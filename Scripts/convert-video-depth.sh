#!/bin/bash
# Produces Models/VideoDepthAnythingSmallF16.mlpackage on this machine: Ollin's
# own Core ML conversion of Video Depth Anything (small), made from the
# upstream PyTorch checkpoint by Scripts/convert-video-depth.py. Nobody
# publishes a Core ML build of this model, so fetch-models.sh calls this when
# the package is missing; run it directly to rebuild (pass --force to redo
# every step).
#
# It takes a few minutes the first time: a Python virtual environment with
# torch and coremltools (about 300 MB), a shallow clone of the upstream
# repository pinned to one commit, the 116 MB checkpoint from Hugging Face,
# and the conversion itself, which checks the result against the upstream
# code before writing it. Everything but the package lands under
# Models/.work/ (gitignored with the rest of Models/).
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
OUT="Models/$NAME.mlpackage"
WORK="Models/.work/video-depth"
UPSTREAM="https://github.com/DepthAnything/Video-Depth-Anything"
COMMIT="4f5ae23172ba60fd7bc11ef671cca678842c7072"
CHECKPOINT="video_depth_anything_vits.pth"
CHECKPOINT_URL="https://huggingface.co/depth-anything/Video-Depth-Anything-Small/resolve/main/$CHECKPOINT"
FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

if [[ -d "$OUT" && "$FORCE" == false ]]; then
    echo "✓ $NAME.mlpackage already in Models/ (use --force to rebuild)"
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

VENV="$WORK/venv"
if [[ ! -x "$VENV/bin/python" || "$FORCE" == true ]]; then
    echo "Creating a virtual environment with torch and coremltools…"
    rm -rf "$VENV"
    "$PYTHON" -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet "torch==2.7.0" "coremltools==9.0" "numpy<2.3" \
        pillow einops easydict
fi

REPO="$WORK/Video-Depth-Anything"
if [[ ! -d "$REPO/.git" || "$FORCE" == true ]]; then
    echo "Cloning the upstream repository at $COMMIT…"
    rm -rf "$REPO"
    git clone --quiet --filter=blob:none "$UPSTREAM" "$REPO"
    git -C "$REPO" checkout --quiet "$COMMIT"
fi

if [[ ! -f "$WORK/$CHECKPOINT" || "$FORCE" == true ]]; then
    echo "Downloading the checkpoint ($CHECKPOINT, 116 MB)…"
    curl --fail --location --progress-bar --output "$WORK/$CHECKPOINT" "$CHECKPOINT_URL"
fi

echo "Converting (this checks the result against the upstream code; a few minutes)…"
"$VENV/bin/python" Scripts/convert-video-depth.py \
    --repo "$REPO" --checkpoint "$WORK/$CHECKPOINT" --encoder vits \
    --out "$OUT" --source-commit "$COMMIT" 2>&1 \
    | grep -v "TracerWarning\|assert [HW] %\|xFormers\|Converting PyTorch\|Running MIL\|added again\|_warnings.warn\|RuntimeWarning\|NSLocalizedDescription\|^}\|Remote\|Failed to load '_ML\|scikit-learn\|TensorFlow\|^\s*$" || true

if [[ -d "$OUT" ]]; then
    echo "✓ $NAME.mlpackage → Models/"
else
    echo "error: the conversion did not produce $OUT" >&2
    exit 1
fi
