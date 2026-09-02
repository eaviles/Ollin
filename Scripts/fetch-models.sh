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
#   mobileclip_s0_image + mobileclip_s0_text: the paired image/text encoders
#     of MobileCLIP-S0 (CVPR 2024, Pavan K. A. Vasu et al.), Apple's official
#     Core ML export, under Apple's permissive weights license (the HF repo
#     declares apple-ascl; no research-only restriction).
#     https://huggingface.co/apple/coreml-mobileclip
#     (MobileCLIP2 is research-only and is deliberately NOT fetched.)
#   SAM2_1SmallImageEncoderFLOAT16 + SAM2_1SmallPromptEncoderFLOAT16 +
#     SAM2_1SmallMaskDecoderFLOAT16: the three parts of one promptable
#     segmentation model, Apache-2.0. Meta's Segment Anything 2.1 (small),
#     in Apple's official Core ML conversion.
#     https://huggingface.co/apple/coreml-sam2.1-small
#   VideoDepthAnythingSmallF16 + VideoDepthAnythingSmallClipF16: temporally
#     consistent video depth, Apache-2.0, one frame at a time (DepthTracker)
#     and a 32-frame window at a time (DepthClip, a whole clip ahead of time),
#     plus VideoDepthClipReference.bin, the upstream clip inference the tests
#     check the pass against. Video Depth Anything (small), Sili Chen et al.,
#     CVPR 2025, https://github.com/DepthAnything/Video-Depth-Anything.
#     Nobody publishes a Core ML build of it, so these are made on this
#     machine by Scripts/convert-video-depth.sh (a one-time Python step of a
#     few minutes, each checked against the upstream code), not downloaded.
#   bpe_simple_vocab_16e6.txt: the byte-pair-encoding vocabulary the text
#     encoder was trained with, from OpenAI's CLIP repository (MIT),
#     https://github.com/openai/CLIP; gunzipped at download.
#
# (The style-transfer example's model is not fetched here: you train your
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

# An .mlpackage hosted as a bare directory (the Hugging Face layout): its
# three files download one by one.
fetch_hf_mlpackage() {
    local name="$1" base="$2"
    if [[ -d "$MODELS_DIR/$name.mlpackage" && "$FORCE" == false ]]; then
        echo "✓ $name.mlpackage already in $MODELS_DIR/ (use --force to re-download)"
        return
    fi
    echo "Downloading $name.mlpackage…"
    rm -rf "$MODELS_DIR/$name.mlpackage"
    local file
    for file in "Data/com.apple.CoreML/model.mlmodel" \
                "Data/com.apple.CoreML/weights/weight.bin" \
                "Manifest.json"; do
        mkdir -p "$MODELS_DIR/$name.mlpackage/$(dirname "$file")"
        curl --fail --location --progress-bar \
            --output "$MODELS_DIR/$name.mlpackage/$file" "$base/$name.mlpackage/$file"
    done
    echo "✓ $name.mlpackage → $MODELS_DIR/"
}

# A gzipped text file downloads and unpacks in place.
fetch_gz_text() {
    local name="$1" url="$2"
    if [[ -f "$MODELS_DIR/$name" && "$FORCE" == false ]]; then
        echo "✓ $name already in $MODELS_DIR/ (use --force to re-download)"
        return
    fi
    echo "Downloading ${name}…"
    mkdir -p "$MODELS_DIR"
    curl --fail --location --progress-bar --output "$MODELS_DIR/$name.gz" "$url"
    gunzip -f "$MODELS_DIR/$name.gz"
    echo "✓ $name → $MODELS_DIR/"
}

fetch "DepthAnythingV2SmallF16" \
    "https://ml-assets.apple.com/coreml/models/Image/DepthEstimation/DepthAnything/DepthAnythingV2SmallF16.mlpackage.zip"

fetch_mlmodel "YOLOv3TinyFP16" \
    "https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3TinyFP16.mlmodel"

fetch_mlmodel "MNISTClassifier" \
    "https://ml-assets.apple.com/coreml/models/Image/DrawingClassification/MNISTClassifier/MNISTClassifier.mlmodel"

fetch_mlmodel "DeepLabV3FP16" \
    "https://ml-assets.apple.com/coreml/models/Image/ImageSegmentation/DeepLabV3/DeepLabV3FP16.mlmodel"

fetch_hf_mlpackage "mobileclip_s0_image" \
    "https://huggingface.co/apple/coreml-mobileclip/resolve/main"

fetch_hf_mlpackage "mobileclip_s0_text" \
    "https://huggingface.co/apple/coreml-mobileclip/resolve/main"

fetch_hf_mlpackage "SAM2_1SmallImageEncoderFLOAT16" \
    "https://huggingface.co/apple/coreml-sam2.1-small/resolve/main"

fetch_hf_mlpackage "SAM2_1SmallPromptEncoderFLOAT16" \
    "https://huggingface.co/apple/coreml-sam2.1-small/resolve/main"

fetch_hf_mlpackage "SAM2_1SmallMaskDecoderFLOAT16" \
    "https://huggingface.co/apple/coreml-sam2.1-small/resolve/main"

fetch_gz_text "bpe_simple_vocab_16e6.txt" \
    "https://github.com/openai/CLIP/raw/main/clip/bpe_simple_vocab_16e6.txt.gz"

# Made here rather than downloaded (see the header); the script is idempotent
# and skips itself once the package exists.
if [[ "$FORCE" == true ]]; then
    Scripts/convert-video-depth.sh --force
else
    Scripts/convert-video-depth.sh
fi
