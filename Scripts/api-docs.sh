#!/usr/bin/env bash
# Build the generated API reference (DocC) for one or more modules, the same
# way the Swift Package Index builds it from the list in `.spi.yml`.
#
#   Scripts/api-docs.sh              every module named in .spi.yml
#   Scripts/api-docs.sh Ollin        one module
#   Scripts/api-docs.sh --open Ollin build it, then open it in Xcode
#
# It fails on a documentation warning, because the two things DocC catches are
# things nothing else here does: a doc comment pointing at a symbol that no
# longer exists, and a parameter documented under a name the signature dropped.
#
# The DocC plugin is deliberately not a dependency of this package (the index
# no longer needs one, and a plugin dependency is resolved by everybody who
# depends on Ollin), so this drives SwiftPM and `docc` directly.
set -euo pipefail

cd "$(dirname "$0")/.."
out=".build/docs"
graphs=".build/out/symbolgraph"
open_it=""

targets=()
for arg in "$@"; do
    case "$arg" in
        --open) open_it="yes" ;;
        *) targets+=("$arg") ;;
    esac
done
if [ ${#targets[@]} -eq 0 ]; then
    while IFS= read -r line; do targets+=("$line"); done < <(
        sed -n '/documentation_targets/,$p' .spi.yml | sed -n 's/^ *- \([A-Za-z][A-Za-z0-9]*\)$/\1/p'
    )
fi

mkdir -p "$out"

# The manifest and the package must not drift apart. A library product added to
# Package.swift and forgotten in .spi.yml would ship with no reference at all,
# and nothing else would say so. Only checked on a full run, since naming a
# target on the command line is how you look at one in isolation.
if [ $# -eq 0 ] || [ "${1:-}" = "--open" ]; then
    swift package dump-package > "$out/package.json"
    python3 - "$out/package.json" <<'CHECK'
import json, re, sys
# The C shim carries the shared CPU/GPU struct header and no API of its own.
skip = {"COllinShaders"}
products = {p["name"] for p in json.load(open(sys.argv[1]))["products"]
            if "library" in json.dumps(p["type"])} - skip
listed = set(re.findall(r"^ *- ([A-Za-z][A-Za-z0-9]*)$", open(".spi.yml").read(), re.M))
missing = sorted(products - listed)
extra = sorted(listed - products - skip)
if missing:
    print("api-docs: .spi.yml documents no reference for: " + ", ".join(missing))
if extra:
    print("api-docs: .spi.yml names something that is not a library product: " + ", ".join(extra))
sys.exit(1 if missing or extra else 0)
CHECK
fi

echo "==> symbol graphs for the whole package"
swift package dump-symbol-graph > "$out/symbol-graph.log" 2>&1 || {
    tail -20 "$out/symbol-graph.log"; exit 1; }

failed=0
for target in "${targets[@]}"; do
    # One module per archive: its own graph plus the extension graphs it writes
    # for types it extends ("Module@Other.symbols.json"), never a dependency's
    # own graph, which docc reads as a second root page.
    mine="$out/graphs/$target"
    rm -rf "$mine"
    mkdir -p "$mine"
    cp "$graphs/$target.symbols.json" "$mine/"
    cp "$graphs/$target@"*.symbols.json "$mine/" 2>/dev/null || true

    catalog=""
    if [ -d "Sources/$target/$target.docc" ]; then catalog="Sources/$target/$target.docc"; fi

    log="$out/$target.log"
    set +e
    # shellcheck disable=SC2086
    xcrun docc convert $catalog \
        --additional-symbol-graph-dir "$mine" \
        --fallback-display-name "$target" \
        --fallback-bundle-identifier "art.ollin.$target" \
        --output-path "$out/$target.doccarchive" > "$log" 2>&1
    status=$?
    set -e
    warnings=$(grep -c '^warning:' "$log" || true)
    if [ "$status" -ne 0 ] || [ "$warnings" -ne 0 ]; then
        printf '%-18s %s warning(s), see %s\n' "$target" "$warnings" "$log"
        grep '^warning:' "$log" | head -5 | sed 's/^/    /'
        failed=1
    else
        pages=$(find "$out/$target.doccarchive/data" -name '*.json' | wc -l | tr -d ' ')
        printf '%-18s clean, %s pages\n' "$target" "$pages"
    fi
done

if [ -n "$open_it" ]; then open "$out/${targets[0]}.doccarchive"; fi
[ "$failed" -eq 0 ] || { echo; echo "The index builds the same thing, so a warning here is a warning there."; exit 1; }
