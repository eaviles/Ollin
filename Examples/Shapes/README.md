#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Shapes</sup>

---

## Shapes

The shape-drawing vocabulary: every primitive, the stroke and hollow modes, and composing shapes (boolean set operations on filled outlines, and SDF combinators that merge distance fields).

| Example | What it shows |
|---|---|
| [Booleans](Booleans/Sketch.swift) | the four `Shape` set operations over the same two moving shapes (a turning star and an orbiting disc), each filled result real geometry that strokes and exports like anything drawn by hand (`union`/`intersection`/`subtracting`/`symmetricDifference`) |
| [Combinators](Combinators/Sketch.swift) | SDF combinators: compose signed-distance fields so 2D shapes *merge* instead of stack (`drawSDF`, `smoothUnion { }`) |
| [CombinatorsGradient](CombinatorsGradient/Sketch.swift) | a linear/radial gradient `fill` or `stroke` painting a whole merged SDF field as one continuous surface, sampled in field space (`drawSDF`, `Gradient`) |
| [CombinatorsStretch](CombinatorsStretch/Sketch.swift) | per-axis sizing of a merged SDF field: an exact `stretched` elongation beside a non-uniform `scaled(x:y:)` bound (`drawSDF`) |
| [HollowShapes](HollowShapes/Sketch.swift) | a grid of shapes breathing from solid into framed hollow rings (`hollow`/`solid`, SDF) |
| [InkRibbon](InkRibbon/Sketch.swift) | stroke as shape: a drifting brush line stroked into a real region (`stroked`), then inset again and again so contour bands ring inside the ribbon (`offset`) |
| [Markers](Markers/Sketch.swift) | the five `drawPoint` markers, one per row, swept across sizes (`pointMarker`, SDF) |
| [NamedPolygons](NamedPolygons/Sketch.swift) | the named regular polygons turning in a labeled row (`drawPentagon`/`drawHexagon`/`drawHeptagon`/`drawOctagon`, SDF) |
| [Primitives](Primitives/Sketch.swift) | every `draw*` primitive, one per cell, turning slowly: a reference sheet for the whole drawing vocabulary |
| [RubberBand](RubberBand/Sketch.swift) | convex hull: the rubber band around a drifting herd of points, recomputed each frame, corners lit, the band itself a stroked region (`convexHull`, `stroked`) |
| [ShapeMenagerie](ShapeMenagerie/Sketch.swift) | rhombus, vesica, moon, cross, and ring, one per row, with corner radius breathing (`drawRhombus`/`drawVesica`/`drawMoon`/`drawCross`/`drawRing`, SDF) |
| [StrokeAlignment](StrokeAlignment/Sketch.swift) | the same shapes stroked inside, centered, and outside their outline, weight pulsing (`strokeAlign`, SDF) |
| [StrokeJoinsAndCaps](StrokeJoinsAndCaps/Sketch.swift) | a zigzag turned with each join and a segment ended with each cap, weight pulsing (`strokeJoin`/`strokeCap`) |

Run one with `swift run Example-Shapes-<Name>`, e.g. `swift run Example-Shapes-Primitives`.
