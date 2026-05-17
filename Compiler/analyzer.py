import tvm
import tvm.relay as relay

# Activation flag bits encoded in the FLAGS field of each instruction
FLAG_SIGMOID  = 0x1   # sigmoid / SiLU gate
FLAG_MULTIPLY = 0x2   # element-wise multiply / SiLU combine
FLAG_RELU     = 0x4   # ReLU / clip


class UniversalLayerAnalyzer(relay.ExprVisitor):
    """
    Walk the *full* Relay graph (backbone + neck + head) and build a flat list
    of [label, call_node, activation_flags] entries.

    The whole graph is analysed so that the emitter's liveness pass can see
    every consumer — including neck consumers of the backbone's multi-scale
    outputs. `neck_start` records the ops_to_emit index of the first neck op
    (the first upsample); the emitter emits only ops[:neck_start].

    Labels
    ------
    FUSED_QNN_CONV  – qnn.conv2d committed by a requantize (+ activations)
    FUSED_QNN_ADD   – qnn.add (residual shortcut)
    POOL            – nn.max_pool2d
    CONCAT          – concatenate
    OTHER           – CPU fallback
    IGNORE          – passthrough / wrapper op (no instruction emitted)

    Activation ops are attached *retroactively* to the conv/pool they follow.
    """

    _NECK_START_OP = "image.resize2d"      # first upsample => start of the neck

    _ACTIVATION_OPS = {
        "sigmoid":    FLAG_SIGMOID,  "qnn.sigmoid": FLAG_SIGMOID,
        "multiply":   FLAG_MULTIPLY, "qnn.mul":     FLAG_MULTIPLY,
        "nn.relu":    FLAG_RELU,     "relu":        FLAG_RELU,  "clip": FLAG_RELU,
    }

    # qnn.add is NOT here — it is the residual shortcut and is emitted.
    # plain `add` IS here — it is the int32 bias add inside a conv block.
    _IGNORE_OPS = frozenset({
        "qnn.conv2d", "nn.conv2d", "nn.bias_add",
        "add",
        "qnn.quantize", "qnn.dequantize",
        "cast", "right_shift",
        "reshape", "split", "strided_slice",
        "transpose", "squeeze", "expand_dims",
    })

    def __init__(self):
        super().__init__()
        self.ops_to_emit  = []
        self.neck_start   = None      # index of the first neck op, or None
        self._flag_target = None      # last CONV/POOL entry, for retro flags

    @staticmethod
    def _find_core_op(node):
        """Unwrap bias / activation wrappers and return the underlying conv name."""
        if not isinstance(node, relay.Call):
            return None
        name = node.op.name
        if name in ("qnn.conv2d", "nn.conv2d"):
            return name
        if name in ("nn.bias_add", "qnn.mul", "qnn.sigmoid",
                    "clip", "nn.relu", "multiply", "sigmoid"):
            return UniversalLayerAnalyzer._find_core_op(node.args[0])
        return None

    def visit_call(self, call):
        super().visit_call(call)
        if not isinstance(call.op, tvm.ir.Op):
            return

        op_name = call.op.name

        # Record where the neck begins (first upsample) — first occurrence only.
        if op_name == self._NECK_START_OP and self.neck_start is None:
            self.neck_start = len(self.ops_to_emit)

        # Activation op — attach retroactively to the conv/pool it follows.
        if op_name in self._ACTIVATION_OPS:
            if self._flag_target is not None:
                self._flag_target[2] |= self._ACTIVATION_OPS[op_name]
            self.ops_to_emit.append(["IGNORE", call, 0])
            return

        # Quantized element-wise add = residual shortcut (carries its scales).
        if op_name == "qnn.add":
            self.ops_to_emit.append(["FUSED_QNN_ADD", call, 0])
            self._flag_target = None
            return

        # qnn.requantize commits a fused conv block.
        if op_name == "qnn.requantize":
            core = self._find_core_op(call.args[0])
            if core in ("qnn.conv2d", "nn.conv2d"):
                entry = ["FUSED_QNN_CONV", call, 0]
                self.ops_to_emit.append(entry)
                self._flag_target = entry
            else:
                self.ops_to_emit.append(["IGNORE", call, 0])
            return

        if op_name in self._IGNORE_OPS:
            self.ops_to_emit.append(["IGNORE", call, 0])
            return

        if op_name == "nn.max_pool2d":
            entry = ["POOL", call, 0]
            self.ops_to_emit.append(entry)
            self._flag_target = entry
            return

        if "concatenate" in op_name:
            self.ops_to_emit.append(["CONCAT", call, 0])
            self._flag_target = None
            return

        # Anything else is a CPU fallback.
        self.ops_to_emit.append(["OTHER", call, 0])
        self._flag_target = None
