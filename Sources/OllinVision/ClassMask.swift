import Accelerate
import CoreML
import Ollin
import Foundation
import os

/// A semantic-segmentation result: every pixel labeled with a class — *which*
/// pixels are the person, the dog, the chair — from a model whose output is a
/// class-index plane (one integer per pixel), the form DeepLabV3-style
/// segmenters produce.
///
/// Three readings of the same plane:
/// - **What's in frame**: `presentClassIndices` / `presentLabels` (largest first)
///   and `coverage(of:)`, the fraction of the picture a class fills.
/// - **What's under a point**: `classIndex(at:in:)` / `label(at:in:)` — the
///   class under any canvas point, the field-shaped query the other map
///   surfaces offer.
/// - **One class as pixels**: `mask(of:)` — a white-alpha `Image` of just that
///   class, like the segmentation matte: draw it into the frame's rectangle
///   and it lands on the picture, `tint(_:)` recolors it.
///
/// `labels` comes from the model itself when it declares a vocabulary (Apple's
/// gallery models do); with no declared labels the index-based reads still
/// work. Class indices above 255 aren't representable on this surface.
///
/// `@unchecked Sendable`: built whole on the analyzer thread and handed over;
/// the only mutation afterward is the per-class mask memo, which sits behind
/// its own lock.
public final class ClassMask: @unchecked Sendable {

    /// The plane's size in pixels — the model's own resolution, not the
    /// frame's (DeepLabV3 answers at 513×513 whatever it watched).
    public let width: Int
    public let height: Int

    /// The model's class vocabulary, indexed by class — `labels[15]` names
    /// class 15. Empty when the model declares none; the index-based reads
    /// don't need it.
    public let labels: [String]

    /// The classes present in this frame, largest pixel count first.
    public let presentClassIndices: [Int]

    /// The class index per pixel, top-down row-major (row 0 is the picture's
    /// top) — pinned by probe against footage with a known subject.
    let plane: [UInt8]

    /// Pixel count per class index (256 slots).
    private let counts: [Int]

    /// Per-class masks build once per frame result and memoize — a sketch
    /// drawing the same class every frame pays one conversion per analyzed
    /// frame, and repeated reads reuse the cached GPU texture.
    private let masks = OSAllocatedUnfairLock(uncheckedState: [Int: Image]())

    init(plane: [UInt8], width: Int, height: Int, counts: [Int], labels: [String]) {
        self.plane = plane
        self.width = width
        self.height = height
        self.counts = counts
        self.labels = labels
        self.presentClassIndices = counts.indices
            .filter { counts[$0] > 0 }
            .sorted { counts[$0] > counts[$1] }
    }

    /// Decode a model's multiarray output: a 2D plane of class indices, Int32
    /// (the DeepLabV3 form) or Float (some conversions store the argmax'd
    /// plane as float). Leading/trailing 1-sized dims are squeezed, so
    /// `[513, 513]` and `[1, 513, 513]` both decode; anything not 2D after
    /// squeezing (raw logits, embeddings) returns `nil`.
    convenience init?(featureValue: MLSendableFeatureValue, labels: [String]) {
        if let array = featureValue.shapedArrayValue(of: Int32.self) {
            self.init(shape: array.shape, labels: labels) { read in
                array.withUnsafeShapedBufferPointer { buffer, _, strides in
                    read(strides) { UInt8(clamping: buffer[$0]) }
                }
            }
        } else if let array = featureValue.shapedArrayValue(of: Float.self) {
            self.init(shape: array.shape, labels: labels) { read in
                array.withUnsafeShapedBufferPointer { buffer, _, strides in
                    read(strides) {
                        let value = buffer[$0]
                        guard value.isFinite else { return 0 }
                        return UInt8(min(max(value.rounded(), 0), 255))
                    }
                }
            }
        } else {
            return nil
        }
    }

    /// The shared shape walk behind both scalar types: find the two real dims,
    /// then fill the plane and histogram in one pass. `withBuffer` hands back
    /// the array's strides plus an element reader, scoped inside the shaped
    /// array's buffer access.
    private convenience init?(
        shape: [Int], labels: [String],
        withBuffer: (_ read: ([Int], (Int) -> UInt8) -> Void) -> Void
    ) {
        let dims = shape.indices.filter { shape[$0] != 1 }
        guard dims.count == 2 else { return nil }
        let (rowDim, colDim) = (dims[0], dims[1])
        let height = shape[rowDim], width = shape[colDim]
        var plane = [UInt8](repeating: 0, count: width * height)
        var counts = [Int](repeating: 0, count: 256)
        withBuffer { strides, element in
            plane.withUnsafeMutableBufferPointer { out in
                counts.withUnsafeMutableBufferPointer { tally in
                    for row in 0..<height {
                        let rowBase = row * strides[rowDim]
                        for col in 0..<width {
                            let value = element(rowBase + col * strides[colDim])
                            out[row * width + col] = value
                            tally[Int(value)] += 1
                        }
                    }
                }
            }
        }
        self.init(plane: plane, width: width, height: height,
                  counts: counts, labels: labels)
    }

    /// The classes present in this frame by name, largest first — skips
    /// classes the model didn't name.
    public var presentLabels: [String] {
        presentClassIndices.compactMap { labels.indices.contains($0) ? labels[$0] : nil }
    }

    /// The fraction of the picture a class fills, `0…1`.
    public func coverage(ofClass index: Int) -> Double {
        guard counts.indices.contains(index) else { return 0 }
        return Double(counts[index]) / Double(width * height)
    }

    /// The fraction of the picture a named class fills, `0…1` — `0` for a
    /// name the model doesn't declare.
    public func coverage(of label: String) -> Double {
        guard let index = index(of: label) else { return 0 }
        return coverage(ofClass: index)
    }

    /// The class index under `point` (a canvas point inside `rect`, the
    /// rectangle you drew the frame into). Out-of-range points clamp to the
    /// edge. Set `mirrored` when the frame is drawn flipped left-to-right.
    public func classIndex(at point: Vector2, in rect: Rectangle,
                           mirrored: Bool = false) -> Int {
        classIndexNormalized(at: VisionSpace.normalizedPoint(point, in: rect,
                                                             mirrored: mirrored))
    }

    /// The class index at a normalized point (`0…1`, lower-left origin) — the
    /// raw surface. Most sketches want `classIndex(at:in:)`.
    public func classIndexNormalized(at point: Vector2) -> Int {
        guard width > 0, height > 0 else { return 0 }
        let col = min(max(Int(point.x * Double(width)), 0), width - 1)
        let row = min(max(Int((1 - point.y) * Double(height)), 0), height - 1)
        return Int(plane[row * width + col])
    }

    /// The class name under `point`, or `nil` when the model didn't name that
    /// class.
    public func label(at point: Vector2, in rect: Rectangle,
                      mirrored: Bool = false) -> String? {
        let index = classIndex(at: point, in: rect, mirrored: mirrored)
        return labels.indices.contains(index) ? labels[index] : nil
    }

    /// One class as a drawable mask: white where the picture is that class,
    /// transparent elsewhere — `tint(_:)` recolors it, drawing it into the
    /// frame's rectangle lands it on the picture. `nil` when the class isn't
    /// in this frame.
    public func mask(ofClass index: Int) -> Image? {
        guard counts.indices.contains(index), counts[index] > 0 else { return nil }
        if let cached = masks.withLockUnchecked({ $0[index] }) { return cached }
        // One vectorized table pass: class index → 255 where it matches.
        var table = [UInt8](repeating: 0, count: 256)
        table[index] = 255
        var alpha = [UInt8](repeating: 0, count: plane.count)
        plane.withUnsafeBufferPointer { src in
            alpha.withUnsafeMutableBufferPointer { dest in
                var source = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: src.baseAddress),
                    height: vImagePixelCount(height), width: vImagePixelCount(width),
                    rowBytes: width)
                var destination = vImage_Buffer(
                    data: dest.baseAddress,
                    height: vImagePixelCount(height), width: vImagePixelCount(width),
                    rowBytes: width)
                vImageTableLookUp_Planar8(&source, &destination, table,
                                          vImage_Flags(kvImageNoFlags))
            }
        }
        guard let image = SegmentationImages.matteImage(fromGray: alpha,
                                                        width: width, height: height) else {
            return nil
        }
        masks.withLockUnchecked { $0[index] = image }
        return image
    }

    /// One named class as a drawable mask — `nil` for a name the model
    /// doesn't declare, or a class not in this frame.
    public func mask(of label: String) -> Image? {
        guard let index = index(of: label) else { return nil }
        return mask(ofClass: index)
    }

    /// The class index for a name, matched case-insensitively against the
    /// model's vocabulary.
    func index(of label: String) -> Int? {
        let wanted = label.lowercased()
        return labels.firstIndex { $0.lowercased() == wanted }
    }
}
