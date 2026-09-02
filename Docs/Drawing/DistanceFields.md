#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Measured distance fields`</sup>

---

## Measured distance fields

Draw something into a layer, then ask every pixel in it two questions. How far away is the
nearest edge, and which way is it? `Filter.distanceField` answers both at once, on the GPU,
for a whole layer at a time.

This is the other half of the [SDF combinators](Combinators.md). There you *write* a
distance field with arithmetic and draw the shape it describes. Here you *measure* one back
out of a picture, whatever drew it: a circle, a stroked path, a glyph, a photograph's alpha,
a frame of video. The result is an ordinary layer, so it filters and combines like any other.

A distance field is worth having because so many effects are one line of arithmetic once you
have it. Growing and shrinking a shape, outlining it at any offset, drawing its contour lines,
finding which shape is nearest, softening a shadow by distance: each of those is a question
about distance, and none of them is easy without one.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/16-LayersAndEffects/MeasuredField-dark.jpg">
  <img src="../../Guide/Images/16-LayersAndEffects/MeasuredField.jpg" alt="Three dark panels. A circle, a square and a stroked zigzag on black; the same shapes as pale contour bands, each ring following its shape and merging with its neighbors where they meet; and the same shapes as flat color regions, each pixel wearing the color of the mark nearest to it" width="680">
</picture>

### Contents

- [Quick start](#quick-start)
- [What the field holds](#what-it-holds)
- [Reading it back as a picture](#field-map)
- [Reading it in a shader](#in-a-shader)
- [What counts as the shape](#the-shape)
- [How far to measure](#how-far)
- [How it works](#how-it-works)

<a name="quick-start"></a>

### Quick start

```swift
override func draw() {
    let marks = makeRenderTarget()
    withTarget(marks) {
        noStroke()
        fill(.white)
        drawCircle(width / 2, height / 2, 180)
    }

    let field = marks.filtered(.distanceField())

    // Contour bands, one every 40 pixels out from the edge.
    drawImage(field.filtered(.fieldMap(.viridis, from: 0, to: 40, repeating: true)).image, 0, 0)
}
```

Two calls: one measures the field, one reads it back as something you can look at.

<a name="what-it-holds"></a>

### What the field holds

The measured layer carries numbers rather than a color. Its channels are:

| Channel | What it holds |
|---|---|
| red | The distance in pixels to the nearest edge. Negative **inside** the shape, positive outside. |
| green, blue | The unit direction from this pixel toward that nearest edge. |
| alpha | 1. |

The two answers fit together:

```
    nearest edge point  =  pixel + direction * abs(distance)
```

so a sketch that wants to know what was drawn at the nearest edge can go and look. That is
what makes the direction worth keeping: a field that held only distance would have to be
measured again the first time anything asked which way.

Distances are in canvas pixels, the same unit `drawCircle(x, y, 180)` uses.

<a name="field-map"></a>

### Reading it back as a picture

`Filter.fieldMap` turns a measured field into something visible: the signed distance mapped
through a color ramp across a window given in pixels.

```swift
let field = marks.filtered(.distanceField())

// The field itself: cool inside the shape, warm outside, over 200 pixels either way.
field.filtered(.fieldMap(.turbo, from: -200, to: 200))

// Contour lines: the same ramp repeated every 40 pixels instead of stretched over one span.
field.filtered(.fieldMap(rings, from: 0, to: 40, repeating: true))
```

Because the window is in pixels and the ramp is yours, the same call does the work of several
separate effects. A ramp that turns over at one distance grows the shape (or shrinks it, at a
negative distance):

```swift
// Everything within 26 pixels of a mark, filled: the shapes grown, and merged where they meet.
field.filtered(.fieldMap(Ramp([ink, .clear]), from: 26, to: 27.5))
```

A ramp that is dark in a narrow band draws an outline at a chosen offset, and a window one
pixel wide keeps that outline smooth-edged rather than jagged.

<a name="in-a-shader"></a>

### Reading it in a shader

A [user shader](../Shaders/Shaders.md) reads the field with `sampleRaw`, which hands back the
layer's stored values untouched. The ordinary `sample` reads a layer as a color, and a
distance in pixels is not one.

This is the shader behind a Voronoi diagram keyed to a picture. Every pixel walks to its
nearest edge and brings back the color it finds there, so each mark paints the region that is
closer to it than to any other mark:

```metal
float4 shade(float2 uv, ShaderInfo info) {
    float4 field = sampleRaw(info, uv);
    float2 here = uv * info.resolution;
    // Step to the edge and a little past it, so the lookup lands in the mark rather than
    // on its soft rim. Signing the overshoot serves both sides: from outside the shape the
    // direction already points inward, and from inside it points out.
    float2 inside = here + field.gb * (abs(field.r) + 4.0 * sign(field.r));
    return sampleAux(info, inside / info.resolution);
}
```

Run it as a combine, with the field as the base and the drawn marks as the second input:

```swift
let cells = field.combined(with: marks, .shader(Shader(nearestMark)))
```

The `…Raw` pair exists for both variants: `sampleRaw` for the one-input filter form, and
`sampleAuxRaw` beside it for a combine whose *second* input is also data.

<a name="the-shape"></a>

### What counts as the shape

The edge is the place where the layer crosses a threshold, and `from` chooses which value is
being cut:

```swift
marks.filtered(.distanceField(from: .alpha, threshold: 0.5))     // the default
marks.filtered(.distanceField(from: .luminance, threshold: 0.4)) // for a layer with no transparency
```

`.alpha` is the coverage a shape was drawn with, which is what you want when the layer holds
marks on nothing. `.luminance`, `.red`, `.green` and `.blue` suit a layer that is opaque
everywhere, such as a photograph or a frame of video.

The crossing is found *between* pixels rather than at their centers: where two neighboring
pixels fall on either side of the threshold, the edge sits at the fraction of the way across
where the value would reach it. An antialiased shape is therefore measured to a fraction of a
pixel, and growing a shape by 20.5 pixels really does put its edge half a pixel outside where
growing by 20 puts it.

<a name="how-far"></a>

### How far to measure

By default the field is measured everywhere: every pixel finds its nearest edge however far
away it is. `maxDistance` says you only care about a band:

```swift
marks.filtered(.distanceField(maxDistance: 64))
```

Past that distance the field reads flat, with a zero direction, which says "nothing within
reach" rather than pointing somewhere untrue.

It is also the speed parameter. The measurement costs one pass per doubling of the distance it has
to carry, so a short answer is a genuinely shorter piece of work. On an M2 at 1080 square, a
field measured over the whole canvas costs about 4.9 ms of GPU time, and one capped at 64
pixels about 2.9 ms.

<a name="how-it-works"></a>

### How it works

The measurement is the jump-flooding algorithm (Rong & Tan, 2006), with the extra opening
pass of their 1+JFA variant (2007). Every pixel that sits on an edge starts out holding the
position of that edge. Then the layer is swept a number of times, and on each sweep a pixel
looks at eight neighbors a fixed step away and keeps whichever edge position is nearest to
it. The step starts at about half the layer and halves every sweep down to one, so an edge
reaches the far corner in about a dozen sweeps rather than a thousand:

```
    sweep 1        sweep 2        sweep 3              sweep n
    step 512       step 256       step 128     …       step 1
```

The result is approximate, in that a small number of pixels end up holding an edge slightly
farther away than their true nearest one. The published error rate is very low, and the
opening pass lowers it further. Ollin's implementation is written from those papers and
credited in [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

---

See also [SDF combinators](Combinators.md) for the field you write rather than measure,
[Effects](Effects.md) for the layer and filter substrate this is built on, [Shaders](../Shaders/Shaders.md)
for the user-shader seam, and [Voronoi & Delaunay](Voronoi.md) for the same partition built
as vector geometry from points instead of measured from a picture.
