#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Basic</sup>

---

## Basic

These examples are the smallest starting point. They cover a first breathing circle, the shape of a sketch, and the `extend(...)` seam.

| [![Describing](https://media.ollin.art/examples/Basic/Describing/still-640.jpg?v=614673a6)](Describing/) | [![Guides](https://media.ollin.art/examples/Basic/Guides/still-640.jpg?v=a0cf7472)](Guides/) | [![HelloCircle](https://media.ollin.art/examples/Basic/HelloCircle/still-640.jpg?v=45527360)](HelloCircle/) | [![NormalizedCoordinates](https://media.ollin.art/examples/Basic/NormalizedCoordinates/still-640.jpg?v=1e6882f1)](NormalizedCoordinates/) |
|---|---|---|---|
| [Describing](Describing/) | [Guides](Guides/) | [HelloCircle](HelloCircle/) | [NormalizedCoordinates](NormalizedCoordinates/) |

| Example | What it shows |
|---|---|
| [HelloCircle](HelloCircle/Sketch.swift) | the smallest program: a breathing circle. `draw()` runs continuously, so the motion is one `time` term and there is no `loop()` call |
| [NormalizedCoordinates](NormalizedCoordinates/Sketch.swift) | placing things by fraction, so a sketch fits any canvas |
| [Guides](Guides/Sketch.swift) | the `extend(...)` seam: an overlay that draws over the sketch |
| [Describing](Describing/Sketch.swift) | `describe`: a sketch that says what it shows, for a screen reader |

Run one with `swift run Example-Basic-<Name>`, for example `swift run Example-Basic-HelloCircle`.
