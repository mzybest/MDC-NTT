"""Exhaustive algebraic check of a candidate early-zero predicate; no RTL edits."""
import argparse
import json
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    radix = 1 << 16
    q = (1 << 60) - (1 << 14) + 1
    inv = pow(q % radix, -1, radix)
    mismatches = []
    zeros = []
    for x in range(radix):
        m = (-x * inv) % radix
        d = (m >> 2) - int(m > ((m & 3) << 14))
        oracle_d = (m * ((1 << 14) - 1)) // radix
        early = x == 0 or (((x >> 2) & 0xfff) == 0xfff and (x >> 14) == ((~x) & 3))
        correction = ((m << 44) if early else
                      (((m - 1) & 0xffff) << 44) | (((1 << 30) - 1) << 14) | ((~(d - 1)) & 0x3fff))
        if d != oracle_d or early != (d == 0) or correction != (m << 44) - oracle_d:
            mismatches.append({"x": x, "m": m, "d": d, "early": early})
        if early:
            zeros.append(hex(x))
    result = {"modulus": hex(q), "input_values": radix, "mismatches": mismatches,
              "zero_x": zeros, "rtl_changed": False, "status": "algebraic_candidate_only",
              "interpretation": "Equivalent for every low word; high word is untouched. No synthesis or timing claim."}
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result))
    if mismatches:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
