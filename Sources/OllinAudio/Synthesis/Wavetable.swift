import Foundation

/// A row of single cycles a note is read from, one after another as the
/// `position` moves, so the sound changes shape while it sounds.
///
/// Where an oscillator traces one shape and a patch pushes a few shapes into
/// each other, a wavetable holds any shapes at all, side by side, and reads a
/// blend of the two the position lands between. Move the position while a note
/// plays and the wave itself changes, which is what makes a held note travel
/// rather than sit still.
///
/// ```swift
/// synth.wavetable = .basic                     // sine, triangle, sawtooth, square
/// synth.voice = Voice(wavetable: WavetableScan(position: 0.3))
/// synth.play("C3", for: 2)
/// ```
///
/// The table is set on the synth and the voice says where in it to read, for
/// the same reason a sampled instrument's recordings are: a voice travels to
/// the audio thread inside a note and has to be copyable a word at a time,
/// and a table is hundreds of kilobytes. Every level of the table is built
/// once, here, so playing it allocates nothing.
///
/// ### Band limits
///
/// A cycle with a corner holds harmonics past any sampling limit, and read
/// fast enough those fold back down the spectrum as a gritty ring. So each
/// frame is kept at eleven strengths, each with half the harmonics of the one
/// before, and a note reads the strongest one whose top harmonic still fits
/// under half the sample rate. A sawtooth stays a sawtooth at the top of the
/// keyboard, and every level comes from the same spectrum, so moving between
/// them is silent.
public final class Wavetable: @unchecked Sendable {

    /// Samples in one cycle, at every frame and every level.
    public static let length = 2048

    /// What the table is called, for a sketch that wants to say.
    public let name: String

    /// How many cycles it holds. `position` runs from the first to the last.
    public let frameCount: Int

    /// Levels of band limiting: level 0 holds every harmonic, and each level
    /// after it half as many as the one before, down to the fundamental alone.
    static let levelCount = 11

    /// The highest harmonic a level keeps.
    static func harmonicLimit(atLevel level: Int) -> Int {
        (length / 2) >> level
    }

    /// Every level of every frame, flat: `[level][frame][sample]`. Kept as
    /// `Float` because the read side adds and blends four of them a sample.
    private let samples: [Float]

    /// A table from the harmonic content of each frame.
    ///
    /// Each inner list is one frame's harmonics, the fundamental first: an
    /// amplitude per harmonic, every partial starting as a sine. An empty
    /// list is silence. A frame is scaled so its loudest point is 1, so a
    /// bright frame and a plain one play at the same level.
    ///
    /// ```swift
    /// Wavetable(name: "odd", harmonics: [
    ///     [1],                         // a sine
    ///     [1, 0, 1 / 3, 0, 1 / 5],     // the start of a square
    /// ])
    /// ```
    public init(name: String = "table", harmonics: [[Double]]) {
        let spectra = harmonics.map { frame -> Spectrum in
            var spectrum = Spectrum()
            for (index, amplitude) in frame.prefix(Wavetable.length / 2 - 1).enumerated() {
                // A sine partial: cosine part zero, sine part the amplitude.
                spectrum.sine[index + 1] = amplitude
            }
            return spectrum
        }
        self.name = name
        self.frameCount = max(1, spectra.count)
        self.samples = Wavetable.build(spectra.isEmpty ? [Spectrum()] : spectra)
    }

    /// A table from cycles you drew: each inner list is one cycle of samples,
    /// any length, in `-1...1`.
    ///
    /// A cycle is resampled to the table's own length and taken apart into
    /// harmonics, so a corner drawn by hand is corrected the same way a
    /// sawtooth is. A frame is scaled so its loudest point is 1.
    public init(name: String = "table", frames: [[Double]]) {
        let spectra = frames.map { cycle -> Spectrum in
            Wavetable.analyze(Wavetable.resampled(cycle))
        }
        self.name = name
        self.frameCount = max(1, spectra.count)
        self.samples = Wavetable.build(spectra.isEmpty ? [Spectrum()] : spectra)
    }

    /// A table from a rule: `shape(phase, frame)` gives the cycle's value at
    /// `phase` (`0..<1` through the cycle) for `frame` (`0...1` across the
    /// table), sampled at every point of every frame.
    ///
    /// ```swift
    /// Wavetable(name: "bend", frameCount: 8) { phase, frame in
    ///     sin(2 * .pi * pow(phase, 1 + 2 * frame))     // a sine bent harder each frame
    /// }
    /// ```
    public convenience init(name: String = "table", frameCount: Int,
                            _ shape: (Double, Double) -> Double) {
        let count = max(1, frameCount)
        let cycles = (0..<count).map { frame -> [Double] in
            let along = count > 1 ? Double(frame) / Double(count - 1) : 0
            return (0..<Wavetable.length).map { shape(Double($0) / Double(Wavetable.length), along) }
        }
        self.init(name: name, frames: cycles)
    }

    // MARK: Reading

    /// One frame's cycle, every harmonic in, for drawing it.
    public func frame(_ index: Int) -> [Double] {
        frame(index, level: 0)
    }

    /// One frame's cycle with only the harmonics up to `harmonicsUpTo` kept,
    /// which is what a high note actually reads: the strongest level whose
    /// top harmonic still fits.
    public func frame(_ index: Int, harmonicsUpTo limit: Int) -> [Double] {
        frame(index, level: Wavetable.level(forHarmonicsUpTo: limit))
    }

    /// The cycle a note at `position` reads: the blend of the two frames the
    /// position lands between, every harmonic in.
    public func cycle(at position: Double) -> [Double] {
        (0..<Wavetable.length).map { index in
            Double(sample(position: position, phase: Double(index) / Double(Wavetable.length), level: 0))
        }
    }

    func frame(_ index: Int, level: Int) -> [Double] {
        let frame = min(max(0, index), frameCount - 1)
        let level = min(max(0, level), Wavetable.levelCount - 1)
        let start = (level * frameCount + frame) * Wavetable.length
        return samples[start ..< start + Wavetable.length].map(Double.init)
    }

    /// The level a note should read when its harmonics may reach `limit`.
    static func level(forHarmonicsUpTo limit: Int) -> Int {
        var level = 0
        while level + 1 < levelCount, harmonicLimit(atLevel: level) > max(1, limit) {
            level += 1
        }
        return level
    }

    /// The level a note at `increment` cycles per sample should read: the
    /// strongest whose top harmonic stays under half the sample rate.
    static func level(forIncrement increment: Double) -> Int {
        guard increment > 0 else { return 0 }
        let fits = Int(0.5 / increment)
        return level(forHarmonicsUpTo: fits)
    }

    /// One sample: the frames either side of `position` read at `phase`
    /// (`0..<1` through the cycle) at `level`, blended both ways.
    @inline(__always)
    func sample(position: Double, phase: Double, level: Int) -> Float {
        let count = Wavetable.length
        let span = Double(frameCount - 1)
        let along = min(max(0, position), 1) * span
        let lower = Int(along)
        let upper = min(lower + 1, frameCount - 1)
        let between = Float(along - Double(lower))

        let scaled = phase * Double(count)
        let first = Int(scaled) & (count - 1)
        let second = (first + 1) & (count - 1)
        let fraction = Float(scaled - Double(Int(scaled)))

        let base = level * frameCount * count
        let a = base + lower * count
        let b = base + upper * count
        let fromLower = samples[a + first] + (samples[a + second] - samples[a + first]) * fraction
        let fromUpper = samples[b + first] + (samples[b + second] - samples[b + first]) * fraction
        return fromLower + (fromUpper - fromLower) * between
    }

    // MARK: Building

    /// One frame's harmonics: a cosine and a sine part per harmonic, the
    /// fundamental at index 1 and nothing at 0.
    struct Spectrum {
        var cosine = [Double](repeating: 0, count: Wavetable.length / 2)
        var sine = [Double](repeating: 0, count: Wavetable.length / 2)
    }

    /// Every level of every frame from its spectrum, each frame scaled so the
    /// full level's loudest point is 1 and every level of it shares that scale.
    private static func build(_ spectra: [Spectrum]) -> [Float] {
        let count = length
        let frames = spectra.count
        var out = [Float](repeating: 0, count: levelCount * frames * count)
        // One cycle of sine, read at (harmonic × sample) modulo the length,
        // so a partial costs a lookup rather than a sine per sample.
        let table = (0..<count).map { sin(2 * Double.pi * Double($0) / Double(count)) }
        let quarter = count / 4

        for (frame, spectrum) in spectra.enumerated() {
            // The weakest level holds the fundamental alone. Each level below
            // it adds the harmonics between its limit and the next one's, so
            // every harmonic is summed exactly once across the whole stack.
            var cycle = [Double](repeating: 0, count: count)
            var highest = 0
            for level in stride(from: levelCount - 1, through: 0, by: -1) {
                // The spectrum stops one short of half the length (the
                // bin at exactly half is the sampling limit itself).
                let limit = min(harmonicLimit(atLevel: level), count / 2 - 1)
                if limit > highest {
                    for harmonic in (highest + 1) ... limit {
                        let s = spectrum.sine[harmonic], c = spectrum.cosine[harmonic]
                        if s == 0 && c == 0 { continue }
                        for index in 0..<count {
                            let at = (harmonic * index) & (count - 1)
                            cycle[index] += s * table[at] + c * table[(at + quarter) & (count - 1)]
                        }
                    }
                    highest = limit
                }
                let start = (level * frames + frame) * count
                for index in 0..<count { out[start + index] = Float(cycle[index]) }
            }
            // Level 0 is the full cycle; scale every level of this frame by
            // its peak so the frames play alike and the levels agree.
            let peak = cycle.reduce(0) { max($0, abs($1)) }
            guard peak > 1e-9 else { continue }
            let scale = Float(1 / peak)
            for level in 0..<levelCount {
                let start = (level * frames + frame) * count
                for index in 0..<count { out[start + index] *= scale }
            }
        }
        return out
    }

    /// A drawn cycle brought to the table's length by reading between its
    /// samples.
    private static func resampled(_ cycle: [Double]) -> [Double] {
        guard cycle.count >= 2 else { return [Double](repeating: cycle.first ?? 0, count: length) }
        return (0..<length).map { index in
            let along = Double(index) / Double(length) * Double(cycle.count)
            let lower = Int(along) % cycle.count
            let upper = (lower + 1) % cycle.count
            let fraction = along - Double(Int(along))
            return cycle[lower] + (cycle[upper] - cycle[lower]) * fraction
        }
    }

    /// The harmonics of a cycle: a plain discrete Fourier transform through
    /// the same sine table the build reads, so the two agree exactly.
    private static func analyze(_ cycle: [Double]) -> Spectrum {
        let count = length
        let table = (0..<count).map { sin(2 * Double.pi * Double($0) / Double(count)) }
        let quarter = count / 4
        var spectrum = Spectrum()
        let scale = 2 / Double(count)
        for harmonic in 1 ..< count / 2 {
            var s = 0.0, c = 0.0
            for index in 0..<count {
                let at = (harmonic * index) & (count - 1)
                s += cycle[index] * table[at]
                c += cycle[index] * table[(at + quarter) & (count - 1)]
            }
            spectrum.sine[harmonic] = s * scale
            spectrum.cosine[harmonic] = c * scale
        }
        return spectrum
    }

    // MARK: The built-in tables

    /// The four plain shapes in a row: sine, triangle, sawtooth, square. The
    /// position walks from the purest to the brightest.
    public static let basic: Wavetable = {
        let top = length / 2 - 1
        let sine = [1.0]
        let triangle = (1...top).map { h -> Double in
            h % 2 == 1 ? (h % 4 == 1 ? 1 : -1) * 8 / (Double.pi * Double.pi * Double(h * h)) : 0
        }
        let sawtooth = (1...top).map { h -> Double in
            (h % 2 == 1 ? 1 : -1) * 2 / (Double.pi * Double(h))
        }
        let square = (1...top).map { h -> Double in
            h % 2 == 1 ? 4 / (Double.pi * Double(h)) : 0
        }
        return Wavetable(name: "basic", harmonics: [sine, triangle, sawtooth, square])
    }()

    /// A pulse narrowing across the table, from a square at the start to a
    /// thin spike at the end: the classic width sweep, as frames.
    public static let pulse: Wavetable = {
        let top = length / 2 - 1
        let widths = [0.5, 0.35, 0.22, 0.12, 0.05]
        let frames = widths.map { width in
            (1...top).map { h in 2 / (Double.pi * Double(h)) * sin(Double.pi * Double(h) * width) }
        }
        return Wavetable(name: "pulse", harmonics: frames)
    }()

    /// Five vowels, a, e, i, o, u, as the harmonics a voice shapes them into,
    /// so a note scanned across the table sings through them.
    public static let vowels: Wavetable = {
        // Each vowel is three resonances of the mouth: where they sit, in Hz,
        // how wide they are, and how loud, worked out for a fundamental near
        // 110 Hz. A little of every harmonic underneath keeps the buzz of a
        // voice under the vowel.
        let formants: [[(hz: Double, width: Double, gain: Double)]] = [
            [(800, 80, 1), (1150, 90, 0.5), (2900, 120, 0.25)],
            [(350, 60, 1), (2000, 100, 0.35), (2800, 120, 0.2)],
            [(270, 60, 1), (2140, 90, 0.25), (2950, 100, 0.15)],
            [(450, 70, 1), (800, 80, 0.6), (2830, 100, 0.2)],
            [(325, 50, 1), (700, 60, 0.4), (2700, 170, 0.1)],
        ]
        let fundamental = 110.0
        let frames = formants.map { vowel in
            (1...40).map { h -> Double in
                let hz = Double(h) * fundamental
                var amplitude = 0.02 / Double(h)
                for formant in vowel {
                    let away = (hz - formant.hz) / formant.width
                    amplitude += formant.gain * exp(-0.5 * away * away)
                }
                return amplitude
            }
        }
        return Wavetable(name: "vowels", harmonics: frames)
    }()
}

/// Where in a wavetable a note reads, and how that moves while it sounds.
///
/// Small and made only of numbers, because this is the part that travels to
/// the audio thread inside a note. The table itself stays on the ``Synth``.
///
/// ```swift
/// WavetableScan(position: 0.3)                                  // held still
/// WavetableScan(position: 1, sweep: -1, envelope: .percussive)  // bright, then settling
/// ```
public struct WavetableScan: Sendable, Hashable, Codable {
    /// Where in the table the note reads, `0` the first frame to `1` the
    /// last, blending between the two it lands between.
    public var position: Double

    /// How far `envelope` moves the position, `-1...1`, added to `position`
    /// as the envelope rises and taken back as it falls. Zero holds the
    /// position still. Negative moves toward the first frame.
    public var sweep: Double

    /// The shape of that movement. Ignored when `sweep` is zero.
    public var envelope: Envelope

    public init(position: Double = 0, sweep: Double = 0, envelope: Envelope = .percussive) {
        self.position = min(max(0, position), 1)
        self.sweep = min(max(-1, sweep), 1)
        self.envelope = envelope
    }

    /// A note read at one place in the table and kept there.
    public static func at(_ position: Double) -> WavetableScan {
        WavetableScan(position: position)
    }
}

extension Voice {
    /// A voice read from the synth's wavetable.
    ///
    /// Which table is ``Synth/wavetable``, set separately, because a table is
    /// far too large to travel inside a note. This says only where in it the
    /// note reads, and how that moves.
    public init(
        wavetable: WavetableScan,
        envelope: Envelope = .standard,
        filter: Filter? = nil,
        detune: Double = 0,
        gain: Double = 0.8
    ) {
        self.init(source: .wavetable(wavetable), envelope: envelope, filter: filter,
                  detune: detune, gain: gain)
    }

    /// Where this voice reads its wavetable, or nil if it is not one.
    public var wavetable: WavetableScan? {
        get {
            if case .wavetable(let scan) = source { return scan }
            return nil
        }
        set { if let newValue { source = .wavetable(newValue) } }
    }

    /// Bright at the front and settling as it goes: the note jumps to the far
    /// end of the table as it strikes and slides back toward the first frame
    /// while it sounds. On the `.basic` table that is a square softening into
    /// a sine.
    public static let morph = Voice(
        wavetable: WavetableScan(position: 0, sweep: 1,
                                 envelope: Envelope(attack: 0.005, decay: 0.7, sustain: 0.15,
                                                    release: 0.3)),
        envelope: Envelope(attack: 0.01, decay: 0.3, sustain: 0.7, release: 0.35),
        gain: 0.7
    )
}
