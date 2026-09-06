#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Video](./README.md) → `Slit scan`</sup>

---

## Slit scan

**`SlitScan`** keeps a rolling history of frames. It rebuilds the image so that every pixel comes from a different moment, and a delay you supply picks the moment. A left-to-right delay gives you the classic slit scan, where each column reads a little further into the past. A radial delay makes time ripple outward. A gray map made from any picture turns that picture into a time-displacement lens. Slow motion stretches into ribbons, and fast motion shears into combs, because the delay has turned time into a spatial dimension.

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
SlitScan(capacity: Int = 48)       // how deep the past reaches
history.append(frame)              // add the newest frame, once per draw()
history.count                    // frames held so far
history.clear()                  // drop the history
```

The reach into the past is the depth times the source frame rate, so a depth of 48 frames at 60 fps spans 0.8 seconds. The first push fixes the size of the history. A frame of any other size is skipped, and you get one note about it.

<a name="reading"></a>

#### Reading it back

```swift
history.image(delay: (Vector2) -> Double) -> Image?
history.image(delay map: Image) -> Image?
```

The closure form hands you each pixel's normalized position, which runs `0...1` on both axes from a top-left origin. Your closure returns how far into the past that pixel reads. `0` is the newest frame, and `1` is the oldest frame still held.

```swift
history.append(frame)
if let warped = history.image(delay: { uv in uv.x }) {         // the classic scan
    drawImage(warped, in: canvasRectangle)
}

// other delays to try:
{ uv in dist(uv.x, uv.y, 0.5, 0.5) / 0.71 }     // time ripples outward
{ uv in 1 - uv.y }                              // the bottom edge is now
{ uv in noise(uv.x * 3, uv.y * 3) }             // turbulent time
```

The map form reads a gray image instead of calling a closure. Black means now, white means the oldest frame held, and a gray in between reads a frame between the two. Any picture can be the lens that way, such as a gradient, a face, or a snapshot of a generator's output. The map may be any size, because it is sampled across the frame.

<a name="feeds"></a>

#### Feeding it video or camera

The history takes CPU-pixel images. A painted `Image` and a `Camera` frame push straight in. A `VideoPlayer` frame is texture-backed, so read it through the player's `snapshot()` first and push the result. Under a headless export the pushes happen on the export clock, so a video-fed slit scan reproduces frame for frame.

<a name="notes"></a>

#### Practical notes

- **Memory is `width x height x 4 x frames` bytes.** Push modest sizes rather than full canvases, such as a camera feed or a painting a few hundred pixels across. You can draw the composed image scaled up, like any other image.
- **Each pixel reads its nearest frame**, so a shallow history shows visible time steps, which look like combs. More frames make the sweep smoother. The stepping also reads as texture, so many pieces keep it.
- **Slow motion stretches, fast motion shears.** A subject that drifts along the delay axis smears into a long ribbon. A subject that moves across that axis ripples instead. If everything only blurs, slow the subject down or deepen the history.
- **Deterministic given the pushed frames**, so an export reproduces, and a slit scan fed by a painted source is snapshot-safe.

---

Related: [`Video`](./Video.md) (playback and `snapshot()`), [`Vision`](../Vision/Vision.md) (the camera feed), [`Images`](../Drawing/Images.md) (the `Image` type). Also [`Effects`](../Drawing/Effects.md), the feedback layer, which is the GPU version of this idea and holds the previous frame rather than a frame history.
