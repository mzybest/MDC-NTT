"""Independent Questa checks followed by four local Vivado benchmarks.
All outputs are isolated; production defaults and existing goldens are untouched.
"""
import argparse,csv,hashlib,json,re,subprocess,sys
from datetime import datetime
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
QUESTA=Path(r"D:\modeltech64_2020.4\win64")
VIVADO=Path(r"D:\Vivado\2026.1\Vivado\bin\vivado.bat")
FILES=["rtl/params_pkg.sv","rtl/intmul_64x64_24x17.sv",
       "rtl/intmul_64x64_csa2_experimental.sv","rtl/wlmont_round16.sv",
       "rtl/mont_mul_wl.sv","sim/mont_mul_wl_csa12_experimental.sv",
       "sim/wl_csa_bench_top.sv","sim/tb_wl_csa_latency.sv",
       "scripts/run_wl_csa_bench.tcl"]
def hashes():
    return {p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in FILES}
def run(cmd,cwd,log,marker=None):
    with log.open("w",encoding="utf-8") as f:
        p=subprocess.run([str(x) for x in cmd],cwd=cwd,stdout=f,
                         stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
    s=log.read_text(errors="replace")
    if p.returncode or (marker and marker not in s) or re.search(r"# \*\* (?:Error|Fatal):|^ERROR:",s,re.M):
        print(s[-9000:],flush=True)
        raise RuntimeError(f"failed {log} exit={p.returncode}")
    print("PASS "+str(log),flush=True)
    return s
def resource(s,label):
    m=re.search(r"^\|\s*"+re.escape(label)+r"\*?\s*\|\s*(\d+)\s*\|",s,re.M)
    if not m:raise ValueError("Missing utilization row "+label)
    return int(m.group(1))
def collect(out):
    rows=[]
    with (out/"timing.csv").open(newline="") as f:timing=list(csv.DictReader(f))
    if len(timing)!=4:raise RuntimeError("incomplete routed results")
    for t in timing:
        d=out/f"kind{t['kind']}_impl{t['impl']}"
        timing_lines=(d/"route_timing.rpt").read_text(errors="replace").splitlines()
        hi=next(i for i,line in enumerate(timing_lines) if "WNS(ns)" in line)
        global_values=timing_lines[hi+2].split()
        row={"all_paths_wns_ns":float(global_values[0]),
             "all_paths_whs_ns":float(global_values[4]),
             "all_paths_hold_failing_endpoints":int(global_values[6]),
             "kind":"integer" if t["kind"]=="0" else "montgomery",
             "implementation":"original" if t["impl"]=="0" else "csa2",
             "core_cycles":int(t["core_cycles"]),"wrapper_extra_cycles":2,
             "II_cycles":1,"reg_to_reg_wns_ns":float(t["reg_to_reg_wns_ns"]),
             "reg_to_reg_whs_ns":float(t["reg_to_reg_whs_ns"]),
             "data_path_delay_ns":float(t["data_path_delay_ns"]),
             "startpoint":t["startpoint"],"endpoint":t["endpoint"]}
        for prefix,name in [("bench","route_utilization.rpt"),("kernel","kernel_route_utilization.rpt")]:
            s=(d/name).read_text(errors="replace")
            for key,label in [("dsp","DSPs"),("slice_lut","Slice LUTs"),("ff","Slice Registers"),("occupied_slices","Slice")]:
                row[prefix+"_"+key]=resource(s,label)
        rows.append(row)
    data={"part":"xc7vx485tffg1761-2","vivado":"2026.1","period_ns":6.667,
          "scope":"fresh routed OOC, equal registered IO boundary, explicit common HD.CLK_SRC",
          "register_boundary_extra_cycles":2,"fixed_modulus":"0x0fffffffffffc001",
          "limitations":["No full NTT/poly top integration or route","No Fmax search",
                         "OOC external-port timing is not board-level signoff",
                         "Kernel hierarchy counts and complete benchmark counts reported separately",
                         "Occupied Slice counts by hierarchy are not additive due to physical sharing"],
          "internal_setup_hold_pass":all(r["reg_to_reg_wns_ns"]>=0 and r["reg_to_reg_whs_ns"]>=0 for r in rows),
          "all_paths_setup_hold_pass":all(r["all_paths_wns_ns"]>=0 and r["all_paths_whs_ns"]>=0 for r in rows),
          "interface_hold_violations":"Observed on external inputs to common input registers with current OOC IO constraints; not waived or fixed.",
          "results":rows}
    (out/"comparison.json").write_text(json.dumps(data,indent=2)+"\n",encoding="utf-8")
    with (out/"comparison.csv").open("w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=rows[0].keys());w.writeheader();w.writerows(rows)
    print(json.dumps(data,indent=2),flush=True)
if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--sim-only",action="store_true")
    ap.add_argument("--collect",type=Path)
    args=ap.parse_args()
    if args.collect:collect(args.collect.resolve());sys.exit(0)
    out=ROOT/"reports/wl_lowcost_modmul/csa_latency"/datetime.now().strftime("%Y%m%d_%H%M%S")
    out.mkdir(parents=True,exist_ok=False)
    print("RUN_DIRECTORY="+str(out),flush=True)
    meta={"started":datetime.now().isoformat(),"source_sha256":hashes(),
          "production_default_changed":False,"full_top_tested":False}
    (out/"metadata.json").write_text(json.dumps(meta,indent=2),encoding="utf-8")
    sd=out/"sim";sd.mkdir()
    run([QUESTA/"vlib.exe","work"],sd,sd/"vlib.log")
    run([QUESTA/"vlog.exe","-sv","-work","work",*[ROOT/p for p in FILES if p.endswith(".sv")]],
        sd,sd/"compile.log")
    s=run([QUESTA/"vsim.exe","-c","-lib","work","tb_wl_csa_latency",
           "-l",sd/"transcript.log","-do","onerror {quit -code 1}; run -all; quit -f"],
          sd,sd/"simulation.log","tb_wl_csa_latency PASS")
    for line in s.splitlines():
        if "CSA_COUNTS" in line or "tb_wl_csa_latency PASS" in line:print(line,flush=True)
    if not args.sim_only:
        run([VIVADO,"-mode","batch","-nojournal","-log",out/"vivado.log",
             "-source",ROOT/"scripts/run_wl_csa_bench.tcl","-tclargs",out],
            out,out/"vivado_console.log","WL_CSA_BENCH_PASS")
        collect(out)
    meta.update({"finished":datetime.now().isoformat(),"source_sha256_after":hashes(),
                 "source_unchanged_during_run":meta["source_sha256"]==hashes()})
    (out/"metadata.json").write_text(json.dumps(meta,indent=2),encoding="utf-8")
    if not meta["source_unchanged_during_run"]:raise RuntimeError("Sources changed during experiment")
    print("WL_CSA_EXPERIMENT_PASS",flush=True)
