import Testing
import Foundation
import Compression
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Ollin
import OllinTestSupport
import OllinUSBMux
@testable import OllinRecord3D
#if canImport(Darwin)
import Darwin
#endif

/// Exercises the live USB stream's frame format — the 104-byte header parser and
/// the body decoder — against frames synthesized in memory (GPU-free, CI-safe),
/// plus a live-device test that refuses itself when no phone is streaming.
@Suite(.timeLimit(.minutes(1))) struct Record3DStreamTests {

    // Color frame 16×12, depth grid 8×6 — the same geometry as the file tests, so
    // the intrinsics halve when scaled from capture (16×12) onto the depth grid.
    let colorW = 16, colorH = 12
    let depthW = 8, depthH = 6

    // MARK: Header parsing

    @Test func parsesFrameHeader() {
        let header = Data(Record3DFrameBytes.header(rgb: 25_283, depth: 210_211, conf: 0, misc: 100,
                                                     fx: 431.07, fy: 431.07, cx: 239.44, cy: 320.01,
                                                     quat: (0, 0, 0, 1), trans: (0.1, -0.2, 0.3)))
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
        var bad = Data(Record3DFrameBytes.header(rgb: 100, depth: 100, conf: 0, misc: 0,
                                                  fx: 1, fy: 1, cx: 1, cy: 1, quat: (0, 0, 0, 1), trans: (0, 0, 0)))
        bad[0] = 0xFF
        #expect(Record3DFrameHeader.parse(bad) == nil)
        // Implausibly huge depth size.
        let huge = Data(Record3DFrameBytes.header(rgb: 0, depth: 1 << 30, conf: 0, misc: 0,
                                                   fx: 1, fy: 1, cx: 1, cy: 1, quat: (0, 0, 0, 1), trans: (0, 0, 0)))
        #expect(Record3DFrameHeader.parse(huge) == nil)
    }

    // MARK: Body decode

    @Test func decodesStreamFrame() {
        let jpeg = Data(Record3DFrameBytes.jpeg(width: colorW, height: colorH))
        let depth = [Float](repeating: 1, count: depthW * depthH)
        let depthBlob = Data(Record3DFrameBytes.lzfse(depth.withUnsafeBytes { [UInt8]($0) }))
        let body = jpeg + depthBlob

        let header = Record3DFrameHeader.parse(
            Data(Record3DFrameBytes.header(rgb: jpeg.count, depth: depthBlob.count, conf: 0, misc: 0,
                                           fx: Double(colorW), fy: Double(colorW), cx: Double(depthW), cy: Double(depthH),
                                           quat: (0, 0, 0, 1), trans: (0, 0, 0))))!

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

    // MARK: Camera detection

    @Test func classifiesCameraFromDepthGrid() {
        // Rear LiDAR is 256×192 (49,152) in either orientation; front TrueDepth
        // is 640×480 (307,200).
        #expect(Record3DCamera.classify(depthWidth: 256, depthHeight: 192) == .lidar)
        #expect(Record3DCamera.classify(depthWidth: 192, depthHeight: 256) == .lidar)
        #expect(Record3DCamera.classify(depthWidth: 640, depthHeight: 480) == .trueDepth)
        #expect(Record3DCamera.classify(depthWidth: 480, depthHeight: 640) == .trueDepth)
        #expect(Record3DCamera.classify(depthWidth: 0, depthHeight: 0) == .unknown)
    }

    // MARK: Live device (refused without a streaming phone)

    /// Whether a phone is attached and the capture app is serving its stream:
    /// the connection the test makes, made once and closed.
    static var phoneIsStreaming: Bool {
        guard let devices = try? USBMux.listDevices(), !devices.isEmpty,
              let fd = try? USBMux.connect(toPort: Record3DDevice.streamPort) else { return false }
        close(fd)
        return true
    }

    @Test(.enabled(if: Record3DStreamTests.phoneIsStreaming, "no phone is streaming over USB here"))
    func streamsFromConnectedDevice() throws {
        let fd = try USBMux.connect(toPort: Record3DDevice.streamPort)
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

}
