# Changelog

Notable changes to Ollin, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Version numbers follow semantic versioning at major zero: a breaking change or a new feature bumps the minor, and a fix bumps the patch. Each release names its breaking renames here, so pin `.upToNextMinor` and read the entry before you move up. From 0.7.0 on an entry is a title and a line or two: what changed and the call to type. The page it links has the rest.

## [Unreleased]

### Added

- **A recording of the phone's stream.** Press Record in the capture app, with no cable, and play the folder back with `PhoneDevice(playing: PhoneRecording(path:))`. It plays on the sketch's clock, so an export shows the same frames every time. Changing mode during a recording asks first. Rebuild the capture app to get the button. [Phone](Docs/3D/Phone.md#a-recording)
- **Drawing on a real surface.** `withPlane(wall)` draws in a wall's own meters. `painted(with: view)` makes a mesh carry the camera picture's pixels, so a piece of the wall can lift off. `occluding { }` lets a real surface hide a drawn thing. `Plane3` is the surface as a value. [Surfaces](Docs/3D/Surfaces.md)
- **A point pinned from a click, and a layer on four of them.** `unproject(_:onto:)` turns a click into a point that stays on a wall. `drawImage(_:topLeft:topRight:bottomRight:bottomLeft:)` lays an image or a layer on four points of space. The `PhoneWallTiles` and `PhonePoster` examples use both. [Surfaces](Docs/3D/Surfaces.md#pinned-points)
- **The phone's camera as a 3D camera.** `device.latestCamera` says where the camera stood and what its lens was, in every ARKit mode. `drawPhonePicture(_:)` and `camera(_:)` put a sketch in the room the phone saw. [Phone](Docs/3D/Phone.md#the-cameras-place-and-lens)
- **A chain that learns a picture.** `MarkovGrid` learns small pictures, written as rows of any value, and writes new grids with the same local habits: `nextRows(_:columns:)` for a whole field, `nextRow(columns:)` for a strip without end. `order` sets how many cells around a place it reads. The `Patterns/MarkovGrid` example writes a town, a maze, and a wall. [MarkovGrid](Docs/Generators/MarkovGrid.md)
- **A second visit to John Whitney.** Two more homages join `Permutations`. `Arabesque` is a ring of 360 points all moving right at whole-number rates, stopping at each fifth of its cycle to turn over. `Matrix` is twenty-four squares at whole-number rates on a path that is never drawn. Both loop exactly. [John Whitney](Examples/Recreations/JohnWhitney/)

### Changed

- **`cameraRay(through:)` returns a `Ray3`.** It returned a tuple, `(origin:direction:)`. `.origin` and `.direction` read as before, so only a destructuring `let (o, d) =` needs rewriting. It also answers under a camera built from a real lens (`Camera3D.intrinsic(_:)`), where it returned `nil`. [Depth compositing](Docs/3D/DepthCompositing.md#cameraRay)
- **A filter's sizes are canvas pixels at any layer scale.** A blur, an outline, a shadow's offset, and every other size mean canvas pixels on a layer made with `makeRenderTarget(scale:)` or `.scaled(_:)`. At 0.5 a filter spreads half as far as it did: divide a size by the scale to keep an old look. [Effects](Docs/Drawing/Effects.md#rendertarget)
- **A one-pixel filter reaches a canvas pixel.** On a scaled layer `.edges`, `.sharpen`, `.emboss`, `.median`, `.toon`, `.normalMap`, and `.schlieren` step by a canvas pixel, so a slope is as steep and an edge carries the same ink at any scale. `.antialias`, `.grain`, and `.jpeg` still work on the layer's own pixels. [Effects](Docs/Drawing/Effects.md#rendertarget)
- **A measured field and the patterns read canvas pixels too.** On a scaled layer `.distanceField` reports its distances, and takes `maxDistance`, in canvas pixels. So do the sizes of `.defocus`, `.light`, the `.anaglyph` combine, `.rust`, `.verdigris`, `.terrazzo`, `.scratches`, and the pulsing border's margins. [Effects](Docs/Drawing/Effects.md#rendertarget)
- **Tone filters take grays as written.** `threshold`, `levels`, `solarize`, and `lumaKey` read a level as the gray a sketch writes: `threshold(0.5)` cuts at `Color(white: 0.5)`, where it cut at 0.735. To keep an old cut, pass the level through `Color.linearToSrgb(_:)`. A bare `lumaKey()` now drops only what is nearly black. [Effects](Docs/Drawing/Effects.md#color--tone)
- **A negative, a posterize, and a contrast work on written grays.** `invert` turns `Color(white: 0.25)` into `Color(white: 0.75)`, `posterize` spaces its steps evenly as seen, and `colorGrade(contrast:)` spreads grays about `Color(white: 0.5)`. For the old negative or contrast, use `channelMixer`, which works on stored light. `levels` no longer cuts a highlight past white down to white. [Effects](Docs/Drawing/Effects.md#color--tone)
- **A map is read as its colors were written.** `.displace` and the `.vector` field of `.lineIntegralConvolution` take `Color(white: 0.5)` as no shift, where it used to move the layer. The map's alpha weights the push, so a map can be marks on a clear layer. A map drawn over `Color(white: 0.735)` goes back to 0.5. [Effects](Docs/Drawing/Effects.md#combined)
- **A mask and an angle field read grays as written.** A `.mask` of `Color(white: 0.5)` keeps half the layer, where it kept 21%, and `.angle(turns:)` reads `Color(white: 0.25)` as a quarter of its turns. White, black, and a soft white mark mask as before. To keep an old share, write the gray as `Color(white: Color.srgbToLinear(g))`. [Effects](Docs/Drawing/Effects.md#combined)
- **`.normalMap` writes the usual normal-map color.** A flat area is `Color(red: 0.5, green: 0.5, blue: 1)`, a deeper blue than before, and the result feeds `.displace` and the `.vector` field as it did. A shader of your own that reads its red and green now reads them through `linearToSrgb`. [Effects](Docs/Drawing/Effects.md#filter)
- **The Guide's Chapter 34 is two chapters.** *Traced light* keeps the mirrors, the bounce, the caustic, and the camera's effects. The new Chapter 35, [The lens and the slow render](Guide/35-TheLensAndTheSlowRender.md), teaches depth of field and the path-traced export. Chapters 35 to 46 are now 36 to 47.
- **A heavy 3D field draws in several passes.** A `drawSDF3D` field with many nodes, under a shadow, is divided into as many as sixteen lighter draws and shown as one, so no single draw asks the GPU for all of it. 126 capsules under `castShadows()` draw at 1080 by 1920 in about 5 s on an M2. [Combinators](Docs/Drawing/Combinators.md#notes)
- **A field of many parts reads the near ones.** A 3D field of a dozen parts or more steps past the parts far from each point it reads, and its value is exactly what it was. The 126-capsule field above draws in half the time. Nothing changes in a sketch. [Combinators](Docs/Drawing/Combinators.md#notes)

### Fixed

- **The camera takes over after the first Allow.** On a Mac never asked for its camera, a sketch made with `Camera.orStill` showed its picture and kept it after Allow, until a relaunch. The picture now stands in only while the prompt is up, a refusal says why in the terminal, and an export never asks. [Vision](Docs/Vision/Vision.md#nocamera)
- **A salience query reads the right place.** On macOS 27, `salience(at:in:)` on a `SaliencyTracker` or a `Saliency` answered from the wrong part of the heat map, so a marker steered by it sat beside the glow. The query now reads the map the picture is drawn from. [Vision](Docs/Vision/Vision.md#saliencytracker)
- **Traced shadows on an M1 or M2 are fast again.** A point light's or a rect or disk panel's traced shadow drew about thirteen times slower than it should: every such frame also carried the traced reflection code, used or not. A frame with no traced reflections now leaves it out, and draws the same picture. [3D](Docs/3D/3D.md#shadows)
- **The capture app, held sideways.** With the phone turned sideways, the Record button and the Wand and Touch pads were off the screen. They now sit on the right, and the modes and status rows scroll on the left. Upright is unchanged. Rebuild the capture app to get it. [Phone](Docs/3D/Phone.md#a-recording)
- **A still sketch keeps up with what you save.** Under `OllinLive`, a `noLoop()` sketch redraws once when an asset it loads changes, and a saved shader or asset shows while the timeline holds the clock. Scrubbing the timeline no longer leaves a still sketch redrawing. [Timeline](Docs/Tools/Timeline.md#the-transport)
- **A screen saver's still sketch stays still.** The system stops and starts a saver more than once, and the second start set a `noLoop()` sketch redrawing at full rate for good. Starting now gives back only what stopping took. Rebuild the saver to get it. [Screen saver](Docs/Output/ScreenSaver.md)
- **A take of a still sketch replays.** `--replay` on a sketch that calls `noLoop()` stopped on its first frame until Space was pressed twice. The replay now draws every frame the take holds and stops at its end. [Replay](Docs/Core/Replay.md#replaying-in-the-window)
- **A night off and the Mac's sleep hold against everything.** A piece shut by its `schedule`, or held for sleep, could be set drawing again by a `redraw()`, a `loop()`, a reload, or the wake arriving first. Each now waits until the reason that holds the loop lets go. [Installation](Docs/Output/Installation.md#keeping-hours)
- **A camera mode entered from Selfie.** Switching from Selfie to another camera mode could leave that mode's camera delivering nothing, and a recording made there ended on an error. Leaving Selfie now waits for the front camera to stop. The Record row also shows its whole sentence. Rebuild the capture app. [Phone](Docs/3D/Phone.md#a-recording)

## [0.18.0] - 2026-11-14

This release adds a pen and lines drawn by hand, soft bodies that touch what is around them, a layer a sketch can read back, and a sketch that floats over the desktop. Small dots and thin lines now lay exactly their own ink, and lit 3D that traces nothing is about ten times faster on an M1 or M2. A few looks and defaults moved, so read **Changed** before you update.

### Added

**Drawing**

- **A pen.** `strokeMedium(.ink(feather:pooling:amount:speed:seed:))` draws ink from a nib. It feathers into the paper where the hand slows, pools at each end, skips when the pen hurries, and darkens where strokes cross. A recorded mark keeps each point's pace in `StrokeMark.Sample.speed`. [Marks](Docs/Drawing/Marks.md#ink)
- **Lines drawn by hand.** `handDrawn(wobble:bow:overshoot:seed:)` on a `Contour`, a `Shape`, or a `StrokeMark` returns the same line with a hand's wobble, bow, and uneven ends. It is seeded, so a line that moves keeps its character. [Marks](Docs/Drawing/Marks.md#hand-drawn)
- **A layer read back.** `RenderTarget.snapshot()` returns a layer's pixels as an `Image`, one frame late. Anything that reads a picture can now read what the sketch draws. [Effects](Docs/Drawing/Effects.md#snapshot)
- **A slit scan on the GPU.** `makeLayerHistory(capacity:)` keeps a layer's last frames, and `Filter.slitScan(_:delay:)` builds each pixel from the frame its delay names. [Effects](Docs/Drawing/Effects.md#layerhistory)
- **A glyph mosaic of a layer.** `drawGlyphMosaic` and `glyphMosaic(of:)` take a layer's `image`, so a moving drawing can be set as text. [Glyph mosaic](Docs/Drawing/GlyphMosaic.md)
- **An accumulator in single precision.** `makeAccumulator(precision: .float32)` keeps the very faint marks a half-float pass drops, at twice the memory. [Accumulation](Docs/Drawing/Accumulation.md#accumulator)

**3D**

- **A camera for each layer.** A camera set inside a layer's `withTarget` block belongs to that layer, so one frame can show a 3D world from several places. [3D](Docs/3D/3D.md#layer-camera)
- **Finishes keep their look in a path-traced export.** `--path-traced` now draws the stylized finishes as the window does: `.toon`, `.gooch`, `.iridescent`, `.glitter`, `.jade`, `.velvet`, `.hologram`, and the standard highlights. The clearcoat, the fabric sheen, the brushed streak, and scattering under the surface still trace as their base. [Path-traced export](Docs/Output/PathTraced.md#where-a-look-is-drawn)
- **Maps show in a traced reflection.** With `rayTracedReflections()` on, a mirror shows a surface's normal, roughness, and occlusion maps, and a fine picture seen small in a mirror no longer shimmers. [3D](Docs/3D/3D.md#ray-traced-reflections)
- **Light that bounces inside a volume.** `Medium.bounce`, from 0 to 1, lets a thick cloud glow from inside and shine through at its thin edges. [Volumes](Docs/3D/Volumes.md#light-and-shadow)
- **Fog veils volumes.** Under `fog` or `aerialPerspective`, a volume is fogged like the solids around it. [Volumes](Docs/3D/Volumes.md#light-and-shadow)
- **A flat field stood up.** `extruded(depth:)` turns any 2D `SDF` composition into an `SDF3D` slab that joins other 3D fields, casts shadows, and voxelizes. [Combinators](Docs/Drawing/Combinators.md#a-flat-field-as-a-slab)
- **Gesture marks in space.** `GestureMark.tube(sides:wobble:wavelength:)` turns a drawn gesture into a mesh, and `GestureMark.solids(spacing:seed:)` strings instances along it. [Gesture marks](Docs/Generators/GestureMarks.md#in-space-tube-and-solids)
- **A layer as an environment.** A `RenderTarget` is a `VideoFeed`, so `environment(.feed(layer))` lights a scene with the sketch's own drawing. [3D](Docs/3D/3D.md#a-live-camera-environment)
- **A sample 3D model.** `import OllinSampleModels`, and `SampleModel.duck.load()` gives a sketch a model to try materials, lights, and camera moves on. [Sample models](Docs/3D/SampleModels.md)

**Geometry and simulation**

- **Finding boxes.** `BoundsIndex` answers which of thousands of rectangles hold a point, overlap a rectangle, or overlap each other. `Rectangle` gains `intersects(_:)`, `intersection(_:)`, and `union(_:)`, and `Box3` gains `intersects(_:)`. [Bounds index](Docs/Drawing/BoundsIndex.md)
- **Neighbors in space.** `SpatialIndex3D` is `SpatialIndex` for `Vector3`: the nearest point, the k nearest, everything within a radius, and everything inside a `Box3`. [Spatial index](Docs/Drawing/SpatialIndex.md#in-space-spatialindex3d)
- **Matching two sets at the least total cost.** `Matching.optimal(_:_:cost:)` pairs two sets so the costs add up to the least possible. A cloud of dots gathers into letters along paths that never cross. `Matching.greedy` is the quick comparison. [Matching](Docs/Drawing/Matching.md)
- **Soft bodies that rub, meet rigid bodies, and fold.** A 2D `SoftBody` has `friction`, and it pushes and is pushed by a rigid `Body`. With `collidesWithItself: true`, a long outline folds onto itself and no longer passes through. [Physics](Docs/Simulation/Physics.md#soft-bodies)

**Sound**

- **An echo long enough to be a loop.** `Delay.time` runs to sixty seconds (`Delay.maxTime`). Each repeat lands on its exact sample, and turning `time` while the echo sounds no longer clicks. [Synthesis](Docs/Helpers/Synthesis.md#delay)
- **The sketch's sound as a file of its own.** `--export-sequence` writes `soundtrack.wav` beside its frames, and `--export-audio FILE` (`OllinApp.exportAudio`) writes the sound alone. A `--skip` stretch is now dropped from the sound too. [Synthesis](Docs/Helpers/Synthesis.md#sound-in-an-export)

**Windows**

- **A sketch over the desktop.** `--overlay`, or `OllinApp.runAsOverlay { MySketch() }`, floats a sketch above every window. Where the canvas is clear (`background(.clear)`) the desktop shows through, and a click there goes to whatever is underneath. [Overlay](Docs/Output/Overlay.md)
- **A second window for a layer.** `makeWindow(showing:title:)` gives a layer a window of its own: the piece on the projector and the controls on the laptop. The returned `SketchWindow` reports its own pointer. [Windows](Docs/Output/Windows.md)

**Parameters and the live window**

- **Undo in the inspector.** ⌘Z puts back a parameter you turned by hand and ⇧⌘Z brings it forward, in every host. One gesture is one step, and a reset is one step. [Parameters](Docs/Helpers/Parameters.md#undoing-a-change)
- **Long menus fold into submenus.** A `ParamChoices` type that declares `paramChoiceGroups` gets a submenu for each group. `Easing` declares its families, so a curve's menu is twelve rows instead of thirty-two. [Parameters](Docs/Helpers/Parameters.md#folded-groups)
- **A description on a parameter.** `help:` on any `@Param` is a sentence about it. The inspector shows it on hover and `--list-params` prints it. [Parameters](Docs/Helpers/Parameters.md#groups-icons-and-a-description)
- **The rest of a package in the live window.** A sketch that imports a library target of its own package, or another Swift package, now runs under `ollin`, OllinLive, and OllinLiveCoding. Saving the library rebuilds it and reloads the sketch. A target with C code, a macro, or a binary is refused by name. [Single-file sketches](Docs/Tools/SingleFile.md#code-shared-between-sketches)
- **A failed frame names its pass.** When the GPU throws a frame away, the error now ends with the pass the failure began in.
- **Traced shadows can be switched off on one Mac.** With `OLLIN_NO_TRACED_SHADOWS=1` in the environment, point lights and panels cast through shadow maps. It is for a Mac whose GPU misbehaves on traced shadows. [3D](Docs/3D/3D.md#shadows)

**Connections**

- **A listener says why its port would not open.** `lastError` on `OSCReceiver`, `TUIOReceiver`, `DMXReceiver`, and `EtherDreamFinder` names the port another program holds. `isRunning` turns false, where such a receiver used to read as running, and `start()` tries again.
- **A publisher says where it is in its life.** `phase` on `SyphonServer`, `VirtualCameraServer`, and `PhoneScreen` is one `PublisherPhase`: `.waiting`, `.publishing`, `.unavailable`, or `.stopped`. `SessionRecorder.lastError` says why a take's file could not be finished.

**Examples**

- **Carlos Cruz-Diez joins the recreations.** [`Examples/Recreations/CarlosCruzDiez`](Examples/Recreations/CarlosCruzDiez/) has `Physichromie`, a panel of blades whose picture depends on where the pointer stands, and `Chromosaturation`, three rooms of colored light the eye adapts to.
- **Eduardo Terrazas joins the recreations.** [`Examples/Recreations/EduardoTerrazas`](Examples/Recreations/EduardoTerrazas/) has `Cosmos`, his structure laid as a tabla of wool yarn, and `Posibilidades`, a sheet of small drawings that each change the same diagram one way.
- **A second visit to Hiroshi Kawano.** [`Examples/Recreations/HiroshiKawano`](Examples/Recreations/HiroshiKawano/) gains `SimulatedColorMosaic` and `Flow`. Both follow the procedure he described: a chain counts how the cells of a few hand-drawn pictures sit together, then writes more like them.
- **Ten examples for the features above.** `Shapes/InkPen`, `Effects/ScannedByItself`, `Patterns/GatherIntoLetters`, `Physics/SoftBodiesMeet`, `3D/Raymarching/StandingField`, `3D/Geometry/GestureMarks3D`, `Audio/Loop`, `Audio/Drive`, `Installation/OverDesktop`, and `Installation/SecondView`.

### Changed

Each of these can change what a sketch draws, sounds like, or accepts.

- **Small dots and thin lines are a little lighter.** A dot a few pixels across or a line under a pixel wide used to lay more ink than its size, and now lays exactly its own. If a sketch looks thinner, raise the size or the `strokeWeight` slightly. Such marks take 7 to 18% more GPU time. [Drawing](Docs/Drawing/Drawing.md#point)
- **A simulation seeded by drawing runs to a different picture.** A shape drawn into a field covers its edge a little differently now, so a rule that amplifies its start (Lenia, reaction-diffusion, a sandpile) ends up somewhere else. The same sketch still repeats from run to run.
- **Blend modes keep alpha as coverage.** `.add` no longer pushes a layer's alpha past 1, so added lights drawn back over a picture do not turn it black. `.multiply`, `.darkest`, and `.subtract` add no coverage, so in an empty layer they leave nothing. To darken the canvas with a layer, set the mode when drawing it back. [Drawing](Docs/Drawing/Drawing.md#blendMode)
- **A see-through `background` is weighted by its alpha.** A window shows a clear canvas over black, so such a background is darker there than it was. For trails, keep the canvas with `noClear()` and paint a see-through rectangle each frame.
- **The five distortion characters do what their names say.** `.softClip`, `.overdrive`, `.bitCrush`, `.ring`, and `.squeeze` were presets of the system's unit, and none matched its name. Each is now a curve of Ollin's own and sounds different. If you used `.softClip` for its echo, add a `Delay(time: 0.357)` beside it. [Synthesis](Docs/Helpers/Synthesis.md#distortion)
- **A camera set inside a layer stays in the layer.** `camera(_:)` inside `withTarget` used to replace the canvas's camera too. If a sketch relied on that, set the camera on the canvas as well.
- **Volumes glow from inside by default.** `bounce` is on, so every medium is brighter in its depths. Set `bounce: 0` for the old picture.
- **The ground under a sun-lit sky is lit by the sun.** Below the horizon of a `.sky` whose sun lights the scene, faces turned down are brighter, and the scene reads a little darker overall because the exposure counts that ground. [3D](Docs/3D/3D.md#the-skys-sun)
- **The sun's light follows the clouds.** Under a cloudscape the scene gets the whole beam while the sun stands in a gap and next to nothing behind a thick cloud. [3D](Docs/3D/3D.md#clouds-over-the-procedural-sky)
- **A 2D soft body rubs and stops rigid bodies by default.** `friction` is 0.3 unless you give one, so pass `friction: 0` for the old slide. Rigid bodies no longer pass through.
- **`--param` refuses a value the parameter cannot hold.** A value past the range or off the step used to land silently on the nearest one. The run now stops and names the nearest value. [Export](Docs/Output/Export.md#setting-a-parameter-for-the-run)
- **The live hosts' status chip says what stopped the sketch.** It reads "Compile error", "setup() failed", or "Shader error", and "Plain build" when the optimized build failed behind the plain one. [Live coding](Docs/Tools/LiveCoding.md#errors-during-a-set)
- **`ollin api <Type>` prints each case's comment.** The members of an enum now carry their documentation in the list. [The reference offline](Docs/Tools/Reference.md#a-name-and-what-it-takes)
- **Molnár's *Interruptions* is redrawn from a plate.** The recreation's numbers are now measured off the plotter drawing the Victoria and Albert Museum holds (E.269-2011): 56 lines a side, a lean toward the vertical, and small patches of missing lines. `Examples/Recreations/VeraMolnar/Interruptions`

### Fixed

**Drawing**

- **Tiny moving dots no longer flicker.** A dot under a few pixels across laid ink that depended on where it fell on the pixel grid, and none at all near a pixel's corner. Its ink is now its area wherever it lands, for GPU particles too. [Drawing](Docs/Drawing/Drawing.md#point)
- **A diagonal hatch reads one even tone.** A line's ink changed with its angle and its place on the grid, which showed as bands. It is now the line's width everywhere. The outline of a built-in shape (the `stroke` on a `drawCircle` or a `drawRect`) is unchanged for now.
- **A line drawn into a coarse layer keeps its ink.** A hatch of thin lines drawn into a half-scale layer or a simulation field came out as broken dashes.
- **See-through shapes blend by their alpha under `.multiply`, `.screen`, `.lightest`, and `.darkest`.** These four took a shape's color whole, so a half-clear multiply read too bright and a soft edge left a ring.
- **A transparent PNG of added light matches the window.** A pile of `.add` marks over a clear canvas stored one mark's color. An EXR still keeps light and coverage apart.
- **A folded outline never takes the window down.** A closed `curveThrough` ring that crossed itself hundreds of times hit an assertion in the fill and ended the window. It now returns a fill.
- **A chamfer, stairs, or columns scope holds a negative radius at zero.** `chamferUnion(radius:)` and its eight siblings now draw what the same operators on an `SDF` value draw.
- **`SlitScan` names its own method.** The note it prints for a skipped frame said `push`, and the method is `append`.

**3D**

- **Lit 3D is about ten times faster on an M1 or M2.** Every lit shader carried the ray tracer, whether the frame traced or not. A lit mesh filling the frame took 43 ms on an M2 and takes 3.9. A frame that does trace is as slow as before. [Combinators](Docs/Drawing/Combinators.md#notes)
- **A traced shadow or a field of blocks could restart the GPU.** On a Mac that traces rays in software, a shadow from a point light or a panel, or a `voxelized` field, could freeze the screen. Both causes are fixed, though a heavy field under a traced shadow can still fail there.
- **The live window carries on after a GPU hang.** It used to show its last finished frame for good. The frame loop also holds while the Mac sleeps.
- **A glowing surface glows in a traced reflection.** A mirror showed a surface with an `emissiveColor` or `Mesh.glowing(_:)` as its unlit body.
- **A marched field drawn in a layer showed on the canvas too.** It happened when the canvas marched its own `drawSDF3D` fields at reduced resolution. The canvas now draws its own fields alone.
- **A mesh field in a layer is culled through the layer's own view.** A `MeshField` in a layer of another shape lost copies at its sides. [Instancing](Docs/3D/Instancing.md#a-field-that-culls-itself)
- **A textured OBJ drew its texture upside down.** The reader now flips `vt` as it reads, as the USD reader already did. [3D](Docs/3D/3D.md#meshes-from-file)

**Sound and simulation**

- **A blown tube holds its pitch however hard it is blown.** Near the top of its range the breath pulled the pitch up to 36 cents sharp. Every preset now stays within five cents from A2 to C7, and the highest notes are a little purer. [Synthesis](Docs/Helpers/Synthesis.md#a-blown-tube)
- **A simulation takes a negative seed.** `makeEvolution`, `makeParticleLife`, and `makeParticleLenia` crashed on any seed below zero.
- **A face's strongest expressions come in one order in every run.** `PhoneFace.strongestBlendShapes()` listed two shapes at the same value in a different order from run to run.

**Parameters and the live hosts**

- **A stepped parameter holds the decimal its step names.** Declared `0.1...2, step: 0.01`, a parameter showing 1.5 held 1.5000000000000002, so `--param zoom=1.5` was refused. A sketch that amplifies tiny differences can draw a different picture for the same seed.
- **`--list-params` says the step of a whole-number parameter.** `8...128, step: 8` now prints `8...128, by 8`.
- **The Colors panel no longer opens over the inspector.** When it comes up over the parameters list it is moved beside the window.
- **A reset under a held clock shows.** With the timeline holding the clock, putting a parameter back changed the value and drew nothing.
- **A package's sketch compiles every file of its target in the live window.** A manifest that excluded one file made the live compile skip the files after it. A target that uses the `package` access level compiles there too.
- **OllinLive keeps a shader error up until the shader is fixed.** Saving a `.metal` file with the same mistake cleared the error and never brought it back.
- **A recovery offer in OllinLiveCoding could be lost, or restored into the wrong sketch.** The offer now survives the launch, and opening another document withdraws it. [Live coding](Docs/Tools/LiveCoding.md#files-saving-and-recovery)
- **Letting go of Command during a drag on the stage left the editor ignoring clicks.** The drag now stands down when it ends.

**Connections and installations**

- **A piece with opening hours kept the display awake all night.** Two holds on the display were taken and only one released. There is one hold now, and the dark hours release it. [Installation](Docs/Output/Installation.md#keeping-hours)
- **A take started right after `stop()` can be stopped.** A second take begun before the last file closed ran on with `isRecording` true. Each take is its own file now. [Recording](Docs/Output/Recording.md#the-typed-layer)
- **A stopped Syphon server or virtual camera stays stopped.** `stop()` released the server and the next frame stood it back up.
- **An MQTT client with `reconnects: false` can connect again.** After a drop, `connect()` returned without dialing. [MQTT](Docs/Integration/MQTT.md#staying-up)
- **A laser whose interlock tripped can be armed again.** It used to stay dark until a restart. `hasStopCondition` and `lastError` say the DAC is stopped. Nothing restarts by itself: `arm()` clears the stop, through `EtherDreamDAC.clearStopCondition()`. [Laser](Docs/Integration/Laser.md#safety)
- **A web socket a server closes says so.** `PushFeed.problem` now reads the close code and the server's reason. [Live data](Docs/Helpers/LiveData.md#pushfeed-a-feed-that-is-pushed)
- **A rebuilt Ollin Camera replaces the installed one.** The app's version lives in one place now, and its README says when to raise it. [Virtual camera](Docs/Integration/VirtualCamera.md)

## [0.17.0] - 2026-10-25

This release adds strokes and fills drawn as materials, eight tape and lens looks, marks built from one gesture, and textures a plotter can draw. A sketch marked `@main` is now a whole app on an iPhone or iPad. Paper texture's folds changed and several fixes move a picture, so read **Changed** and **Fixed** before you update.

### Added

**Drawing**

- **Strokes in a material.** `strokeMedium(_:)` shades a stroke as a material. `.pencil`, `.charcoal`, and `.pastel(palette:)` are settings of `.dry(tooth:softness:roughness:palette:seed:)`: a light line breaks into specks, and a pastel grain takes one of several colors. The stroke's color is the pigment and its alpha the density. [Marks](Docs/Drawing/Marks.md#media)
- **Bristle, dry brush, wet, and oil strokes.** `.bristles` streaks two pigments along the path, and `.dryBrush` runs dry on the paper's grain. `.wet` drags the paint under it, and `.oil` lights its own ridges. A see-through mark lays one coat where it crosses itself. A vector export writes the flat ribbon. [Marks](Docs/Drawing/Marks.md#media)
- **Shapes filled as what they are made of.** `fillMedium(_:)` shades a fill from its distance to its own edge. `.impasto` and `.knife` are thick paint, `.wash` glazes what is under it, and `.gouache` covers it. It applies to `drawShape`, `drawPolygon`, and the built-in shapes with a simple outline. `noFillMedium()` returns to a flat fill. [Marks](Docs/Drawing/Marks.md#fill-media)
- **Fills of chrome, glass, and stone.** `.chrome` reflects a studio and the drawing around its rim, `.glass` bends the drawing at its rim, and `.facetedGlass` breaks it into facets. `.rock`, `.marble`, and `.sand` are stone and grains. The textures move with the shape under `translate` and `rotate`. A vector export writes the fill flat. [Marks](Docs/Drawing/Marks.md#fill-media)
- **A shader stroke knows where it is on the ribbon.** Under `stroke(_ shader:)`, `info.arcLength` is the distance along the path, `info.across` the place across the width, and `info.halfWidth` the local half-width, beside `info.along` and `info.distance`. [Color](Docs/Drawing/Color.md#shader-paint)
- **Shaping the press.** `StrokeMark.pressureDeadZone` ignores a press under it, and `pressureCurve` raises the press to a power. `maxWidthChange` limits how fast a recorded mark's width may change, so a sudden press swells the mark. [Marks](Docs/Drawing/Marks.md#pressure)
- **Marks built from one gesture.** `GestureMark(mark, width:)` turns one drawn path and its width into sixteen families of marks a plotter can draw. They are `cloud`, `chain`, `spikes`, `dashes`, `dots`, `strips`, `feather`, `leaves`, `fringe`, `pixels`, `facets`, `lanes`, `spiral`, `strands`, `fragments`, and `wiggle`. [Gesture marks](Docs/Generators/GestureMarks.md)
- **A gesture's pieces, and its outline.** Each family returns `GestureMark.Piece`s, outlines to fill or lines to stroke, and `.shape` merges a list into one silhouette. `hull()` and `blob()` enclose a whole gesture, and `figure(_:)` is the shape its two ends span. Any `Shape` can be `spiked(_:height:)` or `wobbled(by:scale:)`. [Gesture marks](Docs/Generators/GestureMarks.md)
- **A shape cut by a line.** `shape.split(along: line)` gives a shape's two sides of a `Ray2`, `clipped(to: HalfPlane(point:inward:))` keeps one side, and `clipped(within:of:)` keeps the band around a line. Holes are kept. [Geometry](Docs/Drawing/Geometry.md#shape-cut)
- **Hatching that fits each shape.** `Hatching(centersLines: true)` spaces each shape's lines across its own extent, the whole number nearest its height over `spacing`. A grid of equal cells then gets the same lines in every cell. The SVG exporter honors it too. [Export](Docs/Output/Export.md#hatching-solid-fills-for-a-pen-plotter)

**Particles**

- **Particles that read a picture.** `stepParticles(_:custom:textures:)` hands a particle step up to four pictures, read in the snippet as `picture(index, point)`. Particles can steer by a word, a shape, or a blur the sketch draws. A kernel of your own reads up to eight through `compute(_:buffers:textures:count:params:)`. See the `Compute/SteeredByAPicture` example. [Compute](Docs/Shaders/Compute.md#pictures)
- **One vertex a particle.** `drawParticles(buffer, style: .light, maxSize: 1)` names the largest particle in a buffer, and each is then drawn as one point. A spray of millions of tiny points draws in about half the time. `LineSpray` gains it with no change to the sketch, and the `Particles` form takes the same label. [Depth of field](Docs/Drawing/DepthOfField.md#light)

**Color**

- **Palettes built around one hue.** `Palette.scheme(_:key:count:jitter:seed:)` reads a key color's hue and builds a `.monochrome`, `.vividAndDark`, `.vivid`, `.pastel`, or `.dark` palette around it, with a seeded jitter. `Color.mostVivid(hue:)` is a hue's most vivid displayable color. [Color](Docs/Drawing/Color.md#palette-schemes)
- **A stepped ramp.** `Ramp.stepped([.red, .orange, .yellow])` holds each color flat up to the next stop, for a poster-flat gradient. `Ramp.stepped(stops:)` places the bands, `isStepped` says which kind a ramp is, and `reversed` keeps the bands. `Ramp.holographic` is eight flat bands in the order a grating spreads white light. [Color](Docs/Drawing/Color.md#ramp)
- **A ramp over wavelengths.** `Ramp.wavelengths(from: 400, to: 700)` places the pure hues of the wavelengths evenly, so `color(at:)` walks the physical spectrum. It is a rainbow with a wide green and no magenta. [Color](Docs/Drawing/Color.md#ramp)
- **The color of a thin film, on the CPU.** `Color.interference(thickness: 420)` is the color a clear film that many nanometers deep shows, matching the `.thinFilm` filter. `Spectrum.interference(thickness:ior:)` is the reflectance curve behind it. A `Ramp` of it through `.alongPath` colors a stroke in a soap film's order. See [`Examples/Color/PearlStrokes`](Examples/Color/PearlStrokes/). [Spectrum](Docs/Drawing/Spectrum.md#physical)

**Effects**

- **Wipes in any order.** `Combine.wipe(_:progress:feather:)` turns one layer into another as `progress` runs from 0 to 1, and `Filter.wipe(_:progress:feather:)` brings a layer in over whatever is behind it. In `compose { }` it is `.wiped(to:_:progress:feather:)`. Both cross to a web page. [Effects](Docs/Drawing/Effects.md#wipes-and-copies)
- **The order a wipe follows.** A `WipeOrder` is a straight edge (`.directional(angle:)`), a growing circle (`.radial(center:)`), a clock hand (`.angular(center:angle:)`), blocks (`.cells(columns:rows:)`), or a dissolve (`.noise(size:seed:)`). Reshape one with `.folded()`, `.tiled(_:)`, `.bands(_:)`, `.shuffled(seed:)`, `.checker()`, `.diamond()`, or `.reversed()`. [Effects](Docs/Drawing/Effects.md#wipes-and-copies)
- **Copies of a layer.** `Filter.repeated(_:count:scale:rotation:opacity:hueShift:jitter:seed:)` lays a layer out again in a grid, around a ring, or along a line. Each copy is a step smaller, more turned, fainter, and further around the hue wheel. `facesOut` turns the copies on a ring to face out. It crosses to a web page. [Effects](Docs/Drawing/Effects.md#wipes-and-copies)
- **A glowing edge.** `Filter.edgeGlow(width:colors:spots:spotSize:pulse:bloom:center:phase:)` lays a band of light along a layer's edge, with spots of each color racing around the shape. It crosses to a web page with the other layer styles. [Layer styles](Docs/Drawing/LayerStyles.md#edge-glow)
- **A worn videotape.** `.vhs(smear:jitter:damage:amount:phase:)` plays a layer off a worn tape: lines jitter sideways, the bottom tears where the heads switch, and the color trails behind edges. Feed `phase` your `time`. An `amount` of 0 leaves the layer untouched. [Effects](Docs/Drawing/Effects.md#tape-and-lens)
- **A JPEG at a quality, without a file.** `.jpeg(quality:subsamplesChroma:)` runs the format's own block transform on a layer: flat tiles with ringing toward quality 10, and the color at half resolution. With `subsamplesChroma: false` the color keeps full resolution. The layer's alpha is kept. [Effects](Docs/Drawing/Effects.md#tape-and-lens)
- **Tilt-shift and a progressive blur.** `.tiltShift(focus:angle:band:falloff:radius:)` keeps a band sharp around a line and blurs away from it, so a view reads as a model. `.progressiveBlur(angle:start:end:radius:)` fades a blur in across the layer, matching `.gaussianBlur(radius:)` where it is full. [Effects](Docs/Drawing/Effects.md#tape-and-lens)
- **A light leak.** `.lightLeak(anchor:spread:streaks:colors:flicker:intensity:phase:seed:)` fogs a layer with light from a point on its edge, with streaks along the beam through a three-color ramp. It never darkens a pixel. [Effects](Docs/Drawing/Effects.md#tape-and-lens)
- **A page peeling.** `.pagePeel(amount:corner:radius:shading:sheen:shadow:back:)` curls a layer up from a corner, its back showing. The ground it lifts off is transparent, so what is drawn under it shows through. [Effects](Docs/Drawing/Effects.md#tape-and-lens)
- **Hairline scratches.** `Generator.scratches(count:thickness:length:angle:wobble:flicker:color:phase:seed:)` draws the scratches of a worn print over nothing, to composite over a picture. Each line holds its place for a few dozen frames and flickers. [Effects](Docs/Drawing/Effects.md#generate)
- **Datamosh.** `Sim.datamosh(amount:blockSize:motion:drift:wander:period:seed:)` is a field whose blocks refresh from the drawing or hold, a held block dragging its last contents along the drawing's motion. The `Effects/TapeAndLens` example runs all eight tape and lens looks. Every one but the datamosh crosses to a recorded web page. [Effects](Docs/Drawing/Effects.md#simfield)
- **A red-and-cyan anaglyph.** `.anaglyph(separation:)` prints a layer as a stereo pair for red-and-cyan glasses. `scene.combined(with: scene.depth, .anaglyph())` reads a depth map instead. A near thing then stands off the page and a far one sinks in, by its distance from `focus`. [Effects](Docs/Drawing/Effects.md#design)
- **A heat mirage.** `.mirage(horizon:faults:amount:phase:)` shifts every row above a horizon sideways by a wavering amount and mirrors the picture below it, the shimmer over a hot road. `Filter.mirageShift(y:)` is the row shift, for a sketch that draws where a row went. [Effects](Docs/Drawing/Effects.md#design)
- **Schlieren.** `.schlieren(angle:amount:)` reads a layer's luminance as the density of a gas. Its gradient along a knife's angle becomes light and dark about a mid-gray: the knife-edge photograph of heat or a shock. [Effects](Docs/Drawing/Effects.md#design)
- **Bubble wrap.** `.bubbleWrap()` lays a sheet of bubble wrap over a layer, or over the whole frame as a `postProcess`. Each bubble is a lens that magnifies what is under it. [Effects](Docs/Drawing/Effects.md#design)
- **Chrome for lettering.** `.chrome()` fills a layer's shape with airbrushed logo chrome: a sky above a bending horizon, a floor below, and a bright wire at the join. The sky and the floor are `Ramp`s, `.chromeSky` and `.chromeFloor` by default. It exports to the web page. See [`Examples/Effects/ChromeLettering`](Examples/Effects/ChromeLettering/). [Effects](Docs/Drawing/Effects.md#design)
- **Holographic foil.** `.holographicFoil()` fills a layer's shape with crumpled foil: a stepped rainbow that breaks at every crease, under a light at `lightAngle`. `phase` sweeps the bands, so `phase: time` and `lightAngle: time * 0.3` make the sheet move. `relief` presses the layer's own brightness into the foil. See [`Examples/Effects/CrumpledFoil`](Examples/Effects/CrumpledFoil/). [Effects](Docs/Drawing/Effects.md#design)

**Textures and geometry**

- **A sheet of facets.** `FacetField` lifts a triangulation into flat faces. Each knows its `normal`, its `tilt`, and how squarely it faces a light (`facing(_:)`), and `edges` lists every crease once. Build one with `FacetField.grid(in:spacing:seed:height:)`, `FacetField(points:height:)`, or `crumpled(in:spacing:crinkle:seed:)`, and lift it again with `lifted(by:)`. [Voronoi & Delaunay](Docs/Drawing/Voronoi.md#facets)
- **The foil reads the facets you hold.** `.holographicFoil()` takes a `FacetField`, its own by default or one you hand it. The creases you stroke from `sheet.edges` then land on the filter's own. [Effects](Docs/Drawing/Effects.md#design)
- **Textures drawn as lines.** Four textures a plotter can draw, each as geometry a sketch holds and strokes. `WoodGrain.trace(in:)` traces wood grain around its knots, and `Frost.grow(along:)` stands hoarfrost needles along an outline. `Crackle.grow(in:)` walks the veins of cracked wax, and `Ikat.stripes(in:)` dyes stripes with stepped edges. See the `Patterns/LineTextures` example. [Textures](Docs/Generators/Textures.md#lines)
- **Chromatography rings.** `Chromatography.scatter(in:count:radius:)` and `.spread(at:radius:)` give the stain a drop of ink leaves as it spreads through paper, as geometry a sketch holds. Drops that spread into each other stop where they meet. The `Effects/Phenomena` example shows it with the anaglyph, the misregistered plates, the mirage, the schlieren, and the wavelength ramp. [Textures](Docs/Generators/Textures.md#chromatography)
- **Rust and verdigris.** `generate(.rust())` paints corrosion blooms over steel, and `generate(.verdigris())` a green crust over bronze. The blooms are a `Patina` a sketch can hold, from `Patina.scatter(in:count:radius:seed:)`. Each `Blob` has its `outline`, `masses`, and `blisters` as geometry, and the generator paints the blooms it is handed. [Textures](Docs/Generators/Textures.md#patina)
- **A terrazzo floor.** `generate(.terrazzo())` lays chips of stone in a binder, in three sizes, each clear of every other. The chips are a `Terrazzo` a sketch can hold, from `Terrazzo.scatter(in:chipRadius:density:gap:tones:seed:)`. Each `Chip` is a `Shape`, and the generator paints the floor it is handed. [Textures](Docs/Generators/Textures.md#terrazzo)
- **A crease in a heightfield.** `sheet.creased(along: [a, b], width: 0.03, amplitude: 0.3)` folds a `Heightfield` along a path, and creases stack into a crumpled sheet. `Heightfield.creaseProfile(at:)` is the crease's own profile. [Terrain](Docs/Generators/Terrain.md#crease)

**3D**

- **Any 3D field as blocks.** `SDF3D.voxelized(size:gap:jitter:seams:occlusion:seed:)` rebuilds a raymarched field out of cubes on a grid, each colored by the field at its center. A melt becomes a voxel model, and a slab one block thick becomes pixel art. It costs about three times its field, and it crosses to a web page. [SDF combinators](Docs/Drawing/Combinators.md#blocks)
- **A hologram material.** `material(.hologram)` rules a diffraction grating into a polished metal, the rainbow of a hologram sticker or the back of a disc. `Material.hologram` is the strength, `gratingSpacing` the groove pitch in nanometers, and `gratingRotation` turns the grooves. A path-traced export shades it as the metal under it. See [`Examples/3D/Materials/Hologram`](Examples/3D/Materials/Hologram/). [3D](Docs/3D/3D.md#hologram)

**Export and output**

- **Stroke media on a web page.** `--export-web` carries a stroke under every stroke medium: `.pencil`, `.charcoal`, `.pastel`, `.dry`, `.bristles`, `.dryBrush`, `.wet`, and `.oil`. A wet stroke over a canvas that keeps its paint (`noClear`) still stops the export by name. [Web page](Docs/Output/Web.md#strokes-and-fills-on-the-page)
- **Plates out of register.** `separation.misregistered(offsets:rotations:)` moves each ink's master by its own offset and turns it about the sheet's center, so the preview shows the misprint. Misregister first and screen after. [Print separations](Docs/Output/PrintSeparations.md#screening-the-masters)
- **A sketch is the whole app on a phone or a tablet.** `@main` on a sketch now starts an app on iOS, through `Sketch.main()` and `OllinApp.run(_:)`. Its `@Param`s open in a panel or a sheet. `ollin new --kind ios-app` writes such a sketch, and `ollin phone` now takes one marked `@main`. [The sketch on the phone](Docs/Tools/OnThePhone.md#in-an-app-of-your-own)
- **A sketch's `--help`.** Running a sketch with `--help` or `-h` prints its name, how to run it, its parameters as `--param` takes them, and every flag it reads. It opens no window, writes no file, and does not run `setup()`. [Export](Docs/Output/Export.md#saying-what-a-sketch-declares)

**Examples**

- **Jesús Rafael Soto joins the recreations.** [`Examples/Recreations/JesusRafaelSoto`](Examples/Recreations/JesusRafaelSoto/) has `Vibracion`: wires hung before fine stripes flicker as the pointer moves the viewer. It follows *Vibration* (1961), *Vibration jaune* (1965), and *Grande écriture* (1972). `Penetrable` walks a visitor through the hanging tubes of *The Houston Penetrable*. Both export SVG.
- **Roman Verostko joins the recreations.** [`Examples/Recreations/RomanVerostko`](Examples/Recreations/RomanVerostko/) has `Pathway`, after the procedure he published in 1988: one brush gesture, drawn again thousands of times behind itself as fine pen strokes. `Cyberflower` repeats one curved line along a larger copy of itself until the lines fold into a flower. Each exports an SVG a plotter can draw.
- **Dóra Maurer's folder grows to four.** [`Examples/Recreations/DoraMaurer`](Examples/Recreations/DoraMaurer/) adds two works. `FiveOutOfFour` follows *5 out of 4* (1975 and 1979) and *4 out of 3* (1976). `Overlappings` follows the shaped canvases of 2007 to 2012: congruent sheets on one bent `CoonsPatch`, their overlaps mixed as layers of paint. Both export SVG.

### Changed

- **The folds of `.paperTexture` look different.** Its `folds` are now straight seeded creases lit on one flank, shaped as a `Heightfield` crease is, so a paper-textured picture changes. [Terrain](Docs/Generators/Terrain.md#crease)
- **The Guide is forty-six chapters.** Chapter 20 split in two. *Pictures restyled* keeps the painting, line, grade, film, and paper looks. The new Chapter 21, *Glass, chrome, and tape*, takes the materials and the tape and lens looks. Every chapter file from 21 on is one higher: `21-PicturesYouSolve.md` is now `22-PicturesYouSolve.md`, through `46-Installations.md`. [The Guide's contents](Guide/README.md#contents)
- **Feature edges on a mesh that moves.** A mesh rebuilt every frame over the same index buffer now redoes only the crease test. `featureEdges()` on a 1.2-million-vertex mesh costs about 16 ms a frame, where it cost 0.8 s. [Hidden-line solids](Docs/3D/HiddenLines.md#what-it-costs)
- **A volume skips its empty space.** The march steps past the parts of a grid that hold nothing, and every volume draws the same picture, byte for byte. The `Volumes` example's plume went from 9.6 to 7.3 ms a frame at 1080 square on an M2. [Volumes](Docs/3D/Volumes.md#what-it-costs)

### Fixed

**3D**

- **Touching pieces bounce the same light every time.** Under `globalIllumination()`, a solid cut into pieces that fit back together could light a face a level brighter or darker from render to render. `Mesh.fractured` did, and so did a box flush on a floor. The same seed and frame now draw the same picture. [3D](Docs/3D/3D.md#global-illumination)
- **A wall, a ceiling, or a floor reads the bounce where it stands.** Under `globalIllumination()`, a surface at a room's boundary read its light from in front of itself. A ceiling came out brighter than a path trace of the same room. A bounce-lit room is now a little darker near its walls. [3D](Docs/3D/3D.md#global-illumination)
- **An emissive map glows by its map in the bounce.** A panel glowing through `Mesh.surfaceMapped(emissive:)` lit the room under `globalIllumination()` as if its whole face glowed. Its light now follows the map, as in the path-traced export. A triplanar mesh, a copy, and a map drawn as a layer the same frame still glow whole. [3D](Docs/3D/3D.md#global-illumination)
- **A polished floor throws its light into the bounce.** A smooth metal or glossy surface under a lamp threw almost none of its color onto the ceiling. The color now lands there, and on the walls as a broad, soft patch. [3D](Docs/3D/3D.md#global-illumination)
- **Fog stays where it was drawn under a caption.** A 3D scene with `fog` and a caption, or anything in `withOverlay`, drew the fog a second time over the finished frame. A low mist became one solid sheet below the horizon. [Effects](Docs/Drawing/Effects.md)
- **A lens flare's coatings reflect what a thin film does.** A coated surface sent back about twice the light a real single-layer coating does, and more off the axis. The reflectance is now exact, and the ghosts' colors shift with it. [Lens flare](Docs/3D/LensFlare.md)
- **`stopped(to:)` means the f-number it names.** The iris was closed too little: the double Gauss at f/8 stood at f/5.5 and the Heliar at f/6.4. A stopped-down flare now draws smaller ghosts and a longer star. `Lens.standard` is the double Gauss at f/5.6, which draws the default flare as it was. [Lens flare](Docs/3D/LensFlare.md)
- **Every ghost brightens as the iris closes.** Stopped down, a flare brightens every ghost by as much as the opening's area shrank. A ghost bounded by the front glass used to keep its brightness. A stopped-down Heliar shows more of its veil. [Lens flare](Docs/3D/LensFlare.md)
- **A path-traced room is as bright as the window shows it.** In an environment with lamps the trace ran hot. A white matte ball in the bundled interior traced a quarter brighter than the window showed it. The two now agree within 1%. [Path-traced export](Docs/Output/PathTraced.md#a-pixels-worth-of-a-curved-surface)
- **Light behind solid glass in the trace.** In a path-traced export, a ball behind a solid block of glass read too bright, since the light behind the glass was counted twice. Behind a block with the air's own index it now reads as it does with no block. [Path-traced export](Docs/Output/PathTraced.md)
- **A few more numbers stop at the physics bridge.** A body's `buoyancyScale`, a character's `facing`, a rope's `radius`, and the 2D world's `bounds` refuse a bad value and keep their own. Bad means not a number, an infinity, or past a billion units. A ragdoll's `pose(from:)` or `drive(toward:)` ignores a scene whose transforms hold one. [Physics in 3D](Docs/Simulation/Physics3D.md#world3d)

**Drawing and color**

- **A layer can draw a filter made the same frame.** A filtered or combined layer drawn into another layer came out empty, as in `withTarget(b) { drawImage(a.filtered(.invert()).image, 0, 0) }`. A layer that draws a filter's result now waits for it. [Effects](Docs/Drawing/Effects.md#notes)
- **Hatching no longer skips its first line.** `Hatching.lines(filling:)` and the SVG export's hatched fills could start one step too far in, so equal cells in a grid got different line counts. Neighboring fills still line up. [Export](Docs/Output/Export.md#hatching-solid-fills-for-a-pen-plotter)
- **`displayHeadroom` is 1 unless the sketch asked for headroom.** A `.standard` or `.wide` sketch beside another window holding headroom read that window's value. It now reads 1 there, and only an `.extended` sketch reads the screen. [Color output](Docs/Drawing/ColorOutput.md)
- **A live soft proof on a wide canvas proofs the canvas's own colors.** `Filter.softProof` with a proof `from: .displayP3` gave wrong colors on a wide canvas. A saturated P3 color now proofs within two levels of the same proof on the CPU. [Print color](Docs/Output/PrintColor.md)

**The live window**

- **A live window survives a framework rebuild.** A save after the framework was rebuilt under an open window crashed the window. OllinLive, OllinLiveCoding, `ollin`, and the gallery now refuse that reload with one sentence saying to relaunch, and the sketch keeps playing. [Live coding](Docs/Tools/LiveCoding.md#errors-during-a-set)
- **A picker that ran off the panel.** A `@Param` picker with `style: .segmented` and names wider than the inspector ran past the panel's edge, where its segments could not be clicked. It now falls back to the menu row. [Parameters](Docs/Helpers/Parameters.md#control-styles)

## [0.16.0] - 2026-10-18

This release adds clouds a compute kernel fills, soft bodies from any outline, typed text, and pinch and turn. A curve or a row of bars can be a parameter, and the procedural sky has its own sun. Some physics calls now throw and a few looks moved, so read **Changed** before you update.

### Added

**Drawing**

- **A small picture drawn big, cell by cell.** `imageSampling(.nearest)` keeps every pixel a hard square when a picture is drawn larger than it is. `.linear` stays the default. It is drawing state beside `tint`, restored by `withState { }`, and an `--export-web` page honors it. New example: `Images/PixelArt`. [Images](Docs/Drawing/Images.md)
- **A tone map that keeps a bright color's hue.** `toneMap(.neutral)` is the Khronos PBR Neutral curve. A bright orange stays orange, where `.reinhard` and `.aces` turn it yellow. A web page carries it, and `Rendering/ToneMapping` cycles through four curves. [HDR](Docs/Drawing/HDR.md)

**Geometry and simulation**

- **A shape bent into a curved patch.** `CoonsPatch` is a four-sided region with curved sides, read with `point(u:v:)`. `Contour.warped(from:into:)`, also on `Shape`, bends an outline from a rectangle into one, so lettering in a box lands on a waving banner. See `Shapes/WavingBanner`. [Geometry](Docs/Drawing/Geometry.md#coons-patch)
- **Bending outlines.** `Contour.warped(from:along:)` bends an outline to follow one curve the way it followed another, so lettering on a straight baseline rides a wave. `pulled(toward:amount:radius:)` draws the part near a point toward it. Both are on `Shape` too. See `Shapes/WavyLettering`. [Geometry](Docs/Drawing/Geometry.md#contour-bending)
- **Smoothing, splitting, and fitting an outline.** `smoothed(neighbors:keepingCornersOver:)` averages an outline and leaves its corners, and `split(atCornersOver:span:)` cuts it at them. `fitted(tolerance:)` traces a dense outline with a few cubic curves as a `Path` (Schneider's method). `Path.cubics` reads any path back as cubic Béziers. See `Shapes/TraceToCurves`. [Geometry](Docs/Drawing/Geometry.md#contour-bending)
- **Packing rectangles.** `packRectangles(_:in:padding:allowsRotation:)` fits rectangles of given sizes into one bin without overlap. The `RectanglePacking` it returns says where each went and which did not fit. It is MaxRects with the best short side fit (Jylänki's tightest variant). See `Patterns/PackedPhotos`. [Packing rectangles](Docs/Generators/RectanglePacking.md)
- **A soft body from any outline.** `World.addSoftBody(from:)` turns a closed `Shape` into a squishy body in the 2D physics world that keeps its area and its corners. `stiffness`, `bend`, `pressure`, and `shapeMemory` set the feel. Soft bodies keep each other out, and rigid bodies pass through for now. [Physics](Docs/Simulation/Physics.md)
- **What a soft body reports and takes.** A `SoftBody` reads its `shape`, `area`, `center`, and `velocity`, takes `push`, `applyForce`, and `move(by:)`, and inflates when its `restArea` is set. With `particlesCollide` on, loose particles are pushed out. `Physics/Blobs` is rewritten over it. [Physics](Docs/Simulation/Physics.md)

**3D**

- **A cloud a kernel writes.** `ComputeTexture3D` is a box of samples on the GPU that your own compute kernel fills through `compute(_:writing:)`. `drawVolume` draws it in place of a `Volume`. `PingPongTexture3D` pairs two for a simulation, stepped by `compute(_:reading:writing:)`. [`Examples/3D/Effects/Volumes`](Examples/3D/Effects/Volumes/) fills its plume from `Plume.metal`.
- **A volume casts its shadow.** Under `castShadows()` the solids under a cloud are darker by the light the cloud stops, so a plume stands in its own shadow. A scene without `castShadows()` draws as before. [Volumes](Docs/3D/Volumes.md)

**Input**

- **Typed text.** `typedText()` reads the keyboard as a text field does. A dead-key accent arrives as "é", an emoji as itself, and Chinese or Japanese once a candidate is chosen. `composingText` holds the reading until then, and `textTyped()` fires as text arrives. [`Examples/Input/TypedText`](Examples/Input/TypedText/)
- **Editing keys and the caret in typed text.** Return arrives as `"\n"` and Delete as a backspace, which `caption.append(typing: typedText())` reads as taking a character away. `caretPosition` tells the input method where the line is. `key` and `keyPressed()` are unchanged. A take records the text.
- **Pinch and turn.** Two fingers on the trackpad reach `draw()` as `pinchScale`, a factor, and `turnAngle`, in radians the way `rotate` turns. `size *= pinchScale` and `spin += turnAngle` keep a shape under the fingers. `fingersPinched()` and `fingersTurned()` fire once per event. [Input](Docs/Helpers/Input.md#pinch)
- **A pinch drives the view and the camera.** `viewControl()` zooms with a pinch about the pointer and `cameraControl()` dollies with one. A take records both. The phone showing the sketch (`PhoneDevice.show`) sends its own two fingers to the same values. [`Examples/Input/PinchAndTurn`](Examples/Input/PinchAndTurn/)

**Parameters**

- **A curve as a parameter.** `@Param var falloff = ResponseCurve([(0, 1), (0.5, 0.8), (1, 0)])` is a small graph in the inspector whose points drag, read as `falloff(t)`. `count:` bounds its points. `ResponseCurve` never overshoots them (after Fritsch and Carlson), and `.easing` hands it to a call that takes an `Easing`. [`Examples/Live/Parameters`](Examples/Live/Parameters/)
- **A row of bars as a parameter.** A list of numbers, `@Param(0...1) var accents = [1, 0.2, 0.6, 0.2]`, is a row of bars you paint by dragging across them, for a step pattern. A list of whole numbers works too.
- **Curves and bars go where a parameter goes.** Save writes them back into the sketch, a cue and a timeline key hold them, OSCQuery serves them, and the phone's remote surface edits them. For one run, pass `--param falloff=1@0,0.7@0.4,0@1` or `--param accents=1,0.2,0.6`.

**Export and output**

- **A still named by its moment.** `--at S` stands beside `--frame N` on every one-frame export, from `--export` and `--export-exr` to the vector files. The frame is S seconds of the sketch's clock at `--fps`, so `--at 2` is `--frame 120` at 60 fps. [Export](Docs/Output/Export.md)

**Examples**

- **A second visit to Mohamed Melehi.** [`Examples/Recreations/MohamedMelehi`](Examples/Recreations/MohamedMelehi/) gains two sketches where his wave meets the sun. `Soleil` is after the untitled panel of 1975, and `Volcanique` after *Volcanic* (1985). The wave travels, the palettes can be edited in the inspector, and both export SVG.
- **Dóra Maurer joins the recreations.** [`Examples/Recreations/DoraMaurer`](Examples/Recreations/DoraMaurer/) is after the Hungarian artist (1937 to 2026). `Displacements` runs the rule she stated for her *Displacements*: eight colored parts cross a grid one unit a step. `QuasiImage` enlarges one detail until every line is a band of flat color. Both export SVG.
- **Eduardo Mac Entyre and Miguel Ángel Vidal join the recreations.** [`Examples/Recreations/MacEntyreVidal`](Examples/Recreations/MacEntyreVidal/) is after the two painters who named *Arte Generativo* in Buenos Aires in 1959. `Circunferencias` is Mac Entyre's circle: families of circles in a disc. `Focos` is Vidal's straight line: an octagon of ruled faces and fans of lines. Both export SVG.

### Changed

Each of these can stop a sketch from compiling or change what it draws or sounds like.

**Drawing**

- **`setup()` may throw.** It is now `open func setup() throws`: a loader that cannot read its file lets its `FileError` out with a bare `try`, not `try!`. A window reports the error and holds the sketch, and an export fails with it. An override may leave `throws` off, so existing sketches compile. [Sketch](Docs/Core/Sketch.md)
- **The in-memory recorders take a `try`.** `OllinApp.svg(of:)`, `pdf(of:)`, `gcode(of:)`, `dxf(of:)`, `drafting(of:)`, `stitching(of:)`, `embroidery(of:)`, and `spatialScene(of:)` run `setup()` for a frame, so they now throw with it. A caller of those adds a `try`. [Sketch](Docs/Core/Sketch.md)
- **`CubicBezier` is a value of its own.** `HobbySpline.Segment` is now a typealias of the top-level `CubicBezier`, with the same `point(at:)` and `direction(at:)`. `Path.cubics` and `Contour.fitted(tolerance:)` return it too. Every existing spelling compiles unchanged. [Geometry](Docs/Drawing/Geometry.md)
- **A kept `Shape` drawn again costs a copy.** A shape kept in a property reuses its fill and stroke after its first draw. On an M2, 195 traced outlines went from 124 ms to 6 ms of drawing. Dashed, brushed, profiled, fading, and gradient strokes are worked out each time. Every solid stroke costs less too. No pixel changes.
- **A `@Param` tunes the 2D view live.** `viewControl(center:zoom:)` applied its arguments on the first call only. They are now the view's home. A changed value glides the view there until the viewer moves it, and after that changes only where `resetView()` opens. [Drawing](Docs/Drawing/Drawing.md)
- **A simulation can read a filtered layer, a frame late.** A `filtered(_:)` or `combined(with:_:)` output in a `SimField`'s `inputs` used to read as zero. It now arrives as it stood a frame before, so a kernel can read a measurement such as `.distanceField()`. It is zero on the first frame. [Effects](Docs/Drawing/Effects.md)
- **A sprayed line's `weight` counts under `.perLine` too.** A `SprayLine` or `SprayQuad` under `.perLine(n)` draws its `weight`'s share of `n` points, never fewer than one. The weight used to be ignored there. The default weight of 1 draws what it drew. [Depth of field](Docs/Drawing/DepthOfField.md)

**3D**

- **The procedural sky has its sun.** A `.sky` environment now lights the scene with a sun where it draws its disc, and `castShadows()` throws its shadows. A sketch with a `.sky` and no directional light changes picture. `Environment.sunlight(_:)` decides: `.automatic` yields to a directional light of your own, `.always` never does, and `.off` keeps the sky's glow alone. [3D](Docs/3D/3D.md#sky-sun)
- **The air is the scene's light.** Under a `.sky`, `aerialPerspective()` takes the sky's horizon as its far light, so far ridges fade into the sky behind them. Without a sky, the first directional light's color and intensity scale the haze. [Atmosphere](Docs/3D/Atmosphere.md)
- **A copy's turn is a `Rotation3D`.** `MeshInstance.rotation` is a `Rotation3D` where it was three Euler angles, so a physics body's `rotation` places a copy directly. `.aboutY(a)` spins about y. `Rotation3D.euler(x:y:z:)` composes three angles as `rotateX`, `rotateY`, `rotateZ` would, which is what `rotation: Vector3(a, b, c)` meant. `SurfaceSample.alignment(spin:)` returns one too. [Instancing](Docs/3D/Instancing.md#meshinstance)
- **The live window marches a volume by `volumetricQuality`.** A volume takes one and a half steps per sample spacing at the default, one at `.performance`, and two at `.detail`. Every export takes two, which is what every march took before. [Volumes](Docs/3D/Volumes.md)

**Physics**

- **A 3D world that is full says so.** Every call that creates a body in a `World3D` (`addBody`, `addStaticBodies`, `addCharacter`, `addBodies(from:)`, `addVehicle`, `addRagdoll`, `addSoftBody`, `addRope`) throws `PhysicsError.full` once the world holds its `maxBodies`. The first four did not throw before, so every 3D sketch gains a `try` on them, or `try?` in a click handler. [Physics in 3D](Docs/Simulation/Physics3D.md#world3d)
- **One `drag` in both worlds.** A particle and a rigid `Body` now read `drag` alike: the share of speed lost every sixtieth of a second, whatever the frame rate. Particle sketches feel as they did at 60 fps. `World3D` gains a `drag` too, defaulting to the 5% a second every 3D body already lost. [Physics](Docs/Simulation/Physics.md)
- **A rigid 2D body slows more by default.** At the default `drag` it loses 45% of its speed a second where it lost 1%. Set `world.drag = 0` for the old coasting, as the `Physics/Burst`, `Chain`, `Joints`, and `RigidBodies` examples do. A `.kinematic` body is never dragged. [Physics](Docs/Simulation/Physics.md)
- **A body's own `restitution` wins.** The walls of a 2D `bounds` and the 3D `ground` no longer carry the world's `restitution`. A ball given `restitution: 0` no longer bounces off a default floor. A body that named none follows `world.restitution` when it changes. `Body.restitution` is readable and settable in 2D. [Physics in 3D](Docs/Simulation/Physics3D.md)
- **A change to `gravity` wakes settled bodies, and a spin is not capped.** A tilt now reaches a box asleep on the floor, and an `angularVelocity` of 100 rad/s reads back as 100. [Physics in 3D](Docs/Simulation/Physics3D.md)
- **`substeps` in both worlds.** Cut a step into pieces where a joint's loss shows. A bob on a rod swings back to 70% of its height at one piece a frame and 98% at sixteen. The default, 1, changes nothing. A physics snapshot carries `drag` and `substeps`, and the three formats before it still read. [Physics in 3D](Docs/Simulation/Physics3D.md)

**Sound**

- **Every blown tube speaks from pressure 0.3.** A note's start moved with its tube and pitch, so the clarinet spoke only from about 0.6. Every note now starts at 0.3, and full pressure blows what it always did. A sweep written for the old dial swells sooner. [Physical models](Docs/Helpers/Synthesis.md)
- **A `Limiter` listens ahead, and its sound leaves 5 ms later.** It used to flatten every crest over the ceiling. It now listens `Limiter.lookahead` ahead, so the wave keeps its shape and nothing crosses the ceiling. [Synthesis](Docs/Helpers/Synthesis.md)
- **`Delay` holds its settings to their ranges.** `time` is held to `0...2` seconds (`Delay.maxTime`), `feedback` to `0...0.95`, and `mix` to `0...1`, at init. A time of 3 s used to read back as 3 and echo at 2. It reads back as 2 now. [Synthesis](Docs/Helpers/Synthesis.md)

**Export and output**

- **A wide frame's files keep their depth.** A `.wide` or `.extended` PNG is written at 16 bits a channel under the Display P3 curve. It was 8 bits under a linear profile. A HEIC's picture is 10 bits, up from 8. A `.wide` video stays 8 bits and now takes a standard frame's dither. [Color output](Docs/Drawing/ColorOutput.md)
- **A see-through still stores its color as drawn.** A PNG of a `background(.clear)` canvas keeps each pixel's color beside its coverage, no longer scaled by it. `OllinApp.image(of:)` of such a canvas is tagged `CGImageAlphaInfo.first`, straight alpha, where it was `premultipliedFirst`. Code that reads the bytes itself reads the color as drawn. [Export](Docs/Output/Export.md)

**Parameters and the live window**

- **Timeline edits undo.** ⌘Z while the timeline panel is in front puts the last edit back, and ⇧⌘Z redoes it. A drag is one step. Clicking a key moves the playhead onto it, a scrub near a key snaps to it, and the footer names a selected key's value.
- **The keyframe diamonds make one column, and come with the panel.** Every inspector row's diamond sits at the trailing edge, after its control. With the Timeline panel closed, only a parameter a track or a rule already drives keeps its mark.

### Fixed

**Drawing**

- **A sprayed line in focus keeps its light.** An in-focus line piles its points onto a few pixels, and an `Accumulator` lost most of that light once they were bright. Every `LineSpray`, and `drawParticles(_:style: .light)` alone in a `withAccumulator` block, now keeps all of it, so dense in-focus lines come out brighter. [Depth of field](Docs/Drawing/DepthOfField.md)
- **A line with no light costs nothing in a spray.** A `SprayLine` dark at both ends, or a `SprayQuad` with no light, gets no points, and under `.byLength` the lit ones share the whole pass. A spray whose pieces all go dark now develops dark, where it kept its last picture. [Depth of field](Docs/Drawing/DepthOfField.md)

**3D**

- **A still 2D line stays crisp under temporal anti-aliasing.** In the live window, a one-pixel 2D line drawn into a 3D canvas was smeared across three columns with the camera still. 2D over a background color now passes through exactly as drawn. [3D](Docs/3D/3D.md)
- **The sky turns with the camera.** A turning camera smeared an environment's sky under `temporalAntialiasing()`, left it unstreaked under `motionBlur()`, and warped it under `temporalUpscaling()` and `frameInterpolation()`. The backdrop now turns with the camera, and a bright disc it passes no longer rings into a halo. A plain `background(_:)` is unchanged. [3D](Docs/3D/3D.md)
- **A mover's edge streaks with it.** Under `motionBlur()`, a pixel that a `withMotion` mover half covered took the background's motion, so the mover's edge stayed sharp. A pixel the mover covers at all now carries its motion. [3D](Docs/3D/3D.md)
- **`withMotion` keeps its drawing state inside the block.** It saves and restores the transform and style as `withState` does, so `withMotion { translate(x, y, 0); drawMesh(box) }` in a loop places each box from the origin. Each `translate` used to add to the last, which marched a grid of boxes off screen. [3D](Docs/3D/3D.md)
- **A white surface sends back the light that reaches it.** A white plate with a physically based gloss sent back up to 135% of the light that fell on it under lamps. It now returns the light within half a percent at every angle. Floors seen low and glancing read a little darker and glossier. [3D](Docs/3D/3D.md)
- **A panel's traced shadow is the share of its light the blocker stops.** The floor under a blocker's edge kept more than twice the light that arrives there. The near part of a panel now weighs more than its far part. [3D](Docs/3D/3D.md)
- **A pane of index 1 changes nothing in the path-traced export.** A ball seen through clear glass of the air's own index read 8 to 12% brighter than without it. It now reads the same. [Path-traced export](Docs/Output/PathTraced.md)
- **A picture shows in a traced mirror and through traced glass.** A mesh drawn with `Mesh.textured` showed as its plain fill in a ray-traced reflection and through traced glass. A traced hit now reads the picture, from a loaded image or a layer's `image`. Its other maps still show only on the surface. [3D](Docs/3D/3D.md)
- **A floor gathers the whole sky.** Floors under a sky or a loaded map came out dim: 3 to 8% under a clear procedural sky, 14% under a hazy one. A floor now gathers the sky's light within 2% on a clear day. [3D](Docs/3D/3D.md)
- **Two volumes over one box composite in call order.** When two volumes sat the same distance from the eye, an absorbing medium drawn over a glow could land under it. The later `drawVolume` is now on top. [Volumes](Docs/3D/Volumes.md)
- **A glowing surface lights its neighbors.** The bounce now carries a surface's glow (`Mesh.glowing`, an emissive color). A glowing slab lights the floor under it, as it does in the path-traced export. [3D](Docs/3D/3D.md)
- **A metal bounces its own color.** Under `globalIllumination()` a copper wall throws copper onto what faces it. A physically based wall used to bounce about three times its share of light. The standard finish is unchanged. [3D](Docs/3D/3D.md)
- **An export's bounce reaches its depth in a light room.** A white room's bounced light came out too dim in an export. Exports and snapshots with the bounce on now render brighter in light rooms. [3D](Docs/3D/3D.md)

**Physics**

- **A dense pile of 3D bodies no longer stops the sketch.** A box packed among others could trip an assert and end the process. The world now holds sixteen touching pairs a body, and a step that still drops contacts says so in `World3D.lastError`. `maxBodies` reads back what the world was made with. [Physics in 3D](Docs/Simulation/Physics3D.md)

**Sound**

- **A plucked string rings for its `decay` at every pitch.** A high note rang a fraction of the time it was given: the steel string's 3.6 s was 0.64 s at MIDI 93. Every note now rings for its `decay`, through Jaffe and Smith's decay stretching near the top. [Physical models](Docs/Helpers/Synthesis.md)
- **A lifted bow lets the string ring.** At pressure 0 the bow sat on the string and muted it within a tenth of a second. It now leaves the string over the bottom tenth of `pressure`, so the string rings for its `decay`. [Physical models](Docs/Helpers/Synthesis.md)
- **A blown tube holds no offset.** What a tube sent out sat below zero by up to 0.17 at every pressure under full, which ate headroom in a mix. [Physical models](Docs/Helpers/Synthesis.md)
- **The four built-in rooms are four rooms.** On macOS 27, `Reverb(.room)`, `.hall`, `.plate`, and `.cathedral` all sounded as the same medium hall. Each now loads its own settings, so a hall and a cathedral have their long tails. [Synthesis](Docs/Helpers/Synthesis.md)
- **A distortion at mix 0 passes the sound unchanged.** The unit still colored what it passed at mix 0. It now steps aside, as a flat equalizer does. [Synthesis](Docs/Helpers/Synthesis.md)

**Export and output**

- **An export no longer writes a frame the GPU threw away.** A frame the GPU discarded, after another program's fault, was written half drawn. It is now drawn again, up to twice. One that builds on the frame before (`noClear()`, a persistent layer, a simulation, `--subframes`) stops the export with an `unrendered` error. [Export](Docs/Output/Export.md)
- **A gain map keeps a highlight's edge.** A HEIC rebuilt a highlight's edge up to 38% off. The edge now rebuilds within about 2% of the rendered frame, or 4% for a frame past about 1.5 million pixels. [Color output](Docs/Drawing/ColorOutput.md)
- **A black ground separates to black alone.** A black background in `separated(into: [.black, .fluorescentPink])` laid solid pink under the black, in either ink order. A tie now goes to less ink. [Print separations](Docs/Output/PrintSeparations.md)
- **An absolute proof shows the paper, and the paper is the stock's.** An absolute `SoftProof` of white came out cyan, and the simulated paper far yellower than the press profile's own stock. White now proofs as the stock. An `.absolute` proof shows the paper whether or not `simulatesPaper` is set. Relative and perceptual proofs are unchanged. [Print color](Docs/Output/PrintColor.md)
- **A video started before an export plays in it.** A `VideoPlayer` told to `play()` in a property's initializer held its first frame for a whole export. The play now carries over to the export's clock. `Examples/Vision/OpticalFlow` is rendered again.

**Parameters and the live window**

- **The timeline's authoring loop works as written.** A parameter changed while the clock is held shows at once. The diamond on a key re-keys a changed value, where it removed the key. An edit made with the panel closed lands where the clock stands. The panel takes its first click as a drag.

**Examples**

- **`ObjectTracking` follows something with no camera.** With no camera it tracked a still photograph. It now plays the bundled dance film and takes its first lock from a `FaceTracker` box. The Vision reference listed a `stop()` the tracker does not have: the call is `stopTracking()`.

## [0.15.0] - 2026-10-12

This release adds curves you can ask where they cross, a shader as paint, volumes, layer styles, lofting, and hidden-line solids. An export can blur motion from subframes, and a sketch that is a package reloads live. Some fixes change how a camera move, a caustic, or a struck instrument comes out, so read **Changed** and **Fixed** before you update.

### Added

**Drawing**

- **Segments, arcs, and ellipses as values.** `LineSegment`, `Arc`, and `Ellipse` join `Circle` and `Rectangle` as values a sketch holds. Each knows its length or perimeter, its area, its bounds, and the point on it nearest to another. `drawLine(_:)`, `drawArc(_:mode:)`, and `drawEllipse(_:)` draw them. [Geometry](Docs/Drawing/Geometry.md#plane-curves)
- **Where two curves cross.** Those three, with `Circle`, `Rectangle`, `Triangle`, and `Contour`, share the `PlaneCurve` protocol. `crossings(with:)` returns the points where any two meet, sorted along the shape you asked. [Geometry](Docs/Drawing/Geometry.md#plane-curves)
- **More measures on a circle, a rectangle, and a triangle.** `Circle` gains `area`, `perimeter`, `point(at:)`, `nearestPoint(to:)`, and `distance(to:)`. `Rectangle` gains `area`, `perimeter`, and `edges`, and `Triangle` gains `perimeter` and `edges`. [Geometry](Docs/Drawing/Geometry.md#plane-curves)
- **A shader as paint.** `fill(shader)` and `stroke(shader)` take a `Shader` anywhere they take a color. Its `shade(uv, info)` runs at every pixel the shape covers, where `uv` runs across the shape's bounding box. `info.position`, `info.distance`, and `info.along` place the pixel. `Paint.shader(_:)` carries one as a value. [Color](Docs/Drawing/Color.md#shader-paint)
- **Where a shader paint reaches.** It works on every shape, stroke, curve, and outline text. A mesh under `fill(shader)` takes it as its surface texture. A vector export writes such a shape in middle gray, and a web page export stops and names the call. [Color](Docs/Drawing/Color.md#shader-paint)
- **Smoothing that keeps the points.** `smoothed(neighbors:)` on a `Contour` or a `Shape` moves each point to the average of itself and its neighbors. The outline keeps one point for each it had, so anything keyed to its points stays in step. `weights: .box` is the plain average. [Curves](Docs/Drawing/Curves.md#moving-average)
- **The slope of a fitted field.** `RadialBasis` reports how its field changes. `gradient(at:)` is the way uphill for a field of numbers, and `derivative(at:along:)` works for any field. For a function of your own, `derivative(at:function:)` and `gradient(at:field:)` measure the slope by central differences. [Fitting](Docs/Drawing/Fitting.md#slopes)

**Color and effects**

- **Layer styles.** Six filters give a layer an edge of its own, read from its alpha: `.outline(width:color:align:)`, `.dropShadow(offset:radius:color:)`, `.innerShadow(offset:radius:color:)`, `.outerGlow(radius:color:)`, `.innerGlow(radius:color:)`, and `.bevel(width:depth:profile:angle:elevation:highlight:shadow:)`. They chain like any filter. All six cross to a web page, and so does `.distanceField`, which used to stop the export. [Layer styles](Docs/Drawing/LayerStyles.md)
- **Measuring color.** `distance(to:)` says how different two colors look, in OKLab or by the CIE's 2000 formula with `measure: .ciede2000`. The formula matches the test pairs Sharma, Wu and Dalal published. `CIELab` brings in the Lab numbers swatch books give. `Palette.nearest(to:)` and `nearestIndex(to:)` find the swatch most like a color. [Color](Docs/Drawing/Color.md#measuring)
- **A picture's histogram.** `Image.histogram(of:bins:in:)` counts a picture's pixels by lightness or by one channel, and `percentile(_:)` reads its working black and white. [Color](Docs/Drawing/Color.md#measuring)
- **Shades whose hue drifts.** `Palette.shades(of:count:)` and `Ramp.shades(of:)` build a ramp of one color the way painters shade. The lights turn toward yellow and the shadows toward blue or purple. `hueDrift` sets how far the hue turns, and a negative drift cools the lights. [Color](Docs/Drawing/Color.md#shades)

**3D**

- **Lofting.** `Mesh.loft(_:along:at:smoothed:scale:twist:capped:)` and `drawLoft` build one surface through several flat shapes placed along a 3D path. A bottle runs from a square foot through a round belly to a narrow neck. Sections blend as a smooth curve, or straight from rib to rib with `smoothed: false`. [Sweeps](Docs/3D/Sweeps.md#a-surface-through-several-shapes-lofting)
- **Hidden-line solids.** `featureEdges(creaseAngle:)` draws a mesh as a draughtsman draws a solid. Over the filled faces it strokes only the creases, the boundaries, and the silhouette, at `strokeWeight`. Near solids hide the edges of far ones, and every copy under `drawMesh(_:instances:)` gets its edges. [Hidden-line solids](Docs/3D/HiddenLines.md)
- **Edge weight in world units.** The weight of a hidden-line edge is in canvas points, the same at any distance. `strokeWeight(_:in: .world)` sets it in world units, and `noFeatureEdges()` turns the edges off. [Hidden-line solids](Docs/3D/HiddenLines.md)
- **Volumes.** A `Volume` is a box of density samples, built from a function, a list, or `Volume.noise`. `drawVolume(_:size:medium:)` draws it in a 3D scene as smoke, cloud, fire, or ink. It scatters the scene's lights, shades itself, and takes the shadows solids throw into it. [Volumes](Docs/3D/Volumes.md)
- **What a volume is made of.** A `Medium` sets `density`, `color`, `glow`, `glowIntensity`, and `anisotropy`, with presets `.smoke`, `.cloud`, `.fire`, `.ink`, and `.nebula`. A solid inside a volume is veiled by the medium in front of it, whatever order the calls came in. A web page export names `drawVolume` and stops. [Volumes](Docs/3D/Volumes.md)

**Generators**

- **A turtle you drive from code.** `Turtle` is a pen you walk across the canvas. `forward`, `back`, `left`, and `right` move and turn it, and `penUp` and `penDown` break the line. `pushState` and `popState` draw a branch. `move(to:)`, `home()`, and `heading` place it outright. Each run is a `Contour`, closed after `close()`. [Turtle](Docs/Generators/Turtle.md)
- **Noise in three dimensions that loops.** `noise(x, y, z, loop:)` reads a volume that changes over a lap and comes back exactly to its start. A point cloud's drift then closes a looping export. `signedNoise`, `fbm`, `signedFbm`, `ridgedFbm`, and `turbulence` take the same form. [Noise](Docs/Generators/Noise.md#loop)

**Export and output**

- **Motion blur drawn from subframes.** `--subframes N` draws each exported frame at N moments while the shutter is open and averages them. It blurs anything a sketch draws, at N times the render cost. `--shutter F` sets the opening, else the sketch's own `motionBlur(shutter:)`, else 0.5. In code: `OllinApp.exportSubframes` and `OllinApp.exportShutter`. [Export](Docs/Output/Export.md#motion-blur-from-subframes)
- **What a subframe export asks of a sketch.** At each moment `time` steps through the opening and `deltaTime` is the time since the last draw. `frameCount` counts each moment, so motion counted in frames runs N times as fast. A picture carried between draws, such as a `noClear` pile or a feedback layer, is refused by name. [Export](Docs/Output/Export.md#motion-blur-from-subframes)

**Tools**

- **Live reload for a sketch that is a package.** The live window compiles a sketch with every other `.swift` file of its SwiftPM target, so saving a helper file reloads. `ollin MySketch` runs a package by its folder, and a bare `ollin` runs the one you are in. `--target <name>` picks one sketch of several. [Single-file sketches](Docs/Tools/SingleFile.md#growing-into-a-package)
- **A package's resources in the live window.** The live compile reads `Package.swift`, so a picture in a processed `Images/` folder loads through `.module`. A sketch that imports another target or another package still needs `swift run`, and the error says so. `OllinRun` (the `--installation` host) and `OllinLiveCoding` take a package's folder too. [Single-file sketches](Docs/Tools/SingleFile.md#growing-into-a-package)

**Examples**

- **Anwar Jalal Shemza joins the recreations.** [`Examples/Recreations/AnwarJalalShemza`](Examples/Recreations/AnwarJalalShemza/) is new. `Meem` is the letter he painted from 1964 to 1968, a disc for its head and a line for its tail. `Roots` is his last series: dyed cloth with a flower on top and its roots below as a word in Urdu. Both export SVG.
- **Hiroshi Kawano joins the recreations.** [`Examples/Recreations/HiroshiKawano`](Examples/Recreations/HiroshiKawano/) is new. `Design` walks a grid of five colors with a Markov chain counted off his *Design 3-1* and *Design 3-2*. `ArtificialMondrian` is the series of 1969: two chains lay the black lines, and the regions they close are colored at random.
- **Zdeněk Sýkora joins the recreations.** [`Examples/Recreations/ZdenekSykora`](Examples/Recreations/ZdenekSykora/) is new. `Structure` is the rule he and the mathematician Jaroslav Blažek published in *Leonardo* in 1970 for placing half-disc elements on a grid. `Lines` is a score of chance numbers drawn as tangents joined by arcs. Both export SVG.
- **Eight examples for the features above.** `Shapes/Crossings`, `Patterns/TurtleWalk`, `Shaders/ShaderPaint`, `3D/Geometry/HiddenLines`, `3D/Effects/Volumes`, `Effects/LayerStyles`, `Color/Shades`, and `Motion/ContourWalkers`.

### Changed

Most of these can change what a sketch draws or sounds like, and the first and third can stop one compiling.

- **`ColorVision.matrix` is removed.** Every kind of color vision now has two transforms rather than one. `applied(toLinear:_:_:)` still gives the model's result for a linear color. [Accessibility](Docs/Helpers/Accessibility.md#seeing-your-colors-as-somebody-else-does)
- **The color-vision simulation changed.** At full severity `Color.simulated(_:)` and `Filter.colorVision(_:)` now follow Brettel, Viénot and Mollon (1997). Simulating a simulated color leaves it where it is. A lower severity moves each color that share of the way. Simulated pictures change, the tritan ones most. [Accessibility](Docs/Helpers/Accessibility.md#seeing-your-colors-as-somebody-else-does)
- **`MarkovChain` is in the core.** The chain the music helpers use now lives in `Ollin`, so a drawing sketch can use it without the audio library. A file that imports only `OllinAudio` and uses the chain needs `import Ollin` beside it. `learn(_:after:times:)` takes a table of counts directly. [Composition](Docs/Helpers/Composition.md#markovchain), [Random](Docs/Generators/Random.md#markovchain)
- **2D torque takes points, like force.** `applyTorque` takes a force in points times an arm in points, where it took the engine's newton-meters. A sketch calling it spins about ten thousand times faster at the default scale. Divide its torques by `unitsPerMeter` squared to keep its motion. [Physics](Docs/Simulation/Physics.md#rigid-bodies)
- **The band-pass voice filter is unity at its cutoff.** Resonance now only narrows the band, where the output used to grow with it. A band-pass voice at high resonance plays quieter than before. [Synthesis](Docs/Helpers/Synthesis.md#voicefilter)
- **A caption draws over the finished frame.** `drawCaption` now lands in the overlay. It stays sharp and white over a depth of field, a motion blur, a bloom, or a lens flare, and never joins an accumulating canvas. Inside a layer or a batch recording it draws in place as before. [Text](Docs/Drawing/Text.md#notices)
- **A camera rig's framing follows its arguments.** `cameraShowcase`, `cameraControl`, and `cameraMove` read `target`, `radius`, `elevation`, `azimuth`, and `fieldOfView` on their first call only, so a `@Param` passed in tuned nothing. A changed argument glides the shot there, and the `from:` forms follow. Once the viewer takes the camera, only `resetCamera()` and the idle return move it. [Camera](Docs/3D/Camera.md#showcase)
- **An export's traced soft shadows are smoother and cheaper.** Under temporal anti-aliasing each of the sixteen passes traced the whole ray budget, and now traces its share. The `.detail` tier every export uses takes 64 points on the light, where 16 showed a wide penumbra as steps. `shadowSamples(_:)` still sets an exact count. [3D](Docs/3D/3D.md#soft-shadows)
- **Even spacing on a surface is about three times faster.** `surfacePoints(on:count:)` with its default `.blueNoise` thinning takes about a third of the time, and a debug build gains more. The points are the same for every mesh, count, and seed. [Points on a surface](Docs/Generators/SurfaceSampling.md)
- **A parameter read costs what a stored property costs.** A `@Param` holding a number, an integer, or a switch is now cheap enough to read once per vertex. A color, a vector, a palette, or a text value still reads through a lock, so copy those into a local first. [Parameters](Docs/Helpers/Parameters.md)

### Fixed

**Drawing**

- **A background on the canvas leaves the layers alone.** `background(_:)` outside a layer block used to drop the layers drawn before it. A `withTarget` layer or a `withField` seed drawn first came out empty with no error. It now clears only the canvas, and the order no longer matters. [Effects](Docs/Drawing/Effects.md#withtarget)
- **Exact black and exact white stay exact.** The dither before the 8-bit encode left some pixels of an exact black at 1 and of an exact white at 254. Both ends are now exact in every export and on the web page. Gradients dither as before. [Color output](Docs/Drawing/ColorOutput.md#exports)
- **The blobby cross ends at its tips.** The render drew a faint spike from every tip to the edge of its quad. The spike is gone, and a blobbiness below 0.35 now draws out to its `radius`. [Drawing](Docs/Drawing/Drawing.md#drawblobbycross)
- **A traced SVG outline keeps its sharp corners.** The SVG outline of a curved distance-field shape cut each sharp corner across, by about 2 px on the cut disk and the horseshoe. It now bends through the corner where the two sides meet. [Export](Docs/Output/Export.md#vector-svg)
- **Text along a path fills the glyph the plain run fills.** The same letter carried 4.5% more ink under `drawText(_:along:)` or `perGlyph:` than in a plain run. The two now agree to a level. [Text](Docs/Drawing/Text.md#perglyph)

**3D**

- **An overlay no longer loses the scene under a sky backdrop.** A `withOverlay` block or a caption could cover every surface and keep only the sky and the block. It happened over a scene lit by `environment(.sky(...))`, or by an HDRI with its backdrop shown. [Effects](Docs/Drawing/Effects.md#withoverlay)
- **A camera move starts at its start.** The first frame of a `cameraMove` or `cameraShowcase` move showed it one step in, and two exports at different frame rates disagreed. Frame N now shows the move at N/fps, as `time` reads. Every exported frame of a sketch with a camera move shifts by one step. [Camera](Docs/3D/Camera.md#moves)
- **A move resumed after the hands starts from the hands.** Switching from `cameraControl()` back to the `cameraMove` it left jumped the camera to where the move first started. It now departs from the current pose. [Camera](Docs/3D/Camera.md#control)
- **A motion streak keeps the light of what made it.** Under `motionBlur()` a moving thing grew brighter, and a sharp ghost of it showed inside its own streak. Both are gone. A caption drawn over the 3D scene takes the motion of the surface under it, so draw it in `withOverlay { }`. [3D](Docs/3D/3D.md#motion-blur)
- **A caustic gives back the light its shadow took, and no more.** A clear glass ball's caustic added half again the light its shadow removed. Caustics are now dimmer on a physically based floor, and `caustics(intensity:)` above 1 turns them up past physical. [Caustics](Docs/3D/Caustics.md#casts)
- **A lamp's caustic carries the lamp's light.** Under a point or spot light, a ball's caustic gave back a third of what its shadow took. It now gives back what the shadow took, and a lamp's `reach` thins its caustic as it thins its light. A live caustic no longer dims for its first frames. [Caustics](Docs/3D/Caustics.md#casts)
- **A traced shadow's softness no longer follows the camera.** A traced point light's penumbra changed with where the camera aimed, so it breathed through a camera move. It now holds still. [3D](Docs/3D/3D.md#soft-shadows)
- **A light's reach holds in the bounce and in the trace.** Global illumination and the path tracer now read a lamp's `reach:` as its direct light does. A lamp lights and bounces nothing past it. [3D](Docs/3D/3D.md#reach)
- **A sun brighter than a half float arrives whole.** An HDRI's sun of 200,000 was clamped at 65,504 on decode and delivered a third of its light. It now lights what its pixels say. [3D](Docs/3D/3D.md#environment)
- **The probe grid keeps its planes off a scene's faces.** Global illumination put a ragged dark seam on a room's open end. The seam is gone, and a room no longer has to run past the camera to avoid it. [3D](Docs/3D/3D.md#global-illumination)
- **A sweep's caps meet its walls point for point.** So do a loft's. A straight side with several points along it no longer fills its cap with slivers. [Sweeps](Docs/3D/Sweeps.md)

**Sound**

- **A sound export finds every instrument, on time, at the right level.** An instrument held in a struct, an array, an optional, a dictionary, or the sketch's own object is found. A note no longer lands a frame late. A change of `hearingDistance` reaches the file, and `unplace()` no longer leaves a sound 6 dB down. [Synthesis](Docs/Helpers/Synthesis.md#sound-in-an-export)
- **A struck body no longer clips, and `hardness` colors the strike.** A softer strike now reaches fewer tones, where it pushed the same tones harder. The default `hardness` of `ModalBody`, `ModalBody(shape:)`, and `StruckShape.body` moves from 0.7 to 0.85. A struck instrument plays a little quieter and much cleaner, so raise its gain to keep an old balance. [Synthesis](Docs/Helpers/Synthesis.md#a-struck-body)
- **The struck presets strike harder.** Their `hardness` is now 0.9 for `.bell` and `.bar`, 0.85 for `.drum` and `.plate`, and 0.8 for `.glass`. Every preset but `.wood` used to clip through its attack. The struck `Voice` presets (`.drum`, `.bar`, `.chime`, `.glass`) carry gain 1, within 3 dB of `.pluck` at the same velocity. [Synthesis](Docs/Helpers/Synthesis.md#a-struck-body)

**The reference**

- **The reference no longer promises what the code does not do.** The pages on sound, color output, and physics now state the real limits. A plucked string's `decay` is shorter at high notes, `Delay.time` runs up to 2 s, and a particle's `drag` is taken once a step.
- **Known gaps in photoreal 3D are written down.** Fourteen stand as known issues with their numbers in `CAPABILITIES.md`. The 3D reference no longer promises that emitters light their neighbors under global illumination, which they do in a path-traced export.

## [0.14.0] - 2026-10-06

This release adds depth of field on the canvas, lines in 3D, sweeps along a path, and an overlay over the finished frame. The path-traced export gains a time budget, frames carried through a sequence, and pixels that stop once they settle. Several looks moved, the `.defocus` filter's most of all, so read **Changed** before you update.

### Added

**Drawing**

- **An overlay over the finished frame.** `withOverlay { }` draws its block last, after temporal anti-aliasing, the lens effects, and the `postProcess` filters, so a caption stays sharp and untinted. Over a `noClear()` canvas it never joins the pile. [Effects](Docs/Drawing/Effects.md#withoverlay_)
- **Part of an image.** `drawImage` takes a source rectangle in the image's own pixels, so one cell of a sprite sheet draws with no cropping first. Write `drawImage(sheet, x, y, width, height, sourceX, sourceY, sourceWidth, sourceHeight)` or `drawImage(sheet, in: box, source: cell)`. [Images](Docs/Drawing/Images.md#part)
- **A long exposure in single precision.** `noClear(precision: .float32)` keeps the canvas in single precision, so a pile of very faint marks keeps adding where a half-float canvas levels off. [Accumulation](Docs/Drawing/Accumulation.md#noclear)
- **Trails as the base of a combine.** `Feedback`, `Accumulator`, and `SimField` take `combined(with:_:)` beside `filtered(_:)`, so trails can be masked or displaced by another layer directly. [Effects](Docs/Drawing/Effects.md#feedback)

**3D**

- **Depth of field on the canvas.** `depthOfField()` blurs the finished 3D frame by its depth through the camera's lens: `Camera3D.aperture`, `focusDistance`, and `apertureBlades`. A highlight opens into an even disc the shape of the iris. `focusRange`, `maxBlur`, and `quality` tune it, and `noDepthOfField()` turns it off. [3D](Docs/3D/3D.md#depth-of-field)
- **Depth of field beside the other lens effects.** `depthOfField()` runs after temporal anti-aliasing and before motion blur, so all three work together. A `--path-traced` export skips it, since the traced frame has already come through the lens. [Path-traced export](Docs/Output/PathTraced.md#what-the-traced-frame-adds)
- **Lines in 3D.** `drawLine` and `drawPolyline` take `Vector3` points and draw through the camera with the 2D stroke's weight, joins, and caps. Every point keeps its depth, so a solid in front hides the line. `drawPolyline(_:colors:closed:)` colors each point. [Lines in 3D](Docs/3D/Lines.md)
- **Line weight in scene units, axes, and a grid.** `strokeWeight(0.05, in: .world)` sets a weight in the scene's units, which thins a line as it recedes. `drawAxes(length:)` and `drawGrid(size:divisions:)` are built from the same lines. The example is [`Examples/3D/Geometry/FieldLines`](Examples/3D/Geometry/FieldLines/).
- **A path through space.** `Curve3D` is a path, open or closed, kept as points or threaded smoothly through a few with `Curve3D(curveThrough:closed:segments:)`. `point(at:)` and `frame(at:)` walk it by length. Its frames never twist about the path, so `rotate(frame.rotation)` faces a rider along it. [Sweeps and strips](Docs/3D/Sweeps.md#a-path-through-space)
- **Sweeps and strips.** `Mesh.sweep(_:along:scale:twist:capped:)` carries a `Shape` along a `Curve3D`, sized and turned along the way. `Mesh.strip(between:and:colors:closed:)` is the ribbon between two lines. `drawSweep` and `drawStrip` are the bare calls. [Sweeps and strips](Docs/3D/Sweeps.md)
- **An even pace along a curve.** `Pace` walks a curve written as a function at one speed, with `Pace(byLengthOf:period:)`. `Pace(byAreaBetween:and:period:)` walks the strip between two such curves at one rate of area. Both keep counting periods, so a loop never jumps. [Sweeps and strips](Docs/3D/Sweeps.md#an-even-pace)
- **Instanced copies that move.** `drawMesh(_:instances:)` inside `withMotion` follows every copy from last frame's place to this one's. Temporal anti-aliasing keeps each copy's edges, and motion blur streaks each along its own path. Copies placed by a compute buffer or a `MeshField` keep the camera's motion only. [Instancing](Docs/3D/Instancing.md#motion)

**Geometry**

- **The regions a drawing encloses.** `regions(enclosedBy:)` cuts a set of outlines where they cross and returns every patch the lines wall off as its own `Shape`. `Circle.contour(segments:)` and `Rectangle.contour` turn those values into outlines. The example is [`Examples/Shapes/ColoringBook`](Examples/Shapes/ColoringBook/). [Geometry](Docs/Drawing/Geometry.md#regions)
- **Points in the order of a Hilbert curve.** `hilbertOrder(of:)` and `hilbertSorted(_:)` sort points along a space-filling curve, so one line through a stipple stays local. `hilbertIndex(of:in:level:)` is one point's place on the curve. The example is [`Examples/Images/HilbertLine`](Examples/Images/HilbertLine/). [Hilbert order](Docs/Generators/HilbertOrder.md)

**Path-traced export**

- **A traced frame on a time budget.** `--path-traced --pt-seconds 10` gives each frame ten seconds in place of a sample count. The recipe records the count reached, so the frame reproduces from it. `--pt-min` is a floor the clock may not cut under. In code, `PathTracing.secondsPerFrame`. [Path-traced export](Docs/Output/PathTraced.md#a-time-budget-a-frame)
- **A traced sequence carries its earlier frames.** `--path-traced 32 --pt-reuse 8` carries up to eight frames' worth of samples into each frame of a sequence or video export. A sequence at 32 samples a frame then shows the grain of 256. In code, `PathTracing.reusedFrames`. [Path-traced export](Docs/Output/PathTraced.md#earlier-frames-carried-reuse-across-a-sequence)
- **A bound on bounced light.** `--path-traced 256 --pt-clamp 4` holds light that has bounced twice or more at four times white. A polished scene's fireflies go, and what one bounce shows is never touched. In code, `PathTracing.maxBounceLight`. [Path-traced export](Docs/Output/PathTraced.md#a-bound-on-what-one-bounce-may-carry)
- **A traced pixel stops once it has settled.** `--path-traced 512 --pt-noise 0.01` lets each pixel end early once its grain falls under the figure. The count becomes the most a pixel may trace, and `--pt-min N` raises the least. In code, `PathTracing.noiseThreshold` and `minSamplesPerPixel`. [Path-traced export](Docs/Output/PathTraced.md#fewer-samples-where-the-picture-has-settled)

**Tests**

- **Light and sound are tested against physics.** Thirty-two tests state what must hold whatever the code does: a shadow only takes light, and a plucked string only loses energy. Four measured gaps stand as known issues: a caustic's light, motion blur at a full shutter, the color-vision simulation, and a CMYK proof proofed twice.

**Examples**

- **Kazuya Sakai joins the recreations.** [`Examples/Recreations/KazuyaSakai`](Examples/Recreations/KazuyaSakai/) has `Ondulaciones`, after the series of 1975 and 1976: a ribbon of hard-edge bands that wraps disc after disc. `RightOff`, after the painting of 1973, sets horizontal bands under navy suns ruled with white rings. Both export as outlines.
- **Saloua Raouda Choucair joins the recreations.** [`Examples/Recreations/SalouaRaoudaChoucair`](Examples/Recreations/SalouaRaoudaChoucair/) follows her modular sculptures. `Poem` cuts a block into verses that lift apart and set back, after *Poem*, *Infinite Structure*, and *Poem of Nine Verses*. `Duals` cuts a block into two parts that slide apart and lock, as in the *Repetitive Dual*. `Poem` exports with `--export-usdz` and `Duals` with `--export-svg`.

### Changed

Each of these can change what a sketch draws or exports.

- **`.defocus` blurs as the canvas lens does.** It now runs the same passes as `depthOfField()`, with `focus`, `range`, `irisAngle`, and `catsEye` as before. A near highlight opens into an even disc. The blur now grows with distance all the way to the depth map's ends, reaching `maxBlur` there. Every defocused layer looks different. [3D](Docs/3D/3D.md#depth-of-field)
- **An export holds a sketch that stopped its loop.** After `noLoop()`, an export used to call `draw()` for every frame up to the one asked for. Now the frame the loop stopped on is the picture from then on, as in the window. A replayed take still draws every frame. [Sketch](Docs/Core/Sketch.md#noLoop)
- **A closed contour's walk wraps.** On a closed contour, `Contour.point(at:)`, `tangent(at:)`, `normal(at:)`, and `piece(from:to:)` now wrap a fraction past 1 where they clamped it. `point(at: 1.25)` is a quarter of the way round again. An open contour still clamps. [Geometry](Docs/Drawing/Geometry.md#contour-questions)
- **A filter over a single-precision layer keeps single precision.** A filter or a combine over a layer made with `precision: .float32` used to write a half-float layer. A far distance field came back rounded to whole pixels. Precision now follows the layer through the chain. [Effects](Docs/Drawing/Effects.md#rendertarget), [Measured distance fields](Docs/Drawing/DistanceFields.md#how-far)
- **A tube's rings turn a little.** `Mesh.tube(along:)`, and the helix and torus knot built on it, now place their rings on `Curve3D`'s frames. On the built-in helix and torus knot the rings turn by under two degrees, and the first ring starts where it did. [3D](Docs/3D/3D.md#solid-primitives)
- **A curved polished surface traces with less grain.** A traced pixel now reads a curved mirror over its whole footprint. A field of small polished beads, grainy at any count before, renders at 128 samples with a quarter of the spread per sample. A flat mirror reads as before. [Path-traced export](Docs/Output/PathTraced.md#a-pixels-worth-of-a-curved-surface)
- **A scene nests four times deeper.** A glTF or USD node tree reads to 256 levels, up from 64. A value nested inside a USD file keeps a limit of its own, 64 levels. [Scenes](Docs/3D/Scenes.md#loading)
- **The frame recipe names the framework's commit.** Beside `git`, the sketch package's commit, an exported frame's recipe carries `ollin`, the framework's own. Each ends in `-dirty` when its tree has changes. [Export](Docs/Output/Export.md#reproducibility-metadata)

### Fixed

- **A tap no longer crashes after minutes of use.** A video's soundtrack tap, a camera or screen frame tap, a listening hub's tap, and a custom effect's process each overflowed its stack within minutes. They now run for as long as the sketch does. [Video](Docs/Video/Video.md)
- **The physics solver refuses a number it cannot hold.** A position, a force, or a gravity that is not a number, or is infinite, used to stop a debug build. Each is now refused, in 2D and 3D, and the world prints one note naming the call. [3D physics](Docs/Simulation/Physics3D.md), [2D physics](Docs/Simulation/Physics.md)
- **The traced lens focuses where `focusDistance` says.** The path tracer measured the focus from the near plane and blurred too widely. It now measures from the eye, as the canvas lens does. Every traced frame with an aperture changes. [Path-traced export](Docs/Output/PathTraced.md#what-the-traced-frame-adds)
- **A mover behind instanced copies no longer streaks through them.** A `withMotion` mover behind a field of instanced copies wrote its motion through them, where temporal anti-aliasing and motion blur read it. Every instanced draw now hides what stands behind it. [Instancing](Docs/3D/Instancing.md)
- **A cat's-eye opening keeps a disc's light.** With `catsEye` above zero, a `.defocus` disc carried only the clipped opening's share of its light, which left a step at its silhouette. The opening now changes a disc's shape and never its light. A `catsEye` of 0 is unchanged. [3D](Docs/3D/3D.md#depth-of-field)
- **An EXR's coverage stays at one.** An opaque canvas lit by two added coats wrote an alpha of 3 into `--export-exr`, which a compositor reads as a pixel covered three times. The alpha channel now stops at 1, and the light stays as it summed. [Export](Docs/Output/Export.md#linear-frames-exr)
- **An export that reads a detector repeats.** A tracker's reading used to land whenever its analysis finished, so an export changed from run to run, or the detector never answered. During an export every frame a source offers is now analyzed before the sketch draws. A long `TrajectoryTracker` export can still find a different arc. [Vision](Docs/Vision/Vision.md#frame-sources)
- **A playing video feeds its trackers in an export.** A playing `VideoPlayer` hands each new frame to its trackers during an export, where they read nothing before. `--settle` no longer has to wait out a model. [Vision](Docs/Vision/Vision.md#frame-sources)

## [0.13.0] - 2026-10-02

This release adds a radius for each corner of a rectangle, a gradient that sweeps around a point, and three filters. A still sketch can redraw on demand, and a tuned parameter can be put back from the inspector. Some calls now throw and one-coordinate noise draws a new curve, so read **Changed** before you update.

### Added

**The sketch and its input**

- **A still sketch that answers.** `redraw()` draws one more frame of a sketch that has stopped looping. A `noLoop()` sketch can change what it shows on a click or a key and cost nothing between them. [Sketch](Docs/Core/Sketch.md#redraw)
- **Knowing an export.** `isExporting` is true for the whole of any export and false in a window and under `--bench`. A sketch that spreads slow work over live frames can do all of it at once when every frame is written. [Sketch](Docs/Core/Sketch.md#isExporting)
- **The pointer's shape.** `pointerShape(_:)` gives the pointer over the canvas one of the system's shapes (`PointerShape`: a crosshair, open and closed hands, and nine more). `hidePointer()` and `showPointer()` take it away and bring it back, over the canvas only. [Input](Docs/Helpers/Input.md#pointer)
- **The open panel and the clipboard.** `chooseFiles(withExtensions:allowsMultiple:)` shows the open panel without stopping the frames. The pick arrives as `String` paths through `chosenFiles()` and the `filesChosen()` hook. `copyFrame()` puts the frame the window shows on the clipboard as a PNG. [Input](Docs/Helpers/Input.md#chooseFiles), [Recording](Docs/Output/Recording.md#copyFrame)

**Drawing**

- **A radius per corner.** `drawRect(_:cornerRadii:)` rounds each corner of a rectangle by its own radius, on every anchor `cornerRadius:` takes and on `drawRects`. Write `CornerRadii.top(20)` for a tab, `.bottom`, `.left`, or `.right` for the other pairs, or name all four. [Drawing](Docs/Drawing/Drawing.md#rect)
- **Four radii in a field and on paper.** `SDF.rect(width:height:cornerRadii:)` and `SDF.square(_:cornerRadii:)` carry the four radii into merged fields. The dashed outline and the hollow band follow them, and the SVG and PDF exports write an arc at each rounded corner. [Drawing](Docs/Drawing/Drawing.md#rect)
- **A gradient that sweeps around a point.** `Gradient.conic(center:startAngle:)` lays a ramp once around a center, for a color wheel, a dial, or a pie. It crosses to the web page, and the vector exports write the ramp's midpoint color. An along-path fill no longer shades backwards across its seam. [Color](Docs/Drawing/Color.md#gradient)

**Effects**

- **Three more filters.** `.channelMixer(_:)` runs a `ColorMatrix` over a layer: `.gray`, `.gray(red:green:blue:)`, `.swapping(.red, .blue)`, or a matrix built row by row. `.lensDistortion(amount:quartic:center:fillsFrame:)` bends a layer into a barrel or a pincushion. `.cornerPin(topLeft:topRight:bottomRight:bottomLeft:)` lays a layer onto four points. All three cross to the web page. [Effects](Docs/Drawing/Effects.md#color--tone)
- **A generator's plane as a value.** `ComplexPlane` is the framing every picture of the complex plane shares: `center` in the middle, `span` units across the shorter side, the imaginary axis up. `ComplexPlane(center:zoom:)` takes a generator's `zoom`. [Effects](Docs/Drawing/Effects.md#generate_-and-generator)
- **A number marked on a generator's picture.** A generator's `plane` hands its own framing back. `plane.canvasPoint(of: c, in: bounds)` marks a number on the picture, and `plane.planePoint(at: mouse, in: bounds)` reads the number under the pointer. [Effects](Docs/Drawing/Effects.md#generate_-and-generator)

**3D**

- **Spherical coordinates.** `spherical(azimuth, elevation, radius, around:)` is `polar` in 3D, the angles first, in the camera's own orbit convention. A `Vector3`'s `azimuth` and `elevation` read the angles back. [Math](Docs/Helpers/Math.md#spherical)
- **One mesh from several.** `Mesh.joined(_:)` lays parts end to end as one mesh with no boolean, and `placed(_:)` bakes a `MeshInstance` placement into a part first. The result renders as its parts would under `drawMesh`, in one draw call. `union(_:)` stays the answer for a watertight print. [3D](Docs/3D/3D.md#join)
- **Motion for a mesh that changes shape.** `drawMesh(_:previous:)` takes last frame's vertex positions, so a ribbon rebuilt every frame or a cloth is followed vertex by vertex. `temporalAntialiasing()` keeps its edges refined and `motionBlur()` streaks it where it bent. `withMotion { }` still covers a mesh that moves whole. [3D](Docs/3D/3D.md#drawmesh_previous)
- **A surface that glows in its own colors.** `MeshMaterial.emissiveIntensity`, set on a copy by `Mesh.glowing(_:)`, adds the surface's own color as light, so a vertex-colored mesh glows in each vertex's hue. It adds to `emissiveColor`, works with no lights, and traces in a path-traced export. [3D](Docs/3D/3D.md#meshglowing_-and-meshmaterialemissiveintensity)
- **The environments on a menu.** `Environment` conforms to `ParamChoices`, so `@Param var surroundings = Environment.studio` gives the inspector a menu of the twenty built-in environments. A `.sky(...)` or a built-in with `lightingOnly()` applied is off the menu, so apply the modifier where the sketch uses it. [3D](Docs/3D/3D.md#the-built-in-environments)

**Geometry and simulation**

- **Points inside a shape.** `randomPoints(in:count:)` scatters points evenly over a `Shape`'s fill, holes left out. `randomPoints(along:count:)` scatters them along the outline, and `poissonDisk(in:radius:)` is the blue-noise form kept inside the shape. All three run on the sketch's seeded `random`. [Geometry](Docs/Drawing/Geometry.md#shape-points), [Blue noise](Docs/Generators/BlueNoise.md#shape)
- **The metaball curve on its own.** `Metaballs.falloff(distanceSquared:radius:)` is the bump one ball is made of: 1 at the center, a half at the radius, 0 from twice the radius out. `Metaballs.Ball.value(at:)` is one ball's own contribution, so a sketch can shape its own blobs. [Isosurfaces](Docs/Generators/Isosurface.md#metaballs)

**Connections**

- **The pitch wheel as a parameter.** `MIDIInput.bindPitchBend(to:channel:travel:)` drives a `@Param` from the wheel, the middle of its range at rest. `travel: 0...1` spends the whole range on an upward bend. `pitchBend(channel:)` reads the wheel from -1 to 1, and `unbindPitchBend(channel:)` lets go. A per-note controller's bends stay in `heldNotes`. [MIDI](Docs/Integration/MIDI.md#binding-to-a-param)

**Parameters and the live window**

- **Putting a parameter back.** A parameter tuned in the inspector goes back to the value its `@Param` line declares, with no reload and no `setup()`. Click the dot after its name, or choose *Reset* in the row's menu or on a group card. *Reset all* sits beside the save button. [Parameters](Docs/Helpers/Parameters.md#reset)
- **A reset from code.** `Param.reset()` and `Sketch.resetParameters(named:)` put values back, and `declaredValue` reads what the line gave the parameter. The remote surface has a *Reset all* of its own (`RemoteReset` on the wire). A host passes a `ParamResetAction` as the new `reset:` argument of `ParametersListView(parameters:sketchName:onChange:save:reset:)`. [Parameters](Docs/Helpers/Parameters.md#reset)

**Examples**

- **Alma Thomas joins the recreations.** [`Examples/Recreations/AlmaThomas`](Examples/Recreations/AlmaThomas/) follows the paintings of 1966 to 1972, built from separate strokes of a flat brush. `Rings` is after *Resurrection* and *The Eclipse*. `Columns` is after *Snoopy Sees Earth Wrapped in Sunset*, *Earth Sermon*, *Mars Dust*, and *Starry Night and the Astronauts*. Both use `strokeBrush`, and `--export-svg` gives each stroke as an outline.

### Changed

The entries under **Drawing and export** can stop a sketch from compiling or change what it draws.

**Drawing and export**

- **The headless picture calls throw.** `image(of:)`, the four `contactSheet(of:)` forms, `plates(of:)`, and `separations(of:)` now throw an `ExportError`, where they answered `nil` and printed a line. Their values are no longer optional. `if let frame = OllinApp.image(of: sketch)` becomes `let frame = try OllinApp.image(of: sketch)`, or `try?` for the old answer. [Export](Docs/Output/Export.md#when-an-export-fails)
- **What the thrown error says.** `OllinApp.image(of:)` throws kind `unrendered`, with the renderer's own message and an empty `path`, when the renderer will not start. A sweep over an undeclared parameter, an empty seed or value list, or a separation missing its inks or printing condition throws `unsupported`. `exportWidget` throws when no picture draws. [Export](Docs/Output/Export.md#when-an-export-fails)
- **One-coordinate noise is a field of its own.** `noise(x)`, `signedNoise(x)`, `fbm(x)`, `ridgedFbm(x)`, and `turbulence(x)` ran dead flat across some cells. They now read a one-dimensional field, as `noiseField()` and a formula's `noise` do at y 0 and z 0. The same seed gives a different curve of the same character. The two- and three-coordinate forms are untouched. [Noise](Docs/Generators/Noise.md)
- **A color outside sRGB reads the components the system gives it.** A component below zero of a `Color(displayP3:green:blue:)` now follows the convention `NSColorSpace.extendedSRGB` uses. A sketch that reads such a color's components back sees new numbers. `displayP3Components`, `Color(linear:)`, and `linearRGB` still round-trip, and a color inside sRGB is untouched. [Color output](Docs/Drawing/ColorOutput.md)

**Tools and the inspector**

- **A generated project says sketch.** `ollin new`'s sample name is `MySketch` (it was `MyPiece`). A widget project's one public line is `Door.swift`, declaring `<Name>Door` (it was `Piece.swift` and `<Name>Piece`). A project already generated keeps its own names. [Project generator](Docs/Tools/ProjectGenerator.md), [Widget](Docs/Output/Widget.md)
- **Two more places say sketch.** The generator's menu-bar kind is titled *Menu bar strip*, and the installation supervisor's log lines say "the sketch" where they said "the piece". [Installation](Docs/Output/Installation.md)
- **The extension starter's filter is `cornerShade(amount:)`.** `ollin new --kind extension --seam filter` wrote a `Filter.vignette(amount:)` beside the built-in `vignette(amount:radius:softness:)`, so the starter's own `.vignette()` call was ambiguous. It now writes `cornerShade(amount:)`, called as `.cornerShade()`. A package made from the old starter can rename its function the same way. [Extensions](Docs/Tools/Extensions.md)
- **The inspector's number boxes step.** Shift while dragging a value box now lands on round marks at the plain speed, where it moved ten times faster. A whole number's drag speed follows its range. While you type in a box, the arrow keys step it. A whole number's minus and plus buttons repeat while held. [Parameters](Docs/Helpers/Parameters.md#scrubbing)

**The Guide and the reference**

- **The Guide is forty-five chapters.** Four chapters split along their families. The new files are `24-Automata.md`, `28-MaterialsAndSurroundings.md`, `36-ThePhoneAsASensor.md`, and `42-MakingItPhysical.md`, and `33-DepthAndThePhone.md` is now `35-Depth.md`. [The Guide's contents](Guide/README.md#contents) list them all.
- **Every Guide chapter from 24 on has a new number.** A link to a chapter file needs the new one. Chapter 24 is now 25, 25 and 26 are 26 and 27, and 27 to 33 are 29 to 35. Chapters 34 to 38 are 37 to 41, and 39 to 41 are 43 to 45.
- **Fuller finished sketches in the Guide.** Chapter 36 ends on a dancer read from the bundled film and drawn in lit solids. Chapter 40's music box swings, follows a chord progression, and writes a MIDI file. Chapter 43's live-coded set saves looks as cues. In eight chapters, the sections the finished sketch leaves out now follow it. [Guide](Guide/README.md)
- **The credits carry the history the Guide tells.** `ATTRIBUTION.md` gains an entry for each chapter, naming the people, works, and dates behind its ideas with a source to read. Several chapters correct a date or a name against those sources. [Attribution](ATTRIBUTION.md#the-history-the-guide-tells)

### Fixed

**Drawing**

- **A hole in a contoured field leaves the contour open.** A field that returned NaN or infinity next to a contour made `isolines` stop the program. The line now ends at the hole's edge. [Isolines](Docs/Generators/Isolines.md#levels)
- **A stack of contour levels is fast.** `isolines(at: levels, ...)` marched every cell again for each level. Each cell now visits only the levels that cross it. 28 levels that took 22 ms take 8.5, with the same contours. [Isolines](Docs/Generators/Isolines.md)
- **A kite-and-dart tiling covers its patch.** `Penrose.tiles(.kitesAndDarts, in:tileEdge:)` came back with bare patches through it and too few kites. Each tiling now covers its patch once, and the arcs meet across every edge. [Aperiodic tilings](Docs/Drawing/AperiodicTilings.md)
- **A diffusion curve holds its far side.** Past the band of a two-sided `drawDiffusionCurve`, the region one side held alone came back as the mean of both. `.diffuse` now fills each side's region, and `sharpness` buys cycles, three at 0 and six at 1. [Effects](Docs/Drawing/Effects.md)
- **Text keeps its glyphs when a font's atlas page fills.** On the frame that filled the page, atlas text drawn earlier in it showed the wrong characters. A full page is now kept and a fresh one started. A retained `Batch` keeps its glyphs, and a web export no longer stops there.
- **The fractal generators draw the imaginary axis up.** The Mandelbrot, Julia, and orbit-trap generators read it down, against the reference and the shader library's `complexPlane`. A Julia set with `c` off the real axis now draws mirrored left to right. A Mandelbrot centered off the real axis draws mirrored top to bottom.
- **An image the GPU holds reads `.clear` and ignores a write.** A layer's `image`, or a compute texture's, now does what its documentation says. Its pixel subscript treated it as a picture in memory: a write was kept and read back but never drawn.

**3D**

- **A transparent pixel of a mark writes no depth.** Under `depth(at:)`, a circle, a rect, a glyph, an image, and a point-cloud splat wrote depth over their whole quad. The clear corners hid whatever sat behind them. A mark now hides only where its ink is. [Depth compositing](Docs/3D/DepthCompositing.md#depth)
- **Caustics hold still in an exported video.** An export traced new photons at every frame, so the caustic light flickered in a slowly moving scene. It now traces the same photons throughout. The live window is unchanged, and a still export's caustic comes out a little different. [Caustics](Docs/3D/Caustics.md)
- **Glass shows the scene behind it at that scene's brightness.** With `sceneThroughGlass()` on, the view through glass was dimmed by the environment's intensity and exposure. It now passes all but what the surface reflects away, so a sketch without ray tracing renders brighter through its glass.

**Geometry and simulation**

- **A simulation's substeps cost what their kernels cost.** Every pass of a `Sim.shader` kernel, and every user shader, paid a large fixed cost on each draw, which `--bench` showed as end-to-end time. A 25-substep field that took 37 s to export 60 frames takes 2.5. [Effects](Docs/Drawing/Effects.md#simfield-shader)
- **A neighbor grid covers its bounds.** With a radius that did not divide the bounds, `SpatialHash` left a strip along the right and the bottom empty. So did Particle Life, the Primordial Particle System, Particle Lenia, swarm chemistry, `Swarm`, `ParticleFluid`, and `SoftBodies`. The world is now the bounds. [Compute](Docs/Shaders/Compute.md#spatialhash)
- **A small chance in a simulation is the chance it says.** In the forest fire, the Ising model, and Schelling's board, any chance below about 5e-4 fired far too often. A seeded run of these simulations draws a different run from before. [Effects](Docs/Drawing/Effects.md#simfield)
- **A forest fire takes the trees you plant.** Drawing `Color(white: 0.5)` into a `.forestFire` field planted nothing, and a rect's soft rim spilled trees into the cells beside it. A mark now snaps to the nearest of the three states. A gray from about 0.54 to 0.74 plants trees as before. [Effects](Docs/Drawing/Effects.md#simfield)
- **A physics snapshot keeps a body's own mass and center of mass.** A body given either one, as a scene's `physics:mass` and `physics:centerOfMass` give them, came back from `restore(_:)` at the mass its shape makes. The snapshot now writes both, in format 6, and still reads formats 4 and 5. [Physics3D](Docs/Simulation/Physics3D.md)
- **`surfacePoints` with blue noise is about three times faster.** The default `.blueNoise` scatter returns the same points as before.

**Connections**

- **`TUIOReceiver` reads a real tracker's frame as one frame.** Every frame from a tracker was taken twice: `framesReceived` counted double, and a lifted finger could leave early or blink out. A frame now closes on its frame number, or on the next alive list for a tracker that sends none.

**The live window and tools**

- **Input after a live reload reaches the sketch that is drawing.** In OllinLive and OllinLiveCoding, a click, a key, a drop, or the pointer's position went to the first sketch the window loaded. A mouse-driven sketch stopped answering after its first reload.
- **The undo keys stay with the host.** Command-Z and Shift-Command-Z no longer reach a sketch's `keyPressed()` when the host has nothing to undo.
- **`--cue` finds a look saved beside a live sketch.** An OllinLive export given `--cue <name>` and no `--cues` reported a look saved from the inspector as missing. The export now loads `Sketch.cues.json` from beside the sketch, and a `--cues` file still wins. [Cues](Docs/Helpers/Cues.md)
- **`ollin examples` describes every sketch in its own words.** The picture grid had renamed the first sketch of each row after its neighbors. A search now also lists the sketches whose description matches, and finds a sketch by the author its header credits. The single-sketch view prints the credit.

**Examples and credits**

- **The `MIDIFiles` example starts each bar's melody on the downbeat.** Every bar's figure began an eighth late, and the file ran an eighth past its eight bars.
- **The Hershey font's notice carries the credits its terms ask for.** The `.jhf` data's terms ask two acknowledgments to travel with it, and the notices called it public domain. Both now appear as worded, in `THIRD-PARTY-NOTICES.md` and in the notice beside the font. [Notices](THIRD-PARTY-NOTICES.md#hershey-fonts)

## [0.12.0] - 2026-09-27

A failure now says what went wrong: every export and every loader throws a named error where it stopped the program or answered `nil`. The release adds `ollin api`, a quick reference, and ten sketches in five artists' folders, and exports of GPU simulations now repeat. The new errors break source, so read **Changed** before you update.

### Added

- **`ollin api <name>` says what a public name is.** It prints each declaration with its comment, its file and line, the pages that document it, and the shortest examples that use it. `ollin api Mesh.tube` picks one type's, and `ollin api Param` lists a type's members. [The reference offline](Docs/Tools/Reference.md#a-name-and-what-it-takes)
- **`ollin api` prints a declaration as its source writes it.** A parameter's name carries its unit, as in `rotate(_ radians: Double)`. `ollin api Sketch` prints `@MainActor open class Sketch`, where the `API/` listing says `open class Sketch`. A `nonisolated` member keeps the word.
- **`ollin api` finds a name spelled nearly right.** A name nothing is called lists the names spelled like it. One that is not a sketch call leads with the sketch calls spelled like it, so `strokeWidth` points at `strokeWeight`.
- **A quick reference.** [`Docs/QuickReference.md`](Docs/QuickReference.md) is the framework in one read. It has the calls by area, the units and conventions, `@Param`, the command line, and the mistakes that draw a wrong picture with no error.
- **`llms.txt` at the root of the checkout.** A map of the reference for an assistant helping somebody write a sketch, with every Guide chapter and reference page in one line each. `Scripts/llms.sh` writes it from the pages. [The reference offline](Docs/Tools/Reference.md#for-an-assistant)
- **Every example is checked to draw the same picture twice.** `Scripts/check-determinism.sh` exports each example that runs on its own, twice under one `--seed` in two processes, and compares the pixels. `Scripts/preflight.sh --milestone` runs it. [Why a run repeats](Docs/Concepts/Determinism.md) lists what reaches past a seed, such as the order a `Set` walks.
- **A second visit to Monir Shahroudy Farmanfarmaian.** [`Examples/Recreations/MonirFarmanfarmaian`](Examples/Recreations/MonirFarmanfarmaian/) gains `Geometric`, after the felt-tip *Geometric* drawings on a grid of triangles (2013 and 2014), and `Convertible`, after the *Convertibles* (2010 to 2016). The second cuts each polygon into kites and moves them between every way they can hang.
- **A second visit to Vicente Rojo.** [`Examples/Recreations/VicenteRojo`](Examples/Recreations/VicenteRojo/) gains `Senales`, after the *Señales* (1966-1972), where each sign is painted over the last. `PiramidesYVolcanes`, after the *Pirámides y volcanes* and *Prosa del Popocatépetl* (2003), lays a stepped pyramid and lets lava break out of its steps.
- **A second visit to Vladimir Bonačić.** [`Examples/Recreations/VladimirBonacic`](Examples/Recreations/VladimirBonacic/) gains `GFE164`, his *Dynamic Object GF.E (16,4)* (1969 to 1971), built from the appendix of his 1974 article. `Random63` is *Random 63* (1969) beside a panel of the same bulbs driven by a field. With `sendsToWall` on, both panels go out over sACN through an `LEDMap`.
- **A second visit to Osamu Sato.** [`Examples/Recreations/OsamuSato`](Examples/Recreations/OsamuSato/) gains two sketches from *The Art of Computer Designing* (1993). `StraightLines` draws an eye inside a hatched word with nothing but straight lines, and `word` sets the word. `TotemBuilder` deals a monster made of circles for each seed, and `--export-grid` proofs a pile of them.
- **Waldemar Cordeiro joins the recreations.** [`Examples/Recreations/WaldemarCordeiro`](Examples/Recreations/WaldemarCordeiro/) is the first recreation that reads a photograph. `Derivadas`, after *Derivadas de uma imagem* (1969, with Giorgio Moscati), prints a photograph as characters and takes its derivative three times. `Gente`, after *Gente* (1972-1973), prints a crowd at four degrees of contrast.

### Changed

Each of these can stop a sketch from compiling or break a link.

- **Every export throws an `ExportError` when it cannot finish.** A refused frame, a missing folder, or an unknown file extension used to end the program with a `fatalError`. Each export call on `OllinApp` now throws, naming the file, the frame it reached, and what went wrong. `OllinApp.exportVideo(sketch, …)` becomes `try OllinApp.exportVideo(sketch, …)`. [Export](Docs/Output/Export.md#when-an-export-fails)
- **An `ExportError` says which of three things happened.** Its `kind` is `unsupported` (the request could not be met), `unrendered` (a frame did not draw), or `unwritable` (the file would not take it). Asking for zero frames is now `unsupported`. A clip stopped partway is removed, and a failed export flag exits with status 1.
- **The export calls that now throw.** `export`, `exportSequence`, `exportVideo`, `exportGIF`, `exportSpatialVideo`, `exportEXR`, `exportSVG`, `exportPDF`, `exportDXF`, `exportGCode`, `exportEmbroidery`, `exportSpatial`, `exportWeb`, `exportSeparations`, `exportPlates`, and the four `exportContactSheet` forms. `exportHEIC` throws where it answered `nil`, and its `StillExport` is no longer optional. `exportWidget` throws where it printed.
- **Every loader throws a `FileError` when a file will not load.** A missing file and a file in the wrong format both came back as `nil`. Now `missing` is a path that is not there and `unreadable` is bytes that are not the format. `loadImage("photo.jpg")!` becomes `try! loadImage("photo.jpg")`. [Sketch](Docs/Core/Sketch.md#fileerror)
- **The sketch loaders that now throw.** `loadImage`, `loadMesh`, `loadScene`, `loadSVG`, `loadPalette`, `loadTable`, and `loadJSON` are `throws -> T` where they were `-> T?`. `Palette.palettes` and `loadPalettes` throw where they returned `[]`. `if let photo = loadImage(path)` becomes `if let photo = try? loadImage(path)`. A name lookup such as `OutlineFont(name:)` still answers `nil`.
- **The initializers that now throw.** Each `init?` is now `init … throws`. That covers the file, data, text, and resource initializers of `Image`, `Mesh` (with `objSource:`), `Scene`, `SVG`, `Palette`, `Table`, and `JSON`. It also covers `IESProfile` (with `string:`), `ICCProfile`, `OutlineFont`, `BitmapFont` (the `bdf`, `fnt`, and `resource:` forms), and `StrokeFont` (the `jhf` and `resource:` forms).
- **Compute kernels, phone references, and writers throw too.** `ComputeKernel(entry:resource:withExtension:in:)` and `ComputeKernel(entry:contentsOf:)` throw, as do `PhoneReference.picture(path:…)`, `picture(resource:…)`, `object(path:…)`, and `object(resource:…)`. `Mesh.write(to:)`, `Scene.write(to:)`, `saveMesh`, and `saveScene` throw an `unwritable` error where they returned `false`. `IESProfile` no longer prints on a refusal.
- **The Guide is forty-one chapters in seven parts.** Nine chapters grew out of the longest ones, so every chapter after 15 has a new number. A link to a chapter file needs the new one. [The Guide's contents](Guide/README.md#contents) list them all.
- **Where each Guide chapter went.** 16 is now 19, and 17 is 18. 18 to 26 are 22 to 30. 27 is 33, 28 is 34 (`34-Listening.md`), 29 is 36, and 30 is 32. 31 is 38 (`38-FinishingASketch.md`), and 32 is 41.

### Fixed

**Drawing and effects**

- **A frame with millions of marks in one pass draws them.** A `LineSpray` past about ten million points a frame, or any pass with that many particles, drew nothing and said nothing. A frame the GPU refuses for any reason now says so on standard error. [Depth of field from light](Docs/Drawing/DepthOfField.md)
- **Glyph-atlas text no longer crashes when it fills the atlas.** Under `textMode(.atlas)`, text with more distinct characters than a page holds stopped the sketch: a long run of Chinese or Japanese, say. [Text](Docs/Drawing/Text.md#textmode)
- **Atlas text set a character at a time is one draw call.** Under `textMode(.atlas)`, every `drawText` cost a draw call of its own, live and in a replayed `Batch`. Calls in a row with the same font, blend, and target now share one. [Text](Docs/Drawing/Text.md#textmode)
- **A glow or blur radius under a pixel is noted.** The radius of `.bloom`, `.halation`, and `.gaussianBlur` is a pixel count, so `radius: 0.012` spreads nothing. A sketch that writes one is told once, from `postProcess` or `filtered`. `DynamicObject`, `NamaFrieze`, `LensFlare`, and `SceneExplorer` now give theirs in pixels. [Effects](Docs/Drawing/Effects.md#blur--glow)
- **A feedback layer, an accumulator, or a simulation field is freed when the sketch lets go of it.** None ever was, so a sketch that made one in `setup()` lost it on every live reload. [Effects](Docs/Drawing/Effects.md)
- **An inline compute kernel no longer rebuilds its source on every dispatch.** An `Accumulator`, a particle system, and a simulation each paid for it, about a fifth of a small frame. [Compute](Docs/Shaders/Compute.md#the-kernel-snippet)

**3D and simulation**

- **A chaotic GPU simulation exports the same frames under one seed.** Two exports drifted apart within seconds: Particle Life, the Primordial Particle System, Particle Lenia, swarm chemistry, `Swarm`, `ParticleFluid`, `SoftBodies`, and any kernel over a `SpatialHash`. An export or a take playing back now repeats on the same machine. A live window keeps the faster order. [Artificial life](Docs/Simulation/ArtificialLife.md)
- **Caustics export the same pixels every time.** Two renders of one frame could differ by a level or two in a few dozen pixels. [Caustics](Docs/3D/Caustics.md)
- **A `MeshField` exports the same pixels every time.** Where two copies met at exactly the same depth, either could win. An export now draws the copies in the order they were placed. A live frame keeps the faster gather. [Instancing](Docs/3D/Instancing.md#meshfield)
- **A sea state that changes every frame no longer grows a cache every frame.** An ocean whose wind or height follows the clock used more memory for as long as it ran. The path-traced export's environment tables are bounded the same way. [The ocean](Docs/3D/Ocean.md)

**Files**

- **A file you are handed can no longer end the sketch that reads it.** Every file reader now checks a count the file declares against the bytes the file holds, before any memory is set aside. An input nested past a reader's limit is refused or read to the limit.
- **A look, a palette, or an SVG with bad numbers.** A [`.cube` look](Docs/Drawing/Looks.md) declaring a 256-node cube no longer sets aside 265 MB. An [ASE palette](Docs/Drawing/Color.md) swatch whose numbers are not numbers is skipped, and `Color(hue:)` reads such a hue as red. An [SVG](Docs/Drawing/SVG.md) arc or transform past what a `Double` holds draws a line.
- **A damaged glTF or USD scene is refused.** [glTF](Docs/3D/Scenes.md) accessors with negative indices, overflowing offsets, or triangles naming missing vertices are refused or dropped. USD text with an integer past 64 bits, a crate declaring more than its bytes hold, and a negative face count are refused.
- **A damaged PLY or STL no longer crashes.** A PLY whose faces name missing vertices, and a binary STL whose triangle count its size cannot hold, used to crash Model I/O.
- **A damaged sound file or physics snapshot is refused.** The [audio loaders](Docs/Helpers/Audio.md) refuse a sample rate no sound plays at. [SFZ](Docs/Helpers/Synthesis.md) keys, tunings, levels, and loop points are held to the format's ranges. [Physics snapshots](Docs/Simulation/Physics3D.md) refuse numbers a world does not hold and indices naming nothing.
- **Two numbers past their range read safely.** `JSON`'s `int` reads `nil` for a number no `Int` holds, and `noise()` at a coordinate past 2^63 no longer traps.
- **New limits on nesting.** A glTF or USD scene nests at most 64 levels deep. A [formula](Docs/Helpers/Formula.md) is at most 1,024 numbers, names, and signs, nested at most 64 deep. A scene at the limit loads on a background thread, and `Scene.bounds` reads there too. [Scenes](Docs/3D/Scenes.md#loading)
- **An audio file that declares tens of thousands of channels is refused.** A damaged WAV claiming 32,768 channels stopped the process on macOS 26. Every audio loader now refuses a file past 1,024 channels, with `.couldNotDecode` from `AudioPlayer`. [Audio](Docs/Helpers/Audio.md)
- **An SFZ map written in Latin-1 loads.** `SampledInstrument(contentsOf:)` threw `.couldNotDecode` for a map that is not UTF-8, which is how older libraries spell an accented sample name. [Synthesis](Docs/Helpers/Synthesis.md#sampled-instruments)

**Export and output**

- **`--photo` keeps every camera closed.** A sketch that started a `Camera` itself opened this machine's camera even under the flag, which reached only `Camera.orStill`. `Camera.start()` now throws under `--photo`. `LiveSurface`, `LiveEnvironment`, `DepthCloud`, and `BarcodeReader` take a bundled picture there. [Vision](Docs/Vision/Vision.md)
- **`--skip` builds a picture that carries from frame to frame.** The warmup ran `draw()` but rendered only a `noClear` canvas. A `Feedback` pile, an `Accumulator`, a `LineSpray`'s running mean, or a simulation field started the first written frame empty. That frame now matches a run from zero. [Export](Docs/Output/Export.md)
- **Every tile of a contact sheet draws its feedback layer.** In `--export-grid` and `--export-sweep`, a sketch with a `Feedback` layer drew its first two tiles and left the rest black. [Variations](Docs/Core/Variations.md)
- **`--param` wins over `--cue`.** A value given by hand beside a cue was overwritten by the cue's. The cue now lands first, and before `setup()`, so what `setup()` builds from a parameter reads the cue's value. [Cues](Docs/Helpers/Cues.md)

**Parameters and the live window**

- **Typing a number into an inspector box does what you typed.** The box clamped each key as it arrived, so "300" in a box from 50 to 500 came out as 500. The text is now yours until Return, Tab, or a click away commits it. Escape puts the starting value back. [Parameters](Docs/Helpers/Parameters.md#where-the-controls-appear)
- **Inspector values are plain and round.** A box shows a value's own digits with no trailing zeros or thousands separator (`175`, `0.004`, `25000`). A slider, scrub, or pad drag lands on round values (`2.4`, not `2.4027931415929205`), which is also what Save writes.
- **A sketch window opened while the display is asleep draws once the display wakes.** A window that came up with the lid closed and the monitor asleep stayed blank for good.

**Tools and examples**

- **`ollin docs`, `ollin examples`, and `ollin api` answer in a tenth of a second.** Each lookup went through `swift run`, which took about four seconds and waited out any build already running. [The reference offline](Docs/Tools/Reference.md)
- **An example's page shows one piece in its clip and in its picture.** A sketch that rolls its variation played one piece under a poster of another, on 85 pages. Eight examples have media for the first time, among them `Audio/Expression`, `Soundsuit`, and `Shapes/Watercolor`. [Examples](Examples/README.md)

## [0.11.0] - 2026-09-23

The lens flare is now followed ray by ray through real glass, and Kuramoto oscillators couple over a lattice or a graph. Five artists' folders gain ten recreation sketches. Loaders now throw where they returned `nil`, devices say why they are unavailable, and every flare looks different, so read **Changed** before you update.

### Added

**Simulation and 3D**

- **Kuramoto oscillators on a lattice or a graph.** `Kuramoto(columns:rows:layout:wraps:)` lays a crowd on a `.square(.vonNeumann)`, `.square(.moore)`, or `.hex` lattice, coupled within `range` rings, with `wraps` for a torus. The hex lattice shares `HexGrid`'s addressing. `Kuramoto(neighbors:)` and the settable `neighbors` couple a crowd over any graph. [Oscillators](Docs/Simulation/Oscillators.md)
- **A map of where a crowd has locked.** `localCoherence` is the order parameter over each oscillator's own neighborhood. A crowd can hold several `layers` per site, pulled together by `layerCoupling`, and `rates` is every oscillator's rate at the last substep. The `Simulation/Kuramoto` example gains a honeycomb field. [Oscillators](Docs/Simulation/Oscillators.md)
- **A second lens, and wear on the iris.** `Lens.doubleGauss` is a 1950s six-element double Gauss whose twenty ghosts make the chain a flare is known for. `LensFlare.wear` is wear on the opening: it frays the star's arms and fills the space between them with fine needles. [Lens flare](Docs/3D/LensFlare.md)
- **A streak, dirt, and a halo on a flare.** `LensFlare.streak` (with `streakLength`, `streakAngle`, `streakTint`) is the long line an anamorphic lens throws. `LensFlare.dirt` is grime on the front element, and `LensFlare.halo` (with `haloSize`) is a rainbow ring around a light. All three are off until asked for. [Lens flare](Docs/3D/LensFlare.md)
- **An anamorphic front group.** `Lens.anamorphic(squeeze:)` stretches the ghosts, the star, and the halo sideways by the squeeze. The streak stays a line and the dirt keeps its shape. [Lens flare](Docs/3D/LensFlare.md)

**Examples**

- **Mohamed Melehi joins the recreations.** [`Examples/Recreations/MohamedMelehi`](Examples/Recreations/MohamedMelehi/) is after his hard-edge wave paintings of the 1970s. `Waves` is a ribbon of flat bands that breaks into a traveling wave, and `Flamme` stands the wave up as one flame. Both export every band as a closed outline.
- **Nasreen Mohamedi joins the recreations.** [`Examples/Recreations/NasreenMohamedi`](Examples/Recreations/NasreenMohamedi/) is after her untitled ink and graphite drawings. `Registers` rules runs of fine lines that gather against one heavy line and open toward the next. `Diagonals` floats chevrons that thin to their tips among hairlines. Both export for a pen.
- **A second visit to Gego.** [`Examples/Recreations/Gego`](Examples/Recreations/Gego/) gains two sketches. `Tejedura`, after the *Tejeduras* (1988 to 1991), weaves strips of a print of one of her nets with strips of foil. `Chorro`, after the *Chorros* (1970 to 1971), hangs falls of rods hooked end to end.
- **A second visit to Hassan Sharif.** [`Examples/Recreations/HassanSharif`](Examples/Recreations/HassanSharif/) gains two sketches. `OctoberLines`, after *10th to 13th October No. 1 & No. 2* (1984), sums the numbers a wavy line cuts from a table and rules each sum as a band of lines. `BodyAndSquares`, after the 1983 performance, lays a body across five squares picked by chance.
- **A second visit to Manuel Felguérez.** [`Examples/Recreations/ManuelFelguerez`](Examples/Recreations/ManuelFelguerez/) gains two sketches. `EspacioMultiple`, after *El espacio múltiple* (1973), carries one form through a flat painting, a relief, and a standing piece, and `--export-svg` gives its plan. `RelieveLacado` raises a `MaquinaEstetica` design in lacquered layers under a circling key light.

### Changed

Each of these can stop a sketch from compiling or change what it draws. A call that now throws keeps its old shape with `try?`.

**3D**

- **The lens flare is followed ray by ray.** Each ghost is now a grid of real rays carried through the lens's spherical surfaces, stretched and cut by the barrel as glass makes it. A bright ghost is followed in seven wavelengths (`LensInterface.abbeNumber`). It costs one to five milliseconds a frame at 1080 square on an M2. [Lens flare](Docs/3D/LensFlare.md)
- **A bare `lensFlare()` uses another lens.** With no lens named it uses `Lens.standard`, the double Gauss multicoated at f/8, where it used the Heliar wide open. Name `.heliar` to keep it. `LensFlare.sourceSize` now sets how soft every ghost is, and defaults to `0.015` (was `0.035`). [Lens flare](Docs/3D/LensFlare.md)
- **A flare's brightness follows the iris.** The level is set once per lens, where it was set each frame off the hottest ghost. Closing the iris brightens the ghosts it shrinks and dims the star's arms as it lengthens them. `multicoated()` hands its wavelengths out differently, so each ghost's color changes. [Lens flare](Docs/3D/LensFlare.md)

**Sound**

- **Sound loaders throw.** `ImpulseResponse.load(_:)`, `.resource(_:withExtension:in:)`, and `init(contentsOf:)`, `GrainSource(named:withExtension:in:)` and `(contentsOf:)`, and `SampledInstrument(sfz:in:)` and `(contentsOf:)` throw `AudioError` where they returned `nil`. Its cases are `resourceNotFound`, `couldNotDecode`, and the new `empty`. [Synthesis](Docs/Helpers/Synthesis.md)
- **An audio engine that will not start says why.** `Synth`, `Tone`, and `AudioPlayer` gain `unavailableReason`, cleared by the next start that succeeds, where `Synth.start()` printed and `Tone.play()` and `AudioPlayer.play()` said nothing. `AudioInput.start()` still throws for what it can see, and writes `unavailableReason` for a refused microphone. [Audio](Docs/Helpers/Audio.md)

**Vision and capture**

- **A video that cannot open says so.** `VideoPlayer(url:)` throws `VideoError.fileNotFound` for a missing file, as the `path:` and `resource:` forms already did. A file that opens but is not a movie says so in the new `VideoPlayer.unavailableReason`. [Video](Docs/Video/Video.md)
- **`Record3DRecording.pose(at:)` throws outside the recording.** It throws `frameOutOfRange`, as `frame(at:)` does, and is `nil` only for a frame with no recorded pose. [Record3D](Docs/3D/Record3D.md)
- **Vision has one error type.** The five `Error` enums nested in `ModelTracker`, `PointSegmenter`, `ConceptTracker`, `DepthTracker`, and `DepthClip` are one `VisionError`, with `unavailable` and the new `failed`. A `catch` naming an old type names `VisionError` now. [Vision](Docs/Vision/Vision.md)
- **Two detectors return a value or throw.** `PersonSegmenter.detect(in:quality:)` and `SaliencyTracker.detect(in:mode:)` no longer return an Optional. They throw `VisionError.failed` when a matte or heat map cannot be converted. `SubjectSegmenter.detect(in:)` is `nil` only when no subject is found, and a depth model that answers no map says so in `unavailableReason`. [Vision](Docs/Vision/Vision.md)

**Physics**

- **Physics snapshots throw.** `PhysicsSnapshot(data:)` and `(resource:withExtension:in:)` throw `PhysicsSnapshot.Failure` (`unreadable`, or the new `resourceNotFound`) where they returned `nil`. `World3D.restore(_:)` throws `unreadable` where it printed, and `World3D.load(contentsOf:)` throws where it returned `false`. [3D physics](Docs/Simulation/Physics3D.md)
- **A 3D body that cannot be built throws.** `World3D.addVehicle`, `addRagdoll(from:)`, `addSoftBody(from:)`, `addRope(through:)`, and `addTensegrity(_:)` throw the new `PhysicsError.unbuildable` where they returned `nil` and printed. Its text says what was needed. [3D physics](Docs/Simulation/Physics3D.md)

**Connections**

- **A serial port says what it is waiting on.** `SerialPort` and `FirmataBoard` gain `lastError`, the sentence `open()` is waiting on. It names a missing device, a port another program holds, or a device that went away, and clears when the port opens. These were one silent state behind `isOpen`. [Serial](Docs/Integration/Serial.md)
- **A Syphon client and a Link clock say why they are unavailable.** `SyphonClient` gains `unavailableReason` for a source that was not there, a refused connection, or a source that has gone away. `LinkClock` gains `interfaceCount` and `unavailableReason` for a clock that could open no network interface. [Syphon](Docs/Integration/Syphon.md), [Link](Docs/Integration/Link.md)
- **An OSCQuery server and the remote inspector start again.** `OSCQueryServer` and `RemoteInspector` gain `isRunning`, `unavailableReason`, and a `start()` that serves again after `stop()` or tries a held port again. `RemoteInspector.stop()` no longer leaves `boundPort` set. [OSCQuery](Docs/Integration/OSCQuery.md), [Remote](Docs/Integration/Remote.md)
- **A number that does not fit reads as `nil`.** `OSCArgument.int`, `MQTTMessage.int` and `int(named:)`, `RoomMessage.int`, and a table's `int(_:)` now return `nil` for a number that is not finite or too large for an `Int`. They used to trap. A parameter restored from a stored `.number` that large keeps its value. [OSC](Docs/Integration/OSC.md), [MQTT](Docs/Integration/MQTT.md), [Room](Docs/Integration/Room.md)
- **`VirtualCameraError` is internal.** No public call ever produced it. `VirtualCameraServer.unavailableReason` already carried its sentences.

### Fixed

- **The lens flare's ghosts sit where glass puts them.** Every ghost was misplaced and missized, most of them on the light's own side of the frame. Expect a different flare, with ghosts on both sides of the center. The ghost polygons also line up with the star's arms, where they turned with `starSize`. [Lens flare](Docs/3D/LensFlare.md)
- **A still counts its frame at the rate `--fps` names.** `--export`, `--export-exr`, `--export-plates`, and the vector exports read `--frame` and never `--fps`. So `--frame 30 --fps 10` drew at half a second where it meant three seconds. Every one-frame export now reads both flags. [Export](Docs/Output/Export.md)
- **A `--param` value is there when `setup()` runs.** It landed only after `setup()`, so a count built there read the declared default. It is now applied before `setup()` and again after it. A `canvasSize` that picks its size by a parameter exports and opens at the run's size. [Parameters](Docs/Helpers/Parameters.md)
- **An extension's `afterFrame` fires in an export.** The headless runs never called it, so `FrameInfo.profile` could be read from a window and never from an export. It now fires once per rendered frame. [Profiling](Docs/Tools/Profiling.md)
- **A stranger's packet no longer ends the sketch.** A malformed message could crash a sketch reading Firmata, OSC, MQTT, a room, OSCQuery, the remote page, a WebSocket, Link, or the phone's maps. So could a table cell reading `1e300`, through `int`. Each is now refused, ignored, or read as `nil`. [The test suite](Tests/README.md)
- **A line spray whose scene changes size no longer stalls.** Under `.byLength` sampling, lines that stretch made the spray remake its particles every frame, enough at six million points to stall the desktop. The particles are now kept and only grown. [Depth of field from light](Docs/Drawing/DepthOfField.md)
- **The aesthetic machine weighs a quarter disk at its true center.** `MaquinaEstetica` placed a wedge's weight off center, and drew its quarter ring with a straight inner edge. Both are fixed, and the sheets a seed produces change wherever a wedge or a ring appears.
- **The accumulation page says where a long sum stops.** A faint sample on a `noClear` canvas stops counting under about a thousandth of what the pixel holds, so a long exposure stops brightening. The page now says so and sends a long sum to `makeFeedback(precision: .float32)`. [Accumulation](Docs/Drawing/Accumulation.md)

## [0.10.0] - 2026-09-19

An outline can now answer questions about itself, and one frame can hold several lighting rigs. The depth-of-field aperture has a shape, and a sketch reads and writes MIDI files. A second naming pass moved about thirty names in the satellite modules, so read **Changed** before you update.

### Added

**Drawing**

- **An outline answers questions about itself.** A `Contour` says which way it runs at a fraction along it (`tangent(at:)`, `normal(at:)`) and where it passes nearest a point (`nearestPoint(to:)`, `fraction(of:)`, `distance(to:)`). `piece(from:to:)` hands back the stretch between two fractions. [Geometry](Docs/Drawing/Geometry.md)
- **Crossings, and corners rounded or cut.** `crossings(with:)` and `crossings()` find where a `Contour` meets another outline or itself. `simplified(tolerance:)` thins a dense trace, `rounded(_:)` and `chamfered(_:)` work its corners (on `Shape` too), and `reversed()` walks it backward. `Examples/Shapes/OverUnder` weaves a tangled loop through its own crossings. [Geometry](Docs/Drawing/Geometry.md)
- **Outlines, shapes, and grids read as collections.** A `Contour` is its points, a `Shape` its contours, a `Grid`, `HexGrid`, or `TriangleGrid` its cells, and a `Polyomino` its squares. Each takes `for point in contour`, `grid.count`, `piece.contains(cell)`, `shape.first`, `map`, `filter`, and `randomElement(using:)`. `points`, `contours`, and `cells` still return arrays. [Geometry](Docs/Drawing/Geometry.md)
- **`Contour` gains a geometric `contains(_ point:)`.** It answers the question `Shape.contains(_:)` answers. For vertex membership, ask `contour.points.contains(p)`. [Geometry](Docs/Drawing/Geometry.md)
- **The depth-of-field aperture has a shape.** `Bokeh.aperture` decides what a point far from focus turns into. It is `.round` as before, `.blades(6)` for the hexagon a real iris draws, `.blades(count:rotation:)` to turn it, or `.picture(_:)` for a mask from any `Image`. [Depth of field](Docs/Drawing/DepthOfField.md)
- **Surfaces in the depth-of-field spray.** `SprayQuad` puts a face in a `LineSpray` scene beside its wires, set through `setQuads(_:)`. A quad's `light` is the whole quad's. `LineSpray.picture` is an image the quads read through each quad's `pictureBounds`, so a photograph becomes an object made of light. [Depth of field](Docs/Drawing/DepthOfField.md)

**3D**

- **One frame, several lighting rigs.** `withLights([...]) { }` lights a block from its own fixtures, and `withLights(.noir) { }` from a preset. `withoutLights { }` draws a body flat in its fill color. `addLight(_:)` adds one `Light` to the frame's own rig. Lamps set the ordinary way behave as before. [3D](Docs/3D/3D.md)

**Sound and MIDI**

- **MIDI files in and out.** `MIDIFile` in `OllinAudio` reads a Standard MIDI File into notes a sketch can play or draw, and writes one back out. It reads formats 0, 1, and 2, with the tempo map through `beats(at:)` and `seconds(at:)`. A `Synth` writes down what it plays between `startRecording(tempo:name:)` and `stopRecording()`. [MIDI files](Docs/Helpers/MIDIFiles.md)
- **Timecode compares.** `Timecode` is `Comparable`, so a cue test is `<` and a cue window is a range: `if (cueIn..<cueOut).contains(now)`. The order runs on the moment a timecode names, so two counted at different rates still compare. [MIDI](Docs/Integration/MIDI.md)

**The Guide**

- **Coming from openFrameworks or OPENRNDR.** The Guide's new Appendix E covers the big moves from either one, each as a pair of code followed by what is different. Appendix C stays the call-by-call map for p5.js and Processing. [Appendix E](Guide/E-ComingFromOpenFrameworksAndOPENRNDR.md)

**Examples**

- **A black hole.** [`Examples/Shaders/BlackHole`](Examples/Shaders/BlackHole/) traces light backward past a Schwarzschild horizon, so the shadow and a star seen as a ring fall out of the physics. The disk shines at the temperature Page and Thorne's flux gives it, shifted blue and red by its motion as Luminet drew it in 1979. It plays on the web page too.
- **A homage after Gego.** [`Examples/Recreations/Gego`](Examples/Recreations/Gego/) has two sketches. `Reticularea` hangs a net of irregular triangles from the ceiling and lets gravity fold it, drawn as 2D lines through `project`. `DrawingWithoutPaper` hangs a bent wire lattice off a wall, and its shadow is the drawing. Drag a wire in either one.
- **A homage after Vladimir Bonačić.** [`Examples/Recreations/VladimirBonacic`](Examples/Recreations/VladimirBonacic/) rebuilds two lamp objects he made in Zagreb between 1969 and 1971, driven by the arithmetic of Galois fields. `DynamicObject` is the 32 by 32 square of *GF.E 32-S*, and `NamaFrieze` is the eighteen-panel frieze *DIN. PR 18*. Set `sendsToWall` and the panels go out over sACN.

### Changed

Each of these can stop a sketch from compiling. The second naming pass renamed calls whose names said something other than what they do.

- **Renamed in synthesis.** `Synth.hearingRange` is now `hearingDistance`, `Wavetable.length` is `samplesPerCycle`, and `Compressor.makeup` is `makeupGain`. `Equalizer.lowEdge` / `highEdge` are `lowFrequency` / `highFrequency` beside `midFrequency`, and `GrainCloud.scatter` is `timingJitter` beside `positionJitter` and `pitchSpread`. `Patch.modulated(by:index:)` takes `amount:`.
- **Renamed in listening.** `AudioAnalyzer.process(_:)` is now `analyze(_:)`, `SpeechListener.captionWords` is `maxCaptionWords`, and `Sonification.levels` is `levelRange`. `DetectedPitch.note` is `nearestPitch`, the rounded twin of `pitch`, since `Note` is another type. `AudioAnalyzer.note` and `AudioSource.note` follow it.
- **Renamed in vision.** The `[Classification]` lists called `labels` on `ImageClassifier`, `ConceptTracker`, `ModelTracker`, and `ModelOutput` are now `classifications`. `ConceptTracker.confidence(of:)` is `share(of:)`, `PointSegmenter.Pick.score` is `confidence`, and the segmenter's `isWorking` is `isPicking`. `TrajectoryTracker(trajectoryLength:)` takes `minObservationCount:`, and `ContourDetector.contrastAdjustment` is `contrastFactor`.
- **Renamed in physics.** `World.pixelsPerMeter` is now `unitsPerMeter`, matching `World3D`. `Rope3D`'s `thickness` is `radius`, so `World3D.addRope` takes `radius:`. `Wheel3D.spin` is `rollAngle` beside `steerAngle`, with `spinRate` the rate. `Character3D.move(_:)` is `walk(at:)`, and `dragSoftGrab` / `releaseSoftGrab` are `dragSoftGrip` / `releaseSoftGrip`, after the `SoftGrip` they take.
- **Renamed in screen capture, Bluetooth, haptics, and controllers.** `ScreenSource.window(title:)` is now `window(matching:)`, and `BluetoothDevice(named:)` is `BluetoothDevice(matching:)`. `BluetoothReading.isOn` is `bool`, `BluetoothCharacteristic.standard(for:)` is `known(for:)`, `HapticEvent.strength(at:)` is `intensity(at:)`, and `controllerMotion(_:)` is `controllersReportMotion(_:)`.
- **Renamed in Firmata, MQTT, laser, and timecode.** `FirmataBoard.setSamplingInterval(_ milliseconds: Int)` is now `sampleEvery(_ seconds: Double)`. `MQTTTopic.isValid(_:)` is `isValidFilter(_:)`, `LaserSafety.stationaryLimit` is `maxStationaryPoints`, and `LaserProjector.isConnected` is `isPlaying`. `Timecode.advanced(by:)` is `advanced(byFrames:)`, since `advance(by:)` means seconds everywhere else.
- **Renamed in the room and the phone.** `Room.name` is now `peerName`, since it named this machine, and `Room.problem` is `lastError`. `PhoneState.status` is `statusMessage`, and `PhoneBody.isJointTracked(_:)` is `isObserved(_:)`: it answers whether the camera saw the joint.
- **One shape per kind of failure.** A failure a call can see throws, one that happens later is readable afterwards as a sentence, and `nil` means a value is absent. `MQTTClient.lastError` now clears when the line comes back up, and `EtherDreamFinder.start()` throws `StartError.badPort` where it returned in silence.
- **A camera says why it has no frame.** `Camera` gains `unavailableReason` for a refused permission prompt or a failure after it, where `frame` stayed `nil` with no reason. `start()` still throws for what it can see itself. `Record3DRecording(url:)` reports a missing file as `Record3DError.fileNotFound`, as its `path` twin already did.

### Fixed

- **Building a physics world while another is torn down no longer ends the process.** Two threads could claim the same slot in the rigid solver's table. A sketch builds its world on the main thread and never met this.
- **The compose reference names its modifiers right.** `Docs/Drawing/Effects.md` listed a layer's blend and resolution modifiers as `.blend(_:)` and `.scale(_:)`. They are `.blended(_:)` and `.scaled(_:)`, as its own example wrote them. [Effects](Docs/Drawing/Effects.md)

## [0.9.0] - 2026-09-18

This release shows a running sketch on the phone's screen and lets you write a GPU simulation of your own. It adds complex numbers in Swift and in shaders. A GIF is now written to its file frame by frame. `SprayLine` stores its light differently, so read **Changed** before you update.

### Added

**Drawing and math**

- **A color named by its light.** `Color(linear:green:blue:)` takes linear numbers, the ones a lighting calculation ends with. `linearRGB` reads a color back as light in `Double`. The curves between them, `Color.srgbToLinear` and `Color.linearToSrgb`, are public now. [Color](Docs/Drawing/Color.md#color)
- **A `SprayLine` takes its light as light.** `SprayLine(from:to:light:endLight:)` carries linear RGB radiance per pass. A scene that shades in linear units hands its numbers over unchanged. [Depth of field from light](Docs/Drawing/DepthOfField.md#linespray)
- **Complex numbers.** `Complex` is a point of the plane that multiplies. Write `Complex(1, 2)`, `1 + 2 * .i`, the polar `Complex(magnitude:argument:)`, or `.unit(angle)` to turn by an angle. It has `magnitude`, `argument`, `conjugate`, and `reciprocal`. `Vector2(z)` and `Complex(v)` cross to the canvas and back. [Complex](Docs/Helpers/Complex.md)
- **Functions of a complex number.** `Complex.exp`, `.log`, `.pow`, `.sqrt`, `.sin`, `.cos`, `.tan`, and the hyperbolic three work on the principal branch. `Complex` is a `Numeric` value, so `let c: Complex = 3` works, `2 * z` doubles, and an array sums under `reduce(0, +)`. [Complex](Docs/Helpers/Complex.md)
- **Complex arithmetic in a shader.** The shader library gains a `complex` module with the same arithmetic on a `float2`: `cmul`, `cdiv`, `cexp`, `clog`, `cpow`, `csqrt`, `csin`, `ccos`, and the rest. `complexPlane` reads a layer as the plane. `domainColor` paints a value as the domain-coloring generator does. [Shader library](Docs/Shaders/ShaderLibrary.md)
- **Curl noise in space.** `curlNoise(x, y, z)` and `curlNoise(_ p: Vector3)` give a flow that swirls in every direction and never gathers or drains. A curl now costs about three reads of `noise`, and the shader library has the matching `float3 curlNoise(float3)`. The `Rendering/LineSpray` example bends its rings with it. [Noise](Docs/Generators/Noise.md#curlNoise)
- **The noise fields as a value.** `noiseFields` is the sketch's family of fields as one `NoiseFields` value, seeded as the sketch is, with every `noise`, `fbm`, `curlNoise`, `simplexNoise`, and `worley` form. It can be handed to every core, as under `DispatchQueue.concurrentPerform`. `noiseSeed` still reaches it, and `NoiseFields(seed:)` makes one anywhere. [Noise](Docs/Generators/Noise.md#noiseFields)

**Simulation**

- **A simulation of your own.** `Sim.shader(_:inject:substeps:rest:)` runs a Metal kernel you write over a `SimField` in place of a built-in rule. `shade(uv, info)` returns a cell's next state from `cell(info)`, `cell(info, dx, dy)`, `sampleRaw(info, p)`, and the field's extra `inputs`, read as `input(info, i)`. The `Simulation/Wind` example uses it. [Effects](Docs/Drawing/Effects.md#simfield)
- **A drawn mark enters the field by your rule.** An optional `inject:` kernel reads `mark(info)` and decides how a drawn mark enters the field. A circle or a line drawn in `withField` is then that shape, stepped by your rule. [Effects](Docs/Drawing/Effects.md#simfield)
- **A field with walls, and a field that counts.** Every field has an `edge`, a `FieldEdge`: `.wrapping` (the torus it always was), `.clamped` walls, or one axis of each. The twelve neighbor-reading sims honor it too. A field also has a `precision`, with `.float32` for a state that counts. [Effects](Docs/Drawing/Effects.md#simfield)
- **A field read back, and drawn as arrows.** `SimField.snapshot()` reads the field back as a `FieldSnapshot`. `Filter.arrows(spacing:scale:color:width:)` draws any two-channel layer as arrows. [Effects](Docs/Drawing/Effects.md#simfield)

**Output**

- **The phone as the sketch's screen.** `device.show(self)` keeps a sketch running on the Mac and shows its frames full screen on Ollin Capture, in a new Sketch mode. Nothing is installed on the phone, so a live edit reaches it once the Mac has compiled. Rebuild the capture app to get the mode. [Phone](Docs/3D/Phone.md#the-sketch-on-the-phones-screen)
- **A finger on the phone is the sketch's pointer.** While the phone shows a sketch, the first finger drives `mouseX`, `mouseY`, `mouseIsPressed`, and `pressure`. Every finger still arrives on `device.touches`. `PhoneScreen` reports `isShowing` and lets go of the pointer with `drivesPointer`. `Examples/3D/Phone/PhoneCanvas` paints with a finger.
- **A GIF is written as it is drawn.** `--export-gif` and `--export-loop` put each frame into the file as it is rendered, so a long loop costs the memory of one frame. The frames share one table of colors. `--gif-palette per-frame` (`palette: .perFrame` on `exportGIF`) chooses one for every frame. [Export](Docs/Output/Export.md#animated-gif)
- **A GIF writer a sketch can drive.** `GIFWriter` takes images of your own from a sketch or an extension. Call `GIFWriter(path:width:height:)`, `append(_:delay:)`, and `finish()`, with `palette:` and `loops:` beside them. [Export](Docs/Output/Export.md#animated-gif)

**Tools and the reference**

- **The API diff reads as a version.** `Scripts/api-diff.sh` compares the public listings under `API/` with the last tag. It names every line added, removed, renamed, changed, or deprecated, and the bump the next release needs. `--changelog` prints the skeleton of a changelog entry. [`API/README.md`](API/README.md)
- **Every public name has a place in the reference.** 1,198 names no page mentioned are written up. Among them are the `Mesh` generators (`.klein`, `.lathe`, `.mobius`, `.superellipsoid`), `Material`'s `rimColor`, `rimSharpness`, and `subsurfaceColor`, `StrokeFont`'s metrics, `Installation`'s schedule, `Take.Event`, `FrameProfile`, `ScanGraph.Settings`, `SwarmChemistry.Recipe`, `MPEZone`, `Controller.dpad`, and every satellite's error type.

**Examples**

- **Monir Shahroudy Farmanfarmaian joins the recreations.** [`Examples/Recreations/MonirFarmanfarmaian`](Examples/Recreations/MonirFarmanfarmaian/) has `MirrorFamily`, a relief of small mirror triangles under a moving lamp, with ray-traced reflections in every facet. `BehindGlass`, after her *Mazes*, paints a pane of spiral channels from behind, silver last, then turns it over.
- **Owen Schuh joins the recreations.** [`Examples/Recreations/OwenSchuh`](Examples/Recreations/OwenSchuh/) reads two leaves of a 2022 notebook spread, where a digit is painted as a color. `CountingTheRationals` weaves the table of fractions and walks its diagonals, so one walk reaches every cell. `DiagonalArgument` builds the number that is on no line of a list.
- **Hassan Sharif joins the recreations.** [`Examples/Recreations/HassanSharif`](Examples/Recreations/HassanSharif/) reads two of his semi-systems. `DotsLinesForms` makes the 1984 sheet again from new numbers, as dots, as lines, and as squares. `AngularLines` fills a sheet with lines through six numbered crossings and paints one as a black band on red, after his *Six Points Angular Lines*.
- **Three examples on the complex plane.** `Examples/Shaders/ComplexPlane` colors the ratio of two moving points in a shader and lays that ratio's circles over it from `draw()`. `ImaginaryLog` paints the imaginary part of the ratio's logarithm. `Meromorphic` builds a ratio of two cubics from six moving roots.

### Changed

- **`SprayLine` stores light.** Its `color`, `endColor`, `intensity`, and `endIntensity` properties are gone. `light` and `endLight` hold the linear RGB radiance they used to be multiplied into. The `color:intensity:` initializer is unchanged, so a line written that way builds as before and draws the same pixels.
- **`LineSpray.setLines` keeps its average when nothing moved.** Handing it the lines it already has leaves the running average alone. A sketch that rebuilds its scene each draw now converges under `--settle`, and moved lines restart it as before. [Depth of field from light](Docs/Drawing/DepthOfField.md#linespray)

### Fixed

- **A phone that leaves mid-write no longer ends the sketch.** Pulling the cable or closing the app during a write could end the whole process. That write now fails, and the connection recovers as it does from any drop.
- **The Vision page spells `minSize:` right.** The `RectangleDetector` initializer's size argument is `minSize:`. The page had it as `minimumSize:`.

## [0.8.0] - 2026-09-16

This release adds a crowd that walks through itself, sound cut into grains, and a sketch as a desktop widget. A light can have a reach, and a frame can carry up to 256 of them. OllinLiveCoding can take an edit without starting the piece over. A naming pass renamed a number of calls, so read **Changed** before you update.

### Added

**Drawing**

- **A canvas in the photographic 3:4.** `.photo1080` is 1080 by 1440, and `.photo1080.landscape` is the 4:3 form at 1440 by 1080. It sits beside `.portrait1080`, the slightly taller 4:5 crop, and the project generator offers it too. [Canvas](Docs/Core/Canvas.md#canvasSize)
- **Your seed reaches the standard library's dice.** `randomness` is the sketch's own generator, the stream `random()` draws from. Hand it to any call that takes `using:` and that call follows your seed: `colors.randomElement(using: &randomness)`, `points.shuffled(using: &randomness)`, `Int.random(in: 1 ... 6, using: &randomness)`. Seed it with `randomSeed` or `seed` as before. [Random](Docs/Generators/Random.md#randomness)
- **The seedable generators follow the sketch.** `WaveFunctionCollapse.solve`, `LSystem.expanded`, `ShapeGrammar.run`, and `WangTiles.fill` take `randomness`, so they follow the sketch's `variation` and need no generator of their own. [Random](Docs/Generators/Random.md#randomness)
- **A palette reads as the collection it is.** `for color in palette`, `palette.enumerated()`, `map`, `first`, `isEmpty`, `reversed()`, `Array(palette)`, and `palette.randomElement(using: &randomness)` all work, with no `.colors` in the way. The wrapping `palette[i]` is unchanged and read-only, so a change still goes through `colors`. [Color](Docs/Drawing/Color.md#palette)
- **`Vector2` and `Vector3` share one `Vector` protocol.** `length`, `normalized`, `distance(to:)`, `lerp(to:_:)`, `limited(to:)`, `projected(onto:)`, `with(x:)`, the arithmetic, and the constants are written once for both. A helper written against `Vector` takes either kind of point, `centroid` averages either, and a type of your own can conform. No call or number changed. [Geometry](Docs/Drawing/Geometry.md#vector)
- **Each vector type keeps what does not carry over.** `cross` is a `Double` in the plane and a `Vector3` in space. `Vector2` keeps `angle`, `perpendicular`, the signed `angle(to:)`, and `rotated(by:)`. `Vector3` keeps `unitZ` and `xy`. [Geometry](Docs/Drawing/Geometry.md#vector)

**3D and the phone**

- **A light with a reach.** `pointLight(..., reach: 11)` bounds how far a light carries: full strength at the source and nothing at `reach` and beyond. `pointLight`, `spotLight`, `rectangleLight`, `diskLight`, `tubeLight`, and the matching `Light` factories take it, and `Light.reaching(_:)` sets or clears it. Left off, a light is unbounded as before. [3D](Docs/3D/3D.md#reach)
- **Up to 256 lights in a frame.** A frame now carries up to 256 lights, where it carried eight. Past eight, a pixel is shaded only by the lights whose reach arrives there. Shadows, visible air, bounced light, and the path-traced export still read the first eight. See `Examples/3D/Lighting/ManyLights`. [3D](Docs/3D/3D.md#reach)
- **The sketch tells the phone what to look for.** `device.use(.markers)` asks the phone for a mode, and `device.look(for:)` hands it the pictures to find, each with its printed width. The device repeats both on every connect. A tap on the phone wins, and `device.latestState` says where it landed and what the phone could not use. See `Examples/3D/Phone/PhoneMarkers`. [Phone](Docs/3D/Phone.md#saying-what-to-look-for-from-the-sketch)

**Simulation and sound**

- **A crowd that makes room.** `Crowd` walks a crowd through itself with nobody overlapping while there is room to move. `crowd.add(at:goal:)` places a walker, and `addObstacle` and `addWall` build rooms and corridors. `preferredVelocity` replaces goals with a rule of your own, and `isJammed` marks walkers with no safe move. `drawCrowd` draws them. `Examples/Simulation/Crowd` has four scenes. [Crowds](Docs/Simulation/Crowds.md)
- **A sound played as a cloud of grains.** `synth.grainSource = GrainSource(contentsOf: url)` and `Voice(granular: GrainCloud(size: 0.08, density: 40, speed: 0))` play a sound as short grains. The grains keep the note's pitch while the place they are cut from moves at `speed` alone. `speed: 0` holds one moment, and `synth.grainScrub` drags it through the sound. [Synthesis](Docs/Helpers/Synthesis.md#grains)
- **The shape of a grain cloud.** `size`, `density`, `positionJitter`, `pitchSpread`, `panSpread`, and `scatter` set the cloud. `GrainShape` is the cut each grain is made with, and `.cloud`, `.smear`, and `.rain` are three places to start. `GrainShape.level(at:)` and `Synth.grainCount` draw it. See `Examples/Audio/Grains`. [Synthesis](Docs/Helpers/Synthesis.md#grains)

**Export and output**

- **A sketch as a widget on the desktop.** `ollin new <name> --kind widget` writes an app with a WidgetKit extension inside it, and `./build.sh --install` installs it. A widget is redrawn a few times an hour. The sketch spaces its pictures with `override var widgetTimeline: WidgetTimeline { .every(minutes: 15, count: 4) }`. [Widget](Docs/Output/Widget.md)
- **The clock in a widget, and `date` on every sketch.** In a widget `time` is seconds since midnight of the moment drawn, `deltaTime` is the spacing, and `frameCount` is 1. `date` is new on every sketch: the moment a frame stands for. A day schedule's `scheduledPeriod` now reads it too. [Widget](Docs/Output/Widget.md#the-clock-is-the-time-of-day)
- **A widget's run as pictures.** `--export-widget <dir> [--size WxH]` writes the whole run as pictures named by the moment, on any sketch, so a piece for this surface can be judged in a second. [Widget](Docs/Output/Widget.md#seeing-the-run-without-waiting-for-it)
- **A GIF export says what it will cost before it runs.** When a GIF would need more than an eighth of the machine's memory, the export prints the figure before the first frame. It names two ways down: `--gif-width`, or `--export-video`, which has no such ceiling. The file itself is unchanged.

**Live coding**

- **An edit that does not start the piece over.** OllinLiveCoding reads each ⌘↩ against the code the stage was built from. If only the inside of a method changed, and `setup()` was left alone, the run carries on through the swap. The canvas, the clock, and the random and noise streams come across. [Live coding](Docs/Tools/LiveCoding.md#what-the-edit-changed)
- **What travels, and what starts over.** `@Saved` is how a sketch says which properties should travel. Change a declaration, `setup()`, or anything `setup()` calls, and the swap starts the run over, as ⌘⇧↩ does. The toast names which happened. For a framework caller the new argument is `SketchRunner.reload(to:keepClock:keepRun:)`. [Live coding](Docs/Tools/LiveCoding.md#what-the-edit-changed)

**The Guide and examples**

- **The Guide teaches every tool it lists.** OSCQuery and `ollin doctor` were the last two capabilities with only a mention and an example. Chapter 28 gains *The sketch that says what it takes*, and Chapter 1 gains *Asking the machine what it has*, both with figures. [Hello Ollin](Guide/01-HelloOllin.md)
- **Casey Reas joins the recreations.** [`Examples/Recreations/CaseyReas`](Examples/Recreations/CaseyReas/) carries out two written instructions of the kind his *Process* works are made of. In `Touching`, circles that are never drawn leave a line between their centers while they touch. In `Planes`, lines that turn toward what they touch leave a quadrilateral through each touching pair's endpoints.

### Changed

Each of these is a rename that can stop a sketch from compiling.

- **The GPU simulations step.** `updateSwarm`, `updateParticles`, `updateSimulation`, `updateParticleLife`, `updateParticleLenia`, `updateParticleFluid`, `updateSoftBodies`, `updatePhysarum`, `updatePrimordialParticles`, `updateSwarmChemistry`, `updateAttractorFlow`, and `updateEvolution` are now `stepSwarm`, `stepParticles`, and the rest with the same suffix. `Boids`, `ForceLayout`, `Meander`, and `DifferentialGrowth` already spelled it `step`. `BeatFollower.update(at:)` is `advance(to:)`, which leaves no `update` in the public API.
- **A smoothed value jumps.** `$x.set(v)` is now `$x.jump(to: v)` on `@Eased`, `@Smoothed`, `@Sprung`, and `@Param`, and on the `DampedSpring` and `OneEuroFilter` values under them. It arrives with no glide and drops the filter's history, as it did.
- **A random point in a ring says so.** `ring(innerRadius:outerRadius:)` is now `randomVector(innerRadius:outerRadius:)`, beside `randomVector(in:)`. The old spelling was the one `SDF.ring(innerRadius:outerRadius:)` uses for the shape.
- **An index of refraction is `ior:` everywhere.** `refractedRays(through:from:index:closed:)` and `caustic(through:from:index:closed:)` now take `ior:`, the label `Material`, `MeshMaterial`, `LensInterface`, and `Filter.thinFilm` already use.
- **A Boolean label is a participle.** `.mask(channel:inverted:)`, `.masked(by:channel:inverted:)`, `.lumaKey(low:high:inverted:)`, and `.adaptiveThreshold(window:bias:inverted:)` took `invert:`. `.mirror(vertical:flipped:)` took `flip:`, and `.tile(count:mirrored:)` took `mirror:`. `elementaryCA` and `totalisticCA` take `wraps:` (was `wrap:`), and `map(_:_:_:_:_:clamped:)` took `clamp:`.
- **A listing that asks the system is `available…()`.** `MIDIInput.sources` is now `availableSources()`, `MIDIOutput.destinations` is `availableDestinations()`, and `ScreenCapture.apps()` is `availableApps()`, beside `availableDisplays()` and `availableWindows()`. `DMXReceiver.universeNumbers()` is now the property `universeNumbers`.
- **`detailMapped` fades by an `amount`.** `Mesh.detailMapped(_:normal:scale:amount:)` took `strength:`, and `MeshMaterial.detailAmount` was `detailStrength`.
- **One label for an `Easing`.** `Timeline.to(_:in:curve:)` and the `CameraMove` factories `pushIn`, `pullOut`, `tilt`, and `reveal` now take `curve:` (was `ease:`), the label `@Eased` and `ParamSmoothing.eased` already use.

### Fixed

- **A long export no longer grows until the machine swaps.** An export kept what every frame allocated until the process ended, and now holds one frame's worth from start to finish. The fix covers `--export`, the video, GIF, spatial-video, SVG, PDF, and web exports, a contact sheet, a parameter sweep, and `--skip` warmup frames (issue #23).

## [0.7.0] - 2026-09-14

This release adds MQTT and OSCQuery, a step sequencer and an arpeggiator, pitch tracking, an ink outline for 3D meshes, and a film look. The phone becomes a touch surface, and `ollin doctor` says what a machine can run. A naming pass made fifty-three renames, so read **Changed** before you update.

### Added

**Drawing and 3D**

- **A film look.** `.halation(threshold:radius:tint:amount:)` puts the warm fringe film shows around its brightest highlights. `.filmGrain(amount:size:seed:)` lays a stock's grain over a layer, most in the middle tones and none at black or white. Both cross to the web page. `Examples/Effects/FilmLook` draws a night street through them. [Effects](Docs/Drawing/Effects.md#filter)
- **The cartoon look.** `outline(width:color:)` draws an ink line around every mesh that follows, `width` canvas pixels wide at any distance, over `.toon` or any finish. `Material.outlineWidth`, `outlineColor`, and `outlined(_:color:)` carry it on a material, and `noOutline()` takes it off. The `Inked` example under `3D/Materials` shows it. [3D](Docs/3D/3D.md#outlines)
- **A light that follows the camera.** `Light.relativeTo(.camera)`, or `LightingPreset.relativeTo(.camera)` for a whole rig, keeps a light placed around the eye as the camera orbits. `headlight()` is a light from the eye down the view. World space stays the default. [3D](Docs/3D/3D.md#camera-relative)

**Simulation**

- **Two more fields that evolve.** `.smoothLife(radius:birth:survival:intervalSoftness:cellSoftness:)` runs Rafler's SmoothLife, the Game of Life's rule on a continuous field, with the paper's glider parameters as defaults. `.predatorPrey(halfSaturation:predatorGrowth:predatorDeath:steps:)` puts prey and predators on one land, where the wake winds into spiral waves. Both run on `makeSimField`. SmoothLife joins the `Simulation/Automata` picker, and `Simulation/PredatorPrey` is new. [Effects](Docs/Drawing/Effects.md#simfield)
- **Spins against the heat.** `.ising(temperature:field:sweeps:seed:)` runs the Ising model on a field. A cold field grows into domains, a hot one is noise, and at `Sim.isingCriticalTemperature` clusters come in every size. `IsingSpin` names the two levels for the brush, and the rule joins the `Simulation/Automata` picker. [Effects](Docs/Drawing/Effects.md#simfield)
- **Fireflies in step.** `Kuramoto` is the model of synchronization, on the CPU: a crowd of oscillators, each pulled toward the phase of the others. It reads `coherence` and `meanPhase`, and has `criticalCoupling`, a `lag`, and a ring `range`. `Examples/Simulation/Kuramoto` is a meadow of fireflies falling into step. [Coupled oscillators](Docs/Simulation/Oscillators.md)

**Sound**

- **A step sequencer.** `StepSequencer` is a bar of steps read against the beat. Each step is a note or a rest with its own velocity, probability, and ratchet. The bar has `swing`, `rate`, `gate`, and `seed`. Write one as `"36 . . 36 . . 36 ."` or from a `Rhythm`. See `Examples/Audio/Sequencer`. [Composition](Docs/Helpers/Composition.md#stepsequencer)
- **An arpeggiator.** `Arpeggiator` plays whatever is held, one note a step, in any `Arpeggio.Pattern` over any number of octaves. Hold notes with `hold(_:)` and `release(_:)`, or set `notes` from a controller's held keys. `latches` keeps the last chord playing. [Composition](Docs/Helpers/Composition.md#stepsequencer)
- **Scheduled notes land on their sample.** The sequencer and the arpeggiator hand back `ScheduledNote`s, each with its beat, and `Synth.play(_:tempo:from:)` plays them to the sample. `Synth.play(_:velocity:for:after:)` gains `after:`, a wait in seconds that lands a note on its own sample, live and in an export. [Composition](Docs/Helpers/Composition.md#stepsequencer)
- **The note being sung.** Every audio source now has `pitch`: the fundamental in hertz with a confidence, the nearest note, and the cents off it. `note` is the short form, and `chroma` is the twelve pitch classes. `Audio/Tuner` follows the bundled violin, or the microphone with `--mic`, and `Audio/GuitarTuner` tunes a guitar. [Audio](Docs/Helpers/Audio.md#pitch)

**The phone**

- **The phone as something you play.** Tap Touch in Ollin Capture and every finger on the screen reaches the sketch, with no camera running. `PhoneDevice.touches` reads `down`, the fingers on the glass with a number, a place, and a contact width each, and `taps()` drains the landings. `Examples/3D/Phone/PhoneTouches` plays it. [Phone](Docs/3D/Phone.md#the-screen-as-a-control-surface)
- **The barometer.** Tap Air and `latestAir` carries the pressure in kilopascals. It also says how far the phone has risen since it started measuring, good to about a tenth of a meter. Lifting the phone becomes a control that needs no camera. [Phone](Docs/3D/Phone.md#the-air-around-it)
- **How the phone's picture is moving.** Tap Flow and a tethered iPhone measures optical flow on its rear camera. `PhoneDevice.latestFlow` reads as the Mac's `FlowTracker` field does, through `vector(at:in:)`, `samples(in:every:)`, and `averageFlow(in:)`, and adds `interval`, the time between its two frames. `latestFlowFrame` is the frame it was measured on. [Phone](Docs/3D/Phone.md#how-the-picture-is-moving)
- **`MotionField` lives in the core.** It moved from `OllinVision` and is now built from a closure, so a source of your own can produce one. A sketch that imports `Ollin` sees it unchanged.

**Connections**

- **The message bus a building speaks.** `import OllinMQTT`, and `MQTTClient(host:)` connects a sketch to a broker. `subscribe(to: "home/+/temperature")` takes every room's reading. Read the latest on a topic, everything since the last frame, or bind it to a `@Param`. `MQTTMessage` reads a number, a switch word, or a JSON field through `number(named:)`. See `Examples/Integration/MQTTRoom`. [MQTT](Docs/Integration/MQTT.md)
- **MQTT for a piece left on a wall.** A sketch publishes the same way, and a retained publish reaches the next sketch to subscribe. A `MQTTWill` is what the broker publishes if the machine is cut off. A lost connection reopens after a backoff and puts back every subscription and unacknowledged message. [MQTT](Docs/Integration/MQTT.md)
- **The sketch says what it takes.** `extend(OSCQueryServer())` publishes every `@Param` as an OSCQuery namespace. A control app such as TouchOSC, Chataigne, or ossia score lists the sketch, builds its own controls, and sends values back over OSC. `namespace()` hands the sketch the same tree as an `OSCQueryNode`. `Examples/Integration/OSCQuery` draws the tree it serves. [OSCQuery](Docs/Integration/OSCQuery.md)
- **A color on the OSC wire.** `OSCArgument` gains `.color`, the OSC 1.1 `r` type, read and written as a `Color`. An exhaustive `switch` over the arguments needs the new case. [OSC](Docs/Integration/OSC.md#oscmessage--arguments)

**Parameters and the live window**

- **`--list-params` says what a sketch declares.** It prints every `@Param` with its name, its kind, its value, and what it accepts. It runs `setup()` first and honors what is given beside it, so `--list-params --param radius=200 --cue dusk` describes that run. Each value is in the spelling `--param` reads back. [Export](Docs/Output/Export.md#saying-what-a-sketch-declares)
- **A frame rate and a paper size are menus in the inspector.** `@Param var rate: FrameRate = .film` and `@Param var sheet: PaperSize = .a4` present pop-up menus. The sheets go by their own names (Letter, Legal, Tabloid), which is also what `PaperSize(named:)` takes. [Parameters](Docs/Helpers/Parameters.md)
- **The edit lands in two speeds.** On ⌘↩ OllinLiveCoding puts a plain build on stage the moment it compiles. The optimized build replaces it when ready, with the clock carried both times. `--single-build` waits for the one optimized build. In the engine it is `SketchSession.landsPlainBuildFirst` and `isOptimizing`, with `InspectorStatus.optimizing` on the chip. [Live coding](Docs/Tools/LiveCoding.md#the-evaluate-loop)
- **A name completes under the caret.** OllinLiveCoding lists what the Swift toolchain's completion service knows at the caret. Return or Tab takes a row, and a call lands with its arguments as placeholders that Tab walks. View ▸ Complete as You Type turns the automatic list off. `CodeCompleter` in OllinRuntime is the engine. [Live coding](Docs/Tools/LiveCoding.md#completing-a-name)

**Tools**

- **`ollin doctor` says what this machine can run.** It checks macOS, `swiftc`, the GPU and what it supports, and the shader compiler. It also checks which `ollin` is on the path, the completions, and the camera, microphone, and screen recording permissions. An unsettled answer carries the line that settles it, and nothing asks for a permission. [Doctor](Docs/Tools/Doctor.md)
- **A shell that knows the flags.** `ollin install` now puts zsh completions in place. They cover the subcommands after `ollin` and the flags of the one you are typing, each with a line on what it does. `ollin completions` prints the file for putting somewhere yourself. [Single-file sketches](Docs/Tools/SingleFile.md#install-the-command)

**The Guide and the reference**

- **Ten Guide chapters teach more of their tools.** Chapters 7, 9, 16, 19, 20, 22, 28, 30, 31, and 32 gain twenty-three figures. Chapter 28 now has sections for timecode and OSC, Chapter 30 one for the camera fallback, and Chapter 31 for transparent output and the broadcast grid. [The Guide](Guide/README.md)
- **Chapter 9 reads photographs.** Its figures and its closing sketch use the bundled pictures, where they used a sunset painted in code. Chapter 31 proofs the marigolds against the press. Authoring a picture pixel by pixel stays as a pointer to the `PixelField` example.
- **The reference's Swift is compiled.** `Scripts/check-snippets.sh` now compiles every Swift block in the `Docs/` pages beside the Guide's. `Scripts/check-api-names.sh` reads the public surface under `API/` against the naming rules, and its first run named the renames under **Changed**.

**Examples**

- **A homage after Ryszard Winiarski.** [`Examples/Recreations/RyszardWiniarski`](Examples/Recreations/RyszardWiniarski/) reads two of his rules. *Obszar* fills a gridded square field by field, each decided by a coin, a die, or a rising share of black. *Losowanie dwiema kostkami* lays black and white runs whose every length is the sum of two dice.
- **A homage after Vicente Rojo.** [`Examples/Recreations/VicenteRojo`](Examples/Recreations/VicenteRojo/) reads two of his series. *Negaciones* paints the letter T only as the shadow a T-shaped block would cast, a wall of them repainted one panel at a time. *México bajo la lluvia* is rain crossing a square as a grid of small marks.

### Changed

The renames below can stop a sketch from compiling. Each gives the old name and the new one.

- **Sketches compile faster.** Every sketch compile is one whole-module job (`-wmo`), in every host that compiles a sketch. A 20-line sketch compiles in 0.6 s, where it took 1.0 s.
- **Limits spell `min…`/`max…`.** `ParametricLSystem.taperedTree(minimumLength:)` takes `minLength:`, and `ContourDetector.detect(in:…maximumDimension:)` takes `maxDimension:`. `HandTracker`'s `maximumHandCount` is now `maxHandCount` in the initializer, the property, and `detect(in:maximumHandCount:)`. `TrajectoryTracker`'s `minimumObjectRadius:` and `maximumObjectRadius:` are `minObjectRadius:` and `maxObjectRadius:`.
- **The laser's limits too.** `ILDAFile.maximumPointsPerFrame` is now `maxPointsPerFrame`, `EtherDreamDAC.maximumBatch` is `maxBatch`, `EtherDreamDevice.maximumPointRate` is `maxPointRate`, and `LaserSafety.maximumBrightness` is `maxBrightness`.
- **Every public `seed:` is an `Int`.** `seed: variation` now needs no `UInt64(...)` around it. The types that took a `UInt64` are `Boids`, `AntColony`, `ContinuousPacking`, `CrackGrowth`, `DielectricBreakdown`, `DiffusionLimitedAggregation`, `ForceLayout`, `Kuramoto`, `MeshGrowth`, `MeshReactionDiffusion`, `Vehicle`, and `Population`. `SplitMix64(seed:)`, the generator itself, keeps its `UInt64` state word.
- **Seeded constructors take an `Int` as well.** `DifferentialGrowth` and its `line` and `ring`, `Meander` and its `line`, and `NBody.cluster` and `.disk` take an `Int` seed. So do `Heightfield.diamondSquare` and `.eroded`, and `population(count:genes:seed:)` on `Sketch`.
- **Configuration Booleans read as assertions or state.** `Fit.Result.settled` is now `isSettled`, and `CloudAlignment.applied` is `isApplied`. `PathTracing.denoise` and its `denoise:` label are `denoises`. `DifferentialGrowth.fixedEnds` and its label are `hasFixedEnds`. `SchottkyPairing.fromExterior` and `toExterior` are `mapsFromExterior` and `mapsToExterior`. `Wheel3D.driven` is `isDriven`, and the `wheel(at:…driven:)` label stays.
- **One spelling per kind of step.** `PingPong.advance()` and `PingPongTexture.advance()` are now `swap()`. `TimelineModel.step(byFrames:)` is now `step(_:)`.
- **How much of an effect is `amount`.** `Generator.grainGradient(…intensity:…)` and `Generator.pulsingBorder(…intensity:…)` now take `amount:`. `intensity` stays for light.
- **A loader spells `withExtension:`.** `PhysicsSnapshot(resource:extension:in:)` is now `PhysicsSnapshot(resource:withExtension:in:)`.
- **The state follows the verb.** `SyphonClient.isActive` is now `isConnected`, and `SyphonClient.stop()` is `disconnect()`.
- **A destination is a path.** `Automation.write(to:)`, `Take.write(to:)`, `PhysicsSnapshot.write(to:)`, `World3D.save(to:)`, and `ILDAFile.write(_:to:name:company:projector:)` take a `String` path beside the `URL` they took before.

### Fixed

- **An iPad app running on the Mac.** The framework now builds and runs under Mac Catalyst, which is how an App Project previews on the Mac. The Mac and the phone compile as before.
- **A cape sinking into the back it hangs on.** A skeleton-carried surface whose mesh was wound to face the figure passed through it. Behind is now toward the figure whichever way the mesh is wound.
- **`drawPlane` faces the way its normal says.** The plane named +y as its normal and wound its quads to face -y. The new ink outline drew every such floor as a slab of ink. Its quads now wind counter-clockwise seen from above.

## [0.6.0] - 2026-09-13

### Added

- **Chapter 26 of the Guide shows its temporal tier.** Four figures join *Sculpting with fields*. Two magnify the same exported pixels with temporal anti-aliasing and specular anti-aliasing off and on, beside a sixteen-sample reference for the second. Two are diagrams: what each tier of temporal upscaling renders and how four jittered frames cover the canvas, and which frames interpolation draws, makes, and shows. [Traced light](Guide/34-TracedLight.md)
- **A note under the finger.** `noteOn` hands back a `PlayingNote`, and `bend(_:semitones:)`, `press(_:_:)`, and `slide(_:_:)` reach that one note while it sounds: the pitch on every source but the struck body, the bow or the breath of a driven voice and the level of any other (`Voice.pressureAmount`), and the filter's cutoff (`Voice.Filter.slideAmount`); `pitchBend` bends the whole instrument. On the MIDI side, `MIDIInput.heldNotes` reads every held note with its bend, pressure, and slide resolved, per note on a polyphonic-expression surface (`mpeZones`, laid out from the controller's own configuration message) and per channel on a plain keyboard, and `MIDIOutput` sends bends, pressures, registered parameters, and a zone. [Expression](Docs/Helpers/Synthesis.md#expression), [Per-note expression](Docs/Integration/MIDI.md#per-note-expression-mpe)
- **The phone's ears.** Switch **Hear** on in Ollin Capture and a tethered iPhone names the sounds around it on the phone itself, with only the labels crossing the cable. `PhoneDevice.sounds` gives the same level and trigger reads the Mac's `SoundClassifier` gives, `confidence(of:)`, `topClassification`, the draining `events()`, and `timeSinceHearing(_:)`, over the same values, with the threshold set on the Mac. `SoundClassification` and `SoundEvent` now live in the core, so `import Ollin` alone spells them. [What the phone hears](Docs/3D/Phone.md#what-the-phone-hears)
- **A frame rate you can name.** Every export's `fps:` takes a `FrameRate`. A number still stands in, so `fps: 60` reads as before, and `.film`, `.pal`, `.ntsc`, `.ntscFilm`, and `.ntscDouble` name the rates whose numbers are awkward, kept as exact fractions so a clip at `.ntsc` lands every frame on 1001/30000 of a second. `--fps` takes a name, a number, or a fraction. [Frame rates](Docs/Output/Export.md#frame-rates)
- **A sheet by name for the machine exports.** `GCode(.plotter(), paper: .a4)` and `DXF(paper: .a3)` size a drawing for a sheet with a margin clear on every side, holding its height as well as its width. `PaperSize` carries the ISO A series and the US three, turns with `.landscape`, and reaches the canvas presets through `canvasSize(dpi:)`; `--gcode-paper` and `--dxf-paper` do the same from the command line. [A named sheet](Docs/Output/GCode.md#a-named-sheet)
- **The screen angles, said out loud.** `PrintSeparation.screenAngles(for:)` returns the angles a separation's halftone gives your inks, and `ProcessSeparation.screenAngles` is the four-color rosette in plate order, so a proof can label them or a sketch can screen its own masters at the same angles. `LaserOptimizer(pointsPerSecond:refreshRate:)` takes a projector's two numbers in one line.
- **Two more automata on a field.** `.wireworld()` is Silverman's computing automaton, a circuit typed as text with `WireworldCell` naming its four states, and `.schelling(preference:vacancy:mobility:passes:seed:)` is Schelling's board of two kinds sorting itself from a mild preference, with `SchellingCell` for the brush; both join the `Simulation/Automata` picker. [Simulation fields](Docs/Drawing/Effects.md#simfield)
- **A rule typed where the parameter is set.** In OllinLive, right-click a number's or a switch's diamond for *Write a Rule*, and a field opens under the row. Return drives the parameter from the rule, an emptied field takes it away, and a rule that cannot be read stays in the field with a caret under the character it went wrong at. The rule lands in the same automation file as the keys. [Writing a rule in the row](Docs/Tools/Timeline.md#writing-a-rule-in-the-row)
- **A homage after Sol LeWitt.** `Examples/Recreations/SolLeWitt` carries out two of his instructions: *Wall Drawing 118*, fifty points at random all connected by straight lines, drawn wall after wall at a drafter's pace, and the forty-five two-part combinations of his 1972 compass alphabet on one sheet, with the spacing he left to the drafter breathing.
- **A look from a `.cube` file.** `ColorLUT` reads the color table a grading tool exports, in both its forms, and `.lut(_:amount:)` applies it to a layer or the whole frame, a cube by tetrahedral interpolation. A look can also be built in code and written out as a `.cube`, and one warm print ships with the framework. [Looks](Docs/Drawing/Looks.md)
- **The pitch moves without the length, an instant can be held, and a recording can be stretched.** `.pitchShift(PitchShift(semitones:mix:))` and `.freeze(Freeze(amount:))` join the effect chain, both a phase vocoder that keeps every partial whole, and `stretched(by:)` on a `Recording` or an `ImpulseResponse` gives it back longer at the same pitch. [The two that work in the spectrum](Docs/Helpers/Synthesis.md#the-two-that-work-in-the-spectrum)

### Changed

- **`fps:` is a `FrameRate` rather than a `Double`** on every export entry (`OllinApp.image`, `export`, `exportSequence`, `exportVideo`, `exportGIF`, the vector, spatial, web, sheet, and separation exports). A literal compiles unchanged; a `Double` variable needs `FrameRate(rate)`.

### Fixed

- **The reference and the Guide named calls the code no longer spells.** Seventy-odd backticked names had gone stale behind a rename: `.bloom(threshold:intensity:radius:)` where the label is `amount:`, `hopfBases(spiral:)` for `spiralCount:`, `frameRendered(_:_:)` for `frameRendered(_:image:)`, `Mesh(resource:extension:in:)` for `withExtension:`, and their kin across the effects, physics, and 3D pages. A gate reads every name in backticks against the tree and the public surface now, so the next rename cannot leave a page behind.

## [0.5.0] - 2026-09-12

### Added

- **Every Guide chapter opens on its sketch running.** On the website a chapter's first picture is a clip of the sketch that chapter builds, with the committed still as its poster. The markdown is unchanged, so a clone, GitHub, and a reader who blocks video see the still they always saw. `Scripts/guide-clips.sh` records them, and the manifest moved to `Media/media.json`.
- **A frame for a compositor, in linear light.** `--export-exr <path>` writes one frame before the tone map and the eight-bit rounding, and `--export-sequence <dir> --exr` a folder of them. Red, green and blue hold the light itself, alpha holds coverage, and a 3D camera adds a `Z` channel. In code, `OllinApp.exportEXR`. [Linear frames](Docs/Output/Export.md#linear-frames-exr)
- **Solids cut each other.** `union(_:)`, `intersection(_:)`, `subtracting(_:)`, and `symmetricDifference(_:)` on a `Mesh` are the four set operations a filled `Shape` already had, carried into space. What comes back is an ordinary closed mesh, and cutting is CPU geometry, so cut in `setup()`. [Cutting solids](Docs/3D/3D.md#booleans)
- **Things break.** `fractured(into:seed:)` cuts a `Shape` or a `Mesh` into convex pieces that fit back together exactly, and a point makes them crowd around the blow. With it: `convexHull(of:)` in space, `Shape.area`/`centroid`/`bounds`/`separated()`, `Mesh.volume`/`centroid`, and `World.remove(_:)`. [Fracture](Docs/Generators/Fracture.md)
- **The site tells a search engine what it holds.** `/sitemap.xml` lists every page the build writes, each at the address its own canonical link claims, and `/robots.txt` names the sitemap. Neither is written when the site has no address of its own.

### Fixed

- **`every(_:)` missed its beat at zero in the live window** while every export of the same sketch fired it. The window's first frame has a `deltaTime` of zero, which put the start of the clock on the crossing rather than before it; it borrows a nominal frame now, and `after(0)` fires on the first frame.
- **A 2D body built from an outline of more than eight corners had no collider at all**, so it had no shape, no mass, and hung in the air where it was born. An outline past the solver's limit of eight is now reduced to the eight corners that keep the most of it.

## [0.4.0] - 2026-09-11

### Added

- **The API reference is generated from the source as well as written by hand.** Every public symbol of the twenty-two library modules has a DocC page, with the core's four hundred and seventy top-level names grouped on one landing page. `Scripts/api-docs.sh` builds it locally and fails on a documentation warning, which is how forty stale doc comments came to light.
- **The site can be read by a machine, not just rendered for a person.** Every page has a markdown twin at the same address with `.md` in place of `.html`, and `/llms.txt` is a curated index pointing at those twins. Nothing fetches it automatically.

### Changed

- **The front page's sketches are a band you page through, and a phone gets them too.** *Hello, circle* now leads a row of sketches, each running beside the program that draws it, in place of the separate band of three. Paging is the browser's own scrolling, and only the sketch on screen is fetched.

### Fixed

- **The Syphon satellite works from a package dependency again.** Any project that pulled Ollin in by version, which is what `ollin new --remote` writes, could not use `OllinSyphon` at all: the build stopped at resolution with `the target 'CSyphon' in product 'OllinSyphon' contains unsafe build flags`. The vendored engine's prefix header is now imported per file rather than forced in with an unsafe flag, and nothing about the running code changed.
- **The site's favicon no longer sits in a white box in Safari's tabs.** Safari draws a light plate behind an icon whose own tone reads too close to the bar it sits on. The mark is drawn on nothing now, and the page picks between a near-black file and a paper one, since Safari ignores a color-scheme query inside an SVG favicon.

## [0.3.0] - 2026-09-10

### Added

- **Every example can show what it does, not just what it says.** `Scripts/media.sh` renders a clip and a still and puts them where the site reads them, so an example's page plays the clip with the still as its poster. Three hundred and fifty-three examples have theirs; the rest are written down with the reason they do not.
- **Four vision examples work with no camera plugged in.** The mirror that grows Turing patterns takes the bundled dancer, the object tracker the wrestler, the depth contours the street, and the contour tracer is told which way round its contrast runs. Two are unchanged and honest about it: the barcode reader has no bundled code to read, and the trajectory tracker draws its own ball.
- **The guide and the README open on the work.** The guide's first picture is the sketch each of its thirty-two chapters builds, one per cell, and the README's is thirty-two examples from every area of the framework. On the website both play. The markdown carries the still, which is what GitHub and a plain clone can show.
- **Every examples listing opens on a grid of its sketches.** Each picture links to the sketch and carries its name, and on the website resting the pointer on a cell swaps its still for a short clip, with nothing fetched until then. The 3D folder became ten pages on the way, since a hundred and thirty-seven sketches could not take one grid.
- **Thirteen figures stopped faking what they teach.** The Guide's optical-flow, slit-scan, contour, saliency and detector figures used to author their subject in code, a dancer made of two speckled discs or a clip made of sine stripes. They read the bundled film and photographs now, so what a reader sees is what the technique does to a real picture.
- **`VideoPlayer.snapshot()` works offline.** Under a headless export it reads the same virtual playhead the frame does, so `seek(to:)` and then `snapshot()` hands back exactly the moment asked for. A still-image `detect(in:)` over a clip now works where a live tracker reads nothing, which is what lets a figure measure optical flow on any machine.
- **A sketch that reads the world still runs when the world is not plugged in.** `Camera.orStill(_:)` gives back a running camera where the Mac has one and a still picture where it does not, and everything downstream takes either. Fourteen vision examples now fall back to a bundled photograph instead of showing a notice. `--photo` takes the picture even where a camera would have worked.
- **`StillFrames`.** One picture published as both a `VideoFeed` and a `FrameSource`, so it stands wherever a camera or a video player would. It republishes a few times a second rather than once, because an analyzer drops frames it cannot keep up with and a single frame could be the one dropped.
- **A photograph in the color-vision check.** `Color/ColorVision` and the Guide's figure show a picture beside the palettes, seen the same four ways: the woven blankets, where the two commonest kinds flatten the weave to one olive band while the blues hold.
- **A pair of hands worth tracking.** `SamplePhoto.hands` joins the bundled set, two open palms against a dark ground with every finger separated, and `Vision/HandTracking` reads it instead of the breakdancer. Both hands come back with all twenty-one joints; the breakdancer's are planted and half closed, which gives the drawing almost nothing to show.
- **A short film, for what a still cannot show.** `SampleClip.dance` joins the bundled set: thirty seconds of a dancer on a plain studio ground, 960 square, silent, 1.5 MB, with the camera locked off. `Vision/OpticalFlow` and `Vision/ContourTrace` read it where there is no camera, having shown nothing at all before.
- **The optical-flow overlay reads any source.** Its arrows were scaled against a fixed number of pixels, which suits a hand waved at a webcam and drew almost nothing for a dancer moving a few pixels a frame. Length and color now read against that frame's own fastest motion, so the field is legible whatever it is pointed at.
- **A page under uneven light, and two surfaces to wrap a form in.** `SamplePhoto.page`, `.talavera` and `.stone` join the bundled set. The page is what adaptive thresholding exists for, the talavera repeats seamlessly for `3D/Materials/Triplanar`, and the stone carries real relief, so `3D/Materials/Parallax` reads one photograph as both its color and its height map.
- **Two landscapes at dusk, and the first wide pictures in the set.** `SamplePhoto.headland` and `.boats` join the bundled photographs: a headland over the water at Loreto with cacti in silhouette, and small boats off Cozumel under a pink sky. Everything before them was a square or an upright, so a sketch that wanted a landscape had to crop one.
- **Four streets, for the techniques that want a whole scene.** `SamplePhoto.alley`, `.street`, `.textiles`, and `.city` join the bundled set: a Guanajuato alley, a San Miguel de Allende street strung with papel picado, woven blankets at Teotitlán del Valle, and rooftops running back to the hills. Pixel sorting, seam carving, the frequency domain, and the picture-fit example now run on them.
- **`Image.cropped(x:y:width:height:)` and `Image.cropped(toAspect:)`.** The companion to `resized`: that one changes how big a picture is, these change what is in it. The rectangle form is clamped to the picture, the aspect form takes the largest centered piece of a given shape, and nothing is scaled either way.
- **Two tables seen from above.** `SamplePhoto.breakfast` and `.desk` join the bundled set: an Oaxacan breakfast of plates, bowls and cups, and a desk with a laptop, a plant, a watch and a printed notebook. They finish the vision group, and object detection moved to the breakfast, where it finds five things rather than three.
- **Four more photographs, whole figures this time.** `SamplePhoto.reaching`, `.wrestler`, `.dancer`, and `.handstand` join the bundled set: a dancer against a concrete wall, a masked luchador with both arms raised, a contemporary dancer on white, and a breakdancer upside down on one hand. Each is framed upright so no limb runs off the edge, and each yields its skeleton.
- **The body-pose detector answers the first time it is asked.** Vision loads its 2D body-pose model on the first request that needs it, and requests arriving while it loads come back with nobody in the picture. `BodyTracker.detect(in:)` now asks again, up to three times, until the process has seen one pose.
- **Four photographs to work on.** `import OllinSamplePhotos` and `SamplePhoto.portrait.load()` hands a sketch a real picture, each a 1600-pixel square with its `credit` carried in code. A library of its own, so an app that never imports it ships none of them.
- **`Image.resized(width:height:)`.** A resampled copy of a picture, for the small working copy a stipple, a dither, a mosaic, or a winding wants before it reads every pixel.
- **The stylus beyond its press.** `stylus.tilt` is how far the pen leans, so a chisel drawn that way runs thick one way and thin the other; `stylus.twist` is the barrel turn, `stylus.isEraser` which end is down, and `stylus.isNearby` covers hovering. Everything reads zero under a mouse, and the values are recorded into a take. `stylus.tiltIsAvailable` answers the way `pressureIsAvailable` does.
- **A 3D scene on the plotter.** `lineDrawing(of:)` takes meshes and the camera looking at them and gives back 2D paths with everything the surfaces hide taken out: the silhouette, the creases, and the boundary where a surface ends. Being ordinary line work they reach an SVG, a PDF, G-code, or DXF, where a lit mesh reaches none of them. `creaseAngle` is the dial between a drawing and a wireframe, `Mesh.transformed(by:)` places each mesh first, and `hidden` keeps the covered stretches.
- **The three effects that hold a level.** `.compressor(Compressor())`, `.limiter(Limiter())`, and `.gate(Gate())` join the effects chain: what is over a compressor's threshold goes through at a fraction of what it does, a limiter is a ceiling nothing leaves above, and a gate turns the sound down below its threshold. `makeup` brings a compressed phrase back up, and `hold` keeps a gate from chopping a decaying note.
- **Hatching that follows the picture.** `layer.filtered(.hatching())` draws the layer as pen work whose strokes run along its own flow, so the marks bend around a form instead of running across it, and lays down as many of them as the tone is dark. `spacing`, `length`, and `directions` are the pen, the stroke, and how many layers stack.
- **A forest that keeps burning.** `Sim.forestFire(growth:lightning:)` runs the Drossel-Schwabl rule on the GPU: bare ground grows trees, a tree catches from a burning neighbor or from lightning, and a burning cell is bare ground the next step. Nothing in the rule names a density and one arrives anyway.
- **A homage after John Whitney.** `Examples/Recreations/JohnWhitney/Permutations` draws the rule he set out in *Digital Harmony*: points on concentric circles, the first turning once in a cycle, the hundred and fiftieth a hundred and fifty times. Nothing is random, so the fan falls into a star at every simple fraction of the cycle.
- **A table you put things on.** `TUIOReceiver` reads a tangible surface over the network: `cursors` are touches, `objects` printed markers with the symbol and angle read off them, and `blobs` the shapes it found but cannot name. Each report keeps its id while it stays on the surface. `touch.position(in: bounds)` puts one where it belongs, and the receiver is built on the OSC library, so `import OllinOSC` is all it takes.
- **Fog as one value.** `fog(.mist)` takes a `Fog`: a color, a `veil` (how much of a surface at the camera's target distance is fog) and a `pooling` (how fast it thins with height), so the same preset reads alike over a tabletop and a valley. Five presets, and the bare `fog(_:density:heightFalloff:)` is unchanged. `.haze`, `.mist`, `.thick`, `.groundMist` and `.night` are the presets, `tinted(_:)` takes another color, and a `@Param` of the type puts them on the inspector's menu.
- **Cues.** `saveCue("night")` keeps every parameter's value under a name and `cue("night", over: 2)` brings them back over a fade. The live hosts keep them in `Sketch.cues.json` beside the sketch, the performance host calls one from a MIDI program change or `/ollin/cue`, and `--cue night` renders an export at a saved look. `nextCue` and `previousCue` walk the sheet.
- **Transparent output.** A canvas that starts with `background(.clear)` leaves its background behind in every export: the PNG and the sequence carry an alpha channel, the GIF its one transparent index, and a clip keeps the alpha through `--codec proRes4444` or the new `--codec hevcWithAlpha`. The other codecs still composite over black and say so.
- **Files dropped on the window.** Drop a picture, a clip, a font, or a table from the Finder onto a running sketch and it arrives as a path: `droppedFiles()` returns what was dropped since the last call, `filesDropped()` is called once at each drop, and `mouseX`/`mouseY` hold where it landed. Every host takes the drop.
- **DXF, a drawing for the shop.** `--export-dxf panel.dxf` writes the frame as a DXF a CAD program opens in millimeters: strokes as lines along their centerlines, fills as closed polylines, and a circle kept as a circle. Each color goes on its own layer, so a shop tells a cut from a score by the colors you drew in. `--hatch` writes fills as line work, and `DXF(width:)` and `Drafting` are the planner behind it.
- **The four effects that move a sound.** `.chorus(Chorus())`, `.flanger(Flanger())`, `.phaser(Phaser())`, and `.tremolo(Tremolo())` join the effects chain: a copy sliding later and earlier so one voice reads as several, a copy a hair behind sweeping a comb of notches, a row of phase-turning stages, and the level breathing. Each is one slow wave and the thing it moves. `rate` and `depth` are on every one, and a `mix` of 0 is the plain sound exactly.
- **Shock, the picture flattened into regions.** `layer.filtered(.shock())` smooths the layer along its own flow and sharpens it across that flow, round after round: soft shading snaps into flat regions with crisp edges, and grain or grass is drawn out into one coherent stroke, with no color invented. `iterations` sets the level of abstraction. `radius` is how far across an edge the shock reaches, `flow` how far each round smooths along it, and `threshold` the bend under which nothing is sharpened.

### Fixed

- **A compute kernel no longer recomposes the shader library on every dispatch.** Every `compute(...)` call looked its pipeline up by a hash of the kernel's full composed source, which meant reading the shared library, resolving its includes, and hashing the whole text once per dispatch per frame. A kernel written in the sketch's own source is now found by its own text.

## [0.2.0] - 2026-09-08

### Added

- **Newton's basins.** `generate(.newton(roots:))` runs Newton's method from every pixel over the polynomial with the roots you place, up to eight, and colors each pixel by the root it lands on, shaded by how many steps it took. `relaxation` scales the step so the basins swell, spiral, and shed islands. `phase` turns the palette, and a pixel the method never brings home is painted `trapped`.
- **A homage after Frieder Nake.** `Examples/Recreations/FriederNake/HommageAPaulKlee` draws the drawing usually called *Hommage à Paul Klee* (*13/9/65 Nr. 2*, 1965) from Nake's own list of its chance decisions: horizontal bands of rolled width whose edges buckle without crossing, quadrilaterals left empty or filled, and circles thrown over the whole. A seed is a sheet. `--export-svg` gives the plotter drawing back.
- **A board with no firmware of your own.** `FirmataBoard` in `OllinSerial` speaks Firmata over a serial port, so a board running the StandardFirmata sketch every Arduino IDE ships answers pin by pin: `analog(0)` and `digital(2, pullUp: true)` read, and `write(9, 0.5)` and `write(10, angle: 90)` drive a PWM duty and a servo. `bind(analog:to:)` puts a pin on a `@Param`. `write(13, true)` drives a digital pin, and `messages()` drains every decoded message.
- **The public API, written down.** `API/` holds one generated listing per library product, every public type and member with its types, defaults, and deprecation, and `Scripts/api-surface.sh` fails preflight whenever the build and the listings disagree. A change to the public surface is recorded on purpose and reads as a diff in review. This is the ground the 1.0 deprecation discipline stands on.
- **Deriving one easing curve from another.** `Easing.reversed()` runs a curve from its other end, so an ease-in becomes its ease-out, and `mirrored()` puts the curve on the first half of a trip and its reverse on the second. Where the catalog already holds the result the helper hands back the built-in, so it still reads by name on a menu. `.easeInQuad.reversed() == .easeOutQuad`, and mirroring an ease-out gives the out-in curve the catalog lacks.
- **The performance host on a controller.** OllinLiveCoding answers OSC at fixed addresses under `/ollin/` once a port is set in the inspector's Controls card, and learns a MIDI pad, button, or fader for any of them: press Learn, move the control, done. A host preference, never the sketch's, and the map holds across launches. `OllinInspector.Palette` is public, so a host's own card can sit beside the shipped ones.
- **A room of your own: convolution reverb.** `Reverb(impulse, mix:, preDelay:)` plays an instrument through an `ImpulseResponse`: a recording, fading noise, or a room drawn from a rule, and `.reversed()` runs any of them backward. It sits in the chain like the built-in rooms, and turning `mix` never cuts a tail that is sounding. An `ImpulseResponse` comes from `.load`, `.resource`, `.decay(seconds:damping:)`, or a rule; `synth.reverb` still reaches it, and `Effect.Kind` gains `.convolution`.
- **Timecode: a sketch that chases a timeline.** `TimecodeClock(from: midi)` follows MIDI Time Code, the position a video deck, a show controller, a lighting desk, or a DAW locked to picture sends, into `timecode`, `seconds`, `frameRate`, `isPlaying`, and `isReversed`. The `Timecode` value does the drop-frame arithmetic and both wire forms, and `MIDIOutput.send(timecode:)` and `send(sysEx:)` cover the other direction. [MIDI](Docs/Integration/MIDI.md#timecode-timecodeclock)
- **Sharp features from a field: dual contouring.** `isosurface(at:in:resolution:method: .dualContouring)` meshes a field with one vertex per cube placed where the field's own normals meet, so a block's corners land on the corners and a bored hole keeps its rim, where marching cubes rounds every edge off to the size of a cell. [Isosurfaces](Docs/Generators/Isosurface.md#sharp)
- **A homage after Josef Albers.** `Examples/Recreations/JosefAlbers/Homage` puts the *Homage to the Square* format on the canvas, squares of ten, eight, six, and four units each set half a unit lower than the one around it. It rolls a new set of colors on every few seconds from five palette rules of its own, built in OKLCH and crossfaded in OKLab. `--export-grid` prints a wall of them.
- **Search on the website.** Every page `ollin site` writes carries a search: the button in the bar, `/`, or ⌘K opens it, and it looks through the Guide, the reference, and the examples one section at a time, a page's title counting most and its prose least. The matching is [MiniSearch](https://lucaong.github.io/minisearch/) (MIT), pinned to one release by its hash.
- **Embroidery, a frame as stitches.** `--export-embroidery leaf.dst` writes the frame as the stitches an embroidery machine sews, in the Tajima `.dst` file nearly every machine reads: strokes as a running stitch whose every corner is a penetration, fills as connected rows, and each color as its own thread in draw order. `Embroidery(width:)` takes the hoop's real millimeters. `Embroidery.stitches(_:in:)` plans your own contours, so a sketch can draw the stitches before anything sews.
- **Brushwork, the picture as paint.** `layer.filtered(.brushwork())` lays the layer on as paint patches that follow the picture's own flow: each pixel takes the average of the flattest of eight sectors of a brush around it, so detail flattens while edges stay crisp. `radius` is the brush size and `stretch` how far an edge can draw it out. `sharpness` is how decisively the flattest sector wins, and the patches read as strokes along the contours rather than `.oilPaint`'s square dabs.
- **Lighter, darker, and the complement of a color.** `ink.lighter()`, `ink.darker(by: 0.25)`, and `ink.complement` derive a color from one you hold: the first two step its perceived lightness in OKLab units while hue and chroma stay put, the third is the opposite hue at the same lightness and chroma. A gray is its own complement.
- **Gabor noise, a noise whose spectrum you design.** `generate(.gaborNoise())` scatters small Gaussian blobs each carrying a cosine wave and sums them, so the field has one `wavelength` in pixels, a band `bandwidth` wide around it, and one direction or every direction. Brushed metal, wood grain, silk, and rippled water at a turn of the parameters. `impulses` is the quality and `seed` picks the field. The same field is `gaborNoise(x, y, ...)` and the `GaborNoise` type on the CPU, and `gaborNoise(p, ...)` in a shader of your own.
- **XDoG, the picture as pen and ink.** `layer.filtered(.xdog())` draws a line wherever the layer has an edge, solid ink where it is dark, and paper everywhere else, the lines following each edge's own direction so they run continuous rather than breaking into speckle. `threshold` and `softness` are the cut and its ramp. `radius` is the line scale, `sharpening` how far edges are pushed over the tone, and `foreground` / `background` the ink and the paper.
- **Hobby's spline.** `drawCurve(points, spline: .hobby)` threads a curve through points the way a practiced hand does: every gap becomes a Bézier whose control points are solved together, so the bend flows evenly instead of flattening between far-apart points and swelling between close ones. The default spline is unchanged. `.hobby(tension:curl:)` tunes it, `Contour(curveThrough:spline:)` and `Shape(curveThrough:spline:)` take the same choice, and `HobbySpline(through:)` is the typed form.
- **The drag on the performance stage.** Under OllinLiveCoding, hold Command over the stage and the shape under the pointer is outlined through the code; drag it, pull a corner, or turn the knob, and the numbers change in the code on the stage, which the host then evaluates. The file is still written only by ⌘S. `⌘]` and `⌘[` reorder the same way.
- **Dashed strokes.** `strokeDash([12, 8])` cuts every stroke into dashes, dash then gap in the path's own units, and a `phase:` marches them along. Each dash takes the caps, a corner inside one keeps its join, and SVG, PDF, and G-code carry every dash as its own subpath, so a plotter lifts the pen at each gap. `noStrokeDash()` puts the whole line back, `.dots(spacing:)` under `strokeCap(.round)` is a dotted line, and `Contour.dashed(_:)` / `Shape.dashed(_:)` make the same cut as geometry. `drawCircle`, `drawRect`, `drawTriangle`, `drawNgon`, `drawStar` and their neighbors dash too while a dash is on.
- **An app for the phone, from the generator.** `ollin new <Name> --kind ios-app` writes a sketch as an iPhone and iPad app: the sketch, a host that owns the entry point, the property list, and the `project.yml` that `xcodegen` turns into the Xcode project. `--team <id>` sets the signing team. `--team <id>` or `OLLIN_TEAM` sets the signing team; `ProjectRequest` gains `team` and `Capability` gains `staysOnTheDesk`, the refusal a Mac-only capability gets.
- **The logo.** Ollin has a mark: the day sign's crossing bands with an eye at the center and four marks at the cardinal points, in plain geometry. `Logo/` holds it as two SVG masters, black ink on nothing, and the website shows it in the bar and as the favicon, setting the color itself.
- **A tempo, and note lengths with names.** `Tempo` is beats per minute with a `beatsPerBar`: `tempo.beats(at: time)` is what a `StepCounter` wants each frame and `tempo.seconds(of: .eighth)` what a synth's `for:` wants. `NoteLength` names the lengths on a stave, and a number stands in for either. `NoteLength` runs `.whole` down to `.thirtySecond` with `.dotted` and `.triplet` deriving the others, and `seconds(beats:)`, `seconds(bars:)`, `bars(at:)`, and `secondsPerBeat` read the rest.
- **Tensegrities.** `Tensegrity` describes a structure of struts held apart by cables, with three balanced forms ready-made: `prism(struts:)`, the six-strut `icosahedron(strutLength:)`, and a `tower(levels:)`. `World3D.addTensegrity(_:at:)` gives one weight, so it falls, lands on its own cables, and stands. `imbalance` says whether an arrangement of your own can hold, `drawTensegrity(_:)` draws it where it is, and a new `.cable` joint kind is the rope beside `.distance`'s rod.
- **The weather outside.** `Weather(at:)`, `Weather(in: "Oaxaca")` and their siblings read the current conditions over a place every fifteen minutes, as `temperature`, `humidity`, `cloudCover`, the wind, `condition`, and the day's `sunrise` and `sunset`. Nothing throws, a failure keeps the last reading, and an export reads once. `Weather(latitude:longitude:)` takes a point, `precipitation`, `snowfall`, `pressure` and `isDay` come with it, and `Place.sun(at:)` puts the sun in the sky with no network. [Weather](Docs/Helpers/Weather.md)
- **Strokes and fills as points on the web page.** `--export-web` carries a stroke as the points and the style the sketch gave, and the page expands them through the framework's own fringe expander compiled to WebAssembly. The six heaviest pattern examples, at 51 to 325 MB as vertices, cross at 386 KB to 8.7 MB.
- **Parquet deformations.** `parquetDeformation(columns:rows:from:to:sweep:)` lays a tiling whose tile changes shape as you read across it, a square at one edge becoming an interlocking key at the other, with no piece coming apart, because the geometry lives on the lattice's shared edges rather than on the tiles. An edge is a `Profile` in its own frame (`.straight`, `.tooth`, `.zigzag`, `.wave`, `.bump`, or `.custom`) and `Sweep` runs the change across, down, diagonally, or out from the center; read `tiles` for the pieces or `edges` for line work. [Parquet deformations](Docs/Drawing/ParquetDeformation.md)
- **A weight limit on the web page.** `--export-web` refuses a page past 25 MB instead of writing it, and the message says what it would have weighed, which part is heaviest, and the `--max-page-size` that writes it anyway. A dense enough drawing is refused during the recording, so the export never holds frames a page would not get. In code, `maxBytes:` on `OllinApp.web(of:)` and `exportWeb`, and a `WebWeightRefusal` carrying the numbers.
- **Parameters as controls on the web page.** `--export-web` offers a sketch's `@Param`s on the page: each is probed at other settings, and one whose every effect on the picture moves along a line becomes a slider, a stepper, a switch, a color well, or a field per part. One that changes what is drawn stays at its recorded value, and the exporter says why. `--no-controls` skips the probe, and the inline fragment reaches them through the handle (`params`, `get`, `set`, `reset`). [Parameters as controls](Docs/Output/Web.md#parameters-as-controls)
- **Fields on the web page.** `--export-web` carries a composed field (`drawSDF`) as its program, walked on the page over the framework's own arithmetic carried to GLSL, and a raymarched field (`drawSDF3D`) with its camera, its lights, `castShadows()`, and the four shading models. An environment, an area light, and a glass or coated finish still stop the export by name. A `raymarchResolution` below one is traced at the Mac's own fraction. [Fields on the page](Docs/Output/Web.md#fields-on-the-page)
- **A lens as a field of view.** `.focalLength(35)` is the vertical angle a 35 mm lens sees on a full-frame camera, so `fieldOfView:` takes the lens's own number beside `.degrees(_:)`; pass `sensorHeight:` for a smaller format.
- **Ramp stops as values, and a ramp reversed.** `Ramp(stops: [Ramp.Stop])` takes typed stops beside the tuple list, and `ramp.reversed` runs a ramp the other way, a hard edge keeping its colors in mirrored order.
- **Depth of field from light.** `LineSpray` renders an array of `SprayLine`s as depth of field the way a lens makes it: every frame scatters passes of points along the lines on the GPU, pushes each into a `Bokeh` ball that grows with its distance from the plane of focus, and adds it into a running mean. Nothing is blurred afterward, and moving the camera or the lens restarts the average. `makeLineSpray(_:sampling:passesPerFrame:bokeh:)`, `drawLineSpray(_:)`, and `developed(exposure:ground:)` to print it. [Depth of field from light](Docs/Drawing/DepthOfField.md)
- **A running mean of light.** `makeAccumulator()` / `withAccumulator(_:passes:)` / `Accumulator`: a layer that keeps the sum of every pass drawn into it in single-precision float and the number of passes beside it, and hands back the mean as `image`, so a picture built from faint samples converges instead of brightening without end. `reset()` starts it over, `sum` and `passes` are there for a shader of your own, `Filter.develop(exposure:ground:)` prints accumulated light, and `makeRenderTarget(precision:)` and `makeFeedback(precision:)` take `LayerPrecision.float32`. [Accumulation](Docs/Drawing/Accumulation.md#accumulator)
- **Particles as light.** `drawParticles(_:style: .light)` deposits each particle's `color × alpha × area` as linear light with no perceptual remap, and draws a particle at or under one pixel as a single texel, so a million one-pixel points cost a million fragments rather than twenty-five million. The default `.marks` style is unchanged. [The light particle style](Docs/Drawing/DepthOfField.md#light)
- **A kernel that sees the camera.** `Camera3D.viewMatrix`, `projectionMatrix(aspect:)`, `viewProjectionMatrix(aspect:)`, and `matrices(aspect:)` are public; `ComputeParams.append(camera:aspect:)` packs them, and the library's `ollin_project` projects a world point to canvas points inside a kernel. `cameraParams()` does it for the active camera, `ollin_project_eye` takes a camera-space point, and `ballSample(float3)` joins `discSample` in the library. [Projecting through the camera](Docs/Shaders/Compute.md#camera)
- **Settled frames in an export.** `--settle N` (and `OllinApp.exportSettle`) draws each written frame N times with the clock held and writes the last, so a picture that converges over frames settles for every frame of a still, a sequence, a video, or a GIF. The recipe records it; a take and made frames refuse it. An `Accumulator`'s mean or a `LineSpray` through a turning camera settles for every written frame. [Settled frames](Docs/Output/Export.md#settled-frames)
- **Compute binds up to ten buffers.** `compute(_:buffers:count:params:)` hands a kernel any number of `ComputeBuffer`s of any element types at indices 0…9, and `compute(_:reading:writing:)` now takes two element types, so a kernel can read a static geometry buffer and write an `OllinParticle` buffer without packing one into the other. `ComputeBindable` is public, and so is `Color.linearRGBA`, the radiance a light particle carries.
- **Fractal fields.** Three fractals join the raymarched field as leaves: `SDF3D.mandelbulb(power:iterations:radius:)`, `.mengerSponge(iterations:size:)`, and `.mandelbox(scale:iterations:size:)`. They melt, carve, mirror, and repeat like any other leaf, and `3D/Raymarching/RaymarchedFractals` turns each one's own dial.
- **The sketch on the phone.** A sketch runs on an iPhone or iPad as an app, and `ollin phone Sketch.swift` puts it there and installs it again on every save, its clock and parameters carried across, with the parameters live on the Mac. `SketchRunner.beginInstallation` is public, so an app of your own can turn the checkpoint on. [The sketch on the phone](Docs/Tools/OnThePhone.md)
- **A Web example group.** `Examples/Web/BreathingRing` draws the ring of breathing circles the site opens on as a sketch: a sixty-second loop that wraps without a seam, its ink and paper as parameters so a page can set its own theme.
- **A sketch as a web page.** `--export-web` records what a sketch draws over a duration and writes a page that plays it back in a browser, one self-contained file or, with `--inline`, a fragment for a page of your own. A sketch that declares `loopDuration` records one lap and the page wraps it without a seam. Anything that does not cross stops the export and names the call. [A sketch as a web page](Docs/Output/Web.md)
- **Layers and shaders on the web page.** `--export-web` carries the layered effects: layers drawn with `withTarget`, every `Generator`, every `Filter` and `Combine` that is one shader pass (plus `.gaussianBlur` and `.bloom` as passes of the page's own), `postProcess`, a user `Shader` with `info.time` and `info.mouse` live on the page, compiled `Visual` chains, and a `Feedback` layer or a single-field `SimField` keeping its state. The solves, the ladders, and the simulations with pipelines of their own still leave as video.
- **Pictures, atlas text, and gradients on the web page.** `--export-web` carries a picture drawn with `drawImage`, text through the glyph atlas as its quads over the font's page, and a gradient on an analytic shape from the strip the Mac bakes it into. A live texture, such as a camera or a compute texture, still leaves as video. The page draws its first frame once the browser has decoded the pictures, and its handle gains `ready`.
- **Strokes and fills on the web page.** `--export-web` carries every stroke and every fill the triangle path tessellates, as the vertices the Mac would have drawn, a fill's edge anti-aliased through the same four samples, and a blend mode on shapes, strokes, and fills. A dense line drawing makes a heavy page for now, and the exporter prints the size. That is `drawLine`, `drawPolyline`, `drawBezier`, `drawCurve`, `drawArc`, `drawPolygon`, and `drawShape`, and a `Batch` recorded from them replays under its transform.
- **The website.** `ollin site` writes the README, the Guide, the reference, and every example with its source out as a static website, the pages rendered from the same files `ollin docs` reads, with a workflow that publishes it to GitHub Pages. [The reference offline](Docs/Tools/Reference.md#in-a-browser)

### Changed

- **Preflight and CI, cheaper and less fragile.** `Scripts/preflight.sh` runs its gates cheapest first and the figure gate last, sizes its figure workers to the machine's memory as well as its cores, and compares each sample figure against its own last render rather than the committed image. On CI the build is cached between runs, and the Examples job skips its long build when nothing it compiles against changed.
- **The README's catalog moved to the reference index.** The capability table, the list of sixty-six generative techniques, and the 3D layer list now open [`Docs/README.md`](Docs/README.md#the-catalog), above the groups that list every page. The README's *What's in it* section keeps its eight paragraphs and points at the catalog, so the front door is the pitch and the reference is the map.
- **The website's front page is a page rather than the README end to end.** It shows the README's opening and four of its sections laid out for a browser window: the code beside its paragraph, two short sections side by side, and the eight paragraphs of *What's in it* as a grid of cards. The whole README is the About page, one link away.
- **Note lengths and tempos are typed.** `Note.length` and `Sonification.noteLength` are `NoteLength`s, and `Note.seconds(at:)`, `Synth.play(_:tempo:)`, and `Synth.play(_:step:tempo:)` take a `Tempo`. A literal compiles as it did; a `Double` variable becomes `Tempo(bpm)` or `NoteLength(beats:)`.
- **The reader-facing pages in a plain register.** Every reference page, the README, the roadmap, the example lists, and the concept pages are rewritten sentence by sentence: one idea per sentence, plain words, active voice, the same facts. Along the way about a dozen stale API names, several wrong counts, and five figures whose caption disagreed with the picture are corrected.
- **The site opens on the sketch.** The front page now plays `Examples/Web/BreathingRing` as the page `--export-web` records for it, in place of a hand-written copy of the ring: its ink and paper are set to the site's own colors and follow a change of scheme, and a reader who asked for less motion sees its first frame, still.
- **The live hosts compile the sketch optimized.** `OllinLive`, `OllinLiveCoding`, `OllinRun`, and the gallery compile a sketch with `-O`, so a sketch that does real CPU work every frame runs under the live window at the speed `swift run -c release` gives it. `--no-optimize` compiles it plain when you are debugging the sketch itself: asserts fire, and a crash names every frame.
- **Recording and frame sharing no longer draw the frame twice.** A live take, a Syphon feed, the virtual camera, an LED map, and any `SketchExtension` that asks for the rendered frame now receive the frame the window shows, tone-mapped once more inside the frame's own command buffer. A lit 3D scene that recorded at 19 fps records at its unarmed 46, and the frame arrives a refresh or so after `afterFrame`. That covers `startRecording()` and `--record`, and `wantsRenderedFrame` / `wantsRenderedTexture` are read once per frame.
- **A typed box for bounds.** `Box3` replaces the `(min: Vector3, max: Vector3)` tuple everywhere it appeared: `Scene.bounds`, `Metaballs.bounds`, `ShadowArt.bounds`, `PhoneSceneMesh.bounds`, `PhonePlanes.bounds`, and the `in:` box of `isosurface` and `shadowArt`. Reading `.min` and `.max` is unchanged; a tuple literal becomes `Box3(min:max:)`, and `center`, `size`, `longestSide`, `padded(by:)`, and `union(_:)` come with it.
- The `Rendering/DepthOfField` example runs on the accumulating pipeline: a million samples a pass deposited as light into a running mean that converges, with the focus, the lens, and the passes per frame as parameters, instead of a `noClear` pile that brightened forever.

### Fixed

- **A parameter of your own type can be declared.** The parameters page said a full `ParamValue` conformance works, but the initializer it needed was internal, so a type declared outside the framework could not be wrapped at all. `@Param(constraints:)` is now public, and the source write-back keeps a wrapper such as `Opacity(0.5)` around the literal it changes. There is a bare form for a type whose constraints are `Void`.
- **A shader beside a phone sketch reached the phone as a library, not as source.** `ollin phone` listed a `.metal` sibling in the resources build phase, which Xcode compiles; the framework reads a shader's source at run time, so the file was useless there. It now goes through a copy-files phase and arrives as the text it was.
- **A test parked a worker on the environment download.** The remote-HDRI cache had only a blocking download, right on the export path's main thread and wrong from a test body, where it held one of the concurrency pool's few threads. The cache now has an `async` `download(_:)` that suspends instead, the tests use it, and preflight refuses the blocking form under Tests.
- **A picture could park the whole run.** An image's texture was built through the synchronous MetalKit loader, which decodes on a dispatch worker and waits on its own semaphore; with every worker already blocked, as a busy test run manages, the main thread waited forever. Textures are now decoded on the calling thread and their mip chains blitted on a command buffer. The pixels are unchanged.
- **A translucent PNG composites at its own alpha.** ImageIO decodes a PNG with alpha straight, and the image pipeline blends premultiplied, so a translucent pixel of a loaded PNG drew too bright. The texture is now premultiplied on upload, as an image painted in memory already was.
- The Accumulation and HDR pages described a sum on a `noClear` canvas plus a tone map and left out the divide by the number of passes; both now describe the running mean and point at `Accumulator` and `Filter.develop`.
- The Compute reference said a kernel binds its own buffers at indices 0…9 while the entry points reached two of one type; the `buffers:` form now matches the claim.
- A raymarched field under an orthographic camera drew a soft halo at its silhouette and lost gaps narrower than the halo; the silhouette anti-aliasing now sizes its pixel cone for an orthographic projection.

## [0.1.0] - 2026-09-02

The first tagged release. Ollin grew in one repository from May 2026 to this tag, and that history is not itemized here. This entry says what the release contains, area by area, with a link to the reference for each. The [README](README.md#whats-in-it) carries the fuller catalog, and the [Guide](Guide/README.md) teaches it in order. Read this entry as a table of contents rather than a list of changes.

### The framework

- **Drawing.** A p5-style API over a Metal core: `setup()` and `draw()`, and bare calls like `drawCircle` and `background`. `draw()` runs at the display's refresh rate from the first line, so motion is the default. Some thirty analytic shapes, curved paths, concave and holed fills, variable-width strokes, marks that follow the hand, shape booleans and offsets, gradients, blend modes, clipping, accumulation, and retained batches. Every frame composites in linear light with HDR tone mapping and analytic anti-aliasing. [Drawing](Docs/Drawing/Drawing.md).
- **Text and color.** Bitmap, outline, and single-line plotter fonts through one `drawText`, in any script, in columns, justified, along a path, or as vector shapes. OKLab mixing, spectral paint mixing, palettes and colormaps, color vision simulation, and wide-gamut and HDR output. [Text](Docs/Drawing/Text.md#textmode), [Color](Docs/Drawing/Color.md).
- **Shapes that merge.** SDF combinators in 2D and in raymarched 3D: smooth union, subtraction, morphing, domain mirror, tile, and radial repeat, and a clay-like `sculpt { }` block. [Combinators](Docs/Drawing/Combinators.md).
- **Generative technique.** Sixty-six classic techniques as first-class helpers, from Poisson-disk scatter and L-systems to Wave Function Collapse, strange attractors, marching cubes, paper marbling, and terrain erosion. [Generators](Docs/Generators/README.md).
- **Layers, effects, and shaders.** Off-screen layers with fifty-plus GPU filters, two-layer combines, feedback, simulation fields, and a compose DSL. Measured distance fields, light with shadows in a flat sketch, the frequency domain, and summed-area averages. Your own `shade(uv, info)` fragment function, inline or in a hot-reloading `.metal` file, with errors reported at your own line numbers. Chainable `Visual`s when you would rather skip the Metal. [Effects](Docs/Drawing/Effects.md), [Shaders](Docs/Shaders/Shaders.md).
- **Motion and parameters.** Frame-rate-independent easing and springs, keyframe timelines, seeded variations, and record and replay. `@Param` properties become typed inspector controls, persist across reloads, and can follow a curve or a formula. [Sketch](Docs/Core/Sketch.md), [Automation](Docs/Core/Automation.md), [Variations](Docs/Core/Variations.md).
- **GPU compute and simulation.** Compute kernels with a million particles a frame, and a neighbor-search primitive under artificial life and SPH fluids. Ping-pong texture simulations, steering crowds at GPU scale, populations that evolve, and chaotic systems. [Compute](Docs/Shaders/Compute.md), [Simulation](Docs/Simulation/README.md).
- **Physics.** A stepped `World` with Verlet particles and springs, Box2D bodies and joints in 2D, and Jolt-backed 3D bodies, joints, characters, vehicles, ragdolls, cloth, ropes, and water. [Physics](Docs/Simulation/Physics.md), [Physics in 3D](Docs/Simulation/Physics3D.md).
- **3D, opt-in.** Cameras and imported scenes (OBJ, glTF, USD), instanced meshes and GPU-culled worlds, grass and an ocean, physically based materials with the full map set, glass with dispersion, area lights, image-based lighting and a procedural sky. Shadows, ray-traced reflections, caustics, global illumination, atmosphere, temporal anti-aliasing, motion blur, and lens flare. A 2D sketch never pays for any of it. [3D](Docs/3D/README.md).
- **The world as input.** Nineteen on-device Vision trackers over the camera or any video, depth from a video model, screen and window capture, and video playback. CSV, JSON, and SVG import, live and pushed data feeds, game controllers, and an iPhone over USB as a LiDAR, motion, body, face, and hand sensor. [Vision](Docs/Vision/Vision.md), [Data](Docs/Helpers/Data.md), [The phone](Docs/3D/Phone.md).
- **Sound.** FFT analysis with beat detection, listening for words and named sounds, and a synthesizer the sketch plays. Voice presets, physical models, sampled instruments, wavetables, a patchable graph, effects chains, a place in the 3D scene, and algorithmic composition, all carried into an exported video. [Audio](Docs/Helpers/Audio.md), [Synthesis](Docs/Helpers/Synthesis.md).
- **Integration.** MIDI, OSC, a network tempo session, serial, Bluetooth Low Energy, DMX and LED mapping, and show lasers. Syphon out and in, a virtual camera, haptics, a remote surface for a phone, and a room several machines join to draw one piece on one clock. [Integration](Docs/Integration/README.md).
- **Output.** Headless stills and deterministic sequences, MP4 and GIF with slow motion, SVG and PDF with hatched fills, G-code, and print separations with press proofing. STL, OBJ, and 3MF for printing, USDZ and spatial video, a path-traced export, live recording with sound, and an accessibility layer for color vision and motion. [Export](Docs/Output/Export.md).
- **Running in the system.** A finished piece as a signed Mac app, a screen saver, the desktop wallpaper, a menu-bar strip, or an installation that stays up for a week. [A sketch as an app](Docs/Output/App.md), [Installation](Docs/Output/Installation.md).

### The tools

- **The `ollin` command.** One loose `.swift` file is a whole sketch, run from any directory. `ollin new` writes a starter, `ollin install` puts the command on PATH, and `ollin check` compiles a shader on this machine's GPU. `ollin docs` and `ollin examples` read the reference and the examples in the terminal. [Single-file sketches](Docs/Tools/SingleFile.md), [The reference offline](Docs/Tools/Reference.md).
- **OllinLive.** Save the file and the running window hot-swaps the sketch, with the clock carried across. `@Param` properties appear as typed inspector controls, a timeline records their automation, and Command-drag moves, resizes, or turns a shape by editing the source. `⌘]` and `⌘[` put it in front of or behind its neighbor. [The parameter timeline](Docs/Tools/Timeline.md), [Dragging a shape](Docs/Tools/DragToEdit.md).
- **OllinLiveCoding.** The performance host: the sketch fills the window, the code is drawn over it as translucent text, and Command-Return recompiles the buffer mid-motion. [Live coding](Docs/Tools/LiveCoding.md).
- **The project generator.** `ollin new` and `ollin generate` write a ready-to-run project from ten templates or from any example. They also bring a GLSL fragment shader or a glTF or USD scene over as source, and scaffold an extension library other sketches import. [Project generator](Docs/Tools/ProjectGenerator.md).
- **The examples.** 494 example sketches in their own package, browsable in one gallery window, including twelve recreations after eight artists. [Examples](Examples/README.md).

### The documentation

- The reference under [Docs/](Docs/README.md), about two hundred pages, with a short concept page for each idea the reference assumes.
- The [Guide](Guide/README.md), thirty-two chapters and four appendices: a practical introduction to creative coding taught through Ollin.
- For contributors, [CAPABILITIES.md](CAPABILITIES.md) inventories every capability's invariants, [ARCHITECTURE.md](ARCHITECTURE.md) explains the internals, and [ATTRIBUTION.md](ATTRIBUTION.md) credits the influences and the techniques.

### Requirements

- macOS 26 or later, a Metal-capable GPU, and a Swift 6 toolchain. Apple platforms only, by design: iOS and visionOS are future targets, and Linux, Windows, and the web are out of scope.

### Versioning from here

- Tags begin at 0.1.0. A breaking change or a new feature bumps the minor, a fix bumps the patch, and each release names its breaking renames in this file. Deprecation shims and a settled surface arrive at 1.0. Until then, pin `.upToNextMinor(from: "0.1.0")`.

[Unreleased]: https://github.com/eaviles/Ollin/compare/0.18.0...HEAD
[0.18.0]: https://github.com/eaviles/Ollin/compare/0.17.0...0.18.0
[0.17.0]: https://github.com/eaviles/Ollin/compare/0.16.0...0.17.0
[0.16.0]: https://github.com/eaviles/Ollin/compare/0.15.0...0.16.0
[0.15.0]: https://github.com/eaviles/Ollin/compare/0.14.0...0.15.0
[0.14.0]: https://github.com/eaviles/Ollin/compare/0.13.0...0.14.0
[0.13.0]: https://github.com/eaviles/Ollin/compare/0.12.0...0.13.0
[0.12.0]: https://github.com/eaviles/Ollin/compare/0.11.0...0.12.0
[0.11.0]: https://github.com/eaviles/Ollin/compare/0.10.0...0.11.0
[0.10.0]: https://github.com/eaviles/Ollin/compare/0.9.0...0.10.0
[0.9.0]: https://github.com/eaviles/Ollin/compare/0.8.0...0.9.0
[0.8.0]: https://github.com/eaviles/Ollin/compare/0.7.0...0.8.0
[0.7.0]: https://github.com/eaviles/Ollin/compare/0.6.0...0.7.0
[0.6.0]: https://github.com/eaviles/Ollin/compare/0.5.0...0.6.0
[0.5.0]: https://github.com/eaviles/Ollin/compare/0.4.0...0.5.0
[0.4.0]: https://github.com/eaviles/Ollin/compare/0.3.0...0.4.0
[0.3.0]: https://github.com/eaviles/Ollin/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/eaviles/Ollin/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/eaviles/Ollin/releases/tag/0.1.0
