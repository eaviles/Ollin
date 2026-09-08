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
products=$(swift package dump-package 2>/dev/null | jq -r '
    .products[] | select(.type | has("library")) | .name' \
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

if [[ $build -eq 1 ]]; then
    for module in ${(f)products}; do
        swift build --target "$module" >/dev/null 2>&1 || {
            echo "api-surface: swift build --target $module failed" >&2
            exit 1
        }
    done
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

mkdir -p API .build/api
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
