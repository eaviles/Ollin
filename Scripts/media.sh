#!/bin/zsh
#
# Scripts/media.sh: render the example media and put it where the site reads it.
#
#   Scripts/media.sh Patterns/Kaleidoscope Motion/FlowField   # named examples
#   Scripts/media.sh --category Patterns                      # a whole folder
#   Scripts/media.sh --all                                    # every example
#   Scripts/media.sh --no-upload Patterns/Dendrite            # render only
#
# Each example that earns one gets four files: a clip at the canvas size for
# its own page, a small clip for a grid to play under the pointer, and a still
# at both sizes. They live in Cloudflare R2 behind media.ollin.art rather than
# in git, and `Examples/media.json` is the one place their address is written
# down, so moving the host is one edit there.
#
# A sketch that declares `loopDuration` records exactly one lap. Everything
# else records ten seconds, which is what a clip needs to answer "what does
# this sketch do" before the reader moves on; an example whose arc wants
# longer carries `seconds` in its manifest row, and that row is kept across
# runs. The still is the frame at eight seconds unless the row names another.
#
# Every example gets a picture. Two things change what it gets.
#
# A sketch that needs something plugged in (a camera, the phone, a controller,
# a MIDI or serial or lighting or laser rig, a tablet, a second machine) is
# **held back rather than drawn**, read off its own imports. Its media wants a
# person at the desk with the thing in hand, so it waits for one, and the
# manifest says so under `passedOver` with what it is waiting for.
#
# Everything else renders. Whether it keeps a clip is measured rather than
# guessed: the master is sampled once a second and the largest change between
# samples must reach `MOTION_FLOOR`. A static print scores about 0.2 there and
# a sketch that merely grows slowly scores about 3, so the floor separates
# them with room to spare. Below it the sketch keeps its still and loses only
# the clip, since a print that holds still is still worth showing, and so is a
# sketch that sits waiting for a hand on the mouse.
#
# An example whose folder has not changed since its last run is left alone,
# media and verdict both, so a sweep over everything costs almost nothing the
# second time. The digest covers the whole folder rather than `Sketch.swift`
# alone, since a sketch reading a font, a mesh or a photograph beside it draws
# a different picture without a line of Swift changing. `--force` renders
# anyway.
#
# A sketch that makes music puts it in the file already, so the page clip
# keeps the sound and the small one that plays under a pointer does not.
#
# Every render passes `--photo`, which is what makes a sketch that reads a
# camera take the bundled picture instead. Without it this machine's own
# camera answers and the sketch is filmed reading a dark room.
#
# A sketch with a detector in it also needs wall-clock time before its first
# useful frame, since the model is prepared on another thread and the drawing
# has nothing to draw until it lands. `--settle` redraws the captured frame
# until it does, and the clip skips a couple of seconds ahead for the same
# reason, or the picture is a photograph with nothing found in it.
#
# The master is ProRes, so each deliverable is encoded once from clean pixels
# and never from an already compressed file; it is deleted as soon as the two
# clips are out. The clips are H.264 High 4.0 at yuv420p tagged bt709, which
# is the combination an iPhone decodes and every browser plays.
#
# Credentials come from ~/.config/ollin/r2.env, which is outside the repository
# and never committed.

set -e
cd ${0:A:h}/..
ROOT=$PWD
OUT=$(mktemp -d /tmp/ollin-media.XXXXXX)
trap 'rm -rf $OUT' EXIT

MANIFEST=$ROOT/Examples/media.json
BIN=$ROOT/Examples/.build/out/Products/Release
SECONDS_DEFAULT=10
FPS=60
STILL_FRAME_DEFAULT=480      # eight seconds at sixty
MOTION_FLOOR=1.0
RENDER_LIMIT=300             # seconds before a sketch is given up on and drawn as one frame

# A sketch importing one of these needs something plugged in, so its media
# waits for a person at the desk with the thing in hand.
# Vision and the camera are not here: a sketch that reads a camera falls back
# to a bundled photograph or the bundled film, so it draws the real technique
# on a real picture with nothing plugged in.
DEVICE_MODULES=(OllinPhone OllinRecord3D OllinScreen OllinMIDI
                OllinOSC OllinSerial OllinBluetooth OllinDMX OllinLaser OllinSyphon
                OllinRoom OllinRemote OllinLink OllinHaptics OllinController)
# The ones that need a device without importing a library for it.
DEVICE_SKETCHES=(Input/Pen Audio/Listening Audio/PlayAlong)

upload=1
force=0
missing=0
list=()

examples_under() {
  (cd $ROOT/Examples && find ${1:-.} -name Sketch.swift | sed 's|^\./||;s|/Sketch.swift$||' | sort)
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --all) list=($(examples_under)) ;;
    --category) shift; list+=($(examples_under $1)) ;;
    --no-upload) upload=0 ;;
    --force) force=1 ;;
    --missing) missing=1 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) list+=($1) ;;
  esac
  shift
done
[[ ${#list} -gt 0 ]] || { echo "usage: Scripts/media.sh [--all|--category C] [--no-upload] [--force] [--missing] <Group/Name> ..." >&2; exit 2; }

if (( upload )); then
  [[ -f ~/.config/ollin/r2.env ]] || { echo "no ~/.config/ollin/r2.env; pass --no-upload to render only" >&2; exit 2; }
  set -a; source ~/.config/ollin/r2.env; set +a
  export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare \
         RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
         RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
         RCLONE_CONFIG_R2_ENDPOINT="$R2_ENDPOINT" \
         RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true
fi

cap() { echo "scale=w=${1}:h=${1}:force_original_aspect_ratio=decrease:force_divisible_by=2"; }

# What the example is made of, so an unchanged one can be left alone.
digest_of() {
  find $ROOT/Examples/$1 -type f -not -name '.*' | sort | xargs shasum -a 256 | shasum -a 256 | cut -c1-16
}

# What this example is waiting for before anybody can take its picture.
held_back() {
  local sketch=$ROOT/Examples/$1/Sketch.swift
  for module in $DEVICE_MODULES; do
    grep -q "^import $module\$" $sketch && { echo "needs a device at the desk: imports $module"; return; }
  done
  for named in $DEVICE_SKETCHES; do
    [[ $1 == $named ]] && { echo "needs a device at the desk"; return; }
  done
  echo ""
}

# The largest change between samples a second apart, which is what tells a
# sketch that grows slowly from one that does not move at all.
motion_of() {
  ffmpeg -v error -i "$1" \
    -vf "fps=1,scale=128:-2,format=gray,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" \
    -f null /dev/null 2>/dev/null \
  | awk -F'=' '/YAVG/{ if ($2 > mx) mx = $2 } END { printf "%.3f", mx + 0 }'
}

# Render with a limit, since a sketch that blocks would otherwise hold the run.
render() {
  "$@" > /dev/null 2>&1 &
  local job=$!
  ( sleep $RENDER_LIMIT; kill -9 $job 2>/dev/null ) > /dev/null 2>&1 &
  local watcher=$!
  wait $job 2>/dev/null
  local code=$?
  kill -9 $watcher 2>/dev/null || true
  return $code
}

made=0 passed=0
for example in $list; do
  folder=$ROOT/Examples/$example
  [[ -f $folder/Sketch.swift ]] || { echo "$example: no Sketch.swift" >&2; continue; }
  key=$(echo $example | tr '[:upper:]/' '[:lower:]-')
  digest=$(digest_of $example)

  read -r want_seconds want_frame had_digest standing <<< "$(python3 $ROOT/Scripts/media-manifest.py read $MANIFEST "$example")"
  if (( missing )) && [[ $standing == media ]]; then
    (( passed += 1 ))
    continue
  fi
  if (( ! force )) && (( ! missing )) && [[ $digest == $had_digest ]]; then
    echo "--- $example: unchanged since its last run ($standing)"
    (( passed += 1 ))
    continue
  fi

  waiting=$(held_back $example)
  if [[ -n $waiting ]]; then
    echo "--- $example: $waiting"
    python3 $ROOT/Scripts/media-manifest.py skip $MANIFEST "$example" "$waiting" "$digest"
    (( passed += 1 ))
    continue
  fi

  echo "=== $example"
  target="Example-${example//\//-}"
  swift build -c release --package-path $ROOT/Examples --product $target > /dev/null 2>&1 \
    || { echo "  build failed" >&2; continue; }

  [[ $want_seconds == "-" ]] && want_seconds=$SECONDS_DEFAULT
  [[ $want_frame == "-" ]] && want_frame=$STILL_FRAME_DEFAULT

  # A detector loads on another thread, so the drawing has nothing to show
  # until it has: settle the still and skip the clip past the wait.
  settle=()
  skip=()
  if grep -q '^import OllinVision$' $folder/Sketch.swift; then
    settle=(--settle 120)
    skip=(--skip 3)
  fi

  master=$OUT/$key.mov
  if grep -q 'loopDuration' $folder/Sketch.swift; then
    render $BIN/$target --export-loop $master --codec proRes422 --fps $FPS --photo $skip || true
    length=lap
  else
    render $BIN/$target --export-video $master --seconds $want_seconds --fps $FPS --codec proRes422 --photo $skip || true
    length=${want_seconds}s
  fi
  # A render that ran out of time is killed part way and leaves a file that
  # is not a film, so the master is read before it is trusted: an unreadable
  # one falls back to a single frame rather than stopping the run.
  size=""
  [[ -f $master ]] && size=$(ffprobe -v error -select_streams v:0 \
      -show_entries stream=width,height -of csv=p=0 $master 2>/dev/null) || true
  if [[ -z $size ]]; then
    echo "  no film came back, so a picture instead"
    rm -f $master
    render $BIN/$target --export $OUT/$key.png --frame $want_frame --photo $settle || true
    if [[ ! -f $OUT/$key.png ]]; then
      echo "  could not be drawn at all" >&2
      python3 $ROOT/Scripts/media-manifest.py skip $MANIFEST "$example" "could not be drawn on this machine" "$digest"
      (( passed += 1 ))
      continue
    fi
    size=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $OUT/$key.png)
    ffmpeg -y -loglevel error -i $OUT/$key.png -vf $(cap 1080) -q:v 2 $OUT/$key-still.jpg
    ffmpeg -y -loglevel error -i $OUT/$key.png -vf $(cap 640) -q:v 3 $OUT/$key-still-640.jpg
    for suffix in still.jpg still-640.jpg; do
      (( upload )) && rclone copyto $OUT/$key-$suffix "r2:$R2_BUCKET/examples/$example/$suffix" \
        --header-upload "Cache-Control: public, max-age=31536000, immutable" 2>/dev/null
    done
    python3 $ROOT/Scripts/media-manifest.py still $MANIFEST "$example" "$size" "$want_frame" \
      "0" $OUT/$key-still.jpg $OUT/$key-still-640.jpg "$digest" "too slow to film on this machine"
    rm -f $OUT/$key-*
    (( made += 1 ))
    continue
  fi

  # A sketch that makes music has something to show even when its picture
  # holds still, so sound counts alongside movement.
  sound=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 $master 2>/dev/null)
  motion=$(motion_of $master)
  still_only=0
  [[ $(echo "$motion < $MOTION_FLOOR" | bc -l) == 1 && -z $sound ]] && still_only=1

  render $BIN/$target --export $OUT/$key.png --frame $want_frame --photo $settle || true
  if (( still_only )); then
    rm -f $master
    [[ -f $OUT/$key.png ]] || { echo "  nothing to show" >&2; continue; }
    ffmpeg -y -loglevel error -i $OUT/$key.png -vf $(cap 1080) -q:v 2 $OUT/$key-still.jpg
    ffmpeg -y -loglevel error -i $OUT/$key.png -vf $(cap 640) -q:v 3 $OUT/$key-still-640.jpg
    for suffix in still.jpg still-640.jpg; do
      (( upload )) && rclone copyto $OUT/$key-$suffix "r2:$R2_BUCKET/examples/$example/$suffix" \
        --header-upload "Cache-Control: public, max-age=31536000, immutable" 2>/dev/null
    done
    echo "  holds still ($motion), so a picture and no clip"
    python3 $ROOT/Scripts/media-manifest.py still $MANIFEST "$example" "$size" "$want_frame" \
      "$motion" $OUT/$key-still.jpg $OUT/$key-still-640.jpg "$digest" "holds still"
    rm -f $OUT/$key-*
    (( made += 1 ))
    continue
  fi
  if [[ -n $sound ]]; then
    audio=(-c:a aac -b:a 128k)
  else
    audio=(-an)
  fi
  ffmpeg -y -loglevel error -i $master -vf $(cap 1080) -c:v libx264 -profile:v high -level 4.0 \
    -crf 20 -preset slow -pix_fmt yuv420p -color_primaries bt709 -color_trc bt709 \
    -colorspace bt709 -maxrate 6M -bufsize 12M -g 120 $audio -movflags +faststart $OUT/$key-loop.mp4
  ffmpeg -y -loglevel error -i $master -vf $(cap 640) -r 30 -c:v libx264 -profile:v high -level 4.0 \
    -crf 24 -preset slow -pix_fmt yuv420p -color_primaries bt709 -color_trc bt709 \
    -colorspace bt709 -g 60 -an -movflags +faststart $OUT/$key-loop-640.mp4
  ffmpeg -y -loglevel error -i $OUT/$key.png -vf $(cap 1080) -q:v 2 $OUT/$key-still.jpg
  ffmpeg -y -loglevel error -i $OUT/$key.png -vf $(cap 640) -q:v 3 $OUT/$key-still-640.jpg
  rm -f $master

  weight=0
  for suffix in loop.mp4 loop-640.mp4 still.jpg still-640.jpg; do
    file=$OUT/$key-$suffix
    weight=$(( weight + $(stat -f%z $file) ))
    if (( upload )); then
      rclone copyto $file "r2:$R2_BUCKET/examples/$example/$suffix" \
        --header-upload "Cache-Control: public, max-age=31536000, immutable" 2>/dev/null
    fi
  done
  printf "  %s, %sx%s, motion %s, %.2f MB\n" $length ${size%,*} ${size#*,} $motion "$(( weight / 1048576.0 ))"

  python3 $ROOT/Scripts/media-manifest.py write $MANIFEST "$example" \
    "$size" "$want_seconds" "$want_frame" "$length" "$motion" "${sound:-}" $OUT/$key-loop.mp4 \
    $OUT/$key-loop-640.mp4 $OUT/$key-still.jpg $OUT/$key-still-640.jpg \
    "$digest"
  rm -f $OUT/$key-*
  (( made += 1 ))
done

echo "media: $made rendered, $passed passed over or unchanged"
