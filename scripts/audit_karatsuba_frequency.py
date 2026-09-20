"""Collect physical timing experiments, keeping failures visible."""
import argparse
import csv
import hashlib
import json
import re
import zipfile
from pathlib import Path


def read(p):
    return p.read_text(encoding="utf-8", errors="replace")


def match(pattern, text):
    m = re.search(pattern, text, re.M)
    if m is None:
        raise ValueError("Required report field missing: " + pattern)
    return m.group(1)


def audit(path):
    meta = json.loads(read(path / "metadata.json"))
    if meta["status"] != "completed":
        return {"directory": str(path), "status": meta["status"], "pass": False}
    data = json.loads(read(path / "result.json"))
    route = read(path / "route_status.rpt")
    timing = read(path / "timing.rpt")
    util = read(path / "utilization.rpt")
    data.update(directory=str(path), status="completed")
    for key, label in (("routable_nets", "routable nets"),
                       ("routed_nets", "fully routed nets"),
                       ("route_errors", "nets with routing errors")):
        data[key] = int(match(r"# of " + label + r"\.+\s*:\s*(\d+)", route))
    for key in ("unconstrained_internal_endpoints", "no_clock", "multiple_clock",
                "no_input_delay", "no_output_delay"):
        data[key] = int(match(r"checking " + key + r" \((\d+)\)", timing))
    for key, label in (("lut", "Slice LUTs"), ("ff", "Slice Registers"), ("slice", "Slice"), ("bufg", "BUFGCTRL")):
        data[key] = int(match(r"^\|\s*" + label + r"\s*\|\s*(\d+)\s*\|", util))
    summary = match(r"WNS\(ns\)[^\n]*\n\s*-+[^\n]*\n\s*([^\n]+)", timing).split()
    if len(summary) != 12:
        raise ValueError("Unexpected timing summary")
    data.update(setup_failing_endpoints=int(summary[2]), hold_failing_endpoints=int(summary[6]),
                pulse_width_failing_endpoints=int(summary[10]))
    drc = read(path / "drc.rpt")
    data["drc_summary"] = [
        {"rule": rule.strip(), "severity": severity, "checks": int(count)}
        for rule, severity, count in re.findall(
            r"^\|\s*([A-Z0-9_-]+)\s*\|\s*(Error|Critical Warning|Warning)\s*\|[^|]*\|\s*(\d+)\s*\|",
            drc, re.M)]
    if not data["drc_summary"]:
        raise ValueError("Missing DRC summary")
    data["drc_error_checks"] = sum(r["checks"] for r in data["drc_summary"] if r["severity"] == "Error")
    with zipfile.ZipFile(path / "routed.dcp") as checkpoint:
        data["checkpoint_crc_ok"] = checkpoint.testzip() is None
    normalize = lambda p:  [s.strip() for s in read(p).splitlines()
                           if s.strip() and not s.lstrip().startswith("#")]
    data["constraints_unchanged_during_optimization"] = (
        normalize(path / "constraints_before.xdc") == normalize(path / "constraints_after.xdc"))
    archived = meta.get("archived_scripts_sha256", {
        "implement_karatsuba_frequency.tcl": meta["script_sha256"],
        "run_karatsuba_frequency.py": meta["runner_sha256"],
    })
    data["archived_scripts_match"] = all(
        (path / "source_scripts" / name).is_file()
        and hashlib.sha256((path / "source_scripts" / name).read_bytes()).hexdigest() == expected
        for name, expected in archived.items())
    data["protected_inputs_unchanged"] = meta.get("changed_inputs") == []
    data["internal_implementation_pass"] = (
        data["internal_slack_pass"] and data["drc_error_checks"] == 0 and data["checkpoint_crc_ok"]
        and data["constraints_unchanged_during_optimization"]
        and data["archived_scripts_match"] and data["protected_inputs_unchanged"] and data["routable_nets"] == data["routed_nets"]
        and data["route_errors"] == 0 and data["unconstrained_internal_endpoints"] == 0
        and data["no_clock"] == 0 and data["multiple_clock"] == 0
        and all(data[k] == 0 for k in ("setup_failing_endpoints", "hold_failing_endpoints",
                                     "pulse_width_failing_endpoints")))
    data["output_sha256"] = {name: hashlib.sha256((path / name).read_bytes()).hexdigest()
                             for name in ("routed.dcp", "timing.rpt", "route_status.rpt",
                                          "utilization.rpt", "result.json", "metadata.json")}
    data["inherited_baseline_synth_error"] = meta["inherited_synth_error"]
    data["compute_cycles_inherited_unchanged_rtl"] = 8623
    data["compute_us_at_target"] = 8623 / data["mhz"]
    data["compute_us_at_actual_constraint"] = 8623 * data["period_ns"] / 1000
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("directory", type=Path)
    args = ap.parse_args()
    out = args.directory.resolve()
    runs = [audit(p.parent) for p in sorted(out.glob("*/result.json"))]
    with (out / "probe_retry/baseline_recheck.csv").open(encoding="utf-8", newline="") as f:
        baseline = list(csv.DictReader(f))
    failures = []
    for p in sorted(out.glob("*/metadata.json")):
        meta = json.loads(read(p))
        if meta.get("status") == "failed":
            failures.append({"directory": str(p.parent), "failure": meta.get("failure")})
    result = {"failed_attempts_retained": failures, "baseline_unchanged_route": baseline, "experiments": runs,
              "board_signoff": False, "global_fmax_claim": False,
              "audit_script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (out / "summary.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    for data in runs:
        print(json.dumps({k: data.get(k) for k in ("mhz", "strategy", "wns_ns", "whs_ns",
                         "lut", "ff", "slice", "bufg", "internal_implementation_pass")}, ensure_ascii=True))


if __name__ == "__main__":
    main()
