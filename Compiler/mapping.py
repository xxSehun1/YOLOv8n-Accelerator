"""
mapping.py — Eyeriss Row-Stationary mapping pass.

For each convolution layer this module computes:
  - the Eyeriss mapping parameters (m, n, e, p, q, r, t)
  - PE_CONFIG  : the per-PE configuration word
  - LN_CONFIG  : the psum-chain (line) configuration
  - PE_EN      : the per-PE enable mask
  - the GIN/GON XID/YID scan-chain configuration for filter / ifmap /
    ipsum / opsum
  - a cost estimate (PE-array passes) used to rank candidate mappings

    filter XID = kernel-row index (row % R)      filter YID = PE-set (row // R)
    ifmap  XID = col + (row % R)   [diagonal]    ifmap  YID = 0 (broadcast)
    ipsum  XID = col at a set's entry row        else DEFAULT
    opsum  XID = col at a set's exit  row        else DEFAULT
    LN     : chain the R rows of each PE set, break at the set boundary

"""
from dataclasses import dataclass, field

FILT_R         = 3      # physical PE-set depth; a 1x1 conv runs as a 3x3
PSUM_DATA_SIZE = 4      # bytes per PSUM entry (from lab-2 eyeriss.py)


# Hardware parameters (must match define.svh).
@dataclass
class HW:
    pe_h:        int = 16     # NUMS_PE_ROW
    pe_w:        int = 16     # NUMS_PE_COL
    ifmap_spad:  int = 12
    filter_spad: int = 48
    psum_spad:   int = 16
    xid_bits:    int = 5
    yid_bits:    int = 5      # 16 rows need >= 5 bits (16 IDs + a free DEFAULT)

    @property
    def default_xid(self): return (1 << self.xid_bits) - 1
    @property
    def default_yid(self): return (1 << self.yid_bits) - 1


# Convolution shape.
@dataclass
class ConvShape:
    H: int          # input height
    W: int          # input width
    E: int          # output height
    F: int          # output width
    C: int          # input channels
    M: int          # output channels
    U: int = 1      # stride
    R: int = 3      # conv kernel size (filter height/width)
    P: int = 1      # padding


# Result.
OFMAP_COL_BITS = 5      # PE_CONFIG OFMAP_COL field width -> strip <= 32


def _strip_width(F, max_w=(1 << OFMAP_COL_BITS)):
    """Largest output-row strip width <= max_w that divides F.

    A wide output row is processed in strips so that OFMAP_COL fits the
    5-bit PE_CONFIG field; the controller iterates ceil(F / strip) strips.
    When F has no divisor <= max_w (e.g. a large prime) we fall back to
    max_w and let the controller run a short tail strip.
    """
    for d in range(min(F, max_w), 0, -1):
        if F % d == 0:
            return d
    return min(F, max_w)


@dataclass
class LayerMapping:
    m: int; n: int; e: int; p: int; q: int; r: int; t: int
    pe_config:   int
    ln_config:   int
    pe_en:       int
    ofmap_strip: int = 0      # output columns processed per strip
    n_strips:    int = 1      # number of strips to cover the full row
    cost:        int = 0      # estimated PE-array passes (lower is better)
    util:        float = 0.0  # PE-array utilisation of the chosen mapping
    filter_xid: list = field(default_factory=list)
    filter_yid: list = field(default_factory=list)
    ifmap_xid:  list = field(default_factory=list)
    ifmap_yid:  list = field(default_factory=list)
    ipsum_xid:  list = field(default_factory=list)
    ipsum_yid:  list = field(default_factory=list)
    opsum_xid:  list = field(default_factory=list)
    opsum_yid:  list = field(default_factory=list)
    valid:      bool = True


# Mapping search.
def _candidates(conv, hw):
    """Yield every structurally valid (m, n, e, p, q, r, t) mapping.

    Structural constraints (from lab-2 EyerissMapper / Eyeriss RS dataflow):
      - r * t * e == base, where base = (usable PEs) / R
      - e is a PE-column multiple, half a column, or the full output height
      - p * q <= filter_spad / R          (filter scratchpad capacity)
      - q <= ifmap_spad / R               (ifmap scratchpad capacity)
      - p <= psum_spad / PSUM_DATA_SIZE   (psum scratchpad capacity)
      - m is a divisor of M and a multiple of p
    """
    R     = FILT_R
    eff_h = (hw.pe_h // R) * R          # rows usable as whole PE sets
    sets  = eff_h // R
    n_pe  = eff_h * hw.pe_w
    base  = n_pe // R                   # r * t * e must equal this

    p_max  = hw.psum_spad // PSUM_DATA_SIZE
    q_max  = hw.ifmap_spad // R
    m_list = [m for m in range(1, conv.M + 1) if conv.M % m == 0]
    e_max  = min(hw.pe_w * sets, conv.E)

    for e in range(e_max, 0, -1):
        if not (e % hw.pe_w == 0 or e == hw.pe_w // 2 or e == conv.E):
            continue
        if base % e != 0:
            continue
        rt = base // e
        for r in range(1, sets + 1):
            if rt % r != 0:
                continue
            t = rt // r
            for p in range(1, p_max + 1):
                for q in range(1, q_max + 1):
                    if p * q > hw.filter_spad // R:
                        continue
                    for m in m_list:
                        if m % p == 0:
                            yield (m, 1, e, p, q, r, t)


def _evaluate(mapping, conv, hw):
    """Score a candidate mapping. Returns (cost, util); lower cost is better.

    cost  ~ number of PE-array passes needed to finish the layer:
              ofmap-channel passes  = ceil(M / m)
              ifmap-channel passes  = ceil(C / q)
              ofmap-row    passes   = ceil(E / e)
              row-strip    passes   = n_strips (wide-row tiling)
    util  ~ fraction of the 16x16 PE array kept busy by this mapping.
    """
    m, n, e, p, q, r, t = mapping
    R = FILT_R

    strip    = _strip_width(conv.F)
    n_strips = max(1, -(-conv.F // strip))         # ceil

    ch_passes  = -(-conv.C // q)                   # ceil(C / q)
    out_passes = -(-conv.M // m)                   # ceil(M / m)
    row_passes = -(-conv.E // e)                   # ceil(E / e)
    cost = ch_passes * out_passes * row_passes * n_strips

    used_pe = min(e, hw.pe_w) * (r * R)
    util    = used_pe / float(hw.pe_h * hw.pe_w)

    return cost, util


# Scan-chain / LN / PE_EN generation (geometric).
def _gen_config(hw):
    """Geometric GIN/GON scan chains — identical for every conv layer.

    These depend only on the PE-array geometry, so they are computed once
    and scanned into the hardware at startup. Stride is *not* baked in
    here: the controller applies the stride when it walks the ifmap, so
    the diagonal ifmap-XID pattern stays the same for every layer.
    """
    R       = FILT_R
    H, W    = hw.pe_h, hw.pe_w
    sets    = H // R
    DX, DY  = hw.default_xid, hw.default_yid

    fx = []; fy = []; ix = []; iy = []
    px = []; py = []; ox = []; oy = []
    for row in range(H):
        s        = row // R
        kr       = row % R
        in_set   = s < sets
        entry    = in_set and kr == 0
        exit_    = in_set and kr == R - 1
        fy.append(s if in_set else DY)
        iy.append(0)
        py.append(s if entry else DY)
        oy.append(s if exit_ else DY)
        for col in range(W):
            fx.append(kr  if in_set else DX)
            ix.append(col + kr)
            px.append(col if entry else DX)
            ox.append(col if exit_ else DX)

    # LN: chain the R rows of each set; break at the set boundary
    ln = 0
    for row in range(H - 1):
        if (row // R) < sets and (row % R) != R - 1:
            ln |= (1 << row)

    # PE_EN: enable every PE in a complete set
    pe_en = (1 << (sets * R * W)) - 1

    return dict(filter_xid=fx, filter_yid=fy, ifmap_xid=ix, ifmap_yid=iy,
                ipsum_xid=px,  ipsum_yid=py,  opsum_xid=ox,  opsum_yid=oy,
                ln_config=ln,  pe_en=pe_en)


# Public entry point.
def compute_mapping(conv: ConvShape, hw: HW = None) -> LayerMapping:
    """Compute the full Eyeriss mapping + hardware config for one conv layer.

    Enumerates every structurally valid mapping and keeps the one with the
    lowest estimated pass count (ties broken by higher PE utilisation). If
    no mapping validates, returns a minimal fallback flagged valid=False.
    """
    hw = hw or HW()

    best = None                                    # ((cost, -util), mapping)
    for cand in _candidates(conv, hw):
        cost, util = _evaluate(cand, conv, hw)
        key = (cost, -util)
        if best is None or key < best[0]:
            best = (key, cand, cost, util)

    if best is not None:
        _, (m, n, e, p, q, r, t), cost, util = best
        valid = True
    else:
        # fallback: minimal mapping that always validates structurally
        m, n, e, p, q, r, t = 1, 1, min(hw.pe_w, conv.E), 1, 1, 1, 1
        cost, util, valid = 0, 0.0, False

    # The output row is processed in strips so OFMAP_COL fits its 5-bit field.
    strip    = _strip_width(conv.F)
    n_strips = max(1, -(-conv.F // strip))

    # PE_CONFIG = (p-1)<<7 | (strip-1)<<2 | (q-1)   (lab-3 config_PE_array.h);
    # OFMAP_COL holds the per-strip width, not the full output width.
    pe_config = ((p - 1) << 7) | ((strip - 1) << 2) | (q - 1)

    cfg = _gen_config(hw)
    return LayerMapping(
        m=m, n=n, e=e, p=p, q=q, r=r, t=t,
        pe_config=pe_config, ln_config=cfg["ln_config"], pe_en=cfg["pe_en"],
        ofmap_strip=strip, n_strips=n_strips, cost=cost, util=util,
        filter_xid=cfg["filter_xid"], filter_yid=cfg["filter_yid"],
        ifmap_xid=cfg["ifmap_xid"],   ifmap_yid=cfg["ifmap_yid"],
        ipsum_xid=cfg["ipsum_xid"],   ipsum_yid=cfg["ipsum_yid"],
        opsum_xid=cfg["opsum_xid"],   opsum_yid=cfg["opsum_yid"],
        valid=valid,
    )
