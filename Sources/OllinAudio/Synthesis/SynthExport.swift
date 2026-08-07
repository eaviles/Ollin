import AVFoundation
import Ollin

extension Synth: @MainActor FrameAdvancing, @MainActor ExportAudioSource {

    /// Moves the instrument's own clock forward, once per frame.
    ///
    /// Only used while a sketch is being exported, where there is no audio
    /// hardware to keep time and a frame is however long the export says it is.
    /// A note asked for during a frame is written down against this clock, so
    /// the note lands where the picture that asked for it does.
    public func advance(by dt: Double) {
        guard OllinApp.isRenderingHeadless else { return }
        exportClock += max(0, dt)
    }

    /// The next stretch of this instrument's soundtrack, up to `seconds`.
    ///
    /// The notes were written down as the frames went by; this plays them back
    /// through the same renderer that feeds the speakers and the same effects
    /// that were on the output, on a clock nothing is waiting for. Which is why
    /// the renderer takes events and gives back samples and knows nothing about
    /// an engine: an export is that same code with the waiting taken out.
    ///
    /// Rendered forward a little at a time rather than all at once, because a
    /// file being written a track at a time will not let the picture run far
    /// ahead of the sound.
    package func renderExportAudio(upTo seconds: Double, sampleRate: Double) -> [Float] {
        guard let offline = offlineRender(at: sampleRate) else { return [] }
        let target = Int((seconds * sampleRate).rounded())
        guard target > offline.rendered else { return [] }

        var samples = [Float]()
        samples.reserveCapacity((target - offline.rendered) * 2)

        while offline.rendered < target {
            // Rendered up to the next note rather than in fixed blocks, so a
            // note starts on the sample it was asked for rather than at the
            // next block boundary. An export has no deadline, so it can be
            // exact where the live path cannot.
            while let next = offline.pending.first,
                  Int(next.at * sampleRate) <= offline.rendered {
                var event = next.event
                // A note's length was measured in seconds when it was asked
                // for, because an export may render at a different rate from
                // the hardware it was played on.
                if event.durationSeconds > 0 {
                    event.durationSamples = max(1, Int(event.durationSeconds * sampleRate))
                }
                offline.events.push(event)
                offline.pending.removeFirst()
            }

            var wanted = target - offline.rendered
            if let next = offline.pending.first {
                wanted = min(wanted, max(1, Int(next.at * sampleRate) - offline.rendered))
            }
            let count = AVAudioFrameCount(min(wanted, Int(offline.block)))

            let status: AVAudioEngineManualRenderingStatus
            do {
                status = try offline.engine.renderOffline(count, to: offline.buffer)
            } catch {
                break
            }
            guard status == .success, offline.buffer.frameLength > 0,
                  let channels = offline.buffer.floatChannelData else { break }

            let produced = Int(offline.buffer.frameLength)
            let left = channels[0]
            let right = offline.buffer.format.channelCount > 1 ? channels[1] : channels[0]
            for index in 0..<produced {
                samples.append(left[index])
                samples.append(right[index])
            }
            offline.rendered += produced
        }
        return samples
    }

    /// The offline machine, built the first time it is asked for.
    private func offlineRender(at sampleRate: Double) -> OfflineRender? {
        if let offline, offline.sampleRate == sampleRate { return offline }
        offline?.shutDown()
        offline = OfflineRender(synth: self, sampleRate: sampleRate)
        return offline
    }

    /// Everything an export needs and the live path does not.
    ///
    /// Its own renderer, so an export is not disturbed by whatever the live one
    /// has been doing, and its own engine in the mode where nothing waits for
    /// real time. The effects have to run through an engine because that is
    /// what they are; the notes do not.
    @MainActor final class OfflineRender {
        let sampleRate: Double
        let block: AVAudioFrameCount = 1024
        let engine = AVAudioEngine()
        let events = EventRing(capacity: 4096)
        let buffer: AVAudioPCMBuffer
        var pending: [RecordedNote]
        var rendered = 0
        private var started = false

        init?(synth: Synth, sampleRate: Double) {
            self.sampleRate = sampleRate
            pending = synth.recorded.sorted { $0.at < $1.at }

            guard let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
                  let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
                  let made = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: block)
            else { return nil }
            buffer = made

            let renderer = SynthRenderer(
                voice: synth.startingVoice, polyphony: synth.polyphony,
                sampleRate: sampleRate, events: events
            )
            renderer.gain = synth.gain

            let source = makeSynthSourceNode(format: mono, renderer: renderer)
            let delayUnit = AVAudioUnitDelay()
            let reverbUnit = AVAudioUnitReverb()
            engine.attach(source)
            engine.attach(delayUnit)
            engine.attach(reverbUnit)
            engine.connect(source, to: delayUnit, format: nil)
            engine.connect(delayUnit, to: reverbUnit, format: nil)
            engine.connect(reverbUnit, to: engine.mainMixerNode, format: nil)
            Synth.configure(delayUnit, with: synth.delay)
            Synth.configure(reverbUnit, with: synth.reverb)

            do {
                try engine.enableManualRenderingMode(.offline, format: stereo,
                                                     maximumFrameCount: block)
                try engine.start()
                started = true
            } catch {
                audioNoteOnce("could not render the soundtrack for the export "
                              + "(\(error.localizedDescription)).")
                return nil
            }
        }

        func shutDown() {
            guard started else { return }
            started = false
            engine.stop()
            engine.disableManualRenderingMode()
        }

        nonisolated deinit {}
    }
}

extension Synth {
    /// A note asked for while a sketch was being exported, and when.
    struct RecordedNote {
        var at: Double
        var event: SynthEvent
    }

    /// Whether notes are being written down instead of played.
    var isRecordingForExport: Bool { OllinApp.isRenderingHeadless }

    /// Whether this instrument has been asked to play anything for an export.
    var hasExportAudio: Bool { !recorded.isEmpty }

    /// Writes a note down against the export clock.
    func record(_ event: SynthEvent) {
        // A sketch playing thousands of notes into an export should not grow
        // without bound; past this it is a stuck loop rather than music.
        guard recorded.count < 200_000 else { return }
        let note = RecordedNote(at: exportClock, event: event)
        recorded.append(note)

        // The soundtrack is rendered while the frames are still being drawn, so
        // anything asked for after the machine was built has to reach it too.
        // It arrives in order, because the clock only moves forward.
        offline?.pending.append(note)
    }
}
