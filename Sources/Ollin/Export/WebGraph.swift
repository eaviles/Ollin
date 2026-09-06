import Foundation
import OllinExpander
import simd
import COllinShaders

// MARK: - The graph

/// The pass graph of one recorded frame: the layers the renderer filled, in
/// the order it filled them, what each was filled from, what the canvas drew,
/// and the whole-frame filters after it. Every shape run, image quad, composed
/// field, node program, triangle run, and parameter row points into the frame's
/// float vector, so the structure is one value and the numbers travel apart from
/// it: a frame whose graph equals the last frame's differs only in its vector,
/// which is what lets the moving columns be fitted and sampled the way the
/// shapes already are.
struct WebGraph: Hashable {
    var layers: [WebLayer]
    var canvas: [WebDrawItem]
    var frameFilters: [WebPassNode]
    /// The vector's layout: `instanceCount` shapes of `WebInstance.floats`,
    /// then `quadCount` image quads of `WebQuad.floats`, then `groupCount`
    /// composed 2D fields of `WebGroup.floats` over `nodeCount` instructions of
    /// `WebNode.floats`, then `fieldCount` raymarched 3D fields of
    /// `WebField.floats` over `node3DCount` instructions of `WebNode3D.floats`,
    /// then `sourceFloats` of strokes and fills as their points
    /// (`WebSourceLayout` records, back to back), then `vertexCount` triangle
    /// vertices of `WebVertex.floats` (last among the records, since the track
    /// carries their positions apart), then `paramFloats`.
    var instanceCount: Int
    var quadCount: Int
    var groupCount: Int = 0
    var nodeCount: Int = 0
    var fieldCount: Int = 0
    var node3DCount: Int = 0
    var sourceFloats: Int = 0
    /// The columns of the source region that name a record's shape rather
    /// than its motion (its kind, its flags, its count, a fill's contour
    /// lengths), relative to the region; part of the graph, so two frames
    /// whose records are laid out differently are two casts.
    var sourceStructure: [Int] = []
    var vertexCount: Int
    var paramFloats: Int

    var vectorCount: Int { paramOffset + paramFloats }
    var quadOffset: Int { instanceCount * WebInstance.floats }
    var groupOffset: Int { quadOffset + quadCount * WebQuad.floats }
    var nodeOffset: Int { groupOffset + groupCount * WebGroup.floats }
    var fieldOffset: Int { nodeOffset + nodeCount * WebNode.floats }
    var node3DOffset: Int { fieldOffset + fieldCount * WebField.floats }
    var sourceOffset: Int { node3DOffset + node3DCount * WebNode3D.floats }
    var vertexOffset: Int { sourceOffset + sourceFloats }
    var paramOffset: Int { vertexOffset + vertexCount * WebVertex.floats }

    /// Whether any surface draws triangles this frame, as vertices or as the
    /// points the page expands.
    var hasTriangles: Bool {
        draws { item in
            switch item {
            case .triangles, .sources: return true
            default: return false
            }
        }
    }

    /// How many strokes and fills the frame carries as their points.
    var sourceCount: Int {
        var n = 0
        func count(_ items: [WebDrawItem]) {
            for item in items { if case let .sources(_, _, c, _, _) = item { n += c } }
        }
        count(canvas)
        for layer in layers {
            switch layer.kind {
            case let .geometry(_, items), let .feedback(_, items), let .sim(_, _, items): count(items)
            default: break
            }
        }
        return n
    }

    /// Whether the canvas marches a 3D field this frame, so the page keeps a
    /// depth buffer on it (the fields occlude one another through it, as the
    /// Mac's do) and the frame carries a scene block.
    var hasFields: Bool { fieldCount > 0 }

    /// The columns whose value is part of the cast rather than its motion: a
    /// node's kind and op, a field's program length and boundedness. A frame
    /// that differs from the first in one of these is a different cast, however
    /// alike the graphs read.
    var structuralColumns: [Int] {
        var columns: [Int] = []
        for i in 0 ..< groupCount {
            for c in WebGroup.structuralColumns { columns.append(groupOffset + i * WebGroup.floats + c) }
        }
        for i in 0 ..< nodeCount {
            for c in WebNode.structuralColumns { columns.append(nodeOffset + i * WebNode.floats + c) }
        }
        for i in 0 ..< fieldCount {
            for c in WebField.structuralColumns { columns.append(fieldOffset + i * WebField.floats + c) }
        }
        for i in 0 ..< node3DCount {
            for c in WebNode3D.structuralColumns { columns.append(node3DOffset + i * WebNode3D.floats + c) }
        }
        for c in sourceStructure { columns.append(sourceOffset + c) }
        return columns
    }

    /// Whether any surface draws an item whose edge the raster decides (a
    /// fill's triangles, a picture's quad), so the page rasterizes its drawn
    /// surfaces with multisampling, as the Mac does for every 2D pass. A shape
    /// carries analytic coverage, and a glyph quad's edge is outside its
    /// glyph's field, so neither asks for it.
    var needsMultisampling: Bool {
        draws { item in
            switch item {
            case .triangles, .sources, .image: return true
            default: return false
            }
        }
    }

    private func draws(_ test: (WebDrawItem) -> Bool) -> Bool {
        if canvas.contains(where: test) { return true }
        return layers.contains { layer in
            switch layer.kind {
            case let .geometry(_, items), let .feedback(_, items), let .sim(_, _, items): return items.contains(where: test)
            default: return false
            }
        }
    }

    /// Whether the frame carries state from the one before it (a feedback layer
    /// or a simulation), so the page must play every frame in order.
    var isStateful: Bool {
        layers.contains { layer in
            switch layer.kind {
            case .feedback, .sim: return true
            default: return false
            }
        }
    }
}

/// One layer of the graph.
struct WebLayer: Hashable {
    /// A persistent layer's key (a feedback layer, a simulation field), the same
    /// across frames; -1 for a layer that lives one frame.
    var key: Int
    var width: Int
    var height: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var kind: Kind

    enum Kind: Hashable {
        /// Drawn into: the clear (linear rgb and alpha), then the items.
        case geometry(clear: [Float], items: [WebDrawItem])
        case generator(WebPassNode)
        case filter(input: Int, WebPassNode)
        case combine(base: Int, aux: Int, WebPassNode)
        /// A user shader run as a generator (no inputs), a filter (one), or a
        /// combine (two); its rows sit at `paramOffset`, its clock and pointer
        /// are live on the page.
        case user(shader: Int, inputs: [Int], paramOffset: Int, paramRows: Int)
        /// A layer that remembers itself: the items draw over a clear into the
        /// back of a persistent pair while `previous` reads the front.
        case feedback(clear: [Float], items: [WebDrawItem])
        /// A simulation field: the items seed a scratch layer, the inject lays
        /// it onto the front state, the step runs its substeps, the back holds
        /// the result.
        case sim(WebSimNode, clear: [Float], items: [WebDrawItem])
    }
}

/// One drawing into a surface (a layer or the canvas), in call order.
enum WebDrawItem: Hashable {
    /// `count` analytic shapes starting at instance `start`, under a blend
    /// mode (`WebBlend`).
    case shapes(start: Int, count: Int, blend: Int)
    /// `count` vertices of tessellated geometry starting at vertex `start`: a
    /// fill's triangles, or, with `fringe`, a stroke's edge-expanded bands with
    /// the AA coverage riding each vertex; under a blend mode.
    case triangles(start: Int, count: Int, fringe: Bool, blend: Int)
    /// `count` strokes (`fringe`) or fills as their points and styles: the
    /// records at float `start` of the source region, `floats` long, which
    /// the page expands into the vertices the Mac drew.
    case sources(start: Int, floats: Int, count: Int, fringe: Bool, blend: Int)
    /// A layer or a picture composited as `count` textured quads (six vertices
    /// each, from quad `quad`; more than one when symmetry replicated the
    /// draw), under a blend mode (`WebBlend`).
    case image(source: WebImageSource, quad: Int, count: Int, blend: Int)
    /// `count` glyph quads of atlas text (from quad `quad`, the tint carrying
    /// the fill), sampling atlas `atlas` of the recording, under a blend mode.
    case glyphs(atlas: Int, quad: Int, count: Int, blend: Int)
    /// `count` composed 2D fields (`drawSDF`) starting at group `start`, each a
    /// covering quad whose fragment walks the field's node program, under a
    /// blend mode.
    case groups(start: Int, count: Int, blend: Int)
    /// `count` raymarched 3D fields (`drawSDF3D`) starting at field `start`,
    /// each a fullscreen pass that sphere-traces the field through the frame's
    /// scene block and shades the hit under the finish whose rows sit at
    /// `material` in the parameter region, under a blend mode.
    case fields(start: Int, count: Int, blend: Int, material: Int)
}

enum WebImageSource: Hashable {
    /// Layer `index`'s content this frame.
    case layer(Int)
    /// Feedback layer `index`'s content last frame.
    case previous(Int)
    /// Picture `index` of the recording's assets.
    case picture(Int)
}

/// One fragment pass: the fragment by name, what it reads at texture 0
/// onward, and its rows in the vector. Two names are the page's own passes
/// rather than translated fragments: the Gaussian blur (its row is the sigma)
/// and the bloom (sigma, threshold, intensity), which the page runs as its
/// bright pass, its blur, and its add-back.
struct WebPassNode: Hashable {
    var fragment: String
    var inputs: [WebPassInput]
    var paramOffset: Int
    var paramRows: Int

    static let blur = "ollin_web_blur"
    static let bloom = "ollin_web_bloom"
    /// The translated fragments a page-owned pass runs beside its own blur.
    static let bloomFragments = ["ollin_fx_brightpass", "ollin_fx_bloom_combine"]
    var isPageOwned: Bool { fragment.hasPrefix("ollin_web_") }
}

enum WebPassInput: Hashable {
    case layer(Int)
    /// A lookup strip, by index into the recording's tables.
    case table(Int)
}

/// A single-field simulation as the page steps it.
struct WebSimNode: Hashable {
    var inject: String
    var step: String
    var substeps: Int
    /// The state a fresh field starts at.
    var rest: [Float]
    /// Rows (`ollin_sim_state_seed`'s seed and levels) for a field that starts
    /// as seeded noise instead, or empty.
    var seedFill: [Float]
    /// The sim's own rows, bound after the texel row.
    var paramOffset: Int
    var paramRows: Int
    /// The layer whose brightness re-tunes the step per texel, when the sim has
    /// a modulated variant and the map was drawn this frame.
    var modulation: Int?
    var modulatedStep: String?
}

/// The blend modes as the page numbers them.
enum WebBlend {
    static func index(of mode: BlendMode) -> Int {
        switch mode {
        case .normal: return 0
        case .add: return 1
        case .subtract: return 2
        case .multiply: return 3
        case .screen: return 4
        case .lightest: return 5
        case .darkest: return 6
        }
    }
}

/// One vertex of the triangle path on the wire: the `OllinVertex` fields the
/// page's vertex shader reads, as plain floats. The sketch-space position, the
/// AA coverage a fringe vertex carries (0 on a fill's, where the pipeline
/// ignores it), and the straight sRGB color with its alpha (a fringe vertex's
/// paint alpha; the fragment applies the perceptual coverage remap to the
/// coverage alone, as the Mac's does). A gradient on this path was baked into
/// the vertex colors on the Mac, so it crosses as they are.
enum WebVertex {
    static let floats = 7
    /// The leading fields that are the position, which the track carries
    /// exact; the rest are quantized.
    static let positionFloats = 2

    static func append(_ v: OllinVertex, into out: inout [Float]) {
        out.append(contentsOf: [v.position.x, v.position.y, v.aa.x,
                                v.color.x, v.color.y, v.color.z, v.color.w])
    }
}

/// A composed 2D field on the wire: the `SDFGroupInstance` fields the page's
/// group stage reads, as plain floats in the rows of four that stage reads them
/// by (the transform's axes; its translation with the center; the size with the
/// stroke width and the band width; the stroke slot; the fill gradient
/// geometry; the program's start and length with the fill kind and row; the
/// stroke kind and row), the program renumbered to where it sits in the frame's
/// node region and the gradient rows into the recording's strip.
enum WebGroup {
    static let floats = 26
    /// The program's start and length: columns that name the cast.
    static let structuralColumns = [20, 21]

    static func append(_ g: SDFGroupInstance, nodeStart: Int, fillRow: Float, strokeRow: Float,
                       into out: inout [Float]) {
        let t = g.transform
        out.append(contentsOf: [
            t.columns.0.x, t.columns.0.y, t.columns.1.x, t.columns.1.y,
            t.columns.2.x, t.columns.2.y, g.center.x, g.center.y,
            g.size.x, g.size.y, g.strokeWidth, g.bandWidth,
            g.strokeColor.x, g.strokeColor.y, g.strokeColor.z, g.strokeColor.w,
            g.fillGradientGeo.x, g.fillGradientGeo.y, g.fillGradientGeo.z, g.fillGradientGeo.w,
            Float(nodeStart), Float(g.nodeCount), g.fillGradientKind, fillRow,
            g.strokeGradientKind, strokeRow,
        ])
    }
}

/// One instruction of a composed 2D field on the wire: the `SDFNode` record as
/// four rows of four floats, the way the page's uniform block holds it (the
/// kind and the op as floats, exact at their small values).
enum WebNode {
    static let floats = 16
    static let structuralColumns = [0, 1]

    static func append(_ n: SDFNode, into out: inout [Float]) {
        out.append(contentsOf: [
            Float(n.kind), Float(n.sel), n.k, n.extra,
            n.color.x, n.color.y, n.color.z, n.color.w,
            n.geo0.x, n.geo0.y, n.geo0.z, n.geo0.w,
            n.geo1.x, n.geo1.y, n.geo1.z, n.geo1.w,
        ])
    }
}

/// A raymarched 3D field on the wire: the `SDF3DGroupInstance` fields the
/// page's field pass reads, as plain floats: the inverse model matrix by
/// columns, the world bounds with the model scale and the unbounded flag, the
/// screen-space gradient geometry, the program's place in the frame's 3D node
/// region, the paint kind and its row in the recording's strip, and the normal
/// step a fractal leaf asked for.
enum WebField {
    static let floats = 36
    /// The unbounded flag and the program's start and length.
    static let structuralColumns = [23, 28, 29]

    static func append(_ f: SDF3DGroupInstance, nodeStart: Int, fillRow: Float, into out: inout [Float]) {
        let m = f.inverseModel
        for column in [m.columns.0, m.columns.1, m.columns.2, m.columns.3] {
            out.append(contentsOf: [column.x, column.y, column.z, column.w])
        }
        out.append(contentsOf: [
            f.boundsMin.x, f.boundsMin.y, f.boundsMin.z, f.modelScale,
            f.boundsMax.x, f.boundsMax.y, f.boundsMax.z, f.unbounded,
            f.fillGradientGeo.x, f.fillGradientGeo.y, f.fillGradientGeo.z, f.fillGradientGeo.w,
            Float(nodeStart), Float(f.nodeCount), f.fillGradientKind, fillRow,
            f.normalEpsilon, 0, 0, 0,
        ])
    }
}

/// One instruction of a raymarched 3D field on the wire, laid out as `WebNode`.
enum WebNode3D {
    static let floats = 16
    static let structuralColumns = [0, 1]

    static func append(_ n: SDFNode3D, into out: inout [Float]) {
        out.append(contentsOf: [
            Float(n.kind), Float(n.sel), n.k, n.extra,
            n.color.x, n.color.y, n.color.z, n.color.w,
            n.geo0.x, n.geo0.y, n.geo0.z, n.geo0.w,
            n.geo1.x, n.geo1.y, n.geo1.z, n.geo1.w,
        ])
    }
}

/// The finish of a field batch as the page's rows: the four tinted layers, then
/// the scalars the lighting reads. Nine rows of four.
enum WebMaterial {
    static let rows = 9

    static func rows(of m: OllinMaterial) -> [SIMD4<Float>] {
        [
            m.rimColor, m.subsurfaceColor, m.goochWarm, m.goochCool, m.sparkleColor,
            SIMD4(m.specular, m.specularSharpness, m.iridescence, m.iridescenceScale),
            SIMD4(m.rimSharpness, m.toonBands, Float(m.shadingModel), m.metallic),
            SIMD4(m.roughness, m.sparkleSize, m.sparkleSharpness, m.f0),
            SIMD4(m.iridescenceFlow, m.iridescencePhase, m.iridescenceFlowSize, 0),
        ]
    }

    /// What the page's lighting cannot shade on a field, by name, or `nil`.
    static func refusal(for m: OllinMaterial) -> String? {
        if m.shadingModel == 3 {
            if m.transmission > 0 { return "a transmissive (glass) finish on a raymarched field" }
            if m.clearcoat > 0 { return "a clear-coated finish on a raymarched field" }
            if m.sheenColor.x + m.sheenColor.y + m.sheenColor.z > 0 { return "a sheened finish on a raymarched field" }
            if m.thinFilm > 0 { return "a thin-film finish on a raymarched field" }
            if m.anisotropy.x != 0 { return "a brushed (anisotropic) finish on a raymarched field" }
        }
        if m.scatterStrength > 0 { return "a scattering finish on a raymarched field" }
        return nil
    }
}

/// An image quad on the wire: six vertices of position, uv, and tint.
enum WebQuad {
    static let vertices = 6
    static let floats = 6 * 8

    static func append(_ v: [OllinImageVertex], into out: inout [Float]) {
        for vertex in v {
            out.append(contentsOf: [vertex.position.x, vertex.position.y, vertex.uv.x, vertex.uv.y,
                                    vertex.tint.x, vertex.tint.y, vertex.tint.z, vertex.tint.w])
        }
    }
}

/// A user shader as the page compiles it: the resolved Metal source, how many
/// layers it reads, and the library sections it asked for.
struct WebUserShader: Hashable {
    var source: String
    /// 0 a generator, 1 a filter, 2 a combine.
    var variant: Int
    var modules: Int
    /// The file the source came from, for a diagnostic.
    var name: String
}

// MARK: - The recorder

/// Reads one frame's pass graph and float vector off the drawer after
/// `performDraw()`. Held across the frames of a recording, since a persistent
/// layer keeps its key, a table travels once, a user shader compiles once, a
/// picture travels once however often it is drawn, a gradient row is baked
/// once, and an atlas page is read at the end, when every glyph the frames
/// used is on it.
final class WebGraphRecorder {
    private(set) var tables: [[SIMD4<Float>]] = []
    private(set) var shaders: [WebUserShader] = []
    private var keys: [ObjectIdentifier: Int] = [:]

    /// The pictures the frames draw, each once, in first-use order.
    private(set) var pictures: [WebPicture] = []
    private struct PictureEntry {
        weak var image: Image?
        var generation: Int
        var index: Int
    }
    private var pictureEntries: [ObjectIdentifier: PictureEntry] = [:]

    /// The atlases the frames draw through, in first-use order, with the page
    /// generation each was first seen at.
    private var atlasList: [(atlas: GlyphAtlas, generation: Int)] = []
    private var atlasIndex: [ObjectIdentifier: Int] = [:]

    /// The gradient rows the frames' shapes read, each once: a frame's own row
    /// table is per frame and in first-use order, so the recorder renumbers
    /// each instance's rows into this one table, which the page uploads as
    /// its strip.
    private(set) var gradientRows: [[UInt8]] = []
    private var gradientRowIndex: [[UInt8]: Int] = [:]

    /// Whether a frame marched a field under a physically-based finish, so the
    /// page needs the split-sum table that finish prices its energy against.
    private(set) var usesPhysicallyBasedField = false

    /// Resolves a `.default` quality the way an export does.
    static func exportQuality(_ q: RenderQuality) -> RenderQuality { q == .default ? .detail : q }

    /// The atlas assets, read once the frames are all recorded, so each page
    /// holds every glyph they drew. Throws when a page was rebuilt during the
    /// recording (an earlier frame's quads then address glyphs that moved).
    func finish(frame: Int) throws -> [WebAtlas] {
        try atlasList.map { entry in
            guard entry.atlas.generation == entry.generation else {
                throw WebExportRefusal(call: "drawText through a glyph atlas that filled up and was rebuilt during the recording", frame: frame)
            }
            let page = entry.atlas.webPage()
            guard let asset = WebAssetEncoder.atlas(page: page.bytes, size: GlyphAtlas.webPageSize, rows: page.rows) else {
                throw WebExportRefusal(call: "drawText (the glyph atlas could not be encoded)", frame: frame)
            }
            return asset
        }
    }

    private func pictureIndex(_ image: Image, frame: Int) throws -> Int {
        let id = ObjectIdentifier(image)
        if let entry = pictureEntries[id], entry.image === image, entry.generation == image.pixelGeneration {
            return entry.index
        }
        guard let picture = WebAssetEncoder.picture(of: image) else {
            throw WebExportRefusal(call: "drawImage of a live texture (a camera, a video, a compute texture)", frame: frame)
        }
        let index: Int
        if let found = pictures.firstIndex(of: picture) { index = found }
        else { pictures.append(picture); index = pictures.count - 1 }
        pictureEntries[id] = PictureEntry(image: image, generation: image.pixelGeneration, index: index)
        return index
    }

    private func atlasIndex(_ atlas: GlyphAtlas) -> Int {
        let id = ObjectIdentifier(atlas)
        if let i = atlasIndex[id] { return i }
        atlasList.append((atlas, atlas.generation))
        atlasIndex[id] = atlasList.count - 1
        return atlasList.count - 1
    }

    private func gradientRow(_ row: [UInt8]) -> Int {
        if let i = gradientRowIndex[row] { return i }
        gradientRows.append(row)
        gradientRowIndex[row] = gradientRows.count - 1
        return gradientRows.count - 1
    }

    func capture(_ drawer: Drawer, frame: Int, width canvasWidth: Int, height canvasHeight: Int) throws -> WebFrame {
        func refuse(_ call: String) -> WebExportRefusal { WebExportRefusal(call: call, frame: frame) }
        if !drawer.dispatches.isEmpty {
            throw refuse("compute work (a simulation or GPU particles)")
        }
        // The frame's gradient rows renumbered into the recording's table.
        let frameRows = drawer.gradientRows.map { gradientRow($0) }

        var vector: [Float] = []
        var instanceCount = 0
        var quadCount = 0
        var quads: [Float] = []
        var groupCount = 0
        var groups: [Float] = []
        var nodeCount = 0
        var nodes: [Float] = []
        var fieldCount = 0
        var fields: [Float] = []
        var node3DCount = 0
        var nodes3D: [Float] = []
        var vertexCount = 0
        var vertices: [Float] = []
        var sources: [Float] = []
        var params: [Float] = []

        // The layers, in the order the renderer fills them: generators, drawn
        // targets, feedback, fields, then the filter and combine outputs in
        // record order. Every target gets its index first, so an item drawn
        // into one layer can name another wherever it sits.
        var ordered: [RenderTarget] = []
        for target in drawer.renderTargets { if case .generator = target.origin { ordered.append(target) } }
        for target in drawer.renderTargets { if case .ocean = target.origin { throw refuse("an ocean field") } }
        for target in drawer.renderTargets { if case .accumulate = target.origin { throw refuse("an accumulator (a running mean of light)") } }
        for target in drawer.renderTargets { if case .geometry = target.origin { ordered.append(target) } }
        for target in drawer.renderTargets { if case .feedback = target.origin { ordered.append(target) } }
        for target in drawer.renderTargets { if case .simField = target.origin { ordered.append(target) } }
        for output in drawer.filterOps { ordered.append(output) }
        var index: [ObjectIdentifier: Int] = [:]
        var previousOf: [ObjectIdentifier: Int] = [:]
        for (i, target) in ordered.enumerated() {
            index[ObjectIdentifier(target)] = i
            if case let .feedback(fb) = target.origin { previousOf[ObjectIdentifier(fb.previousLayer)] = i }
        }

        // The batches tagged for each surface, in call order.
        let batches = drawer.batches
        func nextStart(_ i: Int, _ key: KeyPath<GeometryBatch, Int>, end: Int) -> Int {
            i + 1 < batches.count ? batches[i + 1][keyPath: key] : end
        }
        /// What a `drawImage` quad samples: a layer the frame filled, a feedback
        /// layer's last frame, or a picture carried as an asset.
        func imageSource(_ image: Image) throws -> WebImageSource {
            if let target = image.webRenderTarget {
                if let li = index[ObjectIdentifier(target)] { return .layer(li) }
                if let pi = previousOf[ObjectIdentifier(target)] { return .previous(pi) }
                throw refuse("drawImage of a layer the frame did not fill (a depth or normal layer)")
            }
            return .picture(try pictureIndex(image, frame: frame))
        }
        /// Appends a run of image or glyph quads to the quad region, placed by
        /// `transform` when a recording replays them, and returns how many.
        func appendQuads(_ run: ArraySlice<OllinImageVertex>, transform: matrix_float3x3?, call: String) throws -> Int {
            guard run.count % WebQuad.vertices == 0 else { throw refuse("\(call) (a run of \(run.count) vertices)") }
            for vertex in run {
                var placed = vertex
                if let t = transform {
                    let p = t * SIMD3<Float>(vertex.position.x, vertex.position.y, 1)
                    placed.position = SIMD2<Float>(p.x, p.y)
                }
                WebQuad.append([placed], into: &quads)
            }
            let count = run.count / WebQuad.vertices
            quadCount += count
            return count
        }
        /// A gradient row of the frame's (or a recording's) table renumbered into
        /// the recording's strip.
        func row(_ local: Float, in rows: [Int]) throws -> Float {
            let i = Int(local.rounded())
            guard i >= 0, i < rows.count else { throw refuse("a gradient whose row the frame did not bake") }
            return Float(rows[i])
        }
        /// Appends a composed 2D field and, once per source program, its
        /// instructions; `placed` names where the program landed in the frame's
        /// node region, so a symmetry copy or a replayed recording shares it.
        var placedPrograms: [ObjectIdentifier: [Int: Int]] = [:]
        func appendGroup(_ g: SDFGroupInstance, transform: matrix_float3x3?, program: [SDFNode],
                         source: AnyObject, rows: [Int]) throws {
            let ns = Int(g.nodeStart), nc = Int(g.nodeCount)
            guard nc > 0, ns >= 0, ns + nc <= program.count else {
                throw refuse("drawSDF (a field whose program the frame did not hold)")
            }
            let key = ObjectIdentifier(source)
            let local: Int
            if let found = placedPrograms[key]?[ns] {
                local = found
            } else {
                local = nodeCount
                for node in program[ns ..< ns + nc] { WebNode.append(node, into: &nodes); nodeCount += 1 }
                placedPrograms[key, default: [:]][ns] = local
            }
            var placed = g
            if let t = transform { placed.transform = t * g.transform }
            let fillRow = g.fillGradientKind != 0 ? try row(g.fillGradientRow, in: rows) : 0
            let strokeRow = g.strokeGradientKind != 0 ? try row(g.strokeGradientRow, in: rows) : 0
            WebGroup.append(placed, nodeStart: local, fillRow: fillRow, strokeRow: strokeRow, into: &groups)
            groupCount += 1
        }
        /// Appends a raymarched 3D field and its instructions the same way.
        var placedPrograms3D: [Int: Int] = [:]
        func appendField(_ f: SDF3DGroupInstance, rows: [Int]) throws {
            let ns = Int(f.nodeStart), nc = Int(f.nodeCount)
            guard nc > 0, ns >= 0, ns + nc <= drawer.sdf3DNodes.count else {
                throw refuse("drawSDF3D (a field whose program the frame did not hold)")
            }
            let local: Int
            if let found = placedPrograms3D[ns] {
                local = found
            } else {
                local = node3DCount
                for node in drawer.sdf3DNodes[ns ..< ns + nc] { WebNode3D.append(node, into: &nodes3D); node3DCount += 1 }
                placedPrograms3D[ns] = local
            }
            let fillRow = f.fillGradientKind != 0 ? try row(f.fillGradientRow, in: rows) : 0
            WebField.append(f, nodeStart: local, fillRow: fillRow, into: &fields)
            fieldCount += 1
        }
        /// Appends the vertices `[from, to)` of `list`, placed by `transform`,
        /// as a vertex item, or nothing for an empty run.
        func appendVertices(_ list: [OllinVertex], from: Int, to: Int, transform: matrix_float3x3?,
                            fringe: Bool, blend: Int) -> WebDrawItem? {
            guard to > from else { return nil }
            let start = vertexCount
            for vertex in list[from ..< to] {
                var placed = vertex
                if let t = transform {
                    let p = t * SIMD3<Float>(vertex.position.x, vertex.position.y, 1)
                    placed.position = SIMD2<Float>(p.x, p.y)
                }
                WebVertex.append(placed, into: &vertices)
                vertexCount += 1
            }
            return .triangles(start: start, count: vertexCount - start, fringe: fringe, blend: blend)
        }
        /// The items of one triangle or fringe run `[from, to)` over `list`:
        /// the strokes and fills the drawer kept as their points (`recorded`,
        /// in vertex order) travel as source records, consecutive ones in one
        /// item, and whatever between them was expanded by a path that keeps
        /// no source (a glyph's outline, a fill under a gradient) travels as
        /// its vertices, in the order it was drawn.
        func appendRun(_ list: [OllinVertex], from: Int, to: Int, recorded: [WebSource],
                       transform: matrix_float3x3?, fringe: Bool, blend: Int, into items: inout [WebDrawItem]) {
            // The first record inside the run, by binary search on the sorted starts.
            var lo = 0, hi = recorded.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if recorded[mid].vertexRange.lowerBound < from { lo = mid + 1 } else { hi = mid }
            }
            var at = from
            var index = lo
            while index < recorded.count, recorded[index].vertexRange.lowerBound < to {
                let source = recorded[index]
                index += 1
                let range = source.vertexRange
                guard range.lowerBound >= at, range.upperBound <= to, !range.isEmpty else { continue }
                if let item = appendVertices(list, from: at, to: range.lowerBound, transform: transform,
                                             fringe: fringe, blend: blend) {
                    items.append(item)
                }
                let offset = sources.count
                source.encode(into: &sources, under: transform)
                if case let .sources(start, floats, count, f, b)? = items.last, f == fringe, b == blend, start + floats == offset {
                    items[items.count - 1] = .sources(start: start, floats: sources.count - start, count: count + 1,
                                                      fringe: fringe, blend: blend)
                } else {
                    items.append(.sources(start: offset, floats: sources.count - offset, count: 1, fringe: fringe, blend: blend))
                }
                at = range.upperBound
            }
            if let item = appendVertices(list, from: at, to: to, transform: transform, fringe: fringe, blend: blend) {
                items.append(item)
            }
        }
        func items(for surface: RenderTarget?) throws -> [WebDrawItem] {
            var items: [WebDrawItem] = []
            for (i, batch) in batches.enumerated() where batch.target === surface {
                if batch.kind == .clipPush || batch.kind == .clipPop || batch.clipLevel > 0 { throw refuse("withClip") }
                if batch.depth != nil { throw refuse("depth(at:)") }
                let blend = WebBlend.index(of: batch.blendMode)
                switch batch.kind {
                case .sdf:
                    let end = nextStart(i, \.instanceStart, end: drawer.sdfInstances.count)
                    let start = instanceCount
                    for instance in drawer.sdfInstances[batch.instanceStart ..< end] {
                        try Self.appendInstance(instance, rows: frameRows, into: &vector, frame: frame)
                        instanceCount += 1
                    }
                    if instanceCount > start { items.append(.shapes(start: start, count: instanceCount - start, blend: blend)) }
                case .triangles, .fringe:
                    // A fill's triangles or a stroke's fringe bands: the strokes
                    // and fills as their points where the drawer kept them, the
                    // rest of the run vertex for vertex.
                    let end = nextStart(i, \.vertexStart, end: drawer.vertices.count)
                    appendRun(drawer.vertices, from: batch.vertexStart, to: end, recorded: drawer.webSources,
                              transform: nil, fringe: batch.kind == .fringe, blend: blend, into: &items)
                case .retained:
                    // A recording of shapes, strokes, and fills replays as its
                    // own runs, the draw-time transform composed onto each shape's
                    // own and applied to each vertex, as the replay's vertex
                    // stages do.
                    guard let recording = batch.retained else { continue }
                    let inner = recording.innerBatches
                    let simple = recording.points.isEmpty
                        && inner.allSatisfy {
                            ($0.kind == .sdf || $0.kind == .triangles || $0.kind == .fringe
                             || $0.kind == .image || $0.kind == .glyphAtlas || $0.kind == .sdfGroup) && $0.depth == nil
                        }
                    guard simple else { throw refuse("drawBatch (a recording holding more than shapes, strokes, fills, pictures, text, and composed fields)") }
                    // The recording's rows are its own table, renumbered like a frame's.
                    let recordingRows = recording.gradientRows.map { gradientRow($0) }
                    for (j, run) in inner.enumerated() {
                        let next = j + 1 < inner.count ? inner[j + 1] : nil
                        let runBlend = WebBlend.index(of: run.blendMode)
                        switch run.kind {
                        case .sdf:
                            let end = next?.instanceStart ?? recording.sdfInstances.count
                            let start = instanceCount
                            for instance in recording.sdfInstances[run.instanceStart ..< end] {
                                var placed = instance
                                if let t = batch.retainedTransform { placed.transform = t * instance.transform }
                                try Self.appendInstance(placed, rows: recordingRows, into: &vector, frame: frame)
                                instanceCount += 1
                            }
                            if instanceCount > start {
                                items.append(.shapes(start: start, count: instanceCount - start, blend: runBlend))
                            }
                        case .triangles, .fringe:
                            // The recording's strokes and fills as their points
                            // under the draw-time transform, the rest as vertices.
                            let end = next?.vertexStart ?? recording.vertices.count
                            appendRun(recording.vertices, from: run.vertexStart, to: end, recorded: recording.webSources,
                                      transform: batch.retainedTransform, fringe: run.kind == .fringe,
                                      blend: runBlend, into: &items)
                        case .image:
                            guard let image = run.image else { continue }
                            let end = next?.imageStart ?? recording.imageVertices.count
                            let slice = recording.imageVertices[run.imageStart ..< end]
                            guard !slice.isEmpty else { continue }
                            let source = try imageSource(image)
                            let start = quadCount
                            let count = try appendQuads(slice, transform: batch.retainedTransform, call: "drawImage")
                            items.append(.image(source: source, quad: start, count: count, blend: runBlend))
                        case .glyphAtlas:
                            guard let atlas = run.atlas else { continue }
                            let end = next?.glyphStart ?? recording.glyphVertices.count
                            let slice = recording.glyphVertices[run.glyphStart ..< end]
                            guard !slice.isEmpty else { continue }
                            let ai = atlasIndex(atlas)
                            let start = quadCount
                            let count = try appendQuads(slice, transform: batch.retainedTransform, call: "drawText")
                            items.append(.glyphs(atlas: ai, quad: start, count: count, blend: runBlend))
                        case .sdfGroup:
                            let end = next?.sdfGroupStart ?? recording.sdfGroups.count
                            let start = groupCount
                            for group in recording.sdfGroups[run.sdfGroupStart ..< end] {
                                try appendGroup(group, transform: batch.retainedTransform, program: recording.sdfNodes,
                                                source: recording, rows: recordingRows)
                            }
                            if groupCount > start {
                                items.append(.groups(start: start, count: groupCount - start, blend: runBlend))
                            }
                        default:
                            continue
                        }
                    }
                case .image:
                    // A layer's image or a picture: the quads the draw recorded
                    // (one, or one per symmetry copy), sampling the layer this
                    // frame or the picture carried once as an asset.
                    guard let image = batch.image else { continue }
                    let end = nextStart(i, \.imageStart, end: drawer.imageVertices.count)
                    let slice = drawer.imageVertices[batch.imageStart ..< end]
                    guard !slice.isEmpty else { continue }
                    let source = try imageSource(image)
                    let start = quadCount
                    let count = try appendQuads(slice, transform: nil, call: "drawImage")
                    items.append(.image(source: source, quad: start, count: count, blend: blend))
                case .glyphAtlas:
                    // Atlas text: one quad per glyph, the tint its fill, sampling
                    // the font's page, which the recording carries once at the end.
                    guard let atlas = batch.atlas else { continue }
                    let end = nextStart(i, \.glyphStart, end: drawer.glyphVertices.count)
                    let slice = drawer.glyphVertices[batch.glyphStart ..< end]
                    guard !slice.isEmpty else { continue }
                    let ai = atlasIndex(atlas)
                    let start = quadCount
                    let count = try appendQuads(slice, transform: nil, call: "drawText")
                    items.append(.glyphs(atlas: ai, quad: start, count: count, blend: blend))
                case .sdfGroup:
                    // A composed field: its covering quad and its program, the
                    // program once per `drawSDF` however many symmetry copies
                    // share it.
                    let end = nextStart(i, \.sdfGroupStart, end: drawer.sdfGroups.count)
                    let start = groupCount
                    for group in drawer.sdfGroups[batch.sdfGroupStart ..< end] {
                        try appendGroup(group, transform: nil, program: drawer.sdfNodes, source: drawer, rows: frameRows)
                    }
                    if groupCount > start { items.append(.groups(start: start, count: groupCount - start, blend: blend)) }
                case .sdfGroup3D:
                    // A raymarched field on the canvas (a layer that carries depth
                    // was refused above): the fields, their programs, and the
                    // batch's finish as rows the page's lighting reads.
                    if let name = WebMaterial.refusal(for: batch.finish) { throw refuse(name) }
                    if batch.finish.shadingModel == 3 { usesPhysicallyBasedField = true }
                    let end = nextStart(i, \.sdf3DGroupStart, end: drawer.sdf3DGroups.count)
                    let start = fieldCount
                    let material = rows(WebMaterial.rows(of: batch.finish))
                    for field in drawer.sdf3DGroups[batch.sdf3DGroupStart ..< end] {
                        try appendField(field, rows: frameRows)
                    }
                    if fieldCount > start {
                        items.append(.fields(start: start, count: fieldCount - start, blend: blend, material: material.offset))
                    }
                default:
                    throw refuse(OllinApp.webRefusalName(for: batch.kind))
                }
            }
            return items
        }

        func rows(_ p: [SIMD4<Float>]) -> (offset: Int, rows: Int) {
            let offset = params.count
            for row in p { params.append(contentsOf: [row.x, row.y, row.z, row.w]) }
            return (offset, p.count)
        }
        func clearOf(_ target: RenderTarget) -> [Float] {
            let c = target.clearColor
            return [Float(Color.srgbToLinear(c.red)), Float(Color.srgbToLinear(c.green)),
                    Float(Color.srgbToLinear(c.blue)), Float(c.alpha)]
        }
        func layerIndex(_ target: RenderTarget) throws -> Int {
            guard let i = index[ObjectIdentifier(target)] else {
                throw refuse("a layer read before the frame filled it")
            }
            return i
        }
        func node(_ pass: EffectPass) -> WebPassNode {
            var inputs: [WebPassInput] = []
            for input in pass.inputs {
                switch input {
                case .layer(let i): inputs.append(.layer(i))
                case .table(let samples): inputs.append(.table(tableIndex(samples)))
                }
            }
            let r = rows(pass.params)
            return WebPassNode(fragment: pass.fragment, inputs: inputs, paramOffset: r.offset, paramRows: r.rows)
        }
        func userIndex(_ shader: Shader, variant: Int) throws -> (Int, (offset: Int, rows: Int)) {
            let resolved: (source: String, problems: [String])
            if !shader.source.isEmpty {
                let r = ShaderIncludes.resolveFromFilesystem(shader.source, name: shader.sourceFile,
                                                             startLine: shader.diagnosticStartLine)
                resolved = (r.source, r.problems)
            } else if !shader.resourcePath.isEmpty {
                let content = (try? String(contentsOfFile: shader.resourcePath, encoding: .utf8)) ?? ""
                let r = ShaderIncludes.resolveFromFilesystem(content, name: shader.resourcePath)
                resolved = (r.source, r.problems)
            } else {
                throw refuse("a Shader with no source")
            }
            if !resolved.problems.isEmpty {
                throw refuse("a Shader whose include could not be read (\(resolved.problems.joined(separator: "; ")))")
            }
            let user = WebUserShader(source: resolved.source, variant: variant, modules: shader.modules.rawValue,
                                     name: shader.diagnosticSourceName)
            let i: Int
            if let found = shaders.firstIndex(of: user) { i = found } else { shaders.append(user); i = shaders.count - 1 }
            let count = min(shader.params.count, Int(OLLIN_SHADER_PARAM_COUNT))
            let rowCount = (count + 3) / 4
            var rowsOut: [SIMD4<Float>] = Array(shader.paddedParams.prefix(rowCount))
            if rowsOut.isEmpty { rowsOut = [] }
            return (i, rows(rowsOut))
        }
        func persistentKey(_ object: AnyObject) -> Int {
            let id = ObjectIdentifier(object)
            if let k = keys[id] { return k }
            let k = keys.count
            keys[id] = k
            return k
        }

        var layers: [WebLayer] = []
        for target in ordered {
            if target.needsDepth { throw refuse("3D drawing inside a layer") }
            if target.needsStencil { throw refuse("withClip inside a layer") }
            if target.depthLayer != nil || target.normalLayer != nil { throw refuse("a layer's depth") }
            let pw = target.pixelWidth, ph = target.pixelHeight
            var layer = WebLayer(key: -1, width: target.width, height: target.height,
                                 pixelWidth: pw, pixelHeight: ph, kind: .geometry(clear: [], items: []))
            switch target.origin {
            case .geometry:
                layer.kind = .geometry(clear: clearOf(target), items: try items(for: target))
            case .generator(let generator):
                if case let .shader(shader) = generator.kind {
                    let (si, r) = try userIndex(shader, variant: 0)
                    layer.kind = .user(shader: si, inputs: [], paramOffset: r.offset, paramRows: r.rows)
                } else if let pass = generator.pass(width: pw, height: ph) {
                    layer.kind = .generator(node(pass))
                } else {
                    throw refuse("a generator the page cannot carry")
                }
            case let .filter(input, filter):
                let li = try layerIndex(input)
                if case let .shader(shader) = filter.kind {
                    let (si, r) = try userIndex(shader, variant: 1)
                    layer.kind = .user(shader: si, inputs: [li], paramOffset: r.offset, paramRows: r.rows)
                } else if let pass = filter.singlePass(width: pw, height: ph, resolve: Self.exportQuality) {
                    layer.kind = .filter(input: li, node(pass))
                } else if case let .gaussianBlur(radius) = filter.kind {
                    // The Mac runs a hardware Gaussian; the page runs its own
                    // separable one over the same sigma (see `WebPlayer`).
                    let r = rows([SIMD4(Float(max(0.1, radius)), 0, 0, 0)])
                    layer.kind = .filter(input: li, WebPassNode(fragment: WebPassNode.blur, inputs: [.layer(0)],
                                                                paramOffset: r.offset, paramRows: r.rows))
                } else if case let .bloom(threshold, intensity, radius) = filter.kind {
                    let r = rows([SIMD4(Float(max(0.1, radius)), Float(threshold), Float(intensity), 0)])
                    layer.kind = .filter(input: li, WebPassNode(fragment: WebPassNode.bloom, inputs: [.layer(0)],
                                                                paramOffset: r.offset, paramRows: r.rows))
                } else {
                    throw refuse("the \(Self.caseName(filter.kind)) filter")
                }
            case let .combine(base, aux, op):
                let bi = try layerIndex(base), ai = try layerIndex(aux)
                if case let .shader(shader) = op.kind {
                    let (si, r) = try userIndex(shader, variant: 2)
                    layer.kind = .user(shader: si, inputs: [bi, ai], paramOffset: r.offset, paramRows: r.rows)
                } else if let pass = op.singlePass(width: pw, height: ph, resolve: Self.exportQuality) {
                    layer.kind = .combine(base: bi, aux: ai, node(pass))
                } else {
                    throw refuse("the \(Self.caseName(op.kind)) combine")
                }
            case .feedback(let fb):
                layer.key = persistentKey(fb)
                layer.kind = .feedback(clear: clearOf(target), items: try items(for: target))
            case .simField(let field):
                let sim = field.sim
                if sim.fluidConfig != nil || sim.watercolorConfig != nil || sim.selfWarpConfig != nil
                    || sim.turingConfig != nil || sim.stepFragment.isEmpty {
                    throw refuse("the \(Self.caseName(sim.kind)) simulation")
                }
                layer.key = persistentKey(field)
                var modulation: Int? = nil
                if let map = field.modulation, sim.modulatedStepFragment != nil,
                   drawer.renderTargets.contains(where: { $0 === map }) {
                    modulation = try layerIndex(map)
                }
                let r = rows(sim.params)
                let rest = sim.restState
                var seedFill: [Float] = []
                if let fill = sim.stateSeedFill { seedFill = [Float(fill.seed), Float(fill.levels)] }
                let simNode = WebSimNode(inject: sim.injectFragment, step: sim.stepFragment,
                                         substeps: max(1, sim.substeps),
                                         rest: [rest.x, rest.y, rest.z, rest.w], seedFill: seedFill,
                                         paramOffset: r.offset, paramRows: r.rows,
                                         modulation: modulation,
                                         modulatedStep: modulation == nil ? nil : sim.modulatedStepFragment)
                layer.kind = .sim(simNode, clear: clearOf(target), items: try items(for: target))
            case .ocean:
                throw refuse("an ocean field")
            case .accumulate:
                throw refuse("an accumulator (a running mean of light)")
            }
            layers.append(layer)
        }

        let canvas = try items(for: nil)

        var frameFilters: [WebPassNode] = []
        for filter in drawer.frameFilters {
            if case .shader = filter.kind { throw refuse("postProcess(.shader)") }
            guard let pass = filter.singlePass(width: canvasWidth, height: canvasHeight,
                                               resolve: Self.exportQuality) else {
                throw refuse("postProcess(.\(Self.caseName(filter.kind)))")
            }
            frameFilters.append(node(pass))
        }

        // The scene the fields are marched through: the camera, the lights, and
        // the march budget, read the way the export's renderer would set them.
        let scene = fieldCount > 0 ? try Self.sceneBlock(drawer, width: canvasWidth, height: canvasHeight, frame: frame) : []

        // The vector: the shapes already appended, then the quads, the fields
        // and their programs, the vertices, and the rows.
        vector.append(contentsOf: quads)
        vector.append(contentsOf: groups)
        vector.append(contentsOf: nodes)
        vector.append(contentsOf: fields)
        vector.append(contentsOf: nodes3D)
        vector.append(contentsOf: sources)
        vector.append(contentsOf: vertices)
        vector.append(contentsOf: params)
        guard let structure = sources.withUnsafeBufferPointer({ WebSourceLayout.structure(of: $0) }) else {
            throw refuse("a stroke or a fill whose record the page could not read")
        }
        let graph = WebGraph(layers: layers, canvas: canvas, frameFilters: frameFilters,
                             instanceCount: instanceCount, quadCount: quadCount,
                             groupCount: groupCount, nodeCount: nodeCount,
                             fieldCount: fieldCount, node3DCount: node3DCount,
                             sourceFloats: sources.count, sourceStructure: structure.columns,
                             vertexCount: vertexCount, paramFloats: params.count)

        // The ordinary frame clears to the background; an accumulating one only
        // when the sketch asked for a wipe. The first frame always clears, since
        // a fresh surface starts at the background color.
        let clears = frame == 0 || !drawer.accumulates || drawer.backgroundSetThisFrame
        let bg = drawer.backgroundColor
        let clear: SIMD3<Float>? = clears
            ? SIMD3<Float>(Float(Color.srgbToLinear(bg.red)), Float(Color.srgbToLinear(bg.green)),
                           Float(Color.srgbToLinear(bg.blue)))
            : nil
        return WebFrame(clear: clear, vector: vector, graph: graph,
                        toneMapMode: Int(drawer.toneMapMode.shaderIndex),
                        exposure: Float(drawer.toneMapExposure), scene: scene)
    }

    /// The layout of a frame's scene block, the floats the field pass reads
    /// whole: the three camera matrices by columns, then four rows (the
    /// viewport and the two step budgets; the march scale with the reduced
    /// pass's size and the scene scale; the ambient; the eye with the lit flag),
    /// then a row of counts, then `WebScene.lightFloats` per light and one row
    /// per caster.
    enum WebScene {
        static let headerFloats = 48 + 4 * 5
        static let lightFloats = 20
        static let casterFloats = 4
    }

    /// The scene block of a frame that marches a field: what `Uniforms3D` and
    /// `OllinLighting` would carry for the export's renderer, as far as the
    /// page's lighting reaches, and a refusal by name for what it does not (an
    /// environment, fog, an area light, a shaped light, the traced and
    /// screen-space passes). The march budget resolves as the export resolves
    /// it, `.default` lifted to `.detail`; a reduced march resolution keeps the
    /// coverage-adaptive scale the Mac would trace at, so the page marches the
    /// same pixels and upsamples them the same way.
    static func sceneBlock(_ drawer: Drawer, width: Int, height: Int, frame: Int) throws -> [Float] {
        func refuse(_ call: String) -> WebExportRefusal { WebExportRefusal(call: call, frame: frame) }
        guard let camera = drawer.camera3D else { throw refuse("drawSDF3D without a camera") }
        if drawer.environment != nil { throw refuse("an environment (image-based lighting) on a raymarched field") }
        if drawer.contactShadowsEnabled { throw refuse("contactShadows() on a raymarched field") }
        if drawer.globalIlluminationEnabled { throw refuse("globalIllumination() on a raymarched field") }
        if drawer.rayTracedReflectionsEnabled { throw refuse("rayTracedReflections() on a raymarched field") }
        if drawer.sceneThroughGlassEnabled { throw refuse("sceneThroughGlass() on a raymarched field") }
        if drawer.causticsEnabled { throw refuse("caustics() on a raymarched field") }
        let lighting = drawer.makeLighting()
        if lighting.fogColor.w > 0 { throw refuse("fog or aerial perspective around a raymarched field") }
        if !drawer.usedIESProfiles.isEmpty || !drawer.usedLightCookies.isEmpty {
            throw refuse("a light profile or cookie on a raymarched field")
        }
        let lightCount = Int(lighting.lightCount)
        let lights: [OllinLight] = withUnsafePointer(to: lighting.lights) { ptr in
            ptr.withMemoryRebound(to: OllinLight.self, capacity: Int(OLLIN_MAX_LIGHTS)) { buf in
                (0 ..< lightCount).map { buf[$0] }
            }
        }
        if lights.contains(where: { $0.kind >= 3 }) { throw refuse("an area light (a panel or a tube) on a raymarched field") }

        let viewport = SIMD2<Float>(Float(width), Float(height))
        let aspect = Double(viewport.x / viewport.y)
        let view = camera.viewMatrix
        let projection = camera.projectionMatrix(aspect: aspect)
        let viewProjection = projection * view
        let inverse = simd_inverse(viewProjection)
        let steps = MetalRenderer.raymarchBudget(drawer.raymarchQualitySetting, automatic: .detail)
        // The reduced march resolution, as the export resolves it: the base
        // fraction over the fields' screen coverage, full when it reaches one
        // or when a field blends other than normally.
        var scale = MetalRenderer.raymarchScale(drawer.raymarchQualitySetting, automatic: .detail)
        if drawer.batches.contains(where: { $0.kind == .sdfGroup3D && $0.blendMode != .normal }) { scale = 1 }
        if scale < 1 {
            let coverage = MetalRenderer.fieldScreenCoverage(drawer.sdf3DGroups, viewProjection: viewProjection)
            scale = min(1.0, scale / max(coverage.squareRoot(), 1e-3))
        }
        let w = scale < 1 ? max(1, Int((Double(width) * scale).rounded())) : width
        let h = scale < 1 ? max(1, Int((Double(height) * scale).rounded())) : height

        // The one caster a field marches toward: the primary, which is what the
        // renderer keeps when no mesh rendered a map (every other slot needs one).
        var casters: [SIMD4<Float>] = []
        if lighting.enabled != 0, lighting.shadowCasterCount > 0, lighting.shadowLight >= 0 {
            casters.append(SIMD4(Float(lighting.shadowLight), lighting.shadowStrength, 0, 0))
        }

        var out: [Float] = []
        out.reserveCapacity(WebScene.headerFloats + lightCount * WebScene.lightFloats + casters.count * WebScene.casterFloats)
        for m in [view, projection, inverse] {
            for column in [m.columns.0, m.columns.1, m.columns.2, m.columns.3] {
                out.append(contentsOf: [column.x, column.y, column.z, column.w])
            }
        }
        out.append(contentsOf: [viewport.x, viewport.y, Float(steps.march), Float(steps.shadow)])
        out.append(contentsOf: [Float(scale), Float(w), Float(h), lighting.sceneScale])
        out.append(contentsOf: [lighting.ambient.x, lighting.ambient.y, lighting.ambient.z, lighting.ambient.w])
        out.append(contentsOf: [lighting.cameraPosition.x, lighting.cameraPosition.y, lighting.cameraPosition.z,
                                Float(lighting.enabled)])
        out.append(contentsOf: [Float(lightCount), Float(casters.count), 0, 0])
        for l in lights {
            out.append(contentsOf: [l.color.x, l.color.y, l.color.z, l.color.w,
                                    l.position.x, l.position.y, l.position.z, l.position.w,
                                    l.direction.x, l.direction.y, l.direction.z, l.direction.w,
                                    Float(l.kind), l.cosInner, l.cosOuter, l.softness,
                                    l.specular.x, l.specular.y, l.specular.z, l.specular.w])
        }
        for c in casters { out.append(contentsOf: [c.x, c.y, c.z, c.w]) }
        return out
    }

    private func tableIndex(_ samples: [SIMD4<Float>]) -> Int {
        if let i = tables.firstIndex(of: samples) { return i }
        tables.append(samples)
        return tables.count - 1
    }

    /// Appends one shape, its gradient rows (when a paint is one) renumbered
    /// from the frame's or the recording's table into the recording's through
    /// `rows`.
    private static func appendInstance(_ instance: SDFInstance, rows: [Int], into floats: inout [Float], frame: Int) throws {
        var placed = instance
        let fillKind = (instance.shape >> 10) & 0x3
        let strokeKind = (instance.shape >> 12) & 0x3
        func row(_ local: Float) throws -> Float {
            let i = Int(local.rounded())
            guard i >= 0, i < rows.count else { throw WebExportRefusal(call: "a gradient whose row the frame did not bake", frame: frame) }
            return Float(rows[i])
        }
        placed.fillGradient = fillKind != 0 ? try row(instance.fillGradient) : 0
        placed.strokeGradient = strokeKind != 0 ? try row(instance.strokeGradient) : 0
        WebInstance.append(placed, into: &floats)
    }

    /// The case name of an enum value, without its payload.
    static func caseName<T>(_ value: T) -> String {
        let text = String(describing: value)
        if let paren = text.firstIndex(of: "(") { return String(text[..<paren]) }
        return text
    }
}

// MARK: - The graph as the page reads it

extension WebGraph {
    /// A JSON-ready dictionary of the graph.
    var meta: [String: Any] {
        func items(_ list: [WebDrawItem]) -> [[Any]] {
            list.map { item -> [Any] in
                switch item {
                case let .shapes(start, count, blend): return ["s", start, count, blend]
                case let .triangles(start, count, fringe, blend): return ["t", start, count, fringe ? 1 : 0, blend]
                case let .sources(start, floats, count, fringe, blend): return ["x", start, floats, count, fringe ? 1 : 0, blend]
                case let .image(source, quad, count, blend):
                    switch source {
                    case .layer(let i): return ["i", i, quad, blend, count]
                    case .previous(let i): return ["p", i, quad, blend, count]
                    case .picture(let i): return ["m", i, quad, blend, count]
                    }
                case let .glyphs(atlas, quad, count, blend):
                    return ["a", atlas, quad, blend, count]
                case let .groups(start, count, blend):
                    return ["g", start, count, blend]
                case let .fields(start, count, blend, material):
                    return ["f", start, count, blend, material]
                }
            }
        }
        func pass(_ n: WebPassNode) -> [String: Any] {
            ["f": n.fragment, "in": n.inputs.map { input -> [Any] in
                switch input {
                case .layer(let i): return ["l", i]
                case .table(let i): return ["t", i]
                }
            }, "p": n.paramOffset, "r": n.paramRows]
        }
        let layers = self.layers.map { layer -> [String: Any] in
            var d: [String: Any] = ["k": layer.key, "w": layer.width, "h": layer.height,
                                    "pw": layer.pixelWidth, "ph": layer.pixelHeight]
            switch layer.kind {
            case let .geometry(clear, list):
                d["t"] = "g"; d["clear"] = clear; d["items"] = items(list)
            case .generator(let n):
                d["t"] = "gen"; d["pass"] = pass(n)
            case let .filter(input, n):
                d["t"] = "fx"; d["input"] = input; d["pass"] = pass(n)
            case let .combine(base, aux, n):
                d["t"] = "cx"; d["base"] = base; d["aux"] = aux; d["pass"] = pass(n)
            case let .user(shader, inputs, offset, rows):
                d["t"] = "u"; d["shader"] = shader; d["inputs"] = inputs; d["p"] = offset; d["r"] = rows
            case let .feedback(clear, list):
                d["t"] = "fb"; d["clear"] = clear; d["items"] = items(list)
            case let .sim(sim, clear, list):
                d["t"] = "sim"; d["clear"] = clear; d["items"] = items(list)
                var s: [String: Any] = ["inject": sim.inject, "step": sim.step, "n": sim.substeps,
                                        "rest": sim.rest, "seed": sim.seedFill,
                                        "p": sim.paramOffset, "r": sim.paramRows]
                if let m = sim.modulation, let ms = sim.modulatedStep { s["mod"] = m; s["modStep"] = ms }
                d["sim"] = s
            }
            return d
        }
        return ["layers": layers, "canvas": items(canvas), "post": frameFilters.map(pass),
                "instances": instanceCount, "quads": quadCount, "groups": groupCount, "nodes": nodeCount,
                "fields": fieldCount, "nodes3d": node3DCount, "sources": sourceFloats,
                "vertices": vertexCount, "params": paramFloats]
    }

    /// Every framework fragment the graph runs, with the most rows any pass
    /// binds to it.
    var fragmentRows: [String: Int] {
        var rows: [String: Int] = [:]
        func note(_ n: WebPassNode) {
            if n.fragment == WebPassNode.bloom {
                for name in WebPassNode.bloomFragments { rows[name] = max(rows[name] ?? 0, 1) }
                return
            }
            if n.isPageOwned { return }
            rows[n.fragment] = max(rows[n.fragment] ?? 0, n.paramRows)
        }
        for layer in layers {
            switch layer.kind {
            case .generator(let n), .filter(_, let n), .combine(_, _, let n): note(n)
            case .sim(let s, _, _):
                // The inject and the step bind the texel row ahead of the sim's rows.
                for name in [s.inject, s.step] + (s.modulatedStep.map { [$0] } ?? []) {
                    rows[name] = max(rows[name] ?? 0, s.paramRows + 1)
                }
                if !s.seedFill.isEmpty { rows["ollin_sim_state_seed"] = max(rows["ollin_sim_state_seed"] ?? 0, 2) }
            default: break
            }
        }
        for n in frameFilters { note(n) }
        return rows
    }
}
