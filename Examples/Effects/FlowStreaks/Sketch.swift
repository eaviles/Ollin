import Ollin

/// **Line integral convolution** paints a direction field as brushed streaks.
/// Every pixel becomes the average of the picture along the streamline through
/// it, walked both ways, so fine grain turns into hair-thin strokes that follow
/// the field wherever it bends. The field is an `aside { }` layer, drawn only to
/// steer the streaks and never composited; `field:` says how its colors encode a
/// direction. Three readings, on a knob:
///
///   • **swirl**: a noise layer read as an **angle** (`.angle(turns:)`), the
///     classic flow-field look; `turns` winds the field tighter.
///   • **contours**: drifting soft blobs read along their **contour lines**
///     (`.contour`), so the streaks circle each blob like grain around a knot.
///   • **bump**: the blobs' normal map read as a **vector** field (`.vector`, the
///     reading `displace` makes), so the streaks radiate from every bump.
///
/// Try it: raise `length` until the picture melts into strokes, feed a photo in
/// as the base, or replace the aside with a `.normalMap` of any picture.
@main
final class FlowStreaks: Sketch {

    enum Field: String, CaseIterable, ParamOption { case swirl, contours, bump }

    @Param(icon: "wind", group: "Field") var field: Field = .swirl
    /// The streak from end to end, as a fraction of the canvas.
    @Param("Length", 0.01 ... 0.2, icon: "ruler", group: "Field") var length = 0.06
    /// How many turns the swirl's brightness sweeps through, black to white.
    @Param("Turns", 0.5 ... 4, icon: "arrow.triangle.2.circlepath", group: "Field") var turns = 2.0
    /// How much grain the streaks are made of.
    @Param("Grain", 0 ... 1, icon: "circle.dotted", group: "Base") var grain = 0.8

    override func draw() {
        background(Color(white: 0.05))

        compose {
            // The base: a gray sheet with three discs riding their orbits,
            // grained so the streaks have something to be made of.
            layer {
                background(Color(white: 0.5))
                noStroke()
                for i in 0 ..< 3 {
                    let t = time * 0.2 + Double(i) * .tau / 3
                    fill(Color(hue: Double(i) / 3 + 0.05, saturation: 0.75, brightness: 0.95))
                    drawCircle(width * 0.5 + cos(t) * width * 0.22,
                               height * 0.5 + sin(t * 1.3) * height * 0.22, 190)
                }
                fill(.white)
                drawCircle(width * 0.5, height * 0.5, 60)
            }
            .post(.grain(amount: grain))
            .streaked(along: steer(), length: length, field: encoding)
        }

        drawCaption("line integral convolution · \(field.rawValue) · the streaks follow the aside's field")
    }

    /// The aside that steers the streaks, one per field reading.
    private func steer() -> ComposeLayer {
        switch field {
        case .swirl:
            // A noise layer, drifting: the walk reads its gray as an angle.
            return aside {
                withState {
                    translate(width * 0.5, height * 0.5)
                    rotate(time * 0.05)
                    scale(1.4)
                    drawImage(generate(.noise(scale: 3)).image, -width * 0.5, -height * 0.5)
                }
            }
        case .contours, .bump:
            // Soft blobs on their own orbits: read along their contours, or as
            // the normals of the hills they make.
            let blobs = aside {
                background(.black)
                noStroke()
                fill(.white)
                for i in 0 ..< 4 {
                    let t = time * 0.3 + Double(i) * 1.7
                    drawCircle(width * 0.5 + cos(t * 0.9) * width * 0.3,
                               height * 0.5 + sin(t) * height * 0.3, 150)
                }
            }.post(.gaussianBlur(radius: 60))
            return field == .bump ? blobs.post(.normalMap(amount: 4)) : blobs
        }
    }

    private var encoding: Combine.FieldEncoding {
        switch field {
        case .swirl: return .angle(turns: turns)
        case .contours: return .contour
        case .bump: return .vector
        }
    }
}
