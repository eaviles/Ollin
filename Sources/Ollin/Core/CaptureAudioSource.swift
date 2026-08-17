import AVFAudio
import os

/// Something whose live sound can be recorded while it plays.
///
/// The offline exporters ask a source to make its sound again afterwards, all
/// at once. A live recording cannot do that: the sound happens in real time,
/// once, while the person plays. So a live source hands its output over as it
/// goes, buffer by buffer, and the recorder lines the buffers up on its own
/// clock.
///
/// The seam lives here rather than in the audio library because the core
/// cannot depend on a satellite, and the recorder is core. Sources are found
/// the same way the offline exporters find theirs: by looking at what the
/// sketch is holding.
package protocol CaptureAudioSource: AnyObject {
    /// Start handing this source's output to `sink`, one buffer at a time,
    /// from the source's own audio thread.
    @MainActor func beginAudioCapture(into sink: AudioCaptureSink)
    /// Stop handing buffers over. Safe to call when capture never began.
    @MainActor func endAudioCapture()
}

/// One recorded source's lane into the live mixer.
///
/// The audio thread writes buffers in; the recorder's writer queue mixes
/// frames out. The two sides never wait on each other for long: everything
/// lives behind one small lock, and the writes are bounded copies.
///
/// Time is the whole job here. Buffers arrive stamped with the host clock, and
/// the recorder mixes on that same clock, so each buffer is placed at the
/// sample position its stamp says. A device that drops buffers (switching
/// headphones, a stalled engine) leaves a hole, and the hole is filled with
/// silence rather than closed up: closing it up would slide everything after
/// it earlier and the sound would drift away from the picture.
package final class AudioCaptureSink: @unchecked Sendable {
    /// The recording's sample rate. Buffers that arrive at another rate are
    /// resampled on the way in, so every lane speaks the same clock.
    package let sampleRate: Double
    /// The recording's start, in host-clock seconds. Sample position zero.
    package let startHostSeconds: Double

    /// How much sound a lane holds: the mixer reads a fraction of a second
    /// behind the clock, so a couple of seconds is generous headroom.
    private let capacityFrames: Int64
    /// How far a buffer's stamp may disagree with the running counter before
    /// the counter is wrong. Under this, the counter wins (stamps jitter);
    /// over it, the stamp wins and the gap becomes silence.
    private let resyncFrames: Int64

    // Only ever touched with the lock held; the resampler inside is what
    // keeps the struct from saying so itself.
    private struct State: @unchecked Sendable {
        /// Interleaved stereo, indexed by absolute frame modulo capacity.
        var ring: [Float]
        /// The absolute frame one past the last one written.
        var writeHead: Int64 = 0
        /// Whether any buffer has arrived yet.
        var started = false
        /// Resampler for a source running at another rate, made when the
        /// first such buffer arrives and remade if the format changes.
        var converter: AVAudioConverter?
        var converterInputFormat: AVAudioFormat?
        var converted: AVAudioPCMBuffer?
        /// Reused interleave scratch, grown as needed, so the audio thread
        /// does not allocate per callback once warm.
        var scratch: [Float] = []
    }
    private let state: OSAllocatedUnfairLock<State>

    package init(sampleRate: Double, startHostSeconds: Double) {
        self.sampleRate = sampleRate
        self.startHostSeconds = startHostSeconds
        self.capacityFrames = Int64(sampleRate * 2)
        self.resyncFrames = Int64(sampleRate * 0.05)
        self.state = OSAllocatedUnfairLock(
            initialState: State(ring: [Float](repeating: 0, count: Int(sampleRate * 2) * 2)))
    }

    // MARK: The audio-thread side

    /// Takes one buffer from the source's tap. Called on the audio thread.
    package func take(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        let when = time.isHostTimeValid
            ? AVAudioTime.seconds(forHostTime: time.hostTime)
            : AVAudioTime.seconds(forHostTime: mach_absolute_time())
        if buffer.format.sampleRate == sampleRate {
            interleaveAndIngest(buffer, atHostSeconds: when)
        } else {
            resampleAndIngest(buffer, atHostSeconds: when)
        }
    }

    private func interleaveAndIngest(_ buffer: AVAudioPCMBuffer, atHostSeconds when: Double) {
        guard buffer.floatChannelData != nil else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let channels = Int(buffer.format.channelCount)
        let handoff = Handoff(buffer)
        state.withLock { [handoff] s in
            let buffer = handoff.value
            guard let data = buffer.floatChannelData else { return }
            if s.scratch.count < frames * 2 { s.scratch = [Float](repeating: 0, count: frames * 2) }
            if buffer.format.isInterleaved {
                // Interleaved data sits in the first channel pointer, stereo
                // pairs already in order; mono still needs doubling.
                let stream = data[0]
                if channels >= 2 {
                    for f in 0..<frames {
                        s.scratch[f * 2] = stream[f * channels]
                        s.scratch[f * 2 + 1] = stream[f * channels + 1]
                    }
                } else {
                    for f in 0..<frames {
                        s.scratch[f * 2] = stream[f]
                        s.scratch[f * 2 + 1] = stream[f]
                    }
                }
            } else if channels >= 2 {
                // The file is stereo, so a wider source contributes its first
                // pair: that is where a mix puts the mains.
                let left = data[0], right = data[1]
                for f in 0..<frames {
                    s.scratch[f * 2] = left[f]
                    s.scratch[f * 2 + 1] = right[f]
                }
            } else {
                let mono = data[0]
                for f in 0..<frames {
                    s.scratch[f * 2] = mono[f]
                    s.scratch[f * 2 + 1] = mono[f]
                }
            }
            place(frames: frames, atHostSeconds: when, in: &s)
        }
    }

    private func resampleAndIngest(_ buffer: AVAudioPCMBuffer, atHostSeconds when: Double) {
        let handoff = Handoff(buffer)
        state.withLock { [handoff] s in
            let buffer = handoff.value
            if s.converter == nil || s.converterInputFormat != buffer.format {
                guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                 sampleRate: sampleRate, channels: 2,
                                                 interleaved: true),
                      let converter = AVAudioConverter(from: buffer.format, to: target) else { return }
                s.converter = converter
                s.converterInputFormat = buffer.format
                s.converted = nil
            }
            guard let converter = s.converter else { return }
            let ratio = sampleRate / buffer.format.sampleRate
            let need = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 256
            if s.converted == nil || s.converted!.frameCapacity < need {
                s.converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: need)
            }
            guard let out = s.converted else { return }
            out.frameLength = 0
            var handedOver = false
            var conversionError: NSError?
            converter.convert(to: out, error: &conversionError) { _, status in
                if handedOver {
                    status.pointee = .noDataNow
                    return nil
                }
                handedOver = true
                status.pointee = .haveData
                return buffer
            }
            let frames = Int(out.frameLength)
            guard conversionError == nil, frames > 0, let data = out.floatChannelData else { return }
            if s.scratch.count < frames * 2 { s.scratch = [Float](repeating: 0, count: frames * 2) }
            let stream = data[0]
            for i in 0..<(frames * 2) { s.scratch[i] = stream[i] }
            place(frames: frames, atHostSeconds: when, in: &s)
        }
    }

    /// Test entry: hand interleaved stereo frames straight to the placement
    /// logic, at the recording's own rate, as if a tap had delivered them.
    package func ingest(_ stereo: [Float], frames: Int, atHostSeconds when: Double) {
        state.withLock { s in
            if s.scratch.count < frames * 2 { s.scratch = [Float](repeating: 0, count: frames * 2) }
            for i in 0..<(frames * 2) { s.scratch[i] = stereo[i] }
            place(frames: frames, atHostSeconds: when, in: &s)
        }
    }

    /// Places `frames` frames of `s.scratch` on the recording's timeline.
    /// Call with the lock held.
    private func place(frames: Int, atHostSeconds when: Double, in s: inout State) {
        let derived = Int64(((when - startHostSeconds) * sampleRate).rounded())
        var pos: Int64
        if !s.started {
            s.started = true
            pos = derived
        } else {
            // Stamps jitter by a buffer or so; the running counter is smooth.
            // The counter wins until it disagrees by more than jitter can
            // explain, and then the stamp wins: that is a real gap or a real
            // restart, and taking the stamp is what keeps sound and picture
            // together across it.
            pos = abs(derived - s.writeHead) > resyncFrames ? derived : s.writeHead
        }
        var source = 0
        var count = frames
        if pos < 0 {
            // Sound from before the recording started: drop the early part.
            let cut = Int(min(Int64(count), -pos))
            source += cut
            count -= cut
            pos = 0
        }
        guard count > 0 else { return }
        if pos > s.writeHead {
            // A hole. Fill it with silence so everything after it stays put.
            let from = max(s.writeHead, pos - capacityFrames)
            zero(&s.ring, from: from, to: pos)
        }
        write(&s.ring, s.scratch, sourceFrame: source, at: pos, frames: count)
        s.writeHead = max(s.writeHead, pos + Int64(count))
    }

    private func zero(_ ring: inout [Float], from: Int64, to: Int64) {
        var f = from
        while f < to {
            let index = Int(f % capacityFrames) * 2
            ring[index] = 0
            ring[index + 1] = 0
            f += 1
        }
    }

    private func write(_ ring: inout [Float], _ scratch: [Float],
                       sourceFrame: Int, at pos: Int64, frames: Int) {
        for f in 0..<frames {
            let index = Int((pos + Int64(f)) % capacityFrames) * 2
            let s = (sourceFrame + f) * 2
            ring[index] = scratch[s]
            ring[index + 1] = scratch[s + 1]
        }
    }

    // MARK: The mixer side

    /// Adds this lane's frames `from ..< from + frames` into `mix`, interleaved
    /// stereo. Frames the lane never received stay silent. Called on the
    /// recorder's writer queue.
    package func mix(into mix: inout [Float], from: Int64, frames: Int) {
        mix.withUnsafeMutableBufferPointer { out in
            let handoff = Handoff(out)
            state.withLock { [handoff] s in
                let out = handoff.value
                let floor = max(from, s.writeHead - capacityFrames, 0)
                let ceiling = min(from + Int64(frames), s.writeHead)
                guard ceiling > floor else { return }
                var f = floor
                while f < ceiling {
                    let lane = Int(f - from) * 2
                    let index = Int(f % capacityFrames) * 2
                    out[lane] += s.ring[index]
                    out[lane + 1] += s.ring[index + 1]
                    f += 1
                }
            }
        }
    }

    /// The absolute frame one past the last one this lane has received.
    /// For tests and for the recorder's final drain.
    package var framesReceived: Int64 { state.withLock { $0.writeHead } }
}

/// Carries a value the compiler cannot check across into the lock's closure.
/// Every use hands over something the audio thread already owns for the length
/// of the call (a tap's buffer, a pointer into the caller's own array), so the
/// annotation states that discipline rather than waiving anything real.
private struct Handoff<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
