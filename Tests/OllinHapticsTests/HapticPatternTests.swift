import Foundation
import Testing
@testable import OllinHaptics

/// The pattern algebra: how events are held, and what composing two pieces
/// does to their times. Pure values, so nothing here touches hardware.
@Suite
struct HapticPatternTests {

    /// Times are added and divided on the way through, so compare them the way
    /// floating point allows rather than to the last bit.
    func isClose(_ measured: [Double], _ wanted: [Double], within tolerance: Double = 1e-9) -> Bool {
        measured.count == wanted.count
            && zip(measured, wanted).allSatisfy { abs($0 - $1) <= tolerance }
    }

    // MARK: Holding events

    @Test func eventsAreHeldInTimeOrder() {
        let pattern = HapticPattern([
            HapticEvent(.tap, at: 0.4),
            HapticEvent(.tap, at: 0.1),
            HapticEvent(.tap, at: 0.25),
        ])
        #expect(pattern.events.map(\.time) == [0.1, 0.25, 0.4])
    }

    @Test func durationCountsTheTailOfAHum() {
        let pattern = HapticPattern([
            HapticEvent(.tap, at: 0.9),
            HapticEvent(.hum, at: 0.2, duration: 1.5),
        ])
        #expect(pattern.duration == 1.7)
        #expect(HapticPattern.none.duration == 0)
        #expect(HapticPattern.none.isEmpty)
    }

    // MARK: The numbers a sketch hands over

    @Test func everyNumberIsClampedIntoRange() {
        let event = HapticEvent(.tap, at: -3, intensity: 4, sharpness: -1)
        #expect(event.time == 0)
        #expect(event.intensity == 1)
        #expect(event.sharpness == 0)
    }

    @Test func aValueThatIsNotANumberBecomesZero() {
        // A sketch can divide by zero on the way in. One infinity in a time
        // would schedule a knock that never arrives, and one NaN would make
        // every comparison in the plan false.
        let event = HapticEvent(.hum, at: .nan, intensity: .infinity, duration: .nan)
        #expect(event.time == 0)
        #expect(event.intensity == 0)
        #expect(event.duration == 0)
    }

    @Test func aTapCarriesNoLengthAndNoFade() {
        let event = HapticEvent(.tap, duration: 2, fadeIn: 1, fadeOut: 1)
        #expect(event.duration == 0)
        #expect(event.fadeIn == 0)
        #expect(event.fadeOut == 0)
    }

    @Test func aFadeCannotOutlastItsHum() {
        let event = HapticEvent(.hum, duration: 0.4, fadeIn: 3, fadeOut: 3)
        #expect(event.fadeIn == 0.4)
        #expect(event.fadeOut == 0.4)
    }

    // MARK: Composing

    @Test func thenPlacesTheSecondPieceAfterTheFirst() {
        let pattern = HapticPattern.hum(0.5).then(.tap())
        #expect(pattern.events.count == 2)
        #expect(pattern.events[1].kind == .tap)
        #expect(pattern.events[1].time == 0.5)
    }

    @Test func silenceHoldsTheTimeOpen() {
        let pattern = HapticPattern.tap().then(.silence(0.2)).then(.tap())
        let taps = pattern.events.filter { $0.kind == .tap }
        #expect(taps.count == 2)
        #expect(taps[1].time == 0.2)
    }

    @Test func thenWithNothingChangesNothing() {
        let one = HapticPattern.tap()
        #expect(one.then(.none) == one)
        #expect(HapticPattern.none.then(one) == one)
    }

    @Test func overStartsBothPiecesTogether() {
        let pattern = HapticPattern.hum(0.5).over(.tap())
        #expect(pattern.events.count == 2)
        #expect(pattern.events.allSatisfy { $0.time == 0 })
        #expect(pattern.duration == 0.5)
    }

    @Test func delayedMovesTheWholeThing() {
        let pattern = HapticPattern.pulses(3, every: 0.1).delayed(by: 0.5)
        #expect(isClose(pattern.events.map(\.time), [0.5, 0.6, 0.7]))
    }

    @Test func repeatedWithoutAGapPlacesCopiesEndToEnd() {
        let pattern = HapticPattern.hum(0.2).repeated(3)
        #expect(isClose(pattern.events.map(\.time), [0, 0.2, 0.4]))
        #expect(isClose([pattern.duration], [0.6]))
    }

    @Test func repeatedWithAGapUsesTheGap() {
        // A gap shorter than the piece is allowed on purpose: copies overlap,
        // which is how a roll is built out of one hit.
        let pattern = HapticPattern.hum(0.5).repeated(3, every: 0.1)
        #expect(isClose(pattern.events.map(\.time), [0, 0.1, 0.2]))
    }

    @Test func repeatedOnceOrLessIsTheSameOrNothing() {
        let one = HapticPattern.tap()
        #expect(one.repeated(1) == one)
        #expect(one.repeated(0).isEmpty)
    }

    @Test func scaledMultipliesStrengthAndStopsAtFull() {
        let quiet = HapticPattern.tap(intensity: 0.8).scaled(intensity: 0.5)
        #expect(quiet.events[0].intensity == 0.4)
        let loud = HapticPattern.tap(intensity: 0.8).scaled(intensity: 4)
        #expect(loud.events[0].intensity == 1)
    }

    @Test func speedDividesEveryTime() {
        let quick = HapticPattern.hum(0.4, fadeIn: 0.2).delayed(by: 0.6).scaled(speed: 2)
        #expect(quick.events[0].time == 0.3)
        #expect(quick.events[0].duration == 0.2)
        #expect(quick.events[0].fadeIn == 0.1)
    }

    @Test func speedIgnoresAFactorItCannotUse() {
        let pattern = HapticPattern.pulses(2, every: 0.1)
        #expect(pattern.scaled(speed: 0) == pattern)
        #expect(pattern.scaled(speed: -1) == pattern)
    }

    @Test func reversedPutsTheLastEventFirst() {
        let pattern = HapticPattern.tap(intensity: 1).then(.silence(0.3)).then(.tap(intensity: 0.2))
        let back = pattern.reversed()
        #expect(back.events.first(where: { $0.kind == .tap })?.intensity == 0.2)
        #expect(back.duration == pattern.duration)
    }

    @Test func reversingTwiceIsWhereYouStarted() {
        let pattern = HapticPattern.pulses(4, every: 0.12).over(.hum(0.3))
        #expect(pattern.reversed().reversed() == pattern)
    }

    // MARK: The ready-made pieces

    @Test func pulsesAreEvenlySpaced() {
        let pattern = HapticPattern.pulses(4, every: 0.25, intensity: 0.5)
        #expect(pattern.events.count == 4)
        #expect(isClose(pattern.events.map(\.time), [0, 0.25, 0.5, 0.75]))
        #expect(pattern.events.allSatisfy { $0.intensity == 0.5 })
    }

    @Test func askingForNoPulsesGivesNothing() {
        #expect(HapticPattern.pulses(0, every: 0.1).isEmpty)
        #expect(HapticPattern.pulses(-2, every: 0.1).isEmpty)
    }
}
