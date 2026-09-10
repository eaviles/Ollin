#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Input</sup>

---

## Input

Sketches driven by the mouse and the keyboard.

| [![Drag](https://media.ollin.art/examples/Input/Drag/still-640.jpg?v=1c322e5c)](Drag/) | [![Keys](https://media.ollin.art/examples/Input/Keys/still-640.jpg?v=dcc31a0b)](Keys/) | [![PanAndZoom](https://media.ollin.art/examples/Input/PanAndZoom/still-640.jpg?v=03ea91e2)](PanAndZoom/) | [![RepelGrid](https://media.ollin.art/examples/Input/RepelGrid/still-640.jpg?v=8cfa1fd9)](RepelGrid/) |
|---|---|---|---|
| [Drag](Drag/) | [Keys](Keys/) | [PanAndZoom](PanAndZoom/) | [RepelGrid](RepelGrid/) |

| Example | What it shows |
|---|---|
| [PanAndZoom](PanAndZoom/Sketch.swift) | a generated chart that holds more than one screen shows, so you drag to pan and scroll to zoom. The place names are set at a text size of four units, six for the larger places, which reads as a smudge at the opening view and is crisp four zoom steps in (`viewControl`, `viewZoom`) |
| [RepelGrid](RepelGrid/Sketch.swift) | a grid of dots that move away from the cursor (`mouseX`/`mouseY`) |
| [Keys](Keys/Sketch.swift) | steer a dot with WASD or the arrow keys, both read through one `moveAxis` call. Space changes the color (`keyPressed`), and releasing any key flashes a ring (`keyReleased`) |
| [Pen](Pen/Sketch.swift) | a broad-edged nib that reads a tablet: the chisel lies across the way the pen leans, the press sets how wide, the eraser end takes ink away, and a panel says what the stylus is sending (`stylus`, `pressure`) |
| [Drag](Drag/Sketch.swift) | grab, drag, and throw balls. It uses the press and release hooks, draws the per-frame `mouse - previousMouse` delta as a stretch arrow, and averages the release velocity over the last few frames |

Run one with `swift run Example-Input-<Name>`, for example `swift run Example-Input-RepelGrid`.
