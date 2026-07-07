// figure: frame=0
//
// Guide listing (Chapter 17): the first 3D sketch. One camera call, one
// sphere, and the auto-lit default does the shading.
import Ollin

final class FirstSphere: Sketch {
    override func draw() {
        background(Color(hex: 0x10141B))
        cameraShowcase(radius: 5)
        fill(Color(hex: 0xF25F5C))
        drawSphere(radius: 1)
    }
}
