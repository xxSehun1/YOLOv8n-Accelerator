"""
Generate shared_config.hex directly from mapping.py's _gen_config(),
without needing a full compiler run or mapping.txt.

Usage:
    python gen_shared_hex_direct.py
    python gen_shared_hex_direct.py --out ../Hardware/NPU/TestBench/shared_config.hex
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mapping import HW, _gen_config

XID_BITS     = 5
YID_BITS     = 5
NUMS_PE_ROW  = 16
NUMS_PE_COL  = 16
NUM_PE       = NUMS_PE_ROW * NUMS_PE_COL


def pack(cfg):
    """Pack XID/YID arrays from _gen_config() into 40-bit hex lines."""
    fields = [
        ("filter_xid", XID_BITS),
        ("filter_xid", XID_BITS),   # placeholder to match packing order below
    ]
    # Correct packing order matches ConfigLoader's ROM layout:
    #   [4:0]   ifmap_XID
    #   [9:5]   filter_XID
    #   [14:10] ipsum_XID
    #   [19:15] opsum_XID
    #   [24:20] ifmap_YID
    #   [29:25] filter_YID
    #   [34:30] ipsum_YID
    #   [39:35] opsum_YID
    order = [
        ("ifmap_xid",  XID_BITS),
        ("filter_xid", XID_BITS),
        ("ipsum_xid",  XID_BITS),
        ("opsum_xid",  XID_BITS),
        ("ifmap_yid",  YID_BITS),
        ("filter_yid", YID_BITS),
        ("ipsum_yid",  YID_BITS),
        ("opsum_yid",  YID_BITS),
    ]

    # _gen_config returns YID per row (16 entries); expand to per-PE.
    expanded = {}
    for name, bits in order:
        lst = cfg[name]
        if len(lst) == NUMS_PE_ROW:
            # YID fields are row-shared; broadcast to all PEs in that row.
            expanded[name] = [lst[i // NUMS_PE_COL] for i in range(NUM_PE)]
        else:
            expanded[name] = list(lst)

    lines = []
    for i in range(NUM_PE):
        packed = 0
        offset = 0
        for name, bits in order:
            v = expanded[name][i] & ((1 << bits) - 1)
            packed |= v << offset
            offset += bits
        lines.append(f"{packed:010x}")
    return lines


def main():
    ap = argparse.ArgumentParser(description="Generate shared_config.hex from mapping geometry.")
    ap.add_argument("--out", default="../Hardware/NPU/TestBench/shared_config.hex")
    args = ap.parse_args()

    hw  = HW()
    # active_sets=1: PingPong_Ctrl v3 uses T_H=T_W=1, so only PE set 0 receives
    # filter data.  Rows beyond set 0 (rows 3-14) must get DEFAULT ifmap/ipsum/
    # opsum XIDs so they never block the GIN while stuck in WEIGHT.
    #
    # active_cols=E=2: the ipsum loop in PingPong_Ctrl covers cnt_p_row=0..E-1,
    # so only the LN chains for PE columns 0 and 1 are activated.  PE columns
    # >= 2 must get DEFAULT ifmap/ipsum/opsum XIDs: without this they receive
    # real ifmap XIDs (2,3,...) during S_IFMAP, get stuck in COMPUTE after the
    # first pass (the LN chain for those columns never fires), and block the
    # second S_IFMAP when PingPong re-sends the same ifmap tags.
    cfg = _gen_config(hw, active_sets=1, active_cols=2)

    print(f"LN_CONFIG  = 0x{cfg['ln_config']:X}  (expect 0x36DB for 5 sets × 3 rows)")
    print(f"PE_EN mask = 0x{cfg['pe_en']:X}")

    # Show first few filter XID/YID assignments for sanity.
    print("First 6 PE rows filter XID/YID:")
    for row in range(6):
        xid = cfg["filter_xid"][row * NUMS_PE_COL]
        yid = cfg["filter_yid"][row]
        print(f"  row {row}: filter_XID={xid}  filter_YID={yid}")

    lines = pack(cfg)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n")
    print(f"Wrote {len(lines)} entries to {out}")


if __name__ == "__main__":
    main()
