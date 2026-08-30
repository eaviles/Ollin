import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
@testable import Ollin

/// Slow motion in an export: the sketch's own clock and the rate the file plays
/// at come apart, so the run covers more frames and takes longer to watch.
///
/// The value type's arithmetic runs anywhere; the export tests need a GPU and
/// are serialized with the other export suites because they share it.
@Suite(.serialized)
@MainActor
struct SlowMotionTests {

    /// A dot crossing a flat field, driven by `time` alone, so any two renders
    /// of the same moment must agree pixel for pixel however they were reached.
    final class MovingDot: Sketch {
        override var canvasSize: CanvasSize { .square(120) }

        override func draw() {
            background(.black)
            noStroke()
            fill(.white)
            drawCircle(width * (0.2 + 0.6 * time), height / 2, 18)
        }
    }

    // MARK: - The value itself

    @Test func aFactorOfOneIsNotSlowMotion() {
        #expect(!SlowMotion.drawn(1).isActive)
        #expect(!SlowMotion.drawn(0.5).isActive)   // clamped up to 1
        #expect(SlowMotion.drawn(0.5).factor == 1)
        #expect(SlowMotion.drawn(.nan).factor == 1)
        #expect(SlowMotion.drawn(4).isActive)
    }

    @Test func onlyTheDrawnFormStepsTheClockFiner() {
        #expect(SlowMotion.drawn(4).clockRate(playingAt: 30) == 120)
        // The made form draws at the file's own rate and fills the gaps after.
        #expect(SlowMotion.made(2).clockRate(playingAt: 30) == 30)
    }

    @Test func theMadeFormDrawsFewerFramesThanItWrites() {
        let made = SlowMotion.made(2)
        // Every gap takes one made frame, so n drawn frames carry 2n-1 written.
        #expect(made.writtenFrames(forDrawn: 5) == 9)
        #expect(made.drawnFrames(forWritten: 9) == 5)
        // The drawn form draws every frame it writes.
        #expect(SlowMotion.drawn(4).drawnFrames(forWritten: 9) == 9)
    }

    @Test func theNoteSaysWhatWasHandedOver() {
        // 48 frames of a 30 fps file is 1.6s of video, from 0.4s of sketch time.
        let drawn = SlowMotion.drawn(4).note(written: 48, fps: 30)
        #expect(drawn.contains("every frame drawn"))
        #expect(drawn.contains("0.4s"))
        #expect(drawn.contains("1.6s"))
        // The made form counts the frames nobody drew, which is the whole point
        // of saying anything at all.
        let made = SlowMotion.made(2).note(written: 9, fps: 30)
        #expect(made.contains("4 of the 9 frames were made by the GPU"))
    }

    // MARK: - The drawn export

    /// The written frames land on the finer clock: frame 4k of a 4x export is
    /// the sketch at frame 4k of a 4x clock, pixel for pixel.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aDrawnSlowExportRunsTheFinerClock() throws {
        let dir = ollinTempPath("ollin-slowmo-drawn")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        OllinApp.exportSequence(MovingDot(), to: dir, frames: 24, fps: 30,
                                slowMotion: .drawn(4))

        let files = try FileManager.default.contentsOfDirectory(atPath: dir).sorted()
        #expect(files.count == 24)

        // Three probes across the run, each against the same moment rendered on
        // its own through the still path at the finer rate.
        for k in [0, 7, 23] {
            let written = try image(at: dir, frame: k + 1)
            let alone = try #require(OllinApp.image(of: MovingDot(), frame: k, fps: 120))
            #expect(maxDifference(written, alone) == 0,
                    "written frame \(k) is not the sketch at frame \(k) of a 120 fps clock")
        }
    }

    /// The counterfactual that gives the test above its teeth: without the finer
    /// clock, frame 1 of the slow export would be the sketch at 1/30 s. It is at
    /// 1/120 s instead, and the dot has visibly not gone as far.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theFramesBetweenAreNotTheOldOnes() throws {
        let dir = ollinTempPath("ollin-slowmo-between")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        OllinApp.exportSequence(MovingDot(), to: dir, frames: 8, fps: 30, slowMotion: .drawn(4))

        let written = try image(at: dir, frame: 2)                  // the second frame
        let atTheOldRate = try #require(OllinApp.image(of: MovingDot(), frame: 1, fps: 30))
        #expect(maxDifference(written, atTheOldRate) > 0)
    }

    /// A factor of 1 is the export that was always there. Nothing about the
    /// drive changes, so every frame comes back pixel for pixel the same, and
    /// the recipe still says nothing about slow motion.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFactorOfOneChangesNothing() throws {
        let plain = ollinTempPath("ollin-slowmo-plain")
        let asked = ollinTempPath("ollin-slowmo-asked")
        defer {
            try? FileManager.default.removeItem(atPath: plain)
            try? FileManager.default.removeItem(atPath: asked)
        }
        OllinApp.exportSequence(MovingDot(), to: plain, frames: 4, fps: 30)
        OllinApp.exportSequence(MovingDot(), to: asked, frames: 4, fps: 30, slowMotion: .drawn(1))
        for k in 1...4 {
            #expect(maxDifference(try image(at: plain, frame: k),
                                  try image(at: asked, frame: k)) == 0)
        }
        let recipe = try recipeJSON(at: asked, frame: 1)
        #expect(recipe["slowMotion"] == nil)
        #expect(recipe["fps"] as? Int == 30)
    }

    /// The file plays for the factor's worth longer than the sketch ran.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theVideoTakesLongerToWatch() async throws {
        let path = ollinTempPath("ollin-slowmo-video.mp4")
        defer { try? FileManager.default.removeItem(atPath: path) }
        // 0.2s of sketch time: 6 frames at 30 fps plain, 24 at a 4x clock.
        OllinApp.exportVideo(MovingDot(), to: path, frames: 24, fps: 30, slowMotion: .drawn(4))
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - 0.8) < 0.01)      // 4x the 0.2s it covers
    }

    /// The recipe records the rate the *clock* ran at, so a still re-renders
    /// from it unchanged, plus the factor that says how the file plays.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theRecipeCarriesTheClockAndTheFactor() throws {
        let dir = ollinTempPath("ollin-slowmo-recipe")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        OllinApp.exportSequence(MovingDot(), to: dir, frames: 4, fps: 30, slowMotion: .drawn(4))
        let recipe = try recipeJSON(at: dir, frame: 3)
        #expect(recipe["fps"] as? Int == 120)            // the clock, not the file
        #expect(recipe["frame"] as? Int == 2)            // 0-based, on that clock
        #expect(recipe["slowMotion"] as? Int == 4)
        // Drawn frames are what every export promises, so nothing is declared.
        #expect(recipe["madeFrames"] == nil)
    }

    /// An ordinary export says nothing about slow motion at all.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anOrdinaryExportDeclaresNoSlowMotion() throws {
        let dir = ollinTempPath("ollin-slowmo-silent")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        OllinApp.exportSequence(MovingDot(), to: dir, frames: 2, fps: 30)
        let recipe = try recipeJSON(at: dir, frame: 1)
        #expect(recipe["slowMotion"] == nil)
        #expect(recipe["fps"] as? Int == 30)
    }

    /// A warmup is measured in seconds of the sketch's own time, so it settles
    /// the same amount of motion however finely the clock is stepping.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theWarmupCountsSketchSeconds() throws {
        let dir = ollinTempPath("ollin-slowmo-warmup")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        OllinApp.exportSequence(MovingDot(), to: dir, frames: 4, fps: 30,
                                skipSeconds: 0.5, slowMotion: .drawn(4))
        // Half a second at 120 fps is 60 frames of warmup, so the first written
        // frame is the sketch at frame 60 of that clock.
        let written = try image(at: dir, frame: 1)
        let alone = try #require(OllinApp.image(of: MovingDot(), frame: 60, fps: 120))
        #expect(maxDifference(written, alone) == 0)
    }

    // MARK: - The made export

    /// A small moving 3D scene: a camera with a field of view, a still floor,
    /// and a bar crossing it, which is what a made frame has to carry.
    final class MovingBar: Sketch {
        override var canvasSize: CanvasSize { .square(192) }

        override func draw() {
            background(Color(white: 0.05))
            camera(Camera3D(eye: Vector3(0, 2.5, 7), target: Vector3(0, 0.6, 0),
                            projection: .perspective(fieldOfView: .pi / 3)))
            directionalLight(.white, direction: Vector3(-0.4, -0.8, -0.4), intensity: 0.9)
            withState {
                fill(Color(white: 0.7))
                translate(0, -0.1, 0)
                drawBox(width: 12, height: 0.2, depth: 12)
            }
            withMotion("bar") {
                withState {
                    fill(Color(hex: 0xE0B341))
                    translate(cos(time * 9) * 2.6, 0.9, 0)
                    drawBox(width: 0.5, height: 1.6, depth: 0.5)
                }
            }
        }
    }

    /// The frames the sketch did draw are exactly the frames it would have drawn
    /// with no slow motion asked for at all. Only the gaps are new, which is the
    /// whole claim the flag makes.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aMadeExportStillDrawsItsOwnFrames() throws {
        guard makesFrames else { return }        // no interpolator on this GPU
        let dir = ollinTempPath("ollin-slowmo-made")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        // 5 drawn frames at a 30 fps clock, with 4 made frames between them.
        OllinApp.exportSequence(MovingBar(), to: dir, frames: 9, fps: 30, slowMotion: .made(2))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir).count == 9)

        for k in [0, 2, 8] {                       // the drawn ones, 0-based
            let written = try image(at: dir, frame: k + 1)
            let alone = try #require(OllinApp.image(of: MovingBar(), frame: k / 2, fps: 30))
            #expect(maxDifference(written, alone) == 0,
                    "written frame \(k) is not the sketch's own frame \(k / 2)")
        }
    }

    /// A made frame is a new picture that belongs between its neighbors: it is
    /// closer to the truth of that moment than either of them is. That is the
    /// whole claim, and it is measured against the same moments drawn for real.
    ///
    /// It also pins the motion field the interpolator is handed. The fill writes
    /// the frame-wide field into its own texture and returns only the mover
    /// pass, whose unwritten pixels carry the sentinel -16384. Handing that back
    /// as motion warps the whole frame, and a made frame then lands about 80
    /// times further from the truth than simply holding a neighbor would.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aMadeFrameSitsBetweenTheDrawnOnes() throws {
        guard makesFrames else { return }        // no interpolator on this GPU
        let truth = ollinTempPath("ollin-slowmo-truth")
        let made = ollinTempPath("ollin-slowmo-between-made")
        defer {
            try? FileManager.default.removeItem(atPath: truth)
            try? FileManager.default.removeItem(atPath: made)
        }
        // The same nine moments twice: drawn at a 60 fps clock, and drawn at 30
        // with the gaps filled. Index for index they stand for the same time.
        OllinApp.exportSequence(MovingBar(), to: truth, frames: 9, fps: 30, slowMotion: .drawn(2))
        OllinApp.exportSequence(MovingBar(), to: made, frames: 9, fps: 30, slowMotion: .made(2))

        // The first gap is skipped on purpose: see the test below it.
        for k in [3, 5, 7] {                       // the made ones, 0-based
            let filled = try image(at: made, frame: k + 1)
            let real = try image(at: truth, frame: k + 1)
            let before = try image(at: truth, frame: k)
            let after = try image(at: truth, frame: k + 2)
            let error = meanDifference(filled, real)
            // Measured 2026-08-29: about 0.13 against 0.67…0.97 for a held
            // neighbor, so the made frame is roughly six times closer.
            #expect(error < meanDifference(before, real) / 3,
                    "made frame \(k) is no closer to that moment than the frame before it")
            #expect(error < meanDifference(after, real) / 3,
                    "made frame \(k) is no closer to that moment than the frame after it")
        }
    }

    /// The one place the made form falls back to a repeat: the first gap of a
    /// clip. The interpolator carries history, and one pair of frames is not
    /// enough to build any, however many times it is encoded (six was measured
    /// to be worth exactly what three is). So the head of a made clip holds one
    /// picture twice, which is the same thing the live window does when it
    /// starts, and the export says so rather than pretending otherwise.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theFirstGapOfAClipRepeatsItsNeighbor() throws {
        guard makesFrames else { return }
        let dir = ollinTempPath("ollin-slowmo-head")
        defer { try? FileManager.default.removeItem(atPath: dir) }
        OllinApp.exportSequence(MovingBar(), to: dir, frames: 5, fps: 30, slowMotion: .made(2))
        // Written frame 1 is the first made one, and it repeats frame 2.
        #expect(meanDifference(try image(at: dir, frame: 2), try image(at: dir, frame: 3)) < 0.01)
        // Every gap after it is a picture of its own.
        #expect(meanDifference(try image(at: dir, frame: 4), try image(at: dir, frame: 5)) > 0.1)
    }

    /// A flat sketch has no depth and no camera motion to work from, so the
    /// interpolator cannot run over it. The refusal names what is missing.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatSketchIsRefusedMadeFrames() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let flat = MovingDot()
        flat.setCanvasSize(width: 120, height: 120)
        flat.advance(time: 0, deltaTime: 1.0 / 30, frameRate: 30)
        flat.performDraw()
        let refusal = try #require(renderer.madeFrameRefusal(flat.drawer))
        #expect(refusal.contains("3D scene"))
    }

    // MARK: - Support

    /// Whether this GPU carries the platform frame interpolator.
    private var makesFrames: Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return MetalRenderer.frameInterpolationSupported(on: device)
    }

    private func name(_ frame: Int) -> String { String(format: "frame-%05d.png", frame) }

    private func image(at directory: String, frame: Int) throws -> CGImage {
        let url = URL(fileURLWithPath: directory + "/" + name(frame))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func recipeJSON(at directory: String, frame: Int) throws -> [String: Any] {
        let url = URL(fileURLWithPath: directory + "/" + name(frame))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let png = try #require(props[kCGImagePropertyPNGDictionary] as? [CFString: Any])
        let text = try #require(png[kCGImagePropertyPNGDescription] as? String)
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    /// The largest channel difference between two images, 0…255. Both are drawn
    /// into the same 8-bit buffer first, so a difference in color space or in
    /// how the file was encoded cannot be read as a difference in the picture.
    private func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        guard a.width == b.width, a.height == b.height else { return 255 }
        guard let left = bytes(of: a), let right = bytes(of: b) else { return 255 }
        var worst = 0
        for i in 0..<left.count {
            worst = max(worst, abs(Int(left[i]) - Int(right[i])))
        }
        return worst
    }

    /// The average channel difference between two images, 0…255.
    private func meanDifference(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height,
              let left = bytes(of: a), let right = bytes(of: b) else { return 255 }
        var total = 0
        for i in 0..<left.count { total += abs(Int(left[i]) - Int(right[i])) }
        return Double(total) / Double(left.count)
    }

    private func bytes(of image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? pixels : nil
    }
}
