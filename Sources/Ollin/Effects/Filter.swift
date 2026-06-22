import Foundation

/// A texture → texture image operation applied to a `RenderTarget` (or to the
/// whole frame via `postProcess`). A filter reads one off-screen layer and
/// produces a new one, entirely on the GPU, so chaining filters never touches
/// the CPU.
///
/// Filters are plain value descriptors: the renderer reads the parameters and
/// runs the matching GPU work (a tuned Metal Performance Shaders kernel where one
/// fits, an Ollin fragment pass otherwise). Build them with the static factories
/// and hand them to `RenderTarget.filtered(_:)` or `postProcess(_:)`:
///
/// ```swift
/// let layer = renderTarget()
/// withTarget(layer) {
///     background(.black)
///     fill(.orange); drawCircle(width / 2, height / 2, 200)
/// }
/// let glow = layer.filtered(.bloom(threshold: 0.6, intensity: 1.4, radius: 24))
/// drawImage(glow.image, 0, 0)
/// ```
public struct Filter: Sendable {

    /// The concrete operations the renderer knows how to run. Internal: a sketch
    /// builds a `Filter` through the static factories below, never this directly.
    enum Kind: Sendable {
        /// Separable Gaussian blur of the given pixel radius (≈ the kernel sigma).
        case gaussianBlur(radius: Double)
        /// Bloom: keep the part of the image above `threshold` brightness, blur it by
        /// `radius`, and add it back at `intensity`, a self-contained glowing copy.
        case bloom(threshold: Double, intensity: Double, radius: Double)
    }

    let kind: Kind

    /// A Gaussian blur. `radius` is the blur extent in pixels (the kernel sigma);
    /// larger is softer. Backed by a hardware Gaussian kernel.
    public static func gaussianBlur(radius: Double) -> Filter {
        Filter(kind: .gaussianBlur(radius: max(0, radius)))
    }

    /// Bloom (glow). Pixels brighter than `threshold` bleed light into their
    /// surroundings: the bright parts are extracted, blurred by `radius`, and added
    /// back at `intensity`. The result is the original image *plus* its glow, ready
    /// to composite (often additively). Brightness is the max color channel (so a
    /// vivid full-brightness mark blooms whatever its hue); `threshold` runs 0…1
    /// over the linear-light frame, so values above 1 (HDR highlights) bloom hardest.
    public static func bloom(threshold: Double = 0.6,
                             intensity: Double = 1.0,
                             radius: Double = 16) -> Filter {
        Filter(kind: .bloom(threshold: max(0, threshold),
                            intensity: max(0, intensity),
                            radius: max(0, radius)))
    }
}
