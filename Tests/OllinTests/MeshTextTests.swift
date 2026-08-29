import Testing
import Foundation
@testable import Ollin

/// GPU-free checks on solid type (`Mesh.text` / `Mesh.textGlyphs`): the mesh
/// plumbing, the two traps the call exists for (a word arriving upside down, and
/// a glyph simplified away at world-unit sizes), and the geometry a letter with a
/// counter needs.
struct MeshTextTests {

    private let font = OutlineFont.systemMedium

    // MARK: Plumbing

    /// The mesh is a well-formed triangle list with unit normals, like every
    /// other generator.
    @Test func solidTypeIsWellFormed() {
        let mesh = Mesh.text("Ollin", font: font, size: 2, depth: 0.4)
        #expect(!mesh.isEmpty)
        #expect(mesh.indices.count % 3 == 0)
        #expect(mesh.normals.count == mesh.positions.count)
        for i in mesh.indices { #expect(Int(i) < mesh.positions.count) }
        for n in mesh.normals { #expect(abs(n.length - 1) < 1e-6) }
    }

    /// Nothing to set draws nothing, rather than an empty box or a crash.
    @Test func nothingToSetIsAnEmptyMesh() {
        #expect(Mesh.text("", font: font).isEmpty)
        #expect(Mesh.text("   ", font: font).isEmpty)
        #expect(Mesh.text("A", font: font, size: 0).isEmpty)
        #expect(Mesh.textGlyphs("", font: font).isEmpty)
    }

    /// The block is centered on its own ink, so a word placed at a point is
    /// centered on that point, and the thickness is the `depth` asked for,
    /// centered on z = 0 like every other generator.
    @Test func theBlockIsCenteredAndAsDeepAsAsked() {
        let mesh = Mesh.text("Ollin", font: font, size: 2, depth: 0.4)
        let b = mesh.bounds
        let center = mesh.center
        #expect(abs(center.x) < 1e-9)
        #expect(abs(center.y) < 1e-9)
        #expect(abs(center.z) < 1e-9)
        #expect(abs((b.max.z - b.min.z) - 0.4) < 1e-9)
    }

    /// `size` is the em in world units, so the ink scales with it exactly.
    @Test func sizeIsTheEmInWorldUnits() {
        let small = Mesh.text("H", font: font, size: 1).bounds
        let large = Mesh.text("H", font: font, size: 3).bounds
        let smallHeight = small.max.y - small.min.y
        let largeHeight = large.max.y - large.min.y
        #expect(abs(largeHeight / smallHeight - 3) < 1e-6)
        // A capital stands around 0.7 of the em, the figure the docs quote.
        #expect(smallHeight > 0.6 && smallHeight < 0.8)
    }

    // MARK: The first trap: which way is up

    /// Canvas y grows down and world y grows up, so the word has to be turned
    /// over. An upright `L` is wide at the foot and narrow at the head; upside
    /// down it is the other way about.
    @Test func theTypeStandsUp() {
        let mesh = Mesh.text("L", font: font, size: 2, depth: 0.2)
        let b = mesh.bounds
        let height = b.max.y - b.min.y
        let band = height * 0.15
        func width(from lo: Double, to hi: Double) -> Double {
            let xs = mesh.positions.filter { $0.y >= lo && $0.y <= hi }.map(\.x)
            guard let low = xs.min(), let high = xs.max() else { return 0 }
            return high - low
        }
        let foot = width(from: b.min.y, to: b.min.y + band)
        let head = width(from: b.max.y - band, to: b.max.y)
        #expect(foot > head * 1.5, "an upright L is wider at the foot: \(foot) vs \(head)")
    }

    /// Turning it over must not also turn it around: the word still reads left to
    /// right, so the foot of an `L` reaches to the right of its stem.
    @Test func theTypeIsNotMirrored() {
        let mesh = Mesh.text("L", font: font, size: 2, depth: 0.2)
        let b = mesh.bounds
        let band = (b.max.y - b.min.y) * 0.15
        let footRight = mesh.positions.filter { $0.y <= b.min.y + band }.map(\.x).max() ?? 0
        let headRight = mesh.positions.filter { $0.y >= b.max.y - band }.map(\.x).max() ?? 0
        #expect(footRight > headRight, "the foot reaches right of the stem: \(footRight) vs \(headRight)")
    }

    /// A mirror would reverse every triangle and leave the normals pointing into
    /// the solid, which lights a letter from the inside. Every face must still
    /// agree with the normal it carries.
    @Test func facesStillAgreeWithTheirNormals() {
        let mesh = Mesh.text("Ollin", font: font, size: 2, depth: 0.4)
        var faces = 0, disagreeing = 0
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = mesh.positions[Int(mesh.indices[i])]
            let b = mesh.positions[Int(mesh.indices[i + 1])]
            let c = mesh.positions[Int(mesh.indices[i + 2])]
            let wound = (b - a).cross(c - a)
            if wound.lengthSquared > 1e-12 {
                let stated = mesh.normals[Int(mesh.indices[i])]
                faces += 1
                if wound.normalized.dot(stated) < 0 { disagreeing += 1 }
            }
            i += 3
        }
        #expect(faces > 100)
        #expect(disagreeing == 0, "\(disagreeing) of \(faces) faces are inside out")
    }

    // MARK: The second trap: a letter simplified away

    /// A glyph's curves are simplified against the size they are asked for, so a
    /// one-unit em asked for directly comes back as a blob or as nothing at all.
    /// The call sets the type large and scales the points, so a small letter is
    /// still a letter. This is the counterfactual, run both ways.
    @Test func aSmallLetterIsStillALetter() {
        let naive = font.glyphShapes(for: "O", size: 1, alignH: .center, alignV: .baseline,
                                     direction: .automatic, at: .zero)
        let naiveMesh = naive.isEmpty ? Mesh(positions: [], indices: [])
                                      : Mesh.extrude(naive[0], depth: 0.25)
        let mesh = Mesh.text("O", font: font, size: 1, depth: 0.25)
        #expect(mesh.triangleCount > naiveMesh.triangleCount * 4,
                "\(mesh.triangleCount) triangles against the naive \(naiveMesh.triangleCount)")
        // Round, not a lump: the widest and tallest readings of the ring agree
        // with a letter rather than with a triangle.
        let b = mesh.bounds
        #expect((b.max.x - b.min.x) > 0.4)
        #expect((b.max.y - b.min.y) > 0.5)
    }

    /// The size the glyph is traced at must not change what the letter measures:
    /// the same word at two sizes is the same shape, scaled.
    @Test func theTraceSizeDoesNotChangeTheShape() {
        let one = Mesh.text("Og", font: font, size: 1)
        let four = Mesh.text("Og", font: font, size: 4)
        #expect(one.triangleCount == four.triangleCount)
        let a = one.bounds, b = four.bounds
        #expect(abs((b.max.x - b.min.x) / (a.max.x - a.min.x) - 4) < 1e-6)
    }

    // MARK: Letters, holes, and lines

    /// A letter with a counter keeps its hole, which is what makes the solid
    /// closed: every edge of the extrusion is walked once each way.
    @Test func aCounterStaysAHole() {
        let mesh = Mesh.text("o", font: font, size: 2, depth: 0.5)
        var walked: [UInt64: Int] = [:]
        let welded = mesh.welded()
        var i = 0
        while i + 2 < welded.indices.count {
            let tri = [welded.indices[i], welded.indices[i + 1], welded.indices[i + 2]]
            for e in 0..<3 {
                let a = UInt64(tri[e]), b = UInt64(tri[(e + 1) % 3])
                walked[a << 32 | b, default: 0] += 1
            }
            i += 3
        }
        var unmatched = 0
        for (key, count) in walked {
            let a = key >> 32, b = key & 0xFFFF_FFFF
            let back = walked[b << 32 | a] ?? 0
            if count != 1 || back != 1 { unmatched += 1 }
        }
        #expect(unmatched == 0, "\(unmatched) edges are not shared by exactly two faces")
    }

    /// One mesh per glyph that draws something, each in its place in the word,
    /// and drawing them all draws the same solid as the joined one.
    @Test func lettersComeApartAndGoBackTogether() {
        let letters = Mesh.textGlyphs("A B", font: font, size: 2, depth: 0.3)
        #expect(letters.count == 2, "a space has no ink")
        let joined = Mesh.text("A B", font: font, size: 2, depth: 0.3)
        #expect(joined.triangleCount == letters.reduce(0) { $0 + $1.triangleCount })
        #expect(letters[0].center.x < letters[1].center.x, "the letters keep their order")
        for letter in letters {
            #expect(abs(letter.center.z) < 1e-9)
        }
    }

    /// A new line stacks downward and the block grows taller, with the rows
    /// lined up the way `align` asks.
    @Test func aNewLineStacksDownward() {
        let one = Mesh.text("Ollin", font: font, size: 1)
        let two = Mesh.text("Ollin\nOllin", font: font, size: 1)
        let a = one.bounds, b = two.bounds
        #expect((b.max.y - b.min.y) > (a.max.y - a.min.y) * 1.8)
        #expect(abs((b.max.x - b.min.x) - (a.max.x - a.min.x)) < 1e-6)

        let left = Mesh.text("Ollin\nO", font: font, size: 1, align: .left)
        let right = Mesh.text("Ollin\nO", font: font, size: 1, align: .right)
        let shortRowLeft = left.positions.filter { $0.y < 0 }.map(\.x).min() ?? 0
        let shortRowRight = right.positions.filter { $0.y < 0 }.map(\.x).min() ?? 0
        #expect(shortRowLeft < shortRowRight, "a right-aligned short row starts further right")
    }

    /// One line has nothing to line up against, so `align` cannot move it: the
    /// block is centered on its own ink whatever it is asked for.
    @Test func alignmentOnlyMovesRowsAgainstEachOther() {
        let left = Mesh.text("Ollin", font: font, size: 2, align: .left)
        let right = Mesh.text("Ollin", font: font, size: 2, align: .right)
        #expect(left.positions.count == right.positions.count)
        for (a, b) in zip(left.positions, right.positions) {
            #expect(abs(a.x - b.x) < 1e-9)
            #expect(abs(a.y - b.y) < 1e-9)
        }
    }

    /// Building the word once is the advice, so the convenience form has to stay
    /// affordable when a sketch calls it every frame.
    @Test func buildingAWordIsAffordable() {
        _ = Mesh.text("Ollin", font: font, size: 2, depth: 0.4)   // warm the glyph cache
        let start = Date()
        for _ in 0..<10 { _ = Mesh.text("Ollin", font: font, size: 2, depth: 0.4) }
        let each = Date().timeIntervalSince(start) / 10
        #expect(each < 0.005, "a five-letter word costs \(each * 1000) ms to build")
    }
}
