#!/usr/bin/env python3
"""Read and write Examples/media.json, the one place the example media's
address is written down.

    media-manifest.py read  <manifest> <example>
    media-manifest.py write <manifest> <example> <WxH> <seconds> <frame> \
                            <length> <loop> <loopSmall> <still> <stillSmall> <hash>

`read` prints `seconds frame` for one example, with `-` where the row says
nothing, so a run keeps a per-example override that somebody set by hand.
`write` merges one row and rewrites the file sorted, so the diff of a sweep
is one line per example rather than a reshuffle.
"""
import json
import os
import sys
from datetime import date

BASE = "https://media.ollin.art"


def load(path):
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return {"base": BASE, "examples": {}}


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    action, path, example = sys.argv[1], sys.argv[2], sys.argv[3]
    data = load(path)
    row = data["examples"].get(example, {})

    if action == "read":
        print(f"{row.get('seconds', '-')} {row.get('frame', '-')}")
        return

    size, seconds, frame, length = sys.argv[4:8]
    files = sys.argv[8:12]
    source = sys.argv[12]
    width, height = (int(n) for n in size.split(","))
    names = ("loop", "loopSmall", "still", "stillSmall")
    row = {
        "width": width,
        "height": height,
        "length": length,
        "seconds": float(seconds),
        "frame": int(frame),
        "source": source,
        "rendered": date.today().isoformat(),
        "bytes": {n: os.path.getsize(f) for n, f in zip(names, files)},
    }
    for name, suffix in zip(names, ("loop.mp4", "loop-640.mp4", "still.jpg", "still-640.jpg")):
        row[name] = f"examples/{example}/{suffix}"
    data["examples"][example] = row
    data["examples"] = dict(sorted(data["examples"].items()))
    data.setdefault("base", BASE)
    with open(path, "w") as f:
        json.dump(data, f, indent=2, sort_keys=False)
        f.write("\n")


main()
