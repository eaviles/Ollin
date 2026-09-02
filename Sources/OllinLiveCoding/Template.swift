import Foundation

/// The starter buffer for a new, untitled performance: a short motion-by-default
/// sketch with one tunable parameter, so the first ⌘↩ already moves and the
/// inspector already has a slider. Kept tiny on purpose; it's a stage to type
/// over, not a showcase.
enum SketchTemplate {
    static let source = """
    import Ollin

    final class Live: Sketch {
        @Param(0...4) var speed = 1.0

        override func draw() {
            background(Color(hex: 0x101018))
            noFill()
            stroke(.white)
            strokeWeight(2.5 * scale)
            for i in 0..<6 {
                let t = Double(i) / 6
                let r = (90 + t * 240 + sin(time * speed + t * .tau) * 36) * scale
                drawCircle(width / 2, height / 2, r)
            }
        }
    }
    """
}
