import CoreGraphics
import Foundation
@testable import Ollin
import Testing

/// Behavioral probes for `.predatorPrey`, run headless on a small field and read
/// back per frame: a land without predators stays full of prey; a uniform field
/// near the coexistence point oscillates with the period the model's own
/// linearization predicts, which pins the kinetics and the fixed step against the
/// written equations; and predators released on full prey spread as a front and
/// leave an oscillating wake, the spiral-wave regime. Metal-gated.
@Suite
@MainActor
struct PredatorPreyTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLandWithoutPredatorsStaysFull() throws {
        let sketch = PredatorPreyProbeSketch()
        let (prey, predators) = try channels(of: sketch, frame: 30)
        #expect(prey.joined().min()! > 0.97)
        #expect(predators.joined().max()! < 0.01)
    }

    /// A uniform field is the ordinary differential equation (diffusion of a flat
    /// field is exactly nothing), so the prey total from a small displacement of
    /// the coexistence point must swing at the period of the Jacobian's
    /// eigenvalues, stepped as the explicit Euler map steps them. Measured off the
    /// upward crossings of the prey mean, with the dither in the readback
    /// averaged out across the field.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theTotalsOscillateAtTheLinearizedPeriod() throws {
        let h = 0.4, k = 2.0, m = 0.6, steps = 8
        let dt = Sim.predatorPreyTimeStep
        let u = m * h / (k - m)                 // the coexistence point
        let v = (1 - u) * (u + h)
        let fu = 1 - 2 * u - v * h / ((u + h) * (u + h))
        let fv = -u / (u + h)
        let gu = k * v * h / ((u + h) * (u + h))
        let omega = (-fv * gu - fu * fu / 4).squareRoot()   // the ODE's angular frequency
        #expect(omega > 0)
        // Explicit Euler turns the eigenvalue into 1 + lambda dt, whose argument is
        // the phase one step advances.
        let phasePerStep = atan2(omega * dt, 1 + fu * dt / 2)
        let predicted = 2 * .pi / (phasePerStep * Double(steps))   // in frames

        // One run, read at every frame it passes, rather than a fresh run per frame.
        let sketch = PredatorPreyProbeSketch()
        sketch.uniform = (prey: u + 0.02, predators: v)
        let run = try channels(of: sketch, frames: Set(1 ... 75))
        var means: [Double] = []
        for frame in 1 ... 75 {
            let (prey, _) = try #require(run[frame])
            means.append(prey.joined().reduce(0, +) / Double(prey.count * prey[0].count))
        }
        // Upward crossings of the coexistence level, interpolated between frames.
        var crossings: [Double] = []
        for i in 1 ..< means.count where means[i - 1] < u && means[i] >= u {
            let fraction = (u - means[i - 1]) / (means[i] - means[i - 1])
            crossings.append(Double(i - 1) + fraction)
        }
        #expect(crossings.count >= 3, "\(means)")
        let periods = zip(crossings, crossings.dropFirst()).map { $1 - $0 }
        let measured = periods.reduce(0, +) / Double(periods.count)
        #expect(abs(measured - predicted) / predicted < 0.03,
                "measured \(measured) frames, predicted \(predicted)")
        // And the swing is real, small, and growing: past the oscillation threshold.
        let swing = means.max()! - means.min()!
        #expect(swing > 0.02 && swing < 0.3, "\(swing)")
    }

    /// One dot of predators on full prey: the front they make moves outward at a
    /// steady pace, and where it has passed the two populations keep cycling, so
    /// the center's prey level goes on swinging instead of settling.
    @Test(.enabled(if: Snapshot.hasMetal))
    func predatorsReleasedOnFullPreySpreadAsAWaveAndLeaveAWake() throws {
        // One run to the last checkpoint, read at each checkpoint on the way.
        let wake = Array(stride(from: 30, through: 120, by: 3))
        let sketch = PredatorPreyProbeSketch()
        sketch.dropsPredators = true
        let run = try channels(of: sketch, frames: Set([8, 16, 24] + wake))
        func reach(at frame: Int) throws -> Double {
            let (_, predators) = try #require(run[frame])
            var far = 0.0
            for y in 0 ..< predators.count {
                for x in 0 ..< predators[y].count where predators[y][x] > 0.1 {
                    far = max(far, ((Double(x) - 48) * (Double(x) - 48)
                                    + (Double(y) - 48) * (Double(y) - 48)).squareRoot())
                }
            }
            return far
        }
        let early = try reach(at: 8), middle = try reach(at: 16), late = try reach(at: 24)
        #expect(early > 4)
        #expect(middle > early + 3)
        #expect(late > middle + 3, "\(early) \(middle) \(late)")

        var center: [Double] = []
        for frame in wake {
            let (prey, _) = try #require(run[frame])
            center.append(prey[48][48])
        }
        let mean = center.reduce(0, +) / Double(center.count)
        let deviation = (center.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(center.count)).squareRoot()
        #expect(deviation > 0.05, "\(center)")
    }

    // MARK: Readback

    /// The rendered field decoded back to linear prey (red) and predator (green)
    /// levels, one per texel.
    private func channels(of sketch: Sketch, frame: Int) throws -> (prey: [[Double]], predators: [[Double]]) {
        channels(in: try #require(OllinApp.image(of: sketch, frame: frame)))
    }

    /// The same readout at several frames of one headless run. The run goes once
    /// to the last frame asked for and decodes each wanted frame as it passes, so
    /// no checkpoint re-simulates the frames before it. Frame `k` here is the
    /// picture `channels(of:frame: k)` would read.
    private func channels(of sketch: Sketch, frames wanted: Set<Int>) throws
    -> [Int: (prey: [[Double]], predators: [[Double]])] {
        var out: [Int: (prey: [[Double]], predators: [[Double]])] = [:]
        guard let last = wanted.max() else { return out }
        try OllinApp.renderFrames(sketch, frames: last + 1, fps: 60, skipSeconds: 0) { frame, index in
            guard wanted.contains(index), let image = frame.image else { return }
            out[index] = channels(in: image)
        }
        return out
    }

    private func channels(in image: CGImage) -> (prey: [[Double]], predators: [[Double]]) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        func linear(_ s: Double) -> Double {
            s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let prey = (0 ..< h).map { y in (0 ..< w).map { x in linear(Double(data[(y * w + x) * 4]) / 255) } }
        let predators = (0 ..< h).map { y in (0 ..< w).map { x in linear(Double(data[(y * w + x) * 4 + 1]) / 255) } }
        return (prey, predators)
    }
}

/// A 96-texel predator-prey field at the defaults, drawn 1:1. Untouched it rests
/// at full prey; `uniform` stamps the whole field with one state on frame 1 (the
/// ordinary differential equation, run on every texel at once); `dropsPredators`
/// puts one dot of predators at the center on frame 1.
@MainActor
private final class PredatorPreyProbeSketch: Sketch {
    override var canvasSize: CanvasSize { .square(96) }
    var uniform: (prey: Double, predators: Double)?
    var dropsPredators = false

    private var field: SimField!

    override func setup() {
        field = makeSimField(.predatorPrey(), scale: 1)
    }

    override func draw() {
        background(.black)
        withField(field) {
            if frameCount == 1 {
                noStroke()
                if let uniform {
                    // A Color is sRGB-encoded, so the levels are chosen on that
                    // curve to land on the wanted linear values.
                    fill(Color(red: srgb(uniform.prey), green: srgb(uniform.predators), blue: 0))
                    drawRect(-4, -4, width + 8, height + 8)
                }
                if dropsPredators {
                    fill(Color(red: 0, green: 1, blue: 0))
                    drawCircle(48, 48, 3)
                }
            }
        }
        drawImage(field.image, 0, 0)
    }

    private func srgb(_ l: Double) -> Double {
        l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055
    }
}
