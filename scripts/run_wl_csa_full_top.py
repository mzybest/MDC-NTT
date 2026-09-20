"""Reproducible isolated 14/12-cycle full-top integration experiment.
Never edits production RTL, old testbenches, or original memory vectors.
"""
import argparse, csv, difflib, hashlib, json, re, shutil, subprocess
from datetime import datetime
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
QUESTA = Path(r"D:\modeltech64_2020.4\win64")
VIVADO = Path(r"D:\Vivado\2026.1\Vivado\bin\vivado.bat")
TCL = ROOT / "scripts/run_wl_csa_full_top.tcl"
NEW_TBS = [
    "tb_mont_mul_wl_csa_integration",
    "tb_gs_mdc_core_ntt_only_csa_integration",
    "tb_poly_mul_top_dual_forward_csa_integration",
]
OLD_TBS = ["tb_gs_butterfly", "tb_gs_mdc_core", "tb_gs_mdc_core_roundtrip",
           "tb_poly_mul_top_dual_forward_natural_ab"]
DEFAULT_MODULES = ["gs_butterfly", "mdc_stage", "gs_mdc_core", "gs_mdc_core_ntt_only"]
def now():
    return datetime.now().isoformat()
def dump(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
def source_hashes():
    files = [p for folder, ext in [("rtl","*.sv"),("sim","*.sv"),("mem","*.mem")]
             for p in sorted((ROOT/folder).glob(ext))]
    files += [Path(__file__).resolve(), TCL]
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
def run(cmd, cwd, log, marker=None):
    print("START " + str(log), flush=True)
    with log.open("w", encoding="utf-8") as f:
        p = subprocess.run([str(x) for x in cmd], cwd=cwd, stdout=f, stderr=subprocess.STDOUT,
                           creationflags=subprocess.CREATE_NO_WINDOW)
    text = log.read_text(errors="replace")
    if p.returncode or (marker and marker not in text) or re.search(r"# \*\* (?:Error|Fatal):|^ERROR:", text, re.M):
        print(text[-9000:], flush=True)
        raise RuntimeError(f"{log} failed with exit {p.returncode}")
    print("PASS " + str(log), flush=True)
    return text
def prepare(out):
    out.mkdir(parents=True, exist_ok=False)
    # Ordered active synthesis dependency list, copied from the production flow.
    original_flow = (ROOT/"scripts/run_synth_dual_forward_dsp_reduction.tcl").read_text()
    rtl = list(dict.fromkeys(re.findall(r"rtl/[A-Za-z0-9_]+\.sv", original_flow)))
    rtl.insert(rtl.index("rtl/intmul_64x64_24x17.sv")+1, "rtl/intmul_64x64_csa2_experimental.sv")
    meta = {"started":now(), "source_sha256_before":source_hashes(),
            "top":"poly_mul_top_dual_forward", "configuration":"natural_ab_raw_pre_shared",
            "part":"xc7vx485tffg1761-2", "period_ns":6.667, "implementation_period_ns":6.400,
            "production_default_changed":False, "rtl_files":rtl, "status":"prepared",
            "analytical_compute_cycles":{"14":8623, "12":8565},
            "compute_formula":"2*N + 2*LOGN + 1 + (2*LOGN + 5)*L, one BF boundary register",
            "limitations":["External IO timing is unspecified, so internal timing only",
                           "Fixed Q=0x0fffffffffffc001, 60-bit prime in a 64-bit interface",
                           "No Fmax search or power measurement"]}
    for lat in (14,12):
        variant = out/f"lat{lat}"
        snap = variant/"snapshot"
        for folder in ("rtl","sim","mem"):
            (snap/folder).mkdir(parents=True)
        for rel in rtl:
            shutil.copy2(ROOT/rel, snap/rel)
        for name in NEW_TBS+OLD_TBS:
            shutil.copy2(ROOT/"sim"/(name+".sv"), snap/"sim"/(name+".sv"))
        for p in (ROOT/"mem").glob("*.mem"):
            shutil.copy2(p, snap/"mem"/p.name)
        (snap/"rtl_files.txt").write_text("\n".join(rtl)+"\n")
        patches = []
        if lat==12:
            changes = {
                "rtl/params_pkg.sv":[(r"(parameter int MUL_LAT\s*=\s*)14",r"\g<1>12")],
                "rtl/mont_mul_wl.sv":[
                    (r"(localparam int WL_LAT\s*=\s*)14",r"\g<1>12"),
                    (r"intmul_64x64_24x17 u_intmul", "intmul_64x64_csa2_experimental u_intmul"),
                    (r"multiplier: 14 cycles", "multiplier EXPERIMENT SNAPSHOT: 12 cycles")],
                "rtl/poly_mul_top_dual_forward.sv":[(r"(localparam int WL_MONT_LAT\s*=\s*)14",r"\g<1>12")],
            }
            for name in DEFAULT_MODULES:
                changes[f"rtl/{name}.sv"]=[(r"(parameter int MUL_LAT\s*=\s*)14",r"\g<1>params_pkg::MUL_LAT")]
            for rel, replacements in changes.items():
                p=snap/rel
                before=p.read_text()
                after=before
                for pattern,replacement in replacements:
                    after,count=re.subn(pattern,replacement,after)
                    if count!=1:raise RuntimeError(f"Expected one match: {rel} {pattern}, got {count}")
                p.write_text(after,encoding="utf-8")
                patches.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                                   fromfile="production/"+rel,tofile="lat12/"+rel))
        (variant/"snapshot_changes.patch").write_text("".join(patches),encoding="utf-8")
        dump(variant/"snapshot_sha256.json",
             {p.relative_to(snap).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(snap.rglob("*")) if p.is_file()})
    dump(out/"metadata.json",meta)
    return meta
def simulate(out,lat):
    variant=out/f"lat{lat}";snap=variant/"snapshot";logs=variant/"simulation";logs.mkdir(exist_ok=True)
    run([QUESTA/"vlib.exe","work"],snap,logs/"vlib.log")
    rtl=(snap/"rtl_files.txt").read_text().splitlines()
    files=[*rtl,*["sim/"+name+".sv" for name in NEW_TBS+OLD_TBS]]
    run([QUESTA/"vlog.exe","-sv","-work","work",*files],snap,logs/"compile.log")
    cases=[
        ("wl",NEW_TBS[0],[]),
        ("butterfly","tb_gs_butterfly",[]),
        ("butterfly_unit","tb_gs_butterfly",["-gBYPASS_TWIDDLE_MUL=1"]),
        ("ntt_core","tb_gs_mdc_core",["-gUSE_FINAL_UNIT_TWIDDLE_BYPASS=1"]),
        ("roundtrip","tb_gs_mdc_core_roundtrip",[]),
        ("ntt_only",NEW_TBS[1],["-gUSE_FINAL_UNIT_TWIDDLE_BYPASS=1"]),
        ("natural_ab",NEW_TBS[2],[])]
    if lat==14:
        cases.append(("unchanged_natural_ab","tb_poly_mul_top_dual_forward_natural_ab",[]))
    summary={}
    for label,tb,generics in cases:
        s=run([QUESTA/"vsim.exe","-c","-lib","work",*generics,tb,"-l",logs/(label+".transcript.log"),
               "-do","onerror {quit -code 1}; run -all; quit -f"],snap,logs/(label+".log"),tb+" PASS")
        lines=[x for x in s.splitlines() if any(k in x for k in ("_CYCLES","INTEGRATION_PHASES","DIRECTED_LOGICAL_RESULT"," PASS"))]
        summary[label]={"pass":True,"observations":lines}
        for line in lines:print(line,flush=True)
    dump(variant/"simulation.json",summary)
    print(f"CSA_FULL_TOP_SIM_PASS L={lat}",flush=True)
def vivado(out,lat,phase):
    variant=out/f"lat{lat}";d=variant/phase;d.mkdir(exist_ok=True)
    run([VIVADO,"-mode","batch","-nojournal","-log",d/"vivado.log",
         "-source",TCL,"-tclargs",phase,lat,variant/"snapshot",d],
        d,d/"console.log",f"CSA_FULL_TOP_PHASE_PASS {phase} L={lat}")
def resource(s,label,optional=False):
    m=re.search(r"^\|\s*"+re.escape(label)+r"\*?\s*\|\s*([\d.]+)\s*\|",s,re.M)
    if not m:
        if optional:return None
        raise ValueError("Missing resource row "+label)
    return float(m.group(1)) if "." in m.group(1) else int(m.group(1))
def collect(out):
    rows=[]
    for lat in (14,12):
        for phase in ("synth","impl"):
            d=out/f"lat{lat}"/phase
            if not (d/"config.txt").exists():continue
            s=(d/"utilization.rpt").read_text(errors="replace")
            row={"latency":lat,"phase":phase,"compute_cycles":8217+29*lat,
                 "continuous_load_plus_compute_cycles":4096+8217+29*lat}
            for key,label in [("lut","Slice LUTs"),("ff","Slice Registers"),("dsp","DSPs"),
                              ("bram36_equivalent","Block RAM Tile"),("ramb36","RAMB36/FIFO*"),
                              ("ramb18","RAMB18"),("occupied_slices","Slice")]:
                # RAMB36 report heading varies; full report remains authoritative.
                row[key]=resource(s,label,optional=True)
            if phase=="impl":
                with (d/"internal_timing.csv").open() as f:t=next(csv.DictReader(f))
                row.update({"reg_to_reg_wns_ns":float(t["wns_ns"]),
                            "reg_to_reg_whs_ns":float(t["whs_ns"]),
                            "data_path_delay_ns":float(t["data_path_delay_ns"]),
                            "startpoint":t["startpoint"],"endpoint":t["endpoint"]})
                lines=(d/"timing.rpt").read_text(errors="replace").splitlines()
                hi=next(i for i,line in enumerate(lines) if "WNS(ns)" in line)
                vals=lines[hi+2].split()
                row["constrained_wns_ns"]=float(vals[0]);row["constrained_whs_ns"]=float(vals[4])
                row["setup_failing_endpoints"]=int(vals[2]);row["hold_failing_endpoints"]=int(vals[6])
                row["unconstrained_input_count"]=None;row["unconstrained_output_count"]=None
                ts="\n".join(lines)
                for k,name in [("unconstrained_input_count","no_input_delay"),
                               ("unconstrained_output_count","no_output_delay"),
                               ("unconstrained_internal_endpoints","unconstrained_internal_endpoints")]:
                    m=re.search(r"checking "+name+r" \((\d+)\)",ts)
                    if m:row[k]=int(m.group(1))
            rows.append(row)
    dump(out/"comparison.json",{"results":rows,
        "scope":"complete dual-forward top, same fused reduction, isolated source snapshots",
        "board_timing_signoff":False,"period_ns":6.667,"implementation_period_ns":6.400})
    if rows:
        keys=list(dict.fromkeys(k for row in rows for k in row))
        with (out/"comparison.csv").open("w",newline="") as f:
            w=csv.DictWriter(f,fieldnames=keys);w.writeheader();w.writerows(rows)
    print(json.dumps(rows,indent=2),flush=True)
def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--out",type=Path)
    ap.add_argument("--phase",choices=["prepare","sim","synth","impl","all","collect"],default="all")
    ap.add_argument("--latency",type=int,choices=[12,14])
    args=ap.parse_args()
    out=(args.out or ROOT/"reports/wl_lowcost_modmul/csa_full_top"/datetime.now().strftime("%Y%m%d_%H%M%S")).resolve()
    print("RUN_DIRECTORY="+str(out),flush=True)
    if not (out/"metadata.json").exists():meta=prepare(out)
    else:meta=json.loads((out/"metadata.json").read_text())
    try:
        if args.phase in ("all","sim"):
            for lat in ([args.latency] if args.latency else [14,12]):simulate(out,lat)
            meta["simulation_finished"]=now()
        if args.phase in ("all","synth","impl"):
            # Sequential full-top runs avoid two large Vivado memory footprints.
            for lat in ([args.latency] if args.latency else [14,12]):
                for phase in (["synth","impl"] if args.phase=="all" else [args.phase]):
                    vivado(out,lat,phase)
                    meta[f"lat{lat}_{phase}_finished"]=now()
                    dump(out/"metadata.json",meta)
                    collect(out)
        if args.phase=="collect":collect(out)
        meta["status"]="completed_"+args.phase;meta["updated"]=now()
    except Exception as e:
        meta["status"]="failed";meta["error"]=str(e)
        raise
    finally:
        meta["source_sha256_after"]=source_hashes()
        meta["production_sources_unchanged"]=meta["source_sha256_before"]==meta["source_sha256_after"]
        dump(out/"metadata.json",meta)
    if not meta["production_sources_unchanged"]:raise RuntimeError("Production sources changed during experiment")
    print("CSA_FULL_TOP_REQUESTED_PHASE_PASS "+args.phase,flush=True)
if __name__=="__main__":main()