#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Data</sup>

---

## Data

These sketches draw from data. The first two read a file once in `setup()`, and the file decides what the picture looks like. The scale, the colors, and the labels all come out of the file, so none of them is typed into the sketch. The third sketch asks an address again and again, so the picture shows something happening now. The fourth holds one connection open, so every event arrives the moment it happens.

| Example | What it shows |
|---|---|
| [Readings](Readings/Sketch.swift) | a year of readings drawn as a range chart from a CSV file: typed reads by column name, a scale derived from `numbers(_:)`, and notes with commas and quotation marks in them, which survive the parse |
| [Places](Places/Sketch.swift) | a survey drawn from a JSON document: nested objects reached by name, index pairs looped over as paths, and a station with no color that gets a fallback value without a check |
| [Quakes](Quakes/Sketch.swift) | a day of earthquakes read live and re-read again and again: the sketch rebuilds only when the answer changed, keeps the last good list through a failure, and writes what went wrong on the canvas |
| [Edits](Edits/Sketch.swift) | edits to the world's encyclopedia drawn as rain: one connection held open with a `PushFeed`, one drop the moment somebody saves a page, sized by the bytes changed and colored by growth or removal |

The data in the first two sketches is invented. Quakes reads live from the public feed of the United States Geological Survey. Copy how each sketch reads its data, not the numbers.

See [`Docs/Helpers/Data.md`](../../Docs/Helpers/Data.md) for `loadTable` and `loadJSON`, and [`Docs/Helpers/LiveData.md`](../../Docs/Helpers/LiveData.md) for `DataFeed`.
