"""Checkpoint-based physical timing experiments; never changes RTL or vectors.

Reports internal timing only. The accepted source run retains a reviewed synth
console error; this runner neither reclassifies nor suppresses that error.
Each new Vivado invocation is checked strictly for errors and completion.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from datetime import datetime

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "reports/wl_lowcost_modmul/karatsuba_full_top/20260915_115811"
VIVADO = Path(r"D:\Vivado\2026.1\Vivado\bin\vivado.bat")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def inputs():
    paths = list((ROOT / "rtl").glob("*.sv")) + list((ROOT / "mem").glob("*.mem"))
    paths += list((BASE / "candidate/snapshot").rglob("*.sv"))
    paths += [BASE / p for p in (
        "candidate/impl/routed_signoff.dcp", "candidate/synth/synth.dcp", "candidate/impl/pre_route_physopt_oc.dcp",
        "candidate/simulation.json", "reviewed_final_audit.json",
        "candidate/checkpoint_audit/review.json")]
    return {str(p.relative_to(ROOT)): sha(p) for p in sorted(set(paths))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("phase", choices=["probe", "impl"])
    ap.add_argument("--mhz", type=int, choices=[160, 170, 180, 185, 190, 200], default=160)
    ap.add_argument("--checkpoint", type=Path, help="Explicit input DCP; preserved and hashed")
    ap.add_argument("--probe-mhz", default="150 160 170 180")
    ap.add_argument("--strategy", choices=["incremental", "fresh", "targeted", "reroute"], default="incremental")
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    out = args.output.resolve()
    out.relative_to(ROOT / "reports")
    out.mkdir(parents=True, exist_ok=False)
    script = ROOT / "scripts" / ("probe_karatsuba_frequency.tcl" if args.phase == "probe"
                                 else "implement_karatsuba_frequency.tcl")
    checkpoint = BASE / "candidate" / {
        "fresh": "synth/synth.dcp",
        "incremental": "impl/routed_signoff.dcp",
        "targeted": "impl/pre_route_physopt_oc.dcp",
        "reroute": "impl/pre_route_physopt_oc.dcp",
    }[args.strategy]
    if args.checkpoint:
        checkpoint = args.checkpoint.resolve()
        checkpoint.relative_to(ROOT / "reports")
        if not checkpoint.is_file() or checkpoint.suffix.lower() != ".dcp":
            raise ValueError("Checkpoint must be an existing report DCP")
    probe_mhz = [int(value) for value in args.probe_mhz.split()]
    if not probe_mhz or any(value < 100 or value > 250 for value in probe_mhz):
        raise ValueError("Invalid probe frequency list")
    review = json.loads((BASE / "reviewed_final_audit.json").read_text(encoding="utf-8"))
    if not review["review_verification_complete"]:
        raise RuntimeError("Baseline review incomplete")
    archive = out / "source_scripts"
    archive.mkdir()
    archived = {}
    for src in (script, Path(__file__), ROOT / "scripts/karatsuba_targeted_fanout.tcl"):
        shutil.copy2(src, archive / src.name)
        archived[src.name] = sha(src)
    before = inputs()
    checkpoint_key = str(checkpoint.relative_to(ROOT))
    before[checkpoint_key] = sha(checkpoint)
    meta = {"status": "running", "started": datetime.now().isoformat(),
            "phase": args.phase, "mhz": args.mhz, "strategy": args.strategy,
            "baseline": str(BASE), "checkpoint": str(checkpoint),
            "baseline_strict_audit_pass": review["strict_audit_pass"],
            "inherited_synth_error": review["original_error_text"],
            "board_signoff": False, "rtl_changed": False,
            "archived_scripts_sha256": archived, "source_hashes": before, "script_sha256": sha(script),
            "runner_sha256": sha(Path(__file__))}
    write(out / "metadata.json", meta)
    temp = out / "process_temp"
    temp.mkdir()
    env = os.environ.copy()
    env.update(TEMP=str(temp), TMP=str(temp))
    cmd = [str(VIVADO), "-mode", "batch", "-nojournal", "-log", str(out / "vivado.log"),
           "-source", str(script), "-tclargs", str(checkpoint), str(out)]
    if args.phase == "impl":
        cmd += [str(args.mhz), args.strategy]
    else:
        cmd += [" ".join(map(str, probe_mhz))]
    meta["command"] = cmd
    write(out / "metadata.json", meta)
    print(f"START {out}", flush=True)
    try:
        with (out / "console.log").open("w", encoding="utf-8") as log:
            proc = subprocess.Popen(cmd, cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT,
                                    creationflags=subprocess.CREATE_NO_WINDOW)
            meta["launcher_pid"] = proc.pid
            write(out / "metadata.json", meta)
            rc = proc.wait()
        logs = [(out / p).read_text(encoding="utf-8", errors="replace")
                for p in ("console.log", "vivado.log")]
        errors = [line for text in logs for line in text.splitlines()
                  if re.match(r"^\s*(ERROR:|FATAL:)", line)]
        marker = "FREQUENCY_PROBE_PASS" if args.phase == "probe" else "FREQUENCY_IMPLEMENTATION_COMPLETE"
        meta.update(exit_code=rc, errors=errors)
        if rc or errors or not all(marker in text for text in logs):
            raise RuntimeError(f"Vivado failed: exit={rc}, errors={errors}")
        after = inputs()
        after[checkpoint_key] = sha(checkpoint)
        changed = [k for k in before.keys() | after.keys() if before.get(k) != after.get(k)]
        meta["changed_inputs"] = changed
        if changed:
            raise RuntimeError(f"Protected inputs changed: {changed}")
        meta["status"] = "completed"
        if args.phase == "impl":
            meta["timing"] = json.loads((out / "result.json").read_text(encoding="utf-8"))
        print(f"COMPLETE {out}", flush=True)
    except Exception as exc:
        meta.update(status="failed", failure=str(exc))
        raise
    finally:
        meta["finished"] = datetime.now().isoformat()
        write(out / "metadata.json", meta)


if __name__ == "__main__":
    main()
