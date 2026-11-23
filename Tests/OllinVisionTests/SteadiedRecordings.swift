import AVFoundation
import CoreGraphics
import Foundation
import Ollin
import OllinSamplePhotos
import Testing
@testable import OllinVision

/// What a detector found over a run of frames, written down once so the tests
/// that hold found things steady read the same detections on every machine:
/// a detector's answers differ between systems, and a test of steadiness needs
/// the shake it was tuned on.
///
/// Each recording is a still scene filmed by a noisy camera, staged: a sample
/// photo, redrawn each frame a fraction of a pixel off its place, its exposure
/// a little off, with sensor noise added. A detector reads every frame, and
/// what it finds is kept as normalized corners with a label and a confidence.
/// The boxes of such a recording shake and blink the way a live feed's do,
/// with the truth known: nothing in the picture moves.
struct SteadiedRecording: Codable {

    struct Found: Codable {
        var label: String
        var confidence: Double
        /// Normalized, lower-left origin: two opposite corners of a box, or a
        /// quad's four in image order.
        var points: [Double]

        // Short names in the file: a recording is thousands of these.
        enum CodingKeys: String, CodingKey {
            case label = "l", confidence = "c", points = "p"
        }
    }

    /// Analyses a second the recording stands for.
    var rate: Double
    /// The pixel size of the frames the detector read.
    var width: Int
    var height: Int
    var frames: [[Found]]

    /// The folder the recordings are kept in: `Recordings` beside this file,
    /// copied into the test bundle.
    static let folder = Bundle.module.resourceURL!.appendingPathComponent("Recordings")

    static func load(_ name: String) throws -> SteadiedRecording {
        let data = try Data(contentsOf: folder.appendingPathComponent("\(name).json"))
        return try JSONDecoder().decode(SteadiedRecording.self, from: data)
    }

    func write(_ name: String, to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]   // one line, so a diff of it is one line
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(self).write(to: folder.appendingPathComponent("\(name).json"))
    }
}

extension SteadiedRecording.Found {
    init(_ detection: Detection) {
        let box = detection.boundsN
        self.init(label: detection.label, confidence: detection.confidence.rounded(toPlaces: 3),
                  points: [box.x, box.y, box.x + box.width, box.y + box.height].map { $0.rounded(toPlaces: 4) })
    }

    init(_ rectangle: DetectedRectangle) {
        let corners = [rectangle.topLeftN, rectangle.topRightN, rectangle.bottomRightN, rectangle.bottomLeftN]
        self.init(label: "", confidence: rectangle.confidence.rounded(toPlaces: 3),
                  points: corners.flatMap { [$0.x, $0.y] }.map { $0.rounded(toPlaces: 4) })
    }

    /// The detection this was, for a test that feeds the recording back.
    var detection: Detection {
        Detection(label: label, confidence: confidence,
                  boundsN: Rectangle(x: points[0], y: points[1],
                                     width: points[2] - points[0], height: points[3] - points[1]))
    }

    var rectangle: DetectedRectangle {
        DetectedRectangle(confidence: confidence,
                          topLeftN: Vector2(points[0], points[1]), topRightN: Vector2(points[2], points[3]),
                          bottomRightN: Vector2(points[4], points[5]), bottomLeftN: Vector2(points[6], points[7]))
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = Foundation.pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}

/// A still photograph as a noisy camera would film it, one frame at a time,
/// the same frames for the same seed.
struct NoisyCamera {

    private let photo: CGImage
    let width: Int
    let height: Int
    /// The sensor noise's standard deviation, in 8-bit levels.
    let noise: Double
    /// How far a frame sits off its place, in pixels (standard deviation).
    let shake: Double
    /// How far a frame's exposure sits off, as a share (standard deviation).
    let flicker: Double
    private var random: SplitMix
    /// One field of noise, read from a different place each frame.
    private let field: [Int8]

    init(_ photo: CGImage, width: Int, noise: Double, shake: Double = 0.3, flicker: Double = 0.01, seed: UInt64) {
        self.photo = photo
        self.width = width
        self.height = Int((Double(width) * Double(photo.height) / Double(photo.width)).rounded())
        self.noise = noise
        self.shake = shake
        self.flicker = flicker
        var random = SplitMix(seed: seed)
        var field = [Int8](repeating: 0, count: self.width * self.height * 4 + 4096)
        for i in field.indices {
            field[i] = Int8(max(-127, min(127, (random.gaussian() * noise).rounded())))
        }
        self.field = field
        self.random = random
    }

    mutating func frame() -> CGImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let dx = random.gaussian() * shake, dy = random.gaussian() * shake
        let gain = 1 + random.gaussian() * flicker
        let start = Int(random.next() % 4096)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.noneSkipLast.rawValue
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow, space: space, bitmapInfo: info)!
            context.interpolationQuality = .high
            context.draw(photo, in: CGRect(x: dx, y: dy, width: Double(width), height: Double(height)))
        }
        for i in pixels.indices where i % 4 != 3 {
            let value = Double(pixels[i]) * gain + Double(field[start + i])
            pixels[i] = UInt8(max(0, min(255, value.rounded())))
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: space, bitmapInfo: CGBitmapInfo(rawValue: info),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

/// A small seeded generator, so a recording is the same wherever it is made.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0 ..< 1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    /// Standard normal, by the polar form of the Box-Muller transform.
    mutating func gaussian() -> Double {
        while true {
            let u = unit() * 2 - 1, v = unit() * 2 - 1
            let s = u * u + v * v
            if s > 0, s < 1 { return u * (-2 * Foundation.log(s) / s).squareRoot() }
        }
    }
}

/// Writes the recordings. It runs only when asked, since the detectors'
/// answers are the system's and a recording is written once and committed:
///
///     OLLIN_WRITE_STEADY_RECORDINGS=<folder> Scripts/test.sh SteadiedRecordingWriter
@Suite struct SteadiedRecordingWriter {

    static let destination = ProcessInfo.processInfo.environment["OLLIN_WRITE_STEADY_RECORDINGS"]

    static let modelURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Models/YOLOv3TinyFP16.mlmodel")

    @Test(.enabled(if: destination != nil)) @MainActor
    func writesTheRecordings() async throws {
        let folder = URL(fileURLWithPath: try #require(Self.destination))
        let frames = 300

        // A table of things under strong sensor noise, through the object
        // detector with nothing filtered out.
        let table = SamplePhoto.breakfast.load().currentCGImage()
        let detector = ModelTracker(modelAt: Self.modelURL)
        var camera = NoisyCamera(table, width: 960, noise: 8, seed: 20_261_123)
        var objects = SteadiedRecording(rate: 30, width: camera.width, height: camera.height, frames: [])
        for _ in 0..<frames {
            let found = try await detector.detect(in: Image(cgImage: camera.frame())).objects
            objects.frames.append(found.map(SteadiedRecording.Found.init))
        }
        try objects.write("objects-noisy", to: folder)

        // A desk with a notebook, a trackpad and a cup, through the rectangle
        // detector. The cup is the hard part: the detector reports a
        // different rectangle around it on every frame.
        let desk = SamplePhoto.desk.load().currentCGImage()
        camera = NoisyCamera(desk, width: 960, noise: 8, seed: 20_261_124)
        var rectangles = SteadiedRecording(rate: 30, width: camera.width, height: camera.height, frames: [])
        for _ in 0..<frames {
            let found = try await RectangleDetector.detect(in: Image(cgImage: camera.frame()), minConfidence: 0.1)
            rectangles.frames.append(found.map(SteadiedRecording.Found.init))
        }
        try rectangles.write("rectangles-noisy", to: folder)

        // Something that moves: the film's dancer through the object detector.
        let asset = AVURLAsset(url: SampleClip.dance.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 960, height: 960)
        var film = SteadiedRecording(rate: 30, width: 0, height: 0, frames: [])
        for index in 0..<frames {
            let time = CMTime(value: CMTimeValue(index), timescale: 30)
            let (cgImage, _) = try await generator.image(at: time)
            (film.width, film.height) = (cgImage.width, cgImage.height)
            let found = try await detector.detect(in: Image(cgImage: cgImage)).objects
            film.frames.append(found.map(SteadiedRecording.Found.init))
        }
        try film.write("objects-film", to: folder)
    }
}
