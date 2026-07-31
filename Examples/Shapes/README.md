#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Shapes</sup>

---

## Shapes

The shape-drawing vocabulary: every primitive, the stroke and hollow modes, and composing shapes (boolean set operations on filled outlines, and SDF combinators that merge distance fields).

| Example | What it shows |
|---|---|
| [Booleans](Booleans/Sketch.swift) | the four `Shape` set operations over the same two moving shapes (a turning star and an orbiting disc), each filled result real geometry that strokes and exports like anything drawn by hand (`union`/`intersection`/`subtracting`/`symmetricDifference`) |
| [Clipping](Clipping/Sketch.swift) | clipping as drawing state: `withClip(shape) { }` confines fills, strokes, images, and text to the shape's filled region, and nested clips intersect |
| [Combinators](Combinators/Sketch.swift) | SDF combinators: compose signed-distance fields so 2D shapes *merge* instead of stack (`drawSDF`, `smoothUnion { }`) |
| [CombinatorsDetailing](CombinatorsDetailing/Sketch.swift) | the SDF detailing ops on one crossing-bars pair: `columns` ribs a seam, `pipe` beads a crossing, `engrave` scores a v-notch, `groove`/`tongue` cut and raise a mating channel (`drawSDF`) |
| [CombinatorsGradient](CombinatorsGradient/Sketch.swift) | a linear/radial gradient `fill` or `stroke` painting a whole merged SDF field as one continuous surface, sampled in field space (`drawSDF`, `Gradient`) |
| [CombinatorsJoinery](CombinatorsJoinery/Sketch.swift) | the SDF joint ops: chamfer and stairs joins, cuts, and intersections, machined seams beside the organic smooth blends (`drawSDF`) |
| [CombinatorsStretch](CombinatorsStretch/Sketch.swift) | per-axis sizing of a merged SDF field: an exact `stretched` elongation beside a non-uniform `scaled(x:y:)` bound (`drawSDF`) |
| [CornerCutting](CornerCutting/Sketch.swift) | Chaikin corner cutting live: a spiky burst relaxing into a flowing blob over its raw ghost, and an open zigzag whose endpoints never move, with the passes on a knob (`smoothed(iterations:)`) |
| [HollowShapes](HollowShapes/Sketch.swift) | a grid of shapes breathing from solid into framed hollow rings (`hollow`/`solid`, SDF) |
| [Hulls](Hulls/Sketch.swift) | three answers to "what shape are these points?": the convex hull faint, the concave hull breathing from loose to tight, and the alpha shape resolving islands and a hole neither hull can express (`concaveHull`/`alphaShape`/`convexHull`) |
| [InkRibbon](InkRibbon/Sketch.swift) | stroke as shape: a drifting brush line stroked into a real region (`stroked`), then inset again and again so contour bands ring inside the ribbon (`offset`) |
| [Markers](Markers/Sketch.swift) | the five `drawPoint` markers, one per row, swept across sizes (`pointMarker`, SDF) |
| [MedialAxis](MedialAxis/Sketch.swift) | letterforms reduced to their bones: each glyph's skeleton stroked, inscribed circles riding the carried radii, and a bead rolling along each bone at the letter's local thickness (`medialAxis`) |
| [NamedPolygons](NamedPolygons/Sketch.swift) | the named regular polygons turning in a labeled row (`drawPentagon`/`drawHexagon`/`drawHeptagon`/`drawOctagon`, SDF) |
| [Primitives](Primitives/Sketch.swift) | every `draw*` primitive, one per cell, turning slowly: a reference sheet for the whole drawing vocabulary |
| [RubberBand](RubberBand/Sketch.swift) | convex hull: the rubber band around a drifting herd of points, recomputed each frame, corners lit, the band itself a stroked region (`convexHull`, `stroked`) |
| [ShapeMenagerie](ShapeMenagerie/Sketch.swift) | rhombus, vesica, moon, cross, and ring, one per row, with corner radius breathing (`drawRhombus`/`drawVesica`/`drawMoon`/`drawCross`/`drawRing`, SDF) |
| [StrokeAlignment](StrokeAlignment/Sketch.swift) | the same shapes stroked inside, centered, and outside their outline, weight pulsing (`strokeAlign`, SDF) |
| [StrokeJoinsAndCaps](StrokeJoinsAndCaps/Sketch.swift) | a zigzag turned with each join and a segment ended with each cap, weight pulsing (`strokeJoin`/`strokeCap`) |
| [SVGImport](SVGImport/Sketch.swift) | SVG import: the bundled rocket badge drawn as authored (`loadSVG`/`drawSVG`), then mined as geometry, its outlines resampled into even dots |
| [Watercolor](Watercolor/Sketch.swift) | watercolor pigment from polygon deformation: three pools of interleaved translucent layers glazing where they overlap, plus a clipped speckle for granulating texture; a fresh sheet per variation (`Watercolor`, `drawShape`) |

Run one with `swift run Example-Shapes-<Name>`, e.g. `swift run Example-Shapes-Primitives`.
