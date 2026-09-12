// The names Chapter 3's prose establishes around its fragments, so the blocks
// that read them can be compiled. See Guide/AUTHORING.md, "The code in the prose".

// "Add a dot every two seconds", from the section on beats.
var dots: [Vector2] = []
var revealed = false

// "Step a simulation every tenth frame": the prose names a simulation without
// building one, so this stands in for whatever the reader has. It is not
// called `grid`, because `Sketch.grid(columns:rows:)` already is.
struct SnippetSim { func step() {} }
let sim = SnippetSim()
