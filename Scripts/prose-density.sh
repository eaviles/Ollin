#!/bin/zsh
#
# Scripts/prose-density.sh: measure the colon/semicolon density of Guide prose.
#
#   Scripts/prose-density.sh                    # every chapter and appendix
#   Scripts/prose-density.sh Guide/05-Noise.md  # specific files
#
# The "setup: punchline" sentence is the single most common cause of jumpy
# prose in the Guide (see Guide/AUTHORING.md, "Watch the colon habit"). This
# counts sentence-internal colons and semicolons in prose only, skipping code
# blocks, headings, figure embeds, and callout blocks, then reports prose lines
# per construction. Higher is calmer; the practical bar is 2.5 or above.

cd "$(dirname "$0")/.." || exit 1

files=("$@")
if [ ${#files[@]} -eq 0 ]; then
    files=(Guide/[0-9]*.md Guide/[A-D]-*.md)
fi

printf "%-30s %6s %7s %6s %9s\n" FILE LINES COLONS SEMIS DENSITY
for f in "${files[@]}"; do
    prose=$(awk '/^```/{c=!c;next} !c' "$f" | grep -v '^<img' | grep -v '^#' | grep -v '^>')
    n=$(echo "$prose" | grep -c '[a-z]')
    c=$(echo "$prose" | grep -o ': [a-z]' | wc -l | tr -d ' ')
    s=$(echo "$prose" | grep -o ';' | wc -l | tr -d ' ')
    d=$(echo "scale=1; $n / ($c + $s + 0.001)" | bc)
    printf "%-30s %6s %7s %6s %9s\n" "${f:t}" "$n" "$c" "$s" "$d"
done
