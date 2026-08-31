import Foundation
import Testing
@testable import OllinLink

/// The pure musical-time math: tempo clamping and wire precision, timeline
/// round trips, the Euclidean phase, the phase-encoding invariants that make
/// reported beats and reported phase agree, and the continuity rule for
/// re-deriving the client timeline.
@Suite
struct LinkTimeTests {

    @Test func tempoClampsAndRoundTrips() {
        #expect(LinkTempo(bpm: 120).wire == 500_000)
        #expect(LinkTempo(bpm: 5_000).bpm == LinkTempo.maxBPM)
        #expect(LinkTempo(bpm: 1).bpm == LinkTempo.minBPM)
        let fast = LinkTempo(wire: LinkTempo(bpm: 999).wire)
        #expect(abs(fast.bpm - 999) < 0.01)
        // A wire tempo of zero or below re-clamps instead of dividing by zero.
        #expect(LinkTempo(wire: 0).bpm == LinkTempo.maxBPM)
    }

    @Test func timelineRoundTrips() {
        let timeline = LinkTimeline(
            tempo: LinkTempo(bpm: 128),
            anchorMicroBeats: 7_250_000,
            anchorMicros: 123_456_789
        )
        for microBeats: Int64 in [-5_000_000, 0, 1, 999_999, 123_456_789] {
            let time = timeline.micros(at: microBeats)
            #expect(abs(timeline.microBeats(at: time) - microBeats) <= 1)
        }
    }

    @Test func phaseHandlesNegatives() {
        let quantum: Int64 = 4_000_000
        #expect(linkPhase(9_000_000, quantum: quantum) == 1_000_000)
        #expect(linkPhase(-1_000_000, quantum: quantum) == 3_000_000)
        #expect(linkPhase(123, quantum: 0) == 0)
    }

    @Test func phaseEncodingInvariants() {
        let timeline = LinkTimeline(
            tempo: LinkTempo(bpm: 120),
            anchorMicroBeats: 3_141_592,
            anchorMicros: 1_000_000
        )
        let quantum: Int64 = 4_000_000
        for micros: Int64 in [-10_000_000, 0, 1_000_000, 5_432_100, 99_999_999] {
            let raw = timeline.microBeats(at: micros)
            let encoded = linkPhaseEncodedBeats(timeline, at: micros, quantum: quantum)
            // The encoded value stays within half a quantum of the raw beats.
            #expect(abs(encoded - raw) <= quantum / 2)
            // Its own residue mod the quantum is the true grid phase, which is
            // measured from the timeline's beat anchor.
            #expect(linkPhase(encoded, quantum: quantum) == linkPhase(raw - timeline.anchorMicroBeats, quantum: quantum))
        }
    }

    @Test func phaseDecodingInverts() {
        let timeline = LinkTimeline(
            tempo: LinkTempo(bpm: 100),
            anchorMicroBeats: 8_000_000,
            anchorMicros: 500_000
        )
        let quantum: Int64 = 4_000_000
        for micros: Int64 in [0, 600_000, 12_345_678, 100_000_000] {
            let encoded = linkPhaseEncodedBeats(timeline, at: micros, quantum: quantum)
            let time = linkTimeAtPhaseEncodedBeats(timeline, microBeats: encoded, quantum: quantum)
            let again = linkPhaseEncodedBeats(timeline, at: time, quantum: quantum)
            #expect(abs(again - encoded) <= 1)
        }
    }

    @Test func clientTimelineStaysContinuous() {
        let client = LinkTimeline(
            tempo: LinkTempo(bpm: 120),
            anchorMicroBeats: 0,
            anchorMicros: 1_000_000
        )
        let session = LinkTimeline(
            tempo: LinkTempo(bpm: 140),
            anchorMicroBeats: 9_000_000,
            anchorMicros: 2_000_000
        )
        let hostNow: Int64 = 10_000_000
        let updated = linkUpdatedClientTimeline(
            client: client,
            session: session,
            hostNowMicros: hostNow,
            ghostOffsetMicros: -1_000_000
        )
        // The beat magnitude at `hostNow` is preserved across the update.
        #expect(abs(updated.microBeats(at: hostNow) - client.microBeats(at: hostNow)) <= 1)
        #expect(updated.tempo == session.tempo)
        // The new anchor sits on the host time of session beat zero.
        let hostBeatZero = session.micros(at: 0) - -1_000_000
        #expect(updated.anchorMicros == hostBeatZero)
    }
}
