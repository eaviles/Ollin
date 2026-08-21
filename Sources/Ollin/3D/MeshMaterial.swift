import Foundation

/// What a texture does past its own edges, when a mesh's uvs run outside the
/// 0…1 square.
///
/// A uv of 2.5 asks for a point two and a half tiles across an image that is one
/// tile wide, and every renderer needs an answer. `clamp` holds the edge pixel,
/// which is the safe answer for a picture mapped once onto a shape (a globe, a
/// portrait on a plane): the picture never repeats, and its border smears out
/// instead. `tile` repeats the image, which is what a floor, a wall, or a strip
/// of fabric wants, and what a model authored with tiling uvs was drawn against.
/// `mirror` repeats it flipped each time, so the tiles meet edge to edge with no
/// seam even when the image was not made to tile.
///
/// ```swift
/// var floor = Mesh.plane(width: 800, depth: 800)
/// floor.uvs = floor.uvs.map { $0 * 8 }             // eight tiles across
/// floor.material = MeshMaterial(texture: tile, wrap: .tile)
/// ```
///
/// A loaded model brings its file's own answer (see `loadMesh`), so a tiling
/// floor arrives tiling.
public enum TextureWrap: String, Sendable, Hashable, CaseIterable {
    /// The edge pixel holds past the edge. The default, and right for a picture
    /// mapped once onto a shape.
    case clamp
    /// The image repeats.
    case tile
    /// The image repeats, flipped every other tile, so neighbors always meet.
    case mirror
}

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
/// Color textures are **opaque base-color** ones. A `normalTexture` adds
/// per-pixel surface relief: a tangent-space normal map (the standard
/// red-green-blue direction encoding, sampled as raw data rather than color)
/// that bends the lighting normal so a flat triangle shades like a detailed
/// surface. It needs the mesh to carry `tangents` beside its `uvs`
/// (`Mesh.normalMapped(_:scale:)` and the model loaders set both up).
///
/// The rest of the standard surface-map set rides alongside: a
/// `metallicRoughnessTexture` varies the physically-based finish per pixel
/// (the sampled channels *multiply* `material(_:)`'s metallic/roughness and
/// the factors below, so `material(.physicallyBased(metallic: 1, roughness: 1))`
/// shows a model's maps as authored), an `occlusionTexture` dims the ambient
/// and environment light in crevices, and an `emissiveTexture` /
/// `emissiveFactor` make the surface add light of its own. All map through the
/// mesh's `uvs`. A detail pair (`detailTexture` / `detailNormalTexture`)
/// tiles a much finer second texture across the base one, so a surface keeps
/// texture when the camera gets close; see
/// `Mesh.detailMapped(_:normal:scale:strength:)`. The finish *values* below
/// (how metallic, how rough, how clear) are otherwise carried for export
/// rather than drawn, since Ollin shades a mesh through `material(_:)`; with
/// a metallic-roughness map bound, `metallic`/`roughness` act as that map's
/// factors, the standard convention.
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
    /// What every one of this material's textures does past its own edges, for
    /// uvs outside the 0…1 square: `.clamp` (the default) holds the edge pixel,
    /// `.tile` repeats the image, `.mirror` repeats it flipped. One answer covers
    /// the whole map set, since a surface that tiles tiles all of its maps
    /// together. The triplanar projection and the detail pair repeat regardless,
    /// having no uv tile of their own to stay inside.
    public var wrap: TextureWrap
    /// A tangent-space normal map, sampled at each vertex's UV as raw data (no
    /// sRGB decode) and used to bend the lighting normal per pixel. `nil` means
    /// the geometry's own normals light the surface. Needs the mesh to carry
    /// `tangents` (see `Mesh.normalMapped(_:scale:)`); without them the map is
    /// skipped with a one-time note.
    public var normalTexture: Image?
    /// How strongly the normal map bends the surface: 1 as authored, smaller
    /// flattens the relief, larger exaggerates it, 0 turns the map off (the
    /// scale applies to the sampled tangent-space x/y before renormalizing,
    /// glTF's `normalTexture.scale` convention).
    public var normalScale: Double
    /// A metallic-roughness map in the standard packing: roughness in the
    /// green channel, metallic in the blue (occlusion often shares the red;
    /// point `occlusionTexture` at the same image). Sampled as raw data at
    /// each pixel and multiplied by the `metallic`/`roughness` factors below
    /// and the drawing-state finish. `nil` means the finish values apply
    /// uniformly.
    public var metallicRoughnessTexture: Image?
    /// An ambient-occlusion map (its red channel; 1 = open, 0 = fully
    /// occluded), dimming only the *indirect* light (the flat ambient, the
    /// environment, the probe bounce), never a light shining directly on the
    /// surface. `nil` means no baked occlusion.
    public var occlusionTexture: Image?
    /// How much of the occlusion map applies: 1 as authored (the default),
    /// down to 0 for none. The sampled value becomes `1 + strength·(ao − 1)`.
    public var occlusionStrength: Double
    /// An emissive map: color the surface adds as its own light, multiplied by
    /// `emissiveFactor`. Sampled as color (sRGB). `nil` means the factor alone
    /// emits (and a black factor, the default, emits nothing).
    public var emissiveTexture: Image?
    /// A height map (its red channel, sampled as raw data): white is the
    /// surface itself, darker carves relief in below it. The renderer reads it
    /// as parallax occlusion, per-pixel depth that shifts what every other map
    /// shows so a flat triangle reads as carved; `Mesh.displaced(by:scale:)`
    /// reads the same image as real geometry. Needs the mesh to carry
    /// `tangents` beside its `uvs` (see `Mesh.parallaxMapped(_:scale:)`).
    /// `nil` means a flat surface.
    public var heightTexture: Image?
    /// How deep the height map's relief runs, as a fraction of the texture
    /// tile (0.05 = the deepest point sits 5% of the tile below the surface).
    /// 0 turns the map off.
    public var heightScale: Double
    /// The size of one texture tile in world units when the mesh has no `uvs`
    /// to map through: > 0 projects the base `texture` (and `normalTexture`,
    /// if set) flat along each of the three world axes, blended by the surface
    /// normal, so a marched or grown surface with no uv layout can wear a
    /// picture. 0 (the default) maps through `uvs` as usual. Set with
    /// `Mesh.triplanarTextured(_:normal:scale:)`; the other surface maps stay
    /// uv-mapped.
    public var triplanarScale: Double
    /// The emissive tint and strength: black (the default) emits nothing;
    /// with an `emissiveTexture` it scales the map, without one it emits as a
    /// constant color.
    public var emissiveFactor: Color
    /// A detail color map: a second, much finer texture tiled `detailScale`
    /// times across each base tile, multiplying the base color so a surface
    /// keeps texture when the camera gets close. Sampled as raw data with
    /// 128 gray the neutral (the sample × 2 multiplies, so darker values
    /// darken and lighter ones lighten). `nil` means no color detail. Set
    /// with `Mesh.detailMapped(_:normal:scale:strength:)`.
    public var detailTexture: Image?
    /// A detail normal map, tiled like `detailTexture` and reoriented onto
    /// the base normal (the map's relief rides whatever the base `normalTexture`
    /// already shapes), for fine surface grain. Sampled as raw data. Needs the
    /// mesh to carry `tangents` beside its `uvs`. `nil` means no normal detail.
    public var detailNormalTexture: Image?
    /// How many times the detail maps tile across one base uv tile (8 = the
    /// detail repeats 8 × 8 per base tile). Applies to both detail maps.
    public var detailScale: Double
    /// How strongly the detail pair applies: 1 as authored, smaller fades the
    /// detail out, 0 turns it off (the frame is then byte-identical to one
    /// with no detail maps at all).
    public var detailStrength: Double

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
                wrap: TextureWrap = .clamp,
                normalTexture: Image? = nil, normalScale: Double = 1,
                metallicRoughnessTexture: Image? = nil,
                occlusionTexture: Image? = nil, occlusionStrength: Double = 1,
                emissiveTexture: Image? = nil, emissiveFactor: Color = .black,
                heightTexture: Image? = nil, heightScale: Double = 0.05,
                triplanarScale: Double = 0,
                detailTexture: Image? = nil, detailNormalTexture: Image? = nil,
                detailScale: Double = 8, detailStrength: Double = 1,
                metallic: Double = 0, roughness: Double = 0.5, opacity: Double = 1,
                ior: Double = 1.5, clearcoat: Double = 0, clearcoatRoughness: Double = 0.01) {
        self.baseColor = baseColor
        self.texture = texture
        self.wrap = wrap
        self.normalTexture = normalTexture
        self.normalScale = normalScale
        self.metallicRoughnessTexture = metallicRoughnessTexture
        self.occlusionTexture = occlusionTexture
        self.occlusionStrength = occlusionStrength
        self.emissiveTexture = emissiveTexture
        self.emissiveFactor = emissiveFactor
        self.heightTexture = heightTexture
        self.heightScale = heightScale
        self.triplanarScale = triplanarScale
        self.detailTexture = detailTexture
        self.detailNormalTexture = detailNormalTexture
        self.detailScale = detailScale
        self.detailStrength = detailStrength
        self.metallic = metallic
        self.roughness = roughness
        self.opacity = opacity
        self.ior = ior
        self.clearcoat = clearcoat
        self.clearcoatRoughness = clearcoatRoughness
    }
}

extension TextureWrap {
    /// The address mode as the material uniform carries it: 0 clamp, 1 repeat,
    /// 2 mirrored repeat. The fragment picks a `constexpr sampler` by this
    /// number, so clamp being 0 is what keeps an unstated material's bytes and
    /// its picture unchanged.
    var gpuValue: Float {
        switch self {
        case .clamp: 0
        case .tile: 1
        case .mirror: 2
        }
    }
}
