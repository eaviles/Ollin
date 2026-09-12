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
#   FRAMES   framing constructions per 100 prose lines, with the one that
#            fires most named beside it. These are the sentence shapes that
#            comment on the material instead of teaching it, and unlike the
#            three above they are a *report, not a bar*: a page uses some of
#            them legitimately, and the number only says whether one has
#            become a tic. Reference points, measured over the Guide: median
#            7, highest chapter 12. Chapter 1 sat at 19 before its 2026-09-11
#            revision pass, with "worth" carrying the same move twelve times,
#            and came out at 4.
#
# A page over a bar is not a defect to fix in one pass. Fix the page you are
# already editing, and watch the number come down over time.
#
# Why a construction and not a word: the tic reworded itself every time
# ("it's worth two minutes", "a habit worth forming", "worth having under
# your hand"), so a repeated-phrase measure missed it, and a repeated-word
# measure just surfaced whatever the chapter was about. Vale cannot see any
# of this either, because every OllinGuide rule matches vocabulary and these
# are ordinary words in a shape. Guide/AUTHORING.md, "Voice and style".

cd "$(dirname "$0")/.." || exit 1

files=("$@")
if [ ${#files[@]} -eq 0 ]; then
    files=(Guide/[0-9]*.md Guide/[A-D]-*.md Docs/**/*.md README.md)
fi

python3 - "${files[@]}" <<'PY'
import pathlib, re, sys

# The framing constructions counted by the FRAMES column. Each one comments on
# the material or on the reader instead of teaching, and each is built from
# ordinary words, which is why no Vale rule can see it. Keep this list short
# and each entry defensible: it is a report, so a loose pattern costs the
# column its meaning. `reader` overlaps OllinGuide.ReaderPrediction on purpose,
# so a page shows the habit here even where a single instance passed there.
FRAMES = {
    "worth":     r"\bworth\s+(?!of\b)\w",
    "reader":    r"\b(trips?\s+(you|people|almost everyone|everyone|up)"
                 r"|will confuse you|confuses?\s+(you|people)"
                 r"|(will |might |may )?surprises?\s+(you|people)"
                 r"|catch(es)? (you|people) out|you'?ll find (this|that|it))",
    "thething":  r"\b(the thing (to|worth|about)|is what it (is|isn'?t))\b",
    "turnsout":  r"\bturns? out\b",
    "ofcourse":  r"\b(of course|needless to say|as you might expect)\b",
    "noticethat": r"\b(notice that|note that|remember that|bear in mind)\b",
}

print(f'{"FILE":32} {"LINES":>6} {"COLONS":>7} {"SEMIS":>6} {"DENSITY":>8} '
      f'{"LONG%":>6} {"ASIDES":>7} {"FRAMES":>7}  TOP')

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
        # A figure's markup is not prose. The tags are indented inside a
        # <picture> block, so the test has to strip first: without that, every
        # themed figure fed its <source> and <img> lines into the counts, and
        # alt text is full of the colons, semicolons and parentheses this
        # measures. That was 612 lines across 33 Guide pages reading as prose.
        stripped = line.lstrip()
        if in_code or stripped.startswith(("<", "#", ">", "|")):
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

    # FRAMES is reported, never starred: some of these are the right sentence
    # to write, and only their pile-up is the habit.
    lower = text.lower()
    hits = {name: len(re.findall(pat, lower)) for name, pat in FRAMES.items()}
    frames = 100 * sum(hits.values()) / lines
    top = max(hits.items(), key=lambda kv: kv[1])
    top_shown = f"{top[0]}:{top[1]}" if top[1] else "-"

    flag = " *" if ((density is not None and density < 2.0)
                    or long_share > 35 or asides > 2.0) else ""
    over_bar += 1 if flag else 0
    shown = f"{density:8.1f}" if density is not None else f'{"-":>8}'
    print(f"{path.name[:32]:32} {lines:6} {colons:7} {semis:6} "
          f"{shown} {long_share:6.0f} {asides:7.2f} {frames:7.1f}  {top_shown}{flag}")

print()
print("goal: DENSITY 2.5 or above, LONG% 20 or below, ASIDES 1.5 or below")
print(f"    * marks a page well past one of them "
      f"(under 2.0, over 35, or over 2.0): {over_bar} page(s)")
print("FRAMES is a report, not a bar: framing constructions per 100 prose "
      "lines, the")
print("    commonest named. Guide median 7, highest chapter 12. Read the page "
      "when one")
print("    construction carries most of the count.")
PY
