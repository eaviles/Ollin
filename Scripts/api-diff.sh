#!/bin/zsh
#
# Scripts/api-diff.sh: the public surface read as a version.
#
#   Scripts/api-diff.sh                        # the tree's API/ against the last tag
#   Scripts/api-diff.sh --from 0.7.0 --to 0.8.0  # between two refs (--to defaults to the tree)
#   Scripts/api-diff.sh --changelog            # the CHANGELOG skeleton instead of the report
#   Scripts/api-diff.sh --summary              # one line per module and the bump (what preflight prints)
#   Scripts/api-diff.sh --strict               # the shim rule as a gate, whatever the version
#   Scripts/api-diff.sh --warn                 # the shim rule as a count, whatever the version
#   Scripts/api-diff.sh --module M             # one module only
#   Scripts/api-diff.sh --selftest             # the reader against its own fixtures
#
# Reads the listings under API/ (one line per public declaration, written by
# Scripts/api-surface.sh) at two points and says what changed between them:
# every line added, removed, renamed, changed in signature, or deprecated,
# with a removal paired to the addition it became when the same container
# holds one of the same name or the same shape, and a member a protocol the
# type conforms to still supplies (one of Ollin's, or `count` and `first` from
# the standard library's Collection) read as moved. From that it names the bump
# the next release needs. At major zero any public change is a minor, which is
# what the README promises a consumer pinning .upToNextMinor. From 1.0 on a
# removal is a major, an addition or a deprecation is a minor, and a release
# with no public change is a patch.
#
# The shim rule rides on the same diff. From 1.0 on a public spelling never
# goes away without its deprecated twin (the old declaration kept, marked
# @available(*, deprecated, renamed:), forwarding to the new one), so a line
# that is gone at the end and was not deprecated at the start breaks it. Before
# 1.0 the rule is a rehearsal: the run counts what would fail and exits clean.
# From 1.0 on, or under --strict, it fails. Either way, a shim in the working
# tree that sits outside its module's Deprecations.swift, or carries no
# renamed:/message:, fails the run: that is a house rule, not a version.
#
# --changelog prints the entry a person then groups and explains: an Added
# bullet per new type and per container with new members, a Changed bullet
# per rename, signature change and removal in the changelog's own "`old` is
# `new`" form, and a Deprecated bullet per shim with its replacement. The
# release steps read it before writing the Unreleased section; a pairing the
# reader is not sure of says so on its line.
#
# The from ref defaults to the nearest tag on HEAD. Its version comes from the
# tag's name, or from the nearest tag below a ref that is not one. Preflight
# runs the summary whenever API/ or the framework changed, in under a second.

cd "$(dirname "$0")/.." || exit 1
emulate -L zsh

from=""
to=""
typeset -a pass
while [[ $# -gt 0 ]]; do
    case "$1" in
    --from) shift; from="$1" ;;
    --to) shift; to="$1" ;;
    --module) shift; pass+=(--module "$1") ;;
    --strict | --warn | --changelog | --summary) pass+=("$1") ;;
    --selftest) exec python3 Scripts/api-diff.py --selftest ;;
    --help | -h)
        sed -n '3,44p' "$0" | sed -E 's|^# ?||'
        exit 0
        ;;
    *) echo "api-diff: unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done

if [[ -z "$from" ]]; then
    from=$(git describe --tags --abbrev=0 2>/dev/null)
    [[ -n "$from" ]] || { echo "api-diff: no tag to diff against; pass --from" >&2; exit 2; }
fi

# The version a ref stands for: its own name when it is a tag spelled as one,
# else the nearest tag below it.
version_of() {
    if [[ "$1" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
        echo "$1"
    else
        git describe --tags --abbrev=0 "$1" 2>/dev/null || echo "0.0.0"
    fi
}

# The listings at a ref, one file per module, copied out where the reader
# can walk them.
extract() {
    local ref="$1" dir="$2"
    rm -rf "$dir"
    mkdir -p "$dir"
    local found=0
    for file in $(git ls-tree --name-only "$ref" -- API/ 2>/dev/null); do
        [[ "$file" == *.txt ]] || continue
        git show "$ref:$file" >"$dir/${file:t}" || return 1
        found=1
    done
    [[ $found -eq 1 ]] || { echo "api-diff: $ref has no listings under API/" >&2; return 1; }
}

old_dir=".build/api-diff/$from"
extract "$from" "$old_dir" || exit 2
if [[ -n "$to" ]]; then
    new_dir=".build/api-diff/$to"
    extract "$to" "$new_dir" || exit 2
    to_label="$to"
    sources=()
else
    new_dir="API"
    to_label="tree"
    sources=(--sources Sources)
fi

python3 Scripts/api-diff.py --old "$old_dir" --new "$new_dir" \
    --from-label "$from" --to-label "$to_label" --from-version "$(version_of "$from")" \
    "${sources[@]}" "${pass[@]}"
