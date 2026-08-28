# Ollin roadmap

Ollin is a creative-coding framework for Swift and Metal on Apple platforms, aiming for p5.js ergonomics on an OPENRNDR-grade core. This file is the running list of what's planned and what's being explored. If you'd like to help, it's a good place to start.

For how the framework works and the conventions behind it, see the guides in [`Docs/`](Docs/). For working code, browse [`Examples/`](Examples/).

## How to contribute

A few things worth knowing before you pick something up:

- Building and running needs macOS 26+ and a Metal-capable GPU. There's no way around the Swift toolchain and Metal, so changes are verified on a Mac.
- New drawing features are built on the typed core first (the `Drawer` and the value types), then given the bare p5-style call as sugar. Anything the bare API can do, the core should be able to do too, with more control.
- A feature isn't considered done until it has an example. Examples live in [`Examples/`](Examples/), one idea per sketch, and they're compile-tested in CI so they don't rot. Writing the example is also how the API gets a sanity check: if it's awkward to write, the API probably needs work.
- The items under [Up next](#up-next) are the most self-contained, so they tend to make the best first contributions.
- A rough priority sits under sections where it helps: **Near-term** marks well-scoped, good next pickups; **Later** marks bigger items that lean on earlier work. Untagged sections are substantial and wanted, just not the very next thing. Genuinely speculative ideas live under [Further out / exploratory](#further-out--exploratory); the platform-gated legs under [On the horizon](#on-the-horizon).

If you're coming from p5.js or Processing, [the Guide's Appendix C](Guide/C-ComingFromP5.md) maps the API you already know onto Ollin, and [`Docs/Swift.md`](Docs/Swift.md) covers just enough Swift to get productive.

## Toward 1.0

Ollin is pre-1.0, and the public API still changes freely. Version 1.0.0 will be the first public release: the repository opens, semantic version tags and a changelog begin, and from that point on every public rename ships a deprecation shim (the migration discipline described in [`CLAUDE.md`](CLAUDE.md)). This section names what that release waits on, and only that. Everything else on this page stays open for work at any time: the release does not wait on it, and it does not wait for the release.

- **The capabilities a newcomer will look for first.** The most visible gaps for someone arriving from p5.js, Processing, or openFrameworks: the model examples under [Up next](#up-next).
- **Stabilization.** A naming-and-consistency pass over the whole public API, since the shim discipline locks the names in at the release; the test suite reliable end to end, with no flaky or machine-bound failures; and the hand-verification backlog (features that still wait on eyes, ears, or hardware) worked down.
- **The release itself.** The changelog, the release notes, the `1.0.0` tag, and a README presentation pass. The ecosystem legs that need a public repository (DocC, a Swift Package Index listing, the extension index) follow the release rather than gate it.
- **What an open repository is expected to carry.** The files a visitor and GitHub's own interface both look for, which a private repository never needed. A `CONTRIBUTING.md`, since the guidance currently lives in a README section and GitHub links a real file from the issue and pull-request views. A code of conduct, which matters more here than the file's boilerplate reputation suggests, because the creative-coding community reads one as a signal and Ollin is asking that community for trust on the attribution and AI questions already. Issue and pull-request templates, so a bug report arrives with the macOS and GPU details every graphics bug needs. A `SECURITY.md` naming where to send something private. None of these are large, and all of them are cheaper to write before the repository opens than after the first stranger arrives. See the [design notes](DESIGN-NOTES.md#opening-the-repository), which also cover what the README presentation pass has to decide.

## Up next

Near-term, fairly self-contained pieces, each small and well-scoped.

- **More SDF shapes, when a good fit appears.** Any canonical form parameterized by a size and a ratio or two drops into the instanced-SDF path as four small touch-points (a shape tag, a builder, a distance function, and a fragment case).
- **More model examples over `ModelTracker`.** The custom-model tracker runs anything converted to Core ML; a well-known model can make a strong example, with the weights always fetched by `Scripts/fetch-models.sh` rather than committed. Candidates, licenses, and the surfaces involved are in the [design notes](DESIGN-NOTES.md#model-examples-and-modeltracker-surfaces).

## Generative geometry

A tier of classic generative-art building blocks that emit vector geometry (points, `Contour`s, `Shape`s) feeding the existing draw, shape-boolean, hatching, and SVG paths rather than the renderer. They share the plotter-friendly, geometry-first shape the shape booleans set, all driven by the existing seedable `random`/`noise` so a run is reproducible, each ships with an example, and several are the natural implementation behind a [recreation](DESIGN-NOTES.md#examples-folder) of the artist who pioneered them. The conventions for adding one are in the [design notes](DESIGN-NOTES.md#generative-geometry); the broader algorithm catalog is the [technique and algorithm helpers](#technique-and-algorithm-helpers) tier.

## Technique and algorithm helpers

**Near-term.** A standing, growing catalog of classic creative-coding techniques and algorithms as first-class helpers, the way the SDF shapes, the effect `Filter`s, and the [generative-geometry](#generative-geometry) builders are catalogs that keep growing. Each one lands wherever it fits the existing core (a geometry emitter beside the shape builders, a GPU `Generator` or shader for an escape-time or field technique, a simulation beside the compute and `SimField` paths), ships with an example, runs off the seedable `random`/`noise` so a result reproduces, and is implemented from the published technique (credited in `ATTRIBUTION.md`'s Techniques list). Many map onto the *Nature of Code* canon (vectors, forces, particles, autonomous agents, cellular automata, fractals, evolution), so the catalog doubles as a familiar on-ramp from that world, and the geometry-emitting recipes are flagged plotter-friendly for the pen-plotter path.

See the [design notes](DESIGN-NOTES.md#technique-and-algorithm-helpers).

## Expressive brushes and strokes

The hand-drawn, mark-making axis, built on the variable-width stroke renderer (a width per vertex, shaped by a `strokeProfile`), the recorded marks that drive it from the hand, and the brushes that stamp a shape along a path. What's ahead: Apple Pencil tilt and azimuth as further drivers, which wait on the iOS leg under [new input sources](#new-input-sources). Painterly simulation (the generative-watercolor family) stays a [technique-catalog](#technique-and-algorithm-helpers) recipe rather than a brush-engine feature. See the [design notes](DESIGN-NOTES.md#expressive-brushes-and-strokes).

## iPhone as a sensor array

A Mac has no depth camera, inertial sensors, or spare Neural Engine for live perception; a tethered iPhone has all three. The idea: let the phone act as a sensor and on-device ML co-processor for a sketch that still renders on the Mac, capturing and perceiving (LiDAR point clouds, face and body tracking, segmentation, device motion, and more) and streaming typed results the sketch reads in `draw()`. Both a recorded RGBD clip and a tethered phone's live USB RGBD stream already reconstruct on the Mac as point clouds (see [`Docs/3D/Record3D.md`](Docs/3D/Record3D.md)), the kind of world-facing depth feed an Intel RealSense once gave openFrameworks, and a sweep of the phone's depth frames fuses by camera pose into one world cloud that stays registered and straightens itself when it comes back to a place it has already scanned, beside the room the phone reconstructs as a labeled surface (see [`Docs/3D/Phone.md`](Docs/3D/Phone.md)). The work ahead grows that stream into the rest of the phone's senses over Ollin's own iPhone capture app. The wire protocol, the sensor catalog, and the build order are in the [design notes](DESIGN-NOTES.md#iphone-as-a-sensor-array).

## 3D mode

2D stays the default, and 3D keeps building out on top of the existing camera, depth buffer, transform stack, solid primitives, meshes loaded from file (with their materials, textures, and the full surface-map set), textured meshes, the directional/point/spot light & material model, curated lighting presets, the stylized material library (iridescent, velvet, jade, toon, gooch, …), the physically-based metallic-roughness material, image-based lighting from bundled, downloaded, or loaded HDRI environments (with a skybox backdrop), matcap materials (view-normal sphere-texture shading), and directional, spot, and point cast shadows:

- **Soft bodies that meet themselves.** Cloth drapes, folds, and holds air, but a folded sheet passes through its own layers and two sheets pass through each other, because self-collision and cloth-against-cloth are gaps in the solver underneath rather than in the API over it. Tearing is further out still: it needs a shared vertex split and a rebuilt constraint set mid-simulation, which that solver cannot do at all. Both wait on the library growing them, and land as more capability on the shipped `SoftBody3D` surface when it does. (A filled jelly held by tetrahedra is *not* on this list: it was built and measured against the `pressure` a closed surface already takes, and lost. Neither is a hair tier: the solver's hair module accepts no force, collides only with convex hulls, and needs an authored groom, and the rod family already exposed carries more simulated strands in a frame than it does. See [`DESIGN-NOTES.md`](DESIGN-NOTES.md).)


It's opt-in, so a 2D sketch never pays for a depth buffer or a perspective divide. The iPhone point cloud renders through it, and visionOS and AR build on it. See the [design notes](DESIGN-NOTES.md#3d-mode).

## Photorealistic 3D

The high-end, well-curated realism tier, opt-in on the existing PBR, IBL, ray-traced shadows and reflections, and SDF raymarching, so a 2D or stylized 3D sketch never pays. It grows the way the SDF shape catalog does: when a technique that separates a polished product render or film still from "CG" finds a good fit, it lands Metal-native, written from the published technique and credited in `ATTRIBUTION.md`'s Techniques list. The deeper display levers live under [rendering and color frontier](#rendering-and-color-frontier). There is no queue here, by design: the tier takes the next technique that earns its place rather than working through a list.

See the [design notes](DESIGN-NOTES.md#photorealistic-3d).

## Sound, synthesis, and spatial audio

The audio layer both listens (FFT, bands, beat detection) and plays: a polyphonic [`Synth`](Docs/Helpers/Synthesis.md) over shaped, filtered voices with delay and reverb, fed by a [composition](Docs/Helpers/Composition.md) tier that works out what to play (rhythms, keys, chord progressions, tunings past the twelve semitones, and following the beat in the room), over waves, four physical models (two of them driven rather than struck), a patchable operator graph and an ordered chain of effects (built-in kinds or closures the sketch writes itself), reading [data out as notes](Docs/Helpers/Sonification.md), placed in the 3D scene and carried into an exported video.

See the [design notes](DESIGN-NOTES.md#sound-synthesis-and-spatial-audio).

## Tempo sync

Beat, phase, and BPM from MIDI clock are the `TempoClock` in `OllinMIDI` (see [`Docs/Integration/MIDI.md`](Docs/Integration/MIDI.md)); the network tier is **Ableton Link**, the cross-app, cross-machine standard for shared tempo and beat phase across apps and devices on a local network. Joining a Link session would let a sketch share a whole rig's tempo and downbeat with no cabling or manual setup, the way most modern music apps do. Its SDK is GPLv2 or a paid license, so it stays the inspiration-only tier (reimplement the documented protocol from spec, never vendor it, the same posture as Hydra's AGPL), and it's a networked clock-consensus protocol, so it's substantial work rather than a quick pickup. See the [design notes](DESIGN-NOTES.md#tempo-sync).

## Live rigs: physical computing, lighting, and network video

The integration tier reaches other software (Syphon, OSC, MIDI, the virtual camera); this tier reaches the hardware and the network around the machine, the physical-computing heritage of the lineage Ollin comes from:

- **Bluetooth LE.** Peripheral reads surfaced the way OSC and MIDI already read: a latest-value cache, a message drain, `@Param` binding.
- **NDI.** The network sibling of Syphon: send and receive live video between machines, the standard in VJ and broadcast rigs. Its SDK is binary-only under its own license, so unlike the source-vendored tier it needs a licensing review before any code; that review decides whether and how it ships.

All of it is the interop posture: play in someone's existing rig, not replace it. See the [design notes](DESIGN-NOTES.md#live-rigs-physical-computing-lighting-and-network-video).

## New input sources

More of the platform's live signals, each a `FrameSource` or a simple value read in `draw()`:

- **Apple Pencil.** Tilt, azimuth, and hover on the iOS leg, with its force joining the pressure a sketch already reads.
- **Body and world data.** Heart rate from a paired Watch for biofeedback, and real-world ambient data (weather, location) as a slow live input.

Several overlap the [iPhone sensor array](#iphone-as-a-sensor-array); these are the Mac-side direct sources. See the [design notes](DESIGN-NOTES.md#new-input-sources).

## New output surfaces

Ways a sketch leaves the window:

- **Rumble on a game controller.** A pad's motors are an output of the same kind as [haptics](Docs/Integration/Haptics.md), so they belong with that rather than with reading the pad. It needs a controller on the desk to write against.
- **A desktop widget.** Wrap a sketch as a widget, so the output lives in the system rather than a window. The timeline refresh there is measured in minutes, so what a `draw()` means under that constraint is the design question.

See the [design notes](DESIGN-NOTES.md#new-output-surfaces).

## Rendering and color frontier

Deeper use of the Metal core and Apple displays, all opt-in so the 2D path stays untaxed:

- **Dolby Vision.** Dynamic per-scene HDR metadata, where the static HDR10 metadata a video carries describes the whole file at once. It needs the licensed encoder path rather than AVFoundation's plain HDR writer, so it is a licensing question before it is an API one.

See the [design notes](DESIGN-NOTES.md#rendering-and-color-frontier). (The most speculative item here, AI frame interpolation, sits under [Further out / exploratory](#further-out--exploratory).)

## Authoring and editor tooling

**Later.** Editing experiences the live-reload core makes possible, and where Ollin draws its line on AI. The public stance already holds (the README's "It's a tool for making art ... Ollin is not a generative-art model"), and it extends to any AI *feature*: **AI is a tool for operating the framework, never an author of sketches.** Helping wire a generator, suggest a filter, or move knobs toward a look is in scope; generating a whole sketch or its imagery from a prompt is deliberately out. Within that line:

- **A visual node editor** over the effect, SDF-combinator, and shader graphs, living in the live host and round-tripping to Swift source.
- **Deeper live-coding evaluation.** Per-block evaluation and sub-second turnaround on small edits for the OllinLiveCoding performance host, refining its evaluate-on-command loop, plus MIDI/OSC mapping of the host's own performance surface.
- **A field that takes a rule.** The inspector row for a knob taking its rule as typed text, so a rule is written where the knob is turned rather than only in the sketch or the automation file, and pointing at where the text went wrong (`FormulaError` carries the character offset for exactly that).
- **A parameter timeline.** The host surface over the knob tracks a sketch carries: a lane per knob, keys placed and dragged by hand, curve handles shaped by eye, and a playhead scrubbed over the deterministic clock, writing back to the same file the tracks already read. The live host reading that file on launch, and carrying it across a reload, belongs with it.
- **Direct manipulation.** Drag a shape in the running window and have the edit written back into the source, the way a SwiftUI preview manipulates a layout.
- **AI at the controls.** Drive the knobs, wire and parameterize generators, and tune toward a described look, all as operations on the typed `@Param` and effect graph, with the artist composing the sketch.
- **On-device ML as a material.** Apple-silicon models a sketch invokes deliberately, like a noise function: semantic parameter control, neural style as a `Filter`, segmentation-driven generators. Image generation from a text prompt is the one to weigh most carefully against the stance above; if it ships, it is an optional material the artist composes with, never the framework making the piece.

See the [design notes](DESIGN-NOTES.md#authoring-and-editor-tooling).

## Collaboration and multi-device

Apple-native, low-ceremony ways several machines share one piece: the **iPhone as a 6DoF wand** (extending the sensor stream the phone already sends). (A more speculative **SharePlay** co-creation idea sits under [Further out / exploratory](#further-out--exploratory).) See the [design notes](DESIGN-NOTES.md#collaboration-and-multi-device).

## Learning: the Guide

**Near-term.** The reference docs ([`Docs/`](Docs/)) answer "what does this function do"; the [Guide](Guide/README.md) is the narrative layer that answers "how do I think in sketches": a practical, book-length introduction to creative coding taught through Ollin, written for an engineer with no math, graphics, or Swift background. Ahead: the Guide grows in step with the framework. Every capability that ships gets a row in the feature-coverage matrix and a chapter home (the queue, briefs, and coverage plan live in [`Guide/PLAN.md`](Guide/PLAN.md), the writing rules in [`Guide/AUTHORING.md`](Guide/AUTHORING.md)), and the parking lot there reserves a Guide seat for each item on this page. Further out: a website presenting the Guide, the reference, and the examples gallery together.

## A third-party extension ecosystem

The framework grows past the core team only when other people can publish and find extensions, the contributed-addon ecosystems p5.js, openFrameworks (`ofx*`), and OPENRNDR (`orx-*`) all have. The naming convention, the seams, and the starter are in [Writing an extension](Docs/Tools/Extensions.md). What remains is discovery, and most of it waits on the repository being public:

- **A curated index.** An awesome-list-style page of published extensions, so they are findable without a registry of our own. There is nobody to list yet.
- **Ollin's own front door.** The API reference as a DocC catalog (hosted through the Swift Package Index's documentation support or GitHub Pages) and a Swift Package Index listing, the places Swift developers look first. Both need a public repository. The hand-written [`Docs/`](Docs/) stays the curated reference; DocC is the API-completeness net under it.
- **A front door an assistant can read, if that is the right call.** Ollin's agent-facing files point inward: `AGENTS.md` and `CLAUDE.md` describe how to work *on* the framework, and nothing describes how to help somebody *use* it. The outward version of that is a small, well-understood set of conventions (a machine-readable index of the reference, the docs and examples served offline through the `ollin` CLI, the same served over a tool protocol) and most people arriving now work with an assistant, so the reference reaching it accurately is the difference between good sketches and invented API. It is listed as an open question rather than planned work, because it sits close to a line this project draws deliberately (see the boundary under [authoring and editor tooling](#authoring-and-editor-tooling)): serving accurate reference so a person can write their own sketch falls on the permitted side, and anything that starts producing sketches does not. Where exactly the line falls here is @eaviles's call, and it is better settled before the repository opens than after something ships under it.
- **The extension kind in the generator window.** `ollin new --kind extension` writes a package from the command line. The window previews a starting point by *running* it, and a library has nothing to run, so it needs a stage that shows source instead of a frame before it can be offered there.

See the [design notes](DESIGN-NOTES.md#a-third-party-extension-ecosystem).

## Further out / exploratory

Lower-confidence ideas kept on record but deliberately not near-term: each is plausible on the platform, but speculative enough that it shouldn't crowd the planned work above. Distinct from [On the horizon](#on-the-horizon), which is the platform-gated later legs (iOS, visionOS, AR), not uncertainty.

- **AI frame interpolation.** Render at a lower frame rate and ship smooth slow-motion via an on-device interpolation model.
- **Text-to-image as a material.** On-device diffusion a sketch could invoke as an optional, labeled material. The one to weigh hardest against the AI boundary, since it sits closest to the contested use, so it lives here rather than in the planned [authoring tier](#authoring-and-editor-tooling); see the AI stance stated there.
- **SharePlay co-creation.** Two people tuning one sketch together over a FaceTime call (GroupActivities). The most speculative of the [collaboration](#collaboration-and-multi-device) ideas.

## On the horizon

Larger, later directions. 2D on macOS stays the focus; these don't change that.

- **Swift Playgrounds and iOS.** Swift Playgrounds App Projects are the closest Swift gets to the p5.js "open the editor and type, watch it move" experience, and the same work unlocks iPad sketching and embedding in any SwiftUI app. The view layer is already SwiftUI-embeddable; the main blocker is declaring an iOS target and making the view conditional across AppKit and UIKit. The Metal renderer is already portable. [Design notes.](DESIGN-NOTES.md#swift-playgrounds-and-ios)
- **visionOS.** Immersive rendering uses a different render loop (CompositorServices rather than `MTKView`), so the per-frame loop stays behind a seam that either a normal view or a visionOS layer renderer can drive. It builds on the [3D mode](#3d-mode) and the iOS target. [Design notes.](DESIGN-NOTES.md#3d-mode)
- **AR mode and templates.** AR sketches on Apple platforms, with ready-made templates for face, world, and image tracking, so an AR sketch becomes "fill in the `draw()`, the tracking is handed to you". It's layered on the iOS and 3D work rather than a separate engine, and aims at the gap left by discontinued template-driven AR tools. [Design notes.](DESIGN-NOTES.md#ar-mode-and-templates-the-meta-spark-gap)

These three can't be verified in every environment; iOS, visionOS, and AR need the right SDKs, a simulator, or a device.
