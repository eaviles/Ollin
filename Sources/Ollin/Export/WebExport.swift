import Foundation
import simd
import COllinShaders
import OllinShaderText

// MARK: - The recording

/// One recorded frame of the page: the clear the frame asked for, the frame's
/// float vector (the analytic-shape instances the renderer received, in call
/// order, then the image quads that composite a layer, then the vertices of
/// every fill and stroke the triangle path tessellated, then the parameter
/// rows of every effect pass), and the graph that says what the vector means.
/// The vector is the same data the GPU reads each frame, so the page draws it
/// with the same fragments the Mac does.
struct WebFrame: Equatable {
    /// The clear color in linear light, or `nil` when the frame drew onto what
    /// the previous frame left (an accumulating sketch).
    var clear: SIMD3<Float>?
    /// Shapes (`WebInstance.floats` each), then quads (`WebQuad.floats` each),
    /// then the fields and their programs, then strokes and fills as their
    /// points (`WebSourceLayout` records), then vertices (`WebVertex.floats`
    /// each), then parameter rows, laid out as `graph` says.
    var vector: [Float]
    var graph: WebGraph
    var toneMapMode: Int
    var exposure: Float
    /// The 3D scene the frame's fields are marched through (`WebGraphRecorder.sceneBlock`),
    /// or empty: it travels apart from the vector, whole and exact, since a
    /// camera matrix quantized inside its range moves a silhouette.
    var scene: [Float] = []

    /// The shape region of the vector alone.
    var instances: [Float] { Array(vector[0 ..< graph.instanceCount * WebInstance.floats]) }
}

/// What one analytic shape becomes on the wire: the `SDFInstance` fields the
/// page's vertex shader reads, as plain floats. The affine transform travels as
/// its two axis columns and its translation (the third row of a 2D CTM is
/// always 0 0 1), the shape tag as a float (it fits in fourteen bits, so the
/// value is exact), and the two gradient rows renumbered into the recording's
/// one strip (a frame's own table is per frame).
enum WebInstance {
    static let floats = 30

    static func append(_ i: SDFInstance, into out: inout [Float]) {
        let t = i.transform
        out.append(contentsOf: [
            t.columns.0.x, t.columns.0.y, t.columns.1.x, t.columns.1.y, t.columns.2.x, t.columns.2.y,
            i.center.x, i.center.y, i.size.x, i.size.y,
            i.fillColor.x, i.fillColor.y, i.fillColor.z, i.fillColor.w,
            i.strokeColor.x, i.strokeColor.y, i.strokeColor.z, i.strokeColor.w,
            i.param0.x, i.param0.y, i.param1.x, i.param1.y, i.param2.x, i.param2.y,
            i.strokeWidth, i.extra, i.bandWidth, Float(i.shape),
            i.fillGradient, i.strokeGradient,
        ])
    }

    /// The column that holds the shape tag inside one instance's floats.
    static let shapeColumn = 27
}

/// A sketch recorded for the page: every frame's data over a duration, plus
/// the document-level facts the emitter needs. Produced by
/// `OllinApp.recordWebFrames`, consumed by `OllinApp.webPage`.
struct WebRecording {
    /// The sketch's type name, the page's title.
    var name: String
    var width: Int
    var height: Int
    /// Recorded frames per second of the sketch's own time.
    var rate: Double
    var frames: [WebFrame]
    /// Whether the track spans exactly one lap of the sketch's declared
    /// `loopDuration`, so the page wraps from the last frame back to the first
    /// with no seam (the frames interpolate across the wrap).
    var loops: Bool
    /// The reproduction recipe (see ExportMetadata.swift).
    var recipe: String
    /// What the sketch said about itself, the canvas's accessible label.
    var description: String
    /// The formulas driving parameters, in evaluation order (see `WebFormula`).
    var formulas: [WebFormula] = []
    /// Each formula's value at each recorded frame, read back from its
    /// parameter, so a shape column can be matched to the one that moves it.
    var series: [[Float]] = []
    /// The numbers a formula may read that nothing drives, as they stood at
    /// the first recorded frame.
    var constants: [String: Double] = [:]
    /// The automation's clock, when the sketch has one.
    var clock: WebAutomationClock?
    /// Frames the sketch ran before the first recorded one (`--skip`), so the
    /// page stands a formula's `time` and `frame` where the Mac did.
    var frameOffset: Int = 0
    /// The pointer at the first recorded frame, the page's starting mouse.
    var mouse: (x: Double, y: Double) = (0, 0)
    /// The lookup strips the passes read, each once.
    var tables: [[SIMD4<Float>]] = []
    /// The user shaders the frames run, each once.
    var shaders: [WebUserShader] = []
    /// The pictures `drawImage` drew, each once.
    var pictures: [WebPicture] = []
    /// The glyph atlas pages atlas text sampled, each once.
    var atlases: [WebAtlas] = []
    /// The gradient rows the shapes read, each once, the page's strip.
    var gradientRows: [[UInt8]] = []
    /// The split-sum table (`WebBRDFLUT`) when a field wears a physically-based
    /// finish; empty otherwise.
    var brdfLUT: [UInt16] = []
    /// The parameters the page offers as controls, the axes that carry them,
    /// and the parameters left at their recorded values with the reason
    /// (`WebControls.swift`).
    var controls: [WebControl] = []
    var axes: [WebAxis] = []
    var leftOut: [WebLeftOut] = []

    var duration: Double { Double(frames.count) / rate }
    /// Whether any frame carries state from the one before it.
    var isStateful: Bool { frames.contains { $0.graph.isStateful } }
}

/// Why a sketch could not cross to the page: the first call the recorder met
/// that the page cannot carry, and the frame it was met at. The exporter never
/// draws a partial picture; it stops and says what stopped it.
public struct WebExportRefusal: Error, CustomStringConvertible, Equatable {
    /// The call, or the family of calls, that stopped the export.
    public var call: String
    /// The frame (from the first recorded one) the call was met at.
    public var frame: Int

    public var description: String {
        "\(call) does not cross to the web page yet (met at frame \(frame)); export the sketch as video instead (--export-video)"
    }
}

/// One part of a page's weight: what it is, how many bytes of the page it
/// takes (as written, base64 and all), and how much of that a longer
/// recording would grow, so a refusal can say whether fewer frames would
/// help. The parts of a page sum to the page.
struct WebWeight: Equatable {
    /// `shapes`, `vertices`, `scenes`, `controls`, `pictures`, `atlas pages`,
    /// or `shaders and player`.
    var name: String
    /// Bytes stored once for the whole track.
    var once: Int
    /// Bytes stored per recorded frame, over every frame.
    var perFrame: Int
    var bytes: Int { once + perFrame }
    /// Whether recording fewer frames would take most of this part away.
    var growsWithFrames: Bool { perFrame > once }
}

/// The least a page can weigh, worked out frame by frame as a recording
/// runs, from what the frames seen so far must put on it whatever the
/// packing does: the first frame's vertices and shapes travel once (a stable
/// cast's base, or the first record of a changing one); once the cast has
/// changed, every frame that differs from the one before travels whole;
/// every picture travels; and, on a recording that is not a lap and drives
/// nothing by formula, a column that has moved once is sampled in every
/// unique frame at two bytes, so the columns seen moving so far cost that
/// over the frames so far. (A lap may fit a moving column to a few sines and
/// a formula may carry one for nothing, so there those columns are left
/// out, and the page is checked once assembled.) A drawing dense enough is
/// refused at its first frame, and a moving one within its first few, before
/// the recording holds the frames the page would never get.
struct WebWeightBound {
    /// Whether a moving column is sure to be sampled per frame.
    var samplesMovingColumns: Bool
    private var first: WebFrame?
    private var moved: [Bool] = []
    private var movingColumns = 0
    private var uniqueFrames = 0
    private var changing = false
    private var onceBytes = 0
    private var perFrameBytes = 0
    private var pictureBytes = 0
    private var fullestVertices = 0
    /// What the strokes and fills as points have cost, inside the totals
    /// above, and how many the fullest frame carries, so a refusal can name
    /// them apart from the vertices.
    private var sourceBytes = 0
    private var fullestSources = 0
    /// How many of the moving columns are a stroke's or a fill's points.
    private var movingSourceColumns = 0
    /// The expander, once, from the first frame that carries a stroke or a
    /// fill as points.
    private var expanderBytes = 0

    init(samplesMovingColumns: Bool = false) {
        self.samplesMovingColumns = samplesMovingColumns
    }

    /// What the moving columns of a stable cast have cost so far: their
    /// samples over the unique frames, and each one's range and index.
    private var movingBytes: Int {
        changing || !samplesMovingColumns ? 0 : WebTrack.encoded(movingColumns * (2 * uniqueFrames + 12))
    }

    /// The part of `movingBytes` that is a stroke's or a fill's points.
    private var movingSourceBytes: Int {
        changing || !samplesMovingColumns ? 0 : WebTrack.encoded(movingSourceColumns * (2 * uniqueFrames + 12))
    }

    var bytes: Int { onceBytes + perFrameBytes + movingBytes + pictureBytes + expanderBytes }

    mutating func add(_ frame: WebFrame, previous: WebFrame?, pictureBytes pictures: Int) {
        let g = frame.graph
        fullestVertices = max(fullestVertices, g.vertexCount)
        fullestSources = max(fullestSources, g.sourceCount)
        pictureBytes = WebTrack.encoded(pictures)
        let v = WebVertex.floats, p = WebVertex.positionFloats
        guard let first else {
            self.first = frame
            uniqueFrames = 1
            moved = [Bool](repeating: false, count: frame.vector.count)
            // The vertices' positions exact and the rest as samples; the
            // shapes, the rows, and the strokes and fills as points in float32.
            onceBytes = WebTrack.encoded(g.vertexCount * (p * 4 + (v - p) * 2) + g.vertexOffset * 4)
            sourceBytes = WebTrack.encoded(g.sourceFloats * 4)
            // The expander travels with the first stroke or fill as points.
            if g.sourceFloats > 0 { expanderBytes = WebExpanderResource.pageBytes }
            return
        }
        let unique = previous.map { $0.vector != frame.vector || $0.graph != frame.graph } ?? true
        if unique { uniqueFrames += 1 }
        if !changing, frame.graph != first.graph || frame.vector.count != first.vector.count { changing = true; moved = [] }
        if changing {
            if unique {
                perFrameBytes += WebTrack.encoded(g.vertexCount * (p * 4 + (v - p) * 2) + g.sourceOffset * 2 + g.sourceFloats * 4)
                sourceBytes += WebTrack.encoded(g.sourceFloats * 4)
            }
        } else if samplesMovingColumns, unique {
            let so = first.graph.sourceOffset, vo = first.graph.vertexOffset
            for i in moved.indices where !moved[i] && frame.vector[i] != first.vector[i] {
                moved[i] = true
                movingColumns += 1
                if i >= so && i < vo { movingSourceColumns += 1 }
            }
        }
    }

    func refusal(maxBytes: Int, seen: Int, of total: Int) -> WebWeightRefusal {
        // The parts so far: the vertices, the strokes and fills as points, the
        // pictures, and the expander. The heaviest names the refusal.
        let pointBytes = sourceBytes + movingSourceBytes
        let vertexBytes = onceBytes + perFrameBytes + movingBytes - pointBytes
        let movingVertices = movingColumns - movingSourceColumns
        let moving = !changing && movingVertices > 0 ? ", \(movingVertices) columns moving" : ""
        let movingPoints = !changing && movingSourceColumns > 0 ? ", \(movingSourceColumns) columns moving" : ""
        let grows = perFrameBytes + movingBytes > onceBytes
        var parts: [(name: String, bytes: Int, grows: Bool, detail: String)] = [
            ("stroke and fill vertices", vertexBytes, grows, "\(fullestVertices) vertices in the fullest frame\(moving)"),
            ("strokes and fills as points", pointBytes, grows, "\(fullestSources) strokes and fills as points in the fullest frame\(movingPoints)"),
            ("pictures", pictureBytes, true, "one per frame the picture changed"),
            ("the stroke expander", expanderBytes, false, "the expander travels once"),
        ]
        parts.sort { $0.bytes > $1.bytes }
        let heaviest = parts[0]
        return WebWeightRefusal(bytes: bytes, maxBytes: maxBytes, heaviest: heaviest.name, heaviestBytes: heaviest.bytes,
                                growsWithFrames: heaviest.grows, detail: heaviest.detail, seen: (seen, total))
    }
}

/// Why a page was not written: it would weigh more than the export allows.
/// A page past the budget is a page a browser struggles to open and a host
/// refuses to serve, so the exporter stops instead and says what made it
/// heavy, whether recording fewer frames would help, that the sketch exports
/// as video, and the flag that writes the page anyway.
public struct WebWeightRefusal: Error, CustomStringConvertible, Equatable {
    /// What the page would have weighed, in bytes.
    public var bytes: Int
    /// The most the export allowed, in bytes.
    public var maxBytes: Int
    /// The heaviest part of the page (`vertices`, `shapes`, `pictures`, ...)
    /// and its bytes.
    public var heaviest: String
    public var heaviestBytes: Int
    /// Whether the heaviest part is stored per recorded frame, so fewer frames
    /// (a lower `--fps`, a shorter `--seconds`) would take most of it away.
    public var growsWithFrames: Bool
    /// What the heaviest part holds, for the message: the vertex count of the
    /// fullest frame, the picture count, the frame count.
    public var detail: String
    /// When the refusal came during the recording, the recorded frames it had
    /// seen and the frames asked for: `bytes` is then what the page would
    /// weigh at least, from what those frames alone put on it. A drawing
    /// dense enough is refused at its first frame, before the recording
    /// takes the memory the rest would.
    public var seen: (frames: Int, of: Int)?

    public static func == (a: WebWeightRefusal, b: WebWeightRefusal) -> Bool {
        a.bytes == b.bytes && a.maxBytes == b.maxBytes && a.heaviest == b.heaviest && a.heaviestBytes == b.heaviestBytes
            && a.growsWithFrames == b.growsWithFrames && a.detail == b.detail
            && a.seen?.frames == b.seen?.frames && a.seen?.of == b.seen?.of
    }

    public var description: String {
        let mb = Double(1024 * 1024)
        let weight = String(format: "%.1f MB", Double(bytes) / mb)
        let allowed = Self.megabytes(maxBytes)
        let heavy = String(format: "%.1f MB", Double(heaviestBytes) / mb)
        var out: String
        if let seen {
            out = "the page would weigh at least \(weight) (by frame \(seen.frames) of \(seen.of)), past the \(allowed) allowed; \(heavy) of it is \(heaviest)"
        } else {
            out = "the page would weigh \(weight), past the \(allowed) allowed; \(heavy) of it is \(heaviest)"
        }
        if !detail.isEmpty { out += " (\(detail))" }
        if growsWithFrames {
            out += ", stored for every recorded frame: record fewer frames (--fps 10, or a shorter --seconds), or export the sketch as video instead (--export-video)"
        } else {
            out += ", which travels once, so fewer frames would not help: export the sketch as video instead (--export-video)"
        }
        if seen != nil {
            out += "; --max-page-size 0 lifts the limit and writes the page anyway"
        } else {
            let anyway = Int((Double(bytes) / mb).rounded(.up)) + 1
            out += "; --max-page-size \(anyway) writes the page anyway"
        }
        return out
    }

    static func megabytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / Double(1024 * 1024)
        return mb == mb.rounded() ? "\(Int(mb)) MB" : String(format: "%.1f MB", mb)
    }
}

/// A defect in the page's own shaders: the framework's shader text no longer
/// crosses to GLSL. Never the sketch's fault, so it is reported apart from a
/// refusal.
struct WebShaderError: Error, CustomStringConvertible {
    var diagnostics: [WebShaderDiagnostic]
    var description: String {
        "the page's shaders did not translate: " + diagnostics.map { "line \($0.line): \($0.message)" }.joined(separator: "; ")
    }
}

/// The framework's resources hold no expander for the page, so a stroke or a
/// fill as its points has nothing to expand it: a broken checkout, never the
/// sketch's doing.
struct WebExpanderMissing: Error, CustomStringConvertible {
    var description: String {
        "the page's expander (WebExpander.wasm) is missing from the framework's resources; run Scripts/build-web-expander.sh"
    }
}

// MARK: - Recording

extension OllinApp {
    /// Drive `sketch` headlessly the way the video export does (`setup()`, then
    /// `draw()` advanced frame by frame at `fps`) and record what the renderer
    /// received each frame. Never touches Metal, so the page holds nothing
    /// GPU-specific. `skipSeconds` runs the sketch that long before the first
    /// recorded frame. With `controls`, the sketch's parameters are then probed
    /// on fresh sketches from `remake` (a new instance of the same class when
    /// none is given) so the page can offer them as controls (`webControls`).
    static func recordWebFrames(of sketch: Sketch, frames: Int, fps: Double,
                                skipSeconds: Double = 0, controls: Bool = true,
                                maxBytes: Int? = nil,
                                remake: (() -> Sketch)? = nil) throws -> WebRecording {
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }
        let size = sketch.canvasSize
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        // Every stroke and fill is kept as its points from here on, a batch
        // made in `setup()` included.
        sketch.drawer.recordsWebSources = true
        defer { sketch.drawer.recordsWebSources = false }
        sketch.runSetup()
        guard sketch.colorOutput == .standard else {
            throw WebExportRefusal(call: "colorOutput \(sketch.colorOutput) (wide gamut and HDR output)", frame: 0)
        }
        let skip = max(0, Int((skipSeconds * fps).rounded()))
        // A parameter driven by a formula crosses as the formula (see
        // `WebFormula`); its value each frame is what a shape column is
        // matched against. Every parameter's value as the run starts is what
        // a control on the page starts at.
        let formulas = webFormulas(of: sketch)
        var handles: [String: ParamHandle] = [:]
        var baseValues: [String: ParamStored] = [:]
        for handle in sketch.parameters() {
            handles[handle.name] = handle
            if baseValues[handle.name] == nil { baseValues[handle.name] = handle.param.stored }
        }
        var series = [[Float]](repeating: [], count: formulas.count)
        var constants: [String: Double] = [:]
        var mouse: (x: Double, y: Double) = (0, 0)
        let recorder = WebGraphRecorder()
        let loops = sketch.loopDuration.map { abs($0 * fps - Double(frames)) < 0.5 } ?? false
        let recorded = try runWebFrames(sketch, frames: frames, fps: fps, skip: skip,
                                        width: size.width, height: size.height, recorder: recorder,
                                        maxBytes: maxBytes, samplesMovingColumns: !loops && formulas.isEmpty) { k in
            if k == skip {
                constants = webConstants(of: sketch)
                for f in formulas { constants.removeValue(forKey: f.name) }
                mouse = (sketch.mouseX, sketch.mouseY)
            }
            for (i, f) in formulas.enumerated() {
                series[i].append(Float(webFormulaValue(named: f.name, in: handles) ?? 0))
            }
        }
        var recording = WebRecording(name: String(describing: type(of: sketch)),
                                     width: size.width, height: size.height, rate: fps,
                                     frames: recorded, loops: loops,
                                     recipe: ExportMetadata.capture(from: sketch, frame: 0, fps: fps).recipe,
                                     description: sketch.accessibleDescription.lines.joined(separator: " "))
        recording.formulas = formulas
        recording.series = series
        recording.constants = constants
        recording.clock = webAutomationClock(of: sketch)
        recording.frameOffset = skip
        recording.mouse = mouse
        recording.tables = recorder.tables
        recording.shaders = recorder.shaders
        recording.pictures = recorder.pictures
        recording.atlases = try recorder.finish(frame: max(0, frames - 1))
        recording.gradientRows = recorder.gradientRows
        if recorder.usesPhysicallyBasedField { recording.brdfLUT = WebBRDFLUT.shared }
        if controls {
            let probed = webControls(of: sketch, baseValues: baseValues, baseline: recorded, frames: frames,
                                     fps: fps, skip: skip, width: size.width, height: size.height,
                                     remake: remake ?? { type(of: sketch).init() })
            recording.controls = probed.controls
            recording.axes = probed.axes
            recording.leftOut = probed.leftOut
        }
        return recording
    }

    /// Drive `sketch` for `skip + frames` frames at `fps` and record the frames
    /// after the skip through `recorder`, calling `each` with the frame's
    /// index after every recorded draw. The baseline and every probe run
    /// through here, so a probe sees the frames the baseline saw.
    ///
    /// With `maxBytes`, the page is bounded from below as the frames come in
    /// (`WebWeightBound`) and the recording stops with a `WebWeightRefusal`
    /// the moment the bound passes it: a dense drawing is refused at its
    /// first frame, before the frames it would never use take their memory.
    static func runWebFrames(_ sketch: Sketch, frames: Int, fps: Double, skip: Int, width: Int, height: Int,
                             recorder: WebGraphRecorder, maxBytes: Int? = nil, samplesMovingColumns: Bool = false,
                             each: (Int) -> Void = { _ in }) throws -> [WebFrame] {
        var recorded: [WebFrame] = []
        recorded.reserveCapacity(frames)
        sketch.drawer.recordsWebSources = true
        var bound = WebWeightBound(samplesMovingColumns: samplesMovingColumns)
        for k in 0 ..< (skip + frames) {
            sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
            sketch.performDraw()
            if k < skip {
                // The page cannot replay a pile it never saw, nor a state it
                // never stepped.
                if sketch.drawer.accumulates {
                    throw WebExportRefusal(call: "--skip on a sketch that accumulates (noClear)", frame: 0)
                }
                if sketch.drawer.usesFeedback {
                    throw WebExportRefusal(call: "--skip on a sketch with a feedback layer or a simulation", frame: 0)
                }
                continue
            }
            each(k)
            recorded.append(try recorder.capture(sketch.drawer, frame: k - skip, width: width, height: height))
            if let maxBytes {
                bound.add(recorded[recorded.count - 1], previous: recorded.count > 1 ? recorded[recorded.count - 2] : nil,
                          pictureBytes: recorder.pictures.reduce(0) { $0 + $1.data.count })
                if bound.bytes > maxBytes {
                    throw bound.refusal(maxBytes: maxBytes, seen: recorded.count, of: frames)
                }
            }
        }
        return recorded
    }

    /// One frame's data, read off the drawer after `performDraw()`.
    static func captureWebFrame(_ drawer: Drawer, frame: Int, width: Int, height: Int) throws -> WebFrame {
        try WebGraphRecorder().capture(drawer, frame: frame, width: width, height: height)
    }

    /// The call, or the family of calls, a batch kind stands for in a refusal.
    nonisolated static func webRefusalName(for kind: GeometryKind) -> String {
        switch kind {
        case .particles: return "drawParticles"
        case .points3D: return "drawPointCloud"
        case .depthScene: return "drawDepthScene"
        case .mesh3D, .meshInstanced, .meshField, .strands, .ocean:
            return "3D drawing (a mesh, a field, strands, the ocean)"
        case .clipPush, .clipPop: return "withClip"
        // Never refused by kind: shapes, fills, strokes, pictures, atlas text,
        // composed and raymarched fields, and a recording of them cross (a
        // picture that is a live texture, and a field under a light the page
        // cannot carry, are refused where they are read).
        case .sdf, .triangles, .fringe, .retained, .image, .glyphAtlas, .sdfGroup, .sdfGroup3D:
            return "shapes, strokes, fills, pictures, text, and fields"
        }
    }
}

// MARK: - The page's shaders

/// The framework's shader text the page's shaders are cut from, read once from
/// the resource bundle: the helper library, the core segment (the dither), the
/// shapes segment (the analytic primitives' coverage), the two field segments
/// (the composed field's arithmetic, the raymarcher's distance functions), and
/// the four effect segments (the tone-map curve, the filters, the combines, the
/// simulations, the patterns). A page carries only what its frames run.
/// The stroke and fill expander compiled to WebAssembly, read once from the
/// resource bundle: `WebExpander.wasm`, built by `Scripts/build-web-expander.sh`
/// from the `OllinExpander` module the renderer's own strokes and fills go
/// through, beside a manifest naming the toolchain and a hash of the sources.
/// It is the player part a page carries when its strokes and fills travel as
/// points, and it travels only then.
enum WebExpanderResource {
    static let data: Data = {
        guard let url = OllinResources.bundle.url(forResource: "WebExpander", withExtension: "wasm") else { return Data() }
        return (try? Data(contentsOf: url)) ?? Data()
    }()

    /// The module as the page carries it.
    static let base64: String = data.base64EncodedString()

    /// What it weighs on the page, quotes included.
    static var pageBytes: Int { base64.utf8.count + 2 }

    /// The manifest beside the module.
    struct Manifest: Codable, Sendable {
        var toolchain: String
        var sdk: String
        /// The SHA-256 of the sources it was built from, in the script's order.
        var sources: String
        var bytes: Int
    }

    static let manifest: Manifest? = {
        guard let url = OllinResources.bundle.url(forResource: "WebExpander", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }()
}

enum WebShaderSources {
    static let text: String = {
        ["OllinShaderLib", "ShaderCore", "ShaderShapes", "ShaderCombinator", "ShaderRaymarch",
         "ShaderEffects", "ShaderCombine", "ShaderSim", "ShaderPatterns"].compactMap { name -> String? in
            guard let url = OllinResources.bundle.url(forResource: name, withExtension: "metal") else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }.joined(separator: "\n")
    }()

    /// The helper library alone, the text a user shader is compiled against.
    static let library: String = {
        guard let url = OllinResources.bundle.url(forResource: "OllinShaderLib", withExtension: "metal") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()
}

/// The GLSL ES 3.00 shaders a page carries: the shape and present pairs every
/// page has, the image quad pair and the fullscreen effect stage when a frame
/// uses a layer, then one fragment per framework effect the frames run and
/// one per user shader. The shape coverage, the present pass's dither and
/// tone-map curve, and every effect fragment are the framework's own Metal,
/// translated; the vertex stages and the two fragment tails are the page's,
/// and they mirror `ollin_sdf_vertex` and `ollin_present_fragment` line for
/// line.
struct WebShaders {
    var sdfVertex: String
    var sdfFragment: String
    var presentVertex: String
    var presentFragment: String
    var imageVertex: String
    var imageFragment: String
    /// Atlas text: the glyph quads' fragment (`ollin_glyph_fragment`), over the
    /// same vertex stage as an image quad.
    var glyphFragment: String
    /// The triangle path: one vertex stage for a fill and a stroke, the fill's
    /// fragment (`ollin_fragment`) and the stroke's (`ollin_fringe_fragment`).
    var triangleVertex: String
    var triangleFragment: String
    var fringeFragment: String
    /// The fullscreen stage every effect and user pass draws with.
    var effectVertex: String
    /// The framework's effect fragments by name.
    var effects: [String: String]
    /// The user shaders, in the recording's order.
    var users: [String]
    /// A composed 2D field (`drawSDF`): the covering quad's stage and the
    /// fragment that walks the field's program (`ollin_sdfgroup_fragment`), over
    /// the combinator's arithmetic and the shapes' distance functions and
    /// coverage. Empty when no frame draws one.
    var groupVertex: String = ""
    var groupFragment: String = ""
    /// A raymarched 3D field (`drawSDF3D`): the fullscreen stage, the fragment
    /// that sphere-traces the field and shades the hit
    /// (`ollin_raymarch_fragment` and the punctual half of `meshLitColor`), and
    /// the upsample that composites a reduced-resolution march
    /// (`ollin_raymarch_upsample_fragment`). Empty when no frame marches one.
    var fieldVertex: String = ""
    var fieldFragment: String = ""
    var upsampleFragment: String = ""

    static func make(effects wanted: [String: Int] = [:], users: [WebUserShader] = [],
                     groups: Bool = false, fields: Bool = false) throws -> WebShaders {
        let text = WebShaderSources.text
        let shapes = WebShaderLibrary.translate(text, wanted: ["shapes"])
        guard shapes.isClean else { throw WebShaderError(diagnostics: shapes.unsupported) }
        let present = WebShaderLibrary.translate(text, wanted: ["present"])
        guard present.isClean else { throw WebShaderError(diagnostics: present.unsupported) }
        let base = WebShaderLibrary.translate(text, wanted: [])
        guard base.isClean else { throw WebShaderError(diagnostics: base.unsupported) }
        let sdfFragment = WebShaderCompat.preamble + "\n" + shapes.support + "\n\n" + shapes.body + "\n" + sdfFragmentTail
        let presentFragment = WebShaderCompat.preamble + "\n" + present.support + "\n\n" + present.body + "\n" + presentFragmentTail
        let imageFragment = WebShaderCompat.preamble + "\n" + base.support + "\n\n" + base.body + "\n" + imageFragmentTail
        let glyphFragment = WebShaderCompat.preamble + "\n" + base.support + "\n\n" + base.body + "\n" + glyphFragmentTail
        let triangleFragment = WebShaderCompat.preamble + "\n" + base.support + "\n\n" + base.body + "\n" + triangleFragmentTail
        let fringeFragment = WebShaderCompat.preamble + "\n" + base.support + "\n\n" + base.body + "\n" + fringeFragmentTail

        var effects: [String: String] = [:]
        for (name, rows) in wanted {
            let t = WebFragmentTranslator.translate(entry: name, in: text, paramRows: max(1, rows))
            guard t.isClean else { throw WebShaderError(diagnostics: t.unsupported) }
            effects[name] = t.glsl
        }
        let userSources = try users.map { try WebUserShaderGLSL.make($0) }
        var shaders = WebShaders(sdfVertex: sdfVertex, sdfFragment: sdfFragment,
                                 presentVertex: presentVertex, presentFragment: presentFragment,
                                 imageVertex: imageVertex, imageFragment: imageFragment, glyphFragment: glyphFragment,
                                 triangleVertex: triangleVertex, triangleFragment: triangleFragment,
                                 fringeFragment: fringeFragment,
                                 effectVertex: effectVertex, effects: effects, users: userSources)
        if groups {
            let combinator = WebShaderLibrary.translate(text, wanted: ["combinator", "shapes"])
            guard combinator.isClean else { throw WebShaderError(diagnostics: combinator.unsupported) }
            shaders.groupVertex = groupVertex
            shaders.groupFragment = WebShaderCompat.preamble + "\n" + combinator.support + "\n\n" + combinator.body
                + "\n" + resolvePaintSource + "\n" + groupFragmentTail
        }
        if fields {
            let raymarch = WebShaderLibrary.translate(text, wanted: ["raymarch"])
            guard raymarch.isClean else { throw WebShaderError(diagnostics: raymarch.unsupported) }
            shaders.fieldVertex = fieldVertex
            shaders.fieldFragment = WebShaderCompat.preamble + "\n" + raymarch.support + "\n\n" + raymarch.body
                + "\n" + resolvePaintSource + "\n" + fieldLightingSource + "\n" + fieldFragmentTail
            shaders.upsampleFragment = upsampleFragment
        }
        return shaders
    }

    /// The triangle path's vertex stage, `ollin_vertex` and `ollin_fringe_vertex`
    /// in one: a vertex already in sketch space mapped into clip space with y
    /// down, its color and its coverage handed on. A retained batch's draw-time
    /// transform was applied to the recorded vertices on the Mac side, so no
    /// transform rides here.
    static let triangleVertex = """
    #version 300 es
    precision highp float;
    layout(location = 0) in vec2 aPosition;
    layout(location = 1) in float aCoverage;
    layout(location = 2) in vec4 aColor;
    uniform vec2 viewport;
    uniform float ollin_flip;
    out vec4 vColor;
    out float vCoverage;
    void main() {
        gl_Position = vec4((aPosition.x / viewport.x) * 2.0 - 1.0, (1.0 - (aPosition.y / viewport.y) * 2.0) * ollin_flip, 0.0, 1.0);
        vColor = aColor;
        vCoverage = aCoverage;
    }
    """

    /// `ollin_fragment`: a fill's vertex color linearized, its alpha straight,
    /// the edge left to the multisampled raster.
    static let triangleFragmentTail = """
    in vec4 vColor;
    in float vCoverage;
    out vec4 fragColor;
    void main() {
        fragColor = vec4(srgbToLinear(vColor.rgb), vColor.a);
    }
    """

    /// `ollin_fringe_fragment`: the stroke's color linearized, its paint alpha
    /// scaled by the fringe coverage remapped to perceptual alpha, the two kept
    /// apart as the Mac keeps them.
    static let fringeFragmentTail = """
    in vec4 vColor;
    in float vCoverage;
    out vec4 fragColor;
    void main() {
        float a = vColor.a * perceptualCoverage(clamp(vCoverage, 0.0, 1.0));
        fragColor = vec4(srgbToLinear(vColor.rgb), a);
    }
    """

    /// The covering quad of one instance, exactly as `ollin_sdf_vertex` builds it:
    /// the shape plus half the stroke plus a margin for the AA falloff, placed by
    /// the instance's own transform, mapped into clip space with y down. The
    /// viewport is the surface's logical size, so a layer drawn at a fraction of
    /// its size keeps its coordinates and only the raster shrinks. `ollin_flip`
    /// is 1, or -1 into a multisampled surface, where the picture is rasterized
    /// upright in the GPU's own texture space so the fixed sample pattern sits
    /// on it as it sits on the Mac's (the resolve turns it back over).
    static let sdfVertex = """
    #version 300 es
    precision highp float;
    precision highp int;
    layout(location = 0) in vec2 aT0;
    layout(location = 1) in vec2 aT1;
    layout(location = 2) in vec2 aT2;
    layout(location = 3) in vec4 aCenterSize;
    layout(location = 4) in vec4 aFill;
    layout(location = 5) in vec4 aStroke;
    layout(location = 6) in vec4 aP01;
    layout(location = 7) in vec4 aP2WE;
    layout(location = 8) in vec2 aBandShape;
    layout(location = 9) in vec2 aRows;
    uniform vec2 viewport;
    uniform float ollin_flip;
    out vec2 vLocal;
    out vec2 vSize;
    out vec4 vFill;
    out vec4 vStroke;
    out vec2 vP0;
    out vec2 vP1;
    out vec2 vP2;
    out float vStrokeWidth;
    out float vExtra;
    out float vBand;
    out float vFillRow;
    out float vStrokeRow;
    flat out uint vShape;
    flat out uint vAlign;
    flat out uint vFillKind;
    flat out uint vStrokeKind;
    void main() {
        vec2 corners[6] = vec2[6](vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(1.0, 1.0),
                                  vec2(-1.0, -1.0), vec2(1.0, 1.0), vec2(-1.0, 1.0));
        uint tag = uint(aBandShape.y + 0.5);
        uint align = (tag >> 8u) & 3u;
        float strokeWidth = aP2WE.z;
        float outset = (align == 2u) ? strokeWidth * 0.5 : 0.0;
        vec2 size = aCenterSize.zw;
        vec2 extent = size + aBandShape.x * 0.5 + strokeWidth * 0.5 + outset + 2.0;
        vec2 local = corners[gl_VertexID] * extent;
        vec2 q = aCenterSize.xy + local;
        vec2 sketch = aT0 * q.x + aT1 * q.y + aT2;
        gl_Position = vec4((sketch.x / viewport.x) * 2.0 - 1.0, (1.0 - (sketch.y / viewport.y) * 2.0) * ollin_flip, 0.0, 1.0);
        vLocal = local;
        vSize = size;
        vFill = aFill;
        vStroke = aStroke;
        vP0 = aP01.xy;
        vP1 = aP01.zw;
        vP2 = aP2WE.xy;
        vStrokeWidth = strokeWidth;
        vExtra = aP2WE.w;
        vBand = aBandShape.x;
        vFillRow = aRows.x;
        vStrokeRow = aRows.y;
        vShape = tag & 255u;
        vAlign = align;
        vFillKind = (tag >> 10u) & 3u;
        vStrokeKind = (tag >> 12u) & 3u;
    }
    """

    /// The tail of `ollin_sdf_fragment`: the coverage from the translated
    /// `ollin_sdf_coverage`, each paint resolved as `resolvePaint` resolves it
    /// (a solid color linearized; a gradient's geometry mapped to `t` and read
    /// from its row of the strip, an sRGB texture, so the sample comes back
    /// linear), stroke composited over fill in premultiplied linear light,
    /// returned straight so the same source-over blend applies.
    /// `resolvePaint` as the page spells it, over the strip bound as `gradients`:
    /// a solid slot linearized, a gradient's geometry mapped to `t` and read from
    /// its row of the strip (an sRGB texture, so the sample comes back linear).
    static let resolvePaintSource = """
    uniform sampler2D gradients;
    vec4 resolvePaint(vec4 slot, uint kind, float row, vec2 p, float pathT) {
        if (kind == 0u) { return vec4(srgbToLinear(slot.rgb), slot.a); }
        float t;
        if (kind == 1u) {
            vec2 d = slot.zw - slot.xy;
            t = dot(p - slot.xy, d) / max(dot(d, d), 1e-12);
        } else if (kind == 2u) {
            t = length(p - slot.xy) / max(slot.z, 1e-6);
        } else {
            t = pathT;
        }
        vec2 size = vec2(textureSize(gradients, 0));
        float u = (clamp(t, 0.0, 1.0) * (size.x - 1.0) + 0.5) / size.x;
        float v = (row + 0.5) / size.y;
        return texture(gradients, vec2(u, v));
    }
    """

    static let sdfFragmentTail = resolvePaintSource + """
    in vec2 vLocal;
    in vec2 vSize;
    in vec4 vFill;
    in vec4 vStroke;
    in vec2 vP0;
    in vec2 vP1;
    in vec2 vP2;
    in float vStrokeWidth;
    in float vExtra;
    in float vBand;
    in float vFillRow;
    in float vStrokeRow;
    flat in uint vShape;
    flat in uint vAlign;
    flat in uint vFillKind;
    flat in uint vStrokeKind;
    out vec4 fragColor;
    void main() {
        float fillCov = 0.0;
        float strokeCov = 0.0;
        float pathT = 0.0;
        ollin_sdf_coverage(vShape, vAlign, vLocal, vSize, vP0, vP1, vP2,
                           vStrokeWidth, vExtra, vBand, vFillKind == 3u || vStrokeKind == 3u,
                           fillCov, strokeCov, pathT);
        vec4 fillPaint = resolvePaint(vFill, vFillKind, vFillRow, vLocal, pathT);
        vec4 strokePaint = resolvePaint(vStroke, vStrokeKind, vStrokeRow, vLocal, pathT);
        float fillA = fillPaint.a * fillCov;
        float strokeA = strokePaint.a * strokeCov;
        vec3 premul = strokePaint.rgb * strokeA + fillPaint.rgb * fillA * (1.0 - strokeA);
        float a = strokeA + fillA * (1.0 - strokeA);
        if (a <= 0.0) { fragColor = vec4(0.0); return; }
        fragColor = vec4(premul / a, a);
    }
    """

    /// One oversized triangle over the canvas, like `ollin_present_vertex`. No
    /// V flip here: the page's intermediate stores the picture bottom-up, and
    /// the canvas reads it back the same way, so the rows land where they were.
    static let presentVertex = """
    #version 300 es
    precision highp float;
    out vec2 uv;
    void main() {
        vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
        gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
        uv = p;
    }
    """

    /// The tail of `ollin_present_fragment`: exposure, the tone-map mode, then
    /// the sRGB encode and the dither of `finalizeColor`, written straight to the
    /// 8-bit canvas (an sRGB drawable re-encodes what Metal's version returns;
    /// the canvas takes the encoded value as is). The dither reads the pixel
    /// position with y down, as the Mac's fragment does.
    static let presentFragmentTail = """
    uniform sampler2D src;
    uniform vec2 viewport;
    uniform float exposure;
    uniform int toneMapMode;
    in vec2 uv;
    out vec4 fragColor;
    void main() {
        vec3 c = texture(src, uv).rgb * exposure;
        if (toneMapMode == 1) {
            c = c / (1.0 + c);
        } else if (toneMapMode == 2) {
            c = toneMapACES(c);
        }
        vec2 fragCoord = vec2(gl_FragCoord.x, viewport.y - gl_FragCoord.y);
        vec3 enc = linearToSrgb(c);
        enc = clamp(enc + ditherTriangle(fragCoord) * (1.0 / 255.0), 0.0, 1.0);
        fragColor = vec4(enc, 1.0);
    }
    """

    /// The fullscreen stage the effect passes draw with, `ollin_present_vertex`
    /// as written: `uv` turned so (0, 0) is the top-left, the way a Metal
    /// fragment expects it. The reads inside a translated fragment turn the
    /// coordinate back, since the page keeps its layers bottom-up.
    static let effectVertex = """
    #version 300 es
    precision highp float;
    out vec2 uv;
    void main() {
        vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
        gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
        uv = vec2(p.x, 1.0 - p.y);
    }
    """

    /// A textured quad, like `ollin_image_vertex`: the six vertices already in
    /// sketch space, mapped by the surface's logical size.
    static let imageVertex = """
    #version 300 es
    precision highp float;
    layout(location = 0) in vec2 aPosition;
    layout(location = 1) in vec2 aUV;
    layout(location = 2) in vec4 aTint;
    uniform vec2 viewport;
    uniform float ollin_flip;
    out vec2 vUV;
    out vec4 vTint;
    void main() {
        gl_Position = vec4((aPosition.x / viewport.x) * 2.0 - 1.0, (1.0 - (aPosition.y / viewport.y) * 2.0) * ollin_flip, 0.0, 1.0);
        vUV = aUV;
        vTint = aTint;
    }
    """

    /// The page's Gaussian blur, one direction per pass: the taps out to three
    /// and a half sigma, each weighed by the Gaussian and the whole normalized
    /// by the sum, over a layer clamped at its edges, the way the Mac's kernel
    /// reads. Measured against the Mac on a one-pixel line: the profile is the
    /// same normalized Gaussian to within a level or two out past three sigma.
    static let blurFragment = """
    #version 300 es
    precision highp float;
    uniform sampler2D src;
    uniform vec2 step;
    uniform float sigma;
    in vec2 uv;
    out vec4 fragColor;
    void main() {
        vec2 q = vec2(uv.x, 1.0 - uv.y);
        int radius = int(ceil(sigma * 3.5));
        float twoSigma2 = 2.0 * sigma * sigma;
        vec4 sum = texture(src, q);
        float weight = 1.0;
        for (int i = 1; i <= radius; i++) {
            float w = exp(-float(i * i) / twoSigma2);
            vec2 d = step * float(i);
            sum += (texture(src, q + d) + texture(src, q - d)) * w;
            weight += 2.0 * w;
        }
        fragColor = sum / weight;
    }
    """

    /// The tail of `ollin_image_fragment`: the premultiplied linear texel (a
    /// layer's read with the row turned over, since the page keeps its layers
    /// bottom-up; a picture's as uploaded, its first row at the top, the way
    /// the Mac's texture holds it), the straight tint linearized and applied so
    /// the result stays premultiplied.
    static let imageFragmentTail = """
    uniform sampler2D tex;
    uniform float vflip;
    in vec2 vUV;
    in vec4 vTint;
    out vec4 fragColor;
    void main() {
        vec4 c = texture(tex, vec2(vUV.x, mix(vUV.y, 1.0 - vUV.y, vflip)));
        c.rgb *= srgbToLinear(vTint.rgb);
        c *= vTint.a;
        fragColor = c;
    }
    """

    /// The tail of `ollin_glyph_fragment`: the atlas's normalized distance
    /// (0.5 at the edge) turned into screen-space coverage through its
    /// derivative, remapped to perceptual alpha as the Mac's is, over the tint
    /// linearized; straight alpha, like the solid path.
    static let glyphFragmentTail = """
    uniform sampler2D atlas;
    in vec2 vUV;
    in vec4 vTint;
    out vec4 fragColor;
    void main() {
        float sd = texture(atlas, vUV).r;
        float d = sd - 0.5;
        float aa = fwidth(d);
        float cov = (aa > 0.0) ? smoothstep(-aa, aa, d) : step(0.0, d);
        cov = perceptualCoverage(clamp(cov, 0.0, 1.0));
        fragColor = vec4(srgbToLinear(vTint.rgb), vTint.a * cov);
    }
    """

    // MARK: Composed 2D fields

    /// The covering quad of one composed field, as `ollin_sdfgroup_vertex` builds
    /// it: the field's AABB half-extent about its center, placed by the group's
    /// transform, the field-local point handed on for the VM. The group's 26
    /// floats arrive as seven rows: the two axis columns and the translation of
    /// the transform with the center; the size with the stroke width and the
    /// band width; the stroke slot; the fill gradient geometry; the program's
    /// start and length with the fill kind and row; the stroke kind and row.
    static let groupVertex = """
    #version 300 es
    precision highp float;
    precision highp int;
    uniform vec4 group[7];
    uniform vec2 viewport;
    uniform float ollin_flip;
    out vec2 vField;
    void main() {
        vec2 corners[6] = vec2[6](vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(1.0, 1.0),
                                  vec2(-1.0, -1.0), vec2(1.0, 1.0), vec2(-1.0, 1.0));
        vec2 local = corners[gl_VertexID] * group[2].xy;
        vec2 field = group[1].zw + local;
        vec2 sketch = group[0].xy * field.x + group[0].zw * field.y + group[1].xy;
        gl_Position = vec4((sketch.x / viewport.x) * 2.0 - 1.0, (1.0 - (sketch.y / viewport.y) * 2.0) * ollin_flip, 0.0, 1.0);
        vField = field;
    }
    """

    /// The tail of `ollin_sdfgroup_fragment`: the program read from the page's
    /// uniform block (four rows a node, the kind and the op as floats), walked
    /// by the same two stacks over the translated leaf, combine, modify, and
    /// transform arithmetic, then the merged field's coverage and paints
    /// resolved exactly as the Mac's fragment resolves them.
    static let groupFragmentTail = """
    layout(std140) uniform Nodes { vec4 nodeRows[1024]; };
    uniform vec4 group[7];
    in vec2 vField;
    out vec4 fragColor;
    SDFNode readNode(int i) {
        SDFNode nd;
        vec4 r0 = nodeRows[i * 4];
        nd.kind = uint(r0.x + 0.5);
        nd.sel = uint(r0.y + 0.5);
        nd.k = r0.z;
        nd.extra = r0.w;
        nd.color = nodeRows[i * 4 + 1];
        nd.geo0 = nodeRows[i * 4 + 2];
        nd.geo1 = nodeRows[i * 4 + 3];
        return nd;
    }
    void main() {
        vec2 p = vField;
        float distStack[16];
        vec4 colStack[16];
        vec2 pointStack[16];
        int sp = 0;
        int pp = 0;
        int count = int(group[5].y + 0.5);
        for (int i = 0; i < count; i++) {
            SDFNode nd = readNode(i);
            switch (nd.kind) {
            case 0u: {
                float d = ollin_sdf_distance(nd.sel, p, nd.geo0.xy, nd.geo0.zw,
                                             nd.geo1.xy, nd.geo1.zw, nd.extra);
                if (sp < 16) { distStack[sp] = d; colStack[sp] = nd.color; sp++; }
                break;
            }
            case 1u:
                if (sp >= 2) {
                    float d; vec4 c;
                    ollin_sdf_combine(nd.sel, distStack[sp-2], colStack[sp-2],
                                      distStack[sp-1], colStack[sp-1], nd.k, nd.extra, d, c);
                    sp -= 1;
                    distStack[sp-1] = d; colStack[sp-1] = c;
                }
                break;
            case 2u:
                if (sp >= 1) {
                    distStack[sp-1] = (nd.sel == 0u) ? (distStack[sp-1] - nd.k)
                                                     : (abs(distStack[sp-1]) - nd.k);
                }
                break;
            case 3u:
                if (pp < 16) { pointStack[pp] = p; pp++; }
                p = ollin_sdf_xform(p, nd);
                break;
            default:
                if (pp > 0) { pp--; p = pointStack[pp]; }
                if (nd.k != 1.0 && sp >= 1) { distStack[sp-1] *= nd.k; }
                break;
            }
        }
        float d = (sp >= 1) ? distStack[sp-1] : 1.0e9;
        vec4 fillColor = (sp >= 1) ? colStack[sp-1] : vec4(0.0);
        float fillCov = 0.0, strokeCov = 0.0;
        float strokeWidth = group[2].z;
        float hw = strokeWidth * 0.5;
        regionCoverage(d, hw, strokeWidth, 0.0, fillCov, strokeCov);
        uint fillKind = uint(group[5].z + 0.5);
        uint strokeKind = uint(group[6].x + 0.5);
        vec3 fillLin; float fillBaseA;
        if (fillKind == 0u) { fillLin = srgbToLinear(fillColor.rgb); fillBaseA = fillColor.a; }
        else {
            vec4 fp = resolvePaint(group[4], fillKind, group[5].w, vField, 0.0);
            fillLin = fp.rgb; fillBaseA = fp.a;
        }
        float fillA = fillBaseA * fillCov;
        vec3 strokeLin; float strokeBaseA;
        if (strokeKind == 0u) { strokeLin = srgbToLinear(group[3].rgb); strokeBaseA = group[3].a; }
        else {
            vec4 sp2 = resolvePaint(group[3], strokeKind, group[6].y, vField, 0.0);
            strokeLin = sp2.rgb; strokeBaseA = sp2.a;
        }
        float strokeA = strokeBaseA * strokeCov;
        vec3 premul = strokeLin * strokeA + fillLin * fillA * (1.0 - strokeA);
        float a = strokeA + fillA * (1.0 - strokeA);
        if (a <= 0.0) { fragColor = vec4(0.0); return; }
        fragColor = vec4(premul / a, a);
    }
    """

    // MARK: Raymarched 3D fields

    /// One oversized triangle over the canvas, like `ollin_raymarch_vertex`, its
    /// clip position handed on for the ray.
    static let fieldVertex = """
    #version 300 es
    precision highp float;
    out vec2 vClip;
    void main() {
        vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
        gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
        vClip = p * 2.0 - 1.0;
    }
    """

    /// The punctual half of `meshLitColor` as the page spells it: the four
    /// shading models under directional, point, and spot lights with the wrap
    /// term and the cone, the one caster's self-shadow factor, the subsurface
    /// bleed, the iridescent sheen in both of its modes, the sparkle, and the
    /// rim, each inert at its zero value as on the Mac. A field carries no
    /// tangent, no map, no coat, sheen, film, or brushing (the recorder refuses
    /// those), no environment, and no fog, so those branches are not here. The
    /// physically-based lobe prices its energy from the same split-sum table the
    /// Mac bakes, carried as a page asset.
    static let fieldLightingSource = """
    uniform vec4 uAmbient;
    uniform vec4 uEye;
    uniform vec4 uCounts;
    uniform vec4 uLights[40];
    uniform vec4 uCasters[4];
    uniform vec4 uMaterial[9];
    uniform vec4 uScale;
    uniform sampler2D brdfLUT;
    float pbrDGGX(float NoH, float roughness) {
        float a = roughness * roughness;
        float d = NoH * a;
        float k = a / (1.0 - NoH * NoH + d * d);
        return k * k * (1.0 / 3.14159265);
    }
    float pbrVSmithGGX(float NoV, float NoL, float roughness) {
        float a = roughness * roughness;
        float a2 = a * a;
        float GGXV = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
        float GGXL = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
        return 0.5 / max(GGXV + GGXL, 1e-5);
    }
    vec3 pbrFSchlick(float VoH, vec3 F0) {
        float f = pow(1.0 - VoH, 5.0);
        return F0 + (vec3(1.0) - F0) * f;
    }
    float pbrEss(float NoV, float rough) {
        vec2 ab = texture(brdfLUT, vec2(NoV, rough)).rg;
        return clamp(ab.x + ab.y, 0.0, 1.0);
    }
    vec3 pbrEnergyComp(vec3 F0, float ess) {
        return 1.0 + F0 * (1.0 / max(ess, 0.1) - 1.0);
    }
    float sssTranslucency(vec3 viewDir, vec3 toLight, vec3 n) {
        vec3 bent = normalize(toLight + n * 0.35);
        float through = pow(max(dot(viewDir, -bent), 0.0), 3.0);
        float thin = 1.0 - max(dot(n, viewDir), 0.0);
        float thickness = 0.35 + 0.65 * thin;
        return (through + 0.22) * thickness;
    }
    vec4 litColor(vec3 base, float alpha, vec3 normal, vec3 worldPos, float fieldShadow[4]) {
        vec3 n = normalize(normal);
        if (uEye.w == 0.0) { return vec4(base, alpha); }
        vec3 viewDir = normalize(uEye.xyz - worldPos);
        float specStrength = uMaterial[5].x;
        float specularSharpness = max(uMaterial[5].y, 1.0);
        int model = int(uMaterial[6].z + 0.5);
        float bands = max(uMaterial[6].y, 1.0);
        float metallic = uMaterial[6].w;
        bool wantsSSS = uMaterial[1].a > 0.0;
        vec3 lit;
        if (model == 2) { lit = vec3(0.0); }
        else if (model == 3) { lit = uAmbient.rgb * base * (1.0 - metallic); }
        else { lit = uAmbient.rgb * base; }
        vec3 incoming = uAmbient.rgb;
        vec3 sssAccum = vec3(0.0);
        vec3 keyToLight = vec3(0.0, 1.0, 0.0);
        bool haveKey = false;
        int lightCount = int(uCounts.x + 0.5);
        int casterCount = int(uCounts.y + 0.5);
        for (int i = 0; i < 8; i++) {
            if (i >= lightCount) { break; }
            vec4 Lcolor = uLights[i * 5];
            vec4 Lpos = uLights[i * 5 + 1];
            vec4 Ldir = uLights[i * 5 + 2];
            vec4 Lp = uLights[i * 5 + 3];
            vec4 Lspec = uLights[i * 5 + 4];
            int kind = int(Lp.x + 0.5);
            int cs = -1;
            for (int c = 0; c < 4; c++) {
                if (c >= casterCount) { break; }
                if (int(uCasters[c].x + 0.5) == i) { cs = c; break; }
            }
            vec3 toLight;
            float atten = 1.0;
            if (kind == 0) {
                toLight = Ldir.xyz;
            } else {
                toLight = normalize(Lpos.xyz - worldPos);
                if (kind == 2) {
                    float cosA = dot(-toLight, Ldir.xyz);
                    atten = smoothstep(Lp.z, Lp.y, cosA);
                }
            }
            if (cs >= 0) {
                float lit01 = fieldShadow[cs];
                atten *= mix(1.0, lit01, uCasters[cs].y);
            }
            if (!haveKey) { keyToLight = toLight; haveKey = true; }
            float raw = dot(n, toLight);
            float ndl = max((raw + Lp.w) / (1.0 + Lp.w), 0.0);
            vec3 h = normalize(toLight + viewDir);
            float specRaw = (ndl > 0.0) ? pow(max(dot(n, h), 0.0), specularSharpness) : 0.0;
            vec3 specCol = Lspec.rgb * (specRaw * specStrength);
            if (model == 1) {
                float d = ceil(ndl * bands) / bands;
                float spec = (specRaw > 0.5) ? specStrength : 0.0;
                lit += atten * (Lcolor.rgb * base * d + Lspec.rgb * spec);
            } else if (model == 2) {
                lit += atten * specCol;
            } else if (model == 3) {
                float NoL = max(raw, 0.0);
                if (NoL > 0.0) {
                    float rough = clamp(uMaterial[7].x, 0.045, 1.0);
                    float NoV = max(dot(n, viewDir), 1e-4);
                    float NoH = max(dot(n, h), 0.0);
                    float VoH = max(dot(viewDir, h), 0.0);
                    vec3 F0 = mix(vec3(uMaterial[7].w), base, metallic);
                    float D = pbrDGGX(NoH, rough);
                    float Vis = pbrVSmithGGX(NoV, NoL, rough);
                    vec3 F = pbrFSchlick(VoH, F0);
                    vec3 spec = D * Vis * F * pbrEnergyComp(F0, pbrEss(NoV, rough));
                    vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);
                    vec3 diff = kD * base * (1.0 / 3.14159265);
                    lit += (diff + spec) * Lcolor.rgb * (atten * NoL);
                }
            } else {
                lit += atten * (Lcolor.rgb * base * ndl + specCol);
            }
            incoming += atten * Lcolor.rgb * ndl;
            if (wantsSSS) {
                sssAccum += atten * Lcolor.rgb * sssTranslucency(viewDir, toLight, n);
            }
        }
        if (model == 2) {
            float t = dot(n, keyToLight) * 0.5 + 0.5;
            lit += mix(uMaterial[3].rgb, uMaterial[2].rgb, t) * base;
        }
        if (wantsSSS) {
            lit += uMaterial[1].a * uMaterial[1].rgb * base * sssAccum;
        }
        float iridescence = uMaterial[5].z;
        if (iridescence > 0.0) {
            float fres = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), 3.0);
            float irrad = dot(incoming, vec3(0.299, 0.587, 0.114));
            float iridescenceScale = uMaterial[5].w;
            float flow = uMaterial[8].x;
            if (flow > 0.0) {
                float cell = max(uScale.w, 1e-4) * 0.35 * uMaterial[8].z;
                vec3 q = worldPos / cell;
                float t = uMaterial[8].y;
                vec3 d1 = vec3(0.12 * t, -0.30 * t, 0.0);
                vec3 d2 = vec3(-0.22 * t, -0.50 * t, 0.09 * t);
                float wa = fbm(q * 1.2 + d1) * 2.0 - 1.0;
                float wb = fbm(q * 1.2 + d1 + vec3(4.7, 9.1, 2.3)) * 2.0 - 1.0;
                float wm = fbm(q * 2.3 + d2 + vec3(wa, wb, 0.5 * (wa - wb)) * 3.2) * 2.0 - 1.0;
                float head = 0.5 - 0.5 * clamp(n.y, -1.0, 1.0);
                float d = iridescenceScale
                        * max(0.18 + 1.1 * head * head + flow * (0.35 * wa + 0.55 * wm), 0.0);
                vec3 rate = vec3(1.0, 1.2146, 1.4513);
                vec3 wave = 0.5 - 0.5 * cos(6.2831853 * d * rate);
                float coh = exp(-0.18 * d);
                vec3 filmC = mix(vec3(0.5), wave, coh);
                float body = mix(0.35, 1.0, fres);
                lit += iridescence * body * filmC * (0.15 + 0.85 * irrad);
            } else {
                float phase = fres * iridescenceScale;
                vec3 rainbow = 0.5 + 0.5 * cos(6.2831853 * (phase + vec3(0.0, 0.3333, 0.6667)));
                lit += iridescence * fres * rainbow * (0.15 + 0.85 * irrad);
            }
        }
        if (uMaterial[4].a > 0.0) {
            float sparkleSize = uMaterial[7].y;
            float cell = max(uScale.w, 1e-4) * 0.0022 * sparkleSize;
            vec3 q = worldPos / cell;
            vec3 rnd = hash33(floor(q));
            float soft = max(0.05, 0.26 / sparkleSize);
            float mask = smoothstep(0.5, 0.5 - soft, length(fract(q) - 0.5));
            vec3 flakeN = normalize(n + (rnd * 2.0 - 1.0) * 0.7);
            float align = clamp(dot(flakeN, viewDir), 0.0, 1.0);
            float sharp = uMaterial[7].z;
            float flash = pow(align, sharp) + 0.18 * pow(align, sharp * 0.12);
            float irrad = dot(incoming, vec3(0.299, 0.587, 0.114));
            lit += uMaterial[4].a * 1.6 * flash * mask * uMaterial[4].rgb * (0.15 + 0.85 * irrad);
        }
        if (uMaterial[0].a > 0.0) {
            float rim = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), uMaterial[6].x);
            lit += uMaterial[0].a * rim * uMaterial[0].rgb;
        }
        return vec4(lit, alpha);
    }
    """

    /// The tail of `ollin_raymarch_fragment`: the field's program read from the
    /// page's uniform block and walked by the same stacks over the translated
    /// leaf, combine, modify, and transform arithmetic (the roughening's noise
    /// among them); the world ray rebuilt through the inverse view-projection;
    /// the sphere trace with its pixel-cone coverage at the silhouette; the
    /// tetrahedron normal; the analytic self-shadow toward the one caster; the
    /// leaf color or the screen-space gradient; the lighting above; and the
    /// hit's depth through the camera, written as the fragment's own. The
    /// field's 36 floats arrive as nine rows: the inverse model by columns, the
    /// bounds with the model scale and the unbounded flag, the gradient
    /// geometry, the program's place and length with the paint kind and row,
    /// and the normal step. `ollin_flip` turns the ray's clip position over
    /// where the surface is rasterized upright under multisampling, the way the
    /// other stages turn their positions.
    static let fieldFragmentTail = """
    layout(std140) uniform Nodes { vec4 nodeRows[1024]; };
    uniform vec4 field[9];
    uniform mat4 uView;
    uniform mat4 uProj;
    uniform mat4 uInvVP;
    uniform vec4 uViewportSteps;
    uniform float ollin_flip;
    in vec2 vClip;
    out vec4 fragColor;
    const float OLLIN_RAYMARCH_STEP_SCALE = 0.85;
    const float OLLIN_RAYMARCH_EPS = 0.001;
    const float OLLIN_SDF3D_SHADOW_K = 10.0;
    SDFNode3D readNode3D(int i) {
        SDFNode3D nd;
        vec4 r0 = nodeRows[i * 4];
        nd.kind = uint(r0.x + 0.5);
        nd.sel = uint(r0.y + 0.5);
        nd.k = r0.z;
        nd.extra = r0.w;
        nd.color = nodeRows[i * 4 + 1];
        nd.geo0 = nodeRows[i * 4 + 2];
        nd.geo1 = nodeRows[i * 4 + 3];
        return nd;
    }
    float fieldDistance(vec3 p0, out vec4 outColor) {
        float distStack[16];
        vec4 colStack[16];
        vec3 pointStack[16];
        int sp = 0;
        int pp = 0;
        vec3 p = p0;
        int count = int(field[7].y + 0.5);
        for (int i = 0; i < count; i++) {
            SDFNode3D nd = readNode3D(i);
            switch (nd.kind) {
            case 0u: {
                float d = ollin_sdf3d_eval(nd.sel, p, nd.geo0, nd.geo1);
                if (sp < 16) { distStack[sp] = d; colStack[sp] = nd.color; sp++; }
                break;
            }
            case 1u:
                if (sp >= 2) {
                    float d; vec4 c;
                    ollin_sdf3d_combine(nd.sel, distStack[sp-2], colStack[sp-2],
                                        distStack[sp-1], colStack[sp-1], nd.k, nd.extra, d, c);
                    sp -= 1;
                    distStack[sp-1] = d; colStack[sp-1] = c;
                }
                break;
            case 2u:
                if (sp >= 1) {
                    switch (nd.sel) {
                    case 0u: distStack[sp-1] -= nd.k; break;
                    case 1u: distStack[sp-1] = abs(distStack[sp-1]) - nd.k; break;
                    case 2u: {
                        float f = nd.extra;
                        float disp = nd.k * sin(f * p.x) * sin(f * p.y) * sin(f * p.z);
                        distStack[sp-1] = (distStack[sp-1] + disp) * nd.geo0.x;
                        break;
                    }
                    default: {
                        float nse = valueNoise(p * nd.extra) * 2.0 - 1.0;
                        distStack[sp-1] = (distStack[sp-1] + nd.k * nse) * nd.geo0.x;
                        break;
                    }
                    }
                }
                break;
            case 3u:
                if (pp < 16) { pointStack[pp] = p; pp++; }
                p = ollin_sdf3d_xform(p, nd);
                break;
            default:
                if (pp > 0) { pp--; p = pointStack[pp]; }
                if (nd.k != 1.0 && sp >= 1) { distStack[sp-1] *= nd.k; }
                break;
            }
        }
        outColor = (sp >= 1) ? colStack[sp-1] : vec4(0.0);
        return (sp >= 1) ? distStack[sp-1] : 1.0e9;
    }
    float worldDistance(vec3 pw, out vec4 col) {
        mat4 inv = mat4(field[0], field[1], field[2], field[3]);
        vec3 pl = (inv * vec4(pw, 1.0)).xyz;
        return fieldDistance(pl, col) * field[4].w;
    }
    vec3 fieldNormal(vec3 pw) {
        float e = field[8].x > 0.0 ? field[8].x : 0.0008;
        vec2 k = vec2(1.0, -1.0);
        vec4 dummy;
        return normalize(
            k.xyy * worldDistance(pw + k.xyy * e, dummy) +
            k.yyx * worldDistance(pw + k.yyx * e, dummy) +
            k.yxy * worldDistance(pw + k.yxy * e, dummy) +
            k.xxx * worldDistance(pw + k.xxx * e, dummy));
    }
    float softShadow(vec3 ro, vec3 rd, float maxt, float k, int steps) {
        float res = 1.0;
        float t = 0.02;
        vec4 dummy;
        for (int i = 0; i < steps; i++) {
            if (t >= maxt) { break; }
            float h = worldDistance(ro + rd * t, dummy);
            if (h < 0.001) { return 0.0; }
            res = min(res, k * h / t);
            t += h * OLLIN_RAYMARCH_STEP_SCALE;
        }
        return clamp(res, 0.0, 1.0);
    }
    vec2 rayBox(vec3 ro, vec3 rd, vec3 lo, vec3 hi) {
        vec3 inv = 1.0 / rd;
        vec3 ta = (lo - ro) * inv;
        vec3 tb = (hi - ro) * inv;
        vec3 tmn = min(ta, tb), tmx = max(ta, tb);
        float t0 = max(max(tmn.x, tmn.y), tmn.z);
        float t1 = min(min(tmx.x, tmx.y), tmx.z);
        return vec2(t0, t1);
    }
    void main() {
        vec2 ndc = vec2(vClip.x, vClip.y * ollin_flip);
        vec4 nearH = uInvVP * vec4(ndc, 0.0, 1.0);
        vec4 farH = uInvVP * vec4(ndc, 1.0, 1.0);
        vec3 nearW = nearH.xyz / nearH.w;
        vec3 farW = farH.xyz / farH.w;
        vec3 ro = nearW;
        vec3 rd = normalize(farW - nearW);
        vec3 boundsMin = field[4].xyz;
        vec3 boundsMax = field[5].xyz;
        float t0, t1;
        if (field[5].w != 0.0) {
            t0 = 0.0;
            t1 = length(farW - nearW);
        } else {
            vec2 tb = rayBox(ro, rd, boundsMin, boundsMax);
            t0 = max(tb.x, 0.0);
            t1 = tb.y;
            if (t1 < t0) { discard; }
        }
        float kPixel = 1.0 / (max(uProj[1][1], 1e-4)
                              * max(uViewportSteps.y * max(uScale.x, 1e-3), 1.0));
        bool orthographic = uProj[2][3] == 0.0;
        float t = t0;
        vec4 col = vec4(0.0);
        bool hit = false;
        float minRatio = 1.0e9;
        float tNear = t0;
        int steps = int(uViewportSteps.z + 0.5);
        for (int i = 0; i < steps; i++) {
            if (t > t1) { break; }
            vec3 pw = ro + rd * t;
            float d = worldDistance(pw, col);
            if (d < OLLIN_RAYMARCH_EPS) { hit = true; break; }
            float ratio = d / max((orthographic ? 1.0 : t) * kPixel, 1e-6);
            if (ratio < minRatio) { minRatio = ratio; tNear = t; }
            t += d * OLLIN_RAYMARCH_STEP_SCALE;
        }
        float coverage = 1.0;
        vec3 pw;
        if (hit) {
            pw = ro + rd * t;
        } else {
            coverage = clamp(1.0 - minRatio, 0.0, 1.0);
            if (coverage < 0.004) { discard; }
            pw = ro + rd * tNear;
            worldDistance(pw, col);
        }
        vec3 n = fieldNormal(pw);
        float fieldShadow[4];
        fieldShadow[0] = -1.0; fieldShadow[1] = -1.0; fieldShadow[2] = -1.0; fieldShadow[3] = -1.0;
        int casterCount = int(uCounts.y + 0.5);
        if (uEye.w != 0.0) {
            float fieldDiag = length(boundsMax - boundsMin);
            int shadowSteps = int(uViewportSteps.w + 0.5);
            for (int c = 0; c < 4; c++) {
                if (c >= casterCount) { break; }
                int li = int(uCasters[c].x + 0.5);
                vec4 Lpos = uLights[li * 5 + 1];
                vec4 Ldir = uLights[li * 5 + 2];
                int kind = int(uLights[li * 5 + 3].x + 0.5);
                vec3 toLight; float maxt;
                if (kind == 0) {
                    toLight = Ldir.xyz; maxt = fieldDiag;
                } else {
                    vec3 dl = Lpos.xyz - pw;
                    float dist = length(dl);
                    toLight = dl / max(dist, 1e-5);
                    maxt = min(dist, fieldDiag);
                }
                fieldShadow[c] = softShadow(pw + n * 0.015, toLight, maxt, OLLIN_SDF3D_SHADOW_K, shadowSteps);
            }
        }
        vec3 baseRGB = srgbToLinear(col.rgb);
        float baseA = col.a;
        uint fillKind = uint(field[7].z + 0.5);
        if (fillKind != 0u) {
            vec4 clipP = uProj * (uView * vec4(pw, 1.0));
            vec2 ndcP = clipP.xy / clipP.w;
            vec2 screenP = vec2((ndcP.x * 0.5 + 0.5) * uViewportSteps.x,
                                (0.5 - ndcP.y * 0.5) * uViewportSteps.y);
            vec4 grad = resolvePaint(field[6], fillKind, field[7].w, screenP, 0.0);
            baseRGB = grad.rgb;
            baseA = grad.a;
        }
        vec4 lit = litColor(baseRGB, baseA, n, pw, fieldShadow);
        vec4 clip = uProj * (uView * vec4(pw, 1.0));
        fragColor = vec4(lit.rgb, lit.a * coverage);
        gl_FragDepth = clip.z / clip.w;
    }
    """

    /// `ollin_raymarch_upsample_fragment`: the reduced-resolution march read
    /// back at full resolution, its color bilinear and its depth point-sampled,
    /// the depth re-emitted as the fragment's own so the fields keep occluding
    /// one another, the background left alone.
    static let upsampleFragment = """
    #version 300 es
    precision highp float;
    uniform sampler2D halfColor;
    uniform sampler2D halfDepth;
    uniform vec4 region;
    uniform float ollin_flip;
    in vec2 vClip;
    out vec4 fragColor;
    void main() {
        vec2 uv = vec2(vClip.x * 0.5 + 0.5, vClip.y * ollin_flip * 0.5 + 0.5);
        uv = min(uv * region.xy, region.zw);
        vec4 c = texture(halfColor, uv);
        if (c.a < 0.004) { discard; }
        fragColor = c;
        gl_FragDepth = texture(halfDepth, uv).r;
    }
    """
}

/// A user shader as a page fragment: the framework's wrapper written for the
/// page (the `ShaderInfo` the user's `shade` reads, the readers over the layers
/// the pass binds, the clock and pointer as uniforms), the helper library's
/// sections the shader asked for and the user's own source both carried by the
/// token rewriter, and a `main` that converts the straight sRGB result to the
/// premultiplied linear a layer holds, as `ollin_user_fragment` does.
enum WebUserShaderGLSL {
    static func make(_ user: WebUserShader) throws -> String {
        // The library sections the shader asked for, then the user's text, each
        // through the rewriter; the user's `ShaderInfo` references are by value
        // on the page, where Metal took them by reference.
        let modules = Shader.Modules(rawValue: user.modules)
        var sections: Set<String> = []
        if modules.contains(.hash) { sections.insert("hash") }
        if modules.contains(.noise) { sections.insert("noise") }
        if modules.contains(.color) { sections.insert("color") }
        if modules.contains(.sdf) { sections.insert("sdf") }
        if modules.contains(.domain) { sections.insert("domain") }
        if modules.contains(.visual) { sections.insert("visual") }
        let library = WebShaderLibrary.translate(WebShaderSources.library, wanted: sections)
        guard library.isClean else { throw WebShaderError(diagnostics: library.unsupported) }
        let source = user.source
            .replacingOccurrences(of: "thread const ShaderInfo &", with: "const ShaderInfo ")
            .replacingOccurrences(of: "thread const ShaderInfo&", with: "const ShaderInfo ")
            .replacingOccurrences(of: "thread ShaderInfo &", with: "ShaderInfo ")
            .replacingOccurrences(of: "thread ShaderInfo&", with: "ShaderInfo ")
        let body = WebShaderTranslator.translate(source)
        guard body.isClean else {
            throw WebExportRefusal(call: "a Shader the page cannot carry (\(user.name): "
                                   + body.unsupported.map(\.message).joined(separator: "; ") + ")", frame: 0)
        }
        let support = WebShaderCompat.source(for: library.helpers.union(body.helpers),
                                             constants: library.constants.union(body.constants))

        var out = WebShaderCompat.preamble
        if !support.isEmpty { out += support + "\n\n" }
        out += "in vec2 uv;\nuniform vec2 ollin_viewport;\n"
        if user.variant >= 1 { out += "uniform sampler2D ollin_src0;\n" }
        if user.variant >= 2 { out += "uniform sampler2D ollin_src1;\n" }
        out += """
        uniform vec2 ollin_resolution;
        uniform vec2 ollin_mouse;
        uniform float ollin_time;
        uniform float ollin_dt;
        uniform uint ollin_frame;
        uniform uint ollin_paramCount;
        uniform vec4 ollin_params[16];
        \(WebFragmentTranslator.readHelpers)

        """
        out += library.body + "\n\n"
        out += """
        struct ShaderInfo {
            vec2 resolution;
            vec2 mouse;
            float time;
            float deltaTime;
            uint frame;
            uint paramCount;
            vec4 params[16];
        };
        float param(ShaderInfo info, int i) { return info.params[i >> 2][i & 3]; }
        float param(ShaderInfo info, uint i) { return info.params[int(i >> 2u)][int(i & 3u)]; }
        vec4 ollin_layer_sample(sampler2D t, vec2 q) { vec4 c = ollin_tex(t, clamp(q, 0.0, 1.0)); return vec4(linearToSrgb(ollin_unpremul(c)), c.a); }
        vec4 ollin_layer_read(sampler2D t, vec2 q) { return ollin_tex(t, clamp(q, 0.0, 1.0)); }

        """
        if user.variant >= 1 {
            out += """
            vec4 sample_(ShaderInfo info, vec2 p) { return ollin_layer_sample(ollin_src0, p); }
            vec4 sampleRaw(ShaderInfo info, vec2 p) { return ollin_layer_read(ollin_src0, p); }

            """
        }
        if user.variant >= 2 {
            out += """
            vec4 sampleAux(ShaderInfo info, vec2 p) { return ollin_layer_sample(ollin_src1, p); }
            vec4 sampleAuxRaw(ShaderInfo info, vec2 p) { return ollin_layer_read(ollin_src1, p); }

            """
        }
        out += body.body + "\n\n"
        out += """
        out vec4 fragColor;
        void main() {
            ShaderInfo info;
            info.resolution = ollin_resolution;
            info.mouse = ollin_mouse;
            info.time = ollin_time;
            info.deltaTime = ollin_dt;
            info.frame = ollin_frame;
            info.paramCount = ollin_paramCount;
            for (int i = 0; i < 16; ++i) info.params[i] = ollin_params[i];
            vec4 c = shade(uv, info);
            fragColor = vec4(srgbToLinear(c.rgb) * c.a, c.a);
        }

        """
        return out
    }
}

// MARK: - The page

/// The two forms of the page: one self-contained file, or the fragment (the
/// canvas plus one script block) for a page of your own.
public enum WebPageForm: String, Sendable {
    case standalone
    case inline
}

extension OllinApp {
    /// The page text for a recording, in either form. The inline fragment is the
    /// whole of what the standalone page wraps, so the two draw the same pixels.
    /// The standalone page lays the controls out under the canvas when the
    /// recording offers any and `panel` allows it; the inline fragment never
    /// draws a panel, since the page around it owns the layout, and reaches
    /// the controls through the handle instead.
    ///
    /// `maxBytes` is the most the page may weigh; past it the page is not
    /// returned and a `WebWeightRefusal` says what made it heavy. `nil` lifts
    /// the limit.
    static func webPage(of recording: WebRecording, form: WebPageForm, panel: Bool = true,
                        maxBytes: Int? = nil) throws -> String {
        let showsPanel = panel && form == .standalone && !recording.controls.isEmpty
        // The wrapper's own bytes count toward the page, and are known before
        // the fragment exists.
        let wrapper = form == .standalone ? webStandalonePage(around: "", of: recording, showsPanel: showsPanel).utf8.count : 0
        let (fragment, _) = try webInlineFragment(of: recording, panel: showsPanel, maxBytes: maxBytes, wrapperBytes: wrapper)
        return form == .standalone ? webStandalonePage(around: fragment, of: recording, showsPanel: showsPanel) : fragment
    }

    /// The refusal for a page past its budget: the heaviest part, whether it
    /// grows with the frame count, and what it holds.
    static func webWeightRefusal(of recording: WebRecording, weights: [WebWeight], pageBytes: Int, maxBytes: Int) -> WebWeightRefusal {
        // The shaders and the player are what is left of the page once the
        // track and the assets are counted.
        var parts = weights
        let counted = parts.reduce(0) { $0 + $1.bytes }
        parts.append(WebWeight(name: "the shaders and the player", once: max(0, pageBytes - counted), perFrame: 0))
        let heaviest = parts.max { $0.bytes < $1.bytes } ?? parts[0]
        let frames = "\(recording.frames.count) frame\(recording.frames.count == 1 ? "" : "s")"
        let track = WebTrack.vertexCount(of: recording)
        var detail = ""
        switch heaviest.name {
        case "stroke and fill vertices":
            detail = "\(track) vertices in the fullest frame, \(frames)"
        case "strokes and fills as points":
            detail = "\(WebTrack.sourceCount(of: recording)) strokes and fills as points in the fullest frame, \(frames)"
        case "shapes and passes":
            detail = "\(recording.frames.first?.graph.instanceCount ?? 0) shapes in the first frame, \(frames)"
        case "scenes":
            detail = "one scene block per frame, \(frames)"
        case "pictures":
            detail = "\(recording.pictures.count) picture\(recording.pictures.count == 1 ? "" : "s")"
        case "atlas pages":
            detail = "\(recording.atlases.count) page\(recording.atlases.count == 1 ? "" : "s")"
        default:
            break
        }
        return WebWeightRefusal(bytes: pageBytes, maxBytes: maxBytes, heaviest: heaviest.name,
                                heaviestBytes: heaviest.bytes, growsWithFrames: heaviest.growsWithFrames, detail: detail, seen: nil)
    }

    /// The whole file around the inline fragment.
    private static func webStandalonePage(around fragment: String, of recording: WebRecording, showsPanel: Bool) -> String {
        let paper = recording.frames.first?.clear ?? SIMD3<Float>(0, 0, 0)
        let ratio = formatted(Double(recording.width) / Double(recording.height))
        // With a panel, the canvas leaves room for it and the panel's text
        // reads against the paper.
        let luminance = 0.2126 * paper.x + 0.7152 * paper.y + 0.0722 * paper.z
        let ink = luminance > 0.18 ? "#1d1d1f" : "#e8e8ed"
        let layout = showsPanel
            ? "body { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 14px; }\n"
                + "canvas.ollin-sketch { width: min(100vw, calc((100vh - var(--ollin-panel, 0px)) * \(ratio))); height: auto; }\n"
                + ".ollin-controls { color: \(ink); }"
            : "body { display: flex; align-items: center; justify-content: center; }\n"
                + "canvas.ollin-sketch { width: min(100vw, calc(100vh * \(ratio))); height: auto; }"
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="generator" content="Ollin">
        <title>\(htmlEscaped(recording.name))</title>
        <style>
        html, body { margin: 0; height: 100%; background: \(cssColor(linear: paper)); }
        \(layout)
        </style>
        </head>
        <body>
        \(fragment)
        </body>
        </html>

        """
    }

    /// The canvas and its script: the player, the page's shaders, and the track.
    /// `panel` has the script build the controls under the canvas.
    ///
    /// With `maxBytes`, the page's weight (the fragment plus `wrapperBytes`)
    /// is checked before the text is assembled, since a page past the limit
    /// is never built: the slots' sizes say what the fill would come to.
    static func webInlineFragment(of recording: WebRecording, panel: Bool = false,
                                  maxBytes: Int? = nil, wrapperBytes: Int = 0) throws -> (String, [WebWeight]) {
        var rows: [String: Int] = [:]
        for frame in recording.frames {
            for (name, r) in frame.graph.fragmentRows { rows[name] = max(rows[name] ?? 0, r) }
        }
        let shaders = try WebShaders.make(effects: rows, users: recording.shaders,
                                          groups: recording.frames.contains { $0.graph.groupCount > 0 },
                                          fields: recording.frames.contains { $0.graph.hasFields })
        let track = WebTrack(recording)
        let label = recording.description.isEmpty
            ? "\(recording.name), a sketch made with Ollin"
            : recording.description
        // The slots hold the track, which can run to hundreds of megabytes, so
        // they are filled in one pass: a substitution per slot is a copy of the
        // whole page per slot, minutes on a page that size.
        var slots: [String: String] = [:]
        slots["META"] = track.meta
        slots["STREAM"] = track.stream
        slots["BASE"] = track.base
        slots["VBASE"] = track.vertexBase
        slots["VPOS"] = track.vertexPositions
        slots["FIT"] = track.fit
        slots["EXTRA"] = track.extra
        slots["RANGES"] = track.ranges
        slots["VARYING"] = track.varying
        slots["SCENE"] = track.scene
        slots["AXES"] = track.axisData
        slots["PANEL"] = panel ? "true" : "false"
        // The expander, when any frame carries a stroke or a fill as its points.
        let expands = recording.frames.contains { $0.graph.sourceFloats > 0 }
        if expands, WebExpanderResource.data.isEmpty { throw WebExpanderMissing() }
        slots["EXPANDER"] = expands ? "\"\(WebExpanderResource.base64)\"" : "\"\""
        slots["HELPERS"] = FormulaJS.helpers
        slots["GROUP_VS"] = jsString(shaders.groupVertex)
        slots["GROUP_FS"] = jsString(shaders.groupFragment)
        slots["FIELD_VS"] = jsString(shaders.fieldVertex)
        slots["FIELD_FS"] = jsString(shaders.fieldFragment)
        slots["UPSAMPLE_FS"] = jsString(shaders.upsampleFragment)
        let lut = recording.brdfLUT.isEmpty ? "[0, \"\"]"
            : "[\(WebBRDFLUT.size), \"\(WebTrack.base64(recording.brdfLUT))\"]"
        slots["BRDF"] = lut
        slots["SDF_VS"] = jsString(shaders.sdfVertex)
        slots["SDF_FS"] = jsString(shaders.sdfFragment)
        slots["PRESENT_VS"] = jsString(shaders.presentVertex)
        slots["PRESENT_FS"] = jsString(shaders.presentFragment)
        slots["IMAGE_VS"] = jsString(shaders.imageVertex)
        slots["IMAGE_FS"] = jsString(shaders.imageFragment)
        slots["GLYPH_FS"] = jsString(shaders.glyphFragment)
        slots["TRI_VS"] = jsString(shaders.triangleVertex)
        slots["TRI_FS"] = jsString(shaders.triangleFragment)
        slots["FRINGE_FS"] = jsString(shaders.fringeFragment)
        slots["FX_VS"] = jsString(shaders.effectVertex)
        slots["BLUR_FS"] = jsString(WebShaders.blurFragment)
        let effectEntries = shaders.effects.keys.sorted().map { "\(jsString($0)): \(jsString(shaders.effects[$0]!))" }
        slots["FX"] = "{" + effectEntries.joined(separator: ",\n") + "}"
        slots["USERS"] = "[" + shaders.users.map(jsString).joined(separator: ",\n") + "]"
        let tables = recording.tables.map { table -> String in
            let flat = table.flatMap { [$0.x, $0.y, $0.z, $0.w] }
            return "[\(table.count), \"\(WebTrack.base64(flat))\"]"
        }
        slots["TABLES"] = "[" + tables.joined(separator: ",") + "]"
        // The assets: each picture as its file's bytes or a PNG, each atlas page
        // as a gray PNG with the page size and the rows it holds, and the
        // gradient strip's rows as raw texels (a few kilobytes at most).
        let pictures = recording.pictures.map { "[\(jsString($0.mime)), \"\($0.data.base64EncodedString())\"]" }
        slots["PICTURES"] = "[" + pictures.joined(separator: ",\n") + "]"
        let atlases = recording.atlases.map { "[\"\($0.png.base64EncodedString())\", \($0.size), \($0.rows)]" }
        slots["ATLASES"] = "[" + atlases.joined(separator: ",\n") + "]"
        let strip = Data(recording.gradientRows.joined()).base64EncodedString()
        slots["STRIP"] = "[\(recording.gradientRows.count), \(BakedGradient.width), \"\(strip)\"]"
        // The assets' weight beside the track's. A picture per version is what
        // a repainted picture costs, so pictures outnumbering half the frames
        // count as per-frame.
        var weights = track.weights
        let pictureBytes = pictures.reduce(0) { $0 + $1.utf8.count }
        if pictureBytes > 0 {
            let perFrame = recording.pictures.count * 2 > track.uniqueFrames
            weights.append(WebWeight(name: "pictures", once: perFrame ? 0 : pictureBytes, perFrame: perFrame ? pictureBytes : 0))
        }
        let atlasBytes = atlases.reduce(0) { $0 + $1.utf8.count }
        if atlasBytes > 0 { weights.append(WebWeight(name: "atlas pages", once: atlasBytes, perFrame: 0)) }
        if expands { weights.append(WebWeight(name: "the stroke expander", once: WebExpanderResource.pageBytes, perFrame: 0)) }
        let prefix = "<canvas class=\"ollin-sketch\" width=\"\(recording.width)\" height=\"\(recording.height)\" role=\"img\" aria-label=\"\(htmlEscaped(label))\"></canvas>\n<script>\n"
        let suffix = "\n</script>"
        let pageBytes = prefix.utf8.count + WebPlayer.filledCount(WebPlayer.script, with: slots) + suffix.utf8.count + wrapperBytes
        if let maxBytes, pageBytes > maxBytes {
            throw webWeightRefusal(of: recording, weights: weights, pageBytes: pageBytes, maxBytes: maxBytes)
        }
        let script = WebPlayer.filled(WebPlayer.script, with: slots)
        return (prefix + script + suffix, weights)
    }

    private static func htmlEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// A JavaScript string literal, safe inside a script element.
    nonisolated static func jsString(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "<": out += "\\x3C"
            default: out.unicodeScalars.append(c)
            }
        }
        return out + "\""
    }

    private static func cssColor(linear c: SIMD3<Float>) -> String {
        func channel(_ v: Float) -> Int {
            Int((Color.linearToSrgb(Double(max(0, min(1, v)))) * 255).rounded())
        }
        return String(format: "#%02x%02x%02x", channel(c.x), channel(c.y), channel(c.z))
    }

    private static func formatted(_ v: Double) -> String {
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

/// The player: a WebGL2 canvas that replays the track with the page's
/// shaders, the intermediate in linear light (half float where the browser
/// renders to one), the present pass on the canvas. A frame is a graph of
/// surfaces: each layer is filled in the order the Mac filled it (drawn into,
/// generated, filtered from another, combined from two, run by a user shader,
/// or carried over from last frame by a feedback layer or a simulation), the
/// canvas draws its shapes, its fills and strokes, its composed fields, and
/// its raymarched fields (each field's program in a uniform block, the frame's
/// camera and lights in a scene block that travels whole; a reduced march
/// traces into a smaller target and upsamples once, as the Mac's does), and
/// composites the layers it names, and the whole-frame filters run last. A track that draws
/// triangles rasterizes every drawn surface through a multisampled buffer
/// resolved into the surface, the way the Mac's passes resolve, so a fill's
/// edge is anti-aliased there too; an accumulating canvas keeps its samples
/// from frame to frame, as the Mac's accumulation surface does. A moving column arrives one of three ways
/// and the player works each out per frame: live, from a parameter's formula
/// evaluated on the page's clock and pointer; fitted, from the few sines of a
/// lap; or sampled, interpolated between the records when the cast is stable.
/// An accumulating or stateful track draws every frame in order. A reader who
/// asked the system for less motion sees the first frame, still. The handle on
/// the canvas (`canvas.ollin`, also `window.ollin`) plays, pauses, seeks, and
/// shows one frame.
enum WebPlayer {
    /// `template` with each `@NAME@` slot replaced by `values[NAME]`, in one
    /// pass over the template's bytes: a slot is an `@`, upper-case letters,
    /// digits, or underscores, and a closing `@`; any other `@` and a slot
    /// with no value are copied through. The values are never scanned, so one
    /// holding a slot's spelling stays as it is.
    static func filled(_ template: String, with values: [String: String]) -> String {
        var out = ""
        out.reserveCapacity(filledCount(template, with: values))
        let bytes = Array(template.utf8)
        var literalStart = 0
        for slot in slots(in: bytes) where values[slot.name] != nil {
            out += String(decoding: bytes[literalStart ..< slot.range.lowerBound], as: UTF8.self)
            out += values[slot.name]!
            literalStart = slot.range.upperBound
        }
        out += String(decoding: bytes[literalStart...], as: UTF8.self)
        return out
    }

    /// The bytes `filled` would come to, without building it.
    static func filledCount(_ template: String, with values: [String: String]) -> Int {
        var count = template.utf8.count
        for slot in slots(in: Array(template.utf8)) {
            guard let value = values[slot.name] else { continue }
            count += value.utf8.count - slot.range.count
        }
        return count
    }

    /// The slots in `bytes`: each `@NAME@` with the byte range it spans.
    private static func slots(in bytes: [UInt8]) -> [(name: String, range: Range<Int>)] {
        var found: [(name: String, range: Range<Int>)] = []
        var i = 0
        while i < bytes.count {
            guard bytes[i] == UInt8(ascii: "@") else { i += 1; continue }
            var j = i + 1
            while j < bytes.count, bytes[j] == UInt8(ascii: "_") || (bytes[j] >= UInt8(ascii: "A") && bytes[j] <= UInt8(ascii: "Z"))
                    || (bytes[j] >= UInt8(ascii: "0") && bytes[j] <= UInt8(ascii: "9")) { j += 1 }
            guard j > i + 1, j < bytes.count, bytes[j] == UInt8(ascii: "@") else { i += 1; continue }
            found.append((String(decoding: bytes[(i + 1) ..< j], as: UTF8.self), i ..< j + 1))
            i = j + 1
        }
        return found
    }

    static let script = #"""
    (function () {
      var script = document.currentScript;
      var canvas = script ? script.previousElementSibling : null;
      while (canvas && canvas.tagName !== 'CANVAS') canvas = canvas.previousElementSibling;
      if (!canvas) return;
      var D = @META@;
      var STREAM = "@STREAM@";
      var BASE = "@BASE@";
      var VBASE = "@VBASE@";
      var VPOS = "@VPOS@";
      var FIT = "@FIT@";
      var EXTRA = "@EXTRA@";
      var RANGES = "@RANGES@";
      var VARYING = "@VARYING@";
      var SCENE = "@SCENE@";
      var AXES = "@AXES@";
      var PANEL = @PANEL@;
      var SDF_VS = @SDF_VS@;
      var SDF_FS = @SDF_FS@;
      var PRESENT_VS = @PRESENT_VS@;
      var PRESENT_FS = @PRESENT_FS@;
      var IMAGE_VS = @IMAGE_VS@;
      var IMAGE_FS = @IMAGE_FS@;
      var GLYPH_FS = @GLYPH_FS@;
      var TRI_VS = @TRI_VS@;
      var TRI_FS = @TRI_FS@;
      var FRINGE_FS = @FRINGE_FS@;
      var GROUP_VS = @GROUP_VS@;
      var GROUP_FS = @GROUP_FS@;
      var FIELD_VS = @FIELD_VS@;
      var FIELD_FS = @FIELD_FS@;
      var UPSAMPLE_FS = @UPSAMPLE_FS@;
      var FX_VS = @FX_VS@;
      var BLUR_FS = @BLUR_FS@;
      var FX = @FX@;
      var USERS = @USERS@;
      var TABLES = @TABLES@;
      var PICTURES = @PICTURES@;
      var ATLASES = @ATLASES@;
      var STRIP = @STRIP@;
      var BRDF = @BRDF@;
      // The expander (empty unless the track carries strokes or fills as
      // points) is the framework's own stroke and fill expander compiled to
      // WebAssembly. It includes libtess2 by Mikko Mononen, derived from the
      // SGI OpenGL Sample Implementation: Copyright (C) [dates of first
      // publication] Silicon Graphics, Inc., under the SGI Free Software
      // License B, Version 2.0 (http://oss.sgi.com/projects/FreeB/).
      var EXPANDER = @EXPANDER@;
      @HELPERS@
      var F = 30, Q = 48, V = 7, G = 26, NF = 16, FF = 36, N3 = 16;
      var W = D.width, H = D.height;
      function ref(index) { return D.refs ? D.refs[index] : index; }
      function clearOf(index) { return D.clears ? D.clears[index] : D.clear; }
      function toneOf(index) { return D.tones ? D.tones[index] : D.tone; }
      function exposureOf(index) { return D.exposures ? D.exposures[index] : D.exposure; }
      function graphOf(index) { return D.graph ? D.graph : D.graphs[D.graphOf[ref(index)]]; }

      function bytes(b64) {
        if (!b64) return new Uint8Array(0);
        var s = atob(b64), n = s.length, out = new Uint8Array(n);
        for (var i = 0; i < n; i++) out[i] = s.charCodeAt(i);
        return out;
      }
      function floats(b64) { var b = bytes(b64); return new Float32Array(b.buffer, 0, b.length >> 2); }
      function shorts(b64) { var b = bytes(b64); return new Uint16Array(b.buffer, 0, b.length >> 1); }
      function ints(b64) { var b = bytes(b64); return new Uint32Array(b.buffer, 0, b.length >> 2); }
      var stream = shorts(STREAM);
      var rangeData = floats(RANGES);
      var varying = ints(VARYING);
      var base = floats(BASE);
      var vertexBase = shorts(VBASE);
      var vertexPositions = floats(VPOS);
      var fitData = floats(FIT);
      var extra = floats(EXTRA);
      var sceneFloats = floats(SCENE);
      var axisData = floats(AXES);

      var gl = canvas.getContext('webgl2', { alpha: false, antialias: false, depth: false, stencil: false,
                                             premultipliedAlpha: false, preserveDrawingBuffer: true });
      if (!gl) { canvas.setAttribute('title', 'This picture needs WebGL2.'); return; }
      canvas.width = W; canvas.height = H;

      function shader(type, source) {
        var s = gl.createShader(type);
        gl.shaderSource(s, source);
        gl.compileShader(s);
        if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error('Ollin page shader: ' + gl.getShaderInfoLog(s));
        return s;
      }
      function program(vs, fs) {
        var p = gl.createProgram();
        gl.attachShader(p, shader(gl.VERTEX_SHADER, vs));
        gl.attachShader(p, shader(gl.FRAGMENT_SHADER, fs));
        gl.linkProgram(p);
        if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error('Ollin page program: ' + gl.getProgramInfoLog(p));
        return p;
      }
      var sdf = program(SDF_VS, SDF_FS);
      var present = program(PRESENT_VS, PRESENT_FS);
      var uViewport = gl.getUniformLocation(sdf, 'viewport');
      var uFlip = gl.getUniformLocation(sdf, 'ollin_flip');
      var pSrc = gl.getUniformLocation(present, 'src');
      var pViewport = gl.getUniformLocation(present, 'viewport');
      var pExposure = gl.getUniformLocation(present, 'exposure');
      var pToneMap = gl.getUniformLocation(present, 'toneMapMode');
      var image = null, iViewport, iTex, iFlip, iFlipV;
      function imageProgram() {
        if (image) return image;
        image = program(IMAGE_VS, IMAGE_FS);
        iViewport = gl.getUniformLocation(image, 'viewport');
        iTex = gl.getUniformLocation(image, 'tex');
        iFlip = gl.getUniformLocation(image, 'ollin_flip');
        iFlipV = gl.getUniformLocation(image, 'vflip');
        return image;
      }
      // Atlas text: the image quad's vertex stage under the glyph fragment.
      var glyph = null, gViewport, gAtlas, gFlip;
      function glyphProgram() {
        if (glyph) return glyph;
        glyph = program(IMAGE_VS, GLYPH_FS);
        gViewport = gl.getUniformLocation(glyph, 'viewport');
        gAtlas = gl.getUniformLocation(glyph, 'atlas');
        gFlip = gl.getUniformLocation(glyph, 'ollin_flip');
        return glyph;
      }
      // The triangle path's two programs, built when a frame first draws a fill
      // or a stroke.
      var solid = null, fringe = null;
      function triangleProgram(isFringe) {
        if (isFringe) {
          if (!fringe) { var pf = program(TRI_VS, FRINGE_FS); fringe = { p: pf, viewport: gl.getUniformLocation(pf, 'viewport'), flip: gl.getUniformLocation(pf, 'ollin_flip') }; }
          return fringe;
        }
        if (!solid) { var ps = program(TRI_VS, TRI_FS); solid = { p: ps, viewport: gl.getUniformLocation(ps, 'viewport'), flip: gl.getUniformLocation(ps, 'ollin_flip') }; }
        return solid;
      }
      // The node programs of the frame's fields, one field at a time, in a
      // uniform block (four rows a node, 256 nodes at most, the recorder's own cap).
      var nodeUBO = null;
      function nodeBuffer() {
        if (nodeUBO) return nodeUBO;
        nodeUBO = gl.createBuffer();
        gl.bindBuffer(gl.UNIFORM_BUFFER, nodeUBO);
        gl.bufferData(gl.UNIFORM_BUFFER, 16384, gl.DYNAMIC_DRAW);
        gl.bindBufferBase(gl.UNIFORM_BUFFER, 0, nodeUBO);
        return nodeUBO;
      }
      function uploadNodes(view) {
        gl.bindBuffer(gl.UNIFORM_BUFFER, nodeBuffer());
        gl.bufferSubData(gl.UNIFORM_BUFFER, 0, view);
      }
      function bindNodes(p) {
        var bi = gl.getUniformBlockIndex(p, 'Nodes');
        if (bi !== 4294967295) gl.uniformBlockBinding(p, bi, 0);
      }
      // A composed 2D field: the covering quad under the VM fragment.
      var groupP = null;
      function groupProgram() {
        if (groupP) return groupP;
        var p = program(GROUP_VS, GROUP_FS);
        bindNodes(p);
        function u(n) { return gl.getUniformLocation(p, n); }
        groupP = { p: p, viewport: u('viewport'), flip: u('ollin_flip'), group: u('group'), gradients: u('gradients') };
        return groupP;
      }
      // A raymarched 3D field: the fullscreen march, and the upsample of a
      // reduced-resolution one.
      var fieldP = null, upP = null;
      function fieldProgram() {
        if (fieldP) return fieldP;
        var p = program(FIELD_VS, FIELD_FS);
        bindNodes(p);
        function u(n) { return gl.getUniformLocation(p, n); }
        fieldP = { p: p, flip: u('ollin_flip'), field: u('field'), view: u('uView'), proj: u('uProj'), invVP: u('uInvVP'),
                   viewportSteps: u('uViewportSteps'), scale: u('uScale'), ambient: u('uAmbient'), eye: u('uEye'),
                   counts: u('uCounts'), lights: u('uLights'), casters: u('uCasters'), material: u('uMaterial'),
                   gradients: u('gradients'), brdf: u('brdfLUT') };
        return fieldP;
      }
      function upsampleProgram() {
        if (upP) return upP;
        var p = program(FIELD_VS, UPSAMPLE_FS);
        function u(n) { return gl.getUniformLocation(p, n); }
        upP = { p: p, color: u('halfColor'), depth: u('halfDepth'), region: u('region'), flip: u('ollin_flip') };
        return upP;
      }
      // One program per framework fragment and per user shader, built on first use.
      var fxPrograms = {};
      function fxProgram(name) {
        var entry = fxPrograms[name];
        if (entry) return entry;
        var source = FX[name];
        if (!source) throw new Error('Ollin page: no fragment ' + name);
        var p = program(FX_VS, source);
        entry = { p: p, viewport: gl.getUniformLocation(p, 'ollin_viewport'),
                  params: gl.getUniformLocation(p, 'params'), textures: [] };
        var count = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
        // The samplers, in the order the fragment bound them: the translation
        // names them and the recorder binds inputs in that same order.
        for (var i = 0; i < count; i++) {
          var info = gl.getActiveUniform(p, i);
          if (info.type === gl.SAMPLER_2D) entry.textures.push({ name: info.name, loc: gl.getUniformLocation(p, info.name) });
        }
        fxPrograms[name] = entry;
        return entry;
      }
      var blur = null, bSrc, bStep, bSigma;
      function blurProgram() {
        if (blur) return blur;
        blur = program(FX_VS, BLUR_FS);
        bSrc = gl.getUniformLocation(blur, 'src');
        bStep = gl.getUniformLocation(blur, 'step');
        bSigma = gl.getUniformLocation(blur, 'sigma');
        return blur;
      }
      // A separable Gaussian over `sigma`, one pass each way through a spare surface.
      function runBlur(input, sigma, out) {
        var p = blurProgram();
        var mid = acquire(out.w, out.h);
        var passes = [[input, mid, 1 / out.w, 0], [mid.tex, out, 0, 1 / out.h]];
        for (var i = 0; i < 2; i++) {
          gl.bindFramebuffer(gl.FRAMEBUFFER, passes[i][1].fbo);
          gl.viewport(0, 0, out.w, out.h);
          gl.disable(gl.BLEND);
          gl.useProgram(p);
          gl.activeTexture(gl.TEXTURE0);
          gl.bindTexture(gl.TEXTURE_2D, passes[i][0]);
          gl.uniform1i(bSrc, 0);
          gl.uniform2f(bStep, passes[i][2], passes[i][3]);
          gl.uniform1f(bSigma, sigma);
          gl.drawArrays(gl.TRIANGLES, 0, 3);
        }
      }
      // The two passes the page owns: the blur, and the bloom as bright pass,
      // blur, and add-back.
      function runOwned(name, input, rows, out) {
        if (name === 'ollin_web_blur') { runBlur(input, rows[0], out); return; }
        var bright = acquire(out.w, out.h), blurred = acquire(out.w, out.h);
        runFragment('ollin_fx_brightpass', [input], [rows[1], 0, 0, 0], bright);
        runBlur(bright.tex, rows[0], blurred);
        runFragment('ollin_fx_bloom_combine', [input, blurred.tex], [rows[2], 0, 0, 0], out);
      }
      var userPrograms = [];
      function userProgram(index) {
        var entry = userPrograms[index];
        if (entry) return entry;
        var p = program(FX_VS, USERS[index]);
        function u(n) { return gl.getUniformLocation(p, n); }
        entry = { p: p, viewport: u('ollin_viewport'), src0: u('ollin_src0'), src1: u('ollin_src1'),
                  resolution: u('ollin_resolution'), mouse: u('ollin_mouse'), time: u('ollin_time'),
                  dt: u('ollin_dt'), frame: u('ollin_frame'), paramCount: u('ollin_paramCount'),
                  params: u('ollin_params') };
        userPrograms[index] = entry;
        return entry;
      }

      // Textures: the canvas intermediate, a pool of per-frame layers by size,
      // and the persistent pairs a feedback layer or a simulation keeps.
      var floatOK = !!(gl.getExtension('EXT_color_buffer_float') || gl.getExtension('EXT_color_buffer_half_float'));
      gl.getExtension('OES_texture_float_linear');
      var format = floatOK ? gl.RGBA16F : gl.RGBA8;
      function makeSurface(w, h) {
        var tex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.texStorage2D(gl.TEXTURE_2D, 1, format, w, h);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        var fbo = gl.createFramebuffer();
        gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
        var ok = gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE;
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        return { tex: tex, fbo: fbo, w: w, h: h, ok: ok };
      }
      var main = makeSurface(W, H);
      if (!main.ok) { format = gl.RGBA8; main = makeSurface(W, H); }
      // A drawn surface's multisampled buffer, four samples like the Mac's
      // canvas, made once per surface and resolved into its texture after each
      // fill. A surface that persists (the canvas, a feedback pair) keeps its
      // samples, so an accumulating canvas loads them as the Mac's does. The
      // items are rasterized into it upright in the GPU's own texture space
      // (the page otherwise keeps its pictures bottom-up), because the sample
      // pattern is fixed in that space and a mirrored picture meets it
      // mirrored: a diagonal edge then differs from the Mac's by a sample or
      // two, where an upright one matches to a level. The resolve turns the
      // picture back over on its way into the surface's texture.
      var MSAA = !!D.msaa;
      var samples = MSAA ? Math.min(4, gl.getParameter(gl.MAX_SAMPLES)) : 0;
      if (samples < 2) MSAA = false;
      function multisampled(s) {
        if (s.ms !== undefined) return s.ms;
        var rb = gl.createRenderbuffer();
        gl.bindRenderbuffer(gl.RENDERBUFFER, rb);
        gl.renderbufferStorageMultisample(gl.RENDERBUFFER, samples, format, s.w, s.h);
        var fbo = gl.createFramebuffer();
        gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
        gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, rb);
        var ok = gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE;
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        s.ms = ok ? { rb: rb, fbo: fbo } : null;
        return s.ms;
      }
      // The resolve lands in a plain surface of the same size first (a
      // multisampled read allows no flip), then flips into the texture.
      var upright = {};
      function resolve(s) {
        var key = s.w + 'x' + s.h;
        var mid = upright[key] || (upright[key] = makeSurface(s.w, s.h));
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, s.ms.fbo);
        gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, mid.fbo);
        gl.blitFramebuffer(0, 0, s.w, s.h, 0, 0, s.w, s.h, gl.COLOR_BUFFER_BIT, gl.NEAREST);
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, mid.fbo);
        gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, s.fbo);
        gl.blitFramebuffer(0, 0, s.w, s.h, 0, s.h, s.w, 0, gl.COLOR_BUFFER_BIT, gl.NEAREST);
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      }
      // A depth buffer on a surface that marches 3D fields, so the fields
      // occlude one another through it as the Mac's do; one on the
      // multisampled buffer when the surface has one.
      function ensureDepth(s) {
        if (s.depthRB) return;
        var rb = gl.createRenderbuffer();
        gl.bindRenderbuffer(gl.RENDERBUFFER, rb);
        gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, s.w, s.h);
        gl.bindFramebuffer(gl.FRAMEBUFFER, s.fbo);
        gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, rb);
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        s.depthRB = rb;
      }
      function ensureDepthMS(ms, s) {
        if (!ms || ms.depthRB) return;
        var rb = gl.createRenderbuffer();
        gl.bindRenderbuffer(gl.RENDERBUFFER, rb);
        gl.renderbufferStorageMultisample(gl.RENDERBUFFER, samples, gl.DEPTH_COMPONENT24, s.w, s.h);
        gl.bindFramebuffer(gl.FRAMEBUFFER, ms.fbo);
        gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, rb);
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        ms.depthRB = rb;
      }
      // The reduced-resolution march's target, by size: a surface with a depth
      // texture the upsample reads back.
      var halfSurfaces = {};
      function halfSurface(w, h) {
        var key = w + 'x' + h;
        if (halfSurfaces[key]) return halfSurfaces[key];
        var s = makeSurface(w, h);
        var dt = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, dt);
        gl.texStorage2D(gl.TEXTURE_2D, 1, gl.DEPTH_COMPONENT24, w, h);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.bindFramebuffer(gl.FRAMEBUFFER, s.fbo);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, dt, 0);
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        s.depthTex = dt;
        halfSurfaces[key] = s;
        return s;
      }
      var pool = [], used = [];
      function acquire(w, h) {
        for (var i = 0; i < pool.length; i++) {
          if (pool[i].w === w && pool[i].h === h) { var s = pool.splice(i, 1)[0]; used.push(s); return s; }
        }
        var made = makeSurface(w, h);
        used.push(made);
        return made;
      }
      function releaseAll() { while (used.length) pool.push(used.pop()); }
      var persistent = {};
      function slot(key, w, h, rest, seedFill) {
        var s = persistent[key];
        if (s && s.w === w && s.h === h) return s;
        s = { a: makeSurface(w, h), b: makeSurface(w, h), w: w, h: h, flipped: false, age: 0 };
        var fills = [s.a, s.b];
        for (var i = 0; i < 2; i++) {
          if (seedFill && seedFill.length) {
            runFragment('ollin_sim_state_seed', [], [1 / w, 1 / h, 0, 0, seedFill[0], seedFill[1], 0, 0], fills[i]);
          } else {
            gl.bindFramebuffer(gl.FRAMEBUFFER, fills[i].fbo);
            gl.clearColor(rest[0], rest[1], rest[2], rest[3]);
            gl.clear(gl.COLOR_BUFFER_BIT);
          }
        }
        persistent[key] = s;
        return s;
      }
      function clearSurface(s, c) {
        gl.bindFramebuffer(gl.FRAMEBUFFER, s.fbo);
        gl.viewport(0, 0, s.w, s.h);
        gl.clearColor(c[0], c[1], c[2], c.length > 3 ? c[3] : 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);
      }
      var blank = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, blank);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 0]));
      function clampLinear(tex) {
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      }
      // The gradient strip: one row per ramp the shapes read, sRGB texels the
      // sampler decodes to linear, as the Mac's strip is.
      var strip = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, strip);
      if (STRIP[0] > 0) gl.texImage2D(gl.TEXTURE_2D, 0, gl.SRGB8_ALPHA8, STRIP[1], STRIP[0], 0, gl.RGBA, gl.UNSIGNED_BYTE, bytes(STRIP[2]));
      else gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 0]));
      clampLinear(strip);
      var uGradients = gl.getUniformLocation(sdf, 'gradients');
      // The split-sum table a physically-based field prices its energy against,
      // half floats as the Mac stores them.
      var brdf = null;
      if (BRDF[0] > 0) {
        brdf = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, brdf);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RG16F, BRDF[0], BRDF[0], 0, gl.RG, gl.HALF_FLOAT, shorts(BRDF[1]));
        clampLinear(brdf);
      }
      // The pictures and the atlas pages, decoded by the browser (which is
      // asynchronous, so the first frame waits on `ready`). Each is loaded
      // through an image element from a data URL: a picture in flight that way
      // holds the document's load event, which is what a headless dump waits
      // for (a bitmap decode holds nothing, and the dump beat it one time in
      // three), and the upload flags apply to an image element where a bitmap
      // ignores them. A picture is read raw (no color conversion, no
      // orientation) and premultiplied on upload into an sRGB texture with its
      // smaller levels, the way the Mac holds it; an atlas page lands at the
      // top of a page-sized texture, since the glyph quads address the whole
      // page.
      function decode(b64, mime) {
        return new Promise(function (resolve, reject) {
          var img = new Image();
          img.style.imageOrientation = 'none';
          img.onload = function () { resolve(img); };
          img.onerror = function () { reject(new Error('Ollin page: a picture did not decode')); };
          img.src = 'data:' + mime + ';base64,' + b64;
        });
      }
      var pictures = [], atlases = [], pending = [];
      PICTURES.forEach(function (p, i) {
        var tex = gl.createTexture();
        pictures[i] = tex;
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 0]));
        clampLinear(tex);
        pending.push(decode(p[1], p[0]).then(function (img) {
          gl.bindTexture(gl.TEXTURE_2D, tex);
          gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, gl.NONE);
          gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
          gl.texImage2D(gl.TEXTURE_2D, 0, gl.SRGB8_ALPHA8, gl.RGBA, gl.UNSIGNED_BYTE, img);
          gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
          gl.generateMipmap(gl.TEXTURE_2D);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        }));
      });
      ATLASES.forEach(function (a, i) {
        var tex = gl.createTexture();
        atlases[i] = tex;
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, a[1], a[1]);
        clampLinear(tex);
        pending.push(decode(a[0], 'image/png').then(function (img) {
          gl.bindTexture(gl.TEXTURE_2D, tex);
          gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, gl.NONE);
          gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, gl.RGBA, gl.UNSIGNED_BYTE, img);
        }));
      });
      // The stroke and fill expander, when the track carries strokes or fills
      // as their points: the framework's own expander compiled to
      // WebAssembly, instantiated once; a source item hands it the records and
      // draws what comes back. It asks the system for nothing but a random
      // seed, which it never reads. The module is small, so it is compiled
      // synchronously and the first frame never waits on it (a pending
      // compile holds nothing, so a page dumped at its load event could show
      // its strokes missing); a browser that refuses a synchronous compile
      // gets the asynchronous one, and the first frame waits.
      var expander = null;
      if (EXPANDER && typeof WebAssembly !== 'undefined') {
        var wasi = { random_get: function () { return 0; } };
        var wasiProxy = typeof Proxy === 'function'
          ? new Proxy(wasi, { get: function (t, p) { return t[p] || function () { return 0; }; } }) : wasi;
        var imports = { wasi_snapshot_preview1: wasiProxy };
        var adopt = function (instance) {
          var x = instance.exports;
          if (x._initialize) x._initialize();
          expander = { memory: x.memory, input: x.ollin_input, expand: x.ollin_expand, output: x.ollin_output };
        };
        var module = bytes(EXPANDER).buffer;
        try {
          adopt(new WebAssembly.Instance(new WebAssembly.Module(module), imports));
        } catch (e) {
          pending.push(WebAssembly.instantiate(module, imports).then(function (r) { adopt(r.instance); }));
        }
      }
      // The lookup strips, uploaded once.
      var tables = TABLES.map(function (t) {
        var tex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, t[0], 1, 0, gl.RGBA, gl.FLOAT, floats(t[1]));
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        return tex;
      });

      // One instance record per shape, the same 30 floats the recorder wrote.
      var vao = gl.createVertexArray();
      var vbo = gl.createBuffer();
      gl.bindVertexArray(vao);
      gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
      var layout = [[2, 0], [2, 8], [2, 16], [4, 24], [4, 40], [4, 56], [4, 72], [4, 88], [2, 104], [2, 112]];
      for (var a = 0; a < layout.length; a++) {
        gl.enableVertexAttribArray(a);
        gl.vertexAttribPointer(a, layout[a][0], gl.FLOAT, false, F * 4, layout[a][1]);
        gl.vertexAttribDivisor(a, 1);
      }
      gl.bindVertexArray(null);
      // Six vertices per image quad: position, uv, tint.
      var qvao = gl.createVertexArray();
      var qvbo = gl.createBuffer();
      gl.bindVertexArray(qvao);
      gl.bindBuffer(gl.ARRAY_BUFFER, qvbo);
      var qlayout = [[2, 0], [2, 8], [4, 16]];
      for (var b = 0; b < qlayout.length; b++) {
        gl.enableVertexAttribArray(b);
        gl.vertexAttribPointer(b, qlayout[b][0], gl.FLOAT, false, 32, qlayout[b][1]);
      }
      gl.bindVertexArray(null);
      // One triangle vertex: position, coverage, color, the seven floats the
      // recorder wrote.
      var tvao = gl.createVertexArray();
      var tvbo = gl.createBuffer();
      gl.bindVertexArray(tvao);
      gl.bindBuffer(gl.ARRAY_BUFFER, tvbo);
      var tlayout = [[2, 0], [1, 8], [4, 12]];
      for (var t = 0; t < tlayout.length; t++) {
        gl.enableVertexAttribArray(t);
        gl.vertexAttribPointer(t, tlayout[t][0], gl.FLOAT, false, V * 4, tlayout[t][1]);
      }
      gl.bindVertexArray(null);
      // A vertex's position travels exact; its coverage and color sit inside
      // their field's range as 16-bit positions.
      var P = 2, VS = V - P;
      var vlows = [], vscales = [];
      var vranges = D.vranges || [];
      for (var vr = 0; vr < vranges.length; vr += 2) { vlows.push(vranges[vr]); vscales.push((vranges[vr + 1] - vranges[vr]) / 65535); }

      // Sampled values sit inside their column's range as 16-bit positions.
      var lows = [], scales = [];
      for (var r = 0; r < rangeData.length; r += 2) { lows.push(rangeData[r]); scales.push((rangeData[r + 1] - rangeData[r]) / 65535); }
      // A fitted column: its mean, then a frequency, a cosine, and a sine per term.
      var fits = D.fit || [], fitOffsets = [], fitOffset = 0;
      for (var f = 0; f < fits.length; f++) { fitOffsets.push(fitOffset); fitOffset += 1 + 3 * fits[f][1]; }
      // A live column: a parameter's formula, evaluated here on the clock and the pointer.
      var formulas = D.formulas || [], evaluators = [];
      for (var e = 0; e < formulas.length; e++) evaluators.push(new Function('v', 'Fx', 'return ' + formulas[e].js + ';'));
      var drives = D.drive || [];
      var formulaValues = new Float64Array(formulas.length);
      var mouse = { x: D.mouse[0], y: D.mouse[1] };
      canvas.addEventListener('pointermove', function (ev) {
        var rect = canvas.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
          mouse.x = (ev.clientX - rect.left) * W / rect.width;
          mouse.y = (ev.clientY - rect.top) * H / rect.height;
        }
      });

      // The controls: each part of a parameter the probe could wire is an axis
      // whose columns move by slope × (value − base) at every frame, the slope
      // one number, the sines of a lap, or a sample per frame; a color reaches
      // the clear through its linear-light value. A formula reads a control's
      // value under the parameter's name.
      var controls = D.controls || [], axes = D.axes || [];
      var values = new Float64Array(axes.length);
      for (var ai = 0; ai < axes.length; ai++) values[ai] = axes[ai].base;
      var axisRegions = [false, false, false];
      for (var ar = 0; ar < axes.length; ar++) for (var ac = 0; ac < axes[ar].cols.length; ac++) axisRegions[axes[ar].cols[ac][0]] = true;
      function lin(c) { c = Math.min(Math.max(c, 0), 1); return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
      function slopeAt(col, kf, index, fraction) {
        var mode = col[3], off = col[4], n = col[5];
        if (mode === 0) return axisData[off];
        if (mode === 1) {
          var w = 2 * Math.PI * kf / D.frames, s = axisData[off];
          for (var q = 0; q < n; q++) { var m = axisData[off + 1 + q * 3]; s += axisData[off + 2 + q * 3] * Math.cos(w * m) + axisData[off + 3 + q * 3] * Math.sin(w * m); }
          return s;
        }
        var s0 = axisData[off + index];
        if (fraction > 0 && D.stable) { var s1 = axisData[off + (index + 1) % D.frames]; return s0 + (s1 - s0) * fraction; }
        return s0;
      }
      function applyAxes(region, target, count, kf, index, fraction) {
        if (!axisRegions[region]) return;
        for (var a = 0; a < axes.length; a++) {
          var ax = axes[a], v = values[a];
          if (v === ax.base) continue;
          var d0 = v - ax.base, d1 = lin(v) - lin(ax.base);
          for (var c = 0; c < ax.cols.length; c++) {
            var col = ax.cols[c];
            if (col[0] !== region || col[1] >= count) continue;
            target[col[1]] += slopeAt(col, kf, index, fraction) * (col[2] === 1 ? d1 : d0);
          }
        }
      }
      var factScratch = new Float32Array(4);
      function clearAt(index, fraction) {
        var c = clearOf(index);
        if (!axisRegions[2] || !c || !c.length) return c;
        factScratch[0] = c[0]; factScratch[1] = c[1]; factScratch[2] = c[2]; factScratch[3] = 0;
        applyAxes(2, factScratch, 3, index + fraction, index, fraction);
        return [Math.max(0, factScratch[0]), Math.max(0, factScratch[1]), Math.max(0, factScratch[2])];
      }
      function exposureAt(index, fraction) {
        var e = exposureOf(index);
        if (!axisRegions[2]) return e;
        factScratch[0] = 0; factScratch[1] = 0; factScratch[2] = 0; factScratch[3] = e;
        applyAxes(2, factScratch, 4, index + fraction, index, fraction);
        return factScratch[3];
      }

      // The sketch's clock at fractional frame `kf`, and the automation's
      // position on it.
      function sketchTime(kf) { return (kf + D.frameOffset) / D.rate; }
      function clockPosition(kf) {
        var t = sketchTime(kf);
        var position = t, c = D.clock;
        if (c) {
          position = c.start + t * c.speed;
          if (c.loops && c.duration > 0) { position = position % c.duration; if (position < 0) position += c.duration; }
        }
        return position;
      }
      // Every formula at fractional frame `kf`, in the order the Mac evaluates
      // them: a formula reads the clock, the canvas, the pointer, the constants,
      // and the driven values already worked out this frame.
      function evaluateFormulas(kf) {
        var v = Object.assign({}, D.constants);
        for (var a = 0; a < axes.length; a++) v[axes[a].name] = values[a];
        v.time = clockPosition(kf);
        v.frame = Math.floor(kf) + D.frameOffset + 1;
        v.width = W;
        v.height = H;
        v.mouseX = mouse.x;
        v.mouseY = mouse.y;
        for (var i = 0; i < formulas.length; i++) {
          var x = Fx.param(evaluators[i](v, Fx), formulas[i]);
          v[formulas[i].name] = x;
          formulaValues[i] = x;
        }
      }

      var maxLength = D.stable ? base.length + vertexBase.length + vertexPositions.length : (D.lengths.length ? Math.max.apply(null, D.lengths) : 0);
      var scratch = new Float32Array(Math.max(1, maxLength));
      // Where each region of a graph's vector starts.
      function groupOffset(g) { return g.instances * F + g.quads * Q; }
      function nodeOffset(g) { return groupOffset(g) + (g.groups || 0) * G; }
      function fieldOffset(g) { return nodeOffset(g) + (g.nodes || 0) * NF; }
      function node3DOffset(g) { return fieldOffset(g) + (g.fields || 0) * FF; }
      function sourceOffset(g) { return node3DOffset(g) + (g.nodes3d || 0) * N3; }
      function vertexOffset(g) { return sourceOffset(g) + (g.sources || 0); }
      function paramOffset(g) { return vertexOffset(g) + g.vertices * V; }
      // The scene block of frame `index`, moved `fraction` of the way to the
      // next (the camera and the lights slide between records), or null.
      var sceneScratch = null;
      function sceneAt(index, fraction) {
        var s = sceneBase(index, fraction);
        if (!s || !axisRegions[1]) return s;
        var moved = new Float32Array(s.length);
        moved.set(s);
        applyAxes(1, moved, moved.length, index + fraction, index, fraction);
        return moved;
      }
      function sceneBase(index, fraction) {
        if (!D.sceneOffsets) return null;
        var u = ref(index), len = D.sceneLengths[u];
        if (!len) return null;
        var a = sceneFloats.subarray(D.sceneOffsets[u], D.sceneOffsets[u] + len);
        if (fraction > 0 && D.stable) {
          var u2 = ref((index + 1) % D.frames);
          if (u2 !== u && D.sceneLengths[u2] === len) {
            var b = sceneFloats.subarray(D.sceneOffsets[u2], D.sceneOffsets[u2] + len);
            if (!sceneScratch || sceneScratch.length < len) sceneScratch = new Float32Array(len);
            for (var i = 0; i < len; i++) sceneScratch[i] = a[i] + (b[i] - a[i]) * fraction;
            return sceneScratch.subarray(0, len);
          }
        }
        return a;
      }

      // The frame's whole vector at frame `index`, moved `fraction` of the way
      // to the next: the shapes, the quads, the vertices, and the parameter rows.
      function assemble(index, fraction) {
        var u = ref(index);
        if (D.stable) {
          var vo = vertexOffset(D.graph), po = paramOffset(D.graph);
          scratch.set(base.subarray(0, vo), 0);
          if (base.length > vo) scratch.set(base.subarray(vo), po);
          for (var vx = 0; vx < D.graph.vertices; vx++) {
            var at = vo + vx * V;
            scratch[at] = vertexPositions[vx * P];
            scratch[at + 1] = vertexPositions[vx * P + 1];
            for (var vf = 0; vf < VS; vf++) scratch[at + P + vf] = vlows[vf] + vertexBase[vx * VS + vf] * vscales[vf];
          }
          var u2 = ref((index + 1) % D.frames);
          var v = varying, n = v.length, off = u * n, off2 = u2 * n;
          for (var i = 0; i < n; i++) {
            var a = lows[i] + stream[off + i] * scales[i];
            if (fraction > 0 && u2 !== u) { var b = lows[i] + stream[off2 + i] * scales[i]; a += (b - a) * fraction; }
            scratch[v[i]] = a;
          }
          var kf = index + fraction;
          var w = 2 * Math.PI * kf / D.frames;
          for (var j = 0; j < fits.length; j++) {
            var p = fitOffsets[j], terms = fits[j][1], value = fitData[p];
            for (var q = 0; q < terms; q++) {
              var m = fitData[p + 1 + q * 3];
              value += fitData[p + 2 + q * 3] * Math.cos(w * m) + fitData[p + 3 + q * 3] * Math.sin(w * m);
            }
            scratch[fits[j][0]] = value;
          }
          if (drives.length) {
            evaluateFormulas(kf);
            for (var d = 0; d < drives.length; d++) { var dr = drives[d]; scratch[dr[0]] = dr[2] * formulaValues[dr[1]] + dr[3]; }
          }
          applyAxes(0, scratch, po + D.graph.params, kf, index, fraction);
          return;
        }
        // Every frame its own record: the shapes, quads, and vertices as 16-bit
        // samples by field, the parameter rows as floats.
        var g = graphOf(index);
        var si = D.offsets[u], pi = D.positionOffsets[u], so2 = sourceOffset(g), vo2 = vertexOffset(g), count = paramOffset(g);
        var go = groupOffset(g), no = nodeOffset(g), fo = fieldOffset(g), n3o = node3DOffset(g);
        for (var k = 0; k < count; k++) {
          // A stroke or a fill as its points, and a vertex's position, travel exact.
          if ((k >= so2 && k < vo2) || (k >= vo2 && (k - vo2) % V < P)) { scratch[k] = vertexPositions[pi++]; continue; }
          var c;
          if (k < go) c = k < g.instances * F ? (k % F) : F + (k - g.instances * F) % Q;
          else if (k < no) c = F + Q + (k - go) % G;
          else if (k < fo) c = F + Q + G + (k - no) % NF;
          else if (k < n3o) c = F + Q + G + NF + (k - fo) % FF;
          else if (k < so2) c = F + Q + G + NF + FF + (k - n3o) % N3;
          else c = F + Q + G + NF + FF + N3 + (k - vo2) % V;
          scratch[k] = lows[c] + stream[si++] * scales[c];
        }
        var pstart = D.paramOffsets[u];
        for (var e2 = 0; e2 < g.params; e2++) scratch[count + e2] = extra[pstart + e2];
        applyAxes(0, scratch, count + g.params, index + fraction, index, fraction);
      }

      // The blend factors under each mode, as the Mac's pipelines set them: a
      // straight-alpha fragment (a shape, a fill, a stroke) scales by its own
      // alpha, a premultiplied one (an image) by one.
      function setBlend(mode, straight) {
        gl.enable(gl.BLEND);
        var src = straight ? gl.SRC_ALPHA : gl.ONE;
        switch (mode) {
          case 1: gl.blendEquation(gl.FUNC_ADD); gl.blendFuncSeparate(src, gl.ONE, gl.ONE, gl.ONE); break;
          case 2: gl.blendEquationSeparate(gl.FUNC_REVERSE_SUBTRACT, gl.FUNC_ADD); gl.blendFuncSeparate(src, gl.ONE, gl.ONE, gl.ONE); break;
          case 3: gl.blendEquation(gl.FUNC_ADD); gl.blendFuncSeparate(gl.DST_COLOR, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA); break;
          case 4: gl.blendEquation(gl.FUNC_ADD); gl.blendFuncSeparate(gl.ONE_MINUS_DST_COLOR, gl.ONE, gl.ONE, gl.ONE_MINUS_SRC_ALPHA); break;
          case 5: gl.blendEquation(gl.MAX); gl.blendFuncSeparate(src, gl.ONE, gl.ONE, gl.ONE); break;
          case 6: gl.blendEquation(gl.MIN); gl.blendFuncSeparate(src, gl.ONE, gl.ONE, gl.ONE); break;
          default: gl.blendEquation(gl.FUNC_ADD); gl.blendFuncSeparate(src, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
        }
      }
      // The shapes at instance `start`, `count` of them, drawn into the bound
      // surface at logical size `w` by `h`.
      function drawShapes(start, count, blend, w, h, flip) {
        gl.useProgram(sdf);
        gl.uniform2f(uViewport, w, h);
        gl.uniform1f(uFlip, flip);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, strip);
        gl.uniform1i(uGradients, 0);
        setBlend(blend, true);
        gl.bindVertexArray(vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.bufferData(gl.ARRAY_BUFFER, scratch.subarray(start * F, (start + count) * F), gl.DYNAMIC_DRAW);
        gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, count);
        gl.bindVertexArray(null);
      }
      // The triangle vertices at `start`, `count` of them, a fill's or, with
      // `isFringe`, a stroke's, drawn into the bound surface.
      function drawTriangles(start, count, isFringe, blend, w, h, vo, flip) {
        var e = triangleProgram(isFringe);
        gl.useProgram(e.p);
        gl.uniform2f(e.viewport, w, h);
        gl.uniform1f(e.flip, flip);
        setBlend(blend, true);
        gl.bindVertexArray(tvao);
        gl.bindBuffer(gl.ARRAY_BUFFER, tvbo);
        gl.bufferData(gl.ARRAY_BUFFER, scratch.subarray(vo + start * V, vo + (start + count) * V), gl.DYNAMIC_DRAW);
        gl.drawArrays(gl.TRIANGLES, 0, count);
        gl.bindVertexArray(null);
      }
      // The strokes (`isFringe`) or fills an item carries as their points: the
      // records at `item[1]` of the source region, `item[2]` floats of them,
      // expanded by the expander into the vertices the Mac drew and kept per
      // item until the records move, so a still expands once and a moving
      // drawing once a frame. Nothing draws until the expander has loaded.
      var sourceCache = new Map(), drawTick = 0;
      function drawSources(item, isFringe, blend, w, h, so, flip) {
        if (!expander) return;
        var start = item[1], floats = item[2];
        var src = scratch.subarray(so + start, so + start + floats);
        var entry = sourceCache.get(item);
        if (entry) entry.tick = drawTick;
        var same = !!entry && entry.floats.length === floats;
        if (same) { for (var i = 0; i < floats; i++) { if (entry.floats[i] !== src[i]) { same = false; break; } } }
        if (!same) {
          if (!entry) {
            entry = { floats: new Float32Array(floats), buffer: gl.createBuffer(), vao: gl.createVertexArray(), count: 0, tick: drawTick };
            gl.bindVertexArray(entry.vao);
            gl.bindBuffer(gl.ARRAY_BUFFER, entry.buffer);
            for (var t = 0; t < tlayout.length; t++) {
              gl.enableVertexAttribArray(t);
              gl.vertexAttribPointer(t, tlayout[t][0], gl.FLOAT, false, V * 4, tlayout[t][1]);
            }
            gl.bindVertexArray(null);
            sourceCache.set(item, entry);
          }
          if (entry.floats.length !== floats) entry.floats = new Float32Array(floats);
          entry.floats.set(src);
          var ptr = expander.input(floats);
          new Float32Array(expander.memory.buffer, ptr, floats).set(src);
          var count = expander.expand(floats);
          if (count < 0) { entry.count = 0; return; }
          var out = new Float32Array(expander.memory.buffer, expander.output(), count * V);
          gl.bindBuffer(gl.ARRAY_BUFFER, entry.buffer);
          gl.bufferData(gl.ARRAY_BUFFER, out, gl.DYNAMIC_DRAW);
          entry.count = count;
        }
        if (!entry.count) return;
        var e = triangleProgram(isFringe);
        gl.useProgram(e.p);
        gl.uniform2f(e.viewport, w, h);
        gl.uniform1f(e.flip, flip);
        setBlend(blend, true);
        gl.bindVertexArray(entry.vao);
        gl.drawArrays(gl.TRIANGLES, 0, entry.count);
        gl.bindVertexArray(null);
      }
      // An item's vertices stay for as long as the item is drawn: a stable
      // cast's items recur every frame and keep theirs, a changing cast's are
      // let go once the frame has moved past them, so a long recording holds
      // one frame's expansion at a time rather than every frame's.
      function sweepSources() {
        sourceCache.forEach(function (entry, item) {
          if (entry.tick === drawTick) return;
          gl.deleteBuffer(entry.buffer);
          gl.deleteVertexArray(entry.vao);
          sourceCache.delete(item);
        });
        drawTick++;
      }
      // `count` textured quads from quad `quad`: a layer's (its rows turned
      // over, premultiplied), a picture's (as uploaded, premultiplied), or the
      // glyphs of atlas text (the glyph fragment, straight alpha).
      function drawQuads(quad, count, tex, blend, kind, w, h, quadOffset, flip) {
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, tex);
        if (kind === 'glyph') {
          gl.useProgram(glyphProgram());
          gl.uniform2f(gViewport, w, h);
          gl.uniform1f(gFlip, flip);
          gl.uniform1i(gAtlas, 0);
          setBlend(blend, true);
        } else {
          gl.useProgram(imageProgram());
          gl.uniform2f(iViewport, w, h);
          gl.uniform1f(iFlip, flip);
          gl.uniform1f(iFlipV, kind === 'layer' ? 1 : 0);
          gl.uniform1i(iTex, 0);
          setBlend(blend, false);
        }
        gl.bindVertexArray(qvao);
        gl.bindBuffer(gl.ARRAY_BUFFER, qvbo);
        var at = quadOffset + quad * Q;
        gl.bufferData(gl.ARRAY_BUFFER, scratch.subarray(at, at + count * Q), gl.DYNAMIC_DRAW);
        gl.drawArrays(gl.TRIANGLES, 0, count * 6);
        gl.bindVertexArray(null);
      }
      // The composed fields at group `start`, `count` of them, each its own draw:
      // the group's rows as uniforms, its program in the node block.
      var groupRows = new Float32Array(28);
      function drawGroups(start, count, blend, w, h, flip, g) {
        var e = groupProgram();
        gl.useProgram(e.p);
        gl.uniform2f(e.viewport, w, h);
        gl.uniform1f(e.flip, flip);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, strip);
        gl.uniform1i(e.gradients, 0);
        setBlend(blend, true);
        gl.bindVertexArray(null);
        var go = groupOffset(g), no = nodeOffset(g);
        for (var j = 0; j < count; j++) {
          var at = go + (start + j) * G;
          groupRows.set(scratch.subarray(at, at + G));
          gl.uniform4fv(e.group, groupRows);
          var ns = Math.round(scratch[at + 20]), nc = Math.round(scratch[at + 21]);
          uploadNodes(scratch.subarray(no + ns * NF, no + (ns + nc) * NF));
          gl.drawArrays(gl.TRIANGLES, 0, 6);
        }
      }
      // The scene block as the field program's uniforms: the camera, the march
      // budget with the scale this pass traces at, the lights, the casters.
      var lightRows = new Float32Array(160), casterRows = new Float32Array(16);
      function setScene(e, sc, scale) {
        gl.uniformMatrix4fv(e.view, false, sc.subarray(0, 16));
        gl.uniformMatrix4fv(e.proj, false, sc.subarray(16, 32));
        gl.uniformMatrix4fv(e.invVP, false, sc.subarray(32, 48));
        gl.uniform4fv(e.viewportSteps, sc.subarray(48, 52));
        gl.uniform4f(e.scale, scale, sc[53], sc[54], sc[55]);
        gl.uniform4fv(e.ambient, sc.subarray(56, 60));
        gl.uniform4fv(e.eye, sc.subarray(60, 64));
        gl.uniform4fv(e.counts, sc.subarray(64, 68));
        var n = Math.min(8, Math.round(sc[64])), nc = Math.min(4, Math.round(sc[65]));
        lightRows.fill(0); casterRows.fill(0);
        lightRows.set(sc.subarray(68, 68 + n * 20));
        casterRows.set(sc.subarray(68 + n * 20, 68 + n * 20 + nc * 4));
        gl.uniform4fv(e.lights, lightRows);
        gl.uniform4fv(e.casters, casterRows);
      }
      // The fields of one item, marched into the bound target under the depth
      // test, the finish's rows as uniforms, each field's program in the node block.
      function drawFields(item, w, h, flip, g, sc, scale) {
        var e = fieldProgram();
        gl.useProgram(e.p);
        setScene(e, sc, scale);
        gl.uniform1f(e.flip, flip);
        var po = paramOffset(g) + item[4];
        gl.uniform4fv(e.material, scratch.subarray(po, po + 36));
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, strip);
        gl.uniform1i(e.gradients, 0);
        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, brdf || blank);
        gl.uniform1i(e.brdf, 1);
        setBlend(item[3] || 0, true);
        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LEQUAL);
        gl.depthMask(true);
        gl.bindVertexArray(null);
        var fo = fieldOffset(g), n3o = node3DOffset(g);
        for (var j = 0; j < item[2]; j++) {
          var at = fo + (item[1] + j) * FF;
          gl.uniform4fv(e.field, scratch.subarray(at, at + FF));
          var ns = Math.round(scratch[at + 28]), nc = Math.round(scratch[at + 29]);
          uploadNodes(scratch.subarray(n3o + ns * N3, n3o + (ns + nc) * N3));
          gl.drawArrays(gl.TRIANGLES, 0, 3);
        }
        gl.disable(gl.DEPTH_TEST);
      }
      // A reduced-resolution march: every field of the surface into a smaller
      // target at the scene's scale (the Mac's coverage-adaptive fraction),
      // then upsampled onto the target once, its depth re-emitted.
      function drawFieldsReduced(items, target, w, h, flip, g, sc) {
        var scale = sc[52], hw = Math.max(1, Math.round(sc[53])), hh = Math.max(1, Math.round(sc[54]));
        var half = halfSurface(hw, hh);
        gl.bindFramebuffer(gl.FRAMEBUFFER, half.fbo);
        gl.viewport(0, 0, hw, hh);
        gl.clearColor(0, 0, 0, 0);
        gl.depthMask(true);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        for (var i = 0; i < items.length; i++) {
          if (items[i][0] === 'f') drawFields(items[i], w, h, 1, g, sc, scale);
        }
        gl.bindFramebuffer(gl.FRAMEBUFFER, target.fbo);
        gl.viewport(0, 0, target.w, target.h);
        var e = upsampleProgram();
        gl.useProgram(e.p);
        gl.uniform1f(e.flip, flip);
        gl.uniform4f(e.region, 1, 1, (hw - 0.5) / hw, (hh - 0.5) / hh);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, half.tex);
        gl.uniform1i(e.color, 0);
        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, half.depthTex);
        gl.uniform1i(e.depth, 1);
        setBlend(0, false);
        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LEQUAL);
        gl.depthMask(true);
        gl.bindVertexArray(null);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
        gl.disable(gl.DEPTH_TEST);
      }
      // The items of one surface, in call order, into `surface` (its logical
      // size is the layer's, its raster the surface's). `results` holds each
      // layer's texture this frame; `previous` the fronts of the feedback layers;
      // `sc` the frame's scene block when the surface marches 3D fields.
      function drawItems(items, surface, w, h, clear, results, previous, g, sc) {
        var ms = MSAA ? multisampled(surface) : null;
        var target = ms ? { fbo: ms.fbo, w: surface.w, h: surface.h } : surface;
        if (sc) { ensureDepth(surface); ensureDepthMS(ms, surface); }
        gl.bindFramebuffer(gl.FRAMEBUFFER, target.fbo);
        gl.viewport(0, 0, surface.w, surface.h);
        if (clear && clear.length) { gl.clearColor(clear[0], clear[1], clear[2], clear.length > 3 ? clear[3] : 1.0); gl.clear(gl.COLOR_BUFFER_BIT); }
        if (sc) { gl.depthMask(true); gl.clear(gl.DEPTH_BUFFER_BIT); }
        var vo = vertexOffset(g), so = sourceOffset(g), flip = ms ? -1 : 1, reduced = false;
        for (var i = 0; i < items.length; i++) {
          var item = items[i];
          if (item[0] === 's') { drawShapes(item[1], item[2], item[3] || 0, w, h, flip); continue; }
          if (item[0] === 't') { drawTriangles(item[1], item[2], item[3] === 1, item[4] || 0, w, h, vo, flip); continue; }
          if (item[0] === 'x') { drawSources(item, item[4] === 1, item[5] || 0, w, h, so, flip); continue; }
          if (item[0] === 'g') { drawGroups(item[1], item[2], item[3] || 0, w, h, flip, g); continue; }
          if (item[0] === 'f') {
            if (!sc) continue;
            if (sc[52] < 1.0) {
              if (reduced) continue;
              reduced = true;
              drawFieldsReduced(items, target, w, h, flip, g, sc);
            } else {
              drawFields(item, w, h, flip, g, sc, 1.0);
            }
            continue;
          }
          var count = item[4] || 1, qo = g.instances * F;
          if (item[0] === 'a') { drawQuads(item[2], count, atlases[item[1]] || blank, item[3] || 0, 'glyph', w, h, qo, flip); continue; }
          if (item[0] === 'm') { drawQuads(item[2], count, pictures[item[1]] || blank, item[3] || 0, 'picture', w, h, qo, flip); continue; }
          var tex = item[0] === 'p' ? (previous[item[1]] || blank) : (results[item[1]] || blank);
          drawQuads(item[2], count, tex, item[3] || 0, 'layer', w, h, qo, flip);
        }
        gl.disable(gl.BLEND);
        if (ms) resolve(surface);
      }
      // One fullscreen pass of a framework fragment into `out`: the inputs bound
      // in order, the rows at `params`.
      function runFragment(name, inputs, rows, out) {
        var e = fxProgram(name);
        gl.bindFramebuffer(gl.FRAMEBUFFER, out.fbo);
        gl.viewport(0, 0, out.w, out.h);
        gl.disable(gl.BLEND);
        gl.useProgram(e.p);
        gl.uniform2f(e.viewport, out.w, out.h);
        for (var i = 0; i < e.textures.length; i++) {
          gl.activeTexture(gl.TEXTURE0 + i);
          gl.bindTexture(gl.TEXTURE_2D, inputs[i] || blank);
          gl.uniform1i(e.textures[i].loc, i);
        }
        if (e.params) gl.uniform4fv(e.params, rows);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
      }
      function rowsOf(node, g) {
        var start = paramOffset(g) + node.p;
        return scratch.subarray(start, start + node.r * 4);
      }
      function resolveInputs(list, results) {
        var out = [];
        for (var i = 0; i < list.length; i++) out.push(list[i][0] === 't' ? tables[list[i][1]] : (results[list[i][1]] || blank));
        return out;
      }
      function runUser(layer, out, results, kf, g) {
        var e = userProgram(layer.shader);
        gl.bindFramebuffer(gl.FRAMEBUFFER, out.fbo);
        gl.viewport(0, 0, out.w, out.h);
        gl.disable(gl.BLEND);
        gl.useProgram(e.p);
        gl.uniform2f(e.viewport, out.w, out.h);
        for (var i = 0; i < layer.inputs.length; i++) {
          gl.activeTexture(gl.TEXTURE0 + i);
          gl.bindTexture(gl.TEXTURE_2D, results[layer.inputs[i]] || blank);
          gl.uniform1i(i === 0 ? e.src0 : e.src1, i);
        }
        gl.uniform2f(e.resolution, out.w, out.h);
        gl.uniform2f(e.mouse, mouse.x, mouse.y);
        gl.uniform1f(e.time, sketchTime(kf));
        gl.uniform1f(e.dt, 1 / D.rate);
        gl.uniform1ui(e.frame, Math.floor(kf) + D.frameOffset + 1);
        gl.uniform1ui(e.paramCount, layer.count || 0);
        var rows = new Float32Array(64);
        var start = paramOffset(g) + layer.p;
        for (var r = 0; r < layer.r * 4; r++) rows[r] = scratch[start + r];
        gl.uniform4fv(e.params, rows);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
      }
      // A simulation field: the seed marks drawn, laid onto the front state by
      // the inject, the step run its substeps, the last one into the back.
      function runSim(layer, results, previous, g, index) {
        var s = slot(layer.k, layer.pw, layer.ph, layer.sim.rest, layer.sim.seed);
        var front = s.flipped ? s.b : s.a, back = s.flipped ? s.a : s.b;
        var seed = acquire(layer.pw, layer.ph);
        drawItems(layer.items, seed, layer.w, layer.h, layer.clear, results, previous, g);
        var texel = [1 / layer.pw, 1 / layer.ph, 0, 0];
        var own = rowsOf({ p: layer.sim.p, r: layer.sim.r }, g);
        var rows = new Float32Array(4 + own.length);
        rows.set(texel, 0); rows.set(own, 4);
        var s0 = acquire(layer.pw, layer.ph), s1 = acquire(layer.pw, layer.ph);
        runFragment(layer.sim.inject, [front.tex, seed.tex], rows, s0);
        var step = layer.sim.step, extraTex = [];
        if (layer.sim.modStep !== undefined) { step = layer.sim.modStep; extraTex = [results[layer.sim.mod] || blank]; }
        var read = s0, n = layer.sim.n;
        for (var i = 0; i < n; i++) {
          var write = (i === n - 1) ? back : (read === s0 ? s1 : s0);
          rows[2] = i; rows[3] = s.age;
          runFragment(step, [read.tex].concat(extraTex), rows, write);
          read = write;
        }
        s.age += 1;
        s.flipped = !s.flipped;
        return back.tex;
      }

      function draw(index, fraction) {
        assemble(index, fraction);
        var g = graphOf(index);
        var kf = index + fraction;
        var results = [], previous = [];
        releaseAll();
        for (var li = 0; li < g.layers.length; li++) {
          var layer = g.layers[li];
          var out;
          switch (layer.t) {
            case 'g':
              out = acquire(layer.pw, layer.ph);
              drawItems(layer.items, out, layer.w, layer.h, layer.clear, results, previous, g);
              results[li] = out.tex;
              break;
            case 'gen':
              out = acquire(layer.pw, layer.ph);
              runFragment(layer.pass.f, resolveInputs(layer.pass.in, results), rowsOf(layer.pass, g), out);
              results[li] = out.tex;
              break;
            case 'fx':
            case 'cx': {
              out = acquire(layer.pw, layer.ph);
              if (layer.pass.f.indexOf('ollin_web_') === 0) {
                runOwned(layer.pass.f, results[layer.input] || blank, rowsOf(layer.pass, g), out);
                results[li] = out.tex;
                break;
              }
              var ins = layer.t === 'fx' ? [results[layer.input]] : [results[layer.base], results[layer.aux]];
              var bound = [];
              for (var k = 0; k < layer.pass.in.length; k++) {
                var inp = layer.pass.in[k];
                bound.push(inp[0] === 't' ? tables[inp[1]] : (ins[inp[1]] || blank));
              }
              runFragment(layer.pass.f, bound, rowsOf(layer.pass, g), out);
              results[li] = out.tex;
              break;
            }
            case 'u':
              out = acquire(layer.pw, layer.ph);
              runUser(layer, out, results, kf, g);
              results[li] = out.tex;
              break;
            case 'fb': {
              var s = slot(layer.k, layer.pw, layer.ph, [0, 0, 0, 0], null);
              var front = s.flipped ? s.b : s.a, back = s.flipped ? s.a : s.b;
              previous[li] = front.tex;
              drawItems(layer.items, back, layer.w, layer.h, layer.clear, results, previous, g);
              results[li] = back.tex;
              s.flipped = !s.flipped;
              break;
            }
            case 'sim':
              results[li] = runSim(layer, results, previous, g, index);
              break;
          }
        }
        // The canvas (with the frame's scene when it marches fields), then the
        // whole-frame filters through a spare pair.
        var clear = clearAt(index, fraction);
        drawItems(g.canvas, main, W, H, clear.length ? clear : null, results, previous, g, g.fields ? sceneAt(index, fraction) : null);
        var shown = main;
        for (var pi = 0; pi < g.post.length; pi++) {
          var target = acquire(W, H);
          if (g.post[pi].f.indexOf('ollin_web_') === 0) runOwned(g.post[pi].f, shown.tex, rowsOf(g.post[pi], g), target);
          else runFragment(g.post[pi].f, [shown.tex].concat(resolveInputs(g.post[pi].in.slice(1), results)), rowsOf(g.post[pi], g), target);
          shown = target;
        }
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
        gl.disable(gl.BLEND);
        gl.useProgram(present);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, shown.tex);
        gl.uniform1i(pSrc, 0);
        gl.uniform2f(pViewport, W, H);
        gl.uniform1f(pExposure, exposureAt(index, fraction));
        gl.uniform1i(pToneMap, toneOf(index));
        gl.drawArrays(gl.TRIANGLES, 0, 3);
        if (sourceCache.size) sweepSources();
      }

      var player = { canvas: canvas, frames: D.frames, rate: D.rate, duration: D.frames / D.rate,
                     loops: D.loops, playing: false, time: 0, autoplay: true };
      var shown = -1;
      var sequential = D.accumulates || D.stateful;

      // Show frame `index`, moved `fraction` toward the next. An accumulating
      // or stateful track draws every frame between the last shown and this
      // one, in order, since each one builds on the last.
      function showAt(index, fraction) {
        if (sequential) {
          if (shown < 0 || index < shown) {
            persistent = {};
            for (var k = 0; k <= index; k++) draw(k, 0);
          } else {
            var k2 = shown; while (k2 !== index) { k2 = (k2 + 1) % D.frames; draw(k2, 0); }
          }
          shown = index;
          return;
        }
        draw(index, fraction);
        shown = index;
      }
      // Show the picture at `t` seconds of the track.
      function show(t) {
        player.time = t;
        var pos = Math.max(0, t) * D.rate;
        var i = Math.floor(pos), f = pos - i;
        if (f > 0.999999) { i += 1; f = 0; } else if (f < 0.000001) { f = 0; }
        i = i % D.frames;
        if (!D.loops && i === D.frames - 1) f = 0;
        if (!D.stable) f = 0;
        showAt(i, f);
      }

      var last = null, raf = 0;
      function tick(now) {
        if (!player.playing) return;
        if (last === null) last = now;
        var dt = Math.min(0.25, (now - last) / 1000);
        last = now;
        show(player.time + dt);
        raf = requestAnimationFrame(tick);
      }
      player.play = function () {
        if (player.playing || (D.frames < 2 && !drives.length)) return;
        player.playing = true;
        last = null;
        raf = requestAnimationFrame(tick);
      };
      player.pause = function () {
        player.playing = false;
        player.autoplay = false;
        if (raf) cancelAnimationFrame(raf);
        raf = 0;
        last = null;
      };
      player.seek = function (t) { show(t); };
      player.showFrame = function (i) {
        var n = D.frames, index = ((i % n) + n) % n;
        player.time = index / D.rate;
        showAt(index, 0);
      };
      var resume = false;
      document.addEventListener('visibilitychange', function () {
        if (document.hidden) { if (player.playing) { player.pause(); resume = true; } }
        else if (resume) { resume = false; player.play(); }
      });

      // Setting a parameter from the page: `set(name, value)` takes a number,
      // a boolean, a color as '#rrggbb', '#rrggbbaa', {red, green, blue, alpha}
      // or [r, g, b, a] in 0…1, a point as {x, y} or [x, y], a pair of ends as
      // {lower, upper} or [lower, upper], or one part by name ('ink.red', 0.5).
      // A value outside the parameter's range lands on its edge, as on the Mac.
      var started = false, inputs = {};
      function controlNamed(name) { for (var i = 0; i < controls.length; i++) if (controls[i].name === name) return controls[i]; return null; }
      function partOf(c, part) { for (var i = 0; i < c.parts.length; i++) if (c.parts[i].name === part) return c.parts[i]; return null; }
      function partValue(c, p) { return p && p.axis >= 0 ? values[p.axis] : (p ? p.value : undefined); }
      function setPart(c, p, x) {
        if (!p || p.axis < 0) return;
        x = Number(x);
        if (x !== x) return;
        if (p.lo !== undefined) x = Math.min(Math.max(x, p.lo), p.hi);
        if (c.kind === 'integer' || c.kind === 'toggle') x = Math.round(x);
        else if (p.step > 0 && p.lo !== undefined) x = Math.min(p.hi, p.lo + Math.round((x - p.lo) / p.step) * p.step);
        if (c.kind === 'range') {
          // A pair of ends stays ordered, as on the Mac.
          if (p.name === 'lower') x = Math.min(x, partValue(c, partOf(c, 'upper')));
          else x = Math.max(x, partValue(c, partOf(c, 'lower')));
        }
        values[p.axis] = x;
      }
      function hex2(x) { var h = Math.round(Math.min(Math.max(x, 0), 1) * 255).toString(16); return h.length < 2 ? '0' + h : h; }
      function colorOf(c) {
        var r = partValue(c, partOf(c, 'red')), g = partValue(c, partOf(c, 'green')), b = partValue(c, partOf(c, 'blue')), a = partValue(c, partOf(c, 'alpha'));
        return { red: r, green: g, blue: b, alpha: a, hex: '#' + hex2(r) + hex2(g) + hex2(b) };
      }
      function parseColor(v) {
        if (typeof v === 'string') {
          var s = v.replace('#', '');
          if (s.length === 3 || s.length === 4) s = s.split('').map(function (ch) { return ch + ch; }).join('');
          if (s.length !== 6 && s.length !== 8) return null;
          var out = { red: parseInt(s.slice(0, 2), 16) / 255, green: parseInt(s.slice(2, 4), 16) / 255, blue: parseInt(s.slice(4, 6), 16) / 255 };
          if (s.length === 8) out.alpha = parseInt(s.slice(6, 8), 16) / 255;
          return out;
        }
        if (Array.isArray(v)) return { red: v[0], green: v[1], blue: v[2], alpha: v[3] };
        return v || null;
      }
      function redraw() {
        if (!started) return;
        if (sequential) shown = -1;
        if (!player.playing) show(player.time);
      }
      function syncPanel() { for (var key in inputs) inputs[key].sync(); }
      player.params = controls.map(function (c) {
        return { name: c.name, label: c.label, group: c.group || null, kind: c.kind,
                 parts: c.parts.filter(function (p) { return p.axis >= 0; }).map(function (p) { return { name: p.name, min: p.lo, max: p.hi, step: p.step }; }) };
      });
      player.get = function (name) {
        var dot = name.indexOf('.');
        if (dot > 0) { var c0 = controlNamed(name.slice(0, dot)); return c0 ? partValue(c0, partOf(c0, name.slice(dot + 1))) : undefined; }
        var c = controlNamed(name);
        if (!c) return undefined;
        switch (c.kind) {
          case 'number': case 'integer': return partValue(c, c.parts[0]);
          case 'toggle': return partValue(c, c.parts[0]) !== 0;
          case 'color': { var k = colorOf(c); return { red: k.red, green: k.green, blue: k.blue, alpha: k.alpha }; }
          default: { var o = {}; for (var i = 0; i < c.parts.length; i++) o[c.parts[i].name] = partValue(c, c.parts[i]); return o; }
        }
      };
      player.set = function (name, value) {
        var dot = name.indexOf('.');
        if (dot > 0) { var c0 = controlNamed(name.slice(0, dot)); if (c0) { setPart(c0, partOf(c0, name.slice(dot + 1)), value); syncPanel(); redraw(); } return; }
        var c = controlNamed(name);
        if (!c) return;
        switch (c.kind) {
          case 'number': case 'integer': setPart(c, c.parts[0], value); break;
          case 'toggle': setPart(c, c.parts[0], value ? 1 : 0); break;
          case 'color': {
            var k = parseColor(value);
            if (!k) return;
            for (var i = 0; i < c.parts.length; i++) if (k[c.parts[i].name] !== undefined) setPart(c, c.parts[i], k[c.parts[i].name]);
            break;
          }
          default: {
            var o = value || {};
            if (Array.isArray(value)) { o = {}; for (var j = 0; j < c.parts.length; j++) o[c.parts[j].name] = value[j]; }
            for (var i2 = 0; i2 < c.parts.length; i2++) if (o[c.parts[i2].name] !== undefined) setPart(c, c.parts[i2], o[c.parts[i2].name]);
          }
        }
        syncPanel();
        redraw();
      };
      player.reset = function () { for (var a = 0; a < axes.length; a++) values[a] = axes[a].base; syncPanel(); redraw(); };

      // The panel under the canvas, in the standalone page: a row per
      // parameter, grouped as the sketch grouped them, as wide as the canvas.
      var panel = null;
      function fmt(x, p) {
        var span = p.hi - p.lo;
        var d = p.step > 0 ? Math.max(0, Math.ceil(-Math.log10(p.step) - 1e-9)) : (span >= 100 ? 0 : (span >= 10 ? 1 : 2));
        return Number(x).toFixed(d);
      }
      function fitPanel() {
        document.documentElement.style.setProperty('--ollin-panel', (panel.offsetHeight + 28) + 'px');
        var rect = canvas.getBoundingClientRect();
        if (rect.width > 0) panel.style.width = rect.width + 'px';
      }
      function addInputs(c, row) {
        var kind = c.kind;
        function attach(p, input, out) {
          function sync() {
            var v = values[p.axis];
            if (kind === 'toggle') input.checked = v !== 0;
            else if (input.type === 'number') input.value = kind === 'integer' ? String(Math.round(v)) : fmt(v, p);
            else input.value = v;
            if (out) out.value = fmt(v, p);
          }
          input.addEventListener('input', function () {
            setPart(c, p, kind === 'toggle' ? (input.checked ? 1 : 0) : input.value);
            syncPanel();
            redraw();
          });
          inputs[c.name + '.' + p.name] = { sync: sync };
          sync();
        }
        if (kind === 'color') {
          var well = document.createElement('input');
          well.type = 'color';
          well.addEventListener('input', function () {
            var k = parseColor(well.value);
            for (var j = 0; j < c.parts.length; j++) if (k[c.parts[j].name] !== undefined) setPart(c, c.parts[j], k[c.parts[j].name]);
            syncPanel();
            redraw();
          });
          inputs[c.name + '.well'] = { sync: function () { well.value = colorOf(c).hex; } };
          well.value = colorOf(c).hex;
          row.appendChild(well);
        }
        for (var i = 0; i < c.parts.length; i++) {
          var p = c.parts[i];
          if (p.axis < 0) continue;
          if (kind === 'color' && p.name !== 'alpha') continue;
          var input = document.createElement('input'), out = null;
          if (kind === 'toggle') {
            input.type = 'checkbox';
          } else if (kind === 'number' || kind === 'color') {
            input.type = 'range';
            input.min = p.lo; input.max = p.hi; input.step = p.step > 0 ? p.step : 'any';
            out = document.createElement('output');
            if (kind === 'color') { var tag = document.createElement('span'); tag.className = 'part'; tag.textContent = 'alpha'; row.appendChild(tag); }
          } else {
            input.type = 'number';
            if (p.lo !== undefined) { input.min = p.lo; input.max = p.hi; }
            input.step = p.step > 0 ? p.step : (kind === 'integer' ? 1 : 'any');
            if (p.name) { var tag2 = document.createElement('span'); tag2.className = 'part'; tag2.textContent = p.name; row.appendChild(tag2); }
          }
          row.appendChild(input);
          if (out) row.appendChild(out);
          attach(p, input, out);
        }
      }
      function buildPanel() {
        var style = document.createElement('style');
        style.textContent = '.ollin-controls{font:13px/1.4 -apple-system,system-ui,sans-serif;display:grid;grid-template-columns:max-content minmax(0,1fr);gap:8px 14px;align-items:center;box-sizing:border-box;padding:4px 8px;margin:0}'
          + '.ollin-controls h4{grid-column:1/-1;margin:10px 0 0;font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.06em;opacity:.55}'
          + '.ollin-controls label{text-align:right;opacity:.8;white-space:nowrap}'
          + '.ollin-controls .row{display:flex;gap:8px;align-items:center;min-width:0}'
          + '.ollin-controls input[type=range]{flex:1;min-width:80px;margin:0;accent-color:currentColor}'
          + '.ollin-controls input[type=number]{width:5.5em;font:inherit;color:inherit;background:transparent;border:1px solid currentColor;border-radius:6px;padding:2px 6px;opacity:.85}'
          + '.ollin-controls input[type=color]{width:34px;height:24px;padding:0;border:none;background:transparent}'
          + '.ollin-controls input[type=checkbox]{accent-color:currentColor}'
          + '.ollin-controls output{min-width:3.5em;text-align:right;font-variant-numeric:tabular-nums;opacity:.75}'
          + '.ollin-controls .part{font-size:11px;opacity:.55}';
        document.head.appendChild(style);
        panel = document.createElement('form');
        panel.className = 'ollin-controls';
        panel.addEventListener('submit', function (ev) { ev.preventDefault(); });
        var lastGroup = null;
        for (var i = 0; i < controls.length; i++) {
          var c = controls[i], group = c.group || null;
          if (group !== lastGroup && group) { var h = document.createElement('h4'); h.textContent = group; panel.appendChild(h); }
          lastGroup = group;
          var label = document.createElement('label');
          label.textContent = c.label;
          panel.appendChild(label);
          var row = document.createElement('div');
          row.className = 'row';
          panel.appendChild(row);
          addInputs(c, row);
        }
        canvas.insertAdjacentElement('afterend', panel);
        fitPanel();
        window.addEventListener('resize', fitPanel);
      }
      if (PANEL && controls.length) buildPanel();

      canvas.ollin = player;
      window.ollin = player;

      // The first frame, once every picture and page is decoded; a page with
      // none draws it at once. Until then the canvas shows the first frame's paper,
      // so nothing flashes black. A reader who asked the system for less motion
      // sees that frame, still; `pause()` before the start holds it too.
      var still = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      function start() {
        started = true;
        show(0);
        if (!still && player.autoplay) player.play();
      }
      if (pending.length) {
        var paper = clearOf(0);
        if (paper.length) {
          var enc = function (v) { return v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055; };
          gl.bindFramebuffer(gl.FRAMEBUFFER, null);
          gl.clearColor(enc(paper[0]), enc(paper[1]), enc(paper[2]), 1);
          gl.clear(gl.COLOR_BUFFER_BIT);
        }
        player.ready = Promise.all(pending).then(start);
      } else {
        player.ready = Promise.resolve();
        start();
      }
    })();
    """#
}

// MARK: - OllinApp entry points

public extension OllinApp {
    /// Record `frames` frames of `sketch` at `fps` and return the page that plays
    /// them back in a browser, in the form asked for: `.standalone` is one
    /// self-contained HTML file, `.inline` the canvas plus one script block for
    /// a page of your own. No window, no GPU: the track is what the renderer
    /// would have received, and the page draws it with the framework's own
    /// shaders translated to GLSL, so a frame matches the Mac's.
    ///
    /// Throws a `WebExportRefusal` naming the first call the page cannot carry
    /// (a clip, a live texture drawn as an image, 3D) and the frame it was met
    /// at, or a `WebWeightRefusal` when the page would weigh more than
    /// `maxBytes` (`maxWebPageBytes` unless said otherwise; `nil` lifts the
    /// limit); nothing partial is written.
    static func web(of sketch: Sketch, frames: Int, fps: Double = 30, skipSeconds: Double = 0,
                    form: WebPageForm = .standalone, controls: Bool = true,
                    maxBytes: Int? = OllinApp.maxWebPageBytes,
                    remake: (() -> Sketch)? = nil) throws -> String {
        let recording = try recordWebFrames(of: sketch, frames: frames, fps: fps, skipSeconds: skipSeconds,
                                            controls: controls, maxBytes: maxBytes, remake: remake)
        return try webPage(of: recording, form: form, panel: controls, maxBytes: maxBytes)
    }

    /// The most a page may weigh unless an export says otherwise: 25 MB, the
    /// largest file the static hosts a page is put on will serve, and about
    /// what a phone opens in a few seconds. A page past it is refused with
    /// what made it heavy; `--max-page-size` raises or lifts the limit.
    static let maxWebPageBytes = 25 * 1024 * 1024

    /// Record `sketch` and write the page to `path`; the basis for the
    /// `--export-web` flag. A refusal is printed and the process exits nonzero,
    /// so a build step that runs the exporter sees it fail.
    static func exportWeb(_ sketch: Sketch, to path: String, frames: Int, fps: Double = 30,
                          skipSeconds: Double = 0, form: WebPageForm = .standalone,
                          controls: Bool = true, maxBytes: Int? = OllinApp.maxWebPageBytes,
                          remake: (() -> Sketch)? = nil) {
        let recording: WebRecording
        let page: String
        do {
            recording = try recordWebFrames(of: sketch, frames: frames, fps: fps, skipSeconds: skipSeconds,
                                            controls: controls, maxBytes: maxBytes, remake: remake)
            page = try webPage(of: recording, form: form, panel: controls, maxBytes: maxBytes)
        } catch let refusal as WebExportRefusal {
            fflush(stdout)
            FileHandle.standardError.write(Data("Ollin: --export-web stopped: \(refusal).\n".utf8))
            exit(1)
        } catch let refusal as WebWeightRefusal {
            fflush(stdout)
            FileHandle.standardError.write(Data("Ollin: --export-web stopped: \(refusal).\n".utf8))
            exit(1)
        } catch {
            fatalError("Ollin: --export-web failed: \(error)")
        }
        do {
            try page.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            fatalError("Ollin: failed to write \(path): \(error)")
        }
        let track = WebTrack(recording)
        let kb = Double(page.utf8.count) / 1024
        let seconds = String(format: "%.1f", recording.duration)
        let size = kb >= 1024 ? String(format: "%.1f MB", kb / 1024) : String(format: "%.0f KB", kb)
        let unique = track.uniqueFrames == recording.frames.count
            ? "" : ", \(track.uniqueFrames) distinct"
        let wraps = recording.loops ? ", a seamless loop" : ""
        var live: [String] = []
        if track.drivenColumns > 0 { live.append("\(track.drivenColumns) columns live from \(recording.formulas.count) formulas") }
        if track.fittedColumns > 0 { live.append("\(track.fittedColumns) columns fitted to \(track.fitTerms) sines") }
        if track.sampledColumns > 0 || !track.stable { live.append(track.stable ? "\(track.sampledColumns) columns sampled" : "every frame sampled") }
        let passes = track.passCount
        if passes > 0 { live.append("\(passes) shader passes a frame") }
        if track.sourceCount > 0 { live.append("\(track.sourceCount) strokes and fills as points in the fullest frame, expanded on the page") }
        if track.vertexCount > 0 { live.append("\(track.vertexCount) triangle vertices in the fullest frame") }
        if track.groupCount > 0 { live.append("\(track.groupCount) composed field\(track.groupCount == 1 ? "" : "s") a frame") }
        if track.fieldCount > 0 { live.append("\(track.fieldCount) raymarched field\(track.fieldCount == 1 ? "" : "s") a frame") }
        if !recording.controls.isEmpty {
            let names = recording.controls.map(\.name).joined(separator: ", ")
            live.append("\(recording.controls.count) parameter\(recording.controls.count == 1 ? "" : "s") live as controls (\(names); \(track.wiredColumns) columns wired)")
        }
        if !recording.leftOut.isEmpty {
            live.append("left at their recorded values: " + recording.leftOut.map { "\($0.name) (\($0.reason))" }.joined(separator: ", "))
        }
        let assetBytes = recording.pictures.reduce(0) { $0 + $1.data.count } + recording.atlases.reduce(0) { $0 + $1.png.count }
        if assetBytes > 0 {
            var assets: [String] = []
            if !recording.pictures.isEmpty { assets.append("\(recording.pictures.count) picture\(recording.pictures.count == 1 ? "" : "s")") }
            if !recording.atlases.isEmpty { assets.append("\(recording.atlases.count) atlas page\(recording.atlases.count == 1 ? "" : "s")") }
            let akb = Double(assetBytes) / 1024
            let asize = akb >= 1024 ? String(format: "%.1f MB", akb / 1024) : String(format: "%.0f KB", akb)
            live.append(assets.joined(separator: " and ") + " (\(asize) before base64)")
        }
        let how = live.isEmpty ? "" : "; " + live.joined(separator: ", ")
        print("Ollin: exported \(recording.frames.count) frames (\(seconds) s at \(formattedRate(fps)) fps\(unique)\(wraps)) → \(path) (web page, \(form.rawValue), \(size)\(how))")
    }

    private static func formattedRate(_ fps: Double) -> String {
        fps == fps.rounded() ? String(Int(fps)) : String(fps)
    }
}
