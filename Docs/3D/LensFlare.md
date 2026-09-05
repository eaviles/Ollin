#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Lens flare`</sup>

---

## Lens flare: the light the camera adds by itself

Everything else the renderer draws is the light and the surface. A flare is neither, because it comes from the *camera* itself.

A lens is meant to bend light toward the sensor. Some of that light bounces off the glass surfaces instead of passing through them. Light that bounces twice ends up travelling the right way again, so it lands on the sensor where it does not belong. That misplaced light is a **ghost**. A lens flare is a chain of ghosts along the line from a bright source through the middle of the frame.

<img src="../../Guide/Images/26-SculptingWithFields/GhostChain.jpg" alt="A dark room with a small bright lamp. A dark red hexagon sits on the lamp and a teal hexagon sits up and to the left of it, lying on top of a near black slab" width="640">

`lensFlare()` renders that chain. You give it a lens rather than a look. Which ghosts appear, where each one sits, how big it is, and what color it comes out all follow from the lens's own glass.

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
- [The star on the source](#star) - `star`, `starSize`
- [The lens](#lens) - `Lens.heliar`, `stopped(to:)`, `multicoated()`
- [Writing your own prescription](#prescription)
- [The iris](#iris) - `Camera3D.apertureBlades`
- [Which sources flare](#sources)
- [Seeing the source](#seeing)
- [How it works](#how)
- [Notes](#notes)

<a id="on"></a>
### Turning it on

```swift
lensFlare()                                       // the bundled lens, strength 1
lensFlare(amount: 0.4)                          // the same, held back
lensFlare(amount: 1, lens: .heliar.stopped(to: 11))
lensFlare(LensFlare(lens: myLens, amount: 1.2, reach: 0.8, sourceSize: 0.02))
noLensFlare()                                     // back off (the default)
```

`LensFlare` carries four things:

- `lens` - the glass the ghosts come from. [`Lens.heliar`](#lens) by default.
- `strength` - how strong the flare is. `1` is the default reading and `0` removes it. A higher value pushes the flare past what a lens would really do. **Use this to keep the flare honest**. A flare is a lens defect, and a piece may want it in small measure or not at all. So turn `strength` down until the flare reads as light in the camera rather than as paint on the picture.
- `star` - how strong the [star on the source](#star) is, on top of `strength`. `0` gives you the ghosts with no star.
- `starSize` - how far the star reaches from its source, as a fraction of the frame height, measured with the iris wide open. Stopping down grows it from there.
- `reach` - how far outside the frame a source still flares, as a fraction of the frame height. A source just off the edge is the classic flare, so the default value reaches past the frame.
- `sourceSize` - how large the renderer treats the source as being, as a fraction of the frame height. This is the disc the [visibility test](#seeing) reads, so a bigger source fades more gradually as something crosses it.

The flare needs a **perspective** 3D camera and at least one light. An orthographic camera has no angle to give a source, so it never flares.

<a id="star"></a>
### The star on the source

The ghosts are one half of a flare. The star is the other half, and it sits on the source itself, which is the one place the ghosts never sit.

The arms of the star are light **bending at the edges of the iris**. Far from an opening, what its edges do to a wave is the opening's own Fourier transform. So what lands on the sensor is a picture of the opening turned inside out. Six blades put six arms on the star, for the same reason they put six sides on a ghost.

<img src="../../Guide/Images/26-SculptingWithFields/StarPoints.jpg" alt="A dark room with a small bright lamp above a row of blocks. Six golden arms reach out from the lamp, fanning into color at their tips, around a blown-out core" width="640">

```swift
lensFlare(LensFlare(amount: 1, star: 1.4, starSize: 0.5))   // a bigger, stronger star
lensFlare(LensFlare(star: 0))                                 // the ghosts, and no star
```

Three things follow from how the arms are made:

- An **odd** blade count gives **twice** as many arms. No two of its edges are parallel, so each edge throws an arm of its own. Five blades give ten arms.
- A **round** iris (`apertureBlades` at 0, the default) throws no arms at all, only a halo.
- **Stopping down grows the star** while it shrinks the ghosts. Light spreads more around a smaller opening, which is why a landscape at f/16 gets long rays and a portrait wide open gets almost none.

The tips of the arms fan into color because a longer wavelength bends further, so red reaches past blue.

The renderer works the pattern out once rather than every frame. The opening only changes when the blade count does, and the f-number scales the drawn size rather than the shape. The first frame that flares pays for the transform, around 15ms, and every frame after it samples the result.

The size of the star is chosen rather than measured, and it is worth saying why. A real star's arms are visible only because the source is thousands of times brighter than the scene. That is why even the faint tail of an arm still clears the black point. That reach is far outside what a bake of this size can hold. What stays physical is the shape of the star and how it answers the iris. `starSize` is the control for the size.

<a id="lens"></a>
### The lens

A lens is a stack of interfaces, which are the curved and flat boundaries light crosses on its way to the sensor. Each interface carries a radius, a thickness to the next one, and the refractive index of the glass after it. That stack is what a lens designer writes down, and it is what decides the flare.

`Lens.heliar` is the bundled lens. It is a five-element Heliar-type portrait lens of about 100mm from the 1950s. It holds a cemented front doublet, a single middle element, the iris, and a cemented rear doublet. That comes to nine interfaces and thirteen ghosts. Few surfaces means few ghosts, and they come out large and clean, which is the classic photographic flare.

```swift
Lens.heliar                          // wide open, single coated
Lens.heliar.stopped(to: 16)          // iris closed: every ghost smaller and harder
Lens.heliar.multicoated()            // ghosts in different colors instead of one
Lens.heliar.multicoated(from: 480, to: 620)
```

- **`stopped(to:)`** closes the iris to an f-number, which shrinks every ghost together. A ghost is a picture of the opening the light came through, so a smaller opening gives a smaller ghost.
- **`multicoated()`** coats each exposed surface for a different wavelength, the way a modern lens is made. One coating everywhere gives every ghost the same color, which is the single magenta cast of an older lens. A spread of coatings puts a lens's ghosts in greens, ambers, and blues.

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

Up to four sources flare in one frame, and if the scene holds more, the brightest four are used. The brightest source in the frame sets the scale, and the others fall off against it. That way `strength` means the same thing whatever numbers a sketch lights its scene with.

A light is invisible by itself, so a sketch usually draws something where the source is, the way it would for an [area light](./3D.md#lights). A flat single-color matcap ignores the scene lighting, which is what a glowing thing looks like:

```swift
let glow = Image(width: 1, height: 1, color: Color(hex: 0xFFF6E2))
withState {
    translate(lamp)
    fill(.white)
    matcap(glow)
    drawSphere(radius: 0.17)
}
matcap(nil)
```

<a id="seeing"></a>
### Seeing the source

This test is what keeps a flare from reading as a sticker on the frame. The flare's strength follows how much of its source the camera can actually **see**. So something passing in front of a light fades its flare instead of switching it off.

The renderer reads the scene's own depth over a small disc around each source, sized by `sourceSize`. As an occluder covers more of that disc, the flare dims with it. A sample that falls outside the frame counts as seeing the source. A source just off the edge is the classic flare, and the depth buffer knows nothing about what is out there.

A fixture drawn around its own bulb does not block the flare it is there to make. The depth the renderer compares against sits a little in front of the light, so a small lamp sphere is passed over.

<a id="how"></a>
### How it works

The flare is worked out with first-order (paraxial) optics, in the matrix form (see `ATTRIBUTION.md`, Techniques). Every interface is a small matrix acting on a ray. A ray is measured by how far off the axis it runs and how steeply. A whole light path through the lens is therefore one matrix product. For each pair of interfaces that can reflect, the renderer multiplies that path out. The path runs forward to the far interface, back to the near one, then forward to the sensor. Both bounces have to stay on one side of the iris, since light that reflects across it would have to cross the opening three times.

Because that product is linear, a ghost maps a point on the front opening to the sensor by one scale and one shift. So there is nothing to trace at draw time. The fragment runs the map **backwards**, from the pixel it is shading to the point on the front opening whose light would have landed there. It then asks two questions. Did that point start inside the opening, and did it clear the iris? Light that answers yes to both is that ghost's contribution to that pixel.

Color comes from the anti-reflective coating. A coating is a quarter of a wavelength thick, so the reflections off its two faces cancel. That cancelling works only for the wavelength the coating was cut for, and only head on. What survives is both colored and angle dependent. That is why a ghost near the corner of the frame is a different color from one near the middle. A cemented junction between two glasses carries no coating, because the cement is already between them. It reflects only the little that plain Fresnel gives it.

The star is the same opening read a different way. Its pattern is the power spectrum of the opening's own image, taken once with a Fourier transform. The renderer samples that pattern a wavelength at a time, each at its own scale, which is what fans the arms into color. Nearly all of a star's light is in its core, so the bake is scaled to put its *mean* at 1. The core then runs thousands of times above that and blows out, which is what a source does.

The whole flare composites into the linear frame after the temporal resolve and the motion blur, and before the frame filters. That puts it in linear light and ahead of the tone map. A flare is light arriving at the sensor, not paint on the finished picture.

<a id="notes"></a>
### Notes

- **Put a bloom after it.** The flare composites before the frame filters. A `postProcess(.bloom(...))` then glows the ghosts the way it glows everything else bright.
- **The scale is anchored, not physical.** Two coated interfaces pass on a few parts in ten thousand. A real flare shows only because the sun is many thousands of times brighter than anything it lights. A sketch's lights carry no such range, so one number sets the level. Everything under that number stays as the optics worked it out. That covers how the ghosts compare to each other in size, place, and color. It also covers how each source compares to the others in the same frame.
- **One ghost usually blows out.** A lens generally has a ghost that lands near focus. That ghost puts all its light in a small hot dot, which is what it does in a photograph too.
- **The scene's motion never streaks it.** The flare is added after the motion blur, because it belongs to the camera. It does not belong to anything moving in front of the camera.
- **Cost** runs from a tenth of a millisecond to about one millisecond at 1080 square, for one source on an M2. That time is spent on the GPU. What moves the number is how much of the frame the ghosts cover, since a pixel no ghost reaches leaves the loop immediately. The star's pattern is baked once on the CPU and costs one texture read after that.
- **2D costs nothing.** No camera means no flare, so the pass is never encoded.
- The example is [`Examples/3D/Effects/LensFlare`](../../Examples/3D/Effects/LensFlare/Sketch.swift). Run it with `swift run --package-path Examples Example-3D-Effects-LensFlare`.
