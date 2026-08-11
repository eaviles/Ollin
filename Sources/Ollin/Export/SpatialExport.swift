import Foundation
import simd

// Spatial export: one frame of a 3D sketch as a model you can hold up rather
// than a picture of one.
//
// The shape follows the vector exporters. Those drive the sketch headlessly and
// record the frame's 2D draw calls as paths; this drives it the same way and
// records the frame's *3D* draw calls, one node per `drawMesh`, into an
// ordinary `Scene`. That is the whole trick: the recorder's output is the same
// `Scene` a sketch could have loaded from a file, so there is one writer
// (`Scene.write(to:)`) rather than a second path that could drift from it.
//
// What a frame's 3D content is made of decides what travels. Meshes are
// surfaces and go out whole. A point cloud, a GPU particle system, and a
// raymarched field are not surfaces at all, so they say so once and stay
// behind; `isosurface`/`particleSurface` are the way to turn the last two into
// something a file can hold.

/// Collects a frame's 3D draw calls as scene nodes.
///
/// One record per `drawMesh`, keeping the mesh in its own space beside the
/// model matrix that placed it, so the exported node tree carries the same
/// transforms the frame drew with rather than a pile of baked geometry.
final class SpatialRecorder {

    private var nodes: [SceneNode] = []
    private var skipped: [String] = []
    private var notes: [String] = []

    /// Record one mesh draw: the geometry, where it was placed, and the surface
    /// it was wearing.
    func record(mesh: Mesh, transform: simd_float4x4, surface: Color, finish: Material,
                wireframe: Bool, matcap: Bool) {
        guard !mesh.isEmpty else { return }
        if wireframe { note("a wireframe exported as its solid surface: a file holds geometry, not a way of drawing it.") }
        if matcap { note("a matcap exported as a plain colored surface: the look is a texture on the view, which a file has nowhere to put.") }

        var exported = mesh
        var material = Self.previewSurface(finish, surface: surface,
                                           base: mesh.material, notes: &notes)

        // A triplanar projection is a way of drawing (three world-axis
        // projections blended by the normal), and neither file format has a
        // slot for one: the maps it projected stay behind, said plainly, and
        // the surface exports in its own color.
        if (mesh.material?.triplanarScale ?? 0) > 0 {
            if material.texture != nil || material.normalTexture != nil {
                note("a triplanar projection stayed behind: a file's material maps through uvs, which this surface has none of; it exported in its plain color.")
            }
            material.texture = nil
            material.normalTexture = nil
        }

        // Detail maps are a drawing-time refinement too (a finer pair tiled
        // over the base at its own scale), and neither format has a slot for
        // a second tiled texture set.
        if mesh.material?.detailTexture != nil || mesh.material?.detailNormalTexture != nil {
            note("a detail-map pair stayed behind: neither file format has a slot for a second, tiled detail texture.")
            material.detailTexture = nil
            material.detailNormalTexture = nil
        }

        // The renderer multiplies the fill, the material's base color, and any
        // per-vertex color together. A preview surface has one diffuse slot, so
        // whichever of the last two is present carries the composed product and
        // the other steps aside. Surface maps sample through the uvs, so a mesh
        // without them keeps only the constant emissive factor.
        let hasVertexColors = mesh.colors.count == mesh.positions.count
        let uvsAligned = mesh.uvs.count == mesh.positions.count
        if !uvsAligned {
            material.normalTexture = nil
            material.metallicRoughnessTexture = nil
            material.occlusionTexture = nil
            material.emissiveTexture = nil
        }
        let textured = material.texture != nil && uvsAligned
        if textured {
            if hasVertexColors {
                note("a textured mesh's per-vertex colors stayed behind: a preview surface can tint a texture, but not per vertex.")
                exported.colors = []
            }
        } else {
            material.texture = nil
            if hasVertexColors {
                let tint = material.baseColor
                exported.colors = mesh.colors.map {
                    Color(red: $0.red * tint.red, green: $0.green * tint.green,
                          blue: $0.blue * tint.blue, alpha: $0.alpha * tint.alpha)
                }
                material.baseColor = .white
            }
        }
        exported.material = material

        var node = SceneNode(name: "mesh\(nodes.count)")
        node.mesh = exported
        node.localTransform = transform
        nodes.append(node)
    }

    /// Note that some 3D content of `kind` had no surface to write, once per
    /// kind however many times it was drawn.
    func skip(_ kind: String) {
        guard !skipped.contains(kind) else { return }
        skipped.append(kind)
        note("\(kind) stayed behind: a spatial file holds surfaces, and that isn't one.")
    }

    private func note(_ text: String) {
        guard !notes.contains(text) else { return }
        notes.append(text)
    }

    /// The recorded frame as a scene, with the camera and lights it was drawn
    /// under.
    func scene(camera: Camera3D?, lights: [Light], name: String) -> Scene {
        for note in notes { print("Ollin: \(note)") }
        return Scene(nodes: nodes, cameras: camera.map { [$0] } ?? [],
                     lights: lights, name: name)
    }

    /// Whether anything at all was recorded, so an export can say plainly that
    /// a frame had no 3D in it rather than writing an empty file.
    var isEmpty: Bool { nodes.isEmpty }

    // MARK: - The finish

    /// An Ollin surface finish as the parts a preview surface can hold.
    ///
    /// A physically-based finish maps across directly, since both describe a
    /// surface the same way. Every other shading model is a *look* rather than
    /// a description of a material, so what carries is its color and how shiny
    /// it is: the shininess exponent converts to perceptual roughness through
    /// the same curve the renderer's own area lights use, which keeps a
    /// polished surface polished and a matte one matte. What has no slot at all
    /// says so.
    static func previewSurface(_ finish: Material, surface: Color, base: MeshMaterial?,
                               notes: inout [String]) -> MeshMaterial {
        func note(_ text: String) {
            guard !notes.contains(text) else { return }
            notes.append(text)
        }

        let tint = base?.baseColor ?? .white
        let color = Color(red: surface.red * tint.red, green: surface.green * tint.green,
                          blue: surface.blue * tint.blue, alpha: surface.alpha * tint.alpha)

        var out = MeshMaterial(baseColor: color, texture: base?.texture)
        out.opacity = color.alpha

        // The surface maps ride through as drawn: the relief, the packed
        // metallic-roughness channels, the baked occlusion, the emissive map
        // and its factor (the caller strips the textures when the mesh has no
        // uvs to map them with).
        if let base {
            out.normalTexture = base.normalTexture
            out.normalScale = base.normalScale
            out.metallicRoughnessTexture = base.metallicRoughnessTexture
            out.occlusionTexture = base.occlusionTexture
            out.occlusionStrength = base.occlusionStrength
            out.emissiveTexture = base.emissiveTexture
            out.emissiveFactor = base.emissiveFactor
        }

        if finish.shading == .physicallyBased {
            out.metallic = finish.metallic
            out.roughness = finish.roughness
            // With a metallic-roughness map bound, what rendered per pixel is
            // finish × the mesh material's factors × the sampled channels, so
            // the written factors carry the composed product.
            if base?.metallicRoughnessTexture != nil {
                out.metallic = finish.metallic * (base?.metallic ?? 1)
                out.roughness = finish.roughness * (base?.roughness ?? 1)
            }
            out.ior = finish.ior
            out.clearcoat = finish.clearcoat
            out.clearcoatRoughness = finish.clearcoatRoughness
            // Glass is transmission in Ollin and transparency in the format,
            // which is the closest thing it has to say.
            if finish.transmission > 0 {
                out.opacity = color.alpha * (1 - finish.transmission)
            }
            if finish.sheen > 0 {
                note("a sheen stayed behind: the format's surface has no cloth lobe.")
            }
        } else {
            out.roughness = pow(2 / (max(finish.shininess, 0) + 2), 0.25)
            if finish.shading != .standard {
                note("a stylized finish exported as a plain surface: toon, gooch, and the rest are ways of shading, not materials a file can name.")
            }
        }

        if finish.iridescence > 0 || finish.sparkle > 0 || finish.rim > 0
            || finish.subsurface > 0 {
            note("part of a finish stayed behind (iridescence, sparkle, rim, or subsurface): the format's surface has no slot for those.")
        }
        return out
    }
}

// MARK: - Driving a frame

extension OllinApp {

    /// Drive `sketch` headlessly the way `image(of:)` does (`setup()`, then
    /// `draw()` advanced to `frame` at `fps`) and collect that frame's 3D draw
    /// calls as a `Scene`. Never touches Metal, so it runs anywhere and is
    /// deterministic.
    static func recordSpatialFrame(of sketch: Sketch, frame: Int, fps: Double) -> Scene {
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }
        let size = sketch.canvasSize
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.setup()
        let recorder = SpatialRecorder()
        for k in 0...max(0, frame) {                 // advance so frame N is correct
            sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
            sketch.drawer.spatialRecorder = (k == frame) ? recorder : nil
            sketch.performDraw()
        }
        sketch.drawer.spatialRecorder = nil
        if !sketch.drawer.placedDecals.isEmpty {
            recorder.skip("a projected decal")
        }
        if recorder.isEmpty {
            print("Ollin: frame \(frame) drew no 3D geometry, so the model is empty. Spatial export writes meshes (drawMesh, drawScene, and the solid primitives).")
        }
        return recorder.scene(camera: sketch.drawer.camera3D,
                              lights: sketch.drawer.activeLights,
                              name: String(describing: type(of: sketch)))
    }
}

public extension OllinApp {

    /// One frame of `sketch` as a spatial `Scene`: no window, no GPU.
    ///
    /// The 3D counterpart of `svg(of:)`. Each mesh the frame drew becomes a
    /// node carrying the transform that placed it, wearing the surface it was
    /// drawn with, under the frame's own camera and lights. Write it with
    /// `Scene.write(to:)`, or read it, edit it, and draw it back.
    static func spatialScene(of sketch: Sketch, frame: Int = 0, fps: Double = 60) -> Scene {
        recordSpatialFrame(of: sketch, frame: frame, fps: fps)
    }

    /// Render one frame of `sketch` and write it as a spatial model: a `.usdz`
    /// package by default, or a `.usda` layer if the path says so. No window,
    /// no GPU. The basis for the `--export-usdz` flag.
    ///
    /// A `.usdz` opens in Quick Look from the Finder or a message, stands on a
    /// real table through AR, and drops into a visionOS app, so this is how a
    /// 3D sketch leaves as something three-dimensional rather than a picture of
    /// itself.
    ///
    /// `metersPerUnit` says how big one scene unit is (see
    /// `Scene.data(as:metersPerUnit:)`); the default of 1 reads scene units as
    /// meters.
    static func exportSpatial(_ sketch: Sketch, to path: String, frame: Int = 0,
                              fps: Double = 60, metersPerUnit: Double = 1) {
        let scene = spatialScene(of: sketch, frame: frame, fps: fps)
        let url = URL(fileURLWithPath: path)
        let format = SceneFileFormat(fileExtension: url.pathExtension) ?? .usdz
        if scene.write(to: url, as: format, metersPerUnit: metersPerUnit) {
            print("Ollin: exported frame \(frame) → \(path) (\(format.fileExtension.uppercased()))")
        }
    }
}
