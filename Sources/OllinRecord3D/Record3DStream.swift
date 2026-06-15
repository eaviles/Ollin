import Foundation
import CoreGraphics
import ImageIO
import Ollin

/// The camera's 6-DoF pose for a streamed frame, as ARKit reports it: a rotation
/// quaternion and a translation in meters, in ARKit's world space. The recorded
/// (`.r3d`) path doesn't expose pose; the live tether does, for the world-placement
/// and multi-frame fusion work to come. This slice builds clouds in camera space,
/// so the pose is published but not yet applied.
public struct Record3DPose: Equatable, Sendable {
    /// Rotation quaternion `(x, y, z, w)`.
    public var rotation: SIMD4<Float>
    /// Translation in meters, in ARKit world space.
    public var position: Vector3

    public init(rotation: SIMD4<Float>, position: Vector3) {
        self.rotation = rotation
        self.position = position
    }

    /// No rotation, at the origin — what a freshly-started stream reports.
    public static let identity = Record3DPose(rotation: SIMD4<Float>(0, 0, 0, 1), position: .zero)
}

/// The fixed-size header at the front of every Record3D USB stream frame, read
/// clean-room from the wire (104 bytes, little-endian). The frame is this header
/// followed by, in order: a JPEG color image, an LZFSE float32 depth map (meters),
/// an optional LZFSE confidence map, and a small JSON metadata blob.
///
/// Field offsets, observed from a live device:
/// `0` magic (`0x01000000`), `12` body length (= frame size − 16), `40` rgb bytes,
/// `44` depth bytes, `48` confidence bytes, `52` misc bytes, `60…72` intrinsics
/// (fx, fy, cx, cy at the color resolution), `76…100` pose (quaternion + translation).
struct Record3DFrameHeader {
    static let byteCount = 104
    static let magic: UInt32 = 0x0100_0000

    var rgbSize: Int
    var depthSize: Int
    var confidenceSize: Int
    var miscSize: Int
    var fx: Double, fy: Double, cx: Double, cy: Double
    var pose: Record3DPose

    /// Parse a 104-byte header. Returns `nil` if the buffer is short, the magic
    /// doesn't match (a desynchronized stream), or the sizes are implausible — any
    /// of which tells the reader to drop the connection and resync.
    static func parse(_ data: Data) -> Record3DFrameHeader? {
        guard data.count >= byteCount else { return nil }
        let s = data.startIndex
        func u32(_ off: Int) -> UInt32 {
            UInt32(data[s + off]) | (UInt32(data[s + off + 1]) << 8)
                | (UInt32(data[s + off + 2]) << 16) | (UInt32(data[s + off + 3]) << 24)
        }
        func f32(_ off: Int) -> Float { Float(bitPattern: u32(off)) }

        guard u32(0) == magic else { return nil }

        let rgb = Int(u32(40)), depth = Int(u32(44)), conf = Int(u32(48)), misc = Int(u32(52))
        // Guard against a garbage header steering a huge read.
        let total = rgb + depth + conf + misc
        guard rgb >= 0, depth > 0, conf >= 0, misc >= 0, total < 256 * 1024 * 1024 else { return nil }

        let pose = Record3DPose(
            rotation: SIMD4<Float>(f32(76), f32(80), f32(84), f32(88)),
            position: Vector3(Double(f32(92)), Double(f32(96)), Double(f32(100))))

        return Record3DFrameHeader(rgbSize: rgb, depthSize: depth, confidenceSize: conf,
                                   miscSize: misc,
                                   fx: Double(f32(60)), fy: Double(f32(64)),
                                   cx: Double(f32(68)), cy: Double(f32(72)), pose: pose)
    }
}

/// One decoded live frame, boxed for the hand-off from the reader thread to the
/// main thread. Holds the color frame as a `CGImage` (not an `Image`, which isn't
/// `Sendable`); the main thread wraps it. The box is the promise that its contents
/// are only read after the lock hands them over, the way `Camera` boxes its frames.
struct Record3DFrameBox: @unchecked Sendable {
    let sequence: Int
    let color: CGImage
    let depth: [Float]
    let confidence: [UInt8]?
    let depthWidth: Int
    let depthHeight: Int
    let intrinsics: CameraIntrinsics
    let pose: Record3DPose
}

/// Decode a raw frame body (the bytes after the 104-byte header) into a boxed
/// frame, reusing the same depth-grid derivation and intrinsics scaling the
/// recorded-file path uses. Returns `nil` if the color or depth won't decode.
///
/// Free function (not a method) so the reader thread calls it without main-actor
/// isolation — the executor-assertion lesson the audio/camera code documents.
func decodeRecord3DFrame(header: Record3DFrameHeader, body: Data, sequence: Int) -> Record3DFrameBox? {
    let s = body.startIndex
    guard body.count >= header.rgbSize + header.depthSize + header.confidenceSize else { return nil }

    let jpeg = Data(body[s ..< s + header.rgbSize])
    guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
          let color = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

    let depthStart = s + header.rgbSize
    let depthBlob = Data(body[depthStart ..< depthStart + header.depthSize])
    guard let depthData = Record3DCodec.lzfseDecompress(depthBlob) else { return nil }
    let depth = Record3DCodec.floats(from: depthData)
    guard !depth.isEmpty else { return nil }

    // The depth grid isn't carried unambiguously in the header (the color and depth
    // dimensions can match); recover it from the sample count and the color aspect,
    // exactly as the recorded path does (256×192 vs 192×256 share a count, etc.).
    let aspect = Double(color.width) / Double(max(1, color.height))
    let (dw, dh) = Record3DRecording.depthDimensions(count: depth.count, aspect: aspect)

    var confidence: [UInt8]?
    if header.confidenceSize > 0 {
        let confStart = depthStart + header.depthSize
        let confBlob = Data(body[confStart ..< confStart + header.confidenceSize])
        if let conf = Record3DCodec.lzfseDecompress(confBlob), conf.count == depth.count {
            confidence = [UInt8](conf)
        }
    }

    // Intrinsics arrive at the color (capture) resolution; bring them onto the depth grid.
    let intrinsics = CameraIntrinsics(fx: header.fx, fy: header.fy, cx: header.cx, cy: header.cy,
                                      width: color.width, height: color.height)
        .scaled(toWidth: dw, height: dh)

    return Record3DFrameBox(sequence: sequence, color: color, depth: depth, confidence: confidence,
                            depthWidth: dw, depthHeight: dh, intrinsics: intrinsics, pose: header.pose)
}
