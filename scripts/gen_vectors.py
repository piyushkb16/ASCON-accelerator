#!/usr/bin/env python3
"""Generate deterministic vectors with the pinned upstream C implementation.

No ASCON algorithm is reimplemented in Python. Run from any working directory.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SEED = 0x800232
COMMIT = "446347f21b209f3921c65ece70027c366cbe1693"


def inputs():
    states = [0, (1 << 320) - 1, int.from_bytes(bytes(range(40)), "big")]
    states += [1 << bit for bit in range(320)]
    # Every one of the 32 five-bit input combinations is repeated across lanes.
    # The round constant affects only the low eight lanes of word x2.
    for pattern in range(32):
        state = 0
        for word in range(5):
            state = (state << 64) | (
                ((1 << 64) - 1) if (pattern >> (4 - word)) & 1 else 0
            )
        states.append(state)
    rng = random.Random(SEED)
    states += [rng.getrandbits(320) for _ in range(256)]
    return states


def expected(executable, mode, cases):
    request = "".join(f"{selector} {state:080x}\n" for selector, state in cases)
    process = subprocess.run(
        [str(executable), mode], input=request, text=True,
        capture_output=True, check=True,
    )
    outputs = process.stdout.splitlines()
    if len(outputs) != len(cases):
        raise RuntimeError("C oracle returned the wrong vector count")
    for output in outputs:
        if len(output) != 80:
            raise RuntimeError("C oracle returned an invalid state width")
        int(output, 16)
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify committed files")
    args = parser.parse_args()
    states = inputs()
    vector_dir = ROOT / "vectors"
    vector_dir.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ascon-oracle-") as tmp:
        executable = Path(tmp) / "oracle"
        subprocess.run(
            shlex.split(os.environ.get("CC", "cc")) + [
                "-std=c99", "-O2", "-Wall", "-Wextra", "-Werror",
                str(ROOT / "reference/oracle.c"), "-o", str(executable),
            ], check=True,
        )
        manifest = {
            "upstream_commit": COMMIT,
            "seed": hex(SEED),
            "state_count": len(states),
            "state_packing": "{x0,x1,x2,x3,x4}; five 16-hex-digit numeric words",
            "oracle": "unmodified upstream ref ROUND/P8/P12 compiled as C99",
            "vectors": {},
        }
        for mode, selectors in (("round", range(12)), ("permutation", (8, 12))):
            cases = [(selector, state) for selector in selectors for state in states]
            results = expected(executable, mode, cases)
            contents = "".join(
                f"{selector} {state:080x} {result}\n"
                for (selector, state), result in zip(cases, results)
            )
            path = vector_dir / f"{mode}.txt"
            if args.check:
                if path.read_text() != contents:
                    raise SystemExit(f"FAIL: {path.name} differs from upstream C")
            else:
                path.write_text(contents)
            manifest["vectors"][path.name] = {
                "count": len(cases),
                "sha256": hashlib.sha256(contents.encode()).hexdigest(),
            }
            print(f"PASS: {len(cases)} {mode} vectors match pinned upstream C")
        manifest_text = json.dumps(manifest, indent=2) + "\n"
        path = vector_dir / "manifest.json"
        if args.check:
            if path.read_text() != manifest_text:
                raise SystemExit("FAIL: manifest.json differs")
        else:
            path.write_text(manifest_text)


if __name__ == "__main__":
    main()
