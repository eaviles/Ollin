import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
@testable import Ollin
import Testing
import VideoToolbox
import simd

/// Spatial video: the stereo pair a camera makes, and the file it goes into.
///
/// The geometry half is pure arithmetic and always runs. It is written as
/// projections rather than pictures because a stereo pair is a claim about
/// exactly one thing: where a point lands in each eye. A pixel comparison
/// would average that claim away, so the tests here project chosen points and
/// hold the two answers against each other, with a counterfactual each time
/// (a point at the convergence distance against one nearer, an eye against
/// its opposite, a lens against a wider one).
///
/// The file half needs a GPU and an encoder, so it is gated. What it checks is
/// not that the video looks right, which no test can say, but that the system
/// agrees it is spatial: the same reading Photos and Quick Look take.
@Suite
@MainActor
struct SpatialVideoTests {

    // MARK: Support

    /// Where a world point lands across the frame, in normalized device x
    /// (-1 at the left edge, +1 at the right).
    private func screenX(_ camera: Camera3D, _ point: Vector3, aspect: Double = 1) -> Double {
        let clip = camera.viewProjectionMatrix(aspect: aspect)
            * SIMD4<Float>(Float(point.x), Float(point.y), Float(point.z), 1)
        return Double(clip.x / clip.w)
    }

    private let looking = Camera3D.perspective(eye: Vector3(0, 0, 10), target: .zero,
                                               fieldOfView: .pi / 3)

    // MARK: The geometry

    @Test func theEyesAgreeAtTheConvergenceDistanceAndNowhereElse() {
        let pair = looking.stereoPair(StereoGeometry(interocular: 0.5, convergence: 10), aspect: 1)

        // The target is 10 away, which is the convergence distance, so it lands
        // in the same place in both eyes: on the screen plane.
        let atConvergence = screenX(pair.right, .zero) - screenX(pair.left, .zero)
        #expect(abs(atConvergence) < 1e-6)

        // Nearer and farther are the counterfactual, and they must disagree in
        // opposite directions: nearer comes out of the screen, farther sits behind it.
        let nearer = screenX(pair.right, Vector3(0, 0, 5)) - screenX(pair.left, Vector3(0, 0, 5))
        let farther = screenX(pair.right, Vector3(0, 0, -20)) - screenX(pair.left, Vector3(0, 0, -20))
        #expect(nearer < -0.01)
        #expect(farther > 0.01)
    }

    @Test func theEyesStepSidewaysAndKeepLookingParallel() {
        let pair = looking.stereoPair(StereoGeometry(interocular: 0.5, convergence: 10), aspect: 1)

        // Half the spacing each way along the camera's own right axis, which for
        // a camera up on +z looking back at the origin is world +x.
        #expect(abs(pair.left.eye.x + 0.25) < 1e-9)
        #expect(abs(pair.right.eye.x - 0.25) < 1e-9)
        #expect(abs(pair.left.eye.y) < 1e-9 && abs(pair.left.eye.z - 10) < 1e-9)

        // Parallel, not toed in: each eye's target moved with it, so the two
        // view directions are the same vector rather than crossing at the target.
        let leftLook = (pair.left.target - pair.left.eye).normalized
        let rightLook = (pair.right.target - pair.right.eye).normalized
        #expect((leftLook - rightLook).length < 1e-9)
    }

    @Test func anOrthographicPairShearsWhereAPerspectiveOneSlides() {
        let flat = Camera3D.orthographic(eye: Vector3(0, 0, 10), target: .zero, height: 8)
        let pair = flat.stereoPair(StereoGeometry(interocular: 0.5, convergence: 10), aspect: 1)

        // An orthographic camera moved sideways slides its whole picture and
        // shows no depth at all, so the convergence lean has to be a shear.
        // Same test as the perspective one: agree at the convergence distance,
        // disagree either side of it, in opposite directions.
        #expect(abs(screenX(pair.right, .zero) - screenX(pair.left, .zero)) < 1e-6)
        let nearer = screenX(pair.right, Vector3(0, 0, 5)) - screenX(pair.left, Vector3(0, 0, 5))
        let farther = screenX(pair.right, Vector3(0, 0, -5)) - screenX(pair.left, Vector3(0, 0, -5))
        #expect(nearer < -0.01)
        #expect(farther > 0.01)
        #expect(abs(nearer + farther) < 1e-6)   // and by the same amount, being linear in depth
    }

    @Test func aCameraThatIsNotOneOfAPairIsUntouched() {
        // The off switch, byte for byte: nothing about an ordinary camera's
        // projection changes because the stereo fields exist.
        let plain = looking.projectionMatrix(aspect: 1.5)
        let asked = looking.stereoEye(.left, interocular: 0, convergence: 10).projectionMatrix(aspect: 1.5)
        #expect(plain == asked)
        #expect(looking.stereoEye(.left, interocular: 0, convergence: 10) == looking)
    }

    @Test func theDerivedSpacingPutsTheFarBackgroundOnePercentOfTheFrameApart() {
        let (interocular, convergence) = StereoGeometry.automatic.resolved(for: looking, aspect: 1)
        #expect(abs(convergence - 10) < 1e-9)   // the camera's own target distance

        // The rule the derivation is written to: at infinity the eyes differ by
        // 1% of the frame width. Normalized device x spans 2 across the frame,
        // so that is 0.02.
        let pair = looking.stereoPair(.automatic, aspect: 1)
        let far = Vector3(0, 0, -1e7)
        let disparity = screenX(pair.right, far) - screenX(pair.left, far)
        #expect(abs(disparity - 0.02) < 1e-4)
        #expect(interocular > 0)
    }

    @Test func theDerivedSpacingFollowsTheLensAndTheDistance() {
        // A narrower lens magnifies whatever disparity there is, so holding the
        // same 1% of the frame means stepping the eyes closer together. Twice as
        // far away, on the other hand, wants them twice as far apart.
        let wide = Camera3D.perspective(eye: Vector3(0, 0, 10), target: .zero, fieldOfView: .pi / 2)
        let narrow = Camera3D.perspective(eye: Vector3(0, 0, 10), target: .zero, fieldOfView: .pi / 6)
        let far = Camera3D.perspective(eye: Vector3(0, 0, 20), target: .zero, fieldOfView: .pi / 3)
        let spacing = { (c: Camera3D) in StereoGeometry.automatic.resolved(for: c, aspect: 1).interocular }
        #expect(spacing(wide) > spacing(narrow))
        #expect(abs(spacing(far) / spacing(looking) - 2) < 1e-9)
    }

    @Test func aDeclaredNumberIsUsedAsGiven() {
        let asked = StereoGeometry(interocular: 0.42, convergence: 3.5)
        let (interocular, convergence) = asked.resolved(for: looking, aspect: 1)
        #expect(interocular == 0.42)
        #expect(convergence == 3.5)

        // And half of one still leaves the other derived.
        let onlyDistance = StereoGeometry(convergence: 4)
        let resolved = onlyDistance.resolved(for: looking, aspect: 1)
        #expect(resolved.convergence == 4)
        #expect(resolved.interocular > 0 && resolved.interocular != 0.42)
    }

    @Test func theFieldOfViewIsTheAngleTheShotFrames() {
        // A square frame under a 60 degree vertical lens is 60 degrees across too.
        let square = looking.horizontalFieldOfView(aspect: 1, convergence: 10)
        #expect(abs(square - .pi / 3) < 1e-6)

        // A wider frame under the same lens sees more of the world sideways.
        let wide = looking.horizontalFieldOfView(aspect: 16.0 / 9, convergence: 10)
        #expect(wide > square)
        #expect(abs(wide - 2 * atan(tan(Double.pi / 6) * 16.0 / 9)) < 1e-6)
    }

    // MARK: The file

    /// A sketch with something at three depths, so the two eyes have something
    /// to disagree about.
    private final class Depths: Sketch {
        override var canvasSize: CanvasSize { .square(256) }
        override func draw() {
            background(.black)
            camera(.perspective(eye: Vector3(0, 0, 10), target: .zero))
            directionalLight(.white, direction: Vector3(-1, -1, -1))
            for (index, z) in [-6.0, 0, 4].enumerated() {
                withState {
                    translate(Double(index - 1) * 2.5, 0, z)
                    fill(Color(hue: Double(index) / 3, saturation: 0.7, brightness: 1))
                    drawBox(size: 1.6)
                }
            }
        }
    }

    private func exportedClip(_ sketch: Sketch, frames: Int = 4,
                              stereo: StereoGeometry? = nil,
                              metersPerUnit: Double = 1) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-spatial-\(UUID().uuidString).mov")
        OllinApp.exportSpatialVideo(sketch, to: url.path, frames: frames, fps: 12,
                                    stereo: stereo, metersPerUnit: metersPerUnit)
        return url
    }

    /// What the system makes of the file, which is the reading that matters:
    /// the same one Photos and Quick Look take.
    private func playbackOptions(_ url: URL) async -> [AVAssetPlaybackConfigurationOption] {
        await AVAssetPlaybackAssistant(asset: AVURLAsset(url: url)).playbackConfigurationOptions
    }

    /// The spatial numbers the file carries, read back off its format description.
    private func spatialExtensions(_ url: URL) async throws -> [String: Any] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
              let description = try await track.load(.formatDescriptions).first else { return [:] }
        return CMFormatDescriptionGetExtensions(description) as? [String: Any] ?? [:]
    }

    @Test(.enabled(if: Snapshot.hasMetal && VTIsStereoMVHEVCEncodeSupported()))
    func theSystemReadsTheFileAsSpatialVideo() async throws {
        let url = exportedClip(Depths())
        defer { try? FileManager.default.removeItem(at: url) }
        let options = await playbackOptions(url)
        #expect(options.contains(.spatialVideo))
        #expect(options.contains(.stereoMultiviewVideo))
    }

    @Test(.enabled(if: Snapshot.hasMetal && VTIsStereoMVHEVCEncodeSupported()))
    func theFileCarriesTheShotItWasTakenWith() async throws {
        // A tenth of a unit between the eyes, and a unit is a hundredth of a
        // meter, so the baseline is a millimeter: a thousand micrometers.
        let url = exportedClip(Depths(), stereo: StereoGeometry(interocular: 0.1, convergence: 10),
                               metersPerUnit: 0.01)
        defer { try? FileManager.default.removeItem(at: url) }
        let extensions = try await spatialExtensions(url)

        let baseline = extensions[kCMFormatDescriptionExtension_StereoCameraBaseline as String] as? UInt32
        #expect(baseline == 1000)
        #expect(extensions[kCMFormatDescriptionExtension_HasLeftStereoEyeView as String] as? Bool == true)
        #expect(extensions[kCMFormatDescriptionExtension_HasRightStereoEyeView as String] as? Bool == true)
        #expect(extensions[kCMFormatDescriptionExtension_HorizontalDisparityAdjustment as String] as? Int32 == 0)

        // 60 degrees across a square frame, in thousandths of a degree.
        let fov = extensions[kCMFormatDescriptionExtension_HorizontalFieldOfView as String] as? UInt32
        #expect(fov != nil && abs(Int(fov!) - 60_000) < 100)
    }

    @Test(.enabled(if: Snapshot.hasMetal && VTIsStereoMVHEVCEncodeSupported()))
    func thePairInTheFileIsTwoDifferentPicturesAndWiderEyesDisagreeMore() async throws {
        // The two layers must actually hold two views, and the amount they
        // differ has to follow the one number that decides it: with the eyes
        // four times as far apart, everything off the convergence plane moves
        // four times as far. A pair that came out identical, or that ignored
        // the spacing, passes neither half.
        let near = exportedClip(Depths(), stereo: StereoGeometry(interocular: 0.1, convergence: 10))
        let wide = exportedClip(Depths(), stereo: StereoGeometry(interocular: 0.4, convergence: 10))
        defer {
            try? FileManager.default.removeItem(at: near)
            try? FileManager.default.removeItem(at: wide)
        }
        let narrowDifference = try difference(between: near)
        let wideDifference = try difference(between: wide)
        #expect(narrowDifference > 0)
        #expect(wideDifference > narrowDifference * 2)
    }

    /// How much the two eyes of the first frame disagree, as a mean absolute
    /// difference per pixel. Both layers are decoded from the one sample, which
    /// is how a multi-layer file is read.
    private func difference(between url: URL) throws -> Double {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        guard let track = reader.asset.tracks(withMediaType: .video).first else { return 0 }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            AVVideoDecompressionPropertiesKey: [
                kVTDecompressionPropertyKey_RequestedMVHEVCVideoLayerIDs as String: [0, 1],
            ],
        ])
        reader.add(output)
        reader.startReading()
        guard let sample = output.copyNextSampleBuffer(),
              let tagged = sample.taggedBuffers, tagged.count == 2 else { return 0 }
        let planes = tagged.compactMap { buffer -> [UInt8]? in
            guard case let .pixelBuffer(pixels) = buffer.buffer else { return nil }
            return luminance(of: pixels)
        }
        guard planes.count == 2, planes[0].count == planes[1].count, !planes[0].isEmpty else { return 0 }
        let total = zip(planes[0], planes[1]).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) }
        return total / Double(planes[0].count)
    }

    private func luminance(of pixels: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return [] }
        var out = [UInt8](repeating: 0, count: width * height)
        for y in 0 ..< height {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0 ..< width { out[y * width + x] = row[x * 4 + 1] }
        }
        return out
    }
}
