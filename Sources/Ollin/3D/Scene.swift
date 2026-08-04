import Foundation
import simd

/// A 3D scene loaded from a file with its *structure* kept: a tree of named nodes,
/// each with its authored transform and an optional `Mesh`, plus the cameras,
/// lights, and animations the scene was authored with (play one with
/// `apply(_:at:)`). The complement of `loadMesh`, which merges
/// everything to one mesh; `loadScene` keeps the graph so a sketch can draw the
/// whole arrangement in place (`drawScene`), open on the authored view
/// (`camera(scene.camera!)`, `light(...)` each of `scene.lights`), and reach one
/// node by name to drive it from `draw()`:
///
/// ```swift
/// var scene: Scene!
/// override func setup() { scene = loadScene("Stage.gltf")! }
/// override func draw() {
///     camera(scene.camera ?? .orbiting(radius: 6))
///     for l in scene.lights { light(l) }
///     scene["sculpture"]?.rotate(0.01, axis: .unitY)
///     drawScene(scene)
/// }
/// ```
///
/// Everything decomposes into the existing core types: `camera` is a `Camera3D`
/// for `camera(_:)`, `lights` are `Light`s for `light(_:)`, and each node's `mesh`
/// is an ordinary `Mesh` (in the node's local space) that also draws standalone.
/// Structure comes from glTF/GLB files (the node graph, cameras from the core
/// spec, lights from the punctual-lights extension, animations, skins) and from
/// the USD family (`.usdz`/`.usdc`/`.usda`/`.usd`: the node graph, cameras, the
/// authored UsdLux lights, sphere/distant/shaped-cone/rect/disk/cylinder, the
/// authored transform animation, timeSamples baked into keyframe tracks, and
/// the UsdSkel deforming tier, skeletons/skins/blend shapes with their
/// SkelAnimation channels, all read by Ollin's own parser); the remaining mesh
/// formats (`.obj`, `.stl`, …) have no scene graph to keep, so they load as a
/// single-node scene with no cameras or lights, exactly `loadMesh` in a wrapper.
public struct Scene: Sendable {

    /// The root nodes of the scene graph, in document order.
    public var nodes: [SceneNode]
    /// Every camera the file authored, resolved to world space in traversal
    /// order through the tree's *current* transforms, so a camera rides its
    /// node: move the node (by hand or by an applied animation) and the camera
    /// moves with it. Assigning this property replaces the authored cameras
    /// with your own fixed array, which no longer follows the nodes.
    /// glTF cameras carry no aspect ratio worth honoring here: the projection uses
    /// the sketch's canvas aspect, like every other `Camera3D`.
    public var cameras: [Camera3D] {
        get { fixedCameras ?? nodeCameras }
        set { fixedCameras = newValue }
    }
    /// Every light the file authored, resolved to world space in traversal
    /// order through the tree's *current* transforms, so a light rides its
    /// node: move the node (by hand or by an applied animation) and the light
    /// moves with it. Ollin's punctual lights have no distance falloff, so the
    /// file's physical intensities (lux, candela) can't carry over as-is:
    /// within each light kind they are scaled so the brightest is 1, keeping
    /// relative balance. Assigning this property (tweaking one light in place
    /// counts) replaces the authored lights with your own fixed array, which
    /// no longer follows the nodes.
    public var lights: [Light] {
        get { fixedLights ?? nodeLights }
        set { fixedLights = newValue }
    }
    /// Every animation the file authored, in document order: keyframe tracks that
    /// pose the nodes. Play one with `apply(_:at:)`, or find one by name with
    /// `animation(_:)`.
    public var animations: [SceneAnimation]
    /// The scene's authored name, when the file gave it one.
    public var name: String?
    /// The file's skins: joint hierarchies that pose skinned meshes. `drawScene`
    /// reads them; a node references one by index.
    var skins: [SceneSkin]
    /// Hand-set camera/light arrays (from the initializer or the property
    /// setters), overriding the node-resolved ones; `nil` follows the nodes.
    var fixedCameras: [Camera3D]?
    var fixedLights: [Light]?

    /// An empty scene, or one composed by hand from nodes you build yourself.
    public init(nodes: [SceneNode] = [], cameras: [Camera3D] = [],
                lights: [Light] = [], name: String? = nil) {
        self.nodes = nodes
        self.fixedCameras = cameras.isEmpty ? nil : cameras
        self.fixedLights = lights.isEmpty ? nil : lights
        self.animations = []
        self.name = name
        self.skins = []
    }

    /// The scene's main camera: the first one the file authored, or `nil` for a
    /// file with none (fall back to your own, `camera(scene.camera ?? .orbiting(...))`).
    public var camera: Camera3D? { cameras.first }

    /// The first node named `name`, searching the whole tree depth-first. Returns a
    /// *copy* (nodes are values); to mutate a node in place, use the subscript:
    /// `scene["lamp"]?.rotate(0.01, axis: .unitY)`.
    public func node(_ name: String) -> SceneNode? {
        Scene.find(name, in: nodes)
    }

    /// Get or mutate the first node named `name` (depth-first), in place:
    /// `scene["propeller"]?.rotate(0.1, axis: .unitZ)` spins it about its own
    /// pivot each frame. Reading a missing name gives `nil`; writing to one (or
    /// writing `nil`) changes nothing.
    public subscript(_ name: String) -> SceneNode? {
        get { Scene.find(name, in: nodes) }
        set {
            guard let newValue else { return }
            _ = Scene.replace(name, in: &nodes, with: newValue)
        }
    }

    /// The world-space axis-aligned bounds over every node's mesh, composing the
    /// node transforms. `(.zero, .zero)` for a scene with no geometry.
    public var bounds: (min: Vector3, max: Vector3) {
        var lo = Vector3(.infinity, .infinity, .infinity)
        var hi = Vector3(-.infinity, -.infinity, -.infinity)
        var any = false
        func visit(_ node: SceneNode, parent: simd_float4x4) {
            let world = parent * node.localTransform
            if let mesh = node.mesh, !mesh.isEmpty {
                let b = mesh.bounds
                // The world AABB of the local AABB: transform its 8 corners.
                for corner in 0..<8 {
                    let c = Vector3(corner & 1 == 0 ? b.min.x : b.max.x,
                                    corner & 2 == 0 ? b.min.y : b.max.y,
                                    corner & 4 == 0 ? b.min.z : b.max.z)
                    let w = world * SIMD4<Float>(Float(c.x), Float(c.y), Float(c.z), 1)
                    let p = Vector3(Double(w.x), Double(w.y), Double(w.z))
                    lo = Vector3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
                    hi = Vector3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
                    any = true
                }
            }
            for child in node.children { visit(child, parent: world) }
        }
        for node in nodes { visit(node, parent: matrix_identity_float4x4) }
        return any ? (lo, hi) : (.zero, .zero)
    }

    // MARK: - Node-riding cameras and lights

    /// Walk the tree depth-first, handing each node its composed world transform.
    static func visitWorlds(_ nodes: [SceneNode], parent: simd_float4x4,
                            _ body: (SceneNode, simd_float4x4) -> Void) {
        for node in nodes {
            let world = parent * node.localTransform
            body(node, world)
            visitWorlds(node.children, parent: world, body)
        }
    }

    /// The authored lights resolved through the tree's current transforms, in
    /// traversal order (each node's spec emits through its composed world).
    private var nodeLights: [Light] {
        var out: [Light] = []
        Scene.visitWorlds(nodes, parent: matrix_identity_float4x4) { node, world in
            if let spec = node.lightSpec { out.append(spec.resolve(world: world)) }
        }
        return out
    }

    /// The authored cameras resolved through the tree's current transforms, in
    /// traversal order. The target rule reads the current bounds, so the pivot
    /// follows the posed geometry.
    private var nodeCameras: [Camera3D] {
        var refs: [(spec: SceneCameraSpec, world: simd_float4x4)] = []
        Scene.visitWorlds(nodes, parent: matrix_identity_float4x4) { node, world in
            if let spec = node.cameraSpec { refs.append((spec, world)) }
        }
        guard !refs.isEmpty else { return [] }
        let b = bounds
        let sceneCenter: Vector3? = nodes.isEmpty ? nil : (b.min + b.max) * 0.5
        return refs.map {
            Scene.resolveCamera(projection: $0.spec.projection, near: $0.spec.near,
                                far: $0.spec.far, world: $0.world, sceneCenter: sceneCenter)
        }
    }

    /// Rescale every node-riding light spec so the brightest of each kind is 1
    /// (specs arrive from the loaders carrying the file's raw brightness).
    static func normalizeLightSpecs(in nodes: inout [SceneNode]) {
        var kindMax: [Light.Kind: Double] = [:]
        func scan(_ ns: [SceneNode]) {
            for n in ns {
                if let s = n.lightSpec {
                    kindMax[s.kind] = Swift.max(kindMax[s.kind] ?? 0, s.intensity)
                }
                scan(n.children)
            }
        }
        scan(nodes)
        guard !kindMax.isEmpty else { return }
        func apply(_ ns: inout [SceneNode]) {
            for i in ns.indices {
                if let s = ns[i].lightSpec {
                    let peak = kindMax[s.kind] ?? 0
                    ns[i].lightSpec?.intensity = peak > 0 ? s.intensity / peak : 1
                }
                apply(&ns[i].children)
            }
        }
        apply(&nodes)
    }

    private static func find(_ name: String, in nodes: [SceneNode]) -> SceneNode? {
        for node in nodes {
            if node.name == name { return node }
            if let hit = find(name, in: node.children) { return hit }
        }
        return nil
    }

    private static func replace(_ name: String, in nodes: inout [SceneNode],
                                with newNode: SceneNode) -> Bool {
        for i in nodes.indices {
            if nodes[i].name == name { nodes[i] = newNode; return true }
            if replace(name, in: &nodes[i].children, with: newNode) { return true }
        }
        return false
    }
}

/// One node of a loaded `Scene`: a name, an authored local transform, an optional
/// `Mesh` (in the node's *local* space, positioned by the transform when drawn),
/// and child nodes that inherit the transform. A value type: mutate one through
/// the scene's subscript (`scene["lamp"]?.position += Vector3(0, 0.1, 0)`) and the
/// change shows on the next `drawScene`.
public struct SceneNode: Sendable {

    /// The node's authored name (empty when the file gave it none). Names are how
    /// `scene.node(_:)` and the subscript reach a node; duplicates resolve to the
    /// first match depth-first.
    public var name: String
    /// The node's geometry in its own local space, or `nil` for a pure grouping
    /// node. An ordinary `Mesh`: it draws standalone with `drawMesh` too, at the
    /// world origin, without this node's transform.
    public var mesh: Mesh?
    /// Child nodes, drawn inside this node's transform.
    public var children: [SceneNode]
    /// The authored local transform (translation, rotation, scale composed), kept
    /// verbatim as a matrix so nothing is lost to decomposition. The typed accessors
    /// below (`position`, `rotate`, `scale`) edit it.
    var localTransform: simd_float4x4
    /// The file's node index, the identity animation tracks target; `nil` for a
    /// hand-built node.
    var sourceIndex: Int?
    /// The authored translation/rotation/scale components (rotation as the raw
    /// xyzw quaternion) for a node the file gave TRS rather than a matrix: the
    /// base an animation swaps sampled components into, never derived by
    /// decomposing `localTransform`. `nil` for a matrix-authored node, which no
    /// track may target. (An animated USD node's base decomposes from its own
    /// authored op stack at rest instead; its baked tracks overwrite all three
    /// components at every sample, so the base never shows through.)
    var trs: (t: SIMD3<Float>, r: SIMD4<Float>, s: SIMD3<Float>)?
    /// This node's morph-target weights, one per target of its mesh, blending
    /// each target's displacement into the drawn shape (0 leaves it out, 1 adds
    /// it whole). Loaded from the file's authored weights; a weights animation
    /// track writes them, and a sketch can set them directly to pose a blend
    /// shape by hand (`scene["face"]?.weights = [0.8, 0.1]`). Empty, and inert,
    /// for a node whose mesh has no morph targets.
    public var weights: [Double] = []
    /// The scene skin posing this node's mesh (an index into `Scene.skins`), or
    /// `nil` for an unskinned node.
    var skinIndex: Int?
    /// Per-vertex joint indices and blend weights, aligned with the mesh's
    /// `positions` (empty when unskinned). Indices select into the skin's
    /// `joints` array.
    var vertexJoints: [SIMD4<UInt16>] = []
    var vertexWeights: [SIMD4<Float>] = []
    /// The mesh's morph targets: per-vertex displacements `weights` blends in.
    var morphTargets: [SceneMorphTarget] = []
    /// The authored light riding this node, in the node's own frame (emitting
    /// down local -z, extents at authored size, intensity already normalized);
    /// `Scene.lights` resolves it through the node's world transform on every
    /// read, so moving the node carries the light.
    var lightSpec: SceneLightSpec?
    /// The authored camera riding this node: the projection and clip range
    /// (the pose comes from the node's world transform on every `Scene.cameras`
    /// read, so moving the node carries the camera).
    var cameraSpec: SceneCameraSpec?

    /// A node built by hand: `name`, an optional `mesh`, a `position` for its local
    /// translation, and `children`. For composing a scene in code; loaded scenes
    /// carry their authored transforms.
    public init(name: String = "", mesh: Mesh? = nil, position: Vector3 = .zero,
                children: [SceneNode] = []) {
        self.name = name
        self.mesh = mesh
        self.children = children
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(Float(position.x), Float(position.y), Float(position.z), 1)
        self.localTransform = m
    }

    init(name: String, mesh: Mesh?, children: [SceneNode], localTransform: simd_float4x4,
         sourceIndex: Int? = nil,
         trs: (t: SIMD3<Float>, r: SIMD4<Float>, s: SIMD3<Float>)? = nil) {
        self.name = name
        self.mesh = mesh
        self.children = children
        self.localTransform = localTransform
        self.sourceIndex = sourceIndex
        self.trs = trs
    }

    /// The node's local position: its translation relative to the parent node.
    /// Settable, so `scene["lamp"]?.position += Vector3(0, 0.1, 0)` lifts the lamp
    /// (and its children) without touching its rotation or scale.
    public var position: Vector3 {
        get {
            Vector3(Double(localTransform.columns.3.x),
                    Double(localTransform.columns.3.y),
                    Double(localTransform.columns.3.z))
        }
        set {
            localTransform.columns.3 = SIMD4<Float>(Float(newValue.x), Float(newValue.y),
                                                    Float(newValue.z), 1)
            trs?.t = SIMD3<Float>(Float(newValue.x), Float(newValue.y), Float(newValue.z))
        }
    }

    /// Rotate the node by `radians` about `axis`, in its *own* local frame, so it
    /// turns about its authored pivot. Composes with the authored transform:
    /// calling it every frame accumulates into a spin. A no-op for a zero axis.
    public mutating func rotate(_ radians: Double, axis: Vector3) {
        let a = axis.normalized
        guard a.lengthSquared > 0 else { return }
        localTransform = localTransform * Drawer.rotation3(Float(radians), axis: a.simd3)
    }

    /// Scale the node (and its children) uniformly by `factor` about its own pivot,
    /// composing with the authored transform.
    public mutating func scale(by factor: Double) {
        let f = Float(factor)
        localTransform = localTransform * simd_float4x4(diagonal: SIMD4<Float>(f, f, f, 1))
    }
}

// MARK: - Node-riding light and camera payloads

/// A file-authored light in its node's local frame: everything but the pose.
/// The light emits down the node's local -z (both formats' convention), area
/// extents are the authored sizes (a scaling transform scales them at
/// resolution), and `intensity` carries the per-kind normalized brightness.
struct SceneLightSpec: Equatable, Sendable {
    var kind: Light.Kind
    var color: Color
    var intensity: Double
    var coneAngle: Double = 0
    var penumbra: Double = 0
    var width: Double = 1
    var height: Double = 1
    var radius: Double = 0.5
    var length: Double = 1

    /// The spec as a world-space `Light` through its node's composed world
    /// transform: position from the origin, direction down -z, a rect's width
    /// and height scaled by the x/y axis lengths, a disk's radius by their
    /// mean, a tube's endpoints (along local x) transformed whole.
    func resolve(world: simd_float4x4) -> Light {
        func vec(_ c: SIMD4<Float>) -> Vector3 {
            Vector3(Double(c.x), Double(c.y), Double(c.z))
        }
        let position = vec(world.columns.3)
        var direction = -vec(world.columns.2)
        direction = direction.lengthSquared > 1e-12 ? direction.normalized : Vector3(0, -1, 0)
        let xAxis = vec(world.columns.0)
        let yAxis = vec(world.columns.1)
        switch kind {
        case .directional:
            return .directional(color, direction: direction, intensity: intensity)
        case .point:
            return .point(color, at: position, intensity: intensity)
        case .spot:
            return .spot(color, at: position, direction: direction,
                         angle: coneAngle, penumbra: penumbra, intensity: intensity)
        case .rect:
            let up = yAxis.lengthSquared > 1e-12 ? yAxis.normalized : .unitY
            return .rect(color, at: position, direction: direction,
                         width: width * xAxis.length, height: height * yAxis.length,
                         up: up, intensity: intensity)
        case .disk:
            return .disk(color, at: position, direction: direction,
                         radius: radius * (xAxis.length + yAxis.length) / 2,
                         intensity: intensity)
        case .tube:
            let half = Float(length / 2)
            let from = world * SIMD4<Float>(-half, 0, 0, 1)
            let to = world * SIMD4<Float>(half, 0, 0, 1)
            return .tube(color, from: vec(from), to: vec(to),
                         radius: radius * (yAxis.length + vec(world.columns.2).length) / 2,
                         intensity: intensity)
        }
    }
}

/// A file-authored camera in its node's local frame: the projection and clip
/// range (`Scene.cameras` resolves the pose from the node's world transform).
struct SceneCameraSpec: Equatable, Sendable {
    var projection: Camera3D.Projection
    var near: Double
    var far: Double
}

// MARK: - Loading

extension Scene {

    /// Load a scene from a file, keeping its structure. `.gltf`/`.glb` files keep
    /// the full graph: named nodes with transforms, cameras, and punctual lights.
    /// The USD family (`.usdz`, `.usdc`, `.usda`, `.usd`) keeps its graph too:
    /// named nodes in authored order, transforms, cameras, the authored UsdLux
    /// lights, the authored transform animation, and the UsdSkel skins and
    /// blend shapes, all read by Ollin's own parser (see `loadUSDScene`). Any
    /// other format
    /// `loadMesh` reads (`.obj`, `.stl`, …) has no scene graph, so it loads as
    /// one node named after the file, with no cameras or lights. Returns `nil`
    /// if the file can't be read or holds nothing. Mirrors `Mesh(contentsOf:)`.
    public init?(contentsOf url: URL) {
        switch url.pathExtension.lowercased() {
        case "gltf", "glb":
            guard let scene = Scene.loadGLTFScene(url) else { return nil }
            self = scene
        case "usdz", "usdc", "usda", "usd":
            guard let scene = Scene.loadUSDScene(url) else { return nil }
            self = scene
        default:
            guard let mesh = Mesh(contentsOf: url) else { return nil }
            self = Scene(nodes: [SceneNode(name: url.deletingPathExtension().lastPathComponent,
                                           mesh: mesh)])
        }
    }

    /// Load a scene from a file `path`. Sugar over `Scene(contentsOf:)`.
    public init?(path: String) { self.init(contentsOf: URL(fileURLWithPath: path)) }

    /// Load a scene bundled as a resource. Mirrors `Mesh(resource:extension:in:)`;
    /// `in:` has no default, since a default argument would resolve to *Ollin's*
    /// bundle, not the caller's.
    public init?(resource name: String, extension ext: String?, in bundle: Bundle) {
        guard let url = bundle.url(forResource: name, withExtension: ext) else { return nil }
        self.init(contentsOf: url)
    }

    /// Read a glTF/GLB file's default scene with structure kept: the node tree
    /// (names, local transforms, per-node meshes merged from their primitives),
    /// cameras from the core spec, and lights from the punctual-lights extension,
    /// both resolved through their node's world transform.
    static func loadGLTFScene(_ url: URL) -> Scene? {
        guard let doc = GLTFDocument(contentsOf: url) else { return nil }
        let gltf = doc.gltf
        let gltfNodes = gltf.nodes ?? []

        // Build the value-typed node tree. glTF forbids cycles, but the file is
        // untrusted input, so a visited set turns a malformed loop into a skip.
        let lightDefs = gltf.extensions?.KHR_lights_punctual?.lights ?? []
        var building = Set<Int>()
        func build(_ ni: Int) -> SceneNode? {
            guard ni >= 0, ni < gltfNodes.count, !building.contains(ni) else { return nil }
            building.insert(ni)
            defer { building.remove(ni) }
            let n = gltfNodes[ni]
            let children = (n.children ?? []).compactMap(build)
            let meshData = n.mesh.flatMap(doc.localMeshData)
            var node = SceneNode(name: n.name ?? "",
                                 mesh: meshData?.mesh,
                                 children: children,
                                 localTransform: n.localMatrix,
                                 sourceIndex: ni,
                                 trs: n.authoredTRS)
            if let meshData {
                if !meshData.targets.isEmpty {
                    node.morphTargets = meshData.targets
                    // The instance's weights: the node's own, else the mesh's
                    // authored defaults (the format's precedence).
                    node.weights = n.weights ?? meshData.defaultWeights
                }
                if let si = n.skin, !meshData.joints.isEmpty {
                    node.skinIndex = si
                    node.vertexJoints = meshData.joints
                    node.vertexWeights = meshData.weights
                }
            }
            // Cameras and lights ride their nodes: attach the projection /
            // emission halves here; the pose resolves from the node's world
            // transform on every `cameras` / `lights` read.
            if let ci = n.camera, let defs = gltf.cameras, defs.indices.contains(ci) {
                node.cameraSpec = Scene.cameraSpec(defs[ci])
            }
            if let li = n.extensions?.KHR_lights_punctual?.light, lightDefs.indices.contains(li) {
                node.lightSpec = Scene.lightSpec(lightDefs[li])
            }
            return node
        }
        let roots = doc.rootNodes.compactMap(build)

        var scene = Scene(nodes: roots)
        Scene.normalizeLightSpecs(in: &scene.nodes)
        // The skins, resolved to file node indices plus their inverse bind
        // matrices (identity where the file authored none).
        scene.skins = (gltf.skins ?? []).map { def in
            let inverseBind = def.inverseBindMatrices.flatMap(doc.readMat4) ?? []
            return SceneSkin(joints: def.joints, inverseBind: inverseBind)
        }
        if let si = gltf.scene ?? (gltf.scenes?.isEmpty == false ? 0 : nil),
           gltf.scenes?.indices.contains(si) == true {
            scene.name = gltf.scenes?[si].name
        }

        scene.animations = SceneAnimation.load(from: doc)
        return scene
    }

    /// The projection half of an authored glTF camera (the pose resolves later
    /// from the node's world transform). `nil` for an unknown type.
    static func cameraSpec(_ def: GLTF.CameraDef) -> SceneCameraSpec? {
        switch def.type {
        case "perspective":
            guard let p = def.perspective else { return nil }
            return SceneCameraSpec(
                projection: .perspective(fieldOfView: min(max(p.yfov, 0.01), .pi - 0.01)),
                near: max(p.znear, 1e-4), far: p.zfar ?? 1000)
        case "orthographic":
            guard let o = def.orthographic else { return nil }
            return SceneCameraSpec(projection: .orthographic(height: 2 * o.ymag),
                                   near: o.znear, far: o.zfar)
        default:
            return nil
        }
    }

    /// The pose half of camera resolution, shared by every format: eye, view
    /// direction, and up from the node's world transform (both formats aim down
    /// the node's -z), the target found by projecting the scene center onto the
    /// view axis (see above).
    static func resolveCamera(projection: Camera3D.Projection, near: Double, far: Double,
                              world: simd_float4x4, sceneCenter: Vector3?) -> Camera3D {
        let eye = Vector3(Double(world.columns.3.x), Double(world.columns.3.y),
                          Double(world.columns.3.z))
        var back = Vector3(Double(world.columns.2.x), Double(world.columns.2.y),
                           Double(world.columns.2.z))
        back = back.lengthSquared > 1e-12 ? back.normalized : .unitZ
        let forward = Vector3(-back.x, -back.y, -back.z)
        var up = Vector3(Double(world.columns.1.x), Double(world.columns.1.y),
                         Double(world.columns.1.z))
        up = up.lengthSquared > 1e-12 ? up.normalized : .unitY

        var far = far
        if far <= near { far = near + 1000 }

        var focus = 1.0
        if let c = sceneCenter {
            let d = (c - eye).dot(forward)
            if d > near { focus = d }
        }
        return Camera3D(eye: eye, target: eye + forward * focus, up: up,
                        near: near, far: far, projection: projection)
    }

    /// An authored punctual light as a node-local spec, intensity still the
    /// file's raw value (`normalizeLightSpecs` rescales once the tree is
    /// built: physical intensities, lux for directional and candela for point
    /// and spot, have no meaning without distance falloff, which Ollin's
    /// punctual lights don't model, so each kind normalizes to its brightest
    /// and relative balance survives where absolute units don't). A light
    /// shines down its node's -z axis (directional and spot); a point light
    /// sits at the node's position. Colors arrive linear and re-encode to sRGB
    /// (the base-color-factor treatment). The spot's outer cone half-angle
    /// doubles into Ollin's full `coneAngle`; the inner-to-outer soft band
    /// becomes `penumbra`. `nil` for an unknown type.
    static func lightSpec(_ def: GLTF.PunctualLightDef) -> SceneLightSpec? {
        var color = Color.white
        if let c = def.color, c.count == 3 {
            func enc(_ x: Double) -> Double { Color.linearToSrgb(min(max(x, 0), 1)) }
            color = Color(red: enc(c[0]), green: enc(c[1]), blue: enc(c[2]))
        }
        let intensity = max(def.intensity ?? 1, 0)
        switch def.type {
        case "directional":
            return SceneLightSpec(kind: .directional, color: color, intensity: intensity)
        case "point":
            return SceneLightSpec(kind: .point, color: color, intensity: intensity)
        case "spot":
            let outer = def.spot?.outerConeAngle ?? .pi / 4
            let inner = min(def.spot?.innerConeAngle ?? 0, outer)
            let penumbra = outer > 0 ? min(max(1 - inner / outer, 0), 1) : 0
            return SceneLightSpec(kind: .spot, color: color, intensity: intensity,
                                  coneAngle: 2 * outer, penumbra: penumbra)
        default:
            return nil
        }
    }
}

// MARK: - Sketch sugar

extension Sketch {

    /// Load a 3D scene from a file `path`, keeping its structure (named nodes,
    /// cameras, lights). Returns `nil` if it can't be read. Call it in `setup()`
    /// and keep the result in a property. Sugar over `Scene(contentsOf:)`; the
    /// merged-geometry complement is `loadMesh`.
    public func loadScene(_ path: String) -> Scene? { Scene(path: path) }

    /// Load a scene from a file `url`. Sugar over `Scene(contentsOf:)`.
    public func loadScene(_ url: URL) -> Scene? { Scene(contentsOf: url) }
}
