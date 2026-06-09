// swift-tools-version: 6.0
import PackageDescription

// Ollin — a motion-first creative coding framework for Swift + Metal.
//
// One product: the `Ollin` library you `import Ollin` in your sketches.
// Runnable sketches live as executable targets under `Examples/` — run one
// with e.g. `swift run Example-HelloCircle`.
//
// The `.metal` shader in Sources/Ollin/Renderer is declared as a resource (see
// the Ollin target below) so SwiftPM copies it into the target's resource
// bundle and synthesizes `Bundle.module`. MetalRenderer.loadLibrary reads that
// source from `Bundle.module` and compiles it at runtime.
let package = Package(
    name: "Ollin",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "Ollin", targets: ["Ollin"]),
        // Audio as a satellite library: `import OllinAudio` for microphone, file,
        // and oscillator sources analyzed into values a sketch reads in `draw()`.
        // Kept out of `Ollin` so the drawing core stays free of AVFoundation.
        .library(name: "OllinAudio", targets: ["OllinAudio"]),
        // OSC (Open Sound Control) as a satellite library: `import OllinOSC` to
        // send and receive networked control messages to and from the other tools
        // in a performance rig (TouchOSC, Max/MSP, TouchDesigner, …). Built on
        // Network.framework (UDP); the OSC wire format is implemented from the
        // spec. Kept out of `Ollin` so the drawing core stays free of networking.
        .library(name: "OllinOSC", targets: ["OllinOSC"]),
        // MIDI as a satellite library: `import OllinMIDI` to receive from and send
        // to MIDI gear (control surfaces, keyboards, sequencers) over Core MIDI.
        // Kept out of `Ollin` so the drawing core stays free of Core MIDI.
        .library(name: "OllinMIDI", targets: ["OllinMIDI"]),
        // Physics as a satellite library: `import OllinPhysics` for a small
        // Verlet world — particles, springs, and disk collisions — that a sketch
        // steps each frame so motion comes from simulation, not hand-tuned values.
        // A satellite (like the others) to keep it opt-in; it needs no framework
        // beyond Ollin's own geometry types.
        .library(name: "OllinPhysics", targets: ["OllinPhysics"]),
    ],
    targets: [
        // Shared, runtime-side dev machinery used by the live host and the
        // examples gallery: `SketchLoader` compiles a `Sketch.swift` into a
        // dylib and loads it. Kept in its own library (not in shipping `Ollin`)
        // so the framework stays free of dev-only tooling, but reusable by more
        // than one executable.
        .target(
            name: "OllinRuntime",
            dependencies: ["Ollin"]
        ),
        // The live-reload host. `swift run OllinLive <path/to/Sketch.swift>`
        // opens a window, then recompiles + hot-swaps that sketch on save —
        // edit, save, see it update in place, without the window closing.
        .executableTarget(
            name: "OllinLive",
            // The satellite libraries (OllinAudio/OllinOSC/OllinMIDI/OllinPhysics)
            // are linked (not used by the host) so a hot-swapped sketch that
            // `import`s them resolves its symbols against this process at load,
            // the same way it resolves Ollin's.
            dependencies: ["Ollin", "OllinRuntime", "OllinAudio", "OllinOSC", "OllinMIDI", "OllinPhysics"],
            path: "Sources/OllinLive",
            // Export the host's symbols so a hot-swapped sketch `.dylib`
            // (compiled with `-undefined dynamic_lookup`) resolves its Ollin
            // symbols against *this* process at load. That keeps a single copy
            // of `Sketch` et al., so the loaded sketch casts as `Ollin.Sketch`.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-export_dynamic"])
            ]
        ),
        // The examples gallery: a sidebar list of every Examples/ sketch; click
        // one and it compiles + renders in the detail pane. Reuses OllinRuntime's
        // loader and Ollin's SketchView. Needs -export_dynamic for the same
        // reason OllinLive does.
        .executableTarget(
            name: "OllinExamples",
            // Links the satellite libraries (OllinAudio/OllinOSC/OllinMIDI/
            // OllinPhysics) so gallery sketches that `import` them resolve at load
            // (same reason as OllinLive above).
            dependencies: ["Ollin", "OllinRuntime", "OllinAudio", "OllinOSC", "OllinMIDI", "OllinPhysics"],
            path: "Sources/OllinExamples",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-export_dynamic"])
            ]
        ),
        // Vendored libtess2 (GLU-tessellator lineage), the polygon triangulator
        // behind concave/holed `Shape` fills. Bundled third-party C source under
        // its own SGI-B license — see Sources/CLibtess2/README.md and the
        // repo-root THIRD-PARTY-NOTICES.md. Wrapped behind Ollin's own API; the
        // C symbols are not part of Ollin's public surface. The upstream
        // Source/ + Include/ split is preserved so its relative includes resolve;
        // `publicHeadersPath: Include` exposes only tesselator.h.
        .target(
            name: "CLibtess2",
            path: "External/CLibtess2",
            exclude: ["LICENSE.txt", "README.md"],
            publicHeadersPath: "Include"
        ),
        // Vendored Box2D (Erin Catto's 2D rigid-body engine, v3 — pure C),
        // the solver behind OllinPhysics' rigid-body `World`/`Body`. Bundled
        // third-party C source under its own MIT license — see
        // External/CBox2D/README.md and the repo-root THIRD-PARTY-NOTICES.md.
        // Wrapped behind Ollin's own API; the `b2*` symbols are not part of
        // Ollin's public surface. The upstream src/ + include/ split is
        // preserved so its `#include "box2d/…"` directives resolve;
        // `include/module.modulemap` exposes the `box2d/box2d.h` umbrella, and
        // the upstream CMakeLists/natvis are excluded from the build.
        .target(
            name: "CBox2D",
            path: "External/CBox2D",
            exclude: ["LICENSE", "README.md", "src/CMakeLists.txt", "src/box2d.natvis"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        // Audio: amplitude + FFT analysis (Accelerate/vDSP) of microphone, file,
        // and oscillator sources over AVAudioEngine, plus modest tone generation.
        // A satellite library (like OllinRuntime) so the drawing core stays free
        // of AVFoundation; sketches opt in with `import OllinAudio`.
        .target(
            name: "OllinAudio",
            dependencies: ["Ollin"]
        ),
        // OSC: send/receive OSC messages over UDP via Network.framework, with the
        // OSC 1.0 wire format implemented from the spec (no vendored library). A
        // satellite library (like OllinAudio) so the drawing core stays free of
        // networking; sketches opt in with `import OllinOSC`. Depends on Ollin
        // only to bind an incoming address onto a `@Param` knob.
        .target(
            name: "OllinOSC",
            dependencies: ["Ollin"]
        ),
        // MIDI: receive from and send to MIDI gear over Core MIDI, with the MIDI
        // 1.0 message format parsed/encoded from the spec (no vendored library). A
        // satellite library (like OllinOSC) so the drawing core stays free of Core
        // MIDI; sketches opt in with `import OllinMIDI`. Depends on Ollin only to
        // bind an incoming control onto a `@Param` knob.
        .target(
            name: "OllinMIDI",
            dependencies: ["Ollin"]
        ),
        // Physics: a small Verlet world — particles, springs, and disk collisions
        // — stepped each frame so motion can come from simulation. A satellite
        // library (like OllinAudio) so it stays opt-in; it depends on Ollin only
        // for the `Vector2`/`Rectangle` geometry types, no other framework.
        .target(
            name: "OllinPhysics",
            dependencies: ["Ollin", "CBox2D"]
        ),
        // The structs shared between Swift and the Metal shaders (`OllinVertex`,
        // `Uniforms`, `SDFInstance`) are defined once in a C header so their
        // memory layout can't drift between the two sides. This thin C module
        // makes that header importable from Swift; its umbrella header
        // re-includes the canonical file, which lives beside `Shaders.metal`
        // (see Sources/Ollin/Renderer/OllinShaderTypes.h).
        .target(
            name: "COllinShaders",
            path: "Sources/COllinShaders",
            publicHeadersPath: "include"
        ),
        .target(
            name: "Ollin",
            dependencies: ["CLibtess2", "COllinShaders"],
            // Declaring the `.metal` file as a resource makes SwiftPM copy it
            // into the target's resource bundle and synthesize `Bundle.module`,
            // which MetalRenderer.loadLibrary uses to read and compile the shader
            // source at runtime. (`.process` copies the `.metal` as source; it
            // does not precompile a `default.metallib`.) Without this, the file
            // is "unhandled" and `Bundle.module` is never generated.
            //
            // `OllinShaderTypes.h` ships beside it: the runtime shader compiler
            // has no include path, so MetalRenderer splices this header into the
            // source in place of its `#include` directive.
            resources: [
                .process("Renderer/Shaders.metal"),
                .copy("Renderer/OllinShaderTypes.h"),
                // Cozette (MIT) — the bundled default bitmap font, loaded at
                // runtime by BitmapFont.builtin via the BDF parser. License kept
                // beside it; see THIRD-PARTY-NOTICES.md.
                .copy("Resources/cozette.bdf"),
                .copy("Resources/Cozette-LICENSE.txt"),
                // Hershey Sans (futural) — the bundled default stroke font, loaded
                // at runtime by StrokeFont.builtin via the .jhf parser. Public
                // domain; provenance recorded beside it and in THIRD-PARTY-NOTICES.
                .copy("Resources/futural.jhf"),
                .copy("Resources/Hershey-NOTICE.txt")
            ]
        ),
        // Examples — one runnable sketch per executable target, grouped into
        // category folders (openFrameworks-style). Each example is a single
        // `@main` Sketch file; run one with e.g. `swift run Example-HelloCircle`.
        // Hand-written for now; generate these stanzas once the set grows
        // (see CLAUDE.md: don't hand-maintain dozens of target blocks).
        .executableTarget(
            name: "Example-HelloCircle",
            dependencies: ["Ollin"],
            path: "Examples/Basic/HelloCircle"
        ),
        .executableTarget(
            name: "Example-Guides",
            dependencies: ["Ollin"],
            path: "Examples/Basic/Guides"
        ),
        .executableTarget(
            name: "Example-Capture",
            dependencies: ["Ollin"],
            path: "Examples/Basic/Capture"
        ),
        .executableTarget(
            name: "Example-VectorExport",
            dependencies: ["Ollin"],
            path: "Examples/Basic/VectorExport"
        ),
        .executableTarget(
            name: "Example-Hatching",
            dependencies: ["Ollin"],
            path: "Examples/Basic/Hatching"
        ),
        .executableTarget(
            name: "Example-Breathing",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Breathing"
        ),
        .executableTarget(
            name: "Example-SineSweep",
            dependencies: ["Ollin"],
            path: "Examples/Motion/SineSweep"
        ),
        .executableTarget(
            name: "Example-Easing",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Easing"
        ),
        .executableTarget(
            name: "Example-EasingGallery",
            dependencies: ["Ollin"],
            path: "Examples/Motion/EasingGallery"
        ),
        .executableTarget(
            name: "Example-Smoothing",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Smoothing"
        ),
        .executableTarget(
            name: "Example-Orbits",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Orbits"
        ),
        .executableTarget(
            name: "Example-Linkage",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Linkage"
        ),
        .executableTarget(
            name: "Example-Petals",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Petals"
        ),
        .executableTarget(
            name: "Example-Parameters",
            dependencies: ["Ollin"],
            path: "Examples/Live/Parameters"
        ),
        .executableTarget(
            name: "Example-Trail",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Trail"
        ),
        .executableTarget(
            name: "Example-ColorWaves",
            dependencies: ["Ollin"],
            path: "Examples/Color/ColorWaves"
        ),
        .executableTarget(
            name: "Example-Palettes",
            dependencies: ["Ollin"],
            path: "Examples/Color/Palettes"
        ),
        .executableTarget(
            name: "Example-Colormaps",
            dependencies: ["Ollin"],
            path: "Examples/Color/Colormaps"
        ),
        .executableTarget(
            name: "Example-FlowField",
            dependencies: ["Ollin"],
            path: "Examples/Motion/FlowField"
        ),
        .executableTarget(
            name: "Example-EllipseField",
            dependencies: ["Ollin"],
            path: "Examples/Motion/EllipseField"
        ),
        .executableTarget(
            name: "Example-Attractor",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Attractor"
        ),
        .executableTarget(
            name: "Example-Myriad",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Myriad"
        ),
        .executableTarget(
            name: "Example-RectField",
            dependencies: ["Ollin"],
            path: "Examples/Motion/RectField"
        ),
        .executableTarget(
            name: "Example-Spokes",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Spokes"
        ),
        .executableTarget(
            name: "Example-Star",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Star"
        ),
        .executableTarget(
            name: "Example-Polygons",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Polygons"
        ),
        .executableTarget(
            name: "Example-ArcField",
            dependencies: ["Ollin"],
            path: "Examples/Motion/ArcField"
        ),
        .executableTarget(
            name: "Example-ArcModes",
            dependencies: ["Ollin"],
            path: "Examples/Motion/ArcModes"
        ),
        .executableTarget(
            name: "Example-Gaussian",
            dependencies: ["Ollin"],
            path: "Examples/Randomness/Gaussian"
        ),
        .executableTarget(
            name: "Example-Ring",
            dependencies: ["Ollin"],
            path: "Examples/Randomness/Ring"
        ),
        .executableTarget(
            name: "Example-DotGrid",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/DotGrid"
        ),
        .executableTarget(
            name: "Example-Phyllotaxis",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/Phyllotaxis"
        ),
        .executableTarget(
            name: "Example-RepelGrid",
            dependencies: ["Ollin"],
            path: "Examples/Input/RepelGrid"
        ),
        .executableTarget(
            name: "Example-Keys",
            dependencies: ["Ollin"],
            path: "Examples/Input/Keys"
        ),
        .executableTarget(
            name: "Example-WarpGrid",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/WarpGrid"
        ),
        .executableTarget(
            name: "Example-EnergyGrid",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/EnergyGrid"
        ),
        .executableTarget(
            name: "Example-NoiseField",
            dependencies: ["Ollin"],
            path: "Examples/Randomness/NoiseField"
        ),
        .executableTarget(
            name: "Example-RandomBand",
            dependencies: ["Ollin"],
            path: "Examples/Randomness/RandomBand"
        ),
        .executableTarget(
            name: "Example-NoiseWave",
            dependencies: ["Ollin"],
            path: "Examples/Randomness/NoiseWave"
        ),
        .executableTarget(
            name: "Example-Triangles",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Triangles"
        ),
        .executableTarget(
            name: "Example-LifeQuilt",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/LifeQuilt"
        ),
        .executableTarget(
            name: "Example-Markers",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/Markers"
        ),
        .executableTarget(
            name: "Example-NamedPolygons",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/NamedPolygons"
        ),
        .executableTarget(
            name: "Example-ShapeMenagerie",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/ShapeMenagerie"
        ),
        .executableTarget(
            name: "Example-Primitives",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/Primitives"
        ),
        .executableTarget(
            name: "Example-HollowShapes",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/HollowShapes"
        ),
        .executableTarget(
            name: "Example-StrokeAlignment",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/StrokeAlignment"
        ),
        .executableTarget(
            name: "Example-StrokeJoinsAndCaps",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/StrokeJoinsAndCaps"
        ),
        .executableTarget(
            name: "Example-Mandala",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Mandala"
        ),
        .executableTarget(
            name: "Example-HelloText",
            dependencies: ["Ollin"],
            path: "Examples/Text/HelloText"
        ),
        .executableTarget(
            name: "Example-TextVolume",
            dependencies: ["Ollin"],
            path: "Examples/Text/TextVolume"
        ),
        .executableTarget(
            name: "Example-PlaydateFont",
            dependencies: ["Ollin"],
            path: "Examples/Text/PlaydateFont",
            // The font lives beside the sketch (the per-example asset convention)
            // and loads at runtime through the Playdate `.fnt` loader.
            resources: [.copy("MarbleMadness.fnt")]
        ),
        .executableTarget(
            name: "Example-OutlineText",
            dependencies: ["Ollin"],
            path: "Examples/Text/OutlineText"
        ),
        .executableTarget(
            name: "Example-GlyphWave",
            dependencies: ["Ollin"],
            path: "Examples/Text/GlyphWave"
        ),
        .executableTarget(
            name: "Example-TextOnPath",
            dependencies: ["Ollin"],
            path: "Examples/Text/TextOnPath"
        ),
        .executableTarget(
            name: "Example-TextBox",
            dependencies: ["Ollin"],
            path: "Examples/Text/TextBox"
        ),
        .executableTarget(
            name: "Example-VariableFont",
            dependencies: ["Ollin"],
            path: "Examples/Text/VariableFont"
        ),
        .executableTarget(
            name: "Example-StrokeText",
            dependencies: ["Ollin"],
            path: "Examples/Text/StrokeText"
        ),
        .executableTarget(
            name: "Example-TextMetrics",
            dependencies: ["Ollin"],
            path: "Examples/Text/TextMetrics"
        ),
        .executableTarget(
            name: "Example-GlyphContours",
            dependencies: ["Ollin"],
            path: "Examples/Text/GlyphContours"
        ),
        .executableTarget(
            name: "Example-PointShimmer",
            dependencies: ["Ollin"],
            path: "Examples/Text/PointShimmer"
        ),
        .executableTarget(
            name: "Example-JitterType",
            dependencies: ["Ollin"],
            path: "Examples/Text/JitterType"
        ),
        .executableTarget(
            name: "Example-PixelField",
            dependencies: ["Ollin"],
            path: "Examples/Images/PixelField"
        ),
        .executableTarget(
            name: "Example-Spectrum",
            dependencies: ["Ollin", "OllinAudio"],
            path: "Examples/Audio/Spectrum"
        ),
        .executableTarget(
            name: "Example-Microphone",
            dependencies: ["Ollin", "OllinAudio"],
            path: "Examples/Audio/Microphone"
        ),
        .executableTarget(
            name: "Example-FilePlayer",
            dependencies: ["Ollin", "OllinAudio"],
            path: "Examples/Audio/FilePlayer",
            // The bundled clip the sketch loads via Bundle.module (a launch path
            // overrides it). CC BY-SA, provenance in THIRD-PARTY-NOTICES.md.
            resources: [.copy("fandanguito.m4a")]
        ),
        // Integration tier — OSC, and (later) MIDI/Syphon. Self-contained: the
        // sketch sends OSC to itself on loopback and visualizes what it receives,
        // so it needs no external app to run.
        .executableTarget(
            name: "Example-OSCLoopback",
            dependencies: ["Ollin", "OllinOSC"],
            path: "Examples/Integration/OSCLoopback"
        ),
        // Listens for OSC and prints/draws every message — point a phone or any
        // OSC source at this Mac to discover what its controls send.
        .executableTarget(
            name: "Example-OSCMonitor",
            dependencies: ["Ollin", "OllinOSC"],
            path: "Examples/Integration/OSCMonitor"
        ),
        // Self-contained: a virtual-source output sends animated MIDI to itself and
        // the input draws it back, so it runs with no hardware (like OSCLoopback).
        .executableTarget(
            name: "Example-MIDILoopback",
            dependencies: ["Ollin", "OllinMIDI"],
            path: "Examples/Integration/MIDILoopback"
        ),
        // Listens to every MIDI source and prints/draws what arrives — connect a
        // controller and discover what each knob/pad sends just by touching it.
        .executableTarget(
            name: "Example-MIDIMonitor",
            dependencies: ["Ollin", "OllinMIDI"],
            path: "Examples/Integration/MIDIMonitor"
        ),
        // Physics — a Verlet world stepped each frame. Packing is a field of
        // colliding discs; Blobs are spring-built soft bodies that squish.
        .executableTarget(
            name: "Example-Packing",
            dependencies: ["Ollin", "OllinPhysics"],
            path: "Examples/Physics/Packing"
        ),
        .executableTarget(
            name: "Example-Blobs",
            dependencies: ["Ollin", "OllinPhysics"],
            path: "Examples/Physics/Blobs"
        ),
        .executableTarget(
            name: "Example-Stack",
            dependencies: ["Ollin", "OllinPhysics"],
            path: "Examples/Physics/Stack"
        ),
        // Recreations — sketches recreating past computer artists, namespaced by
        // artist (see Examples/Recreations/README.md).
        .executableTarget(
            name: "Example-VeraMolnar-Interruptions",
            dependencies: ["Ollin"],
            path: "Examples/Recreations/VeraMolnar/Interruptions"
        ),
        .executableTarget(
            name: "Example-VeraMolnar-DesOrdres",
            dependencies: ["Ollin"],
            path: "Examples/Recreations/VeraMolnar/DesOrdres"
        ),
        .executableTarget(
            name: "Example-BridgetRiley-Fragment3",
            dependencies: ["Ollin"],
            path: "Examples/Recreations/BridgetRiley/Fragment3"
        ),
        .executableTarget(
            name: "Example-BridgetRiley-Current",
            dependencies: ["Ollin"],
            path: "Examples/Recreations/BridgetRiley/Current"
        ),
        .executableTarget(
            name: "Example-OsamuSato-Totem",
            dependencies: ["Ollin"],
            path: "Examples/Recreations/OsamuSato/Totem"
        ),
        .executableTarget(
            name: "Example-OsamuSato-Alphabet",
            dependencies: ["Ollin"],
            path: "Examples/Recreations/OsamuSato/Alphabet"
        ),
        // Render-correctness snapshot tests: render small deterministic sketches
        // off-screen (the `--export` path) and diff them against committed
        // reference PNGs in `References/`. Regenerate the references with
        // `OLLIN_RECORD_SNAPSHOTS=1 swift test`. Skips when no Metal device.
        .testTarget(
            name: "OllinTests",
            dependencies: ["Ollin"],
            resources: [.copy("References")]
        ),
        // DSP correctness for the audio analyzer: feed synthesized signals and
        // check amplitude and the spectrum peak bin. GPU-independent, so it runs
        // in CI alongside the rest of the GPU-free tests.
        .testTarget(
            name: "OllinAudioTests",
            dependencies: ["OllinAudio"]
        ),
        // OSC correctness: wire-format encode/decode round-trips (every arg type,
        // padding edges, malformed input rejected without trapping) plus an
        // in-process UDP loopback. GPU-independent, so it runs in CI too.
        .testTarget(
            name: "OllinOSCTests",
            dependencies: ["OllinOSC"]
        ),
        // MIDI correctness: MIDI 1.0 / UMP parse+encode round-trips (every message
        // kind, malformed/non-1.0 words rejected without trapping) — Core MIDI-free,
        // so it runs in CI. The loopback self-test needs the Core MIDI server and
        // skips when it's unavailable.
        .testTarget(
            name: "OllinMIDITests",
            dependencies: ["OllinMIDI"]
        ),
        // Physics correctness: Verlet integration (a body falls the expected
        // distance under gravity), spring rest-length restoration, pinned bodies
        // staying put, disk collisions separating overlap, and wall bounce. No
        // GPU, so it runs in CI.
        .testTarget(
            name: "OllinPhysicsTests",
            dependencies: ["OllinPhysics", "CBox2D"]
        ),
    ],
    // The whole package builds in the Swift 6 language mode, so data-race safety
    // is enforced as errors everywhere — framework, hosts, and example sketches.
    swiftLanguageModes: [.v6]
)
