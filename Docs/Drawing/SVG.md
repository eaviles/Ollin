#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `SVG import`</sup>

---

## SVG import

Read vector artwork into the same `Shape`s and `Contour`s the rest of the framework uses. A logo traced in a design tool arrives as geometry. So does a scanned drawing auto-traced to paths, or a file exported from another sketch. Once it is loaded you can draw it as authored, respace it into dots, offset it, or hatch it. You can also run it through the [shape booleans](./Geometry.md), or send it back out through the [SVG export](../Output/Export.md).

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/ImportMined-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/ImportMined.jpg" alt="Three panels of the same imported sailboat SVG: drawn as authored with its own fills, respaced into even dots along every outline, and hatched into pen line work at a different angle per part" width="680">
</picture>

```swift
@main
final class Badge: Sketch {
    var art: SVG?

    override func setup() {
        art = loadSVG("rocket.svg")
    }

    override func draw() {
        background(.white)
        guard let art else { return }
        drawSVG(art, in: Rectangle(x: 100, y: 100, width: 880, height: 880))
    }
}
```

The importer covers the subset of SVG that generative work meets in practice:

- `<path>`, with the full path grammar of lines, cubic and quadratic Béziers, smooth shorthands, and elliptical arcs.
- The basic shapes `rect` including rounded corners, `circle`, `ellipse`, `line`, `polyline`, and `polygon`.
- `<g>` groups, `transform` lists, presentation attributes, and inline `style`.
- Both fill rules, per-element opacity, and stroke width, join, and cap.

Curves are flattened to points at import, after the transforms are applied, so the sampling density matches the final size. The [`Path`](./Geometry.md) builder works the same way.

The importer deliberately skips gradients and patterns, CSS `<style>` blocks, `<use>`/`<symbol>` references, clipping, masks, filters, and text. A `url(#…)` paint falls back to mid-gray, so the form stays visible. Convert text to outlines when you export from a design tool. Content inside `<defs>` and similar elements is ignored as a whole, and the plain geometry in the file still imports.

### Contents

- [Loading](#loading)
- [Drawing: drawSVG](#drawing)
- [The SVG type](#type)
- [Mining the geometry](#geometry)
- [Gotchas](#gotchas)

<a name="loading"></a>

#### Loading

```swift
loadSVG(_ path: String) -> SVG?          // Sketch sugar, by file path
loadSVG(_ url: URL) -> SVG?

SVG(contentsOf: "art/crest.svg")         // the same, as initializers
SVG(url: fileURL)
SVG(data: data)                          // raw bytes (an inline string, a download)
SVG(resource: "crest", in: .module)      // bundled beside the sketch
```

All of these return `nil` when the file cannot be read or holds no importable geometry. The `resource:in:` form follows the font and image loaders, so you pass the caller's bundle explicitly, such as `.module` from inside a package target. Pass it every time, because a default would resolve to Ollin's own bundle rather than yours.

<a name="drawing"></a>

#### Drawing: drawSVG

```swift
drawSVG(_ svg: SVG)                      // in the document's own coordinates
drawSVG(_ svg: SVG, in rect: Rectangle)  // scaled uniformly to fit rect
```

`drawSVG` draws every element in document order, with the fill, stroke, stroke width, join, and cap it was authored with. The current transform applies, so `translate`, `rotate`, and `scale` move the whole artwork. Your sketch's own fill and stroke state is untouched afterward, and elements with neither a fill nor a stroke are skipped.

`drawSVG(_:in:)` letterboxes the artwork. It keeps the aspect ratio, scales the artwork to fit, and centers it in `rect`. That is the same rule as `Rectangle(fitting:in:)`.

<a name="type"></a>

#### The SVG type

```swift
struct SVG {
    var elements: [Element]              // document order, back to front
    var bounds: Rectangle                // the viewBox (or the geometry's bounds)

    var shapes: [Shape]                  // just the geometry
    var contours: [Contour]              // every contour, as plain line-work
    func element(named: String) -> Element?   // find by id="…"
    func fitted(in: Rectangle) -> SVG    // a scaled copy (strokes scale too)
}

struct SVG.Element {
    var shape: Shape                     // closed contours fill; open ones stroke
    var fill: Color?                     // nil = fill="none"
    var stroke: Color?                   // nil = unstroked (the SVG default)
    var strokeWidth: Double              // in document units, transform-scaled
    var join: StrokeJoin                 // stroke-linejoin (miter default)
    var cap: StrokeCap                   // stroke-linecap (butt default)
    var name: String?                    // the id attribute
}
```

Coordinates come back in the document's user space, which is the `viewBox`. They run y-down from the top-left, the same as the canvas, so nothing needs flipping. `fitted(in:)` returns a copy remapped into a canvas rectangle. Use it when you would rather hold the scaled geometry than wrap the drawing in a transform.

An element's `id` survives as `name`, so you can pull one part of the artwork out and treat it on its own:

```swift
if let window = art.element(named: "window") {
    drawShape(window.shape.resampled(spacing: 4))
}
```

<a name="geometry"></a>

#### Mining the geometry

Once a file is imported it is data rather than a picture, so the rest of the framework can work on it directly. Here are some of the things a loaded file feeds:

```swift
// Even dots along every outline (see Contour.resampled).
for contour in art.fitted(in: frame).contours {
    for p in contour.resampled(spacing: 6).points {
        drawCircle(center: p, radius: 2)
    }
}

// Booleans against drawn geometry (see Geometry.md).
let cut = art.shapes[0].subtracting(stamp)

// Plotter output: import, transform, re-export as vectors.
// swift run MySketch --export-svg out.svg
```

A `<path>` with several contours stays one `Shape`, so holes keep cutting. Its `fill-rule` maps onto the shape's `winding`, which is `nonzero` by default and `evenodd` when the file was authored that way.

<a name="gotchas"></a>

#### Gotchas

- **An element with no fill and no stroke is invisible in SVG terms, but still parsed.** The default fill is black. That is the SVG initial value, so most artwork shows up as it is. `drawSVG` skips only the elements that set `fill="none"` and have no stroke, and their geometry is still there in `shapes` and `contours`.
- **Gradient fills fall back to mid-gray.** The importer resolves flat colors, which covers hex, `rgb()`, the CSS named set, and opacity folded into alpha. A gradient or pattern reference keeps the element visible in gray instead of dropping it. Repaint that element yourself when the color matters.
- **Sizes are document units.** Nothing is rescaled at load. A 100-unit viewBox draws 100 pixels wide until you use `drawSVG(_:in:)` or `fitted(in:)`.
- **Text does not import.** Convert text to outlines when you export from the design tool. It then arrives as paths, like everything else.

Example: [`Examples/Shapes/SVGImport`](../../Examples/Shapes/SVGImport/Sketch.swift). The vector half of export is in [`Output/Export.md`](../Output/Export.md).
