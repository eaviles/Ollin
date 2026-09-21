#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Lens flare`</sup>

---

## Lens flare: the light the camera adds by itself

Everything else the renderer draws is the light and the surface. A flare is neither, because it comes from the *camera* itself.

A lens is meant to bend light toward the sensor. Some of that light bounces off the glass surfaces instead of passing through them. Light that bounces twice ends up travelling the right way again, so it lands on the sensor where it does not belong. That misplaced light is a **ghost**. A lens flare is a chain of ghosts along the line from a bright source through the middle of the frame. Some land beyond the source and some land across the center from it.

<img src="../../Guide/Images/26-SculptingWithFields/GhostChain.jpg" alt="A dark room with a small bright lamp up and to the left. Coral and lavender hexagons nest on the lamp. A blue-gray hexagon sits down and to the right of it, toward the middle of the frame, lying across a near black slab. Larger, fainter hexagons trail off both ways along the same line" width="640">

`lensFlare()` renders that chain. You give it a lens rather than a look. Which ghosts appear, where each one sits, how big it is, what shape it is bent into, and what color it comes out all follow from the lens's own glass, because every ghost is worked out by following real rays through it.

```swift
override func draw() {
    camera(...)
    pointLight(.white, at: lamp, intensity: 16)
    lensFlare()                       // the bundled lens, at its default reading
}
```

The flare is per-frame state, like the lights and the camera, so call it in `draw()` after both. A frame that does not call it renders exactly as it did before the flare existed, and costs nothing.

### Contents

- [Turning it on](#on) - `lensFlare(...)` / `noLensFlare()`
- [The star on the source](#star) - `star`, `starSize`, `wear`
- [Streak, dirt, and halo](#extras) - `streak`, `dirt`, `halo`, off until asked for
- [The lens](#lens) - `Lens.standard`, `Lens.doubleGauss`, `Lens.heliar`, `stopped(to:)`, `multicoated()`, `anamorphic()`
- [Inside a ghost](#inside) - its bent shape, the barrel's cut, caustics, the colored rim, the soft edge
- [Writing your own prescription](#prescription) - `LensInterface`, `abbeNumber`
- [The iris](#iris) - `Camera3D.apertureBlades`
- [Which sources flare](#sources)
- [Seeing the source](#seeing)
- [How it works](#how)
- [Notes](#notes)

<a id="on"></a>
### Turning it on

```swift
lensFlare()                                       // the standard lens, amount 1
lensFlare(amount: 0.4)                          // the same, held back
lensFlare(amount: 1, lens: .heliar.stopped(to: 11))
lensFlare(LensFlare(lens: .doubleGauss.stopped(to: 5.6), amount: 1.2, reach: 0.8, sourceSize: 0.02))
noLensFlare()                                     // back off (the default)
```

`LensFlare` carries seven things, and [three extras](#extras) that are off until you ask for them:

- `lens` - the glass the ghosts come from. [`Lens.standard`](#lens) by default.
- `amount` - how strong the flare is. `1` is the default reading and `0` removes it. A higher value pushes the flare past what a lens would really do. **Use this to keep the flare honest**. A flare is a lens defect, and a piece may want it in small measure or not at all. So turn `amount` down until the flare reads as light in the camera rather than as paint on the picture.
- `star` - how strong the [star on the source](#star) is, on top of `amount`. `0` gives you the ghosts with no star.
- `starSize` - how far the star reaches from its source, as a fraction of the frame height, measured with the iris wide open. Stopping down grows it from there.
- `wear` - how worn the iris is, from `0` to `1`. It is what turns the star's ruled arms into [a real one](#star).
- `reach` - how far outside the frame a source still flares, as a fraction of the frame height. A source just off the edge is the classic flare, so the default value reaches past the frame.
- `sourceSize` - how large the source is, as the radius of the disc it fills, in fractions of the frame height. The [visibility test](#seeing) reads that disc, so a bigger source fades more gradually as something crosses it. It also sets [how soft every ghost's edge is](#inside).

The flare needs a **perspective** 3D camera and at least one light. An orthographic camera has no angle to give a source, so it never flares.

<a id="star"></a>
### The star on the source

The ghosts are one half of a flare. The star is the other half, and it sits on the source itself, which is the one place the ghosts never sit.

The arms of the star are light **bending at the edges of the iris**. Far from an opening, what its edges do to a wave is the opening's own Fourier transform. So what lands on the sensor is a picture of the opening turned inside out. Six blades put six arms on the star, for the same reason they put six sides on a ghost.

<img src="../../Guide/Images/26-SculptingWithFields/StarPoints.jpg" alt="A dark room with a small bright lamp above a row of blocks. Six golden arms reach out from the lamp, each a close frayed pair with fine needles between them, around a blown-out core. A pale hexagon sits on the lamp, and up and to the left a small soft disc with a red rim" width="640">

```swift
lensFlare(LensFlare(amount: 1, star: 1.4, starSize: 0.5))   // a bigger, stronger star
lensFlare(LensFlare(star: 0))                                 // the ghosts, and no star
```

Three things follow from how the arms are made:

- An **odd** blade count gives **twice** as many arms. No two of its edges are parallel, so each edge throws an arm of its own. Five blades give ten arms.
- A **round** iris (`apertureBlades` at 0, the default) throws no arms at all, only a halo.
- **Stopping down grows the star** while it shrinks the ghosts. Light spreads more around a smaller opening, which is why a landscape at f/16 gets long rays and a portrait wide open gets almost none.

- Stopping down also **dims the arms as it lengthens them**. The iris moves the flare's light around and neither adds nor removes any. The same light along longer arms leaves each stretch of arm fainter.

The tips of the arms fan into color because a longer wavelength bends further, so red reaches past blue.

A perfect opening throws perfect arms, and no real star looks like that. `wear` is the wear on the opening. The blades of a worn iris do not sit quite evenly, so opposite edges stop being parallel and each arm splits into a close pair. The edges bow by a hair, which frays an arm into a narrow fan. Specks and hairline scratches lie across the opening, and each one bends a little light of its own. Spread across the colors, that light becomes the fine needles between the arms and the faint grain around the source.

```swift
lensFlare(LensFlare(wear: 0))      // a clean opening: ruled arms and nothing else
lensFlare(LensFlare(wear: 1))      // a well-used lens
```

The wear is drawn from the blade count, so one opening always makes the same star. The default is `0.5`.

The renderer works the pattern out once rather than every frame. The opening only changes when the blade count or the wear does, and the f-number scales the drawn size rather than the shape. The first frame that flares pays for the transform, around a tenth of a second, and every frame after it samples the result.

The size of the star is chosen rather than measured, and it is worth saying why. A real star's arms are visible only because the source is thousands of times brighter than the scene. That is why even the faint tail of an arm still clears the black point. That reach is far outside what a bake of this size can hold. What stays physical is the shape of the star and how it answers the iris. `starSize` is the control for the size.

<a id="extras"></a>
### Streak, dirt, and halo

Three more parts of a flare do not come from the lens's own glass. All three are `0` by default, so a flare that does not ask for them is unchanged.

```swift
lensFlare(LensFlare(streak: 1))                          // a line through every light
lensFlare(LensFlare(streak: 0.8, streakAngle: .pi / 2))   // the filter turned upright
lensFlare(LensFlare(dirt: 0.7))                          // a lens that wants cleaning
lensFlare(LensFlare(halo: 0.6, haloSize: 0.3))           // a ring round the light
```

**`streak`** is what cylindrical glass does to a light. A cylinder bends light one way and not the other, so it fans a light out to either side, across itself and no other way, into one line. That line passes through the source, runs as thin as the source is wide, and tapers toward its ends. The front group of an anamorphic lens is cylindrical and throws it. A streak filter is a glass ruled with fine cylindrical grooves, made to throw the same line on any lens. `streakLength` is how far it reaches each way, in frame heights. `streakAngle` turns it, in radians, with `0` level. `streakTint` is its color. On an anamorphic lens that is whatever the coatings on the cylindrical glass send back, and a streak filter is sold tinted to match. Blue is the one the look is known by. This is the long line through the lights of a night street.

**`dirt`** is grime on the front element, from `0` to `1`. Dirt that close to the lens is far too near to be in focus, so each speck becomes a soft blur **the shape and size of the iris**. That is why a dirty lens takes a clean picture until it is turned toward a light. Then each speck scatters a little of that light into the camera, mostly onward the way it was already going, so the specks nearest the light glow brightest. They take the blades' shape from `apertureBlades`, they grow as the iris opens, and they fade with the rest of the flare as something covers the source. The specks stay where they are from frame to frame, the way dirt does.

**`halo`** is the thin rainbow ring around a light, red outermost, and `haloSize` is its radius in frame heights. Unlike everything else on this page it is **a look and not optics**. Nothing in a lens of plain spheres draws that ring. The nearest real thing is the corona that fine mist makes around the moon, and that comes with a central glow some fifty times brighter than its ring, which would drown the frame. So this is the ring that flare artwork draws, offered as that.

<a id="lens"></a>
### The lens

A lens is a stack of interfaces, which are the curved and flat boundaries light crosses on its way to the sensor. Each interface carries a radius, a thickness to the next one, and the refractive index of the glass after it. That stack is what a lens designer writes down, and it is what decides the flare.

Two lenses are bundled, and they flare very differently.

`Lens.doubleGauss` is a six-element double Gauss of 100mm at f/2 from the 1950s. It has two single elements outside and two cemented doublets facing each other across the iris. Most fast normal lenses since have been built on that layout. Its ten glass surfaces make twenty ghosts in a good run of sizes, so it strings the chain a lens flare is known for. Wide open its ghosts are broad and faint, a veil more than a chain. Stopped down they sharpen into separate polygons.

`Lens.heliar` is a five-element Heliar-type portrait lens of about 100mm, also from the 1950s. It holds a cemented front doublet, a single middle element, the iris, and a cemented rear doublet. That comes to nine interfaces and thirteen ghosts. Most of them are wide and faint, and the barrel cuts them rather than the iris, so this lens veils the frame more than it chains across it.

`Lens.standard` is what `lensFlare()` uses when you name no lens: the double Gauss, multicoated, stopped to f/8. Any lens wide open throws ghosts so broad that they read as haze, and a single coating makes them all one color. A few stops down with a modern coating is where a flare looks like one.

```swift
Lens.heliar                          // wide open, single coated
Lens.heliar.stopped(to: 16)          // iris closed: every ghost smaller and harder
Lens.heliar.multicoated()            // ghosts in different colors instead of one
Lens.heliar.multicoated(from: 480, to: 620)
Lens.doubleGauss.multicoated().stopped(to: 11)
```

- **`stopped(to:)`** closes the iris to an f-number, which shrinks the ghosts the iris shapes. A ghost is a picture of the opening the light came through, so a smaller opening gives a smaller ghost. **It gets brighter as it shrinks**, by as much as it shrank: the same light in a smaller shape. That is why a lens wide open hazes the frame and the same lens at f/16 throws hard bright polygons. A ghost the barrel bounds rather than the iris does not shrink, so it does not brighten either. It sets the lens's `fStop`, which is `nil` while the iris sits wide open at the opening the prescription gives it. A `Lens` also carries its `coatingWavelength` in nanometers, the wavelength its anti-reflective coating is tuned for: a coating cancels its own wavelength best and the ones either side of it least, which is why the ghosts come out colored rather than gray. Around 550 is the usual choice, the middle of what the eye sees best. Each `LensInterface` in the stack carries its own `coating` wavelength, and the one with `isIris` set is the adjustable opening that shapes every ghost and the star.
- **`multicoated()`** coats each exposed surface for a different wavelength, the way a modern lens is made. One coating everywhere gives every ghost the same color, which is the single magenta cast of an older lens. A spread of coatings puts a lens's ghosts in lavenders, reds, and blues. The wavelengths are handed out so that surfaces next to each other land far apart in the range. A ghost is made by a pair of surfaces and the brightest pairs are neighbors. A plain front-to-back sweep would give each such pair two coatings nearly alike, and the whole chain would come out in one color.

- **`anamorphic(squeeze:)`** puts an anamorphic front group on the lens, and it changes the look a good deal, so it is something you ask for. That group is cylindrical glass that squeezes a wide view onto a narrow frame, and the picture is stretched back out when it is shown. Everything that forms *behind* it is stretched with the picture: at the usual `squeeze` of `2` the ghosts, the star, and the [halo](#extras) come out twice as wide as they are tall, and the star's arms lie flatter. What stretches is the shape the iris gives a ghost. The source itself is as round on the frame as it ever was, so a ghost's edge is as soft across as it is up and down, and a ghost near focus, which is a picture of the source, stays round. The [streak](#extras) stays one thin line, and the [dirt](#extras) on the front keeps its shape. The tall oval an anamorphic lens is known for belongs to blur far from the lens. It rounds off as the blurred thing comes closer, and on the front glass itself it is as wide as it is tall. `1.33` and `1.5` are the milder squeezes. It sets the lens's `squeeze`, which is `1` on an ordinary lens. Pair it with [`streak`](#extras), since the same cylindrical glass throws both.

```swift
lensFlare(LensFlare(lens: .standard.anamorphic(), streak: 1))
```

<a id="inside"></a>
### Inside a ghost

A ghost is not a flat copy of the iris in one color. Every ghost is followed ray by ray through the real glass, and five things show for it.

**It is bent.** A lens's surfaces are spheres, and a sphere bends a ray near its rim by more than proportion says. So a ghost's sides stretch and lean, more the further the source sits from the middle of the frame. Some ghosts pass the iris first and are bent hard afterwards, and those come out as a hexagon with curved-in sides and sharp corners.

**The barrel cuts it.** A ray can clear the iris and still stray past the rim of an element further along, where the lens stops it. Where a ghost ends in a curve instead of a straight side, that is the round barrel showing. On a lens of wide ghosts the barrel removes most of what the iris let through.

**Light gathers inside it.** Neighboring rays can land on top of one another. Where they do the ghost is brighter, along a rim or in a core. That is a caustic, the same thing as the bright line at the bottom of a cup of tea.

**The color runs across it, and the rim is fringed.** A coating's color depends on the angle light meets it at, and each ray meets each surface at its own angle. So one ghost is one color in its middle and another toward its edge. Glass also bends blue more than red, by an amount that is the glass's Abbe number. A ghost bright enough for it to show is followed once per wavelength, seven across the spectrum, so its colors part smoothly where it ends. Both bundled lenses carry the Abbe numbers their patents print.

**The edge is as soft as the source is wide.** A ghost is a picture taken *with* the source. Every point of the source throws its own copy, shifted a little, and the copies add up. So a wider source softens a ghost's edge. `sourceSize` is the control.

```swift
lensFlare(LensFlare(sourceSize: 0.004))   // a distant street lamp: hard, crisp ghosts
lensFlare(LensFlare(sourceSize: 0.04))    // a big soft lamp: the ghosts melt at the edge
```

From a small enough source the light also **rings** just inside a ghost's edge, the way it does at any sharp edge a short way from a screen: a bright line along the rim, then fainter ones inside it, tinted because each color rings at its own spacing. A wider source blurs the rings away before it blurs anything else.

One kind of ghost is handled apart. A ghost that lands almost in focus, seen from a source wider than the opening it came through, stops being a shape at all and becomes **a small soft picture of the source**. Its bends and caustics are smeared out by then, so it is worked out to first order, where that smear has an exact form. Set `sourceSize` to the size of what you drew at the light, and that ghost comes out the right size.

<a id="prescription"></a>
### Writing your own prescription

A lens patent prints the same table that `Lens` holds, so you can type a published prescription in directly. Distances are in millimeters, read from the front of the barrel toward the sensor, and `ior` is the medium *after* each interface.

Here are the first rows of the bundled lens, as an example of the shape. Its front group is a cemented doublet, which is two glasses meeting at the second surface, with air after the third.

```swift
let lens = Lens(interfaces: [
    LensInterface(radius:  30.810, thickness: 7.700, ior: 1.652, height: 14.5),
    LensInterface(radius: -89.350, thickness: 1.850, ior: 1.603, height: 14.5),
    LensInterface(radius: 580.380, thickness: 3.520, ior: 1.000, height: 14.5),
    // ... the middle element ...
    LensInterface.iris(thickness: 3.000, height: 11.6),
    // ... the rear group, ending with the gap to the sensor ...
])
```

A radius of `0` is a flat surface, and `height` is the radius of the clear opening. Only two of those openings matter to a flare: the front interface, which is the entrance pupil, and the iris.

A patent also prints each glass's Abbe number, usually in a column headed ν or V. Pass it as `abbeNumber` and the ghosts get their [colored rims](#inside) from the real glass. Leave it out and a typical value for that index stands in.

```swift
LensInterface(radius: 30.810, thickness: 7.700, ior: 1.652, height: 14.5, abbeNumber: 58.6)
```

More interfaces means more ghosts. That is why a modern zoom flares in a busy scatter of small shapes, where a triplet throws three large ones. A lens that makes more than 24 ghosts keeps the 24 that will show.

<a id="iris"></a>
### The iris

A ghost is a picture of the opening the light came through, so the opening's shape is the ghost's shape. That opening belongs to the camera:

```swift
var camera = Camera3D(eye: ..., target: ...)
camera.apertureBlades = 6            // 0 (the default) is a round iris
self.camera(camera)
```

A real lens carries five to eleven blades. The same setting shapes the out-of-focus highlights that the [path-traced export](../Output/PathTraced.md) renders through `Camera3D.aperture`. It also shapes the highlights of a scene defocused by its own depth in the live view ([`.defocus`](../Drawing/Effects.md#combined)). All three read that one setting, so none of them can disagree about what lens this is.

<a id="sources"></a>
### Which sources flare

Every [`Light`](./3D.md#lights) in the frame can flare: directional, point, spot, and the area kinds. A directional light flares from the point at infinity its rays come from, which is where the sun would be. The rest flare from their own position.

Up to four sources flare in one frame, and if the scene holds more, the brightest four are used. The brightest source in the frame sets the scale, and the others fall off against it. That way `amount` means the same thing whatever numbers a sketch lights its scene with.

A light is invisible by itself, so a sketch usually draws something where the source is, the way it would for an [area light](./3D.md#lights). A flat single-color matcap ignores the scene lighting, which is what a glowing thing looks like:

```swift
let lamp = Vector3(1, 2.1, -2)
let glow = Image(width: 1, height: 1, color: Color(hex: 0xFFF6E2))
withState {
    translate(lamp)
    fill(.white)
    matcap(glow)
    drawSphere(radius: 0.1)
}
matcap(nil)
```

Tell the flare how large that thing is on the frame with [`sourceSize`](#inside), and the ghosts come out as soft as a source that size would make them.

<a id="seeing"></a>
### Seeing the source

This test is what keeps a flare from reading as a sticker on the frame. The flare's strength follows how much of its source the camera can actually **see**. So something passing in front of a light fades its flare instead of switching it off.

The renderer reads the scene's own depth over a small disc around each source, sized by `sourceSize`. As an occluder covers more of that disc, the flare dims with it. A sample that falls outside the frame counts as seeing the source. A source just off the edge is the classic flare, and the depth buffer knows nothing about what is out there.

A fixture drawn around its own bulb does not block the flare it is there to make. The depth the renderer compares against sits a little in front of the light, so a small lamp sphere is passed over.

<a id="how"></a>
### How it works

A ghost is worked out by following rays (see `ATTRIBUTION.md`, Techniques). A grid of rays is laid across the front opening, all arriving from the light's direction. Each is carried through the actual spherical surfaces along one ghost's path: forward to the far reflecting surface, back to the near one, forward again to the sensor. The surfaces are met in the order the path names them, and the ray is bent by the real law of refraction at each. The grid lands on the sensor as a bent mesh. The light each cell carried in is spread over whatever area that cell ends up covering, which is what draws a caustic where the mesh bunches up. Both bounces have to stay on one side of the iris, since light that reflects across it would have to cross the opening three times.

Every ray records two things along the way. One is where it crossed the iris, and the ghost's shape is the iris's shape read at that point. The other is the furthest it strayed toward the rim of any element, and a pixel whose rays strayed past a rim is the barrel's cut. Both are read per pixel between the rays, so a coarse grid still gives a clean edge. A ray that cannot leave a glass is lost, and its neighbors are already dark, since what crosses a surface falls to nothing as a ray nears that angle.

The same paths are also worked out to first order, as a product of small matrices, one per surface. That form makes a ghost one scale and one shift. It is what decides how fine a grid a ghost needs, which ghosts are bright enough to draw at all, and what level the whole flare is set at, and it draws the one kind of ghost that is a picture of its source. The two are checked against each other: a real ray close to the axis has to land where the matrices say, to parts in a million, for every ghost.

Color comes from the anti-reflective coating. A coating is a quarter of a wavelength thick, so the reflections off its two faces cancel. That cancelling works only for the wavelength the coating was cut for, and only head on. What survives is both colored and angle dependent. That is why a ghost near the corner of the frame is a different color from one near the middle, and why one ghost changes color from its middle to its rim. Each ray's two reflections are worked out at the angle that ray met them at. A cemented junction between two glasses carries no coating, because the cement is already between them. It reflects only the little that plain Fresnel gives it.

The ghosts are drawn on a canvas half the frame's size each way, four samples to a pixel, and read back through a smooth sampler. They are the dear half of a flare, and they are the half that can afford fewer pixels, since a ghost's edge is never sharper than its source is small. The samples are for the one edge no softening reaches: where a ghost's mesh folds over itself along a caustic, the fold is a plain geometric edge. The star is the other way round. Its needles are a pixel wide, so it is added at full size.

The star is the same opening read a different way. Its pattern is the power spectrum of the opening's own image, taken once with a Fourier transform. The renderer samples that pattern a wavelength at a time, each at its own scale, which is what fans the arms into color. Nearly all of a star's light is in its core, so the bake is scaled to put its *mean* at 1. The core then runs thousands of times above that and blows out, which is what a source does.

The whole flare composites into the linear frame after the temporal resolve and the motion blur, and before the frame filters. That puts it in linear light and ahead of the tone map. A flare is light arriving at the sensor, not paint on the finished picture.

<a id="notes"></a>
### Notes

- **Put a bloom after it.** The flare composites before the frame filters. A `postProcess(.bloom(...))` then glows the ghosts the way it glows everything else bright.
- **The scale is anchored, not physical.** Two coated interfaces pass on a few parts in ten thousand. A real flare shows only because the sun is many thousands of times brighter than anything it lights. A sketch's lights carry no such range, so one number sets the level. Everything under that number stays as the optics worked it out. That covers how the ghosts compare to each other in size, place, and color. It also covers how each source compares to the others in the same frame.
- **The level belongs to the lens.** It is set once, with the iris wide open and a source of a standard size, under two ceilings. No single ghost comes out brighter than a fixed level, which is what holds a lens of few compact ghosts. All of them together add no more than a fixed average to the frame, which is what holds a lens whose ghosts are all wide. Nothing about the frame moves it, so no ghost changes brightness because another one did.
- **A small source sharpens everything.** Crisp polygons, bright caustic rims, and rings inside the edges all belong to a small source. Give the source a size and they soften together, and a ghost near focus becomes [a soft picture of it](#inside).
- **The scene's motion never streaks it.** The flare is added after the motion blur, because it belongs to the camera. It does not belong to anything moving in front of the camera.
- **Cost** runs from about one millisecond a frame to about five, at 1080 square on an M2 for one source. A stopped-down lens with compact ghosts is at the low end. A lens whose ghosts each fill the frame, wide open, is at the high end, since every one of them has to be filled in. It was measured with the GPU kept busy, frames back to back, against the same scene with no flare. A ghost too faint to show is not drawn at all. Only ghosts bright enough for a fringe to show are followed once per wavelength. The streak, the dirt, and the halo cost nothing that can be measured.
- **2D costs nothing.** No camera means no flare, so the pass is never encoded.
- The example is [`Examples/3D/Effects/LensFlare`](../../Examples/3D/Effects/LensFlare/Sketch.swift). Run it with `swift run --package-path Examples Example-3D-Effects-LensFlare`.
