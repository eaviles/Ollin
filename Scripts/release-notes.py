#!/usr/bin/env python3
"""
Scripts/release-notes.py <version>: one release's changelog entry as a GitHub
release body.

    Scripts/release-notes.py 0.2.0 > notes.md
    gh release create 0.2.0 --title "Ollin 0.2.0" --notes-file notes.md --latest

Reads the `## [<version>]` section of CHANGELOG.md and rewrites every relative
link in it to the file at that tag on GitHub, since a release page does not
resolve a relative link the way a page in the repository does. Anchors ride
along; absolute links, mail links, and the link reference lines at the foot
of the file are left alone. Prints how many links it rewrote on stderr, so a
count of zero on an entry that plainly has links reads as the failure it is.

When the tag is already in this clone, every rewritten link is read against
the tree at that tag, and a path that is not there stops the run by name. A
section rewritten after its release can name a page that has moved since (a
chapter renumbered, a page split), and the release page would link nowhere.
"""
import re
import subprocess
import sys

if len(sys.argv) != 2:
    sys.exit(__doc__.strip())
version = sys.argv[1]
text = open("CHANGELOG.md", encoding="utf-8").read()
match = re.search(r"^## \[" + re.escape(version) + r"\][^\n]*\n(.*?)(?=^## \[|\Z)",
                  text, re.S | re.M)
if not match:
    sys.exit(f"release-notes: CHANGELOG.md has no entry for {version}")
body = match.group(1).strip("\n")
body = re.sub(r"^\[[^\]]+\]: https?://\S+\n?", "", body, flags=re.M).rstrip("\n")

count = 0
tagged = subprocess.run(["git", "rev-parse", "-q", "--verify", f"refs/tags/{version}"],
                        capture_output=True).returncode == 0
missing = []


def absolute(link):
    global count
    label, target = link.group(1), link.group(2)
    if re.match(r"^(https?:|mailto:|#)", target):
        return link.group(0)
    count += 1
    path, _, anchor = target.partition("#")
    if tagged and subprocess.run(["git", "cat-file", "-e", f"{version}:{path.rstrip('/')}"],
                                 capture_output=True).returncode != 0:
        missing.append(target)
    url = f"https://github.com/eaviles/Ollin/blob/{version}/{path}"
    return f"[{label}]({url}#{anchor})" if anchor else f"[{label}]({url})"


body = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", absolute, body)
sys.stderr.write(f"release-notes: rewrote {count} relative links\n")
if missing:
    for target in missing:
        sys.stderr.write(f"release-notes: not in the tree at {version}: {target}\n")
    sys.exit(f"release-notes: {len(missing)} link(s) would lead nowhere on the {version} page")
print(body)
