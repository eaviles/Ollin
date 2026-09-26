# B. Just enough math, visually (`B-JustEnoughMath.md`)

Size: 6,675 prose words, 15 `##` and 68 `###` sections, 604 lines. Appendix. No hook figure; every entry is one picture plus one paragraph (57 to 154 words).

## Sections

| Line | Group | Words | `###` | Entries |
|---|---|---|---|---|
| 5 | (intro) | 163 | 0 | Promise: every math idea, picture, plain words, chapter pointer; built for dipping. |
| 13 | Where things are | 370 | 4 | Canvas y-down; normalized 0…1; Vision point to canvas; 3D world frame. |
| 48 | Angles and circles | 479 | 5 | Radians and tau; angle plus radius; sine; phase; n copies. |
| 91 | Fractions, mapping, and wrapping | 357 | 4 | lerp/map; `%`, fract, pingPong; perfect loop; grid-to-image sampling. |
| 120 | Shaping a value | 225 | 2 | Shaping curves (step, smoothstep, squaring); exponential decay. |
| 137 | Randomness | 449 | 5 | Seeds; threshold probability; uniform vs Gaussian; clumping; random walk. |
| 184 | Noise | 485 | 5 | Coherence; scale as zoom; field plus time; octaves; worley cells. |
| 231 | Moving the paper | 201 | 2 | Transforms move the frame; compounding moves. |
| 248 | Vectors, motion, and forces | 770 | 7 | Arrows; motion trio; steering; F = ma; spring; Verlet; deltaTime. |
| 310 | Fields and following them | 339 | 4 | Field as rule; Euler tracing; iterated maps; optical flow. |
| 342 | Local rules, global structure | 775 | 8 | Neighborhoods; Life; recursion; L-systems; WFC; parameter map; escape time; density. |
| 410 | Shapes as regions | 309 | 4 | Booleans; offsets; convex hull; Voronoi/Delaunay. |
| 442 | Color and light as numbers | 467 | 5 | Perceptual mixing; luminance; blend arithmetic; tone mapping; feedback. |
| 488 | Per-pixel thinking and distance | 608 | 6 | Shader as function; SDF; level sets; min/max/smooth min; sphere tracing; folding. |
| 544 | Into three dimensions | 433 | 5 | Orbit camera; perspective and depth test; unprojection; pose; occlusion voids. |
| 582 | Sound as numbers | 237 | 2 | Spectrum with log bands; beats as events. |

## What the appendix promises against what it delivers

Line 7 promises "Every math idea in the guide" and "If a page anywhere loses you, the missing piece is here". The form holds: all 68 entries have an `<img>` or `<picture>` and a chapter link. The coverage does not (gaps below).

Six pictures are B's own; 62 reuse chapter figures. Some show a finished piece, not the idea: 108 RingPulse.gif (no whole-cycle diagram), 131 Comets (no decay curve), 453 PixelSampling (no channel weights), 327 Plates, 114 TypeMosaic, 570 SweepFuse.

## Chapter pointers

- Every chapter number in B matches its topic (grep-checked, for example Ch 1 278, Ch 3 337, Ch 9 560, Ch 12 40, Ch 16 839).
- Line 65: `polar(angle, radius, around:)` and `angles(12)` appear in no chapter.
- Line 325 names "Euler integration", a term Ch 14 never uses. Line 384 "Chapter 13 closes with it": overlapping WFC (Ch 13 373) follows.
- Line 460: weights applied to sRGB values; Ch 9 120 says `c.luminance` uses linearized components.
- Reverse: Ch 22, 31, 32 never link B. Ch 18 410 links "Local rules", but its "Iterated maps" (327) sits in "Fields". Ch 29 1053 links "Sound as numbers", which covers only Ch 28's analysis.

## Math the chapters lean on that B lacks

- Confirmed absent: gcd (Ch 7 104); square-root spread and a distribution's tail (Ch 4 206, 208; B's walk at 182 stops at "a path appears"); quadratic growth (Ch 6 298, Ch 3 201); linear light, sRGB, gamut (taught at Ch 9 175, Ch 16 767; B never names them); damped oscillator (Ch 3 252; B's spring at 286 has no damping or overshoot).
- Also absent: complex numbers (Ch 17 172, Ch 18 203, 266; B's 402 says "the formula's two numbers" without them); atan2 (Ch 15 423, Ch 22 708); Fourier outside sound (Ch 15 211, Ch 16 443, Ch 23 226); log scale for counts and log spirals (Ch 18 49, Ch 12 133); sqrt and the golden angle (Ch 15 92); surface normals (Ch 21 28, Ch 22 192); inverse square (Ch 21 326); circle inversion (Ch 18 77); downhill search (Ch 14 182); barycentric (Ch 23 161); tunings and envelopes (Ch 29 698, 42).
- B has: smoothstep, lerp, radians, modulo, fract, exponential, probability, Gaussian, distance field, projection, luminance, log hearing. No chapter needs dot product, matrices, derivative or quaternion.

## Order for a reader arriving from a link

- Chapters link groups, not entries (only 4 entry anchors are used), so the reader scans up to 8 entries.
- Groups mix chapters: "Where things are" runs Ch 1, 17, 30, 21. Color (Ch 2) is group 12 (442). "One second is one second" (Ch 3) closes the Vectors group (301). Level sets (508) sits about 390 lines from shaping curves (122).
- The heading "Local rules, global structure" is both the group (342) and an entry (353); the group also holds recursion, escape time, density and parameter maps, which are not local rules.
- Entries stand alone, which suits dipping; callbacks at 486 and 553 assume a straight read.

## Concepts used before they are introduced

- Line 257 Pythagoras (no picture); 471 linear light, never named; 524 "the k dial"; 568 focal length.

## Creative coding as a practice

- Seeds (146), parameter maps (393), GIF loops (112); enough for an appendix.

## Voice: the worst paragraphs

- Line 146, "`random()` isn't dice… a sibling, not a variation": false negatives.
- Line 193, "is not a roll… the entire difference": false negative, overselling.
- Line 580, "They're not errors… the voids yawn open": false negative, poetry.
- Line 402, "literally a loop counter, colorized"; 524 "The magic option": overselling.
- Lines 112 "live and die by it", 118 "wearing work clothes", 240 "ride on earlier ones": idioms.
- Lines 299 "quiet engine", 331 "made luminous", 408 "trades grain for cream": poetry.
- Lines 9, 477: punchline pairs. Counts: "exactly" 16, "honest" 3, "one rule/question" framing 11.

## Overlap with other chapters

- "Where things are" duplicates `Docs/Concepts/Coordinates.md` (D line 20 cites both); linear light lives in `Docs/Concepts/Light.md` and Ch 9 175, not B.

## Candidate moves

- Add entries for the gaps, each in the group its chapter links; linear light goes ahead of luminance.
- Split "Local rules" into local rules and iteration; move iterated maps, escape time and density together; rename the duplicate heading at 353.
- Move deltaTime (301) next to sine; cross-link level sets and shaping curves. Diagrams for 108, 131, 453.
- Point chapter "Go deeper" lines at entry anchors; tie or drop `polar`/`angles` (65).
