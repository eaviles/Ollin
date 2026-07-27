#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 18</sup>

---

# 18. Sculpting with fields

<img src="Images/18-SculptingWithFields/Molten.jpg" alt="A pale mint sculpture like a settling drop of melted glass, glossy under studio light, one lobe drooping toward a dark floor that catches its soft shadow" width="560">

Chapter 13 treated shapes as outlines you cut and joined, like paper. This chapter treats them as something closer to wax: shapes that melt into each other, carve each other, and hold together as one surface no matter how you push them. The tool is the **signed distance field**, an idea you've already met twice without the name, and it ends in the sculpture above: one body made of four melted lobes, slowly breathing, orbitable with the mouse.

## A shape as a question

Chapter 12 defined a field as an answer at every point. A **signed distance field** is a shape stored that way: ask any point of the canvas, and it answers with one number, *how far is the nearest surface*. The sign carries which side you're on: positive outside, negative inside, zero exactly on the boundary.

<img src="Images/18-SculptingWithFields/FieldMap.jpg" alt="A distance field visualized: a melted circle-and-box shape in warm orange, surrounded by concentric cool bands of equal distance, with a bold dark line at distance zero" width="680">

That's the whole idea, and it's worth a slow look. The shape is not stored as an outline; the *bold line* is just the places where the field happens to answer zero. Chapter 15 used this trick per pixel (a circle was "all the points within `radius`", and `smoothstep` softened its edge). What's new here is what the representation buys: if two shapes are each a distance function, then *combining the answers* combines the shapes.

## Melting

The everyday container for this is the `SDF` value type, and the first verb to learn is `smoothUnion`:

```swift
import Ollin

final class Melt: Sketch {
    override func draw() {
        background(Color(hex: 0x101318))
        noStroke()
        let k = 20 + (sin(time) * 0.5 + 0.5) * 90

        let blob = SDF.circle(radius: 130).colored(Color(hex: 0xE4572E))
            .smoothUnion(SDF.rect(width: 240, height: 140, cornerRadius: 28)
                .colored(Color(hex: 0x3A6EA5))
                .at(x: 130, y: 40), k: k)

        drawSDF(blob.at(x: width / 2, y: height / 2))
    }
}
```

Run it and watch the seam. `SDF.circle` and `SDF.rect` are field *values*, like a `Shape` or a `Color`; `.at` moves one; `.colored` paints one; `.smoothUnion` merges two into a new field; and `drawSDF` rasterizes whatever field you hand it, in one pass. The knob `k` is the width of the melt, in canvas points:

<img src="Images/18-SculptingWithFields/MeltStrip.jpg" alt="The same orange and blue circles at four smoothing radii: touching hard at k = 0, necking together at 22, flowing into a peanut at 55, and fused into one capsule at 110" width="680">

At `k = 0` the union is hard, two shapes overlapping like Chapter 13. As `k` grows, the seam becomes a fillet, then a neck, then the pair is one body. Look at the colors: the smooth union blends the two operands' colors across the melt, which is what makes the result read as one object rather than a trick. This one knob is most of the medium; put it on a `@Param` slider and you'll feel it immediately.

One habit worth setting early: **order matters in the chain**. Every call wraps the field before it, so `circle.at(p).scaled(2)` scales the *moved* circle (it lands twice as far out), while `circle.scaled(2).at(p)` scales in place and then moves. Read chains inside out and they always make sense.

## The verbs

Melting is one verb of six:

<img src="Images/18-SculptingWithFields/Verbs.jpg" alt="Six tiles of the same circle and rounded rectangle combined by union, smoothUnion, morph, subtract, smoothSubtract, and intersect" width="680">

```swift
a.union(b)               // either
a.smoothUnion(b, k: 34)  // either, melted
a.subtract(b)            // a with b carved away
a.smoothSubtract(b, k: 34)
a.intersect(b)           // only the overlap
a.morph(b, amount: 0.5)  // a shape halfway between the two
```

These are Chapter 13's booleans reborn on fields, plus two that outlines can't do: the smooth forms, and `morph`, which blends the *boundary itself*, so at `0.5` you get a genuinely in-between shape, not a crossfade. Two modifiers round out the kit: `.rounded(12)` inflates any field with soft corners, and `.onion(8)` hollows it into a shell. And past the melted family there's a whole *machined* family (`chamferUnion`, `stairsUnion`, `columnsUnion`, plus engrave, groove, tongue, and pipe detailing) that shapes the seam like joinery instead of wax; the [combinators reference](../Docs/Drawing/Combinators.md#combining) has the full bench.

## Writing it like drawing

Building chains is precise, but sometimes you just want to draw. The block form captures ordinary draw calls and merges them:

```swift
translate(width / 2, height / 2)
fill(Color(hex: 0xE4572E))
smoothUnion(k: 18) {
    drawCircle(0, 0, 110)
    drawRect(center: Vector2(120, 30), width: 190, height: 80, cornerRadius: 20)
    drawNgon(-105, 40, 62, sides: 6)
}
```

Everything drawable with a fill can join a block, including shapes the `SDF` type doesn't name (hearts, stars, trapezoids), and each call's own `fill` becomes its color in the melt. It reads like normal drawing; the block just holds the shapes open until it closes, then merges them all.

## Into space

Everything above lifts into 3D nearly unchanged. `SDF3D` builds fields in space, and `drawSDF3D` draws the merged surface through Chapter 17's camera, lit by its lights, wearing its materials:

```swift
final class FirstMarch: Sketch {
    override func draw() {
        background(Color(hex: 0x0D1017))
        camera(.orbiting(target: .zero, radius: 5.2, azimuth: 0.5,
                         elevation: 0.3, fieldOfView: .pi / 4))
        material(.jade)

        let blob = SDF3D.sphere(radius: 1).colored(Color(hex: 0x39D0C8))
            .smoothUnion(SDF3D.sphere(radius: 0.72)
                .at(x: 1.0, y: 0.42, z: 0.1)
                .colored(Color(hex: 0xFF4F97)), k: 0.5)
            .smoothSubtract(SDF3D.sphere(radius: 0.55).at(x: -0.45, y: 0.75, z: 0.5), k: 0.25)

        drawSDF3D(blob)
    }
}
```

<img src="Images/18-SculptingWithFields/FirstMarch.jpg" alt="Two spheres melted into a single teal-to-pink body with a smooth crater carved into its upper left, shaded like polished jade" width="560">

Try building that from triangle meshes and you'll appreciate what just happened: the two spheres aren't two surfaces cleverly joined, they are *one* surface, because the field underneath is one function. The leaf catalog matches the mesh primitives (sphere, box, torus, capsule, cylinder, cone, octahedron, and more, plus `line(from:to:radius:)`, a stroke between two points that's perfect for sketching limbs and branches for the melt to flesh out). Fields and meshes coexist in one scene and correctly hide each other; the [combinators reference](../Docs/Drawing/Combinators.md#fields-3d) has the whole catalog.

## How the picture gets made

A mesh is triangles, and the GPU knows how to draw triangles. A field is just a function, so how does it become pixels? By *asking it the right question, repeatedly*. For each pixel, a ray leaves the camera, and the field is asked: how far is the nearest surface? The answer is a promise, nothing is closer than this, so the ray can safely hop exactly that far. Ask again, hop again:

<img src="Images/18-SculptingWithFields/MarchRay.jpg" alt="A diagram of sphere tracing: a ray from an eye crossing the canvas in shrinking hops, each hop bounded by a circle showing the distance the field reported, ending on a gray blob's surface" width="680">

The hops shrink as the ray nears a surface (watch them tighten as the ray passes over the lower shape) and grow again in open space, and the ray lands on the surface without ever stepping through it. This is called **sphere tracing**, and it's the second big advantage of the representation: the same number that let shapes melt is what steers the rays that draw them.

You get all of this without writing any of it. The one practical knob is `raymarchQuality(_:)`: tracing costs by the pixel, so the live window traces at a resolution budget by default while exports always render full quality. If a heavy field stutters while you sketch, `raymarchQuality(.performance)` buys headroom.

## Sculpting like clay

For forms you build up rather than compose, the `sculpt { }` block turns the operators into working state: shapes `add()` on or `carve()` away, melting by the current `blend(_:)` amount, top to bottom like a session at a potter's wheel:

```swift
sculpt {
    blend(0.3)                 // melt amount for what follows
    fill(Color(hex: 0xD96F4E))
    drawSphere(radius: 1.0)                                        // the body
    withState { translate(0, 0.95, 0)
                drawTorus(radius: 0.5, tube: 0.16) }               // a lip melts on
    carve()                    // now shapes cut away
    withState { translate(0, 1.1, 0); drawSphere(radius: 0.52) }   // the hollow
    add(); blend(0.05)         // back to adding, nearly hard
    withState { translate(0, 0.35, 1.05); rotateX(.pi / 2)
                drawTorus(radius: 0.34, tube: 0.09) }              // a handle
}
```

<img src="Images/18-SculptingWithFields/Vessel.jpg" alt="A round terracotta vessel with a melted-on lip, a hollowed mouth, and a crisp ring handle, thrown from spheres and tori inside a sculpt block" width="560">

Flip one `add()` to `carve()` and a bump becomes a dent, which is exactly the kind of edit live coding thrives on. A further set of distortions bends whole forms: `.twisted(1.2)` screws a shape around its axis, `.bent(0.6)` curls it, and `.displaced` / `.roughened` ripple or roughen the surface (the rock look). They're all safe to stack; the tracer automatically compensates for the distortion.

## Folding space

The last trick is the strangest one. Instead of copying a shape, you can fold the *space it lives in*, so one shape answers for many:

<img src="Images/18-SculptingWithFields/DomainFold.jpg" alt="Three panels: an asymmetric cluster mirrored into a facing pair, the same cluster tiled into a three-by-three grid, and a petal fanned into a nine-fold rosette" width="680">

```swift
cluster.mirrored(x: true)                             // a facing pair
cluster.repeated(spacing: Vector2(88, 88), count: 1)  // a 3×3 tiling
petal.at(x: 82, y: 0).repeatedRadially(count: 9)      // a rosette
```

There is still only one cluster; the domain operator rewrites each query point (folding it across the mirror, wrapping it into a cell, rotating it into a wedge) before the field answers. Copies are free: a thousand-copy tiling costs what one copy costs. All three work in 3D too, where `repeatedRadially` fans a wedge around an axis and a mirrored melt becomes a symmetric creature. One honest note: the radial fold is exact when the repeated content is symmetric within its wedge; an asymmetric cluster can show a faint seam where wedges meet (the rosette panel uses a symmetric petal for exactly that reason).

## The finish

A field shades like a mesh, so all of Chapter 17 applies: `material(.jade)` gives a melt its glow, `castShadows()` grounds it (a field even self-shadows, and trades shadows with the meshes around it), and an `environment(_:)` lights it from its surroundings (a bundled HDRI like `.studio` or `.sunset`, or the procedural `.sky(sunElevation:)`, which needs no asset at all). That last one is where the physically based materials from Chapter 17 pay off: under `environment(.studio)`, a `material(.dielectric(roughness: 0.07))` field picks up the studio's soft light strips as real reflections, which is the glassy look this chapter ends on. Two pointers for when you want more: `SDF3D.plane()` is an infinite floor you can merge into the field for true horizon-to-horizon self-shadowing, and on Apple silicon `rayTracedReflections()` lets a physically based field mirror the actual meshes around it. The [combining map](../Docs/3D/Combining.md) sorts out exactly which finish applies to which geometry.

## Putting it together: molten

Make `MySketches/Molten.swift`:

```swift
import Ollin

final class Molten: Sketch {
    override func setup() { seed(9) }

    override func draw() {
        background(Color(hex: 0x0D1017))
        cameraShowcase(target: Vector3(0, 1.0, 0), radius: 6.4,
                       elevation: 0.2, fieldOfView: .pi / 4.2)
        environment(.studio.lightingOnly())
        toneMap(.aces, exposure: 1.05)
        directionalLight(Color(white: 0.85), direction: Vector3(-0.5, -1, -0.35),
                         intensity: 0.55)
        castShadows()

        // The floor that catches the sculpture's shadow.
        material(.matte)
        fill(Color(hex: 0x30343F))
        drawPlane(width: 30, depth: 30)

        // The glass: four lobes melting into one body, breathing.
        let breathe = 0.42 + signedNoise(time * 0.25) * 0.1
        let glass = Color(hex: 0x9FDCD3)
        let body = SDF3D.sphere(radius: 0.8).at(x: 0, y: 0.85, z: 0)
            .smoothUnion(SDF3D.ellipsoid(rx: 0.62, ry: 0.4, rz: 0.62)
                .at(x: 0.72, y: 0.5, z: 0.25), k: breathe)
            .smoothUnion(SDF3D.torus(radius: 0.6, tube: 0.19)
                .at(x: -0.55, y: 1.25, z: -0.1).rotatedZ(0.5), k: 0.4)
            .smoothUnion(SDF3D.sphere(radius: 0.4).at(x: -0.2, y: 1.95, z: 0.3), k: 0.5)
            .twisted(0.3)
            .colored(glass)

        material(.dielectric(roughness: 0.07))
        drawSDF3D(body)
    }
}
```

<img src="Images/18-SculptingWithFields/Molten.jpg" alt="The finished molten piece: a glossy mint body of fused lobes with a drooping drip, its reflection-lit surface reading as glass, over a dark floor with a soft shadow" width="560">

Four primitive lobes, three smooth unions, one twist, and a glassy finish; the breathing comes from `signedNoise` easing the first melt radius in and out. Notice the mesh floor and the traced field sharing the frame: the field drops its shadow onto the plane, and each would hide the other if they overlapped. That's the everyday reality of this chapter: fields aren't a separate world, they're one more kind of thing your scene draws.

Then make it yours:

- Replace a lobe with `SDF3D.line(from:to:radius:)` and grow the drop a limb; a few chained lines plus a big `k` is how creatures start.
- Wrap the body in `.repeatedRadially(count: 5)` (offset it from the axis first) and the drop becomes a chandelier.
- Trade the glass for `.metal(roughness: 0.15)` with `environment(.sunset)`, and add `rayTracedReflections()` if your Mac traces.
- Carve it: one `smoothSubtract` of a big sphere turns the sculpture into a grotto.

## Where this comes from

Distance fields as a drawing medium are the craft of the demoscene and Shadertoy communities, and above all of Inigo Quilez, whose catalogs of distance functions, the polynomial smooth minimum, and raymarching articles underlie nearly everything here and are credited throughout Ollin's implementation. Sphere tracing was formalized by John C. Hart in 1996; the blobby, merging-spheres idea is much older, going back to Jim Blinn's 1982 "blobby model" and the metaballs of 1980s Japanese graphics research. The space-folding domain operators follow the hg_sdf library by the demogroup Mercury. The sculpt-block idea of building form by adding and carving under a melt radius is the working model of digital clay tools, studied from Shader Park's composable API. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [SDF combinators](../Docs/Drawing/Combinators.md): the complete reference, including the machined joint family, gradient paint on merged fields, per-axis stretching, the infinite plane, and the quality dials.
- [Combining 3D features](../Docs/3D/Combining.md): what fields take (materials, shadows, environments) and where they differ from meshes.
- Worked examples: [`Examples/Shapes/Combinators`](../Examples/Shapes/Combinators/Sketch.swift) and [`CombinatorsGradient`](../Examples/Shapes/CombinatorsGradient/Sketch.swift) in 2D; in 3D, [`Examples/3D/Raymarching/RaymarchedSDF`](../Examples/3D/Raymarching/RaymarchedSDF/Sketch.swift), [`RaymarchedShapes`](../Examples/3D/Raymarching/RaymarchedShapes/Sketch.swift), [`RaymarchedSculpt`](../Examples/3D/Raymarching/RaymarchedSculpt/Sketch.swift), [`RaymarchedClay`](../Examples/3D/Raymarching/RaymarchedClay/Sketch.swift), [`RaymarchedDomain`](../Examples/3D/Raymarching/RaymarchedDomain/Sketch.swift), [`RaymarchedRadial`](../Examples/3D/Raymarching/RaymarchedRadial/Sketch.swift), [`RaymarchedPlane`](../Examples/3D/Raymarching/RaymarchedPlane/Sketch.swift), and [`RaymarchedEnvironment`](../Examples/3D/Raymarching/RaymarchedEnvironment/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 17, 3D, gently](17-3DGently.md) · Next: [Chapter 19, Depth and the iPhone as a sensor](19-DepthAndThePhone.md)
