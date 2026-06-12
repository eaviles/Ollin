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
#   YOLOv3TinyFP16 — object detection (80 COCO classes), YOLO License v2
#     (public domain). Joseph Redmon & Ali Farhadi's YOLOv3-tiny, in Apple's
#     Core ML conversion from the same gallery.
#   MNISTClassifier — handwritten-digit classification, MIT (Apple).
#     The gallery's Turi Create-trained drawing classifier.
#   DeepLabV3FP16 — semantic segmentation (21 everyday classes), Apache-2.0.
#     The TensorFlow DeepLabV3 research model, in Apple's Core ML conversion
#     from the same gallery.
#
# (The style-transfer example's model is not fetched here — you train your
# own with Scripts/train-style-model.swift; see Examples/Vision/README.md.)

set -euo pipefail
cd "$(dirname "$0")/.."

MODELS_DIR="Models"
FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# An .mlpackage ships zipped; unzip it into place.
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

# A single-file .mlmodel downloads as-is.
fetch_mlmodel() {
    local name="$1" url="$2"
    if [[ -f "$MODELS_DIR/$name.mlmodel" && "$FORCE" == false ]]; then
        echo "✓ $name.mlmodel already in $MODELS_DIR/ (use --force to re-download)"
        return
    fi
    echo "Downloading $name.mlmodel…"
    mkdir -p "$MODELS_DIR"
    curl --fail --location --progress-bar --output "$MODELS_DIR/$name.mlmodel" "$url"
    echo "✓ $name.mlmodel → $MODELS_DIR/"
}

fetch "DepthAnythingV2SmallF16" \
    "https://ml-assets.apple.com/coreml/models/Image/DepthEstimation/DepthAnything/DepthAnythingV2SmallF16.mlpackage.zip"

fetch_mlmodel "YOLOv3TinyFP16" \
    "https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3TinyFP16.mlmodel"

fetch_mlmodel "MNISTClassifier" \
    "https://ml-assets.apple.com/coreml/models/Image/DrawingClassification/MNISTClassifier/MNISTClassifier.mlmodel"

fetch_mlmodel "DeepLabV3FP16" \
    "https://ml-assets.apple.com/coreml/models/Image/ImageSegmentation/DeepLabV3/DeepLabV3FP16.mlmodel"
