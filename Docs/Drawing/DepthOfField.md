#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Depth of field from light`</sup>

---

## Depth of field from light

A blurred photograph is not a sharp picture with a blur on top. It is many rays of light that each landed in a slightly different place, because they passed through the lens out of focus. Ollin can render a picture the same way. Draw a scene as millions of faint points. Move every point to a random spot in a ball, and let the ball grow with the point's distance from the plane of focus. Then add all the points up as light. Lines on the focal plane stay sharp, and the rest softens into bokeh. There is no blur filter. The blur comes from where the light fell.

`LineSpray` is that technique as one call. It is built from four smaller features that you can also use on their own. They are the `.light` particle style, the `Accumulator`, the `Bokeh` lens value, and the `develop` filter that prints the result.

<img src="../Images/RingSphere.jpg" alt="A sphere made of a hundred and fifty rings of latitude seen through a real lens: the rim on the lit side crisp and bright, the far side dissolved into pale fog, and a burst of light at the center where short spokes pile up" width="680">

### Contents

- [LineSpray](#linespray) - lines of light through a lens, converging over frames
- [Bokeh](#bokeh) - the lens
- [Accumulator](#accumulator) - the running mean under it
- [The light particle style](#light) - particles that deposit light for an additive sum
- [develop](#develop) - printing accumulated light
- [Building your own](#own) - the same pipeline from the compute primitives
- [Notes](#notes)

<a id="linespray"></a>
### LineSpray

Give a `LineSpray` an array of `SprayLine`s once, in `setup()`. Then draw it every frame while a camera is set:

```swift
var spray: LineSpray!

override func setup() {
    var lines: [SprayLine] = []
    for i in 0 ..< 400 {
        let a = Vector3(random(-5, 5), random(-5, 5), random(-5, 5))
        let b = a + Vector3(random(-1, 1), random(-1, 1), random(-1, 1))
        lines.append(SprayLine(from: a, to: b, color: .white, intensity: 0.5))
    }
    spray = makeLineSpray(lines, sampling: .byLength(pointsPerPass: 50_000), passesPerFrame: 5)
    spray.bokeh = Bokeh(focalDistance: 20, strength: 0.08, minSize: 0.02)
}

override func draw() {
    background(.black)
    camera(.orbiting(target: .zero, radius: 20, azimuth: 0.4, elevation: 0.3, fieldOfView: .pi / 8))
    drawLineSpray(spray)
    drawImage(spray.developed(exposure: 400, ground: Color(hex: 0x151010)).image, 0, 0)
}
```

Each frame, `drawLineSpray` scatters `passesPerFrame` passes of points along the lines on the GPU, and adds them into a running mean. Every point is a new spot on its line. Ollin then moves that spot to another spot inside the bokeh ball around it, and projects it through the sketch's `Camera3D`. The mean converges as passes add up, so the longer the sketch runs, the smoother the bokeh gets. When you change the camera, the lens, the lines, or the point size, the average restarts on its own. It restarts because the samples drawn before no longer describe the picture. `spray.passes` tells you how far it has converged.

A `SprayLine` is a segment with a tone at each end, an intensity, and a weight:

```swift
SprayLine(from: a, to: b, color: .orange, endColor: .white, intensity: 2, weight: 1)
```

- `color` and `endColor` are sRGB tones. Ollin linearizes them before they become light. `intensity` (and `endIntensity`) is the light emitted per pass, in linear units, so a line can be brighter than white.
- A line's light per pass is its color times its intensity, however many points draw it. Every point carries its share of that light. This keeps the exposure the same under either sampling mode.
- `sampling` picks how a pass divides its points among the lines. `.byLength(pointsPerPass:)` gives every line points in proportion to its length times its `weight`, and never fewer than one. So a long line is drawn as densely as a short one. `.perLine(n)` gives every line the same count.
- `pointSize` is the diameter that each sample's light spreads over, in canvas points. The total light is the same at any size, so a larger size softens the grain without changing the exposure. The default of 1 is a one-pixel point, which is the cheapest to draw.
- `spray.image` is the running mean as an `Image` in linear light, for when you would rather print it yourself. `spray.setLines(_:)` swaps in a new scene and restarts the average.

The `Rendering/LineSpray` example draws a whole scene through it, with the camera, the lens, and the print settings as parameters.

<a id="bokeh"></a>
### Bokeh

`Bokeh` describes the lens as a value:

```swift
Bokeh(focalDistance: 49, strength: 0.095, minSize: 0.015, power: 1, attenuation: 0)
```

- `focalDistance` is the distance from the camera to the plane of focus, along the view axis, in world units.
- `strength` is the ball's radius per unit of defocus, so it acts as the aperture. Every sample scatters inside a ball of radius `strength × defocus^power`, where `defocus` is the sample's distance from the focal plane. A `strength` of 0 is a pinhole.
- `minSize` is the smallest ball. It gives a line that is exactly in focus some width, rather than a hairline.
- `power` is the exponent applied to the defocus before it is scaled. A `power` of 1 grows the blur in proportion to distance. A `power` of 1.5 keeps the region near focus sharper and lets far things blur faster.
- `attenuation` fades light with distance from the focal plane. Each sample is multiplied by `exp(-attenuation × defocus)`.

<a id="accumulator"></a>
### Accumulator

An `Accumulator` is a layer that keeps the running **mean** of everything drawn into it, frame after frame. The mean is what makes a picture built from faint samples converge instead of growing brighter without end. It is documented with the rest of [accumulation](./Accumulation.md#accumulator). `LineSpray` owns one as `spray.accumulator`. The [DepthOfField](../../Examples/Rendering/DepthOfField/Sketch.swift) example drives one directly.

<a id="light"></a>
### The light particle style

`drawParticles(_:style: .light)` draws a particle buffer as light rather than ink:

```swift
withAccumulator(light, passes: 4) {
    blendMode(.add)
    drawParticles(samples, style: .light)
}
```

- Coverage is the plain area ramp, so a particle deposits `color × alpha × area` wherever it lands. The deposit is exactly linear in the particle's size. It is the same whether the particle falls on a pixel's center or on its corner. The default `.marks` style instead remaps coverage to perceptual alpha. That is right for ink over a light ground, but wrong for a sum of light. In a sum of light it lifts a dot on a corner to more than twice the light of a dot on a center.
- `color` is read as linear radiance, not as an sRGB tone. If you want to write a tone in the kernel, convert it with `srgbToLinear`.
- A particle at or under one pixel takes a cheap path. Its quad is a single texel, so a million one-pixel points cost a million fragments rather than twenty-five million. The deposit is continuous across the one-pixel boundary, so a size that is animated through that boundary never steps in brightness.
- To deposit a point's whole light into its pixel, put the radiance in `color` and set `alpha = 4 / (π × size²)`. The disc's area then cancels out, and the pixel receives the radiance itself.

<a id="develop"></a>
### develop

`Filter.develop(exposure:ground:)` prints a layer of accumulated light as a picture. It scales the layer's linear values by `exposure`, then rolls them off through the Reinhard curve `x / (1 + x)`, so nothing clips. After the curve, it adds `ground` as a display color that the curve never touches. `ground` is the paper the light is printed on. The result is written as the display value itself rather than re-encoded. That is what gives a picture accumulated from faint light, such as a sandpainting, its deep midtones. `Accumulator.developed(exposure:ground:)` and `LineSpray.developed(exposure:ground:)` apply this filter to the mean.

```swift
drawImage(light.developed(exposure: 30, ground: Color(hex: 0x151010)).image, 0, 0)
```

<a id="own"></a>
### Building your own

`LineSpray` samples lines. The same pipeline runs from the compute primitives over any geometry a kernel can evaluate, such as a curve, a surface, or a point cloud. Each frame, do three things:

1. Pack the camera with `cameraParams()` and append the lens after it. Dispatch a kernel with `compute(_:buffers:count:params:)`, binding your scene buffer and a particle buffer. In the kernel, move a point into camera space with the packed `view`. Then scatter it with `ballSample(seed) × radius`, and project it with `ollin_project_eye(p.camera, eye, u.resolution)`.
2. Draw the particles with `drawParticles(buffer, style: .light)` inside `withAccumulator(acc, passes:)` under `blendMode(.add)`.
3. Print with `acc.developed(exposure:ground:)`.

The `Rendering/DepthOfField` example is exactly that pipeline, over nine closed curves. It draws each sample as three particles scattered to slightly different radii, so the bokeh gets chromatic fringes. The [compute reference](../Shaders/Compute.md#camera) covers the kernel side.

<a id="notes"></a>
### Notes

- **A camera is required.** `drawLineSpray` projects through the active `Camera3D`. Without one, it does nothing. The focal distance is measured along the view axis. So when the camera's target is what should be sharp, set `focalDistance` to the camera's `radius`.
- **Tell the accumulator how many passes.** The mean divides by the number of passes recorded. When a frame draws several passes' worth of samples, say how many, using `passesPerFrame` or `withAccumulator(_:passes:)`. Otherwise the picture reads too bright by that factor.
- **Exposure is a print setting.** It scales the mean after the mean has converged, so changing it does not restart the average. Changing the lens or the camera does.
- **A moving camera in an export.** Every frame of a turning scene restarts the average, so a plain video export is grainy. `--settle N` holds the clock and draws each written frame N times before writing it (see [Settled frames](../Output/Export.md#settled-frames)). For the ring sphere, 40 draws is 200 passes.
- **Not on the web page.** An accumulator keeps state that the recorded page cannot hold, so `--export-web` names it and stops. Export the sketch as video instead.
- **Attribution.** The technique is Anders Hoff's ([inconvergent](https://inconvergent.net/2019/depth-of-field/)). [Blurry](https://github.com/Domenicobrz/Blurry) by Domenico Bruzzese is the reference implementation. It was read for approach, and Ollin's version is written independently. See `ATTRIBUTION.md`.

---

#### <sup>[Accumulation](./Accumulation.md) · [HDR & tone-mapping](./HDR.md) · [Compute & GPU particles](../Shaders/Compute.md) · [3D](../3D/3D.md)</sup>
