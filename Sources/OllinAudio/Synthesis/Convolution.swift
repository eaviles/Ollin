import AVFoundation
import Ollin
import os

// MARK: - A room, as the sound it makes of a click

/// A room, written down as what it does to a single click.
///
/// Clap once in a stairwell and what comes back is the stairwell: every
/// surface, every distance, all at once. That recording is an impulse
/// response, and a sound played through it is heard in that room, because
/// every sample of the sound starts its own copy of the click's answer. A
/// ``Reverb`` made from one is a convolution reverb.
///
/// ```swift
/// let stairwell = ImpulseResponse.resource("stairwell", withExtension: "wav", in: .module)!
/// synth.reverb = Reverb(stairwell, mix: 0.4)
/// ```
///
/// The room does not have to be real. ``decay(seconds:damping:sampleRate:seed:)``
/// makes one from fading noise, and ``init(seconds:sampleRate:seed:_:)`` draws
/// one from a rule, the way a sketch draws anything else:
///
/// ```swift
/// let hall = ImpulseResponse.decay(seconds: 3, damping: 0.6)
/// let bell = ImpulseResponse(seconds: 2) { t, _ in exp(-3 * t) * sin(2 * .pi * 440 * t) }
/// ```
///
/// A response is two channels, one per side, so a room has width; a mono
/// recording is heard the same on both sides. The samples are the response
/// as recorded or drawn: the reverb brings the room to unit energy on the
/// way in, so a quiet recording and a loud one sit at the same level and
/// `mix` means the same thing for every room.
public struct ImpulseResponse: Sendable, Hashable, Codable {
    /// The response, one array per channel: one for a room heard the same
    /// on both sides, two for one recorded with a pair of microphones.
    public var channels: [[Float]]
    /// Samples per second the response was recorded or drawn at. A reverb
    /// running at another rate resamples it on the way in.
    public var sampleRate: Double

    /// The longest room a reverb takes, in seconds. A longer response is
    /// cut there: past twenty seconds it is a drone rather than a room.
    public static let maxSeconds = 20.0

    /// A response heard the same on both sides.
    public init(_ samples: [Float], sampleRate: Double) {
        channels = [samples]
        self.sampleRate = sampleRate
    }

    /// A response with a side of its own for each ear.
    public init(left: [Float], right: [Float], sampleRate: Double) {
        channels = [left, right]
        self.sampleRate = sampleRate
    }

    /// How many samples each channel holds.
    public var frameCount: Int { channels.first?.count ?? 0 }

    /// How long the room answers, in seconds.
    public var duration: Double {
        sampleRate > 0 ? Double(frameCount) / sampleRate : 0
    }

    /// How many channels there are, one or two.
    public var channelCount: Int { channels.count }

    // MARK: Drawn from a rule

    /// A room drawn from a rule.
    ///
    /// The closure is asked for each sample: the time in seconds since the
    /// click, and a noise value in `-1...1` it may use or ignore. Use the
    /// noise and the room is diffuse; ignore it and the room is whatever the
    /// rule says, a ringing tone, a run of echoes, a shape you had in mind.
    /// The noise differs between the two sides, which is what gives a drawn
    /// room its width, and it comes from `seed`, so the same rule draws the
    /// same room every run.
    ///
    /// ```swift
    /// // A hall: noise fading over three seconds.
    /// ImpulseResponse(seconds: 3) { t, noise in exp(-2.3 * t) * noise }
    /// // A resonator: the room hums at A.
    /// ImpulseResponse(seconds: 2) { t, _ in exp(-3 * t) * sin(2 * .pi * 440 * t) }
    /// ```
    public init(seconds: Double, sampleRate: Double = 48000, seed: Int = 0,
                _ shape: (_ time: Double, _ noise: Double) -> Double) {
        let rate = max(1000, sampleRate)
        let length = min(max(0.001, seconds), ImpulseResponse.maxSeconds)
        let count = max(1, Int((length * rate).rounded()))
        var sides: [[Float]] = []
        for side in 0..<2 {
            var generator = ImpulseResponse.noise(seed: seed, side: side)
            var samples = [Float](repeating: 0, count: count)
            for index in 0..<count {
                let time = Double(index) / rate
                samples[index] = Float(shape(time, generator.next()))
            }
            sides.append(samples)
        }
        channels = sides
        self.sampleRate = rate
    }

    /// A room made of fading noise, the plainest room there is.
    ///
    /// - Parameters:
    ///   - seconds: how long the room takes to fall silent: the time it
    ///     takes the answer to drop sixty decibels.
    ///   - damping: how much faster the top end fades than the bottom,
    ///     `0...1`. Zero leaves the noise bright for its whole length, which
    ///     no real room does; one pulls the top down hard, the way a room
    ///     full of curtains does.
    ///   - sampleRate: what the response is drawn at.
    ///   - seed: which noise. Two seeds are two rooms of the same size.
    public static func decay(seconds: Double = 2, damping: Double = 0.5,
                             sampleRate: Double = 48000, seed: Int = 0) -> ImpulseResponse {
        let rate = max(1000, sampleRate)
        let length = min(max(0.001, seconds), maxSeconds)
        let held = min(max(0, damping), 1)
        let count = max(1, Int((length * rate).rounded()))
        var sides: [[Float]] = []
        for side in 0..<2 {
            var generator = noise(seed: seed, side: side)
            var samples = [Float](repeating: 0, count: count)
            var filtered = 0.0
            for index in 0..<count {
                let progress = Double(index) / Double(count)
                // The top end goes first: a one-pole lowpass whose cutoff
                // falls with time, from about twenty kilohertz to as low as
                // four hundred hertz when the damping is all the way up.
                let cutoff = 20000 * pow(400 / 20000, held * (0.3 + 0.7 * progress))
                let pull = 1 - exp(-2 * .pi * cutoff / rate)
                filtered += (generator.next() - filtered) * pull
                // The lowpass quietens the noise by a known amount; undone
                // here so the fade is the fade asked for and not the filter's.
                let level = (pull / (2 - pull)).squareRoot()
                let envelope = exp(-6.9078 * progress)
                samples[index] = Float(filtered / level * envelope)
            }
            sides.append(samples)
        }
        return ImpulseResponse(left: sides[0], right: sides[1], sampleRate: rate)
    }

    /// The noise a drawn room is made of, one stream per side.
    private static func noise(seed: Int, side: Int) -> NoiseStream {
        let base = UInt64(bitPattern: Int64(seed))
        return NoiseStream(SplitMix64(seed: base &+ UInt64(side) &* 0x9E37_79B9_7F4A_7C15))
    }

    /// Uniform noise in `-1...1` from a seeded generator.
    private struct NoiseStream {
        var generator: SplitMix64
        init(_ generator: SplitMix64) { self.generator = generator }
        mutating func next() -> Double {
            Double(generator.next() >> 11) / Double(1 << 53) * 2 - 1
        }
    }

    // MARK: Recorded

    /// A room read from a recording: anything the system plays, WAV, AIFF,
    /// CAF, or a compressed file. The first two channels are kept, and a
    /// response longer than ``maxSeconds`` is cut there. Nil, with a note,
    /// when the file cannot be read.
    public static func load(_ path: String) -> ImpulseResponse? {
        ImpulseResponse(contentsOf: URL(fileURLWithPath: path))
    }

    /// A room read from a file in a bundle, the sketch's own by default.
    public static func resource(_ name: String, withExtension ext: String = "wav",
                                in bundle: Bundle) -> ImpulseResponse? {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            audioNoteOnce("no impulse response named \(name).\(ext) in the bundle.")
            return nil
        }
        return ImpulseResponse(contentsOf: url)
    }

    /// A room read from a file.
    public init?(contentsOf url: URL) {
        guard let file = try? AVAudioFile(forReading: url) else {
            audioNoteOnce("the impulse response at \(url.lastPathComponent) could not be read.")
            return nil
        }
        let format = file.processingFormat
        let rate = format.sampleRate
        let available = Int(file.length)
        let limit = Int(ImpulseResponse.maxSeconds * rate)
        let count = min(available, limit)
        guard count > 0, rate > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              (try? file.read(into: buffer, frameCount: AVAudioFrameCount(count))) != nil,
              let data = buffer.floatChannelData else {
            audioNoteOnce("the impulse response at \(url.lastPathComponent) holds no sound.")
            return nil
        }
        if available > limit {
            audioNoteOnce("the impulse response at \(url.lastPathComponent) is longer than "
                          + "\(Int(ImpulseResponse.maxSeconds)) seconds and was cut there.")
        }
        let frames = Int(buffer.frameLength)
        let sides = min(2, Int(format.channelCount))
        channels = (0..<sides).map { Array(UnsafeBufferPointer(start: data[$0], count: frames)) }
        sampleRate = rate
    }

    // MARK: Turned around

    /// The same room run backward: the answer swells toward the click rather
    /// than fading from it, the reverse reverb of a thousand records.
    public func reversed() -> ImpulseResponse {
        var copy = self
        copy.channels = channels.map { Array($0.reversed()) }
        return copy
    }

    // MARK: What the reverb convolves with

    /// The response as the reverb runs it: at `rate`, after `preDelay`
    /// seconds of silence, no longer than ``maxSeconds``, and at unit energy
    /// across the sides, so every room sits at one level.
    func prepared(at rate: Double, preDelay: Double) -> [[Float]] {
        var sides = channels.filter { !$0.isEmpty }
        if sides.isEmpty { sides = [[0]] }
        if sampleRate != rate {
            sides = ImpulseResponse.resampled(sides, from: sampleRate, to: rate)
        }
        let limit = max(1, Int(ImpulseResponse.maxSeconds * rate))
        let lead = Int((min(max(0, preDelay), 1) * rate).rounded())
        sides = sides.map { side in
            let kept = side.count > limit ? Array(side[..<limit]) : side
            return lead > 0 ? [Float](repeating: 0, count: lead) + kept : kept
        }
        var energy = 0.0
        for side in sides {
            for sample in side { energy += Double(sample) * Double(sample) }
        }
        energy /= Double(sides.count)
        if energy > 0 {
            let gain = Float(1 / energy.squareRoot())
            sides = sides.map { $0.map { $0 * gain } }
        }
        return sides
    }

    /// The response at another rate, through the system's converter.
    static func resampled(_ sides: [[Float]], from source: Double, to target: Double) -> [[Float]] {
        guard source > 0, target > 0, source != target, let first = sides.first, !first.isEmpty,
              let inFormat = AVAudioFormat(standardFormatWithSampleRate: source,
                                           channels: AVAudioChannelCount(sides.count)),
              let outFormat = AVAudioFormat(standardFormatWithSampleRate: target,
                                            channels: AVAudioChannelCount(sides.count)),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let input = AVAudioPCMBuffer(pcmFormat: inFormat,
                                           frameCapacity: AVAudioFrameCount(first.count)),
              let inputData = input.floatChannelData
        else { return sides }
        input.frameLength = AVAudioFrameCount(first.count)
        for (index, side) in sides.enumerated() {
            side.withUnsafeBufferPointer { samples in
                inputData[index].update(from: samples.baseAddress!, count: min(side.count, first.count))
            }
        }
        let expected = Int((Double(first.count) * target / source).rounded())
        guard let output = AVAudioPCMBuffer(pcmFormat: outFormat,
                                            frameCapacity: AVAudioFrameCount(expected + 64)),
              let outputData = output.floatChannelData else { return sides }
        var handed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if handed {
                outStatus.pointee = .endOfStream
                return nil
            }
            handed = true
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error else { return sides }
        let produced = min(Int(output.frameLength), expected)
        return (0..<sides.count).map { Array(UnsafeBufferPointer(start: outputData[$0], count: produced)) }
    }
}

// MARK: - The reverb that runs a room

/// A reverb of a recorded or drawn room: the sound convolved with an
/// ``ImpulseResponse``, one convolver per side.
///
/// Built on the main thread for one room at one sample rate, then run on the
/// audio thread through the chain's closure unit. The mix is the one setting
/// that changes without rebuilding, so a sketch turning it never cuts a tail
/// that is still sounding.
final class ConvolutionReverb: @unchecked Sendable {
    let impulse: ImpulseResponse
    let preDelay: Double
    let sampleRate: Double
    /// How many samples the room runs for as prepared: resampled, after the
    /// pre-delay, and cut to the longest a room may be.
    let preparedFrameCount: Int

    private let convolvers: [PartitionedConvolver]
    private let mixLock: OSAllocatedUnfairLock<Float>
    private let wet: UnsafeMutablePointer<Float>

    init(_ reverb: Reverb, impulse: ImpulseResponse, sampleRate: Double) {
        self.impulse = impulse
        self.preDelay = reverb.preDelay
        self.sampleRate = sampleRate
        let sides = impulse.prepared(at: sampleRate, preDelay: reverb.preDelay)
        preparedFrameCount = sides.first?.count ?? 0
        // One convolver per output side, each with the response's own side
        // where it has one and the single side otherwise.
        convolvers = (0..<2).map { PartitionedConvolver(response: sides[min($0, sides.count - 1)]) }
        mixLock = OSAllocatedUnfairLock(initialState: Float(min(max(0, reverb.mix), 1)))
        wet = .allocate(capacity: PartitionedConvolver.slice)
        wet.initialize(repeating: 0, count: PartitionedConvolver.slice)
    }

    deinit { wet.deallocate() }

    /// Whether this engine is the one `reverb` asks for at `rate`: the same
    /// room, the same pre-delay. Anything else is a rebuild.
    func serves(_ reverb: Reverb, at rate: Double) -> Bool {
        reverb.impulse == impulse && reverb.preDelay == preDelay && rate == sampleRate
    }

    /// How much of the result is the room, `0...1`. Read on the audio thread,
    /// set from anywhere.
    var mix: Double {
        get { Double(mixLock.withLock { $0 }) }
        set { mixLock.withLock { $0 = Float(min(max(0, newValue), 1)) } }
    }

    /// Runs the room over one block, in place.
    func process(_ block: AudioBlock) {
        let mix = mixLock.withLock { $0 }
        let dry = 1 - mix
        for channel in 0..<min(block.channelCount, convolvers.count) {
            let samples = block[channel]
            guard let base = samples.baseAddress else { continue }
            var offset = 0
            while offset < samples.count {
                let run = min(PartitionedConvolver.slice, samples.count - offset)
                convolvers[channel].process(input: base + offset, wet: wet, count: run)
                for index in 0..<run {
                    base[offset + index] = base[offset + index] * dry + wet[index] * mix
                }
                offset += run
            }
        }
    }
}
