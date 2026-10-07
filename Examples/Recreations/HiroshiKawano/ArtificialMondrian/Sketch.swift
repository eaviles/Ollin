//  Recreation after Hiroshi Kawano - the "Artificial Mondrian" series (1969,
//  gouache on paper after designs computed on the HITAC 5020 in FORTRAN IV),
//  read from "KD 27", "KD 52" (71.4 x 50 cm) and "KD 55", ZKM | Center for
//  Art and Media Karlsruhe. A homage, not a reproduction, and not affiliated
//  with or endorsed by the artist or his estate.
//  https://zkm.de/en/artworks/kd-55
//  https://zkm.de/en/artworks/kd-28
//
//  An original Ollin interpretation, written from the paintings and from the
//  museum's account of the method. Nothing was ported: no program text was
//  read, and the transition tables below are this sketch's own, chosen so the
//  sheets read like the paintings.

import Ollin

/// Artificial Mondrian (Hiroshi Kawano, Tokyo, 1969). Five years after his
/// first designs, Kawano named a series for the painter he admired, while
/// claiming no close likeness to his work. On the university's HITAC 5020 a
/// transition probability matrix decided how long the horizontal and vertical
/// lines ran and whether they crossed, the lines closed into many-sided
/// forms, and the colors were dealt at random. He painted the results in
/// gouache: a few forms on a white ground, each held in a black band of one
/// width, divided by the same black into rectangles, steps and L-shapes of
/// flat color, with here and there a one-cell notch where a line stopped.
///
/// This sketch builds that on a raster of `units` cells, a band one cell
/// wide. The positions of the lines come from a chain over the gaps between
/// them, narrow, medium or wide, each kind deciding the next. A few forms
/// grow over the lattice the lines make, their outline always drawn. Inside a
/// form every line is walked from crossing to crossing by a second chain that
/// decides whether the next stretch is drawn or left open, so a line runs on
/// through some crossings and stops at others. A stretch that leads nowhere
/// is taken back, a line that stops at a crossing sometimes runs one cell
/// past it, the notch of the paintings, and every region the black closes
/// gets a color dealt from the look. `look` picks the
/// painting the colors and the number of forms are read from (`kd55`, three
/// forms in blues, greens, yellow, crimson and orange; `kd27`, one arch in
/// lemon, petrol, maroon, red, orange and violet with a white hole; `kd52`,
/// one form in teal, purple, olive, red and yellow); `share` is how much of
/// the lattice the forms take and `notches` how often a line that stops runs
/// one cell on. The seed deals the sheet, and a press deals the next one.
///
/// Over one cycle of `seconds` the black is laid line by line, the regions
/// are painted one after another, the sheet holds, and it fades back to
/// paper, which is also the export loop.
///
/// Every stretch of band exports as one rectangle, every notch as one cell
/// and every region as the rectangles that tile it, all on the raster, so
/// `--export-svg` with a frame in the hold gives the sheet back exactly.
@main
final class ArtificialMondrian: Sketch {
    enum Look: String, CaseIterable, ParamOption {
        case kd55, kd27, kd52

        /// The colors, measured off the painting.
        var palette: [Color] {
            switch self {
            case .kd55:
                [0x097BC9, 0x0092CB, 0xF8D301, 0xC52546, 0xA2C954, 0x0097A0, 0x874695, 0x01A178, 0xF57502]
                    .map { Color(hex: $0) }
            case .kd27:
                [0xE2CF50, 0x014873, 0x600404, 0xD01A14, 0xFD6303, 0x4C0B18, 0x044244, 0x342557]
                    .map { Color(hex: $0) }
            case .kd52:
                [0x008CA2, 0x7F248E, 0xC4130E, 0x959701, 0xE6C600, 0xFC8002, 0x036D5D, 0xC80740]
                    .map { Color(hex: $0) }
            }
        }

        /// How many forms the sheet starts from.
        var forms: Int { self == .kd55 ? 3 : 1 }

        /// The chance a region is left the white of the ground.
        var holes: Double { self == .kd27 ? 0.06 : 0 }
    }

    @Param(icon: "paintpalette") var look = Look.kd55
    @Param(24 ... 96, icon: "square.grid.3x3") var units = 44
    @Param(0.15 ... 0.8, icon: "square.on.square") var share = 0.5
    @Param(0 ... 1, icon: "line.diagonal") var notches = 0.35
    @Param(4 ... 60, icon: "clock") var seconds = 14.0

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { seconds }

    private let ground = Color(hex: 0xEEE5DD)
    private let black = Color(hex: 0x141313)

    /// The kinds of gap between one line and the next, in cells, the band
    /// included.
    private enum Gap: Int, CaseIterable {
        case narrow, medium, wide

        var cells: ClosedRange<Int> { [3 ... 4, 5 ... 6, 7 ... 9][rawValue] }
    }

    /// Whether the next stretch of a line, crossing to crossing, is drawn.
    private enum Stretch: Int, CaseIterable { case open, drawn }

    /// The gap chain: after a gap of each kind, out of twenty, how often the
    /// next gap is narrow, medium or wide.
    private static let gapCounts: [(Gap, [Int])] = [
        (.narrow, [7, 9, 4]), (.medium, [8, 7, 5]), (.wide, [11, 7, 2]),
    ]

    /// The line chain: after an open stretch and after a drawn one, out of
    /// twenty, how often the next is open or drawn. A drawn line mostly runs
    /// on through its crossing; an open one mostly picks up again.
    private static let stretchCounts: [(Stretch, [Int])] = [
        (.open, [8, 12]), (.drawn, [3, 17]),
    ]

    /// A rectangle of cells, `x0 ... x1` by `y0 ... y1`, inclusive.
    private struct Cells: Equatable {
        var x0, y0, x1, y1: Int
    }

    private struct Region {
        var color: Color
        var tiles: [Cells]
    }

    private struct Plan {
        /// The band, in the order it is laid: the horizontal lines from the
        /// top, then the vertical ones from the left.
        var stretches: [Cells]
        var notches: [Cells]
        /// In reading order of their first cell.
        var regions: [Region]
    }

    private var plan: Plan?
    private var plannedFor: (look: Look, seed: Int, units: Int, share: Double, notches: Double)?
    private var pressed = false

    override func mousePressed() {
        pressed = true
    }

    override func draw() {
        if pressed {
            pressed = false
            seed(variation + 1)
        }
        let wanted = (look: look, seed: variation, units: units, share: share, notches: notches)
        if plannedFor.map({ $0 != wanted }) ?? true {
            plannedFor = wanted
            plan = deal()
        }
        guard let plan else { return }

        background(ground)
        noStroke()
        let u = width / Double(units)
        let phase = loopProgress(over: seconds)

        // The regions, painted one after another once the black is down.
        let painting = phase < 0.35 ? 0 : min(1, (phase - 0.35) / 0.3)
        let reached = painting * Double(plan.regions.count)
        for (k, region) in plan.regions.enumerated() where Double(k) < reached {
            fill(region.color.withAlpha(min(1, (reached - Double(k)) * 2)))
            for t in region.tiles { draw(t, u) }
        }

        // The black, laid stretch by stretch, each growing along its line.
        fill(black)
        let laying = min(1, phase / 0.35) * Double(plan.stretches.count)
        for (k, s) in plan.stretches.enumerated() where Double(k) < laying {
            let grown = min(1, laying - Double(k))
            if grown >= 1 {
                draw(s, u)
            } else if s.y0 == s.y1 {
                drawRect(Double(s.x0) * u, Double(s.y0) * u, Double(s.x1 - s.x0 + 1) * u * grown, u)
            } else {
                drawRect(Double(s.x0) * u, Double(s.y0) * u, u, Double(s.y1 - s.y0 + 1) * u * grown)
            }
        }
        if laying >= Double(plan.stretches.count) {
            for n in plan.notches { draw(n, u) }
        }

        if phase > 0.9 {
            fill(ground.withAlpha(smoothstep(0.9, 1, phase)))
            drawRect(0, 0, width, height)
        }
    }

    private func draw(_ c: Cells, _ u: Double) {
        drawRect(Double(c.x0) * u, Double(c.y0) * u, Double(c.x1 - c.x0 + 1) * u, Double(c.y1 - c.y0 + 1) * u)
    }

    // MARK: - Dealing a sheet

    private func deal() -> Plan {
        randomSeed(variation)
        var gaps = MarkovChain<Gap>(seed: variation &* 7919 &+ 1)
        for (before, counts) in Self.gapCounts {
            for (k, times) in counts.enumerated() { gaps.learn(Gap(rawValue: k)!, after: [before], times: times) }
        }
        var lines = MarkovChain<Stretch>(seed: variation &* 7919 &+ 2)
        for (before, counts) in Self.stretchCounts {
            for (k, times) in counts.enumerated() { lines.learn(Stretch(rawValue: k)!, after: [before], times: times) }
        }

        // 1. Where the lines can be: a chain over the gaps, inside a margin.
        let margin = 3
        func positions() -> [Int] {
            var at = [margin]
            gaps.start(at: .medium)
            while true {
                let range = gaps.next()!.cells
                let gap = range.lowerBound + Int(random(Double(range.count)))
                guard at[at.count - 1] + gap <= units - 1 - margin else { break }
                at.append(at[at.count - 1] + gap)
            }
            return at
        }
        let xs = positions(), ys = positions()
        let columns = xs.count - 1, rows = ys.count - 1

        // 2. The forms: a few cells of the lattice, grown a neighbor at a
        // time, a cell with more of the form around it likelier to join, so
        // the forms come out compact.
        var form = [[Bool]](repeating: [Bool](repeating: false, count: columns), count: rows)
        func inForm(_ j: Int, _ i: Int) -> Bool { j >= 0 && j < rows && i >= 0 && i < columns && form[j][i] }
        if look.forms == 1 {
            // One form, as on KD 27 and KD 52, grows from near the middle.
            form[rows / 2 + Int(random(-1, 1.99))][columns / 2 + Int(random(-1, 1.99))] = true
        } else {
            // Several, as on KD 55, each starting in its own band of columns
            // so they spread over the sheet before they meet.
            for k in 0 ..< look.forms {
                let left = k * columns / look.forms, right = (k + 1) * columns / look.forms
                form[Int(random(Double(rows)))][left + Int(random(Double(max(1, right - left))))] = true
            }
        }
        let target = max(look.forms, Int(share * Double(rows * columns)))
        var size = form.joined().filter { $0 }.count
        while size < target {
            var frontier: [(Int, Int)] = []
            var weights: [Double] = []
            for j in 0 ..< rows {
                for i in 0 ..< columns where !form[j][i] {
                    let touching = [(1, 0), (-1, 0), (0, 1), (0, -1)].filter { inForm(j + $0.0, i + $0.1) }.count
                    if touching > 0 {
                        frontier.append((j, i))
                        weights.append(Double(1 + 3 * (touching - 1)))
                    }
                }
            }
            guard !frontier.isEmpty else { break }
            var roll = random(weights.reduce(0, +))
            var pick = frontier.count - 1
            for (k, w) in weights.enumerated() {
                roll -= w
                if roll < 0 { pick = k; break }
            }
            form[frontier[pick].0][frontier[pick].1] = true
            size += 1
        }

        // 3. The stretches of every line: on a form's edge always drawn,
        // inside a form drawn or left open by the line chain, walked along
        // each line from crossing to crossing.
        enum Kind { case edge, inside }
        var horizontal: [Int: Kind] = [:]   // key j * 1000 + i: line y j, from column i to i + 1
        var vertical: [Int: Kind] = [:]     // key j * 1000 + i: line x i, from row j to j + 1
        for j in 0 ... rows {
            lines.start(at: .drawn)
            for i in 0 ..< columns {
                let above = inForm(j - 1, i), below = inForm(j, i)
                if above != below {
                    horizontal[j * 1000 + i] = .edge
                } else if above, lines.next() == .drawn {
                    horizontal[j * 1000 + i] = .inside
                }
            }
        }
        for i in 0 ... columns {
            lines.start(at: .drawn)
            for j in 0 ..< rows {
                let left = inForm(j, i - 1), right = inForm(j, i)
                if left != right {
                    vertical[j * 1000 + i] = .edge
                } else if left, lines.next() == .drawn {
                    vertical[j * 1000 + i] = .inside
                }
            }
        }

        // 4. A stretch inside a form that leads nowhere, one end touching no
        // other stretch, is taken back, over and over until none is left.
        // Crossings are keyed j * 1000 + i at (xs[i], ys[j]).
        func degrees() -> [Int: Int] {
            var degree: [Int: Int] = [:]
            for key in horizontal.keys {
                degree[key, default: 0] += 1
                degree[key + 1, default: 0] += 1
            }
            for key in vertical.keys {
                degree[key, default: 0] += 1
                degree[key + 1000, default: 0] += 1
            }
            return degree
        }
        var pruning = true
        while pruning {
            pruning = false
            let degree = degrees()
            for key in horizontal.keys.sorted() where horizontal[key] == .inside {
                if degree[key] == 1 || degree[key + 1] == 1 {
                    horizontal[key] = nil
                    pruning = true
                    break
                }
            }
            if pruning { continue }
            for key in vertical.keys.sorted() where vertical[key] == .inside {
                if degree[key] == 1 || degree[key + 1000] == 1 {
                    vertical[key] = nil
                    pruning = true
                    break
                }
            }
        }

        // 5. Where a drawn line stops at a crossing and the stretch beyond is
        // open inside the form, the line sometimes runs one cell past the
        // crossing: a notch. At most one per open stretch, so a short one is
        // never closed by two.
        var notchCells: [Cells] = []
        func notch(_ x: Int, _ y: Int) { notchCells.append(Cells(x0: x, y0: y, x1: x, y1: y)) }
        for j in 0 ... rows {
            for i in 0 ..< columns where horizontal[j * 1000 + i] == nil && inForm(j - 1, i) && inForm(j, i) {
                let fromLeft = i > 0 && horizontal[j * 1000 + i - 1] != nil
                let fromRight = i + 1 < columns && horizontal[j * 1000 + i + 1] != nil
                if fromLeft, random() < notches {
                    notch(xs[i] + 1, ys[j])
                } else if fromRight, random() < notches {
                    notch(xs[i + 1] - 1, ys[j])
                }
            }
        }
        for i in 0 ... columns {
            for j in 0 ..< rows where vertical[j * 1000 + i] == nil && inForm(j, i - 1) && inForm(j, i) {
                let fromAbove = j > 0 && vertical[(j - 1) * 1000 + i] != nil
                let fromBelow = j + 1 < rows && vertical[(j + 1) * 1000 + i] != nil
                if fromAbove, random() < notches {
                    notch(xs[i], ys[j] + 1)
                } else if fromBelow, random() < notches {
                    notch(xs[i], ys[j + 1] - 1)
                }
            }
        }

        // 6. The raster: the black, then the regions it closes inside the
        // forms, found by flood fill, each dealt a color.
        let n = units
        var band = [Bool](repeating: false, count: n * n)
        var stretchCells: [Cells] = []
        for key in horizontal.keys.sorted() {
            let j = key / 1000, i = key % 1000
            stretchCells.append(Cells(x0: xs[i], y0: ys[j], x1: xs[i + 1], y1: ys[j]))
        }
        for key in vertical.keys.sorted(by: { ($0 % 1000, $0 / 1000) < ($1 % 1000, $1 / 1000) }) {
            let j = key / 1000, i = key % 1000
            stretchCells.append(Cells(x0: xs[i], y0: ys[j], x1: xs[i], y1: ys[j + 1]))
        }
        for c in stretchCells + notchCells {
            for y in c.y0 ... c.y1 { for x in c.x0 ... c.x1 { band[y * n + x] = true } }
        }
        var inside = [Bool](repeating: false, count: n * n)
        for j in 0 ..< rows {
            for i in 0 ..< columns where form[j][i] {
                for y in ys[j] ... ys[j + 1] { for x in xs[i] ... xs[i + 1] where !band[y * n + x] { inside[y * n + x] = true } }
            }
        }
        var region = [Int](repeating: -1, count: n * n)
        var count = 0
        for start in 0 ..< n * n where inside[start] && region[start] < 0 {
            var stack = [start]
            region[start] = count
            while let at = stack.popLast() {
                let x = at % n, y = at / n
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < n, ny >= 0, ny < n else { continue }
                    let next = ny * n + nx
                    if inside[next], region[next] < 0 {
                        region[next] = count
                        stack.append(next)
                    }
                }
            }
            count += 1
        }
        let palette = look.palette
        let colors = (0 ..< count).map { _ in
            random() < look.holes ? ground : palette[Int(random(Double(palette.count)))]
        }

        // Each region as rectangles: runs along a row, merged down while the
        // run below matches it exactly.
        var tiles = [[Cells]](repeating: [], count: count)
        var open: [Int: Cells] = [:]   // keyed by x0 * 1000 + x1, the run growing down
        for y in 0 ..< n {
            var runs: [Int: (Int, Cells)] = [:]
            var x = 0
            while x < n {
                let id = region[y * n + x]
                guard id >= 0 else { x += 1; continue }
                var end = x
                while end + 1 < n, region[y * n + end + 1] == id { end += 1 }
                runs[x * 1000 + end] = (id, Cells(x0: x, y0: y, x1: end, y1: y))
                x = end + 1
            }
            for (key, run) in open.sorted(by: { $0.key < $1.key }) {
                if let below = runs[key], region[below.1.y0 * n + below.1.x0] == region[run.y0 * n + run.x0] {
                    open[key]!.y1 = y
                    runs[key] = nil
                } else {
                    tiles[region[run.y0 * n + run.x0]].append(run)
                    open[key] = nil
                }
            }
            for (key, run) in runs { open[key] = run.1 }
        }
        for (_, run) in open.sorted(by: { $0.key < $1.key }) { tiles[region[run.y0 * n + run.x0]].append(run) }

        let regions = (0 ..< count).map { Region(color: colors[$0], tiles: tiles[$0]) }
        return Plan(stretches: stretchCells, notches: notchCells, regions: regions)
    }
}
