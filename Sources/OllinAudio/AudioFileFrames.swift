import AVFoundation
import Foundation

/// Every frame an audio file holds, read the one way every loader here reads a
/// file: a stretch at a time until the file runs out.
///
/// A file's header says how long it is, and the reader it hands the bytes to
/// believes it. Reading into one buffer of that length sets aside whatever the
/// header claims before a frame is decoded, so a sixty-byte file that says it
/// holds a billion frames asks for gigabytes, and a length past what a frame
/// count holds traps at the narrowing. Reading in stretches costs what the file
/// really holds. The sample rate is checked the same way, since every consumer
/// divides by it or multiplies a duration by it.
struct AudioFileFrames {
    /// One array of samples per channel, all the same length.
    var channels: [[Float]]
    /// The file's own rate, checked to be one audio is played at.
    var sampleRate: Double
    /// The format the frames were decoded in (deinterleaved 32-bit floats).
    var format: AVAudioFormat

    /// How many samples a stretch reads, over all the channels: 65,536
    /// frames of up to sixteen channels, and fewer frames past that, so the
    /// buffer a stretch reads into stays at four megabytes whatever the file
    /// declares.
    static let stretchSamples = 65_536 * 16

    /// The most channels a file may declare, which is also the most the
    /// system's reader converts. A WAV keeps its channel count in sixteen bits
    /// and a CAF in thirty-two, so a few changed bytes can claim tens of
    /// thousands; the system's buffer for that many is gigabytes a stretch,
    /// and on macOS 26 making it throws a C++ exception, which ends the
    /// process rather than answering `nil`.
    static let maxChannels: AVAudioChannelCount = 1024

    /// Whether frames in `format` are read at all: a rate a sound is played at
    /// and a channel count a recording carries. Checked before a buffer is
    /// made for them.
    static func reads(_ format: AVAudioFormat) -> Bool {
        format.sampleRate.isFinite && rates.contains(format.sampleRate)
            && (1...maxChannels).contains(format.channelCount)
    }

    /// How many frames a stretch reads for a file of `channels` channels.
    static func stretch(channels: AVAudioChannelCount) -> AVAudioFrameCount {
        AVAudioFrameCount(max(1, stretchSamples / max(1, Int(channels))))
    }

    /// The rates a file may declare: a hertz up to eight times the highest
    /// rate a studio records at. A rate outside it (or not a number at all,
    /// which a floating-point header field can spell) is not a sound.
    static let rates: ClosedRange<Double> = 1...1_536_000

    /// The frames of the file at `url`, at most `limit` of them. Throws what
    /// opening the file throws; `nil` when the file holds no frames, declares
    /// a rate no sound is played at, or declares more than `maxChannels`.
    static func read(_ url: URL, limit: Int? = nil) throws -> AudioFileFrames? {
        guard declaresPlausiblePackets(url) else { return nil }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = stretch(channels: format.channelCount)
        guard reads(format),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        var channels = [[Float]](repeating: [], count: Int(format.channelCount))
        var total = 0
        let most = limit ?? Int.max
        while total < most {
            let want = AVAudioFrameCount(min(Int(frames), most - total))
            do { try file.read(into: buffer, frameCount: want) } catch { break }
            let got = Int(buffer.frameLength)
            guard got > 0, let data = buffer.floatChannelData else { break }
            for channel in channels.indices {
                channels[channel].append(contentsOf: UnsafeBufferPointer(start: data[channel], count: got))
            }
            total += got
        }
        guard total > 0 else { return nil }
        return AudioFileFrames(channels: channels, sampleRate: format.sampleRate, format: format)
    }

    /// Whether a Core Audio file's own description of a packet is one a
    /// recording could have. The system reader sets aside a buffer as large as
    /// the largest packet the file declares when it opens it, and a CAF
    /// declares that size, with its channel count, in 32-bit fields: a
    /// sixty-byte file can claim four gigabytes a packet. A WAV or an AIFF
    /// keeps the same numbers in 16 bits, which cannot ask for much, so only a
    /// CAF is read here (its `desc` chunk leads the file, big-endian).
    static func declaresPlausiblePackets(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 52), head.count == 52,
              head.starts(with: Data("caff".utf8)), head[8..<12].elementsEqual("desc".utf8) else { return true }
        func field(_ offset: Int) -> UInt32 {
            head[offset..<offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        }
        let bytesPerPacket = field(36), framesPerPacket = field(40), channels = field(44)
        return bytesPerPacket <= 1 << 20 && framesPerPacket <= 1 << 20 && channels <= maxChannels
    }

    /// How many frames were read.
    var frameCount: Int { channels.first?.count ?? 0 }

    /// The channels averaged into one.
    var mono: [Float] {
        guard let first = channels.first else { return [] }
        guard channels.count > 1 else { return first }
        var out = [Float](repeating: 0, count: first.count)
        let share = Float(1) / Float(channels.count)
        for channel in channels {
            for index in out.indices { out[index] += channel[index] * share }
        }
        return out
    }

    /// The frames as one buffer in the decoded format, for a player that
    /// schedules a buffer rather than reading samples.
    func buffer() -> AVAudioPCMBuffer? {
        guard let length = AVAudioFrameCount(exactly: frameCount),
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: length),
              let data = out.floatChannelData else { return nil }
        out.frameLength = length
        for (index, channel) in channels.enumerated() {
            channel.withUnsafeBufferPointer { samples in
                if let base = samples.baseAddress { data[index].update(from: base, count: samples.count) }
            }
        }
        return out
    }
}
