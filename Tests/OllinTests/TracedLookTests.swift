@testable import Ollin
import Testing
import CoreGraphics
import Foundation
import simd

/// A finish's look in the path-traced export: the highlight, the cel bands, the
/// warm-cool ramp, the rainbow sheen, the flakes, the glow through the body, the
/// rim, and the grating's rainbow.
///
/// The first statement is raster parity. The lit fragment paints each of these by
/// a formula of its own and a sketch is tuned on that picture, so the trace draws
/// the same formula wherever the camera sees the surface. A sphere alone under one
/// light has nothing to bounce light off and nothing to shadow it, so its traced
/// frame and its window frame are the same picture, and the table below holds each
/// finish to its twin within a tolerance measured for it.
///
/// The second is what keeps a look from feeding a room: it is drawn where the
/// camera sees the surface (head on, through glass, in a reflection) and nowhere
/// else, so a stylized surface lights its neighbors exactly as a matte one of its
/// color does.
@Suite(.serialized)
@MainActor
struct TracedLookTests {

    // MARK: - One sphere, one light: the parity table

    /// Where the light stands for a probe.
    enum Rig: Sendable {
        /// One directional light from the upper front right, over a dim ambient.
        case key
        /// The same light from behind the sphere, for what shows against the light.
        case back
        /// One rectangle panel, for the terms a panel has a form of its own for.
        case panel
        /// The key light with no ambient under it, for a metal: with no environment
        /// the lit fragment gives a metal's body none of the flat ambient, and the
        /// trace reflects it, which is a difference of the body and not of the look.
        case alone
    }

    /// One sphere in one finish under one rig.
    final class Probe: Sketch {
        var finish = Material()
        var rig = Rig.key

        override var canvasSize: CanvasSize { .square(256) }

        static func make(_ finish: Material, _ rig: Rig) -> Probe {
            let p = Probe()
            p.finish = finish
            p.rig = rig
            return p
        }

        override func draw() {
            background(.black)
            camera(Camera3D(eye: Vector3(0, 0, 4), target: .zero))
            ambientLight(Color(white: rig == .alone ? 0 : 0.1))
            switch rig {
            case .key, .alone:
                directionalLight(Color(white: 0.8), direction: Vector3(-1, -1, -1))
            case .back:
                directionalLight(Color(white: 0.8), direction: Vector3(-0.5, -0.4, 1))
            case .panel:
                rectangleLight(Color(white: 1), at: Vector3(1.8, 1.8, 2.2),
                               direction: Vector3(-1.8, -1.8, -2.2), width: 3.2, height: 3.2,
                               intensity: 1.5)
            }
            fill(Color(red: 0.8, green: 0.35, blue: 0.2))
            material(finish)
            drawSphere(radius: 1.2)
        }
    }

    /// One row of the table: a finish, the rig that shows it, and how far its traced
    /// frame may stand from its window frame, per pixel and by region, in 8-bit levels.
    struct Row: Sendable, CustomTestStringConvertible {
        var name: String
        var finish: Material
        var rig: Rig
        var pixel: Double
        var region: Double
        var testDescription: String { name }
    }

    /// The tolerances were measured on 2026-11-11 at 64 samples and set at about
    /// twice the reading. Under the key light every look read within 0.30 a pixel and
    /// 0.14 by region of its twin (the widest: the toon bands' edges and the
    /// hologram's rainbow). Under the panel the matte body under a look is sampled,
    /// so a pixel carries its grain (1.85 on the plain matte control, 1.5 on the
    /// rest) and a region reads within 0.23. The flakes are the one look whose
    /// detail is finer than a pixel here: the window draws one flake a pixel and the
    /// trace averages the flakes a pixel covers, so they agree by region alone
    /// (glitter 7.66 a pixel and 2.06 by region, sequins 1.31 and 0.46).
    nonisolated static let table: [Row] = [
        Row(name: "matte", finish: .matte, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "clay", finish: .clay, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "rubber", finish: .rubber, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "plastic", finish: .plastic, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "ceramic", finish: .ceramic, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "glossy", finish: .glossy, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "polished", finish: .polished, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "iridescent", finish: .iridescent, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "soap bubble", finish: .soapBubble, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "oil slick", finish: .oilSlick, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "beetle", finish: .beetle, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "a drifting film",
            finish: Material(specular: 0.6, specularSharpness: 80, iridescence: 0.9,
                             iridescenceScale: 1.4, iridescenceFlow: 0.6),
            rig: .key, pixel: 0.6, region: 0.3),
        Row(name: "glitter", finish: .glitter, rig: .key, pixel: 14, region: 4),
        Row(name: "sequin", finish: .sequin, rig: .key, pixel: 3, region: 1),
        Row(name: "velvet", finish: .velvet, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "jade", finish: .jade, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "wax", finish: .wax, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "jade against the light", finish: .jade, rig: .back, pixel: 0.5, region: 0.3),
        Row(name: "wax against the light", finish: .wax, rig: .back, pixel: 0.5, region: 0.3),
        Row(name: "velvet against the light", finish: .velvet, rig: .back, pixel: 0.5, region: 0.3),
        Row(name: "toon", finish: .toon, rig: .key, pixel: 0.6, region: 0.3),
        Row(name: "gooch", finish: .gooch, rig: .key, pixel: 0.5, region: 0.3),
        Row(name: "hologram", finish: .hologram, rig: .alone, pixel: 0.6, region: 0.3),
        Row(name: "matte under a panel", finish: .matte, rig: .panel, pixel: 3.5, region: 0.5),
        Row(name: "plastic under a panel", finish: .plastic, rig: .panel, pixel: 3.5, region: 0.5),
        Row(name: "polished under a panel", finish: .polished, rig: .panel, pixel: 3.5, region: 0.5),
        Row(name: "toon under a panel", finish: .toon, rig: .panel, pixel: 0.5, region: 0.3),
        Row(name: "gooch under a panel", finish: .gooch, rig: .panel, pixel: 0.5, region: 0.3),
        Row(name: "jade under a panel", finish: .jade, rig: .panel, pixel: 3.5, region: 0.5),
        Row(name: "iridescent under a panel", finish: .iridescent, rig: .panel, pixel: 3.5, region: 0.5)
    ]

    private func traced(_ sketch: Sketch, samples: Int = 64) throws -> CGImage {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples, denoises: false)
        defer { OllinApp.pathTracedExport = nil }
        return try OllinApp.image(of: sketch, frame: 1)
    }

    private func window(_ sketch: Sketch) throws -> CGImage {
        OllinApp.pathTracedExport = nil
        return try OllinApp.image(of: sketch, frame: 1)
    }

    /// The pixels whose own ray meets a sphere at the origin, seen through a camera
    /// of the default lens on a square canvas, with the sphere's radius scaled by
    /// `scale`: under 1 leaves out the outline, which the window and the trace
    /// anti-alias two different ways, and over 1 takes the outline in with a margin.
    private func sphere(radius: Double, scale: Double, eye: SIMD3<Double>,
                        target: SIMD3<Double>, size: Int) -> [Bool] {
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(right, forward)
        let reach = tan(Double.pi / 6)
        let r = radius * scale
        var inside = [Bool](repeating: false, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let nx = (Double(x) + 0.5) / Double(size) * 2 - 1
                let ny = 1 - (Double(y) + 0.5) / Double(size) * 2
                let dir = simd_normalize(forward + right * (nx * reach) + up * (ny * reach))
                let along = simd_dot(-eye, dir)
                let off = simd_length(-eye - dir * along)
                inside[y * size + x] = along > 0 && off < r
            }
        }
        return inside
    }

    /// How far two frames stand apart over a set of pixels, in 8-bit levels: the
    /// mean difference per pixel, and the same after each frame is averaged over
    /// blocks of eight pixels, which is what reads a finish whose detail is finer
    /// than a pixel.
    private func distance(_ a: CGImage, _ b: CGImage, over inside: [Bool]) -> (pixel: Double, region: Double) {
        let pa = pixels(of: a), pb = pixels(of: b)
        let w = a.width
        var sum = 0.0, count = 0.0
        var blocks: [Int: (a: Double, b: Double, n: Double)] = [:]
        for i in inside.indices where inside[i] {
            let key = (i / w / 8) * 4096 + (i % w) / 8
            var block = blocks[key] ?? (0, 0, 0)
            for c in 0..<3 {
                let va = Double(pa[i * 4 + c]), vb = Double(pb[i * 4 + c])
                sum += abs(va - vb)
                block.a += va
                block.b += vb
            }
            block.n += 3
            count += 3
            blocks[key] = block
        }
        var regionSum = 0.0, regions = 0.0
        for block in blocks.values where block.n >= 96 {
            regionSum += abs(block.a - block.b) / block.n
            regions += 1
        }
        return (sum / max(count, 1), regionSum / max(regions, 1))
    }

    /// The mean of a frame over a set of pixels, all three channels.
    private func mean(_ image: CGImage, over inside: [Bool]) -> Double {
        let p = pixels(of: image)
        var sum = 0.0, count = 0.0
        for i in inside.indices where inside[i] {
            sum += Double(p[i * 4]) + Double(p[i * 4 + 1]) + Double(p[i * 4 + 2])
            count += 3
        }
        return sum / max(count, 1)
    }

    private var probeDisc: [Bool] {
        sphere(radius: 1.2, scale: 0.955, eye: SIMD3(0, 0, 4), target: .zero, size: 256)
    }

    @Test(.enabled(if: Snapshot.hasRaytracing), arguments: table)
    func aFinishTracesAsTheWindowDrawsIt(_ row: Row) throws {
        let t = try traced(Probe.make(row.finish, row.rig))
        let w = try window(Probe.make(row.finish, row.rig))
        let d = distance(t, w, over: probeDisc)
        #expect(d.pixel < row.pixel, "\(row.name): \(d.pixel) levels a pixel from its window twin, bound \(row.pixel)")
        #expect(d.region < row.region, "\(row.name): \(d.region) levels by region from its window twin, bound \(row.region)")
    }

    /// The table would hold as well if every finish drew nothing, in both
    /// pipelines. So each look is also read against the plain body under it: the
    /// traced frame of the finish stands well apart from the traced frame of a matte
    /// sphere of its color, which is what a finish with no look traces as.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func everyLookStandsApartFromThePlainBody() throws {
        let inside = probeDisc
        let plain = try traced(Probe.make(.matte, .key))
        let plainBack = try traced(Probe.make(.matte, .back))
        let plainPanel = try traced(Probe.make(.matte, .panel))
        let bare = try traced(Probe.make(Material(shading: .physicallyBased, metallic: 1, roughness: 0.3), .alone))
        let cases: [(String, Material, Rig, CGImage)] = [
            ("polished", .polished, .key, plain), ("iridescent", .iridescent, .key, plain),
            ("glitter", .glitter, .key, plain), ("velvet", .velvet, .key, plain),
            ("toon", .toon, .key, plain), ("gooch", .gooch, .key, plain),
            ("jade against the light", .jade, .back, plainBack),
            ("hologram", .hologram, .alone, bare),
            ("polished under a panel", .polished, .panel, plainPanel),
            ("toon under a panel", .toon, .panel, plainPanel)
        ]
        for (name, finish, rig, body) in cases {
            let d = distance(try traced(Probe.make(finish, rig)), body, over: inside)
            #expect(d.pixel > 1.5, "\(name) traces \(d.pixel) levels from its plain body: its look is not drawn")
        }
    }

    // MARK: - A ball on a floor: where a look is drawn, and where it is not

    /// A ball on a floor under the key light, with the things a look has to answer
    /// to placed around it.
    final class Stage: Sketch {
        enum Floor: Sendable { case matte, mirror }
        enum Extra: Sendable {
            case none
            /// A sheet of clear glass between the camera and the ball.
            case pane
            /// A block that shadows the ball's highlight from the key light.
            case shade
            /// A wall between the ball and a light behind it.
            case wall
        }
        var finish = Material()
        var floor = Floor.matte
        var extra = Extra.none
        var backlit = false
        /// A rectangle panel from the key light's side in place of the key light.
        var panel = false

        static let eye = SIMD3<Double>(0, 1.2, 5)
        static let target = SIMD3<Double>(0, -0.4, 0)

        override var canvasSize: CanvasSize { .square(256) }

        static func make(_ finish: Material, floor: Floor = .matte, extra: Extra = .none,
                         backlit: Bool = false, panel: Bool = false) -> Stage {
            let s = Stage()
            s.finish = finish
            s.floor = floor
            s.extra = extra
            s.backlit = backlit
            s.panel = panel
            return s
        }

        override func draw() {
            background(.black)
            camera(Camera3D(eye: Vector3(Stage.eye.x, Stage.eye.y, Stage.eye.z),
                            target: Vector3(Stage.target.x, Stage.target.y, Stage.target.z)))
            ambientLight(Color(white: 0.1))
            if panel {
                rectangleLight(Color(white: 1), at: Vector3(2.6, 2.6, 2.6),
                               direction: Vector3(-1, -1, -1), width: 2.4, height: 2.4,
                               intensity: 2.5)
            } else {
                directionalLight(Color(white: 0.8),
                                 direction: backlit ? Vector3(-0.5, -0.4, 1) : Vector3(-1, -1, -1))
            }
            withState {
                fill(Color(white: 0.8))
                material(floor == .mirror ? .metal(roughness: 0.06) : .matte)
                translate(0, -1.03, 0)
                drawBox(width: 14, height: 0.04, depth: 14)
            }
            switch extra {
            case .none:
                break
            case .pane:
                withState {
                    fill(.white)
                    material(.glass())
                    translate(0, 0.2, 2.2)
                    drawBox(width: 5, height: 5, depth: 0.02)
                }
            case .shade:
                withState {
                    fill(Color(white: 0.5))
                    material(.matte)
                    translate(1.46, 1.6, 2.0)
                    drawBox(width: 1.1, height: 1.1, depth: 1.1)
                }
            case .wall:
                withState {
                    fill(Color(white: 0.5))
                    material(.matte)
                    translate(1.5, 1.2, -3)
                    drawBox(width: 7, height: 7, depth: 0.2)
                }
            }
            fill(Color(red: 0.8, green: 0.35, blue: 0.2))
            material(finish)
            drawSphere(radius: 1)
        }
    }

    private func ball(scale: Double) -> [Bool] {
        sphere(radius: 1, scale: scale, eye: Stage.eye, target: Stage.target, size: 256)
    }

    /// A finish by the name a parameterized test carries, with the plain body its
    /// frames are read against: the matte finish for the older shading models, and
    /// for the hologram the bare metal under its grating.
    private func finish(named name: String) throws -> (styled: Material, plain: Material) {
        let finishes: [String: (Material, Material)] = [
            "polished": (.polished, .matte), "iridescent": (.iridescent, .matte),
            "glitter": (.glitter, .matte), "velvet": (.velvet, .matte), "jade": (.jade, .matte),
            "toon": (.toon, .matte), "gooch": (.gooch, .matte),
            "hologram": (.hologram, Material(shading: .physicallyBased, metallic: 1, roughness: 0.3))
        ]
        return try #require(finishes[name])
    }

    /// The transport statement, to the byte. Every pixel that does not look at the
    /// ball itself sees it only by light that has bounced off the matte floor, and
    /// there a ball in any finish is a matte ball of its color: the frames are the
    /// same bytes, shadow and color bleed included. The rim, the sheen, the flakes,
    /// and the ramp add light of their own where the camera sees them, so this is
    /// what holds a room of them from feeding itself.
    @Test(.enabled(if: Snapshot.hasRaytracing),
          arguments: ["polished", "iridescent", "glitter", "velvet", "jade", "toon", "gooch", "hologram"])
    func aStylizedSurfaceLightsItsNeighborsAsAMatteOneDoes(_ name: String) throws {
        let pair = try finish(named: name)
        let styled = pixels(of: try traced(Stage.make(pair.styled), samples: 16))
        let plain = pixels(of: try traced(Stage.make(pair.plain), samples: 16))
        let onBall = ball(scale: 1.06)
        var differing = 0, seen = 0, apart = 0
        for i in onBall.indices {
            let same = styled[i * 4] == plain[i * 4] && styled[i * 4 + 1] == plain[i * 4 + 1]
                && styled[i * 4 + 2] == plain[i * 4 + 2]
            if onBall[i] {
                if !same { apart += 1 }
            } else {
                seen += 1
                if !same { differing += 1 }
            }
        }
        #expect(seen > 30_000)
        #expect(differing == 0, "\(name): \(differing) pixels off the ball differ from the matte ball's frame")
        // A polished highlight is a small spot; every other look covers the ball.
        #expect(apart > (name == "polished" ? 60 : 500),
                "\(name): the ball itself reads as its plain body (\(apart) pixels differ)")
    }

    /// A look shows in a mirror. On a polished floor the ball's reflection is seen
    /// by a path that has not scattered off a matte lobe, so the rim, the bands,
    /// and the sheen are in it, as they are in the window's traced reflections.
    @Test(.enabled(if: Snapshot.hasRaytracing), arguments: ["velvet", "toon", "iridescent"])
    func aLookShowsInAMirror(_ name: String) throws {
        let pair = try finish(named: name)
        let styled = pixels(of: try traced(Stage.make(pair.styled, floor: .mirror)))
        let plain = pixels(of: try traced(Stage.make(pair.plain, floor: .mirror)))
        let onBall = ball(scale: 1.06)
        var reflected = 0
        for i in onBall.indices where !onBall[i] {
            let apart = abs(Int(styled[i * 4]) - Int(plain[i * 4]))
                + abs(Int(styled[i * 4 + 1]) - Int(plain[i * 4 + 1]))
                + abs(Int(styled[i * 4 + 2]) - Int(plain[i * 4 + 2]))
            if apart > 24 { reflected += 1 }
        }
        #expect(reflected > 300, "\(name): \(reflected) pixels of the mirror show the look")
    }

    /// A look shows through glass: a clear sheet in front of the ball takes its own
    /// few percent off the picture and leaves the look in it.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aLookShowsThroughGlass() throws {
        let onBall = ball(scale: 0.94)
        let bare = distance(try traced(Stage.make(.velvet)), try traced(Stage.make(.matte)), over: onBall)
        let paned = distance(try traced(Stage.make(.velvet, extra: .pane)),
                             try traced(Stage.make(.matte, extra: .pane)), over: onBall)
        #expect(bare.pixel > 10, "the rim alone reads \(bare.pixel) levels over the matte ball")
        #expect(paned.pixel > 0.75 * bare.pixel,
                "behind the sheet the rim reads \(paned.pixel) levels, \(bare.pixel) without it")
    }

    /// A highlight is shadowed. The window draws it wherever the light's direction
    /// says, and the trace asks whether the light arrives: a block between the key
    /// light and the highlight takes it away, and the spot falls to the body in
    /// shadow.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func aHighlightIsShadowed() throws {
        let lit = try traced(Stage.make(.polished))
        let shaded = try traced(Stage.make(.polished, extra: .shade))
        let patch = brightestPatch(of: lit)
        let before = mean(lit, over: patch), after = mean(shaded, over: patch)
        #expect(before > 200, "the highlight reads \(before)")
        #expect(after < 90, "under the block the highlight still reads \(after) (\(before) lit)")
    }

    /// The five-pixel square of the ball that reads brightest in a frame: the
    /// highlight, on a finish that has one.
    private func brightestPatch(of image: CGImage) -> [Bool] {
        let p = pixels(of: image)
        let onBall = ball(scale: 0.9)
        var best = (value: 0, x: 0, y: 0)
        for y in 2..<254 {
            for x in 2..<254 where onBall[y * 256 + x] {
                var v = 0
                for dy in -2...2 {
                    for dx in -2...2 { v += Int(p[((y + dy) * 256 + x + dx) * 4 + 1]) }
                }
                if v > best.value { best = (v, x, y) }
            }
        }
        var patch = [Bool](repeating: false, count: 256 * 256)
        for dy in -2...2 {
            for dx in -2...2 { patch[(best.y + dy) * 256 + best.x + dx] = true }
        }
        return patch
    }

    /// Under a panel the cel band and the highlight are the panel's whole integrals,
    /// the window's own numbers, and the traced ray says how much of the panel the
    /// surface sees: a block in front of the panel dims both where it stands in the
    /// way.
    @Test(.enabled(if: Snapshot.hasRaytracing), arguments: ["polished", "toon"])
    func aPanelsBandAndHighlightAreShadowed(_ name: String) throws {
        let finish = try finish(named: name).styled
        let lit = try traced(Stage.make(finish, panel: true))
        let shaded = try traced(Stage.make(finish, extra: .shade, panel: true))
        let patch = brightestPatch(of: lit)
        let before = mean(lit, over: patch), after = mean(shaded, over: patch)
        #expect(after < before - 25, "\(name): behind the block the patch reads \(after), \(before) lit")
    }

    /// The glow through a body passes the body and stops at anything else. Against
    /// the light a jade ball glows at its edges (the table holds that to the window,
    /// which draws it with no shadow at all); a wall between the ball and the light
    /// puts the glow out, leaving the frame of the same ball without its glow behind
    /// the same wall.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theGlowStopsAtAnotherBody() throws {
        let onBall = ball(scale: 0.94)
        // The plain twin keeps jade's highlight, so what is left is the glow alone.
        let jade = Material.jade
        let noGlow = Material(specular: jade.specular, specularSharpness: jade.specularSharpness)
        let lit = distance(try traced(Stage.make(.jade, backlit: true)),
                           try traced(Stage.make(noGlow, backlit: true)), over: onBall)
        let walled = distance(try traced(Stage.make(.jade, extra: .wall, backlit: true)),
                              try traced(Stage.make(noGlow, extra: .wall, backlit: true)), over: onBall)
        #expect(lit.pixel > 2, "against the light the glow reads \(lit.pixel) levels")
        #expect(walled.pixel < 0.25, "behind a wall the glow still reads \(walled.pixel) levels")
    }

    // MARK: - What a look leaves alone

    /// A sphere in a uniform field with no light in the frame.
    final class Furnace: Sketch {
        var finish = Material()
        override var canvasSize: CanvasSize { .square(256) }
        static func make(_ finish: Material) -> Furnace {
            let f = Furnace()
            f.finish = finish
            return f
        }
        override func draw() {
            background(.black)
            camera(Camera3D(eye: Vector3(0, 0, 4), target: .zero))
            ambientLight(Color(white: 0.5))
            fill(.white)
            material(finish)
            drawSphere(radius: 1.2)
        }
    }

    /// The furnace still holds for the looks that answer to a light and nothing
    /// else. A highlight, a cel band, and the glow through a body are drawn from
    /// the light list, so with no light in the frame a polished, a toon, or a jade
    /// sphere in a uniform field is the white matte sphere, and reads the field.
    @Test(.enabled(if: Snapshot.hasRaytracing), arguments: ["polished", "toon", "jade"])
    func aLookThatAnswersToALightKeepsTheFurnace(_ name: String) throws {
        let image = try traced(Furnace.make(try finish(named: name).styled), samples: 96)
        let inside = sphere(radius: 1.2, scale: 0.7, eye: SIMD3(0, 0, 4), target: .zero, size: 256)
        let m = mean(image, over: inside)
        #expect(abs(m - 127.5) < 3, "\(name) in the furnace reads \(m), the field is 127.5")
    }

    /// The same command renders the same bytes with every look in the frame.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theLooksAreDeterministic() throws {
        for finish in [Material.glitter, .iridescent, .toon, .jade, .hologram] {
            let a = pixels(of: try traced(Stage.make(finish, floor: .mirror), samples: 16))
            let b = pixels(of: try traced(Stage.make(finish, floor: .mirror), samples: 16))
            #expect(a == b)
        }
    }
}
