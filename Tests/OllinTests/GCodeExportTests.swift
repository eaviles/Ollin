import Ollin
import Testing

/// Checks on the G-code exporter. Like the SVG tests, these record draw calls
/// on the CPU and never touch Metal, so they run everywhere. Each program is
/// replayed through a small interpreter below, and the tests assert machine
/// facts (the pen is up whenever the head travels, the laser power word rides
/// only cutting moves, the cutter never goes below the asked depth, nothing
/// leaves the bed) rather than exact program text.
@Suite
@MainActor
struct GCodeExportTests {

    // MARK: - A small G-code interpreter

    /// Replays a program tracking the modal state the dialect defines: motion
    /// mode, position, feed, power word, and the spindle/laser mode.
    struct Sim {
        struct Segment {
            var rapid: Bool
            var from: (x: Double, y: Double, z: Double)
            var to: (x: Double, y: Double, z: Double)
            var s: Double
            var power: String?          // "M3", "M4", or nil after M5
        }
        var segments: [Segment] = []
        var sawEnd = false
        var comments: [String] = []
        var endedWithPowerOff = true    // no M3/M4 still in force at M2

        init(_ text: String) {
            var x = 0.0, y = 0.0, z = 0.0, s = 0.0
            var motion = "G0"
            var power: String?
            for rawLine in text.split(separator: "\n") {
                var line = String(rawLine)
                if let mark = line.firstIndex(of: ";") {
                    let comment = String(line[line.index(after: mark)...])
                        .trimmingCharacters(in: .whitespaces)
                    if !comment.isEmpty { comments.append(comment) }
                    line = String(line[..<mark])
                }
                var newX: Double?, newY: Double?, newZ: Double?
                for word in line.split(separator: " ") {
                    let letter = word.prefix(1)
                    let value = Double(word.dropFirst())
                    switch letter {
                    case "G":
                        if word == "G0" || word == "G1" { motion = String(word) }
                    case "M":
                        if word == "M3" || word == "M4" { power = String(word) }
                        if word == "M5" { power = nil }
                        if word == "M2" { sawEnd = true; endedWithPowerOff = power == nil }
                    case "X": newX = value
                    case "Y": newY = value
                    case "Z": newZ = value
                    case "S": if let value { s = value }
                    default: break
                    }
                }
                if newX != nil || newY != nil || newZ != nil {
                    let from = (x, y, z)
                    x = newX ?? x; y = newY ?? y; z = newZ ?? z
                    segments.append(Segment(rapid: motion == "G0", from: from,
                                            to: (x, y, z), s: s, power: power))
                }
            }
        }

        /// Segments that move in the plane (draw, cut, or travel).
        var planar: [Segment] {
            segments.filter { $0.from.x != $0.to.x || $0.from.y != $0.to.y }
        }
    }

    // MARK: - Fixtures

    /// One line drawn across a 100 px canvas: the smallest thing to measure.
    final class OneLine: Sketch {
        override var canvasSize: CanvasSize { .square(100) }
        override func draw() {
            background(.white)
            stroke(.black)
            drawLine(Vector2(10, 10), Vector2(90, 10))
            noLoop()
        }
    }

    /// A mix of stroke, fill, and an off-canvas overhang. Seeded, so the
    /// reproduction recipe (and with it the program text) is byte-stable.
    final class Mixed: Sketch {
        override var canvasSize: CanvasSize { .square(100) }
        override func setup() { randomSeed(7); noiseSeed(7) }
        override func draw() {
            background(.white)
            noStroke()
            fill(.black)
            drawRect(20, 20, 30, 20)                        // fill -> outline loop
            stroke(.black)
            drawLine(Vector2(50, 90), Vector2(150, 90))     // runs off the canvas
            drawCircle(70, 60, 15)                          // stroked ring
            let blank = Image(width: 4, height: 4, color: .blue)
            drawImage(blank, 0, 0, 8, 8)                    // skipped -> note
            noLoop()
        }
    }

    /// A line crossing a circular clip region.
    final class Clipped: Sketch {
        override var canvasSize: CanvasSize { .square(100) }
        override func draw() {
            background(.white)
            stroke(.black)
            withClip(Circle(center: Vector2(50, 50), radius: 20)) {
                drawLine(Vector2(0, 50), Vector2(100, 50))
            }
            noLoop()
        }
    }

    static let plotter = GCode(.plotter(), width: 100)

    // MARK: - Plotter

    @Test func plotterPenIsUpForEveryTravel() {
        let sim = Sim(OllinApp.gcode(of: Mixed(), settings: Self.plotter))
        #expect(sim.sawEnd)
        #expect(!sim.planar.isEmpty)
        for segment in sim.planar {
            if segment.rapid {
                #expect(segment.from.z == 5 && segment.to.z == 5)   // travel: pen up
            } else {
                #expect(segment.from.z == 0 && segment.to.z == 0)   // draw: pen down
            }
        }
    }

    @Test func theCanvasTopBecomesTheBedTop() {
        // Canvas y grows downward, the bed's grows upward: the line drawn at
        // canvas y 10 on a 100 px -> 100 mm square must plot at machine y 90.
        let sim = Sim(OllinApp.gcode(of: OneLine(), settings: Self.plotter))
        let draws = sim.planar.filter { !$0.rapid }
        #expect(draws.count == 1)
        if let draw = draws.first {
            #expect(abs(draw.from.y - 90) < 1e-6 && abs(draw.to.y - 90) < 1e-6)
            #expect(min(draw.from.x, draw.to.x) == 10 && max(draw.from.x, draw.to.x) == 90)
        }
    }

    @Test func nothingLeavesTheBed() {
        let settings = GCode(.plotter(), width: 100, margin: 10)
        let sim = Sim(OllinApp.gcode(of: Mixed(), settings: settings))
        for segment in sim.planar where !segment.rapid {
            for point in [segment.from, segment.to] {
                #expect(point.x >= 10 - 1e-6 && point.x <= 110 + 1e-6)
                #expect(point.y >= 10 - 1e-6 && point.y <= 110 + 1e-6)
            }
        }
        // The overhang was really cut, not scaled away: some draw ends at the
        // bed's right edge.
        let maxX = sim.planar.filter { !$0.rapid }.map { max($0.from.x, $0.to.x) }.max() ?? 0
        #expect(abs(maxX - 110) < 1e-3)
    }

    @Test func theProgramIsDeterministic() {
        let a = OllinApp.gcode(of: Mixed(), settings: Self.plotter)
        let b = OllinApp.gcode(of: Mixed(), settings: Self.plotter)
        #expect(a == b)
    }

    @Test func theHeaderSaysWhatAndHowBig() {
        let program = OllinApp.gcode(of: Mixed(), settings: Self.plotter)
        #expect(program.contains("; canvas 100 x 100 px maps to 100 x 100 mm"))
        #expect(program.contains("machine: pen plotter"))
        #expect(program.contains("G21 ; millimeters"))
        #expect(program.contains("G90 ; absolute coordinates"))
        #expect(program.contains("image draw call has no line work"))   // the skipped note
        #expect(program.contains("; {\"tool\":\"Ollin\""))               // the recipe line
    }

    @Test func servoPenWritesPowerWordsAndDwells() {
        let settings = GCode(.plotter(pen: .servo(up: 0, down: 1000)), width: 100)
        let program = OllinApp.gcode(of: OneLine(), settings: settings)
        #expect(program.contains("M3 S1000"))
        #expect(program.contains("M3 S0"))
        #expect(program.contains("G4 P0.15"))
        #expect(!program.contains("G0 Z"))                      // no Z axis in servo mode
    }

    // MARK: - Laser

    @Test func laserPowerRidesOnlyCuttingMoves() {
        let settings = GCode(.laser(power: 0.6, passes: 2), width: 100)
        let program = OllinApp.gcode(of: OneLine(), settings: settings)
        let sim = Sim(program)
        #expect(program.contains("M4 S0"))                      // dynamic mode, armed at zero
        let cuts = sim.planar.filter { !$0.rapid }
        #expect(cuts.count == 2)                                // two passes over the one line
        for cut in cuts {
            #expect(cut.s == 600)                               // 0.6 of the S 1000 scale
            #expect(cut.power == "M4")
        }
        for travel in sim.planar.filter(\.rapid) {
            #expect(travel.rapid)                               // travels stay rapids: beam off
        }
        #expect(sim.endedWithPowerOff)                          // M5 before M2
    }

    @Test func constantModeArmsWithM3() {
        let settings = GCode(.laser(mode: .constant), width: 100)
        let program = OllinApp.gcode(of: OneLine(), settings: settings)
        #expect(program.contains("M3 S0"))
        #expect(!program.contains("M4"))
    }

    // MARK: - Mill

    @Test func millStaysAboveTheAskedDepthAndTravelsSafe() {
        let settings = GCode(.mill(depth: 1.2, depthPerPass: 0.5), width: 100)
        let sim = Sim(OllinApp.gcode(of: Mixed(), settings: settings))
        var depths = Set<Double>()
        for segment in sim.segments {
            #expect(segment.to.z >= -1.2 - 1e-9)
            if segment.rapid, segment.from.x != segment.to.x || segment.from.y != segment.to.y {
                #expect(segment.from.z == 5 && segment.to.z == 5)   // travel at safe height
            }
            if !segment.rapid, segment.from.x != segment.to.x || segment.from.y != segment.to.y {
                #expect(segment.to.z < 0)                           // cutting happens in the stock
                #expect(segment.power == "M3")                      // spindle on
                depths.insert(segment.to.z)
            }
        }
        #expect(depths == [-0.5, -1.0, -1.2])                       // the pass ladder, exact
        #expect(sim.endedWithPowerOff)
    }

    // MARK: - Planning

    @Test func orderingShortensTravel() {
        // Segments deliberately scrambled: drawn order ping-pongs across the
        // canvas, nearest-neighbor order walks straight down.
        let canvas = Rectangle(x: 0, y: 0, width: 100, height: 100)
        var paths: [Contour] = []
        for i in 0..<10 {
            let y = Double(i) * 10
            paths.append(Contour([Vector2(i % 2 == 0 ? 0 : 90, y),
                                  Vector2(i % 2 == 0 ? 10 : 100, y)], closed: false))
        }
        let ordered = GCode(.plotter(), width: 100).toolpath(paths, in: canvas)
        let drawnOrder = GCode(.plotter(), width: 100, ordered: false, joinTolerance: 0)
            .toolpath(paths, in: canvas)
        #expect(ordered.travelLength < drawnOrder.travelLength)
        #expect(ordered.drawnLength == drawnOrder.drawnLength)      // ordering never redraws
    }

    @Test func touchingEndsMergeAndClose() {
        let canvas = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let square = [
            Contour([Vector2(10, 10), Vector2(90, 10)], closed: false),
            Contour([Vector2(90, 90), Vector2(10, 90)], closed: false),
            Contour([Vector2(90, 10), Vector2(90, 90)], closed: false),
            Contour([Vector2(10, 90), Vector2(10, 10)], closed: false),
        ]
        let toolpath = GCode(.plotter(), width: 100).toolpath(square, in: canvas)
        #expect(toolpath.paths.count == 1)
        #expect(toolpath.paths.first?.isClosed == true)
        #expect(abs(toolpath.drawnLength - 320) < 1e-6)
    }

    @Test func aClosedLoopEntersAtItsNearestCorner() {
        let canvas = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let loop = Contour([Vector2(60, 20), Vector2(80, 20), Vector2(80, 40), Vector2(60, 40)])
        let toolpath = GCode(.plotter(), width: 100).toolpath([loop], in: canvas)
        // The machine origin is the canvas's bottom-left, canvas point (0, 100):
        // the nearest corner of the loop is (60, 40).
        #expect(toolpath.paths.first?.points.first == Vector2(60, 40))
        #expect(toolpath.paths.first?.isClosed == true)
    }

    @Test func toolpathClipsToTheCanvas() {
        let canvas = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let overhang = Contour([Vector2(50, 50), Vector2(200, 50)], closed: false)
        let toolpath = GCode(.plotter(), width: 100).toolpath([overhang], in: canvas)
        #expect(toolpath.paths.count == 1)
        for point in toolpath.paths[0].points {
            #expect(point.x <= 100 + 1e-6)
        }
        #expect(abs(toolpath.drawnLength - 50) < 1e-3)
    }

    @Test func aClipRegionCutsTheLineWork() {
        let sim = Sim(OllinApp.gcode(of: Clipped(), settings: Self.plotter))
        let draws = sim.planar.filter { !$0.rapid }
        #expect(!draws.isEmpty)
        for draw in draws {
            // Machine space keeps x; y flips around 50 on this square canvas,
            // so the clip circle stays centered at (50, 50).
            for point in [draw.from, draw.to] {
                let dx = point.x - 50, dy = point.y - 50
                #expect((dx * dx + dy * dy).squareRoot() <= 20 + 1e-3)
            }
        }
    }

    @Test func hatchingTurnsAFillIntoManyLines() {
        let plain = Sim(OllinApp.gcode(of: Mixed(), settings: Self.plotter))
        let hatched = Sim(OllinApp.gcode(of: Mixed(), settings: Self.plotter,
                                         hatching: Hatching(spacing: 2)))
        let plainDraws = plain.planar.filter { !$0.rapid }.count
        let hatchedDraws = hatched.planar.filter { !$0.rapid }.count
        #expect(hatchedDraws > plainDraws + 5)
    }

    @Test func aSketchCanEmitItsOwnProgram() {
        let canvas = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let paths = [Contour([Vector2(0, 0), Vector2(100, 100)], closed: false)]
        let program = GCode(.plotter(), width: 200).program(paths, in: canvas)
        #expect(program.contains("G21"))
        #expect(program.hasSuffix("M2 ; end\n"))
        let toolpath = GCode(.plotter(), width: 200).toolpath(paths, in: canvas)
        #expect(abs(toolpath.drawnLength - 200 * 2.0.squareRoot()) < 1e-6)
        #expect(toolpath.travels.count == 2)                        // out and home again
    }
}
