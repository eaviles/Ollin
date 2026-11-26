import CoreGraphics
import Foundation
import OllinWebGate
import Testing
@testable import Ollin

/// Invariants of the effect chain and the layers: what a filter, a blend, a
/// combine, a feedback loop, a field, and a layer must do whatever their
/// implementation. A filter at the setting that asks for none of its effect is
/// its input; a blur moves light and makes none; a glow never darkens; a blend
/// mode is its arithmetic; a layer holds what the canvas would have drawn.
///
/// Every reading is the frame in linear light, taken before the present pass
/// tone-maps, dithers, and quantizes it: half-float components, premultiplied
/// by coverage, with the canvas cleared to nothing so a layer's own alpha is
/// the frame's. A statement is read against an analytic value or a twin render.
///
/// A statement that fell is pinned where it fell: a `withKnownIssue` holding
/// the measurement and its date, scoped by a plain `if` to the cases that
/// fall, so the day a fix lands the pin fails and is removed. One trap in
/// writing these: `drawRect` spills its edge ramp into the neighboring texels,
/// so a mask of exactly one texel is drawn as a polygon.
@Suite(.enabled(if: Snapshot.hasMetal))
@MainActor
struct EffectInvariantTests {

    // MARK: Support

    /// A frame in linear light: red, green, blue premultiplied, then coverage.
    struct Frame {
        let width: Int
        let height: Int
        let rgba: [Float]

        func at(_ x: Int, _ y: Int) -> SIMD4<Double> {
            let i = (y * width + x) * 4
            return SIMD4(Double(rgba[i]), Double(rgba[i + 1]), Double(rgba[i + 2]), Double(rgba[i + 3]))
        }
        func value(_ x: Int, _ y: Int, _ c: Int = 0) -> Double { Double(rgba[(y * width + x) * 4 + c]) }

        /// Channel `c` summed over a box (the whole frame by default).
        func sum(_ c: Int = 0, x: Range<Int>? = nil, y: Range<Int>? = nil) -> Double {
            var total = 0.0
            for py in y ?? 0..<height { for px in x ?? 0..<width { total += value(px, py, c) } }
            return total
        }

        /// The largest difference from `other` in any channel, and where.
        func worst(against other: Frame, x: Range<Int>? = nil, y: Range<Int>? = nil) -> (by: Double, x: Int, y: Int, channel: Int) {
            var out = (by: 0.0, x: 0, y: 0, channel: 0)
            for py in y ?? 0..<height { for px in x ?? 0..<width { for c in 0..<4 {
                let d = abs(value(px, py, c) - other.value(px, py, c))
                if d > out.by || d.isNaN { out = (d.isNaN ? .infinity : d, px, py, c) }
            } } }
            return out
        }

        /// The mean difference from `other` over every channel.
        func mean(against other: Frame) -> Double {
            var total = 0.0
            for i in rgba.indices { total += abs(Double(rgba[i]) - Double(other.rgba[i])) }
            return total / Double(rgba.count)
        }
    }

    /// A sketch drawn by closures, still by default.
    final class Probe: Sketch {
        var side = 96
        var wide = 0
        var holds = true
        var prepare: @MainActor (Probe) -> Void = { _ in }
        var body: @MainActor (Probe) -> Void = { _ in }
        var feedback: Feedback?
        var field: SimField?
        var accumulator: Accumulator?
        var layer: RenderTarget?
        override var canvasSize: CanvasSize { wide > 0 ? .size(wide, side) : .square(side) }
        override func setup() {
            if holds { noLoop() }
            prepare(self)
        }
        override func draw() { body(self) }
    }

    static func render(_ probe: Probe, frame: Int = 0, scale: Int = 1) throws -> Frame {
        let renderer = try OllinApp.headlessRenderer(for: probe)
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        renderer.capturesLinearFrame = true
        if scale != 1 { renderer.renderScale = scale }
        _ = try OllinApp.renderImage(of: probe, frame: frame, fps: 60, renderer: renderer)
        let linear = try #require(renderer.lastLinearFrame)
        let count = linear.width * linear.height
        let halfs = linear.color.contents().bindMemory(to: Float16.self, capacity: count * 4)
        var rgba = [Float](repeating: 0, count: count * 4)
        for i in 0 ..< count * 4 { rgba[i] = Float(halfs[i]) }
        return Frame(width: linear.width, height: linear.height, rgba: rgba)
    }

    /// One still frame of `body` on a square canvas of `side` pixels.
    static func render(side: Int = 96, wide: Int = 0, scale: Int = 1,
                       _ body: @escaping @MainActor (Probe) -> Void) throws -> Frame {
        let probe = Probe()
        probe.side = side; probe.wide = wide; probe.body = body
        return try render(probe, scale: scale)
    }

    /// A picture with flats of every hue, light past white, a half-transparent
    /// disc, an opaque one, a thin line, and bare layer between them. Drawn into
    /// whatever target is current, on a 96-pixel canvas.
    static func picture(_ s: Sketch) {
        s.noStroke()
        for i in 0 ..< 8 {
            s.fill(Color(hue: Double(i) / 8, saturation: 0.8, brightness: 0.35 + 0.08 * Double(i)))
            s.drawRect(Double(i) * 12, 0, 12, 26)
        }
        s.fill(Color(linear: 3.0, green: 1.6, blue: 0.4))
        s.drawRect(8, 34, 24, 18)
        s.fill(Color(red: 0.2, green: 0.7, blue: 0.9, alpha: 0.5))
        s.drawCircle(64, 56, 19)
        s.fill(.white)
        s.drawCircle(28, 74, 9)
        s.stroke(.white)
        s.strokeWeight(1.5)
        s.drawLine(4, 91, 92, 85)
        s.noStroke()
    }

    /// The picture in a layer, drawn back through `filter` over a cleared canvas.
    static func filtered(_ filter: Filter?, layerScale: Double = 1) throws -> Frame {
        try render { s in
            s.background(.clear)
            let layer = layerScale == 1 ? s.makeRenderTarget() : s.makeRenderTarget(scale: layerScale)
            s.withTarget(layer) { picture(s) }
            s.drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
        }
    }

    private static var plainPicture: Frame?
    static func plain() throws -> Frame {
        if let known = plainPicture { return known }
        let frame = try filtered(nil)
        plainPicture = frame
        return frame
    }

    /// A pin that reads its measurement into the record: the house form, a plain
    /// `if` around `withKnownIssue`, scoped to the cases that fall.
    private func pinned(_ reason: Comment, when active: Bool = true, _ body: () throws -> Void) throws {
        if active { withKnownIssue(reason) { try body() } } else { try body() }
    }

    private func describe(_ w: (by: Double, x: Int, y: Int, channel: Int)) -> String {
        String(format: "%.6f at (%d, %d) channel %d", w.by, w.x, w.y, w.channel)
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.5f", v) }
    private static func fmt(_ v: SIMD4<Double>) -> String { "(\(fmt(v.x)), \(fmt(v.y)), \(fmt(v.z)), \(fmt(v.w)))" }
    private func fmt(_ v: Double) -> String { Self.fmt(v) }
    private func fmt(_ v: SIMD4<Double>) -> String { Self.fmt(v) }

    /// A flat layer of one color through `filter`, over a cleared canvas.
    private func flat(_ side: Int = 64, _ color: Color, _ filter: Filter) throws -> Frame {
        try Self.render(side: side) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            s.withTarget(layer) { s.background(color) }
            s.drawImage(layer.filtered(filter).image, 0, 0)
        }
    }

    private func mean(_ f: Frame) -> SIMD4<Double> {
        var m = SIMD4<Double>(repeating: 0)
        for y in 0..<f.height { for x in 0..<f.width { m += f.at(x, y) } }
        return m / Double(f.width * f.height)
    }

    /// A white disc in a layer through `filter`, drawn back at canvas size.
    static func disc(side: Int = 128, wide: Int = 0, radius: Double = 10, color: Color = .white, filter: Filter?,
                     layerScale: Double = 1, scale: Int = 1) throws -> Frame {
        let w = Double(wide > 0 ? wide : side), h = Double(side)
        return try render(side: side, wide: wide, scale: scale) { s in
            s.background(.clear)
            let layer = layerScale == 1 ? s.makeRenderTarget() : s.makeRenderTarget(scale: layerScale)
            s.withTarget(layer) {
                s.noStroke(); s.fill(color)
                s.drawCircle(w / 2 + (wide > 0 ? 0 : 0.3), h / 2 - (wide > 0 ? 0 : 0.2), radius)
            }
            let shown = filter.map { layer.filtered($0) } ?? layer
            s.drawImage(shown.image, 0, 0, w, h)
        }
    }

    /// The sum of a channel and its variance along each axis about its centroid.
    static func spread(_ f: Frame, _ c: Int = 3) -> (sum: Double, varX: Double, varY: Double) {
        var sum = 0.0, mx = 0.0, my = 0.0
        for y in 0..<f.height { for x in 0..<f.width {
            let v = f.value(x, y, c); sum += v; mx += v * Double(x); my += v * Double(y)
        } }
        mx /= sum; my /= sum
        var vx = 0.0, vy = 0.0
        for y in 0..<f.height { for x in 0..<f.width {
            let v = f.value(x, y, c)
            vx += v * (Double(x) - mx) * (Double(x) - mx); vy += v * (Double(y) - my) * (Double(y) - my)
        } }
        return (sum, vx / sum, vy / sum)
    }

    struct Named: Sendable, CustomTestStringConvertible {
        let name: String
        let filter: Filter
        var testDescription: String { name }
    }

    // MARK: A layer

    /// A drawing made in a canvas-sized layer and drawn back is the drawing made
    /// on the canvas: over nothing, over its own ground, and through a second
    /// layer. Not within anti-aliasing: the same numbers.
    @Test func aLayerHoldsWhatTheCanvasWouldDraw() throws {
        let plain = try Self.plain()
        let direct = try Self.render { s in s.background(.clear); Self.picture(s) }
        #expect(direct.worst(against: plain).by == 0, "over nothing: \(describe(direct.worst(against: plain)))")
        let ground = Color(white: 0.3)
        let onCanvas = try Self.render { s in s.background(ground); Self.picture(s) }
        let inLayer = try Self.render { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            s.withTarget(layer) { s.background(ground); Self.picture(s) }
            s.drawImage(layer.image, 0, 0)
        }
        #expect(onCanvas.worst(against: inLayer).by == 0, "over a ground: \(describe(onCanvas.worst(against: inLayer)))")
        let nested = try Self.render { s in
            s.background(.clear)
            let inner = s.makeRenderTarget()
            s.withTarget(inner) { Self.picture(s) }
            let outer = s.makeRenderTarget()
            s.withTarget(outer) { s.drawImage(inner.image, 0, 0) }
            s.drawImage(outer.image, 0, 0)
        }
        #expect(nested.worst(against: plain).by == 0, "through two layers: \(describe(nested.worst(against: plain)))")
    }

    /// Where a layer holds nothing, drawing it changes nothing, under every mode.
    @Test(arguments: BlendMode.allCases)
    func anEmptyAreaOfALayerLeavesTheGround(mode: BlendMode) throws {
        let f = try Self.render(side: 32) { s in
            s.background(Color(linear: 0.2, green: 0.5, blue: 0.7))
            let top = s.makeRenderTarget()
            s.withTarget(top) { s.noStroke(); s.fill(Color(linear: 0.6, green: 0.3, blue: 0.1)); s.drawRect(0, 0, 16, 32) }
            s.blendMode(mode)
            s.drawImage(top.image, 0, 0)
        }
        let beside = f.at(24, 16)
        #expect(abs(beside.x - 0.2) < 0.001 && abs(beside.y - 0.5) < 0.001 && abs(beside.z - 0.7) < 0.001 && beside.w == 1,
                "\(mode): beside the layer's mark the ground reads \(fmt(beside))")
    }

    /// An opaque layer drawn over an opaque ground under a mode is the mode's
    /// arithmetic in linear light.
    @Test(arguments: BlendMode.allCases)
    func aLayerUnderAModeIsItsArithmetic(mode: BlendMode) throws {
        let s0 = SIMD3(0.6, 0.3, 0.1), d0 = SIMD3(0.2, 0.5, 0.7)
        let f = try Self.render(side: 32) { s in
            s.background(Color(linear: d0))
            let top = s.makeRenderTarget()
            s.withTarget(top) { s.background(Color(linear: s0)) }
            s.blendMode(mode)
            s.drawImage(top.image, 0, 0)
        }
        let want: SIMD3<Double>
        switch mode {
        case .normal: want = s0
        case .add: want = d0 + s0
        case .subtract: want = d0 - s0
        case .multiply: want = d0 * s0
        case .screen: want = d0 + s0 - d0 * s0
        case .lightest: want = pointwiseMax(d0, s0)
        case .darkest: want = pointwiseMin(d0, s0)
        }
        let got = f.at(16, 16)
        for c in 0..<3 { #expect(abs(got[c] - want[c]) < 0.002, "\(mode) channel \(c): \(got[c]) where the arithmetic gives \(want[c])") }
    }

    /// A surface's alpha is how much of each pixel is covered, under every mode:
    /// over an opaque ground it stays 1, and over nothing a mode that lightens
    /// covers as an ordinary shape does (two half-clear marks cover three
    /// quarters) while a mode that darkens adds no coverage at all.
    @Test(arguments: [BlendMode.add, .subtract, .screen, .lightest, .multiply, .darkest], [true, false])
    func aLayersAlphaStaysCoverage(mode: BlendMode, grounded: Bool) throws {
        let f = try Self.render(side: 32) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            s.withTarget(layer) {
                if grounded { s.background(Color(linear: 0.1, green: 0.1, blue: 0.1)) }
                s.noStroke(); s.blendMode(mode); s.fill(Color(linear: 0.3, green: 0.3, blue: 0.3, alpha: 0.5))
                s.drawRect(8, 8, 16, 16); s.drawRect(12, 12, 8, 8)
            }
            s.drawImage(layer.image, 0, 0)
        }
        let alpha = f.value(16, 16, 3)
        let lightens = mode == .add || mode == .screen || mode == .lightest
        let want = grounded ? 1.0 : (lightens ? 0.75 : 0.0)
        #expect(abs(alpha - want) < 0.001, "\(mode), \(grounded ? "over a ground" : "over nothing"): two half-clear marks left an alpha of \(alpha) where the coverage is \(want)")
    }

    /// Lights added in a layer are that layer's marks. Laid over a ground they
    /// cover it as their coverage says, never by more than all of it; and the
    /// layer added to the ground is the lights added to the ground.
    @Test(arguments: [1.0, 0.5])
    func lightsAddedInALayerAreTheLayersMarks(alpha: Double) throws {
        let ground = 0.8, light = 0.1 / alpha
        func lights(_ s: Probe) {
            s.noStroke(); s.blendMode(.add); s.fill(Color(linear: light, green: light, blue: light, alpha: alpha))
            for _ in 0..<3 { s.drawRect(8, 8, 16, 16) }
        }
        func shown(_ back: BlendMode?) throws -> SIMD4<Double> {
            try Self.render(side: 32) { s in
                s.background(Color(linear: ground, green: ground, blue: ground))
                guard let back else { lights(s); return }
                let layer = s.makeRenderTarget()
                s.withTarget(layer) { lights(s) }
                s.blendMode(back)
                s.drawImage(layer.image, 0, 0)
            }.at(16, 16)
        }
        let direct = try shown(nil), added = try shown(.add), laid = try shown(.normal)
        #expect(abs(direct.x - (ground + 0.3)) < 0.002, "three lights added to the ground read \(direct.x)")
        #expect(abs(added.x - direct.x) < 0.002, "the layer added back reads \(added.x), the lights added on the canvas \(direct.x)")
        let uncovered = pow(1 - alpha, 3)
        #expect(abs(laid.x - (0.3 + ground * uncovered)) < 0.002,
                "the layer laid over the ground reads \(laid.x): its light is 0.3 and it leaves \(uncovered) of the ground")
        #expect(abs(added.w - 1) < 0.001 && abs(laid.w - 1) < 0.001 && abs(direct.w - 1) < 0.001, "the canvas stays opaque")
    }

    /// A see-through `background` is the same color drawn over the whole surface.
    @Test(arguments: [true, false])
    func aSeeThroughBackgroundIsTheSameColorDrawn(inLayer: Bool) throws {
        let ink = Color(linear: 0.2, green: 0.5, blue: 0.7, alpha: 0.5)
        func shown(_ fill: @escaping @MainActor (Probe) -> Void) throws -> SIMD4<Double> {
            try Self.render(side: 32) { s in
                guard inLayer else { fill(s); return }
                s.background(.clear)
                let layer = s.makeRenderTarget()
                s.withTarget(layer) { fill(s) }
                s.drawImage(layer.image, 0, 0)
            }.at(16, 16)
        }
        let cleared = try shown { $0.background(ink) }
        let drawn = try shown { s in s.background(.clear); s.noStroke(); s.fill(ink); s.drawRect(0, 0, 32, 32) }
        for c in 0..<4 { #expect(abs(cleared[c] - drawn[c]) < 0.002, "channel \(c): cleared \(cleared[c]), drawn \(drawn[c])") }
    }

    /// The drawing paths a blend mode reaches, each laying one flat ink over
    /// the middle of a 32-pixel canvas.
    enum Laid: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case shape, fill, stroke, field, picture, paint, paintedShape, paintedStroke, solid
        var testDescription: String { rawValue }

        @MainActor func lay(_ ink: Color, mode: BlendMode, on s: Sketch) {
            switch self {
            case .shape:
                s.noStroke(); s.blendMode(mode); s.fill(ink); s.drawRect(8, 8, 16, 16)
            case .fill:
                s.noStroke(); s.blendMode(mode); s.fill(ink)
                s.drawPolygon([Vector2(x: 8, y: 8), Vector2(x: 24, y: 8), Vector2(x: 24, y: 24), Vector2(x: 8, y: 24)])
            case .stroke:
                s.noFill(); s.blendMode(mode); s.stroke(ink); s.strokeWeight(12)
                s.drawLine(4, 16, 28, 16)
            case .field:
                s.noStroke(); s.blendMode(mode); s.fill(ink)
                s.drawSDF(SDF.circle(radius: 9).at(16, 16))
            case .picture:
                let layer = s.makeRenderTarget()
                s.withTarget(layer) { s.noStroke(); s.fill(ink); s.drawRect(8, 8, 16, 16) }
                s.blendMode(mode)
                s.drawImage(layer.image, 0, 0)
            case .paint, .paintedShape, .paintedStroke:
                let source = String(format: "float4 shade(float2 uv, ShaderInfo info) { return float4(%.9f, %.9f, %.9f, %.9f); }",
                                    ink.red, ink.green, ink.blue, ink.alpha)
                let paint = Shader(source)
                s.blendMode(mode)
                if self == .paintedStroke {
                    s.noFill(); s.stroke(paint); s.strokeWeight(12); s.drawLine(4, 16, 28, 16)
                } else if self == .paintedShape {
                    s.noStroke(); s.fill(paint); s.drawRect(8, 8, 16, 16)
                } else {
                    s.noStroke(); s.fill(paint)
                    s.drawPolygon([Vector2(x: 8, y: 8), Vector2(x: 24, y: 8), Vector2(x: 24, y: 24), Vector2(x: 8, y: 24)])
                }
            case .solid:
                s.ortho(eye: Vector3(x: 0, y: 0, z: 10), height: 2)
                s.noStroke(); s.blendMode(mode); s.fill(ink); s.drawMesh(.box(size: 1))
            }
        }
    }

    /// A see-through ink under a mode is the mode's arithmetic weighted by the
    /// ink's coverage, on every drawing path: the ink's color times its alpha
    /// is what a multiply, a screen, a sum, and a difference work on; the
    /// lighter of two compares the ink as it lies over black, and the darker of
    /// two as it lies over white. The canvas stays opaque under all of them.
    @Test(arguments: BlendMode.allCases, Laid.allCases)
    func aSeeThroughInkUnderAModeIsItsWeightedArithmetic(mode: BlendMode, path: Laid) throws {
        let g = SIMD3(0.3, 0.5, 0.7)
        for (ink, a) in [(SIMD3(0.9, 0.6, 0.2), 0.5), (SIMD3(0.1, 0.4, 0.05), 0.9)] {
            let got = try Self.render(side: 32) { s in
                s.background(Color(linear: g))
                path.lay(Color(linear: ink.x, green: ink.y, blue: ink.z, alpha: a), mode: mode, on: s)
            }.at(16, 16)
            // A solid is shaded, so the color its alpha weights is the one it
            // shows opaque, read off the same solid over black.
            var c = ink
            if path == .solid {
                let lit = try Self.render(side: 32) { s in
                    s.background(.black)
                    path.lay(Color(linear: ink.x, green: ink.y, blue: ink.z), mode: .normal, on: s)
                }.at(16, 16)
                c = SIMD3(lit.x, lit.y, lit.z)
            }
            let weighted = c * a
            let want: SIMD3<Double>
            switch mode {
            case .normal: want = weighted + g * (1 - a)
            case .add: want = g + weighted
            case .subtract: want = g - weighted
            case .multiply: want = g * (SIMD3(repeating: 1 - a) + weighted)
            case .screen: want = g + weighted * (SIMD3(repeating: 1) - g)
            case .lightest: want = pointwiseMax(weighted, g)
            case .darkest: want = pointwiseMin(weighted + SIMD3(repeating: 1 - a), g)
            }
            for i in 0..<3 {
                #expect(abs(got[i] - want[i]) < 0.003, "\(mode), a \(path) at alpha \(a), channel \(i): \(got[i]) where the weighted arithmetic gives \(want[i])")
            }
            #expect(abs(got.w - 1) < 0.001, "\(mode), a \(path) at alpha \(a): the opaque canvas was left with an alpha of \(got.w)")
        }
    }

    /// An ink of no alpha changes nothing under any mode, whatever the ground
    /// holds: light past white, and less than none.
    @Test(arguments: BlendMode.allCases, [Laid.fill, .stroke, .shape, .picture])
    func anInkOfNoAlphaChangesNothing(mode: BlendMode, path: Laid) throws {
        func ground(_ s: Sketch) {
            s.background(Color(linear: 3.0, green: 0.5, blue: 0.1))
            s.noStroke(); s.blendMode(.subtract); s.fill(Color(linear: 0, green: 0, blue: 0.3)); s.drawRect(0, 0, 32, 32)
            s.blendMode(.normal)
        }
        let bare = try Self.render(side: 32) { s in ground(s) }
        let under = try Self.render(side: 32) { s in
            ground(s)
            path.lay(Color(linear: 0.4, green: 0.4, blue: 0.4, alpha: 0), mode: mode, on: s)
        }
        #expect(bare.value(16, 16, 2) < -0.15, "the ground's blue is below nothing: \(bare.value(16, 16, 2))")
        #expect(under.worst(against: bare).by == 0, "\(mode), a \(path): \(describe(under.worst(against: bare)))")
    }

    /// Over nothing, a mode that lightens leaves the shape itself, as the
    /// ordinary blend would have drawn it, and a mode that darkens leaves
    /// nothing: it works on what is already there.
    @Test(arguments: [BlendMode.add, .screen, .lightest, .subtract, .multiply, .darkest])
    func overNothingAModeLeavesTheShapeOrNothing(mode: BlendMode) throws {
        func layered(_ mode: BlendMode, over ground: Color) throws -> Frame {
            try Self.render(side: 64) { s in
                s.background(ground)
                let layer = s.makeRenderTarget()
                s.withTarget(layer) {
                    s.noStroke(); s.blendMode(mode)
                    s.fill(Color(linear: 0.2, green: 0.7, blue: 0.9, alpha: 0.5)); s.drawCircle(20.3, 22.6, 12)
                    s.fill(Color(linear: 0.9, green: 0.4, blue: 0.1)); s.drawRect(36, 30, 20, 24)
                    s.stroke(Color(linear: 0.5, green: 0.9, blue: 0.3)); s.strokeWeight(3); s.noFill(); s.drawLine(6, 56, 58, 8)
                }
                s.drawImage(layer.image, 0, 0)
            }
        }
        if mode == .add || mode == .screen || mode == .lightest {
            // The line crosses the two fills, and where marks overlap a mode is
            // its own arithmetic, so the twin is read where each mark lies alone.
            let got = try layered(mode, over: .clear), plain = try layered(.normal, over: .clear)
            for (x, y) in [(20, 22), (12, 20), (40, 48), (52, 50), (8, 54), (56, 10), (2, 2), (60, 60)] {
                let d = got.at(x, y) - plain.at(x, y)
                #expect(abs(d.x) < 0.001 && abs(d.y) < 0.001 && abs(d.z) < 0.001 && abs(d.w) < 0.001,
                        "\(mode) at (\(x), \(y)): \(fmt(got.at(x, y))) where the shape itself is \(fmt(plain.at(x, y)))")
            }
        } else {
            let ground = Color(linear: 0.6, green: 0.6, blue: 0.6)
            let got = try layered(mode, over: ground), bare = try Self.render(side: 64) { s in s.background(ground) }
            #expect(got.worst(against: bare).by == 0, "\(mode): \(describe(got.worst(against: bare)))")
        }
    }

    /// A wash multiplied over a layer tints what the layer holds, at every
    /// coverage, and leaves the bare layer bare.
    @Test func aMultiplyWashTintsWhatALayerHolds() throws {
        let wash = SIMD3(0.6, 0.3, 0.1)
        let f = try Self.render(side: 64) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            s.withTarget(layer) {
                s.noStroke(); s.fill(.white); s.drawCircle(32.3, 31.6, 16)
                s.blendMode(.multiply); s.fill(Color(linear: wash)); s.drawRect(0, 0, 64, 64)
            }
            s.drawImage(layer.filtered(.gaussianBlur(radius: 3)).image, 0, 0)
        }
        #expect(f.at(2, 2) == SIMD4(0, 0, 0, 0), "the bare corner reads \(fmt(f.at(2, 2)))")
        var worst = 0.0, read = 0
        for y in 0..<64 { for x in 0..<64 {
            let p = f.at(x, y)
            guard p.w > 0.02 else { continue }
            read += 1
            for c in 0..<3 { worst = max(worst, abs(p[c] / p.w - wash[c])) }
        } }
        #expect(read > 700 && worst < 0.01, "over \(read) covered pixels the color strays from the wash by \(worst)")
    }

    /// A shape's edge under a mode lies between the ground and the shape: along
    /// an anti-aliased rim and through a blurred layer's skirt, no pixel is
    /// brighter or darker than both, and none opens a hole in the canvas.
    @Test(arguments: BlendMode.allCases, [false, true])
    func aShapesEdgeUnderAModeStaysBetweenTheGroundAndTheShape(mode: BlendMode, soft: Bool) throws {
        for (ground, ink) in [(0.5, 0.8), (0.5, 0.15)] {
            let f = try Self.render(side: 64) { s in
                s.background(Color(linear: ground, green: ground, blue: ground))
                let color = Color(linear: ink, green: ink, blue: ink)
                if soft {
                    let layer = s.makeRenderTarget()
                    s.withTarget(layer) { s.noStroke(); s.fill(color); s.drawCircle(32, 32, 16) }
                    s.blendMode(mode)
                    s.drawImage(layer.filtered(.gaussianBlur(radius: 4)).image, 0, 0)
                } else {
                    s.blendMode(mode)
                    s.noStroke(); s.fill(color); s.drawCircle(32.3, 31.6, 20)
                    s.noFill(); s.stroke(color); s.strokeWeight(3); s.drawLine(3, 60, 61, 57)
                }
            }
            let inside = f.value(32, 32)
            let low = min(ground, inside) - 0.0015, high = max(ground, inside) + 0.0015
            var lowest = Double.infinity, highest = -Double.infinity, thinnest = Double.infinity
            for y in 0..<64 { for x in 0..<64 {
                // Where the line crosses nothing else: its own interior is a second full value.
                if !soft && y > 52 { continue }
                lowest = min(lowest, f.value(x, y)); highest = max(highest, f.value(x, y))
            } }
            for i in stride(from: 3, to: f.rgba.count, by: 4) { thinnest = min(thinnest, Double(f.rgba[i])) }
            #expect(lowest >= low && highest <= high,
                    "\(mode), \(soft ? "a blurred layer" : "a disc") of \(ink) over \(ground): the frame runs \(lowest) to \(highest) where the ground is \(ground) and the shape \(inside)")
            #expect(thinnest >= 0.999, "\(mode): the canvas was left with an alpha of \(thinnest)")
            if !soft {
                // The line's rim, on its own: between the ground and the line's interior.
                let core = f.value(32, 58)
                var rimLow = Double.infinity, rimHigh = -Double.infinity
                for y in 53..<64 { for x in 0..<64 { rimLow = min(rimLow, f.value(x, y)); rimHigh = max(rimHigh, f.value(x, y)) } }
                #expect(rimLow >= min(ground, core) - 0.0015 && rimHigh <= max(ground, core) + 0.0015,
                        "\(mode): a line of \(ink) over \(ground) runs \(rimLow) to \(rimHigh) where its interior is \(core)")
            }
        }
    }

    /// Every mode in a column over bands of dark, middle, and light ground: a
    /// see-through disc, a filled outline, a field, a stroke, and a layer laid
    /// back, with a see-through layer background along the foot.
    final class Blended: Sketch {
        override var canvasSize: CanvasSize { .size(280, 240) }
        override func draw() {
            background(Color(white: 0.5))
            noStroke()
            let bands = [Color(red: 0.12, green: 0.2, blue: 0.3), Color(red: 0.55, green: 0.5, blue: 0.4),
                         Color(red: 0.95, green: 0.9, blue: 0.8)]
            for band in 0..<17 {
                fill(bands[band % 3])
                drawRect(0, Double(band) * 12, 280, 12)
            }
            let ink = Color(red: 0.9, green: 0.45, blue: 0.2, alpha: 0.6)
            for (column, mode) in BlendMode.allCases.enumerated() {
                let x = Double(column) * 40 + 20
                let layer = makeRenderTarget()
                withTarget(layer) { noStroke(); fill(ink); drawCircle(x, 180, 13) }
                withState {
                    blendMode(mode)
                    noStroke(); fill(ink)
                    drawCircle(x, 20, 14)
                    drawPolygon([Vector2(x - 14, 46), Vector2(x + 14, 50), Vector2(x + 10, 74), Vector2(x - 12, 70)])
                    drawSDF(SDF.circle(radius: 10).smoothUnion(SDF.rect(width: 24, height: 8).at(0, 7), k: 4).at(x, 136))
                    noFill(); stroke(ink); strokeWeight(7)
                    drawLine(x - 13, 92, x + 13, 108)
                    drawImage(layer.image, 0, 0)
                }
            }
            let veil = makeRenderTarget()
            withTarget(veil) { background(Color(red: 0.2, green: 0.6, blue: 0.9, alpha: 0.5)) }
            drawImage(veil.image, 0, 204, 280, 36)
        }
    }

    /// The recorded page blends as the Mac does: the same weighted colors and
    /// the same coverage under every mode, on each path the page plays.
    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func thePageBlendsAsTheMacDoes() async throws {
        let recording = try OllinApp.recordWebFrames(of: Blended(), frames: 2, fps: 30)
        let page = try OllinApp.webPage(of: recording, form: .inline)
        let played = try await WebExportTests.pagePixels(page, frame: 1)
        let reference = try OllinApp.image(of: Blended(), frame: 1, fps: 30)
        let difference = try WebExportTests.meanDifference(played, reference)
        let far = WebTriangleTests.farFraction(played, reference)
        print("web page against the Mac: every blend mode, mean difference \(String(format: "%.3f", difference)), \(String(format: "%.3f", far * 100))% of the pixels past 32 levels")
        #expect(difference < Snapshot.tolerance, "mean difference \(difference)")
        #expect(far < WebTriangleTests.farTolerance, "\(far * 100)% of the pixels past 32 levels")
    }

    /// A layer starts each frame holding nothing, whether its handle was made
    /// this frame or kept from `setup()`.
    @Test func aKeptLayerStartsClearEveryFrame() throws {
        let probe = Probe(); probe.holds = false; probe.side = 32
        var tick = 0
        probe.prepare = { s in s.layer = s.makeRenderTarget() }
        probe.body = { s in
            s.background(.clear)
            let kept = s.layer!
            s.withTarget(kept) {
                if tick == 0 { s.background(Color(linear: 0.5, green: 0, blue: 0)) }
                s.noStroke(); s.fill(.white); s.drawRect(tick == 0 ? 0 : 20, tick == 0 ? 0 : 20, 8, 8)
            }
            s.drawImage(kept.image, 0, 0)
            tick += 1
        }
        let f = try Self.render(probe, frame: 1)
        #expect(f.value(24, 24, 3) == 1 && f.value(4, 4) != 1, "the second frame's mark is there and the first frame's is gone")
        try pinned("a kept handle keeps the color its last `background` cleared to: the frame after reads (0.5, 0, 0, 1) where it drew nothing (measured 2026-11-09)") {
            #expect(f.value(14, 14, 3) == 0, "the layer's untouched middle reads \(fmt(f.at(14, 14)))")
        }
    }

    /// The order layers are filled in follows what they show, not the order
    /// their blocks were opened in.
    @Test func aLayerCanShowALayerMadeAfterIt() throws {
        let f = try Self.render(side: 32) { s in
            s.background(.clear)
            let b = s.makeRenderTarget(), a = s.makeRenderTarget()
            s.withTarget(b) { s.background(Color(linear: 0.1, green: 0.1, blue: 0.1)) }
            s.withTarget(a) { s.noStroke(); s.fill(.white); s.drawCircle(16, 16, 8) }
            s.withTarget(b) { s.drawImage(a.image, 0, 0) }
            s.drawImage(b.image, 0, 0)
        }
        try pinned("layers are filled in the order their first block opened, so a layer opened first draws a later layer's image before that layer is filled: the disc is missing (measured 2026-11-09)") {
            #expect(f.value(16, 16) > 0.9, "the later layer's disc reads \(f.value(16, 16)) inside the earlier layer")
        }
    }

    /// `background` inside a layer's block clears that layer, whatever it holds
    /// from an earlier block, and nothing of another layer.
    @Test func backgroundInALayerClearsThatLayerAndOnlyIt() throws {
        let second = try Self.render(side: 32) { s in
            s.background(.clear)
            let a = s.makeRenderTarget()
            s.withTarget(a) { s.noStroke(); s.fill(.white); s.drawRect(0, 0, 16, 32) }
            s.withTarget(a) { s.background(Color(linear: 0, green: 0, blue: 0.5)) }
            s.drawImage(a.image, 0, 0)
        }
        #expect(abs(second.value(24, 16, 2) - 0.5) < 0.002, "the background's color reached the layer")
        try pinned("a background in a layer's second block clears that block only: the first block's white half is still there (measured 2026-11-09)") {
            #expect(second.value(8, 16) < 0.01, "the earlier block's mark reads \(second.value(8, 16)) under the new background")
        }
        let nested = try Self.render(side: 32) { s in
            s.background(.clear)
            let a = s.makeRenderTarget(), b = s.makeRenderTarget()
            s.withTarget(a) {
                s.withTarget(b) { s.noStroke(); s.fill(.white); s.drawRect(0, 0, 32, 32) }
                s.background(.clear)
                s.drawImage(b.image, 0, 0)
            }
            s.drawImage(a.image, 0, 0)
        }
        try pinned("a background in a layer's block also drops what a second layer drew inside that block: the inner layer comes back empty (measured 2026-11-09)") {
            #expect(nested.value(16, 16, 3) > 0.99, "the inner layer reads \(fmt(nested.at(16, 16)))")
        }
    }

    /// A `compose` block is the same calls written by hand: the same layers, the
    /// same filters in the same order, the same blend, to the number.
    @Test func composeIsTheSameCallsByHand() throws {
        let byHand = try Self.render { s in
            s.background(Color(white: 0.1))
            let under = s.makeRenderTarget(scale: 0.5)
            s.withTarget(under) { s.noStroke(); s.fill(.indigo); s.drawCircle(48, 48, 30) }
            s.drawImage(under.filtered(.gaussianBlur(radius: 5)).image, 0, 0, 96, 96)
            let top = s.makeRenderTarget()
            s.withTarget(top) { Self.picture(s) }
            s.blendMode(.add)
            s.drawImage(top.filtered(.bloom(amount: 1.4)).filtered(.gaussianBlur(radius: 1.5)).image, 0, 0)
            s.blendMode(.normal)
        }
        let composed = try Self.render { s in
            s.background(Color(white: 0.1))
            s.compose {
                s.layer { s.noStroke(); s.fill(.indigo); s.drawCircle(48, 48, 30) }
                    .post(.gaussianBlur(radius: 5)).scaled(0.5)
                s.layer { Self.picture(s) }
                    .post(.bloom(amount: 1.4), .gaussianBlur(radius: 1.5)).blended(.add)
            }
        }
        #expect(composed.worst(against: byHand).by == 0, "a stack of two: \(describe(composed.worst(against: byHand)))")
        let handMask = try Self.render { s in
            s.background(.clear)
            let base = s.makeRenderTarget()
            s.withTarget(base) { Self.picture(s) }
            let mask = s.makeRenderTarget()
            s.withTarget(mask) { s.noStroke(); s.fill(.white); s.drawCircle(48, 48, 30) }
            s.drawImage(base.filtered(.invert()).combined(with: mask.filtered(.gaussianBlur(radius: 3)), .mask()).filtered(.sepia()).image, 0, 0)
        }
        let composedMask = try Self.render { s in
            s.background(.clear)
            s.compose {
                s.layer { Self.picture(s) }
                    .post(.invert())
                    .masked(by: s.aside { s.noStroke(); s.fill(.white); s.drawCircle(48, 48, 30) }.post(.gaussianBlur(radius: 3)))
                    .post(.sepia())
            }
        }
        #expect(composedMask.worst(against: handMask).by == 0, "a masked layer: \(describe(composedMask.worst(against: handMask)))")
    }

    /// A `compose` block under a transform draws where the same drawing would.
    @Test func composeUnderATransformDrawsWhereTheDrawingWould() throws {
        func span(_ f: Frame) -> ClosedRange<Int>? {
            let xs = (0..<f.width).filter { f.value($0, 25, 3) > 0.5 }
            return xs.isEmpty ? nil : xs.first!...xs.last!
        }
        let direct = try Self.render(side: 64) { s in
            s.background(.clear); s.translate(10, 0)
            s.noStroke(); s.fill(.white); s.drawRect(20, 20, 10, 10)
        }
        let composed = try Self.render(side: 64) { s in
            s.background(.clear); s.translate(10, 0)
            s.compose { s.layer { s.noStroke(); s.fill(.white); s.drawRect(20, 20, 10, 10) } }
        }
        #expect(span(direct) == 30...39)
        try pinned("the transform carries into the layer's drawing and then moves the finished layer again: under translate(10, 0) the mark lands at 40 to 49 where the same drawing lands at 30 to 39 (measured 2026-11-09)") {
            #expect(span(composed) == span(direct), "compose drew the mark at \(String(describing: span(composed)))")
        }
    }

    /// What a frame makes of a layer does not depend on what else the frame
    /// makes of it: four results off one layer each match the frame that makes
    /// that result alone.
    @Test func severalResultsOffOneLayerEachMatchTheirOwnFrame() throws {
        let makers: [@MainActor (RenderTarget) -> RenderTarget] = [
            { $0.filtered(.invert()) },
            { $0.filtered(.gaussianBlur(radius: 3)) },
            { $0.filtered(.invert()).combined(with: $0.filtered(.gaussianBlur(radius: 3)), .mix(amount: 0.5)) },
            { $0.filtered(.bloom()).filtered(.swirl()) },
            { $0 },
        ]
        let together = try Self.render(wide: 96 * makers.count) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget(width: 96, height: 96)
            s.withTarget(layer) { Self.picture(s) }
            let made = makers.map { $0(layer) }
            for (i, m) in made.enumerated() { s.drawImage(m.image, Double(96 * i), 0) }
        }
        for (i, make) in makers.enumerated() {
            let alone = try Self.render { s in
                s.background(.clear)
                let layer = s.makeRenderTarget()
                s.withTarget(layer) { Self.picture(s) }
                s.drawImage(make(layer).image, 0, 0)
            }
            var worst = 0.0
            for y in 0..<96 { for x in 0..<96 { for c in 0..<4 {
                worst = max(worst, abs(together.value(x + 96 * i, y, c) - alone.value(x, y, c)))
            } } }
            #expect(worst == 0, "result \(i) differs from its own frame by \(worst)")
        }
    }

    // MARK: A filter asked for nothing

    /// Filters that hand the texel back untouched at their neutral setting.
    nonisolated static let exactlyNeutral: [Named] = [
        Named(name: "gaussianBlur radius 0", filter: .gaussianBlur(radius: 0)),
        Named(name: "boxBlur radius 0", filter: .boxBlur(radius: 0)),
        Named(name: "motionBlur distance 0", filter: .motionBlur(distance: 0)),
        Named(name: "radialBlur amount 0", filter: .radialBlur(amount: 0)),
        Named(name: "progressiveBlur radius 0", filter: .progressiveBlur(radius: 0)),
        Named(name: "tiltShift radius 0", filter: .tiltShift(radius: 0)),
        Named(name: "bloom amount 0", filter: .bloom(amount: 0)),
        Named(name: "halation amount 0", filter: .halation(amount: 0)),
        Named(name: "sharpen amount 0", filter: .sharpen(amount: 0)),
        Named(name: "antialias amount 0", filter: .antialias(amount: 0)),
        Named(name: "exposure 0 stops", filter: .exposure(stops: 0)),
        Named(name: "channelMixer identity", filter: .channelMixer(.identity)),
        Named(name: "vignette amount 0", filter: .vignette(amount: 0)),
        Named(name: "chromaticAberration amount 0", filter: .chromaticAberration(amount: 0)),
        Named(name: "diffraction amount 0", filter: .diffraction(amount: 0)),
        Named(name: "thinFilm amount 0", filter: .thinFilm(amount: 0)),
        Named(name: "anaglyph amount 0", filter: .anaglyph(amount: 0)),
        Named(name: "glitch amount 0", filter: .glitch(amount: 0)),
        Named(name: "vhs amount 0", filter: .vhs(amount: 0)),
        Named(name: "swirl angle 0", filter: .swirl(angle: 0)),
        Named(name: "bulge amount 0", filter: .bulge(amount: 0)),
        Named(name: "wave amplitude 0", filter: .wave(amplitude: 0)),
        Named(name: "ripple amplitude 0", filter: .ripple(amplitude: 0)),
        Named(name: "polar amount 0", filter: .polar(amount: 0)),
        Named(name: "tile count 1", filter: .tile(count: 1)),
        Named(name: "tile count 1 mirrored", filter: .tile(count: 1, mirrored: true)),
        Named(name: "perturb amount 0", filter: .perturb(amount: 0)),
        Named(name: "lensDistortion 0", filter: .lensDistortion(amount: 0, quartic: 0)),
        Named(name: "cornerPin identity", filter: .cornerPin()),
        Named(name: "mirage amount 0", filter: .mirage(amount: 0)),
        Named(name: "pagePeel amount 0", filter: .pagePeel(amount: 0)),
        Named(name: "bubbleWrap radius 0", filter: .bubbleWrap(radius: 0)),
        Named(name: "bubbleWrap amount 0", filter: .bubbleWrap(amount: 0)),
        Named(name: "repeated count 1", filter: .repeated(.grid(columns: 1), count: 1, scale: 1)),
        Named(name: "outline width 0", filter: .outline(width: 0)),
        Named(name: "edgeGlow width 0", filter: .edgeGlow(width: 0)),
        Named(name: "wipe progress 1", filter: .wipe(.directional(), progress: 1)),
        Named(name: "levels 0 1 1", filter: .levels(blackPoint: 0, whitePoint: 1, gamma: 1)),
        Named(name: "invert 0", filter: .invert(amount: 0)),
        Named(name: "lumaKey 0 to 1", filter: .lumaKey(low: 0, high: 1)),
        Named(name: "lightLeak intensity 0", filter: .lightLeak(intensity: 0)),
    ]

    /// Filters whose arithmetic takes the color out from under its alpha and
    /// puts it back, which a half float returns within one step of its precision.
    nonisolated static let neutralWithinAStep: [Named] = [
        Named(name: "colorGrade defaults", filter: .colorGrade()),
        Named(name: "temperature 0 0", filter: .temperature(amount: 0, tint: 0)),
        Named(name: "vibrance 0", filter: .vibrance(amount: 0)),
        Named(name: "sepia 0", filter: .sepia(amount: 0)),
        Named(name: "duotone 0", filter: .duotone(dark: .blue, light: .yellow, amount: 0)),
        Named(name: "gradientMap 0", filter: .gradientMap(Ramp([.black, .red, .white]), amount: 0)),
        Named(name: "lut identity", filter: .lut(.identity())),
        Named(name: "lut amount 0", filter: .lut(.warmPrint, amount: 0)),
        Named(name: "softProof amount 0", filter: .softProof(SoftProof(.genericCMYK), amount: 0)),
        Named(name: "grain amount 0", filter: .grain(amount: 0)),
        Named(name: "filmGrain amount 0", filter: .filmGrain(amount: 0)),
        Named(name: "contour amount 0", filter: .contour(amount: 0)),
        Named(name: "iridescence amount 0", filter: .iridescence(amount: 0)),
        Named(name: "glitter amount 0", filter: .glitter(amount: 0)),
        Named(name: "pixelate size 1", filter: .pixelate(size: 1)),
        // Scanlines takes the color out from under its alpha like the rest of
        // this list (0.0005 at one soft-edged pixel, measured 2026-11-12).
        Named(name: "scanlines amount 0", filter: .scanlines(amount: 0)),
    ]

    /// A filter at the setting that asks for none of its effect is its input:
    /// every channel, light past white and see-through pixels included.
    @Test(arguments: exactlyNeutral)
    func aFilterAskedForNothingReturnsItsInput(_ item: Named) throws {
        let w = try Self.filtered(item.filter).worst(against: try Self.plain())
        #expect(w.by == 0, "\(item.name): \(describe(w))")
    }

    @Test(arguments: neutralWithinAStep)
    func aToneFilterAskedForNothingIsWithinAStep(_ item: Named) throws {
        let plain = try Self.plain()
        let w = try Self.filtered(item.filter).worst(against: plain)
        // One step of a half float at the value that moved: 2^-10 of it.
        let step = max(abs(plain.value(w.x, w.y, w.channel)), 0.5) / 1024
        #expect(w.by <= step * 1.01, "\(item.name): \(describe(w)), a step there is \(step)")
    }

    // MARK: Tones as written

    /// A gray named the way a sketch names it, through a tone filter, and the
    /// gray (or the share of its coverage) that must come back, named the same way.
    struct Tone: Sendable, CustomTestStringConvertible {
        let name: String
        let filter: Filter
        let white: Double
        /// The gray that comes back, as written; nil where only the coverage is read.
        var gives: Double?
        /// The coverage that comes back.
        var alpha = 1.0
        var testDescription: String { "\(name) of \(white)" }
    }

    nonisolated static let tones: [Tone] = [
        Tone(name: "threshold 0.5", filter: .threshold(0.5), white: 0.49, gives: 0),
        Tone(name: "threshold 0.5", filter: .threshold(0.5), white: 0.51, gives: 1),
        Tone(name: "soft threshold 0.5", filter: .threshold(0.5, softness: 0.25), white: 0.5, gives: 0.5),
        Tone(name: "soft threshold 0.5", filter: .threshold(0.5, softness: 0.25), white: 0.8, gives: 1),
        Tone(name: "invert", filter: .invert(), white: 0.25, gives: 0.75),
        Tone(name: "invert", filter: .invert(), white: 1, gives: 0),
        Tone(name: "invert 0.5", filter: .invert(amount: 0.5), white: 0.2, gives: 0.5),
        Tone(name: "posterize 3", filter: .posterize(levels: 3), white: 0.3, gives: 0),
        Tone(name: "posterize 3", filter: .posterize(levels: 3), white: 0.4, gives: 0.5),
        Tone(name: "posterize 3", filter: .posterize(levels: 3), white: 0.7, gives: 1),
        Tone(name: "solarize 0.5", filter: .solarize(0.5, softness: 0), white: 0.25, gives: 0.25),
        Tone(name: "solarize 0.5", filter: .solarize(0.5, softness: 0), white: 0.75, gives: 0.25),
        Tone(name: "levels 0.25 to 0.75", filter: .levels(blackPoint: 0.25, whitePoint: 0.75), white: 0.25, gives: 0),
        Tone(name: "levels 0.25 to 0.75", filter: .levels(blackPoint: 0.25, whitePoint: 0.75), white: 0.5, gives: 0.5),
        Tone(name: "levels 0.25 to 0.75", filter: .levels(blackPoint: 0.25, whitePoint: 0.75), white: 0.75, gives: 1),
        Tone(name: "levels 0.25 to 0.75", filter: .levels(blackPoint: 0.25, whitePoint: 0.75), white: 0.9, gives: 1),
        Tone(name: "levels gamma 2", filter: .levels(gamma: 2), white: 0.5, gives: 0.25),
        Tone(name: "contrast 0", filter: .colorGrade(contrast: 0), white: 0.9, gives: 0.5),
        Tone(name: "contrast 0", filter: .colorGrade(contrast: 0), white: 0.1, gives: 0.5),
        Tone(name: "contrast 2", filter: .colorGrade(contrast: 2), white: 0.4, gives: 0.3),
        Tone(name: "contrast 2", filter: .colorGrade(contrast: 2), white: 0.6, gives: 0.7),
        Tone(name: "contrast 0.5", filter: .colorGrade(contrast: 0.5), white: 1, gives: 0.75),
        Tone(name: "lumaKey from 0.5", filter: .lumaKey(low: 0.5), white: 0.4, alpha: 0),
        Tone(name: "lumaKey from 0.5", filter: .lumaKey(low: 0.5), white: 0.5, alpha: 0.5),
        Tone(name: "lumaKey from 0.5", filter: .lumaKey(low: 0.5), white: 0.6, gives: 0.6),
        Tone(name: "lumaKey to 0.5", filter: .lumaKey(low: 0, high: 0.5), white: 0.6, alpha: 0),
    ]

    /// A tone filter's levels and its arithmetic are in the grays a sketch
    /// writes: a cut at 0.5 falls at `Color(white: 0.5)`, a negative of
    /// `Color(white: 0.25)` is `Color(white: 0.75)`, a contrast of 0 is mid-gray.
    @Test(arguments: tones)
    func aToneFilterWorksOnTheGrayAsWritten(_ tone: Tone) throws {
        let out = mean(try flat(32, Color(white: tone.white), tone.filter))
        #expect(abs(out.w - tone.alpha) < 0.002, "\(tone.name): Color(white: \(tone.white)) came back with a coverage of \(fmt(out.w)) where \(tone.alpha) is due")
        guard let gives = tone.gives else { return }
        for c in 0 ..< 3 {
            let written = Color.linearToSrgb(out[c] / out.w)
            #expect(abs(written - gives) < 0.002, "\(tone.name): Color(white: \(tone.white)) came back as \(fmt(written)) as written where \(gives) is due (channel \(c))")
        }
    }

    /// A ramp of written grays through `threshold(0.5)` is black up to its
    /// middle and white from there on, and the cut moves with the value.
    @Test(arguments: [0.25, 0.5, 0.75])
    func aThresholdSplitsAWrittenRampAtItsValue(_ value: Double) throws {
        let out = try Self.render { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            s.withTarget(layer) {
                s.noStroke()
                for x in 0 ..< 96 {
                    s.fill(Color(white: (Double(x) + 0.5) / 96))
                    let x0 = Double(x), x1 = Double(x + 1)
                    s.drawPolygon([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, 96), Vector2(x0, 96)])
                }
            }
            s.drawImage(layer.filtered(.threshold(value)).image, 0, 0)
        }
        let cut = Int(value * 96)
        for x in 0 ..< 96 {
            #expect(out.value(x, 48) == (x < cut ? 0 : 1), "column \(x), written as \((Double(x) + 0.5) / 96), came back \(out.value(x, 48)) under a cut at \(value)")
        }
    }

    /// Levels a hair off its neutral setting is a hair off the picture, light
    /// past white included: the curve carries on past the white point.
    @Test func levelsNearItsNeutralSettingIsNearThePicture() throws {
        let plain = try Self.plain()
        let w = try Self.filtered(.levels(blackPoint: 0, whitePoint: 1, gamma: 1.001)).worst(against: plain)
        #expect(w.by < 0.01, "levels at a gamma of 1.001: \(describe(w)), where the picture holds \(plain.value(w.x, w.y, w.channel))")
    }

    /// A stretch makes white and never more: under a white point of 0.5 the
    /// picture's light past white is as bright as it was, and its channel
    /// between the white point and white comes out white.
    @Test func levelsMakesWhiteAndNeverMore() throws {
        let plain = try Self.plain()
        let out = try Self.filtered(.levels(whitePoint: 0.5))
        // Inside the flat that holds (3.0, 1.6, 0.4) in light.
        #expect(plain.at(20, 43) == SIMD4(3.0, 1.599609375, 0.39990234375, 1), "the picture's bright flat reads \(fmt(plain.at(20, 43)))")
        let got = out.at(20, 43)
        #expect(abs(got.x - 3.0) < 0.004 && abs(got.y - 1.6) < 0.002 && abs(got.z - 1) < 0.001, "under a white point of 0.5 the flat (3.0, 1.6, 0.4) came back \(fmt(got)) where (3.0, 1.6, 1.0) is due")
        #expect(out.rgba.enumerated().allSatisfy { $0.element <= max(plain.rgba[$0.offset], 1) + 0.001 }, "a stretch made light past white that was not there")
    }

    /// A color falls on the side of a cut that the gray as bright as it is falls
    /// on: its luminance, read as a written gray.
    @Test func aCutReadsAColorAsTheGrayOfItsLuminance() throws {
        // Three colors of one luminance, the one `Color(white: 0.5)` has, a tenth over and a tenth under.
        let half = Color.srgbToLinear(0.5)
        for (name, r, g, b) in [("a gray", 1.0, 1.0, 1.0), ("an orange", 2.2, 0.7, 0.3), ("a blue", 0.3, 0.9, 3.0)] {
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            for (side, k) in [(1.0, 1.1), (0.0, 0.9)] {
                let scale = half * k / luminance
                let out = mean(try flat(32, Color(linear: r * scale, green: g * scale, blue: b * scale), .threshold(0.5)))
                #expect(out.x == side, "\(name) \(k) times as bright as mid-gray came back \(fmt(out)) under threshold(0.5)")
            }
        }
    }

    // MARK: Blurs

    /// A blur moves light and makes none: away from the edges, the layer's
    /// summed coverage is what it was.
    @Test(arguments: [1.0, 2.0, 4.0, 8.0])
    func aBlurMovesLightAndMakesNone(radius: Double) throws {
        let base = Self.spread(try Self.disc(filter: nil)).sum
        for (name, filter) in [("gaussian", Filter.gaussianBlur(radius: radius)), ("box", .boxBlur(radius: radius))] {
            let ratio = Self.spread(try Self.disc(filter: filter)).sum / base
            #expect(abs(ratio - 1) < 0.003, "\(name) blur at \(radius) kept \(ratio) of the light")
        }
    }

    /// A Gaussian blur's radius is its standard deviation in canvas pixels, and
    /// a box blur of radius r is 2r + 1 pixels wide, on a plain render and on a
    /// supersampled one brought back down.
    @Test(arguments: [1.0, 2.0, 4.0, 8.0], [1, 2])
    func aBlursRadiusIsItsWidthInPixels(radius: Double, renderScale: Int) throws {
        let base = Self.spread(try Self.disc(filter: nil, scale: renderScale))
        let g = Self.spread(try Self.disc(filter: .gaussianBlur(radius: radius), scale: renderScale))
        let sigma = ((g.varX - base.varX).squareRoot() + (g.varY - base.varY).squareRoot()) / 2
        #expect(abs(sigma / radius - 1) < (radius < 2 ? 0.05 : 0.015), "a Gaussian of radius \(radius) spread the disc by a sigma of \(sigma)")
        let b = Self.spread(try Self.disc(filter: .boxBlur(radius: radius), scale: renderScale))
        let width = 2 * radius + 1
        let want = ((width * width - 1) / 12).squareRoot()
        let got = ((b.varX - base.varX).squareRoot() + (b.varY - base.varY).squareRoot()) / 2
        #expect(abs(got / want - 1) < 0.015, "a box of radius \(radius) spread the disc by \(got) where \(width) pixels give \(want)")
    }

    // MARK: Sizes at any layer scale

    /// Bands of rising gray eight pixels wide, set two pixels back so no band's
    /// edge falls on the edge of an eight-pixel cell, in a layer through `filter`.
    static func bands(filter: Filter?, layerScale: Double) throws -> Frame {
        try render(side: 128) { s in
            s.background(.clear)
            let layer = layerScale == 1 ? s.makeRenderTarget() : s.makeRenderTarget(scale: layerScale)
            s.withTarget(layer) {
                s.noStroke()
                for b in 0...16 {
                    let v = Double(b + 1) / 18
                    s.fill(Color(linear: v, green: v, blue: v))
                    s.drawRect(Double(b) * 8 - 2, 0, 8, 128)
                }
            }
            s.drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0, 128, 128)
        }
    }

    /// Where channel `c` sits along x, weighed by its own light.
    static func centerX(_ f: Frame, _ c: Int) -> Double {
        var sum = 0.0, at = 0.0
        for y in 0..<f.height { for x in 0..<f.width {
            let v = f.value(x, y, c); sum += v; at += v * (Double(x) + 0.5)
        } }
        return at / sum
    }

    /// A layer's `scale` is how finely it is kept, so what a filter does to the
    /// picture is the same at any scale: a blur is as wide, an outline as thick,
    /// a mosaic's cells as large, a shadow as far away.
    @Test(arguments: [0.25, 0.5, 1.0, 2.0])
    func aFiltersSizesAreCanvasPixelsAtAnyLayerScale(layerScale: Double) throws {
        let base = Self.spread(try Self.disc(filter: nil, layerScale: layerScale))
        let g = Self.spread(try Self.disc(filter: .gaussianBlur(radius: 4), layerScale: layerScale))
        let sigma = ((g.varX - base.varX).squareRoot() + (g.varY - base.varY).squareRoot()) / 2
        #expect(abs(sigma / 4 - 1) < 0.05, "on a layer at \(layerScale) a radius of 4 spread the disc by a sigma of \(sigma)")

        let plain = try Self.disc(radius: 16, filter: nil, layerScale: layerScale).sum(3)
        let outlined = try Self.disc(radius: 16, filter: .outline(width: 6, color: .white, align: .outside),
                                     layerScale: layerScale).sum(3)
        let grew = (outlined / .pi).squareRoot() - (plain / .pi).squareRoot()
        #expect(abs(grew - 6) < 0.3, "on a layer at \(layerScale) an outline of 6 grew the disc by \(grew)")

        // A mosaic of 8 has cells eight canvas pixels across: one value inside
        // each cell, and the next band's value in the next cell.
        let mosaic = try Self.bands(filter: .pixelate(size: 8), layerScale: layerScale)
        var within = 0.0, smallestStep = 9.0
        for k in 0..<16 {
            within = max(within, abs(mosaic.value(8 * k + 2, 67) - mosaic.value(8 * k + 5, 67)))
            if k < 15 { smallestStep = min(smallestStep, mosaic.value(8 * k + 11, 67) - mosaic.value(8 * k + 3, 67)) }
        }
        #expect(within < 0.002, "on a layer at \(layerScale) a cell of 8 holds two values \(within) apart")
        #expect(smallestStep > 0.04, "on a layer at \(layerScale) two cells of 8 side by side differ by \(smallestStep), a band is \(1.0 / 18)")

        // A shadow's offset of 40 lands 40 away.
        let shadowed = try Self.render(side: 128, wide: 192) { s in
            s.background(.clear)
            let layer = layerScale == 1 ? s.makeRenderTarget() : s.makeRenderTarget(scale: layerScale)
            s.withTarget(layer) { s.noStroke(); s.fill(.blue); s.drawCircle(50.3, 63.8, 10) }
            s.drawImage(layer.filtered(.dropShadow(offset: Vector2(40, 0), radius: 2, color: .red)).image, 0, 0, 192, 128)
        }
        let away = Self.centerX(shadowed, 0) - Self.centerX(shadowed, 2)
        #expect(abs(away - 40) < 0.3, "on a layer at \(layerScale) a shadow offset by 40 lands \(away) away")
    }

    /// Something that takes a size, with every size it takes multiplied by `k`.
    struct Sized<Made: Sendable>: Sendable, CustomTestStringConvertible {
        let name: String
        let make: @Sendable (Double) -> Made
        var testDescription: String { name }
        init(_ name: String, _ make: @escaping @Sendable (Double) -> Made) { self.name = name; self.make = make }
    }

    /// A layer kept at `layerScale` beside its twin: a full-size layer that
    /// many times as large, holding the same texels, where a canvas pixel is a
    /// texel. `draw(k, twin)` draws one or the other with every size
    /// multiplied by `k`. The scaled layer with its sizes as written must be
    /// the twin with its sizes multiplied by the scale, and must be far from
    /// the twin with its sizes as written, which is what sizes read in the
    /// layer's own texels drew.
    private func judge(_ name: String, at layerScale: Double, within share: Double = 0.25,
                       _ draw: (_ k: Double, _ twin: Bool) throws -> Frame) throws {
        let got = try draw(1, false), same = try draw(layerScale, true), texels = try draw(1, true)
        let off = got.mean(against: same), gap = texels.mean(against: same)
        #expect(gap > 0.002, "\(name): the same sizes read in texels change the picture by only \(gap), which proves nothing")
        #expect(off < share * gap, "\(name) on a layer at \(layerScale) is \(off) from its twin; sizes read in texels would be \(gap) from it")
    }

    /// The picture in a layer kept at `layerScale`, or in its twin, with
    /// `between` turning the layer into what is drawn back.
    static func scaled(_ layerScale: Double, twin: Bool, _ fill: @escaping @MainActor (Probe) -> Void = { picture($0) },
                       _ between: @escaping @MainActor (Probe, RenderTarget) -> RenderTarget) throws -> Frame {
        try render { s in
            s.background(.clear)
            let layer = Self.layer(s, layerScale, twin: twin, fill)
            s.drawImage(between(s, layer).image, 0, 0, 96, 96)
        }
    }

    /// A layer over the 96-pixel canvas kept at `layerScale`, or its twin.
    static func layer(_ s: Probe, _ layerScale: Double, twin: Bool,
                      _ fill: @escaping @MainActor (Probe) -> Void) -> RenderTarget {
        let side = Int((96 * layerScale).rounded())
        let layer = twin ? s.makeRenderTarget(width: side, height: side)
                         : (layerScale == 1 ? s.makeRenderTarget() : s.makeRenderTarget(scale: layerScale))
        s.withTarget(layer) {
            s.withState {
                if twin { s.scale(layerScale) }
                fill(s)
            }
        }
        return layer
    }

    nonisolated static let sizedFilters: [Sized<Filter>] = [
        Sized("gaussianBlur") { .gaussianBlur(radius: 3 * $0) },
        Sized("boxBlur") { .boxBlur(radius: 4 * $0) },
        Sized("bloom") { .bloom(threshold: 0.2, amount: 2, radius: 4 * $0) },
        Sized("halation") { .halation(threshold: 0.3, radius: 4 * $0) },
        Sized("tiltShift") { .tiltShift(radius: 6 * $0) },
        Sized("progressiveBlur") { .progressiveBlur(start: 0.2, radius: 6 * $0) },
        Sized("dither") { .dither(levels: 3, pixelSize: 2 * $0) },
        Sized("two-color dither") { .dither(dark: .black, light: .white, pixelSize: 2 * $0) },
        Sized("filmGrain") { .filmGrain(amount: 0.4, size: 4 * $0) },
        Sized("pixelate") { .pixelate(size: 6 * $0) },
        Sized("chrome") { .chrome(warp: 6 * $0, coreWidth: 8 * $0, breakWidth: 3 * $0) },
        Sized("anaglyph") { .anaglyph(separation: 6 * $0) },
        Sized("mirage") { .mirage(amount: 8 * $0) },
        Sized("flutedGlass margins") { .flutedGlass(flutes: 12, margins: Insets(top: 12 * $0, right: 12 * $0, bottom: 12 * $0, left: 12 * $0)) },
        Sized("outline") { .outline(width: 4 * $0, color: .red) },
        Sized("dropShadow") { .dropShadow(offset: Vector2(6, 4) * $0, radius: 3 * $0, color: .red) },
        Sized("innerShadow") { .innerShadow(offset: Vector2(4, 3) * $0, radius: 2 * $0, color: .red) },
        Sized("outerGlow") { .outerGlow(radius: 8 * $0, color: .red) },
        Sized("innerGlow") { .innerGlow(radius: 6 * $0, color: .red) },
        Sized("edgeGlow") { .edgeGlow(width: 6 * $0) },
        Sized("bevel") { .bevel(width: 5 * $0) },
        Sized("adaptiveThreshold") { .adaptiveThreshold(window: 12 * $0) },
        Sized("fieldMap of a measured field") { _ in .distanceField() },
    ]

    /// Filters that take a size and also hold a length of their own (an edge's
    /// antialiasing ramp, the blur under a direction field, a count of taps, a
    /// sheet laid out over the canvas). That length is canvas pixels too, and
    /// the twin reads it in its own texels, so these sit near their twin where
    /// the ones above sit on it.
    nonisolated static let sizedWithALengthOfTheirOwn: [Sized<Filter>] = [
        Sized("bilateral") { .bilateral(radius: 2 * $0, sigma: 4) },
        Sized("oilPaint") { .oilPaint(radius: 2 * $0) },
        Sized("xdog") { .xdog(radius: 2 * $0, flow: 4 * $0) },
        Sized("brushwork") { .brushwork(radius: 4 * $0) },
        Sized("hatching") { .hatching(spacing: 6 * $0, length: 12 * $0) },
        Sized("arrows") { .arrows(spacing: 12 * $0, scale: 10 * $0, width: 2 * $0) },
        Sized("bubbleWrap") { .bubbleWrap(radius: 10 * $0, gap: 3 * $0) },
        Sized("holographicFoil") { .holographicFoil(spacing: 24 * $0, bandWidth: 12 * $0, bandShift: 30 * $0) },
    ]

    /// Two whose own lengths are most of what they draw (the tape's lines and
    /// tears, the rounds of a shock), so no twin holds them.
    nonisolated static let sizedAgainstTheFullSize: [Sized<Filter>] = [
        Sized("shock") { .shock(flow: 8 * $0, radius: 4 * $0, smoothing: 4 * $0) },
        Sized("vhs") { .vhs(smear: 24 * $0, jitter: 8 * $0, damage: 0) },
    ]

    /// Every filter that takes a size takes it in canvas pixels, on a layer
    /// kept at half size and on one kept at twice.
    @Test(arguments: sizedFilters, [0.5, 2.0])
    func aSizedFilterKeepsItsSizesOnAScaledLayer(_ item: Sized<Filter>, layerScale: Double) throws {
        try judge(item.name, at: layerScale, within: 0.05) { k, twin in
            try Self.scaled(layerScale, twin: twin) { _, layer in
                if item.name.hasPrefix("fieldMap") {
                    // The field's own numbers are the size here: a ramp that
                    // reads them spans the same canvas pixels at any scale.
                    return layer.filtered(.distanceField(maxDistance: 24 * k))
                        .filtered(.fieldMap(Ramp([.black, .white]), from: -8 * k, to: 12 * k))
                }
                return layer.filtered(item.make(k))
            }
        }
    }

    @Test(arguments: sizedWithALengthOfTheirOwn, [0.5, 2.0])
    func aFilterWithALengthOfItsOwnStaysNearItsTwin(_ item: Sized<Filter>, layerScale: Double) throws {
        // The oil paint flattens detail and leaves flats as they are, so it is
        // read on a picture that has detail.
        let detailed = item.name == "oilPaint"
        try judge(item.name, at: layerScale, within: 0.5) { k, twin in
            try Self.scaled(layerScale, twin: twin, { detailed ? Self.speckled($0) : Self.picture($0) }) { _, layer in
                layer.filtered(item.make(k))
            }
        }
    }

    /// A picture that is detail all over: squares three pixels across in
    /// colors that jump from one to the next, under the half-clear disc.
    static func speckled(_ s: Sketch) {
        s.noStroke()
        var state: UInt32 = 0x9E37_79B9
        func next() -> Double { state = state &* 1_664_525 &+ 1_013_904_223; return Double(state >> 8) / Double(1 << 24) }
        for j in 0 ..< 32 { for i in 0 ..< 32 {
            s.fill(Color(linear: next(), green: next(), blue: next()))
            s.drawPolygon([Vector2(Double(i) * 3, Double(j) * 3), Vector2(Double(i) * 3 + 3, Double(j) * 3),
                           Vector2(Double(i) * 3 + 3, Double(j) * 3 + 3), Vector2(Double(i) * 3, Double(j) * 3 + 3)])
        } }
        s.fill(Color(red: 0.2, green: 0.7, blue: 0.9, alpha: 0.5))
        s.drawCircle(64, 56, 19)
    }

    /// Read against the full-size picture on a layer kept at twice the size:
    /// nearer to it than to the full-size picture with its sizes halved, which
    /// is what sizes read in texels drew.
    @Test(arguments: sizedAgainstTheFullSize)
    func aFilterMadeOfItsOwnLengthsKeepsThemOnAFinerLayer(_ item: Sized<Filter>) throws {
        let right = try Self.filtered(item.make(1)), got = try Self.filtered(item.make(1), layerScale: 2)
        let texels = try Self.filtered(item.make(0.5))
        let off = got.mean(against: right), gap = texels.mean(against: right)
        #expect(gap > 0.002, "\(item.name): the same sizes halved change the picture by only \(gap), which proves nothing")
        #expect(off < 0.6 * gap, "\(item.name) on a layer at 2 is \(off) from the full-size picture; sizes read in texels would be \(gap) from it")
    }

    /// A measured field's distances are canvas pixels at any layer scale, and so
    /// is the reach it is held to.
    @Test(arguments: [0.5, 2.0])
    func aMeasuredFieldReadsCanvasPixelsAtAnyLayerScale(layerScale: Double) throws {
        let c = Vector2(64, 64)
        let field = try Self.render(side: 128) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget(scale: layerScale, precision: .float32)
            s.withTarget(layer) { s.noStroke(); s.fill(.white); s.drawCircle(c.x, c.y, 30) }
            s.drawImage(layer.filtered(.distanceField(maxDistance: 20)).image, 0, 0, 128, 128)
        }
        var worst = 0.0
        for y in stride(from: 10, to: 118, by: 4) { for x in stride(from: 10, to: 118, by: 4) {
            let analytic = (Vector2(Double(x) + 0.5, Double(y) + 0.5) - c).length - 30
            guard abs(analytic) > 3, abs(analytic) < 16 else { continue }
            worst = max(worst, abs(field.value(x, y) - analytic))
        } }
        #expect(worst < 1.5 / min(layerScale, 1), "on a layer at \(layerScale) the field strays from the true distance by \(worst) canvas pixels")
        #expect(field.value(64, 64) == -20 && field.value(4, 4) == 20, "the reach of 20 is held as 20: \(field.value(64, 64)) inside, \(field.value(4, 4)) outside")
    }

    nonisolated static let sizedCombines: [Sized<Combine>] = [
        Sized("defocus") { .defocus(focus: 0.1, range: 0.05, maxBlur: 8 * $0) },
        Sized("anaglyph by depth") { .anaglyph(separation: 16 * $0, focus: 0.2) },
        Sized("light") { .light(reach: 24 * $0) },
    ]

    /// A combine's sizes are canvas pixels too: the largest blur of a defocus,
    /// the parallax of an anaglyph, how far a flat scene's light travels.
    @Test(arguments: sizedCombines, [0.5, 2.0])
    func aSizedCombineKeepsItsSizesOnAScaledLayer(_ item: Sized<Combine>, layerScale: Double) throws {
        let lit = item.name == "light"
        try judge(item.name, at: layerScale, within: 0.05) { k, twin in
            try Self.scaled(layerScale, twin: twin, { s in
                // A flat scene of two walls, or the picture.
                if lit { s.noStroke(); s.fill(.white); s.drawRect(20, 10, 6, 60); s.drawRect(60, 50, 30, 6) }
                else { Self.picture(s) }
            }) { s, base in
                let other = Self.layer(s, layerScale, twin: twin) { s in
                    s.noStroke()
                    // A lamp, or a depth map: near on the left, far on the right.
                    if lit { s.fill(.orange); s.drawCircle(46, 34, 5) }
                    else { for i in 0..<12 { s.fill(Color(white: Double(i) / 11)); s.drawRect(Double(i) * 8, 0, 8, 96) } }
                }
                return base.combined(with: other, item.make(k))
            }
        }
    }

    nonisolated static let sizedGenerators: [Sized<Generator>] = [
        Sized("gaborNoise") { .gaborNoise(wavelength: 12 * $0, seed: 3) },
        Sized("rust") { .rust(count: 6, radius: 10 * $0 ... 22 * $0, seed: 2) },
        Sized("terrazzo") { .terrazzo(chipRadius: 12 * $0, gap: 2 * $0, seed: 2) },
        Sized("scratches") { .scratches(count: 8, thickness: 2 * $0, wobble: 5 * $0, seed: 2) },
        Sized("pulsingBorder margins") { .pulsingBorder(margins: Insets(top: 14 * $0, right: 14 * $0, bottom: 14 * $0, left: 14 * $0)) },
    ]

    /// A pattern's sizes are canvas pixels on a layer kept at any scale. A
    /// pattern is drawn from nothing, so it is read against the full-size one:
    /// nearer to it than to the full-size pattern with its sizes divided by
    /// the scale, which is what sizes read in texels drew.
    @Test(arguments: sizedGenerators, [0.5, 2.0])
    func aSizedPatternKeepsItsSizesOnAScaledLayer(_ item: Sized<Generator>, layerScale: Double) throws {
        func pattern(_ k: Double, _ scale: Double) throws -> Frame {
            try Self.render { s in
                s.background(.clear)
                s.drawImage(s.generate(item.make(k), scale: scale).image, 0, 0, 96, 96)
            }
        }
        let right = try pattern(1, 1), got = try pattern(1, layerScale), texels = try pattern(1 / layerScale, 1)
        let off = got.mean(against: right), gap = texels.mean(against: right)
        #expect(gap > 0.002, "\(item.name): the same sizes divided by \(layerScale) change the pattern by only \(gap), which proves nothing")
        #expect(off < 0.5 * gap, "\(item.name) on a layer at \(layerScale) is \(off) from the full-size pattern; sizes read in texels would be \(gap) from it")
    }

    /// A smooth hill of light and a few soft marks: nothing in it is sharper
    /// than a few pixels, so a filter that reads slopes reads the same ones on
    /// a layer kept finer.
    static func smooth(_ filter: Filter?, layerScale: Double, softness: Double = 2.5) throws -> Frame {
        try render(side: 128) { s in
            s.background(.clear)
            let layer = layerScale == 1 ? s.makeRenderTarget() : s.makeRenderTarget(scale: layerScale)
            s.withTarget(layer) {
                s.background(Color(linear: 0.02, green: 0.02, blue: 0.02))
                s.noStroke()
                for i in 0..<40 {
                    let t = Double(i) / 40
                    s.fill(Color(linear: 0.05 + 0.6 * t, green: 0.04 + 0.5 * t * t, blue: 0.1 + 0.3 * t, alpha: 0.12))
                    s.drawCircle(52 + 14 * t, 60 + 6 * t, 56 * (1 - t) + 2)
                    s.drawCircle(96 - 10 * t, 36 + 8 * t, 30 * (1 - t) + 1)
                }
            }
            let soft = layer.filtered(.gaussianBlur(radius: softness))
            s.drawImage((filter.map { soft.filtered($0) } ?? soft).image, 0, 0, 128, 128)
        }
    }

    nonisolated static let reachOnePixel: [Named] = [
        Named(name: "edges", filter: .edges(amount: 4)), Named(name: "sharpen", filter: .sharpen(amount: 12)),
        Named(name: "emboss", filter: .emboss(amount: 8)), Named(name: "normalMap", filter: .normalMap(amount: 4)),
        Named(name: "relight", filter: .relight(.metal)), Named(name: "schlieren", filter: .schlieren(amount: 4)),
        Named(name: "toon", filter: .toon(levels: 4, edges: 4)),
        Named(name: "chromaticAberration along edges", filter: .chromaticAberration(amount: 0.08, mode: .edges)),
    ]

    /// A filter with no size reaches one pixel, and that pixel is the canvas's:
    /// on a layer kept at twice the size it changes a smooth picture by as much
    /// as it does on a full-size one. Read in texels, a slope there is half as
    /// steep and a second difference a quarter.
    @Test(arguments: reachOnePixel)
    func aOnePixelReachIsACanvasPixel(_ item: Named) throws {
        // A second difference of a very smooth picture is too small to read,
        // so the two filters that take one read a picture half as soft.
        let softness = (item.name == "sharpen" || item.name.hasPrefix("chromatic")) ? 1.2 : 2.5
        func strength(_ scale: Double) throws -> Double {
            try Self.smooth(item.filter, layerScale: scale, softness: softness)
                .mean(against: try Self.smooth(nil, layerScale: scale, softness: softness))
        }
        let full = try strength(1), fine = try strength(2)
        #expect(full > 0.0005, "\(item.name) changes the smooth picture by only \(full), which proves nothing")
        #expect(abs(fine / full - 1) < 0.2, "\(item.name) changes the picture by \(fine) on a layer at 2 and by \(full) at 1")
    }

    /// The median takes a two-pixel speck out at any layer scale: its three by
    /// three is three canvas pixels across, never three texels.
    @Test(arguments: [1.0, 2.0])
    func theMedianTakesOutASpeckAtAnyLayerScale(layerScale: Double) throws {
        func specks(_ filter: Filter?) throws -> Double {
            try Self.render(side: 96) { s in
                s.background(.clear)
                let layer = layerScale == 1 ? s.makeRenderTarget() : s.makeRenderTarget(scale: layerScale)
                s.withTarget(layer) {
                    s.background(.black); s.noStroke(); s.fill(.white)
                    for j in 0..<8 { for i in 0..<8 {
                        let x = Double(8 + i * 11), y = Double(8 + j * 11)
                        s.drawPolygon([Vector2(x, y), Vector2(x + 2, y), Vector2(x + 2, y + 2), Vector2(x, y + 2)])
                    } }
                }
                s.drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0, 96, 96)
            }.sum(0)
        }
        let before = try specks(nil), after = try specks(.median())
        #expect(before > 200, "the specks are there: \(before)")
        #expect(after < 0.05 * before, "on a layer at \(layerScale) the median left \(after) of \(before)")
    }

    /// The straight color of a one-color shape is that color at every pixel a
    /// filter leaves it on: no dark fringe, no bright one, however thin the
    /// coverage gets. Alpha is premultiplied through the chain.
    nonisolated static let keepsColor: [Named] = [
        Named(name: "gaussianBlur", filter: .gaussianBlur(radius: 4)), Named(name: "boxBlur", filter: .boxBlur(radius: 4)),
        Named(name: "motionBlur", filter: .motionBlur(distance: 0.05)), Named(name: "radialBlur", filter: .radialBlur(amount: 0.1)),
        Named(name: "tiltShift", filter: .tiltShift(radius: 6)), Named(name: "progressiveBlur", filter: .progressiveBlur(radius: 6)),
        Named(name: "bilateral", filter: .bilateral()), Named(name: "median", filter: .median()),
        Named(name: "swirl", filter: .swirl()), Named(name: "wave", filter: .wave()),
        Named(name: "pixelate", filter: .pixelate(size: 6)), Named(name: "lensDistortion", filter: .lensDistortion()),
        Named(name: "oilPaint", filter: .oilPaint()),
    ]

    @Test(arguments: keepsColor)
    func aShapesColorSurvivesAFilterAtEveryCoverage(_ item: Named) throws {
        let ink = SIMD3(0.8, 0.1, 0.3)
        let f = try Self.disc(radius: 20, color: Color(linear: ink, alpha: 0.5), filter: item.filter)
        var worst = 0.0
        for y in 0..<f.height { for x in 0..<f.width {
            let p = f.at(x, y)
            guard p.w > 0.02 else { continue }
            for c in 0..<3 { worst = max(worst, abs(p[c] / p.w / ink[c] - 1)) }
        } }
        #expect(worst < 0.006, "\(item.name): the straight color strays by \(worst * 100)%")
    }

    // MARK: Glows

    nonisolated static let glows: [Named] = [
        Named(name: "bloom", filter: .bloom()), Named(name: "strong bloom", filter: .bloom(threshold: 0.2, amount: 2, radius: 6)),
        Named(name: "halation", filter: .halation()), Named(name: "outerGlow", filter: .outerGlow()),
        Named(name: "edgeGlow", filter: .edgeGlow()), Named(name: "lightLeak", filter: .lightLeak()),
    ]

    /// A glow adds light: no channel of any pixel is darker for it, and it
    /// changes the picture.
    @Test(arguments: glows)
    func aGlowNeverDarkens(_ item: Named) throws {
        let plain = try Self.plain(), out = try Self.filtered(item.filter)
        var darkest = 0.0
        for i in out.rgba.indices { darkest = min(darkest, Double(out.rgba[i]) - Double(plain.rgba[i])) }
        #expect(darkest >= 0, "\(item.name) left a channel \(-darkest) darker")
        #expect(out.worst(against: plain).by > 0.05, "\(item.name) changed nothing")
    }

    /// A glow whose threshold no pixel reaches leaves the frame as it was.
    @Test func aThresholdAboveTheBrightestPixelLeavesTheFrame() throws {
        let plain = try Self.plain()
        #expect(try Self.filtered(.bloom(threshold: 50)).worst(against: plain).by == 0)
        #expect(try Self.filtered(.halation(threshold: 50)).worst(against: plain).by == 0)
    }

    // MARK: Filters against each other and against plain drawing

    /// A filter that undoes another leaves the picture: two stops up then two
    /// down and a channel swap done twice to the number, a negative of a
    /// negative within two steps of the layer's precision.
    @Test func filtersThatUndoEachOtherLeaveThePicture() throws {
        func chain(_ filters: [Filter]) throws -> Frame {
            try Self.render { s in
                s.background(.clear)
                let layer = s.makeRenderTarget()
                s.withTarget(layer) { Self.picture(s) }
                var shown = layer
                for f in filters { shown = shown.filtered(f) }
                s.drawImage(shown.image, 0, 0)
            }
        }
        let plain = try Self.plain()
        #expect(try chain([.exposure(stops: 1), .exposure(stops: -1)]).worst(against: plain).by == 0)
        #expect(try chain([.channelMixer(.swapping(.red, .blue)), .channelMixer(.swapping(.red, .blue))]).worst(against: plain).by == 0)
        #expect(try chain([.invert(), .invert()]).worst(against: plain).by < 0.002)
    }

    /// Vibrance turned down dulls a color toward the gray of its own
    /// brightness and stops there: at -1 every color is that gray, and on the
    /// way no color passes through gray into the opposite hue.
    @Test(arguments: [-1.0, -0.75, -0.5, -0.25])
    func vibranceTurnedDownStopsAtGray(amount: Double) throws {
        let red = try flat(32, Color(linear: 1, green: 0, blue: 0), .vibrance(amount: amount)).at(16, 16)
        let gray = 0.2126
        #expect(red.x >= red.y - 0.002 && red.x >= red.z - 0.002, "at \(amount) pure red came back \(fmt(red)), its hue turned")
        #expect(abs(red.y - red.z) < 0.002, "at \(amount) pure red came back \(fmt(red))")
        if amount <= -0.5 {
            #expect(abs(red.x - gray) < 0.003 && abs(red.y - gray) < 0.003, "at \(amount) pure red came back \(fmt(red)), where its gray is \(gray)")
        }
        // A muted color is dulled less than a vivid one, and at -1 is gray too.
        let muted = try flat(32, Color(linear: 0.5, green: 0.4, blue: 0.4), .vibrance(amount: amount)).at(16, 16)
        #expect(muted.x >= muted.y - 0.002, "at \(amount) a muted red came back \(fmt(muted))")
        if amount == -1 { #expect(abs(muted.x - muted.y) < 0.003, "at -1 a muted red came back \(fmt(muted))") }
    }

    /// Colorama lays the hue wheel along brightness: a pixel takes the wheel's
    /// color for its own brightness and keeps its brightness. So a ramp of
    /// written grays comes back as the wheel in order, one turn from black to
    /// white, each column as bright as its gray, black still black; `shift`
    /// turns the wheel; and a color keeps its own value under its new hue.
    @Test(arguments: [(1.0, 0.0), (2.0, 0.0), (1.0, 0.25)])
    func coloramaLaysTheWheelAlongBrightness(cycles: Double, shift: Double) throws {
        let f = try Self.render(side: 128) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            s.withTarget(layer) {
                s.noStroke()
                for x in 0..<128 {
                    s.fill(Color(white: (Double(x) + 0.5) / 128))
                    s.drawPolygon([Vector2(Double(x), 0), Vector2(Double(x) + 1, 0), Vector2(Double(x) + 1, 128), Vector2(Double(x), 128)])
                }
            }
            s.drawImage(layer.filtered(.colorama(cycles: cycles, shift: shift)).image, 0, 0)
        }
        var worst = 0.0
        for x in stride(from: 2, to: 128, by: 5) {
            let gray = (Double(x) + 0.5) / 128
            let turn = gray * cycles + shift
            let want = Color(hue: turn - turn.rounded(.down), saturation: 1, brightness: gray).linearRGBA
            let got = f.at(x, 64)
            for c in 0..<3 { worst = max(worst, abs(got[c] - Double(want[c]))) }
        }
        #expect(worst < 0.02, "a written gray ramp under \(cycles) turns shifted \(shift) strays from the wheel by \(worst)")
        #expect(f.at(0, 64).x < 0.001 && f.at(0, 64).w > 0.99, "black came back \(fmt(f.at(0, 64)))")
        // A color keeps its value, the largest channel as written.
        let color = try flat(32, Color(red: 0.2, green: 0.7, blue: 0.9), .colorama(cycles: cycles, shift: shift)).at(16, 16)
        let value = Color.linearToSrgb(max(color.x, color.y, color.z))
        #expect(abs(value - 0.9) < 0.01, "a color whose largest channel is written 0.9 came back with \(value)")
    }

    /// `mirror` keeps one half of the layer and shows its reflection on the
    /// other, and `tile(count: 2)` is four half-size copies, each what
    /// `drawImage` draws at half size.
    @Test func mirrorAndTileAreTheLayerDrawnAgain() throws {
        let plain = try Self.plain(), mirrored = try Self.filtered(.mirror())
        var kept = 0.0, reflected = 0.0
        for y in 0..<96 { for x in 0..<48 { for c in 0..<4 {
            kept = max(kept, abs(mirrored.value(x, y, c) - plain.value(x, y, c)))
            reflected = max(reflected, abs(mirrored.value(95 - x, y, c) - plain.value(x, y, c)))
        } } }
        #expect(kept == 0 && reflected == 0, "the kept half strays by \(kept), the reflected one by \(reflected)")
        let tiled = try Self.filtered(.tile(count: 2))
        let drawn = try Self.render { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            s.withTarget(layer) { Self.picture(s) }
            for j in 0..<2 { for i in 0..<2 { s.drawImage(layer.image, Double(i) * 48, Double(j) * 48, 48, 48) } }
        }
        #expect(tiled.worst(against: drawn).by == 0, "tiling by two: \(describe(tiled.worst(against: drawn)))")
    }

    /// Mirroring flips every other cell, and the first is not one of them: the
    /// first cell of a mirrored tiling is the first cell of the plain one, and
    /// the cell beside it is that cell's reflection in the line between them.
    /// (One mirrored tile is the picture itself, held with the neutral settings.)
    @Test func aMirroredTilingStartsWithThePictureAndReflectsTheNext() throws {
        let tiled = try Self.filtered(.tile(count: 2)), mirrored = try Self.filtered(.tile(count: 2, mirrored: true))
        var first = 0.0, across = 0.0, down = 0.0
        for y in 0..<48 { for x in 0..<48 { for c in 0..<4 {
            first = max(first, abs(mirrored.value(x, y, c) - tiled.value(x, y, c)))
            across = max(across, abs(mirrored.value(95 - x, y, c) - tiled.value(x, y, c)))
            down = max(down, abs(mirrored.value(x, 95 - y, c) - tiled.value(x, y, c)))
        } } }
        #expect(first < 0.001, "the first cell of a mirrored tiling strays from the plain one by \(first)")
        #expect(across < 0.001 && down < 0.001, "the next cell is not the reflection: \(across) across, \(down) down")
    }

    /// A kaleidoscope shows the wedge of the picture it is turned to: the one
    /// from the picture's middle toward its right edge, as wide as half a
    /// segment. A mark inside that wedge shows in every wedge of the wheel, and
    /// at its own place among them; a mark at the same place on the far side of
    /// the middle is in no wedge and shows nowhere.
    @Test func aKaleidoscopeShowsTheWedgeItIsTurnedTo() throws {
        // Four segments: the wedge kept runs from the +x axis a quarter of a
        // right angle down, so a mark 22.5 degrees below the axis sits in its middle.
        let away = SIMD2(28 * cos(Double.pi / 8), 28 * sin(Double.pi / 8))
        func wheel(markAt sign: Double, folded: Bool = true) throws -> Frame {
            try Self.render { s in
                s.background(.clear)
                let layer = s.makeRenderTarget()
                s.withTarget(layer) { s.noStroke(); s.fill(.white); s.drawCircle(48 + sign * away.x, 48 + sign * away.y, 5) }
                s.drawImage((folded ? layer.filtered(.kaleidoscope(segments: 4, angle: 0)) : layer).image, 0, 0)
            }
        }
        let mark = try wheel(markAt: 1, folded: false).sum(3), shown = try wheel(markAt: 1), hidden = try wheel(markAt: -1)
        #expect(abs(shown.sum(3) / (8 * mark) - 1) < 0.05, "a mark in the wedge shows as \(shown.sum(3) / mark) marks where the wheel has eight")
        #expect(shown.value(Int(48 + away.x), Int(48 + away.y), 3) > 0.99, "the mark is not at its own place")
        #expect(hidden.sum(3) < 0.01 * mark, "a mark across the middle from the wedge shows as \(hidden.sum(3) / mark) marks")
    }

    nonisolated static let roundWarps: [Named] = [
        Named(name: "swirl", filter: .swirl()), Named(name: "bulge", filter: .bulge()), Named(name: "ripple", filter: .ripple()),
        Named(name: "lensDistortion", filter: .lensDistortion()), Named(name: "radialBlur", filter: .radialBlur()),
    ]

    /// A warp measured from the center keeps a centered disc round on a layer
    /// twice as wide as it is tall.
    @Test(arguments: roundWarps)
    func aWarpAboutTheCenterStaysRound(_ item: Named) throws {
        let out = Self.spread(try Self.disc(side: 96, wide: 192, radius: 30, filter: item.filter))
        #expect(abs(out.varX.squareRoot() / out.varY.squareRoot() - 1) < 0.001,
                "\(item.name) on a 2:1 layer spread the disc \(out.varX.squareRoot()) across and \(out.varY.squareRoot()) down")
    }

    /// A motion blur's `distance` is one length whatever its angle, and what it
    /// leaves of a thin mark is a streak.
    @Test func aMotionBlurIsOneLengthAtAnyAngle() throws {
        func smeared(_ angle: Double) throws -> (x: Double, y: Double) {
            let base = Self.spread(try Self.disc(side: 96, wide: 192, radius: 3, filter: nil))
            let f = Self.spread(try Self.disc(side: 96, wide: 192, radius: 3, filter: .motionBlur(angle: angle, distance: 0.25)))
            return ((f.varX - base.varX).squareRoot(), max(0, f.varY - base.varY).squareRoot())
        }
        let across = try smeared(0), down = try smeared(.pi / 2), diagonal = try smeared(.pi / 4)
        #expect(abs(down.y / across.x - 1) < 0.03, "the smear is \(across.x) across and \(down.y) down")
        #expect(abs(diagonal.y / diagonal.x - 1) < 0.03, "at 45 degrees the smear runs \(diagonal.x) across and \(diagonal.y) down")
        // The length is `distance` of the layer's height, 24 px here, and a
        // streak that long spreads a mark by its length over the root of twelve.
        let streak = 0.25 * 96 / 12.0.squareRoot()
        #expect(abs(across.x / streak - 1) < 0.03, "a smear of 24 px spreads a mark by \(across.x), where a streak that long spreads it \(streak)")
        let comb = try Self.render(side: 128) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            s.withTarget(layer) { s.noStroke(); s.fill(.white); s.drawRect(64, 0, 1, 128) }
            s.drawImage(layer.filtered(.motionBlur(angle: 0, distance: 0.5)).image, 0, 0)
        }
        let inside = (40..<88).map { comb.value($0, 64, 3) }
        #expect(inside.min()! > inside.max()! * 0.9, "inside the streak the coverage runs from \(inside.min()!) to \(inside.max()!)")
        // The line's light is all still there, spread along the streak.
        let line = try Self.render(side: 128) { s in
            s.background(.clear); s.noStroke(); s.fill(.white); s.drawRect(64, 0, 1, 128)
        }.sum(3, y: 64..<65)
        #expect(abs(comb.sum(3, y: 64..<65) / line - 1) < 0.01, "a row of the smeared line holds \(comb.sum(3, y: 64..<65)) of the line's \(line)")
    }

    /// The two rows a motion blur takes are one long row of taps: together they
    /// span the smear's length, no tap is over a texel from the next up to
    /// 4,096 texels, neither row asks for more than the fragment's 64, and a
    /// smear of no length is one tap.
    @Test(arguments: [0.0, 0.4, 1.0, 6.4, 16.0, 43.2, 64.0, 540.0, 1920.0, 4096.0, 100_000.0, .infinity, .nan])
    func aMotionBlursTwoRowsAreOneLongRow(length: Double) {
        let taps = Filter.motionBlurTaps(length: length)
        let held = length.isFinite ? min(length, 65536) : 0
        #expect((1...64).contains(taps.fine) && (1...64).contains(taps.coarse))
        #expect(abs(Double(taps.fine * taps.coarse) * taps.fineStep - held) < 1e-9 * max(1, held), "the taps span \(Double(taps.fine * taps.coarse) * taps.fineStep) of \(held)")
        #expect(abs(taps.coarseStep - Double(taps.fine) * taps.fineStep) < 1e-9 * max(1, held), "a tap of the second row is not one first row from the next")
        if held <= 4096 { #expect(taps.fineStep <= 1, "taps \(taps.fineStep) texels apart leave gaps") }
        if held == 0 { #expect(taps.fine == 1 && taps.coarse == 1) }
    }

    /// A flat field has no contour lines, whatever its brightness.
    @Test func contourLeavesAFlatFieldFlat() throws {
        let gray = try flat(32, Color(linear: 0.33, green: 0.33, blue: 0.33), .contour(levels: 10, amount: 1)).at(16, 16)
        #expect(abs(gray.x - 0.33) < 0.002, "a flat 0.33 came back \(gray.x)")
        let white = try flat(32, .white, .contour(levels: 10, amount: 1)).at(16, 16)
        #expect(white.x > 0.99, "flat white came back \(white.x)")
    }

    /// A slope has its lines: a ramp from black to white under four levels is
    /// crossed by three dark lines, each where the ramp passes a level, and
    /// between them the ramp is as it was.
    @Test func contourDrawsALineWhereARampCrossesALevel() throws {
        func ramp(_ filter: Filter?) throws -> Frame {
            try Self.render(side: 128) { s in
                s.background(.clear)
                let layer = s.makeRenderTarget()
                s.withTarget(layer) {
                    s.noStroke()
                    for x in 0..<128 {
                        let v = (Double(x) + 0.5) / 128
                        s.fill(Color(linear: v, green: v, blue: v))
                        s.drawPolygon([Vector2(Double(x), 0), Vector2(Double(x) + 1, 0), Vector2(Double(x) + 1, 128), Vector2(Double(x), 128)])
                    }
                }
                s.drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
            }
        }
        let plain = try ramp(nil), lined = try ramp(.contour(levels: 4, amount: 1))
        for level in 1...3 {
            let x = level * 32
            let darkest = (x - 2...x + 1).map { lined.value($0, 64) / plain.value($0, 64) }.min()!
            #expect(darkest < 0.6, "where the ramp crosses level \(level) the line leaves \(darkest) of it")
            #expect(abs(lined.value(x + 16, 64) - plain.value(x + 16, 64)) < 0.002, "between two lines the ramp moved")
        }
    }

    /// A dither trades levels for a pattern and keeps the brightness: the mean
    /// of a flat field is the field's value.
    @Test(arguments: [(0.5, 2.0), (0.25, 2.0), (0.6, 4.0), (0.5, 8.0)])
    func anOrderedDitherKeepsTheMeanBrightness(value: Double, levels: Double) throws {
        let out = try flat(64, Color(linear: value, green: value, blue: value), .dither(levels: levels))
        let got = mean(out).x
        #expect(abs(got - value) < 0.02, "a flat \(value) dithered to \(levels) levels has a mean of \(got)")
        // And every pixel sits on one of the levels: a whole number of steps
        // from black to white.
        var off = 0.0
        for y in 0..<64 { for x in 0..<64 { let v = out.value(x, y) * (levels - 1); off = max(off, abs(v - v.rounded())) } }
        #expect(off < 0.005, "a pixel sits \(off) of a step off the nearest of \(levels) levels")
    }

    nonisolated static let inked: [Named] = [
        Named(name: "hatching", filter: .hatching(foreground: .black, background: Color(white: 1, alpha: 0))),
        Named(name: "xdog", filter: .xdog(foreground: .black, background: Color(white: 1, alpha: 0))),
        Named(name: "crosshatch", filter: .crosshatch(foreground: .black, background: Color(white: 1, alpha: 0))),
        Named(name: "lineScreen", filter: .lineScreen(foreground: .black, background: Color(white: 1, alpha: 0))),
    ]

    /// What a filter or a generator writes is premultiplied like everything a
    /// layer holds: no color is brighter than its own coverage allows.
    @Test(arguments: inked)
    func whatAFilterWritesIsPremultiplied(_ item: Named) throws {
        let f = try Self.filtered(item.filter)
        var past = 0.0, stray = 0.0, inked = 0.0
        for y in 0..<96 { for x in 0..<96 {
            let p = f.at(x, y)
            past = max(past, max(p.x, p.y, p.z) - p.w); stray = max(stray, max(p.x, p.y, p.z)); inked += p.w
        } }
        #expect(past < 0.002, "\(item.name) wrote a color \(past) past its own alpha")
        // Black ink over a background that is clear is black wherever it is,
        // at the soft edge of a mark too: the clear color brings none of its own.
        #expect(stray < 0.002, "\(item.name) left \(stray) of the clear background's white in its ink")
        #expect(inked > 40, "\(item.name) drew no ink to read")
    }

    struct NamedPattern: Sendable, CustomTestStringConvertible {
        let name: String
        let generator: Generator
        var testDescription: String { name }
    }

    /// The six basic patterns in a half-clear white over nothing.
    nonisolated static let seeThroughPatterns: [NamedPattern] = {
        let ink = Color(white: 1, alpha: 0.5), none = Color.clear
        return [
            NamedPattern(name: "checkers", generator: .checkers(scale: 4, foreground: ink, background: none)),
            NamedPattern(name: "gridLines", generator: .gridLines(scale: 4, weight: 0.3, foreground: ink, background: none)),
            NamedPattern(name: "bars", generator: .bars(scale: 4, foreground: ink, background: none)),
            NamedPattern(name: "noise", generator: .noise(scale: 4, foreground: ink, background: none)),
            NamedPattern(name: "cellular", generator: .cellular(scale: 4, foreground: ink, background: none)),
            NamedPattern(name: "gaborNoise", generator: .gaborNoise(wavelength: 12, foreground: ink, background: none)),
        ]
    }()

    /// A pattern's see-through color is held as a layer holds one, under its
    /// alpha: half-clear white is half of white at half coverage, at every
    /// pixel and every share of the pattern.
    @Test(arguments: seeThroughPatterns)
    func whatAPatternWritesIsPremultiplied(_ item: NamedPattern) throws {
        let f = try Self.render(side: 64) { s in
            s.background(.clear)
            s.drawImage(s.generate(item.generator).image, 0, 0)
        }
        var off = 0.0, most = 0.0
        for y in 0..<64 { for x in 0..<64 {
            let p = f.at(x, y)
            for c in 0..<3 { off = max(off, abs(p[c] - p.w)) }
            most = max(most, p.w)
        } }
        #expect(off < 0.002, "\(item.name) holds a white \(off) away from its own coverage")
        #expect(most > 0.4 && most < 0.502, "\(item.name) at its fullest covers \(most), where the color's alpha is a half")
    }

    @Test func whatAGlitchWritesIsPremultiplied() throws {
        let glitch = try Self.render(side: 96) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            s.withTarget(layer) { s.noStroke(); s.fill(.white); s.drawRect(30, 0, 36, 96) }
            s.drawImage(layer.filtered(.glitch(amount: 0.3, seed: 1)).image, 0, 0)
        }
        var past = 0.0
        for y in 0..<96 { for x in 0..<96 { let p = glitch.at(x, y); past = max(past, max(p.x, p.y, p.z) - p.w) } }
        #expect(past < 0.002, "a glitched bar wrote a color \(past) past its own alpha")
    }

    /// Grain is noise at any seed, the frame count of a long run included.
    @Test(arguments: [0.0, 200_000])
    func grainStaysNoiseAtAnySeed(seed: Double) throws {
        let g = try flat(64, Color(linear: 0.4, green: 0.4, blue: 0.4), .grain(amount: 0.5, seed: seed))
        var values = Set<Float>()
        for i in stride(from: 0, to: g.rgba.count, by: 4) { values.insert(g.rgba[i]) }
        #expect(values.count > 800, "at seed \(seed) the grain holds \(values.count) distinct values")
        // The next frame's grain is another pattern, not this one again.
        let next = try flat(64, Color(linear: 0.4, green: 0.4, blue: 0.4), .grain(amount: 0.5, seed: seed + 1))
        var same = 0
        for i in stride(from: 0, to: g.rgba.count, by: 4) where g.rgba[i] == next.rgba[i] { same += 1 }
        #expect(same < 200, "at seed \(seed) and the one after, \(same) of 4,096 pixels hold the same grain")
    }

    /// Film grain is even about each displayed value, so a flat gray keeps its
    /// average as displayed. The light it sends out rises with it, since the
    /// lighter half of the grain adds more light than the darker half takes
    /// away: a little at the default amount, about a fifth at 0.2.
    @Test(arguments: [(0.05, 0.005, 0.03), (0.2, 0.15, 0.28)])
    func filmGrainKeepsAFlatsMeanAsDisplayed(amount: Double, least: Double, most: Double) throws {
        let out = try flat(128, Color(white: 0.5), .filmGrain(amount: amount, size: 1))
        var displayed = 0.0, light = 0.0
        for i in stride(from: 0, to: out.rgba.count, by: 4) {
            let v = Double(out.rgba[i])
            light += v; displayed += Color.linearToSrgb(v)
        }
        let count = Double(out.rgba.count / 4)
        displayed /= count; light /= count
        let lift = light / Color.srgbToLinear(0.5) - 1
        #expect(abs(displayed - 0.5) < 0.004, "at \(amount) a flat mid-gray is displayed at a mean of \(displayed)")
        #expect(lift > least && lift < most, "at \(amount) the flat sends out \(lift * 100)% more light")
    }

    // MARK: Combines

    struct Mixed: Sendable, CustomTestStringConvertible {
        let name: String
        let op: Combine
        /// What the other layer holds: 0 white, 1 black, 2 nothing, 3 a picture, 4 the gray that means no shift.
        let aux: Int
        var testDescription: String { name }
    }

    static func auxiliary(_ kind: Int, _ s: Probe) {
        switch kind {
        case 0: s.background(.white)
        case 1: s.background(.black)
        case 2: s.noStroke(); s.fill(.white); s.drawCircle(-50, -50, 2)
        case 3: s.background(Color(linear: 0.1, green: 0.4, blue: 0.2)); s.noStroke(); s.fill(.orange); s.drawCircle(48, 48, 30)
        default: s.background(Color(white: 0.5))
        }
    }

    static func combined(_ op: Combine, aux kind: Int) throws -> Frame {
        try render { s in
            s.background(.clear)
            let base = s.makeRenderTarget()
            s.withTarget(base) { picture(s) }
            let other = s.makeRenderTarget()
            s.withTarget(other) { auxiliary(kind, s) }
            s.drawImage(base.combined(with: other, op).image, 0, 0)
        }
    }

    nonisolated static let returnsBase: [Mixed] = [
        Mixed(name: "mask by white", op: .mask(), aux: 0), Mixed(name: "mask by opaque, alpha", op: .mask(channel: .alpha), aux: 0),
        Mixed(name: "inverted mask by black", op: .mask(inverted: true), aux: 1),
        Mixed(name: "mix 0", op: .mix(amount: 0), aux: 3), Mixed(name: "wipe 0", op: .wipe(.directional(), progress: 0), aux: 3),
        Mixed(name: "displace 0", op: .displace(amount: 0), aux: 3), Mixed(name: "displace by mid-gray", op: .displace(amount: 0.1), aux: 4),
        Mixed(name: "displace by nothing", op: .displace(amount: 0.1), aux: 2),
        Mixed(name: "streaks along mid-gray", op: .lineIntegralConvolution(length: 0.1), aux: 4),
        Mixed(name: "streaks along nothing", op: .lineIntegralConvolution(length: 0.1), aux: 2),
        Mixed(name: "disperse by black", op: .disperse(amount: 0.02), aux: 1), Mixed(name: "disperse 0", op: .disperse(amount: 0), aux: 0),
        Mixed(name: "paintMix 0", op: .paintMix(amount: 0), aux: 3), Mixed(name: "paintMix with nothing", op: .paintMix(), aux: 2),
        Mixed(name: "seamlessClone of nothing", op: .seamlessClone(), aux: 2),
        Mixed(name: "streaks of length 0", op: .lineIntegralConvolution(length: 0), aux: 4),
        Mixed(name: "anaglyph 0", op: .anaglyph(amount: 0), aux: 4),
    ]

    /// A combine at the setting, or over the other layer, that asks for none of
    /// its effect is its base, to the number.
    @Test(arguments: returnsBase)
    func aCombineAskedForNothingReturnsItsBase(_ item: Mixed) throws {
        let w = try Self.combined(item.op, aux: item.aux).worst(against: try Self.plain())
        #expect(w.by == 0, "\(item.name): \(describe(w))")
    }

    /// A mask by black, by nothing, or by no alpha keeps nothing.
    @Test func aMaskByNothingKeepsNothing() throws {
        for (name, op, aux) in [("black", Combine.mask(), 1), ("an empty layer", .mask(), 2), ("no alpha", .mask(channel: .alpha), 2)] {
            let out = try Self.combined(op, aux: aux)
            #expect(out.rgba.allSatisfy { $0 == 0 }, "a mask by \(name) kept something")
        }
    }

    /// `mix` and a wipe show the base at 0 and the other layer at 1, and `mix`
    /// is the straight line between them at every amount.
    @Test func mixIsTheStraightLineBetweenItsLayers() throws {
        let plain = try Self.plain()
        let other = try Self.render { s in s.background(.clear); Self.auxiliary(3, s) }
        #expect(try Self.combined(.mix(amount: 1), aux: 3).worst(against: other).by == 0)
        #expect(try Self.combined(.wipe(.directional(), progress: 1), aux: 3).worst(against: other).by == 0)
        for t in [0.25, 0.5, 0.75] {
            let out = try Self.combined(.mix(amount: t), aux: 3)
            var worst = 0.0
            for i in out.rgba.indices {
                let want = Double(plain.rgba[i]) + (Double(other.rgba[i]) - Double(plain.rgba[i])) * t
                worst = max(worst, abs(Double(out.rgba[i]) - want))
            }
            #expect(worst < 0.003, "mix at \(t) strays from the line by \(worst)")
        }
    }

    // MARK: A layer read as numbers

    /// A base whose red is its own column and whose green is its own row, so a
    /// shift can be read off the result: 96 strips each way, one texel wide,
    /// drawn as polygons since a rectangle's edge ramp spills into its neighbors.
    static func coordinates(_ s: Sketch) {
        s.noStroke()
        for i in 0 ..< 96 {
            let a = Double(i), b = Double(i + 1)
            s.blendMode(.normal)
            s.fill(Color(linear: a / 96, green: 0, blue: 0))
            s.drawPolygon([Vector2(a, 0), Vector2(b, 0), Vector2(b, 96), Vector2(a, 96)])
        }
        s.blendMode(.add)
        for i in 0 ..< 96 {
            let a = Double(i), b = Double(i + 1)
            s.fill(Color(linear: 0, green: a / 96, blue: 0))
            s.drawPolygon([Vector2(0, a), Vector2(96, a), Vector2(96, b), Vector2(0, b)])
        }
        s.blendMode(.normal)
    }

    /// The picture, or the coordinate base, moved by `map`.
    static func displaced(coordinates: Bool = false, amount: Double = 0.1,
                          _ map: (@MainActor (Probe) -> Void)?) throws -> Frame {
        try render { s in
            s.background(.clear)
            let base = s.makeRenderTarget()
            s.withTarget(base) { if coordinates { Self.coordinates(s) } else { Self.picture(s) } }
            guard let map else { s.drawImage(base.image, 0, 0); return }
            let field = s.makeRenderTarget()
            s.withTarget(field) { map(s) }
            s.drawImage(base.combined(with: field, .displace(amount: amount)).image, 0, 0)
        }
    }

    /// A displacement map's mid-gray is no shift, to the number: the gray a sketch
    /// writes, a picture's two middle levels, and the nothing around a map drawn
    /// on a clear layer.
    @Test func aDisplacementMapsMidGrayIsNoShift() throws {
        let plain = try Self.plain()
        let gray = try Self.displaced { $0.background(Color(white: 0.5)) }
        #expect(gray.worst(against: plain).by == 0, "a mid-gray map moved the layer: \(describe(gray.worst(against: plain)))")
        for level in [127.0, 128.0] {
            let eightBit = try Self.displaced { $0.background(Color(white: level / 255)) }
            #expect(eightBit.worst(against: plain).by == 0, "a map at \(Int(level)) of 255 moved the layer: \(describe(eightBit.worst(against: plain)))")
        }
        let clear = try Self.displaced { s in s.noStroke(); s.fill(Color(white: 0.5)); s.drawCircle(48, 48, 10) }
        #expect(clear.worst(against: plain).by == 0, "a map with nothing around its mark moved the layer: \(describe(clear.worst(against: plain)))")
    }

    /// A map's colors are the shift as written, and its alpha is the weight: a
    /// full push to the right moves the layer by the amount, a weaker one by its
    /// share less the step that counts as none, in the direction its two
    /// channels name, and a soft-edged mark on a clear layer pushes by its own
    /// alpha at every pixel, a ramp and never a step.
    @Test func aDisplacementMapPushesByItsColorUnderItsAlpha() throws {
        // What a texel reads is the place it came from, so the shift in pixels
        // is its reading less the unmoved base's own.
        let rest = try Self.displaced(coordinates: true, nil)
        func shift(_ f: Frame, _ x: Int, _ y: Int) -> SIMD2<Double> {
            SIMD2((f.value(x, y, 0) - rest.value(x, y, 0)) * 96, (f.value(x, y, 1) - rest.value(x, y, 1)) * 96)
        }
        // A push `d` from mid-gray, as written, in the share of the amount it asks for.
        func share(_ d: Double) -> Double { (d - 1.0 / 255) / (0.5 - 1.0 / 255) }

        let full = shift(try Self.displaced(coordinates: true) { $0.background(Color(red: 1, green: 0.5, blue: 0)) }, 40, 48)
        #expect(abs(full.x - 9.6) < 0.06 && full.y == 0, "a full push to the right moved a texel by \(full) px where the amount is 9.6 across")
        let quarter = shift(try Self.displaced(coordinates: true) { $0.background(Color(red: 0.625, green: 0.5, blue: 0)) }, 40, 48)
        #expect(abs(quarter.x - 9.6 * share(0.125)) < 0.06 && quarter.y == 0, "a quarter push moved a texel by \(quarter) px where \(9.6 * share(0.125)) across is due")
        let up = shift(try Self.displaced(coordinates: true) { $0.background(Color(red: 0.5, green: 0, blue: 0)) }, 40, 48)
        #expect(abs(up.y + 9.6) < 0.06 && up.x == 0, "a full push up moved a texel by \(up) px where the amount is 9.6 up")

        // A weak push keeps its direction: twice as far across as down.
        let weak = shift(try Self.displaced(coordinates: true, amount: 0.5) { $0.background(Color(red: 0.54, green: 0.52, blue: 0)) }, 40, 40)
        let length = 48 * share((0.04 * 0.04 + 0.02 * 0.02).squareRoot())
        #expect(abs(weak.x - length * 0.8944) < 0.08 && abs(weak.y - length * 0.4472) < 0.08,
                "a weak push of (0.04, 0.02) moved a texel by \(weak) px where (\(length * 0.8944), \(length * 0.4472)) is due")

        let mark: @MainActor (Probe) -> Void = { s in
            s.noStroke(); s.fill(Color(red: 1, green: 0.5, blue: 0)); s.drawCircle(36, 48, 14)
        }
        func soft(_ s: Probe) -> RenderTarget {
            let map = s.makeRenderTarget()
            s.withTarget(map) { mark(s) }
            return map.filtered(.gaussianBlur(radius: 6))
        }
        let weight = try Self.render { s in s.background(.clear); s.drawImage(soft(s).image, 0, 0) }
        let moved = try Self.render { s in
            s.background(.clear)
            let base = s.makeRenderTarget()
            s.withTarget(base) { Self.coordinates(s) }
            s.drawImage(base.combined(with: soft(s), .displace(amount: 0.1)).image, 0, 0)
        }
        var worst = 0.0, jump = 0.0, still = 0.0
        for x in 2 ..< 80 {
            let a = weight.value(x, 48, 3)
            worst = max(worst, abs(shift(moved, x, 48).x - 9.6 * a))
            jump = max(jump, abs(shift(moved, x + 1, 48).x - shift(moved, x, 48).x))
            if a == 0 { still = max(still, abs(shift(moved, x, 48).x)) }
        }
        #expect(worst < 0.1, "a soft mark's push strays from its alpha by \(worst) px")
        #expect(jump < 1.5, "the push steps by \(jump) px between two neighbors: a soft edge on the map is a hard edge in the push")
        #expect(still == 0, "a pixel the map never reached moved \(still) px")
    }

    /// A mask keeps the share its gray is written as, under the gray's own
    /// coverage: half for `Color(white: 0.5)`, a quarter for the same gray at
    /// half alpha, and a soft white mark's own alpha.
    @Test func aMaskKeepsTheShareItsGrayIsWrittenAs() throws {
        let plain = try Self.plain()
        func masked(_ mask: @escaping @MainActor (Probe) -> Void) throws -> Frame {
            try Self.render { s in
                s.background(.clear)
                let base = s.makeRenderTarget()
                s.withTarget(base) { Self.picture(s) }
                let other = s.makeRenderTarget()
                s.withTarget(other) { mask(s) }
                s.drawImage(base.combined(with: other, .mask()).image, 0, 0)
            }
        }
        func share(_ out: Frame, x: Range<Int>) -> Double { out.sum(3, x: x) / plain.sum(3, x: x) }
        let gray = try masked { $0.background(Color(white: 0.5)) }
        #expect(abs(share(gray, x: 0 ..< 96) - 0.5) < 0.002, "a mask of mid-gray kept \(share(gray, x: 0 ..< 96)) of the layer")
        let quarter = try masked { $0.background(Color(white: 0.25)) }
        #expect(abs(share(quarter, x: 0 ..< 96) - 0.25) < 0.002, "a mask of Color(white: 0.25) kept \(share(quarter, x: 0 ..< 96)) of the layer")
        // A half-clear gray over nothing, drawn as a polygon so its edge is a texel's.
        let veiled = try masked { s in
            s.noStroke(); s.fill(Color(white: 0.5, alpha: 0.5))
            s.drawPolygon([Vector2(0, 0), Vector2(48, 0), Vector2(48, 96), Vector2(0, 96)])
        }
        #expect(abs(share(veiled, x: 0 ..< 48) - 0.25) < 0.002, "mid-gray at half alpha kept \(share(veiled, x: 0 ..< 48)) of the layer")
        #expect(veiled.sum(3, x: 48 ..< 96) == 0, "a mask kept something where it holds nothing")

        func spot(_ s: Probe) -> RenderTarget {
            let layer = s.makeRenderTarget()
            s.withTarget(layer) { s.noStroke(); s.fill(.white); s.drawCircle(48, 48, 24) }
            return layer.filtered(.gaussianBlur(radius: 6))
        }
        let weight = try Self.render { s in s.background(.clear); s.drawImage(spot(s).image, 0, 0) }
        let lit = try Self.render { s in
            s.background(.clear)
            let base = s.makeRenderTarget()
            s.withTarget(base) { Self.picture(s) }
            s.drawImage(base.combined(with: spot(s), .mask()).image, 0, 0)
        }
        var worst = 0.0
        for i in 0 ..< lit.width * lit.height {
            let a = Double(weight.rgba[i * 4 + 3])
            for c in 0 ..< 4 { worst = max(worst, abs(Double(lit.rgba[i * 4 + c]) - Double(plain.rgba[i * 4 + c]) * a)) }
        }
        #expect(worst < 0.004, "a soft white mask strays from its own alpha by \(worst)")
    }

    /// The angle reading of a streak field takes the gray as written: at one turn
    /// `Color(white: 0.25)` is a quarter turn, straight down, and
    /// `Color(white: 0.5)` half a turn, straight across.
    @Test(arguments: [(0.25, false), (0.5, true)])
    func aStreakFieldsAngleIsTheGrayAsWritten(white: Double, across: Bool) throws {
        let out = try Self.render { s in
            s.background(.clear)
            let base = s.makeRenderTarget()
            s.withTarget(base) { s.noStroke(); s.fill(.white); s.drawCircle(48.3, 47.8, 3) }
            let field = s.makeRenderTarget()
            s.withTarget(field) { s.background(Color(white: white)) }
            s.drawImage(base.combined(with: field, .lineIntegralConvolution(length: 0.3, field: .angle(turns: 1))).image, 0, 0)
        }
        let spread = Self.spread(out)
        let (along, beside) = across ? (spread.varX, spread.varY) : (spread.varY, spread.varX)
        #expect(along > 12 * beside, "a field of Color(white: \(white)) smeared a dot \(spread.varX) across and \(spread.varY) down (variances)")
    }

    /// The angle runs on past black: a field below zero turns the other way by
    /// the same curve, so a signed field (a noise about zero) is one smooth
    /// field and not a flat half. An eighth of a turn each way smears a dot
    /// down to the right and up to the right.
    @Test(arguments: [1.0, -1.0])
    func aStreakFieldsAngleRunsOnBelowBlack(sign: Double) throws {
        let stored = sign * Color.srgbToLinear(0.125)
        let out = try Self.render { s in
            s.background(.clear)
            let base = s.makeRenderTarget()
            s.withTarget(base) { s.noStroke(); s.fill(.white); s.drawCircle(48.3, 47.8, 3) }
            let field = s.makeRenderTarget(precision: .float32)
            s.withTarget(field) { s.background(Color(linear: stored, green: stored, blue: stored)) }
            s.drawImage(base.combined(with: field, .lineIntegralConvolution(length: 0.3, field: .angle(turns: 1))).image, 0, 0)
        }
        // The smear's tilt: how its coverage leans, across against down, about its center.
        var sum = 0.0, mx = 0.0, my = 0.0
        for y in 0 ..< out.height { for x in 0 ..< out.width { let v = out.value(x, y, 3); sum += v; mx += v * Double(x); my += v * Double(y) } }
        mx /= sum; my /= sum
        var lean = 0.0, spread = 0.0
        for y in 0 ..< out.height { for x in 0 ..< out.width {
            let v = out.value(x, y, 3), dx = Double(x) - mx, dy = Double(y) - my
            lean += v * dx * dy; spread += v * (dx * dx + dy * dy)
        } }
        let tilt = 2 * lean / spread   // 1 along the falling diagonal, -1 along the rising one, 0 flat or upright
        #expect(tilt * sign > 0.8, "a field of \(sign < 0 ? "minus " : "")an eighth of a turn smeared a dot with a tilt of \(tilt), where \(sign) is the diagonal due")
    }

    /// A flat layer's normal map is the color a sketch would write for "no
    /// direction", and it moves nothing as a displacement map or a streak field.
    @Test func aFlatNormalMapIsMidGrayAsWritten() throws {
        let flat = try Self.render(side: 64) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            s.withTarget(layer) { s.background(Color(white: 0.3)) }
            s.drawImage(layer.filtered(.normalMap(amount: 4)).image, 0, 0)
        }
        let half = Color.srgbToLinear(0.5)
        let want = [half, half, 1.0]
        let got = flat.at(32, 32)
        for c in 0 ..< 3 {
            #expect(abs(got[c] - want[c]) < 0.0005, "a flat layer's normal map holds \(fmt(got)) where the color written as (0.5, 0.5, 1) is stored as \(want)")
        }
        let plain = try Self.plain()
        for (name, op) in [("displace", Combine.displace(amount: 0.1)), ("streaks", .lineIntegralConvolution(length: 0.1))] {
            let out = try Self.render { s in
                s.background(.clear)
                let base = s.makeRenderTarget()
                s.withTarget(base) { Self.picture(s) }
                let level = s.makeRenderTarget()
                s.withTarget(level) { s.background(Color(white: 0.3)) }
                s.drawImage(base.combined(with: level.filtered(.normalMap(amount: 4)), op).image, 0, 0)
            }
            #expect(out.worst(against: plain).by == 0, "\(name) by a flat layer's normal map moved the layer: \(describe(out.worst(against: plain)))")
        }
    }

    /// A combine whose other layer holds nothing does what it does over an
    /// empty layer: a mix of 0 is still the base.
    @Test func aCombineWithALayerNothingDrewIntoIsStillItsBase() throws {
        let out = try Self.render { s in
            s.background(.clear)
            let base = s.makeRenderTarget()
            s.withTarget(base) { Self.picture(s) }
            s.drawImage(base.combined(with: s.makeRenderTarget(), .mix(amount: 0)).image, 0, 0)
        }
        let plain = try Self.plain()
        try pinned("a combine is skipped when either layer was never drawn into, and a skipped result is empty: a mix of 0 with such a layer returns nothing where it returns the base over a layer holding one off-canvas mark (measured 2026-11-09)") {
            #expect(out.worst(against: plain).by == 0, "the result holds a summed alpha of \(out.sum(3))")
        }
    }

    // MARK: What a layer keeps between frames

    /// A loop that draws last frame's picture back, drawn whole and untouched,
    /// holds it: a hundred frames on it is the same numbers.
    @Test func feedbackHoldsAFrame() throws {
        let probe = Probe(); probe.holds = false
        var tick = 0
        probe.prepare = { s in s.feedback = s.makeFeedback() }
        probe.body = { s in
            s.background(.clear)
            let fb = s.feedback!
            s.withFeedback(fb) { prev in if tick == 0 { Self.picture(s) } else { s.drawImage(prev, 0, 0) } }
            s.drawImage(fb.image, 0, 0)
            tick += 1
        }
        let held = try Self.render(probe, frame: 100), plain = try Self.plain()
        #expect(held.worst(against: plain).by == 0, "after a hundred frames: \(describe(held.worst(against: plain)))")
    }

    /// A layer that draws a feedback layer's image shows what the feedback
    /// holds this frame, as the canvas drawing the same image does.
    @Test func aLayerShowsAFeedbackLayersImageOfTheSameFrame() throws {
        func shown(throughALayer: Bool) throws -> Frame {
            let probe = Probe(); probe.holds = false; probe.side = 32
            var tick = 0
            probe.prepare = { s in s.feedback = s.makeFeedback() }
            probe.body = { s in
                s.background(.clear)
                let fb = s.feedback!
                // One square a frame, each in its own place, nothing kept.
                s.withFeedback(fb) { _ in s.noStroke(); s.fill(.white); s.drawRect(Double(tick) * 8, 0, 8, 8) }
                if throughALayer {
                    let copy = s.makeRenderTarget()
                    s.withTarget(copy) { s.drawImage(fb.image, 0, 0) }
                    s.drawImage(copy.image, 0, 0)
                } else {
                    s.drawImage(fb.image, 0, 0)
                }
                tick += 1
            }
            return try Self.render(probe, frame: 2)
        }
        let direct = try shown(throughALayer: false)
        #expect(direct.value(20, 4, 3) > 0.99 && direct.value(12, 4, 3) == 0, "on the canvas the feedback shows this frame's square")
        let copied = try shown(throughALayer: true)
        try pinned("every plain layer is filled before any feedback layer in a frame, so a layer that draws a feedback's image holds the frame before: the copy shows frame 1's square where frame 2's is (found in a sketch and measured 2026-11-10)") {
            #expect(copied.value(20, 4, 3) > 0.99 && copied.value(12, 4, 3) == 0,
                    "through a layer: this frame's square reads \(copied.value(20, 4, 3)), the frame before's \(copied.value(12, 4, 3))")
        }
    }

    /// A loop that draws last frame back at a gain fades as the gain to the
    /// number of frames.
    @Test(arguments: [LayerPrecision.float32, .float16])
    func feedbackFadesAsItsGain(precision: LayerPrecision) throws {
        let probe = Probe(); probe.holds = false
        var tick = 0
        probe.prepare = { s in s.feedback = s.makeFeedback(precision: precision) }
        probe.body = { s in
            s.background(.clear)
            let fb = s.feedback!
            s.withFeedback(fb) { prev in
                if tick == 0 { Self.picture(s) } else { s.tint(Color(white: 1, alpha: 0.98)); s.drawImage(prev, 0, 0); s.noTint() }
            }
            s.drawImage(fb.image, 0, 0)
            tick += 1
        }
        let faded = try Self.render(probe, frame: 100), plain = try Self.plain()
        var lo = 9.0, hi = -9.0
        for i in faded.rgba.indices where plain.rgba[i] > 0.2 {
            let ratio = Double(faded.rgba[i]) / Double(plain.rgba[i]); lo = min(lo, ratio); hi = max(hi, ratio)
        }
        let want = pow(0.98, 100.0)
        try pinned("a half float is stored cut off, never rounded up, so every frame loses half a step on average beyond its gain: after 100 frames at 0.98 the picture holds 0.128 of itself where the gain gives 0.1326, 3.4% dark (measured 2026-11-09; of 64 probe values none was stored above the nearest half)",
                   when: precision == .float16) {
            #expect(abs(lo / want - 1) < 0.006 && abs(hi / want - 1) < 0.006, "\(precision): after 100 frames at 0.98 the picture holds \(lo) to \(hi) of itself, the gain gives \(want)")
        }
    }

    /// A loop that keeps most of last frame and lays a little of a color over
    /// it settles on that color, opaque.
    @Test(arguments: [LayerPrecision.float32, .float16])
    func aRunningMeanSettlesOnItsValue(precision: LayerPrecision) throws {
        let probe = Probe(); probe.holds = false; probe.side = 16
        probe.prepare = { s in s.feedback = s.makeFeedback(precision: precision) }
        probe.body = { s in
            s.background(.clear)
            let fb = s.feedback!
            s.withFeedback(fb) { prev in
                s.drawImage(prev, 0, 0)
                s.noStroke(); s.fill(Color(linear: 0.6, green: 0.3, blue: 0.1, alpha: 0.02)); s.drawRect(0, 0, 16, 16)
            }
            s.drawImage(fb.image, 0, 0)
        }
        let got = try Self.render(probe, frame: 600).at(8, 8)
        try pinned("the same cut-off store: a mean that keeps 0.98 of itself settles 4.1% dark at (0.576, 0.288, 0.097) with an alpha of 0.976, a layer that should be opaque and is not (0.8% dark at a keep of 0.9) (measured 2026-11-09)",
                   when: precision == .float16) {
            #expect(abs(got.x / 0.6 - 1) < 0.005 && got.w > 0.995, "\(precision): the mean settled at \(fmt(got))")
        }
    }

    /// An accumulator's picture is the mean of its passes: the same pass any
    /// number of times is that pass, and two passes taking turns are their
    /// average, light past white included.
    @Test func anAccumulatorsPictureIsTheMeanOfItsPasses() throws {
        func accumulated(frames: Int, alternates: Bool) throws -> Frame {
            let probe = Probe(); probe.holds = false
            var tick = 0
            probe.prepare = { s in s.accumulator = s.makeAccumulator() }
            probe.body = { s in
                s.background(.clear)
                let acc = s.accumulator!
                s.withAccumulator(acc) {
                    if alternates && tick % 2 == 1 { s.noStroke(); s.fill(Color(linear: 0.4, green: 0.4, blue: 0.4)); s.drawRect(0, 0, 96, 96) }
                    else { Self.picture(s) }
                }
                s.drawImage(acc.image, 0, 0)
                tick += 1
            }
            return try Self.render(probe, frame: frames - 1)
        }
        let plain = try Self.plain()
        for n in [1, 10, 100] {
            #expect(try accumulated(frames: n, alternates: false).worst(against: plain).by == 0, "the same pass \(n) times")
        }
        let two = try accumulated(frames: 100, alternates: true)
        var worst = 0.0
        for i in two.rgba.indices {
            let other = i % 4 == 3 ? 1.0 : 0.4
            worst = max(worst, abs(Double(two.rgba[i]) - (Double(plain.rgba[i]) + other) / 2))
        }
        #expect(worst < 0.002, "two passes taking turns stray from their average by \(worst)")
    }

    /// `reset()` starts the mean over wherever in `draw()` it is called.
    @Test(arguments: [true, false])
    func resetStartsAnAccumulatorsMeanOver(beforeTheBlock: Bool) throws {
        func value(at frame: Int) throws -> Double {
            let probe = Probe(); probe.holds = false; probe.side = 16
            var tick = 0
            probe.prepare = { s in s.accumulator = s.makeAccumulator() }
            probe.body = { s in
                s.background(.clear)
                let acc = s.accumulator!
                // A brighter pass before the reset, so a sum that kept it reads high.
                let v = tick < 10 ? 0.75 : 0.25
                if beforeTheBlock && tick == 10 { acc.reset() }
                s.withAccumulator(acc) { s.noStroke(); s.fill(Color(linear: v, green: v, blue: v)); s.drawRect(0, 0, 16, 16) }
                if !beforeTheBlock && tick == 10 { acc.reset() }
                s.drawImage(acc.image, 0, 0)
                tick += 1
            }
            return try Self.render(probe, frame: frame).value(8, 8)
        }
        let after = try [10, 11, 14].map { try value(at: $0) }
        try pinned("the block has counted its pass before the reset zeroes the count, so the sum starts over and the count does not: with the reset after the block the mean reads a tenth of the pass on that frame, twice it on the next, and one pass too many from then on (0.023, 0.500, 0.375 for a pass of 0.25, measured 2026-11-09)",
                   when: !beforeTheBlock) {
            for v in after { #expect(abs(v - 0.25) < 0.002, "after the reset the mean reads \(after)") }
        }
    }

    // MARK: The frequency domain and the measured field

    static func plate(_ s: Sketch, side: Int) {
        s.background(Color(linear: 0.2, green: 0.2, blue: 0.2)); s.noStroke(); s.fill(.white)
        s.drawCircle(Double(side) * 0.4, Double(side) * 0.55, Double(side) * 0.2)
    }

    static func roundTrip(side: Int, precision: LayerPrecision, mask: (@MainActor (Probe) -> Void)?) throws -> Frame {
        try render(side: side) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget(precision: precision)
            s.withTarget(layer) { plate(s, side: side) }
            var spectrum = layer.filtered(.fourier())
            if let mask {
                let kept = s.makeRenderTarget(precision: precision)
                s.withTarget(kept) { mask(s) }
                spectrum = spectrum.combined(with: kept, .mask())
            }
            s.drawImage(spectrum.filtered(.inverseFourier()).image, 0, 0)
        }
    }

    /// A picture taken to its spectrum and back is the picture, with nothing
    /// done to the spectrum and with a mask that keeps all of it.
    @Test(arguments: [(128, LayerPrecision.float16, false), (128, .float16, true), (512, .float32, true), (512, .float16, true)])
    func aFourierRoundTripReturnsThePicture(side: Int, precision: LayerPrecision, masked: Bool) throws {
        let source = try Self.render(side: side) { s in Self.plate(s, side: side) }
        var keepAll: (@MainActor (Probe) -> Void)?
        if masked { keepAll = { (s: Probe) in s.background(.white) } }
        let back = try Self.roundTrip(side: side, precision: precision, mask: keepAll)
        try pinned("a combine over a spectrum writes a layer of the picture's precision, and a half float has eleven bits for a sum that runs to the hundreds of thousands: on a 512 square of the default precision the masked trip brings white back as 0.376 (a mean error of 0.47; a `.float32` layer makes the trip within a step) (measured 2026-11-09)",
                   when: side == 512 && precision == .float16) {
            #expect(back.worst(against: source).by < 0.002, "\(side) \(precision): \(describe(back.worst(against: source)))")
        }
    }

    /// The lowest frequency alone is the picture's mean, everywhere.
    @Test func theLowestFrequencyAloneIsThePicturesMean() throws {
        let side = 128
        let source = try Self.render(side: side) { s in Self.plate(s, side: side) }
        let flatField = try Self.roundTrip(side: side, precision: .float32) { s in
            s.background(.black); s.noStroke(); s.fill(.white)
            s.drawPolygon([Vector2(64, 64), Vector2(65, 64), Vector2(65, 65), Vector2(64, 65)])
        }
        let want = source.sum(1) / Double(side * side)
        var lo = 9.0, hi = -9.0
        for y in 0..<side { for x in 0..<side { lo = min(lo, flatField.value(x, y)); hi = max(hi, flatField.value(x, y)) } }
        #expect(abs(lo - want) < 0.002 && abs(hi - want) < 0.002, "the lowest frequency alone runs \(lo) to \(hi), the mean is \(want)")
    }

    /// A measured field is the distance to the shape's edge in pixels, negative
    /// inside, with a unit direction that lands on the edge.
    @Test func aMeasuredFieldIsTheDistanceToTheEdge() throws {
        let c = Vector2(64.3, 63.8)
        let field = try Self.render(side: 128) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget(precision: .float32)
            s.withTarget(layer) {
                s.noStroke(); s.fill(.white)
                s.drawPolygon((0..<360).map { i in c + Vector2(angle: Double(i) / 360 * 2 * .pi) * 30 })
            }
            s.drawImage(layer.filtered(.distanceField()).image, 0, 0)
        }
        var distance = 0.0, landing = 0.0, direction = 0.0
        for y in 8..<120 { for x in 8..<120 {
            let p = Vector2(Double(x) + 0.5, Double(y) + 0.5)
            let analytic = (p - c).length - 30
            guard abs(analytic) > 2, abs(analytic) < 24 else { continue }
            let v = field.at(x, y)
            distance = max(distance, abs(v.x - analytic))
            landing = max(landing, abs((p + Vector2(v.y, v.z) * abs(v.x) - c).length - 30))
            direction = max(direction, abs((v.y * v.y + v.z * v.z).squareRoot() - 1))
        } }
        #expect(distance < 0.4, "the field strays from the true distance by \(distance) px")
        #expect(landing < 0.4, "a pixel moved along its direction by its distance lands \(landing) px off the edge")
        #expect(direction < 0.002, "a direction's length strays from 1 by \(direction)")
        #expect(field.value(64, 64) < 0 && field.value(110, 64) > 0, "the field is negative inside and positive outside")
    }

    /// Past the reach it was asked for, a field has the reach as its distance
    /// and no direction.
    @Test func pastItsReachAFieldHasNoDirection() throws {
        let field = try Self.render(side: 256) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            s.withTarget(layer) { s.noStroke(); s.fill(.white); s.drawCircle(40, 128, 6) }
            s.drawImage(layer.filtered(.distanceField(maxDistance: 32)).image, 0, 0)
        }
        #expect(field.value(106, 128) == 32 && field.value(196, 128) == 32, "the distance is held at the reach")
        #expect(field.value(196, 128, 1) == 0, "far past the reach there is no direction")
        try pinned("the direction is cleared only where no edge point arrived, and the ladder carries one to about twice its first step: 60 px from a shape under a reach of 32 the distance is 32 and the direction still points at the shape (measured 2026-11-09)") {
            #expect(field.value(106, 128, 1) == 0, "60 px out, past a reach of 32, the direction reads \(field.value(106, 128, 1))")
        }
    }

    // MARK: Generators and fields

    /// A checkerboard is its cells: `scale` of them down the layer, the first
    /// in the foreground color, hard-edged where the cell is whole pixels, and
    /// the same board on a layer kept at half scale.
    @Test(arguments: [1.0, 0.5])
    func aCheckerboardIsItsCells(layerScale: Double) throws {
        let f = try Self.render(side: 128) { s in
            s.background(.clear)
            s.drawImage(s.generate(.checkers(scale: 8), scale: layerScale).image, 0, 0, 128, 128)
        }
        for j in 0..<8 { for i in 0..<8 {
            let want = (i + j) % 2 == 0 ? 1.0 : 0.0
            #expect(f.value(i * 16 + 8, j * 16 + 8) == want, "cell \(i), \(j) reads \(f.value(i * 16 + 8, j * 16 + 8))")
        } }
        if layerScale == 1 {
            #expect(f.value(15, 8) == 1 && f.value(16, 8) == 0, "the first cell's edge falls between pixels 15 and 16")
        }
    }

    /// Grid lines are drawn where the lines are and nowhere else.
    @Test func gridLinesDrawOnlyTheirLines() throws {
        let f = try Self.render(side: 120) { s in
            s.background(.clear)
            s.drawImage(s.generate(.gridLines(scale: 8, weight: 0.1, foreground: .black, background: .white)).image, 0, 0)
        }
        // Lines sit at the middle of each 15-pixel cell: 7.5, 22.5, and so on.
        #expect(f.value(22, 40) < 0.1, "the line itself is drawn")
        for x in 11...18 { #expect(f.value(x, 40) > 0.99, "between two lines, at x \(x), the background reads \(f.value(x, 40))") }
    }

    /// A grid's ink is its lines' width: lines a share `weight` of a cell wide,
    /// both ways, cover `1 - (1 - weight)²` of the layer, whether a line is
    /// wider than a pixel or thinner, and lines of no weight are no lines.
    @Test(arguments: [0.0, 0.02, 0.1, 0.3, 1.0])
    func gridLinesCoverTheShareTheirWeightSays(weight: Double) throws {
        let f = try Self.render(side: 120) { s in
            s.background(.clear)
            s.drawImage(s.generate(.gridLines(scale: 8, weight: weight, foreground: .white, background: .clear)).image, 0, 0)
        }
        let covered = f.sum(3) / (120 * 120), want = 1 - (1 - weight) * (1 - weight)
        #expect(abs(covered - want) < 0.002, "lines of weight \(weight) cover \(covered) of the layer, where their width covers \(want)")
        if weight == 0 { #expect(f.rgba.allSatisfy { $0 == 0 }, "lines of no weight still drew") }
    }

    /// A field at rest stays at rest: the reaction's resting mix for thirty
    /// frames, and a still fluid's dye with nothing to carry or fade it.
    @Test func aFieldAtRestStaysAtRest() throws {
        let probe = Probe(); probe.holds = false; probe.side = 64
        var tick = 0
        var resting: FieldSnapshot?
        probe.prepare = { s in s.field = s.makeSimField(.reactionDiffusion()) }
        probe.body = { s in
            s.background(.black)
            let field = s.field!
            s.withField(field) {}
            s.drawImage(field.image, 0, 0)
            if tick == 30 { resting = field.snapshot() }
            tick += 1
        }
        _ = try Self.render(probe, frame: 30)
        let snap = try #require(resting)
        #expect(snap.values.allSatisfy { $0.x == 1 && $0.y == 0 }, "the reaction's resting mix moved")

        func dye(at frame: Int) throws -> Frame {
            let fluid = Probe(); fluid.holds = false; fluid.side = 64
            var step = 0
            fluid.prepare = { s in s.field = s.makeSimField(.fluid(curl: 0, velocityDissipation: 0, densityDissipation: 0)) }
            fluid.body = { s in
                s.background(.clear)
                let field = s.field!
                s.withField(field) {
                    if step == 0 { s.noStroke(); s.fill(Color(linear: 0.6, green: 0.3, blue: 0.1)); s.drawCircle(32, 32, 12) }
                }
                s.drawImage(field.image, 0, 0)
                step += 1
            }
            return try Self.render(fluid, frame: frame)
        }
        let early = try dye(at: 2), late = try dye(at: 40)
        #expect(early.sum(0) > 100, "the dye is there")
        #expect(late.worst(against: early).by < 0.002, "a still fluid's dye moved: \(describe(late.worst(against: early)))")
    }
}
