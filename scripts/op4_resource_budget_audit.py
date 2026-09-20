#!/usr/bin/env python3
"""Necessary multiplier-capacity bounds for the existing OP4 candidate.

Only shifts the complete, internally bubble-free inverse schedule in time.
It does not solve arbitrary stage retiming, folding, or an optimal physical
allocation. Passing this test is necessary, NOT sufficient for feasibility.
"""
import json
import math
from collections import defaultdict
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/op4_streaming_feasibility'


def peak(windows):
    events=defaultdict(int)
    for label,start,end,count in windows:
        events[start]+=count
        events[end+1]-=count
    used=best=0
    when=None
    for t in sorted(events):
        used+=events[t]
        if used>best:
            best,when=used,t
    return best,when


def main():
    base=json.loads((ROOT/'reports/quad_inverse_audit/cycle_model.json').read_text())
    f=next(x for x in base['sizes'] if x['N']==4096)
    audit=json.loads((OUT/'schedule_value_audit.json').read_text())
    inv=next(x for x in audit['cases'] if x['N']==4096)
    fixed=[]
    for core,key in [('A','forward_A_stage_spans'),('B','forward_B_stage_spans')]:
        for row in f[key]:
            if row['stage']==11:
                continue
            # Model issue cycles at modular multiplier, after input/add registers.
            off=1+int(core=='B' and row['stage']==0)
            fixed.append((f'{core}.S{row["stage"]}',row['input'][0]+off,row['input'][1]+off,1))
    fixed += [('Pre',-14,2033,4),('PW',inv['first_pw']-14,inv['last_pw']-14,2)]
    moving=[]
    for row in inv['inverse_stage_rows']:
        if row['stage']==11:
            continue
        off=row['butterfly_latency']-14
        moving.append((f'I{row["stage"]}',row['butterfly_input'][0]+off,row['butterfly_input'][1]+off,1))
    moving.append(('Post',inv['inverse_first_output'],inv['inverse_last_output'],2))
    evaluated=[]
    for delay in range(2049):
        count,when=peak(fixed+[(a,s+delay,e+delay,c) for a,s,e,c in moving])
        evaluated.append((delay,count,when))
    bounds=[]
    for extra in range(7):
        delay,count,when=next(r for r in evaluated if r[1]<=26+extra)
        bounds.append({'extra_modmul':extra,'total_modmul':26+extra,
                       'minimum_uniform_delay_passing_capacity_only':delay,
                       'conditional_compute_cycles':6576+delay,
                       'boundary_fifo_data_words_for_equal_rate_delay':2*delay,
                       'peak_issue_demand':count})
    examples=[]
    for extra,delay in [(6,0),(4,64),(2,256),(3,128)]:
        count,when=peak(fixed+[(a,s+delay,e+delay,c) for a,s,e,c in moving])
        examples.append({'extra_modmul':extra,'uniform_delay':delay,'peak_demand':count,
                         'capacity':26+extra,'passes_necessary_capacity_test':count<=26+extra})
    ops=sum((e-s+1)*c for _,s,e,c in fixed+moving)
    assert ops==83968
    assert evaluated[0][1]==32
    report={'status':'NECESSARY_BOUNDS_ONLY_NOT_FEASIBLE_PARETO_POINTS',
            'scope':[
                'Same forward timing, same 2-path RN inverse stage latencies and continuous 2048-beat windows.',
                'Inverse stages and Post are all shifted by one common delay; no independent per-stage retiming.',
                'Every non-final butterfly issues to a general modular multiplier, even on individual unit twiddles, as in the current regular datapath.',
                'Counts multiplier initiation demand, allowing arbitrary per-cycle sharing and tags.',
                'Ignores ROM, FIFO, routing, physical latency compatibility and pipeline ownership drain; accepted points can still be infeasible.',
                'Changing algorithms, factor specialization, faster subclocks, or selective stage buffering requires a new model.'
            ],'uniform_delay_capacity_bounds':bounds,'hypothetical_examples_checked':examples,
            'batch_work_bound':{'general_modmul_issues_per_job':ops,
                               'II_lower_bound_at_26_units':math.ceil(ops/26),
                               'II_lower_bound_at_32_units':math.ceil(ops/32),
                               'units_required_by_work_count_for_II_2048':math.ceil(ops/2048),
                               'input_bound_with_one_A_and_one_B_coefficient_per_cycle':4096,
                               'note':'Work bounds are necessary only, and assume the current operation counts. They do not prove any achievable job II.'}}
    (OUT/'resource_budget_bounds.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':
    main()
