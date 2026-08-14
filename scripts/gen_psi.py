#!/usr/bin/env python3
"""Generate Montgomery-domain psi^i and psi^-i tables for negacyclic NTT."""

from pathlib import Path
from gen_params import N, QW, find_parameters

P = find_parameters()
Q, PSI, R = P["Q"], P["PSI"], 1 << QW


def table(inverse: bool) -> list[int]:
    root = pow(PSI, -1, Q) if inverse else PSI
    return [pow(root, i, Q) * R % Q for i in range(N)]


def main() -> None:
    out_dir = Path(__file__).resolve().parents[1] / "mem"
    out_dir.mkdir(exist_ok=True)
    generated = {}
    for name, inverse in (("psi.mem", False), ("psi_inv.mem", True)):
        values = table(inverse)
        (out_dir / name).write_text(
            "".join(f"{x:016x}\n" for x in values), encoding="ascii"
        )
        generated[name] = values
        print(f"wrote {name}")

    n_inv = pow(N, -1, Q)
    fused = [(factor * n_inv) % Q for factor in generated["psi_inv.mem"]]
    (out_dir / "psi_inv_ninv.mem").write_text(
        "".join(f"{x:016x}\n" for x in fused), encoding="ascii"
    )
    print("wrote psi_inv_ninv.mem")


if __name__ == "__main__":
    main()
