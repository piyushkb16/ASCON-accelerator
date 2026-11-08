# ASCON accelerator — milestone 1

Conventional, iterative **Ascon-AEAD128 permutation baseline** for the
LUT-based near-memory architecture research project. Implements the round
function and p[8]/p[12] permutation engine in synthesizable SystemVerilog.
The full authenticated-encryption controller is the next milestone.

## Run

Requires Icarus Verilog (tested with 12.0), Make, and optionally Python 3 + a C99
compiler for regenerating/checking vectors. Yosys is optional for synthesis.
Run commands from this directory:

```sh
make test           # RTL against committed C-reference vectors + control tests
make check-vectors  # rebuild pinned C oracle and check committed vectors offline
make synth          # generic synthesis/check, reports in build/
```

Use `make IVERILOG=/path/to/iverilog VVP=/path/to/vvp` or
`make synth YOSYS=/path/to/yosys` for non-default installations.
`make vectors` deliberately regenerates the golden vectors; normal tests do
not silently change expected results. `make clean` removes generated build files.

## Contents

| Path | Purpose |
| --- | --- |
| `rtl/ascon_round.sv` | One combinational round: constant, S-box, diffusion |
| `rtl/ascon_permutation.sv` | One reused round datapath; p[8]/p[12] controller |
| `tb/tb_ascon.sv` | Differential datapath and transaction/reset tests |
| `reference/` | Pinned upstream C sources, license, oracle and provenance |
| `vectors/` | Deterministic round/permutation cases and manifest |
| `scripts/` | Vector generation and generic synthesis |
| `docs/architecture.md` | State mapping, timing and research scope |
| `docs/verification.md` | Verified results and remaining acceptance gates |

## Interface in brief

`state_i` and `state_o` pack `{x0, x1, x2, x3, x4}` as numeric 64-bit words.
This concatenation is an internal interface, not an external message byte
serialization. SP 800-232 uses little-endian byte loading at the future AEAD
boundary; byte 0 of x0 maps to `x0[7:0]`.

A transaction is accepted on a rising edge with `start_i && ready_o`.
`p8_i=1` selects 8 rounds; `p8_i=0` selects 12. Completion occurs 8 or 12
clock periods after acceptance, with a one-cycle `done_o` pulse. A new request
can be accepted at the following rising edge (initiation interval 9 or 13
cycles for consecutive requests). Requests while busy, including at the
completion edge, are ignored. Hold result until the next completion. There is
no output backpressure; the caller must capture each completed result.

Reset is asynchronous active low and aborts a running transaction. The
integrator must deassert reset synchronously to the target clock. See the full
specification before integrating.

## Scope and next steps

This is conventional logic, with 64 parallel bit-sliced S-boxes and fixed
rotation wiring. It is not a programmable LUT core or a physical PIM device.
It does not yet accept keys, nonces, AD or messages, and cannot generate or
verify authentication tags. Permutation verification is not full AEAD KAT
coverage, cryptographic validation, or side-channel certification.

Next: add the Ascon-AEAD128 byte interface, initialization, AD/message padding,
domain separation, encryption/decryption and final tag verification; compare
complete transactions against standardized known-answer tests. Define a
bounded authenticated-plaintext release policy before exposing decryption
outputs. Then measure the baseline on a selected FPGA and implement LUT and
near-memory variants under matched constraints.

The baseline has an extra 320-bit result register to hold the previous output
during a new operation. Its area cost must be counted consistently when
comparing architectures; future internal AEAD integration may use a different
handshake to remove that copy.

## Sources

- [NIST SP 800-232 (final, August 2025)](https://csrc.nist.gov/pubs/sp/800/232/final)
- [ascon/ascon-c](https://github.com/ascon/ascon-c), pinned details in
  [reference/README.md](reference/README.md)

Third-party reference code retains its CC0 notices. Licensing and authorship
for the new research RTL should be decided before public release.
