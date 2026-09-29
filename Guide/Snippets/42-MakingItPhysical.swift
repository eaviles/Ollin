// The names Chapter 42's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

// The sketch the file writers are handed, and an instance of it.
final class MySketch: Sketch {}
@MainActor let sketch = MySketch()

// The soft proof the gamut check reads, and the picture it checks.
let press = SoftProof(.genericCMYK)
@MainActor let artwork = Image(width: 64, height: 64, color: .white)

// The 3D work: the meshes a line drawing reads, a mesh to print, and a scene
// to write as a model.
let sculpture = Mesh.torusKnot(radius: 0.62, tube: 0.2, segments: 220, sides: 14)
let meshes = [sculpture]
let scene = Scene()
