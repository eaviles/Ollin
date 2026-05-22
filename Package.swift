// swift-tools-version: 5.9
import PackageDescription

// Ollin — a motion-first creative coding framework for Swift + Metal.
//
// Two products:
//   • Ollin       — the library you `import Ollin` in your sketches.
//   • OllinSketch — an executable that boots a window and runs a Sketch.
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
        .executable(name: "OllinSketch", targets: ["OllinSketch"]),
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
        .executableTarget(
            name: "OllinSketch",
            dependencies: ["Ollin"]
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
    ]
)
