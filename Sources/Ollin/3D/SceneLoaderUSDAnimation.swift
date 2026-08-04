import Foundation
import simd

// The animation leg of USD scene import: the authored xformOp timeSamples
// become `SceneAnimation` tracks, from the same raw-tree read that builds the
// node tree.
//
// A flattened USD layer has no named clips; the layer's whole timeline is one
// animation, so a stage with any sampled xformOp yields exactly one (unnamed)
// `SceneAnimation`. Each animated prim's op stack is *baked*: the composed
// local matrix is evaluated at the union of the prim's authored sample times
// (each op's attribute sampled per the runtime's default linear interpolation;
// `USDAttribute.sampled(at:)`) and decomposed into translation/rotation/scale
// keys. Baking is what lets every authored op form (pivot pairs, single-axis
// ops, mixed orders, whole-matrix ops) play through the existing three track
// kinds; the price is that an op stack whose composition genuinely shears
// (possible only through matrix ops interleaved with non-uniform scales)
// keeps only its TRS part. Time codes convert to seconds through the layer's
// `timeCodesPerSecond` (falling back to `framesPerSecond`, then the spec
// default 24), offset by `startTimeCode`, so a timeline authored to open at
// frame 101 (a common DCC convention) still starts at zero. Sample
// interpolation is a runtime choice the format never authors (linear is the
// universal default), so baked tracks are LINEAR; a non-lerpable value type
// holds between samples, which is the held/STEP semantic exactly where it
// can occur.
//
// Each track is keyed by its prim's absolute path; the scene walk maps paths
// onto the per-prim node identity (`SceneNode.sourceIndex`) it assigned, so a
// name duplicated across branches animates exactly the prim that authored
// the samples.

extension Scene {

    typealias RestPose = (t: SIMD3<Float>, r: SIMD4<Float>, s: SIMD3<Float>)

    /// One animated prim's bake: its absolute path (the binding key), its
    /// keyframe track (`nodeIndex` unassigned until the scene walk maps it),
    /// and its rest pose (the decomposed op stack at rest, the TRS base
    /// `apply(_:at:)` swaps sampled components into).
    struct USDBakedTrack {
        var path: String
        var track: SceneAnimation.Track
        var rest: RestPose
    }

    /// The stage's authored transform animation, baked per prim in traversal
    /// order. Nil when no xformOp carries time samples.
    static func resolveUSDAnimation(_ stage: USDStage)
        -> (duration: Double, entries: [USDBakedTrack])? {
        let tcps = metadataScalar(stage, "timeCodesPerSecond")
            ?? metadataScalar(stage, "framesPerSecond") ?? 24
        guard tcps > 0 else { return nil }
        let start = metadataScalar(stage, "startTimeCode") ?? 0

        var entries: [USDBakedTrack] = []
        var end = 0.0
        func walk(_ prim: USDPrim, parentPath: String) {
            if prim.specifier == .class { return }
            let path = parentPath + "/" + prim.name
            let times = animatedSampleTimes(prim)
            if !times.isEmpty {
                var translations: [SIMD4<Float>] = []
                var rotations: [SIMD4<Float>] = []
                var scales: [SIMD4<Float>] = []
                var previous: SIMD4<Float>?
                for t in times {
                    let (matrix, _) = prim.localXform(at: t)
                    let (tt, r, s) = decomposeTRS(matrix)
                    // Keep consecutive quaternion keys on one hemisphere so
                    // the sampler's shortest arc is the baked arc.
                    var q = r
                    if let p = previous, simd_dot(p, q) < 0 { q = -q }
                    previous = q
                    translations.append(SIMD4<Float>(tt, 0))
                    rotations.append(q)
                    scales.append(SIMD4<Float>(s, 0))
                }
                let seconds = times.map { ($0 - start) / tcps }
                let track = SceneAnimation.Track(
                    nodeIndex: -1,
                    translation: .init(times: seconds, values: translations, mode: .linear),
                    rotation: .init(times: seconds, values: rotations, mode: .linear),
                    scale: .init(times: seconds, values: scales, mode: .linear))
                entries.append(USDBakedTrack(path: path, track: track,
                                             rest: decomposeTRS(prim.localXform().matrix)))
                end = Swift.max(end, seconds[seconds.count - 1])
            }
            for child in prim.children { walk(child, parentPath: path) }
        }
        for prim in stage.prims { walk(prim, parentPath: "") }
        guard !entries.isEmpty else { return nil }
        return (end, entries)
    }

    /// The union of authored sample times over the ops the prim's
    /// `xformOpOrder` actually applies, ascending and deduplicated.
    private static func animatedSampleTimes(_ prim: USDPrim) -> [Double] {
        var all: [Double] = []
        for token in prim.xformOpOrderTokens where token != "!resetXformStack!" {
            let name = token.hasPrefix("!invert!")
                ? String(token.dropFirst("!invert!".count)) : token
            if let samples = prim.attribute(name)?.timeSamples {
                all.append(contentsOf: samples.map(\.time))
            }
        }
        guard !all.isEmpty else { return [] }
        all.sort()
        var times: [Double] = []
        for t in all where times.last != t { times.append(t) }
        return times
    }

    /// A composed local matrix split back into translation, rotation
    /// (an xyzw quaternion), and scale, assuming the T·R·S shape every
    /// shear-free op stack composes to. A mirrored basis folds its flip into
    /// the x scale (the standard convention), keeping the rotation proper.
    /// (Shared with the skinning leg, which decomposes joint rest transforms.)
    static func decomposeTRS(_ m: simd_double4x4) -> RestPose {
        let t = SIMD3<Float>(Float(m.columns.3.x), Float(m.columns.3.y), Float(m.columns.3.z))
        let c0 = SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)
        let c1 = SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z)
        let c2 = SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        var sx = simd_length(c0)
        let sy = simd_length(c1), sz = simd_length(c2)
        if simd_determinant(simd_double3x3(c0, c1, c2)) < 0 { sx = -sx }
        guard sx != 0, sy != 0, sz != 0 else {
            return (t, SIMD4<Float>(0, 0, 0, 1), SIMD3<Float>(Float(sx), Float(sy), Float(sz)))
        }
        let q = simd_quatd(simd_double3x3(c0 / sx, c1 / sy, c2 / sz)).normalized
        return (t,
                SIMD4<Float>(Float(q.imag.x), Float(q.imag.y), Float(q.imag.z), Float(q.real)),
                SIMD3<Float>(Float(sx), Float(sy), Float(sz)))
    }

    static func metadataScalar(_ stage: USDStage, _ key: String) -> Double? {
        stage.metadata[key]?.usdScalar
    }
}
