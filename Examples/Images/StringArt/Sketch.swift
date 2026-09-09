import Ollin
import OllinSamplePhotos

/// String art: a profile knitted out of one continuous thread.
///
/// `StringArt` rings the canvas with 200 pins and winds a single thread
/// between them, chord after chord, each one chosen greedily for the
/// darkness it still covers. Dark regions collect many crossings, light
/// regions few, and the straight lines add up to a shaded picture. The
/// canvas never clears (`noClear()`): every frame winds a few more chords
/// onto the accumulation, so the face knits itself over the first seconds.
///
/// The winding is deterministic (no seed involved), and `art.thread` holds
/// the whole piece so far as one open polyline: draw it with `drawPolyline`
/// in a clearing sketch and the vector exports write a single continuous
/// line, exactly the thing a pen plotter loves most.
///
/// The picture is one of the bundled sample photographs, a woman in profile
/// on a plain ground: bold tonal masses, which is what the technique reads
/// best, since every chord crosses the whole disk.
@main
final class StringArt: Sketch {
    private var art: Ollin.StringArt!

    override func setup() {
        noClear()
        let picture = SamplePhoto.profile.load().resized(width: 340, height: 340)
        art = Ollin.StringArt(of: picture, center: center,
                              radius: 470, pins: 200, chords: 3200, ink: 0.08)
    }

    override func draw() {
        if frameCount == 1 {
            background(Color(hex: 0xF6F1E7))
            noStroke()
            fill(Color(hex: 0x3A3C46))
            for pin in art.pins { drawCircle(center: pin, radius: 2.4) }
        }

        noFill()
        stroke(Color(hex: 0x20222B).withAlpha(0.35))
        strokeWeight(1.0)
        for chord in art.step(8) {
            drawLine(chord.from, chord.to)
        }

        // The caption stays word-for-word stable: the canvas never clears,
        // so changing text would smear over itself.
        drawCaption("one continuous thread over 200 pins")
    }
}
