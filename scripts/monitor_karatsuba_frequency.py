"""Read-only foreground companion; prints changed log tails every 20 seconds."""
import json
import argparse
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parents[1] / "reports/wl_lowcost_modmul/karatsuba_frequency/20260917")
parser.add_argument("--names", nargs="+", default=["inc160", "targeted170_retry", "targeted180"])
args = parser.parse_args()
root = args.directory.resolve()
names = args.names
seen = {}
for tick in range(270):
    terminal = []
    for name in names:
        folder = root / name
        log = folder / "console.log"
        if log.exists():
            text = log.read_text(encoding="utf-8", errors="replace")
            if seen.get(name) != len(text):
                seen[name] = len(text)
                print(name + ":\n" + "\n".join(text.splitlines()[-5:]), flush=True)
        meta = folder / "metadata.json"
        if meta.exists():
            try:
                data = json.loads(meta.read_text(encoding="utf-8"))
                if data.get("status") in ("completed", "failed"):
                    terminal.append(name)
            except json.JSONDecodeError:
                pass
    if len(terminal) == len(names):
        print("ALL_EXPERIMENTS_TERMINAL", flush=True)
        break
    time.sleep(20)
