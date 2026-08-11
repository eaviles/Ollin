import CoreGraphics
import Foundation
import simd
import Testing
@testable import Ollin

/// Behavioral probes for motion blur (`motionBlur`). The export path is fully
/// deterministic (frame k reads frame k-1's camera and movers, the gather jitter
/// is a pure function of pixel position), so every claim runs there, each against
/// its counterfactual twin: the same frame with the blur off, the same motion
/// turned ninety degrees, a shorter shutter, a probe pixel the streak cannot
/// reach. Orthographic 1:1 scenes (world units = pixels) keep expectations exact.
@Suite
@MainActor
struct MotionBlurTests {

    // MARK: Pixel support

    private func pixels(_ image: CGImage) -> (data: [UInt8], w: Int, h: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w, h)
    }

    /// The red byte at a pixel (the probes draw white ink on black, so one
    /// channel carries the whole story).
    private func ink(_ p: (data: [UInt8], w: Int, h: Int), _ x: Int, _ y: Int) -> Int {
        Int(p.data[(y * p.w + x) * 4])
    }

    // MARK: The claims

    /// A moving object streaks along its own motion: a pixel a few pixels past
    /// the box's edge *along* the travel picks up ink that the blur-off frame
    /// leaves black, and a pixel the same distance past the edge *across* the
    /// travel stays black. Pins the mover velocity reaching the fill, the
    /// gather direction, and the on/off gate at once.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aMoverStreaksAlongItsMotion() throws {
        let on = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: true, shutter: 1), frame: 2)))
        let off = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: false), frame: 2)))
        // Export frame 2 draws with frameCount 3: the box (24 px square) centers
        // at world (60, 0) = pixel (156, 96), edges at x 144/168, moving +x
        // 20 px per frame; shutter 1 spreads the streak 10 px each way.
        let along = ink(on, 174, 96)          // 6 px past the leading edge
        let alongOff = ink(off, 174, 96)
        let across = ink(on, 156, 96 - 18)    // 6 px past the top edge
        #expect(alongOff <= 1, "the unblurred frame must be black past the edge: \(alongOff)")
        #expect(along > 20, "the streak must reach past the silhouette: \(along)")
        #expect(across <= 2, "the streak must not spread across the motion: \(across)")
        // And the silhouette itself is no longer solid: the leading edge pixel
        // shares its exposure with the background it swept over.
        let edgeOn = ink(on, 166, 96)
        let edgeOff = ink(off, 166, 96)
        #expect(edgeOn < edgeOff, "an edge inside the streak must dilute: \(edgeOn) vs \(edgeOff)")
    }

    /// The counterfactual twin: the same box moving *up* streaks vertically, not
    /// horizontally. A velocity-axis swap anywhere in the chain reads red here.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theStreakFollowsTheMotionDirection() throws {
        let on = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: true, shutter: 1,
                                  velocity: Vector3(0, 20, 0)), frame: 2)))
        // World +y is screen up: drawn with frameCount 3, the box centers at
        // pixel (96, 36), edges at y 24/48 and x 84/108.
        let along = max(ink(on, 96, 18), ink(on, 96, 54))     // 6 px past either edge
        let across = max(ink(on, 96 + 18, 36), ink(on, 96 - 18, 36))
        #expect(along > 20, "a vertical mover must streak vertically: \(along)")
        #expect(across <= 2, "a vertical mover must not streak horizontally: \(across)")
    }

    /// Camera motion blurs the static scene with no `withMotion` in sight: the
    /// velocity fill's depth reprojection is the whole source. A panning camera
    /// streaks a still box's edge into the background.
    @Test(.enabled(if: Snapshot.hasMetal))
    func cameraMotionBlursTheStaticScene() throws {
        let on = pixels(try #require(OllinApp.image(
            of: MBCameraProbe.make(blur: true), frame: 2)))
        let off = pixels(try #require(OllinApp.image(
            of: MBCameraProbe.make(blur: false), frame: 2)))
        // The camera tracks +x at 20 px per frame, so the still box slides -x
        // across the frame; drawn with frameCount 3 its center sits at pixel
        // (36, 96) with edges at x 24/48, and shutter 1 spreads 10 px each way.
        let trail = ink(on, 55, 96)          // 7 px past the trailing edge
        let trailOff = ink(off, 55, 96)
        #expect(trailOff <= 1, "the unblurred frame must be black past the edge: \(trailOff)")
        #expect(trail > 15, "camera motion must streak the still box: \(trail)")
    }

    /// The dominant velocity travels the tile pyramid: a background pixel in the
    /// tile *next to* the mover's own (whose own tile max is zero) still gathers
    /// the streak, because the neighbor max hands it the mover's velocity.
    /// Dropping the neighbor-max pass (or the tile max under it) reads red.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theStreakReachesAcrossTileBounds() throws {
        let on = pixels(try #require(OllinApp.image(
            of: MBTileProbe.make(blur: true), frame: 2)))
        let off = pixels(try #require(OllinApp.image(
            of: MBTileProbe.make(blur: false), frame: 2)))
        // k is 16 at 192 tall, so tiles split at x = 112: the 8 px box centered
        // at pixel (104, 96) spans x 100...108, inside tile [96, 112); moving
        // 30 px per frame at shutter 1 its streak spreads 15 px, reaching x 123.
        let neighbor = ink(on, 118, 96)      // inside tile [112, 128)
        let neighborOff = ink(off, 118, 96)
        #expect(neighborOff <= 1, "the unblurred frame must be black there: \(neighborOff)")
        #expect(neighbor > 8, "the streak must cross into the neighboring tile: \(neighbor)")
    }

    /// A longer shutter is a longer streak: at a pixel only the wide spread can
    /// reach, shutter 1 leaves ink where shutter 0.25 leaves black.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theShutterScalesTheStreak() throws {
        let wide = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: true, shutter: 1), frame: 2)))
        let crisp = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: true, shutter: 0.25), frame: 2)))
        // Spread is 10 px at shutter 1, 2.5 px at 0.25; probe 6 px past the
        // leading edge (x 168, the box drawn with frameCount 3).
        let far = ink(wide, 174, 96)
        let short = ink(crisp, 174, 96)
        #expect(far > 20, "the wide shutter must reach 6 px past the edge: \(far)")
        #expect(short <= 2, "the short shutter must not: \(short)")
    }

    /// A still frame is byte-identical with the blur on: nothing moved, so the
    /// chain skips on the CPU (the camera float-equal to last frame's, no mover
    /// recorded) and the frame never even pays the passes.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aStillFrameIsByteIdentical() throws {
        let on = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: true, velocity: .zero, mover: false), frame: 2)))
        let off = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: false, velocity: .zero, mover: false), frame: 2)))
        #expect(on.data == off.data, "a still frame must be byte-identical under the blur")
    }

    /// A still frame with a still *mover* is byte-identical too: the mover pass
    /// runs (a range is recorded) but writes zero motion, the whole-neighborhood
    /// dominant velocity stays under half a pixel, and the reconstruction's
    /// early-out copies every pixel through untouched.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aStillMoverPassesThroughUntouched() throws {
        let on = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: true, velocity: .zero), frame: 2)))
        let off = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: false, velocity: .zero), frame: 2)))
        #expect(on.data == off.data, "a still mover must pass through byte-identically")
    }

    /// Frame zero has nothing to blur: no previous camera exists yet, so the
    /// first frame renders byte-identically with the blur on.
    @Test(.enabled(if: Snapshot.hasMetal))
    func frameZeroHasNothingToBlur() throws {
        let on = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: true, shutter: 1), frame: 0)))
        let off = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: false), frame: 0)))
        #expect(on.data == off.data, "frame zero must be byte-identical under the blur")
    }

    /// `noMotionBlur()` after `motionBlur()` is byte-identical to never asking:
    /// the per-frame reset and the renderer gate in one equality.
    @Test(.enabled(if: Snapshot.hasMetal))
    func turningItOffIsTheDefaultAgain() throws {
        let off = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: false), frame: 2)))
        let toggled = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: false, toggle: true), frame: 2)))
        #expect(off.data == toggled.data,
                "an on-then-off frame must be byte-identical to never-on")
    }

    /// Export determinism: the gather jitter is a pure function of pixel
    /// position and the velocities are a pure function of the frame pair, so two
    /// renders of one blurred frame are byte-identical (what every snapshot and
    /// video export stands on).
    @Test(.enabled(if: Snapshot.hasMetal))
    func anExportIsAPureFunctionOfTheFrame() throws {
        let first = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: true, shutter: 1), frame: 2)))
        let second = pixels(try #require(OllinApp.image(
            of: MBMoverProbe.make(blur: true, shutter: 1), frame: 2)))
        #expect(first.data == second.data,
                "two renders of one blurred frame must be byte-identical")
    }

    /// The no-camera gate: a 2D frame that asks for motion blur renders
    /// byte-identically to one that never did, answered with a note.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aTwoDFrameIsUntouched() throws {
        let plain = pixels(try #require(OllinApp.image(of: MB2DProbe.make(blur: false), frame: 2)))
        let asked = pixels(try #require(OllinApp.image(of: MB2DProbe.make(blur: true), frame: 2)))
        #expect(plain.data == asked.data, "a 2D frame must ignore the blur ask byte-identically")
    }

    /// The backdrop holds still by design: under a panning camera, a far-corner
    /// background pixel (no geometry anywhere near it) is untouched, so 2D
    /// overlays and the environment never smear.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theBackdropHoldsStill() throws {
        let on = pixels(try #require(OllinApp.image(
            of: MBCameraProbe.make(blur: true), frame: 2)))
        let off = pixels(try #require(OllinApp.image(
            of: MBCameraProbe.make(blur: false), frame: 2)))
        var same = true
        for y in 4..<24 where same {
            for x in 164..<188 where same {
                for c in 0..<4 {
                    if on.data[(y * on.w + x) * 4 + c] != off.data[(y * off.w + x) * 4 + c] {
                        same = false
                    }
                }
            }
        }
        #expect(same, "an empty background corner must be byte-identical under camera motion")
    }
}

// MARK: - Probe sketches

/// A white box on black, orthographic 1:1 (192 world units across 192 pixels),
/// moving `velocity` world units per frame under `withMotion`. World (0, 0) is
/// pixel (96, 96); world +x is screen +x, world +y is screen up.
private final class MBMoverProbe: Sketch {
    var blur = true
    var shutter = 0.5
    var velocity = Vector3(20, 0, 0)
    var mover = true
    var toggle = false

    static func make(blur: Bool, shutter: Double = 0.5,
                     velocity: Vector3 = Vector3(20, 0, 0),
                     mover: Bool = true, toggle: Bool = false) -> MBMoverProbe {
        let probe = MBMoverProbe()
        probe.blur = blur
        probe.shutter = shutter
        probe.velocity = velocity
        probe.mover = mover
        probe.toggle = toggle
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        ortho(eye: Vector3(0, 0, 100), target: .zero, height: 192, near: 1, far: 200)
        if blur { motionBlur(shutter: shutter) }
        if toggle { motionBlur(); noMotionBlur() }
        fill(.white)
        let place = {
            self.withState {
                self.translate(self.velocity.x * Double(self.frameCount),
                               self.velocity.y * Double(self.frameCount),
                               self.velocity.z * Double(self.frameCount))
                self.drawBox(width: 24, height: 24, depth: 2)
            }
        }
        if mover { withMotion { place() } } else { place() }
    }
}

/// A still white box under a camera tracking +x 20 world units per frame: all
/// motion comes from the camera, read back through the depth reprojection.
private final class MBCameraProbe: Sketch {
    var blur = true

    static func make(blur: Bool) -> MBCameraProbe {
        let probe = MBCameraProbe()
        probe.blur = blur
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        let track = 20.0 * Double(frameCount)
        ortho(eye: Vector3(track, 0, 100), target: Vector3(track, 0, 0),
              height: 192, near: 1, far: 200)
        if blur { motionBlur(shutter: 1) }
        fill(.white)
        drawBox(width: 24, height: 24, depth: 2)
    }
}

/// A small fast mover placed so its streak crosses a tile boundary: an 8 px box
/// whose own tile ends at x = 112 while its 15 px spread reaches x = 123.
private final class MBTileProbe: Sketch {
    var blur = true

    static func make(blur: Bool) -> MBTileProbe {
        let probe = MBTileProbe()
        probe.blur = blur
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        ortho(eye: Vector3(0, 0, 100), target: .zero, height: 192, near: 1, far: 200)
        if blur { motionBlur(shutter: 1) }
        fill(.white)
        withMotion {
            withState {
                // Drawn with frameCount 3 the box centers at world x = 8 (pixel
                // 104), one frame's travel being 30 px: the previous frame put
                // it at world x = -22.
                translate(30.0 * Double(frameCount) - 82, 0, 0)
                drawBox(width: 8, height: 8, depth: 2)
            }
        }
    }
}

/// A 2D frame (no camera) that asks for the blur: nothing must change.
private final class MB2DProbe: Sketch {
    var blur = true

    static func make(blur: Bool) -> MB2DProbe {
        let probe = MB2DProbe()
        probe.blur = blur
        return probe
    }

    override var canvasSize: CanvasSize { .square(128) }

    override func draw() {
        background(.black)
        if blur { motionBlur() }
        fill(.white)
        drawCircle(64 + Double(frameCount) * 10, 64, 30)
    }
}
