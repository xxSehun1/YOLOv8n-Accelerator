# Gate C Full First CONV Report - 2026-05-31

## Scope

This run uses the ISA-defined first YOLOv8n backbone CONV size, not the tiny 16x16 smoke test.

Full Gate C ISA:

```text
OP:DMA_LD | DRAM:0x00000000 | SRAM:0x00000000 | SIZE:0x0012C000
OP:DMA_LD | DRAM:0x01000000 | SRAM:0x00380000 | SIZE:0x000001F0
OP:CONFIG | IN_H:640 | IN_W:640 | IN_C:3 | OUT_C:16 | STRIDE:2 | PCFG:0x07E | SHIFT:0x0A
OP:CONV   | IN:0x00000000 | WGT:0x00380000 | OUT:0x0012C000 | FLAGS:0xB | STRIDE:2 | PAD:1 | KERNEL:3
OP:HALT   | IN:0x00000000 | WGT:0x00000000 | OUT:0x00000000 | FLAGS:0x0 | STRIDE:0 | PAD:0 | KERNEL:0
```

Tensor sizes:

```text
Input  = 640 * 640 * 3   = 0x0012C000 bytes
Output = 320 * 320 * 16  = 0x00190000 bytes
Output SRAM base = 0x0012C000
Last output byte = 0x0012C000 + 0x00190000 - 1 = 0x002BBFFF
```

## Generated Files

```text
Build/input_seed0.bin                  size=1228800  sha256=f70a73020042b6b5acd0207fd004ee3291da0dbb779f10b4e231a2019a747006
Build/golden_l0_conv.bin               size=1638400  sha256=3192dbd8c4ecf9de4ef79d1c7de7482ac6ad3c264d9093aae7e8d0cbafde4eb6
Build/full_instructions_gatec_full.txt size=421      sha256=9a16b123cfa7aa0b5315d1494d2b6c838c6f11182bd481d18536d54f1fbdca99
Build/npu_program_gatec_full.hex       size=165      sha256=e209bb4c7317c04b583c6fff789859736bec35a0df9487d7ecfb4204fc067718
```

## Command

Run from `Hardware/NPU/TestBench`:

```sh
tcsh -c 'make gate_c_first_conv_full_vcs >& gate_c_first_conv_full_vcs.log'
```

The target compiles `NPU_first_conv_tb.sv` with:

```text
+define+GATEC_FULL
+define+NO_FSDB
```

## Monitor Witness

Source log:

```text
Hardware/NPU/TestBench/gate_c_first_conv_full_vcs.log
```

Important monitor lines:

```text
== NPU_first_conv_tb: Gate C full 640x640 first real CONV bit-exact check ==
[DECODE pc=0] DMA_LD dram=0x00000000 sram=0x00000000 size=0x0012c000
[DECODE pc=1] DMA_LD dram=0x01000000 sram=0x00380000 size=0x000001f0
[DECODE pc=2] CONFIG H=640 W=640 IC=3 OC=16 stride=2 pcfg=0x07e shift=0x0a
[DECODE pc=3] CONV in=0x00000000 wgt=0x00380000 out=0x0012c000 flags=0x00b stride=2 pad=1 kernel=3 uses_cfg(H=640 W=640 IC=3 OC=16 pcfg=0x07e shift=0x0a)
[COMPUTE][pc=3] wrote through output byte offset 0x0018ffff oc=15 oh=319 ow=319
[EXEC_DONE][pc=3] first CONV real output complete
[TB] first CONV completed at 501762725000
[DECODE pc=4] HALT
[TB] HALT observed at 501762745000
```

The final output offset `0x0018ffff` is the last byte of a `0x00190000` byte output tensor.

## Result

PASS:

```text
PASS: debug opcode alias checked through first CONV and HALT
PASS: HALT reached after first CONV
PASS: Gate C full 640x640 first CONV output byte-for-byte matches ../../../Build/golden_l0_conv.bin
== NPU_first_conv_tb GATE C PASS ==
```

VCS report:

```text
Simulation time: 501762745000 ps
CPU Time: 30.540 seconds
Data structure size: 12.0Mb
```

## Conclusion

Full Gate C first CONV passed at ISA-defined tensor size.

This confirms, for the first YOLOv8n backbone CONV layer:

- DMA input load handles `0x0012C000` bytes.
- DMA weight load handles the first layer `0x000001F0` byte weight/bias blob.
- Decoder latches the full `640x640x3 -> 16` CONFIG.
- `ConvAddrGen` reaches the final full-scale coordinate `oc=15 oh=319 ow=319`.
- Decoder reaches `HALT` at pc=4 after the first CONV completes.
- Compute output SRAM matches the frozen software golden byte-for-byte.
