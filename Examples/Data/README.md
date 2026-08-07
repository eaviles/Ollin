#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Data</sup>

---

## Data

Drawing from a file. Both sketches read their data once in `setup()` and let the file decide what the picture looks like: the scale, the colors, and the labels all come out of it rather than being typed into the sketch.

| Example | What it shows |
|---|---|
| [Readings](Readings/Sketch.swift) | a year of readings as a range chart read from a CSV: typed reads by column name, a scale derived from `numbers(_:)`, and notes holding commas and quotation marks that survive the parse |
| [Places](Places/Sketch.swift) | a survey drawn from a JSON document: nested objects reached by name, index pairs looped as paths, and a station missing its color landing on a fallback with no check |

The data in both is invented. What is worth copying is the reading, not the numbers.

See [`Docs/Helpers/Data.md`](../../Docs/Helpers/Data.md) for `loadTable` and `loadJSON`.
