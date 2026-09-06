#!/bin/zsh
#
# Scripts/build-web-expander.sh: compile the stroke and fill expander to
# WebAssembly, the player part a web page uses to expand strokes and fills
# it carries as points.
#
#   Scripts/build-web-expander.sh            # rewrites Sources/Ollin/Resources/WebExpander.wasm
#   Scripts/build-web-expander.sh --check    # says whether the resource is current
#
# The page's expander is the framework's own expander: Sources/OllinExpander
# (the fringe expander's geometry, the fan, the tessellator's glue, and the
# record layout) plus Scripts/web-expander/Entry.swift (the exported entry
# points) and the vendored libtess2, compiled with Embedded Swift for
# wasm32-unknown-wasip1 through the swift.org toolchain and its WebAssembly
# SDK. The result is committed as a resource beside a manifest that names the
# toolchain and a hash of the sources it was built from; a test compares the
# hash with the sources, so an expander edit without a rebuild fails there
# rather than shipping a page that expands differently from the Mac.
#
# Needs the swift.org toolchain (not Xcode's, which carries no WebAssembly
# SDK) under ~/Library/Developer/Toolchains or /Library/Developer/Toolchains,
# with its `_wasm-embedded` Swift SDK installed (`swift sdk install`). Point
# OLLIN_WASM_TOOLCHAIN at a toolchain to use a particular one.

cd "$(dirname "$0")/.." || exit 1
emulate -L zsh
set -o pipefail

resource=Sources/Ollin/Resources/WebExpander.wasm
manifest=Sources/Ollin/Resources/WebExpander.json
shim=Scripts/web-expander/shim

# The sources the module is built from, in one fixed order, and their hash.
sources=(Sources/OllinExpander/*.swift(N) Scripts/web-expander/Entry.swift
         External/CLibtess2/Include/*.h(N) External/CLibtess2/Source/*.c(N) External/CLibtess2/Source/*.h(N)
         $shim/setjmp.h)
hash=$(cat $sources | shasum -a 256 | cut -d' ' -f1)

if [[ "$1" == "--check" ]]; then
    if [[ ! -f "$manifest" ]]; then
        echo "web-expander: no manifest at $manifest" >&2
        exit 1
    fi
    recorded=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sources"])' "$manifest")
    if [[ "$recorded" == "$hash" ]]; then
        echo "web-expander: $resource is current ($hash)"
        exit 0
    fi
    echo "web-expander: $resource was built from other sources ($recorded, now $hash); rerun Scripts/build-web-expander.sh" >&2
    exit 1
fi

# The toolchain: the one named, or the newest swift.org release installed.
toolchain=${OLLIN_WASM_TOOLCHAIN:-}
if [[ -z "$toolchain" ]]; then
    for dir in ~/Library/Developer/Toolchains /Library/Developer/Toolchains; do
        for candidate in $dir/swift-*-RELEASE.xctoolchain(Non); do
            toolchain=$candidate
            break 2
        done
    done
fi
if [[ -z "$toolchain" || ! -x "$toolchain/usr/bin/swift" ]]; then
    echo "web-expander: no swift.org toolchain found; install one from swift.org (with its WebAssembly SDK) or set OLLIN_WASM_TOOLCHAIN" >&2
    exit 1
fi
swift="$toolchain/usr/bin/swift"
sdk=$("$swift" sdk list 2>/dev/null | grep -- '_wasm-embedded$' | head -1)
if [[ -z "$sdk" ]]; then
    echo "web-expander: the toolchain at $toolchain has no embedded WebAssembly SDK; install the matching one with \`$swift sdk install <url>\`" >&2
    exit 1
fi
version=$("$swift" --version 2>/dev/null | head -1)
echo "web-expander: building with $version and $sdk"

work=$(mktemp -d "${TMPDIR:-/tmp}/ollin-web-expander.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Expander" "$work/CLibtess2/shim"
cp Sources/OllinExpander/*.swift Scripts/web-expander/Entry.swift "$work/Expander/"
cp -R External/CLibtess2/Source External/CLibtess2/Include "$work/CLibtess2/"
cp $shim/setjmp.h "$work/CLibtess2/shim/"
cat > "$work/Package.swift" <<'PKG'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "OllinWebExpander",
    targets: [
        .target(name: "CLibtess2", path: "CLibtess2", exclude: ["shim"], publicHeadersPath: "Include",
                cSettings: [.define("NDEBUG"), .headerSearchPath("shim")]),
        .executableTarget(
            name: "OllinWebExpander", dependencies: ["CLibtess2"], path: "Expander",
            swiftSettings: [.enableExperimentalFeature("Embedded"),
                            .unsafeFlags(["-Osize", "-wmo", "-parse-as-library"])],
            linkerSettings: [.unsafeFlags(["-Xlinker", "--no-entry", "-Xlinker", "--strip-all",
                                           "-Xclang-linker", "-mexec-model=reactor"])]),
    ])
PKG
if ! "$swift" build --package-path "$work" --swift-sdk "$sdk" -c release 2>&1 | grep -vE '^\[[0-9]+/[0-9]+\]|^Building for|^Build complete|^Compiling|^Write '; then
    :
fi
built=$(find "$work/.build" -name OllinWebExpander.wasm -path '*release*' | head -1)
if [[ -z "$built" || ! -s "$built" ]]; then
    echo "web-expander: the build produced no module" >&2
    exit 1
fi
mkdir -p "$(dirname "$resource")"
cp "$built" "$resource"
bytes=$(stat -f %z "$resource")
cat > "$manifest" <<JSON
{
  "toolchain": "$version",
  "sdk": "$sdk",
  "sources": "$hash",
  "bytes": $bytes
}
JSON
echo "web-expander: wrote $resource ($bytes bytes) and $manifest"
