// The names Chapter 26's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

let ball = Mesh.icosphere(radius: 1, subdivisions: 1)
let knot = Mesh.torusKnot(radius: 0.62, tube: 0.2, segments: 220, sides: 14)
let anchor = Vector3(0, 1, -2)
let letters = Mesh.textGlyphs("Ollin", size: 1.5, depth: 0.3)
