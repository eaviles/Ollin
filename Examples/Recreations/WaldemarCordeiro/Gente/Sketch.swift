//  Recreation after Waldemar Cordeiro - Gente (1972-1973), made with Raul
//  Fernando Dada and J. Soares Sobrinho at the computing center of the
//  Instituto de Artes of the Universidade Estadual de Campinas: a photograph
//  of a crowd in the Praça da Sé, São Paulo, printed on continuous-form
//  paper at several degrees of contrast (Gente Grau 1, 2, 4, and 6, computer
//  output, 63.5 x 30.5 cm). Read from the three sheets in the visgraf gallery
//  of the 1993 Arteônica exhibition, the Gente Grau 2 sheet Luciana Brito
//  Galeria showed in 2025, the exhibition catalog's list of the series, and
//  the account of it in Almerinda da Silva Lopes's 2008 paper for ANPAP. A
//  homage, not a reproduction, and not affiliated with or endorsed by the
//  artist's estate.
//  https://www.visgraf.impa.br/Gallery/waldemar/obras/gente.htm
//  https://www.visgraf.impa.br/Gallery/waldemar/catalogo/obras.htm
//  https://www.newcitybrazil.com/2025/11/28/waldemar-cordeiros-pioneering-computer-art-at-luciana-brito-galeria/
//  https://anpap.org.br/anais/2008/artigos/004.pdf
//
//  An original Ollin interpretation, written from the sheets. Nothing was
//  ported: the program is known here only through what the sheets show.

import Foundation
import Ollin
import OllinSamplePhotos

/// People (Waldemar Cordeiro, Campinas, 1972-1973). A photograph of a crowd
/// gathered in the Praça da Sé, read point by point into levels of dark and
/// printed by a line printer on continuous-form paper, sprocket holes down
/// both edges, the folds of the form across it, and a colophon typed under
/// the picture. The series prints the same crowd at several degrees, which
/// Cordeiro described as levels of contrast rendered in gradations of one
/// tone. At the first degree the crowd is all there, face by face; at the
/// sixth only the lightest points are left, white shapes on a field of
/// struck black. Up close the sheet is characters, a dash, an H, an H struck
/// over with an O; from across the room it is people.
///
/// This sketch hangs the four degrees side by side, on one of the bundled
/// photographs (`picture`), never the photograph of the Sé. A 1:2 box of the
/// picture is cut into 100 by 160 blocks on whole pixels, each block as much
/// taller than wide as the printer's cell (ten to the inch across, eight
/// down), so the picture prints undistorted; each block's mean in linear
/// light is read as luma, and the range between the lightest and darkest
/// block is cut into seven levels, 0 to 6. The degree is
/// read here as a multiplier: at degree `k` every level is multiplied by
/// `k` and held at 6, which keeps the lightest level white at every degree
/// and turns everything else dark as `k` rises. (The sixth-degree sheet in
/// the visgraf gallery keeps white close to the lightest tenth of the
/// first-degree sheet, which is what this reading predicts.) Each level is
/// struck as characters whose ink rises with the level, measured in this
/// face: a blank, a dash, an equals sign, an H, then an H struck over with
/// an O, with an O and an X, and with an O, an M, and a number sign.
///
/// The view does what the sheets ask of a visitor: it steps in toward one
/// place on one sheet until the characters read, holds, and steps back
/// until the picture reads, a sheet at a time, every `seconds`. `focusX`
/// and `focusY` pick the place, as fractions of the printed picture.
///
/// `--export-svg` at a frame where the view is out gives the four sheets
/// back as the glyphs the printer struck, one outline per strike.
@main
final class Gente: Sketch {
    enum Picture: String, CaseIterable, ParamOption { case wrestler, street, marigolds }

    @Param(icon: "photo") var picture = Picture.wrestler
    @Param(4 ... 60, icon: "clock") var seconds = 12.0
    @Param(1 ... 12, icon: "plus.magnifyingglass") var closest = 7.0
    @Param(0 ... 1, icon: "arrow.left.and.right") var focusX = 0.5
    @Param(0 ... 1, icon: "arrow.up.and.down") var focusY = 0.3

    override var canvasSize: CanvasSize { .fhd1080 }
    override var loopDuration: Double? { seconds * Double(Self.degrees.count) }

    /// The degrees of contrast, one sheet each.
    static let degrees = [1, 2, 4, 6]

    // A sheet of continuous form twelve inches across and 25 down, at 100
    // pixels to three inches; the picture is 100 columns across at ten to the
    // inch and 160 rows down at eight.
    static let inch = 100.0 / 3
    static let sheetWidth = 12 * inch
    static let sheetHeight = 25 * inch
    static let gap = 64.0
    static let sheetTop = (1080 - sheetHeight) / 2
    static let columns = 100
    static let rows = 160
    static let cellWidth = inch / 10
    static let cellHeight = inch / 8
    static let blockInset = inch
    static let blockTop = inch

    /// The characters struck on one place for each level, lightest first.
    static let strikes: [[Character]] = [
        [], ["-"], ["="], ["H"], ["H", "O"], ["H", "O", "X"], ["H", "O", "M", "#"],
    ]

    private let wall = Color(hex: 0xE4E3DF)
    private let paper = Color(hex: 0xF2ECDC)
    private let ink = Color(hex: 0x1F1D1B)

    private var sheets: [Batch] = []
    private var builtFor: Picture?
    private var face = OutlineFont.systemMono

    override func setup() {
        face = OutlineFont(name: "Menlo-Bold") ?? .systemMono
        build()
    }

    override func draw() {
        if builtFor != picture { build() }
        background(wall)

        // One approach per sheet: out, in toward the focus, hold, back out.
        let lap = seconds * Double(Self.degrees.count)
        let t = time.truncatingRemainder(dividingBy: lap)
        let sheet = min(Self.degrees.count - 1, Int(t / seconds))
        let u = t / seconds - Double(sheet)
        let near = smoothstep(0.12, 0.42, u) * (1 - smoothstep(0.62, 0.92, u))

        // Zoom evenly in scale, and slide the focus from where it sits on
        // the wall to the middle of the view as the view closes in.
        let zoom = exp(near * log(closest))
        let focus = Self.origin(of: sheet) + Vector2(
            Self.blockInset + focusX * Double(Self.columns) * Self.cellWidth,
            Self.blockTop + focusY * Double(Self.rows) * Self.cellHeight)
        let middle = Vector2(width / 2, height / 2)
        let onScreen = focus + (middle - focus) * near
        let center = focus - (onScreen - middle) / zoom

        withState {
            translate(middle)
            scale(zoom)
            translate(center * -1)
            for batch in sheets { drawBatch(batch) }
        }
    }

    /// The top left corner of sheet `k` on the wall.
    static func origin(of k: Int) -> Vector2 {
        let across = Double(degrees.count) * sheetWidth + Double(degrees.count - 1) * gap
        return Vector2((1920 - across) / 2 + Double(k) * (sheetWidth + gap), sheetTop)
    }

    /// The middle of cell (`r`, `c`) on sheet `k`.
    static func cell(_ k: Int, _ r: Int, _ c: Int) -> Vector2 {
        origin(of: k) + Vector2(blockInset + (Double(c) + 0.5) * cellWidth,
                                blockTop + (Double(r) + 0.5) * cellHeight)
    }

    // MARK: - Reading the picture

    private func build() {
        let levels = Self.levels(of: photo(picture).load())
        let credit = photo(picture).credit
        withState {
            textFont(face)
            textSize(100)
            // A character is set a little smaller than its cell, so the
            // struck marks stand apart the way the printer's did.
            textSize(0.78 * Self.cellWidth * 100 / textWidth("M"))
            textAlign(.center, .middle)
            textMode(.atlas)
            sheets = Self.degrees.enumerated().map { k, degree in
                makeBatch {
                    drawForm(k)
                    noStroke()
                    for pass in 0 ..< 4 {
                        fill(ink.withAlpha(0.8 + 0.12 * Self.unit(k * 16 + pass)))
                        for r in 0 ..< Self.rows {
                            for c in 0 ..< Self.columns {
                                let marks = Self.strikes[Self.contrast(levels[r][c], degree)]
                                guard pass < marks.count else { continue }
                                let p = Self.cell(k, r, c)
                                drawText(String(marks[pass]), p.x, p.y)
                            }
                        }
                    }
                    fill(ink.withAlpha(0.86))
                    let colophon = ["'GENTE' GRAU \(degree)   COMPUTER OUTPUT",
                                    "APOS WALDEMAR CORDEIRO, 1972-1973",
                                    "FOTOGRAFIA: \(credit.photographer), \(credit.place)"]
                    for (i, line) in colophon.enumerated() {
                        let typed = line.uppercased().folding(options: .diacriticInsensitive, locale: nil)
                        for (c, mark) in typed.enumerated() where mark != " " && c < Self.columns {
                            let p = Self.cell(k, Self.rows + 3 + i, c)
                            drawText(String(mark), p.x, p.y)
                        }
                    }
                }
            }
        }
        builtFor = picture
    }

    private func photo(_ picture: Picture) -> SamplePhoto {
        switch picture {
        case .wrestler: .wrestler
        case .street: .street
        case .marigolds: .marigolds
        }
    }

    /// The first degree: the largest 1:2 box of the picture, centered, cut into
    /// 100 by 160 blocks on whole pixels, each block's mean tone scaled
    /// between the lightest and darkest block and cut into seven equal levels.
    static func levels(of image: Image) -> [[Int]] {
        let w = Double(image.width), h = Double(image.height)
        var boxWidth = h / 2, boxHeight = h
        if boxWidth > w {
            boxWidth = w
            boxHeight = 2 * w
        }
        let x0 = (w - boxWidth) / 2, y0 = (h - boxHeight) / 2
        var dark: [[Double]] = []
        for r in 0 ..< rows {
            let ya = (y0 + Double(r) * boxHeight / Double(rows)).rounded(.down)
            let yb = (y0 + Double(r + 1) * boxHeight / Double(rows)).rounded(.down)
            var line: [Double] = []
            for c in 0 ..< columns {
                let xa = (x0 + Double(c) * boxWidth / Double(columns)).rounded(.down)
                let xb = (x0 + Double(c + 1) * boxWidth / Double(columns)).rounded(.down)
                let mean = image.averageColor(in: Rectangle(x: xa, y: ya, width: xb - xa, height: yb - ya))
                line.append(1 - (0.2126 * mean.red + 0.7152 * mean.green + 0.0722 * mean.blue))
            }
            dark.append(line)
        }
        let all = dark.flatMap { $0 }
        let lo = all.min() ?? 0, hi = all.max() ?? 1
        let span = max(hi - lo, 1e-9)
        return dark.map { line in
            line.map { min(6, Int(((($0 - lo) / span) * 7).rounded(.down))) }
        }
    }

    /// A level at degree `k` of contrast: multiplied by `k`, held at 6.
    static func contrast(_ level: Int, _ k: Int) -> Int { min(6, level * k) }

    // MARK: - The form

    /// The paper of sheet `k`: a faint shadow on the wall, the form, the
    /// sprocket holes down both edges every half inch, and the folds.
    private func drawForm(_ k: Int) {
        let o = Self.origin(of: k)
        noStroke()
        fill(Color(white: 0, alpha: 0.06))
        drawRect(o.x + 3, o.y + 4, Self.sheetWidth, Self.sheetHeight)
        fill(paper)
        drawRect(o.x, o.y, Self.sheetWidth, Self.sheetHeight)
        fill(wall)
        var y = Self.inch / 4
        while y < Self.sheetHeight {
            drawCircle(o.x + Self.inch / 4, o.y + y, Self.inch * 5 / 64)
            drawCircle(o.x + Self.sheetWidth - Self.inch / 4, o.y + y, Self.inch * 5 / 64)
            y += Self.inch / 2
        }
        // The pin-feed strips tear off along a line of cuts, and the pages
        // fold every eleven inches.
        stroke(ink.withAlpha(0.14))
        strokeWeight(0.5)
        for x in [Self.inch / 2, Self.sheetWidth - Self.inch / 2] {
            var y = 2.0
            while y < Self.sheetHeight {
                drawLine(o.x + x, o.y + y, o.x + x, o.y + y + 2)
                y += 4
            }
        }
        for fold in [7.0, 18.0] {
            stroke(ink.withAlpha(0.08))
            drawLine(o.x, o.y + fold * Self.inch, o.x + Self.sheetWidth, o.y + fold * Self.inch)
        }
    }

    /// A fixed number in 0 ..< 1 for an integer.
    static func unit(_ n: Int) -> Double {
        var z = UInt64(bitPattern: Int64(n)) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
