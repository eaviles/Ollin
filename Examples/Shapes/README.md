#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Shapes</sup>

---

## Shapes

These examples cover the shape-drawing vocabulary. They show every primitive and the stroke and hollow modes. They also show two ways to compose shapes: boolean set operations on filled outlines, and SDF combinators that merge distance fields.

| Example | What it shows |
|---|---|
| [Arrows](Arrows/Sketch.swift) | a field of `drawArrow` marks that lean toward the cursor, and a turning ring that sweeps `headLength`/`headWidth`. The ring is translucent because each arrow lays one even coat: the shaft stops at the base of the head |
| [Booleans](Booleans/Sketch.swift) | the four `Shape` set operations (`union`/`intersection`/`subtracting`/`symmetricDifference`) applied to the same two moving shapes, a turning star and an orbiting disc. Each filled result is real geometry, so it strokes and exports like anything drawn by hand |
| [Clipping](Clipping/Sketch.swift) | clipping as drawing state: `withClip(shape) { }` confines fills, strokes, images, and text to the filled region of the shape, and nested clips intersect |
| [Combinators](Combinators/Sketch.swift) | SDF combinators: `drawSDF` and `smoothUnion { }` compose signed-distance fields, so 2D shapes merge instead of stacking |
| [CombinatorsDetailing](CombinatorsDetailing/Sketch.swift) | the SDF detailing operations on one pair of crossing bars (`drawSDF`): `columns` adds ribs along a seam, `pipe` adds a bead at a crossing, `engrave` cuts a v-notch, and `groove`/`tongue` cut and raise a channel that mates |
| [CombinatorsGradient](CombinatorsGradient/Sketch.swift) | a linear or radial `Gradient` used as `fill` or `stroke` paints a whole merged SDF field as one continuous surface, because the gradient is sampled in field space (`drawSDF`) |
| [CombinatorsJoinery](CombinatorsJoinery/Sketch.swift) | the SDF joint operations (`drawSDF`): chamfer and stairs joins, cuts, and intersections, which give machined seams, drawn beside the organic smooth blends |
| [CombinatorsStretch](CombinatorsStretch/Sketch.swift) | per-axis sizing of a merged SDF field (`drawSDF`): `stretched` elongates the field exactly, and `scaled(x:y:)` gives a non-uniform bound, drawn side by side |
| [CornerCutting](CornerCutting/Sketch.swift) | Chaikin corner cutting, animated: a spiky burst relaxes into a smooth blob drawn over its raw outline, which stays faint underneath, and an open zigzag smooths while its endpoints never move. The number of passes is a parameter (`smoothed(iterations:)`) |
| [HollowShapes](HollowShapes/Sketch.swift) | a grid of shapes that cycle between solid fills and framed hollow rings (`hollow`/`solid`, SDF) |
| [Hulls](Hulls/Sketch.swift) | three ways to find the shape of a set of points (`convexHull`/`concaveHull`/`alphaShape`). The convex hull is drawn faint with its corner points lit, the concave hull cycles from loose to tight, and the alpha shape finds islands and a hole that neither hull can express |
| [InkRibbon](InkRibbon/Sketch.swift) | a stroke as a shape: a drifting brush line is turned into a real region (`stroked`), then inset repeatedly (`offset`) so contour bands nest inside the ribbon |
| [Markers](Markers/Sketch.swift) | the five `drawPoint` markers, one per row, each drawn across a range of sizes (`pointMarker`, SDF) |
| [MedialAxis](MedialAxis/Sketch.swift) | letterforms reduced to their skeletons (`medialAxis`). The skeleton of each glyph is stroked, inscribed circles are drawn from the radii the skeleton carries, and a bead rolls along each branch at the local thickness of the letter |
| [Neighbors](Neighbors/Sketch.swift) | a `SpatialIndex` over four thousand points answers three queries each frame: which point is nearest, which points are within a given distance, and which are inside a sliding box. Every point is also joined to its nearest neighbor |
| [Polygons](Polygons/Sketch.swift) | regular polygons from 3 to 8 sides drawn with `drawNgon`. From the pentagon up, each is also drawn and labeled through its named call, which is sugar over `drawNgon` (`drawPentagon`/`drawHexagon`/`drawHeptagon`/`drawOctagon`). A five-point `drawStar` goes from spiky to round as its inner radius grows. Everything turns (SDF) |
| [Primitives](Primitives/Sketch.swift) | every `draw*` primitive, one per cell, turning slowly, as a reference sheet for the whole drawing vocabulary. The shapes that accept `cornerRadius:` cycle through it |
| [Scattered](Scattered/Sketch.swift) | fitting: a value known at a few scattered points becomes a value defined everywhere, because each known point contributes a bump (`RadialBasis`) |
| [Star](Star/Sketch.swift) | a concave star with a hole, filled through `drawShape` and the vector `Shape` type. This is a triangulated fill, which `drawPolygon` cannot do |
| [StraightSkeleton](StraightSkeleton/Sketch.swift) | the straight skeleton used as a topographic survey. The ridge network of an island is extracted once (`straightSkeleton`). Then an animated series of mitered insets (`inset(by:)`) draws contour lines, which split where the land narrows and ring the lake |
| [StrokeAlignment](StrokeAlignment/Sketch.swift) | the same shapes stroked inside, centered on, and outside their outline, with the weight pulsing (`strokeAlign`, SDF) |
| [StrokeJoinsAndCaps](StrokeJoinsAndCaps/Sketch.swift) | a zigzag drawn with each join and a segment ended with each cap, with the weight pulsing (`strokeJoin`/`strokeCap`) |
| [Brushwork](Brushwork/Sketch.swift) | drag to paint: a `StrokeMark` measures how fast and how hard you drew and turns that into width and opacity (`StrokeDynamics`, `drawMark`). Three pre-recorded marks show each axis on its own |
| [DashedStrokes](DashedStrokes/Sketch.swift) | six dashed strokes sharing one weight and one clock (`strokeDash`): marching ants around a rounded rectangle, dots under round caps along a spiral, two rings turning against each other, a four-length pattern on a star, a taper read across the gaps, and a gradient running on through them |
| [StrokeProfiles](StrokeProfiles/Sketch.swift) | one spiral at one weight drawn under each width profile (`strokeProfile`): taper, lift off, wedge, a turning calligraphy nib, and one defined by hand |
| [Superellipse](Superellipse/Sketch.swift) | a wall of superellipse plates, with one exponent moving the whole family from a pinched star through diamond, ellipse, and squircle to an almost-rectangle |
| [Supershape](Supershape/Sketch.swift) | one closed contour that moves through star, flower, and gear-like forms as slow sines sweep the 2D superformula, drawn over fading copies of its recent shapes |
| [SVGImport](SVGImport/Sketch.swift) | SVG import: the bundled rocket badge is drawn as authored (`loadSVG`/`drawSVG`), then used as geometry, with its outlines resampled into evenly spaced dots |
| [Triangles](Triangles/Sketch.swift) | the two `drawTriangle` forms side by side: an equilateral triangle that turns on its center, and an isosceles wedge that turns on its apex (SDF) |
| [Watercolor](Watercolor/Sketch.swift) | watercolor pigment made by deforming polygons (`Watercolor`, `drawShape`): three pools of interleaved translucent layers that glaze where they overlap, plus a clipped speckle for a granulated texture. Each variation starts a fresh sheet |
| [Brushes](Brushes/Sketch.swift) | marks made by repeating a shape along a path: `strokeBrush` replaces the continuous ribbon with a row of stamps, which take their size from `strokeWeight` and their color from the stroke |

Run one with `swift run Example-Shapes-<Name>`, for example `swift run Example-Shapes-Primitives`.
