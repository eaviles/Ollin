import Foundation
import simd

// The USD leg of structure-preserving scene import, read natively: one
// `USDStage` parse serves the whole `Scene`. The node tree keeps the file's
// authored child order and every node carries real per-prim identity
// (`sourceIndex`, assigned depth-first in authored order), which is what
// animation and skinning tracks bind by. Meshes rebuild from their authored
// data (points kept indexed where attributes allow, expanded per face corner
// when normals or texture coordinates are faceVarying or per-face), materials
// read the bound preview surface spec-correctly (linear colors re-encoded to
// sRGB, textures resolved through the package or the file's folder), cameras
// resolve from their prims' authored attributes, and the UsdLux lights, the
// baked transform animation, and the UsdSkel deforming tier ride the same
// parse (`SceneLoaderUSDLights` / `SceneLoaderUSDAnimation` /
// `SceneLoaderUSDSkinning`).
//
// The reading envelope is the parser core's: flattened single layers and
// self-contained packages. Schema semantics honored here: `visibility =
// "invisible"` hides a subtree (nodes stay, nothing renders or images),
// a `guide` or `proxy` purpose skips rendering for its subtree, Scope prims
// arrive as plain grouping nodes, and material/shader/skel-support prims
// (Material, Shader, NodeGraph, Skeleton, SkelAnimation, BlendShape,
// GeomSubset) are consumed by their own resolution passes rather than
// becoming nodes. `upAxis` and `metersPerUnit` are deliberately *not*
// applied: a scene arrives in its author's own units and orientation, the
// `loadMesh` contract. A subdivision-surface mesh draws its control cage
// (refine one yourself with `mesh.subdivided(_:)` when the smooth limit
// matters).

extension Scene {

    /// Read a USD file's default layer with structure kept: the node tree in
    /// authored order (names, local transforms, per-node meshes in node-local
    /// space, per-prim identity), the authored cameras and UsdLux lights
    /// resolved through their prims' world transforms, the authored transform
    /// animation, and the UsdSkel deforming tier. Returns `nil` when the file
    /// can't be parsed or holds no prims at all.
    static func loadUSDScene(_ url: URL) -> Scene? {
        guard let data = try? Data(contentsOf: url),
              let opened = try? USDStage.open(data: data),
              !opened.stage.prims.isEmpty else { return nil }
        let stage = opened.stage

        var build = USDBuild(stage: stage, assets: USDAssetStore(fileURL: url, opened: opened))
        var roots: [SceneNode] = []
        for prim in stage.prims {
            if let node = buildNode(prim, parentPath: "", parent: matrix_identity_double4x4,
                                    hidden: false, renderSkipped: false, build: &build) {
                roots.append(node)
            }
        }
        var scene = Scene(nodes: roots)
        Scene.normalizeLightSpecs(in: &scene.nodes)

        // The stage's one animation: baked xformOp tracks plus the SkelAnimation
        // channels, every track bound by prim identity. Each animated prim's
        // rest pose (the decomposed op stack at rest) installs as its node's
        // TRS base, the field `apply` requires. Skeleton subtrees append after
        // the tree nodes, their joints numbered past every prim index.
        var tracks: [SceneAnimation.Track] = []
        var duration = 0.0
        if let baked = resolveUSDAnimation(stage) {
            for entry in baked.entries {
                guard let index = build.indexOfPath[entry.path] else { continue }
                _ = Scene.withNode(sourceIndex: index, in: &scene.nodes) { $0.trs = entry.rest }
                var track = entry.track
                track.nodeIndex = index
                tracks.append(track)
            }
            duration = baked.duration
        }
        let skel = resolveUSDSkinning(stage, into: &scene, indexOfPath: build.indexOfPath,
                                      firstJointIndex: build.nextIndex)
        tracks += skel.tracks
        duration = Swift.max(duration, skel.duration)
        if !tracks.isEmpty {
            scene.animations = [SceneAnimation(name: "", duration: duration, tracks: tracks)]
        }
        return scene
    }

    // MARK: - The walk

    /// Prim types that never become scene nodes: each is consumed by its own
    /// resolution pass (materials by the mesh read, Skeleton by the skinning
    /// pass, which synthesizes the real joint subtree).
    private static let usdNonNodeTypes: Set<String> = [
        "Material", "Shader", "NodeGraph", "Skeleton", "SkelAnimation",
        "BlendShape", "GeomSubset",
    ]

    private struct USDBuild {
        var stage: USDStage
        var assets: USDAssetStore
        /// Every built node's identity, keyed by its prim's absolute path.
        var indexOfPath: [String: Int] = [:]
        /// The next identity to assign; after the walk, the floor for the
        /// skinning pass's synthesized joint indices.
        var nextIndex = 0
        /// Resolved materials by material prim path (decoding a texture twice
        /// would be wasteful; `nil` records a material that resolved to nothing).
        var materials: [String: MeshMaterial?] = [:]
    }

    /// One prim as a `SceneNode`, depth-first: identity assigned in authored
    /// order, children in authored order, the mesh built when the prim is a
    /// renderable Mesh. `hidden` carries an ancestor's `visibility =
    /// "invisible"` (nothing under it renders or images); `renderSkipped` adds
    /// the `guide`/`proxy` purpose (meshes and lights skip, cameras still
    /// resolve). Both inherit down the subtree, the schema's pruning rules.
    private static func buildNode(_ prim: USDPrim, parentPath: String,
                                  parent: simd_double4x4, hidden: Bool,
                                  renderSkipped: Bool, build: inout USDBuild) -> SceneNode? {
        guard prim.specifier != .class, !usdNonNodeTypes.contains(prim.typeName) else {
            return nil
        }
        let path = parentPath + "/" + prim.name
        let (composed, resets) = prim.localXform()
        // A `!resetXformStack!` prim discards its inherited stack; the tree
        // still composes parents, so bake the discard into the local matrix.
        let local = resets ? parent.inverse * composed : composed
        let world = resets ? composed : parent * local

        let hidden = hidden
            || prim.attribute("visibility")?.authoredValue?.usdToken == "invisible"
        var renderSkipped = renderSkipped || hidden
        if let purpose = prim.attribute("purpose")?.authoredValue?.usdToken,
           purpose == "guide" || purpose == "proxy" {
            renderSkipped = true
        }

        var mesh: Mesh?
        if prim.typeName == "Mesh", !renderSkipped {
            // A deforming mesh must keep the authored points indexed: every
            // skel primvar and blend-shape offset is authored against them.
            mesh = buildUSDMesh(prim, keepIndexed: prim.isSkelDeforming,
                                material: resolveUSDMaterial(for: prim, build: &build))
        }

        let index = build.nextIndex
        build.nextIndex += 1
        build.indexOfPath[path] = index

        var children: [SceneNode] = []
        for child in prim.children {
            if let node = buildNode(child, parentPath: path, parent: world, hidden: hidden,
                                    renderSkipped: renderSkipped, build: &build) {
                children.append(node)
            }
        }
        var node = SceneNode(name: prim.name, mesh: mesh, children: children,
                             localTransform: f4x4(local), sourceIndex: index)
        // Cameras and lights ride their nodes: the projection / emission
        // halves attach here and the pose resolves from the node's world
        // transform on every `cameras` / `lights` read.
        if prim.typeName == "Camera", !hidden {
            node.cameraSpec = usdCameraSpec(prim)
        }
        if usdLightTypeNames.contains(prim.typeName), !renderSkipped {
            node.lightSpec = usdLightSpec(prim)
        }
        return node
    }

    /// Mutate the first node carrying `sourceIndex` (depth-first), in place.
    @discardableResult
    static func withNode(sourceIndex: Int, in nodes: inout [SceneNode],
                         _ body: (inout SceneNode) -> Void) -> Bool {
        for i in nodes.indices {
            if nodes[i].sourceIndex == sourceIndex { body(&nodes[i]); return true }
            if withNode(sourceIndex: sourceIndex, in: &nodes[i].children, body) { return true }
        }
        return false
    }

    // MARK: - Cameras

    /// A camera prim's authored projection as a node-local spec: field of view
    /// from focal length over vertical aperture (both spelled in the same
    /// tenth-of-unit scale, so only the ratio matters), an orthographic
    /// aperture in tenths of a world unit, near/far from `clippingRange`.
    /// Schema defaults apply; the pose resolves later from the node's world
    /// transform.
    private static func usdCameraSpec(_ prim: USDPrim) -> SceneCameraSpec {
        var near = 1.0
        var far = 1_000_000.0
        if case .tuple(let clip)? = prim.attribute("clippingRange")?.authoredValue,
           clip.count == 2 {
            near = clip[0]
            far = clip[1]
        }
        let projection: Camera3D.Projection
        if prim.attribute("projection")?.authoredValue?.usdToken == "orthographic" {
            let aperture = prim.attribute("verticalAperture")?.authoredValue?.usdScalar ?? 15.2908
            projection = .orthographic(height: aperture / 10)
        } else {
            let focal = prim.attribute("focalLength")?.authoredValue?.usdScalar ?? 50
            let aperture = prim.attribute("verticalAperture")?.authoredValue?.usdScalar ?? 15.2908
            let fov = focal > 0 ? 2 * atan(aperture / (2 * focal)) : 0.7
            projection = .perspective(fieldOfView: min(max(fov, 0.01), .pi - 0.01))
            near = max(near, 1e-4)
        }
        return SceneCameraSpec(projection: projection, near: near, far: far)
    }

    // MARK: - Meshes

    /// A Mesh prim's geometry from its authored data. The indexed form keeps
    /// the authored points (vertex-interpolated normals and texture
    /// coordinates honored, anything else smoothed or dropped); the general
    /// form expands per face corner when normals or `primvars:st` are
    /// faceVarying or per-face, so those looks survive. Faces
    /// fan-triangulate in authored winding (reversed under a `leftHanded`
    /// orientation); a face with a bad index is skipped whole rather than
    /// mis-wound. Returns `nil` when the geometry is unreadable.
    static func buildUSDMesh(_ prim: USDPrim, keepIndexed: Bool,
                             material: MeshMaterial?) -> Mesh? {
        guard let pointsFlat = prim.attribute("points")?.authoredValue?.usdFlatTuples(arity: 3),
              case .intArray(let counts)? = prim.attribute("faceVertexCounts")?.authoredValue,
              case .intArray(let rawIndices)? = prim.attribute("faceVertexIndices")?.authoredValue
        else { return nil }
        let pointCount = pointsFlat.count / 3
        guard pointCount > 0 else { return nil }
        var points = [Vector3]()
        points.reserveCapacity(pointCount)
        for i in 0..<pointCount {
            points.append(Vector3(pointsFlat[i * 3], pointsFlat[i * 3 + 1], pointsFlat[i * 3 + 2]))
        }
        let leftHanded = prim.attribute("orientation")?.authoredValue?.usdToken == "leftHanded"
        let cornerCount = counts.reduce(0) { $0 + Int($1) }
        let faceCount = counts.count

        // `primvars:normals` wins over `normals` when both are authored (the
        // schema's precedence); normals default to vertex interpolation.
        let normalsAttr = prim.attribute("primvars:normals") ?? prim.attribute("normals")
        let normalsSpec = USDPrimvarSpec(normalsAttr, indices: nil, arity: 3,
                                         defaultInterpolation: .vertex, pointCount: pointCount,
                                         cornerCount: cornerCount, faceCount: faceCount)
        let stSpec = USDPrimvarSpec(prim.attribute("primvars:st"),
                                    indices: prim.attribute("primvars:st:indices"), arity: 2,
                                    defaultInterpolation: nil, pointCount: pointCount,
                                    cornerCount: cornerCount, faceCount: faceCount)

        // Per-corner and per-face data can't ride shared vertices; expand
        // unless the mesh must stay indexed (the deforming form, where such a
        // set drops instead).
        let expand = !keepIndexed && (normalsSpec?.needsExpansion == true
            || stSpec?.needsExpansion == true)
        return expand
            ? expandedUSDMesh(points: points, counts: counts, rawIndices: rawIndices,
                              leftHanded: leftHanded, normalsSpec: normalsSpec, stSpec: stSpec,
                              material: material)
            : indexedUSDMesh(points: points, counts: counts, rawIndices: rawIndices,
                             leftHanded: leftHanded, normalsSpec: normalsSpec, stSpec: stSpec,
                             material: material)
    }

    /// The indexed form: the mesh on its authored points.
    private static func indexedUSDMesh(points: [Vector3], counts: [Int64],
                                       rawIndices: [Int64], leftHanded: Bool,
                                       normalsSpec: USDPrimvarSpec?, stSpec: USDPrimvarSpec?,
                                       material: MeshMaterial?) -> Mesh? {
        let pointCount = points.count
        var indices: [UInt32] = []
        var cursor = 0
        for count in counts {
            let c = Int(count)
            defer { cursor += c }
            guard c >= 3, cursor + c <= rawIndices.count else { continue }
            let face = Array(rawIndices[cursor..<(cursor + c)])
            guard face.allSatisfy({ $0 >= 0 && $0 < pointCount }) else { continue }
            for k in 1..<(c - 1) {
                if leftHanded {
                    indices += [UInt32(face[0]), UInt32(face[k + 1]), UInt32(face[k])]
                } else {
                    indices += [UInt32(face[0]), UInt32(face[k]), UInt32(face[k + 1])]
                }
            }
        }
        guard !indices.isEmpty else { return nil }

        var normals = [Vector3](repeating: .zero, count: pointCount)
        if let spec = normalsSpec, spec.interpolation == .vertex {
            for i in 0..<pointCount {
                normals[i] = unitNormal(spec.element(at: i))
            }
        } else {
            Mesh.smoothNormals(into: &normals, positions: points, indices: indices,
                               vertexRange: 0..<pointCount)
        }

        var uvs: [Vector2] = []
        if let spec = stSpec, spec.interpolation == .vertex {
            for i in 0..<pointCount { uvs.append(uv(spec.element(at: i))) }
        }
        return Mesh(positions: points, normals: normals, indices: indices,
                    uvs: uvs, material: material)
    }

    /// The expanded form: one vertex per face corner, so per-corner and
    /// per-face attributes land exactly.
    private static func expandedUSDMesh(points: [Vector3], counts: [Int64],
                                        rawIndices: [Int64], leftHanded: Bool,
                                        normalsSpec: USDPrimvarSpec?, stSpec: USDPrimvarSpec?,
                                        material: MeshMaterial?) -> Mesh? {
        let pointCount = points.count
        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var uvs: [Vector2] = []
        var indices: [UInt32] = []
        var haveAllNormals = normalsSpec != nil
        var haveAllUVs = stSpec != nil

        // Attribute element for one corner: by corner, point, face, or the
        // shared constant, per the spec's interpolation.
        func element(_ spec: USDPrimvarSpec, corner: Int, point: Int, face: Int) -> [Double]? {
            switch spec.interpolation {
            case .faceVarying: spec.element(at: corner)
            case .vertex: spec.element(at: point)
            case .uniform: spec.element(at: face)
            case .constant: spec.element(at: 0)
            }
        }

        var cursor = 0
        var faceIndex = -1
        for count in counts {
            faceIndex += 1
            let c = Int(count)
            let base = cursor
            defer { cursor += c }
            guard c >= 3, base + c <= rawIndices.count else { continue }
            let face = Array(rawIndices[base..<(base + c)])
            guard face.allSatisfy({ $0 >= 0 && $0 < pointCount }) else { continue }

            let first = UInt32(positions.count)
            for k in 0..<c {
                let point = Int(face[k])
                positions.append(points[point])
                if let spec = normalsSpec,
                   let n = element(spec, corner: base + k, point: point, face: faceIndex) {
                    normals.append(unitNormal(n))
                } else {
                    normals.append(.zero)
                    haveAllNormals = false
                }
                if let spec = stSpec,
                   let t = element(spec, corner: base + k, point: point, face: faceIndex) {
                    uvs.append(uv(t))
                } else {
                    uvs.append(.zero)
                    haveAllUVs = false
                }
            }
            for k in 1..<(c - 1) {
                if leftHanded {
                    indices += [first, first + UInt32(k + 1), first + UInt32(k)]
                } else {
                    indices += [first, first + UInt32(k), first + UInt32(k + 1)]
                }
            }
        }
        guard !indices.isEmpty else { return nil }
        if !haveAllNormals {
            // No shared vertices to smooth across, so this is the flat-facet
            // fallback, the honest look for a mesh authored without normals.
            Mesh.smoothNormals(into: &normals, positions: positions, indices: indices,
                               vertexRange: 0..<positions.count)
        }
        return Mesh(positions: positions, normals: normals, indices: indices,
                    uvs: haveAllUVs ? uvs : [], material: material)
    }

    private static func unitNormal(_ c: [Double]?) -> Vector3 {
        guard let c, c.count == 3 else { return .unitY }
        let v = Vector3(c[0], c[1], c[2])
        return v.lengthSquared > 1e-12 ? v.normalized : .unitY
    }

    /// A texture coordinate flipped to the top-left convention.
    private static func uv(_ c: [Double]?) -> Vector2 {
        guard let c, c.count == 2 else { return .zero }
        return Vector2(c[0], 1 - c[1])
    }

    // MARK: - Materials

    /// The mesh's bound preview surface resolved spec-correctly: a connected
    /// `UsdUVTexture` becomes the material's texture (its file read through
    /// the package or the layer's folder), a `diffuseColor` value re-encodes
    /// linear to sRGB (the treatment every loader's authored color gets), and
    /// a mesh with no binding falls back to its first `displayColor`. Nil
    /// when none of those are authored.
    private static func resolveUSDMaterial(for prim: USDPrim,
                                           build: inout USDBuild) -> MeshMaterial? {
        if let target = prim.relationship("material:binding")?.targets.first {
            let path = usdPrimPath(ofPropertyPath: target)
            if let cached = build.materials[path] {
                if let cached { return cached }
            } else {
                let resolved = build.stage.prim(atPath: path).flatMap {
                    resolvePreviewSurface($0, build: &build)
                }
                build.materials[path] = resolved
                if let resolved { return resolved }
            }
        }
        if let flat = prim.attribute("primvars:displayColor")?.authoredValue?
            .usdFlatTuples(arity: 3), flat.count >= 3 {
            return MeshMaterial(baseColor: encodedColor(flat[0], flat[1], flat[2]))
        }
        return nil
    }

    /// The first `UsdPreviewSurface` shader in the material's subtree
    /// (authored order, which covers the flattened export shapes: the shader
    /// directly under the material, or nested in a NodeGraph).
    private static func resolvePreviewSurface(_ material: USDPrim,
                                              build: inout USDBuild) -> MeshMaterial? {
        guard let shader = firstPreviewSurface(in: material) else { return nil }
        let diffuse = shader.attribute("inputs:diffuseColor") ?? shader.attribute("diffuseColor")

        // A connected diffuse input names a texture shader; follow it to the
        // file asset.
        if let connection = diffuse?.connections.first,
           let texture = build.stage.prim(atPath: usdPrimPath(ofPropertyPath: connection)),
           texture.attribute("info:id")?.authoredValue?.usdToken == "UsdUVTexture",
           case .asset(let file)? = (texture.attribute("inputs:file")
               ?? texture.attribute("file"))?.authoredValue,
           let image = build.assets.image(atAssetPath: file) {
            return MeshMaterial(baseColor: .white, texture: image)
        }
        if let c = diffuse?.authoredValue?.usdComponents(count: 3) {
            return MeshMaterial(baseColor: encodedColor(c[0], c[1], c[2]))
        }
        return nil
    }

    private static func firstPreviewSurface(in prim: USDPrim) -> USDPrim? {
        if prim.attribute("info:id")?.authoredValue?.usdToken == "UsdPreviewSurface" {
            return prim
        }
        for child in prim.children {
            if let hit = firstPreviewSurface(in: child) { return hit }
        }
        return nil
    }

    /// A linear color component set re-encoded to sRGB (authored USD colors
    /// are linear, `Color` is display-encoded).
    private static func encodedColor(_ r: Double, _ g: Double, _ b: Double) -> Color {
        func enc(_ x: Double) -> Double { Color.linearToSrgb(min(max(x, 0), 1)) }
        return Color(red: enc(r), green: enc(g), blue: enc(b))
    }

    /// The prim half of a property path: `</a/b.outputs:surface>` names prim
    /// `/a/b` (prim names can't contain a dot).
    static func usdPrimPath(ofPropertyPath path: String) -> String {
        guard let dot = path.firstIndex(of: ".") else { return path }
        return String(path[..<dot])
    }

    static func f4x4(_ m: simd_double4x4) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1),
                                SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)))
    }
}

// MARK: - Primvar reading

/// One authored primvar-shaped attribute, its interpolation resolved and its
/// optional `:indices` dereferenced: `element(at:)` answers the tuple for a
/// point, corner, or face slot. Interpolation comes from the authored
/// metadata (`varying` reads as `vertex` on a polygonal mesh), falling back
/// to the declared default or, failing that, to what the element count
/// matches. A spec whose element count fits no interpolation is nil, so a
/// mis-sized set drops whole rather than mis-mapping.
struct USDPrimvarSpec {
    enum Interpolation { case constant, uniform, vertex, faceVarying }

    var interpolation: Interpolation
    private var components: [Double]
    private var arity: Int
    private var indices: [Int]?

    init?(_ attr: USDAttribute?, indices indicesAttr: USDAttribute?, arity: Int,
          defaultInterpolation: Interpolation?, pointCount: Int, cornerCount: Int,
          faceCount: Int) {
        guard let attr, let flat = attr.authoredValue?.usdFlatTuples(arity: arity),
              !flat.isEmpty else { return nil }
        var indexList: [Int]?
        if case .intArray(let raw)? = indicesAttr?.authoredValue {
            let tupleCount = flat.count / arity
            guard raw.allSatisfy({ $0 >= 0 && $0 < tupleCount }) else { return nil }
            indexList = raw.map(Int.init)
        }
        let elementCount = indexList?.count ?? flat.count / arity

        let interpolation: Interpolation?
        switch attr.metadata["interpolation"]?.usdToken {
        case "constant": interpolation = .constant
        case "uniform": interpolation = .uniform
        case "vertex", "varying": interpolation = .vertex
        case "faceVarying": interpolation = .faceVarying
        default:
            // Unauthored: the declared default when its size fits, else the
            // interpolation the element count singles out.
            if let d = defaultInterpolation,
               elementCount == Self.expectedCount(d, pointCount, cornerCount, faceCount) {
                interpolation = d
            } else if elementCount == pointCount {
                interpolation = .vertex
            } else if elementCount == cornerCount {
                interpolation = .faceVarying
            } else if elementCount == 1 {
                interpolation = .constant
            } else if elementCount == faceCount {
                interpolation = .uniform
            } else {
                interpolation = nil
            }
        }
        guard let interpolation,
              elementCount == Self.expectedCount(interpolation, pointCount, cornerCount,
                                                 faceCount)
        else { return nil }
        self.interpolation = interpolation
        self.components = flat
        self.arity = arity
        self.indices = indexList
    }

    private static func expectedCount(_ i: Interpolation, _ points: Int, _ corners: Int,
                                      _ faces: Int) -> Int {
        switch i {
        case .constant: 1
        case .uniform: faces
        case .vertex: points
        case .faceVarying: corners
        }
    }

    /// Whether this set needs one vertex per face corner to land exactly.
    var needsExpansion: Bool {
        interpolation == .faceVarying || interpolation == .uniform
    }

    /// The tuple at element slot `i` (a point, corner, or face index per the
    /// interpolation), through the indices when authored.
    func element(at i: Int) -> [Double]? {
        guard i >= 0 else { return nil }
        var slot = i
        if let indices {
            guard i < indices.count else { return nil }
            slot = indices[i]
        }
        let start = slot * arity
        guard start + arity <= components.count else { return nil }
        return Array(components[start..<(start + arity)])
    }
}

// MARK: - Asset resolution

/// Resolves authored asset paths (texture files) against where the layer
/// actually lives: entries of the `.usdz` package, or the folder of a loose
/// layer on disk.
struct USDAssetStore {
    private let archive: USDZipArchive?
    private let layerDirectory: String
    private let baseURL: URL

    init(fileURL: URL, opened: USDStage.Opened) {
        archive = opened.archive
        layerDirectory = (opened.defaultLayerName as NSString?)?
            .deletingLastPathComponent ?? ""
        baseURL = fileURL.deletingLastPathComponent()
    }

    /// The decoded image at an authored asset path, resolved relative to the
    /// default layer. Remote URLs and absolute paths are not resolved (the
    /// envelope is self-contained files). In a package, a path that misses
    /// falls back to the sole entry sharing its file name, which forgives the
    /// exporters that flatten directory layouts.
    func image(atAssetPath path: String) -> Image? {
        var relative = path
        if relative.hasPrefix("./") { relative.removeFirst(2) }
        guard !relative.isEmpty, !relative.contains("://"), !relative.hasPrefix("/")
        else { return nil }

        if let archive {
            let joined = layerDirectory.isEmpty ? relative : layerDirectory + "/" + relative
            if let data = archive.data(named: Self.normalize(joined)) {
                return Image(data: data)
            }
            let leaf = (relative as NSString).lastPathComponent
            let hits = archive.entryNames.filter { ($0 as NSString).lastPathComponent == leaf }
            if hits.count == 1, let data = archive.data(named: hits[0]) {
                return Image(data: data)
            }
            return nil
        }
        guard let data = try? Data(contentsOf: baseURL.appendingPathComponent(relative))
        else { return nil }
        return Image(data: data)
    }

    /// `a/./b/../c` to `a/c`: archive entry names are stored normalized.
    private static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == "..", !parts.isEmpty, parts.last != ".." {
                parts.removeLast()
            } else {
                parts.append(part)
            }
        }
        return parts.joined(separator: "/")
    }
}

// MARK: - Raw-value normalization

// The raw tree keeps each file's own shape, so the same field can arrive
// `.token` from crate and `.string` from text, or `.tokenArray` against
// `.stringArray`; scalars widen but keep their numeric case. These accessors
// are where the consumer tier normalizes, shared by the walk and the light /
// animation / skinning legs.

extension USDValue {

    /// A token-shaped value from either container.
    var usdToken: String? {
        switch self {
        case .token(let t): t
        case .string(let s): s
        default: nil
        }
    }

    /// A token-array-shaped value from either container.
    var usdTokenArray: [String]? {
        switch self {
        case .tokenArray(let t): t
        case .stringArray(let s): s
        default: nil
        }
    }

    /// A numeric scalar widened to `Double`.
    var usdScalar: Double? {
        switch self {
        case .double(let d): d
        case .int(let i): Double(i)
        case .uint(let u): Double(u)
        default: nil
        }
    }

    /// A numeric scalar as `Int`.
    var usdInt: Int? {
        switch self {
        case .int(let i): Int(i)
        case .uint(let u): Int(u)
        default: nil
        }
    }

    /// A fixed-arity tuple's components (a single vector, color, or quat),
    /// when the count matches.
    func usdComponents(count: Int) -> [Double]? {
        guard case .tuple(let c) = self, c.count == count else { return nil }
        return c
    }

    /// A float-typed array widened to `Float` elements.
    var usdFloats: [Float]? {
        switch self {
        case .floatArray(let f): f
        case .doubleArray(let d): d.map(Float.init)
        default: nil
        }
    }

    /// A tuple array's flat components widened to `Double`, when the arity
    /// matches.
    func usdFlatTuples(arity: Int) -> [Double]? {
        switch self {
        case .floatTupleArray(let a, let f) where a == arity: f.map(Double.init)
        case .doubleTupleArray(let a, let d) where a == arity: d
        default: nil
        }
    }

    /// A single matrix4d as a column-vector matrix (rows load as columns, the
    /// row-vector convention).
    var usdMatrix: simd_double4x4? {
        guard case .tuple(let m) = self, m.count == 16 else { return nil }
        return simd_double4x4(columns: (SIMD4(m[0], m[1], m[2], m[3]),
                                        SIMD4(m[4], m[5], m[6], m[7]),
                                        SIMD4(m[8], m[9], m[10], m[11]),
                                        SIMD4(m[12], m[13], m[14], m[15])))
    }

    /// A matrix4d array as column-vector matrices, requiring exactly `count`.
    func usdMatrixArray(count: Int) -> [simd_double4x4]? {
        guard let flat = usdFlatTuples(arity: 16), flat.count == count * 16 else { return nil }
        return (0..<count).map { i in
            let m = Array(flat[i * 16..<(i + 1) * 16])
            return simd_double4x4(columns: (SIMD4(m[0], m[1], m[2], m[3]),
                                            SIMD4(m[4], m[5], m[6], m[7]),
                                            SIMD4(m[8], m[9], m[10], m[11]),
                                            SIMD4(m[12], m[13], m[14], m[15])))
        }
    }
}

extension USDPrim {
    /// Whether this Mesh prim deforms (a skin binding or blend-shape targets),
    /// which is what forces its rebuild to keep the authored points indexed.
    var isSkelDeforming: Bool {
        relationship("skel:skeleton") != nil || relationship("skel:blendShapeTargets") != nil
    }

    /// The authored point count, the layout every skel primvar and
    /// blend-shape offset aligns with.
    var authoredPointCount: Int {
        (attribute("points")?.authoredValue?.usdFlatTuples(arity: 3)?.count ?? 0) / 3
    }
}
