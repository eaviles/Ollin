import Foundation
import Ollin
import Testing
@testable import OllinAudio

/// The claim a struck body makes is that its frequencies come out of its shape
/// rather than being chosen, which is checkable: a round shape has to give the
/// ratios a real drumhead gives, and a square one the ratios a square membrane
/// gives. Both are known in closed form, so the solver is measured against
/// physics rather than against itself.
@Suite struct ModalBodyTests {

    static let sampleRate = 44100.0

    // MARK: - Shapes

    /// A circular membrane rings at ratios set by the zeros of the Bessel
    /// functions. Nothing in the solver knows that; it measures the shape.
    ///
    /// A round shape's tones come in pairs, because a pattern with lobes round
    /// the rim fits at any rotation and two of those are independent, so every
    /// tone but the ones with no rotation at all is there twice. That is a real
    /// property of a real drum, not an artefact, and the list below carries it.
    @Test func aRoundShapeRingsLikeADrumhead() {
        let body = ModalBody(shape: Self.circle(radius: 100), modes: 6, resolution: 44)
        // The zeros again, each repeated as many times as it occurs: the first
        // and the fourth once, the rest twice.
        let zeros = [2.404826, 3.831706, 3.831706, 5.135622, 5.135622, 5.520078]
        let known = zeros.map { $0 / zeros[0] }

        #expect(body.count >= 6)
        for index in 0..<6 {
            let measured = body.modes[index].ratio
            let error = abs(measured - known[index]) / known[index]
            #expect(error < 0.03, "mode \(index): measured \(measured), a drumhead gives \(known[index])")
        }
    }

    /// A square membrane's ratios are the square roots of `m² + n²`.
    @Test func aSquareShapeRingsLikeASquareMembrane() {
        let body = ModalBody(shape: Self.rectangle(width: 100, height: 100),
                             modes: 6, resolution: 44)
        let known = ModalBody.squareRatios

        for index in 0..<6 {
            let measured = body.modes[index].ratio
            let error = abs(measured - known[index]) / known[index]
            #expect(error < 0.03, "mode \(index): measured \(measured), a square gives \(known[index])")
        }
    }

    /// Stretching a shape changes what it rings at, which is the whole point.
    /// A rectangle twice as long as it is wide has a known second ratio.
    @Test func stretchingAShapeChangesWhatItRingsAt() {
        let oblong = ModalBody(shape: Self.rectangle(width: 100, height: 200),
                               modes: 4, resolution: 44)
        // For a rectangle, the eigenvalues go as (m/a)² + (n/b)². With b twice
        // a, the first two are 1.25 and 2 in those units.
        let expected = (2.0 / 1.25).squareRoot()
        #expect(abs(oblong.modes[1].ratio - expected) / expected < 0.03,
                "measured \(oblong.modes[1].ratio), a 1:2 rectangle gives \(expected)")

        let square = ModalBody(shape: Self.rectangle(width: 100, height: 100),
                               modes: 4, resolution: 44)
        #expect(abs(square.modes[1].ratio - oblong.modes[1].ratio) > 0.2,
                "a square and an oblong came out the same")
    }

    /// Only the shape decides the ratios, not how big it was drawn. The same
    /// outline at four times the size is the same instrument.
    @Test func sizeDoesNotChangeTheRatios() {
        let small = ModalBody(shape: Self.circle(radius: 40), modes: 5, resolution: 44)
        let large = ModalBody(shape: Self.circle(radius: 160), modes: 5, resolution: 44)
        for index in 0..<5 {
            #expect(abs(small.modes[index].ratio - large.modes[index].ratio) < 0.02,
                    "mode \(index): \(small.modes[index].ratio) vs \(large.modes[index].ratio)")
        }
    }

    /// A hole is part of the shape, so it changes the sound.
    @Test func aHoleChangesWhatAShapeRingsAt() {
        let solid = ModalBody(shape: Self.circle(radius: 100), modes: 4, resolution: 44)
        let ring = ModalBody(shape: Shape(outer: Self.circlePoints(radius: 100),
                                          holes: [Self.circlePoints(radius: 45)]),
                             modes: 4, resolution: 44)
        #expect(abs(solid.modes[1].ratio - ring.modes[1].ratio) > 0.05,
                "solid \(solid.modes[1].ratio) vs ring \(ring.modes[1].ratio)")
    }

    /// Where a shape is struck decides which of its tones answer. A round shape
    /// hit exactly in the middle can only ring in the shapes that move there,
    /// which are the ones with no rotational pattern; every other tone holds
    /// still in the middle. Its twin, struck off center, wakes them all.
    @Test func strikingTheMiddleOfARoundShapeSilencesHalfOfIt() {
        // Measured once, then struck twice, which is what `StruckShape` is for.
        let measured = StruckShape(Self.circle(radius: 100), modes: 5, resolution: 44)
        #expect(measured != nil)
        let middle = measured!.body(struckAt: Vector2(0, 0))
        let offCenter = measured!.body(struckAt: Vector2(48, 26))

        // The tone at 1.593 is there twice, and which of the pair carries the
        // energy at any one point is arbitrary: both ring at the same
        // frequency, so only their total is a real quantity. Hence the sum.
        func gain(of body: ModalBody, near ratio: Double) -> Double {
            body.modes.filter { abs($0.ratio - ratio) < 0.08 }.reduce(0) { $0 + $1.gain }
        }
        let centerGain = gain(of: middle, near: 1.593)
        let offGain = gain(of: offCenter, near: 1.593)
        #expect(offGain > 0.2, "an off center strike should reach it, got \(offGain)")
        #expect(centerGain < 0.25 * offGain,
                "center \(centerGain) vs off center \(offGain)")
    }

    /// Measuring once and striking twice must agree with measuring twice, so
    /// the cheap path and the plain one are the same instrument.
    @Test func measuringOnceAndStrikingTwiceMatchesMeasuringTwice() {
        let outline = Self.rectangle(width: 120, height: 80)
        let measured = StruckShape(outline, modes: 6, resolution: 40)
        #expect(measured != nil)
        let point = Vector2(38, 51)
        #expect(measured!.body(struckAt: point, decay: 3, damping: 0.5, hardness: 0.4)
                == ModalBody(shape: outline, struckAt: point, modes: 6, resolution: 40,
                             decay: 3, damping: 0.5, hardness: 0.4))
    }

    @Test func theSameShapeAlwaysGivesTheSameAnswer() {
        let outline = Self.circle(radius: 100)
        let one = ModalBody(shape: outline, modes: 8, resolution: 44)
        let same = ModalBody(shape: outline, modes: 8, resolution: 44)
        #expect(one == same)
    }

    /// A shape too small to hold a standing wave falls back rather than
    /// producing nonsense.
    @Test func aShapeTooSmallToMeasureFallsBack() {
        let sliver = Shape([Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.01), Vector2(0, 0.01)])
        let body = ModalBody(shape: sliver, modes: 4, resolution: 8)
        #expect(body.count > 0)
        #expect(body.modes.allSatisfy { $0.ratio.isFinite && $0.ratio >= 1 })
    }

    // MARK: - The body as a value

    @Test func modesArePutInOrderAndMeasuredAgainstTheirLowest() {
        let body = ModalBody(modes: [
            ModalBody.Mode(ratio: 900, gain: 0.5),
            ModalBody.Mode(ratio: 300, gain: 0.25),
            ModalBody.Mode(ratio: 600, gain: 1.0),
        ])
        #expect(body.count == 3)
        #expect(body.modes.map(\.ratio) == [1, 2, 3])
        #expect(body.modes[2].gain == 0.5)      // the loudest is 1, the rest follow
        #expect(body.modes[1].gain == 1.0)
    }

    @Test func aBodyIsCappedAtWhatItCanCarry() {
        let many = (1...40).map { ModalBody.Mode(ratio: Double($0), gain: 1) }
        #expect(ModalBody(modes: many).count == ModalBody.maxModes)
        #expect(ModalBody(modes: []).count == 0)
    }

    @Test func aBodyIsAnOrdinaryVoice() {
        #expect(Voice.chime.body == .bell)
        #expect(Voice.chime.string == nil)
        #expect(Voice.nylon.body == nil)

        var voice = Voice.drum
        voice.waveform = .square
        #expect(voice.body == nil)
        voice.body = .glass
        #expect(voice.source == .body(.glass))
    }

    // MARK: - What it sounds like

    /// A struck body puts energy at its own ratios and not between them.
    @Test func theToneComesOutAtTheRatiosTheBodyNames() {
        let body = ModalBody(modes: [
            ModalBody.Mode(ratio: 1, gain: 1),
            ModalBody.Mode(ratio: 2.4, gain: 0.8),
            ModalBody.Mode(ratio: 4.1, gain: 0.6),
        ], decay: 3, damping: 0.2, hardness: 0.9)

        let fundamental = 220.0
        let samples = renderNote(body, midi: Pitch(frequency: fundamental).midi, seconds: 0.6)

        for mode in body.modes {
            let atMode = magnitude(samples, at: fundamental * mode.ratio)
            // Between two of its tones there should be very little, which is
            // what makes this a bank of tones rather than a noise.
            let between = magnitude(samples, at: fundamental * (mode.ratio + 0.5))
            #expect(atMode > 8 * between,
                    "ratio \(mode.ratio): \(atMode) at the tone, \(between) beside it")
        }
    }

    /// Higher tones going sooner is what `damping` means. The twins differ only
    /// in that.
    @Test func dampingTakesTheHighTonesFirst() {
        let base = ModalBody(modes: [
            ModalBody.Mode(ratio: 1, gain: 1), ModalBody.Mode(ratio: 6, gain: 1),
        ], decay: 3, damping: 0)
        var steep = base
        steep.damping = 2.5

        let fundamental = 200.0
        let midi = Pitch(frequency: fundamental).midi
        let window = Int(Self.sampleRate) / 4
        let start = Int(Self.sampleRate * 0.7)

        let evenly = Array(renderNote(base, midi: midi, seconds: 1.2)[start..<(start + window)])
        let steeply = Array(renderNote(steep, midi: midi, seconds: 1.2)[start..<(start + window)])

        let evenlyHigh = magnitude(evenly, at: fundamental * 6)
        let steeplyHigh = magnitude(steeply, at: fundamental * 6)
        let evenlyLow = magnitude(evenly, at: fundamental)
        let steeplyLow = magnitude(steeply, at: fundamental)

        #expect(steeplyHigh < 0.15 * evenlyHigh, "\(steeplyHigh) vs \(evenlyHigh)")
        // And the low tone is still there in both, so this is about which tone
        // went rather than about the whole thing stopping.
        #expect(steeplyLow > 0.5 * evenlyLow, "\(steeplyLow) vs \(evenlyLow)")
    }

    /// A hard strike is over at once and reaches everything; a soft one leans
    /// on the body and only the low tones answer.
    @Test func aHarderStrikeReachesTheHigherTones() {
        var soft = ModalBody.bell
        soft.hardness = 0.0
        var hard = ModalBody.bell
        hard.hardness = 1.0

        let fundamental = 300.0
        let midi = Pitch(frequency: fundamental).midi
        let softly = renderNote(soft, midi: midi, seconds: 0.4)
        let firmly = renderNote(hard, midi: midi, seconds: 0.4)

        let top = fundamental * 4
        #expect(magnitude(firmly, at: top) > 4 * magnitude(softly, at: top),
                "hard \(magnitude(firmly, at: top)) vs soft \(magnitude(softly, at: top))")
    }

    @Test func decaySetsHowLongItRings() {
        var quick = ModalBody.bell
        quick.decay = 0.3
        var long = ModalBody.bell
        long.decay = 8

        let window = Int(Self.sampleRate) / 10
        let start = Int(Self.sampleRate)
        let quickly = Array(renderNote(quick, midi: 60, seconds: 1.4)[start..<(start + window)])
        let slowly = Array(renderNote(long, midi: 60, seconds: 1.4)[start..<(start + window)])
        #expect(rms(quickly) < 0.05 * rms(slowly), "\(rms(quickly)) vs \(rms(slowly))")
    }

    /// A tone above half the sample rate cannot be represented, so it is
    /// dropped rather than folded back down the spectrum as something that was
    /// never struck.
    @Test func tonesPastWhatCanBeHeardAreDroppedRatherThanFolded() {
        // The fourth mode of this body lands at 40 kHz when played at 5 kHz,
        // which would fold to about 4 kHz if it were kept.
        let body = ModalBody(modes: [
            ModalBody.Mode(ratio: 1, gain: 1), ModalBody.Mode(ratio: 8, gain: 1),
        ], decay: 2, damping: 0)
        let samples = renderNote(body, midi: Pitch(frequency: 5000).midi, seconds: 0.3)
        let folded = 2 * Self.sampleRate / 2 - 40000
        #expect(magnitude(samples, at: folded) < 0.002,
                "something appeared at \(folded) Hz: \(magnitude(samples, at: folded))")
        #expect(magnitude(samples, at: 5000) > 0.01)
    }

    @Test func itStaysBoundedAtEveryPitchAndSetting() {
        for midi in stride(from: 24.0, through: 108.0, by: 7) {
            for body in [ModalBody.drum, .plate, .bar, .bell, .wood, .glass] {
                let samples = renderNote(body, midi: midi, seconds: 0.25, velocity: 1)
                let peak = samples.map { abs($0) }.max() ?? 0
                #expect(peak.isFinite && peak <= 1.01, "midi \(midi) reached \(peak)")
                #expect(samples.allSatisfy { $0.isFinite })
            }
        }
    }

    @Test func theSameNoteRendersToTheSameSamples() {
        #expect(renderNote(.bell, midi: 60, seconds: 0.3)
                == renderNote(.bell, midi: 60, seconds: 0.3))
    }

    // MARK: - Shapes to strike

    private static func circlePoints(radius: Double, steps: Int = 160) -> [Vector2] {
        (0..<steps).map { step in
            let angle = Double(step) / Double(steps) * .tau
            return Vector2(cos(angle) * radius, sin(angle) * radius)
        }
    }

    private static func circle(radius: Double) -> Shape {
        Shape(circlePoints(radius: radius))
    }

    private static func rectangle(width: Double, height: Double) -> Shape {
        Shape([Vector2(0, 0), Vector2(width, 0), Vector2(width, height), Vector2(0, height)])
    }

    // MARK: - Rendering and measuring

    private func renderNote(
        _ body: ModalBody, midi: Double, seconds: Double, velocity: Double = 0.9
    ) -> [Float] {
        let events = EventRing()
        let voice = Voice(body: body, envelope: Envelope(attack: 0.0002, decay: 0.001,
                                                         sustain: 1, release: 0.1), gain: 1)
        let renderer = SynthRenderer(
            voice: voice, polyphony: 4, sampleRate: Self.sampleRate, events: events, seed: 7
        )
        renderer.gain = 1
        events.push(SynthEvent(kind: .noteOn, pitch: midi, velocity: velocity))

        let count = Int(seconds * Self.sampleRate)
        var samples = [Float](repeating: 0, count: count)
        samples.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: count) }
        return samples
    }

    private func magnitude(_ samples: [Float], at frequency: Double) -> Double {
        let count = samples.count
        guard count > 8 else { return 0 }
        var real = 0.0
        var imaginary = 0.0
        var weight = 0.0
        let step = 2 * Double.pi * frequency / Self.sampleRate
        for index in 0..<count {
            let hann = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(count - 1))
            let value = Double(samples[index]) * hann
            real += value * cos(step * Double(index))
            imaginary -= value * sin(step * Double(index))
            weight += hann
        }
        return weight > 0 ? sqrt(real * real + imaginary * imaginary) * 2 / weight : 0
    }

    private func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
            .squareRoot()
    }
}
