import Testing
import Foundation
import CoreGraphics
import ImageIO
import OllinWebGate
@testable import Ollin

/// The field door of the web page: a composed 2D field (`drawSDF`) crosses as
/// its covering quad and its node program, a raymarched 3D field (`drawSDF3D`)
/// as its program, its bounds, and the frame's scene block (the camera, the
/// lights, the march budget), and the page walks both programs with the
/// framework's own arithmetic carried to GLSL. The recorder is checked on its
/// own (what a frame holds, what folds, what refuses), then the page against
/// the Mac in the shared browser gate.
@Suite @MainActor struct WebFieldTests {

    // MARK: Fixtures

    /// Two composed fields: a melt of circles with a carved bar and a stroke,
    /// its morph moving with the clock, under a linear fill; and a mirrored
    /// ring tiled twice, colored leaf by leaf.
    final class Combined: Sketch {
        override var canvasSize: CanvasSize { .square(240) }
        override func draw() {
            background(.white)
            let blob = SDF.circle(radius: 34).at(90, 90)
                .smoothUnion(SDF.circle(radius: 26).at(140, 110 + sin(time) * 12), k: 22)
                .subtract(SDF.rect(width: 90, height: 12).rotated(0.4).at(115, 100))
                .morph(SDF.star(outerRadius: 44, innerRadius: 20, points: 5).at(115, 100), amount: 0.3 + 0.2 * sin(time * 0.7))
            fill(Gradient.linear(from: Vector2(40, 40), to: Vector2(200, 160), [.red, .blue]))
            stroke(.black)
            strokeWeight(3)
            drawSDF(blob)
            noStroke()
            fill(.black)
            let ring = SDF.ring(innerRadius: 8, outerRadius: 14).colored(Color(hex: 0x206040))
                .union(SDF.square(10, cornerRadius: 3).colored(Color(hex: 0xD04020)).at(0, -22))
                .mirrored(x: true, y: false)
                .repeated(spacing: Vector2(50, 0), count: 1)
                .at(120, 190)
            drawSDF(ring)
        }
    }

    /// A composed field under symmetry and under the additive blend, and one
    /// replayed from a recording turning.
    final class Folded: Sketch {
        override var canvasSize: CanvasSize { .square(160) }
        var batch: Batch?
        override func setup() {
            batch = makeBatch {
                fill(Color(hex: 0x3060C0))
                drawSDF(SDF.circle(radius: 14).smoothUnion(SDF.circle(radius: 10).at(18, 0), k: 8))
            }
        }
        override func draw() {
            background(.black)
            symmetry(4)
            blendMode(.add)
            fill(Color(red: 0.5, green: 0.2, blue: 0.1, alpha: 0.9))
            drawSDF(SDF.rhombus(width: 60, height: 30).at(90, 60).rounded(4))
            noSymmetry()
            blendMode(.normal)
            guard let batch else { return }
            withState {
                translate(80, 80)
                rotate(Double(frameCount) * 0.15)
                drawBatch(batch)
            }
        }
    }

    /// A raymarched blob under a directional key and ambient, glossy, on a
    /// turntable: the field carved and melted, the smooth seam blending colors.
    final class Marched: Sketch {
        override var canvasSize: CanvasSize { .square(200) }
        override func draw() {
            background(Color(hex: 0x0e1116))
            camera(.orbiting(target: .zero, radius: 5.5, azimuth: time * 0.5, elevation: 0.45,
                             fieldOfView: .pi / 4, near: 0.1, far: 40))
            directionalLight(.white, direction: Vector3(-0.6, 0.7, 0.5), intensity: 1.1, softness: 0.3)
            ambientLight(Color(white: 0.16))
            material(.glossy)
            let orbit = Vector3(cos(time) * 1.3, sin(time * 1.3) * 0.5, sin(time) * 1.3)
            let blob = SDF3D.sphere(radius: 1.05).colored(Color(hex: 0x39d0ff))
                .smoothUnion(SDF3D.sphere(radius: 0.85).at(orbit).colored(Color(hex: 0xff4f97)), k: 0.7)
                .smoothUnion(SDF3D.box(size: 1.0).rotatedY(0.6).at(-1.1, 0.7, 0.4).colored(Color(hex: 0xb6ff5a)), k: 0.5)
                .smoothSubtract(SDF3D.sphere(radius: 0.7).at(0.2, 1.15, 0), k: 0.25)
            drawSDF3D(blob)
        }
    }

    /// The scoped block form under jade (the subsurface bleed) and a
    /// screen-space gradient fill on a second field, with a point light and a
    /// spot beside the key.
    final class Sculpted: Sketch {
        override var canvasSize: CanvasSize { .square(200) }
        override func draw() {
            background(Color(hex: 0x131018))
            camera(.orbiting(target: Vector3(0, 0.1, 0), radius: 6.2, azimuth: 0.4 + time * 0.2, elevation: 0.3,
                             fieldOfView: .pi / 4, near: 0.1, far: 40))
            directionalLight(.white, direction: Vector3(-0.5, 0.8, 0.4), intensity: 1.15, softness: 0.3)
            pointLight(Color(hex: 0xffd080), at: Vector3(2.5, 2.0, 1.5), intensity: 3)
            spotLight(Color(hex: 0x80c0ff), at: Vector3(-2, 3, 2), direction: Vector3(0.5, -1, -0.5),
                      coneAngle: 0.8, penumbra: 0.4, intensity: 4)
            ambientLight(Color(white: 0.18))
            material(.jade)
            sculpt {
                blend(0.3)
                fill(Color(hex: 0xd96f4e))
                withState { drawSphere(radius: 1.0) }
                withState { translate(0, -1.0, 0); drawCylinder(radius: 0.55, height: 0.5) }
                fill(Color(hex: 0xe8a06a))
                withState { translate(0, 0.95, 0); drawTorus(radius: 0.5, tube: 0.16) }
                carve()
                withState { translate(0, 1.1, 0); drawSphere(radius: 0.52) }
            }
            material(.glossy)
            fill(.linear(from: Vector2(0, 40), to: Vector2(0, 160), [Color(hex: 0xfb923c), Color(hex: 0x6366f1)]))
            withState { translate(2.0, -0.2, 0); drawSDF3D(SDF3D.octahedron(radius: 0.7).roughened(amplitude: 0.05, frequency: 6)) }
        }
    }

    /// Self-shadowing under `castShadows()`: a ground plane with a ball, a bar,
    /// and a pin, the field unbounded, the caster the key light.
    final class Shadowed: Sketch {
        override var canvasSize: CanvasSize { .square(200) }
        override func draw() {
            background(Color(hex: 0x0a0e16))
            camera(.orbiting(target: Vector3(0, 0.1, 0), radius: 7, azimuth: 0.9 + time * 0.22, elevation: 0.32,
                             fieldOfView: .pi / 4, near: 0.1, far: 60))
            directionalLight(.white, direction: Vector3(0.4, -0.92, -0.25), intensity: 1.3, softness: 0.2)
            ambientLight(Color(white: 0.14))
            castShadows()
            material(.glossy)
            let floor = SDF3D.plane(offset: -0.85).colored(Color(hex: 0x5b6472))
            let ball = SDF3D.sphere(radius: 0.7).colored(Color(hex: 0x38bdf8)).at(-1.5, -0.15, 0.2)
            let bar = SDF3D.capsule(radius: 0.3, height: 1.0).colored(Color(hex: 0xf472b6)).rotatedZ(0.5).at(0.3, 0.05, -0.7)
            let pin = SDF3D.cone(radius: 0.55, height: 1.6).colored(Color(hex: 0xfacc15)).at(1.7, -0.05, 0.6)
            drawSDF3D(floor.union(ball).union(bar).union(pin))
        }
    }

    /// A march at a reduced resolution, upsampled: the Mac's coverage-adaptive
    /// fraction, traced into a smaller target and read back bilinear.
    final class Reduced: Sketch {
        override var canvasSize: CanvasSize { .square(200) }
        override func draw() {
            raymarchResolution(0.5)
            background(Color(hex: 0x0b1020))
            camera(.orbiting(target: .zero, radius: 6, azimuth: time * 0.4, elevation: 0.25,
                             fieldOfView: .pi / 4, near: 0.1, far: 40))
            directionalLight(.white, direction: Vector3(-0.3, -0.85, -0.45), intensity: 1.2, softness: 0.35)
            ambientLight(Color(white: 0.22))
            material(.clay)
            fill(Color(hex: 0xf2c14e))
            let blob = SDF3D.sphere(radius: 1.05)
                .smoothUnion(SDF3D.sphere(radius: 0.7).at(1.3, 0.4, 0), k: 0.55)
                .smoothUnion(SDF3D.torus(radius: 1.1, tube: 0.25).at(-0.8, -0.6, 0.3), k: 0.4)
            drawSDF3D(blob)
        }
    }

    /// Three finishes on three fields: a physically-based metal (the split-sum
    /// table), a toon cel, and a Gooch warm-cool, plus an iridescent rim.
    final class Finished: Sketch {
        override var canvasSize: CanvasSize { .square(200) }
        override func draw() {
            background(Color(hex: 0x101418))
            camera(.orbiting(target: .zero, radius: 7, azimuth: 0.3 + time * 0.3, elevation: 0.35,
                             fieldOfView: .pi / 4, near: 0.1, far: 40))
            directionalLight(.white, direction: Vector3(-0.5, 0.9, 0.3), intensity: 1.2)
            pointLight(Color(hex: 0xffc080), at: Vector3(0, 3, 3), intensity: 5)
            ambientLight(Color(white: 0.12))
            material(.polishedMetal)
            fill(Color(hex: 0xd0b060))
            withState { translate(-1.8, 0, 0); drawSDF3D(SDF3D.sphere(radius: 0.9).smoothUnion(SDF3D.box(size: 0.9).at(0.5, 0.7, 0), k: 0.3)) }
            material(Material(shading: .toon, toonBands: 3, specular: 0.5, specularSharpness: 40))
            fill(Color(hex: 0x60c0f0))
            withState { translate(0, 0, 0); drawSDF3D(SDF3D.torus(radius: 0.8, tube: 0.3).rotatedX(0.8)) }
            var gooch = Material(shading: .gooch)
            gooch.iridescence = 0.6
            gooch.rim = 0.4
            gooch.rimColor = Color(hex: 0xff8060)
            material(gooch)
            fill(Color(hex: 0xe0e0e0))
            withState { translate(1.8, 0, 0); drawSDF3D(SDF3D.mengerSponge(iterations: 2, size: 1.6)) }
        }
    }

    // MARK: The recorder

    @Test func aComposedFieldCrossesAsItsQuadAndProgram() throws {
        let sketch = Combined()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 3, fps: 30)
        let frame = recording.frames[2]
        let g = frame.graph
        #expect(g.groupCount == 2)
        #expect(g.nodeCount == sketch.drawer.sdfNodes.count)
        #expect(g.instanceCount == 0 && g.fieldCount == 0 && g.node3DCount == 0)
        #expect(frame.vector.count == g.vectorCount)
        #expect(frame.scene.isEmpty)
        #expect(!g.hasFields && !g.needsMultisampling)
        var items: [(Int, Int)] = []
        for item in g.canvas {
            guard case let .groups(start, count, blend) = item else { Issue.record("\(item)"); continue }
            #expect(blend == 0)
            items.append((start, count))
        }
        // The two calls share a run (one blend, no batch break), so one item names both.
        #expect(items.map(\.0) == [0] && items.map(\.1) == [2])
        // The first group on the wire is the drawer's, field for field: the
        // identity transform, its program at node 0, a 3-point stroke, a linear
        // fill on the strip's first row.
        let group = Array(frame.vector[g.groupOffset ..< g.groupOffset + WebGroup.floats])
        let drawn = sketch.drawer.sdfGroups[0]
        #expect(Array(group[0 ..< 6]) == [1, 0, 0, 1, 0, 0])
        #expect(group[6] == drawn.center.x && group[7] == drawn.center.y)
        #expect(group[10] == 3 && group[20] == 0 && group[21] == Float(drawn.nodeCount))
        #expect(group[22] == 1 && group[23] == 0 && group[24] == 0)
        // The second group's program follows the first's.
        let second = Array(frame.vector[g.groupOffset + WebGroup.floats ..< g.groupOffset + 2 * WebGroup.floats])
        #expect(second[20] == Float(drawn.nodeCount))
        // A node on the wire is the drawer's: the first is a translate scope.
        let node = Array(frame.vector[g.nodeOffset ..< g.nodeOffset + WebNode.floats])
        let n0 = sketch.drawer.sdfNodes[0]
        #expect(node[0] == Float(n0.kind) && node[1] == Float(n0.sel))
        #expect(node[8] == n0.geo0.x && node[9] == n0.geo0.y)
        // The morph amount moves with the clock, so the frames differ; the graph does not.
        #expect(recording.frames[0].vector != recording.frames[2].vector)
        #expect(recording.frames[0].graph == recording.frames[2].graph)
        let track = WebTrack(recording)
        #expect(track.stable)
        #expect(track.groupCount == 2 && track.fieldCount == 0)
    }

    @Test func symmetryCopiesAndARecordingShareOneProgram() throws {
        let sketch = Folded()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 2, fps: 30)
        let frame = recording.frames[1]
        let g = frame.graph
        // Four folds of the rhombus, then the recording's field: five groups
        // over two programs.
        #expect(g.groupCount == 5)
        let batch = try #require(sketch.batch)
        #expect(g.nodeCount == sketch.drawer.sdfNodes.count + batch.sdfNodes.count)
        var blends: [Int] = []
        var starts: [Float] = []
        for item in g.canvas {
            guard case let .groups(start, count, blend) = item else { Issue.record("\(item)"); continue }
            blends.append(blend)
            for i in start ..< start + count {
                starts.append(frame.vector[g.groupOffset + i * WebGroup.floats + 20])
            }
        }
        #expect(blends == [WebBlend.index(of: .add), 0])
        #expect(starts[0] == starts[1] && starts[1] == starts[2] && starts[2] == starts[3])
        #expect(starts[4] == Float(sketch.drawer.sdfNodes.count))
        // The recording's group lands under the draw-time transform: its
        // translation is the frame's.
        let last = g.groupOffset + 4 * WebGroup.floats
        #expect(abs(frame.vector[last + 4] - 80) < 1e-3 && abs(frame.vector[last + 5] - 80) < 1e-3)
    }

    @Test func aRaymarchedFieldCrossesWithItsScene() throws {
        let sketch = Marched()
        let recording = try OllinApp.recordWebFrames(of: sketch, frames: 3, fps: 30)
        let frame = recording.frames[2]
        let g = frame.graph
        #expect(g.fieldCount == 1 && g.groupCount == 0)
        #expect(g.node3DCount == sketch.drawer.sdf3DNodes.count)
        #expect(g.hasFields)
        #expect(frame.vector.count == g.vectorCount)
        #expect(g.canvas.count == 1)
        guard case let .fields(start, count, blend, material) = g.canvas[0] else { Issue.record("\(g.canvas)"); return }
        #expect(start == 0 && count == 1 && blend == 0)
        // The finish's rows sit in the parameter region: glossy is a standard
        // model at specular 0.9, sharpness 160.
        let rows = Array(frame.vector[g.paramOffset + material ..< g.paramOffset + material + WebMaterial.rows * 4])
        #expect(rows.count == 36)
        #expect(abs(rows[20] - 0.9) < 1e-6 && rows[21] == 160 && rows[26] == 0)
        // The field on the wire: the drawer's, field for field.
        let field = Array(frame.vector[g.fieldOffset ..< g.fieldOffset + WebField.floats])
        let drawn = sketch.drawer.sdf3DGroups[0]
        #expect(field[16] == drawn.boundsMin.x && field[19] == drawn.modelScale && field[23] == 0)
        #expect(field[28] == 0 && field[29] == Float(drawn.nodeCount) && field[30] == 0)
        // The scene block: three matrices, four rows, the counts, one light,
        // no caster (nothing casts).
        let header = WebGraphRecorder.WebScene.headerFloats
        #expect(frame.scene.count == header + WebGraphRecorder.WebScene.lightFloats)
        #expect(frame.scene[48] == 200 && frame.scene[49] == 200)
        #expect(frame.scene[50] == 192 && frame.scene[51] == 72)   // the export's `.detail` budget
        #expect(frame.scene[52] == 1 && frame.scene[53] == 200)     // a full-resolution march
        #expect(frame.scene[63] == 1)                               // lit
        #expect(frame.scene[64] == 1 && frame.scene[65] == 0)       // one light, no caster
        #expect(frame.scene[header + 12] == 0)                      // a directional light
        // The camera turns, so the scene moves; the cast holds.
        #expect(recording.frames[0].scene != recording.frames[2].scene)
        let track = WebTrack(recording)
        #expect(track.stable)
        #expect(track.fieldCount == 1)
        #expect(!track.scene.isEmpty)
        #expect(track.meta.contains("\"sceneOffsets\""))
        #expect(recording.brdfLUT.isEmpty)
    }

    @Test func aStillFieldUnderATurningCameraIsANewFrameEveryFrame() throws {
        // The Shadowed scene's field never moves; only its camera does, and that
        // lives in the scene block, so the fold must read the scene too or
        // every frame would play the first frame's camera.
        let recording = try OllinApp.recordWebFrames(of: Shadowed(), frames: 4, fps: 30)
        #expect(recording.frames[0].vector == recording.frames[3].vector)
        #expect(recording.frames[0].scene != recording.frames[3].scene)
        let track = WebTrack(recording)
        #expect(track.uniqueFrames == 4)
        #expect(track.stable)
    }

    @Test func aReducedMarchCarriesItsScaleAndAShadowItsCaster() throws {
        let reduced = try OllinApp.recordWebFrames(of: Reduced(), frames: 1, fps: 30)
        let scene = reduced.frames[0].scene
        #expect(scene[50] == 128 && scene[51] == 48)   // a custom resolution keeps the default budget
        #expect(scene[52] > 0 && scene[52] < 1)
        #expect(Double(scene[53]) == (200 * Double(scene[52])).rounded())
        let shadowed = try OllinApp.recordWebFrames(of: Shadowed(), frames: 1, fps: 30)
        let s = shadowed.frames[0].scene
        let header = WebGraphRecorder.WebScene.headerFloats
        #expect(s[65] == 1)
        #expect(s.count == header + WebGraphRecorder.WebScene.lightFloats + WebGraphRecorder.WebScene.casterFloats)
        #expect(s[header + 20] == 0 && s[header + 21] == 1)   // caster: light 0 at full strength
        let g = shadowed.frames[0].graph
        #expect(shadowed.frames[0].vector[g.fieldOffset + 23] == 1)   // unbounded: the plane
    }

    @Test func aPhysicallyBasedFieldBringsTheTable() throws {
        let recording = try OllinApp.recordWebFrames(of: Finished(), frames: 1, fps: 30)
        #expect(recording.frames[0].graph.fieldCount == 3)
        #expect(recording.frames[0].graph.canvas.count == 3)
        #expect(recording.brdfLUT.count == WebBRDFLUT.size * WebBRDFLUT.size * 2)
        // A rough dielectric keeps most of its energy; the table reads near 1.
        let n = WebBRDFLUT.size
        let (a, b) = WebBRDFLUT.integrate(ndv: 0.7, rough: 0.5)
        #expect(a + b > 0.85 && a + b < 1.0, "\(a) + \(b)")
        // The half conversion round-trips a few values exactly.
        #expect(WebHalf.bits(1.0) == 0x3C00 && WebHalf.bits(0.5) == 0x3800 && WebHalf.bits(0) == 0)
        #expect(WebHalf.bits(-2.0) == 0xC000)
        let mid = recording.brdfLUT[((n / 2) * n + n / 2) * 2]
        #expect(mid > 0x3000 && mid < 0x3C00)
    }

    @Test func whatThePageCannotLightIsRefusedByName() throws {
        final class Lit: Sketch {
            var setup3D: (Lit) -> Void = { _ in }
            override var canvasSize: CanvasSize { .square(80) }
            override func draw() {
                background(.black)
                camera(.orbiting(target: .zero, radius: 5, azimuth: 0.3, elevation: 0.3, fieldOfView: .pi / 4, near: 0.1, far: 30))
                directionalLight(.white, direction: Vector3(-0.5, 0.8, 0.4))
                setup3D(self)
                drawSDF3D(SDF3D.sphere(radius: 1))
            }
        }
        func refusal(_ configure: @escaping (Lit) -> Void) -> String {
            let sketch = Lit()
            sketch.setup3D = configure
            do {
                _ = try OllinApp.recordWebFrames(of: sketch, frames: 1, fps: 30)
                return "crossed"
            } catch let r as WebExportRefusal {
                return r.call
            } catch {
                return "\(error)"
            }
        }
        #expect(refusal { $0.environment(.sunset) }.hasPrefix("an environment"))
        #expect(refusal { $0.fog(.gray, density: 0.1) }.hasPrefix("fog"))
        #expect(refusal { $0.rectangleLight(.white, at: Vector3(0, 3, 0), direction: Vector3(0, -1, 0), width: 2, height: 2) }.hasPrefix("an area light"))
        #expect(refusal { $0.material(.glass()) }.hasPrefix("a transmissive"))
        #expect(refusal { var m = Material.polishedMetal; m.clearcoat = 0.5; $0.material(m) }.hasPrefix("a clear-coated"))
        #expect(refusal { $0.contactShadows() }.hasPrefix("contactShadows"))
        #expect(refusal { _ in } == "crossed")
    }

    @Test func thePagesFieldShadersAreTheFrameworksOwn() throws {
        let shaders = try WebShaders.make(groups: true, fields: true)
        #expect(shaders.groupFragment.contains("void ollin_sdf_combine(uint op, float da, vec4 ca, float db, vec4 cb,"))
        #expect(shaders.groupFragment.contains("float ollin_sdf_distance(uint shape, vec2 p, vec2 size,"))
        #expect(shaders.groupFragment.contains("layout(std140) uniform Nodes { vec4 nodeRows[1024]; };"))
        #expect(shaders.groupFragment.contains("regionCoverage(d, hw, strokeWidth, 0.0, fillCov, strokeCov);"))
        #expect(shaders.fieldFragment.contains("float ollin_sdf3d_eval(uint shape, vec3 p, vec4 geo0, vec4 geo1)"))
        #expect(shaders.fieldFragment.contains("float ollin_sd3_mandelbox("))
        #expect(shaders.fieldFragment.contains("float valueNoise(vec3 p)"))
        #expect(shaders.fieldFragment.contains("gl_FragDepth = clip.z / clip.w;"))
        #expect(shaders.fieldFragment.contains("vec4 litColor(vec3 base, float alpha, vec3 normal, vec3 worldPos, float fieldShadow[4])"))
        // A page with no field carries neither.
        let plain = try WebShaders.make()
        #expect(plain.groupFragment.isEmpty && plain.fieldFragment.isEmpty)
    }

    // MARK: The browser

    /// A picture written out for a look, under `OLLIN_WEB_DUMP`.
    static func dump(_ image: CGImage, to path: String) {
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func thePageDrawsTheFieldsTheMacDrew() async throws {
        let cases: [(name: String, make: () -> Sketch, frames: Int, probe: Int)] = [
            ("Combined (a melt, a carve, a morph, a gradient, a stroke, a tiling)", { Combined() }, 8, 5),
            ("Folded (symmetry, additive, a recording)", { Folded() }, 4, 2),
            ("Marched (a turntable blob)", { Marched() }, 6, 4),
            ("Sculpted (jade, a gradient, a spot and a point)", { Sculpted() }, 1, 0),
            ("Shadowed (a self-shadowing plane)", { Shadowed() }, 1, 0),
            ("Reduced (a half-resolution march)", { Reduced() }, 3, 1),
            ("Finished (metal, toon, Gooch)", { Finished() }, 1, 0),
        ]
        for c in cases {
            let recording = try OllinApp.recordWebFrames(of: c.make(), frames: c.frames, fps: 30)
            let page = try OllinApp.webPage(of: recording, form: .inline)
            let played = try await WebExportTests.pagePixels(page, frame: c.probe)
            let reference = try #require(OllinApp.image(of: c.make(), frame: c.probe, fps: 30))
            let difference = try WebExportTests.meanDifference(played, reference)
            let far = WebTriangleTests.farFraction(played, reference)
            print("web page against the Mac: \(c.name) frame \(c.probe), mean difference \(String(format: "%.3f", difference)), \(String(format: "%.3f", far * 100))% of the pixels past 32 levels")
            if let dir = ProcessInfo.processInfo.environment["OLLIN_WEB_DUMP"] {
                let slug = String(c.name.prefix { $0.isLetter })
                Self.dump(played, to: "\(dir)/\(slug)-page.png")
                Self.dump(reference, to: "\(dir)/\(slug)-mac.png")
            }
            #expect(difference < Snapshot.tolerance, "\(c.name) frame \(c.probe): mean difference \(difference)")
            #expect(far < WebTriangleTests.farTolerance, "\(c.name) frame \(c.probe): \(far * 100)% of the pixels past 32 levels")
        }
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theGateSeesATurnedField() async throws {
        // The page at one frame of the turntable against the Mac at another
        // must read as different, or the parity above proves nothing.
        let recording = try OllinApp.recordWebFrames(of: Marched(), frames: 12, fps: 10)
        let page = try OllinApp.webPage(of: recording, form: .inline)
        let played = try await WebExportTests.pagePixels(page, frame: 0)
        let elsewhere = try #require(OllinApp.image(of: Marched(), frame: 11, fps: 10))
        let difference = try WebExportTests.meanDifference(played, elsewhere)
        #expect(difference > Snapshot.tolerance, "mean difference \(difference)")
    }
}
