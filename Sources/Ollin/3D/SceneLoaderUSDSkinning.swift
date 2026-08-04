import Foundation
import simd

// The skinning leg of USD scene import: UsdSkel skeletons, skin bindings, and
// blend shapes, resolved from the same raw-tree read that serves lights and
// transform animation into the deforming tier `drawScene` already poses
// (`SceneSkinning.swift`), so a rigged USD file bends and blends with no new
// user API.
//
// The platform importer can't carry this tier: its joint vertex attributes
// come back scrambled, and a deforming mesh's vertex layout is whatever it
// chose (authored points kept here, expanded per face corner there, split
// again by normal generation), so per-point data (joint weights, blend-shape
// offsets) has nothing stable to align with. A deforming mesh is therefore
// rebuilt from the raw tree itself: authored points kept indexed (the layout
// every skel primvar and blend-shape offset is authored against), faces
// fan-triangulated, authored vertex-interpolated normals honored (smoothed
// across faces otherwise), vertex-interpolated `primvars:st` carried (v
// flipped to the top-left convention), and the bound preview-surface diffuse
// color read raw, matching how the platform path colors the file's unskinned
// meshes (the spec-correct color pass belongs to the native swap).
//
// Joints become ordinary `SceneNode`s: each Skeleton prim synthesizes a
// container node at the prim's world transform holding one node per joint,
// nested by the joint paths' own hierarchy, each node's TRS base its local
// rest transform. Synthesized nodes carry real identity (`sourceIndex`), so
// SkelAnimation tracks bind by index rather than name, and hand-posing a
// joint works like any node (`scene["tip"]?.rotate(...)`). The skinning math
// then falls out of the shipped pose path: a joint's scene-root world is
// skelWorld · jointSkelSpace, and each binding's inverse-bind entry is
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
    /// joints as nodes, rebuilds each deforming mesh from its authored points
    /// with skin and blend-shape data attached, and returns the SkelAnimation
    /// tracks (joint TRS by node identity, blend-shape weights by node name)
    /// with their timeline end, for the caller to merge into the stage's one
    /// animation.
    static func resolveUSDSkinning(_ stage: USDStage, into scene: inout Scene)
        -> (tracks: [SceneAnimation.Track], duration: Double) {

        var skeletons: [String: USDSkeletonRecord] = [:]
        var skeletonOrder: [String] = []
        var meshes: [(prim: USDPrim, animSource: String?)] = []
        var nextJointIndex = 0

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
                if prim.relationship("skel:skeleton") != nil
                    || prim.relationship("skel:blendShapeTargets") != nil {
                    meshes.append((prim, animSource))
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

        // Skeleton subtrees join the scene after the platform nodes, so
        // name-bound lookups keep finding tree nodes first.
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

        // Deforming meshes: rebuild from authored points, attach skin and
        // blend-shape data to the tree node of the prim's name, and bind the
        // weights channel by that same name.
        for (prim, inheritedSource) in meshes {
            resolveDeformingMesh(prim, stage: stage, skeletons: skeletons,
                                 inheritedAnimSource: inheritedSource,
                                 tcps: tcps, start: start, into: &scene,
                                 tracks: &tracks, duration: &duration)
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
        guard case .tokenArray(let jointPaths)? = prim.attribute("joints")?.authoredValue,
              !jointPaths.isEmpty,
              let bind = matrixArray(prim.attribute("bindTransforms")?.authoredValue,
                                     count: jointPaths.count)
        else { return nil }
        let rest = matrixArray(prim.attribute("restTransforms")?.authoredValue,
                               count: jointPaths.count)

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
        guard case .tokenArray(let animJoints)? = anim.attribute("joints")?.authoredValue,
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
            guard let flat = flatTuples(value, arity: arity),
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

    private static func resolveDeformingMesh(_ prim: USDPrim, stage: USDStage,
                                             skeletons: [String: USDSkeletonRecord],
                                             inheritedAnimSource: String?,
                                             tcps: Double, start: Double,
                                             into scene: inout Scene,
                                             tracks: inout [SceneAnimation.Track],
                                             duration: inout Double) {
        guard let built = buildDeformingMesh(prim, stage: stage),
              var node = scene.node(prim.name) else { return }
        node.mesh = built.mesh

        // The skin binding: mesh-local joint order (skel:joints remaps into
        // the skeleton's order when authored), per-point influences from the
        // skel primvars, inverse binds folding in the geometry bind transform.
        var boundSkeleton: USDSkeletonRecord?
        if let target = prim.relationship("skel:skeleton")?.targets.first,
           let record = skeletons[target] {
            boundSkeleton = record
        }
        if let record = boundSkeleton,
           let (joints, weights) = skinPrimvars(prim, pointCount: built.pointCount) {
            let slots: [Int]
            if case .tokenArray(let meshJoints)? = prim.attribute("skel:joints")?.authoredValue {
                var indexOfPath: [String: Int] = [:]
                for (i, p) in record.jointPaths.enumerated() where indexOfPath[p] == nil {
                    indexOfPath[p] = i
                }
                slots = meshJoints.map { indexOfPath[$0] ?? -1 }
            } else {
                slots = Array(0..<record.jointPaths.count)
            }
            let geomBind = matrix(prim.attribute("primvars:skel:geomBindTransform")?.authoredValue)
                ?? matrix_identity_double4x4
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
            node.skinIndex = scene.skins.count - 1
            node.vertexJoints = joints
            node.vertexWeights = weights
        }

        // Blend shapes: names pair with target prims by position; offsets
        // expand onto the authored points (sparse via pointIndices).
        var shapeNames: [String] = []
        var morphTargets: [SceneMorphTarget] = []
        if case .tokenArray(let names)? = prim.attribute("skel:blendShapes")?.authoredValue,
           let rel = prim.relationship("skel:blendShapeTargets") {
            for (name, target) in zip(names, rel.targets) {
                guard let shape = stage.prim(atPath: target),
                      let morph = resolveBlendShape(shape, pointCount: built.pointCount)
                else { continue }
                shapeNames.append(name)
                morphTargets.append(morph)
            }
        }
        if !morphTargets.isEmpty {
            node.morphTargets = morphTargets
            node.weights = [Double](repeating: 0, count: morphTargets.count)
        }
        scene[prim.name] = node

        // The weights channel: the animation bound to the mesh's skeleton (or
        // inherited down the prim chain) drives the targets by shape name; a
        // shape the animation doesn't name stays 0. The mesh's node is a
        // platform node with no prim identity, so this one track kind binds
        // by name, like the xformOp tracks.
        guard tcps > 0, !shapeNames.isEmpty,
              let animPath = boundSkeleton?.animSource ?? inheritedAnimSource,
              let anim = stage.prim(atPath: animPath),
              case .tokenArray(let animShapes)? = anim.attribute("blendShapes")?.authoredValue,
              let weightsAttr = anim.attribute("blendShapeWeights") else { return }
        var raw = weightsAttr.timeSamples.map { ($0.time, $0.value) }
        if raw.isEmpty, let v = weightsAttr.value { raw = [(start, v)] }
        var indexOfShape: [String: Int] = [:]
        for (i, s) in animShapes.enumerated() where indexOfShape[s] == nil { indexOfShape[s] = i }
        var times: [Double] = []
        var flat: [Float] = []
        for (time, value) in raw {
            guard let sample = floats(value), sample.count == animShapes.count else { continue }
            times.append((time - start) / tcps)
            for name in shapeNames {
                flat.append(indexOfShape[name].map { sample[$0] } ?? 0)
            }
        }
        guard !times.isEmpty else { return }
        var track = SceneAnimation.Track(nodeIndex: -1, nodeName: prim.name)
        track.weights = SceneAnimation.WeightsSampler(times: times, values: flat,
                                                      count: shapeNames.count, mode: .linear)
        tracks.append(track)
        duration = Swift.max(duration, times[times.count - 1])
    }

    /// The prim's mesh rebuilt from its authored data, keeping the authored
    /// points indexed: the layout every skel primvar and blend-shape offset
    /// aligns with. Nil when the geometry is unreadable (the caller leaves
    /// the platform node untouched, an undeformed but honest draw).
    private static func buildDeformingMesh(_ prim: USDPrim, stage: USDStage)
        -> (mesh: Mesh, pointCount: Int)? {
        guard let pointsFlat = flatTuples(prim.attribute("points")?.authoredValue, arity: 3),
              case .intArray(let counts)? = prim.attribute("faceVertexCounts")?.authoredValue,
              case .intArray(let rawIndices)? = prim.attribute("faceVertexIndices")?.authoredValue
        else { return nil }
        let pointCount = pointsFlat.count / 3
        guard pointCount > 0 else { return nil }
        var positions = [Vector3]()
        positions.reserveCapacity(pointCount)
        for i in 0..<pointCount {
            positions.append(Vector3(pointsFlat[i * 3], pointsFlat[i * 3 + 1],
                                     pointsFlat[i * 3 + 2]))
        }

        // Fan-triangulate the authored faces, keeping the authored winding
        // (reversed for a leftHanded orientation); a face with a bad index is
        // skipped whole rather than mis-wound.
        let leftHanded = metaToken(prim.attribute("orientation")?.authoredValue) == "leftHanded"
        var indices: [UInt32] = []
        var cursor = 0
        for count in counts {
            let c = Int(count)
            defer { cursor += c }
            guard c >= 3, cursor + c <= rawIndices.count else { continue }
            let face = Array(rawIndices[cursor..<(cursor + c)])
            guard face.allSatisfy({ $0 >= 0 && $0 < pointCount }) else { continue }
            for k in 1..<(c - 1) {
                if leftHanded {
                    indices += [UInt32(face[0]), UInt32(face[k + 1]), UInt32(face[k])]
                } else {
                    indices += [UInt32(face[0]), UInt32(face[k]), UInt32(face[k + 1])]
                }
            }
        }
        guard !indices.isEmpty else { return nil }

        // Authored vertex-interpolated normals ride (the attribute's default
        // interpolation); anything else (faceVarying, missing, mis-sized)
        // smooths across faces, the loadMesh treatment.
        var normals = [Vector3](repeating: .zero, count: pointCount)
        var haveNormals = false
        if let attr = prim.attribute("normals"),
           let flat = flatTuples(attr.authoredValue, arity: 3),
           flat.count == pointCount * 3,
           (metaToken(attr.metadata["interpolation"]) ?? "vertex") == "vertex" {
            for i in 0..<pointCount {
                let v = Vector3(flat[i * 3], flat[i * 3 + 1], flat[i * 3 + 2])
                normals[i] = v.lengthSquared > 1e-12 ? v.normalized : .unitY
            }
            haveNormals = true
        }
        if !haveNormals {
            Mesh.smoothNormals(into: &normals, positions: positions, indices: indices,
                               vertexRange: 0..<pointCount)
        }

        // Vertex-interpolated primvars:st carries (v flipped to the top-left
        // convention); a faceVarying set can't ride an indexed mesh and drops.
        var uvs: [Vector2] = []
        if let attr = prim.attribute("primvars:st"),
           let flat = flatTuples(attr.authoredValue, arity: 2),
           flat.count == pointCount * 2,
           metaToken(attr.metadata["interpolation"]) == "vertex" {
            for i in 0..<pointCount {
                uvs.append(Vector2(flat[i * 2], 1 - flat[i * 2 + 1]))
            }
        }

        let mesh = Mesh(positions: positions, normals: normals, indices: indices,
                        uvs: uvs, material: deformingMaterial(prim, stage: stage))
        return (mesh, pointCount)
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
              let rawWeights = floats(jw.authoredValue),
              rawWeights.count == rawIndices.count else { return nil }
        let elementSize = Swift.max(metaInt(ji.metadata["elementSize"]) ?? 1, 1)
        let constant = metaToken(ji.metadata["interpolation"]) == "constant"
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
        guard let offsets = flatTuples(prim.attribute("offsets")?.authoredValue, arity: 3)
        else { return nil }
        let offsetCount = offsets.count / 3
        let normalOffsets = flatTuples(prim.attribute("normalOffsets")?.authoredValue, arity: 3)
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

    /// The bound preview surface's diffuse color, read raw (a display value,
    /// matching the platform path's treatment of the file's other meshes), or
    /// the first authored displayColor. Nil when neither is authored.
    private static func deformingMaterial(_ prim: USDPrim, stage: USDStage) -> MeshMaterial? {
        if let target = prim.relationship("material:binding")?.targets.first,
           let material = stage.prim(atPath: target),
           let color = previewSurfaceColor(material) {
            return MeshMaterial(baseColor: color)
        }
        if let attr = prim.attribute("primvars:displayColor"),
           let flat = flatTuples(attr.authoredValue, arity: 3), flat.count >= 3 {
            return MeshMaterial(baseColor: Color(red: flat[0], green: flat[1], blue: flat[2]))
        }
        return nil
    }

    private static func previewSurfaceColor(_ material: USDPrim) -> Color? {
        if case .token("UsdPreviewSurface")? = material.attribute("info:id")?.authoredValue,
           case .tuple(let c)? = material.attribute("inputs:diffuseColor")?.authoredValue,
           c.count == 3 {
            return Color(red: c[0], green: c[1], blue: c[2])
        }
        for child in material.children {
            if let color = previewSurfaceColor(child) { return color }
        }
        return nil
    }

    // MARK: - Value helpers

    /// A tuple array's flat components widened to `Double`, when the arity
    /// matches.
    private static func flatTuples(_ v: USDValue?, arity: Int) -> [Double]? {
        switch v {
        case .floatTupleArray(let a, let f) where a == arity: f.map(Double.init)
        case .doubleTupleArray(let a, let d) where a == arity: d
        default: nil
        }
    }

    private static func floats(_ v: USDValue?) -> [Float]? {
        switch v {
        case .floatArray(let f): f
        case .doubleArray(let d): d.map(Float.init)
        default: nil
        }
    }

    /// A single matrix4d value as a column-vector matrix (rows load as
    /// columns, the row-vector convention).
    private static func matrix(_ v: USDValue?) -> simd_double4x4? {
        guard case .tuple(let m)? = v, m.count == 16 else { return nil }
        return simd_double4x4(columns: (SIMD4(m[0], m[1], m[2], m[3]),
                                        SIMD4(m[4], m[5], m[6], m[7]),
                                        SIMD4(m[8], m[9], m[10], m[11]),
                                        SIMD4(m[12], m[13], m[14], m[15])))
    }

    /// A matrix4d array as column-vector matrices, requiring exactly `count`.
    private static func matrixArray(_ v: USDValue?, count: Int) -> [simd_double4x4]? {
        guard let flat = flatTuples(v, arity: 16), flat.count == count * 16 else { return nil }
        return (0..<count).map { i in
            let m = Array(flat[i * 16..<(i + 1) * 16])
            return simd_double4x4(columns: (SIMD4(m[0], m[1], m[2], m[3]),
                                            SIMD4(m[4], m[5], m[6], m[7]),
                                            SIMD4(m[8], m[9], m[10], m[11]),
                                            SIMD4(m[12], m[13], m[14], m[15])))
        }
    }

    /// Attribute metadata keeps the file's shape (a token from crate, a bare
    /// string from text), so consumers accept both.
    private static func metaToken(_ v: USDValue?) -> String? {
        switch v {
        case .token(let t): t
        case .string(let s): s
        default: nil
        }
    }

    private static func metaInt(_ v: USDValue?) -> Int? {
        switch v {
        case .int(let i): Int(i)
        case .uint(let u): Int(u)
        default: nil
        }
    }

    private static func f4x4(_ m: simd_double4x4) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1),
                                SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)))
    }
}
