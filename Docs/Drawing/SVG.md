#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `SVG import`</sup>

---

## SVG import

Read vector artwork into the same `Shape`s and `Contour`s the rest of the framework speaks. A logo traced in a design tool comes in as geometry. So does a scanned drawing auto-traced to paths, or a file exported from another sketch. You can draw it as authored, respace it into dots, offset it, or hatch it. You can also run it through the [shape booleans](./Geometry.md), or send it back out through the [SVG export](../Output/Export.md).

<img src="../../Guide/Images/15-ShapesAsMaterial/ImportMined.jpg" alt="Three panels of the same imported sailboat SVG: drawn as authored with its own fills, respaced into even dots along every outline, and hatched into pen line work at a different angle per part" width="680">

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

The importer covers the subset generative work actually meets:

- `<path>`, with the full path grammar of lines, cubic and quadratic Béziers, smooth shorthands, and elliptical arcs.
- The basic shapes `rect` including rounded corners, `circle`, `ellipse`, `line`, `polyline`, and `polygon`.
- `<g>` groups, `transform` lists, presentation attributes, and inline `style`.
- Both fill rules, per-element opacity, and stroke width, join, and cap.

Curves are flattened to points at import, after transforms, so sampling density matches the final size. That is exactly like the [`Path`](./Geometry.md) builder.

What it deliberately skips is gradients and patterns, CSS `<style>` blocks, `<use>`/`<symbol>` references, clipping, masks, filters, and text. A `url(#…)` paint falls back to mid-gray, so the form stays visible. Convert text to outlines when exporting from a design tool. Content inside `<defs>` and friends is ignored whole, and the plain geometry in the file still imports.

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

All return `nil` when the file can't be read or holds no importable geometry. The `resource:in:` form follows the font and image loaders. Pass the caller's bundle explicitly, such as `.module` from inside a package target. A default would resolve to Ollin's own bundle rather than yours.

<a name="drawing"></a>

#### Drawing: drawSVG

```swift
drawSVG(_ svg: SVG)                      // in the document's own coordinates
drawSVG(_ svg: SVG, in rect: Rectangle)  // scaled uniformly to fit rect
```

Draws every element in document order with the fill, stroke, stroke width, and join/cap it was authored with. The current transform applies (`translate`/`rotate`/`scale` move the whole artwork), and your sketch's fill/stroke state is untouched afterward. Elements with neither fill nor stroke are skipped.

`drawSVG(_:in:)` letterboxes the artwork. It keeps its aspect ratio, scaled to fit and centered in `rect`, which is the same rule as `Rectangle(fitting:in:)`.

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

Coordinates come back in the document's user space (the `viewBox`), y-down from the top-left like the canvas, so nothing needs flipping. `fitted(in:)` returns a copy remapped into a canvas rectangle when you'd rather hold the scaled geometry than wrap drawing in a transform.

An element's `id` survives as `name`, so a specific part of the artwork can be pulled out and treated on its own:

```swift
if let window = art.element(named: "window") {
    drawShape(window.shape.resampled(spacing: 4))
}
```

<a name="geometry"></a>

#### Mining the geometry

The point of importing vectors is that they stop being a picture and become data. Some of what a loaded file feeds directly:

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

A multi-contour `<path>` stays one `Shape`, so holes keep cutting (its `fill-rule` maps onto the shape's `winding`: `nonzero` by default, `evenodd` when authored that way).

<a name="gotchas"></a>

#### Gotchas

- **An unfilled, unstroked element is invisible in SVG terms but still parsed.** The default fill is black, so most artwork just shows up. That is the SVG initial value. Only `fill="none"` elements with no stroke are skipped by `drawSVG`, and their geometry still rides along in `shapes`/`contours`.
- **Gradient fills fall back to mid-gray.** The importer resolves flat colors. That covers hex, `rgb()`, the CSS named set, and opacity folded into alpha. A gradient or pattern reference keeps the element visible in gray, rather than dropping it. Repaint by element when it matters.
- **Sizes are document units.** Nothing is rescaled at load. A 100-unit viewBox draws 100 pixels wide until you use `drawSVG(_:in:)` or `fitted(in:)`.
- **Text doesn't import.** Convert text to outlines when exporting from the design tool, then it arrives as paths like everything else.

Example: [`Examples/Shapes/SVGImport`](../../Examples/Shapes/SVGImport/Sketch.swift). Export's vector half lives in [`Output/Export.md`](../Output/Export.md).
