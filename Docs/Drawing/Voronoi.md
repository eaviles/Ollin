#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Voronoi & Delaunay`</sup>

---

## Voronoi & Delaunay

Tessellation: turn a set of points into vector geometry. A **Delaunay triangulation** connects the points into well-shaped (un-slivery) triangles; its dual, a **Voronoi diagram**, partitions the canvas into one convex cell per point, where a cell is every place closer to its point than to any other — the "stochastic crystallization" look. Both produce ordinary `Shape`s, so the cells and triangles fill, stroke, offset, hatch, and export like anything you draw by hand.

Everything here is driven by the seedable [`random`](../Generators/Random.md)/[`noise`](../Generators/Noise.md) helpers, so the same seed always yields the same tessellation.

### Contents

- [Quick start](#quick-start)
- [Voronoi](#voronoi)
- [Lloyd relaxation](#lloyd)
- [Delaunay](#delaunay)
- [Triangle](#triangle)

<a name="quick-start"></a>

### Quick start

Scatter some sites and draw their Voronoi cells, each in its own color:

```swift
override func draw() {
    background(.black)
    seed(7)
    let sites = (0..<120).map { _ in randomVector(in: canvasRectangle) }

    for (i, cell) in voronoi(sites).cells.enumerated() {
        fill(Colormap.viridis.color(at: Double(i) / 120))
        stroke(.black); strokeWeight(1.5)
        drawShape(cell)
    }
}
```

`canvasRectangle` is the whole canvas as a `Rectangle` — the default clip region. `voronoi(_:in:)` and the value types below are the typed core; the `draw*` calls are sugar over them.

<a name="voronoi"></a>

### Voronoi

`voronoi(_ sites:in:)` returns a `Voronoi` value. Build one directly with `Voronoi(sites:bounds:)` when you're outside a `Sketch`.

```swift
let v = voronoi(sites)              // clipped to the canvas
let v = voronoi(sites, in: region) // clipped to a Rectangle you choose
```

| Member | Meaning |
| --- | --- |
| `cells: [Shape]` | One convex cell per site, **in the same order as `sites`**. Each is a closed `Shape`. |
| `cell(_ i: Int) -> Shape` | The cell for site `i`. |
| `sites: [Vector2]` | The sites, in input order. |
| `bounds: Rectangle` | The rectangle every cell is clipped to. |
| `centroid(_ i: Int) -> Vector2` | The area-weighted centroid of cell `i` (where Lloyd relaxation would move the site). |
| `relaxed(iterations:) -> [Vector2]` | Lloyd relaxation — see below. |

Because cells are 1:1 with sites, you can carry data alongside the sites and look it up by index while drawing:

```swift
let cells = voronoi(sites).cells
for (i, cell) in cells.enumerated() {
    fill(siteColors[i])
    drawShape(cell)
}
```

Every cell is **clipped to `bounds`**, so the cells at the edge of the field get finite shapes rather than running off to infinity. Sites are taken exactly as given (no clustering); keep them inside `bounds` for cells that cover the canvas.

To draw all cells in the current `fill`/`stroke` in one call:

```swift
fill(.white); stroke(.black)
drawVoronoi(sites)            // or drawVoronoi(sites, in: region)
```

<a name="lloyd"></a>

### Lloyd relaxation

Raw random sites clump and leave gaps. **Lloyd's algorithm** evens them out: move each site to its cell's centroid and re-tessellate, repeatedly, converging toward a calm, organic ("centroidal") spacing.

```swift
let scattered = (0..<120).map { _ in randomVector(in: canvasRectangle) }
let even = lloyd(scattered, iterations: 6)   // sugar
let even = voronoi(scattered).relaxed(iterations: 6)   // equivalent
```

`lloyd(_:in:iterations:)` returns the relaxed sites — feed them into `voronoi(...)`, keep iterating, or animate them. A few iterations is usually enough; more keeps smoothing toward a honeycomb.

<a name="delaunay"></a>

### Delaunay

`delaunay(_ points:)` (or `Delaunay(points)`) returns the triangulation — the well-shaped triangle mesh through the points, and what the Voronoi diagram is the dual of.

```swift
let mesh = delaunay(points)
noFill(); stroke(.black)
for t in mesh.triangles { drawShape(t.shape) }   // a wireframe mesh

let cells = mesh.voronoi(bounds: canvasRectangle).cells   // the dual diagram
```

| Member | Meaning |
| --- | --- |
| `points: [Vector2]` | The input points, in order. |
| `triangles: [Triangle]` | The triangles (see [`Triangle`](#triangle)). |
| `triangleShapes: [Shape]` | Each triangle as a fillable `Shape`. |
| `indices: [Int]` | Triangle corners as a flat list of indices into `points` — three per triangle. |
| `neighbors(of i: Int) -> [Int]` | The points sharing an edge with point `i`. |
| `voronoi(bounds:) -> Voronoi` | The dual Voronoi diagram, clipped to `bounds`. |

`drawDelaunay(points)` draws the mesh in the current `fill`/`stroke` (`noFill()` for a wireframe).

Computed with the Bowyer-Watson incremental algorithm. Exactly coincident points are skipped during insertion (they don't corrupt the mesh); fully collinear inputs simply produce no triangles. It's tuned for creative-coding scale — hundreds to a few thousand points, recomputed every frame.

<a name="triangle"></a>

### Triangle

The unit a `Delaunay` is made of, useful on its own.

| Member | Meaning |
| --- | --- |
| `a`, `b`, `c: Vector2` | The three corners. |
| `points: [Vector2]` | The corners, in order. |
| `centroid: Vector2` | The average of the corners. |
| `area: Double` | Unsigned area. |
| `circumcircle: Circle` | The circle through all three corners; its center is a Voronoi vertex. |
| `circumcenter: Vector2` | The center of the `circumcircle`. |
| `contour: Contour` / `shape: Shape` | The triangle as fillable geometry. |

```swift
let t = Triangle(a, b, c)
fill(.clear); stroke(.gray); drawCircle(t.circumcircle)   // the circumcircle
fill(.black); drawShape(t.shape)
```

---

See also [`Geometry`](../Drawing/Geometry.md) for the `Shape`/`Contour` types these produce (and the shape booleans and offsetting that consume them), and [`Random`](../Generators/Random.md)/[`Noise`](../Generators/Noise.md) for seeding the sites.
