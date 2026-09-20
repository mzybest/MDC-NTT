#!/usr/bin/env python3
"""Independently check current RTL trace and proposed 4-bank scheduling.

Run scripts/run_quad_inverse_audit.ps1 first. No RTL or test-vector mutation.
Reference arithmetic uses natural-order iterative DIT, independent of GS/C2.
"""
from __future__ import annotations

import csv
import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'reports' / 'quad_inverse_audit'


def rev(x: int, bits: int) -> int:
    return int(f'{x:0{bits}b}'[::-1], 2)


def transform(values: list[int], root: int, q: int) -> list[int]:
    n = len(values)
    bits = n.bit_length() - 1
    a = [values[rev(i, bits)] for i in range(n)]
    size = 2
    while size <= n:
        factor = pow(root, n // size, q)
        half = size // 2
        for base in range(0, n, size):
            w = 1
            for j in range(half):
                u, v = a[base+j], a[base+j+half] * w % q
                a[base+j], a[base+j+half] = (u+v) % q, (u-v) % q
                w = w * factor % q
        size *= 2
    return a


def params() -> dict[str, int]:
    source = (ROOT / 'rtl' / 'params_pkg.sv').read_text()
    constants = {k: int(v, 16) for k, v in re.findall(r"(\w+)\s*=\s*64'h([0-9a-fA-F]+)", source)}
    constants['N'] = int(re.search(r'parameter int N\s*=\s*(\d+)', source)[1])
    constants['QW'] = int(re.search(r'parameter int QW\s*=\s*(\d+)', source)[1])
    assert constants['QW'] == 64 and constants['N'] == 4096, 'Audit binds to active Q64/N4096'
    return constants


def read_mem(name: str) -> list[int]:
    return [int(x, 16) for x in (ROOT / 'mem' / name).read_text().split()]


def audit_trace() -> tuple[dict, dict, dict]:
    p = params()
    n, q, psi, omega = p['N'], p['Q'], p['PSI'], p['OMEGA']
    half, bits = n // 2, n.bit_length() - 1
    rm = pow(2, 64, q)
    ri = pow(rm, -1, q)
    aa, bb = read_mem('input_a.mem'), read_mem('input_b.mem')
    a = [v * ri % q for v in aa]
    b = [v * ri % q for v in bb]
    ah = transform([v * pow(psi, i, q) % q for i, v in enumerate(a)], omega, q)
    bh = transform([v * pow(psi, i, q) % q for i, v in enumerate(b)], omega, q)
    ch = [x*y % q for x, y in zip(ah, bh)]
    (OUT/'c_ntt_reference.mem').write_text(''.join(f'{v*rm%q:016x}\n' for v in ch))
    iraw = transform(ch, pow(omega, -1, q), q)
    expected_result = [v * pow(n, -1, q) * pow(psi, -i, q) % q * rm % q
                       for i, v in enumerate(iraw)]
    assert expected_result == read_mem('golden_result.mem')
    rows = defaultdict(list)
    for row in csv.reader((OUT / 'rtl_trace.csv').open()):
        rows[row[0]].append(row[1:])
    for tag in ('READ_A', 'PRE', 'FWD', 'PW', 'INTT_READ', 'INTT_IN', 'INTT_OUT', 'POST'):
        assert len(rows[tag]) == half, (tag, len(rows[tag]))
        cycles = [int(row[0]) for row in rows[tag]]
        assert cycles == list(range(cycles[0], cycles[0] + half)), tag
    for r, row in enumerate(rows['READ_A']):
        assert int(row[1]) == r
    for r, row in enumerate(rows['PRE']):
        inds = (r, r+half)
        expected = [aa[i] * pow(psi, i, q) % q for i in inds]
        expected += [bb[i] * pow(psi, i, q) % q for i in inds]
        assert [int(v, 16) for v in row[1:]] == expected, ('PRE', r)
    for r, row in enumerate(rows['FWD']):
        j = rev(r, bits-1)
        expected = [ah[j]*rm % q, ah[j+half]*rm % q, bh[j]*rm % q, bh[j+half]*rm % q]
        assert int(row[1]) == r and [int(v, 16) for v in row[2:]] == expected, ('FWD', r)
    for r, row in enumerate(rows['PW']):
        j = rev(r, bits-1)
        assert int(row[1]) == r
        assert [int(v, 16) for v in row[2:]] == [ch[j]*rm % q, ch[j+half]*rm % q], ('PW', r)
    for r, row in enumerate(rows['INTT_READ']):
        assert int(row[1]) == r and int(row[2]) == rev(r, bits-1)
    for r, row in enumerate(rows['INTT_IN']):
        assert [int(v, 16) for v in row[2:]] == [ch[r]*rm % q, ch[r+half]*rm % q], ('INTT_IN', r)
    for r, row in enumerate(rows['INTT_OUT']):
        j = rev(r, bits-1)
        assert [int(v, 16) for v in row[2:]] == [iraw[j]*rm % q, iraw[j+half]*rm % q], ('INTT_OUT', r)
    for row in rows['POST']:
        i, j = int(row[1]), int(row[2])
        assert [int(v, 16) for v in row[3:]] == [expected_result[i], expected_result[j]]
    start = int(rows['START'][0][0])
    timing = {tag: {'first': int(rows[tag][0][0])-start,
                    'last': int(rows[tag][-1][0])-start,
                    'count': len(rows[tag])}
              for tag in ('READ_A','PRE','FWD','PW','INTT_READ','INTT_IN','INTT_OUT','POST','DONE')}
    assert timing['DONE']['first'] == 8623
    assert timing['PW']['first'] > timing['READ_A']['last']
    assert timing['INTT_READ']['first'] == timing['PW']['last']
    assert timing['INTT_IN']['first'] == timing['PW']['last'] + 1
    stage_timing = {}
    for name in ('STAGE_A', 'STAGE_B'):
        stage_timing[name] = [[int(c)-start, int(s), int(count)] for c, s, count in rows[name]]
    result = {
        'status': 'PASS', 'N': n, 'Q': hex(q), 'cycle_origin': 'accepted compute start = 0',
        'start_absolute': start, 'timing': timing,
        'A_last_read_to_first_C_write': timing['PW']['first']-timing['READ_A']['last'],
        'A_last_core_input_to_first_C_write': timing['PW']['first']-timing['PRE']['last'],
        'C_last_write_to_INTT_first_input': timing['INTT_IN']['first']-timing['PW']['last'],
        'independent_bit_reverse_copy_cycles': 0,
        'forward_coefficients_compared': 2*n, 'pointwise_coefficients_compared': n,
        'inverse_input_coefficients_compared': n, 'inverse_output_coefficients_compared': n,
        'post_coefficients_compared': n, 'stage_timing': stage_timing,
    }
    return result, timing, stage_timing


def audit_banks(n: int) -> dict:
    b = n.bit_length()-1
    m, h = n//2, n//4
    layouts = []
    for natural_quarters in (False, True):
        ram = [[None]*h for _ in range(4)]
        writes = set()
        for t in range(m):
            inds = [rev(t,b-1), m+rev(t,b-1)]
            dests = ([(i//h,i%h) for i in inds] if natural_quarters else
                     [(t&1,t>>1), (2+(t&1),t>>1)])
            assert dests[0][0] != dests[1][0]
            for i, dest in zip(inds,dests):
                bank, addr = dest
                assert dest not in writes
                writes.add(dest)
                ram[bank][addr] = i
        assert len(writes) == n
        for k in range(h):
            addr = k if natural_quarters else rev(k,b-2)
            assert [ram[bank][addr] for bank in range(4)] == [k+l*h for l in range(4)]
        layouts.append({'layout': 'logical_quarter_write' if natural_quarters else 'physical_even_odd_split',
                        'writes_checked': n,'four_lane_reads_checked':h,'conflicts':0})
    conflict_beats = 0
    result_locations = set()
    first_result_indices = []
    for r in range(h):
        z = rev(r,b-2)
        idx = [2*z,m+2*z,2*z+1,m+2*z+1]
        if r < 8:
            first_result_indices.append(idx)
        quarter_banks = [i//h for i in idx]
        conflict_beats += len(set(quarter_banks)) != 4
        banks = [(i//m)*2+(i&1) for i in idx]
        assert len(set(banks)) == 4
        for i, bank in zip(idx,banks):
            loc = (bank,(i%m)>>1)
            assert loc not in result_locations
            result_locations.add(loc)
    assert len(result_locations) == n
    return {'N': n,'coefficient_storage_bits': n*64,'input_layouts':layouts,
            'result_quarter_bank_conflict_beats':conflict_beats,
            'result_half_parity_bank_conflicts':0,
            'result_bank_rule':'bank = 2*index_MSB + index_LSB; address = index[LOGN-2:1]',
            'first_result_indices':first_result_indices}


def audit_overlap(timing: dict, stages: dict) -> dict:
    n=4096; h=n//4
    ready=[2*rev(k,10)+1 for k in range(h)]
    limits=[ready[k]-k for k in range(h)]
    start=max(limits)
    witnesses=[k for k,v in enumerate(limits) if v==start]
    assert start==1954 and witnesses==[31,63]
    assert all(start+k >= ready[k] for k in range(h))
    assert any(start-1+k < ready[k] for k in range(h))
    # C write at edge t becomes available after that edge. Strict current SDP
    # forbids reading the same address at t; request >= t+1, core sees it +1.
    request_start=start+1
    core_start=start+2
    assert all(request_start+k > ready[k] for k in range(h))
    old_whole_frame_core_start=timing['INTT_IN']['first']-timing['PW']['first']
    proposed_core_abs=timing['PW']['first']+core_start
    collision_audit=[]
    for label in ('STAGE_A','STAGE_B'):
        first={s:c for c,s,count in stages[label] if count==0}
        last={s:c for c,s,count in stages[label] if count==2047}
        for s in range(12):
            # Keep each physical BFU pipeline, compensate A S0 by one cycle
            # at transpose, to match B's existing S0 boundary register.
            new_first=proposed_core_abs if s==0 else proposed_core_abs+(first[s]-first[0])-1024+(label=='STAGE_A')
            depth=0 if s==11 else 1<<(10-s)
            bf=15+int((label=='STAGE_A' and s==11) or (label=='STAGE_B' and s==0))
            old_drain=last[s]+bf+depth
            assert new_first > old_drain, (label,s,new_first,old_drain)
            collision_audit.append({'core':label[-1],'stage':s,'old_drain_estimate':old_drain,
                                    'new_first_estimate':new_first,'free_gap':new_first-old_drain})
    return {'PW_first_write_origin':0,'PW_last_write':2047,
            'abstract_contiguous_start':start,'critical_k':witnesses,
            'strict_SDP_first_read_request':request_start,
            'strict_SDP_first_core_input':core_start,
            'current_whole_frame_first_core_input':old_whole_frame_core_start,
            'maximum_overlap_gain_current_SDP':old_whole_frame_core_start-core_start,
            'stage_overlap_model':'current RTL stage input timings + BFU/delay bounds; no mode-tag RTL implemented',
            'stage_occupancy':collision_audit,
            'minimum_same_stage_free_gap':min(x['free_gap'] for x in collision_audit),
            'global_active_mode_safe':False,'dual_FIFO_context_required_by_occupancy':False}


def main() -> None:
    trace,timing,stages=audit_trace()
    report={'current_RTL':trace,'bank_enumeration':[audit_banks(n) for n in (8,16,32,4096)],
            'overlap':audit_overlap(timing,stages),
            'new_configurable_full_top_RTL_simulated':False,'new_4path_full_top_routed':False}
    (OUT/'layout_audit.json').write_text(json.dumps(report,indent=2)+'\n')
    print('CURRENT_RTL_NUMERICAL_LAYOUT_AUDIT=PASS')
    print(json.dumps({'timing':timing,'A_C_gap':trace['A_last_read_to_first_C_write'],
                      'bank_N4096':report['bank_enumeration'][-1],
                      'overlap_start':report['overlap']['strict_SDP_first_core_input'],
                      'overlap_gain':report['overlap']['maximum_overlap_gain_current_SDP'],
                      'min_stage_gap':report['overlap']['minimum_same_stage_free_gap']},indent=2))


if __name__=='__main__':
    main()
