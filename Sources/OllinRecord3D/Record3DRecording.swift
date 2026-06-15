import Foundation
import Ollin

/// A recorded RGBD clip captured by the **Record3D** iOS app (an ARKit
/// color-plus-depth recorder), opened on the Mac and turned into 3D point
/// clouds. The device-free first step of the iPhone-as-a-sensor-array work:
/// record a clip on the phone, AirDrop the `.r3d` over, and orbit your room as a
/// cloud — no networking, no live tether.
///
/// ```swift
/// let scan = try Record3DRecording(path: "/path/to/scan.r3d")
/// override func draw() {
///     let i = frameCount % scan.frameCount
///     let cloud = try! scan.pointCloud(at: i)
///     camera(.orbiting(radius: 2.5, azimuth: time * 0.4))
///     drawPointCloud(cloud)
/// }
/// ```
///
/// A `.r3d` is a ZIP holding a `metadata` JSON (camera intrinsics, resolution,
/// frame rate) and a per-frame set of files: a JPEG color image, an
/// LZFSE-compressed float32 depth map in meters, and an LZFSE-compressed
/// confidence map. Everything decodes with Apple-native frameworks — no third
/// party. The format is read here clean-room from its public structure; the
/// `record3d` library that documents it is LGPL-2.1 and credited, never copied.
///
/// Frames decode lazily and the most recent one is cached, so re-reading the
/// same index (orbiting a held frame) costs nothing.
public final class Record3DRecording {

    /// The archive entry names for one frame.
    private struct FrameFiles {
        let jpg: String
        let depth: String
        let conf: String?
    }

    private let archive: ZIPArchive
    private let frames: [FrameFiles]
    private let captureIntrinsics: CameraIntrinsics

    /// The clip's frame rate, frames per second (`0` if the recording didn't state one).
    public let fps: Double

    private var cachedIndex: Int?
    private var cachedFrame: RGBDFrame?

    /// The number of RGBD frames in the recording.
    public var frameCount: Int { frames.count }

    /// The camera intrinsics at the recording's stated capture resolution. Each
    /// frame's `intrinsics` are these rescaled to that frame's depth-map grid.
    public var intrinsics: CameraIntrinsics { captureIntrinsics }

    /// Open a recording from raw `.r3d` bytes (already in memory).
    public init(data: Data) throws {
        archive = try ZIPArchive(data: data)

        // Catalogue per-frame files by their integer stem (e.g. `rgbd/12.jpg`).
        var byStem: [Int: (jpg: String?, depth: String?, conf: String?)] = [:]
        for name in archive.entryNames {
            let base = (name as NSString).lastPathComponent
            let stem = (base as NSString).deletingPathExtension
            guard let n = Int(stem) else { continue }
            var entry = byStem[n] ?? (nil, nil, nil)
            switch (base as NSString).pathExtension.lowercased() {
            case "jpg", "jpeg": entry.jpg = name
            case "depth": entry.depth = name
            case "conf": entry.conf = name
            default: break
            }
            byStem[n] = entry
        }
        frames = byStem.keys.sorted().compactMap { n in
            guard let e = byStem[n], let jpg = e.jpg, let depth = e.depth else { return nil }
            return FrameFiles(jpg: jpg, depth: depth, conf: e.conf)
        }
        guard !frames.isEmpty else { throw Record3DError.missingEntry("rgbd frames") }

        guard let metadata = archive.data(named: "metadata") else {
            throw Record3DError.missingEntry("metadata")
        }
        (captureIntrinsics, fps) = try Self.parseMetadata(metadata)
    }

    /// Open the recording at a filesystem `path`. Throws if no file exists there.
    public convenience init(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw Record3DError.fileNotFound(path)
        }
        try self.init(url: URL(fileURLWithPath: path))
    }

    /// Open the recording at `url`.
    public convenience init(url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    /// Open a recording bundled as a resource. Pass the caller's bundle as
    /// `bundle` (a default would resolve to Ollin's own bundle, not yours).
    public convenience init(resource name: String, withExtension ext: String, in bundle: Bundle) throws {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw Record3DError.resourceNotFound("\(name).\(ext)")
        }
        try self.init(url: url)
    }

    /// Decode the RGBD frame at `index` (0-based, in capture order).
    public func frame(at index: Int) throws -> RGBDFrame {
        guard index >= 0, index < frames.count else {
            throw Record3DError.frameOutOfRange(index, count: frames.count)
        }
        if let cachedFrame, cachedIndex == index { return cachedFrame }

        let files = frames[index]
        guard let jpg = archive.data(named: files.jpg), let color = Image(data: jpg) else {
            throw Record3DError.decodeFailed("color frame \(index)")
        }
        guard let depthBlob = archive.data(named: files.depth),
              let depthData = Self.lzfseDecompress(depthBlob) else {
            throw Record3DError.decodeFailed("depth frame \(index)")
        }
        let depth = Self.floats(from: depthData)
        // The depth map's grid isn't in the metadata; derive it from the sample
        // count and the capture aspect (256×192 vs 192×256 both have 49,152 samples).
        let aspect = Double(captureIntrinsics.width) / Double(max(1, captureIntrinsics.height))
        let (dw, dh) = Self.depthDimensions(count: depth.count, aspect: aspect)

        var confidence: [UInt8]?
        if let confName = files.conf, let confBlob = archive.data(named: confName),
           let confData = Self.lzfseDecompress(confBlob), confData.count == depth.count {
            confidence = [UInt8](confData)
        }

        let frame = RGBDFrame(color: color, depth: depth, confidence: confidence,
                              depthWidth: dw, depthHeight: dh,
                              intrinsics: captureIntrinsics.scaled(toWidth: dw, height: dh))
        cachedIndex = index
        cachedFrame = frame
        return frame
    }

    /// Decode frame `index` and unproject it into a `PointCloud` (see
    /// `RGBDFrame.pointCloud(...)` for the parameters).
    public func pointCloud(at index: Int,
                           minimumConfidence: DepthConfidence = .high,
                           depthRange: ClosedRange<Double>? = nil,
                           step: Int = 1,
                           pointSize: Double = 0.012) throws -> PointCloud {
        try frame(at: index).pointCloud(minimumConfidence: minimumConfidence,
                                        depthRange: depthRange, step: step, pointSize: pointSize)
    }

    // MARK: - Metadata

    private static func parseMetadata(_ data: Data) throws -> (CameraIntrinsics, Double) {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            throw Record3DError.malformedMetadata("not a JSON object")
        }
        guard let k = (json["K"] as? [Any])?.compactMap({ ($0 as? NSNumber)?.doubleValue }),
              k.count >= 9 else {
            throw Record3DError.malformedMetadata("missing or short intrinsics 'K'")
        }
        let w = (json["w"] as? NSNumber)?.intValue ?? 0
        let h = (json["h"] as? NSNumber)?.intValue ?? 0
        guard w > 0, h > 0 else {
            throw Record3DError.malformedMetadata("missing capture resolution 'w'/'h'")
        }
        let fps = (json["fps"] as? NSNumber)?.doubleValue ?? 0
        // Record3D stores K column-major, the ARKit `intrinsics` layout:
        // [fx, 0, 0,  0, fy, 0,  cx, cy, 1].
        let intrinsics = CameraIntrinsics(fx: k[0], fy: k[4], cx: k[6], cy: k[7],
                                          width: w, height: h)
        return (intrinsics, fps)
    }

    /// Find the (width, height) factor pair of `count` whose ratio is closest to
    /// the capture `aspect` — how the depth grid is recovered without a header.
    static func depthDimensions(count: Int, aspect: Double) -> (Int, Int) {
        guard count > 0 else { return (0, 0) }
        let target = aspect > 0 ? aspect : 4.0 / 3.0
        var best = (w: count, h: 1)
        var bestError = Double.greatestFiniteMagnitude
        var d = 1
        while d * d <= count {
            if count % d == 0 {
                let e = count / d
                for (w, h) in [(e, d), (d, e)] {
                    let error = abs(Double(w) / Double(h) - target)
                    if error < bestError { bestError = error; best = (w, h) }
                }
            }
            d += 1
        }
        return best
    }

    // MARK: - Decompression

    /// Decompress an LZFSE blob (the depth and confidence buffers) into raw bytes.
    private static func lzfseDecompress(_ src: Data) -> Data? {
        Record3DCodec.lzfseDecompress(src)
    }

    /// Reinterpret little-endian float32 `data` as `[Float]`.
    private static func floats(from data: Data) -> [Float] {
        Record3DCodec.floats(from: data)
    }
}

/// Errors thrown while opening or decoding a Record3D recording.
public enum Record3DError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case resourceNotFound(String)
    case notAnArchive
    case missingEntry(String)
    case malformedMetadata(String)
    case decodeFailed(String)
    case frameOutOfRange(Int, count: Int)

    public var description: String {
        switch self {
        case .fileNotFound(let path): return "Record3D file not found: \(path)"
        case .resourceNotFound(let name): return "Record3D resource not found: \(name)"
        case .notAnArchive: return "Not a readable .r3d archive (no ZIP directory found)"
        case .missingEntry(let name): return "Record3D recording is missing its \(name)"
        case .malformedMetadata(let why): return "Record3D metadata is malformed: \(why)"
        case .decodeFailed(let what): return "Failed to decode \(what)"
        case .frameOutOfRange(let i, let count): return "Frame \(i) is out of range (0..<\(count))"
        }
    }
}
