// PhonePictureCoding: the step between a compressed picture and the wire, in both
// directions, shared by the Ollin capture app (Apps/OllinPhoneApp) and the Mac
// satellite (OllinPhone).
//
// LOAD-BEARING: like PhoneWire.swift this file is compiled *verbatim into both
// ends*, so the Mac's tests run the exact code the phone uses to rebuild a
// picture for its decoder. It imports CoreMedia and nothing of Ollin's.

import CoreMedia
import Foundation

extension PhonePicture {

    /// The length of the big-endian prefix in front of every NAL unit in `data`.
    /// The compressor writes four bytes, and the decoder is told the same number.
    static let nalLengthByteCount = 4

    /// Read one picture out of a compressor's output: the coded bytes, whether it
    /// stands alone, and on a keyframe the parameter sets its format carries.
    ///
    /// Returns `nil` for a buffer with no bytes (a frame the compressor dropped)
    /// or a format this wire cannot carry: not HEVC, or NAL units behind a length
    /// that is not four bytes.
    init?(sampleBuffer: CMSampleBuffer) {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC,
              let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0 else { return nil }
        var bytes = Data(count: length)
        let copied = bytes.withUnsafeMutableBytes { raw -> OSStatus in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                       destination: raw.baseAddress!)
        }
        guard copied == noErr else { return nil }

        let isKeyframe = Self.isSync(sampleBuffer)
        var sets: [Data] = []
        if isKeyframe {
            guard let read = Self.parameterSets(of: format) else { return nil }
            sets = read
        }
        let size = CMVideoFormatDescriptionGetDimensions(format)
        self.init(width: Int(size.width), height: Int(size.height), isKeyframe: isKeyframe,
                  parameterSets: sets, data: bytes)
    }

    /// Whether the compressor marked this buffer as standing alone. A buffer with
    /// no attachments at all is a sync sample, which is how the format says so.
    static func isSync(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
              let first = attachments.first else { return true }
        return !((first[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false)
    }

    /// The HEVC parameter sets a format carries, in order, or `nil` when it
    /// cannot say or frames its NAL units with some other length.
    static func parameterSets(of format: CMFormatDescription) -> [Data]? {
        var count = 0
        var headerLength: Int32 = 0
        guard CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                format, parameterSetIndex: 0, parameterSetPointerOut: nil,
                parameterSetSizeOut: nil, parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: &headerLength) == noErr,
              count > 0, Int(headerLength) == nalLengthByteCount else { return nil }
        var sets: [Data] = []
        for index in 0..<count {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            guard CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                    format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
                    parameterSetSizeOut: &size, parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil) == noErr,
                  let pointer else { return nil }
            sets.append(Data(bytes: pointer, count: size))
        }
        return sets
    }

    /// Build the buffer a decoder or a display layer takes.
    ///
    /// A keyframe brings its parameter sets, and `format` is rebuilt from them
    /// only when they differ from the ones it was built from, since they repeat
    /// on every keyframe while the size holds. A picture that is not a keyframe
    /// decodes against `format` as it stands, so before the first keyframe there
    /// is nothing to build and this returns `nil`: the phone waits for one.
    ///
    /// The buffer is marked to be shown the moment it is decoded, since a live
    /// picture has no timeline to wait on.
    func sampleBuffer(reusing format: inout PhonePictureFormat?) -> CMSampleBuffer? {
        if isKeyframe, format?.parameterSets != parameterSets {
            guard let rebuilt = PhonePictureFormat(parameterSets: parameterSets) else { return nil }
            format = rebuilt
        }
        guard let format, !data.isEmpty else { return nil }

        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
                blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                dataLength: data.count, flags: kCMBlockBufferAssureMemoryNowFlag,
                blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block else { return nil }
        let written = data.withUnsafeBytes { raw -> OSStatus in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: data.count)
        }
        guard written == kCMBlockBufferNoErr else { return nil }

        var sampleSize = data.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault, dataBuffer: block,
                formatDescription: format.description, sampleCount: 1,
                sampleTimingEntryCount: 0, sampleTimingArray: nil,
                sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
                sampleBufferOut: &sample) == noErr,
              let sample else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0),
                                      to: CFMutableDictionary.self)
            CFDictionarySetValue(first, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            if !isKeyframe {
                CFDictionarySetValue(first, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                     Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
        }
        return sample
    }
}

/// A decoder's format, and the parameter sets it was built from, so the next
/// keyframe can tell whether it needs a new one.
struct PhonePictureFormat {
    let parameterSets: [Data]
    let description: CMVideoFormatDescription

    init?(parameterSets: [Data]) {
        guard !parameterSets.isEmpty, parameterSets.allSatisfy({ !$0.isEmpty }) else { return nil }
        // Hold every set in one buffer so the pointers stay valid for the call.
        let joined = parameterSets.reduce(Data(), +)
        var made: CMVideoFormatDescription?
        let status = joined.withUnsafeBytes { raw -> OSStatus in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            var offset = 0
            var pointers: [UnsafePointer<UInt8>] = []
            for set in parameterSets {
                pointers.append(base + offset)
                offset += set.count
            }
            let sizes = parameterSets.map(\.count)
            return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault, parameterSetCount: parameterSets.count,
                parameterSetPointers: pointers, parameterSetSizes: sizes,
                nalUnitHeaderLength: Int32(PhonePicture.nalLengthByteCount),
                extensions: nil, formatDescriptionOut: &made)
        }
        guard status == noErr, let made else { return nil }
        self.parameterSets = parameterSets
        self.description = made
    }
}
