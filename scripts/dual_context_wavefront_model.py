#!/usr/bin/env python3
"""Cycle model for a mode-tagged, dual-context GS-MDC pipeline.

The model intentionally tracks ownership and valid timing rather than modular
arithmetic.  It proves that two independent post-BFU reorder contexts allow a
new transform frame every N/2 accepted input cycles while the previous frame
is still flushing through later stages.
"""

from __future__ import annotations

import argparse
from collections import deque
from dataclasses import dataclass


@dataclass(frozen=True)
class Token:
    frame: int
    sample: int
    mode: str
    branch: str


class QualifiedDelay:
    def __init__(self, depth: int) -> None:
        self.depth = depth
        # dout is the registered output, so only DEPTH-1 older entries remain
        # behind it. This matches delay_memory's RAM_DEPTH=DEPTH-1 scheme and
        # the shift implementation observed between clock edges.
        self.pipe: deque[Token | None] = deque([None] * max(depth - 1, 0))
        self.dout: Token | None = None

    def advance(self, value: Token | None) -> None:
        if self.depth == 0:
            self.dout = value
            return
        self.pipe.append(value)
        self.dout = self.pipe.popleft()


class ReorderContext:
    def __init__(self, depth: int, pairs: int, context_id: int) -> None:
        self.depth = depth
        self.pairs = pairs
        self.context_id = context_id
        self.reorder_count = 0
        self.flush_count = 0
        self.flushing = False
        self.fifo_a = QualifiedDelay(depth)
        self.fifo_b = QualifiedDelay(depth)
        self.active_frame: int | None = None
        self.last_tag: tuple[int, str] | None = None

    def step(
        self, bf_pair: tuple[Token, Token] | None
    ) -> tuple[Token, Token] | None:
        if self.depth == 0:
            return bf_pair

        if bf_pair is not None and self.flushing:
            raise AssertionError(
                f"context {self.context_id} reused while still flushing frame "
                f"{self.active_frame}"
            )

        bf_u = bf_pair[0] if bf_pair is not None else None
        bf_v = bf_pair[1] if bf_pair is not None else None
        if bf_pair is not None:
            tag = (bf_u.frame, bf_u.mode)
            if self.reorder_count == 0:
                if self.active_frame is not None:
                    raise AssertionError(
                        f"context {self.context_id} starts frame {bf_u.frame} "
                        f"before frame {self.active_frame} is released"
                    )
                self.active_frame = bf_u.frame
                self.last_tag = tag
            elif tag != self.last_tag:
                raise AssertionError(
                    f"context {self.context_id} tag changed within a frame"
                )

        phase = (self.reorder_count // self.depth) & 1
        output: tuple[Token, Token] | None = None
        if self.flushing:
            if self.fifo_b.dout is None or self.fifo_a.dout is None:
                raise AssertionError("flush observed an invalid delayed token")
            output = (self.fifo_b.dout, self.fifo_a.dout)
        elif bf_pair is not None and phase:
            if self.fifo_b.dout is None:
                raise AssertionError("phase-1 output observed an empty FIFO_B")
            output = (self.fifo_b.dout, bf_u)
        elif (
            bf_pair is not None
            and not phase
            and self.reorder_count >= 2 * self.depth
        ):
            if self.fifo_b.dout is None or self.fifo_a.dout is None:
                raise AssertionError("phase-0 output observed an empty delay")
            output = (self.fifo_b.dout, self.fifo_a.dout)

        advance = bf_pair is not None or self.flushing
        if advance:
            fifo_a_in = None if self.flushing else bf_v
            if self.flushing:
                fifo_b_in = None
            elif phase:
                fifo_b_in = self.fifo_a.dout
            else:
                fifo_b_in = bf_u
            self.fifo_a.advance(fifo_a_in)
            self.fifo_b.advance(fifo_b_in)

        if self.flushing:
            if self.flush_count == self.depth - 1:
                self.flush_count = 0
                self.flushing = False
                self.active_frame = None
                self.last_tag = None
            else:
                self.flush_count += 1
        elif bf_pair is not None:
            if self.reorder_count == self.pairs - 1:
                self.reorder_count = 0
                self.flush_count = 0
                self.flushing = True
            else:
                self.reorder_count += 1

        return output


class DualContextStage:
    def __init__(self, stage_id: int, depth: int, pairs: int, bf_latency: int) -> None:
        self.stage_id = stage_id
        self.depth = depth
        self.bf_pipe: deque[tuple[Token, Token] | None] = deque(
            [None] * bf_latency
        )
        self.contexts = [
            ReorderContext(depth, pairs, 0),
            ReorderContext(depth, pairs, 1),
        ]
        self.output_collisions = 0

    def step(
        self, input_pair: tuple[Token, Token] | None
    ) -> tuple[Token, Token] | None:
        self.bf_pipe.append(input_pair)
        bf_pair = self.bf_pipe.popleft()

        outputs: list[tuple[Token, Token]] = []
        for context_id, context in enumerate(self.contexts):
            selected = None
            if bf_pair is not None and (bf_pair[0].frame & 1) == context_id:
                selected = bf_pair
            context_output = context.step(selected)
            if context_output is not None:
                outputs.append(context_output)

        if len(outputs) > 1:
            self.output_collisions += 1
            frames = [pair[0].frame for pair in outputs]
            raise AssertionError(
                f"stage {self.stage_id} output collision between frames {frames}"
            )
        return outputs[0] if outputs else None


def stage_depth(logn: int, stage_id: int) -> int:
    if stage_id == logn - 1:
        return 0
    return 1 << (logn - stage_id - 2)


def run_model(n: int, frames: int, bf_latency: int) -> dict[str, object]:
    if n < 4 or n & (n - 1):
        raise ValueError("N must be a power of two and at least 4")
    logn = n.bit_length() - 1
    pairs = n // 2
    stages = [
        DualContextStage(s, stage_depth(logn, s), pairs, bf_latency)
        for s in range(logn)
    ]

    total_inputs = frames * pairs
    max_cycles = total_inputs + frames * pairs + logn * (bf_latency + pairs) + 100
    outputs: dict[int, list[int]] = {frame: [] for frame in range(frames)}
    output_cycles: dict[int, list[int]] = {frame: [] for frame in range(frames)}

    for cycle in range(max_cycles):
        input_pair = None
        if cycle < total_inputs:
            frame = cycle // pairs
            sample = cycle % pairs
            mode = "NTT" if frame % 2 == 0 else "INTT"
            input_pair = (
                Token(frame, sample, mode, "u"),
                Token(frame, sample, mode, "v"),
            )

        pair = input_pair
        for stage in stages:
            pair = stage.step(pair)

        if pair is not None:
            frame0 = pair[0].frame
            frame1 = pair[1].frame
            if frame0 != frame1:
                raise AssertionError(
                    f"final output mixed frames {frame0} and {frame1} at cycle {cycle}"
                )
            outputs[frame0].append(pair[0].sample)
            output_cycles[frame0].append(cycle)

        if all(len(items) == pairs for items in outputs.values()):
            break
    else:
        raise AssertionError("model timed out before all frames completed")

    for frame in range(frames):
        if len(outputs[frame]) != pairs:
            raise AssertionError(
                f"frame {frame} produced {len(outputs[frame])}/{pairs} output pairs"
            )
        cycles = output_cycles[frame]
        if cycles[-1] - cycles[0] + 1 != pairs:
            raise AssertionError(f"frame {frame} output contains bubbles")
        if frame and cycles[0] != output_cycles[frame - 1][-1] + 1:
            raise AssertionError(
                f"frames {frame - 1}/{frame} are not contiguous at the output"
            )

    return {
        "n": n,
        "frames": frames,
        "pairs": pairs,
        "bf_latency": bf_latency,
        "first_output": output_cycles[0][0],
        "last_output": output_cycles[frames - 1][-1],
        "frame_starts": [output_cycles[f][0] for f in range(frames)],
        "frame_ends": [output_cycles[f][-1] for f in range(frames)],
        "stage_depths": [stage.depth for stage in stages],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--n", type=int, default=4096)
    parser.add_argument("--frames", type=int, default=4)
    parser.add_argument("--bf-latency", type=int, default=15)
    args = parser.parse_args()

    result = run_model(args.n, args.frames, args.bf_latency)
    print("dual-context wavefront schedule: PASS")
    for key, value in result.items():
        print(f"{key}: {value}")


if __name__ == "__main__":
    main()
