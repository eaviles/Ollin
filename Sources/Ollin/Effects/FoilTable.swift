import Foundation
import os
import simd

/// The facets of a `FacetField` packed into the lookup strip the holographic
/// foil fragment reads, with a cell grid in front of them so a pixel finds its
/// facet in a few reads rather than a walk of the whole sheet.
///
/// The strip is `float4` texels in this order:
///
/// - texel 0: the cell grid's columns and rows, the cell size in pixels, and
///   where the candidate list starts;
/// - texel 1: the grid's origin in pixels, where the facets start, and how many
///   there are;
/// - one texel per cell: where its candidates start in the list, and how many;
/// - the candidate list: facet indices, four to a texel;
/// - two texels per facet: the corners `a` and `b`, then `c` and the heights of
///   `b` and `c` above `a`, which is all a normal needs.
///
/// Positions are layer pixels, so the strip does not depend on the layer's size
/// and a sheet built in canvas units lands where the sketch put it. Every
/// number is an exact small integer or a position, and the strip is 32-bit
/// float, so nothing rounds.
enum FoilTable {
    /// The most facets a strip carries: past this the filter keeps the first
    /// ones, since the strip is one texture row and a row has a width limit the
    /// page shares.
    static let maxFacets = 5_000

    /// The most candidates one cell lists. A cell the size of a facet is
    /// touched by a handful; the cap only bounds the fragment's loop.
    static let maxCandidatesPerCell = 48

    /// Pack `field` for a layer. The cell size follows the facets' own size, so
    /// a cell holds a few of them whatever the sheet's density.
    static func pack(_ field: FacetField) -> [SIMD4<Float>] {
        let facets = Array(field.facets.prefix(maxFacets))
        guard !facets.isEmpty else { return [SIMD4(0, 0, 1, 2), SIMD4(0, 0, 2, 0)] }
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        var areaSum = 0.0
        for facet in facets {
            for p in facet.triangle.points {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            areaSum += facet.area
        }
        // A cell about the size of a typical facet: the square root of the mean
        // area, doubled so a facet spans a cell or two rather than many.
        let cellSize = max(2 * (areaSum / Double(facets.count)).squareRoot(), 1)
        let columns = max(1, min(256, Int(((maxX - minX) / cellSize).rounded(.up)) + 1))
        let rows = max(1, min(256, Int(((maxY - minY) / cellSize).rounded(.up)) + 1))
        let sizeX = max((maxX - minX) / Double(columns), 1e-9)
        let sizeY = max((maxY - minY) / Double(rows), 1e-9)
        // One size for both axes: the larger, so the grid covers the sheet.
        let cell = max(sizeX, sizeY, cellSize)

        var lists = [[Int]](repeating: [], count: columns * rows)
        for (index, facet) in facets.enumerated() {
            let points = facet.triangle.points
            let fx0 = max(0, Int(((points.map(\.x).min()! - minX) / cell).rounded(.down)))
            let fx1 = min(columns - 1, Int(((points.map(\.x).max()! - minX) / cell).rounded(.down)))
            let fy0 = max(0, Int(((points.map(\.y).min()! - minY) / cell).rounded(.down)))
            let fy1 = min(rows - 1, Int(((points.map(\.y).max()! - minY) / cell).rounded(.down)))
            guard fx1 >= fx0, fy1 >= fy0 else { continue }
            for y in fy0 ... fy1 {
                for x in fx0 ... fx1 where lists[y * columns + x].count < maxCandidatesPerCell {
                    lists[y * columns + x].append(index)
                }
            }
        }

        let candidateStart = 2 + columns * rows
        var candidates: [Float] = []
        var cells: [SIMD4<Float>] = []
        cells.reserveCapacity(columns * rows)
        for list in lists {
            cells.append(SIMD4(Float(candidates.count), Float(list.count), 0, 0))
            candidates.append(contentsOf: list.map { Float($0) })
        }
        while candidates.count % 4 != 0 { candidates.append(0) }
        let facetStart = candidateStart + candidates.count / 4

        var strip: [SIMD4<Float>] = []
        strip.reserveCapacity(facetStart + facets.count * 2)
        strip.append(SIMD4(Float(columns), Float(rows), Float(cell), Float(candidateStart)))
        strip.append(SIMD4(Float(minX), Float(minY), Float(facetStart), Float(facets.count)))
        strip.append(contentsOf: cells)
        var k = 0
        while k < candidates.count {
            strip.append(SIMD4(candidates[k], candidates[k + 1], candidates[k + 2], candidates[k + 3]))
            k += 4
        }
        for facet in facets {
            let t = facet.triangle, h = facet.heights
            strip.append(SIMD4(Float(t.a.x), Float(t.a.y), Float(t.b.x), Float(t.b.y)))
            strip.append(SIMD4(Float(t.c.x), Float(t.c.y), Float(h[1] - h[0]), Float(h[2] - h[0])))
        }
        return strip
    }

    /// The strip for the sheet `Filter.holographicFoil` builds when handed none:
    /// `FacetField.crumpled` over the layer, packed, kept by its arguments so a
    /// frame does not triangulate again.
    static func defaultStrip(width: Int, height: Int, spacing: Double, crinkle: Double, seed: Int) -> [SIMD4<Float>] {
        let key = DefaultKey(width: width, height: height, spacing: spacing, crinkle: crinkle, seed: seed)
        if let strip = cache.withLock({ $0[key] }) { return strip }
        let field = FacetField.crumpled(in: Rectangle(x: 0, y: 0, width: Double(width), height: Double(height)),
                                        spacing: spacing, crinkle: crinkle, seed: seed)
        let strip = pack(field)
        cache.withLock { cache in
            if cache.count >= 8 { cache.removeAll() }
            cache[key] = strip
        }
        return strip
    }

    private struct DefaultKey: Hashable {
        var width: Int, height: Int
        var spacing: Double, crinkle: Double
        var seed: Int
    }

    private static let cache = OSAllocatedUnfairLock<[DefaultKey: [SIMD4<Float>]]>(initialState: [:])

    /// A ramp sampled into the strip the fragment reads a stripe from: 256
    /// texels across one cycle of the bands, read by texel so a stepped ramp
    /// keeps its hard edges.
    static func bandStrip(_ ramp: Ramp) -> [SIMD4<Float>] {
        (0 ..< 256).map { ramp.color(at: (Double($0) + 0.5) / 256).linearRGBA }
    }
}
