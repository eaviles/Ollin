import CoreGraphics
import Foundation
import Testing
@testable import Ollin

/// The holographic foil filter against the sheet it is built on. The filter at
/// `amount` 0 changes no byte; the sheet it builds for itself is the one a
/// sketch builds with `FacetField.crumpled`, byte for byte; the GPU finds the
/// same facet under every centroid the CPU does and shades it by the same
/// normal; the rainbow breaks at the creases of a crumpled sheet and runs
/// whole across a flat one; a pixel off a handed-in sheet reads as a flat
/// facet; a mark pressed in by `relief` moves only the facets it touches; the
/// creases a sketch draws from the sheet round-trip through SVG; and the foil
/// moves with its phase and its light.
@Suite
@MainActor
struct HolographicFoilTests {

    static let side = 240
    static let layer = Rectangle(x: 0, y: 0, width: Double(side), height: Double(side))
    static let light = (angle: -2.2, elevation: 0.9)

    /// A white opaque layer, with whatever `marks` draws into it, over black,
    /// filtered or not.
    final class FoilProbe: Sketch {
        var filter: Filter?
        var marks: (@MainActor (Sketch) -> Void)?
        static func make(_ filter: Filter?, marks: (@MainActor (Sketch) -> Void)? = nil) -> FoilProbe {
            let s = FoilProbe(); s.filter = filter; s.marks = marks; return s
        }
        override var canvasSize: CanvasSize { .square(HolographicFoilTests.side) }
        override func draw() {
            background(.black)
            let layer = makeRenderTarget()
            withTarget(layer) {
                background(.white)
                marks?(self)
            }
            drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
        }
    }

    /// A foil with no stripes, creases, or glints: the facets' shade alone.
    static func shadeOnly(facets: FacetField?, relief: Double = 0) -> Filter {
        .holographicFoil(facets: facets, bands: Ramp.stepped([.clear]),
                         lightAngle: light.angle, lightElevation: light.elevation,
                         relief: relief, creases: 0, glints: 0)
    }

    /// The gray the fragment writes for a facet at a pixel center, as the test
    /// reads its formula: the metal shade, the marker step, and the highlight.
    static func predictedGray(facet: Facet?, at p: Vector2) -> Double {
        let n = facet?.normal ?? .unitZ
        let f = max(0, n.dot(FacetField.lightDirection(angle: light.angle, elevation: light.elevation)))
        var shade = 0.26 + 0.64 * pow(f, 1.4) + 0.35 * pow(f, 28)
        if let facet {
            let side = (p - facet.centroid).dot(facet.tilt)
            let x = min(max((side + 0.75) / 1.5, 0), 1)
            shade += 0.07 * (x * x * (3 - 2 * x) - 0.5)
        }
        return shade
    }

    static func srgbByte(_ linear: Double) -> Double {
        let v = min(max(linear, 0), 1)
        return (v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055) * 255
    }

    // MARK: Identity

    @Test(.enabled(if: Snapshot.hasMetal))
    func amountZeroChangesNoByte() throws {
        let mark: @MainActor (Sketch) -> Void = { s in
            s.noStroke(); s.fill(Color(red: 1, green: 0, blue: 0)); s.drawCircle(60, 60, 12)
        }
        let plain = try OllinApp.image(of: FoilProbe.make(nil, marks: mark), frame: 1)
        let held = try OllinApp.image(of: FoilProbe.make(.holographicFoil(amount: 0), marks: mark), frame: 1)
        #expect(maxDifference(plain, held) == 0)
        // The gate can fail: the foil at full amount is another picture.
        let foiled = try OllinApp.image(of: FoilProbe.make(.holographicFoil(), marks: mark), frame: 1)
        #expect(maxDifference(plain, foiled) > 100)
    }

    /// The sheet the filter builds for itself is `FacetField.crumpled` over the
    /// layer with the same arguments, so a sketch that builds it draws creases
    /// that land on the filter's.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theDefaultSheetIsTheOneASketchCanBuild() throws {
        let built = FacetField.crumpled(in: Self.layer, spacing: 56, crinkle: 0.6, seed: 1)
        let byDefault = try OllinApp.image(of: FoilProbe.make(.holographicFoil()), frame: 1)
        let handed = try OllinApp.image(of: FoilProbe.make(.holographicFoil(facets: built)), frame: 1)
        #expect(maxDifference(byDefault, handed) == 0)
        let other = FacetField.crumpled(in: Self.layer, spacing: 56, crinkle: 0.6, seed: 2)
        let otherSeed = try OllinApp.image(of: FoilProbe.make(.holographicFoil(facets: other)), frame: 1)
        #expect(maxDifference(byDefault, otherSeed) > 60, "another seed is another sheet")
    }

    // MARK: The GPU facets are the CPU facets

    /// Under every facet's centroid the GPU writes the gray the CPU's normal
    /// predicts, within the dither: the fragment found the same facet, with the
    /// same corners and heights, as the sheet holds.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theGPUShadesEachFacetByTheCPUsNormal() throws {
        let sheet = FacetField.crumpled(in: Self.layer, spacing: 30, crinkle: 0.8, seed: 3)
        let px = Pixels(try OllinApp.image(of: FoilProbe.make(Self.shadeOnly(facets: sheet)), frame: 1))
        var checked = 0, worst = 0.0
        var misses: [String] = []
        for facet in sheet.facets {
            let c = facet.centroid
            guard c.x > 4, c.y > 4, c.x < Double(Self.side) - 4, c.y < Double(Self.side) - 4 else { continue }
            // The centroid's pixel must sit well inside the facet, or a
            // neighbor's shade bleeds in.
            let inradius = 2 * facet.area / facet.triangle.perimeter
            guard inradius > 3 else { continue }
            let center = Vector2(c.x.rounded(.down) + 0.5, c.y.rounded(.down) + 0.5)
            let predicted = Self.srgbByte(Self.predictedGray(facet: facet, at: center))
            let read = Double(px.gray(Int(center.x), Int(center.y)))
            let off = abs(read - predicted)
            worst = max(worst, off)
            checked += 1
            if off > 3 { misses.append("facet at \(c): read \(read), predicted \(predicted)") }
        }
        #expect(checked > 60, "\(checked) facets checked")
        #expect(misses.isEmpty, Comment(rawValue: "\(misses.count) of \(checked) facets off by more than 3 levels (worst \(worst)):\n" + misses.prefix(6).joined(separator: "\n")))
    }

    /// A pixel off a handed-in sheet reads as a flat facet: the shade of a
    /// face straight under the light, with no crease or glint.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aPixelOffTheSheetReadsFlat() throws {
        let small = FacetField.grid(in: Rectangle(x: 80, y: 80, width: 80, height: 80), spacing: 20, seed: 1) { p in
            12 * sin(p.x / 9)
        }
        let px = Pixels(try OllinApp.image(of: FoilProbe.make(Self.shadeOnly(facets: small)), frame: 1))
        let flat = Self.srgbByte(Self.predictedGray(facet: nil, at: .zero))
        for (x, y) in [(6, 6), (Self.side - 7, 6), (6, Self.side - 7), (Self.side - 7, Self.side - 7)] {
            #expect(abs(Double(px.gray(x, y)) - flat) <= 2, "(\(x), \(y)) reads \(px.gray(x, y)) against \(flat)")
        }
        // The sheet itself is there, and not flat.
        let under = sheet(small, px: px)
        #expect(under.count > 8)
        #expect(under.contains { abs(Double($0) - flat) > 8 }, "the small sheet shades its facets")
    }

    private func sheet(_ field: FacetField, px: Pixels) -> [Int] {
        field.facets.compactMap { f in
            let c = f.centroid
            guard c.x > 90, c.y > 90, c.x < 150, c.y < 150 else { return nil }
            return px.gray(Int(c.x), Int(c.y))
        }
    }

    // MARK: The break

    /// Across the creases of a crumpled sheet the stripe changes on most of
    /// them, and across the same creases of the flat sheet it mostly does not:
    /// the facets' tilts move the bands, and a flat facet moves them by nothing.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theRainbowBreaksAtACreaseAndRunsWholeOnAFlatSheet() throws {
        func filter(_ sheet: FacetField) -> Filter {
            .holographicFoil(facets: sheet, bandWidth: 24, bandAngle: -0.6, bandShift: 140,
                             lightAngle: Self.light.angle, lightElevation: Self.light.elevation,
                             creases: 0, glints: 0)
        }
        let crumpled = FacetField.crumpled(in: Self.layer, spacing: 30, crinkle: 1.2, seed: 5)
        let flat = FacetField.crumpled(in: Self.layer, spacing: 30, crinkle: 0, seed: 5)
        #expect(crumpled.points == flat.points, "the crinkle moves heights, not points")
        func breakShare(_ sheet: FacetField, reference: FacetField) throws -> Double {
            let px = Pixels(try OllinApp.image(of: FoilProbe.make(filter(sheet)), frame: 1))
            var pairs = 0, broken = 0
            for edge in reference.edges {
                let m = edge.midpoint
                let n = edge.direction.perpendicular
                let a = m + n * 3, b = m - n * 3
                guard [a, b].allSatisfy({ $0.x > 6 && $0.y > 6 && $0.x < Double(Self.side) - 6 && $0.y < Double(Self.side) - 6 }) else { continue }
                pairs += 1
                if abs(hueDistance(px, a, b)) > 0.04 { broken += 1 }
            }
            #expect(pairs > 100)
            return Double(broken) / Double(max(pairs, 1))
        }
        let whole = try breakShare(flat, reference: crumpled)
        let broken = try breakShare(crumpled, reference: crumpled)
        #expect(whole < 0.3, "flat sheet: the stripe changed across \(whole) of the creases")
        #expect(broken > 0.55, "crumpled sheet: the stripe changed across only \(broken) of the creases")
        #expect(broken > whole * 2)
    }

    /// The hue distance between two pixels, on the color wheel (0 to 0.5).
    private func hueDistance(_ px: Pixels, _ a: Vector2, _ b: Vector2) -> Double {
        func hue(_ p: Vector2) -> Double {
            let x = Int(p.x), y = Int(p.y)
            return Color(red: Double(px.channel(0, x, y)) / 255, green: Double(px.channel(1, x, y)) / 255,
                         blue: Double(px.channel(2, x, y)) / 255).hue
        }
        let d = abs(hue(a) - hue(b))
        return min(d, 1 - d)
    }

    // MARK: Relief

    /// A gray mark drawn into the layer presses in under `relief`: the facets
    /// whose corners it covers tilt, and a facet far from it does not move.
    @Test(.enabled(if: Snapshot.hasMetal))
    func reliefPressesAMarkIntoTheSheetAndNothingElse() throws {
        let sheet = FacetField.crumpled(in: Self.layer, spacing: 40, crinkle: 0.5, seed: 7)
        let mark: @MainActor (Sketch) -> Void = { s in
            s.noStroke(); s.fill(Color(white: 0.7)); s.drawRect(center: Vector2(120, 120), width: 60, height: 60)
        }
        let flat = Pixels(try OllinApp.image(of: FoilProbe.make(Self.shadeOnly(facets: sheet), marks: mark), frame: 1))
        let pressed = Pixels(try OllinApp.image(of: FoilProbe.make(Self.shadeOnly(facets: sheet, relief: 60), marks: mark), frame: 1))
        var nearMoved = 0, farMoved = 0
        for y in 0 ..< Self.side {
            for x in 0 ..< Self.side {
                let off = abs(flat.gray(x, y) - pressed.gray(x, y))
                guard off > 3 else { continue }
                let d = max(abs(x - 120), abs(y - 120))
                if d < 30 + 2 * 40 { nearMoved += 1 } else { farMoved += 1 }
            }
        }
        #expect(nearMoved > 500, "the mark moved \(nearMoved) pixels around it")
        #expect(farMoved == 0, "\(farMoved) pixels moved more than two facets from the mark")
    }

    // MARK: The creases on paper

    /// The creases a sketch draws from the sheet come back from the SVG it
    /// writes as the same segments, so a plotter gets exactly the sheet.
    @Test func theCreasesRoundTripThroughSVG() throws {
        final class Creases: Sketch {
            let sheet = FacetField.crumpled(in: HolographicFoilTests.layer, spacing: 48, crinkle: 0.6, seed: 4)
            override var canvasSize: CanvasSize { .square(HolographicFoilTests.side) }
            override func draw() {
                background(.white)
                stroke(.black); strokeWeight(1)
                for edge in sheet.edges { drawLine(edge) }
            }
        }
        let sketch = Creases()
        let text = try OllinApp.svg(of: sketch)
        let parsed = try SVG(data: Data(text.utf8))
        let segments = parsed.contours.filter { $0.points.count == 2 }
        let edges = sketch.sheet.edges
        #expect(segments.count == edges.count, "\(segments.count) segments for \(edges.count) creases")
        var missing = 0
        for edge in edges {
            let found = segments.contains { c in
                let (p, q) = (c.points[0], c.points[1])
                return (p.distance(to: edge.start) < 0.01 && q.distance(to: edge.end) < 0.01)
                    || (p.distance(to: edge.end) < 0.01 && q.distance(to: edge.start) < 0.01)
            }
            if !found { missing += 1 }
        }
        #expect(missing == 0, "\(missing) creases did not come back")
    }

    // MARK: Motion

    /// The bands sweep with the phase and the light turns the shading, so two
    /// frames of a moving foil differ, and the phase alone moves the stripes.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theFoilMovesWithItsPhaseAndItsLight() throws {
        final class Moving: Sketch {
            override var canvasSize: CanvasSize { .square(HolographicFoilTests.side) }
            override func draw() {
                background(.black)
                let layer = makeRenderTarget()
                withTarget(layer) { background(.white) }
                drawImage(layer.filtered(.holographicFoil(lightAngle: time * 0.5, phase: time * 2)).image, 0, 0)
            }
        }
        let first = try OllinApp.image(of: Moving(), frame: 1)
        let later = try OllinApp.image(of: Moving(), frame: 40)
        #expect(maxDifference(first, later) > 80)
        let still = try OllinApp.image(of: FoilProbe.make(.holographicFoil(creases: 0, glints: 0, phase: 0)), frame: 1)
        let swept = try OllinApp.image(of: FoilProbe.make(.holographicFoil(creases: 0, glints: 0, phase: 1)), frame: 1)
        #expect(maxDifference(still, swept) > 80, "the phase alone moves the stripes")
    }

    // MARK: Pixels

    private func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        let pa = Pixels(a), pb = Pixels(b)
        var worst = 0
        for i in 0 ..< min(pa.bytes.count, pb.bytes.count) {
            worst = max(worst, abs(Int(pa.bytes[i]) - Int(pb.bytes[i])))
        }
        return worst
    }
}
