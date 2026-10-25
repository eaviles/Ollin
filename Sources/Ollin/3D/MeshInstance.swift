import Foundation
import simd

/// One placement of a mesh in an instanced draw (`drawMesh(_:instances:)`):
/// where a copy sits, how it turns, how it scales, and an optional per-copy
/// tint. The mesh's vertices upload once and the GPU places every copy, so a
/// field of thousands costs one draw call instead of thousands of CPU re-bakes.
///
/// The transform reads like the sketch calls it replaces: the copy is placed as
/// if you had written `translate(position)`, then `rotate(rotation)`, then
/// `scale`. The whole field still follows the surrounding 3D transform stack,
/// so `translate`/`rotate` before the draw move every copy together.
public struct MeshInstance: Sendable {

    /// Where this copy sits, in world units (applied first).
    public var position: Vector3
    /// How this copy turns: one `Rotation3D`, about any axis. `.aboutY(a)`
    /// spins a copy about y, `Rotation3D(from:to:)` points its up along a
    /// direction, a physics body's own `rotation` places it as the solver has
    /// it, and `.euler(x:y:z:)` is three angles composed the way `rotateX`,
    /// `rotateY`, `rotateZ` would be, in that order.
    public var rotation: Rotation3D
    /// How this copy scales, per axis (applied last). `Vector3(1, 1, 1)` keeps
    /// the mesh's own size.
    public var scale: Vector3
    /// A per-copy tint multiplied onto the surface color (the current `fill`
    /// times the mesh material's base color), or `nil` to leave it unchanged.
    /// Nothing clamps it, so a component past 1 draws the copy brighter than
    /// its surface color.
    public var color: Color?

    /// A placement from position, rotation, per-axis scale, and tint.
    public init(position: Vector3 = .zero, rotation: Rotation3D = .identity,
                scale: Vector3 = Vector3(1, 1, 1), color: Color? = nil) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.color = color
    }

    /// A placement with one uniform scale factor on all three axes.
    public init(position: Vector3 = .zero, rotation: Rotation3D = .identity,
                scale: Double, color: Color? = nil) {
        self.init(position: position, rotation: rotation,
                  scale: Vector3(scale, scale, scale), color: color)
    }

    /// The local -> world matrix this placement composes to: T · R · S, the
    /// turn built through the same axis-angle helper `rotate(_:)` uses, so the
    /// matrix matches the equivalent `translate`/`rotate`/`scale` call
    /// sequence exactly.
    var matrix: simd_float4x4 {
        var m = Drawer.translation3(position.simd3)
        if rotation != .identity {
            let axis = rotation.axis.normalized
            if axis.lengthSquared > 0 {
                m = m * Drawer.rotation3(Float(rotation.angle), axis: axis.simd3)
            }
        }
        if scale != Vector3(1, 1, 1) {
            m = m * Drawer.scaling3(Float(scale.x), Float(scale.y), Float(scale.z))
        }
        return m
    }
}
