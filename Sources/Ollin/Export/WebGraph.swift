import Foundation
import simd
import COllinShaders

// MARK: - The graph

/// The pass graph of one recorded frame: the layers the renderer filled, in
/// the order it filled them, what each was filled from, what the canvas drew,
/// and the whole-frame filters after it. Every shape run, image quad, triangle
/// run, and parameter row points into the frame's float vector, so the structure is
/// one value and the numbers travel apart from it: a frame whose graph equals
/// the last frame's differs only in its vector, which is what lets the moving
/// columns be fitted and sampled the way the shapes already are.
struct WebGraph: Hashable {
    var layers: [WebLayer]
    var canvas: [WebDrawItem]
    var frameFilters: [WebPassNode]
    /// The vector's layout: `instanceCount` shapes of `WebInstance.floats`,
    /// then `quadCount` image quads of `WebQuad.floats`, then `vertexCount`
    /// triangle vertices of `WebVertex.floats`, then `paramFloats`.
    var instanceCount: Int
    var quadCount: Int
    var vertexCount: Int
    var paramFloats: Int

    var vectorCount: Int { paramOffset + paramFloats }
    var quadOffset: Int { instanceCount * WebInstance.floats }
    var vertexOffset: Int { quadOffset + quadCount * WebQuad.floats }
    var paramOffset: Int { vertexOffset + vertexCount * WebVertex.floats }

    /// Whether any surface draws triangles this frame, so the page rasterizes
    /// its drawn surfaces with multisampling, as the Mac does for every 2D pass
    /// (a fill's edge has no analytic coverage of its own).
    var hasTriangles: Bool {
        func any(_ items: [WebDrawItem]) -> Bool {
            items.contains { if case .triangles = $0 { return true } else { return false } }
        }
        if any(canvas) { return true }
        return layers.contains { layer in
            switch layer.kind {
            case let .geometry(_, items), let .feedback(_, items), let .sim(_, _, items): return any(items)
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
    /// A layer composited as a textured quad (its six vertices at `quad`),
    /// under a blend mode (`WebBlend`).
    case image(source: WebImageSource, quad: Int, blend: Int)
}

enum WebImageSource: Hashable {
    /// Layer `index`'s content this frame.
    case layer(Int)
    /// Feedback layer `index`'s content last frame.
    case previous(Int)
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
/// layer keeps its key, a table travels once, and a user shader compiles once.
final class WebGraphRecorder {
    private(set) var tables: [[SIMD4<Float>]] = []
    private(set) var shaders: [WebUserShader] = []
    private var keys: [ObjectIdentifier: Int] = [:]

    /// Resolves a `.default` quality the way an export does.
    static func exportQuality(_ q: RenderQuality) -> RenderQuality { q == .default ? .detail : q }

    func capture(_ drawer: Drawer, frame: Int, width canvasWidth: Int, height canvasHeight: Int) throws -> WebFrame {
        func refuse(_ call: String) -> WebExportRefusal { WebExportRefusal(call: call, frame: frame) }
        if drawer.camera3D != nil || !drawer.lights.isEmpty {
            throw refuse("3D drawing (a camera or a light)")
        }
        if !drawer.dispatches.isEmpty {
            throw refuse("compute work (a simulation or GPU particles)")
        }

        var vector: [Float] = []
        var instanceCount = 0
        var quadCount = 0
        var quads: [Float] = []
        var vertexCount = 0
        var vertices: [Float] = []
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
                        try Self.appendInstance(instance, into: &vector, frame: frame)
                        instanceCount += 1
                    }
                    if instanceCount > start { items.append(.shapes(start: start, count: instanceCount - start, blend: blend)) }
                case .triangles, .fringe:
                    // A fill's triangles or a stroke's fringe bands: the run the
                    // renderer would draw, vertex for vertex.
                    let end = nextStart(i, \.vertexStart, end: drawer.vertices.count)
                    let start = vertexCount
                    for vertex in drawer.vertices[batch.vertexStart ..< end] {
                        WebVertex.append(vertex, into: &vertices)
                        vertexCount += 1
                    }
                    if vertexCount > start {
                        items.append(.triangles(start: start, count: vertexCount - start,
                                                fringe: batch.kind == .fringe, blend: blend))
                    }
                case .retained:
                    // A recording of shapes, strokes, and fills replays as its
                    // own runs, the draw-time transform composed onto each shape's
                    // own and applied to each vertex, as the replay's vertex
                    // stages do.
                    guard let recording = batch.retained else { continue }
                    let inner = recording.innerBatches
                    let simple = recording.imageVertices.isEmpty && recording.glyphVertices.isEmpty
                        && recording.points.isEmpty && recording.sdfGroups.isEmpty
                        && inner.allSatisfy {
                            ($0.kind == .sdf || $0.kind == .triangles || $0.kind == .fringe) && $0.depth == nil
                        }
                    guard simple else { throw refuse("drawBatch (a recording holding more than shapes, strokes, and fills)") }
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
                                try Self.appendInstance(placed, into: &vector, frame: frame)
                                instanceCount += 1
                            }
                            if instanceCount > start {
                                items.append(.shapes(start: start, count: instanceCount - start, blend: runBlend))
                            }
                        case .triangles, .fringe:
                            let end = next?.vertexStart ?? recording.vertices.count
                            let start = vertexCount
                            for vertex in recording.vertices[run.vertexStart ..< end] {
                                var placed = vertex
                                if let t = batch.retainedTransform {
                                    let p = t * SIMD3<Float>(vertex.position.x, vertex.position.y, 1)
                                    placed.position = SIMD2<Float>(p.x, p.y)
                                }
                                WebVertex.append(placed, into: &vertices)
                                vertexCount += 1
                            }
                            if vertexCount > start {
                                items.append(.triangles(start: start, count: vertexCount - start,
                                                        fringe: run.kind == .fringe, blend: runBlend))
                            }
                        default:
                            continue
                        }
                    }
                case .image:
                    guard let image = batch.image else { continue }
                    let source: WebImageSource
                    if let target = image.webRenderTarget {
                        if let li = index[ObjectIdentifier(target)] { source = .layer(li) }
                        else if let pi = previousOf[ObjectIdentifier(target)] { source = .previous(pi) }
                        else { throw refuse("drawImage of a layer the frame did not fill (a depth or normal layer)") }
                    } else {
                        throw refuse("drawImage")
                    }
                    let end = nextStart(i, \.imageStart, end: drawer.imageVertices.count)
                    let run = Array(drawer.imageVertices[batch.imageStart ..< end])
                    guard run.count == WebQuad.vertices else { throw refuse("drawImage (a quad of \(run.count) vertices)") }
                    WebQuad.append(run, into: &quads)
                    items.append(.image(source: source, quad: quadCount, blend: WebBlend.index(of: batch.blendMode)))
                    quadCount += 1
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

        // The vector: the shapes already appended, then the quads, the vertices,
        // and the rows.
        vector.append(contentsOf: quads)
        vector.append(contentsOf: vertices)
        vector.append(contentsOf: params)
        let graph = WebGraph(layers: layers, canvas: canvas, frameFilters: frameFilters,
                             instanceCount: instanceCount, quadCount: quadCount,
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
                        exposure: Float(drawer.toneMapExposure))
    }

    private func tableIndex(_ samples: [SIMD4<Float>]) -> Int {
        if let i = tables.firstIndex(of: samples) { return i }
        tables.append(samples)
        return tables.count - 1
    }

    private static func appendInstance(_ instance: SDFInstance, into floats: inout [Float], frame: Int) throws {
        let fillKind = (instance.shape >> 10) & 0x3
        let strokeKind = (instance.shape >> 12) & 0x3
        if fillKind != 0 || strokeKind != 0 {
            throw WebExportRefusal(call: "a gradient fill or stroke", frame: frame)
        }
        WebInstance.append(instance, into: &floats)
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
                case let .image(source, quad, blend):
                    switch source {
                    case .layer(let i): return ["i", i, quad, blend]
                    case .previous(let i): return ["p", i, quad, blend]
                    }
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
                "instances": instanceCount, "quads": quadCount, "vertices": vertexCount, "params": paramFloats]
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
