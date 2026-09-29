// The names Chapter 45's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

// The chapter's MQTT section declares its own client; the import is here so the
// satellite is linked into the probe that compiles the block.
import OllinMQTT
import OllinRoom

// The checkpoint's tile, the struct of yours the prose says is marked Codable.
struct Tile: Codable { var cell: Int; var color: Color }

// A point of your world in desk coordinates, for the windows that share a desk.
var worldPoint = Vector2(0, 0)

// The room the seats and messages read, the bird a sketch sends through it, and
// the drawing as wide as the wall.
@MainActor let room = Room(named: "wall", seat: 0)
var position = Vector2(0, 0)
func drawWall(across width: Double) {}
