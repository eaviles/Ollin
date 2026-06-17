import Foundation

/// The surface look of a `Mesh` beyond its raw geometry: a base color and an
/// optional texture image, mapped onto the mesh through its `uvs`.
///
/// A mesh draws in its `fill` color by default; a material *tints* that — the
/// `baseColor` multiplies the fill, and a `texture` (sampled at each vertex's UV)
/// multiplies it further. So a white-`fill`, white-`baseColor` textured mesh shows
/// the texture as-is, and `baseColor` or `fill` color it. The texture needs the
/// mesh to carry matching `uvs` (one per vertex); without them the mesh falls back
/// to a flat `baseColor × fill` surface — a texture can't map with nothing to map
/// against. Set one with `Mesh.textured(_:)`, or read it from a model file
/// (`loadMesh`). It rides the Blinn-Phong light model like any mesh surface.
///
/// ```swift
/// let globe = Mesh.sphere(radius: 200).textured(earthImage)
/// drawMesh(globe)
/// ```
///
/// The milestone contract is **opaque base-color textures**; metallic/roughness,
/// normal, and emissive maps are the later PBR tier.
public struct MeshMaterial: @unchecked Sendable {
    // `@unchecked Sendable`: the only stored reference is an `Image`, which a
    // material uses read-only for texturing (handed to the renderer's
    // `texture(for:)` like every drawn image). Treating it as shared-immutable
    // keeps `Mesh` `Sendable` without making `Image` globally `Sendable` — the
    // same way loaded textures are already shared across the analysis/render seams.

    /// The base (diffuse) color, multiplied onto the mesh's `fill`. White (the
    /// default) leaves the fill and any texture unchanged.
    public var baseColor: Color
    /// The diffuse texture, sampled at each vertex's UV and multiplied onto
    /// `baseColor × fill`. `nil` means a flat (untextured) surface.
    public var texture: Image?

    public init(baseColor: Color = .white, texture: Image? = nil) {
        self.baseColor = baseColor
        self.texture = texture
    }
}
