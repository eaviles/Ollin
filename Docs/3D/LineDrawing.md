#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Line drawing`</sup>

---

## Line drawing: a scene as line work a machine can follow

The renderer draws a picture. A picture is pixels, and a pen is not. `lineDrawing(of:)` takes the same meshes and the same camera and gives back **2D paths** instead: the lines a draughtsman would draw, with everything the surfaces hide taken out.

```swift
camera(Camera3D(eye: Vector3(5, 4, 6), target: .zero))
stroke(.black)
noFill()
for line in lineDrawing(of: [.box(size: 2)]) {
    drawPolyline(line.points, closed: line.isClosed)
}
```

What comes back is ordinary line work in canvas points, so everything that works on a path works on these: a stroke weight, a [brush](../Drawing/Marks.md), a wobble, a clip. And because they are paths rather than pixels, they reach the machines: [SVG and PDF](../Output/Export.md), [G-code](../Output/GCode.md) for a pen plotter or a mill, [DXF](../Output/DXF.md) for a laser cutter's own software. A lit mesh reaches none of those, because a vector file has nowhere to put a shaded surface.

### Contents

- [Which lines are drawn](#which) - silhouette, crease, boundary
- [Placing several things](#placing) - one call, so they occlude each other
- [Plotting it](#plotting)
- [What it costs](#cost) - `spacing`, and what to expect
- [How it works](#how)
- [Notes](#notes)

<a id="which"></a>
### Which lines are drawn

Three kinds, and between them they are what makes a drawing rather than a wireframe.

- The **silhouette**, where a surface turns away from the camera. This is the outline of a ball, of a cylinder, of a head.
- A **crease**, where two faces meet at more than `creaseAngle`. This is the edge of a cube, the rim of a cylinder's cap, the fold in a piece of geometry.
- A **boundary**, where a surface simply ends: the border of a plane, the open edge of a mesh that is not closed.

Everything else, which is the tessellation inside a smooth surface, is left out.

```swift
lineDrawing(of: mesh, creaseAngle: .pi / 6)   // the default: 30 degrees
lineDrawing(of: mesh, creaseAngle: 0.2)       // finds gentler ridges too
lineDrawing(of: mesh, creaseAngle: 0)         // every edge: a wireframe, not a drawing
```

`creaseAngle` is the one dial worth turning. A sphere at the default is its outline alone. Lower it and the tessellation starts to show, which is usually a mistake and occasionally the point.

<a id="placing"></a>
### Placing several things

Everything handed to one call hides everything else in it. That is why it takes an array rather than one mesh at a time:

```swift
let scene: [Mesh] = [
    .box(width: 6, height: 0.5, depth: 6).transformed(by: MeshInstance(position: Vector3(0, -0.25, 0))),
    .sphere(radius: 1).transformed(by: MeshInstance(position: Vector3(1, 1, 0))),
]
for line in lineDrawing(of: scene) { drawPolyline(line.points, closed: line.isClosed) }
```

`Mesh.transformed(by:)` takes a [`MeshInstance`](./Instancing.md), the same placement value the instanced draws take, and returns the mesh moved. Two calls to `lineDrawing` are two drawings that know nothing of each other, and the near one will not hide the far one.

The active camera and the current 3D transform place the drawing, exactly the way they place `drawMesh`, so a `withState { rotateY(a); ... }` around the call turns the drawing with the scene.

<a id="plotting"></a>
### Plotting it

Nothing special: the paths are drawn, and the export takes what was drawn.

```sh
ollin Scene.swift --export-svg scene.svg
ollin Scene.swift --export-gcode scene.gcode --width 180
ollin Scene.swift --export-dxf scene.dxf --width 180
```

Two habits worth keeping. Draw with `noFill()`, since a filled path is a shape a pen cannot make. And keep the stroke weight honest, since a plotter draws the pen's own width whatever the file says.

<a id="cost"></a>
### What it costs

Every edge that might be drawn is walked and tested for whether something covers it. `spacing` is how far apart, in canvas points, that test is made:

```swift
lineDrawing(of: scene, spacing: 2)     // the default
lineDrawing(of: scene, spacing: 0.5)   // catches a narrow gap, four times the work
lineDrawing(of: scene, spacing: 6)     // faster, and may miss a thin thing in front
```

Whatever the spacing, the two ends of a visible stretch are pinned down to a fraction of a point, so a coarse spacing costs accuracy only where something narrow crosses an edge. What it cannot do is find a gap narrower than itself.

The work is proportional to the number of edges drawn times their length, so it is the `creaseAngle` that decides the bill: a smooth mesh at the default costs its outline, and the same mesh at 0 costs its whole tessellation. This is CPU work, done while the frame is being built, and a scene of a few thousand triangles is a few milliseconds.

<a id="how"></a>
### How it works

Vertices that sit at the same place are welded first, since a mesh drawn with hard edges holds a copy of each corner per face and without welding every edge would look like a boundary. Each face is then projected, and its turn on the canvas says which way it faces. An edge is kept if it has one face (a boundary), if its two faces face opposite ways (a silhouette), or if their normals differ by more than `creaseAngle` (a crease).

Each kept edge is then walked. At every step the point is tested against the faces that could cover it, found through a grid of the canvas, by asking whether any of them is nearer at that point. Where the answer changes between two steps, the change is pinned down by halving. What comes back is the stretches that can be seen, joined end to end into as few paths as they allow so a pen lifts as rarely as it can.

<a id="notes"></a>
### Notes

- **Geometry behind the camera** is cut at the camera's near plane rather than dragged around behind it. A face that straddles that plane does not hide anything, which shows only when something is half behind the camera.
- **A stretch shorter than a canvas point is dropped.** That is the width of the tolerance the depth test needs, and what it removes is the speck a hidden edge shows of itself where it runs into the silhouette it ends on.
- **The silhouette of a tessellated surface is the tessellation's**, so a ball's outline is a many-sided polygon just inside the true circle. More segments make it rounder.
- **Faces with no area at all are ignored.** A lat-long sphere's poles are rows of them, and their direction is whatever the arithmetic makes of a cross product of nothing.
- **Materials, colors, and lights play no part.** This is geometry. To draw parts in different colors, call it once per group and `stroke` each differently, remembering that groups drawn separately do not hide each other.

---

<sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Line drawing`</sup>
