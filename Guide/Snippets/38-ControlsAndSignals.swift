// The names Chapter 38's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".
import OllinController
import OllinHaptics
import OllinMIDI
import OllinOSC

// The two hands the steps start, and the things a sketch of your own does
// when they move: a flash, a new shape per note, and a mark per reading.
let midi = MIDIInput()
let osc = OSCReceiver(port: 8000)
func flash() {}
func spawn(_ note: Int) {}
func mark(_ time: Date) {}

// The controller's ship and what it fires, and the ball that lands.
var ship = Vector2.zero
func fire(from position: Vector2) {}
struct Ball { var justLanded = false; var position = Vector2.zero }
var ball = Ball()

// The touch table, and the tide the counting fragment reads.
let surface = TUIOReceiver()
let tide = DataFeed("https://example.org/tide.json", every: 600)
