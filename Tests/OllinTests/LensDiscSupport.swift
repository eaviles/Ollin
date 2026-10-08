import Foundation
import Metal
import Testing
@testable import Ollin

// What a thin lens makes of a flat disc, and a frame read back in linear light to
// hold a blur against it. Shared by the depth-of-field suites: the layer filter
// (`DefocusTests`), the canvas pass (`DepthOfFieldTests`), and the iris
// (`ApertureBokehTests`).

/// The share of a disc of radius `kernel`, centered `at` from the center of a disc of
/// radius `subject`, that lies on the subject: the brightness a thin lens gives a flat
/// disc at each radius once every point of it has spread into a disc of the kernel's
/// radius. Whole from one kernel inside the silhouette, half at the silhouette, and
/// gone one kernel outside; the overlap of two circles in between.
func lensDiscCover(subject a: Double, kernel b: Double, at d: Double) -> Double {
    if b <= 1e-9 { return d < a ? 1 : 0 }
    if d >= a + b { return 0 }
    if d <= abs(a - b) { return a >= b ? 1 : (a * a) / (b * b) }
    let a2 = a * a, b2 = b * b, d2 = d * d
    let alpha = acos((d2 + a2 - b2) / (2 * d * a))
    let beta = acos((d2 + b2 - a2) / (2 * d * b))
    let area = a2 * alpha + b2 * beta - 0.5 * sqrt((-d + a + b) * (d + a - b) * (d - a + b) * (d + a + b))
    return area / (.pi * b2)
}

/// A frame rendered headless and read back before the present pass quantizes it: one
/// luminance per pixel in linear light, row 0 at the top.
struct LinearLuminanceFrame {
    let width: Int
    let height: Int
    let lum: [Double]

    @MainActor
    init(of sketch: Sketch) throws {
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        renderer.capturesLinearFrame = true
        _ = try OllinApp.renderImage(of: sketch, frame: 0, fps: 60, renderer: renderer)
        let linear = try #require(renderer.lastLinearFrame)
        let n = linear.width * linear.height
        let halfs = linear.color.contents().bindMemory(to: Float16.self, capacity: n * 4)
        var lum = [Double](repeating: 0, count: n)
        for i in 0 ..< n {
            lum[i] = 0.2126 * Double(halfs[i * 4]) + 0.7152 * Double(halfs[i * 4 + 1]) + 0.0722 * Double(halfs[i * 4 + 2])
        }
        width = linear.width; height = linear.height; self.lum = lum
    }

    func at(_ x: Int, _ y: Int) -> Double { lum[y * width + x] }

    /// Every pixel's luminance added up: the light in the frame.
    var total: Double { lum.reduce(0, +) }

    /// The mean luminance at each whole-pixel radius from `center` (in canvas
    /// coordinates, where a pixel's center lies at a half) over every angle, out to
    /// `maxRadius`.
    func radialProfile(center: (x: Double, y: Double), maxRadius: Int) -> [Double] {
        var sum = [Double](repeating: 0, count: maxRadius + 1)
        var count = [Int](repeating: 0, count: maxRadius + 1)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let r = Int(hypot(Double(x) + 0.5 - center.x, Double(y) + 0.5 - center.y).rounded())
                if r <= maxRadius { sum[r] += at(x, y); count[r] += 1 }
            }
        }
        return (0 ... maxRadius).map { count[$0] > 0 ? sum[$0] / Double(count[$0]) : 0 }
    }
}
