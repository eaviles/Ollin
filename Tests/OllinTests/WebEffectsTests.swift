import Testing
import Foundation
import CoreGraphics
import OllinWebGate
@testable import Ollin

/// The shader door of the web page: layers, generators, filters, combines,
/// user shaders, chains, feedback, simulations, and whole-frame filters
/// recorded as a pass graph and played back with the framework's own
/// fragments carried to GLSL. The recorder is checked on its own (what the
/// graph holds, what stays live, what refuses), then each kind of pass is
/// played in the browser at a chosen frame and diffed against the same frame
/// from `OllinApp.image(of:frame:)` under the snapshot tolerance. The browser
/// checks skip, with the reason in the log, where no browser gives WebGL2.
@Suite @MainActor struct WebEffectsTests {

    // MARK: Fixtures

    /// A pattern filled from math alone, its phase on the clock.
    final class Generated: Sketch {
        override var canvasSize: CanvasSize { .square(160) }
        override func draw() {
            background(.black)
            drawImage(generate(.cellular(scale: 5, jitter: 0.8, style: .cells,
                                         foreground: Color(hex: 0xF2E8DC), background: Color(hex: 0x101820),
                                         phase: time * 2)).image, 0, 0)
        }
    }

    /// Shapes drawn into a layer, then two filters in a chain.
    final class Filtered: Sketch {
        override var canvasSize: CanvasSize { .square(160) }
        override func draw() {
            background(Color(hex: 0x0E1116))
            let layer = makeRenderTarget()
            withTarget(layer) {
                background(Color(hex: 0x0E1116))
                noStroke()
                let colors: [UInt32] = [0xFF5D73, 0xFFC857, 0x55D6BE, 0x8E7DBE]
                for r in 0 ..< 4 {
                    for c in 0 ..< 4 {
                        fill(Color(hex: colors[(r + c) % colors.count]))
                        drawCircle((Double(c) + 0.5) * 40, (Double(r) + 0.5) * 40, 14)
                    }
                }
            }
            drawImage(layer.filtered(.swirl(angle: 1.5 + sin(time) * 0.5, radius: 0.9))
                          .filtered(.colorGrade(contrast: 1.2, saturation: 1.4)).image, 0, 0)
        }
    }

    /// A generator recolored through a lookup strip.
    final class Mapped: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(.black)
            drawImage(generate(.noise(scale: 3, sharpness: 0.2)).filtered(.gradientMap(.viridis)).image, 0, 0)
        }
    }

    /// Two layers, mixed, then masked by a third.
    final class Combined: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(.white)
            let warm = makeRenderTarget()
            withTarget(warm) { background(Color(hex: 0xFF8C42)); noStroke(); fill(.white); drawCircle(60, 60, 30) }
            let cool = makeRenderTarget()
            withTarget(cool) { background(Color(hex: 0x4CC9F0)); noStroke(); fill(.black); drawRect(20, 20, 50, 80) }
            let mask = makeRenderTarget()
            withTarget(mask) { noStroke(); fill(.white); drawCircle(60 + sin(time) * 20, 60, 45) }
            drawImage(warm.combined(with: cool, .mix(amount: 0.5)).combined(with: mask, .mask()).image, 0, 0)
        }
    }

    /// The smallest user shader, run as a generator.
    final class UserGenerator: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        private let plasma = Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float2 p = (uv * 2.0 - 1.0) * 6.0;
            float fx = cos(p.x) * cos(p.y);
            float fy = sin(p.x) * sin(p.y);
            float v = unipolar(sin((fx * fx + fy * fy) * 6.28318 + info.time));
            float3 col = palette(v, float3(0.5), float3(0.5), float3(1.0), float3(0.0, 0.33, 0.67));
            return float4(col, 1.0);
        }
        """)
        override func draw() {
            background(.black)
            drawImage(generate(plasma).image, 0, 0)
        }
    }

    /// A user shader run as a filter, reading the layer with `sample`.
    final class UserFilter: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        private let wave = Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            uv.x += sin(uv.y * 24.0 + info.time) * 0.02;
            float4 c = sample(info, uv);
            c.rgb = floor(c.rgb * 6.0) / 6.0;
            return c;
        }
        """)
        override func draw() {
            let layer = makeRenderTarget()
            withTarget(layer) {
                background(Color(hex: 0x0E1116))
                noStroke()
                let colors: [UInt32] = [0xFF5D73, 0xFFC857, 0x55D6BE, 0x8E7DBE, 0x3A86FF]
                for r in 0 ..< 4 {
                    for c in 0 ..< 4 {
                        fill(Color(hex: colors[(r + c) % colors.count]))
                        drawCircle((Double(c) + 0.5) * 30, (Double(r) + 0.5) * 30, 10)
                    }
                }
            }
            drawImage(layer.filtered(.shader(wave)).image, 0, 0)
        }
    }

    /// A user shader run as a combine over two layers, with parameters.
    final class UserCombine: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        private let blend = Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float4 a = sample(info, uv);
            float4 b = sampleAux(info, uv);
            float edge = uv.x + uv.y - 1.0 + sin(uv.y * 18.0 + info.time) * param(info, 0);
            float m = smoothstep(-0.05, 0.05, edge);
            return mix(a, b, m);
        }
        """, params: [0.06])
        override func draw() {
            let warm = makeRenderTarget()
            withTarget(warm) {
                background(Color(hex: 0x2B1B12))
                noFill(); strokeWeight(6)
                for i in 0 ..< 6 { stroke(Color(hex: i % 2 == 0 ? 0xFF8C42 : 0xFFD166)); drawCircle(60, 60, Double(i) * 10 + 5) }
            }
            let cool = makeRenderTarget()
            withTarget(cool) {
                background(Color(hex: 0x0E1B2A))
                noStroke(); fill(Color(hex: 0x4CC9F0))
                for i in 0 ..< 5 { drawRect(Double(i) * 24 + 4, 10, 8, 100) }
            }
            drawImage(warm.combined(with: cool, .shader(blend)).image, 0, 0)
        }
    }

    /// A chain compiled into one pass.
    final class Chained: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            drawVisual(
                .oscillator(frequency: 12, speed: 1.2, colorShift: 0.35)
                    .kaleidoscope(segments: 6)
                    .rotated(time * 0.05)
                    .saturation(1.3)
            )
        }
    }

    /// The declarative stack: a half-size layer with a filter, a layer added
    /// as light, a layer screened.
    final class Composed: Sketch {
        override var canvasSize: CanvasSize { .square(160) }
        override func draw() {
            background(Color(white: 0.03))
            compose {
                layer {
                    noStroke()
                    for i in 0 ..< 4 {
                        let t = time * 0.2 + Double(i) * .tau / 4
                        fill(Color(hue: Double(i) / 4, saturation: 0.7, brightness: 0.6))
                        drawCircle(80 + cos(t) * 40, 80 + sin(t * 1.3) * 40, 36)
                    }
                }
                .post(.posterize(levels: 4))
                .scaled(0.5)

                layer {
                    noStroke()
                    for i in 0 ..< 12 {
                        let a = Double(i) / 12 * .tau + time * 0.4
                        fill(Color(hue: Double(i) / 12, saturation: 0.85, brightness: 1))
                        drawCircle(80 + cos(a) * 50, 80 + sin(a) * 50, 5)
                    }
                }
                .blended(.add)

                layer {
                    noStroke()
                    fill(Color(white: 0.3))
                    drawRect(20, 70, 120, 20)
                }
                .blended(.screen)
            }
        }
    }

    /// A layer that remembers itself: last frame spun and faded, a new mark on top.
    final class Remembering: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        var trail: Feedback!
        override func setup() { trail = makeFeedback() }
        override func draw() {
            background(Color(white: 0.02))
            withFeedback(trail) { prev in
                withState {
                    translate(center)
                    rotate(0.1)
                    scale(0.96)
                    translate(-width / 2, -height / 2)
                    tint(Color(white: 1, alpha: 0.9))
                    drawImage(prev, 0, 0)
                }
                noStroke()
                fill(Color(hue: (time * 0.2).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 1))
                drawCircle(60 + sin(time * 2) * 30, 60 + cos(time * 3) * 30, 8)
            }
            drawImage(trail.image, 0, 0)
        }
    }

    /// A field that evolves: reaction-diffusion seeded once, recolored.
    final class Living: Sketch {
        override var canvasSize: CanvasSize { .square(96) }
        var field: SimField!
        override func setup() { field = makeSimField(.reactionDiffusion(feed: 0.037, kill: 0.06), scale: 0.5) }
        override func draw() {
            background(.black)
            withField(field) {
                noStroke(); fill(.white)
                if frameCount < 3 { drawCircle(48, 48, 8) }
            }
            drawImage(field.filtered(.gradientMap(.magma)).image, 0, 0)
        }
    }

    /// Whole-frame filters after the canvas.
    final class Posted: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(.white)
            noStroke()
            fill(Color(hex: 0x102030))
            drawCircle(40 + Double(frameCount) * 2, 60, 24)
            postProcess(.invert(amount: 1))
            postProcess(.vignette(amount: 0.8, radius: 0.5, softness: 0.5))
        }
    }

    /// A blurred layer under a bloomed one, the two passes the page owns.
    final class Blurred: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(Color(white: 0.05))
            let soft = makeRenderTarget()
            withTarget(soft) { noStroke(); fill(Color(hex: 0x3A86FF)); drawCircle(50, 60, 24) }
            drawImage(soft.filtered(.gaussianBlur(radius: 6 + sin(time) * 2)).image, 0, 0)
            let bright = makeRenderTarget()
            withTarget(bright) { noStroke(); fill(Color(hex: 0xFFC857)); drawStar(center: Vector2(80, 60), outerRadius: 22, innerRadius: 10, points: 5) }
            withState {
                blendMode(.add)
                drawImage(bright.filtered(.bloom(threshold: 0.4, amount: 1.6, radius: 10)).image, 0, 0)
            }
        }
    }

    final class Diffused: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        override func draw() {
            background(.white)
            let layer = makeRenderTarget()
            withTarget(layer) { noStroke(); fill(.black); drawCircle(60, 60, 20) }
            drawImage(layer.filtered(.diffuse()).image, 0, 0)
        }
    }

    final class Flowing: Sketch {
        override var canvasSize: CanvasSize { .square(120) }
        var fluid: SimField!
        override func setup() { fluid = makeSimField(.fluid(curl: 30), scale: 0.5) }
        override func draw() {
            withField(fluid, force: Vector2(2, 0)) { noStroke(); fill(.orange); drawCircle(60, 60, 10) }
            drawImage(fluid.image, 0, 0)
        }
    }

    // MARK: The recorder

    @Test func aGeneratorIsOnePassAndItsPhaseMoves() throws {
        let recording = try OllinApp.recordWebFrames(of: Generated(), frames: 8, fps: 30)
        let frame = recording.frames[2]
        #expect(frame.graph.layers.count == 1)
        guard case let .generator(node) = frame.graph.layers[0].kind else { Issue.record("not a generator"); return }
        #expect(node.fragment == "ollin_gen_cellular")
        #expect(node.paramRows == 4)
        #expect(node.inputs.isEmpty)
        // The canvas composites the layer as one quad; no shapes.
        #expect(frame.graph.canvas == [.image(source: .layer(0), quad: 0, count: 1, blend: 0)])
        #expect(frame.graph.instanceCount == 0 && frame.graph.quadCount == 1)
        #expect(frame.vector.count == WebQuad.floats + 16)
        // The phase (params[0].w, the fourth float of the rows) is the one thing
        // that moves, so the cast is stable and that column samples.
        let track = WebTrack(recording)
        #expect(track.stable)
        #expect(WebTrack.ints(track.varying) == [UInt32(WebQuad.floats + 3)])
        #expect(track.meta.contains("\"graph\":{"))
        #expect(track.meta.contains("\"f\":\"ollin_gen_cellular\""))
        #expect(track.passCount == 1)
    }

    @Test func aFilterChainReadsItsInputsInOrder() throws {
        let recording = try OllinApp.recordWebFrames(of: Filtered(), frames: 3, fps: 30)
        let g = recording.frames[0].graph
        #expect(g.layers.count == 3)
        guard case let .geometry(clear, items) = g.layers[0].kind else { Issue.record("layer 0 is not drawn"); return }
        #expect(clear.count == 4 && clear[3] == 1)
        #expect(items == [.shapes(start: 0, count: 16, blend: 0)])
        guard case let .filter(input1, swirl) = g.layers[1].kind else { Issue.record("layer 1 is not a filter"); return }
        #expect(input1 == 0 && swirl.fragment == "ollin_fx_swirl" && swirl.paramRows == 2)
        guard case let .filter(input2, grade) = g.layers[2].kind else { Issue.record("layer 2 is not a filter"); return }
        #expect(input2 == 1 && grade.fragment == "ollin_fx_color_grade")
        #expect(g.canvas == [.image(source: .layer(2), quad: 0, count: 1, blend: 0)])
        // Only the swirl's angle moves.
        let track = WebTrack(recording)
        #expect(track.stable)
        #expect(track.sampledColumns == 1)
    }

    @Test func aLookupTableTravelsOnce() throws {
        let recording = try OllinApp.recordWebFrames(of: Mapped(), frames: 2, fps: 30)
        #expect(recording.tables.count == 1)
        #expect(recording.tables[0].count == 256)
        guard case let .filter(_, node) = recording.frames[0].graph.layers[1].kind else { Issue.record("no filter"); return }
        #expect(node.inputs == [.layer(0), .table(0)])
        let track = WebTrack(recording)
        #expect(track.uniqueFrames == 1)
    }

    @Test func aCombineNamesItsBaseAndAux() throws {
        let recording = try OllinApp.recordWebFrames(of: Combined(), frames: 2, fps: 30)
        let g = recording.frames[0].graph
        #expect(g.layers.count == 5)
        guard case let .combine(base, aux, mix) = g.layers[3].kind else { Issue.record("layer 3 is not a combine"); return }
        #expect(base == 0 && aux == 1 && mix.fragment == "ollin_fx_mix")
        guard case let .combine(base2, aux2, mask) = g.layers[4].kind else { Issue.record("layer 4 is not a combine"); return }
        #expect(base2 == 3 && aux2 == 2 && mask.fragment == "ollin_fx_mask")
    }

    @Test func aUserShaderTravelsOnceWithItsRows() throws {
        let recording = try OllinApp.recordWebFrames(of: UserCombine(), frames: 3, fps: 30)
        #expect(recording.shaders.count == 1)
        #expect(recording.shaders[0].variant == 2)
        #expect(recording.shaders[0].source.contains("sampleAux(info, uv)"))
        guard case let .user(shader, inputs, _, rows) = recording.frames[0].graph.layers[2].kind else {
            Issue.record("layer 2 is not a user shader"); return
        }
        #expect(shader == 0 && inputs == [0, 1] && rows == 1)
        // The page compiles it as GLSL with the readers over the two layers.
        let glsl = try WebUserShaderGLSL.make(recording.shaders[0])
        #expect(glsl.contains("uniform sampler2D ollin_src1;"))
        #expect(glsl.contains("vec4 sampleAux(ShaderInfo info, vec2 p)"))
        #expect(glsl.contains("vec4 shade(vec2 uv, ShaderInfo info)"))
        #expect(glsl.contains("sample_(info, uv)"))
        #expect(!glsl.contains("float4"))
        // A chain compiles to a user shader too.
        let chained = try OllinApp.recordWebFrames(of: Chained(), frames: 2, fps: 30)
        #expect(chained.shaders.count == 1 && chained.shaders[0].variant == 0)
    }

    @Test func feedbackAndFieldsAreStateful() throws {
        let remembering = try OllinApp.recordWebFrames(of: Remembering(), frames: 4, fps: 30)
        #expect(remembering.isStateful)
        let g = remembering.frames[1].graph
        guard case let .feedback(_, items) = g.layers[0].kind else { Issue.record("layer 0 is not feedback"); return }
        #expect(g.layers[0].key == 0)
        #expect(items.count == 2)
        #expect(items[0] == .image(source: .previous(0), quad: 0, count: 1, blend: 0))
        if case .shapes = items[1] {} else { Issue.record("the new mark is missing") }
        #expect(WebTrack(remembering).meta.contains("\"stateful\":true"))

        let living = try OllinApp.recordWebFrames(of: Living(), frames: 4, fps: 30)
        guard case let .sim(sim, _, seeds) = living.frames[0].graph.layers[0].kind else { Issue.record("layer 0 is not a field"); return }
        #expect(sim.inject == "ollin_sim_inject" && sim.step == "ollin_sim_reaction_diffusion" && sim.substeps == 14)
        #expect(sim.rest == [1, 0, 0, 1] && sim.paramRows == 1)
        #expect(seeds.count == 1)
        // The seed stops after the third frame, so the cast changes.
        if case .sim(_, _, let later) = living.frames[3].graph.layers[0].kind { #expect(later.isEmpty) }
        #expect(living.frames[0].graph.layers[0].pixelWidth == 48)
    }

    @Test func wholeFrameFiltersFollowTheCanvas() throws {
        let recording = try OllinApp.recordWebFrames(of: Posted(), frames: 2, fps: 30)
        let g = recording.frames[0].graph
        #expect(g.layers.isEmpty)
        #expect(g.frameFilters.map(\.fragment) == ["ollin_fx_invert", "ollin_fx_vignette"])
        #expect(g.canvas == [.shapes(start: 0, count: 1, blend: 0)])
        #expect(g.paramFloats == 8)
    }

    @Test func refusesWhatThePageCannotRunAndNamesIt() throws {
        func refusal(_ sketch: Sketch, frames: Int = 2) -> WebExportRefusal? {
            do { _ = try OllinApp.recordWebFrames(of: sketch, frames: frames, fps: 30); return nil }
            catch let refusal as WebExportRefusal { return refusal }
            catch { return nil }
        }
        let diffused = try #require(refusal(Diffused()))
        #expect(diffused.call == "the diffuse filter")
        // A blur and a bloom are the page's own passes, so they cross.
        let blurred = try OllinApp.recordWebFrames(of: Blurred(), frames: 2, fps: 30)
        let kinds = blurred.frames[0].graph.layers.compactMap { layer -> String? in
            if case let .filter(_, node) = layer.kind { return node.fragment }
            return nil
        }
        #expect(kinds == [WebPassNode.blur, WebPassNode.bloom])
        #expect(Set(blurred.frames[0].graph.fragmentRows.keys) == Set(WebPassNode.bloomFragments))
        let flowing = try #require(refusal(Flowing()))
        #expect(flowing.call == "the fluid simulation")
        // A skip cannot stand in for the frames a state would have stepped.
        #expect(throws: WebExportRefusal.self) {
            try OllinApp.recordWebFrames(of: Remembering(), frames: 2, fps: 30, skipSeconds: 1)
        }
    }

    // MARK: The browser

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func everyKindOfPassPlaysWhatTheMacDrew() async throws {
        let cases: [(name: String, make: () -> Sketch, frames: Int, probe: Int)] = [
            ("Generated", { Generated() }, 8, 5),
            ("Filtered", { Filtered() }, 6, 3),
            ("Mapped", { Mapped() }, 2, 1),
            ("Combined", { Combined() }, 6, 4),
            ("UserGenerator", { UserGenerator() }, 4, 2),
            ("UserFilter", { UserFilter() }, 4, 3),
            ("UserCombine", { UserCombine() }, 4, 1),
            ("Chained", { Chained() }, 4, 2),
            ("Composed", { Composed() }, 6, 4),
            ("Remembering", { Remembering() }, 12, 11),
            ("Living", { Living() }, 16, 15),
            ("Posted", { Posted() }, 4, 2),
            ("Blurred and bloomed", { Blurred() }, 4, 2),
        ]
        var worst: [String] = []
        for c in cases {
            let recording = try OllinApp.recordWebFrames(of: c.make(), frames: c.frames, fps: 30)
            let page = try OllinApp.webPage(of: recording, form: .inline)
            let played = try await WebExportTests.pagePixels(page, frame: c.probe)
            let reference = try #require(OllinApp.image(of: c.make(), frame: c.probe, fps: 30))
            let difference = try WebExportTests.meanDifference(played, reference)
            print("web page against the Mac: \(c.name) frame \(c.probe), mean difference \(String(format: "%.3f", difference))")
            if difference >= Snapshot.tolerance { worst.append("\(c.name) frame \(c.probe): \(difference)") }
        }
        #expect(worst.isEmpty, Comment(rawValue: worst.joined(separator: "\n")))
    }

    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func theGateSeesAMissingPass() async throws {
        // A gate that cannot fail proves nothing: the filtered page against
        // the Mac's unfiltered layer must read as different.
        final class Plain: Sketch {
            override var canvasSize: CanvasSize { .square(160) }
            override func draw() {
                background(Color(hex: 0x0E1116))
                noStroke()
                let colors: [UInt32] = [0xFF5D73, 0xFFC857, 0x55D6BE, 0x8E7DBE]
                for r in 0 ..< 4 {
                    for c in 0 ..< 4 {
                        fill(Color(hex: colors[(r + c) % colors.count]))
                        drawCircle((Double(c) + 0.5) * 40, (Double(r) + 0.5) * 40, 14)
                    }
                }
            }
        }
        let recording = try OllinApp.recordWebFrames(of: Filtered(), frames: 4, fps: 30)
        let page = try OllinApp.webPage(of: recording, form: .inline)
        let played = try await WebExportTests.pagePixels(page, frame: 3)
        let unfiltered = try #require(OllinApp.image(of: Plain(), frame: 3, fps: 30))
        let difference = try WebExportTests.meanDifference(played, unfiltered)
        #expect(difference > Snapshot.tolerance, "mean difference \(difference)")
    }
}
