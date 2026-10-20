import Ollin

/// Material textures by name, the pixel kind: a rust bloom, a verdigris
/// patina, a terrazzo floor, bubble wrap over a drawing, and a crease folded
/// into a heightfield, one picker across them. Each texture is a generator or
/// a filter the sketch asks for with a few parameters and a seed, and the two
/// scatters are geometry the sketch holds (`Patina`, `Terrazzo`): the GPU
/// paints the very blobs and chips the sketch can stroke, which the ink switch
/// shows. The blooms grow in one after another and the chips are laid largest
/// first, the light drifting around the sheet, so the textures move.
@main
final class Textures: Sketch {
    enum Texture: String, CaseIterable, ParamOption { case rust, verdigris, terrazzo, bubbleWrap, crease }

    @Param(style: .segmented, icon: "square.grid.2x2") var texture = Texture.rust
    @Param("Seed", 1 ... 99, icon: "dice") var seed = 7
    @Param("Size", 0.4 ... 2, icon: "circle.dashed") var size = 1.0
    @Param("Density", 0.2 ... 1, icon: "circle.hexagongrid") var density = 0.6
    @Param("Light drift", 0 ... 1, icon: "sun.max") var lightDrift = 0.15
    @Param("Outlines in ink", icon: "pencil.line") var drawsOutlines = false

    override var loopDuration: Double? { 16 }

    private var patina: Patina?
    private var floor: Terrazzo?
    private var builtFor: (seed: Int, size: Double, density: Double)?

    private func rebuildIfNeeded() {
        if let builtFor, builtFor == (seed, size, density) { return }
        let region = canvasRectangle
        let count = Int((8 + 14 * density).rounded())
        patina = Patina.scatter(in: region, count: count, radius: (40 * size) ... (150 * size), seed: seed)
        floor = Terrazzo.scatter(in: region, chipRadius: 44 * size, density: 0.3 + 0.5 * density,
                                 gap: 3 * size, tones: 5, seed: seed)
        builtFor = (seed, size, density)
    }

    /// The blooms grown in one after another over the loop: each blob's
    /// radius and blisters scaled by its own ease, the geometry rebuilt so the
    /// GPU paints the grown bloom.
    private func grownPatina(_ t: Double) -> Patina {
        guard let patina else { return Patina(blobs: []) }
        let blobs = patina.blobs.enumerated().map { i, blob -> Patina.Blob in
            let start = Double(i) / Double(max(patina.blobs.count, 1)) * 0.6
            let grow = smoothstep(start, start + 0.3, t)
            let scale = 0.15 + 0.85 * grow
            return Patina.Blob(center: blob.center, radius: blob.radius * scale,
                               amplitudes: blob.amplitudes, phases: blob.phases,
                               massOffset: blob.massOffset,
                               blisters: blob.blisters.map {
                                   Circle(center: blob.center + ($0.center - blob.center) * scale,
                                          radius: $0.radius * scale)
                               },
                               tone: blob.tone)
        }
        return Patina(blobs: blobs)
    }

    override func draw() {
        rebuildIfNeeded()
        let t = loopProgress(over: 16)
        let light = -2.2 + time * lightDrift

        switch texture {
        case .rust, .verdigris:
            background(Color(hex: 0x1A1B1E))
            let blooms = grownPatina(t)
            let layer = texture == .rust
                ? generate(.rust(blobs: blooms, lightAngle: light))
                : generate(.verdigris(blobs: blooms, lightAngle: light))
            drawImage(layer.image, 0, 0)
            if drawsOutlines {
                noFill()
                stroke(Color(white: 0.05, alpha: 0.7))
                strokeWeight(1.2 * scale)
                for blob in blooms.blobs {
                    drawPolygon(blob.outline.points)
                    for mass in blob.masses { drawPolygon(mass.points) }
                }
            }
        case .terrazzo:
            background(Color(hex: 0x1A1B1E))
            guard let floor else { return }
            // The chips laid largest first over the first half of the loop.
            let laid = Int(Double(floor.chips.count) * smoothstep(0, 0.55, t))
            let poured = Terrazzo(chips: Array(floor.chips.prefix(laid)), gap: floor.gap)
            drawImage(generate(.terrazzo(chips: poured)).image, 0, 0)
            if drawsOutlines {
                noFill()
                stroke(Color(white: 0.1, alpha: 0.8))
                strokeWeight(1.2 * scale)
                for chip in poured.chips { drawShape(chip.shape) }
            }
        case .bubbleWrap:
            // A drawing first, then the sheet over everything drawn.
            background(Color(hex: 0xF2EEE6))
            noStroke()
            let palette = [Color(hex: 0xE4572E), Color(hex: 0x2B6C8C), Color(hex: 0xF2B36A), Color(hex: 0x1F7A6B)]
            for i in 0 ..< 7 {
                let a = Double(i) / 7 * .tau + time * 0.25
                let r = width * (0.22 + 0.1 * sin(time * 0.4 + Double(i)))
                fill(palette[i % palette.count])
                drawCircle(width / 2 + cos(a) * r, height / 2 + sin(a) * r, width * 0.11)
            }
            fill(Color(hex: 0x1A1B1E))
            textFont(.systemBold)
            textSize(width * 0.16)
            textAlign(.center, .middle)
            drawText("WRAP", width / 2, height / 2)
            postProcess(.bubbleWrap(radius: 26 * size * scale, gap: 6 * size * scale, lightAngle: light))
        case .crease:
            // A sheet with three creases whose ends drift, lit from the
            // field's own slope so the folds read as folds.
            background(Color(hex: 0x1A1B1E))
            if baseSheet == nil || baseSeed != seed {
                baseSheet = Heightfield(columns: 257, rows: 257) { u, v in
                    0.5 + 0.06 * (fbm(u * 3 + Double(seed), v * 3, octaves: 3) - 0.5)
                }
                baseSeed = seed
            }
            guard var sheet = baseSheet else { return }
            for i in 0 ..< 3 {
                let swing = 0.12 * sin(time * 0.3 + Double(i) * 2.1)
                let from = Vector2(0.1 + 0.3 * Double(i) + swing, i == 1 ? 0.95 : 0.05)
                let to = Vector2(0.9 - 0.3 * Double(i) - swing, i == 1 ? 0.05 : 0.95)
                sheet = sheet.creased(along: [from, to], width: 0.02 * size, amplitude: 0.28 * density)
            }
            drawImage(shaded(sheet, lightAngle: light), in: canvasRectangle)
        }
    }

    private var baseSheet: Heightfield?
    private var baseSeed = 0

    /// The sheet lit as paper: each sample's normal from the field's own
    /// slope (central differences of the heights), one Lambert term against
    /// a light at `lightAngle`, painted through a paper ramp.
    private func shaded(_ field: Heightfield, lightAngle: Double) -> Image {
        let paper = Ramp([Color(hex: 0x8F8779), Color(hex: 0xE6DFD0), Color(hex: 0xFFFBF2)])
        let light = Vector3(cos(lightAngle) * 0.7, sin(lightAngle) * 0.7, 0.72).normalized
        let relief = 26.0
        var pixels = [UInt8]()
        pixels.reserveCapacity(field.columns * field.rows * 4)
        for y in 0 ..< field.rows {
            for x in 0 ..< field.columns {
                let left = field[max(x - 1, 0), y], right = field[min(x + 1, field.columns - 1), y]
                let up = field[x, max(y - 1, 0)], down = field[x, min(y + 1, field.rows - 1)]
                let normal = Vector3(-(right - left) * relief, -(down - up) * relief, 1).normalized
                let lit = 0.25 + 0.75 * max(0, normal.dot(light))
                let c = paper.color(at: min(max(lit, 0), 1))
                pixels.append(contentsOf: [UInt8((c.red * 255).rounded()), UInt8((c.green * 255).rounded()),
                                           UInt8((c.blue * 255).rounded()), 255])
            }
        }
        return Image(width: field.columns, height: field.rows, premultipliedRGBA: pixels)
            ?? Image(width: field.columns, height: field.rows, color: .white)
    }
}
