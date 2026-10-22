#!/bin/zsh
#
# Scripts/check-ci-swift.sh: build the package with the Swift the CI runner
# compiles with, so a break that only the runner sees is found before a push.
#
#   Scripts/check-ci-swift.sh    # every target but the tests, in its own build folder
#
# The desk and the runner run different compilers (6.4 here, the macos-26
# image's 6.3 there), and the two disagree about which expressions are too
# hard to type-check. An expression the newer solver settles at once fails on
# the runner with "unable to type-check this expression in reasonable time",
# often reported against a different file: Wavetable.basic (2026-09-02), a sum
# of vector products in Noise.swift (2026-09-16), two map closures in
# GestureMark.swift (2026-10-21). The newer compiler's long-expression warning
# flagged none of them, so the reliable check is the older compiler itself.
#
# Needs a swift.org toolchain of the runner's minor under
# ~/Library/Developer/Toolchains or /Library/Developer/Toolchains (or the one
# OLLIN_CI_TOOLCHAIN names), and a macOS 26 SDK, because a compiler cannot
# read an SDK built by a newer Swift: this desk's macOS 27 SDK stops 6.3 at
# Accelerate. The SDK is the one OLLIN_CI_SDK names, else a MacOSX26 SDK in an
# installed Xcode, else the one the Swift Playground app carries. Missing
# either, it says so and passes, since the runner still checks.
#
# When the runner moves to a new Swift, move `runner_swift` with it.

cd "$(dirname "$0")/.." || exit 1
emulate -L zsh
setopt null_glob

runner_swift=6.3

toolchain=${OLLIN_CI_TOOLCHAIN:-}
if [[ -z "$toolchain" ]]; then
    for dir in ~/Library/Developer/Toolchains /Library/Developer/Toolchains; do
        for candidate in $dir/swift-${runner_swift}*-RELEASE.xctoolchain(On); do
            toolchain=$candidate
            break 2
        done
    done
fi
if [[ -z "$toolchain" || ! -x "$toolchain/usr/bin/swift" ]]; then
    echo "ci-swift: no Swift $runner_swift toolchain from swift.org installed, so the runner's compiler is not checked here (set OLLIN_CI_TOOLCHAIN to use one)"
    exit 0
fi

sdk=${OLLIN_CI_SDK:-}
if [[ -z "$sdk" ]]; then
    for candidate in /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26*.sdk(On) \
                     "/Applications/Swift Playground.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"; do
        [[ -d "$candidate" ]] || continue
        version=$(/usr/libexec/PlistBuddy -c 'Print :Version' "$candidate/SDKSettings.plist" 2>/dev/null)
        if [[ "$version" == 26.* ]]; then
            sdk=$candidate
            break
        fi
    done
fi
if [[ -z "$sdk" ]]; then
    echo "ci-swift: no macOS 26 SDK found (Swift $runner_swift cannot read a newer one), so the runner's compiler is not checked here; an Xcode 26 install or the Swift Playground app carries one, or set OLLIN_CI_SDK to a MacOSX26 SDK"
    exit 0
fi

swift="$toolchain/usr/bin/swift"
echo "ci-swift: $("$swift" --version 2>&1 | head -1), against $sdk"
SDKROOT="$sdk" "$swift" build --scratch-path .build/ci-swift --sdk "$sdk" -j 4
