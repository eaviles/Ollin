#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Installation</sup>

---

## Installation

These pieces are made to be left running: on a wall, in a shop window, or at a stand for the length of a fair.

| Example | What it shows |
|---|---|
| [Unattended](Unattended/Sketch.swift) | `installation`, the one line that fills the screen, hides the pointer, and keeps the display awake. It also shows the clock restart that a run of weeks needs |
| [Watched](Watched/Sketch.swift) | `restarts`, the watch that starts the piece again, together with `@Saved` state and a checkpoint cadence. Press **c** to crash the piece and **h** to hang it, and it comes back with one ring per run. Quit it and run it again, and the record carries on |
| [Hours](Hours/Sketch.swift) | `schedule`, a piece that keeps the building's hours and changes with the time of day inside them. The sketch reads the schedule through `scheduledPeriod` and `scheduledProgress` |
| [Fitted](Fitted/Sketch.swift) | `projection`, which lines the picture up with the wall it is projected onto. Press **Command-K** and drag the four corners, and the numbers are kept under that display |
| [ManyDisplays](ManyDisplays/Sketch.swift) | `displays`, one long canvas across every display the machine drives. Add `--rehearse 3` to lay that wall out as three windows on one desk |
| [ManyWindows](ManyWindows/Sketch.swift) | `canvasOnScreen`, one world seen through several windows. Run it three times and drag the windows apart, and the dots drift out of one window and into the next |

Run one from this `Examples/` directory with `swift run Example-Installation-<Name>`, e.g. `swift run Example-Installation-Unattended`. It takes the whole screen, and Command-Q quits.

To work on one in an ordinary window, add `--no-installation`. To put any other sketch up for an evening, run that one with `--installation`. See [`Docs/Output/Installation.md`](../../Docs/Output/Installation.md) for the full reference.
