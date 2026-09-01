import CoreGraphics
import Foundation
import ImageIO
import Metal
@testable import Ollin
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
/// A passing snapshot also reports how close it came: a reference above
/// `driftWarningFraction` of the tolerance prints a line naming itself and
/// writes the same actual / reference / diff triple a failure does, so a
/// change that moves the render a little is visible in the run that makes it
/// rather than years later, when something unrelated finally tips it past the
/// bar. See `warnIfDrifting`.
///
/// **Recording references.** Set `OLLIN_RECORD_SNAPSHOTS=1` and run the tests
/// to (re)write the reference PNGs into `Tests/OllinTests/References/` from the
/// current render, then commit them. Set it to a *name* instead (any value other
/// than `0`/`1`, matched as a case-insensitive substring) to record only the
/// snapshots whose name matches while every other case still compares: adding
/// one snapshot rewrites nothing else, so there is nothing to `git restore`
/// afterwards. `0` or an empty value means compare mode, so a
/// stale exported variable can't record by accident. Record on a known-good
/// build, since the references are the source of truth thereafter, and only
/// once the reason they moved is understood: the metric is a mean, so it hides
/// a large local difference behind a small average, and "the tests still pass"
/// is not by itself evidence that nothing changed. The write goes to the source
/// tree while the compare path reads the built bundle, so the recording run
/// itself verifies nothing; the next `swift test` does.
enum Snapshot {

    /// Mean per-channel difference (0…255) allowed before a snapshot is a
    /// regression. Comfortably above cross-GPU AA jitter, well below any
    /// structural change.
    static let tolerance = 2.0

    /// The fraction of `tolerance` a reference may drift to before the run says
    /// so out loud (see the drift warning below).
    static let driftWarningFraction = 0.25

    /// Whether a Metal device exists — gates the tests so they skip (rather than
    /// fail) on a machine or CI runner without a usable GPU.
    static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    /// Whether the default device can ray-trace from the render stages, the gate for
    /// ray-traced point shadows + reflections. RT-only snapshots use it so they skip
    /// (rather than diverge) on a non-ray-tracing GPU / CI runner.
    /// `OLLIN_NO_RAY_TRACING=1` answers false here too, so a run that forces the
    /// rasterized fallbacks (to exercise the point caster's cube on a machine that would
    /// otherwise trace) skips the snapshots whose references were recorded traced,
    /// instead of failing them.
    static var hasRaytracing: Bool {
        guard ProcessInfo.processInfo.environment["OLLIN_NO_RAY_TRACING"] != "1" else { return false }
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return device.supportsRaytracing && device.supportsRaytracingFromRender
    }

    /// Whether the default device can be driven through a mesh pipeline, the gate
    /// for anything that draws a strand field. A paravirtualized GPU builds the
    /// pipeline and then has no object-stage binding to call, which throws an
    /// Objective-C exception rather than failing, so a test that renders one there
    /// does not fail: it kills the whole process and every other test with it.
    /// `OLLIN_NO_MESH_SHADERS=1` answers false here too.
    static var hasMeshShaders: Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return MetalRenderer.meshShadersAvailable(on: device)
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

    /// What `OLLIN_RECORD_SNAPSHOTS` asks of the case named `name`: `1` records
    /// everything, `0`/empty/unset records nothing, and any other value records
    /// only the names it matches as a case-insensitive substring.
    private static func shouldRecord(_ name: String) -> Bool {
        guard let value = ProcessInfo.processInfo.environment["OLLIN_RECORD_SNAPSHOTS"],
              !value.isEmpty, value != "0" else { return false }
        if value == "1" { return true }
        return name.localizedCaseInsensitiveContains(value)
    }

    /// Render `sketch` at `frame` and return its mean per-channel difference
    /// (0…255) from the reference named `name`. In record mode it writes the
    /// reference instead and returns `0`. Throws on a render or load failure.
    @MainActor
    static func meanDifference(of sketch: Sketch, against name: String, frame: Int = 0) throws -> Double {
        guard let actual = OllinApp.image(of: sketch, frame: frame) else { throw Failure.renderFailed }

        if shouldRecord(name) {
            try writeReference(actual, named: name)
            print("Ollin: recorded reference '\(name)' into the source tree; "
                  + "the next test run compares against it.")
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

        // A divergence, or a drift worth a look, drops the actual frame, the
        // reference it missed, and an amplified difference image somewhere
        // inspectable together. The drift warning says "find the cause", and
        // the triple is where finding it starts.
        if mean >= tolerance * driftWarningFraction {
            try? writeComparisonArtifacts(actual: a, reference: r, named: name)
        }
        warnIfDrifting(mean, named: name)
        return mean
    }

    /// Say so when a reference is passing but on its way to failing.
    ///
    /// A passing snapshot reports nothing about *how* passing it was, and the
    /// metric is a mean, which averages a local difference away: a reference
    /// once sat at 93% of the tolerance, with a quarter of its pixels differing
    /// by up to 230 levels, and passed every run for five hundred commits. The
    /// point of this line is that the drift shows up while it is still small,
    /// in the run that introduces it, rather than as a mystery on the day
    /// something unrelated finally tips it over.
    ///
    /// It never fails a test. A warning means "find out why, then either fix it
    /// or re-record deliberately", and re-recording without understanding the
    /// cause is exactly the thing to avoid.
    private static func warnIfDrifting(_ mean: Double, named name: String) {
        let warnAt = tolerance * driftWarningFraction
        guard mean >= warnAt else { return }
        if drifting.isEmpty { atexit { Snapshot.summarizeDrift() } }
        drifting.append(name)
        let percent = Int((mean / tolerance * 100).rounded())
        print(String(format: "Ollin: snapshot '%@' is drifting: mean %.3f is %d%% of the %.1f tolerance. "
                     + "Find the cause before re-recording.", name, mean, percent, tolerance))
    }

    /// Per-case drift warnings scroll past inside a long run, so every name that
    /// warned is re-listed once at process exit, under the test summary where it
    /// gets read. Mutated only from the main-actor test path and read at exit
    /// after every test has finished, which is what makes the unguarded static
    /// safe.
    nonisolated(unsafe) private static var drifting: [String] = []

    private static func summarizeDrift() {
        guard !drifting.isEmpty else { return }
        print("Ollin: \(drifting.count) snapshot reference\(drifting.count == 1 ? " is" : "s are")"
              + " drifting this run: \(drifting.joined(separator: ", "))."
              + " Find the causes before re-recording.")
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

    /// Write the comparison triple: `<name>.png` (the actual frame),
    /// `<name>.reference.png`, and `<name>.diff.png`, where the diff holds the
    /// per-channel absolute difference amplified 8x so a near-tolerance
    /// divergence is visible at a glance instead of reading as black.
    private static func writeComparisonArtifacts(actual a: (bytes: [UInt8], width: Int, height: Int),
                                                 reference r: (bytes: [UInt8], width: Int, height: Int),
                                                 named name: String) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ollin-snapshot-failures")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var diff = [UInt8](repeating: 255, count: a.bytes.count)
        for i in a.bytes.indices where i % 4 != 3 {
            diff[i] = UInt8(min(255, abs(Int(a.bytes[i]) - Int(r.bytes[i])) * 8))
        }

        try writePNG(image(from: a.bytes, width: a.width, height: a.height),
                     to: dir.appendingPathComponent("\(name).png"))
        try writePNG(image(from: r.bytes, width: r.width, height: r.height),
                     to: dir.appendingPathComponent("\(name).reference.png"))
        try writePNG(image(from: diff, width: a.width, height: a.height),
                     to: dir.appendingPathComponent("\(name).diff.png"))
        print("Ollin: wrote snapshot '\(name)' actual, reference, and 8x diff to \(dir.path)/")
    }

    /// Wrap a tightly-packed RGBA8 buffer back into a `CGImage` for writing.
    private static func image(from bytes: [UInt8], width: Int, height: Int) -> CGImage {
        let data = Data(bytes)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.renderFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw Failure.renderFailed }
    }
}
