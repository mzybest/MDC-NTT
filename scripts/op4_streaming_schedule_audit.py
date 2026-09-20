#!/usr/bin/env python3
"""OP4-order streaming candidate: values, C2 state, and physical lifetimes.

This is an architectural model, not RTL or a place-and-route result.
Forward timing uses the existing model calibrated against Questa traces.
New inverse C2s execute the same two-queue/phase/flush equations before BFUs.
Physical allocation is checked for N=4096 only; smaller sizes test ordering.
"""
from __future__ import annotations

import csv
import json
import random
from collections import defaultdict, deque
from dataclasses import dataclass
from pathlib import Path

from quad_inverse_cycle_model import two_path
from quad_inverse_layout_audit import params, rev, transform

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'reports' / 'op4_streaming_feasibility'


@dataclass(frozen=True)
class Token:
    pos: int
    value: int
    frame: str


class C2:
    """Persistent data queues; no data clearing between ownership changes."""
    def __init__(self, depth):
        self.depth = depth
        self.a = deque([Token(-1, 123, 'stale')] * depth)
        self.b = deque([Token(-1, 456, 'stale')] * depth)
        self.last = None

    def tick(self, u, v, phase):
        da, db = self.a.popleft(), self.b.popleft()
        self.a.append(v)
        self.b.append(da if phase else u)
        return db, u if phase else da

    def frame(self, events):
        times = sorted(events)
        assert times == list(range(times[0], times[-1] + 1))
        d = self.depth
        if not d:
            return dict(events)
        if self.last is not None:
            assert times[0] > self.last, 'shared FIFO lifetime conflict'
            for _ in range(self.last + 1, times[0]):
                self.tick(None, None, 0)
        out = {}
        count = 0
        flushing = False
        flush_count = 0
        for t in range(times[0], times[-1] + d + 1):
            pair = events.get(t)
            assert not (flushing and pair is not None)
            phase = (count // d) & 1
            valid = flushing or (pair is not None and (phase or count >= 2*d))
            result = self.tick(*(pair if pair is not None else (None, None)), phase)
            if valid:
                assert all(x is not None and x.pos >= 0 for x in result), 'stale FIFO output'
                out[t] = result
            if flushing:
                flush_count += 1
                if flush_count == d:
                    flushing, flush_count = False, 0
            elif pair is not None:
                count += 1
                if count == len(events):
                    count, flushing = 0, True
        assert not flushing and count == flush_count == 0
        self.last = times[-1] + d
        assert sorted(out) == list(range(times[0]+d, times[-1]+d+1))
        return out


def shifted(events, delay):
    return {t+delay: pair for t, pair in events.items()}


def inverse_stream(events, n, q, invroot, shared_deep=None, context='frame0'):
    bits = n.bit_length()-1
    rows = []
    for j in range(bits):
        depth = 0 if j == 0 else 1 << (j-1)
        incoming = [min(events), max(events)]
        storage = shared_deep if j == bits-1 and shared_deep is not None else C2(depth)
        pairs = storage.frame(events)
        distance = 1 << j
        # Retain the existing B.S0 and A.S11 extra boundary registers.
        latency = 15 + int(j in (1, bits-1))
        out = {}
        for count, t in enumerate(sorted(pairs)):
            a, b = pairs[t]
            assert a.frame == b.frame == context
            assert b.pos == a.pos + distance, ('inverse pair', j, count, a.pos, b.pos)
            assert a.pos % (2*distance) == count % distance
            group = a.pos // (2*distance)
            assert group == count // distance
            exponent = rev(group, bits-1)
            if j == bits-1:
                assert exponent == 0, 'unit-twiddle bypass only belongs to inverse last stage'
            w = pow(invroot, exponent, q)
            out[t+latency] = (Token(a.pos, (a.value+b.value) % q, context),
                             Token(b.pos, (a.value-b.value)*w % q, context))
        rows.append({'stage':j, 'delay_per_fifo':depth, 'c2_input':incoming,
                     'c2_live_until':max(pairs), 'butterfly_input':[min(pairs),max(pairs)],
                     'butterfly_latency':latency, 'butterfly_output':[min(out),max(out)]})
        events = out
    return shifted(events, 14), rows


def check_values(events, a, b, psi, omega, q):
    n = len(a)
    ah = transform([x*pow(psi,i,q) % q for i,x in enumerate(a)], omega, q)
    bh = transform([x*pow(psi,i,q) % q for i,x in enumerate(b)], omega, q)
    ref = transform([x*y % q for x,y in zip(ah,bh)], pow(omega,-1,q), q)
    ni = pow(n,-1,q)
    expected = [x*ni*pow(psi,-i,q) % q for i,x in enumerate(ref)]
    result = [None]*n
    for r,t in enumerate(sorted(events)):
        assert [v.pos for v in events[t]] == [r,r+n//2], 'Post must use natural half-lane indices'
        for token in events[t]:
            assert result[token.pos] is None
            result[token.pos] = token.value*ni*pow(psi,-token.pos,q) % q
    assert result == expected, 'independent natural-order DIT reference mismatch'
    # Direct ring multiplication is independent of all NTT implementations.
    checked = list(range(n)) if n <= 32 else [0,1,2,17,255,1023,2048,4095]
    for k in checked:
        direct = sum(a[i]*b[k-i] if i <= k else -a[i]*b[k-i+n] for i in range(n)) % q
        assert result[k] == direct, ('direct negacyclic',k)
    return len(checked)


def one_case(n, seed):
    p=params(); q=p['Q']; psi=pow(p['PSI'],4096//n,q); omega=psi*psi % q
    assert pow(psi,n,q) == q-1
    rng=random.Random(seed)
    a=[rng.randrange(q) for _ in range(n)]
    b=[rng.randrange(q) for _ in range(n)]
    apre=[v*pow(psi,i,q) % q for i,v in enumerate(a)]
    bpre=[v*pow(psi,i,q) % q for i,v in enumerate(b)]
    af,sa=two_path(apre,q,omega)
    bf,sb=two_path(bpre,q,omega,{0})
    assert sorted(af) == sorted(bf)
    context=f'N{n}_seed{seed}'
    pw={t+14:tuple(Token(x.pos,x.value*y.value % q,context) for x,y in zip(af[t],bf[t])) for t in af}
    for r,t in enumerate(sorted(pw)):
        assert [v.pos for v in pw[t]] == [2*r,2*r+1]
    shared=C2(n//4)
    # Exercise physical A.S0 C2 first with the forward data, then reuse the
    # same queue objects for inverse last-stage C2 without clearing storage.
    first_bf={r+15:(Token(r,(apre[r]+apre[r+n//2])%q,'old_forward'),
                    Token(r+n//2,(apre[r]-apre[r+n//2])*pow(omega,r,q)%q,'old_forward'))
              for r in range(n//2)}
    shared.frame(first_bf)
    inverse,rows=inverse_stream(pw,n,q,pow(omega,-1,q),shared,context)
    checked=check_values(inverse,a,b,psi,omega,q)
    out={'N':n,'seed':seed,'value_pair_order_checks':'PASS',
         'stale_fifo_reuse_check':'PASS','direct_convolution_coefficients_checked':checked,
         'first_pw':min(pw),'last_pw':max(pw),'first_inverse_input':rows[0]['butterfly_input'][0],
         'inverse_first_output':min(inverse),'inverse_last_output':max(inverse),
         'post_first':min(inverse)+14,'post_last':max(inverse)+14,
         'output_pairs':len(inverse),'inverse_stage_rows':rows}
    if n==4096:
        out['allocation']=allocation(sa,sb,rows,min(af),max(af),min(inverse),max(inverse))
        out['compute_done_projection']=max(inverse)+14+1+15
    return out


def allocation(sa,sb,rows,f_first,f_last,i_first,i_last):
    jobs=defaultdict(list)
    # Reserve full occupied pipeline lifetimes, stronger than issue-only checking.
    for core,spans in [('A',sa),('B',sb)]:
        for s in spans:
            lat=15+int((core=='A' and s['stage']==11) or (core=='B' and s['stage']==0))
            jobs[f'{core}.S{s["stage"]}'].append(('forward',s['input'][0],s['input'][1]+lat))
    for lane in range(4):
        jobs[f'pool{lane}'].append(('Pre',-14,2047))
        if lane<2:
            jobs[f'pool{lane}'].append(('PW',f_first,f_last+14))
            jobs[f'pool{lane}'].append(('Post',i_first,i_last+14))
    owners=['A.S0','B.S0','pool2','pool3']+[f'new{k}' for k in range(6)]+['A.S1','A.S11']
    reuse=[]
    for row,owner in zip(rows,owners):
        start=row['butterfly_input'][0]; end=row['butterfly_output'][1]
        row['arithmetic_owner']=owner
        previous_end=max((e for _,_,e in jobs[owner]),default=None)
        reuse.append({'inverse_stage':row['stage'],'owner':owner,'start':start,
                      'previous_pipeline_last':previous_end,
                      'idle_cycles_before_reuse':None if previous_end is None else start-previous_end-1})
        jobs[owner].append((f'I{row["stage"]}',start,end))
    for owner,entries in jobs.items():
        entries.sort(key=lambda x:x[1])
        for old,new in zip(entries,entries[1:]):
            assert old[2] < new[1], ('physical arithmetic conflict',owner,old,new)
    fifo_old_end=sa[0]['output'][1]
    fifo_new_start=rows[-1]['c2_input'][0]
    assert fifo_new_start>fifo_old_end
    # Old A.S0 BFU and old A.S0 C2 intentionally have different owners here.
    assert rows[0]['butterfly_input'][0] < fifo_old_end
    return {'full_arithmetic_pipeline_lifetime_conflicts':0,'reuse':reuse,
            'deep_fifo_owner':'A.S0 two 1024-cycle delay memories',
            'deep_fifo_old_last_output':fifo_old_end,'deep_fifo_inverse_first_input':fifo_new_start,
            'deep_fifo_idle_cycles':fifo_new_start-fifo_old_end-1,
            'additional_inverse_delay_words':sum(2*r['delay_per_fifo'] for r in rows[:-1]),
            'additional_general_modmul_units':6,
            'pool_bfu_adapters':2,
            'separate_BFU_and_C2_ownership_required':True}


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    cases=[one_case(n,20260909+s) for n in (8,16,32,4096) for s in range(2)]
    large=[r for r in cases if r['N']==4096][0]
    calibrated=json.loads((ROOT/'reports/quad_inverse_audit/cycle_model.json').read_text())
    assert calibrated['baseline_stage_timing_matches_current_Questa']
    assert large['first_pw']+15==2271 and large['last_pw']+15==4318
    assert large['compute_done_projection']==6576
    report={'status':'PASS_ARCHITECTURAL_MODEL_ONLY','candidate':'GS RN 2-path streaming with partial arithmetic reuse',
            'time_origin':'first forward-core input; add 15 for current top compute coordinates',
            'cases':cases,'new_RTL_simulated':False,'vivado_synthesis_or_route_run':False,
            'scope_limits':[
                'Single-job internal streaming. Not a claim of accepting another job every 2048 cycles.',
                'Arithmetic is over the ordinary field; new Montgomery-domain RTL still requires verification.',
                'Twiddles are exact mathematical values. ROM ports, prefetch and read routing are not simulated.',
                'New short C2 queues have dedicated storage; only final two 1024-depth queues reuse A.S0.',
                'B.S0 and A.S11 boundary registers are preserved; interconnect needs no extra cycles in this model.',
                'Ownership windows include full arithmetic drain; hardware owner registers/muxes are not RTL-verified.',
                'C2 state persists across forward/inverse ownership change; repeated top-level jobs are not simulated.',
                'LUT/FF/BRAM, achievable clock and complete system area require synthesis and route.'
            ]}
    (OUT/'schedule_value_audit.json').write_text(json.dumps(report,indent=2)+'\n')
    with (OUT/'inverse_stage_schedule.csv').open('w',newline='') as f:
        w=csv.writer(f)
        w.writerow(['inverse_stage','owner','depth_each_FIFO','C2_input_first','C2_live_last',
                    'BFU_input_first','BFU_input_last','BFU_output_last'])
        for r in large['inverse_stage_rows']:
            w.writerow([r['stage'],r['arithmetic_owner'],r['delay_per_fifo'],r['c2_input'][0]+15,
                        r['c2_live_until']+15,r['butterfly_input'][0]+15,
                        r['butterfly_input'][1]+15,r['butterfly_output'][1]+15])
    print(json.dumps({'status':report['status'],'cases':len(cases),
                      'N4096_compute_done_projection':large['compute_done_projection'],
                      'allocation':large['allocation']},indent=2))


if __name__=='__main__':
    main()
