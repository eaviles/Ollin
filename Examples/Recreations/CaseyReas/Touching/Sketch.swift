//  Recreation after Casey Reas - the "Process" works (2004-2010), where a short
//  text names a kind of element, gives it behaviors, and the picture is the
//  record of what a surface full of them did to each other. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist.
//  https://reas.com/process
//
//  An original Ollin interpretation. Nothing was ported, and the instruction
//  below is our own, written in the form Reas writes his in. The vocabulary
//  it is written with, an element being a form plus a list of behaviors, is
//  his.

import Ollin

/// **The instruction.**
///
/// > *Element 1.* A circle that moves in a straight line, stays on the
/// > surface, turns while it touches another element, and moves away from an
/// > element it overlaps.
/// >
/// > *The process.* A rectangular surface filled with instances of Element 1,
/// > each a different size. While two elements touch, draw a line between
/// > their centers. Set the value of the line from the distance between the
/// > centers: the shortest black, the longest white. Do not draw the
/// > elements.
///
/// That text is the work, and this file is one reading of it. Reas writes a
/// process in English first and calls the software that follows secondary to
/// it, which is the same claim LeWitt makes about a wall drawing and its
/// drafter. Two people given the paragraph above would write different
/// sketches, and both would be carrying it out.
///
/// What makes the picture is the last sentence. The elements are never drawn,
/// so nothing you see is a thing: every mark is a relation between two things
/// that are invisible, laid down at the moment it held and left there. A
/// circle crossing the surface leaves nothing at all until it meets another
/// one, and then leaves a fan of lines that thickens while they stay
/// together. The surface is the only record that any of it happened.
///
/// The value rule is what sorts that record out. A line's value is its own
/// length against the longest line two elements could ever draw, so small
/// elements, whose centers are close even when they are barely touching,
/// write dark, while the largest pair writes white on white and leaves the
/// surface alone. Size is not drawn either. It shows only as how dark a
/// meeting comes out.
///
/// Try it: `elements` is how many are on the surface and `smallest` and
/// `largest` bound their sizes, so narrowing the two together turns the whole
/// record dark or pale. `speed` is how fast they cross, `turn` how hard a
/// touch bends them, which is what gathers them into knots rather than
/// letting them pass through. `ink` and `lineWeight` are the pen. A press
/// wipes the surface and starts the next one, and so does changing anything
/// the elements are made of. `--export-svg` gives back the lines of a single
/// frame, every one of them a chord no longer than two of the largest
/// elements, with its gray exactly that length over that longest line.
@main
final class Touching: Sketch {
    @Param(10 ... 260, icon: "circle.grid.3x3") var elements = 100
    @Param(4 ... 60, icon: "smallcircle.filled.circle") var smallest = 14.0
    @Param(20 ... 180, icon: "circle.circle") var largest = 66.0
    @Param(2 ... 120, icon: "speedometer") var speed = 42.0
    @Param(0 ... 4, icon: "arrow.turn.right.up") var turn = 1.4
    @Param(0.01 ... 0.5, icon: "drop") var ink = 0.14
    @Param(0.2 ... 3, icon: "pencil.tip") var lineWeight = 0.7
    @Param(1 ... 999, icon: "dice") var firstSurface = 1

    /// The surface being drawn on. A press starts the next one.
    private var surface = 0
    /// What the elements were made of when they were placed. Changing any of
    /// it means a different set of elements, so the surface starts over.
    private var made = ""

    private var position: [Vector2] = []
    private var direction: [Vector2] = []
    private var radius: [Double] = []
    /// Which way each element turns while it is touching something. Reas's
    /// behavior says only that the direction changes, so the sign is one of
    /// the choices a reading has to make, and giving half of them each way
    /// keeps the surface from drifting into one long curl.
    private var chirality: [Double] = []

    /// How fast an element moves out of an overlap, as a share of the overlap
    /// a second. The behavior says an element moves away from one it
    /// overlaps, not that two may never overlap, and the difference is the
    /// whole tone of the picture: settle it in one frame and every line is
    /// drawn at the pale end of the value rule, since the centers are never
    /// nearer than just touching.
    private let separation = 2.2

    override func setup() {
        noClear()
        background(.white)
    }

    override func mousePressed() {
        surface += 1
        place()
    }

    override func draw() {
        let recipe = "\(elements) \(smallest) \(largest) \(firstSurface)"
        if recipe != made {
            made = recipe
            surface = firstSurface
            place()
        }
        move(by: min(deltaTime, 1.0 / 30))
        record()
    }

    /// Places the elements for a surface, and wipes what the last set drew.
    private func place() {
        randomSeed(surface)
        background(.white)
        let low = min(smallest, largest)
        let high = max(smallest, largest)
        position = []
        direction = []
        radius = []
        chirality = []
        for _ in 0 ..< elements {
            let size = random(low, high)
            let room = Rectangle(center: center,
                                 width: max(1, width - 2 * size),
                                 height: max(1, height - 2 * size))
            position.append(randomVector(in: room))
            direction.append(Vector2(1, 0).rotated(by: random(.tau)))
            radius.append(size)
            chirality.append(random() < 0.5 ? -1 : 1)
        }
    }

    /// One step of the four behaviors, in the order the instruction names
    /// them. Overlap moves an element where it stands; touching turns it.
    /// What each element carries is a *direction*, a unit vector put back to
    /// unit length after every turn, and `speed` multiplies it here, since
    /// the first behavior says the motion is a straight line at a constant
    /// rate rather than something that can be accelerated.
    private func move(by dt: Double) {
        for i in position.indices {
            position[i] += direction[i] * speed * dt
        }
        for i in position.indices {
            let size = radius[i]
            let here = position[i]
            var going = direction[i]
            if here.x < size, going.x < 0 { going = Vector2(-going.x, going.y) }
            if here.x > width - size, going.x > 0 { going = Vector2(-going.x, going.y) }
            if here.y < size, going.y < 0 { going = Vector2(going.x, -going.y) }
            if here.y > height - size, going.y > 0 { going = Vector2(going.x, -going.y) }
            direction[i] = going
        }
        for i in position.indices {
            for j in (i + 1) ..< position.count {
                let apart = position[j] - position[i]
                let distance = apart.length
                let touching = radius[i] + radius[j]
                guard distance < touching, distance > 0 else { continue }
                let away = apart / distance
                let overlap = touching - distance
                let step = overlap * 0.5 * min(1, separation * dt)
                position[i] -= away * step
                position[j] += away * step
                direction[i] = direction[i].rotated(by: chirality[i] * turn * dt).normalized
                direction[j] = direction[j].rotated(by: chirality[j] * turn * dt).normalized
            }
        }
    }

    /// The process itself: one line per touching pair, valued by how far apart
    /// the centers are against the longest such line there could be.
    private func record() {
        let longest = 2 * max(smallest, largest)
        strokeWeight(lineWeight)
        for i in position.indices {
            for j in (i + 1) ..< position.count {
                let distance = position[i].distance(to: position[j])
                guard distance < radius[i] + radius[j] else { continue }
                stroke(Color(white: min(1, distance / longest), alpha: ink))
                drawLine(position[i], position[j])
            }
        }
    }
}
