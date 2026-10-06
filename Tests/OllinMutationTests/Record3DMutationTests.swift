import Compression
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import OllinMutation
import OllinTestSupport
@testable import OllinRecord3D

/// The Record3D USB stream frame (a 104-byte header, then a JPEG, an LZFSE
/// depth map, and a confidence map) under the mutation harness, the header
/// and the body decoded as the reader thread decodes them.
@Suite struct Record3DMutationTests {

    static let colorWidth = 8, colorHeight = 6

    static func seeds() -> [[UInt8]] {
        let depth: [Float] = (0..<48).map { 0.5 + Float($0) * 0.01 }
        var depthBytes: [UInt8] = []
        for value in depth { withUnsafeBytes(of: value.bitPattern.littleEndian) { depthBytes.append(contentsOf: $0) } }
        let confidence = [UInt8](repeating: 2, count: 48)
        let color = Record3DFrameBytes.jpeg(width: Self.colorWidth, height: Self.colorHeight)
        let depthBlob = Record3DFrameBytes.lzfse(depthBytes), confidenceBlob = Record3DFrameBytes.lzfse(confidence)
        let whole = Record3DFrameBytes.header(rgb: color.count, depth: depthBlob.count, conf: confidenceBlob.count, misc: 2)
            + color + depthBlob + confidenceBlob + [0x7B, 0x7D]
        let bare = Record3DFrameBytes.header(rgb: color.count, depth: depthBlob.count, conf: 0, misc: 0) + color + depthBlob
        return [whole, bare]
    }

    @Test func aStreamFrame() {
        let report = MutationRun.run("record3d-stream", seeds: Self.seeds(), count: 500) { bytes in
            let data = Data(bytes)
            guard let header = Record3DFrameHeader.parse(data) else { return false }
            let body = data.count > Record3DFrameHeader.byteCount ? data.dropFirst(Record3DFrameHeader.byteCount) : Data()
            guard let box = decodeRecord3DFrame(header: header, body: Data(body), sequence: 1) else { return false }
            _ = box.depthWidth * box.depthHeight
            _ = box.intrinsics
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }

    @Test func theCodecAlone() {
        let seeds = [Record3DFrameBytes.lzfse([UInt8](repeating: 9, count: 200)), Record3DFrameBytes.lzfse(Array(0..<255)),
                     Record3DFrameBytes.jpeg(width: Self.colorWidth, height: Self.colorHeight)]
        let report = MutationRun.run("record3d-codec", seeds: seeds, count: 400) { bytes in
            let data = Data(bytes)
            let inflated = Record3DCodec.lzfseDecompress(data)
            if let inflated { _ = Record3DCodec.floats(from: inflated) }
            _ = Record3DCodec.floats(from: data)
            return inflated != nil
        }
        #expect(report.cases > 0, "\(report)")
    }
}
