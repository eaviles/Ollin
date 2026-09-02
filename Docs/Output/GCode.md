#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `GCode`</sup>

---

## G-code

A sketch's line work can leave as a program a machine runs directly. G-code is the language pen plotters, laser cutters, and CNC routers read: rapids, feed moves, and a few mode words. The [SVG export](./Export.md#vector-svg) hands your drawing to a machine's own tooling; this export skips the tooling and writes the moves.

```sh
swift run Example-Export-Toolpath --export-gcode plot.gcode
```

The same thing from code, with the full parameters:

```swift
OllinApp.exportGCode(sketch, to: "plot.gcode",
                     settings: GCode(.plotter(), width: 150))
```

`GCode` takes a machine and a physical width. The width is explicit on purpose, the same way a mesh export asks for its size. A machine needs real units, and a silent default would draw at a silent size.

### The three machines

Each factory carries curated defaults, and every number is a parameter:

```swift
GCode(.plotter(), width: 150)                          // pen up Z5, down Z0, 2400 mm/min
GCode(.plotter(pen: .servo(up: 0, down: 1000)), width: 150)
GCode(.laser(power: 0.6, passes: 2), width: 150)       // 60% power, cut twice
GCode(.mill(depth: 3, depthPerPass: 0.5), width: 150)  // six passes per path
```

- **`.plotter`** lifts the pen between paths. By default it moves a Z axis, which most pen machines read as a virtual pen lift. A machine that drives its pen with a servo takes `.servo(up:down:)` instead: the two numbers are written as the spindle power word, with a short pause so the servo lands before the head moves.
- **`.laser`** writes power as the S word, scaled by `powerScale` (1000 on most hobby controllers). Travels are rapids, and a laser controller fires only during feed moves, so the beam is off between paths without any extra command. `mode: .dynamic` scales power with actual head speed so corners do not scorch; `.constant` holds it. `passes` repeats each path in place, for cutting through in several light passes.
- **`.mill`** cuts `depth` millimeters into the stock, at most `depthPerPass` per lap. Travels happen at `safeHeight` above the stock. Plunges use `plungeFeed`, cuts use `feed`, and a closed loop plunges deeper each lap without retracting.

### Size, origin, and the flip

The canvas width maps to `width` millimeters and the height follows the canvas aspect. `margin` adds a border on all sides, so the footprint is `width + 2 * margin` across. The machine origin is the canvas's bottom-left corner. A canvas grows downward and a bed grows upward, so the program flips the y axis. Every program is absolute millimeters (`G90`, `G21`) and ends with the head home and `M2`.

### What the planner does

Between your draw calls and the file sit four steps, each one a machine actually needs:

- **Strokes plot along their centerlines.** A pen has one width, so `strokeWeight` does not travel. Fills contribute their outlines; pass a `Hatching` to shade them as line work instead, exactly as the [SVG export](./Export.md#hatching-solid-fills-for-a-pen-plotter) does.
- **Everything is clipped.** A `withClip` region cuts the line work the way it cuts the render, and nothing past the canvas edge reaches the bed.
- **Touching ends merge.** Open paths whose ends meet within `joinTolerance` millimeters become one path, so the pen stays down across what was drawn as many short calls. A merged path whose own ends meet closes into a loop.
- **The order is planned.** With `ordered` on (the default), a greedy nearest-neighbor walk from the origin reorders the paths, reverses one when its far end is closer, and enters a closed loop at whichever point is nearest. Ordering changes travel only, never what is drawn.

Raster images have no line work and are skipped, with a note in the file's header. The header also records the [reproduction recipe](./Export.md#reproducibility-metadata), the canvas-to-millimeter mapping, and the measured draw and travel lengths.

### Previewing the route

The planner is public, so a sketch can watch the machine's route before anything moves:

```swift
let plan = GCode(.plotter(), width: 150)
    .toolpath(contours, in: Rectangle(x: 0, y: 0, width: width, height: height))
plan.paths          // the line work, clipped and in plot order
plan.travels        // the pen-up hops, origin to origin
plan.drawnLength    // millimeters of drawing, one pass
plan.travelLength   // millimeters of travel, the part ordering shrinks
plan.program        // the G-code text
```

`Toolpath.paths` and `travels` stay in canvas coordinates, so drawing them over the sketch needs no conversion. The `Export/Toolpath` example animates a pen along the route at machine speed. Inside `draw()`, `isVectorExporting` is true while a vector export records the frame. A preview sketch reads it to keep its chrome (the pen marker, a caption) out of the plotted line work.

### From the command line

Every sketch and example takes the flag directly:

```sh
swift run Example-X --export-gcode out.gcode                        # pen plotter, 150 mm wide
swift run Example-X --export-gcode out.gcode --gcode-machine laser
swift run Example-X --export-gcode out.gcode --gcode-machine mill --gcode-width 80 --gcode-margin 5
swift run Example-X --export-gcode out.gcode --hatch --hatch-spacing 6
```

`--gcode-machine` picks a profile with its defaults; the API is where the finer parameters live. `--hatch`, `--cross-hatch`, `--hatch-spacing`, and `--hatch-angle` work the same as they do for SVG.

### Before you run it

A program from any tool deserves a dry run: pen out, laser disarmed, cutter above the stock. Check the header's size line against your bed, and check the machine's own full-power S value against `powerScale`. The file states everything it assumed.

---

Next: [Export](./Export.md) for the flat exporters these sit beside (PNG, video, GIF, SVG, PDF), and [Fabrication](./Fabrication.md) for the 3D sibling that writes a `Mesh` for printing.
