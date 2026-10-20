import Foundation
import Testing
@testable import Ollin

/// The scatters behind the material textures, on the CPU: a patina's blooms
/// keep their outline within the radii the waver allows, hold their masses and
/// blisters inside, and come back the same from a seed; a terrazzo's chips
/// never sit closer than the rule, come in their tiers and side counts, keep
/// every corner inside the circle, and come back the same from a seed; a
/// crease pressed into a heightfield matches the kernel's closed form at five
/// offsets and leaves the far sheet alone.
@Suite struct MaterialTextureTests {

    static let region = Rectangle(x: 0, y: 0, width: 600, height: 400)

    // MARK: Patina

    /// Every bloom's outline lies within the band the waver allows, so its area
    /// sits between the areas of the two bounding circles.
    @Test func aBloomsAreaLiesWithinItsRadii() {
        let patina = Patina.scatter(in: Self.region, count: 16, radius: 30 ... 90, seed: 4)
        #expect(patina.blobs.count >= 10)
        for blob in patina.blobs {
            let inner = blob.radius * (1 - blob.swing), outer = blob.radius * (1 + blob.swing)
            let area = Shape(blob.outline.points).area
            #expect(area >= .pi * inner * inner * 0.999, "area \(area) under the inner circle's \(Double.pi * inner * inner)")
            #expect(area <= .pi * outer * outer * 1.001, "area \(area) over the outer circle's \(Double.pi * outer * outer)")
            // And the outline's own radii stay in the band at every angle.
            for i in 0 ..< 360 {
                let r = blob.boundaryRadius(at: Double(i) / 360 * 2 * .pi)
                #expect(r >= inner - 1e-9 && r <= outer + 1e-9)
            }
        }
    }

    /// The nested masses and the blisters sit inside the bloom that holds them,
    /// read against the outline rather than the circle.
    @Test func massesAndBlistersStayInsideTheBloom() {
        let patina = Patina.scatter(in: Self.region, count: 12, radius: 40 ... 120, seed: 9)
        for blob in patina.blobs {
            for blister in blob.blisters {
                #expect(blob.contains(blister.center), "a blister's center off its bloom")
                #expect(blister.radius > 0 && blister.radius < blob.radius * 0.14)
            }
            // The second, smaller mass stays wholly inside; the first may poke
            // out on the thin side of a ragged bloom, so only its center is held.
            let small = blob.masses[1]
            let inside = small.points.filter { blob.contains($0) }.count
            #expect(inside == small.points.count, "\(small.points.count - inside) points of the inner mass outside the bloom")
            #expect(blob.contains(blob.masses[0].points.reduce(.zero, +) / Double(blob.masses[0].points.count)))
        }
    }

    /// The centers keep the scatter's rule: three quarters of the two radii.
    @Test func bloomsNeverStack() {
        let patina = Patina.scatter(in: Self.region, count: 30, radius: 20 ... 60, seed: 2)
        for (i, a) in patina.blobs.enumerated() {
            for b in patina.blobs[(i + 1)...] {
                #expect((a.center - b.center).length >= 0.75 * (a.radius + b.radius) - 1e-9)
            }
        }
    }

    /// The same seed makes the same patina, down to every blister; another
    /// seed makes another.
    @Test func aPatinaRepeatsFromItsSeed() {
        let a = Patina.scatter(in: Self.region, count: 10, seed: 11)
        let b = Patina.scatter(in: Self.region, count: 10, seed: 11)
        let c = Patina.scatter(in: Self.region, count: 10, seed: 12)
        #expect(a == b)
        #expect(a != c)
        #expect(TextureTable.pack(a) == TextureTable.pack(b))
    }

    // MARK: Terrazzo

    /// No two chips' circles come closer than the gap: counted over every
    /// pair, the violations are zero.
    @Test func chipsNeverSitCloserThanTheRule() {
        let floor = Terrazzo.scatter(in: Self.region, chipRadius: 30, density: 0.6, gap: 3, seed: 5)
        #expect(floor.chips.count > 60, "only \(floor.chips.count) chips")
        var violations = 0
        var pairs = 0
        for (i, a) in floor.chips.enumerated() {
            for b in floor.chips[(i + 1)...] {
                pairs += 1
                if (a.center - b.center).length < a.radius + b.radius + floor.gap - 1e-9 { violations += 1 }
            }
        }
        #expect(pairs > 1000)
        #expect(violations == 0, "\(violations) pairs under the rule")
    }

    /// The chips come in the three tiers at their radii, largest first, with
    /// five to eight sides, every corner inside the circle and one on it.
    @Test func chipsComeInTiersWithTheirCorners() {
        let floor = Terrazzo.scatter(in: Self.region, chipRadius: 30, density: 0.6, seed: 5)
        var tiers = Set<Int>()
        var lastTier = 0
        for chip in floor.chips {
            tiers.insert(chip.tier)
            #expect(chip.tier >= lastTier, "a smaller tier placed before a larger one")
            lastTier = chip.tier
            #expect(abs(chip.radius - 30 * Terrazzo.tierScales[chip.tier]) < 1e-9)
            #expect((5 ... 8).contains(chip.sides))
            #expect(chip.corners.allSatisfy { $0 >= 0.72 - 1e-9 && $0 <= 1 + 1e-9 })
            #expect(abs((chip.corners.max() ?? 0) - 1) < 1e-9, "no corner on the circle")
            for p in chip.points { #expect((p - chip.center).length <= chip.radius + 1e-9) }
            #expect(chip.contains(chip.center))
        }
        #expect(tiers == [0, 1, 2])
    }

    /// The same seed lays the same floor.
    @Test func aFloorRepeatsFromItsSeed() {
        let a = Terrazzo.scatter(in: Self.region, seed: 21)
        let b = Terrazzo.scatter(in: Self.region, seed: 21)
        let c = Terrazzo.scatter(in: Self.region, seed: 22)
        #expect(a == b)
        #expect(a != c)
        #expect(TextureTable.pack(a) == TextureTable.pack(b))
    }

    /// A denser floor holds more chips and covers more of the region, up to
    /// where the darts jam.
    @Test func densityLaysMoreChips() {
        func coverage(_ floor: Terrazzo) -> Double {
            floor.chips.reduce(0) { $0 + Shape($1.points).area } / (Self.region.width * Self.region.height)
        }
        let sparse = Terrazzo.scatter(in: Self.region, chipRadius: 30, density: 0.2, seed: 3)
        let dense = Terrazzo.scatter(in: Self.region, chipRadius: 30, density: 0.6, seed: 3)
        let counts = "sparse \(sparse.chips.count) chips covering \(coverage(sparse)), dense \(dense.chips.count) covering \(coverage(dense))"
        #expect(dense.chips.count > sparse.chips.count, Comment(rawValue: counts))
        #expect(coverage(dense) > coverage(sparse) * 1.5, Comment(rawValue: counts))
        #expect(coverage(sparse) > 0.12 && coverage(sparse) < 0.3, Comment(rawValue: counts))
        #expect(coverage(dense) > 0.35, Comment(rawValue: counts))
    }

    // MARK: The lookup strip

    /// Every record the strip lists under a cell reaches that cell, and every
    /// record is listed under the cell its center falls in.
    @Test func theStripListsEveryRecordUnderItsCell() {
        let floor = Terrazzo.scatter(in: Self.region, chipRadius: 30, density: 0.5, seed: 8)
        let strip = TextureTable.pack(floor)
        let columns = Int(strip[0].x), rows = Int(strip[0].y)
        let cell = Double(strip[0].z), candidateStart = Int(strip[0].w)
        let originX = Double(strip[1].x), originY = Double(strip[1].y)
        let recordStart = Int(strip[1].z)
        #expect(Int(strip[1].w) == floor.chips.count)
        for (index, chip) in floor.chips.enumerated() {
            let cx = min(max(Int(((chip.center.x - originX) / cell).rounded(.down)), 0), columns - 1)
            let cy = min(max(Int(((chip.center.y - originY) / cell).rounded(.down)), 0), rows - 1)
            let slot = strip[2 + cy * columns + cx]
            let listed = (0 ..< Int(slot.y)).map { k -> Int in
                let i = Int(slot.x) + k
                let four = strip[candidateStart + i / 4]
                return Int(four[i % 4])
            }
            #expect(listed.contains(index), "chip \(index) missing from its cell")
            let record = strip[recordStart + index * TextureTable.chipTexels]
            #expect(abs(Double(record.x) - chip.center.x) < 1e-3 && abs(Double(record.z) - chip.radius) < 1e-3)
        }
    }

    // MARK: Creases

    /// The kernel's closed form: 1 at the crease, the asymmetric flanks, the
    /// troughs two widths out, and nothing far away.
    @Test func theCreaseProfileHasItsShape() {
        #expect(abs(Heightfield.creaseProfile(at: 0) - (1 - 0.35 * exp(-8))) < 1e-12)
        #expect(Heightfield.creaseProfile(at: 1) > Heightfield.creaseProfile(at: -1), "the positive flank lifts")
        #expect(Heightfield.creaseProfile(at: -2) < -0.3, "the trough on the lowered side")
        #expect(Heightfield.creaseProfile(at: 2) < 0.1, "the trough on the lifted side")
        #expect(abs(Heightfield.creaseProfile(at: 12)) < 1e-3)
        #expect(abs(Heightfield.creaseProfile(at: -12)) < 1e-3)
    }

    /// A straight crease across a flat sheet adds the kernel at every sample:
    /// read at five offsets against the closed form evaluated by hand, and
    /// unchanged twelve widths away.
    @Test func aCreaseMatchesTheKernelAtFiveOffsets() {
        let flat = Heightfield(columns: 201, rows: 101, repeating: 0.5)
        let width = 0.05, amplitude = 0.2
        // A horizontal crease at v = 0.5, walked left to right.
        let sheet = flat.creased(along: [Vector2(0, 0.5), Vector2(1, 0.5)], width: width, amplitude: amplitude)
        for s in [-2.5, -1.0, 0.0, 0.6, 2.0] {
            // The positive side is where the direction (1, 0) crossed with the
            // offset to the sample is positive: the larger v.
            let v = 0.5 + s * width
            let y = Int((v * 100).rounded())
            let expectedS = (Double(y) / 100 - 0.5) / width
            let floor = 0.004
            let cusp = exp(floor.squareRoot() - (expectedS * expectedS + floor).squareRoot())
            let step = 0.3 * tanh(2 * expectedS) * exp(-expectedS * expectedS / 8)
            let off = abs(expectedS) - 2
            let trough = -0.35 * exp(-off * off / 0.5)
            let expected = 0.5 + amplitude * (cusp + step + trough)
            #expect(abs(sheet[100, y] - expected) < 1e-9, "at s \(expectedS): \(sheet[100, y]) against \(expected)")
        }
        // The sign: the sample past the crease (larger v) is on the positive
        // side of a left-to-right walk, and sits higher than its mirror.
        #expect(sheet[100, 55] > sheet[100, 45])
        // Far from the crease nothing but the tail's trace remains.
        #expect(abs(sheet[100, 0] - 0.5) < amplitude * 1e-3)
        #expect(abs(sheet[100, 100] - 0.5) < amplitude * 1e-3)
        // Walked the other way, the flanks swap.
        let back = flat.creased(along: [Vector2(1, 0.5), Vector2(0, 0.5)], width: width, amplitude: amplitude)
        #expect(abs(back[100, 45] - sheet[100, 55]) < 1e-12)
    }

    /// A path of one point, a zero width, or a zero amplitude changes nothing.
    @Test func aDegenerateCreaseChangesNothing() {
        let sheet = Heightfield(columns: 33, rows: 33) { u, v in u * v }
        #expect(sheet.creased(along: [Vector2(0.5, 0.5)], width: 0.1, amplitude: 1).values == sheet.values)
        #expect(sheet.creased(along: [Vector2(0, 0), Vector2(1, 1)], width: 0, amplitude: 1).values == sheet.values)
        #expect(sheet.creased(along: [Vector2(0, 0), Vector2(1, 1)], width: 0.1, amplitude: 0).values == sheet.values)
    }
}
