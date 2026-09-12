#!/usr/bin/env python3
"""Read and write Media/media.json, the one place the site media's
address is written down.

    media-manifest.py read  <manifest> <example>
    media-manifest.py skip  <manifest> <example> <reason> [digest]
    media-manifest.py still <manifest> <example> <WxH> <frame> <motion> \
                            <still> <stillSmall> <digest> <reason>
    media-manifest.py write <manifest> <example> <WxH> <seconds> <frame> \
                            <length> <motion> <sound> <loop> <loopSmall> \
                            <still> <stillSmall> <hash>

`read` prints `seconds frame digest standing` for one example, with `-` where
the row says nothing, so a run keeps a per-example override that somebody set
by hand and can tell an example it has already answered for from a new one.
`standing` is `media`, `over`, or `-`.
`still` records an example that draws one picture and holds it: it keeps a
still at both sizes and no clip, since ten seconds of a print that does not
move is worth nobody's bytes. `write` merges a full row and `skip` records why
an example has no media at all;
either way the file is rewritten sorted, so the diff of a sweep is one line
per example rather than a reshuffle. An example moves between the two lists
rather than appearing in both.
"""
import json
import os
import sys
from datetime import date

BASE = "https://media.ollin.art"


def versioned(path, file):
    """The address with a token that changes when the bytes do.

    The files are served as immutable for a year, which is what a picture
    nobody edits wants, but a re-render writes new bytes to the same name and
    every reader who has the old one keeps it. The token is a digest of the
    file itself, so a re-render is a different address and an unchanged one is
    the same address, which is the property a cache needs.
    """
    import hashlib
    with open(file, "rb") as f:
        return f"{path}?v={hashlib.md5(f.read()).hexdigest()[:8]}"


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

    if action == "still":
        size, frame, motion = sys.argv[4:7]
        still, small, source, reason = sys.argv[7:11]
        width, height = (int(n) for n in size.split(","))
        data["passedOver"].pop(example, None)
        data["examples"][example] = {
            "width": width, "height": height, "length": "still",
            "stillBecause": reason,
            "frame": int(frame), "motion": float(motion), "source": source,
            "rendered": date.today().isoformat(),
            "bytes": {"still": os.path.getsize(still), "stillSmall": os.path.getsize(small)},
            "still": versioned(f"examples/{example}/still.jpg", still),
            "stillSmall": versioned(f"examples/{example}/still-640.jpg", small),
        }
        save(path, data)
        return

    if action == "skip":
        data["examples"].pop(example, None)
        row = {"reason": sys.argv[4], "rendered": date.today().isoformat()}
        if len(sys.argv) > 5:
            row["source"] = sys.argv[5]
        data["passedOver"][example] = row
        save(path, data)
        return

    size, seconds, frame, length, motion, sound = sys.argv[4:10]
    files = sys.argv[10:14]
    source = sys.argv[14]
    width, height = (int(n) for n in size.split(","))
    names = ("loop", "loopSmall", "still", "stillSmall")
    row = {
        "width": width,
        "height": height,
        "length": length,
        "seconds": float(seconds),
        "frame": int(frame),
        "motion": float(motion),
        "sound": bool(sound),
        "source": source,
        "rendered": date.today().isoformat(),
        "bytes": {n: os.path.getsize(f) for n, f in zip(names, files)},
    }
    for name, suffix, file in zip(names, ("loop.mp4", "loop-640.mp4", "still.jpg", "still-640.jpg"), files):
        row[name] = versioned(f"examples/{example}/{suffix}", file)
    data["passedOver"].pop(example, None)
    data["examples"][example] = row
    save(path, data)


main()
