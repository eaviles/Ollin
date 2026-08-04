import Foundation
import simd
#if canImport(ModelIO)
import ModelIO
#endif

// The USD leg of structure-preserving scene import: `Scene(contentsOf:)` routes
// the USD family (`.usdz`/`.usdc`/`.usda`/`.usd`) here, walking Model I/O's
// object hierarchy into the same `SceneNode` tree the glTF reader builds, so
// `drawScene`, the name subscript, and the camera resolution all apply with no
// new rules. What the importer exposes bounds what a `Scene` can keep:
//
// - Nodes arrive with their names, local transforms (translate/rotate/scale
//   ops and authored matrices, composed), and node-local meshes, children
//   alphabetized rather than in authored order.
// - Cameras arrive as typed camera objects (vertical field of view in degrees;
//   an orthographic aperture in tenths of a world unit).
// - Lights do *not* survive the importer (light prims come back as bare
//   grouping nodes with even their transforms dropped), and neither do
//   animation or skinning, so all three fill from Ollin's own parser
//   instead: one raw-tree read resolves the UsdLux prims onto `lights`
//   (`SceneLoaderUSDLights.swift`), the authored xformOp timeSamples onto
//   `animations` (`SceneLoaderUSDAnimation.swift`), and the UsdSkel tier
//   (skeletons, skin bindings, blend shapes, SkelAnimation channels) onto
//   the deforming node data `drawScene` poses
//   (`SceneLoaderUSDSkinning.swift`, which also rebuilds each deforming
//   mesh from its authored points, since per-point skin data has nothing
//   stable to align with in the importer's vertex layout).

#if canImport(ModelIO)
extension Scene {

    /// Read a USD file's default layer with structure kept: the node tree (names,
    /// local transforms, per-node meshes in node-local space) plus the authored
    /// cameras resolved through their node's world transform, exactly the glTF
    /// treatment, and the authored UsdLux lights and transform animation read
    /// by Ollin's own parser (see above). Returns `nil` when the file can't be
    /// read or holds no objects at all.
    static func loadModelIOScene(_ url: URL) -> Scene? {
        let asset = MDLAsset(url: url)
        guard asset.count > 0 else { return nil }

        var roots: [SceneNode] = []
        for i in 0..<asset.count where !(asset.object(at: i) is MDLSkeleton) {
            roots.append(buildNode(asset.object(at: i)))
        }
        var scene = Scene(nodes: roots)

        // Cameras: walk again composing world transforms, collecting each in
        // traversal order (the glTF resolution order).
        var cameraRefs: [(camera: MDLCamera, world: simd_float4x4)] = []
        func visit(_ obj: MDLObject, parent: simd_float4x4) {
            let world = parent * localMatrix(of: obj)
            if let cam = obj as? MDLCamera { cameraRefs.append((cam, world)) }
            for child in obj.children.objects { visit(child, parent: world) }
        }
        for i in 0..<asset.count { visit(asset.object(at: i), parent: matrix_identity_float4x4) }

        let center = scene.nodes.isEmpty ? nil : scene.bounds
        let sceneCenter = center.map { ($0.min + $0.max) * 0.5 }
        scene.cameras = cameraRefs.map { resolveCamera($0.camera, world: $0.world,
                                                       sceneCenter: sceneCenter) }

        // One raw-tree read serves what the importer drops: lights, the
        // authored transform animation (whose tracks bind by node name; each
        // animated prim's rest pose becomes the node's TRS base), and the
        // UsdSkel tier. Rest poses install before the skinning pass appends
        // its skeleton subtrees, so a name-bound install can only land on a
        // tree node; the merged tracks form the stage's one animation.
        if let stage = try? USDStage.load(contentsOf: url) {
            scene.lights = resolveUSDLights(stage)
            let baked = resolveUSDAnimation(stage)
            if let baked {
                for (name, pose) in baked.restPoses {
                    installRestPose(name, pose, in: &scene.nodes)
                }
            }
            let skel = resolveUSDSkinning(stage, into: &scene)
            var tracks = baked?.animation.tracks ?? []
            tracks += skel.tracks
            let duration = Swift.max(baked?.animation.duration ?? 0, skel.duration)
            if !tracks.isEmpty {
                scene.animations = [SceneAnimation(name: "", duration: duration, tracks: tracks)]
            }
        }
        return scene
    }

    /// One Model I/O object as a `SceneNode`: name, local transform, a node-local
    /// `Mesh` when the object carries triangles, children recursed. A light or
    /// other untranslated prim becomes a bare named grouping node. Skeleton
    /// objects are skipped: the skinning pass synthesizes the real joint
    /// subtree from the raw tree, and a bare stand-in would shadow its name.
    private static func buildNode(_ obj: MDLObject) -> SceneNode {
        var mesh: Mesh?
        if let mdl = obj as? MDLMesh, let data = Mesh.readMDLMesh(mdl), !data.positions.isEmpty,
           !data.indices.isEmpty {
            mesh = Mesh(positions: data.positions, normals: data.normals, indices: data.indices,
                        uvs: data.uvs ?? [], material: data.material)
        }
        let children = obj.children.objects.filter { !($0 is MDLSkeleton) }.map(buildNode)
        return SceneNode(name: obj.name, mesh: mesh, children: children,
                         localTransform: localMatrix(of: obj))
    }

    private static func localMatrix(of obj: MDLObject) -> simd_float4x4 {
        obj.transform?.matrix ?? matrix_identity_float4x4
    }

    /// A `Camera3D` from a Model I/O camera and its node's world transform,
    /// through the shared pose resolution (the -z aiming convention). The
    /// importer's field of view is the vertical angle in degrees; a USD
    /// orthographic aperture is spelled in tenths of a world unit, so the
    /// frustum height is the vertical aperture over ten.
    private static func resolveCamera(_ cam: MDLCamera, world: simd_float4x4,
                                      sceneCenter: Vector3?) -> Camera3D {
        let projection: Camera3D.Projection
        var near = Double(cam.nearVisibilityDistance)
        let far = Double(cam.farVisibilityDistance)
        if cam.projection == .orthographic {
            projection = .orthographic(height: Double(cam.sensorVerticalAperture) / 10)
        } else {
            let fov = Double(cam.fieldOfView) * .pi / 180
            projection = .perspective(fieldOfView: min(max(fov, 0.01), .pi - 0.01))
            near = max(near, 1e-4)
        }
        return resolveCamera(projection: projection, near: near, far: far,
                             world: world, sceneCenter: sceneCenter)
    }
}
#endif
