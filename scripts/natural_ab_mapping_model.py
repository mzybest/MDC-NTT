#!/usr/bin/env python3
"""Verify the two-lane GS output and C_NTT/INTT bank mapping."""


def bit_reverse(value: int, bits: int) -> int:
    result = 0
    for index in range(bits):
        result |= ((value >> index) & 1) << (bits - 1 - index)
    return result


def main() -> None:
    n = 16
    pair_count = n // 2
    pair_bits = 3

    ac0_logical = [bit_reverse(t, pair_bits) for t in range(pair_count)]
    ac1_logical = [pair_count + value for value in ac0_logical]

    print("N=16 GS two-lane C_NTT mapping")
    print(
        "| t/i | pair bits | rev3(t) | forward out0 logical | "
        "forward out1 logical | C write addr | INTT read addr | "
        "INTT lane0 logical | INTT lane1 logical |"
    )
    print(
        "|---:|:---:|---:|---:|---:|---:|---:|---:|---:|"
    )

    for pair_index in range(pair_count):
        reversed_index = bit_reverse(pair_index, pair_bits)
        intt_read_addr = bit_reverse(pair_index, pair_bits)
        intt_lane0 = ac0_logical[intt_read_addr]
        intt_lane1 = ac1_logical[intt_read_addr]

        assert intt_lane0 == pair_index
        assert intt_lane1 == pair_count + pair_index

        print(
            f"| {pair_index} | {pair_index:03b} | {reversed_index} | "
            f"{ac0_logical[pair_index]} | {ac1_logical[pair_index]} | "
            f"{pair_index} | {intt_read_addr} | "
            f"{intt_lane0} | {intt_lane1} |"
        )

    print("N16_MAPPING_CHECK=PASS")


if __name__ == "__main__":
    main()
