#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Video](./README.md) → `Slit scan`</sup>

---

## Slit scan

**`SlitScan`** keeps a rolling history of frames and rebuilds the image with every pixel read from a different moment, chosen by a delay. A left-to-right delay is the classic slit scan, each column a little further into the past. A radial delay ripples time outward. A gray map of any picture becomes a time-displacement lens. Slow motion stretches into ribbons, and fast motion shears into combs. Time becomes a spatial dimension.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/30-Seeing/SlitScanDelay-dark.jpg">
  <img src="../../Guide/Images/30-Seeing/SlitScanDelay.jpg" alt="Two panels: a synthetic clip's newest frame showing horizontal stripes with one bright horizontal band, and the slit-scanned version where that band has become a clean diagonal and the stripes have sheared" width="680">
</picture>

### Contents

- [Building the history](#history)
- [Reading it back](#reading)
- [Feeding it video or camera](#feeds)
- [Practical notes](#notes)

<a name="history"></a>

#### Building the history

```swift
SlitScan(frames: Int = 48)       // how deep the past reaches
history.push(frame)              // add the newest frame, once per draw()
history.count                    // frames held so far
history.clear()                  // drop the history
```

Depth times the source frame rate is the reach into the past. A depth of 48 frames at 60 fps spans 0.8 seconds. The first push fixes the history's size. Frames of any other size are skipped with a one-time note.

<a name="reading"></a>

#### Reading it back

```swift
history.image(delay: (Vector2) -> Double) -> Image?
history.image(delay map: Image) -> Image?
```

The closure form gets each pixel's normalized position (`0...1` each way, top-left origin). It returns how far into the past to read. `0` is the newest frame, and `1` is the oldest held.

```swift
history.push(frame)
if let warped = history.image(delay: { uv in uv.x }) {         // the classic scan
    drawImage(warped, in: canvasRectangle)
}

// other delays to try:
{ uv in dist(uv.x, uv.y, 0.5, 0.5) / 0.71 }     // time ripples outward
{ uv in 1 - uv.y }                              // the bottom edge is now
{ uv in noise(uv.x * 3, uv.y * 3) }             // turbulent time
```

The map form reads a gray image instead. Black is now, white is the oldest held, and anything between interpolates. Any picture then becomes the lens, such as a gradient, a face, or a snapshot of a generator's output. The map may be any size, and it is sampled across the frame.

<a name="feeds"></a>

#### Feeding it video or camera

The history eats CPU-pixel images. A painted `Image` and a `Camera` frame push directly. A `VideoPlayer` frame is texture-backed, so read it through the player's `snapshot()` first and push that. Under a headless export the pushes happen on the export clock, so a video-fed slit scan reproduces frame for frame.

<a name="notes"></a>

#### Practical notes

- **Memory is `width x height x 4 x frames` bytes.** Push modest sizes, such as a camera feed or a few-hundred-pixel painting, rather than full canvases. The composed image draws scaled up like any other.
- **Each pixel reads its nearest frame**, so a shallow history shows visible time-steps (combs). More frames smooth the sweep. The stepping also reads as texture, and many pieces keep it.
- **Slow motion stretches, fast motion shears.** A subject drifting along the delay axis smears into a long ribbon. Motion across it ripples instead. If everything just blurs, slow the subject or deepen the history.
- **Deterministic given the pushed frames**, so exports reproduce and a painted-source slit scan is snapshot-safe.

---

Related: [`Video`](./Video.md) (playback and `snapshot()`), [`Vision`](../Vision/Vision.md) (the camera feed), [`Images`](../Drawing/Images.md) (the `Image` type), [`Effects`](../Drawing/Effects.md) (the feedback layer, the GPU sibling: the previous frame, not a frame history).
