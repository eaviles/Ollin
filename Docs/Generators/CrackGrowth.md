#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Crack growth`</sup>

---

## Crack growth

**`CrackGrowth`** subdivides the plane the way glaze crackles. Straight cracks travel across the canvas, and every collision starts a new crack perpendicular to the one it hit. The rules are short. A crack advances until it reaches another crack's line or the edge of the canvas. There it stops, restarts perpendicular to a random point on the existing pattern, and adds one more crack. The result is a street map that keeps getting denser for as long as you let it run. The technique is the crack-subdivision algorithm of Jared Tarbell's *Substrate* (2003), implemented independently from the published descriptions.

Each crack also lays a translucent **wash** across the open space on one side of its line. That sand-painter shading is what gives the classic watercolor look. The helper emits geometry only, and you draw the marks yourself. The wash can therefore be inks on paper, glowing additive dust, or nothing at all.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/13-GrowingThings/CrackedCity-dark.jpg">
  <img src="../../Guide/Images/13-GrowingThings/CrackedCity.jpg" alt="Two panels: left, a vertical crack stopped on a horizontal line at an orange dot marked stops here, with an orange arrow setting out perpendicular from the vertical line; right, a plane subdivided into rectangular city blocks by fine dark cracks with faint colored washes beside them" width="680">
</picture>

### Contents

- [CrackGrowth](#stepper)
- [The marks and the wash](#marks)
- [Practical notes](#notes)

<a name="stepper"></a>

#### CrackGrowth

```swift
CrackGrowth(width: Double, height: Double,
            cracks: Int = 3, seedAngles: Int = 16,
            maxCracks: Int = 200, seed: UInt64 = 0)
```

`CrackGrowth` is a stateful stepper that you hold across frames. `cracks` sets how many start moving at once over a grid seeded with `seedAngles` phantom angles, and the population then grows to `maxCracks`. The same `seed` always grows the same pattern.

```swift
let field = CrackGrowth(width: 1080, height: 1080, seed: 7)

override func setup() { noClear() }

override func draw() {
    if frameCount == 1 { background(.white) }
    for mark in field.step(4) {
        fill(Color.black.withAlpha(0.33))
        drawPoint(mark.point)
    }
}
```

The canvas never clears, so each frame draws only that frame's marks and the picture builds up over time. `field.segments` returns every crack line so far as plain `(Vector2, Vector2)` segments, which are ready for [SVG export](../Output/Export.md) and the pen plotter.

<a name="marks"></a>

#### The marks and the wash

```swift
field.step()          // one tick; returns [Mark]
field.step(_ ticks:)  // several ticks, marks collected

CrackGrowth.grains(from: Vector2, to: Vector2,
                   gain: Double, count: Int = 64) -> [Grain]
```

Each `Mark` carries the crack's index, the new `point` on its line, and the `washExtent` where the open space ends. It also carries a `gain` in `0...1` that drifts slowly for each crack. The index is a stable palette key. `grains` lays the classic wash along that span. It returns `count` translucent grains, crowded toward the crack by a doubled sine ease, with alpha fading outward from `0.1`.

```swift
for mark in field.step(4) {
    let ink = inks[mark.crack % inks.count]
    for grain in CrackGrowth.grains(from: mark.point, to: mark.washExtent,
                                    gain: mark.gain) {
        fill(ink.withAlpha(grain.alpha))
        drawPoint(grain.position)
    }
}
```

<a name="notes"></a>

#### Practical notes

- **Accumulate, don't redraw.** The look comes from thousands of faint marks piling up. Call `noClear()` and draw the `background` once, which is the whole recipe. See `Examples/Patterns/Cracks`.
- **The wash varies on its own.** `gain` takes a random walk for each crack. The shading swells and thins along a line, with no styling work from you.
- **One ink per crack reads best.** `mark.crack` stays the same for the crack's whole life, including its restarts. It therefore maps cleanly onto a palette.
- **`maxCracks` controls the density.** The population only grows. Two hundred cracks fill a canvas in about a minute, and forty keep it sparse and architectural.
- **Plotter output is the segments, not the marks.** `field.segments` gives you the street plan as clean line work. The wash is a raster effect, so leave it out of the vector layer.

---

Related: [`Single line`](./SingleLine.md) and [`Spanning tree`](./SpanningTree.md) (the other line-work generators), [`Walks`](./Walks.md), and [`Export`](../Output/Export.md) (SVG and the plotter path).
