# Guide authoring charter

How the [Ollin Guide](README.md) gets written. Every writing session follows this file so that 20+ chapters written months apart read as one coherent guide. The chapter queue and briefs live in [PLAN.md](PLAN.md); this file is the how.

## The four principles

The Guide exists because good books on this subject keep failing in the same four ways. Each failure has a rule here, and the rules are checkable, not aspirational.

**1. Nothing arrives unexplained.**
The founding story: @eaviles got stuck at chapter 5 of the Book of Shaders because `smoothstep` was used before it was ever really explained, and that was the end of the book. One unexplained concept can cost the whole reader.
The rule: before a chapter uses any concept (in prose, in a listing, or inside a figure), it must appear in an earlier chapter, earlier in the same chapter, or in Appendix B. While writing, keep a running list of every concept the chapter leans on and check each one. When math appears, it gets three things together: a picture, a plain-words intuition, and only then the code. Notation alone is never enough.
The check ("the smoothstep test"): reread each page asking, could someone with no math background follow this page using only what the guide has shown so far? If not, teach the missing piece or cut the dependency.

**2. The Guide can't rot.**
Books about living software go stale; readers hit examples that no longer compile and conclude they're the problem.
The rule: every listing lives as a compilable figure sketch under `Figures/`, and `Scripts/guide-figures.sh` compiles and renders all of them. Run it before every commit that touches the Guide. A failing figure blocks the commit. (This is a local gate on purpose, not a CI job, because a virtualized runner cannot run the Vision figures or match anyone's GPU. The reasoning is in PLAN.md.)

**3. Everything runs, every image is honest.**
The rule: every image under `Images/` is produced by the figure runner from a committed sketch, never hand-made, never edited after render. Prose listings are a figure file verbatim, or a clearly labeled delta of one ("add this line to `Swarm.swift`"). If a listing can't be a runnable file, rewrite it until it can.

**4. Practice first, tiny steps.**
The rule: something appears on the reader's canvas within the first page of every chapter. Concepts arrive in steps small enough that each one produces a visible change. Theory that doesn't change what's on the canvas within a page or two gets cut or moved to an appendix. Every chapter ends with a finished piece that composes what it taught, under a `## Putting it together: <name>` heading.

## Voice and style

- Plain, warm, and humble. Second person for the reader ("you draw a circle"), first person plural sparingly for shared moves ("let's slow this down"). Never lecture.
- Short sentences where possible. One idea per paragraph. Read it aloud; if it sounds like documentation, loosen it, if it sounds like marketing, flatten it, and if it sounds pleased with itself, say it straight.
- Explain in a simple, practical way: what a thing is, what it does, and how you use it, in terms the reader can act on. Given a clever explanation and a practical one, pick practical.
- Mostly ordinary sentences. Compression is its own kind of performing: prose where every sentence lands an epigram or a clever appositive reads as written by a machine, however plain the words. Vary sentence length, let plain sentences carry the explanation, and budget roughly one memorable line per section. Don't reuse a signature phrasing from an earlier chapter.
- **Write what a teacher would say out loud.** This is the test that settles most style questions. A teacher explaining something at a whiteboard connects one sentence to the next ("so", "because", "once you do that", "which means"); they don't deliver a series of separate pronouncements and leave the listener to work out the joins. Prose that reads as jumpy is almost always missing those joins.
- **Watch the colon habit.** The `setup: punchline` sentence is a small drum hit, and a page of them is exhausting to read even when each one is good. It is the single most common cause of jumpy prose in this guide. Keep sentence-internal colons to roughly one every four or five prose lines, and reach for them when a genuine list or definition follows. When counting a draft, the same budget covers the semicolon-joined compound sentence, which is the same move wearing a different hat. Most of them convert to an ordinary sentence with a connective word, and the paragraph reads better for it.
- **Keep a sentence under 25 words.** Past that, a sentence is nearly always two sentences held together by a colon, a semicolon, or a parenthesis. The reader carries the first half while working through the second. Splitting it costs nothing and usually improves the paragraph. A catalog line or a table row can run longer, because a list is not a sentence; running prose should not.
- **One aside per paragraph, never nested.** The parenthesis is this repo's favourite tool and its most tiring one: a good sentence with two more sentences pushed inside it. Keep the aside that carries the reader, promote the next one to its own sentence, and delete the third. Most of them go without loss, and the sentence they were hiding in gets easier to read.
- **Three nouns in a row is the limit.** "Weighted Voronoi stipple density map" asks the reader to work out which noun modifies which before they can read the sentence around it. Break the pile with a preposition: "the stipple density map, from a weighted Voronoi".
- **A warning gets a flatter voice than an explanation.** Someone reading a gotcha note has a broken sketch in front of them, so the note drops the teaching connectives. One fact per sentence, active voice, the action as an instruction. Say what happens, why, and what to do instead. The warmth belongs in the paragraph that teaches the idea, not in the sentence that tells someone their texture is empty.
- **Don't open a section with a fragment.** "Now the heart of the chapter." and "Time to build the piece." are stage directions, not teaching. Write the full sentence: "This is the heart of the chapter."
- Prefer plain words for a concept's payoff over the language of wagers and returns. "The bet", "the payoff", "pays off", "earns its keep", and "the win" all frame the reader's learning as an investment. Say what actually happens instead: what the technique does, or what it saves you.
- Plain words (the Apple Style Guide rule: choose words that are easily understood, and if you can use fewer, do). Prefer the common word over the vivid rare one: jitter, not stagger; awkward, not clumsy; gaps, not droughts. Many readers won't have English as a first language; a word they'd need a dictionary for costs more than it adds.
- Metaphors must teach. One that carries a concept (the noise landscape, the zoom knob, the tile doorways) earns its place; a decorative one ("pays the debt in full", a function with moods or a soul) gets cut. One metaphor per idea, never stacked, never stretched across chapters, and no personified code unless the personification is the explanation.
- Natural flow over clever flow. No fragment-as-transition ("Everything at once."), no inverted openers ("Six-three-one: ..."), no chains of matched clauses where a plain sentence would do. Write the sentence a good teacher would say out loud.
- No em dashes anywhere in the Guide (repo-wide rule, enforced by tooling). Use commas, colons, parentheses, or a new sentence.
- An ellipsis is the single character "…", never three dots. A Swift range spelled in prose goes in backticks as code (`0...1`); there the three dots are the operator.
- Sentence case for headings and chapter titles.
- The Guide calls itself "the guide" (or "this guide"), never "the book". Real books keep their titles.
- It's fine to say something is hard, and to say when a technique's result is only "usually good". Honesty beats polish.
- Influences are named openly and generously in prose (Nature of Code, the Book of Shaders, Processing, p5.js, OPENRNDR are part of the story and get credit). Inside `.swift` figure files the repo rule applies: no external framework or product names in comments.
- Run the humanizer pass over every chapter before it ships.
- Jokes are allowed. One per chapter is probably plenty.
- The checkable subset of these rules runs as a lint: `Scripts/prose-lint.sh`. It is Vale, configured by `.vale.ini` plus the custom rules in `.vale/styles/OllinGuide`, and the first run needs `brew install vale`. Errors block a commit; warnings are judgment prompts, fix them or keep them on purpose. The same lint covers `Docs/` and the reader-facing `README.md` files, which share the plain-words bar in their own reference tone. The sentence-length rule opens as a suggestion in `Docs/` and converts page by page, the way the em-dash rule did.
- `Scripts/prose-density.sh` is the page-level companion to that lint. It scores three habits per page: prose lines per colon or semicolon, the share of sentences over 25 words, and asides per paragraph. The goals are 2.5 or above, 20 or below, and 1.5 or below, and a star marks a page well past one of them. Vale finds the sentence; this tells you whether the page has a habit, which is the thing worth fixing. Run it on a page you are about to edit, and again after.

**These voice rules are not Guide-only.** They apply to every page a reader lands on: `Docs/`, the repository `README.md`, and the per-folder READMEs. The Guide is warm and second-person while `Docs/` is neutral and terse, but the teacher test, the colon budget, the fragment rule, and the plain-words bar hold in both. A session correcting prose anywhere in the repository works from this section.

## Chapter anatomy

A chapter is one markdown file, `NN-PascalCase.md`, and reads like this:

1. **The hook.** An image of the finished piece and two or three sentences on where the chapter is going. No throat-clearing.
2. **Steps.** Small numbered or titled sections, each introducing one idea, each with visible output. Code appears as a full small sketch first, then deltas. Swift-language notes appear as short callout blocks (`> **Swift note.** ...`) at the exact moment the reader first needs them, and only for what the step needs.
3. **Putting it together.** The finished piece, built from the chapter's steps, with its full listing (it lives in `Figures/` like everything else) and a rendered image. End by inviting two or three specific variations to try.
4. **Where this comes from.** A short paragraph crediting the technique's originators and canonical sources, consistent with `ATTRIBUTION.md`. This is a feature of the guide: readers learn the field's history and where to read more.
5. **Go deeper.** Links into `Docs/` pages (this is also how the coverage audit works) and related `Examples/`.

Keep chapters honest about hardware: anything needing a device beyond the Mac (a MIDI controller, an iPhone) leads with the path every reader can follow and treats the hardware as the bonus.

## How big a chapter gets, and when it becomes two

A chapter that reads well runs about 2,000 to 8,000 words over 10 to 14 sections. That is not a budget to write to. It is the range the best-reading chapters already sit in, and it is worth knowing because the failure it describes cannot be seen from inside a session.

The failure is quiet. Each session adds one section to the chapter its feature was assigned to, and every one of those additions is correct and passes every gate. Then one day the chapter is a catalog. That is how a chapter here reached 24,511 words and 48 flat sections with nothing ever catching it, because nothing was wrong with any single step.

So watch for the three signs, which arrive in this order:

- **The payoff stops paying.** The rule is that the finished piece composes what the chapter taught. When it composes a quarter of it, the chapter is carrying more than one subject and the piece is quietly choosing one.
- **The prose announces a seam.** A sentence like "the other half of GPU simulation evolves particles" is a chapter boundary written in the voice of a transition. So is a section that opens by disclaiming its own membership.
- **The headings stop working as retrieval.** Evocative headings read beautifully and find nothing at 20 sections, which is why grown chapters need the technique name riding the heading.

When a chapter does split, split it at a seam the prose already has, and give each half the whole anatomy. A new chapter is not a slice. It needs its own hook, its own finished piece, its own credits, and its own "Go deeper", and the parent's credits paragraph for whatever left travels with it. Renumbering is `Scripts/guide-renumber.sh`, and `Scripts/guide-links.sh` is what proves the move landed.

## Figures

Figure sketches live in `Figures/<NN-ChapterName>/<FigureName>.swift`, rendered to `Images/<NN-ChapterName>/<FigureName>.jpg` (or `.png`/`.gif`) by the runner. Conventions:

- A figure file is an ordinary Ollin sketch (a `class ... : Sketch`), self-contained, with no dependencies beyond the framework.
- **Pin the seed in any figure that touches `random` or `noise`.** A sketch's `variation` is rolled fresh at launch, so an unseeded figure re-renders differently every run and shows up as churn in `git status` after each full gate. Call `seed(_:)` (or `noiseSeed(_:)`) in the figure. The check is to render twice and `cmp` the output. The exceptions are the `// figure: unstable` set below, which are genuinely not reproducible; restore those rather than committing them.
- The first line may carry a directive comment configuring the render:
  - `// figure: frame=120` renders that frame as a still (default: `frame=0`).
  - `// figure: gif duration=3 fps=30` renders an animated GIF loop.
  - Stills are JPEG (quality 0.85) by default: the renderer's anti-banding dither is per-pixel noise, so PNGs of even flat diagrams weigh hundreds of kilobytes for no visible gain at the Guide's display widths. `format=png` opts one figure back into lossless, for the rare image that needs it.
- Diagrams are figures too, drawn with Ollin (that's the point: the diagrams are reproducible and are themselves example code). Use a small canvas for diagrams (`override var canvasSize: CanvasSize { .size(880, 550) }` is a good default), the system outline font for labels, and keep them monochrome-plus-one-accent so they read as diagrams, not artwork.
- Payoff pieces render at the default square canvas unless the piece wants otherwise.
- GIFs are used sparingly (motion the prose genuinely can't convey), short (2 to 4 seconds), and small; they weigh on the repository forever.
- Every image referenced from a chapter must exist in `Images/` and come from the runner; the reverse also holds, no orphaned figures.
- Embed images with an `<img>` tag carrying a display `width`, never a bare markdown image; a full-bleed 1080-pixel image dominates the page and hurts reading. House widths: `680` for the wide 880×550 diagrams, `560` for square art and finished pieces, `480` for GIFs. Always keep the `alt` text. (This is the one sanctioned bit of HTML in the Guide; everything else stays plain markdown.)

- **A figure that needs a file from the repository cannot find it with `#filePath`.** Figures are compiled from a copy in a work directory, so a figure's own path leads nowhere near the checkout, and `Bundle.module` resolves to the figure's folder rather than the repository. The runner sets the working directory to the repository root, so walk up from `FileManager.default.currentDirectoryPath` until the path you want exists. Chapter 21's `SceneAsSource` does this to reach an example's scene file, and the symptom of getting it wrong is an empty panel rather than an error.
- **A figure that analyzes a still with `waitFor` must not read the sketch's own properties inside the closure.** `waitFor` parks the main thread, and a sketch's properties (static ones too) are main-actor isolated, so a read from inside the closure waits on the parked thread and the figure hangs forever with nothing printed. Read the values into locals first. Chapter 29's `AttentionAndLabels` hit this and looked exactly like a Neural Engine deadlock.
- **A figure whose render genuinely cannot reproduce carries `// figure: unstable`.** Only a handful do: the GPU particle sims in `20-ParticleSimulations` (`ArtificialLife`, `Evolution`, `FluidAndBlobs`, `ParticleLenia`, `SwarmChemistry`) and `10-Vectors/Swarm`, whose neighbor sums are added in an order decided by GPU atomics, `26-SculptingWithFields/CausticLight`, whose photon parcels accumulate in an order decided the same way (the wobble stays under a few counts of 255), `23-Landscapes/FieldWorld` and `23-Landscapes/Valley`, whose GPU cull compacts the surviving copies with atomics so their draw order changes between runs (the same few counts of 255, over a few hundredths of a percent of the frame), and the two driven by system ML models: `29-Seeing/Trajectory`, whose Vision-model parabola fit drifts in its low-order bits across model/OS updates (it renders byte-identically within a session, so the drift only ever shows up as churn after an environment change), and `28-SoundAndControl/Listening`, whose transcriptions and sound labels come from the system's speech and sound models. The runner then verifies them (they still have to compile and render) without rewriting their committed images, so they stop showing up as changes. This is not a way out of pinning a seed; use it only when the framework itself makes no reproducibility promise: a GPU race, or a system ML model Ollin doesn't control.

Rendering:

```sh
Scripts/guide-figures.sh                  # render every figure, fail on any error
Scripts/guide-figures.sh --only Swarm     # just figures whose path contains "Swarm"
Scripts/guide-figures.sh --force          # ignore the cache
Scripts/guide-figures.sh --help           # every option, and how the cache is keyed
```

The runner (`swift run OllinGuideFigures`) compiles each figure with the same loader the live host uses, renders it headlessly, and writes the image beside the chapter's others. A compile error in any figure exits nonzero and names the file and line.

Run the whole suite, not `--only`. It costs about three minutes cold and under a second when nothing changed, because of two things worth knowing about:

- **Unchanged figures are skipped**, using `Guide/.figure-cache.json` (gitignored). A figure re-renders when its own source changes, when its image is missing or was edited by hand, or when the framework moves: anything under `Sources/` or `External/`, the package manifest, or the compiler version. That last rule is deliberately broad, since a renderer change can alter any figure.
- **The work is split across four worker processes.** Sharding rather than threads, because the expensive figures spend their time in `setup()` on the main actor, and only separate processes run those at once.

Both exist for one reason. The full run once took twenty minutes, which is long enough that a session under pressure talks itself into skipping the gate, and a gate nobody runs protects nothing. If a future change pushes the cold run back toward that, treat it as a real problem rather than a fact of life. The runner prints its slowest figures after every run, so you can see where the time is going.

## Coverage: the Guide cannot fall behind the framework

The matrix in [PLAN.md](PLAN.md) is the promise that no capability is merely named in a table. `Scripts/guide-coverage.sh` is what makes the promise checkable, and it is step 5 of the ship checklist in `CLAUDE.md`. It fails when a Docs page has no matrix row, when a row names a page that does not exist, when a page is unreachable from a numbered chapter's "Go deeper" list, when a page is missing from Appendix D, or when any row is still `pointed` without an entry in the Guide debt ledger.

That last rule is the point. **`pointed` is not an acceptable resting place for something that shipped.** The floor is `shown` (a chapter mention plus a worked example) in the same commit that ships the feature, and `taught` is the goal. This is the gap that produced the backlog: a `pointed` row satisfied the old checklist completely, so seven feature slices shipped over two days at the end of July 2026 with one-line table entries and no teaching, and every audit passed because a row existed.

If a session truly cannot teach what it just shipped, the honest move is a Guide debt entry naming the chapter that owes the section, mentioned in the commit message. The script prints every entry on every run, so debt stays visible and countable instead of hiding in a table cell.

## The session workflow

One chapter per session, in this order:

1. Read the chapter's brief in [PLAN.md](PLAN.md), and skim the chapters it builds on (at least their step headings) so terminology stays consistent.
2. Check the brief's parked roadmap items: anything shipped in the framework since the brief was written gets folded in.
3. Build the figures first. Write each figure sketch, render it, and look at it (open the image, verify it shows what the prose will claim). The finished piece usually comes first; it tells you what the steps must teach.
4. Write the prose around the verified figures and listings. Track the concept list against principle 1 as you go.
5. Add the chapter's math ideas to Appendix B (an entry with a picture, in the matching theme group), give its new capabilities rows in Appendix D, and update its "Go deeper" targets in the coverage matrix in PLAN.md (flip rows to their promised depth).
6. Run `Scripts/guide-figures.sh` (all figures, not just the new ones).
7. Humanizer pass over the chapter, plus the plain-words check from *Voice and style* (rare words, decorative metaphor, clever flow). Then run `Scripts/prose-lint.sh` and clear its errors.
8. Update PLAN.md status, link the chapter in `Guide/README.md`'s contents.
9. Run `Scripts/guide-links.sh` and `Scripts/guide-coverage.sh`, and clear both. The first checks that the navigation is real (links, anchors, images, the footer chain, and every chapter pointer including the ones in CAPABILITIES.md); the second checks that the Guide teaches what Ollin ships.
10. Run the docs audit, then commit (Guide chapters are milestones; commit and push per the repo convention).

If the chapter's scope doesn't fit the session, cut whole steps and write the cut back into the PLAN.md brief. Never ship a half-explained concept to save time; that's the one unforgivable failure (principle 1).
