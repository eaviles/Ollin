#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 21</sup>

---

# 21. 3D, gently

<img src="Images/21-3DGently/Plaza.jpg" alt="A small sculpture court at golden hour: a glossy teal knot, a deep red vase, a sparkling car-paint sphere, an orange faceted gem, and one wireframe sphere, each on a pale plinth, casting long soft shadows" width="560">

Every sketch so far lived on a flat canvas. This chapter adds the third axis, and the surprising part is how little changes. You keep the same `draw()`, the same `fill` and `translate`, and the same motion by default. What's new is a camera, a handful of solid shapes, and light. By the end you'll have built that sculpture court, and you'll be able to grab it with the mouse and walk around it.

## The world behind the canvas

3D drawing doesn't happen *on* the canvas. It happens in a world of its own, and a **camera** photographs that world onto the canvas each frame. The world has three axes, where x runs right, y runs **up**, and z runs toward you. Positions in it are `Vector3`s, which are exactly [Chapter 10](10-Vectors.md)'s `Vector2` with a third number:

```swift
let p = Vector3(2, 1, -3)     // 2 right, 1 up, 3 away
```

Two habits from the canvas need resetting. First, in the world **y goes up**, the opposite of the canvas, where y grows downward, so a tower rises toward positive y. Second, there are no pixels here. World distances are **world units**, and a unit means whatever your scene wants it to mean. That's a meter for a room, or a sphere-width for an abstract piece. Sizes on screen come from where the camera stands.

## A camera and a sphere

A sketch becomes 3D by setting a camera. That's the entire opt-in, and the friendliest camera is one call:

```swift
import Ollin

final class FirstSphere: Sketch {
    override func draw() {
        background(Color(hex: 0x10141B))
        cameraShowcase(radius: 5)
        fill(Color(hex: 0xF25F5C))
        drawSphere(radius: 1)
    }
}
```

<img src="Images/21-3DGently/FirstSphere.jpg" alt="A single coral-red sphere, softly shaded, floating on a near-black background" width="560">

Run it live and drag. The sphere isn't a flat disc, it's a shaded ball, and the mouse orbits around it. `cameraShowcase` gives you the camera most 3D sketches want with no wiring at all. It circles the scene slowly on its own, and you can grab it any time. Drag to orbit, scroll to move closer or farther, and right-drag to slide the view. After ten seconds of being left alone it drifts back to the opening shot and resumes. That way a sketch on a wall keeps moving and a curious viewer can always explore. When you'd rather the camera hold still until you move it, `cameraControl()` gives you the same gestures without the automatic orbit.

Notice you set up no lights. Solids are lit by a default rig automatically, so a shape looks three-dimensional out of the box. We'll take the lights over ourselves in a few pages.

The camera's home position is three numbers. The picture to keep in mind is an eye riding a sphere around a target:

<img src="Images/21-3DGently/Orbit.jpg" alt="A diagram of the orbiting camera: a small camera body on a gray ring around a dark knot, with a dashed sight line labeled radius, a ground arc labeled azimuth, and a climbing arc labeled elevation" width="680">

**Radius** is how far away the eye sits. **Azimuth** is how far around it has walked, an angle in radians like every angle since [Chapter 3](03-MotionAndTime.md). **Elevation** is how high it has climbed above the horizon. Every camera motion in this chapter, the automatic orbit and your mouse drags alike, is just these three numbers changing. The camera is per-frame state, like the things you draw, so it's set inside `draw()`.

> **Swift note.** `cameraShowcase(radius: 5)` fills in defaults for everything you don't mention: target, elevation, lens. The framing arguments only apply on the first call; after that, the viewer and the auto-orbit own the pose, which is why passing the same numbers every frame doesn't fight the mouse.

## Depth is real

Place a few spheres at different distances and the second new thing appears:

```swift
override func draw() {
    background(Color(hex: 0x10141B))
    cameraShowcase(target: Vector3(0, 0.4, -1), radius: 13,
                   elevation: 0.3, fieldOfView: .pi / 4)

    fill(Color(white: 0.75))
    drawPlane(width: 40, depth: 40)

    for i in 0 ..< 6 {
        withState {
            translate(Double(i) * 0.9 - 2.1, 0.7, 2.4 - Double(i) * 2.0)
            fill(Color(hue: 0.55 + Double(i) * 0.06, saturation: 0.55, brightness: 0.95))
            drawSphere(radius: 0.7)
        }
    }
}
```

<img src="Images/21-3DGently/DepthRow.jpg" alt="Six spheres in a row marching away from the camera across a pale floor, each one smaller and partly hidden behind the one before it" width="560">

Three things happened at once. `translate` grew a third argument, so it moves things in space now. The spheres get smaller as they get farther away, because the camera has perspective. And each sphere *hides* the ones behind it. That hiding is the **depth test**, which means the renderer remembers, per pixel, how far away the nearest surface was, and anything farther loses. You never sort anything by hand. Draw in any order and the world works it out.

`drawPlane` is the floor, a flat sheet on the ground, and it's the stage most scenes stand on. `fieldOfView` is the lens. Smaller angles are telephoto, which reads calm and flat and suits product shots, while bigger angles are wide-angle, dramatic and stretched at the edges. The default is a fairly wide lens, so this sketch tightens it to a quarter turn.

## A catalog of solids

The catalog runs well past spheres and boxes. Each of these is one call, shaded and depth-tested like everything else:

<img src="Images/21-3DGently/Catalog.jpg" alt="A four-by-four grid of labeled solid primitives: box, sphere, icosphere, cylinder, cone, capsule, rounded box, torus, the four larger Platonic solids, pyramid, helix, torus knot, and plane" width="560">

The names are what you'd guess: `drawBox(size: 1.5)`, `drawTorus(radius: 0.6, tube: 0.25)`, `drawCone(radius: 0.7, height: 1.5)`, and so on. Past the everyday ones there's also a small shape *factory*. `drawSupershape` and `drawSuperellipsoid` sweep whole families of organic and gem-like forms from a few numbers. `drawExtrude` pushes any flat 2D shape into depth. `drawLathe` revolves a side profile into a vase, and `drawTube` sweeps a tube along any 3D path. The `3D/ShapeFactory` example is the tour.

Under every one of these calls is a **`Mesh`**, the shape as a cloud of triangles, which is what all 3D surfaces are made of here. The `draw*` calls rebuild their mesh every frame, which is fine for a box and wasteful for a dense knot. The pattern for anything heavy is the one you know from images and fonts, build once, draw forever:

```swift
let knot = Mesh.torusKnot(radius: 0.62, tube: 0.2, segments: 220, sides: 14)
// …each frame:
drawMesh(knot)
```

## Placing things: transforms compose

You've been using `withState` and `translate` since [Chapter 6](06-GridsAndRepetition.md), and in 3D they're joined by `rotateX`, `rotateY`, `rotateZ` (each spins around one axis), and the same `scale`. The important idea hasn't changed: **every move builds on the moves before it**. In 3D that compounding is where structures come from:

```swift
override func draw() {
    background(Color(hex: 0x10141B))
    camera(.orbiting(target: Vector3(0, 4.4, 0), radius: 15,
                     azimuth: 0.7, elevation: 0.22, fieldOfView: .pi / 4))

    // The center post the treads wind around.
    withState {
        translate(0, 4.4, 0)
        fill(Color(white: 0.35))
        drawCylinder(radius: 0.22, height: 9.4)
    }

    for i in 0 ..< 26 {
        translate(0, 0.34, 0)          // each tread builds on the last:
        rotateY(0.34)                  // a step up and a turn
        withState {
            translate(1.25, 0, 0)      // out to the side, this tread only
            fill(Color(hue: 0.55 + Double(i) * 0.012, saturation: 0.5, brightness: 0.95))
            drawBox(width: 2.1, height: 0.15, depth: 0.85)
        }
    }
}
```

<img src="Images/21-3DGently/Stairs.jpg" alt="A spiral staircase built from twenty-six colored slabs winding up a dark central post, cyan at the bottom shading to pink at the top" width="560">

Read the loop closely, because it uses both halves of the tool. The climb and the turn sit *outside* any `withState`, so they accumulate, step after step, and that accumulation is the spiral. The sideways step to hang each tread off the post sits *inside* a `withState`, so it applies to one tread and is forgotten. One repeated move-and-turn, and a staircase happens.

This sketch also shows the plain `camera(.orbiting(...))` call, a fixed pose you specify completely, with no mouse involved. Reach for it when you want to compose a shot exactly, and for `cameraShowcase` when you want the scene alive and explorable.

Nesting `withState` blocks builds solar systems. Translate to a planet and draw it, then translate again and draw its moon, and the moon inherits the planet's motion for free. The `3D/Transforms` example is exactly that, three transforms deep.

## Light, by playing

Everything so far wore the default lighting. Taking over is one call before you draw, and the fastest way to feel what lighting does is to swap whole moods:

<img src="Images/21-3DGently/PresetTour.gif" alt="The same still life of a sphere, box, and torus relit once per second by six lighting presets, from soft neutral studio light to a single harsh noir key to dim blue moonlight" width="480">

```swift
lightingPreset(.goldenHour)     // one call relights the whole scene
```

The six presets (`.standard`, `.threePoint`, `.goldenHour`, `.noir`, `.studio`, `.moonlight`) are each an ambient wash plus a few placed lights, tuned like film rigs. Play with them first, because the mood of a 3D piece is mostly its light. Swapping presets on a knob teaches you more in a minute than any paragraph.

When you're ready to place your own, there are three kinds of light, and one scene can carry all of them:

```swift
ambientLight(Color(white: 0.1))                                     // a floor for the shadows
directionalLight(Color(hex: 0xFFD9A8), direction: Vector3(-0.6, -1, -0.35))
pointLight(Color(hex: 0x39D8E8), at: Vector3(2.7, 1.7, 1.9))
spotLight(Color(hex: 0xE85FD0), at: Vector3(-3.4, 4.6, 2.6),
          direction: Vector3(0, -1, 0), angle: .pi / 5, penumbra: 0.4)
castShadows()
```

<img src="Images/21-3DGently/LightKinds.jpg" alt="A sphere, box, and torus on a pale floor lit three ways at once: warm directional light from the left, a cyan point light marked by a small ball, and a magenta spot pooling on the floor" width="680">

A **directional** light is the sun, parallel rays from a direction, with no position of its own, lighting everything evenly. A **point** light is a bulb at a place, so nearby things catch it strongly. A **spot** is a point light narrowed to an aimed cone, with a `penumbra` for how soft its edge falls. The `ambientLight` is a flat wash added to every surface so the unlit sides aren't pure black. Each light takes an `intensity`, and in the figure each has its own color so you can see who's doing what. The warm key shades everything, the cyan bulb blooms on the surfaces near it, and the magenta cone pools on the floor.

Two smaller dials finish the surface's response to light: `specular(_:)` sets how strong the highlight is (0 is matte) and `shininess(_:)` how tight. But mostly you won't set those by hand, because of the materials library below. First, though, there is that one extra line in the listing above to account for.

## Shadows, and what they tell you

**`castShadows()`** is what plants objects in a scene. Without it, a floating sphere and a resting sphere look the same, because nothing in the picture says where either one is. A shadow answers that.

```swift
directionalLight(.white, direction: Vector3(-0.22, -1, -0.16))
castShadows()
shadowSoftness(1)

drawPlane(width: 14, depth: 8)                                  // something to catch them
withState { translate(0, 3.4, 0); drawSphere(radius: 0.5) }     // and something to cast one
```

<img src="Images/21-3DGently/Shadows.jpg" alt="Four identical orange spheres over one pale floor, each higher than the last, their four shadows in a row on the floor. The leftmost sphere rests on the floor and its shadow is a tight dark ellipse; each shadow further right is a little smaller, further from its sphere, and visibly blurrier" width="680">

Four identical spheres, one floor, one light. You know instantly which one is resting and which is highest, and the only thing telling you is the shadow. Two things change as a sphere climbs. The shadow drifts away from it, and the edge gets softer. The one on the left, touching down, has a tight ellipse with a crisp edge. The one on the right, three and a bit units up, has a blurry patch with a wide grey skirt.

That softening is worth knowing about because it is the thing that makes rendered shadows look real. Shadows here are **contact-hardening** by default, so they are sharp where an object meets a surface and softer as the shadow falls away. `shadowSoftness(_:)` sets how strong the effect is, from `0` for a hard edge, the classic look, through the `0.5` default to `1`. The figure asks for `1` so the difference is easy to see at this size. At the default it is subtler and usually what you want.

Some practical notes, in the order they tend to bite:

- **You need something to catch a shadow.** A sphere alone in space casts into nothing. A floor, or another object, is what makes the shadow visible.
- **It's opt-in and per-frame.** A sketch that never calls `castShadows()` pays nothing at all, so shadows cost you only when you ask. Call it in `draw()` alongside the lights, and `noShadows()` turns it back off.
- **One light does the casting**, chosen for you. It's the first directional light, or a spot if there's no directional, or a point light failing that. A glowing panel can cast too, which is the next section. The default rig's key light is directional, so a scene you haven't relit already works.
- **Nothing needs aiming.** The shadow's frame auto-fits around whatever the camera is looking at.

The three kinds of light cast by different routes, which mostly matters because it explains the cost. A directional or spot light renders the scene once from the light's own viewpoint and darkens whatever that view can't see. A point light casts in every direction at once. So on Apple silicon it traces actual rays from each lit pixel toward the light, which is exact, with no bias artifacts, and the most expensive of the three. On a GPU that can't trace rays it falls back to a depth map sampled by direction. Point shadows still work everywhere, and your sketch doesn't change either way.

If a penumbra looks grainy rather than smooth, that's the sample count, not the softness. `shadowQuality(.detail)` asks for more samples relative to whatever GPU is running, and `shadowSamples(16)` sets an exact number.

There is one place even a good shadow map falls short, and it is the most important few pixels in the picture. That's the exact line where an object touches the ground. A map has finite resolution, and the bias that keeps its speckle off nudges its shadow slightly away from the caster. The last sliver of contact opens up, and a resting box can read as floating a hair above the floor. **`contactShadows()`** closes that seam. For each pixel the renderer walks a short ray toward the casting light through the scene's own depth. It darkens the pixel where something nearby blocks the way, which draws the fine dark line a map can't hold at any resolution.

```swift
castShadows()
shadowSoftness(0.9)   // a wide, soft look: lovely, but every base goes loose
contactShadows()      // the short march that seats them again
```

<img src="Images/21-3DGently/Seated.jpg" alt="An orange box, a blue sphere, and a yellow cylinder resting on a pale floor under wide soft shadows, each base hugged by a fine dark seam that pins it to the ground. A small white sphere hovers at the upper left with only a soft detached blob of shadow on the floor below it, and no seam" width="680">

The three resting solids each get the tight dark line at their base. The hovering sphere, the one thing genuinely off the ground, gets only the soft drifted blob a real gap produces. That difference is the whole feature. It refines whatever caster `castShadows()` picked, works on any Mac, and takes one optional dial. `contactShadows(length: 8)` sets the ray's reach in world units, and with no length a short reach comes from the scene's own scale. The honest limit is that the march can only consult what the camera sees. Off-screen geometry casts no contact shadow, and a curved surface can pick up a touch of extra shading just inside its silhouette. For the seam under a resting thing, which is what it's for, it simply works.

## A light with a body

The three kinds above are infinitesimal points. A fourth family gives light a *body*. `rectLight` is a glowing panel, a softbox or a window. `diskLight` is a glowing circle, and `tubeLight` is a glowing cylinder strung between two points, a neon. `intensity` means something different here, and it's worth a moment. It is the glow of the surface itself, so brightness falls off with distance on its own. A bigger panel pours more light at the same glow, and a thin neon needs an intensity in the tens, because a thin tube is a small piece of sky.

What a body buys you is easiest to see by changing its size and nothing else:

```swift
let side = 1.0 + pingPong(over: 6) * 2.2
let facing = Vector3(0.55, -0.58, 0.6)          // aimed down across the set
rectLight(Color(hue: 0.09, saturation: 0.22, brightness: 1.0),
          at: Vector3(-3.4, 4.8, -1.2), direction: facing,
          width: side, height: side, intensity: 70 / (side * side))
castShadows()
```

<img src="Images/21-3DGently/LightWithABody.gif" alt="A teal pillar and an orange sphere on a gray floor under one warm glowing panel that slowly grows and shrinks. When the panel is small the sphere's highlight is a tight spot and both shadows are crisp; as it grows the highlight widens into a sheen, the shading wraps, and the shadows spread into soft pools while the scene's overall brightness stays the same" width="560">

The listing divides the panel's glow by its area as it grows. The light poured on the set never changes, so you can watch what size alone does. Three things move together. The highlight on the sphere is the panel's own reflection, so it grows from a small window into a broad sheen. The shading wraps further around each form, because more of each surface can see some part of the panel. And the cast shadows, sharp when the panel is small, spread into soft-edged pools. They stay crisp where the box meets the floor and widen the farther they fall. The size of the light is the softness of the picture, and here it's one number.

Shadows work the way the last section said, with the panel's size standing in for a light's position. A rect or disk panel is picked as the caster when no punctual light claims the job, and its penumbra comes from the panel's real extent, nothing to set. `shadowSoftness(_:)` scales that extent rather than some separate size, so `0` is hard, the `0.5` default is the panel's true size, and `1` is twice as soft. A tube never casts. It glows in every direction, so there is no side to draw a shadow from. One practical note comes from the figure's own listing. Lights are invisible, so the glowing slab you see is a drawn prop, placed a step *behind* the emitting plane. A casting panel treats any geometry in front of that plane, its own prop included, as an occluder.

The `3D/Lighting/AreaLights` example stages all three shapes over a glossy floor. Put it beside `3D/Lighting/Lighting` and the difference between a bulb and a panel is the whole studio-photography look. `3D/Lighting/AreaShadows` is the breathing softbox.

## The shape of the throw

A bare point light pours the same brightness in every direction, and a spot is just that pour with a cone cut into it. Real fixtures are choosier. A recessed downlight pools a hot disc with a faint ring of spill around it. A street lamp throws sideways in two wings, so the bright spot isn't the foot of its own pole. A wallwasher climbs the wall and leaves the room alone. Lighting manufacturers measure exactly where each fixture sends its light. They publish the measurement as an **IES file**, a small text file of brightness-by-angle, and a light can wear one:

```swift
let ring = IESProfile(string: ringFile)!     // or IESProfile(resource: "downlight", in: .module)!

pointLight(Color(hue: 0.09, saturation: 0.35, brightness: 1.0),
           at: Vector3(-2.6, 2.4, 0.4), intensity: 1.4, profile: ring)

let rock = sin(loopProgress(over: 6) * .tau) * 0.16
spotLight(Color(hue: 0.12, saturation: 0.25, brightness: 1.0),
          at: Vector3(3.6, 4.6, 4.2), direction: Vector3(-0.32, -0.66, -0.55),
          angle: 0.85, penumbra: 0.12, intensity: 1.25,
          cookie: window, roll: rock)
```

<img src="Images/21-3DGently/ShapedLight.gif" alt="A dark room with a sphere and a low slab. On the left an orange downlight pools a hot disc around the sphere with a faint ring of spill just outside it. On the right, warm window panes with a cross of mullion shadow lie across the floor and climb over the slab, rocking slowly from side to side" width="560">

The left pool is the profile at work, a hot center, a dip, then the spill ring, all read from a dozen numbers in the file. The profile's `0°` aims along the light's axis. A spot uses its `direction`, and a point light takes an `axis:`, straight down unless you say otherwise. Its brightest direction is normalized to `1`, so `intensity` still means what it always means, and anywhere the file didn't measure is dark, exactly as the fixture is. Parse the file once in `setup()` and keep it, since it's plain data. `IESProfile(resource:in:)`, `(contentsOf:)`, `(data:)`, and `(string:)` all read the same format. The throw is the fixture's signature, and the file is how you borrow a real one.

The window on the right is the second shaper, a **cookie**, an image a spot projects through its cone. Stage crews call the physical version a gobo, a stencil slid in front of the light. `LightCookie(image)` wraps any `Image` once, in `setup()`. Black blocks, white passes, and color tints like a gel. The image's edges land at the spot's outer cone, so a wider cone throws the same picture larger. The `roll:` in the listing is what rocks the panes. One knob spins an asymmetric profile and the cookie together about the beam, the way a fixture turns in its yoke.

Two habits worth keeping. A profile ends where its measurements end, so a downlight file that stops at 90° sends nothing above the fixture's own horizon. To wash a wall, tilt the light's `axis:` at it, the way the real fixture would be aimed. And both shapers are made-once values. The profile parses its file and the cookie resamples its image at construction, so build them in `setup()` and hand the same value to the light every frame. The `3D/Lighting/LightShaping` example stages a downlight, a batwing, a wallwasher, and this same window over one floor. Its three `.ies` files ride beside the sketch as bundled resources.

## Air you can see

Everything so far shows a light only where it lands. Real air shows the light on its way. Dust and haze catch a beam mid-flight, which is why a projector's cone hangs visibly over a cinema audience. It's why sun through a window is a slanted block of bright air. Two calls give a scene that air.

```swift
fog(Color(hex: 0xB4BDC9), density: 0.16, heightFalloff: 0.55)
```

`fog` fades every surface toward its color with distance, so near things stay crisp while far things dissolve, and depth reads at a glance. `density` is the thickness. The `heightFalloff` thins it with altitude, which is the morning-mist look, mist pooling low while tall things rise clear of it. It costs almost nothing, since the fade is an exact formula rather than a blur pass, so animating the density is just a number moving. The `3D/Effects/Fog` example is a colonnade standing in exactly this mist.

Fog paints every distance toward one color, which is right for a room. Outdoor air is choosier. It takes the blue out of a far ridge's own light, and it adds sunlight scattered into the path, blue from the side, brighter and whiter toward the sun. That is aerial perspective, the cue that makes mountains read as mountains, and it needs to know where the sun sits. So first give the scene a sky. `environment(.sky)` wraps the world in a computed one, with `turbidity` for how dusty the air is and `sunElevation` for how high the sun rides. An environment can light a whole scene, which the materials run in [Chapter 25](25-SculptingWithFields.md) takes up. Here its job is handing the haze its sun, and with the sky in place the perspective itself is one call:

```swift
environment(.sky(turbidity: 2.4, sunElevation: 0.34))
aerialPerspective()
```

<img src="Images/21-3DGently/DistantAir.jpg" alt="A file of dark ridgelines stepping away under a pale sky, each silhouette a step paler and bluer than the one in front, the farthest melting into the horizon, the air brightening toward the sun on the right" width="680">

With a `.sky` environment it follows the sky's own sun, rotation and all, so dropping the sun to the horizon reddens the haze by itself. `density` is how much air the scene spans, and bare it sizes itself to the camera framing. `haziness` trades the crisp blue of a clear day for the gray veil and sun halo of a humid one. It replaces `fog` for the frame, the last call wins, and the beams below ride it exactly as they ride fog. The `3D/Effects/AerialPerspective` example puts all of it on knobs.

```swift
castShadows()
volumetricLight()
fog(Color(hex: 0x0A0E18), density: 0.02)   // a whisper of haze for the beams to live in
```

`volumetricLight()` is the beam half. It watches the air along every line of sight and adds the light the haze scatters toward you, so directional and spot lights become *visible in flight*. The point is that everything a light already carries shapes its beam. The spot's cone becomes the projector cone. A cookie's panes read as tilted bars of bright air before they land as a window on the floor, and an IES profile's throw shows its real shape. And with `castShadows()` on, anything standing in the beam carves a dark shaft out of it, the crepuscular rays of a forest morning.

<img src="Images/21-3DGently/VisibleAir.jpg" alt="A dark set under a warm window-gobo beam slanting down from the upper left: the panes read as bars of bright air, land as a window of light on the floor, and a cylinder, sphere, and box carve dark shafts out of the beam. A faint cool beam crosses low behind the props" width="680">

The `anisotropy` knob runs −1…1 and sets how strongly the haze throws light forward. Near 1, a beam flares when the view swings toward its source, the headlights-in-fog effect. At 0 it glows evenly from every side. And the two calls compose either way. With `fog`, the beams live in the fog's own thickness. Without it, the air stays clear and *only* the beams appear, which is the dark-stage look of `3D/Lighting/VolumetricLight`. **The air is part of the scene, and light crossing it is something you can draw.**

One habit is worth knowing. The beam march has a quality dial like the shadows do, `volumetricQuality` with three tiers. The default already does the right thing, frame-rate-safe live, lifted to full quality on export.

## Materials

A material is a surface's whole way of catching light, picked by name. The color still comes from `fill`; the *finish* comes from `material`:

```swift
fill(Color(hex: 0x2C8C86))      // the color
material(.velvet)               // the finish
drawSphere(radius: 1)
```

<img src="Images/21-3DGently/MaterialRow.jpg" alt="Ten spheres in the same teal, each with a different finish: matte, plastic, glossy, iridescent, soap bubble, velvet, jade, toon, gooch, and glitter" width="680">

That's ten finishes on one color. The library runs from matte through glossy to the showpieces. `.iridescent` and `.soapBubble` shift hue as the view moves, `.velvet` glows at the edges, and `.jade` lets light through thin parts. `.toon` and `.gooch` are the stylized cartoon and warm-to-cool looks, and `.glitter` is full of tiny mirror flakes that flash as anything moves. `material(_:)` is drawing state like `fill`, saved by `withState`, so every shape in a frame can wear its own.

A `Material` is also a plain value you can tweak. Car paint is the classic recipe, gold flakes over a deep red:

```swift
var paint = Material.glitter
paint.sparkleColor = Color(hue: 0.12, saturation: 0.75, brightness: 1)
material(paint)
fill(Color(hue: 0.02, saturation: 0.8, brightness: 0.4))
drawSphere(radius: 0.62)
```

There's a further tier, the physically based metals and plastics (`material(.metal(roughness: 0.2))`), that really comes alive once a scene has surroundings to reflect. That's the next chapter's territory, where environments light the scene, so treat it as a pointer for now.

## Shading from a picture: matcaps

Matcaps are the shortcut of the sculpting world. Instead of lights and materials, the entire look, lighting included, is painted into one photograph of a sphere. Every surface point borrows the color the sphere would have there.

```swift
matcap(.chrome)
drawMesh(knot)
```

<img src="Images/21-3DGently/MatcapRow.jpg" alt="The same knot wearing four matcaps: reflective chrome, brown terracotta clay, red car paint, and a flat toon look" width="680">

One call, no lights to place, and the look is total, from chrome and clay to car paint and cel shading. It works by asking, for each point on the surface, which way that point is facing relative to you. Then it reads the color from the matching spot on the sphere picture. Point straight at the camera and you get the middle of the picture. Face away toward the edge and you get the rim. Because the picture was lit once, all of that lighting comes along for free. That's why the highlights slide as the view turns, and why it reads as a real material rather than a paint job.

The trade is the same fact seen from the other side. **A matcap ignores your lights, your `material(_:)`, and your shadows**, because it isn't lit at all. The light is a photograph. That makes matcaps a separate axis rather than another finish. They are the wrong choice when an object needs to belong to a scene, matched to its lighting and grounded by a shadow. They are the right one when you want a good-looking surface with no lighting work, which is most of the time you're sketching a form.

There are 26 built in, real studio captures grouped by family. There are metals like `.chrome` and `.bronze`, clays like `.terracotta` and `.sage`, ceramics like `.pearl`, and translucents like `.wax`. Then there is the neutral studio set, `.toon` and `.toonDark`, and a handful of diagnostic ones, `.checkNormal` and `.checkGradient`, meant for reading geometry rather than looking good. Beyond those, `matcap(loadImage("my-matcap.png"))` wears any sphere image you find or paint. `Matcap.shaded(baseColor:metallic:roughness:)` bakes one on the spot with no asset at all, which is the option to reach for when you want a specific color and don't want to ship a file.

Two smaller things. The current `fill` tints the result, so keep it `.white` to see a matcap as captured. And `matcap(_:)` is drawing state like `fill`, so `withState` scopes it and `noMatcap()` returns to the lit path.

## A mesh from a file

Any model you make in a 3D tool can join a sketch. `loadMesh` reads the common formats (`.usdz`, `.obj`, `.gltf`/`.glb`, `.stl`, `.ply`) into a `Mesh`, materials and textures included:

```swift
final class Loaded: Sketch {
    var model: Mesh?

    override func setup() {
        model = loadMesh("/Users/you/Downloads/rubber-duck.usdz")?.normalized(scale: 3)
    }

    override func draw() {
        background(Color(hex: 0x10141B))
        cameraShowcase(radius: 6)
        if let model {
            fill(.white)
            withState { rotateY(time * 0.3); drawMesh(model) }
        }
    }
}
```

The one habit that saves confusion is **`normalized(scale:)`**. A file arrives at whatever size and position its author saved, anywhere from millimeters to kilometers. Normalizing recenters it and scales its longest side to the world units you ask for. Keep the `fill` white so the model's own colors show, because a colored fill tints it. Models you build yourself are yours to ship, while downloaded ones carry licenses worth checking before you bundle them.

> **Swift note.** `loadMesh(...)?.normalized(scale: 3)` chains with `?.` because loading can fail: if the file isn't there, `loadMesh` returns `nil`, the chain stops, and `model` stays `nil`. The `if let model` in `draw()` then simply skips drawing, so a missing file never crashes the sketch.

`loadMesh` deliberately flattens a file into one mesh you place yourself. Sometimes the file *is* the placement: a whole scene composed in the design tool, with a camera framing it and lights already set. For that there's `loadScene`, which keeps the file's structure instead of merging it:

```swift
stage = loadScene("Stage.gltf")!            // in setup()

camera(stage.camera ?? .orbiting(radius: 6))   // the file's own framing
for l in stage.lights { light(l) }             // and its lighting
stage["sculpture"]?.rotate(deltaTime, axis: .unitY)
drawScene(stage)                               // every node, in its authored place
```

A scene is a tree of named nodes, and everything unpacks into things you already know. The file's camera is a `Camera3D`, its lights are `Light`s, and each node's geometry is a `Mesh`. `drawScene` draws the whole layout where the tool put it. `stage["sculpture"]` reaches one node by name, so a single piece moves while the rest holds still. Bring the set over from the design tool, and keep the choreography in the sketch. The `3D/Geometry/LoadedScene` example is a small stage to poke at, and [Scenes](../Docs/3D/Scenes.md) has the details.

If the file was animated in the tool, that motion carries over too. `stage.animations` holds the authored keyframe tracks, and applying one poses the scene at whatever moment you ask for:

```swift
if let spin = stage.animation("spin") {
    stage.apply(spin, at: time.truncatingRemainder(dividingBy: spin.duration))
}
```

The file remembers its motion; the sketch decides when time passes. `apply` takes any time you hand it, so wrapping `time` loops the animation, `time * 0.5` plays it at half speed, and a knob's value scrubs it. The `3D/Geometry/AnimatedScene` example plays a small orrery's authored spin this way, one seamless 8-second lap.

Tracks like the orrery's move whole nodes, rigid pieces on a hierarchy. A file can also carry motion that bends the geometry itself. A *skin* ties each vertex to a few joint nodes with blend weights, so a blade of kelp or an arm flexes smoothly as its joints turn. *Morph targets* store alternate shapes for a mesh, and the node's `weights` mix them, the way faces animate between expressions. Both play through the same `apply`, and `drawScene` poses them without any extra calls. The `3D/Geometry/SkinnedScene` example is a small tidepool doing both at once, kelp swaying on skins while an anemone pulses on two morph targets. And since `weights` is just a node property, `tank["anemone"]?.weights = [1, 0]` poses a blend shape from any signal you like.

Whether a mesh came from a file or a generator, there are two other ways to dress it besides lighting a solid surface.

<img src="Images/21-3DGently/SurfaceKinds.jpg" alt="Three spheres side by side: a solid glossy teal one, the same sphere drawn as a pale cyan net of triangle edges, and one wrapped in an orange and cream checker whose squares narrow toward the poles" width="680">

```swift
withState { fill(teal); material(.glossy); drawMesh(globe) }     // solid
withState { stroke(pale); wireframe(); drawMesh(globe) }         // edges only
withState { fill(.white); drawMesh(globe.textured(checker)) }    // wrapped in an image
```

**`wireframe()`** draws the mesh as its triangle edges instead of filled faces, taking the current `stroke` color and `strokeWeight`. It's how you see what a mesh is actually made of, which is genuinely useful when a generator gives you something odd. It's also just a look, the standard way to show a form that's still a proposal rather than a finished object. Because the faces are see-through, a wireframe doesn't light, so lights and materials have nothing to do.

**`textured(_:)`** returns a copy of a mesh wrapped in an `Image`. Every built-in generator emits the texture coordinates that decide where each part of the picture lands, and the checker above is chosen to make those readable. The squares stay square around the middle and narrow to slivers at the poles. That's what wrapping a flat rectangle onto a ball does, and you'll meet it whenever you texture a sphere. A textured mesh still lights normally, so it takes materials and shadows like any other surface. Keep the `fill` white unless you want the image tinted, the same rule as a loaded model.

Both are ordinary drawing state, saved by `withState`, so one frame holds all three treatments (the figure is a single render).

## A scene you can take apart

Loading a scene keeps the file in charge. Re-export from the tool and the sketch picks up the change, which is what you want while the model is still moving. There is a moment when you want the opposite: the layout is settled, and now you want to *work* on it. For that, ask for the sketch itself.

```sh
ollin new Yard --from-scene yard.usdz
```

<img src="Images/21-3DGently/SceneAsSource.jpg" alt="Left, the generated draw() with its camera call, its lights and its nested withState blocks. Right, the same scene drawn from those placements: a torus on a pedestal beside a lamp and a blue sphere" width="680">

That writes a project whose `draw()` is the scene, spelled out. The camera is a `Camera3D` with its own numbers. Each light is the factory that makes it. Every node is a `withState` block holding the moves that put it where the tool put it, nested the way the file nests them.

What does not become source is the geometry. A mesh is not something anybody edits as text. The sketch reads the file once for its meshes and places them itself. That is what `drawPart` does. Materials ride their meshes for the same reason. No `fill` appears anywhere.

So this is the lossy direction, and it says what it lost. Animation stays behind, along with the skins and blend shapes that bend geometry, since nothing in a written-out placement drives them. A mesh wearing several materials draws in the first, and its block is marked. Everything else is a line in your own sketch now.

Both directions are worth having. `loadScene` is for a set that is still being built. This one is for the moment the file stops being the piece and becomes the material. [Bringing a scene over](../Docs/Tools/SceneImport.md) has the details.

## Relief from a picture: normal maps

A texture changes a surface's color. A **normal map** changes how it catches light. Each texel stores a surface direction instead of a color, and at shading time the lighting normal bends by it. The result is relief without geometry.

<img src="Images/21-3DGently/SurfaceRelief.jpg" alt="Three gray spheres under the same warm light: one hammered with soft dents, one engraved with concentric rings, and one bare, all with perfectly circular silhouettes" width="680">

```swift
let hammered = Mesh.sphere(radius: 1).normalMapped(dents)
```

All three spheres are the same 96-segment sphere, and only the middle of the picture knows about dents and rings. Look at the silhouettes, which are perfect circles. That's the tell, and the trade. The bumps exist only in how the light lands, so they cost a texture sample instead of a million triangles. The edge of the object never learns about them. Games have leaned on this for twenty years, which is why a cobblestone street in one can be six polygons.

**`normalMapped(_:scale:)`** hangs a map on any mesh that carries texture coordinates. It quietly sets up the frame of reference the map's directions are expressed in, a *tangent basis*. It's the same standard one other tools bake maps against, so a map made elsewhere lights the same way here. `scale` is a relief dial, where 0 flattens it off, 1 is as authored, and more exaggerates. Loaded models bring their own normal maps along without being asked.

Where do maps come from? Anywhere images do, and one particularly satisfying place, which is math. Start with a height function, take its slopes, and encode them. The `3D/Materials/NormalMaps` example builds hammered metal, woven cloth, and engraved rings this way in a couple dozen lines, no files involved. One convention matters when authoring by hand. Green marks the slope that faces *up the image*. If a map from elsewhere lights upside down, its green channel is inverted, so flip it and it's home.

## What the surface is, per texel

A normal map changes how light lands. The rest of the standard map set changes what the surface *is* from texel to texel, and `surfaceMapped(...)` hangs any of them on a mesh:

<img src="Images/21-3DGently/SurfaceMaps.jpg" alt="Four spheres under one studio environment: coppery paint worn through to polished metal in soft patches, a pale coffered grid with shadow settled into its grooves, a near-black sphere crossed by glowing cyan seams, and a bare matte control" width="680">

```swift
let panel = Mesh.sphere(radius: 1)
    .textured(paint)
    .surfaceMapped(metallicRoughness: wear,   // roughness in g, metallic in b
                   occlusion: cavity,         // its red channel
                   emissive: seams)           // an ordinary color image
```

A **metallic-roughness map** packs two dials into one image, with roughness on green and metallic on blue, the packing every glTF exporter uses. Per pixel it multiplies the finish you draw under. `.physicallyBased` is the measured tier the materials section pointed ahead to. Both dials at 1 make it a blank the map can write on, so `material(.physicallyBased(metallic: 1, roughness: 1))` shows the map as authored. That multiply is the whole trick of the first sphere. One map says where the paint has rubbed through to bare polished metal, and the base texture colors the same patches silver.

An **occlusion map** is baked shadow for the crevices geometry doesn't have, and it dims only the *steady* light, the ambient and the environment. A lamp shining straight into a groove still lights it, which is exactly how real crevices behave and why the convention exists. The second sphere pairs it with a normal map made from the same height field, the usual recipe. The relief catches the light, and the occlusion keeps its grooves dark.

An **emissive map** makes texels give off light of their own, tinted and dimmed by an `emissiveColor` factor. It works with no lights at all, which is what the third sphere leans on, a nearly black shell whose engraved seams glow. Emission is the surface's own radiance, so fog veils it with distance like everything else. One line of housekeeping is worth knowing. A glowing surface doesn't light its neighbors unless global illumination is on, at which point it does.

Loaded glTF and USD models carry all of these in and out without being asked, and the round trip through `saveScene` keeps them. Like the normal maps above, every map in the figure is authored from a function in `setup()`. The `3D/Materials/SurfaceMaps` example is the worked version with a glow knob.

## Depth from a picture: height maps

A normal map tilts the light. A **height map** goes one further and stores the depth itself. The red channel is height, white is the surface, and darker is carved in below it. One image, and Ollin reads it two ways.

<img src="Images/21-3DGently/HeightRelief.jpg" alt="Three cratered tan spheres seen slightly from the side: a parallax-mapped one whose craters sink deep yet whose outline is a perfect circle, a displaced one with a genuinely bumpy cratered rim, and a bare control with flat dark spots" width="680">

```swift
let moon = base.textured(dust).parallaxMapped(craterHeights, scale: 0.06)
let rock = base.displaced(by: craterHeights, scale: 0.13).textured(dust)
```

**`parallaxMapped(_:scale:)`** is the shading read. At every pixel the renderer marches your line of sight down into the height field and finds where it lands. Then it reads the base texture, the normal map, and every other map *there* instead of at the flat surface. Crevices sink, slide against their rims as the view moves, and hide their far walls, everything real carving does. And still not one vertex has moved. `scale` is the depth of the relief as a fraction of the picture's tile. It needs the same texture coordinates and tangent basis a normal map does, and it sets the basis up itself the same way.

**`displaced(by:scale:)`** is the geometry read. Every vertex really moves along its normal by the height at its spot on the picture, normals are recomputed, and the relief becomes true of the mesh, with `scale` now in the mesh's own units. It's honest work done once, so do it in `setup()` and keep the result. The detail you get is the *mesh's* to give, since a plane with more `segments` carves finer.

Look at the outlines in the figure, because they are the entire lesson. The parallax sphere's silhouette is a perfect circle however deep the craters read. The shading is fiction, and the outline, the cast shadow, and a mirror all keep telling the geometric truth. The displaced sphere's rim is genuinely cratered, in shadow and reflection too. Inside the outline the two are nearly twins, which is exactly why parallax is worth having, all of the depth and none of the triangles. When the edge matters, displace. When it doesn't, march.

White stays put in both readings, one convention doing quiet work. A height map's white regions *are* the authored surface, so the two spheres agree about where the relief lives, and you can hand one map to both calls. The `3D/Materials/Parallax` example is the worked version with the parallax depth on a knob. USD files carry the map in and out, since `saveScene` writes it to the preview surface's displacement slot, while glTF simply has no place to put one.

## Smooth from a cage

There is a third way to get a mesh, and it's the one character artists live in. Build something crude out of a few boxes and extrusions, then let the computer round it. `subdivided(levels:)` takes any mesh as a **control cage**, splits every face, and eases every vertex toward its neighbors, once per level.

```swift
let cage = Mesh.extrude(Profile.star(), depth: 0.75)
let smooth = cage.subdivided(levels: 2)
```

<img src="Images/21-3DGently/SubdivisionCage.jpg" alt="Three views of the same extruded five-pointed star: the control cage as a pale cyan wireframe, one level of subdivision as a plump amber star with soft edges, and two levels as a much softer orange form sitting inside the ghosted wireframe of the cage whose points now reach far past it" width="680">

You model the cage, and the smoothness is computed. One level already turns the slab-sided star into something you'd want to hold. By two the form has melted well inside its cage, which is the thing to internalize. The smooth surface eases *toward the averages* of the cage, so it always sits inside it, and pointy features round off the fastest. If a shape comes out softer than you wanted, the fix is a chunkier cage, not fewer levels.

Any mesh works as a cage with no preparation. Take the primitives, an extrusion, a lathe, or a loaded model. `subdivided` welds their shared corners and recovers their intended faces before refining, so a box rounds as one closed surface rather than six drifting plates. Open sheets keep their rims, and a subdivided `plane` smooths along its edge instead of shrinking away from it. Triangle-native meshes like an icosphere or a marching-cubes blob have their own refinement rules a scheme argument away, `subdivided(.loop, levels: 2)`. The [reference page](../Docs/Generators/SubdivisionSurfaces.md) covers when to pick which.

Like erosion below, this is `setup()`-shaped work: each level roughly quadruples the face count, so refine once, keep the mesh, and let `draw()` just draw it. Two or three levels is almost always enough.

## A surface that outgrows itself

Subdividing takes a shape you designed and smooths it. This does the opposite. It hands you a shape nobody designed, out of a rule you can say in one sentence.

Take a mesh. Push its vertices apart, and split any triangle that stretches so the triangles stay a fixed size. The surface now has more area than it started with, and here is the part that matters. **Nothing is pushing it outward.** The forces run along its own edges, and those lie in the surface. It cannot get bigger the way a balloon does. So the new area has to go somewhere, and the only direction left is sideways. It folds.

```swift
// setup(), and keep it:
growth = MeshGrowth(mesh: .icosphere(subdivisions: 3), driver: .uniform, seed: 7)

// draw():
growth.step()
drawMesh(growth.mesh)
```

<img src="Images/21-3DGently/GrowingSurface.jpg" alt="Three forms in a row against black: a smooth yellow sphere labelled the seed, an orange ball completely covered in even brain-like folds labelled everywhere, and a flattened orange form with a smooth top and a ruffled rim labelled at the equator" width="680">

That middle one is a plain sphere that grew evenly, and it is worth sitting with, because nobody told it to make lobes. Grow a ball uniformly and it does not become a bigger ball. It becomes a brain. Every fold in it is the surface running out of room.

The `driver` decides *where* the growth is fastest, and since every driver folds, what you are really choosing is **where the folds go**:

```swift
MeshGrowth(mesh: seed, driver: .uniform)      // evenly, all over
MeshGrowth(mesh: seed, driver: .curvature)    // wherever it already bulges

// Only near the equator, the way a leaf grows along its margin.
MeshGrowth(mesh: seed, driver: .field { position, _ in
    1 - smoothstep(0.1, 0.5, abs(position.y))
})
```

The third panel is that last one. The poles never grew, so they stayed smooth, and everything the band made had to ruffle. It is the same rule as the lettuce leaf and the kale edge. They grow faster along the rim than through the middle, and they buckle for exactly this reason.

The two knobs worth knowing early. `edgeLength` is the triangle size, so it sets the finest fold the surface can hold and it is where the cost lives. `stiffness` is how much the surface resists bending, and it decides how *big* the folds come out. A sheet with no stiffness buckles at the smallest scale it can and reads as crumpled paper, while more of it gathers the same growth into broader waves. If a result looks like foil someone sat on, that is the knob.

There is a fourth driver, `.chemical`, that runs a reaction-diffusion pattern in the surface and grows where the pattern collects. The chemistry decides where to add area, and the new area gives the chemistry more room to spread. That is the branching-coral one, and the [reference page](../Docs/Generators/MeshGrowth.md) has it along with self-avoidance, open sheets that keep their rims, and the cost.

Growth is slow on purpose. A form takes hundreds of steps, and stepping once a frame while you watch it develop is most of the pleasure. `maxVertices` is the ceiling that keeps it interactive, and it also decides how far a form gets before it settles.

## A picture from three sides: triplanar

The last two sections left you holding a small problem. A texture maps through uv coordinates, a little address on every vertex saying where on the picture it sits. The surfaces you just made have none. Nobody unwrapped the grown ball, a subdivided cage comes back without its uvs, and the marched blobs of the next chapter are the same way. `textured(_:)` has nothing to hold onto.

`triplanarTextured` sidesteps the question instead of answering it. Rather than asking the mesh where the picture goes, it projects the picture through the world three times, once along each axis, like three slide projectors aimed down x, y, and z. Every point on the surface blends the three by how squarely it faces each projector. A wall takes nearly everything from the projector facing it. A 45-degree slope takes half and half, and the handoff is gradual enough that you cannot find the line.

```swift
drawMesh(grown.triplanarTextured(stone, normal: veins, scale: 0.9))
```

<img src="Images/21-3DGently/TriplanarSkin.jpg" alt="Two sand-colored carved forms against black: a grown, folded ball completely covered in a continuous engraved vein pattern with no visible seam, and a cairn of three stacked boxes whose shared pattern runs unbroken across all three" width="680">

`scale` is the size of one tile in world units, and a `normal:` map rides the same projection. So the veins in the figure are engraved relief, not just darker paint. Notice what you did *not* do. There are no uvs, no tangent basis, and no unwrapping, and the projection works on any mesh you can make or load.

The picture stands still and the surface moves through it. That is the one thing to understand about triplanar, and it cuts both ways. The cairn is three separate boxes drawn one after another, and the pattern runs unbroken across all three, because they stand in the same standing field. That is why the technique is beloved for terrain and rockwork. But a mesh you animate through the transform stack slides through the pattern rather than carrying it along, so a body that travels should wear uvs. A form that grows or morphs in place, like the blob in the `3D/Materials/Triplanar` example, flows through the pattern like a shape turning under falling light, which is its own kind of beautiful.

The projection carries the base texture and a normal map, while the rest of the map set stays with uvs. The [reference page](../Docs/3D/3D.md#triplanar) has the edges of the envelope. The example puts the tile size and the relief on knobs.

## Texture that survives a close look

Every texture has a budget. A picture sized to cover a whole boulder spends all its texels on the big shapes. The moment the camera leans in, the surface runs out of information and dissolves into soft nothing. Real rock does not do that. Get closer and there is always another scale of grain waiting.

`detailMapped` fakes that second scale honestly. It tiles a much finer texture pair across the base one, a color map and a normal map. They repeat several times per base tile, so the close look finds grain the base never carried.

```swift
drawMesh(boulder
    .textured(rock)
    .normalMapped(rockBumps)
    .detailMapped(grain, normal: grainBumps, scale: 12))
```

<img src="Images/21-3DGently/SurfaceGrain.jpg" alt="Two warm-toned spheres side by side against black, seen close: the left one smooth and soft where its texture has run out of resolution, the right one carrying fine woven grain across the same large forms" width="680">

Two conventions make the pair behave. The detail color map multiplies the base with middle gray as its neutral, value 128 in the image. Darker speckles darken, lighter ones lighten, and a flat gray image changes nothing. Author it as texture swinging around gray and the overall tone of your surface holds. And the detail normal map is *reoriented onto* the base relief rather than replacing it. The fine bumps ride the large forms the base map already shaped, the way real grain follows the rock it is part of.

`scale` is how many times the pair repeats across the base, and `strength` fades it out, with zero the honest off switch. One caution is worth keeping. The detail maps carry no mips, so a very high tile count can shimmer when the surface gets small on screen. Keep the scale in the range your framing actually shows, which is what the `3D/Materials/Detail` example is for. It puts the same base maps on two spheres, the detail pair on one of them, and the tile count and strength on knobs while the camera sways close.

## A picture stamped onto the scene: decals

Everything so far dressed one mesh. A sticker does not care about meshes. Slap it on a crate and it wraps whatever it lands on, the crate, the pallet under it, half of the wall behind.

A `Decal` works like that. Wrap an image once, then place it each frame as a small projection box. Every surface inside the box receives the picture, composited over the surface's own color before lighting, so it shades like paint rather than a glowing overlay.

```swift
let sticker = Decal(loadImage("label.png")!)!

override func draw() {
    // camera, lights, floor, crates ...
    decal(sticker, at: dropPoint, width: 140)   // projects straight down by default
}
```

<img src="Images/21-3DGently/Stamped.jpg" alt="A gray floor with two tan crates: a red, white, and blue roundel stamped across the floor and continuing up over a crate's top, a black and yellow striped tag on the crate's front face, and a half-transparent yellow ring overlapping the roundel on the floor" width="680">

The box has a direction, a width and height, and a depth. The placement is per-frame state like a light, which is the quietly powerful part. Move `at:` and the stamp slides across the scene, crossing from the floor up onto a crate and over its far edge, conforming to whatever it touches. Transparency in the image is honored, and later decals composite over earlier ones. A surface standing edge-on to the projection fades the stamp out instead of smearing it down the side, which is the failure you would otherwise get on every wall.

A decal is paint, so it takes the finish of the surface it lands on. Stamp a rough floor and the mark is matte. Stamp polished metal and it sits under the shine. The [reference page](../Docs/3D/3D.md#decals) has the envelope. That's eight per frame, which surfaces receive them, and what mirrors show. The `3D/Materials/Decals` example slides a roundel across floor and crates on a loop, with the size, a roll, and a see-through ring on knobs.

## What the depth buffer is for

[Chapter 16](16-LayersAndEffects.md) filtered layers by their color. A 3D scene drawn into a layer carries something extra that a flat drawing never has. For every pixel, it knows how far away the thing at that pixel is. That's the **depth buffer**, and three effects exist purely to use it.

```swift
let scene = renderTarget()
withTarget(scene) { /* your 3D scene */ }

drawImage(scene.combined(with: scene.depth,
                         .ambientOcclusion(radius: 0.7, intensity: 1.5)).image, 0, 0)
```

<img src="Images/21-3DGently/DepthEffects.jpg" alt="Three panels of the same field of pale blocks on a ground plane: plain, then with ambient occlusion darkening the gaps and contacts, then with depth of field leaving one band of blocks sharp while the front and back blur" width="680">

`scene.depth` is an ordinary layer whose brightness is distance, so it feeds `combined(with:)` like any other, and everything else in [Chapter 16](16-LayersAndEffects.md) still applies.

**`.ambientOcclusion`** darkens the places light struggles to reach. Those are crevices, the gaps between objects, and the line where something meets the ground. Compare the first two panels and the blocks stop floating. That single change is most of what makes a render read as solid rather than pasted together. It costs one line, because the depth layer already knows where the crevices are.

**`.defocus`** is a camera lens. It keeps a band of distance sharp, set by `focus` and `range`, and blurs everything else more the further it is from that band, up to `maxBlur`. It's how you point at one thing in a busy scene. Both `focus` and `range` are read against the depth layer's `0...1`, so they depend on the camera's `near` and `far`. That is why setting those to actually bracket your scene matters, rather than leaving them enormous.

**`.screenSpaceReflections`** makes a floor glossy by reflecting the scene in it, and it runs on any Mac. It has one limit worth understanding rather than being surprised by. It reflects what is on the screen, and a picture does not contain the back of anything. Where the true reflection would be of a surface the camera cannot see, such as the underside of a ball resting on a floor, it can only approximate. That shows as a soft zone right at the contact. A touch of `roughness` hides it, and [Chapter 25](25-SculptingWithFields.md) has the exact alternative.

All three take a `quality` tier, `.performance`, `.default`, or `.detail`, which trades frame rate for smoothness. The tier is relative to your machine rather than an absolute setting, so `.default` means "the balanced choice for this GPU" and buys more samples on a faster one. Raising it to `.detail` for a final export is the usual move, since the export doesn't have to keep up with a display.

## Keeping your bearings

3D scenes are easy to get lost in, so the tools for finding yourself again are built in. `cameraView(.front)` snaps the camera to a canonical angle, like front, top, left, or isometric, and `resetCamera()` returns to the opening shot. The host apps put the same snaps in a **Camera** menu, ⌘0 through ⌘7, so they work on any running sketch without a line of code. Two more calls help while you build. `cameraAxis()` shows a small clickable x-y-z compass, and `groundGrid()` lays a faint reference floor. Both are development chrome, drawn only in the live window and never in an export, which is why you won't find them in any figure in this chapter.

One more thing to keep straight as you combine features. Ollin draws several *kinds* of 3D thing, and they don't all take the same finishes. Solid meshes are the fullest citizens, taking materials, textures, shadows, and reflections. The raymarched fields of [Chapter 25](25-SculptingWithFields.md) take materials, environments, and shadows but arrive by a different route. Point clouds are camera-facing splats and take neither lighting nor shadows, which is exactly right for what they are. None of this is arbitrary, since each kind is a different way of getting pixels on screen, but it does mean a material that transforms a mesh may do nothing to a cloud. When something you expected to apply doesn't, the [combining reference](../Docs/3D/Combining.md) is a table of what stacks with what.

## Putting it together: the plaza

The finished piece is a small sculpture court you curate yourself. There are five plinths and five pieces, each wearing a different finish, under golden-hour light with soft shadows. The camera orbits until you take over. Make `MySketches/Plaza.swift`:

```swift
import Ollin

final class Plaza: Sketch {
    // Built once; drawn every frame.
    let knot = Mesh.torusKnot(radius: 0.62, tube: 0.2, segments: 220, sides: 14)
    let vase = Mesh.lathe((0...24).map { i in
        let t = Double(i) / 24
        return Vector2(0.16 + 0.36 * sin(t * .pi * 0.92), (t - 0.5) * 1.5)
    }, segments: 44)
    let pearl = Mesh.sphere(radius: 0.62, segments: 48, rings: 32)
    let gem = Mesh.icosahedron(radius: 0.55)
    let sketchWork = Mesh.icosphere(radius: 0.66, subdivisions: 1)

    override func draw() {
        background(Color(hex: 0x141824))
        cameraShowcase(target: Vector3(0, 1.15, 0), radius: 12,
                       elevation: 0.26, fieldOfView: .pi / 4.4)
        lightingPreset(.goldenHour)
        castShadows()

        // The court floor.
        fill(Color(hex: 0x3A3D45))
        specular(0.05)
        drawPlane(width: 60, depth: 60)

        // Each piece: move to its plinth, draw the plinth, lift, spin, draw.
        withState {
            translate(-3.2, 0, 0.6); plinth(1.0)
            translate(0, 1.5, 0); rotateY(time * 0.24)
            material(.glossy); fill(Color(hex: 0x2C8C86))
            drawMesh(knot)
        }
        withState {
            translate(-1.0, 0, -1.6); plinth(1.55)
            translate(0, 2.32, 0)
            material(.velvet); fill(Color(hex: 0x8C1F35))
            drawMesh(vase)
        }
        withState {
            translate(1.0, 0, 1.4); plinth(0.75)
            translate(0, 1.4, 0)
            var paint = Material.glitter
            paint.sparkleColor = Color(hue: 0.12, saturation: 0.75, brightness: 1)
            material(paint); fill(Color(hue: 0.02, saturation: 0.8, brightness: 0.4))
            drawMesh(pearl)
        }
        withState {
            translate(3.3, 0, 0.9); plinth(1.2)
            translate(0, 1.7, 0); rotateY(time * 0.3); rotateX(0.15)
            material(.toon); fill(Color(hex: 0xE08A3C))
            drawMesh(gem)
        }
        withState {
            translate(-0.4, 0, -3.4); plinth(2.0)
            translate(0, 2.72, 0); rotateY(time * -0.2)
            wireframe()                       // one piece still being imagined
            stroke(Color(hex: 0xBFC7D5)); strokeWeight(1.2)
            drawMesh(sketchWork)
        }
    }

    // A stone block whose top lands at `height`.
    func plinth(_ height: Double) {
        withState {
            translate(0, height / 2, 0)
            material(.matte); fill(Color(white: 0.88))
            drawBox(width: 0.95, height: height, depth: 0.95)
        }
    }
}
```

<img src="Images/21-3DGently/Plaza.jpg" alt="The finished plaza: five sculptures on plinths, glossy, velvet, glittering, toon, and wireframe, under warm low light with long soft shadows" width="560">

Everything in it is this chapter. Meshes are built once, and plinths are placed with the transform stack. Note how each block translates to its spot, draws the plinth, then keeps translating upward for the piece. There's one preset for the light, one `castShadows()`, and a different material per sculpture. The last piece is drawn with `wireframe()`, mesh edges only, the standard look for a form that's still a proposal.

Then make it yours:

- Recast the show by swapping in a supershape, a lathe of your own profile, or a loaded model on the tallest plinth.
- Relight it. `.noir` turns the court into a crime scene, and `.moonlight` into a garden at night. Put the preset on a `@Param` menu knob.
- Give the pearl's plinth a slow `rotateY` of its own and let the whole pedestal turn.
- Try `matcap(.chrome)` on the gem and notice what stops responding. Lights and shadows go quiet, and only the view still matters.

## Where this comes from

The camera-on-an-orbit model is the shared convention of 3D tools everywhere, from CAD turntables to the orbit controls of three.js. The lighting model under the materials is Blinn-Phong shading, Jim Blinn's 1977 refinement of Bui Tuong Phong's specular model, the workhorse of real-time graphics for decades. The toon and warm-to-cool finishes descend from the non-photorealistic rendering literature, notably Amy Gooch and colleagues' 1998 technical illustration shading. The three-point lighting behind the presets is a film-set convention nearly as old as film. Matcaps grew up in the digital-sculpting world, where painters bake a whole studio into one sphere image. The supershape formula is Johan Gielis's superformula (2003), while the lathe and extrude are as old as pottery and pasta. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [3D](../Docs/3D/3D.md): the full reference for cameras, primitives, meshes, lights, materials, matcaps, shadows, and loading models, including the environment lighting and ray-traced reflections this chapter only waved at.
- [Camera control](../Docs/3D/Camera.md): `cameraShowcase`, the cinematic move catalog, view snaps, and the input surface underneath.
- [Combining 3D features](../Docs/3D/Combining.md): the practical map of what stacks with what (which geometry takes materials, casts shadows, appears in reflections).
- Lens and grounding effects: draw a 3D scene into a render target and its depth layer feeds [Chapter 16](16-LayersAndEffects.md)'s combine effects, `.defocus` for camera-like depth of field, `.ambientOcclusion` to darken contacts and crevices, `.screenSpaceReflections` for glossy floors on any Mac. See [Effects](../Docs/Drawing/Effects.md#combined) and the `3D/SceneDefocus` example.
- [Shadows in full](../Docs/3D/3D.md#shadows): how each caster kind works, the soft-shadow quality dials, and the frustum fitting you never have to touch.
- [Atmosphere](../Docs/3D/Atmosphere.md): the full fog and volumetric-light reference, what participates and what sits out, and the quality dial's exact step counts.
- [Scenes](../Docs/3D/Scenes.md): the full `loadScene` reference, what carries over from a glTF file (nodes, cameras, punctual lights, animations, skins, and morph targets) and from a USD file (nodes, cameras, its UsdLux lights, area kinds included, its transform animation, timeSamples arriving as one animation `apply(_:at:)` plays, and its UsdSkel skins and blend shapes, joints arriving as nodes you can pose by name), how intensities are normalized, and building a `Scene` in code.
- [Bringing a scene over](../Docs/Tools/SceneImport.md): `ollin new --from-scene` writes the sketch instead of loading the file, so the camera, the lights and every placement become source you own. What it leaves behind, and why, is listed there.
- Textures and wireframes: [`Mesh.textured(_:)`](../Docs/3D/3D.md#textures) also takes a `baseColor` for tinting a shared texture, and [`Mesh.uvs`](../Docs/3D/3D.md) is where the coordinates live if you're generating your own geometry.
- [The 26 built-in matcaps](../Docs/3D/3D.md#the-built-in-matcaps), listed by family, plus `Matcap.shaded` for baking one from a color.
- [3D physics](../Docs/Simulation/Physics3D.md): the full `World3D` reference, every collider and joint kind, forces and impulses, the camera-grab machinery, and [saving a world](../Docs/Simulation/Physics3D.md#snapshots) to load back later, with the `3D/Physics` examples (a tower under cannon fire, a pile you can rummage through, a wrecking ball on a chain).
- Appendix B draws this chapter's math, one picture per idea: [Where things are](B-JustEnoughMath.md#where-things-are), [Moving the paper](B-JustEnoughMath.md#moving-the-paper), [Into three dimensions](B-JustEnoughMath.md#into-three-dimensions).
- Worked examples: [`Examples/3D/Geometry/Solids`](../Examples/3D/Geometry/Solids/Sketch.swift), [`Examples/3D/Geometry/ShapeFactory`](../Examples/3D/Geometry/ShapeFactory/Sketch.swift), [`Examples/3D/Geometry/Transforms`](../Examples/3D/Geometry/Transforms/Sketch.swift), [`Examples/3D/Lighting/LightingPresets`](../Examples/3D/Lighting/LightingPresets/Sketch.swift), [`Examples/3D/Lighting/Shadows`](../Examples/3D/Lighting/Shadows/Sketch.swift), [`Examples/3D/Materials/Materials`](../Examples/3D/Materials/Materials/Sketch.swift), [`Examples/3D/Materials/Matcap`](../Examples/3D/Materials/Matcap/Sketch.swift), [`Examples/3D/Geometry/LoadedMesh`](../Examples/3D/Geometry/LoadedMesh/Sketch.swift), and [`Examples/3D/Geometry/LoadedScene`](../Examples/3D/Geometry/LoadedScene/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 20, Simulations made of particles](20-ParticleSimulations.md) · Next: [Chapter 22, Landscapes and multitudes](22-Landscapes.md)
