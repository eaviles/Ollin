import Ollin

/// One segmentation result: the soft `matte` and the `cutout` it makes of the
/// source image. Both are drawable `Image`s — draw them into the same rectangle
/// you drew the source into and they line up with the picture.
///
/// - `matte` is a white silhouette whose alpha is the per-pixel confidence
///   (`0…1`). Drawn as-is it's a white shape; `tint(_:)` recolors it, which is
///   how a silhouette, a drop shadow, or a colored glow comes from the same matte.
/// - `cutout` keeps the source's own pixels where the matte is on and is
///   transparent everywhere else — the person (or subject) lifted off the
///   background, ready to composite over anything.
///
/// `@unchecked Sendable`: `Image` is a class, but both images are freshly created
/// by the segmenter and handed over whole — nothing else holds or mutates them.
///
/// The shared pixel work that builds these — turning a grayscale matte into the
/// white-alpha matte and the source cutout — lives in the core as
/// `SegmentationImages`, so the iPhone capture stream produces the same forms.
public struct Segmentation: @unchecked Sendable {

    /// The soft matte: white, with alpha = per-pixel confidence. At the model's
    /// resolution, not the source's — drawing it into the source's rectangle
    /// rescales it back onto the picture.
    public let matte: Image

    /// The source's pixels where the matte is on, transparent elsewhere, at the
    /// source's own resolution.
    public let cutout: Image

    init(matte: Image, cutout: Image) {
        self.matte = matte
        self.cutout = cutout
    }
}
