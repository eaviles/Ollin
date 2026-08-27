import Foundation
import Testing
@testable import OllinHaptics

/// The translation from a written pattern into what a trackpad can deliver.
/// A pure function, so every rule in it is checked here with no hardware and
/// no waiting.
@Suite
struct TrackpadPlanTests {

    // MARK: Sharpness picks the feeling

    @Test func sharpnessPicksOneOfThreeFeelings() {
        #expect(TrackpadPlan.feel(forSharpness: 0) == .soft)
        #expect(TrackpadPlan.feel(forSharpness: 0.2) == .soft)
        #expect(TrackpadPlan.feel(forSharpness: 0.5) == .level)
        #expect(TrackpadPlan.feel(forSharpness: 0.9) == .crisp)
        #expect(TrackpadPlan.feel(forSharpness: 1) == .crisp)
    }

    @Test func aTapBecomesOneKnockWhereItWasWritten() {
        let knocks = TrackpadPlan.knocks(for: .tap(sharpness: 0.9).delayed(by: 0.3))
        #expect(knocks.count == 1)
        #expect(knocks[0].time == 0.3)
        #expect(knocks[0].feel == .crisp)
    }

    // MARK: Strength becomes density

    @Test func aStrongerHumIsADenserTrain() {
        let weak = TrackpadPlan.knocks(for: .hum(1, intensity: 0.2))
        let strong = TrackpadPlan.knocks(for: .hum(1, intensity: 1))
        #expect(weak.count > 1)
        #expect(strong.count > weak.count)
        // The rate at full strength is the one the plan promises.
        #expect(abs(Double(strong.count) - TrackpadPlan.fastestHum) <= 2)
    }

    @Test func theTrainCoversTheWholeHumAndNoMore() {
        let hum = HapticPattern.hum(0.5, intensity: 0.8).delayed(by: 0.25)
        let knocks = TrackpadPlan.knocks(for: hum)
        #expect(knocks.first?.time == 0.25)
        #expect(knocks.last!.time <= 0.75 + 1e-9)
    }

    @Test func aFadeInThinsTheStartOfTheTrain() {
        // The hand reads a train that starts slow and thickens as a sound
        // arriving, which is what a fade is for. The gaps must shrink.
        let knocks = TrackpadPlan.knocks(for: .hum(1.2, intensity: 1, fadeIn: 0.8))
        let gaps = zip(knocks.dropFirst(), knocks).map { $0.time - $1.time }
        #expect(gaps.count > 3)
        #expect(gaps.first! > gaps.last!)
    }

    @Test func aFadeOutEndsInSilenceRatherThanAStrayKnock() {
        let faded = HapticPattern.hum(1, intensity: 1, fadeOut: 0.5)
        let knocks = TrackpadPlan.knocks(for: faded)
        // The tail falls under the floor before the hum is over, so the last
        // knock lands short of the end.
        #expect(knocks.last!.time < 0.98)
    }

    // MARK: The floor

    @Test func anEventUnderTheFloorIsNotPlanned() {
        #expect(TrackpadPlan.knocks(for: .tap(intensity: 0.02)).isEmpty)
        #expect(TrackpadPlan.knocks(for: .hum(1, intensity: 0.01)).isEmpty)
        #expect(TrackpadPlan.knocks(for: .silence(0.5)).isEmpty)
    }

    @Test func theOverallStrengthCanTakeAPatternUnderTheFloor() {
        let pattern = HapticPattern.tap(intensity: 0.08)
        #expect(TrackpadPlan.knocks(for: pattern, strength: 1).count == 1)
        #expect(TrackpadPlan.knocks(for: pattern, strength: 0.5).isEmpty)
        #expect(TrackpadPlan.knocks(for: pattern, strength: 0).isEmpty)
    }

    // MARK: Spacing

    @Test func knocksTooCloseTogetherAreDropped() {
        let crowded = HapticPattern([
            HapticEvent(.tap, at: 0),
            HapticEvent(.tap, at: 0.005),
            HapticEvent(.tap, at: 0.008),
            HapticEvent(.tap, at: 0.4),
        ])
        let knocks = TrackpadPlan.knocks(for: crowded)
        #expect(knocks.map(\.time) == [0, 0.4])
    }

    @Test func knocksComeOutInOrderEvenWhenPiecesOverlap() {
        let layered = HapticPattern.hum(0.6, intensity: 0.5)
            .over(.pulses(3, every: 0.2).delayed(by: 0.05))
        let times = TrackpadPlan.knocks(for: layered).map(\.time)
        #expect(times == times.sorted())
    }

    // MARK: Not running away

    @Test func aVeryLongHumStopsAtTheCap() {
        let knocks = TrackpadPlan.knocks(for: .hum(10_000, intensity: 1))
        #expect(knocks.count <= TrackpadPlan.maximumKnocks)
        #expect(knocks.count > 100)
    }

    @Test func nothingIsPlannedForAnEmptyPattern() {
        #expect(TrackpadPlan.knocks(for: .none).isEmpty)
    }

    // MARK: The shape of a fade, read on its own

    @Test func theStrengthInsideAHumFollowsItsFades() {
        let event = HapticEvent(.hum, intensity: 1, duration: 1, fadeIn: 0.25, fadeOut: 0.25)
        #expect(event.strength(at: 0) == 0)
        #expect(abs(event.strength(at: 0.125) - 0.5) < 1e-9)
        #expect(event.strength(at: 0.5) == 1)
        #expect(abs(event.strength(at: 0.875) - 0.5) < 1e-9)
        #expect(event.strength(at: 1) == 0)
    }

    @Test func aTapIsAlwaysAtFullStrengthWhereItStands() {
        let event = HapticEvent(.tap, intensity: 0.7)
        #expect(event.strength(at: 0) == 0.7)
    }
}
