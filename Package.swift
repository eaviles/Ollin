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
            // The satellite libraries (OllinAudio/OllinOSC/OllinMIDI/OllinPhysics)
            // are linked (not used by the host) so a hot-swapped sketch that
            // `import`s them resolves its symbols against this process at load,
            // the same way it resolves Ollin's.
            dependencies: ["Ollin", "OllinRuntime", "OllinAudio", "OllinOSC", "OllinMIDI", "OllinPhysics", "OllinVision", "OllinVideo", "OllinSyphon", "OllinCamera", "OllinRecord3D", "OllinPhone"],
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
            dependencies: ["Ollin", "OllinRuntime", "OllinAudio", "OllinOSC", "OllinMIDI", "OllinPhysics", "OllinVision", "OllinVideo", "OllinSyphon", "OllinCamera", "OllinRecord3D", "OllinPhone"],
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
                .copy("Renderer/ShaderCore.metal"),
                .copy("Renderer/ShaderShapes.metal"),
                .copy("Renderer/ShaderCombinator.metal"),
                .copy("Renderer/Shader3D.metal"),
                .copy("Renderer/ShaderRaymarch.metal"),
                .copy("Renderer/ShaderEffects.metal"),
                .copy("Renderer/ShaderIBL.metal"),
                .copy("Renderer/OllinShaderTypes.h"),
                // The MSL compute prelude (hash/noise/curl/disc), spliced into
                // user compute-kernel source at runtime like OllinShaderTypes.h.
                .copy("Renderer/OllinCompute.h"),
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
        // Examples — one runnable sketch per executable target, grouped into
        // category folders (openFrameworks-style). Each example is a single
        // `@main` Sketch file; run one with e.g. `swift run Example-Basic-HelloCircle`.
        // Hand-written for now; generate these stanzas once the set grows
        // (see CLAUDE.md: don't hand-maintain dozens of target blocks).
        .executableTarget(
            name: "Example-Basic-HelloCircle",
            dependencies: ["Ollin"],
            path: "Examples/Basic/HelloCircle"
        ),
        .executableTarget(
            name: "Example-Basic-Guides",
            dependencies: ["Ollin"],
            path: "Examples/Basic/Guides"
        ),
        .executableTarget(
            name: "Example-Export-Capture",
            dependencies: ["Ollin"],
            path: "Examples/Export/Capture"
        ),
        .executableTarget(
            name: "Example-Export-VectorExport",
            dependencies: ["Ollin"],
            path: "Examples/Export/VectorExport"
        ),
        .executableTarget(
            name: "Example-Export-Hatching",
            dependencies: ["Ollin"],
            path: "Examples/Export/Hatching"
        ),
        .executableTarget(
            name: "Example-Rendering-Blending",
            dependencies: ["Ollin"],
            path: "Examples/Rendering/Blending"
        ),
        .executableTarget(
            name: "Example-Effects-Bloom",
            dependencies: ["Ollin"],
            path: "Examples/Effects/Bloom"
        ),
        .executableTarget(
            name: "Example-Shapes-Combinators",
            dependencies: ["Ollin"],
            path: "Examples/Shapes/Combinators"
        ),
        .executableTarget(
            name: "Example-Shapes-CombinatorsGradient",
            dependencies: ["Ollin"],
            path: "Examples/Shapes/CombinatorsGradient"
        ),
        .executableTarget(
            name: "Example-Shapes-CombinatorsStretch",
            dependencies: ["Ollin"],
            path: "Examples/Shapes/CombinatorsStretch"
        ),
        .executableTarget(
            name: "Example-3D-RaymarchedReceiveShadow",
            dependencies: ["Ollin"],
            path: "Examples/3D/RaymarchedReceiveShadow"
        ),
        .executableTarget(
            name: "Example-3D-RaymarchedPointCast",
            dependencies: ["Ollin"],
            path: "Examples/3D/RaymarchedPointCast"
        ),
        .executableTarget(
            name: "Example-3D-RaymarchedStretch",
            dependencies: ["Ollin"],
            path: "Examples/3D/RaymarchedStretch"
        ),
        .executableTarget(
            name: "Example-Effects-Feedback",
            dependencies: ["Ollin"],
            path: "Examples/Effects/Feedback"
        ),
        .executableTarget(
            name: "Example-Effects-Compose",
            dependencies: ["Ollin"],
            path: "Examples/Effects/Compose"
        ),
        .executableTarget(
            name: "Example-Effects-Aside",
            dependencies: ["Ollin"],
            path: "Examples/Effects/Aside"
        ),
        .executableTarget(
            name: "Example-Effects-Defocus",
            dependencies: ["Ollin"],
            path: "Examples/Effects/Defocus"
        ),
        .executableTarget(
            name: "Example-Rendering-Accumulation",
            dependencies: ["Ollin"],
            path: "Examples/Rendering/Accumulation"
        ),
        .executableTarget(
            name: "Example-Effects-ColorFilters",
            dependencies: ["Ollin"],
            path: "Examples/Effects/ColorFilters"
        ),
        .executableTarget(
            name: "Example-Effects-BlurFilters",
            dependencies: ["Ollin"],
            path: "Examples/Effects/BlurFilters"
        ),
        .executableTarget(
            name: "Example-Effects-StylizeFilters",
            dependencies: ["Ollin"],
            path: "Examples/Effects/StylizeFilters"
        ),
        .executableTarget(
            name: "Example-Effects-RetroFilters",
            dependencies: ["Ollin"],
            path: "Examples/Effects/RetroFilters"
        ),
        .executableTarget(
            name: "Example-Effects-Distortion",
            dependencies: ["Ollin"],
            path: "Examples/Effects/Distortion"
        ),
        .executableTarget(
            name: "Example-Simulation-GrayScott",
            dependencies: ["Ollin"],
            path: "Examples/Simulation/GrayScott"
        ),
        .executableTarget(
            name: "Example-Simulation-GameOfLife",
            dependencies: ["Ollin"],
            path: "Examples/Simulation/GameOfLife"
        ),
        .executableTarget(
            name: "Example-Simulation-Fluid",
            dependencies: ["Ollin"],
            path: "Examples/Simulation/Fluid"
        ),
        .executableTarget(
            name: "Example-Effects-Patterns",
            dependencies: ["Ollin"],
            path: "Examples/Effects/Patterns"
        ),
        .executableTarget(
            name: "Example-Rendering-ToneMapping",
            dependencies: ["Ollin"],
            path: "Examples/Rendering/ToneMapping"
        ),
        .executableTarget(
            name: "Example-Rendering-DepthOfField",
            dependencies: ["Ollin"],
            path: "Examples/Rendering/DepthOfField"
        ),
        .executableTarget(
            name: "Example-Compute-CurlField",
            dependencies: ["Ollin"],
            path: "Examples/Compute/CurlField"
        ),
        .executableTarget(
            name: "Example-Compute-ReactionDiffusion",
            dependencies: ["Ollin"],
            path: "Examples/Compute/ReactionDiffusion",
            // The kernels live in their own .metal file (highlighted, editor-checked);
            // .copy ships the source for Ollin's runtime compiler to read + splice.
            resources: [.copy("Kernels.metal")]
        ),
        .executableTarget(
            name: "Example-3D-PointCloud",
            dependencies: ["Ollin"],
            path: "Examples/3D/PointCloud"
        ),
        .executableTarget(
            name: "Example-3D-Transforms",
            dependencies: ["Ollin"],
            path: "Examples/3D/Transforms"
        ),
        .executableTarget(
            name: "Example-3D-Solids",
            dependencies: ["Ollin"],
            path: "Examples/3D/Solids"
        ),
        .executableTarget(
            name: "Example-3D-RaymarchedSDF",
            dependencies: ["Ollin"],
            path: "Examples/3D/RaymarchedSDF"
        ),
        .executableTarget(
            name: "Example-3D-RaymarchedShapes",
            dependencies: ["Ollin"],
            path: "Examples/3D/RaymarchedShapes"
        ),
        .executableTarget(
            name: "Example-3D-RaymarchedSculpt",
            dependencies: ["Ollin"],
            path: "Examples/3D/RaymarchedSculpt"
        ),
        .executableTarget(
            name: "Example-3D-RaymarchedDomain",
            dependencies: ["Ollin"],
            path: "Examples/3D/RaymarchedDomain"
        ),
        .executableTarget(
            name: "Example-3D-RaymarchedRadial",
            dependencies: ["Ollin"],
            path: "Examples/3D/RaymarchedRadial"
        ),
        .executableTarget(
            name: "Example-3D-RaymarchedPlane",
            dependencies: ["Ollin"],
            path: "Examples/3D/RaymarchedPlane"
        ),
        .executableTarget(
            name: "Example-3D-RaymarchedCastShadow",
            dependencies: ["Ollin"],
            path: "Examples/3D/RaymarchedCastShadow"
        ),
        .executableTarget(
            name: "Example-3D-RaymarchedGradient",
            dependencies: ["Ollin"],
            path: "Examples/3D/RaymarchedGradient"
        ),
        .executableTarget(
            name: "Example-3D-RaymarchedShadow",
            dependencies: ["Ollin"],
            path: "Examples/3D/RaymarchedShadow"
        ),
        .executableTarget(
            name: "Example-3D-SceneDefocus",
            dependencies: ["Ollin"],
            path: "Examples/3D/SceneDefocus"
        ),
        .executableTarget(
            name: "Example-3D-AmbientOcclusion",
            dependencies: ["Ollin"],
            path: "Examples/3D/AmbientOcclusion"
        ),
        .executableTarget(
            name: "Example-3D-TexturedMesh",
            dependencies: ["Ollin"],
            path: "Examples/3D/TexturedMesh"
        ),
        .executableTarget(
            name: "Example-3D-Wireframe",
            dependencies: ["Ollin"],
            path: "Examples/3D/Wireframe"
        ),
        .executableTarget(
            name: "Example-3D-LoadedMesh",
            dependencies: ["Ollin"],
            path: "Examples/3D/LoadedMesh",
            resources: [.copy("model.gltf"), .copy("model.obj")]
        ),
        .executableTarget(
            name: "Example-3D-ShapeFactory",
            dependencies: ["Ollin"],
            path: "Examples/3D/ShapeFactory"
        ),
        .executableTarget(
            name: "Example-3D-Lighting",
            dependencies: ["Ollin"],
            path: "Examples/3D/Lighting"
        ),
        .executableTarget(
            name: "Example-3D-LightingPresets",
            dependencies: ["Ollin"],
            path: "Examples/3D/LightingPresets"
        ),
        .executableTarget(
            name: "Example-3D-Materials",
            dependencies: ["Ollin"],
            path: "Examples/3D/Materials"
        ),
        .executableTarget(
            name: "Example-3D-PhysicalMaterials",
            dependencies: ["Ollin"],
            path: "Examples/3D/PhysicalMaterials"
        ),
        .executableTarget(
            name: "Example-3D-ImageBasedLighting",
            dependencies: ["Ollin"],
            path: "Examples/3D/ImageBasedLighting"
        ),
        .executableTarget(
            name: "Example-3D-EnvironmentGallery",
            dependencies: ["Ollin"],
            path: "Examples/3D/EnvironmentGallery"
        ),
        .executableTarget(
            name: "Example-3D-ProceduralSky",
            dependencies: ["Ollin"],
            path: "Examples/3D/ProceduralSky"
        ),
        .executableTarget(
            name: "Example-3D-HighResEnvironment",
            dependencies: ["Ollin"],
            path: "Examples/3D/HighResEnvironment"
        ),
        .executableTarget(
            name: "Example-3D-EnvironmentURL",
            dependencies: ["Ollin"],
            path: "Examples/3D/EnvironmentURL"
        ),
        .executableTarget(
            name: "Example-3D-Matcap",
            dependencies: ["Ollin"],
            path: "Examples/3D/Matcap"
        ),
        .executableTarget(
            name: "Example-3D-Shadows",
            dependencies: ["Ollin"],
            path: "Examples/3D/Shadows"
        ),
        .executableTarget(
            name: "Example-3D-SpotShadow",
            dependencies: ["Ollin"],
            path: "Examples/3D/SpotShadow"
        ),
        .executableTarget(
            name: "Example-3D-PointShadow",
            dependencies: ["Ollin"],
            path: "Examples/3D/PointShadow"
        ),
        .executableTarget(
            name: "Example-3D-DepthCompositing",
            dependencies: ["Ollin"],
            path: "Examples/3D/DepthCompositing"
        ),
        .executableTarget(
            name: "Example-3D-DepthCloud",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/3D/DepthCloud"
        ),
        .executableTarget(
            name: "Example-3D-DepthOcclusion",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/3D/DepthOcclusion"
        ),
        .executableTarget(
            name: "Example-3D-Record3DCloud",
            dependencies: ["Ollin", "OllinRecord3D"],
            path: "Examples/3D/Record3DCloud"
        ),
        .executableTarget(
            name: "Example-3D-Record3DLiveCloud",
            dependencies: ["Ollin", "OllinRecord3D"],
            path: "Examples/3D/Record3DLiveCloud"
        ),
        // 2D markers floating at true metric depths inside a live RGBD feed — the
        // metric (meters) sibling of DepthOcclusion, via a Camera3D.fromIntrinsics.
        .executableTarget(
            name: "Example-3D-MetricDepthScene",
            dependencies: ["Ollin", "OllinRecord3D"],
            path: "Examples/3D/MetricDepthScene"
        ),
        .executableTarget(
            name: "Example-3D-DepthLiftedPose",
            dependencies: ["Ollin", "OllinVision", "OllinRecord3D"],
            path: "Examples/3D/DepthLiftedPose"
        ),
        // The Ollin iPhone capture app's live body pose drawn as an orbiting 3D
        // stick figure — the own-app sibling of Record3DLiveCloud.
        .executableTarget(
            name: "Example-3D-PhoneBodyPose",
            dependencies: ["Ollin", "OllinPhone"],
            path: "Examples/3D/PhoneBodyPose"
        ),
        // The Ollin capture app's live face mesh + blendshapes, orbited as a point
        // cloud with expression bars — the front-camera sibling of PhoneBodyPose.
        .executableTarget(
            name: "Example-3D-PhoneFace",
            dependencies: ["Ollin", "OllinPhone"],
            path: "Examples/3D/PhoneFace"
        ),
        // The Ollin capture app's live rear-LiDAR RGBD cloud — the depth sibling of
        // PhoneBodyPose and PhoneFace.
        .executableTarget(
            name: "Example-3D-PhoneDepthCloud",
            dependencies: ["Ollin", "OllinPhone"],
            path: "Examples/3D/PhoneDepthCloud"
        ),
        // Sweep the phone around a room and fuse every depth frame, by its camera
        // pose, into one accumulated world cloud — the fusion sibling of PhoneDepthCloud.
        .executableTarget(
            name: "Example-3D-PhoneWorldScan",
            dependencies: ["Ollin", "OllinPhone"],
            path: "Examples/3D/PhoneWorldScan"
        ),
        // The phone's on-device person segmentation lifted onto a live backdrop —
        // the rear-camera Segment-mode sibling of the depth/pose/face examples.
        .executableTarget(
            name: "Example-3D-PhoneSegmentation",
            dependencies: ["Ollin", "OllinPhone"],
            path: "Examples/3D/PhoneSegmentation"
        ),
        .executableTarget(
            name: "Example-Motion-Breathing",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Breathing"
        ),
        .executableTarget(
            name: "Example-Motion-SineSweep",
            dependencies: ["Ollin"],
            path: "Examples/Motion/SineSweep"
        ),
        .executableTarget(
            name: "Example-Motion-Easing",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Easing"
        ),
        .executableTarget(
            name: "Example-Motion-EasingGallery",
            dependencies: ["Ollin"],
            path: "Examples/Motion/EasingGallery"
        ),
        .executableTarget(
            name: "Example-Motion-Smoothing",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Smoothing"
        ),
        .executableTarget(
            name: "Example-Motion-Orbits",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Orbits"
        ),
        .executableTarget(
            name: "Example-Motion-Linkage",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Linkage"
        ),
        .executableTarget(
            name: "Example-Motion-Petals",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Petals"
        ),
        .executableTarget(
            name: "Example-Live-Parameters",
            dependencies: ["Ollin"],
            path: "Examples/Live/Parameters"
        ),
        .executableTarget(
            name: "Example-Motion-Trail",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Trail"
        ),
        .executableTarget(
            name: "Example-Color-ColorWaves",
            dependencies: ["Ollin"],
            path: "Examples/Color/ColorWaves"
        ),
        .executableTarget(
            name: "Example-Color-HSBWheel",
            dependencies: ["Ollin"],
            path: "Examples/Color/HSBWheel"
        ),
        .executableTarget(
            name: "Example-Color-Mixing",
            dependencies: ["Ollin"],
            path: "Examples/Color/Mixing"
        ),
        .executableTarget(
            name: "Example-Color-Gradients",
            dependencies: ["Ollin"],
            path: "Examples/Color/Gradients"
        ),
        .executableTarget(
            name: "Example-Color-Harmonies",
            dependencies: ["Ollin"],
            path: "Examples/Color/Harmonies"
        ),
        .executableTarget(
            name: "Example-Color-Swatchbook",
            dependencies: ["Ollin"],
            path: "Examples/Color/Swatchbook"
        ),
        .executableTarget(
            name: "Example-Color-Palettes",
            dependencies: ["Ollin"],
            path: "Examples/Color/Palettes"
        ),
        .executableTarget(
            name: "Example-Color-Colormaps",
            dependencies: ["Ollin"],
            path: "Examples/Color/Colormaps"
        ),
        .executableTarget(
            name: "Example-Motion-FlowField",
            dependencies: ["Ollin"],
            path: "Examples/Motion/FlowField"
        ),
        .executableTarget(
            name: "Example-Motion-EllipseField",
            dependencies: ["Ollin"],
            path: "Examples/Motion/EllipseField"
        ),
        .executableTarget(
            name: "Example-Motion-Attractor",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Attractor"
        ),
        .executableTarget(
            name: "Example-Motion-Myriad",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Myriad"
        ),
        .executableTarget(
            name: "Example-Motion-RectField",
            dependencies: ["Ollin"],
            path: "Examples/Motion/RectField"
        ),
        .executableTarget(
            name: "Example-Motion-Spokes",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Spokes"
        ),
        .executableTarget(
            name: "Example-Motion-Star",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Star"
        ),
        .executableTarget(
            name: "Example-Motion-Polygons",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Polygons"
        ),
        .executableTarget(
            name: "Example-Motion-ArcField",
            dependencies: ["Ollin"],
            path: "Examples/Motion/ArcField"
        ),
        .executableTarget(
            name: "Example-Motion-ArcModes",
            dependencies: ["Ollin"],
            path: "Examples/Motion/ArcModes"
        ),
        .executableTarget(
            name: "Example-Randomness-Gaussian",
            dependencies: ["Ollin"],
            path: "Examples/Randomness/Gaussian"
        ),
        .executableTarget(
            name: "Example-Randomness-Ring",
            dependencies: ["Ollin"],
            path: "Examples/Randomness/Ring"
        ),
        .executableTarget(
            name: "Example-Patterns-DotGrid",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/DotGrid"
        ),
        .executableTarget(
            name: "Example-Patterns-Phyllotaxis",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/Phyllotaxis"
        ),
        .executableTarget(
            name: "Example-Input-RepelGrid",
            dependencies: ["Ollin"],
            path: "Examples/Input/RepelGrid"
        ),
        .executableTarget(
            name: "Example-Input-Keys",
            dependencies: ["Ollin"],
            path: "Examples/Input/Keys"
        ),
        .executableTarget(
            name: "Example-Patterns-WarpGrid",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/WarpGrid"
        ),
        .executableTarget(
            name: "Example-Patterns-EnergyGrid",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/EnergyGrid"
        ),
        .executableTarget(
            name: "Example-Randomness-NoiseField",
            dependencies: ["Ollin"],
            path: "Examples/Randomness/NoiseField"
        ),
        .executableTarget(
            name: "Example-Randomness-RandomBand",
            dependencies: ["Ollin"],
            path: "Examples/Randomness/RandomBand"
        ),
        .executableTarget(
            name: "Example-Randomness-NoiseWave",
            dependencies: ["Ollin"],
            path: "Examples/Randomness/NoiseWave"
        ),
        .executableTarget(
            name: "Example-Motion-Triangles",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Triangles"
        ),
        .executableTarget(
            name: "Example-Patterns-LifeQuilt",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/LifeQuilt"
        ),
        .executableTarget(
            name: "Example-Shapes-Markers",
            dependencies: ["Ollin"],
            path: "Examples/Shapes/Markers"
        ),
        .executableTarget(
            name: "Example-Shapes-NamedPolygons",
            dependencies: ["Ollin"],
            path: "Examples/Shapes/NamedPolygons"
        ),
        .executableTarget(
            name: "Example-Shapes-ShapeMenagerie",
            dependencies: ["Ollin"],
            path: "Examples/Shapes/ShapeMenagerie"
        ),
        .executableTarget(
            name: "Example-Shapes-Primitives",
            dependencies: ["Ollin"],
            path: "Examples/Shapes/Primitives"
        ),
        .executableTarget(
            name: "Example-Shapes-Booleans",
            dependencies: ["Ollin"],
            path: "Examples/Shapes/Booleans"
        ),
        .executableTarget(
            name: "Example-Patterns-Topography",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/Topography"
        ),
        .executableTarget(
            name: "Example-Patterns-Voronoi",
            dependencies: ["Ollin"],
            path: "Examples/Patterns/Voronoi"
        ),
        .executableTarget(
            name: "Example-Shapes-HollowShapes",
            dependencies: ["Ollin"],
            path: "Examples/Shapes/HollowShapes"
        ),
        .executableTarget(
            name: "Example-Shapes-StrokeAlignment",
            dependencies: ["Ollin"],
            path: "Examples/Shapes/StrokeAlignment"
        ),
        .executableTarget(
            name: "Example-Shapes-StrokeJoinsAndCaps",
            dependencies: ["Ollin"],
            path: "Examples/Shapes/StrokeJoinsAndCaps"
        ),
        .executableTarget(
            name: "Example-Motion-Mandala",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Mandala"
        ),
        .executableTarget(
            name: "Example-Text-HelloText",
            dependencies: ["Ollin"],
            path: "Examples/Text/HelloText"
        ),
        .executableTarget(
            name: "Example-Text-TextVolume",
            dependencies: ["Ollin"],
            path: "Examples/Text/TextVolume"
        ),
        .executableTarget(
            name: "Example-Text-PlaydateFont",
            dependencies: ["Ollin"],
            path: "Examples/Text/PlaydateFont",
            // The font lives beside the sketch (the per-example asset convention)
            // and loads at runtime through the Playdate `.fnt` loader.
            resources: [.copy("MarbleMadness.fnt")]
        ),
        .executableTarget(
            name: "Example-Text-OutlineText",
            dependencies: ["Ollin"],
            path: "Examples/Text/OutlineText"
        ),
        .executableTarget(
            name: "Example-Text-GlyphWave",
            dependencies: ["Ollin"],
            path: "Examples/Text/GlyphWave"
        ),
        .executableTarget(
            name: "Example-Text-TextOnPath",
            dependencies: ["Ollin"],
            path: "Examples/Text/TextOnPath"
        ),
        .executableTarget(
            name: "Example-Text-TextBox",
            dependencies: ["Ollin"],
            path: "Examples/Text/TextBox"
        ),
        .executableTarget(
            name: "Example-Text-VariableFont",
            dependencies: ["Ollin"],
            path: "Examples/Text/VariableFont"
        ),
        .executableTarget(
            name: "Example-Text-StrokeText",
            dependencies: ["Ollin"],
            path: "Examples/Text/StrokeText"
        ),
        .executableTarget(
            name: "Example-Text-TextMetrics",
            dependencies: ["Ollin"],
            path: "Examples/Text/TextMetrics"
        ),
        .executableTarget(
            name: "Example-Text-GlyphContours",
            dependencies: ["Ollin"],
            path: "Examples/Text/GlyphContours"
        ),
        .executableTarget(
            name: "Example-Text-PointShimmer",
            dependencies: ["Ollin"],
            path: "Examples/Text/PointShimmer"
        ),
        .executableTarget(
            name: "Example-Text-JitterType",
            dependencies: ["Ollin"],
            path: "Examples/Text/JitterType"
        ),
        .executableTarget(
            name: "Example-Images-PixelField",
            dependencies: ["Ollin"],
            path: "Examples/Images/PixelField"
        ),
        .executableTarget(
            name: "Example-Audio-Spectrum",
            dependencies: ["Ollin", "OllinAudio"],
            path: "Examples/Audio/Spectrum"
        ),
        .executableTarget(
            name: "Example-Audio-Microphone",
            dependencies: ["Ollin", "OllinAudio"],
            path: "Examples/Audio/Microphone"
        ),
        .executableTarget(
            name: "Example-Audio-FilePlayer",
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
            name: "Example-Integration-OSCLoopback",
            dependencies: ["Ollin", "OllinOSC"],
            path: "Examples/Integration/OSCLoopback"
        ),
        // Listens for OSC and prints/draws every message — point a phone or any
        // OSC source at this Mac to discover what its controls send.
        .executableTarget(
            name: "Example-Integration-OSCMonitor",
            dependencies: ["Ollin", "OllinOSC"],
            path: "Examples/Integration/OSCMonitor"
        ),
        // Self-contained: a virtual-source output sends animated MIDI to itself and
        // the input draws it back, so it runs with no hardware (like OSCLoopback).
        .executableTarget(
            name: "Example-Integration-MIDILoopback",
            dependencies: ["Ollin", "OllinMIDI"],
            path: "Examples/Integration/MIDILoopback"
        ),
        // Listens to every MIDI source and prints/draws what arrives — connect a
        // controller and discover what each knob/pad sends just by touching it.
        .executableTarget(
            name: "Example-Integration-MIDIMonitor",
            dependencies: ["Ollin", "OllinMIDI"],
            path: "Examples/Integration/MIDIMonitor"
        ),
        // Self-contained: publishes its own frames as a Syphon source and
        // subscribes to them, so the feedback inset is the round-trip (like
        // OSCLoopback). Open Syphon's Simple Client to see it cross-app.
        .executableTarget(
            name: "Example-Integration-SyphonLoopback",
            dependencies: ["Ollin", "OllinSyphon"],
            path: "Examples/Integration/SyphonLoopback"
        ),
        // Subscribes to any external Syphon source (openFrameworks, Resolume, …)
        // and draws it letterboxed — the "see what's out there" viewer.
        .executableTarget(
            name: "Example-Integration-SyphonViewer",
            dependencies: ["Ollin", "OllinSyphon"],
            path: "Examples/Integration/SyphonViewer"
        ),
        // Publishes its frames to the Ollin Camera virtual camera, so any
        // webcam app (Photo Booth, Zoom, a browser) reads the sketch as a live
        // camera; the canvas shows the connection state. Needs the Ollin
        // Camera extension installed (Apps/OllinCameraApp).
        .executableTarget(
            name: "Example-Integration-VirtualCamera",
            dependencies: ["Ollin", "OllinCamera"],
            path: "Examples/Integration/VirtualCamera"
        ),
        // Physics — a Verlet world stepped each frame. Packing is a field of
        // colliding discs; Blobs are spring-built soft bodies that squish.
        .executableTarget(
            name: "Example-Physics-Packing",
            dependencies: ["Ollin", "OllinPhysics"],
            path: "Examples/Physics/Packing"
        ),
        .executableTarget(
            name: "Example-Physics-Blobs",
            dependencies: ["Ollin", "OllinPhysics"],
            path: "Examples/Physics/Blobs"
        ),
        .executableTarget(
            name: "Example-Physics-Stack",
            dependencies: ["Ollin", "OllinPhysics"],
            path: "Examples/Physics/Stack"
        ),
        .executableTarget(
            name: "Example-Physics-Tumble",
            dependencies: ["Ollin", "OllinPhysics"],
            path: "Examples/Physics/Tumble"
        ),
        .executableTarget(
            name: "Example-Physics-Chain",
            dependencies: ["Ollin", "OllinPhysics"],
            path: "Examples/Physics/Chain"
        ),
        // Video — plays a bundled clip (or a path passed on launch) as a live
        // image. The clip is the example's own asset (CC BY-SA, provenance in
        // THIRD-PARTY-NOTICES.md), per the per-example asset convention.
        .executableTarget(
            name: "Example-Video-VideoPlayback",
            dependencies: ["Ollin", "OllinVideo"],
            path: "Examples/Video/VideoPlayback",
            resources: [.copy("voladores.mp4")]
        ),
        // Vision — the Mac's camera plus Apple Vision perception. WebcamFeed draws
        // the live feed; FaceTracking overlays detected faces and landmarks. Both
        // need a camera and grant camera permission on first run.
        .executableTarget(
            name: "Example-Vision-WebcamFeed",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/WebcamFeed"
        ),
        .executableTarget(
            name: "Example-Vision-FaceTracking",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/FaceTracking"
        ),
        // The camera transformed so the face stays locked level and centered —
        // the room moves, not the head.
        .executableTarget(
            name: "Example-Vision-FaceAlign",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/FaceAlign"
        ),
        // Traces the camera's edges into vector contours (Shapes); self-contained,
        // falling back to a generated pattern when there's no camera.
        .executableTarget(
            name: "Example-Vision-ContourTrace",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/ContourTrace"
        ),
        // Hand skeletons (21 joints, up to two hands) drawn over the live feed.
        .executableTarget(
            name: "Example-Vision-HandTracking",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/HandTracking"
        ),
        // A person's 2D pose drawn as a stick figure over the live feed.
        .executableTarget(
            name: "Example-Vision-BodyPose",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/BodyPose"
        ),
        // The 3D pose: the skeleton in meters, overlaid on the feed and re-drawn
        // from the side — a view no camera is at.
        .executableTarget(
            name: "Example-Vision-BodyPose3D",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/BodyPose3D"
        ),
        // People lifted off the background and composited over a drawn gradient
        // (background replacement; the matte doubles as the drop shadow).
        .executableTarget(
            name: "Example-Vision-PersonSegmentation",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/PersonSegmentation"
        ),
        // The salient subject lifted into a spotlight: dimmed frame, full-color
        // cutout, matte halo.
        .executableTarget(
            name: "Example-Vision-SubjectLift",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/SubjectLift"
        ),
        // Rectangular shapes (paper, screens, cards) highlighted as quads.
        .executableTarget(
            name: "Example-Vision-RectangleScan",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/RectangleScan"
        ),
        // Barcodes / QR codes outlined and their payload printed.
        .executableTarget(
            name: "Example-Vision-BarcodeReader",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/BarcodeReader"
        ),
        // OCR — text read from the feed, each line boxed and printed.
        .executableTarget(
            name: "Example-Vision-TextScan",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/TextScan"
        ),
        // Object tracking — click to lock onto a patch and follow it across frames.
        .executableTarget(
            name: "Example-Vision-ObjectTracking",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/ObjectTracking"
        ),
        // Optical flow — the camera's motion as a field of arrows, with dust
        // particles riding it.
        .executableTarget(
            name: "Example-Vision-OpticalFlow",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/OpticalFlow"
        ),
        // Image classification — what the camera sees, named live as animated
        // label bars.
        .executableTarget(
            name: "Example-Vision-SceneLabels",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/SceneLabels"
        ),
        // Saliency — where the eye goes, as a warm heat-map glow over the feed
        // with the salient regions boxed and a marker gliding to the hottest spot.
        .executableTarget(
            name: "Example-Vision-EyeCatcher",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/EyeCatcher"
        ),
        // A custom Core ML model (monocular depth) over the live feed — the
        // depth map sampled into a relief of disks. The model weights download
        // via Scripts/fetch-models.sh (never committed).
        .executableTarget(
            name: "Example-Vision-DepthRelief",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/DepthRelief"
        ),
        // Object detection (YOLOv3-tiny) — labeled boxes over the live feed.
        // The model weights download via Scripts/fetch-models.sh (never
        // committed).
        .executableTarget(
            name: "Example-Vision-ObjectDetection",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/ObjectDetection"
        ),
        // Semantic segmentation (DeepLabV3) — every pixel painted by class.
        // The model weights download via Scripts/fetch-models.sh (never
        // committed).
        .executableTarget(
            name: "Example-Vision-PaintByClass",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/PaintByClass"
        ),
        // A model reading the sketch's own pixels — draw a digit with the
        // mouse, MNIST classifies it; no camera at all. The model weights
        // download via Scripts/fetch-models.sh (never committed).
        .executableTarget(
            name: "Example-Vision-DigitReader",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/DigitReader"
        ),
        // The camera through a Create ML style-transfer model you train
        // yourself (no download — the model is the user's own work).
        .executableTarget(
            name: "Example-Vision-StyleMirror",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/StyleMirror"
        ),
        // Trajectory detection — ballistic arcs found in a synthetic feed (a
        // custom FrameSource the example conforms itself).
        .executableTarget(
            name: "Example-Vision-TrajectoryTracking",
            dependencies: ["Ollin", "OllinVision"],
            path: "Examples/Vision/TrajectoryTracking"
        ),
        // Vision over recorded footage — contours traced from a playing video
        // (the frame-source seam: a tracker attached to a VideoPlayer the way
        // it attaches to a Camera). Bundles the same CC BY-SA clip as
        // VideoPlayback; provenance in THIRD-PARTY-NOTICES.md.
        .executableTarget(
            name: "Example-Vision-VideoTrace",
            dependencies: ["Ollin", "OllinVision", "OllinVideo"],
            path: "Examples/Vision/VideoTrace",
            resources: [.copy("voladores.mp4")]
        ),
        // Recreations — sketches recreating past computer artists, namespaced by
        // artist (see Examples/Recreations/README.md).
        .executableTarget(
            name: "Example-Recreations-VeraMolnar-Interruptions",
            dependencies: ["Ollin"],
            path: "Examples/Recreations/VeraMolnar/Interruptions"
        ),
        .executableTarget(
            name: "Example-Recreations-VeraMolnar-DesOrdres",
            dependencies: ["Ollin"],
            path: "Examples/Recreations/VeraMolnar/DesOrdres"
        ),
        .executableTarget(
            name: "Example-Recreations-BridgetRiley-Fragment3",
            dependencies: ["Ollin"],
            path: "Examples/Recreations/BridgetRiley/Fragment3"
        ),
        .executableTarget(
            name: "Example-Recreations-BridgetRiley-Current",
            dependencies: ["Ollin"],
            path: "Examples/Recreations/BridgetRiley/Current"
        ),
        .executableTarget(
            name: "Example-Recreations-OsamuSato-Totem",
            dependencies: ["Ollin"],
            path: "Examples/Recreations/OsamuSato/Totem"
        ),
        .executableTarget(
            name: "Example-Recreations-OsamuSato-Alphabet",
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
