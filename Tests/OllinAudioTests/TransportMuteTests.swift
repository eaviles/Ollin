import Ollin
import Testing
@testable import OllinAudio

/// The take transport's hold on an instrument: while a scrub re-simulates
/// frames that should pass unheard, a request to start a note is dropped
/// before it can start the engine, and everything else still lands.
@Suite
@MainActor
struct TransportMuteTests {

    @Test func aMutedSynthDropsNewNotes() {
        let synth = Synth(.nylon)
        synth.transportMuted = true
        synth.play("A4")
        #expect(!synth.isRunning,
                "a note asked for under the transport's hold must be dropped before it starts the engine")
    }

    @Test func unmutingRestoresTheVoice() {
        let synth = Synth(.nylon)
        synth.transportMuted = true
        synth.play("A4")
        synth.transportMuted = false
        synth.play("A4")
        #expect(synth.isRunning,
                "after the transport lets go, a note plays the ordinary way")
    }
}
