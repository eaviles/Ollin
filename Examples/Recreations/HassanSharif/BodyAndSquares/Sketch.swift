//  Recreation after Hassan Sharif - "Body and Squares" (Dubai, 1983;
//  photographs, negatives, ink, pen and pencil on paper mounted on card,
//  84 x 59.5 cm, Guggenheim Abu Dhabi), the first of his performances and a
//  semi-system carried out on the ground. A homage, not a reproduction, and
//  not affiliated with or endorsed by the artist or his estate.
//  https://universes.art/en/specials/hassan-sharif/performance-is-good/body-squares
//  https://universes.art/en/nafas/articles/2009/hassan-sharif
//
//  An original Ollin interpretation written from the documentation and from
//  what its readers say about the method. Nothing was ported: the work is a
//  grid drawn on the ground, a body, and a camera.

import Ollin

/// "Body and Squares" (Hassan Sharif, 1983). Back in Dubai for the summer
/// of his last student year, he took the semi-systems off the paper. On a
/// patch of ground he drew a grid of twenty-five squares with a cube, the
/// whole grid the size of his body, and lay down on it, position after
/// position, a camera on a tripod above. The sheet that documents it holds
/// the sketch of the setup, the contact sheets, five prints, and, top right,
/// a long grid with squares filled in: the outcome of calculations by chance
/// and order that named the squares his body would touch in each position.
/// The work, its readers say, calculates the combinations of squares a body
/// can cover.
///
/// This sketch is the ground and the record. The grid is five by five, its
/// side one height, the squares numbered 1 to 25 in reading order. For every
/// position chance picks five numbers without repeating, one each for the
/// head, the two hands and the two feet, and the body lies down so that
/// each of those lands in its square, the joints found by relaxing a chain
/// of fixed bone lengths until the ends sit where they were sent. A pick the
/// body cannot reach is struck through on the record, as he struck out what
/// failed, and picked again. Once the body is down, every square it lies
/// across is read off the ground and filled in on the record beside a small
/// print of the position: that is the calculation and its photograph. The
/// sheet holds `positions` positions, one every `every` seconds, holds for
/// `hold` seconds when it is full, and the next sheet begins with new
/// numbers; `firstSheet` numbers the first, and a press starts the next
/// sheet now.
///
/// Every limb exports as a line and the head as a circle, so `--export-svg`
/// with a frame after the sheet is full gives the record back to be checked
/// against the body: for each position, the squares the printed body's
/// lines and head pass through are exactly the squares filled in beside it,
/// and its five ends lie in five different squares.
@main
final class BodyAndSquares: Sketch {
    @Param(4 ... 12, icon: "square.grid.2x2") var positions = 10
    @Param(1 ... 10, icon: "figure.fall") var every = 3.0
    @Param(0 ... 30, icon: "clock") var hold = 5.0
    @Param(1 ... 999, icon: "number") var firstSheet = 1

    override var canvasSize: CanvasSize { .size(1620, 1080) }

    private let wall = Color(hex: 0xE6E3DC)
    private let ground = Color(hex: 0xB5AFA3)
    private let chalk = Color(hex: 0xF4F0E6)
    private let paper = Color(hex: 0xF6F3EB)
    private let pencilGrid = Color(hex: 0xD3CEC2)
    private let handwriting = Color(hex: 0x2A2B5E)
    private let red = Color(hex: 0xC3342A)
    private let clothes = Color(hex: 0x2B2A28)
    private let ink = Color(hex: 0x1B1919)

    /// The squares on a side of the grid.
    private let across = 5

    /// How long the body takes to move from one position to the next, and
    /// how long after that the record is written.
    private let moving = 0.8
    private let recording = 1.0

    /// The body's joints.
    private enum Joint: Int, CaseIterable {
        case head, neck, shoulderL, shoulderR, elbowL, elbowR, handL, handR
        case pelvis, hipL, hipR, kneeL, kneeR, footL, footR
    }

    /// The bones, as fixed distances between joints, in units of the grid's
    /// side, which is one height.
    private nonisolated static let bones: [(Joint, Joint, Double)] = [
        (.head, .neck, 0.10), (.neck, .shoulderL, 0.12), (.neck, .shoulderR, 0.12), (.shoulderL, .shoulderR, 0.24),
        (.shoulderL, .elbowL, 0.18), (.elbowL, .handL, 0.17), (.shoulderR, .elbowR, 0.18), (.elbowR, .handR, 0.17),
        (.neck, .pelvis, 0.30), (.pelvis, .hipL, 0.08), (.pelvis, .hipR, 0.08), (.hipL, .hipR, 0.16),
        (.hipL, .kneeL, 0.24), (.kneeL, .footL, 0.23), (.hipR, .kneeR, 0.24), (.kneeR, .footR, 0.23),
    ]

    /// The bones the body lays on the ground and the print shows: the cross
    /// bars between the shoulders and between the hips are inside the trunk.
    private nonisolated static let limbs: [(Joint, Joint)] = [
        (.head, .neck), (.neck, .shoulderL), (.neck, .shoulderR),
        (.shoulderL, .elbowL), (.elbowL, .handL), (.shoulderR, .elbowR), (.elbowR, .handR),
        (.neck, .pelvis), (.pelvis, .hipL), (.pelvis, .hipR),
        (.hipL, .kneeL), (.kneeL, .footL), (.hipR, .kneeR), (.kneeR, .footR),
    ]

    /// How open a lying body stays: the least distance between a limb's two
    /// ends and between the two hands, feet and knees, so an arm or a leg
    /// lies nearly straight and the legs do not cross, as in the prints.
    private nonisolated static let spreads: [(Joint, Joint, Double)] = [
        (.shoulderL, .handL, 0.30), (.shoulderR, .handR, 0.30),
        (.hipL, .footL, 0.42), (.hipR, .footR, 0.42),
        (.handL, .handR, 0.18), (.footL, .footR, 0.14), (.kneeL, .kneeR, 0.10),
    ]

    /// The ends chance sends somewhere, in the order the numbers are picked.
    private nonisolated static let ends: [Joint] = [.head, .handL, .handR, .footL, .footR]

    private nonisolated static let headRadius = 0.065

    /// A sample of the body counts for a square only when it is this far
    /// inside it, in units of the grid's side, so a limb lying along a chalk
    /// line marks neither side.
    private nonisolated static let margin = 0.004

    /// One position: the numbers, the failed picks, the body, the squares.
    private struct Position {
        var picks: [Int]
        var struck: [[Int]]
        /// The joints, in units of the grid's side.
        var joints: [Vector2]
        var covered: Set<Int>
    }

    private struct Sheet {
        var number: Int
        var positions: [Position]
    }

    private var sheet: Sheet?
    private var began = 0.0
    private var pressed = 0
    private var program = (positions: 0, first: 0)

    override func setup() {
        textFont(OutlineFont.systemMono)
    }

    override func mousePressed() {
        pressed += 1
    }

    override func draw() {
        background(wall)

        let wanted = (positions: positions, first: firstSheet)
        if sheet == nil || program != wanted {
            program = wanted
            start(sheet: firstSheet, at: time)
        }
        while pressed > 0 {
            pressed -= 1
            start(sheet: (sheet?.number ?? firstSheet) + 1, at: time)
        }
        while let current = sheet, time - began >= duration(of: current) {
            start(sheet: current.number + 1, at: began + duration(of: current))
        }
        guard let current = sheet else { return }

        // The ground on the left, the record on the right.
        let floor = Rectangle(x: 70, y: 110, width: 860, height: 860)
        let record = Rectangle(x: 990, y: 60, width: 570, height: 960)

        // Where the body is: the position it is at, how far it has moved
        // there, and how many positions are on the record.
        let elapsed = time - began
        let index = min(current.positions.count - 1, max(0, Int(elapsed / every)))
        let within = elapsed - Double(index) * every
        let travel = min(1, within / moving)
        let recorded = index + (within >= recording ? 1 : 0)

        noStroke()
        fill(ground)
        drawRect(floor)
        drawGrid(floor, color: chalk, weight: 3, hand: true)

        let pose: [Vector2]
        if index > 0 && travel < 1 {
            let from = current.positions[index - 1].joints
            let to = current.positions[index].joints
            pose = zip(from, to).map { $0.lerp(to: $1, smoothStep(travel)) }
        } else {
            pose = current.positions[index].joints
        }
        drawBody(pose, in: floor, scale: 1)

        noStroke()
        fill(paper)
        drawRect(record)
        drawRecord(record, sheet: current, recorded: recorded)

        let title = "Body and Squares, sheet \(current.number): position \(index + 1) of \(current.positions.count)"
        drawText(title, floor.x, floor.y + floor.height + 24, size: 16, color: handwriting, align: .left, .top)
    }

    /// The grid on the ground, chalk by hand, or in pencil on the record.
    private func drawGrid(_ area: Rectangle, color: Color, weight: Double, hand: Bool) {
        noFill()
        stroke(color)
        strokeWeight(weight)
        strokeCap(.round)
        for k in 0 ... across {
            let f = Double(k) / Double(across)
            if hand {
                // A chalk line: a run of points that wander a little.
                var vertical: [Vector2] = []
                var horizontal: [Vector2] = []
                let steps = 24
                for step in 0 ... steps {
                    let t = Double(step) / Double(steps)
                    let wobble = 2.4
                    vertical.append(Vector2(area.x + area.width * f + (noise(Double(k) * 3.1, t * 5) - 0.5) * wobble,
                                            area.y + area.height * t))
                    horizontal.append(Vector2(area.x + area.width * t,
                                              area.y + area.height * f + (noise(t * 5, Double(k) * 3.1 + 40) - 0.5) * wobble))
                }
                drawPolyline(vertical)
                drawPolyline(horizontal)
            } else {
                drawLine(area.x + area.width * f, area.y, area.x + area.width * f, area.y + area.height)
                drawLine(area.x, area.y + area.height * f, area.x + area.width, area.y + area.height * f)
            }
        }
    }

    /// The body on a grid: the limbs as strokes, the trunk heavier, the head
    /// a disk. `scale` is 1 on the ground and the print's fraction on paper.
    private func drawBody(_ joints: [Vector2], in area: Rectangle, scale: Double) {
        func at(_ joint: Joint) -> Vector2 {
            let p = joints[joint.rawValue]
            return Vector2(area.x + p.x * area.width, area.y + p.y * area.height)
        }
        noFill()
        stroke(clothes)
        strokeCap(.round)
        for (a, b) in BodyAndSquares.limbs {
            let trunk = a == .neck && b == .pelvis
            strokeWeight(area.width * (trunk ? 0.12 : 0.045))
            drawLine(at(a), at(b))
        }
        noStroke()
        fill(clothes)
        drawCircle(center: at(.head), radius: area.width * BodyAndSquares.headRadius)
    }

    /// The record: a print of each position beside the grid of squares it
    /// covered, its numbers under them, and the picks that were struck out.
    private func drawRecord(_ paper: Rectangle, sheet: Sheet, recorded: Int) {
        let size = 13.0
        drawText("Body and Squares, sheet \(sheet.number)", paper.x + 24, paper.y + 22, size: size + 2,
                 color: handwriting, align: .left, .top)
        drawText("head, hands, feet: the squares picked", paper.x + 24, paper.y + 22 + size * 1.7, size: size,
                 color: handwriting, align: .left, .top)

        let columns = 2
        let rows = (sheet.positions.count + columns - 1) / columns
        let top = paper.y + 78
        let cellWidth = (paper.width - 48) / Double(columns)
        let cellHeight = (paper.height - 78 - 20) / Double(rows)
        let print = min(cellHeight - 42, 118.0)
        for index in 0 ..< min(recorded, sheet.positions.count) {
            let position = sheet.positions[index]
            let column = index % columns
            let row = index / columns
            let origin = Vector2(paper.x + 24 + Double(column) * cellWidth, top + Double(row) * cellHeight)

            // The print: the grid and the body, small.
            let printArea = Rectangle(x: origin.x, y: origin.y, width: print, height: print)
            noStroke()
            fill(ground)
            drawRect(printArea)
            drawGrid(printArea, color: chalk, weight: 1, hand: false)
            drawBody(position.joints, in: printArea, scale: print / 860)

            // The squares covered, filled in.
            let side = print * 0.62
            let squares = Rectangle(x: origin.x + print + 16, y: origin.y, width: side, height: side)
            let cell = side / Double(across)
            noStroke()
            fill(ink)
            for number in position.covered {
                let n = number - 1
                drawRect(Rectangle(x: squares.x + Double(n % across) * cell, y: squares.y + Double(n / across) * cell,
                                   width: cell, height: cell))
            }
            drawGrid(squares, color: pencilGrid, weight: 1, hand: false)

            // The numbers, and the picks that were struck.
            let textX = squares.x
            var y = squares.y + side + 8
            drawText("\(index + 1):  " + position.picks.map { String($0) }.joined(separator: " "),
                     textX, y, size: size, color: handwriting, align: .left, .top)
            y += size * 1.4
            for attempt in position.struck.suffix(2) {
                let text = attempt.map { String($0) }.joined(separator: " ")
                drawText(text, textX + 30, y, size: size * 0.9, color: handwriting, align: .left, .top)
                noFill()
                stroke(red)
                strokeWeight(1.2)
                drawLine(textX + 26, y + size * 0.5, textX + 34 + Double(text.count) * size * 0.56, y + size * 0.5)
                y += size * 1.25
            }
        }
    }

    /// Chance picks the squares for every position; the body finds a way to
    /// lie on them, or the pick is struck and chance tries again.
    private func start(sheet number: Int, at moment: Double) {
        randomSeed(number)
        var found: [Position] = []
        var previous: [Vector2]? = nil
        for _ in 0 ..< positions {
            var struck: [[Int]] = []
            var position: Position? = nil
            for _ in 0 ..< 40 {
                let picks = pickSquares()
                if let joints = BodyAndSquares.lieDown(picks: picks, across: across, near: previous) {
                    position = Position(picks: picks, struck: struck,
                                        joints: joints, covered: BodyAndSquares.squaresCovered(by: joints, across: across))
                    break
                }
                struck.append(picks)
            }
            // Forty failures in a row do not happen with these bones; if they
            // did, the body would lie straight down the middle.
            let settled = position ?? Position(picks: [3, 11, 15, 22, 24], struck: struck,
                                               joints: BodyAndSquares.lieDown(picks: [3, 11, 15, 22, 24], across: across, near: nil)
                                                   ?? BodyAndSquares.straight(), covered: [])
            found.append(settled)
            previous = settled.joints
        }
        sheet = Sheet(number: number, positions: found)
        began = moment
    }

    /// Five of the twenty-five numbers, no repeats: the first five of a
    /// shuffle.
    private func pickSquares() -> [Int] {
        let count = across * across
        var deck = Array(1 ... count)
        for i in 0 ..< BodyAndSquares.ends.count {
            let j = i + min(count - 1 - i, Int(random(0, Double(count - i))))
            deck.swapAt(i, j)
        }
        return Array(deck.prefix(BodyAndSquares.ends.count))
    }

    /// The body lying down with its ends in the picked squares: the chain of
    /// bones relaxed under the squares' pull. `nil` when the picks are out of
    /// reach.
    private nonisolated static func lieDown(picks: [Int], across: Int, near previous: [Vector2]?) -> [Vector2]? {
        let n = Double(across)
        func square(_ number: Int) -> (x: ClosedRange<Double>, y: ClosedRange<Double>) {
            let k = number - 1
            let x0 = Double(k % across) / n, y0 = Double(k / across) / n
            return (x0 ... x0 + 1 / n, y0 ... y0 + 1 / n)
        }
        func clamp(_ p: Vector2, into s: (x: ClosedRange<Double>, y: ClosedRange<Double>), inset: Double) -> Vector2 {
            Vector2(min(s.x.upperBound - inset, max(s.x.lowerBound + inset, p.x)),
                    min(s.y.upperBound - inset, max(s.y.lowerBound + inset, p.y)))
        }
        func center(_ number: Int) -> Vector2 {
            let s = square(number)
            return Vector2((s.x.lowerBound + s.x.upperBound) / 2, (s.y.lowerBound + s.y.upperBound) / 2)
        }

        // A first guess: the head at its square, the rest laid toward the
        // feet, or the last position when there was one.
        var joints: [Vector2]
        if let previous {
            joints = previous
        } else {
            joints = straight()
        }
        let head = center(picks[0])
        let feet = (center(picks[3]) + center(picks[4])) / 2
        var axis = feet - head
        let length = axis.lengthSquared.squareRoot()
        axis = length > 1e-6 ? axis / length : Vector2(0, 1)
        if previous == nil {
            let side = Vector2(-axis.y, axis.x)
            for joint in Joint.allCases {
                let s = straight()[joint.rawValue]
                joints[joint.rawValue] = head + axis * (s.y - straight()[Joint.head.rawValue].y) + side * (s.x - 0.5)
            }
        }

        let pins: [(Joint, Int, Double)] = zip(ends, picks).map { ($0, $1, $0 == .head ? headRadius : 0.02) }
        for _ in 0 ..< 500 {
            for (joint, number, inset) in pins {
                joints[joint.rawValue] = clamp(joints[joint.rawValue], into: square(number), inset: inset)
            }
            for (a, b, rest) in bones {
                var d = joints[b.rawValue] - joints[a.rawValue]
                var l = d.lengthSquared.squareRoot()
                if l < 1e-9 {
                    d = Vector2(1e-4, 0)
                    l = 1e-4
                }
                let correction = (l - rest) / l * 0.5
                joints[a.rawValue] = joints[a.rawValue] + d * correction
                joints[b.rawValue] = joints[b.rawValue] - d * correction
            }
            for (a, b, least) in spreads {
                var d = joints[b.rawValue] - joints[a.rawValue]
                var l = d.lengthSquared.squareRoot()
                if l < 1e-9 {
                    d = Vector2(1e-4, 0)
                    l = 1e-4
                }
                guard l < least else { continue }
                let correction = (l - least) / l * 0.5
                joints[a.rawValue] = joints[a.rawValue] + d * correction
                joints[b.rawValue] = joints[b.rawValue] - d * correction
            }
            for i in joints.indices {
                joints[i] = Vector2(min(1, max(0, joints[i].x)), min(1, max(0, joints[i].y)))
            }
        }
        for (joint, number, inset) in pins {
            let s = square(number)
            let p = joints[joint.rawValue]
            let tolerance = 0.004
            guard p.x >= s.x.lowerBound + inset - tolerance, p.x <= s.x.upperBound - inset + tolerance,
                  p.y >= s.y.lowerBound + inset - tolerance, p.y <= s.y.upperBound - inset + tolerance else { return nil }
        }
        for (a, b, rest) in bones {
            let l = (joints[b.rawValue] - joints[a.rawValue]).lengthSquared.squareRoot()
            if abs(l - rest) > 0.01 { return nil }
        }
        for (a, b, least) in spreads {
            let l = (joints[b.rawValue] - joints[a.rawValue]).lengthSquared.squareRoot()
            if l < least - 0.01 { return nil }
        }
        return joints
    }

    /// The body lying straight down the middle of the grid, head at the top.
    private nonisolated static func straight() -> [Vector2] {
        var joints = [Vector2](repeating: .zero, count: Joint.allCases.count)
        joints[Joint.head.rawValue] = Vector2(0.5, 0.09)
        joints[Joint.neck.rawValue] = Vector2(0.5, 0.19)
        joints[Joint.shoulderL.rawValue] = Vector2(0.38, 0.19)
        joints[Joint.shoulderR.rawValue] = Vector2(0.62, 0.19)
        joints[Joint.elbowL.rawValue] = Vector2(0.36, 0.37)
        joints[Joint.elbowR.rawValue] = Vector2(0.64, 0.37)
        joints[Joint.handL.rawValue] = Vector2(0.35, 0.54)
        joints[Joint.handR.rawValue] = Vector2(0.65, 0.54)
        joints[Joint.pelvis.rawValue] = Vector2(0.5, 0.49)
        joints[Joint.hipL.rawValue] = Vector2(0.42, 0.49)
        joints[Joint.hipR.rawValue] = Vector2(0.58, 0.49)
        joints[Joint.kneeL.rawValue] = Vector2(0.42, 0.73)
        joints[Joint.kneeR.rawValue] = Vector2(0.58, 0.73)
        joints[Joint.footL.rawValue] = Vector2(0.42, 0.96)
        joints[Joint.footR.rawValue] = Vector2(0.58, 0.96)
        return joints
    }

    /// The squares the body lies across: every square a limb's line or the
    /// head's disk passes through by more than the margin.
    private nonisolated static func squaresCovered(by joints: [Vector2], across: Int) -> Set<Int> {
        var covered = Set<Int>()
        let n = Double(across)
        func mark(_ p: Vector2) {
            let cx = p.x * n, cy = p.y * n
            let fx = cx - cx.rounded(.down), fy = cy - cy.rounded(.down)
            let m = margin * n
            guard fx > m, fx < 1 - m, fy > m, fy < 1 - m else { return }
            let column = Int(cx), row = Int(cy)
            guard column >= 0, column < across, row >= 0, row < across else { return }
            covered.insert(row * across + column + 1)
        }
        let step = 0.002
        for (a, b) in limbs {
            let from = joints[a.rawValue], to = joints[b.rawValue]
            let length = (to - from).lengthSquared.squareRoot()
            let count = max(1, Int(length / step))
            for k in 0 ... count {
                mark(from.lerp(to: to, Double(k) / Double(count)))
            }
        }
        let head = joints[Joint.head.rawValue]
        for ring in 0 ... 6 {
            let r = headRadius * Double(ring) / 6
            for k in 0 ..< 48 {
                let angle = Double(k) / 48 * 2 * .pi
                mark(Vector2(head.x + cos(angle) * r, head.y + sin(angle) * r))
            }
        }
        return covered
    }

    private func smoothStep(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }

    /// Every position at its pace, then the hold.
    private func duration(of sheet: Sheet) -> Double {
        Double(sheet.positions.count) * every + hold
    }
}
