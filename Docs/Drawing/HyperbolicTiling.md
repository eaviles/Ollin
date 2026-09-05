#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Hyperbolic tiling`</sup>

---

## Hyperbolic tiling

Regular tilings of the hyperbolic plane, drawn in the Poincaré disk. Identical p-sided tiles meet q to a vertex, and the pattern repeats forever toward a circular horizon it never reaches.

On flat paper only three regular tilings exist: triangles, squares, and hexagons. That limit comes from the corners meeting at a vertex, which must add up to a full turn. Hyperbolic space has room for every pair beyond those three, so the tiling exists whenever `(sides - 2) * (meeting - 2) > 4`, and the disk shows all of it at once. Every tile is the same true size, and only the drawing makes them smaller as they approach the rim.

The call returns geometry, not draw calls. You get typed tiles whose outlines feed the same drawing, boolean, hatching, and SVG paths as everything else. That makes the pattern plotter-ready line work too. Generation is deterministic, with no randomness and no use of time.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/07-Tiles/HyperbolicDisks-dark.jpg">
  <img src="../../Guide/Images/07-Tiles/HyperbolicDisks.jpg" alt="Two Poincaré disks side by side. Left: pentagons meeting four to a corner in a crisp ivory-and-indigo curved checkerboard. Right: heptagons meeting three to a corner, ivory at the center deepening to indigo as the tiles shrink toward the circular horizon" width="680">
</picture>

### Contents

- [hyperbolicTiling / HyperbolicTiling](#hyperbolicTiling)
- [Coloring](#coloring)
- [Panning across the tiling](#panning)

<a name="hyperbolicTiling"></a>

#### hyperbolicTiling / HyperbolicTiling

```swift
hyperbolicTiling(sides: Int = 7,
                 meeting: Int = 3,
                 in bounds: Rectangle? = nil,
                 viewpoint: Vector2 = Vector2(0, 0),
                 minEdge: Double = 3) -> [HyperbolicTiling.Tile]
```

Returns the tiles of the regular hyperbolic tiling, with `sides`-sided tiles meeting `meeting` to a vertex. That pair is the Schläfli symbol {p,q}. The tiles draw in the disk inscribed in `bounds`, which defaults to the whole canvas. The pair must satisfy `(sides - 2) * (meeting - 2) > 4`. The classic pairs are {7,3}, {3,7}, {5,4}, {4,5}, {6,4}, and {8,3}.

The construction places the central tile exactly, working from the hyperbolic triangle it decomposes into. It then reflects that tile across its own edges, and keeps reflecting the reflections. Each edge lies on a circle that meets the horizon at right angles, so the reflection is an inversion in that circle. Tiles whose longest edge would draw shorter than `minEdge` canvas units are dropped, and that is what bounds the otherwise endless tiling.

Each `HyperbolicTiling.Tile` carries:

| Member | Meaning |
| --- | --- |
| `points: [Vector2]` | The outline. Its curved geodesic edges are already flattened to short segments. |
| `center: Vector2` | The tile's hyperbolic center. |
| `depth: Int` | Edge crossings from the central tile. It is 0 there, 1 for its neighbors, and so on. |
| `parity: Int` | 0 or 1, flipping across every shared edge. Use it to two-color the tiling. |
| `shape` / `contour` | Fillable `Shape` / closed `Contour`. |

```swift
for tile in hyperbolicTiling(sides: 5, meeting: 4) {
    fill(tile.parity == 0 ? .ivory : .indigo)
    drawShape(tile.shape)
}
```

The full typed form is `HyperbolicTiling.tiles(sides:meeting:in:viewpoint:minEdge:maxDepth:)`, where `maxDepth` puts a second limit on the reflection depth.

<a name="coloring"></a>

#### Coloring

`parity` alternates across every shared edge. When `meeting` is even, the two colors close consistently around every vertex, so the whole tiling checkerboards perfectly. When `meeting` is odd, a perfect two-coloring cannot exist, because an odd ring of tiles surrounds each vertex. The coloring still alternates, and it resolves deterministically where the colors meet. For an odd `meeting`, `depth` is the better value to color by:

```swift
for tile in hyperbolicTiling(sides: 7, meeting: 3) {
    fill(Color.mix(.ivory, .teal, min(Double(tile.depth) / 6, 1)))
    drawShape(tile.shape)
}
```

For plain line work, stroke each tile's outline. The flattened points also go straight to the SVG path, so you can plot the result:

```swift
noFill()
stroke(.black)
for tile in hyperbolicTiling(sides: 4, meeting: 5, minEdge: 2) {
    drawPolyline(tile.points, closed: true)
}
```

<a name="panning"></a>

#### Panning across the tiling

`viewpoint` is the point of the hyperbolic plane that is brought to the middle of the disk. You give it in disk units, so its length must stay below 1. Animating it pans the camera across the tiling while the horizon stays put. Tiles grow as they approach the middle and shrink again as they move away, and the picture never runs out.

```swift
override func draw() {
    background(.white)
    let t = loopProgress(over: 24) * 2 * .pi
    let viewpoint = Vector2(cos(t), sin(t)) * 0.32
    for tile in hyperbolicTiling(sides: 5, meeting: 4, viewpoint: viewpoint) {
        fill(tile.parity == 0 ? .ivory : .indigo)
        drawShape(tile.shape)
    }
}
```

A closed circuit of viewpoints loops perfectly. The pan is a rigid motion of the hyperbolic plane, so the number of visible tiles stays roughly constant however far it travels.

Run the example with `swift run --package-path Examples Example-Patterns-HyperbolicTiling`. The periodic tilings are on the [tiling & layout](./Tiling.md) page, and the tilings that never repeat are on the [aperiodic tilings](./AperiodicTilings.md) page.
