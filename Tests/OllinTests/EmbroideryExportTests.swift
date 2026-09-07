import Ollin
import Testing
import Foundation

/// Checks on the embroidery exporter. Like the G-code tests, these record draw
/// calls on the CPU and never touch Metal, so they run everywhere. Each file is
/// read back through a small reader below, and the tests assert machine facts
/// (every record moves within the grid, the decoded path lands where the plan
/// said, a fill is rows, a color is a thread) rather than exact bytes.
@Suite
@MainActor
struct EmbroideryExportTests {

    // MARK: - A small .dst reader

    /// The header's counts and every record decoded back to a position on the
    /// tenth-millimeter grid, from the design's start.
    struct DST {
        enum Kind { case stitch, jump, colorChange, end }
        struct Record {
            var kind: Kind
            var dx: Int, dy: Int
            var x: Int, y: Int
        }
        var label = ""
        var headerCount = 0
        var headerColors = 0
        var extents = (plusX: 0, minusX: 0, plusY: 0, minusY: 0)
        var records: [Record] = []

        init(_ data: Data) {
            precondition(data.count >= 515, "a .dst is a 512-byte header plus records")
            let header = String(decoding: data.prefix(512), as: UTF8.self)
            func field(_ key: String) -> String {
                guard let range = header.range(of: key + ":") else { return "" }
                let rest = header[range.upperBound...]
                return String(rest.prefix { $0 != "\r" })
            }
            label = field("LA").trimmingCharacters(in: .whitespaces)
            headerCount = Int(field("ST").trimmingCharacters(in: .whitespaces)) ?? -1
            headerColors = Int(field("CO").trimmingCharacters(in: .whitespaces)) ?? -1
            extents = (Int(field("+X").trimmingCharacters(in: .whitespaces)) ?? -1,
                       Int(field("-X").trimmingCharacters(in: .whitespaces)) ?? -1,
                       Int(field("+Y").trimmingCharacters(in: .whitespaces)) ?? -1,
                       Int(field("-Y").trimmingCharacters(in: .whitespaces)) ?? -1)
            let bytes = [UInt8](data)
            var x = 0, y = 0
            var i = 512
            while i + 2 < bytes.count {
                let b0 = bytes[i], b1 = bytes[i + 1], b2 = bytes[i + 2]
                i += 3
                if b0 == 0, b1 == 0, b2 == 0xF3 {
                    records.append(Record(kind: .end, dx: 0, dy: 0, x: x, y: y))
                    break
                }
                var dx = 0, dy = 0
                if b0 & 0x01 != 0 { dx += 1 }
                if b0 & 0x02 != 0 { dx -= 1 }
                if b0 & 0x04 != 0 { dx += 9 }
                if b0 & 0x08 != 0 { dx -= 9 }
                if b0 & 0x80 != 0 { dy += 1 }
                if b0 & 0x40 != 0 { dy -= 1 }
                if b0 & 0x20 != 0 { dy += 9 }
                if b0 & 0x10 != 0 { dy -= 9 }
                if b1 & 0x01 != 0 { dx += 3 }
                if b1 & 0x02 != 0 { dx -= 3 }
                if b1 & 0x04 != 0 { dx += 27 }
                if b1 & 0x08 != 0 { dx -= 27 }
                if b1 & 0x80 != 0 { dy += 3 }
                if b1 & 0x40 != 0 { dy -= 3 }
                if b1 & 0x20 != 0 { dy += 27 }
                if b1 & 0x10 != 0 { dy -= 27 }
                if b2 & 0x04 != 0 { dx += 81 }
                if b2 & 0x08 != 0 { dx -= 81 }
                if b2 & 0x20 != 0 { dy += 81 }
                if b2 & 0x10 != 0 { dy -= 81 }
                let kind: Kind
                switch b2 & 0xC0 {
                case 0xC0: kind = .colorChange
                case 0x80: kind = .jump
                default: kind = .stitch
                }
                x += dx
                y += dy
                records.append(Record(kind: kind, dx: dx, dy: dy, x: x, y: y))
            }
        }

        var moves: [Record] { records.filter { $0.kind != .end } }
    }

    // MARK: - Probes

    /// A 200 x 100 canvas, so `width: 200` puts one millimeter on each unit.
    private func probe(_ body: @escaping (Sketch) -> Void) -> StitchProbe {
        let p = StitchProbe()
        p.body = body
        return p
    }

    private let mm = Embroidery(width: 200)

    /// The plan's positions on the file's own grid: tenth-millimeters from the
    /// canvas center, y up.
    private func grid(_ p: Vector2, canvas: Rectangle, settings: Embroidery) -> (Int, Int) {
        let s = settings.width / canvas.width * 10
        return (Int(((p.x - canvas.center.x) * s).rounded()),
                Int(((canvas.center.y - p.y) * s).rounded()))
    }

    // MARK: - Laws

    @Test func theFileIsAHeaderAndRecordsThatCountThemselves() {
        let sketch = probe { s in
            s.noFill(); s.stroke(.black); s.strokeWeight(2)
            s.drawRect(40, 20, 100, 50)
        }
        let data = OllinApp.embroidery(of: sketch, settings: mm)
        let file = DST(data)
        #expect(data.count == 512 + 3 * file.records.count)
        #expect(file.records.last?.kind == .end)
        #expect(file.headerCount == file.moves.count, "ST counts every record before the end")
        #expect(file.headerColors == 0)
        #expect(file.label == "OLLIN")
        let plan = OllinApp.stitching(of: sketch, settings: mm)
        #expect(plan.threads.count == 1 && plan.colorChanges == 0)
        #expect(plan.stitchCount == file.moves.filter { $0.kind == .stitch }.count)
    }

    @Test func everyRecordMovesWithinTheGridAndLandsWhereThePlanSaid() {
        let sketch = probe { s in
            s.noFill(); s.stroke(.black); s.strokeWeight(2)
            s.drawCircle(60, 50, 35)
            s.drawLine(120, 10, 190, 90)
            s.drawRect(130, 20, 30, 30)
        }
        let plan = OllinApp.stitching(of: sketch, settings: mm)
        let file = DST(plan.dst())
        #expect(file.moves.allSatisfy { abs($0.dx) <= 121 && abs($0.dy) <= 121 })
        // Every stitch and jump of the plan is reached by the file, on the grid,
        // even though a long jump is spread over several records.
        let canvas = Rectangle(x: 0, y: 0, width: 200, height: 100)
        let planned = plan.stitches.filter { $0.kind != .colorChange }
            .map { grid($0.position, canvas: canvas, settings: mm) }
        let landed = Set(file.moves.map { [$0.x, $0.y] })
        let missed = planned.filter { !landed.contains([$0.0, $0.1]) }
        #expect(missed.isEmpty, "\(missed.count) of \(planned.count) planned points never reached")
        // The extents in the header are the extents of the path.
        let xs = file.moves.map(\.x), ys = file.moves.map(\.y)
        #expect(file.extents.plusX == xs.max()! && file.extents.minusX == -xs.min()!)
        #expect(file.extents.plusY == ys.max()! && file.extents.minusY == -ys.min()!)
    }

    @Test func aRunningStitchKeepsThePitchAndHitsTheCorners() {
        let sketch = probe { s in
            s.noFill(); s.stroke(.black); s.strokeWeight(2)
            s.drawRect(40, 20, 100, 50)
        }
        let plan = OllinApp.stitching(of: sketch, settings: mm)
        var previous: Vector2?
        var longest = 0.0
        for stitch in plan.stitches where stitch.kind == .stitch {
            if let p = previous { longest = max(longest, p.distance(to: stitch.position)) }
            previous = stitch.position
        }
        #expect(longest <= 2.5 + 1e-9, "no stitch is longer than the pitch (\(longest))")
        let corners = [Vector2(40, 20), Vector2(140, 20), Vector2(140, 70), Vector2(40, 70)]
        for corner in corners {
            #expect(plan.stitches.contains { $0.kind == .stitch && $0.position.distance(to: corner) < 1e-6 },
                    "the corner \(corner) is a penetration")
        }
        #expect(abs(plan.threadLength - 300) < 1e-6, "the perimeter is sewn once (\(plan.threadLength))")
    }

    @Test func aFillIsRowsAtTheSpacingOrItsOutlineAlone() {
        let sketch = probe { s in
            s.noStroke(); s.fill(.black)
            s.drawRect(50, 30, 40, 20)
        }
        let rows = OllinApp.stitching(of: sketch, settings: Embroidery(width: 200, fillSpacing: 0.5))
        let ys = Set(rows.stitches.filter { $0.kind == .stitch }.map { Int(($0.position.y * 100).rounded()) })
        #expect(ys.count >= 38 && ys.count <= 42, "twenty millimeters at half-millimeter rows (\(ys.count))")
        #expect(rows.stitches.filter { $0.kind == .stitch }.allSatisfy {
            $0.position.x >= 50 - 1e-6 && $0.position.x <= 90 + 1e-6
                && $0.position.y >= 30 - 1e-6 && $0.position.y <= 50 + 1e-6
        }, "every stitch of the fill lies inside it")
        // Rows are connected end to end where they can be: far fewer jumps than rows.
        #expect(rows.jumpCount <= 2, "the rows connect without lifting the thread (\(rows.jumpCount))")

        let outline = OllinApp.stitching(of: sketch, settings: Embroidery(width: 200, fillSpacing: nil))
        let onEdge = outline.stitches.filter { $0.kind == .stitch }.allSatisfy { st in
            let p = st.position
            let onX = abs(p.x - 50) < 1e-6 || abs(p.x - 90) < 1e-6
            let onY = abs(p.y - 30) < 1e-6 || abs(p.y - 50) < 1e-6
            return onX || onY
        }
        #expect(onEdge, "with no spacing the fill is sewn as its outline")
        #expect(abs(outline.threadLength - 120) < 1e-6)
    }

    @Test func eachColorIsItsOwnThreadInDrawOrder() {
        let sketch = probe { s in
            s.noStroke()
            s.fill(.red); s.drawRect(10, 10, 30, 30)
            s.fill(.blue); s.drawRect(60, 10, 30, 30)
            s.fill(.red); s.drawRect(110, 10, 30, 30)
        }
        let plan = OllinApp.stitching(of: sketch, settings: mm)
        #expect(plan.threads == [.red, .blue, .red], "later red sews on top, so it is its own thread")
        #expect(plan.colorChanges == 2)
        let file = DST(plan.dst())
        #expect(file.headerColors == 2)
        #expect(file.moves.filter { $0.kind == .colorChange }.count == 2)
        // A change of thread moves nothing.
        #expect(file.moves.filter { $0.kind == .colorChange }.allSatisfy { $0.dx == 0 && $0.dy == 0 })
    }

    @Test func aLongHopIsAJumpSpreadOverSeveralRecords() {
        let sketch = probe { s in
            s.noFill(); s.stroke(.black); s.strokeWeight(2)
            s.drawLine(5, 50, 15, 50)
            s.drawLine(185, 50, 195, 50)
        }
        let plan = OllinApp.stitching(of: sketch, settings: mm)
        // One jump between the two lines (the hop from the center to the first
        // line is a jump too).
        #expect(plan.jumpCount == 2)
        let file = DST(plan.dst())
        let jumps = file.moves.filter { $0.kind == .jump }
        // 170 mm at most 12.1 mm a record.
        #expect(jumps.count >= 14 + 8, "the long hop is many records (\(jumps.count))")
        #expect(jumps.allSatisfy { abs($0.dx) <= 121 && abs($0.dy) <= 121 })
        // Nothing is sewn while the thread is carried: a run of jumps, then stitches.
        var runs = 0
        var inJump = false
        for r in file.moves {
            if r.kind == .jump { if !inJump { runs += 1; inJump = true } } else { inJump = false }
        }
        #expect(runs == 2)
    }

    @Test func theWidthSetsTheScaleAndTheHoopGrowsUpward() {
        let sketch = probe { s in
            s.noFill(); s.stroke(.black); s.strokeWeight(2)
            s.drawLine(0, 10, 200, 10)
        }
        let file = DST(OllinApp.embroidery(of: sketch, settings: Embroidery(width: 100)))
        let xs = file.moves.map(\.x), ys = file.moves.map(\.y)
        #expect(xs.max()! - xs.min()! == 1000, "two hundred units across at 100 mm is 1000 grid steps")
        // Forty units above the center at half a millimeter a unit is 200 grid steps up.
        #expect(ys.allSatisfy { $0 >= 0 } && ys.max()! == 200, "the canvas top is above the center in the hoop (\(ys.max()!))")
        let plan = OllinApp.stitching(of: sketch, settings: Embroidery(width: 100, margin: 5))
        #expect(abs(plan.size.width - 110) < 1e-9 && abs(plan.size.height - 60) < 1e-9)
    }

    @Test func orderingShortensTheJumpsAndSewsTheSameThread() {
        let sketch = probe { s in
            s.noFill(); s.stroke(.black); s.strokeWeight(2)
            // Four short strokes drawn in the worst order for a machine.
            s.drawLine(10, 10, 20, 10)
            s.drawLine(180, 90, 190, 90)
            s.drawLine(10, 90, 20, 90)
            s.drawLine(180, 10, 190, 10)
        }
        let ordered = OllinApp.stitching(of: sketch, settings: Embroidery(width: 200))
        let asDrawn = OllinApp.stitching(of: sketch, settings: Embroidery(width: 200, optimizesTravel: false))
        #expect(ordered.jumpLength < asDrawn.jumpLength * 0.8, "\(ordered.jumpLength) against \(asDrawn.jumpLength)")
        #expect(abs(ordered.threadLength - asDrawn.threadLength) < 1e-6)
        #expect(ordered.stitchCount == asDrawn.stitchCount)
    }

    @Test func theFileTakesItsLabelFromItsName() throws {
        let sketch = probe { s in
            s.noFill(); s.stroke(.black); s.strokeWeight(2)
            s.drawCircle(100, 50, 30)
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-embroidery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("Rings.dst").path
        OllinApp.exportEmbroidery(sketch, to: path, settings: mm)
        let file = DST(try Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(file.label == "RINGS")
        #expect(file.moves.filter { $0.kind == .stitch }.count > 60)
    }

    @Test func thePublicPlannerTakesPlainContours() {
        let canvas = Rectangle(x: 0, y: 0, width: 200, height: 100)
        let square = Contour([Vector2(20, 20), Vector2(80, 20), Vector2(80, 80), Vector2(20, 80)], closed: true)
        let plan = mm.stitches([square], in: canvas)
        #expect(abs(plan.threadLength - 240) < 1e-6)
        #expect(plan.threads == [.black])
        let data = mm.data([square], in: canvas, label: "SQ")
        #expect(DST(data).label == "SQ")
    }
}

/// A sketch whose whole drawing is a closure, on a 200 x 100 canvas.
private final class StitchProbe: Sketch {
    var body: (Sketch) -> Void = { _ in }
    override var canvasSize: CanvasSize { .size(200, 100) }
    override func draw() { body(self) }
}
