@testable import Ollin
import Testing
import Foundation

/// Render checks on the layer styles: `outline`, `dropShadow`, `innerShadow`,
/// `outerGlow`, `innerGlow`, and `bevel`, each read from a layer's alpha.
///
/// Every measurement is in linear light read before the present pass, with the
/// paint white over a black canvas, so a channel's value is the paint's
/// coverage. Widths are measured by area, summed from the antialiased picture
/// rather than counted from a hard cut, and compared with the shape's own area
/// rather than the radius it was asked for (a drawn disc's half-covered contour
/// sits a fraction of a pixel off its nominal radius). The checks pin what each
/// style promises: a band exactly as wide as asked against the shape's own edge,
/// a shadow that is the layer's Gaussian moved by its offset, a glow that follows
/// the distance from the edge, a bevel lit by the model it documents, and a clear
/// color or a zero reach that hands back the layer's own bytes.
@Suite
@MainActor
struct LayerStyleTests {

    // MARK: Linear read-back

    struct Linear: Equatable {
        let width: Int
        let height: Int
        let rgb: [Float]
        func value(_ x: Int, _ y: Int, _ c: Int = 0) -> Double { Double(rgb[(y * width + x) * 3 + c]) }
        /// Channel `c` summed over the whole frame: coverage times area.
        func sum(_ c: Int = 0) -> Double {
            var total = 0.0
            for i in 0 ..< width * height { total += Double(rgb[i * 3 + c]) }
            return total
        }
    }

    static func render(_ sketch: Sketch) throws -> Linear {
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        renderer.capturesLinearFrame = true
        _ = try OllinApp.renderImage(of: sketch, frame: 0, fps: 60, renderer: renderer)
        let linear = try #require(renderer.lastLinearFrame)
        let count = linear.width * linear.height
        let halfs = linear.color.contents().bindMemory(to: Float16.self, capacity: count * 4)
        var rgb = [Float](repeating: 0, count: count * 3)
        for i in 0 ..< count {
            for c in 0 ..< 3 { rgb[i * 3 + c] = Float(halfs[i * 4 + c]) }
        }
        return Linear(width: linear.width, height: linear.height, rgb: rgb)
    }

    // MARK: Fixtures

    /// A disc in a layer, drawn in `ink` and styled by `filter`, over a black canvas.
    /// `polygon` draws it as a 360-gon through the multisampled triangle path,
    /// whose antialiased edge is symmetric about its half-covered contour; the
    /// analytic disc's edge is remapped to perceptual alpha, which leans it outward.
    final class Disc: Sketch {
        static let center = Vector2(120.3, 119.6)
        static let radius = 62.0
        let ink: Color
        let filter: Filter?
        let polygon: Bool
        init(ink: Color, filter: Filter?, polygon: Bool = false) {
            self.ink = ink; self.filter = filter; self.polygon = polygon; super.init()
        }
        required init() { ink = .white; filter = nil; polygon = false; super.init() }
        override var canvasSize: CanvasSize { .square(240) }
        override func draw() {
            background(.black)
            let layer = makeRenderTarget()
            withTarget(layer) {
                noStroke(); fill(ink)
                if polygon {
                    drawPolygon((0 ..< 360).map { i in
                        let a = Double(i) / 360 * 2 * .pi
                        return Self.center + Vector2(cos(a), sin(a)) * Self.radius
                    })
                } else {
                    drawCircle(center: Self.center, radius: Self.radius)
                }
            }
            drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
        }
    }

    /// A box in a layer, drawn in `ink` and styled by `filter`, over a black canvas.
    /// Its edges fall on pixel boundaries; `polygon` draws it through the
    /// multisampled triangle path, where such an edge covers a pixel wholly or
    /// not at all, so its complement is exact.
    final class Box: Sketch {
        static let corner = Vector2(70, 60)
        static let size = Vector2(100, 120)
        static var outline: [Vector2] {
            [corner, corner + Vector2(size.x, 0), corner + size, corner + Vector2(0, size.y)]
        }
        let ink: Color
        let filter: Filter?
        let polygon: Bool
        init(ink: Color, filter: Filter?, polygon: Bool = false) {
            self.ink = ink; self.filter = filter; self.polygon = polygon; super.init()
        }
        required init() { ink = .white; filter = nil; polygon = false; super.init() }
        override var canvasSize: CanvasSize { .square(240) }
        override func draw() {
            background(.black)
            let layer = makeRenderTarget()
            withTarget(layer) {
                noStroke(); fill(ink)
                if polygon { drawPolygon(Self.outline) }
                else { drawRect(corner: Self.corner, width: Self.size.x, height: Self.size.y) }
            }
            drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
        }
    }

    /// The radius of a white disc of `area` pixels.
    private func radius(ofArea area: Double) -> Double { (area / .pi).squareRoot() }

    /// The shape's own radius, from the summed coverage of the bare white disc.
    private func discRadius(polygon: Bool = true) throws -> Double {
        radius(ofArea: try Self.render(Disc(ink: .white, filter: nil, polygon: polygon)).sum())
    }

    /// Channel 0 read bilinearly at a point in pixel units.
    private func bilinear(_ image: Linear, _ q: Vector2) -> Double {
        let gx = q.x - 0.5, gy = q.y - 0.5
        let x0 = Int(gx.rounded(.down)), y0 = Int(gy.rounded(.down))
        let fx = gx - Double(x0), fy = gy - Double(y0)
        let top = image.value(x0, y0) * (1 - fx) + image.value(x0 + 1, y0) * fx
        let bottom = image.value(x0, y0 + 1) * (1 - fx) + image.value(x0 + 1, y0 + 1) * fx
        return top * (1 - fy) + bottom * fy
    }

    // MARK: Outline
    //
    // The disc here is a 360-gon through the multisampled path: its antialiased edge is
    // symmetric about its half-covered contour, so the band's width can be read against
    // the shape's own area. (The analytic disc's edge leans outward, its coverage
    // remapped to perceptual alpha, which moves an inside band's area by up to 0.07
    // pixel without the band itself moving.) Within a pixel of the edge the field is the
    // distance to the nearest of a row of discrete edge points, which overestimates
    // there, so a band narrower than two pixels carries a little less ink than its
    // width, measured at most 0.06 pixel short one-sided and 0.125 centered.

    @Test(.enabled(if: Snapshot.hasMetal), arguments: [0.25, 0.5, 1.0, 3.0, 8.0])
    func anOutsideOutlineReachesItsWidthPastTheShapesOwnEdge(width: Double) throws {
        // A black disc with a white band laid under it: the band shows only past the
        // disc, so the frame's sum is the band's area, and the disc plus the band is a
        // disc grown by the width.
        let r0 = try discRadius()
        let band = try Self.render(Disc(ink: .black, filter: .outline(width: width, color: .white),
                                        polygon: true)).sum()
        let grown = radius(ofArea: .pi * r0 * r0 + band)
        #expect(abs(grown - r0 - width) < 0.06, "grown by \(grown - r0) for a width of \(width)")
    }

    @Test(.enabled(if: Snapshot.hasMetal), arguments: [0.25, 0.5, 1.0, 3.0, 8.0])
    func anInsideOutlineCutsItsWidthInFromTheShapesOwnEdge(width: Double) throws {
        // A white disc painted black for `width` in from its edge: what stays white is
        // the disc shrunk by the width.
        let r0 = try discRadius()
        let left = try Self.render(Disc(ink: .white, filter: .outline(width: width, color: .black, align: .inside),
                                        polygon: true)).sum()
        #expect(abs(radius(ofArea: left) - (r0 - width)) < 0.06,
                "shrunk by \(r0 - radius(ofArea: left)) for a width of \(width)")
    }

    @Test(.enabled(if: Snapshot.hasMetal), arguments: [0.25, 0.5, 1.0, 3.0, 8.0])
    func aCenteredOutlineStraddlesTheEdgeByHalfItsWidth(width: Double) throws {
        // A white band over a black disc, centered on the edge: its area is the ring
        // between the disc shrunk and grown by half the width, 2 pi r w.
        let r0 = try discRadius()
        let band = try Self.render(Disc(ink: .black, filter: .outline(width: width, color: .white, align: .center),
                                        polygon: true)).sum()
        let measured = band / (2 * .pi * r0)
        #expect(abs(measured - width) < 0.125, "a band \(measured) wide for a width of \(width)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anOutlinesOpacityIsItsColorsAlpha() throws {
        let full = try Self.render(Disc(ink: .black, filter: .outline(width: 6, color: .white))).sum()
        let half = try Self.render(Disc(ink: .black, filter: .outline(width: 6, color: Color(white: 1, alpha: 0.5)))).sum()
        #expect(abs(half / full - 0.5) < 0.002)
    }

    // MARK: Shadows

    /// The drop shadow built from public calls: a white box blurred by the same
    /// radius and drawn with the black box over it. `blurFirst` blurs the box where
    /// it is and draws the blurred layer moved by the offset, the same texture the
    /// filter reads; otherwise the box is drawn at the offset and blurred there.
    final class ShadowReference: Sketch {
        let offset: Vector2
        let radius: Double
        let blurFirst: Bool
        init(offset: Vector2, radius: Double, blurFirst: Bool) {
            self.offset = offset; self.radius = radius; self.blurFirst = blurFirst; super.init()
        }
        required init() { offset = Vector2(0, 0); radius = 1; blurFirst = true; super.init() }
        override var canvasSize: CanvasSize { .square(240) }
        override func draw() {
            background(.black)
            let shape = makeRenderTarget()
            withTarget(shape) {
                noStroke(); fill(.white)
                drawRect(corner: Box.corner + (blurFirst ? Vector2(0, 0) : offset), width: Box.size.x, height: Box.size.y)
            }
            let blurred = shape.filtered(.gaussianBlur(radius: radius)).image
            if blurFirst { drawImage(blurred, offset.x, offset.y) } else { drawImage(blurred, 0, 0) }
            let layer = makeRenderTarget()
            withTarget(layer) { noStroke(); fill(.black); drawRect(corner: Box.corner, width: Box.size.x, height: Box.size.y) }
            drawImage(layer.image, 0, 0)
        }
    }

    private func worstDifference(_ a: Linear, _ b: Linear) -> Double {
        var worst = 0.0
        for i in 0 ..< a.rgb.count { worst = max(worst, abs(Double(a.rgb[i] - b.rgb[i]))) }
        return worst
    }

    @Test(.enabled(if: Snapshot.hasMetal), arguments: [(Vector2(7, -5), 6.0), (Vector2(-12, 9), 3.0), (Vector2(0, 0), 10.0)])
    func aDropShadowIsTheLayersGaussianMovedByItsOffset(offset: Vector2, radius: Double) throws {
        let shadowed = try Self.render(Box(ink: .black, filter: .dropShadow(offset: offset, radius: radius,
                                                                           color: .white)))
        #expect(shadowed.sum() > 100, "the shadow drew")
        // The same blurred texture, moved a whole number of pixels: the same bytes.
        let moved = try Self.render(ShadowReference(offset: offset, radius: radius, blurFirst: true))
        #expect(worstDifference(shadowed, moved) < 1e-4, "against the blur moved")
        // The box drawn at the offset and blurred there: the same up to the hardware
        // blur's own dependence on where a shape sits, a few half-float steps.
        let redrawn = try Self.render(ShadowReference(offset: offset, radius: radius, blurFirst: false))
        #expect(worstDifference(shadowed, redrawn) < 0.006, "against the box blurred at the offset")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSubPixelOffsetReadsBetweenTheBlurredTexels() throws {
        let offset = Vector2(6.5, 3.25)
        let shadowed = try Self.render(Box(ink: .black, filter: .dropShadow(offset: offset, radius: 5, color: .white)))
        let reference = try Self.render(ShadowReference(offset: offset, radius: 5, blurFirst: false))
        #expect(worstDifference(shadowed, reference) < 0.01)
    }

    /// The inner shadow built from public calls: the box's complement (the canvas
    /// with the box cut out, drawn as one even-odd shape so its edges cover pixels
    /// wholly or not at all) moved by the offset and blurred, in white over black.
    final class InnerShadowReference: Sketch {
        let offset: Vector2
        let radius: Double
        init(offset: Vector2, radius: Double) { self.offset = offset; self.radius = radius; super.init() }
        required init() { offset = Vector2(0, 0); radius = 1; super.init() }
        override var canvasSize: CanvasSize { .square(240) }
        override func draw() {
            background(.black)
            let complement = makeRenderTarget()
            withTarget(complement) {
                noStroke(); fill(.white)
                let frame = [Vector2(-40, -40), Vector2(280, -40), Vector2(280, 280), Vector2(-40, 280)]
                drawShape(Shape(outer: frame.map { $0 + offset }, holes: [Box.outline.map { $0 + offset }]))
            }
            drawImage(complement.filtered(.gaussianBlur(radius: radius)).image, 0, 0)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal), arguments: [(Vector2(6, 9), 4.0), (Vector2(-10, 3), 7.0)])
    func anInnerShadowIsWhatTheLayerDoesNotCoverBlurredAndMoved(offset: Vector2, radius: Double) throws {
        // Inside the box the shaded white is 1 - k, and the reference is k, so the two
        // sum to one; outside the box the layer is empty and the filter leaves it so.
        let shaded = try Self.render(Box(ink: .white, filter: .innerShadow(offset: offset, radius: radius,
                                                                         color: .black), polygon: true))
        let reference = try Self.render(InnerShadowReference(offset: offset, radius: radius))
        var worst = 0.0, outside = 0.0, darkened = 0
        for y in 0 ..< shaded.height {
            for x in 0 ..< shaded.width {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let inX = px - Box.corner.x, inY = py - Box.corner.y
                let inside = inX > 0 && inY > 0 && inX < Box.size.x && inY < Box.size.y
                if inside {
                    worst = max(worst, abs(shaded.value(x, y) + reference.value(x, y) - 1))
                    if shaded.value(x, y) < 0.5 { darkened += 1 }
                } else {
                    outside = max(outside, shaded.value(x, y))
                }
            }
        }
        #expect(darkened > 300, "the shadow fell")
        #expect(worst < 0.006, "worst \(worst) from summing to one")
        #expect(outside == 0)
    }

    // MARK: Glows
    //
    // A glow is read off the field, and the field reproduces the drawn edge's own
    // half-covered contour, coverage steps included (about a quarter pixel on a
    // multisampled edge), so single pixels stray by that much distance times the
    // falloff's slope. The curve is pinned by the mean over each one-pixel band of
    // distance, where a reach one pixel off reads 0.015.

    /// The glow's mean error from `curve` per band of distance `across` (from the
    /// shape's area radius), and its worst single pixel.
    private func glowErrors(_ glow: Linear, from: Double, to: Double, across: (Vector2) -> Double,
                            curve: (Double) -> Double) -> (mean: Double, worst: Double) {
        var sums: [Int: (Double, Int)] = [:]
        var worst = 0.0
        for y in 0 ..< glow.height {
            for x in 0 ..< glow.width {
                let d = across(Vector2(Double(x) + 0.5, Double(y) + 0.5))
                guard d > from, d < to else { continue }
                let e = glow.value(x, y) - curve(d)
                worst = max(worst, abs(e))
                let band = sums[Int(d), default: (0, 0)]
                sums[Int(d)] = (band.0 + e, band.1 + 1)
            }
        }
        let mean = sums.values.map { abs($0.0 / Double($0.1)) }.max() ?? .infinity
        return (mean, worst)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anOuterGlowFallsWithTheDistanceFromTheEdge() throws {
        let r0 = try discRadius()
        let reach = 30.0
        let glow = try Self.render(Disc(ink: .black, filter: .outerGlow(radius: reach, color: .white), polygon: true))
        let errors = glowErrors(glow, from: 2, to: reach + 4, across: { ($0 - Disc.center).length - r0 },
                                curve: { d in pow(max(0, 1 - d / reach), 2) })
        #expect(errors.mean < 0.004, "a band's mean is off by \(errors.mean) from (1 - d/r)^2")
        #expect(errors.worst < 0.02, "a pixel is off by \(errors.worst)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anInnerGlowFallsWithTheDistanceInFromTheEdge() throws {
        let r0 = try discRadius()
        let reach = 24.0
        let glow = try Self.render(Disc(ink: .black, filter: .innerGlow(radius: reach, color: .white), polygon: true))
        let errors = glowErrors(glow, from: 2, to: r0 - 1, across: { r0 - ($0 - Disc.center).length },
                                curve: { s in pow(max(0, 1 - s / reach), 2) })
        #expect(errors.mean < 0.004, "a band's mean is off by \(errors.mean) from (1 - s/r)^2")
        #expect(errors.worst < 0.025, "a pixel is off by \(errors.worst)")
    }

    // MARK: Bevel

    @Test(.enabled(if: Snapshot.hasMetal), arguments: Filter.BevelProfile.allCases)
    func aBevelLeavesTheFlatTopAndTheOutsideAlone(profile: Filter.BevelProfile) throws {
        let gray = Color(white: 0.5)
        let flat = try Self.render(Box(ink: gray, filter: nil))
        let width = 10.0
        let beveled = try Self.render(Box(ink: gray, filter: .bevel(width: width, profile: profile)))
        var changedOnTop = 0, changedOutside = 0, changedInBand = 0
        let inset = width + 1
        for y in 0 ..< flat.height {
            for x in 0 ..< flat.width {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let inX = px - Box.corner.x, inY = py - Box.corner.y
                let s = min(inX, inY, Box.size.x - inX, Box.size.y - inY)
                let differs = (0 ..< 3).contains { flat.value(x, y, $0) != beveled.value(x, y, $0) }
                if s > inset, differs { changedOnTop += 1 }
                if s < -1.5, differs { changedOutside += 1 }
                if s > 1, s < width - 1, differs { changedInBand += 1 }
            }
        }
        #expect(changedOnTop == 0)
        #expect(changedOutside == 0)
        #expect(changedInBand > 1000)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aChiseledSlopeIsLitByTheModelItDocuments() throws {
        // A light from straight left, raised 30 degrees, on a box's left slope (rising
        // 1:1 inward, so its normal leans 45 degrees left) and its right slope (45
        // degrees right): the highlight and shadow weights follow from the normal.
        let gray = 0.5
        let elevation = Double.pi / 6
        let beveled = try Self.render(Box(ink: Color(white: gray),
                                         filter: .bevel(width: 12, depth: 1, profile: .chiseled,
                                                        angle: .pi, elevation: elevation,
                                                        highlight: .white, shadow: .black)))
        let linearGray = Color.srgbToLinear(gray)
        let lz = sin(elevation), lx = -cos(elevation)
        let n = 1 / 2.0.squareRoot()
        let leftFacing = -n * lx + n * lz                   // leaning toward the light
        let rightFacing = n * lx + n * lz                   // leaning away from it
        let toward = min(max((leftFacing - lz) / (1 - lz), 0), 1)
        let away = min(max((lz - rightFacing) / lz, 0), 1)
        let expectedLeft = linearGray + (1 - linearGray) * toward
        let expectedRight = linearGray * (1 - away)
        let midY = Int(Box.corner.y + Box.size.y / 2)
        for s in [4, 6, 8] {
            let leftX = Int(Box.corner.x) + s, rightX = Int(Box.corner.x + Box.size.x) - 1 - s
            #expect(abs(beveled.value(leftX, midY) - expectedLeft) < 2e-3,
                    "left slope \(beveled.value(leftX, midY)) against \(expectedLeft)")
            #expect(abs(beveled.value(rightX, midY) - expectedRight) < 2e-3,
                    "right slope \(beveled.value(rightX, midY)) against \(expectedRight)")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aRoundedBevelOnADiscHasNoStreaks() throws {
        // Around a ring inside a disc's bevel the light changes only with the angle to
        // the light, smoothly; a direction read from the nearest edge point instead turns
        // by up to ten degrees between neighbors and draws radial streaks. The ring is
        // read bilinearly every half pixel, and each reading is compared with the mean of
        // its two neighbors: a curve leaves next to nothing there, a streak its step.
        let beveled = try Self.render(Disc(ink: Color(white: 0.6), filter: .bevel(width: 14)))
        let ring = try discRadius(polygon: false) - 4
        let steps = 720
        let readings = (0 ..< steps).map { k -> Double in
            let a = Double(k) / Double(steps) * 2 * .pi
            return bilinear(beveled, Disc.center + Vector2(cos(a), sin(a)) * ring)
        }
        var worst = 0.0
        for k in 0 ..< steps {
            let around = (readings[(k + steps - 1) % steps] + readings[(k + 1) % steps]) / 2
            worst = max(worst, abs(readings[k] - around))
        }
        #expect(worst < 0.02, "a bump of \(worst) between neighbors on the ring")
    }

    // MARK: Nothing asked, nothing changed

    @Test(.enabled(if: Snapshot.hasMetal))
    func aClearColorOrAZeroReachHandsBackTheLayersOwnBytes() throws {
        let clear = Color(white: 1, alpha: 0)
        let ink = Color(hex: 0x3D7EDB)
        let filters: [(String, Filter)] = [
            ("clear outline", .outline(width: 6, color: clear)),
            ("clear inside outline", .outline(width: 6, color: clear, align: .inside)),
            ("clear centered outline", .outline(width: 6, color: clear, align: .center)),
            ("zero-width outline", .outline(width: 0, color: .white)),
            ("zero-width centered outline", .outline(width: 0, color: .white, align: .center)),
            ("clear drop shadow", .dropShadow(color: clear)),
            ("clear inner shadow", .innerShadow(color: clear)),
            ("clear outer glow", .outerGlow(color: clear)),
            ("zero-radius outer glow", .outerGlow(radius: 0)),
            ("clear inner glow", .innerGlow(color: clear)),
            ("zero-radius inner glow", .innerGlow(radius: 0)),
            ("clear bevel", .bevel(highlight: clear, shadow: clear)),
            ("zero-width bevel", .bevel(width: 0)),
            ("zero-depth bevel", .bevel(depth: 0)),
        ]
        let plainDisc = try Self.render(Disc(ink: ink, filter: nil))
        let plainBox = try Self.render(Box(ink: ink, filter: nil))
        for (name, filter) in filters {
            #expect(try Self.render(Disc(ink: ink, filter: filter)) == plainDisc, "\(name) on a disc")
            #expect(try Self.render(Box(ink: ink, filter: filter)) == plainBox, "\(name) on a box")
        }
    }
}
