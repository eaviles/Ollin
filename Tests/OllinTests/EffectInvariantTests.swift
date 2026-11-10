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
        Named(name: "scanlines amount 0", filter: .scanlines(amount: 0)),
        Named(name: "glitch amount 0", filter: .glitch(amount: 0)),
        Named(name: "vhs amount 0", filter: .vhs(amount: 0)),
        Named(name: "swirl angle 0", filter: .swirl(angle: 0)),
        Named(name: "bulge amount 0", filter: .bulge(amount: 0)),
        Named(name: "wave amplitude 0", filter: .wave(amplitude: 0)),
        Named(name: "ripple amplitude 0", filter: .ripple(amplitude: 0)),
        Named(name: "polar amount 0", filter: .polar(amount: 0)),
        Named(name: "tile count 1", filter: .tile(count: 1)),
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
        Named(name: "lightLeak intensity 0", filter: .lightLeak(intensity: 0)),
    ]

    /// Filters whose arithmetic takes the color out from under its alpha and
    /// puts it back, which a half float returns within one step of its precision.
    nonisolated static let neutralWithinAStep: [Named] = [
        Named(name: "colorGrade defaults", filter: .colorGrade()),
        Named(name: "temperature 0 0", filter: .temperature(amount: 0, tint: 0)),
        Named(name: "vibrance 0", filter: .vibrance(amount: 0)),
        Named(name: "sepia 0", filter: .sepia(amount: 0)),
        Named(name: "invert 0", filter: .invert(amount: 0)),
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
    ]

    /// A filter at the setting that asks for none of its effect is its input:
    /// every channel, light past white and see-through pixels included.
    @Test(arguments: exactlyNeutral)
    func aFilterAskedForNothingReturnsItsInput(_ item: Named) throws {
        let w = try Self.filtered(item.filter).worst(against: try Self.plain())
        switch item.name {
        case "levels 0 1 1":
            try pinned("levels clamps to 0...1 before its curve, so at 0, 1, 1 light past white is cut: 3.0 comes back 1.0 (measured 2026-11-09)") {
                #expect(w.by == 0, "\(item.name): \(describe(w))")
            }
        case "lightLeak intensity 0":
            try pinned("the leak's dither is added before the intensity's floor, so at intensity 0 half the pixels gain up to 0.002 of light and of alpha (measured 2026-11-09)") {
                #expect(w.by == 0, "\(item.name): \(describe(w))")
            }
        default:
            #expect(w.by == 0, "\(item.name): \(describe(w))")
        }
    }

    @Test(arguments: neutralWithinAStep)
    func aToneFilterAskedForNothingIsWithinAStep(_ item: Named) throws {
        let plain = try Self.plain()
        let w = try Self.filtered(item.filter).worst(against: plain)
        // One step of a half float at the value that moved: 2^-10 of it.
        let step = max(abs(plain.value(w.x, w.y, w.channel)), 0.5) / 1024
        #expect(w.by <= step * 1.01, "\(item.name): \(describe(w)), a step there is \(step)")
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

    /// A layer's `scale` is how finely it is kept, so what a filter does to the
    /// picture is the same at any scale: a blur is as wide, an outline as thick.
    @Test func aFiltersSizesDoNotFollowTheLayersScale() throws {
        let base = Self.spread(try Self.disc(filter: nil, layerScale: 0.5))
        let g = Self.spread(try Self.disc(filter: .gaussianBlur(radius: 4), layerScale: 0.5))
        let sigma = (g.varX - base.varX).squareRoot()
        try pinned("a filter's pixel sizes are the layer's own texels: on a half-scale layer a Gaussian of radius 4 spreads by a sigma of 7.98 canvas pixels, an outline of 6 grows the disc by 12.03, a pixelate of 8 makes 16-pixel cells, and a shadow's offset of 40 lands 80 away (measured 2026-11-09)") {
            #expect(abs(sigma / 4 - 1) < 0.05, "on a half-scale layer a radius of 4 spread the disc by \(sigma)")
            let plain = try Self.disc(radius: 16, filter: nil, layerScale: 0.5).sum(3)
            let outlined = try Self.disc(radius: 16, filter: .outline(width: 6, color: .white, align: .outside), layerScale: 0.5).sum(3)
            let grew = (outlined / .pi).squareRoot() - (plain / .pi).squareRoot()
            #expect(abs(grew - 6) < 0.3, "on a half-scale layer an outline of 6 grew the disc by \(grew)")
        }
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
        try pinned("the region means are taken of colors already divided by their alpha, where an empty neighbor counts as black: a half-clear shape's rim comes back 4% dark (measured 2026-11-09)",
                   when: item.name == "oilPaint") {
            #expect(worst < 0.006, "\(item.name): the straight color strays by \(worst * 100)%")
        }
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

    /// One mirrored tile is the picture: mirroring flips every other cell, and
    /// the first is not one of them.
    @Test func aMirroredTileOfOneIsThePicture() throws {
        let plain = try Self.plain(), out = try Self.filtered(.tile(count: 1, mirrored: true))
        try pinned("the mirrored fold is one minus the coordinate on the first cell, so the first cell is a flipped one: one mirrored tile is the picture turned half round, to the number (measured 2026-11-09)") {
            #expect(out.mean(against: plain) < 0.001, "one mirrored tile differs from the picture by a mean of \(out.mean(against: plain))")
        }
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
        try pinned("the blur's step is taken in the layer's own 0 to 1 coordinates with no aspect, so on a 2:1 layer the same distance smears 14.8 px across and 7.4 down, and an angle of 45 degrees runs at 27 (measured 2026-11-09)") {
            #expect(abs(down.y / across.x - 1) < 0.03, "the smear is \(across.x) across and \(down.y) down")
            #expect(abs(diagonal.y / diagonal.x - 1) < 0.03, "at 45 degrees the smear runs \(diagonal.x) across and \(diagonal.y) down")
        }
        let comb = try Self.render(side: 128) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            s.withTarget(layer) { s.noStroke(); s.fill(.white); s.drawRect(64, 0, 1, 128) }
            s.drawImage(layer.filtered(.motionBlur(angle: 0, distance: 0.5)).image, 0, 0)
        }
        let inside = (40..<88).map { comb.value($0, 64, 3) }
        try pinned("sixteen taps however long the smear: a one-pixel line smeared over half a 128-pixel layer is sixteen copies with gaps that read 0 between them (measured 2026-11-09)") {
            #expect(inside.min()! > inside.max()! * 0.5, "inside the streak the coverage runs from \(inside.min()!) to \(inside.max()!)")
        }
    }

    /// A flat field has no contour lines, whatever its brightness.
    @Test func contourLeavesAFlatFieldFlat() throws {
        let gray = try flat(32, Color(linear: 0.33, green: 0.33, blue: 0.33), .contour(levels: 10, amount: 1)).at(16, 16)
        #expect(abs(gray.x - 0.33) < 0.002, "a flat 0.33 came back \(gray.x)")
        let white = try flat(32, .white, .contour(levels: 10, amount: 1)).at(16, 16)
        try pinned("a flat field whose brightness sits on a level has a zero distance to the line and a zero pixel step, which the line's ramp reads as on the line: flat white comes back solid black (measured 2026-11-09)") {
            #expect(white.x > 0.99, "flat white came back \(white.x)")
        }
    }

    /// A dither trades levels for a pattern and keeps the brightness: the mean
    /// of a flat field is the field's value.
    @Test(arguments: [(0.5, 2.0), (0.25, 2.0), (0.6, 4.0), (0.5, 8.0)])
    func anOrderedDitherKeepsTheMeanBrightness(value: Double, levels: Double) throws {
        let got = mean(try flat(64, Color(linear: value, green: value, blue: value), .dither(levels: levels))).x
        try pinned("the quantizer multiplies by the number of levels and divides by one less, so the mean comes back n / (n - 1) times the value: 0.5 at two levels is all white, 0.6 at four reads 0.79, 0.5 at eight reads 0.571 (measured 2026-11-09)") {
            #expect(abs(got - value) < 0.02, "a flat \(value) dithered to \(levels) levels has a mean of \(got)")
        }
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
        let f = try flat(64, Color(linear: 0.6, green: 0.6, blue: 0.6), item.filter)
        var past = 0.0
        for y in 0..<64 { for x in 0..<64 { let p = f.at(x, y); past = max(past, max(p.x, p.y, p.z) - p.w) } }
        try pinned("the two colors are mixed as written, with a clear background's white still in it: color past its coverage by 1.0 under crosshatch and 0.15 under lineScreen, which composites as added white (measured 2026-11-09)",
                   when: item.name == "crosshatch" || item.name == "lineScreen") {
            #expect(past < 0.002, "\(item.name) wrote a color \(past) past its own alpha")
        }
    }

    @Test func whatAGeneratorOrAGlitchWritesIsPremultiplied() throws {
        let half = try Self.render(side: 64) { s in
            s.background(.clear)
            s.drawImage(s.generate(.checkers(scale: 4, foreground: Color(white: 1, alpha: 0.5), background: .clear)).image, 0, 0)
        }.at(4, 4)
        try pinned("the pattern generators return their colors as written: a half-clear white cell holds (1, 1, 1, 0.5) where a layer holds (0.5, 0.5, 0.5, 0.5) (measured 2026-11-09)") {
            #expect(abs(half.x - 0.5) < 0.002, "a half-clear white cell holds \(fmt(half))")
        }
        let glitch = try Self.render(side: 96) { s in
            s.background(.clear)
            let layer = s.makeRenderTarget()
            s.withTarget(layer) { s.noStroke(); s.fill(.white); s.drawRect(30, 0, 36, 96) }
            s.drawImage(layer.filtered(.glitch(amount: 0.3, seed: 1)).image, 0, 0)
        }
        var past = 0.0
        for y in 0..<96 { for x in 0..<96 { let p = glitch.at(x, y); past = max(past, max(p.x, p.y, p.z) - p.w) } }
        try pinned("the three channels are read from three places under the green one's alpha: beside a shifted white bar a pixel holds (0, 0.11, 0.83, 0.11), a color 0.72 past its coverage (measured 2026-11-09)") {
            #expect(past < 0.002, "a glitched bar wrote a color \(past) past its own alpha")
        }
    }

    /// Grain is noise at any seed, the frame count of a long run included.
    @Test(arguments: [0.0, 200_000])
    func grainStaysNoiseAtAnySeed(seed: Double) throws {
        let g = try flat(64, Color(linear: 0.4, green: 0.4, blue: 0.4), .grain(amount: 0.5, seed: seed))
        var values = Set<Float>()
        for i in stride(from: 0, to: g.rgba.count, by: 4) { values.insert(g.rgba[i]) }
        try pinned("the seed is added to the pixel's position before the hash, and single precision has no fraction left at that size: at a seed of 200,000, an hour of frames, 4,096 pixels hold 16 values and one in six neighbors is its pair (1,605 values at seed 0) (measured 2026-11-09)",
                   when: seed > 1000) {
            #expect(values.count > 800, "at seed \(seed) the grain holds \(values.count) distinct values")
        }
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
        default: s.background(Color(linear: 0.5, green: 0.5, blue: 0.5))
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
        Mixed(name: "displace 0", op: .displace(amount: 0), aux: 3), Mixed(name: "displace by linear mid-gray", op: .displace(amount: 0.1), aux: 4),
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

    /// A displacement map's mid-gray is no shift: the gray a sketch writes, and
    /// the nothing around a map drawn on a clear layer.
    @Test func aDisplacementMapsMidGrayIsNoShift() throws {
        let plain = try Self.plain()
        func displaced(_ map: @escaping @MainActor (Probe) -> Void) throws -> Frame {
            try Self.render { s in
                s.background(.clear)
                let base = s.makeRenderTarget()
                s.withTarget(base) { Self.picture(s) }
                let field = s.makeRenderTarget()
                s.withTarget(field) { map(s) }
                s.drawImage(base.combined(with: field, .displace(amount: 0.1)).image, 0, 0)
            }
        }
        let gray = try displaced { $0.background(Color(white: 0.5)) }
        try pinned("the map is read as stored, in linear light, and centered on 0.5 there: `Color(white: 0.5)` stores 0.214 and moves the whole layer 5.5 px of a 96-pixel canvas at an amount of 0.1; the gray that is no shift is `Color(white: 0.735)` (measured 2026-11-09)") {
            #expect(gray.mean(against: plain) < 0.001, "a mid-gray map moved the layer: a mean of \(gray.mean(against: plain)) from the base")
        }
        let clear = try displaced { s in s.noStroke(); s.fill(Color(linear: 0.5, green: 0.5, blue: 0.5)); s.drawCircle(48, 48, 10) }
        try pinned("a clear texel of the map reads as red 0 and green 0, the largest shift there is: a map drawn on a clear layer moves everything outside its marks by the full amount, and a soft edge on the map is a hard step (measured 2026-11-09)") {
            #expect(clear.mean(against: plain) < 0.001, "a map with nothing around its mark moved the layer: a mean of \(clear.mean(against: plain)) from the base")
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
        try pinned("the line's pixel step is taken of a coordinate that wraps at the cell's edge, and where the wrap falls inside one 2 by 2 block of pixels the step is a whole cell: two pixels at such an edge read 0.81, a faint second line between the lines (measured 2026-11-09 on a 120-pixel layer, at x 14 and 15)") {
            for x in 11...18 { #expect(f.value(x, 40) > 0.99, "between two lines, at x \(x), the background reads \(f.value(x, 40))") }
        }
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
