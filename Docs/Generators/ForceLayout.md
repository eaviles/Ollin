#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Force-directed layout`</sup>

---

## Force-directed layout

**`ForceLayout`** lays out a graph with no coordinates ever given. Every node pushes every other node apart, every edge pulls its two ends together, and the graph untangles itself into an even, readable web. It is the standard spring-embedder layout. In a sketch it doubles as motion. Step it each frame and the untangling *is* the animation. The web reflows live as nodes join or a hand drags one.

```
  random start                 settling                    settled

   o  o    o                  o   o                      o---o
    \ |  / |                  |\ /                      /     \
   o--o-o  o        →       o-o-o---o         →        o--o    o
    huddle of                edges even out,           every edge near
    tangled edges            crossings resolve         one length, no pile-ups
```

All you provide is a node count and index pairs for the edges. Positions start at seeded random spots and improve step by step. Each step every node moves a little along its summed force, capped by a temperature that cools linearly to zero. The layout therefore swings boldly at first, refines gently, and then freezes. It is deterministic throughout, so the same seed replays the same run.

### Contents

- [ForceLayout](#build)
- [Stepping, settling, and reheating](#step)
- [Growing and interacting](#interact)
- [drawGraph](#draw)
- [Practical notes](#notes)

<a name="build"></a>

#### ForceLayout

```swift
ForceLayout(count: Int, edges: [(Int, Int)] = [], in bounds: Rectangle,
            idealDistance: Double? = nil, seed: UInt64 = 1)
ForceLayout(positions: [Vector2], edges: [(Int, Int)] = [], in bounds: Rectangle,
            idealDistance: Double? = nil)
```

A layout of `count` nodes joined by `edges`, placed at seeded random positions inside `bounds`. You can pass explicit `positions` instead, from a circle, a grid, or the output of another pass. Nodes clamp to `bounds` every step, so the graph always stays drawable.

```swift
let ring = (0 ..< 24).map { ($0, ($0 + 1) % 24) }
let layout = ForceLayout(count: 24, edges: ring, in: bounds, seed: 7)
```

The edges can come from anywhere: a hand-written list, a [Delaunay triangulation](../Drawing/Voronoi.md), a [maze](../Drawing/Tiling.md), or a word-adjacency map. `idealDistance` is the spacing constant `k` every force is measured against, defaulting to `√(area / count)`. Settled edges come out near `k` only for small or dense graphs. In a large sparse web the crowd's combined repulsion compresses spacing below it, so treat `k` as the size dial. Raise it to open the web, lower it to tighten. Per-edge `weight`, set through `layout.edges` or `connect`, multiplies that edge's pull and draws its ends closer than the rest.

`gravity`, which defaults to 0, adds a phantom edge from every node to the center of `bounds`, scaled by its value. Leave it off for a single connected graph. A small value around 0.01 keeps *disconnected* pieces from repelling each other onto the walls.

<a name="step"></a>

#### Stepping, settling, and reheating

```swift
layout.step()          // one pass: repel, attract, move, cool
layout.step(10)        // several
layout.settle()        // run to a standstill (setup-shaped)
layout.reheat(0.3)     // stir a settled layout back into motion
```

The live form is one `step()` per frame in `draw()`. At the default `coolingSteps` of 250, the layout settles in about four seconds of watching. `settle()` runs the whole cooling schedule at once, for when you want the settled web and not the settling. A settled layout's `step()` returns immediately, so it can stay in `draw()`.

`temperature` is the cap on how far a node may move in one step. It cools linearly to zero from `initialTemperature`, a tenth of the frame's larger side, and `isSettled` reports the freeze. `reheat(_:)` warms it back up. Passing `1` restarts the full run, and small fractions give a gentle reflow that reads well after a change. Try `0.3` after adding a node or releasing a drag.

```swift
override func draw() {
    layout.step()
    background(.white)
    stroke(.black); fill(.black)
    drawGraph(layout)
}
```

<a name="interact"></a>

#### Growing and interacting

```swift
let i = layout.addNode(at: point)   // appends, returns the index
layout.connect(i, parent)           // appends an edge
layout.nearestNode(to: mouse)       // picking a node up
layout.pinned[i] = true             // a pinned node exerts forces but never moves
```

A growing network is add, connect, reheat, and the web makes room for each newcomer. Dragging uses the same vocabulary. Pin the grabbed node, write its position each frame, keep a little heat on so the neighbors follow, and unpin on release:

```swift
override func mousePressed() {
    grabbed = layout.nearestNode(to: Vector2(mouseX, mouseY))
    if let grabbed { layout.pinned[grabbed] = true }
}

override func draw() {
    if let grabbed, mouseIsPressed {
        layout.positions[grabbed] = Vector2(mouseX, mouseY)
        layout.reheat(0.15)
    }
    layout.step()
    // ...
}
```

Pins also hold structure: fix a root at the top and a tree hangs from it.

<a name="draw"></a>

#### drawGraph

```swift
drawGraph(layout)                  // edges in the stroke, nodes in the fill
drawGraph(layout, nodeRadius: 0)   // edges only
```

The plain rendering draws each edge as a line in the current stroke and each node as a disk in the current fill. For anything richer, such as node size by degree, edge color by weight, or labels, read `positions` and `edges` directly. They are ordinary arrays, and everything drawn is ordinary geometry, so the result feeds [SVG and PDF export](../Output/Export.md) like any other line work.

<a name="notes"></a>

#### Practical notes

- **Cost is all pairs.** Each step is O(n²) over the nodes plus O(m) over the edges. That is comfortable to step live into the low thousands of nodes, with `settle()` in `setup()` beyond that. For simulations of thousands of moving *agents*, reach for the GPU systems in [artificial life](../Simulation/ArtificialLife.md) instead. This is a layout tool.
- **It finds a good layout, not the best one.** Force direction settles into a local minimum, and different seeds give different untanglings, all equally reasonable. That is the [variations](../Core/Variations.md) story, so keep the seed that reads best.
- **A growing graph wants its spacing re-derived.** `idealDistance` is set once from the starting count. If the population grows a lot, reassign it as you add, using `√(area / count)` scaled to taste, so the web keeps filling the frame.

The worked example is [`Examples/Patterns/ForceGraph`](../../Examples/Patterns/ForceGraph/Sketch.swift). A scale-free network grows node by node and lays itself out as it grows, with any node draggable and the web reflowing around it.
