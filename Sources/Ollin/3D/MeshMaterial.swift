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
/// Textures are **opaque base-color** ones; normal, emissive, and
/// metallic/roughness *maps* are a later tier. The finish values below (how
/// metallic, how rough, how clear) are carried for export rather than drawn,
/// since Ollin shades a mesh through `material(_:)`.
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

    // The finish below is carried, not rendered. Ollin shades a mesh through
    // `material(_:)`, which is drawing state rather than something the mesh
    // owns, so these describe the surface for a *file*: they are what the
    // spatial exporter writes and what a reader could hand back. Each one is a
    // value USD's preview surface has a slot for, and the defaults are that
    // spec's own, so a material saying nothing about its finish exports as the
    // plain neutral surface.
    /// How metallic the surface is, 0 for a dielectric and 1 for bare metal.
    public var metallic: Double
    /// How rough the surface is, 0 for a mirror and 1 for fully diffuse.
    public var roughness: Double
    /// How opaque the surface is, 1 for solid.
    public var opacity: Double
    /// The index of refraction, 1.5 being ordinary glass.
    public var ior: Double
    /// A clear lacquer over the surface, 0 for none.
    public var clearcoat: Double
    /// How rough that coat is.
    public var clearcoatRoughness: Double

    public init(baseColor: Color = .white, texture: Image? = nil,
                metallic: Double = 0, roughness: Double = 0.5, opacity: Double = 1,
                ior: Double = 1.5, clearcoat: Double = 0, clearcoatRoughness: Double = 0.01) {
        self.baseColor = baseColor
        self.texture = texture
        self.metallic = metallic
        self.roughness = roughness
        self.opacity = opacity
        self.ior = ior
        self.clearcoat = clearcoat
        self.clearcoatRoughness = clearcoatRoughness
    }
}
