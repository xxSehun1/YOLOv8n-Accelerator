"""
phase0_audit.py -- Phase 0 golden-contract audit.

This script checks the current generated artifacts before real RTL numerical
work starts. It intentionally separates two ideas:

1. Structural artifact sanity can pass today.
2. Final golden-contract freeze can still be incomplete until independent
   golden tensors and the integer math spec are versioned.
"""
import argparse
import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "Build"

DRAM_OUTPUT_BASE = 0x0020_0000
DRAM_WEIGHT_BASE = 0x0100_0000

REQUIRED_ARTIFACTS = [
    BUILD / "full_instructions.txt",
    BUILD / "npu_program.hex",
    BUILD / "weights.bin",
    BUILD / "mapping.txt",
]

OPTIONAL_GENERATED = [
    BUILD / "iss_layers.npz",
]

FROZEN_GOLDEN_REQUIRED = [
    ("golden_contract.md", None),
    ("golden_p3.bin", 0x00064000),
    ("golden_p4.bin", 0x00032000),
    ("golden_p5.bin", 0x00019000),
]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_fields(line):
    out = {}
    for part in line.split("|"):
        if ":" in part:
            k, v = part.split(":", 1)
            out[k.strip()] = v.strip()
    return out


def load_instructions(path):
    return [parse_fields(line.strip())
            for line in path.read_text().splitlines()
            if "OP:" in line]


def audit_artifacts() -> bool:
    ok = True
    print("== Phase 0 artifact presence ==")
    for path in REQUIRED_ARTIFACTS:
        if path.exists():
            print(f"  PASS: {path.relative_to(ROOT)} exists size={path.stat().st_size}")
        else:
            print(f"  FAIL: {path.relative_to(ROOT)} missing")
            ok = False

    print("\n== Artifact hashes ==")
    for path in REQUIRED_ARTIFACTS:
        if path.exists():
            print(f"  SHA256 {path.relative_to(ROOT)} {sha256(path)}")

    print("\n== Optional generated artifacts ==")
    for path in OPTIONAL_GENERATED:
        if path.exists():
            print(f"  INFO: {path.relative_to(ROOT)} exists size={path.stat().st_size}")
        else:
            print(f"  INFO: {path.relative_to(ROOT)} not present yet")
    return ok


def audit_isa() -> bool:
    instr_path = BUILD / "full_instructions.txt"
    if not instr_path.exists():
        return False

    ok = True
    instrs = load_instructions(instr_path)
    counts = {}
    for ins in instrs:
        op = ins.get("OP", "")
        counts[op] = counts.get(op, 0) + 1

    print("\n== ISA structural checks ==")
    print(f"  INFO: instruction_count={len(instrs)}")
    for op in sorted(counts):
        print(f"  INFO: {op}={counts[op]}")

    if instrs and instrs[-1].get("OP") == "HALT":
        print("  PASS: final instruction is HALT")
    else:
        print("  FAIL: final instruction is not HALT")
        ok = False

    old_overload = []
    input_loads = 0
    for idx, ins in enumerate(instrs):
        if ins.get("OP") != "DMA_LD":
            continue
        dram = int(ins["DRAM"], 16)
        if dram >= DRAM_WEIGHT_BASE:
            continue
        if dram < DRAM_OUTPUT_BASE:
            input_loads += 1
            if input_loads > 1:
                old_overload.append((idx, dram, int(ins["SRAM"], 16)))

    if not old_overload:
        print("  PASS: no old low-address overloaded DMA_LD concat pattern found")
    else:
        print("  FAIL: possible old overloaded DMA_LD concat pattern found")
        for idx, dram, sram in old_overload[:8]:
            print(f"    line={idx} dram=0x{dram:08X} sram=0x{sram:08X}")
        ok = False

    if counts.get("DMA_LD", 0) == 46 and counts.get("DMA_ST", 0) == 17:
        print("  PASS: DMA_LD/DMA_ST counts match current generated backbone")
    else:
        print("  FAIL: DMA_LD/DMA_ST counts differ from current generated backbone")
        ok = False

    if counts.get("CONV", 0) == 27 and counts.get("POOL", 0) == 3 and counts.get("ADD", 0) == 6:
        print("  PASS: CONV/POOL/ADD counts match current generated backbone")
    else:
        print("  FAIL: compute op counts differ from current generated backbone")
        ok = False

    return ok


def audit_frozen_golden() -> bool:
    print("\n== Frozen golden-contract files ==")
    ok = True
    for rel, expected_size in FROZEN_GOLDEN_REQUIRED:
        path = BUILD / rel
        if path.exists():
            size = path.stat().st_size
            if expected_size is not None and size != expected_size:
                print(
                    f"  FAIL: {path.relative_to(ROOT)} size={size} "
                    f"expected={expected_size}"
                )
                ok = False
            else:
                print(f"  PASS: {path.relative_to(ROOT)} exists size={size}")
                print(f"  SHA256 {path.relative_to(ROOT)} {sha256(path)}")
        else:
            print(f"  BLOCKER: {path.relative_to(ROOT)} missing")
            ok = False
    if ok:
        print("  PASS: final sign-off golden contract files are present")
    else:
        print("  INFO: Phase 0 final golden contract is not frozen yet")
    return ok


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true",
                        help="return non-zero if frozen golden files are missing")
    args = parser.parse_args()

    artifacts_ok = audit_artifacts()
    isa_ok = audit_isa()
    golden_ok = audit_frozen_golden()

    print("\n== Phase 0 audit result ==")
    if artifacts_ok and isa_ok:
        print("  PASS: generated ISA/artifact structure is internally sane")
    else:
        print("  FAIL: generated ISA/artifact structure has errors")
        return 1

    if golden_ok:
        print("  PASS: frozen final golden contract is present")
        return 0

    print("  INCOMPLETE: frozen final golden contract is still missing")
    return 2 if args.strict else 0


if __name__ == "__main__":
    raise SystemExit(main())
