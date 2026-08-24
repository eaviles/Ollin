import simd

/// One node's authored local transform, split into the moves a sketch writes by
/// hand: a translation, one rotation about an axis, and a per-axis scale.
///
/// This exists for the project generator, which turns a loaded scene into source
/// a person can edit. Drawing never needs it: `drawScene` composes the authored
/// matrix untouched, which is why `localTransform` is kept verbatim in the first
/// place. Package access, like the other seams a sibling target reads.
package struct ScenePlacement: Sendable, Equatable {
    package var translation: Vector3
    /// The rotation in radians, about `axis`. Zero means the node carries none,
    /// and `axis` is then the y axis so a printed call still reads sensibly.
    package var angle: Double
    package var axis: Vector3
    package var scale: Vector3

    /// Whether translate, rotate and scale reproduce the authored matrix.
    ///
    /// A shear or a projective row does not reduce to the three, so a caller
    /// that prints them would be writing something quietly wrong. False is the
    /// signal to say so rather than to guess.
    package var isExact: Bool

    /// Whether the three moves are all identity, so nothing needs printing.
    package var isIdentity: Bool {
        translation == .zero && angle == 0 && scale == Vector3(1, 1, 1)
    }
}

/// What a scene carries that placing its meshes by hand cannot reproduce.
///
/// The project generator reads this so it can say what it left behind. Every
/// count is of nodes, and a zero means the file asked for nothing of the kind.
package struct SceneImportLosses: Sendable, Equatable {
    /// Nodes a skin poses. Placed by hand, such a mesh draws in its bind pose.
    package var skinnedNodes = 0
    /// Nodes carrying morph targets, whose weights nothing will drive.
    package var morphedNodes = 0
    /// Nodes whose mesh wears more than one material. Drawn whole, it wears the
    /// first one.
    package var multiMaterialNodes = 0
    /// Keyframe tracks the file authored.
    package var animations = 0
}

extension Scene {

    /// A walk of the tree counting what will not survive being written out as
    /// placement calls.
    package var importLosses: SceneImportLosses {
        var losses = SceneImportLosses(animations: animations.count)
        func visit(_ nodes: [SceneNode]) {
            for node in nodes {
                if node.skinIndex != nil { losses.skinnedNodes += 1 }
                if !node.morphTargets.isEmpty { losses.morphedNodes += 1 }
                if node.meshParts.count > 1 { losses.multiMaterialNodes += 1 }
                visit(node.children)
            }
        }
        visit(nodes)
        return losses
    }
}

extension SceneNode {

    /// Whether the file gives this node's mesh more than one material. Drawn
    /// whole with `drawMesh`, such a mesh wears the first, so a caller placing
    /// parts by hand has to say so.
    public var wearsSeveralMaterials: Bool { meshParts.count > 1 }

    /// Whether this node's authored transform splits cleanly into translate,
    /// rotate, and scale. A transform carrying a shear does not; `drawScene`
    /// still draws it exactly (the matrix is kept verbatim), but anything
    /// re-expressing the node as separate moves works from an approximation,
    /// and a viewer inspecting the file should say so.
    public var placementIsExact: Bool { placement.isExact }

    /// This node's local transform as translate, rotate and scale.
    ///
    /// Rotation comes back as one angle about one axis, which is the form
    /// `rotate(_:axis:)` takes. The decomposition itself is `Scene.decomposeTRS`,
    /// the same one the USD animation bake and the skinning leg use, so a node
    /// splits the same way whoever asks.
    package var placement: ScenePlacement {
        let f = localTransform
        let m = simd_double4x4(columns: (SIMD4<Double>(f.columns.0), SIMD4<Double>(f.columns.1),
                                        SIMD4<Double>(f.columns.2), SIMD4<Double>(f.columns.3)))
        let rest = Scene.decomposeTRS(m)

        let translation = Vector3(Double(rest.t.x), Double(rest.t.y), Double(rest.t.z))
        let scale = Vector3(Double(rest.s.x), Double(rest.s.y), Double(rest.s.z))

        // The quaternion as an angle about an axis. A rotation of nothing has no
        // axis to report, so it takes y and an angle of zero.
        let q = simd_quatd(ix: Double(rest.r.x), iy: Double(rest.r.y),
                           iz: Double(rest.r.z), r: Double(rest.r.w)).normalized
        var angle = 2 * acos(min(1, max(-1, q.real)))
        let sine = (1 - q.real * q.real).squareRoot()
        var axis = Vector3(0, 1, 0)
        if sine > 1e-9, angle > 1e-9 {
            axis = Vector3(q.imag.x / sine, q.imag.y / sine, q.imag.z / sine)
        } else {
            angle = 0
        }

        var placement = ScenePlacement(translation: translation, angle: angle,
                                       axis: axis, scale: scale, isExact: true)
        placement.isExact = reproduces(m, placement)
        return placement
    }

    /// Whether the split, composed back in the order a sketch would call it,
    /// lands on the matrix it came from. Measured against the size of the
    /// matrix itself, so a scene in meters and one in millimetres get the
    /// same answer.
    private func reproduces(_ m: simd_double4x4, _ p: ScenePlacement) -> Bool {
        var rebuilt = matrix_identity_double4x4
        rebuilt.columns.3 = SIMD4<Double>(p.translation.x, p.translation.y, p.translation.z, 1)
        if p.angle != 0 {
            let q = simd_quatd(angle: p.angle, axis: simd_normalize(SIMD3(p.axis.x, p.axis.y, p.axis.z)))
            rebuilt = rebuilt * simd_double4x4(q)
        }
        rebuilt = rebuilt * simd_double4x4(diagonal: SIMD4(p.scale.x, p.scale.y, p.scale.z, 1))

        var largest = 0.0
        for column in 0..<4 {
            for row in 0..<4 { largest = Swift.max(largest, abs(m[column][row])) }
        }
        let tolerance = Swift.max(1e-4, largest * 1e-4)
        for column in 0..<4 {
            for row in 0..<4 where abs(m[column][row] - rebuilt[column][row]) > tolerance {
                return false
            }
        }
        return true
    }
}
