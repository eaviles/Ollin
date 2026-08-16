import Foundation
import CoreGraphics
import ImageIO
import Ollin

/// One decoded person-segmentation frame from the phone (the rear camera in Segment
/// mode, the front camera in Selfie mode), boxed for
/// the hand-off from the reader thread to the main thread. The `matte` is already
/// rotated upright (it's small, so the rotation is eager on the reader thread); the
/// `color` is kept in the sensor orientation and rotated **lazily** by `orientation`
/// only when the cutout is read — so a sketch that draws only the matte never pays to
/// rotate the full-resolution color. Both rotate through the same `rotatedCGImage`,
/// by the same quarter-turn count, so they stay aligned. CGImages (not `Image`s,
/// which aren't `Sendable`); the main thread builds the drawable forms.
struct PhoneSegmentationBox: @unchecked Sendable {
    let sequence: Int
    let matte: CGImage          // upright
    let color: CGImage          // sensor orientation
    let orientation: Int        // quarter turns clockwise to bring `color` upright
}

/// Decode a `PhoneSegmentationSample` into a boxed frame: JPEG-decode the color,
/// wrap the matte plane as a gray `CGImage`, and rotate the matte upright by the
/// sample's `orientation` (the color is rotated later, on demand). Returns `nil` if
/// the color won't decode or the matte is empty/too short.
///
/// Free function (not a method) so the reader thread calls it without main-actor
/// isolation — the executor-assertion lesson the audio/camera code documents.
func decodePhoneSegmentation(_ sample: PhoneSegmentationSample, sequence: Int) -> PhoneSegmentationBox? {
    guard sample.matteWidth > 0, sample.matteHeight > 0,
          sample.matte.count >= sample.matteWidth * sample.matteHeight else { return nil }

    guard let source = CGImageSourceCreateWithData(sample.colorJPEG as CFData, nil),
          let color = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let matteRaw = SegmentationImages.grayCGImage(fromPlane: sample.matte,
                                                        width: sample.matteWidth,
                                                        height: sample.matteHeight) else { return nil }

    let turns = Int(sample.orientation)
    let matte = rotatedCGImage(matteRaw, quarterTurnsCW: turns) ?? matteRaw
    return PhoneSegmentationBox(sequence: sequence, matte: matte, color: color, orientation: turns)
}

/// Rotate a `CGImage` by `quarterTurnsCW` × 90° **clockwise** through a single
/// (hardware-accelerated) Core Graphics draw, returning a new upright image; a turn
/// count that's a multiple of 4 returns the input unchanged. Used for both the matte
/// and the color, so the same turn count keeps them aligned. The output is a
/// premultiplied RGBA image (a gray matte becomes `(g, g, g, 255)`, which the
/// downstream gray extraction reads back as `g`).
///
/// `package` so the GPU-free tests can pin the rotation direction directly.
package func rotatedCGImage(_ image: CGImage, quarterTurnsCW turns: Int) -> CGImage? {
    let n = ((turns % 4) + 4) % 4
    guard n != 0 else { return image }
    let w = image.width, h = image.height
    let swap = (n == 1 || n == 3)
    let dstWidth = swap ? h : w
    let dstHeight = swap ? w : h
    guard let context = CGContext(
        data: nil, width: dstWidth, height: dstHeight,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    // Rotate about the destination's center, then draw the source centered. The
    // context is y-up, so a clockwise visual turn is a negative rotation.
    context.translateBy(x: CGFloat(dstWidth) / 2, y: CGFloat(dstHeight) / 2)
    context.rotate(by: -CGFloat(n) * .pi / 2)
    context.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return context.makeImage()
}
