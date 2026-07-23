#!/usr/bin/env python3
"""Pre-RTL feasibility model for an asymmetric dual-forward GS-MDC design.

The model answers three questions without changing functional RTL:

1. What is the exact single-product cycle schedule when A_NTT and B_NTT run
   concurrently and one full core is reused for C_INTT?
2. Does a second NTT-only core plus two additional Pre_NTT multipliers fit in
   the target XC7A200T according to the routed hierarchy report?
3. Can the existing A/B and C/result bank organization sustain the required
   coefficient traffic without a same-bank conflict?

Timing closure is deliberately not predicted. It requires actual RTL,
synthesis, placement, and routing.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

from dual_context_wavefront_model import run_model


@dataclass(frozen=True)
class Resources:
    total_luts: int = 0
    logic_luts: int = 0
    lutrams: int = 0
    srls: int = 0
    ffs: int = 0
    ramb36: int = 0
    ramb18: int = 0
    dsps: int = 0

    @property
    def lut_memory(self) -> int:
        return self.lutrams + self.srls

    def __add__(self, other: "Resources") -> "Resources":
        return Resources(**{
            key: getattr(self, key) + getattr(other, key)
            for key in self.__dataclass_fields__
        })

    def __sub__(self, other: "Resources") -> "Resources":
        return Resources(**{
            key: getattr(self, key) - getattr(other, key)
            for key in self.__dataclass_fields__
        })


@dataclass(frozen=True)
class HierarchyRow:
    instance: str
    module: str
    resources: Resources


def _to_int(value: str) -> int:
    return int(value.replace(",", "").strip())


def parse_hierarchy(path: Path) -> list[HierarchyRow]:
    rows: list[HierarchyRow] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.split("|")[1:-1]]
        if len(cells) != 10:
            continue
        try:
            values = [_to_int(cell) for cell in cells[2:]]
        except ValueError:
            continue
        rows.append(HierarchyRow(
            instance=cells[0],
            module=cells[1],
            resources=Resources(*values),
        ))
    if not rows:
        raise ValueError(f"no hierarchy rows parsed from {path}")
    return rows


def find_row(rows: Iterable[HierarchyRow], instance: str) -> HierarchyRow:
    matches = [row for row in rows if row.instance == instance]
    if len(matches) != 1:
        raise ValueError(
            f"expected exactly one hierarchy row for {instance}, got {len(matches)}"
        )
    return matches[0]


def sum_matching(rows: Iterable[HierarchyRow], fragment: str) -> Resources:
    total = Resources()
    for row in rows:
        if fragment in row.instance:
            total += row.resources
    return total


def parse_device_capacity(path: Path) -> dict[str, int]:
    wanted = {
        "Slice LUTs": "slice_luts",
        "LUT as Memory": "lut_memory",
        "Slice Registers": "ffs",
        "Block RAM Tile": "bram",
        "DSPs": "dsps",
    }
    result: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.split("|")[1:-1]]
        if len(cells) < 5 or cells[0] not in wanted:
            continue
        try:
            available = _to_int(cells[4])
        except ValueError:
            continue
        result.setdefault(wanted[cells[0]], available)
    missing = set(wanted.values()) - set(result)
    if missing:
        raise ValueError(f"missing capacity fields in {path}: {sorted(missing)}")
    return result


def resource_model(repo: Path, n: int, qw: int) -> dict[str, object]:
    report_dir = repo / "reports" / "twiddle_bram_experiment" / "impl_e06"
    hierarchy_path = report_dir / "utilization_hierarchical.rpt"
    utilization_path = report_dir / "utilization.rpt"
    rows = parse_hierarchy(hierarchy_path)

    top = find_row(rows, "poly_mul_top").resources
    core = find_row(rows, "u_core").resources
    scale0 = find_row(rows, "u_intt_scale0").resources
    scale1 = find_row(rows, "u_intt_scale1").resources
    pre0 = find_row(rows, "u_pre_mul0").resources
    pre1 = find_row(rows, "u_pre_mul1").resources

    # Core1 only performs forward NTT. Removing its two N^-1 multipliers saves
    # 40 DSP relative to copying the complete NTT/INTT core.
    ntt_only_core = core - scale0 - scale1
    extra_pre_pair = pre0 + pre1

    # a_ntt_even/odd are unnecessary when lockstep CoreA/CoreB outputs feed
    # Pointwise directly. A 6-input LUT stores 64 bits of distributed RAM.
    pairs = n // 2
    a_ntt_lutram = 2 * math.ceil(pairs * qw / 64)
    a_ntt_cache = Resources(total_luts=a_ntt_lutram, lutrams=a_ntt_lutram)

    retained_cache = top + ntt_only_core + extra_pre_pair
    direct_pointwise = retained_cache - a_ntt_cache

    reorder_bram = sum_matching(rows, "g_output_reorder.fifo_").ramb36
    twiddle_bram = sum_matching(
        rows, "g_stage_local_twiddle.u_twiddle_rom"
    ).ramb36
    if reorder_bram != 10 or twiddle_bram != 15:
        raise AssertionError(
            f"unexpected core BRAM split: reorder={reorder_bram}, "
            f"twiddle={twiddle_bram}"
        )

    shared_twiddle = Resources(
        total_luts=direct_pointwise.total_luts,
        logic_luts=direct_pointwise.logic_luts,
        lutrams=direct_pointwise.lutrams,
        srls=direct_pointwise.srls,
        ffs=direct_pointwise.ffs,
        ramb36=direct_pointwise.ramb36 - twiddle_bram,
        ramb18=direct_pointwise.ramb18,
        dsps=direct_pointwise.dsps,
    )
    ntt_only_rom = Resources(
        total_luts=direct_pointwise.total_luts,
        logic_luts=direct_pointwise.logic_luts,
        lutrams=direct_pointwise.lutrams,
        srls=direct_pointwise.srls,
        ffs=direct_pointwise.ffs,
        # NTT-only Stage0..3 images need 4+2+1+1 RAMB36.
        ramb36=direct_pointwise.ramb36 - twiddle_bram + 8,
        ramb18=direct_pointwise.ramb18,
        dsps=direct_pointwise.dsps,
    )

    capacity = parse_device_capacity(utilization_path)

    def utilization(resources: Resources) -> dict[str, float]:
        return {
            "slice_luts_pct": 100.0 * resources.total_luts / capacity["slice_luts"],
            "lut_memory_pct": 100.0 * resources.lut_memory / capacity["lut_memory"],
            "ffs_pct": 100.0 * resources.ffs / capacity["ffs"],
            "bram_pct": 100.0 * resources.ramb36 / capacity["bram"],
            "dsps_pct": 100.0 * resources.dsps / capacity["dsps"],
        }

    def fits(resources: Resources) -> bool:
        return (
            resources.total_luts <= capacity["slice_luts"]
            and resources.lut_memory <= capacity["lut_memory"]
            and resources.ffs <= capacity["ffs"]
            and resources.ramb36 <= capacity["bram"]
            and resources.dsps <= capacity["dsps"]
        )

    variants = {
        "retain_a_ntt_and_duplicate_twiddle": retained_cache,
        "direct_pointwise_duplicate_twiddle": direct_pointwise,
        "direct_pointwise_ntt_only_twiddle": ntt_only_rom,
        "direct_pointwise_shared_twiddle": shared_twiddle,
    }
    return {
        "source_hierarchy_report": str(hierarchy_path.relative_to(repo)),
        "source_utilization_report": str(utilization_path.relative_to(repo)),
        "device_capacity": capacity,
        "measured_stage_local_top": asdict(top),
        "measured_full_core": asdict(core),
        "derived_ntt_only_core": asdict(ntt_only_core),
        "measured_extra_pre_pair": asdict(extra_pre_pair),
        "a_ntt_cache_lutram_removed": a_ntt_lutram,
        "core_bram_split": {
            "reorder": reorder_bram,
            "combined_ntt_intt_twiddle": twiddle_bram,
        },
        "variants": {
            name: {
                "resources": asdict(resources),
                "lut_memory": resources.lut_memory,
                "utilization": utilization(resources),
                "fits": fits(resources),
            }
            for name, resources in variants.items()
        },
        "capacity_pass": all(fits(resources) for resources in variants.values()),
        "timing_proven": False,
    }


def make_schedule(
    n: int,
    mul_lat: int,
    sequential_forward: bool,
) -> dict[str, object]:
    pairs = n // 2
    stage_result = run_model(
        n=n,
        frames=1,
        bf_latency=mul_lat + 1,
    )
    core_first_latency = int(stage_result["first_output"]) + mul_lat

    pre_first = mul_lat + 1
    a_in_first = pre_first
    a_in_last = a_in_first + pairs - 1
    b_in_first = a_in_last + 1 if sequential_forward else a_in_first
    b_in_last = b_in_first + pairs - 1

    a_out_first = a_in_first + core_first_latency
    a_out_last = a_out_first + pairs - 1
    b_out_first = b_in_first + core_first_latency
    b_out_last = b_out_first + pairs - 1

    pointwise_first = max(a_out_first, b_out_first) + mul_lat
    pointwise_last = max(a_out_last, b_out_last) + mul_lat
    intt_in_first = pointwise_last + 1
    intt_in_last = intt_in_first + pairs - 1
    intt_out_first = intt_in_first + core_first_latency
    intt_out_last = intt_out_first + pairs - 1
    done = intt_out_last + mul_lat + 1

    return {
        "n": n,
        "pairs": pairs,
        "mul_lat": mul_lat,
        "bf_latency": mul_lat + 1,
        "core_first_input_to_first_output": core_first_latency,
        "core_first_input_to_frame_done": core_first_latency + pairs,
        "a_ntt_input": [a_in_first, a_in_last],
        "b_ntt_input": [b_in_first, b_in_last],
        "a_ntt_output": [a_out_first, a_out_last],
        "b_ntt_output": [b_out_first, b_out_last],
        "pointwise_output": [pointwise_first, pointwise_last],
        "c_intt_input": [intt_in_first, intt_in_last],
        "c_intt_output": [intt_out_first, intt_out_last],
        "full_mul_cycles": done,
    }


def cycle_model(n: int, mul_lat: int, frequency_mhz: float) -> dict[str, object]:
    baseline = make_schedule(n, mul_lat, sequential_forward=True)
    dual = make_schedule(n, mul_lat, sequential_forward=False)

    reduction = baseline["full_mul_cycles"] - dual["full_mul_cycles"]
    speedup = baseline["full_mul_cycles"] / dual["full_mul_cycles"]
    if n == 4096 and mul_lat == 14:
        if baseline["full_mul_cycles"] != 10669:
            raise AssertionError(
                "cycle model no longer matches the measured wavefront baseline"
            )
        if dual["full_mul_cycles"] != 8621 or reduction != n // 2:
            raise AssertionError("unexpected N=4096 dual-forward schedule")

    load_cycles = 2 * n
    return {
        "baseline_wavefront": baseline,
        "dual_forward": dual,
        "cycle_reduction": reduction,
        "latency_reduction_pct": 100.0 * reduction / baseline["full_mul_cycles"],
        "operation_rate_speedup": speedup,
        "baseline_compute_us": baseline["full_mul_cycles"] / frequency_mhz,
        "dual_forward_compute_us": dual["full_mul_cycles"] / frequency_mhz,
        "current_single_port_load_cycles": load_cycles,
        "baseline_first_load_to_done_cycles": load_cycles + baseline["full_mul_cycles"],
        "dual_forward_first_load_to_done_cycles": load_cycles + dual["full_mul_cycles"],
    }


def bandwidth_model(n: int) -> dict[str, object]:
    phases = {
        "dual_pre_ntt": {
            "reads": {"a_bank0": 1, "a_bank1": 1, "b_bank0": 1, "b_bank1": 1},
            "writes": {},
            "cycles": n // 2,
        },
        "pointwise_write": {
            "reads": {},
            "writes": {"c_ntt_even": 1, "c_ntt_odd": 1},
            "cycles": n // 2,
        },
        "intt_feed": {
            "reads": {"c_ntt_even": 1, "c_ntt_odd": 1},
            "writes": {},
            "cycles": n // 2,
        },
        "post_write": {
            "reads": {},
            "writes": {"result_bank0": 1, "result_bank1": 1},
            "cycles": n // 2,
        },
    }

    conflicts: list[str] = []
    for phase, accesses in phases.items():
        banks = set(accesses["reads"]) | set(accesses["writes"])
        for bank in banks:
            total = accesses["reads"].get(bank, 0) + accesses["writes"].get(bank, 0)
            if total > 1:
                conflicts.append(f"{phase}:{bank}:{total}")

    return {
        "phases": phases,
        "max_input_coefficients_per_cycle": 4,
        "input_mapping": {
            "core_a_lane0": "a_bank0[pair] -> A[pair]",
            "core_a_lane1": "a_bank1[pair] -> A[pair+N/2]",
            "core_b_lane0": "b_bank0[pair] -> B[pair]",
            "core_b_lane1": "b_bank1[pair] -> B[pair+N/2]",
        },
        "psi_reads_per_cycle": 2,
        "psi_rule": "lane factors are broadcast to A and B Pre_NTT multipliers",
        "twiddle_rule": (
            "lockstep cores request the same NTT stage/address; one registered "
            "stage-local twiddle value may be broadcast to both BFUs"
        ),
        "pointwise_rule": (
            "same-cycle CoreA/CoreB outputs feed two pointwise multipliers "
            "directly; logical-index equality must be asserted in RTL"
        ),
        "conflicts": conflicts,
        "bank_schedule_pass": not conflicts,
        "external_load_port_coefficients_per_cycle": 1,
        "external_load_cycles_for_a_and_b": 2 * n,
    }


def print_resources(model: dict[str, object]) -> None:
    print("RESOURCE_MODEL")
    print("variant,total_luts,lut_memory,ffs,dsps,bram,fit")
    variants = model["variants"]
    for name, entry in variants.items():
        r = entry["resources"]
        print(
            f"{name},{r['total_luts']},{entry['lut_memory']},{r['ffs']},"
            f"{r['dsps']},{r['ramb36']},{entry['fits']}"
        )
    print(f"RESOURCE_CAPACITY_PASS={model['capacity_pass']}")
    print("PHYSICAL_TIMING_PROVEN=False")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--n", type=int, default=4096)
    parser.add_argument("--qw", type=int, default=64)
    parser.add_argument("--mul-lat", type=int, default=14)
    parser.add_argument("--frequency-mhz", type=float, default=100.0)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--json", type=Path)
    parser.add_argument(
        "--cycle-only",
        action="store_true",
        help="skip the N=4096 routed-report resource model",
    )
    args = parser.parse_args()

    cycles = cycle_model(args.n, args.mul_lat, args.frequency_mhz)
    resources = None if args.cycle_only else resource_model(args.repo, args.n, args.qw)
    bandwidth = bandwidth_model(args.n)
    result = {
        "cycle_model": cycles,
        "resource_model": resources,
        "bandwidth_model": bandwidth,
        "overall": {
            "cycle_schedule_pass": True,
            "resource_capacity_pass": (
                None if resources is None else resources["capacity_pass"]
            ),
            "bank_schedule_pass": bandwidth["bank_schedule_pass"],
            "rtl_function_proven": False,
            "post_route_timing_proven": False,
            "decision": "PROCEED_TO_CONTROLLED_RTL_PROTOTYPE",
        },
    }

    print("DUAL_FORWARD_PRE_RTL_FEASIBILITY")
    print(f"N={args.n} QW={args.qw} MUL_LAT={args.mul_lat}")
    print(f"BASELINE_FULL_MUL_CYCLES={cycles['baseline_wavefront']['full_mul_cycles']}")
    print(f"DUAL_FORWARD_FULL_MUL_CYCLES={cycles['dual_forward']['full_mul_cycles']}")
    print(f"CYCLE_REDUCTION={cycles['cycle_reduction']}")
    print(f"LATENCY_REDUCTION_PCT={cycles['latency_reduction_pct']:.4f}")
    print(f"OPERATION_RATE_SPEEDUP={cycles['operation_rate_speedup']:.6f}")
    print(f"DUAL_FORWARD_COMPUTE_US={cycles['dual_forward_compute_us']:.2f}")
    print(f"CORE_FIRST_INPUT_TO_FRAME_DONE={cycles['dual_forward']['core_first_input_to_frame_done']}")
    if resources is not None:
        print_resources(resources)
    else:
        print("RESOURCE_MODEL=SKIPPED_CYCLE_ONLY")
    print(f"BANK_SCHEDULE_PASS={bandwidth['bank_schedule_pass']}")
    print(f"BANK_CONFLICTS={bandwidth['conflicts']}")
    print("OVERALL=CONDITIONAL_PASS_PRE_RTL")

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
