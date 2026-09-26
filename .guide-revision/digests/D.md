# D. The complete toolbox (`D-CompleteToolbox.md`)

Size: 10,025 prose words (nearly all in table cells), 19 `##` and 0 `###` sections, 438 lines, 326 table rows. Appendix. No figures.

## Sections

| Line | Group | Words | Rows | Contents |
|---|---|---|---|---|
| 5 | (intro) | 188 | 0 | "Everything Ollin can do, one line each"; index and map of the untried. |
| 13 | The ideas underneath | 264 | 7 | The seven `Docs/Concepts` pages (Idea, What it says, Guide, Reference). |
| 27 | The sketch and its window | 567 | 21 | Lifecycle, clock, input, `@Param`, cues, CLI tools, importers. |
| 53 | Drawing | 466 | 16 | Shapes, ink, transforms, blend, accumulation, strokes, HDR, gradients. |
| 74 | Color | 114 | 5 | Values, OKLab, spectral, palettes, colormaps. |
| 84 | Text and images | 470 | 17 | Text, images, pixels, image techniques, data, live data, weather. |
| 106 | Geometry you can hold | 849 | 28 | Value types, complex, paths, booleans, curves, assorted techniques. |
| 139 | Motion, math, and randomness | 188 | 8 | Math helpers, loops, easing, random, noise. |
| 152 | Generative systems | 1,343 | 53 | Sampling, image generators, meshes, tiles, growth, fractals, CA. |
| 210 | Physics and simulation | 452 | 17 | 2D and 3D physics, IK, n-body, crowds, GPU life, fluids. |
| 232 | Layers and effects | 797 | 24 | Targets, filters, looks, fields, fractals, simulation fields. |
| 261 | Shaders and compute | 141 | 6 | Shaders, library, chains, compute. |
| 272 | 3D | 1,184 | 37 | Camera, lights, materials, AA, instancing, ocean, drainage, billiards. |
| 314 | Sculpting with fields | 102 | 4 | SDF 2D and 3D, `sculpt`, fractal fields. |
| 323 | Depth and the phone | 157 | 5 | RGBD, captures, capture app, fusion. |
| 333 | Sound and control | 623 | 19 | Analysis, MIDI, OSC, serial, BLE, MQTT, room, haptics. |
| 357 | Making sound | 290 | 4 | Synthesis (one 119-word row), composition, MIDI files, sonification. |
| 366 | Seeing and video | 174 | 8 | Trackers, video, slit scan. |
| 379 | Sharing and performing | 1,119 | 35 | Exports, replay, automation, fabrication, interop, live coding. |
| 419 | Installations | 529 | 12 | DMX, lasers, app wrappers, phone, unattended, profiling. |

## What the appendix promises against what it delivers

- Line 7 promises "the guarantee that nothing shipped goes unmentioned"; line 9 says a missing row means a missing feature. Neither holds. Sections with no row: Ch 25 characters (13), vehicles (65), ragdolls (159), cloth (201), ropes (298), water (344); Ch 24 queries (83, 114), collision groups (163), degrees of freedom (207), snapshots (361); Ch 22 normal and height maps (192, 230), cutting solids (253), decals (391), anisotropy (439), glass (529), clearcoat and sheen (569), thin film (589), subsurface (611); Ch 26 global illumination (305); Ch 21 light sets (352); Ch 29 patching (67), sampled instruments (241), tunings (698).
- Cause: `Guide/PLAN.md` 307 says D is generated from the coverage matrix, which is keyed by Docs page. A page covering many capabilities becomes one row: `Physics3D.md` (row 217 serves Ch 24 and 25), `3D.md` materials (291 names only "metal and gloss"), `Synthesis.md` (361, 119 words).
- "One line each" fails at 361, 362, 129, 350, 363 (47 to 119 words).

## Guide pointers

- Every Guide cell is a chapter-level link (`[Ch N](file.md)`), never a section anchor, so no row names a heading that could have gone stale. The cost: 37 rows send the reader into Ch 31 and 31 into Ch 15 with no section.
- Checked over 60 rows by grep. Matches include 39 (Ch 31 887), 60 (Ch 6 114), 102 (Ch 9 387), 104 (Ch 16 608), 120 (Ch 26 173), 219 (Ch 11 296), 243 (Ch 16 318), 259 (Ch 17 320), 280 (Ch 18 169), 296-301 (Ch 26 253 to 493), 343 (Ch 28 240), 350 (Ch 32 60), 362 (Ch 29 612), 377 (Ch 30 459), 424 (Ch 31 327), 434 (Ch 32 105).
- Line 63, Accumulation, Ch 19: no hit for accumul, `noClear` or `Accumulator`; `Accumulator` is taught in Ch 16.
- Line 91, Atlas text, Ch 8: `textMode(.atlas)` absent; "atlas" appears once, in the examples list (345).
- Line 64, Depth of field from light, Ch 16: `LineSpray` and `Bokeh` are only in Ch 20 (53 to 59); Ch 16 has `developed` (747) and a Go deeper link.
- Line 304, Camera control and moves, Ch 21: `CameraMove` absent; only Go deeper (628) names "the cinematic move catalog".
- Line 149, Noise, Ch 14 for `curlNoise`: Ch 14 teaches `curlField` (127).
- Line 24, Light and color, Ch 16 only: Ch 9 175 is where linear light is taught.

## Group names against how a reader looks

- The first half groups by kind (Drawing, Geometry you can hold, Generative systems); the second half reuses chapter titles (Layers and effects, Sculpting with fields through Installations). Neither rule is kept.
- Misfiled: 280 Billiards (2D, Ch 18) and 279 Drainage under 3D; 96 a feed with no camera and 101-103 tables, live data, weather under "Text and images"; 350-352 MQTT, remote, room (Ch 32) and 354 haptics under "Sound and control"; 424, 427-428 lasers and phone (Ch 31) under Installations; 411 screen capture (Ch 30) under Sharing; 249-250 escape time and domain coloring, 254-258 simulation fields under "Layers and effects"; 120 Shadow art (a 3D solid) under Geometry.
- One topic split across groups: Lenia 207 and 254; watercolor 133 and 258; caustics 123 and 289; fractals 190, 249, 321; hulls 134 and 170; steering 196 and 227; randomness 148 against walks 173, percolation 163, blue noise 156.
- "Generative systems" holds 53 rows with no inner order; "Color" has 5, while gradient paint (72) sits under Drawing.

## Index or pitch

- Mostly an index; many cells lead with API names (31, 34, 35), not the plain-words line PLAN.md 307 asks for.
- Pitch vocabulary: "real" 13 times (110 "real operators", 285, 290, 297, 386 twice); 69 "for (almost) nothing"; 269 "without touching the CPU"; 292 "on any Mac, no ray tracing needed"; 293 "in one call and no lights"; 296 "the actual scene"; 330 "and the air it is standing in"; 343 "rides the show's own position" (idiom); 7 "the guarantee".

## Overlap with other chapters

- `Docs/README.md` "The catalog" (line 11) is a second capability index grouped by Docs area (Core, Drawing, Generators, Helpers…), and Guide README Contents a third; D's groups match neither (confirmed).

## Candidate moves

- Regroup by one rule: the Guide's chapters (so group and Guide column agree) or the Docs areas (so D mirrors the catalog).
- Generate one row per taught capability, not per Docs page; split 217, 291, 361 and add the missing Ch 22, 24, 25, 26, 29 rows.
- Fix pointers at 63, 91, 64, 304, 149, 24; add section anchors for Ch 15 and Ch 31 rows.
- Merge the split topics; give the data rows a group; soften lines 7 and 9; strip the pitch words.
