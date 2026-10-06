import AVFoundation
import Foundation
import Testing
import os
import Ollin
@testable import OllinAudio

/// The relay that carries a source's buffers to the listening tier, read
/// once per buffer on the audio thread.
@Suite struct AudioTapRelayTests {

    /// The tap is as deep in the stack on the three-hundredth buffer as on
    /// the first: the relay's lock holds the closure in a struct, so a read
    /// never re-wraps it (the video tap's measured defect, pinned here on the
    /// hub's own relay).
    @Test func theTapStaysOneCallDeepAcrossBuffers() throws {
        let relay = AudioTapRelay()
        let depths = OSAllocatedUnfairLock(initialState: [Int]())
        relay.tap = { _, _ in
            let depth = Thread.callStackSymbols.count
            depths.withLock { $0.append(depth) }
        }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        buffer.frameLength = 64
        for _ in 0 ..< 300 { relay.deliver(buffer) }

        let seen = depths.withLock { $0 }
        #expect(seen.count == 300)
        #expect(seen.first == seen.last, "the tap sat \(seen.first ?? 0) deep on the first buffer and \(seen.last ?? 0) on the last")
    }
}
