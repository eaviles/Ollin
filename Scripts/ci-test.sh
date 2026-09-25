#!/bin/zsh
#
# Scripts/ci-test.sh: `swift test` under a watchdog that turns a wedge into a
# diagnosis.
#
#   Scripts/ci-test.sh [swift test arguments]
#   Scripts/ci-test.sh --run <command> [arguments]   # any command instead
#
# The test process's output is watched. When nothing has been written for
# OLLIN_QUIET_LIMIT seconds (900 by default), every test process still alive
# is sampled and its threads' stacks are printed here, then the run is killed
# and this exits 124. On a machine nobody can attach to, that is the only way
# to learn what a wedged run was waiting on: a step that merely reaches its
# cap leaves a silence, and the process's last buffered lines die with it.
#
# Fifteen minutes because a healthy run is quiet for up to ten. The pool
# parks behind the main-actor chain and results land in bursts (the workflow
# has the numbers on its test step), while the runs that wedged were silent
# for over thirty. A limit under the longest healthy silence would sample a
# run that was about to finish.
#
# A run that fails is followed by what outlives a crashed test process: the
# system's crash reports written during the run (Scripts/crash-report.py) and
# any case the mutation harness was trying when its process went down.

cd "$(dirname "$0")/.." || exit 1
emulate -L zsh

limit=${OLLIN_QUIET_LIMIT:-900}
log=$(mktemp -t ollin-ci-test) || exit 1
started=$(mktemp -t ollin-ci-started) || exit 1
trap 'rm -f "$log" "$started"' EXIT

# `--run` wraps a command of the caller's (Scripts/test.sh ci, which runs
# OllinTests as shards and the other targets beside them); the sample below
# still finds every test process, since the shards invoke the same helper
# `swift test` does.
if [[ "$1" == "--run" ]]; then
    shift
    "$@" > >(tee -a "$log") 2>&1 &
else
    swift test "$@" > >(tee -a "$log") 2>&1 &
fi
pid=$!

quiet=0
last=-1
while kill -0 $pid 2>/dev/null; do
    sleep 15
    size=$(stat -f %z "$log" 2>/dev/null || echo 0)
    if [[ $size == $last ]]; then
        (( quiet += 15 ))
    else
        quiet=0
        last=$size
    fi
    if (( quiet >= limit )); then
        print -r -- "ci-test: ====== NO OUTPUT FOR $quiet s: sampling the test processes ======"
        for p in $(pgrep -f 'swiftpm-testing-helper|\.xctest/'); do
            print -r -- "ci-test: ------ sample of pid $p ($(ps -o comm= -p $p)) ------"
            sample $p 2 -mayDie -file "$log.sample-$p" > /dev/null 2>&1
            head -3000 "$log.sample-$p"
            rm -f "$log.sample-$p"
        done
        print -r -- "ci-test: killing the wedged run"
        pkill -f 'swiftpm-testing-helper' 2>/dev/null
        pkill -P $pid 2>/dev/null
        kill $pid 2>/dev/null
        wait $pid 2>/dev/null
        exit 124
    fi
done

wait $pid
result=$?

# A test process that dies on a signal takes its buffered output with it, so
# the log above names no test. Two witnesses outlive it: the report the system
# writes for the crashed process (its faulting thread's frames), and the
# mutation harness's log, which holds the case each run was trying when the
# process went down (a run that completes removes its own).
if (( result != 0 )); then
    Scripts/crash-report.py "$started"
    mutations="${TMPDIR:-$(getconf DARWIN_USER_TEMP_DIR)}/ollin-mutation"
    for entry in "$mutations"/*.log(N); do
        print -r -- "ci-test: a mutation run did not finish: $(head -c 1200 "$entry")"
    done
fi
exit $result
