//  Recreation after Sol LeWitt - "Wall Drawing 118" (1971), the instruction
//  that places fifty points at random on a wall and connects every one of them
//  to every other with a straight line. A homage, not a reproduction, and not
//  affiliated with or endorsed by the artist or his estate.
//  https://www.artic.edu/artworks/196148/wall-drawing-118-50-randomly-placed-points-connected-by-straight-lines
//
//  An original Ollin interpretation written from the published instruction.
//  Nothing was ported: a LeWitt wall drawing is a written instruction that a
//  drafter carries out, and this sketch is one more drafter carrying it out.

import Ollin

/// "Wall Drawing 118" (Sol LeWitt, 1971). The whole work is three sentences:
/// "On a wall surface, any continuous stretch of wall, using a hard pencil,
/// place fifty points at random. The points should be evenly distributed over
/// the area of the wall. All of the points should be connected by straight
/// lines."
///
/// LeWitt did not draw his wall drawings. He wrote them, and other people drew
/// them, each time on a new wall, so every installation of the same work is a
/// different drawing. The instruction is the work, the way a score is the
/// piece. That makes this sketch the drafter rather than the picture. It
/// places the fifty points and connects them one line at a time at a
/// drafter's pace. It holds the finished wall for a while, then paints the
/// wall over and starts again, and the next drawing is not the last one.
///
/// Two things in the sentence do the work. "At random" and "evenly
/// distributed" pull against each other, since plain chance clumps. So the
/// drafter here throws a handful of candidate spots for every point and keeps
/// the one farthest from the points already placed. And "all of the points"
/// is a count: fifty points make 1,225 lines, and a wall this dense is what a
/// small rule looks like when it is followed all the way.
///
/// Try it: `points` is the number in the instruction, `pace` how many lines a
/// second the drafter draws, and `hold` how long the finished wall stays up
/// before the next one starts. `firstWall` picks the first drawing, and every
/// wall after it is the next one in line. A press moves on to the next wall.
/// The lines export as strokes, so `--export-svg` with a frame after the
/// drawing is done gives all 1,225 of them back.
@main
final class FiftyPoints: Sketch {
    @Param(3 ... 120, icon: "circle.grid.3x3") var points = 50
    @Param(10 ... 600, icon: "pencil") var pace = 90.0
    @Param(0 ... 30, icon: "clock") var hold = 6.0
    @Param(1 ... 999, icon: "dice") var firstWall = 1

    /// Seconds between one point being placed and the next.
    private let placingStep = 0.05
    /// How many spots the drafter weighs before placing each point.
    private let candidates = 24

    /// The wall the cached points belong to, so a new wall rolls new points
    /// once rather than every frame.
    private var wall = Int.min
    private var placed: [Vector2] = []
    /// Every pair of points, in the order the drafter connects them: the first
    /// point to all the others, then the second to all the ones after it.
    private var pairs: [(Int, Int)] = []
    private var skipped = 0

    override func mousePressed() {
        skipped += 1
    }

    override func draw() {
        background(Color(hex: 0xF3F1EC))

        let count = max(3, points)
        let lineCount = count * (count - 1) / 2
        let placing = Double(count) * placingStep
        let drawing = Double(lineCount) / pace
        let cycle = placing + drawing + hold
        let lap = Int(time / cycle)
        let phase = time - Double(lap) * cycle
        let current = firstWall + skipped + lap
        if current != wall || placed.count != count {
            prepare(wall: current, count: count)
        }

        // A hard pencil: thin, gray, and a little darker where lines cross.
        noFill()
        stroke(Color(white: 0.28, alpha: 0.55))
        strokeWeight(1)
        strokeCap(.butt)

        let progress = max(0, (phase - placing) * pace)
        let whole = min(lineCount, Int(progress))
        for k in 0 ..< whole {
            let (i, j) = pairs[k]
            drawLine(placed[i], placed[j])
        }
        // The line under the pencil right now, as far as it has got.
        if whole < lineCount {
            let (i, j) = pairs[whole]
            let fraction = progress - Double(whole)
            if fraction > 0 {
                drawLine(placed[i], Vector2.lerp(placed[i], placed[j], fraction))
            }
        }

        noStroke()
        fill(Color(white: 0.15))
        let shown = phase < placing ? min(count, Int(phase / placingStep) + 1) : count
        for point in placed.prefix(shown) {
            drawCircle(center: point, radius: 3)
        }
    }

    /// Places the points for one wall. Each one is the farthest of a handful of
    /// random spots from everything placed before it, which is what "at
    /// random" and "evenly distributed" come to when both have to hold.
    private func prepare(wall: Int, count: Int) {
        self.wall = wall
        randomSeed(wall)
        let room = Rectangle(center: center, width: width * 0.88, height: height * 0.88)
        placed = []
        placed.reserveCapacity(count)
        for _ in 0 ..< count {
            var best = randomVector(in: room)
            var bestClearance = -1.0
            for _ in 0 ..< candidates {
                let candidate = randomVector(in: room)
                let clearance = placed.map { $0.distance(to: candidate) }.min() ?? .infinity
                if clearance > bestClearance {
                    best = candidate
                    bestClearance = clearance
                }
            }
            placed.append(best)
        }
        pairs = []
        pairs.reserveCapacity(count * (count - 1) / 2)
        for i in 0 ..< count {
            for j in (i + 1) ..< count {
                pairs.append((i, j))
            }
        }
    }
}
