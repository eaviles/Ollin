import Ollin

/// Gabor noise as a generator: a noise whose spectrum is designed rather than
/// inherited. Every kernel is a small Gaussian blob carrying a cosine wave, so
/// the field has one principal `wavelength` and, when `spread` is small, one
/// direction: brushed metal, wood grain, silk, and rippled water at a turn of
/// the parameters. `bandwidth` is the width of the band around that wavelength;
/// low values run the waves long and let them interfere. The direction turns
/// half a circle each lap (a Gabor field at `angle + .pi` is the same field),
/// and the waves slide with a phase that is periodic over one lap, so the
/// whole thing loops without a seam:
///
/// ```sh
/// swift run Example-Effects-GaborNoise --export-loop /tmp/gabor.gif
/// ```
///
/// The dots are the CPU form of the same field, `GaborNoise(...).value(x, y)`,
/// read at a grid of points and sized by what they read: they sit on the crests
/// the GPU painted, which is what lets a sketch place marks by a field it never
/// reads back from the GPU.
@main
final class GaborNoise_Example: Sketch {
    private let period = 8.0
    override var loopDuration: Double? { period }

    @Param(4 ... 96, icon: "waveform.path") var wavelength = 28.0
    @Param(0.1 ... 2, icon: "slider.horizontal.below.rectangle") var bandwidth = 0.35
    @Param(0 ... Double.pi, icon: "arrow.triangle.branch") var spread = 0.25
    @Param(4 ... 64, icon: "circle.dotted") var impulses = 32
    @Param(icon: "circle.grid.3x3") var showsCrests = true

    override func draw() {
        let ink = Color(hex: 0xF2E8DC), paper = Color(hex: 0x14202B)
        background(paper)
        let lap = loopProgress(over: period)
        let angle = lap * .pi
        let phase = lap * .tau
        let field = generate(.gaborNoise(wavelength: wavelength, bandwidth: bandwidth,
                                         angle: angle, spread: spread, impulses: impulses,
                                         phase: phase, seed: 7,
                                         foreground: ink, background: paper))
        drawImage(field.image, 0, 0)

        guard showsCrests else { return }
        let noise = GaborNoise(wavelength: wavelength, bandwidth: bandwidth, angle: angle,
                               spread: spread, impulses: impulses, phase: phase, seed: 7)
        noStroke()
        fill(Color(hex: 0xE85D75))
        let step = 24.0
        for y in stride(from: step / 2, to: height, by: step) {
            for x in stride(from: step / 2, to: width, by: step) {
                let crest = noise.value(x, y) - 0.62
                if crest > 0 { drawCircle(x, y, crest * 30) }
            }
        }
    }
}
