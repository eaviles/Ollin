import AppKit
import CoreHaptics
import Foundation
import Testing
@testable import OllinHaptics

/// A stand-in for the trackpad: it takes the calls and writes them down.
final class RecordingPerformer: NSObject, NSHapticFeedbackPerformer, @unchecked Sendable {
    var performed: [NSHapticFeedbackManager.FeedbackPattern] = []

    func perform(
        _ pattern: NSHapticFeedbackManager.FeedbackPattern,
        performanceTime: NSHapticFeedbackManager.PerformanceTime
    ) {
        performed.append(pattern)
    }
}

/// The translation into the system's own haptic pattern.
///
/// This machine reports no haptic engine, so nothing here can be played. The
/// translation is still worth checking, and it can be: the system builds a
/// pattern out of events without asking the hardware anything, so the events
/// are read straight back off what was built.
@Suite
struct DeviceHapticsTests {

    func value(_ event: CHHapticEvent, _ id: CHHapticEvent.ParameterID) -> Float? {
        event.eventParameters.first { $0.parameterID == id }?.value
    }

    @Test func aTapBecomesOneInstantWithStrengthAndCrispness() {
        let events = DeviceHaptics.events(
            from: .tap(intensity: 0.6, sharpness: 0.25).delayed(by: 0.4), strength: 1)
        #expect(events.count == 1)
        #expect(events[0].type == .hapticTransient)
        #expect(events[0].relativeTime == 0.4)
        #expect(value(events[0], .hapticIntensity) == 0.6)
        #expect(value(events[0], .hapticSharpness) == 0.25)
    }

    @Test func aHumBecomesOneStretchWithItsLength() {
        let events = DeviceHaptics.events(from: .hum(0.8, intensity: 0.5), strength: 1)
        #expect(events.count == 1)
        #expect(events[0].type == .hapticContinuous)
        #expect(events[0].duration == 0.8)
        #expect(value(events[0], .sustained) == 1)
    }

    @Test func aFadeRidesTheSystemEnvelopeAsAShareOfTheHum() {
        // The system takes an attack as a share of the event, not as seconds,
        // so a quarter-length fade arrives as a quarter.
        let events = DeviceHaptics.events(
            from: .hum(1, fadeIn: 0.25, fadeOut: 0.5), strength: 1)
        #expect(value(events[0], .attackTime) == 0.25)
        #expect(value(events[0], .releaseTime) == 0.5)
    }

    @Test func silenceIsDropped() {
        #expect(DeviceHaptics.events(from: .silence(0.4), strength: 1).isEmpty)
        #expect(DeviceHaptics.events(from: .tap(), strength: 0).isEmpty)
    }

    @Test func theOverallStrengthScalesAndStopsAtFull() {
        let half = DeviceHaptics.events(from: .tap(intensity: 0.8), strength: 0.5)
        #expect(value(half[0], .hapticIntensity) == 0.4)
        let over = DeviceHaptics.events(from: .tap(intensity: 0.8), strength: 4)
        #expect(value(over[0], .hapticIntensity) == 1)
    }

    @Test func theWholePatternBuilds() throws {
        // The system works out its own duration from the envelope it will
        // play, so that number is not ours to predict. What this checks is
        // that a composed pattern reaches it whole: the silence in the middle
        // drops out, and the two felt pieces arrive where they were written.
        let pattern = HapticPattern.tap().then(.silence(0.1)).then(.hum(0.5, fadeOut: 0.2))
        let events = DeviceHaptics.events(from: pattern, strength: 1)
        #expect(events.map(\.type) == [.hapticTransient, .hapticContinuous])
        #expect(events.map(\.relativeTime) == [0, 0.1])
        let built = try DeviceHaptics.makePattern(from: pattern, strength: 1)
        #expect(built.duration > 0)
    }

    @Test func aPatternWithNothingLeftToPlayRefusesToBuild() {
        #expect(throws: (any Error).self) {
            try DeviceHaptics.makePattern(from: .silence(1), strength: 1)
        }
    }
}

/// The hub: what it decides the hardware is, what it schedules, and the two
/// rules that stop a sketch from asking for more than the actuator can do.
///
/// Serialized, because there is one hub for the process and each test replaces
/// its seams.
@Suite(.serialized)
@MainActor
struct HapticHubTests {

    /// A hub with every seam replaced, so no real hardware and no real waiting
    /// is involved.
    ///
    /// The stand-in scheduler runs each knock at once and moves the stand-in
    /// clock to the moment that knock was meant for. Without that move the
    /// whole timeline would happen at one instant, and the rule that spaces
    /// knocks would throw away everything after the first.
    func prepare(
        trackpad: Bool = true,
        engine: Bool = false
    ) -> (hub: HapticHub, performer: RecordingPerformer, timeline: Timeline) {
        let hub = HapticHub.shared
        let performer = RecordingPerformer()
        let timeline = Timeline()
        hub.performer = performer
        hub.trackpadIsPresent = { trackpad }
        hub.engineIsPresent = { engine }
        hub.strength = 1
        hub.clock = { timeline.now }
        hub.schedule = { delay, body in
            timeline.delays.append(delay)
            timeline.now = timeline.start + delay
            body()
        }
        hub.forgetHardware()
        hub.stop()
        return (hub, performer, timeline)
    }

    /// A clock the test winds by hand, and a note of every delay asked for.
    final class Timeline {
        var now = 0.0
        var delays: [Double] = []
        /// Where the pattern being played started, so a delay reads from it.
        var start = 0.0
    }

    // MARK: What the hardware is

    @Test func aTrackpadIsFoundWhenThereIsNoEngine() {
        let (hub, _, _) = prepare(trackpad: true, engine: false)
        #expect(hub.hardware == .trackpad)
        #expect(hub.unavailableReason == nil)
    }

    @Test func anEngineWinsOverATrackpad() {
        let (hub, _, _) = prepare(trackpad: true, engine: true)
        #expect(hub.hardware == .engine)
    }

    @Test func aMachineWithNeitherSaysWhy() {
        let (hub, performer, _) = prepare(trackpad: false, engine: false)
        #expect(hub.hardware == .none)
        #expect(hub.unavailableReason != nil)
        hub.play(.tap())
        #expect(performer.performed.isEmpty)
    }

    // MARK: Scheduling

    @Test func everyPlannedKnockIsScheduledAtItsOwnMoment() {
        let (hub, performer, timeline) = prepare()
        hub.play(.pulses(3, every: 0.25))
        #expect(timeline.delays == [0, 0.25, 0.5])
        #expect(performer.performed.count == 3)
    }

    @Test func theFeelingReachesTheSystemUnchanged() {
        let (hub, performer, _) = prepare()
        hub.play(.tap(sharpness: 0.1).then(.silence(0.5)).then(.tap(sharpness: 0.9)))
        #expect(performer.performed == [.generic, .alignment])
    }

    @Test func theStrengthParameterReachesThePlan() {
        let (hub, performer, _) = prepare()
        hub.strength = 0
        hub.play(.tap())
        #expect(performer.performed.isEmpty)
    }

    @Test func stoppingCancelsWhatHasNotBeenFeltYet() {
        let hub = HapticHub.shared
        let performer = RecordingPerformer()
        var pending: [@MainActor () -> Void] = []
        hub.performer = performer
        hub.trackpadIsPresent = { true }
        hub.engineIsPresent = { false }
        hub.strength = 1
        hub.clock = { 0 }
        hub.schedule = { _, body in pending.append(body) }
        hub.forgetHardware()

        hub.play(.pulses(3, every: 0.25))
        hub.stop()
        for body in pending { body() }
        #expect(performer.performed.isEmpty)
    }

    // MARK: The rule that guards the hardware across calls

    @Test func aSketchCallingEveryFrameCannotFloodTheActuator() {
        // Each of these patterns is legal on its own. The pile of them is not,
        // and the plan cannot see the pile, because it only ever sees one
        // pattern. Ten taps arrive 6 ms apart, which is faster than the
        // hardware is asked to go, so three land and the rest are dropped.
        let (hub, performer, timeline) = prepare()
        for step in 0..<10 {
            timeline.start = Double(step) * 0.006
            hub.play(.tap())
        }
        #expect(performer.performed.count == 3)
    }

    @Test func aKnockLandsOnceTheGapHasPassed() {
        let (hub, performer, timeline) = prepare()
        hub.play(.tap())
        timeline.start = TrackpadPlan.minSpacing
        hub.play(.tap())
        #expect(performer.performed.count == 2)
    }
}
