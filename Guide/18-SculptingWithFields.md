#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 18</sup>

---

# 18. Sculpting with fields

<img src="Images/18-SculptingWithFields/Molten.jpg" alt="A pale mint sculpture like a settling drop of melted glass, glossy under studio light, one lobe drooping toward a dark floor that catches its soft shadow" width="560">

Chapter 13 treated shapes as outlines you cut and joined, like paper. This chapter treats them as something closer to wax: shapes that melt into each other, carve each other, and hold together as one surface no matter how you push them. The tool is the **signed distance field**, an idea you've already met twice without the name, and it ends in the sculpture above: one body made of four melted lobes, slowly breathing, orbitable with the mouse.

## A shape as a question

Chapter 12 defined a field as an answer at every point. A **signed distance field** is a shape stored that way. Ask any point of the canvas and it answers with one number, *how far is the nearest surface*. The sign carries which side you're on: positive outside, negative inside, zero exactly on the boundary.

<img src="Images/18-SculptingWithFields/FieldMap.jpg" alt="A distance field visualized: a melted circle-and-box shape in warm orange, surrounded by concentric cool bands of equal distance, with a bold dark line at distance zero" width="680">

That's the whole idea, and it's worth a slow look. The shape is not stored as an outline, and the *bold line* is only the places where the field happens to answer zero. Chapter 15 used this trick per pixel (a circle was "all the points within `radius`", and `smoothstep` softened its edge). What's new here is what the representation makes possible, because if two shapes are each a distance function, then *combining the answers* combines the shapes.

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

Run it and watch the seam. `SDF.circle` and `SDF.rect` are field *values*, like a `Shape` or a `Color`. From there `.at` moves one, `.colored` paints one, `.smoothUnion` merges two into a new field, and `drawSDF` rasterizes whatever field you hand it in a single pass. The knob `k` is the width of the melt, in canvas points:

<img src="Images/18-SculptingWithFields/MeltStrip.jpg" alt="The same orange and blue circles at four smoothing radii: touching hard at k = 0, necking together at 22, flowing into a peanut at 55, and fused into one capsule at 110" width="680">

At `k = 0` the union is hard, two shapes overlapping like Chapter 13. As `k` grows, the seam becomes a fillet, then a neck, then the pair is one body. Look at the colors, because the smooth union blends the two operands' colors across the melt, and that is what makes the result read as one object rather than a trick. This one knob is most of the medium, so put it on a `@Param` slider and you'll feel it immediately.

One habit is worth setting early, and it's that **order matters in the chain**. Every call wraps the field before it, so `circle.at(p).scaled(2)` scales the *moved* circle (it lands twice as far out), while `circle.scaled(2).at(p)` scales in place and then moves. Read chains inside out and they always make sense.

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

These are Chapter 13's booleans reborn on fields, plus two things outlines can't do. The smooth forms are one. The other is `morph`, which blends the *boundary itself*, so at `0.5` you get a genuinely in-between shape rather than a crossfade. Two modifiers round out the kit: `.rounded(12)` inflates any field with soft corners, and `.onion(8)` hollows it into a shell. And past the melted family there's a whole *machined* family (`chamferUnion`, `stairsUnion`, `columnsUnion`, plus engrave, groove, tongue, and pipe detailing) that shapes the seam like joinery instead of wax. The [combinators reference](../Docs/Drawing/Combinators.md#combining) has the full bench.

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

Everything drawable with a fill can join a block, including shapes the `SDF` type doesn't name (hearts, stars, trapezoids), and each call's own `fill` becomes its color in the melt. It reads like normal drawing, and the block simply holds the shapes open until it closes, then merges them all.

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

Try building that from triangle meshes and you'll appreciate what just happened: the two spheres aren't two surfaces cleverly joined, they are *one* surface, because the field underneath is one function. The leaf catalog matches the mesh primitives (sphere, box, torus, capsule, cylinder, cone, octahedron, and more, plus `line(from:to:radius:)`, a stroke between two points that's perfect for sketching limbs and branches for the melt to flesh out). Fields and meshes coexist in one scene and correctly hide each other, and the [combinators reference](../Docs/Drawing/Combinators.md#fields-3d) has the whole catalog.

## How the picture gets made

A mesh is triangles, and the GPU knows how to draw triangles. A field is just a function, so how does it become pixels? By *asking it the right question, repeatedly*. For each pixel, a ray leaves the camera, and the field is asked: how far is the nearest surface? The answer is a promise, nothing is closer than this, so the ray can safely hop exactly that far. Ask again, hop again:

<img src="Images/18-SculptingWithFields/MarchRay.jpg" alt="A diagram of sphere tracing: a ray from an eye crossing the canvas in shrinking hops, each hop bounded by a circle showing the distance the field reported, ending on a gray blob's surface" width="680">

The hops shrink as the ray nears a surface (watch them tighten as the ray passes over the lower shape) and grow again in open space, and the ray lands on the surface without ever stepping through it. This is called **sphere tracing**, and it's the second big advantage of the representation: the same number that let shapes melt is what steers the rays that draw them.

You get all of this without writing any of it. The one practical knob is `raymarchQuality(_:)`. Tracing costs by the pixel, so the live window traces at a resolution budget by default while exports always render at full quality. If a heavy field stutters while you sketch, `raymarchQuality(.performance)` loosens that budget further.

## Sculpting like clay

For forms you build up rather than compose, the `sculpt { }` block turns the operators into working state. Shapes `add()` on or `carve()` away, melting by the current `blend(_:)` amount, and the block reads top to bottom like a session at a potter's wheel:

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

Flip one `add()` to `carve()` and a bump becomes a dent, which is exactly the kind of edit live coding thrives on. A further set of distortions bends whole forms: `.twisted(1.2)` screws a shape around its axis, `.bent(0.6)` curls it, and `.displaced` / `.roughened` ripple or roughen the surface (the rock look). They're all safe to stack, because the tracer compensates for the distortion on its own.

## Folding space

The last trick is the strangest one. Instead of copying a shape, you can fold the *space it lives in*, so one shape answers for many:

<img src="Images/18-SculptingWithFields/DomainFold.jpg" alt="Three panels: an asymmetric cluster mirrored into a facing pair, the same cluster tiled into a three-by-three grid, and a petal fanned into a nine-fold rosette" width="680">

```swift
cluster.mirrored(x: true)                             // a facing pair
cluster.repeated(spacing: Vector2(88, 88), count: 1)  // a 3×3 tiling
petal.at(x: 82, y: 0).repeatedRadially(count: 9)      // a rosette
```

There is still only one cluster, because the domain operator rewrites each query point before the field answers, folding it across the mirror, wrapping it into a cell, or rotating it into a wedge. Copies are free, so a thousand-copy tiling costs what one copy costs. All three work in 3D too, where `repeatedRadially` fans a wedge around an axis and a mirrored melt becomes a symmetric creature. One honest caveat is worth knowing. The radial fold is exact when the repeated content is symmetric within its wedge, and an asymmetric cluster can show a faint seam where the wedges meet, which is why the rosette panel uses a symmetric petal.

## The finish

A field shades like a mesh, so all of Chapter 17 applies: `material(.jade)` gives a melt its glow, and `castShadows()` grounds it (a field even self-shadows, and trades shadows with the meshes around it). But there is one family of finishes Chapter 17 deliberately left for here, because it doesn't work without something this chapter's sculptures finally give it a reason to set up.

### Two numbers for most real surfaces

The materials in Chapter 17 were named looks: velvet, jade, toon. The **physically based** ones are different in kind. Instead of a name, you give two properties, and the renderer works out how light should behave:

```swift
material(.metal(roughness: 0.12))         // a metal, nearly polished
material(.dielectric(roughness: 0.4))     // a non-metal, satin
```

**Metal or not** is the first question, and it's close to binary in the real world. Metals tint the light they reflect (gold reflects gold) and have no color of their own underneath. Everything else, called a *dielectric* (plastic, glass, skin, paint, stone), reflects white highlights and shows its own color through them. **Roughness** is the second, and it's the one you'll actually reach for: how scattered the reflection is, from `0` for a mirror to `1` for chalk.

<img src="Images/18-SculptingWithFields/Roughness.jpg" alt="Five identical grey metal spheres in a row labeled 0.02, 0.15, 0.32, 0.6, and 1.0. The first is a dark mirror with a tiny sharp highlight, and each one after it has a broader, softer, paler highlight until the last is an almost flat matte grey" width="680">

That is one material with one number changed. The leftmost sphere is a mirror, so what you see on it is mostly a reflection of the room it's standing in, which is why it's dark with one small bright highlight. As roughness grows, that reflection smears out into a wide sheen, and by `1.0` it has spread so far that the sphere just reads as its average brightness. `fill` still sets the color, exactly as before; roughness only decides how the surface handles light.

There are ready-made ones for the common cases (`.brushedMetal`, `.polishedMetal`, `.smoothPlastic`, `.roughPlastic`), and they're all the same two properties underneath. Watch the naming, though: plain `.plastic` is one of the *stylized* finishes from Chapter 17, not a physically based one, so reach for `.smoothPlastic` when you want this family.

### Surroundings as the light

Here's the catch that makes this a Chapter 18 topic. A mirror reflects its surroundings, so **a physically based surface with no surroundings has almost nothing to work with** and goes dark and dull. Named lights don't fix it, because a point light is a point: it makes a highlight, not a reflection.

What fixes it is an **environment**: a photograph of a whole place, wrapped around your scene as a sphere, used as the light.

```swift
environment(.sunset)
material(.metal(roughness: 0.12))
drawSDF3D(body)
```

<img src="Images/18-SculptingWithFields/EnvironmentSky.jpg" alt="A chrome blob of three fused lobes over a grey-blue floor under a clear pale blue sky, its whole surface reflecting soft sky gradients" width="680">

<img src="Images/18-SculptingWithFields/EnvironmentSunset.jpg" alt="The same chrome blob in the same position, now under a warm evening HDRI of Venice. Ochre buildings and trees fill the background, and the buildings are clearly visible reflected in the left side of the blob" width="680">

Those two images are the same field, the same material, the same camera, and the same floor. The only difference is one word. Look at the left flank of the second blob and you can read the buildings in it, which is the whole idea in one glance: the surroundings *are* the reflection, and they are also the light. The floor is lit by the sky in the first and by an ochre evening in the second, without a single light being placed.

Twenty environments come curated. Eight of them (`.studio`, `.city`, `.courtyard`, `.forest`, `.interior`, `.night`, `.sunrise`, `.sunset`) are bundled, so they work offline and instantly; the other twelve download the first time you use one and cache from then on. They range enormously in real brightness, so each is exposed to a consistent level for you, and they pair well with `toneMap(.aces)` from Chapter 14 for a filmic rolloff on the highlights.

The first image uses none of them. **`.sky(...)`** builds a daylight sky at runtime with nothing to load:

```swift
environment(.sky(sunElevation: 0.35))       // no asset, and the sun can move
```

It takes a sun elevation and a `turbidity` for how hazy the air is, and because it's computed rather than loaded, you can animate the sun and watch the whole scene's light follow. It's the one to reach for when you want good lighting and don't want to think about assets at all.

Two knobs come up immediately in practice. An environment paints itself **behind** your scene as a backdrop, which is usually what you want, since the reflections then match what you can see. When you'd rather keep your own `background(_:)`, `.lightingOnly()` keeps the light and drops the picture. And `.backgroundBlur(_:)` softens just the backdrop, which pushes it back behind the subject; both figures above use a little.

`SDF3D.plane()` is worth knowing about here too, since it's an infinite floor you can merge into the field for true horizon-to-horizon self-shadowing.

## Mirrors that see off screen

Chapter 17 finished with screen-space reflections and an honest limit: they reflect what is on the screen, so they cannot show you anything the camera can't already see. `rayTracedReflections()` is the answer to that, and it works differently enough to be worth understanding.

Instead of searching the finished picture for what a reflection should show, it fires an actual ray off each reflective surface and asks what the ray hits, using the real geometry. Off-screen objects appear. Hidden faces appear. The underside of a ball resting on a mirrored floor appears, because the ray goes there and looks. It integrates into the environment lighting rather than sitting on top as a post-process, so a traced hit simply replaces what the environment would have contributed, and a ray that hits nothing shows the sky.

<img src="Images/18-SculptingWithFields/TracedMirror.jpg" alt="An orange sphere and a pale box on a nearly polished dark floor under studio lighting, with a blue sphere overhead cropped by the top of the frame. Both floor reflections are sharp, and the box's shows its underside" width="560">

Look at the box's reflection rather than the sphere's. You can see its underside, the face resting toward the floor, which the camera never sees from where it stands. That face exists in the geometry, so a ray sent to it comes back with an answer. A screen-space reflection has no pixels of that face to borrow, because the picture simply doesn't contain it, and has to approximate.

```swift
environment(.studio)
rayTracedReflections()          // needs a ray-tracing GPU; a no-op elsewhere
material(.metal(roughness: 0.08))
```

Three conditions come with it. It needs an `environment(_:)` to fall back to, it only affects physically based materials, and it needs a GPU that can trace rays. Every Apple silicon Mac can, though the M3 generation and later do it in dedicated hardware and earlier chips do it in software, so the same scene costs more frames on an M1 or M2. Anywhere it isn't available the call does nothing at all rather than failing, so a sketch that asks for it still runs and simply looks plainer, which is why you can leave the call in.

There's one behavior worth expecting rather than being puzzled by. Reflections are traced with a limited number of rays and cleaned up over time while the camera holds still, so a fresh view can look faintly noisy for a moment before it settles. Exports don't have that problem, because there Ollin averages several rays within each frame instead of across frames, which is also why a video export can't flicker.

When you want the map of which finish applies to which kind of geometry, meshes and fields differing in a few places, the [combining reference](../Docs/3D/Combining.md) is the table for it.

## Putting it together: molten

The finished piece is a single body of four melted lobes, twisted a little, finished as glass under studio light, breathing slowly over a floor that catches its shadow. Make `MySketches/Molten.swift`:

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

The whole sculpture is four primitive lobes, three smooth unions, one twist, and a glassy finish, and the breathing comes from `signedNoise` easing the first melt radius in and out. Notice the mesh floor and the traced field sharing the frame. The field drops its shadow onto the plane, and each would hide the other if they overlapped. That's the everyday reality of this chapter: fields aren't a separate world, they're one more kind of thing your scene draws.

Then make it yours:

- Replace a lobe with `SDF3D.line(from:to:radius:)` and grow the drop a limb. A few chained lines plus a big `k` is how creatures start.
- Wrap the body in `.repeatedRadially(count: 5)` (offset it from the axis first) and the drop becomes a chandelier.
- Trade the glass for `.metal(roughness: 0.15)` with `environment(.sunset)`, and add `rayTracedReflections()` if your Mac traces.
- Carve it, since one `smoothSubtract` of a big sphere turns the sculpture into a grotto.

## Where this comes from

Distance fields as a drawing medium are the craft of the demoscene and Shadertoy communities, and above all of Inigo Quilez, whose catalogs of distance functions, the polynomial smooth minimum, and raymarching articles underlie nearly everything here and are credited throughout Ollin's implementation. Sphere tracing was formalized by John C. Hart in 1996, and the blobby, merging-spheres idea is much older, going back to Jim Blinn's 1982 "blobby model" and the metaballs of 1980s Japanese graphics research. The space-folding domain operators follow the hg_sdf library by the demogroup Mercury. The sculpt-block idea of building form by adding and carving under a melt radius is the working model of digital clay tools, studied from Shader Park's composable API. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [SDF combinators](../Docs/Drawing/Combinators.md): the complete reference, including the machined joint family, gradient paint on merged fields, per-axis stretching, the infinite plane, and the quality dials.
- [Combining 3D features](../Docs/3D/Combining.md): what fields take (materials, shadows, environments) and where they differ from meshes.
- [Environment lighting](../Docs/3D/3D.md#environment-lighting): all twenty curated environments listed by mood, which eight are bundled offline, `highRes` backdrops, loading your own `.exr` or `.hdr`, where downloads cache, and the full procedural-sky knobs.
- [Physically based materials](../Docs/3D/3D.md): the metallic-roughness model in full, plus the ready-made metals and dielectrics and how they combine with the stylized finishes.
- Worked examples for this section: [`Examples/3D/Materials/PhysicalMaterials`](../Examples/3D/Materials/PhysicalMaterials/Sketch.swift), [`Examples/3D/Environments/ImageBasedLighting`](../Examples/3D/Environments/ImageBasedLighting/Sketch.swift), [`EnvironmentGallery`](../Examples/3D/Environments/EnvironmentGallery/Sketch.swift) (steps through all twenty), and [`ProceduralSky`](../Examples/3D/Environments/ProceduralSky/Sketch.swift).
- Worked examples: [`Examples/Shapes/Combinators`](../Examples/Shapes/Combinators/Sketch.swift) and [`CombinatorsGradient`](../Examples/Shapes/CombinatorsGradient/Sketch.swift) in 2D; in 3D, [`Examples/3D/Raymarching/RaymarchedSDF`](../Examples/3D/Raymarching/RaymarchedSDF/Sketch.swift), [`RaymarchedShapes`](../Examples/3D/Raymarching/RaymarchedShapes/Sketch.swift), [`RaymarchedSculpt`](../Examples/3D/Raymarching/RaymarchedSculpt/Sketch.swift), [`RaymarchedClay`](../Examples/3D/Raymarching/RaymarchedClay/Sketch.swift), [`RaymarchedDomain`](../Examples/3D/Raymarching/RaymarchedDomain/Sketch.swift), [`RaymarchedRadial`](../Examples/3D/Raymarching/RaymarchedRadial/Sketch.swift), [`RaymarchedPlane`](../Examples/3D/Raymarching/RaymarchedPlane/Sketch.swift), and [`RaymarchedEnvironment`](../Examples/3D/Raymarching/RaymarchedEnvironment/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 17, 3D, gently](17-3DGently.md) · Next: [Chapter 19, Depth and the iPhone as a sensor](19-DepthAndThePhone.md)
