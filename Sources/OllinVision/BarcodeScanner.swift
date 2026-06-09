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
    /// The barcode kind (e.g. "QR", "EAN13"), as Vision names it.
    public let symbology: String
    /// Detection confidence, `0…1`.
    public let confidence: Double

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
        let c = corners(in: rect, mirrored: mirrored)
        return c.reduce(Vector2.zero, +) / Double(c.count)
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

    /// Scan barcodes in `camera`'s live feed.
    @MainActor
    public init(_ camera: Camera) {
        camera.register(self)
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
            symbology: symbologyName(observation.symbology),
            confidence: Double(observation.confidence),
            topLeftN: vec(observation.topLeft),
            topRightN: vec(observation.topRight),
            bottomRightN: vec(observation.bottomRight),
            bottomLeftN: vec(observation.bottomLeft)
        )
    }

    /// A short, readable name for a symbology (strips Vision's verbose prefix).
    private static func symbologyName(_ symbology: BarcodeSymbology) -> String {
        let raw = String(describing: symbology)
        if let dot = raw.lastIndex(of: ".") {
            return String(raw[raw.index(after: dot)...])
        }
        return raw
    }
}
