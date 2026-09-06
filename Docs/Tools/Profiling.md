#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Profiling`</sup>

---

## Profiling

Ollin renders on the GPU, so a sketch can draw a great deal before it slows down. When a sketch does slow down, you need to know which half of the frame, the CPU or the GPU, is taking the time. The inspector shows this. Its cell grid ends with three counts, and two bars sit under the grid. Together, the counts and the bars show where the frame time went.

In a standalone sketch, open the inspector with **⌘/**. In OllinLive, the gallery, and the live-coding host, the inspector is in the sidebar. Every host shows the same card.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/32-Installations/CostRow-dark.jpg">
  <img src="../../Guide/Images/32-Installations/CostRow.jpg" alt="A diagram of the inspector's cost row: a row of cells reading 1 draw, 2 passes, 1 batch, over a CPU bar filled a little over half and a GPU bar filled less, with callouts naming what each part means" width="680">
</picture>

### Contents

- [The two bars](#the-two-bars) - CPU against GPU, on one scale
- [The three counts](#the-three-counts) - draws, passes, batches
- [What to do about a slow frame](#what-to-do-about-a-slow-frame)
- [Capturing a frame for Xcode](#capturing-a-frame-for-xcode) - `captureGPUFrame()`
- [Reading the numbers from code](#reading-the-numbers-from-code) - `FrameProfile`

---

<a name="the-two-bars"></a>
### The two bars

The **CPU** bar is the time spent in your `draw()` plus the time spent encoding it into GPU commands. Tessellation is part of this time, and in an immediate-mode renderer it is the first cost to grow. The **GPU** bar is the time the device spent on the frame, read from the device's own timestamps.

Both bars use the same scale: the period of one frame. At 60 frames a second, that period is 16.7 ms. So the longer bar is the bottleneck, and two short bars mean the sketch has time to spare.

The two bars are not stacked into one, on purpose. The CPU builds frame N while the GPU is still drawing frame N-1, so the two times overlap instead of adding up. One stacked bar would suggest a total that does not exist.

Hover over either bar for the detail. The CPU tooltip splits its number into drawing time and encoding time, and it also shows the time spent waiting for the display. That wait is spare time, not work, so a large wait means the sketch has headroom.

The GPU number has one caveat. It is measured on the frame the device has just finished, which is a frame or two behind the one being built. The number is smoothed for display, so you only notice the lag when a sketch changes cost suddenly.

<a name="the-three-counts"></a>
### The three counts

- **Draws** is the number of draw calls the frame issued. Hover over it for the breakdown by path. The paths are instanced SDF shapes, fill and stroke vertices, mesh vertices, glyphs, images, fields, point splats, particles, and compute dispatches.
- **Passes** is the number of render passes the frame encoded. The canvas and the present are always two of them, and every effects layer, filter, shadow map, and probe bake adds its own pass.
- **Batches** is the number of runs the drawer recorded. A run ends, and a new one starts, whenever the pipeline, blend mode, texture, or clip level changes.

The ratio of batches to shapes is the useful number. Ten thousand circles in one batch cost one draw call, but ten circles that each change the blend mode cost ten draw calls.

The first frame reads higher than the frames after it, because some setup happens once and is then cached for the life of the window.

<a name="what-to-do-about-a-slow-frame"></a>
### What to do about a slow frame

Read the bars first, then act on the longer one.

**The CPU bar is longer.** The frame is spending its time building geometry.

- Check the draws tooltip for a large vertex count. Fills and strokes are tessellated on the CPU, but each closed shape in the [SDF catalog](../Drawing/Drawing.md) is one instance.
- Put static geometry in a [retained batch](../Drawing/Batches.md). A batch is recorded once and then replayed from GPU memory on every later frame.
- A high batch count with few shapes means the state changes for each shape. Group together the shapes that share a blend mode, a texture, or a clip.

**The GPU bar is longer.** The frame is spending its time shading pixels.

- Look at the pass count. A long [filter chain](../Drawing/Effects.md) is a series of passes over the whole canvas, and each pass costs fill rate.
- An effects layer can render at a fraction of the canvas size. Pass `scale:` to `makeRenderTarget(scale:)` for any soft effect, such as a blur or a glow.
- In 3D, shadows, reflections, and global illumination each add passes of their own. The [3D pages](../3D/3D.md) give the cost of each one.

**Both bars are short and the frame rate is still low.** Something outside the drawing is holding up the frame. A file read or a heavy `setup()` call in the middle of `draw()` will do it.

<a name="capturing-a-frame-for-xcode"></a>
### Capturing a frame for Xcode

When the GPU bar is longer and you need to know which pass is slow, hand the frame to Metal's own debugger:

```swift
if frameCount == 120 { captureGPUFrame() }        // or: captureGPUFrame(to: "slow.gputrace")
```

The captured frame is the same frame you call `captureGPUFrame()` from, because the request is taken between your `draw()` and the render that follows it. Ollin writes a `.gputrace` file. That file opens in Xcode and shows per-pass timings, the pipeline state, and every bound resource.

**Metal does not capture unless the process asks for it at launch.** Run the sketch with the capture flag set:

```sh
MTL_CAPTURE_ENABLED=1 ollin MySketch.swift
```

Without the flag, the sketch prints the command line above and keeps drawing. The host menu offers the same capture as an action. **View ▸ Capture GPU Frame (⌘⇧G)** captures the next frame.

Either way, Ollin prints the frame's passes in order next to the file path. That list alone often answers the question, and you do not need to open Xcode to read it.

<a name="reading-the-numbers-from-code"></a>
### Reading the numbers from code

A sketch can read the same numbers through the [extension seam](../Core/Sketch.md#extensions). `FrameInfo` carries a `FrameProfile`, so an extension can log a frame, watch for a threshold, or draw its own readout:

```swift
final class SlowFrameLog: SketchExtension {
    func afterFrame(_ sketch: Sketch, _ info: FrameInfo) {
        let p = info.profile
        guard p.cpuMS > 8 else { return }
        print("frame \(sketch.frameCount): \(p.cpuMS) ms CPU, \(p.drawCalls) draws, \(p.batches) batches")
    }
}
```

`FrameProfile` holds three groups of values. The first group is the four times (`cpuDrawMS`, `cpuEncodeMS`, `gpuMS`, `waitMS`). The second is the submitted work (`drawCalls`, `passes`, `computeDispatches`, `batches`), and the third is the geometry each path drew. `cpuMS` is the sum of the two CPU times, and `tessellatedVertices` is the sum of every vertex the CPU built this frame.

The counts reflect what was drawn, not what was recorded, so a batch the renderer skipped does not appear in them.

---

Related: [Sketch](../Core/Sketch.md) - [Drawing](../Drawing/Drawing.md) - [Retained batches](../Drawing/Batches.md) - [Effects](../Drawing/Effects.md) - [Parameters](../Helpers/Parameters.md)
