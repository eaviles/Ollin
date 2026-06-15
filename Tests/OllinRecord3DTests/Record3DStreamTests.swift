import Testing
import Foundation
import Compression
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Ollin
@testable import OllinRecord3D
#if canImport(Darwin)
import Darwin
#endif

/// Exercises the live USB stream's frame format — the 104-byte header parser and
/// the body decoder — against frames synthesized in memory (GPU-free, CI-safe),
/// plus a live-device test that soft-skips when no phone is streaming.
@Suite struct Record3DStreamTests {

    // Color frame 16×12, depth grid 8×6 — the same geometry as the file tests, so
    // the intrinsics halve when scaled from capture (16×12) onto the depth grid.
    let colorW = 16, colorH = 12
    let depthW = 8, depthH = 6

    // MARK: Header parsing

    @Test func parsesFrameHeader() {
        let header = makeHeader(rgb: 25_283, depth: 210_211, conf: 0, misc: 100,
                                fx: 431.07, fy: 431.07, cx: 239.44, cy: 320.01,
                                quat: (0, 0, 0, 1), trans: (0.1, -0.2, 0.3))
        let parsed = Record3DFrameHeader.parse(header)
        #expect(parsed != nil)
        #expect(parsed?.rgbSize == 25_283)
        #expect(parsed?.depthSize == 210_211)
        #expect(parsed?.confidenceSize == 0)
        #expect(parsed?.miscSize == 100)
        #expect(abs((parsed?.fx ?? 0) - 431.07) < 1e-2)
        #expect(abs((parsed?.cy ?? 0) - 320.01) < 1e-2)
        #expect(parsed?.pose.rotation == SIMD4<Float>(0, 0, 0, 1))
        #expect(abs((parsed?.pose.position.x ?? 0) - 0.1) < 1e-5)
        #expect(abs((parsed?.pose.position.z ?? 0) - 0.3) < 1e-5)
    }

    @Test func rejectsBadHeader() {
        // Short buffer.
        #expect(Record3DFrameHeader.parse(Data(count: 50)) == nil)
        // Wrong magic (a desynchronized stream).
        var bad = makeHeader(rgb: 100, depth: 100, conf: 0, misc: 0,
                             fx: 1, fy: 1, cx: 1, cy: 1, quat: (0, 0, 0, 1), trans: (0, 0, 0))
        bad[0] = 0xFF
        #expect(Record3DFrameHeader.parse(bad) == nil)
        // Implausibly huge depth size.
        let huge = makeHeader(rgb: 0, depth: 1 << 30, conf: 0, misc: 0,
                              fx: 1, fy: 1, cx: 1, cy: 1, quat: (0, 0, 0, 1), trans: (0, 0, 0))
        #expect(Record3DFrameHeader.parse(huge) == nil)
    }

    // MARK: Body decode

    @Test func decodesStreamFrame() {
        let jpeg = makeJPEG()
        let depth = [Float](repeating: 1, count: depthW * depthH)
        let depthBlob = lzfseCompress(depth.withUnsafeBytes { Data($0) })
        let body = jpeg + depthBlob

        let header = Record3DFrameHeader.parse(
            makeHeader(rgb: jpeg.count, depth: depthBlob.count, conf: 0, misc: 0,
                       fx: Double(colorW), fy: Double(colorW), cx: Double(depthW), cy: Double(depthH),
                       quat: (0, 0, 0, 1), trans: (0, 0, 0)))!

        let box = decodeRecord3DFrame(header: header, body: body, sequence: 7)
        #expect(box != nil)
        guard let box else { return }
        #expect(box.sequence == 7)
        #expect(box.color.width == colorW)
        #expect(box.color.height == colorH)
        #expect(box.depthWidth == depthW)
        #expect(box.depthHeight == depthH)
        #expect(box.depth.count == depthW * depthH)
        #expect(box.depth.allSatisfy { $0 == 1 })
        // Intrinsics (fx=16, cx=8, cy=6 at 16×12) scaled onto the 8×6 grid halve.
        #expect(box.intrinsics.fx == 8)
        #expect(box.intrinsics.cx == 4)
        #expect(box.intrinsics.cy == 3)
    }

    // MARK: Live device (soft-skips without a streaming phone)

    @Test func streamsFromConnectedDevice() {
        let devices = (try? USBMux.listDevices()) ?? []
        guard !devices.isEmpty else { return }   // nothing attached — skip
        let fd: Int32
        do { fd = try USBMux.connect(toPort: Record3DDevice.streamPort) }
        catch { return }                          // attached but not streaming — skip
        defer { close(fd) }
        var timeout = timeval(tv_sec: 4, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let headerData = USBMux.readFully(fd, Record3DFrameHeader.byteCount)
        guard headerData.count == Record3DFrameHeader.byteCount,
              let header = Record3DFrameHeader.parse(headerData) else {
            Issue.record("Connected to the stream but the first header didn't parse")
            return
        }
        let total = header.rgbSize + header.depthSize + header.confidenceSize + header.miscSize
        let body = USBMux.readFully(fd, total)
        #expect(body.count == total)
        let box = decodeRecord3DFrame(header: header, body: body, sequence: 1)
        #expect(box != nil)
        if let box {
            #expect(box.depth.count == box.depthWidth * box.depthHeight)
            #expect(box.depth.contains { $0 > 0 })   // a real scene has positive depth
        }
    }

    // MARK: - Synthetic frame builders

    /// A 104-byte little-endian frame header with the observed field offsets.
    private func makeHeader(rgb: Int, depth: Int, conf: Int, misc: Int,
                            fx: Double, fy: Double, cx: Double, cy: Double,
                            quat: (Float, Float, Float, Float),
                            trans: (Float, Float, Float)) -> Data {
        var h = [UInt8](repeating: 0, count: 104)
        func u32(_ off: Int, _ v: UInt32) {
            h[off] = UInt8(v & 0xff); h[off+1] = UInt8((v >> 8) & 0xff)
            h[off+2] = UInt8((v >> 16) & 0xff); h[off+3] = UInt8((v >> 24) & 0xff)
        }
        func f32(_ off: Int, _ v: Float) { u32(off, v.bitPattern) }
        u32(0, 0x0100_0000)                       // magic
        u32(40, UInt32(rgb)); u32(44, UInt32(depth)); u32(48, UInt32(conf)); u32(52, UInt32(misc))
        f32(60, Float(fx)); f32(64, Float(fy)); f32(68, Float(cx)); f32(72, Float(cy))
        f32(76, quat.0); f32(80, quat.1); f32(84, quat.2); f32(88, quat.3)
        f32(92, trans.0); f32(96, trans.1); f32(100, trans.2)
        return Data(h)
    }

    private func makeJPEG() -> Data {
        let context = CGContext(data: nil, width: colorW, height: colorH, bitsPerComponent: 8,
                                bytesPerRow: colorW * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: colorW, height: colorH))
        let cgImage = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
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
}
