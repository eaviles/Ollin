import AVFoundation
import Foundation
import Ollin
import os

/// Something that wants a source's sound as it plays: the analyzer behind a
/// `Soundtrack`, a `SpeechListener`, a `SoundClassifier`.
///
/// `hear` runs on the source's audio thread, so a conformer keeps whatever it
/// publishes behind its own lock and is `Sendable`. The samples are valid only
/// for the duration of the call.
protocol AudioListening: AnyObject, Sendable {
    func hear(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double)
}

/// One shared hub per audio source, created the first time a listener attaches
/// to it. The core's `AudioTapSource` has a single tap slot, on the rule that a
/// consumer needing to fan out owns it; this is that owner. Everything in this
/// library reaches a source's sound through the hub, so a `Soundtrack`, a
/// `SpeechListener`, and a `SoundClassifier` over one microphone all hear it
/// and none of them silently unseats the others.
///
/// Lifetime mirrors the frame side: the hub is held strongly by the tap closure
/// installed on the source, so it lives as long as the source keeps the tap;
/// this table only remembers it weakly so the next listener finds it. When the
/// last listener goes, the hub releases the slot.
@MainActor
enum SourceTapHubs {

    private struct WeakRef {
        weak var hub: AudioTapHub?
    }
    private static var table: [ObjectIdentifier: WeakRef] = [:]

    /// The hub running over `source`, creating it (and claiming the source's
    /// tap) on first use.
    static func hub(for source: any AudioTapSource) -> AudioTapHub {
        table = table.filter { $0.value.hub != nil }
        let key = ObjectIdentifier(source)
        // The identity check matters: a hub outlives its source (a listener
        // holds it), and a later source can be allocated at the same address,
        // so the key alone could hand back a hub bound to something gone.
        if let existing = table[key]?.hub, existing.isBound(to: source) { return existing }
        let hub = AudioTapHub(source: source)
        table[key] = WeakRef(hub: hub)
        source.audioTap = makeHubTap(hub)
        return hub
    }
}

/// Formed in a free function, never inside a `@MainActor` context, so the tap
/// carries no actor isolation. The source calls it from its audio thread, and a
/// main-actor closure would trap there (the render-thread rule).
private func makeHubTap(_ hub: AudioTapHub) -> AudioTap {
    { samples, sampleRate in hub.deliver(samples, sampleRate: sampleRate) }
}

/// Fans one source's audio out to every listener attached to it.
///
/// `@unchecked Sendable`: the listener list lives under `lock`, and the
/// listeners it drives are themselves `Sendable`.
final class AudioTapHub: @unchecked Sendable {

    private struct Weak {
        weak var listener: (any AudioListening)?
    }
    private let lock = OSAllocatedUnfairLock(initialState: [Weak]())

    /// The source whose slot this hub holds. Weak: the hub is kept alive by the
    /// tap closure the source itself holds, so a strong link would be a cycle.
    private weak var source: (any AudioTapSource)?

    init(source: any AudioTapSource) {
        self.source = source
    }

    /// Whether this hub still belongs to `source`.
    @MainActor
    func isBound(to source: any AudioTapSource) -> Bool {
        self.source === source
    }

    /// Add a listener. Held weakly, so dropping it from the sketch unregisters
    /// it.
    func register(_ listener: any AudioListening) {
        lock.withLock { listeners in
            listeners.removeAll { $0.listener == nil || $0.listener === listener }
            listeners.append(Weak(listener: listener))
        }
    }

    /// Remove a listener, releasing the source's tap slot if it was the last
    /// one, so detaching the only consumer leaves the source as it was found.
    @MainActor
    func unregister(_ listener: any AudioListening) {
        let remaining = lock.withLock { listeners -> Int in
            listeners.removeAll { $0.listener == nil || $0.listener === listener }
            return listeners.count
        }
        if remaining == 0 { source?.audioTap = nil }
    }

    /// Hand a block of samples to every live listener. Called on the source's
    /// audio thread.
    func deliver(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) {
        let listeners: [any AudioListening] = lock.withLock { listeners in
            listeners.removeAll { $0.listener == nil }
            return listeners.compactMap { $0.listener }
        }
        for listener in listeners { listener.hear(samples, sampleRate: sampleRate) }
    }
}

/// One block of mono audio, copied out of the tap so it can be carried to a
/// listener's own queue. The buffer is filled once here and never written
/// again, so handing it across is safe even though the compiler cannot prove
/// it: the box is the promise, the way the frame side boxes a `CGImage`.
struct PCMBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init?(mono samples: UnsafePointer<Float>, count: Int, sampleRate: Double) {
        guard count > 0, sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(count)
        buffer.floatChannelData![0].update(from: samples, count: count)
        self.buffer = buffer
    }
}

/// The slot side of `AudioTapSource` for the sources this library owns.
///
/// The microphone, the file player, and the oscillator each feed an
/// `AudioAnalyzer` from a tap on their own engine. A relay rides along in that
/// same tap so those sources can *also* hand their samples on, which is what
/// lets a `SpeechListener` or a `SoundClassifier` bind to a microphone the way
/// it binds to a playing video.
///
/// `@unchecked Sendable`: the one stored value lives under the lock, and an
/// `AudioTap` is `@Sendable` by declaration. The down-mix scratch is touched
/// only from the tap callback, which the engine calls serially.
final class AudioTapRelay: @unchecked Sendable {
    private let stored = OSAllocatedUnfairLock<AudioTap?>(initialState: nil)
    private var scratch = UnsafeMutableBufferPointer<Float>.allocate(capacity: 0)

    deinit { scratch.deallocate() }

    var tap: AudioTap? {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }

    /// Forward a buffer, if anything is listening, as the mono the seam
    /// promises. Nothing is truncated: an analyzer keeps only its most recent
    /// windowful, but a listener transcribing words needs every sample.
    ///
    /// Called on the audio thread, where the scratch is grown at most once per
    /// buffer size rather than allocated per callback.
    func deliver(_ buffer: AVAudioPCMBuffer) {
        guard let tap = stored.withLock({ $0 }), let channels = buffer.floatChannelData else {
            return
        }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let rate = buffer.format.sampleRate
        let channelCount = Int(buffer.format.channelCount)

        if channelCount == 1 {
            tap(UnsafeBufferPointer(start: channels[0], count: frames), rate)
            return
        }
        if scratch.count < frames {
            scratch.deallocate()
            scratch = UnsafeMutableBufferPointer<Float>.allocate(capacity: frames)
        }
        let inv = Float(1) / Float(channelCount)
        for i in 0..<frames { scratch[i] = channels[0][i] * inv }
        for c in 1..<channelCount {
            let src = channels[c]
            for i in 0..<frames { scratch[i] += src[i] * inv }
        }
        tap(UnsafeBufferPointer(start: scratch.baseAddress!, count: frames), rate)
    }
}
