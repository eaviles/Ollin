import Foundation
import simd

// The skinning leg of USD scene import: UsdSkel skeletons, skin bindings, and
// blend shapes, resolved from the same raw-tree read that builds the node
// tree into the deforming tier `drawScene` already poses
// (`SceneSkinning.swift`), so a rigged USD file bends and blends with no new
// user API.
//
// The scene walk already rebuilt each deforming mesh on its authored points,
// kept indexed (the layout every skel primvar and blend-shape offset is
// authored against), so this pass only *attaches*: per-point joint
// influences from the skel primvars, blend-shape targets, and the
// SkelAnimation channels.
//
// Joints become ordinary `SceneNode`s: each Skeleton prim synthesizes a
// container node at the prim's world transform holding one node per joint,
// nested by the joint paths' own hierarchy, each node's TRS base its local
// rest transform. Synthesized nodes carry real identity (`sourceIndex`,
// numbered past every prim index), so SkelAnimation tracks bind by index
// like every other track, and hand-posing a joint works like any node
// (`scene["tip"]?.rotate(...)`). The skinning math then falls out of the
// shipped pose path: a joint's scene-root world is skelWorld ·
// jointSkelSpace, and each binding's inverse-bind entry is
// inv(bindTransform) · geomBindTransform, so worlds[joint] · inverseBind ·
// point is exactly the UsdSkel skinning equation, the skinned node's own
// chain ignored (the shipped rule, shared with glTF).
//
// The envelope, within the parser core's flattened single layers: skin data
// authored on the prims themselves (`skel:skeleton` and the skel primvars on
// the mesh; the animation source on the skeleton or inherited from an
// ancestor), blend shapes with optional sparse `pointIndices` and
// `normalOffsets`. In-between shapes are skipped, and a malformed piece
// degrades to the undeformed draw, never a mis-draw.

extension Scene {

    private struct USDSkeletonRecord {
        var jointPaths: [String]
        /// Synthesized node identity per joint, in skeleton joint order.
        var sourceIndices: [Int]
        /// The authored world-space bind transform per joint.
        var bind: [simd_double4x4]
        /// The bound SkelAnimation prim's path, if any.
        var animSource: String?
        /// The assembled joint subtree, appended to the scene by the caller.
        var container: SceneNode
    }

    /// UsdSkel resolution over the raw tree: synthesizes each Skeleton prim's
    /// joints as nodes (identities numbered from `firstJointIndex`, past
    /// every prim's), attaches skin and blend-shape data to each deforming
    /// mesh's node, and returns the SkelAnimation tracks (joint TRS and
    /// blend-shape weights, all bound by node identity) with their timeline
    /// end, for the caller to merge into the stage's one animation.
    static func resolveUSDSkinning(_ stage: USDStage, into scene: inout Scene,
                                   indexOfPath: [String: Int], firstJointIndex: Int)
        -> (tracks: [SceneAnimation.Track], duration: Double) {

        var skeletons: [String: USDSkeletonRecord] = [:]
        var skeletonOrder: [String] = []
        var meshes: [(prim: USDPrim, path: String, animSource: String?)] = []
        var nextJointIndex = firstJointIndex

        walkPrims(stage) { prim, path, world, animSource in
            switch prim.typeName {
            case "Skeleton":
                if let record = resolveSkeleton(prim, world: world, animSource: animSource,
                                                firstJointIndex: nextJointIndex) {
                    nextJointIndex += record.jointPaths.count
                    skeletons[path] = record
                    skeletonOrder.append(path)
                }
            case "Mesh":
                if prim.isSkelDeforming {
                    meshes.append((prim, path, animSource))
                }
            default:
                break
            }
        }
        guard !skeletons.isEmpty || !meshes.isEmpty else { return ([], 0) }

        let tcps = metadataScalar(stage, "timeCodesPerSecond")
            ?? metadataScalar(stage, "framesPerSecond") ?? 24
        let start = metadataScalar(stage, "startTimeCode") ?? 0
        var tracks: [SceneAnimation.Track] = []
        var duration = 0.0

        // Skeleton subtrees join the scene after the tree nodes.
        for path in skeletonOrder {
            scene.nodes.append(skeletons[path]!.container)
        }

        // SkelAnimation joint channels, bound by synthesized identity.
        for path in skeletonOrder {
            let record = skeletons[path]!
            guard tcps > 0, let animPath = record.animSource,
                  let anim = stage.prim(atPath: animPath) else { continue }
            appendJointTracks(anim, record: record, tcps: tcps, start: start,
                              tracks: &tracks, duration: &duration)
        }

        // Deforming meshes: attach skin and blend-shape data to each prim's
        // node, and bind the weights channel by that same identity.
        for (prim, path, inheritedSource) in meshes {
            resolveDeformingMesh(prim, path: path, stage: stage, skeletons: skeletons,
                                 inheritedAnimSource: inheritedSource,
                                 tcps: tcps, start: start, indexOfPath: indexOfPath,
                                 into: &scene, tracks: &tracks, duration: &duration)
        }
        return (tracks, duration)
    }

    // MARK: - The walk

    /// Visit every prim depth-first in authored order with its absolute path,
    /// composed world transform, and the nearest `skel:animationSource`
    /// binding on it or an ancestor (the binding inherits down the hierarchy).
    private static func walkPrims(
        _ stage: USDStage,
        _ body: (USDPrim, String, simd_double4x4, String?) -> Void) {
        func walk(_ prim: USDPrim, parentPath: String, parent: simd_double4x4,
                  inherited: String?) {
            guard prim.specifier != .class else { return }
            let path = parentPath + "/" + prim.name
            let (local, resets) = prim.localXform()
            let world = resets ? local : parent * local
            let animSource = prim.relationship("skel:animationSource")?.targets.first
                ?? inherited
            body(prim, path, world, animSource)
            for child in prim.children {
                walk(child, parentPath: path, parent: world, inherited: animSource)
            }
        }
        for prim in stage.prims {
            walk(prim, parentPath: "", parent: matrix_identity_double4x4, inherited: nil)
        }
    }

    // MARK: - Skeletons

    /// One Skeleton prim resolved: joint hierarchy from the joint paths
    /// (parent = the longest strict prefix present in the list), local rest
    /// transforms as each joint node's TRS base, world-space bind transforms
    /// kept for the bindings. Nil when joints or bind transforms are missing
    /// or mis-shaped.
    private static func resolveSkeleton(_ prim: USDPrim, world: simd_double4x4,
                                        animSource: String?, firstJointIndex: Int)
        -> USDSkeletonRecord? {
        guard let jointPaths = prim.attribute("joints")?.authoredValue?.usdTokenArray,
              !jointPaths.isEmpty,
              let bind = prim.attribute("bindTransforms")?.authoredValue?
                  .usdMatrixArray(count: jointPaths.count)
        else { return nil }
        let rest = prim.attribute("restTransforms")?.authoredValue?
            .usdMatrixArray(count: jointPaths.count)

        var indexOfPath: [String: Int] = [:]
        for (i, p) in jointPaths.enumerated() where indexOfPath[p] == nil { indexOfPath[p] = i }
        let parents: [Int?] = jointPaths.map { path in
            var p = path
            while let cut = p.lastIndex(of: "/") {
                p = String(p[..<cut])
                if let idx = indexOfPath[p] { return idx }
            }
            return nil
        }

        // Local rest transforms: authored, or derived from the world-space
        // binds (exact when the skeleton stands at its bind placement).
        let localRest: [simd_double4x4] = (0..<jointPaths.count).map { i in
            if let rest { return rest[i] }
            if let p = parents[i] { return bind[p].inverse * bind[i] }
            return world.inverse * bind[i]
        }

        var childLists = [[Int]](repeating: [], count: jointPaths.count)
        var roots: [Int] = []
        for (i, parent) in parents.enumerated() {
            if let parent { childLists[parent].append(i) } else { roots.append(i) }
        }
        // A parent is always a strictly shorter path, so recursion can't cycle.
        func buildJoint(_ i: Int) -> SceneNode {
            let pose = decomposeTRS(localRest[i])
            let name = jointPaths[i].split(separator: "/").last.map(String.init) ?? jointPaths[i]
            return SceneNode(name: name, mesh: nil,
                             children: childLists[i].map(buildJoint),
                             localTransform: SceneNode.compose(pose),
                             sourceIndex: firstJointIndex + i,
                             trs: pose)
        }
        let container = SceneNode(name: prim.name, mesh: nil,
                                  children: roots.map(buildJoint),
                                  localTransform: f4x4(world))
        return USDSkeletonRecord(jointPaths: jointPaths,
                                 sourceIndices: (0..<jointPaths.count).map { firstJointIndex + $0 },
                                 bind: bind, animSource: animSource, container: container)
    }

    // MARK: - SkelAnimation joint channels

    /// One channel's usable keyframes: times in seconds and, per keyframe, the
    /// flat components over the animation's joints. A static (default-only)
    /// channel becomes a single held key; a mis-shaped sample is dropped.
    private struct USDChannel {
        var times: [Double]
        var samples: [[Double]]
    }

    private static func appendJointTracks(_ anim: USDPrim, record: USDSkeletonRecord,
                                          tcps: Double, start: Double,
                                          tracks: inout [SceneAnimation.Track],
                                          duration: inout Double) {
        guard let animJoints = anim.attribute("joints")?.authoredValue?.usdTokenArray,
              !animJoints.isEmpty else { return }
        let t = channel(anim.attribute("translations"), arity: 3,
                        joints: animJoints.count, tcps: tcps, start: start)
        let r = channel(anim.attribute("rotations"), arity: 4,
                        joints: animJoints.count, tcps: tcps, start: start)
        let s = channel(anim.attribute("scales"), arity: 3,
                        joints: animJoints.count, tcps: tcps, start: start)

        var indexOfPath: [String: Int] = [:]
        for (i, p) in record.jointPaths.enumerated() where indexOfPath[p] == nil {
            indexOfPath[p] = i
        }
        for (j, jointPath) in animJoints.enumerated() {
            // A joint the skeleton doesn't declare has no node to drive.
            guard let slot = indexOfPath[jointPath] else { continue }
            var track = SceneAnimation.Track(nodeIndex: record.sourceIndices[slot])
            track.translation = sampler(t, joint: j, arity: 3, isQuaternion: false)
            track.rotation = sampler(r, joint: j, arity: 4, isQuaternion: true)
            track.scale = sampler(s, joint: j, arity: 3, isQuaternion: false)
            guard track.translation != nil || track.rotation != nil || track.scale != nil
            else { continue }
            tracks.append(track)
            for c in [track.translation, track.rotation, track.scale] {
                if let last = c?.times.last { duration = Swift.max(duration, last) }
            }
        }
    }

    private static func channel(_ attr: USDAttribute?, arity: Int, joints: Int,
                                tcps: Double, start: Double) -> USDChannel? {
        guard let attr else { return nil }
        var raw = attr.timeSamples.map { ($0.time, $0.value) }
        if raw.isEmpty, let v = attr.value { raw = [(start, v)] }
        var times: [Double] = []
        var samples: [[Double]] = []
        for (time, value) in raw {
            guard let flat = value.usdFlatTuples(arity: arity),
                  flat.count == joints * arity else { continue }
            times.append((time - start) / tcps)
            samples.append(flat)
        }
        guard !times.isEmpty else { return nil }
        return USDChannel(times: times, samples: samples)
    }

    /// One joint's sampler sliced out of a channel. Sample interpolation is a
    /// runtime stage setting, never authored (the transform-animation rule),
    /// so tracks are LINEAR; the shipped rotation sampler slerps its segments
    /// along the shortest arc.
    private static func sampler(_ channel: USDChannel?, joint: Int, arity: Int,
                                isQuaternion: Bool) -> SceneAnimation.Sampler? {
        guard let channel else { return nil }
        var values: [SIMD4<Float>] = []
        values.reserveCapacity(channel.times.count)
        for flat in channel.samples {
            let base = joint * arity
            if isQuaternion {
                // Raw-tree quats are (real, i, j, k); the sampler stores xyzw.
                values.append(SIMD4<Float>(Float(flat[base + 1]), Float(flat[base + 2]),
                                           Float(flat[base + 3]), Float(flat[base])))
            } else {
                values.append(SIMD4<Float>(Float(flat[base]), Float(flat[base + 1]),
                                           Float(flat[base + 2]), 0))
            }
        }
        return SceneAnimation.Sampler(times: channel.times, values: values, mode: .linear)
    }

    // MARK: - Deforming meshes

    private static func resolveDeformingMesh(_ prim: USDPrim, path: String, stage: USDStage,
                                             skeletons: [String: USDSkeletonRecord],
                                             inheritedAnimSource: String?,
                                             tcps: Double, start: Double,
                                             indexOfPath: [String: Int],
                                             into scene: inout Scene,
                                             tracks: inout [SceneAnimation.Track],
                                             duration: inout Double) {
        // The walk built (or, for a hidden prim, skipped) the mesh; the
        // authored point count is the layout every attachment aligns with.
        guard let index = indexOfPath[path] else { return }
        var hasMesh = false
        Scene.withNode(sourceIndex: index, in: &scene.nodes) { hasMesh = $0.mesh != nil }
        guard hasMesh else { return }
        let pointCount = prim.authoredPointCount
        guard pointCount > 0 else { return }

        // The skin binding: mesh-local joint order (skel:joints remaps into
        // the skeleton's order when authored), per-point influences from the
        // skel primvars, inverse binds folding in the geometry bind transform.
        var boundSkeleton: USDSkeletonRecord?
        if let target = prim.relationship("skel:skeleton")?.targets.first,
           let record = skeletons[target] {
            boundSkeleton = record
        }
        var skinAttachment: (index: Int, joints: [SIMD4<UInt16>], weights: [SIMD4<Float>])?
        if let record = boundSkeleton,
           let (joints, weights) = skinPrimvars(prim, pointCount: pointCount) {
            let slots: [Int]
            if let meshJoints = prim.attribute("skel:joints")?.authoredValue?.usdTokenArray {
                var indexOfJoint: [String: Int] = [:]
                for (i, p) in record.jointPaths.enumerated() where indexOfJoint[p] == nil {
                    indexOfJoint[p] = i
                }
                slots = meshJoints.map { indexOfJoint[$0] ?? -1 }
            } else {
                slots = Array(0..<record.jointPaths.count)
            }
            let geomBind = prim.attribute("primvars:skel:geomBindTransform")?.authoredValue?
                .usdMatrix ?? matrix_identity_double4x4
            var skinJoints: [Int] = []
            var inverseBind: [simd_float4x4] = []
            for slot in slots {
                guard slot >= 0, slot < record.bind.count else {
                    // A dangling remap entry poses as the identity rather
                    // than mis-indexing another joint.
                    skinJoints.append(-1)
                    inverseBind.append(matrix_identity_float4x4)
                    continue
                }
                skinJoints.append(record.sourceIndices[slot])
                inverseBind.append(f4x4(record.bind[slot].inverse * geomBind))
            }
            scene.skins.append(SceneSkin(joints: skinJoints, inverseBind: inverseBind))
            skinAttachment = (scene.skins.count - 1, joints, weights)
        }

        // Blend shapes: names pair with target prims by position; offsets
        // expand onto the authored points (sparse via pointIndices).
        var shapeNames: [String] = []
        var morphTargets: [SceneMorphTarget] = []
        if let names = prim.attribute("skel:blendShapes")?.authoredValue?.usdTokenArray,
           let rel = prim.relationship("skel:blendShapeTargets") {
            for (name, target) in zip(names, rel.targets) {
                guard let shape = stage.prim(atPath: target),
                      let morph = resolveBlendShape(shape, pointCount: pointCount)
                else { continue }
                shapeNames.append(name)
                morphTargets.append(morph)
            }
        }
        Scene.withNode(sourceIndex: index, in: &scene.nodes) { node in
            if let (si, joints, weights) = skinAttachment {
                node.skinIndex = si
                node.vertexJoints = joints
                node.vertexWeights = weights
            }
            if !morphTargets.isEmpty {
                node.morphTargets = morphTargets
                node.weights = [Double](repeating: 0, count: morphTargets.count)
            }
        }

        // The weights channel: the animation bound to the mesh's skeleton (or
        // inherited down the prim chain) drives the targets by shape name; a
        // shape the animation doesn't name stays 0. The track binds by the
        // mesh's node identity, like every other track.
        guard tcps > 0, !shapeNames.isEmpty,
              let animPath = boundSkeleton?.animSource ?? inheritedAnimSource,
              let anim = stage.prim(atPath: animPath),
              let animShapes = anim.attribute("blendShapes")?.authoredValue?.usdTokenArray,
              let weightsAttr = anim.attribute("blendShapeWeights") else { return }
        var raw = weightsAttr.timeSamples.map { ($0.time, $0.value) }
        if raw.isEmpty, let v = weightsAttr.value { raw = [(start, v)] }
        var indexOfShape: [String: Int] = [:]
        for (i, s) in animShapes.enumerated() where indexOfShape[s] == nil { indexOfShape[s] = i }
        var times: [Double] = []
        var flat: [Float] = []
        for (time, value) in raw {
            guard let sample = value.usdFloats, sample.count == animShapes.count else { continue }
            times.append((time - start) / tcps)
            for name in shapeNames {
                flat.append(indexOfShape[name].map { sample[$0] } ?? 0)
            }
        }
        guard !times.isEmpty else { return }
        var track = SceneAnimation.Track(nodeIndex: index)
        track.weights = SceneAnimation.WeightsSampler(times: times, values: flat,
                                                      count: shapeNames.count, mode: .linear)
        tracks.append(track)
        duration = Swift.max(duration, times[times.count - 1])
    }

    /// The per-point joint influences from the skel primvars: `elementSize`
    /// influences per point (one shared element under constant interpolation,
    /// the rigid binding), capped at the pose path's four; past four, the
    /// heaviest win (the blend renormalizes over what's used).
    private static func skinPrimvars(_ prim: USDPrim, pointCount: Int)
        -> (joints: [SIMD4<UInt16>], weights: [SIMD4<Float>])? {
        guard let ji = prim.attribute("primvars:skel:jointIndices"),
              let jw = prim.attribute("primvars:skel:jointWeights"),
              case .intArray(let rawIndices)? = ji.authoredValue,
              let rawWeights = jw.authoredValue?.usdFloats,
              rawWeights.count == rawIndices.count else { return nil }
        let elementSize = Swift.max(ji.metadata["elementSize"]?.usdInt ?? 1, 1)
        let constant = ji.metadata["interpolation"]?.usdToken == "constant"
        let expected = constant ? elementSize : pointCount * elementSize
        guard rawIndices.count == expected else { return nil }

        var joints = [SIMD4<UInt16>](repeating: SIMD4<UInt16>(), count: pointCount)
        var weights = [SIMD4<Float>](repeating: SIMD4<Float>(), count: pointCount)
        for p in 0..<pointCount {
            let base = constant ? 0 : p * elementSize
            var picks: [(w: Float, j: Int)] = []
            for e in 0..<elementSize {
                let w = rawWeights[base + e]
                let j = Int(rawIndices[base + e])
                guard w > 0, j >= 0 else { continue }
                picks.append((w, j))
            }
            if picks.count > 4 {
                picks.sort { $0.w != $1.w ? $0.w > $1.w : $0.j < $1.j }
                picks.removeSubrange(4...)
            }
            for (k, pick) in picks.enumerated() {
                joints[p][k] = UInt16(clamping: pick.j)
                weights[p][k] = pick.w
            }
        }
        return (joints, weights)
    }

    /// One BlendShape prim as a morph target over the authored points:
    /// `offsets` land on every point, or on the points `pointIndices` names
    /// (the sparse form), zeros elsewhere; `normalOffsets` ride only when
    /// they pair one-to-one with the offsets.
    private static func resolveBlendShape(_ prim: USDPrim, pointCount: Int)
        -> SceneMorphTarget? {
        guard let offsets = prim.attribute("offsets")?.authoredValue?.usdFlatTuples(arity: 3)
        else { return nil }
        let offsetCount = offsets.count / 3
        let normalOffsets = prim.attribute("normalOffsets")?.authoredValue?
            .usdFlatTuples(arity: 3)
        let haveNormals = normalOffsets?.count == offsets.count && !offsets.isEmpty

        func vec(_ flat: [Double], _ i: Int) -> Vector3 {
            Vector3(flat[i * 3], flat[i * 3 + 1], flat[i * 3 + 2])
        }
        var positions = [Vector3](repeating: .zero, count: pointCount)
        var normals = haveNormals ? [Vector3](repeating: .zero, count: pointCount) : []

        if case .intArray(let pointIndices)? = prim.attribute("pointIndices")?.authoredValue {
            guard pointIndices.count == offsetCount else { return nil }
            for (k, raw) in pointIndices.enumerated() {
                let p = Int(raw)
                guard p >= 0, p < pointCount else { continue }
                positions[p] = vec(offsets, k)
                if haveNormals { normals[p] = vec(normalOffsets!, k) }
            }
        } else {
            guard offsetCount == pointCount else { return nil }
            for k in 0..<pointCount {
                positions[k] = vec(offsets, k)
                if haveNormals { normals[k] = vec(normalOffsets!, k) }
            }
        }
        return SceneMorphTarget(positionDeltas: positions, normalDeltas: normals)
    }
}
