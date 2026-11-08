# Milestone 1 verification record

This record covers the conventional round and permutation engine only.
Verification was run on 7 November 2026 (Asia/Kolkata).

## Results

| Check | Result |
| --- | --- |
| Single-round outputs across all 12 constants | 7,332 / 7,332 passed |
| p8/p12 complete permutation outputs | 1,222 / 1,222 passed |
| Completed transactions including protocol scenarios | 1,227 |
| Testbench checks | 71,341 passed |
| Offline vectors rebuilt from pinned C source | Both files and manifest matched |
| Generic synthesis and structural check | Passed, zero reported problems |

The simulation finished at 142,866 ns. This is testbench simulated time, not
an FPGA performance measurement. The test clock is deliberately arbitrary.

Golden outputs use the actual unmodified upstream C round/permutation functions
at commit `446347f21b209f3921c65ece70027c366cbe1693`. See
[`../reference/README.md`](../reference/README.md) for source hashes, license,
the deterministic seed, input coverage and vector format. No network access is
required to rebuild the reference oracle.

The controller suite checks captured input/mode, 8- and 12-clock compute
latency, 9- and 13-clock minimum acceptance intervals, ignored requests while
busy (including the completion edge), held-start retriggering, stable completed
outputs, one-cycle completion pulses, asynchronous reset aborts, ignored starts
under reset, recovery and absence of stale completions. Reset is exercised
early in p12, immediately before p8 completion, and while completion is high.

An independent specification review also enumerated all 32 S-box mappings
against NIST Table 6 and checked all diffusion rotations and round constants.
The committed round vectors cover all 32 repeated bit-column input patterns.

## Reproduce

From the repository root, with tools on PATH:

```sh
make test
make check-vectors
make synth
```

Tools used here:

- Icarus Verilog compiler/runtime 12.0 (Debian package 12.0-2+b1).
- Yosys 0.52, git `fee39a3284c90249e1d9684cf6944ffbbcbb8f90`.
- GCC 14.2.0 (Debian 14.2.0-19) for the reference C adapter.
- Python 3.12.14 for deterministic vector generation.

The cloud environment had no HDL tools preinstalled. Debian packages were
downloaded and extracted locally without system installation. The same
Makefile was used with `IVERILOG`, `VVP` and `YOSYS` overrides. The relocated
Icarus installation additionally needed its `-B` support-directory flag. These
paths are environment-specific and are not dependencies of the source package.

In this attached cloud workspace, the exact tool overrides are:

```sh
make test \
  IVERILOG='/workspace/work/tools/root/usr/bin/iverilog -B /workspace/work/tools/root/usr/lib/x86_64-linux-gnu/ivl' \
  VVP=/workspace/work/tools/root/usr/bin/vvp
make synth YOSYS=/workspace/work/tools/root/usr/bin/yosys
```

Captured simulation/reference output is in `../results/verification.log`;
the generic synthesis log is in `../results/synthesis.log`. A fresh synthesis
run writes its log and generic netlist under `build/`.

## Synthesis interpretation

`scripts/synth.ys` uses Yosys generic synthesis with `-noabc`, followed by
`check -assert`. It does not use a target FPGA, standard-cell library, physical
placement/routing, clock constraint or activity trace. Generic synthesis
reported 646 single-bit flip-flops, 325 mux cells, 324 AND cells, 390 NOT cells,
5 OR cells and 1,355 XOR cells across the hierarchy (3,045 generic cells).
These are synthesis sanity-check counts, **not** FPGA LUT counts or ASIC area.
The output hold register contributes 320 of the flip-flops and must be counted
consistently across later comparisons.

## Remaining acceptance gates

1. Full Ascon-AEAD128 controller and documented byte/stream interface.
2. Official standardized AEAD known-answer tests and randomized differential
   encryption/decryption, including partial blocks and authentication failures.
3. A defined authenticated-plaintext release policy and buffer bounds.
4. Device-specific synthesis/implementation and measured cycle accounting for
   complete messages, followed by activity-based power estimates or measurement.
5. Programmable LUT and memory-organized variants evaluated under the same
   interface and constraints, with a current literature review before novelty
   claims.

There is no FPGA bitstream, Fmax, measured power, AEAD-conformance or physical
PIM result in this milestone.
