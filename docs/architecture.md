# ASCON accelerator: permutation baseline

## Scope and claim boundary

This milestone implements the round function and the 8-round and 12-round
permutations used by standardized Ascon-AEAD128. The target is **NIST SP 800-232,
final, August 2025**, rather than the older Ascon-128 or Ascon-128a byte interface.
The round engine is a conventional iterative accelerator with registers and a
Boolean datapath. It is not an implementation of processing inside a memory
array, and no physical PIM, energy-saving, novelty, side-channel resistance, or
complete AEAD-conformance claim follows from this milestone.

Full authenticated encryption/decryption, padding, key/nonce loading, associated
data processing, tag generation/verification, and a streaming byte interface are
later milestones. Hash/XOF support is an optional extension.

## State layout

The permutation state consists of five unsigned 64-bit integers `x0` through
`x4`. The RTL port packs these words as `{x0, x1, x2, x3, x4}`:

| RTL slice | Numeric state word |
| --- | --- |
| `state_i[319:256]` | `x0` |
| `state_i[255:192]` | `x1` |
| `state_i[191:128]` | `x2` |
| `state_i[127:64]` | `x3` |
| `state_i[63:0]` | `x4` |

The same packing applies to `state_o` and test-vector hex strings. Each 16-digit
word in a vector is its ordinary numeric hexadecimal representation, most
significant digit first. This is an internal word convention, not an external
serialized byte sequence.

NIST Appendix A uses little-endian byte ordering: byte 0 of the future serialized
state is `x0[7:0]`, byte 1 is `x0[15:8]`, and byte 8 is `x1[7:0]`. For example,
bytes `00 01 02 03 04 05 06 07` load numeric `x0 = 64'h0706050403020100`.
Do not treat the 80-digit internal packed hex value as the serialized byte stream.
No byte-order conversion is performed inside the permutation engine.

## Round function

Every round applies the three layers in this order:

1. XOR the 8-bit round constant into the least significant byte of `x2`.
2. Apply the standard 5-bit S-box to each of the 64 columns
   `{x0[j], x1[j], x2[j], x3[j], x4[j]}` in parallel.
3. Apply the word-specific linear diffusion below.

The S-box table from NIST Table 6, indexed by the 5-bit column with `x0[j]` as
its most significant bit and `x4[j]` as its least significant bit, is:

```text
input:  00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f
output: 04 0b 1f 14 1a 15 09 02 1b 05 08 12 1d 03 06 1c
input:  10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f
output: 1e 13 07 0e 00 0d 11 18 10 0c 01 19 16 0a 0f 17
```

The baseline realizes the substitution with Boolean operations, not a
runtime-programmable table. Nonlinear intermediate values must be computed from
the same pre-update state; sequentially overwriting an operand changes the S-box.

For a substituted word `w`, diffusion is `w ^ rotr(w, a) ^ rotr(w, b)`:

| Word | Right rotation `a` | Right rotation `b` |
| --- | ---: | ---: |
| `x0` | 19 | 28 |
| `x1` | 61 | 39 |
| `x2` | 1 | 6 |
| `x3` | 10 | 17 |
| `x4` | 7 | 41 |

These are circular rotations of unsigned 64-bit values, not shifts with zero
fill. Both rotations use the original substituted word.

## Round schedule

NIST defines permutations of up to 16 rounds. This engine exposes only the two
required for Ascon-AEAD128. Our round index 0 through 11 labels the p12 schedule;
it is not the index of NIST's full 16-entry constant table.

```text
local index:  0  1  2  3  4  5  6  7  8  9 10 11
constant:    f0 e1 d2 c3 b4 a5 96 87 78 69 5a 4b
p12:         ^--------------------------------^
p8:                      ^--------------------^
```

In particular, p8 begins with `b4`, not `f0`. Each permutation round has a
different constant. All constants are applied to `x2[7:0]` without bit reversal.

## RTL blocks and transaction protocol

`ascon_round` is combinational, with inputs `state_i[319:0]` and
`round_constant_i[7:0]`, and output `state_o[319:0]`.

`ascon_permutation` reuses one round datapath and stores its intermediate state.
It has clock `clk_i`, asynchronous active-low reset `rst_ni`, request `start_i`,
mode `p8_i` (1 for p8, 0 for p12), input state `state_i`, status `ready_o`,
`busy_o`, and `done_o`, and completed state `state_o`.

- A request is accepted on a rising edge where `start_i && ready_o` is true.
  Acceptance captures the entire input state and the mode. It does not execute
  the first round on that edge.
- `ready_o = !busy_o`. Requests arriving while busy are ignored, including on
  the edge that completes the final round. Inputs may change while busy.
- Each following rising edge executes one round. Completion occurs 8 or 12
  clock periods after acceptance. On that edge, the result updates, `busy_o`
  becomes 0, and `done_o` becomes 1.
- `done_o` lasts one cycle. The output holds the last completed result through
  idle time and a subsequent computation. There is no output backpressure.
- The next request can be accepted at the rising edge immediately following
  completion. The minimum request-acceptance interval is therefore 9 clocks for
  p8 and 13 clocks for p12, including the load cycle.
- Holding `start_i` high requests another transaction whenever the engine next
  becomes ready. The source must lower it if only one transaction is intended.
- Reset clears state, result and status, cancels an operation in flight, and
  leaves the engine ready. Reset deassertion must satisfy the target device's
  reset-release timing requirements; integration should synchronize its release.

For example, a p8 accepted at edge 0 computes rounds at edges 1 through 8,
raises `done_o` at edge 8, and may accept the next request at edge 9.

## Verification and completion criteria

The milestone requires comparison with an independently obtained, pinned
standardized upstream C implementation, not only a model translated from the
RTL. Record source revision, vector-generation command and deterministic seed.
Check each round constant, p8/p12, zero and all-one states, varied bit patterns,
and randomized states. Include checks for correct S-box bit ordering and
rotation direction.

Control checks cover precise cycle count, input/mode capture, ignored requests
while busy, earliest subsequent acceptance, held requests, result retention,
single-cycle completion, and reset both while idle and during a permutation.
Passing permutation tests does not establish complete AEAD correctness.

Later AEAD verification must exercise standard known-answer vectors and
randomized differential encryption/decryption; zero-length and partial messages
and associated data; altered key, nonce, associated data, ciphertext and tag;
and streaming stalls. The AEAD interface must either withhold plaintext until
successful authentication or provide an explicit untrusted-output contract
that prevents unauthenticated data from being used as verified plaintext.

## Research variants and fair evaluation

Start with this conventional iterative baseline. Then compare a programmable
LUT S-box implementation using the same state layout, followed by a precisely
specified memory-organized LUT architecture. State where data lives, which
operations execute in or near memory, and how every transfer occurs. A
memory-based table or FPGA LUT alone does not demonstrate physical PIM.

Use matched interfaces, supported functions, reset behavior, constraints,
technology/device, tool versions and flow settings. Report primitive resource
counts and memory usage, timing after implementation, cycles, initiation
interval, and message-level latency/throughput. Do not equate permutation
throughput with payload throughput: AEAD adds initialization, finalization,
padding and associated-data work. Distinguish independent messages from the
dependent blocks within one message.

Power/energy comparisons need a documented activity trace, frequency,
voltage/temperature assumptions, and a common boundary including memory,
configuration, communication and control. Separate estimated from measured
power, and dynamic from static power. The 320-bit ASCON state already fits in
registers, so any memory-locality advantage is a hypothesis to measure.
Use ablations to isolate programmability, resource sharing and interconnect
cost. Synthesis alone provides neither energy results nor physical PIM proof.

## Sources

- NIST SP 800-232, final (August 2025): Sections 3.1-3.4 and Tables 5-6 for the
  permutation; Section 4 for AEAD; Appendix A for byte/state representation.
  <https://doi.org/10.6028/NIST.SP.800-232>
  <https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-232.pdf>
- Standardized Ascon reference and optimized C implementations:
  <https://github.com/ascon/ascon-c>. The bundled reference provenance identifies
  the exact revision used for test vectors.

The standard was read directly for this specification. A systematic review of
ASCON hardware and memory-compute literature remains necessary before making a
publication novelty claim.
