import Ollin
import OllinAudio

/// A sound cut into pieces too short to have a pitch, and piled back up.
///
/// Every other instrument here reads a sound from one end to the other, so
/// where it is and how high it sounds are one number. A grain cloud has two.
/// The grains are read at whatever speed the note asks for, and the place they
/// are cut from travels at `speed`, which is a separate control. Set `speed` to
/// 0 and the sound stops while the note keeps going: one moment, held, for as
/// long as you like.
///
/// The sound is drawn across the middle. The lit band is where grains are being
/// cut from right now, as wide as the jitter lets them stray, and it slides
/// along at `speed`. **Drag anywhere to pull that band through the sound by
/// hand**, which is the thing worth doing here. The curve at the bottom left is
/// the shape each grain is cut with, and the bar beside it is how many are
/// sounding at once.
@main
final class GrainsSketch: Sketch {

    enum Cut: String, ParamOption { case bell, gaussian, triangle, plateau, tick, swell }

    @Param(0.002 ... 0.25, icon: "ruler", group: "Grain") var size = 0.07
    @Param(1 ... 300, icon: "square.stack.3d.down.right", group: "Grain") var density = 45.0
    @Param(icon: "waveform.path", group: "Grain") var cut = Cut.bell
    @Param(-1 ... 1, icon: "forward", group: "Cloud") var speed = 0.0
    @Param(0 ... 0.5, icon: "arrow.left.and.right", group: "Cloud") var jitter = 0.01
    @Param(0 ... 12, icon: "tuningfork", group: "Cloud") var pitchSpread = 0.0
    @Param(0 ... 1, icon: "speaker.wave.2", group: "Cloud") var panSpread = 0.7
    @Param(0 ... 1, icon: "dice", group: "Cloud") var scatter = 1.0

    let synth = Synth(polyphony: 8)
    /// The sound itself, made here rather than loaded so the sketch stands
    /// alone: a struck bar, a tone climbing, and a rattle, three things a
    /// band can be dragged between.
    var source: GrainSource!
    /// The source drawn once as a row of peaks, since a second of samples is
    /// far more than a row of pixels.
    var outline: [Double] = []
    var held: PlayingNote?
    var trace: [Double] = []
    var built = ""
    /// Where the band is, worked out the way the cloud works it out, so the
    /// picture says the same thing the sound does.
    var readPosition = 0.0
    var scrub = 0.0
    /// Whether anybody has taken over; until then the sketch drags itself.
    var hasDragged = false

    override func setup() {
        source = Self.material()
        outline = Self.peaks(of: source, count: 420)
        synth.gain = 0.55
        synth.grainSource = source
        synth.effects = [.reverb(Reverb(.hall, mix: 0.25))]
        rebuild()
        held = synth.noteOn("C4", velocity: 0.85)
    }

    private var recipe: String {
        "\(size)-\(density)-\(cut)-\(speed)-\(jitter)-\(pitchSpread)-\(panSpread)-\(scatter)"
    }

    /// The whole feature in two lines: which sound, and how it is cut up.
    /// They are set apart because a sound is far too large to travel inside a
    /// note, the same rule a sampled instrument keeps.
    private func rebuild() {
        synth.grainSource = source
        synth.voice = Voice(
            granular: GrainCloud(size: size, density: density, position: readPosition,
                                 positionJitter: jitter, speed: speed,
                                 pitchSpread: pitchSpread, panSpread: panSpread,
                                 scatter: scatter, shape: shape),
            envelope: .sustained, gain: 0.8)
        built = recipe
    }

    private var shape: GrainShape {
        switch cut {
        case .bell: return .bell
        case .gaussian: return .gaussian
        case .triangle: return .triangle
        case .plateau: return .plateau
        case .tick: return .tick
        case .swell: return .swell
        }
    }

    override func draw() {
        background(Color(hex: 0x0A0C11))

        // Dragging pulls the reading through the sound. It reaches a note that
        // is already sounding, which is why this is a drag rather than a note.
        if mouseIsPressed {
            scrub = fract(min(max(0, mouseX / width), 1) - readPosition + 1)
            hasDragged = true
        } else if !hasDragged {
            // Left alone, the sketch drags itself, so a frozen cloud is seen
            // moving rather than described as able to.
            scrub = fract(0.5 - 0.5 * cos(time * 0.5))
        }
        synth.grainScrub = scrub

        // The band travels at the same speed the cloud travels at, so the
        // picture and the sound agree without either asking the other.
        if speed != 0 {
            readPosition = fract(readPosition + speed * deltaTime / max(0.001, source.duration))
        }
        if built != recipe {
            // A cloud is read when a note starts, so a changed setting takes
            // the next note. The held one is let go and taken again.
            if let held { synth.noteOff(held) }
            rebuild()
            held = synth.noteOn("C4", velocity: 0.85)
        }

        trace.append(Double(synth.amplitude))
        if trace.count > 300 { trace.removeFirst() }

        drawSound()
        drawGrainShape()
        drawCount()
        drawTrace()
        drawCaption("A sound cut into grains. The lit band is where they come from.", edge: .top)
        drawCaption(hasDragged
                    ? "Speed 0 holds the reading still while the note keeps going."
                    : "Dragging itself. Take over with the pointer.")
    }

    /// The sound as a row of peaks, with the band lit over it.
    private func drawSound() {
        let middle = height * 0.42, tall = height * 0.2
        noStroke()
        let reading = fract(readPosition + scrub)

        for (index, peak) in outline.enumerated() {
            let along = Double(index) / Double(max(1, outline.count - 1))
            // How much of the band this column is under, so a wide jitter
            // lights a wide stretch and a tight one lights a line.
            let away = abs(shortestWay(from: along, to: reading))
            let lit = jitter > 0.0005 ? max(0, 1 - away / max(0.004, jitter)) : (away < 0.004 ? 1 : 0)
            let color = lit > 0
                ? Color.mix(Color(hex: 0xE8A33D), Color(hex: 0xFFE9C4), lit * 0.6)
                : Color(white: 0.28)
            fill(color.withAlpha(0.35 + 0.65 * lit))
            let x = width * 0.06 + width * 0.88 * along
            let bar = max(1.5 * scale, peak * tall)
            drawRect(center: Vector2(x, middle), width: 2.2 * scale, height: bar * 2)
        }

        // The middle of the band, which is where a grain with no jitter at all
        // would be cut from.
        stroke(Color(hex: 0xFFE9C4))
        strokeWeight(1.6 * scale)
        let x = width * 0.06 + width * 0.88 * reading
        drawLine(x, middle - tall * 1.25, x, middle + tall * 1.25)

        noStroke()
        fill(Color(white: 0.5))
        textSize(12 * scale)
        textAlign(.center)
        drawText(String(format: "%.2f s of %.2f", reading * source.duration, source.duration),
                 at: Vector2(x, middle + tall * 1.25 + 18 * scale))
        textAlign(.left)
    }

    /// The shape one grain is cut with, read off the shipped curve rather than
    /// drawn by hand, so it cannot disagree with the sound.
    private func drawGrainShape() {
        let box = Rectangle(x: width * 0.08, y: height * 0.72,
                            width: width * 0.26, height: height * 0.14)
        noFill()
        stroke(Color(hex: 0x6FA8DC, alpha: 0.9))
        strokeWeight(2 * scale)
        drawPolyline((0...120).map { step in
            let t = Double(step) / 120
            return Vector2(box.x + box.width * t,
                           box.y + box.height * (1 - shape.level(at: t)))
        })
        noStroke()
        fill(Color(white: 0.5))
        textSize(12 * scale)
        drawText("\(cut.rawValue), \(Int(size * 1000)) ms",
                 at: Vector2(box.x, box.y + box.height + 18 * scale))
    }

    /// How many grains are sounding, which is what density and size come to.
    private func drawCount() {
        let box = Rectangle(x: width * 0.4, y: height * 0.72,
                            width: width * 0.2, height: height * 0.14)
        let count = synth.grainCount
        noStroke()
        fill(Color(white: 0.16))
        drawRect(corner: box.corner, width: box.width, height: box.height)
        fill(Color(hex: 0xE8A33D))
        let full = min(1, Double(count) / 48)
        drawRect(corner: Vector2(box.x, box.y + box.height * (1 - full)),
                 width: box.width, height: box.height * full)
        fill(Color(white: 0.5))
        textSize(12 * scale)
        drawText("\(count) grains sounding",
                 at: Vector2(box.x, box.y + box.height + 18 * scale))
    }

    /// What came out, so the cut and the sound are on one screen.
    private func drawTrace() {
        let box = Rectangle(x: width * 0.66, y: height * 0.72,
                            width: width * 0.26, height: height * 0.14)
        guard trace.count > 2 else { return }
        noFill()
        stroke(Color(hex: 0x6FA8DC, alpha: 0.8))
        strokeWeight(2 * scale)
        drawPolyline(trace.enumerated().map { index, value in
            Vector2(box.x + box.width * Double(index) / Double(max(1, trace.count - 1)),
                    box.y + box.height * (1 - min(value * 4, 1)))
        })
    }

    /// The shorter way round a loop between two places in it, since the sound
    /// comes round rather than running out.
    private func shortestWay(from a: Double, to b: Double) -> Double {
        let raw = b - a
        return raw - (raw + 0.5).rounded(.down)
    }

    /// The sound to cut up: the bundled struck bar, a tone climbing behind it,
    /// and a rattle at the end, so dragging the band somewhere is audibly
    /// somewhere else.
    private static func material() -> GrainSource {
        let bar = GrainSource.builtIn ?? GrainSource(waveform: .sawtooth, frequency: 220, seconds: 1)
        var frames = bar.frames
        let rate = bar.sampleRate
        var phase = 0.0
        for index in 0 ..< Int(1.5 * rate) {
            let along = Double(index) / (1.5 * rate)
            phase += 2 * .pi * (180 + 900 * along) / rate
            frames.append(Float(0.35 * sin(phase) * (1 - along * 0.5)))
        }
        var noise = SplitMix64(seed: 9)
        for index in 0 ..< Int(0.8 * rate) {
            let along = Double(index) / (0.8 * rate)
            let value = Double.random(in: -1 ... 1, using: &noise)
            frames.append(Float(0.3 * value * sin(along * 40)))
        }
        return GrainSource(name: "material", frames: frames, sampleRate: rate,
                           rootKey: bar.rootKey)
    }

    /// The loudest sample in each column, which is what a waveform is when
    /// there are a hundred times more samples than pixels.
    private static func peaks(of source: GrainSource, count: Int) -> [Double] {
        let frames = source.frames
        guard frames.count > count else { return frames.map { Double(abs($0)) } }
        let span = frames.count / count
        return (0..<count).map { column in
            var peak = 0.0
            for index in column * span ..< min(frames.count, (column + 1) * span) {
                peak = max(peak, Double(abs(frames[index])))
            }
            return peak
        }
    }
}
