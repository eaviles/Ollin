import Foundation
import simd
import COllinShaders
import OllinShaderText

// MARK: - The recording

/// One recorded frame of the page: the clear the frame asked for and the
/// analytic-shape instances the renderer received, in call order. This is the
/// same data the GPU reads each frame, kept on the primitives door (the closed
/// analytic shapes: circles, ellipses, rects, arcs, triangles, polygons by
/// count, stars, rings, markers, and the novelty catalog), so the page draws
/// them with the same fragment the Mac does.
struct WebFrame: Equatable {
    /// The clear color in linear light, or `nil` when the frame drew onto what
    /// the previous frame left (an accumulating sketch).
    var clear: SIMD3<Float>?
    /// `WebInstance.floats` values per instance, in call order.
    var instances: [Float]
    var toneMapMode: Int
    var exposure: Float
}

/// What one analytic shape becomes on the wire: the `SDFInstance` fields the
/// page's vertex shader reads, as plain floats. The affine transform travels as
/// its two axis columns and its translation (the third row of a 2D CTM is
/// always 0 0 1), the shape tag as a float (it fits in fourteen bits, so the
/// value is exact), and the two gradient rows stay behind, since a gradient
/// paint does not cross yet.
enum WebInstance {
    static let floats = 28

    static func append(_ i: SDFInstance, into out: inout [Float]) {
        let t = i.transform
        out.append(contentsOf: [
            t.columns.0.x, t.columns.0.y, t.columns.1.x, t.columns.1.y, t.columns.2.x, t.columns.2.y,
            i.center.x, i.center.y, i.size.x, i.size.y,
            i.fillColor.x, i.fillColor.y, i.fillColor.z, i.fillColor.w,
            i.strokeColor.x, i.strokeColor.y, i.strokeColor.z, i.strokeColor.w,
            i.param0.x, i.param0.y, i.param1.x, i.param1.y, i.param2.x, i.param2.y,
            i.strokeWidth, i.extra, i.bandWidth, Float(i.shape),
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

    var duration: Double { Double(frames.count) / rate }
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
    /// received each frame, kept to the primitives door. Never touches Metal, so
    /// the page holds nothing GPU-specific. `skipSeconds` runs the sketch that
    /// long before the first recorded frame.
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
        var recorded: [WebFrame] = []
        recorded.reserveCapacity(frames)
        for k in 0 ..< (skip + frames) {
            sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
            sketch.performDraw()
            if k < skip {
                // The page cannot replay a pile it never saw.
                if sketch.drawer.accumulates {
                    throw WebExportRefusal(call: "--skip on a sketch that accumulates (noClear)", frame: 0)
                }
                continue
            }
            recorded.append(try captureWebFrame(sketch.drawer, frame: k - skip))
        }
        let loops = sketch.loopDuration.map { abs($0 * fps - Double(frames)) < 0.5 } ?? false
        return WebRecording(name: String(describing: type(of: sketch)),
                            width: size.width, height: size.height, rate: fps,
                            frames: recorded, loops: loops,
                            recipe: ExportMetadata.capture(from: sketch, frame: 0, fps: fps).recipe,
                            description: sketch.accessibleDescription.lines.joined(separator: " "))
    }

    /// One frame's data, read off the drawer after `performDraw()`: the batches
    /// in call order, each one either a run of analytic shapes or the reason the
    /// export stops.
    static func captureWebFrame(_ drawer: Drawer, frame: Int) throws -> WebFrame {
        func refuse(_ call: String) -> WebExportRefusal { WebExportRefusal(call: call, frame: frame) }
        if drawer.camera3D != nil || !drawer.lights.isEmpty {
            throw refuse("3D drawing (a camera or a light)")
        }
        if !drawer.dispatches.isEmpty {
            throw refuse("compute work (a simulation or GPU particles)")
        }
        if !drawer.renderTargets.isEmpty || !drawer.filterOps.isEmpty || !drawer.frameFilters.isEmpty {
            throw refuse("a layer or an effect (withTarget, a filter, postProcess, a Visual chain)")
        }

        var floats: [Float] = []
        let batches = drawer.batches
        for (i, batch) in batches.enumerated() {
            if batch.target != nil { throw refuse("a layer (withTarget)") }
            if batch.kind == .clipPush || batch.kind == .clipPop || batch.clipLevel > 0 { throw refuse("withClip") }
            if batch.blendMode != .normal { throw refuse("blendMode(.\(batch.blendMode))") }
            if batch.depth != nil { throw refuse("depth(at:)") }
            switch batch.kind {
            case .sdf:
                let end = i + 1 < batches.count ? batches[i + 1].instanceStart : drawer.sdfInstances.count
                for instance in drawer.sdfInstances[batch.instanceStart ..< end] {
                    try appendInstance(instance, into: &floats, frame: frame)
                }
            case .retained:
                // A recording made of analytic shapes alone replays as those shapes
                // under the draw-time transform, composed onto each one's own.
                guard let recording = batch.retained else { continue }
                let onlyShapes = recording.vertices.isEmpty && recording.imageVertices.isEmpty
                    && recording.glyphVertices.isEmpty && recording.points.isEmpty
                    && recording.sdfGroups.isEmpty
                    && recording.innerBatches.allSatisfy { $0.kind == .sdf && $0.blendMode == .normal && $0.depth == nil }
                guard onlyShapes else { throw refuse("drawBatch (a recording holding more than analytic shapes)") }
                for instance in recording.sdfInstances {
                    var placed = instance
                    if let t = batch.retainedTransform { placed.transform = t * instance.transform }
                    try appendInstance(placed, into: &floats, frame: frame)
                }
            default:
                throw refuse(webRefusalName(for: batch.kind))
            }
        }

        // The ordinary frame clears to the background; an accumulating one only
        // when the sketch asked for a wipe. The first frame always clears, since
        // a fresh surface starts at the background color.
        let clears = frame == 0 || !drawer.accumulates || drawer.backgroundSetThisFrame
        let bg = drawer.backgroundColor
        let clear: SIMD3<Float>? = clears
            ? SIMD3<Float>(Float(Color.srgbToLinear(bg.red)), Float(Color.srgbToLinear(bg.green)),
                           Float(Color.srgbToLinear(bg.blue)))
            : nil
        return WebFrame(clear: clear, instances: floats,
                        toneMapMode: Int(drawer.toneMapMode.shaderIndex),
                        exposure: Float(drawer.toneMapExposure))
    }

    private static func appendInstance(_ instance: SDFInstance, into floats: inout [Float], frame: Int) throws {
        let fillKind = (instance.shape >> 10) & 0x3
        let strokeKind = (instance.shape >> 12) & 0x3
        if fillKind != 0 || strokeKind != 0 {
            throw WebExportRefusal(call: "a gradient fill or stroke", frame: frame)
        }
        WebInstance.append(instance, into: &floats)
    }

    /// The call, or the family of calls, a batch kind stands for in a refusal.
    static func webRefusalName(for kind: GeometryKind) -> String {
        switch kind {
        case .triangles:
            return "a filled polygon, shape, or outline text (drawPolygon, drawShape, drawCurve, drawText, an elliptical or full-turn drawArc), which goes through the triangle path"
        case .fringe:
            return "a stroked path (drawLine, drawPolyline, drawBezier, drawCurve, a drawShape outline), which goes through the stroke path"
        case .image: return "drawImage"
        case .glyphAtlas: return "drawText (the glyph atlas)"
        case .sdfGroup: return "drawSDF (a combined field)"
        case .sdfGroup3D: return "a raymarched 3D field"
        case .particles: return "drawParticles"
        case .points3D: return "drawPointCloud"
        case .depthScene: return "drawDepthScene"
        case .mesh3D, .meshInstanced, .meshField, .strands, .ocean:
            return "3D drawing (a mesh, a field, strands, the ocean)"
        case .clipPush, .clipPop: return "withClip"
        case .sdf, .retained: return "an analytic shape"
        }
    }
}

// MARK: - The page's shaders

/// The framework's shader text the page's shaders are cut from, read once from
/// the resource bundle: the helper library, the core segment (the dither), the
/// shapes segment (the analytic primitives' coverage), and the effects segment
/// (the tone-map curve). Only the marked sections cross.
enum WebShaderSources {
    static let text: String = {
        ["OllinShaderLib", "ShaderCore", "ShaderShapes", "ShaderEffects"].compactMap { name -> String? in
            guard let url = OllinResources.bundle.url(forResource: name, withExtension: "metal") else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }.joined(separator: "\n")
    }()
}

/// The four GLSL ES 3.00 shaders a page carries. The shape coverage and the
/// present pass's dither and tone-map curve are the framework's own Metal,
/// translated; the vertex stages and the two fragment tails are the page's, and
/// they mirror `ollin_sdf_vertex` and `ollin_present_fragment` line for line.
struct WebShaders {
    var sdfVertex: String
    var sdfFragment: String
    var presentVertex: String
    var presentFragment: String

    static func make() throws -> WebShaders {
        let shapes = WebShaderLibrary.translate(WebShaderSources.text, wanted: ["shapes"])
        guard shapes.isClean else { throw WebShaderError(diagnostics: shapes.unsupported) }
        let present = WebShaderLibrary.translate(WebShaderSources.text, wanted: ["present"])
        guard present.isClean else { throw WebShaderError(diagnostics: present.unsupported) }
        let sdfFragment = WebShaderCompat.preamble + "\n" + shapes.support + "\n\n" + shapes.body + "\n" + sdfFragmentTail
        let presentFragment = WebShaderCompat.preamble + "\n" + present.support + "\n\n" + present.body + "\n" + presentFragmentTail
        return WebShaders(sdfVertex: sdfVertex, sdfFragment: sdfFragment,
                          presentVertex: presentVertex, presentFragment: presentFragment)
    }

    /// The covering quad of one instance, exactly as `ollin_sdf_vertex` builds it:
    /// the shape plus half the stroke plus a margin for the AA falloff, placed by
    /// the instance's own transform, mapped into clip space with y down.
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
    uniform vec2 viewport;
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
    flat out uint vShape;
    flat out uint vAlign;
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
        gl_Position = vec4((sketch.x / viewport.x) * 2.0 - 1.0, 1.0 - (sketch.y / viewport.y) * 2.0, 0.0, 1.0);
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
        vShape = tag & 255u;
        vAlign = align;
    }
    """

    /// The tail of `ollin_sdf_fragment`: the coverage from the translated
    /// `ollin_sdf_coverage`, the two solid paints linearized, stroke composited
    /// over fill in premultiplied linear light, returned straight so the same
    /// source-over blend applies.
    static let sdfFragmentTail = """
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
    flat in uint vShape;
    flat in uint vAlign;
    out vec4 fragColor;
    void main() {
        float fillCov = 0.0;
        float strokeCov = 0.0;
        float pathT = 0.0;
        ollin_sdf_coverage(vShape, vAlign, vLocal, vSize, vP0, vP1, vP2,
                           vStrokeWidth, vExtra, vBand, false, fillCov, strokeCov, pathT);
        vec4 fillPaint = vec4(srgbToLinear(vFill.rgb), vFill.a);
        vec4 strokePaint = vec4(srgbToLinear(vStroke.rgb), vStroke.a);
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
        let shaders = try WebShaders.make()
        let track = WebTrack(recording)
        let label = recording.description.isEmpty
            ? "\(recording.name), a sketch made with Ollin"
            : recording.description
        var script = WebPlayer.script
        script = script.replacingOccurrences(of: "@META@", with: track.meta)
        script = script.replacingOccurrences(of: "@STREAM@", with: track.stream)
        script = script.replacingOccurrences(of: "@BASE@", with: track.base)
        script = script.replacingOccurrences(of: "@SDF_VS@", with: jsString(shaders.sdfVertex))
        script = script.replacingOccurrences(of: "@SDF_FS@", with: jsString(shaders.sdfFragment))
        script = script.replacingOccurrences(of: "@PRESENT_VS@", with: jsString(shaders.presentVertex))
        script = script.replacingOccurrences(of: "@PRESENT_FS@", with: jsString(shaders.presentFragment))
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
    static func jsString(_ s: String) -> String {
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

/// The recorded frames packed for the page. Weight is the governor: a frame
/// whose shapes are the previous frame's is stored once (a still costs one
/// frame), and when every frame carries the same cast (the same count of
/// shapes with the same tags, the ordinary animation), the columns that never
/// change are stored once as the base and only the moving ones stream, which
/// is what makes interpolating between frames possible at all. Values stay
/// float32, so the page computes with the numbers the Mac had.
struct WebTrack {
    /// A JSON object: the facts the player reads.
    var meta: String
    /// Base64 float32: the moving columns per unique frame (a stable cast), or
    /// every instance of every unique frame.
    var stream: String
    /// Base64 float32: the first unique frame whole, for a stable cast; empty
    /// otherwise.
    var base: String
    var uniqueFrames: Int
    var stable: Bool

    init(_ recording: WebRecording) {
        // Consecutive duplicates fold onto one record.
        var uniques: [[Float]] = []
        var refs: [Int] = []
        for frame in recording.frames {
            if let last = uniques.last, last == frame.instances {
                refs.append(uniques.count - 1)
            } else {
                uniques.append(frame.instances)
                refs.append(uniques.count - 1)
            }
        }
        uniqueFrames = uniques.count

        let n = WebInstance.floats
        var stable = false
        if let first = uniques.first, first.count % n == 0 {
            stable = uniques.allSatisfy { u in
                guard u.count == first.count else { return false }
                var i = WebInstance.shapeColumn
                while i < u.count {
                    if u[i] != first[i] { return false }
                    i += n
                }
                return true
            }
        }
        self.stable = stable

        var values: [Float] = []
        var base: [Float] = []
        var meta: [String: Any] = [
            "width": recording.width,
            "height": recording.height,
            "rate": recording.rate,
            "frames": recording.frames.count,
            "loops": recording.loops,
            "accumulates": recording.frames.contains { $0.clear == nil },
            "refs": refs,
            "clears": recording.frames.map { f -> [Float] in f.clear.map { [$0.x, $0.y, $0.z] } ?? [] },
            "tones": recording.frames.map(\.toneMapMode),
            "exposures": recording.frames.map(\.exposure),
            "recipe": recording.recipe,
        ]
        if stable, let first = uniques.first {
            base = first
            var varying: [Int] = []
            for column in first.indices where uniques.contains(where: { $0[column] != first[column] }) {
                varying.append(column)
            }
            for u in uniques {
                for column in varying { values.append(u[column]) }
            }
            meta["stable"] = true
            meta["count"] = first.count / n
            meta["varying"] = varying
        } else {
            var offsets: [Int] = []
            var counts: [Int] = []
            for u in uniques {
                offsets.append(values.count)
                counts.append(u.count / n)
                values.append(contentsOf: u)
            }
            meta["stable"] = false
            meta["offsets"] = offsets
            meta["counts"] = counts
        }
        self.stream = Self.base64(values)
        self.base = Self.base64(base)
        let json = (try? JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        self.meta = String(decoding: json, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003C")
    }

    /// Little-endian float32 bytes, base64.
    static func base64(_ values: [Float]) -> String {
        var data = Data(capacity: values.count * 4)
        for v in values {
            var bits = v.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data.base64EncodedString()
    }
}

/// The player: a WebGL2 canvas that replays the track with the page's
/// shaders, the intermediate in linear light (half float where the browser
/// renders to one), the present pass on the canvas. Frames interpolate when
/// the cast is stable; an accumulating track draws every frame in order. A
/// reader who asked the system for less motion sees the first frame, still.
/// The handle on the canvas (`canvas.ollin`, also `window.ollin`) plays,
/// pauses, seeks, and shows one frame.
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
      var SDF_VS = @SDF_VS@;
      var SDF_FS = @SDF_FS@;
      var PRESENT_VS = @PRESENT_VS@;
      var PRESENT_FS = @PRESENT_FS@;
      var F = 28;
      var W = D.width, H = D.height;

      function floats(b64) {
        if (!b64) return new Float32Array(0);
        var s = atob(b64), n = s.length, bytes = new Uint8Array(n);
        for (var i = 0; i < n; i++) bytes[i] = s.charCodeAt(i);
        return new Float32Array(bytes.buffer, 0, n >> 2);
      }
      var stream = floats(STREAM);
      var base = floats(BASE);

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
      var pSrc = gl.getUniformLocation(present, 'src');
      var pViewport = gl.getUniformLocation(present, 'viewport');
      var pExposure = gl.getUniformLocation(present, 'exposure');
      var pToneMap = gl.getUniformLocation(present, 'toneMapMode');

      // The linear intermediate: half float where the browser can render to one.
      var floatOK = !!(gl.getExtension('EXT_color_buffer_float') || gl.getExtension('EXT_color_buffer_half_float'));
      var tex = gl.createTexture();
      var fbo = gl.createFramebuffer();
      function makeIntermediate(format) {
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.texStorage2D(gl.TEXTURE_2D, 1, format, W, H);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
        return gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE;
      }
      if (!(floatOK && makeIntermediate(gl.RGBA16F))) {
        gl.deleteTexture(tex); tex = gl.createTexture();
        makeIntermediate(gl.RGBA8);
      }
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);

      // One instance record per shape, the same 28 floats the recorder wrote.
      var vao = gl.createVertexArray();
      var vbo = gl.createBuffer();
      gl.bindVertexArray(vao);
      gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
      var layout = [[2, 0], [2, 8], [2, 16], [4, 24], [4, 40], [4, 56], [4, 72], [4, 88], [2, 104]];
      for (var a = 0; a < layout.length; a++) {
        gl.enableVertexAttribArray(a);
        gl.vertexAttribPointer(a, layout[a][0], gl.FLOAT, false, F * 4, layout[a][1]);
        gl.vertexAttribDivisor(a, 1);
      }
      gl.bindVertexArray(null);

      var varying = D.stable ? D.varying : null;
      var maxCount = D.stable ? D.count : (D.counts.length ? Math.max.apply(null, D.counts) : 0);
      var scratch = new Float32Array(Math.max(1, maxCount) * F);

      // The instances of unique frame `u`, moved a fraction `f` toward unique
      // frame `u2` when the cast is stable.
      function assemble(u, f, u2) {
        if (D.stable) {
          scratch.set(base);
          var v = varying, n = v.length, off = u * n;
          if (f > 0 && u2 !== u) {
            var off2 = u2 * n;
            for (var i = 0; i < n; i++) { var x = stream[off + i]; scratch[v[i]] = x + (stream[off2 + i] - x) * f; }
          } else {
            for (var j = 0; j < n; j++) scratch[v[j]] = stream[off + j];
          }
          return D.count;
        }
        var start = D.offsets[u], count = D.counts[u];
        scratch.set(stream.subarray(start, start + count * F));
        return count;
      }

      function draw(index, fraction) {
        var u = D.refs[index];
        var next = D.refs[(index + 1) % D.frames];
        var count = assemble(u, fraction, next);
        gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
        gl.viewport(0, 0, W, H);
        var clear = D.clears[index];
        if (clear.length) { gl.clearColor(clear[0], clear[1], clear[2], 1.0); gl.clear(gl.COLOR_BUFFER_BIT); }
        if (count > 0) {
          gl.useProgram(sdf);
          gl.uniform2f(uViewport, W, H);
          gl.enable(gl.BLEND);
          gl.blendEquation(gl.FUNC_ADD);
          gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
          gl.bindVertexArray(vao);
          gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
          gl.bufferData(gl.ARRAY_BUFFER, scratch.subarray(0, count * F), gl.DYNAMIC_DRAW);
          gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, count);
          gl.bindVertexArray(null);
        }
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
        gl.disable(gl.BLEND);
        gl.useProgram(present);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.uniform1i(pSrc, 0);
        gl.uniform2f(pViewport, W, H);
        gl.uniform1f(pExposure, D.exposures[index]);
        gl.uniform1i(pToneMap, D.tones[index]);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
      }

      var player = { canvas: canvas, frames: D.frames, rate: D.rate, duration: D.frames / D.rate,
                     loops: D.loops, playing: false, time: 0 };
      var shown = -1;

      // Show the picture at `t` seconds. An accumulating track draws every
      // frame between the last shown and this one, in order, since each one
      // builds on the last.
      function show(t) {
        player.time = t;
        var pos = Math.max(0, t) * D.rate;
        var i = Math.floor(pos) % D.frames;
        var f = pos - Math.floor(pos);
        if (!D.loops && i === D.frames - 1) f = 0;
        if (!D.stable) f = 0;
        if (D.accumulates) {
          if (shown < 0) { for (var k = 0; k <= i; k++) draw(k, 0); }
          else { var k2 = shown; while (k2 !== i) { k2 = (k2 + 1) % D.frames; draw(k2, 0); } }
          shown = i;
          return;
        }
        draw(i, f);
        shown = i;
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
        if (player.playing || D.frames < 2) return;
        player.playing = true;
        last = null;
        raf = requestAnimationFrame(tick);
      };
      player.pause = function () {
        player.playing = false;
        if (raf) cancelAnimationFrame(raf);
        raf = 0;
        last = null;
      };
      player.seek = function (t) { show(t); };
      player.showFrame = function (i) {
        var n = D.frames;
        show((((i % n) + n) % n) / D.rate);
      };
      var resume = false;
      document.addEventListener('visibilitychange', function () {
        if (document.hidden) { if (player.playing) { player.pause(); resume = true; } }
        else if (resume) { resume = false; player.play(); }
      });
      canvas.ollin = player;
      window.ollin = player;

      show(0);
      var still = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      if (!still) player.play();
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
    /// shapes shader translated to GLSL, so a frame matches the Mac's.
    ///
    /// Throws a `WebExportRefusal` naming the first call the page cannot carry
    /// (a stroked path, a filled polygon, text, an image, a layer, 3D) and the
    /// frame it was met at; nothing partial is written.
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
        print("Ollin: exported \(recording.frames.count) frames (\(seconds) s at \(formattedRate(fps)) fps\(unique)\(wraps)) → \(path) (web page, \(form.rawValue), \(size))")
    }

    private static func formattedRate(_ fps: Double) -> String {
        fps == fps.rounded() ? String(Int(fps)) : String(fps)
    }
}
