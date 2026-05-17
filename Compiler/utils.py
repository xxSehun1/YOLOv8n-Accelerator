import struct
import math

def get_tensor_shape(checked_type):
    """Return a list of ints from a Relay checked type (scalar-safe)."""
    if checked_type is None:
        return [1, 1, 1, 1]
    if hasattr(checked_type, "shape"):
        return [int(d) for d in checked_type.shape]
    if hasattr(checked_type, "fields"):
        return [int(d) for d in checked_type.fields[0].shape]
    return [1, 1, 1, 1]

def float_to_int32_bits(f):
    """Reinterpret a Python float as its IEEE 754 single-precision bit pattern."""
    return struct.unpack('<I', struct.pack('<f', f))[0]

def align_up(value, alignment):
    """Round *value* up to the next multiple of *alignment* (must be power-of-2)."""
    return (value + alignment - 1) & ~(alignment - 1)

def scale_to_shift(in_scale, out_scale, max_shift=63):
    """
    Express requantisation as a power-of-2 arithmetic right shift, matching
    the hardware PostQuant unit (out_q = accumulator >>> shift).

        out_q = in_q * (in_scale / out_scale) ≈ in_q >> shift
        =>  shift = round(log2(out_scale / in_scale))

    Returns the shift clamped to the 6-bit hardware field range [0, 63].
    """
    if in_scale <= 0.0 or out_scale <= 0.0:
        return 0
    shift = round(math.log2(out_scale / in_scale))
    return max(0, min(shift, max_shift))
