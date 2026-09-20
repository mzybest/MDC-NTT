"""Summarize named hierarchy attribution, not isolated arithmetic area."""
import json
from pathlib import Path
import sys

report = Path(sys.argv[1])
stack = []
rows = []
for line in report.read_text(encoding="utf-8").splitlines():
    cells = line.split("|")
    if len(cells) < 12 or not cells[3].strip().isdigit():
        continue
    label = cells[1]
    indent = len(label) - len(label.lstrip())
    name = label.strip()
    if name.startswith("("):
        continue
    while stack and stack[-1][0] >= indent:
        stack.pop()
    stack.append((indent, name))
    rows.append(dict(path="/".join(x[1] for x in stack), name=name,
                     **dict(zip(["lut", "logic_lut", "lutram", "srl", "ff", "bram36", "bram18", "dsp"],
                                map(lambda x: int(x.strip()), cells[3:11])))))

groups = {}
for kind, predicate in {
    "core_rounds": lambda r: "/u_core_" in r["path"] and r["name"].startswith("u_round"),
    "peripheral_rounds": lambda r: "g_shared_periph_pool" in r["path"] and r["name"].startswith("u_round"),
    "retained_mod_add_hierarchy": lambda r: r["name"] == "u_add",
    "retained_mod_sub_hierarchy": lambda r: r["name"] == "u_sub",
    "integer_multipliers": lambda r: r["name"] == "u_intmul",
}.items():
    selected = [r for r in rows if predicate(r)]
    groups[kind] = {"count": len(selected), "named_row_sums": {
        key: sum(r[key] for r in selected)
        for key in ("lut", "logic_lut", "ff", "dsp", "bram36", "bram18")}, "rows": selected}
result = {"source": str(report), "boundary": "Named hierarchy attribution only; physical optimization can move or share logic. Round totals exclude terminal conditional correction. Missing add hierarchy does not imply zero arithmetic cost.", "groups": groups}
report.with_name("resource_summary.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps({k: {a:b for a,b in v.items() if a != "rows"} for k,v in groups.items()}, indent=2))
