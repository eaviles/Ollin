#!/bin/zsh
#
# Scripts/prose-density.sh: score the reader-facing prose for the three habits
# that make it tiring to read (Guide/AUTHORING.md, "Voice and style").
#
#   Scripts/prose-density.sh                    # Guide chapters, Docs, the READMEs
#   Scripts/prose-density.sh Guide/05-Noise.md  # specific files
#
# Vale flags these line by line; this is the page-level view, which is the one
# to work from, because a single long sentence is fine and a page of them is
# the problem. Three numbers, prose only (code blocks, headings, figure embeds,
# and callout blocks are skipped):
#
#   DENSITY  prose lines per sentence-internal colon or semicolon. The
#            "setup: punchline" sentence is a drum hit, and a page of them is
#            exhausting even when each one is good. Higher is calmer; 2.5 or
#            above is the practical bar.
#   LONG%    share of sentences over 25 words. A sentence past that is usually
#            two sentences held together by the punctuation above. 20 or below.
#   ASIDES   parentheses per paragraph (the repo writes one paragraph per
#            line). One aside per paragraph reads as a voice; three read as a
#            footnote pile. 1.5 or below.
#
# A page over a bar is not a defect to fix in one pass. Fix the page you are
# already editing, and watch the number come down over time.

cd "$(dirname "$0")/.." || exit 1

files=("$@")
if [ ${#files[@]} -eq 0 ]; then
    files=(Guide/[0-9]*.md Guide/[A-D]-*.md Docs/**/*.md README.md)
fi

python3 - "${files[@]}" <<'PY'
import pathlib, re, sys

print(f'{"FILE":32} {"LINES":>6} {"COLONS":>7} {"SEMIS":>6} {"DENSITY":>8} {"LONG%":>6} {"ASIDES":>7}')

over_bar = 0
for name in sys.argv[1:]:
    path = pathlib.Path(name)
    if not path.is_file():
        continue
    prose, in_code = [], False
    for line in path.read_text().split("\n"):
        if line.startswith("```"):
            in_code = not in_code
            continue
        if in_code or line.startswith(("<img", "#", ">", "|")):
            continue
        if line.strip():
            prose.append(line)
    body = "\n".join(prose)
    lines = len(prose)
    if lines < 5:
        continue

    # Sentence-internal colons only: a heading colon or a "Note:" label is not
    # the habit this measures.
    colons = len(re.findall(r": [a-z]", body))
    semis = body.count(";")
    parens = body.count("(")
    density = lines / (colons + semis) if colons + semis else None

    text = re.sub(r"`[^`]*`", "CODE", body)
    sentences = [s for line in text.split("\n")
                 for s in re.split(r"(?<=[.!?])\s+(?=[A-Z(])", line)
                 if len(s.split()) >= 3]
    long_share = 100 * sum(1 for s in sentences if len(s.split()) > 25) / max(1, len(sentences))
    asides = parens / lines

    flag = " *" if ((density is not None and density < 2.0)
                    or long_share > 35 or asides > 2.0) else ""
    over_bar += 1 if flag else 0
    shown = f"{density:8.1f}" if density is not None else f'{"-":>8}'
    print(f"{path.name[:32]:32} {lines:6} {colons:7} {semis:6} "
          f"{shown} {long_share:6.0f} {asides:7.2f}{flag}")

print()
print("goal: DENSITY 2.5 or above, LONG% 20 or below, ASIDES 1.5 or below")
print(f"    * marks a page well past one of them "
      f"(under 2.0, over 35, or over 2.0): {over_bar} page(s)")
PY
