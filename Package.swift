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
        .macOS(.v14)
    ],
    products: [
        .library(name: "Ollin", targets: ["Ollin"]),
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
            dependencies: ["Ollin", "OllinRuntime"],
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
            dependencies: ["Ollin", "OllinRuntime"],
            path: "Sources/OllinExamples",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-export_dynamic"])
            ]
        ),
        .target(
            name: "Ollin",
            // Declaring the `.metal` file as a resource makes SwiftPM copy it
            // into the target's resource bundle and synthesize `Bundle.module`,
            // which MetalRenderer.loadLibrary uses to read and compile the shader
            // source at runtime. (`.process` copies the `.metal` as source; it
            // does not precompile a `default.metallib`.) Without this, the file
            // is "unhandled" and `Bundle.module` is never generated.
            resources: [
                .process("Renderer/Shaders.metal")
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
            name: "Example-Orbits",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Orbits"
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
            name: "Example-Myriad",
            dependencies: ["Ollin"],
            path: "Examples/Motion/Myriad"
        ),
        .executableTarget(
            name: "Example-ArcField",
            dependencies: ["Ollin"],
            path: "Examples/Motion/ArcField"
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
            name: "Example-RepelGrid",
            dependencies: ["Ollin"],
            path: "Examples/Input/RepelGrid"
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
    ],
    // The whole package builds in the Swift 6 language mode, so data-race safety
    // is enforced as errors everywhere — framework, hosts, and example sketches.
    swiftLanguageModes: [.v6]
)
