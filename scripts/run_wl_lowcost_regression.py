"""Run unchanged Q64 regression against the selected default WL implementation.
No input memories or original testbenches are regenerated or edited.
"""
import argparse
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = Path(r"D:\modeltech64_2020.4\win64")
OUT = ROOT / "reports/wl_lowcost_modmul/regression"
WORK = ROOT / "questa_work_wl_lowcost_regression"

def run(exe, args, label, marker=None):
    log = OUT / (label + ".log")
    if exe == "vsim":
        args = [*args, "-l", str(OUT / (label + ".transcript.log"))]
    with log.open("w") as stream:
        p = subprocess.run([str(BIN / (exe + ".exe")), *args], cwd=ROOT,
                           stdout=stream, stderr=subprocess.STDOUT,
                           creationflags=subprocess.CREATE_NO_WINDOW)
    text = log.read_text(errors="replace")
    if p.returncode or (marker and marker not in text) or re.search(r"# \*\* (Fatal|Error):", text):
        print(text[-7000:], flush=True)
        raise RuntimeError(f"{label} failed; see {log}")
    print(f"PASS {label}", flush=True)
    if label == "tb_natural_ab":
        for line in text.splitlines():
            if "NATURAL_AB_CYCLES" in line or "DIRECTED_LOGICAL_RESULT" in line:
                print(line, flush=True)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-unit", action="store_true")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    baseline = (ROOT / "scripts/run_q64_core_control_localization_regression.bat").read_text()
    files = list(dict.fromkeys(re.findall(r"(?:rtl|sim)\\[A-Za-z0-9_]+\.sv", baseline)))
    if not args.skip_unit:
        files.append("sim/tb_wlmont_lowcost.sv")
    if not WORK.exists():
        run("vlib", [WORK.name], "vlib")
    run("vlog", ["-sv", "-work", WORK.name, *files], "compile")
    tests = ["tb_top_data_bram", "tb_mont_mul_wl", "tb_gs_butterfly",
             "tb_gs_mdc_core", "tb_gs_mdc_core_ntt_only", "tb_poly_mul_top_wavefront"]
    if not args.skip_unit:
        tests.insert(0, "tb_wlmont_lowcost")
    for tb in tests:
        run("vsim", ["-c", "-lib", WORK.name, tb, "-do", "run -all; quit -f"], tb, tb + " PASS")
    run("vsim", ["-c", "-lib", WORK.name, "-gUSE_LOAD_PREPROCESS=0",
        "-gFUSE_INTT_SCALE_IN_POST=1", "-gUSE_FINAL_UNIT_TWIDDLE_BYPASS=1",
        "-gUSE_TOP_DATA_BRAM=1", "-gUSE_SHARED_PERIPH_MONT=1",
        "tb_poly_mul_top_dual_forward", "-do", "run -all; quit -f"],
        "tb_dual_forward_bram_shared", "tb_poly_mul_top_dual_forward PASS")
    run("vsim", ["-c", "-lib", WORK.name, "tb_poly_mul_top_dual_forward_natural_ab",
        "-do", "run -all; quit -f"], "tb_natural_ab", "tb_poly_mul_top_dual_forward_natural_ab PASS")
    print("WL_LOWCOST_REGRESSION_PASS", flush=True)
