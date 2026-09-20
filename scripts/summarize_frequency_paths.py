"""Summarize Vivado timing-path reports without changing implementation inputs."""
import argparse
import collections
import json
import re
from pathlib import Path


def summarize(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    paths = []
    for block in re.split(r"(?=Slack \((?:MET|VIOLATED)\))", text)[1:]:
        def field(pattern):
            match = re.search(pattern, block)
            if not match:
                raise ValueError(f"Missing {pattern} in {path}")
            return match.group(1).strip()
        paths.append({
            "slack_ns": float(field(r"Slack \([^)]*\)\s*:\s*([-\d.]+)ns")),
            "source": field(r"Source:\s*([^\r\n]+)"),
            "destination": field(r"Destination:\s*([^\r\n]+)"),
            "data_delay": field(r"Data Path Delay:\s*([^\r\n]+)"),
            "logic_levels": field(r"Logic Levels:\s*([^\r\n]+)"),
        })
    if not paths:
        raise ValueError(f"No timing paths in {path}")
    return {"report": str(path), "path_count": len(paths),
            "unique_sources": dict(collections.Counter(p["source"] for p in paths)),
            "worst": paths[0], "paths": paths}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("reports", type=Path, nargs="+")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    results = [summarize(p) for p in args.reports]
    args.output.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    for result in results:
        print(json.dumps({k: result[k] for k in ("report", "path_count", "worst")}))
