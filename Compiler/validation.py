"""
validation.py — numerical verification of the compiler.

Usage:  make valid
"""
import numpy as np
import onnx
import tvm
import tvm.relay as relay
import hashlib
from datetime import date
from pathlib import Path

from analyzer import UniversalLayerAnalyzer
from emitter  import NPUFullProgramEmitter, _chw, _PASSTHROUGH
from utils    import get_tensor_shape, scale_to_shift
from npu_iss  import NPU_ISS, conv_int8, pool_max, add_int8, ZP

MODEL  = "../Model/train/weights/best_int8.onnx"
INSTRS = "../Build/full_instructions.txt"
WEIGHTS = "../Build/weights.bin"
BUILD = Path("../Build")

GOLDEN_OUTPUTS = [
    {
        "name": "P3",
        "file": "golden_p3.bin",
        "layer": 15,
        "op": "CONV",
        "shape": (64, 80, 80),
        "dram": 0x003F4000,
        "isa_line": 61,
        "store_line": 65,
    },
    {
        "name": "P4",
        "file": "golden_p4.bin",
        "layer": 24,
        "op": "CONV",
        "shape": (128, 40, 40),
        "dram": 0x004BC000,
        "isa_line": 96,
        "store_line": 100,
    },
    {
        "name": "P5",
        "file": "golden_p5.bin",
        "layer": 35,
        "op": "CONV",
        "shape": (256, 20, 20),
        "dram": 0x00545800,
        "isa_line": 140,
        "store_line": 141,
    },
]


# Golden: execute the correct graph with the ISS kernels.

class GoldenRunner:
    def __init__(self, params, input_image):
        self.params  = params                 # name -> tvm NDArray
        self.values  = {}                     # relay node -> uint8 (C,H,W)
        self.image   = input_image            # uint8 (C,H,W)
        self.results = []                     # (op, ndarray) for CONV/POOL/ADD

    # -- resolve a node to its uint8 feature-map array -----------------------
    # -- resolve a node to its uint8 feature-map array -----------------------
    def _arr(self, node):
        if node in self.values:
            return self.values[node]
        if isinstance(node, relay.Var):
            return self.image
            
        # ⬇️ 新增這兩行來處理 TVM 折疊後的常數節點
        if isinstance(node, relay.Constant):
            return node.data.numpy()
            
        if isinstance(node, relay.TupleGetItem):
            parent = self._arr(node.tuple_value)
            return self._split_slice(node.tuple_value, node.index, parent)
        if isinstance(node, relay.Call):
            nm = node.op.name
            if nm == "strided_slice":
                return self._sslice(node, self._arr(node.args[0]))
            if (nm in _PASSTHROUGH or nm == "split") and node.args:
                return self._arr(node.args[0])
        raise RuntimeError(f"golden: cannot resolve {type(node)}")
    
    def _split_slice(self, split_node, index, parent):
        if not (isinstance(split_node, relay.Call)
                and split_node.op.name == "split"):
            return parent
        c = parent.shape[0]
        sec = split_node.attrs.indices_or_sections
        try:
            n = int(sec)
            cp = c // n
            return parent[index * cp:(index + 1) * cp]
        except TypeError:
            pts = [0] + [int(x) for x in sec] + [c]
            return parent[pts[index]:pts[index + 1]]

    def _sslice(self, node, parent):
        begin = [int(x) for x in node.attrs.begin]
        end   = [int(x) for x in node.attrs.end]
        if len(begin) > 1:
            return parent[begin[1]:end[1]]
        return parent

    # -- weight / bias extraction --------------------------------------------
    def _weight_np(self, node):
        if isinstance(node, relay.Constant):
            return node.data.numpy()
        if isinstance(node, relay.Var) and node.name_hint in self.params:
            return self.params[node.name_hint].numpy()
        raise RuntimeError("golden: weight not found")

    def _find_bias(self, call, conv):
        node = call.args[0]
        while isinstance(node, relay.Call) and node is not conv:
            if node.op.name == "nn.bias_add":
                return self._weight_np(node.args[1])
            if not node.args:
                break
            node = node.args[0]
        return None

    # -- execute one op ------------------------------------------------------
    def exec_op(self, label, call, flags):
        if label == "FUSED_QNN_CONV":
            conv = NPUFullProgramEmitter._unwrap(call, ("qnn.conv2d", "nn.conv2d"))
            x = self._arr(conv.args[0]).astype(np.int64) - ZP
            w = self._weight_np(conv.args[1]).astype(np.int8)
            bias_np = self._find_bias(call, conv)
            bias = bias_np.astype(np.int32) if bias_np is not None else None
            in_s  = call.args[1].data.numpy().item()
            out_s = call.args[3].data.numpy().item()
            shift = scale_to_shift(in_s, out_s)
            a = conv.attrs
            stride = int(a.strides[0])     if hasattr(a, "strides")     else 1
            pad    = int(a.padding[0])     if hasattr(a, "padding")     else 0
            y = conv_int8(x, w, bias, stride, pad, shift, flags)
            self.values[call] = y
            self.results.append(("CONV", y))

        elif label == "FUSED_QNN_ADD":
            add = call if call.op.name in ("qnn.add", "add") \
                  else NPUFullProgramEmitter._unwrap(call, ("qnn.add", "add"))
            a_s = self._arr(add.args[0]).astype(np.int64) - ZP
            b_s = self._arr(add.args[1]).astype(np.int64) - ZP
            lhs = rhs = 0
            if add.op.name == "qnn.add" and len(add.args) >= 7:
                lhs = scale_to_shift(add.args[2].data.numpy().item(),
                                     add.args[6].data.numpy().item())
                rhs = scale_to_shift(add.args[4].data.numpy().item(),
                                     add.args[6].data.numpy().item())
            y = add_int8(a_s, b_s, lhs, rhs)
            self.values[call] = y
            self.results.append(("ADD", y))

        elif label == "POOL":
            x = self._arr(call.args[0]).astype(np.int64) - ZP
            a = call.attrs
            k  = int(a.pool_size[0]) if hasattr(a, "pool_size") else 2
            st = int(a.strides[0])   if hasattr(a, "strides")   else k
            pd = int(a.padding[0])   if hasattr(a, "padding")   else 0
            y = pool_max(x, k, st, pd)
            self.values[call] = y
            self.results.append(("POOL", y))

        elif label == "CONCAT":
            tup = call.args[0]
            fields = list(tup.fields) if isinstance(tup, relay.Tuple) else [tup]
            y = np.concatenate([self._arr(f) for f in fields], axis=0)
            self.values[call] = y                    # not a recorded layer


def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _write_frozen_golden(golden_layers, iss_layers):
    BUILD.mkdir(parents=True, exist_ok=True)

    lines = [
        "# YOLOv8n Backbone Frozen Golden Contract",
        "",
        f"Date: {date.today().isoformat()}",
        "Input: fixed random uint8 image generated by numpy default_rng(seed=0), shape=(3,640,640)",
        "Layout: CHW contiguous uint8 feature maps",
        "Zero point: 128",
        "Sign-off scope: P3/P4/P5 backbone outputs after compiler/ISS bit-exact validation",
        "",
        "## Source Artifacts",
        "",
    ]

    for src in (Path(INSTRS), Path(WEIGHTS), BUILD / "npu_program.hex", BUILD / "mapping.txt"):
        lines.append(f"- {src.name}: size={src.stat().st_size} sha256={_sha256(src)}")

    lines += [
        "",
        "## Frozen Outputs",
        "",
    ]

    for spec in GOLDEN_OUTPUTS:
        layer = spec["layer"]
        gop, ga = golden_layers[layer]
        idx, sop, saddr, sa = iss_layers[layer]
        expected_shape = spec["shape"]

        if gop != spec["op"] or sop != spec["op"]:
            raise RuntimeError(f"{spec['name']} layer op mismatch: golden={gop} iss={sop}")
        if ga.shape != expected_shape or sa.shape != expected_shape:
            raise RuntimeError(
                f"{spec['name']} shape mismatch: golden={ga.shape} iss={sa.shape}"
            )
        if not np.array_equal(ga, sa):
            raise RuntimeError(f"{spec['name']} golden/ISS mismatch during freeze")

        out_path = BUILD / spec["file"]
        out_path.write_bytes(ga.astype(np.uint8, copy=False).tobytes(order="C"))
        lines.append(
            f"- {spec['name']}: file={spec['file']} layer=L{layer} "
            f"op={spec['op']} shape={expected_shape} bytes={ga.size} "
            f"compute_isa_line={spec['isa_line']} final_dma_st_line={spec['store_line']} "
            f"final_dram=0x{spec['dram']:08X} sram_out=0x{saddr:08X} "
            f"sha256={_sha256(out_path)}"
        )

    lines += [
        "",
        "## Required Use",
        "",
        "RTL final sign-off must compare byte-for-byte against all three files.",
        "A sequential debug ComputeTop may use these files only as a bring-up reference.",
        "Project completion requires the real systolic/PE datapath to match these outputs.",
        "",
    ]
    (BUILD / "golden_contract.md").write_text("\n".join(lines))
    print("\nFrozen golden contract written:")
    for spec in GOLDEN_OUTPUTS:
        path = BUILD / spec["file"]
        print(f"  {path} size={path.stat().st_size} sha256={_sha256(path)}")
    print(f"  {BUILD / 'golden_contract.md'}")


# Main.

def main():
    print("Loading model and running TVM passes...")
    onnx_model  = onnx.load(MODEL)
    mod, params = relay.frontend.from_onnx(onnx_model, {"images": (1, 3, 640, 640)})
    with tvm.transform.PassContext(opt_level=1):
        mod["main"] = relay.build_module.bind_params_by_name(mod["main"], params)
        mod = relay.transform.InferType()(mod)
        mod = relay.transform.FakeQuantizationToInteger()(mod)
        mod = relay.transform.FoldConstant()(mod)

    analyzer = UniversalLayerAnalyzer()
    analyzer.visit(mod["main"])
    ops      = analyzer.ops_to_emit
    boundary = analyzer.neck_start if analyzer.neck_start is not None else len(ops)

    # identical random input for both sides (matches npu_iss default seed 0)
    rng = np.random.default_rng(0)
    img = rng.integers(0, 256, size=3 * 640 * 640, dtype=np.uint8)

    # Golden.
    print("Computing golden (correct graph + ISS kernels)...")
    golden = GoldenRunner(params, img.reshape(3, 640, 640))
    for idx in range(boundary):
        label, call, flags = ops[idx]
        if label == "IGNORE":
            if call.args:
                golden.values[call] = golden._arr(call.args[0])
            continue
        golden.exec_op(label, call, flags)

    # ISS on the compiled stream.
    print("Running ISS on the compiled instruction stream...")
    instrs  = [ln.strip() for ln in open(INSTRS) if '|' in ln]
    weights = open(WEIGHTS, 'rb').read()
    iss = NPU_ISS(weights)
    iss.run(instrs, img)

    # Compare layer by layer.
    g = golden.results
    s = [(op, arr) for (_, op, _, arr) in iss.layers]
    print(f"\nGolden layers: {len(g)}   ISS layers: {len(s)}")
    if len(g) != len(s):
        print("FAIL — layer count differs (compiler emitted wrong number of ops)")
        return 1

    ok = True
    for i, ((gop, ga), (sop, sa)) in enumerate(zip(g, s)):
        if gop != sop or ga.shape != sa.shape:
            print(f"  L{i:2d} MISMATCH  golden {gop}{ga.shape}  vs  ISS {sop}{sa.shape}")
            ok = False
            break
        diff = np.abs(ga.astype(np.int32) - sa.astype(np.int32))
        ndiff = int((diff != 0).sum())
        if ndiff:
            print(f"  L{i:2d} {gop:5s} MISMATCH  max|diff|={int(diff.max())}  "
                  f"{ndiff}/{ga.size} elements differ")
            ok = False
            break
        print(f"  L{i:2d} {gop:5s} {ga.shape}  match")

    if ok:
        _write_frozen_golden(g, iss.layers)
        print(f"\nPASS — all {len(g)} layers bit-exact. Compiler dataflow verified.")
        return 0
    print(f"\nFAIL — first divergence at L{i}. "
          f"Inspect that op in {INSTRS}.")
    return 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
