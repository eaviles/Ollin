import AVFoundation
import Accelerate
import Foundation
import MediaToolbox
import Ollin
import os

/// Everything the audio tap's C callbacks touch, owned *by the tap itself*:
/// `clientInfo` carries a retained reference in, and only the `finalize`
/// callback releases it. That ownership is the crux. A tap can't be stopped
/// synchronously, so its `process` callback may still run after the
/// `VideoPlayer` that installed it is gone; because the callbacks reach only
/// this storage (never the player), there is no object left to race. The
/// consumer closure crosses in through the lock; the scratch buffer and
/// format are touched only by the tap's own serialized prepare/process/
/// unprepare callbacks on the audio thread.
final class VideoAudioTapStorage: @unchecked Sendable {

    /// The current consumer, written from the main thread, read per process
    /// callback on the audio thread.
    let handler = OSAllocatedUnfairLock<AudioTap?>(initialState: nil)

    // Audio-thread-only state (the tap serializes prepare/process/unprepare).
    private var sampleRate: Double = 0
    private var mono: UnsafeMutableBufferPointer<Float>?

    func prepare(maxFrames: Int, format: AudioStreamBasicDescription) {
        sampleRate = format.mSampleRate
        unprepare()
        mono = .allocate(capacity: max(1, maxFrames))
    }

    func unprepare() {
        mono?.deallocate()
        mono = nil
    }

    /// Averages whatever channel layout the tap delivers (planar buffers or
    /// one interleaved buffer) down to mono and hands it to the consumer.
    func deliver(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard frames > 0, let mono, let baseAddress = mono.baseAddress,
              let handler = handler.withLock({ $0 }) else { return }
        let count = min(frames, mono.count)
        vDSP_vclr(baseAddress, 1, vDSP_Length(count))

        var channels = 0
        for buffer in UnsafeMutableAudioBufferListPointer(list) {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let interleaved = Int(buffer.mNumberChannels)
            if interleaved <= 1 {
                vDSP_vadd(baseAddress, 1, samples, 1, baseAddress, 1, vDSP_Length(count))
                channels += 1
            } else {
                for channel in 0..<interleaved {
                    vDSP_vadd(baseAddress, 1, samples + channel, vDSP_Stride(interleaved),
                              baseAddress, 1, vDSP_Length(count))
                }
                channels += interleaved
            }
        }
        guard channels > 0 else { return }
        var scale = Float(1) / Float(channels)
        vDSP_vsmul(baseAddress, 1, &scale, baseAddress, 1, vDSP_Length(count))
        handler(UnsafeBufferPointer(start: baseAddress, count: count), sampleRate)
    }

    deinit { unprepare() }
}

/// Builds the processing tap that feeds `storage`. Created with `PreEffects`
/// so the analysis hears the soundtrack itself: `volume` and `isMuted` shape
/// what comes out of the speakers, not what a visual reacts to.
///
/// The tap retains the storage at creation (the `passRetained` into
/// `clientInfo`) and its `finalize` callback releases it, so the storage
/// lives exactly as long as any callback could run. The tap itself is owned
/// by the audio mix it's handed to; when the player item and its mix go
/// away, the tap finalizes.
func makeVideoAudioTap(storage: VideoAudioTapStorage) -> MTAudioProcessingTap? {
    let retainedStorage = Unmanaged.passRetained(storage)
    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: UnsafeMutableRawPointer(retainedStorage.toOpaque()),
        init: { _, clientInfo, tapStorageOut in
            tapStorageOut.pointee = clientInfo
        },
        finalize: { tap in
            Unmanaged<VideoAudioTapStorage>
                .fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
        },
        prepare: { tap, maxFrames, format in
            let storage = Unmanaged<VideoAudioTapStorage>
                .fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
            storage.prepare(maxFrames: Int(maxFrames), format: format.pointee)
        },
        unprepare: { tap in
            let storage = Unmanaged<VideoAudioTapStorage>
                .fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
            storage.unprepare()
        },
        process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
            let status = MTAudioProcessingTapGetSourceAudio(
                tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
            guard status == noErr else { return }
            let storage = Unmanaged<VideoAudioTapStorage>
                .fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
            storage.deliver(bufferListInOut, frames: Int(numberFramesOut.pointee))
        })

    var tap: MTAudioProcessingTap?
    let status = MTAudioProcessingTapCreate(
        kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
    guard status == noErr, let tap else {
        retainedStorage.release()   // finalize will never run to release it
        return nil
    }
    return tap
}
