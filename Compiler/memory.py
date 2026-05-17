"""
Memory model for the ping-pong NPU.

Feature maps (activations) live entirely in the 4 MiB on-chip SRAM and
ping-pong between layers — there is no DRAM round-trip for intermediate
activations. The hardware Ping-Pong Controller streams them through the
64 KiB I/O Map Buffers automatically.

DRAM holds only:
  - the input image,
  - the packed INT8 weights (+ INT32 bias),
  - the three multi-scale backbone outputs (P3 / P4 / P5) handed to the neck.
"""
from utils import align_up

# ── DRAM (off-chip) ─────────────────────────────────────────────────────────
DRAM_INPUT_BASE   = 0x0000_0000          # input image
DRAM_OUTPUT_BASE  = 0x0020_0000          # backbone outputs P3 / P4 / P5
DRAM_OUTPUT_SIZE  = 14 * 1024 * 1024
DRAM_WEIGHT_BASE  = 0x0100_0000          # packed INT8 weights + INT32 bias
DRAM_WEIGHT_SIZE  = 4 * 1024 * 1024

# ── SRAM (4 MiB on-chip) ────────────────────────────────────────────────────
SRAM_SIZE         = 4 * 1024 * 1024
SRAM_WSTAGE_SIZE  = 512 * 1024           # weight staging area (two slots)
SRAM_WSTAGE_BASE  = SRAM_SIZE - SRAM_WSTAGE_SIZE
SRAM_WSTAGE_SLOT  = SRAM_WSTAGE_SIZE // 2    # 256 KiB per double-buffer slot
SRAM_ACT_BASE     = 0x0000_0000          # activation region (everything below)
SRAM_ACT_SIZE     = SRAM_WSTAGE_BASE

BUF_ALIGN = 16
ISA_MAX_INSTRUCTIONS = (64 * 1024) // 16     # 64 KiB ISA region, 16 B/instr


class BumpAllocator:
    """Monotonic bump allocator over a fixed byte region (no reuse)."""

    def __init__(self, base, size, name):
        self.base   = base
        self.limit  = base + size
        self.cursor = base
        self.name   = name

    def alloc(self, nbytes, align=BUF_ALIGN):
        addr = align_up(self.cursor, align)
        if addr + nbytes > self.limit:
            raise MemoryError(
                f"{self.name} overflow: 0x{nbytes:X} B at 0x{addr:08X} "
                f"exceeds region limit 0x{self.limit:08X}"
            )
        self.cursor = addr + nbytes
        return addr

    @property
    def used(self):
        return self.cursor - self.base


class PoolAllocator:
    """Bump allocator with free-list reuse and coalescing.

    Used for the SRAM activation region: a feature map is released once its
    last consumer has run, and its space reused by a later layer. Liveness
    keeps a residual's input alive across the whole bottleneck automatically.
    """

    def __init__(self, base, size, name):
        self.base  = base
        self.limit = base + size
        self.name  = name
        self.bump  = base
        self.holes = []                       # sorted list of [addr, size]
        self.peak  = 0

    def alloc(self, nbytes, align=BUF_ALIGN):
        nbytes = align_up(nbytes, align)
        for hole in self.holes:               # first-fit reuse
            if hole[1] >= nbytes:
                addr = hole[0]
                if hole[1] == nbytes:
                    self.holes.remove(hole)
                else:
                    hole[0] += nbytes
                    hole[1] -= nbytes
                return addr
        addr = align_up(self.bump, align)
        if addr + nbytes > self.limit:
            raise MemoryError(
                f"{self.name} overflow: 0x{nbytes:X} B at 0x{addr:08X} "
                f"exceeds region limit 0x{self.limit:08X}"
            )
        self.bump = addr + nbytes
        self.peak = max(self.peak, self.bump - self.base)
        return addr

    def release(self, addr, nbytes, align=BUF_ALIGN):
        nbytes = align_up(nbytes, align)
        self.holes.append([addr, nbytes])
        self.holes.sort()
        merged = []
        for h in self.holes:
            if merged and merged[-1][0] + merged[-1][1] == h[0]:
                merged[-1][1] += h[1]
            else:
                merged.append(list(h))
        self.holes = merged

    @property
    def used(self):
        return self.peak
