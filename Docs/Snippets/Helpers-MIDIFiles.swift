// The names the MIDI files page's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

import Foundation
import Ollin
import OllinAudio

// The piece the page keeps reading from, once the opening listing has read it.
var song = MIDIFile([])

// Where a file is being read from or written to, and the bytes of one that
// arrived some other way.
let path = "piece.mid"
let bytes = Data()

// The pattern the writing section takes its notes from, and the two parts the
// long form builds its tracks out of.
var sequencer = StepSequencer(count: 16)
let chords: [ScheduledNote] = []
let melody: [ScheduledNote] = []
