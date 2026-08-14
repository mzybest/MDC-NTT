#!/usr/bin/env python3
"""Prove that the fused Post factor equals scale followed by psi^-i."""

import random
from pathlib import Path

from gen_params import N, QW, find_parameters

P = find_parameters()
Q = P["Q"]
R = 1 << QW
R_INV = pow(R, -1, Q)


def mont(a: int, b: int) -> int:
    return (a * b * R_INV) % Q


def read_mem(path: Path) -> list[int]:
    return [int(line, 16) for line in path.read_text(encoding="ascii").splitlines()]


def main() -> None:
    mem_dir = Path(__file__).resolve().parents[1] / "mem"
    psi_inv = read_mem(mem_dir / "psi_inv.mem")
    fused = read_mem(mem_dir / "psi_inv_ninv.mem")
    if len(psi_inv) != N or len(fused) != N:
        raise RuntimeError("Post factor table depth mismatch")

    n_inv = pow(N, -1, Q)
    n_inv_mont = n_inv * R % Q
    for index, (psi_factor, fused_factor) in enumerate(zip(psi_inv, fused)):
        expected = psi_factor * n_inv % Q
        if fused_factor != expected:
            raise RuntimeError(f"factor mismatch at index {index}")

    rng = random.Random(0x445350)
    for _ in range(10000):
        x_mont = rng.randrange(Q)
        index = rng.randrange(N)
        explicit = mont(mont(x_mont, n_inv_mont), psi_inv[index])
        combined = mont(x_mont, fused[index])
        if explicit != combined:
            raise RuntimeError(f"Montgomery equivalence mismatch at index {index}")

    print(f"FUSED_POST_FACTOR_VALIDATION=PASS factors={N} random=10000")


if __name__ == "__main__":
    main()
