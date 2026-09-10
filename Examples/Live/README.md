#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Live</sup>

---

## Live

Sketches that show OllinLive features.

| [![Cues](https://media.ollin.art/examples/Live/Cues/still-640.jpg?v=af1e1234)](Cues/) | [![DragToEdit](https://media.ollin.art/examples/Live/DragToEdit/still-640.jpg?v=808bb7cd)](DragToEdit/) | [![Parameters](https://media.ollin.art/examples/Live/Parameters/still-640.jpg?v=e274f8ca)](Parameters/) |  |
|---|---|---|---|
| [Cues](Cues/) | [DragToEdit](DragToEdit/) | [Parameters](Parameters/) |  |

| Example | What it shows |
|---|---|
| [DragToEdit](DragToEdit/Sketch.swift) | Command-drag a shape in the window, and the numbers in this file change. `⌘]` and `⌘[` move the shape's line past its neighbor's line |
| [Parameters](Parameters/Sketch.swift) | the typed `@Param` family, shown in grouped inspector cards under OllinLive |
| [Cues](Cues/Sketch.swift) | the looks a piece was tuned to, saved as cues and called back over a fade: keys 1 to 5 call the five in `Sketch.cues.json`, space the next, and the inspector's Cues card lists, calls, and saves them |

To run one, go to the `Examples/` directory and run `swift run Example-Live-<Name>`, for example `swift run Example-Live-Parameters`. To run it under live reload instead, go to the repo root and run `swift run OllinLive Examples/Live/Parameters/Sketch.swift`.
