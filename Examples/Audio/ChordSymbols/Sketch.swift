import Ollin
import OllinAudio

/// Chords written the way chords are written on paper.
///
/// A `Chord` reads its own symbol (`"Dm7"`, `"F#maj7"`, `"C/G"`), and a
/// `Progression(symbols:)` strings them into changes, so a chart copied off a
/// page arrives as itself. The sibling `Changes` example writes a progression
/// as scale degrees instead, the form that survives a change of key; symbols
/// carry their own qualities, which is the form for chords that do not all
/// come from one key. This sketch is the symbol path.
///
/// The chart is a text parameter: type any symbols into it and they play. Each card
/// is one token, the lit card is the chord sounding, and the stack below it is
/// that chord spelled out as the pitches `Chord` actually hands back, lowest
/// first. A slash chord shows its work: the named bass turns the stack until
/// that note is at the bottom. A token that is not a chord goes dim and is
/// skipped, because `Chord(symbol:)` answers nil rather than guessing.
///
/// Keys `1` to `4` load charts worth hearing: a turnaround, a ii V I, a line
/// with a slash bass walking under it, and falling fifths that pass through
/// keys no single scale holds, which is the case degrees cannot write.
@main
final class ChordSymbols: Sketch {

    @Param(icon: "text.quote", group: "Chart") var chart = "Cmaj7 Am7 Dm7 G7"
    @Param(40 ... 120, icon: "metronome", group: "Playing") var tempo = 66.0

    static let charts = [
        "Cmaj7 Am7 Dm7 G7",
        "Dm7 G7 Cmaj7 Cmaj7",
        "C C7 F Fm C/G G7 C C",
        "Am7 D7 Gmaj7 Cmaj7 F#m7b5 B7 Em7 Em7",
    ]

    let pad = Synth(.pad, polyphony: 16)
    let bass = Synth(.bass, polyphony: 4)

    /// One token of the chart, kept beside what it parsed to, so the cards
    /// line up with the sound and a typo stays visible.
    struct Card {
        let text: String
        let chord: Chord?
    }
    var cards: [Card] = []
    var changes = Progression(symbols: "C")
    var counter = StepCounter(perBeat: 0.5)
    var sounding = 0
    var lit: [Double] = []
    var built = ""

    override func setup() {
        pad.gain = 0.34
        pad.reverb = Reverb(.hall, mix: 0.3)
        bass.gain = 0.42
        rebuild()
    }

    private var recipe: String { chart }

    private func rebuild() {
        // The same split the symbols initializer makes, kept by hand so every
        // token gets a card, the unreadable ones included.
        cards = chart
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "|" })
            .map { Card(text: String($0), chord: Chord(symbol: String($0))) }
        changes = Progression(cards.compactMap(\.chord))
        lit = [Double](repeating: 0, count: max(1, changes.count))
        sounding = 0
        built = recipe
    }

    override func draw() {
        background(Color(hex: 0x0B0E14))
        if built != recipe { rebuild() }

        for step in counter.steps(upTo: time * tempo / 60) {
            let index = step % max(1, changes.count)
            sounding = index
            if index < lit.count { lit[index] = 1 }
            pad.play(chord: changes.pitches(at: index), velocity: 0.5, for: 2 * 60 / tempo * 1.9)
            bass.play(changes.root(at: index).transposed(by: -12),
                      velocity: 0.8, for: 2 * 60 / tempo * 1.7)
        }

        drawChart()
        drawStack()
        drawCaption("A chart as text: every card is one symbol, and the lit one is sounding.",
                    edge: .top)
        drawCaption("Type your own chart into the chart parameter; keys 1 to 4 load ones worth hearing.")
    }

    private func drawChart() {
        let perRow = 8
        let slot = width * 0.9 / Double(min(perRow, max(1, cards.count)))
        let cardWidth = min(slot * 0.86, 150 * scale)
        let top = height * 0.18

        var playIndex = 0
        for (index, card) in cards.enumerated() {
            let row = index / perRow
            let inRow = index % perRow
            let rowCount = min(perRow, cards.count - row * perRow)
            let x = width / 2 + (Double(inRow) - Double(rowCount - 1) / 2) * slot
            let y = top + Double(row) * 84 * scale
            let center = Vector2(x, y)

            if card.chord == nil {
                // A token that did not read: dim, struck, and never played.
                noStroke()
                fill(Color(hex: 0x5A2A26).withAlpha(0.5))
                drawRect(center: center, width: cardWidth, height: 58 * scale)
                fill(Color(white: 0.45))
                textSize(20 * scale)
                textAlign(.center, .middle)
                drawText(card.text, at: center)
                stroke(Color(white: 0.45))
                strokeWeight(2 * scale)
                drawLine(x - cardWidth * 0.32, y, x + cardWidth * 0.32, y)
                continue
            }

            if playIndex < lit.count { lit[playIndex] *= pow(0.1, deltaTime) }
            let glow = playIndex == sounding ? 1.0 : lit[min(playIndex, lit.count - 1)]
            noStroke()
            fill(Colormap.magma.color(at: 0.2 + 0.5 * Double(playIndex)
                                      / Double(max(1, changes.count)))
                .withAlpha(0.15 + glow * 0.55))
            drawRect(center: center, width: cardWidth, height: 58 * scale)
            fill(Color(white: 0.5 + glow * 0.45))
            textSize(23 * scale)
            textAlign(.center, .middle)
            drawText(card.text, at: center)
            playIndex += 1
        }
    }

    private func drawStack() {
        guard let chord = changes.chord(at: sounding) else { return }
        let pitches = changes.pitches(at: sounding)
        let middleX = width / 2
        let base = height * 0.76
        let spread = height * 0.28

        // The chord spelled out, lowest first, each note a bar at its height.
        for pitch in pitches {
            let lift = (pitch.midi - 43) / 40
            let y = base - lift * spread
            let wide = (150 - lift * 40) * scale
            noStroke()
            fill(Colormap.magma.color(at: 0.3 + lift * 0.5).withAlpha(0.85))
            drawRect(center: Vector2(middleX, y), width: wide, height: 16 * scale)
            fill(Color(white: 0.65))
            textSize(15 * scale)
            textAlign(.left, .middle)
            drawText("\(pitch)", at: Vector2(middleX + wide / 2 + 14 * scale, y))
        }

        // What the symbol resolved to, said in the type's own words.
        noStroke()
        fill(Color(white: 0.85))
        textSize(24 * scale)
        textAlign(.center)
        let inversion = chord.inversion == 0 ? "" : ", inversion \(chord.inversion)"
        drawText("\(chord.root) \(chord.quality)\(inversion)",
                 at: Vector2(middleX, base + 52 * scale))
    }

    override func keyPressed() {
        guard let key, let index = key.wholeNumberValue,
              (1 ... Self.charts.count).contains(index) else { return }
        chart = Self.charts[index - 1]
    }
}
