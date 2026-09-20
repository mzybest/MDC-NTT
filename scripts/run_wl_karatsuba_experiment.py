"""Snapshot-based unit comparison: 60-bit schoolbook vs 9-leaf Karatsuba."""
import argparse,csv,hashlib,json,os,re,shutil,subprocess
from datetime import datetime
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
QUESTA=Path(r"D:\modeltech64_2020.4\win64")
VIVADO=Path(r"D:\Vivado\2026.1\Vivado\bin\vivado.bat")
FILES=["rtl/params_pkg.sv","rtl/intmul_64x64_24x17.sv",
       "rtl/intmul_60x60_karatsuba4_experimental.sv","rtl/wlmont_round16.sv",
       "rtl/mont_mul_wl.sv","sim/mont_mul_wl_karatsuba14_experimental.sv",
       "sim/wl_karatsuba_bench_top.sv","sim/tb_wl_karatsuba.sv",
       "scripts/run_wl_karatsuba_bench.tcl","scripts/run_wl_karatsuba_experiment.py"]
PRODUCTION=["rtl/params_pkg.sv","rtl/intmul_64x64_24x17.sv","rtl/wlmont_round16.sv",
            "rtl/mont_mul_wl.sv","rtl/gs_butterfly.sv","rtl/mdc_stage.sv",
            "rtl/gs_mdc_core.sv","rtl/gs_mdc_core_ntt_only.sv",
            "rtl/poly_mul_top_dual_forward.sv","rtl/peripheral_mont_pool.sv"]
def now():return datetime.now().isoformat()
def dump(p,x):p.write_text(json.dumps(x,indent=2)+"\n",encoding="utf-8")
def hashes(files,root=ROOT):
    return {p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in files}
def run(cmd,cwd,log,marker=None):
    print("START "+str(log),flush=True)
    with log.open("w",encoding="utf-8") as f:
        p=subprocess.run([str(x) for x in cmd],cwd=cwd,stdout=f,stderr=subprocess.STDOUT,
                         creationflags=subprocess.CREATE_NO_WINDOW)
    s=log.read_text(errors="replace")
    if p.returncode or (marker and marker not in s) or re.search(r"# \*\* (?:Error|Fatal):|^ERROR:",s,re.M):
        print(s[-9000:],flush=True)
        raise RuntimeError(f"failed {log} exit={p.returncode}")
    print("PASS "+str(log),flush=True)
    return s
def resource(s,label):
    m=re.search(r"^\|\s*"+re.escape(label)+r"\*?\s*\|\s*([\d.]+)\s*\|",s,re.M)
    if not m:raise ValueError("Missing utilization row "+label)
    return float(m.group(1)) if "." in m.group(1) else int(m.group(1))
def collect(out,require_complete=False):
    timing_path=out/"timing.csv"
    if not timing_path.exists():return []
    with timing_path.open(newline="") as f: timing=list(csv.DictReader(f))
    if require_complete and len(timing)!=4:raise RuntimeError("incomplete routed results")
    rows=[]
    for t in timing:
        d=out/f"kind{t['kind']}_impl{t['impl']}"
        ts=(d/"route_timing.rpt").read_text(errors="replace")
        lines=ts.splitlines()
        hi=next(i for i,l in enumerate(lines) if "WNS(ns)" in l)
        vals=lines[hi+2].split()
        r={"kind":"integer" if t["kind"]=="0" else "montgomery",
           "implementation":"schoolbook" if t["impl"]=="0" else "karatsuba4",
           "input_contract_bits":60,"core_cycles":int(t["core_cycles"]),"II_cycles":1,
           "wrapper_extra_cycles":2,
           "reg_to_reg_wns_ns":float(t["reg_to_reg_wns_ns"]),
           "reg_to_reg_whs_ns":float(t["reg_to_reg_whs_ns"]),
           "data_path_delay_ns":float(t["data_path_delay_ns"]),
           "startpoint":t["startpoint"],"endpoint":t["endpoint"],
           "all_paths_wns_ns":float(vals[0]),"all_paths_whs_ns":float(vals[4]),
           "all_paths_setup_failing_endpoints":int(vals[2]),"all_paths_hold_failing_endpoints":int(vals[6])}
        for pfx,name in [("bench","route_utilization.rpt"),("kernel","kernel_route_utilization.rpt")]:
            s=(d/name).read_text(errors="replace")
            for key,label in [("dsp","DSPs"),("lut","Slice LUTs"),("ff","Slice Registers"),
                              ("slices","Slice"),("bram36_equivalent","Block RAM Tile")]:
                r[pfx+"_"+key]=resource(s,label)
        for key in ("unconstrained_internal_endpoints","no_input_delay","no_output_delay"):
            mt=re.search(r"checking "+key+r" \((\d+)\)",ts)
            r[key]=int(mt.group(1)) if mt else None
        route=(d/"route_status.rpt").read_text()
        mt=re.search(r"# of nets with routing errors\.+\s*:\s*(\d+)",route)
        r["routing_errors"]=int(mt.group(1)) if mt else None
        rows.append(r)
    data={"part":"xc7vx485tffg1761-2","vivado":"2026.1","period_ns":6.667,
          "fixed_modulus":"0x0fffffffffffc001","R":"2^64",
          "scope":"fresh routed OOC, equal 60-bit operand range and registered IO boundary",
          "full_top_tested":False,"board_timing_signoff":False,
          "results":rows,
          "limitations":["No Fmax or power measurement","OOC IO timing model is not a board signoff",
                         "Kernel and wrapper occupied Slice counts are not additive",
                         "Not a replacement for arbitrary 64-bit operands"]}
    dump(out/"comparison.json",data)
    if rows:
        with (out/"comparison.csv").open("w",newline="") as f:
            w=csv.DictWriter(f,fieldnames=rows[0].keys());w.writeheader();w.writerows(rows)
    print(json.dumps(rows,indent=2),flush=True)
    return rows
def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--sim-only",action="store_true")
    ap.add_argument("--out",type=Path)
    ap.add_argument("--collect",type=Path)
    args=ap.parse_args()
    if args.collect:collect(args.collect.resolve(),True);return
    out=(args.out or ROOT/"reports/wl_lowcost_modmul/karatsuba4"/datetime.now().strftime("%Y%m%d_%H%M%S")).resolve()
    out.mkdir(parents=True,exist_ok=False)
    print("RUN_DIRECTORY="+str(out),flush=True)
    snap=out/"source_snapshot"
    for rel in FILES:
        dst=snap/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,dst)
    protected=sorted(set(PRODUCTION+[p.relative_to(ROOT).as_posix() for folder,pattern in [("rtl","*.sv"),("sim","*.sv"),("mem","*.mem")] for p in (ROOT/folder).glob(pattern)]))
    meta={"started":now(),"status":"prepared","source_sha256_before":hashes(FILES),
          "protected_sha256_before":hashes(protected),"production_default_changed":False,
          "full_top_tested":False,"shared_external_input_width_bits":60}
    dump(out/"metadata.json",meta)
    tmp=out/"process_temp";tmp.mkdir()
    os.environ["TEMP"]=str(tmp);os.environ["TMP"]=str(tmp)
    try:
        sd=out/"sim";sd.mkdir()
        run([QUESTA/"vlib.exe","work"],sd,sd/"vlib.log")
        run([QUESTA/"vlog.exe","-sv","-work","work",*[snap/p for p in FILES if p.endswith(".sv")]],
            sd,sd/"compile.log")
        s=run([QUESTA/"vsim.exe","-c","-lib","work","tb_wl_karatsuba","-l",sd/"transcript.log",
               "-do","onerror {quit -code 1}; run -all; quit -f"],sd,sd/"simulation.log","tb_wl_karatsuba PASS")
        observations=[l for l in s.splitlines() if any(k in l for k in ("KARATSUBA","PASS","SEED","COUNTS"))]
        dump(out/"simulation.json",{"pass":True,"observations":observations})
        for l in observations:print(l,flush=True)
        meta["simulation_finished"]=now();meta["status"]="simulation_passed";dump(out/"metadata.json",meta)
        if not args.sim_only:
            run([VIVADO,"-mode","batch","-nojournal","-log",out/"vivado.log",
                 "-source",snap/"scripts/run_wl_karatsuba_bench.tcl","-tclargs",snap,out],
                out,out/"vivado_console.log","WL_KARATSUBA_BENCH_PASS")
            collect(out,True)
        meta["status"]="completed_sim" if args.sim_only else "completed_all"
    except Exception as e:
        meta["status"]="failed";meta["error"]=str(e)
        raise
    finally:
        meta["finished"]=now()
        meta["source_sha256_after"]=hashes(FILES)
        meta["protected_sha256_after"]=hashes(protected)
        meta["sources_unchanged"]=meta["source_sha256_before"]==meta["source_sha256_after"]==hashes(FILES,snap)
        meta["production_and_mem_unchanged"]=meta["protected_sha256_before"]==meta["protected_sha256_after"]
        dump(out/"metadata.json",meta)
    if not meta["sources_unchanged"] or not meta["production_and_mem_unchanged"]:
        raise RuntimeError("Input source or production/golden changed during run")
    print("WL_KARATSUBA_EXPERIMENT_PASS",flush=True)
if __name__=="__main__":main()