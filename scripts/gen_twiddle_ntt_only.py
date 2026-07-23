#!/usr/bin/env python3
"""Generate independent NTT-only stage-local Montgomery twiddle tables."""

from pathlib import Path

from gen_params import LOGN, N, QW
from gen_twiddle_stage_local import read_words, stage_table


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    mem_dir = repo_root / "mem"
    total_words = 0

    for stage in range(LOGN):
        distance = 1 << (LOGN - stage - 1)
        ntt_words = stage_table(stage, inverse=False)
        combined_words = read_words(mem_dir / f"twiddle_stage{stage:02d}.mem")

        if len(ntt_words) != distance:
            raise RuntimeError(f"stage {stage} generated depth mismatch")
        if combined_words[:distance] != ntt_words:
            raise RuntimeError(f"stage {stage} does not match combined NTT table")

        output = mem_dir / f"twiddle_ntt_stage{stage:02d}.mem"
        output.write_text(
            "".join(f"{word:0{QW // 4}x}\n" for word in ntt_words),
            encoding="ascii",
        )
        total_words += distance
        print(f"wrote {output.name}: words={distance}")

    if total_words != N - 1:
        raise RuntimeError(f"unexpected NTT-only word count {total_words}")
    print(f"NTT_ONLY_TWIDDLE_GENERATION=PASS total_words={total_words}")


if __name__ == "__main__":
    main()
