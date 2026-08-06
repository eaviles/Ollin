#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 17</sup>

---

# 17. 3D, gently

<img src="Images/17-3DGently/Plaza.jpg" alt="A small sculpture court at golden hour: a glossy teal knot, a deep red vase, a sparkling car-paint sphere, an orange faceted gem, and one wireframe sphere, each on a pale plinth, casting long soft shadows" width="560">

Every sketch so far lived on a flat canvas. This chapter adds the third axis, and the surprising part is how little changes: the same `draw()`, the same `fill` and `translate`, the same motion by default. What's new is a camera, a handful of solid shapes, and light. By the end you'll have built that sculpture court, and you'll be able to grab it with the mouse and walk around it.

## The world behind the canvas

3D drawing doesn't happen *on* the canvas. It happens in a world of its own, and a **camera** photographs that world onto the canvas each frame. The world has three axes: x runs right, y runs **up**, and z runs toward you. Positions in it are `Vector3`s, which are exactly Chapter 8's `Vector2` with a third number:

```swift
let p = Vector3(2, 1, -3)     // 2 right, 1 up, 3 away
```

Two habits from the canvas need resetting. First, in the world **y goes up**, the opposite of the canvas, where y grows downward, so a tower rises toward positive y. Second, there are no pixels here. World distances are **world units**, and a unit means whatever your scene wants it to mean (a meter for a room, a "sphere-width" for an abstract piece). Sizes on screen come from where the camera stands.

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

<img src="Images/17-3DGently/FirstSphere.jpg" alt="A single coral-red sphere, softly shaded, floating on a near-black background" width="560">

Run it live and drag. The sphere isn't a flat disc, it's a shaded ball, and the mouse orbits around it. `cameraShowcase` gives you the camera most 3D sketches want with no wiring at all. It circles the scene slowly on its own, you can grab it any time (drag to orbit, scroll to move closer or farther, right-drag to slide the view), and after ten seconds of being left alone it drifts back to the opening shot and resumes. That way a sketch on a wall keeps moving and a curious viewer can always explore.

Notice you set up no lights. Solids are lit by a default rig automatically, so a shape looks three-dimensional out of the box. We'll take the lights over ourselves in a few pages.

The camera's home position is described by three numbers, and the picture to keep in mind is an eye riding a sphere around a target:

<img src="Images/17-3DGently/Orbit.jpg" alt="A diagram of the orbiting camera: a small camera body on a gray ring around a dark knot, with a dashed sight line labeled radius, a ground arc labeled azimuth, and a climbing arc labeled elevation" width="680">

**Radius** is how far away the eye sits. **Azimuth** is how far around it has walked, an angle in radians like every angle since Chapter 3. **Elevation** is how high it has climbed above the horizon. Every camera motion in this chapter, the automatic orbit and your mouse drags alike, is just these three numbers changing. The camera is per-frame state, like the things you draw, so it's set inside `draw()`.

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

<img src="Images/17-3DGently/DepthRow.jpg" alt="Six spheres in a row marching away from the camera across a pale floor, each one smaller and partly hidden behind the one before it" width="560">

Three things happened at once. `translate` grew a third argument, so it moves things in space now. The spheres get smaller as they get farther away, because the camera has perspective. And each sphere *hides* the ones behind it. That hiding is the **depth test**, which means the renderer remembers, per pixel, how far away the nearest surface was, and anything farther loses. You never sort anything by hand. Draw in any order and the world works it out.

`drawPlane` is the floor, a flat sheet on the ground, and it's the stage most scenes stand on. `fieldOfView` is the lens. Smaller angles are telephoto, which reads calm and flat and suits product shots, while bigger angles are wide-angle, dramatic and stretched at the edges. The default is a fairly wide lens, so this sketch tightens it to a quarter turn.

## A catalog of solids

The catalog runs well past spheres and boxes. Each of these is one call, shaded and depth-tested like everything else:

<img src="Images/17-3DGently/Catalog.jpg" alt="A four-by-four grid of labeled solid primitives: box, sphere, icosphere, cylinder, cone, capsule, rounded box, torus, the four larger Platonic solids, pyramid, helix, torus knot, and plane" width="560">

The names are what you'd guess: `drawBox(size: 1.5)`, `drawTorus(radius: 0.6, tube: 0.25)`, `drawCone(radius: 0.7, height: 1.5)`, and so on. Past the everyday ones there's also a small shape *factory*. `drawSupershape` and `drawSuperellipsoid` sweep whole families of organic and gem-like forms from a few numbers, `drawExtrude` pushes any flat 2D shape into depth, `drawLathe` revolves a side profile into a vase, and `drawTube` sweeps a tube along any 3D path. The `3D/ShapeFactory` example is the tour.

Under every one of these calls is a **`Mesh`**, the shape as a cloud of triangles, which is what all 3D surfaces are made of here. The `draw*` calls rebuild their mesh every frame, which is fine for a box and wasteful for a dense knot. The pattern for anything heavy is the one you know from images and fonts, build once, draw forever:

```swift
let knot = Mesh.torusKnot(radius: 0.62, tube: 0.2, segments: 220, sides: 14)
// …each frame:
drawMesh(knot)
```

## Placing things: transforms compose

You've been using `withState` and `translate` since Chapter 6, and in 3D they're joined by `rotateX`, `rotateY`, `rotateZ` (each spins around one axis), and the same `scale`. The important idea hasn't changed: **every move builds on the moves before it**. In 3D that compounding is where structures come from:

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

<img src="Images/17-3DGently/Stairs.jpg" alt="A spiral staircase built from twenty-six colored slabs winding up a dark central post, cyan at the bottom shading to pink at the top" width="560">

Read the loop closely, because it uses both halves of the tool. The climb and the turn sit *outside* any `withState`, so they accumulate, step after step, and that accumulation is the spiral. The sideways step to hang each tread off the post sits *inside* a `withState`, so it applies to one tread and is forgotten. One repeated move-and-turn, and a staircase happens.

This sketch also shows the plain `camera(.orbiting(...))` call, a fixed pose you specify completely, with no mouse involved. Reach for it when you want to compose a shot exactly, and for `cameraShowcase` when you want the scene alive and explorable.

Nesting `withState` blocks builds solar systems. Translate to a planet and draw it, then translate again and draw its moon, and the moon inherits the planet's motion for free. The `3D/Transforms` example is exactly that, three transforms deep.

## Light, by playing

Everything so far wore the default lighting. Taking over is one call before you draw, and the fastest way to feel what lighting does is to swap whole moods:

<img src="Images/17-3DGently/PresetTour.gif" alt="The same still life of a sphere, box, and torus relit once per second by six lighting presets, from soft neutral studio light to a single harsh noir key to dim blue moonlight" width="480">

```swift
lightingPreset(.goldenHour)     // one call relights the whole scene
```

The six presets (`.standard`, `.threePoint`, `.goldenHour`, `.noir`, `.studio`, `.moonlight`) are each an ambient wash plus a few placed lights, tuned like film rigs. Play with them first, because the mood of a 3D piece is mostly its light, and swapping presets on a knob teaches you more in a minute than any paragraph.

When you're ready to place your own, there are three kinds of light, and one scene can carry all of them:

```swift
ambientLight(Color(white: 0.1))                                     // a floor for the shadows
directionalLight(Color(hex: 0xFFD9A8), direction: Vector3(-0.6, -1, -0.35))
pointLight(Color(hex: 0x39D8E8), at: Vector3(2.7, 1.7, 1.9))
spotLight(Color(hex: 0xE85FD0), at: Vector3(-3.4, 4.6, 2.6),
          direction: Vector3(0, -1, 0), angle: .pi / 5, penumbra: 0.4)
castShadows()
```

<img src="Images/17-3DGently/LightKinds.jpg" alt="A sphere, box, and torus on a pale floor lit three ways at once: warm directional light from the left, a cyan point light marked by a small ball, and a magenta spot pooling on the floor" width="680">

A **directional** light is the sun, parallel rays from a direction, with no position of its own, lighting everything evenly. A **point** light is a bulb at a place, so nearby things catch it strongly. A **spot** is a point light narrowed to an aimed cone, with a `penumbra` for how soft its edge falls. The `ambientLight` is a flat wash added to every surface so the unlit sides aren't pure black. Each light takes an `intensity`, and in the figure each has its own color so you can see who's doing what: the warm key shades everything, the cyan bulb blooms on the surfaces near it, the magenta cone pools on the floor.

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

<img src="Images/17-3DGently/Shadows.jpg" alt="Four identical orange spheres over one pale floor, each higher than the last, their four shadows in a row on the floor. The leftmost sphere rests on the floor and its shadow is a tight dark ellipse; each shadow further right is a little smaller, further from its sphere, and visibly blurrier" width="680">

Four identical spheres, one floor, one light. You know instantly which one is resting and which is highest, and the only thing telling you is the shadow. Two things change as a sphere climbs: the shadow drifts away from it, and the edge gets softer. The one on the left, touching down, has a tight ellipse with a crisp edge. The one on the right, three and a bit units up, has a blurry patch with a wide grey skirt.

That softening is worth knowing about because it is the thing that makes rendered shadows look real. Shadows here are **contact-hardening** by default: sharp where an object meets a surface, softer as the shadow falls away. `shadowSoftness(_:)` sets how strong the effect is, from `0` (a hard edge, the classic look) through the `0.5` default to `1`. The figure asks for `1` so the difference is easy to see at this size; at the default it is subtler and usually what you want.

Some practical notes, in the order they tend to bite:

- **You need something to catch a shadow.** A sphere alone in space casts into nothing. A floor, or another object, is what makes the shadow visible.
- **It's opt-in and per-frame.** A sketch that never calls `castShadows()` pays nothing at all, so shadows cost you only when you ask. Call it in `draw()` alongside the lights, and `noShadows()` turns it back off.
- **One light does the casting**, chosen for you: the first directional light, or a spot if there's no directional, or a point light failing that. (A glowing panel can cast too; that's the next section.) The default rig's key light is directional, so a scene you haven't relit already works.
- **Nothing needs aiming.** The shadow's frame auto-fits around whatever the camera is looking at.

The three kinds of light cast by different routes, which mostly matters because it explains the cost. A directional or spot light renders the scene once from the light's own viewpoint and darkens whatever that view can't see. A point light casts in every direction at once, so on Apple silicon it instead traces actual rays from each lit pixel toward the light, which is exact (no bias artifacts) but the most expensive of the three. On a GPU that can't trace rays it falls back to a depth map sampled by direction, so point shadows still work everywhere and your sketch doesn't change either way.

If a penumbra looks grainy rather than smooth, that's the sample count, not the softness: `shadowQuality(.detail)` asks for more samples relative to whatever GPU is running, and `shadowSamples(16)` sets an exact number.

## A light with a body

The three kinds above are infinitesimal points. A fourth family gives light a *body*: `rectLight` is a glowing panel (a softbox, a window), `diskLight` a glowing circle, `tubeLight` a glowing cylinder strung between two points (a neon). `intensity` means something different here, and it's worth a moment: it is the glow of the surface itself, so brightness falls off with distance on its own, a bigger panel pours more light at the same glow, and a thin neon needs an intensity in the tens because a thin tube is a small piece of sky.

What a body buys you is easiest to see by changing its size and nothing else:

```swift
let side = 1.0 + pingPong(over: 6) * 2.2
let facing = Vector3(0.55, -0.58, 0.6)          // aimed down across the set
rectLight(Color(hue: 0.09, saturation: 0.22, brightness: 1.0),
          at: Vector3(-3.4, 4.8, -1.2), direction: facing,
          width: side, height: side, intensity: 70 / (side * side))
castShadows()
```

<img src="Images/17-3DGently/LightWithABody.gif" alt="A teal pillar and an orange sphere on a gray floor under one warm glowing panel that slowly grows and shrinks. When the panel is small the sphere's highlight is a tight spot and both shadows are crisp; as it grows the highlight widens into a sheen, the shading wraps, and the shadows spread into soft pools while the scene's overall brightness stays the same" width="560">

The listing divides the panel's glow by its area as it grows, so the light poured on the set never changes and you can watch what size alone does. Three things move together. The highlight on the sphere is the panel's own reflection, so it grows from a small window into a broad sheen. The shading wraps further around each form, because more of each surface can see some part of the panel. And the cast shadows, sharp when the panel is small, spread into soft-edged pools, still crisp where the box meets the floor and wider the farther they fall. The size of the light is the softness of the picture, and here it's one number.

Shadows work the way the last section said, with the panel's size standing in for a light's position: a rect or disk panel is picked as the caster when no punctual light claims the job, and its penumbra comes from the panel's real extent, nothing to set. `shadowSoftness(_:)` scales that extent rather than some separate size: `0` hard, the `0.5` default the panel's true size, `1` twice as soft. A tube never casts; it glows in every direction, so there is no side to draw a shadow from. One practical note from the figure's own listing: lights are invisible, so the glowing slab you see is a drawn prop, placed a step *behind* the emitting plane, because a casting panel treats any geometry in front of that plane, its own prop included, as an occluder.

The `3D/Lighting/AreaLights` example stages all three shapes over a glossy floor; put it beside `3D/Lighting/Lighting` and the difference between a bulb and a panel is the whole studio-photography look. `3D/Lighting/AreaShadows` is the breathing softbox.

## The shape of the throw

A bare point light pours the same brightness in every direction, and a spot is just that pour with a cone cut into it. Real fixtures are choosier. A recessed downlight pools a hot disc with a faint ring of spill around it; a street lamp throws sideways in two wings so the bright spot isn't the foot of its own pole; a wallwasher climbs the wall and leaves the room alone. Lighting manufacturers measure exactly where each fixture sends its light and publish the measurement as an **IES file**, a small text file of brightness-by-angle, and a light can wear one:

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

<img src="Images/17-3DGently/ShapedLight.gif" alt="A dark room with a sphere and a low slab. On the left an orange downlight pools a hot disc around the sphere with a faint ring of spill just outside it. On the right, warm window panes with a cross of mullion shadow lie across the floor and climb over the slab, rocking slowly from side to side" width="560">

The left pool is the profile at work: a hot center, a dip, then the spill ring, all read from a dozen numbers in the file. The profile's `0°` aims along the light's axis (a spot uses its `direction`; a point light takes an `axis:`, straight down unless you say otherwise), its brightest direction is normalized to `1` so `intensity` still means what it always means, and anywhere the file didn't measure is dark, exactly as the fixture is. Parse the file once in `setup()` and keep it; it's plain data, and `IESProfile(resource:in:)`, `(contentsOf:)`, `(data:)`, and `(string:)` all read the same format. The throw is the fixture's signature, and the file is how you borrow a real one.

The window on the right is the second shaper: a **cookie**, an image a spot projects through its cone (stage crews call the physical version a gobo, a stencil slid in front of the light). `LightCookie(image)` wraps any `Image` once, in `setup()`; black blocks, white passes, color tints like a gel, and the image's edges land at the spot's outer cone, so a wider cone throws the same picture larger. The `roll:` in the listing is what rocks the panes: one knob spins an asymmetric profile and the cookie together about the beam, the way a fixture turns in its yoke.

Two habits worth keeping. A profile ends where its measurements end, so a downlight file that stops at 90° sends nothing above the fixture's own horizon; to wash a wall, tilt the light's `axis:` at it, the way the real fixture would be aimed. And both shapers are made-once values: the profile parses its file and the cookie resamples its image at construction, so build them in `setup()` and hand the same value to the light every frame. The `3D/Lighting/LightShaping` example stages a downlight, a batwing, a wallwasher, and this same window over one floor, with its three `.ies` files riding beside the sketch as bundled resources.

## Air you can see

Everything so far shows a light only where it lands. Real air shows the light on its way: dust and haze catch a beam mid-flight, which is why a projector's cone hangs visibly over a cinema audience and sun through a window is a slanted block of bright air. Two calls give a scene that air.

```swift
fog(Color(hex: 0xB4BDC9), density: 0.16, heightFalloff: 0.55)
```

`fog` fades every surface toward its color with distance, so near things stay crisp while far things dissolve, and depth reads at a glance. `density` is the thickness; the `heightFalloff` thins it with altitude, which is the morning-mist look, mist pooling low while tall things rise clear of it. It costs almost nothing (the fade is an exact formula, not a blur pass), so animating the density is just a number moving. The `3D/Effects/Fog` example is a colonnade standing in exactly this mist.

```swift
castShadows()
volumetricLight()
fog(Color(hex: 0x0A0E18), density: 0.02)   // a whisper of haze for the beams to live in
```

`volumetricLight()` is the beam half: it watches the air along every line of sight and adds the light the haze scatters toward you, so directional and spot lights become *visible in flight*. The point is that everything a light already carries shapes its beam. The spot's cone becomes the projector cone; a cookie's panes read as tilted bars of bright air before they land as a window on the floor; an IES profile's throw shows its real shape; and with `castShadows()` on, anything standing in the beam carves a dark shaft out of it, the crepuscular rays of a forest morning.

<img src="Images/17-3DGently/VisibleAir.jpg" alt="A dark set under a warm window-gobo beam slanting down from the upper left: the panes read as bars of bright air, land as a window of light on the floor, and a cylinder, sphere, and box carve dark shafts out of the beam. A faint cool beam crosses low behind the props" width="680">

The `anisotropy` knob (−1…1) is how strongly the haze throws light forward: near 1, a beam flares when the view swings toward its source, the headlights-in-fog effect; 0 glows evenly from every side. And the two calls compose either way: with `fog`, the beams live in the fog's own thickness; without it, the air stays clear and *only* the beams appear, which is the dark-stage look of `3D/Lighting/VolumetricLight`. **The air is part of the scene, and light crossing it is something you can draw.**

One habit: the beam march has a quality dial like the shadows do (`volumetricQuality`, three tiers), and the default already does the right thing, frame-rate-safe live, lifted to full quality on export.

## Materials

A material is a surface's whole way of catching light, picked by name. The color still comes from `fill`; the *finish* comes from `material`:

```swift
fill(Color(hex: 0x2C8C86))      // the color
material(.velvet)               // the finish
drawSphere(radius: 1)
```

<img src="Images/17-3DGently/MaterialRow.jpg" alt="Ten spheres in the same teal, each with a different finish: matte, plastic, glossy, iridescent, soap bubble, velvet, jade, toon, gooch, and glitter" width="680">

That's ten finishes on one color. The library runs from matte through glossy to the showpieces: `.iridescent` and `.soapBubble` shift hue as the view moves, `.velvet` glows at the edges, `.jade` lets light through thin parts, `.toon` and `.gooch` are the stylized cartoon and warm-to-cool looks, and `.glitter` is full of tiny mirror flakes that flash as anything moves. `material(_:)` is drawing state like `fill`, saved by `withState`, so every shape in a frame can wear its own.

A `Material` is also a plain value you can tweak. Car paint is the classic recipe, gold flakes over a deep red:

```swift
var paint = Material.glitter
paint.sparkleColor = Color(hue: 0.12, saturation: 0.75, brightness: 1)
material(paint)
fill(Color(hue: 0.02, saturation: 0.8, brightness: 0.4))
drawSphere(radius: 0.62)
```

There's a further tier, the physically based metals and plastics (`material(.metal(roughness: 0.2))`), that really comes alive once a scene has surroundings to reflect. That's the next chapter's territory, where environments light the scene, so treat it as a pointer for now.

## Shading from a picture

Matcaps are the shortcut of the sculpting world. Instead of lights and materials, the entire look, lighting included, is painted into one photograph of a sphere, and every surface point borrows the color the sphere would have there.

```swift
matcap(.chrome)
drawMesh(knot)
```

<img src="Images/17-3DGently/MatcapRow.jpg" alt="The same knot wearing four matcaps: reflective chrome, brown terracotta clay, red car paint, and a flat toon look" width="680">

One call, no lights to place, and the look is total: chrome, clay, car paint, cel shading. It works by asking, for each point on the surface, which way that point is facing relative to you, then reading the color from the matching spot on the sphere picture. Point straight at the camera and you get the middle of the picture; face away toward the edge and you get the rim. Because the picture was lit once, all of that lighting comes along for free, which is why the highlights slide as the view turns and why it reads as a real material rather than a paint job.

The trade is the same fact seen from the other side. **A matcap ignores your lights, your `material(_:)`, and your shadows**, because it isn't lit at all: the light is a photograph. That makes matcaps a separate axis rather than another finish, and it makes them the wrong choice when an object needs to belong to a scene (matched to its lighting, grounded by a shadow) and the right one when you want a good-looking surface with no lighting work, which is most of the time you're sketching a form.

There are 26 built in, real studio captures grouped by family: metals like `.chrome` and `.bronze`, clays like `.terracotta` and `.sage`, ceramics like `.pearl`, translucents like `.wax`, the neutral studio set, `.toon` and `.toonDark`, and a handful of diagnostic ones (`.checkNormal`, `.checkGradient`) meant for reading geometry rather than looking good. Beyond those, `matcap(loadImage("my-matcap.png"))` wears any sphere image you find or paint, and `Matcap.shaded(baseColor:metallic:roughness:)` bakes one on the spot with no asset at all, which is the option to reach for when you want a specific color and don't want to ship a file.

Two smaller things: the current `fill` tints the result, so keep it `.white` to see a matcap as captured, and `matcap(_:)` is drawing state like `fill`, so `withState` scopes it and `noMatcap()` returns to the lit path.

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

The one habit that saves confusion is **`normalized(scale:)`**. A file arrives at whatever size and position its author saved, anywhere from millimeters to kilometers, and normalizing recenters it and scales its longest side to the world units you ask for. Keep the `fill` white so the model's own colors show, because a colored fill tints it. (Models you build yourself are yours to ship, while downloaded ones carry licenses worth checking before you bundle them.)

> **Swift note.** `loadMesh(...)?.normalized(scale: 3)` chains with `?.` because loading can fail: if the file isn't there, `loadMesh` returns `nil`, the chain stops, and `model` stays `nil`. The `if let model` in `draw()` then simply skips drawing, so a missing file never crashes the sketch.

`loadMesh` deliberately flattens a file into one mesh you place yourself. Sometimes the file *is* the placement: a whole scene composed in the design tool, with a camera framing it and lights already set. For that there's `loadScene`, which keeps the file's structure instead of merging it:

```swift
stage = loadScene("Stage.gltf")!            // in setup()

camera(stage.camera ?? .orbiting(radius: 6))   // the file's own framing
for l in stage.lights { light(l) }             // and its lighting
stage["sculpture"]?.rotate(deltaTime, axis: .unitY)
drawScene(stage)                               // every node, in its authored place
```

A scene is a tree of named nodes, and everything unpacks into things you already know: the file's camera is a `Camera3D`, its lights are `Light`s, each node's geometry is a `Mesh`. `drawScene` draws the whole layout where the tool put it, and `stage["sculpture"]` reaches one node by name so a single piece moves while the rest holds still. Bring the set over from the design tool; keep the choreography in the sketch. The `3D/Geometry/LoadedScene` example is a small stage to poke at, and [Scenes](../Docs/3D/Scenes.md) has the details.

If the file was animated in the tool, that motion carries over too. `stage.animations` holds the authored keyframe tracks, and applying one poses the scene at whatever moment you ask for:

```swift
if let spin = stage.animation("spin") {
    stage.apply(spin, at: time.truncatingRemainder(dividingBy: spin.duration))
}
```

The file remembers its motion; the sketch decides when time passes. `apply` takes any time you hand it, so wrapping `time` loops the animation, `time * 0.5` plays it at half speed, and a knob's value scrubs it. The `3D/Geometry/AnimatedScene` example plays a small orrery's authored spin this way, one seamless 8-second lap.

Tracks like the orrery's move whole nodes, rigid pieces on a hierarchy. A file can also carry motion that bends the geometry itself. A *skin* ties each vertex to a few joint nodes with blend weights, so a blade of kelp or an arm flexes smoothly as its joints turn; *morph targets* store alternate shapes for a mesh, and the node's `weights` mix them, the way faces animate between expressions. Both play through the same `apply`, and `drawScene` poses them without any extra calls. The `3D/Geometry/SkinnedScene` example is a small tidepool doing both at once, kelp swaying on skins while an anemone pulses on two morph targets, and since `weights` is just a node property, `tank["anemone"]?.weights = [1, 0]` poses a blend shape from any signal you like.

Whether a mesh came from a file or a generator, there are two other ways to dress it besides lighting a solid surface.

<img src="Images/17-3DGently/SurfaceKinds.jpg" alt="Three spheres side by side: a solid glossy teal one, the same sphere drawn as a pale cyan net of triangle edges, and one wrapped in an orange and cream checker whose squares narrow toward the poles" width="680">

```swift
withState { fill(teal); material(.glossy); drawMesh(globe) }     // solid
withState { stroke(pale); wireframe(); drawMesh(globe) }         // edges only
withState { fill(.white); drawMesh(globe.textured(checker)) }    // wrapped in an image
```

**`wireframe()`** draws the mesh as its triangle edges instead of filled faces, taking the current `stroke` color and `strokeWeight`. It's how you see what a mesh is actually made of, which is genuinely useful when a generator gives you something odd, and it's also just a look: the standard way to show a form that's still a proposal rather than a finished object. Because the faces are see-through, a wireframe doesn't light, so lights and materials have nothing to do.

**`textured(_:)`** returns a copy of a mesh wrapped in an `Image`. Every built-in generator emits the texture coordinates that decide where each part of the picture lands, and the checker above is chosen to make those readable: the squares stay square around the middle and narrow to slivers at the poles, which is what wrapping a flat rectangle onto a ball does and something you'll meet whenever you texture a sphere. A textured mesh still lights normally, so it takes materials and shadows like any other surface. Keep the `fill` white unless you want the image tinted, the same rule as a loaded model.

Both are ordinary drawing state, saved by `withState`, so one frame holds all three treatments (the figure is a single render).

## Smooth from a cage

There is a third way to get a mesh, and it's the one character artists live in: build something crude out of a few boxes and extrusions, then let the computer round it. `subdivided(levels:)` takes any mesh as a **control cage**, splits every face, and eases every vertex toward its neighbors, once per level.

```swift
let cage = Mesh.extrude(Profile.star(), depth: 0.75)
let smooth = cage.subdivided(levels: 2)
```

<img src="Images/17-3DGently/SubdivisionCage.jpg" alt="Three views of the same extruded five-pointed star: the control cage as a pale cyan wireframe, one level of subdivision as a plump amber star with soft edges, and two levels as a much softer orange form sitting inside the ghosted wireframe of the cage whose points now reach far past it" width="680">

You model the cage; the smoothness is computed. One level already turns the slab-sided star into something you'd want to hold, and by two the form has melted well inside its cage, which is the thing to internalize: the smooth surface eases *toward the averages* of the cage, so it always sits inside it, and pointy features round off the fastest. If a shape comes out softer than you wanted, the fix is a chunkier cage, not fewer levels.

Any mesh works as a cage with no preparation. The primitives, an extrusion, a lathe, a loaded model: `subdivided` welds their shared corners and recovers their intended faces before refining, so a box rounds as one closed surface rather than six drifting plates. Open sheets keep their rims (a subdivided `plane` smooths along its edge instead of shrinking away from it). Triangle-native meshes like an icosphere or a marching-cubes blob have their own refinement rules a scheme argument away, `subdivided(.loop, levels: 2)`, and the [reference page](../Docs/Generators/SubdivisionSurfaces.md) covers when to pick which.

Like erosion below, this is `setup()`-shaped work: each level roughly quadruples the face count, so refine once, keep the mesh, and let `draw()` just draw it. Two or three levels is almost always enough.

## A surface that outgrows itself

Subdividing takes a shape you designed and smooths it. This does the opposite: it hands you a shape nobody designed, out of a rule you can say in one sentence.

Take a mesh. Push its vertices apart, and split any triangle that stretches so the triangles stay a fixed size. The surface now has more area than it started with, and here is the part that matters: **nothing is pushing it outward**. The forces run along its own edges, and those lie in the surface. It cannot get bigger the way a balloon does. So the new area has to go somewhere, and the only direction left is sideways. It folds.

```swift
// setup(), and keep it:
growth = MeshGrowth(mesh: .icosphere(subdivisions: 3), driver: .uniform, seed: 7)

// draw():
growth.step()
drawMesh(growth.mesh)
```

<img src="Images/17-3DGently/GrowingSurface.jpg" alt="Three forms in a row against black: a smooth yellow sphere labelled the seed, an orange ball completely covered in even brain-like folds labelled everywhere, and a flattened orange form with a smooth top and a ruffled rim labelled at the equator" width="680">

That middle one is a plain sphere that grew evenly, and it is worth sitting with, because nobody told it to make lobes. Grow a ball uniformly and it does not become a bigger ball; it becomes a brain. Every fold in it is the surface running out of room.

The `driver` decides *where* the growth is fastest, and since every driver folds, what you are really choosing is **where the folds go**:

```swift
MeshGrowth(mesh: seed, driver: .uniform)      // evenly, all over
MeshGrowth(mesh: seed, driver: .curvature)    // wherever it already bulges

// Only near the equator, the way a leaf grows along its margin.
MeshGrowth(mesh: seed, driver: .field { position, _ in
    1 - smoothstep(0.1, 0.5, abs(position.y))
})
```

The third panel is that last one: the poles never grew, so they stayed smooth, and everything the band made had to ruffle. It is the same rule as the lettuce leaf and the kale edge, which grow faster along the rim than through the middle and buckle for exactly this reason.

The two knobs worth knowing early. `edgeLength` is the triangle size, so it sets the finest fold the surface can hold and it is where the cost lives. `stiffness` is how much the surface resists bending, and it decides how *big* the folds come out: a sheet with no stiffness buckles at the smallest scale it can and reads as crumpled paper, while more of it gathers the same growth into broader waves. If a result looks like foil someone sat on, that is the knob.

There is a fourth driver, `.chemical`, that runs a reaction-diffusion pattern in the surface and grows where the pattern collects, so the chemistry decides where to add area and the new area gives the chemistry more room to spread. That is the branching-coral one, and the [reference page](../Docs/Generators/MeshGrowth.md) has it along with self-avoidance, open sheets that keep their rims, and the cost.

Growth is slow on purpose: a form takes hundreds of steps, and stepping once a frame while you watch it develop is most of the pleasure. `maxVertices` is the ceiling that keeps it interactive, and it also decides how far a form gets before it settles.

## A landscape you grow

Loading a mesh gets you a shape somebody else made. Generating one gets you a shape nobody has seen. Terrain is the friendliest place to start, because a landscape is just a height for every point on a grid, and Ollin has a type for exactly that.

```swift
let land = Heightfield.diamondSquare(size: 257, roughness: 0.55, seed: 7)
drawMesh(land.mesh(width: 10, depth: 10, height: 2.2))
```

A `Heightfield` holds heights between 0 and 1, and you can grow one from any field you like, including everything Chapter 5 taught. `Heightfield(columns: 257, rows: 257) { u, v in fbm(u * 3, v * 3, octaves: 6) }` rolls hills, and swapping in `ridgedFbm` creases them into ridges. The `diamondSquare` form above is the classic terrain fractal instead: set the four corners, then repeatedly fill in each square's center and each edge's midpoint with the average of its neighbors plus a random nudge, halving the grid step and shrinking the nudge each round. `roughness` controls how fast the nudges shrink, and around 0.55 reads as landscape. The `size` rounds up to the grid the subdivision needs, which is why it wants numbers like 129, 257, or 513.

Here is the thing that separates a terrain from a cloud of noise, though. Real land doesn't look the way it does because of the rock. It looks that way because water has been running down it for a very long time.

```swift
let weathered = land
    .eroded(.hydraulic(drops: 50_000), seed: 7)
    .eroded(.thermal(talus: 0.012, iterations: 30))
```

<img src="Images/17-3DGently/Erosion.jpg" alt="Three grayscale heightmaps: raw diamond-square noise with soft blobby light and dark regions, the same field after rain with branching valleys carved through it, and after gravity with those valley walls slightly settled" width="680">

`.hydraulic` drops tens of thousands of simulated raindrops on the terrain. Each one lands somewhere random, rolls downhill, picks up sediment while it's moving fast, and drops that sediment again as it slows down or dries out. No single drop does much. Fifty thousand of them agree with each other about where the valleys are, and branching drainage networks appear that no amount of layered noise will give you. The middle panel above is the whole argument for the technique.

`.thermal` is gravity's half of the job. Wherever two neighboring samples differ by more than `talus`, some of that excess slides to the lower one, so cliffs shed into scree slopes and spikes settle to an angle they can actually hold. It's a smaller change than rain, and the third panel shows a gentler version of the second rather than a different landscape, which is exactly what weathering looks like.

<img src="Images/17-3DGently/TerrainMesh.jpg" alt="The eroded terrain standing up as a lit 3D mesh in warm low sunlight, green in the valleys and pale on the ridges, with the carved drainage lines visible across it" width="560">

Once the field is shaped, it reads out three ways. `mesh(width:depth:height:)` gives you a solid mesh with proper normals, `image()` gives you the grayscale heightmap (that's what the three panels are), and `value(atU:v:)` samples any point for placing trees, routing a path, or driving something else entirely. The picture above wears a texture built by walking each height up a `Ramp` from valley green to snow, which is the whole coloring recipe.

One practical note carries all of this. Erosion is genuine work, tens of thousands of drops each walking dozens of steps, so it belongs in `setup()`. Grow the field, weather it, keep the mesh, and let `draw()` just draw it.

## Things with weight

Chapter 9 dropped flat shapes into a physics world and let gravity do the animating. The same world exists in 3D, and it fits the scene you've been building all chapter: crates that stack, balls that roll, chains that swing, with real contact response, under the same lights and shadows as everything else. It comes with `import OllinPhysics`, like its 2D sibling, and it keeps the shape you already know: build a `World3D` once, add bodies, step it every frame.

```swift
let world = World3D()

override func setup() {
    world.ground = 0                     // a static floor at y = 0
    for level in 0 ..< 6 {
        world.addBody(.box(width: 1, height: 1, depth: 1),
                      at: Vector3(0, 0.6 + Double(level) * 1.04, 0))
    }
}

override func draw() {
    background(.black)
    cameraShowcase()
    world.step(dt: deltaTime)
    for body in world.bodies {
        withBody(body) { drawBox(width: 1, height: 1, depth: 1) }
    }
}
```

The one new move is `withBody`. In Chapter 9 you drew a body by translating to its `position` and rotating by its `angle`; a 3D body's orientation is a full spatial rotation, not one number, so `withBody(body) { }` moves the whole transform stack to the body's pose and lets the block draw in body-local space. Whatever you draw there (a box matched to the collider, a loaded mesh, a whole small assembly) rides the body, and it stays ordinary drawing, so materials, shadows, and export all apply untouched.

<img src="Images/17-3DGently/CrateFall.jpg" alt="A pyramid of colored crates caught mid-collapse on a dark floor, crates tumbling and skidding away to the right, the topmost purple crate still in the air" width="560">

The figure is the whole idea in one frame: a crate pyramid built in `setup()` (each crate one `addBody` with a `.box` collider), a dense steel ball thrown at it with an opening `velocity`, and frame 92 of the collapse. Nothing in it is animated by hand, and nothing in it is random either; the solver is deterministic, so this exact wreck replays every run.

Colliders come from a small catalog: `.box`, `.sphere`, `.capsule`, `.cylinder`, their tapered cousins (`.cone`, `.taperedCylinder`, `.taperedCapsule`), a convex `.hull` of your own points, and a static `.mesh` for scenery a body can't be. `connect` links bodies with joints, the 2D kinds plus `.ball`, the free-swiveling socket a hanging chain is made of. And the cursor reaches through the camera: `grabBody(at:in:)` ray-picks the body under the mouse and `dragGrab(_:to:)` slides it across the view at the depth it was picked, which is how you rummage through a pile in a running sketch.

A body doesn't have to be one shape, either. `.compound` fuses several colliders into a single rigid body, each part posed in the body's local space, and the mass, balance, and spin all come from the whole assembly:

```swift
var parts: [Collider3D.Part] = [
    .part(.cylinder(height: 0.2, radius: 0.32),
          rotated: .pi / 2, axis: .unitX, density: 2),   // the metal hub
]
for arm in 0 ..< 4 {
    let angle = Double(arm) * .pi / 2
    parts.append(.part(.box(width: 1.5, height: 0.26, depth: 0.08),
                       at: Vector3(cos(angle), sin(angle), 0) * 1.11,
                       rotated: angle, axis: .unitZ))    // a blade
}
let cross = world.addBody(.compound(parts), at: hubCenter)
```

That's a windmill's blade cross: five shapes, one body. A part's own `density` weighs it against the rest, which is how a hammer gets a head that leads its swing, and `withBody` still draws the whole thing; translate to each part's pose inside the block and draw its shape.

Hinges and sliders can also be *powered*. Give one `limits` when you connect it (measured from the pose it was built in, so 0 means "as built") and the returned joint carries a small motor: `drive(at: 2.5)` turns it at a steady rate, `drive(to: 0)` is a spring servo that seeks a pose and holds it, `stopMotor()` cuts the power, and `friction` is the drag that winds a freewheeling hinge down. The servo's `strength` is a torque cap, and a weak one is a *character* knob, not a compromise: it's what makes a door closer something a thrown ball can still barge through.

<img src="Images/17-3DGently/Windmill.jpg" alt="A four-bladed windmill mid-turn on a dark ground, colored balls scattered across the floor, and two low swing gates on either side both pushed open by balls rolling through them" width="560">

One motored hinge does all the animating here: the compound blade cross from above rides a `.revolute` driven at a constant rate, and the balls it bats away shove through swing gates on either side, each a limited hinge with springy stops (`softenLimits`) held shut by a `drive(to: 0)` closer too weak to argue with a rolling ball. The interactive version is the [`3D/Physics/Windmill`](../Examples/3D/Physics/Windmill/) example, where the space bar cuts the motor and you can watch hinge friction coast the mill to a stop.

And the landscape you grew a few pages back can hold all of this up. `.heightfield` takes a `Heightfield` directly, sized exactly like its `mesh(width:depth:height:)`, so the collider and the drawn mesh trace one surface:

```swift
world.addBody(.heightfield(land, width: 14, depth: 14, height: 4.2),
              at: .zero, kind: .static)
```

<img src="Images/17-3DGently/Rockslide.jpg" alt="Brightly colored rocks, spheres, boxes, and cones, spread mid-slide down a pale eroded mountainside, a gold box caught mid-tumble, green scrub at the foot of the slope" width="560">

The rocks are spheres, boxes, and cones dropped along the ridge, and the ravines the rain carved are the same ravines that funnel them down. For scenery that arrives as a file instead of a field, `world.addStaticColliders(from: scene)` walks a loaded `Scene` and turns every mesh into a static collider at its authored place, so a ball can roll through the hall you imported. The interactive slide, with its perpetual rock feed and a dice knob that regrows the mountain, is the [`3D/Physics/Rockslide`](../Examples/3D/Physics/Rockslide/) example.

## Asking what hit what

So far the world has been something to watch. To make it something to *play*, you need to know when things happen: a ball reached the goal, a crate landed hard, the plate has something on it. Ollin hands that over the way it hands over the mouse. Every `step` leaves a list on the world, and `draw()` reads it:

```swift
world.step(dt: deltaTime)
for contact in world.contacts where contact.phase == .began {
    knocks.append(Knock(at: contact.point, strength: contact.speed))
}
```

No callbacks, and nothing that fires at an awkward moment: just a list that belongs to the step that filled it. Each `Contact3D` says which two bodies met (`a` and `b`, with `contact.other(than: ball)` to save you the guessing), where, which way the surfaces faced, and `speed`, how fast they were closing when they met. That last one is the useful one. It's measured before the solver answers the collision, so it's the size of the *impact*, which means one number can set the volume of a clink, the size of a spark, or the brightness of a flash. Touches are per pair of bodies, so a crate landing on a mesh floor is one arrival, not one per triangle it happens to rest on.

The other half is a body that isn't solid at all. Pass `isSensor: true` and you get a region: things fall through it untouched, and it tells you who's inside.

```swift
let goal = world.addBody(.cylinder(height: 0.5, radius: 1),
                         at: hoopCenter, isSensor: true)

score += goal.entered.count           // crossed during this step
let crossing = !goal.touching.isEmpty // one is in there right now
```

<img src="Images/17-3DGently/Trigger.jpg" alt="A gold-lit ring floating above a teal tray on a dark floor, one orange ball falling away below the ring, four balls resting in the tray, and a thin white circle marking a knock on the ring's rim" width="560">

The hoop in the figure is two bodies in the same place, which is the trick worth stealing: a solid rim of beads a ball can clatter off, and a sensor disc filling the hole. Only a ball that gets *through* enters the sensor, so `goal.entered` is a scoreboard, and the ring lights while one is crossing. The tray below is a sensor too, and its color is `touching.count`.

That tray is also why sensors are built the way they are. A ball that settles in it stops moving, and the solver, sensibly, puts anything that has stopped moving to sleep to save the work; a sleeping body reports no contacts, so a still stack reads as touching nothing. A sensor never sleeps, so it goes on counting what's parked in it long after the balls have dozed off. Events are for the moment something happens; a sensor is for the standing question of what's in here. The playable version, where you can drag a ball and post it through the hoop by hand, is the [`3D/Physics/Trigger`](../Examples/3D/Physics/Trigger/) example.

You don't animate a pile; you drop one.

## Asking what is there

Contacts tell you what the solver noticed while it was stepping. Often you want something it was never asked: whether the lamp can see a crate, how far the floor is below a point in mid-air, what is standing inside a circle you just made up. It knows all of that, because working out what is where is what a collision solver does all day. You just have to ask, and you ask between steps.

Three questions, three calls. **A ray** is a line with a start and an end, and it comes back holding the first thing in the way.

```swift
if let hit = world.raycast(from: lamp, to: crate.position) {
    lit = hit.body === crate        // nothing got in first
}
```

That second line is the whole of line of sight: the crate is visible when the crate *is* what the ray found. Put a pillar between them and the ray comes back holding the pillar instead.

A `Hit3D` says which body, where it touched (`point`), which way the surface faces there (`normal`, which is what a bounce or a scorch mark is built from), and how far along the query the touch was (`distance`). Aim the same call downward and that last one is the height of the drop:

```swift
let drop = world.raycast(from: p, to: p - Vector3(0, 20, 0))?.distance
```

**A sweep** is a ray with a body. It slides a whole shape along the line and reports what the shape runs into.

```swift
let below = world.sweep(.sphere(radius: 0.55), from: overhead, to: patrol)
```

A ray asks what is in the way; a sweep asks whether something fits. That is usually the question you meant. A ray threads a gap a shoulder would never get through, and a ray drops between two crates onto the floor a drone would never have reached. Anything a body can wear works as the probe, turned however you like with `rotated:`, apart from the two colliders that describe scenery rather than a thing: a mesh and a height field.

**An overlap** asks what is inside a region right now.

```swift
for caught in world.bodiesOverlapping(.sphere(radius: 4), at: blast) {
    guard let body = caught as? Body3D else { continue }   // only a solid takes one
    body.applyImpulse((body.position - blast).normalized * 12)
}
```

A blast radius in four lines, and the sphere it asked with never existed. You could build a sensor body there and read `touching` instead, and for a *standing* question, the pressure plate from the last section, you should. But a sensor has to exist before the moment, sit somewhere, and be cleared away after. An overlap is a question asked once, anywhere, with a shape invented on the spot. `bodiesContaining(point)` is the same question with no shape at all.

<img src="Images/17-3DGently/Sightlines.jpg" alt="A dark yard of orange crates and four tall pillars, a pale lamp at the upper left with thin beams reaching the crates it can see, two crates behind the pillars left dark blue, and a small teal drone hovering inside a wide teal ring with a probe line down to a disc on the floor" width="560">

All three are in that yard. The beams are one ray per crate, so the two crates behind the pillars stay dark. The drone is holding its height with a sweep straight down, and the disc under it is where the sweep stopped. The ring is the sphere an overlap just asked with, drawn at its own radius as it fades, since a pulse does not spread: everything inside it was caught at once.

Three habits worth having early. Queries see solid bodies, so a sensor is invisible to them unless you pass `includingSensors: true`, and so is a soft body, which has no single pose to hand back. `ignoring:` is how something casts from inside itself, which you will want the first time a robot's own chassis blocks its view. And none of this steps the world, so you can ask fourteen times a frame, once per crate, and find everything exactly where you left it.

The [`3D/Physics/Sightlines`](../Examples/3D/Physics/Sightlines/) example is the playable version, where you can drag a crate into cover and watch its beam go out.

A query is a question, not a move.

## Someone to be in there

Everything so far you watch. A **character** is something you *are*: a figure that walks where you steer it, climbs what it can climb, and stops at what it can't.

You might reach for a body with a capsule collider and start pushing it around with forces. Don't. A body is at the mercy of the simulation, which is the whole point of a body and exactly wrong here: shove it and it tips over, land it awkwardly and it rolls away, and you spend the evening fighting torques to keep a person upright. A character is a different thing on purpose. It has a shape and it collides, but nothing tumbles it and nothing knocks it down. You hand it a direction and it goes.

```swift
walker = world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(0, 2, 0))
```

Steering it is a `draw()` poll, like the mouse:

```swift
var east = 0.0, south = 0.0
if isKeyDown(.leftArrow)  { east -= 1 }
if isKeyDown(.rightArrow) { east += 1 }
if isKeyDown(.upArrow)    { south -= 1 }
if isKeyDown(.downArrow)  { south += 1 }

let heading = Vector3(east, 0, south)
walker.move(heading.length > 0 ? heading.normalized * 3 : .zero)
if isKeyDown(" ") { walker.jump() }

world.step(dt: deltaTime)
withCharacter(walker) { drawCapsule(radius: 0.3, height: 1.2) }
```

That's a walkable scene: eight lines and a `step`. The same `world.step` moves the character along with the crates, so there's no second update to forget. `move` sets the speed it's *trying* to walk at and keeps it until you say otherwise; falling and jumping stay the world's business, which is why you only give it a horizontal direction. `jump` is granted only if it's on the ground when the step comes round, so holding the key hops rather than flies.

<img src="Images/17-3DGently/Walker.jpg" alt="A small orange figure with a pink cap brim mid-stride on the second of four pale steps, legs apart in a walking pose, two crates it has shouldered aside sitting on the green floor beside the stair" width="560">

`withCharacter` is `withBody`'s twin, and it puts the origin at the character's **feet**. That's the detail that makes drawing one pleasant: model your figure standing on the floor at the origin, and it stands on the floor in the world.

Three numbers decide what the scenery does to it, and each is worth meeting by breaking it:

```swift
walker.stepHeight = 0.4        // the tallest step it walks up: a kerb, a stair
walker.maxSlope = 50 * .pi / 180  // the steepest hill it can climb
walker.pushStrength = 100      // how hard it can shove a crate, in newtons
```

Set `stepHeight` to zero and the stairs in the figure become a wall it stands against forever. Wind `maxSlope` down and a hill it strolled up last run holds it halfway. Set `pushStrength` to zero and those two crates stop being scenery it walks through and start being furniture it walks around. None of that is scripted anywhere; it's the same walk meeting different limits.

Two velocities are worth telling apart. `walker.velocity` is what it's *trying* to do, and `walker.actualVelocity` is what the world let it do. Walk into a wall and the first still reads a brisk pace while the second reads nothing. Drive a walk cycle from the second and the legs stop when the figure stops, which is the difference between a character and a puppet skating on the spot:

```swift
let pace = Vector2(walker.actualVelocity.x, walker.actualVelocity.z).length
stride += pace * deltaTime * 3.4
```

One last thing, and it's the one that connects this section to the last. A character is swept through the world by hand rather than simulated, so strictly it isn't in the scene. It carries a stand-in that is: `walker.body`, an ordinary kinematic body riding inside the capsule. That's what lets everything else notice it, sensors included:

```swift
if lookout.isTouching(walker.body) { /* you're on the platform */ }
```

So the trigger you built for balls works for people, unchanged. The playable version, an eroded island with stairs up to a lookout that lights as you arrive, is the [`3D/Physics/Stroll`](../Examples/3D/Physics/Stroll/) example.

## Something to drive

A character walks. A **vehicle** is the other thing you operate: a body carried on sprung wheels, with an engine behind the pedal. Same idea as the character, one step further out. You don't push it and you don't steer it by force. You press things.

```swift
car = world.addVehicle(.box(width: 1.8, height: 0.7, depth: 4),
                       at: Vector3(0, 2, 0),
                       wheels: [
                           .wheel(at: Vector3( 0.9, -0.15,  1.3), steers: true),
                           .wheel(at: Vector3(-0.9, -0.15,  1.3), steers: true),
                           .wheel(at: Vector3( 0.9, -0.15, -1.3), driven: true, handBrake: true),
                           .wheel(at: Vector3(-0.9, -0.15, -1.3), driven: true, handBrake: true),
                       ])
```

Read that list once and you have the whole machine. Four wheels, bolted where you say, in the chassis's own coordinates. The front two turn. The back two are the ones the engine reaches, and the ones the hand brake grabs. Nothing else about a car needs saying, and the two flags you did say are the ones that decide how it feels.

Driving it is the same shape as walking:

```swift
car.throttle = isKeyDown(.upArrow) ? 1 : (isKeyDown(.downArrow) ? -1 : 0)
car.steering = (isKeyDown(.rightArrow) ? 1 : 0) - (isKeyDown(.leftArrow) ? 1 : 0)
car.handBrake = isKeyDown(" ") ? 1 : 0

world.step(dt: deltaTime)

withBody(car.body) { drawBox(width: 1.8, height: 0.7, depth: 4) }
for wheel in car.wheels {
    withWheel(wheel) { drawCylinder(radius: wheel.radius, height: wheel.width) }
}
```

`withWheel` is `withBody` for a wheel, and it knows where the suspension put it, how far it has rolled, and which way it is pointing. Draw a cylinder in that block and you get a tire, turned and spinning, without ever computing any of it.

Press the throttle and hold a full lock, and the thing you were about to type by hand happens on its own: the car leans, the inside front wheel goes light, the back tires start sliding, and it comes round. Pull the hand brake in the middle of it and only the back wheels lock, because they are the ones you gave a hand brake to. That's the figure below, one frame out of a scripted lap.

<img src="Images/17-3DGently/Joyride.jpg" alt="A red car sliding sideways through a corner marked by a curve of colored cubes, its front wheels turned into the turn and a rear tire glowing yellow where it is spinning" width="560">

The glowing tire is one line: `wheel.slip` is how much that tire is sliding rather than rolling, and coloring by it turns a number into something you can feel.

```swift
fill(Color.mix(Color(hex: 0x232B36), Color(hex: 0xF2A93B),
               t: min(1, wheel.slip)))
```

The car drives along its chassis's **+z**, so model whatever you draw facing that way. Two settings are worth breaking things with. `suspensionFrequency` on each wheel is the spring, in hertz: around 1.5 is a road car, and at 3 you feel every stone. `topSpeed` is the gearing rather than a promise, the speed the machine tops out at on a flat straight; wind it down and the car pulls harder off the line and runs out of legs sooner. Both can be changed while you drive, so put them on `@Param` sliders and feel the same corner three ways.

Two wheels work too. `balances: true` adds the controller that holds a motorcycle up and leans it into turns, and the one thing it needs that a car doesn't is a raked front fork, `casterAngle` around 30°. Without the rake it flops over at the first correction, which is also true of real bicycles and is the nicest small piece of physics in this chapter.

The driveable version, a car over the same kind of eroded island the walker got, is the [`3D/Physics/Joyride`](../Examples/3D/Physics/Joyride/) example.

## Turning without steering

There is a third machine, and it is the same call again with `tracked: true`. The wheels stop being wheels and become road wheels, split into a left and a right band by which side of the hull you put them on. No list to keep in order, no pairs to declare: a wheel at positive x is on the left track, and that is the whole of it.

```swift
var wheels: [Wheel3D] = []
for side in [1.3, -1.3] {
    for i in 0 ..< 5 {
        wheels.append(.wheel(at: Vector3(side, -0.28, -1.8 + Double(i) * 0.9),
                             radius: 0.44, width: 0.6))
    }
}
let crawler = world.addVehicle(.box(width: 2, height: 0.9, depth: 5.2),
                               at: Vector3(0, 1.2, 0), wheels: wheels,
                               mass: 4200, topSpeed: 9, tracked: true)!
```

Throttle and brake mean exactly what they did. Steering is the interesting one, because a track has nothing to turn. Instead the number runs the inside band slower: at half lock it stops, and the machine turns about its own stopped track. At full lock it runs *backwards*, one band forward and one back, and the machine spins where it stands.

**A tracked machine steers with its drivetrain, so it needs throttle to turn at all.** Idle the engine and there is nothing to run one band against the other. That is true of the real thing too, and it is the first thing to try:

```swift
crawler.throttle = 1
crawler.steering = 1        // turn on the spot
```

<img src="Images/17-3DGently/Crawler.jpg" alt="A yellow tracked machine seen from above, standing among a ring of eight colored posts and turned at an angle to them, its far track drawn in orange and its near track in blue" width="560">

The posts are there to say it stayed put. It drove up to the middle, then held the throttle with the stick over, and it is turning between them rather than driving past them. The colors are the two bands: `trackSpeed(.left)` and `trackSpeed(.right)` read how fast each one is running over the ground, and painting one warm when that number is positive and cool when it is negative makes a still picture of a turn readable.

```swift
for side in [Vehicle3D.TrackSide.left, .right] {
    fill(crawler.trackSpeed(side) < 0 ? Color(hex: 0x3F6FA8) : Color(hex: 0xC4622A))
    // …draw that band's links…
}
```

Those two numbers are also what you scroll a drawn track by, and `wheels(on:)` hands you one band's road wheels, front first, to lay it around.

Most of what a wheel knows carries over. The suspension is the same suspension. Two things change meaning, and both are worth knowing. `driven` marks the **sprocket** its band is turned at rather than one of a driven pair, and with none marked each band takes its rearmost wheel. And `grip` scales a flat pair of numbers rather than a tire's slip curve, which is the real difference between a track and a wheel: a tire loses grip once it starts spinning, and a band does not. That is why a crawler walks up a bank a car would sit at the bottom of turning its wheels.

The machine on tracks working a quarry is the [`3D/Physics/Crawler`](../Examples/3D/Physics/Crawler/) example.

## Letting a figure fall

Back in "A mesh from a file" a skinned figure moved because a keyframe track told every joint where to be. That's animation: the same pose every time, whatever else is happening. A **ragdoll** is the other answer. Hand `addRagdoll` the same loaded scene and it reads the skeleton, builds a rigid body for every joint, and hangs each one off its parent on a cone-limited ball joint. Then the world decides where the limbs go.

```swift
figure = loadScene("figure.gltf")!
ragdoll = world.addRagdoll(from: figure, at: Vector3(0, 3, 0))
```

Each limb's shape is fitted to the figure's own mesh rather than guessed from bone lengths: the vertices a joint pulls hardest on get gathered up and a capsule is laid along the way they spread. That's why a torso comes out thick and a forearm thin, from two bones of similar length. You never say how wide anything is.

Then the loop, which is one line longer than an animation's:

```swift
world.step(dt: deltaTime)
figure.apply(ragdoll)     // the pose the solver just found
drawScene(figure)
```

`figure.apply(ragdoll)` is `apply(_:at:)` run backwards. Instead of a keyframe track posing the joints, the simulated bodies do, and everything downstream (the skin, the materials, the shadows) carries on as if a track had. Drop the figure and it falls like something with weight in it, because it is.

That figure will lie where it lands forever, which is the thing people mean by "ragdoll" and also its limit. `drive(toward:)` is the other half:

```swift
target.apply(walk, at: time)             // where the animation wants the limbs
ragdoll.drive(toward: target, strength: effort)
world.step(dt: deltaTime)
figure.apply(ragdoll)                    // where they actually ended up
```

Every joint grows a motor pulling toward the pose the target scene is holding. Now the animation is a *request*, and the world gets a vote. Push the figure and it resists, gives, and comes back. The figure below is one drop, run twice, changing exactly one thing.

<img src="Images/17-3DGently/Ragdolls.jpg" alt="Two identical figures dropped onto a dark floor: the left one lies sprawled on its back, the right one stands upright with its arms out" width="560">

Keep two copies of the scene: one the animation poses (the target) and one the solver poses (the drawn one). A `Scene` is a value type, so that's one assignment, and it matters, because a figure driven toward the scene it was just posed from has nowhere left to pull.

`strength` is the knob to play with. It's the most torque a joint may use, in newton-metres. High and the figure will not be moved; low and the heavy limbs sag out of the pose, which is how a figure reads as tired rather than switched off. Sweep it and you get a whole range of characters out of one number.

Nothing drives the root, so a powered figure still falls over as a whole: the motors hold its shape, not its place. Pin the hips (`ragdoll.limbs[0].body.kind = .kinematic`) and it stands there like a puppet on a hook, which is what the [`3D/Physics/Ragdoll`](../Examples/3D/Physics/Ragdoll/) example does. Press space there and the hips let go.

Two more things worth knowing. Every limb is an ordinary body, so you can grab one with the mouse and drag the figure around by an arm. And each figure gets its own collision group, so a thigh never fights the pelvis it sits inside, while two figures still knock into each other properly.

## Cloth that finds its own shape

Everything in this chapter so far moves as one solid piece. A crate can be anywhere, but it is always crate-shaped. A **soft body** is the other kind of thing: its mesh's vertices *are* the simulation, held to each other by springs, so it arrives at a shape rather than carrying one around.

You build one from any mesh you already know how to draw.

```swift
cloth = world.addSoftBody(from: .plane(width: 3, depth: 3, segments: 24),
                          at: Vector3(0, 3, 0))
```

Then the loop, which has one new call in it:

```swift
world.step(dt: deltaTime)
fill(.beige)
drawSoftBody(cloth)
```

`drawSoftBody` draws the mesh the simulation just arrived at. It is the same mesh you handed over, with new positions and new normals, so its uvs, its colors, and its material all carry through, and shadows and reflections treat it like any other mesh. Drop that sheet on a sphere and it drapes over it, because a hundred particles each found somewhere to be and the springs between them argued about it.

Two knobs decide what fabric it is, and they are separate for a good reason.

```swift
stiffness: 1     // how hard it resists being stretched
bend: 0          // how hard it resists being folded
```

A bedsheet barely stretches at all and folds freely, which is exactly `stiffness: 1, bend: 0` (the defaults). Card is stiff in both. A rubber sheet is the odd one, low stiffness and low bend. Reach for `bend` when a cloth is crumpling more than it should; reach for `stiffness` when it is sagging like a net.

Nothing holds a sheet up unless you say so, and the way you say so is `pinned:`. It gets handed every vertex of the mesh, in the mesh's own coordinates, and answers yes or no:

```swift
pinned: { $0.z < -1.4 }      // hold the far edge, let the rest hang
```

That closure is the whole hanging story: two corners for a flag, one edge for a curtain, a patch in the middle for a handkerchief held up by its middle. You can change your mind later too, with `pin`, `unpin`, and `move(_:to:)`, which drags a particle to a point and lets the rest of the cloth follow.

A **closed** mesh can do something a sheet cannot: hold air.

```swift
ball = world.addSoftBody(from: .icosphere(radius: 0.5, subdivisions: 3),
                         at: Vector3(0, 2, 0), pressure: 3)
```

`pressure` is in gravities: `1` means the air inside pushes out just hard enough to hold the ball's own weight up, and `2` to `4` reads as a firm ball that still dents when it lands. Zero is an empty bag. It is a live number, so a ball can deflate under your hand mid-frame. On a sheet it does nothing, since a sheet has no inside, and Ollin will say so once rather than quietly inventing a shape.

<img src="Images/17-3DGently/Cloth.jpg" alt="A cream sheet draped over a sphere on a dark floor, beside two teal balls: the left one slumped flat, the right one round" width="560">

One last move, because a soft body has no single pose for a force to push on: impulses do nothing to one. `applyForce` does, spread over all its particles, and it is how you make wind.

```swift
banner.applyForce(Vector3(0, 0, gust))
```

The [`3D/Physics/Drape`](../Examples/3D/Physics/Drape/) example puts all of it in one scene: a banner pegged to a washing line, a sheet thrown over a crate, and a ball you can let the air out of, all three draggable. Worth knowing before you build on this: soft bodies collide with the rigid world but not with each other or themselves, so a sheet folded double will pass through its own layers.

## A cape on someone's back

`pinned:` holds a corner of cloth *still*. A cape needs the other thing: held to something that is moving, and left to hang off it. Your figure from a page ago already has the moving thing in it, a skeleton, so you can name which joint of it carries which part of the cloth.

```swift
cape = world.addSoftBody(from: sheet, at: Vector3(0, 0.85, -0.13),
                         rotation: .pi / 2, axis: Vector3(1, 0, 0),
                         pinned: { $0.z < -0.55 },      // clasped at the neck
                         skinnedTo: figure,
                         carriedBy: { _ in "chest" })
```

Then one call a frame, after the figure is posed and before the world steps:

```swift
figure.apply(ragdoll)
cape.follow(figure)
world.step(dt: deltaTime)
```

Nothing was painted in a modelling tool to make that work. **The pose the figure is standing in when you build the cloth is the bind pose**, so you hang the cape where it belongs, name the joints, and everything the figure does from then on is read as the motion since. `carriedBy:` is handed a vertex in the mesh's own coordinates, the same ones `pinned:` gets, and answers with a joint's name or `nil` for a part that is just cloth.

Notice that `pinned:` is doing something new here without changing its meaning: **a pinned vertex is held by whatever holds it.** A joint carries it, so it is held to the figure; if no joint does, it is held to the world, exactly as your banner's top edge was.

<img src="Images/17-3DGently/Cape.jpg" alt="Two identical figures walking, each with a cape: the left cape hangs where it was hung while its figure walks away from it, the right one is still on its figure's back" width="560">

Both figures there are walking the same path. The only difference between them is that one cape names a joint and the other does not.

Three numbers shape what the loose part may do, and all three are plain distances in world units:

```swift
sway: { 0.05 },        // how far from the skin it may get
backStop: 0.04,        // how far into the figure's back it may be pushed
maxStretch: 1.02       // how far it may reach from what holds it
```

`sway` is a leash: `0` welds that part to the skin, the default of `.infinity` lets it swing freely, and `0.05` really does mean five centimetres. `backStop` keeps the cape out of the back it hangs on without waiting for a collision to sort it out. `maxStretch` is the one worth remembering even for cloth no figure carries: a heavy sheet hung from one edge stretches under its own weight however stiff you make it, and `1` (its own rest length, no more) fixes that for almost nothing.

Two knobs work while it runs: `cape.swayScale` multiplies every leash at once, and `cape.followsSkin = false` drops the leashes entirely, leaving only the clasp. The [`3D/Physics/Cape`](../Examples/3D/Physics/Cape/) example has both on keys, and a figure you can knock over so the cape comes down with it.

## A line that knows how it is turned

Cloth is a surface. Plenty of what you want to hang in a scene is not one: a rope, a cable, a chain, a vine, the stem of a plant. Those are curves, and you build one from a list of points.

```swift
let rope = world.addRope(through: (0 ..< 40).map { Vector3(0, -Double($0) * 0.1, 0) },
                         at: Vector3(0, 3, 0),
                         thickness: 0.04,
                         pinned: { $0.y > -0.001 })      // hung from the top
```

Anything that makes points makes a rope, so that list could as easily be a `Contour`, a sampled `Path`, a `randomWalk`, or a ridge you read off a `Heightfield`. The points become the particles one for one, so `pin`, `move(_:to:)`, and `positions` all speak in indices into the list you handed over, and `drawSoftBody(rope)` sweeps a tube of `thickness` along it. Everything from the last few pages still applies: it lands on things, turns up in `world.contacts`, floats, takes `applyForce` for wind, and can be dragged with `grabSoftBody`.

Two knobs shape it, and both mean the same thing on a twig and on a mooring line:

```swift
stiffness: 1,      // how much it resists being stretched
bend: 0            // how much it resists being bent
```

`bend` is the one that decides what the rope *is*. At `0` it is limp rope. Around `0.5` a length sticking out sideways droops about a third of its own length, which reads as heavy cable. Near `1` it holds itself out like a stem.

<img src="Images/17-3DGently/Rope.jpg" alt="Four lines on four posts: the first has folded straight down, the second droops in an arc, the third holds itself straight out, and the fourth hangs as a chain of interlocking links" width="560">

The three on the left were built as the same straight line sticking out from their posts, and differ in that one number.

The fourth is where a rope stops being a line of points. **Every segment carries an orientation of its own**, which you read with `rope.segments`. `withSegment(_:)` stands the transform stack in the middle of one with +y running along the rope, the same way `withBody(_:)` stands it on a body, so a cylinder or a capsule drawn inside the block already lies the right way:

```swift
for segment in chain.segments {
    withSegment(segment) {
        rotate(.pi / 2, axis: Vector3(1, 0, 0))       // lay the ring across the rope
        if segment.index.isMultiple(of: 2) {
            rotate(.pi / 2, axis: Vector3(0, 0, 1))   // roll every other link
        }
        drawTorus(radius: segment.length * 0.6, tube: 0.028)
    }
}
```

That second `rotate` is the whole point. Rolling every other link a quarter turn about the rope's own axis is what makes a chain interlock, and you can only ask that of something that knows how it is rolled. **Three points in a row tell you which way a line is going and nothing about which way is up.** Leaves along a stem, rings on a flag, beads on a string: same move each time.

Two things worth knowing before you build something long. `maxStretch: 1` caps how far a rope may reach from what holds it, which stops a heavy one creeping longer under load. And stiffness travels one segment per solver pass, so a long rope divided finely needs more passes than the default five before a high `bend` really holds: forty points over six units wants about twenty.

A rope does not collide with itself, so a coil passes through its own turns. It also has no surface for a ray to hit, so `raycast` and the other queries look straight through one (the mouse still finds it). And it is a single strand: a plant with three stems is three ropes. The [`3D/Physics/Rigging`](../Examples/3D/Physics/Rigging/) example has a rope, a chain, and a leafy vine hanging in the same wind.

## Water, and what it holds up

A world can have water the same way it has ground. One property, and nothing has to opt in.

```swift
world.water = Water(level: 0)
```

Everything already in the world starts floating. You do not mark a crate as floatable, and you do not pick how high it rides, because you have already said: it is the `density` you built it with.

```swift
world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0, 4, 0),
              density: 0.3)   // cork
world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(2, 4, 0),
              density: 3)     // stone
```

The cork bobs, the stone goes to the bottom, and the interesting part is what happens in between. A body of density `0.5` settles with exactly half of itself under the surface. One at `0.8` rides low with a fifth of it dry. **The waterline is not a setting, it is an answer**: a body sinks until the water it has pushed out of the way weighs the same as it does, which is the whole of buoyancy in one sentence.

Here are four identical crates that differ in nothing but that number.

<img src="Images/17-3DGently/Floating.jpg" alt="Four cube crates floating in a row on still blue water, each sitting lower than the one before it, from a pale crate mostly above the surface to a dark one almost entirely under" width="560">

`Water` has a `density` of its own, on the same scale, where `1` is water and also the default body material. Push it to `1.3` for brine and every crate in the scene rides higher, without touching any of them.

The knob you will actually reach for first is drag.

```swift
world.water = Water(level: 0, linearDrag: 0.5)   // the default
```

At `0` a crate dropped in oscillates about its waterline and never stops, which looks less like water than like a trampoline. The default dips, comes back, and settles in about a second. `angularDrag` does the same for turning, which is what stops a long shape rocking all afternoon after it lands.

Give the surface a shape and it carries whatever is riding it:

```swift
world.water = Water(level: 0, waves: Water.Waves(amplitude: 0.25,
                                                 wavelength: 8, speed: 1.5))
```

Now you have a problem you would have had to solve yourself: drawing water that matches the water. `waterMesh` hands back the surface the bodies are floating on, as an ordinary mesh, so the swell you can see and the swell they ride are the same one.

```swift
if let surface = world.waterMesh(extent: 40) {
    fill(Color(hex: 0x2C7C96))
    material(.dielectric(roughness: 0.3))
    drawMesh(surface)
}
```

Keep a little roughness in that material. A perfect mirror reflects the lower half of the environment wherever a wave tilts the reflection below the horizon, which lays flat grey patches along the troughs, and a sea is not a mirror anyway.

Two things worth knowing before you build on this. `world.water` is an ocean, not a pool: everything below `level` is water, out to the horizon, so a harbour is what you get by putting static walls in it. And the water does not reach everything, on purpose: sensors, static bodies, and a walking character go where you put them rather than where the water would.

The [`3D/Physics/Flotsam`](../Examples/3D/Physics/Flotsam/) example is the whole thing in one scene: crates from cork to nearly waterlogged riding a swell at their own depths, a stone anchor on the bottom, and a current carrying the lot past. Drag one under and let go.

## A raft made of cloth

The sheet from two sections ago floats too, and it is worth a section of its own because it is where the two halves of this chapter meet: the thing with no pose turns out to be an ordinary member of the world.

Floating it is one number.

```swift
raft.density = 0.3           // rides high; above 1 it sinks
```

That reads exactly like a crate's `density`, and it means the same thing: how heavy this is for its size, against the water. A *closed* soft body does not even need telling, because a mass and a volume are all it takes and a beach ball has both. A sheet has no inside, so there is nothing to work it out from, and it starts as heavy as water, lying awash in the surface the way a wet sheet does. The line above is what makes it a raft.

<img src="Images/17-3DGently/Raft.jpg" alt="A flat cloth raft floating on a calm sea carrying two crates, a sounding line hanging from a post beside it" width="560">

Cloth in water behaves like cloth: its area for its weight is enormous, and drag is what measures that, so a heavy sheet sinks slowly and a floating one is carried along by a current rather than left standing in it.

The second half is that a cloth turns up in `world.contacts`, the list from "Asking what hit what". A crate landing on the deck reports where it hit and how hard, exactly like a crate landing on the floor.

```swift
for contact in world.contacts where contact.phase == .began {
    splash(at: contact.point, size: contact.speed)
}
```

The one thing to notice is that a contact names `any Colliding3D`, not `Body3D`. That is deliberate, and it is the type telling you the truth: either side may be a cloth, and a cloth is not something you can push with an impulse or hang a joint from. When you want to act on what you found, say which kind you were after.

```swift
if let crate = contact.other(than: raft) as? Body3D {
    crate.applyImpulse(Vector3(0, 3, 0))
}
```

Everything else about touching works the way it did: `raft.touching` is what is aboard, a sensor sees the raft sail into it, and `raycast` stops at cloth, so a curtain blocks a sightline and a sounding line drops onto a deck.

One asymmetry to keep in mind, because it is useful rather than annoying: a settled *pile of crates* falls asleep and stops reporting its touches, while a settled cloth keeps its list. The solver stops asking a sleeping soft body who it is against, which is not the same as it having let go.

The [`3D/Physics/Raft`](../Examples/3D/Physics/Raft/) example is the three of them in one scene: a cloth raft riding a swell with cargo on it, a sounding line that shortens onto her deck when you sail her under it, and a harbour gate that lights when she passes through. Drag the deck to steer.

## Things that pass through each other

So far everything in a world collides with everything else, which is the honest default and is usually what you want. But a lot of scenes need the opposite of a wall somewhere: sparks that drift through the machine that threw them, a ghost that walks through the door, confetti that does not pile on itself, a laser that only some things stop.

You could reach for that with logic, checking who touched what and undoing it. Ollin gives you the other way round. Put things in a named **group**, then tell the world that two groups never touch.

```swift
let bead = world.addBody(.sphere(radius: 0.2), at: p, group: "beads")
world.ignoreCollisions(between: "beads", and: "grating")
```

That is the whole thing: a word where you build something, and one sentence saying what it does not touch. Here are two identical tubes with identical gratings and the same beads poured into each. The only difference is that the right pour is in a group the grating was told to ignore.

<img src="Images/17-3DGently/Sorted.jpg" alt="Two glass tubes side by side, each with a horizontal grating across the middle. In the left tube a pile of amber beads rests on top of the grating; in the right tube the same number of teal beads has fallen straight through it and lies on the floor below" width="560">

Three things about that sentence are worth having straight.

**It reads both ways.** `ignoreCollisions(between: "beads", and: "grating")` is a fact about a pair, not a direction. There is no version of this where the beads ignore the grating and the grating still stops the beads.

**Naming a group is not a rule.** A world where nobody has written an `ignoreCollisions` behaves exactly like a world with no groups at all, so you can tag things as you build them and decide later what any of it means. That also means a typo in a group name does nothing at all rather than something surprising, which is worth remembering when a rule seems to have been ignored. `world.collisionGroups` prints what the world actually heard.

**A group still collides with itself.** Two crates in one group stack normally. If you want confetti that drifts through its own drift, say so:

```swift
world.ignoreCollisions(between: "confetti", and: "confetti")
```

Everything you can add to a world takes a group, the same way it takes a density: bodies, characters, vehicles, ragdolls, soft bodies, and the static scenery you import from a `Scene`. And a rule holds everywhere the pair could have met, which matters more than it sounds. A filtered pair does not collide, does not turn up in `contacts`, is not seen by a sensor, is walked through by a character (including another character), and is not felt by a vehicle's wheels. There is no corner of the world where the rule half-applies.

Groups also change what a question sees. Every query from earlier in this chapter takes `as:`, which asks it the way a body of that group would ask it:

```swift
world.ignoreCollisions(between: "bullets", and: "glass")

world.raycast(from: muzzle, to: target)                  // stops at the pane
world.raycast(from: muzzle, to: target, as: "bullets")   // goes right through
```

That is the piece that turns filtering from a physics trick into something you can aim with: a sight line that ignores foliage, a ground probe that ignores the character doing the probing, a targeting ray that only sees what its own shot would hit.

You can move something between groups while it runs, too. `body.group = "debris"` takes effect on the next step, and things already settled on each other are woken so the world looks at the pair again, which is how a crate that was scenery a moment ago becomes something to fall through.

The [`3D/Physics/Sieve`](../Examples/3D/Physics/Sieve/) example is a sorting machine built out of nothing else: beads of three colors roll down one ramp with three windows set into it, each window told to ignore one color. Press space and the three rules are withdrawn, and the same machine stops sorting.

## Taking a direction away

A rigid body can do six things: travel along three axes and turn about three. You can take any of them away.

That sounds like a small setting. The first thing it buys is not. A lot of sketches want a flat world: a pin table, a side-on machine, a puzzle of tiles that slide. Building one in 2D means giving up lighting, shadows, and solid shapes. Building it in 3D means every collision quietly pushes things toward and away from the camera until the whole thing stops reading as flat. So say the bodies may not go that way.

```swift
let bead = world.addBody(.sphere(radius: 0.2), at: p, freedom: .plane())
```

Below are two identical pin boards. The same beads are poured down each, one at a time, and every bead is given the same careless sideways nudge on the way down. The beads on the left are held to the board's plane. The ones on the right are not.

<img src="Images/17-3DGently/Flattened.jpg" alt="Two identical pin boards standing in open-fronted bins. At the foot of the left board nine teal beads lie in a single straight row, all at the same depth. At the right board the same nine amber beads are scattered: a few still in the bin at different depths, several out on the open floor in front of it" width="620">

The left beads had nowhere to put that nudge, so they landed in one flat sheet. The right ones took it and left. **A locked direction is not a rule the body tries to obey; it is a direction the body no longer has.** Nothing can move it that way: not gravity, not a contact, not a joint, not even a velocity you set on it yourself.

There are names for the combinations worth wanting, and you can spell out anything else:

```swift
.all                        // the default
.plane()                    // travels in x and y, turns about z: a flat world
.plane(normal: .unitY)      // travels in x and z, turns about y: a top view
.upright                    // travels any way, turns only about up, never tips
.noTurning                  // slides and is shoved, never spins
.noMoving                   // spins where it is, never travels
[.moveX, .turnZ]
```

`.upright` is the other one you'll reach for: a fridge on a dolly, a chess piece, anything that should slide and turn without ever falling over. The one thing you cannot ask for is a tilted plane, because what the solver takes away is whole world axes, so `.plane(normal:)` rounds its normal to the nearest one.

Two smaller knobs live next to it. **`gravityScale`** is how hard the world pulls on one body against the `1` everything else feels, which is a balloon and a feather in the same world:

```swift
balloon.gravityScale = -0.3      // rises
feather.gravityScale = 0.15      // falls a sixth as far in the same second
```

And **`checksPath`** is for things that are small and quick. A body that covers more than its own width between two steps can be in front of a thin wall at one step and past it at the next, having touched nothing on the way. Turn this on and the solver sweeps the body's shape along its whole path instead of only testing where it ended up:

```swift
let pellet = world.addBody(.sphere(radius: 0.05), at: muzzle, checksPath: true)
pellet.velocity = Vector3(0, 0, 120)
```

It is off by default because it is not free, but it is close: the check only runs once a body is actually moving fast for its size, so an ordinary throw lands in exactly the same spot either way. Turn it on for bullets, pellets, and anything you fire, and leave it alone for everything else.

All three can be set when you add a body and changed while it runs. The [`3D/Physics/Bagatelle`](../Examples/3D/Physics/Bagatelle/) example is a pin table with all three on a knob: flatten the balls or free them, make them heavy or weightless, and fire a shot quick enough to leave through a thin rail the moment you stop checking its path.

## Machines out of joints

A hinge and a slider will get you a door and a drawer. A machine wants more, and the joints left over are each one idea.

**A track.** Hand `.path` a ring of points and the second body is threaded onto the smooth curve through them, free to travel along it and nothing else. A rollercoaster car, a bead on a wire, a camera on a dolly rail:

```swift
let ride = world.connect(rails, cart,
                         .path(through: points, looping: true,
                               alignment: .followsPath))
ride.drive(at: 6)          // world units per second along the track
ride.progress              // 0 at the first point, 1 at the last
```

The curve runs *through* the points rather than between them, so a dozen of them describe a long smooth track. `alignment` decides how much of the body's turning the track takes over: `.free` leaves it tumbling, `.followsPath` banks it into every bend. A flat `Contour` becomes a track on the ground in one call, which means you can draw the route with the curve tools from Chapter 13 and then ride it.

**A rope over two hooks.** `.pulley` ties two bodies to one length of rope, so one side rising is the other falling. Read it the way you would trace it with a finger:

```swift
world.connect(tray, counterweight,
              .pulley(from: trayTop, over: leftHook,
                      and: rightHook, to: weightTop))
```

Rope behaves like rope: it resists being pulled longer and gives when it is let slack, so both ends can drop together but neither can stretch. `ratio: 2` threads the second side twice, which is a block and tackle: that side moves half as far and lifts twice as much.

**The joint that is just a list of freedoms.** Every kind so far is a choice out of the six things a body can do, the same six the last section took away. When none of the named kinds fits, say which ones you're keeping:

```swift
// A post a platter rides: it may rise and it may spin, and nothing else.
world.connect(post, platter,
              .allowing([.moveY, .turnY], at: top, travel: 0...1.4))
```

`.allowing([])` is a weld. `.allowing([.turnX, .turnY, .turnZ])` is a ball joint. One turn with a range is a hinge. It is worth writing those three out once, because it shows what the whole set is made of.

**And two joints that tie other joints together.** Here is the shift worth slowing down for. **A gear does not connect two wheels; it connects two hinges.** What is tied together is not the bodies but the *motion the joints allow*, so that is what you name:

```swift
let small = world.connect(frame, pinion, .revolute(at: hub, axis: .unitZ))
let big = world.connect(frame, wheel, .revolute(at: farHub, axis: .unitZ))
world.connect(small, big, .gear(teeth: 20, and: 40))
```

Turn either hinge now and the other turns, the opposite way, at the ratio you asked for. Its sibling ties a hinge to a slider, so turning becomes sliding:

```swift
world.connect(big, rack, .rackAndPinion(travelPerTurn: 2 * .pi * pinionRadius))
```

`travelPerTurn` is how far the bar runs for one full turn of the pinion, which for a pinion of radius `r` is its own circumference. Both links compose: the machine below is one motor, two links, and four bodies.

<img src="Images/17-3DGently/Machines.jpg" alt="A small toothed wheel meshed with a wheel twice its size on a timber back plate. Each wheel has one pale spoke, and the two are at clearly different angles. Below them a steel bar has slid to the right and pushed four teal blocks into a bunch at the end of their shelf" width="620">

The motor only ever turns the small wheel. The big wheel is turning because the gear link says it must, half as fast and the other way, and the bar is sliding because the rack link says a turn of that same shaft is a distance along the shelf. The pale spokes are there so you can see the two wheels are not at the same angle.

One gotcha, and it will be your first one: real gear teeth mesh, and plain cylinders just jam into each other. Tell them not to collide.

```swift
world.ignoreCollisions(between: "gears", and: "gears")
```

The [`3D/Physics/Contraption`](../Examples/3D/Physics/Contraption/) example is a workshop with one of each: that drive train, a hoist you can load, a platter allowed only to rise and spin, and a cart on a track. Drag any of it.

## Keeping what settled

Some arrangements you don't design, you find. A heap of stones tipped in one at a time and left to rock itself quiet is one of them: four hundred steps of falling and leaning went into it, and there is no way to write it down as code. It only exists in the world's memory, and closing the sketch loses it.

So save it. `snapshot()` takes the whole world as it stands, and `restore(_:)` puts it back:

```swift
let settled = world.snapshot()      // once the heap has come to rest
// …knock it over, drag stones out of it, wreck it…
world.restore(settled)              // exactly the heap you had
```

A snapshot is a value you can keep, so it also goes to a file, which is how a heap survives quitting:

```swift
override func setup() {
    world.ground = 0
    if !world.load(contentsOf: file) {   // nothing there the first time
        buildTheHeap()
        try? world.save(to: file)
    }
}
```

Restoring is not "roughly where things were". Every body comes back in the same pose, moving at the same speed, spinning the same way, and, if it had gone to sleep, still asleep, so a saved heap doesn't shudder back into shape as it arrives. A door saved standing half open is still half open, and still stops where it used to, because a joint remembers the pose it was made in and the snapshot remembers that too.

Now, you might reasonably ask why any of this is needed. If the code that built the heap is right there, why not run it again?

<img src="Images/17-3DGently/Kept.jpg" alt="Three heaps of flat stones side by side on a dark floor. The first two, labelled saved and restored, are identical stone for stone. The third, labelled simulated again, is a visibly different heap" width="720">

Three heaps, all from the same code. The first was simulated and captured. The second is that capture restored, which is exact. The third was simulated again with one stone released a ten-millionth of a unit higher, and that is the whole difference in the setup. Stones landing on stones magnify it: one lands a little differently, which tips the next, and by the twelfth you have a different heap.

That is not a bug, it is what falling stones are. It does mean the same code can give you a slightly different heap on a machine whose floating point rounds one bit differently, which is exactly the situation a committed figure or a piece you want to keep is in. **Simulating it again gives you *a* heap; only saving gives you *that* heap.**

A snapshot holds every body with its collider and all its knobs, every joint between them, gears and racks, the collision groups and their rules, and the world's gravity, ground, bounce, and water. It also holds the things you built on top of those. A character comes back mid-stride. A vehicle comes back drivable and still under power, with its engine turning at the speed it was turning and its wheels already spinning, so a truck restored at speed carries on rather than pulling away from rest. A ragdoll comes back where it fell.

That last one is worth a moment, because it is the one that looks impossible. A ragdoll was built from a skinned figure loaded off disk, and a file of physics has no business carrying a mesh. It doesn't. What the solver actually holds is a shape per limb, the tree they hang in, and how far each joint may bend, and *that* is small enough to write down. The skin stays where it always was: your asset, in your sketch, loaded the ordinary way. So the snapshot and the sketch each keep the half they are good at, and `figure.apply(ragdoll)` puts them back together:

```swift
world.restore(saved)
figure = world.ragdolls.first     // the bodies are new ones
skin.apply(figure)                // your mesh, over the restored pose
```

One thing to watch throughout: restoring empties the world first, so any `Body3D`, `Vehicle3D`, or `Character3D` you were holding onto is gone. Take them from `world.bodies`, `world.vehicles`, and `world.characters` again. They come back in the order they were saved, and each body still knows its own `collider`, which is usually all a drawing loop needs.

There is one more thing worth saying about size, and it follows the same idea one step further. Almost everything in a world is small. A box is three numbers. But a terrain collider is thousands of samples, and a cloth is a whole mesh, and those get written into the file every single time you save. So name them instead:

```swift
island.assetName = "island"
banner?.assetName = "banner"
```

and say what the names mean on the way back in:

```swift
world.restore(saved) { name in
    name == "island" ? .heightfield(terrain) : .mesh(sheet)
}
```

On a yard with a terrain floor in it that is the difference between a hundred kilobytes and one. The trade is real, though, and it goes both ways: a snapshot that names nothing is self-contained, which is what lets you commit it beside the sketch and open it anywhere, so that stays the default. A name the resolver doesn't recognize costs you that one body and a note, not the restore. And a cloth needs a name to be saved at all, because a cloth is nothing but its mesh.

That is one direction: keeping a world you found. The other is picking up one somebody else made. A `.usd` file can say which of its prims are physical, and `world.addBodies(from: scene)` reads the lot, so a sketch that loads such a file writes no physics of its own:

```swift
let scene = loadScene("yard.usda")!
world.addBodies(from: scene)
```

Bodies, colliders, joints, masses, materials, gravity. Reading it is lossy, and that is exactly why it works: a file's description of a body is a description, and anything it leaves out has a sensible answer waiting. Writing the same format would not be, which is why the two jobs use two formats. Import to pick up an arrangement; snapshot to keep one.

The [`3D/Physics/Cairn`](../Examples/3D/Physics/Cairn/) example is a heap of stones laid one at a time. Wreck it by dragging, press R and it is back exactly; press S, quit, and run it again, and the same cairn is standing there. [`3D/Physics/Yard`](../Examples/3D/Physics/Yard/) does the same for a yard with a truck in it, a figure pacing across, another lying where it fell, and a terrain floor and a banner that the file names rather than holds. And [`3D/Physics/Imported`](../Examples/3D/Physics/Imported/) goes the other way: its `yard.usda` is hand-written, and the sketch is a camera and a drawing loop.

## What the depth buffer is for

Chapter 14 filtered layers by their color. A 3D scene drawn into a layer carries something extra that a flat drawing never has: for every pixel, how far away the thing at that pixel is. That's the **depth buffer**, and three effects exist purely to use it.

```swift
let scene = renderTarget()
withTarget(scene) { /* your 3D scene */ }

drawImage(scene.combined(with: scene.depth,
                         .ambientOcclusion(radius: 0.7, intensity: 1.5)).image, 0, 0)
```

<img src="Images/17-3DGently/DepthEffects.jpg" alt="Three panels of the same field of pale blocks on a ground plane: plain, then with ambient occlusion darkening the gaps and contacts, then with depth of field leaving one band of blocks sharp while the front and back blur" width="680">

`scene.depth` is an ordinary layer whose brightness is distance, so it feeds `combined(with:)` like any other, and everything else in Chapter 14 still applies.

**`.ambientOcclusion`** darkens the places light struggles to reach: crevices, the gaps between objects, and the line where something meets the ground. Compare the first two panels and the blocks stop floating. That single change is most of what makes a render read as solid rather than pasted together, and it costs one line because the depth layer already knows where the crevices are.

**`.defocus`** is a camera lens. It keeps a band of distance sharp, set by `focus` and `range`, and blurs everything else more the further it is from that band, up to `maxBlur`. It's how you point at one thing in a busy scene. Both `focus` and `range` are read against the depth layer's `0...1`, so they depend on the camera's `near` and `far`, which is why setting those to actually bracket your scene matters rather than leaving them enormous.

**`.screenSpaceReflections`** makes a floor glossy by reflecting the scene in it, and it runs on any Mac. It has one limit worth understanding rather than being surprised by: it reflects what is on the screen, and a picture does not contain the back of anything. Where the true reflection would be of a surface the camera cannot see, such as the underside of a ball resting on a floor, it can only approximate, which shows as a soft zone right at the contact. A touch of `roughness` hides it, and Chapter 18 has the exact alternative.

All three take a `quality` tier, `.performance`, `.default`, or `.detail`, which trades frame rate for smoothness. The tier is relative to your machine rather than an absolute setting, so `.default` means "the balanced choice for this GPU" and buys more samples on a faster one. Raising it to `.detail` for a final export is the usual move, since the export doesn't have to keep up with a display.

## Keeping your bearings

3D scenes are easy to get lost in, so the tools for finding yourself again are built in. `cameraView(.front)` snaps the camera to a canonical angle (front, top, left, isometric, and friends) and `resetCamera()` returns to the opening shot. The host apps put the same snaps in a **Camera** menu (⌘0 through ⌘7), so they work on any running sketch without a line of code. Two more calls help while you build: `cameraAxis()` shows a small clickable x-y-z compass, and `groundGrid()` lays a faint reference floor. Both are development chrome, drawn only in the live window, never in an export, which is why you won't find them in any figure in this chapter.

One more thing to keep straight as you combine features. Ollin draws several *kinds* of 3D thing, and they don't all take the same finishes. Solid meshes are the fullest citizens, taking materials, textures, shadows, and reflections. The raymarched fields of Chapter 18 take materials, environments, and shadows but arrive by a different route. Point clouds are camera-facing splats and take neither lighting nor shadows, which is exactly right for what they are. None of this is arbitrary, since each kind is a different way of getting pixels on screen, but it does mean a material that transforms a mesh may do nothing to a cloud. When something you expected to apply doesn't, the [combining reference](../Docs/3D/Combining.md) is a table of what stacks with what.

## Putting it together: the plaza

The finished piece is a small sculpture court you curate yourself: five plinths, five pieces, each wearing a different finish, under golden-hour light with soft shadows, on a camera that orbits until you take over. Make `MySketches/Plaza.swift`:

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

<img src="Images/17-3DGently/Plaza.jpg" alt="The finished plaza: five sculptures on plinths, glossy, velvet, glittering, toon, and wireframe, under warm low light with long soft shadows" width="560">

Everything in it is this chapter: meshes built once, plinths placed with the transform stack (note how each block translates to its spot, draws the plinth, then keeps translating upward for the piece), one preset for the light, one `castShadows()`, and a different material per sculpture. The last piece is drawn with `wireframe()`, mesh edges only, the standard look for a form that's still a proposal.

Then make it yours:

- Recast the show by swapping in a supershape, a lathe of your own profile, or a loaded model on the tallest plinth.
- Relight it: `.noir` turns the court into a crime scene, `.moonlight` into a garden at night. Put the preset on a `@Param` menu knob.
- Give the pearl's plinth a slow `rotateY` of its own and let the whole pedestal turn.
- Try `matcap(.chrome)` on the gem and notice what stops responding: lights, shadows, everything but the view.

## Where this comes from

The camera-on-an-orbit model is the shared convention of 3D tools everywhere, from CAD turntables to the orbit controls of three.js. The lighting model under the materials is Blinn-Phong shading, Jim Blinn's 1977 refinement of Bui Tuong Phong's specular model, the workhorse of real-time graphics for decades. The toon and warm-to-cool finishes descend from the non-photorealistic rendering literature, notably Amy Gooch and colleagues' 1998 technical illustration shading. The three-point lighting behind the presets is a film-set convention nearly as old as film. Matcaps grew up in the digital-sculpting world, where painters bake a whole studio into one sphere image. The supershape formula is Johan Gielis's superformula (2003), while the lathe and extrude are as old as pottery and pasta. Diamond-square terrain comes from Alain Fournier, Don Fussell, and Loren Carpenter's 1982 paper on stochastic models, the same line of work that put fractal mountains in *Star Trek II*. The droplet erosion follows Hans Theobald Beyer's 2015 thesis on hydraulic erosion for procedural terrain, and thermal weathering is the talus-angle relaxation from Ken Musgrave, Craig Kolb, and Robert Mace's 1989 paper on eroded fractal terrains. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [3D](../Docs/3D/3D.md): the full reference for cameras, primitives, meshes, lights, materials, matcaps, shadows, and loading models, including the environment lighting and ray-traced reflections this chapter only waved at.
- [Camera control](../Docs/3D/Camera.md): `cameraShowcase`, the cinematic move catalog, view snaps, and the input surface underneath.
- [Combining 3D features](../Docs/3D/Combining.md): the practical map of what stacks with what (which geometry takes materials, casts shadows, appears in reflections).
- Lens and grounding effects: draw a 3D scene into a render target and its depth layer feeds Chapter 14's combine effects, `.defocus` for camera-like depth of field, `.ambientOcclusion` to darken contacts and crevices, `.screenSpaceReflections` for glossy floors on any Mac. See [Effects](../Docs/Drawing/Effects.md#combined) and the `3D/SceneDefocus` example.
- [Shadows in full](../Docs/3D/3D.md#shadows): how each caster kind works, the soft-shadow quality dials, and the frustum fitting you never have to touch.
- [Atmosphere](../Docs/3D/Atmosphere.md): the full fog and volumetric-light reference, what participates and what sits out, and the quality dial's exact step counts.
- [Scenes](../Docs/3D/Scenes.md): the full `loadScene` reference, what carries over from a glTF file (nodes, cameras, punctual lights, animations, skins, and morph targets) and from a USD file (nodes, cameras, its UsdLux lights, area kinds included, its transform animation, timeSamples arriving as one animation `apply(_:at:)` plays, and its UsdSkel skins and blend shapes, joints arriving as nodes you can pose by name), how intensities are normalized, and building a `Scene` in code.
- Textures and wireframes: [`Mesh.textured(_:)`](../Docs/3D/3D.md#textures) also takes a `baseColor` for tinting a shared texture, and [`Mesh.uvs`](../Docs/3D/3D.md) is where the coordinates live if you're generating your own geometry.
- [The 26 built-in matcaps](../Docs/3D/3D.md#the-built-in-matcaps), listed by family, plus `Matcap.shaded` for baking one from a color.
- [Terrain](../Docs/Generators/Terrain.md): building heightfields from noise or subdivision, every erosion knob, and reading a field out as a mesh, an image, or samples.
- [3D physics](../Docs/Simulation/Physics3D.md): the full `World3D` reference, every collider and joint kind, forces and impulses, the camera-grab machinery, and [saving a world](../Docs/Simulation/Physics3D.md#snapshots) to load back later, with the `3D/Physics` examples (a tower under cannon fire, a pile you can rummage through, a wrecking ball on a chain).
- Worked examples: [`Examples/3D/Geometry/Solids`](../Examples/3D/Geometry/Solids/Sketch.swift), [`Examples/3D/Geometry/ShapeFactory`](../Examples/3D/Geometry/ShapeFactory/Sketch.swift), [`Examples/3D/Geometry/Transforms`](../Examples/3D/Geometry/Transforms/Sketch.swift), [`Examples/3D/Lighting/LightingPresets`](../Examples/3D/Lighting/LightingPresets/Sketch.swift), [`Examples/3D/Lighting/Shadows`](../Examples/3D/Lighting/Shadows/Sketch.swift), [`Examples/3D/Materials/Materials`](../Examples/3D/Materials/Materials/Sketch.swift), [`Examples/3D/Materials/Matcap`](../Examples/3D/Materials/Matcap/Sketch.swift), [`Examples/3D/Geometry/LoadedMesh`](../Examples/3D/Geometry/LoadedMesh/Sketch.swift), [`Examples/3D/Geometry/LoadedScene`](../Examples/3D/Geometry/LoadedScene/Sketch.swift), and [`Examples/3D/Geometry/Terrain`](../Examples/3D/Geometry/Terrain/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 16, Simulations](16-Simulations.md) · Next: [Chapter 18, Sculpting with fields](18-SculptingWithFields.md)
