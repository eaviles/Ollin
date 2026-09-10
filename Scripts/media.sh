#!/bin/zsh
#
# Scripts/media.sh: render the example media and put it where the site reads it.
#
#   Scripts/media.sh Patterns/Kaleidoscope Motion/FlowField   # named examples
#   Scripts/media.sh --all                                    # every example
#   Scripts/media.sh --no-upload Patterns/Dendrite            # render only
#
# Each example gets four files: a clip at the canvas size for its own page, a
# small clip for a grid to play under the pointer, and a still at both sizes.
# They live in Cloudflare R2 behind media.ollin.art rather than in git, and
# `Examples/media.json` is the one place their address is written down, so
# moving the host is one edit there.
#
# A sketch that declares `loopDuration` records exactly one lap. Everything
# else records ten seconds, which is what a clip needs to answer "what does
# this sketch do" before the reader moves on; an example whose arc wants
# longer carries `seconds` in its manifest row, and that row is kept across
# runs. The still is the frame at eight seconds unless the row names another.
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
upload=1
list=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --all) list=($(cd $ROOT/Examples && find . -name Sketch.swift | sed 's|^\./||;s|/Sketch.swift$||' | sort)) ;;
    --no-upload) upload=0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) list+=($1) ;;
  esac
  shift
done
[[ ${#list} -gt 0 ]] || { echo "usage: Scripts/media.sh [--all] [--no-upload] <Group/Name> ..." >&2; exit 2; }

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

# What the manifest already says about one example, as `seconds frame`.
row() { python3 $ROOT/Scripts/media-manifest.py read $MANIFEST "$1"; }

for example in $list; do
  folder=$ROOT/Examples/$example
  [[ -f $folder/Sketch.swift ]] || { echo "$example: no Sketch.swift" >&2; continue; }
  target="Example-${example//\//-}"
  key=$(echo $example | tr '[:upper:]/' '[:lower:]-')
  echo "=== $example"

  read -r want_seconds want_frame <<< "$(row $example)"
  [[ $want_seconds == "-" ]] && want_seconds=$SECONDS_DEFAULT
  [[ $want_frame == "-" ]] && want_frame=$STILL_FRAME_DEFAULT

  swift build -c release --package-path $ROOT/Examples --product $target > /dev/null 2>&1 \
    || { echo "  build failed" >&2; continue; }

  master=$OUT/$key.mov
  if grep -q 'loopDuration' $folder/Sketch.swift; then
    $BIN/$target --export-loop $master --codec proRes422 --fps $FPS > /dev/null 2>&1
    length=lap
  else
    $BIN/$target --export-video $master --seconds $want_seconds --fps $FPS --codec proRes422 > /dev/null 2>&1
    length=${want_seconds}s
  fi
  [[ -f $master ]] || { echo "  no master rendered" >&2; continue; }
  $BIN/$target --export $OUT/$key.png --frame $want_frame > /dev/null 2>&1

  ffmpeg -y -loglevel error -i $master -vf $(cap 1080) -c:v libx264 -profile:v high -level 4.0 \
    -crf 20 -preset slow -pix_fmt yuv420p -color_primaries bt709 -color_trc bt709 \
    -colorspace bt709 -maxrate 6M -bufsize 12M -g 120 -an -movflags +faststart $OUT/$key-loop.mp4
  ffmpeg -y -loglevel error -i $master -vf $(cap 640) -r 30 -c:v libx264 -profile:v high -level 4.0 \
    -crf 24 -preset slow -pix_fmt yuv420p -color_primaries bt709 -color_trc bt709 \
    -colorspace bt709 -g 60 -an -movflags +faststart $OUT/$key-loop-640.mp4
  ffmpeg -y -loglevel error -i $OUT/$key.png -vf $(cap 1080) -q:v 2 $OUT/$key-still.jpg
  ffmpeg -y -loglevel error -i $OUT/$key.png -vf $(cap 640) -q:v 3 $OUT/$key-still-640.jpg
  rm -f $master

  size=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $OUT/$key-loop.mp4)
  echo "  $length, ${size%,*}x${size#*,}"
  for suffix in loop.mp4 loop-640.mp4 still.jpg still-640.jpg; do
    file=$OUT/$key-$suffix
    printf "  %-14s %7.2f MB\n" $suffix "$(( $(stat -f%z $file) / 1048576.0 ))"
    if (( upload )); then
      rclone copyto $file "r2:$R2_BUCKET/examples/$example/$suffix" \
        --header-upload "Cache-Control: public, max-age=31536000, immutable" 2>/dev/null
    fi
  done

  python3 $ROOT/Scripts/media-manifest.py write $MANIFEST "$example" \
    "$size" "$want_seconds" "$want_frame" "$length" $OUT/$key-loop.mp4 \
    $OUT/$key-loop-640.mp4 $OUT/$key-still.jpg $OUT/$key-still-640.jpg \
    "$(find $folder -type f -not -name '.*' | sort | xargs shasum -a 256 | shasum -a 256 | cut -c1-16)"
done

echo "manifest: $MANIFEST"
