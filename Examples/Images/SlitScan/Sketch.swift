import Ollin

/// Time smeared across space: slit-scan over a painted feed.
///
/// A `SlitScan` holds a rolling history of frames and rebuilds the image with
/// every pixel read from a different moment, chosen by a delay: here the
/// default is the classic scan (the left edge is now, the right edge is the
/// oldest frame held), and holding the mouse switches to a radial delay, so
/// time ripples outward from the center. A bouncing ball becomes an arcing
/// smear; the straight color bands shear into curves.
///
/// The source is painted small every frame (the sketch carries no asset) and
/// shown in the corner. The same two calls work on a video or camera frame:
/// push each new frame, then ask for the displaced image.
@main
final class SlitScan: Sketch {
    // The sketch class takes the technique's name, so the framework type is
    // reached through the module.
    private let history = Ollin.SlitScan(capacity: 90)
    private let source = Image(width: 256, height: 256, color: .black)

    override func draw() {
        paint()
        history.append(source)

        background(.black)
        let warped = mouseIsPressed
            ? history.image(delay: { uv in dist(uv.x, uv.y, 0.5, 0.5) / 0.71 })
            : history.image(delay: { uv in uv.x })
        if let warped {
            drawImage(warped, in: canvasRectangle)
        }

        // The live feed, inset in the corner.
        let inset = Rectangle(x: width - 236, y: height - 236, width: 200, height: 200)
        drawImage(source, in: inset)
        noFill()
        stroke(.white)
        strokeWeight(2 * scale)
        drawRect(inset)

        drawCaption("left is now, right is a second ago; hold the mouse for radial time")
    }

    /// The feed the history records: color bands drifting up while a bright
    /// ball swings on a lissajous orbit.
    private func paint() {
        let n = source.width
        // A slow drift across, a fast bounce up and down: the classic recipe
        // for the scan, which stretches slow horizontal motion into a long
        // ribbon while the fast vertical swing ripples along it.
        let ballX = 0.5 + 0.42 * sin(time * 0.55)
        let ballY = 0.5 + 0.32 * sin(time * 4.5 + 1.2)
        for y in 0 ..< n {
            let v = (Double(y) + 0.5) / Double(n)
            for x in 0 ..< n {
                let u = (Double(x) + 0.5) / Double(n)
                // Drifting hue bands.
                let band = fract(v * 3 - time * 0.6)
                var color = Color(hue: fract(0.55 + band * 0.25),
                                  saturation: 0.55, brightness: 0.5)
                // The ball, with a soft rim.
                let d = dist(u, v, ballX, ballY)
                if d < 0.11 {
                    color = Color.mix(.white, color, smoothstep(0.07, 0.11, d))
                }
                source[x, y] = color
            }
        }
    }
}
