#!/usr/bin/env python3
"""Value-and-cycle GS/C2 model for one Stage0 transpose plus two subcores.

Each token carries its full-transform DIF array position and field value.
The two delay queues advance EVERY clock, matching rtl/delay_memory.sv.
The current two-path latency is calibrated against the fresh Questa trace.
This is a pre-RTL model, not a claim that configurable RTL has been built.
"""
from __future__ import annotations

import json
from collections import deque
from dataclasses import dataclass

from quad_inverse_layout_audit import OUT, params, rev, transform


@dataclass(frozen=True)
class Token:
    pos: int
    value: int


def shift(events, delay):
    return {t+delay: pair for t,pair in events.items()}


def stage(events, n, sid, q, root, depth, boundary=0, offset=0):
    """One contiguous frame; exact bf_count/C2/flush equations of mdc_stage."""
    times=sorted(events)
    assert times==list(range(times[0], times[-1]+1)), 'MDC frame must be contiguous'
    distance=n>>(sid+1)
    step=1<<sid
    powers=[pow(root,j*step,q) for j in range(distance)]
    bf={}
    for count,t in enumerate(times):
        a,b=events[t]
        j=(count+offset)%distance
        assert b.pos==a.pos+distance, ('pair',sid,count,a.pos,b.pos,distance)
        assert a.pos%(2*distance)<distance and a.pos%distance==j, ('twiddle',sid,count,a.pos,j)
        bf[t+15+boundary]=(Token(a.pos,(a.value+b.value)%q),
                           Token(b.pos,(a.value-b.value)*powers[j]%q))
    if depth==0:
        return bf
    fifo_a=deque([None]*depth)
    fifo_b=deque([None]*depth)
    count=0
    flushing=False
    flush_count=0
    output={}
    for t in range(min(bf),max(bf)+depth+1):
        pair=bf.get(t)
        assert not (flushing and pair is not None)
        u,v=pair if pair is not None else (None,None)
        phase=(count//depth)&1
        da,db=fifo_a[0],fifo_b[0]
        valid=flushing or (pair is not None and (phase or count>=2*depth))
        if valid:
            values=(db,u if phase else da)
            assert all(x is not None for x in values), ('invalid FIFO output',sid,t)
            output[t]=values
        # The actual RAM advances even on bubbles; dummy data is don't-care.
        fifo_a.append(v)
        fifo_a.popleft()
        fifo_b.append(da if phase else u)
        fifo_b.popleft()
        if flushing:
            flush_count+=1
            if flush_count==depth:
                flushing=False
                flush_count=0
        elif pair is not None:
            count+=1
            if count==len(events):
                count=0
                flushing=True
    assert count==0 and not flushing and flush_count==0
    assert len(output)==len(events)
    assert sorted(output)==list(range(min(output),max(output)+1))
    return output


def two_path(values, q, root, mask=None):
    n=len(values); L=n.bit_length()-1; m=n//2
    mask={L-1} if mask is None else mask
    e={k:(Token(k,values[k]),Token(k+m,values[k+m])) for k in range(m)}
    spans=[]
    for s in range(L):
        before=[min(e),max(e)]
        d=n>>(s+2) if s<L-1 else 0
        e=stage(e,n,s,q,root,d,int(s in mask))
        spans.append({'stage':s,'input':before,'output':[min(e),max(e)],'depth':d})
    return shift(e,14),spans


def split_four(values, q, invroot, keep_existing_masks):
    n=len(values); L=n.bit_length()-1; m=n//2; h=n//4
    a={k:(Token(k,values[k]),Token(k+m,values[k+m])) for k in range(h)}
    b={k:(Token(k+h,values[k+h]),Token(k+3*h,values[k+3*h])) for k in range(h)}
    # Candidate 1: both inverse masks use only Stage0 (same total budget).
    # Candidate 2: preserve A@last and B@0; pad A before transpose and B at tail.
    a=stage(a,n,0,q,invroot,0,int(not keep_existing_masks))
    b=stage(b,n,0,q,invroot,0,1,offset=h)
    if keep_existing_masks:
        a=shift(a,1)
    assert sorted(a)==sorted(b)
    u={t:(a[t][0],b[t][0]) for t in a}
    v={t:(a[t][1],b[t][1]) for t in a}
    spans=[]
    for s in range(1,L):
        before=[min(u),max(u)]
        d=n>>(s+2) if s<L-1 else 0
        u=stage(u,n,s,q,invroot,d,int(keep_existing_masks and s==L-1))
        v=stage(v,n,s,q,invroot,d,0)
        spans.append({'stage':s,'input_A':before,'output_A':[min(u),max(u)],
                      'output_B':[min(v),max(v)],'depth_per_FIFO':d})
    u=shift(u,14)
    v=shift(v,14+int(keep_existing_masks))
    assert sorted(u)==sorted(v)
    return {t:u[t]+v[t] for t in u},spans


def check_stream(events, reference, n, four):
    L=n.bit_length()-1; m=n//2
    natural=[None]*n
    for r,t in enumerate(sorted(events)):
        expected_positions=[2*r,2*r+1]+([m+2*r,m+2*r+1] if four else [])
        assert [v.pos for v in events[t]]==expected_positions
        for token in events[t]:
            i=rev(token.pos,L)
            assert token.value==reference[i], ('numeric',n,t,token.pos,i)
            assert natural[i] is None
            natural[i]=token.value
    assert natural==reference
    return natural


def direct_negacyclic(a,b,q):
    n=len(a); out=[0]*n
    for i,x in enumerate(a):
        for j,y in enumerate(b):
            idx=i+j
            out[idx%n]=(out[idx%n]+(x*y if idx<n else -x*y))%q
    return out


def test_size(n):
    p=params(); q=p['Q']
    psi=pow(p['PSI'],4096//n,q); omega=psi*psi%q; iw=pow(omega,-1,q)
    assert pow(psi,n,q)==q-1 and pow(omega,n//2,q)==q-1
    a=[(19*i*i+3*i+7)%q for i in range(n)]
    b=[(5*i*i+17*i+11)%q for i in range(n)]
    a_pre=[x*pow(psi,i,q)%q for i,x in enumerate(a)]
    b_pre=[x*pow(psi,i,q)%q for i,x in enumerate(b)]
    ah=transform(a_pre,omega,q); bh=transform(b_pre,omega,q)
    af,aspans=two_path(a_pre,q,omega)
    bf,bspans=two_path(b_pre,q,omega,{0})
    check_stream(af,ah,n,False);check_stream(bf,bh,n,False)
    assert sorted(af)==sorted(bf)
    ch=[x*y%q for x,y in zip(ah,bh)]
    ir=transform(ch,iw,q)
    old,_=two_path(ch,q,iw)
    check_stream(old,ir,n,False)
    variants=[]
    for keep in (False,True):
        events,spans=split_four(ch,q,iw,keep)
        result=check_stream(events,ir,n,True)
        ni=pow(n,-1,q)
        result=[x*ni*pow(psi,-i,q)%q for i,x in enumerate(result)]
        direct=direct_negacyclic(a,b,q)
        assert result==direct
        bad=[x*pow(n//2,-1,q)*pow(psi,-i,q)%q for i,x in enumerate(ir)]
        assert bad==[x*2%q for x in result]
        assert any(x!=y for x,y in zip(result,bad)), 'bad half scaling must be detected'
        wrong_bank=0
        for values in events.values():
            inds=[rev(x.pos,n.bit_length()-1) for x in values]
            wrong_bank+=len({i//(n//4) for i in inds})<4
            assert len({(i//(n//2))*2+(i&1) for i in inds})==4
        assert wrong_bank==n//4
        delta=max(old)-max(events)
        assert min(old)-min(events)==n//4-int(keep)
        assert delta==n//2-int(keep)
        variants.append({'keep_existing_masks':keep,'inverse_first_output':min(events),
                         'inverse_last_output':max(events),'output_beats':len(events),
                         'inverse_latency_reduction':delta,
                         'full_top_cycle_projection':8623-delta if n==4096 else None,
                         'pair_twiddle_value_order_check':'PASS',
                         'direct_negacyclic_check':'PASS','half_inverse_scale_negative_control':'PASS',
                         'quarter_result_bank_conflict_beats':wrong_bank,
                         'half_parity_result_bank_conflicts':0,'stage_spans':spans})
    return {'N':n,'Q':hex(q),'baseline_first_output':min(old),
            'baseline_last_output':max(old),'forward_A_stage_spans':aspans,
            'forward_B_stage_spans':bspans,'variants':variants}


def main():
    results=[test_size(n) for n in (8,16,32,4096)]
    measured=json.loads((OUT/'layout_audit.json').read_text())['current_RTL']
    t=measured['timing']; large=results[-1]
    assert large['baseline_first_output']==t['INTT_OUT']['first']-t['INTT_IN']['first']
    for label,key in (('STAGE_A','forward_A_stage_spans'),('STAGE_B','forward_B_stage_spans')):
        source={s:c-t['PRE']['first'] for c,s,count in measured['stage_timing'][label] if count==0}
        for span in large[key]:
            assert span['input'][0]==source[span['stage']], (label,span,source)
    report={'status':'PASS','baseline_stage_timing_matches_current_Questa':True,
            'sizes':results,'new_configurable_RTL_simulated':False,'new_full_top_routed':False,
            'implementation_requirements':[
                'Variable frame pairs: N/2 forward, N/4 inverse; reset bf/reorder/flush/output counts at correct frame boundary',
                'CoreB S0 inverse exponent starts at N/4: prefetch its non-unit twiddle before first valid',
                'Only S0 transpose crosses cores; bypass original S0 C2 in inverse mode',
                'Use global N inverse scale, not the subtransform N/2 inverse',
                'Post has four factors and four pool lanes; result banks use index MSB and LSB',
                'No arbitrary valid bubbles; delay_memory advances every clock',
                'Wait for full frame drain before global mode switch, or implement stage-local configuration tags',
            ]}
    (OUT/'cycle_model.json').write_text(json.dumps(report,indent=2)+'\n')
    print('QUAD_INVERSE_CYCLE_VALUE_MODEL=PASS')
    for row in results:
        print(json.dumps({'N':row['N'],'baseline_first':row['baseline_first_output'],
                          'variants':[{k:v for k,v in x.items() if k!='stage_spans'} for x in row['variants']]},indent=2))


if __name__=='__main__':
    main()
