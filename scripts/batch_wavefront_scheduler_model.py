#!/usr/bin/env python3
"""Frame-level scheduler model for batched dual-context GS-MDC jobs.

The model separates three quantities that must not be conflated:

* one transform frame occupies the core input for N/2 cycles;
* B pointwise data makes C_INTT ready 4303 cycles after B starts for N=4096;
* a job bank cannot be reused until its C_INTT post-processing is complete.

It also feeds the generated frame schedule through the validated per-stage
dual-context token model.  This catches context reuse, flush, frame mixing,
and output-collision errors rather than validating only a high-level table.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from enum import Enum

from dual_context_wavefront_model import DualContextStage, Token, stage_depth


class Role(str, Enum):
    A_NTT = "A_NTT"
    B_NTT = "B_NTT"
    C_INTT = "C_INTT"

    @property
    def mode(self) -> str:
        return "INTT" if self is Role.C_INTT else "NTT"


@dataclass
class Job:
    job_id: int
    bank: int
    state: str = "A_READY"
    release: int = 0
    a_start: int | None = None
    b_start: int | None = None
    c_start: int | None = None
    result_done: int | None = None


@dataclass(frozen=True)
class FrameLaunch:
    sequence: int
    job_id: int
    bank: int
    role: Role
    context: int
    ready_at: int
    start: int
    pairs: int

    @property
    def end(self) -> int:
        return self.start + self.pairs - 1


@dataclass(frozen=True)
class ScheduleResult:
    jobs: tuple[Job, ...]
    launches: tuple[FrameLaunch, ...]
    idle_cycles: int
    core_span: int
    start_ii_steady: float
    completion_ii_steady: float
    core_utilization_steady: float
    current_load_limited_ii: float
    dual_load_limited_ii: float


def steady_average(values: list[int], trim: int) -> float:
    """Average an even number of middle intervals.

    The greedy scheduler has a two-job completion cadence. Trimming startup
    and batch-drain jobs, then averaging an even interval count, reports the
    repeating steady state without hiding finite-batch idle cycles.
    """
    available = len(values) - 1 - 2 * trim
    if available < 2:
        return 0.0
    count = available - (available & 1)
    return (values[trim + count] - values[trim]) / count


def build_schedule(
    *,
    pairs: int,
    job_count: int,
    buffers: int,
    result_latency: int,
) -> ScheduleResult:
    if buffers < 1:
        raise ValueError("buffers must be at least one")
    if job_count < buffers:
        raise ValueError("job_count must be at least buffers")

    jobs: list[Job] = []
    active: list[Job | None] = [None] * buffers
    launches: list[FrameLaunch] = []
    next_job_id = 0
    core_free = 0

    def release_completed_banks(now: int) -> None:
        nonlocal next_job_id
        for bank, job in enumerate(active):
            if (
                job is not None
                and job.state == "C_RUNNING"
                and job.result_done is not None
                and job.result_done <= now
            ):
                active[bank] = None
            if active[bank] is None and next_job_id < job_count:
                new_job = Job(job_id=next_job_id, bank=bank, release=now)
                jobs.append(new_job)
                active[bank] = new_job
                next_job_id += 1

    release_completed_banks(0)
    c_launches = 0
    while c_launches < job_count:
        release_completed_banks(core_free)

        candidates: list[tuple[int, int, Job, Role]] = []
        for job in active:
            if job is None or job.release > core_free:
                continue
            if job.state == "C_READY":
                candidates.append((0, job.job_id, job, Role.C_INTT))
            elif job.state == "B_READY":
                candidates.append((1, job.job_id, job, Role.B_NTT))
            elif job.state == "A_READY":
                candidates.append((2, job.job_id, job, Role.A_NTT))

        if not candidates:
            future_events: list[int] = []
            for job in active:
                if job is None:
                    continue
                if job.state in ("B_READY", "C_READY") and job.release > core_free:
                    future_events.append(job.release)
                if (
                    job.state == "C_RUNNING"
                    and job.result_done is not None
                    and job.result_done > core_free
                ):
                    future_events.append(job.result_done)
            if not future_events:
                raise AssertionError("scheduler deadlocked without a future event")
            core_free = min(future_events)
            continue

        _, _, job, role = min(candidates)
        sequence = len(launches)
        launch = FrameLaunch(
            sequence=sequence,
            job_id=job.job_id,
            bank=job.bank,
            role=role,
            context=sequence & 1,
            ready_at=job.release,
            start=core_free,
            pairs=pairs,
        )
        launches.append(launch)

        if role is Role.A_NTT:
            job.a_start = core_free
            job.state = "B_READY"
            job.release = core_free + pairs
        elif role is Role.B_NTT:
            if job.a_start is None:
                raise AssertionError("B_NTT launched before A_NTT")
            job.b_start = core_free
            job.state = "C_READY"
            job.release = core_free + result_latency
        else:
            if job.b_start is None:
                raise AssertionError("C_INTT launched before B_NTT")
            job.c_start = core_free
            job.result_done = core_free + result_latency
            job.state = "C_RUNNING"
            c_launches += 1

        core_free += pairs

    jobs.sort(key=lambda job: job.job_id)
    launches.sort(key=lambda launch: launch.sequence)
    validate_dependencies(jobs, launches, pairs, result_latency)

    core_span = launches[-1].end - launches[0].start + 1
    busy_cycles = len(launches) * pairs
    idle_cycles = core_span - busy_cycles
    starts = [job.a_start for job in jobs]
    completions = [job.result_done for job in jobs]
    if any(value is None for value in starts + completions):
        raise AssertionError("incomplete job timing record")
    start_values = [int(value) for value in starts]
    completion_values = [int(value) for value in completions]
    start_ii = steady_average(start_values, buffers)
    completion_ii = steady_average(completion_values, buffers)
    steady_utilization = 3 * pairs / start_ii

    return ScheduleResult(
        jobs=tuple(jobs),
        launches=tuple(launches),
        idle_cycles=idle_cycles,
        core_span=core_span,
        start_ii_steady=start_ii,
        completion_ii_steady=completion_ii,
        core_utilization_steady=steady_utilization,
        current_load_limited_ii=max(start_ii, 2 * 2 * pairs),
        dual_load_limited_ii=max(start_ii, 2 * pairs),
    )


def validate_dependencies(
    jobs: list[Job],
    launches: list[FrameLaunch],
    pairs: int,
    result_latency: int,
) -> None:
    previous_by_bank: dict[int, Job] = {}
    for job in jobs:
        assert job.a_start is not None
        assert job.b_start is not None
        assert job.c_start is not None
        assert job.result_done is not None
        if job.b_start < job.a_start + pairs:
            raise AssertionError(f"job {job.job_id} overlaps A_NTT and B_NTT")
        if job.c_start < job.b_start + result_latency:
            raise AssertionError(f"job {job.job_id} launches C_INTT before C is ready")
        previous = previous_by_bank.get(job.bank)
        if previous is not None and job.a_start < int(previous.result_done):
            raise AssertionError(
                f"bank {job.bank} reused by job {job.job_id} before job "
                f"{previous.job_id} completed"
            )
        previous_by_bank[job.bank] = job

    for earlier, later in zip(launches, launches[1:]):
        if later.start <= earlier.end:
            raise AssertionError("two transform frames overlap at the core input")
        if later.context == earlier.context:
            raise AssertionError("adjacent frames did not alternate reorder contexts")


def validate_dual_context_pipeline(
    *,
    n: int,
    bf_latency: int,
    launches: tuple[FrameLaunch, ...],
) -> dict[str, object]:
    logn = n.bit_length() - 1
    pairs = n // 2
    stage_first_offset = sum(stage_depth(logn, s) for s in range(logn))
    stage_first_offset += logn * bf_latency
    stages = [
        DualContextStage(s, stage_depth(logn, s), pairs, bf_latency)
        for s in range(logn)
    ]
    by_start = {launch.start: launch for launch in launches}
    active_launch: FrameLaunch | None = None
    outputs: dict[int, list[int]] = {
        launch.sequence: [] for launch in launches
    }
    output_cycles: dict[int, list[int]] = {
        launch.sequence: [] for launch in launches
    }
    last_input = launches[-1].end
    max_cycles = last_input + 2 * pairs + logn * (bf_latency + pairs) + 100

    for cycle in range(max_cycles):
        if cycle in by_start:
            if active_launch is not None:
                raise AssertionError("new frame started before prior frame input ended")
            active_launch = by_start[cycle]

        input_pair = None
        if active_launch is not None:
            sample = cycle - active_launch.start
            if 0 <= sample < pairs:
                token0 = Token(
                    active_launch.sequence,
                    sample,
                    active_launch.role.mode,
                    "u",
                )
                token1 = Token(
                    active_launch.sequence,
                    sample,
                    active_launch.role.mode,
                    "v",
                )
                input_pair = (token0, token1)
            if sample == pairs - 1:
                active_launch = None

        pair = input_pair
        for stage in stages:
            pair = stage.step(pair)

        if pair is not None:
            frame0 = pair[0].frame
            frame1 = pair[1].frame
            if frame0 != frame1:
                raise AssertionError(
                    f"final output mixed frames {frame0} and {frame1}"
                )
            outputs[frame0].append(pair[0].sample)
            output_cycles[frame0].append(cycle)

        if all(len(items) == pairs for items in outputs.values()):
            break
    else:
        raise AssertionError("dual-context pipeline validation timed out")

    for launch in launches:
        cycles = output_cycles[launch.sequence]
        if len(cycles) != pairs:
            raise AssertionError(
                f"frame {launch.sequence} emitted {len(cycles)}/{pairs} pairs"
            )
        if cycles[-1] - cycles[0] + 1 != pairs:
            raise AssertionError(f"frame {launch.sequence} output contains bubbles")
        expected_first = launch.start + stage_first_offset
        if cycles[0] != expected_first:
            raise AssertionError(
                f"frame {launch.sequence} first output {cycles[0]} != "
                f"expected {expected_first}"
            )

    return {
        "pipeline_frames": len(launches),
        "first_stage_output": output_cycles[launches[0].sequence][0],
        "last_stage_output": output_cycles[launches[-1].sequence][-1],
        "output_collisions": sum(stage.output_collisions for stage in stages),
    }


def print_result(buffers: int, result: ScheduleResult, pipeline: dict[str, object]) -> None:
    print(f"\n=== {buffers} job buffer(s) ===")
    print("seq  start    end  ctx  bank  job  role    ready  wait")
    for launch in result.launches[:24]:
        print(
            f"{launch.sequence:3d} {launch.start:6d} {launch.end:6d} "
            f" {launch.context:1d}    {launch.bank:1d}  {launch.job_id:3d} "
            f"{launch.role.value:7s} {launch.ready_at:6d} "
            f"{launch.start - launch.ready_at:5d}"
        )
    print(f"core_span_cycles: {result.core_span}")
    print(f"finite_batch_idle_cycles: {result.idle_cycles}")
    print(f"finite_batch_utilization: {100.0 * (1 - result.idle_cycles / result.core_span):.4f}%")
    print(f"steady_job_start_ii: {result.start_ii_steady:.3f}")
    print(f"steady_completion_ii: {result.completion_ii_steady:.3f}")
    print(f"steady_core_utilization: {100.0 * result.core_utilization_steady:.4f}%")
    print(f"current_single_lane_load_limited_ii: {result.current_load_limited_ii:.3f}")
    print(f"dual_A_B_load_limited_ii: {result.dual_load_limited_ii:.3f}")
    for key, value in pipeline.items():
        print(f"{key}: {value}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--n", type=int, default=4096)
    parser.add_argument("--jobs", type=int, default=60)
    parser.add_argument("--buffers", type=int, nargs="+", default=[1, 2, 3])
    parser.add_argument("--bf-latency", type=int, default=15)
    parser.add_argument("--mul-latency", type=int, default=14)
    parser.add_argument("--pointwise-latency", type=int, default=14)
    parser.add_argument("--result-latency", type=int)
    args = parser.parse_args()

    if args.n < 4 or args.n & (args.n - 1):
        raise ValueError("N must be a power of two and at least 4")
    pairs = args.n // 2
    logn = args.n.bit_length() - 1
    stage_first_offset = sum(stage_depth(logn, s) for s in range(logn))
    stage_first_offset += logn * args.bf_latency
    result_latency = args.result_latency
    if result_latency is None:
        result_latency = (
            stage_first_offset
            + args.mul_latency
            + pairs - 1
            + args.pointwise_latency
            + 1
        )
    print("batch wavefront frame scheduler model")
    print(f"N={args.n} pairs={pairs} jobs={args.jobs}")
    print(f"result_latency={result_latency} bf_latency={args.bf_latency}")

    results: dict[int, ScheduleResult] = {}
    for buffers in args.buffers:
        result = build_schedule(
            pairs=pairs,
            job_count=args.jobs,
            buffers=buffers,
            result_latency=result_latency,
        )
        pipeline = validate_dual_context_pipeline(
            n=args.n,
            bf_latency=args.bf_latency,
            launches=result.launches,
        )
        results[buffers] = result
        print_result(buffers, result, pipeline)

    if (
        args.n == 4096
        and result_latency == 4303
        and 1 in results
        and abs(results[1].start_ii_steady - 10654.0) > 0.001
    ):
        raise AssertionError("single-buffer model no longer matches RTL calibration")
    if args.n == 4096 and 3 in results:
        theoretical_ii = 3 * pairs
        if abs(results[3].start_ii_steady - theoretical_ii) > 0.001:
            raise AssertionError(
                f"three buffers missed theoretical II={theoretical_ii}"
            )
        if abs(results[3].core_utilization_steady - 1.0) > 0.000001:
            raise AssertionError("three-buffer steady-state schedule contains bubbles")
        if abs(results[3].completion_ii_steady - theoretical_ii) > 0.001:
            raise AssertionError("three-buffer completion cadence is not steady")

    if args.n == 4096 and result_latency == 4303 and 2 in results:
        if abs(results[2].start_ii_steady - 6247.5) > 0.001:
            raise AssertionError("two-buffer steady II no longer matches calibration")

    print("\nbatch wavefront scheduler model: PASS")


if __name__ == "__main__":
    main()
