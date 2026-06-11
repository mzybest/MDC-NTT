#!/usr/bin/env python3
"""Generate deterministic Montgomery-domain inputs and golden files."""

import random
from pathlib import Path
from gen_params import N, find_parameters
from ref_ntt import cyclic_mul, gs_ntt, to_mont

Q = find_parameters()["Q"]


def write_mem(path: Path, values: list[int]) -> None:
    path.write_text("".join(f"{x:016x}\n" for x in values), encoding="ascii")


def main() -> None:
    rng = random.Random(0x4D4443)
    a = [rng.randrange(Q) for _ in range(N)]
    b = [rng.randrange(Q) for _ in range(N)]
    out = Path(__file__).resolve().parents[1] / "mem"
    out.mkdir(exist_ok=True)
    write_mem(out / "input_a.mem", [to_mont(x) for x in a])
    write_mem(out / "input_b.mem", [to_mont(x) for x in b])
    write_mem(out / "golden_ntt_a.mem", [to_mont(x) for x in gs_ntt(a)])
    write_mem(out / "golden_result.mem", [to_mont(x) for x in cyclic_mul(a, b)])
    print("wrote deterministic test vectors")


if __name__ == "__main__":
    main()
