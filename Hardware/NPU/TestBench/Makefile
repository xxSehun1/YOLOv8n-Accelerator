# Run all NPU unit and integration testbenches via Verilator.
#
# Usage (from Hardware/NPU/TestBench):
#   make all          # build + run every unit testbench
#   make pe           # PE single-unit
#   make array        # full PE_array (16x16)
#   make config       # ConfigLoader
#   make weight       # Weight_Buffer
#   make iomap        # IOMap_Buffer
#   make opsum        # OpsumCollector
#   make top          # NPU_top compile-only lint
#   make sim_top      # NPU_top full simulation (1x1 synthetic conv)
#   make clean        # remove obj_* dirs and generated hex
#   make help
#
# Each testbench gets its own --Mdir (obj_<name>) so multiple builds coexist.

VFLAGS := --binary --timing -j 16 -Wno-fatal
VCS ?= vcs
VCS_FLAGS := -sverilog -full64 -timescale=1ns/1ps -debug_access+all
VCS_FAST_FLAGS := -sverilog -full64 -timescale=1ns/1ps +define+NO_FSDB
VCS_FULL_FLAGS := -sverilog -full64 -timescale=1ns/1ps +define+NO_FSDB +define+GATEC_FULL
XRUN ?= xrun
XRUN_FLAGS := -64bit -sv -timescale 1ns/1ps

VINCS := +incdir+.. \
         +incdir+../Control \
         +incdir+../Buffer \
         +incdir+../Compute \
         +incdir+../Memory \
         +incdir+../PE_Array \
         +incdir+../PE_Array/GIN \
         +incdir+../PE_Array/GON \
         +incdir+../PPU

# Full source list for NPU_top builds.
TOP_SRCS := ../NPU_top.sv \
            ../Control/Decoder.sv ../Control/DMA_ctrl.sv \
            ../Control/ConfigLoader.sv ../Control/PingPong_Ctrl.sv \
            ../Control/OpsumCollector.sv \
            ../Buffer/Weight_Buffer.sv ../Buffer/IOMap_Buffer.sv \
            ../Buffer/Line_Buffer.sv \
            ../Memory/SRAM.sv ../Memory/ICache.sv \
            ../PE_Array/PE_array.sv \
            ../PPU/PPU.sv ../PPU/PSUM_acc.sv ../PPU/Add_Qint8.sv

COMPUTE_SRCS := ../Compute/QuantizeUnit.sv \
                ../Compute/ActivationUnit.sv \
                ../Compute/AddUnit.sv \
                ../Compute/PoolCompareUnit.sv \
                ../Compute/ConvMacUnit.sv \
                ../Compute/ConvAddrGen.sv \
                ../Compute/PoolAddrGen.sv \
                ../Compute/AddAddrGen.sv \
                ../Compute/ComputeTop.sv

CTRL_SRCS := ../NPU_ctrl_top.sv \
             ../Control/Decoder.sv ../Control/DMA_ctrl.sv \
             $(COMPUTE_SRCS) \
             ../Memory/SRAM.sv ../Memory/ICache.sv

.PHONY: all pe array config weight iomap opsum top sim_top ctrl_full primitive_units_vcs quantize_unit_vcs activation_unit_vcs add_unit_vcs pool_compare_unit_vcs conv_mac_unit_vcs silu_qint8_vcs pingpong_buffer_vcs step2_pe_pipeline_vcs gate_f_micro_vcs gate_f_first_conv_full_vcs gate_f_first_conv_fast_vcs gate_f_first_conv_fast_vec_vcs decoder_opcode_vcs dma_ctrl_unit_vcs first_conv_vcs first_conv_vcs_fsdb gate_c_first_conv_vcs gate_c_first_conv_full_vcs gate_d_first_add_vcs gate_d_sppf_vcs gate_e_full_backbone_vcs ctrl_full_vcs ctrl_full_vcs_fsdb ctrl_full_xrun use_gatef_micro_program use_build_program clean help

all: pe array config weight iomap opsum
	@echo
	@echo "==== ALL UNIT TESTBENCHES DONE ===="

# PE single-unit.
pe:
	@echo "==== PE_tb ===="
	verilator $(VFLAGS) $(VINCS) --Mdir obj_pe \
	          ../PE_Array/PE.sv PE_tb.sv --top-module PE_tb
	./obj_pe/VPE_tb

# Full PE_array at 16x16.
array:
	@echo "==== PE_array_tb (16x16) ===="
	verilator $(VFLAGS) $(VINCS) --Mdir obj_array \
	          ../PE_Array/PE_array.sv PE_array_tb.sv \
	          --top-module PE_array_tb
	./obj_array/VPE_array_tb

# ConfigLoader (needs shared_config.hex first).
config: shared_config.hex
	@echo "==== ConfigLoader_tb ===="
	verilator $(VFLAGS) $(VINCS) --Mdir obj_config \
	          ../Control/ConfigLoader.sv ConfigLoader_tb.sv \
	          --top-module ConfigLoader_tb
	./obj_config/VConfigLoader_tb

# Weight_Buffer.
weight:
	@echo "==== Weight_Buffer_tb ===="
	verilator $(VFLAGS) $(VINCS) --Mdir obj_weight \
	          ../Buffer/Weight_Buffer.sv Weight_Buffer_tb.sv \
	          --top-module Weight_Buffer_tb
	./obj_weight/VWeight_Buffer_tb

# IOMap_Buffer.
iomap:
	@echo "==== IOMap_Buffer_tb ===="
	verilator $(VFLAGS) $(VINCS) --Mdir obj_iomap \
	          ../Buffer/IOMap_Buffer.sv IOMap_Buffer_tb.sv \
	          --top-module IOMap_Buffer_tb
	./obj_iomap/VIOMap_Buffer_tb

# OpsumCollector.
opsum:
	@echo "==== OpsumCollector_tb ===="
	verilator $(VFLAGS) $(VINCS) --Mdir obj_opsum \
	          ../Control/OpsumCollector.sv OpsumCollector_tb.sv \
	          --top-module OpsumCollector_tb
	./obj_opsum/VOpsumCollector_tb

# NPU_top compile-only lint (no testbench, no simulation).
top:
	@echo "==== NPU_top compile-only lint ===="
	verilator --lint-only \
	          -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-PINMISSING -Wno-WIDTH \
	          $(VINCS) $(TOP_SRCS) --top-module NPU_top

# NPU_top full simulation (1x1 synthetic conv).
sim_top: shared_config.hex npu_program.hex
	@echo "==== NPU_top_tb (integration) ===="
	verilator $(VFLAGS) -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-PINMISSING \
	          $(VINCS) --Mdir obj_top \
	          $(TOP_SRCS) NPU_top_tb.sv --top-module NPU_top_tb
	./obj_top/VNPU_top_tb

# Control/ISA/data-exchange simulation against the compiler-generated program.
# This uses NPU_ctrl_top with the real sequential ComputeTop.
ctrl_full: use_build_program
	@echo "==== NPU_ctrl_top_tb (generated ISA, real sequential compute) ===="
	verilator $(VFLAGS) -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-PINMISSING \
	          $(VINCS) --Mdir obj_ctrl_full \
	          $(CTRL_SRCS) NPU_ctrl_top_tb.sv --top-module NPU_ctrl_top_tb
	./obj_ctrl_full/VNPU_ctrl_top_tb

primitive_units_vcs: quantize_unit_vcs activation_unit_vcs add_unit_vcs pool_compare_unit_vcs conv_mac_unit_vcs
	@echo "==== Primitive compute unit VCS regression PASS ===="

quantize_unit_vcs:
	@echo "==== QuantizeUnit_tb via VCS ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       ../Compute/QuantizeUnit.sv QuantizeUnit_tb.sv \
	       -top QuantizeUnit_tb -o simv_quantize_unit
	./simv_quantize_unit

activation_unit_vcs:
	@echo "==== ActivationUnit_tb via VCS ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       ../Compute/ActivationUnit.sv ActivationUnit_tb.sv \
	       -top ActivationUnit_tb -o simv_activation_unit
	./simv_activation_unit

add_unit_vcs:
	@echo "==== AddUnit_tb via VCS ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       ../Compute/AddUnit.sv AddUnit_tb.sv \
	       -top AddUnit_tb -o simv_add_unit
	./simv_add_unit

pool_compare_unit_vcs:
	@echo "==== PoolCompareUnit_tb via VCS ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       ../Compute/PoolCompareUnit.sv PoolCompareUnit_tb.sv \
	       -top PoolCompareUnit_tb -o simv_pool_compare_unit
	./simv_pool_compare_unit

conv_mac_unit_vcs:
	@echo "==== ConvMacUnit_tb via VCS ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       ../Compute/ConvMacUnit.sv ConvMacUnit_tb.sv \
	       -top ConvMacUnit_tb -o simv_conv_mac_unit
	./simv_conv_mac_unit

silu_qint8_vcs:
	@echo "==== SiLU_Qint8_tb via VCS ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       ../PPU/SiLU_Qint8.sv SiLU_Qint8_tb.sv \
	       -top SiLU_Qint8_tb -o simv_silu_qint8
	./simv_silu_qint8

pingpong_buffer_vcs:
	@echo "==== PingPong_Ctrl_Buffer_tb via VCS ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       ../Control/PingPong_Ctrl.sv \
	       ../Buffer/Weight_Buffer.sv \
	       ../Buffer/IOMap_Buffer.sv \
	       ../Buffer/Line_Buffer.sv \
	       PingPong_Ctrl_Buffer_tb.sv \
	       -top PingPong_Ctrl_Buffer_tb -o simv_pingpong_buffer
	./simv_pingpong_buffer

step2_pe_pipeline_vcs:
	@echo "==== LineBuffer_PE_pipeline_tb via VCS ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       ../Buffer/Line_Buffer.sv \
	       ../PE_Array/PE.sv \
	       LineBuffer_PE_pipeline_tb.sv \
	       -top LineBuffer_PE_pipeline_tb -o simv_step2_pe_pipeline
	./simv_step2_pe_pipeline

gate_f_micro_vcs: use_gatef_micro_program shared_config.hex
	@echo "==== NPU_top_tb true-systolic micro Gate F smoke via VCS ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       $(TOP_SRCS) NPU_top_tb.sv \
	       -top NPU_top_tb -o simv_npu_top_tb
	./simv_npu_top_tb

gate_f_first_conv_full_vcs: use_gatec_full_program shared_config.hex
	@echo "==== NPU_gate_f_first_conv_tb TRUE systolic full first-CONV via VCS ===="
	$(VCS) $(VCS_FAST_FLAGS) $(VINCS) \
	       $(TOP_SRCS) NPU_gate_f_first_conv_tb.sv \
	       -top NPU_gate_f_first_conv_tb -o simv_gate_f_first_conv_full
	./simv_gate_f_first_conv_full

gate_f_first_conv_fast_vcs: shared_config.hex
	@echo "==== NPU_gate_f_first_conv_fast_tb TRUE systolic full first-CONV via VCS ===="
	$(VCS) $(VCS_FAST_FLAGS) $(VINCS) \
	       $(TOP_SRCS) NPU_gate_f_first_conv_fast_tb.sv \
	       -top NPU_gate_f_first_conv_fast_tb -o simv_gate_f_first_conv_fast
	./simv_gate_f_first_conv_fast

gate_f_first_conv_fast_vec_vcs: shared_config.hex
	@echo "==== NPU_gate_f_first_conv_fast_tb TRUE systolic vector first-CONV via VCS ===="
	$(VCS) $(VCS_FAST_FLAGS) $(VINCS) -Mdir=csrc_gate_f_fast_vec \
	       $(TOP_SRCS) NPU_gate_f_first_conv_fast_tb.sv \
	       -top NPU_gate_f_first_conv_fast_tb -o simv_gate_f_first_conv_fast_vec
	./simv_gate_f_first_conv_fast_vec

decoder_opcode_vcs:
	@echo "==== Decoder_opcode_tb via VCS ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       ../Control/Decoder.sv Decoder_opcode_tb.sv \
	       -top Decoder_opcode_tb -o simv_decoder_opcode
	./simv_decoder_opcode

dma_ctrl_unit_vcs:
	@echo "==== DMA_ctrl_unit_tb via VCS ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       ../Control/DMA_ctrl.sv DMA_ctrl_unit_tb.sv \
	       -top DMA_ctrl_unit_tb -o simv_dma_ctrl_unit
	./simv_dma_ctrl_unit

first_conv_vcs: use_build_program
	@echo "==== NPU_first_conv_tb via VCS ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       $(CTRL_SRCS) NPU_first_conv_tb.sv \
	       -top NPU_first_conv_tb -o simv_first_conv
	./simv_first_conv

gate_c_first_conv_vcs: use_gatec_tiny_program
	@echo "==== NPU_first_conv_tb Gate C via VCS (fast no-debug build) ===="
	$(VCS) $(VCS_FAST_FLAGS) $(VINCS) \
	       $(CTRL_SRCS) NPU_first_conv_tb.sv \
	       -top NPU_first_conv_tb -o simv_gate_c_first_conv
	./simv_gate_c_first_conv

gate_c_first_conv_full_vcs: use_gatec_full_program
	@echo "==== NPU_first_conv_tb Gate C FULL 640x640 via VCS (fast no-debug build) ===="
	$(VCS) $(VCS_FULL_FLAGS) $(VINCS) \
	       $(CTRL_SRCS) NPU_first_conv_tb.sv \
	       -top NPU_first_conv_tb -o simv_gate_c_first_conv_full
	./simv_gate_c_first_conv_full

gate_d_first_add_vcs: use_gated_first_add_program
	@echo "==== NPU_gate_d_tb first residual ADD via VCS ===="
	$(VCS) $(VCS_FAST_FLAGS) $(VINCS) \
	       $(CTRL_SRCS) NPU_gate_d_tb.sv \
	       -top NPU_gate_d_tb -o simv_gate_d_first_add
	./simv_gate_d_first_add

gate_d_sppf_vcs: use_gated_sppf_program
	@echo "==== NPU_gate_d_tb SPPF via VCS ===="
	$(VCS) $(VCS_FAST_FLAGS) +define+GATED_SPPF $(VINCS) \
	       $(CTRL_SRCS) NPU_gate_d_tb.sv \
	       -top NPU_gate_d_tb -o simv_gate_d_sppf
	./simv_gate_d_sppf

gate_e_full_backbone_vcs: use_build_program
	@echo "==== NPU_gate_e_tb full backbone via VCS ===="
	$(VCS) $(VCS_FAST_FLAGS) $(VINCS) \
	       $(CTRL_SRCS) NPU_gate_e_tb.sv \
	       -top NPU_gate_e_tb -o simv_gate_e_full_backbone
	./simv_gate_e_full_backbone

first_conv_vcs_fsdb: use_build_program
	@echo "==== NPU_first_conv_tb via VCS + FSDB ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       $(CTRL_SRCS) NPU_first_conv_tb.sv \
	       -top NPU_first_conv_tb -o simv_first_conv_fsdb
	./simv_first_conv_fsdb +FSDB

ctrl_full_vcs: use_build_program
	@echo "==== NPU_ctrl_top_tb via VCS (generated ISA, real sequential compute) ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       $(CTRL_SRCS) NPU_ctrl_top_tb.sv \
	       -top NPU_ctrl_top_tb -o simv_ctrl_full
	./simv_ctrl_full

ctrl_full_vcs_fsdb: use_build_program
	@echo "==== NPU_ctrl_top_tb via VCS + FSDB ===="
	$(VCS) $(VCS_FLAGS) $(VINCS) \
	       $(CTRL_SRCS) NPU_ctrl_top_tb.sv \
	       -top NPU_ctrl_top_tb -o simv_ctrl_full_fsdb
	./simv_ctrl_full_fsdb +FSDB

ctrl_full_xrun: use_build_program
	@echo "==== NPU_ctrl_top_tb via xrun (generated ISA, real sequential compute) ===="
	$(XRUN) $(XRUN_FLAGS) $(VINCS) \
	        $(CTRL_SRCS) NPU_ctrl_top_tb.sv \
	        -top NPU_ctrl_top_tb

# Generated hex inputs.
# shared_config.hex is generated directly from the PE-array geometry (mapping.py _gen_config).
# This is correct because XID/YID assignments depend only on array shape, not on layer params.
shared_config.hex:
	@echo "-- generating shared_config.hex --"
	python3 ../../../Compiler/gen_shared_hex_direct.py --out shared_config.hex

npu_program.hex:
	@echo "-- generating npu_program.hex --"
	python3 ../../../Compiler/gen_test_program.py --out npu_program.hex

use_build_program:
	@echo "-- using compiler-generated Build/npu_program.hex --"
	cp ../../../Build/npu_program.hex npu_program.hex

use_gatec_tiny_program:
	@echo "-- using Gate C tiny first-conv program --"
	cp ../../../Build/npu_program_gatec_tiny.hex npu_program.hex

use_gatec_full_program:
	@echo "-- using Gate C full first-conv program --"
	cp ../../../Build/npu_program_gatec_full.hex npu_program.hex

use_gated_first_add_program:
	@echo "-- using Gate D first residual ADD program --"
	cp ../../../Build/npu_program_gate_d_first_add.hex npu_program.hex

use_gated_sppf_program:
	@echo "-- using Gate D SPPF block program --"
	cp ../../../Build/npu_program_gate_d_sppf.hex npu_program.hex

use_gatef_micro_program:
	@echo "-- using true-systolic Gate F micro smoke program --"
	cp npu_program_gatef_micro.hex npu_program.hex

clean:
	rm -rf obj_pe obj_array obj_config obj_weight obj_iomap obj_opsum obj_top \
	       obj_ctrl_full simv_ctrl_full simv_ctrl_full.daidir \
	       simv_quantize_unit simv_quantize_unit.daidir \
	       simv_activation_unit simv_activation_unit.daidir \
	       simv_add_unit simv_add_unit.daidir \
	       simv_pool_compare_unit simv_pool_compare_unit.daidir \
	       simv_conv_mac_unit simv_conv_mac_unit.daidir \
	       simv_silu_qint8 simv_silu_qint8.daidir \
	       simv_pingpong_buffer simv_pingpong_buffer.daidir \
	       simv_step2_pe_pipeline simv_step2_pe_pipeline.daidir \
	       simv_npu_top_tb simv_npu_top_tb.daidir \
	       simv_gate_f_first_conv_full simv_gate_f_first_conv_full.daidir \
	       simv_decoder_opcode simv_decoder_opcode.daidir \
	       simv_dma_ctrl_unit simv_dma_ctrl_unit.daidir \
	       simv_first_conv simv_first_conv.daidir \
	       simv_gate_c_first_conv simv_gate_c_first_conv.daidir \
	       simv_gate_c_first_conv_full simv_gate_c_first_conv_full.daidir \
	       simv_gate_d_first_add simv_gate_d_first_add.daidir \
	       simv_gate_d_sppf simv_gate_d_sppf.daidir \
	       simv_gate_e_full_backbone simv_gate_e_full_backbone.daidir \
	       simv_first_conv_fsdb simv_first_conv_fsdb.daidir npu_first_conv.fsdb \
	       simv_ctrl_full_fsdb simv_ctrl_full_fsdb.daidir npu_ctrl_top.fsdb \
	       xcelium.d xrun.history xrun.log csrc ucli.key \
	       shared_config.hex npu_program.hex

help:
	@echo "Targets:"
	@echo "  Unit tests : pe array config weight iomap opsum"
	@echo "  Integration: top (lint) sim_top (run)"
	@echo "  Compute    : primitive_units_vcs quantize_unit_vcs activation_unit_vcs add_unit_vcs pool_compare_unit_vcs conv_mac_unit_vcs silu_qint8_vcs gate_c_first_conv_vcs gate_c_first_conv_full_vcs gate_d_first_add_vcs gate_d_sppf_vcs gate_e_full_backbone_vcs"
	@echo "  Control sim: ctrl_full (Verilator) pingpong_buffer_vcs (VCS) step2_pe_pipeline_vcs (VCS) gate_f_micro_vcs (VCS) decoder_opcode_vcs (VCS) dma_ctrl_unit_vcs (VCS) first_conv_vcs (VCS) first_conv_vcs_fsdb (VCS+FSDB) ctrl_full_vcs (VCS) ctrl_full_vcs_fsdb (VCS+FSDB) ctrl_full_xrun (xrun)"
	@echo "  Generated  : shared_config.hex npu_program.hex"
	@echo "  Utility    : all clean help"
