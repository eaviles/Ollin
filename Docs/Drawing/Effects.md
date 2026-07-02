#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Effects`</sup>

---

## Layered effects

Draw into **off-screen layers**, run GPU **filters** over them (blur, bloom), and **composite** the results back onto the canvas with blend modes. It's how you build glow, soft backdrops, depth-of-field haze, and post-processing looks, following the OPENRNDR `compose`/`Filter` model on Ollin's Metal core.

Everything stays on the GPU. A layer is a Metal texture you draw into and then sample; a filter reads one texture and writes another; compositing is an ordinary [`drawImage`](../Drawing/Images.md) with a [`blendMode`](../Drawing/Drawing.md#blendmode). Nothing is ever read back to the CPU between steps, so the slow path other tools fall into (copying a layer back to combine it) never happens here.

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
- [combined / Combine](#combined) - combine two layers (mask, displace, mix, defocus, ambient occlusion, screen-space reflections)
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

Make an off-screen layer to draw into. The no-argument form is full-canvas size; pass `scale` to render the layer at a fraction of that resolution.

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

Redirect everything drawn in the closure into `target` instead of the canvas. Scoped exactly like [`withState { }`](../Drawing/Drawing.md#withstate): the current drawing state and transform carry in, and drawing returns to the canvas when it ends.

```swift
let layer = renderTarget()
withTarget(layer) {
    background(.clear)                  // clear THIS layer (transparent here)
    fill(.white); noStroke()
    drawCircle(width / 2, height / 2, 120)
}
// back to drawing on the canvas
```

Call [`background(_:)`](../Drawing/Drawing.md#background) inside the block to clear the layer. Inside a `withTarget` it clears *that layer* (its fill color and its geometry so far), leaving the canvas untouched. A layer starts transparent, so an unwritten or partly-written layer composites as nothing where you didn't draw.

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

The work runs on the GPU during the frame's render; `filtered` just records it.

<a id="filter"></a>
### Filter

Filters are value descriptors built with static factories. They composite in
[linear light](../Drawing/HDR.md), so grades and blends are physically correct. Each family
has a contact-sheet example: `Effects/ColorFilters`, `Effects/BlurFilters`,
`Effects/StylizeFilters`, `Effects/RetroFilters`, and `Effects/Distortion`
(`Effects/Glitter` shows the iridescence + glitter pair on shapes). The catalog:

#### Blur & glow

- **`.gaussianBlur(radius:)`** a Gaussian blur; `radius` is the extent in pixels (larger is softer). Backed by a hardware Gaussian kernel.
- **`.bloom(threshold:intensity:radius:)`** glow: pixels brighter than `threshold` bleed light into their surroundings. The bright parts are extracted, blurred by `radius`, and added back at `intensity`, so the result is the original **plus** its glow, ready to composite (often additively). Brightness is the **max color channel** (HSV "value"), not luminance, so a vivid full-brightness mark blooms the same whatever its hue. `threshold` runs `0…1` over the linear-light frame, so HDR highlights (values above 1, from additive light) bloom hardest.
- **`.bilateral(radius:sigma:)`** edge-preserving smoothing: blur flat areas while keeping edges sharp (the cartoon / denoise base). `sigma` is how different a neighbour's color may be before it stops blending. Smaller keeps more edges.
- **`.motionBlur(angle:distance:)`** directional smear along `angle`, `distance` a fraction of the layer: the streak of a moving subject.
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
- **`.solarize(_:softness:)`** invert the tones above a brightness with a soft fold: the part-positive, part-negative darkroom (Sabattier) look.
- **`.temperature(amount:tint:)`** white balance: `amount` warms (>0) or cools (<0), `tint` pushes toward magenta (>0) or green (<0).
- **`.vibrance(amount:)`** smart saturation that lifts the muted colors most and the vivid ones least (so it punches a flat image without blowing already-saturated tones).
- **`.colorama(cycles:shift:)`** cycle the hue wheel `cycles` times across luminance, turning a gradient into rainbow bands; `shift` spins the wheel.
- **`.lumaKey(low:high:invert:)`** make the image transparent outside a brightness band, so a dark or light backdrop drops out: a luminance key.

```swift
layer.filtered(.colorGrade(contrast: 1.3, saturation: 1.6, hue: 0.05))
layer.filtered(.gradientMap(.turbo))
layer.filtered(.levels(blackPoint: 0.08, whitePoint: 0.92, gamma: 1.4))
layer.filtered(.vibrance(amount: 0.6))
```

#### Stylize & optical

- **`.edges(intensity:)`** Sobel edge magnitude, bright edges on black; a quick ink/outline pass.
- **`.sharpen(amount:)`** unsharp mask, emphasizing local detail.
- **`.vignette(amount:radius:softness:)`** darken toward the corners (aspect-correct, so circular).
- **`.chromaticAberration(amount:)`** split the red and blue channels radially, like cheap-lens fringing.
- **`.halftone(scale:angle:)`** a rotated dot screen, dot size tracking brightness.
- **`.dither(levels:)`** ordered (Bayer 4×4) dithering, the retro look that fakes more shades than it has.
- **`.grain(amount:seed:)`** film grain; feed `seed` your `time` or `frameCount` for grain that moves.
- **`.pixelate(size:channel:tint:)`** mosaic into blocks `size` canvas-pixels across; `channel` can read one channel out as gray and `tint` recolor it.
- **`.lineScreen(scale:softness:angle:foreground:background:)`** a brightness-driven line screen: each cell paints a centered bar whose width tracks its brightness, painted `foreground` over `background`.
- **`.emboss(amount:angle:)`** light the luminance slope along `angle` as a gray relief, like stamped metal.
- **`.oilPaint(radius:)`** the Kuwahara region filter: flatten detail into oil-paint patches while keeping edges crisp. `radius` is the brush size in pixels (bigger is broader and costlier).
- **`.crosshatch(scale:foreground:background:)`** pencil shading: layered diagonal strokes that thicken as the image darkens.
- **`.toon(levels:edges:)`** cel shading: flatten into `levels` brightness bands and ink the Sobel edges over them.
- **`.median()`** a 3×3 median, knocking out speckle and stray pixels while keeping edges sharp.
- **`.contour(levels:intensity:)`** dark iso-brightness lines (one every `1/levels` of the range), turning tone into a topographic map.
- **`.cmykHalftone(scale:)`** separate into cyan/magenta/yellow/black and screen each as rotated dots at the classic print angles: the colour-process look.
- **`.normalMap(strength:)`** read the image as a height field and output its surface normal as an RGB vector (the bluish bump-map look), ready to feed `.displace` (see [combine](#combined)) or a lighting pass.
- **`.iridescence(amount:scale:bands:shift:)`** wash the content with the flowing rainbow sheen of a soap film or oil slick. The colors come from thin-film interference (each channel cycling at its own wavelength, so the bands run through the film color order), swirled across the content by a noise field and following its shading. `amount` blends the sheen over the original, `scale` sets how fine the swirl is, `bands` how many color cycles the film runs through, and `shift` slides the colors: feed it your `time` for a sheen that flows.
- **`.glitter(density:amount:size:saturation:phase:)`** scatter twinkling sparkle flecks across the content: a dense dust of small glints plus occasional bright cross-flare flashes, landing only where something is drawn. `density` is the fleck grid resolution (cells across the layer), `amount` the brightness (flashes run past 1.0 in linear light, so a following `.bloom` makes them glow), `size` scales the flecks, `saturation` tints them from white (0) toward each fleck's own color (1), and `phase` drives the twinkle: feed it your `time` so it sparkles.

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
- **`.glitch(amount:seed:)`** tear random blocks of rows sideways and split their channels; feed `seed` your `time`/`frameCount` so it flickers.
- **`.crt(curvature:scanline:aberration:)`** the full old-monitor look in one pass: barrel curvature, scanlines, a corner vignette, and a touch of aberration.

```swift
layer.filtered(.scanlines(count: 240))
layer.filtered(.crt())
postProcess(.glitch(amount: 0.3, seed: time * 8))
```

#### Distortion

These warp the image's *coordinates*: they re-sample the source at a remapped position, so color passes through untouched. Center-relative warps stay round on a non-square layer.

- **`.kaleidoscope(segments:angle:)`** fold into mirrored wedges around the center, rotated by `angle`.
- **`.swirl(angle:radius:)`** twirl into a vortex: rotation strongest at the center, fading to none at `radius`.
- **`.bulge(amount:radius:)`** a radial lens: `amount` > 0 bulges (fisheye), < 0 pinches; it eases back to the image at `radius`.
- **`.wave(amplitude:frequency:phase:vertical:)`** ripple rows side to side (or columns up and down); animate `phase` for motion.
- **`.ripple(amplitude:frequency:phase:)`** concentric waves from the center, like a drop in water.
- **`.mirror(vertical:flip:)`** reflect one half of the image onto the other.
- **`.polar(amount:)`** bend around the center by remapping between Cartesian and polar coordinates: a tunnel / fold.
- **`.tile(count:mirror:)`** repeat the image in a `count`×`count` grid; `mirror` flips alternate cells for a seamless tiling.
- **`.perturb(amount:scale:phase:)`** warp by the image's own internal fbm noise (no map needed), for a smoky / heat-haze ripple.

```swift
layer.filtered(.kaleidoscope(segments: 8))
layer.filtered(.swirl(angle: 3, radius: 0.6))
postProcess(.ripple(amplitude: 0.02, frequency: 12, phase: time * 3))
```

Filters chain, so an effect reads as one expression:

```swift
layer.filtered(.threshold(0.5)).filtered(.gaussianBlur(radius: 3)).filtered(.gradientMap(.magma))
```

<a id="combined"></a>
### combined(with:_:) and Combine

A [`Filter`](#filter) reads one layer; a `Combine` reads **two**: a base layer and an auxiliary layer that modulates it, which is what masking, displacement, and cross-dissolve need. `base.combined(with: aux, op)` runs the op on the GPU and hands back a new layer, itself filterable and combinable, so multi-input effects chain like single-input ones.

A `Combine` is a value descriptor like `Filter`, but the aux layer rides alongside it (a value descriptor can't hold a `RenderTarget`), passed as the `with:` argument. The ops:

- **`.mask(channel:invert:)`** keep the base where the aux reads **bright** (`channel: .luminance`, the default; draw the mask in white over transparent) or **opaque** (`channel: .alpha`), fading to transparent elsewhere; `invert` flips it. A spotlight reveal, a vignette, a clip to a shape.
- **`.displace(amount:)`** offset the base's pixels by the aux read as a **vector field**: red → horizontal, green → vertical, mid-gray = no shift, up to `amount` of the layer. Feed it noise or a gradient for ripples, smearing, heat-haze, and refraction.
- **`.mix(amount:)`** cross-dissolve the base toward the aux by `amount` (0 = base, 1 = aux); the transition workhorse.
- **`.defocus(focus:range:maxBlur:quality:)`** depth of field: blur the base by the aux read as a **depth map** (its luminance is the depth, 0 near … 1 far). The band `focus ± range` stays sharp; the blur grows with distance from it up to `maxBlur` pixels. It's a circle-of-confusion bokeh gather with near/far separation. The depth map can be a smooth gradient (a tilt-shift plane), a real depth feed, or hard-edged discrete per-object depths: overlapping defocused regions blend like real bokeh, a defocused foreground spreads over and covers an in-focus subject behind it, and a sharp subject occludes the blur behind it with a crisp edge. `quality` is a `RenderQuality` tier (`.default`/`.performance`/`.detail`, hardware-relative) setting the bokeh sample count. More taps trade frame rate for creamier, structure-free blur (`maxBlur` is the blur *amount*; `quality` is the blur *smoothness*).
- **`.ambientOcclusion(radius:intensity:bias:quality:)`** ambient occlusion: darken the base in crevices, gaps, and where surfaces meet, reading the aux as a **depth map**. View-space position and surface normal are reconstructed from the depth (no separate normal buffer), then occlusion is estimated with a hemisphere of samples oriented to the normal (a dense low-discrepancy kernel, so it stays stable without per-pixel jitter, smoothed with a depth-aware blur) and multiplied into the base. Feed it a 3D scene's own [`depth`](#depth): that layer carries the camera's near/far and field of view, so `radius` reads in **world units**. `intensity` scales the darkening, `bias` rejects self-occlusion (raise it if flat faces speckle, lower it if contacts look weak), and `quality` is the sample-count tier. As a post-process it darkens the final image, not just the ambient term: the standard screen-space trade, dialed with `intensity`.
- **`.screenSpaceReflections(intensity:maxDistance:thickness:roughness:fresnel:edgeFade:quality:)`** screen-space reflections: make the scene reflect off its own surfaces (a glossy floor, wet asphalt, a polished tabletop), reading the aux as a **depth map**. Each pixel's reflection ray is built from the view-space position and surface normal, marched through the depth buffer until it meets the scene, and the colour there is composited back over the surface. Feed it a 3D scene's own [`depth`](#depth): the layer carries the camera scale, so `maxDistance` reads in **world units**. `intensity` is the reflection strength, `thickness` is how close a ray must pass a surface to hit it (a fraction of the surface's distance, so it scales with the scene; too large smears a reflection into a "cylinder"), `roughness` blurs it for a glossy (rather than mirror) finish, `fresnel` strengthens it at grazing angles, `edgeFade` fades a reflection as its ray nears the frame border, and `quality` is the ray-march step tier. It reflects only what's already on screen: off-screen and hidden geometry can't appear (rays fade out as they reach the frame edge). Like all screen-space reflection, it's at its best on broad surfaces with well-separated reflected objects; very dense or near-grazing scenes can show faint artifacts where reflected surfaces graze the ray. A touch of `roughness` softens those, and the `Examples/3D/ScreenSpaceReflections` sketch shows a clean composition. Reflections are accumulated across frames so they hold steady as the camera moves, and the march runs at a resolution the `quality` tier sets (full on export). One limit is worth understanding plainly: this effect makes a mirror out of the *finished picture*, and a picture doesn't contain the back of anything. Wherever the true reflection is of a surface the camera can't see (the underside of a ball resting on the floor, the hidden face of a box), the effect can only approximate, which shows as a soft, imperfect zone at object-floor contacts. For exact mirrors of real geometry, including hidden and off-screen surfaces, use [`rayTracedReflections()`](../3D/3D.md#ray-traced-reflections) on a ray-tracing GPU; [Combining 3D features](../3D/Combining.md) compares the two side by side.

```swift
let scene = renderTarget()
withTarget(scene) { background(.black); fill(.orange); drawCircle(width / 2, height / 2, 300) }

let mask = renderTarget()
withTarget(mask) { fill(.white); drawCircle(mouseX, mouseY, 200) }   // white = visible

drawImage(scene.combined(with: mask.filtered(.gaussianBlur(radius: 12)), .mask()).image, 0, 0)
```

The base and aux can render at different `scale`s; the aux is sampled by normalized coordinates. In a `compose { }` block, the same ops read as `aside` modifiers ([below](#aside)). The `Effects/Aside` example shows a displacement map and a spotlight mask in one scene.

<a id="depth"></a>
### depth: a 3D scene's depth as a layer

The depth map `.defocus` reads can be one you draw by hand, but when the scene **is** 3D its depth comes for free. Draw a 3D scene into a render target, and because meshes (or point clouds) land in it the target captures depth, exposed as `target.depth`: a gray layer (0 near … 1 far) the renderer fills from the scene's own depth buffer. Feed it straight to `.defocus` as the aux and a real 3D render racks focus like a lens, no hand-drawn depth map needed. The same layer feeds `.ambientOcclusion` and `.screenSpaceReflections`, and because it carries the camera's near/far and field of view, their world-unit parameters (`radius`, `maxDistance`) read in the scene's own scale.

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

`scene.depth` maps over the camera's `near`/`far`, so **set them to bracket your scene**: tight planes both make the focal plane sweep usefully and give the depth buffer its best precision. It's a normal layer otherwise: draw it (`drawImage(scene.depth.image, 0, 0)`) to see the depth, or filter it. Depth capture costs nothing on a 2D target (no 3D drawn means no depth buffer), and the extra normalize pass runs only when you actually read `.depth`. The `3D/SceneDefocus` example racks focus through a row of orbs by their own depth.

<a id="generate"></a>
### generate(_:) and Generator

A `Generator` is a procedural pattern filled from math alone, no input layer. Where a
`Filter` transforms a layer you drew, a `Generator` **is** a layer: a source you composite,
filter, or feed into another effect. `generate(_:)` realizes one into a `RenderTarget`,
itself drawable and filterable, so a pattern flows straight into the rest of the chain.
The `Effects/Patterns` example shows all four and a composed mix.

```swift
let stripes = generate(.bars(scale: 24, foreground: .black, background: .white))
drawImage(stripes.filtered(.gaussianBlur(radius: 4)).image, 0, 0)

// A LYGIA-style mix: noise → colormap, with a grid multiplied over it.
let field = generate(.noise(scale: 5)).filtered(.gradientMap(.turbo))
drawImage(field.image, 0, 0)
blendMode(.multiply)
drawImage(generate(.gridLines(scale: 20, weight: 0.08)).image, 0, 0)
```

The patterns (cells stay square whatever the layer's aspect ratio):

- **`.checkers(scale:foreground:background:)`** a two-color board, `scale` cells across.
- **`.gridLines(scale:weight:foreground:background:)`** a line grid, each line `weight` (0…1) of a cell wide.
- **`.bars(scale:vertical:foreground:background:)`** parallel stripes, `scale` across, on either axis.
- **`.noise(scale:sharpness:foreground:background:)`** fractal value noise, from a soft cloud (`sharpness` 0) to a hard two-tone split (1).

<a id="postprocess"></a>
### postProcess(_:)

Apply a filter to the **whole finished frame**, just before it's shown: the quick way to bloom or blur everything without managing a layer:

```swift
override func draw() {
    background(.black)
    // …draw a bright scene…
    postProcess(.bloom(threshold: 0.7, intensity: 1.2))   // glow the whole frame
}
```

Call it in `draw()`; multiple calls chain in order.

<a id="feedback"></a>
### feedback(scale:) and withFeedback(_:_:)

A `Feedback` layer **remembers itself across frames**. Each frame you read last frame's content, transform it (fade, zoom, rotate, offset), and draw new content on top; the result becomes next frame's content. That read-transform-write loop is what makes trails, tunnels, and the video-feedback look of a camera pointed at its own screen.

It's distinct from the [accumulation surface](../Drawing/Accumulation.md) (`noClear`), which piles new draws onto an *unchanging* canvas. Feedback hands you the previous frame as an **image you can transform** before drawing it back, and that transform step is the whole effect.

Unlike `renderTarget()` (a per-frame handle), a `Feedback` is **persistent**: make it once in `setup()` and hold it. Its identity is what ties this frame's write to last frame's read, so make a fresh one each `draw()` and it never builds up.

```swift
var trail: Feedback!

override func setup() { trail = feedback() }      // make once, store it

override func draw() {
    background(.black)                            // clears the canvas (resets the frame)
    withFeedback(trail) { prev in                 // prev = last frame's content
        translate(width / 2, height / 2)          // spin + shrink the old frame
        rotate(0.06); scale(0.98)                 //   about the canvas centre
        translate(-width / 2, -height / 2)
        tint(Color(white: 1, alpha: 0.94))        // gentle decay so trails fade
        drawImage(prev, 0, 0)
        noTint()
        fill(.white); drawCircle(mouseX, mouseY, 12)   // a fresh mark on top
    }
    drawImage(trail.image, 0, 0)                  // composite the result to the canvas
}
```

- `withFeedback(_:_:)` hands the previous frame in as the closure parameter. The `withTarget(feedback) { … }` form works too: read last frame by name with `feedback.previous` inside.
- `feedback.previous` is last frame's content; `feedback.image` is this frame's, for compositing.
- Call `background(_:)` **before** the block. On the canvas it resets the whole frame, so calling it after would wipe the layer's geometry (like any other `withTarget` layer). Inside the block, `background(_:)` clears just the feedback layer.
- See the `Effects/Feedback` example for a spiralling tunnel.

<a id="simfield"></a>
### simField(_:) and Sim

Where a [`Filter`](#filter) transforms an image once, a `Sim` runs a **stateful simulation** on a persistent layer that evolves every frame by reading its own neighbourhood: reaction-diffusion patterns spreading, cellular-automaton cells living and dying, a fluid carrying colour. You don't write the kernel: pick a `Sim` from the catalog, make a `SimField` with it, and **draw into the field to seed or force it**.

A `SimField` is **persistent** like `Feedback` (make it once in `setup()` and hold it). Each frame the marks you draw in `withField` land on the field's current state, the renderer steps the simulation, and the result is the field's `image`. The raw state is *data*, so recolor it through the same `Filter` catalog as everything else.

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

- **`.reactionDiffusion(feed:kill:)`** Gray-Scott reaction-diffusion: two chemicals diffuse and react into coral, spots, stripes, and dividing cells. Draw light marks to inject chemical B (it spreads from there); `feed`/`kill` pick the regime. State is A in red, B in green. Recolor with `.gradientMap`/`.threshold`.
- **`.gameOfLife()`** Conway's Game of Life (B3/S23). Draw white to make cells alive, black to kill them. Use a low field `scale` so each texel is a visible cell. The `image` is crisp black-and-white.
- **`.fluid(curl:velocityDissipation:densityDissipation:pressureIterations:buoyancy:)`** a real-time fluid: an incompressible flow that carries colour. The mark's *colour* injects dye; `withField`'s `force:` pushes the flow where the mark lands, so dragging (or an animated force) swirls the colour. `curl` is the swirliness, the dissipations how fast flow and dye fade, and `buoyancy` an optional upward lift on bright dye (smoke that rises on its own). The `image` is the dye; composite or `.filtered(.bloom)` it directly.

```swift
var fluid: SimField!
override func setup() { fluid = simField(.fluid(curl: 30), scale: 0.5) }

override func draw() {
    let push = Vector2(cos(time), sin(time)) * 4         // an animated push (or a mouse delta)
    withField(fluid, force: push) {                      // colour -> dye, motion -> velocity
        noStroke(); fill(Color(hue: time * 0.08, saturation: 0.9, brightness: 1))
        drawCircle(width / 2, height / 2, 16)
    }
    drawImage(fluid.filtered(.bloom()).image, 0, 0)      // the swirling dye, bloomed
}
```

- `withField(field, force:) { … }` draws into the field's state (scoped like `withTarget`); leave the block empty to let it evolve untouched. `force` (canvas points per frame) is the velocity a `.fluid` receives where the marks land; the single-field sims ignore it.
- `field.image` is the evolved field; `field.filtered(_:)` recolors or post-processes it like any layer.
- `scale` sets the field's internal resolution: lower it for broader reaction-diffusion features, chunkier automaton cells, and a cheaper, softer fluid.
- See `Simulation/GrayScott` (reaction-diffusion), `Simulation/GameOfLife`, and `Simulation/Fluid`.

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

It's pure sugar over the substrate: `compose` makes a [`renderTarget`](#rendertarget) for each layer, draws into it with [`withTarget`](#withtarget), chains its [`filtered`](#filtered) calls, and composites the result with [`drawImage`](#image) under its [`blendMode`](../Drawing/Drawing.md#blendmode). Anything you can do in a block, you can do by hand with those calls; `compose` just gathers them.

The layer modifiers chain in any order:

- `.post(_:)` runs a filter over the layer before it composites. Chain calls (or pass several to `.post(_:_:)`) to stack filters: `.post(.threshold()).post(.bloom())`.
- `.blend(_:)` sets the [blend mode](../Drawing/Drawing.md#blendmode) the layer composites with (default `.normal`).
- `.scale(_:)` renders the layer at a fraction of the canvas resolution (default `1`), like [`renderTarget(scale:)`](#rendertarget); drop it for a layer a blur or glow will soften anyway.

Notes:

- **Order is bottom-to-top.** Layers composite in the order written: the first sits beneath the rest.
- **A layer clears to transparent.** A `layer { }` that doesn't call `background(_:)` composites only what it draws; call `background(_:)` inside to give it an opaque backdrop (it clears just that layer).
- **Call it near the top of `draw()`.** Layers composite onto whatever is already on the canvas, so draw a `background(_:)` (or a base layer) first. Like `withTarget`, an active transform carries into each layer's drawing.
- See the `Effects/Compose` example for a blurred backdrop, a bloomed ring, and a screened edge lattice.

<a id="aside"></a>
### aside(_:)

An `aside` is a helper layer drawn only to **feed** another layer's effect (a mask, a displacement map, the other half of a cross-dissolve) rather than compositing on its own. It's the [`Combine`](#combined) ops as `compose` modifiers, so a multi-input effect reads as a small graph with the compositor managing the intermediate textures rather than your threading them by hand.

Build the helper with `aside { }` (the same as `layer { }`, named for how it's used; it takes the same `.post(...)` and `.scale(...)` modifiers, but its `.blend(...)` is unused since it never composites) and hand it to a layer's combine modifier:

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
- **`.mixed(with:amount:)`** cross-dissolve the layer toward the aside.
- **`.defocused(by:focus:range:maxBlur:)`** depth of field: blur the layer by the aside read as a depth map.

They interleave with `.post(_:)` in call order, and an aside can itself carry filters (a blurred mask edge, a softened displacement map). See the `Effects/Aside` example for a displacement map and a spotlight mask in one scene, and `Effects/Defocus` for racking focus through a depth map.

<a id="notes"></a>
### Notes

- **It's GPU-resident, by design.** Layers are Metal render targets and filter inputs are texture samples, so a layer is never copied back to the CPU. That's the difference between this and combining `createGraphics`-style buffers on the CPU, which forces a full-frame upload every frame.
- **Linear light, premultiplied.** Layers composite in the same [linear-float](../Drawing/HDR.md) space as the canvas, so blur and bloom are physically correct (blurring in linear light, not gamma). Tone-mapping and dithering still happen once, at present, so a layer holds raw linear color.
- **2D layers.** A `withTarget` block is a 2D drawing surface; 3D geometry (meshes, point clouds, depth scenes) and GPU particles inside one aren't composited in Phase 1.
- **Pair bloom with `.add`.** Bloom output is self-contained (sharp image + glow). Compositing it with [`blendMode(.add)`](../Drawing/Drawing.md#blendmode) over a scene reads as added light rather than a covering layer.
- See the `Effects/Bloom` example for a blurred backdrop behind a bloomed foreground.

---

#### <sup>[Drawing](../Drawing/Drawing.md) · [HDR & tone-mapping](../Drawing/HDR.md) · [Images](../Drawing/Images.md) · [Accumulation](../Drawing/Accumulation.md)</sup>
