"""Isolated 14-cycle full-top candidate: 22 Karatsuba cores + 4 full64 peripherals.

Derived from run_wl_csa_full_top.py; never edits workspace RTL, TBs or vectors.
Only the candidate is run. The earlier fused14 run is a labelled reference,
not a fresh baseline. collect reads existing metadata without updating it.
"""
import argparse
import csv
import difflib
import hashlib
import json
import os
import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QUESTA = Path(r"D:\modeltech64_2020.4\win64")
VIVADO = Path(r"D:\Vivado\2026.1\Vivado\bin\vivado.bat")
TCL_REL = "scripts/run_wl_karatsuba_full_top.tcl"
PY_REL = "scripts/run_wl_karatsuba_full_top.py"
FLOW_REL = "scripts/run_synth_dual_forward_dsp_reduction.tcl"
DEFAULT_BASELINE = ROOT / "reports/wl_lowcost_modmul/csa_full_top/20260914_230139/lat14"
INT_REL = "rtl/intmul_60x60_karatsuba4_experimental.sv"
MONT_REL = "sim/mont_mul_wl_karatsuba14_experimental.sv"
SELECTOR_NAME = "mont_mul_core_karatsuba_select"
SELECTOR_REL = "rtl/" + SELECTOR_NAME + ".sv"
ORIGINAL_TOP_TB = "tb_poly_mul_top_dual_forward_csa_integration"
CANDIDATE_TOP_TB = "tb_poly_mul_top_dual_forward_karatsuba_integration"
TB_NAMES = ["tb_mont_mul_wl_csa_integration", "tb_gs_butterfly", "tb_gs_mdc_core",
            "tb_gs_mdc_core_roundtrip", "tb_gs_mdc_core_ntt_only_csa_integration",
            ORIGINAL_TOP_TB, "tb_poly_mul_top_dual_forward_natural_ab"]
CASES = [
    ("wl_peripheral_original", TB_NAMES[0], []),
    ("butterfly", "tb_gs_butterfly", []),
    ("butterfly_unit", "tb_gs_butterfly", ["-gBYPASS_TWIDDLE_MUL=1"]),
    ("ntt_core", "tb_gs_mdc_core", ["-gUSE_FINAL_UNIT_TWIDDLE_BYPASS=1"]),
    ("roundtrip", "tb_gs_mdc_core_roundtrip", []),
    ("ntt_only", TB_NAMES[4], ["-gUSE_FINAL_UNIT_TWIDDLE_BYPASS=1"]),
    ("natural_ab_full64", CANDIDATE_TOP_TB, []),
    ("unchanged_natural_ab", "tb_poly_mul_top_dual_forward_natural_ab", []),
]
# This is an output of the unchanged core TB, never an input or golden.
# Do not copy/hash it as immutable snapshot input; the workspace original is
# nevertheless covered by source_hashes() and must remain untouched.
GENERATED_MEM = {"mem/output_ntt_a.mem"}
EXPECTED_GENERICS = dict(item.split("=", 1) for item in (
    "MUL_LAT=14 USE_WL_MONT=1 USE_WL_CORE=1 USE_WL_PRE_NTT=1 USE_WL_POINTWISE=1 "
    "USE_WL_POST_INTT=1 USE_BFU_BOUNDARY_PIPE=1 USE_STAGE_LOCAL_TWIDDLE=1 "
    "TWIDDLE_BRAM_STAGES=4 USE_LOAD_PREPROCESS=0 FUSE_INTT_SCALE_IN_POST=1 "
    "USE_FINAL_UNIT_TWIDDLE_BYPASS=1 USE_TOP_DATA_BRAM=1 USE_SHARED_PERIPH_MONT=1 "
    "USE_NATURAL_AB_LOADER=1").split())
EXPECTED_DIRECTIVES = ["opt_design -directive Explore", "place_design -directive AltSpreadLogic_medium",
                       "phys_opt_design -directive AggressiveFanoutOpt", "phys_opt_design -directive AggressiveExplore",
                       "route_design -directive MoreGlobalIterations -tns_cleanup", "phys_opt_design -directive Explore",
                       "route_design -directive MoreGlobalIterations -tns_cleanup"]
ERROR_RE = re.compile(r"^\s*(?:#\s*)?(?:ERROR:|\*\*\s*(?:Error|Fatal)(?:\s*\([^\n)]*\))?:)", re.M | re.I)


def now():
    return datetime.now().isoformat()


def dump(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def source_hashes():
    files = [p for folder, pattern in (("rtl", "*.sv"), ("sim", "*.sv"), ("mem", "*.mem"))
             for p in (ROOT / folder).glob(pattern)]
    files += [ROOT / p for p in (PY_REL, TCL_REL, FLOW_REL)]
    return {p.relative_to(ROOT).as_posix(): digest(p) for p in sorted(set(files))}


def different_keys(before, after):
    return sorted(k for k in before.keys() | after.keys() if before.get(k) != after.get(k))


def replace_exact(text, pattern, replacement, count, label):
    result, found = re.subn(pattern, lambda _: replacement, text)
    if found != count:
        raise RuntimeError(f"{label}: expected {count} matches, got {found}")
    return result


def patch_text(before, after, source, target):
    return "".join(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                      fromfile=source, tofile=target))


def derive_top_tb(before):
    """Keep the three original cases/checks, then append a full64 identity case."""
    after = replace_exact(before, rf"\bmodule {ORIGINAL_TOP_TB};",
                          f"module {CANDIDATE_TOP_TB};", 1, "TB module")
    after = replace_exact(after, r"    integer index;\n\n    \$readmemh",
                          "    integer index;\n    integer full64_input_count;\n"
                          "    logic [63:0] identity_rng;\n\n    $readmemh", 1, "TB declarations")
    extra_case = r'''
    // Additional independent interface-range test. B is Montgomery one at
    // coefficient zero, so negacyclic multiplication returns A modulo Q.
    // Only the in-memory golden array changes; no .mem file is written.
    wait_for_idle();
    if ((QW != 64) || (L != 14) || (EXPECT_COMPUTE != 8623))
      $fatal(1, "full64 identity case requires the audited 64-bit / 14-cycle configuration");
    identity_rng = 64'h6a09e667f3bcc909;
    for (index = 0; index < N; index = index + 1) begin
      identity_rng = identity_rng ^ (identity_rng << 13);
      identity_rng = identity_rng ^ (identity_rng >> 7);
      identity_rng = identity_rng ^ (identity_rng << 17);
      a[index] = identity_rng;
      b[index] = '0;
    end
    a[0] = 64'h1000000000000000;
    a[1] = 64'hffffffffffffffff;
    a[2] = Q;
    a[3] = Q + 64'd1;
    a[4] = '0;
    a[5] = Q - 64'd1;
    a[N/2-1] = 64'h8000000000000000;
    a[N/2] = 64'hffffffffffffffff;
    a[N-1] = 64'h1000000000000000;
    b[0] = R_MOD_Q;
    full64_input_count = 0;
    for (index = 0; index < N; index = index + 1) begin
      golden[index] = a[index] % Q;
      if (|a[index][63:60]) full64_input_count = full64_input_count + 1;
    end
    if (full64_input_count == 0)
      $fatal(1, "full64 identity case did not exercise input bits 63:60");
    if ((a[0] !== 64'h1000000000000000) || (golden[0] !== 64'd16383))
      $fatal(1, "2^60 normalization reference must be 16383");
    $display("KARATSUBA_NONCANONICAL_INPUT full64_input_count=%0d a0=%016x golden0=%0d seed=6a09e667f3bcc909",
             full64_input_count, a[0], golden[0]);
    load_natural(1'b0, accepted_count, load_elapsed, first_fire, last_fire);
    if ((accepted_count != N) || (load_elapsed != N))
      $fatal(1, "identity continuous load accepted=%0d elapsed=%0d", accepted_count, load_elapsed);
    start_and_wait(start_cycle, done_cycle);
    check_random_result();
    result_addr = '0;
    #1;
    if (result_data !== 64'd16383)
      $fatal(1, "2^60 full64 interface result=%016x expected=16383", result_data);
    report_cycles("noncanonical_identity", accepted_count, load_elapsed,
                  first_fire, last_fire, start_cycle, done_cycle);
    $display("KARATSUBA_NONCANONICAL_IDENTITY full64_input_count=%0d checked=%0d result0=%0d PASS",
             full64_input_count, N, result_data);
    wait_for_idle();
'''
    old_pass = f'    $display("{ORIGINAL_TOP_TB} PASS");'
    new_pass = f'    $display("{CANDIDATE_TOP_TB} PASS");'
    after = replace_exact(after, re.escape(old_pass), extra_case + "\n" + new_pass, 1, "TB final case")
    after = replace_exact(after, "CSA_INTEGRATION_PHASES", "KARATSUBA_INTEGRATION_PHASES", 1, "phase label")
    return "// Generated in the experiment snapshot; original tests and goldens are unchanged.\n" + after


def read_config(path):
    return dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line)


def baseline_reference(base, active_rtl):
    """Record the existing run, including its reviewed console-only errors."""
    base = base.resolve()
    parent_meta = base.parent / "metadata.json"
    old_meta = json.loads(parent_meta.read_text())
    expected = {"vivado": "2026.1", "latency": "14", "reduction": "fused2", "top": "poly_mul_top_dual_forward",
                "configuration": "natural_ab_raw_pre_shared", "part": "xc7vx485tffg1761-2"}
    evidence = [parent_meta, base / "snapshot_sha256.json", base / "simulation.json"]
    for phase in ("synth", "impl"):
        cfg = read_config(base / phase / "config.txt")
        if any(cfg.get(k) != v for k, v in expected.items()):
            raise RuntimeError(f"Reference {phase} configuration does not match fused14")
        if float(cfg["period_ns"]) != 6.667 or float(cfg["implementation_period_ns"]) != 6.4:
            raise RuntimeError("Reference clock periods differ")
        evidence += [base / phase / name for name in ("config.txt", "utilization.rpt", "timing.rpt")]
    evidence += [base / "impl/internal_timing.csv", base / "synth/vivado.log", base / "impl/vivado.log"]
    if not all(p.is_file() for p in evidence):
        raise RuntimeError("Reference evidence is incomplete")
    synth_log = (base / "synth/vivado.log").read_text(errors="replace")
    generic_match = re.search(r"^Command: synth_design[^\n]* -generic \{([^}\n]+)\}", synth_log, re.M)
    if not generic_match:
        raise RuntimeError("Reference actual synth_design command is unavailable")
    actual_generics = dict(item.split("=", 1) for item in generic_match.group(1).split())
    if actual_generics != EXPECTED_GENERICS:
        raise RuntimeError("Reference generics differ: " + json.dumps(actual_generics, sort_keys=True))
    impl_log = (base / "impl/vivado.log").read_text(errors="replace")
    actual_directives = re.findall(r"^Command: ((?:opt_design|place_design|phys_opt_design|route_design) -[^\r\n]+)", impl_log, re.M)
    if actual_directives != EXPECTED_DIRECTIVES:
        raise RuntimeError("Reference implementation directives differ: " + repr(actual_directives))
    mem_inputs = [p.relative_to(ROOT).as_posix() for p in sorted((ROOT / "mem").glob("*.mem"))
                  if p.relative_to(ROOT).as_posix() not in GENERATED_MEM]
    reference_manifest = json.loads((base / "snapshot_sha256.json").read_text())
    source_differences = [rel for rel in active_rtl + mem_inputs
                          if digest(ROOT / rel) != digest(base / "snapshot" / rel)
                          or digest(base / "snapshot" / rel) != reference_manifest.get(rel)]
    if source_differences:
        raise RuntimeError("Active RTL/mem differs from reference or its saved hash: " + ", ".join(source_differences))
    evidence += [base / "snapshot" / rel for rel in active_rtl + mem_inputs]
    return {"directory": str(base), "rerun": False, "source_matches_current_active_rtl_and_mem": True,
            "matched_rtl_count": len(active_rtl), "matched_mem_count": len(mem_inputs),
            "actual_generics": actual_generics, "actual_implementation_directives": actual_directives,
            "metadata_status": old_meta.get("status"),
            "reviewed_error_records": {k: v for k, v in old_meta.items() if k.startswith("reviewed_") and "lat12" not in k},
            "evidence_sha256": {str(p): digest(p) for p in evidence}}


def prepare(out, baseline):
    if out.exists():
        raise RuntimeError("New run directory must not already exist: " + str(out))
    flow = (ROOT / FLOW_REL).read_text()
    active_rtl = list(dict.fromkeys(re.findall(r"rtl/[A-Za-z0-9_]+\.sv", flow)))
    if not active_rtl or active_rtl[0] != "rtl/params_pkg.sv":
        raise RuntimeError("Could not identify the ordered production RTL list")
    before_hashes = source_hashes()
    candidate_flow = (ROOT / TCL_REL).read_text()
    candidate_generics = re.search(r"set generics \[list ([^\]\n]+)\]", candidate_flow)
    candidate_directives = re.findall(r"^\s*((?:opt_design|place_design|phys_opt_design|route_design) -[^\r\n]+)", candidate_flow, re.M)
    if not candidate_generics or dict(item.split("=", 1) for item in candidate_generics.group(1).split()) != EXPECTED_GENERICS:
        raise RuntimeError("Candidate Tcl generics differ from the audited configuration")
    if candidate_directives != EXPECTED_DIRECTIVES:
        raise RuntimeError("Candidate implementation directives differ from the reference")
    for rel, pattern in [
        ("rtl/params_pkg.sv", r"parameter int MUL_LAT\s*=\s*14\s*;"),
        ("rtl/params_pkg.sv", r"Q\s*=\s*64'h0fffffffffffc001\s*;"),
        ("rtl/mont_mul_wl.sv", r"parameter int REDUCTION_IMPL\s*=\s*2"),
        ("rtl/mont_mul_wl.sv", r"localparam int WL_LAT\s*=\s*14\s*;"),
        (MONT_REL, r"parameter int REDUCTION_IMPL\s*=\s*2"),
        (MONT_REL, r"localparam int WL_LAT\s*=\s*14\s*;"),
    ]:
        if len(re.findall(pattern, (ROOT / rel).read_text())) != 1:
            raise RuntimeError("Unexpected production/candidate configuration: " + rel)
    reference = baseline_reference(baseline, active_rtl)
    rtl = list(active_rtl)
    rtl.insert(rtl.index("rtl/intmul_64x64_24x17.sv") + 1, INT_REL)
    selector_index = rtl.index("rtl/mont_mul_select.sv") + 1
    rtl[selector_index:selector_index] = [MONT_REL, SELECTOR_REL]
    out.mkdir(parents=True)
    variant = out / "candidate"
    snap = variant / "snapshot"
    inputs = [p for p in rtl if p != SELECTOR_REL]
    inputs += ["sim/" + name + ".sv" for name in TB_NAMES]
    inputs += [p.relative_to(ROOT).as_posix() for p in sorted((ROOT / "mem").glob("*.mem"))
               if p.relative_to(ROOT).as_posix() not in GENERATED_MEM]
    inputs += [PY_REL, TCL_REL, FLOW_REL]
    for rel in dict.fromkeys(inputs):
        dst = snap / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, dst)
    patches = []
    bf = snap / "rtl/gs_butterfly.sv"
    before = bf.read_text()
    after = replace_exact(before, r"\bmont_mul_select(?=\s*#)", SELECTOR_NAME, 2, "BFU selector sites")
    bf.write_text(after, encoding="utf-8")
    patches.append(patch_text(before, after, "production/rtl/gs_butterfly.sv", "candidate/rtl/gs_butterfly.sv"))
    original_selector = (snap / "rtl/mont_mul_select.sv").read_text()
    selector = replace_exact(original_selector, r"\bmodule mont_mul_select\b",
                             "module " + SELECTOR_NAME, 1, "core selector module")
    selector = replace_exact(selector, r"\bmont_mul_wl(?=\s*#)",
                             "mont_mul_wl_karatsuba14_experimental", 1, "core WL branch")
    selector = "// Snapshot-only BFU selector. Peripheral mont_mul_select remains untouched.\n" + selector
    (snap / SELECTOR_REL).write_text(selector, encoding="utf-8")
    patches.append(patch_text("", selector, "/dev/null", "candidate/" + SELECTOR_REL))
    tb_rel = "sim/" + CANDIDATE_TOP_TB + ".sv"
    tb_before = (snap / "sim" / (ORIGINAL_TOP_TB + ".sv")).read_text()
    tb_after = derive_top_tb(tb_before)
    (snap / tb_rel).write_text(tb_after, encoding="utf-8")
    patches.append(patch_text(tb_before, tb_after, "production/sim/" + ORIGINAL_TOP_TB + ".sv", "candidate/" + tb_rel))
    (snap / "rtl_files.txt").write_text("\n".join(rtl) + "\n", encoding="utf-8")
    (variant / "snapshot_changes.patch").write_text("".join(patches), encoding="utf-8")
    immutable = {p.relative_to(snap).as_posix(): digest(p)
                 for p in sorted(snap.rglob("*")) if p.is_file()}
    dump(variant / "snapshot_sha256.json", immutable)
    for rel in ("rtl/mont_mul_select.sv", "rtl/mont_mul_wl.sv", "rtl/peripheral_mont_pool.sv",
                "rtl/poly_mul_top_dual_forward.sv", "rtl/params_pkg.sv"):
        if immutable[rel] != before_hashes[rel]:
            raise RuntimeError("Peripheral/configuration isolation failed: " + rel)
    meta = {"schema": "wl_karatsuba_full_top_v1", "started": now(), "status": "prepared",
            "top": "poly_mul_top_dual_forward", "configuration": "natural_ab_raw_pre_shared",
            "variant": "core22_karatsuba14_peripheral4_full64", "latency": 14,
            "part": "xc7vx485tffg1761-2", "period_ns": 6.667, "implementation_period_ns": 6.400,
            "modulus": "0x0fffffffffffc001", "montgomery_R": "2^64", "reduction": "fused2",
            "vivado": "2026.1", "generics": EXPECTED_GENERICS, "implementation_directives": EXPECTED_DIRECTIVES,
            "production_default_changed": False, "top_input_width_bits": 64,
            "core_frontend_input_width_bits": 60, "peripheral_frontend_input_width_bits": 64,
            "expected_frontend_instances": {"core_karatsuba": 22, "peripheral_schoolbook": 4},
            "dsp_budget_not_measurement": 246, "rtl_files": rtl, "copied_inputs": inputs,
            "simulation_cases": [case[0] for case in CASES],
            "analytical_compute_cycles": 8623, "continuous_load_plus_compute_cycles": 12719,
            "source_sha256_before": before_hashes, "snapshot_sha256": immutable,
            "patch_sha256": digest(variant / "snapshot_changes.patch"), "baseline_reference": reference,
            "snapshot_generated_output_exclusions": sorted(GENERATED_MEM), "phases": {},
            "limitations": ["Existing earlier fused14 reference is not rerun in this experiment",
                            "External IO delays/pins are unspecified; internal timing only",
                            "No Fmax search or power measurement"]}
    dump(out / "metadata.json", meta)
    verify_inputs(out, meta)
    return meta


def input_audit(out, meta):
    snap = out / "candidate/snapshot"
    source_after = source_hashes()
    snap_after = {rel: digest(snap / rel) for rel in meta["snapshot_sha256"]}
    source_changes = different_keys(meta["source_sha256_before"], source_after)
    snapshot_changes = different_keys(meta["snapshot_sha256"], snap_after)
    if digest(out / "candidate/snapshot_changes.patch") != meta["patch_sha256"]:
        snapshot_changes.append("../snapshot_changes.patch")
    manifest = out / "candidate/snapshot_sha256.json"
    if not manifest.is_file() or json.loads(manifest.read_text()) != meta["snapshot_sha256"]:
        snapshot_changes.append("../snapshot_sha256.json")
    return {"source_sha256_after": source_after, "snapshot_sha256_after": snap_after,
            "production_sources_unchanged": not source_changes, "snapshot_inputs_unchanged": not snapshot_changes,
            "source_changes": source_changes, "snapshot_changes": snapshot_changes}


def verify_inputs(out, meta):
    audit = input_audit(out, meta)
    if not audit["production_sources_unchanged"] or not audit["snapshot_inputs_unchanged"]:
        raise RuntimeError("Immutable inputs changed: " + ", ".join(audit["source_changes"] + audit["snapshot_changes"]))
    return audit


def run(cmd, cwd, log, env, marker=None, secondary_logs=()):
    print("START " + str(log), flush=True)
    with log.open("w", encoding="utf-8") as output:
        result = subprocess.run([str(x) for x in cmd], cwd=cwd, env=env, stdout=output,
                                stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    console = log.read_text(errors="replace")
    texts = [console]
    for other in secondary_logs:
        if not other.is_file():
            raise RuntimeError("Missing tool log: " + str(other))
        texts.append(other.read_text(errors="replace"))
    if result.returncode or (marker and marker not in console) or any(ERROR_RE.search(s) for s in texts):
        print(console[-9000:], flush=True)
        raise RuntimeError(f"Tool failed: {log}, exit={result.returncode}; errors are never whitelisted")
    print("PASS " + str(log), flush=True)
    return console


def simulate(out, meta, env):
    variant = out / "candidate"
    snap = variant / "snapshot"
    logs = variant / "simulation"
    logs.mkdir(exist_ok=False)
    run([QUESTA / "vlib.exe", "work"], snap, logs / "vlib.log", env)
    files = meta["rtl_files"] + ["sim/" + name + ".sv" for name in TB_NAMES + [CANDIDATE_TOP_TB]]
    run([QUESTA / "vlog.exe", "-sv", "-work", "work", *files], snap, logs / "compile.log", env)
    summary = {}
    for label, tb, generics in CASES:
        transcript = logs / (label + ".transcript.log")
        text = run([QUESTA / "vsim.exe", "-c", "-lib", "work", *generics, tb, "-l", transcript,
                    "-do", "onerror {quit -code 1}; run -all; quit -f"], snap,
                   logs / (label + ".log"), env, tb + " PASS", [transcript])
        observations = [line for line in text.splitlines() if any(word in line for word in
                        ("_CYCLES", "INTEGRATION_PHASES", "DIRECTED_LOGICAL_RESULT", "NONCANONICAL", " PASS"))]
        if label == "natural_ab_full64":
            identity = re.search(r"KARATSUBA_NONCANONICAL_IDENTITY full64_input_count=(\d+) checked=4096 result0=16383 PASS", text)
            cycle_lines = [line for line in observations if "NATURAL_AB_CYCLES case=" in line]
            expected_cases = {"random_continuous", "random_bubbles", "directed_bubbles", "noncanonical_identity"}
            found_cases = {re.search(r"case=(\w+)", line).group(1) for line in cycle_lines}
            if not identity or int(identity.group(1)) <= 0 or found_cases != expected_cases:
                raise RuntimeError("Missing original cases or full64 identity coverage")
            if any(not re.search(r"\bcompute=8623\b", line) for line in cycle_lines):
                raise RuntimeError("Unexpected full-top 14-cycle compute schedule")
        summary[label] = {"pass": True, "observations": observations}
        for line in observations:
            print(line, flush=True)
    dump(variant / "simulation.json", summary)
    print("KARATSUBA_FULL_TOP_SIM_PASS L=14", flush=True)
    return {"simulation_json_sha256": digest(variant / "simulation.json")}


def require_phase(out, meta, phase):
    record = meta["phases"].get(phase, {})
    if record.get("status") != "passed":
        raise RuntimeError(f"A recorded successful {phase} phase is required")
    if phase == "sim":
        if digest(out / "candidate/simulation.json") != record["simulation_json_sha256"]:
            raise RuntimeError("Simulation receipt changed")
    else:
        checkpoint = "synth.dcp" if phase == "synth" else "routed_signoff.dcp"
        if digest(out / "candidate" / phase / checkpoint) != record["checkpoint_sha256"]:
            raise RuntimeError("Checkpoint differs from its successful phase receipt")


def vivado(out, meta, phase, env):
    require_phase(out, meta, "sim" if phase == "synth" else "synth")
    variant = out / "candidate"
    snap = variant / "snapshot"
    output = variant / phase
    output.mkdir(exist_ok=False)
    run([VIVADO, "-mode", "batch", "-nojournal", "-log", output / "vivado.log",
         "-source", snap / TCL_REL, "-tclargs", phase, snap, output], output,
        output / "console.log", env, f"KARATSUBA_FULL_TOP_PHASE_PASS {phase} L=14", [output / "vivado.log"])
    required = ["config.txt", "utilization.rpt", "hierarchy.rpt", "ram.rpt", "timing.rpt", "isolation_audit.txt"]
    checkpoint = "synth.dcp" if phase == "synth" else "routed_signoff.dcp"
    required.append(checkpoint)
    if phase == "impl":
        required += ["internal_timing.csv", "internal_setup.rpt", "internal_hold.rpt", "route_status.rpt", "drc.rpt"]
    if not all((output / name).is_file() and (output / name).stat().st_size for name in required):
        raise RuntimeError("Missing or empty required " + phase + " artifact")
    return {"checkpoint_sha256": digest(output / checkpoint),
            "artifact_sha256": {name: digest(output / name) for name in required if name != checkpoint}}


def resource(text, label, optional=False):
    match = re.search(r"^\|\s*" + re.escape(label) + r"\*?\s*\|\s*([\d.]+)\s*\|", text, re.M)
    if not match:
        if optional:
            return None
        raise ValueError("Missing utilization row " + label)
    value = match.group(1)
    return float(value) if "." in value else int(value)


def result_row(directory, label, phase, meta):
    folder = directory / phase
    text = (folder / "utilization.rpt").read_text(errors="replace")
    cfg = read_config(folder / "config.txt")
    if cfg.get("latency") != "14" or cfg.get("part") != meta["part"] or cfg.get("configuration") != meta["configuration"]:
        raise RuntimeError("Report configuration does not match metadata: " + str(folder))
    row = {"variant": label, "phase": phase, "latency": 14,
           "compute_cycles": meta["analytical_compute_cycles"],
           "continuous_load_plus_compute_cycles": meta["continuous_load_plus_compute_cycles"]}
    for key, name in [("lut", "Slice LUTs"), ("ff", "Slice Registers"), ("dsp", "DSPs"),
                      ("bram36_equivalent", "Block RAM Tile"), ("ramb36", "RAMB36/FIFO*"),
                      ("ramb18", "RAMB18"), ("occupied_slices", "Slice")]:
        row[key] = resource(text, name, optional=key in ("ramb36", "ramb18") or (key == "occupied_slices" and phase == "synth"))
    if phase == "impl":
        with (folder / "internal_timing.csv").open(newline="") as stream:
            timing = next(csv.DictReader(stream))
        row.update({"reg_to_reg_wns_ns": float(timing["wns_ns"]), "reg_to_reg_whs_ns": float(timing["whs_ns"]),
                    "data_path_delay_ns": float(timing["data_path_delay_ns"]),
                    "startpoint": timing["startpoint"], "endpoint": timing["endpoint"]})
        summary = (folder / "timing.rpt").read_text(errors="replace")
        lines = summary.splitlines()
        header = next(i for i, line in enumerate(lines) if "WNS(ns)" in line)
        vals = lines[header + 2].split()
        row.update({"constrained_wns_ns": float(vals[0]), "constrained_whs_ns": float(vals[4]),
                    "setup_failing_endpoints": int(vals[2]), "hold_failing_endpoints": int(vals[6])})
        for name in ("no_input_delay", "no_output_delay", "unconstrained_internal_endpoints"):
            match = re.search(r"checking " + name + r" \((\d+)\)", summary)
            row[name] = int(match.group(1)) if match else None
        row["internal_setup_hold_pass"] = row["reg_to_reg_wns_ns"] >= 0 and row["reg_to_reg_whs_ns"] >= 0
    return row


def collect(out, meta):
    """Read original metadata and reports; write only derived comparison files."""
    reference = meta["baseline_reference"]
    for path, expected in reference["evidence_sha256"].items():
        if digest(Path(path)) != expected:
            raise RuntimeError("Recorded reference evidence changed: " + path)
    rows = [result_row(Path(reference["directory"]), "reference_fused14_earlier_run", phase, meta)
            for phase in ("synth", "impl")]
    for phase in ("synth", "impl"):
        record = meta["phases"].get(phase, {})
        if record.get("status") != "passed":
            continue
        folder = out / "candidate" / phase
        for name, expected in record["artifact_sha256"].items():
            if digest(folder / name) != expected:
                raise RuntimeError("Recorded candidate report changed: " + str(folder / name))
        rows.append(result_row(out / "candidate", "candidate_core22_karatsuba14", phase, meta))
    data = {"metadata_status": meta["status"], "metadata_sha256": digest(out / "metadata.json"),
            "scope": "Candidate-only complete dual-forward top; existing earlier fused14 reference is not rerun",
            "baseline_reference": reference, "part": meta["part"], "period_ns": meta["period_ns"],
            "implementation_period_ns": meta["implementation_period_ns"], "board_timing_signoff": False,
            "results": rows, "limitations": meta["limitations"]}
    dump(out / "comparison.json", data)
    fields = list(dict.fromkeys(key for row in rows for key in row))
    with (out / "comparison.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps(rows, indent=2), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, help="New run directory, or existing directory when resuming")
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE, help="Existing fused14 reference (prepare only)")
    parser.add_argument("--phase", choices=["prepare", "sim", "synth", "impl", "all", "collect"], default="prepare")
    args = parser.parse_args()
    if args.phase == "collect" and not args.out:
        parser.error("--phase collect requires an existing --out directory")
    out = (args.out or ROOT / "reports/wl_lowcost_modmul/karatsuba_full_top" / datetime.now().strftime("%Y%m%d_%H%M%S")).resolve()
    print("RUN_DIRECTORY=" + str(out), flush=True)
    metadata = out / "metadata.json"
    if args.phase == "collect":
        # Deliberately outside the execution/finally branch: do not refresh
        # original timestamps, source hashes, phase results, or status.
        meta = json.loads(metadata.read_text())
        if meta.get("schema") != "wl_karatsuba_full_top_v1":
            raise RuntimeError("Not a Karatsuba full-top run directory")
        collect(out, meta)
        return
    meta = json.loads(metadata.read_text()) if metadata.exists() else prepare(out, args.baseline)
    if meta.get("schema") != "wl_karatsuba_full_top_v1":
        raise RuntimeError("Not a Karatsuba full-top run directory")
    try:
        verify_inputs(out, meta)
        temporary = out / "process_temp"
        temporary.mkdir(exist_ok=True)
        env = os.environ.copy()
        env.update({"TEMP": str(temporary), "TMP": str(temporary)})
        phases = ["sim", "synth", "impl"] if args.phase == "all" else ([] if args.phase == "prepare" else [args.phase])
        for phase in phases:
            verify_inputs(out, meta)
            if meta["phases"].get(phase, {}).get("status") == "passed":
                require_phase(out, meta, phase)
                print("ALREADY_PASSED " + phase, flush=True)
                continue
            meta["status"] = "running_" + phase
            meta["phases"][phase] = {"status": "running", "started": now()}
            dump(metadata, meta)
            receipt = simulate(out, meta, env) if phase == "sim" else vivado(out, meta, phase, env)
            verify_inputs(out, meta)
            meta["phases"][phase].update(receipt)
            meta["phases"][phase].update({"status": "passed", "finished": now()})
            dump(metadata, meta)
        meta["status"] = "completed_" + args.phase
        meta.pop("error", None)
    except Exception as error:
        meta["status"] = "failed"
        meta["error"] = str(error)
        for record in meta["phases"].values():
            if record.get("status") == "running":
                record.update({"status": "failed", "finished": now(), "error": str(error)})
        raise
    finally:
        audit = input_audit(out, meta)
        meta.update(audit)
        meta["updated"] = now()
        if not audit["production_sources_unchanged"] or not audit["snapshot_inputs_unchanged"]:
            meta["status"] = "failed_input_integrity"
        dump(metadata, meta)
    if not meta["production_sources_unchanged"] or not meta["snapshot_inputs_unchanged"]:
        raise RuntimeError("Production or snapshot inputs changed")
    if args.phase in ("synth", "impl", "all"):
        collect(out, meta)
    print("KARATSUBA_FULL_TOP_REQUESTED_PHASE_PASS " + args.phase, flush=True)


if __name__ == "__main__":
    main()
