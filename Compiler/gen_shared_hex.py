"""
Generate shared_config.hex for the NPU's ConfigLoader.

Reads the [SHARED] section of mapping.txt and packs the 4 XID + 4 YID per-PE
values into one 40-bit hex line per PE (matches ConfigLoader.sv ROM_W).

Packed layout, LSB first:
  [ 4: 0]  ifmap_XID
  [ 9: 5]  filter_XID
  [14:10]  ipsum_XID
  [19:15]  opsum_XID
  [24:20]  ifmap_YID
  [29:25]  filter_YID
  [34:30]  ipsum_YID
  [39:35]  opsum_YID

Usage:
  python gen_shared_hex.py
  python gen_shared_hex.py --mapping ../Build/mapping.txt \
                           --out ../Hardware/NPU/TestBench/shared_config.hex
"""
import argparse
import sys
from pathlib import Path

XID_BITS    = 5
YID_BITS    = 5
NUMS_PE_ROW = 16
NUMS_PE_COL = 16
NUM_PE      = NUMS_PE_ROW * NUMS_PE_COL


def parse_shared(path):
    """Parse the [SHARED] section of mapping.txt. Returns dict of lists/ints."""
    text = Path(path).read_text()
    if "[SHARED]" not in text:
        sys.exit(f"error: no [SHARED] section in {path}")

    shared = text.split("[SHARED]", 1)[1]
    if "[LAYERS]" in shared:
        shared = shared.split("[LAYERS]", 1)[0]

    out = {}
    for line in shared.splitlines():
        if ":" not in line:
            continue
        key, val = line.split(":", 1)
        key, val = key.strip(), val.strip()
        if "," in val:
            out[key] = [int(x) for x in val.split(",")]
        elif val.startswith("0x"):
            out[key] = int(val, 16)
        elif val.lstrip("-").isdigit():
            out[key] = int(val)
    return out


def pack(shared):
    """Return one hex string per PE, packed per the layout above."""
    fields = [("ifmap_XID",  XID_BITS),
              ("filter_XID", XID_BITS),
              ("ipsum_XID",  XID_BITS),
              ("opsum_XID",  XID_BITS),
              ("ifmap_YID",  YID_BITS),
              ("filter_YID", YID_BITS),
              ("ipsum_YID",  YID_BITS),
              ("opsum_YID",  YID_BITS)]

    # mapping.py emits YID per row (16 entries) and XID per PE (256 entries),
    # because in Eyeriss YID is shared across a PE row. Expand the per-row
    # lists so every PE has its own packed value.
    for name, _ in fields:
        if name not in shared:
            sys.exit(f"error: mapping.txt [SHARED] missing field '{name}'")
        lst = shared[name]
        if len(lst) == NUMS_PE_ROW:
            shared[name] = [lst[i // NUMS_PE_COL] for i in range(NUM_PE)]
        elif len(lst) != NUM_PE:
            sys.exit(f"error: {name} has {len(lst)} entries, "
                     f"expected {NUM_PE} or {NUMS_PE_ROW}")

    lines = []
    for i in range(NUM_PE):
        packed = 0
        offset = 0
        for name, bits in fields:
            v = shared[name][i] & ((1 << bits) - 1)
            packed |= v << offset
            offset += bits
        lines.append(f"{packed:010x}")
    return lines


def main():
    ap = argparse.ArgumentParser(description="Generate shared_config.hex.")
    ap.add_argument("--mapping", default="../Build/mapping.txt",
                    help="path to mapping.txt (default: %(default)s)")
    ap.add_argument("--out",
                    default="../Hardware/NPU/TestBench/shared_config.hex",
                    help="output hex path (default: %(default)s)")
    args = ap.parse_args()

    shared = parse_shared(args.mapping)
    lines  = pack(shared)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n")
    print(f"wrote {len(lines)} entries to {out}")

    if "LN_CONFIG" in shared:
        print(f"  LN_CONFIG = 0x{shared['LN_CONFIG']:X}  "
              f"(confirm against ConfigLoader LN_CONFIG_INIT = 0x36DB)")
    if "PE_EN" in shared:
        print(f"  PE_EN     = 0x{shared['PE_EN']:X}  "
              f"(confirm against ConfigLoader PE_EN_INIT)")


if __name__ == "__main__":
    main()
