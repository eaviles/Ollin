#!/bin/zsh
#
# Scripts/release-smoke.sh: the stranger's build.
#
#   Scripts/release-smoke.sh                 # the newest tag, generated, fetched, built, rendered
#   Scripts/release-smoke.sh 0.8.0           # a particular published tag
#   Scripts/release-smoke.sh --template 3d   # a starting point that pulls more of the framework
#   Scripts/release-smoke.sh --with physics  # and the satellites a project wires in
#   Scripts/release-smoke.sh --keep          # leave the project and the frame behind
#   Scripts/release-smoke.sh --warm-cache    # reuse this machine's package cache
#   Scripts/release-smoke.sh --selftest      # the render laws against their own fixtures
#
# Every other gate here reads the repository: the tests build the tree, the
# figure gate renders out of it, preflight compiles the prose against it. None
# of them is the route somebody else takes. A stranger writes one line into a
# manifest, SwiftPM fetches a tag from GitHub, and the framework has to build
# from that checkout alone and draw a picture. Nothing tested that, so this
# does: it generates the project the generator writes for a stranger
# (`ollin new --remote`), points SwiftPM at a cache of its own so the fetch is
# a real one over the network, builds it, and renders one frame headless.
#
# What it can catch that a green tree cannot: a resource left out of a target
# (the tree finds it beside the source), a product that is not public, a tag
# that was never pushed, a manifest that names a version nobody published, a
# dependency reachable only from this machine, a checkout that builds only
# because something else in the tree built first.
#
# The tag has to exist on the remote, which fixes when this runs. Before a
# release it is a rehearsal against the tag already out there, and it proves
# the route rather than the release. After the tag is pushed it is the proof
# for that release, and it is the last step of the release: cut the tag, push
# it, run this.
#
# The laws, each printed as it passes:
#
#   the tag         exists on origin, because that is where SwiftPM will look
#   the manifest    pins the version under test with .upToNextMinor, the form
#                   the README tells a consumer to use
#   the resolve     answers from the published repository, at a version on
#                   that same minor (a newer patch is the pin working)
#   the build       compiles with the dependency fetched, not pathed
#   the frame       is the canvas the sketch declares, and it has ink on it
#
# The ink law is the one that would quietly go missing, because a framework
# that builds and renders nothing still writes a file. The frame is read back
# through ImageIO and a pixel counts as ink when it differs from the corner by
# more than a level or two, so a white circle on white would fail the way an
# empty canvas does. --selftest runs that reader against a blank fixture and
# an inked one and refuses to continue if the blank one passes.
#
# Costs: a full clone of the repository (the pack is well over a hundred
# megabytes) and a debug build of the framework from cold, so a first run is
# minutes. --warm-cache reuses the machine's own package cache, which skips
# the clone and makes a re-run quick; the honest run is the cold one, and the
# release proof is always cold.

cd "$(dirname "$0")/.." || exit 1

# Every long command here is piped through tail to keep the log readable, and
# without this the pipe would report tail's success as the build's.
setopt pipefail

version=""
template="blank"
extras=""
keep=0
warm=0
selftest=0
configuration="debug"
workdir=""
want_template=0
want_with=0
want_in=0

for arg in "$@"; do
    if [[ $want_template -eq 1 ]]; then template="$arg"; want_template=0; continue; fi
    if [[ $want_with -eq 1 ]]; then extras="$arg"; want_with=0; continue; fi
    if [[ $want_in -eq 1 ]]; then workdir="$arg"; want_in=0; continue; fi
    case "$arg" in
    --template) want_template=1 ;;
    --template=*) template="${arg#--template=}" ;;
    --with) want_with=1 ;;
    --with=*) extras="${arg#--with=}" ;;
    --in) want_in=1 ;;
    --in=*) workdir="${arg#--in=}" ;;
    --keep) keep=1 ;;
    --warm-cache) warm=1 ;;
    --release) configuration="release" ;;
    --selftest) selftest=1 ;;
    --help | -h)
        sed -n '3,55p' "$0" | sed 's|^# \{0,1\}||'
        exit 0
        ;;
    -*)
        print -u2 "release-smoke: unknown option $arg"
        exit 2
        ;;
    *) version="$arg" ;;
    esac
done

typeset -g failures=0

step() { print "\n== $1" }
pass() { print "   ok: $1" }
fail() { print -u2 "   FAILED: $1"; failures=$((failures + 1)) }

# The frame reader, written out beside the work so the script stays one file.
# It prints `<width> <height> <inked> <total>`, where a pixel is inked when it
# differs from the top-left one by more than two levels in any channel.
write_reader() {
    cat > "$1" <<'SWIFT'
import Foundation
import ImageIO
import CoreGraphics

guard CommandLine.arguments.count > 1 else { exit(2) }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("cannot read \(url.path)\n".utf8))
    exit(1)
}
let width = image.width, height = image.height
var bytes = [UInt8](repeating: 0, count: width * height * 4)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(data: &bytes, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: width * 4,
                              space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
let corner = (bytes[0], bytes[1], bytes[2])
var inked = 0
for i in stride(from: 0, to: bytes.count, by: 4) {
    let dr = abs(Int(bytes[i]) - Int(corner.0))
    let dg = abs(Int(bytes[i + 1]) - Int(corner.1))
    let db = abs(Int(bytes[i + 2]) - Int(corner.2))
    if max(dr, max(dg, db)) > 2 { inked += 1 }
}
print("\(width) \(height) \(inked) \(width * height)")
SWIFT
}

# A fixture pair for --selftest: one blank sheet, one with a mark on it.
write_fixtures() {
    cat > "$1" <<'SWIFT'
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

func write(_ path: String, inked: Bool) {
    let side = 64
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    if inked {
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fillEllipse(in: CGRect(x: 20, y: 20, width: 24, height: 24))
    }
    let url = URL(fileURLWithPath: path)
    let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(out, context.makeImage()!, nil)
    CGImageDestinationFinalize(out)
}

write(CommandLine.arguments[1], inked: false)
write(CommandLine.arguments[2], inked: true)
SWIFT
}

# --selftest: the reader against a blank sheet and an inked one. The ink law is
# the one that rots into a check of whether a file exists, so it is proven to
# go red before any run trusts it.
if [[ $selftest -eq 1 ]]; then
    dir=$(mktemp -d "${TMPDIR:-/tmp}/ollin-smoke-selftest.XXXXXX") || exit 1
    write_reader "$dir/read.swift"
    write_fixtures "$dir/write.swift"
    step "the reader against its own fixtures"
    if ! swift "$dir/write.swift" "$dir/blank.png" "$dir/inked.png"; then
        fail "could not write the fixtures"
        rm -rf "$dir"
        exit 1
    fi
    blank=$(swift "$dir/read.swift" "$dir/blank.png")
    inked=$(swift "$dir/read.swift" "$dir/inked.png")
    print "   blank: $blank"
    print "   inked: $inked"
    [[ "${blank[(w)1]}" == "64" && "${blank[(w)2]}" == "64" ]] \
        && pass "the size is read off the file" || fail "the size is wrong"
    [[ "${blank[(w)3]}" == "0" ]] \
        && pass "a blank sheet reads as no ink" || fail "a blank sheet read as ink"
    (( ${inked[(w)3]} > 100 )) \
        && pass "a mark on the sheet reads as ink" || fail "a mark read as no ink"
    rm -rf "$dir"
    if [[ $failures -gt 0 ]]; then
        print -u2 "\nrelease-smoke --selftest: $failures failed."
        exit 1
    fi
    print "\nrelease-smoke --selftest: the render laws hold."
    exit 0
fi

# The version under test: what was asked for, else the newest tag on HEAD.
if [[ -z "$version" ]]; then
    version=$(git describe --tags --abbrev=0 2>/dev/null)
    if [[ -z "$version" ]]; then
        print -u2 "release-smoke: no tag to test; name one (Scripts/release-smoke.sh 0.8.0)."
        exit 2
    fi
fi

print "Ollin release smoke: the stranger's build of $version"
print "  template: $template${extras:+, wiring in $extras}"
cache_note="a cache of its own, so the fetch is a real one"
[[ $warm -eq 1 ]] && cache_note="this machine's own package cache"
print "  build:    $configuration, $cache_note"

step "the tag exists on origin"
if git ls-remote --tags origin "refs/tags/$version" 2>/dev/null | grep -q "refs/tags/$version"; then
    pass "origin has $version"
else
    fail "origin has no tag $version. SwiftPM fetches from GitHub, so the tag has to be pushed first."
    exit 1
fi

step "the generator"
if ! swift build --product OllinNew 2>&1 | tail -3; then
    fail "could not build OllinNew"
    exit 1
fi
bin=$(swift build --show-bin-path 2>/dev/null)
if [[ ! -x "$bin/OllinNew" ]]; then
    fail "no OllinNew binary at $bin"
    exit 1
fi
pass "OllinNew built"

if [[ -z "$workdir" ]]; then
    workdir=$(mktemp -d "${TMPDIR:-/tmp}/ollin-release-smoke-$version.XXXXXX") || exit 1
else
    mkdir -p "$workdir" || exit 1
fi
project="$workdir/SmokeSketch"

cleanup() {
    if [[ $keep -eq 1 ]]; then
        print "\nleft behind: $workdir"
    else
        rm -rf "$workdir"
    fi
}

step "the project a stranger gets"
wiring=()
[[ -n "$extras" ]] && wiring=(--with "$extras")
if ! "$bin/OllinNew" SmokeSketch --kind mac-sketch --template "$template" \
        $wiring --remote --in "$workdir" > "$workdir/new.log" 2>&1; then
    cat "$workdir/new.log"
    fail "ollin new --remote refused"
    cleanup
    exit 1
fi
if [[ ! -f "$project/Package.swift" ]]; then
    cat "$workdir/new.log"
    fail "no manifest at $project/Package.swift"
    cleanup
    exit 1
fi
pass "written to $project"

step "the manifest pins the published framework"
pin=$(grep -n 'package(url:' "$project/Package.swift" | head -1)
if [[ -z "$pin" ]]; then
    fail "the manifest names no remote package"
    cleanup
    exit 1
fi
print "   $pin"
pinned=$(print -r -- "$pin" | sed -n 's/.*upToNextMinor(from: "\([^"]*\)").*/\1/p')
if [[ -z "$pinned" ]]; then
    fail "the pin is not the .upToNextMinor form the README tells a consumer to use"
    cleanup
    exit 1
fi
pass "pinned .upToNextMinor(from: \"$pinned\")"
if [[ "$pinned" != "$version" ]]; then
    # FrameworkSource.latestRelease is bumped in the release commit, so before a
    # tag it names the release being prepared and after it names this one. A
    # rehearsal against an older tag rewrites the entry rather than refusing.
    print "   note: the generator pins $pinned; this run wants $version, so the entry was rewritten."
    sed -i '' "s/upToNextMinor(from: \"$pinned\")/upToNextMinor(from: \"$version\")/" "$project/Package.swift"
fi

# A cache of its own, so the fetch is a real one rather than whatever this
# machine already has. --warm-cache is the re-run, and says so above.
paths=()
if [[ $warm -eq 0 ]]; then
    paths=(--cache-path "$workdir/cache" --scratch-path "$project/.build")
fi

step "SwiftPM fetches it from GitHub"
start=$SECONDS
if ! swift package resolve --package-path "$project" $paths 2>&1 | tail -5; then
    fail "resolve failed"
    cleanup
    exit 1
fi
resolved=$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' "$project/Package.resolved" | head -1)
url=$(sed -n 's/.*"location" *: *"\([^"]*\)".*/\1/p' "$project/Package.resolved" | head -1)
[[ -z "$url" ]] && url=$(sed -n 's/.*"repositoryURL" *: *"\([^"]*\)".*/\1/p' "$project/Package.resolved" | head -1)
print "   resolved $resolved from $url"
if [[ "$url" != *"github.com"* ]]; then
    fail "the dependency did not come from GitHub"
else
    pass "fetched from $url in $((SECONDS - start))s"
fi
if [[ "${resolved%.*}" == "${version%.*}" ]]; then
    pass "resolved $resolved, on the pinned minor"
else
    fail "resolved $resolved, which is not on ${version%.*}"
fi

step "the build"
start=$SECONDS
if ! swift build --package-path "$project" $paths -c "$configuration" 2>&1 | tail -20; then
    fail "the stranger's build does not compile"
    cleanup
    exit 1
fi
pass "built in $((SECONDS - start))s"

step "one frame, headless"
frame="$workdir/frame.png"
start=$SECONDS
if ! swift run --package-path "$project" $paths -c "$configuration" SmokeSketch \
        --export "$frame" 2>&1 | tail -10; then
    fail "the sketch did not run"
    cleanup
    exit 1
fi
if [[ ! -f "$frame" ]]; then
    fail "no frame written to $frame"
    cleanup
    exit 1
fi
pass "rendered in $((SECONDS - start))s"

step "the frame"
write_reader "$workdir/read.swift"
read_out=$(swift "$workdir/read.swift" "$frame")
if [[ -z "$read_out" ]]; then
    fail "the frame could not be read back"
    cleanup
    exit 1
fi
w=${read_out[(w)1]} h=${read_out[(w)2]} inked=${read_out[(w)3]} total=${read_out[(w)4]}
print "   $w x $h, $inked of $total pixels carry ink"
declared=$(sed -n 's/.*canvasSize = *\.\([a-zA-Z0-9]*\).*/\1/p' "$project/Sources/SmokeSketch/Sketch.swift" | head -1)
if [[ -z "$declared" ]]; then
    # The framework's own default, which the blank starting point leaves alone.
    [[ "$w" == "1080" && "$h" == "1080" ]] \
        && pass "1080 square, the canvas a sketch gets by default" \
        || fail "the frame is $w x $h, not the 1080 square a sketch gets by default"
else
    pass "the sketch declares .$declared and the frame is $w x $h"
fi
if (( inked > total / 1000 )); then
    pass "the frame has ink on it"
else
    fail "the frame is blank: $inked of $total pixels differ from the corner"
fi

cleanup

if [[ $failures -gt 0 ]]; then
    print -u2 "\nrelease-smoke: $failures failed for $version."
    exit 1
fi
print "\nrelease-smoke: $version builds and draws for somebody who only has the tag."
