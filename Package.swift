// swift-tools-version: 6.0
import PackageDescription

// Ollin — a motion-first creative coding framework for Swift + Metal.
//
// One product: the `Ollin` library you `import Ollin` in your sketches.
// Runnable sketches are a package of their own, in `Examples/`. Run one with
// `cd Examples && swift run Example-Basic-HelloCircle`, or from here with
// `swift run --package-path Examples Example-Basic-HelloCircle`. The note
// beside the test targets below says why they are not declared here.
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
    case dmx = "OllinDMX"
    case midi = "OllinMIDI"
    case physics = "OllinPhysics"
    case vision = "OllinVision"
    case video = "OllinVideo"
    case syphon = "OllinSyphon"
    case camera = "OllinCamera"
    case record3D = "OllinRecord3D"
    case phone = "OllinPhone"
    case screen = "OllinScreen"
    case controller = "OllinController"

    var dependency: Target.Dependency { .byName(name: rawValue) }
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
        // DMX lighting as a satellite library: `import OllinDMX` to drive stage
        // lights and dimmers from `draw()` over Art-Net or sACN (ANSI E1.31),
        // and to let a lighting console drive a sketch. Both wire formats are
        // implemented from their published specs over Network.framework (UDP).
        // Kept out of `Ollin` so the drawing core stays free of networking.
        .library(name: "OllinDMX", targets: ["OllinDMX"]),
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
        // Screen and window capture as a satellite library: `import OllinScreen`
        // to take any window or display on the Mac as a live texture-backed
        // frame source, drawn with `drawImage` and analyzed by the vision
        // trackers like a camera. Built on ScreenCaptureKit; kept out of `Ollin`
        // so the drawing core stays free of it, and so the screen-recording
        // permission is something a sketch opts into rather than inherits.
        .library(name: "OllinScreen", targets: ["OllinScreen"]),
        // Game controllers as a satellite library: `import OllinController` to
        // read sticks, triggers, buttons, motion and a touchpad in `draw()`.
        // Built on GameController; a satellite rather than core input because
        // a controller arrives from a system service rather than through the
        // view, so unlike the mouse and keyboard it needs no AppKit/UIKit
        // seam, and the core stays free of the framework.
        .library(name: "OllinController", targets: ["OllinController"]),
        // The shared CPU/GPU struct header as an importable module. A sketch
        // driving the raw `SpatialHash` builds `OllinParticle` buffers itself and
        // needs the declarations, which is why the compute examples `import
        // COllinShaders`; a product is what lets a sketch outside this package
        // (the Examples package among them) reach it at all.
        .library(name: "COllinShaders", targets: ["COllinShaders"]),
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
        // The project generator's model: the kinds of project it can make, the
        // ready-made templates, the capabilities each one wires in, and the files
        // they turn into. Depends on nothing at all, not even Ollin, because it
        // only ever produces text; that keeps it quick to build and quick to test,
        // and lets both faces of the generator share one implementation.
        .target(
            name: "OllinProjects"
        ),
        // The generator's command line, behind `ollin new`. Making a project is
        // one command, and `--list` says what can be made.
        .executableTarget(
            name: "OllinNew",
            dependencies: ["OllinProjects"]
        ),
        // The generator's window. Shows each starting point by *running* it, so
        // what you pick is what you get; it compiles a template through the same
        // loader the gallery uses, hence the satellite links and -export_dynamic
        // that every sketch-loading host needs.
        .executableTarget(
            name: "OllinProjectGenerator",
            dependencies: ["Ollin", "OllinRuntime", "OllinProjects"] + Satellite.allCases.map(\.dependency),
            path: "Sources/OllinProjectGenerator",
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
        // Vendored MikkTSpace (Morten S. Mikkelsen's tangent-space generator),
        // the standard the glTF 2.0 spec names for computing vertex tangents
        // when a normal-mapped model authors none, and the basis normal-map
        // bakers target, so generated tangents match baked textures. Bundled
        // third-party C source under its zlib-style per-file notice; see
        // External/CMikkTSpace/README.md and the repo-root
        // THIRD-PARTY-NOTICES.md. Wrapped behind Ollin's own API; the C symbols
        // are not part of Ollin's public surface.
        .target(
            name: "CMikkTSpace",
            path: "External/CMikkTSpace",
            exclude: ["LICENSE.txt", "README.md"],
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
        // Vendored Jolt Physics (Jorrit Rouwe's multi-core 3D rigid-body
        // engine, C++17), the solver behind OllinPhysics' 3D `World3D`/`Body3D`
        // API. Bundled third-party C++ source under its own MIT license; see
        // External/CJolt/README.md and the repo-root THIRD-PARTY-NOTICES.md.
        // Wrapped behind Ollin's own API: Swift imports only the C bridge in
        // include/ (no C++ interop), so the `JPH` symbols stay off Ollin's
        // public surface. The upstream Jolt/ subtree is preserved so its
        // `#include <Jolt/...>` directives resolve via the `.` header search
        // path; the GPU compute backends, HLSL shaders, and debug renderer are
        // present on disk but excluded from the build (their `JPH_USE_*` and
        // `JPH_DEBUG_RENDERER` gates stay off).
        .target(
            name: "CJolt",
            path: "External/CJolt",
            exclude: [
                "LICENSE", "README.md",
                "Jolt/Jolt.cmake", "Jolt/Jolt.natvis",
                "Jolt/Physics/Collision/Shape/TaperedCapsuleShape.gliffy",
                "Jolt/Shaders", "Jolt/Renderer",
                "Jolt/Compute/MTL", "Jolt/Compute/DX12", "Jolt/Compute/VK",
                "Jolt/Compute/CPU",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath(".")
            ],
            linkerSettings: [
                .linkedLibrary("c++")
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
            dependencies: ["Ollin"],
            // The small sampled instrument, generated by
            // Scripts/make-sample-instrument.swift rather than sourced, so the
            // framework carries no third-party audio. Copied rather than
            // processed: the loader opens the .sfz and the .wav files beside
            // it by name, exactly as it opens a library a sketch points at.
            resources: [.copy("Resources/Struck")]
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
        // DMX: drive lighting rigs over Art-Net and sACN (ANSI E1.31), both
        // wire formats written from their published specs (no vendored
        // library), via Network.framework UDP. A satellite (like OllinOSC) so
        // the drawing core stays free of networking; sketches opt in with
        // `import OllinDMX`. Depends on Ollin for `Color` and to bind an
        // incoming channel onto a `@Param` knob.
        .target(
            name: "OllinDMX",
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
            dependencies: ["Ollin", "CBox2D", "CJolt"]
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
        // Screen and window capture: a `ScreenCapture` over ScreenCaptureKit that
        // surfaces any window or display as a texture-backed `Image` (IOSurface
        // straight into a Metal texture, no CPU round-trip) and as a `FrameSource`
        // the vision trackers read. A satellite (like OllinVideo) so the drawing
        // core stays free of ScreenCaptureKit, and so the screen-recording consent
        // belongs to sketches that ask for it.
        .target(
            name: "OllinScreen",
            dependencies: ["Ollin"]
        ),
        // Game controllers: sticks, triggers, buttons, motion and a touchpad,
        // polled once a frame and read as plain values in `draw()`. A
        // satellite (like OllinScreen) so the drawing core stays free of
        // GameController, and because a controller reaches the process from a
        // system service rather than through the view, so it needs none of the
        // AppKit/UIKit plumbing the mouse and keyboard do.
        .target(
            name: "OllinController",
            dependencies: ["Ollin"]
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
            dependencies: ["CLibtess2", "CClipper2", "COllinShaders", "CHosekWilkie", "CMikkTSpace"],
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
                .copy("Renderer/ShaderGI.metal"),
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
                .copy("Resources/Environments"),
                .copy("Resources/LTC")
            ]
        ),
        // The runnable example sketches are their own package, in Examples/.
        // SwiftPM builds every target of the root package and offers no way to
        // scope a build to the tests and their dependencies, so declaring them
        // here links 350 sketch executables no test depends on into every
        // `swift test` (measured cold: 7m23s and 13 GB with them, 1m30s and
        // 1.7 GB without).
        // Nothing reaches an example through its target: the gallery and the live
        // hosts all compile a sketch from its source file. See Examples/Package.swift.
        // Render-correctness snapshot tests: render small deterministic sketches
        // off-screen (the `--export` path) and diff them against committed
        // reference PNGs in `References/`. Regenerate the references with
        // `OLLIN_RECORD_SNAPSHOTS=1 swift test`. Skips when no Metal device.
        .testTarget(
            name: "OllinTests",
            dependencies: ["Ollin", "COllinShaders", "OllinProjects"],
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
        // DMX correctness: golden-byte encodes against the published packet
        // layouts, decode round-trips, malformed input rejected without
        // trapping, the pure send cadence (change detection, repeats,
        // keep-alives), receiver priority/sequence/terminate rules over
        // crafted datagrams, plus an in-process UDP loopback. GPU-independent
        // (so it runs in CI) except the LED map's one end-to-end frame pin,
        // which is Metal-gated. Ollin is named for the geometry types the LED
        // map speaks (`Vector2`, `Rectangle`, `Color`).
        .testTarget(
            name: "OllinDMXTests",
            dependencies: ["Ollin", "OllinDMX"]
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
            dependencies: ["OllinPhysics", "CBox2D", "CJolt"]
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
        // Screen capture: the source-matching rules (pure, and the part a sketch
        // actually writes) plus the permission surface, then an end-to-end
        // capture that soft-skips where the screen-recording permission is off,
        // so it never fails CI for a consent the machine can't grant itself.
        .testTarget(
            name: "OllinScreenTests",
            dependencies: ["Ollin", "OllinScreen"]
        ),
        // Controller reading correctness. A synthetic `GCController` is a real
        // controller object the system never lists, so the tests inject one
        // through the hub's source seam and drive the shipped read path with
        // no hardware attached.
        .testTarget(
            name: "OllinControllerTests",
            dependencies: ["Ollin", "OllinController"]
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
        // The project generator: what each kind and template emits, and that the
        // emitted thing actually builds. The build check is the load-bearing one,
        // since a generated sketch that does not compile is worse than none, and
        // it runs headlessly with no GPU.
        .testTarget(
            name: "OllinProjectsTests",
            dependencies: ["OllinProjects"]
        ),
    ],
    // The whole package builds in the Swift 6 language mode, so data-race safety
    // is enforced as errors everywhere — framework, hosts, and example sketches.
    swiftLanguageModes: [.v6],
    // Vendored Clipper2 (External/CClipper2) is C++17; this only affects how
    // C++ sources compile, nothing about the Swift side.
    cxxLanguageStandard: .cxx17
)
