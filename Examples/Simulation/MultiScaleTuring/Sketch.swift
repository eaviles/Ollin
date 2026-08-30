import Ollin

/// **Multi-scale Turing patterns**, McCabe's elaboration of Turing's morphogenesis
/// model, on the GPU through the effects substrate. A `SimField` running
/// `.multiScaleTuring()` holds one substance; every step each pixel compares the
/// field's average over a small disc against its average over a larger one, at each
/// of five magnifications at once, and lets only the magnification whose two averages
/// agree most closely move it. Broad lobes and fine stippling settle into the same
/// picture, and the result reads like an electron micrograph of a diatom.
///
/// The field starts as noise and organizes itself, so nothing seeds it. Drag to
/// disturb the pattern and watch it heal. Turn `symmetry` up to fold every scale
/// around the center into a rosette.
@main
final class MultiScaleTuring_Example: Sketch {

    @Param(0 ... 12, icon: "circle.hexagongrid", group: "Form") var symmetry = 0
    @Param(icon: "paintpalette", group: "Look") var relief = true

    private var field: SimField!

    override func setup() {
        field = makeSimField(.multiScaleTuring(seed: Double(variation)), scale: 0.5)
    }

    override func draw() {
        background(.black)
        // Retuning the rule live keeps the evolved field and reshapes it from here on.
        field.sim = .multiScaleTuring(scales: symmetry < 2 ? .ladder : .rosette(symmetry),
                                      seed: Double(variation))

        withField(field) {
            noStroke()
            if mouseIsPressed {
                fill(Color(white: keyIsPressed ? 0 : 1, alpha: 0.9))
                drawCircle(mouseX, mouseY, 60)
            }
        }
        // The field is grayscale, so it takes either a color ramp or relief shading.
        // The lit-from-above look is an accident of a flat 2D rule, and it reads as depth.
        let shaded = relief ? field.filtered(.relight(height: 0.35))
                            : field.filtered(.gradientMap(.magma))
        drawImage(shaded.image, 0, 0)
        drawCaption("Multi-scale Turing · five scales competing per pixel · drag to disturb, hold a key to darken")
    }
}
