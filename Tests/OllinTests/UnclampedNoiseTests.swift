import Foundation
import Testing
@testable import Ollin

/// `noise(…, clamped: false)` and its signed and looping forms: the same field
/// as `noise`, read before the cut. It equals `noise` wherever `noise` is
/// strictly inside its range, runs past the end wherever `noise` rests on
/// one, and never rests on an end itself.
@Suite("Noise with nothing cut off")
struct UnclampedNoiseTests {

    /// A spread of read points over the field, the same on every run.
    static func points(_ count: Int, seed: UInt64) -> [(x: Double, y: Double, z: Double, lap: Double)] {
        var rng = SplitMix64(seed: seed)
        return (0 ..< count).map { _ in
            (Double.random(in: 0 ..< 256, using: &rng), Double.random(in: 0 ..< 256, using: &rng),
             Double.random(in: 0 ..< 256, using: &rng), Double.random(in: 0 ..< 1, using: &rng))
        }
    }

    /// Holds one unclamped read against the clamped read of the same point,
    /// and counts the reads the clamp cut. `low ... high` is the clamped range.
    struct Tally {
        var onAnEnd = 0, cut = 0, disagreements = 0, wrongSide = 0
        var least = Double.infinity, most = -Double.infinity

        mutating func hold(_ free: Double, against clamped: Double, low: Double, high: Double) {
            least = Swift.min(least, free)
            most = Swift.max(most, free)
            if free == low || free == high { onAnEnd += 1 }
            if clamped > low && clamped < high {
                if free != clamped { disagreements += 1 }
            } else {
                cut += 1
                if clamped == low ? free > low : free < high { wrongSide += 1 }
            }
        }
    }

    @Test("In 800,000 reads of a 2D field none rests on an end, and it is `noise` wherever `noise` is not cut")
    func twoDimensions() {
        let fields = NoiseFields(seed: 3)
        var tally = Tally()
        for point in Self.points(800_000, seed: 41) {
            tally.hold(fields.noise(point.x, point.y, clamped: false), against: fields.noise(point.x, point.y), low: 0, high: 1)
        }
        #expect(tally.onAnEnd == 0)
        #expect(tally.disagreements == 0)
        #expect(tally.wrongSide == 0)
        // The clamp it leaves out is real: about 4 reads in 100.
        #expect(tally.cut > 800_000 * 3 / 100 && tally.cut < 800_000 * 5 / 100, "\(tally.cut) reads were cut")
        // How far the field runs: past both ends, and never past twice its range.
        #expect(tally.least < -0.3 && tally.most > 1.3, "\(tally.least) to \(tally.most)")
        #expect(tally.least > -0.6 && tally.most < 1.6, "\(tally.least) to \(tally.most)")
    }

    @Test("The same holds in 3D, signed, and around a loop")
    func theOtherForms() {
        let fields = NoiseFields(seed: 8)
        var volume = Tally(), signed = Tally(), signedVolume = Tally()
        var lap = Tally(), lapLine = Tally(), lapPlane = Tally(), lapVolume = Tally(), signedLapPlane = Tally()
        for p in Self.points(120_000, seed: 77) {
            volume.hold(fields.noise(p.x, p.y, p.z, clamped: false), against: fields.noise(p.x, p.y, p.z), low: 0, high: 1)
            signed.hold(fields.signedNoise(p.x, p.y, clamped: false), against: fields.signedNoise(p.x, p.y), low: -1, high: 1)
            signedVolume.hold(fields.signedNoise(p.x, p.y, p.z, clamped: false), against: fields.signedNoise(p.x, p.y, p.z), low: -1, high: 1)
            lap.hold(fields.noise(loop: p.lap, radius: p.x, clamped: false), against: fields.noise(loop: p.lap, radius: p.x), low: 0, high: 1)
            lapLine.hold(fields.noise(p.x, loop: p.lap, radius: 3, clamped: false), against: fields.noise(p.x, loop: p.lap, radius: 3), low: 0, high: 1)
            lapPlane.hold(fields.noise(p.x, p.y, loop: p.lap, radius: 3, clamped: false),
                          against: fields.noise(p.x, p.y, loop: p.lap, radius: 3), low: 0, high: 1)
            lapVolume.hold(fields.noise(p.x, p.y, p.z, loop: p.lap, radius: 3, clamped: false),
                           against: fields.noise(p.x, p.y, p.z, loop: p.lap, radius: 3), low: 0, high: 1)
            signedLapPlane.hold(fields.signedNoise(p.x, p.y, loop: p.lap, radius: 3, clamped: false),
                                against: fields.signedNoise(p.x, p.y, loop: p.lap, radius: 3), low: -1, high: 1)
        }
        let all = [("3D", volume), ("signed 2D", signed), ("signed 3D", signedVolume), ("a lap", lap), ("a lap along a line", lapLine),
                   ("a lap over a plane", lapPlane), ("a lap through a volume", lapVolume), ("a signed lap over a plane", signedLapPlane)]
        for (name, tally) in all {
            #expect(tally.onAnEnd == 0, "\(name)")
            #expect(tally.disagreements == 0, "\(name)")
            #expect(tally.wrongSide == 0, "\(name)")
            #expect(tally.cut > 120_000 / 100, "\(name): the clamp cut only \(tally.cut) reads, so this proved little")
        }
    }

    @Test("A line's field never leaves its range, so both answers are one")
    func oneDimension() {
        let fields = NoiseFields(seed: 5)
        for p in Self.points(50_000, seed: 9) {
            #expect(fields.noise(p.x, clamped: false) == fields.noise(p.x))
            #expect(fields.signedNoise(p.x, clamped: false) == fields.signedNoise(p.x))
        }
    }

    @Test("With the clamp asked for, every form is the plain call")
    func clampedIsThePlainCall() {
        let fields = NoiseFields(seed: 12)
        for p in Self.points(4000, seed: 2) {
            #expect(fields.noise(p.x, clamped: true) == fields.noise(p.x))
            #expect(fields.noise(p.x, p.y, clamped: true) == fields.noise(p.x, p.y))
            #expect(fields.noise(p.x, p.y, p.z, clamped: true) == fields.noise(p.x, p.y, p.z))
            #expect(fields.signedNoise(p.x, clamped: true) == fields.signedNoise(p.x))
            #expect(fields.signedNoise(p.x, p.y, clamped: true) == fields.signedNoise(p.x, p.y))
            #expect(fields.signedNoise(p.x, p.y, p.z, clamped: true) == fields.signedNoise(p.x, p.y, p.z))
            #expect(fields.noise(loop: p.lap, radius: 2, clamped: true) == fields.noise(loop: p.lap, radius: 2))
            #expect(fields.noise(p.x, loop: p.lap, clamped: true) == fields.noise(p.x, loop: p.lap))
            #expect(fields.noise(p.x, p.y, loop: p.lap, clamped: true) == fields.noise(p.x, p.y, loop: p.lap))
            #expect(fields.noise(p.x, p.y, p.z, loop: p.lap, clamped: true) == fields.noise(p.x, p.y, p.z, loop: p.lap))
            #expect(fields.signedNoise(loop: p.lap, radius: 2, clamped: true) == fields.signedNoise(loop: p.lap, radius: 2))
            #expect(fields.signedNoise(p.x, loop: p.lap, clamped: true) == fields.signedNoise(p.x, loop: p.lap))
            #expect(fields.signedNoise(p.x, p.y, loop: p.lap, clamped: true) == fields.signedNoise(p.x, p.y, loop: p.lap))
            #expect(fields.signedNoise(p.x, p.y, p.z, loop: p.lap, clamped: true) == fields.signedNoise(p.x, p.y, p.z, loop: p.lap))
        }
    }

    @Test("The unsigned read is the signed one moved into 0...1, and a lap still closes")
    func signedAndUnsignedAgree() {
        let fields = NoiseFields(seed: 30)
        for p in Self.points(4000, seed: 6) {
            #expect(fields.noise(p.x, p.y, clamped: false) == (fields.signedNoise(p.x, p.y, clamped: false) + 1) / 2)
            #expect(fields.noise(p.x, p.y, p.z, clamped: false) == (fields.signedNoise(p.x, p.y, p.z, clamped: false) + 1) / 2)
            let start = fields.signedNoise(p.x, p.y, p.z, loop: 0, radius: 2, clamped: false)
            let end = fields.signedNoise(p.x, p.y, p.z, loop: 1, radius: 2, clamped: false)
            #expect(abs(start - end) < 1e-9)
        }
    }

    @MainActor
    @Test("The sketch's bare calls read the same numbers")
    func theSketchForwards() {
        let sketch = Sketch()
        sketch.noiseSeed(19)
        let fields = sketch.noiseFields
        for p in Self.points(500, seed: 4) {
            for clamped in [false, true] {
                #expect(sketch.noise(p.x, clamped: clamped) == fields.noise(p.x, clamped: clamped))
                #expect(sketch.noise(p.x, p.y, clamped: clamped) == fields.noise(p.x, p.y, clamped: clamped))
                #expect(sketch.noise(p.x, p.y, p.z, clamped: clamped) == fields.noise(p.x, p.y, p.z, clamped: clamped))
                #expect(sketch.signedNoise(p.x, clamped: clamped) == fields.signedNoise(p.x, clamped: clamped))
                #expect(sketch.signedNoise(p.x, p.y, clamped: clamped) == fields.signedNoise(p.x, p.y, clamped: clamped))
                #expect(sketch.signedNoise(p.x, p.y, p.z, clamped: clamped) == fields.signedNoise(p.x, p.y, p.z, clamped: clamped))
                #expect(sketch.noise(loop: p.lap, radius: 2, clamped: clamped) == fields.noise(loop: p.lap, radius: 2, clamped: clamped))
                #expect(sketch.noise(p.x, loop: p.lap, clamped: clamped) == fields.noise(p.x, loop: p.lap, clamped: clamped))
                #expect(sketch.noise(p.x, p.y, loop: p.lap, clamped: clamped) == fields.noise(p.x, p.y, loop: p.lap, clamped: clamped))
                #expect(sketch.noise(p.x, p.y, p.z, loop: p.lap, clamped: clamped) == fields.noise(p.x, p.y, p.z, loop: p.lap, clamped: clamped))
                #expect(sketch.signedNoise(loop: p.lap, radius: 2, clamped: clamped) == fields.signedNoise(loop: p.lap, radius: 2, clamped: clamped))
                #expect(sketch.signedNoise(p.x, loop: p.lap, clamped: clamped) == fields.signedNoise(p.x, loop: p.lap, clamped: clamped))
                #expect(sketch.signedNoise(p.x, p.y, loop: p.lap, clamped: clamped) == fields.signedNoise(p.x, p.y, loop: p.lap, clamped: clamped))
                #expect(sketch.signedNoise(p.x, p.y, p.z, loop: p.lap, clamped: clamped)
                        == fields.signedNoise(p.x, p.y, p.z, loop: p.lap, clamped: clamped))
            }
        }
    }
}
