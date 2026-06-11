#!/usr/bin/env python3
"""Reference radix-2 GS transforms and Montgomery helpers."""

from gen_params import N, QW, find_parameters

P = find_parameters()
Q, R = P["Q"], 1 << QW
OMEGA, PSI = P["OMEGA"], P["PSI"]


def to_mont(x: int) -> int:
    return (x % Q) * R % Q


def from_mont(x: int) -> int:
    return x * pow(R, -1, Q) % Q


def gs_ntt(values: list[int], inverse: bool = False) -> list[int]:
    """DIF GS transform. Output is bit-reversed; input/output share one domain."""
    a = list(values)
    root = pow(OMEGA, -1, Q) if inverse else OMEGA
    distance = N // 2
    while distance:
        step = N // (2 * distance)
        for base in range(0, N, 2 * distance):
            for j in range(distance):
                x, y = a[base + j], a[base + j + distance]
                a[base + j] = (x + y) % Q
                a[base + j + distance] = (x - y) * pow(root, j * step, Q) % Q
        distance //= 2
    if inverse:
        ninv = pow(N, -1, Q)
        a = [x * ninv % Q for x in a]
    return a


def bit_reverse_permute(a: list[int]) -> list[int]:
    bits = (len(a) - 1).bit_length()
    out = [0] * len(a)
    for i, x in enumerate(a):
        out[int(f"{i:0{bits}b}"[::-1], 2)] = x
    return out


def cyclic_mul(a: list[int], b: list[int]) -> list[int]:
    fa, fb = gs_ntt(a), gs_ntt(b)
    product_br = [x * y % Q for x, y in zip(fa, fb)]
    return bit_reverse_permute(gs_ntt(bit_reverse_permute(product_br), True))


def negacyclic_mul(a: list[int], b: list[int]) -> list[int]:
    twist = [pow(PSI, i, Q) for i in range(N)]
    ta = [x * w % Q for x, w in zip(a, twist)]
    tb = [x * w % Q for x, w in zip(b, twist)]
    c = cyclic_mul(ta, tb)
    return [x * pow(w, -1, Q) % Q for x, w in zip(c, twist)]


if __name__ == "__main__":
    sample = list(range(N))
    transformed = gs_ntt(sample)
    restored = bit_reverse_permute(gs_ntt(bit_reverse_permute(transformed), True))
    assert restored == sample
    print("NTT/INTT round trip: PASS")
