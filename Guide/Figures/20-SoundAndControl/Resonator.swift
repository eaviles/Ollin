// figure: frame=248
//
// Guide payoff (Chapter 20): an audio-reactive instrument. A ring of spectrum
// spokes breathes with the music, a core throbs on every detected beat, and
// each beat flings a burst of sparks outward. The sound comes from StageMic,
// the chapter's pretend microphone (a little synthesized band fed into a real
// AudioAnalyzer), so the figure renders the same everywhere; swap it for an
// AudioInput() and the same reads follow whatever the room is playing.
import Ollin
import OllinAudio

final class Resonator: Sketch {
    let mic = StageMic()

    @Param(24...96) var spokes = 56
    @Param(0.6...2.4) var brightness = 1.4

    struct Spark {
        var position: Vector2
        var velocity: Vector2
        var life: Double
    }

    var sparks: [Spark] = []
    var lastBeat = 0
    var pulse = 0.0

    /// Where the instrument sits: a touch below center, to leave the crown room.
    var mid: Vector2 { center + Vector2(0, 60 * scale) }

    override func setup() {
        seed(20)                              // the sparks re-fly the same way
    }

    override func draw() {
        mic.listen()
        let audio = mic.analyzer

        background(Color(hex: 0x06040E))
        toneMap(.aces)
        blendMode(.add)

        // The beat: snap the pulse up when a new one lands, let it fade.
        pulse *= exp(-deltaTime * 5)
        if audio.beatCount > lastBeat {
            lastBeat = audio.beatCount
            pulse = 1
            spawnSparks()
        }

        // The spectrum, worn as a ring of spokes: bass at the top, treble at
        // the bottom, mirrored left and right so the ring stays symmetric.
        let levels = audio.bands(spokes / 2 + 1)
        withState {
            translate(mid)
            rotate(time * 0.06)
            for i in 0 ..< spokes {
                let band = i <= spokes / 2 ? i : spokes - i
                let level = Double(levels[band])
                let angle = Double(i) / Double(spokes) * .tau - .pi / 2
                let dir = Vector2(cos(angle), sin(angle))
                let inner = 175 * scale
                let len = (14 + level * 290) * scale
                fill(Colormap.magma.color(at: 0.2 + level * 0.75)
                    .withAlpha(0.25 + level * 0.75 * brightness))
                drawOrientedBox(dir * inner, dir * (inner + len),
                                thickness: (3.5 + level * 9) * scale)
            }
        }

        // Sparks from past beats, flying and fading.
        for i in sparks.indices {
            sparks[i].position += sparks[i].velocity * deltaTime
            sparks[i].life -= deltaTime
        }
        sparks.removeAll { $0.life <= 0 }
        noStroke()
        for spark in sparks {
            let a = max(0, spark.life / 0.8)
            fill(Color(hue: 0.09, saturation: 0.5, brightness: 1).withAlpha(a * 0.9))
            drawCircle(spark.position.x, spark.position.y, (1.5 + a * 5) * scale)
        }

        // The core: a warm glow that swells on the beat, a hot center.
        let ember = Color(hex: 0xFFB65C)
        let glowRadius = (185 + pulse * 150) * scale
        fill(.radial(center: mid, radius: glowRadius,
                     Ramp([ember.withAlpha(0.3 + pulse * 0.5), ember.withAlpha(0)])))
        drawCircle(center: mid, radius: glowRadius)
        let coreRadius = (80 + pulse * 60) * scale
        fill(.radial(center: mid, radius: coreRadius,
                     Ramp([Color.white.withAlpha(0.95), Color.white.withAlpha(0)])))
        drawCircle(center: mid, radius: coreRadius)

        blendMode(.normal)
    }

    func spawnSparks() {
        for i in 0 ..< 14 {
            let angle = Double(i) / 14 * .tau + random(-0.15, 0.15)
            let speed = random(200, 380) * scale
            let dir = Vector2(cos(angle), sin(angle))
            sparks.append(Spark(position: mid + dir * 180 * scale,
                                velocity: dir * speed,
                                life: random(0.45, 0.8)))
        }
    }
}

/// A pretend microphone. It synthesizes a little band (a kick drum every half
/// second, a hat between the kicks, a held bass note, a slow arpeggio, a
/// whisper of hiss) and feeds the samples into a real `AudioAnalyzer`,
/// exactly the way a live source would. Every audio read in this chapter comes out of the analyzer
/// itself; only the air has been replaced.
final class StageMic {
    let analyzer = AudioAnalyzer(fftSize: 2048, sampleRate: 44100)
    private var sample = 0
    private let rate = 44100.0

    /// Listen for one frame's worth of the tape (1/60 s by default).
    func listen(seconds: Double = 1.0 / 60) {
        let count = Int(rate * seconds)
        var tape = [Float](repeating: 0, count: count)
        for i in 0 ..< count {
            let t = Double(sample + i) / rate
            let sinceKick = t.truncatingRemainder(dividingBy: 0.5)
            var s = sin(t * 55 * .tau) * 0.6 * exp(-sinceKick * 9)     // the kick's thump
            s += sin(t * 2800 * .tau) * 0.3 * exp(-sinceKick * 70)     // and its click
            let sinceHat = (t + 0.25).truncatingRemainder(dividingBy: 0.5)
            s += white(sample + i + 7919) * 0.07 * exp(-sinceHat * 45)  // an off-beat hat
            s += sin(t * 110 * .tau) * 0.2                             // a held bass note
            let notes: [Double] = [330, 415, 494, 659]
            let melody = notes[Int(t + 0.25) % notes.count]            // a slow arpeggio
            s += sin(t * melody * .tau) * 0.16
            s += sin(t * melody * 2 * .tau) * 0.06
            s += white(sample + i) * 0.02                              // a little hiss
            tape[i] = Float(s)
        }
        sample += count
        tape.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: count) }
    }

    private func white(_ i: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: i) &* 0x9E3779B97F4A7C15
        x ^= x >> 29
        x &*= 0xBF58476D1CE4E5B9
        x ^= x >> 32
        return Double(x >> 40) / Double(1 << 23) - 1
    }
}
