// The names Chapter 36's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".
import OllinPhone

// The phone, and the rectangle a frame landed in.
@MainActor let device = PhoneDevice()
let rect = Rectangle(x: 0, y: 0, width: 1080, height: 810)
var dust: [Vector2] = []

// The wand's balls, what it aimed at and holds, and its last press count.
@MainActor let wand = device.latestWand!
let balls = [Vector3(-0.5, 1.46, -1.42), Vector3(0.02, 1.3, -1.5)]
var aimed: (index: Int, distance: Double)? = nil
var held: Int?
var lastPressCount = 0

// The marks the sounds and taps leave, the glass on the canvas, and the lift.
struct Ring { var at: Vector2; var born: Double }
var rings: [Ring] = []
func place(for label: String) -> Vector2 { .zero }
let pad = Rectangle(x: 48, y: 44, width: 210, height: 396)
var lift = 0.0
