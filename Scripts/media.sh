#!/bin/zsh
#
# Scripts/media.sh: render the example media and put it where the site reads it.
#
#   Scripts/media.sh Patterns/Kaleidoscope Motion/FlowField   # named examples
#   Scripts/media.sh --category Patterns                      # a whole folder
#   Scripts/media.sh --all                                    # every example
#   Scripts/media.sh --no-upload Patterns/Dendrite            # render only
#   Scripts/media.sh --held                                   # what is held, and why
#   Scripts/media.sh --selftest                               # a hold must hold
#
# Each example that earns one gets four files: a clip at the canvas size for
# its own page, a small clip for a grid to play under the pointer, and a still
# at both sizes. They live in Cloudflare R2 behind media.ollin.art rather than
# in git, and `Media/media.json` is the one place their address is written
# down, so moving the host is one edit there.
#
# A sketch that declares `loopDuration` records exactly one lap. Everything
# else records ten seconds, which is what a clip needs to answer "what does
# this sketch do" before the reader moves on; an example whose arc wants
# longer carries `seconds` in its manifest row, and that row is kept across
# runs. The still is the frame at eight seconds unless the row names another.
#
# No clip runs past thirty seconds. A row that asks for more is filmed for
# thirty, and a lap longer than that shows its first thirty: the clip then
# jumps once each time the page repeats it, which is the price of a piece
# whose lap cannot be shortened without spoiling it. A sketch that can take a
# thirty-second lap should have one, so that its clip is a whole loop. The
# reason is weight: a clip streams at up to 6 Mbit/s, so a 72-second lap of
# moving line work was 53 MB on one page.
#
# Every example gets a picture. Three things change what it gets.
#
# An example named in `Media/held.txt` is **held: left exactly as it stands**.
# The sketch would render, but its picture is not cleared for the site. So
# nothing is rendered, its row in the manifest is not touched, and nothing is
# uploaded, on every kind of run, `--force` and a run that names it included;
# the run prints the sentence the list gives. The list is read and checked
# before anything is rendered, and a list that cannot be trusted (missing, a
# line with no reason, a name that is no example's folder) stops the run,
# since the other reading would lift a hold in silence. `--held` prints the
# list and makes the same checks; `--selftest` runs this script over a planted
# repository and fails unless a held example comes through each kind of run
# untouched, and unless the same run with nothing held would have reached it.
#
# A sketch that needs something plugged in (a camera, the phone, a controller,
# a MIDI or serial or lighting or laser rig, a tablet, a second machine) is
# **held back rather than drawn**, read off its own imports. Its media wants a
# person at the desk with the thing in hand, so it waits for one, and the
# manifest says so under `passedOver` with what it is waiting for. An example
# that imports a device library and plays the far end itself (a loopback on
# this Mac, a stand-in tracker, a dancer of its own) is staged instead:
# `RUNS_ALONE` in `example-devices.zsh` names what stands in, it renders like
# any other, and its row carries that sentence as `staged`.
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
# Every render also passes one `--seed`. The clip and the still are two
# renders, and a sketch that rolls its variation would otherwise deal a new
# piece for each, so the page's poster showed one piece and its clip another.
# A sketch that pins its own seed keeps it, since `seed(_:)` in `setup()`
# comes after the flag.
#
# The master is ProRes, so each deliverable is encoded once from clean pixels
# and never from an already compressed file; it is deleted as soon as the two
# clips are out. The clips are H.264 High 4.0 at yuv420p tagged bt709, which
# is the combination an iPhone decodes and every browser plays. Both are
# capped, the page clip at 6 Mbit/s and the small one at 2, since a field of
# noise does not compress and a grid plays a dozen small ones at once.
#
# Two kinds of sketch are treated apart. A canvas left partly clear by a
# translucent background has its still laid over black, as the clip shows it.
# And a sketch that films in HDR keeps its still and no clip, since the page's
# standard-range clip would play it dim.
#
# Credentials come from ~/.config/ollin/r2.env, which is outside the repository
# and never committed.

set -e
cd ${0:A:h}/..
ROOT=$PWD
OUT=$(mktemp -d /tmp/ollin-media.XXXXXX)
trap 'rm -rf $OUT' EXIT

MANIFEST=$ROOT/Media/media.json
BIN=$ROOT/Examples/.build/out/Products/Release
SECONDS_DEFAULT=10
CLIP_LIMIT=30                # seconds: no clip on the site runs longer
FPS=60
STILL_FRAME_DEFAULT=480      # eight seconds at sixty
SEED=1                       # the one variation every render of an example draws
MOTION_FLOOR=1.0
RENDER_LIMIT=${RENDER_LIMIT:-300}   # seconds before a sketch is given up on and drawn as one frame; a long lap on a busy machine is run with a larger figure

# Which examples need something plugged in (`held_back`), shared with the
# other scripts that run every example alone.
source $ROOT/Scripts/example-devices.zsh

upload=1
force=0
missing=0
selftest=0
only_held=0
list=()

examples_under() {
  (cd $ROOT/Examples && find ${1:-.} -name .build -prune -o -name Sketch.swift -print \
     | sed 's|^\./||;s|/Sketch.swift$||' | sort)
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --all) list=($(examples_under)) ;;
    --category) shift; list+=($(examples_under $1)) ;;
    --no-upload) upload=0 ;;
    --force) force=1 ;;
    --missing) missing=1 ;;
    --held) only_held=1 ;;
    --selftest) selftest=1 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) list+=($1) ;;
  esac
  shift
done

# --selftest: a hold must hold. This script is copied into a planted
# repository of its own and run there, so what is proven is this file as it
# stands and no flag or path exists for the test alone. The repository has
# two held examples (one whose row is out of date, so any run would render it
# again; one with no row at all, which is what `--missing` goes looking for)
# and one that is not held. Stand-ins take the place of the three things a
# run reaches outside itself: `swift build` does nothing, an example's binary
# draws a few frames of a test pattern, and `rclone` copies into a folder
# that plays the bucket. Each writes down that it was called. Every kind of
# run is then made twice: with the list in place, where the held pair's row,
# hosted file, and call log must come through untouched; and with nothing
# held, where the same run must reach them, or the first proved nothing.
if (( selftest )); then
  for tool in ffmpeg ffprobe python3; do
    whence -p $tool > /dev/null || { echo "media selftest: no $tool here, so nothing was checked" >&2; exit 77; }
  done
  W=${OUT:A}/world
  bin=$W/Examples/.build/out/Products/Release
  mkdir -p $W/Scripts $W/Media $W/stubs $W/home/.config/ollin $bin
  cp $ROOT/Scripts/media.sh $ROOT/Scripts/media-manifest.py $ROOT/Scripts/example-devices.zsh $W/Scripts/
  for name in Held HeldNew Free; do
    mkdir -p $W/Examples/Planted/$name
    echo "// planted for the self-test: $name" > $W/Examples/Planted/$name/Sketch.swift
  done
  cat > $W/stubs/swift <<EOF
#!/bin/zsh
echo "swift \$*" >> $W/calls.log
EOF
  cat > $W/stubs/rclone <<EOF
#!/bin/zsh
echo "rclone \$*" >> $W/calls.log
[[ \$1 == copyto ]] || exit 0
to=$W/bucket/\${3#r2:*/}
mkdir -p \${to:h} && cp \$2 \$to
EOF
  # The one that is not held moves, so it is filmed down the whole path; the
  # held pair would hold still, which is the quickest way to be rendered.
  cat > $W/stubs/example <<EOF
#!/bin/zsh
echo "render \${0:t} \$*" >> $W/calls.log
picture=color=c=gray:size=64x64:rate=10
[[ \${0:t} == *Free ]] && picture=testsrc2=size=64x64:rate=10
while [[ \$# -gt 0 ]]; do
  case \$1 in
    --export-video|--export-loop) shift; ffmpeg -v error -y -f lavfi -i \$picture -t 3 -c:v prores_ks -profile:v 0 \$1 ;;
    --export) shift; ffmpeg -v error -y -f lavfi -i \$picture -frames:v 1 \$1 ;;
  esac
  shift
done
EOF
  chmod +x $W/stubs/*
  for name in Held HeldNew Free; do cp $W/stubs/example $bin/Example-Planted-$name; done
  print -r -- "R2_BUCKET=selftest R2_ACCESS_KEY_ID=none R2_SECRET_ACCESS_KEY=none R2_ENDPOINT=none" \
    | tr ' ' '\n' > $W/home/.config/ollin/r2.env
  cat > $W/planted.json <<'EOF'
{
  "base": "https://media.ollin.art",
  "examples": {
    "Planted/Held": {
      "width": 64,
      "height": 64,
      "length": "still",
      "stillBecause": "holds still",
      "frame": 480,
      "motion": 0.0,
      "source": "0000000000000000",
      "rendered": "2026-01-01",
      "bytes": {
        "still": 26,
        "stillSmall": 26
      },
      "still": "examples/Planted/Held/still.jpg?v=planted0",
      "stillSmall": "examples/Planted/Held/still-640.jpg?v=planted0"
    }
  },
  "passedOver": {}
}
EOF
  why="its picture is not cleared for the site"
  both="# what the self-test holds
Planted/Held  $why
Planted/HeldNew  $why
"

  plant() {      # the repository as it stands before a run, under this list
    rm -rf $W/bucket
    mkdir -p $W/bucket/examples/Planted/Held
    print -n "the picture the site shows" > $W/bucket/examples/Planted/Held/still.jpg
    cp $W/planted.json $W/Media/media.json
    print -rn -- "$1" > $W/Media/held.txt
    : > $W/calls.log
  }
  go() {         # one run of the copy, with the stand-ins ahead of the real tools
    code=0
    HOME=$W/home PATH=$W/stubs:$PATH /bin/zsh $W/Scripts/media.sh "$@" > $W/said.txt 2>&1 || code=$?
  }
  row() {        # an example's row as the manifest has it, or `absent`
    python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
r = d['examples'].get(sys.argv[2], d['passedOver'].get(sys.argv[2]))
print('absent' if r is None else json.dumps(r, sort_keys=True))" $W/Media/media.json $1
  }
  said() { grep -qF -- "$1" $W/said.txt }
  failed=0 kept=0 reached=0 stopped=0
  fail() {
    echo "media selftest: $current: $1"
    sed 's/^/    | /' $W/said.txt
    (( failed += 1 ))
  }

  plant "$both"
  held_row=$(row Planted/Held)
  held_file=$(shasum < $W/bucket/examples/Planted/Held/still.jpg)

  holds() {      # holds <what kind of run> <its arguments>: the held pair comes through untouched
    current=$1; shift
    (( kept += 1 ))
    go "$@"
    (( code == 0 )) || { fail "the run stopped with $code"; return; }
    [[ $(row Planted/Held) == $held_row && $(row Planted/HeldNew) == absent ]] \
      || fail "a held example's row was written"
    [[ $(shasum < $W/bucket/examples/Planted/Held/still.jpg) == $held_file && ! -e $W/bucket/examples/Planted/HeldNew ]] \
      || fail "a held example's hosted files changed"
    if grep -qE 'Planted[-/]Held' $W/calls.log; then fail "a held example was built, rendered, or uploaded"; fi
    said "Planted/Held: held: $why" || fail "the run did not print the sentence"
  }
  free_rendered() {   # the one that is not held went down the whole path, as it always has
    local got=$(row Planted/Free)
    [[ $got == *'"loop": "examples/Planted/Free/loop.mp4?v='* && $got == *'"seed": 1'* ]] \
      || fail "the example that is not held has no film in its row"
    if [[ $1 == hosted ]]; then
      for file in loop.mp4 loop-640.mp4 still.jpg still-640.jpg; do
        [[ -s $W/bucket/examples/Planted/Free/$file ]] || fail "the example that is not held is missing $file where the site reads it"
      done
    fi
  }
  reaches() {    # reaches <what kind of run> <an example> <its arguments>: with nothing held, the run renders it
    current="$1, with nothing held"; local name=$2; shift 2
    (( reached += 1 ))
    plant ""
    local before=$(row $name)
    go "$@"
    grep -q "^render Example-${name//\//-} " $W/calls.log && [[ $(row $name) != $before ]] \
      || fail "the run never reached $name, so the hold is not what kept it out"
  }
  refuses() {    # refuses <what is wrong with the list> <what the run must say>: nothing runs
    current=$1
    (( stopped += 1 ))
    go --all
    (( code == 2 )) || fail "the run did not stop (it ended with $code)"
    said "$2" || fail "the run did not say what was wrong"
    [[ ! -s $W/calls.log ]] || fail "something was built, rendered, or uploaded first"
    cmp -s $W/planted.json $W/Media/media.json || fail "the manifest was written"
  }

  # The five kinds of run, and the two flags that go with any of them.
  plant "$both"; holds "named" Planted/Held Planted/HeldNew
  cmp -s $W/planted.json $W/Media/media.json || fail "the manifest is not the file it was, byte for byte"
  said "0 rendered, 0 passed over or unchanged, 2 held" || fail "the last line does not count what was held"
  plant "$both"; holds "a category" --category Planted;                             free_rendered hosted
  plant "$both"; holds "everything" --all;                                          free_rendered hosted
  plant "$both"; holds "named and forced" --force Planted/Held Planted/HeldNew Planted/Free; free_rendered hosted
  plant "$both"; holds "everything, forced" --force --all;                          free_rendered hosted
  plant "$both"; holds "what is missing" --missing --all;                           free_rendered hosted
  plant "$both"; holds "everything, with no upload" --no-upload --all;              free_rendered
  [[ ! -e $W/bucket/examples/Planted/Free ]] || fail "a run told not to upload did"
  plant "$both"; holds "named with stray slashes" ./Planted//Held Planted/HeldNew/
  if [[ -e $W/examples ]]; then      # a file system that ignores case
    plant "$both"; holds "named in another case" planted/held PLANTED/HELDNEW
    plant "$both"; holds "a category in another case" --category planted;           free_rendered hosted
  fi
  plant "${both%$'\n'}"; holds "a list whose last line has no line end" --all

  reaches "named" Planted/Held Planted/Held Planted/HeldNew
  reaches "a category" Planted/Held --category Planted
  reaches "everything" Planted/Held --all
  reaches "named and forced" Planted/Held --force Planted/Held Planted/HeldNew
  reaches "what is missing" Planted/HeldNew --missing --all
  reaches "everything, with no upload" Planted/Held --no-upload --all

  plant "$both"; rm $W/Media/held.txt
  refuses "the list is missing" "Media/held.txt is missing"
  plant "Planted/Held"$'\n'
  refuses "a line gives no reason" "holds Planted/Held without the sentence"
  plant "Planted/Gone  $why"$'\n'
  refuses "a line names no example" "holds Planted/Gone, which is no example's folder"
  plant "planted/held  $why"$'\n'
  refuses "a line misspells its folder" "holds planted/held, which is no example's folder"

  if (( failed )); then
    echo "media selftest: $failed of the checks failed"
    exit 1
  fi
  echo "media selftest: $kept runs left a held example untouched, $reached reached it once nothing was held, and $stopped lists that cannot be trusted stopped the run"
  exit 0
fi

# Every example under the name its folder spells, found once. A name from the
# command line is matched to it whatever its case and its slashes, so
# `vision/stylemirror/` is `Vision/StyleMirror` and nothing else. On a file
# system that ignores case the folder answers to both, and a hold, a manifest
# row, and a hosted file are each kept under one spelling.
typeset -A spelled
for name in $(examples_under); do spelled[${(L)name}]=$name; done

# The examples whose media on the site is not to be replaced, each with the
# sentence that says why. Read whole and checked before anything is rendered:
# a list that cannot be trusted stops the run, since passing it by would lift
# a hold without anybody having decided to.
HELD=$ROOT/Media/held.txt
typeset -A HELD_FOR
[[ -f $HELD ]] || { echo "media: Media/held.txt is missing, and that is where a held example is written down (a list with nothing on it is still a file)" >&2; exit 2; }
while read -r name why || [[ -n $name ]]; do
  if [[ -z $name || $name == \#* ]]; then continue; fi
  [[ -n $why ]] || { echo "media: Media/held.txt holds $name without the sentence that says why" >&2; exit 2; }
  [[ ${spelled[${(L)name}]} == $name ]] \
    || { echo "media: Media/held.txt holds $name, which is no example's folder as the folder is spelled (a renamed example takes its line with it)" >&2; exit 2; }
  HELD_FOR[$name]=$why
done < $HELD

if (( only_held )); then
  for name in ${(ok)HELD_FOR}; do echo "$name: held: ${HELD_FOR[$name]}"; done
  echo "media: ${#HELD_FOR} held"
  exit 0
fi

[[ ${#list} -gt 0 ]] || { echo "usage: Scripts/media.sh [--all|--category C] [--no-upload] [--force] [--missing] <Group/Name> ... | --held | --selftest" >&2; exit 2; }

named=($list)
list=()
for name in $named; do
  parts=(${(s:/:)name})
  parts=(${parts:#.})
  key=${(L)${(j:/:)parts}}
  if (( ${+spelled[$key]} )); then
    list+=(${spelled[$key]})
  else
    echo "$name: no Sketch.swift" >&2
  fi
done

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

# The largest change between samples a second apart, which is what tells a
# sketch that grows slowly from one that does not move at all.
motion_of() {
  ffmpeg -v error -i "$1" \
    -vf "fps=1,scale=128:-2,format=gray,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" \
    -f null /dev/null 2>/dev/null \
  | awk -F'=' '/YAVG/{ if ($2 > mx) mx = $2 } END { printf "%.3f", mx + 0 }'
}

# A canvas that a translucent background leaves partly clear keeps that alpha
# in its PNG, and a JPEG would drop it and show the colors unweighted, paler
# than the clip, which shows the canvas over black. So a picture with any
# alpha below full is laid over black first, as the clip is, and an opaque one
# passes through untouched.
over_black() {
  local low=$(ffmpeg -v error -i "$1" \
    -vf "format=rgba,alphaextract,signalstats,metadata=print:key=lavfi.signalstats.YMIN:file=-" \
    -f null /dev/null 2>/dev/null | awk -F'=' '/YMIN/{ print int($2); exit }')
  if [[ -n $low ]] && (( low < 255 )); then echo "format=rgba,premultiply=inplace=1,format=rgb24,"; fi
}

# The still at both sizes, from the example's rendered picture.
make_stills() {
  local flat=$(over_black $OUT/$key.png)
  ffmpeg -y -loglevel error -i $OUT/$key.png -vf "${flat}$(cap 1080)" -q:v 2 $OUT/$key-still.jpg
  ffmpeg -y -loglevel error -i $OUT/$key.png -vf "${flat}$(cap 640)" -q:v 3 $OUT/$key-still-640.jpg
}

# An example that keeps a still and no clip: both sizes up, and the row
# written with its motion and the reason (`publish_still <motion> <reason>`).
publish_still() {
  make_stills
  for suffix in still.jpg still-640.jpg; do
    if (( upload )); then
      rclone copyto $OUT/$key-$suffix "r2:$R2_BUCKET/examples/$example/$suffix" \
        --header-upload "Cache-Control: public, max-age=31536000, immutable" 2>/dev/null
    fi
  done
  python3 $ROOT/Scripts/media-manifest.py still $MANIFEST "$example" "$size" "$want_frame" \
    "$1" $OUT/$key-still.jpg $OUT/$key-still-640.jpg "$digest" "$2"
  rm -f $OUT/$key-*
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

made=0 passed=0 held=0
for example in $list; do
  # A held example is left exactly as it stands, whatever kind of run this
  # is. It is asked first, before the folder is read or its row looked up, so
  # no flag further down can reach it.
  if (( ${+HELD_FOR[$example]} )); then
    echo "--- $example: held: ${HELD_FOR[$example]}"
    (( held += 1 ))
    continue
  fi
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
  # What the row records about the render: the seed it drew under, and what
  # stood in for a device, if anything did.
  export MEDIA_SEED=$SEED MEDIA_STAGED="$(stand_in $example)"
  if [[ -n $MEDIA_STAGED ]]; then echo "  staged: $MEDIA_STAGED"; fi
  target="Example-${example//\//-}"
  swift build -c release --package-path $ROOT/Examples --product $target > /dev/null 2>&1 \
    || { echo "  build failed" >&2; continue; }

  [[ $want_seconds == "-" ]] && want_seconds=$SECONDS_DEFAULT
  if (( want_seconds > CLIP_LIMIT )); then
    echo "  its row asks for ${want_seconds}s, and a clip is held to $CLIP_LIMIT"
    want_seconds=$CLIP_LIMIT
  fi
  [[ $want_frame == "-" ]] && want_frame=$STILL_FRAME_DEFAULT

  # A sketch that carries light past white films in HDR, and the page's clip
  # is standard range: encoded without a tone map it plays dim and gray. Its
  # picture is already the standard-range one, so it keeps that and no clip.
  if grep -q 'colorOutput: ColorOutput { \.extended }' $folder/Sketch.swift; then
    render $BIN/$target --export $OUT/$key.png --frame $want_frame --photo --seed $SEED || true
    [[ -f $OUT/$key.png ]] || { echo "  nothing to show" >&2; continue; }
    size=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $OUT/$key.png)
    echo "  films in HDR, so a picture and no clip"
    publish_still 0 "films in HDR, which the page's standard-range clip would play dim"
    (( made += 1 ))
    continue
  fi

  master=$OUT/$key.mov
  if grep -q 'loopDuration' $folder/Sketch.swift; then
    render $BIN/$target --export-loop $master --codec proRes422 --fps $FPS --photo --seed $SEED || true
    length=lap
  else
    render $BIN/$target --export-video $master --seconds $want_seconds --fps $FPS --codec proRes422 --photo --seed $SEED || true
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
    render $BIN/$target --export $OUT/$key.png --frame $want_frame --photo --seed $SEED || true
    if [[ ! -f $OUT/$key.png ]]; then
      echo "  could not be drawn at all" >&2
      python3 $ROOT/Scripts/media-manifest.py skip $MANIFEST "$example" "could not be drawn on this machine" "$digest"
      (( passed += 1 ))
      continue
    fi
    size=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $OUT/$key.png)
    publish_still 0 "too slow to film on this machine"
    (( made += 1 ))
    continue
  fi

  # A sketch that makes music has something to show even when its picture
  # holds still, so sound counts alongside movement.
  sound=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 $master 2>/dev/null)
  motion=$(motion_of $master)
  still_only=0
  [[ $(echo "$motion < $MOTION_FLOOR" | bc -l) == 1 && -z $sound ]] && still_only=1

  render $BIN/$target --export $OUT/$key.png --frame $want_frame --photo --seed $SEED || true
  if (( still_only )); then
    rm -f $master
    [[ -f $OUT/$key.png ]] || { echo "  nothing to show" >&2; continue; }
    echo "  holds still ($motion), so a picture and no clip"
    publish_still $motion "holds still"
    (( made += 1 ))
    continue
  fi
  if [[ -n $sound ]]; then
    audio=(-c:a aac -b:a 128k)
  else
    audio=(-an)
  fi
  # A lap longer than the limit shows its first part, and both clips are cut
  # from the same master so they stay one picture.
  duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 $master 2>/dev/null)
  cut=()
  if (( ${duration:-0} > CLIP_LIMIT + 0.05 )); then
    echo "  a lap of $(printf '%.0f' $duration)s, so its first $CLIP_LIMIT"
    cut=(-t $CLIP_LIMIT)
    length="first ${CLIP_LIMIT}s of a lap"
    duration=$CLIP_LIMIT
  fi
  ffmpeg -y -loglevel error -i $master $cut -vf $(cap 1080) -c:v libx264 -profile:v high -level 4.0 \
    -crf 20 -preset slow -pix_fmt yuv420p -color_primaries bt709 -color_trc bt709 \
    -colorspace bt709 -maxrate 6M -bufsize 12M -g 120 $audio -movflags +faststart $OUT/$key-loop.mp4
  # The grid's clip plays under the pointer, so it is held to 2 Mbit/s and to
  # about 3 MB in all: a lap longer than twelve seconds lowers its rate to
  # fit, since a long lap at the full rate was 6 to 10 MB on a phone.
  small_rate=$(python3 -c "import sys; d=float(sys.argv[1] or 10); print(f'{min(2.0, 24.0 / max(d, 1)):.3f}')" "$duration")
  ffmpeg -y -loglevel error -i $master $cut -vf $(cap 640) -r 30 -c:v libx264 -profile:v high -level 4.0 \
    -crf 24 -preset slow -pix_fmt yuv420p -color_primaries bt709 -color_trc bt709 \
    -colorspace bt709 -maxrate ${small_rate}M -bufsize $(python3 -c "print(f'{2 * float(\"$small_rate\"):.3f}')")M \
    -g 60 -an -movflags +faststart $OUT/$key-loop-640.mp4
  make_stills
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

echo "media: $made rendered, $passed passed over or unchanged, $held held"
