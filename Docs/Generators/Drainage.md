#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Drainage</sup>

---

## Drainage: rivers worked out from the ground

Nothing here decides where a river should go. Water on any cell of a [`Heightfield`](./Terrain.md) runs to whichever of its eight neighbors is steepest downhill. A cell joins the network once enough ground drains through it. Apply that rule everywhere and the valleys fill with branching lines on their own, because the shape of the ground is what places them.

```swift
let land = Heightfield.diamondSquare(size: 257, roughness: 0.55, seed: 7)
    .eroded(.hydraulic())
let water = land.drainage()

for river in water.rivers(minFlow: 140, in: mapFrame) {
    strokeWeight(0.7 + Double(river.order) * 0.9)
    drawPolyline(river.points)
}
```

What comes back is ordinary geometry. The points sit in the frame you asked for, so you can stroke them, hatch them, or send them to a pen through [SVG export](../Output/Export.md).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/23-Landscapes/WhereWaterGoes-dark.jpg">
  <img src="../../Guide/Images/23-Landscapes/WhereWaterGoes.jpg" alt="Three panels of one landscape. On the left a faint contour map with a branching blue river network over it, thickening downstream. In the middle the same ground split into colored basins that meet along ridges. On the right the flow as a red field, every crease of the terrain lit up" width="680">
</picture>

### Contents

- [Filling the hollows first](#filling)
- [Flow](#flow)
- [The network](#network)
- [Ordering](#order)
- [Basins](#basins)
- [What it costs](#cost)

<a name="filling"></a>

#### Filling the hollows first

A landscape is full of hollows with no way out. Water that arrives in one has nowhere to go, so the network stops there. A field grown from noise has thousands of these hollows.

So every hollow is filled first, which is what a real basin does once it has brimmed over.

```swift
let level = land.filled()          // the same field, every hollow filled to its brim
let water = land.drainage()        // does the same pass for you
let raw = land.drainage(fillingHollows: false)   // to see the hollows instead
```

The field is flooded inward from its own edges, lowest first. A cell the flood reaches is raised to the level of whatever let the water in. That level is the brim of the hollow holding the cell, and nothing else moves. A field that already drains everywhere comes back unchanged.

Two details of that pass are worth knowing, because both show up in the picture.

**A filled hollow follows the way the flood came in.** A lake has no shape of its own. Reading a slope off the filled surface drains it as a fan of straight parallel lines, which is the flood's own front showing through. So the water there takes the link the flood arrived on instead, and that link leads to the point where the hollow brims over.

**A wide hollow can brim over at more than one place.** The flood enters at whichever low place on the rim it reaches first. A rim with several equally low places is entered at several of them, so the lake leaves by each one. A symmetric bowl is the worst case for this, and real ground rarely is one.

`minDrop` is the small slope a filled cell keeps over the cell that flooded it. Leave it alone unless you have a reason to change it.

<a name="flow"></a>

#### Flow

```swift
water.flow(x, y)      // how many cells run through this one, itself counted
water.downstream      // for each cell, the one it runs into, or -1 at an outlet
water.flowField       // the same counts as a Heightfield
```

A cell that nothing reaches but its own rain reads 1, and the number climbs down a valley into the tens of thousands. The count only grows, so the cell below always carries strictly more than the cell above it. A cell's count is one plus everything above it.

The numbers are cell counts, so call `.normalized()` on `flowField` before you image it. A logarithm reads far better than the raw count. A trunk carries thousands of times what a headwater does, so a linear ramp shows the trunk and nothing else.

A diagonal step is measured over its own longer distance rather than treated as a straight step. Without that, every network would lean toward the diagonals.

<a name="network"></a>

#### The network

```swift
let rivers = water.rivers(minFlow: 140, in: frame)   // [River]
river.points     // the run itself, in that frame
river.order      // Strahler's order for the reach
river.flow       // the flow at its lowest end, in cells
```

`minFlow` is the smallest catchment you are willing to call a river, measured in cells. It decides whether you get a few large trunks or a fine web of creeks, so it is worth putting on a parameter.

Each reach is traced once. A run starts at a source, or just below a meeting, and stops at the next meeting. It shares that last cell with the reach below it, so the lines join. One odd case is kept rather than dropped. A single-cell reach happens when a cell over the threshold leaves the field at once, fed only by ground too small to count.

<a name="order"></a>

#### Ordering

Strahler's order counts how much branching sits upstream of a reach, rather than how far the water has come.

```
     1 ──┐            a headwater is 1
     1 ──┴── 2 ──┐    two of the same order make the next one up
     1 ──┐       │
     2 ──┴── 2 ──┴── 3
```

A headwater is 1. Two reaches of equal order meet to make the next order up, and an unequal pair keeps the larger of the two. Stroke by order and the network thickens downstream the way a map does. Order is also easier to read than flow, which spans four orders of magnitude.

```swift
let order = water.strahlerOrders(minFlow: 140)   // per cell, 0 outside the network
```

<a name="basins"></a>

#### Basins

```swift
water.basin(x, y)     // which outlet this cell's water reaches
water.outlets         // the cells the water leaves by, in basin order
water.outlet(x, y)
```

A basin is every cell whose water leaves by the same outlet. A cell and the cell below it are always in the same basin. Draw each basin in its own tone and you see the divides, which are the ridges, without ever computing a ridge.

<a name="cost"></a>

#### What it costs

The whole pass is a flood, a sweep, and a count, so a 257-square field takes a few tens of milliseconds. That is still real work, and the field does not change while you draw it. Run the pass in `setup()`, or when a parameter moves, then keep the network and let `draw()` draw it.

Everything here is a pure function of the field, and a field is a pure function of its seed, so a run reproduces exactly.

### See also

- [`Terrain`](./Terrain.md) - `Heightfield`, diamond-square, and the erosion passes that carve the valleys drainage then finds
- [`Isolines`](./Isolines.md) - contour lines from the same field, for the map underneath
- [`Export`](../Output/Export.md) - SVG output, since a river network is already lines a pen can draw
- Example: [Patterns/Rivers](../../Examples/Patterns/Rivers/Sketch.swift)
