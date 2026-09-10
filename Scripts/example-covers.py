#!/usr/bin/env python3
"""Build the picture that stands for a group of sketches.

    Scripts/example-covers.py            # every group
    Scripts/example-covers.py --no-upload

A group's cell in a listing shows four of its sketches in a 2x2 rather than
one of them, so it reads as a group rather than as a sketch that happens to be
first. A group with fewer than four keeps the 2x2 and fills what it has, since
the shape is what carries the meaning.

Which four is a choice, not a rule, so the list lives in `Examples/media.json`
under `covers` and this only draws it. The pictures come from the same stills
the grids use, fetched at their versioned addresses so a re-rendered sketch is
never taken from a cache, and the result is uploaded beside the examples as
`groups/<name>.jpg`.
"""
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "Examples" / "media.json"
SIZES = {"": 1080, "-640": 640}


def fetch(url, into):
    # Through curl rather than urllib, since the host answers a bare urllib
    # request with a refusal.
    subprocess.run(["curl", "-sSfL", "-o", str(into), url], check=True)


def montage(files, side, out):
    """Four pictures in a 2x2, or as many as there are in the same shape."""
    cell = side // 2
    subprocess.run([
        # This install refuses to run without a font named, even with nothing
        # to write.
        "montage", "-font", "/System/Library/Fonts/Supplemental/Arial.ttf",
        *[str(f) for f in files], "-tile", "2x2",
        "-geometry", f"{cell}x{cell}+0+0", "-background", "#000",
        "-gravity", "center", "-extent", f"{side}x{side}", str(out),
    ], check=True)


def main():
    upload = "--no-upload" not in sys.argv
    data = json.load(open(MANIFEST))
    base, covers = data["base"], data.get("covers", {})
    if not isinstance(next(iter(covers.values()), []), list):
        sys.exit("covers must be a list of examples per group")

    written = {}
    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        for group, examples in sorted(covers.items()):
            rows = [data["examples"][e] for e in examples if e in data["examples"]]
            if not rows:
                print(f"{group}: none of its sketches has a picture")
                continue
            group_key = group.replace("/", "-")
            entry = {"of": examples}
            for suffix, side in SIZES.items():
                source = "still" if side > 640 else "stillSmall"
                files = []
                for n, row in enumerate(rows[:4]):
                    file = work / f"{group_key}-{n}{suffix}.jpg"
                    fetch(f"{base}/{row[source]}", file)
                    files.append(file)
                out = work / f"{group_key}{suffix}.jpg"
                montage(files, side, out)
                token = hashlib.md5(out.read_bytes()).hexdigest()[:8]
                path = f"groups/{group_key}{suffix}.jpg"
                if upload:
                    subprocess.run([
                        "rclone", "copyto", str(out), f"r2:{BUCKET}/{path}",
                        "--header-upload", "Cache-Control: public, max-age=31536000, immutable",
                    ], check=True, capture_output=True)
                entry["image" if not suffix else "imageSmall"] = f"{path}?v={token}"
            written[group] = entry
            print(f"{group}: {len(rows[:4])} of {len(examples)}")

    data["groups"] = dict(sorted(written.items()))
    # Ordered for reading, but nothing is dropped: a key this script does not
    # know about is still the manifest's, and rewriting the file without it
    # deleted the page heroes once already.
    first = ("base", "heroes", "covers", "groups")
    ordered = {k: data[k] for k in first if k in data}
    ordered.update({k: v for k, v in data.items() if k not in ordered})
    with open(MANIFEST, "w") as f:
        json.dump(ordered, f, indent=2)
        f.write("\n")
    print(f"covers: {len(written)} groups")


BUCKET = ""
if "--no-upload" not in sys.argv:
    # The remote is described entirely by the environment, so no secret ever
    # reaches a config file or a command line.
    import os
    settings = {}
    for line in open(pathlib.Path.home() / ".config/ollin/r2.env"):
        if "=" in line and not line.startswith("#"):
            key, value = line.split("=", 1)
            settings[key.strip()] = value.strip()
    BUCKET = settings["R2_BUCKET"]
    os.environ.update({
        "RCLONE_CONFIG_R2_TYPE": "s3",
        "RCLONE_CONFIG_R2_PROVIDER": "Cloudflare",
        "RCLONE_CONFIG_R2_ACCESS_KEY_ID": settings["R2_ACCESS_KEY_ID"],
        "RCLONE_CONFIG_R2_SECRET_ACCESS_KEY": settings["R2_SECRET_ACCESS_KEY"],
        "RCLONE_CONFIG_R2_ENDPOINT": settings["R2_ENDPOINT"],
        "RCLONE_CONFIG_R2_NO_CHECK_BUCKET": "true",
    })

main()
