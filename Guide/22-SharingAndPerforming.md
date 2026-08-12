#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 22</sup>

---

# 22. Sharing and performing

<img src="Images/22-SharingAndPerforming/Finale.jpg" alt="A bold posterized field of nested contour bands, electric blue and green at the edges through lilac and olive to a small lime core, like a printed topographic map of a wave" width="560">

Twenty-one chapters of pieces have lived on your screen. This last chapter is about everywhere else they can go: out as files (a poster, a video, a GIF, a plotter drawing), out as live feeds (into a VJ rig, into a video call), out as light on a real rig, and out on a stage, where writing the code is the performance. The piece above is the final state of a live-coded set you'll build in five evaluations, and every road out of the framework starts from the same place, the sketch you already have.

## Leaving as files

<img src="Images/22-SharingAndPerforming/ExportMap.jpg" alt="A diagram with a box labeled your sketch in the middle, arrows fanning left to five file outputs (still, sequence, video, GIF, SVG) and right to three live feeds (the window, Syphon, virtual camera)" width="680">

Every file export runs the sketch *headlessly*. No window opens, `setup()` runs, the clock advances to the frame you asked for, `draw()` runs, and the result is written. Because the offline clock is a fixed timestep, an export is deterministic: the same sketch, seed, and frame make the same file every time, however long the render takes. Sources follow the same clock, so a video decodes by frame position and an `AudioPlayer` feeds its analyzer the matching slice of its file each frame, which means even an audio-reactive piece exports with its beats in the same places. The flags live on any example's executable, and a loose sketch file gets the identical surface through the live host:

```sh
swift run OllinLive MySketches/Finale.swift --export poster.png --frame 200
swift run --package-path Examples Example-Motion-Breathing --export-sequence /tmp/out --seconds 5 --fps 60
```

`--export` writes one frame as a PNG, and `--export-sequence` writes every frame, lossless, ready for `ffmpeg` or an edit timeline. Exports default to the best render quality (`.detail`), since a file has no frame rate to protect, and `--render-quality` dials that down when you want a fast draft.

### Rendering from code

Those flags are a command-line wrapper around one function, and the function is available to you directly:

```swift
if let frame = OllinApp.image(of: MySketch(), frame: 200) {
    // a CGImage, rendered with no window anywhere in sight
}
```

`OllinApp.image(of:frame:)` builds the sketch, runs `setup()`, advances the clock to the frame you asked for, renders, and hands back a `CGImage`. (`OllinApp.export` is that call plus a PNG writer, which is all `--export` is.)

This matters the moment you want to render *many* things, or render on your own terms. A contact sheet of twenty seeds, thumbnails for a catalog, a batch job over a folder of inputs, a test that checks a render hasn't changed: all of them are a loop around this one call, and none of them need a window, a display, or a person watching.

<img src="Images/22-SharingAndPerforming/HeadlessCapture.jpg" alt="Four dark square tiles in a row, each showing the same cluster of green-to-orange circles in a different arrangement, labeled frame 0, frame 30, frame 60, and frame 90, above the caption OllinApp.image(of: Pulse(), frame:), four renders, no window" width="680">

That figure is the call demonstrating itself. It's one sketch whose `draw()` renders a *different* sketch four times at four frames and lays out the results, and because a fresh instance is built per capture, each render starts cleanly from `setup()`.

It's also how this guide is made. Every image you've seen in it is a committed sketch under `Guide/Figures/`, rendered by a small tool that walks the folder and calls `OllinApp.image(of:frame:)` on each one. That's the reason nothing here can quietly rot: a listing that stops compiling fails the render, and a figure that stops matching its prose is a file someone can open and run.

## Motion: video and GIF

For a file you can post, skip the stitching and encode directly:

```sh
swift run OllinLive MySketches/Finale.swift --export-video finale.mp4 --seconds 12
swift run OllinLive MySketches/Finale.swift --export-gif finale.gif --seconds 4 --gif-width 540
```

Reach for video first, because it's almost always the right choice. The default `h264` plays everywhere, `--codec hevc` is better quality per byte when the file needs to be smaller, and the two ProRes profiles are for edit timelines rather than for sharing. `--bitrate` (in Mbit/s) is the file-size dial, and a 1080-square piece looks clean around 10 to 15 in `h264`. The GIF is for the short loop. It's palette-limited and heavy per second, so keep it a few seconds, downscale with `--gif-width`, and know that a piece where *every* pixel changes every frame (a drifting full-canvas field) defeats GIF compression entirely and balloons the file. Chapter 3's perfectly looping phase tricks are exactly what a GIF wants.

## Vector: the plotter path

Chapter 13 promised that shapes held as geometry could leave as geometry, and `--export-svg` is that promise kept:

```sh
swift run OllinLive MySketches/Plot.swift --export-svg plot.svg
swift run OllinLive MySketches/Plot.swift --export-svg plot.svg --hatch
```

The exporter records each draw call at its own level, before any pixels exist: circles become `<circle>`, polylines `<polyline>`, shapes and outline text `<path>` with their fill rules, transforms and opacity intact. The file opens in a browser, Inkscape, or Illustrator, and feeds a pen plotter's tooling directly. Since a pen has no fill, `--hatch` turns solid fills into parallel line work spaced by tone (add `--cross-hatch`, or set `--hatch-spacing` and `--hatch-angle`), while stroke fonts and stroked geometry pass through as the single lines they already are. Images are the one thing that can't come along, because a vector file has no place for them.

The same recording writes as a **PDF** with `--export-pdf plot.pdf`, and that is the path to paper. One canvas pixel maps to one PDF point, so the paper presets on `CanvasSize` come out true to size. Declare `override var canvasSize: CanvasSize { .a4 }` (or `.usLetter`, `.a5`, with `.landscape` to turn the sheet) and the exported page *is* that sheet, vector-sharp at any printer's resolution. If the raster export should be print-grade too, `.a4.dpi(300)` renders the pixels at 300 dots per inch while the PDF page stays exactly A4. Everything the SVG carries, the PDF carries the same way, hatching included.

## Printing one ink at a time

Some presses can't print a full-color image at all. A risograph or a screen-printing rig lays down one ink per pass, and it needs you to hand it a separate grayscale plate for each one. If you have never prepared work for that kind of press, the mental model is the useful part.

<img src="Images/22-SharingAndPerforming/Separations.jpg" alt="Four panels: three grayscale masters labelled fluorescent pink, blue, and yellow, each carrying a different part of the same image, followed by the color preview of the three overprinted" width="680">

Each ink gets a **master**, a grayscale image where black means "lay down full ink here" and white means "leave the paper bare". The press runs the paper through once per master, and the inks stack up. Because printing inks are translucent rather than opaque, overlapping them mixes: pink over blue makes a purple neither drum could print alone. That's why the three plain-looking plates above produce a picture with more colors in it than three.

```swift
override var printInks: [Ink]? { [.fluorescentPink, .blue, .yellow] }
```

Declare that on your sketch, export with `--export-separations`, and you get one master per ink plus a preview with registration marks on it, which is the sheet you check before committing to paper. Working the other way round, `artwork.separated(into:)` does the same job to any `Image` in code, so you can look at the plates while you compose.

The interesting part is what happens for a color no single ink can make. Ollin searches for the combination of ink coverages whose overprint comes closest, judged the way your eye judges rather than by raw numbers, using the same perceptual space Chapter 2's color mixing uses. Draw in an ink's own color and it separates exactly. Draw anything else, including gradients and photographs, and it lands on the nearest mix those drums can actually reach.

One practical note carries over from Chapter 7's halftone. A press cannot hold a dot smaller than about two percent coverage, so anything fainter drops to bare paper rather than becoming invisible speckle, and `separation.halftoned(pitch:)` rotates each ink's dot grid to its own angle so the drums overprint into a rosette instead of a moire. `separation.dithered()` is the grainier alternative. [Print separations](../Docs/Output/PrintSeparations.md) has the full ink catalog, which carries the community-measured colors of the standard risograph line, plus the screening details.

## Something you can hold

A plotter turns a `Contour` into ink on paper. A 3D printer does the same job for a `Mesh`, and the call is just as short:

```swift
sculpture.normalized(scale: 60).write(to: "sculpture.3mf")
```

`normalized(scale: 60)` is doing the work that matters. A mesh carries bare numbers, and a printer needs millimeters, so this centers the shape on the origin, where a build platform wants it, and fits its longest side to 60 mm. The extension picks the format, and the file records that size.

Then there is the thing nobody warns you about, which is that a shape can look completely finished and still be unbuildable. A printer has to decide, for every point in space, whether it is inside the object or outside it, and it can only answer that if the surface actually closes. Here are two copies of the same knot, one swept closed and one left open at its ends:

<img src="Images/22-SharingAndPerforming/Fabrication.jpg" alt="Two identical-looking gold torus knots side by side; the left is labelled closed and ready to print, the right open at the ends with 36 edges bordering a hole" width="680">

On screen an open surface is exactly as convincing as a closed one. A printer is the first thing that ever disagrees.

So ask before you commit to plastic:

```swift
let check = sculpture.printCheck()
print(check.summary)        // "9360 triangles, 60.00 x 52.50 x 26.02 units: ready to print"
```

`printCheck()` reports whether the surface closes, whether neighbouring triangles agree on which side is out, whether the whole thing is inside out, and how big the file says it is. When something is wrong, `problems` says so in words rather than numbers. A mesh that fails is still written, with a note, because an open surface is a perfectly good thing to draw and only fabrication needs it sealed.

Starting from a shape that closes by construction saves the repair work entirely: Chapter 17's metaballs and isosurfaces close by definition, since a field has an inside, and so do the solid primitives and a tube swept with `closed: true`. A plane, or a lathe without caps, does not.

One last thing happens quietly on the way out. Ollin's meshes are flat-shaded, which means every triangle carries its own three corners so each face can hold its own normal, and neighbouring triangles share no vertex at all. Read as a solid, that is not a surface with a few holes in it, it is nothing but holes. The writers merge those duplicate corners first, settle the winding against the mesh's own normals, and stand the model up on z, because Ollin's world is y-up and a build platform is not. You get a solid without having to know any of that, which is the point. [Fabrication](../Docs/Output/Fabrication.md) has the details, and `Examples/3D/Geometry/Fabrication` is the knot above, with knobs.

## Something you can walk around

A printer takes one mesh. A whole 3D scene has somewhere else to go:

```sh
swift run Example-3D-Geometry-Solids --export-usdz piece.usdz
```

USDZ is the format Apple's platforms read without being asked. Double-click the file and Quick Look opens it. Send it in a message and it opens there too. Tap the AR button and the piece stands on the floor in front of you at whatever size the file says it is. Drop it into a visionOS app and it is already a model.

The thing to notice is what changed about the artifact. Every export so far in this chapter has been a *picture of* the sketch, taken from where the camera happened to be. This one is the scene itself. Whoever opens it picks their own angle.

Any `Scene` writes the same way, including one you loaded or built by hand:

```swift
scene.write(to: "piece.usdz")
```

And a frame becomes a scene when you ask for it:

```swift
let scene = OllinApp.spatialScene(of: sketch, frame: 120)
```

That hands back an ordinary `Scene`, the same kind [Chapter 17](17-3DGently.md) loaded from a file, so you can look at what your own frame is made of, move a node, and write it out. One writer serves both paths, which is why the file and the frame cannot disagree.

Here is a frame drawn the ordinary way, beside the same frame written to a `.usdz` and opened again:

<img src="Images/22-SharingAndPerforming/SpatialExport.jpg" alt="Two identical arrangements of a yellow sphere, blue rounded box and green torus; the left is surrounded by scattered grey dust motes, the right has none" width="680">

The surfaces come back exactly. The dust does not, and that is the rule worth carrying: **a model file holds surfaces**. Meshes travel, with their transforms, their colors, their textures, and as much of their finish as the format has a slot for, along with the camera and the lights. A point cloud, a GPU particle system, and a raymarched field are not surfaces, so they stay behind. So does 2D drawing, which is why a labelled diagram arrives without its labels. Ollin prints one note for each thing it left, rather than letting you find out later.

If you want a field or a cloud to travel, give it a surface first: `isosurface(at:in:_:)` and `particleSurface(of:)` from Chapter 17 turn one into a mesh, and a mesh always goes.

One number decides whether the model is furniture or a paperweight:

```swift
scene.write(to: "piece.usdz", metersPerUnit: 0.05)
```

A model file records how big one scene unit is, and nothing is scaled on the way out. At the default of 1 a sphere of radius 1 arrives two meters across. Most 3D sketches work at unit scale, so something between `0.01` and `0.1` is usually what you want for a piece someone will set on a table.

Lighting is the one place a spatial export deliberately gives something up. The lights travel, but an [environment](../Docs/3D/3D.md#environment-lighting) does not, because a viewer supplies its own, and in AR that viewer is a camera looking at your actual room. A metal surface exported this way reflects wherever it ends up, which is a better answer than the studio it was made in. [Spatial](../Docs/Output/Spatial.md) has the full list of what carries, and `Examples/3D/Geometry/SpatialExport` is a ring of solids with a save key.

## Something you can look into

A model hands over a scene and lets someone choose an angle. That works because the scene is still. Motion cannot be handed over that way, so it gets handed over differently: recorded from two eyes at once, the way you already see the room you are sitting in.

```sh
swift run Example-3D-Geometry-SpatialVideo --export-spatial piece.mov --seconds 8
```

That writes **spatial video**, which is the format Apple's platforms record and play with real depth. Everything about the drive is the export you already know, the same fixed clock and the same determinism, except each frame is rendered twice, from two cameras a little way apart, and the two views travel together in one file.

Two numbers decide what that looks like, and neither is a setting you get right or wrong. They are composition.

<img src="Images/22-SharingAndPerforming/StereoPair.jpg" alt="A plan-view diagram: two eyes at the bottom looking parallel, a horizontal line labeled the screen, and three objects whose sight lines land on the screen as paired marks, crossed for the near object, coincident at the screen, spread apart for the far one" width="680">

**Convergence** is the distance at which the two eyes agree, and the diagram is what that means. Follow a line from each eye through an object to the screen: those two landing places are where each eye sees it. For something sitting at the convergence distance they land together, so it appears *on* the screen. For something nearer, the lines have already crossed by the time they get there, and the marks come out the wrong way round: your eyes read that as an object in front of the screen, poking out. Farther away, the marks spread apart the ordinary way and the object sits behind. So choosing the convergence distance is choosing what the viewer is looking *into* rather than *out at*.

**Interocular** is how far apart the eyes stand, in world units, and it is the depth dial. Half reads flatter. Twice reads deeper, then starts to hurt. Left alone, Ollin puts the eyes 1% of the frame width apart, which is a rule with a reason: it works out to the far background separating by 1% of the frame too, less than a viewer's own eyes span, so nothing ever asks them to point outward, which is the one thing stereo must never do.

A sketch declares both the way it declares a loop:

```swift
override var stereoGeometry: StereoGeometry {
    StereoGeometry(interocular: 0.1, convergence: 6)
}
```

Leave either one out and it is worked out from the camera: the convergence distance defaults to whatever the camera is already pointing at, on the reasoning that you are looking at the thing the piece is about. Either can also be overridden for one export with `--interocular` and `--convergence`, which is the fastest way to find out what they do. Push the near pillar of that example until it stops being pleasant, and you will have learned more than this section can tell you.

One detail is worth knowing because it explains something that could otherwise look like a bug. The frame is **drawn once and rendered twice**. Not drawn twice: drawing again would roll the sketch's randomness a second time and step every simulation a second time, and some of them are honest about not repeating exactly, so the two eyes would end up looking at different worlds. One draw, two cameras, and both eyes see the same instant.

The consequences of that are worth reading as rules. Anything the sketch already flattened while drawing, a `project()`, a `depth(at:)` placement, a billboard, keeps its one answer and therefore lands flat on the screen plane in both eyes, which for captions and overlays is usually what you want. A 2D sketch has nothing to disagree about and comes out flat, and says so. So does an accumulating sketch, because its pile lives in one surface and there is only one of it.

Finally, the file records how far apart the eyes that shot it really were, so a player can scale the depth it shows. `--meters-per-unit` is how you say what a world unit is, exactly as for a model. [Spatial](../Docs/Output/Spatial.md#spatial-video) has the rest, and `Examples/3D/Geometry/SpatialVideo` is a colonnade built to have depth worth recording, with both numbers on knobs.

## Reproducibility is part of the piece

A shared render is better when it can be *re-made*. Three habits from earlier chapters do the work here. Seed the randomness (`seed(…)` in `setup()`, Chapter 4), so the export and the re-export are the same artwork, not siblings. Copy tuned `@Param` values back into their declarations once they feel right, because a headless export reads the defaults written in code, not the inspector. And share the `.swift` file alongside the render when you can, because in Ollin the sketch is the artifact, and a reader holding the source holds the whole piece, seeds, knobs, and all.

The exports meet you halfway. Every PNG, SVG, PDF, and video Ollin writes carries a small **recipe** in its metadata: the seeds the run used, the value of every `@Param`, the git commit the code was at (marked dirty if you had uncommitted edits), and which frame at which rate produced it.

Image metadata has existed for decades, in the same place a camera writes its shutter speed and lens. Ollin puts something more useful there. Read it back with any metadata tool:

```sh
exiftool -Description poster.png
```

This matters when you need to recover a past render. You find an image from four months ago that you like, you have no memory of which of eleven variations produced it, and the sketch has changed since. The file tells you: seed 48213, these knob values, that commit. Check out the commit, pass the seed, and you have it back.

Two limits. GIF has no metadata slot in its format, so a GIF export carries nothing. And a recipe only takes you back to the code if the code still exists, which is another argument for committing your sketches. [The details](../Docs/Output/Export.md#reproducibility-metadata) list every field.

## Live feeds: into other apps

Some pieces shouldn't become files at all. They should stay alive and go *into* something. **Syphon** is the macOS standard for handing GPU frames between running apps, and one line makes a sketch a source every VJ tool can see:

```swift
import OllinSyphon

override func setup() {
    publishSyphon(name: "Ollin")     // every frame is now a Syphon source
}
```

Resolume, MadMapper, VDMX, and other creative-coding frameworks all read it live, pixel-identical to your window, with nothing touching disk. It works the other way too: `SyphonClient` subscribes to another app's feed and hands you each frame as an `Image` to draw, warp, or feed to Chapter 21's trackers. Pair it with Chapter 20 and the rig conversation goes both directions at once: visuals over Syphon, control over OSC or MIDI. The `Integration/SyphonLoopback` example runs both ends in one sketch (a video-feedback tunnel, since it watches itself), so you can see the plumbing with no second app installed.

### The sketch as a webcam

Syphon is app-to-app, which means both ends have to have agreed to speak it. That covers the VJ world and misses everything else, including the one destination people ask about most: the browser. A web page asks the operating system for a *camera*, and no amount of Syphon will make it see one.

So the other publishing route makes the sketch an actual camera:

```swift
import Ollin
import OllinCamera

override func setup() {
    publishVirtualCamera()      // every frame now feeds a system-wide camera
}
```

After that, "Ollin Camera" is in the camera menu of every app on the machine. Zoom, Meet, QuickTime, OBS, Photo Booth, and any web page that asks for a camera can all take a sketch as their input. Your next video call can open on a reaction-diffusion field.

There's a one-time setup, and it's worth knowing why. A camera device is a piece of the operating system, not something a sketch can conjure, so the device itself is a macOS **system extension** installed by the Ollin Camera app in this repository: launch it from `/Applications` and approve the extension in *System Settings ▸ General ▸ Login Items & Extensions ▸ Camera Extensions*. From then on the device exists whether or not any sketch is running, and when nothing is publishing it shows a "no signal" test card, which is a friendlier thing for a video call to find than a black rectangle. If you publish without having installed it, nothing breaks: the sketch keeps drawing, and `isAvailable` and `unavailableReason` tell you what's missing.

Two facts about the frame will save you a confused minute:

- **The camera frame is a fixed 1280×720.** Your canvas is scaled to fit and centered, so a square canvas arrives with black bars down both sides. If a piece is destined for a call, `canvasSize = .size(1280, 720)` fills the frame exactly.
- **The camera runs at 30 fps.** A sketch running faster publishes every other frame, and a slower one simply updates the camera at its own pace.

And when the picture looks wrong, suspect the *viewer* first. Photo Booth mirrors every camera preview like a selfie mirror, so text in your sketch reads backwards there exactly as it would on the built-in camera, and it crops, because its preview pane isn't 16:9. Conferencing apps usually mirror your self-view while sending the unmirrored picture to everyone else. QuickTime's File ▸ New Movie Recording shows the frame as published, uncropped and unmirrored, so it's the fastest way to see what other apps are really receiving.

## Light instead of pixels

A lighting rig is a display with very few, very bright pixels, and a sketch can render for it too. Stage lighting speaks **DMX**, the protocol that has told dimmers, LED pars, and moving heads what to do since 1986, and it travels over ordinary Ethernet in two dialects, **Art-Net** and **sACN**. The model is small enough to hold in one sentence: a *universe* is 512 channels of one byte each, a *fixture* listens at an address and reads a few consecutive channels, and what each channel means (red, green, blue, a dimmer, a pan motor) is printed in the fixture's manual. You fill 512 bytes, you send them, the room changes.

```swift
import OllinDMX

let dmx = DMXSender()                           // sACN multicast: zero config
let par = DMXFixture.rgb(at: 1)                 // an RGB par on channels 1-3

override func draw() {
    var rig = DMXUniverse()
    rig.set(par, color: Color(hue: fract(time * 0.1), saturation: 1, brightness: 1))
    dmx.send(rig)                               // universe 1, every frame
}
```

`DMXSender()` with no address multicasts sACN, which any listening node on the network picks up with no addressing at all; `DMXSender(artNet: "192.168.1.60")` unicasts Art-Net to a node that wants it. Either way you send every frame, like a second `draw()` aimed at the room, and the sender handles the wire's own etiquette (changed data only, capped near DMX's own refresh rate, keep-alives while nothing moves), so a 60 fps sketch makes a perfectly polite lighting console. The fixture sugar keeps the addressing in one place: patch a `DMXFixture` per lamp with the roles its manual lists, chain them with `nextAddress`, and `rig.set(par, color:)` lands on whatever channels the layout names.

<img src="Images/22-SharingAndPerforming/LampsAndBytes.jpg" alt="A diagram in two rows: six colored pars hanging over a dark stage throwing red through violet light, and below them the same universe's first eighteen channels as meter bars bracketed into fixtures, with the fourth par dim in both views" width="680">

It works the other way around too. A `DMXReceiver` turns the sketch into a fixture: a real console fades channel 1 and `draw()` reads it as `dmx.level(1)`, or `dmx.bind(channel: 1, to: $radius)` puts the fader on the same knob the inspector slider moves, exactly like Chapter 20's MIDI and OSC bindings. The `Integration/DMXLoopback` example runs both ends on `127.0.0.1`, a sender chasing colors across a drawn rig that is lit from what the receiver reads back, so the whole path runs with no console and no hardware. When you do reach for real lights, two practical notes: macOS asks once for Local Network permission, attributed to the terminal you launched from, and a free sACN monitor app will show you every universe on the wire while you find your fixture's address.

The rig's big sibling is the LED wall, and for that you stop filling channels by hand. An `LEDMap` lays the fixtures over the canvas itself: a strip is a run of sample points along a line or a curve, a matrix is a grid of them, and every frame the map reads the rendered pixels under each LED (on the GPU, a few hundred points, never a whole-frame readback) and ships them through a `DMXSender`. The wall is just the canvas, somewhere else.

```swift
let dmx = DMXSender()                     // or unicast to your pixel controller
let leds = LEDMap(sender: dmx)

override func setup() {
    leds.addStrip(from: Vector2(100, 540), to: Vector2(980, 540), leds: 144)
    leds.addMatrix(in: Rectangle(x: 390, y: 150, width: 300, height: 300),
                   columns: 16, rows: 16, universe: 2)
    extend(leds)                          // from here on it feeds itself
}
```

After `extend(leds)` you draw as if the wall didn't exist; whatever lands under the mapped points is what the wall shows. Each LED averages the little patch of canvas it stands for, so a strip over fine detail glows steadily instead of flickering, and on the wire the map packs whole LEDs into universes (170 RGB pixels per universe, longer runs continuing on the next number up), which is exactly the layout pixel controllers expect: patch yours to the numbers `leds.universes` reports and you're done. The `Integration/LEDMapping` example runs it all on loopback, the drawn strip and panel lit from what a receiver reads back off the wire.

<img src="Images/22-SharingAndPerforming/LEDWall.jpg" alt="A diagram in two rows: a colorful gradient picture with a wavy strip of small rings and a bracketed grid of rings mapped over it, and below, the same LEDs lit for real: the strip laid out straight in wire order and the panel beside it, each labeled with the universe it occupies" width="680">

## Adding behavior without touching the sketch

One more piece is worth knowing about once you have several sketches, because it answers a question that comes up as soon as you want the same extra behavior in all of them: how do you add something to a sketch's life cycle without editing the sketch?

An **extension** is a small object that gets told when things happen. You register it once, and from then on it hears about setup, about each frame before and after the drawing, and, if it asks, about the finished rendered image.

```swift
extend(MyWatermark())
```

The reason this exists rather than you just adding lines to `draw()` is that some behavior isn't about the artwork. A frame recorder, an on-screen readout of the frame rate, a guide overlay you toggle while composing, a logger that notes which seed produced which render: none of those belong in the piece, and all of them want to apply to every piece. Ollin's own frame-rate statistics work exactly this way, as an extension registered by the host rather than anything in your sketch.

The one detail worth flagging is that hearing about the rendered image is opt-in, through a property the extension sets, because reading pixels back from the GPU costs real time. An extension that only watches timing pays nothing. The [extension seam](../Docs/Core/Sketch.md#extensions) has the hook list.

## Performing the code itself

The last output is a stage. `swift run OllinLiveCoding` opens the performance host, where the sketch fills the window and the code rides over it as translucent text, part of the show:

<img src="Images/22-SharingAndPerforming/StageDiagram.jpg" alt="An annotated diagram of the performance host: a dark window with a posterized visual filling the stage, code lines riding over it on translucent strips, an Evaluated toast, and callouts naming each part" width="680">

The loop is different from the live-reload host you've used since Chapter 1. There is no file watching and no separate editor, so you type in the window and press **⌘↩** to evaluate. The buffer compiles in the background while the running sketch keeps drawing, and on success the new sketch swaps in with the clock carried across, so a phase-driven motion never jumps mid-set. Tuned `@Param` knobs (including ones bound over MIDI or OSC) carry across too. A typo can't stop the show: the last good sketch keeps playing, the errors land in a strip along the bottom, and you fix and evaluate again. When the code should get out of the way, **⌃⇧H** hides it and the visuals keep the whole stage, and **⌃⌘F** is fullscreen for the projector. For a real set, `Scripts/OllinLiveCoding` builds the host in release mode so the framework renders at full speed.

Evaluation never writes your file (⌘S does), so you can riff as recklessly as the room deserves and keep only what worked.

## Putting it together: a set in five evaluations

What you'll build here is a short performed set. Open the host with a fresh buffer and build the chapter's finale the way an audience would watch it grow, one evaluation at a time, using Chapter 15's `Visual` chains (the natural material for this kind of set, since every step is one added line):

<img src="Images/22-SharingAndPerforming/SetSteps.jpg" alt="Five numbered thumbnails: vertical color bands, the bands folded into a five-pointed mandala, the fold melted by noise, the melt posterized into hard bands, and the whole thing color-shifted toward green" width="680">

1. Start with breath. Type `drawVisual(.oscillator(frequency: 11, speed: 0.6, colorShift: 0.5))`, press ⌘↩, and drifting bands fill the stage.
2. Fold space by adding `.kaleidoscope(5)`, which turns the bands into a five-pointed mandala, still breathing.
3. Melt the fold with `.displaced(by: .noise(scale: 3, speed: 0.25), amount: 0.09)`.
4. Make it a print with `.posterized(bins: 6, gamma: 0.75)`, and the melt hardens into contour bands like a screen print.
5. Set it flying with `.rotated(time * 0.03)` and `.colorCycled(time * 0.04)`, a slow spin through the whole color wheel.

The finished buffer is the whole piece, and it's small enough to retype from memory, which is rather the point ([`Finale.swift`](Figures/22-SharingAndPerforming/Finale.swift) is the committed figure):

```swift
import Ollin

final class Finale: Sketch {
    override func draw() {
        drawVisual(
            .oscillator(frequency: 11, speed: 0.6, colorShift: 0.5)
                .kaleidoscope(5)
                .displaced(by: .noise(scale: 3, speed: 0.25), amount: 0.09)
                .posterized(bins: 6, gamma: 0.75)
                .rotated(time * 0.03)
                .colorCycled(time * 0.04)
        )
    }
}
```

<img src="Images/22-SharingAndPerforming/Finale.jpg" alt="The finale at one moment: nested posterized contour bands from electric blue and green edges to a lime core, slowly rotating and cycling hue when live" width="560">

Then close the loop this chapter opened: save the buffer (⌘S), record the piece as a file to share (`swift run OllinLive MySketches/Finale.swift --export-video finale.mp4 --seconds 12`), and if a projector or a call is handy, `publishSyphon()` or `publishVirtualCamera()` while you perform. The same small sketch just walked out of every door this chapter opened.

Then make it yours:

- Play the set differently by reordering the moves, or swap step 2's fold for `.repeated(x: 3, y: 3)` and the mandala becomes wallpaper.
- Wire Chapter 20 in: `@Param` the oscillator frequency, bind it to a MIDI knob, and the set gets a second instrument.
- Feed it eyes: `.displaced(by: .layer(feed), amount: 0.1)` over a layer you draw the webcam into, and the audience melts the piece.
- Perform an old friend, since any finished piece from this guide runs in the host as-is. Try evaluating changes into Chapter 16's reaction-diffusion while it grows.

## Where this comes from

Live coding as a performance practice was organized by TOPLAP (founded 2004), whose manifesto demanded "show us your screens". The code-over-the-visuals layout of this host is that idea, and its most direct model is Olivia Jack's browser instrument Hydra, which made the pattern feel effortless. Alex McLean and the TidalCycles community built the musical wing of the same practice. Syphon is Tom Butterworth and Anton Marini's gift to the Mac's visual ecosystem, and the vendored framework carries their names. The pen-plotter revival that SVG export serves grew around the AxiDraw and the #plottertwitter community, heirs of the 1960s computer-art plotters this guide's recreations visit. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Export](../Docs/Output/Export.md): every flag, codec advice, GIF timing, SVG mapping, hatching.
- [Print separations](../Docs/Output/PrintSeparations.md): the spot-ink model, the ink catalog, screening angles, and the overprint preview.
- [Fabrication](../Docs/Output/Fabrication.md): writing a mesh as STL, OBJ, or 3MF, real-world sizing, and what makes a surface printable.
- [Syphon](../Docs/Integration/Syphon.md): publishing, receiving, discovery, and the loopback.
- [Virtual camera](../Docs/Integration/VirtualCamera.md): the one-time install, publishing, the test card.
- [DMX](../Docs/Integration/DMX.md): universes and fixtures, Art-Net and sACN, the send cadence, and the console-drives-the-sketch direction.
- [Live coding](../Docs/Tools/LiveCoding.md): the evaluate loop, errors, recovery, and the keyboard reference.
- Worked examples: [`Examples/Export/VectorExport`](../Examples/Export/VectorExport/Sketch.swift), [`Examples/Export/Hatching`](../Examples/Export/Hatching/Sketch.swift), [`Examples/Integration/SyphonLoopback`](../Examples/Integration/SyphonLoopback/Sketch.swift), [`Examples/Integration/SyphonViewer`](../Examples/Integration/SyphonViewer/Sketch.swift), [`Examples/Integration/DMXLoopback`](../Examples/Integration/DMXLoopback/Sketch.swift), and [`Examples/Integration/VirtualCamera`](../Examples/Integration/VirtualCamera/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 21, Seeing](21-Seeing.md) · Next: [Appendix A, Just enough Swift](A-JustEnoughSwift.md)
