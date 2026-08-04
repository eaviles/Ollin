import Foundation
import simd

// The animation leg of USD scene import: no platform importer carries a USD
// file's timeSamples, so `loadModelIOScene` resolves them from the raw tree,
// the same read that supplies the lights.
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
// frame 101 (a common DCC convention) still starts at zero. Sample interpolation is a runtime choice the format
// never authors (linear is the universal default), so baked tracks are
// LINEAR; a non-lerpable value type holds between samples, which is the
// held/STEP semantic exactly where it can occur.
//
// Tracks bind by node *name* for now: the platform importer that builds the
// node tree keeps no prim identity to index into, so a track finds the first
// node of its prim's name depth-first (a duplicated name animates its first
// match, the subscript's rule). The native scene walk (stage 5 of the arc)
// replaces name binding with real per-prim identity.

extension Scene {

    typealias RestPose = (t: SIMD3<Float>, r: SIMD4<Float>, s: SIMD3<Float>)

    /// The stage's authored transform animation as one `SceneAnimation`, plus
    /// each animated prim's rest pose (the decomposed op stack at rest, the
    /// TRS base `apply(_:at:)` swaps sampled components into), in traversal
    /// order. Nil when no xformOp carries time samples.
    static func resolveUSDAnimation(_ stage: USDStage)
        -> (animation: SceneAnimation, restPoses: [(name: String, pose: RestPose)])? {
        let tcps = metadataScalar(stage, "timeCodesPerSecond")
            ?? metadataScalar(stage, "framesPerSecond") ?? 24
        guard tcps > 0 else { return nil }
        let start = metadataScalar(stage, "startTimeCode") ?? 0

        var tracks: [SceneAnimation.Track] = []
        var restPoses: [(name: String, pose: RestPose)] = []
        var end = 0.0
        func walk(_ prim: USDPrim) {
            if prim.specifier == .class { return }
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
                tracks.append(SceneAnimation.Track(
                    nodeIndex: -1, nodeName: prim.name,
                    translation: .init(times: seconds, values: translations, mode: .linear),
                    rotation: .init(times: seconds, values: rotations, mode: .linear),
                    scale: .init(times: seconds, values: scales, mode: .linear)))
                restPoses.append((prim.name, decomposeTRS(prim.localXform().matrix)))
                end = Swift.max(end, seconds[seconds.count - 1])
            }
            for child in prim.children { walk(child) }
        }
        for prim in stage.prims { walk(prim) }
        guard !tracks.isEmpty else { return nil }
        return (SceneAnimation(name: "", duration: end, tracks: tracks), restPoses)
    }

    /// Install `pose` as the TRS base of the first node named `name`
    /// (depth-first), the same binding its track will use.
    @discardableResult
    static func installRestPose(_ name: String, _ pose: RestPose,
                                in nodes: inout [SceneNode]) -> Bool {
        for i in nodes.indices {
            if nodes[i].name == name { nodes[i].trs = pose; return true }
            if installRestPose(name, pose, in: &nodes[i].children) { return true }
        }
        return false
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
    private static func decomposeTRS(_ m: simd_double4x4) -> RestPose {
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

    private static func metadataScalar(_ stage: USDStage, _ key: String) -> Double? {
        switch stage.metadata[key] {
        case .double(let d): d
        case .int(let i): Double(i)
        case .uint(let u): Double(u)
        default: nil
        }
    }
}
