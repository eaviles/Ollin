import CoreGraphics
import Testing
@testable import Ollin

/// Rendered checks on the self-warp sim's motion feedback.
///
/// The one thing a pixel snapshot cannot pin here is the *direction*: a motion
/// fit with its sign flipped still produces a plausible smeared picture, just
/// smeared the wrong way. So the load-bearing probes are directional, on a dot
/// marching steadily across the field at an overshooting strength (at strength
/// 1 an accurate fit lands the carried ghost back on the dot, which reads as
/// almost nothing): positive strength must throw the ghost ahead of the
/// motion, negative behind it. A third probe pins the fit's null: a scene that
/// does not move must measure no motion and converge to the drawing itself.
@Suite
@MainActor
struct SelfWarpTests {

    /// A bright disc marching right at a steady 6 px per frame on black.
    private final class MovingDot: Sketch {
        var strength = 3.0
        var field: SimField!
        override var canvasSize: CanvasSize { .square(256) }
        override func setup() {
            field = simField(.selfWarp(strength: strength, refresh: 0.25,
                                       smoothing: 0.3))
        }
        override func draw() {
            background(.black)   // before withField: a later one wipes the seed batches
            withField(field) {
                background(.black)
                fill(.white)
                drawCircle(40 + Double(frameCount) * 6, 128, 18)
            }
            drawImage(field.image, 0, 0)
        }
    }

    /// A scene with edges everywhere that never moves.
    private final class StillScene: Sketch {
        var warped = true
        var field: SimField!
        override var canvasSize: CanvasSize { .square(256) }
        override func setup() {
            if warped { field = simField(.selfWarp(refresh: 0.25)) }
        }
        private func scene() {
            background(Color(red: 0.1, green: 0.1, blue: 0.15))
            noStroke()
            for i in 0..<6 {
                fill(Color(hue: Double(i) / 6, saturation: 0.7, brightness: 0.9))
                drawCircle(40 + Double(i) * 36, 90 + Double(i % 2) * 70, 22)
            }
        }
        override func draw() {
            if warped {
                background(.black)
                withField(field) { scene() }
                drawImage(field.image, 0, 0)
            } else {
                scene()
            }
        }
    }

    /// The rendered frame as one gray value per pixel.
    private func grays(of image: CGImage) -> (w: Int, h: Int, at: (Int, Int) -> Int) {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (w, h, { x, y in Int(bytes[(y * w + x) * 4]) })
    }

    /// Mean gray over a horizontal band beside the dot: `dx` spans measured from
    /// the dot's center, in the strip of rows the dot travels in.
    private func bandMean(_ image: CGImage, dotX: Int, dx: ClosedRange<Int>) -> Double {
        let (w, h, gray) = grays(of: image)
        var sum = 0, count = 0
        for y in (h / 2 - 14)...(h / 2 + 14) {
            for offset in dx {
                let x = dotX + offset
                guard x >= 0, x < w, y >= 0, y < h else { continue }
                sum += gray(x, y); count += 1
            }
        }
        return count > 0 ? Double(sum) / Double(count) : 0
    }

    /// Overshooting strength throws the carried ghost ahead of the motion: the
    /// band past the dot's leading rim must carry far more ink than the mirror
    /// band behind it (measured at 89 vs 0.2 when this was pinned).
    @Test(.enabled(if: Snapshot.hasMetal))
    func theGhostIsThrownAlongTheMotion() throws {
        let sketch = MovingDot()
        let frame = 20
        let image = try #require(OllinApp.image(of: sketch, frame: frame))
        let dotX = 40 + (frame + 1) * 6
        let ahead = bandMean(image, dotX: dotX, dx: 20...48)
        let behind = bandMean(image, dotX: dotX, dx: -48...(-20))
        #expect(ahead > behind * 4 + 20,
                "ahead \(ahead) vs behind \(behind): the ghost is not riding the motion")
    }

    /// Negative strength drags the history against the motion, so the same probe
    /// flips: the ghost lands behind the dot.
    @Test(.enabled(if: Snapshot.hasMetal))
    func negativeStrengthDragsTheOtherWay() throws {
        let sketch = MovingDot()
        sketch.strength = -3
        let frame = 20
        let image = try #require(OllinApp.image(of: sketch, frame: frame))
        let dotX = 40 + (frame + 1) * 6
        let ahead = bandMean(image, dotX: dotX, dx: 20...48)
        let behind = bandMean(image, dotX: dotX, dx: -48...(-20))
        #expect(behind > ahead * 4 + 20,
                "behind \(behind) vs ahead \(ahead): negative strength did not reverse the drag")
    }

    /// A still scene must measure no motion: after the refresh has converged, the
    /// warped field is the drawing itself, pixel for pixel within the dither's
    /// reach. This pins the fit's null (a static picture solves to zero
    /// displacement exactly) and the advect pass's identity at zero flow.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aStillSceneStaysStill() throws {
        let warped = StillScene()
        let direct = StillScene()
        direct.warped = false
        let a = try #require(OllinApp.image(of: warped, frame: 60))
        let b = try #require(OllinApp.image(of: direct, frame: 60))
        let (w, h, ga) = grays(of: a)
        let (_, _, gb) = grays(of: b)
        var total = 0
        for y in 0..<h { for x in 0..<w { total += abs(ga(x, y) - gb(x, y)) } }
        let mean = Double(total) / Double(w * h)
        #expect(mean < 1.0, "mean gray difference \(mean): the still scene drifted")
    }
}
