# Golden permutation reference

The algorithm code in `upstream/` is copied **without modifications** from
[ascon/ascon-c](https://github.com/ascon/ascon-c), commit
[`446347f21b209f3921c65ece70027c366cbe1693`](https://github.com/ascon/ascon-c/tree/446347f21b209f3921c65ece70027c366cbe1693),
directory `crypto_aead/asconaead128/ref/`. The root upstream `LICENSE` is
retained in `upstream/LICENSE` (CC0-1.0). This repository identifies its current
algorithms as NIST SP 800-232 implementations. The retrieved source snapshot is
fully vendored, so no network access is needed to regenerate the vectors.

`oracle.c` is a local adapter that calls the actual upstream `ROUND`, `P8` and
`P12` functions. Python supplies test inputs and writes results; it does not
reimplement the ASCON round as the correctness oracle. This avoids comparing RTL
only against a matching local transcription of the same algorithm.

Run from the project root:

```sh
python3 scripts/gen_vectors.py
python3 scripts/gen_vectors.py --check
```

Requirements: Python 3 and a C99 compiler, selected by `CC` (default `cc`). The
temporary compiled executable is removed automatically. Vector hashes, upstream
commit, seed and case counts are recorded in `vectors/manifest.json`.

## Format and coverage

Both files contain data-only lines with three whitespace-delimited fields:

```text
selector input_state expected_state
```

Each state is 80 hexadecimal digits encoding numeric words as
`{x0,x1,x2,x3,x4}`, with x0 in bits `[319:256]` and x4 in bits `[63:0]`.
This text representation is **not** the message-byte serialization. In the
standardized AEAD algorithm, message bytes are loaded into each 64-bit word in
little-endian order; that boundary belongs to the later AEAD controller.

- `round.txt`: selectors 0–11 map to constants
  `f0 e1 d2 c3 b4 a5 96 87 78 69 5a 4b`.
- `permutation.txt`: selectors 8 and 12 invoke P8 and P12. P8 starts with constant
  `b4` (round index 4), not `f0`.

There are 611 input states: all-zero, all-one, a 40-byte ascending ramp, all 320
single-bit states, all 32 possible five-bit lane patterns repeated across the
64 bit lanes, and 256 deterministic random states with seed `0x800232`.
All states are tested at every round index (7,332 cases) and in both
permutations (1,222 cases). The round constant changes the low eight lanes of
x2; the other 56 lanes of each repeated-pattern state cover each S-box input
unchanged. These are **reference-derived permutation vectors**, not published
NIST AEAD known-answer tests. Passing them validates this milestone's
permutation core, not a complete AEAD implementation or NIST certification.

## Vendored-file SHA-256

```text
5537d4d10b76b81b6e8dfd8b644480a4b1efa332fbb0cdb61126c5be781ef7b4  LICENSE
c83217138b791c0e37ab1ab7bde216ed0392fc0c17bc2078f7454217bd4e1ea5  ascon.h
91cae918bdd5c365090afec02767916764e2c33e72a5d89348b96d20e0c7819e  constants.h
58ac28a23c4f310228e79dc18eb7608b62ba3abeedbc28e80d97eb7e3be5d8fb  permutations.h
bf59de3eb2e71c72f47d64c2cdee393fd3a1ca8337f0bd5636d41cca196f19d0  printstate.h
3ed06f5c6330b085952f6626e5df4a9ca598911f33b15b3ebc5d58dddb8fda11  round.h
```
