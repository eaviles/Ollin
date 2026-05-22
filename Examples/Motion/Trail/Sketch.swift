import Foundation
import Ollin

/// A point traces a Lissajous figure (`cos`/`sin` on slightly different
/// frequencies), and the last 600 positions are kept in a `trail` and drawn as
/// a single connected `polyline`. A filled dot marks the live head.
///
/// The trail is just a `[Vector2]` the sketch owns: append the new point each
/// frame, drop the oldest once it passes 600.
@main
final class Trail: Sketch {
    var trail: [Vector2] = []

    override func draw() {
        background(.black)

        let head = Vector2(width / 2 + 300 * cos(time * 3),
                           height / 2 + 300 * sin(time * 3.7))
        trail.append(head)
        if trail.count > 600 { trail.removeFirst() }

        noFill()
        stroke(.white)
        polyline(trail)

        noStroke()
        fill(.white)
        circle(x: head.x, y: head.y, radius: 10)
    }
}
