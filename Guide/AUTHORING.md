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
The rule: every listing lives as a compilable figure sketch under `Figures/`, and `Scripts/guide-figures.sh` compiles and renders all of them. Run it before every commit that touches the Guide. A failing figure blocks the commit. (CI wiring is deliberately deferred for now; the script is the gate. See PLAN.md.)

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
- The checkable subset of these rules runs as a lint: `Scripts/prose-lint.sh` (Vale; config in `.vale.ini` plus the custom rules in `.vale/styles/OllinGuide`; first run needs `brew install vale`). Errors block a commit; warnings are judgment prompts, fix them or keep them on purpose. The same lint covers `Docs/` and the reader-facing `README.md` files, which share the plain-words bar in their own reference tone.

**These voice rules are not Guide-only.** They apply to every page a reader lands on: `Docs/`, the repository `README.md`, and the per-folder READMEs. The Guide is warm and second-person while `Docs/` is neutral and terse, but the teacher test, the colon budget, the fragment rule, and the plain-words bar hold in both. A session correcting prose anywhere in the repository works from this section.

## Chapter anatomy

A chapter is one markdown file, `NN-PascalCase.md`, and reads like this:

1. **The hook.** An image of the finished piece and two or three sentences on where the chapter is going. No throat-clearing.
2. **Steps.** Small numbered or titled sections, each introducing one idea, each with visible output. Code appears as a full small sketch first, then deltas. Swift-language notes appear as short callout blocks (`> **Swift note.** ...`) at the exact moment the reader first needs them, and only for what the step needs.
3. **Putting it together.** The finished piece, built from the chapter's steps, with its full listing (it lives in `Figures/` like everything else) and a rendered image. End by inviting two or three specific variations to try.
4. **Where this comes from.** A short paragraph crediting the technique's originators and canonical sources, consistent with `ATTRIBUTION.md`. This is a feature of the guide: readers learn the field's history and where to read more.
5. **Go deeper.** Links into `Docs/` pages (this is also how the coverage audit works) and related `Examples/`.

Keep chapters honest about hardware: anything needing a device beyond the Mac (a MIDI controller, an iPhone) leads with the path every reader can follow and treats the hardware as the bonus.

## Figures

Figure sketches live in `Figures/<NN-ChapterName>/<FigureName>.swift`, rendered to `Images/<NN-ChapterName>/<FigureName>.jpg` (or `.png`/`.gif`) by the runner. Conventions:

- A figure file is an ordinary Ollin sketch (a `class ... : Sketch`), self-contained, with no dependencies beyond the framework.
- The first line may carry a directive comment configuring the render:
  - `// figure: frame=120` renders that frame as a still (default: `frame=0`).
  - `// figure: gif duration=3 fps=30` renders an animated GIF loop.
  - Stills are JPEG (quality 0.85) by default: the renderer's anti-banding dither is per-pixel noise, so PNGs of even flat diagrams weigh hundreds of kilobytes for no visible gain at the Guide's display widths. `format=png` opts one figure back into lossless, for the rare image that needs it.
- Diagrams are figures too, drawn with Ollin (that's the point: the diagrams are reproducible and are themselves example code). Use a small canvas for diagrams (`override var canvasSize: CanvasSize { .size(880, 550) }` is a good default), the system outline font for labels, and keep them monochrome-plus-one-accent so they read as diagrams, not artwork.
- Payoff pieces render at the default square canvas unless the piece wants otherwise.
- GIFs are used sparingly (motion the prose genuinely can't convey), short (2 to 4 seconds), and small; they weigh on the repository forever.
- Every image referenced from a chapter must exist in `Images/` and come from the runner; the reverse also holds, no orphaned figures.
- Embed images with an `<img>` tag carrying a display `width`, never a bare markdown image; a full-bleed 1080-pixel image dominates the page and hurts reading. House widths: `680` for the wide 880×550 diagrams, `560` for square art and finished pieces, `480` for GIFs. Always keep the `alt` text. (This is the one sanctioned bit of HTML in the Guide; everything else stays plain markdown.)

Rendering:

```sh
Scripts/guide-figures.sh                  # render every figure, fail on any error
Scripts/guide-figures.sh --only Swarm     # just figures whose path contains "Swarm"
```

The runner (`swift run OllinGuideFigures`) compiles each figure with the same loader the live host uses, renders it headlessly, and writes the image beside the chapter's others. A compile error in any figure exits nonzero and names the file and line.

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
9. Run the docs audit, then commit (Guide chapters are milestones; commit and push per the repo convention).

If the chapter's scope doesn't fit the session, cut whole steps and write the cut back into the PLAN.md brief. Never ship a half-explained concept to save time; that's the one unforgivable failure (principle 1).
