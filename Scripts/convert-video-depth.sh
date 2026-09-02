#!/bin/bash
# Produces Ollin's own Core ML conversions of Video Depth Anything (small)
# in Models/ on this machine, made from the upstream PyTorch checkpoint by
# Scripts/convert-video-depth.py: VideoDepthAnythingSmallF16.mlpackage (the
# streaming step DepthTracker runs, one frame at a time) and
# VideoDepthAnythingSmallClipF16.mlpackage (the 32-frame window DepthClip
# reads a whole recording through ahead of time), plus
# VideoDepthClipReference.bin, the upstream clip inference on a fixed clip
# that DepthClip's tests check the scheduler against. Nobody publishes a
# Core ML build of this model, so fetch-models.sh calls this when a package
# is missing; run it directly to rebuild (pass --force to redo every step).
#
# It takes a few minutes the first time: a Python virtual environment with
# torch and coremltools (about 400 MB), a shallow clone of the upstream
# repository pinned to one commit, the 116 MB checkpoint from Hugging Face,
# and the conversions themselves, each checked against the upstream code
# before it is written. Everything but the packages lands under Models/.work/
# (gitignored with the rest of Models/).
#
# Needs a Python from 3.10 to 3.13 (torch and coremltools ship no wheels for
# 3.14 yet); `brew install python@3.13` provides one.
#
# Video Depth Anything: Sili Chen, Hengkai Guo, Shengnan Zhu, Feihu Zhang,
# Zilong Huang, Jiashi Feng, Bingyi Kang, CVPR 2025.
# https://github.com/DepthAnything/Video-Depth-Anything (Apache-2.0; the small
# checkpoint is Apache-2.0, the larger ones CC-BY-NC-4.0 and not used here).

set -euo pipefail
cd "$(dirname "$0")/.."

NAME="VideoDepthAnythingSmallF16"
CLIP_NAME="VideoDepthAnythingSmallClipF16"
REFERENCE_NAME="VideoDepthClipReference.bin"
OUT="Models/$NAME.mlpackage"
CLIP_OUT="Models/$CLIP_NAME.mlpackage"
REFERENCE_OUT="Models/$REFERENCE_NAME"
WORK="Models/.work/video-depth"
UPSTREAM="https://github.com/DepthAnything/Video-Depth-Anything"
COMMIT="4f5ae23172ba60fd7bc11ef671cca678842c7072"
CHECKPOINT="video_depth_anything_vits.pth"
CHECKPOINT_URL="https://huggingface.co/depth-anything/Video-Depth-Anything-Small/resolve/main/$CHECKPOINT"
FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# Each product is made only when missing (or on --force).
WANT=()
if [[ -d "$OUT" && "$FORCE" == false ]]; then
    echo "✓ $NAME.mlpackage already in Models/ (use --force to rebuild)"
else
    WANT+=(--out "$OUT")
fi
if [[ -d "$CLIP_OUT" && "$FORCE" == false ]]; then
    echo "✓ $CLIP_NAME.mlpackage already in Models/ (use --force to rebuild)"
else
    WANT+=(--clip-out "$CLIP_OUT")
fi
if [[ -f "$REFERENCE_OUT" && "$FORCE" == false ]]; then
    echo "✓ $REFERENCE_NAME already in Models/ (use --force to rebuild)"
else
    WANT+=(--reference-out "$REFERENCE_OUT")
fi
if [[ ${#WANT[@]} -eq 0 ]]; then
    exit 0
fi

# A Python the conversion tools support, newest first.
PYTHON=""
for candidate in python3.13 python3.12 python3.11 python3.10 \
                 /opt/homebrew/opt/python@3.13/bin/python3.13 \
                 /opt/homebrew/opt/python@3.12/bin/python3.12 \
                 /usr/local/opt/python@3.13/bin/python3.13 \
                 /usr/local/opt/python@3.12/bin/python3.12; do
    if command -v "$candidate" >/dev/null 2>&1; then
        PYTHON="$(command -v "$candidate")"
        break
    fi
done
if [[ -z "$PYTHON" ]]; then
    echo "error: no Python 3.10 to 3.13 found (torch and coremltools have no wheels for newer ones)." >&2
    echo "       brew install python@3.13, then run this again." >&2
    exit 1
fi
echo "Using $PYTHON ($("$PYTHON" --version))"

mkdir -p "$WORK"

# The upstream clip inference imports torchvision, OpenCV, and tqdm, so the
# environment carries them beside torch and coremltools. A venv made before
# they were listed is completed in place.
VENV="$WORK/venv"
if [[ ! -x "$VENV/bin/python" || "$FORCE" == true ]]; then
    echo "Creating a virtual environment with torch and coremltools…"
    rm -rf "$VENV"
    "$PYTHON" -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip
fi
"$VENV/bin/pip" install --quiet "torch==2.7.0" "torchvision==0.22.0" "coremltools==9.0" \
    "numpy<2.3" pillow einops easydict opencv-python-headless tqdm

REPO="$WORK/Video-Depth-Anything"
if [[ ! -d "$REPO/.git" || "$FORCE" == true ]]; then
    echo "Cloning the upstream repository at ${COMMIT}…"
    rm -rf "$REPO"
    git clone --quiet --filter=blob:none "$UPSTREAM" "$REPO"
    git -C "$REPO" checkout --quiet "$COMMIT"
fi

if [[ ! -f "$WORK/$CHECKPOINT" || "$FORCE" == true ]]; then
    echo "Downloading the checkpoint ($CHECKPOINT, 116 MB)…"
    curl --fail --location --progress-bar --output "$WORK/$CHECKPOINT" "$CHECKPOINT_URL"
fi

echo "Converting (this checks each result against the upstream code; a few minutes)…"
"$VENV/bin/python" Scripts/convert-video-depth.py \
    --repo "$REPO" --checkpoint "$WORK/$CHECKPOINT" --encoder vits \
    "${WANT[@]}" --source-commit "$COMMIT" 2>&1 \
    | grep -v "TracerWarning\|assert [HW] %\|xFormers\|Converting PyTorch\|Running MIL\|added again\|_warnings.warn\|RuntimeWarning\|NSLocalizedDescription\|^}\|Remote\|Failed to load '_ML\|scikit-learn\|TensorFlow\|^\s*$" || true

for product in "$OUT" "$CLIP_OUT" "$REFERENCE_OUT"; do
    if [[ ! -e "$product" ]]; then
        echo "error: the conversion did not produce $product" >&2
        exit 1
    fi
done
echo "✓ $NAME.mlpackage, $CLIP_NAME.mlpackage, and $REFERENCE_NAME → Models/"
