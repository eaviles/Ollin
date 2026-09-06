#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → Web page</sup>

---

## A sketch as a web page

`--export-web` records what a sketch draws over a duration and writes a page that plays the recording back in a browser. It works like a video export. The sketch runs on the Mac, and the page is a file you can put anywhere. The page draws with the framework's own shaders, translated from Metal to GLSL. Those are the shape shader, the stroke and fill pipelines, and the fragment behind every effect the sketch used. So a frame on the page matches the frame the Mac would have shown, to within the few levels measured in [strokes and fills on the page](#strokes-and-fills-on-the-page) and the sections after it.

```sh
swift run --package-path Examples Example-Web-BreathingRing --export-web ring.html
```

The sketch's source stays in Swift. The page holds only a canvas, the shaders, and the recorded track, so it carries no source and no editor.

### Contents

- [Recording a page](#recording-a-page) - the flag, its length, `OllinApp.web` / `exportWeb`
- [What crosses](#what-crosses) - the analytic shapes, strokes and fills, text, the composed and raymarched fields, the layered effects, and what stops the export
- [Strokes and fills on the page](#strokes-and-fills-on-the-page) - the vertices the Mac would have drawn, and a fill's edge through the same four samples
- [Pictures and text on the page](#pictures-and-text-on-the-page) - a picture once, as its file or its pixels; atlas text over the font's page; a gradient from the strip
- [Fields on the page](#fields-on-the-page) - a composed field's program on the same machine; a raymarched field through its camera and lights
- [Layers and shaders on the page](#layers-and-shaders-on-the-page) - the pass graph beside the shapes, the framework's fragments rewritten, a shader of yours live
- [The two forms](#the-two-forms) - one self-contained file, or a fragment for a page of your own
- [Playing back](#playing-back) - the handle on the canvas, interpolation, loops, reduced motion
- [Motion that stays live](#motion-that-stays-live) - a parameter driven by a formula crosses as the formula
- [Parameters as controls](#parameters-as-controls) - a parameter the page can carry becomes a control under the canvas, and a handle for your own page
- [What the page weighs](#what-the-page-weighs) - what is worked out, what is fitted, what streams
- [The weight limit](#the-weight-limit) - the 25 MB a page may weigh, what the refusal says, and the flag past it

---

### Recording a page

The exporter runs the sketch frame by frame at a fixed rate, as the video export does. At each frame it records what the renderer received. Nothing is rendered on the Mac during the recording, so the page holds nothing specific to a GPU.

```sh
swift run --package-path Examples Example-Basic-HelloCircle --export-web hello.html --seconds 6
swift run --package-path Examples Example-Basic-HelloCircle --export-web hello.html --frames 90 --fps 15
swift run OllinLive MySketches/Ring.swift --export-web ring.html --inline
```

| Flag | Meaning |
|---|---|
| `--frames N` or `--seconds S` | how long to record. With neither, a sketch that declares `loopDuration` records exactly one lap, which the page wraps without a seam. |
| `--fps F` | the recorded frames per second of the sketch's own time, 30 by default. The page interpolates between them, so a slow, smooth motion records well at 10 or 15. |
| `--skip S` | run the sketch for `S` seconds before the first recorded frame. |
| `--inline` | write the fragment for a page of your own instead of a whole file (see [the two forms](#the-two-forms)). |
| `--no-controls` | leave the parameters at their recorded values: no probe, no panel, and no handle onto them (see [parameters as controls](#parameters-as-controls)). |
| `--max-page-size MB` | the most the page may weigh, 25 MB by default; `0` lifts the limit (see [the weight limit](#the-weight-limit)). |

`--seed`, `--param`, `--replay`, and `--automation` apply here as on every export. In code, `OllinApp.web(of:frames:fps:skipSeconds:form:controls:maxBytes:)` returns the page as a string, and `OllinApp.exportWeb(_:to:frames:fps:skipSeconds:form:controls:maxBytes:)` writes it to a file and reports the size.

### What crosses

The page carries the closed analytic shapes: `drawCircle`, `drawEllipse`, `drawRect`, `drawArc`, `drawTriangle`, `drawPolygon` by count, `drawStar`, `drawRing`, `drawPoint` and the markers, and the rest of the [shape catalog](../Drawing/Drawing.md). Each shape crosses with its fill, its stroke, the stroke's weight and alignment, a hollow band, and the transform it was drawn under. Symmetry folds cross as the copies they make. Every stroke crosses too: `drawLine`, `drawPolyline`, `drawBezier`, `drawCurve`, a `drawShape` outline, and an elliptical or full-turn `drawArc`. A stroke keeps its weight, its joins, its caps, a gradient along it, and a width that varies. Every fill the triangle path tessellates crosses as well: `drawPolygon` from points, `drawShape` with its holes, `drawCurve` closed, and text in the default outline mode.

Text through the glyph atlas (`textMode(.atlas)`) crosses as its glyph quads over the font's page. A gradient on an analytic shape crosses with its ramp, whether linear, radial, or along the path. The page reads the ramp from the same strip the Mac bakes it into. A picture drawn with `drawImage` crosses too. That covers a file you loaded and a picture painted or edited in memory. It also covers a picture a transform made, and the color glyph in a line of text. A picture travels once, however many frames draw it. The page draws it under its `tint`, its `blendMode`, a crop, and the transform it was drawn under. When it is drawn small, the page reads it from its smaller levels.

A composed field drawn with `drawSDF` crosses as its program. The program holds every leaf, melt, carve, joint, modifier, and domain transform of [the field catalog](../Drawing/Combinators.md). It carries the current fill or the leaves' own colors, a gradient fill or stroke by field position, and the stroke along the merged outline. A raymarched field drawn with `drawSDF3D` crosses too, with the camera it was seen through and the lights that lit it. The lights are directional, point, and spot lights, plus the ambient and the self-shadow of `castShadows()` toward the key. The four shading models cross with their finishes: the specular, a subsurface bleed, the iridescent sheen, the sparkle, and the rim. A gradient fill by screen position crosses. A `raymarchResolution` below one is traced at the same fraction the Mac traces at.

A `blendMode` applies to shapes, strokes, fills, text, pictures, and fields with the same factors the Mac's pipelines use. A `Batch` recorded from any of those replays under its draw-time transform. `background` is each frame's clear, and a sketch that accumulates (`noClear`) plays back frame on frame. The tone map and the exposure cross too, and the present pass on the page dithers and encodes as the Mac's does.

The page carries the [layered effects](../Drawing/Effects.md) too, and it runs their shaders live. A layer drawn with `withTarget` crosses as a surface of its own, at its own resolution when it was made with a `scale`. It comes back onto the canvas or into another layer as the quad that `drawImage(layer.image)` drew, under its `blendMode` and `tint`. Every `Generator` crosses. So does every `Filter` and `Combine` that is one shader pass on the Mac. Those are the color and tone grades, the stylize and optical set, the distortions, and the design filters that read the picture. They also include `.mask`, `.displace`, `.mix`, `.paintMix`, `.disperse`, and the line integral convolution. The lookup filters `.gradientMap` and `.fieldMap` cross with their strips. `.gaussianBlur` and `.bloom` cross as passes of the page's own, a separable Gaussian measured against the Mac's kernel. A user [`Shader`](../Shaders/Shaders.md) crosses as a generator, a filter, or a combine. The same rewriter carries its `shade(uv, info)` to GLSL. The shader runs on the page's own clock and pointer, so `info.time` and `info.mouse` stay live. A compiled [`Visual`](../Shaders/Visuals.md) chain is a user shader, so it crosses the same way. `postProcess` filters run after the canvas, as they do on the Mac. A `Feedback` layer and a single-field `SimField` keep their state on the page and step there. That covers reaction-diffusion, Life, Lenia, the ripples, the cellular automata, the sandpile, and the falling sand. Because they keep state, a track that holds one of these plays every frame in order from the first.

Anything else stops the export before a file is written. The message names the call and the frame where it was met:

```
Ollin: --export-web stopped: withClip does not cross to the web page yet (met at frame 2); export the sketch as video instead (--export-video).
```

A picture that is a live texture stops the export. That is a camera frame, a video frame, a compute texture, or a layer the frame did not fill. So do clipping, `depth(at:)`, compute work, and wide-gamut or HDR output. The rest of 3D stops it too: a mesh, a point cloud, or a field drawn inside a layer. Around a raymarched field, the export stops on what the page's lighting does not carry. That is an environment, fog and aerial perspective, an area light, and a light with a profile or a cookie. It is also contact shadows, global illumination, ray-traced reflections, the scene through glass, and caustics. A finish that is transmissive, clear-coated, sheened, thin-film, brushed, or scattering stops it as well. Among the effects, the export stops on the passes that the Mac runs as a solver, or as a chain of passes at several sizes. Those are `.diffuse`, `.distanceField`, `.boxBlur`, `.adaptiveThreshold`, `.fourier`, `.softProof`, `.liquidMetal`, `.heatmap`, `.gemSmoke`, `.seamlessClone`, `.defocus`, `.ambientOcclusion`, `.light`, and `.screenSpaceReflections`. It also stops on the simulations with a pipeline of their own: `.fluid`, `.watercolor`, `.selfWarp`, and `.multiScaleTuring`. A sketch that draws any of those is a video export today. The [roadmap](../../ROADMAP.md#new-output-surfaces) lists the work those calls wait on.

### Strokes and fills on the page

On the Mac, a stroke is expanded into bands of triangles, and an anti-aliasing coverage travels with each vertex. A polygon, a shape with holes, or a glyph outline is triangulated the same way. The recorder writes those vertices down as they are, seven numbers each: the position, the coverage, and the color with its alpha. The page draws them with the two fragments the Mac uses, translated to GLSL. A fill's color is linearized, and its edge is left to the rasterizer. A stroke's coverage is remapped to perceptual alpha, so a thin dark line reads as dark on the page as it does on the Mac.

A fill's edge has no analytic coverage of its own. So a page that draws one rasterizes every drawn surface through a four-sample multisampled buffer, as the Mac does, and resolves it afterwards. The sample pattern is fixed in the GPU's own texture space, so a mirrored picture would land on that pattern mirrored too. The page therefore rasterizes the canvas upright in that space. Measured against the Mac, a polygon's edge then agrees to within a level or two. A canvas that accumulates keeps its samples from frame to frame.

### Pictures and text on the page

A picture travels once, however many frames draw it. A file the sketch loaded travels as the file itself when a browser can read the format (PNG, JPEG, GIF, WebP). A photo then weighs on the page what it weighs on disk. Any other picture travels as a PNG of the pixels the Mac's texture was built from. That covers a picture painted in memory, edited through the pixel subscript, or made by a transform. It also covers one read from a format a browser does not open. A picture whose pixels change between frames travels once per version, and two images with the same pixels travel once. The browser decodes each picture as it is, with no color conversion and no orientation applied. The picture lands in an sRGB texture with its smaller levels, as the Mac holds it. So a picture drawn small reads the same level on both. A JPEG is the one picture that is decoded twice: by ImageIO on the Mac and by the browser on the page. The two decoders can differ by a few levels along a sharp color edge.

Text through the glyph atlas draws each glyph as a quad over the font's distance-field page. The recorder writes down the quads. When the recording ends, it writes down the atlas rows up to the last glyph packed, as an 8-bit PNG. By then every glyph the frames drew is on it. The fragment on the web page is the Mac's, translated to GLSL. It turns the sampled distance into coverage through its screen-space derivative and remaps that coverage to perceptual alpha. Then it applies the alpha to the fill the quad's corners carry, so a gradient fill on atlas text crosses too. A font whose page filled up and was rebuilt during the recording stops the export, because the earlier quads would address glyphs that moved. A page of body text in one or two fonts stays inside that limit.

A gradient on an analytic shape travels with the shape's record as its ramp's row in a strip. The strip holds one row of 256 texels for each distinct ramp in the recording, baked on the Mac in the ramp's own color space. The page reads the strip with the same lookup the Mac's fragment makes. The strip weighs a kilobyte per ramp.

### Fields on the page

On the Mac, a composed field is a small program. Its leaves, combines, modifiers, and transform scopes are flattened in evaluation order, and a stack machine in the fragment walks them per pixel. The recorder writes the program down as it is, four rows of four numbers per instruction. It stores the covering quad's record beside the program, with the program's place in the frame. The page walks the program with the same machine, written for GLSL over the framework's own arithmetic. The distance functions, the joint ops, the combine switch, and the point transforms are the Metal source translated to GLSL. The program sits in a uniform block, one field at a time, with 256 instructions at most, which is the framework's own cap. The merged outline's coverage and the paints then resolve as the Mac's fragment resolves them. So a melt's seam and a stroke along it read the same. Symmetry copies and a replayed recording share one program.

A raymarched field crosses the same way, and its scene crosses with it. Each frame that marches one carries a scene block, whole and exact. The block holds the camera's view, projection, and inverse, the march budget, the ambient, and the eye. It also holds up to eight lights with their kinds and cones, and the one caster the field shadows itself toward. The block travels apart from the shape records, because a camera matrix quantized inside its range would move a silhouette. The page's fragment rebuilds each pixel's world ray through the inverse view-projection. Then it sphere-traces the field's program with the same step scale and the same pixel-cone coverage at the silhouette. It takes the tetrahedron normal and marches the analytic self-shadow toward the caster. Then it shades the hit through the punctual half of the mesh lighting, translated for the page. That half is the four shading models under directional, point, and spot lights, with the wrap term and the cone. It also includes the subsurface bleed, the iridescent sheen in both of its modes, the sparkle, and the rim. A physically based finish takes its specular energy from the same split-sum table the Mac bakes. That table is baked once for the page and carried as an asset when a field wears such a finish. The hit's depth is written as the fragment's own depth. So two fields occlude each other through a depth buffer on the page, as they do on the Mac. The march budget follows the export's. `.default` lifts to `.detail`, and an explicit tier or step count holds. A `raymarchResolution` below one traces into a smaller target at the coverage-adaptive fraction the Mac would use. Then it upsamples once, with bilinear color and point-sampled depth.

In the 200-pixel test cases, measured against the Mac, every field is within a mean of 0.15 levels. No pixel is more than 32 levels off. A melt with a carve, a morph, a gradient, a stroke, and a tiling reads at 0.006. A turntable blob reads at 0.13. Jade under a spot light and a point light reads at 0.06, a self-shadowing plane at 0.04, and a half-resolution march at 0.09. Three finishes, a metal, a toon, and a Gooch, read at 0.06. Over the framework's own examples, all five Combinators sketches cross, and so do twelve of the seventeen Raymarching sketches. They cross at means of 0.05 to 0.15, with no pixel far off. Each of those pages is 220 to 306 KB. The five that stop are the ones that draw a mesh beside the field, or an environment.

### Layers and shaders on the page

Each frame, the recorder writes down the graph the renderer received, beside the shape records. The graph holds the layers in the order the Mac fills them, and it records what each layer was filled from. A layer may be drawn into, generated, filtered from another, or combined from two. It may also be run by a shader of yours, or carried over by a feedback layer or a field. The graph also holds what the canvas drew and the whole-frame filters. A filter's numbers travel as parameter rows, the way a shape's do. So a generator's `phase` that is fed `time` fits to its sines on a lap. Otherwise it is sampled. A graph that stays the same from frame to frame travels once.

The page's shaders are the framework's own. The fragment behind each filter, generator, combine, and simulation step is cut out of the Metal source with every helper it reaches. It is translated to GLSL ES 3.00 and then compiled by the browser. Only the fragments the recording runs are on the page. A shader of yours is translated the same way, and the `ShaderInfo` and the `sample` readers the framework gives it are translated for the page. A layer on the page is a half-float texture in linear light, like the Mac's, and it is sampled the same way.

The clock a shader reads on the page is the track's own. So a shader that moves on `info.time` moves on the page at the recorded rate. A shader that reads `info.mouse` follows the pointer over the canvas. What Swift computed each frame and handed to a shader, such as a filter's angle or a `Shader`'s `params`, is a recorded column.

### The two forms

The standalone form is one self-contained HTML file. You can open it, host it, or put it in an `iframe`. It centers the canvas, colors the page around it with the sketch's own background color, and scales the canvas to fit.

The inline form (`--inline`) is the same canvas and the same script block with no page around them, for a page you already have:

```html
<canvas class="ollin-sketch" width="1080" height="1080" role="img" aria-label="..."></canvas>
<script>
...
</script>
```

Paste the two elements together wherever the picture belongs, and style the canvas as you would any other. The script finds the canvas just ahead of it, so several pictures can share one page. The canvas's `aria-label` is the [description the sketch gives of itself](../Helpers/Accessibility.md), or else its name.

The framework's own site is a page of that kind. The ring it opens on is `Examples/Web/BreathingRing` in this form, pasted into the front page with its ink and paper set through the handle to the page's colors (see [the site](../Tools/Reference.md#in-a-browser)).

### Playing back

The page starts playing on load and wraps at the end of the track. A sketch that declared `loopDuration` and recorded one lap wraps without a seam. Any other track wraps with whatever jump its first and last frames make. When every frame draws the same set of shapes, which is the ordinary animation, the page interpolates between the recorded frames. The motion then stays smooth at any refresh rate and at any recorded rate. When the set changes from frame to frame, the page steps from one frame to the next.

A reader whose system asks for less motion (`prefers-reduced-motion`) sees the first frame, held still. A hidden tab pauses, and it resumes from where it stopped when it is shown again.

The script leaves a handle on the canvas as `canvas.ollin`, and `window.ollin` points to the last one on the page:

| Member | What it does |
|---|---|
| `play()`, `pause()` | run or hold the track |
| `seek(seconds)` | show the picture at a time on the sketch's clock |
| `showFrame(i)` | show one recorded frame exactly, with no interpolation |
| `frames`, `rate`, `duration`, `loops` | what was recorded |
| `playing`, `time` | where it is |
| `ready` | a promise that resolves once every picture and atlas page is decoded, when the first frame draws (the canvas shows the sketch's paper until then) |
| `params` | the parameters the page offers as controls, each with its kind and the parts it takes (see [parameters as controls](#parameters-as-controls)) |
| `get(name)`, `set(name, value)` | read or move a parameter, or one part of it (`set('ink.red', 0.5)`) |
| `reset()` | every parameter back to its recorded value |

The page needs WebGL2, which every current browser has. It composites in linear light like the Mac, in a half-float intermediate where the browser can render to one. The present pass encodes to the canvas with the same dither.

### Motion that stays live

A parameter driven by a [formula](../Helpers/Formula.md) crosses as the formula, not as its values:

```swift
@Param(0 ... 300) var radius = 100.0

override func setup() {
    drive($radius, "150 + sin(time * tau / 6) * 40")
}

override func draw() {
    background(.white)
    noFill()
    stroke(.black)
    drawCircle(width / 2, height / 2, radius)
}
```

The recorder keeps the formula's value at every frame beside the shapes. A shape column that turns out to be a straight function of the formula is wired to the formula instead of being stored. The radius here is one such column, and so is a position that adds an offset to it. The page carries the formula as JavaScript and works those columns out every frame from its own clock and pointer. So `time`, `frame`, `width`, `height`, `mouseX`, and `mouseY` mean the same on the page as in the sketch. A formula that reads the pointer follows it live. The parameter's range and step apply on the page as they do on the Mac. A formula that reads another driven parameter is evaluated after that one, as on the Mac. A formula that reads a noise field stays a recorded value, because the page has no copy of the field.

A column the sketch computes in Swift from the parameter in some other way (squared, say) is not wired. It travels as [the weight section](#what-the-page-weighs) describes.

### Parameters as controls

A sketch's `@Param`s cross as controls. When the recording is done, the exporter probes each one. It makes a fresh sketch and sets the parameter to a few other values inside its range. Then it records the same frames again and looks at every number that moved. A number that moves along a line in the parameter at every frame is wired. Its slope per frame is kept the way a moving column is kept. That is one number when the slope never changes. When the track is a lap, it is the sines of the lap. Otherwise it is a sample per frame. A parameter whose every effect wires is offered on the page. The standalone page lays the controls out under the canvas, grouped as the sketch grouped them. A number gets a slider, and an integer gets a stepper. A switch gets a checkbox, a color gets a well, and a point or a pair of ends gets a field per part. Moving a control moves the picture the way the Mac would have drawn it at that setting. That is measured against `--param` at the same values.

```swift
@Param(0 ... 200) var radius = 60.0
@Param var ink: Color = .black
@Param var paper: Color = .white

override func draw() {
    background(paper)
    noFill()
    stroke(ink)
    drawCircle(width / 2, height / 2, radius)
}
```

Here the radius wires directly to the circle. The ink reaches the stroke's color unchanged, and the paper reaches the frame's clear through its linear-light value, which the probe finds on its own. A shader's `params` and a filter's numbers are columns like any other, so a parameter a shader reads is a control too. A parameter that a [formula](#motion-that-stays-live) reads as a constant moves the formula's result live.

What the probe cannot wire stays at its recorded value, and the exporter names it and says why. A count of shapes, or a switch that adds one, changes what is drawn, so it cannot wire. A radius the sketch squares moves a number some other way than along a line. Two parameters multiplied together move the picture only in combination. The probe catches that case by moving every wired parameter at once. Then it checks that the picture moved by the sum of what each did alone. A menu, a piece of text, and a swatch strip have no control on the page. A parameter a formula drives is left out, and so is one that nothing reads. So is every parameter of a sketch that draws differently on each run. A parameter may empty the picture at one end of its range, as a radius of zero does. The probe fits it just short of that end, and the page still offers it.

The inline form never draws a panel, because the page around it owns the layout. It carries the same parameters through the handle, so a page can set the sketch's colors to its own theme.

```js
canvas.ollin.set('paper', '#111111');
canvas.ollin.set('ink', { red: 1, green: 1, blue: 1, alpha: 0.8 });
canvas.ollin.set('radius', 140);
```

`--no-controls` leaves the parameters at their recorded values and skips the probe. The probe records the sketch once more per setting, with three settings per part. So a sketch with many parameters takes a few times as long to export as it took to record.

### What the page weighs

Each shape is 30 numbers per frame, and four things keep that small. A frame whose shapes are the previous frame's is stored once, so a still costs one frame however long it is recorded. When the set of shapes is stable, the columns that never change are stored once as the base, in float32. Those columns are colors, a fixed transform, and a stroke weight. Only the moving columns travel. A moving column wired to a formula travels as nothing at all. A moving column of a lap (a track recorded from `loopDuration`) is fitted to the sines it is made of. The ordinary looping sketch writes its motion as sines with whole cycle counts per lap. Such a motion fits exactly in as many terms as it has sines. The page evaluates those terms at any time, so the motion between the recorded frames is the true one rather than a straight line. A column that fits none of those forms travels as 16-bit samples. Each sample is within one part in 65,535 of its column's range, and the page interpolates between frames. A sampled column's range and its index travel as binary beside its samples, twelve bytes per column.

A stroke or a fill weighs its vertices, seven numbers each. A stroke's bands run to a few dozen vertices per segment, so a dense line drawing is where a page gets heavy. The vertices of a still, or of what never moves in a drawing, travel once: each position exact, the coverage and color as 16-bit samples. Only the vertices that move travel as columns, fitted or sampled like a shape's. This was measured on the sixty-one pattern examples that draw strokes and fills. A third of the pages are under 1 MB, and the median is about 3 MB. A dense line drawing runs to hundreds of megabytes over six seconds. A tiling of 152,000 vertices whose every vertex moves is 398 MB. A guilloche of 3.4 million vertices weighs 78 MB before its second frame. A page that heavy is refused, and the refusal says what made it heavy (see [the weight limit](#the-weight-limit)).

A picture weighs its file, or its PNG, once, as base64 in the page, which is a third more than the raw bytes. An atlas page weighs its packed rows as an 8-bit PNG. The body text in the `Text/TextVolume` example carries its whole atlas page in 9 KB. A gradient weighs its row, a kilobyte. A picture whose pixels change every frame weighs one PNG per version, which is what makes a sketch that repaints its picture each frame heavy. This was measured on the twenty-nine text and image examples. The pages run from 157 KB to 11 MB with a median under 1 MB, and every one matches the Mac.

A control weighs its slopes, packed like a moving column, plus the page's controls code. The ring's two colors add four kilobytes.

When it finishes, the exporter prints a report. It gives the file size, what stayed live, what fitted, what sampled, and the fullest frame's vertex count. It lists the pictures and atlas pages the page carries and the parameters live as controls. It also lists the parameters left at their recorded values, with the reason for each. Measured on the ring of twenty-eight circles the site opens on, its sixty-second lap fits whole, with every moving column fitted to a few sines. That page is 83 KB whether it was recorded at 10 fps or at 30, and most of that is the shaders and the player. The breathing circle for six seconds at 30 fps is not a lap, so it samples its radius, and its page is 75 KB. The effects examples run 98 to 165 KB for the same reason. A page carries only the fragments its frames run, and a filter's numbers add a few floats per frame. The rate still matters for a track that samples. The page interpolates, so a slow motion looks the same recorded at 10 fps as at 60 and weighs a sixth as much. A host serves the page compressed, and the page's encoding is chosen so that it compresses well.

### The weight limit

A page may weigh 25 MB. That is about the largest file a static host will serve when you put a page on one. It is also about what a phone opens in a few seconds. Past that limit, nothing is written. The exporter says what the page would have weighed and which part of it is heaviest. It says whether that part is stored for every recorded frame or travels once. If it is stored for every frame, a lower `--fps` or a shorter `--seconds` would take most of it away. If it travels once, those flags would not help. The exporter points at the video export, and it names the `--max-page-size` that writes the page anyway:

```
Ollin: --export-web stopped: the page would weigh 398.4 MB, past the 25 MB allowed; 398.3 MB of it is stroke and fill vertices (152346 vertices in the fullest frame, 180 frames), stored for every recorded frame: record fewer frames (--fps 10, or a shorter --seconds), or export the sketch as video instead (--export-video); --max-page-size 400 writes the page anyway.
```

The parts are the shapes and passes, the stroke and fill vertices, the scenes of raymarched fields, and the controls. The remaining parts are the pictures, the atlas pages, and the shaders and the player. A picture counts as per-frame when the recording holds about one per frame, which is what a repainted picture costs. `--max-page-size 100` allows 100 MB, and `--max-page-size 0` lifts the limit. In code, `maxBytes:` on `OllinApp.web(of:)` and `exportWeb` does the same. Past the limit, they throw a `WebWeightRefusal` that carries the numbers.

A drawing that is dense enough is refused before the recording is done. As the frames come in, the exporter keeps a lower bound on what the page can weigh, from what it has seen so far. The first frame's vertices travel once whatever else happens. A picture travels. When the set of shapes changes, the exporter stores every frame that differs from the one before. On a recording that is not a lap and drives nothing by formula, a column that has moved once is sampled. It is then stored as a sample in every frame from then on. The moment that bound passes the limit, the recording stops, and the message names the frame it stopped at:

```
Ollin: --export-web stopped: the page would weigh at least 34.2 MB (by frame 2 of 180), past the 25 MB allowed; 34.2 MB of it is stroke and fill vertices (537600 vertices in the fullest frame, 1074078 columns moving), stored for every recorded frame: record fewer frames (--fps 10, or a shorter --seconds), or export the sketch as video instead (--export-video); --max-page-size 0 lifts the limit and writes the page anyway.
```

A lap, or a sketch with a formula on a parameter, is different. It may fit or carry its moving columns for much less than a sample per frame. In that case those columns are left out of the bound, and the page is weighed once it is assembled. Either way, the weight is worked out from the parts before the page's text exists, so a refusal never builds the page.

Measured on the six heaviest pattern examples at six seconds and 30 fps, each one was refused in under a second:

| Example | Refused | The page, at least | Vertices a frame | A frame as SVG |
|---|---|---|---|---|
| `Patterns/Penrose` (every vertex moves) | frame 5 | 27 MB (398 MB whole) | 152,000 | 149 KB |
| `Patterns/Roses` (every vertex moves) | frame 2 | 34 MB (521 MB whole) | 538,000 | 181 KB |
| `Patterns/Spirograph` (every vertex moves) | frame 2 | 68 MB | 1,064,000 | 361 KB |
| `Patterns/Kleinian` (still) | frame 1 | 74 MB | 3,219,000 | 1.2 MB |
| `Patterns/Guilloche` (still) | frame 1 | 78 MB | 3,387,000 | 1.2 MB |
| `Patterns/ParametricLSystem` (still) | frame 1 | 223 MB | 9,760,000 | 12.5 MB |

The last column measures the change that would bring these pages under the limit. That change is to store a stroke as the points and the style the sketch gave. The page would then expand it, rather than the Mac. Vertices weigh 15 to 70 times what the points do. The [design notes](../../DESIGN-NOTES.md#new-output-surfaces) say what that option would cost.
