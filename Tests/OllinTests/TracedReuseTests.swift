@testable import Ollin
import Testing
import CoreGraphics
import Foundation
import simd

/// Correctness probes for reuse across a traced sequence (`--pt-reuse`,
/// `PathTracing.reusedFrames`): a frame carries the samples the frames before it
/// gathered at the same point of the scene.
///
/// Every claim is measured against a converged render of the same frame rather than
/// against taste: a still scene must come out as settled as a render of the whole
/// carried count, a surface a mover uncovers must show what is there and not what
/// the mover left (no ghost), a reflection that does not follow its surface's motion
/// must be followed rather than smeared, and the same command must render the same
/// sequence byte for byte.
@Suite(.serialized)
@MainActor
struct TracedReuseTests {

    /// The probe scene, 160 pixels square: a matte floor under one small bright
    /// panel (the shape that grains a thin render) and a still camera, with one
    /// thing in it per kind. Motion is measured in seconds, so the sequence drive
    /// and the single-frame drive put the same moment at the same frame index.
    final class Probe: Sketch {
        enum Kind {
            /// A matte sphere on the floor; nothing moves.
            case still
            /// The same, under a camera that slides sideways a little each frame.
            case pan
            /// A bright matte box sliding across the dark floor as a declared mover.
            case slide
            /// A polished ball spinning in place as a declared mover: its surface
            /// moves and its reflection of the panel stays put.
            case spin
        }
        var kind: Kind = .still

        override var canvasSize: CanvasSize { .square(160) }

        static func make(_ kind: Kind) -> Probe {
            let p = Probe()
            p.kind = kind
            return p
        }

        /// How far the slide's box has moved by `time`, world units a second.
        static let slideSpeed = 2.4
        /// How fast the spin's ball turns, radians a second.
        static let spinSpeed = 4.5
        /// How fast the pan's camera slides, world units a second.
        static let panSpeed = 1.2

        override func draw() {
            background(.black)
            ambientLight(Color(white: 0.03))
            rectangleLight(Color(white: 7), at: Vector3(1.7, 2.4, 1.6),
                           direction: Vector3(-0.6, -1, -0.6), width: 0.45, height: 0.45)
            let eyeX = kind == .pan ? Self.panSpeed * time : 0
            camera(Camera3D(eye: Vector3(eyeX, 1.3, 4), target: Vector3(eyeX, 0.35, 0)))
            material(Material())
            // The floor: dark under the slide, so a bright box's ghost cannot hide
            // in it; mid-gray otherwise.
            fill(kind == .slide ? Color(white: 0.15) : Color(white: 0.75))
            withState {
                translate(0, -0.55, 0)
                drawBox(width: 9, height: 0.6, depth: 9)
            }
            switch kind {
            case .still, .pan:
                fill(Color(white: 0.75))
                withState {
                    translate(0, 0.45, 0)
                    drawSphere(radius: 0.9)
                }
            case .slide:
                fill(.white)
                withMotion("box") {
                    translate(-1.6 + Self.slideSpeed * time, 0.15, 0.4)
                    drawBox(width: 1.0, height: 0.8, depth: 0.8)
                }
            case .spin:
                fill(Color(white: 0.9))
                material(.metal(roughness: 0.05))
                withMotion("ball") {
                    translate(0, 0.45, 0)
                    rotateY(Self.spinSpeed * time)
                    drawSphere(radius: 0.9)
                }
            }
        }
    }

    // MARK: - Drives and reads

    static let fps = 30.0

    /// The frames of a sequence under the given settings, in order.
    private func sequence(_ kind: Probe.Kind, frames: Int, settings: PathTracing) throws -> [CGImage] {
        OllinApp.pathTracedExport = settings
        defer { OllinApp.pathTracedExport = nil }
        var images: [CGImage] = []
        try OllinApp.renderFrames(Probe.make(kind), frames: frames, fps: Self.fps, skipSeconds: 0) { frame, _ in
            images.append(try #require(frame.image))
        }
        return images
    }

    /// One frame rendered on its own, with no history, under a fixed count.
    private func alone(_ kind: Probe.Kind, frame: Int, samples: Int) throws -> CGImage {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples, denoises: false)
        defer { OllinApp.pathTracedExport = nil }
        return try OllinApp.image(of: Probe.make(kind), frame: frame, fps: FrameRate(Self.fps))
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// A region of the canvas, as fractions of its width and height.
    struct Region {
        var x0: Double, x1: Double, y0: Double, y1: Double
        static let whole = Region(x0: 0, x1: 1, y0: 0, y1: 1)
    }

    /// How far two renders of the same frame sit apart over a region, in 8-bit
    /// levels, root mean square over the three channels.
    private func rootMeanSquare(_ a: CGImage, _ b: CGImage, over r: Region = .whole) -> Double {
        let x = pixels(of: a), y = pixels(of: b)
        let w = a.width, h = a.height
        var sum = 0.0
        var count = 0
        for py in Int(Double(h) * r.y0)..<Int(Double(h) * r.y1) {
            for px in Int(Double(w) * r.x0)..<Int(Double(w) * r.x1) {
                let i = (py * w + px) * 4
                for c in 0..<3 {
                    let d = Double(x[i + c]) - Double(y[i + c])
                    sum += d * d
                    count += 1
                }
            }
        }
        return (sum / Double(max(count, 1))).squareRoot()
    }

    /// The mean brightness over a region, 8-bit levels, the three channels together.
    private func mean(_ image: CGImage, over r: Region) -> Double {
        let d = pixels(of: image)
        let w = image.width, h = image.height
        var sum = 0.0
        var count = 0
        for py in Int(Double(h) * r.y0)..<Int(Double(h) * r.y1) {
            for px in Int(Double(w) * r.x0)..<Int(Double(w) * r.x1) {
                let i = (py * w + px) * 4
                sum += Double(d[i]) + Double(d[i + 1]) + Double(d[i + 2])
                count += 3
            }
        }
        return sum / Double(max(count, 1))
    }

    /// Where a world point lands on the probe's canvas, as fractions, under the
    /// probe's still camera: the same projection the renderer uses.
    private func project(_ p: Vector3, eyeX: Double = 0) -> (x: Double, y: Double) {
        let cam = Camera3D(eye: Vector3(eyeX, 1.3, 4), target: Vector3(eyeX, 0.35, 0))
        let vp = cam.projectionMatrix(aspect: 1) * cam.viewMatrix
        let clip = vp * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
        return (Double(clip.x / clip.w) * 0.5 + 0.5, 0.5 - Double(clip.y / clip.w) * 0.5)
    }

    // MARK: - The claims

    /// A still scene under a still camera: every pixel finds itself in the frame
    /// before, so after the history fills a frame holds the whole carried count, and
    /// a frame traced at 16 samples with four frames' worth carried must sit as
    /// close to a converged render as a render of 64 does, and much closer than a
    /// render of 16.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aStillSceneCarriesItsEarlierFrames() throws {
        let frames = 6
        let reused = try sequence(.still, frames: frames,
                                  settings: PathTracing(samplesPerPixel: 16, reusedFrames: 4))
        let reference = try alone(.still, frame: frames - 1, samples: 1024)
        let thin = try alone(.still, frame: frames - 1, samples: 16)
        let deep = try alone(.still, frame: frames - 1, samples: 64)
        let reusedError = rootMeanSquare(reused[frames - 1], reference)
        let thinError = rootMeanSquare(thin, reference)
        let deepError = rootMeanSquare(deep, reference)
        #expect(reusedError < thinError * 0.65,
                "reused \(reusedError) against 16 alone \(thinError)")
        #expect(reusedError < deepError * 1.25,
                "reused \(reusedError) against 64 alone \(deepError)")
    }

    /// The first frame of a run has no frame before it and traces the history's
    /// worth itself: 16 samples with four frames' worth to carry is a 64-sample
    /// render of that frame, the same samples in the same order, so the two agree
    /// to the rounding of a division.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theFirstFrameTracesTheHistorysWorth() throws {
        let reused = try sequence(.still, frames: 1,
                                  settings: PathTracing(samplesPerPixel: 16, reusedFrames: 4))
        let deep = try alone(.still, frame: 0, samples: 64)
        let error = rootMeanSquare(reused[0], deep)
        #expect(error < 0.5, "first reusing frame against 64 alone \(error)")
    }

    /// The camera slides and the scene holds still: every pixel's history lies a
    /// little to one side, found through the camera's own motion, and the frame
    /// still settles well past what it traced alone.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aPanningCameraFindsItsHistory() throws {
        let frames = 6
        let reused = try sequence(.pan, frames: frames,
                                  settings: PathTracing(samplesPerPixel: 16, reusedFrames: 4))
        let reference = try alone(.pan, frame: frames - 1, samples: 1024)
        let thin = try alone(.pan, frame: frames - 1, samples: 16)
        let reusedError = rootMeanSquare(reused[frames - 1], reference)
        let thinError = rootMeanSquare(thin, reference)
        #expect(reusedError < thinError * 0.75,
                "reused under a pan \(reusedError) against 16 alone \(thinError)")
    }

    /// A bright box slides over a dark floor. The floor it uncovers has no history
    /// of its own (the frame before held the box there, another surface at another
    /// depth), so it must show the floor at the frame's own count and nothing of
    /// the box: a ghost would read tens of levels bright. The floor it has not
    /// reached, meanwhile, still settles.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func anUncoveredFloorCarriesNoGhost() throws {
        let frames = 8
        let reused = try sequence(.slide, frames: frames,
                                  settings: PathTracing(samplesPerPixel: 16, reusedFrames: 8))
        let last = frames - 1
        let reference = try alone(.slide, frame: last, samples: 512)
        let thin = try alone(.slide, frame: last, samples: 16)
        // The strip the box vacated over the last three frames: between where its
        // trailing face was three frames ago and where it is now, over the box's
        // own height on the canvas.
        let time = Double(last) / Self.fps
        let step = Probe.slideSpeed / Self.fps
        let back = project(Vector3(-1.6 + Probe.slideSpeed * time - 0.5 - 3 * step, 0.15, 0.8))
        let front = project(Vector3(-1.6 + Probe.slideSpeed * time - 0.5, 0.15, 0.8))
        let top = project(Vector3(-1.6 + Probe.slideSpeed * time, 0.5, 0.8))
        let bottom = project(Vector3(-1.6 + Probe.slideSpeed * time, -0.2, 0.8))
        let strip = Region(x0: back.x, x1: front.x - 0.005, y0: top.y, y1: bottom.y)
        let ghost = mean(reused[last], over: strip) - mean(reference, over: strip)
        #expect(ghost < 10, "the uncovered strip reads \(ghost) levels off the reference")
        // Far from the box, the floor settles.
        let far = Region(x0: 0.7, x1: 0.95, y0: 0.6, y1: 0.9)
        let reusedFar = rootMeanSquare(reused[last], reference, over: far)
        let thinFar = rootMeanSquare(thin, reference, over: far)
        #expect(reusedFar < thinFar * 0.8, "far floor reused \(reusedFar) against alone \(thinFar)")
    }

    /// A polished ball spins in place. Its surface moves, so a declared mover's
    /// motion says each pixel came from a little way around the ball, while its
    /// reflection of the panel stays where it is: the history found there is the
    /// wrong light, further from the frame's own estimate than its grain allows,
    /// and is pulled to that grain. The ball must come out no worse than the frame
    /// traced alone, and the floor around it still settles.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aSpinningMirrorIsFollowedNotSmeared() throws {
        let frames = 8
        let reused = try sequence(.spin, frames: frames,
                                  settings: PathTracing(samplesPerPixel: 16, reusedFrames: 8))
        let last = frames - 1
        let reference = try alone(.spin, frame: last, samples: 512)
        let thin = try alone(.spin, frame: last, samples: 16)
        let ball = Region(x0: 0.36, x1: 0.64, y0: 0.3, y1: 0.58)
        let reusedBall = rootMeanSquare(reused[last], reference, over: ball)
        let thinBall = rootMeanSquare(thin, reference, over: ball)
        #expect(reusedBall < thinBall * 1.15,
                "the spinning ball reused \(reusedBall) against alone \(thinBall)")
        let floor = Region(x0: 0.05, x1: 0.3, y0: 0.62, y1: 0.92)
        let reusedFloor = rootMeanSquare(reused[last], reference, over: floor)
        let thinFloor = rootMeanSquare(thin, reference, over: floor)
        #expect(reusedFloor < thinFloor * 0.8,
                "the floor beside it reused \(reusedFloor) against alone \(thinFloor)")
    }

    /// The house rule: a frame of a reusing sequence is a function of the frames
    /// before it, and the same command renders the same sequence byte for byte.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theSequenceIsTheSameBytesTwice() throws {
        let settings = PathTracing(samplesPerPixel: 8, reusedFrames: 4)
        let first = try sequence(.slide, frames: 3, settings: settings)
        let second = try sequence(.slide, frames: 3, settings: settings)
        for k in 0..<3 {
            #expect(pixels(of: first[k]) == pixels(of: second[k]), "frame \(k)")
        }
    }

    /// With the mode off nothing is carried: a sequence of three frames reads the
    /// same as each frame rendered alone, byte for byte, so a command written
    /// before the flag existed renders what it always did.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func nothingIsCarriedUnlessAskedFor() throws {
        #expect(PathTracing(samplesPerPixel: 8).reusedFrames == 0)
        let plain = try sequence(.slide, frames: 3, settings: PathTracing(samplesPerPixel: 8))
        for k in 0..<3 {
            let one = try alone(.slide, frame: k, samples: 8)
            #expect(pixels(of: plain[k]) == pixels(of: one), "frame \(k)")
        }
    }
}
