#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `SDF combinators`</sup>

---

## SDF combinators

Compose signed-distance *fields* so shapes **merge** instead of just stacking. A smooth
union melts two shapes into one blob (their colors blending across the seam), subtraction
carves one out of another, intersection keeps only the overlap, and morph blends between
two shapes. Domain operators tile or mirror the whole field. The result fills as a single
region, and a stroke traces the *merged* outline.

This is the geometry counterpart of the image-space [layered effects](./Effects.md): there
you composite finished *layers*; here you combine the *distance fields* before they are
ever drawn, so the shapes fuse rather than overlap.

You build a field with the `SDF` value type and draw it with `drawSDF`. The value type is
the core; the [scoped block form](#scoped-blocks) is sugar over it. Both are solid color
only for now (a gradient on a merged field is a later addition).

### Contents

- [Quick start](#quick-start)
- [Building a field](#building)
- [Combining](#combining)
- [Modifiers: round and onion](#modifiers)
- [Placing and coloring](#placing)
- [Domain operators](#domain)
- [Scoped blocks](#scoped-blocks)
- [3D fields](#fields-3d)
- [Notes and limits](#notes)

<a name="quick-start"></a>

### Quick start

Two shapes melting together, the melt amount breathing:

```swift
override func draw() {
    background(.black)
    noStroke()
    let k = 20 + (sin(time) * 0.5 + 0.5) * 80   // how much they melt

    let blob = SDF.circle(radius: 150).colored(.init(hex: 0xff5470))
        .smoothUnion(
            SDF.rect(width: 260, height: 150, cornerRadius: 30)
                .colored(.init(hex: 0x3a86ff))
                .at(x: 120, y: 0),
            k: k)
        .at(x: width * 0.5, y: height * 0.5)

    drawSDF(blob)
}
```

`SDF.circle(...)` and friends are field *values*; `.colored`, `.at`, and `.smoothUnion`
return new fields; `drawSDF` rasterizes the whole composition in one pass.

<a name="building"></a>

### Building a field

The leaf constructors are the common centered region shapes. Each is centered on the field
origin (move it with [`.at`](#placing)).

| Constructor | Shape |
| --- | --- |
| `SDF.circle(radius:)` | a circle |
| `SDF.ellipse(rx:ry:)` | an axis-aligned ellipse |
| `SDF.rect(width:height:cornerRadius:)` | a rectangle, optionally rounded |
| `SDF.square(_:cornerRadius:)` | a square |
| `SDF.ngon(radius:sides:)` | a regular polygon, one vertex up |
| `SDF.star(outerRadius:innerRadius:points:)` | a star |
| `SDF.rhombus(width:height:cornerRadius:)` | a diamond |
| `SDF.ring(innerRadius:outerRadius:)` | a filled annulus |
| `SDF.triangle(radius:)` | an equilateral triangle, point up |

The [scoped block form](#scoped-blocks) reaches *every* fillable shape Ollin can draw
(`drawNgon`, `drawHeart`, `drawTrapezoid`, and the rest), so use a block when you want a
shape the value type does not name directly.

<a name="combining"></a>

### Combining

Each combinator takes another field and returns the combined one, so they chain. The smooth
variants take a smoothing radius `k` (in canvas points) that sets how wide the blend is, and
they **blend the two operands' colors** across that blend so a melt reads as one object.

```swift
let a = SDF.circle(radius: 100).colored(.red)
let b = SDF.circle(radius: 100).colored(.blue).at(x: 120, y: 0)

a.union(b)              // hard union: the area covered by either
a.smoothUnion(b, k: 40) // melt them together (colors blend at the seam)
a.subtract(b)           // a with b carved out
a.smoothSubtract(b, k: 40)
a.intersect(b)          // only where both overlap (a lens)
a.smoothIntersect(b, k: 40)
a.morph(b, amount: 0.5) // blend the shape itself between a and b (0 = a, 1 = b)
```

`subtract` and `smoothSubtract` keep the first field's color (it is the body that remains).
`morph` is a *field* blend, not a crossfade: at `amount: 0.5` the boundary is genuinely
halfway between the two shapes.

<a name="modifiers"></a>

### Modifiers: round and onion

```swift
field.rounded(12)   // grow the field outward by 12 with rounded corners
field.onion(8)      // hollow it into an 8-wide shell straddling its outline
```

`onion` turns any field into a band, the same trick `drawRing` uses, so you can hollow out a
melted blob or a morphed star.

<a name="placing"></a>

### Placing and coloring

```swift
field.at(x: 540, y: 540)   // move the field's origin to a point
field.at(somePoint)        // ... given a Vector2
field.rotated(.pi / 6)     // rotate about the origin
field.scaled(1.5)          // uniformly scale about the origin
field.colored(.orange)     // paint the unpainted leaves this color
```

Order matters, because every transform applies to whatever it wraps. `circle.at(p).scaled(2)`
scales the moved circle (so it also moves twice as far from the origin); `circle.scaled(2).at(p)`
scales in place, then moves. `colored` fills only leaves that have no color yet, so set a
leaf's own color before combining for a two-color melt, and use `colored` on the whole field
as a fallback. A leaf with no color, and no enclosing `colored`, takes the current `fill`.

Only **uniform** scale is supported: a non-uniform scale is not a valid distance field, so it
would distort the smoothing and the outline.

<a name="domain"></a>

### Domain operators

Domain operators transform the *space* the field lives in, so one shape becomes many.

```swift
field.mirrored(x: true)                       // reflect across the y axis (kaleidoscope)
field.mirrored(x: true, y: true)              // reflect across both axes
field.repeated(spacing: Vector2(160, 0), count: 3)   // tile: 3 copies each side, on a 160 grid
field.at(x: 120, y: 0).repeatedRadially(count: 8)   // fold a wedge into a ring of 8 (a mandala)
```

`repeated`'s `count` is the number of copies to each side of the origin on each axis; a
`spacing` component of `0` leaves that axis untiled. `repeatedRadially`'s `count` is the
number of copies evenly spaced around the origin; offset the wedge from the origin first
(`.at`) so the copies fan out around it. Because a domain operator wraps a whole field, you
can tile a melted cluster, mirror a carved shape, or ring a wedge into a mandala.

<a name="scoped-blocks"></a>

### Scoped blocks

The block form is sugar over the value type: bare draw calls inside a block are captured and
merged under the block's operator, then drawn (with the current `fill`/`stroke`) when the
block closes. It reads like ordinary immediate-mode drawing, and reaches every fillable shape.

```swift
fill(.orange)
smoothUnion(k: 18) {
    drawCircle(0, 0, 120)
    drawRect(90, 0, 200, 80)
    drawNgon(-90, 0, 60, sides: 6)
}
```

The blocks mirror the combinators and domain operators: `union { }`, `smoothUnion(k:) { }`,
`subtract { }`, `smoothSubtract(k:) { }`, `intersect { }`, `smoothIntersect(k:) { }`,
`mirrored(x:y:) { }`, `repeated(spacing:count:) { }`, `repeatedRadially(count:) { }`. They
nest, so a domain block can wrap a combine block:

```swift
fill(.indigo)
repeated(spacing: Vector2(150, 0), count: 2) {
    smoothUnion(k: 12) {
        drawRect(-30, -30, 60, 60, cornerRadius: 14)
        drawCircle(34, 0, 22)
    }
}
```

Each captured call's own `fill` becomes that leaf's color, so colors melt at a smooth seam
exactly as with `.colored`. Set up position with the [transform stack](./Drawing.md)
(`translate`/`rotate`) around the block; non-region draws inside a block (lines, text,
images) are ignored.

<a name="fields-3d"></a>

### 3D fields

The same idea lifts into space: `SDF3D` builds a 3D field and `drawSDF3D` sphere-traces it as
one merged surface inside an active [3D camera](./3D.md), lit by the scene's lights and
depth-composited with the rasterized meshes (each occludes the other where they meet). It is
the 3D sibling of `SDF` / `drawSDF`, with the same combine, modifier, and transform vocabulary.

```swift
override func draw() {
    camera(.orbiting(target: .zero, radius: 5.5, azimuth: time * 0.35,
                     elevation: 0.4, fieldOfView: .pi / 4))
    directionalLight(.white, direction: Vector3(-0.6, 0.7, 0.5))
    material(.jade)

    let blob = SDF3D.sphere(radius: 1).colored(.init(hex: 0x39d0ff))
        .smoothUnion(SDF3D.sphere(radius: 0.8)
            .at(x: cos(time) * 1.2, y: 0, z: sin(time) * 1.2)
            .colored(.init(hex: 0xff4f97)), k: 0.6)
        .smoothSubtract(SDF3D.sphere(radius: 0.7).at(x: 0, y: 1, z: 0), k: 0.2)

    drawSDF3D(blob)
}
```

The leaf constructors are the common centered solids:

| Constructor | Solid |
| --- | --- |
| `SDF3D.sphere(radius:)` | a sphere |
| `SDF3D.box(width:height:depth:)` / `SDF3D.box(size:)` | a box / cube |
| `SDF3D.roundBox(width:height:depth:radius:)` / `SDF3D.roundBox(size:radius:)` | a box / cube with filleted edges |
| `SDF3D.torus(radius:tube:)` | a torus, lying in the xz-plane |
| `SDF3D.capsule(radius:height:)` | a capsule along the y-axis |
| `SDF3D.cylinder(radius:height:)` | a cylinder along the y-axis |
| `SDF3D.cone(radius:height:)` / `SDF3D.cone(bottomRadius:topRadius:height:)` | a cone / frustum along the y-axis |
| `SDF3D.octahedron(radius:)` | an octahedron |
| `SDF3D.ellipsoid(rx:ry:rz:)` | an ellipsoid |

The combinators (`.union` / `.smoothUnion(_:k:)` / `.subtract` / `.smoothSubtract(_:k:)` /
`.intersect` / `.smoothIntersect(_:k:)` / `.morph(_:amount:)`), the modifiers (`.rounded` /
`.onion`), the domain operators (`.mirrored(x:y:z:)`, `.repeated(spacing:count:)`, and
`.repeatedRadially(count:around:)`), and `.colored` all behave exactly as in 2D, the smooth
ops blending the leaf colors across the seam. Positioning is in three dimensions:
`.at(x:y:z:)` / `.at(_ p: Vector3)`, `.rotated(_:axis:)` (plus `.rotatedX` / `.rotatedY` /
`.rotatedZ`), and `.scaled(_:)` (uniform). The domain operators rewrite the query point as
point-space scopes, so the whole mirrored / tiled / radially repeated field is still one
sphere-traced surface (no per-copy draw cost), and method-chain order stays exact:
`a.at(p).repeated(…)` tiles the moved field, `a.repeated(…).at(p)` shifts the tiling.
`repeated` is finite (`count` copies to each side), so the field stays bounded;
`repeatedRadially` folds a wedge into a ring of `count` copies around `axis` (default the
y-axis), so offset the wedge off the axis first (`.at(x: r, …)`) for the copies to fan out.

The **scoped block form** works in 3D too, and it's the same `smoothUnion(k:) { }` (and the
other combine blocks) as 2D. Inside a block with a camera set, the bare mesh primitives
(`drawSphere` / `drawBox` / `drawCapsule` / `drawCone` / `drawTorus` / `drawCylinder` /
`drawRoundedBox` / `drawOctahedron`) are captured and merged as raymarched fields rather than
rasterized as separate solids. The transform stack works inside the block, and each call's own
`fill` becomes that lobe's color:

```swift
material(.jade)
smoothUnion(k: 0.35) {
    fill(.init(hex: 0x3ad6c5))
    withState { translate(0, -0.6, 0); drawSphere(radius: 0.95) }   // body
    withState { translate(0, 0.7, 0);  drawSphere(radius: 0.62) }   // head
    fill(.init(hex: 0xff5d73))
    withState { translate(0, 1.5, 0); drawCone(radius: 0.45, height: 0.7) }  // hat
}
```

The block form's domain blocks work in 3D too (`mirrored(x:y:z:) { … }`,
`repeated(spacing:count:) { … }`, the `Vector3` spacing for 3D tiling), wrapping a combine
block to mirror or tile a whole built cell. A primitive that has no analytic field
(`drawIcosphere`, `drawTorusKnot`, a custom `Mesh`, …) inside a block is ignored with a
one-time note.

**Self-shadowing.** With [`castShadows()`](./3D.md), a merged field drops soft shadows onto
itself: a penumbra march toward the casting light, contact-hardening (sharper where shapes
meet, softer as the shadow falls away). It's the same opt-in as mesh shadows, so a field
without `castShadows()` shades unshadowed (and stays byte-identical). The field self-shadows
but does not yet cast a shadow into the *mesh* shadow maps, so build a slab and the shapes on
it as one field to see them shadow one another.

The merged surface's **silhouette is anti-aliased** analytically (a sphere-traced fullscreen
pass gets no MSAA at its hit/miss edge): the march measures how closely a ray that misses the
surface grazed it, relative to the pixel's own footprint, and the edge fades by that coverage.
It's automatic, so any field's outline stays smooth without supersampling.

The 3D path is opt-in like the rest of [3D mode](./3D.md), so a 2D sketch never pays for it.
Today it covers the leaves above with solid color per leaf and uniform scale. Casting into the
mesh shadow maps is on the [roadmap](../ROADMAP.md).

<a name="notes"></a>

### Notes and limits

- **Solid color only.** A field fills with solid colors (per leaf, or the current `fill`);
  gradient paint on a merged field is a later addition.
- **Closed regions only.** Combinators merge fillable shapes. Open marks (lines, open arcs,
  Bézier strokes) have no interior to merge, so they are not combinator leaves.
- **Uniform scale only**, as above.
- **2D and 3D.** `SDF` / `drawSDF` are the 2D fields here; `SDF3D` / `drawSDF3D` sphere-trace
  the same kind of field in space (see [3D fields](#fields-3d)). The 3D form is opt-in and
  shares these limits (solid color, uniform scale).
- A composition is bounded (a generous node and nesting budget); a field past it is skipped
  with a console note rather than mis-drawn.

---

See also [`Drawing`](./Drawing.md) for the immediate-mode shapes and the transform stack,
[`Geometry`](./Geometry.md) for the vector `Shape` booleans (which combine *filled outlines*,
the polygonal counterpart to these field operators), [`Color`](./Color.md) for the color
types the leaves carry, and [`3D`](./3D.md) for the camera and lights the 3D fields draw
through. The examples are `Examples/Basic/Combinators` (2D), `Examples/3D/RaymarchedSDF`
(merged metaball, depth-composited with a mesh), `Examples/3D/RaymarchedShapes` (the 3D
primitive catalog), `Examples/3D/RaymarchedSculpt` (the scoped block form),
`Examples/3D/RaymarchedDomain` (the mirror and repeat domain operators),
`Examples/3D/RaymarchedRadial` (the radial/polar repeat operator), and
`Examples/3D/RaymarchedShadow` (self-shadowing under `castShadows()`).
