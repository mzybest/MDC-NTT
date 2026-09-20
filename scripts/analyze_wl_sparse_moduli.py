#!/usr/bin/env python3
"""Analyze q = 2**n - c*2**s + 1 using only the Python standard library.

The default enumerates prime candidates and prints JSON without changing files.
Use --check-arithmetic to repeat the exhaustive 16-bit Montgomery-round audit.
Use --output PATH to write the JSON explicitly as UTF-8.

This is a mathematical exploration of the generalized modulus family. It does
not implement, simulate, or synthesize that family in RTL.
"""

import argparse
import json
from pathlib import Path


WORD_BITS = 16
N_VALUES = tuple(range(55, 65))
S_VALUES = (13, 14, 15)
C_VALUES = (1, 3, 5, 7, 9, 11, 13, 15)
# This witness set is deterministic for integers strictly below 2**64.
MR_BASES = (2, 325, 9375, 28178, 450775, 9780504, 1795265022)
SMALL_PRIMES = (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37)


def is_prime64(value):
    """Exact deterministic Miller-Rabin primality test for value < 2**64."""
    if value >= 1 << 64:
        raise ValueError("is_prime64 only supports integers below 2**64")
    if value < 2:
        return False
    for prime in SMALL_PRIMES:
        if value % prime == 0:
            return value == prime

    odd_part = value - 1
    exponent = 0
    while odd_part & 1 == 0:
        odd_part >>= 1
        exponent += 1
    for base in MR_BASES:
        base %= value
        if base == 0:
            continue
        residue = pow(base, odd_part, value)
        if residue in (1, value - 1):
            continue
        for _ in range(exponent - 1):
            residue = residue * residue % value
            if residue == value - 1:
                break
        else:
            return False
    return True


def arithmetic_bounds():
    """Closed-form bounds; this function does not run the exhaustive audit."""
    radix = 1 << WORD_BITS
    bounds = []
    for s in S_VALUES:
        for c in C_VALUES:
            extra_bits = (c - 1).bit_length()
            offset_minus_one = c * (1 << s) - 1
            kappa = (offset_minus_one + radix - 1) // radix
            bounds.append({
                "s": s,
                "c": c,
                "c_times_m_width": WORD_BITS + extra_bits,
                "d_width": s + extra_bits,
                "max_d": offset_minus_one - kappa,
                "kappa": kappa,
            })
    return bounds


def check_arithmetic():
    """Repeat the original 24 * 65536 multiplier-word checks, without RTL."""
    radix = 1 << WORD_BITS
    mask = radix - 1
    checked_n = (55, 64)
    checked_high = (0, (1 << 113) - 1)
    cases = 0
    maximum_d = 0
    maximum_cm = 0

    for s in S_VALUES:
        low_bits = WORD_BITS - s
        remainder_mask = (1 << low_bits) - 1
        for c in C_VALUES:
            offset = c * (1 << s)
            q_low = (1 - offset) & mask
            kappa = (offset - 1 + radix - 1) // radix
            d_width = s + (c - 1).bit_length()
            local_maximum_d = 0

            for m in range(radix):
                cm = c * m
                d = m * (offset - 1) // radix
                shortcut = (cm >> low_bits) - int(
                    m > ((cm & remainder_mask) << s)
                )
                if shortcut != d or not 0 <= d < 1 << d_width:
                    raise ArithmeticError(f"d formula/width failed: s={s}, c={c}, m={m}")

                # Multiplication by -q_low is a permutation modulo 2**16.
                x = (-m * q_low) & mask
                if (-x * (1 + offset)) & mask != m:
                    raise ArithmeticError(f"inverse formula failed: s={s}, c={c}, m={m}")
                if (x + m * q_low) // radix != kappa * m - d:
                    raise ArithmeticError(f"low carry failed: s={s}, c={c}, m={m}")

                for n in checked_n:
                    high_shift = n - WORD_BITS
                    correction = (m << high_shift) - d
                    if d == 0:
                        concatenated = m << high_shift
                    else:
                        middle_ones = ((1 << (high_shift - d_width)) - 1) << d_width
                        low_complement = (~(d - 1)) & ((1 << d_width) - 1)
                        concatenated = ((m - 1) << high_shift) | middle_ones | low_complement
                    if concatenated != correction or not 0 <= correction < 1 << n:
                        raise ArithmeticError(
                            f"correction failed: n={n}, s={s}, c={c}, m={m}"
                        )
                    q = (1 << n) - offset + 1
                    for high_word in checked_high:
                        t = (high_word << WORD_BITS) | x
                        if (t + m * q) // radix != high_word + correction:
                            raise ArithmeticError(
                                f"round failed: n={n}, s={s}, c={c}, m={m}, high={high_word}"
                            )
                        cases += 1
                local_maximum_d = max(local_maximum_d, d)
                maximum_cm = max(maximum_cm, cm)

            expected_maximum_d = offset - 1 - kappa
            if local_maximum_d != expected_maximum_d:
                raise ArithmeticError(f"maximum d failed: s={s}, c={c}")
            maximum_d = max(maximum_d, local_maximum_d)

    return {
        "status": "PASS",
        "evidence": "Executed by --check-arithmetic in this invocation",
        "m_values_per_s_c": radix,
        "s_c_combinations": len(S_VALUES) * len(C_VALUES),
        "n_values_checked": list(checked_n),
        "high_words_checked": [str(value) for value in checked_high],
        "round_identity_cases": cases,
        "max_d": maximum_d,
        "max_c_times_m": maximum_cm,
    }


def analyze(run_arithmetic=False):
    primes = []
    for n in N_VALUES:
        for s in S_VALUES:
            for c in C_VALUES:
                q = (1 << n) - c * (1 << s) + 1
                if is_prime64(q):
                    if (q - 1) % 8192 or not ((q - 1) >> s) & 1:
                        raise ArithmeticError("Unexpected negacyclic root-order condition")
                    primes.append({
                        "n": n, "s": s, "c": c,
                        # Strings preserve exact values in JSON consumers with
                        # IEEE-754 number representations.
                        "q_decimal": str(q), "q_hex": hex(q),
                        "v2_q_minus_one": s,
                    })
    result = {
        "math_only": True,
        "RTL_support": False,
        "rtl_support_scope": "The generalized (n,s,c) family has not been implemented or synthesized",
        "modulus_family": "q = 2^n - c*2^s + 1",
        "word_bits": WORD_BITS,
        "n_values": list(N_VALUES),
        "s_values": list(S_VALUES),
        "c_values": list(C_VALUES),
        "candidate_count": len(N_VALUES) * len(S_VALUES) * len(C_VALUES),
        "prime_count": len(primes),
        "primality_method": {
            "name": "deterministic 64-bit Miller-Rabin",
            "exclusive_upper_bound": str(1 << 64),
            "bases": list(MR_BASES),
        },
        "count_by_n": {str(n): sum(p["n"] == n for p in primes) for n in N_VALUES},
        "count_by_c": {str(c): sum(p["c"] == c for p in primes) for c in C_VALUES},
        "count_by_s": {str(s): sum(p["s"] == s for p in primes) for s in S_VALUES},
        "count_matrix_n_by_c": {
            "columns_c": list(C_VALUES),
            "rows": {str(n): [sum(p["n"] == n and p["c"] == c for p in primes)
                              for c in C_VALUES] for n in N_VALUES},
        },
        "primes": primes,
        "formulas": {
            "conditions": "B=2^w; n>=w; 0<s<w; 2s>=w; q>0",
            "m": "-x*(1+c*2^s) mod B, where x=T mod B",
            "d": "floor(c*m/2^(w-s)) - [m > ((c*m mod 2^(w-s))*2^s)]",
            "kappa": "ceil((c*2^s-1)/B)",
            "low_carry": "kappa*m-d; it is not generally m-d when c*2^s>B",
            "correction": "m*2^(n-w)-d",
            "next_round": "floor(T/B)+correction",
            "concatenation_condition": "n-w >= D, D=s+ceil(log2(c)); handle d=0 separately",
        },
        "arithmetic_bounds": arithmetic_bounds(),
        "arithmetic_check": check_arithmetic() if run_arithmetic else {"status": "NOT_RUN"},
        "limitations": [
            "Primality and root-order checks are not a security-strength or FHE-parameter validation.",
            "The c*m constant product and expanded d widths require new RTL beyond the fixed-q implementation.",
            "Zero reduction DSPs, LUT cost, frequency and latency cannot be generalized without implementation and synthesis.",
        ],
    }
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-arithmetic", action="store_true",
                        help="run all 65536 multiplier words for each of the 24 (s,c) pairs")
    parser.add_argument("--output", type=Path,
                        help="optional JSON destination, written using UTF-8")
    args = parser.parse_args()
    report = analyze(run_arithmetic=args.check_arithmetic)
    serialized = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(serialized, encoding="utf-8")
    print(serialized, end="")


if __name__ == "__main__":
    main()
