// Drawer, the image half: drawImage and the textured-quad batch emission,
// tint state application, and the image vertex layout.

import Foundation
import simd
import COllinShaders

extension Drawer {
    // MARK: Images

    /// Draw `image` into `rect` (sketch space), stretched to fit. The image rides
    /// the transform stack like everything else, so `translate`/`rotate`/`scale`
    /// move and warp it. Recorded as one textured quad with its own batch, so it
    /// composites in draw order with the shapes around it. A zero-area rect or a
    /// non-uploadable image draws nothing.
    func drawImage(_ image: Image, in rect: Rectangle) {
        guard rect.width > 0, rect.height > 0, image.width > 0, image.height > 0 else { return }
        if let recorder = svgRecorder {
            recorder.skippedImages += 1   // raster has no place in a vector file
            return
        }
        let x0 = Float(rect.x), y0 = Float(rect.y)
        let x1 = Float(rect.x + rect.width), y1 = Float(rect.y + rect.height)
        // The four corners with their UVs: (0,0) top-left … (1,1) bottom-right.
        // A CPU-decoded texture's origin is top-left and sketch space is y-down, so
        // uv.y and screen y run the same way — no flip. A vertically-flipped image
        // (a GL/Syphon-origin texture) swaps the top and bottom V so it lands upright.
        let (vTop, vBot): (Float, Float) = image.flipsVertically ? (1, 0) : (0, 1)
        let tint = tintColor?.simd4 ?? SIMD4<Float>(1, 1, 1, 1)   // nil tint = the image unchanged
        let tl = imageVertex(x0, y0, 0, vTop, tint)
        let tr = imageVertex(x1, y0, 1, vTop, tint)
        let br = imageVertex(x1, y1, 1, vBot, tint)
        let bl = imageVertex(x0, y1, 0, vBot, tint)
        beginImageBatch(image)
        // Symmetry replicas extend this same batch (one texture, many quads).
        replicated { imageVertices.append(contentsOf: [tl, tr, br, tl, br, bl]) }
    }

    /// Draw a depth scene into `rect`: `color` is the backdrop and `depth` is a
    /// gray depth map (white = nearest by default) sampled per pixel and written to
    /// the depth buffer. After it, 2D placed at a normalized `depth(_:)` is occluded
    /// by the scene — the way a sprite is hidden by a nearer subject. Allocates the
    /// depth buffer (like a camera) with no 3D camera needed; raster only.
    func drawDepthScene(color: Image, depth: Image, in rect: Rectangle, whiteIsNear: Bool) {
        guard rect.width > 0, rect.height > 0,
              color.width > 0, color.height > 0, depth.width > 0, depth.height > 0 else { return }
        if svgRecorder != nil { return }   // a depth scene has no vector form
        hasDepthScene = true
        currentTarget?.needsDepth = true   // depth scene in a target → that pass carries depth
        let x0 = Float(rect.x), y0 = Float(rect.y)
        let x1 = Float(rect.x + rect.width), y1 = Float(rect.y + rect.height)
        let (vTop, vBot): (Float, Float) = color.flipsVertically ? (1, 0) : (0, 1)
        // The whiteIsNear flag rides in tint.r (the fragment reads it; the backdrop
        // color is drawn untinted), so no new per-batch field is needed.
        let flag = SIMD4<Float>(whiteIsNear ? 1 : 0, 0, 0, 0)
        let tl = imageVertex(x0, y0, 0, vTop, flag)
        let tr = imageVertex(x1, y0, 1, vTop, flag)
        let br = imageVertex(x1, y1, 1, vBot, flag)
        let bl = imageVertex(x0, y1, 0, vBot, flag)
        beginDepthSceneBatch(color: color, depth: depth, metricDepth: nil)
        imageVertices.append(contentsOf: [tl, tr, br, tl, br, bl])
    }

    /// Draw a *metric* depth scene from an `RGBDFrame`: `frame.color` is the backdrop
    /// and `frame.depth` (meters) is written into the depth buffer as true clip-space
    /// depth against the active camera's near/far — so 3D geometry placed at real
    /// world coordinates (`drawPointCloud`, `depth(at:)`) occludes and is occluded by
    /// the feed in one metric space. Needs an active camera (`Camera3D.fromIntrinsics`
    /// is the matching one); a no-op without one, or for SVG (no vector form). The
    /// backdrop is **letterboxed** into `rect` by the feed's aspect (no stretch),
    /// matching the metric camera's own letterbox so backdrop and placed geometry
    /// align. Raster only.
    func drawDepthScene(metricFrame frame: RGBDFrame, in rect: Rectangle) {
        guard rect.width > 0, rect.height > 0,
              frame.color.width > 0, frame.color.height > 0,
              frame.depthWidth > 0, frame.depthHeight > 0,
              frame.depth.count >= frame.depthWidth * frame.depthHeight else { return }
        guard let camera = camera3D else { return }   // metric depth needs near/far
        if svgRecorder != nil { return }
        hasDepthScene = true
        currentTarget?.needsDepth = true   // depth scene in a target → that pass carries depth
        // Map metric depth d → Metal NDC z ∈ [0,1] as ndc_z = P − Q/d, where
        // P = far/(far−near), Q = far·near/(far−near) (the perspective depth curve).
        // These ride in the quad's vertex tint so the fragment needs no extra buffer.
        let denom = camera.far - camera.near
        let p = denom != 0 ? camera.far / denom : 0
        let q = denom != 0 ? camera.far * camera.near / denom : 0
        // Letterbox the feed into `rect` by the intrinsics' aspect — the same fit the
        // metric camera applies in clip space, so the backdrop and the projected 3D
        // geometry land on the same pixels.
        let k = frame.intrinsics
        let fit = Rectangle(fitting: Vector2(Double(k.width), Double(k.height)), in: rect)
        let x0 = Float(fit.x), y0 = Float(fit.y)
        let x1 = Float(fit.x + fit.width), y1 = Float(fit.y + fit.height)
        let (vTop, vBot): (Float, Float) = frame.color.flipsVertically ? (1, 0) : (0, 1)
        // tint.a = 1 selects the metric branch (the normalized path leaves it 0);
        // tint.r/.g carry P/Q.
        let flag = SIMD4<Float>(Float(p), Float(q), 0, 1)
        let tl = imageVertex(x0, y0, 0, vTop, flag)
        let tr = imageVertex(x1, y0, 1, vTop, flag)
        let br = imageVertex(x1, y1, 1, vBot, flag)
        let bl = imageVertex(x0, y1, 0, vBot, flag)
        let carrier = MetricDepthMap(depth: frame.depth,
                                     width: frame.depthWidth, height: frame.depthHeight)
        beginDepthSceneBatch(color: frame.color, depth: nil, metricDepth: carrier)
        imageVertices.append(contentsOf: [tl, tr, br, tl, br, bl])
    }

    /// Open a fresh `.depthScene` batch carrying the color backdrop and either a
    /// normalized gray `depth` map or a `metricDepth` map (meters). Always appends
    /// (like `beginImageBatch`); resets `currentKind`.
    private func beginDepthSceneBatch(color: Image, depth: Image?, metricDepth: MetricDepthMap?) {
        currentKind = .depthScene
        currentBatchBlend = currentBlend
        currentBatchDepth = currentDepth
        batches.append(GeometryBatch(kind: .depthScene, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count,
                                     imageStart: imageVertices.count,
                                     glyphStart: glyphVertices.count,
                                     pointStart: points.count,
                                     meshStart: meshVertices.count,
                                     sdfGroupStart: sdfGroups.count,
                                     sdf3DGroupStart: sdf3DGroups.count,
                                     blendMode: currentBlend, image: color,
                                     depthImage: depth, metricDepth: metricDepth,
                                     target: currentTarget))
    }

    /// Build one textured-quad vertex, transforming its position by the current
    /// CTM (mirrors `emit` for the triangle path).
    func imageVertex(_ x: Float, _ y: Float, _ u: Float, _ v: Float,
                             _ tint: SIMD4<Float>) -> OllinImageVertex {
        var position = SIMD2<Float>(x, y)
        if !transformIsIdentity {
            let p = transform * SIMD3<Float>(x, y, 1)
            position = SIMD2<Float>(p.x, p.y)
        }
        return OllinImageVertex(position: position, uv: SIMD2<Float>(u, v), tint: tint)
    }
}
