import Ollin
import Vision
import Foundation
import os

/// A detected barcode — its decoded payload, its kind, and where it is. Common
/// kinds are QR codes (which usually carry text or a URL) and the retail
/// barcodes (EAN, UPC, Code 128).
public struct DetectedBarcode: Sendable {

    /// The decoded contents (the text or URL behind a QR code, the digits of a
    /// product barcode), or `nil` if it couldn't be decoded.
    public let payload: String?
    /// The barcode kind: `.qr`, `.ean13`, `.code128`, and the rest.
    public let symbology: Symbology
    /// Detection confidence, `0…1`.
    public let confidence: Double

    /// A kind of barcode. The named ones are the kinds a sketch usually asks
    /// about; a code the system learns to read later still arrives, under its
    /// own `rawValue`, so this stays open rather than closed like an enum.
    public struct Symbology: RawRepresentable, Hashable, Sendable,
                             CustomStringConvertible {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public var description: String { rawValue }

        /// A QR code, the square one that usually carries text or a URL.
        public static let qr = Symbology(rawValue: "qr")
        /// A Micro QR code, the small-payload version.
        public static let microQR = Symbology(rawValue: "microQR")
        /// Aztec, the square code with a bullseye in the middle.
        public static let aztec = Symbology(rawValue: "aztec")
        /// Data Matrix, the small square code on components and labels.
        public static let dataMatrix = Symbology(rawValue: "dataMatrix")
        /// PDF417, the wide code on boarding passes and driving licenses.
        public static let pdf417 = Symbology(rawValue: "pdf417")
        /// EAN-13, the retail barcode used outside North America.
        public static let ean13 = Symbology(rawValue: "ean13")
        /// EAN-8, the short retail barcode for small packages.
        public static let ean8 = Symbology(rawValue: "ean8")
        /// UPC-E, the compressed North American retail barcode.
        public static let upce = Symbology(rawValue: "upce")
        /// Code 39, the older alphanumeric industrial barcode.
        public static let code39 = Symbology(rawValue: "code39")
        /// Code 93, Code 39's denser successor.
        public static let code93 = Symbology(rawValue: "code93")
        /// Code 128, the dense barcode on parcels and shipping labels.
        public static let code128 = Symbology(rawValue: "code128")
        /// ITF-14, the carton code printed on shipping boxes.
        public static let itf14 = Symbology(rawValue: "itf14")
        /// Codabar, still used by libraries and blood banks.
        public static let codabar = Symbology(rawValue: "codabar")
        /// GS1 DataBar, the small retail code on fresh produce.
        public static let dataBar = Symbology(rawValue: "gs1DataBar")
    }

    // Normalized corners (lower-left origin), image order.
    let topLeftN: Vector2
    let topRightN: Vector2
    let bottomRightN: Vector2
    let bottomLeftN: Vector2

    /// The four corners mapped into `rect`, in perimeter order — ready to
    /// `drawPolygon` as a closed quad around the code.
    public func corners(in rect: Rectangle, mirrored: Bool = false) -> [Vector2] {
        [topLeftN, topRightN, bottomRightN, bottomLeftN]
            .map { VisionSpace.point($0, in: rect, mirrored: mirrored) }
    }

    /// The center of the code, mapped into `rect`.
    public func center(in rect: Rectangle, mirrored: Bool = false) -> Vector2 {
        corners(in: rect, mirrored: mirrored).centroid ?? .zero
    }
}

/// Reads barcodes and QR codes from a camera's frames (or a still image). A
/// classical detector, so it runs on any Mac. Point it at a QR code to pull a URL
/// or a bit of text out of the world and into a sketch — a simple way to hand a
/// running piece some input.
///
/// ```swift
/// let camera = Camera()
/// let codes = BarcodeScanner(camera)
/// override func draw() {
///     if let frame = camera.frame { drawImage(frame, in: bounds) }
///     for code in codes.barcodes {
///         drawPolygon(code.corners(in: bounds))
///         if let payload = code.payload { drawText(payload, code.center(in: bounds)) }
///     }
/// }
/// ```
public final class BarcodeScanner: VisionTracking, @unchecked Sendable {

    private let lock = OSAllocatedUnfairLock<[DetectedBarcode]>(initialState: [])
    private let status = VisionStatus("barcode scanning")

    /// The barcodes found in the most recent analyzed frame.
    public var barcodes: [DetectedBarcode] { lock.withLock { $0 } }
    /// How many barcodes are present right now.
    public var count: Int { lock.withLock { $0.count } }

    /// Whether barcode scanning can run here (it's classical, so effectively
    /// always `true`); `unavailableReason` would explain a `false`.
    public var isAvailable: Bool { status.isAvailable }
    /// Why barcode scanning can't run here, or `nil` when it can.
    public var unavailableReason: String? { status.reason }

    /// Scan barcodes in `source`'s frames — the live camera, or a playing video.
    @MainActor
    public init(_ source: any FrameSource) {
        SourceAnalyzers.analyzer(for: source).register(self)
    }

    /// Scan barcodes in a still image, once.
    public static func detect(in image: Image) async throws -> [DetectedBarcode] {
        let request = DetectBarcodesRequest()
        let observations = try await request.perform(on: image.currentCGImage())
        return observations.map(decode)
    }

    // MARK: VisionTracking

    func analyze(_ cgImage: CGImage, size: CGSize) async {
        guard status.isAvailable else { return }
        let request = DetectBarcodesRequest()
        do {
            let observations = try await request.perform(on: cgImage)
            status.recordSuccess()
            lock.withLock { $0 = observations.map(BarcodeScanner.decode) }
        } catch {
            status.recordFailure(error)
        }
    }

    // MARK: Decoding

    private static func decode(_ observation: BarcodeObservation) -> DetectedBarcode {
        func vec(_ p: NormalizedPoint) -> Vector2 { Vector2(Double(p.x), Double(p.y)) }
        return DetectedBarcode(
            payload: observation.payloadString,
            symbology: DetectedBarcode.Symbology(rawValue: symbologyName(observation.symbology)),
            confidence: Double(observation.confidence),
            topLeftN: vec(observation.topLeft),
            topRightN: vec(observation.topRight),
            bottomRightN: vec(observation.bottomRight),
            bottomLeftN: vec(observation.bottomLeft)
        )
    }

    /// The kind as Ollin names it. A kind with no name here keeps the one
    /// the system gives it, so a new code still reads.
    private static func symbologyName(_ symbology: BarcodeSymbology) -> String {
        String(describing: symbology)
    }
}
