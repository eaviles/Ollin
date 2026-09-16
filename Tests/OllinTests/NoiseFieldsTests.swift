import Foundation
import Testing
@testable import Ollin

/// `NoiseFields`: the sketch's fields as a value. The value reads what the
/// sketch reads, keeps its seed as a value does, and answers the same numbers
/// from another thread, which is the reason it exists.
@Suite
struct NoiseFieldsTests {

    /// Every field on the value answers what the sketch's own call answers.
    @MainActor
    @Test func theValueReadsTheSketchsOwnFields() {
        let sketch = Sketch()
        sketch.noiseSeed(9)
        let fields = sketch.noiseFields
        for i in 0 ..< 48 {
            let x = Double(i) * 0.37 + 0.2, y = Double(i % 7) * 0.53 + 1.1, z = Double(i % 5) * 0.29 + 0.7
            let lap = Double(i) / 48
            #expect(fields.noise(x, y, z) == sketch.noise(x, y, z))
            #expect(fields.signedNoise(x) == sketch.signedNoise(x))
            #expect(fields.noise(x, y, loop: lap, radius: 0.8) == sketch.noise(x, y, loop: lap, radius: 0.8))
            #expect(fields.fbm(x, y, octaves: 5) == sketch.fbm(x, y, octaves: 5))
            #expect(fields.tilingFbm(lap, x - floor(x)) == sketch.tilingFbm(lap, x - floor(x)))
            #expect(fields.ridgedFbm(x, y) == sketch.ridgedFbm(x, y))
            #expect(fields.turbulence(x, y, z) == sketch.turbulence(x, y, z))
            #expect(fields.warpedFbm(x, y) == sketch.warpedFbm(x, y))
            #expect(fields.curlNoise(x, y) == sketch.curlNoise(x, y))
            #expect(fields.curlNoise(Vector3(x, y, z)) == sketch.curlNoise(x, y, z))
            #expect(fields.simplexNoise(x, y, z) == sketch.simplexNoise(x, y, z))
            #expect(fields.signedSimplexNoise(x) == sketch.signedSimplexNoise(x))
            #expect(fields.worley(x, y, feature: .border) == sketch.worley(x, y, feature: .border))
            #expect(fields.worley(x, y, z, jitter: 0.5) == sketch.worley(x, y, z, jitter: 0.5))
        }
    }

    /// A value made from a seed is the sketch seeded the same, and a different
    /// seed is a different field.
    @MainActor
    @Test func aSeedMakesTheSameFieldsAnywhere() {
        let sketch = Sketch()
        sketch.noiseSeed(21)
        let same = NoiseFields(seed: 21), other = NoiseFields(seed: 22)
        var differs = false
        for i in 0 ..< 32 {
            let x = Double(i) * 0.41, y = Double(i) * 0.19 + 3
            #expect(same.noise(x, y) == sketch.noise(x, y))
            #expect(same.simplexNoise(x, y) == sketch.simplexNoise(x, y))
            #expect(same.worley(x, y) == sketch.worley(x, y))
            if other.noise(x, y) != same.noise(x, y) { differs = true }
        }
        #expect(differs)
    }

    /// A copy keeps the seed it was taken with: reseeding the sketch moves the
    /// sketch's own reading and leaves the copy where it was.
    @MainActor
    @Test func aCopyKeepsItsSeedAcrossAReseed() {
        let sketch = Sketch()
        sketch.noiseSeed(5)
        let before = sketch.noiseFields
        let reading = sketch.noise(2.3, 4.1)
        sketch.noiseSeed(6)
        #expect(before.noise(2.3, 4.1) == reading, "the copy still reads seed 5")
        #expect(sketch.noiseFields.noise(2.3, 4.1) == NoiseFields(seed: 6).noise(2.3, 4.1), "the sketch reads seed 6")
        #expect(sketch.noise(2.3, 4.1) != reading)
    }

    /// The whole point: read off the main actor, on every core at once, and
    /// land the numbers the main thread would have.
    @MainActor
    @Test func theValueReadsTheSameNumbersOffTheMainThread() {
        let sketch = Sketch()
        sketch.noiseSeed(13)
        let fields = sketch.noiseFields
        let count = 20_000
        let points = (0 ..< count).map { i in
            Vector3(Double(i) * 0.0137, Double(i % 97) * 0.0211 + 2, Double(i % 89) * 0.0173 + 5)
        }
        var flows = [Vector3](repeating: .zero, count: count)
        var heights = [Double](repeating: 0, count: count)
        flows.withUnsafeMutableBufferPointer { flow in
            heights.withUnsafeMutableBufferPointer { height in
                DispatchQueue.concurrentPerform(iterations: count) { i in
                    flow[i] = fields.curlNoise(points[i])
                    height[i] = fields.fbm(points[i].x, points[i].y, octaves: 3)
                }
            }
        }
        for i in stride(from: 0, to: count, by: 251) {
            #expect(flows[i] == sketch.curlNoise(points[i]))
            #expect(heights[i] == sketch.fbm(points[i].x, points[i].y, octaves: 3))
        }
    }
}
