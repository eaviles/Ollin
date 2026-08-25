#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Drainage</sup>

---

## Drainage: rivers worked out from the ground

Nothing here decides where a river should go. Water on any cell of a [`Heightfield`](./Terrain.md) runs to whichever of its eight neighbors is steepest downhill, and a cell joins the network once enough ground drains through it. Follow that everywhere and the valleys fill with branching lines by themselves, because the shape of the ground is what decides them.

```swift
let land = Heightfield.diamondSquare(size: 257, roughness: 0.55, seed: 7)
    .eroded(.hydraulic())
let water = land.drainage()

for river in water.rivers(minimumFlow: 140, in: mapFrame) {
    strokeWeight(0.7 + Double(river.order) * 0.9)
    drawPolyline(river.points)
}
```

What comes back is ordinary geometry: points in the frame you asked for, ready to stroke, to hatch, or to send to a pen through [SVG export](../Output/Export.md).

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

A landscape is full of hollows with no way out. Water arriving in one has nowhere to go, so the network stops dead there, and a field grown from noise has thousands of them.

Every hollow is filled first, which is what a real basin does once it has brimmed over.

```swift
let level = land.filled()          // the same field, every hollow filled to its brim
let water = land.drainage()        // does the same pass for you
let raw = land.drainage(fillingHollows: false)   // to see the hollows instead
```

The field is flooded inward from its own edges, lowest first. A cell the flood reaches is raised to the level of whatever let the water in, which is the brim of the hollow holding it, and nothing else moves. A field that already drains everywhere comes back unchanged.

Two details of that pass are worth knowing, because both show up in the picture.

**A filled hollow follows the way the flood came in.** A lake has no shape of its own, so reading a slope off the filled surface drains it as a fan of straight parallel lines, which is the flood's own front showing through. Instead the water there takes the link the flood arrived on, which leads to the point the hollow brims over at.

**A wide hollow can brim over at more than one place.** The flood fills it from whichever low place on its rim it reaches first, so a rim with several equally low places is entered at several of them, and the lake leaves by each. A symmetric bowl is the worst case for this and real ground rarely is one.

`minimumDrop` is the hair of slope a filled cell keeps over the one that flooded it. Leave it alone unless you have a reason.

<a name="flow"></a>

#### Flow

```swift
water.flow(x, y)      // how many cells run through this one, itself counted
water.downstream      // for each cell, the one it runs into, or -1 at an outlet
water.flowField       // the same counts as a Heightfield
```

A cell nothing reaches but its own rain reads 1, and the number climbs down a valley to the tens of thousands. It only grows: the cell below always carries strictly more than the cell above it, and a cell's count is one plus everything above it.

The numbers are cell counts, so `flowField` wants `.normalized()` before imaging, and a logarithm reads far better than the raw count. A trunk carries thousands of times what a headwater does, so a linear ramp shows the trunk and nothing else.

A diagonal step is measured over its own longer distance rather than treated as a straight one, or every network would lean toward the diagonals.

<a name="network"></a>

#### The network

```swift
let rivers = water.rivers(minimumFlow: 140, in: frame)   // [River]
river.points     // the run itself, in that frame
river.order      // Strahler's order for the reach
river.flow       // the flow at its lowest end, in cells
```

`minimumFlow` has a real meaning: it is the smallest catchment you are willing to call a river, in cells. It is the whole difference between a few great trunks and a fine tracery of creeks, and it is worth putting on a knob.

Each reach is traced once. A run starts at a source, or just below a meeting, and stops at the next meeting, sharing that cell with the reach below it so the lines join. One odd case exists and is kept rather than dropped: a single-cell reach, where a cell over the threshold leaves the field at once, fed only by ground too small to count.

<a name="order"></a>

#### Ordering

Strahler's order counts how much of the branching upstream is behind a reach, rather than how far it has come.

```
     1 ──┐            a headwater is 1
     1 ──┴── 2 ──┐    two of the same order make the next one up
     1 ──┐       │
     2 ──┴── 2 ──┴── 3
```

A headwater is 1. Two reaches of equal order meeting make the next one up, and an unequal pair keeps the larger of the two. Stroking by it draws a network that thickens downstream the way a map does, and it is cheaper to read than flow, which spans four orders of magnitude.

```swift
let order = water.strahlerOrders(minimumFlow: 140)   // per cell, 0 outside the network
```

<a name="basins"></a>

#### Basins

```swift
water.basin(x, y)     // which outlet this cell's water reaches
water.outlets         // the cells the water leaves by, in basin order
water.outlet(of: x, y)
```

A basin is everybody who leaves by the same door, so a cell and the cell below it are always in the same one. Drawing each in its own tone shows the divides, which are the ridges, without ever computing a ridge.

<a name="cost"></a>

#### What it costs

The whole pass is a flood, a sweep, and a count, so a 257-square field is a few tens of milliseconds. It is still real work, and the field does not change while you draw it, so do it in `setup()` or when a knob moves. Keep the network and let `draw()` draw it.

Everything is a pure function of the field, and a field is a pure function of its seed, so a run reproduces exactly.

### See also

- [`Terrain`](./Terrain.md) - `Heightfield`, diamond-square, and the erosion passes that carve the valleys this then finds
- [`Isolines`](./Isolines.md) - contour lines from the same field, for the map underneath
- [`Export`](../Output/Export.md) - SVG out, since a river network is already lines a pen can draw
- Example: [Patterns/Rivers](../../Examples/Patterns/Rivers/Sketch.swift)
