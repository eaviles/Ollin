import Foundation

/// One grain that is currently sounding.
///
/// Plain numbers in memory the renderer owns, for the reason every model here
/// holds its state that way: the render thread writes this, and an array is one
/// value with one owner that could decide to copy itself.
struct GrainSlot {
    /// Where the read head is in the source, in samples, as a fraction.
    var position = 0.0
    /// How far it moves per output sample, which is what the grain's pitch is.
    var step = 1.0
    /// How far through its own envelope the grain is, `0..<1`.
    var phase = 0.0
    /// How much of the envelope one output sample covers.
    var phaseStep = 1.0
    var gainLeft = 1.0
    var gainRight = 1.0
}

/// One grain cloud's running state: a small pile of read heads, each with its
/// own pitch, its own place in the source, and its own envelope, plus the one
/// position they are all cut from as it travels.
///
/// The source is held by the synth rather than copied here, exactly as a
/// sampled voice holds its instrument. Set before the note starts and only read
/// afterwards.
struct GrainVoice {
    /// How many grains one note may have sounding at once.
    ///
    /// Past this a new grain is dropped rather than waited for, the same
    /// bargain the event ring makes: a cloud dense enough to run out is already
    /// a texture, and one missing grain in it cannot be heard, where an
    /// allocation on the render thread would be.
    static let maxGrains = 48

    static func memoryNeeded() -> Int { maxGrains }

    private let grains: UnsafeMutablePointer<GrainSlot>
    /// Sounding grains, packed at the front of the buffer.
    private var count = 0

    private var source: GrainSource?
    private var cloud = GrainCloud()
    private var sampleRate = 44100.0
    /// Where in the source the note is reading, in samples, as a fraction.
    /// Every grain is cut from here plus its own jitter.
    private var readHead = 0.0
    /// How far that travels per output sample.
    private var travel = 0.0
    /// Output samples until the next grain starts, as a fraction.
    private var untilNext = 0.0
    /// The pitch the note sounds at, as a step through the source.
    private var baseStep = 1.0
    /// Alternate grains take the voice's detune, so two streams a fraction
    /// apart beat against each other the way two oscillators do.
    private var detune = 0.0
    private var alternate = false
    private var random: UInt64
    /// The right channel of the last sample, when the cloud pans.
    private(set) var right = 0.0
    /// Whether this cloud throws its grains to the sides at all, read once at
    /// the note rather than a comparison a sample.
    private var pans = false
    private var finished = true

    init(buffer: UnsafeMutablePointer<GrainSlot>, seed: UInt64) {
        self.grains = buffer
        self.random = seed | 1
    }

    /// Whether this voice pans its grains, so the renderer knows whether the
    /// block needs two channels at all.
    var isPanning: Bool { !finished && pans }

    /// How many grains this voice has sounding, for the renderer to publish.
    var soundingCount: Int { count }

    mutating func reset() {
        source = nil
        count = 0
        right = 0
        pans = false
        finished = true
    }

    /// Sets up a note.
    mutating func start(source: GrainSource, cloud: GrainCloud, pitch: Double,
                        detune: Double, sampleRate: Double, seed: UInt64) {
        reset()
        guard !source.isEmpty else { return }
        self.source = source
        self.cloud = cloud
        self.sampleRate = max(1, sampleRate)
        self.detune = detune
        self.alternate = false
        self.pans = cloud.panSpread > 0
        // The cloud's own seed rather than the voice's alone, so the same
        // settings timingJitter the same way wherever they are played, and a
        // different seed is a different cloud of the same shape.
        self.random = (seed &+ UInt64(bitPattern: Int64(cloud.seed)) &* 0x9E37_79B9_7F4A_7C15) | 1
        readHead = min(max(0, cloud.position), 1) * Double(source.frames.count)
        travel = cloud.speed * source.sampleRate / self.sampleRate
        retune(semitones: pitch - Double(source.rootKey))
        // The first grain starts on the first sample, so a note speaks at once
        // however sparse the cloud is.
        untilNext = 0
        finished = false
    }

    /// Moves a sounding note to another pitch: grains started from here on are
    /// read faster or slower. The ones already going keep their own step, the
    /// way a note already sounding keeps the recording it started on.
    mutating func retune(semitones: Double) {
        guard let source else { return }
        baseStep = pow(2, semitones / 12) * (source.sampleRate / sampleRate)
    }

    /// One sample, with the position moved on and any grain that is due
    /// started. `scrub` moves the reading through the source without moving
    /// the note, in source lengths.
    mutating func next(scrub: Double) -> Double {
        guard !finished, let source else { right = 0; return 0 }
        let frames = source.frames
        let total = Double(frames.count)

        if untilNext <= 0 { startGrain(total: total, scrub: scrub) }
        untilNext -= 1

        var left = 0.0
        var rightSum = 0.0
        var index = 0
        while index < count {
            let grain = grains[index]
            let value = GrainVoice.read(frames, at: grain.position)
                * GrainVoice.window(cloud.shape, at: grain.phase)
            if pans {
                left += value * grain.gainLeft
                rightSum += value * grain.gainRight
            } else {
                left += value
            }

            var moved = grain
            moved.position += moved.step
            moved.phase += moved.phaseStep
            if moved.phase >= 1 {
                // Finished: the last sounding grain takes its place, so the
                // sample loop only ever walks the grains that are sounding.
                count -= 1
                if index != count { grains[index] = grains[count] }
                continue
            }
            // A grain that runs off either end wraps, because a cloud loops:
            // stopping instead would cut its envelope and click.
            if moved.position >= total { moved.position -= total }
            else if moved.position < 0 { moved.position += total }
            grains[index] = moved
            index += 1
        }

        // One step is a handful of samples at most, so the position comes
        // round with a subtraction rather than a remainder.
        readHead += travel
        if readHead >= total { readHead -= total }
        else if readHead < 0 { readHead += total }

        right = pans ? rightSum : left
        return left
    }

    /// Cuts one grain and schedules the next.
    private mutating func startGrain(total: Double, scrub: Double) {
        let mean = sampleRate / max(0.1, cloud.density)
        // At no timingJitter the grains are on a strict clock, which is heard as a
        // pitch at the density. At full timingJitter the gap is exponential, which
        // is what independent arrivals look like, and the average is the same
        // either way, so timingJitter changes the texture and not the loudness.
        let gap: Double
        if cloud.timingJitter <= 0 {
            gap = mean
        } else {
            let spread = -log(max(1e-9, uniform()))
            gap = mean * (1 - cloud.timingJitter + cloud.timingJitter * spread)
        }
        untilNext += max(1, gap)

        guard count < GrainVoice.maxGrains else { return }

        var grain = GrainSlot()
        var start = readHead + scrub * total
        if cloud.positionJitter > 0 {
            start += (uniform() * 2 - 1) * cloud.positionJitter * total
        }
        // Wrapped rather than clamped, for the reason the read is: a cloud
        // reaching past the end comes round again.
        start = start.truncatingRemainder(dividingBy: total)
        if start < 0 { start += total }
        grain.position = start

        var step = baseStep
        if cloud.pitchSpread > 0 {
            step *= pow(2, (uniform() * 2 - 1) * cloud.pitchSpread / 12)
        }
        if detune != 0 {
            // Two interleaved streams a fraction apart: overlapping grains
            // from the two beat against each other exactly as two detuned
            // oscillators do, at no extra cost.
            if alternate { step *= pow(2, detune / 12) }
            alternate.toggle()
        }
        grain.step = step

        let length = max(2.0, cloud.size * sampleRate)
        grain.phase = 0
        grain.phaseStep = 1 / length

        if cloud.panSpread > 0 {
            // Equal power, so a grain thrown to one side is as loud as one in
            // the middle, and scaled so the middle is exactly unity: a cloud
            // that spreads nothing is the same level as one that does.
            let pan = (uniform() * 2 - 1) * cloud.panSpread
            let angle = (pan + 1) * Double.pi / 4
            grain.gainLeft = cos(angle) * 1.414_213_562_373_095_1
            grain.gainRight = sin(angle) * 1.414_213_562_373_095_1
        }

        grains[count] = grain
        count += 1
    }

    /// `0..<1`, from the voice's own generator rather than the sketch's, so a
    /// cloud cannot shift any other roll a sketch makes and an offline render
    /// of the same notes produces the same samples.
    private mutating func uniform() -> Double {
        random &+= 0x9E37_79B9_7F4A_7C15
        var z = random
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Between two samples, because a grain moved off its recorded pitch
    /// almost never lands on one.
    @inline(__always)
    static func read(_ frames: [Float], at position: Double) -> Double {
        let whole = Int(position)
        guard whole >= 0, whole < frames.count else { return 0 }
        let next = whole + 1 < frames.count ? whole + 1 : 0
        let fraction = position - Double(whole)
        return Double(frames[whole]) * (1 - fraction) + Double(frames[next]) * fraction
    }

    // MARK: The envelope

    /// How many points one shape is kept at. A grain envelope is read once per
    /// sample per sounding grain, so it is a table rather than a cosine.
    static let windowLength = 1024

    /// Every shape, one after another, each with a guard point at the end so
    /// the read between two points needs no wrap.
    ///
    /// Raw memory rather than an array because this is read once per sample per
    /// sounding grain, and an array read on the render thread is a retain.
    /// Taken once, at ``warm()``, before any note can reach it.
    nonisolated(unsafe) private static let windows: UnsafeMutablePointer<Double> = {
        let count = windowLength
        let shapes = GrainShape.allCases
        let out = UnsafeMutablePointer<Double>.allocate(capacity: shapes.count * (count + 1))
        out.initialize(repeating: 0, count: shapes.count * (count + 1))
        for shape in shapes {
            let base = shape.tableIndex * (count + 1)
            var peak = 0.0
            for point in 0...count {
                let t = Double(point) / Double(count)
                let value = GrainVoice.windowValue(shape, at: t)
                out[base + point] = value
                peak = max(peak, value)
            }
            guard peak > 1e-9 else { continue }
            for point in 0...count { out[base + point] /= peak }
        }
        return out
    }()

    /// Builds the envelope table, if it has not been built. Called from the
    /// renderer's own setup, because building it on the render thread would
    /// be an allocation there.
    static func warm() { _ = windows }

    /// One shape's value at `t`, `0...1` through the grain, before it is
    /// brought to a peak of one.
    private static func windowValue(_ shape: GrainShape, at t: Double) -> Double {
        switch shape {
        case .bell:
            return 0.5 - 0.5 * cos(2 * Double.pi * t)
        case .gaussian:
            // Truncated at a little over three deviations and lifted so the
            // ends reach zero, or the grain would begin and end on a step.
            let sigma = 0.15
            let away = (t - 0.5) / sigma
            let edge = exp(-0.5 * pow(0.5 / sigma, 2))
            return max(0, (exp(-0.5 * away * away) - edge) / (1 - edge))
        case .triangle:
            return 1 - abs(2 * t - 1)
        case .plateau:
            // A flat middle between two raised-cosine ramps, so the middle of
            // the grain is the source untouched and neither end has a corner.
            let ramp = 0.15
            if t < ramp { return 0.5 - 0.5 * cos(Double.pi * t / ramp) }
            if t > 1 - ramp { return 0.5 - 0.5 * cos(Double.pi * (1 - t) / ramp) }
            return 1
        case .tick:
            // A very short rise into an exponential fall, with the fall's own
            // floor taken out so the grain ends at nothing rather than at a
            // hundredth: a step that small at the end of a grain is still a
            // click, and there are a great many grains.
            let floor = exp(-6.0)
            return (1 - exp(-t / 0.004)) * (exp(-6 * t) - floor) / (1 - floor)
        case .swell:
            return GrainVoice.windowValue(.tick, at: 1 - t)
        }
    }

    /// The shape's value at `phase`, read between the two points either side.
    @inline(__always)
    static func window(_ shape: GrainShape, at phase: Double) -> Double {
        let count = windowLength
        let base = shape.tableIndex * (count + 1)
        let along = min(max(0, phase), 1) * Double(count)
        let lower = Int(along)
        guard lower < count else { return windows[base + count] }
        let fraction = along - Double(lower)
        let a = windows[base + lower]
        return a + (windows[base + lower + 1] - a) * fraction
    }
}

extension GrainShape {
    /// Where this shape's points start in the table. A switch rather than
    /// `allCases.firstIndex`, which searches.
    var tableIndex: Int {
        switch self {
        case .bell: return 0
        case .gaussian: return 1
        case .triangle: return 2
        case .plateau: return 3
        case .tick: return 4
        case .swell: return 5
        }
    }
}
