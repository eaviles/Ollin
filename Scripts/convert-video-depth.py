#!/usr/bin/env python3
"""Convert Video Depth Anything to a stateful Core ML package, one frame at a time.

Video Depth Anything (Sili Chen et al., CVPR 2025, Apache-2.0 code; the Small
checkpoint is Apache-2.0, the Base and Large checkpoints CC-BY-NC-4.0) predicts
temporally consistent relative depth. Its published inference reads clips of 32
frames; the repository also ships an experimental *streaming* mode that keeps a
cache of temporal-attention inputs and runs one frame at a time. This script
exports that streaming step as a single Core ML model with the cache held in
Core ML state, so a caller feeds one image per call and reads one depth map:

    inputs   image  (RGB, W x H, 0..255)     reset  (1,) float, 1 on the first frame
    outputs  depth  (1, 1, H, W) float32     relative inverse depth, larger is nearer
    state    cache_0 .. cache_7              the temporal-attention caches, 42 slots

The step reproduces the upstream streaming policy exactly: slot 0 keeps the first
frame of the session as a permanent anchor, slot 1 a slowly aging second anchor,
and the last 29 slots the most recent frames; a frame with `reset` set attends
only to itself and refills every slot with its own cache, which is what the
upstream code does for a session's first frame. The script checks the traced
step against the upstream head's own cached forward pass over a synthetic clip,
then checks the converted package against the traced step, and refuses to write
a package that disagrees.

Usage (from a clone of https://github.com/DepthAnything/Video-Depth-Anything):

    python3 convert-video-depth.py --repo path/to/Video-Depth-Anything \
        --checkpoint checkpoints/video_depth_anything_vits.pth \
        --encoder vits --out VideoDepthAnythingSmallF16.mlpackage

The input shape is fixed at conversion (the encoder's position embedding is
resolved for it); `--width` and `--height` take multiples of 14 and default to
518 x 392, the landscape shape the sibling single-image conversion uses.
Requirements: torch, coremltools, numpy, pillow, einops, easydict.
"""

import argparse
import os
import sys
import time

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

CONFIGS = {
    "vits": dict(features=64, out_channels=[48, 96, 192, 384]),
    "vitb": dict(features=128, out_channels=[96, 192, 384, 768]),
    "vitl": dict(features=256, out_channels=[256, 512, 1024, 1024]),
}
LAYERS = {"vits": [2, 5, 8, 11], "vitb": [2, 5, 8, 11], "vitl": [4, 11, 17, 23]}
NAMES = {"vits": "Small", "vitb": "Base", "vitl": "Large"}
LICENSES = {"vits": "Apache-2.0", "vitb": "CC-BY-NC-4.0", "vitl": "CC-BY-NC-4.0"}

# The upstream streaming policy, from video_depth_stream.py: a window of 32
# frames (31 cached plus the new one), kept in a list of 42 cache entries
# where entry 1 is dropped once the list is full.
INFER_LEN = 32
SLOTS = 42
WINDOW = INFER_LEN - 1
MEAN = [0.485, 0.456, 0.406]
STD = [0.229, 0.224, 0.225]


def load_upstream(repo):
    sys.path.insert(0, repo)
    from video_depth_anything.dinov2 import DINOv2
    from video_depth_anything.dpt_temporal import DPTHeadTemporal
    return DINOv2, DPTHeadTemporal


class Reference(nn.Module):
    """The upstream model's two halves, wired the way its own class wires them,
    minus the video reading. `depth` is the upstream head's own forward pass,
    cache and all, so the check below compares against the published code."""

    def __init__(self, encoder, DINOv2, DPTHeadTemporal):
        super().__init__()
        self.encoder = encoder
        self.pretrained = DINOv2(model_name=encoder)
        self.head = DPTHeadTemporal(self.pretrained.embed_dim, use_bn=False,
                                    use_clstoken=False, num_frames=INFER_LEN,
                                    pe="ape", **CONFIGS[encoder])

    def features(self, x):
        return self.pretrained.get_intermediate_layers(
            x, LAYERS[self.encoder], return_class_token=True)

    def depth(self, features, height, width, cache=None):
        out, new_cache = self.head(features, height // 14, width // 14, 1,
                                   cached_hidden_state_list=cache)
        out = F.interpolate(out, size=(height, width), mode="bilinear", align_corners=True)
        return F.relu(out), new_cache


def normalize(image):
    mean = torch.tensor(MEAN).view(1, 3, 1, 1)
    std = torch.tensor(STD).view(1, 3, 1, 1)
    return (image - mean) / std


def reference_stream(ref, frames, height, width):
    """The upstream streaming loop (infer_video_depth_one), on preprocessed
    frames: the first frame runs alone, every later one against the window
    the list policy selects."""
    depths, cache_list = [], []
    with torch.no_grad():
        for index, frame in enumerate(frames):
            feats = ref.features(normalize(frame))
            if index == 0:
                depth, cache = ref.depth(feats, height, width)
                cache_list = [cache] * INFER_LEN
            else:
                current = cache_list[0:2] + cache_list[-INFER_LEN + 3:]
                assert len(current) == WINDOW
                window = [torch.cat([entry[k] for entry in current], dim=1)
                          for k in range(len(current[0]))]
                depth, cache = ref.depth(feats, height, width, window)
                cache_list.append(cache)
            if index + INFER_LEN > SLOTS:
                del cache_list[1]
            depths.append(depth)
    return depths


class StreamingStep(nn.Module):
    """One streaming step with the caches as buffers: the module Core ML
    traces. The temporal attention is written out here so the cache can live
    in fixed-shape state; every weight and every other layer is the upstream
    module's own."""

    def __init__(self, ref, height, width):
        super().__init__()
        self.pretrained = ref.pretrained
        self.head = ref.head
        self.layers = LAYERS[ref.encoder]
        self.height, self.width = height, width
        self.register_buffer("mean", torch.tensor(MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(STD).view(1, 3, 1, 1))

        # The position embedding is a function of the input shape only; resolve
        # it once so the traced graph carries a constant instead of a resize.
        embed = self.pretrained.embed_dim
        tokens = 1 + (height // 14) * (width // 14)
        with torch.no_grad():
            pos = self.pretrained.interpolate_pos_encoding(
                torch.zeros(1, tokens, embed), height, width).clone()
        self.register_buffer("pos_embed_fixed", pos)
        self.pretrained.interpolate_pos_encoding = lambda x, w, h: self.pos_embed_fixed

        # One cache per temporal-attention block, shaped by a dry run of the
        # upstream head: (slots, tokens at that stage, channels).
        with torch.no_grad():
            feats = ref.features(torch.zeros(1, 3, height, width))
            _, cache = ref.depth(feats, height, width)
        self.cache_shapes = [(SLOTS, entry.shape[0], entry.shape[2]) for entry in cache]
        for k, shape in enumerate(self.cache_shapes):
            self.register_buffer(f"cache_{k}", torch.zeros(*shape))

    def forward(self, image, reset):
        x = (image - self.mean) / self.std
        feats = self.pretrained.get_intermediate_layers(x, self.layers, return_class_token=True)
        depth = self.head_step(feats, reset)
        depth = F.interpolate(depth, size=(self.height, self.width),
                              mode="bilinear", align_corners=True)
        return F.relu(depth)

    def head_step(self, features, reset):
        head = self.head
        patch_h, patch_w = self.height // 14, self.width // 14
        out = []
        for i, (tokens, _) in enumerate(features):
            x = tokens.permute(0, 2, 1).reshape(1, tokens.shape[-1], patch_h, patch_w)
            x = head.projects[i](x)
            x = head.resize_layers[i](x)
            out.append(x)
        layer_1, layer_2, layer_3, layer_4 = out

        layer_3 = self.temporal(0, layer_3, reset)
        layer_4 = self.temporal(1, layer_4, reset)

        layer_1_rn = head.scratch.layer1_rn(layer_1)
        layer_2_rn = head.scratch.layer2_rn(layer_2)
        layer_3_rn = head.scratch.layer3_rn(layer_3)
        layer_4_rn = head.scratch.layer4_rn(layer_4)

        path_4 = head.scratch.refinenet4(layer_4_rn, size=layer_3_rn.shape[2:])
        path_4 = self.temporal(2, path_4, reset)
        path_3 = head.scratch.refinenet3(path_4, layer_3_rn, size=layer_2_rn.shape[2:])
        path_3 = self.temporal(3, path_3, reset)
        path_2 = head.scratch.refinenet2(path_3, layer_2_rn, size=layer_1_rn.shape[2:])
        path_1 = head.scratch.refinenet1(path_2, layer_1_rn)

        out = head.scratch.output_conv1(path_1)
        out = F.interpolate(out, (patch_h * 14, patch_w * 14), mode="bilinear", align_corners=True)
        return head.scratch.output_conv2(out)

    def temporal(self, module_index, x, reset):
        """One temporal module over a single frame: the upstream transformer
        with its two attention blocks reading and writing the caches."""
        transformer = self.head.motion_modules[module_index].temporal_transformer
        residual = x
        h = transformer.norm(x)
        _, channels, rows, cols = h.shape
        h = h.permute(0, 2, 3, 1).reshape(1, rows * cols, channels)
        h = transformer.proj_in(h)
        block = transformer.transformer_blocks[0]
        for i, (attention, norm) in enumerate(zip(block.attention_blocks, block.norms)):
            cache = getattr(self, f"cache_{2 * module_index + i}")
            h = self.attend(attention, norm(h), cache, reset) + h
        h = block.ff(block.ff_norm(h)) + h
        h = transformer.proj_out(h)
        h = h.reshape(1, rows, cols, channels).permute(0, 3, 1, 2)
        return h + residual

    def attend(self, attention, normed, cache, reset):
        """Temporal attention for the new frame against the cached window, then
        the cache update. `normed` is (1, tokens, channels); its value is what
        the upstream code stores as this block's cache entry."""
        new = normed[0]                                        # (tokens, channels)
        tokens, channels = new.shape
        r = reset.reshape(1, 1)
        window = torch.cat([cache[0:2], cache[2 + (SLOTS - WINDOW):]], dim=0)   # (31, tokens, channels)

        pe = attention.pos_encoder.pe[0]                       # (32, channels)
        pe_new = pe[0:1] * r + pe[WINDOW:WINDOW + 1] * (1 - r)
        query_in = new + pe_new                                # (tokens, channels)
        context = torch.cat([window + pe[:WINDOW].unsqueeze(1), query_in.unsqueeze(0)], dim=0)
        context = context.permute(1, 0, 2)                     # (tokens, 32, channels)

        heads = attention.heads
        head_dim = channels // heads
        query = attention.to_q(query_in).reshape(tokens, 1, heads, head_dim).permute(0, 2, 1, 3)
        key = attention.to_k(context).reshape(tokens, INFER_LEN, heads, head_dim).permute(0, 2, 3, 1)
        value = attention.to_v(context).reshape(tokens, INFER_LEN, heads, head_dim).permute(0, 2, 1, 3)
        scores = torch.matmul(query, key) * attention.scale    # (tokens, heads, 1, 32)
        # A reset frame attends to itself alone, the way the first frame of a
        # session does upstream: the window's keys are pushed out of the softmax.
        masked = torch.cat([torch.full((1, 1, 1, WINDOW), -1e4), torch.zeros(1, 1, 1, 1)], dim=-1)
        scores = scores + masked * reset.reshape(1, 1, 1, 1)
        probs = scores.softmax(dim=-1)
        mixed = torch.matmul(probs, value)                     # (tokens, heads, 1, head_dim)
        mixed = mixed.permute(0, 2, 1, 3).reshape(tokens, 1, channels)
        out = attention.to_out[0](mixed).permute(1, 0, 2)      # (1, tokens, channels)

        rolled = torch.cat([cache[0:1], cache[2:], new.unsqueeze(0)], dim=0)
        filled = new.unsqueeze(0).expand(SLOTS, -1, -1)
        r3 = reset.reshape(1, 1, 1)
        # A slice assignment, which is the in-place form the converter turns
        # into a state update (a whole-tensor copy_ is not recognized).
        cache[:] = rolled * (1 - r3) + filled * r3
        return out


def synthetic_clip(count, height, width, seed=7):
    """A deterministic clip with structure at several scales and motion: a
    gradient, drifting soft blobs, and a moving hard-edged bar."""
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    ys, xs = ys / height, xs / width
    centers = rng.uniform(0.1, 0.9, size=(6, 2)).astype(np.float32)
    velocities = rng.uniform(-0.01, 0.01, size=(6, 2)).astype(np.float32)
    frames = []
    for t in range(count):
        image = np.zeros((3, height, width), dtype=np.float32)
        image[0] = xs
        image[1] = ys
        image[2] = 0.5 + 0.5 * np.sin(6.0 * xs + 0.1 * t)
        for c in range(6):
            cx, cy = centers[c] + velocities[c] * t
            blob = np.exp(-(((xs - cx) ** 2 + (ys - cy) ** 2) / 0.01))
            image[c % 3] = image[c % 3] * (1 - blob) + blob * ((c + 1) / 7.0)
        bar_x = 0.2 + 0.6 * ((t % 20) / 20.0)
        image[:, :, int(bar_x * width):int(bar_x * width) + width // 10] = 0.9
        image = np.clip(image, 0, 1)
        frames.append((image * 255).round().astype(np.uint8))
    return frames


def report(label, reference, candidate):
    """Max and mean absolute difference, relative to the reference's spread."""
    worst, total, count = 0.0, 0.0, 0
    spread = max(float(r.max() - r.min()) for r in reference) or 1.0
    for a, b in zip(reference, candidate):
        diff = np.abs(np.asarray(a, dtype=np.float32) - np.asarray(b, dtype=np.float32))
        worst = max(worst, float(diff.max()))
        total += float(diff.mean())
        count += 1
    print(f"  {label}: max {worst / spread:.5f}, mean {total / count / spread:.6f} "
          f"(relative to a depth spread of {spread:.2f}, over {count} frames)")
    return worst / spread


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--repo", required=True, help="a clone of the upstream repository")
    parser.add_argument("--checkpoint", required=True, help="the .pth checkpoint")
    parser.add_argument("--encoder", default="vits", choices=list(CONFIGS))
    parser.add_argument("--out", required=True, help="the .mlpackage to write")
    parser.add_argument("--width", type=int, default=518)
    parser.add_argument("--height", type=int, default=392)
    parser.add_argument("--frames", type=int, default=48, help="check clip length")
    parser.add_argument("--source-commit", default="", help="upstream commit, recorded as metadata")
    args = parser.parse_args()
    if args.width % 14 or args.height % 14:
        sys.exit("error: --width and --height must be multiples of 14")

    import coremltools as ct
    from PIL import Image

    DINOv2, DPTHeadTemporal = load_upstream(os.path.abspath(args.repo))
    torch.manual_seed(0)
    ref = Reference(args.encoder, DINOv2, DPTHeadTemporal)
    state = torch.load(args.checkpoint, map_location="cpu")
    ref.load_state_dict(state, strict=True)
    ref.eval()
    height, width = args.height, args.width
    print(f"Loaded {args.encoder} from {args.checkpoint}; input {width} x {height}")

    clip = synthetic_clip(args.frames, height, width)
    tensors = [torch.from_numpy(f).float().unsqueeze(0) / 255.0 for f in clip]

    print("Running the upstream streaming loop as the reference...")
    started = time.time()
    reference = [d[0, 0].numpy() for d in reference_stream(ref, tensors, height, width)]
    print(f"  {len(reference)} frames in {time.time() - started:.1f} s")

    step = StreamingStep(ref, height, width).eval()
    print("Running the stateful step in PyTorch...")
    stepped = []
    with torch.no_grad():
        for index, frame in enumerate(tensors):
            reset = torch.tensor([1.0 if index == 0 else 0.0])
            stepped.append(step(frame, reset)[0, 0].numpy())
    worst = report("stateful step vs upstream", reference, stepped)
    if worst > 1e-3:
        sys.exit("error: the stateful step does not reproduce the upstream streaming pass")

    print("Tracing...")
    for k in range(len(step.cache_shapes)):
        getattr(step, f"cache_{k}").zero_()
    example = (tensors[0], torch.tensor([1.0]))
    with torch.no_grad():
        traced = torch.jit.trace(step, example, check_trace=False)

    print("Converting...")
    states = [ct.StateType(wrapped_type=ct.TensorType(shape=shape, dtype=np.float16),
                           name=f"cache_{k}")
              for k, shape in enumerate(step.cache_shapes)]
    model = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[ct.ImageType(name="image", shape=(1, 3, height, width),
                             scale=1 / 255.0, color_layout=ct.colorlayout.RGB),
                ct.TensorType(name="reset", shape=(1,), dtype=np.float32)],
        outputs=[ct.TensorType(name="depth", dtype=np.float32)],
        states=states,
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=ct.precision.FLOAT16,
    )

    size = NAMES[args.encoder]
    model.author = "Sili Chen, Hengkai Guo, Shengnan Zhu, Feihu Zhang, Zilong Huang, " \
                   "Jiashi Feng, Bingyi Kang (Video Depth Anything, ByteDance)"
    model.license = LICENSES[args.encoder]
    model.version = "1.0"
    model.short_description = (
        f"Video Depth Anything ({size}), streaming: temporally consistent relative "
        f"depth from one frame at a time, with the temporal-attention cache held in "
        f"model state. Feed frames in order; set reset to 1 on the first frame of a "
        f"session. Depth is relative inverse depth: larger is nearer.")
    model.input_description["image"] = f"One RGB frame, {width} x {height}."
    model.input_description["reset"] = "1 on the first frame of a session (the frame then " \
                                       "anchors the session's depth scale), else 0."
    model.output_description["depth"] = "Relative inverse depth, (1, 1, height, width); " \
                                        "larger is nearer, scale consistent across frames."
    meta = model.user_defined_metadata
    meta["source"] = "https://github.com/DepthAnything/Video-Depth-Anything"
    meta["paper"] = "https://arxiv.org/abs/2501.12375"
    meta["checkpoint"] = os.path.basename(args.checkpoint)
    if args.source_commit:
        meta["source_commit"] = args.source_commit
    meta["converter"] = "Scripts/convert-video-depth.py (Ollin)"
    meta["input_size"] = f"{width}x{height}"
    meta["computeUnits"] = "cpuAndGPU"

    # A stateful model only opens its state once loaded by the framework from
    # disk, so the package is written first and checked from there; a package
    # that disagrees with the traced step is removed again.
    import shutil
    if os.path.exists(args.out):
        shutil.rmtree(args.out)
    model.save(args.out)
    print(f"Wrote {args.out}; checking it on this machine...")
    # CPU and GPU, by measurement: the Neural Engine fails to build an execution
    # plan for this graph (error -14 at load), and on the GPU a frame takes about
    # 68 ms on an M2 against 140 ms on the CPU alone. A caller must pin the
    # same units; `computeUnits` in the metadata says so.
    loaded = ct.models.MLModel(args.out, compute_units=ct.ComputeUnit.CPU_AND_GPU)
    if loaded._framework_error is not None:
        shutil.rmtree(args.out)
        sys.exit(f"error: the package would not load: {loaded._framework_error}")
    predicted = []
    session = loaded.make_state()
    started = time.time()
    for index, frame in enumerate(clip):
        picture = Image.fromarray(np.transpose(frame, (1, 2, 0)))
        result = loaded.predict({"image": picture,
                                 "reset": np.array([1.0 if index == 0 else 0.0], dtype=np.float32)},
                                state=session)
        predicted.append(result["depth"][0, 0])
        if index == 0:
            started = time.time()
    per_frame = (time.time() - started) / max(len(clip) - 1, 1)
    print(f"  {per_frame * 1000:.1f} ms per frame after the first (Python overhead included)")
    worst = report("Core ML vs stateful step", stepped, predicted)
    if worst > 0.05:
        shutil.rmtree(args.out)
        sys.exit("error: the converted package disagrees with the traced step; removed it")
    print(f"Done: {args.out}")


if __name__ == "__main__":
    main()
