#!/usr/bin/env python3
"""Generate deterministic multi-job vectors for the batch wavefront RTL."""

from __future__ import annotations

import argparse
import random
from pathlib import Path

from gen_params import N, find_parameters
from ref_ntt import negacyclic_mul, to_mont

Q = find_parameters()["Q"]


def write_mem(path: Path, values: list[int]) -> None:
    path.write_text("".join(f"{value:016x}\n" for value in values), encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs", type=int, default=6)
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "reports"
        / "batch_wavefront_scheduler"
        / "vectors",
    )
    args = parser.parse_args()
    if args.jobs < 3:
        raise ValueError("at least three jobs are required to exercise bank reuse")

    rng = random.Random(0x42415443484D4443)
    flat_a: list[int] = []
    flat_b: list[int] = []
    flat_golden: list[int] = []

    for job in range(args.jobs):
        if job == args.jobs - 1:
            a = [0] * N
            b = [0] * N
            a[N - 1] = 1
            b[1] = 1
        else:
            a = [rng.randrange(Q) for _ in range(N)]
            b = [rng.randrange(Q) for _ in range(N)]

        golden = negacyclic_mul(a, b)
        if job == args.jobs - 1:
            assert golden[0] == Q - 1
            assert all(value == 0 for value in golden[1:])

        flat_a.extend(to_mont(value) for value in a)
        flat_b.extend(to_mont(value) for value in b)
        flat_golden.extend(to_mont(value) for value in golden)

    args.out.mkdir(parents=True, exist_ok=True)
    write_mem(args.out / "batch_input_a.mem", flat_a)
    write_mem(args.out / "batch_input_b.mem", flat_b)
    write_mem(args.out / "batch_golden.mem", flat_golden)
    (args.out / "manifest.txt").write_text(
        f"jobs={args.jobs}\nN={N}\nseed=0x42415443484D4443\n"
        f"directed_job={args.jobs - 1}\n",
        encoding="ascii",
    )
    print(
        f"wrote {args.jobs} batch jobs ({args.jobs - 1} random + 1 directed) "
        f"to {args.out}"
    )


if __name__ == "__main__":
    main()