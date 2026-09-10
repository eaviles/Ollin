#!/usr/bin/env python3
"""Tile a folder of clips into one grid, and write the result into the manifest.

    media-heroes.py tile   <folder> <cell> <across> <out.mp4>
    media-heroes.py record <manifest> <hero> <still> <clip>

`tile` lays the folder's clips out in order, each cropped to a square of
`cell` pixels, `across` of them per row. Every clip is trimmed to the same
length first, or a short one freezes while the rest keep running.

`record` writes the two addresses into `heroes.<name>`, each carrying a token
taken from the file's own bytes: the files are served as immutable for a year,
which is what a picture nobody edits wants, and a rebuilt one has to be a
different address or every reader keeps the old one.
"""
import glob
import hashlib
import json
import os
import subprocess
import sys


def tile(folder, cell, across, out):
    files = sorted(glob.glob(f"{folder}/*.mov") + glob.glob(f"{folder}/*.mp4"))
    files = [f for f in files if os.path.basename(f) != os.path.basename(out)]
    if not files:
        sys.exit("nothing to tile")
    scale = "".join(
        f"[{i}:v]trim=0:6,setpts=PTS-STARTPTS,scale={cell}:{cell}:"
        f"force_original_aspect_ratio=increase,crop={cell}:{cell}[v{i}];"
        for i in range(len(files)))
    layout = "|".join(f"{(i % across) * cell}_{(i // across) * cell}" for i in range(len(files)))
    refs = "".join(f"[v{i}]" for i in range(len(files)))
    command = ["ffmpeg", "-y", "-loglevel", "error"]
    for f in files:
        command += ["-i", f]
    command += [
        "-filter_complex", f"{scale}{refs}xstack=inputs={len(files)}:layout={layout}[out]",
        "-map", "[out]", "-c:v", "libx264", "-profile:v", "high", "-level", "4.0",
        "-crf", "22", "-preset", "slow", "-pix_fmt", "yuv420p",
        "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
        "-maxrate", "6M", "-bufsize", "12M", "-g", "60", "-an",
        "-movflags", "+faststart", out,
    ]
    subprocess.run(command, check=True)
    print(f"  tiled {len(files)} cells, {across} across")


def record(manifest, name, still, clip):
    def token(path):
        with open(path, "rb") as f:
            return hashlib.md5(f.read()).hexdigest()[:8]
    data = json.load(open(manifest))
    hero = data.setdefault("heroes", {}).setdefault(name, {})
    hero["image"] = f"heroes/{name}-hero.jpg?v={token(still)}"
    hero["clip"] = f"heroes/{name}-hero.mp4?v={token(clip)}"
    first = ("base", "heroes", "covers", "groups")
    out = {k: data[k] for k in first if k in data}
    out.update({k: v for k, v in data.items() if k not in out})
    with open(manifest, "w") as f:
        json.dump(out, f, indent=2)
        f.write("\n")
    print(f"  {name}: {hero['image']}")


if len(sys.argv) < 2:
    sys.exit(__doc__)
if sys.argv[1] == "tile":
    tile(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5])
elif sys.argv[1] == "record":
    record(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
else:
    sys.exit(__doc__)
