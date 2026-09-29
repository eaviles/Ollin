// The names Chapter 40's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".
import OllinAudio
import OllinMIDI

// The synth every fragment plays, the clock and counter the steps run on,
// and the step and scale degree a fragment reads.
@MainActor let synth = Synth(.pluck)
let tempo: Tempo = 120
var counter = StepCounter(perBeat: 4)
let step = 0
let degree = 0

// The rhythm of the rhythm step, which the swing step reads at each step.
let rhythm = Rhythm(5, in: 16)

// The scale of the pitch step, played by the fragments after it, and the
// major scale of the chord step, which a progression reads.
let pentatonic = Scale(.minorPentatonic, root: "A3")
let major = Scale(.major, root: "C3")

// The drum pattern of the sequencer step, and the MIDI input the arpeggiator
// follows, as in Chapter 38.
var drums: StepSequencer = "36 . . 36 . . 36 . 38 . . 36 . 38 . ."
let midi = MIDIInput()

// The two synths the progression plays, a pad for the chords and a bass,
// which the MIDI file step writes as two tracks.
@MainActor let pad = Synth(.pad)
@MainActor let bass = Synth(.pluck)

// The table of temperatures the sonification reads, what it reads out, and
// the second synth that sounds the reference note.
let table = try! Table(text: "temperature\n18\n21\n24\n19")
let readings = Sonification(table, column: "temperature",
                            in: Scale(.minorPentatonic, root: "A3"))
@MainActor let marker = Synth(.bell)

// A package gives a sketch its own resource bundle; the probe is not one.
extension Bundle { static var module: Bundle { .main } }
