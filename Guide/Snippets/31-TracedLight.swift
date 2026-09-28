// The names Chapter 31's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

let ribbon = Mesh.plane(width: 4, depth: 0.4, segments: 40)
var lastPositions: [Vector3] = []

// The frame the defocus reads, and the line spray with its lines.
var scene: RenderTarget!
var spray: LineSpray!
let lines: [SprayLine] = []
