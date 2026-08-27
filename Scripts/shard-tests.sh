#!/bin/zsh
#
# Scripts/shard-tests.sh: run OllinTests as several processes at once.
#
#   Scripts/shard-tests.sh          # four shards
#   Scripts/shard-tests.sh <n>      # n shards
#
# Why: OllinTests draws through `Sketch`, which is main-actor isolated, so
# every render probe queues on one thread and the target uses 2.0 of 8 cores
# (835 s of CPU over 409 s of wall clock). A process has one main thread, so
# the only way to reach the rest of the machine is more processes. Measured
# 2026-08-27: 409 s in one process, 189 s in four.
#
# Why not four `swift test` runs: they work, and they are slower. The shards
# themselves finish in 64 to 182 s, but four SwiftPM invocations serialize on
# the .build lock computing their build plans, and the wall clock comes to
# 426 s, worse than one process. Only the per-shard numbers look like a win,
# which is why this measures the wall clock and prints it.
#
# So each shard invokes the built bundle the way SwiftPM itself does. That
# needs both DYLD paths below: without the framework path it cannot find
# XCTest, and without the library path it cannot find libXCTestSwiftSupport,
# which sits beside the platform's other libraries rather than in the
# framework. Everything is derived through xcrun, since a hardcoded toolchain
# path would break on the next Xcode.
#
# Suites are dealt round-robin across the shards, which splits their number
# evenly and their cost only roughly: a shard can finish in a third the time of
# the slowest one, because what a suite costs is mostly how much it renders and
# nothing here knows that in advance. Balancing by measured time needs times
# that a main-thread-bound run cannot give (every `@MainActor` suite reports
# roughly the whole run), so this deals blind on purpose.
#
# What makes dealing blind safe is that no test writes a fixed path any more
# (`ollinTempPath` in the test support). Before that, two suites sharing a
# literal temp name could land in different processes and clobber each other.
#
# The run counts what it executed against what the bundle lists, and fails if
# they differ. A filter that quietly matches nothing is the failure worth
# catching here: everything else about a sharded run looks identical whether
# it ran 2903 tests or 2900.

cd "$(dirname "$0")/.." || exit 1
emulate -L zsh
# No err_return here: `wait` carries a failing shard's status, and a failure is
# something to collect and report rather than to abort on.

shards=${1:-4}
# DataFeedTests and SpatialVideoTests want the machine to themselves and run in
# test.sh's phase 1, so they are not part of this.
apart='OllinTests.DataFeedTests|OllinTests.SpatialVideoTests'
single() {
    echo "shard-tests: $1; running OllinTests in one process instead"
    exec swift test --filter '^OllinTests\.' --skip "$apart"
}

# Nothing may need building once the shards start: they do not go through
# SwiftPM and would find no bundle.
if ! build=$(swift build --build-tests 2>&1); then
    print -r -- "$build" >&2
    exit 1
fi

platform=$(xcrun --sdk macosx --show-sdk-platform-path 2>/dev/null)
helper="$(dirname "$(xcrun --find swift)")/../libexec/swift/pm/swiftpm-testing-helper"
bundle=".build/debug/OllinTests.xctest/Contents/MacOS/OllinTests"
[[ -n "$platform" && -x "$helper" && -f "$bundle" ]] || single "no direct invocation on this toolchain"

export DYLD_FRAMEWORK_PATH="$platform/Developer/Library/Frameworks"
export DYLD_LIBRARY_PATH="$platform/Developer/usr/lib"

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT

"$helper" --test-bundle-path "$bundle" --list-tests --testing-library swift-testing "$bundle" \
    > "$work/ids.txt" 2>/dev/null || single "the bundle would not list its tests"
expected=$(grep -cvE "^($apart)/" "$work/ids.txt") || true
[[ $expected -gt 0 ]] || single "the bundle listed no tests"

python3 - "$work" "$shards" "$apart" <<'PY'
import sys, re
work, shards, apart = sys.argv[1], int(sys.argv[2]), sys.argv[3]
drop = re.compile('^(' + apart + ')/')
suites = sorted({l.split('/')[0] for l in open(work + '/ids.txt') if l.strip() and not drop.match(l)})
for i in range(shards):
    mine = suites[i::shards]
    pattern = '^(' + '|'.join(s.replace('.', r'\.') for s in mine) + ')/' if mine else '^$a^'
    open(f'{work}/shard{i}.filter', 'w').write(pattern)
    print(f'shard-tests: shard {i} has {len(mine)} suites')
PY

echo "shard-tests: $expected tests over $shards shards"
started=$SECONDS
for i in {0..$((shards - 1))}; do
    "$helper" --test-bundle-path "$bundle" --testing-library swift-testing "$bundle" \
        --filter "$(<$work/shard$i.filter)" > "$work/shard$i.log" 2>&1 &
done
wait
elapsed=$((SECONDS - started))

ran=0
typeset -a failures
for i in {0..$((shards - 1))}; do
    count=$(grep -oE 'Test run with [0-9]+ tests' "$work/shard$i.log" | grep -oE '[0-9]+' | head -1)
    ran=$((ran + ${count:-0}))
    # The per-test lines, not the run summary, which also says "failed after".
    failures+=(${(f)"$(grep '✘ Test .*failed after' "$work/shard$i.log" | grep -v 'Test run with')"})
    printf 'shard-tests: shard %d ran %s tests\n' $i "${count:-none}"
done

echo "shard-tests: $ran tests in ${elapsed}s"

if [[ $ran -ne $expected ]]; then
    echo "shard-tests: ran $ran tests, the bundle lists $expected; the filters do not cover it" >&2
    exit 1
fi
if (( ${#failures} > 0 )); then
    print -l -- $failures >&2
    exit 1
fi
