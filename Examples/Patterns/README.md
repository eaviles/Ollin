#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Patterns</sup>

---

## Patterns

Grids and rule-based repetition.

| Example | What it shows |
|---|---|
| [Booleans](Booleans/Sketch.swift) | the four `Shape` set operations over the same two moving shapes — a turning star and an orbiting disc — each filled result real geometry that strokes and exports like anything drawn by hand (`union`/`intersection`/`subtracting`/`symmetricDifference`) |
| [DotGrid](DotGrid/Sketch.swift) | a grid of black/white dots woven by a modulo rule |
| [EnergyGrid](EnergyGrid/Sketch.swift) | columns sized by a moving "energy" share (`translate`, `drawRect`) |
| [HollowShapes](HollowShapes/Sketch.swift) | a grid of shapes breathing from solid into framed hollow rings (`hollow`/`solid`, SDF) |
| [LifeQuilt](LifeQuilt/Sketch.swift) | a four-layer Game of Life filling cells with triangular wedges, colored by a radial cosine palette (`drawTriangle`, SDF) |
| [Markers](Markers/Sketch.swift) | the five `drawPoint` markers, one per row, swept across sizes (`pointMarker`, SDF) |
| [NamedPolygons](NamedPolygons/Sketch.swift) | the named regular polygons turning in a labeled row (`drawPentagon`/`drawHexagon`/`drawHeptagon`/`drawOctagon`, SDF) |
| [Phyllotaxis](Phyllotaxis/Sketch.swift) | a sunflower seed-head — points at the golden angle marching outward by `sqrt(i)` — built into a `Circle` array and drawn with a single batch call, spinning slowly while the count breathes (`drawCircles`) |
| [Primitives](Primitives/Sketch.swift) | every `draw*` primitive, one per cell, turning slowly — a reference sheet for the whole drawing vocabulary |
| [ShapeMenagerie](ShapeMenagerie/Sketch.swift) | rhombus, vesica, moon, cross, and ring, one per row, with corner radius breathing (`drawRhombus`/`drawVesica`/`drawMoon`/`drawCross`/`drawRing`, SDF) |
| [StrokeAlignment](StrokeAlignment/Sketch.swift) | the same shapes stroked inside, centered, and outside their outline, weight pulsing (`strokeAlign`, SDF) |
| [StrokeJoinsAndCaps](StrokeJoinsAndCaps/Sketch.swift) | a zigzag turned with each join and a segment ended with each cap, weight pulsing (`strokeJoin`/`strokeCap`) |
| [Topography](Topography/Sketch.swift) | a breathing blob inset inward over and over until the region pinches out, each surviving ring stroked — contour lines that crowd where the form narrows; pure line work that plots straight to SVG (`Shape.offset(by:join:)`) |
| [Voronoi](Voronoi/Sketch.swift) | a field of noise-drifting sites partitioned into Voronoi cells, evened out with Lloyd relaxation and colored by a sweeping focal point — the cursor is a live site, so the cells crystallize around the mouse (`voronoi`/`lloyd`) |
| [WarpGrid](WarpGrid/Sketch.swift) | a checkerboard of rects warped under the mouse (`drawRect`) |

Run one with `swift run Example-Patterns-<Name>`, e.g. `swift run Example-Patterns-DotGrid`.
