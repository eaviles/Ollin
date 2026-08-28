import Ollin

/// **Light in a flat sketch**: a room, a lamp you carry with the pointer, and light
/// that works out for itself where it can go.
///
/// Two layers go in and one comes out. The **scene** is what light meets: whatever is
/// drawn there is solid, and its alpha is how much of a ray it stops. The **lamps**
/// layer is what gives light off. `.light()` hands back the light arriving at every
/// pixel, which is the picture.
///
/// Nothing here draws a shadow or a falloff. They come out of the measurement:
///
/// - a shadow is **sharp where it meets the shape and soft further away**, because a
///   pixel far from an edge sees more of the lamp than a pixel beside it;
/// - a small lamp **falls off with distance**, because it covers less and less of the
///   circle of directions a pixel can look along;
/// - a lit wall **gives its own color back**, so the red block reddens the floor beside
///   it and the green wall greens the room. That is the `bounces` knob; at 0 every
///   surface stays black and only the lamps are seen.
///
/// Try it: turn `bounces` to 0 and back to watch the room lose and regain its color,
/// pull `reach` down until the far corners fall dark, or open `sky` a little so the
/// room reads as one with a window in it.
@main
final class Light_Example: Sketch {

    enum View: String, CaseIterable, ParamOption { case light, scene }

    @Param(style: .segmented, icon: "sun.max") var view: View = .light
    @Param(0.2 ... 12, icon: "light.max") var brightness = 5.0
    @Param(0 ... 3, icon: "arrow.triangle.2.circlepath") var bounces = 1
    @Param(120 ... 1600, icon: "arrow.left.and.right") var reach = 1600.0
    @Param(icon: "cloud.sun") var sky = Color(white: 0.02)

    let walls = Color(hex: 0x2B3138)
    let inks = [Color(hex: 0xC8503C), Color(hex: 0x3F8F6B), Color(hex: 0xD9A441),
                Color(hex: 0x4C6FB0)]

    /// Where the carried lamp is. Before the pointer has been anywhere it stands in
    /// the lower half of the room, so the room is lit the moment the sketch opens.
    var pointer: Vector2 {
        mouseX == 0 && mouseY == 0 ? Vector2(380, 700) : Vector2(mouseX, mouseY)
    }

    override func draw() {
        background(.black)

        // What the light meets. The layer starts empty, and empty is where light
        // travels: only what is drawn here stops a ray.
        let scene = renderTarget()
        withTarget(scene) {
            noStroke()
            fill(walls)
            drawRect(90, 90, 900, 26)                     // the four walls of the room
            drawRect(90, 964, 900, 26)
            drawRect(90, 90, 26, 900)
            drawRect(964, 90, 26, 900)

            fill(inks[1])                                 // one wall in a strong color,
            drawRect(116, 300, 26, 480)                   // so the bounce is easy to see
            fill(inks[3])
            drawRect(848, 300, 26, 480)

            fill(inks[0])
            drawRect(260, 800, 320, 30)
            fill(inks[2])
            drawCircle(720, 830, 66)

            // A comb, to be read through: the gaps between its teeth cut the light
            // into beams without anything drawing a beam.
            fill(walls)
            for i in 0 ..< 8 {
                drawRect(230 + Double(i) * 78, 470, 26, 120)
            }
        }

        // What gives light off. One lamp follows the pointer; the other drifts along
        // the top of the room, so the light keeps moving when nobody touches it.
        let lamps = renderTarget()
        withTarget(lamps) {
            noStroke()
            fill(.white)
            drawCircle(pointer.x, pointer.y, 16)
            fill(inks[2])
            drawCircle(540 + cos(time * 0.4) * 320, 240 + sin(time * 0.53) * 60, 12)
        }

        if view == .scene {
            drawImage(scene.image, 0, 0)
            return
        }

        let lit = scene.combined(with: lamps, .light(reach: reach, brightness: brightness,
                                                     bounces: bounces, sky: sky))
        drawImage(lit.image, 0, 0)
    }
}
