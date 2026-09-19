import CoreGraphics
import Foundation
import OllinWebGate
import Testing
@testable import Ollin

/// The `Shaders/BlackHole` example on the web page: its shader, the heaviest user
/// shader in the examples (the orbit integration, the disk's crossings, the
/// spectral sum for the color of heat, the star field on a cube), carried to
/// GLSL by the shader door and played in a browser against the Mac's frame.
@Suite
@MainActor
struct BlackHolePageTests {

    /// The example's shader at a small size, its camera drifting and the disk's
    /// clock running so the recorded parameters move from frame to frame.
    final class Lensed: Sketch {
        override var canvasSize: CanvasSize { .size(192, 108) }
        /// Degrees the camera stands above the disk.
        var elevation: Float = 7

        static let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // OllinTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // the repository
            .appendingPathComponent("Examples/Shaders/BlackHole")

        override func setup() {
            toneMap(.aces)
        }

        override func draw() {
            background(.black)
            guard let text = try? String(contentsOf: Self.folder.appendingPathComponent("blackhole.metal"),
                                         encoding: .utf8) else { return }
            let radians = Float.pi / 180
            let lens = Shader(text, params: [
                26, elevation * radians, Float(time) * 3 * radians, 38 * radians, 3, 14,
                4500, 1, 0.7, 0.8, Float(time * 8), 0.5,
                0, 1.5, .pi, -7 * radians,
                1,
            ], file: Self.folder.appendingPathComponent("Sketch.swift").path)
            drawImage(generate(lens).filtered(.bloom(threshold: 0.9, amount: 0.35, radius: 4)).image, 0, 0)
        }
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func thePagePlaysWhatTheMacDrew() async throws {
        let recording = try OllinApp.recordWebFrames(of: Lensed(), frames: 4, fps: 30)
        let page = try OllinApp.webPage(of: recording, form: .inline)
        let played = try await WebExportTests.pagePixels(page, frame: 2)
        let reference = try #require(OllinApp.image(of: Lensed(), frame: 2, fps: 30))
        let difference = try WebExportTests.meanDifference(played, reference)
        print("web page against the Mac: the black hole, frame 2, mean difference \(String(format: "%.3f", difference))")
        #expect(difference < Snapshot.tolerance, "mean difference \(difference)")

        // A comparison that cannot fail proves nothing: the same frame with the
        // camera two degrees higher must read as a different picture.
        let raised = Lensed()
        raised.elevation = 9
        let moved = try #require(OllinApp.image(of: raised, frame: 2, fps: 30))
        let apart = try WebExportTests.meanDifference(played, moved)
        #expect(apart > Snapshot.tolerance, "two degrees apart reads as \(apart)")
    }
}
