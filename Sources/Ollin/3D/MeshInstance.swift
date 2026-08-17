import Foundation
import simd

/// One placement of a mesh in an instanced draw (`drawMesh(_:instances:)`):
/// where a copy sits, how it turns, how it scales, and an optional per-copy
/// tint. The mesh's vertices upload once and the GPU places every copy, so a
/// field of thousands costs one draw call instead of thousands of CPU re-bakes.
///
/// The transform reads like the sketch calls it replaces: the copy is placed as
/// if you had written `translate(position)`, then `rotateX/rotateY/rotateZ` (in
/// that order), then `scale`. The whole field still rides the surrounding 3D
/// transform stack, so `translate`/`rotate` before the draw move every copy
/// together.
public struct MeshInstance: Sendable {

    /// Where this copy sits, in world units (applied first).
    public var position: Vector3
    /// How this copy turns: Euler angles in radians, applied about the x-axis,
    /// then the y-axis, then the z-axis (the `rotateX`/`rotateY`/`rotateZ` order).
    public var rotation: Vector3
    /// How this copy scales, per axis (applied last). `Vector3(1, 1, 1)` keeps
    /// the mesh's own size.
    public var scale: Vector3
    /// A per-copy tint multiplied onto the surface color (the current `fill`
    /// times the mesh material's base color), or `nil` to leave it unchanged.
    public var color: Color?

    /// A placement from position, Euler rotation, per-axis scale, and tint.
    public init(position: Vector3 = .zero, rotation: Vector3 = .zero,
                scale: Vector3 = Vector3(1, 1, 1), color: Color? = nil) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.color = color
    }

    /// A placement with one uniform scale factor on all three axes.
    public init(position: Vector3 = .zero, rotation: Vector3 = .zero,
                scale: Double, color: Color? = nil) {
        self.init(position: position, rotation: rotation,
                  scale: Vector3(scale, scale, scale), color: color)
    }

    /// The local -> world matrix this placement composes to: T · Rx · Ry · Rz · S,
    /// matching the equivalent `translate`/`rotateX`/`rotateY`/`rotateZ`/`scale`
    /// call sequence exactly.
    var matrix: simd_float4x4 {
        var m = Drawer.translation3(position.simd3)
        if rotation.x != 0 { m = m * Drawer.rotationX(Float(rotation.x)) }
        if rotation.y != 0 { m = m * Drawer.rotationY(Float(rotation.y)) }
        if rotation.z != 0 { m = m * Drawer.rotationZ(Float(rotation.z)) }
        if scale != Vector3(1, 1, 1) {
            m = m * Drawer.scaling3(Float(scale.x), Float(scale.y), Float(scale.z))
        }
        return m
    }
}
