#!/bin/zsh
#
# Scripts/llms.sh: write the checkout's llms.txt, or check it.
#
#   Scripts/llms.sh           # rewrite llms.txt at the repository's root
#   Scripts/llms.sh --check   # fail if it is not what the reference writes
#
# llms.txt is the map of this checkout for an assistant helping somebody
# write a sketch: a paragraph on what Ollin is, the commands that look a
# detail up from the checkout (ollin api, ollin docs, ollin examples), the
# quick reference to read first, then one line per Guide chapter and per
# reference page, links as paths from the root. It follows the llms.txt
# convention the site's own index follows, and it is written by the same
# code (SiteBuilder.checkoutIndex), so the two cannot disagree about a page.
#
# Every line of it comes from somewhere else (a page's title, the one line
# the reference index says about it, the groups the index files it under),
# so an edit to any of those stales it. Scripts/preflight.sh runs --check
# on every commit for that reason, not only on a change to this script.
cd "$(dirname "$0")/.." || exit 1
emulate -L zsh
set -o pipefail

check=0
[[ "${1:-}" == "--check" ]] && check=1

swift build --quiet --product OllinDocs || {
    echo "llms: OllinDocs would not build" >&2
    exit 1
}
binary=".build/debug/OllinDocs"
written=$(mktemp "${TMPDIR:-/tmp}/ollin-llms.XXXXXX") || exit 1
trap 'rm -f "$written"' EXIT
"$binary" llms > "$written" || {
    echo "llms: the index could not be written" >&2
    exit 1
}

if [[ $check -eq 1 ]]; then
    if ! cmp -s "$written" llms.txt; then
        echo "llms: llms.txt is not what the reference writes; run Scripts/llms.sh and commit it" >&2
        diff -u llms.txt "$written" | head -40 >&2
        exit 1
    fi
    echo "llms: llms.txt is current ($(wc -l < llms.txt | tr -d ' ') lines)"
    exit 0
fi

cp "$written" llms.txt
echo "llms: wrote llms.txt ($(wc -l < llms.txt | tr -d ' ') lines)"
