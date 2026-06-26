import CoreGraphics
import Foundation
import ImageIO
import Metal
import Ollin
import UniformTypeIdentifiers

/// Render-correctness snapshot testing: render a sketch off-screen (the same
/// headless path as `--export`, via `OllinApp.image(of:)`) and compare its
/// pixels against a committed reference image. Compile-testing proves an example
/// builds; this proves it still renders the same.
///
/// The metric is the mean per-channel absolute difference over every pixel, on a
/// 0…255 scale. A real regression — a wrong color, a missing or shifted shape —
/// moves it by tens to hundreds; sub-pixel anti-aliasing differences between
/// GPUs touch only shape edges and barely move it. So a small tolerance catches
/// regressions while staying robust across machines (test sketches keep large
/// flat regions to hold the edge fraction down).
///
/// **Recording references.** Set `OLLIN_RECORD_SNAPSHOTS=1` and run the tests
/// to (re)write the reference PNGs into `Tests/OllinTests/References/` from the
/// current render, then commit them. Do this on a known-good build, since the
/// references are the source of truth thereafter.
enum Snapshot {

    /// Mean per-channel difference (0…255) allowed before a snapshot is a
    /// regression. Comfortably above cross-GPU AA jitter, well below any
    /// structural change.
    static let tolerance = 2.0

    /// Whether a Metal device exists — gates the tests so they skip (rather than
    /// fail) on a machine or CI runner without a usable GPU.
    static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    /// Whether the default device can ray-trace from the render stages, the gate for
    /// ray-traced point shadows + reflections. RT-only snapshots use it so they skip
    /// (rather than diverge) on a non-ray-tracing GPU / CI runner.
    static var hasRaytracing: Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return device.supportsRaytracing && device.supportsRaytracingFromRender
    }

    enum Failure: Error, CustomStringConvertible {
        case renderFailed
        case missingReference(String)
        case sizeMismatch(actual: (Int, Int), reference: (Int, Int))

        var description: String {
            switch self {
            case .renderFailed:
                return "Ollin: the sketch failed to render off-screen (no Metal device?)"
            case .missingReference(let name):
                return "Ollin: no reference image '\(name)'. Record it first with OLLIN_RECORD_SNAPSHOTS=1."
            case .sizeMismatch(let a, let r):
                return "Ollin: rendered \(a.0)×\(a.1) but reference is \(r.0)×\(r.1)."
            }
        }
    }

    /// Render `sketch` at `frame` and return its mean per-channel difference
    /// (0…255) from the reference named `name`. In record mode it writes the
    /// reference instead and returns `0`. Throws on a render or load failure.
    @MainActor
    static func meanDifference(of sketch: Sketch, against name: String, frame: Int = 0) throws -> Double {
        guard let actual = OllinApp.image(of: sketch, frame: frame) else { throw Failure.renderFailed }

        if ProcessInfo.processInfo.environment["OLLIN_RECORD_SNAPSHOTS"] != nil {
            try writeReference(actual, named: name)
            return 0
        }

        guard let reference = loadReference(named: name) else { throw Failure.missingReference(name) }
        guard let a = rgba(of: actual), let r = rgba(of: reference) else { throw Failure.renderFailed }
        guard a.width == r.width, a.height == r.height else {
            throw Failure.sizeMismatch(actual: (a.width, a.height), reference: (r.width, r.height))
        }

        var total = 0
        for i in a.bytes.indices { total += abs(Int(a.bytes[i]) - Int(r.bytes[i])) }
        let mean = Double(total) / Double(a.bytes.count)

        // On a real divergence, drop the actual frame somewhere inspectable.
        if mean >= tolerance { try? writeActual(actual, named: name) }
        return mean
    }

    // MARK: Pixels

    /// Draw `image` into a tightly-packed RGBA8 buffer so two images compare
    /// byte for byte regardless of how each `CGImage` stores its samples.
    private static func rgba(of image: CGImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let ptr = ctx.data else { return nil }
        let buffer = UnsafeRawBufferPointer(start: ptr, count: w * h * 4)
        return (Array(buffer), w, h)
    }

    // MARK: Reference files

    /// Reference PNGs live beside this file (so record mode can rewrite the
    /// source), and are also copied into the test bundle as a resource for the
    /// compare path.
    private static var referencesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("References", isDirectory: true)
    }

    private static func loadReference(named name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "References")
                ?? Bundle.module.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image
    }

    private static func writeReference(_ image: CGImage, named name: String) throws {
        try FileManager.default.createDirectory(at: referencesDirectory, withIntermediateDirectories: true)
        try writePNG(image, to: referencesDirectory.appendingPathComponent("\(name).png"))
    }

    private static func writeActual(_ image: CGImage, named name: String) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ollin-snapshot-failures")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png")
        try writePNG(image, to: url)
        print("Ollin: snapshot '\(name)' diverged; wrote the actual frame to \(url.path)")
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.renderFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw Failure.renderFailed }
    }
}
