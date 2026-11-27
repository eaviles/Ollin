#### <sup>[Ollin](../../README.md) → [Reference](../README.md) → [3D](./README.md) → `Drawing on a real surface`</sup>

---

## Drawing on a real surface

A camera's picture is flat, and the wall it shows stands in a room. These calls let a sketch work on that wall as a surface. It draws on the wall in meters. It keeps a clicked point on the spot it was clicked. It lifts a piece of the wall off still showing the picture's own pixels. It lets the real wall hide a drawn thing that goes behind it.

They are for a sketch that draws over a camera's picture through a camera that matches it. A [recording of the phone's stream](Phone.md#a-recording) gives both. Nothing here needs a phone: the calls take a surface, a picture, and a `Camera3D`, wherever those came from. The [phone page](Phone.md#drawing-on-what-the-phone-saw) has the forms that take what the phone reports.

```swift
drawPhonePicture(view)                      // the camera's picture, covering the canvas
camera(view)                                // a 3D camera that matches it
let wall = device.planes.largest(of: .wall)!

occluding { drawMesh(wall.mesh) }           // the real wall hides what goes behind it

withPlane(wall) {                           // x along the wall, y up it, z out of it, in meters
    translate(0.5, 0.2)                     // a place on the wall
    painted(with: view) {                   // what is drawn here carries the picture's pixels
        translate(0, 0, 0.1)                // ten centimeters out of the wall
        drawBox(width: 0.25, height: 0.25, depth: 0.01)
    }
}
```

### Contents

- [A surface: `Plane3`](#a-surface) - a wall or a floor as a value, with coordinates of its own
- [Drawing in a surface's coordinates](#withPlane) - `withPlane(_:)`
- [A point that stays put](#pinned-points) - `unproject(_:onto:)`, `cameraRay(through:)`, pins kept as values
- [The picture as paint](#painted) - `painted(with:from:)`, a piece of the picture that moves
- [A real thing that hides a drawn one](#occluding) - `occluding { }`
- [An image on four points](#an-image-on-four-points) - `drawImage(_:topLeft:topRight:bottomRight:bottomLeft:)`, a layer on a wall
- [What it does not do](#what-it-does-not-do)

<a id="a-surface"></a>
### A surface: `Plane3`

`Plane3` is a flat surface in space with two directions of its own, so a place on it is two numbers. It has an `origin`, a `right` and an `up` that lie in it, and a `normal` out of its front. Its coordinates are in the units of the space it stands in, which is meters for a room a phone measured.

```swift
let wall = Plane3(origin: Vector3(0, 1.5, -2), normal: .unitZ)   // through a point, facing a way
let table = Plane3(through: corners, facing: eye)                // fitted to measured points

wall.point(at: Vector2(0.4, 0.2))           // Vector3: 40 cm right, 20 cm up
wall.point(at: Vector2(0.4, 0.2), lift: 0.1)    // and 10 cm out of its front
wall.coordinates(of: point)                 // Vector2: the place straight under a point
wall.distance(to: point)                    // Double: in front is positive, behind negative
wall.intersection(with: ray)                // Vector3?: where a Ray3 meets it
```

On a wall, `up` is the room's up laid onto the surface, and `right` runs to the right of someone facing it. A floor or a ceiling has no such up, and takes the room's -z. [`Geometry`](../Drawing/Geometry.md#plane3) has the whole type: the three ways to make one, the fit through points, and the surfaces made from another (`moved(by:lift:)`, `turned(by:)`, `flipped`).

<a id="withPlane"></a>
### Drawing in a surface's coordinates

**`withPlane(_:)`** runs a block in the surface's own coordinates: x along `right`, y along `up`, z out of the front, with (0, 0, 0) at the `origin`.

```swift
withPlane(wall) {
    translate(0.5, 0.2, 0.05)       // on the wall, 5 cm out of it
    drawBox(size: 0.1)
    drawLine(Vector3(-1, 0, 0), Vector3(1, 0, 0))       // a line along it
}
```

It is the 3D transform `wall.matrix`, scoped the way `withState` scopes one. Everything 3D follows it: meshes, [lines between `Vector3` points](Lines.md), [solid type](3D.md#solid-type). A 2D call such as `drawCircle` still draws on the canvas. A flat composition goes onto a surface through a layer, [laid on four points](#an-image-on-four-points).

<a id="pinned-points"></a>
### A point that stays put

A click is a place on the canvas. Met with a surface, it is a place in the room, and a place in the room stays where it is while the camera moves.

**`unproject(_:onto:)`** returns the point of a `Plane3` under a canvas point, through the active camera. It is [`cameraRay(through:)`](DepthCompositing.md#cameraRay) met with the surface, and it is `nil` when the surface is not in front of the camera along that line.

```swift
var pins: [Vector3] = []

override func mousePressed() {
    if let spot = unproject(mouse, onto: wall) { pins.append(spot) }
}
```

A pin is a plain `Vector3`, kept in the sketch. Draw at it on any later frame and it lands on the same spot of the wall. `wall.coordinates(of: spot)` is the same place as two numbers on the wall, if that is the form you want to keep.

`cameraRay(through:)` works through every kind of camera, a real lens included (`Camera3D.intrinsic(_:)`, and the camera a phone reports). It returns a `Ray3`.

<a id="painted"></a>
### The picture as paint

**`painted(with:from:)`** paints the meshes drawn in its block with a picture as a camera saw it. Every point of a mesh shows the pixel that camera had of the point. The picture is taken to fill the camera's whole view.

Drawn over the same picture through the same camera, a painted mesh left where it is changes nothing you can see. Moved, it carries its pixels along, which is the use: a piece of what the picture shows, cut loose.

**A mesh takes its pixels where it stands when the block opens.** A transform made before the block places the mesh. A transform made inside the block moves it afterwards and leaves what it is painted with alone.

```swift
withPlane(wall) {
    translate(tile.x, tile.y)               // before the block: where the tile is on the wall
    painted(with: picture, from: lens) {
        translate(0, 0, push)               // inside it: the move, pixels and all
        drawBox(width: 0.25, height: 0.25, depth: 0.01)
    }
}
```

So a scene of placed things, each to be painted where it stands, wants a block around each draw and its placement outside. Wrapping the whole scene in one block would read every transform inside it as a move.

A stretch counts as a move too. Paint a thin slab flat on a wall, then scale it along the wall's normal, and it becomes a block. Its face shows the wall, and its sides show the wall's edge pixels drawn out. The [`PhoneWallTiles`](../../Examples/3D/Phone/PhoneWallTiles/Sketch.swift) example does this.

- **It is exact for each pixel.** The place in the picture is worked out per pixel, so a wall-sized mesh of two triangles seen at a slant is as right as a fine one.
- **The fill tints it.** `fill(.white)` leaves the picture as it is. Any other fill multiplies it, which is how a block's sides are shaded.
- **It is unlit, and outside the lighting.** The picture already holds the light of the place it was taken in. A painted mesh takes no light, casts no shadow, and shows in no reflection.
- **It still has depth.** It hides what is behind it and is hidden by what is nearer.
- **What the camera did not see is not drawn.** A part of a mesh outside the picture, or behind the camera that took it, has no pixel to show.
- **Meshes only.** `drawMesh`, and the solid primitives built on it. Instanced meshes, mesh fields, and marched fields inside the block draw as they always do.

How exact "changes nothing" is: flat faces come out on the picture's own values. On a curved mesh's rim a few pixels can sit up to two levels of 255 off. Where the canvas enlarges the picture, about one pixel in a thousand sits one level off.

<a id="occluding"></a>
### A real thing that hides a drawn one

**`occluding { }`** draws the meshes in its block as depth alone. Each one hides whatever is drawn behind it afterwards, and puts no color of its own on the canvas.

It is for the real things in the picture. Stand a mesh where a real wall or table is and draw it inside this block. From then on a drawn thing that goes behind the real one disappears behind it, with the picture of the real one showing through untouched.

```swift
drawPhonePicture(view)
camera(view)
occluding { drawMesh(device.planes.mesh) }      // the room's own flat surfaces
drawSphere(radius: 0.2)                         // hidden where a surface is nearer
```

Order matters, as it does for anything that hides. What was drawn before the block is already on the canvas and stays. Like a painted mesh, one drawn here is outside the lighting: no shadow, no reflection.

It hides exactly as much as the mesh you give it. A phone in Room mode reports flat surfaces and a room mesh. So a wall or a table top hides well, and the side of a chair hides only if the room mesh has it.

### An image on four points

**`drawImage(_:topLeft:topRight:bottomRight:bottomLeft:)`** lays an image on four points of space. The corners go to the four, and the rest lands where a flat sheet through them would carry it. That holds exactly, however the sheet is turned to the camera.

This is how flat 2D drawing gets onto a wall: draw it into a [layer](../Drawing/Effects.md#rendertarget), and lay the layer's image on the wall.

```swift
let poster = makeRenderTarget(width: 700, height: 950)      // once, in setup()

withTarget(poster) {                                        // any 2D drawing
    background(.black)
    drawCircle(350, 475, 200)
}
drawImage(poster.image, topLeft: pins[0], topRight: pins[1],
          bottomRight: pins[2], bottomLeft: pins[3])
```

The points go through the 3D transform, so inside `withPlane(_:)` they are places on the surface: `Vector3(x, y, 0)`, with y up. The four are taken in order around the sheet and should lie on one flat surface. Points that cross over draw nothing and leave a note.

The image is unlit and outside the lighting. `tint(_:)` tints it like any image. It is hidden by what is nearer, and it hides what is behind it wherever it is not clear. So a layer cleared to nothing leaves the wall showing between its marks.

### What it does not do

- **A lifted piece leaves its picture behind.** The camera's picture is still flat on the canvas, so a piece lifted clear of the wall shows again, flat, on the wall behind it when seen from the side. A block that stays joined to the wall by its sides covers its own place and has no such double. For a piece that floats, draw something over the place it left.
- **2D calls do not follow `withPlane(_:)`.** A flat composition reaches a surface through a layer.
- **Nothing here finds a surface.** The surface is one the phone reported, or one you fit through points with `Plane3(through:)`.
- **A drawn thing is only as steady as the camera's place.** A phone's sense of where it is drifts a little over a long walk, and what is drawn slides against the picture by that much.
- **Not carried:** a vector export has no picture to paint with and draws none of this. A spatial export writes a painted mesh as a plain surface and leaves an occluding one out. A web page export names the call and stops.

---

See also [Phone](Phone.md#drawing-on-what-the-phone-saw) for the forms that take a `PhoneCamera` and a `PhonePlane`, and [a recording](Phone.md#a-recording) for where the picture and the camera come from. [Depth compositing](DepthCompositing.md) places flat 2D drawing at one depth in a scene, and [decals](3D.md#decals) stamp a picture onto lit surfaces. The [`PhoneWallTiles`](../../Examples/3D/Phone/PhoneWallTiles/Sketch.swift) example pushes a wall's own tiles out of it, and [`PhonePoster`](../../Examples/3D/Phone/PhonePoster/Sketch.swift) lays a layer on a poster and sends balls through the wall.
