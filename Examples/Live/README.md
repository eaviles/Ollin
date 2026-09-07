#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Live</sup>

---

## Live

Sketches that show OllinLive features.

| Example | What it shows |
|---|---|
| [DragToEdit](DragToEdit/Sketch.swift) | Command-drag a shape in the window, and the numbers in this file change. `⌘]` and `⌘[` move the shape's line past its neighbor's line |
| [Parameters](Parameters/Sketch.swift) | the typed `@Param` family, shown in grouped inspector cards under OllinLive |
| [DescribedLook](DescribedLook/Sketch.swift) | a look asked for in words: type a phrase, press Return, and the parameters it concerns move on this Mac's own model (`tuneParameters(toward:)`) |

To run one, go to the `Examples/` directory and run `swift run Example-Live-<Name>`, for example `swift run Example-Live-Parameters`. To run it under live reload instead, go to the repo root and run `swift run OllinLive Examples/Live/Parameters/Sketch.swift`.
