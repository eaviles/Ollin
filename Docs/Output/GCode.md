#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `GCode`</sup>

---

## G-code

You can export a sketch's line work as a program that a machine runs directly. G-code is the language that pen plotters, laser cutters, and CNC routers read. A G-code program consists of rapids, feed moves, and a few mode words. The [SVG export](./Export.md#vector-svg) hands your drawing to a machine's own tooling. This export skips that tooling and writes the moves itself.

```sh
swift run --package-path Examples Example-Export-Toolpath --export-gcode plot.gcode
```

The same export from code, with the full parameters:

```swift
OllinApp.exportGCode(sketch, to: "plot.gcode",
                     settings: GCode(.plotter(), width: 150))
```

`GCode` takes a machine and a physical width. The width is a required argument on purpose, in the same way that a mesh export asks for its size. A machine needs real units, and a default width would silently pick a size you never chose.

### The three machines

Each factory sets its own defaults, and every number is a parameter you can set:

```swift
GCode(.plotter(), width: 150)                          // pen up Z5, down Z0, 2400 mm/min
GCode(.plotter(pen: .servo(up: 0, down: 1000)), width: 150)
GCode(.laser(power: 0.6, passes: 2), width: 150)       // 60% power, cut twice
GCode(.mill(depth: 3, depthPerPass: 0.5), width: 150)  // six passes per path
```

- **`.plotter`** lifts the pen between paths. By default it moves a Z axis, which most pen machines read as a virtual pen lift. A machine that drives its pen with a servo takes `.servo(up:down:)` instead. The two numbers are written as the S word, the same word a laser uses for power. A short pause follows, so the servo lands before the head moves.
- **`.laser`** writes power as the S word, scaled by `powerScale` (1000 on most hobby controllers). Travels are rapids, and a laser controller fires only during feed moves, so the beam is off between paths without any extra command. `mode: .dynamic` scales power with the actual head speed, so corners do not scorch. `.constant` holds the power steady. `passes` repeats each path in place, which lets you cut through in several light passes.
- **`.mill`** cuts `depth` millimeters into the stock, at most `depthPerPass` per lap. Travels happen at `safeHeight` above the stock. Plunges use `plungeFeed` and cuts use `feed`. A closed loop plunges deeper on each lap without retracting.

### Size, origin, and the flip

The canvas width maps to `width` millimeters, and the height follows the canvas aspect ratio. `margin` adds a border on all sides, so the footprint is `width + 2 * margin` across. The machine origin is the bottom-left corner of the canvas. A canvas grows downward and a bed grows upward, so the program flips the y axis. Every program is in absolute millimeters (`G90`, `G21`), and it ends with the head at home and `M2`.

### What the planner does

Four steps sit between your draw calls and the file, and a machine needs each one:

- **Strokes plot along their centerlines.** A pen has one width, so `strokeWeight` does not carry over. Fills contribute their outlines. Pass a `Hatching` to shade them as line work instead, exactly as the [SVG export](./Export.md#hatching-solid-fills-for-a-pen-plotter) does.
- **Everything is clipped.** A `withClip` region cuts the line work the same way it cuts the render. Nothing past the canvas edge reaches the bed.
- **Touching ends merge.** Open paths whose ends meet within `joinTolerance` millimeters become one path. The pen then stays down across a line that you drew as many short calls. A merged path whose own ends meet closes into a loop.
- **The order is planned.** `ordered` is on by default. With it on, a greedy nearest-neighbor walk from the origin reorders the paths. The walk reverses a path when its far end is closer, and it enters a closed loop at whichever point is nearest. Ordering changes only the travel, never what is drawn.

Raster images have no line work, so they are skipped, and the file's header notes this. The header also records the [reproduction recipe](./Export.md#reproducibility-metadata), the canvas-to-millimeter mapping, and the measured draw and travel lengths.

### Previewing the route

The planner is public, so a sketch can show the machine's route before anything moves:

```swift
let plan = GCode(.plotter(), width: 150)
    .toolpath(contours, in: Rectangle(x: 0, y: 0, width: width, height: height))
plan.paths          // the line work, clipped and in plot order
plan.travels        // the pen-up hops, origin to origin
plan.drawnLength    // millimeters of drawing, one pass
plan.travelLength   // millimeters of travel, the part ordering shrinks
plan.program        // the G-code text
```

`Toolpath.paths` and `travels` stay in canvas coordinates, so you can draw them over the sketch with no conversion. The `Export/Toolpath` example animates a pen along the route at machine speed. Inside `draw()`, `isVectorExporting` is true while a vector export records the frame. A preview sketch reads it to keep its chrome (the pen marker, a caption) out of the plotted line work.

### From the command line

Every sketch and example takes the flag directly:

```sh
swift run --package-path Examples Example-X --export-gcode out.gcode                        # pen plotter, 150 mm wide
swift run --package-path Examples Example-X --export-gcode out.gcode --gcode-machine laser
swift run --package-path Examples Example-X --export-gcode out.gcode --gcode-machine mill --gcode-width 80 --gcode-margin 5
swift run --package-path Examples Example-X --export-gcode out.gcode --hatch --hatch-spacing 6
```

`--gcode-machine` picks a profile with its defaults. The finer parameters live in the API. `--hatch`, `--cross-hatch`, `--hatch-spacing`, and `--hatch-angle` work the same way as they do for SVG.

### Before you run it

Whatever tool wrote the program, run it dry before you run it for real. Take the pen out, disarm the laser, and hold the cutter above the stock. Check the size line in the header against your bed. Check the machine's own full-power S value against `powerScale`. The file states everything it assumed.

---

Next: [Export](./Export.md) covers the flat exporters beside this one (PNG, video, GIF, SVG, PDF). [Fabrication](./Fabrication.md) covers the 3D sibling, which writes a `Mesh` for printing.
