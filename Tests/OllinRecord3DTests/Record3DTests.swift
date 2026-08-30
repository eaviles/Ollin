import Testing
import Foundation
import Compression
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Ollin
@testable import OllinRecord3D

/// Exercises the `.r3d` decode end to end against a recording synthesized in
/// memory — a ZIP (stored entries) holding a `metadata` JSON, one JPEG color
/// frame, and LZFSE-compressed depth and confidence buffers. No committed binary
/// asset and no GPU, so it runs anywhere CI does.
@Suite struct Record3DTests {

    // Synthetic recording geometry: color frame 16×12, depth grid 8×6, so the
    // intrinsics halve when scaled from capture (16×12) onto the depth grid.
    let colorW = 16, colorH = 12
    let depthW = 8, depthH = 6

    // MARK: Opening + metadata

    @Test func opensAndParsesMetadata() throws {
        let recording = try Record3DRecording(data: makeRecording())
        #expect(recording.frameCount == 1)
        #expect(recording.frameRate == 30)
        // K is column-major [fx,0,0, 0,fy,0, cx,cy,1] at the capture resolution.
        #expect(recording.intrinsics.fx == 16)
        #expect(recording.intrinsics.fy == 16)
        #expect(recording.intrinsics.cx == 8)
        #expect(recording.intrinsics.cy == 6)
        #expect(recording.intrinsics.width == colorW)
        #expect(recording.intrinsics.height == colorH)
    }

    @Test func garbageIsNotAnArchive() {
        #expect(throws: (any Error).self) {
            _ = try Record3DRecording(data: Data([0x1, 0x2, 0x3, 0x4, 0x5]))
        }
    }

    @Test func frameOutOfRangeThrows() throws {
        let recording = try Record3DRecording(data: makeRecording())
        #expect(throws: (any Error).self) { _ = try recording.frame(at: 1) }
        #expect(throws: (any Error).self) { _ = try recording.frame(at: -1) }
    }

    // MARK: Frame decode

    @Test func decodesFrameDepthAndConfidence() throws {
        let recording = try Record3DRecording(data: makeRecording())
        let frame = try recording.frame(at: 0)
        #expect(frame.depthWidth == depthW)
        #expect(frame.depthHeight == depthH)
        #expect(frame.depth.count == depthW * depthH)
        #expect(frame.confidence?.count == depthW * depthH)
        #expect(frame.color.width == colorW)
        #expect(frame.color.height == colorH)
        // Depth round-trips through LZFSE (the buffer was filled with 1.0).
        #expect(frame.depth.allSatisfy { $0 == 1 })
        // Intrinsics are scaled onto the 8×6 depth grid (half of capture).
        #expect(frame.intrinsics.fx == 8)
        #expect(frame.intrinsics.cx == 4)
        #expect(frame.intrinsics.cy == 3)
    }

    // MARK: Unprojection

    @Test func unprojectsIntoPointCloud() throws {
        let recording = try Record3DRecording(data: makeRecording())
        let cloud = try recording.pointCloud(at: 0, minConfidence: .high)
        // All 48 samples are positive depth at full confidence, so none drop.
        #expect(cloud.count == depthW * depthH)

        // Points are added row-major, so index = row * depthW + col. With depth 1
        // and the scaled intrinsics (fx=fy=8, cx=4, cy=3), the principal-point
        // pixel (col 4, row 3) lands at the origin in x/y, one meter down −z.
        let center = cloud.points[3 * depthW + 4].position
        #expect(abs(center.x) < 1e-6)
        #expect(abs(center.y) < 1e-6)
        #expect(abs(center.z + 1) < 1e-6)

        // The top-left pixel: x = (0−4)/8 = −0.5, y = −(0−3)/8 = 0.375.
        let corner = cloud.points[0].position
        #expect(abs(corner.x + 0.5) < 1e-6)
        #expect(abs(corner.y - 0.375) < 1e-6)
        #expect(abs(corner.z + 1) < 1e-6)
    }

    @Test func confidenceFloorDropsLowSamples() throws {
        // Half the grid at low confidence, dropped by a `.high` floor.
        let recording = try Record3DRecording(data: makeRecording(highConfidenceRows: depthH / 2))
        let strict = try recording.pointCloud(at: 0, minConfidence: .high)
        let loose = try recording.pointCloud(at: 0, minConfidence: .low)
        #expect(strict.count == depthW * (depthH / 2))
        #expect(loose.count == depthW * depthH)
    }

    // MARK: Depth-grid derivation

    @Test func derivesDepthGridFromCountAndAspect() {
        // LiDAR (49,152 samples) and TrueDepth (307,200) in both orientations.
        #expect(Record3DRecording.depthDimensions(count: 49_152, aspect: 4.0 / 3.0) == (256, 192))
        #expect(Record3DRecording.depthDimensions(count: 49_152, aspect: 3.0 / 4.0) == (192, 256))
        #expect(Record3DRecording.depthDimensions(count: 307_200, aspect: 4.0 / 3.0) == (640, 480))
        #expect(Record3DRecording.depthDimensions(count: 48, aspect: 4.0 / 3.0) == (8, 6))
    }

    // MARK: - Synthetic `.r3d` builder

    /// A one-frame `.r3d` archive in memory. `highConfidenceRows` (default: all)
    /// sets how many top rows of the confidence map are `2` (high); the rest are
    /// `0` (low).
    private func makeRecording(highConfidenceRows: Int? = nil) -> Data {
        let metadata: [String: Any] = [
            "K": [16.0, 0, 0, 0, 16.0, 0, 8.0, 6.0, 1.0],   // column-major, capture res
            "w": colorW, "h": colorH, "fps": 30.0,
        ]
        let metaData = try! JSONSerialization.data(withJSONObject: metadata)

        let depth = [Float](repeating: 1, count: depthW * depthH)
        let depthData = depth.withUnsafeBytes { Data($0) }

        let highRows = highConfidenceRows ?? depthH
        var confidence = [UInt8](repeating: 0, count: depthW * depthH)
        for row in 0..<min(highRows, depthH) {
            for col in 0..<depthW { confidence[row * depthW + col] = 2 }
        }

        return makeZIP([
            ("metadata", metaData),
            ("rgbd/0.jpg", makeJPEG()),
            ("rgbd/0.depth", lzfseCompress(depthData)),
            ("rgbd/0.conf", lzfseCompress(Data(confidence))),
        ])
    }

    private func makeJPEG() -> Data {
        let context = CGContext(data: nil, width: colorW, height: colorH, bitsPerComponent: 8,
                                bytesPerRow: colorW * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: colorW, height: colorH))
        let cgImage = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private func lzfseCompress(_ data: Data) -> Data {
        let capacity = data.count * 2 + 4096
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_LZFSE)
            }
        }
        out.removeSubrange(written..<out.count)
        return out
    }

    /// A ZIP archive with every entry stored uncompressed (method 0).
    private func makeZIP(_ entries: [(name: String, data: Data)]) -> Data {
        var out = [UInt8]()
        var central = [UInt8]()
        for (name, data) in entries {
            let nameBytes = Array(name.utf8)
            let crc = crc32(data)
            let bytes = [UInt8](data)
            let offset = UInt32(out.count)
            out += le32(0x0403_4b50)
            out += le16(20) + le16(0) + le16(0) + le16(0) + le16(0)   // version, flags, method, time, date
            out += le32(crc) + le32(UInt32(bytes.count)) + le32(UInt32(bytes.count))
            out += le16(UInt16(nameBytes.count)) + le16(0)            // name length, extra length
            out += nameBytes + bytes

            central += le32(0x0201_4b50)
            central += le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0)  // madeby, needed, flags, method, time, date
            central += le32(crc) + le32(UInt32(bytes.count)) + le32(UInt32(bytes.count))
            central += le16(UInt16(nameBytes.count)) + le16(0) + le16(0)            // name, extra, comment lengths
            central += le16(0) + le16(0) + le32(0)                    // disk start, internal/external attrs
            central += le32(offset) + nameBytes
        }
        let cdOffset = UInt32(out.count)
        out += central
        out += le32(0x0605_4b50) + le16(0) + le16(0)
        out += le16(UInt16(entries.count)) + le16(UInt16(entries.count))
        out += le32(UInt32(central.count)) + le32(cdOffset) + le16(0)
        return Data(out)
    }

    private func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    private func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
