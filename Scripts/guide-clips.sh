#!/bin/zsh
#
# Scripts/guide-clips.sh: record the sketch each Guide chapter builds, so the
# website can play it where the markdown shows a still.
#
#   Scripts/guide-clips.sh                       # every chapter
#   Scripts/guide-clips.sh 01 05                 # named chapters, by number
#   Scripts/guide-clips.sh --no-upload 01        # render only, keep the file
#
# The committed still stays exactly where it is. It is what a clone, GitHub and
# `ollin docs` show, and it becomes the video's poster on the site, so a reader
# who blocks video or has asked for less motion sees the picture the markdown
# promised. A chapter with no row recorded yet renders as it always did, which
# is why the site half of this can ship before the clips do.
#
# The clip comes from the chapter's own hook figure, found by reading the first
# image in the chapter and mapping it back to Guide/Figures. A figure that
# declares `loopDuration` records exactly one lap and loops seamlessly;
# everything else records ten seconds.
#
# Upload needs R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY, the same pair
# Scripts/media.sh uses. Without them the run renders and says so.

set -e
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)
OUT=${TMPDIR:-/tmp}/ollin-guide-clips
MANIFEST=$ROOT/Examples/media.json
FPS=30
SECONDS_DEFAULT=10

upload=1
wanted=()
for arg in "$@"; do
  case $arg in
    --no-upload) upload=0 ;;
    *) wanted+=("$arg") ;;
  esac
done

if (( upload )) && [[ -z $R2_ACCESS_KEY_ID || -z $R2_SECRET_ACCESS_KEY ]]; then
  echo "guide-clips: no R2 credentials in the environment, so rendering only."
  echo "             set R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY to publish."
  upload=0
fi

mkdir -p $OUT
echo "guide-clips: building the host once"
swift build -c release --product OllinLive >/dev/null

for chapter in Guide/[0-9]*.md; do
  stem=$(basename $chapter .md)
  number=${stem%%-*}
  if (( ${#wanted} )) && [[ ! " ${wanted[@]} " =~ " ${number} " ]]; then continue; fi

  # The hook is the chapter's first image, and its figure is the sketch.
  hook=$(grep -m1 -oE '<img src="Images/[^"]+"' $chapter | sed 's/.*src="//;s/"//') || true
  [[ -z $hook ]] && { echo "  $stem: no hook image"; continue; }
  name=$(basename $hook); name=${name%.*}
  figure=Guide/Figures/$stem/$name.swift
  [[ -f $figure ]] || { echo "  $stem: no figure at $figure"; continue; }

  master=$OUT/$stem.mov
  clip=$OUT/$stem.mp4
  rm -f $master $clip
  if grep -q 'loopDuration' $figure; then
    echo "  $stem: one lap of $name"
    swift run -c release OllinLive $figure --export-loop $master --codec proRes422 --fps $FPS >/dev/null 2>&1 || true
  else
    echo "  $stem: ${SECONDS_DEFAULT}s of $name"
    swift run -c release OllinLive $figure --export-video $master --seconds $SECONDS_DEFAULT --fps $FPS --codec proRes422 >/dev/null 2>&1 || true
  fi

  size=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $master 2>/dev/null) || true
  if [[ -z $size ]]; then echo "    no film came back, leaving the still alone"; rm -f $master; continue; fi
  w=${size%,*}; h=${size#*,}

  ffmpeg -y -loglevel error -i $master -vf "scale='min(1080,iw)':-2" \
         -c:v libx264 -pix_fmt yuv420p -crf 23 -movflags +faststart $clip
  rm -f $master
  echo "    $(du -h $clip | cut -f1) at ${w}x${h}"

  if (( upload )); then
    export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare \
           RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
           RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
           RCLONE_CONFIG_R2_ENDPOINT="$R2_ENDPOINT"
    rclone copyto $clip R2:${R2_BUCKET:-ollin-media}/guide/$stem.mp4
  fi

  python3 - "$MANIFEST" "$stem" "guide/$stem.mp4" "$hook" "$w" "$h" <<'PY'
import json, sys
manifest, stem, clip, still, w, h = sys.argv[1:7]
d = json.load(open(manifest))
d.setdefault("chapters", {})[stem] = {"clip": clip, "still": still,
                                      "width": int(w), "height": int(h)}
json.dump(d, open(manifest, "w"), indent=2, sort_keys=True)
PY
done

echo "guide-clips: done. The site plays a chapter's hook wherever a row exists;"
echo "             everywhere else the committed still is shown as before."
