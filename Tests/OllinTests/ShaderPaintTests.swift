import Testing
import CoreGraphics
@testable import Ollin

/// A `Shader` as paint: `fill(shader)` and `stroke(shader)` run `shade` at every
/// pixel a shape covers, on the analytic (SDF), tessellated, and fringe-stroke
/// paths alike, with `uv` across the shape's own box and `info.position`,
/// `info.distance`, and `info.along` beside it; a mesh reads the same shader as
/// its surface texture. Every probe renders headless and reads the frame back.
@Suite(.enabled(if: Snapshot.hasMetal))
@MainActor
struct ShaderPaintTests {

    // MARK: Shaders

    /// One color everywhere: what `fill(Color)` draws, through the paint pipeline.
    nonisolated static let flat = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        return float4(0.95, 0.8, 0.3, 1.0);
    }
    """)
    nonisolated static let flatColor = Color(red: 0.95, green: 0.8, blue: 0.3)

    /// The shape's own uv as red and green: a corner reads its place in the box.
    nonisolated static let uvShader = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        return float4(uv.x, uv.y, 0.0, 1.0);
    }
    """)

    /// The edge distance: red deepens inward over 60 units, blue is 1 outside.
    nonisolated static let edgeShader = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        return float4(saturate(-info.distance / 60.0), 0.0, info.distance > 0.0 ? 1.0 : 0.0, 1.0);
    }
    """)

    /// A stroke's two coordinates: red runs along it, green across it over 10 units.
    nonisolated static let strokeShader = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        return float4(info.along, saturate(abs(info.distance) / 10.0), info.distance < 0.0 ? 1.0 : 0.0, 1.0);
    }
    """)

    /// The canvas position as a picture, in canvas points over the frame.
    nonisolated static let positionShader = Shader("""
    float4 shade(float2 uv, ShaderInfo info) {
        return float4(info.position.x / 256.0, info.position.y / 256.0, 0.0, 1.0);
    }
    """)

    // MARK: Forms

    /// One drawing call under a paint, on a 256-point canvas over black.
    struct Form: Sendable, CustomTestStringConvertible {
        let name: String
        /// Draws the form; the sketch's fill and stroke are already set.
        let draw: @MainActor @Sendable (Sketch) -> Void
        var testDescription: String { name }
    }

    nonisolated static let forms: [Form] = [
        Form(name: "rect (SDF)") { $0.drawRect(40, 50, 150, 110) },
        Form(name: "circle (SDF)") { $0.drawCircle(128, 128, 70) },
        Form(name: "rounded rect (SDF)") { $0.drawRect(40, 50, 150, 110, cornerRadius: 20) },
        Form(name: "star (SDF)") { $0.drawStar(128, 128, 90, 40, points: 7) },
        Form(name: "polygon (triangles + fringe)") {
            $0.drawPolygon([Vector2(40, 50), Vector2(190, 70), Vector2(170, 200), Vector2(60, 180)])
        },
        Form(name: "shape with a hole (triangles + fringe)") {
            let outer = Contour([Vector2(30, 30), Vector2(220, 40), Vector2(210, 220), Vector2(40, 200)])
            let hole = Contour([Vector2(90, 90), Vector2(160, 95), Vector2(150, 160), Vector2(100, 150)])
            $0.drawShape(Shape(contours: [outer, hole]))
        },
        Form(name: "line (fringe)") { $0.drawLine(30, 40, 220, 200) },
        Form(name: "polyline (fringe)") {
            $0.drawPolyline([Vector2(20, 200), Vector2(90, 60), Vector2(160, 190), Vector2(230, 50)])
        },
        Form(name: "bezier (fringe)") { $0.drawBezier(20, 200, 128, 10, 236, 200) },
        Form(name: "dashed circle (SDF fill + fringe outline)") {
            $0.strokeDash([18, 10]); $0.drawCircle(128, 128, 80)
        },
        Form(name: "elliptical arc (triangles + fringe)") {
            $0.drawArc(128, 128, 100, 60, start: 0.4, stop: 4.5, mode: .pie)
        },
        Form(name: "outline text (triangles)") {
            $0.textSize(120); $0.textAlign(.center, .middle); $0.drawText("Ab", 128, 128)
        },
        Form(name: "rotated rect (SDF under a transform)") {
            $0.translate(128, 128); $0.rotate(0.6); $0.drawRect(-70, -40, 140, 80)
        },
    ]

    /// The frame of `form` under `paint` (fill and stroke both, 12 wide).
    func render(_ form: Form, fill: Paint?, stroke: Paint?) throws -> Pixels {
        Pixels(try OllinApp.image(of: PaintedForm(form.draw, fill: fill, stroke: stroke), frame: 1))
    }

    @Test(arguments: forms)
    func aConstantShaderDrawsWhatAFlatColorDraws(_ form: Form) throws {
        let flat = Paint.shader(Self.flat)
        let color = Paint.color(Self.flatColor)
        let blank = try render(form, fill: nil, stroke: nil)
        // Fill alone, stroke alone, and both at once: each byte for byte.
        let shadedFill = try render(form, fill: flat, stroke: nil)
        #expect(shadedFill.bytes != blank.bytes || form.name.contains("line") || form.name.contains("bezier")
                || form.name.contains("polyline"), "the shader fill drew nothing")
        #expect(shadedFill.bytes == (try render(form, fill: color, stroke: nil)).bytes, "fill")
        let shadedStroke = try render(form, fill: nil, stroke: flat)
        #expect(shadedStroke.bytes != blank.bytes, "the shader stroke drew nothing")
        #expect(shadedStroke.bytes == (try render(form, fill: nil, stroke: color)).bytes, "stroke")
        let both = try render(form, fill: flat, stroke: flat)
        #expect(both.bytes == (try render(form, fill: color, stroke: color)).bytes, "fill and stroke")
        // A shader fill under a plain stroke, and the other way round: the two
        // paints of one shape may come from two pipelines.
        #expect((try render(form, fill: flat, stroke: color)).bytes == (try render(form, fill: color, stroke: color)).bytes,
                "shader fill under a color stroke")
        #expect((try render(form, fill: color, stroke: flat)).bytes == (try render(form, fill: color, stroke: color)).bytes,
                "color fill under a shader stroke")
    }

    @Test func uvRunsAcrossTheShapesOwnBox() throws {
        // The same rectangle on the analytic path and the tessellated one, each
        // reading its corners as (0,0), (1,0), (0,1), (1,1), with the interior
        // agreeing to a level (both interpolate the same affine map).
        let sdf = try render(Form(name: "rect") { $0.drawRect(40, 50, 150, 110) },
                             fill: .shader(Self.uvShader), stroke: nil)
        let tri = try render(Form(name: "polygon") {
            $0.drawPolygon([Vector2(40, 50), Vector2(190, 50), Vector2(190, 160), Vector2(40, 160)])
        }, fill: .shader(Self.uvShader), stroke: nil)
        for p in [sdf, tri] {
            // Two pixels inside each corner: 2/150 and 2/110 of the way in.
            #expect(p.channel(0, 42, 52) < 8 && p.channel(1, 42, 52) < 10, "top-left")
            #expect(p.channel(0, 187, 52) > 247 && p.channel(1, 187, 52) < 10, "top-right")
            #expect(p.channel(0, 42, 157) < 8 && p.channel(1, 42, 157) > 245, "bottom-left")
            #expect(p.channel(0, 187, 157) > 247 && p.channel(1, 187, 157) > 245, "bottom-right")
            #expect(p.channel(2, 100, 100) == 0 && p.channel(3, 100, 100) == 255)
        }
        var worst = 0
        for y in stride(from: 54, to: 156, by: 3) {
            for x in stride(from: 44, to: 186, by: 3) {
                for c in 0..<3 { worst = max(worst, abs(sdf.channel(c, x, y) - tri.channel(c, x, y))) }
            }
        }
        #expect(worst <= 1, "the two paths disagree by \(worst) levels inside the rectangle")
    }

    @Test func uvTurnsWithTheShape() throws {
        // A rectangle rotated a quarter turn about its center: the box turns with
        // it, so the pixel at what is now the screen's top-left corner reads the
        // uv of the shape's own corner that landed there, not (0, 0).
        let p = try render(Form(name: "turned") {
            $0.translate(128, 128); $0.rotate(.pi / 2); $0.drawRect(-60, -40, 120, 80)
        }, fill: .shader(Self.uvShader), stroke: nil)
        // After a quarter turn clockwise (y down), the shape's (u=0, v=0) corner
        // (-60, -40) lands at (40, -60) relative to the center: the screen's
        // top-right. The screen's top-left is the shape's (u=0, v=1) corner.
        #expect(p.channel(0, 90, 70) < 10 && p.channel(1, 90, 70) > 245, "screen top-left is the shape's bottom-left")
        #expect(p.channel(0, 166, 70) < 10 && p.channel(1, 166, 70) < 10, "screen top-right is the shape's top-left")
        #expect(p.channel(0, 90, 186) > 245 && p.channel(1, 90, 186) > 245, "screen bottom-left is the shape's bottom-right")
    }

    @Test func distanceIsSignedFromTheEdge() throws {
        // A circle of radius 60: a pixel is read at its center, so the pixel at
        // (128, 128) sits 0.71 from the circle's center and 59.29 inside (red
        // 0.988), the one at (158, 128) 29.5 inside (red 0.492); outside is blue.
        let p = try render(Form(name: "circle") { $0.drawCircle(128, 128, 60) },
                           fill: .shader(Self.edgeShader), stroke: nil)
        func expected(_ x: Int, _ y: Int) -> Int {
            let d = 60 - ((Double(x) + 0.5 - 128) * (Double(x) + 0.5 - 128)
                          + (Double(y) + 0.5 - 128) * (Double(y) + 0.5 - 128)).squareRoot()
            return Int((min(d / 60, 1) * 255).rounded())
        }
        #expect(abs(p.channel(0, 128, 128) - expected(128, 128)) <= 1, "the center reads \(p.channel(0, 128, 128))")
        #expect(abs(p.channel(0, 158, 128) - expected(158, 128)) <= 1, "30 units inside reads \(p.channel(0, 158, 128))")
        #expect(abs(p.channel(0, 100, 150) - expected(100, 150)) <= 1, "off axis reads \(p.channel(0, 100, 150))")
        #expect(p.channel(2, 128, 128) == 0)
        // The polygon path has no edge distance: a fill reads far inside everywhere.
        let poly = try render(Form(name: "polygon") {
            $0.drawPolygon([Vector2(60, 60), Vector2(200, 60), Vector2(200, 200), Vector2(60, 200)])
        }, fill: .shader(Self.edgeShader), stroke: nil)
        #expect(poly.channel(0, 62, 62) == 255 && poly.channel(0, 128, 128) == 255)
    }

    @Test func aStrokeReadsAlongAndAcross() throws {
        // A horizontal line 20 wide from x 20 to 236: `along` is 0.5 at its
        // middle, `distance` 8 of 10 near its edge, and its sign flips across it.
        let line = try render(Form(name: "line") { $0.strokeWeight(20); $0.drawLine(20, 128, 236, 128) },
                              fill: nil, stroke: .shader(Self.strokeShader))
        #expect(abs(line.channel(0, 128, 128) - 128) <= 2, "along at the middle reads \(line.channel(0, 128, 128))")
        #expect(line.channel(0, 40, 128) < 40 && line.channel(0, 216, 128) > 215, "along runs start to end")
        // Pixels are read at their centers: row 128 sits 0.5 off the centerline
        // (green 0.05), row 120 sits 7.5 off (green 0.75).
        #expect(abs(line.channel(1, 128, 128) - 13) <= 1, "half a point off the centerline reads \(line.channel(1, 128, 128))")
        #expect(abs(line.channel(1, 128, 120) - 191) <= 2, "7.5 of 10 across reads \(line.channel(1, 128, 120))")
        #expect(line.channel(2, 128, 120) != line.channel(2, 128, 136), "the sign flips across the line")
        // A round cap: the distance keeps growing out to the cap's rim along the
        // line's own axis, with no hairline where the cap's wedges change sign
        // (a wedge straddling zero would interpolate |distance| down to 0 there).
        let capped = try render(Form(name: "capped") {
            $0.strokeWeight(20); $0.strokeCap(.round); $0.drawLine(60, 128, 196, 128)
        }, fill: nil, stroke: .shader(Self.strokeShader))
        #expect(abs(capped.channel(1, 54, 128) - 140) <= 24, "5.5 units into the cap reads \(capped.channel(1, 54, 128))")
        #expect(capped.channel(1, 51, 128) > capped.channel(1, 56, 128), "the distance grows toward the rim")
        // A closed outline, on both stroke paths: inside is negative (blue 1),
        // outside positive, whichever way the outline was drawn.
        let box = try render(Form(name: "rect outline") { $0.strokeWeight(12); $0.drawRect(60, 60, 140, 140) },
                             fill: nil, stroke: .shader(Self.strokeShader))
        #expect(box.channel(2, 128, 63) == 255 && box.channel(2, 128, 57) == 0, "SDF outline: inside negative")
        let poly = try render(Form(name: "polygon outline") {
            $0.strokeWeight(12)
            $0.drawPolygon([Vector2(60, 60), Vector2(200, 60), Vector2(200, 200), Vector2(60, 200)])
        }, fill: nil, stroke: .shader(Self.strokeShader))
        #expect(poly.channel(2, 128, 63) == 255 && poly.channel(2, 128, 57) == 0, "fringe outline, clockwise: inside negative")
        let widdershins = try render(Form(name: "polygon outline") {
            $0.strokeWeight(12)
            $0.drawPolygon([Vector2(60, 60), Vector2(60, 200), Vector2(200, 200), Vector2(200, 60)])
        }, fill: nil, stroke: .shader(Self.strokeShader))
        #expect(widdershins.channel(2, 128, 63) == 255 && widdershins.channel(2, 128, 57) == 0,
                "fringe outline, counterclockwise: inside negative")
    }

    @Test func positionIsTheCanvasPoint() throws {
        // Two shapes under one shader read one picture: the canvas itself, so a
        // pattern continues across them, and a rotated shape does not turn it.
        let p = try render(Form(name: "two") {
            $0.drawRect(20, 20, 100, 216)
            $0.translate(180, 128); $0.rotate(0.7); $0.drawRect(-40, -90, 80, 180)
        }, fill: .shader(Self.positionShader), stroke: nil)
        for (x, y) in [(40, 40), (100, 200), (180, 128), (170, 90)] {
            #expect(abs(p.channel(0, x, y) - Int((Double(x) + 0.5) / 256 * 255)) <= 2, "x at \(x), \(y)")
            #expect(abs(p.channel(1, x, y) - Int((Double(y) + 0.5) / 256 * 255)) <= 2, "y at \(x), \(y)")
        }
    }

    @Test func parametersReachThePaint() throws {
        let shader = Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            return float4(param(info, 0), param(info, 1), float(info.paramCount) / 4.0, 1.0);
        }
        """, params: [0.25, 0.75])
        let p = try render(Form(name: "rect") { $0.drawRect(40, 50, 150, 110) },
                           fill: .shader(shader), stroke: nil)
        #expect(abs(p.channel(0, 128, 100) - 64) <= 1 && abs(p.channel(1, 128, 100) - 191) <= 1)
        #expect(abs(p.channel(2, 128, 100) - 128) <= 1)
    }

    @Test func aMeshReadsTheShaderAsItsSurface() throws {
        // A unit plane facing an orthographic camera two units tall on a 256
        // canvas covers the same 128 points a rectangle does; the shader baked as
        // its texture reads at its uvs, so the two pictures agree, corner for corner.
        let mesh = try render(Form(name: "plane") { sketch in
            sketch.camera(Camera3D(eye: Vector3(0, 5, 0), target: .zero, up: Vector3(0, 0, -1),
                                   projection: .orthographic(height: 2)))
            sketch.noLights()
            sketch.drawMesh(Mesh.plane(width: 1, depth: 1))
        }, fill: .shader(Self.uvShader), stroke: nil)
        let rect = try render(Form(name: "rect") { $0.drawRect(64, 64, 128, 128) },
                              fill: .shader(Self.uvShader), stroke: nil)
        #expect(mesh.channel(0, 67, 67) < 12 && mesh.channel(1, 67, 67) < 12, "top-left")
        #expect(mesh.channel(0, 188, 67) > 240 && mesh.channel(1, 188, 67) < 12, "top-right")
        #expect(mesh.channel(0, 67, 188) < 12 && mesh.channel(1, 67, 188) > 240, "bottom-left")
        var sum = 0.0, count = 0.0, worst = 0
        for y in stride(from: 70, to: 186, by: 2) {
            for x in stride(from: 70, to: 186, by: 2) {
                for c in 0..<2 {
                    let d = abs(mesh.channel(c, x, y) - rect.channel(c, x, y))
                    sum += Double(d); count += 1; worst = max(worst, d)
                }
            }
        }
        #expect(sum / count < 1.5, "the mesh and the rectangle differ by \(sum / count) levels on average")
        #expect(worst <= 6, "worst pixel differs by \(worst) levels")
        // Outside the plane the canvas is the background.
        #expect(mesh.channel(0, 30, 30) == 0 && mesh.channel(1, 30, 30) == 0)
    }

    @Test func shapesUnderOneShaderShareARun() throws {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.fill(Self.uvShader)
        drawer.noStroke()
        for i in 0..<5 { drawer.drawRect(Rectangle(x: Double(i) * 20, y: 10, width: 15, height: 15)) }
        #expect(drawer.batches.count == 1)
        #expect(drawer.batches.first?.paintShader == Self.uvShader)
        // A plain shape between two shaded ones breaks the run; two shaders alternate.
        drawer.fill(.white)
        drawer.drawRect(Rectangle(x: 0, y: 40, width: 15, height: 15))
        drawer.fill(Self.uvShader)
        drawer.drawRect(Rectangle(x: 20, y: 40, width: 15, height: 15))
        drawer.fill(Self.edgeShader)
        drawer.drawRect(Rectangle(x: 40, y: 40, width: 15, height: 15))
        #expect(drawer.batches.count == 4)
        #expect(drawer.batches[1].paintShader == nil)
        #expect(drawer.batches[3].paintShader == Self.edgeShader)
        // The paint kind rides the tag's fill slot (5), the stroke slot staying 0.
        let tag = drawer.sdfInstances[0].shape
        #expect((tag >> 10) & 7 == 5 && (tag >> 13) & 7 == 0)
    }

    @Test func aBrokenShaderDrawsNothingAndSaysSo() throws {
        let broken = Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            return float4(uv, 0.0, nonsense);
        }
        """)
        let p = try render(Form(name: "rect") { $0.drawRect(40, 50, 150, 110) },
                           fill: .shader(broken), stroke: nil)
        let blank = try render(Form(name: "rect") { $0.drawRect(40, 50, 150, 110) }, fill: nil, stroke: nil)
        #expect(p.bytes == blank.bytes)
    }

    @Test func theWebPageNamesTheCall() throws {
        let sketch = PaintedForm({ $0.drawRect(40, 50, 150, 110) }, fill: .shader(Self.uvShader), stroke: nil)
        let refusal = #expect(throws: WebExportRefusal.self) {
            _ = try OllinApp.recordWebFrames(of: sketch, frames: 2, fps: 30)
        }
        #expect(refusal?.call.contains("fill(Shader)") == true)
    }

    @Test func aVectorFileWritesTheShapeInGray() throws {
        let sketch = PaintedForm({ $0.drawRect(40, 50, 150, 110) }, fill: .shader(Self.uvShader), stroke: .shader(Self.edgeShader))
        let svg = try OllinApp.svg(of: sketch)
        #expect(svg.contains("<rect x=\"40\" y=\"50\" width=\"150\" height=\"110\" fill=\"rgb(128,128,128)\""))
        #expect(svg.contains("stroke=\"rgb(128,128,128)\""))
    }

    @Test func paintCarriesAShaderAsOneValue() throws {
        let paint = Paint.shader(Self.uvShader)
        #expect(paint.solidColor == nil)
        #expect(paint.shader == Self.uvShader)
        #expect(Paint.color(.red).shader == nil)
        #expect(Self.uvShader != Self.edgeShader)
        #expect(Shader("a") == Shader("a", params: []) && Shader("a") != Shader("a", params: [1]))
        var seen: Set<Paint> = [paint, .shader(Self.edgeShader), .color(.red)]
        seen.insert(.shader(Self.uvShader))
        #expect(seen.count == 3)
    }
}

/// A 256-point canvas over black, one form drawn under the given fill and stroke
/// (12 wide, so a shader stroke has room to read across).
@MainActor
private final class PaintedForm: Sketch {
    var form: (Sketch) -> Void = { _ in }
    var fillPaint: Paint?
    var strokePaint: Paint?

    convenience init(_ form: @escaping (Sketch) -> Void, fill: Paint?, stroke: Paint?) {
        self.init()
        self.form = form
        self.fillPaint = fill
        self.strokePaint = stroke
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        if let fillPaint { fill(fillPaint) } else { noFill() }
        if let strokePaint { stroke(strokePaint) } else { noStroke() }
        strokeWeight(12)
        form(self)
    }
}
