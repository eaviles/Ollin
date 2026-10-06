import AudioToolbox
import Foundation
import Testing
import os
import Ollin
@testable import OllinVideo

/// The tap storage read once per audio block.
@Suite struct VideoAudioTapTests {

    /// The consumer is as deep in the stack on the three-hundredth block as
    /// on the first. A lock whose state was the closure itself reabstracted
    /// it on every read, two thunk frames a block, and the tap thread's stack
    /// (512 KB) was gone after about twenty minutes of play: the runner's
    /// crash on 2026-10-06, at 5,562 blocks.
    @Test func theConsumerStaysOneCallDeepAcrossBlocks() {
        let storage = VideoAudioTapStorage()
        var format = AudioStreamBasicDescription()
        format.mSampleRate = 44_100
        storage.prepare(maxFrames: 64, format: format)
        defer { storage.unprepare() }

        let depths = OSAllocatedUnfairLock(initialState: [Int]())
        storage.handler.withLock {
            $0.value = { _, _ in
                let depth = Thread.callStackSymbols.count
                depths.withLock { $0.append(depth) }
            }
        }

        var samples = [Float](repeating: 0.5, count: 64)
        samples.withUnsafeMutableBufferPointer { buffer in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 1,
                                      mDataByteSize: UInt32(buffer.count * MemoryLayout<Float>.size),
                                      mData: UnsafeMutableRawPointer(buffer.baseAddress)))
            for _ in 0 ..< 300 {
                storage.deliver(&list, frames: 64)
            }
        }

        let seen = depths.withLock { $0 }
        #expect(seen.count == 300)
        #expect(seen.first == seen.last, "the consumer sat \(seen.first ?? 0) deep on the first block and \(seen.last ?? 0) on the last")
    }
}
