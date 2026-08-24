#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Circle packing`</sup>

---

## Circle packing

Fill a region with circles that grow until they touch but never overlap, the classic generative-art motif. Two ways to produce a packing are built in, and both are **reproducible**, so seeding a run always lays the circles down the same way.

- **Grow-to-touch** (`packCircles`): each circle grows to the largest it can be without hitting a neighbor or the bounds. `packCircles(count:)` scatters its own seed points and fills the gaps between big circles with progressively smaller ones, giving the dense, varied look. `packCircles(around:)` grows a circle at each point you hand it, and a [blue-noise](./BlueNoise.md) set makes an even foam.
- **Front relaxation** (`relaxCircles`): start from circles that overlap and push every overlapping pair apart until none do, holding their radii fixed. It's the way to settle a set you sized yourself.

The output is `[Circle]`, so it feeds straight into [`drawCircles`](../Drawing/Drawing.md), the [shape booleans](../Drawing/Geometry.md), hatching, and SVG export.

```
  packCircles(count:)              packCircles(around: sites)       relaxCircles(overlapping)

    ___     __   ___                 __   __   __   __              (  (○)  )   overlap →
   (   )   (  ) (   )               (  ) (  ) (  ) (  )              ( ○  ○ )   push apart
   (   ) o (  )O(   )               (__) (__) (__) (__)                 ↓          ↓
   (___)   (__) (___)               __   __   __   __              ( ○ )( ○ )  no overlap,
    o  ___   o   __                 (  ) (  ) (  ) (  )             ( ○ )( ○ )  radii fixed
     O(   ) O   (  )                (__) (__) (__) (__)

  big first, small fill gaps       one circle per point,           separation only, no
  (varied radii)                   grown to just touch (a foam)     growth
```

<img src="../../Guide/Images/15-ShapesAsMaterial/PackingLapse.jpg" alt="Four panels of the same seeded circle packing at step 2, 8, 30, and 220: a few large circles claim the space early and ever smaller circles fill the leftover gaps" width="680">

### Contents

- [packCircles (self-seeding)](#pack)
- [packCircles (from points)](#around)
- [relaxCircles](#relax)
- [Standalone (outside a sketch)](#standalone)

<a name="pack"></a>

#### packCircles (self-seeding)

```swift
packCircles(in bounds: Rectangle? = nil,
            count: Int,
            minRadius: Double,
            maxRadius: Double = .infinity,
            padding: Double = 0,
            attemptsPerCircle: Int = 30) -> [Circle]
```

A dense packing of `bounds`, the whole canvas by default. It scatters up to `count` seed points and grows a circle at each to the largest radius that clears every circle already placed, so big circles land first and smaller ones fill the gaps. `count` is a target rather than a guarantee, because packing gets harder as the region fills, so a run stops once `count` circles are placed *or* it has thrown its dart budget (`count * attemptsPerCircle`) without room for more. A circle smaller than `minRadius` is never placed, `maxRadius` caps how large one may grow, and `padding` opens a gap between neighbors.

```swift
seed(11)
let packed = packCircles(count: 900, minRadius: 4 * scale, maxRadius: 110 * scale, padding: 3 * scale)
noStroke(); fill(.white)
drawCircles(packed)
```

Because the layout is a pure function of the seed, compute it once and hold it (in a stored property) rather than every frame, then animate something visual (a circle's color, a small wobble) so the pack breathes without the circles jumping. See the `CirclePacking` example.

<a name="around"></a>

#### packCircles (from points)

```swift
packCircles(around sites: [Vector2],
            in bounds: Rectangle? = nil,
            minRadius: Double = 0,
            maxRadius: Double = .infinity,
            padding: Double = 0) -> [Circle]
```

Grow a circle at each of `sites` until it just touches its nearest neighbor (or the bounds). Because two circles growing at the same rate meet exactly halfway, each radius is simply half the distance to the nearest other point (less half the `padding`). It needs no random source, so it reads straight off the points. Feed it a [blue-noise](./BlueNoise.md) set for an even, gap-free foam.

```swift
seed(7)
let sites = poissonDisk(radius: 40)
noStroke(); fill(.white)
drawCircles(packCircles(around: sites, padding: 2))
```

<a name="relax"></a>

#### relaxCircles

```swift
relaxCircles(_ circles: [Circle],
             in bounds: Rectangle? = nil,
             iterations: Int = 20,
             padding: Double = 0) -> [Circle]
```

Push overlapping circles apart until none overlap, holding each radius fixed. Each pass nudges every overlapping pair away by half their overlap, then slides any circle poking past the bounds back inside. A few iterations settle most sets, and a heavily overlapping one wants more. It is the sibling of Voronoi's [`lloyd`](../Drawing/Voronoi.md) for circles you sized yourself, so pick your radii and let relaxation resolve the collisions.

```swift
seed(3)
// Sites with your own radii, then separated:
let sized = poissonDisk(radius: 30).map { Circle(center: $0, radius: random(8, 26)) }
drawCircles(relaxCircles(sized, iterations: 40, padding: 2))
```

<a name="standalone"></a>

#### Standalone (outside a sketch)

The `Sketch` methods are sugar over free functions. `packCircles(count:)` takes any random source, so geometry code outside a sketch can pack reproducibly too (hand it a seeded [`SplitMix64`](./Random.md)). `packCircles(around:)` and `relaxCircles` are deterministic and take none.

```swift
var rng = SplitMix64(seed: 11)
let packed = packCircles(in: bounds, count: 400, minRadius: 3, maxRadius: 90, using: &rng)

let sites = poissonDisk(in: bounds, radius: 40, using: &rng)
let foam = packCircles(around: sites, in: bounds, padding: 2)
```

---

Related: [`Blue noise`](./BlueNoise.md) (the even seed set a foam packing grows from), [`Voronoi & Delaunay`](../Drawing/Voronoi.md) (the other way to tile a region from points), [`Geometry`](../Drawing/Geometry.md) (the `Circle` type and the shape booleans the output feeds).
