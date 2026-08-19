// figure: frame=930
//
// Guide sketch (Chapter 9): the steering recipe, run twice. Two chasers
// share one hopping lure and one top speed; only maxForce differs, so
// one snaps onto each new spot while the other sails past and swings back.
import Ollin

final class Chasers: Sketch {
    var positions = [Vector2(240, 880), Vector2(840, 880)]
    var velocities = [Vector2.zero, Vector2.zero]
    var trails: [[Vector2]] = [[], []]
    let forces = [2200.0, 320.0]        // how sharply each may turn
    let tints = [Color(hex: 0xF25C54), Color(hex: 0x4CC9F0)]
    let maxSpeed = 420.0

    override func draw() {
        background(Color(hex: 0x0E1116))

        let spots = [Vector2(250, 330), Vector2(830, 380), Vector2(620, 840)]
        var lure = spots[Int(time / 4) % spots.count]
        if mouseIsPressed { lure = Vector2(mouseX, mouseY) }

        for i in positions.indices {
            let desired = (lure - positions[i]).normalized * maxSpeed
            let steer = (desired - velocities[i]).limited(to: forces[i])
            velocities[i] = (velocities[i] + steer * deltaTime).limited(to: maxSpeed)
            positions[i] += velocities[i] * deltaTime

            trails[i].append(positions[i])
            if trails[i].count > 300 { trails[i].removeFirst() }

            noFill()
            stroke(tints[i].withAlpha(0.5))
            strokeWeight(2.5)
            drawPolyline(trails[i])
            noStroke()
            fill(tints[i])
            drawCircle(center: positions[i], radius: 13)
        }

        noStroke()
        fill(Color(white: 1, alpha: 0.8))
        drawCircle(center: lure, radius: 6)
    }
}
