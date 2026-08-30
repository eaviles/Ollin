import Ollin
import Testing

/// Pure-CPU checks on `Heightfield`: construction and sampling, diamond-square
/// determinism and range, both erosion passes (deterministic, bounded, doing
/// what they claim), and the mesh/image emission. No GPU.
@Suite
struct HeightfieldTests {

    // MARK: Construction & sampling

    @Test func fieldInitializerSamplesNormalizedCoordinates() {
        let field = Heightfield(columns: 5, rows: 3) { u, v in u + v * 10 }
        #expect(field[0, 0] == 0)
        #expect(abs(field[4, 0] - 1) < 1e-12)
        #expect(abs(field[0, 2] - 10) < 1e-12)
        #expect(abs(field[2, 1] - (0.5 + 5)) < 1e-12)
    }

    @Test func bilinearSamplingMatchesCornersAndMidpoints() {
        var field = Heightfield(columns: 2, rows: 2)
        field[0, 0] = 0; field[1, 0] = 1
        field[0, 1] = 0; field[1, 1] = 1
        #expect(field.value(u: 0, v: 0) == 0)
        #expect(field.value(u: 1, v: 1) == 1)
        #expect(abs(field.value(u: 0.5, v: 0.5) - 0.5) < 1e-12)
        // Clamped past the edges.
        #expect(field.value(u: -1, v: 0) == 0)
        #expect(field.value(u: 2, v: 0) == 1)
    }

    @Test func normalizedSpansZeroToOne() {
        let field = Heightfield(columns: 3, rows: 2, values: [2, 4, 6, 8, 10, 12])
        let unit = field.normalized()
        #expect(unit.values.min() == 0)
        #expect(unit.values.max() == 1)
        // A flat field maps to zeros rather than dividing by nothing.
        let flat = Heightfield(columns: 2, rows: 2, repeating: 3).normalized()
        #expect(flat.values.allSatisfy { $0 == 0 })
    }

    // MARK: Diamond-square

    @Test func diamondSquareRoundsUpToPowerOfTwoPlusOne() {
        #expect(Heightfield.diamondSquare(size: 100, seed: 1).columns == 129)
        #expect(Heightfield.diamondSquare(size: 129, seed: 1).columns == 129)
        #expect(Heightfield.diamondSquare(size: 130, seed: 1).columns == 257)
    }

    @Test func diamondSquareIsDeterministicPerSeed() {
        let a = Heightfield.diamondSquare(size: 65, roughness: 0.6, seed: 42)
        let b = Heightfield.diamondSquare(size: 65, roughness: 0.6, seed: 42)
        let c = Heightfield.diamondSquare(size: 65, roughness: 0.6, seed: 43)
        #expect(a.values == b.values)
        #expect(a.values != c.values)
    }

    @Test func diamondSquareIsNormalizedAndFinite() {
        let field = Heightfield.diamondSquare(size: 65, roughness: 0.8, seed: 7)
        #expect(field.values.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        #expect(field.values.min() == 0)
        #expect(field.values.max() == 1)
    }

    // MARK: Hydraulic erosion

    private func hills(_ side: Int = 33) -> Heightfield {
        Heightfield(columns: side, rows: side) { u, v in
            0.5 + 0.4 * sin(u * .tau) * cos(v * .tau)
        }
    }

    @Test func hydraulicErosionIsDeterministicPerSeed() {
        let land = hills()
        let a = land.eroded(.hydraulic(drops: 2_000), seed: 9)
        let b = land.eroded(.hydraulic(drops: 2_000), seed: 9)
        let c = land.eroded(.hydraulic(drops: 2_000), seed: 10)
        #expect(a.values == b.values)
        #expect(a.values != c.values)
    }

    @Test func hydraulicErosionActuallyMovesMaterialAndStaysBounded() {
        let land = hills()
        let eroded = land.eroded(.hydraulic(drops: 2_000), seed: 9)
        #expect(eroded.values != land.values)
        // Heights stay finite and never dig below zero; drops carry material
        // off the map, so total mass can only stay or go down.
        #expect(eroded.values.allSatisfy { $0.isFinite && $0 >= 0 })
        let before = land.values.reduce(0, +)
        let after = eroded.values.reduce(0, +)
        #expect(after <= before + 1e-9)
    }

    @Test func zeroDropsLeaveTheFieldUntouched() {
        let land = hills()
        #expect(land.eroded(.hydraulic(drops: 0), seed: 1).values == land.values)
    }

    // MARK: Thermal erosion

    @Test func thermalErosionRelaxesSlopesTowardTheTalus() {
        // A single spike sheds into a scree cone; the worst neighbor step
        // shrinks and mass is conserved exactly (nothing leaves the map).
        var land = Heightfield(columns: 17, rows: 17, repeating: 0)
        land[8, 8] = 1
        let settled = land.eroded(.thermal(talus: 0.02, iterations: 200))

        func worstStep(_ f: Heightfield) -> Double {
            var worst = 0.0
            for y in 0 ..< f.rows {
                for x in 1 ..< f.columns {
                    worst = max(worst, abs(f[x, y] - f[x - 1, y]))
                }
            }
            for y in 1 ..< f.rows {
                for x in 0 ..< f.columns {
                    worst = max(worst, abs(f[x, y] - f[x, y - 1]))
                }
            }
            return worst
        }
        #expect(worstStep(settled) < worstStep(land))
        #expect(settled[8, 8] < 1)
        let before = land.values.reduce(0, +)
        let after = settled.values.reduce(0, +)
        #expect(abs(before - after) < 1e-9)
        #expect(settled.values.allSatisfy { $0.isFinite && $0 >= 0 })
    }

    @Test func thermalErosionLeavesRestingSlopesAlone() {
        // A gentle ramp entirely under the talus angle must not move at all.
        let ramp = Heightfield(columns: 9, rows: 9) { u, _ in u * 0.05 }
        let settled = ramp.eroded(.thermal(talus: 0.02, iterations: 50))
        for (a, b) in zip(ramp.values, settled.values) {
            #expect(abs(a - b) < 1e-12)
        }
    }

    // MARK: Mesh & image emission

    @Test func meshHasTheRightShape() {
        let field = Heightfield(columns: 4, rows: 3) { u, _ in u }
        let mesh = field.mesh(width: 30, depth: 20, height: 5)
        #expect(mesh.positions.count == 12)
        #expect(mesh.normals.count == 12)
        #expect(mesh.uvs.count == 12)
        #expect(mesh.triangleCount == 3 * 2 * 2)
        // Centered on the origin in the ground plane, heights lifted on +y.
        #expect(abs(mesh.positions.first!.x - -15) < 1e-12)
        #expect(abs(mesh.positions.last!.x - 15) < 1e-12)
        #expect(abs(mesh.positions.first!.z - -10) < 1e-12)
        #expect(abs(mesh.positions.last!.z - 10) < 1e-12)
        #expect(abs(mesh.positions.last!.y - 5) < 1e-12)
        // Unit normals, and a tilted-plane field tilts them against the slope.
        for n in mesh.normals {
            #expect(abs(n.length - 1) < 1e-9)
            #expect(n.y > 0)
            #expect(n.x < 0)   // heights rise with +x, so normals lean -x
        }
        // UVs span the unit square.
        #expect(mesh.uvs.first! == Vector2(0, 0))
        #expect(mesh.uvs.last! == Vector2(1, 1))
    }

    @Test func meshWindingFacesUp() {
        // Every triangle of an up-facing terrain must wind counter-clockwise
        // seen from +y: the cross product of its edges points up.
        let field = Heightfield(columns: 3, rows: 3) { u, v in u * v }
        let mesh = field.mesh(width: 10, depth: 10, height: 2)
        for t in 0 ..< mesh.triangleCount {
            let a = mesh.positions[Int(mesh.indices[t * 3])]
            let b = mesh.positions[Int(mesh.indices[t * 3 + 1])]
            let c = mesh.positions[Int(mesh.indices[t * 3 + 2])]
            let normal = (b - a).cross(c - a)
            #expect(normal.y > 0)
        }
    }

    @Test func imageIsTheGrayscaleHeightmap() {
        var field = Heightfield(columns: 2, rows: 2, repeating: 0)
        field[1, 0] = 1
        field[0, 1] = 0.5
        let image = field.image()
        #expect(image.width == 2 && image.height == 2)
        #expect(image[0, 0].red == 0)
        #expect(image[1, 0].red == 1)
        #expect(abs(image[0, 1].red - 0.5) < 0.01)
    }
}
