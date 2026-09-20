#!/usr/bin/env python3
"""Audit exact shift/sub replacements for current WL constant products.

Arithmetic proof/check only. No RTL or timing/resource measurement is changed.
Unlike replacing Montgomery reduction, this preserves a*b*R^-1 semantics.
"""
import json
import random
from pathlib import Path
from quad_inverse_layout_audit import params

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/op4_streaming_feasibility'


def main():
    q=params()['Q']; radix=1<<16; mask=radix-1
    qh0=(q>>16)&((1<<24)-1)
    qh1=q>>40
    assert q==(1<<60)-(1<<14)+1
    assert qh0==(1<<24)-1 and qh1==(1<<20)-1
    for m in range(radix):
        old0=m*qh0; old1=m*qh1
        assert old0==(m<<24)-m
        assert old1==(m<<20)-m
        assert old0+(old1<<24)==(m<<44)-m
        # Optional concatenation implementation, with mandatory zero case.
        d=m-1
        cat0=0 if m==0 else (d<<24) | (((1<<24)-1)^d)
        cat1=0 if m==0 else (d<<20) | (((1<<20)-1)^d)
        assert old0==cat0 and old1==cat1
    def redc(t):
        for _ in range(4):
            m=((t&mask)*0xbfff)&mask
            low=(t&mask)+m*(q&mask)
            assert (low&mask)==0
            t=(t>>16)+((m<<44)-m)+(low>>16)
        return t-q if t>=q else t
    rng=random.Random(20260910)
    edge=[0,1,2,65535,65536,(1<<59),q-2,q-1]
    pairs=[(a,b) for a in edge for b in edge]+[(rng.randrange(q),rng.randrange(q)) for _ in range(10000)]
    rinv=pow(1<<64,-1,q)
    for a,b in pairs:
        assert redc(a*b)==a*b*rinv % q
    report={'status':'PASS_ARITHMETIC_EQUIVALENCE_ONLY',
            'q':hex(q),'Q_H0':hex(qh0),'Q_H1':hex(qh1),
            'all_possible_16bit_m_checked':65536,'Montgomery_pairs_checked':len(pairs),
            'identities':['m*(2^24-1)=(m<<24)-m','m*(2^20-1)=(m<<20)-m',
                          'm*(Q>>16)=(m<<44)-m'],
            'current_source':'rtl/wlmont_round16.sv explicitly forces the two constant products into DSPs',
            'candidate_scope':'Replace only constant-product logic, retain registered boundaries and Montgomery semantics. Fixed-Q specialization can retain generic fallback.',
            'structural_DSP_estimate':{'current_per_modmul':20,'input_product_DSPs':12,
                                       'candidate_reduction_DSPs':0,'candidate_per_modmul':12,
                                       'current_26_unit_top':520,'candidate_26_unit_top':312},
            'new_RTL_tested':False,'Vivado_run':False,
            'limits':['DSP estimates assume LUT shift/sub implementation and unchanged 12-DSP product tiling.',
                      'No claim about LUT, FF, critical path, clock frequency or whole-top DSP count after synthesis.',
                      'This is established constant-multiplier specialization, not evidence of publication novelty.',
                      'The optimization specializes the current fixed modulus, not arbitrary 64-bit primes.']}
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'fixed_q_wl_constant_audit.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':
    main()
