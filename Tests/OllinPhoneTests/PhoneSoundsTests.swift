import Testing
import Foundation
import Ollin
import OllinPhone

/// Exercises the phone's ears with no phone attached: the `.sound` wire kind's
/// round trip, and the laws `PhoneSounds` keeps over staged readings, which are
/// the same laws the Mac's own classifier keeps (a level for every label, the
/// strongest one whatever the threshold, an event only on a crossing from
/// below). All GPU-free, so it runs anywhere.
///
/// No time limit, unlike its siblings: `PhoneSounds` lives on the main actor,
/// so this suite does too, and on the runner every main-actor suite in the
/// process takes its turn on one main actor. A limit here measured the queue
/// ahead of it rather than the work (all fourteen tests expired together at
/// 407 seconds on 2026-09-13); the process watchdog is what catches a wedge.
@MainActor
@Suite struct PhoneSoundsTests {

    // MARK: The wire

    @Test func roundTripsAReading() {
        let sample = PhoneSoundSample(timestamp: 12.25, duration: 1.5, classifications: [
            PhoneSoundClassification(label: "dog_bark", confidence: 0.91),
            PhoneSoundClassification(label: "speech", confidence: 0.4),
            PhoneSoundClassification(label: "música", confidence: 0.07),     // non-ASCII survives
            PhoneSoundClassification(label: "silence", confidence: 0),
        ])
        #expect(roundTrip(.sound(sample)) == .sound(sample))
    }

    @Test func roundTripsAnEmptyReading() {
        // A classifier that reports nothing (a model with no labels yet) is a
        // valid reading, not a broken frame.
        let sample = PhoneSoundSample(timestamp: 0, duration: 1, classifications: [])
        #expect(roundTrip(.sound(sample)) == .sound(sample))
    }

    /// The built-in vocabulary is three hundred-odd labels, past what one count
    /// byte holds, so the count must be two bytes and every label must come back.
    @Test func aWholeVocabularySurvivesTheWire() throws {
        let labels = (0..<320).map {
            PhoneSoundClassification(label: "label_\($0)", confidence: Float(320 - $0) / 320)
        }
        let sample = PhoneSoundSample(timestamp: 3, duration: 1.5, classifications: labels)
        guard case .sound(let back)? = roundTrip(.sound(sample)) else {
            Issue.record("the reading did not come back")
            return
        }
        #expect(back.classifications.count == 320)
        #expect(back.classifications.last?.label == "label_319")
    }

    @Test func aTruncatedReadingDecodesToNothing() {
        // Cut inside the last label's confidence: the whole reading is refused
        // rather than half a list handed over.
        let sample = PhoneSoundSample(timestamp: 1, duration: 1, classifications: [
            PhoneSoundClassification(label: "clapping", confidence: 0.8),
            PhoneSoundClassification(label: "music", confidence: 0.2),
        ])
        let data = PhoneWire.encode(.sound(sample))
        let cut = data.prefix(data.count - 2)
        guard let header = PhoneHeader.parse(cut) else {
            Issue.record("the header did not parse")
            return
        }
        let payload = cut.subdata(in: (cut.startIndex + PhoneWire.headerByteCount) ..< cut.endIndex)
        #expect(PhoneWire.decode(header: header, payload: payload) == nil)
    }

    // MARK: The laws

    /// A level is there for every label the phone reported, whatever the
    /// threshold, and zero for one it never named.
    @Test func everyReportedLabelHasALevel() {
        let ears = PhoneSounds()
        ears.hear([.init(label: "music", confidence: 0.3),
                   .init(label: "speech", confidence: 0.05)], at: 0)
        #expect(ears.confidence(of: "music") == 0.3)
        #expect(ears.confidence(of: "speech") == 0.05)
        #expect(ears.confidence(of: "dog_bark") == 0)
    }

    /// The strongest label is reported whatever the threshold; the list above
    /// the threshold is only what reaches it, strongest first.
    @Test func theStrongestLabelIgnoresTheThresholdAndTheListHonorsIt() {
        let ears = PhoneSounds()
        ears.hear([.init(label: "speech", confidence: 0.35),
                   .init(label: "clapping", confidence: 0.7),
                   .init(label: "music", confidence: 0.65)], at: 0)
        #expect(ears.topClassification?.label == "clapping")
        #expect(ears.classifications.map(\.label) == ["clapping", "music"])
        ears.threshold = 0.9
        #expect(ears.topClassification?.label == "clapping")
        // The threshold applies from the next reading on.
        ears.hear([.init(label: "clapping", confidence: 0.7)], at: 0.75)
        #expect(ears.classifications.isEmpty)
        #expect(ears.topClassification?.label == "clapping")
    }

    /// A label crossing the threshold from below is one event, stamped with the
    /// end of the window it crossed in; a label that stays above fires no more.
    @Test func aCrossingFromBelowIsOneEvent() {
        let ears = PhoneSounds()
        ears.hear([.init(label: "dog_bark", confidence: 0.2)], at: 0, duration: 1.5)
        #expect(ears.events().isEmpty)
        ears.hear([.init(label: "dog_bark", confidence: 0.8)], at: 0.75, duration: 1.5)
        let events = ears.events()
        #expect(events.count == 1)
        #expect(events.first?.label == "dog_bark")
        #expect(events.first?.confidence == 0.8)
        #expect(events.first?.time == 2.25)
        // Held above the threshold across the next two windows: nothing new.
        ears.hear([.init(label: "dog_bark", confidence: 0.85)], at: 1.5, duration: 1.5)
        ears.hear([.init(label: "dog_bark", confidence: 0.7)], at: 2.25, duration: 1.5)
        #expect(ears.events().isEmpty)
    }

    /// A sound that stops and starts again is two events.
    @Test func aSoundThatReturnsFiresAgain() {
        let ears = PhoneSounds()
        ears.hear([.init(label: "knock", confidence: 0.9)], at: 0)
        ears.hear([.init(label: "knock", confidence: 0.1)], at: 1)
        ears.hear([.init(label: "knock", confidence: 0.9)], at: 2)
        let events = ears.events()
        #expect(events.map(\.label) == ["knock", "knock"])
        #expect(events.map(\.time) == [1.5, 3.5])
    }

    /// Two labels crossing in one window are two events, strongest first, and
    /// draining hands each out once.
    @Test func eventsDrain() {
        let ears = PhoneSounds()
        ears.hear([.init(label: "speech", confidence: 0.7),
                   .init(label: "laughter", confidence: 0.95)], at: 0)
        #expect(ears.events().map(\.label) == ["laughter", "speech"])
        #expect(ears.events().isEmpty)
    }

    /// The reading a phone sends is ranked on arrival, so a list in any order
    /// reads the same.
    @Test func aReadingIsRankedOnArrival() {
        let ears = PhoneSounds()
        ears.hear([.init(label: "a", confidence: 0.61),
                   .init(label: "c", confidence: 0.99),
                   .init(label: "b", confidence: 0.8)], at: 0)
        #expect(ears.classifications.map(\.label) == ["c", "b", "a"])
        #expect(ears.events().map(\.label) == ["c", "b", "a"])
    }

    /// Time since hearing is huge before a label is ever heard, and starts at
    /// zero the moment it is, on the phone's clock carried forward by the Mac's.
    @Test func timeSinceHearingRunsFromTheCrossing() {
        let ears = PhoneSounds()
        #expect(ears.timeSinceHearing("clapping") == .greatestFiniteMagnitude)
        ears.hear([.init(label: "clapping", confidence: 0.9)], at: 4, duration: 1.5)
        let since = ears.timeSinceHearing("clapping")
        #expect(since >= 0 && since < 0.5)
        // A later window with the label still above it moves the mark forward.
        ears.hear([.init(label: "clapping", confidence: 0.9)], at: 5, duration: 1.5)
        #expect(ears.timeSinceHearing("clapping") < 0.5)
        // A window without it leaves the mark where it was, and the clock runs on.
        ears.hear([.init(label: "clapping", confidence: 0.1)], at: 8, duration: 1.5)
        let later = ears.timeSinceHearing("clapping")
        #expect(later >= 3 && later < 3.5)
    }

    /// Nothing has been heard until a reading arrives, and a reading counts.
    @Test func listeningIsReadOffTheReadings() {
        let ears = PhoneSounds()
        #expect(!ears.isListening)
        #expect(ears.readingCount == 0)
        #expect(ears.topClassification == nil)
        ears.hear([.init(label: "silence", confidence: 0.9)], at: 0)
        #expect(ears.isListening)
        #expect(ears.readingCount == 1)
    }

    /// The threshold is clamped to its range, and a reset forgets what was
    /// heard but not the threshold.
    @Test func resetKeepsTheThreshold() {
        let ears = PhoneSounds()
        ears.threshold = 1.7
        #expect(ears.threshold == 1)
        ears.threshold = 0.4
        ears.hear([.init(label: "beep", confidence: 0.5)], at: 0)
        #expect(ears.events().count == 1)
        ears.reset()
        #expect(ears.threshold == 0.4)
        #expect(ears.topClassification == nil)
        #expect(ears.confidence(of: "beep") == 0)
        #expect(ears.readingCount == 0)
        // After a reset the same sound is a fresh crossing.
        ears.hear([.init(label: "beep", confidence: 0.5)], at: 1)
        #expect(ears.events().count == 1)
    }

    /// A wire reading feeds the device's ears the same way a staged one does,
    /// with the phone's single-precision confidences widened.
    @Test func aWireReadingFeedsTheDevice() {
        let device = PhoneDevice()
        #expect(device.sounds.events().isEmpty)
        #expect(!device.sounds.isListening)
        device.sounds.hear([.init(label: "siren", confidence: 0.75)], at: 2, duration: 1)
        #expect(device.sounds.topClassification == SoundClassification(label: "siren", confidence: 0.75))
        #expect(device.sounds.events().first?.time == 3)
    }

    // MARK: Helpers

    private func roundTrip(_ message: PhoneMessage) -> PhoneMessage? {
        let data = PhoneWire.encode(message)
        guard let header = PhoneHeader.parse(data) else { return nil }
        let start = data.startIndex + PhoneWire.headerByteCount
        let payload = data.subdata(in: start ..< data.endIndex)
        return PhoneWire.decode(header: header, payload: payload)
    }
}
