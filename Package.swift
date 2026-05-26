// swift-tools-version: 5.9
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
    ]
)
