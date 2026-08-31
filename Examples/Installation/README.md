#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Installation</sup>

---

## Installation

Pieces made to be left running: on a wall, in a shop window, at a stand for the length of a fair.

| Example | What it shows |
|---|---|
| [Unattended](Unattended/Sketch.swift) | `installation`, the one line that fills the screen, hides the pointer, and keeps the display awake, plus the clock restart a run of weeks needs |
| [Watched](Watched/Sketch.swift) | `restarts`, the watch that starts the piece again, over `@Saved` state and a checkpoint cadence: press **c** to crash it and **h** to hang it, and see it come back with a ring per run; quit it and run it again, and the record carries on |
| [Hours](Hours/Sketch.swift) | `schedule`, a piece that keeps the building's hours and changes with the day inside them, read through `scheduledPeriod` and `scheduledProgress` |
| [Fitted](Fitted/Sketch.swift) | `projection`, lining the picture up with the wall it is thrown onto: press **Command-K**, drag the four corners, and the numbers are kept under that display |
| [ManyDisplays](ManyDisplays/Sketch.swift) | `displays`, one long canvas across every display the machine drives: add `--rehearse 3` to lay that wall out as three windows on one desk |
| [ManyWindows](ManyWindows/Sketch.swift) | `canvasOnScreen`, one world seen through several windows: run it three times, drag them apart, and the dots drift out of one and into the next |

Run one from this `Examples/` directory with `swift run Example-Installation-<Name>`, e.g. `swift run Example-Installation-Unattended`. It takes the whole screen; Command-Q quits.

To work on one in an ordinary window, add `--no-installation`. To put any other sketch up for an evening, run that one with `--installation`. See [`Docs/Output/Installation.md`](../../Docs/Output/Installation.md).
