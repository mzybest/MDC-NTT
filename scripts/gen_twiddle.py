#!/usr/bin/env python3
"""Generate stage-major Montgomery-domain GS twiddle ROM files."""

from pathlib import Path
from gen_params import N, LOGN, QW, find_parameters

P = find_parameters()
Q, R, OMEGA = P["Q"], 1 << QW, P["OMEGA"]


def table(inverse: bool) -> list[int]:
    root = pow(OMEGA, -1, Q) if inverse else OMEGA
    words = []
    for stage in range(LOGN):
        distance = 1 << (LOGN - stage - 1)
        step = N // (2 * distance)
        for k in range(N // 2):
            words.append(pow(root, (k % distance) * step, Q) * R % Q)
    return words


def main() -> None:
    out_dir = Path(__file__).resolve().parents[1] / "mem"
    out_dir.mkdir(exist_ok=True)
    for name, inverse in (("twiddle_ntt.mem", False), ("twiddle_intt.mem", True)):
        (out_dir / name).write_text(
            "".join(f"{x:016x}\n" for x in table(inverse)), encoding="ascii"
        )
        print(f"wrote {name}")


if __name__ == "__main__":
    main()
