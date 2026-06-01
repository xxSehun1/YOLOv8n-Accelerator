
PYTHON ?= python3
TEST_DATA_ROOT_PATH ?= /tmp/tvm_test_data


run: 
	$(PYTHON) main.py
	$(PYTHON) gen_shared_hex.py

sim:
	$(PYTHON) npu_iss.py

valid:
	TEST_DATA_ROOT_PATH=$(TEST_DATA_ROOT_PATH) $(PYTHON) validation.py

phase0:
	$(PYTHON) phase0_audit.py

phase0-strict:
	$(PYTHON) phase0_audit.py --strict

gatec-vectors:
	$(PYTHON) generate_gatec_vectors.py

gated-vectors:
	$(PYTHON) generate_gate_d_vectors.py

clean:
	rm -f	../Build/full_instructions.txt \
			../Build/cpu_runtime.py \
			../Build/npu_program.hex \
			../Build/weights.bin \
			../Build/weights.hex \
			../Build/iss_layers.npz \
			../Build/mapping.txt
