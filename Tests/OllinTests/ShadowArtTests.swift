import Foundation
import Ollin
import Testing

/// Laws for shadow art. The claim is about what the carved solid throws, so the
/// tests cast its shadows and compare them with the ones asked for.
@Suite
struct ShadowArtTests {
    /// Two shadows come out exact when they are solid in the same rows, since the
    /// front and the side share the vertical axis.
    ///
    /// The side shape is deliberately lopsided. A disc or a square is the same
    /// picture turned over, so reading that silhouette along the wrong axis would
    /// carve a different solid and no law would notice.
    @Test func twoShadowsAreCastExactlyWhenTheirRowsAgree() {
        let circle = disc(size: 64)
        let bitten = bittenDisc(size: 64)     // the same rows, and not symmetric
        let art = shadowArt(fromFront: circle, fromSide: bitten, resolution: 40)
        #expect(art.count > 0)

        expect(art.shadow(from: .front), matches: circle, resolution: 40, "front")
        expect(art.shadow(from: .side), matches: bitten, resolution: 40, "side")
    }

    /// And they fall short when the rows disagree, which is the part that is easy
    /// to get wrong. The front and the side are seen from either end of the same
    /// vertical axis, so a row that is empty in one empties it in the other: no
    /// solid can throw a shadow where nothing is lit.
    @Test func twoShadowsFallShortWhenTheirRowsDisagree() {
        let n = 40
        let circle = disc(size: 64)           // empty in the top and bottom rows
        let letter = ell(size: 64)            // solid down to the very bottom
        let art = shadowArt(fromFront: circle, fromSide: letter, resolution: n)

        let cast = art.shadow(from: .side)
        let wanted = flags(letter, resolution: n)
        var short = 0
        for i in cast.indices {
            #expect(!(cast[i] && !wanted[i]), "the side shadow spilled outside the one asked for")
            if wanted[i], !cast[i] { short += 1 }
        }
        #expect(short > 0, "the rows disagree, so the side shadow has to fall short")

        // And what is lost is exactly the rows the circle leaves empty.
        let front = flags(circle, resolution: n)
        for row in 0 ..< n {
            let frontHasRow = (0 ..< n).contains { front[$0 + row * n] }
            for column in 0 ..< n where wanted[column + row * n] {
                #expect(cast[column + row * n] == frontHasRow,
                        "row \(row) came out wrong")
            }
        }
    }

    /// A point survives exactly where every shadow it is lit through says solid.
    /// That is the definition, checked voxel by voxel.
    @Test func aVoxelSurvivesOnlyWhereEveryShadowAgrees() {
        let a = disc(size: 48)
        let b = bittenDisc(size: 48)
        let n = 32
        let art = shadowArt(fromFront: a, fromSide: b, resolution: n)
        let front = flags(a, resolution: n)
        let side = flags(b, resolution: n)
        for z in 0 ..< n {
            for y in 0 ..< n {
                for x in 0 ..< n {
                    let wanted = front[x + y * n] && side[z + y * n]
                    #expect(art.isSolid(x, y, z) == wanted, "voxel \(x),\(y),\(z)")
                }
            }
        }
    }

    /// One shadow on its own is no constraint in the other two directions, so the
    /// solid is a prism: the same slice at every depth.
    @Test func oneShadowGivesAPrism() {
        let n = 24
        let art = shadowArt(fromFront: disc(size: 48), resolution: n)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let atFront = art.isSolid(x, y, 0)
                for z in 1 ..< n {
                    #expect(art.isSolid(x, y, z) == atFront, "column \(x),\(y) is not straight")
                }
            }
        }
        expect(art.shadow(from: .front), matches: disc(size: 48), resolution: n, "front")
    }

    /// Three shadows usually cannot all be cast, and the honest answer is that the
    /// ones thrown are *inside* the ones asked for rather than equal to them. This
    /// pins both halves: never larger, and here genuinely smaller.
    @Test func threeShadowsAreCastAtMostAndSometimesLess() {
        let n = 36
        // A cross, a disc, and a ring: no solid throws all three.
        let art = shadowArt(fromFront: cross(size: 48), fromSide: disc(size: 48),
                            fromAbove: ring(size: 48), resolution: n)
        let asked: [(ShadowArt.Side, [Bool])] = [
            (.front, flags(cross(size: 48), resolution: n)),
            (.side, flags(disc(size: 48), resolution: n)),
            (.above, flags(ring(size: 48), resolution: n)),
        ]
        var short = 0
        for (side, wanted) in asked {
            let cast = art.shadow(from: side)
            for i in cast.indices {
                #expect(!(cast[i] && !wanted[i]), "the \(side) shadow spilled outside the one asked for")
                if wanted[i], !cast[i] { short += 1 }
            }
        }
        #expect(short > 0, "these three shadows should not all be castable")
    }

    /// A shadow with nothing in it leaves nothing to carve, and no shadows at all
    /// leave nothing either: a solid has to be asked for.
    @Test func nothingAskedForIsNothingCarved() {
        let n = 16
        #expect(shadowArt(fromFront: Image(width: 32, height: 32, color: .black), resolution: n).count == 0)
        #expect(shadowArt(resolution: n).count == 0)
        // And everything asked for is everything carved.
        #expect(shadowArt(fromFront: Image(width: 32, height: 32, color: .white),
                          resolution: n).count == n * n * n)
    }

    /// Dark can mean solid instead, which is what a scanned drawing looks like.
    @Test func theSenseOfTheSilhouetteCanBeTurnedOver() {
        let n = 20
        let white = Image(width: 32, height: 32, color: .white)
        #expect(shadowArt(fromFront: white, resolution: n).count == n * n * n)
        #expect(shadowArt(fromFront: white, resolution: n, inverted: true).count == 0)
    }

    /// The carved solid comes back as a surface, and it is a real one: enough
    /// triangles to close over the voxels, and all of them inside the bounds.
    @Test func theSolidComesBackAsASurface() {
        let art = shadowArt(fromFront: disc(size: 48), fromSide: box(size: 48, inset: 0.25),
                            resolution: 24)
        let mesh = art.mesh
        #expect(mesh.positions.count > 100)
        #expect(mesh.indices.count % 3 == 0)
        for point in mesh.positions {
            #expect(point.x >= -1.001 && point.x <= 1.001)
            #expect(point.y >= -1.001 && point.y <= 1.001)
            #expect(point.z >= -1.001 && point.z <= 1.001)
        }
    }

    // MARK: - Helpers

    private func expect(_ cast: [Bool], matches picture: Image, resolution: Int,
                        _ name: String) {
        let wanted = flags(picture, resolution: resolution)
        var wrong = 0
        for i in cast.indices where cast[i] != wanted[i] { wrong += 1 }
        #expect(wrong == 0, "the \(name) shadow differs in \(wrong) of \(cast.count) cells")
    }

    /// The picture as flags, sampled the way the carving samples it.
    private func flags(_ picture: Image, resolution: Int) -> [Bool] {
        var out = [Bool](repeating: false, count: resolution * resolution)
        for row in 0 ..< resolution {
            for column in 0 ..< resolution {
                let x = Int((Double(column) + 0.5) / Double(resolution) * Double(picture.width))
                let y = Int((Double(row) + 0.5) / Double(resolution) * Double(picture.height))
                let color = picture[min(x, picture.width - 1), min(y, picture.height - 1)]
                out[column + row * resolution] = color.luminance * color.alpha >= 0.5
            }
        }
        return out
    }

    private func disc(size: Int) -> Image {
        paint(size: size) { u, v in (u * u + v * v).squareRoot() < 0.8 }
    }

    private func ring(size: Int) -> Image {
        paint(size: size) { u, v in
            let r = (u * u + v * v).squareRoot()
            return r < 0.85 && r > 0.45
        }
    }

    private func box(size: Int, inset: Double) -> Image {
        paint(size: size) { u, v in abs(u) < 1 - inset && abs(v) < 1 - inset }
    }

    /// The disc with a bite out of it: lopsided, so the same picture turned over
    /// is not this picture, and yet solid in every row the disc is, so the pair can
    /// really be cast.
    private func bittenDisc(size: Int) -> Image {
        paint(size: size) { u, v in
            let inside = (u * u + v * v).squareRoot() < 0.8
            let bite = u > 0.1 && u < 0.5 && v > 0.45 && v < 0.7
            return inside && !bite
        }
    }

    /// A lopsided shape that reaches rows the disc does not.
    private func ell(size: Int) -> Image {
        paint(size: size) { u, v in (u < -0.1 && v > -0.85) || (v > 0.4 && u < 0.8) }
    }

    private func cross(size: Int) -> Image {
        paint(size: size) { u, v in (abs(u) < 0.3 && abs(v) < 0.9) || (abs(v) < 0.3 && abs(u) < 0.9) }
    }

    private func paint(size: Int, _ inside: (Double, Double) -> Bool) -> Image {
        let picture = Image(width: size, height: size, color: .black)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let u = (Double(x) + 0.5) / Double(size) * 2 - 1
                let v = (Double(y) + 0.5) / Double(size) * 2 - 1
                picture[x, y] = inside(u, v) ? .white : .black
            }
        }
        return picture
    }
}
