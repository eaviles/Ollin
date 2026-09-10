#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Shapes</sup>

---

## Shapes

| [![Arrows](https://media.ollin.art/examples/Shapes/Arrows/still-640.jpg?v=7129651c)](Arrows/) | [![Booleans](https://media.ollin.art/examples/Shapes/Booleans/still-640.jpg?v=e9545bf1)](Booleans/) | [![Brushes](https://media.ollin.art/examples/Shapes/Brushes/still-640.jpg?v=3d541644)](Brushes/) | [![Brushwork](https://media.ollin.art/examples/Shapes/Brushwork/still-640.jpg?v=8773c62f)](Brushwork/) |
|---|---|---|---|
| [Arrows](Arrows/) | [Booleans](Booleans/) | [Brushes](Brushes/) | [Brushwork](Brushwork/) |
| [![Clipping](https://media.ollin.art/examples/Shapes/Clipping/still-640.jpg?v=deba1c50)](Clipping/) | [![Combinators](https://media.ollin.art/examples/Shapes/Combinators/still-640.jpg?v=cf09fb4a)](Combinators/) | [![CombinatorsDetailing](https://media.ollin.art/examples/Shapes/CombinatorsDetailing/still-640.jpg?v=e63093ec)](CombinatorsDetailing/) | [![CombinatorsGradient](https://media.ollin.art/examples/Shapes/CombinatorsGradient/still-640.jpg?v=d08e1008)](CombinatorsGradient/) |
| [Clipping](Clipping/) | [Combinators](Combinators/) | [CombinatorsDetailing](CombinatorsDetailing/) | [CombinatorsGradient](CombinatorsGradient/) |
| [![CombinatorsJoinery](https://media.ollin.art/examples/Shapes/CombinatorsJoinery/still-640.jpg?v=a43dd00c)](CombinatorsJoinery/) | [![CombinatorsStretch](https://media.ollin.art/examples/Shapes/CombinatorsStretch/still-640.jpg?v=8ad63b3b)](CombinatorsStretch/) | [![CornerCutting](https://media.ollin.art/examples/Shapes/CornerCutting/still-640.jpg?v=597652fc)](CornerCutting/) | [![DashedStrokes](https://media.ollin.art/examples/Shapes/DashedStrokes/still-640.jpg?v=f261c625)](DashedStrokes/) |
| [CombinatorsJoinery](CombinatorsJoinery/) | [CombinatorsStretch](CombinatorsStretch/) | [CornerCutting](CornerCutting/) | [DashedStrokes](DashedStrokes/) |
| [![HobbySpline](https://media.ollin.art/examples/Shapes/HobbySpline/still-640.jpg?v=4fcaf66f)](HobbySpline/) | [![HollowShapes](https://media.ollin.art/examples/Shapes/HollowShapes/still-640.jpg?v=86f4d78e)](HollowShapes/) | [![Hulls](https://media.ollin.art/examples/Shapes/Hulls/still-640.jpg?v=0851621d)](Hulls/) | [![InkRibbon](https://media.ollin.art/examples/Shapes/InkRibbon/still-640.jpg?v=b2aa2e81)](InkRibbon/) |
| [HobbySpline](HobbySpline/) | [HollowShapes](HollowShapes/) | [Hulls](Hulls/) | [InkRibbon](InkRibbon/) |
| [![Markers](https://media.ollin.art/examples/Shapes/Markers/still-640.jpg?v=a47c2557)](Markers/) | [![MedialAxis](https://media.ollin.art/examples/Shapes/MedialAxis/still-640.jpg?v=380b00e1)](MedialAxis/) | [![Neighbors](https://media.ollin.art/examples/Shapes/Neighbors/still-640.jpg?v=e41d2e15)](Neighbors/) | [![Polygons](https://media.ollin.art/examples/Shapes/Polygons/still-640.jpg?v=ca0678f9)](Polygons/) |
| [Markers](Markers/) | [MedialAxis](MedialAxis/) | [Neighbors](Neighbors/) | [Polygons](Polygons/) |
| [![Primitives](https://media.ollin.art/examples/Shapes/Primitives/still-640.jpg?v=2cf14690)](Primitives/) | [![SVGImport](https://media.ollin.art/examples/Shapes/SVGImport/still-640.jpg?v=d457d6d3)](SVGImport/) | [![Scattered](https://media.ollin.art/examples/Shapes/Scattered/still-640.jpg?v=499a8bf5)](Scattered/) | [![Star](https://media.ollin.art/examples/Shapes/Star/still-640.jpg?v=3eff53ae)](Star/) |
| [Primitives](Primitives/) | [SVGImport](SVGImport/) | [Scattered](Scattered/) | [Star](Star/) |
| [![StraightSkeleton](https://media.ollin.art/examples/Shapes/StraightSkeleton/still-640.jpg?v=ebfed2c0)](StraightSkeleton/) | [![StrokeAlignment](https://media.ollin.art/examples/Shapes/StrokeAlignment/still-640.jpg?v=906e3ddc)](StrokeAlignment/) | [![StrokeJoinsAndCaps](https://media.ollin.art/examples/Shapes/StrokeJoinsAndCaps/still-640.jpg?v=02096cb2)](StrokeJoinsAndCaps/) | [![StrokeProfiles](https://media.ollin.art/examples/Shapes/StrokeProfiles/still-640.jpg?v=c2ed6e7d)](StrokeProfiles/) |
| [StraightSkeleton](StraightSkeleton/) | [StrokeAlignment](StrokeAlignment/) | [StrokeJoinsAndCaps](StrokeJoinsAndCaps/) | [StrokeProfiles](StrokeProfiles/) |
| [![Superellipse](https://media.ollin.art/examples/Shapes/Superellipse/still-640.jpg?v=5d1a3834)](Superellipse/) | [![Supershape](https://media.ollin.art/examples/Shapes/Supershape/still-640.jpg?v=5ce79b23)](Supershape/) | [![Triangles](https://media.ollin.art/examples/Shapes/Triangles/still-640.jpg?v=0c166e76)](Triangles/) |  |
| [Superellipse](Superellipse/) | [Supershape](Supershape/) | [Triangles](Triangles/) |  |

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
| [HobbySpline](HobbySpline/Sketch.swift) | the same drifting points threaded by the default spline and by Hobby's fit (`drawCurve(spline: .hobby)`), an open run on the left and a filled loop on the right, with `tension` and `curl` as parameters |
| [StrokeProfiles](StrokeProfiles/Sketch.swift) | one spiral at one weight drawn under each width profile (`strokeProfile`): taper, lift off, wedge, a turning calligraphy nib, and one defined by hand |
| [Superellipse](Superellipse/Sketch.swift) | a wall of superellipse plates, with one exponent moving the whole family from a pinched star through diamond, ellipse, and squircle to an almost-rectangle |
| [Supershape](Supershape/Sketch.swift) | one closed contour that moves through star, flower, and gear-like forms as slow sines sweep the 2D superformula, drawn over fading copies of its recent shapes |
| [SVGImport](SVGImport/Sketch.swift) | SVG import: the bundled rocket badge is drawn as authored (`loadSVG`/`drawSVG`), then used as geometry, with its outlines resampled into evenly spaced dots |
| [Triangles](Triangles/Sketch.swift) | the two `drawTriangle` forms side by side: an equilateral triangle that turns on its center, and an isosceles wedge that turns on its apex (SDF) |
| [Watercolor](Watercolor/Sketch.swift) | watercolor pigment made by deforming polygons (`Watercolor`, `drawShape`): three pools of interleaved translucent layers that glaze where they overlap, plus a clipped speckle for a granulated texture. Each variation starts a fresh sheet |
| [Brushes](Brushes/Sketch.swift) | marks made by repeating a shape along a path: `strokeBrush` replaces the continuous ribbon with a row of stamps, which take their size from `strokeWeight` and their color from the stroke |

Run one with `swift run Example-Shapes-<Name>`, for example `swift run Example-Shapes-Primitives`.
