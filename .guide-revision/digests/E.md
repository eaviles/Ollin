# E. Coming from openFrameworks and OPENRNDR (`E-ComingFromOpenFrameworksAndOPENRNDR.md`)

Size: 2,876 prose words, 4 `##` and 18 `###` sections, 542 lines. Appendix (no part). No figure; opens on lineage (line 7) and scope (line 9).

## Sections

| Line | Heading | Words | Teaches / the reader makes |
|---|---|---|---|
| 5 | # E (intro) | 122 | Lineage; "shorter than Appendix C"; C's tables serve. |
| 11 | From openFrameworks | 0 | Container. |
| 13 | The app becomes one class | 180 | Three files to one class; no `update()`; `time`/`deltaTime`. |
| 63 | The names you type every day | 170 | oF-to-Ollin table. |
| 82 | Fill and stroke are separate inks | 86 | Two inks; AA and blending always on. |
| 107 | One scope for the matrix and the style | 52 | `withState` for both push pairs. |
| 135 | An ofFbo is a layer | 160 | `makeRenderTarget`/`withTarget`, `filtered`; `Feedback` named. |
| 170 | Shaders: one function, in Metal | 160 | `shade`, `info`, `params`; `--from-shader`. |
| 205 | 3D: the camera is a call | 114 | `cameraControl`, `pointLight`, `drawBox`; `Mesh`, `loadMesh`. |
| 235 | C++ habits that change | 126 | Struct copies in a loop; write through `.indices`. |
| 257 | Addons become satellite modules | 232 | 10-row addon table; ofxGui against `@Param`. |
| 300 | projectGenerator becomes ollin new | 119 | `ollin new`, live loop, `--keep-clock`. |
| 312 | From OPENRNDR | 0 | Container. |
| 314 | From Kotlin to Swift | 107 | `val`/`let`, lambdas, `it`/`$0`, data class vs struct. |
| 320 | The program becomes a sketch | 72 | `program`/`extend` to `setup`/`draw`; events as overrides. |
| 364 | No drawer to pass around | 111 | `Drawer` internal; helpers extend `Sketch`. |
| 388 | The value types are close by design | 206 | Color/Vector/Contour table; `point(at:)` by length. |
| 407 | isolated, and the degrees trap | 57 | `isolated` is `withState`; `rotate` in radians. |
| 422 | Render targets and the compositor | 147 | `compose` in `draw()`, filters as values, `aside`. |
| 464 | Shade styles | 109 | Gradients as paint; shader plus mask. |
| 486 | The orx modules | 299 | Table, then parameters, noise seeds, olive, `extend`, Syphon, Gradle. |
| 525 | What stays behind | 159 | Platforms, browser, community addons. |
| 531 | Go deeper | 84 | C, A, Ch 16, 17, 21, D. |

## What the appendix promises against what it delivers

Line 9: "shorter than Appendix C on purpose". False: 2,876 prose words against 2,565, 542 lines against 254. It also says C's tables serve the everyday calls, yet line 63's table repeats about ten of them (`time`, `deltaTime`, `noClear`, radians, `signedNoise`, `map(clamped:)`, `Vector2`/`Color`). Each big move gets a code pair; line 525 names the costs honestly.

Pitch or translation: mostly translation; pitch at lines 7, 166, 298, 310, 460.

API spot-check (`API/`): `cameraControl(radius:)`, `drawBox(size:)`, `pointLight(_:at:)`, `piece(from:to:)`, `crossings(with:)`, `signedSimplexNoise`, `SyphonServer(name:)`, the OSC/MIDI class names, `ollin new --with osc,params`: all current. Line 405's `c.pointAtLength(...)` is OPENRNDR's, but reads as an Ollin call.

Chapter pointers (Ch 1, 6, 15, 16, 17, 21) all resolve; two are stale and one set is missing:

- Line 233, "`loadMesh` … [Chapter 21] starts there": Ch 21 has no `loadMesh`; that is Ch 22. Line 537 also gives Ch 21 "meshes".
- Line 310 cites Ch 1 for `--keep-clock`; only Ch 31 covers it.
- The addon table (261 to 272) points only to Docs, never to Ch 11, 28, 30, 31 or 32.

## Seams and catalog signs

- Line 486, "The orx modules": six unrelated topics after its table; the heading does not find `SketchExtension` or Syphon.
- Line 407: one heading, two topics.
- "in the openFrameworks half" four times (409, 462, 499, 523).

## Cold starts and dropped-in sections

- Line 509, `SketchExtension`: arrives mid-orx, no pointer to Ch 31's section on it.
- Line 366, "a decision the project will make before 1.0": project-internal note.

## Techniques given only through their API

- Line 168: `makeFeedback()`/`withFeedback`, the classic trails FBO, has no code pair. Line 482: `.radial`, `.alongPath` are names only.

## Concepts used before they are introduced

- Line 201, "How many layers the function reads": this assumes shader inputs, which Ch 17 teaches.

## Creative coding as a practice

- Lines 298, 310, 529: inspector write-back, the live loop, community addons.
- Missing: installations and performance, core oF uses; no pointer to Ch 32 or Ch 31's live coding.

## Voice: the worst paragraphs

- Line 7, "openFrameworks showed how plain …, and OPENRNDR showed what …": matched clause pair, lineage pitch.
- Lines 166 and 460, "costs nothing": overselling, repeated.
- Line 201, "ride along as `params`": idiom.
- Line 316, "easy to think of it as Java. The programs are written in Kotlin, though": setup and reversal.
- Line 239, "One habit changes meaning, and it's the loop over your particles.": punchline shape.

## Overlap with other chapters

- Lines 63 to 80 against Appendix C's tables (confirmed).
- Inside E: `Filter` catalog three times (168, 269, 490); OSC/MIDI/Syphon three times (264, 497, 509).
- Lines 235 to 255 against Appendix A line 161.

## Candidate moves

- Cut line 9's claim; trim line 63's table to oF-only names.
- Split "The orx modules": `extend`/Syphon get a heading linking Ch 31; olive moves beside line 310.
- Add a chapter column to the addon table and a Ch 32 pointer.
- Point lines 233 and 537 to Ch 22, line 310 to Ch 31. Add a `Feedback` pair at 168; cut line 366.
