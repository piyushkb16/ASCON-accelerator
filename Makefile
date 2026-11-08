PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
IVFLAGS ?= -g2012 -Wall
RTL := rtl/ascon_round.sv rtl/ascon_permutation.sv

.PHONY: all test vectors check-vectors synth clean
all: test

# Regenerate explicitly; normal tests use the committed golden vectors.
vectors:
	$(PYTHON) scripts/gen_vectors.py

check-vectors:
	$(PYTHON) scripts/gen_vectors.py --check

build/tb_ascon.vvp: $(RTL) tb/tb_ascon.sv
	mkdir -p build
	$(IVERILOG) $(IVFLAGS) -s tb_ascon -o $@ $(RTL) tb/tb_ascon.sv

test: build/tb_ascon.vvp
	$(VVP) $<

# Generic synthesis/check only: no FPGA family, clock or physical mapping.
synth:
	mkdir -p build
	$(YOSYS) -Q -T -l build/synthesis.log scripts/synth.ys

clean:
	rm -rf build
