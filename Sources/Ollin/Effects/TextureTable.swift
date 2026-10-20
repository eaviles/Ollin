import Foundation
import os
import simd

/// A set of records with a footprint each (the blobs of a `Patina`, the chips
/// of a `Terrazzo`) packed into the lookup strip a texture generator reads,
/// with a cell grid in front of them so a pixel finds the records that reach
/// it in a few reads rather than a walk of the whole set. The layout is the
/// one `FoilTable` packs a sheet into, with records of any fixed texel count:
///
/// - texel 0: the cell grid's columns and rows, the cell size in pixels, and
///   where the candidate list starts;
/// - texel 1: the grid's origin in pixels, where the records start, and how
///   many there are;
/// - one texel per cell: where its candidates start in the list, and how many;
/// - the candidate list: record indices, four to a texel;
/// - `texelsPerRecord` texels per record, in the order they were given.
///
/// Positions are layer pixels, so the strip does not depend on the layer's
/// size and a scatter built in canvas units lands where the sketch put it.
enum TextureTable {
    /// The most candidates one cell lists; the cap bounds the fragment's loop.
    static let maxCandidatesPerCell = 32

    /// One record to pack: the pixels it can touch, and its texels.
    struct Record {
        var bounds: Rectangle
        var texels: [SIMD4<Float>]
    }

    /// Pack `records` for a layer, every one `texelsPerRecord` texels long,
    /// over a grid of `cellSize` pixels.
    static func pack(_ records: [Record], texelsPerRecord: Int, cellSize: Double) -> [SIMD4<Float>] {
        guard !records.isEmpty else { return [SIMD4(1, 1, 1, 3), SIMD4(0, 0, 3, 0), SIMD4(0, 0, 0, 0)] }
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for record in records {
            let b = record.bounds
            minX = min(minX, b.x); maxX = max(maxX, b.x + b.width)
            minY = min(minY, b.y); maxY = max(maxY, b.y + b.height)
        }
        let cell = max(cellSize, 1)
        let columns = max(1, min(256, Int(((maxX - minX) / cell).rounded(.up)) + 1))
        let rows = max(1, min(256, Int(((maxY - minY) / cell).rounded(.up)) + 1))
        // One size for both axes, grown if the cap on the grid asks for it.
        let span = max((maxX - minX) / Double(columns), (maxY - minY) / Double(rows), cell)

        var lists = [[Int]](repeating: [], count: columns * rows)
        for (index, record) in records.enumerated() {
            let b = record.bounds
            let fx0 = max(0, Int(((b.x - minX) / span).rounded(.down)))
            let fx1 = min(columns - 1, Int(((b.x + b.width - minX) / span).rounded(.down)))
            let fy0 = max(0, Int(((b.y - minY) / span).rounded(.down)))
            let fy1 = min(rows - 1, Int(((b.y + b.height - minY) / span).rounded(.down)))
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
        let recordStart = candidateStart + candidates.count / 4

        var strip: [SIMD4<Float>] = []
        strip.reserveCapacity(recordStart + records.count * texelsPerRecord)
        strip.append(SIMD4(Float(columns), Float(rows), Float(span), Float(candidateStart)))
        strip.append(SIMD4(Float(minX), Float(minY), Float(recordStart), Float(records.count)))
        strip.append(contentsOf: cells)
        var k = 0
        while k < candidates.count {
            strip.append(SIMD4(candidates[k], candidates[k + 1], candidates[k + 2], candidates[k + 3]))
            k += 4
        }
        for record in records {
            var texels = record.texels
            while texels.count < texelsPerRecord { texels.append(SIMD4(repeating: 0)) }
            strip.append(contentsOf: texels.prefix(texelsPerRecord))
        }
        return strip
    }

    // MARK: Patina

    /// The most blooms a strip carries: the strip is one texture row, and a
    /// row has a width limit the page shares.
    static let maxBlobs = 1_000
    /// Texels per bloom: the center, radius, and tone; the four amplitudes;
    /// the four phases; the first two blisters' centers; their radii and the
    /// mass offset; the last two blisters' centers; their radii and the count.
    static let blobTexels = 7

    /// Pack `patina` for a layer.
    static func pack(_ patina: Patina) -> [SIMD4<Float>] {
        let blobs = Array(patina.blobs.prefix(maxBlobs))
        var reach = 1.0
        let records = blobs.map { blob -> Record in
            // The bloom reaches its outline's widest, plus the lip and the
            // powder drawn around it, read as a share of the radius, and the
            // drips run below it by up to 1.6 radii.
            let extent = blob.radius * (1 + blob.swing) + 0.12 * blob.radius + 2
            let dripReach = 1.6 * blob.radius
            reach = max(reach, extent + dripReach)
            let f = { (v: Double) in Float(v) }
            let blisters = blob.blisters.prefix(4)
            func blister(_ i: Int) -> Circle {
                i < blisters.count ? blisters[blisters.startIndex + i] : Circle(center: blob.center, radius: 0)
            }
            let b0 = blister(0), b1 = blister(1), b2 = blister(2), b3 = blister(3)
            return Record(
                bounds: Rectangle(x: blob.center.x - extent, y: blob.center.y - extent,
                                  width: 2 * extent, height: 2 * extent + dripReach),
                texels: [SIMD4(f(blob.center.x), f(blob.center.y), f(blob.radius), f(blob.tone)),
                         SIMD4(f(blob.amplitudes[0]), f(blob.amplitudes[1]), f(blob.amplitudes[2]), f(blob.amplitudes[3])),
                         SIMD4(f(blob.phases[0]), f(blob.phases[1]), f(blob.phases[2]), f(blob.phases[3])),
                         SIMD4(f(b0.center.x), f(b0.center.y), f(b1.center.x), f(b1.center.y)),
                         SIMD4(f(b0.radius), f(b1.radius), f(blob.massOffset.x), f(blob.massOffset.y)),
                         SIMD4(f(b2.center.x), f(b2.center.y), f(b3.center.x), f(b3.center.y)),
                         SIMD4(f(b2.radius), f(b3.radius), Float(blisters.count), 0)])
        }
        return pack(records, texelsPerRecord: blobTexels, cellSize: reach)
    }

    /// The strip for the blooms `Generator.rust` and `.verdigris` scatter when
    /// handed none: `Patina.scatter` over the layer, packed, kept by its
    /// arguments so a frame does not scatter again.
    static func defaultPatinaStrip(width: Int, height: Int, count: Int,
                                   radius: ClosedRange<Double>, seed: Int) -> [SIMD4<Float>] {
        let key = PatinaKey(width: width, height: height, count: count,
                            low: radius.lowerBound, high: radius.upperBound, seed: seed)
        if let strip = patinaCache.withLock({ $0[key] }) { return strip }
        let patina = Patina.scatter(in: Rectangle(x: 0, y: 0, width: Double(width), height: Double(height)),
                                    count: count, radius: radius, seed: seed)
        let strip = pack(patina)
        patinaCache.withLock { cache in
            if cache.count >= 8 { cache.removeAll() }
            cache[key] = strip
        }
        return strip
    }

    private struct PatinaKey: Hashable {
        var width: Int, height: Int, count: Int
        var low: Double, high: Double
        var seed: Int
    }

    private static let patinaCache = OSAllocatedUnfairLock<[PatinaKey: [SIMD4<Float>]]>(initialState: [:])

    // MARK: Terrazzo

    /// The most chips a strip carries.
    static let maxChips = 3_000
    /// Texels per chip: the center, radius, and rotation; the side count,
    /// tone, tier, and a hash; the first four corners; the last four.
    static let chipTexels = 4

    /// Pack `terrazzo` for a layer.
    static func pack(_ terrazzo: Terrazzo) -> [SIMD4<Float>] {
        let chips = Array(terrazzo.chips.prefix(maxChips))
        var reach = 1.0
        let records = chips.enumerated().map { index, chip -> Record in
            reach = max(reach, chip.radius + 1)
            let f = { (v: Double) in Float(v) }
            var corners = chip.corners.prefix(8).map(f)
            while corners.count < 8 { corners.append(0) }
            return Record(
                bounds: Rectangle(x: chip.center.x - chip.radius - 1, y: chip.center.y - chip.radius - 1,
                                  width: 2 * chip.radius + 2, height: 2 * chip.radius + 2),
                texels: [SIMD4(f(chip.center.x), f(chip.center.y), f(chip.radius), f(chip.rotation)),
                         SIMD4(Float(min(chip.sides, 8)), Float(chip.tone), Float(chip.tier),
                               Float(index % 1024) / 1024),
                         SIMD4(corners[0], corners[1], corners[2], corners[3]),
                         SIMD4(corners[4], corners[5], corners[6], corners[7])])
        }
        // A cell about two of the largest chips across: a few candidates a cell.
        return pack(records, texelsPerRecord: chipTexels, cellSize: 2 * reach)
    }

    /// The strip for the chips `Generator.terrazzo` scatters when handed none:
    /// `Terrazzo.scatter` over the layer, packed, kept by its arguments.
    static func defaultTerrazzoStrip(width: Int, height: Int, chipRadius: Double, density: Double,
                                     gap: Double, tones: Int, seed: Int) -> [SIMD4<Float>] {
        let key = TerrazzoKey(width: width, height: height, chipRadius: chipRadius,
                              density: density, gap: gap, tones: tones, seed: seed)
        if let strip = terrazzoCache.withLock({ $0[key] }) { return strip }
        let terrazzo = Terrazzo.scatter(in: Rectangle(x: 0, y: 0, width: Double(width), height: Double(height)),
                                        chipRadius: chipRadius, density: density, gap: gap,
                                        tones: tones, seed: seed)
        let strip = pack(terrazzo)
        terrazzoCache.withLock { cache in
            if cache.count >= 8 { cache.removeAll() }
            cache[key] = strip
        }
        return strip
    }

    private struct TerrazzoKey: Hashable {
        var width: Int, height: Int
        var chipRadius: Double, density: Double, gap: Double
        var tones: Int, seed: Int
    }

    private static let terrazzoCache = OSAllocatedUnfairLock<[TerrazzoKey: [SIMD4<Float>]]>(initialState: [:])
}
