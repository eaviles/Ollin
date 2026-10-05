#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Path-traced export`</sup>

---

## Path-traced export

Tune the scene live, then render it offline. `--path-traced` switches the still, sequence, and video exports to an offline path tracer. Instead of rasterizing, the tracer follows light paths through the 3D scene. It spends seconds per frame on a look the live pipeline cannot reach inside a frame budget. The sketch itself does not change, so the live window stays the fast raster preview and the flag renders the finished frame.

```sh
swift run --package-path Examples Example-3D-Effects-PathTraced                                # tune live
swift run --package-path Examples Example-3D-Effects-PathTraced --export out.png --path-traced 512
swift run --package-path Examples Example-3D-Effects-PathTraced --export-video out.mp4 --seconds 4 --path-traced 256
```

The number is how many light paths each pixel traces. More samples make a smoother image, and the cost grows in proportion to the count. Check the timings before you start a long render. On an M2 at 1080x1080 the example scene takes 83 s at 512 and 157 s at 1024. At 2048 it takes 296 s, and at 4096 it takes 589 s.

If you leave the count off, it follows `--render-quality`: 64 for performance, 256 for default, and 4096 for detail. One still at the detail tier takes about ten minutes on the machine above, so it is the setting you leave running. A *sequence* pays that cost on every frame, which means days rather than hours. The video example names 256 for that reason. A mirror finish under an environment wants the high counts: `Material.polishedMetal` under an `environment` reflects one sharp path of the map per sample, so at 64 samples every bead of it is fireflies, and the detail count is what settles it.

**The detail tier is a final render, so name a count for anything else.**

`--pt-depth` is how many surfaces one path may touch, 8 unless you say otherwise. The cost is in the bounces that land on something. A ray that leaves the scene ends its path, and after the third bounce a path ends by chance in proportion to how much light it still carries. So a closed room, a mirror facing a mirror, and glass, which spends a bounce on every face it enters and leaves, use the depth in full. An open scene of opaque surfaces under an environment sees most of its paths end on their own, and there the depth is the first setting to cut. Two opaque meshes on nothing, lit by an environment, rendered at depth 2 in a little over half the time depth 8 took, with no visible difference. Glass, mirrors, and color carried between walls need the depth back.

A still's render reports progress on one line, and a sequence keeps its usual per-frame line. The mode needs a ray-tracing GPU, which every Apple-silicon Mac has. On any other machine the export prints a note and renders with the raster pipeline.

### What the traced frame adds

- **Physically soft shadows.** The tracer samples the panel's real surface. So an area light's shadow is sharp at the contact point and softens with distance.
- **Color bleeding.** A red sphere on a white floor tints the floor red, because bounced light carries color everywhere it lands. It carries that color through any number of bounces.
- **Mirror in mirror.** Every polished surface reflects the scene, including the reflections in other surfaces. Reflections continue to the full path depth (`--pt-depth`, default 8).
- **Real glass.** A `.glass(...)` material refracts the real scene. Light bends through a solid body by its index of refraction, and an `attenuationColor` tints it along the path inside. A thin pane passes the view straight through behind its reflection. Frosted glass roughens both. The shadow follows the same rule, so light reaches the floor *through* a glass object, tinted by its color. It does not stop at an opaque silhouette.
- **Emissive surfaces are lights.** A mesh with an emissive material glows and also lights its surroundings. The tracer samples glowing surfaces directly, the way it samples an area light's panel. So a neon bar throws smooth light with soft shadows, instead of waiting for bounces that happen to find it.
- **Textures travel with the light.** A traced hit reads the mesh's base-color texture at the point it hits. So a textured floor shows its picture in a mirror, keeps it through a glass sphere, and bleeds its colors onto its neighbors.
- **The surface maps travel too.** A normal map bends the traced shading the way it bends the raster shading. Its relief then shows in reflections and in bounce light. A metallic-roughness map varies the finish across the surface, and an occlusion map dims the environment's light in the crevices. An emissive map sets where a glowing mesh emits, including the light it throws on the room. A triplanar texture projects at a traced hit exactly as it does live, and so does its normal map.
- **Copies are part of the scene.** They trace like the meshes they stand for, whichever of the three forms placed them. That covers an [instanced draw](../3D/Instancing.md), a placement buffer a kernel writes, or a retained [`MeshField`](../3D/Instancing.md#meshfield). Each copy carries its own placement, its own tint, and the finish of its own draw. So a field of pebbles casts shadows, shows up in mirrors, and bleeds color the way a hand-placed pebble does. A copy costs a matrix rather than a triangle list, so a large field is cheap to trace.
- **A real lens.** `Camera3D.aperture` (a thin-lens radius in world units) and `Camera3D.focusDistance` (from the eye, along the view axis, as the canvas lens reads it) give the traced camera depth of field. The live view stays pinhole-sharp while you frame the shot, unless the sketch calls [`depthOfField()`](../3D/3D.md#depth-of-field), which blurs the raster frame through the same settings; in a traced export that call stands down, since the traced frame came through the lens already, so a sketch can leave it on for the window and export without a second blur. If you leave `focusDistance` at `nil`, the camera focuses on its `target`.

```swift
var cam = Camera3D(eye: Vector3(0, 1.5, 8), target: .zero)
cam.aperture = 0.12          // 0 (the default) is a pinhole
cam.focusDistance = 7.4      // nil focuses on `target`
camera(cam)
```

The scene needs no other change. The tracer reads the same lights, materials, environment, and camera the raster path draws, in the same units. So the traced frame shows the same picture, with the light worked out in full.

**Which lights cast shadows.** The tracer follows the light itself, so it needs no [`castShadows()`](../3D/3D.md#shadows). Every light in the frame casts a shadow, and the raster path's four-caster cap does not apply. A light can still opt out with `castsShadow: false`, and the export honors that. So the fill and rim of a [`lightingPreset(_:)`](../3D/3D.md#lights) rig cast nothing here either. In the raster path that flag also controls cost, because each caster is another pass over the scene. Here it only decides the picture, so the export matches what you framed.

### What stays raster

The tracer covers the solid 3D meshes. Everything else keeps its ordinary pipeline, and it composites with the traced layer by depth, in draw order:

- 2D drawing, before and after the 3D content.
- Wireframe meshes, the ground grid, and matcap meshes. A matcap is the unlit stylized finish, so a glowing prop drawn over an area light keeps its glow and never blocks the light's rays.
- Point clouds, strand fields, and raymarched SDF fields.
- A [`MeshField`](../3D/Instancing.md#meshfield) over its `tracedCopyBudget`. That budget keeps a huge field out of the traced scene, by the same rule the live mirrors use. Its copies still draw here, but they draw rasterized.

The contact sheets, the vector exports (SVG and PDF), and the benchmark always use the raster path.

### What the traced frame does not carry yet

- **Height, detail, and decals stay raster refinements.** A traced hit reads the flat surface at its plain uv. So a height map's parallax relief, the tiled detail pair, and projected decals apply in the raster view only. The occlusion map dims the environment's share at a hit, which is the raster path's own convention. Light carried from surface to surface is real traced transport, blocked by the actual geometry.
- **The stylized finishes trace plain.** The tracer reads a material's metallic-roughness base, its transmission, its thin film, and its emission. The sheens the raster path paints on top have no traced form yet, so a sketch tuned on one loses it in the traced frame. Per library material:
  - **Traced as drawn:** `.physicallyBased(metallic:roughness:)`, `.metal(roughness:)`, `.dielectric(roughness:)`, `.polishedMetal`, `.smoothPlastic`, `.roughPlastic`, `.glass(...)`, `.frostedGlass`, `.clearGlass`, `.gummy`, `.soapFilm(thickness:)`, `.anodized`, `.oilOnWater`, and `.nacre`. The thin film's interference colors trace, and so does a glass's dispersion.
  - **Traced as the base, without the layer:** `.carPaint(roughness:)` and `.lacquer` (no clearcoat), `.satin` and `.felt` (no sheen), `.brushedMetal` (an even polish, no streak), `.skin(radius:)` and `.marble(radius:)` (no scattering under the surface).
  - **Traced as a matte surface at its raster brightness:** the standard finishes `.matte`, `.clay`, `.rubber`, `.plastic`, `.ceramic`, `.glossy`, and `.polished` (their highlight drops), `.iridescent`, `.soapBubble`, `.oilSlick`, and `.beetle` (no rainbow sheen), `.glitter` and `.sequin` (no sparkle), `.velvet` (no rim glow), `.jade` and `.wax` (no glow through the edges), `.toon` (no bands), and `.gooch` (no warm and cool).
  A vertex color, the `fill`, `MeshMaterial.emissiveColor`, and `emissiveIntensity` (the surface glowing in its own color, `Mesh.glowing(_:)`) travel on every finish; a hit glows in the same color the raster frame shows.
- **A surface glowing in its own color is not sampled as a light either.** The light table weighs a mesh by its `emissiveColor` factor alone, so a mesh whose glow is its own color (`emissiveIntensity`, with no factor) glows at every hit and lights the scene through the paths that find it, the way a glowing copy does below.
- **A glowing copy is not sampled as a light.** The tracer aims at an emissive *mesh* as a light. An emissive *copy* glows, and its light still reaches the scene. But it arrives only through the paths that happen to find it, so it converges more slowly. The cause is the light table, which weighs each glowing triangle by its area in the world, and a copy's triangles are unplaced. For two of the three placement forms, the CPU never sees where a copy stands at all. So if a shape has to light the room, draw it with a plain `drawMesh` or use an area light.
- **Glass shadows are tinted, not focused.** Light through glass reaches a shadow as a straight, tinted pass. The bent, concentrated bright lines of a real caustic come from the live [`caustics()`](../3D/Caustics.md) feature instead.
- **Volumetric shafts stay raster features.** Height fog and aerial perspective do apply to the traced frame, along the eye's path.
- **Temporal anti-aliasing does nothing here, and motion blur still applies.** Temporal anti-aliasing refines edges by accumulating frames, and a traced pixel's edge is resolved by its own samples, so a traced frame reads the same with it on or off. Motion blur runs after the composite, from the depth the traced layer writes, so a moving camera streaks a traced frame as it streaks a raster one.

### The grain filter

The error left over in a traced render shows as grain. Sampling it away costs the square, so four times the paths halve the grain. `--denoise` filters the finished render instead, which takes a fraction of a second. The filter is off unless you ask for it, so the plain flag always renders the estimate the tracer arrived at.

The filter reads the surface separately from the light. While it traces, the tracer records the first surface each pixel hit: its own color, the direction it faces, and how far away it is. The light is then divided by that color, filtered, and multiplied back. So a texture, a painted pattern, or a silhouette is never blurred, and only the light on it is.

The filter measures its own strength instead of taking a setting. The tracer records the spread of each pixel's own samples, and the filter blends across a pixel only as far as that spread allows. So a thin render is smoothed hard and a nearly converged one only a little, and there is no per-scene dial to get wrong.

The filter also does not trade the picture for smoothness. The example scene was measured against an 8192-sample render, and the filtered frame sits closer to it than the raw frame at every count tried. At 64 samples the error falls from 17.6 to 9.1, and at 2048 it falls from 5.5 to 3.9. Counted in samples, 64 filtered samples land where about 240 raw ones would, and 2048 filtered ones land where about 4000 would. That saves five minutes of tracing on an M2.

```sh
swift run --package-path Examples Example-3D-Effects-PathTraced --export out.png --path-traced 64            # the raw estimate
swift run --package-path Examples Example-3D-Effects-PathTraced --export out.png --path-traced 64 --denoise  # filtered
```

On a sequence the filter steadies the picture rather than making it flicker. It runs on each frame by itself, but most of what separates two consecutive raw frames is grain, so filtering brings them closer together. On the example scene's moving camera at 48 samples, the difference between one frame and the next falls from 2.85 to 1.21.

Two things to know about it:

- **A real sparkle reads softer.** A rough metal catching a small bright source makes true glitter, and the filter cannot tell that from grain. When the sparkle is the subject, leave the filter off and raise the sample count.
- **One sample has nothing to measure.** `--path-traced 1` has no spread to read, so the filter does not run.

### Fewer samples where the picture has settled

Not every pixel needs the whole count. The black around a subject settles in a few samples, a sharp and evenly lit face in a few more, and only a blurred or glossy region needs them all. `--pt-noise` lets each pixel stop on its own once the grain it is left with falls under a figure, and the sample count becomes the most a pixel may trace:

```sh
swift run --package-path Examples Example-3D-Effects-PathTraced --export out.png --path-traced 512 --pt-noise 0.04
```

The figure is the standard error of the brightness a pixel shows, divided by the square root of that brightness. The square root follows the eye, which reads a step in a shadow as larger than the same step on a lit face, so one figure means about the same everywhere in the frame. At 0.01 a settled pixel's standard error is about one level in 255 at any brightness, which is a final still's figure, and one that few pixels of a real scene reach under a few hundred samples. At 0.04 it is about four levels, the grain a frame at a few hundred samples already shows, and the everyday figure; a pixel that settles there took about a quarter of the samples it would at 0.01. Above white, where a tone map compresses the picture, the figure is a share of the brightness itself.

The tracer reads the spread of each pixel's own samples, the same measurement the grain filter uses. Every pixel takes a minimum first, the square root of the count rounded up to eight (16 at 128, 64 at 4096), then the open pixels take eight more at a time and are checked between. A pixel still sampling keeps its eight neighbors sampling, so an edge or a highlight one pixel has found pulls its neighbors along. `--pt-min N` raises the minimum, which is the setting to reach for when a scene's grain is rare and bright, a small source caught by a glossy surface: a pixel's first samples can miss such a path and read as settled, and no measurement of the samples it has can count the one it has not seen yet.

What the stop buys is measured two ways, since the samples it saves are not all alike. On the example scene at 1080 by 1080, against a 2048-sample render, a cap of 512 at `--pt-noise 0.04` reached a mean of 217 samples a pixel and read 29.2 dB, where a fixed 224 read 26.7 dB: at equal samples the stop is two and a half decibels ahead, because its samples went where the grain was. In time it took 88 s against the fixed count's 104, and a fixed render given the same 88 s (432 samples) read 28.9 dB, so at equal time the stop is a quarter of a decibel ahead. The time follows the samples only loosely because the pixels that settle first are the cheap ones, the margins and the matte floor whose paths end early, while the glass, the mirror floor, and the blurred regions stay open and cost the most per sample. At 0.08 the mean was 143 for 64 s and 28.0 dB (a fixed 312 at 62 s read 27.8), and at 0.02 the mean was 306 for the full count's time and picture. On a smaller study, a floor and a sphere under one small panel at a cap of 256, 0.005 reached a mean of 140 for the error of the full count, and the same mean spent evenly erred a third more.

The saving depends on the picture. A scene that is grain from edge to edge settles only its margins: two thousand small polished beads on black, each a mirror of a studio with hot lamps in it, are a field of rare bright paths, and a pixel that catches one every few hundred samples has a spread no count under thousands brings under the figure. There the stop settles the black around the subject at any threshold, the mean says so (87 of a cap of 128), and the time does not move, since the margins were nearly free to begin with. A render like that wants the grain filter and the count, not the stop.

The frame stays a pure function of its index. The checks fall at fixed sample counts whatever the GPU's timing, and the samples are added in order, so the same command renders the same bytes and a sequence cannot flicker from the stop. The still's recipe records what the trace was given and what it spent: the count, the depth, the filter, the noise figure, the minimum, and the mean samples a pixel reached, to a tenth. A sequence records them for every frame, a video records the settings alone, and the sequence and video exports end with one line that says the mean reached over the run.

### A bound on what one bounce may carry

Some grain no count removes. On a polished scene, a bead or a floor that mirrors a studio with hot lamps in it, a pixel's samples are mostly ordinary and now and then one catches a lamp through a bounce and carries hundreds of times the light of the rest. That one sample is a bright dot, a firefly, and the pixel's spread stays enormous however many samples it takes: the stop above never settles it, and the grain filter chases dots that move from frame to frame. `--pt-clamp` bounds what any bounce may add to a sample:

```sh
swift run --package-path Examples Example-3D-Effects-PathTraced --export out.png --path-traced 256 --pt-clamp 4
```

The number is in units of white. Light that has bounced twice or more on its way to the eye, a lamp's reflection in a ball seen again on the floor, a bright wall lighting a shelf, a highlight passed from one polished bead to the next, is held to that value in its brightest channel, scaled down whole so its color holds. What one bounce shows, a lamp in a mirror, a window on a glossy floor, the lamps a surface faces, is direct light and is never touched, so a scene with nothing to bounce light between renders the same bytes under any bound. The limit applies to each contribution, not to a sample's total, so a path that carries several bounces of ordinary light keeps all of it.

It is a bias, and the frame says what it cost. The tracer sums, per pixel, the light the bound took off, and the still's recipe records the bound and the share of the frame's light it dropped (`"clamp":4,"clampDropped":0.0083`), to a hundredth of a percent; a sequence or video export ends with one line that says the mean over the run. A share of a percent or two is a cleaner picture whose brightest reflections dimmed by less than the grain they carried. Several percent is a darker one, and the bound should rise. 4 to 10 is the usual range, the higher end for a scene lit by a small sun through a mirror. With the dots gone, the spread the stop reads falls to what the pixel's ordinary samples have, so `--pt-noise` can settle such a scene where it could not before, and the two flags are made to run together. In code it is `PathTracing.maxBounceLight`.

What the bound does depends on where a scene's grain comes from, and the recipe's share is the test. On a scene of two thousand polished beads mirroring a lit studio, a bound of 4 at 128 samples took 7.5 percent of the frame's light (9.3 at 2, 5.5 at 8) and moved the picture by a tenth of a decibel against a 1024-sample render, and under `--pt-noise 0.04` the pixels settled at the same mean of 86 with or without it. That scene's grain is one-bounce light, the studio's lamps caught by each bead's glossy finish, which the bound rightly leaves alone; a share of several percent beside no change in the grain is how a render says so, and what it wants is the count, the grain filter, or a better estimator for that light, not a bound.

### A pixel's worth of a curved surface

A pixel is a bundle of rays. On a curved polished surface its footprint spans a range of normals, so the reflections it gathers fan out over a cone of directions far wider than the pixel itself. A bead a dozen pixels wide mirrors a whole room into a few hundred pixels, and each of them sees about nine degrees of it. A sample reads one direction of that cone, and where the room holds a lamp the samples that land on it carry hundreds of times the light of the rest. That is grain no count settles. It is one-bounce light, so the bound above leaves it alone.

The tracer reads the surroundings at the footprint instead. A cone travels with each path, a width and a spread angle. It starts at the pixel and widens by the pixel's angle per unit of travel. When the camera has a lens it opens to the lens, converging to the focus distance and spreading past it, so an out-of-focus surface reads a footprint the size of its circle of confusion. At every reflection it grows by twice the surface's curvature under it, read from the triangle's vertex normals. The environment is then read at the mip whose texel matches the cone, beside the sampled lobe's own footprint, which the cone also carries to the next surface. The read never goes coarser than a cell of about twenty degrees, past which a sample would stop standing for its own direction. The lights get the same treatment. The light list is shaded through a lobe widened by the spread of normals under the footprint, the specular anti-aliasing the live view runs, so a lamp's highlight on a small bead is the pixel's share of it rather than a spike one sample in a few hundred catches. The tracer's own copy of the environment weights its mip chain by latitude, since the plain chain counts the poles as if they were as wide as the equator and reads up to a tenth dark at the coarse levels a wide footprint asks for.

There is nothing to set. A flat mirror seen pinhole-sharp keeps a cone under a texel and reads the base level as it always did. A rough surface's lobe already asked for a coarse level, and a matte one is untouched. What changes is a polished surface that is small on the canvas, curved, or out of focus. The measurement is the scene that asked for it, two thousand polished beads mirroring a lit interior at 1080 by 1080. The per-sample spread over the subject fell by 71 percent. A 128-sample render moved from 18.0 to 19.3 dB against a sharp 1024-sample render, and it sits 23.7 dB from its own 1024 where the sharp pair sat 18. The mean held within two percent of the sharp render in every region, which is the sharp 128's own distance from it. The price is a bias of that order. The read averages the surroundings over the footprint before the lobe weighs them, so where the room's bright side lines up with one end of a bead's footprint the bead reads a percent or two off, and a lamp's reflection a pixel wide softens to two. The footprint is an underestimate where a surface curves one way more than the other, since the three edge curvatures are averaged. That is the side a Monte Carlo tracer wants, because the samples still average what the filter leaves. A glass surface keeps the cone through a crossing, so a lens in the scene does not widen it.

### Earlier frames carried: reuse across a sequence

A frame of a sequence is mostly last frame's light. Under a still camera and a slow sweep, almost every pixel shows the surface it showed a frame ago, lit as it was, and tracing it again from nothing throws that away. `--pt-reuse` carries the earlier frames' samples into each frame:

```sh
swift run --package-path Examples Example-3D-Effects-PathTraced --export-video out.mov --seconds 4 --path-traced 32 --pt-reuse 8
```

The number is how many frames' worth a pixel may carry, 8 when the flag stands alone. Each frame finds where every pixel was in the frame before, by the motion the sketch declared for its movers (`withMotion`, instanced copies included) or by the camera's own motion through the pixel's depth, and reads the earlier frame's samples there. Under a lens a blurred pixel's light comes from its whole circle of confusion, so such a pixel follows the movers inside that circle rather than the one under its center. Those samples join only if they belong to the same surface, at the depth this pixel expects and facing the same way, both tolerances opening where the surface itself turns or recedes fast across the pixel's neighbors. Light follows the facing rather than the surface point, so the history found at the spot must also face the pixel's way, within about two degrees plus what the pixel's own grain allows: a ball turning in place carries its surface around while its image of the room and its shading stay put, so a bead that slides carries while one that spins falls back to its own frame. What passes is trusted by spread: the carried light may sit a few standard errors from the frame's own estimate, the two spreads together, and is pulled to that distance when it sits further. So a surface a mover uncovers starts over, a reflection that moved is followed rather than smeared, and a still floor carries the whole history. Each frame traces its own stretch of every pixel's random stream, so the carried samples are new ones and not the same paths again. The carried sums add to the frame's own up to the history's worth at the count, and from then on the picture is a running mean over the last frames' worth. A sequence at 32 samples a frame with 8 frames carried shows the grain of 256, and that grain holds still from frame to frame, which is the flicker a sequence of independent frames has and this one does not.

The first frame of a run has no frame before it, so it traces the whole history's worth itself, and the sequence starts as settled as it goes on. The grain filter, when asked for, runs over the carried frame and reads its spread, so it filters less as the history deepens. The per-pixel stop and the bounce bound apply to each frame's own samples as before.

Measured on a scene of two thousand polished beads sweeping under a still camera with a lens, at 1080 by 1080 and a path depth of 4, against a 1024-sample render: 32 samples a frame with 8 frames carried took 57 s for twelve frames where 128 alone took 136, the frames sat 20.6 dB apart where 128 alone sat 19.9 and 32 alone 18.7, and each frame read 22.0 dB on the subject where 32 alone read 20.3 and 128 alone 24.1. So a sequence is steadier than one at four times the count, at under half the time, and each frame on its own sits between the two counts. The history is read between pixels every frame a surface moves, so a lamp's speck a pixel wide on a moving bead softens into its neighbors over the frames, and in a file that clips at white that reads a little brighter than the sharp render. And a blurred field of movers at different rates, the far half of a sweep under a lens, is followed by their mean motion and smears along it; where a sequence shows that, a lower count of carried frames trades some steadiness for less smear, and `--pt-reuse 4` is the figure to try first.

What it costs is that a frame is then a function of the frames before it. The same command renders the same sequence byte for byte, since every step is a pure function of what the earlier frames left. A still of one frame rendered on its own has no history and traces the history's worth itself, so it reproduces the sequence's settledness and not its bytes; the recipe says which it was (`"reuse":8`) and the mean count a pixel held once the earlier frames were carried in (`"carriedSamples":231.5`), and a sequence or video export ends with one line that says the mean over the run. What the reuse cannot know is a change of light with no change of surface that stays under the frame's own grain, a shadow's soft edge creeping a pixel a frame, which it follows a few standard errors at a time rather than at once; the count sets that grain, and a higher count follows faster. In code it is `PathTracing.reusedFrames`.

### A time budget a frame

Sometimes the hours are what is fixed. A sequence has to be done by morning, or a still has the minute you can spare, and the count a scene needs to fill that time is not known until it has been traced. `--pt-seconds` gives each frame a time in place of a count:

```sh
swift run --package-path Examples Example-3D-Effects-PathTraced --export out.png --path-traced --pt-seconds 10
swift run --package-path Examples Example-3D-Effects-PathTraced --export-video out.mov --seconds 4 --path-traced --pt-seconds 10 --pt-reuse 8
```

The number is the most seconds a frame's trace may take. The tracer runs its samples in dispatches of about a second of GPU work. Under a budget it sizes each one to the time left, from the time the last one took per sample, so a frame ends within about one sample's worth of its budget rather than one dispatch's. The count follows the scene. The example scene reaches 50 samples in ten seconds at its full path depth and 93 at a depth of 2, and a sequence whose camera moves from an open view into a closed room keeps its time a frame while its count falls. A count beside the flag is still the most a pixel traces, and a frame that reaches it stops there with time to spare. The bare flag's count under a budget is the detail tier's 4096 whatever the quality, since the clock is what decides and a final still's count is the one a fast scene may converge to first. `--pt-min N` is a floor the clock may not cut under, for a sequence that must never fall below a grain whatever a hard frame costs. The budget covers the tracing alone. The scene's setup, the grain filter, and the file add a fraction of a second to a frame.

The frame the clock leaves is a fixed render of the count it reached, byte for byte. The samples are added in order onto running sums and nothing in a sample reads the count, so stopping at 50 samples leaves exactly the frame `--path-traced 50` renders. The recipe records the budget and that count (`"seconds":10,"reachedSamples":50`), so a frame you liked reproduces from its count in place of its budget, with the depth, the threshold, the minimum, and the bound as the recipe gives them. Under `--pt-noise` the clock cuts the rounds where it falls, and the frame is the stop's own frame at that count as the cap, with the same mean in the recipe. The stop's first check falls at the square root of the cap, 64 under the bare flag's 4096, so a budget that ends a frame under that count never checks, and `--pt-min 16` brings the first check forward. A sequence or video export ends with one line that says the counts the frames reached, least to most and the mean, and the mean time a frame took against its budget. That line is the number a long render is planned from.

Under `--pt-reuse` the first frame of a run traces the whole history's worth of samples itself, so it gets the history's worth of time. Eight frames carried at ten seconds is an eighty-second first frame, and the sequence starts as settled as it goes on at the same proportional cost. A budget costs a reusing sequence its reproducibility. Each frame's count follows the clock, and a frame is a function of the frames before it, so the same command no longer renders the same sequence twice. Every frame's recipe records the count it reached, but a reusing sequence reproduces only from a fixed count.

Measured on the example scene at 1080 by 1080 on an M2, from launch to file. A fixed 128 samples took 29.5 s. `--pt-seconds 10` traced 50 samples in 9.9 s and took 10.7 s in all, the scene's setup and the write being the rest, and `--path-traced 50` then rendered the same bytes. The same ten seconds at `--pt-depth 2` reached 93 samples. Under `--pt-noise 0.04` they reached the same 50 with no pixel settled, the first check being at 64. A sequence of three frames at `--pt-seconds 5 --pt-reuse 4` traced 101 samples in its first frame, in twenty seconds, and 25 in each frame after, in five. It ended with the line that says so:

```
Ollin: path tracing reached 25 to 101 samples a pixel (a mean of 50.3) in a mean of 10.0 s a frame, under a budget of 5 s
```

### Determinism and the programmatic surface

Sampling is a pure function of the pixel, the sample index, and the bounce. The filter is a pure function of what the sampling left behind. So the same command renders the same bytes, and a video export cannot flicker. Under `--pt-reuse` a frame is a pure function of the frames before it as well, so a sequence is still the same bytes twice while a frame of it rendered alone is not. Under `--pt-seconds` the count follows the clock, so a frame is the same bytes as a fixed render of the count its recipe records rather than of the same command twice. You can also set the mode in code, with the same options the flag carries:

```swift
OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 512, maxDepth: 8, denoises: true)  // the flag's `--denoise`
try OllinApp.export(sketch, to: "out.png", frame: 120)
OllinApp.pathTracedExport = nil
```

`noiseThreshold` is the flag's `--pt-noise` and `minSamplesPerPixel` its `--pt-min`; `nil`, the default, is the square root of the count:

```swift
OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 512, noiseThreshold: 0.01, minSamplesPerPixel: 32)
```

`maxBounceLight` is the flag's `--pt-clamp`, and 0, the default, is no bound:

```swift
OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 256, noiseThreshold: 0.04, maxBounceLight: 4)
```

`reusedFrames` is the flag's `--pt-reuse`, and 0, the default, carries nothing; it takes effect across the frames of one `exportSequence` or `exportVideo` run:

```swift
OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 32, reusedFrames: 8)
try OllinApp.exportSequence(sketch, to: "frames", frames: 240, fps: 60)
OllinApp.pathTracedExport = nil
```

`secondsPerFrame` is the flag's `--pt-seconds`, and 0, the default, is no budget; `samplesPerPixel` stays the most a pixel traces:

```swift
OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 4096, secondsPerFrame: 10)
```

### See also

- [`Export`](./Export.md) for the full set of export flags this mode builds on.
- [`3D`](../3D/README.md) for the camera, lights, materials, and environments the tracer reads.
