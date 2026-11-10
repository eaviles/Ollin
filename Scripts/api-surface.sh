#!/bin/zsh
#
# Scripts/api-surface.sh: the public API, written down and diffed.
#
#   Scripts/api-surface.sh                # check: every listing under API/ matches the build
#   Scripts/api-surface.sh --record       # rewrite the listings from the build
#   Scripts/api-surface.sh --module M     # one module only (either mode)
#   Scripts/api-surface.sh --no-build     # trust the products already built
#
# Builds each library product, dumps its public surface with the toolchain's
# swift-api-digester, flattens the dump to one line per declaration
# (Scripts/api-surface.py), and compares the result with API/<Module>.txt.
# A difference fails the check and prints the diff. A change to the public
# surface is meant to show up here: run --record, read the diff, and commit
# the listing with the change (the changelog names a rename by both names).
#
# What the listing is for. The 1.0 release is the one where the API settles,
# and from then on every public rename ships a deprecation shim. The listings
# make that discipline mechanical: the last naming sweep before the tag reads
# these files instead of the tree, and after the tag a removed line with no
# `@available(deprecated)` line beside it is the failure mode the shim rule
# exists to catch. Before the tag the check only asks that a change be
# deliberate, which is what --record says.
#
# The listing is toolchain-dependent in its spelling (the digester prints
# types as the compiler that built the module spells them), so it is
# recorded and checked on the development toolchain. CI builds on a runner
# whose Swift may lag, which is why this gate runs from preflight and not
# from the workflow. Preflight runs it whenever Sources/, External/, or the
# manifest changed.

cd "$(dirname "$0")/.." || exit 1
emulate -L zsh
setopt null_glob

record=0
build=1
only=""
while [[ $# -gt 0 ]]; do
    case "$1" in
    --record) record=1 ;;
    --no-build) build=0 ;;
    --module) shift; only="$1" ;;
    --help | -h)
        sed -n '3,33p' "$0" | sed 's|^# \?||'
        exit 0
        ;;
    *) echo "api-surface: unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done

# Every library product with Swift sources. A C target (its sources under an
# include/ folder) is a header, which is its own listing.
manifest=$(swift package dump-package 2>/dev/null)
products=$(jq -r '.products[] | select(.type | has("library")) | .name' <<<"$manifest" \
    | while read -r name; do
        [[ -d "Sources/$name/include" ]] && continue
        echo "$name"
    done)
if [[ -n "$only" ]]; then
    products="$only"
fi
if [[ -z "$products" ]]; then
    echo "api-surface: no library products found (is jq installed?)" >&2
    exit 2
fi

# One build for all of them. `swift build` takes a single --target, and a call
# per module is two to three seconds of planning each even when nothing needs
# compiling: 24 modules were 56 of this script's 61 seconds (2026-11-10). So
# build the one executable whose dependencies reach the most of the modules
# wanted (the snippet checker and the figure runner each import every
# satellite), and then, by name, any module that executable does not reach, so
# a satellite added to the package and to no tool is still built before it is
# read. One module alone (--module) is built by name.
mkdir -p API .build/api
if [[ $build -eq 1 ]]; then
    print -r -- "$manifest" >.build/api/package.json
    plan=$(python3 - .build/api/package.json ${(f)products} <<'PY'
import json, pathlib, sys

manifest = json.load(open(sys.argv[1]))
wanted = set(sys.argv[2:])
depends = {
    target["name"]: [next(iter(entry.values()))[0] for entry in target["dependencies"]]
    for target in manifest["targets"]
}

def reach(name):
    seen, pending = set(), [name]
    while pending:
        current = pending.pop()
        if current in seen:
            continue
        seen.add(current)
        pending.extend(depends.get(current, []))
    return seen

# The one reaching the most of them. Seven executables tie on that (every host
# imports every satellite), and the tie matters: the first by name is the
# gallery, a large app nothing else in a preflight builds, and picking it
# recompiled the gallery after every change to the core. So among equals take
# the snippet checker, which preflight builds next anyway, and failing that
# the one with the fewest sources of its own.
def sources(name):
    target = next(t for t in manifest["targets"] if t["name"] == name)
    folder = pathlib.Path(target.get("path") or f"Sources/{name}")
    return sum(1 for _ in folder.rglob("*.swift"))

executables = sorted(t["name"] for t in manifest["targets"] if t["type"] == "executable")
best = min(executables,
           key=lambda name: (-len(reach(name) & wanted), name != "OllinGuideSnippets", sources(name), name),
           default=None)
covered = reach(best) & wanted if best else set()
if len(covered) < 2:
    covered = set()
else:
    print("product", best)
for name in sorted(wanted - covered):
    print("target", name)
PY
    ) || { echo "api-surface: could not read the package's targets" >&2; exit 2; }
    while read -r kind name; do
        [[ -n "$name" ]] || continue
        swift build "--$kind" "$name" >/dev/null 2>&1 || {
            echo "api-surface: swift build --$kind $name failed" >&2
            exit 1
        }
    done <<<"$plan"
fi

bin=$(swift build --show-bin-path 2>/dev/null)
[[ -d "$bin" ]] || { echo "api-surface: no build products at $bin" >&2; exit 1; }
sdk=$(xcrun --show-sdk-path)
target="arm64-apple-macos$(sw_vers -productVersion | cut -d. -f1)"

# The C products the Swift products import: the generated module maps of the
# build layout in use (the Xcode-style layout writes them beside the
# intermediates, the classic one under each target's build folder), plus the
# checked-in ones under External/.
typeset -a includes
includes=(-I "$bin")
for dir in External/*/include; do
    [[ -f "$dir/module.modulemap" ]] && includes+=(-I "$dir")
done
for map in "$bin"/../../Intermediates.noindex/GeneratedModuleMaps/*.modulemap "$bin"/*.build/module.modulemap; do
    [[ -f "$map" ]] && includes+=(-Xcc "-fmodule-map-file=$map")
done

failed=0
for module in ${(f)products}; do
    json=".build/api/$module.json"
    if ! xcrun swift-api-digester -dump-sdk -module "$module" -o "$json" \
        -sdk "$sdk" -target "$target" "${includes[@]}" 2>".build/api/$module.log"; then
        echo "api-surface: the digester could not load $module:" >&2
        sed 's/^/    /' ".build/api/$module.log" >&2
        failed=1
        continue
    fi
    listing="API/$module.txt"
    fresh=".build/api/$module.txt"
    python3 Scripts/api-surface.py "$json" "$module" >"$fresh" || { failed=1; continue; }
    if [[ $record -eq 1 ]]; then
        cp "$fresh" "$listing"
        echo "api-surface: recorded $listing ($(($(wc -l <"$fresh") - 2)) declarations)"
    elif [[ ! -f "$listing" ]]; then
        echo "api-surface: $listing is missing; run with --record" >&2
        failed=1
    elif ! diff -u "$listing" "$fresh" >".build/api/$module.diff"; then
        echo "api-surface: $module changed its public surface:" >&2
        grep -E '^[-+]' ".build/api/$module.diff" | grep -vE '^(\+\+\+|---)' | sed 's/^/    /' >&2
        failed=1
    fi
done

if [[ $failed -ne 0 ]]; then
    if [[ $record -eq 0 ]]; then
        echo "api-surface: the listings under API/ do not match the build." >&2
        echo "api-surface: if the change is meant, run Scripts/api-surface.sh --record and commit API/ with it." >&2
    fi
    exit 1
fi
[[ $record -eq 1 ]] || echo "api-surface: every listing matches the build"
