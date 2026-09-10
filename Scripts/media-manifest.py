#!/usr/bin/env python3
"""Read and write Examples/media.json, the one place the example media's
address is written down.

    media-manifest.py read  <manifest> <example>
    media-manifest.py skip  <manifest> <example> <reason> [digest]
    media-manifest.py write <manifest> <example> <WxH> <seconds> <frame> \
                            <length> <motion> <loop> <loopSmall> <still> \
                            <stillSmall> <hash>

`read` prints `seconds frame digest standing` for one example, with `-` where
the row says nothing, so a run keeps a per-example override that somebody set
by hand and can tell an example it has already answered for from a new one.
`standing` is `media`, `over`, or `-`.
`write` merges one row and `skip` records why an example has no media at all;
either way the file is rewritten sorted, so the diff of a sweep is one line
per example rather than a reshuffle. An example moves between the two lists
rather than appearing in both.
"""
import json
import os
import sys
from datetime import date

BASE = "https://media.ollin.art"


def load(path):
    if os.path.exists(path):
        with open(path) as f:
            data = json.load(f)
    else:
        data = {}
    data.setdefault("base", BASE)
    data.setdefault("examples", {})
    data.setdefault("passedOver", {})
    return data


def save(path, data):
    data["examples"] = dict(sorted(data["examples"].items()))
    data["passedOver"] = dict(sorted(data["passedOver"].items()))
    with open(path, "w") as f:
        json.dump(data, f, indent=2, sort_keys=False)
        f.write("\n")


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    action, path, example = sys.argv[1], sys.argv[2], sys.argv[3]
    data = load(path)

    if action == "read":
        row = data["examples"].get(example)
        standing = "media" if row else ("over" if example in data["passedOver"] else "-")
        if row is None:
            row = data["passedOver"].get(example, {})
        if not isinstance(row, dict):      # an older file wrote the reason as a bare string
            row = {}
        print(f"{row.get('seconds', '-')} {row.get('frame', '-')} "
              f"{row.get('source', '-')} {standing}")
        return

    if action == "skip":
        data["examples"].pop(example, None)
        row = {"reason": sys.argv[4], "rendered": date.today().isoformat()}
        if len(sys.argv) > 5:
            row["source"] = sys.argv[5]
        data["passedOver"][example] = row
        save(path, data)
        return

    size, seconds, frame, length, motion = sys.argv[4:9]
    files = sys.argv[9:13]
    source = sys.argv[13]
    width, height = (int(n) for n in size.split(","))
    names = ("loop", "loopSmall", "still", "stillSmall")
    row = {
        "width": width,
        "height": height,
        "length": length,
        "seconds": float(seconds),
        "frame": int(frame),
        "motion": float(motion),
        "source": source,
        "rendered": date.today().isoformat(),
        "bytes": {n: os.path.getsize(f) for n, f in zip(names, files)},
    }
    for name, suffix in zip(names, ("loop.mp4", "loop-640.mp4", "still.jpg", "still-640.jpg")):
        row[name] = f"examples/{example}/{suffix}"
    data["passedOver"].pop(example, None)
    data["examples"][example] = row
    save(path, data)


main()
