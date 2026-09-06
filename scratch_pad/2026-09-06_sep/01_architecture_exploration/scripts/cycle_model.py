#!/usr/bin/env python3
"""
Cycle model for arm16: in-order five-stage pipeline fed by a streamed serial fetch.

Stall policy on fetch-not-ready:
  drain  : older instructions keep flowing; a bubble enters decode.
  freeze : all stage registers hold until the next instruction arrives.
Parameters in core cycles: F = fetch per sequential instruction, R = stream restart, D = PSRAM data access.
Workload mix: fractions of instructions that are taken branches (b), loads or stores (m), and dependent on
the previous instruction (d). Forwarding saves stall cycles only when the dependent pair is adjacent in
the pipeline, which happens only when instructions arrive faster than the pipeline depth.
"""

def cpi(policy, F, R, D, b, m, d, fwd, btb_entries=0, on_chip=False):
    if on_chip:                          # program served from on-chip storage: no fetch cost
        return 1.0 + d * (0 if fwd else 2)
    if policy == 'drain':
        seq = F                           # pipeline drains between arrivals; no hazards on the streamed path
        br  = max(R + 2 - btb_entries * F, 2)   # resolve at execute, restart; a cached target hides one F
        mem = D + R + 3                   # issue at memory stage, data access, restart the stream
        return seq + b * br + m * mem
    seq = F                               # freeze: instructions stay packed, one stage per arrival
    haz = d * (1 if fwd else 2)
    br  = 2 * F + R                       # branch resolves after the next arrival, which is wasted
    mem = 2 * F + D + R                   # load issues two arrivals late
    return seq + haz + b * br + m * mem

MIXES = {'straight-line': (0.00, 0.00, 0.30), 'loop-heavy': (0.20, 0.10, 0.40), 'load-heavy': (0.10, 0.30, 0.40)}
ROWS = [
 ("freeze, F16 R40, no fwd",         dict(policy='freeze', F=16, R=40, D=48, fwd=False)),
 ("freeze, F16 R40, fwd",            dict(policy='freeze', F=16, R=40, D=48, fwd=True)),
 ("drain, F16 R40, no fwd",          dict(policy='drain',  F=16, R=40, D=48, fwd=False)),
 ("drain, F16 R40, fwd",             dict(policy='drain',  F=16, R=40, D=48, fwd=True)),
 ("drain, F16 R24 (continuous read)",dict(policy='drain',  F=16, R=24, D=48, fwd=True)),
 ("drain, F16 R24 + 1-entry BTC",    dict(policy='drain',  F=16, R=24, D=48, fwd=True, btb_entries=1)),
 ("drain, F8 R12 (SCK = core)",      dict(policy='drain',  F=8,  R=12, D=24, fwd=True)),
 ("drain, F8 R12 + 1-entry BTC",     dict(policy='drain',  F=8,  R=12, D=24, fwd=True, btb_entries=1)),
 ("on-chip program, no fwd",         dict(policy='drain',  F=16, R=24, D=48, fwd=False, on_chip=True)),
 ("on-chip program, fwd",            dict(policy='drain',  F=16, R=24, D=48, fwd=True,  on_chip=True)),
]

if __name__ == '__main__':
    print(f"{'configuration':<38} " + " ".join(f"{k:>14}" for k in MIXES))
    for name, kw in ROWS:
        print(f"{name:<38} " + " ".join(f"{cpi(b=b, m=m, d=d, **kw):>14.1f}" for (b, m, d) in MIXES.values()))
    print("\ncore cycles per instruction, lower is better; mixes are (taken-branch, load/store, dependent) fractions")
