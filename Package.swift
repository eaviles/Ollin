// swift-tools-version: 6.0
import PackageDescription

// Ollin — a motion-first creative coding framework for Swift + Metal.
//
// One product: the `Ollin` library you `import Ollin` in your sketches.
// Runnable sketches live as executable targets under `Examples/` — run one
// with e.g. `swift run Example-Basic-HelloCircle`.
//
// The `.metal` shader in Sources/Ollin/Renderer is declared as a resource (see
// the Ollin target below) so SwiftPM copies it into the target's resource
// bundle and synthesizes `Bundle.module`. MetalRenderer.loadLibrary reads that
// source from `Bundle.module` and compiles it at runtime.

// The satellite libraries a sketch can link beside the core. Typed (not raw
// strings) so a call site can't misspell one, and so the dev hosts can link
// the whole set via `Satellite.allCases` instead of a hand-kept list.
enum Satellite: String, CaseIterable {
    case audio = "OllinAudio"
    case osc = "OllinOSC"
    case midi = "OllinMIDI"
    case physics = "OllinPhysics"
    case vision = "OllinVision"
    case video = "OllinVideo"
    case syphon = "OllinSyphon"
    case camera = "OllinCamera"
    case record3D = "OllinRecord3D"
    case phone = "OllinPhone"

    var dependency: Target.Dependency { .byName(name: rawValue) }
}

// One example sketch = one line in the targets list. The target name is
// derived from the folder path under Examples/ ("Basic/HelloCircle" →
// Example-Basic-HelloCircle), so name and path can't drift apart; satellite
// libraries ride the second argument and co-located assets `resources:`.
func example(
    _ folder: String,
    _ satellites: [Satellite] = [],
    resources: [Resource]? = nil,
    dependencies extra: [Target.Dependency] = []
) -> Target {
    .executableTarget(
        name: "Example-" + folder.split(separator: "/").joined(separator: "-"),
        dependencies: ["Ollin"] + satellites.map(\.dependency) + extra,
        path: "Examples/" + folder,
        resources: resources
    )
}

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
        // Computer vision as a satellite library: `import OllinVision` for the
        // Mac's camera (built-in, Continuity, or external) plus Apple Vision /
        // Core ML perception — face/hand/body tracking, segmentation, contours,
        // and more — surfaced as typed values a sketch reads in `draw()`. Kept out
        // of `Ollin` so the drawing core stays free of AVFoundation / Vision.
        .library(name: "OllinVision", targets: ["OllinVision"]),
        // Video playback as a satellite library: `import OllinVideo` to play a
        // video file into a sketch as a live image — each decoded frame arrives
        // as a GPU texture drawn through `drawImage`. Kept out of `Ollin` so the
        // drawing core stays free of AVFoundation playback (the input-side
        // companion to the core's offline video export).
        .library(name: "OllinVideo", targets: ["OllinVideo"]),
        // Syphon as a satellite library: `import OllinSyphon` to share live
        // visuals with the other apps on a Mac (openFrameworks via ofxSyphon,
        // Resolume, MadMapper, VDMX, …) — publish the sketch's rendered frames as
        // a Syphon source and consume an external Syphon texture as an input.
        // Built on the vendored Syphon Framework (Metal subset, BSD 2-Clause);
        // kept out of `Ollin` so the drawing core stays free of that dependency.
        .library(name: "OllinSyphon", targets: ["OllinSyphon"]),
        // The virtual-camera publish client: `import OllinCamera` to feed a
        // sketch's rendered frames to the Ollin Camera system virtual camera,
        // so every app that takes a webcam (including browsers, which Syphon
        // can't reach) reads the sketch as a live camera. The camera device is
        // installed once by the Ollin Camera app (Apps/OllinCameraApp); this
        // library connects to it from any sketch process.
        .library(name: "OllinCamera", targets: ["OllinCamera"]),
        // Record3D RGBD recordings as a satellite library: `import OllinRecord3D`
        // to open a `.r3d` clip captured by the Record3D iOS app and turn its
        // color-plus-depth frames into 3D point clouds drawn through `Camera3D`.
        // The device-free first slice of the iPhone-as-a-sensor-array work; pure
        // Apple-native decode (ZIP + LZFSE + ImageIO), kept out of `Ollin`.
        .library(name: "OllinRecord3D", targets: ["OllinRecord3D"]),
        // The Ollin iPhone capture app's Mac client: `import OllinPhone` to read a
        // tethered phone's live on-device ARKit sensor stream (body pose, device
        // motion) over USB. The own-app sibling of OllinRecord3D's borrowed RGBD
        // feed; the wire format (PhoneWire) is shared verbatim with the iOS app.
        .library(name: "OllinPhone", targets: ["OllinPhone"]),
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
            // Every satellite library is linked (not used by the host) so a
            // hot-swapped sketch that `import`s one resolves its symbols
            // against this process at load, the same way it resolves Ollin's.
            dependencies: ["Ollin", "OllinRuntime"] + Satellite.allCases.map(\.dependency),
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
            // Links every satellite library so gallery sketches that `import`
            // them resolve at load (same reason as OllinLive above).
            dependencies: ["Ollin", "OllinRuntime"] + Satellite.allCases.map(\.dependency),
            path: "Sources/OllinExamples",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-export_dynamic"])
            ]
        ),
        // The live-coding performance host: one window where the running sketch
        // fills the stage and the code rides over it; ⌘↩ recompiles the editor
        // buffer and hot-swaps the sketch mid-motion. Reuses OllinRuntime's
        // loader + session engine. Needs -export_dynamic and the satellite
        // links for the same reasons OllinLive does.
        .executableTarget(
            name: "OllinLiveCoding",
            dependencies: ["Ollin", "OllinRuntime"] + Satellite.allCases.map(\.dependency),
            path: "Sources/OllinLiveCoding",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-export_dynamic"])
            ]
        ),
        // The Guide's figure runner: `swift run OllinGuideFigures` compiles every
        // Guide/Figures sketch through OllinRuntime's loader and renders its
        // committed image into Guide/Images (see Guide/AUTHORING.md). Exits
        // nonzero when any figure fails, so a stale Guide listing breaks here
        // instead of in front of a reader. Needs -export_dynamic + the satellite
        // links for the same reasons OllinLive does (figures load as dylibs).
        .executableTarget(
            name: "OllinGuideFigures",
            dependencies: ["Ollin", "OllinRuntime"] + Satellite.allCases.map(\.dependency),
            path: "Sources/OllinGuideFigures",
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
        // Vendored Hosek-Wilkie analytic sky model (RGB path): Lukas Hosek and
        // Alexander Wilkie's coefficient dataset + configuration code, the model
        // behind the procedural-sky environment (`Environment.sky`). Bundled
        // third-party C source under its own 3-clause BSD license. See
        // External/CHosekWilkie/README.md and the repo-root THIRD-PARTY-NOTICES.md.
        // Wrapped behind Ollin's own API (the `arhosek_*` symbols stay off Ollin's
        // public surface); the upstream model + private headers live in Source/,
        // and `publicHeadersPath: Include` exposes only the thin Ollin-authored
        // ollin_hosek_bridge.h.
        .target(
            name: "CHosekWilkie",
            path: "External/CHosekWilkie",
            exclude: ["LICENSE", "README.md"],
            publicHeadersPath: "Include"
        ),
        // Vendored Clipper2 (Angus Johnson's polygon clipping + offsetting
        // library, C++), the engine behind `Shape`'s booleans (union/
        // intersection/subtracting/symmetricDifference) and `offset(by:join:)`.
        // Bundled third-party C++ source under its own Boost Software License —
        // see External/CClipper2/README.md and the repo-root
        // THIRD-PARTY-NOTICES.md. Wrapped behind Ollin's own API; Swift imports
        // only the thin C shim in include/ (no C++ interop), so the
        // `Clipper2Lib` symbols stay off Ollin's public surface. The upstream
        // include/ + src/ layout is preserved under Clipper2Lib/ so its
        // `#include "clipper2/…"` directives resolve.
        .target(
            name: "CClipper2",
            path: "External/CClipper2",
            exclude: ["LICENSE", "README.md"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("Clipper2Lib/include")
            ],
            linkerSettings: [
                .linkedLibrary("c++")
            ]
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
        // Vendored Syphon Framework (Metal subset) — the IOSurface-backed GPU
        // frame-sharing engine behind `OllinSyphon`. Bundled third-party
        // Objective-C source under its own BSD 2-Clause license — see
        // External/CSyphon/README.md and the repo-root THIRD-PARTY-NOTICES.md.
        // Wrapped behind Ollin's own API; the `Syphon*` symbols are not part of
        // Ollin's public surface. `include/` holds a curated umbrella +
        // module.modulemap exposing only the Metal server/client + directory;
        // the implementation headers sit in the target root (found via the `.`
        // header search path). The upstream `Syphon_Prefix.pch` is supplied with
        // `-include` (it defines SYPHONLOG and imports Cocoa for every `.m`) and
        // excluded from the source set. Syphon is ARC, so no `-fno-objc-arc`.
        .target(
            name: "CSyphon",
            path: "External/CSyphon",
            exclude: ["License.txt", "README.md", "Syphon_Prefix.pch"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include"),
                // `-include` the prefix (SYPHONLOG + Cocoa for every `.m`).
                // `-UDEBUG` undefines the debug-build DEBUG macro *for Syphon only*,
                // so its SYPHONLOG connection-lifecycle NSLogs stay quiet in a
                // `swift run`/`swift test` debug build (they'd otherwise spam).
                .unsafeFlags(["-include", "Syphon_Prefix.pch", "-UDEBUG"])
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("IOSurface"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOKit"),
                .linkedFramework("Cocoa")
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
        // Computer vision: the Mac's camera over AVFoundation plus Apple Vision /
        // Core ML perception, wrapped behind Ollin's own typed trackers and result
        // values (the Vision substrate stays private and swappable). A satellite
        // (like OllinAudio) so the drawing core stays free of AVFoundation/Vision;
        // sketches opt in with `import OllinVision`. Depends on Ollin for the
        // `Image`/`Vector2`/`Rectangle` types results map onto.
        .target(
            name: "OllinVision",
            dependencies: ["Ollin"]
        ),
        // Syphon: publish/consume live GPU frames to/from other Mac apps over the
        // vendored Syphon Framework, wrapped behind Ollin's own SyphonServer /
        // SyphonClient. A satellite (like OllinOSC) so the drawing core stays free
        // of the dependency; depends on Ollin for the extension seam + `Image`.
        .target(
            name: "OllinSyphon",
            dependencies: ["Ollin", "CSyphon"]
        ),
        // Virtual camera: publish the sketch's rendered frames to the Ollin
        // Camera system extension over its CMIO sink stream (IOSurface-backed,
        // no CPU round-trip), so webcam apps and browsers read the sketch as a
        // camera. A satellite so the drawing core stays free of CoreMediaIO;
        // depends on Ollin for the rendered-texture extension seam.
        .target(
            name: "OllinCamera",
            dependencies: ["Ollin"]
        ),
        // Video playback: a `VideoPlayer` over AVPlayer that surfaces each decoded
        // frame as a texture-backed `Image` (CVMetalTextureCache, no CPU round-trip)
        // a sketch draws with `drawImage`. A satellite (like OllinAudio) so the
        // drawing core stays free of AVFoundation playback; sketches opt in with
        // `import OllinVideo`.
        .target(
            name: "OllinVideo",
            dependencies: ["Ollin"]
        ),
        // Record3D RGBD recordings: a `Record3DRecording` that opens a `.r3d` clip
        // (a ZIP of a metadata JSON + per-frame JPEG color, LZFSE float32 depth, and
        // confidence) and unprojects each frame into a `PointCloud`. Native decode
        // only (Foundation/Compression/ImageIO); the `.r3d` format is read clean-room
        // from its public structure. A satellite (like OllinVideo) so the core stays
        // lean; sketches opt in with `import OllinRecord3D`.
        .target(
            name: "OllinRecord3D",
            dependencies: ["Ollin", "OllinUSBMux"]
        ),
        // Shared usbmuxd transport: the publicly-documented protocol that tunnels a
        // TCP connection to a USB-tethered iPhone (the plumbing Xcode and
        // libimobiledevice use). Extracted from OllinRecord3D so OllinPhone shares
        // it; `package`-level surface, no library product — it's transport plumbing,
        // not public API. No dependencies (pure Foundation/Darwin).
        .target(
            name: "OllinUSBMux"
        ),
        // The Ollin iPhone capture app's Mac client: reads a tethered phone's live
        // on-device ARKit sensor stream (body pose, device motion) over the usbmuxd
        // tunnel. A satellite (like OllinRecord3D) so the drawing core stays lean.
        // PhoneWire.swift is shared verbatim with the iOS app (Apps/OllinPhoneApp),
        // so it imports only Foundation/simd — never Ollin.
        .target(
            name: "OllinPhone",
            dependencies: ["Ollin", "OllinUSBMux"]
        ),
        // The structs shared between Swift and the Metal shaders (`OllinVertex`,
        // `Uniforms`, `SDFInstance`) are defined once in a C header so their
        // memory layout can't drift between the two sides. This thin C module
        // makes that header importable from Swift; its umbrella header
        // re-includes the canonical file, which lives beside the shader segments
        // (see Sources/Ollin/Renderer/OllinShaderTypes.h).
        .target(
            name: "COllinShaders",
            path: "Sources/COllinShaders",
            publicHeadersPath: "include"
        ),
        .target(
            name: "Ollin",
            dependencies: ["CLibtess2", "CClipper2", "COllinShaders", "CHosekWilkie"],
            // Declaring the `.metal` files as resources makes SwiftPM copy them
            // into the target's resource bundle and synthesize `Bundle.module`,
            // which MetalRenderer.loadLibrary reads and concatenates (ShaderCore
            // first, then the rest) into one library it compiles at runtime. Use
            // `.copy` so the *raw source* ships: on current toolchains `.process`
            // instead precompiles a single `default.metallib`, which can't carry
            // the device-conditional `OLLIN_RT_SHADOWS` define (ray-traced point
            // shadows on a capable GPU) — runtime compilation is what makes that
            // variant, the hot-reload seam, and user shaders possible.
            //
            // `OllinShaderTypes.h` ships beside them: the runtime shader compiler
            // has no include path, so MetalRenderer splices this header into the
            // concatenated source in place of its `#include` directive.
            resources: [
                .copy("Renderer/OllinShaderLib.metal"),
                .copy("Renderer/ShaderCore.metal"),
                .copy("Renderer/ShaderShapes.metal"),
                .copy("Renderer/ShaderCombinator.metal"),
                .copy("Renderer/Shader3D.metal"),
                .copy("Renderer/ShaderRaymarch.metal"),
                .copy("Renderer/ShaderEffects.metal"),
                .copy("Renderer/ShaderCombine.metal"),
                .copy("Renderer/ShaderSim.metal"),
                .copy("Renderer/ShaderPatterns.metal"),
                .copy("Renderer/ShaderIBL.metal"),
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
                .copy("Resources/Hershey-NOTICE.txt"),
                // Built-in matcap (material-capture) sphere textures, loaded at
                // runtime by Matcap.chrome/clay/jade/… The whole directory is copied
                // (a Matcaps/ subdirectory in the bundle), CC0 license kept beside
                // them; derived from Blender's CC0 matcaps, see THIRD-PARTY-NOTICES.md.
                .copy("Resources/Matcaps"),
                // Built-in HDRI environment maps for image-based lighting, loaded at
                // runtime by Environment.studio/sunset/… (equirectangular EXR, half-float
                // PIZ so ImageIO decodes them). CC0; per-file provenance + credits in the
                // resource LICENSE file and THIRD-PARTY-NOTICES.md.
                .copy("Resources/Environments")
            ]
        ),
        // Examples: one runnable sketch per executable target, grouped into
        // category folders. Each example is a single `@main` Sketch file; run
        // one with e.g. `swift run Example-Basic-HelloCircle`. Each line is an
        // `example(...)` call (the helper above the package declaration):
        // adding an example is the folder plus one line here.
        example("Basic/HelloCircle"),
        example("Basic/NormalizedCoordinates"),
        example("Basic/Guides"),
        example("Export/Capture"),
        example("Export/VectorExport"),
        example("Export/Hatching"),
        example("Rendering/Blending"),
        example("Effects/Bloom"),
        example("Shapes/Combinators"),
        example("Shapes/CombinatorsGradient"),
        example("Shapes/CombinatorsStretch"),
        example("Shapes/CombinatorsJoinery"),
        example("Shapes/CombinatorsDetailing"),
        example("3D/Raymarching/RaymarchedReceiveShadow"),
        example("3D/Raymarching/RaymarchedPointCast"),
        example("3D/Raymarching/RaymarchedPointReceive"),
        example("3D/Raymarching/RaymarchedStretch"),
        example("3D/Raymarching/RaymarchedEnvironment"),
        example("Effects/Feedback"),
        example("Effects/Compose"),
        example("Effects/Aside"),
        example("Effects/Defocus"),
        example("Rendering/Accumulation"),
        example("Effects/ColorFilters"),
        example("Effects/BlurFilters"),
        example("Effects/StylizeFilters"),
        example("Effects/RetroFilters"),
        example("Effects/Relight"),
        example("Effects/Glitter"),
        example("Effects/MeshGradient"),
        example("Effects/DesignPatterns"),
        example("Effects/PatternFields"),
        example("Effects/DesignFilters"),
        example("Effects/Distortion"),
        example("Simulation/GrayScott"),
        example("Simulation/GameOfLife"),
        example("Simulation/Lenia"),
        example("Simulation/Fluid"),
        example("Simulation/ParticleLife"),
        example("Simulation/PrimordialParticles"),
        example("Simulation/Physarum"),
        example("Simulation/ParticleFluid"),
        example("Simulation/SoftBodies"),
        example("Effects/Fractals"),
        example("Effects/Patterns"),
        example("Effects/Cellular"),
        example("Shaders/HelloShader"),
        example("Shaders/ShaderFilter"),
        example("Shaders/ShaderBlend"),
        example("Shaders/ShaderFile", resources: [.copy("ripple.metal")]),
        example("Shaders/VisualSynth"),
        example("Shaders/DomainWarp"),
        example("Rendering/ToneMapping"),
        example("Rendering/DepthOfField"),
        example("Rendering/RetainedBatch"),
        example("Compute/CurlField"),
        // The kernels live in their own .metal file (highlighted, editor-checked);
        // .copy ships the source for Ollin's runtime compiler to read + splice.
        example("Compute/ReactionDiffusion", resources: [.copy("Kernels.metal")]),
        // Drives the raw SpatialHash, so it constructs OllinParticle buffers directly
        // and needs the shared-struct module (which the typed sims hide).
        example("Compute/NeighborSearch", dependencies: [.byName(name: "COllinShaders")]),
        example("3D/Geometry/PointCloud"),
        example("3D/Geometry/StrangeAttractor"),
        example("3D/Geometry/Transforms"),
        example("3D/Geometry/Solids"),
        example("3D/Raymarching/RaymarchedSDF"),
        example("3D/Raymarching/RaymarchedShapes"),
        example("3D/Raymarching/RaymarchedSculpt"),
        example("3D/Raymarching/RaymarchedJoinery"),
        example("3D/Raymarching/RaymarchedDistort"),
        example("3D/Raymarching/RaymarchedDetailing"),
        example("3D/Raymarching/RaymarchedClay"),
        example("3D/Raymarching/RaymarchedDomain"),
        example("3D/Raymarching/RaymarchedRadial"),
        example("3D/Raymarching/RaymarchedPlane"),
        example("3D/Raymarching/RaymarchedCastShadow"),
        example("3D/Raymarching/RaymarchedGradient"),
        example("3D/Raymarching/RaymarchedShadow"),
        example("3D/Effects/SceneDefocus"),
        example("3D/Effects/AmbientOcclusion"),
        example("3D/Effects/ScreenSpaceReflections"),
        example("3D/Effects/RayTracedReflections"),
        example("3D/Geometry/TexturedMesh"),
        example("3D/Geometry/Wireframe"),
        example("3D/Geometry/LoadedMesh", resources: [.copy("model.gltf"), .copy("model.obj")]),
        example("3D/Geometry/ShapeFactory"),
        example("3D/Camera/CameraControl"),
        example("3D/Camera/CameraMoves"),
        example("3D/Camera/SceneViews"),
        example("3D/Lighting/Lighting"),
        example("3D/Lighting/LightingPresets"),
        example("3D/Materials/Materials"),
        example("3D/Materials/PhysicalMaterials"),
        example("3D/Environments/ImageBasedLighting"),
        example("3D/Environments/EnvironmentGallery"),
        example("3D/Environments/ProceduralSky"),
        example("3D/Environments/HighResEnvironment"),
        example("3D/Environments/EnvironmentURL"),
        example("3D/Materials/Matcap"),
        example("3D/Lighting/Shadows"),
        example("3D/Lighting/SpotShadow"),
        example("3D/Lighting/PointShadow"),
        example("3D/Depth/DepthCompositing"),
        example("3D/Depth/DepthCloud", [.vision]),
        example("3D/Depth/DepthOcclusion", [.vision]),
        example("3D/Depth/Record3DCloud", [.record3D]),
        example("3D/Depth/Record3DLiveCloud", [.record3D]),
        // 2D markers floating at true metric depths inside a live RGBD feed — the
        // metric (meters) sibling of DepthOcclusion, via a Camera3D.fromIntrinsics.
        example("3D/Depth/MetricDepthScene", [.record3D]),
        example("3D/Depth/DepthLiftedPose", [.vision, .record3D]),
        // The Ollin iPhone capture app's live body pose drawn as an orbiting 3D
        // stick figure — the own-app sibling of Record3DLiveCloud.
        example("3D/Phone/PhoneBodyPose", [.phone]),
        // The Ollin capture app's live face mesh + blendshapes, orbited as a point
        // cloud with expression bars — the front-camera sibling of PhoneBodyPose.
        example("3D/Phone/PhoneFace", [.phone]),
        // The Ollin capture app's live rear-LiDAR RGBD cloud — the depth sibling of
        // PhoneBodyPose and PhoneFace.
        example("3D/Phone/PhoneDepthCloud", [.phone]),
        // Sweep the phone around a room and fuse every depth frame, by its camera
        // pose, into one accumulated world cloud — the fusion sibling of PhoneDepthCloud.
        example("3D/Phone/PhoneWorldScan", [.phone]),
        // The phone's on-device person segmentation lifted onto a live backdrop —
        // the rear-camera Segment-mode sibling of the depth/pose/face examples.
        example("3D/Phone/PhoneSegmentation", [.phone]),
        example("Motion/Breathing"),
        example("Motion/SineSweep"),
        example("Motion/Easing"),
        example("Motion/EasingGallery"),
        example("Motion/Smoothing"),
        example("Motion/Timeline"),
        example("Motion/Orbits"),
        example("Motion/Linkage"),
        example("Motion/Petals"),
        example("Live/Parameters"),
        example("Motion/Trail"),
        example("Motion/Steering"),
        example("Motion/PerfectLoop"),
        example("Motion/Epicycles", resources: [.copy("whale.svg")]),
        example("Motion/Morphing"),
        example("Motion/Lissajous"),
        example("Motion/Harmonograph"),
        example("Motion/Springs"),
        example("Motion/InverseKinematics"),
        example("Motion/DoublePendulum"),
        example("Motion/NBody"),
        example("Color/ColorWaves"),
        example("Color/HSBWheel"),
        example("Color/Mixing"),
        example("Color/Gradients"),
        example("Color/Harmonies"),
        example("Color/Swatchbook"),
        example("Color/Palettes"),
        example("Color/PaletteFile", resources: [.copy("palettes.csv"), .copy("sunset.hex")]),
        example("Color/PaletteFromImage"),
        example("Color/Dithering"),
        example("Color/PrintSeparation"),
        example("Color/Colormaps"),
        example("Motion/FlowField"),
        example("Motion/EllipseField"),
        example("Motion/Attractor"),
        example("Motion/Myriad"),
        example("Motion/RectField"),
        example("Motion/Spokes"),
        example("Motion/Star"),
        example("Motion/Polygons"),
        example("Motion/ArcField"),
        example("Motion/ArcModes"),
        example("Randomness/Gaussian"),
        example("Randomness/Ring"),
        example("Randomness/Walk"),
        example("Randomness/Variations"),
        example("Patterns/CliffordAttractor"),
        example("Patterns/DotGrid"),
        example("Patterns/Grid"),
        example("Patterns/Phyllotaxis"),
        example("Input/RepelGrid"),
        example("Input/Keys"),
        example("Patterns/WarpGrid"),
        example("Patterns/EnergyGrid"),
        example("Randomness/NoiseField"),
        example("Randomness/RandomBand"),
        example("Randomness/NoiseWave"),
        example("Motion/Triangles"),
        example("Patterns/LifeQuilt"),
        example("Shapes/Markers"),
        example("Shapes/NamedPolygons"),
        example("Shapes/ShapeMenagerie"),
        example("Shapes/Primitives"),
        example("Shapes/Booleans"),
        example("Shapes/Clipping"),
        example("Shapes/InkRibbon"),
        example("Shapes/RubberBand"),
        example("Shapes/CornerCutting"),
        example("Shapes/SVGImport", resources: [.copy("rocket.svg")]),
        example("Patterns/Topography"),
        example("Patterns/RidgeLines"),
        example("Patterns/Voronoi"),
        example("Patterns/BlueNoise"),
        example("Patterns/LowDiscrepancy"),
        example("Patterns/Stippling"),
        example("Patterns/LevyFlight"),
        example("Patterns/SelfAvoidingWalk"),
        example("Patterns/Kaleidoscope"),
        example("Patterns/Truchet"),
        example("Patterns/CirclePacking"),
        example("Patterns/LSystem"),
        example("Patterns/DifferentialGrowth"),
        example("Patterns/WaveFunctionCollapse"),
        example("Patterns/ElementaryCA"),
        example("Patterns/Turmites"),
        example("Patterns/ShapePacking"),
        example("Patterns/Streamlines"),
        example("Patterns/Spirograph"),
        example("Patterns/Roses"),
        example("Patterns/Flocking"),
        example("Patterns/Venation"),
        example("Patterns/Dendrite"),
        example("Patterns/HexGrid"),
        example("Patterns/TriangleGrid"),
        example("Patterns/Subdivision"),
        example("Patterns/Maze"),
        example("Patterns/Apollonian"),
        example("Shapes/HollowShapes"),
        example("Shapes/StrokeAlignment"),
        example("Shapes/StrokeJoinsAndCaps"),
        example("Motion/Mandala"),
        example("Text/HelloText"),
        example("Text/TextVolume"),
        // The font lives beside the sketch (the per-example asset convention)
        // and loads at runtime through the Playdate `.fnt` loader.
        example("Text/PlaydateFont", resources: [.copy("MarbleMadness.fnt")]),
        example("Text/OutlineText"),
        example("Text/GlyphWave"),
        example("Text/TextOnPath"),
        example("Text/TextBox"),
        example("Text/VariableFont"),
        example("Text/StrokeText"),
        example("Text/TextMetrics"),
        example("Text/GlyphContours"),
        example("Text/PointShimmer"),
        example("Text/JitterType"),
        example("Images/GlyphMosaic"),
        example("Images/PixelField"),
        example("Images/PixelSort"),
        example("Images/SingleLine"),
        example("Images/SlitScan"),
        example("Audio/Spectrum", [.audio]),
        example("Audio/Microphone", [.audio]),
        // The bundled clip the sketch loads via Bundle.module (a launch path
        // overrides it). CC BY-SA, provenance in THIRD-PARTY-NOTICES.md.
        example("Audio/FilePlayer", [.audio], resources: [.copy("fandanguito.m4a")]),
        // Integration tier — OSC, and (later) MIDI/Syphon. Self-contained: the
        // sketch sends OSC to itself on loopback and visualizes what it receives,
        // so it needs no external app to run.
        example("Integration/OSCLoopback", [.osc]),
        // Listens for OSC and prints/draws every message — point a phone or any
        // OSC source at this Mac to discover what its controls send.
        example("Integration/OSCMonitor", [.osc]),
        // Self-contained: a virtual-source output sends animated MIDI to itself and
        // the input draws it back, so it runs with no hardware (like OSCLoopback).
        example("Integration/MIDILoopback", [.midi]),
        // Listens to every MIDI source and prints/draws what arrives — connect a
        // controller and discover what each knob/pad sends just by touching it.
        example("Integration/MIDIMonitor", [.midi]),
        // Self-contained: an internal timer sends MIDI clock to itself and a
        // TempoClock locks the visuals to it; point real gear at the Mac and the
        // same sketch follows that instead.
        example("Integration/TempoSync", [.midi]),
        // Self-contained: publishes its own frames as a Syphon source and
        // subscribes to them, so the feedback inset is the round-trip (like
        // OSCLoopback). Open Syphon's Simple Client to see it cross-app.
        example("Integration/SyphonLoopback", [.syphon]),
        // Subscribes to any external Syphon source (openFrameworks, Resolume, …)
        // and draws it letterboxed — the "see what's out there" viewer.
        example("Integration/SyphonViewer", [.syphon]),
        // Publishes its frames to the Ollin Camera virtual camera, so any
        // webcam app (Photo Booth, Zoom, a browser) reads the sketch as a live
        // camera; the canvas shows the connection state. Needs the Ollin
        // Camera extension installed (Apps/OllinCameraApp).
        example("Integration/VirtualCamera", [.camera]),
        // Physics — a Verlet world stepped each frame. Packing is a field of
        // colliding discs; Blobs are spring-built soft bodies that squish.
        example("Physics/Packing", [.physics]),
        example("Physics/Blobs", [.physics]),
        example("Physics/Stack", [.physics]),
        example("Physics/Tumble", [.physics]),
        example("Physics/Chain", [.physics]),
        // Video — plays a bundled clip (or a path passed on launch) as a live
        // image. The clip is the example's own asset (CC BY-SA, provenance in
        // THIRD-PARTY-NOTICES.md), per the per-example asset convention.
        example("Video/VideoPlayback", [.video], resources: [.copy("voladores.mp4")]),
        // The video's soundtrack analyzed live: a Soundtrack taps the playing
        // clip's audio (the core AudioTapSource seam) and the sketch draws its
        // bands and beats over the footage. Its clip pairs the voladores
        // footage with the fandanguito violin recording as the soundtrack
        // (both CC BY-SA; provenance in THIRD-PARTY-NOTICES.md).
        example("Video/SoundReactive", [.video, .audio], resources: [.copy("voladores-fandanguito.mp4")]),
        // Vision — the Mac's camera plus Apple Vision perception. WebcamFeed draws
        // the live feed; FaceTracking overlays detected faces and landmarks. Both
        // need a camera and grant camera permission on first run.
        example("Vision/WebcamFeed", [.vision]),
        example("Vision/FaceTracking", [.vision]),
        // The camera transformed so the face stays locked level and centered —
        // the room moves, not the head.
        example("Vision/FaceAlign", [.vision]),
        // Traces the camera's edges into vector contours (Shapes); self-contained,
        // falling back to a generated pattern when there's no camera.
        example("Vision/ContourTrace", [.vision]),
        // Hand skeletons (21 joints, up to two hands) drawn over the live feed.
        example("Vision/HandTracking", [.vision]),
        // A person's 2D pose drawn as a stick figure over the live feed.
        example("Vision/BodyPose", [.vision]),
        // The 3D pose: the skeleton in meters, overlaid on the feed and re-drawn
        // from the side — a view no camera is at.
        example("Vision/BodyPose3D", [.vision]),
        // People lifted off the background and composited over a drawn gradient
        // (background replacement; the matte doubles as the drop shadow).
        example("Vision/PersonSegmentation", [.vision]),
        // The salient subject lifted into a spotlight: dimmed frame, full-color
        // cutout, matte halo.
        example("Vision/SubjectLift", [.vision]),
        // Rectangular shapes (paper, screens, cards) highlighted as quads.
        example("Vision/RectangleScan", [.vision]),
        // Barcodes / QR codes outlined and their payload printed.
        example("Vision/BarcodeReader", [.vision]),
        // OCR — text read from the feed, each line boxed and printed.
        example("Vision/TextScan", [.vision]),
        // Object tracking — click to lock onto a patch and follow it across frames.
        example("Vision/ObjectTracking", [.vision]),
        // Optical flow — the camera's motion as a field of arrows, with dust
        // particles riding it.
        example("Vision/OpticalFlow", [.vision]),
        // Image classification — what the camera sees, named live as animated
        // label bars.
        example("Vision/SceneLabels", [.vision]),
        // Saliency — where the eye goes, as a warm heat-map glow over the feed
        // with the salient regions boxed and a marker gliding to the hottest spot.
        example("Vision/EyeCatcher", [.vision]),
        // A custom Core ML model (monocular depth) over the live feed — the
        // depth map sampled into a relief of disks. The model weights download
        // via Scripts/fetch-models.sh (never committed).
        example("Vision/DepthRelief", [.vision]),
        // Object detection (YOLOv3-tiny) — labeled boxes over the live feed.
        // The model weights download via Scripts/fetch-models.sh (never
        // committed).
        example("Vision/ObjectDetection", [.vision]),
        // Semantic segmentation (DeepLabV3) — every pixel painted by class.
        // The model weights download via Scripts/fetch-models.sh (never
        // committed).
        example("Vision/PaintByClass", [.vision]),
        // A model reading the sketch's own pixels — draw a digit with the
        // mouse, MNIST classifies it; no camera at all. The model weights
        // download via Scripts/fetch-models.sh (never committed).
        example("Vision/DigitReader", [.vision]),
        // The camera through a Create ML style-transfer model you train
        // yourself (no download — the model is the user's own work).
        example("Vision/StyleMirror", [.vision]),
        // Trajectory detection — ballistic arcs found in a synthetic feed (a
        // custom FrameSource the example conforms itself).
        example("Vision/TrajectoryTracking", [.vision]),
        // Vision over recorded footage — contours traced from a playing video
        // (the frame-source seam: a tracker attached to a VideoPlayer the way
        // it attaches to a Camera). Bundles the same CC BY-SA clip as
        // VideoPlayback; provenance in THIRD-PARTY-NOTICES.md.
        example("Vision/VideoTrace", [.vision, .video], resources: [.copy("voladores.mp4")]),
        // Recreations — sketches recreating past computer artists, namespaced by
        // artist (see Examples/Recreations/README.md).
        example("Recreations/VeraMolnar/Interruptions"),
        example("Recreations/VeraMolnar/DesOrdres"),
        example("Recreations/BridgetRiley/Fragment3"),
        example("Recreations/BridgetRiley/Current"),
        example("Recreations/OsamuSato/Totem"),
        example("Recreations/OsamuSato/Alphabet"),
        // Render-correctness snapshot tests: render small deterministic sketches
        // off-screen (the `--export` path) and diff them against committed
        // reference PNGs in `References/`. Regenerate the references with
        // `OLLIN_RECORD_SNAPSHOTS=1 swift test`. Skips when no Metal device.
        .testTarget(
            name: "OllinTests",
            dependencies: ["Ollin", "COllinShaders"],
            resources: [.copy("References")]
        ),
        // DSP correctness for the audio analyzer: feed synthesized signals and
        // check amplitude and the spectrum peak bin. GPU-independent, so it runs
        // in CI alongside the rest of the GPU-free tests.
        .testTarget(
            name: "OllinAudioTests",
            dependencies: ["Ollin", "OllinAudio"]
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
        // Vision correctness: the normalized↔canvas coordinate mapping (pure, runs
        // everywhere) plus a soft-skipping still-image face detection (renders a
        // simple synthetic image and tolerates a no-detection result, so it never
        // fails CI but verifies the path end-to-end when the model is present).
        // OllinVideo is here for the frame-source seam's end-to-end test: a
        // tracker running over a playing VideoPlayer.
        .testTarget(
            name: "OllinVisionTests",
            dependencies: ["Ollin", "OllinVision", "OllinVideo"]
        ),
        // Syphon correctness: a directory smoke test (always on) plus a
        // Metal-gated in-process publish→discover→receive loopback that
        // soft-skips if the announcement doesn't surface (Mach-restricted
        // sandbox). Uses the vendored CSyphon to stand up the publisher.
        .testTarget(
            name: "OllinSyphonTests",
            dependencies: ["Ollin", "OllinSyphon", "CSyphon"]
        ),
        // Virtual-camera publish client: the connect failure path (always on),
        // the GPU letterbox pass (Metal-gated), and a soft-gated end-to-end
        // push that runs for real where the Ollin Camera extension is installed.
        .testTarget(
            name: "OllinCameraTests",
            dependencies: ["Ollin", "OllinCamera"]
        ),
        // Video correctness: writes a tiny clip with AVAssetWriter, then checks
        // metadata loading and CPU frame snapshots; the GPU texture path is
        // Metal-gated. Soft-skips where the headless environment can't encode
        // or decode, so it never fails CI for environmental reasons.
        .testTarget(
            name: "OllinVideoTests",
            dependencies: ["Ollin", "OllinVideo"]
        ),
        // Record3D decode correctness: synthesizes a tiny `.r3d` in memory (a ZIP
        // of metadata + one JPEG + one LZFSE depth/confidence buffer) and checks
        // the ZIP read, metadata/intrinsics parse, depth round-trip, depth-grid
        // derivation, and the unprojection into a point cloud. GPU-free, so it
        // runs in CI with no committed binary asset.
        .testTarget(
            name: "OllinRecord3DTests",
            dependencies: ["Ollin", "OllinRecord3D", "OllinUSBMux"]
        ),
        // Phone sensor-stream wire format: encode/decode round-trips for the motion
        // and body-pose messages (GPU-free, CI-safe), plus a live-gated test that
        // pulls a frame off a connected phone running the capture app and soft-skips
        // without one (the Record3D pattern).
        .testTarget(
            name: "OllinPhoneTests",
            dependencies: ["Ollin", "OllinPhone", "OllinUSBMux"]
        ),
    ],
    // The whole package builds in the Swift 6 language mode, so data-race safety
    // is enforced as errors everywhere — framework, hosts, and example sketches.
    swiftLanguageModes: [.v6],
    // Vendored Clipper2 (External/CClipper2) is C++17; this only affects how
    // C++ sources compile, nothing about the Swift side.
    cxxLanguageStandard: .cxx17
)
