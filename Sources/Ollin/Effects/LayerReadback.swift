import Foundation
import simd

/// What a sketch asked to read off a layer this frame. The renderer fills the
/// request inside the frame's own command buffer and hands the bytes back once
/// the GPU is done, so a read never waits on the GPU: what a call returns is
/// the frame before's answer to the same call.
struct LayerReadbackRequest {
    /// What is read: the layer's pixels, or the average tone of each cell of a
    /// grid over it (the glyph mosaic's reduction).
    enum Kind: Equatable {
        case pixels
        case cells(columns: Int, rows: Int)

        /// The call a web export names when it stops on this read.
        var callName: String {
            switch self {
            case .pixels: return "RenderTarget.snapshot() (a layer read back to the CPU)"
            case .cells: return "glyphMosaic of a layer (a layer read back to the CPU)"
            }
        }
    }

    let target: RenderTarget
    let kind: Kind
}

/// One answer, as it came back from the frame before: the pixels as an `Image`
/// for `.pixels`, the cell averages for `.cells`, each the premultiplied color
/// as the present pass stores it (tone-mapped, sRGB-encoded) with its coverage
/// beside it.
struct LayerReadbackResult {
    let kind: LayerReadbackRequest.Kind
    let pixelWidth: Int
    let pixelHeight: Int
    let image: Image?
    let cells: [SIMD4<Float>]?
}

extension Drawer {

    /// Ask for `kind` off `target` this frame and return what the same call got
    /// the frame before: the n-th request of a frame reads the n-th result of
    /// the last frame delivered, when it is of the same kind at the same pixel
    /// size, and `nil` otherwise (the first frame, a layer the frame did not
    /// fill, a request that moved). Requests are matched by position because a
    /// layer is a per-frame handle: the handle that asked last frame is gone.
    func requestLayerReadback(of target: RenderTarget,
                              _ kind: LayerReadbackRequest.Kind) -> LayerReadbackResult? {
        let index = layerReadbacks.count
        layerReadbacks.append(LayerReadbackRequest(target: target, kind: kind))
        guard index < layerReadbackResults.count, let result = layerReadbackResults[index],
              result.kind == kind,
              result.pixelWidth == target.pixelWidth, result.pixelHeight == target.pixelHeight
        else { return nil }
        return result
    }

    /// Whether the sketch asked to read any layer back this frame. A headless
    /// drive then renders every frame rather than only the one it keeps, since
    /// a read answers from the frame before.
    var readsLayersBack: Bool { !layerReadbacks.isEmpty }
}

public extension RenderTarget {

    /// The layer's pixels on the CPU, as drawn the frame before: an `Image` with
    /// CPU pixels, so everything that reads a picture (`SlitScan.append`, a
    /// dither, a stipple, `image[x, y]`) can read what the sketch draws.
    ///
    /// Calling it asks for this frame's pixels and returns the frame before's.
    /// The read is a copy of the layer into a shared buffer inside the frame's
    /// own command buffer, handed over once the GPU has finished that frame, so
    /// the render loop never waits for it. In the window the answer is one
    /// frame old, or older when the GPU is behind. In an export every frame is
    /// rendered and read in turn, so the answer is exactly the frame before.
    /// `nil` on the first frame, and for a layer nothing was drawn into.
    ///
    /// The pixels are the layer as it would be shown: tone-mapped, sRGB-encoded,
    /// with the layer's coverage as alpha. The n-th `snapshot()` call in a frame
    /// reads what the n-th call of the frame before asked for, at the same
    /// size; a sketch that snapshots several layers keeps them in one order.
    ///
    /// ```swift
    /// let scene = makeRenderTarget()
    /// withTarget(scene) { drawMovingShapes() }
    /// if let picture = scene.snapshot() {     // last frame's pixels
    ///     history.append(picture)              // a CPU slit scan of the sketch's own drawing
    /// }
    /// ```
    ///
    /// A web page export stops at a sketch that reads a layer back, and names
    /// the call.
    func snapshot() -> Image? {
        drawer?.requestLayerReadback(of: self, .pixels)?.image
    }
}
