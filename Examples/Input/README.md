#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Input</sup>

---

## Input

Mouse- and keyboard-driven sketches.

| Example | What it shows |
|---|---|
| [PanAndZoom](PanAndZoom/Sketch.swift) | a generated chart with more in it than one screen shows: drag to pan, scroll to zoom, with place names set at four units that are a smudge at the opening view and crisp four notches in (`viewControl`, `viewZoom`) |
| [RepelGrid](RepelGrid/Sketch.swift) | a grid of dots that flee the cursor (`mouseX`/`mouseY`) |
| [Keys](Keys/Sketch.swift) | steer a dot with WASD and the arrows folded into one `moveAxis` read, space to recolor (`keyPressed`), any release flashes a ring (`keyReleased`) |
| [Drag](Drag/Sketch.swift) | grab, drag, and fling balls: the press and release hooks, the `mouse - previousMouse` per-frame delta drawn as a stretch arrow, and a release velocity averaged over the last few frames |

Run one with `swift run Example-Input-<Name>`, e.g. `swift run Example-Input-RepelGrid`.
