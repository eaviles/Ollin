import Foundation
import simd

// The skeleton seam: a loaded `Scene`'s joint hierarchy flattened into plain
// values, plus the write-back that poses those joints from outside. The
// skinning pass reads joints to deform a mesh; this reads and *writes* them, so
// something other than a keyframe track can drive the figure. The physics
// satellite builds a ragdoll on it (a rigid body per joint, the simulated pose
// written back), which is why the seam lives in the core rather than in either
// module: satellites never depend on each other.

/// One joint of a loaded scene's skeleton, in the skin's own joint order (so a
/// vertex's `SceneSkinnedVertex.joints` index straight into an array of these).
package struct SceneSkeletonJoint: Sendable {
    /// The joint node's authored name, empty when the file gave it none.
    package var name: String
    /// The joint node's file identity, which is what `Scene.setJointWorlds(_:)`
    /// keys on.
    package var sourceIndex: Int
    /// The joint's parent *within this skin*, as an index into the same array,
    /// or `nil` for a root joint. A joint whose ancestor chain leaves the skin
    /// (an armature container, the scene root) reads as a root.
    package var parent: Int?
    /// The joint node's transform relative to the scene root, composed through
    /// the tree's current transforms: the pose the skeleton is in right now,
    /// which for a freshly loaded scene is its rest pose.
    package var world: simd_float4x4
    /// The skin's inverse bind matrix for this joint: mesh bind space into the
    /// joint's local space, so `world * inverseBind * p` poses a vertex.
    package var inverseBind: simd_float4x4
}

/// One vertex of a skinned mesh, in the mesh's own bind space, with the joints
/// that move it. Consumers that need to know how much of a figure hangs off
/// each joint (fitting a collider to a limb) read these.
package struct SceneSkinnedVertex: Sendable {
    package var position: Vector3
    /// Indices into the skin's joint list (the `skeleton()` array).
    package var joints: SIMD4<UInt16>
    package var weights: SIMD4<Float>
}

extension Scene {

    /// The scene's skeleton: the first skin's joints, in the skin's joint
    /// order, each carrying its current world transform, its inverse bind
    /// matrix, and its parent within the skin. Empty for a scene with no skin.
    ///
    /// Order is the skin's, not the tree's, because that is the order every
    /// per-vertex joint index is written against; parents are named by index,
    /// so a consumer that needs parents-before-children sorts for itself.
    package func skeleton() -> [SceneSkeletonJoint] {
        guard let skin = skins.first, !skin.joints.isEmpty else { return [] }
        let worlds = nodeWorldTransforms()

        // Which skin slot each file node fills, so an ancestor walk can ask
        // "is this node also a joint?" in one lookup.
        var slotOf: [Int: Int] = [:]
        for (slot, source) in skin.joints.enumerated() where slotOf[source] == nil {
            slotOf[source] = slot
        }

        // The nearest joint ancestor of every joint, found in one tree walk
        // that carries the closest enclosing joint slot down each branch.
        var parentOf: [Int: Int] = [:]
        var nameOf: [Int: String] = [:]
        func visit(_ node: SceneNode, enclosing: Int?) {
            var enclosingNext = enclosing
            if let source = node.sourceIndex {
                nameOf[source] = node.name
                if let slot = slotOf[source] {
                    if let enclosing { parentOf[slot] = enclosing }
                    enclosingNext = slot
                }
            }
            for child in node.children { visit(child, enclosing: enclosingNext) }
        }
        for node in nodes { visit(node, enclosing: nil) }

        return skin.joints.enumerated().map { slot, source in
            SceneSkeletonJoint(
                name: nameOf[source] ?? "",
                sourceIndex: source,
                parent: parentOf[slot],
                world: worlds[source] ?? matrix_identity_float4x4,
                inverseBind: slot < skin.inverseBind.count
                    ? skin.inverseBind[slot] : matrix_identity_float4x4)
        }
    }

    /// Every vertex of every mesh the first skin poses, in the mesh's bind
    /// space, with its joint indices and blend weights. Nodes whose skin
    /// attributes don't align with their mesh are skipped, the way the posing
    /// pass skips them.
    package func skinnedVertices() -> [SceneSkinnedVertex] {
        guard !skins.isEmpty else { return [] }
        var out: [SceneSkinnedVertex] = []
        func visit(_ node: SceneNode) {
            defer { for child in node.children { visit(child) } }
            guard node.skinIndex == 0, let mesh = node.mesh else { return }
            let n = mesh.positions.count
            guard node.vertexJoints.count == n, node.vertexWeights.count == n else { return }
            out.reserveCapacity(out.count + n)
            for i in 0..<n {
                out.append(SceneSkinnedVertex(position: mesh.positions[i],
                                              joints: node.vertexJoints[i],
                                              weights: node.vertexWeights[i]))
            }
        }
        for node in nodes { visit(node) }
        return out
    }

    /// Pose the tree by writing world transforms onto nodes, keyed by file
    /// identity: the inverse of reading `nodeWorldTransforms()`. Each named
    /// node's local transform becomes `inverse(parent world) * world`, walking
    /// top-down so a joint written here is what its children are placed
    /// against. Nodes not named keep their local transform and ride their
    /// parent, which is what makes a partial skeleton (a ragdoll that skips the
    /// fingers) carry the rest of the figure rigidly.
    ///
    /// The scale a node carries is preserved: only its rotation and translation
    /// are replaced, since a rigid-body pose has no scale of its own and
    /// dividing it out would shrink the mesh.
    package mutating func setJointWorlds(_ worlds: [Int: simd_float4x4]) {
        guard !worlds.isEmpty else { return }
        func visit(_ node: inout SceneNode, parent: simd_float4x4) {
            var world = parent * node.localTransform
            if let source = node.sourceIndex, let posed = worlds[source] {
                world = Scene.keepingScale(of: world, pose: posed)
                node.localTransform = parent.inverse * world
                // A node the file gave TRS components carries the base an
                // animation swaps sampled channels into, so it is re-synced to
                // the posed transform (the `position` setter's rule). Without
                // that, a rotation-only track applied next frame would drag the
                // node back to its authored translation.
                if node.trs != nil { node.trs = Scene.components(of: node.localTransform) }
            }
            for i in node.children.indices { visit(&node.children[i], parent: world) }
        }
        for i in nodes.indices { visit(&nodes[i], parent: matrix_identity_float4x4) }
    }

    /// `pose`'s rotation and translation wearing `current`'s scale: the columns
    /// of `pose` rescaled by the lengths `current`'s carry.
    static func keepingScale(of current: simd_float4x4,
                             pose: simd_float4x4) -> simd_float4x4 {
        var out = pose
        for column in 0..<3 {
            let scale = simd_length(SIMD3<Float>(current[column].x, current[column].y,
                                                 current[column].z))
            guard scale.isFinite, scale > 0, abs(scale - 1) > 1e-6 else { continue }
            out[column] *= scale
        }
        return out
    }

    /// A local transform split into the translation/rotation/scale components
    /// an animation base is stored as. Used only to re-sync a base a pose just
    /// overwrote, never to invent one for a matrix-authored node.
    static func components(of m: simd_float4x4)
        -> (t: SIMD3<Float>, r: SIMD4<Float>, s: SIMD3<Float>) {
        var basis = m
        var scale = SIMD3<Float>(1, 1, 1)
        for column in 0..<3 {
            let axis = SIMD3<Float>(m[column].x, m[column].y, m[column].z)
            let length = simd_length(axis)
            scale[column] = length > 0 ? length : 1
            basis[column] = SIMD4<Float>(axis / scale[column], 0)
        }
        basis.columns.3 = SIMD4<Float>(0, 0, 0, 1)
        let q = simd_quatf(basis)
        return (t: SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z),
                r: SIMD4<Float>(q.vector.x, q.vector.y, q.vector.z, q.vector.w),
                s: scale)
    }
}
