# C. Coming from p5.js and Processing (`C-ComingFromP5.md`)

Size: 2,565 prose words, 5 `##` and 12 `###` sections, 254 lines. Appendix (no part). Opening figure: `Pulse.jpg` (line 43), a blue circle on white, the translated sketch.

## Sections

| Line | Heading | Words | Teaches / the reader makes |
|---|---|---|---|
| 5 | # C. Coming from p5.js and Processing (intro) | 189 | The model carries over; "a lookup page, not a lesson". |
| 13 | One sketch, twice | 191 | p5 `Pulse` beside Ollin; five differences. Blue circle. |
| 53 | The dictionary | 0 | Container for 12 tables. |
| 55 | The sketch and the loop | 147 | `setup`/`draw`, `canvasSize`, `time`, `deltaTime`, `frameRate`. |
| 70 | Shapes | 252 | `draw` prefix, radii, polygon, arc, cubic vs `drawBezier`, `drawCurve`. |
| 92 | Ink and color | 145 | hex, alpha, HSB initializer, `Color.mix`, enums. |
| 107 | Transforms and state | 113 | `pushState`/`withState`, radians, `.tau`. |
| 118 | Randomness and noise | 130 | `randomChoice`, `seed`, `fbm`, `signedNoise`, `loop:`. |
| 132 | Vectors | 125 | `Vector2` operators; values, not in place. |
| 148 | Everyday math | 96 | `map(clamped:)`, `clamp`, `uv`. |
| 158 | Text | 70 | `drawText`, `.middle`, three font kinds. |
| 168 | Images and pixels | 96 | `loadImage`, `drawImage`, subscript, render targets. |
| 179 | Mouse and keyboard | 99 | No `mouseDragged`, `previousMouse`, `isKeyDown`. |
| 191 | The bigger machines | 111 | GUI, filters, shaders, 3D, sound, each to a chapter. |
| 205 | Saving your work | 119 | Export flags, including SVG and web. |
| 218 | Different on purpose | 370 | `let`/`var` swap, types, modes to labels, clock, auto-clear, files. |
| 234 | Habits worth dropping | 210 | Seven habits. |
| 244 | Go deeper | 94 | Ch 1, Swift.md, Drawing, D, Examples. |

## What the appendix promises against what it delivers

Line 9 promises "entries point at chapters as they go"; four tables have no pointer (the loop, Shapes, Everyday math, Mouse and keyboard). Missing p5 staples: `createCapture` (Ch 30), `loadPixels`/`pixels[]` and `loadJSON`/`loadTable` (Ch 9), `textToPoints` (Ch 8), `beginContour`, Processing's `size()`. Nothing points to Ch 11 to 14, the Nature of Code material p5 readers bring.

Pitch or translation: the tables translate plainly; pitch leaks at lines 7, 90, 224, 237, 239, 249, 250. "Habits worth dropping" casts p5 idioms as bad habits, and four of its seven bullets repeat: `withState` (113, 236), degrees (114, 237), `time` over `frameCount` (50, 64, 228, 238), `Color.mix` (104, 239). Line 232 is the balanced model ("What you give up is the browser").

Lane: C stays out of E's; E line 63 repeats part of C's tables.

API spot-check (`API/Ollin.txt`): `drawEllipse`, `isKeyDown`, `previousMouse`, `Image(width:height:)` and its `[x, y]` get/set, `fbm(_:_:octaves:gain:)`, `lerp(to:_:)` are current. Two are stale:

- Line 172: `loadImage` "returns an optional"; it throws (`API/Ollin.txt:2299`).
- Line 200: no bare `camera()` exists (`camera(_: Camera3D)`, line 1967); Ch 21 opens on `cameraShowcase(radius:)` and `cameraControl()`.

Chapter pointers: all 14 linked chapters match current titles and content; none stale.

## Seams and catalog signs

- Lines 130 and 146, "Two more are worth meeting", "One habit is worth noticing": tacked on.
- Line 191, "The bigger machines": hides 3D, shaders, sound, GUI.

## Cold starts and dropped-in sections

- None found.

## Techniques given only through their API

- Line 199: `.filtered` and `.combined` are listed as `Shader` calls; they take a `Filter`/`Combine`, which a shader enters through `.shader(_:)`.
- Line 128, `fbm`: what layering does is unsaid.

## Concepts used before they are introduced

- Line 48: the computed-property override `override var canvasSize`; in neither Appendix A nor `Docs/Swift.md`.
- Line 175, subscript `img[x, y]`; line 116, `.degrees(d)`: not in Appendix A.

## Creative coding as a practice

- Line 241 (`@Param` over re-running), lines 207 and 232 (share an export, not a URL).
- Missing: live reload against the web editor's refresh; seeds stored in exports (Ch 31).

## Voice: the worst paragraphs

- Line 7, "Your instincts are right. Mostly the spelling changes.": reader prediction, fragment.
- Line 220, "It stings for a week."; line 237, "you won't miss it": reader prediction.
- Line 224, "A drawing can't be broken by a mode set three functions away.": pitch closer.
- Line 90, "The catalog runs well past p5's.": overselling.
- Line 250, "will feel like home": prediction.
- Lines 72 and 83, "wear a `draw` prefix", "ride in as an array": idioms. "worth" appears 4 times.

## Overlap with other chapters

- Line 222 repeats Appendix A line 81 almost verbatim ("tends to behave"), confirmed.

## Candidate moves

- Fix line 172 (the throwing load, with `try?`) and line 200 (`cameraShowcase`/`cameraControl`).
- Add the missing rows and a short block sending Nature of Code readers to Ch 10 to 14.
- Fold "Habits worth dropping" into "Different on purpose", cutting the four repeats.
- Add chapter pointers to the four tables that have none. Rename "The bigger machines".
