#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 21</sup>

---

# 21. Pictures you solve

<!-- Hook image: the finished sketch, the lighthouse (Figures/21-PicturesYouSolve/Lighthouse.swift). Waiting on its render on the Mac. -->

Most filters look at a picture and change it. The ones in this chapter treat a layer as a problem to solve. A few colored marks spread into a smooth painting, and a pasted patch loses its seam. A drawing becomes a measure of how far every pixel sits from an edge, and a picture becomes the waves that add up to it. A scene and some lamps give back the light that reaches every pixel. Any window's average costs the same, however wide. Each makes a kind of picture no ordinary filter can. The chapter ends on a lighthouse at dusk. Its sky is diffused from a few marks, its beams are worked out by the light, and its outlines are measured.

## A picture made of a few marks: diffusion

Every filter so far took a picture and did something to it. This one makes the picture.

Draw a few marks into a layer. `.diffuse` holds each drawn pixel as a color source and lets the color out into the empty space between them until it settles:

```swift
let marks = makeRenderTarget()
withTarget(marks) {
    drawDiffusionCurve(horizon, left: Color(hex: 0xE86F4A), right: Color(hex: 0x101A2E))
    noStroke(); fill(Color(hex: 0xFFE9B0))
    drawCircle(width * 0.7, height * 0.2, 26)
}
drawImage(marks.filtered(.diffuse()).image, 0, 0)
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/21-PicturesYouSolve/Diffusion-dark.jpg">
  <img src="Images/21-PicturesYouSolve/Diffusion.jpg" alt="Three dark panels. A black field with a thin two-color curve and two dots; the same marks after diffusing into a smooth dusk sky over deep water with a glowing sun; and the same again with a second curve added low down, which reorganizes the whole lower half into a lit shore" width="680">
</picture>

The rule the solve follows matters, because everything the picture does follows from it. **Away from the marks, every pixel ends up the average of its four neighbors.** That is the rule a soap film obeys when you dip a bent wire in it. Nothing overshoots, no color appears that was not put there, and a mark's influence falls away smoothly in every direction at once.

`drawDiffusionCurve` is the form the technique is named for. It draws the same path twice, a hair apart, with a different color on each side. The field jumps across the curve and stays smooth everywhere else. Left and right are named from walking the path in the order its points come, so reversing the points swaps the colors.

Now compare it to a gradient, which is the tool you would otherwise reach for. A gradient needs a direction and two ends. This needs neither. The shape of the field is decided by where you put the marks. That is why the third panel remakes the whole lower half of the picture with one added curve. You are not filling a shape with a ramp. You are placing a few colors and letting the space between them work itself out.

Two practical notes. A pixel counts as a source when its alpha reaches `threshold`. A half-opaque mark pulls half as hard as a solid one, so a soft brush mark is a suggestion rather than a rule. And `sharpness` decides how much of the work happens at full size. Turn it down for speed while composing, up when a thin mark's color must stay crisp against it.

## Putting a piece of one picture into another

The same settling does a second job, and it belongs here because the trick behind it is the same one.

You have a patch you want to drop into a picture: a slab of texture, a cut-out, something from elsewhere. Paste it and it reads as pasted. The rim gives it away, and so does the color, because the patch was lit differently wherever it came from.

`.seamlessClone` fixes both without touching the patch's detail:

```swift
let backdrop = makeRenderTarget()
withTarget(backdrop) { drawImage(wall, 0, 0) }

let patch = makeRenderTarget()
withTarget(patch) { drawImage(stones, 240, 180) }   // transparent everywhere else

drawImage(backdrop.combined(with: patch, .seamlessClone()).image, 0, 0)
```

<img src="Images/21-PicturesYouSolve/SeamlessClone.jpg" alt="Three panels. A green slab of stones on black; the same slab pasted onto a blue-to-orange gradient with an obvious circular rim; and the same slab cloned, where the rim has vanished entirely and the stones themselves have gone blue at the top and orange at the bottom" width="680">

Where the patch layer is opaque is where it lands, so the shape you draw is the shape that gets cloned. Draw it where you want it and that is the whole positioning story.

Here is what it does, in one sentence, because everything else follows from it. **Around the rim it measures how far the patch's color sits from the backdrop's. It spreads that difference across the inside as smoothly as it can, and adds it back.** On the rim that lands exactly on the backdrop, so there is no join left to see. Inside, the patch is nudged by the gentlest correction that reaches it. The stones survive because only the slow, low part of the color is replaced.

Spreading a difference as smoothly as possible is the diffusion above, wearing a different hat. The marks are the rim, and the field between them is the correction.

Two things follow, and both are better met here than by surprise. The patch keeps its own **range of tone** and only moves where that range sits. Drop a contrasty patch somewhere much darker than itself and its shadows go below black. And the rim is where the entire answer comes from, so a rim laid across a **hard edge** drags that edge inward. Keep the rim on quiet ground and neither one comes up.

`amount` runs from 0 to 1. One is the full clone. Zero leaves the seam in, which is the picture you want beside it when you are deciding whether it worked.

## A field you measure: how far is the nearest edge

The two sections above both did the same trick from different sides. They treated the layer as something to be *solved* rather than something to be looked at. This one goes further and treats it as something to be *measured*.

Draw your marks into a layer. Then ask every pixel in it a question: how far away is the nearest edge of anything drawn, and which way is it?

```swift
let field = marks.filtered(.distanceField())
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/21-PicturesYouSolve/MeasuredField-dark.jpg">
  <img src="Images/21-PicturesYouSolve/MeasuredField.jpg" alt="Three dark panels. A circle, a square and a stroked zigzag on black; the same shapes as pale contour bands, each ring following its shape and merging with its neighbors where they meet; and the same shapes as flat color regions, each pixel wearing the color of the mark nearest to it" width="680">
</picture>

That layer is no longer a picture. Its red channel holds the distance in pixels, running negative inside a shape and positive outside it, and its green and blue hold the direction to that nearest edge. **A picture of a thing, turned into the measurement of where that thing is.**

The two answers fit together into one line worth remembering:

```
    nearest edge  =  pixel + direction * abs(distance)
```

`.fieldMap` reads the field back as something you can see, by running the distance through a color ramp over a window you give in pixels. The middle panel above is one call:

```swift
field.filtered(.fieldMap(bands, from: 0, to: 34, repeating: true))
```

`repeating` wraps the ramp instead of stretching it, so the same colors come around every 34 pixels and the marks wear contour lines like a map. Look at where two shapes meet in that panel: their rings run into each other and stop along a crease. That crease is every place equally far from both, and you did not have to work it out.

Change the window and the same call does other jobs. A ramp that turns over at one distance grows the shape by exactly that much, and shrinks it at a negative one:

```swift
field.filtered(.fieldMap(Ramp([ink, .clear]), from: 26, to: 27.5))
```

That is a dilate. Blobs that were separate merge as they grow into each other, which is how you get a soft mass out of scattered marks. A ramp that is dark in a narrow band draws an outline at any offset you like, inside or outside.

The third panel is the direction channel doing its work. Each pixel walks to its nearest edge, steps a little past it, and brings back the color it finds:

```metal
float4 shade(float2 uv, ShaderInfo info) {
    float4 field = sampleRaw(info, uv);
    float2 here = uv * info.resolution;
    float2 inside = here + field.gb * (abs(field.r) + 4.0 * sign(field.r));
    return sampleAux(info, inside / info.resolution);
}
```

Every pixel ends up wearing the color of whichever mark is nearest to it. That is a Voronoi diagram, built out of the shapes themselves rather than out of a list of points, and it costs one lookup per pixel. Run it with `field.combined(with: marks, .shader(...))`.

Note `sampleRaw` rather than `sample`, the read the shaders in [Chapter 18](18-YourFirstShader.md) make. The ordinary read hands a layer over as a color, and a distance in pixels is not one. `sampleRaw` gives you the stored numbers untouched.

One practical note. Measuring the whole canvas costs a few milliseconds, because the measurement works outward in steps and needs one step per doubling of the distance it carries. When you only care about a band near the marks, say so and it gets shorter:

```swift
marks.filtered(.distanceField(maxDistance: 64))
```

Past that distance the field reads flat, with a zero direction, which is its way of saying nothing is within reach.

## A picture read as waves

There is one more way to stop treating a layer as a picture, and it is the oldest. A grid of
pixels is one reading of a drawing. A **sum of waves** is another, and the two hold exactly
the same information. The Fourier transform is how you get from one to the other, and it
runs on the GPU:

```swift
let spectrum = plate.filtered(.fourier())
```

<img src="Images/21-PicturesYouSolve/FrequencyDomain.jpg" alt="Three panels. A dark plate with a pale circle, a blue square, a red triangle and a row of fine white stripes; the same plate as a spectrum, a bright center with a star of lines radiating from it and a grid of faint dots; and the plate blurred smooth, its stripes gone to a flat gray band and rings of ripple around every shape" width="680">

The middle panel is that spectrum. It is not a picture of the drawing, it is a map of the
drawing's *scales*: slow, wide gradients near the middle, fine detail out at the edges. The
star through it is the shapes' straight edges, and the grid of dots is the row of stripes,
which is one wavelength and so lands in one place.

Why make the trip? Because filtering by scale, which is awkward on the pixel side, is a
multiplication on this side. Draw a shape over the spectrum and you have a filter:

```swift
let soft = plate.filtered(.fourier())
    .combined(with: mask, .mask())     // white circle in the middle of a black layer
    .filtered(.inverseFourier())
```

Keep the middle and the fine detail is gone: that is the third panel, and the stripes have
become one flat band. Invert the mask and the opposite happens, leaving the edges and
nothing else. A ring keeps one band of scales and drops both the coarse and the fine, which
no ordinary blur can do at all.

Three things to know before you reach for it. The layer has to be square with a side that is
a power of two (`makeRenderTarget(width: 512, height: 512)`), because the transform works by
halving. It reads one channel, the brightness unless you name another, so what comes back is
gray. And a hard-edged mask *rings*: look at the ripples around every shape in the third
panel, which are the price of cutting a band off sharply, and soften the mask's own edge to
soften them.

It also runs the other way on its own. Write a spectrum, transform it, and a field comes out
that nobody drew. That sounds like a curiosity until you learn that the physics of a sea is
written as a spectrum, which is exactly how [Chapter 27](27-Landscapes.md) makes an ocean.
The [reference](../Docs/Drawing/Fourier.md) has the cost and the rest of the rules.

## Light that works itself out

The measured field above is the hard half of a much bigger trick, and the trick is one to have on its own. Draw a scene into one layer and some lamps into another, and ask what light reaches every pixel.

```swift
let lit = scene.combined(with: lamps, .light())
drawImage(lit.image, 0, 0)
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/21-PicturesYouSolve/LightField-dark.jpg">
  <img src="Images/21-PicturesYouSolve/LightField.jpg" alt="Three dark panels. A room drawn flat: walls, a comb of four teeth, a red bar, a yellow disc and a small white dot. The same room as light, with the dot lit and four beams thrown between the teeth into soft shadows. The same again, with the red bar, the yellow disc and the green wall now glowing in their own colors" width="680">
</picture>

The base layer is **the scene**: whatever you draw there is solid, and its alpha is how much of a ray it stops. The aux layer is **the lamps**: whatever you draw there gives light off, in its own color. What comes back is the light itself, which is why you draw it as the frame instead of over the scene.

Look at what nobody drew. The comb throws four beams, and they fan out. Each shadow is hard where it meets the tooth that casts it, and soft further down. A pixel further down can see more of the lamp. The light thins out with distance, and it thins out at the rate a real one does. In the third panel the red bar reddens the floor beside it and the green wall greens its own corner of the room. Those are all one measurement rather than five effects that have to be kept in step by hand.

The parameter for that third panel is `bounces`:

```swift
scene.combined(with: lamps, .light(brightness: 5, bounces: 1))
```

At `0` every surface stays black and only the lamps are seen. That is the middle panel, and a good look in its own right. At `1`, the default, light comes back off whatever it lands on, carrying that surface's color with it. Each further bounce costs another pass, and past one or two you will not see the difference.

Two more parameters matter early. `sky` is the light arriving from beyond the reach of the field. A color there turns a dark room into a lit one with a window in it. `reach` is how far light travels in pixels, which is both an answer ("this is a small room") and the speed parameter.

Speed is the thing to say plainly. This is the most expensive effect in the chapter. It is also the one whose cost does *not* follow how much you drew. One lamp and two hundred cost the same, and so do ten shapes and ten thousand. What costs is the size of the layer and how far light may travel. If a sketch needs its frame rate back, draw the light into a half-size layer first (`makeRenderTarget(scale: 0.5)`), or pass `quality: .performance`.

Underneath, the answer is a ladder of light fields. Each one holds a single ring of distance around every point it samples. Close in there are many places and few directions; further out there are few places and many directions, over a span four times as long. That trade is exactly why one lamp on the far side of the room costs no more than one beside you. The rays are marched against the measured field from the section above, which is why an empty room is crossed in a single step.

## Averages of a neighborhood, at a flat price

The [distance field](#a-field-you-measure-how-far-is-the-nearest-edge) asked every pixel how far away something was. Here is a different question, and a cheaper answer than you would expect. **What does the neighborhood around this pixel look like?**

The obvious way to answer costs more the wider you look. A 5-pixel square is 25 reads, a 500-pixel square is 250,000, and a blur that reaches across the canvas is out of the question. There is another way, and it turns the cost into a flat fee.

Build one table first. Every texel in it holds the sum of everything above and to the left of it. Then the sum over *any* rectangle is a bit of arithmetic on four corners of that table:

```
      A ─────────── B          the shaded box
      │             │            =  D − B − C + A
      │      ┌──────┤
      │      │//////│          four lookups, wherever the box is
      C ─────┼──────D          and however big it is
             │//////│
```

That table is a **summed-area table**, and once you have one, two useful filters cost almost nothing.

The first is a blur:

```swift
layer.filtered(.boxBlur(radius: 4))     // these two
layer.filtered(.boxBlur(radius: 400))   // cost the same
```

It is the plainest blur there is, just the average of the square around each pixel, and it is not as good-looking as `gaussianBlur`. Reach for it when the reach is large. Reach for it too when the radius changes while the sketch runs, and you do not want the frame rate changing with it. Three of them in a row look near enough Gaussian that you will stop being able to tell, and that is still three fixed-price passes.

The second one is the interesting one.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/21-PicturesYouSolve/LocalAverages-dark.jpg">
  <img src="Images/21-PicturesYouSolve/LocalAverages.jpg" alt="Three panels. A page of dark bars and dots on pale paper with a light falling across it, bright at the top left and deep in shadow at the bottom right; the same page cut to black and white by one threshold, which swallows the whole shadowed half into solid black; and the same page cut against each pixel's own neighborhood, where every bar and dot survives on clean white paper" width="680">
</picture>

The left panel is a page with a light falling across it. Try to cut it to black and white with `threshold` and you have to pick one number, and there is no number that works. Pick one that keeps the shadowed corner and you flood the lit one. Pick one that keeps the lit corner and the shadow goes solid black, which is the middle panel.

`adaptiveThreshold` compares each pixel with the average of its own surroundings instead:

```swift
page.filtered(.adaptiveThreshold())
```

That is the right panel. Every mark survives, in shadow and in light alike. **Hard contrast is local, and uneven light is not, so comparing locally keeps the first and throws away the second.**

The parameter that matters is `window`, how wide that neighborhood is in pixels. It wants to be big enough to hold both ink and paper. Set it smaller than your marks and the middle of a thick stroke sees nothing but more stroke. It decides that must be what paper looks like here, and comes out hollow. Since widening it is free, err wide. Left alone it is an eighth of the layer.

There is one more parameter, `bias`, which is how far below the local average a pixel has to fall before it goes dark. It is a *fraction* rather than a fixed amount, and that is not fussiness. Light falling on a page multiplies what comes back off it. Only a test that scales along with the average is unmoved when somebody turns the lamp down.

Two costs, and neither one grows with the window. Building the table is about twenty passes over the layer, a few milliseconds for a full canvas. One of these in a frame is comfortable. A dozen are not. And the running totals get large, which eats into a float's precision and leaves a small error behind. That error is a fixed amount divided by the size of your window, so it fades away as the window grows. It only shows up at tiny radii, which is where you would reach for a Gaussian anyway.

## Putting it together: the lighthouse

The lighthouse is a harbor at dusk, and very little of it is painted. A handful of marks diffuse into the whole sky and sea. Two lamps and a scene give back the light, with its beams and soft shadows worked out by `.light`. And every silhouette wears an outline read off its measured distance field. Make `MySketches/Lighthouse.swift`:

```swift
import Ollin

final class Lighthouse: Sketch {
    let night = Color(hex: 0x2A2350)
    let dusk = Color(hex: 0xE86F4A)
    let sea = Color(hex: 0x16233F)
    let deep = Color(hex: 0x080D1A)
    let sun = Color(hex: 0xFFE9B0)
    let land = Color(hex: 0x0A0D16)
    let rim = Color(hex: 0xF2C879)

    let lantern = Vector2(235, 272)

    override func draw() {
        let boat = Vector2(800, 700 + sin(time * 0.9) * 5)

        // The marks: a horizon warm above and deep below, a band of night at the
        // top, a low sun, and its path on the water. Diffusion fills in the rest.
        let marks = makeRenderTarget()
        withTarget(marks) {
            background(.clear)
            let horizon = stride(from: -20.0, through: width + 20, by: 12).map { x in
                Vector2(x, 640 + sin(x / width * 5 + time * 0.4) * 8)
            }
            drawDiffusionCurve(horizon, left: dusk, right: sea, width: 4)
            noStroke()
            fill(night)
            drawRect(0, 0, width, 24)
            fill(deep)
            drawRect(0, height - 24, width, 24)
            fill(sun)
            drawCircle(620, 606, 30)
            fill(dusk)
            drawRect(575, 690, 90, 4)
        }

        // The scene: everything the light meets. The shutter around the lamp
        // turns, and the gaps between its blades cut the light into beams.
        let scene = makeRenderTarget()
        withTarget(scene) {
            noStroke()
            fill(land)
            drawPolygon([Vector2(0, 1080), Vector2(0, 560), Vector2(90, 530),
                         Vector2(180, 486), Vector2(280, 482), Vector2(340, 540),
                         Vector2(390, 650), Vector2(440, 800), Vector2(500, 1080)])
            drawPolygon([Vector2(214, 490), Vector2(256, 490),
                         Vector2(249, 300), Vector2(221, 300)])
            for blade in 0 ..< 8 {
                let angle = time * 0.5 + Double(blade) * .tau / 8
                withState(at: lantern + Vector2(cos(angle), sin(angle)) * 30, rotation: angle) {
                    drawRect(center: .zero, width: 8, height: 13)
                }
            }
            drawPolygon([boat + Vector2(-65, -10), boat + Vector2(65, -10),
                         boat + Vector2(48, 12), boat + Vector2(-50, 12)])
            drawRect(boat.x - 2, boat.y - 104, 4, 96)
        }

        // The lamps: the lighthouse lamp, and a small one at the masthead.
        let lamps = makeRenderTarget()
        withTarget(lamps) {
            noStroke()
            fill(Color(hex: 0xFFF1C8))
            drawCircle(lantern.x, lantern.y, 12)
            fill(Color(hex: 0xFF7A50))
            drawCircle(boat.x, boat.y - 110, 6)
        }

        // The sky, then the silhouettes, then the light laid over both.
        drawImage(marks.filtered(.diffuse()).image, 0, 0)
        drawImage(scene.image, 0, 0)
        blendMode(.add)
        drawImage(scene.combined(with: lamps, .light(brightness: 6)).image, 0, 0)
        blendMode(.normal)

        // An outline a few pixels out from every silhouette, read off the field.
        let field = scene.filtered(.distanceField(maxDistance: 32))
        let band = Ramp([rim.withAlpha(0), rim, rim.withAlpha(0)])
        drawImage(field.filtered(.fieldMap(band, from: 1, to: 5)).image, 0, 0)
    }
}
```

The sketch builds three layers each frame and reads the picture out of them. `marks` holds the diffusion's sources. The horizon is a curve with dusk above and sea below. A band of night runs along the top, and deep water along the bottom. The sun and its path on the water are marks too. `.diffuse()` settles everything between them. The horizon's wave is part of the curve, so the sky and the sea swell with it.

`scene` does two jobs. `.light` reads it as the solid things that stop a ray, and `.distanceField` reads the same layer as shapes to measure. `lamps` holds the two lights. What `.light` hands back is the light alone, so the sketch draws the sky and the silhouettes first and adds the light over them under `.add`. Adding black changes nothing, so wherever no lamp reaches, the sky shows through untouched.

The beams come from the shutter. Its eight blades turn with `time`, and the gaps between them let the lamp's light out in spokes. Nothing in the sketch draws a beam. It is the comb from the room above, bent into a ring.

The outline is a `fieldMap` whose ramp runs from clear to gold and back to clear, over a window from 1 to 5 pixels. That lights a thin band just outside every silhouette, the mast and the shutter blades included. The field is measured again every frame, so the band follows the boat as it rides the swell.

Then make it yours:

- Put the sun on the pointer. Its disc is a mark like any other, so `drawCircle(mouseX, mouseY, 30)` in its place re-solves the whole sky around wherever you point.
- Chart the water. Measure a second field out to a `maxDistance` of 120, and map it with `repeating: true` over a window of about 18 pixels. It rings the boat and the headland like ripples on a map.
- Give the land a color. Fill it a dark green instead of near-black, and with the default single bounce the light that lands on the headland comes back green.

This one is about motion, since the beams sweep and the boat rides the swell, so keep it as a movie. `swift run OllinLive MySketches/Lighthouse.swift --export-video lighthouse.mp4 --seconds 16` writes sixteen seconds of it. An export measures the light at its finest quality, so the file takes longer to write than the window takes to draw.

## Where this comes from

Each of these solves a problem somebody published. Diffusion curves are Alexandrina Orzan, Adrien Bousseau, Holger Winnemöller, Pascal Barla, Joëlle Thollot, and David Salesin's, from 2008. Pasting without a seam is Patrick Pérez, Michel Gangnet, and Andrew Blake's Poisson image editing, from 2003. The measured field floods the layer by Guodong Rong and Tiow-Seng Tan's jump flooding, from 2006. The waves come from James W. Cooley and John W. Tukey's fast Fourier transform, from 1965. The light rebuilds Alexander Sannikov's radiance cascades, from 2024. And the local averages stand on Franklin C. Crow's summed-area table, from 1984.

The seamless paste settles its correction with the convolution pyramids of Zeev Farbman, Raanan Fattal, and Dani Lischinski, from 2011. The local cut that keeps every mark on the shadowed page is Derek Bradley and Gerhard Roth's adaptive threshold, from 2007. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Diffusion](../Docs/Drawing/Effects.md#generate) and the [seamless paste](../Docs/Drawing/Effects.md#combined): `.diffuse` and `drawDiffusionCurve` with their parameters, and what `.seamlessClone` keeps and where its rim should sit.
- [Measured distance fields](../Docs/Drawing/DistanceFields.md): what the field holds, reading it back, and the jump flood underneath it.
- [The frequency domain](../Docs/Drawing/Fourier.md): the transform both ways, filtering by scale, building a field from its spectrum, and what the ladder costs.
- [Light in a flat sketch](../Docs/Drawing/Light.md): the two layers, every parameter, what it costs at each quality tier, what it will not do, and the ladder underneath it.
- [Local averages](../Docs/Drawing/LocalAverages.md): the box blur, the adaptive threshold, choosing the window, and what the summed-area table costs.
- Worked examples: [`Examples/Effects/DiffusionCurves`](../Examples/Effects/DiffusionCurves/Sketch.swift), [`Examples/Effects/SeamlessClone`](../Examples/Effects/SeamlessClone/Sketch.swift), [`Examples/Effects/DistanceField`](../Examples/Effects/DistanceField/Sketch.swift), [`Examples/Effects/Fourier`](../Examples/Effects/Fourier/Sketch.swift), [`Examples/Effects/Light`](../Examples/Effects/Light/Sketch.swift), and [`Examples/Effects/SummedArea`](../Examples/Effects/SummedArea/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 20, Pictures restyled](20-PicturesRestyled.md) · Next: [Chapter 22, Iterated forms](22-IteratedForms.md)
