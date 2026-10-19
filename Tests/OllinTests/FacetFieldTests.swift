import Foundation
import Testing
@testable import Ollin

/// A sheet of facets: each triangle's normal follows the height function it was
/// lifted by, the lattice covers its region, the creases are listed once, the
/// same seed makes the same sheet, and two facets of different tilt under one
/// band land in different stripes, which is what breaks a rainbow at a crease.
@Suite struct FacetFieldTests {

    static let region = Rectangle(x: 0, y: 0, width: 400, height: 300)

    // MARK: Normals

    /// A plane's gradient is constant, so every facet of a sheet lifted by a
    /// plane has the same normal, and it is the plane's: the normal's slope is
    /// minus the gradient, exactly.
    @Test func aPlaneGivesEveryFacetThePlanesNormal() {
        let (alpha, beta) = (0.35, -0.2)
        let sheet = FacetField.grid(in: Self.region, spacing: 40, seed: 3) { p in alpha * p.x + beta * p.y + 7 }
        #expect(sheet.facets.count > 50)
        for facet in sheet.facets {
            let n = facet.normal
            #expect(abs(n.length - 1) < 1e-12)
            #expect(n.z > 0)
            #expect(abs(n.x / n.z + alpha) < 1e-9, "x slope \(n.x / n.z) for gradient \(alpha)")
            #expect(abs(n.y / n.z + beta) < 1e-9, "y slope \(n.y / n.z) for gradient \(beta)")
        }
    }

    /// On a smooth height, a small facet's normal is within a few degrees of
    /// the analytic gradient at its centroid, and closer as the facets shrink.
    @Test func aSmoothHeightsNormalFollowsItsGradient() {
        func height(_ p: Vector2) -> Double { 30 * sin(p.x / 60) * cos(p.y / 80) }
        func gradient(_ p: Vector2) -> Vector2 {
            Vector2(30 / 60 * cos(p.x / 60) * cos(p.y / 80), -30 / 80 * sin(p.x / 60) * sin(p.y / 80))
        }
        func worstAngle(spacing: Double) -> Double {
            let sheet = FacetField.grid(in: Self.region, spacing: spacing, jitter: 0.3, seed: 5, height: height)
            var worst = 0.0
            // The facets inside the region: what the sheet is for. The ring
            // past its edge is there to cover it, not to be read.
            for facet in sheet.facets where Self.region.contains(facet.centroid) {
                let g = gradient(facet.centroid)
                let expected = Vector3(-g.x, -g.y, 1)
                let cosine = facet.normal.dot(expected) / expected.length
                worst = max(worst, acos(min(cosine, 1)))
            }
            return worst
        }
        let coarse = worstAngle(spacing: 24), fine = worstAngle(spacing: 8)
        #expect(coarse < 0.2, "worst angle \(coarse) rad at spacing 24")
        #expect(fine < 0.08, "worst angle \(fine) rad at spacing 8")
        #expect(fine < coarse * 0.6, "finer facets \(fine) should track the gradient closer than \(coarse)")
    }

    /// The hair-thin triangles a triangulation closes a jittered outline with
    /// are dropped from a lattice sheet, so no facet is a sliver and no crease
    /// runs the length of the hull.
    @Test func aLatticeSheetHasNoSlivers() {
        let sheet = FacetField.grid(in: Self.region, spacing: 24, jitter: 0.3, seed: 5) { _ in 0 }
        for facet in sheet.facets {
            let t = facet.triangle
            let inradius = 2 * t.area / t.perimeter
            #expect(inradius > 1, "a sliver of inradius \(inradius) at \(t.centroid)")
        }
        // A hull triangle may span two cells; a sliver along the hull spans many.
        #expect(sheet.edges.allSatisfy { $0.length < 24 * 3 }, "a crease runs the hull")
        // Trimming only drops: the full triangulation held every kept triple.
        let full = Delaunay(FacetField.latticePoints(in: Self.region, spacing: 24, jitter: 0.3, seed: 5))
        #expect(sheet.delaunay.indices.count < full.indices.count)
        #expect(sheet.delaunay.indices.count > full.indices.count * 9 / 10, "trimming dropped more than a tenth")
    }

    /// A flat sheet reads straight up, and `facing` is the cosine against the
    /// light: 1 head on, 0 grazing or from behind.
    @Test func facingIsTheCosineAgainstTheLight() {
        let flat = Facet(Triangle(Vector2(0, 0), Vector2(10, 0), Vector2(0, 10)), heights: SIMD3(0, 0, 0))
        #expect(flat.normal == .unitZ)
        #expect(flat.tilt == .zero)
        #expect(abs(flat.facing(.unitZ) - 1) < 1e-12)
        #expect(abs(flat.facing(Vector3(0, 0, 3)) - 1) < 1e-12, "the light's length does not matter")
        #expect(flat.facing(Vector3(1, 0, 0)) == 0)
        #expect(flat.facing(Vector3(0, 0, -1)) == 0)
        #expect(abs(flat.facing(lightAngle: 0, elevation: .pi / 2) - 1) < 1e-12)
        #expect(abs(flat.facing(lightAngle: 1, elevation: .pi / 6) - 0.5) < 1e-12)
        let light = FacetField.lightDirection(angle: 0.7, elevation: 0.4)
        #expect(abs(light.length - 1) < 1e-12)
        #expect(light.z > 0)
        // The tilt points downhill: a face rising toward +x leans toward -x.
        let rising = Facet(Triangle(Vector2(0, 0), Vector2(10, 0), Vector2(0, 10)), heights: SIMD3(0, 5, 0))
        #expect(rising.tilt.x < 0)
        #expect(abs(rising.tilt.y) < 1e-12)
    }

    // MARK: The lattice

    /// Every point of the region lies on some facet, including the corners,
    /// and the lattice is anchored at the origin: two regions that overlap
    /// share the points in their overlap.
    @Test func theLatticeCoversItsRegionAndIsAnchored() {
        let sheet = FacetField.grid(in: Self.region, spacing: 37, seed: 11) { _ in 0 }
        for y in stride(from: 0.0, through: 300, by: 25) {
            for x in stride(from: 0.0, through: 400, by: 25) {
                #expect(sheet.facet(containing: Vector2(x, y)) != nil, "no facet under (\(x), \(y))")
            }
        }
        let other = FacetField.latticePoints(in: Rectangle(x: 200, y: 100, width: 400, height: 300), spacing: 37, seed: 11)
        let shared = Set(sheet.points.map { "\($0.x),\($0.y)" }).intersection(other.map { "\($0.x),\($0.y)" })
        #expect(shared.count > 20, "the overlap shares \(shared.count) points")
        // Jitter stays inside its bound, so no two lattice points cross.
        let zero = FacetField.latticePoints(in: Self.region, spacing: 37, jitter: 0, seed: 11)
        for (p, q) in zip(sheet.points, zero) {
            #expect(abs(p.x - q.x) <= 37 * 0.25 + 1e-9)
            #expect(abs(p.y - q.y) <= 37 * 0.25 + 1e-9)
        }
    }

    /// Lifting again keeps the points and the triangles and changes only the
    /// heights, so a sheet that breathes never triangulates twice.
    @Test func liftingKeepsTheTriangulation() {
        let sheet = FacetField.grid(in: Self.region, spacing: 50, seed: 2) { _ in 0 }
        let lifted = sheet.lifted { p in p.x * 0.1 }
        #expect(lifted.delaunay.indices == sheet.delaunay.indices)
        #expect(lifted.points == sheet.points)
        #expect(lifted.facets.count == sheet.facets.count)
        #expect(lifted != sheet)
        #expect(sheet.facets.allSatisfy { $0.normal == .unitZ })
        #expect(lifted.facets.allSatisfy { $0.normal.x < 0 })
    }

    /// Every crease once: no segment repeats, every facet edge is listed, and
    /// the count is what a triangulation's edges add up to.
    @Test func everyCreaseIsListedOnce() {
        let sheet = FacetField.grid(in: Self.region, spacing: 45, seed: 4) { _ in 0 }
        let edges = sheet.edges
        func key(_ s: LineSegment) -> String {
            let a = s.start, b = s.end
            let (p, q) = (a.x, a.y) < (b.x, b.y) ? (a, b) : (b, a)
            return "\(p.x),\(p.y)-\(q.x),\(q.y)"
        }
        let keys = edges.map(key)
        #expect(Set(keys).count == keys.count, "a crease repeats")
        let listed = Set(keys)
        for facet in sheet.facets {
            for edge in facet.edges { #expect(listed.contains(key(edge))) }
        }
        // Euler: for a triangulated disc, 3T = 2E - H with H the hull edges.
        let triangles = sheet.facets.count
        #expect(edges.count > triangles, "\(edges.count) edges for \(triangles) facets")
        #expect(edges.count < 2 * triangles)
    }

    /// The same seed makes the same crumple, another seed another one, and the
    /// crinkle sets the swing.
    @Test func aCrumpleIsItsSeedsAndItsCrinkle() {
        let a = FacetField.crumpled(in: Self.region, spacing: 48, crinkle: 0.6, seed: 9)
        let b = FacetField.crumpled(in: Self.region, spacing: 48, crinkle: 0.6, seed: 9)
        let c = FacetField.crumpled(in: Self.region, spacing: 48, crinkle: 0.6, seed: 10)
        #expect(a == b)
        #expect(a != c)
        #expect(a.points != c.points, "the seed moves the lattice too")
        let flat = FacetField.crumpled(in: Self.region, spacing: 48, crinkle: 0, seed: 9)
        #expect(flat.facets.allSatisfy { $0.normal == .unitZ })
        let deep = FacetField.crumpled(in: Self.region, spacing: 48, crinkle: 1.2, seed: 9)
        let swing = { (s: FacetField) in (s.heights.max() ?? 0) - (s.heights.min() ?? 0) }
        #expect(swing(a) > 10)
        #expect(swing(deep) > swing(a) * 1.8)
    }

    // MARK: The band break

    /// Two facets under one band center, one flat and one leaning, read
    /// different band coordinates by the shift, and a stepped spectrum puts
    /// them in different stripes: the break the foil shows at every crease.
    @Test func twoTiltsUnderOneBandLandInDifferentStripes() {
        let t = Triangle(Vector2(100, 100), Vector2(160, 100), Vector2(100, 160))
        let flat = Facet(t, heights: SIMD3(0, 0, 0))
        let leaning = Facet(t, heights: SIMD3(0, 30, 24))
        #expect(flat.centroid == leaning.centroid)
        let angle = -0.6, shift = 90.0, bandWidth = 36.0
        let spectrum = Ramp.holographic
        let cycle = bandWidth * Double(spectrum.stops.count)
        func stripe(_ f: Facet) -> Color {
            let u = f.bandCoordinate(angle: angle, shift: shift)
            return spectrum.color(at: u / cycle - (u / cycle).rounded(.down))
        }
        #expect(flat.bandCoordinate(angle: angle, shift: shift) == flat.centroid.dot(Vector2(angle: angle)))
        #expect(abs(flat.bandCoordinate(angle: angle, shift: shift) - leaning.bandCoordinate(angle: angle, shift: shift)) > bandWidth,
                "the lean moves the band by less than a stripe")
        #expect(stripe(flat) != stripe(leaning))
        // With no shift the two sit in one stripe, since they share a centroid.
        #expect(flat.bandCoordinate(angle: angle, shift: 0) == leaning.bandCoordinate(angle: angle, shift: 0))
    }
}
