#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Marbling`</sup>

---

## Marbling

Paper marbling in closed form. A **`Marbling`** bath holds colored ink regions as vector outlines; **`drop`** floats a new circle of ink and pushes everything already floating aside, and the raking tools (**`tine`**, **`comb`**, a circular tine, **`swirl`**) bend every region at once. Each operation is an exact point transform (the classic marbling equations: the area-preserving drop and the exponential-falloff stylus family), so regions deform without ever tearing or crossing, and the finished paper is ordinary geometry: fill it with `drawMarbling`, stroke the outlines, or send them to [SVG/PDF export](../Output/Export.md) as plotter-ready paths.

```
   drop, drop, drop          comb down             swirl
        ____                 /\  /\  /\           @@@@@
      /  __  \               \ \/ \/ /           @ @@@ @
     |  (__)  |              /\  /\  /\          @ @ @ @
      \ ____ /               \ \/ \/ /           @ @@@ @
        bull's-eye            nonpareil           French curl
```

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

`Marbling` is a value type: operations mutate it in place, and a copied bath is a snapshot you can keep raking separately. `spacing` is the refinement grain: as a transform stretches an outline, its segments subdivide until no longer than about this, with the new points landing exactly on the transformed curve. `inks` is the ordered stack, oldest first; each `MarbledInk` carries a fillable `shape` and its `color`.

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

A drop pushes every floating point radially away from its center: a point at distance `d` lands at `√(d² + r²)`, the displacement that preserves the area of everything around the drop, so earlier regions thin into crescents but never vanish. Concentric drops of alternating color build the bull's-eye that every classic pattern starts from; scattered drops make "stones."

```swift
bath.add(shape, color: .black)      // float an arbitrary outline as ink
bath.add(contour, color: .black)
```

`add` floats any outline onto the bath as-is (only drops displace); every later tool rakes it like any other ink. Floating [text outlines](../Drawing/Text.md) and combing them is the classic trick, and a `Shape` keeps its holes, so glyph counters survive.

<a name="rake"></a>

#### Raking tools

```swift
bath.tine(through: point, direction: pull, strength: 120, falloff: 48)
bath.comb(through: point, direction: .unitY, spacing: 110, strength: 260, falloff: 30)
bath.tine(around: center, radius: 200, strength: 300, falloff: 48)
bath.swirl(at: center, strength: 400, falloff: 96)
```

All four share one falloff law: a point at distance `d` from the tool moves by `strength · 2^(−d/falloff)`, always parallel to the tool's motion. `strength` is the full displacement at the tool itself (an arc length for the two rotational tools, so negative values reverse the spin); `falloff` is the distance at which the pull halves.

- **`tine(through:direction:)`** pulls one stylus along a line: the stroke that drags a bull's-eye into a heart.
- **`comb(through:direction:spacing:)`** pulls a whole row of parallel teeth, one every `spacing`: rows of drops under a comb become the feathered *nonpareil*. Keep `falloff` well under the tooth spacing or the teeth blur into one broad shear.
- **`tine(around:radius:)`** drags the stylus around a circle: everything near the track slides along it.
- **`swirl(at:)`** stirs a vortex: the middle whirls hardest and the spin dies off outward, the tight curl at the heart of French-curl papers.

<a name="draw"></a>

#### Drawing and exporting

```swift
noStroke()
drawMarbling(bath)          // fills each ink in its own color, oldest first
```

`drawMarbling` honors the current stroke state on every outline (leave it off for flat marbled paper; a hairline stroke reads as engraved veining) and restores the fill afterward. For anything custom, walk `bath.inks` yourself: each ink's `shape` fills, strokes, clips, and exports like any other. The whole bath is vector geometry, so `--export-svg` / `--export-pdf` write true paths and a [hatching pass](../Output/Export.md#hatching-solid-fills-for-a-pen-plotter) turns the fills into plotter line work.

<a name="notes"></a>

#### Practical notes

- **Deterministic by construction.** There is no randomness inside: the same operations always marble the same paper. Randomize drop positions and colors with the sketch's seeded [`random`](Random.md) and the whole sheet reproduces from its seed.
- **Setup-shaped work.** Outlines gain points as they stretch, so cost grows with the operation count. Compose the bath in `setup()` (or per interaction) and redraw the held result; don't rebuild it every frame.
- **Order is the picture.** Later drops sit above earlier ones, and `drawMarbling` paints oldest-first, so the stack reads exactly as poured. Paper-colored drops carve negative space.
- **`spacing` is the fidelity knob.** Halving it roughly doubles the points; the default holds up to a full-canvas sheet. For heavy comb-after-comb sequences, consider `spacing: 6` while sketching and tighten for the final export.
- **True ink dispersion is a different tool.** The bath is the classical *kinematic* model (transforms of outlines); bleeding, granulation, and wet-into-wet diffusion belong to simulation, not marbling.

---

Related: [`Watercolor`](Watercolor.md) (the painterly sibling), [`Text`](../Drawing/Text.md#outlinefont) (outlines to float), [`Export`](../Output/Export.md) (SVG/PDF and hatching), [`Variations`](../Core/Variations.md) (seeds that name a sheet).
