# Guide revision: the proposal

Session 1 of the Guide revision, 2026-09-26, on `main` at `a554d02`. This file holds the recommendations (R1 to R34), the evidence for each, what each costs, and, once @eaviles has ruled, the ruling beside each one. The evidence cites the digests under `digests/` by chapter and line (for example "12:103" is Chapter 12, line 103, at `a554d02`). Line numbers go stale as the tranches land, so a later session re-reads the digest before trusting one.

## What the review found, in one page

1. **The finished piece composes a small part of its chapter, almost everywhere.** In nearly every chapter the "Putting it together" sketch uses less than half of what the chapter teaches; Chapter 10 is the clear exception. Chapter 7's piece uses 1 of 11 technique sections, Chapter 19's uses 2 of 18, Chapter 15's uses 6 of 27 subsections, Chapter 26's leaves out 64% of the prose, and Chapter 31's uses about a tenth. Seven pieces still claim to use everything (3:9, 5:208, 6:357, 14:200, 15:839, 29:1019, 31:1114).
2. **The shape is the same every time: the original chapter, then a tail.** Each chapter opens with the steps its first author wrote toward the piece. The capabilities added later sit after those steps, or wedged between them, one `##` each. The scars are visible:
   - Counts and ordinals that went stale when a section was inserted: 4:142, 7:95, 11:289 against 11:505, 12:42, 13:9 and 13:242 to 326, 18:85, 19:244 and 19:392 to 435, 20:119 to 201, 25:598, 26:218, 29:350, 30:280, 32:571.
   - Sections that defend their own membership ("it belongs here even though it is not a field at all", 14:180; "Here is why keyframes sit in this chapter", 31:991): more than twenty, in seventeen chapters.
   - Seams announced in the prose ("the first half of GPU simulation", 19:9; "The hands come next", 28:196; "the two halves of that", 29:11).
   - Headings that name a metaphor instead of the technique, so a reader can't find pursuit curves (12:103), shape grammars (13:141), line integral convolution (14:129), IES profiles (21:284), or optical flow on the phone (27:404) from the contents.
3. **Several sections sit in the wrong chapter.** Wave function collapse is in Chapter 13 and admits it "grows nothing" (13:352); Chapter 7 teaches the same edge agreement. Chapter 16 uses shaders (16:213, 16:298, 16:418) one chapter before the shader gate. Chapter 27 teaches hands, gaze, text, attention and flow on the phone before Chapter 30 teaches them on the webcam. Chapter 26's second half (5,471 words) is about traced light and draws no field. Live network data sits in the pictures chapter (9:387 to 498). The cost row a reader needs in Part II sits in the last chapter (32:105). There are about fifty such moves in all (R9, R10).
4. **Techniques arrive as API calls.** Many sections give a call and its parameters without saying what the technique is, where it comes from, or what an artist uses it for: the color harmonies (2:150), fBm (5:142), inverse kinematics ("IK" is never expanded, 11:298), curl noise (14:127), the gradient map every grid simulation uses (19:129), music theory from scales to chords (29:552 to 711), and more listed per digest.
5. **Nothing introduces creative coding itself.** No page says what creative coding is, who does it, what people make with it, or how they work at it. The working practice (sketch, tune, keep variations, finish, export) appears only as scattered asides: 4:57 states it well, then the chapter's own piece bypasses the workflow it just taught (4:235). No chapter walks a sketch through to a finished print or video (31:547 has the calls, not the practice).
6. **The voice drifts in the later chapters.** "Worth" appears 165 times; 122 of those are in Parts IV and V, which hold under half of the prose. "Exactly" appears 300 times, "honest" 62, and "the whole" or "the entire" about 380. False negatives, bold aphorisms and figure-provenance asides ("it cost the figure above a few attempts", 16:604) cluster in the same chapters.
7. **The openers repeat.** 23 of 32 chapter openers end "by the end you'll have built the sketch above" or close to it. 15 open a paragraph with "Chapter N did X. This chapter does Y", three running at 22, 23 and 24. The known negation hook is still back to back: 18 ("Nobody drew the fern") then 19 ("Nobody drew those corridors."), and it returns at 22, 23 and 32.
8. **The front door and the appendices have drifted.** The README contents lines no longer match ten chapters (12 still ends "a line that grows into coral", which moved to 13; 13 still lists the chaos game, which moved to 18). "How to read it" calls Part III the shortest part (Part II is, at 30,750 prose words against 33,522) and gives page counts that don't track the parts. Appendix B lacks the gcd, a distribution's tail, linear light, damped springs, complex numbers, surface normals and pitch. Appendix D promises "nothing shipped goes unmentioned" (D:7) and has no row for characters, vehicles, cloth, glass, subsurface, global illumination or tunings. Appendix A misses `try`, `&`, key paths, `zip` and implicitly unwrapped optionals, all of which chapters type.
9. **Accuracy defects turned up on the way.** Stale API names in prose or listings (16:903 `intensity` for `amount`; 19:535 and 22:389 `strength` for `amount`; 23:495 a `t:` label; 25:34, 526, 584 `move` and `world.step`; 25:264 `rotation:`; 9:418 `updates` for `updateCount`), about fifteen chapter pointers aimed at the wrong chapter, and a dozen false statements (13:53 counts 512 tips on a 256-tip tree; 24:44 and 24:564 contradict each other). R12 collects them.

The sentence-level meters are fine, as expected. The trouble is order, placement, and what a chapter promises against what it delivers.

## Cause, and what the ship checklist has to do with it

The checklist in `CLAUDE.md` asks each new capability to be taught in a chapter in the same commit, to at least `shown`. That rule keeps the guide current, and it is also the mechanism that produced most of the above: each session added one correct `##` to the chapter its feature was assigned to, never touched the piece, the intro, or the README contents line, and passed every gate. So the rule itself produces the dropped-in feel. R33 and R34 give it a standard landing place (a family section after the piece) and a cap that turns growth into a structure review instead of a longer tail. The floor (`shown`) can stay.

## Group 1: the overall map

The current map is five parts and 32 chapters. The recommendation is one renumber tranche that makes four changes, and keeps every other chapter's number. The chapters that change number are 16, 17, and every chapter from 27 on. Chapters 1 to 15 and 18 to 26 keep their numbers and URLs.

Proposed map, with every option in this group approved:

| Part | Chapters |
|---|---|
| I. Seeing something move | 1 Hello, Ollin · 2 Color · 3 Motion and time · 4 Randomness · 5 Noise · 6 Grids and repetition · 7 Tiles · 8 Words · 9 Pictures and data (unchanged) |
| II. Systems that come alive | 10 Vectors · 11 Forces and physics · 12 Flocks and swarms · 13 Growing things · 14 Fields and flow · 15 Shapes as material (unchanged) |
| III. Pixels and light | **16 Your first shader** (was 17) · **17 Layers and effects** (was 16) · 18 Iterated forms · 19 Simulations on a grid · 20 Simulations made of particles |
| IV. The third dimension | 21 3D, gently · 22 Meshes, maps, and materials · 23 Landscapes · 24 Worlds with weight · 25 Characters, vehicles, and cloth · 26 Sculpting with fields · **27 Traced light** (new, from 26 and 31) |
| V. The world coming in | **28 Seeing** (was 30) · **29 Depth and the iPhone** (was 27) · **30 Listening** (from 28) · **31 Controls and signals** (from 28, with 9's live data) |
| VI. Out into the world | **32 Making sound** (from 29) · **33 Music by rule** (from 29) · **34 Finishing a piece** (from 31) · **35 Performing** (from 31) · **36 Installations** (was 32) |

With only R1 to R3 and R5 approved (no sound splits), the guide has 34 chapters: 28 Seeing, 29 Depth, 30 Sound and control, 31 Making sound, 32 Finishing a piece, 33 Performing, 34 Installations.

### R1. Swap Chapters 16 and 17, so the shader gate opens Part III

- **What changes.** "Your first shader" becomes Chapter 16 and "Layers and effects" Chapter 17. The shader chapter introduces `generate(...)` itself in one sentence (it is the only thing its core needs from the layers chapter, 17:44). The layers chapter then treats every filter as a shader the reader can already read.
- **Reader problem.** Chapter 16 uses the shader chapter's material before it exists: `uv(of: mouse)` at 16:213, `generate(myShader)` at 16:298, a hand-written Metal `shade` with `sample` at 16:418 to 429, and `.gyroid` at 16:577. The README calls 17 Part III's gate (README line 41), while Parts II and IV open on their gates (10, 21). The shader chapter's core (17:11 to 108, about 780 words) needs nothing from Chapter 16 except `generate`.
- **Cost.** A renumber of two chapters (their URLs, clips, and hero cells swap). A handful of "Chapter 16"/"Chapter 17" sentences in both files and in Chapters 19 and 20 read differently afterwards. No new figure. Part of tranche T2.
- **Risk.** Low. The shader chapter's tail (chains, GLSL import) leans on layer vocabulary; those sections move after the piece (R11) and point forward.
- **Keep-numbers alternative.** Move Chapter 16's three shader-dependent passages (the antialias section 16:287, the distance-field listing 16:377 to 437, the design generators 16:566 to 582) into the shader chapter's tail, and fix the README's gate sentence. It costs no renumber and leaves the gate second in its part.

### R2. Move Chapter 26's traced-light half into a new Chapter 27, "Traced light"

- **What changes.** Lines 26:253 to 515 (ray-traced and glossy reflections, global illumination, caustics, temporal and specular anti-aliasing, motion blur, lens flare, upscaling, frame interpolation) become their own chapter at the end of Part IV. The path-traced still (31:46) joins it, and so do the camera pieces from Chapter 21 (defocus and aperture blades 21:516, screen-space reflections 21:525). Chapter 26 keeps its field half and its piece, Molten.
- **Reader problem.** The half is 64% of Chapter 26 (5,471 words); its twelve figures draw no field and its prose names fields twice (26 digest). It was written as a sequel to Chapters 21 and 22 ("every light in the last two chapters", 26:307, now means the physics chapters). Chapters 21 and 22 point forward to it four times (21:523, 21:525, 22:550, 22:587).
- **Cost.** Every chapter from 27 on renumbers (they renumber under R3 anyway). One new finished piece and hook: a room that composes bounce light, a glossy floor, glass caustics, a flared lamp and a moving object (figure drafted in the cloud, rendered on the Mac). New credits paragraph (the missing ones are in `ATTRIBUTION.md`: DDGI, caustics, TAA, motion blur). Coverage rows for about ten Docs pages change home chapter. Part of T2; the prose around the new piece waits for the render.
- **Risk.** Medium: a new chapter needs its full anatomy, and until the piece renders it ships with an HTML comment where the hook goes.
- **Lighter alternative (26 digest).** Reflections, GI and caustics go after Chapter 22's "Glass"; flare, blur and both anti-aliasing sections go beside Chapter 21's depth effects; upscaling and interpolation go to the performance section. No new chapter, but Chapters 21 and 22 (already 8,000 and 10,700 words) grow into the catalogs R11 is trying to undo.

### R3. Split Chapter 31 into "Finishing a piece" and "Performing"

- **What changes.** Chapter 31 (17,330 words, 31 `##`, more than twice the upper range) becomes two chapters.
  - **Finishing a piece**: the files (stills, render scale, EXR, video and GIF, alpha, frame rates, slow motion, settle), reproducibility and passing parameters back in, describable output, the web page (trimmed), paper and machines (SVG and PDF, the 3D line drawing, G-code, embroidery and DXF folded together, separations, soft proof), and the 3D exports (print, USDZ, spatial video). It opens on the working practice (R19) and ends on a new piece: one keeper taken through to a poster, a loop, and a plot, with its recipe read back.
  - **Performing**: live coding, cues, the take, replay, keyframes, the timeline panel, parameters as rules, and the live feeds out (Syphon, the virtual camera). It keeps the current hook and piece (the set in five evaluations), extended with a cue and a take so it composes every section.
  - Out of Chapter 31 entirely: the path-traced still (to 27, R2), the laser (to Installations, beside DMX), haptics (to Controls and signals), and the handing-over sections (extension package, `SketchExtension`, the phone) to Installations (R10).
- **Reader problem.** The piece uses about 1,700 of 17,330 words (31 digest). A reader who wants to plot a drawing reads past live coding, and one who wants to perform reads past G-code. The chapter teaches the calls of finishing and none of its practice (31:547 against 4:57).
- **Cost.** Part of the Part V renumber. One new finished piece and hook for "Finishing a piece". About 1,500 words of reference-like detail move to Docs (the list of what crosses to the web page at 31:256, the frame-rate grid at 31:141, the `PaperSize` list at 31:274, codec detail). About twenty coverage rows change home. Two sessions of the chapter tranche, plus the Mac render.
- **Risk.** Medium. `CAPABILITIES.md` and several `Docs/` pages point at `Guide Ch 31 § *Heading*`; every one is re-pointed (check-links enforces it).
- **Keep-numbers alternative.** Keep one chapter and regroup it into four `##` groups (files, paper and machines, 3D, the stage), move the handing-over sections to Chapter 32, and cut to Docs. It would still be about 12,000 words with a piece that composes one group.

### R4. Split the two sound chapters at the seams they already name (optional, separable)

- **R4a. Chapter 28 into "Listening" and "Controls and signals".** "The hands come next" (28:196) joins two chapters: hearing (amplitude, spectrum, beat, pitch, speech, sound events) and controls (MIDI, OSC, OSCQuery, binding, TUIO, game controllers, serial, Bluetooth). The piece, Resonator, uses 28:11 to 85 and none of the controls, so the "playable instrument" can't be played as written (28 digest). "Listening" keeps Resonator as its piece; "Controls and signals" gains the live data from Chapter 9 (`DataFeed`, `PushFeed`, `Weather`, 9:387 to 498), haptics from Chapter 31, and MQTT's reading half from Chapter 32. It needs a new piece: a playable instrument bound to a controller, an OSC fader, and a data feed.
- **R4b. Chapter 29 into "Making sound" and "Music by rule".** The chapter names its own split (29:11, 29:504). Its piece, the music box, composes the second half and about eight of 23 teaching sections. "Music by rule" keeps the music box and adds swing, a progression, and a written `.mid`; "Making sound" needs a new piece (the digest suggests a board of drawn outlines and strings struck, plucked and bowed with the mouse, through an effects chain and a drawn room). The pitch primer (R21) goes at the head of "Music by rule".
- **Cost.** Each adds one chapter inside the Part V renumber (no extra URL cost beyond R3), one new finished piece, and about one chapter session. Without them the guide has 34 chapters, and Chapters 28 and 29 get the in-place treatment of R11.
- **Why optional.** Both chapters can be made to read in order without splitting (28 by naming its spine, "every source gives a level, a moment, and a bind", early instead of at 28:503; 29 by moving the effects block after the sources). The split serves the reader better; the in-place fix is cheaper.

### R5. Reorder Part V so Seeing comes first, and split Part V into two parts

- **What changes.** Seeing (the webcam, every Mac has one) opens Part V, then Depth and the iPhone, then the sound and control chapters. Part V becomes "The world coming in" (Seeing, Depth, Listening, Controls) and Part VI "Out into the world" (Making sound, Music by rule, Finishing, Performing, Installations).
- **Reader problem.** Chapter 27 teaches hands, gaze, text, attention and flow in the form that needs a phone (27:328 to 423), before Chapter 30 teaches the same trackers on the webcam; Chapter 30 never mentions the phone (30 digest). Four earlier chapters already use Chapter 30's API (16:602, 22:500, 27:406, 28:132). With Seeing first, the phone streams become the phone versions of trackers the reader already knows, and they shrink to that. A single Part V of eight or nine chapters mixes inputs and outputs; two parts say which is which.
- **Cost.** No extra URL cost (Part V renumbers under R2 anyway). The README part list, `PLAN.md` briefs, and the hero grid (see below) change. Part names are prose only.
- **Risk.** Low.
- **Stronger variant (30 digest).** Put Seeing's camera core right after the layers chapter, where readers who want interactive pieces meet it sooner. That renumbers everything from 18 on, so it is not recommended.

### R6. Part II's name (optional)

"Systems that come alive" fits Chapters 10 to 14 and not Chapter 15, which is geometry held as data. Two cheap options: rename the part ("Systems and shapes"), or leave it. No renumber.

### What the renumber costs, all together

- Renumbered chapters: 16, 17, and 27 onward (eight existing chapters). New chapters: 27, and three or five in Parts V and VI depending on R4. `Scripts/guide-renumber.sh --dry-run` runs in the cloud container, so the moves can be made here and verified on the Mac.
- On the Mac: re-render the figures whose folders moved (paths change, pixels don't), render the new finished pieces, re-key the chapter clips (`Scripts/guide-clips.sh`), and rebuild the hero grid. The hero is 8 across by 4 rows for 32 cells (`Media/media.json`); 34 chapters has no tidy grid, 35 is 7 by 5, and 36 is 9 by 4. The website needs redirects for the changed chapter URLs.
- In the repo: `CAPABILITIES.md`, `CLAUDE.md`, `Docs/` and the `Examples/` READMEs point at `Guide Ch N § *Heading*`; the renumber script rewrites the numbers, and every heading that moved chapter is re-pointed by hand (check-links reports each one).
- Tranche T2, two sessions, merged as soon as the Mac gates pass.

## Group 2: chapter structure

### R7. One shape for every chapter: a spine that ends in the piece, then a family section

This is the mechanism for most of the chapter work, and it keeps the numbers.

- **The spine** is the sequence of steps the finished piece needs, in order, each opening from the step before. The piece composes the spine, and "Putting it together" says so accurately.
- **The family section** comes after "Putting it together" and before "Where this comes from". It holds the relatives of the chapter's technique that the piece doesn't use: one `##` per family, headed with the family's name ("More tiles that agree at their edges"), and one `###` per technique, headed with the technique's name ("Hitomezashi: one coin per grid line"). Each entry opens with what the technique is, what it is for, and where it comes from, then shows its picture and its call, and points to the Docs page and the example. A bridge paragraph opens the family: what the piece used, and what else belongs to the same idea.
- **Why after the piece.** A reader who follows the spine finishes something within the first half of the chapter, and the family reads as a shelf to come back to, findable by technique name. The finished piece stops being a quarter of the chapter pretending to be all of it.
- **Where a family entry is big enough to be its own chapter,** the family section is where the case for a split shows first (R33).
- **Cost.** Applied chapter by chapter in the chapter tranches (T5 to T13). Most chapters need no new figure: the family entries keep their existing figures. Where a spine section has no figure or no canvas step (10:88, 17:110, 20:63), the tranche drafts one.
- **Risk.** Two costs to watch. A family section can become a catalog of its own, and the cap in R33 limits that. And the anatomy in `AUTHORING.md` changes (R33), so @eaviles rules on the pattern before the chapter tranches start.

### R8. Where the spine is thin, widen the piece rather than the tail

A few pieces can compose more with a small code change and no new idea: Chapter 3's piece can take an `Easing` parameter (3 digest), Chapter 4's can roll in `setup()` from `variation` so the chapter's own seed workflow works on it (4:235, `Sources/Ollin/Math/Random.swift:27`), Chapter 8's can move (per-glyph motion is taught at 8:69 and unused), Chapter 12's can add the predator its own "make it yours" suggests (12:463), Chapter 25's can be driven by the keys the chapter teaches (25:581), and Chapter 18's can build its clouds once in `setup()` instead of every frame. Each is a figure change, so each goes on the Mac list; the tranche drafts the code.

### R9. Cross-chapter moves in Parts I and II

Each move carries its figure (`git mv` of the source and image, the path renamed to the new chapter), gets a bridge at both ends, and is re-read for claims that were true only in the old place.

| # | Move | Evidence | Coverage row |
|---|---|---|---|
| a | Wave function collapse, both sections, 13:350 to 395 → Ch 7, after polyominoes and beside Wang tiles | 13:352 "grows nothing"; Ch 7 teaches edge agreement (7:13, 7:38) with no solver | WFC row home 13 → 7 |
| b | Crease patterns, 7:154 → Ch 15 (held geometry) or Ch 31's paper section | 7:156, 7:160 disclaim the chapter; needs 3D and SVG export | folding row home |
| c | Percolation, 4:214 → Ch 19 beside the other lattice rules | used by nothing in Ch 4; 4:142 "one more idea completes the starter kit" | percolation row |
| d | Blue noise and low-discrepancy sequences, 15:500 to 532 → Ch 4 | Ch 13 (13:230) and Ch 14 (14:110) use `poissonDisk` first and promise it; 15:500 cites Ch 4 | sampling row |
| e | Apollonian gasket and Ford circles, 6:279 and 6:308 → Ch 15 "Packing" | 6:279 "a circle rather than a grid"; Ch 18:118 uses the gasket | tilings row |
| f | Maze, 6:277 → Ch 7 beside the maze of diagonals; de Bruijn, 6:332 → Ch 7 or Docs | 6:334 "Here is its opposite"; 7:71 | Grids row |
| g | `viewControl`, 6:223 → Ch 1 "The canvas is not the window" | no tie to grids; the figure is a map | View row |
| h | `.wander` sway, 3:156 → Ch 5 beside `loop:` | needs Ch 5 noise and `loopDuration` | Motion row |
| i | `@Smoothed`, 3:254 to 267 → Listening (Ch 30) beside `smoothing: .smoothed` | 3:267 "file it away until Part V"; 28:375 | Values row |
| j | Chaos-game leftovers: 13:322, 13:523, README 70 → removed or pointed at Ch 18 | the material lives only in Ch 18 now | none |
| k | Differential growth leftovers: 12:468, 12:478, README 69, PLAN brief → Ch 13 | taught only at 13:181 | growth row |
| l | Spirolaterals, 15:108 → Ch 13 beside the L-system turtle | a turtle walk (13:74) | curves row |
| m | Pursuit curves, 12:103 → after "Roaming", bridged from `pursue` (sample 1 below) | interrupts seek/arrive/wander; 12:137 "A runner is not a `Vehicle`" | none |
| n | Kuramoto's lattice half, 12:381 to 397 → Ch 19 | leans on Ch 19 (12:397) | sync row |
| o | Double pendulum, 11:310 → Ch 18 beside the chaotic maps | a chaos lesson (18:149) | IK/pendulum row |
| p | "Breaking things", 11:507 → before the Wrecker (the bricks shatter) or Ch 15 after Voronoi; its 3D bullet (11:614) → Ch 24 | after the piece; needs Voronoi from Ch 15 | fracture row |
| q | `Fit.minimize`, 14:178 → Ch 15 or Docs | 14:180 "not a field at all" | fitting row |
| r | Live data (`DataFeed`, `PushFeed`, `Weather`), 9:387 to 498 → Controls and signals (R4a), or a family section in Ch 9 if R4a is declined | network plumbing in a pictures chapter; 9:599 files it with Part V | three rows |
| s | Seam carving, 9:283 → beside "The box is never the right shape" (9:82) as the fourth answer | 9:287 "the third answer" re-counts 9:84 | none |
| t | Photo palettes and dithering, 2:184 and 2:210 → Ch 9, or a family section in Ch 2 | both need `loadImage` from Ch 9 | two rows |
| u | Interactive evolution, 20:230 → Ch 4 after the keeper workflow | its subject is choosing among variations (4:57), unlinked | evolution row |

### R10. Cross-chapter moves in Parts III to VI

| # | Move | Evidence | Coverage row |
|---|---|---|---|
| a | The complex plane, 17:172 → Ch 18 beside domain coloring | 17:187 and 18:295 point at each other | complex row |
| b | Chladni figures, 17:320 → folded into the pattern fields; the CPU isolines to Ch 14 | 17:143 promises returns in Ch 19 and 28 that aren't there | Chladni row |
| c | Depth of field (`LineSpray`, `Bokeh`), 20:53 → Traced light (27) | needs a 3D camera and `--settle` | DoF row |
| d | The 3D attractor flow, 23:76 → Ch 20 or Ch 18 | 23:78 "Here they are" finishes Ch 18's list; no ground in it | attractor row |
| e | Many lights (`reach:`, 256 lights), 21:309 → Ch 23 (multitudes) | lighting depth in a gate chapter | many-lights row |
| f | IES profiles and cookies (21:284), light sets (21:334) → Docs, with a pointer | gate chapter; M2 timings | two rows (to `shown`) |
| g | Sky and aerial perspective, 21:393 to 402 → Ch 22's environments | 22:474 presents `.sky` as new | atmosphere row |
| h | Depth compositing on pillars, 27:81 → Ch 21 | no depth frame in its figure | depth-compositing row |
| i | 3D text, 22:125 → Ch 21's solids | a shape factory like 21:101 | text-3D row |
| j | Hopf fibration, 22:157 → Docs with a pointer | tied to neither neighbor | Hopf row (to `shown`) |
| k | `Environment.feed`, 22:495 → Seeing | needs Ch 30's `Camera` (22:500) | feed row |
| l | `--from-scene`, 22:104 → Finishing or `Docs/Tools` | CLI tooling | importer row |
| m | Shadow art, 26:173 → Ch 22 "Meshes made from other meshes" | 26:175 "nothing to do with fields" | shadow-art row |
| n | Buoyancy, 25:344 → Ch 24 after density, bridged to Ch 23's sea; the raft's contacts half (25:416) → the cloth section | 23:262 "no floating bodies" and 25:344 never link | water row |
| o | Snapshots of characters, vehicles, cloth (24:397 to 425, 24:436) → end of Ch 25 | Ch 24 covers Ch 25's objects before they exist | snapshot row |
| p | Motors, 24:66 → the start of "Machines out of joints"; heightfield and scene colliders (24:72) beside USD import (24:427) | appended to section one | none |
| q | The phone's controls (wand, hearing, touch, air), 27:491 to 594 → Controls and signals, or kept as phone streams | controls, not depth (27:530, 27:556) | phone rows |
| r | Markers protocol, 27:446 → `Docs/3D/Phone.md` with a pointer | reference | markers row |
| s | Tempo sync, 29:713 → Listening, beside the beat and clock sections | duplicates 28:68, 28:216, 28:326; `mic` undefined | tempo row |
| t | Timecode, 28:240 → Performing | show-control topic | timecode row |
| u | The cost row, 32:105 → a first reading in Ch 3 "When a frame takes too long" and the full reading at the end of the layers chapter | readers hit a slow sketch in Part II; 3:47 promises Ch 32 "puts it to work", nothing does | profiling row |
| v | HDR output, 16:763 → Finishing a piece | an export topic splitting the persistence thread | HDR row |
| w | Laser, 31:327 → Installations beside DMX | a live device | laser row |
| x | Haptics, 31:704 → Controls and signals | an output to the hand | haptics row |
| y | Handing over (extension package 31:766, `SketchExtension` 31:745, the phone 31:803 to 864) → Installations, grouped with the screen saver, wallpaper, widget and app (32:477 to 659) as "On somebody else's machine" | two digests find these belong together; 32:571 already points at the wrong neighbor | several rows |
| z | "Models of your own", 30:278 to 388 → a family section in Seeing, after the piece | 1,150 words of downloads and weights with no bridge | model rows |

### R11. Per-chapter reorganization (the chapter tranches)

Each chapter gets R7's shape, the moves above, headings that name techniques, bridges where the digest lists them missing, and the voice pass of R16. The table names the spine and the family section for each; the digest has the line-level detail.

| Ch | Spine (ends in the piece) | Family section after the piece | Other changes |
|---|---|---|---|
| 1 | first sketch, creative coding (R18), frame, coordinates, canvas and window, fractions, shapes and ink (with draw order), motion, mouse, piece, saving values | tools: drag-to-edit, `ollin doctor` beside the toolchain check, packages and terminal docs trimmed to pointers | 49% of the chapter is tooling (1 digest); piece uses fractions as 1:146 advises |
| 2 | naming, hue, mixing, lightness (split out of mixing), palettes and harmonies (sample 2), ramps and gradient paint (moved up), color vision, piece | spectrum and paint mixing; palettes from files | piece gains a harmony ramp; fix 2:106 (HSB does pass through green) |
| 3 | clock, sine, phase, map and lerp (with a wrap picture), shaping, easing, piece | sway and wave, `@Eased` and `@Sprung`, `Timeline`, timers, reduced motion | "act" labels (3:99, 3:222) replaced by bridges |
| 4 | dice, seeds, choices, the two shapes of chance, the walk, keepers (moved last), piece on `variation` | the walk family, blue noise (R9d), interactive evolution (R9u) | fix 4:9 ("poster"), 4:153 (`drawLine` was shown in Ch 1) |
| 5 | lookup, zoom, `signedNoise` (moved up), 2D field, time and `loop:` (own heading), octaves and fBm, piece | simplex, worley, ridged, turbulence, warped | Gabor and `noiseFields` to Docs; fix 5:208 |
| 6 | grid, hex and triangle grids (moved up), transforms (heading names them), symmetry, fold, clip (define `star`), view box, piece | subdivide, Ulam | moves e, f, g out |
| 7 | Truchet (ten print folded in), hitomezashi, piece | kolam and sona, knotwork, parquet deformations, polyominoes, WFC, aperiodic (Penrose's rule pictured), hyperbolic (formula after its picture) | intro and README line name the whole family |
| 8 | text, three kinds of font, the box form and justification (in Latin), scripts (one section), motion, geometry, piece (moving) | none | Mongolian, hanging punctuation, most of vertical text to Docs |
| 9 | pictures, fit (with carving), asking a picture, marks, piece | mosaic, stipple and one line, thread, sorting, autostereogram | CSV and JSON stay with a data-to-marks step (R22); sample photo list to Docs |
| 10 | arrows, arithmetic (with `drawArrow` on the canvas), length and direction, the motion trio, steering (with its picture), piece | none | R24 |
| 11 | a force, a world, springs, rigid bodies (a runnable sketch), hinges and a handle, breaking (R9p), piece | IK chain, n-body, force layout (after springs) | fix the three/four count (11:289, 11:505) |
| 12 | steer, seek and arrive, roaming (with `noClear` trails), three rules, flock, piece | pursuit curves, crowds, synchronization | neighbor grid becomes an aside under the flock |
| 13 | tree, L-systems, parametric, space colonization (drawn), DLA, piece | shape grammars, differential growth, dielectric breakdown (under DLA), cracks, meanders | fix 13:53; add the missing credits for differential growth and dielectric breakdown |
| 14 | field (two kinds named), isolines, flow field, streamlines, spacing, piece | advection (a small sketch), LIC, radial basis | fix 14:85 (Chladni is in the shader chapter), cut 14:243 |
| 15 | held shapes, booleans and offsets (moved up), outline questions, scatters and Voronoi, hatching and SVG, piece | curves you can write down; how a line is drawn (profile, dynamics, brushes, dash); hulls and skeletons; packing; wet media | batches to the performance section; see Q5 on splitting |
| 16 | per pixel, first shader, distance, time and parameters, the library, pattern fields (Chladni folded), piece | shaders from elsewhere: chains, GLSL import, `#include`, `ollin check` | R1 |
| 17 | a layer, filters, blend modes, `compose`, `noClear`, the running mean, tone map, feedback, piece | filters that restyle a picture; layers you solve and measure | "dials" paragraphs to Docs (they repeat `Docs/Drawing/Effects.md`); see Q5 |
| 18 | chaos game, flames and relatives (named headings), Schottky, maps, bifurcation, billiards, escape time (Buddhabrot after it), Newton, domain coloring, piece | none | complex plane in (R10a); link Ch 16 and Appendix B |
| 19 | GPU state, Life, "a field is data" with `.gradientMap` and `.levels` explained (moved up from 19:349), reaction-diffusion, piece | automata, piles and fires, sorting and spins, other chemistries, fluids and ripples, materials, a rule of your own | fix the stale ordinals and 19:535 `strength` |
| 20 | particles (with `id`, `dt`, `hash22`, `custom` taught), neighbor sort citing Ch 12, piece | Particle Life, Physarum and ant colonies, Lenia, the big flock, SPH and jellies, evolution, swarm chemistry | fix 20:119, 20:197, 20:201 |
| 21 | world, camera, bearings (moved up), depth, solids (with `wireframe` and 3D text), transforms, light, shadows, materials (moved up), matcaps, outline, fog, piece | area lights, contact shadows | moves e, f, g out; teach surface normals |
| 22 | a mesh from a file, maps together (texture basics, normal, height, triplanar, detail, decals), meshes from meshes, finishes with environments first, piece | none, or the finish presets as a family | rosters, ranges, glass internals to Docs; fix 22:389, the duck against the crystal |
| 23 | landscape, rivers, the sea, instancing, scatter (the piece uses `surfacePoints`), world the camera trims, grass, piece | none | attractor out; add drainage and ocean credits; fix 23:495 |
| 24 | bodies, contacts, queries, groups, freedoms, machines (with motors), tensegrity, snapshots of rigid bodies, piece | none | buoyancy in; fix 24:44 against 24:564 |
| 25 | three `##` groups: figures (character, ragdoll, cape), vehicles (tracks as a `###`), cloth and rope | none | fix the stale names; piece driven by keys |
| 26 | shape as a question, melting (smooth minimum explained), verbs, drawing form, into space, sphere tracing, field to mesh, sculpting, distortions (own section), folding, fractal leaves, piece | none | Molten is called glass and uses `.dielectric`; fix one or the other |
| 27 new | reflections, glossy floors, bounce, caustics, the path-traced still, the lens (defocus, flare, motion blur), settling edges and highlights (TAA, specular AA), fewer pixels and frames, piece (new) | none | R2 |
| 28 Seeing | the webcam (with `VideoPlayer` beside `orStill`), trackers, the body as a controller, the person as pixels, the picture as a field, piece | reading print, following one thing, labels and saliency, models of your own, screen capture, slit scan | rehearse on footage becomes one practice note (30:491, 30:538) |
| 29 Depth | the Mac thread unbroken (13 to 238), the real sensors after it, the phone's depth streams, piece | the phone's perception streams, now pointing back to Seeing | Mac-first holds for the whole spine |
| 30 Listening | sources first, amplitude, spectrum, beat, pitch, speech and events, musical time together, piece (Resonator) | none | the mapping craft (R23) |
| 31 Controls | the spine named first (level, moment, bind), MIDI, OSC, binding, controllers, serial and Bluetooth, live data, haptics, piece (new) | TUIO, OSCQuery | R4a |
| 32 Making sound | a synth, envelope and filter, FM, sources (sampler, wavetables, grains, string, modal, bowed), expression, the effects chain after the sources, piece (new) | none | audio-thread limit said once (29:93) |
| 33 Music by rule | pitch primer (R21), steps and tempo, rhythms, scales and snapping, chords, progressions, Markov, sequencer, MIDI files, piece (music box) | tunings, sonification | R4b |
| 34 Finishing | the practice (R19), stills, film, reproducibility, paper, machines, 3D, piece (new) | the web page, describable output | R3 |
| 35 Performing | live coding, cues, the take, replay, keyframes and timeline (bridged to Ch 3's `Timeline`), rules, feeds out, piece | none | R3 |
| 36 Installations | leaving it running (opens the chapter), the room, light (DMX, LED, laser), the building (MQTT), tuning from the floor, on somebody else's machine, piece | none | closing for the guide (R26); fix 32:757, 32:684 |

### R12. The known-errors tranche, first and fast

The digests found about forty defects that need no structural decision. They are prose fixes (and a few listing fixes) that a reader hits today, and fixing them first gives every later tranche a clean base. The list is in `LEDGER.md` under T1, one line each with its source line. It covers the stale API names in section 9 of the summary, the wrong chapter pointers (14:85, 16:42, 18:60, 19:78, 10:13, 24:15, 17:143, 22:609, 22:625, 26:307, 15:602, 23:163), the false statements (13:53, 2:106, 12:150, 24:44 against 24:564, 30:276, 30:280, 30:491, 22's duck against crystal, 32:757, 4:153), and the README contents lines. Every changed Swift block goes on the Mac list for `check-snippets.sh`. One session.

## Group 3: flow

### R13. Rewrite the chapter openers as a set

Read as one list, the openers repeat four shapes (summary item 7). Each chapter's first paragraph should say what the chapter teaches and why a reader would want it, in a shape its neighbors don't use. The rewrite happens once, after the structural tranches, reading all openers together; each chapter tranche leaves its opener alone except to fix what it now promises. The piece picture keeps its place; the sentence "by the end you'll have built the sketch above" goes, since the anatomy already says so.

### R14. A short opening for each part

Today only Chapter 10 says which part it opens ("Part II begins here", 10:9). Recommendation: each part's first chapter opens with two or three sentences on where the part goes and what it asks of the reader, and the README's "How to read it" becomes the map of parts with the same sentences in short. No separate part pages, since the footer chain and the gates read only chapters and appendices.

### R15. Bridges, inside chapters and between them

Every section opens from where the reader is: what they just made, or what they can't do yet, and why the next idea helps. The digests list the missing joins by line (for example 2:240, 3:76 to 97, 7:71, 9:283 to 328, 12:399, 16:53 to 71, 21:383 to 418, 29:500 to 502). Between chapters, the overlaps the digests confirmed get a back-link at the second telling instead of a second explanation: the neighbor grid (12:268 and 20:65), fading trails (12:401, 16:679, 20:166), Lenia (19:88 and 20:117), watercolor (15:740 and 19:470), keyframes (3:269 and 31:961), and escape time (18:195 and 26:245). Done inside each chapter tranche.

### R16. The voice pass, where it is needed most

Inside each chapter tranche, the paragraphs its digest lists under "Voice" get rewritten, and the page's framing devices are brought down: "worth", "exactly", "honest", "the whole X", bold aphorisms, false negatives, and figure provenance in the prose (16:604, 30:121, 30:202, 30:453, 30:538). Parts IV and V carry most of it (122 of the 165 uses of "worth"). `prose-density.sh` is run on each chapter before and after, and its FRAMES column should fall.

### R17. Stop counting in prose

Counts and ordinals ("the third grower", "four more games", "the last rule in this chapter") are the defect that insertion creates most often (summary item 2). Name the neighbor instead: "DLA's walkers", not "the third grower". Applied in each chapter tranche, and proposed as a charter rule (R33).

## Group 4: expansions

### R18. What creative coding is, in Chapter 1

- **Where.** A new section in Chapter 1, right after "Your first sketch" (1:57), so the reader has a circle on the canvas before the guide steps back.
- **What.** About 500 words: what creative coding is (making pictures, motion and sound by writing the rules that make them); who does it and what for (art, design and illustration, print and plotter work, visuals for music and performance, installations, data), each with a pointer to the chapter that teaches it; where the word "sketch" comes from; and how people work at it, as a loop the guide keeps returning to: write a rule, run it, tune it, keep the variations you like, finish one, export it. Each step names the chapter that teaches it (parameters in Ch 1, seeds and keepers in Ch 4, the first export in Ch 3, finishing in Finishing a piece).
- **Cost.** No new figure. About 500 words added to Chapter 1, which R11 also trims by about 1,500 words of tooling. Part of the Part I tranche.
- **Guard.** It describes the field, names real practitioners only where the chapter's credits already do, and makes no promise to the reader.

### R19. The working practice, as a thread instead of an aside

- Chapter 4: "Finding a seed worth keeping" (4:71) becomes the chapter's last spine step, and the piece is rebuilt on `seed`/`variation` in `setup()`, so the Variation card and `--export-grid --seeds` work on it (today they don't: `randomSeed` in `draw()` overrides `variation`). Add keeping the keepers: the seed in the export's metadata (31:551).
- Chapter 3: the first export stays the loop; add one sentence on exporting a still.
- Finishing a piece (R3): opens on the walk from a sketch to a finished work: pick a keeper, fix its seed and parameters, size it for the output (paper and dpi, frame rate), proof it, export, check the recipe. Its new piece is that walk.
- Chapter 15: "how a plot runs": one file per pen, pen order, hatch spacing from the nib, a test plot (15 digest). About 300 words, no new figure.
- Seeing: rehearse on recorded footage, then go live (from the figure-provenance asides at 30:491 and 30:538).

### R20. Techniques get their what, where from, and what for

Every technique section opens with what the technique is, where it comes from (one clause; the full credit stays in "Where this comes from"), and what people use it for, before its call. The digests list about sixty places where one or more of the three is missing ("Techniques given only through their API" in each). Sample 2 below shows the size: about 150 words where there were 50. Most need no figure; the tranche drafts one where the idea needs a picture (the harmonies, the gradient map, curl noise). Applied in each chapter tranche.

### R21. A pitch primer before the music theory

Before scales (29:552), a short section with a keyboard figure: the semitone as the step, the octave, a scale as a pattern of steps, degree and root, the triad, major against minor counted in semitones, the fifth. Rhythm already gets picture, words, then code (29:526, 29:540, 29:636); pitch doesn't, and 29:552 to 711 fail the smoothstep test. Plus a tunings figure (29:698), and an Appendix B entry "Pitch as ratios". Two new figures. About 700 words.

### R22. Numbers into marks, in Chapter 9

If CSV and JSON stay in Chapter 9 (R9r moves the live feeds out), they get one step on turning a column into marks: which property carries the value (position, size, color), scaling from the data's range, and one small data piece. About 500 words and one figure. Data visualization as a practice is otherwise absent (9 digest).

### R23. The mapping craft for music visuals, in Listening

Which band drives what, levels against moments, decay you can feel, a mixer feed instead of the room microphone, and rehearsing on a recording (28 digest). About 400 words; the Resonator figure already shows it.

### R24. A gate chapter that carries its weight: Chapter 10

Move the steering diagram from Chapter 12 (12:24) to where steering is first taught (10:156); put `drawArrow` on the canvas in "An arrow you can draw"; teach `lerp(to:)` and dividing a vector by a number, which Chapters 21 and 11 say Chapter 10 taught (21:19, 11:35); give `Thrown` its output figure. One or two new figures. About 400 words.

### R25. Performance habits early

The cost row (R10u), a short reading in Chapter 3 and the full reading at the end of the layers chapter, plus batches (15:814) beside it. A reader meets a slow sketch in Part II.

### R26. A close for the guide

The guide ends on Installations' "Go deeper" and a footer to Appendix A (32 digest). Recommendation: a short final section in the last chapter, about 300 words: the path in one paragraph, where to keep learning (the reference, the examples, the books the credits name), and how to share work and report a problem in the guide. No new figure.

### R27. Appendix B's missing entries

Add entries, each in the group its chapter links to: the gcd, the tail of a distribution and the square-root spread, quadratic growth, linear light and gamut (ahead of luminance), damping in the spring entry, complex numbers, `atan2`, the Fourier idea outside sound, log scales, the golden angle, surface normals, inverse square, circle inversion, barycentric coordinates, pitch as ratios. About fifteen entries, most reusing a chapter figure, a few needing a new diagram (B digest). Also: split "Local rules, global structure" into local rules and iteration, and point chapters at entry anchors rather than group anchors.

## Group 5: cuts and moves to Docs

### R28. Reference lists go to the reference

Each cut leaves a one-line pointer with an example link in the chapter, so its coverage row stays at `shown` with an honest description.

| From | What | To | Row |
|---|---|---|---|
| 5:178, 5:195 | Gabor noise; `noiseFields` | `Docs/Generators/Noise.md` | Noise |
| 8:172, 8:213, most of 8:150 | Mongolian, hanging punctuation, vertical text detail | `Docs/Drawing/Text.md` | three text rows |
| 9:48 | the twenty sample photos | `Docs` images page | Images |
| 16:88, 107, 126, 145 | the stylize filters' "dials" | `Docs/Drawing/Effects.md` (it already has them) | Effects |
| 17:114 to 122, 17:260, 17:293 | splice mechanics, `#include`, `ollin check` | `Docs/Shaders/Shaders.md`, `Docs/Tools` | three rows |
| 21:284, 21:334 | IES and cookies, light sets | `Docs/3D/3D.md` | two rows |
| 22 (several) | material preset rosters, parameter ranges, "honest edges", glass internals, skins detail, Hopf | `Docs/3D/3D.md`, `Docs/3D/HopfFibration.md` | material rows |
| 23:194 and timings | `MeshField` fine print, M2 timings | `Docs/3D/Instancing.md` | Instancing |
| 25:112, 25:155 | motorcycle, sprocket and grip | `Docs/Physics` | Physics3D |
| 26:461 to 465 | lens prescriptions list | `Docs/3D/LensFlare.md` | Lens flare |
| 28:377 | inspector show-rules | `Docs/Helpers/Parameters.md` | Parameters |
| 31:141, 31:256, 31:274 | frame-rate grid, what crosses to the web page, `PaperSize` list | `Docs/Output` pages | three rows |
| 1:338 to 436 | `ollin doctor` detail, packages, terminal docs | `Docs/Tools` | tool rows |

About 5,000 words leave the chapters in all. `guide-coverage.sh` runs after each batch; a row whose home chapter now only points gets its depth text rewritten to say so, and never drops below `shown`.

## Group 6: the front door and the appendices

### R29. `Guide/README.md`

- **Contents lines.** Rewrite each to match what its chapter teaches after the tranches. Ten are stale now (7, 9, 12, 13, 15, 18, 23, 26, 28, 30).
- **How to read it.** Recount the parts (prose words today: I 44,892; II 30,750; III 33,522; IV 43,373; V 59,202), give page counts from one rule, drop "the shortest part" for Part III, and say which chapters each gate serves (the shader chapter serves 19 and 20; Chapter 18 writes no shader).
- **Where it reads as a pitch.** "Guides like this tend to fail in known ways" (README:21) criticizes other guides; "it teaches you to think in sketches" (README:17) promises an outcome; "Four promises" are promises. Recommendation: one section, "How the guide is made", that states the four facts plainly (every listing compiles, every image is rendered by the code beside it, concepts arrive before they're used, something reaches the canvas in the first page), with no comparison and no promise.
- **The hero.** "thirty-two" appears twice (README:11, README:28); both follow the chapter count.

### R30. Appendix D: one row per thing a reader looks for

D promises every shipped capability (D:7) and misses whole chapters' worth (D digest), because it grew from the coverage matrix, which is keyed by Docs page. Recommendation: one row per taught capability, grouped by the guide's parts and chapters so the group and the "Guide" column agree, each "Guide" cell linking the section rather than the chapter; the missing rows added; the six wrong pointers fixed (D:24, 63, 64, 91, 149, 304); the pitch words taken out ("real" 13 times, "the guarantee"). One session, late, after the chapters settle. See Q8 on how D is produced.

### R31 (Appendix A). The Swift the chapters type

Add a section "Swift you'll see in listings": force unwrap and implicitly unwrapped optionals, `try`, `try?` and `try!`, `&` for inout, key paths, `zip`, `lazy var`, `override var`, `switch`, `stride`, and an `init` of your own (A digest). Fix A:205 (the guide meets `if let` before `??`) and A:257 (the guide does throw). About 600 words. `Docs/Swift.md` repeats nine of A's ten sections; see Q9.

### R32 (Appendices C and E)

C: fix C:172 (`loadImage` throws) and C:200 (no bare `camera()`), add the missing everyday calls (`createCapture`, `pixels`, `loadTable`/`loadJSON`, `textToPoints`, `beginContour`, `size()`), and point at Chapters 11 to 14 for readers bringing *The Nature of Code*. E: fix E:9 ("shorter than Appendix C", which it isn't), E:233 (meshes are in Ch 22), E:310 (`--keep-clock` is in Performing), and point the addon table at chapters, including Installations. Small.

## Group 7: the charter

### R33. Changes to `AUTHORING.md`

- **Anatomy.** Add the family section (R7) between "Putting it together" and "Where this comes from", with its heading rule. State that the piece composes the spine and that "Putting it together" says what it uses, never "everything".
- **Size.** Keep 2,000 to 8,000 words, and add: the family section holds at most about 40% of a chapter's prose (or about 3,000 words); past that, the chapter is reviewed for a split along its families, or entries move to Docs.
- **Rules that make the three signs checkable.** No counting siblings in prose (R17). A sentence defending a section's membership is a move signal, not a bridge. Headings name the technique in every chapter, not only grown ones. The intro and the README contents line change in the same commit as a section.
- **Openers.** A chapter's first paragraph says what it teaches and why; a structural change rereads all openers as one list.
- **Technique entries.** What it is, what it's for, where it comes from, before the call (R20).
- **Figures in prose.** Prose explains the reader's workflow, not how a figure was made.
- **Practice.** "Putting it together" ends with how to keep that kind of piece (the export or plot that fits it).

### R34. The ship checklist (a suggestion for `CLAUDE.md`)

Step 5 could read: a new user-facing capability lands in its chapter's family section at `shown` or better (an entry with what, what for, where from, a picture or example, and its call), and joins a chapter's spine only when that chapter's structure is revised on purpose. The same commit updates the chapter intro and the README contents line when they name the family. When a family section passes its cap, the session files a "structure review" entry in the Guide debt ledger instead of adding to the tail. The floor stays `shown`. Two optional lints that would catch the defects this review found by hand: a Vale rule for counting siblings ("the (second|third|fourth|last) (section|grower|rule)", "(three|four|five) more") and a FRAMES threshold for "worth". Both are suggestions; the scripts and Vale rules are @eaviles's to change.

## Voice samples

Two real passages, before and after, to judge the voice before the edits start.

### Sample 1: a dropped-in section tied into its chapter (Chapter 12)

Before (12:101 to 109, where it sits today, between "Seek, and the art of stopping" and "Roaming"):

> Both trails here are just arrays of positions, appended each frame and drawn with `drawPolyline`, the same trick as every trail in this chapter.
>
> ## Everyone chasing somebody
>
> `seek` and `arrive` both point at something that stands still. Give every creature a target that is also running, and the picture changes completely.
>
> The oldest version of the question is from 1877. Four dogs stand at the corners of a square. Each one runs at the next, always at full speed, always straight at where that dog is *now*. What do they draw, and how far does each dog run?
>
> You can answer it by running it. `Pursuit` is a stepper you hold, like `World` in the last chapter and the flock later in this one. Build it, step it, and read the geometry out:

What's wrong: it interrupts the `Vehicle` thread (seek and arrive, then wander) with a different type; the heading hides the technique; "the oldest version" is from 1877 while the chapter's own credits date the question to 1732 (12:468); the reader learns why `Pursuit` isn't a `Vehicle` twenty lines later (12:137); the code calls `run()` while the prose says "step it"; nothing says what pursuit curves are for.

After (moved to follow "Roaming", whose last paragraph introduces `pursue`):

> ## Chasing a moving target: pursuit curves
>
> `pursue` aims at where a moving target will be, so a creature can cut the corner and catch up. A simpler chaser aims at where its target is now. It keeps turning to face the target, so its path bends into a curve, called a pursuit curve. Draw many of these paths together and you get line work that suits a pen plotter.
>
> One version of the question, from 1877, uses four dogs. They stand at the corners of a square. Each dog runs at the next one at full speed, always straight at where that dog is now. What path does each dog draw, and how far does it run?
>
> You can find out by running it. `Pursuit` holds a whole chase at once. Its runners carry no momentum and no turning limit, so they are simpler than a `Vehicle`. You build a chase, run it, and read the paths out:

### Sample 2: a thin technique introduction expanded (Chapter 2)

Before (2:150, the whole of what the chapter says about harmonies):

> Eight classic sets ship built in, from `.set1` through `.accent`. The **harmony builders** grow a whole palette out of one base color, and because they work in OKLCH the companions keep the base's weight rather than drifting lighter or darker: `Palette.complementary(of: base)`, `.triadic(of: base)`, `.analogous(of: base)`, and `.splitComplementary(of: base)`.

What's wrong: four color-theory terms arrive as four calls, with no word on what complementary, triadic, analogous, or split complementary means, where the idea comes from, or when you'd reach for one. The reader who doesn't already know the terms can't choose between the calls.

After (a `###` inside "Kits you carry", with a new figure):

> Eight classic sets ship built in, from `.set1` through `.accent`. Often, though, you start from one color you already like and need companions for it.
>
> ### Palettes from one color: harmonies
>
> A harmony finds those companions on the hue circle from "Thinking in hue". Picture your base color as a point on that circle. Its **complement** sits half a turn away, which gives the strongest contrast of hue. A **triad** divides the circle into thirds. **Analogous** colors are close neighbors, a twelfth of a turn apart, and they read as calm and related. A **split complement** takes the two neighbors of the complement instead of the complement itself, which keeps most of the contrast with less clash.
>
> `<!-- figure: HarmonyWheel, the four arrangements on one hue circle; waiting on a render -->`
>
> The circle itself goes back to Isaac Newton, who drew the colors of the spectrum as a circle in *Opticks* (1704). Each harmony is one call that takes your base color and returns a `Palette`:
>
> ```swift
> let base = Color(hex: 0x2A9D8F)
> let calm = Palette.analogous(of: base)   // the base and two neighbors
> let bold = Palette.triadic(of: base)
> ```
>
> The builders turn the hue in OKLCH, so every companion keeps the base's lightness, and none of them looks brighter than the rest. Use the result as a starting point, then vary the lightness. That adds contrast, and it keeps the colors apart for readers with color blindness, as "Will everybody see it?" shows.

Checked against `Sources/Ollin/Color/Palette.swift:78 to 107`: the complement is a half turn, the split complement and analogous spread default to a twelfth of a turn, `analogous(of:)` defaults to three colors centered on the base, and the rotation keeps OKLCH lightness (chroma is kept where the new hue allows it). The Newton credit is to be checked against `ATTRIBUTION.md` before it ships.

## Proposed tranches

Structural work first, so it merges before `main` moves on. Each tranche is one or two sessions; each ends with a push, the handoff, and the Mac list.

| # | Tranche | Carries | Sessions | Mac work |
|---|---|---|---|---|
| T1 | Known errors, and the charter if ruled early | R12, R33, R34 text for @eaviles | 1 | `check-snippets.sh` on every touched page |
| T2 | The renumber and the splits | R1 to R6 | 2 | re-render moved figures, render three to five new pieces, clips, hero, redirects |
| T3 | Cross-chapter moves, Parts I and II | R9 | 1 to 2 | re-render moved figures (path changes) |
| T4 | Cross-chapter moves, Parts III to VI | R10 | 2 | same |
| T5 to T7 | Part I chapters: 1 to 3, 4 to 6, 7 to 9 | R7, R8, R11, R15 to R20, R22, R25, R28 | 3 | figure drafts for widened pieces and new diagrams |
| T8 to T9 | Part II: 10 to 12, 13 to 15 | same, R24 | 2 | same |
| T10 to T11 | Part III: 16 and 17, 18 to 20 | same | 2 | same |
| T12 to T14 | Part IV: 21 and 22, 23 to 25, 26 and 27 | same | 3 | same |
| T15 to T17 | Parts V and VI | same, R21, R23 | 3 | same |
| T18 | Prose around the new pieces and diagrams once rendered | R2 to R4, R20, R21 | 1 | none |
| T19 | Openers as a set, part openings, README, the close | R13, R14, R26, R29 | 1 | none |
| T20 | Appendices | R27, R30 to R32 | 1 to 2 | B's new diagrams |
| T21 | Final gates, and delete `.guide-revision/` | | 1 | full `preflight.sh --milestone` |

About 22 to 26 sessions in all. The count falls if R4 is declined (two fewer chapters to build) or if the Part I and II chapter tranches are merged with the cross-chapter moves they depend on.

## Apple's writing guidance, and where it differs from `AUTHORING.md`

The network allowed the Human Interface Guidelines page on writing (read through its JSON endpoint); the Apple Style Guide pages rendered only their tables of contents, so its specific entries were not read. What the HIG page adds that fits a user guide: choose words that are easily understood, check that each word needs to be there, read it out loud, write for localization and accessibility, keep a list of common terms and use it consistently, put the most important information first, and label actions with a verb. All of that is already in `AUTHORING.md` except the terms list, which R33 could add (the vocabulary rulings are the start of one). One difference, named rather than changed: the HIG says to avoid "we" altogether, while `AUTHORING.md` allows "let's" sparingly for a shared move. The house style wins.

## Open questions for @eaviles

1. **The map.** Approve R1 to R6 as a set, or pick: the minimum that fixes the reader problems is R1, R2, R3 and R5 (34 chapters). R4a and R4b add two chapters (36 in all).
2. **The family section.** Is the pattern in R7 (after the piece, one `##` per family, `###` per technique) the shape you want, and what should the family heading look like?
3. **The checklist.** Is R34's landing place for new capabilities acceptable, with the floor left at `shown`?
4. **New finished pieces.** R2, R3 and R4 need three to five new pieces rendered on the Mac. Is that load acceptable, and in which order?
5. **Chapters 15 and 17 (today's 16).** Reorganize in place (recommended, keeps numbers) or split? A split of either renumbers every chapter after it.
6. **Live data.** If R4a is declined, do the live feeds stay in Chapter 9 as a family section, or go to Installations beside MQTT?
7. **Handing over.** Installations as "a room, and somebody else's machine" (R10y), or a separate home for the phone, app, and package material?
8. **Appendix D.** Is D written by hand or generated from the matrix? R30 changes it from one row per Docs page to one row per taught capability.
9. **`Docs/Swift.md`.** It repeats nine of Appendix A's ten sections. Turn it into a lookup page that links into A, or leave both?
10. **The README's "Four promises".** Replace with "How the guide is made" (R29), or keep the promises framing?

## Rulings

Recorded here once @eaviles has answered, one line per recommendation: approved, amended (with the amendment), or rejected.
