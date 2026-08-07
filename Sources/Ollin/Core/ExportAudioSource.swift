import Foundation

/// Something that can hand the offline exporters a soundtrack.
///
/// The exporters drive a sketch on a fixed clock with no window and no
/// speakers, so anything that makes sound has to be able to make it again
/// afterwards, all at once, rather than as it goes. A source records what the
/// sketch asked for while the frames were being rendered, and is asked for the
/// result at the end.
///
/// The seam lives here rather than in the audio library because the core cannot
/// depend on a satellite, and the exporters are core. A sketch's sound sources
/// are found the same way its animated values are: by looking at what the
/// sketch is holding.
package protocol ExportAudioSource: AnyObject {
    /// Samples from wherever the last call stopped up to `seconds`, as
    /// interleaved stereo at `sampleRate`.
    ///
    /// Asked for as the frames are written rather than at the end, because a
    /// file being written a track at a time will not let one track run far
    /// ahead of another: the writer stops taking pictures until the sound
    /// catches up. So a source renders forward a little at a time, which it can
    /// do because everything asked for up to that moment has already been.
    func renderExportAudio(upTo seconds: Double, sampleRate: Double) -> [Float]
}

public extension Sketch {
    /// The sound sources this sketch is holding, for the offline exporters.
    ///
    /// Found by looking at the sketch's own stored properties, the same way
    /// eased and sprung values are found, so an instrument held in the usual
    /// place is picked up with nothing to declare.
    internal func exportAudioSources() -> [ExportAudioSource] {
        var found: [ExportAudioSource] = []
        var mirror: Mirror? = Mirror(reflecting: self)
        while let current = mirror {
            for child in current.children {
                if let source = child.value as? ExportAudioSource { found.append(source) }
            }
            mirror = current.superclassMirror
        }
        return found
    }

    /// The next stretch of this sketch's soundtrack, mixed, up to `seconds`.
    ///
    /// Each source renders forward from wherever it stopped, so calling this as
    /// the frames go by produces one continuous soundtrack.
    internal func renderSoundtrack(
        upTo seconds: Double, sampleRate: Double, sources: [ExportAudioSource]
    ) -> [Float] {
        var mixed = [Float]()
        for source in sources {
            let samples = source.renderExportAudio(upTo: seconds, sampleRate: sampleRate)
            if mixed.count < samples.count {
                mixed.append(contentsOf: [Float](repeating: 0, count: samples.count - mixed.count))
            }
            for index in samples.indices { mixed[index] += samples[index] }
        }
        // Several instruments at once must not clip where one would not. The
        // whole soundtrack cannot be measured first, because it is being
        // written as it is made, so anything over is bent rather than cut: the
        // curve meets the straight part at the same slope, so there is no
        // corner to hear where it takes over.
        for index in mixed.indices where abs(mixed[index]) > 0.7 {
            let sign: Float = mixed[index] < 0 ? -1 : 1
            let over = (abs(mixed[index]) - 0.7) / 0.3
            mixed[index] = sign * (0.7 + 0.3 * Float(tanh(Double(over))))
        }
        return mixed
    }
}
