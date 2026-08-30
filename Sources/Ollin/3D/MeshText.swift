import Foundation

/// Solid type: a string set in an outline font and pushed into three dimensions.
///
/// Both halves of this exist already: a glyph is a vector `Shape`, and
/// `Mesh.extrude` turns a `Shape` into a solid that honors its holes. What sits
/// between them is two traps, which is why this is a call rather than a line in
/// a sketch. Text is laid out in canvas coordinates, where y grows *down*, and a
/// 3D world counts y *up*, so an extruded word arrives upside down. And a
/// glyph's curves are flattened and simplified against the size they are asked
/// for, so asking for a one-unit-tall letter returns a blob rather than a
/// letter.
public extension Mesh {

    /// `string` set in `font` and extruded `depth` deep along z: one solid,
    /// standing upright, centered on the model origin.
    ///
    /// `size` is the type size in **world units**, the 3D counterpart of
    /// `textSize`. It is the em, so a capital stands about `0.7 * size` tall and
    /// a line of text is a little taller than that. `depth` is the thickness,
    /// centered on `z = 0` like every other generator.
    ///
    /// ```swift
    /// let word = Mesh.text("Ollin", size: 2, depth: 0.4)
    /// // in draw():
    /// material(.metal(roughness: 0.3))
    /// drawMesh(word)
    /// ```
    ///
    /// The mesh is centered on the ink it actually has, in x and y, so a word
    /// placed at a point is centered on that point. `\n` starts a new line, and
    /// `align` sets how the lines line up with each other (it does nothing to a
    /// single line, which is centered either way).
    ///
    /// Build it once and keep it when the string does not change: every call
    /// triangulates the glyphs and raises their walls again. ``textGlyphs(_:font:size:depth:align:)``
    /// returns the same type as one mesh per glyph, for a word whose letters
    /// move on their own.
    ///
    /// Like any extrusion this carries no texture coordinates, so it takes a
    /// color and a material rather than an image.
    static func text(_ string: String, font: OutlineFont = .systemMedium,
                     size: Double = 1, depth: Double = 0.25,
                     align: HorizontalTextAlign = .center) -> Mesh {
        Mesh.joined(textGlyphs(string, font: font, size: size, depth: depth, align: align))
    }

    /// The same solid type as ``text(_:font:size:depth:align:)``, one mesh per
    /// glyph, each still in its place in the word.
    ///
    /// Drawing all of them draws the word. Each one carries its own position, so
    /// `mesh.center` is where that letter sits, which is what a letter turning on
    /// its own axis needs:
    ///
    /// ```swift
    /// for (i, glyph) in letters.enumerated() {
    ///     let c = glyph.center
    ///     withState {
    ///         translate(c)
    ///         rotateX(sin(time + Double(i) * 0.4))
    ///         translate(-c)
    ///         drawMesh(glyph)
    ///     }
    /// }
    /// ```
    ///
    /// A space has no ink, so it contributes no mesh: the count is the number of
    /// glyphs that draw something, not the number of characters.
    static func textGlyphs(_ string: String, font: OutlineFont = .systemMedium,
                           size: Double = 1, depth: Double = 0.25,
                           align: HorizontalTextAlign = .center) -> [Mesh] {
        guard size > 0, !string.isEmpty else { return [] }
        // Glyph curves are flattened and then simplified back to a fixed
        // tolerance in the units they were asked for, so a one-unit em would be
        // simplified until the letter is gone. Set the type large, then scale
        // the points: layout is linear in the size, so this is the same block,
        // finely traced, and every 3D size shares one cached set of outlines.
        let reference = 512.0
        let shapes = font.glyphShapes(for: string, size: reference, alignH: align,
                                      alignV: .baseline, direction: .automatic,
                                      at: .zero)
        guard !shapes.isEmpty else { return [] }

        var lo = Vector2(.infinity, .infinity)
        var hi = Vector2(-.infinity, -.infinity)
        for shape in shapes {
            for contour in shape.contours {
                for p in contour.points {
                    lo = Vector2(min(lo.x, p.x), min(lo.y, p.y))
                    hi = Vector2(max(hi.x, p.x), max(hi.y, p.y))
                }
            }
        }
        guard lo.x <= hi.x, lo.y <= hi.y else { return [] }
        let middle = (lo + hi) * 0.5
        let k = size / reference

        return shapes.compactMap { shape in
            let placed = Shape(contours: shape.contours.map { contour in
                Contour(contour.points.map {
                    Vector2(($0.x - middle.x) * k, ($0.y - middle.y) * k)
                }, closed: contour.isClosed)
            }, winding: shape.winding)
            let solid = Mesh.extrude(placed, depth: depth)
            return solid.isEmpty ? nil : solid.standingUp()
        }
    }
}

private extension Mesh {

    /// Turn a mesh built in canvas coordinates (y down) half a turn about x, so
    /// it stands up in a y-up world.
    ///
    /// A half turn rather than a mirror of y, on purpose: a mirror reverses every
    /// triangle's winding and turns its normal into the solid, which lights the
    /// letter from the inside. A rotation keeps both, and since it leaves x
    /// alone the word still reads left to right.
    func standingUp() -> Mesh {
        var turned = self
        turned.positions = positions.map { Vector3($0.x, -$0.y, -$0.z) }
        turned.normals = normals.map { Vector3($0.x, -$0.y, -$0.z) }
        return turned
    }

    /// One mesh holding all of `meshes`, indices renumbered as they are appended.
    /// The parts carry no texture coordinates (an extrusion emits none), so
    /// neither does the result.
    static func joined(_ meshes: [Mesh]) -> Mesh {
        guard meshes.count != 1 else { return meshes[0] }
        var all = Mesh(positions: [], indices: [])
        for mesh in meshes {
            let offset = UInt32(all.positions.count)
            all.positions.append(contentsOf: mesh.positions)
            all.normals.append(contentsOf: mesh.normals)
            all.indices.append(contentsOf: mesh.indices.map { $0 + offset })
        }
        return all
    }
}
