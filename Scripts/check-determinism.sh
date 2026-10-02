#!/bin/zsh
#
# Scripts/check-determinism.sh: does the same seed draw the same pixels?
#
#   Scripts/check-determinism.sh                          # every example that runs alone
#   Scripts/check-determinism.sh --category Patterns      # one folder
#   Scripts/check-determinism.sh Patterns/Kaleidoscope    # named examples
#   Scripts/check-determinism.sh --file Sketch.swift      # a loose sketch file
#   Scripts/check-determinism.sh --selftest               # the check can go red
#
# Each example is exported twice at one frame under one `--seed`, in two
# separate processes, and the two pictures are compared pixel for pixel. Two
# processes, not two renders in one: a `Dictionary` or `Set` walks its keys in
# an order seeded per process, and so does anything keyed by an address, so a
# second render in the same process would share exactly what can differ.
#
# This is the ground under record and replay, variations, `--export-grid`,
# the recipe every export carries, and the snapshot suite: all of them assume
# a seed and a frame name one picture. What breaks that is a clock read
# (`Date()` rather than `time`), a random draw that is not the sketch's own
# (`Double.random(in:)` without a generator), the order of a hashed
# collection, or GPU work whose result depends on which thread got there
# first.
#
# The frame is the one the example's still on the site is taken at (the
# manifest's `frame`, eight seconds unless the row names another), so the
# picture a reader sees is the one proven to come back. `--frame N` overrides
# it for every example. Examples that need something plugged in are held back
# by the same rule as the media (`example-devices.zsh`); a sketch that reads
# a camera takes the bundled photograph (`--photo`), as it does for its media.
#
# A sketch that draws the world as it is at the moment it runs (a live feed,
# today's weather) cannot come back, and is held back rather than counted as
# a failure: two runs are two moments. A sketch that reads a detector is
# checked like any other, since an export analyzes every frame its sources
# offer on the export's own clock, models loaded first. The one detector that
# does not answer the same frames the same way twice is held back too.
#
# A pass over every example is about an hour on the M2, one GPU job at a
# time, so this is a milestone check rather than a preflight gate. `--keep
# DIR` keeps both pictures of every example that differs, and `--log FILE`
# appends one tab-separated line per example.
#
# Exit status: 0 when every example drew the same picture twice, 1 when any
# differed or drew nothing, 2 on a usage error.

set -e
cd ${0:A:h}/..
ROOT=$PWD
OUT=$(mktemp -d /tmp/ollin-determinism.XXXXXX)
trap 'rm -rf $OUT' EXIT

source $ROOT/Scripts/example-devices.zsh

MANIFEST=$ROOT/Media/media.json
HOST=$ROOT/.build/release/OllinLive
SEED=7
FRAME_DEFAULT=480            # eight seconds at sixty, the media's still
RENDER_LIMIT=300             # seconds before a render is given up on

# The ones that draw the world as it is while they run, on purpose.
LIVE_WORLD=(Data/Edits Data/Outside)
# The loopbacks whose far end answers over UDP, so a frame draws whichever
# packet had landed by then, a different one each run.
OVER_UDP=(Integration/DMXLoopback Integration/OSCLoopback)
# The ones whose detector does not answer the same frames the same way twice:
# Vision's trajectory request fits its arcs a few millionths differently from
# run to run on identical frames and timestamps, and over a long run that
# changes which sightings join an arc.
NOT_EXACT=(Vision/TrajectoryTracking)

frame_override=""
keep=""
log=""
selftest=0
list=()
files=()

examples_under() {
  (cd $ROOT/Examples && find ${1:-.} -name Sketch.swift -not -path '*/.build/*' \
     | sed 's|^\./||;s|/Sketch.swift$||' | sort)
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --all) list=($(examples_under)) ;;
    --category) shift; list+=($(examples_under $1)) ;;
    --file) shift; files+=(${1:A}) ;;
    --frame) shift; frame_override=$1 ;;
    --seed) shift; SEED=$1 ;;
    --keep) shift; keep=${1:A}; mkdir -p $keep ;;
    --log) shift; log=${1:A} ;;
    --selftest) selftest=1 ;;
    -h|--help) sed -n '3,40p' $0 | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) list+=($1) ;;
  esac
  shift
done
(( selftest )) || [[ ${#list} -gt 0 || ${#files} -gt 0 ]] || list=($(examples_under))

# The host every sketch is compiled into and run by, built once up front so
# the pass measures the tree as it is.
swift build -c release --product OllinLive > $OUT/build.log 2>&1 \
  || { cat $OUT/build.log >&2; echo "the host did not build" >&2; exit 1; }

# Render with a limit, since a sketch that blocks would otherwise hold the run.
# The watcher's own sleep goes with it, so a long pass leaves no strays.
render() {
  "$@" > $OUT/render.log 2>&1 &
  local job=$!
  ( sleep $RENDER_LIMIT & wait $!; kill -9 $job 2>/dev/null ) > /dev/null 2>&1 &
  local watcher=$!
  wait $job 2>/dev/null
  local code=$?
  pkill -P $watcher 2>/dev/null || true
  kill -9 $watcher 2>/dev/null || true
  return $code
}

# How far apart two pictures are: the pixels that differ in any channel, the
# largest difference in levels, and the box they fall in.
compare() {
  python3 - "$1" "$2" <<'EOF'
import subprocess, sys
import numpy as np

def pixels(path):
    size = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                           "-show_entries", "stream=width,height", "-of", "csv=p=0", path],
                          capture_output=True, text=True, check=True).stdout.strip()
    w, h = (int(v) for v in size.split(","))
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "rawvideo",
                          "-pix_fmt", "rgba64le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<u2").reshape(h, w, 4).astype(np.int32) >> 8

a, b = pixels(sys.argv[1]), pixels(sys.argv[2])
if a.shape != b.shape:
    print(f"sizes differ: {a.shape[1]}x{a.shape[0]} against {b.shape[1]}x{b.shape[0]}")
    sys.exit(0)
delta = np.abs(a - b).max(axis=2)
moved = delta > 0
n = int(moved.sum())
if n == 0:
    print("same pixels")
    sys.exit(0)
ys, xs = np.nonzero(moved)
share = 100.0 * n / moved.size
print(f"{n} pixels ({share:.2f}%), up to {int(delta.max())} levels, "
      f"in x {xs.min()}-{xs.max()} y {ys.min()}-{ys.max()}")
EOF
}

same=0 differed=0 failed=0 held=0
differing=()
failing=()

record() {
  [[ -n $log ]] && print -r -- "$1	$2	$3" >> $log
  return 0
}

# Draw one sketch twice and say whether the pictures match.
check() {
  local name=$1 sketch=$2 frame=$3
  shift 3
  local extra=("$@")
  rm -f $OUT/first.png $OUT/second.png
  local started=$SECONDS
  render $HOST $sketch --export $OUT/first.png --frame $frame --seed $SEED --photo $extra || true
  if [[ ! -f $OUT/first.png ]]; then
    local why=$(grep -m1 -iE 'error|fatal|could not|failed' $OUT/render.log | cut -c1-160)
    echo "  no picture: ${why:-the render ended without one}"
    record $name "no picture" "${why:-}"
    failing+=($name); (( failed += 1 ))
    return
  fi
  render $HOST $sketch --export $OUT/second.png --frame $frame --seed $SEED --photo $extra || true
  if [[ ! -f $OUT/second.png ]]; then
    echo "  no picture the second time"
    record $name "no picture" "second run"
    failing+=($name); (( failed += 1 ))
    return
  fi
  local took=$(( SECONDS - started ))
  if cmp -s $OUT/first.png $OUT/second.png; then
    echo "  same (frame $frame, ${took}s)"
    record $name same "frame $frame"
    (( same += 1 ))
    return
  fi
  local verdict=$(compare $OUT/first.png $OUT/second.png)
  if [[ $verdict == "same pixels" ]]; then
    echo "  same pixels, different bytes (frame $frame, ${took}s)"
    record $name same "frame $frame, bytes differ"
    (( same += 1 ))
    return
  fi
  echo "  DIFFERS at frame $frame: $verdict"
  record $name differs "frame $frame: $verdict"
  differing+=($name); (( differed += 1 ))
  if [[ -n $keep ]]; then
    local stem=$keep/${name//\//-}
    cp $OUT/first.png $stem-first.png
    cp $OUT/second.png $stem-second.png
  fi
}

# The frame an example's still is taken at.
frame_of() {
  [[ -n $frame_override ]] && { echo $frame_override; return; }
  python3 - "$MANIFEST" "$1" "$FRAME_DEFAULT" <<'EOF'
import json, sys
rows = json.load(open(sys.argv[1])).get("examples", {})
print(rows.get(sys.argv[2], {}).get("frame", sys.argv[3]))
EOF
}

if (( selftest )); then
  # Three sketches the check must tell apart: one that reads the wall clock
  # and one that walks a Set must differ between two processes, and the same
  # drawing from the seeded generator must not.
  mkdir -p $OUT/selftest
  cat > $OUT/selftest/Clock.swift <<'EOF'
import Foundation
import Ollin

final class Clock: Sketch {
    override func draw() {
        background(.white)
        fill(.black)
        let t = Date().timeIntervalSinceReferenceDate
        drawCircle(width / 2 + (t.truncatingRemainder(dividingBy: 1) - 0.5) * 400, height / 2, 80)
    }
}
EOF
  cat > $OUT/selftest/HashOrder.swift <<'EOF'
import Ollin

final class HashOrder: Sketch {
    override func draw() {
        background(.white)
        fill(.black)
        let names: Set<String> = ["fig", "pear", "mango", "banana", "apricot", "blueberry", "clementine", "pomegranate"]
        for (i, name) in names.enumerated() {
            drawCircle(120 + Double(i) * 120, height / 2, Double(name.count) * 8)
        }
    }
}
EOF
  cat > $OUT/selftest/Seeded.swift <<'EOF'
import Ollin

final class Seeded: Sketch {
    override func draw() {
        background(.white)
        fill(.black)
        for _ in 0 ..< 40 {
            drawCircle(random(width), random(height), random(4, 40) + noise(time) * 10)
        }
    }
}
EOF
  for name in Clock HashOrder Seeded; do
    echo "=== selftest/$name"
    check selftest/$name $OUT/selftest/$name.swift 30
  done
  wanted=(selftest/Clock selftest/HashOrder)
  if [[ ${differing[*]} == ${wanted[*]} && $same == 1 && $failed == 0 ]]; then
    echo "selftest: the clock and the hash order go red, the seeded sketch stays green"
    exit 0
  fi
  echo "selftest: FAILED (differed: ${differing[*]:-none}; same: $same; no picture: ${failing[*]:-none})" >&2
  exit 1
fi

for sketch in $files; do
  echo "=== ${sketch:t}"
  check ${sketch:t} $sketch ${frame_override:-$FRAME_DEFAULT}
done

for example in $list; do
  sketch=$ROOT/Examples/$example/Sketch.swift
  [[ -f $sketch ]] || { echo "$example: no Sketch.swift" >&2; continue; }
  waiting=$(held_back $example)
  (( ${LIVE_WORLD[(Ie)$example]} )) && waiting="draws the world as it is while it runs"
  (( ${OVER_UDP[(Ie)$example]} )) && waiting="draws the packet that had landed by then"
  (( ${NOT_EXACT[(Ie)$example]} )) && waiting="its detector fits a few millionths differently each run"
  if [[ -n $waiting ]]; then
    echo "--- $example: $waiting"
    record $example held "$waiting"
    (( held += 1 ))
    continue
  fi
  echo "=== $example"
  check $example $sketch $(frame_of $example)
done

echo "determinism: $same the same, $differed differed, $failed drew nothing, $held held back"
(( differed )) && echo "  differed: ${differing[*]}"
(( failed )) && echo "  drew nothing: ${failing[*]}"
(( differed == 0 && failed == 0 ))
