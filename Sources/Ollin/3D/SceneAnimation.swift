import Foundation
import simd

/// One authored animation of a loaded `Scene`: named keyframe tracks that move
/// nodes by translation, rotation, and scale, and blend their meshes' morph
/// targets by weight. Sample it onto the scene at any time with
/// `scene.apply(_:at:)`, driven by the sketch's own clock:
///
/// ```swift
/// var stage: Scene!
/// override func setup() { stage = loadScene("Orrery.gltf")! }
/// override func draw() {
///     if let spin = stage.animation("spin") {
///         stage.apply(spin, at: time.truncatingRemainder(dividingBy: spin.duration))
///     }
///     drawScene(stage)
/// }
/// ```
///
/// Sampling follows the file's authored interpolation per track: stepped holds,
/// linear blends (rotations along the shortest arc), or cubic splines. A time
/// before a track's first keyframe or past its last holds the nearest keyframe's
/// value, so a one-shot animation ends in its final pose; loop it by wrapping
/// `time` over `duration`, as above. Applying is absolute (the same time always
/// produces the same pose), so calling it every frame just works.
public struct SceneAnimation: Sendable {

    /// The animation's authored name (empty when the file gave it none). Names are
    /// how `scene.animation(_:)` finds one.
    public var name: String

    /// The end of the animation's timeline in seconds: the latest keyframe over
    /// every track. Tracks may start later than 0; before a track's first
    /// keyframe its value holds.
    public var duration: Double

    /// The per-node tracks, keyed by the file's node identity.
    var tracks: [Track]

    init(name: String, duration: Double, tracks: [Track]) {
        self.name = name
        self.duration = duration
        self.tracks = tracks
    }

    /// Every channel targeting one node, grouped so the node's pose rebuilds once
    /// per application. glTF tracks bind by the file's node index (matched against
    /// `SceneNode.sourceIndex`); USD tracks bind by node *name* instead (the
    /// platform importer that builds the node tree keeps no prim identity), so a
    /// name duplicated across branches animates its first depth-first match, the
    /// subscript's rule. The native USD scene walk will replace name binding with
    /// real per-prim identity.
    struct Track: Sendable {
        var nodeIndex: Int
        /// The target node's name, for tracks bound by name rather than index.
        var nodeName: String? = nil
        var translation: Sampler?
        var rotation: Sampler?
        var scale: Sampler?
        var weights: WeightsSampler?
    }

    /// One keyframe curve: timestamps plus values, sampled by the authored
    /// interpolation mode. Values are stored one `SIMD4` per keyframe (vec3
    /// channels pad w with 0), or three per keyframe for cubic splines: the
    /// in-tangent, the value, and the out-tangent, in the file's element order.
    struct Sampler: Sendable {
        enum Mode: Sendable { case step, linear, cubicSpline }
        var times: [Double]
        var values: [SIMD4<Float>]
        var mode: Mode

        /// The stored value element of keyframe `k` (skipping tangents for splines).
        private func value(_ k: Int) -> SIMD4<Float> {
            mode == .cubicSpline ? values[3 * k + 1] : values[k]
        }

        /// The segment containing `time`: the keyframe index `k` with
        /// `times[k] <= time < times[k+1]`, or nil when the time clamps to an end.
        private func segment(at time: Double) -> Int? {
            guard time > times[0] else { return nil }
            guard time < times[times.count - 1] else { return nil }
            // Binary search: the last keyframe at or before `time`.
            var lo = 0, hi = times.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if times[mid] <= time { lo = mid } else { hi = mid }
            }
            return lo
        }

        /// Sample a vector channel (translation, scale) at `time`, clamping
        /// outside the keyframe range.
        func sample(at time: Double) -> SIMD4<Float> {
            guard let k = segment(at: time) else {
                return time <= times[0] ? value(0) : value(times.count - 1)
            }
            let td = times[k + 1] - times[k]
            let t = Float((time - times[k]) / td)
            switch mode {
            case .step:
                return value(k)
            case .linear:
                return (1 - t) * value(k) + t * value(k + 1)
            case .cubicSpline:
                return hermite(k, t: t, td: Float(td))
            }
        }

        /// Sample a rotation channel at `time`: linear tracks take the spherical
        /// interpolation along the shortest arc, splines interpolate the raw
        /// components; either way the result is normalized.
        func sampleRotation(at time: Double) -> simd_quatf {
            guard let k = segment(at: time) else {
                let v = time <= times[0] ? value(0) : value(times.count - 1)
                return simd_normalize(simd_quatf(ix: v.x, iy: v.y, iz: v.z, r: v.w))
            }
            let td = times[k + 1] - times[k]
            let t = Float((time - times[k]) / td)
            let raw: SIMD4<Float>
            switch mode {
            case .step:
                raw = value(k)
            case .linear:
                raw = SceneAnimation.Sampler.slerp(value(k), value(k + 1), t)
            case .cubicSpline:
                raw = hermite(k, t: t, td: Float(td))
            }
            return simd_normalize(simd_quatf(ix: raw.x, iy: raw.y, iz: raw.z, r: raw.w))
        }

        /// The cubic Hermite blend over segment `k` at normalized `t`: keyframe
        /// `k`'s value and out-tangent against `k+1`'s value and in-tangent, the
        /// tangents scaled by the segment duration `td`.
        private func hermite(_ k: Int, t: Float, td: Float) -> SIMD4<Float> {
            let t2 = t * t, t3 = t2 * t
            let vk = values[3 * k + 1], bk = values[3 * k + 2]
            let ak1 = values[3 * (k + 1)], vk1 = values[3 * (k + 1) + 1]
            return (2 * t3 - 3 * t2 + 1) * vk + td * (t3 - 2 * t2 + t) * bk
                + (-2 * t3 + 3 * t2) * vk1 + td * (t3 - t2) * ak1
        }

        /// Spherical linear interpolation between two raw quaternions along the
        /// shortest arc: the arc angle comes from the dot product's absolute
        /// value and its sign folds into the second endpoint. A near-parallel
        /// pair degrades to normalized linear interpolation.
        static func slerp(_ q0: SIMD4<Float>, _ q1: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
            let d = simd_dot(q0, q1)
            let s: Float = d < 0 ? -1 : 1
            let m = min(abs(d), 1)
            if m > 1 - 1e-6 {
                return simd_normalize((1 - t) * q0 + (t * s) * q1)
            }
            let a = acos(m)
            return (sin(a * (1 - t)) / sin(a)) * q0 + (s * sin(a * t) / sin(a)) * q1
        }
    }

    /// A morph-weights keyframe curve: `count` scalars per keyframe (one per
    /// morph target), flattened in the file's layout. For a cubic spline each
    /// keyframe stores three groups of `count` scalars: every target's
    /// in-tangent, then every value, then every out-tangent.
    struct WeightsSampler: Sendable {
        var times: [Double]
        var values: [Float]
        var count: Int
        var mode: Sampler.Mode

        /// The stored value of target `c` at keyframe `k` (skipping tangents).
        private func value(_ k: Int, _ c: Int) -> Float {
            mode == .cubicSpline ? values[(3 * k + 1) * count + c] : values[k * count + c]
        }

        /// Sample every target's weight at `time`, clamping outside the
        /// keyframe range like the vector samplers.
        func sample(at time: Double) -> [Double] {
            guard time > times[0] else { return (0..<count).map { Double(value(0, $0)) } }
            guard time < times[times.count - 1] else {
                return (0..<count).map { Double(value(times.count - 1, $0)) }
            }
            var lo = 0, hi = times.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if times[mid] <= time { lo = mid } else { hi = mid }
            }
            let td = times[lo + 1] - times[lo]
            let t = Float((time - times[lo]) / td)
            switch mode {
            case .step:
                return (0..<count).map { Double(value(lo, $0)) }
            case .linear:
                return (0..<count).map {
                    Double((1 - t) * value(lo, $0) + t * value(lo + 1, $0))
                }
            case .cubicSpline:
                let t2 = t * t, t3 = t2 * t
                let ftd = Float(td)
                return (0..<count).map { c in
                    let vk = values[(3 * lo + 1) * count + c]
                    let bk = values[(3 * lo + 2) * count + c]
                    let ak1 = values[3 * (lo + 1) * count + c]
                    let vk1 = values[(3 * (lo + 1) + 1) * count + c]
                    return Double((2 * t3 - 3 * t2 + 1) * vk + ftd * (t3 - 2 * t2 + t) * bk
                        + (-2 * t3 + 3 * t2) * vk1 + ftd * (t3 - t2) * ak1)
                }
            }
        }
    }
}

// MARK: - Applying to a scene

extension Scene {

    /// Pose the scene by `animation` sampled at `time` (seconds on the
    /// animation's own timeline): each animated node's local transform rebuilds
    /// from its authored components with the sampled ones swapped in, so
    /// un-animated components keep their authored values. Absolute, not
    /// additive: applying the same time twice gives the same pose, so call it
    /// every frame in `draw()`. Times outside the keyframe range hold the
    /// nearest keyframe; loop by wrapping `time` over `duration`. Only geometry
    /// moves: the scene's `cameras` and `lights` were resolved at load.
    public mutating func apply(_ animation: SceneAnimation, at time: Double) {
        for track in animation.tracks {
            _ = Scene.apply(track, at: time, in: &nodes)
        }
    }

    /// The first animation named `name`, or `nil`.
    public func animation(_ name: String) -> SceneAnimation? {
        animations.first { $0.name == name }
    }

    private static func apply(_ track: SceneAnimation.Track, at time: Double,
                              in nodes: inout [SceneNode]) -> Bool {
        for i in nodes.indices {
            let matches = track.nodeName.map { nodes[i].name == $0 }
                ?? (nodes[i].sourceIndex == track.nodeIndex)
            if matches {
                nodes[i].apply(track, at: time)
                return true
            }
            if apply(track, at: time, in: &nodes[i].children) { return true }
        }
        return false
    }
}

extension SceneNode {

    /// Rebuild this node's local transform from its authored TRS components with
    /// the track's sampled values swapped in, and sample any morph-weights
    /// channel into `weights`. A node authored with an explicit matrix has no
    /// components to recompose (the spec forbids animating one), so its
    /// transform stays untouched, and a weights-only track leaves the transform
    /// alone entirely.
    mutating func apply(_ track: SceneAnimation.Track, at time: Double) {
        if let s = track.weights { weights = s.sample(at: time) }
        guard track.translation != nil || track.rotation != nil || track.scale != nil
        else { return }
        guard var pose = trs else { return }
        if let s = track.translation {
            let v = s.sample(at: time)
            pose.t = SIMD3<Float>(v.x, v.y, v.z)
        }
        if let s = track.rotation {
            pose.r = s.sampleRotation(at: time).vector
        }
        if let s = track.scale {
            let v = s.sample(at: time)
            pose.s = SIMD3<Float>(v.x, v.y, v.z)
        }
        trs = pose
        localTransform = SceneNode.compose(pose)
    }

    /// T · R · S, the glTF local-transform composition.
    static func compose(_ pose: (t: SIMD3<Float>, r: SIMD4<Float>, s: SIMD3<Float>)) -> simd_float4x4 {
        var translation = matrix_identity_float4x4
        translation.columns.3 = SIMD4<Float>(pose.t.x, pose.t.y, pose.t.z, 1)
        let q = simd_quatf(ix: pose.r.x, iy: pose.r.y, iz: pose.r.z, r: pose.r.w)
        let scale = simd_float4x4(diagonal: SIMD4<Float>(pose.s.x, pose.s.y, pose.s.z, 1))
        return translation * simd_float4x4(q) * scale
    }
}

// MARK: - Parsing

extension SceneAnimation {

    /// Every playable animation in the document: channels grouped into per-node
    /// tracks (sorted by node index, so output order is deterministic), TRS and
    /// morph-weights paths read, unreadable samplers skipped, an animation with
    /// no usable track dropped.
    static func load(from doc: GLTFDocument) -> [SceneAnimation] {
        (doc.gltf.animations ?? []).compactMap { def in
            var byNode: [Int: Track] = [:]
            var end = 0.0
            for channel in def.channels {
                guard let ni = channel.target.node,
                      channel.sampler >= 0, channel.sampler < def.samplers.count else { continue }
                let s = def.samplers[channel.sampler]
                let mode: Sampler.Mode
                switch s.interpolation ?? "LINEAR" {
                case "STEP": mode = .step
                case "CUBICSPLINE": mode = .cubicSpline
                default: mode = .linear
                }
                guard let times = doc.readFloats(s.input), !times.isEmpty,
                      mode != .cubicSpline || times.count >= 2 else { continue }

                if channel.target.path == "weights" {
                    // Morph weights: `k` scalars per keyframe, `k` the target
                    // count of the node's mesh (its first primitive; the format
                    // requires every primitive to agree). A channel with no
                    // morphing mesh to drive, or a mis-sized output, is dropped.
                    let gltfNodes = doc.gltf.nodes ?? []
                    let meshes = doc.gltf.meshes ?? []
                    guard ni >= 0, ni < gltfNodes.count, let mi = gltfNodes[ni].mesh,
                          mi >= 0, mi < meshes.count,
                          let k = meshes[mi].primitives.first?.targets?.count, k > 0,
                          let flat = doc.readFloats(s.output),
                          flat.count == (mode == .cubicSpline ? 3 : 1) * times.count * k
                    else { continue }
                    var track = byNode[ni] ?? Track(nodeIndex: ni)
                    track.weights = WeightsSampler(times: times, values: flat.map(Float.init),
                                                   count: k, mode: mode)
                    byNode[ni] = track
                    end = max(end, times[times.count - 1])
                    continue
                }

                let values: [SIMD4<Float>]?
                switch channel.target.path {
                case "translation", "scale":
                    values = doc.readVec3(s.output).map {
                        $0.map { SIMD4<Float>(Float($0.x), Float($0.y), Float($0.z), 0) }
                    }
                case "rotation":
                    values = doc.readVec4(s.output)
                default:
                    values = nil          // unknown paths
                }
                let expected = mode == .cubicSpline ? 3 * times.count : times.count
                guard let values, values.count == expected else { continue }

                let sampler = Sampler(times: times, values: values, mode: mode)
                var track = byNode[ni] ?? Track(nodeIndex: ni)
                switch channel.target.path {
                case "translation": track.translation = sampler
                case "rotation": track.rotation = sampler
                default: track.scale = sampler
                }
                byNode[ni] = track
                end = max(end, times[times.count - 1])
            }
            guard !byNode.isEmpty else { return nil }
            let tracks = byNode.keys.sorted().map { byNode[$0]! }
            return SceneAnimation(name: def.name ?? "", duration: end, tracks: tracks)
        }
    }
}
