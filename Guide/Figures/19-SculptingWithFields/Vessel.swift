// figure: frame=0
//
// Guide listing (Chapter 19): the sculpt block. A form built top to bottom
// like working clay: add the body and a lip, carve the hollow, then add a
// crisp handle with the melt turned nearly off.
import Ollin

final class Vessel: Sketch {
    override func draw() {
        background(Color(hex: 0x12100E))
        camera(.orbiting(target: Vector3(0, 0.35, 0), radius: 5,
                         azimuth: 0.4, elevation: 0.28, fieldOfView: .pi / 4))
        lightingPreset(.studio)
        material(.clay)

        sculpt {
            blend(0.3)                 // melt amount for what follows
            fill(Color(hex: 0xD96F4E))
            drawSphere(radius: 1.0)                                        // the body
            withState { translate(0, 0.95, 0)
                        drawTorus(radius: 0.5, tube: 0.16) }               // a lip melts on
            carve()                    // now shapes cut away
            withState { translate(0, 1.1, 0); drawSphere(radius: 0.52) }   // the hollow
            add(); blend(0.05)         // back to adding, nearly hard
            withState { translate(0, 0.35, 1.05); rotateX(.pi / 2)
                        drawTorus(radius: 0.34, tube: 0.09) }              // a handle
        }
    }
}
