# Ollin roadmap

Ollin is a creative-coding framework for Swift and Metal on Apple platforms. It aims for the ergonomics of p5.js on a core built to OPENRNDR's standard. This file is the running list of what is planned and what is being explored. If you want to help, it is a good place to start.

The guides in [`Docs/`](Docs/) explain how the framework works and the conventions behind it. For working code, browse [`Examples/`](Examples/).

## How to contribute

Here are a few things to know before you pick something up:

- Building and running needs macOS 26+ and a Metal-capable GPU. Nothing replaces the Swift toolchain and Metal, so changes are verified on a Mac.
- A new drawing feature is built on the typed core first (the `Drawer` and the value types). Then it gets the bare p5-style call as sugar. Anything the bare API can do, the core should also be able to do, with more control.
- A feature is not done until it has an example. Examples live in [`Examples/`](Examples/), one idea per sketch. CI compiles them, so they do not rot. Writing the example also checks the API, because an API that is awkward to write against probably needs work.
- The items under [Up next](#up-next) are the most self-contained, so they tend to make the best first contributions.
- Some sections carry a rough priority tag. The tag **Near-term** marks well-scoped items that make good next pickups. The tag **Later** marks bigger items that depend on earlier work. A section with no tag is substantial and wanted, but it is not the next thing to pick up. Speculative ideas live under [Further out / exploratory](#further-out--exploratory), and the platform-gated legs live under [On the horizon](#on-the-horizon).

If you come from p5.js or Processing, [the Guide's Appendix C](Guide/C-ComingFromP5.md) maps the API you already know onto Ollin. The page [`Docs/Swift.md`](Docs/Swift.md) covers just enough Swift to get productive.

## Toward 1.0

Ollin is pre-1.0, and the public API still changes freely. Semantic version tags and a changelog begin with `0.1.0`, so a SwiftPM project has a version to pin before the API settles. At major zero, a breaking change or a new feature bumps the minor, and a fix bumps the patch. A consumer pins `.upToNextMinor`, and each release names its breaking renames in its notes. Version 1.0.0 is the release where the API settles. From that point on, every public rename ships a deprecation shim, which is the migration discipline described in [`CLAUDE.md`](CLAUDE.md). `Scripts/api-diff.sh` turns strict at that tag, and a public spelling gone with no deprecated twin fails preflight from then on. This section names what that release waits on, and only that. Everything else on this page stays open for work at any time. The release does not wait on that work, and that work does not wait for the release.

- **Stabilization.** The release waits on three things here. The first is a last naming sweep over the public API before the tag, read from the listings under [`API/`](API/), because the shim discipline locks the names in at the release; `Scripts/check-api-names.sh` holds the settled spelling rules against those listings on every change, and `Scripts/check-api-pages.sh` holds every name in them to having a page, so that sweep is a reading for meaning (a `factor` that is not a multiplier, a verb that says less than the call does) rather than for spelling or for coverage. The second is a test suite that is reliable end to end, with no flaky or machine-bound failures. The third is working down the hand-verification backlog, which is the features that still wait on eyes, ears, or hardware.
- **The surface reader and the standard library's protocols.** `Scripts/api-diff.sh` already treats a member that moved onto one of Ollin's own protocols as moved rather than removed, by finding its line under that protocol in the same listing. A conformance to a standard-library protocol has no such line to find, so a type that gains `Collection` and drops its own `count` reads as a removal even though every call site still compiles. That is a warning before 1.0 and a failure after it, so the reader needs a small table of what the common standard-library protocols supply, checked only when the type gained that protocol in the same diff.

- **The release itself.** This is the release notes, the `1.0.0` tag, and a README presentation pass. The ecosystem legs that need a public repository (DocC, a Swift Package Index listing, the extension index) follow the release. They do not gate it.
- **What an open repository is expected to carry.** These are the surfaces a visitor sees beside the README. None of them can be set from a file. The first is the About description and topics. The second is a social-preview image; the card the website already serves, `Logo/ollin-social.png`, is the file to upload. The third is Discussions switched on, with a Show and tell category and a pinned welcome thread. The fourth is a logged-out check that the issues link and the install URL resolve. The domains are set here too. The canonical home the About field names is ollin.art, and ollin.run, ollin.live, and ollin.mov become permanent redirects to it. All of these are small, and they are cheaper to set before the first stranger arrives than after. See the [design notes](DESIGN-NOTES.md#opening-the-repository), which also cover what the README presentation pass has to decide.

## Up next

These are near-term, fairly self-contained pieces. Each one is small and well-scoped.

- **More SDF shapes, when a good fit appears.** A candidate is any canonical form parameterized by a size and a ratio or two. Such a shape drops into the instanced-SDF path as four small touch-points: a shape tag, a builder, a distance function, and a fragment case.
- **Rounded corners of different sizes.** A rectangle takes one radius per corner, for a tab, a speech bubble, or a card with one square edge. The instanced box has free parameter slots to carry the four radii.
- **Drawing part of an image.** `drawImage` takes a source rectangle inside the image. A sprite sheet, a tile set, or a film strip then draws one frame at a time, with no cropping first.
- **A gradient that sweeps around a point.** This is the conic gradient, used for color wheels, dials, and pie charts. The sketch chooses the center and the angle the sweep starts from.
- **Pitch bend bound to a parameter.** A parameter binds to a MIDI control change. The pitch wheel is the other continuous control on most keyboards, and it binds the same way.
- **Points inside a shape.** A sketch scatters random points evenly inside any `Shape`, holes included, or along its outline by length. The same helper offers a blue-noise scatter inside the shape.
- **One mesh from several.** Meshes placed by their transforms join into one mesh, with no boolean. The result is one draw call and one file for a printer.
- **Three more filters.** A channel mixer weighs each output channel from the input channels. Lens distortion bends a layer into a barrel or a pincushion. A corner pin lays a layer onto four points.
- **Small sketch conveniences.** `redraw()` draws one frame of a sketch that has stopped looping. A sketch can set the pointer's shape or hide it, and spherical coordinates sit beside `polar`. A file can be picked through the system's open panel, and the frame can be copied to the clipboard.

See the [design notes](DESIGN-NOTES.md#small-pieces).

## Generative geometry

This tier is a set of classic generative-art building blocks. Each one emits vector geometry (points, `Contour`s, `Shape`s) that feeds the existing draw, shape-boolean, hatching, and SVG paths, rather than the renderer. They follow the plotter-friendly, geometry-first pattern that the shape booleans set. All of them run off the existing seedable `random`/`noise`, so a run is reproducible. Each ships with an example. Several are the natural implementation behind a [recreation](DESIGN-NOTES.md#examples-folder) of a work by the artist who pioneered them. The conventions for adding one are in the [design notes](DESIGN-NOTES.md#generative-geometry). The broader algorithm catalog is the [technique and algorithm helpers](#technique-and-algorithm-helpers) tier.

- **An outline you can ask questions of.** `Contour` answers the tangent and normal at a fraction, the nearest point to a position, and the stretch between two fractions. It also finds where two outlines cross, simplifies a dense trace, reverses its direction, and rounds or cuts its corners. Line segments, arcs, and ellipses join `Circle` and `Rectangle` as values, each able to produce an outline and to report where it crosses another.
- **Bending outlines.** These edits warp a shape along a curve and pull an outline toward a point while its ends stay fixed. They also smooth an outline without losing its corners, and split it where it bends sharply. Fitting a few cubic curves through a dense trace belongs here too. All of it builds on the outline questions above.
- **The regions a drawing encloses.** Overlapping lines, circles, and outlines are split at every crossing, and each enclosed region comes back as its own `Shape`. Every region can then take its own fill, like a page in a coloring book.
- **A shape bent into a curved patch.** A shape maps into a four-sided region whose sides are curves, such as lettering on a waving banner. This is the curved counterpart of `Rectangle.point(u:v:)`.
- **Points in the order of a space-filling curve.** Points sort by their place along a Hilbert curve, so neighbors in the list sit near each other on the page. That gives one continuous line through a stipple, and it orders a large set with a single sort.
- **Packing rectangles.** Rectangles of given sizes pack into a bin, for a contact sheet of photos at their own proportions, a collage, or a texture atlas.
- **A turtle you drive from code.** A turtle moves forward, turns, lifts and lowers its pen, and returns to a saved position. Its path comes back as `Contour`s. The L-system turtle reads a string, and this one takes calls, for Logo-style drawing.

## Technique and algorithm helpers

**Near-term.** This is a standing catalog of classic creative-coding techniques and algorithms as first-class helpers. It keeps growing, as the SDF shapes, the effect `Filter`s, and the [generative-geometry](#generative-geometry) builders do. Each one lands wherever it fits the existing core. A geometry emitter goes beside the shape builders. An escape-time or field technique becomes a GPU `Generator` or shader. A simulation goes beside the compute and `SimField` paths. Each ships with an example, and each runs off the seedable `random`/`noise`, so a result reproduces. Each is implemented from the published technique, which is credited in the Techniques list of `ATTRIBUTION.md`. Many map onto the *Nature of Code* canon (vectors, forces, particles, autonomous agents, cellular automata, fractals, evolution). That makes the catalog a familiar entry point for a reader who comes from that book. The geometry-emitting recipes are flagged plotter-friendly for the pen-plotter path.

- **A soft body from any shape.** The 2D physics world turns a `Shape` into a ring of particles that keeps its area, bends, and collides outline against outline. The `Physics/Blobs` example builds its bodies by hand from springs, and this makes one body a single call.
- **Finding boxes and neighbors in 3D.** A bounds index answers which of many boxes contain a point, which overlap a rectangle, and which overlap each other. A 3D form of `SpatialIndex` answers its neighbor questions for point clouds and swarms in space.
- **Matching two sets at the least total cost.** This finds the pairing between two sets of points with the least total distance. Particles can then gather into the letters of a word along the shortest total path, and outlines can pair the same way.
- **Layer styles.** A layer gets a drop shadow, an inner or outer glow, a bevel, or an outline, each read from its alpha. They build on the distance field the effects already measure.
- **Measuring color.** Helpers measure the perceptual distance between two colors, find the palette entry nearest a color, and build a histogram of an image. Ramps can also drift in hue, cooler in the shadows and warmer in the light.
- **Slopes of a fitted field.** `RadialBasis` reports its gradient beside its value. Small numerical derivative helpers cover any function a sketch writes.

See the [design notes](DESIGN-NOTES.md#technique-and-algorithm-helpers).

## Expressive brushes and strokes

This is the hand-drawn, mark-making axis. It is built on the variable-width stroke renderer, which gives a width per vertex, shaped by a `strokeProfile`. It also builds on the recorded marks that drive that renderer from the hand, and on the brushes that stamp a shape along a path. What is ahead is Apple Pencil tilt and azimuth as further drivers. They need a Pencil and a tablet, so they sit under [new input sources](#new-input-sources). Painterly simulation (the generative-watercolor family) stays a [technique-catalog](#technique-and-algorithm-helpers) recipe rather than a brush-engine feature. See the [design notes](DESIGN-NOTES.md#expressive-brushes-and-strokes).

## iPhone as a sensor array

A Mac has no depth camera, no inertial sensors, and no spare Neural Engine for live perception. A tethered iPhone has all three. The idea is to let the phone act as a sensor and an on-device ML co-processor for a sketch that still renders on the Mac. The phone captures and perceives (LiDAR point clouds, face and body tracking, segmentation, device motion, and more). It streams typed results that the sketch reads in `draw()`. A recorded RGBD clip and a tethered phone's live USB RGBD stream already reconstruct on the Mac as point clouds (see [`Docs/3D/Record3D.md`](Docs/3D/Record3D.md)). That is the kind of world-facing depth feed an Intel RealSense once gave openFrameworks. A sweep of the phone's depth frames fuses by camera pose into one world cloud. That cloud stays registered, and it straightens itself when the phone comes back to a place it has already scanned. Alongside that world cloud, the phone reconstructs the room as a labeled surface (see [`Docs/3D/Phone.md`](Docs/3D/Phone.md)). The work ahead grows that stream into the rest of the phone's senses, over Ollin's own iPhone capture app. The wire protocol, the sensor catalog, and the build order are in the [design notes](DESIGN-NOTES.md#iphone-as-a-sensor-array).

## 3D mode

2D stays the default, and 3D keeps building out on top of the pieces that already exist. Those are the camera, depth buffer, transform stack, solid primitives, and textured meshes. Meshes loaded from file also belong there, with their materials, textures, and the full surface-map set. The pieces also include the directional/point/spot light and material model, curated lighting presets, and the stylized material library (iridescent, velvet, jade, toon, gooch, …). There is also the physically-based metallic-roughness material, and image-based lighting from bundled, downloaded, or loaded HDRI environments (with a skybox backdrop). The last pieces are matcap materials (view-normal sphere-texture shading) and directional, spot, and point cast shadows. The work ahead builds on all of that:

- **Soft bodies that meet themselves.** Cloth drapes, folds, and holds air. But a folded sheet passes through its own layers, and two sheets pass through each other. That happens because self-collision and cloth-against-cloth are gaps in the solver underneath, not in the API over it. Tearing is further out still. It needs a shared vertex split and a rebuilt constraint set in the middle of a simulation, which that solver cannot do at all. Both wait on the library growing them. When it does, they land as more capability on the shipped `SoftBody3D` surface. A filled jelly held by tetrahedra is *not* on this list. It was built and measured against the `pressure` a closed surface already takes, and the `pressure` form did better. A hair tier is not on the list either. The solver's hair module accepts no force, collides only with convex hulls, and needs an authored groom. The rod family already exposed carries more simulated strands in a frame than that module does. See [`DESIGN-NOTES.md`](DESIGN-NOTES.md).
- **Lines in 3D.** Lines and polylines run between points in space, with a width measured on screen and a color per point. Solids in front of them hide them. Axis and grid helpers for orienting a scene are built from them.
- **Sweeping and lofting.** A `Shape` sweeps along a 3D path, and it can turn and scale along the way. A surface can also loft through a series of cross-sections. A 3D path with frames that do not twist is the spine of both.
- **Volume rendering.** A 3D grid of density draws as a glowing or light-absorbing cloud. It suits smoke from a simulation, a scanned volume, or 3D noise.


3D mode is opt-in, so a 2D sketch never pays for a depth buffer or a perspective divide. The iPhone point cloud renders through it, and visionOS and AR build on it. See the [design notes](DESIGN-NOTES.md#3d-mode).

## Photorealistic 3D

This is the high-end, curated realism tier. It is opt-in on the existing PBR, IBL, ray-traced shadows and reflections, and SDF raymarching. So a 2D or stylized 3D sketch never pays for it. It grows the way the SDF shape catalog does. When a technique that separates a polished product render or film still from "CG" finds a good fit, it lands Metal-native. Each one is written from the published technique and credited in the Techniques list of `ATTRIBUTION.md`. The deeper display levers live under [rendering and color frontier](#rendering-and-color-frontier). There is no queue here, by design. The tier takes the next technique that fits, rather than working through a list.

See the [design notes](DESIGN-NOTES.md#photorealistic-3d).

## Sound, synthesis, and spatial audio

The audio layer both listens and plays. Listening covers FFT, bands, and beat detection. Playing runs through a polyphonic [`Synth`](Docs/Helpers/Synthesis.md) over shaped, filtered voices with delay and reverb. A [composition](Docs/Helpers/Composition.md) tier feeds it and works out what to play. That covers rhythms, keys, chord progressions, tunings past the twelve semitones, and following the beat in the room. The synth is built over waves, wavetables read by position, grains cut out of a sound, and four physical models (two of them driven rather than struck). There is also a patchable operator graph and an ordered chain of effects. The effects are built-in kinds or closures the sketch writes itself. The layer can read [data out as notes](Docs/Helpers/Sonification.md). The sound can be placed in the 3D scene and carried into an exported video.

See the [design notes](DESIGN-NOTES.md#sound-synthesis-and-spatial-audio).

## Live rigs: physical computing, lighting, and network video

The integration tier reaches other software (Syphon, OSC, MIDI, the virtual camera). This tier reaches the hardware and the network around the machine. That is the physical-computing tradition of the frameworks Ollin comes from:

- **NDI.** NDI is the network sibling of Syphon. It sends and receives live video between machines, and it is the standard in VJ and broadcast rigs. It has no published protocol, so unlike the rest of this tier it cannot be written from a specification. It ships as a satellite over the runtime the user installs from NDI: nothing of NDI's in the repository but its MIT-licensed headers, sending first, then receiving. The reasoning against the SDK license is in the design notes.
- **A pen plotter, driven live.** A sketch sends its paths straight to pen plotters such as the AxiDraw over their serial command set. It streams G-code to GRBL-family machines the same way. Pause, pen height, and a preview of what is left to draw come with it. This needs a plotter on the desk to write against.

All of it follows the interop posture: play in someone's existing rig, do not replace it. See the [design notes](DESIGN-NOTES.md#live-rigs-physical-computing-lighting-and-network-video).

## New input sources

These are more of the platform's live signals. Each one is a `FrameSource` or a simple value read in `draw()`:

- **Apple Pencil.** Tilt, azimuth, and hover on the tablet. The Pencil's force joins the pressure a sketch already reads.
- **Body data, and where the Mac is.** Heart rate from a paired Watch, for biofeedback. The Mac's own location as a slow live input, so a weather can follow the machine.
- **Depth from video, deeper.** The first piece is the metric checkpoint of the video depth model, once its license is settled. With it, a webcam's depth comes in meters and lifts into an `RGBDFrame` and a point cloud. The second piece is the encoder on the Neural Engine, with only the temporal head on the GPU, for twice the readings a second.
- **Pinch and rotate.** The trackpad's pinch and rotate gestures read as plain values in `draw()`, with hooks beside the mouse's. Two-finger gestures on a phone arrive the same way.
- **Typed text.** A sketch reads typed text through the system's input methods. Accents, dead keys, the emoji viewer, and Chinese or Japanese input then arrive as text. `key` still reports single key presses.
- **Following a region across video.** A sketch marks a region of a camera or video frame, and the region is followed as it moves. The trackers find what they were built for, such as bodies, faces, and hands, and this follows whatever the sketch picked.

Several overlap the [iPhone sensor array](#iphone-as-a-sensor-array). These are the Mac-side direct sources. See the [design notes](DESIGN-NOTES.md#new-input-sources).

## New output surfaces

These are ways a sketch leaves the window:

- **Rumble on a game controller.** A game controller's motors are an output of the same kind as [haptics](Docs/Integration/Haptics.md). So they belong with haptics rather than with reading the controller. This needs a controller on the desk to write against.
- **The rest of the sketch on the web page.** The [page export](Docs/Output/Web.md) already carries these parts of a sketch. It carries the analytic shapes, strokes and fills, text and pictures, and the composed and raymarched fields. It also carries the layered effects and the parameters as controls, and it expands strokes and fills on the page from the points the sketch gave. Some things stay with the video export. Those are the effects that are a solve or a ladder on the Mac, lit meshes, ray tracing, and compute work. Pictures that arrive as a texture every frame stay there too. This is not a browser runtime for the framework. That stays out, and the platform stance in `CLAUDE.md` says why.
- **A sketch over the desktop.** The sketch runs in a transparent window that floats above other windows. Clicks pass through wherever the sketch drew nothing, so a piece can stay on screen while you work.
- **A second window.** One sketch draws two views, such as the projector's picture and a control view on the laptop. Two cameras on one world are another case.
- **Motion blur from sub-frames in an export.** An export renders several moments across the shutter for each frame and averages them. Any sketch gets motion blur this way, 2D and shader work included.

See the [design notes](DESIGN-NOTES.md#new-output-surfaces).

## The sketch on a phone, and Swift Playgrounds

A sketch renders through one view on either window system. `Apps/OllinSketchApp` is the reference project for wrapping one as an iOS app. What is ahead is the work around that project: the Swift Playgrounds entry point and the smaller things a device offers.

- **Swift Playgrounds App Projects.** The Swift Playgrounds app has App Projects (`.swiftpm`). They are the closest Swift gets to the p5.js onboarding of "open the editor and type, watch it move". The same package shape embeds a sketch in any SwiftUI app. An App Project is a Swift package, so the [project generator](Docs/Tools/ProjectGenerator.md) can write one as a kind of its own. It is the one app-shaped kind that needs no Xcode project and no signing team. One gate stands in front of all of it. The app builds with its own bundled toolchain rather than the Mac's, and the version in the store bundles a Swift a minor below the floor this tree compiles at, so the work waits on a Playgrounds release that catches up, not on anything here. The dependency itself arrives by git URL, which the public repository serves. [Design notes.](DESIGN-NOTES.md#swift-playgrounds-and-ios)
- **The keyboard on a tablet.** A hardware keyboard feeds the same key path a desk sketch reads, through the UIKit press events. So a keyboard-driven sketch is portable too.

See the [design notes](DESIGN-NOTES.md#swift-playgrounds-and-ios).

## Rendering and color frontier

These are deeper uses of the Metal core and Apple displays. All are opt-in, so the 2D path stays untaxed:

- **Dolby Vision.** Dynamic per-scene HDR metadata, in contrast to the static HDR10 metadata a video carries, which describes the whole file at once. It needs the licensed encoder path rather than AVFoundation's plain HDR writer, so it is a licensing question before it is an API one.
- **A shader as paint.** A `Shader` fills or strokes a 2D shape, computed per pixel in the shape's own coordinates. The same shader can be a mesh's surface material. Pictures, patterns, and noise then become fills, with no clipping by hand.

See the [design notes](DESIGN-NOTES.md#rendering-and-color-frontier).

## Authoring and editor tooling

**Later.** This section covers the editing experiences the live-reload core makes possible, and where Ollin draws its line on AI: nowhere in the work. The README says it ("It's a tool for making art … Ollin is not a generative-art model"), and it extends to any AI *feature*: **AI helped build the framework, and it plays no part in what you make with it.** Not as the author of a sketch, and not at the controls either, because in generative art the parameters are the work. A palette, a density, a speed chosen by hand is the hand. Models that read the world (the [perception tier](Docs/Vision/Vision.md), depth, listening) are input, like a camera, and stay. Within that line:

- **A visual node editor** over the effect, SDF-combinator, and shader graphs. It lives in the live host and round-trips to Swift source.
- **Curves and sequences as parameters.** One inspector row edits a curve by dragging its points, for a falloff or a response. Another edits a row of values as bars, for a step pattern. Both save back into the sketch like any other parameter.

See the [design notes](DESIGN-NOTES.md#authoring-and-editor-tooling).

## Collaboration and multi-device

These are Apple-native ways, with little setup, for several machines to share one piece. A **SharePlay** co-creation idea sits under [Further out / exploratory](#further-out--exploratory). Its shape is settled, but it is gated. See the [design notes](DESIGN-NOTES.md#collaboration-and-multi-device).

## Learning: the Guide

**Near-term.** The reference docs ([`Docs/`](Docs/)) answer "what does this function do". The [Guide](Guide/README.md) is the narrative layer that answers "how do I think in sketches". It is a practical, book-length introduction to creative coding taught through Ollin, written for an engineer with no math, graphics, or Swift background. What is ahead is that the Guide grows in step with the framework. Every capability that ships gets a row in the feature-coverage matrix and a chapter home. The queue, briefs, and coverage plan live in [`Guide/PLAN.md`](Guide/PLAN.md), and the writing rules live in [`Guide/AUTHORING.md`](Guide/AUTHORING.md). The parking lot there reserves a place in the Guide for each item on this page.

## A third-party extension ecosystem

The framework grows past the core team only when other people can publish and find extensions. Other frameworks already have this: p5.js, openFrameworks (`ofx*`), and OPENRNDR (`orx-*`) all have contributed-addon ecosystems. The naming convention, the seams, and the starter are in [Writing an extension](Docs/Tools/Extensions.md). What remains is discovery, and most of it waits on the repository being public:

- **A curated index.** An awesome-list-style page of published extensions, so they can be found without a registry of our own. There is nobody to list yet.
- **Ollin's own front door.** A listing on the Swift Package Index, which is where Swift developers look first, and which builds and hosts the generated API reference for the modules `.spi.yml` names, rebuilding it on every push and keeping a copy per release. A listing is a pull request against the index's own package list, so it is a step somebody takes rather than one that happens. The hand-written [`Docs/`](Docs/) stays the curated reference, and the generated one is the API-completeness net under it.
- **A front door an assistant can read, if that is the right call.** Ollin's agent-facing files point inward. `AGENTS.md` and `CLAUDE.md` describe how to work *on* the framework, and nothing describes how to help somebody *use* it. The site writes an index of the reference and a markdown twin of every page, and a general-purpose documentation server reads a file of that shape as it stands, so an assistant can be pointed at the reference today. What is open is whether Ollin runs a server of its own over the same pages [`ollin docs`](Docs/Tools/Reference.md) reads, answering a search rather than handing back a whole page. Most people arriving now work with an assistant. So the reference reaching that assistant accurately is the difference between good sketches and invented API. This is listed as an open question rather than planned work. The reason is that it sits close to a line this project draws deliberately (see the boundary under [authoring and editor tooling](#authoring-and-editor-tooling)). Serving accurate reference so a person can write their own sketch falls on the permitted side. Anything that starts producing sketches does not. Where exactly the line falls here is @eaviles's call, and what waits on it is a server of Ollin's own rather than the reference itself.

See the [design notes](DESIGN-NOTES.md#a-third-party-extension-ecosystem).

## Further out / exploratory

These are lower-confidence ideas, kept on record but deliberately not near-term. Each is plausible on the platform, but it is speculative enough that it should not crowd the planned work above. This section is distinct from [On the horizon](#on-the-horizon), which holds the platform-gated later legs (visionOS, AR), not uncertain ones.

- **SharePlay co-creation.** Two people tune one sketch together over a FaceTime call. The shape is settled. A GroupActivities transport sits behind the room's transport seam and carries the wire it already speaks (parameters, seed, the shared clock). The sketch is bundled as an app and installed on both Macs, because the `com.apple.developer.group-session` entitlement applies to apps only. Tuning is all it covers. An edit to the sketch is a rebuild on both ends, so co-editing code never travels over the call. It waits on three gates, in order. The first is a public repository, because the other person must be able to get the app. The second is a verified real-signing run for the app kind. The third is demand. See the [design notes](DESIGN-NOTES.md#collaboration-and-multi-device).

## On the horizon

These are larger, later directions. 2D on macOS stays the focus, and these do not change that.

- **visionOS.** Immersive rendering uses a different render loop (CompositorServices rather than `MTKView`). So the per-frame loop stays behind a seam that either a normal view or a visionOS layer renderer can drive. It builds on the [3D mode](#3d-mode). [Design notes.](DESIGN-NOTES.md#3d-mode)
- **AR mode and templates.** AR sketches on Apple platforms, with ready-made templates for face, world, and image tracking. With those templates, an AR sketch becomes "fill in the `draw()`, the tracking is handed to you". It is layered on the [phone](#the-sketch-on-a-phone-and-swift-playgrounds) and [3D](#3d-mode) work rather than being a separate engine. It aims at the gap left by discontinued template-driven AR tools. [Design notes.](DESIGN-NOTES.md#ar-mode-and-templates-the-meta-spark-gap)

Neither can be verified at the desk alone. Both need the right SDKs and a device.
