#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Matching`</sup>

---

## Matching

A `Matching` pairs two sets element by element at the least total cost: every element of the smaller set gets one partner in the other, no two share a partner, and the costs of the pairs add up to the smallest sum any such pairing can have. This is the assignment problem. With distance as the cost, a cloud of particles sent to the points of a shape this way travels the least in total, and no two of their paths cross. With a cost of your own, two palettes match color to color, or a set of pieces matches a set of holes by size.

### Contents

- [Quick start](#quick-start)
- [A cost of your own](#cost)
- [Reading the pairing](#reading)
- [Greedy, for comparison](#greedy)
- [Cost and size](#size)
- [Reference](#reference)

<a name="quick-start"></a>

### Quick start

```swift
var particles: [Vector2] = []
var targets: [Vector2] = []
var match = Matching.optimal([Vector2](), [Vector2]())

override func setup() {
    particles = (0 ..< 800).map { _ in randomVector(in: canvasRectangle) }
    targets = textToShapes("HELLO", at: center).flatMap { randomPoints(in: $0, count: 160) }
    match = Matching.optimal(particles, targets)      // the cost is the distance
}

override func draw() {
    background(.black)
    fill(.white)
    for pair in match.pairs {
        particles[pair.first] = particles[pair.first].lerp(to: targets[pair.second], 0.04)
        drawCircle(center: particles[pair.first], radius: 3)
    }
}
```

Each pair names an index into the first set and an index into the second. The sketch keeps the sets themselves, and the matching only says who goes with whom.

<a name="cost"></a>

### A cost of your own

The point forms use the distance. The general form takes any two arrays and a closure that prices one element against one of the other:

```swift
let swatches: [Color] = [.red, .orange, .yellow]
let wanted: [Color] = [.blue, .green, .gray]
let byLook = Matching.optimal(swatches, wanted) { $0.distance(to: $1) }

let pieces: [Double] = [12, 30, 7, 22]        // radii
let holes: [Double] = [8, 31, 11, 20, 28]
let bySize = Matching.optimal(pieces, holes) { abs($0 - $1) }
```

A cost that is infinite, or not a number, **forbids** the pair: those two are never paired. The matching then pairs as many elements as the allowed pairs permit, at the least total cost among those pairings, and an element with no allowed partner is left out, so `partner(of:)` answers nil for it. That is how a sketch keeps particles out of a region or colors out of a group with one line in the closure:

```swift
let dots: [Vector2] = []
let spots: [Vector2] = []
let keepLeft = Matching.optimal(dots, spots) { dot, spot in
    spot.x > width / 2 ? .infinity : dot.distance(to: spot)
}
```

A table of costs works too, one row per element of the first set and one column per element of the second: `Matching.optimal(costs:)`. A short row forbids the pairs past its end.

<a name="reading"></a>

### Reading the pairing

- `pairs` lists every pair made, ascending by `first`.
- `partner(of:)` answers the second set's index for an element of the first, or nil when it has none.
- `totalCost` is the sum over the pairs.
- `reversed()` is the same pairing read from the other side, so `partner(of:)` then answers for the second set's elements.

When the sets differ in size, every element of the smaller set is paired and the rest of the larger one is left out. Two hundred particles and fifty targets pair fifty particles; the other hundred and fifty answer nil to `partner(of:)` and are the sketch's to scatter, dim, or hold still.

<a name="greedy"></a>

### Greedy, for comparison

`Matching.greedy` pairs the sets by the rule a first draft usually writes: each element of the first set, in turn, takes the cheapest partner still free. It is fast and it is a proper pairing, and its total is often well above the least, because the first few choices take the partners the later ones needed. With distance as the cost its paths cross each other, and the flight of a cloud paired this way reads as a tangle where the optimal one reads as a single motion. The worked example switches between the two with one key so the difference can be watched.

<a name="size"></a>

### Cost and size

`optimal` finds the pairing exactly, by the shortest-augmenting-path method of Jonker and Volgenant. Its work grows with about the cube of the count, and it holds the cost of every pair in memory while it runs (the two counts multiplied, as numbers). In a release build a thousand on a side pairs in about sixty milliseconds, two thousand in a third of a second, and three thousand in under a second with seventy megabytes held for the table. Find the pairing once when the sets are set, not every frame: a cloud that gathers into a word matches once at the start of the flight and then moves along fixed roads.

Among pairings that share the least total, the one answered is fixed, so a seeded sketch reproduces.

<a name="reference"></a>

### Reference

| Finding one | Meaning |
| --- | --- |
| `Matching.optimal(_ first: [A], _ second: [B], cost: (A, B) -> Double)` | The pairing at the least total cost over any two sets. |
| `Matching.optimal(_ first: [Vector2], _ second: [Vector2])` | The same, with distance as the cost. |
| `Matching.optimal(_ first: [Vector3], _ second: [Vector3])` | The same in space. |
| `Matching.optimal(costs: [[Double]])` | The same over a table, one row per element of the first set. |
| `Matching.greedy(_ first: [A], _ second: [B], cost: (A, B) -> Double)` | Each element in turn takes the cheapest free partner. |
| `Matching.greedy(_ first: [Vector2], _ second: [Vector2])` | The greedy rule by distance. |

| Reading it | Meaning |
| --- | --- |
| `pairs: [Pair]` | Every pair made, ascending by `first`; a `Pair` holds `first` and `second`, and `Matching.Pair(first, second)` builds one. |
| `partner(of: Int) -> Int?` | The second set's index paired with an element of the first, or nil. |
| `totalCost: Double` | The sum of the costs over the pairs. |
| `firstCount: Int` / `secondCount: Int` | How many elements each set held. |
| `reversed() -> Matching` | The same pairing with the sets' roles swapped. |
| `Matching(pairs:totalCost:firstCount:secondCount:)` | A matching from pairs you already have. |

Runnable: [`Examples/Patterns/GatherIntoLetters`](../../Examples/Patterns/GatherIntoLetters/Sketch.swift), a cloud of dots flying from one word into the next along the roads the least total gives, with the greedy pairing a key away.

---

See also [`Spatial index`](./SpatialIndex.md) for the nearest-neighbor questions, which answer "who is close" rather than "who goes with whom", and [`Shape morphing`](./Morphing.md) for tweening one outline into another rather than one set of points into another.
