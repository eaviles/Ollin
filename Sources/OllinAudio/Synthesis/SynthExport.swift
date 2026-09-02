import AVFoundation
import Ollin

extension Synth: @MainActor TransportMutable {}

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
            // A move takes effect at the next block rather than splitting one.
            // An onset is a transient and has to land on its own sample; where
            // a sound is coming from is not, and a block is a fifth of a frame,
            // so quantizing the move to it cannot be heard.
            while let next = offline.pendingPoses.first,
                  Int(next.at * sampleRate) <= offline.rendered {
                offline.apply(next)
                offline.pendingPoses.removeFirst()
            }

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
        /// Where the instrument was and where it was heard from, still to come.
        var pendingPoses: [RecordedPose]
        var rendered = 0
        private var started = false
        /// The listener, built only for an instrument the sketch actually
        /// placed. Nil leaves the chain exactly the shape it has always been.
        private let environment: AVAudioEnvironmentNode?
        private let source: AVAudioSourceNode

        init?(synth: Synth, sampleRate: Double) {
            self.sampleRate = sampleRate
            pending = synth.recorded.sorted { $0.at < $1.at }
            pendingPoses = synth.recordedPoses.sorted { $0.at < $1.at }

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
            // What the live renderer holds by reference travels here too, or
            // a sampled or wavetable note in the export renders as silence.
            renderer.instrument = synth.instrument
            renderer.wavetable = synth.wavetable

            // A placed instrument has to reach the listener as a single stream,
            // because turning one into two is the listener's whole job. An
            // unplaced one is built at the output's own channel count instead,
            // exactly as the live path builds it: the render block writes its
            // one stream into every channel, so the sound arrives in both ears.
            // Fed in as mono it reaches only the first of them.
            let placing = !pendingPoses.isEmpty
            source = makeSynthSourceNode(format: placing ? mono : stereo, renderer: renderer)
            engine.attach(source)
            // The same chain the output has, built the same way from the same
            // list. An export that ran a different set of effects from the one
            // the sketch was heard through would be a different piece.
            var chain: [AVAudioUnit] = []
            for effect in synth.effects {
                let unit = Effect.makeUnit(for: effect.kind)
                engine.attach(unit)
                effect.apply(to: unit)
                chain.append(unit)
            }

            // Whatever the chain hangs from: the listener where there is one.
            var head: AVAudioNode = source
            if !placing {
                environment = nil
            } else {
                // The same shape the live path is rewired into: one stream
                // reaches something that knows where the ears are and leaves it
                // as two, with the room applied after the placing.
                let listener = AVAudioEnvironmentNode()
                listener.distanceAttenuationParameters.distanceAttenuationModel = .inverse
                // `.auto` is what the live path asks for too. With no output
                // device to ask about, it resolves to a plain left and right
                // rather than the head model: a file cannot know what it will
                // be played back on.
                listener.renderingAlgorithm = .auto
                applyHearingRange(synth.placementRange, to: listener)
                source.renderingAlgorithm = .auto
                environment = listener
                engine.attach(listener)
                engine.connect(source, to: listener, format: mono)
                head = listener
            }
            // A connection touching a custom unit names the chain's format
            // outright, exactly as the live path does: left to work it out,
            // the engine resamples around the unit instead of running it at
            // the export's rate. Here that format is known, not queried: two
            // channels at the rate this whole machine renders at.
            func isCustom(_ node: AVAudioNode) -> Bool {
                (node as? AVAudioUnit)?.auAudioUnit is ClosureAudioUnit
            }
            for unit in chain {
                let named = isCustom(unit) || isCustom(head)
                engine.connect(head, to: unit, format: named ? stereo : nil)
                head = unit
            }
            engine.connect(head, to: engine.mainMixerNode,
                           format: isCustom(head) ? stereo : nil)

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

        /// Whether this machine was built with a listener in it, and so can
        /// carry a placing at all.
        var canPlace: Bool { environment != nil }

        /// Moves the sound and the listener to where the sketch had them.
        ///
        /// Both at once, because neither means anything alone: a position is
        /// only somewhere relative to whoever is listening.
        func apply(_ pose: RecordedPose) {
            guard let environment else { return }
            environment.listenerPosition = audioPoint(pose.listener.eye)
            environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
                forward: audioVector(pose.listener.forward),
                up: audioVector(pose.listener.up)
            )
            // No position means the instrument left the scene, which is the
            // same as sitting in the middle of the listener's head.
            source.position = audioPoint(pose.position ?? pose.listener.eye)
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
