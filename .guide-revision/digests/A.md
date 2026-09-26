# A. Just enough Swift (`A-JustEnoughSwift.md`)

Size: 2,020 prose words, 15 `##` and 0 `###` sections, 270 lines. Appendix (no part). Opening figure: `Meteors.jpg` (line 52), sixty streaks crossing a night sky, from the one complete listing (line 17).

## Sections

| Line | Heading | Words | Teaches / the reader makes |
|---|---|---|---|
| 5 | # A. Just enough Swift (intro) | 188 | Promise: all the guide's Swift, nothing more; points to `Docs/Swift.md` and Appendix C. |
| 13 | One sketch, top to bottom | 95 | `Meteors` listing; the only canvas output. |
| 56 | Naming values: `let` and `var` | 90 | `let` first, `var` for state across frames. |
| 69 | Types, mostly invisible | 124 | Inference; spell the type for an empty array. |
| 83 | Two kinds of number | 153 | `Int`/`Double`, integer division, conversions, `Float` at the borders. |
| 104 | Functions and their labels | 165 | `func`, labels, `_`, defaults. |
| 120 | Choosing and repeating | 86 | `if`, ternary, ranges, `for _`, `while`. |
| 141 | Arrays | 73 | append/count/index/removeFirst, `enumerated`, `map`, `filter`. |
| 161 | Classes and structs, or who copies | 347 | `final class`, `override`, `self`, value vs reference, immutable structs, `with(x:)`. |
| 185 | Closures: functions as values | 124 | Trailing closures, `withState`, `$0`, capture. |
| 201 | Optionals: maybe a value, maybe nothing | 112 | `??`, `if let`, `guard let`, `?.`. |
| 225 | Enums and the leading dot | 94 | Closed typed cases, `.pie`. |
| 231 | Property wrappers: properties with machinery | 102 | `@Param`, `@Eased`, `@Smoothed`, `$size`. |
| 245 | Strings, briefly | 45 | Interpolation, `"""`. |
| 255 | What the guide never needed | 135 | `throws`, `async`, protocols skippable. |
| 261 | Go deeper | 79 | Swift.md, C, Ch 1, Examples. |

## What the appendix promises against what it delivers

Line 7 promises "every piece of Swift the guide leans on"; it covers the core but misses much the chapters type. Swift notes by first appearance (16 chapters, as line 7 says):

| Chapter:line | Introduces |
|---|---|
| 1:89, 190, 192, 269, 443 | class/`override`; `Vector2`; labels, leading dot; `let`/`var`; ranges, `Double(i)`, `[Color]`, `%` |
| 2:29, 352 | optional, `if let`, force unwrap `!`; properties |
| 4:40, 187 | `for _`; `Int(...)`, `min` |
| 6:57, 112, 155 | chaining; ternary, trailing block; `func` |
| 8:65, 125 | `??`; `.map { }` |
| 9:564 | `guard let`; `Array(string)` |
| 10:215; 11:160, 226; 12:42 | array ops, `.indices`; class as reference, `?.`; `let` on a class |
| 13:59, 483; 17:55; 21:64 | recursion, `filter`; `"""`; defaults |
| 22:42; 27:31; 28:34 | `try?`; `[Float]`; `Float` to `Double` |
| 30:85, 487 | `lazy var`; `Ollin.SlitScan` |

A's order roughly tracks this, with enums and `@Param` (Ch 1) moved last. The reported gaps:

- `&` inout (Ch 4:64, 15:387, 18:53): absent.
- `try!` and throwing (Ch 2:178 first, seven chapters; bare `try` at Ch 24:343): absent; A's lines 212 and 220 use `try?` unexplained.
- `zip` (Ch 7:56), key paths (`\.corners`, Ch 7:250, six uses): absent. Ch 7:250 is the guide's first `.map`, before Ch 8's note.
- Implicitly unwrapped optionals: absent; first at Ch 12:252 (not 13), 18 declarations. Force unwrap `!` (Ch 2:29) too.
- `.map`: covered (lines 154, 197), closure form only.

Also absent: `override var canvasSize` (Ch 1:138), `lazy var` (Ch 20:18, noted only at Ch 30:85), `switch` (Ch 18:333), `stride` (Ch 14:74), `%`, recursion, own types with `init` (Ch 11:542), `extension Sketch` (Ch 31:780).

## Seams and catalog signs

- Line 205, "in the order the guide meets them": lists `??` first; the guide meets `if let` first (Ch 2:29), `??` at Ch 8:65.
- Line 257: Ch 30's prose never writes `try await` (only its figure source), and "asks for one of them once" ignores throwing.
- Line 120's heading hides `if` and loops.

## Cold starts and dropped-in sections

- None found.

## Techniques given only through their API

- Line 217, `guard let source else` shorthand; line 31, hex literal `0x101623`: both unexplained.

## Concepts used before they are introduced

- Line 154: closures (`{ $0.x }`), first explained at line 185.
- Line 212: `try?`; nowhere in A.

## Creative coding as a practice

- Only line 54 (edit along in OllinLive) and line 266 (read `Examples/`).
- Line 81: errors are caught "the moment you save", but not where they show, or that the last good sketch keeps running.

## Voice: the worst paragraphs

- Line 85, "the section to read if you only read one": significance announcement.
- Line 174, "which is a quiet gift": overselling.
- Line 223, "what *doesn't* happen … mostly isn't a thing": false negative.
- Line 229, "That's the whole trade against strings, and it's a good one.": punchline.
- Line 183, "easy to miss": reader prediction.
- Line 266, "the fastest Swift course there is": overselling.

## Overlap with other chapters

- `Docs/Swift.md` (confirmed): 9 of its 10 sections repeat A's in order, with identical examples (`let radius = 120.0`, `1 / 2 // 0`, the `withState` block, the misspelled-`draw` sentence). A adds structs, enums, wrappers, ternary, `filter`. Both share every gap. Only Ch 1 and 32 link A.
- Appendix C line 222 repeats line 81 almost verbatim ("tends to behave").

## Candidate moves

- Add a section on Swift seen in listings: `!`, IUO, `try`/`try?`/`try!`, `&`, key paths, `zip`, `lazy var`, `override var`, `switch`, `stride`, `init`. Fix line 257.
- Fix line 205's order; put Arrays after Closures.
- Make `Docs/Swift.md` a lookup page into A's anchors; have Swift notes link A.
