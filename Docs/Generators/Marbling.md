#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Marbling`</sup>

---

## Marbling

This page covers paper marbling in closed form. A **`Marbling`** bath holds colored ink regions as vector outlines. **`drop`** floats a new circle of ink and pushes everything already floating aside. Four raking tools bend every region at once: **`tine`**, **`comb`**, a circular tine, and **`swirl`**.

Each operation is an exact point transform from the classic marbling equations, the area-preserving drop and the stylus family with exponential falloff. Regions therefore deform without ever tearing or crossing. The finished paper is ordinary geometry, so you can fill it with `drawMarbling`, stroke the outlines, or send them to [SVG/PDF export](../Output/Export.md) as plotter-ready paths.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/MarblingSteps-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/MarblingSteps.jpg" alt="Four panels from one bull's-eye of alternating drops: the drops alone as concentric rings, a single stylus pulled down through them into a heart, a comb of teeth feathering them into a nonpareil, and an off-center vortex curling them" width="680">
</picture>

### Contents

- [The bath](#bath)
- [Dropping ink](#drop)
- [Raking tools](#rake)
- [Drawing and exporting](#draw)
- [Practical notes](#notes)

<a name="bath"></a>

#### The bath

```swift
var bath = Marbling()                 // spacing: 4 by default
var fine = Marbling(spacing: 2)      // smoother, heavier outlines
```

`Marbling` is a value type. Operations mutate it in place, so a copied bath is a snapshot, and you can rake that copy separately. `spacing` is the refinement grain. As a transform stretches an outline, its segments subdivide until none is longer than about that distance. The new points land exactly on the transformed curve. `inks` is the ordered stack, oldest first, and each `MarbledInk` in it carries a fillable `shape` and its `color`.

```swift
var bath = Marbling()
for i in 0 ..< 20 {
    bath.drop(at: center, radius: 200 - Double(i) * 9,
              color: i.isMultiple(of: 2) ? navy : cream)
}
bath.comb(through: center, direction: .unitY, spacing: 90, strength: 260)
drawMarbling(bath)
```

<a name="drop"></a>

#### Dropping ink

```swift
bath.drop(at: Vector2(400, 300), radius: 80, color: .indigo)
bath.drop(400, 300, radius: 80, color: .indigo)   // positional form
```

A drop pushes every floating point radially away from its center. A point at distance `d` lands at `√(d² + r²)`, which is the displacement that preserves the area of everything around the drop. Earlier regions therefore thin into crescents, but they never vanish. Concentric drops of alternating color build the bull's-eye that every classic pattern starts from, and scattered drops make "stones."

```swift
bath.add(shape, color: .black)      // float an arbitrary outline as ink
bath.add(contour, color: .black)
```

`add` floats any outline onto the bath as it is, because only a drop displaces what is already floating. Every later tool then rakes that outline like any other ink. The classic move is to float [text outlines](../Drawing/Text.md) and comb them, and a `Shape` keeps its holes, so glyph counters survive.

<a name="rake"></a>

#### Raking tools

```swift
bath.tine(through: point, direction: pull, strength: 120, falloff: 48)
bath.comb(through: point, direction: .unitY, spacing: 110, strength: 260, falloff: 30)
bath.tine(around: center, radius: 200, strength: 300, falloff: 48)
bath.swirl(at: center, strength: 400, falloff: 96)
```

All four tools share one falloff law. A point at distance `d` from the tool moves by `strength · 2^(−d/falloff)`, always parallel to the tool's motion. `strength` is the full displacement at the tool itself. For the two rotational tools that displacement is an arc length, so a negative value reverses the spin. `falloff` is the distance at which the pull halves.

- **`tine(through:direction:)`** pulls one stylus along a line. This is the stroke that drags a bull's-eye into a heart.
- **`comb(through:direction:spacing:)`** pulls a whole row of parallel teeth, one every `spacing`. Rows of drops under a comb become the feathered *nonpareil*. Keep `falloff` well under the tooth spacing, or the teeth blur into one broad shear.
- **`tine(around:radius:)`** drags the stylus around a circle, so everything near the track slides along it.
- **`swirl(at:)`** stirs a vortex. The middle turns hardest and the spin falls off outward, which gives the tight curl of French-curl papers.

<a name="draw"></a>

#### Drawing and exporting

```swift
noStroke()
drawMarbling(bath)          // fills each ink in its own color, oldest first
```

`drawMarbling` honors the current stroke state on every outline, and it restores the fill afterward. Leave the stroke off for flat marbled paper, because a hairline stroke reads as engraved veining. For anything else, walk `bath.inks` yourself. Each ink's `shape` fills, strokes, clips, and exports like any other shape. The whole bath is vector geometry, so `--export-svg` and `--export-pdf` write true paths. A [hatching pass](../Output/Export.md#hatching-solid-fills-for-a-pen-plotter) then turns the fills into plotter line work.

<a name="notes"></a>

#### Practical notes

- **Deterministic by construction.** There is no randomness inside the bath, so the same operations always marble the same paper. Randomize drop positions and colors with the sketch's seeded [`random`](Random.md), and the whole sheet then reproduces from its seed.
- **Setup-shaped work.** Outlines gain points as they stretch, so the cost grows with the number of operations. Compose the bath in `setup()`, or once per interaction, and redraw the result you kept. Don't rebuild the bath every frame.
- **Order is the picture.** Later drops sit above earlier ones. `drawMarbling` paints oldest first, so the stack reads in the order you poured it. A drop in the paper color carves negative space.
- **`spacing` is the fidelity parameter.** Halving it roughly doubles the number of points, and the default holds up over a full-canvas sheet. For long runs of one comb after another, try `spacing: 6` while you sketch, then tighten it for the final export.
- **True ink dispersion is a different tool.** The bath is the classical *kinematic* model, which transforms outlines. Bleeding, granulation, and wet-into-wet diffusion need a simulation, so they are outside what marbling does.

---

Related: [`Watercolor`](Watercolor.md) (the painterly sibling), [`Text`](../Drawing/Text.md#outlinefont) (outlines to float), [`Export`](../Output/Export.md) (SVG/PDF and hatching), [`Variations`](../Core/Variations.md) (seeds that name a sheet).
