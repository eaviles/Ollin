import Foundation
import Ollin

/// `@Eased` values glide toward whatever you assign them, a little each frame —
/// motion with no update step to call. Here four dots race the same flip on
/// their own curve, so the shapes pull apart as they travel.
///
/// The target flips every 1.5s between the two ends. Assigning the value it's
/// already heading for is a no-op, so setting the target every frame is fine —
/// only the flip restarts a tween. The curves diverge in flight: `.linear` holds
/// one speed, `.easeIn` lags then rushes, `.easeOut` leaps then settles,
/// `.easeInOut` eases at both ends.
@main
final class EasingCurves: Sketch {
    @Eased(duration: 1.2, curve: .linear)    var linearX = 0.0
    @Eased(duration: 1.2, curve: .easeIn)    var easeInX = 0.0
    @Eased(duration: 1.2, curve: .easeOut)   var easeOutX = 0.0
    @Eased(duration: 1.2, curve: .easeInOut) var easeInOutX = 0.0

    override func draw() {
        background(.white)

        // Flip the shared target between the track ends every 1.5 seconds.
        let goal = Int(time / 1.5) % 2 == 0 ? 0.85 : 0.15
        linearX = goal; easeInX = goal; easeOutX = goal; easeInOutX = goal

        let left = width * 0.14, right = width * 0.86
        let span = right - left
        let rows = [linearX, easeInX, easeOutX, easeInOutX]
        let dot = 26 * scale

        for (i, t) in rows.enumerated() {
            let y = height * (0.26 + Double(i) * 0.16)
            stroke(Color(white: 0.85)); strokeWeight(2 * scale)
            drawLine(left, y, right, y)
            noStroke(); fill(.black)
            drawCircle(left + span * t, y, dot)
        }
    }
}
