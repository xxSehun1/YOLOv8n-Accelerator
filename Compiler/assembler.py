"""
Assembler: convert human-readable instruction text to 128-bit hex words.

Each instruction line uses a pipe-delimited key:value format.
See README.md §Instruction Set Architecture for the full bit-field spec.

Three instruction formats:
    CONFIG  – layer dimensions + requantisation scale
    DMA     – DMA_LD / DMA_ST  (DRAM <-> SRAM transfer)
    EXEC    – CONV / POOL / CONCAT / ADD / OTHER / BIAS / HALT
"""

OP_MAP = {
    "CONV":   0x1,
    "POOL":   0x2,
    "CONCAT": 0x3,
    "ADD":    0x4,
    "OTHER":  0x5,
    "CONFIG": 0x6,
    "BIAS":   0x7,
    "DMA_LD": 0x8,
    "DMA_ST": 0x9,
    "ADDCFG": 0xA,
    "HALT":   0xF,
}

_DMA_OPS = ("DMA_LD", "DMA_ST")


def _parse_fields(line):
    """Split 'KEY:VALUE | KEY:VALUE ...' into a dict (whitespace stripped)."""
    return {
        p.split(':', 1)[0].strip(): p.split(':', 1)[1].strip()
        for p in line.split('|')
        if ':' in p
    }


def _encode_config(f, opcode):
    """CONFIG instruction (128-bit).

    SHIFT — 6-bit requantisation right-shift for the PostQuant unit.
    PCFG  — 10-bit per-layer PE_CONFIG (Eyeriss mapping: p, OFMAP_COL, q),
            defaults to 0 for POOL / ADD which do not use the PE array.
    """
    shift = int(f.get('SHIFT', '0'), 16) & 0x3F
    pcfg  = int(f.get('PCFG',  '0'), 16) & 0x3FF
    return (
        opcode                << 124 |
        int(f['IN_H'])        << 108 |
        int(f['IN_W'])        <<  92 |
        int(f['IN_C'])        <<  76 |
        int(f['OUT_C'])       <<  60 |
        int(f['STRIDE'])      <<  56 |
        pcfg                  <<   6 |                       # [15:6]
        shift                                                # [5:0]
    )


def _encode_dma(f, opcode):
    """DMA_LD / DMA_ST instruction (128-bit)."""
    return (
        opcode                                << 124 |
        (int(f['DRAM'], 16) & 0xFFFF_FFFF)    <<  92 |
        (int(f['SRAM'], 16) & 0xFFFF_FFFF)    <<  60 |
        (int(f['SIZE'], 16) & 0xFFFF_FFFF)    <<  28
    )


def _encode_addcfg(f, opcode):
    """ADDCFG instruction (128-bit): per-operand requantisation shifts.

    LHS / RHS are 6-bit right-shift amounts; the ADD unit rescales each
    operand by its shift before summing.
    """
    return (
        opcode                       << 124 |
        (int(f['LHS'], 16) & 0x3F)   << 118 |
        (int(f['RHS'], 16) & 0x3F)   << 112
    )


def _encode_exec(f, opcode):
    """CONV / POOL / CONCAT / ADD / OTHER / BIAS / HALT instruction (128-bit)."""
    return (
        opcode                                  << 124 |
        (int(f['IN'],  16) & 0xFFFF_FFFF)      <<  92 |
        (int(f['WGT'], 16) & 0xFFFF_FFFF)      <<  60 |
        (int(f['OUT'], 16) & 0xFFFF_FFFF)      <<  28 |
        (int(f['FLAGS'], 16) & 0xFFF)           <<  16 |
        (int(f['STRIDE']) & 0xF)                <<  12 |
        (int(f['PAD'])    & 0xF)                <<   8 |
        (int(f['KERNEL']) & 0xF)                <<   4
    )


def text_to_hex_full(input_file, output_file):
    """Assemble *input_file* (one instruction per line) into 32-hex-char words."""
    with open(input_file) as fin, open(output_file, 'w') as fout:
        for lineno, line in enumerate(fin, 1):
            if '|' not in line:
                continue

            fields  = _parse_fields(line)
            op_name = fields.get('OP', '').strip()
            opcode  = OP_MAP.get(op_name)

            if opcode is None:
                raise ValueError(
                    f"assembler: line {lineno}: unknown opcode '{op_name}'"
                )

            try:
                if op_name == "CONFIG":
                    val = _encode_config(fields, opcode)
                elif op_name == "ADDCFG":
                    val = _encode_addcfg(fields, opcode)
                elif op_name in _DMA_OPS:
                    val = _encode_dma(fields, opcode)
                else:
                    val = _encode_exec(fields, opcode)
            except KeyError as missing:
                raise ValueError(
                    f"assembler: line {lineno}: missing field {missing} "
                    f"in: {line.strip()!r}"
                ) from None

            fout.write(f"{val:032x}\n")
