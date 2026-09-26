# Guide revision ledger

The state of the Guide revision, kept in the repo so each cloud session can start from it. Read this first, then the digests for what you are about to touch, then only the sections you will edit. This folder is temporary and public: the last session deletes it.

## Where things stand

- Branch: `claude/guide-revision`, cut from `main` at `a554d02` on 2026-09-26.
- Session 1 (2026-09-26): review and proposal. No chapter edits. Wrote the 37 digests under `digests/` and `PROPOSAL.md`.
- Rulings: waiting on @eaviles. Nothing in `PROPOSAL.md` is approved yet.
- Next step: record the rulings in `PROPOSAL.md` and in the tranche table below, then start tranche 1.

## Baseline (session 1, on `a554d02`)

| Gate | Result |
|---|---|
| `Scripts/check-links.sh` | pass: 38 Guide pages, 224 Docs pages, 32 chapters, 921 images, 594 examples, 0 errors, 0 notes |
| `Scripts/guide-coverage.sh` | pass: 329 matrix rows covering 210 Docs pages |
| `Scripts/check-names.sh` | pass: 0 errors, 11 notes (all "bullet names no Docs/ page" notes in `CAPABILITIES.md`) |
| `Scripts/check-api-pages.sh` | pass: 10,844 declarations, 791 exempt by construction, 148 allowed |
| `Scripts/prose-lint.sh` (Vale 3.12.0, Linux binary) | 0 errors; Guide only: 1,119 warnings and 883 suggestions in 40 files |
| `Scripts/prose-density.sh` | runs; LONG% at or under 20 on every chapter; FRAMES highest on Ch 25 (11.9), Ch 30 (11.0), Ch 24 (10.6), Ch 27 (10.2); "worth" 169 times across the chapters |
| `Scripts/check-snippets.sh`, `guide-figures.sh`, `guide-clips.sh`, `preflight.sh` | not runnable on Linux; Mac only |

How to run them here: `sudo apt-get install -y zsh`; Vale from the Linux release tarball at github.com/errata-ai/vale (v3.12.0 works), copied to `/usr/local/bin`, then `vale sync` at the repo root (it writes the Google package under `.vale/styles/`, which is gitignored).

`Scripts/guide-renumber.sh --dry-run` also runs here (checked with `--dry-run 32=33`), so a renumber can be made in the cloud and verified on the Mac.

## Tranches

As proposed in `PROPOSAL.md` § Proposed tranches. Rows change once the proposal is ruled on. Each row: the tranche, the recommendations it carries, its status, and the commit that finished it.

| # | Tranche | Carries | Status | Commit |
|---|---|---|---|---|
| T1 | Known errors (list below), and the charter text if ruled early | R12, R33 | proposed | |
| T2 | The renumber and the splits | R1 to R6 | proposed | |
| T3 | Cross-chapter moves, Parts I and II | R9 | proposed | |
| T4 | Cross-chapter moves, Parts III to VI | R10 | proposed | |
| T5 to T17 | Chapter tranches, part by part | R7, R8, R11, R15 to R25, R28 | proposed | |
| T18 | Prose around the new pieces once rendered | R2 to R4, R20, R21 | proposed | |
| T19 | Openers, part openings, README, the close | R13, R14, R26, R29 | proposed | |
| T20 | Appendices | R27, R30 to R32 | proposed | |
| T21 | Final gates; delete `.guide-revision/` | | proposed | |

## T1: the known-errors list

Defects a reader hits today that need no structural decision. Each line: where (chapter:line at `a554d02`), what is wrong, and the fix. A line marked "verify" needs a check against `Sources/` or a render before it is changed. Every changed Swift block goes on the Mac list.

API names and listings:

- 16:903: a `@Param` on bloom's `intensity`; the parameter is `amount` (`API/Ollin.txt:3729`). 16:905 suggests "a second `compose` layer" the piece doesn't have.
- 19:535: self-warp `strength`; the parameter is `amount` (`API/Ollin.txt:5924`).
- 22:389: detail map `strength`; the parameter is `amount` (`API/Ollin.txt:4791`). 22:502: `func draw()` lacks `override`.
- 23:495: `Color.mix(pineDark, pineLight, t: ...)`; the call has no `t:` label (`API/Ollin.txt:3128`, and the figure source `Guide/Figures/23-Landscapes/Valley.swift:223`).
- 25:34, 25:526, 25:584: prose names `move` and `world.step`; the code is `walk(at:)` and `advance(by:)`. 25:264: `rotation:` is `rotated:`. 25:305: `thickness:` is not a rope parameter (`API/OllinPhysics.txt:361`). 25:183 and 25:263: `walk`, `target`, `sheet` are undefined.
- 9:418, 9:461: `updates` is `updateCount`. 9:455: `splash` is undefined.
- 6:193: the clip snippet uses an undefined `star` (`Shape.star(...)` exists).
- 29:811: `sequencer` is undefined (it was `drums`). 29:713: `mic` and `scale` are undefined.
- 30:83: says to draw the feed mirrored; `drawFrame` has no such parameter (`API/Ollin.txt:1951`), and the figure `Mirror` is not mirrored. Verify.
- 24:559: "drag the tooth count" while `bigTeeth` is read only in `setup()`. Verify on the Mac.
- C:172: `loadImage` throws (`API/Ollin.txt:2298`), it doesn't return an optional. C:200: there is no bare `camera()`.

Chapter pointers aimed at the wrong place:

- 10:13: "since Chapter 6"; `Vector2` first appears in Ch 1 (1:188).
- 14:85: Chladni figures credited to Chapter 19; they are in Ch 17 (17:348).
- 16:42: `drawImage` credited to Chapter 8; it is Ch 9.
- 16:429: "the `sample` you met in the filters above"; no `sample` appears above.
- 16:515: "The section above asked every pixel how far away"; that section is 16:377, not the one above.
- 17:143: promises Chladni returns in Ch 19 and Ch 28; neither has it.
- 18:60: says Ch 19 zooms into the Mandelbrot set; the zoom is in Ch 18 (18:216).
- 19:78: `DifferentialGrowth` sent to Ch 12; it is taught in Ch 13 (13:181).
- 22:609, 22:625: describe Ch 21 features (a band count, a `subsurface` glow) that Ch 21 doesn't teach. 22:270: cites a `subtract { }` block that Ch 26 never shows.
- 23:163: blue noise "met in Chapter 13"; it is explained in Ch 15 (15:502).
- 24:15: "the scene the last chapter built" means Ch 21, not Ch 23.
- 26:307: "every light in the last two chapters" now means the physics chapters.
- 15:602: `noClear()` credited to Ch 16; Ch 12 introduces it (12:401).
- 3:47: promises Ch 32 "puts it to work on a real piece"; nothing does.
- 32:571: "the same wrapper the next section describes"; the next section is the widget, the wrapper is at 32:629.
- 12:468, 12:478: differential growth's credit and example belong to Ch 13.
- 13:322, 13:523: chaos-game leftovers; the material is in Ch 18.
- E:233 and E's Go deeper: meshes are loaded in Ch 22, not Ch 21. E:310: `--keep-clock` is in Ch 31, not Ch 1.
- D:24, D:63, D:64, D:91, D:149, D:304: the six Appendix D pointers listed in `digests/D.md`.

Statements that are false:

- 2:73: says the guide has no math behind OKLab; Appendix B § Color and light as numbers has it.
- 2:106: "never on green"; the HSB row of the figure at 2:62 passes through green.
- 2:299: "Three sentences will get you through it"; seven follow.
- 4:9: calls Ch 2's finale a "poster"; it is a color field. 4:153: says `drawLine` hasn't been written out; Ch 1 shows it (1:174).
- 5:9: "Chapter 4 ended with a complaint"; Ch 4 now ends elsewhere.
- 11:289 against 11:505 and 11:624: four assembled systems, then three.
- 12:150: "Nobody in either panel ever runs in a straight line"; the quarry does (12:139).
- 13:53: "2⁹ tips, five hundred twelve"; the tree has 256 tips and 511 segments. Verify against the figure.
- 13:164: "an L-system grows forever" against 13:108.
- 17:53: says Metal's `mix` has "the same meanings" as before; `Color.mix` blends in OKLab by default, Metal's `mix` per channel.
- 18:85: "The third" is now the fourth of "Four more games".
- 19:329, 19:340, 19:577: the same feed/kill pair (0.055/0.062) is called dividing dots, a maze, and a mitosis regime. Verify.
- 20:197: "as the last section" (the caveat is at 20:93); 20:201: "the only search" against the heading at 20:95.
- 22:684, 22:717: "the model the chapter opened with" is the crystal; the chapter opened with a duck (22:26). "Cushion" names two different objects (22:9, 22:730).
- 24:44 against 24:564: "this exact wreck replays every run" and "they tumble differently on every run".
- 26:519: Molten "finished as glass" uses `.dielectric(roughness: 0.07)`.
- 30:276: "the words" and "the card"; the saliency figure is the marigold portrait. 30:280: "these three" covers five types. 30:491: "the interactive mirror promised at the top"; the top promised a painting.
- 31:156: "3.6 seconds long by the end of an hour" reads as a slip for "3.6 seconds off". 31:473: "Every export so far has been a picture of the sketch" is false after SVG and the 3D print.
- 32:684: justifies `loopDuration` by a shader clock the piece doesn't use. 32:757: runs `Example-Installation-Unattended` instead of the reader's `WallPiece.swift`.
- "Uses everything" claims: 3:9, 5:208, 6:357, 14:200, 15:839, 29:1019, 31:1114. Fix each to say what the piece uses.
- A:205: the guide meets `if let` before `??`. A:257: the guide does throw, and Ch 30's prose never writes `try await`.

The front door:

- `Guide/README.md` contents lines for Ch 7, 9, 12, 13, 15, 18, 23, 26, 28, 30 no longer match their chapters (the digests list what each omits or misplaces).
- `Guide/README.md` "How to read it": Part III is not the shortest part; Chapter 18 writes no shader; the page counts don't follow one rule.

## Open questions for @eaviles

See the end of `PROPOSAL.md`.

## The Mac list

Nothing yet. Session 1 changed no figure, snippet, or chapter.
