import Foundation
import Ollin

/// Numbers read out as notes.
///
/// A series of measurements, a row of a terrain, a line across a picture: any
/// of them becomes something to listen to by spreading its values over a range
/// of pitch. Snapped through a ``Scale`` the result stays in key, so a reading
/// can be music rather than only a signal.
///
/// ```swift
/// let readings = Sonification(table, column: "temperature",
///                             in: Scale(.minorPentatonic, root: "A3"))
///
/// override func draw() {
///     for step in counter.steps(at: time) {
///         if let note = readings[step] { synth.play(note, tempo: tempo) }
///     }
/// }
/// ```
///
/// Like everything else in this tier it answers a step number and owns no
/// clock, so the same read-out can be driven by `time`, by a detected beat, or
/// by a `TempoClock`.
///
/// It is also a way to hear a drawing. A sketch that plots a column can read
/// the same column out loud with no second copy of the data, which is how a
/// picture reaches someone who is not looking at it.
///
/// ### How the mapping is made
///
/// Two choices are worth knowing about, because both are easy to get wrong and
/// neither is what you would write first.
///
/// Pitch is spread evenly in **semitones**, not in hertz. Hearing is
/// logarithmic: the step from 220 to 440 Hz and the step from 440 to 880 sound
/// like the same distance, though one is twice the other. Spreading a series
/// evenly in hertz crushes the whole bottom of the data into a few notes.
///
/// Loudness is spread evenly in **decibels**, for the same reason. Loudness is
/// the weaker of the two, though, and deliberately does nothing unless asked:
/// how loud something sounds depends on how high it is as well as how strong
/// it is, so a series read out on loudness alone is read out through a
/// distortion. Reach for pitch first and use ``amplified(by:)`` for a second
/// series, not to say the same thing twice.
public struct Sonification: Sendable, Equatable {

    /// Which way round the reading goes.
    public enum Polarity: String, Sendable, Hashable, CaseIterable, Codable {
        /// More is higher, which is what a listener expects of a quantity.
        case positive
        /// More is lower. The right way round for a size, since a small thing
        /// is the one that rings high.
        case negative
    }

    /// How the two ends of the data are decided.
    public enum Bounds: Sendable, Equatable {
        /// The smallest and largest values there are.
        case extremes
        /// The same, after setting aside a fraction of the data at each end, so
        /// one wild reading cannot flatten everything else into a single note.
        case robust(ignoring: Double)
        /// A range you name, whatever the data does. The form to use when two
        /// read-outs have to be comparable with each other.
        case fixed(ClosedRange<Double>)
    }

    /// The numbers being read, in order.
    public var values: [Double]
    /// Which values land at the bottom and top of the pitch range. Values
    /// outside it are held at the ends rather than running off.
    public var valueDomain: ClosedRange<Double>
    /// The span of pitch the data is spread over.
    public var pitches: ClosedRange<Pitch>
    /// The notes the reading is allowed to land on, or nil to use every
    /// semitone between the ends.
    public var scale: Scale?
    /// Which way round the reading goes.
    public var polarity: Polarity
    /// How long each note lasts, in beats.
    public var noteLength: Double

    /// A second series read out as loudness, or nil to play everything at full
    /// level. See ``amplified(by:)``.
    public var loudness: [Double]?
    /// Which values of that second series land at the ends of ``levels``.
    public var loudnessDomain: ClosedRange<Double>
    /// The quietest and loudest a note may be, in decibels relative to full
    /// level. Spread in decibels because that is the unit loudness is heard in.
    public var levels: ClosedRange<Double>

    // MARK: Making one

    /// Reads a series of numbers.
    ///
    /// - Parameters:
    ///   - values: the numbers, in the order they should be heard.
    ///   - scale: the notes to land on, or nil for every semitone.
    ///   - pitches: the span the data is spread over. Three octaves by default,
    ///     which is wide enough to hear a shape in and not so wide that the top
    ///     of it is shrill.
    ///   - bounds: how the two ends of the data are decided.
    ///   - polarity: which way round the reading goes.
    ///   - noteLength: how long each note lasts, in beats.
    public init(
        _ values: [Double],
        in scale: Scale? = nil,
        pitches: ClosedRange<Pitch> = "C3"..."C6",
        bounds: Bounds = .extremes,
        polarity: Polarity = .positive,
        noteLength: Double = 0.25
    ) {
        self.values = values
        self.scale = scale
        self.pitches = pitches
        self.polarity = polarity
        self.noteLength = max(0.001, noteLength)
        self.valueDomain = Sonification.domain(of: values, by: bounds)
        self.loudness = nil
        self.loudnessDomain = 0...1
        self.levels = -18...0
    }

    /// Reads a column of a table.
    ///
    /// Cells that are not numbers are dropped, the way `numbers(_:)` drops
    /// them, so a gap in the data is a note that is not played rather than a
    /// note at zero.
    public init(
        _ table: Table, column: String,
        in scale: Scale? = nil,
        pitches: ClosedRange<Pitch> = "C3"..."C6",
        bounds: Bounds = .extremes,
        polarity: Polarity = .positive,
        noteLength: Double = 0.25
    ) {
        self.init(table.numbers(column), in: scale, pitches: pitches,
                  bounds: bounds, polarity: polarity, noteLength: noteLength)
    }

    /// Reads one row of a terrain, left to right.
    ///
    /// A row of a heightfield is a cross-section, so this is the ground's
    /// profile read out as a tune: hills go up.
    public init(
        _ field: Heightfield, row: Int,
        in scale: Scale? = nil,
        pitches: ClosedRange<Pitch> = "C3"..."C6",
        bounds: Bounds = .extremes,
        polarity: Polarity = .positive,
        noteLength: Double = 0.25
    ) {
        let y = min(max(row, 0), field.rows - 1)
        let values = (0 ..< field.columns).map { field[$0, y] }
        self.init(values, in: scale, pitches: pitches,
                  bounds: bounds, polarity: polarity, noteLength: noteLength)
    }

    /// Reads one column of a terrain, top to bottom.
    public init(
        _ field: Heightfield, column: Int,
        in scale: Scale? = nil,
        pitches: ClosedRange<Pitch> = "C3"..."C6",
        bounds: Bounds = .extremes,
        polarity: Polarity = .positive,
        noteLength: Double = 0.25
    ) {
        let x = min(max(column, 0), field.columns - 1)
        let values = (0 ..< field.rows).map { field[x, $0] }
        self.init(values, in: scale, pitches: pitches,
                  bounds: bounds, polarity: polarity, noteLength: noteLength)
    }

    /// Reads a straight line across a terrain, in normalized coordinates.
    ///
    /// The line is sampled at `count` evenly spaced points, so it can run at
    /// any angle across the field rather than along the grid.
    public init(
        _ field: Heightfield, from start: Vector2, to end: Vector2, count: Int,
        in scale: Scale? = nil,
        pitches: ClosedRange<Pitch> = "C3"..."C6",
        bounds: Bounds = .extremes,
        polarity: Polarity = .positive,
        noteLength: Double = 0.25
    ) {
        let steps = max(2, count)
        let values = (0 ..< steps).map { index -> Double in
            let t = Double(index) / Double(steps - 1)
            let point = start + (end - start) * t
            return field.value(u: point.x, v: point.y)
        }
        self.init(values, in: scale, pitches: pitches,
                  bounds: bounds, polarity: polarity, noteLength: noteLength)
    }

    /// Reads one row of a picture, left to right, as brightness.
    ///
    /// Brightness is weighed the way the eye weighs it, so a pure blue reads
    /// far darker than a green of the same numeric size. A fully transparent
    /// pixel reads as black.
    ///
    /// A picture living on the GPU has no pixels to read on this side, and
    /// gives an empty reading; call `snapshot()` first.
    public init(
        _ image: Image, row: Int,
        in scale: Scale? = nil,
        pitches: ClosedRange<Pitch> = "C3"..."C6",
        bounds: Bounds = .extremes,
        polarity: Polarity = .positive,
        noteLength: Double = 0.25
    ) {
        let y = min(max(row, 0), max(0, image.height - 1))
        let values = (0 ..< image.width).map { image[$0, y].luminance }
        self.init(values, in: scale, pitches: pitches,
                  bounds: bounds, polarity: polarity, noteLength: noteLength)
    }

    /// Reads one column of a picture, top to bottom, as brightness.
    public init(
        _ image: Image, column: Int,
        in scale: Scale? = nil,
        pitches: ClosedRange<Pitch> = "C3"..."C6",
        bounds: Bounds = .extremes,
        polarity: Polarity = .positive,
        noteLength: Double = 0.25
    ) {
        let x = min(max(column, 0), max(0, image.width - 1))
        let values = (0 ..< image.height).map { image[x, $0].luminance }
        self.init(values, in: scale, pitches: pitches,
                  bounds: bounds, polarity: polarity, noteLength: noteLength)
    }

    // MARK: Reading it

    /// How many notes there are to play.
    public var count: Int { values.count }

    /// Whether there is nothing to read.
    public var isEmpty: Bool { values.isEmpty }

    /// The note at a step, or nil past the end.
    public subscript(step: Int) -> Note? { note(at: step) }

    /// The note at a step, or nil past the end.
    public func note(at step: Int) -> Note? {
        guard step >= 0, step < values.count else { return nil }
        return Note(pitch(for: values[step]),
                    velocity: velocity(at: step),
                    length: noteLength)
    }

    /// The whole reading at once, for a phrase a sketch holds on to.
    public func notes() -> [Note] {
        (0 ..< count).compactMap { note(at: $0) }
    }

    /// Where one value lands, whether or not it is in the data.
    ///
    /// The way to sound anything on the same footing as the reading: a
    /// threshold, an average, the value under the mouse.
    public func pitch(for value: Double) -> Pitch {
        let span = valueDomain.upperBound - valueDomain.lowerBound
        var t = span > 1e-12 ? (value - valueDomain.lowerBound) / span : 0.5
        t = min(max(t, 0), 1)
        if polarity == .negative { t = 1 - t }

        // Spread evenly in semitones rather than in hertz, because a semitone
        // is what a listener hears as a step of the same size wherever it is.
        let low = pitches.lowerBound.midi, high = pitches.upperBound.midi
        let landed = Pitch(low + (high - low) * t)
        return scale?.snap(landed) ?? landed
    }

    /// How hard the note at a step is struck.
    public func velocity(at step: Int) -> Double {
        guard let loudness, step >= 0, step < loudness.count else { return 1 }
        let span = loudnessDomain.upperBound - loudnessDomain.lowerBound
        var t = span > 1e-12 ? (loudness[step] - loudnessDomain.lowerBound) / span : 1
        t = min(max(t, 0), 1)
        // Spread in decibels, then turned into the 0...1 a note is struck at.
        let decibels = levels.lowerBound + (levels.upperBound - levels.lowerBound) * t
        return min(max(pow(10, decibels / 20), 0), 1)
    }

    /// A note sounding one value of the data, to be played alongside the
    /// reading as a fixed point to hear the rest against.
    ///
    /// Without one a listener has to have absolute pitch to know what any note
    /// means. With one, a reading is heard as above or below something, which
    /// is the whole difference between a sound and a measurement. It is the
    /// grid line of an ordinary chart.
    public func reference(at value: Double, velocity: Double = 0.5) -> Note {
        Note(pitch(for: value), velocity: velocity, length: noteLength)
    }

    // MARK: Changing it

    /// The same reading with a second series read out as loudness.
    ///
    /// The series is lined up with the first by position, so entry 3 of one is
    /// heard at the same moment as entry 3 of the other.
    public func amplified(
        by series: [Double], bounds: Bounds = .extremes,
        levels: ClosedRange<Double> = -18...0
    ) -> Sonification {
        var copy = self
        copy.loudness = series
        copy.loudnessDomain = Sonification.domain(of: series, by: bounds)
        copy.levels = levels
        return copy
    }

    /// The same reading turned the other way up.
    public func inverted() -> Sonification {
        var copy = self
        copy.polarity = polarity == .positive ? .negative : .positive
        return copy
    }

    // MARK: Working out the ends

    /// The two values that land at the ends of the pitch range.
    static func domain(of values: [Double], by bounds: Bounds) -> ClosedRange<Double> {
        switch bounds {
        case .fixed(let range):
            return range
        case .extremes:
            guard let low = values.min(), let high = values.max() else { return 0...1 }
            return low <= high ? low...high : high...low
        case .robust(let ignoring):
            guard !values.isEmpty else { return 0...1 }
            let fraction = min(max(ignoring, 0), 0.49)
            let sorted = values.sorted()
            let low = quantile(sorted, fraction)
            let high = quantile(sorted, 1 - fraction)
            return low <= high ? low...high : high...low
        }
    }

    /// The value a fraction of the way through a sorted series, interpolating
    /// between the two readings it falls between.
    private static func quantile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let position = min(max(fraction, 0), 1) * Double(sorted.count - 1)
        let index = Int(position.rounded(.down))
        let next = min(index + 1, sorted.count - 1)
        return sorted[index] + (sorted[next] - sorted[index]) * (position - Double(index))
    }
}

// MARK: - Playing one

public extension Synth {
    /// Plays one step of a reading, if there is one there.
    ///
    /// ```swift
    /// for step in counter.steps(at: time) {
    ///     synth.play(readings, step: step, tempo: tempo)
    /// }
    /// ```
    func play(_ sonification: Sonification, step: Int, tempo: Double = 120) {
        guard let note = sonification.note(at: step) else { return }
        play(note, tempo: tempo)
    }
}
