#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Autostereogram`</sup>

---

## Autostereogram

**`Image.autostereogram(_:pattern:seed:)`** hides a shape in a picture's own repetition. Look through the picture until the repeats double up, and a surface you never drew stands out of the page.

```swift
let hidden = depthMap.autostereogram(Autostereogram(repeatWidth: 120, relief: 0.22))
drawImage(hidden, in: rect)
```

The whole technique comes from one rule:

```
   |------ repeat ------|          a flat background repeats at a fixed spacing,
   .  . ..  .  . ..  .  .          so both eyes pair the same marks and read
                                   them at the depth that spacing stands for

   |--- shorter ---|               shorten the repeat and the pair reads as
   .  . ..  .  . ..  .  .          nearer. that is the whole technique
```

Ollin turns a depth map into a picture by shortening the repeat wherever the shape is closer. The surface you see is not in the picture at all, because it is the depth your eyes work out from the pairing.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/09-Pictures/DepthInARepeat-dark.jpg">
  <img src="../../Guide/Images/09-Pictures/DepthInARepeat.jpg" alt="Two strips of scattered marks. The top one repeats at a fixed spacing, marked with a bracket underneath. The bottom one repeats at that spacing at its ends and at a shorter spacing through the middle, with both brackets marked and the shorter one in orange" width="680">
</picture>

### Contents

- [autostereogram](#make)
- [Autostereogram settings](#settings)
- [Practical notes](#notes)

<a name="make"></a>

#### autostereogram

```swift
Image.autostereogram(_ settings: Autostereogram = Autostereogram(),
                     pattern: Image? = nil, seed: Int = 0) -> Image?

drawAutostereogram(of depth: Image, in rect: Rectangle? = nil,
                   settings: Autostereogram = Autostereogram(),
                   pattern: Image? = nil, seed: Int = 0)
```

The picture you pass in is the **depth map**. The brightness of a pixel says how near that part of the shape sits. Draw the shape in white on black, or hand a rendered depth buffer straight in.

The call returns nil when the picture is no wider than one repeat. It also returns nil when the picture is texture-backed and has no CPU pixels, so read a frame through `snapshot()` first.

**`pattern`** is the tile to repeat. Pass nil for seeded color noise, which is what the classic pictures use, because noise pairs unambiguously. A pattern with large flat areas gives the eyes nothing to lock onto. A pattern with obvious repeats of its own gives them the wrong thing to pair.

The picture is built column by column. Every column takes its color from the column one separation to its left, so the leftmost repeat is the only free choice. That is why the pattern only has to be one repeat wide.

<a name="settings"></a>

#### Autostereogram settings

```swift
struct Autostereogram {
    var repeatWidth: Int = 120     // pixels between repeats at the far plane
    var relief: Double = 0.22      // how much the repeat shortens at the nearest point
    var whiteIsNear: Bool = true
}
```

- **`repeatWidth`** is the far-plane spacing. A wider repeat is easier on the eyes and holds less detail. Use about a sixth of the picture's width, or 100 to 140 pixels for a screen at arm's length.
- **`relief`** is how much nearer the closest part sits, as a fraction of the repeat. The eyes **cannot pair the picture at all past about a third**. That is the limit of the technique, not a dial to turn up.
- **`whiteIsNear`** sets which brightness counts as near.

<a name="notes"></a>

#### Practical notes

- **Draw it at its own pixel size.** Scaling resamples the repeats that the eyes have to pair. A stereogram shown at 80% is much harder to fuse, and one shown at 40% is impossible.
- **Hard edges read best.** A soft gradient gives the eyes nothing to lock onto at the edge of a shape. Shapes with flat tops and sharp sides come through much more clearly than a smooth blob.
- **The edges of a shape are ambiguous.** Within one separation of a depth step, neither depth is the answer. A viewer sees that as a shimmer along the edge, and it comes from the technique, not from the code.
- **Reading it takes practice.** Look *through* the picture at something behind the screen until the repeats double up. If you cross your eyes instead, you read the same picture inside out, so a shape that should stand up appears to sink.
- **An exported frame is dithered.** The present pass adds a level of noise. The repeats in a saved PNG then match to within a level or two rather than exactly. Eyes do not care, but a program reading one back has to allow for it.

Example: `Images/Autostereogram`. Guide: [Chapter 9](../../Guide/09-Pictures.md).

---

#### Where this comes from

Christopher Tyler and Maureen Clarke made the first single-image random-dot stereogram in 1990. It builds on the random-dot stereogram Bela Julesz devised in 1959 to show that depth is worked out before shapes are recognized. The column-by-column construction is the one Harold Thimbleby, Stuart Inglis, and Ian Witten set out in "Displaying 3D Images" (*IEEE Computer* 27/10, 1994). See [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

#### Go deeper

- [Images](./Images.md): loading, drawing, and pixel access
- [Depth compositing](../3D/DepthCompositing.md): where a real depth map comes from, and what else you can do with one
- [Spatial export](../Output/Spatial.md): the other way to send depth to two eyes, one picture each
