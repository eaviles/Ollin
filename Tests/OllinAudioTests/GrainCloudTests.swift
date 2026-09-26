import Foundation
import Testing
@testable import OllinAudio

/// Grains cut out of a sound. What is checked is that one grain is the source
/// it was cut from and nothing else, that a pile of them gets louder the way
/// independent things do, that holding the position still holds the sound
/// still while the note keeps going, that spreading the pitch spreads the
/// spectrum, and that a seed gives the same cloud twice.
@Suite struct GrainCloudTests {

    static let rate = 44100.0

    /// An envelope that is simply out of the way: full level on the first
    /// sample and there until the note is let go, so what comes out of the
    /// renderer is the cloud and nothing shaping it.
    static let flat = Envelope(attack: 0, decay: 0, sustain: 1, release: 0.05)

    static func render(_ voice: Voice, source: GrainSource?, pitch: Double,
                       seconds: Double, gain: Double = 1, scrub: Double = 0,
                       scrubAt: Double? = nil) -> [Double] {
        let events = EventRing()
        let renderer = SynthRenderer(voice: voice, polyphony: 4, sampleRate: rate, events: events)
        renderer.gain = gain
        renderer.grainSource = source
        renderer.grainScrub = scrub
        events.push(SynthEvent(kind: .noteOn, pitch: pitch, velocity: 1, durationSamples: 0))
        var out = [Double]()
        let block = 512
        let target = Int(seconds * rate)
        while out.count < target {
            if let scrubAt, out.count >= Int(scrubAt * rate) { renderer.grainScrub = 0.9 }
            var chunk = [Float](repeating: 0, count: block)
            chunk.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: block) }
            out += chunk.map(Double.init)
        }
        return out
    }

    /// The same, in two channels.
    static func renderStereo(_ voice: Voice, source: GrainSource?, pitch: Double,
                             seconds: Double, gain: Double = 1) -> (left: [Double], right: [Double]) {
        let events = EventRing()
        let renderer = SynthRenderer(voice: voice, polyphony: 4, sampleRate: rate, events: events)
        renderer.gain = gain
        renderer.grainSource = source
        events.push(SynthEvent(kind: .noteOn, pitch: pitch, velocity: 1, durationSamples: 0))
        var left = [Double](), right = [Double]()
        let block = 512
        while left.count < Int(seconds * rate) {
            var a = [Float](repeating: 0, count: block)
            var b = [Float](repeating: 0, count: block)
            a.withUnsafeMutableBufferPointer { one in
                b.withUnsafeMutableBufferPointer { two in
                    renderer.render(into: one, right: two, frameCount: block)
                }
            }
            left += a.map(Double.init)
            right += b.map(Double.init)
        }
        return (left, right)
    }

    static func magnitude(_ s: ArraySlice<Double>, at hz: Double) -> Double {
        let n = s.count
        guard n > 16 else { return 0 }
        let w = 2 * Double.pi * hz / rate
        let c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in s { let s0 = v + c * s1 - s2; s2 = s1; s1 = s0 }
        return (s1 * s1 + s2 * s2 - c * s1 * s2).squareRoot() / Double(n)
    }

    static func rms(_ s: ArraySlice<Double>) -> Double {
        guard !s.isEmpty else { return 0 }
        return (s.reduce(0) { $0 + $1 * $1 } / Double(s.count)).squareRoot()
    }

    /// A sound with a different value at every sample, so reproducing it is a
    /// real claim rather than one a constant would also satisfy.
    static func textured(count: Int, peak: Double = 0.3) -> GrainSource {
        let frames = (0..<count).map { index -> Float in
            let t = Double(index)
            return Float(peak * sin(t * 0.037) * cos(t * 0.0091 + 1))
        }
        return GrainSource(name: "textured", frames: frames, sampleRate: rate, rootKey: 60)
    }

    /// A sound whose pitch climbs steadily from one end to the other, so where
    /// in it a grain was cut from can be read straight off the spectrum.
    static func chirp(seconds: Double, from low: Double, to high: Double,
                      peak: Double = 0.4) -> GrainSource {
        let count = Int(seconds * rate)
        var phase = 0.0
        var frames = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let along = Double(index) / Double(count)
            phase += 2 * Double.pi * (low + (high - low) * along) / rate
            frames[index] = Float(peak * sin(phase))
        }
        return GrainSource(name: "chirp", frames: frames, sampleRate: rate, rootKey: 60)
    }

    /// The frequency that carries the most of a window, over a sweep of the
    /// range a chirp covers.
    static func peakFrequency(_ s: ArraySlice<Double>, over range: ClosedRange<Double>) -> Double {
        var best = range.lowerBound
        var bestMagnitude = 0.0
        var hz = range.lowerBound
        while hz <= range.upperBound {
            let magnitude = Self.magnitude(s, at: hz)
            if magnitude > bestMagnitude { bestMagnitude = magnitude; best = hz }
            hz += 4
        }
        return best
    }

    // MARK: One grain

    @Test func oneGrainIsTheSourceItWasCutFrom() {
        // A single grain, cut from a quarter of the way in, at the pitch the
        // source was recorded at, with a flat-topped envelope: through the
        // middle of the grain there is nothing between the source and the
        // output at all, so they agree sample for sample.
        let source = Self.textured(count: Int(Self.rate))
        let size = 0.05
        let cloud = GrainCloud(size: size, density: 2, position: 0.25, positionJitter: 0,
                               speed: 0, timingJitter: 0, shape: .plateau)
        let sound = Self.render(Voice(granular: cloud, envelope: Self.flat, gain: 1),
                                source: source, pitch: 60, seconds: 0.5)

        let start = Int(0.25 * Double(source.frames.count))
        let length = size * Self.rate
        // The plateau is flat between its two ramps, each a sixth of the grain.
        let from = Int(0.2 * length), to = Int(0.8 * length)
        var worst = 0.0
        for index in from..<to {
            worst = max(worst, abs(sound[index] - Double(source.frames[start + index])))
        }
        #expect(worst < 1e-7, "the middle of the grain should be the source: off by \(worst)")

        // And it is a grain rather than the whole sound: past its own length
        // it has gone, and the next one is not due for half a second.
        let after = sound[(Int(length) + 64) ..< Int(0.4 * Self.rate)]
        #expect(Self.rms(after) < 1e-9)
    }

    @Test func aGrainFadesInAndOutRatherThanCutting() {
        // Every shape starts and ends at nothing, which is the whole reason a
        // grain wears one: a straight cut at these lengths is a click.
        for shape in GrainShape.allCases {
            #expect(GrainVoice.window(shape, at: 0) < 1e-6, "\(shape) starts at nothing")
            #expect(GrainVoice.window(shape, at: 1) < 1e-6, "\(shape) ends at nothing")
            let peak = stride(from: 0.0, through: 1.0, by: 0.001)
                .map { GrainVoice.window(shape, at: $0) }.max() ?? 0
            #expect(abs(peak - 1) < 0.01, "\(shape) reaches full level: \(peak)")
        }
    }

    // MARK: A pile of them

    @Test func loudnessRisesWithTheSquareRootOfTheDensity() {
        // Grains land on each other at random, so what adds is power rather
        // than amplitude: four times as many is twice as loud, not four times.
        let source = Self.textured(count: Int(2 * Self.rate))
        func level(_ density: Double) -> Double {
            let cloud = GrainCloud(size: 0.03, density: density, position: 0.5,
                                   positionJitter: 0.4, speed: 0)
            let sound = Self.render(Voice(granular: cloud, envelope: Self.flat, gain: 1),
                                    source: source, pitch: 60, seconds: 2.5, gain: 0.25)
            return Self.rms(sound[Int(0.3 * Self.rate) ..< Int(2.3 * Self.rate)])
        }
        let quiet = level(20)
        let loud = level(80)
        let ratio = loud / quiet
        #expect(abs(ratio - 2) < 0.3, "four times the grains should be twice as loud: \(ratio)")
    }

    @Test func aCloudDropsGrainsRatherThanWaitingForRoom() {
        // Past what one note may have sounding at once a grain is dropped, the
        // same bargain the event ring makes. What must not happen is a stall,
        // a click, or anything but sound.
        let source = Self.textured(count: Int(Self.rate))
        let cloud = GrainCloud(size: 0.5, density: 1000, position: 0.5,
                               positionJitter: 0.3, speed: 0)
        let sound = Self.render(Voice(granular: cloud, envelope: Self.flat, gain: 1),
                                source: source, pitch: 60, seconds: 0.8, gain: 0.05)
        let window = sound[Int(0.4 * Self.rate) ..< Int(0.75 * Self.rate)]
        #expect(Self.rms(window) > 1e-4, "a cloud past its limit still sounds")
        #expect(!sound.contains { !$0.isFinite })
    }

    // MARK: The position, and holding it still

    @Test func aFrozenPositionHoldsItsSpectrumWhileTheClockRuns() {
        // The one thing nothing else in this tier does. The source climbs in
        // pitch from end to end; a note frozen half way through it reads the
        // same place for as long as it sounds, so its spectrum does not move.
        let source = Self.chirp(seconds: 2, from: 200, to: 1600)
        let frozen = GrainCloud(size: 0.05, density: 60, position: 0.5,
                                positionJitter: 0.003, speed: 0)
        let held = Self.render(Voice(granular: frozen, envelope: Self.flat, gain: 1),
                               source: source, pitch: 60, seconds: 2, gain: 0.3)
        let early = Self.peakFrequency(held[Int(0.2 * Self.rate) ..< Int(0.5 * Self.rate)],
                                       over: 150...1700)
        let late = Self.peakFrequency(held[Int(1.5 * Self.rate) ..< Int(1.9 * Self.rate)],
                                      over: 150...1700)
        #expect(abs(early - 900) < 90, "half way along a 200 to 1600 climb: \(early)")
        #expect(abs(late - early) < 60, "and it stays there: \(early) then \(late)")

        // Told to travel instead, the same note walks the sound as it goes.
        var moving = frozen
        moving.speed = 1
        moving.position = 0
        let walked = Self.render(Voice(granular: moving, envelope: Self.flat, gain: 1),
                                 source: source, pitch: 60, seconds: 2, gain: 0.3)
        let first = Self.peakFrequency(walked[Int(0.1 * Self.rate) ..< Int(0.4 * Self.rate)],
                                       over: 150...1700)
        let last = Self.peakFrequency(walked[Int(1.5 * Self.rate) ..< Int(1.9 * Self.rate)],
                                      over: 150...1700)
        #expect(last > first + 500, "travelling, it climbs: \(first) then \(last)")
    }

    @Test func aScrubMovesANoteThatIsAlreadySounding() {
        // A held note, dragged. The reading jumps to the far end of the sound
        // while the note itself carries on, which is the sound of a playhead
        // being pulled rather than of a new note.
        let source = Self.chirp(seconds: 2, from: 200, to: 1600)
        let cloud = GrainCloud(size: 0.05, density: 60, position: 0,
                               positionJitter: 0.003, speed: 0)
        // Not the whole length: a cloud loops, so a source length along is the
        // same place as none at all, exactly as position 1 is position 0.
        let sound = Self.render(Voice(granular: cloud, envelope: Self.flat, gain: 1),
                                source: source, pitch: 60, seconds: 2, gain: 0.3,
                                scrubAt: 1.0)
        let before = Self.peakFrequency(sound[Int(0.3 * Self.rate) ..< Int(0.8 * Self.rate)],
                                        over: 150...1700)
        let after = Self.peakFrequency(sound[Int(1.4 * Self.rate) ..< Int(1.9 * Self.rate)],
                                       over: 150...1700)
        #expect(abs(before - 240) < 120, "the start of the sound: \(before)")
        #expect(after > 1300, "dragged most of the way along it: \(after)")
    }

    @Test func theSoundComesRoundRatherThanRunningOut() {
        // A cloud loops: travelling past the end of a short sound reads the
        // start of it again, rather than going quiet part way through a note.
        let source = Self.textured(count: Int(0.4 * Self.rate))
        let cloud = GrainCloud(size: 0.03, density: 60, positionJitter: 0.05, speed: 1)
        let sound = Self.render(Voice(granular: cloud, envelope: Self.flat, gain: 1),
                                source: source, pitch: 60, seconds: 1.6, gain: 0.3)
        let late = Self.rms(sound[Int(1.2 * Self.rate) ..< Int(1.55 * Self.rate)])
        let early = Self.rms(sound[Int(0.05 * Self.rate) ..< Int(0.35 * Self.rate)])
        #expect(late > early * 0.5, "three times past the end it is still sounding: \(late)")
    }

    @Test func runningBackwardReadsTheSoundBackward() {
        let source = Self.chirp(seconds: 2, from: 200, to: 1600)
        let cloud = GrainCloud(size: 0.05, density: 60, position: 0.95,
                               positionJitter: 0.003, speed: -1)
        let sound = Self.render(Voice(granular: cloud, envelope: Self.flat, gain: 1),
                                source: source, pitch: 60, seconds: 1.6, gain: 0.3)
        let first = Self.peakFrequency(sound[Int(0.1 * Self.rate) ..< Int(0.4 * Self.rate)],
                                       over: 150...1700)
        let last = Self.peakFrequency(sound[Int(1.1 * Self.rate) ..< Int(1.5 * Self.rate)],
                                      over: 150...1700)
        #expect(last < first - 500, "it comes down rather than up: \(first) then \(last)")
    }

    // MARK: Pitch, and the two clocks

    @Test func theNotesPitchMovesTheGrainsAndNotTheTravel() {
        // The whole claim of this tier in one test. A note an octave up reads
        // each grain twice as fast, so everything is an octave higher, while
        // the position travels through the sound at exactly the same speed, so
        // the same moment is reached at the same time.
        let source = Self.chirp(seconds: 2, from: 200, to: 800)
        let cloud = GrainCloud(size: 0.06, density: 50, position: 0,
                               positionJitter: 0.002, speed: 1)
        func peaks(at pitch: Double, over range: ClosedRange<Double>) -> (Double, Double) {
            let sound = Self.render(Voice(granular: cloud, envelope: Self.flat, gain: 1),
                                    source: source, pitch: pitch, seconds: 1.7, gain: 0.3)
            return (Self.peakFrequency(sound[Int(0.2 * Self.rate) ..< Int(0.5 * Self.rate)],
                                       over: range),
                    Self.peakFrequency(sound[Int(1.3 * Self.rate) ..< Int(1.6 * Self.rate)],
                                       over: range))
        }
        let (rootEarly, rootLate) = peaks(at: 60, over: 150...1000)
        let (upEarly, upLate) = peaks(at: 72, over: 300...2000)
        #expect(abs(upEarly / rootEarly - 2) < 0.12,
                "an octave up is twice the frequency: \(rootEarly) then \(upEarly)")
        #expect(abs(upLate / rootLate - 2) < 0.12,
                "and still is later on: \(rootLate) then \(upLate)")
        // The travel is the same: the later window is the same distance along
        // the climb in both, which is what pitch not touching time means.
        #expect(abs((rootLate - rootEarly) * 2 - (upLate - upEarly)) < 120,
                "the sound is walked at the same speed either way")
    }

    @Test func spreadingThePitchWidensThePeak() {
        // A steady tone, frozen. With no spread every grain reads it at the
        // same speed and the tone stays a line; spread, the grains land either
        // side of it and the line becomes a band.
        let count = Int(Self.rate)
        let tone = GrainSource(
            name: "tone",
            frames: (0..<count).map { Float(0.4 * sin(2 * Double.pi * 440 * Double($0) / Self.rate)) },
            sampleRate: Self.rate, rootKey: 60
        )
        func spectrum(_ spread: Double) -> (center: Double, side: Double) {
            let cloud = GrainCloud(size: 0.06, density: 60, position: 0.5,
                                   positionJitter: 0.05, speed: 0, pitchSpread: spread)
            let sound = Self.render(Voice(granular: cloud, envelope: Self.flat, gain: 1),
                                    source: tone, pitch: 60, seconds: 2, gain: 0.3)
            let window = sound[Int(0.5 * Self.rate) ..< Int(1.9 * Self.rate)]
            let side = max(Self.magnitude(window, at: 440 * pow(2, 2.5 / 12)),
                           Self.magnitude(window, at: 440 * pow(2, -2.5 / 12)))
            return (Self.magnitude(window, at: 440), side)
        }
        let tight = spectrum(0)
        let wide = spectrum(3)
        #expect(tight.side < tight.center * 0.1,
                "with no spread the tone is a line: \(tight.side) beside \(tight.center)")
        #expect(wide.side > wide.center * 0.3,
                "spread, there is as much beside it as on it: \(wide.side) beside \(wide.center)")
    }

    @Test func aStrictClockIsHeardAsAPitchOfItsOwn() {
        // With no timingJitter the grains arrive on a clock, and a frozen cloud
        // repeats the same piece of sound at that rate, so the output is
        // periodic at the density whatever the source was.
        let source = Self.textured(count: Int(Self.rate))
        func line(_ timingJitter: Double) -> Double {
            let cloud = GrainCloud(size: 0.004, density: 300, position: 0.5,
                                   positionJitter: 0, speed: 0, timingJitter: timingJitter)
            let sound = Self.render(Voice(granular: cloud, envelope: Self.flat, gain: 1),
                                    source: source, pitch: 60, seconds: 1.2, gain: 0.5)
            let window = sound[Int(0.3 * Self.rate) ..< Int(1.1 * Self.rate)]
            return Self.magnitude(window, at: 300) / max(1e-12, Self.rms(window))
        }
        let clocked = line(0)
        let scattered = line(1)
        #expect(clocked > scattered * 3,
                "a strict clock puts a line at the grain rate: \(clocked) against \(scattered)")
    }

    // MARK: Two channels

    @Test func nothingPanningRendersTwoChannelsAsOne() {
        // The load-bearing one. A cloud that spreads nothing, and every other
        // voice there is, must come out of the two-channel path exactly as it
        // came out of the one-channel path, to the bit.
        let source = Self.textured(count: Int(Self.rate))
        let cases: [(String, Voice, GrainSource?)] = [
            ("a cloud that spreads nothing",
             Voice(granular: GrainCloud(size: 0.04, density: 40, positionJitter: 0.2), gain: 1),
             source),
            ("a plain wave", Voice(waveform: .sawtooth, envelope: .organ), nil),
            ("a plucked string", .nylon, nil),
            ("a struck body", .chime, nil),
        ]
        for (what, voice, grainSource) in cases {
            let mono = Self.render(voice, source: grainSource, pitch: 60, seconds: 0.5, gain: 0.5)
            let stereo = Self.renderStereo(voice, source: grainSource, pitch: 60,
                                           seconds: 0.5, gain: 0.5)
            #expect(mono == stereo.left, "\(what): the left channel is the mono render")
            #expect(stereo.left == stereo.right, "\(what): and the two channels are one stream")
        }
    }

    @Test func spreadingTheGrainsSeparatesTheChannels() {
        let source = Self.textured(count: Int(Self.rate))
        let cloud = GrainCloud(size: 0.03, density: 50, positionJitter: 0.3, speed: 0,
                               panSpread: 1)
        let spread = Self.renderStereo(Voice(granular: cloud, envelope: Self.flat, gain: 1),
                                       source: source, pitch: 60, seconds: 1, gain: 0.4)
        let window = Int(0.2 * Self.rate) ..< Int(0.9 * Self.rate)
        let left: [Double] = Array(spread.left[window])
        let right: [Double] = Array(spread.right[window])
        #expect(left != right, "the two sides are not the same sound")
        var gap = [Double]()
        for index in left.indices { gap.append(left[index] - right[index]) }
        let difference = Self.rms(gap[...])
        #expect(difference > 0.2 * Self.rms(left[...]), "and they differ audibly: \(difference)")
        // Neither side is favored: the spread is even, so over a second the
        // two carry the same amount.
        let ratio = Self.rms(left[...]) / max(1e-12, Self.rms(right[...]))
        #expect(abs(ratio - 1) < 0.15, "and neither side is favored: \(ratio)")
    }

    @Test func theMiddleIsTheSameLevelSpreadOrNot() {
        // Equal power, scaled so the middle is exactly unity: a cloud that
        // spreads its grains is not quieter than one that does not.
        let source = Self.textured(count: Int(Self.rate))
        func level(_ spread: Double) -> Double {
            let cloud = GrainCloud(size: 0.03, density: 60, positionJitter: 0.3, speed: 0,
                                   panSpread: spread)
            let sound = Self.renderStereo(Voice(granular: cloud, envelope: Self.flat, gain: 1),
                                          source: source, pitch: 60, seconds: 1.2, gain: 0.4)
            let window = Int(0.2 * Self.rate) ..< Int(1.1 * Self.rate)
            let left = Self.rms(sound.left[window]), right = Self.rms(sound.right[window])
            return (0.5 * (left * left + right * right)).squareRoot()
        }
        let ratio = level(1) / level(0)
        #expect(abs(ratio - 1) < 0.12, "spreading keeps the level: \(ratio)")
    }

    // MARK: The rules

    @Test func aSeedRepeatsTheCloud() {
        let source = Self.textured(count: Int(Self.rate))
        let cloud = GrainCloud(size: 0.03, density: 60, positionJitter: 0.4, speed: 0,
                               pitchSpread: 5, seed: 7)
        let once = Self.render(Voice(granular: cloud, envelope: Self.flat, gain: 1),
                               source: source, pitch: 60, seconds: 0.6, gain: 0.4)
        let again = Self.render(Voice(granular: cloud, envelope: Self.flat, gain: 1),
                                source: source, pitch: 60, seconds: 0.6, gain: 0.4)
        #expect(once == again, "the same cloud twice is the same samples")

        var other = cloud
        other.seed = 8
        let different = Self.render(Voice(granular: other, envelope: Self.flat, gain: 1),
                                    source: source, pitch: 60, seconds: 0.6, gain: 0.4)
        #expect(different != once, "and another seed is another cloud")
        // The same cloud, though: the same settings scatter to the same level.
        let a = Self.rms(once[Int(0.2 * Self.rate)...]), b = Self.rms(different[Int(0.2 * Self.rate)...])
        #expect(abs(a - b) < 0.25 * max(a, b), "of the same shape: \(a) against \(b)")
    }

    @Test func noSoundMeansSilenceAndNothingElse() {
        let sound = Self.render(Voice(granular: GrainCloud()), source: nil, pitch: 60, seconds: 0.3)
        #expect(!sound.contains { abs($0) > 1e-9 })

        // And an empty one is refused the same way rather than read past.
        let empty = GrainSource(frames: [], sampleRate: Self.rate)
        #expect(empty.isEmpty)
        let none = Self.render(Voice(granular: GrainCloud()), source: empty, pitch: 60, seconds: 0.3)
        #expect(!none.contains { abs($0) > 1e-9 })
    }

    @Test func theVoiceSaysHowItCuts() throws {
        var voice = Voice(granular: GrainCloud(size: 0.03, density: 12, speed: 0))
        #expect(voice.granular?.density == 12)
        #expect(voice.wavetable == nil && voice.plucked == nil && voice.patch == nil)
        #expect(Voice.cloud.granular != nil)
        #expect(Voice.pluck.granular == nil)
        voice.granular?.speed = 0.5
        #expect(voice.granular?.speed == 0.5)
        #expect(!voice.source.isDriven)

        let data = try JSONEncoder().encode(voice)
        let back = try JSONDecoder().decode(Voice.self, from: data)
        #expect(back == voice)
    }

    @Test func everySettingIsHeldToItsRange() {
        let wild = GrainCloud(size: 40, density: 1e6, position: 9, positionJitter: -2,
                              speed: 99, pitchSpread: -1, panSpread: 4, timingJitter: 8)
        #expect(wild.size == 1)
        #expect(wild.density == 1000)
        #expect(wild.position == 1)
        #expect(wild.positionJitter == 0)
        #expect(wild.speed == 4)
        #expect(wild.pitchSpread == 0)
        #expect(wild.panSpread == 1)
        #expect(wild.timingJitter == 1)
        #expect(GrainCloud.frozen(at: 0.3).speed == 0)
    }

    @Test func aSourceCanBeBuiltFromWhatIsAlreadyHere() throws {
        let wave = GrainSource(waveform: .sawtooth, frequency: 220, seconds: 0.25)
        #expect(abs(wave.duration - 0.25) < 0.01)
        #expect(wave.rootKey == 57, "220 Hz is the A below middle C: \(wave.rootKey)")
        #expect(wave.frames.contains { abs($0) > 0.1 })

        let instrument = try #require(SampledInstrument.builtIn)
        let cut = GrainSource(recording: instrument.recording(at: 0, over: 0...127))
        #expect(!cut.isEmpty)
        #expect(cut.rootKey == instrument.recordingRoots[0])

        let bundled = try #require(GrainSource.builtIn)
        #expect(!bundled.isEmpty)
        #expect(bundled.duration > 0.1)
    }

    @Test func aCloudWithNoSoundSetReadsTheBundledOne() async {
        // The same rule a wavetable voice keeps: a first note is a sound
        // rather than silence.
        await MainActor.run {
            let synth = Synth(Voice(granular: GrainCloud()))
            #expect(synth.grainSource != nil)

            let other = Synth(.pluck)
            #expect(other.grainSource == nil)
            other.voice = .cloud
            #expect(other.grainSource != nil)
        }
    }
}
