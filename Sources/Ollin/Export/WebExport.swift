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
    /// then vertices (`WebVertex.floats` each), then parameter rows, laid out
    /// as `graph` says.
    var vector: [Float]
    var graph: WebGraph
    var toneMapMode: Int
    var exposure: Float

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

/// A defect in the page's own shaders: the framework's shader text no longer
/// crosses to GLSL. Never the sketch's fault, so it is reported apart from a
/// refusal.
struct WebShaderError: Error, CustomStringConvertible {
    var diagnostics: [WebShaderDiagnostic]
    var description: String {
        "the page's shaders did not translate: " + diagnostics.map { "line \($0.line): \($0.message)" }.joined(separator: "; ")
    }
}

// MARK: - Recording

extension OllinApp {
    /// Drive `sketch` headlessly the way the video export does (`setup()`, then
    /// `draw()` advanced frame by frame at `fps`) and record what the renderer
    /// received each frame. Never touches Metal, so the page holds nothing
    /// GPU-specific. `skipSeconds` runs the sketch that long before the first
    /// recorded frame.
    static func recordWebFrames(of sketch: Sketch, frames: Int, fps: Double,
                                skipSeconds: Double = 0) throws -> WebRecording {
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }
        let size = sketch.canvasSize
        sketch.setCanvasSize(width: Double(size.width), height: Double(size.height))
        sketch.runSetup()
        guard sketch.colorOutput == .standard else {
            throw WebExportRefusal(call: "colorOutput \(sketch.colorOutput) (wide gamut and HDR output)", frame: 0)
        }
        let skip = max(0, Int((skipSeconds * fps).rounded()))
        // A parameter driven by a formula crosses as the formula (see
        // `WebFormula`); its value each frame is what a shape column is
        // matched against.
        let formulas = webFormulas(of: sketch)
        var handles: [String: ParamHandle] = [:]
        for handle in sketch.parameters() { handles[handle.name] = handle }
        var series = [[Float]](repeating: [], count: formulas.count)
        var constants: [String: Double] = [:]
        var mouse: (x: Double, y: Double) = (0, 0)
        var recorded: [WebFrame] = []
        recorded.reserveCapacity(frames)
        let recorder = WebGraphRecorder()
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
            if k == skip {
                constants = webConstants(of: sketch)
                for f in formulas { constants.removeValue(forKey: f.name) }
                mouse = (sketch.mouseX, sketch.mouseY)
            }
            for (i, f) in formulas.enumerated() {
                series[i].append(Float(webFormulaValue(named: f.name, in: handles) ?? 0))
            }
            recorded.append(try recorder.capture(sketch.drawer, frame: k - skip,
                                                 width: size.width, height: size.height))
        }
        let loops = sketch.loopDuration.map { abs($0 * fps - Double(frames)) < 0.5 } ?? false
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
        return recording
    }

    /// One frame's data, read off the drawer after `performDraw()`.
    static func captureWebFrame(_ drawer: Drawer, frame: Int, width: Int, height: Int) throws -> WebFrame {
        try WebGraphRecorder().capture(drawer, frame: frame, width: width, height: height)
    }

    /// The call, or the family of calls, a batch kind stands for in a refusal.
    nonisolated static func webRefusalName(for kind: GeometryKind) -> String {
        switch kind {
        case .sdfGroup: return "drawSDF (a combined field)"
        case .sdfGroup3D: return "a raymarched 3D field"
        case .particles: return "drawParticles"
        case .points3D: return "drawPointCloud"
        case .depthScene: return "drawDepthScene"
        case .mesh3D, .meshInstanced, .meshField, .strands, .ocean:
            return "3D drawing (a mesh, a field, strands, the ocean)"
        case .clipPush, .clipPop: return "withClip"
        // Never refused by kind: shapes, fills, strokes, pictures, atlas text,
        // and a recording of them cross (a picture that is a live texture is
        // refused where it is read).
        case .sdf, .triangles, .fringe, .retained, .image, .glyphAtlas:
            return "shapes, strokes, fills, pictures, and text"
        }
    }
}

// MARK: - The page's shaders

/// The framework's shader text the page's shaders are cut from, read once from
/// the resource bundle: the helper library, the core segment (the dither), the
/// shapes segment (the analytic primitives' coverage), and the four effect
/// segments (the tone-map curve, the filters, the combines, the simulations,
/// the patterns). A page carries only what its frames run.
enum WebShaderSources {
    static let text: String = {
        ["OllinShaderLib", "ShaderCore", "ShaderShapes", "ShaderEffects", "ShaderCombine",
         "ShaderSim", "ShaderPatterns"].compactMap { name -> String? in
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

    static func make(effects wanted: [String: Int] = [:], users: [WebUserShader] = []) throws -> WebShaders {
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
        return WebShaders(sdfVertex: sdfVertex, sdfFragment: sdfFragment,
                          presentVertex: presentVertex, presentFragment: presentFragment,
                          imageVertex: imageVertex, imageFragment: imageFragment, glyphFragment: glyphFragment,
                          triangleVertex: triangleVertex, triangleFragment: triangleFragment,
                          fringeFragment: fringeFragment,
                          effectVertex: effectVertex, effects: effects, users: userSources)
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
    static let sdfFragmentTail = """
    uniform sampler2D gradients;
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
    static func webPage(of recording: WebRecording, form: WebPageForm) throws -> String {
        let fragment = try webInlineFragment(of: recording)
        guard form == .standalone else { return fragment }
        let paper = recording.frames.first?.clear ?? SIMD3<Float>(0, 0, 0)
        let ratio = Double(recording.width) / Double(recording.height)
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
        body { display: flex; align-items: center; justify-content: center; }
        canvas.ollin-sketch { width: min(100vw, calc(100vh * \(formatted(ratio)))); height: auto; }
        </style>
        </head>
        <body>
        \(fragment)
        </body>
        </html>

        """
    }

    /// The canvas and its script: the player, the page's shaders, and the track.
    static func webInlineFragment(of recording: WebRecording) throws -> String {
        var rows: [String: Int] = [:]
        for frame in recording.frames {
            for (name, r) in frame.graph.fragmentRows { rows[name] = max(rows[name] ?? 0, r) }
        }
        let shaders = try WebShaders.make(effects: rows, users: recording.shaders)
        let track = WebTrack(recording)
        let label = recording.description.isEmpty
            ? "\(recording.name), a sketch made with Ollin"
            : recording.description
        var script = WebPlayer.script
        script = script.replacingOccurrences(of: "@META@", with: track.meta)
        script = script.replacingOccurrences(of: "@STREAM@", with: track.stream)
        script = script.replacingOccurrences(of: "@BASE@", with: track.base)
        script = script.replacingOccurrences(of: "@VBASE@", with: track.vertexBase)
        script = script.replacingOccurrences(of: "@VPOS@", with: track.vertexPositions)
        script = script.replacingOccurrences(of: "@FIT@", with: track.fit)
        script = script.replacingOccurrences(of: "@EXTRA@", with: track.extra)
        script = script.replacingOccurrences(of: "@HELPERS@", with: FormulaJS.helpers)
        script = script.replacingOccurrences(of: "@SDF_VS@", with: jsString(shaders.sdfVertex))
        script = script.replacingOccurrences(of: "@SDF_FS@", with: jsString(shaders.sdfFragment))
        script = script.replacingOccurrences(of: "@PRESENT_VS@", with: jsString(shaders.presentVertex))
        script = script.replacingOccurrences(of: "@PRESENT_FS@", with: jsString(shaders.presentFragment))
        script = script.replacingOccurrences(of: "@IMAGE_VS@", with: jsString(shaders.imageVertex))
        script = script.replacingOccurrences(of: "@IMAGE_FS@", with: jsString(shaders.imageFragment))
        script = script.replacingOccurrences(of: "@GLYPH_FS@", with: jsString(shaders.glyphFragment))
        script = script.replacingOccurrences(of: "@TRI_VS@", with: jsString(shaders.triangleVertex))
        script = script.replacingOccurrences(of: "@TRI_FS@", with: jsString(shaders.triangleFragment))
        script = script.replacingOccurrences(of: "@FRINGE_FS@", with: jsString(shaders.fringeFragment))
        script = script.replacingOccurrences(of: "@FX_VS@", with: jsString(shaders.effectVertex))
        script = script.replacingOccurrences(of: "@BLUR_FS@", with: jsString(WebShaders.blurFragment))
        let effectEntries = shaders.effects.keys.sorted().map { "\(jsString($0)): \(jsString(shaders.effects[$0]!))" }
        script = script.replacingOccurrences(of: "@FX@", with: "{" + effectEntries.joined(separator: ",\n") + "}")
        script = script.replacingOccurrences(of: "@USERS@", with: "[" + shaders.users.map(jsString).joined(separator: ",\n") + "]")
        let tables = recording.tables.map { table -> String in
            let flat = table.flatMap { [$0.x, $0.y, $0.z, $0.w] }
            return "[\(table.count), \"\(WebTrack.base64(flat))\"]"
        }
        script = script.replacingOccurrences(of: "@TABLES@", with: "[" + tables.joined(separator: ",") + "]")
        // The assets: each picture as its file's bytes or a PNG, each atlas page
        // as a gray PNG with the page size and the rows it holds, and the
        // gradient strip's rows as raw texels (a few kilobytes at most).
        let pictures = recording.pictures.map { "[\(jsString($0.mime)), \"\($0.data.base64EncodedString())\"]" }
        script = script.replacingOccurrences(of: "@PICTURES@", with: "[" + pictures.joined(separator: ",\n") + "]")
        let atlases = recording.atlases.map { "[\"\($0.png.base64EncodedString())\", \($0.size), \($0.rows)]" }
        script = script.replacingOccurrences(of: "@ATLASES@", with: "[" + atlases.joined(separator: ",\n") + "]")
        let strip = Data(recording.gradientRows.joined()).base64EncodedString()
        script = script.replacingOccurrences(of: "@STRIP@", with: "[\(recording.gradientRows.count), \(BakedGradient.width), \"\(strip)\"]")
        return """
        <canvas class="ollin-sketch" width="\(recording.width)" height="\(recording.height)" role="img" aria-label="\(htmlEscaped(label))"></canvas>
        <script>
        \(script)
        </script>
        """
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
/// canvas draws its shapes, its fills and strokes, and composites the layers
/// it names, and the whole-frame filters run last. A track that draws
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
      var FX_VS = @FX_VS@;
      var BLUR_FS = @BLUR_FS@;
      var FX = @FX@;
      var USERS = @USERS@;
      var TABLES = @TABLES@;
      var PICTURES = @PICTURES@;
      var ATLASES = @ATLASES@;
      var STRIP = @STRIP@;
      @HELPERS@
      var F = 30, Q = 48, V = 7;
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
      var stream = shorts(STREAM);
      var base = floats(BASE);
      var vertexBase = shorts(VBASE);
      var vertexPositions = floats(VPOS);
      var fitData = floats(FIT);
      var extra = floats(EXTRA);

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
      for (var r = 0; r < D.ranges.length; r += 2) { lows.push(D.ranges[r]); scales.push((D.ranges[r + 1] - D.ranges[r]) / 65535); }
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
      function vertexOffset(g) { return g.instances * F + g.quads * Q; }
      function paramOffset(g) { return vertexOffset(g) + g.vertices * V; }

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
          var v = D.varying, n = v.length, off = u * n, off2 = u2 * n;
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
          return;
        }
        // Every frame its own record: the shapes, quads, and vertices as 16-bit
        // samples by field, the parameter rows as floats.
        var g = graphOf(index);
        var si = D.offsets[u], pi = D.positionOffsets[u], vo2 = vertexOffset(g), count = paramOffset(g);
        for (var k = 0; k < count; k++) {
          if (k >= vo2 && (k - vo2) % V < P) { scratch[k] = vertexPositions[pi++]; continue; }
          var c = k < g.instances * F ? (k % F) : (k < vo2 ? F + (k - g.instances * F) % Q : F + Q + (k - vo2) % V);
          scratch[k] = lows[c] + stream[si++] * scales[c];
        }
        var pstart = D.paramOffsets[u];
        for (var e2 = 0; e2 < g.params; e2++) scratch[count + e2] = extra[pstart + e2];
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
      // The items of one surface, in call order, into `surface` (its logical
      // size is the layer's, its raster the surface's). `results` holds each
      // layer's texture this frame; `previous` the fronts of the feedback layers.
      function drawItems(items, surface, w, h, clear, results, previous, g) {
        var ms = MSAA ? multisampled(surface) : null;
        gl.bindFramebuffer(gl.FRAMEBUFFER, ms ? ms.fbo : surface.fbo);
        gl.viewport(0, 0, surface.w, surface.h);
        if (clear && clear.length) { gl.clearColor(clear[0], clear[1], clear[2], clear.length > 3 ? clear[3] : 1.0); gl.clear(gl.COLOR_BUFFER_BIT); }
        var vo = vertexOffset(g), flip = ms ? -1 : 1;
        for (var i = 0; i < items.length; i++) {
          var item = items[i];
          if (item[0] === 's') { drawShapes(item[1], item[2], item[3] || 0, w, h, flip); continue; }
          if (item[0] === 't') { drawTriangles(item[1], item[2], item[3] === 1, item[4] || 0, w, h, vo, flip); continue; }
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
        // The canvas, then the whole-frame filters through a spare pair.
        var clear = clearOf(index);
        drawItems(g.canvas, main, W, H, clear.length ? clear : null, results, previous, g);
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
        gl.uniform1f(pExposure, exposureOf(index));
        gl.uniform1i(pToneMap, toneOf(index));
        gl.drawArrays(gl.TRIANGLES, 0, 3);
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
      canvas.ollin = player;
      window.ollin = player;

      // The first frame, once every picture and page is decoded; a page with
      // none draws it at once. Until then the canvas shows the first frame's paper,
      // so nothing flashes black. A reader who asked the system for less motion
      // sees that frame, still; `pause()` before the start holds it too.
      var still = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      function start() {
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
    /// at; nothing partial is written.
    static func web(of sketch: Sketch, frames: Int, fps: Double = 30, skipSeconds: Double = 0,
                    form: WebPageForm = .standalone) throws -> String {
        let recording = try recordWebFrames(of: sketch, frames: frames, fps: fps, skipSeconds: skipSeconds)
        return try webPage(of: recording, form: form)
    }

    /// Record `sketch` and write the page to `path`; the basis for the
    /// `--export-web` flag. A refusal is printed and the process exits nonzero,
    /// so a build step that runs the exporter sees it fail.
    static func exportWeb(_ sketch: Sketch, to path: String, frames: Int, fps: Double = 30,
                          skipSeconds: Double = 0, form: WebPageForm = .standalone) {
        let recording: WebRecording
        let page: String
        do {
            recording = try recordWebFrames(of: sketch, frames: frames, fps: fps, skipSeconds: skipSeconds)
            page = try webPage(of: recording, form: form)
        } catch let refusal as WebExportRefusal {
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
        if track.vertexCount > 0 { live.append("\(track.vertexCount) triangle vertices in the fullest frame") }
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
