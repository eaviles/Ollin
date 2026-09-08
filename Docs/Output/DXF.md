#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `DXF`</sup>

---

## DXF

You can export a frame as a DXF drawing, the file a CAD program, a laser cutter's own software, or a vector editor opens as line work in millimeters. Each color in the sketch becomes a layer, which is how a shop tells a cut from a score from an engraving: draw the outline in one color and the fold lines in another, and the file arrives already sorted. The [SVG export](./Export.md#vector-svg) is the same drawing for the web and for print. This one is the same drawing for the shop.

```sh
swift run --package-path Examples Example-Export-Drafting --export-dxf panel.dxf
```

The same export from code, with the full parameters:

```swift
OllinApp.exportDXF(sketch, to: "panel.dxf", settings: DXF(width: 150))
```

`DXF` takes a physical width in millimeters. The width is a required argument on purpose, the way [`GCode`](./GCode.md) asks for one. A drawing opened in a shop program has real millimeters, and a default would size the part silently.

### Size and the flip

The canvas width maps to `width` millimeters, and the height follows the canvas aspect ratio. `margin` adds a border on all sides, so the drawing is `width + 2 * margin` across. The drawing's origin is the bottom-left corner of the canvas. A canvas grows downward and a drawing grows upward, so the y axis flips on the way out, and the canvas's top edge is the drawing's top. The file says its units are millimeters and its extents are the drawing's size.

### What goes in the file

- **A layer per color.** Every color the sketch draws in, stroke or fill, is a layer named by the color's display bytes: `color-1B1040` for a dark ink. The layer carries the nearest of the nine standard drawing colors, since that is all a layer can say, and the exact color stays in the name. Layers appear in the order they were first drawn on.
- **Strokes are lines and polylines along their centerlines.** `strokeWeight` does not carry over, since a shop program has its own idea of a line. A two-point path is a `LINE`, anything longer a `POLYLINE`, closed where the path was closed.
- **Fills are closed polylines.** A solid fill contributes its outline. Pass a `Hatching` and the fill arrives as line work instead, the way it does for a plotter.
- **A circle stays a circle.** `drawCircle` writes a `CIRCLE` when nothing has skewed it: a move, a turn, or a uniform scale keeps it round, and a clip that could cut it flattens it to a polyline instead. A cutter drilling a hole prefers a true circle.
- **Touching ends merge.** Open paths whose ends meet within `joinTolerance` millimeters become one polyline, so a curve drawn as many calls arrives as one entity. Zero keeps every call its own entity. Nothing is reordered: an entity drawn later is written later.
- **Everything is clipped.** A `withClip` region cuts the work the same way it cuts the render, and nothing past the canvas edge reaches the file. Raster images have no line work, so they are skipped.

The file is the R12 dialect of the format, the oldest still written and the one every reader takes. It carries no handles, no object dictionary, and no text, only the layers and the entities above.

### Previewing the layers

The planner is public, so a sketch can show what a shop program will open before anything is written. From inside a sketch, plan your own contours:

```swift
let canvas = Rectangle(x: 0, y: 0, width: width, height: height)
let plan = DXF(width: 150).drafting(contours, in: canvas)
plan.entities      // every line, polyline, and circle, in canvas coordinates
plan.layers        // the layers, with the color each stands for
plan.size          // the drawing in millimeters, margin included
plan.text          // the file
```

Contours planned this way sit on the default layer, `0`. From outside a sketch, `OllinApp.drafting(of:settings:)` plans a whole frame, colors and circles included, and `OllinApp.dxf(of:settings:)` is its text. Each `Entity` keeps canvas coordinates, so you can draw a plan over the sketch with no conversion, and `entities(on:)` picks one layer out.

### From the command line

Every sketch and example takes the flag directly:

```sh
swift run --package-path Examples Example-X --export-dxf out.dxf                               # 150 mm wide
swift run --package-path Examples Example-X --export-dxf out.dxf --dxf-width 80 --dxf-margin 5
swift run --package-path Examples Example-X --export-dxf out.dxf --hatch --hatch-spacing 6
swift run --package-path Examples Example-X --export-dxf out.dxf --frame 120
```

`--dxf-width` sets the physical width, which is 150 mm from the command line, and `--dxf-margin` the border. `--hatch`, `--cross-hatch`, `--hatch-spacing`, and `--hatch-angle` work the same way as they do for SVG.

### Before you cut

Open the file in the program that will drive the machine and check the size against the material before anything moves. A shop program reads a layer's name and color, so the sketch's colors are the handle: give each operation its own color, and keep a color to one operation.

---

Next: [G-code](./GCode.md) skips the shop program and writes the machine's moves itself. [Export](./Export.md) covers the flat exporters beside this one (PNG, video, GIF, SVG, PDF).
