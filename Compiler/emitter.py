"""
NPU program emitter — ping-pong buffer model.

Feature maps live entirely in the 4 MiB SRAM and ping-pong between layers;
the hardware Ping-Pong Controller streams them through the 64 KiB I/O Map
Buffers automatically, so the compiler emits NO per-layer activation DMA.

Per layer the emitter produces:
    DMA_LD  weights   (DRAM -> SRAM weight-staging slot)
    CONFIG            (dimensions + requant shift)
    CONV / POOL / ADD (operates on SRAM addresses)

Data movement is emitted only at the program edges and for spills:
    - input image          : one DMA_LD  (DRAM -> SRAM)
    - backbone outputs      : one DMA_ST each for P3 / P4 / P5 (SRAM -> DRAM)

Liveness is computed over the *full* graph so the three multi-scale outputs
(feature maps consumed by the neck) are detected and written back to DRAM
instead of being freed.
"""
import tvm
import tvm.relay as relay
import numpy as np

from utils    import get_tensor_shape, scale_to_shift
from analyzer import UniversalLayerAnalyzer
from mapping  import HW, ConvShape, compute_mapping
from memory   import (BumpAllocator, PoolAllocator,
                      DRAM_INPUT_BASE, DRAM_OUTPUT_BASE, DRAM_OUTPUT_SIZE,
                      DRAM_WEIGHT_BASE, DRAM_WEIGHT_SIZE,
                      SRAM_ACT_BASE, SRAM_ACT_SIZE,
                      SRAM_WSTAGE_BASE, SRAM_WSTAGE_SLOT)

# Ops whose result simply aliases their first argument's buffer.
_PASSTHROUGH = frozenset({
    "reshape", "qnn.requantize", "cast", "clip", "transpose",
    "qnn.sigmoid", "qnn.mul", "squeeze", "expand_dims",
    "qnn.quantize", "qnn.dequantize", "nn.relu", "relu",
})

# Ops a producer-search recurses through (passthrough + slicing).
_TRANSPARENT = _PASSTHROUGH | {"split", "strided_slice"}

# FLAGS bit 3: a per-output-channel int32 bias follows the weights.
_FLAG_BIAS = 0x8


def _chw(shape):
    """Extract (C, H, W) from an NCHW-ish shape; scalar-safe."""
    if len(shape) >= 4: return shape[1], shape[2], shape[3]
    if len(shape) == 3: return shape[0], shape[1], shape[2]
    if len(shape) == 2: return shape[1], 1, 1
    if len(shape) == 1: return shape[0], 1, 1
    return 1, 1, 1


class NPUFullProgramEmitter:
    def __init__(self, params_dict):
        self.params_dict   = params_dict
        self.instructions  = []
        self.pc_counter    = 0
        self.memory_map    = {}                       # relay node -> SRAM address
        self.buffers       = {}                       # producer -> (sram_addr, size)
        self.fmap_alloc    = PoolAllocator(SRAM_ACT_BASE, SRAM_ACT_SIZE, "SRAM activation")
        self.weight_alloc  = BumpAllocator(DRAM_WEIGHT_BASE, DRAM_WEIGHT_SIZE, "DRAM weight")
        self.output_alloc  = BumpAllocator(DRAM_OUTPUT_BASE, DRAM_OUTPUT_SIZE, "DRAM output")
        self.weight_memory = bytearray(DRAM_WEIGHT_SIZE)
        self.cpu_op_names  = set()
        self.cpu_tasks     = []
        self._wslot        = 0                        # weight-staging double buffer
        self.hw            = HW()                     # Eyeriss array parameters
        self.mappings      = []                       # [(conv call, LayerMapping)]

    # Low-level helpers.

    def _inst(self, text):
        pc = self.pc_counter
        self.instructions.append(text)
        self.pc_counter += 1
        return pc

    def _store_conv_params(self, w_np, bias_np):
        """Pack [int8 weights][int32 bias] contiguously into DRAM.

        Returns (dram_addr, total_bytes, has_bias). The NPU finds the bias
        at  WGT + OUT_C*IN_C*K*K.
        """
        blob = bytearray(w_np.astype(np.int8).tobytes())
        has_bias = bias_np is not None
        if has_bias:
            blob += bias_np.astype(np.int32).tobytes()
        addr = self.weight_alloc.alloc(len(blob))
        off  = addr - DRAM_WEIGHT_BASE
        self.weight_memory[off:off + len(blob)] = bytes(blob)
        return addr, len(blob), has_bias

    def _weight_np(self, node):
        if isinstance(node, relay.Constant):
            return node.data.numpy()
        if isinstance(node, relay.Var) and node.name_hint in self.params_dict:
            return self.params_dict[node.name_hint].numpy()
        return None

    @staticmethod
    def _unwrap(call, targets):
        """Descend through wrapper ops until a node in *targets* is reached."""
        node = call.args[0]
        while isinstance(node, relay.Call) and node.op.name not in targets:
            node = node.args[0]
        return node

    def _add_node(self, call):
        """Return the qnn.add / add node of a FUSED_QNN_ADD entry."""
        if call.op.name in ("qnn.add", "add"):
            return call
        return self._unwrap(call, ("qnn.add", "add"))

    def _find_bias(self, call, conv):
        """Locate the conv-block bias constant between *call* and *conv*."""
        node = call.args[0]
        while isinstance(node, relay.Call) and node is not conv:
            if node.op.name == "nn.bias_add":
                b = self._weight_np(node.args[1])
                if b is not None:
                    return b
            if not node.args:
                break
            node = node.args[0]
        return None

    def _wstage(self):
        """Return the next weight-staging SRAM slot (double-buffered)."""
        slot = SRAM_WSTAGE_BASE + self._wslot * SRAM_WSTAGE_SLOT
        self._wslot ^= 1
        return slot

    # Address resolution.

    def _resolve(self, node):
        """Return the SRAM byte address that *node* refers to."""
        if node in self.memory_map:
            return self.memory_map[node]
        if isinstance(node, relay.TupleGetItem):
            base = self._resolve(node.tuple_value)
            return base + self._split_offset(node.tuple_value, node.index)
        if isinstance(node, relay.Call):
            name = node.op.name
            if name == "strided_slice":
                return self._resolve(node.args[0]) + self._sslice_offset(node)
            if name in _PASSTHROUGH and node.args:
                return self._resolve(node.args[0])
            if name == "split" and node.args:
                return self._resolve(node.args[0])
        return SRAM_ACT_BASE

    def _split_offset(self, split_node, index):
        """Byte offset of split slice *index* (channel split, NCHW => contiguous)."""
        if not (isinstance(split_node, relay.Call)
                and split_node.op.name == "split"):
            return 0
        in_shape = get_tensor_shape(split_node.args[0].checked_type)
        if len(in_shape) < 4 or int(split_node.attrs.axis) != 1:
            return 0
        c, h, w  = _chw(in_shape)
        sections = split_node.attrs.indices_or_sections
        try:
            c_start = index * (c // int(sections))
        except TypeError:
            points  = [0] + [int(x) for x in sections]
            c_start = points[index]
        return c_start * h * w

    def _sslice_offset(self, node):
        """Byte offset of a channel-axis strided_slice (NCHW)."""
        in_shape = get_tensor_shape(node.args[0].checked_type)
        if len(in_shape) < 4:
            return 0
        _, h, w = _chw(in_shape)
        begin = [int(x) for x in node.attrs.begin]
        return (begin[1] if len(begin) > 1 else 0) * h * w

    # Liveness analysis.

    def _input_nodes(self, label, call):
        """Feature-map input nodes consumed by an operation."""
        if label == "FUSED_QNN_CONV":
            return [self._unwrap(call, ("qnn.conv2d", "nn.conv2d")).args[0]]
        if label == "FUSED_QNN_ADD":
            add = self._add_node(call)
            return [add.args[0], add.args[1]]
        if label == "CONCAT":
            tup = call.args[0]
            return list(tup.fields) if isinstance(tup, relay.Tuple) else [tup]
        return list(call.args[:1])                      # POOL, OTHER

    def _compute_liveness(self, ops, params, boundary):
        """
        Return (last_full, last_bb, prod_idx):
          last_full[prod] – index of the last consumer over the WHOLE graph
          last_bb[prod]   – index of the last consumer within the backbone
          prod_idx[prod]  – index at which the producer was emitted
        """
        producer  = {}
        prod_idx  = {}
        last_full = {}
        last_bb   = {}
        for p in params:
            producer[p] = p
            prod_idx[p] = -1

        def prod_of(node):
            if node in producer:
                return producer[node]
            if isinstance(node, relay.TupleGetItem):
                return prod_of(node.tuple_value)
            if isinstance(node, relay.Call) and node.args \
               and node.op.name in _TRANSPARENT:
                return prod_of(node.args[0])
            return None

        for idx, (label, call, _) in enumerate(ops):
            if label == "IGNORE":
                if call.args:
                    p = prod_of(call.args[0])
                    if p is not None:
                        producer[call] = p
                continue
            for arg in self._input_nodes(label, call):
                p = prod_of(arg)
                if p is not None:
                    last_full[p] = idx
                    if idx < boundary:
                        last_bb[p] = idx
            producer[call] = call
            prod_idx[call] = idx
        return last_full, last_bb, prod_idx

    # Main pass.

    def visit(self, expr):
        analyzer = UniversalLayerAnalyzer()
        analyzer.visit(expr)
        ops      = analyzer.ops_to_emit
        boundary = analyzer.neck_start if analyzer.neck_start is not None else len(ops)
        params   = list(getattr(expr, "params", []))

        last_full, last_bb, prod_idx = self._compute_liveness(ops, params, boundary)

        # Classify every producer: normal (freed) vs backbone output (spilled).
        free_at, spill_at = {}, {}
        for prod, pidx in prod_idx.items():
            gl = last_full.get(prod)
            if gl is not None and gl < boundary:
                free_at.setdefault(gl, []).append(prod)
            else:
                # consumed only by the neck (or unconsumed) => backbone output
                when = last_bb.get(prod, pidx)
                spill_at.setdefault(when, []).append(prod)

        # Load graph inputs (the image): DRAM -> SRAM.
        in_alloc = BumpAllocator(DRAM_INPUT_BASE,
                                 DRAM_OUTPUT_BASE - DRAM_INPUT_BASE, "DRAM input")
        for p in params:
            try:
                c, h, w = _chw(get_tensor_shape(p.checked_type))
            except Exception:
                continue
            size = c * h * w
            sram = self.fmap_alloc.alloc(size)
            dram = in_alloc.alloc(size)
            self.memory_map[p] = sram
            self.buffers[p]    = (sram, size)
            self._inst(f"OP:DMA_LD | DRAM:0x{dram:08X} | SRAM:0x{sram:08X} | "
                       f"SIZE:0x{size:08X}")

        dispatch = {
            "FUSED_QNN_CONV": self._emit_conv,
            "FUSED_QNN_ADD":  self._emit_add,
            "POOL":           self._emit_pool,
            "CONCAT":         self._emit_concat,
            "OTHER":          self._emit_other,
        }

        # Emit the backbone.
        for idx in range(boundary):
            label, call, flags = ops[idx]
            if label == "IGNORE":
                if call.args:
                    self.memory_map[call] = self._resolve(call.args[0])
                continue
            dispatch[label](call, flags)

            # free feature maps whose last (whole-graph) consumer was this op
            for prod in free_at.get(idx, []):
                if prod in self.buffers:
                    a, s = self.buffers.pop(prod)
                    self.fmap_alloc.release(a, s)

            # backbone outputs: write back to DRAM, then free the SRAM copy
            for prod in spill_at.get(idx, []):
                if prod in self.buffers:
                    a, s = self.buffers.pop(prod)
                    dram = self.output_alloc.alloc(s)
                    self._inst(f"OP:DMA_ST | DRAM:0x{dram:08X} | "
                               f"SRAM:0x{a:08X} | SIZE:0x{s:08X}")
                    self.fmap_alloc.release(a, s)

    # Per-operation emitters.

    def _emit_conv(self, call, flags):
        conv = self._unwrap(call, ("qnn.conv2d", "nn.conv2d"))

        in_node = conv.args[0]
        in_sram = self._resolve(in_node)
        in_c, in_h, in_w   = _chw(get_tensor_shape(in_node.checked_type))
        out_c, out_h, out_w = _chw(get_tensor_shape(call.checked_type))

        w_np = self._weight_np(conv.args[1])
        if w_np is None:
            raise ValueError("conv2d weight not found in params dict")
        bias_np = self._find_bias(call, conv)
        wgt_dram, wgt_bytes, has_bias = self._store_conv_params(w_np, bias_np)
        if has_bias:
            flags |= _FLAG_BIAS

        in_scale  = call.args[1].data.numpy().item()
        out_scale = call.args[3].data.numpy().item()
        shift     = scale_to_shift(in_scale, out_scale)

        attrs  = conv.attrs
        stride = int(attrs.strides[0])     if hasattr(attrs, "strides")     else 1
        pad    = int(attrs.padding[0])     if hasattr(attrs, "padding")     else 0
        kernel = int(attrs.kernel_size[0]) if hasattr(attrs, "kernel_size") else 1

        # Eyeriss Row-Stationary mapping for this conv layer
        lm = compute_mapping(ConvShape(H=in_h, W=in_w, E=out_h, F=out_w,
                                       C=in_c, M=out_c, U=stride,
                                       R=kernel, P=pad), self.hw)
        self.mappings.append((call, lm))

        out_size = out_c * out_h * out_w
        out_sram = self.fmap_alloc.alloc(out_size)
        self.memory_map[call] = out_sram
        self.buffers[call]    = (out_sram, out_size)

        w_sram = self._wstage()
        self._inst(f"OP:DMA_LD | DRAM:0x{wgt_dram:08X} | SRAM:0x{w_sram:08X} | "
                   f"SIZE:0x{wgt_bytes:08X}")
        self._inst(f"OP:CONFIG | IN_H:{in_h} | IN_W:{in_w} | IN_C:{in_c} | "
                   f"OUT_C:{out_c} | STRIDE:{stride} | "
                   f"PCFG:0x{lm.pe_config:03X} | SHIFT:0x{shift:02X}")
        self._inst(f"OP:CONV   | IN:0x{in_sram:08X} | WGT:0x{w_sram:08X} | "
                   f"OUT:0x{out_sram:08X} | FLAGS:0x{flags:X} | "
                   f"STRIDE:{stride} | PAD:{pad} | KERNEL:{kernel}")

    def _emit_pool(self, call, flags):
        in_node = call.args[0]
        in_sram = self._resolve(in_node)
        in_c, in_h, in_w   = _chw(get_tensor_shape(in_node.checked_type))
        out_c, out_h, out_w = _chw(get_tensor_shape(call.checked_type))

        attrs  = call.attrs
        kernel = int(attrs.pool_size[0]) if hasattr(attrs, "pool_size") else 2
        stride = int(attrs.strides[0])   if hasattr(attrs, "strides")   else kernel
        pad    = int(attrs.padding[0])   if hasattr(attrs, "padding")   else 0

        out_size = out_c * out_h * out_w
        out_sram = self.fmap_alloc.alloc(out_size)
        self.memory_map[call] = out_sram
        self.buffers[call]    = (out_sram, out_size)

        self._inst(f"OP:CONFIG | IN_H:{in_h} | IN_W:{in_w} | IN_C:{in_c} | "
                   f"OUT_C:{out_c} | STRIDE:{stride} | SHIFT:0x00")
        self._inst(f"OP:POOL   | IN:0x{in_sram:08X} | WGT:0x00000000 | "
                   f"OUT:0x{out_sram:08X} | FLAGS:0x{flags:X} | "
                   f"STRIDE:{stride} | PAD:{pad} | KERNEL:{kernel}")

    def _emit_add(self, call, flags):
        add = self._add_node(call)

        a_sram = self._resolve(add.args[0])
        b_sram = self._resolve(add.args[1])
        in_c, in_h, in_w   = _chw(get_tensor_shape(add.args[0].checked_type))
        out_c, out_h, out_w = _chw(get_tensor_shape(call.checked_type))

        # qnn.add args: lhs, rhs, lhs_scale, lhs_zp, rhs_scale, rhs_zp,
        #               out_scale, out_zp  — each operand rescaled by a shift.
        lhs_shift = rhs_shift = 0
        if add.op.name == "qnn.add" and len(add.args) >= 7:
            try:
                lhs_s = add.args[2].data.numpy().item()
                rhs_s = add.args[4].data.numpy().item()
                out_s = add.args[6].data.numpy().item()
                lhs_shift = scale_to_shift(lhs_s, out_s)
                rhs_shift = scale_to_shift(rhs_s, out_s)
            except Exception:
                pass

        out_size = out_c * out_h * out_w
        out_sram = self.fmap_alloc.alloc(out_size)
        self.memory_map[call] = out_sram
        self.buffers[call]    = (out_sram, out_size)

        self._inst(f"OP:ADDCFG | LHS:0x{lhs_shift:02X} | RHS:0x{rhs_shift:02X}")
        self._inst(f"OP:CONFIG | IN_H:{in_h} | IN_W:{in_w} | IN_C:{in_c} | "
                   f"OUT_C:{out_c} | STRIDE:1 | SHIFT:0x00")
        self._inst(f"OP:ADD    | IN:0x{a_sram:08X} | WGT:0x{b_sram:08X} | "
                   f"OUT:0x{out_sram:08X} | FLAGS:0x{flags:X} | "
                   f"STRIDE:1 | PAD:0 | KERNEL:1")

    def _emit_concat(self, call, flags):
        """Concatenation realised as SRAM-to-SRAM block moves: each input is
        copied into its channel slice of the output (NCHW => contiguous)."""
        tup    = call.args[0]
        fields = list(tup.fields) if isinstance(tup, relay.Tuple) else [tup]
        out_c, out_h, out_w = _chw(get_tensor_shape(call.checked_type))

        out_size = out_c * out_h * out_w
        out_sram = self.fmap_alloc.alloc(out_size)
        self.memory_map[call] = out_sram
        self.buffers[call]    = (out_sram, out_size)

        cur = out_sram
        for f in fields:
            c, h, w = _chw(get_tensor_shape(f.checked_type))
            src     = self._resolve(f)
            size    = c * h * w
            self._inst(f"OP:DMA_LD | DRAM:0x{src:08X} | SRAM:0x{cur:08X} | "
                       f"SIZE:0x{size:08X}")
            cur += size

    def _emit_other(self, call, flags):
        """CPU fallback trap (rare inside the backbone)."""
        in_node = call.args[0] if call.args else None
        if in_node is not None:
            in_sram = self._resolve(in_node)
            in_c, in_h, in_w = _chw(get_tensor_shape(in_node.checked_type))
        else:
            in_sram, in_c, in_h, in_w = SRAM_ACT_BASE, 1, 1, 1

        out_c, out_h, out_w = _chw(get_tensor_shape(call.checked_type))
        out_size = out_c * out_h * out_w
        out_sram = self.fmap_alloc.alloc(out_size)
        self.memory_map[call] = out_sram
        self.buffers[call]    = (out_sram, out_size)

        op_name = getattr(call.op, "name", "unknown")
        self.cpu_op_names.add(op_name)
        pc = self._inst(f"OP:OTHER  | IN:0x{in_sram:08X} | WGT:0x00000000 | "
                        f"OUT:0x{out_sram:08X} | FLAGS:0x0 | "
                        f"STRIDE:1 | PAD:0 | KERNEL:1")
        self.cpu_tasks.append(
            f"    elif interrupt_pc == {pc}:\n"
            f"        cpu_execute_{op_name.replace('.', '_')}"
            f"(sram, 0x{in_sram:08X}, 0x{out_sram:08X}, "
            f"{in_h}, {in_w}, {in_c})\n"
        )
