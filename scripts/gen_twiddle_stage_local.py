#!/usr/bin/env python3
"""Generate compact per-stage Montgomery-domain GS twiddle tables."""

from pathlib import Path

from gen_params import LOGN, N, QW, find_parameters
from gen_twiddle import table


P = find_parameters()
Q = P["Q"]
R = 1 << QW
OMEGA = P["OMEGA"]


def stage_table(stage: int, inverse: bool) -> list[int]:
    distance = 1 << (LOGN - stage - 1)
    root = pow(OMEGA, -1, Q) if inverse else OMEGA
    step = N // (2 * distance)
    return [pow(root, index * step, Q) * R % Q for index in range(distance)]


def read_words(path: Path) -> list[int]:
    return [int(line, 16) for line in path.read_text(encoding="ascii").splitlines()]


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    mem_dir = repo_root / "mem"
    legacy_ntt = read_words(mem_dir / "twiddle_ntt.mem")
    legacy_intt = read_words(mem_dir / "twiddle_intt.mem")
    generated_ntt = table(inverse=False)
    generated_intt = table(inverse=True)

    if legacy_ntt != generated_ntt or legacy_intt != generated_intt:
        raise RuntimeError("legacy twiddle files do not match scripts/gen_twiddle.py")

    full_stage_depth = N // 2
    total_words = 0
    for stage in range(LOGN):
        distance = 1 << (LOGN - stage - 1)
        offset = stage * full_stage_depth
        ntt_words = stage_table(stage, inverse=False)
        intt_words = stage_table(stage, inverse=True)

        if ntt_words != legacy_ntt[offset : offset + distance]:
            raise RuntimeError(f"stage {stage} NTT table mismatch")
        if intt_words != legacy_intt[offset : offset + distance]:
            raise RuntimeError(f"stage {stage} INTT table mismatch")

        words = ntt_words + intt_words
        output = mem_dir / f"twiddle_stage{stage:02d}.mem"
        output.write_text(
            "".join(f"{word:0{QW // 4}x}\n" for word in words),
            encoding="ascii",
        )
        total_words += len(words)
        print(
            f"wrote {output.name}: distance={distance}, "
            f"NTT={distance}, INTT={distance}, total={len(words)}"
        )

    legacy_words = 2 * LOGN * full_stage_depth
    print(
        f"stage-local total={total_words} words; legacy total={legacy_words} words; "
        f"compression={legacy_words / total_words:.3f}x"
    )


if __name__ == "__main__":
    main()
