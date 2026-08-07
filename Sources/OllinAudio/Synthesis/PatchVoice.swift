import Foundation

/// A patch's running state: eight oscillators and what they do to each other.
///
/// The whole thing is one forward pass. A patch is built so that anything
/// pushing something else sits in an earlier lane than what it pushes, so by
/// the time an operator is evaluated whatever modulates it has already been
/// worked out this sample. No sorting and no second pass.
///
/// The oscillators are lanes rather than objects. Eight `Oscillator` values in
/// an array would be a reference this struct carries, and a voice is copied
/// when a note starts, which would mean reference counting on the audio thread.
/// So the phases live in a vector and the shapes are read through the same
/// function the ordinary oscillator reads them through.
struct PatchVoice {
    /// Each operator's position through its cycle, `0..<1`.
    private var phases = SIMD8<Double>.zero
    /// Each operator's triangle integrator, unused by the other shapes.
    private var triangles = SIMD8<Double>.zero
    /// What each operator produced this sample, at its own level.
    private var values = SIMD8<Double>.zero
    /// The same from last sample, for the operators that push themselves.
    private var previous = SIMD8<Double>.zero
    private var increments = SIMD8<Double>.zero

    private var patch = Patch()
    /// How much to divide the sum by, so a patch of several operators is not
    /// louder than a patch of one.
    private var outputScale = 1.0
    private var noiseState: UInt64

    init(seed: UInt64) {
        // A zero state would leave the generator stuck at zero forever.
        noiseState = seed | 1
    }

    mutating func reset() {
        phases = .zero
        triangles = .zero
        values = .zero
        previous = .zero
    }

    /// Sets the patch up for a note.
    mutating func start(patch: Patch, frequency: Double, sampleRate: Double) {
        reset()
        self.patch = patch
        var outputs = 0.0
        for lane in 0..<patch.count {
            increments[lane] = patch.ratios[lane] * frequency / max(1, sampleRate)
            if patch.reachesOutput(lane) { outputs += 1 }
        }
        outputScale = outputs > 0 ? 1 / outputs : 0
    }

    /// One sample.
    mutating func next() -> Double {
        var mixed = 0.0
        for lane in 0..<patch.count {
            let shape = Waveform(shapeIndex: patch.shapes[lane])
            var raw: Double
            if shape == .noise {
                raw = nextNoise()
            } else {
                // What is pushing this operator: whatever modulates it, plus
                // its own last output where it pushes itself. Both move where
                // the shape is read rather than how fast the phase advances.
                var offset = patch.feedbacks[lane] * previous[lane]
                let source = patch.modulators[lane]
                if source >= 0 { offset += values[Int(source)] }

                let increment = increments[lane]
                let read = offset == 0 ? phases[lane] : fract(phases[lane] + offset)
                var triangle = triangles[lane]
                raw = waveformSample(shape, at: read, increment: increment,
                                     lastTriangle: &triangle)
                triangles[lane] = triangle
                phases[lane] = fract(phases[lane] + increment)
            }

            // The level is the mix level where the operator is heard and the
            // modulation depth where it is not, which is one number doing the
            // two jobs an operator's level does.
            values[lane] = raw * patch.levels[lane]
            if patch.reachesOutput(lane) { mixed += values[lane] }
        }
        previous = values
        return mixed * outputScale
    }

    private mutating func nextNoise() -> Double {
        noiseState &+= 0x9E37_79B9_7F4A_7C15
        var z = noiseState
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) * (2.0 / 9_007_199_254_740_992.0) - 1.0
    }
}
