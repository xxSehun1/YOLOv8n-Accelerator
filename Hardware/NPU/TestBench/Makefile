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

VFLAGS := --binary --timing -j 0 -Wno-fatal

VINCS := +incdir+.. \
         +incdir+../Control \
         +incdir+../Buffer \
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

.PHONY: all pe array config weight iomap opsum top sim_top clean help

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

# Generated hex inputs.
# shared_config.hex is generated directly from the PE-array geometry (mapping.py _gen_config).
# This is correct because XID/YID assignments depend only on array shape, not on layer params.
shared_config.hex:
	@echo "-- generating shared_config.hex --"
	python3 ../../../Compiler/gen_shared_hex_direct.py --out shared_config.hex

npu_program.hex:
	@echo "-- generating npu_program.hex --"
	python3 ../../../Compiler/gen_test_program.py --out npu_program.hex

clean:
	rm -rf obj_pe obj_array obj_config obj_weight obj_iomap obj_opsum obj_top \
	       shared_config.hex npu_program.hex

help:
	@echo "Targets:"
	@echo "  Unit tests : pe array config weight iomap opsum"
	@echo "  Integration: top (lint) sim_top (run)"
	@echo "  Generated  : shared_config.hex npu_program.hex"
	@echo "  Utility    : all clean help"
