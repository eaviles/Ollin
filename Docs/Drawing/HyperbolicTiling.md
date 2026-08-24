#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Hyperbolic tiling`</sup>

---

## Hyperbolic tiling

Regular tilings of the hyperbolic plane, seen through the Poincaré disk: identical p-sided tiles meeting q around every vertex, repeating forever into a circular horizon they never reach.

On flat paper only three regular tilings exist (triangles, squares, hexagons), because the corners meeting at a vertex must sum to a full turn. Hyperbolic space has room for every pair beyond them: whenever `(sides - 2) * (meeting - 2) > 4` the tiling exists, and the disk shows all of it at once. Every tile is the same true size; the disk only *draws* them smaller as they approach the rim.

It is geometry, not draw calls: the call hands back typed tiles whose outlines feed the same drawing, boolean, hatching, and SVG paths as everything else, so the lace is plotter-ready line work too. Generation is deterministic, with no randomness and no time.

<img src="../../Guide/Images/07-Tiles/HyperbolicDisks.jpg" alt="Two Poincaré disks side by side. Left: pentagons meeting four to a corner in a crisp ivory-and-indigo curved checkerboard. Right: heptagons meeting three to a corner, ivory at the center deepening to indigo as the tiles shrink toward the circular horizon" width="680">

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

The tiles of the regular hyperbolic tiling: `sides`-sided tiles meeting `meeting` to a vertex, the Schläfli symbol {p,q}. They draw in the disk inscribed in `bounds`, which defaults to the whole canvas. The pair must satisfy `(sides - 2) * (meeting - 2) > 4`; {7,3}, {3,7}, {5,4}, {4,5}, {6,4}, and {8,3} are all classics.

The construction places the central tile exactly, from the hyperbolic triangle it decomposes into. Then it reflects that tile across its own edges, and keeps reflecting the reflections. Each edge lies on a circle that meets the horizon at right angles, and the reflection is inversion in that circle. Tiles whose longest edge would draw shorter than `minEdge` canvas units are pruned. That prune is what bounds the otherwise endless tiling.

Each `HyperbolicTiling.Tile` carries:

| Member | Meaning |
| --- | --- |
| `points: [Vector2]` | The outline, curved geodesic edges already flattened to short segments. |
| `center: Vector2` | The tile's hyperbolic center. |
| `depth: Int` | Edge crossings from the central tile: 0 there, 1 for its neighbors, and so on. |
| `parity: Int` | 0 or 1, flipping across every shared edge. The two-coloring hook. |
| `shape` / `contour` | Fillable `Shape` / closed `Contour`. |

```swift
for tile in hyperbolicTiling(sides: 5, meeting: 4) {
    fill(tile.parity == 0 ? .ivory : .indigo)
    drawShape(tile.shape)
}
```

The full typed form is `HyperbolicTiling.tiles(sides:meeting:in:viewpoint:minEdge:maxDepth:)`, with `maxDepth` a backstop on the reflection depth.

<a name="coloring"></a>

#### Coloring

`parity` alternates across every shared edge. When `meeting` is even, the two colors close consistently around every vertex and the whole tiling checkerboards perfectly. When `meeting` is odd a perfect two-coloring cannot exist, because an odd ring of tiles surrounds each vertex. The coloring still alternates, resolved deterministically where the colors meet, but `depth` makes a better hook there:

```swift
for tile in hyperbolicTiling(sides: 7, meeting: 3) {
    fill(Color.mix(.ivory, .teal, t: min(Double(tile.depth) / 6, 1)))
    drawShape(tile.shape)
}
```

For bare line work, stroke each tile's outline (or plot it: the flattened points go straight to the SVG path):

```swift
noFill()
stroke(.black)
for tile in hyperbolicTiling(sides: 4, meeting: 5, minEdge: 2) {
    drawPolyline(tile.points, closed: true)
}
```

<a name="panning"></a>

#### Panning across the tiling

`viewpoint` is the point of the hyperbolic plane (in disk units, length below 1) brought to the middle of the disk. Animating it pans the camera across the tiling while the horizon stays put. Tiles grow as they approach the middle and shrink away again, and the picture never runs out.

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

A closed viewpoint circuit loops perfectly. Because the pan is a rigid motion of the hyperbolic plane, the number of visible tiles stays roughly constant however far it travels.

See the example: `swift run --package-path Examples Example-Patterns-HyperbolicTiling`. The periodic tilings live on the [tiling & layout](./Tiling.md) page and the tilings that never repeat on the [aperiodic tilings](./AperiodicTilings.md) page.
