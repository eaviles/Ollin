// The names Chapter 39's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".
import OllinMIDI

// The parameters the keyframe and formula steps drive, by their kinds.
@Param(40...320) var radius = 190.0
@Param(3...13) var count = 8
@Param(2...20) var edge = 8.0
@Param var filled = true
@Param(x: 0...1080, y: 0...1080, width: 40...900, height: 40...900) var box = Rectangle(x: 100, y: 200, width: 620, height: 400)
@Param(x: 0...1080, y: 0...1080) var eye = Vector2(540, 540)

// The MIDI input of Chapter 35, the timecode clock read from it, and the
// timecode step's function of your own.
let midi = MIDIInput()
@MainActor let timecode = TimecodeClock(from: midi)
func flash() {}
