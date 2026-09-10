#!/bin/zsh
#
# Scripts/example-heroes.sh: rebuild a page's opening picture.
#
#   Scripts/example-heroes.sh guide     # the sketch each chapter builds
#   Scripts/example-heroes.sh readme    # examples from across the framework
#   Scripts/example-heroes.sh both --no-upload
#
# A page opens on a grid of sketches playing at once. The markdown carries the
# still, since that is what GitHub and a plain clone can show, and the site
# swaps in the clip; both files are written here and both are named in
# `Examples/media.json` under `heroes`, which is also where what each is made
# of is written down, so a hero is rebuilt rather than remembered.
#
# The guide's cells are the sketch each chapter of the Guide builds. Nothing
# picks them by eye: every chapter figure marks its own `Guide payoff` in
# source, so the list is the book's and there are exactly as many as there are
# chapters. The README's cells are named in the manifest.
#
# Each cell is filmed with a running start, or a sketch that accumulates opens
# on an empty canvas and the grid begins full of holes. Three of the guide's
# want an age of their own, which the manifest names too: a swarm that
# converges wants catching early, a particle drift wants far longer, and a
# grid simulation is isolated rings too early and a solid field too late.

set -e
cd ${0:A:h}/..
ROOT=$PWD
MANIFEST=$ROOT/Examples/media.json
OUT=$(mktemp -d /tmp/ollin-hero.XXXXXX)
trap 'rm -rf $OUT' EXIT

upload=1
which=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-upload) upload=0 ;;
    both) which=(guide readme) ;;
    guide|readme) which+=($1) ;;
    *) echo "usage: Scripts/example-heroes.sh [guide|readme|both] [--no-upload]" >&2; exit 2 ;;
  esac
  shift
done
[[ ${#which} -gt 0 ]] || { echo "usage: Scripts/example-heroes.sh [guide|readme|both] [--no-upload]" >&2; exit 2; }

if (( upload )); then
  set -a; source ~/.config/ollin/r2.env; set +a
  export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare \
         RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
         RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
         RCLONE_CONFIG_R2_ENDPOINT="$R2_ENDPOINT" \
         RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true
fi

# The sketch each chapter builds, filmed from its own figure file.
film_guide() {
  local n=0
  for figure in $(grep -rl 'Guide payoff\|payoff sketch\|Chapter 2 payoff' $ROOT/Guide/Figures/*/*.swift \
                  | sed "s|$ROOT/Guide/Figures/||;s|\.swift$||" | sort); do
    n=$((n+1))
    local lead=$(python3 -c "
import json; h = json.load(open('$MANIFEST'))['heroes']['guide']
print(h.get('leads', {}).get('$figure', h.get('lead', 6)))")
    swift run OllinLive $ROOT/Guide/Figures/$figure.swift \
      --export-video $OUT/$(printf '%02d' $n).mov --seconds 6 --fps 30 \
      --codec proRes422 --photo --skip $lead > /dev/null 2>&1
    echo "  $figure (from $lead s)"
  done
}

# The examples the manifest names, taken from the clips already published.
film_readme() {
  local n=0
  python3 - "$MANIFEST" <<'PY' > $OUT/list.txt
import json, sys
d = json.load(open(sys.argv[1]))
for name in d['heroes']['readme']['sketches']:
    row = d['examples'].get(name)
    if row and row.get('loopSmall'):
        print(f"{d['base']}/{row['loopSmall']}")
    else:
        print(f"MISSING\t{name}", file=sys.stderr)
PY
  while read -r url; do
    n=$((n+1))
    curl -sSfL -o $OUT/$(printf '%02d' $n).mp4 "$url"
  done < $OUT/list.txt
  echo "  $n clips"
}

for hero in $which; do
  echo "=== $hero"
  rm -f $OUT/*.mov(N) $OUT/*.mp4(N) $OUT/*.jpg(N)
  if [[ $hero == guide ]]; then film_guide; else film_readme; fi
  cell=$(python3 -c "import json;print(json.load(open('$MANIFEST'))['heroes']['$hero'].get('cell', 200))")
  across=$(python3 -c "import json;print(json.load(open('$MANIFEST'))['heroes']['$hero'].get('across', 8))")
  python3 $ROOT/Scripts/media-heroes.py tile $OUT $cell $across $OUT/$hero.mp4
  ffmpeg -y -loglevel error -ss 2 -i $OUT/$hero.mp4 -frames:v 1 -q:v 2 $OUT/$hero.jpg
  # Uploaded under the name the manifest already uses.
  for suffix in mp4 jpg; do
    cp $OUT/$hero.$suffix $OUT/$hero-hero.$suffix
    (( upload )) && rclone copyto $OUT/$hero-hero.$suffix "r2:$R2_BUCKET/heroes/$hero-hero.$suffix" \
      --header-upload "Cache-Control: public, max-age=31536000, immutable" 2>/dev/null
  done
  python3 $ROOT/Scripts/media-heroes.py record $MANIFEST $hero $OUT/$hero-hero.jpg $OUT/$hero-hero.mp4
  printf "  %s: %.2f MB\n" $hero "$(( $(stat -f%z $OUT/$hero.mp4) / 1048576.0 ))"
done

echo "heroes: written into $MANIFEST; the markdown reads the address from there"
