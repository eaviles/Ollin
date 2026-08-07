import AVFoundation
import Foundation
import Ollin

/// An instrument made of recordings.
///
/// Everything else a `Synth` can play is worked out as it goes. This is the
/// other way: someone recorded the thing, and playing a note means finding the
/// nearest recording and moving it to the pitch asked for.
///
/// ```swift
/// let piano = SampledInstrument(sfz: "Piano.sfz", in: .module)
/// synth.instrument = piano
/// synth.voice = Voice(sampled: Sampled(), envelope: .plucked)
/// synth.play("C4", for: 1.5)
/// ```
///
/// Ollin bundles one small instrument (``builtin``) so a sketch can hear this
/// work without downloading anything. For real instruments, see the sources
/// listed in the [documentation](doc:); the format to look for is **SFZ**,
/// which is what most freely licensed libraries ship in.
///
/// ### Why this is a reference rather than a value
///
/// Everything else a voice can be built from is a handful of numbers, because
/// a `Voice` travels to the audio thread inside a note and has to be copyable
/// a word at a time. Recordings are megabytes and live on the heap, so they
/// cannot ride along. An instrument is held by the `Synth` instead, and a note
/// carries only the settings for playing it. That is why ``Synth/instrument``
/// is set separately from ``Synth/voice`` rather than being part of it.
public final class SampledInstrument: @unchecked Sendable {

    /// One recording, and the notes it answers to.
    struct Zone {
        /// The samples themselves, one channel, at `sampleRate`.
        var frames: [Float]
        var sampleRate: Double
        var lowKey: Int
        var highKey: Int
        var rootKey: Int
        var lowVelocity: Int
        var highVelocity: Int
        /// A correction in cents.
        var tune: Double
        /// The zone's own level as a multiplier, from its decibels.
        var gain: Double
        var loopStart: Int?
        var loopEnd: Int?
    }

    private(set) var zones: [Zone] = []

    /// What the instrument is called, for a sketch that wants to say.
    public let name: String

    /// How many recordings it holds.
    public var recordingCount: Int { zones.count }

    /// Whether anything loaded at all.
    public var isEmpty: Bool { zones.isEmpty }

    // MARK: Loading

    /// Reads an instrument from an `.sfz` file and the recordings beside it.
    ///
    /// A region whose file is missing is skipped with a note rather than
    /// refused, so one absent recording costs one note of the range instead of
    /// the whole instrument.
    public init?(contentsOf url: URL) {
        name = url.deletingPathExtension().lastPathComponent
        guard let file = SFZFile(contentsOf: url) else {
            audioNoteOnce("could not read the instrument at \(url.lastPathComponent).")
            return nil
        }
        let folder = url.deletingLastPathComponent()
        for region in file.regions {
            let sampleURL = folder.appendingPathComponent(region.sample)
            guard let (frames, rate) = SampledInstrument.read(sampleURL) else {
                audioNoteOnce("an instrument names \(region.sample), which is not "
                              + "beside it; that part of the range will be silent.")
                continue
            }
            zones.append(Zone(
                frames: frames, sampleRate: rate,
                lowKey: region.lowKey, highKey: region.highKey, rootKey: region.rootKey,
                lowVelocity: region.lowVelocity, highVelocity: region.highVelocity,
                tune: region.tune, gain: pow(10, region.volume / 20),
                loopStart: region.loops ? (region.loopStart ?? 0) : nil,
                loopEnd: region.loops ? (region.loopEnd ?? frames.count - 1) : nil
            ))
        }
        if zones.isEmpty {
            audioNoteOnce("the instrument at \(url.lastPathComponent) has nothing "
                          + "playable in it.")
            return nil
        }
    }

    /// Reads an instrument bundled with a sketch.
    ///
    /// The bundle is explicit because a default would resolve to Ollin's own
    /// rather than the caller's, which is the rule every loader here follows.
    public convenience init?(sfz name: String, in bundle: Bundle) {
        let base = (name as NSString).deletingPathExtension
        guard let url = bundle.url(forResource: base, withExtension: "sfz") else {
            audioNoteOnce("no instrument named \(name) in that bundle.")
            return nil
        }
        self.init(contentsOf: url)
    }

    /// An instrument built from recordings already in hand.
    ///
    /// The way in for a sketch that made its own sounds, or read them from
    /// somewhere Ollin does not know about.
    public init(name: String = "instrument", recordings: [Recording]) {
        self.name = name
        zones = recordings.map { recording in
            Zone(frames: recording.frames, sampleRate: recording.sampleRate,
                 lowKey: recording.lowKey, highKey: recording.highKey,
                 rootKey: recording.rootKey, lowVelocity: 0, highVelocity: 127,
                 tune: 0, gain: 1, loopStart: nil, loopEnd: nil)
        }
    }

    /// One recording handed over directly.
    public struct Recording: Sendable {
        /// The samples, one channel.
        public var frames: [Float]
        public var sampleRate: Double
        /// The note it was recorded at.
        public var rootKey: Int
        /// The notes it should answer to. Defaults to the note it was recorded
        /// at and nothing else.
        public var lowKey: Int
        public var highKey: Int

        public init(frames: [Float], sampleRate: Double, rootKey: Int,
                    lowKey: Int? = nil, highKey: Int? = nil) {
            self.frames = frames
            self.sampleRate = sampleRate
            self.rootKey = rootKey
            self.lowKey = lowKey ?? rootKey
            self.highKey = highKey ?? rootKey
        }
    }

    /// Reads an audio file into one channel of samples.
    ///
    /// Folded to mono, because a sampled voice is one stream the same as every
    /// other voice here, and stereo would have to be thrown away somewhere.
    static func read(_ url: URL) -> ([Float], Double)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let count = AVAudioFrameCount(file.length)
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                       frameCapacity: count),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData else { return nil }

        let frames = Int(buffer.frameLength)
        var mono = [Float](repeating: 0, count: frames)
        let channelCount = Int(format.channelCount)
        for channel in 0..<channelCount {
            let data = channels[channel]
            for index in 0..<frames { mono[index] += data[index] }
        }
        if channelCount > 1 {
            let scale = Float(1.0 / Double(channelCount))
            for index in mono.indices { mono[index] *= scale }
        }
        return (mono, format.sampleRate)
    }

    // MARK: The bundled one

    /// A small instrument Ollin carries, so the sampler can be heard working
    /// without downloading anything.
    ///
    /// A struck bar, recorded at five pitches a fourth apart. It is generated
    /// rather than sourced (`Scripts/make-sample-instrument.swift`), so it is
    /// Ollin's own and carries no licence of anyone else's. It is a
    /// demonstration and not a library: five recordings and a few hundred
    /// kilobytes, where a real instrument is hundreds of recordings and
    /// gigabytes.
    ///
    /// It is also a fair thing to sample. A struck bar rings at ratios that are
    /// not harmonics, each partial fading at its own rate, which is expensive
    /// to work out and cheap to play back, and that is what a sampler is for.
    public static let builtin: SampledInstrument? = {
        guard let url = Bundle.module.url(forResource: "Struck/Struck", withExtension: "sfz")
                ?? Bundle.module.url(forResource: "Struck", withExtension: "sfz") else {
            audioNoteOnce("the bundled instrument is missing from this build.")
            return nil
        }
        return SampledInstrument(contentsOf: url)
    }()

    // MARK: Reading it back

    /// The note each recording was made at, in the order they were read.
    ///
    /// What a sketch draws to show which recordings an instrument is made of.
    public var recordingRoots: [Int] { zones.map(\.rootKey) }

    /// Which recording answers a note, or nil if the instrument is empty.
    ///
    /// The same choice the sampler makes, so a sketch can show it.
    public func recordingIndex(for key: Int, velocity: Double = 0.8) -> Int? {
        zone(for: key, velocity: velocity)
    }

    /// One of the recordings, handed back so it can be rebuilt into another
    /// instrument. `range` is the notes it should answer to there.
    public func recording(at index: Int, over range: ClosedRange<Int>) -> Recording {
        guard index >= 0, index < zones.count else {
            return Recording(frames: [], sampleRate: 44100, rootKey: 60)
        }
        let zone = zones[index]
        return Recording(frames: zone.frames, sampleRate: zone.sampleRate,
                         rootKey: zone.rootKey,
                         lowKey: range.lowerBound, highKey: range.upperBound)
    }

    // MARK: Choosing a recording

    /// The recording to play for a note, or nil if nothing covers it.
    ///
    /// Where several cover it, the one recorded nearest the note wins, so a
    /// note is moved as little as possible. Moving a recording a long way is
    /// what makes a sampled instrument sound wrong, and it is the one thing
    /// choosing well can avoid.
    func zone(for key: Int, velocity: Double) -> Int? {
        let struck = Int((min(max(0, velocity), 1) * 127).rounded())
        var best: Int?
        var bestDistance = Int.max
        for (index, zone) in zones.enumerated() {
            guard key >= zone.lowKey, key <= zone.highKey,
                  struck >= zone.lowVelocity, struck <= zone.highVelocity else { continue }
            let distance = abs(key - zone.rootKey)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        // Nothing covers it: rather than silence, the nearest recording of any
        // range is stretched to reach, which is what a small instrument played
        // outside its range should do.
        if best == nil, !zones.isEmpty {
            var nearest = 0
            var distance = Int.max
            for (index, zone) in zones.enumerated() where abs(key - zone.rootKey) < distance {
                distance = abs(key - zone.rootKey)
                nearest = index
            }
            best = nearest
        }
        return best
    }
}

// MARK: - Playing one

/// How a recording is played, as opposed to which one.
///
/// Small and made only of numbers, because this is the part that travels to
/// the audio thread inside a note. The recordings themselves stay on the
/// ``Synth``.
public struct Sampled: Sendable, Hashable, Codable {
    /// Whether a note holds by repeating the looped part of its recording.
    ///
    /// Only does anything for a recording that says where its loop is. Without
    /// one, a note lasts as long as the recording does.
    public var loops: Bool

    /// How much the note's velocity changes its loudness, `0...1`.
    ///
    /// At 0 every note is as loud as it was recorded, which is right for an
    /// instrument whose own recordings are the dynamics. At 1 velocity is the
    /// whole of it.
    public var velocitySensitivity: Double

    /// Moves every note by this many semitones, for an instrument recorded at
    /// the wrong pitch or one you want an octave down.
    public var transpose: Double

    public init(loops: Bool = true, velocitySensitivity: Double = 0.7,
                transpose: Double = 0) {
        self.loops = loops
        self.velocitySensitivity = min(max(0, velocitySensitivity), 1)
        self.transpose = transpose
    }
}
