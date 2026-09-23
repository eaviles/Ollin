//  Recreation after Gego (Gertrud Goldschmidt) - the Tejeduras, 1988 to 1991:
//  small works woven out of strips of paper, cut from her own prints, from
//  magazines and leaflets, and from the foil of cigarette packets, weft over
//  warp the way cloth is made.
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or her estate.
//  https://www.macba.cat/en/art-artists/artists/gego/tejedura-888
//
//  An original Ollin interpretation, written from the works and from the
//  accounts of how they were made. Nothing was ported: the strips were cut
//  with a blade and woven by hand at her table in Caracas.

import Ollin

/// A Tejedura (Gego, 1988 to 1991). A print she pulled herself, cut into
/// strips and woven with strips of foil, weft over warp. The impression she
/// kept lies on the left; the one she cut is on the right, being woven.
///
/// In her last years Gego could no longer bend and tie wire, and she went
/// back to paper, but not as a thing to draw on: as a thing to cut up and
/// weave. The strips came from whatever was on the table, her own prints
/// among them, and the weaving was the plain kind, one strip over and under
/// the next, except that she broke the rhythm wherever she felt like it and
/// let a strip run over two or three crossings before it dived. A print cut
/// into strips and woven this way is still the print: every piece of every
/// line is where it was, only some of them are under the foil now.
///
/// So the sketch pulls a print first, a net of lines on nodes, drawn the way
/// her nets are drawn. It cuts that print into warp strips of uneven width,
/// cuts a weft of foil to the same measure, and decides the weave one row at a
/// time: over, under, over, under, with a break at the rate `breaks` where the
/// strip floats. Then it weaves, at `pace` strips a second, and every cell of
/// the weave shows whichever strip is on top there: the foil, or the print's
/// own pieces cut exactly to that cell. When the sheet is done it rests, and
/// then another print is pulled and cut. `strips` is how fine the cut is,
/// `foil` which packet the weft came from, and `nodes` how fine the print is.
@main
final class Tejedura: Sketch {
    /// How many strips the print is cut into across its width. They are not
    /// all the same: each is somewhere between two thirds and four thirds of
    /// the even cut, which is what a blade and a ruler do by hand, and the
    /// weft is cut to the same measure.
    @Param(24 ... 56, step: 2, icon: "scissors") var strips = 40
    /// How often the over-and-under rhythm is broken: a strip that runs over
    /// two or three crossings before it dives, where a loom would never let it.
    @Param(0 ... 0.3, icon: "line.diagonal") var breaks = 0.08
    /// How many weft strips go in a second.
    @Param(0.5 ... 8, icon: "timer") var pace = 4.0
    /// Which packet the weft strips were cut from.
    @Param(icon: "rectangle.stack") var foil = Foil.magenta
    /// How fine the print is: how many nodes its net is drawn on.
    @Param(60 ... 220, step: 10, icon: "point.3.connected.trianglepath.dotted")
    var nodes = 130

    enum Foil: String, CaseIterable, ParamOption { case magenta, gold, black }

    let mat = Color(hex: 0xE7E2D8)
    let paper = Color(hex: 0xF6F2EA)
    let ink = Color(hex: 0x1F1D1B)
    let pencil = Color(hex: 0x6F6A63)
    let shade = Color(hex: 0x6B655C)
    let shadow = Color(hex: 0x9A948A)

    /// The two impressions, the same size, side by side on the mat.
    let sheetWidth = 440.0
    let sheetHeight = 546.0
    let printOrigin = Vector2(90, 232)
    let weaveOrigin = Vector2(550, 232)
    /// How long a finished sheet rests before the next print is pulled.
    let hold = 5.0
    /// The radius of a node on the print.
    let dotRadius = 1.7

    /// One print and the weave cut from it, all in the sheet's own
    /// coordinates, the top left corner of the paper at zero.
    struct Sheet {
        var lines: [(Vector2, Vector2)] = []
        var dots: [Vector2] = []
        /// The cut edges: `columns[i] ... columns[i + 1]` is warp strip `i`,
        /// `rows[j] ... rows[j + 1]` is weft strip `j`.
        var columns: [Double] = []
        var rows: [Double] = []
        /// Which strip is on top at each crossing, `[row][column]`.
        var weftOver: [[Bool]] = []
        var rowColor: [Color] = []
        /// The print's pieces, cut to each cell: the line pieces and the dot
        /// pieces, indexed `row * columnCount + column`.
        var cellLines: [[(Vector2, Vector2)]] = []
        var cellDots: [[[Vector2]]] = []
        /// The same pieces cut to each warp strip alone, which is all a strip
        /// is until the weft has crossed it.
        var columnLines: [[(Vector2, Vector2)]] = []
        var columnDots: [[[Vector2]]] = []
        var startTime = 0.0
        var number = 1

        var columnCount: Int { columns.count - 1 }
        var rowCount: Int { rows.count - 1 }
    }

    var sheet = Sheet()

    override var canvasSize: CanvasSize { .square(1080) }

    override func setup() {
        pullAndCut(number: 1, at: 0)
    }

    // MARK: - The print

    /// Pulls a print, cuts both impressions' worth of strips out of one of
    /// them, and decides the weave.
    func pullAndCut(number: Int, at start: Double) {
        var next = Sheet()
        next.number = number
        next.startTime = start
        (next.lines, next.dots) = pullThePrint(number: number)
        let mean = sheetWidth / Double(strips)
        next.columns = cut(sheetWidth, mean: mean)
        next.rows = cut(sheetHeight, mean: mean)
        next.weftOver = weave(rows: next.rowCount, columns: next.columnCount)
        let inks = foil.inks
        next.rowColor = (0 ..< next.rowCount).map { _ in
            random() < 0.15 ? inks.1 : inks.0
        }
        (next.cellLines, next.cellDots) = cutToCells(next)
        (next.columnLines, next.columnDots) = cutToStrips(next)
        sheet = next
    }

    /// A net of lines on nodes, the drawing she made over and over: points
    /// scattered with a density that knots up and opens out, each joined to
    /// its neighbors, the triangles too big for a hand dropped so the edge
    /// frays, and a few regions left open.
    func pullThePrint(number: Int) -> ([(Vector2, Vector2)], [Vector2]) {
        let bounds = Rectangle(corner: .zero, width: sheetWidth, height: sheetHeight)
        let shift = Double(number) * 137.0
        let sites = stipple(count: nodes, in: bounds, iterations: 8) { p in
            0.35 + 0.65 * pow(noise(p.x * 0.009 + shift, p.y * 0.009 - shift), 1.6)
        }
        let joined = delaunay(sites)
        let reach = (sheetWidth * sheetHeight / Double(nodes)).squareRoot() * 1.55

        var seen = Set<Int64>()
        var lines: [(Vector2, Vector2)] = []
        var used = Set<Int>()
        var i = 0
        while i + 2 < joined.indices.count {
            let a = joined.indices[i], b = joined.indices[i + 1], c = joined.indices[i + 2]
            i += 3
            let pa = sites[a], pb = sites[b], pc = sites[c]
            let longest = max((pb - pa).length, max((pc - pb).length, (pa - pc).length))
            if longest > reach { continue }
            let mid = (pa + pb + pc) / 3
            if noise(mid.x * 0.016 + shift + 50, mid.y * 0.016 - shift) < 0.14 { continue }
            for (u, v) in [(a, b), (b, c), (c, a)] {
                let low = min(u, v), high = max(u, v)
                let key = Int64(low) << 32 | Int64(high)
                if seen.insert(key).inserted { lines.append((sites[low], sites[high])) }
                used.insert(u); used.insert(v)
            }
        }
        let dots = used.sorted().map { sites[$0] }
        return (lines, dots)
    }

    // MARK: - The cut and the weave

    /// The edges of strips cut across `total` by hand: each somewhere between
    /// 0.72 and 1.28 of the even cut, and the last of the overshoot shared
    /// out over all of them so the strips fill the sheet exactly.
    func cut(_ total: Double, mean: Double) -> [Double] {
        var widths: [Double] = []
        var sum = 0.0
        while sum < total {
            let w = random(mean * 0.72, mean * 1.28)
            widths.append(w)
            sum += w
        }
        let excess = (sum - total) / Double(widths.count)
        var edges = [0.0]
        for w in widths { edges.append(edges.last! + w - excess) }
        edges[edges.count - 1] = total
        return edges
    }

    /// Which strip is on top at every crossing. A row starts on the plain
    /// rhythm, over on the even rows and under on the odd ones, and goes
    /// over, under, over, under across, except that at the rate `breaks` a
    /// strip runs over two or three crossings before the rhythm resumes.
    func weave(rows: Int, columns: Int) -> [[Bool]] {
        var over: [[Bool]] = []
        for j in 0 ..< rows {
            var row = [Bool](repeating: false, count: columns)
            var state = j % 2 == 0
            var i = 0
            while i < columns {
                let run = random() < breaks ? (random() < 0.5 ? 2 : 3) : 1
                for k in 0 ..< run where i + k < columns { row[i + k] = state }
                i += run
                state.toggle()
            }
            over.append(row)
        }
        return over
    }

    /// The print's lines and dots, cut to every cell they cross: the pieces a
    /// blade leaves when it cuts the strips, and then cuts them again where
    /// the weft crosses.
    func cutToCells(_ s: Sheet) -> ([[(Vector2, Vector2)]], [[[Vector2]]]) {
        let cols = s.columnCount, rows = s.rowCount
        var cellLines = [[(Vector2, Vector2)]](repeating: [], count: cols * rows)
        var cellDots = [[[Vector2]]](repeating: [], count: cols * rows)

        func span(_ edges: [Double], _ low: Double, _ high: Double) -> ClosedRange<Int> {
            var first = 0, last = edges.count - 2
            while first < edges.count - 2 && edges[first + 1] <= low { first += 1 }
            while last > 0 && edges[last] >= high { last -= 1 }
            return first ... max(first, last)
        }

        for (a, b) in s.lines {
            let cs = span(s.columns, min(a.x, b.x), max(a.x, b.x))
            let rs = span(s.rows, min(a.y, b.y), max(a.y, b.y))
            for j in rs {
                for i in cs {
                    let cell = Rectangle(x: s.columns[i], y: s.rows[j],
                                         width: s.columns[i + 1] - s.columns[i],
                                         height: s.rows[j + 1] - s.rows[j])
                    if let piece = clip(a, b, to: cell), (piece.1 - piece.0).length > 0.3 {
                        cellLines[j * cols + i].append(piece)
                    }
                }
            }
        }

        let round = (0 ..< 24).map { k -> Vector2 in
            let angle = Double(k) / 24 * .tau
            return Vector2(cos(angle), sin(angle)) * dotRadius
        }
        for dot in s.dots {
            let ring = round.map { $0 + dot }
            let cs = span(s.columns, dot.x - dotRadius, dot.x + dotRadius)
            let rs = span(s.rows, dot.y - dotRadius, dot.y + dotRadius)
            for j in rs {
                for i in cs {
                    let cell = Rectangle(x: s.columns[i], y: s.rows[j],
                                         width: s.columns[i + 1] - s.columns[i],
                                         height: s.rows[j + 1] - s.rows[j])
                    let piece = clip(ring, to: cell)
                    if piece.count >= 3, area(piece) > 0.05 {
                        cellDots[j * cols + i].append(piece)
                    }
                }
            }
        }
        return (cellLines, cellDots)
    }

    /// The print's lines and dots cut into the warp strips, before any weft.
    func cutToStrips(_ s: Sheet) -> ([[(Vector2, Vector2)]], [[[Vector2]]]) {
        var lines = [[(Vector2, Vector2)]](repeating: [], count: s.columnCount)
        var dots = [[[Vector2]]](repeating: [], count: s.columnCount)
        let round = (0 ..< 24).map { k -> Vector2 in
            let angle = Double(k) / 24 * .tau
            return Vector2(cos(angle), sin(angle)) * dotRadius
        }
        for i in 0 ..< s.columnCount {
            let strip = Rectangle(x: s.columns[i], y: 0,
                                  width: s.columns[i + 1] - s.columns[i], height: sheetHeight)
            for (a, b) in s.lines {
                if let piece = clip(a, b, to: strip), (piece.1 - piece.0).length > 0.3 {
                    lines[i].append(piece)
                }
            }
            for dot in s.dots {
                let piece = clip(round.map { $0 + dot }, to: strip)
                if piece.count >= 3, area(piece) > 0.05 { dots[i].append(piece) }
            }
        }
        return (lines, dots)
    }

    /// The part of a segment inside a rectangle, or nothing.
    func clip(_ a: Vector2, _ b: Vector2, to r: Rectangle) -> (Vector2, Vector2)? {
        let d = b - a
        var t0 = 0.0, t1 = 1.0
        let bounds = [(-d.x, a.x - r.x), (d.x, r.x + r.width - a.x),
                      (-d.y, a.y - r.y), (d.y, r.y + r.height - a.y)]
        for (p, q) in bounds {
            if p == 0 {
                if q < 0 { return nil }
            } else {
                let t = q / p
                if p < 0 { t0 = max(t0, t) } else { t1 = min(t1, t) }
                if t0 > t1 { return nil }
            }
        }
        return (a + d * t0, a + d * t1)
    }

    /// The part of a convex polygon inside a rectangle.
    func clip(_ polygon: [Vector2], to r: Rectangle) -> [Vector2] {
        var out = polygon
        let edges: [(Vector2) -> Double] = [
            { $0.x - r.x }, { r.x + r.width - $0.x },
            { $0.y - r.y }, { r.y + r.height - $0.y },
        ]
        for inside in edges {
            let input = out
            out = []
            guard !input.isEmpty else { break }
            var previous = input[input.count - 1]
            for current in input {
                let dc = inside(current), dp = inside(previous)
                if dc >= 0 {
                    if dp < 0 { out.append(previous.lerp(to: current, dp / (dp - dc))) }
                    out.append(current)
                } else if dp >= 0 {
                    out.append(previous.lerp(to: current, dp / (dp - dc)))
                }
                previous = current
            }
        }
        return out
    }

    func area(_ polygon: [Vector2]) -> Double {
        var twice = 0.0
        for k in polygon.indices {
            let a = polygon[k], b = polygon[(k + 1) % polygon.count]
            twice += a.x * b.y - b.x * a.y
        }
        return abs(twice) / 2
    }

    // MARK: - Drawing

    override func draw() {
        background(mat)
        let elapsed = time - sheet.startTime
        let done = Double(sheet.rowCount) / pace
        if elapsed >= done + hold {
            pullAndCut(number: sheet.number + 1, at: time)
        }
        let progress = min((time - sheet.startTime) * pace, Double(sheet.rowCount))

        drawImpression()
        drawWeave(progress: progress)

        drawText("the print, one impression", printOrigin.x, printOrigin.y + sheetHeight + 18,
                 size: 13, color: pencil, align: .left, .top)
        drawText("the other, cut into strips and woven", weaveOrigin.x,
                 weaveOrigin.y + sheetHeight + 18, size: 13, color: pencil, align: .left, .top)
        drawText("tejedura \(sheet.number)", weaveOrigin.x + sheetWidth,
                 weaveOrigin.y + sheetHeight + 18, size: 13, color: pencil, align: .right, .top)
    }

    /// The impression she kept, whole.
    func drawImpression() {
        noStroke()
        fill(shadow.withAlpha(0.35))
        drawRect(corner: printOrigin + Vector2(3, 4), width: sheetWidth, height: sheetHeight)
        fill(paper)
        drawRect(corner: printOrigin, width: sheetWidth, height: sheetHeight)

        withState {
            translate(printOrigin)
            noFill()
            stroke(ink)
            strokeWeight(1)
            strokeCap(.butt)
            for (a, b) in sheet.lines { drawLine(a, b) }
            noStroke()
            fill(ink)
            for dot in sheet.dots { drawCircle(center: dot, radius: dotRadius) }
        }
    }

    /// The other impression, cut and woven as far as `progress` rows. Every
    /// cell shows the strip on top there; where the weft has not arrived yet
    /// the warp strips hang alone and show the whole print.
    func drawWeave(progress: Double) {
        noStroke()
        fill(shadow.withAlpha(0.35))
        drawRect(corner: weaveOrigin + Vector2(3, 4), width: sheetWidth, height: sheetHeight)

        let s = sheet
        let cols = s.columnCount
        let wovenRows = Int(progress)
        // How far the weft has got across the row it is in. A strip has
        // arrived at a crossing once it shows there, so the row counts as
        // woven up to the last crossing the weft is on top of.
        var wovenColumns = 0
        if wovenRows < s.rowCount {
            let reached = Int((progress - Double(wovenRows)) * Double(cols) + 0.5)
            wovenColumns = (0 ..< reached).last { s.weftOver[wovenRows][$0] }.map { $0 + 1 } ?? 0
        }

        /// Whether a cell has been woven: the weft has crossed it.
        func isWoven(_ i: Int, _ j: Int) -> Bool {
            j < wovenRows || (j == wovenRows && i < wovenColumns)
        }
        /// Whether a cell shows the warp: the weft is under it there, or has
        /// not arrived yet.
        func showsWarp(_ i: Int, _ j: Int) -> Bool {
            !(isWoven(i, j) && s.weftOver[j][i])
        }
        /// The row from which a strip is still bare, with no weft across it.
        func bareFrom(_ i: Int) -> Int {
            wovenRows + (i < wovenColumns ? 1 : 0)
        }

        withState {
            translate(weaveOrigin)
            // The paper, the foil where the weft is on top, and the print's
            // pieces where the warp is; then every cut edge over them, so an
            // edge is never covered by the neighbor it was cut against.
            noStroke()
            fill(paper)
            drawRect(0, 0, sheetWidth, sheetHeight)
            for j in 0 ..< s.rowCount {
                for i in 0 ..< cols where !showsWarp(i, j) {
                    fill(s.rowColor[j])
                    drawRect(s.columns[i], s.rows[j], s.columns[i + 1] - s.columns[i],
                             s.rows[j + 1] - s.rows[j])
                }
            }
            // The print's pieces: cut to the cell where the weft has crossed
            // and the warp is on top, and cut only to the strip below that,
            // where the warp still hangs bare.
            noFill()
            stroke(ink)
            strokeWeight(1)
            strokeCap(.butt)
            for j in 0 ..< s.rowCount {
                for i in 0 ..< cols where isWoven(i, j) && showsWarp(i, j) {
                    for (a, b) in s.cellLines[j * cols + i] { drawLine(a, b) }
                }
            }
            for i in 0 ..< cols where bareFrom(i) < s.rowCount {
                let bare = Rectangle(x: s.columns[i], y: s.rows[bareFrom(i)],
                                     width: s.columns[i + 1] - s.columns[i],
                                     height: sheetHeight - s.rows[bareFrom(i)])
                for (a, b) in s.columnLines[i] {
                    if let piece = clip(a, b, to: bare), (piece.1 - piece.0).length > 0.3 {
                        drawLine(piece.0, piece.1)
                    }
                }
            }
            noStroke()
            fill(ink)
            for j in 0 ..< s.rowCount {
                for i in 0 ..< cols where isWoven(i, j) && showsWarp(i, j) {
                    for piece in s.cellDots[j * cols + i] { drawPolygon(piece) }
                }
            }
            for i in 0 ..< cols where bareFrom(i) < s.rowCount {
                let bare = Rectangle(x: s.columns[i], y: s.rows[bareFrom(i)],
                                     width: s.columns[i + 1] - s.columns[i],
                                     height: sheetHeight - s.rows[bareFrom(i)])
                for ring in s.columnDots[i] {
                    let piece = clip(ring, to: bare)
                    if piece.count >= 3, area(piece) > 0.05 { drawPolygon(piece) }
                }
            }

            // The cut edges. A boundary between two cells carries an edge
            // unless one strip runs straight across it on top: two foil cells
            // side by side are one weft strip floating, two warp cells one
            // above the other are one warp strip, and neither shows a cut.
            // The sheet's own edge is always a cut. Each run of boundaries
            // that carries an edge is drawn as one line.
            noFill()
            stroke(shade.withAlpha(0.28))
            strokeWeight(1)
            strokeCap(.butt)
            for i in 0 ... cols {
                let x = s.columns[i]
                var start: Int? = nil
                for j in 0 ... s.rowCount {
                    let cut = j < s.rowCount && (i == 0 || i == cols
                        || showsWarp(i - 1, j) || showsWarp(i, j))
                    if cut, start == nil { start = j }
                    if !cut, let from = start {
                        drawLine(Vector2(x, s.rows[from]), Vector2(x, s.rows[j]))
                        start = nil
                    }
                }
            }
            for j in 0 ... s.rowCount {
                let y = s.rows[j]
                var start: Int? = nil
                for i in 0 ... cols {
                    let cut = i < cols && (j == 0 || j == s.rowCount
                        || !showsWarp(i, j - 1) || !showsWarp(i, j))
                    if cut, start == nil { start = i }
                    if !cut, let from = start {
                        drawLine(Vector2(s.columns[from], y), Vector2(s.columns[i], y))
                        start = nil
                    }
                }
            }
        }
    }
}

extension Tejedura.Foil {
    /// The two colors a packet's foil comes in: most rows the first, a few
    /// the second.
    var inks: (Color, Color) {
        switch self {
        case .magenta: return (Color(hex: 0xD81E8C), Color(hex: 0xC7232E))
        case .gold: return (Color(hex: 0xC9A23A), Color(hex: 0x9E7B22))
        case .black: return (Color(hex: 0x1C1A18), Color(hex: 0x3A3633))
        }
    }
}
