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

Ollin is pre-1.0, and the public API still changes freely. Semantic version tags and a changelog begin with `0.1.0`, so a SwiftPM project has a version to pin before the API settles. At major zero, a breaking change or a new feature bumps the minor, and a fix bumps the patch. A consumer pins `.upToNextMinor`, and each release names its breaking renames in its notes. Version 1.0.0 is the release where the API settles. From that point on, every public rename ships a deprecation shim, which is the migration discipline described in [`CLAUDE.md`](CLAUDE.md). This section names what that release waits on, and only that. Everything else on this page stays open for work at any time. The release does not wait on that work, and that work does not wait for the release.

- **Stabilization.** The release waits on three things here. The first is a last naming sweep over the public API before the tag, because the shim discipline locks the names in at the release. The second is a test suite that is reliable end to end, with no flaky or machine-bound failures. The third is working down the hand-verification backlog, which is the features that still wait on eyes, ears, or hardware.
- **The release itself.** This is the release notes, the `1.0.0` tag, and a README presentation pass. The ecosystem legs that need a public repository (DocC, a Swift Package Index listing, the extension index) follow the release. They do not gate it.
- **What an open repository is expected to carry.** These are the surfaces a visitor sees beside the README. None of them can be set from a file. The first is the About description and topics. The second is a social-preview image; the card the website already serves, `Logo/ollin-social.png`, is the file to upload. The third is Discussions switched on, with a Show and tell category and a pinned welcome thread. The fourth is a logged-out check that the issues link and the install URL resolve. The domains are set here too. The canonical home the About field names is ollin.art, and ollin.run, ollin.live, and ollin.mov become permanent redirects to it. All of these are small, and they are cheaper to set before the first stranger arrives than after. See the [design notes](DESIGN-NOTES.md#opening-the-repository), which also cover what the README presentation pass has to decide.

## Up next

These are near-term, fairly self-contained pieces. Each one is small and well-scoped.

- **More SDF shapes, when a good fit appears.** A candidate is any canonical form parameterized by a size and a ratio or two. Such a shape drops into the instanced-SDF path as four small touch-points: a shape tag, a builder, a distance function, and a fragment case.

## Generative geometry

This tier is a set of classic generative-art building blocks. Each one emits vector geometry (points, `Contour`s, `Shape`s) that feeds the existing draw, shape-boolean, hatching, and SVG paths, rather than the renderer. They follow the plotter-friendly, geometry-first pattern that the shape booleans set. All of them run off the existing seedable `random`/`noise`, so a run is reproducible. Each ships with an example. Several are the natural implementation behind a [recreation](DESIGN-NOTES.md#examples-folder) of a work by the artist who pioneered them. The conventions for adding one are in the [design notes](DESIGN-NOTES.md#generative-geometry). The broader algorithm catalog is the [technique and algorithm helpers](#technique-and-algorithm-helpers) tier.

## Technique and algorithm helpers

**Near-term.** This is a standing catalog of classic creative-coding techniques and algorithms as first-class helpers. It keeps growing, as the SDF shapes, the effect `Filter`s, and the [generative-geometry](#generative-geometry) builders do. Each one lands wherever it fits the existing core. A geometry emitter goes beside the shape builders. An escape-time or field technique becomes a GPU `Generator` or shader. A simulation goes beside the compute and `SimField` paths. Each ships with an example, and each runs off the seedable `random`/`noise`, so a result reproduces. Each is implemented from the published technique, which is credited in the Techniques list of `ATTRIBUTION.md`. Many map onto the *Nature of Code* canon (vectors, forces, particles, autonomous agents, cellular automata, fractals, evolution). That makes the catalog a familiar entry point for a reader who comes from that book. The geometry-emitting recipes are flagged plotter-friendly for the pen-plotter path.

See the [design notes](DESIGN-NOTES.md#technique-and-algorithm-helpers).

## Expressive brushes and strokes

This is the hand-drawn, mark-making axis. It is built on the variable-width stroke renderer, which gives a width per vertex, shaped by a `strokeProfile`. It also builds on the recorded marks that drive that renderer from the hand, and on the brushes that stamp a shape along a path. What is ahead is Apple Pencil tilt and azimuth as further drivers. They need a Pencil and a tablet, so they sit under [new input sources](#new-input-sources). Painterly simulation (the generative-watercolor family) stays a [technique-catalog](#technique-and-algorithm-helpers) recipe rather than a brush-engine feature. See the [design notes](DESIGN-NOTES.md#expressive-brushes-and-strokes).

## iPhone as a sensor array

A Mac has no depth camera, no inertial sensors, and no spare Neural Engine for live perception. A tethered iPhone has all three. The idea is to let the phone act as a sensor and an on-device ML co-processor for a sketch that still renders on the Mac. The phone captures and perceives (LiDAR point clouds, face and body tracking, segmentation, device motion, and more). It streams typed results that the sketch reads in `draw()`. A recorded RGBD clip and a tethered phone's live USB RGBD stream already reconstruct on the Mac as point clouds (see [`Docs/3D/Record3D.md`](Docs/3D/Record3D.md)). That is the kind of world-facing depth feed an Intel RealSense once gave openFrameworks. A sweep of the phone's depth frames fuses by camera pose into one world cloud. That cloud stays registered, and it straightens itself when the phone comes back to a place it has already scanned. Alongside that world cloud, the phone reconstructs the room as a labeled surface (see [`Docs/3D/Phone.md`](Docs/3D/Phone.md)). The work ahead grows that stream into the rest of the phone's senses, over Ollin's own iPhone capture app. One direction for the work ahead follows from how the stream works today. The wire runs one way, from the phone to the Mac, so a sketch cannot tell the phone what to look for. For that reason, the pictures the phone recognizes live in its own folder. Handing a reference down the same cable would put that choice back in the `.swift` file, where the rest of the piece lives. The wire protocol, the sensor catalog, and the build order are in the [design notes](DESIGN-NOTES.md#iphone-as-a-sensor-array).

## 3D mode

2D stays the default, and 3D keeps building out on top of the pieces that already exist. Those are the camera, depth buffer, transform stack, solid primitives, and textured meshes. Meshes loaded from file also belong there, with their materials, textures, and the full surface-map set. The pieces also include the directional/point/spot light and material model, curated lighting presets, and the stylized material library (iridescent, velvet, jade, toon, gooch, …). There is also the physically-based metallic-roughness material, and image-based lighting from bundled, downloaded, or loaded HDRI environments (with a skybox backdrop). The last pieces are matcap materials (view-normal sphere-texture shading) and directional, spot, and point cast shadows. The work ahead builds on all of that:

- **Soft bodies that meet themselves.** Cloth drapes, folds, and holds air. But a folded sheet passes through its own layers, and two sheets pass through each other. That happens because self-collision and cloth-against-cloth are gaps in the solver underneath, not in the API over it. Tearing is further out still. It needs a shared vertex split and a rebuilt constraint set in the middle of a simulation, which that solver cannot do at all. Both wait on the library growing them. When it does, they land as more capability on the shipped `SoftBody3D` surface. A filled jelly held by tetrahedra is *not* on this list. It was built and measured against the `pressure` a closed surface already takes, and the `pressure` form did better. A hair tier is not on the list either. The solver's hair module accepts no force, collides only with convex hulls, and needs an authored groom. The rod family already exposed carries more simulated strands in a frame than that module does. See [`DESIGN-NOTES.md`](DESIGN-NOTES.md).


3D mode is opt-in, so a 2D sketch never pays for a depth buffer or a perspective divide. The iPhone point cloud renders through it, and visionOS and AR build on it. See the [design notes](DESIGN-NOTES.md#3d-mode).

## Photorealistic 3D

This is the high-end, curated realism tier. It is opt-in on the existing PBR, IBL, ray-traced shadows and reflections, and SDF raymarching. So a 2D or stylized 3D sketch never pays for it. It grows the way the SDF shape catalog does. When a technique that separates a polished product render or film still from "CG" finds a good fit, it lands Metal-native. Each one is written from the published technique and credited in the Techniques list of `ATTRIBUTION.md`. The deeper display levers live under [rendering and color frontier](#rendering-and-color-frontier). There is no queue here, by design. The tier takes the next technique that fits, rather than working through a list.

See the [design notes](DESIGN-NOTES.md#photorealistic-3d).

## Sound, synthesis, and spatial audio

The audio layer both listens and plays. Listening covers FFT, bands, and beat detection. Playing runs through a polyphonic [`Synth`](Docs/Helpers/Synthesis.md) over shaped, filtered voices with delay and reverb. A [composition](Docs/Helpers/Composition.md) tier feeds it and works out what to play. That covers rhythms, keys, chord progressions, tunings past the twelve semitones, and following the beat in the room. The synth is built over waves, wavetables read by position, and four physical models (two of them driven rather than struck). There is also a patchable operator graph and an ordered chain of effects. The effects are built-in kinds or closures the sketch writes itself. The layer can read [data out as notes](Docs/Helpers/Sonification.md). The sound can be placed in the 3D scene and carried into an exported video.

See the [design notes](DESIGN-NOTES.md#sound-synthesis-and-spatial-audio).

## Live rigs: physical computing, lighting, and network video

The integration tier reaches other software (Syphon, OSC, MIDI, the virtual camera). This tier reaches the hardware and the network around the machine. That is the physical-computing tradition of the frameworks Ollin comes from:

- **NDI.** NDI is the network sibling of Syphon. It sends and receives live video between machines, and it is the standard in VJ and broadcast rigs. Its SDK is binary-only under its own license. So unlike the source-vendored tier, it needs a licensing review before any code is written. That review decides whether and how it ships.

All of it follows the interop posture: play in someone's existing rig, do not replace it. See the [design notes](DESIGN-NOTES.md#live-rigs-physical-computing-lighting-and-network-video).

## New input sources

These are more of the platform's live signals. Each one is a `FrameSource` or a simple value read in `draw()`:

- **Apple Pencil.** Tilt, azimuth, and hover on the tablet. The Pencil's force joins the pressure a sketch already reads.
- **Body data, and where the Mac is.** Heart rate from a paired Watch, for biofeedback. The Mac's own location as a slow live input, so a weather can follow the machine.
- **Depth from video, deeper.** The first piece is the metric checkpoint of the video depth model, once its license is settled. With it, a webcam's depth comes in meters and lifts into an `RGBDFrame` and a point cloud. The second piece is the encoder on the Neural Engine, with only the temporal head on the GPU, for twice the readings a second.

Several overlap the [iPhone sensor array](#iphone-as-a-sensor-array). These are the Mac-side direct sources. See the [design notes](DESIGN-NOTES.md#new-input-sources).

## New output surfaces

These are ways a sketch leaves the window:

- **Rumble on a game controller.** A game controller's motors are an output of the same kind as [haptics](Docs/Integration/Haptics.md). So they belong with haptics rather than with reading the controller. This needs a controller on the desk to write against.
- **A desktop widget.** Wrap a sketch as a widget, so the output lives in the system rather than in a window. A widget's timeline refreshes on a scale of minutes. So the design question is what a `draw()` means under that constraint.
- **The rest of the sketch on the web page.** The [page export](Docs/Output/Web.md) already carries these parts of a sketch. It carries the analytic shapes, strokes and fills, text and pictures, and the composed and raymarched fields. It also carries the layered effects and the parameters as controls, and it expands strokes and fills on the page from the points the sketch gave. Some things stay with the video export. Those are the effects that are a solve or a ladder on the Mac, lit meshes, ray tracing, and compute work. Pictures that arrive as a texture every frame stay there too. This is not a browser runtime for the framework. That stays out, and the platform stance in `CLAUDE.md` says why.

See the [design notes](DESIGN-NOTES.md#new-output-surfaces).

## The sketch on a phone, and Swift Playgrounds

A sketch renders through one view on either window system. `Apps/OllinSketchApp` is the reference project for wrapping one as an iOS app. What is ahead is the work around that project: the Swift Playgrounds entry point and the smaller things a device offers.

- **Swift Playgrounds App Projects.** The Swift Playgrounds app has App Projects (`.swiftpm`). They are the closest Swift gets to the p5.js onboarding of "open the editor and type, watch it move". The same package shape embeds a sketch in any SwiftUI app. An App Project is a Swift package, so the [project generator](Docs/Tools/ProjectGenerator.md) can write one as a kind of its own. It is the one app-shaped kind that needs no Xcode project and no signing team. Two questions gate it, in order. The first is whether the Playgrounds app's own bundled toolchain builds the framework's platform floor at all. The second is how the package dependency arrives. It arrives by git URL there, so the tablet waits on the repository being public. The Mac app is the place to verify against a local checkout first. [Design notes.](DESIGN-NOTES.md#swift-playgrounds-and-ios)
- **The keyboard on a tablet.** A hardware keyboard feeds the same key path a desk sketch reads, through the UIKit press events. So a keyboard-driven sketch is portable too.

See the [design notes](DESIGN-NOTES.md#swift-playgrounds-and-ios).

## Rendering and color frontier

These are deeper uses of the Metal core and Apple displays. All are opt-in, so the 2D path stays untaxed:

- **Dolby Vision.** Dynamic per-scene HDR metadata, in contrast to the static HDR10 metadata a video carries, which describes the whole file at once. It needs the licensed encoder path rather than AVFoundation's plain HDR writer, so it is a licensing question before it is an API one.

See the [design notes](DESIGN-NOTES.md#rendering-and-color-frontier).

## Authoring and editor tooling

**Later.** This section covers the editing experiences the live-reload core makes possible, and where Ollin draws its line on AI: nowhere in the work. The README says it ("It's a tool for making art … Ollin is not a generative-art model"), and it extends to any AI *feature*: **AI helped build the framework, and it plays no part in what you make with it.** Not as the author of a sketch, and not at the controls either, because in generative art the parameters are the work. A palette, a density, a speed chosen by hand is the hand. Models that read the world (the [perception tier](Docs/Vision/Vision.md), depth, listening) are input, like a camera, and stay. Within that line:

- **A visual node editor** over the effect, SDF-combinator, and shader graphs. It lives in the live host and round-trips to Swift source.
- **Deeper live-coding evaluation.** Per-block evaluation and sub-second turnaround on small edits for the OllinLiveCoding performance host. This refines its evaluate-on-command loop.
- **A field that takes a rule.** The inspector row for a parameter takes its rule as typed text. That way a rule is written where the parameter is set, rather than only in the sketch or the automation file. The row also points at where the text went wrong, because `FormulaError` carries the character offset for exactly that.

See the [design notes](DESIGN-NOTES.md#authoring-and-editor-tooling).

## Collaboration and multi-device

These are Apple-native ways, with little setup, for several machines to share one piece. A **SharePlay** co-creation idea sits under [Further out / exploratory](#further-out--exploratory). Its shape is settled, but it is gated. See the [design notes](DESIGN-NOTES.md#collaboration-and-multi-device).

## Learning: the Guide

**Near-term.** The reference docs ([`Docs/`](Docs/)) answer "what does this function do". The [Guide](Guide/README.md) is the narrative layer that answers "how do I think in sketches". It is a practical, book-length introduction to creative coding taught through Ollin, written for an engineer with no math, graphics, or Swift background. What is ahead is that the Guide grows in step with the framework. Every capability that ships gets a row in the feature-coverage matrix and a chapter home. The queue, briefs, and coverage plan live in [`Guide/PLAN.md`](Guide/PLAN.md), and the writing rules live in [`Guide/AUTHORING.md`](Guide/AUTHORING.md). The parking lot there reserves a place in the Guide for each item on this page.

## A third-party extension ecosystem

The framework grows past the core team only when other people can publish and find extensions. Other frameworks already have this: p5.js, openFrameworks (`ofx*`), and OPENRNDR (`orx-*`) all have contributed-addon ecosystems. The naming convention, the seams, and the starter are in [Writing an extension](Docs/Tools/Extensions.md). What remains is discovery, and most of it waits on the repository being public:

- **A curated index.** An awesome-list-style page of published extensions, so they can be found without a registry of our own. There is nobody to list yet.
- **Ollin's own front door.** This is two things: the API reference as a DocC catalog, and a Swift Package Index listing. The catalog would be hosted through the Swift Package Index's documentation support or GitHub Pages. Those are the places Swift developers look first. Both need a public repository. The hand-written [`Docs/`](Docs/) stays the curated reference, and DocC is the API-completeness net under it.
- **A front door an assistant can read, if that is the right call.** Ollin's agent-facing files point inward. `AGENTS.md` and `CLAUDE.md` describe how to work *on* the framework, and nothing describes how to help somebody *use* it. The outward version is a small, well-understood set of conventions: a machine-readable index of the reference, and the same index served over a tool protocol. Both are built over the same pages [`ollin docs`](Docs/Tools/Reference.md) reads. Most people arriving now work with an assistant. So the reference reaching that assistant accurately is the difference between good sketches and invented API. This is listed as an open question rather than planned work. The reason is that it sits close to a line this project draws deliberately (see the boundary under [authoring and editor tooling](#authoring-and-editor-tooling)). Serving accurate reference so a person can write their own sketch falls on the permitted side. Anything that starts producing sketches does not. Where exactly the line falls here is @eaviles's call. It is better settled before the repository opens than after something ships under it. What waits on that call is only the part that points an assistant at the reference.

See the [design notes](DESIGN-NOTES.md#a-third-party-extension-ecosystem).

## Further out / exploratory

These are lower-confidence ideas, kept on record but deliberately not near-term. Each is plausible on the platform, but it is speculative enough that it should not crowd the planned work above. This section is distinct from [On the horizon](#on-the-horizon), which holds the platform-gated later legs (visionOS, AR), not uncertain ones.

- **SharePlay co-creation.** Two people tune one sketch together over a FaceTime call. The shape is settled. A GroupActivities transport sits behind the room's transport seam and carries the wire it already speaks (parameters, seed, the shared clock). The sketch is bundled as an app and installed on both Macs, because the `com.apple.developer.group-session` entitlement applies to apps only. Tuning is all it covers. An edit to the sketch is a rebuild on both ends, so co-editing code never travels over the call. It waits on three gates, in order. The first is a public repository, because the other person must be able to get the app. The second is a verified real-signing run for the app kind. The third is demand. See the [design notes](DESIGN-NOTES.md#collaboration-and-multi-device).

## On the horizon

These are larger, later directions. 2D on macOS stays the focus, and these do not change that.

- **visionOS.** Immersive rendering uses a different render loop (CompositorServices rather than `MTKView`). So the per-frame loop stays behind a seam that either a normal view or a visionOS layer renderer can drive. It builds on the [3D mode](#3d-mode). [Design notes.](DESIGN-NOTES.md#3d-mode)
- **AR mode and templates.** AR sketches on Apple platforms, with ready-made templates for face, world, and image tracking. With those templates, an AR sketch becomes "fill in the `draw()`, the tracking is handed to you". It is layered on the [phone](#the-sketch-on-a-phone-and-swift-playgrounds) and [3D](#3d-mode) work rather than being a separate engine. It aims at the gap left by discontinued template-driven AR tools. [Design notes.](DESIGN-NOTES.md#ar-mode-and-templates-the-meta-spark-gap)

Neither can be verified at the desk alone. Both need the right SDKs and a device.
