// figure: frame=0
//
// Guide figure (Chapter 27): one staged reading from the phone's flow stream,
// drawn the two ways a sketch reads it. The field samples as a grid of streaks
// (each the local motion, colored by speed), and dust carried by the same
// field for a few seconds shows where the motion takes things: around the
// vortex on the left, off to the right along the drift.
//
// The reading is staged rather than read, the way this chapter's other figures
// stage a depth camera: the same PhoneFlow a phone fills in, built by hand from
// a PhoneFlowSample so the figure renders anywhere. The map is written
// camera-native with one quarter turn, so the turn the Mac applies is in the
// picture too.
import Foundation
import simd
import Ollin
import OllinPhone

final class FlowAsField: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    /// The camera-native map is landscape (the sensor's own frame); one
    /// clockwise turn stands it upright for a phone held sideways in this
    /// staging, which keeps the picture wide.
    static let mapWidth = 33
    static let mapHeight = 44

    /// A staged reading: a vortex turning about the left third of the upright
    /// picture and a steady drift to the right across the right third, written
    /// in flow-map pixels into the camera-native grid. The turn moves the
    /// picture's contents by a quarter turn, so the upright field is computed
    /// first and then written back through the inverse of the turn the Mac
    /// will apply.
    static func stagedReading() -> PhoneFlow {
        let uprightW = mapHeight, uprightH = mapWidth    // after one clockwise turn
        var upright = [SIMD2<Float>](repeating: .zero, count: uprightW * uprightH)
        for row in 0..<uprightH {
            for col in 0..<uprightW {
                let x = (Double(col) + 0.5) / Double(uprightW)
                let y = 1 - (Double(row) + 0.5) / Double(uprightH)
                // The vortex: tangential motion falling off past its rim.
                let dx = x - 0.32, dy = y - 0.5
                let r = (dx * dx + dy * dy).squareRoot()
                let swirl = 2.4 * exp(-r * r / (2 * 0.16 * 0.16)) * min(r / 0.08, 1)
                var vx = -dy / max(r, 1e-6) * swirl
                var vy = dx / max(r, 1e-6) * swirl
                // The drift: the right third slides to the right, eased in.
                let ease = min(max((x - 0.6) / 0.18, 0), 1)
                vx += 1.8 * ease * ease * (3 - 2 * ease)
                // Written in flow-map pixels, y down the upright picture.
                upright[row * uprightW + col] = SIMD2<Float>(Float(vx), Float(-vy))
            }
        }
        // Back to the camera-native grid: the Mac turns the map once clockwise
        // and every vector with it, so the stage turns it once counterclockwise.
        var native = [SIMD2<Float>](repeating: .zero, count: mapWidth * mapHeight)
        for row in 0..<uprightH {
            for col in 0..<uprightW {
                let v = upright[row * uprightW + col]
                let nativeCol = row
                let nativeRow = mapHeight - 1 - col
                native[nativeRow * mapWidth + nativeCol] = SIMD2<Float>(v.y, -v.x)
            }
        }
        return PhoneFlow(PhoneFlowSample(isTracked: true, timestamp: 4.2, interval: 1.0 / 15,
                                         flowWidth: mapWidth, flowHeight: mapHeight,
                                         orientation: 1, confidence: 0.9, flow: native))
    }

    let motion = stagedReading()

    override func setup() {
        seed(27)
    }

    override func draw() {
        background(Color(hex: 0x0D1017))

        // The stand-in for the camera frame: a letterboxed panel, dimmed the way
        // the live example dims the picture under its overlay.
        let rect = Rectangle(fitting: Vector2(4, 3), in: canvasRectangle.inset(by: .all(24)))
        noStroke()
        fill(Color(white: 0.10))
        drawRect(rect, cornerRadius: 14)

        // The field as a grid of streaks: each sample is the local motion,
        // colored by how fast the picture is moving there against the
        // reading's fastest motion, which is how the live example scales it.
        let spacing = 26.0
        let samples = motion.samples(in: rect, every: spacing)
        let fastest = max(samples.map(\.flow.length).max() ?? 0, 0.001)
        strokeWeight(2)
        for sample in samples {
            let speed = sample.flow.length
            guard speed > fastest * 0.06 else { continue }
            let t = min(speed / fastest, 1)
            let tone = Colormap.turbo.color(at: t)
            stroke(Color(red: tone.red, green: tone.green, blue: tone.blue, alpha: 0.35 + t * 0.65))
            drawLine(sample.position, sample.position + sample.flow * (spacing * 0.9 / fastest))
        }

        // Dust carried by the same field for a few seconds: every grain reads
        // the motion under itself, the way the live example's does, and its
        // trail is drawn behind it.
        var grains = (0..<260).map { _ in
            Vector2(rect.x + random(rect.width), rect.y + random(rect.height))
        }
        var trails = grains.map { [$0] }
        let gain = 0.55 * spacing / fastest
        for _ in 0..<28 {
            for i in grains.indices {
                let push = motion.vector(at: grains[i], in: rect) * gain
                grains[i] += push
                if rect.contains(grains[i]) { trails[i].append(grains[i]) }
            }
        }
        strokeWeight(1)
        stroke(Color(white: 1, alpha: 0.28))
        for trail in trails where trail.count > 1 {
            drawPolyline(trail)
        }
        noStroke()
        fill(Color(white: 1, alpha: 0.85))
        drawPoints(trails.compactMap(\.last).filter { rect.contains($0) }, size: 4)

        drawCaption("FlowAsField: samples(in:every:) as streaks colored by speed, dust carried by vector(at:in:)")
    }
}
