#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Effects`</sup>

---

## Layered effects

Draw into **off-screen layers**, run GPU **filters** over them (blur, bloom), and **composite** the results back onto the canvas with blend modes. It's how you build glow, soft backdrops, depth-of-field haze, and post-processing looks, following the OPENRNDR `compose`/`Filter` model on Ollin's Metal core.

Everything stays on the GPU. A layer is a Metal texture you draw into and then sample, a filter reads one texture and writes another, and compositing is an ordinary [`drawImage`](../Drawing/Images.md) with a [`blendMode`](../Drawing/Drawing.md#blendMode). Nothing is ever read back to the CPU between steps, so the slow path other tools fall into (copying a layer back to combine it) never happens here.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/16-LayersAndEffects/Layers-dark.jpg">
  <img src="../../Guide/Images/16-LayersAndEffects/Layers.jpg" alt="A diagram of the layer graph: two source drawings, arrows into a blurred version and a bloomed version, then arrows into one composited panel" width="680">
</picture>

```swift
override func draw() {
    background(.black)

    let layer = renderTarget()                 // a full-canvas off-screen layer
    withTarget(layer) {                         // …draw into it, scoped like withState
        background(.clear)
        fill(.orange); noStroke()
        drawCircle(width / 2, height / 2, 200)
    }

    blendMode(.add)                             // add the glow as light
    drawImage(layer.filtered(.bloom(intensity: 1.6)).image, 0, 0)
}
```

### Contents

- [renderTarget](#rendertarget) - make an off-screen layer
- [withTarget](#withtarget) - draw into a layer
- [RenderTarget.image](#image) - composite a layer back
- [filtered](#filtered) - run a filter over a layer
- [Filter](#filter) - the filter catalog (blur, bloom, color, stylize)
- [combined / Combine](#combined) - combine two layers (mask, displace, disperse, mix, seamless clone, defocus, ambient occlusion, screen-space reflections)
- [depth](#depth) - a 3D scene's depth buffer as a layer (feed `.defocus` / `.ambientOcclusion` / `.screenSpaceReflections`)
- [generate / Generator](#generate) - procedural pattern sources
- [postProcess](#postprocess) - filter the whole frame
- [feedback / withFeedback](#feedback) - a layer that remembers itself (trails, tunnels)
- [simField / Sim](#simfield) - a layer that runs a simulation (reaction-diffusion, Game of Life, fluid)
- [compose / layer](#compose) - declare a stack of layers as one block
- [aside](#aside) - a helper layer that feeds another layer's effect
- [Notes](#notes)

<a id="rendertarget"></a>
### renderTarget(scale:)

Make an off-screen layer to draw into. The no-argument form is full-canvas size, and `scale` renders the layer at a fraction of that resolution.

```swift
let layer = renderTarget()              // full canvas
let haze  = renderTarget(scale: 0.5)    // half-resolution, for a layer you'll blur
```

Effects are **fill-rate bound** (cost tracks pixels × passes), so a layer you're going to blur or glow rarely needs full detail. Drop `scale` and it upsamples when you draw it back. There's also an explicit-size form for a layer that isn't full-canvas:

```swift
let badge = renderTarget(width: 256, height: 256)
```

Make a target inside `draw()`. It's a per-frame handle, and the GPU texture behind it is pooled and reused across frames for you, so creating one each frame doesn't allocate.

<a id="withtarget"></a>
### withTarget(_:_:)

Redirect everything drawn in the closure into `target` instead of the canvas. Scoped exactly like [`withState { }`](../Drawing/Drawing.md#isolated), so the current drawing state and transform carry in, and drawing returns to the canvas when it ends.

```swift
let layer = renderTarget()
withTarget(layer) {
    background(.clear)                  // clear THIS layer (transparent here)
    fill(.white); noStroke()
    drawCircle(width / 2, height / 2, 120)
}
// back to drawing on the canvas
```

Call [`background(_:)`](../Drawing/Drawing.md#background) inside the block to clear the layer. Inside a `withTarget` it clears *that layer* (its fill color and its geometry so far), leaving the canvas untouched. A layer starts transparent, so an unwritten or partly written layer composites as nothing where you didn't draw.

<a id="image"></a>
### RenderTarget.image

A layer as a drawable [`Image`](../Drawing/Images.md), so you composite it with the ordinary `drawImage`, riding the transform stack, `tint`, and `blendMode` like any image:

```swift
drawImage(layer.image, 0, 0)                       // at the top-left, native size
drawImage(layer.image, 0, 0, width, height)        // scaled to fill
blendMode(.add); drawImage(layer.image, 0, 0)      // added as light
```

The image always reflects what was drawn into the layer *this* frame.

<a id="filtered"></a>
### filtered(_:)

Run a [`Filter`](#filter) over a layer and get back a new layer, itself drawable and itself filterable, so effects chain:

```swift
let blurred = layer.filtered(.gaussianBlur(radius: 20))
let glowed  = layer.filtered(.bloom()).filtered(.gaussianBlur(radius: 4))
drawImage(blurred.image, 0, 0)
```

The work runs on the GPU during the frame's render, and `filtered` just records it.

<a id="filter"></a>
### Filter

Filters are value descriptors built with static factories. They composite in
[linear light](../Drawing/HDR.md), so grades and blends are physically correct. Each family
has a contact-sheet example: `Effects/ColorFilters`, `Effects/BlurFilters`,
`Effects/StylizeFilters`, `Effects/RetroFilters`, and `Effects/Distortion`
(`Effects/Glitter` shows the iridescence + glitter pair on shapes). The catalog:

<img src="../../Guide/Images/16-LayersAndEffects/FilterSheet.jpg" alt="A twelve-tile contact sheet: one sunset landscape shown plain and through gaussianBlur, bloom, posterize, duotone, halftone, pixelate, edges, oilPaint, glitch, swirl, and crosshatch filters" width="560">

#### Blur & glow

- **`.gaussianBlur(radius:)`** a Gaussian blur, where `radius` is the extent in pixels (larger is softer). Backed by a hardware Gaussian kernel.
- **`.bloom(threshold:intensity:radius:)`** glow: pixels brighter than `threshold` bleed light into their surroundings. The bright parts are extracted, blurred by `radius`, and added back at `intensity`, so the result is the original **plus** its glow, ready to composite (often additively). Brightness is the **max color channel** (HSV "value"), not luminance, so a vivid full-brightness mark blooms the same whatever its hue. `threshold` runs `0…1` over the linear-light frame, so HDR highlights (values above 1, from additive light) bloom hardest.
- **`.bilateral(radius:sigma:)`** edge-preserving smoothing that blurs flat areas while keeping edges sharp (the cartoon or denoise base). `sigma` is how different a neighbor's color may be before it stops blending, so smaller keeps more edges.
- **`.motionBlur(angle:distance:)`** directional smear along `angle`, `distance` a fraction of the layer, the streak of a moving subject.
- **`.radialBlur(amount:)`** zoom blur smearing outward from the center, `amount` a fraction of the layer.

```swift
layer.filtered(.gaussianBlur(radius: 24))
layer.filtered(.bloom(threshold: 0.6, intensity: 1.4, radius: 24))
layer.filtered(.bilateral(radius: 6, sigma: 0.18))
```

#### Color & tone

- **`.colorGrade(brightness:contrast:saturation:hue:)`** the workhorse grade: an additive `brightness`, `contrast` pivoting on mid-gray, `saturation` (0 = gray, >1 = punchier), and a `hue` rotation in **turns** (0…1 wraps the wheel). All default to no-op, so pass only what you want.
- **`.invert(amount:)`** toward the photographic negative (`amount` 1 = full).
- **`.posterize(levels:)`** quantize each channel to flat steps, a screen-printed banding.
- **`.threshold(_:softness:)`** two tones at a brightness cut, `softness` widening the edge.
- **`.sepia(amount:)`** a warm monochrome tone, blended by `amount`.
- **`.duotone(dark:light:amount:)`** map luminance between two colors (shadows → `dark`, highlights → `light`).
- **`.gradientMap(_:amount:)`** read luminance and look its color up along a [`Ramp`](../Drawing/Color.md) or [`Colormap`](../Drawing/Color.md) (viridis, magma, turbo, …). A fast recolor of a grayscale field or a whole scene.
- **`.exposure(stops:)`** scale the light in linear-light stops (+1 doubles, −1 halves).
- **`.levels(blackPoint:whitePoint:gamma:)`** the photo-tool staple: pull `blackPoint` to black and `whitePoint` to white, then bend the midtones by `gamma` (>1 darkens).
- **`.solarize(_:softness:)`** invert the tones above a brightness with a soft fold, the part-positive, part-negative darkroom (Sabattier) look.
- **`.temperature(amount:tint:)`** white balance: `amount` warms (>0) or cools (<0), `tint` pushes toward magenta (>0) or green (<0).
- **`.vibrance(amount:)`** smart saturation that lifts the muted colors most and the vivid ones least (so it punches a flat image without blowing already-saturated tones).
- **`.colorama(cycles:shift:)`** cycle the hue wheel `cycles` times across luminance, turning a gradient into rainbow bands, and `shift` spins the wheel.
- **`.lumaKey(low:high:invert:)`** make the image transparent outside a brightness band, so a dark or light backdrop drops out, a luminance key.

```swift
layer.filtered(.colorGrade(contrast: 1.3, saturation: 1.6, hue: 0.05))
layer.filtered(.gradientMap(.turbo))
layer.filtered(.levels(blackPoint: 0.08, whitePoint: 0.92, gamma: 1.4))
layer.filtered(.vibrance(amount: 0.6))
```

#### Stylize & optical

- **`.edges(intensity:)`** Sobel edge magnitude, bright edges on black, a quick ink or outline pass.
- **`.sharpen(amount:)`** unsharp mask, emphasizing local detail.
- **`.vignette(amount:radius:softness:)`** darken toward the corners (aspect-correct, so circular).
- **`.chromaticAberration(amount:mode:spectral:quality:)`** pull the color channels apart, the way cheap glass, a misprinted plate, or a lens wide open does. `amount` is the split in fractions of the canvas, and `mode` picks which picture you get, since the members of the family look genuinely unlike each other rather than like one look at different strengths:

  - **`.magnify`** (the default) scales each channel about the center: nothing splits in the middle, the split grows straight with the distance out, and straight lines stay straight. The physically honest form of lateral color.
  - **`.lens(radius:falloff:)`** shapes that growth. `radius` (0…1 of the half-diagonal) is where the fringe starts to show at all, and `falloff` is the exponent it grows by past there (about 2 reads like glass). `.lens(radius: 0, falloff: 1)` is `.magnify` again.
  - **`.offset(angle:)`** moves every pixel by the same vector, so the middle splits as much as the corner. Misregistration rather than optics: a plate printed a hair off, an anaglyph, a scan that slipped.
  - **`.edges`** fringes only where there is an edge, sliding along the local brightness gradient and scaling by how strong it is, so flat regions keep their exact color. A positive `amount` leaves a warm halo on the bright side of every edge and a negative one leaves the cool, purple-fringing kind.
  - **`.axial`** is longitudinal color: the channels differ in *focus* rather than in position, so one end of the spectrum is sharp while the other softens. A positive `amount` keeps red sharp and a negative one keeps blue sharp, which is what turns an out-of-focus highlight green on one side of focus and magenta on the other. Most of the fast-lens-wide-open look, and it pairs with [`.defocus`](#combined) rather than replacing it.

  `spectral: true` takes the split over a whole set of wavelength taps rather than three, turning three hard ghosts into a continuous rainbow smear, and `quality` sets how many taps (7 / 15 / 31). It is the single largest jump in quality here, and it is off by default because three taps are the cheap glitch look people often want. Every mode hands the layer back untouched at `amount: 0`, so an A/B costs nothing. Each tap is unpremultiplied before its channel is read, so a layer with soft edges of its own keeps them instead of growing a dark rim, and past the frame edge the sampler clamps. See `Examples/Effects/Dispersion`, and [`.disperse`](#combined) to drive the amount from a second layer.
- **`.halftone(scale:angle:)`** a rotated dot screen, dot size tracking brightness.
- **`.dither(levels:)`** ordered (Bayer 4×4) dithering, the retro look that fakes more shades than it has.
- **`.dither(dark:light:bias:pixelSize:)`** the two-tone variant: the same ordered pattern mapped onto exactly two chosen colors, cut by tone, the 1-bit / newsprint look in any palette. `bias` shifts the cut (positive lightens), and either color may be transparent so the shadows drop out.
- **`.grain(amount:seed:)`** film grain, so feed `seed` your `time` or `frameCount` for grain that moves.
- **`.pixelate(size:channel:tint:)`** mosaic into blocks `size` canvas-pixels across, where `channel` can read one channel out as gray and `tint` recolor it.
- **`.lineScreen(scale:softness:angle:foreground:background:)`** a brightness-driven line screen: each cell paints a centered bar whose width tracks its brightness, painted `foreground` over `background`.
- **`.emboss(amount:angle:)`** light the luminance slope along `angle` as a gray relief, like stamped metal.
- **`.oilPaint(radius:)`** the Kuwahara region filter: flatten detail into oil-paint patches while keeping edges crisp. `radius` is the brush size in pixels (bigger is broader and costlier).
- **`.crosshatch(scale:foreground:background:)`** pencil shading: layered diagonal strokes that thicken as the image darkens.
- **`.toon(levels:edges:)`** cel shading: flatten into `levels` brightness bands and ink the Sobel edges over them.
- **`.median()`** a 3×3 median, knocking out speckle and stray pixels while keeping edges sharp.
- **`.contour(levels:intensity:)`** dark iso-brightness lines (one every `1/levels` of the range), turning tone into a topographic map.
- **`.cmykHalftone(scale:)`** separate into cyan/magenta/yellow/black and screen each as rotated dots at the classic print angles, the color-process look.
- **`.normalMap(strength:)`** read the image as a height field and output its surface normal as an RGB vector (the bluish bump-map look), ready to feed `.displace` (see [combine](#combined)) or a lighting pass.
- **`.relight(_:angle:elevation:height:intensity:color:)`** read the layer as a height map (bright = raised) and light it as embossed physical matter with a curated finish: `.matte` clay, `.metal`, wet `.glass`, grainy `.sand`, or `.liquid` (the last two refract the image beneath). `angle` sets where the light comes from, `elevation` how low it rakes (grazing light deepens relief), `height` exaggerates the slopes, and `color` overrides the material color (by default the layer keeps its own). It's the cheap 2D cousin of the 3D materials, so a noise field or a simulation instantly reads as terrain, hammered gold, or wet skin. See `Examples/Effects/Relight`.

  The relief it lights is the layer's broad shape, not its finest pixels. Slope weights a wavelength by 1/L, so detail a few pixels across would otherwise tilt the surface as steeply as the shape the layer is actually made of, and a razor highlight would scatter that into speckle. The slope is measured over a small span instead of a single pixel, which rolls off anything under about six pixels while leaving broader relief untouched, and the span grows with resolution so a sketch relit at 4K keeps the same surface character it had at 1080. Feed it something smooth; a heavily dithered or noisy layer has little broad relief to light.
- **`.iridescence(amount:scale:bands:shift:)`** wash the content with the flowing rainbow sheen of a soap film or oil slick. The colors come from thin-film interference (each channel cycling at its own wavelength, so the bands run through the film color order), swirled across the content by a noise field and following its shading. `amount` blends the sheen over the original, `scale` sets how fine the swirl is, `bands` how many color cycles the film runs through, and `shift` slides the colors, so feed it your `time` for a sheen that flows.
- **`.glitter(density:amount:size:saturation:phase:)`** scatter twinkling sparkle flecks across the content: a dense dust of small glints plus occasional bright cross-flare flashes, landing only where something is drawn. `density` is the fleck grid resolution (cells across the layer), `amount` the brightness (flashes run past 1.0 in linear light, so a following `.bloom` makes them glow), `size` scales the flecks, `saturation` tints them from white (0) toward each fleck's own color (1), and `phase` drives the twinkle, so feed it your `time` and it sparkles.
- **`.thinFilm(amount:thickness:variation:ior:scale:shift:quality:)`** wash the content with a *measured* interference film: where `.iridescence` styles the rainbow, this one works the real physics out per wavelength (a `quality`-sized set of spectral taps), so the colors arrive in the true film color order. `thickness` is the film's mean depth in nanometers (about 100 is near-clear, 300 to 600 the strong colors, toward 1500 the crowded pastel a bubble shows just before it pops), `variation` how many nanometers the swirl adds and removes, `ior` the film's refractive index (1.35 soap, 1.45 oil), `scale` the swirl frequency, and `shift` slides the swirl, so feed it your `time` for a draining film. See [Spectral color](Spectrum.md) and the `Effects/SoapFilm` example.
- **`.diffraction(amount:angle:orders:falloff:quality:)`** streak bright content into rainbow-split grating orders along `angle`: each side of the image repeats `orders` times, every repeat offset in proportion to wavelength (the grating equation, so red always reaches farther than blue), while the image itself stays put. `amount` is the first order's reach (a fraction of the layer), `falloff` how much dimmer each further order is, and `quality` the wavelength tap count. Bright-on-dark content plus a following `.bloom` gives the full groove-pattern sparkle. See [Spectral color](Spectrum.md) and the `Effects/SoapFilm` example.

```swift
layer.filtered(.halftone(scale: 48))
layer.filtered(.oilPaint(radius: 5))
layer.filtered(.toon(levels: 5))
layer.filtered(.lineScreen(scale: 60, angle: .pi / 6))
layer.filtered(.iridescence(amount: 0.85, shift: time * 0.2))
layer.filtered(.glitter(phase: time * 2)).filtered(.bloom(threshold: 0.8))
```

#### Retro / optical

- **`.scanlines(count:intensity:)`** darken alternating horizontal lines, the CRT look. `count` is how many lines span the height.
- **`.glitch(amount:seed:)`** tear random blocks of rows sideways and split their channels, and feed `seed` your `time`/`frameCount` so it flickers.
- **`.crt(curvature:scanline:aberration:)`** the full old-monitor look in one pass: barrel curvature, scanlines, a corner vignette, and a touch of aberration.

```swift
layer.filtered(.scanlines(count: 240))
layer.filtered(.crt())
postProcess(.glitch(amount: 0.3, seed: time * 8))
```

#### Distortion

These warp the image's *coordinates*, re-sampling the source at a remapped position, so color passes through untouched. Center-relative warps stay round on a non-square layer.

- **`.kaleidoscope(segments:angle:)`** fold into mirrored wedges around the center, rotated by `angle`.
- **`.swirl(angle:radius:center:)`** twirl into a vortex: rotation strongest at `center`, fading to none at `radius`.
- **`.bulge(amount:radius:center:)`** a radial lens where `amount` > 0 bulges (fisheye) and < 0 pinches, easing back to the image at `radius`.
- **`.ripple(amplitude:frequency:phase:center:)`** concentric waves spreading from `center`, like a drop in water.
- **`.wave(amplitude:frequency:phase:vertical:)`** ripple rows side to side (or columns up and down), and animate `phase` for motion.

The three radial warps take an optional `center` in fractions of the layer (top-left origin; the middle by default), so a cursor-driven lens or vortex is one line: `.bulge(amount: 1, center: Vector2(mouseX / width, mouseY / height))`.
- **`.mirror(vertical:flip:)`** reflect one half of the image onto the other.
- **`.polar(amount:)`** bend around the center by remapping between Cartesian and polar coordinates, a tunnel or fold.
- **`.tile(count:mirror:)`** repeat the image in a `count`×`count` grid, and `mirror` flips alternate cells for a seamless tiling.
- **`.perturb(amount:scale:phase:)`** warp by the image's own internal fbm noise (no map needed), for a smoky / heat-haze ripple.
- **`.droste(inner:twist:zoom:center:rotation:)`** the picture inside itself, without end. The ring between `inner` and the layer's edge repeats at every scale, so a smaller copy of the picture sits in the middle of it, with a smaller copy inside that one. `inner` is the radius of the hole, which is also how much smaller each copy is. `twist` is how many copies one turn around the middle steps down: `0` leaves plain concentric rings, `1` winds them into the single spiral of the Escher construction, and a negative value winds it the other way. `zoom` slides the picture into itself in copies, so `zoom: time * 0.2` is an endless fall that loops exactly every five seconds. The join between one copy and the next shows unless the picture is made for it: keep the content clear of both edges of the ring, or let the ring end on flat color at each end.

```swift
layer.filtered(.kaleidoscope(segments: 8))
layer.filtered(.swirl(angle: 3, radius: 0.6))
layer.filtered(.droste(inner: 0.4, twist: 1, zoom: time * 0.2))
postProcess(.ripple(amplitude: 0.02, frequency: 12, phase: time * 3))
```

#### Design

The image-filter siblings of the [design-pattern generators](#generate), with the
same conventions: animation is an explicit `phase` you feed `time`, and palettes
blend in sRGB so designer colors read true. Three of them read the layer's
**alpha shape** (draw a shape or logo into a transparent layer, then filter it),
and the others transform the whole layer. `Effects/DesignFilters` shows six of
them; `Images/LuminanceMelt` shows the melt.

<img src="../../Guide/Images/16-LayersAndEffects/DesignFilters.jpg" alt="Six tiles in two labeled rows. The top row, 'these read the shape', shows the same heart silhouette as flowing chrome, as a red-and-blue thermal map with contour bands, and as pale swirling gem smoke. The bottom row, 'these read the picture', shows the same orange and teal mesh gradient behind angled glass flutes, refracted through rippling water, and embossed onto a crumpled paper sheet" width="680">

- **`.liquidMetal(repetition:softness:dispersion:distortion:contour:angle:tint:phase:)`**
  render the alpha shape as flowing chrome: reflectance bands that compress and wrap
  the silhouette as if the shape were inflated, with chromatic fringing.
- **`.heatmap(colors:contour:innerGlow:outerGlow:angle:noise:phase:)`** thermal
  imaging of the alpha shape: heat blooms inside, a halo radiates outside, traveling
  waves pulse through, all mapped cold-to-hot through `colors` (the first stop fades
  to transparent).
- **`.gemSmoke(colors:body:innerSwirl:outerSwirl:innerGlow:outerGlow:offset:scale:angle:phase:)`**
  smoke coils trapped inside the alpha shape (and leaking around it) over a glassy
  body fill.
- **`.flutedGlass(flutes:shape:profile:distortion:shift:stretch:blur:edges:highlights:shadows:margins:angle:)`**
  ribbed architectural glass: each flute refracts its slice of the image
  (`FluteProfile`: `.prism` / `.lens` / `.contour` / `.cascade` / `.flat`), the flute
  layout bent by `FluteShape` (`.lines` / `.irregular` / `.wave` / `.zigzag` /
  `.eggCrate`), with boundary hairlines, shadow ramps, a frost `blur`, and `margins`
  (layer pixels) leaving a plain frame around the glass. Static by design, so animate its
  knobs.
- **`.water(scale:waves:refraction:layering:edges:highlights:highlight:phase:)`** the image
  under shallow rippling water: broad waves wobble it, caustics shimmer it, bright
  filaments wash over it.
- **`.paperTexture(paper:shading:contrast:roughness:fiber:crumples:folds:drops:seed:)`**
  lay the image onto a synthesized sheet of paper (tooth, fibers, crumple facets,
  fold creases, speckles), embossed by the same relief lighting. Static by design.
- **`.melt(colors:scale:warp:liquify:blend:phase:)`** the luminance melt: the layer
  liquified by a warped noise field and poured through a four-stop palette (dark to
  light). One displacement does double duty, warping the field's own domain and
  shifting where the layer is sampled, so the picture smears along the field's
  currents while its brightness steers the field back. `liquify` is the smear,
  `blend` how much the image leads (1 reads the liquified picture straight through
  the palette), `warp` the turbulence, `scale` the field zoom. The picture survives
  as light and shadow, not as its own colors; that dyed reading is the look.

```swift
let logo = renderTarget()
withTarget(logo) { noStroke(); fill(.white); drawHeart(width / 2, height / 2, 400) }
drawImage(logo.filtered(.liquidMetal(phase: time)).image, 0, 0)
```

Filters chain, so an effect reads as one expression:

```swift
layer.filtered(.threshold(0.5)).filtered(.gaussianBlur(radius: 3)).filtered(.gradientMap(.magma))
```

<a id="combined"></a>
### combined(with:_:) and Combine

A [`Filter`](#filter) reads one layer, while a `Combine` reads **two**: a base layer and an auxiliary layer that modulates it, which is what masking, displacement, and cross-dissolve need. `base.combined(with: aux, op)` runs the op on the GPU and hands back a new layer, itself filterable and combinable, so multi-input effects chain like single-input ones.

A `Combine` is a value descriptor like `Filter`, but the aux layer rides alongside it (a value descriptor can't hold a `RenderTarget`), passed as the `with:` argument. The ops:

- **`.mask(channel:invert:)`** keep the base where the aux reads **bright** (`channel: .luminance`, the default; draw the mask in white over transparent) or **opaque** (`channel: .alpha`), fading to transparent elsewhere, and `invert` flips it. A spotlight reveal, a vignette, a clip to a shape.
- **`.displace(amount:)`** offset the base's pixels by the aux read as a **vector field**: red → horizontal, green → vertical, mid-gray = no shift, up to `amount` of the layer. Feed it noise or a gradient for ripples, smearing, heat-haze, and refraction.
- **`.disperse(amount:mode:spectral:quality:)`** chromatic aberration over the base, its amount scaled per pixel by the aux's brightness. A white aux splits by the full `amount` and a black one leaves the base alone, so the aux decides *where* the color comes apart rather than how much. `mode`, `spectral`, and `quality` mean what they mean on [`.chromaticAberration`](#filter).
- **`.mix(amount:)`** cross-dissolve the base toward the aux by `amount` (0 = base, 1 = aux), the transition workhorse.
- **`.paintMix(amount:quality:)`** blend the base toward the aux the way scattering paints blend, not the way lights cross-dissolve: per pixel both colors become reflectance spectra and mix through the Kubelka-Munk model over a `quality`-sized set of wavelength taps, the GPU form of `Color.mix(_:_:t:in: .paint)` (see [Spectral color](Spectrum.md)). A yellow wash over a blue field meets it in green, and overlaps darken like glazes. The aux's own coverage gates the mix, so where the aux layer is empty the base passes through untouched and the aux reads as paint laid over the base; `amount` is the mix where it's opaque.
- **`.seamlessClone(amount:threshold:)`** drop the aux layer into the base so the join disappears: the patch keeps its own detail and takes on the base's color and brightness, which is what stops a cut-out reading as a cut-out. **The aux's opaque region is where it lands**, so draw the patch into a layer of its own, transparent everywhere else, positioned where you want it. Around the rim of the patch it measures how far the patch's color sits from the base's, spreads that difference across the inside as smoothly as it can, and adds it back, so the rim matches the base exactly and the inside is nudged by the gentlest correction that reaches it. `amount` dials that correction, with 1 fully seamless and 0 a plain paste with the seam left in (a useful before picture); `threshold` is the alpha a texel needs to count as part of the patch, worth raising if a soft-edged patch reads as larger than it looks. Two limits follow from what it does rather than from the implementation. Only the low, slow part of the patch's color is replaced, so its **range of tone is kept**: drop a contrasty patch somewhere much darker than itself and its shadows are pushed below black and clip. And the rim is where the whole answer comes from, so a rim laid **across a hard edge** in the base smears that edge inward. Keep the rim on quiet ground. See the `Effects/SeamlessClone` example.
- **`.defocus(focus:range:maxBlur:quality:)`** depth of field: blur the base by the aux read as a **depth map** (its luminance is the depth, 0 near … 1 far). The band `focus ± range` stays sharp, and the blur grows with distance from it up to `maxBlur` pixels. It's a circle-of-confusion bokeh gather with near/far separation. The depth map can be a smooth gradient (a tilt-shift plane), a real depth feed, or hard-edged discrete per-object depths, since overlapping defocused regions blend like real bokeh, a defocused foreground spreads over and covers an in-focus subject behind it, and a sharp subject occludes the blur behind it with a crisp edge. `quality` is a `RenderQuality` tier (`.default`/`.performance`/`.detail`, hardware-relative) setting the bokeh sample count. More taps trade frame rate for creamier, structure-free blur (`maxBlur` is the blur *amount*, and `quality` is the blur *smoothness*). **`blades`, `irisAngle`, and `catsEye` shape the highlights.** An out-of-focus point of light is a picture of the opening it came through, so an iris with `blades` makes it a polygon of that many sides (`0` is round, 5 to 11 is what a real lens carries), `irisAngle` turns the opening, and `catsEye` (0 to 1) clips it toward the corners the way a lens barrel does, laying a highlight down into a lemon the long way around the frame. The polygon is taken at the same *area* as the round opening, so a blade count changes the shape of a highlight and not how large it reads, and `catsEye` changes shape only (reach for `.vignette` to darken the corners as well). `blades` left unnamed takes the blade count from the camera that drew the depth layer (`Camera3D.apertureBlades`), so a 3D scene defocused by its own depth wears the same opening its [lens flare](../3D/LensFlare.md) ghosts and its [path-traced export](../Output/PathTraced.md) do; name it at the call to shape a blur no camera knows about, such as a tilt-shift over a hand-drawn ramp. One limit worth knowing: the shape is only as clean as the tap budget, so a light much smaller than the spacing between taps comes out showing the gather's own pattern. Keep a light a few pixels across or raise `quality`. A round opening costs exactly what it always did, and a shaped one costs about a third more GPU time. See the `Effects/Bokeh` example.- **`.ambientOcclusion(radius:intensity:bias:quality:)`** ambient occlusion: darken the base in crevices, gaps, and where surfaces meet, reading the aux as a **depth map**. View-space position and surface normal are reconstructed from the depth (no separate normal buffer), then occlusion is estimated with a hemisphere of samples oriented to the normal (a dense low-discrepancy kernel, so it stays stable without per-pixel jitter, smoothed with a depth-aware blur) and multiplied into the base. Feed it a 3D scene's own [`depth`](#depth), since that layer carries the camera's near/far and field of view, so `radius` reads in **world units**. `intensity` scales the darkening, `bias` rejects self-occlusion (raise it if flat faces speckle, lower it if contacts look weak), and `quality` is the sample-count tier. As a post-process it darkens the final image, not just the ambient term, the standard screen-space trade, dialed with `intensity`.
- **`.screenSpaceReflections(intensity:maxDistance:thickness:roughness:fresnel:edgeFade:quality:)`** screen-space reflections: make the scene reflect off its own surfaces (a glossy floor, wet asphalt, a polished tabletop), reading the aux as a **depth map**. Each pixel's reflection ray is built from the view-space position and surface normal, marched through the depth buffer until it meets the scene, and the color there is composited back over the surface. Feed it a 3D scene's own [`depth`](#depth), since the layer carries the camera scale, so `maxDistance` reads in **world units**. `intensity` is the reflection strength, `thickness` is how close a ray must pass a surface to hit it (a fraction of the surface's distance, so it scales with the scene, and too large smears a reflection into a "cylinder"), `roughness` blurs it for a glossy (rather than mirror) finish, `fresnel` strengthens it at grazing angles, `edgeFade` fades a reflection as its ray nears the frame border, and `quality` is the ray-march step tier. It reflects only what's already on screen, so off-screen and hidden geometry can't appear (rays fade out as they reach the frame edge). Like all screen-space reflection, it's at its best on broad surfaces with well-separated reflected objects; very dense or near-grazing scenes can show faint artifacts where reflected surfaces graze the ray. A touch of `roughness` softens those, and the `Examples/3D/Effects/ScreenSpaceReflections` sketch shows a clean composition. Reflections are accumulated across frames so they hold steady as the camera moves, and the march runs at a resolution the `quality` tier sets (full on export). One limit is worth understanding plainly: this effect makes a mirror out of the *finished picture*, and a picture doesn't contain the back of anything. Wherever the true reflection is of a surface the camera can't see (the underside of a ball resting on the floor, the hidden face of a box), the effect can only approximate, which shows as a soft, imperfect zone at object-floor contacts. For exact mirrors of real geometry, including hidden and off-screen surfaces, use [`rayTracedReflections()`](../3D/3D.md#ray-traced-reflections) on a ray-tracing GPU, and [Combining 3D features](../3D/Combining.md) compares the two side by side.

```swift
let scene = renderTarget()
withTarget(scene) { background(.black); fill(.orange); drawCircle(width / 2, height / 2, 300) }

let mask = renderTarget()
withTarget(mask) { fill(.white); drawCircle(mouseX, mouseY, 200) }   // white = visible

drawImage(scene.combined(with: mask.filtered(.gaussianBlur(radius: 12)), .mask()).image, 0, 0)
```

The base and aux can render at different `scale`s, since the aux is sampled by normalized coordinates. In a `compose { }` block, the same ops read as `aside` modifiers ([below](#aside)). The `Effects/Aside` example shows a displacement map and a spotlight mask in one scene.

<a id="depth"></a>
### depth: a 3D scene's depth as a layer

The depth map `.defocus` reads can be one you draw by hand, but when the scene **is** 3D its depth comes for free. Draw a 3D scene into a render target, and because meshes (or point clouds) land in it the target captures depth, exposed as `target.depth`, a gray layer (0 near … 1 far) the renderer fills from the scene's own depth buffer. Feed it straight to `.defocus` as the aux and a real 3D render racks focus like a lens, no hand-drawn depth map needed. The same layer feeds `.ambientOcclusion` and `.screenSpaceReflections`, and because it carries the camera's near/far and field of view, their world-unit parameters (`radius`, `maxDistance`) read in the scene's own scale.

```swift
let scene = renderTarget()
withTarget(scene) {
    perspective(eye: Vector3(0, 2, 18), target: .zero, near: 5, far: 34)   // bracket the scene
    drawSphere(radius: 1.5)                                                 // 3D → depth captured
    // … more meshes …
}
let dof = scene.combined(with: scene.depth, .defocus(focus: 0.4, maxBlur: 30))
drawImage(dof.image, 0, 0)
```

`scene.depth` maps over the camera's `near`/`far`, so **set them to bracket your scene**, since tight planes both make the focal plane sweep usefully and give the depth buffer its best precision. It's a normal layer otherwise, so draw it (`drawImage(scene.depth.image, 0, 0)`) to see the depth, or filter it. Depth capture costs nothing on a 2D target (no 3D drawn means no depth buffer), and the extra normalize pass runs only when you actually read `.depth`. The `3D/SceneDefocus` example racks focus through a row of orbs by their own depth.

<a id="generate"></a>
### generate(_:) and Generator

A `Generator` is a procedural pattern filled from math alone, no input layer. Where a
`Filter` transforms a layer you drew, a `Generator` **is** a layer, a source you composite,
filter, or feed into another effect. `generate(_:)` realizes one into a `RenderTarget`,
itself drawable and filterable, so a pattern flows straight into the rest of the chain.
The `Effects/Patterns` example shows the four basic patterns and a composed mix;
`Effects/MeshGradient` and `Effects/DesignPatterns` show the design-pattern set.

```swift
let stripes = generate(.bars(scale: 24, foreground: .black, background: .white))
drawImage(stripes.filtered(.gaussianBlur(radius: 4)).image, 0, 0)

// A layered mix: noise → colormap, with a grid multiplied over it.
let field = generate(.noise(scale: 5)).filtered(.gradientMap(.turbo))
drawImage(field.image, 0, 0)
blendMode(.multiply)
drawImage(generate(.gridLines(scale: 20, weight: 0.08)).image, 0, 0)
```

The basic patterns (cells stay square whatever the layer's aspect ratio):

- **`.checkers(scale:foreground:background:)`** a two-color board, `scale` cells across.
- **`.gridLines(scale:weight:foreground:background:)`** a line grid, each line `weight` (0…1) of a cell wide.
- **`.bars(scale:vertical:foreground:background:)`** parallel stripes, `scale` across, on either axis.
- **`.noise(scale:sharpness:warp:foreground:background:)`** fractal value noise, from a soft cloud (`sharpness` 0) to a hard two-tone split (1). `warp` domain-warps the field (the layers displace their own sampling coordinates, twice over), where 0 is the plain field and 1 the classic flowing marble-and-cloud smear.
- **`.cellular(scale:jitter:style:foreground:background:phase:)`** Worley cellular noise, `scale` cells across: `.cells` (dark cores brightening toward the walls), `.borders` (thin cracks tracing the walls), or `.mosaic` (flat stained-glass panes). `jitter` runs the cells from a regular grid (0) to fully organic (1). `phase` makes the feature points wander on small orbits so the cells crawl and reform, and it is periodic over 2π, so `phase: loopProgress(over: 12) * .tau` loops seamlessly. See the `Cellular` example.

**Design patterns**: richer animated sources in the same mold. Every one takes a
`phase` you feed `time` for motion (or hold fixed for a still), most take a palette
of `colors` plus a `background`, and centered compositions stay centered and round
at any canvas aspect. Their palettes blend in sRGB (the space design gradients are
authored in), so the mixes match what a design tool would show:

```swift
// An animated wallpaper in one call.
drawImage(generate(.meshGradient(phase: time)).image, 0, 0)
```

- **`.meshGradient(colors:distortion:swirl:mixing:grain:phase:)`** soft blobs of up to 8 colors
  drifting on orbits, blended into the classic mesh-gradient wash; `distortion` smears it
  organically, `swirl` winds a vortex, `mixing` runs the blend from hard poster cells (0)
  through the classic look (0.5) to a buttery wash (1), `grain` dithers the boundaries and
  films the result.
- **`.filaments(color:highlight:background:scale:brightness:contrast:phase:)`** a glowing
  web of thin writhing filaments, the neural-lace look.
- **`.smokeRing(colors:background:radius:thickness:fill:scale:detail:phase:)`** a billowing
  ring of smoke, radially banded through the palette, and `fill` softens it from crisp ring
  toward a smoky disk.
- **`.colorPanels(colors:background:density:length:skew:blur:fadeIn:fadeOut:gradient:phase:)`**
  translucent color panes fanning around a central axis in fake perspective.
- **`.spiral(foreground:background:density:distortion:strokeWidth:taper:cap:noise:noiseScale:softness:scale:phase:)`**
  a two-color spiral, from crisp line-art through whirlpool to wobbly hand-drawn rings.
- **`.waves(foreground:background:shape:frequency:amplitude:spacing:proportion:softness:scale:phase:)`**
  wavy-line stripes, where `shape` (0…3) morphs zigzag → sine → irregular mixes.
- **`.dotOrbit(colors:background:scale:size:sizeVariation:spread:steps:phase:)`** a grid of
  dots, each orbiting its own cell on its own phase, colors quantized to flat print-like shades.
- **`.grainGradient(colors:background:shape:softness:intensity:noise:phase:)`** poster-style
  banded gradients over an animated field (`GrainShape`: `.wave` / `.dots` / `.truchet` /
  `.corners` / `.ripple` / `.blob` / `.sphere`), the band edges chewed by film grain.
- **`.pulsingBorder(colors:background:roundness:thickness:softness:intensity:bloom:spots:spotSize:pulse:smoke:smokeScale:margins:phase:)`**
  a glowing rounded border hugging the layer edge (inset by `margins`, in layer pixels),
  up to eight light spots per color racing the perimeter, with a heartbeat `pulse` and
  smoke wisps.
- **`.godRays(colors:background:x:y:density:breakup:coreSize:coreIntensity:intensity:bloom:bloomTint:phase:)`**
  crepuscular rays streaming from a point, one drifting streak layer per color. `bloom`
  morphs the stack from alpha layering to additive light, and `bloomTint` washes an extra
  glow color over the lit areas.

**Pattern fields**: closed-form animated fields, each a few lines of per-pixel math
with a strong signature look. Same conventions as the design patterns (a `phase` to
feed `time`, sRGB palette blending, square cells at any aspect):

- **`.quasicrystal(colors:background:symmetry:scale:contrast:phase:)`** plane waves at
  `symmetry` evenly spaced angles, summed into a pattern that is ordered but never repeats,
  with crisp N-fold stars around its bright centers. The field walks the palette,
  `contrast` sharpens the walk, and `phase` shimmers the whole crystal.
- **`.moire(foreground:background:sources:frequency:scale:phase:)`** a few concentric
  ring gratings on slowly orbiting centers, and where they overlap, their beat sweeps out
  large fringes that move much faster than the centers do.
- **`.gyroid(foreground:background:scale:thickness:phase:)`** a planar slice of the
  gyroid surface, drawn as interwoven organic bands with a dimmed echo for depth, and
  `phase` sweeps the slicing plane so the bands crawl and reconnect.
- **`.phyllotaxis(colors:background:count:dotSize:phase:)`** the sunflower's seed
  arrangement (golden-angle spiral) as a continuous dot field, colored center-to-rim
  by age. Past `dotSize` ≈ 1 the dots fuse into a cellular texture, and `phase` spins the head.
- **`.hexPulse(colors:background:scale:gap:phase:)`** a hexagonal lattice whose every
  cell breathes on its own hashed rhythm, brightness and a little size riding the pulse.
- **`.chladni(m:n:style:weight:grain:foreground:background:scale:phase:)`** the
  standing-wave field of a ringing square plate: `.sand` gathers speckled ink along the
  still nodal lines (`weight` the gather width, `grain` from smooth ink to loose sand,
  shivering as `phase` advances), `.wave` breathes the signed field between the colors.
  Integer `m`/`n` ring true modes and fractional values morph between figures; the
  full story (the CPU field, nodal isolines, the audio join) is on its
  [own page](../Generators/Chladni.md).

See `Examples/Effects/PatternFields` for the first five (plus a field chained into
`.relight`), and `Examples/Patterns/Chladni` for the plate.

**Escape-time fractals**: the classic sets as generators, colored by the smooth
(stepless) iteration count through the palette, `phase` cycling the bands:

- **`.mandelbrot(colors:interior:center:zoom:iterations:cycles:phase:)`** the Mandelbrot
  set: iterate z = z² + c from zero at every pixel's c and color by how fast the orbit
  escapes; points that never escape are the set, painted `interior`. `center`/`zoom`
  frame the complex plane (zoom 1 shows the whole set, and float precision holds useful
  detail to a few thousand times in), and `iterations` caps the orbit (raise it as you
  zoom).
- **`.julia(c:colors:interior:center:zoom:iterations:cycles:phase:)`** a Julia set: the
  same iteration with `c` fixed and the orbit started at each pixel, so every `c` yields
  a different filigree (points near the Mandelbrot set's edge give the richest). Animate
  `c` a little and the whole form morphs.
- **`.orbitTrap(_:c:colors:center:zoom:iterations:glow:angle:)`** an orbit trap: the
  same iteration, colored by the orbit's closest pass to a trap shape held in the
  plane rather than by its escape. Orbits that graze the trap glow through the last
  of `colors`; distant ones sit in the first. Stalks and filaments appear wherever
  orbits pass near the shape. The trap is a `Generator.OrbitTrap`: `.point(_:)`,
  `.cross(_:)` for the stalk look, `.circle(center:radius:)`, or
  `.square(center:radius:)`, the outlines lit from both sides. `c: nil` works the
  Mandelbrot plane; a fixed `c` picks that Julia set and re-centers the default
  framing. `glow` is the falloff distance in plane units; tighten it to thin the
  filaments. `angle` turns the trap about its own center; feed it your `time` and
  the stalks sweep.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/18-IteratedForms/FractalPair-dark.jpg">
  <img src="../../Guide/Images/18-IteratedForms/FractalPair.jpg" alt="Three panels in blue, gold, and cream. The whole Mandelbrot set with a small red circle marking a point on the edge of its left bulb; a Julia set of dense spiral filigree; and a deep zoom into the Mandelbrot boundary showing the same shapes recurring at a smaller scale" width="680">
</picture>

**Diffusion**: not a look laid over a picture but a picture made out of a few marks.
`.diffuse` holds every drawn pixel as a color source and lets the color out into the
empty space between them until it settles. Away from the marks every pixel ends up the
average of its four neighbors, which is the rule a soap film obeys, so the field is
smooth everywhere, nothing overshoots, and no color appears that was not put there.

- **`.diffuse(threshold:sharpness:)`** a pixel counts as a source when its alpha is at
  least `threshold`, and a half-opaque mark pulls half as hard as a solid one, so draw
  the marks into a layer of their own and filter that. `sharpness` (0…1) decides how much
  of the solving happens at full size: low is faster and softer, 1 keeps a thin mark's
  color crisp right up against it.
- **`drawDiffusionCurve(_:left:right:width:)`** lays the form the technique is named for:
  the same path twice, a hair apart, carrying a different color on each side, so the field
  jumps across the curve and is smooth everywhere else. Left and right are named from
  walking the path in the order its points come, so reversing them swaps the colors. It
  takes a `Contour` or bare points, and `width` is how thick each side's mark is (two or
  three points is plenty).

```swift
let marks = renderTarget()
withTarget(marks) {
    drawDiffusionCurve(horizon, left: Color(hex: 0xE86F4A), right: Color(hex: 0x101A2E))
    noStroke(); fill(Color(hex: 0xFFE9B0))
    drawCircle(width * 0.7, height * 0.2, 26)     // a light the whole field bends around
}
drawImage(marks.filtered(.diffuse()).image, 0, 0)
```

A gradient needs a direction and two ends. This needs neither, which is why the field can
be shaped by where the marks are rather than by a line between two stops. See
`Examples/Effects/DiffusionCurves`.

The solve is the frame's cost: about 24 ms of GPU at 1080 square on an M2, running every
frame while the marks move. When they do not move, do it once. Hold the filtered layer in
a property, fill it in `setup()`, and draw it each frame like any other image.


**Measured distance fields**: a question asked of a layer rather than a look laid over it.
`.distanceField` measures how far every pixel is from the nearest edge of whatever was
drawn, and which way that edge lies, and `.fieldMap` reads the answer back as a picture.
Growing and shrinking a shape, outlining it at an offset, drawing its contour lines, and
building a Voronoi keyed to the marks themselves are all one small step from there.

- **`.distanceField(from:threshold:maxDistance:)`** measure the field. Red is the distance
  in pixels, negative inside the shape; green and blue are the unit direction to that
  nearest edge, so `pixel + direction * abs(distance)` is the edge point itself. `from`
  chooses what the threshold cuts (`.alpha` by default, or brightness or one channel for a
  layer with no transparency in it), and `maxDistance` both bounds the answer and shortens
  the work.
- **`.fieldMap(_:from:to:repeating:)`** read a measured field back through a `Ramp` or
  `Colormap` over a window given in pixels, wrapped rather than clamped when `repeating`,
  which draws the field as contour bands.

```swift
let field = marks.filtered(.distanceField())
drawImage(field.filtered(.fieldMap(.viridis, from: 0, to: 40, repeating: true)).image, 0, 0)
```

A user shader reads the field with `sampleRaw`, which returns the layer's stored values
with no color conversion, and that is how the direction gets used. The whole surface,
including the nearest-edge shader, is in [Measured distance fields](DistanceFields.md); see
`Examples/Effects/DistanceField`.

The measurement costs about 4.9 ms of GPU at 1080 square on an M2 over the whole canvas,
and about 2.9 ms capped at 64 pixels.


**Domain coloring**: the same plane, asked a different question. Instead of iterating,
evaluate a complex function once at every pixel and paint the *direction* its answer
points, off a palette wheel that wraps (the last stop blends back into the first, so a
turn has no seam). What you get is readable: a **zero** shows the whole wheel once
turning counter-clockwise, a **pole** shows it once the other way, and a repeated zero
shows it twice. Counting wheels counts zeros and poles, which is the argument principle
drawn rather than proved.

- **`.domainColoring(_:colors:shading:strength:center:zoom:phase:)`** the function is a
  `Generator.ComplexFunction`: `.rational(zeros:poles:)` places up to four of each (repeat
  a point for a double zero, leave `poles` empty for a polynomial) and is the one to move
  around; `.power(_:)` winds the wheel that many times, and a fractional exponent leaves
  the seam of its branch cut on show; `.exponential`, `.sine`, and `.tangent` are the
  classics, `tan z` alternating zeros and poles along the real axis; `.logarithm` draws
  its own cut down the negative real axis.
- `shading` is a `Generator.DomainShading`: `.phase` is color alone (the plain phase
  portrait, every point fully lit), `.modulus` ramps dark to light between each doubling
  of the value's size (a contour map of magnitude), and `.conformal` rules direction too,
  twelve sectors to the turn, so away from the interesting points the field tiles into
  little squares. `strength` (0…1) sets how hard the rulings press.
- `center` and `zoom` frame the plane as they do for the fractals (zoom 1 shows about
  3 units across), the imaginary axis running **up** the canvas as it is written on paper.
  `phase` turns the palette around the wheel and recolors only, so `phase: time * 0.05`
  is free.

See `Examples/Effects/DomainColoring` for the four above, one of them swimming its zeros.

See `Examples/Effects/Fractals` for the first two, with the Julia's `c` on a slow
orbit, and `Examples/Effects/OrbitTraps` for all four traps, two of them turning.

A pattern composes for the layer it fills. The default `generate(_:)` makes a
full-canvas layer, and `generate(_:width:height:)` fills one of an explicit size, so a
tile or panel gets its own undistorted pattern instead of a squashed full-canvas one.

<a id="postprocess"></a>
### postProcess(_:)

Apply a filter to the **whole finished frame**, just before it's shown, the quick way to bloom or blur everything without managing a layer:

```swift
override func draw() {
    background(.black)
    // …draw a bright scene…
    postProcess(.bloom(threshold: 0.7, intensity: 1.2))   // glow the whole frame
}
```

Call it in `draw()`, and multiple calls chain in order.

<a id="feedback"></a>
### feedback(scale:) and withFeedback(_:_:)

A `Feedback` layer **remembers itself across frames**. Each frame you read last frame's content, transform it (fade, zoom, rotate, offset), and draw new content on top, and the result becomes next frame's content. That read-transform-write loop is what makes trails, tunnels, and the video-feedback look of a camera pointed at its own screen.

It's distinct from the [accumulation surface](../Drawing/Accumulation.md) (`noClear`), which piles new draws onto an *unchanging* canvas. Feedback hands you the previous frame as an **image you can transform** before drawing it back, and that transform step is the whole effect.

Unlike `renderTarget()` (a per-frame handle), a `Feedback` is **persistent**, so make it once in `setup()` and hold it. Its identity is what ties this frame's write to last frame's read, so make a fresh one each `draw()` and it never builds up.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/16-LayersAndEffects/FeedbackSteps-dark.jpg">
  <img src="../../Guide/Images/16-LayersAndEffects/FeedbackSteps.jpg" alt="Four panels of the same orbiting dot drawn into feedback layers with different transforms: fade only leaves a short tail, zoom smears it into a streak, rotate wraps it into a swirl, zoom plus rotate coils it into a spiral" width="680">
</picture>

```swift
var trail: Feedback!

override func setup() { trail = feedback() }      // make once, store it

override func draw() {
    background(.black)                            // clears the canvas (resets the frame)
    withFeedback(trail) { prev in                 // prev = last frame's content
        translate(width / 2, height / 2)          // spin + shrink the old frame
        rotate(0.06); scale(0.98)                 //   about the canvas center
        translate(-width / 2, -height / 2)
        tint(Color(white: 1, alpha: 0.94))        // gentle decay so trails fade
        drawImage(prev, 0, 0)
        noTint()
        fill(.white); drawCircle(mouseX, mouseY, 12)   // a fresh mark on top
    }
    drawImage(trail.image, 0, 0)                  // composite the result to the canvas
}
```

- `withFeedback(_:_:)` hands the previous frame in as the closure parameter. The `withTarget(feedback) { … }` form works too, reading last frame by name with `feedback.previous` inside.
- `feedback.previous` is last frame's content, and `feedback.image` is this frame's, for compositing.
- `feedback.filtered(_:)` runs this frame's result through a `Filter` (bloom the trails, recolor them through a gradient map) like any layer, and the state the loop carries forward stays untouched.
- Call `background(_:)` **before** the block. On the canvas it resets the whole frame, so calling it after would wipe the layer's geometry (like any other `withTarget` layer). Inside the block, `background(_:)` clears just the feedback layer.
- See the `Effects/Feedback` example for a spiralling tunnel.

<a id="simfield"></a>
<a name="simfield"></a>

### simField(_:) and Sim

Where a [`Filter`](#filter) transforms an image once, a `Sim` runs a **stateful simulation** on a persistent layer that evolves every frame by reading its own neighborhood: reaction-diffusion patterns spreading, cellular-automaton cells living and dying, a fluid carrying color. You don't write the kernel. Pick a `Sim` from the catalog, make a `SimField` with it, and **draw into the field to seed or force it**.

A `SimField` is **persistent** like `Feedback` (make it once in `setup()` and hold it). Each frame the marks you draw in `withField` land on the field's current state, the renderer steps the simulation, and the result is the field's `image`. The raw state is *data*, so recolor it through the same `Filter` catalog as everything else.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/19-GridSimulations/FeedKillMap-dark.jpg">
  <img src="../../Guide/Images/19-GridSimulations/FeedKillMap.jpg" alt="A six-by-four grid of reaction-diffusion dishes at different feed and kill settings: most sit quiet, while a diagonal band grows spots, rings, mazes, and mitosing dots" width="680">
</picture>

```swift
var rd: SimField!

override func setup() { rd = simField(.reactionDiffusion(), scale: 0.5) }   // half-res field

override func draw() {
    withField(rd) {                                  // draw to seed: marks inject chemical
        noStroke(); fill(.white)
        if mouseIsPressed { drawCircle(mouseX, mouseY, 16) }
    }
    drawImage(rd.filtered(.gradientMap(.magma)).image, 0, 0)   // evolve, then recolor
}
```

The catalog:

- **`.reactionDiffusion(feed:kill:)`** Gray-Scott reaction-diffusion: two chemicals diffuse and react into coral, spots, stripes, and dividing cells. Draw light marks to inject chemical B (it spreads from there), and `feed`/`kill` pick the regime. State is A in red, B in green. Recolor with `.gradientMap`/`.threshold`. The **`.reactionDiffusion(feed:kill:toFeed:toKill:)`** form lets the regime *vary across the field*: set the field's `modulation` to a layer and its brightness slides `feed`/`kill` per texel, from the first pair where the map is black to the `to` pair where it is white. It stays one continuous simulation, so the pattern flows across the regime boundary instead of seaming at it: a camera matte as the map grows maze walls on a silhouette and spots everywhere else (the `Vision/TuringMirror` example), and any drawn or generated layer steers it the same way. Draw the map each frame before reading the field; a frame with no map runs the plain black-end pair.
- **`.gameOfLife()`** Conway's Game of Life (B3/S23). Draw white to make cells alive, black to kill them. Use a low field `scale` so each texel is a visible cell. The `image` is crisp black-and-white.
- **`.lenia(radius:growthCenter:growthWidth:timeScale:rings:)`** Lenia, the *continuous* Game of Life: the state is a smooth `0...1` mass, and each step convolves it with a soft ring kernel and grows or starves every texel by how close its neighborhood mass sits to `growthCenter` (`growthWidth` is how forgiving that rule is). Blobs pulse, split, and swim. Seed it with a *dense* soup of soft gray-to-white marks, because sparse mass starves, and the dying, labyrinth, rings, and fat-maze looks are all real regimes of the model, so if everything fades, seed denser or widen the growth. The kernel reads `radius` texels around every texel each step, making the field `scale` the cost lever, and `SimField.sim` is settable live (`field.sim = .lenia(...)`) so growth knobs can ride a `@Param`. The `image` is grayscale mass; recolor with `.gradientMap`. The CPU cellular automata (Wolfram rules, turmites) live in [Generators → Cellular automata](../Generators/CellularAutomata.md).
- **`.ripples(speed:damping:)`** a water surface: the 2D wave equation on a height field, the classic interactive ripple pool. A drawn mark's brightness is *added* to the surface height (this sim's inject leaves its velocity channel alone), the bump collapses, and rings spread, reflect softly off an absorbing rim, and die away by `damping`. Dab soft marks (a `drawCircle` under a radial gradient fading to clear is the ideal drop; a hard-edged disc rings at every frequency, a real splash) and don't hold them, since an opaque held mark pours water every frame. The state is height in red and velocity in green, both signed; the raw `image` is a debugging view, so recolor it or shade it as a surface with `.filtered(.relight(...))`. `speed` is the neighbor-coupling gain and is capped at 1: the step goes unstable at 2, where the shortest wave the grid can hold grows with every step and settles into a grid-scale rattle that shades into glitter. Rings still travel at a good pace because the step takes six substeps a frame. See the `Simulation/Ripples` example.
- **`.multiScaleTuring(scales:seed:)`** McCabe's multi-scale Turing patterns: one substance, looked at through several magnifications at once. Each scale averages the field over a small disc (the *activator*) and a larger one (the *inhibitor*), and where the small average is the greater the field brightens a little, otherwise it darkens. That rule at a single scale grows the stripes of a zebra; at several scales, each pixel each step runs them all and lets only the one whose two averages *disagree least* act, so broad forms and fine detail settle into the same picture and it comes out looking like an electron micrograph of a diatom. Unlike the rest of the catalog, a Turing field **needs no seeding**: it starts from noise and organizes itself, so reading it is enough to run it and a `withField` block is only for disturbing a settled pattern (a mark's brightness replaces the field, and the pattern heals around it). Edges wrap, so the picture tiles. The `image` is grayscale, ready for `.gradientMap`, or for `.relight` to read it as relief, which is worth trying first: the lit-from-above look is an accident of a flat 2D rule and reads as real depth. See the `Simulation/MultiScaleTuring` example.
- **`.cyclic(states:threshold:range:neighborhood:seed:)`** Griffeath's cyclic cellular automaton: every cell wears one of `states` colors arranged in a circle, and a cell advances to the next color the moment at least `threshold` neighbors already wear it, so each color eats the one before it and is eaten by the one after. The field **needs no seeding**: it starts from seeded random states (a uniform field is a fixed point, so noise is the required start, and the same `seed` replays the same run) and self-organizes through the famous four acts, colored static, growing droplets, spiral defects, and finally a field of turning spiral cores. The defaults are the classic rule (14 states, threshold 1, the four edge-sharing neighbors); raising `threshold` with a wider `range` (and `.moore`, the eight-cell block) trades spirals for churning block turbulence. Drawing *stamps* states (brightness picks the state, white the top) and the flow swallows the wound. The `image` is one flat gray level per state, made for `.gradientMap` with a ramp whose last stop repeats the first hue, so the wheel closes without a seam. One texel is one cell; edges wrap. See the `Simulation/CyclicAutomaton` example.
- **`.excitable(states:threshold:range:neighborhood:)`** the Greenberg-Hastings model, the classic cellular automaton of excitable media (heart tissue, neurons, a chemical oscillator). A resting cell fires when at least `threshold` neighbors are firing, then climbs alone through its refractory tail back to rest, and mid-recovery it cannot be re-lit, which is exactly what turns a spark into a traveling ring with a dead zone behind it: rings annihilate where they collide, and a broken front curls into a pair of counter-rotating spirals that re-excite the medium forever. The field starts at rest, so **draw to spark it**: a bright mark excites the cells it covers, a black mark calms them (dab sparks for rings; excite a line, let it grow, then wipe half the plane with black and the cut ends curl into spirals). Rest reads black, a firing cell faint gray, the refractory tail climbs toward white; run it through `.gradientMap` with a dark-to-hot ramp so the wavefronts glow. See the `Simulation/Excitable` example.
- **`.briansBrain()`** Silverman's three-state automaton where every cell is ready, firing, or resting: a ready cell fires on exactly two firing neighbors, a firing cell spends the next step resting (and cannot be re-lit), a resting cell returns to ready. Almost nothing settles, so the field boils forever with gliders racing along diagonals and orthogonals. **Draw loose sprinkles, not solid blobs**: a solid blob dies at once (every interior cell rests together, and a flat edge shows three neighbors where a birth needs exactly two), while a random soup explodes into permanent traffic. The raw `image` is already the classic picture (white fire, mid-gray afterglow, black ground); a `.gradientMap` restyles it. See the `Simulation/BriansBrain` example.
- **`.hodgepodge(states:k1:k2:g:neighborhood:seed:)`** the Gerhardt-Schuster hodgepodge machine, the automaton built to mimic an oscillating chemical reaction (its curling wavefronts are dead ringers for the Belousov-Zhabotinsky reaction in a dish). Cells run from healthy (0) through degrees of infection to ill (`states`): a healthy cell catches `⌊a/k1⌋ + ⌊b/k2⌋` from its infected and ill neighbors, an infected cell climbs to its neighborhood's average infection plus `g` (the speed of infection, the behavior dial: low dies out, mid plateaus, high locks into the spiral regime), and an ill cell recovers to healthy at once. Like the cyclic automaton it **needs no seeding** (all-healthy is a fixed point, so it starts from seeded random states and the same `seed` replays the same run); drawing stamps degrees of infection and the waves close over the wound. The `image` is the infection degree as grayscale, made for `.gradientMap` across a hot or rainbow ramp, the classic way these figures are pictured. See the `Simulation/Hodgepodge` example.
- **`.sandpile(pour:topplings:)`** the Abelian sandpile (the Bak-Tang-Wiesenfeld model, the one that named *self-organized criticality*): grains pile up on a grid, any cell holding four or more topples, sending one grain to each of its four neighbors for every four it holds, and a single grain dropped on a settled pile can set off an avalanche of any size. Draw into the field to pour sand: a full-white mark adds `pour` grains to every texel it covers, each frame, scaled by the mark's brightness and rounded to whole grains; nothing erases, and grains that topple over the field's edge fall off and are gone (that slow leak is what lets the pile keep settling). The classic circular figure with its self-similar lobes comes from the drop-and-relax protocol: pour one heavy mark on one frame (`pour: 1024` under a small disc), then let the mountain collapse. A mark *held* down is a torrent instead, and its center stays molten (cells at four and above, the top of the ramp) for as long as you keep pouring. The state is the grain count in quarters, so a stable cell reads 0, ¼, ½, or ¾ gray: four flat levels made for `.gradientMap`, one color per count, the classic way these piles are pictured. `topplings` is the pacing dial (an avalanche front moves one texel per pass): a few passes per frame let you watch each wave roll, 128 hurries a collapse. See the `Simulation/Sandpile` example.

  Each rung is a `TuringScale` (`activatorRadius`, `inhibitorRadius`, `amount`, `weight`, `symmetry`, `variationRadius`), and the presets are `.ladder` (the default: five rungs doubling from radius 2 to 32), `.broad` (three widely separated scales, big smooth lobes), and `.rosette(n)` (the ladder folded into n-fold rotational symmetry about the center, the diatom plates of McCabe's later figures). Three things about tuning it are worth knowing, because each one is the difference between the pattern and a near-miss:

  - **Keep the amounts equal across scales** unless you want one to dominate. Whichever rung pushes hardest sets the field's range, and since every step renormalizes, the others get squeezed toward mid gray: an uneven ladder gives you one scale's pattern with the rest as a faint wash.
  - **`variationRadius` decides how large a region a scale can claim.** Read at a single point (`variationRadius: 0`) a fine scale's disagreement passes through zero along every contour of its own structure, and least disagreement wins, so it takes a dense web of pixels everywhere and buries the coarse scales. It defaults to the rung's `inhibitorRadius`, which is the balanced choice; smaller sharpens the boundaries between scale regions.
  - **Radii are in field texels**, so they follow the field's `scale`, and a rung at radius 1 works on single texels, which reads as speckle rather than detail. Keep a clear gap between rungs; the default ladder doubles.

  Cost is the one place it differs from the other sims: a step runs a blur pyramid, a variation chain per scale, an extent reduction, and the step itself, so it wants a field `scale` of about 0.5. `symmetry` multiplies the gather, so a rosette costs n times a free field.

- **`.fluid(curl:velocityDissipation:densityDissipation:pressureIterations:buoyancy:)`** a real-time fluid, an incompressible flow that carries color. The mark's *color* injects dye, and `withField`'s `force:` pushes the flow where the mark lands, so dragging (or an animated force) swirls the color. `curl` is the swirliness, the dissipations how fast flow and dye fade, and `buoyancy` an optional upward lift on bright dye (smoke that rises on its own). The `image` is the dye; composite or `.filtered(.bloom)` it directly.

```swift
var fluid: SimField!
override func setup() { fluid = simField(.fluid(curl: 30), scale: 0.5) }

override func draw() {
    let push = Vector2(cos(time), sin(time)) * 4         // an animated push (or a mouse delta)
    withField(fluid, force: push) {                      // color -> dye, motion -> velocity
        noStroke(); fill(Color(hue: time * 0.08, saturation: 0.9, brightness: 1))
        drawCircle(width / 2, height / 2, 16)
    }
    drawImage(fluid.filtered(.bloom()).image, 0, 0)      // the swirling dye, bloomed
}
```

- **`.watercolor(pigments:...)`** wet paint on rough paper: the classic three-layer wash simulation (shallow water above the sheet, pigment settling onto it, moisture creeping through it), rendered by optical Kubelka-Munk layer compositing so washes glow and glazes mix like real paint. Its field is a `WatercolorField` (made with `watercolor(...)` rather than `simField`), whose palette maps onto the mark's color channels, with **alpha as water**: `paint.ink(0)` and `paint.water()` build brush colors, `paint.dry()` bakes the wash into a dried glaze for wet-on-dry layering, and `paint.blot()` lifts the water while the pigment stays movable (the backrun setup). Edge darkening, dry-brush, backruns, granulation, wet-in-wet flow, and glazing all come out of the simulation. The whole model has [its own page](../Simulation/Watercolor.md); see the `Simulation/Watercolor` example.

```swift
var paint: WatercolorField!
override func setup() { paint = watercolor(pigments: [.frenchUltramarine, .burntUmber]) }

override func draw() {
    withField(paint) {
        noStroke()
        if mouseIsPressed { fill(paint.ink(0)); drawCircle(mouseX, mouseY, 24) }
    }
    drawImage(paint.image, 0, 0)                         // the painting, over its paper
}
```

- `withField(field, force:) { … }` draws into the field's state (scoped like `withTarget`), and an empty block lets it evolve untouched. `force` (canvas points per frame) is the velocity a `.fluid` receives where the marks land, and the single-field sims ignore it.
- `field.modulation` attaches a layer whose brightness re-tunes the sim per texel, for sims that support one (today `.reactionDiffusion`, above). Set it once and draw into the layer each frame; attach a drawn or generated layer, not a `filtered(_:)` output (filters resolve after the sims each frame, so a filtered map would always be a frame stale).
- `field.image` is the evolved field, and `field.filtered(_:)` recolors or post-processes it like any layer.
- `scale` sets the field's internal resolution: lower it for broader reaction-diffusion features, chunkier automaton cells, and a cheaper, softer fluid.
- See `Simulation/GrayScott` (reaction-diffusion), `Simulation/GameOfLife`, `Simulation/Fluid`, and `Simulation/Watercolor`.

<a id="compose"></a>
### compose(_:) and layer(_:)

`compose { }` is the declarative form of everything above. Instead of making each off-screen layer, filtering it, and compositing it back by hand, you declare the whole stack as one block: each `layer { }` is a drawing, its `.post(...)` filters, and the `.blend(...)` mode it composites with. The intermediate layers are managed for you.

```swift
override func draw() {
    background(.black)
    compose {
        layer {                                  // beneath: a soft, blurred field
            noStroke(); fill(.indigo)
            drawCircle(width / 2, height / 2, 300)
        }
        .post(.gaussianBlur(radius: 40))
        .scale(0.5)                              // half-res: the blur hides it

        layer {                                  // on top: marks that glow…
            noStroke(); fill(.cyan)
            drawCircle(mouseX, mouseY, 60)
        }
        .post(.bloom(intensity: 1.6))
        .blend(.add)                             // …added as light
    }
}
```

It's pure sugar over the substrate: `compose` makes a [`renderTarget`](#rendertarget) for each layer, draws into it with [`withTarget`](#withtarget), chains its [`filtered`](#filtered) calls, and composites the result with [`drawImage`](#image) under its [`blendMode`](../Drawing/Drawing.md#blendMode). Anything you can do in a block, you can do by hand with those calls, and `compose` just gathers them.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/16-LayersAndEffects/BlendModes-dark.jpg">
  <img src="../../Guide/Images/16-LayersAndEffects/BlendModes.jpg" alt="Seven tiles of the same orange and blue discs overlapping on a gray ground, each composited with a different blend mode: normal, add, subtract, multiply, screen, lightest, darkest" width="680">
</picture>

The layer modifiers chain in any order:

- `.post(_:)` runs a filter over the layer before it composites. Chain calls (or pass several to `.post(_:_:)`) to stack filters: `.post(.threshold()).post(.bloom())`.
- `.blend(_:)` sets the [blend mode](../Drawing/Drawing.md#blendMode) the layer composites with (default `.normal`).
- `.scale(_:)` renders the layer at a fraction of the canvas resolution (default `1`), like [`renderTarget(scale:)`](#rendertarget), and drop it for a layer a blur or glow will soften anyway.

Notes:

- **Order is bottom-to-top.** Layers composite in the order written, so the first sits beneath the rest.
- **A layer clears to transparent.** A `layer { }` that doesn't call `background(_:)` composites only what it draws; call `background(_:)` inside to give it an opaque backdrop (it clears just that layer).
- **Call it near the top of `draw()`.** Layers composite onto whatever is already on the canvas, so draw a `background(_:)` (or a base layer) first. Like `withTarget`, an active transform carries into each layer's drawing.
- See the `Effects/Compose` example for a blurred backdrop, a bloomed ring, and a screened edge lattice.

<a id="aside"></a>
### aside(_:)

An `aside` is a helper layer drawn only to **feed** another layer's effect (a mask, a displacement map, the other half of a cross-dissolve) rather than compositing on its own. It's the [`Combine`](#combined) ops as `compose` modifiers, so a multi-input effect reads as a small graph with the compositor managing the intermediate textures rather than your threading them by hand.

Build the helper with `aside { }` (the same as `layer { }`, named for how it's used, taking the same `.post(...)` and `.scale(...)` modifiers, though its `.blend(...)` is unused since it never composites) and hand it to a layer's combine modifier:

```swift
compose {
    layer { drawImage(photo, 0, 0) }
        .masked(by: aside {                          // a soft spotlight reveal
            fill(.white); drawCircle(mouseX, mouseY, 200)
        }.post(.gaussianBlur(radius: 30)))

    layer { drawImage(scene, 0, 0) }
        .displaced(by: aside { drawImage(noise, 0, 0) }, amount: 0.04)   // ripple
}
```

The combine modifiers mirror the [`Combine`](#combined) ops:

- **`.masked(by:channel:invert:)`** keep the layer where the aside reads bright (or, with `channel: .alpha`, opaque).
- **`.displaced(by:amount:)`** push the layer's pixels around by the aside read as a vector field.
- **`.dispersed(by:amount:mode:spectral:quality:)`** pull the layer's colors apart where the aside is bright.
- **`.mixed(with:amount:)`** cross-dissolve the layer toward the aside.
- **`.cloned(from:amount:threshold:)`** drop the aside into the layer so the join disappears, the aside keeping its detail and taking the layer's color. Where the aside is opaque is where it lands.
- **`.defocused(by:focus:range:maxBlur:)`** depth of field: blur the layer by the aside read as a depth map. It takes `blades`, `irisAngle`, and `catsEye` too, so the highlights wear the shape of a real opening.

They interleave with `.post(_:)` in call order, and an aside can itself carry filters (a blurred mask edge, a softened displacement map). See the `Effects/Aside` example for a displacement map and a spotlight mask in one scene, and `Effects/Defocus` for racking focus through a depth map.

<a id="notes"></a>
### Notes

- **It's GPU-resident, by design.** Layers are Metal render targets and filter inputs are texture samples, so a layer is never copied back to the CPU. That's the difference between this and combining `createGraphics`-style buffers on the CPU, which forces a full-frame upload every frame.
- **Linear light, premultiplied.** Layers composite in the same [linear-float](../Drawing/HDR.md) space as the canvas, so blur and bloom are physically correct (blurring in linear light, not gamma). Tone-mapping and dithering still happen once, at present, so a layer holds raw linear color.
- **Layers take 2D and 3D alike.** A `withTarget` block is a full drawing surface, so 2D marks, meshes, point clouds, and GPU particles all render into it and composite back. A target a 3D scene is drawn into also captures depth, which is what [`depth`](#depth) reads.
- **Filtered layers composite on the canvas, not inside another target.** Geometry layers are filled before the frame's filters run, so a `withTarget` block that draws a *filtered* layer's `image` samples it before it exists (an empty texture). Composite filtered results on the canvas, or chain further `filtered(_:)`/`combined(_:)` calls, which resolve in order.
- **Pair bloom with `.add`.** Bloom output is self-contained (sharp image + glow). Compositing it with [`blendMode(.add)`](../Drawing/Drawing.md#blendMode) over a scene reads as added light rather than a covering layer.
- See the `Effects/Bloom` example for a blurred backdrop behind a bloomed foreground.

---

#### <sup>[Drawing](../Drawing/Drawing.md) · [HDR & tone-mapping](../Drawing/HDR.md) · [Images](../Drawing/Images.md) · [Accumulation](../Drawing/Accumulation.md)</sup>
