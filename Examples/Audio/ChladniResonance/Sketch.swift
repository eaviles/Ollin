import Ollin
import OllinAudio

/// A signal generator sweeping a Chladni plate. A `Tone` glides slowly up and
/// down in pitch, and the plate *listens*: each mode in a small table rings at
/// its own frequency (ordered by the square plate's m² + n² eigenvalue), the
/// sketch reads the analyzer's `magnitude(in:)` around every mode's pitch, and
/// the plate morphs toward whichever mode hears the most energy. Figures snap
/// in and out as the sweep passes their resonances, exactly like sweeping a
/// real plate with a function generator.
///
/// It is self-contained on purpose (the sound is synthesized, so no microphone
/// permission is needed) but the reads come from the analysis, not the tone's
/// setting: swap the `Tone` for an `AudioInput()` and whistling at your Mac
/// sweeps the figures the same way.
@main
final class ChladniResonance: Sketch {
    let tone = Tone(frequency: 220, amplitude: 0.12, waveform: .sine)

    /// Modes of the square plate with m > n (the morph never crosses the still
    /// m == n diagonal), ordered by eigenvalue: the plate's rising resonances.
    let modes: [(m: Double, n: Double)] = {
        var pairs: [(m: Double, n: Double)] = []
        for m in 2 ... 7 {
            for n in 1 ..< m { pairs.append((Double(m), Double(n))) }
        }
        return pairs.sorted { $0.m * $0.m + $0.n * $0.n < $1.m * $1.m + $1.n * $1.n }
    }()

    /// Each mode's ring frequency: pitch rising with the eigenvalue, spread
    /// across a comfortable audible span.
    var frequencies: [Double] {
        modes.map { 160 + ($0.m * $0.m + $0.n * $0.n) * 14 }
    }

    // The plate's current mode numbers, gliding toward the loudest resonance.
    private var m = 2.0, n = 1.0

    @Param(0 ... 1, icon: "circle.dotted") var grain = 0.6

    override func setup() {
        tone.play()
    }

    override func draw() {
        background(Color(hex: 0x14181F))

        // The generator sweep: glide across the whole resonance span and back.
        let range = frequencies.first! ... frequencies.last!
        let sweep = pingPong(over: 36)
        tone.frequency = lerp(range.lowerBound - 30, range.upperBound + 30, sweep)

        // The plate listens: energy around each mode's pitch, loudest wins.
        var best = 0
        var bestLevel: Float = 0
        for (i, f) in frequencies.enumerated() {
            let level = tone.magnitude(in: f - 24 ... f + 24)
            if level > bestLevel { best = i; bestLevel = level }
        }

        // Glide toward the ringing mode, frame-rate independently.
        let approach = 1 - exp(-deltaTime * 4)
        m = lerp(m, modes[best].m, approach)
        n = lerp(n, modes[best].n, approach)

        let plate = generate(.chladni(m: m, n: n, weight: 0.1, grain: grain,
                                      phase: time))
        drawImage(plate.image, 0, 0)

        drawCaption("ChladniResonance")
    }
}
