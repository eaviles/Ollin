// swift-tools-version: 5.9
import PackageDescription

// Ollin — a motion-first creative coding framework for Swift + Metal.
//
// Two products:
//   • Ollin       — the library you `import Ollin` in your sketches.
//   • OllinSketch — an executable that boots a window and runs a Sketch.
//
// The `.metal` shader in Sources/Ollin/Renderer is compiled by SwiftPM into a
// `default.metallib` inside the target's resource bundle. We load it at runtime
// via `Bundle.module` (see MetalRenderer.loadLibrary).
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
            name: "Ollin"
            // No explicit `resources:` entry is needed: SwiftPM detects the
            // `.metal` source automatically, compiles it, and synthesizes
            // `Bundle.module` so we can load the shader library at runtime.
        ),
        .executableTarget(
            name: "OllinSketch",
            dependencies: ["Ollin"]
        ),
    ]
)
