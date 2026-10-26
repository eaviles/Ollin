#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Bounds index`</sup>

---

## Bounds index

A `BoundsIndex` answers three questions about a set of rectangles without testing every one: which boxes hold a point, which boxes overlap a rectangle, and which boxes overlap each other. Where a [`SpatialIndex`](./SpatialIndex.md) holds points, this holds extents. Hand it the bounds of a thousand shapes and picking the one under the pointer reads a few boxes rather than a thousand. Hand it every outline's box and the pairs that could collide come back before any outline is tested against another. Hand it the pieces already placed and a packing asks whether a new one fits.

Every answer is an **index into `boxes`**. Your sketch keeps its own payload in its own array (the shape, its color, its velocity) and reads it back with the same index.

### Contents

- [Quick start](#quick-start)
- [Picking what is under the pointer](#picking)
- [The broad phase: every overlapping pair](#pairs)
- [Boxes that move](#refit)
- [Exactness](#exactness)
- [Reference](#reference)

<a name="quick-start"></a>

### Quick start

```swift
var shapes: [Shape] = []
var boxes = BoundsIndex([])

override func setup() {
    shapes = (0 ..< 2000).map { _ in
        Shape(contours: [Circle(center: randomVector(in: canvasRectangle), radius: random(6, 30)).contour])
    }
    boxes = BoundsIndex(shapes.compactMap(\.bounds))
}

override func draw() {
    background(.black)
    fill(.gray)
    for shape in shapes { drawShape(shape) }

    // The shapes whose box holds the mouse, brightest last.
    fill(.orange)
    for i in boxes.indices(containing: mouse) { drawShape(shapes[i]) }
}
```

Building the index costs one pass over the boxes plus a sort at every split, so it is normal to build it fresh when the boxes change. Do not build it inside the loop that queries it.

<a name="picking"></a>

### Picking what is under the pointer

`indices(containing:)` answers ascending by index, and a sketch draws in index order, so the **last** index is the shape on top:

```swift
var shapes: [Shape] = []
var boxes = BoundsIndex([])

override func draw() {
    if let top = boxes.indices(containing: mouse).last {
        stroke(.white)
        noFill()
        drawShape(shapes[top])
    }
}
```

A box is a coarse test. A circle's box is held by the mouse at its corners too, so when the exact outline matters, ask the few candidates the index returns: `shapes[i].contains(mouse)` runs on a handful rather than on every shape.

`indices(overlapping:)` is the same question for a rectangle, which is what a marquee selection or a viewport asks: everything the dragged box touches, boxes that only touch it included.

<a name="pairs"></a>

### The broad phase: every overlapping pair

`overlappingPairs()` returns every pair of boxes in the set that overlap, each once, with the lower index first, sorted by the first index and then the second. It walks the tree against itself, so the pairs come back in far fewer tests than every box against every other.

```swift
override func draw() {
    let pieces: [Shape] = []            // the shapes the sketch keeps
    let boxes = BoundsIndex(pieces.compactMap(\.bounds))
    for pair in boxes.overlappingPairs() {
        // Only these pairs can really touch. Test the outlines now.
        let shared = pieces[pair.first].intersection(pieces[pair.second])
        if shared.area > 0 { drawShape(shared) }
    }
}
```

A `Shape` with no outline has no `bounds`, so `compactMap` drops it; when a set can hold such shapes, keep the boxes and the shapes in step yourself.

Two sets at once, a flock against the obstacles or the ink against the paper's holes, is `overlappingPairs(with:)`: `first` indexes this index's boxes and `second` the other's.

<a name="refit"></a>

### Boxes that move

When the boxes drift a little each frame without being reordered, keep the index and refit it:

```swift
var pieces: [Shape] = []
var boxes = BoundsIndex([])

override func draw() {
    boxes.refit(to: pieces.compactMap(\.bounds))
}
```

The tree keeps its shape and recomputes every node's box from the leaves up, one pass rather than a build. The new array has to hold the same count in the same order: box `i` is still the `i`-th box, only placed elsewhere. Boxes that have wandered far from where the tree was built still answer exactly, only more slowly, because the nodes' boxes grow to hold them. Rebuild when the set has been reshuffled. A refit with a different count rebuilds on its own.

<a name="exactness"></a>

### Exactness

The index is only a faster way to ask a question with one right answer, so every answer equals what a loop over every box would find:

- The boundary counts as inside, matching `Rectangle.contains(_:)`: a point on an edge is held by that box.
- Touching counts as overlapping, matching `Rectangle.intersects(_:)`: two boxes that share an edge or a corner are a pair.
- Results come back sorted, ascending by index, and a pair lists its lower index first. The two closure forms walk in the index's own fixed order, which reproduces from run to run.

<a name="reference"></a>

### Reference

| Building | Meaning |
| --- | --- |
| `BoundsIndex(_ boxes: [Rectangle])` | An index over a set of boxes. |
| `refit(to: [Rectangle])` | The same boxes moved, same count and order: the tree keeps its shape and recomputes its boxes. |
| `boxes: [Rectangle]` / `count: Int` / `isEmpty: Bool` | What the index holds. |
| `bounds: Rectangle?` | The one rectangle around every box, or nil when empty. |

| Query | Meaning |
| --- | --- |
| `indices(containing: Vector2) -> [Int]` | Every box that holds the point, ascending by index. |
| `indices(overlapping: Rectangle) -> [Int]` | Every box that overlaps the rectangle, ascending by index. |
| `forEachIndex(containing: Vector2, _ body: (Int) -> Void)` | The same walk with no array built. |
| `forEachIndex(overlapping: Rectangle, _ body: (Int) -> Void)` | The same walk with no array built. |
| `overlappingPairs() -> [Pair]` | Every overlapping pair within the set, lower index first, sorted. |
| `overlappingPairs(with: BoundsIndex) -> [Pair]` | Every overlapping pair across two sets, `first` here and `second` there. |

`BoundsIndex.Pair` holds `first` and `second`, and `BoundsIndex.Pair(first, second)` builds one, for a test that wants to name a pair it expects. The matching helpers on `Rectangle` are `intersects(_:)`, `intersection(_:)`, and `union(_:)`, on the [Geometry](./Geometry.md#rectangle) page.

---

See also [`Spatial index`](./SpatialIndex.md) for the same idea over points, on the canvas and in space, and [`Geometry`](./Geometry.md) for `Rectangle` and the shapes whose `bounds` feed this index.
