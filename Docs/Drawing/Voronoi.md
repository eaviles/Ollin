#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Voronoi & Delaunay`</sup>

---

## Voronoi & Delaunay

Tessellation turns a set of points into vector geometry. A **Delaunay triangulation** connects the points into well-shaped (un-slivery) triangles. Its dual, a **Voronoi diagram**, partitions the canvas into one convex cell per point, where a cell is every place closer to its point than to any other, the "stochastic crystallization" look. Both produce ordinary `Shape`s, so the cells and triangles fill, stroke, offset, hatch, and export like anything you draw by hand.

Everything here is driven by the seedable [`random`](../Generators/Random.md)/[`noise`](../Generators/Noise.md) helpers, so the same seed always yields the same tessellation.

<img src="../../Guide/Images/15-ShapesAsMaterial/Duals.jpg" alt="Two panels over the same orange points: on the left Voronoi cells partitioning the panel into convex territories, on the right the Delaunay triangulation joining each point to its natural neighbors" width="680">

### Contents

- [Quick start](#quick-start)
- [Voronoi](#voronoi)
- [Lloyd relaxation](#lloyd)
- [Power diagrams: cells with weights](#power)
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

`canvasRectangle` is the whole canvas as a `Rectangle`, the default clip region. `voronoi(_:in:)` and the value types below are the typed core, and the `draw*` calls are sugar over them.

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
| `relaxed(iterations:) -> [Vector2]` | Lloyd relaxation (see below). |

Because cells are 1:1 with sites, you can carry data alongside the sites and look it up by index while drawing:

```swift
let cells = voronoi(sites).cells
for (i, cell) in cells.enumerated() {
    fill(siteColors[i])
    drawShape(cell)
}
```

Every cell is **clipped to `bounds`**, so the cells at the edge of the field get finite shapes rather than running off to infinity. Sites are taken exactly as given (no clustering), so keep them inside `bounds` for cells that cover the canvas.

To draw all cells in the current `fill`/`stroke` in one call:

```swift
fill(.white); stroke(.black)
drawVoronoi(sites)            // or drawVoronoi(sites, in: region)
```

<a name="lloyd"></a>

### Lloyd relaxation

Raw random sites clump and leave gaps. **Lloyd's algorithm** evens them out by moving each site to its cell's centroid and re-tessellating, repeatedly, converging toward a calm, organic ("centroidal") spacing.

```swift
let scattered = (0..<120).map { _ in randomVector(in: canvasRectangle) }
let even = lloyd(scattered, iterations: 6)   // sugar
let even = voronoi(scattered).relaxed(iterations: 6)   // equivalent
```

`lloyd(_:in:iterations:)` returns the relaxed sites, so feed them into `voronoi(...)`, keep iterating, or animate them. A few iterations is usually enough, and more keeps smoothing toward a honeycomb.

<a name="power"></a>

### Power diagrams: cells with weights

```swift
powerDiagram(sites: [WeightedSite], in bounds: Rectangle? = nil) -> PowerDiagram
powerDiagram(of circles: [Circle], in bounds: Rectangle? = nil) -> PowerDiagram
drawPowerDiagram(of circles: [Circle], in bounds: Rectangle? = nil)

struct WeightedSite {
    init(_ point: Vector2, weight: Double = 0)
    init(_ circle: Circle)                    // weight = radius squared
    func power(to point: Vector2) -> Double   // squared distance, less the weight
}

struct PowerDiagram {
    let sites: [WeightedSite]
    let cells: [Shape]                        // one per site, empty when it lost
    func site(owning point: Vector2) -> Int?
}
```

A Voronoi cell holds every place closer to its site than to any other. A **power** cell holds every place whose *power* is least, where power is the squared distance less a weight the site carries. That single change gives every site a dial, and it is the diagram to reach for when the things being divided have sizes.

Two properties survive the change and one is new. The boundary between two cells is still a straight line, so the cells are still convex polygons and they still tile the region exactly. What is new is that **a site can lose everything**: a small circle sitting inside a large one gets no cell at all, which a plain Voronoi diagram can never do. Its `cells` entry is an empty `Shape`, and drawing it draws nothing.

The weight is not a radius and not an importance, and only the *differences* between weights matter. Adding the same amount to every weight leaves the diagram exactly where it was.

**Weighting a circle by the square of its radius is the case worth knowing.** The power of a point on the circle is then zero, so a circle that touches no other lies entirely inside its own cell. That is what makes the diagram the right partition for a set of circles of different sizes: cell boundaries fall where two circles would meet if they grew, rather than halfway between their centers.

<img src="../../Guide/Images/15-ShapesAsMaterial/WeightedTerritories.jpg" alt="Two panels over the same five circles, one large and four small. On the left the cell boundaries fall halfway between the centers and slice through the large circle. On the right each site carries its size as a weight, and every circle sits whole inside its own cell" width="680">

```swift
let circles = packCircles(count: 80, minRadius: 8, maxRadius: 60)
let diagram = powerDiagram(of: circles)
for (index, cell) in diagram.cells.enumerated() {
    fill(palette[index % palette.count])
    drawShape(cell)
}
```

Every cell is cut out with one half-plane per other site, so the cost grows with the square of the site count. A few hundred sites is comfortable, a few thousand is not. `site(owning:)` answers from the sites themselves rather than from the polygons, so it is exact and works outside `bounds` too.

<a name="delaunay"></a>

### Delaunay

`delaunay(_ points:)` (or `Delaunay(points)`) returns the triangulation, the well-shaped triangle mesh through the points, and what the Voronoi diagram is the dual of.

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
| `indices: [Int]` | Triangle corners as a flat list of indices into `points`, three per triangle, in a canonical deterministic order (each triple leads with its smallest index; the list is sorted). |
| `neighbors(of i: Int) -> [Int]` | The points sharing an edge with point `i`. |
| `voronoi(bounds:) -> Voronoi` | The dual Voronoi diagram, clipped to `bounds`. |

`drawDelaunay(points)` draws the mesh in the current `fill`/`stroke` (`noFill()` for a wireframe).

Computed with the Bowyer-Watson incremental algorithm. Exactly coincident points are skipped during insertion (they don't corrupt the mesh), and fully collinear inputs simply produce no triangles. It's tuned for creative-coding scale, hundreds to a few thousand points, recomputed every frame.

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
