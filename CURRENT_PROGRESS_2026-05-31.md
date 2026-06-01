# YOLOv8n Backbone Outer-Control Progress

Date: 2026-05-31

## Current Scope

目前完成範圍是我方負責的 NPU 最外層 control/dataflow bring-up：

```text
start / rst
  -> ICache
  -> Decoder
  -> DMA_ctrl
  -> SRAM / DRAM model
  -> DummyExec
  -> HALT
```

目前不是完整 YOLOv8 backbone 數值驗證。CONV / POOL / ADD 的 real compute 還是用 `DummyExec` 代替。

## Spec Basis

目前 RTL/TB 對齊新版 compiler generated ISA：

```text
DMA_LD  = DRAM -> SRAM
DMA_ST  = SRAM -> DRAM
CONFIG  = latch tensor/config state for next compute op
ADDCFG  = latch lhs/rhs shift for next ADD
CONV    = dispatch compute command
POOL    = dispatch compute command
ADD     = dispatch compute command
HALT    = stop execution and park PC
```

新版 concat 不再使用舊版 overloaded `DMA_LD SRAM->SRAM`。現在 concat 透過 DRAM staging：

```text
SRAM -> DRAM by DMA_ST
DRAM -> SRAM by DMA_LD
```

## RTL Completed

- `Hardware/NPU/NPU_ctrl_top.sv`
  - 整合 ICache、Decoder、DMA_ctrl、SRAM、DummyExec。
  - 提供 waveform/debug 訊號：
    ```text
    debug_pc
    debug_opcode
    debug_opcode_name
    debug_exec_valid
    debug_dma_valid
    debug_*_count
    ```

- `Hardware/NPU/Control/Decoder.sv`
  - 支援 current ISA decode flow。
  - 修正 unsupported opcode：不會 deadlock，會前進到下一條。
  - 修正 HALT：PC 停在 HALT instruction，不會被 default case 多加一。
  - 加入 command stability assertions：
    ```text
    DMA payload stable while dma_valid && !dma_done
    EXEC payload stable while exec_valid && !exec_done
    ```

- `Hardware/NPU/Control/DMA_ctrl.sv`
  - 支援 DMA_LD DRAM->SRAM。
  - 支援 DMA_ST SRAM->DRAM。
  - 不再使用舊版 SRAM->SRAM concat-copy overload。

## TB Completed

- `Hardware/NPU/TestBench/Decoder_opcode_tb.sv`
  - 直接測 Decoder opcode output。
  - 覆蓋：
    ```text
    DMA_LD
    DMA_ST
    CONFIG + CONV
    CONFIG + POOL
    ADDCFG + CONFIG + ADD
    HALT
    unsupported CONCAT / OTHER / BIAS / 0xE
    ```

- `Hardware/NPU/TestBench/DMA_ctrl_unit_tb.sv`
  - 直接測 DMA_ctrl data path。
  - 覆蓋：
    ```text
    small DMA_LD
    weight DMA_LD
    small DMA_ST
    DRAM staging store/load pair
    ```

- `Hardware/NPU/TestBench/NPU_first_conv_tb.sv`
  - 只跑到第一個 CONV。
  - 驗證 input DMA、weight DMA、CONFIG、CONV dispatch、DummyExec output。

- `Hardware/NPU/TestBench/NPU_ctrl_top_tb.sv`
  - 跑完整 generated backbone ISA 到 HALT。
  - 用 monitor witness 追每條 decode/DMA/EXEC flow。
  - 檢查 op count、DMA count、concat staging、final output region smoke。

## VCS Results

已跑過：

```text
make decoder_opcode_vcs       PASS
make dma_ctrl_unit_vcs        PASS
make first_conv_vcs           PASS
make ctrl_full_vcs            PASS
make first_conv_vcs_fsdb      PASS
make ctrl_full_vcs_fsdb       PASS
```

Full generated backbone checkpoint：

```text
pc=141
exec=36
conv=27
pool=3
add=6
dma_ld=46
dma_st=17
weight_ld=27
sram_copy=0
store=17
```

## Generated Evidence

Clean markdown logs：

```text
decoder_opcode_log.md
dma_ctrl_unit_log.md
first_conv_log.md
log.md
```

Full report：

```text
YOLO_BACKBONE_VERIFICATION_REPORT_2026-05-31.md
```

FSDB：

```text
Hardware/NPU/TestBench/npu_first_conv.fsdb
Hardware/NPU/TestBench/npu_ctrl_top.fsdb
```

## Important Current Claim

現在可以主張：

```text
Outer control/dataflow path is implemented and verified with DummyExec.
Generated ISA can run from start to HALT.
Decoder opcode behavior is unit-tested.
DMA_ctrl direction and data movement are unit-tested.
First CONV outer data/control flow is verified.
Full generated backbone outer-control sequence reaches HALT with expected counts.
```

現在不能主張：

```text
YOLOv8 backbone numerical correctness.
Real convolution correctness.
Real pooling correctness.
Real residual ADD correctness.
PE array / systolic scheduling correctness.
PPU / activation / quantization correctness.
Bit-exact P3/P4/P5 outputs.
```

## Remaining Work

下一個真正 milestone 應該是：

```text
Replace DummyExec for the first real CONV layer.
Compare first CONV output against frozen bit-exact integer golden output.
```

在 real compute 接上前，這個專案目前只能算是：

```text
Control/dataflow bring-up complete.
Numerical accelerator validation not complete.
```

