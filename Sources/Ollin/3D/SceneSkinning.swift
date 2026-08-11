import Foundation
import simd

// The deforming tier of a loaded `Scene`: skins (a joint hierarchy posing a mesh
// through per-vertex joint weights) and morph targets (blended per-vertex
// displacements). Both are data the loader attaches to nodes; `drawScene` poses
// with them automatically, so an animated file that bends and blends just plays.
// The posing math lives here so it can be pinned by unit tests without a render.

/// One skin of a loaded `Scene`: the joint nodes (as file node indices, the
/// identity `SceneNode.sourceIndex` carries) and one inverse bind matrix per
/// joint, which maps the mesh's bind-pose space into that joint's local space.
struct SceneSkin: Sendable {
    var joints: [Int]
    var inverseBind: [simd_float4x4]
}

/// One morph target of a node's mesh: per-vertex displacements aligned with the
/// mesh's `positions`. `normalDeltas` is empty for a target that moves no
/// normals (the base normals then shade the blended shape).
struct SceneMorphTarget: Sendable {
    var positionDeltas: [Vector3]
    var normalDeltas: [Vector3]
}

extension Scene {

    /// Every file-indexed node's transform relative to the scene root, composed
    /// in one walk of the tree: the pose the skinning pass reads joints from.
    /// Hand-built nodes carry no source index, so they can't act as joints.
    package func nodeWorldTransforms() -> [Int: simd_float4x4] {
        var worlds: [Int: simd_float4x4] = [:]
        func visit(_ node: SceneNode, parent: simd_float4x4) {
            let world = parent * node.localTransform
            if let si = node.sourceIndex { worlds[si] = world }
            for child in node.children { visit(child, parent: world) }
        }
        for node in nodes { visit(node, parent: matrix_identity_float4x4) }
        return worlds
    }
}

extension SceneNode {

    /// This node's mesh with its morph-target displacements blended in at the
    /// current `weights`: position = base + Σ weight · target displacement, and
    /// the same for normals when a target carries normal displacements
    /// (renormalized once at the end). Returns `nil` when there is nothing to
    /// morph (no mesh, no targets, every weight zero, or displacement arrays
    /// that don't align with the mesh), so the un-morphing path stays the
    /// untouched original.
    func morphedMesh() -> Mesh? {
        guard let mesh, !morphTargets.isEmpty, !weights.isEmpty else { return nil }
        let n = mesh.positions.count
        let active = zip(weights, morphTargets).filter {
            $0.0 != 0 && $0.1.positionDeltas.count == n
        }
        guard !active.isEmpty else { return nil }
        var copy = mesh
        var movedNormals = false
        let hasNormals = mesh.normals.count == n
        for (weight, target) in active {
            for i in 0..<n {
                copy.positions[i] = copy.positions[i] + target.positionDeltas[i] * weight
            }
            if hasNormals, target.normalDeltas.count == n {
                movedNormals = true
                for i in 0..<n {
                    copy.normals[i] = copy.normals[i] + target.normalDeltas[i] * weight
                }
            }
        }
        if movedNormals {
            for i in 0..<n {
                let v = copy.normals[i]
                copy.normals[i] = v.lengthSquared > 1e-12 ? v.normalized : .unitY
            }
        }
        return copy
    }

    /// `base` (this node's mesh, or its morphed copy) posed by `skin`'s joints:
    /// each vertex blends its (up to four) joint matrices by its weights, where a
    /// joint matrix is the joint node's scene-root transform times its inverse
    /// bind matrix. The result lands in *scene-root* space: the format's rule is
    /// that a skinned mesh's own node chain is ignored, its placement coming
    /// entirely from the joints. Normals blend the joint matrices'
    /// inverse-transposes and renormalize. Weights renormalize defensively over
    /// the influences actually used (a malformed joint index drops out); a vertex
    /// with no usable influence keeps its bind-pose position. Returns `nil` when
    /// the skin attributes don't align with the mesh, so the caller can fall back
    /// to drawing undeformed.
    func skinnedMesh(_ base: Mesh, skin: SceneSkin,
                     worlds: [Int: simd_float4x4]) -> Mesh? {
        let n = base.positions.count
        guard !skin.joints.isEmpty, vertexJoints.count == n, vertexWeights.count == n
        else { return nil }

        var jointMatrices = [simd_float4x4]()
        var normalMatrices = [simd_float3x3]()
        jointMatrices.reserveCapacity(skin.joints.count)
        normalMatrices.reserveCapacity(skin.joints.count)
        for (j, source) in skin.joints.enumerated() {
            let world = worlds[source] ?? matrix_identity_float4x4
            let inverseBind = j < skin.inverseBind.count
                ? skin.inverseBind[j] : matrix_identity_float4x4
            let m = world * inverseBind
            jointMatrices.append(m)
            normalMatrices.append(m.normalMatrix)
        }

        var copy = base
        let hasNormals = base.normals.count == n
        // Tangents pose with the positions (the blended joint matrix's linear
        // part; a surface direction, not the normal's inverse-transpose), so a
        // normal map keeps lighting correctly on a bent limb.
        let hasTangents = base.tangents.count == n
        for i in 0..<n {
            let vj = vertexJoints[i]
            let vw = vertexWeights[i]
            var m = simd_float4x4()
            var nm = simd_float3x3()
            var used: Float = 0
            for k in 0..<4 {
                let w = vw[k]
                guard w > 0 else { continue }
                let ji = Int(vj[k])
                guard ji < jointMatrices.count else { continue }
                m += jointMatrices[ji] * w
                nm += normalMatrices[ji] * w
                used += w
            }
            guard used > 1e-6 else { continue }
            let inv = 1 / used
            let p = base.positions[i]
            let hp = m * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
            copy.positions[i] = Vector3(Double(hp.x * inv), Double(hp.y * inv),
                                        Double(hp.z * inv))
            if hasNormals {
                let bn = base.normals[i]
                let hn = nm * SIMD3<Float>(Float(bn.x), Float(bn.y), Float(bn.z))
                let v = Vector3(Double(hn.x), Double(hn.y), Double(hn.z))
                copy.normals[i] = v.lengthSquared > 1e-12 ? v.normalized : bn
            }
            if hasTangents {
                let bt = base.tangents[i]
                let lin = simd_float3x3(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                                        SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                                        SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
                let ht = lin * SIMD3<Float>(Float(bt.direction.x), Float(bt.direction.y),
                                            Float(bt.direction.z))
                let v = Vector3(Double(ht.x), Double(ht.y), Double(ht.z))
                if v.lengthSquared > 1e-12 {
                    copy.tangents[i] = MeshTangent(v.normalized, handedness: bt.handedness)
                }
            }
        }
        return copy
    }
}
