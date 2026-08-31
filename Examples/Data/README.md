#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Data</sup>

---

## Data

Drawing from data. The first two sketches read a file once in `setup()` and let it decide what the picture looks like: the scale, the colors, and the labels all come out of the file rather than being typed into the sketch. The third keeps asking an address, so the picture is of something happening now, and the fourth holds one connection open so every event lands the moment it happens.

| Example | What it shows |
|---|---|
| [Readings](Readings/Sketch.swift) | a year of readings as a range chart read from a CSV: typed reads by column name, a scale derived from `numbers(_:)`, and notes holding commas and quotation marks that survive the parse |
| [Places](Places/Sketch.swift) | a survey drawn from a JSON document: nested objects reached by name, index pairs looped as paths, and a station missing its color landing on a fallback with no check |
| [Quakes](Quakes/Sketch.swift) | a day of earthquakes read live over and over: rebuilding only when the answer changed, keeping the last good list through a failure, and saying what went wrong on the canvas |
| [Edits](Edits/Sketch.swift) | the world's encyclopedia being edited, drawn as rain: one connection held open with a `PushFeed`, a drop the moment somebody saves a page, sized by the bytes changed and colored by growth or removal |

The data in the first two is invented. Quakes reads the United States Geological Survey's public feed, live. What is worth copying is the reading, not the numbers.

See [`Docs/Helpers/Data.md`](../../Docs/Helpers/Data.md) for `loadTable` and `loadJSON`, and [`Docs/Helpers/LiveData.md`](../../Docs/Helpers/LiveData.md) for `DataFeed`.
