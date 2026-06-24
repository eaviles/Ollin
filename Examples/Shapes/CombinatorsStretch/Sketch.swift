import Ollin

// Per-axis sizing of a 2D SDF field. `stretched` inserts straight space along an axis (a circle
// becomes a stadium) and stays an exact distance field, so a smooth union blends evenly.
// `scaled(x:y:)` is a true non-uniform scale (a circle becomes an ellipse), but only a
// conservative bound, which is why `stretched` is the preferred per-axis tool. Left: two stretched
// circles smooth-union into a clean cross; right: a circle scaled into an ellipse, with a bead.
@main
final class CombinatorsStretch: Sketch {
    override func draw() {
        background(Color(white: 0.07))
        noStroke()
        let t = time
        let a = 70 + (sin(t) * 0.5 + 0.5) * 80

        // Stretch (exact): a vertical and a horizontal stadium (circles elongated) smooth-union
        // into a clean plus — the exact SDF keeps the blend fillet even.
        let cross = SDF.circle(radius: 52).stretched(y: a).colored(Color(hex: 0x4cc9f0))
            .smoothUnion(SDF.circle(radius: 52).stretched(x: a).colored(Color(hex: 0xff5d8f)), k: 46)
        withState { translate(width * 0.3, height * 0.5); drawSDF(cross) }

        // Non-uniform scale (bound): a circle scaled into an ellipse, smooth-unioned with a bead.
        let ell = SDF.circle(radius: 95).scaled(x: 1.0 + a / 160, y: 0.55).colored(Color(hex: 0xffd166))
            .smoothUnion(SDF.circle(radius: 38).at(x: 130, y: 0).colored(Color(hex: 0x8ac926)), k: 44)
        withState { translate(width * 0.72, height * 0.5); rotate(t * 0.2); drawSDF(ell) }

        drawCaption("Per-axis SDF sizing: stretched (exact, left) vs scaled x/y (bound, right)")
    }
}
