"""Collect all three routed implementations; refuse incomplete experiment data."""
import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "reports/wl_lowcost_modmul"
VIVADO = OUT / "vivado"

def resource(text, label):
    found = re.search(r"^\|\s*" + re.escape(label) + r"\*?\s*\|\s*(\d+)\s*\|", text, re.M)
    if not found:
        raise ValueError("Missing utilization row: " + label)
    return int(found.group(1))

if __name__ == "__main__":
    with (VIVADO / "internal_timing.csv").open(newline="") as f:
        timing = {int(r["impl"]): r for r in csv.DictReader(f)}
    rows = []
    for impl in range(3):
        directory = VIVADO / f"impl_{impl}"
        text = (directory / "route_utilization.rpt").read_text(errors="replace")
        row = {"impl": impl,
               "slice_luts": resource(text, "Slice LUTs"),
               "slice_registers": resource(text, "Slice Registers"),
               "occupied_slices": resource(text, "Slice"),
               "dsp48": resource(text, "DSPs"),
               "reg_to_reg_wns_ns": float(timing[impl]["reg_to_reg_wns_ns"]),
               "latency_cycles": 14, "II_cycles": 1}
        rows.append(row)
    with (OUT / "comparison.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    data = {"scope": "standalone mont_mul_wl, routed OOC, fixed Q",
            "part": "xc7vx485tffg1761-2", "period_ns": 6.667,
            "external_port_timing_signoff": False,
            "timing_limitations": ["OOC external ports unbound", "HD.CLK_SRC not specified", "No Fmax sweep or full-top timing signoff"],
            "full_top_postroute_measured": False, "implementations": rows}
    data["fused_change_vs_dsp_percent"] = {
        k: round(100 * (rows[2][k] - rows[0][k]) / rows[0][k], 3)
        for k in ["slice_luts", "slice_registers", "occupied_slices", "dsp48"]}
    (OUT / "comparison.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(data, indent=2))
