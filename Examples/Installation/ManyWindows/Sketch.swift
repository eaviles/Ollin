import Foundation
import Ollin

/// One world, seen through as many windows as you open.
///
/// Run it more than once. Each run opens its own window, and every window looks
/// into the same world, so a dot drifts out of one and into the next with the
/// desk in between:
///
///     swift run --package-path Examples Example-Installation-ManyWindows &
///     swift run --package-path Examples Example-Installation-ManyWindows &
///     swift run --package-path Examples Example-Installation-ManyWindows &
///
/// Then drag the windows apart, and resize them. The world stays where it is:
/// each window is a hole cut in the desk rather than a picture of its own.
///
/// Two things make that work, and neither is a trick.
///
/// `canvasOnScreen` says where this canvas sits on the desk, measured the way
/// the canvas is measured, so every window describes the same desk in the same
/// numbers. The drawing then happens in desk coordinates and is moved into this
/// canvas at the last moment.
///
/// The other is that nothing here talks to anything. The windows are separate
/// programs and they never exchange a word. Instead the whole world is a
/// function of the time of day, which they all read the same, so they cannot
/// disagree. That is the cheapest way to keep several screens in step, and it
/// is worth reaching for before anything with a network in it.
///
/// See `Docs/Output/Installation.md`.
@main
final class ManyWindows: Sketch {

    override var canvasSize: CanvasSize { .size(760, 520) }
    override var windowMode: WindowMode { .resizable }

    /// The moment every window agrees on. A sketch's own clock starts when that
    /// sketch starts, and these are started one after another, so the motion
    /// reads the clock the machine keeps instead. Subtracting a fixed moment
    /// keeps the number small enough to stay smooth.
    private var sharedTime: Double { Date().timeIntervalSince1970 - 1_700_000_000 }

    private let colors = [Color(red: 0.93, green: 0.24, blue: 0.14),
                          Color(red: 0.10, green: 0.44, blue: 0.90),
                          Color(red: 0.98, green: 0.78, blue: 0.10),
                          Color(white: 0.97)]

    private let count = 260

    override func draw() {
        // Off the desk (an export, a still) there is no window and no screen,
        // so the piece is its own world on its own clock, and the frame comes
        // out the same every time it is rendered.
        let world = screenFrame ?? Rectangle(x: 0, y: 0, width: width, height: height)
        let mine = canvasOnScreen ?? world
        let now = canvasOnScreen == nil ? time : sharedTime

        // A window can be showing the canvas at less than its own size, so a
        // length on the desk becomes a length here through one number.
        let scale = width / mine.width
        func here(_ point: Vector2) -> Vector2 {
            (point - Vector2(mine.x, mine.y)) * scale
        }

        background(Color(white: 0.06))

        // Rings around the middle of the desk. Each window holds a piece of
        // one, and the pieces line up across the gaps between the windows.
        noFill()
        stroke(Color(white: 0.17))
        strokeWeight(2)
        for ring in 1...7 {
            let radius = Double(ring) * world.height * 0.085
                + sin(now * 0.15 + Double(ring) * 0.7) * 14
            drawCircle(center: here(world.center), radius: radius * scale)
        }

        for dot in 0..<count {
            let speed = 10 + steady(dot, 1) * 26                  // points a second
            let heading = steady(dot, 2) * .tau
            let gone = Vector2(steady(dot, 3) * world.width, steady(dot, 4) * world.height)
                + Vector2(cos(heading), sin(heading)) * (speed * now)
            // The desk wraps at its edges, so a dot that leaves one side comes
            // back at the other rather than being gone for good.
            let place = Vector2(world.x + wrapped(gone.x, world.width),
                                world.y + wrapped(gone.y, world.height))

            let size = (4 + steady(dot, 5) * 26) * scale
            let ink = colors[dot % colors.count]
            if steady(dot, 6) < 0.35 {
                noFill()
                stroke(ink)
                strokeWeight(max(1.5, size * 0.22))
                drawCircle(center: here(place), radius: size)
            } else {
                noStroke()
                fill(ink)
                drawCircle(center: here(place), radius: size)
            }
        }
    }

    /// A length brought back inside the desk, so a dot that walks off one edge
    /// arrives at the opposite one.
    private func wrapped(_ measure: Double, _ length: Double) -> Double {
        let inside = measure.truncatingRemainder(dividingBy: length)
        return inside < 0 ? inside + length : inside
    }

    /// A steady number between 0 and 1 for one dot, different for each `salt`.
    /// Read from the dot's own number rather than drawn from `random()`, so
    /// every window agrees about every dot without anybody having to say so.
    private func steady(_ index: Int, _ salt: Int) -> Double {
        var bits = UInt64(truncatingIfNeeded: index &* 374_761_393 &+ salt &* 668_265_263)
        bits ^= bits >> 31
        bits = bits &* 0x9E37_79B9_7F4A_7C15
        bits ^= bits >> 29
        return Double(bits % 100_000) / 100_000
    }
}
