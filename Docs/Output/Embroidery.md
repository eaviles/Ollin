#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Embroidery`</sup>

---

## Embroidery

You can export a frame as the stitches an embroidery machine sews. The file is a Tajima `.dst`, the format nearly every machine and every embroidery program reads. A `.dst` holds no colors, only the stitches, the jumps between them, and the stops where the thread changes. So the design goes onto the hoop exactly as planned, and you load each thread in the order the sketch drew its colors.

```sh
swift run --package-path Examples Example-Export-Embroidery --export-embroidery leaf.dst
```

The same export from code, with the full parameters:

```swift
OllinApp.exportEmbroidery(sketch, to: "leaf.dst",
                          settings: Embroidery(width: 100))
```

`Embroidery` takes a physical width in millimeters. The width is a required argument on purpose, the way [`GCode`](./GCode.md) asks for one. A hoop has real millimeters, and a default would size the design silently.

### Size and the hoop

The canvas width maps to `width` millimeters, and the height follows the canvas aspect ratio. `margin` adds a border on all sides, so the footprint is `width + 2 * margin` across. The design starts at the canvas center, and every stitch in the file is a move from the one before it. So a hoop centered on the design sews it whole. A hoop grows upward and a canvas downward, so the file flips the y axis. Positions sit on a tenth-millimeter grid, and one record moves at most 12.1 mm, so a long jump takes several records.

### What the planner does

Five steps sit between your draw calls and the file:

- **Strokes sew along their centerlines** as a running stitch. `stitchLength` is the pitch, 2.5 mm by default. No stitch is longer than it, and every corner is a penetration. `strokeWeight` does not carry over, since a thread has one width.
- **Fills sew as rows.** `fillSpacing` is the distance between the rows, 0.4 mm by default, and `fillAngle` is their direction. The rows connect end to end, so the thread stays down across a fill. Pass `fillSpacing: nil` to sew only each fill's outline. Rows 0.4 mm apart are a dense, solid fill, and wider rows show the ground between them.
- **Each color is a thread, in draw order.** A new thread starts whenever the color changes. What was drawn later is sewn later, so it lies on top. A sketch that wants fewer thread changes draws each color's shapes together. A gradient sews in the middle color of its ramp.
- **Everything is clipped.** A `withClip` region cuts the stitches the same way it cuts the render. Nothing past the canvas edge reaches the hoop.
- **Touching ends merge, and the order is planned.** Open paths whose ends meet within `joinTolerance` millimeters sew as one path. Within each thread, a nearest-neighbor walk reorders the paths to shorten the jumps. Ordering changes only the jumps, never what is sewn.

A hop from one path to the next is a stitch when it is within the pitch. Otherwise it is a jump, with the thread carried over. Raster images have no stitches, so they are skipped.

### Previewing the stitches

The planner is public, so a sketch can show the sewing before anything runs. From inside a sketch, plan your own contours:

```swift
let canvas = Rectangle(x: 0, y: 0, width: width, height: height)
let plan = Embroidery(width: 100).stitches(contours, in: canvas)
plan.stitches      // every penetration and jump, in canvas coordinates
plan.stitchCount   // penetrations
plan.threadLength  // millimeters of running stitch
plan.jumpLength    // millimeters carried in jumps, the part ordering shrinks
plan.size          // the design in millimeters, margin included
plan.dst()         // the file's bytes
```

`Stitch.position` stays in canvas coordinates, so you can draw the plan over the sketch with no conversion. Each stitch carries a `kind`: a `.stitch`, a `.jump`, or a `.colorChange`. From outside a sketch, `OllinApp.stitching(of:settings:)` plans a whole frame, fills and colors included, and `threads` lists the colors in the order the machine asks for them. The `Export/Embroidery` example draws a leaf and its stitches side by side.

### From the command line

Every sketch and example takes the flag directly:

```sh
swift run --package-path Examples Example-X --export-embroidery out.dst                                   # 100 mm wide
swift run --package-path Examples Example-X --export-embroidery out.dst --embroidery-width 80 --embroidery-margin 5
swift run --package-path Examples Example-X --export-embroidery out.dst --stitch-length 3 --fill-spacing 0.6
swift run --package-path Examples Example-X --export-embroidery out.dst --fill-spacing 0                  # fills as outlines
```

`--embroidery-width` sets the physical width, which is 100 mm from the command line, and `--fill-spacing 0` sews fills as outlines. The finer parameters live in the API. The file's label, the name a machine shows, is the file's own name.

### Before you sew it

Sew a test on scrap first. The file carries no lock stitches and no trims. The machine's own settings, or a pass through your embroidery program, add them, and that program also tells you which thread to load when. Rows half a millimeter apart across a large fill are many thousands of stitches, so check `stitchCount` against what the fabric and the stabilizer will take. Check `size` against the hoop.

---

Next: [G-code](./GCode.md) covers the plotter, laser, and mill sibling. [Export](./Export.md) covers the flat exporters (PNG, video, GIF, SVG, PDF).
