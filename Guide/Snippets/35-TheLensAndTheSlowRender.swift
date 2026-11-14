// The names Chapter 35's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

// The frame the defocus reads, and the line spray with its lines.
var scene: RenderTarget!
var spray: LineSpray!
let lines: [SprayLine] = []

// The camera the traced-lens fragment adds two lines to.
var lens = Camera3D(eye: Vector3(0, 1, 5), target: .zero)
