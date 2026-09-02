import Ollin

/// Wave Function Collapse, the overlapping model: instead of declaring tiles and
/// the edges that may meet, you hand it a small picture and it works the
/// vocabulary out for itself. It cuts the sample into every little square patch
/// the sample contains, notes how often each one turns up and which ones may
/// overlap, then fills a much larger grid so that every overlap agrees.
///
/// What comes out is new, but locally it is made of nothing that wasn't in the
/// sample: the same walls, the same weave, the same flowers, arranged in a way
/// the sample never showed. The samples here are authored right in the source as
/// little character grids, so you can edit one and watch the texture change.
///
/// The `motif` parameter picks a sample, `patternSize` sets how much context a patch
/// carries (2 keeps only the loosest sense of it, 4 reproduces whole motifs), and
/// `symmetry` decides whether turned and mirrored copies are learned too. Flowers
/// know which way is up, so try them at `.none`.
@main
final class TextureSynthesisSketch: Sketch {
    override var canvasSize: CanvasSize { .square(1080) }

    enum Motif: String, CaseIterable, ParamOption {
        case rooms, weave, flowers
    }

    @Param var motif: Motif = .rooms
    @Param(2 ... 4) var patternSize: Int = 3
    @Param var symmetry: WFCSymmetry = .all
    @Param var wrapsSample: Bool = true
    @Param var tileable: Bool = false

    private var texture: Image?
    private var sample: Image?
    private var lastSettings = ""
    private var patternCount = 0

    override func draw() {
        background(Color(hex: 0x0E1116))
        resolveIfNeeded()

        let margin = 44.0 * scale
        let sampleBox = Rectangle(x: margin, y: margin,
                                  width: 240 * scale, height: 240 * scale)
        let outputBox = Rectangle(x: margin, y: sampleBox.y + sampleBox.height + 56 * scale,
                                  width: width - margin * 2,
                                  height: height - (sampleBox.y + sampleBox.height + 56 * scale) - margin)

        if let sample { drawPixels(sample, in: sampleBox) }
        if let texture { drawPixels(texture, in: outputBox) }

        noStroke()
        fill(Color(hex: 0x8A93A3))
        textSize(17 * scale)
        drawText("the sample", at: Vector2(sampleBox.x, sampleBox.y - 14 * scale))
        let learned = "\(patternCount) patterns learned from a \(sample?.width ?? 0)x\(sample?.height ?? 0) sample"
        drawText(learned, at: Vector2(sampleBox.x + sampleBox.width + 28 * scale,
                                      sampleBox.y + 24 * scale))
        fill(Color(hex: 0x5D6675))
        drawText("every square of the picture below is one the sample already contained",
                 at: Vector2(sampleBox.x + sampleBox.width + 28 * scale,
                             sampleBox.y + 52 * scale))
    }

    /// Learn and solve only when something actually changed: both halves are real
    /// work, and neither belongs in a frame loop.
    private func resolveIfNeeded() {
        let settings = "\(motif)-\(patternSize)-\(symmetry)-\(wrapsSample)-\(tileable)"
        guard settings != lastSettings else { return }
        lastSettings = settings

        let source = Self.image(for: motif)
        sample = source
        seed(7)
        guard let model = OverlappingWFC(learningFrom: source, patternSize: patternSize,
                                         symmetry: symmetry, wrapsSample: wrapsSample) else {
            texture = nil
            patternCount = 0
            return
        }
        patternCount = model.patternCount
        texture = wfc(model, width: 72, height: 44, tileable: tileable) ?? texture
    }

    /// Draw an image as one rectangle per pixel, fitted inside `box`.
    ///
    /// `drawImage` would smooth a picture this small into mush when it's blown up
    /// this far; a rectangle per pixel keeps the edges hard, and it's what a
    /// vector export writes out too.
    private func drawPixels(_ image: Image, in box: Rectangle) {
        let cell = min(box.width / Double(image.width), box.height / Double(image.height))
        let originX = box.x + (box.width - cell * Double(image.width)) / 2
        let originY = box.y + (box.height - cell * Double(image.height)) / 2
        noStroke()
        for y in 0 ..< image.height {
            for x in 0 ..< image.width {
                fill(image[x, y])
                drawRect(corner: Vector2(originX + Double(x) * cell, originY + Double(y) * cell),
                         width: cell, height: cell)
            }
        }
    }

    // MARK: - The samples

    /// Three little pictures, authored here as character grids so the whole
    /// input is visible in the source. One color per character.
    private static func image(for motif: Motif) -> Image {
        switch motif {
        case .rooms: return build(rooms, inks: [".": 0x11151C, "#": 0x8FB8DE])
        case .weave: return build(weave, inks: ["." : 0x14100E, "o": 0xE4A03F, "+": 0x8C4A2F])
        case .flowers: return build(flowers, inks: [".": 0x121A26, "|": 0x4E9A57,
                                                    "o": 0xE4572E, "#": 0x6B4A2F])
        }
    }

    private static func build(_ rows: [String], inks: [Character: UInt32]) -> Image {
        let image = Image(width: rows[0].count, height: rows.count)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                image[x, y] = Color(hex: inks[ch] ?? 0xFF00FF)
            }
        }
        return image
    }

    /// Walls that recombine into floorplans the sample never drew.
    private static let rooms = [
        "................",
        "..######..####..",
        "..#....#..#..#..",
        "..#....####..#..",
        "..#..........#..",
        "..#..####....#..",
        "..####..#..###..",
        "........#..#....",
        "..#######..#....",
        "..#.....#..#....",
        "..#.....####....",
        "..#######.......",
        "................",
        "..####..######..",
        "..#..#..#....#..",
        "..#..####....#..",
    ]

    /// Bands crossing over and under, which constrains tightly enough that the
    /// solver has to keep the weave consistent everywhere.
    private static let weave = [
        "..oo....oo......",
        "..oo....oo......",
        "++++++++++++++++",
        "++++++++++++++++",
        "..oo....oo......",
        "..oo....oo......",
        "..oo....oo......",
        "..oo....oo......",
        "++++++++++++++++",
        "++++++++++++++++",
        "..oo....oo......",
        "..oo....oo......",
    ]

    /// Stems standing on ground under sky: a sample that knows which way is up,
    /// so it wants `symmetry: .none` to stay the right way round.
    private static let flowers = [
        "................",
        "................",
        ".....o..........",
        "..o..|.......o..",
        "..|..|.......|..",
        "..|..|..o....|..",
        "..|..|..|....|..",
        "..|..|..|..o.|..",
        "..|..|..|..|.|..",
        "################",
        "################",
    ]
}
