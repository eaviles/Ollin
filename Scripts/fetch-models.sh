#!/bin/bash
# Downloads the Core ML models the model-driven examples use into Models/
# (gitignored — model weights are fetched, never committed). Idempotent:
# a model already in place is skipped; pass --force to re-download.
#
# Models:
#   DepthAnythingV2SmallF16 — monocular depth estimation, Apache-2.0.
#     Apple's official Core ML conversion of Depth Anything V2 (small).
#     https://developer.apple.com/machine-learning/models/
#     https://huggingface.co/apple/coreml-depth-anything-v2-small

set -euo pipefail
cd "$(dirname "$0")/.."

MODELS_DIR="Models"
FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

fetch() {
    local name="$1" url="$2"
    if [[ -d "$MODELS_DIR/$name.mlpackage" && "$FORCE" == false ]]; then
        echo "✓ $name.mlpackage already in $MODELS_DIR/ (use --force to re-download)"
        return
    fi
    echo "Downloading $name.mlpackage…"
    local zip="$MODELS_DIR/$name.zip"
    mkdir -p "$MODELS_DIR"
    curl --fail --location --progress-bar --output "$zip" "$url"
    rm -rf "$MODELS_DIR/$name.mlpackage"
    unzip -q -o "$zip" -d "$MODELS_DIR" -x "__MACOSX/*"
    rm -f "$zip"
    [[ -d "$MODELS_DIR/$name.mlpackage" ]] || {
        echo "error: $name.mlpackage did not unpack as expected" >&2
        exit 1
    }
    echo "✓ $name.mlpackage → $MODELS_DIR/"
}

fetch "DepthAnythingV2SmallF16" \
    "https://ml-assets.apple.com/coreml/models/Image/DepthEstimation/DepthAnything/DepthAnythingV2SmallF16.mlpackage.zip"
