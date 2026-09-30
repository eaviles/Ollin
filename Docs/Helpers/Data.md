#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Data`</sup>

---

## Data

Read a CSV, a TSV, or a JSON file and draw from it. Reading a file is slow next to drawing one frame, so each loader runs once. Call it in `setup()`, keep the result in a property, and read it in `draw()`.

Both loaders throw a `FileError` when a file can't be read or holds nothing usable: `missing` when nothing is there, `unreadable` when the bytes are not a table or JSON, each with the path and a sentence. Write `try!` to stop the sketch with that sentence, or `try?` to carry on with `nil`, so a missing asset or a bad download shows up as an empty sketch you can report rather than a crash.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/09-Pictures/DataAsMaterial-dark.jpg">
  <img src="../../Guide/Images/09-Pictures/DataAsMaterial.jpg" alt="Left, five lines of a CSV file in a pixel font, the header and one quoted row picked out in dark ink. Right, the four data rows as colored horizontal bars labeled Oslo, Bath Maine, Kyoto, and Lima, each sized by its number" width="680">
</picture>

### Contents

- [loadTable](#loadTable)
- [Table](#Table)
- [Reading rows](#rows)
- [Reading columns](#columns)
- [Mapping a column to a mark](#mapping)
- [How a file is read](#parsing)
- [loadJSON](#loadJSON)
- [JSON](#JSON)
- [Reaching through a document](#reaching)
- [When you want a type instead](#codable)
- [Files beside the sketch](#sketchResource)

<a name="loadTable"></a>

### loadTable

```swift
func loadTable(_ path: String, format: TableFormat = .auto, hasHeader: Bool? = nil) throws -> Table
func loadTable(_ url: URL, format: TableFormat = .auto, hasHeader: Bool? = nil) throws -> Table
func loadTable(resource: String, withExtension ext: String? = "csv", in bundle: Bundle,
               format: TableFormat = .auto, hasHeader: Bool? = nil) throws -> Table
```

Read a delimited file. Use the `resource:` form for a file that sits beside the sketch. Pass `.module` for the sketch's own bundle. That parameter has no default, because a default would resolve to Ollin's bundle rather than yours.

```swift
final class Readings: Sketch {
    private var table: Table?

    override func setup() {
        table = try? loadTable(resource: "readings", withExtension: "csv", in: .module)
    }

    override func draw() {
        background(.black)
        guard let table else { return drawStatus("no readings", style: .warning) }

        for (index, row) in table.enumerated() {
            let x = map(Double(index), 0, Double(table.count), 100, width - 100)
            fill(row.color("tint") ?? .white)
            drawCircle(x, height / 2, row.number("high") ?? 10)
        }
    }
}
```

A URL works too, including a network one. Reading it blocks until the file arrives, so `setup()` is the place for it.

<a name="Table"></a>

### Table

```swift
struct Table {
    var columns: [String]     // the header names, empty when read headerless
    var rows: [Row]
}
```

A `Table` is also a collection of its rows, so `table.count`, `table[0]`, `for row in table`, `table.enumerated()`, `filter`, and `map` all work directly.

Every cell is text, because that is what the file holds. A row converts a cell to another type when you ask for that type.

<a name="rows"></a>

### Reading rows

```swift
row["pop"]              // String?
row[2]                  // String?, by position
row.number("lat")       // Double?
row.int("count")        // Int?, rounding a decimal
row.bool("active")      // Bool?  true/yes/1, false/no/0, either case
row.color("tint")       // Color?, from a hex string like #ff8800
row.cells               // [String], the row as the file has it
```

Each of these has a matching `at position:` form for a headerless file, such as `row.number(at: 1)`.

Every one of them answers `nil` rather than a stand-in value. That happens when the column isn't there, when the row stops before it, or when the cell isn't the thing you asked for. An empty cell is not a zero, so a gap in a file reads as a gap. Your sketch decides what to do about it:

```swift
guard let lat = row.number("lat"), let lon = row.number("lon") else { continue }
```

<a name="columns"></a>

### Reading columns

```swift
table.column("city")     // [String], one per row, in row order
table.numbers("pop")     // [Double]
```

`column(_:)` returns one entry per row, so it lines up with `rows`. A row that stops before the column contributes an empty string.

`numbers(_:)` drops cells that aren't numbers. Use it to read a column as a *series*, usually to find the range you draw against:

```swift
let highs = table.numbers("high")
guard let top = highs.max(), let bottom = table.numbers("low").min() else { return }
```

When rows have to stay lined up with each other, read each row's cells instead.

<a name="mapping"></a>

### Mapping a column to a mark

A file gives you rows and columns. A drawing wants marks, and nothing in the file says which. Each mark asks which column, which of its properties, and over what range. Any property will do, because a length, a radius, a height, a hue, and a turn are all numbers.

The range should come from the file, not from a number typed in. Read the column as a series with `numbers(_:)`, take its ends with `min()` and `max()`, and carry each value across with `map`. `max()` answers `nil` for an empty column, so guard it:

```swift
let rain = table.numbers("rain")
guard let most = rain.max() else { return }
for (index, row) in table.enumerated() {
    let height = map(row.number("rain") ?? 0, 0, most, 0, 250)
    drawRect(corner: Vector2(60 + Double(index) * 30, 300 - height), width: 20, height: height)
}
```

The low end of the range depends on the property:

- **A length starts at zero**, whatever the column's smallest value is. A bar twice as long stands for a number twice as big only when the scale starts there.
- **A position runs from the column's smallest value to its largest**, so the marks spread over the space you gave them.
- **A dot takes the square root.** The eye reads a dot by its area, so give the radius `.squareRoot()` of the mapped value. Then a value twice as big reads twice as big rather than four times.

Two columns place a mark. Read one into x and one into y, and every row becomes a point in a field, the chart called a scatter. The rows in order place a mark too. When they are a sequence, such as the months of a year, the row's index is the x and its number the y. `drawPolyline` through those points draws the line read as time:

```swift
let high = table.numbers("high")
guard let lowest = high.min(), let highest = high.max() else { return }
var points: [Vector2] = []
for (index, row) in table.enumerated() {
    let y = map(row.number("high") ?? lowest, lowest, highest, 300, 60)
    points.append(Vector2(60 + Double(index) * 30, y))
}
drawPolyline(points)
```

Color is one more property. A column can carry it outright, through `row.color(_:)`, or a number can pick it from a [`Ramp`](../Drawing/Color.md#ramp): `ramp.color(at: map(value, lowest, highest, 0, 1))` turns a temperature into a color.

The [Readings example](../../Examples/Data/Readings/Sketch.swift) draws a year from one table. Each month is a bar from its low to its high, in a color the file carries. Under each bar sits a rain dot sized by the rain column.

<a name="parsing"></a>

### How a file is read

Parsing follows the published CSV description. A cell wrapped in double quotes can hold the separator, line breaks, and doubled quotes, where two quotes stand for one:

```csv
month,note
Feb,"the ""thaw"" week"
May,"long, mild evenings"
```

The quotes are not part of the cell. `"long, mild evenings"` arrives as one cell, without them.

Around that rule, parsing is forgiving, because real files are untidy. All of these read without complaint: a byte-order mark, any mix of line endings, blank lines, a missing final newline, and rows of uneven length. A spreadsheet writes that mark at the front of a file, and left in place it would join the first column's name invisibly. An unquoted cell has its surrounding spaces trimmed, so `a, b` reads as `b`. Quote a cell to keep the spaces. A backslash is not an escape here, only a doubled quote is.

Two things are guessed when you don't state them, and stating one overrides its guess.

**The separator.** `.auto` counts commas, tabs, semicolons, and pipes on the first line, outside quotes, then takes the most frequent one. Name the separator with `format:` when a file is unusual enough for that count to go wrong:

```swift
(try? loadTable("odd.txt", format: .tsv))
(try? loadTable("odd.txt", format: .delimited("|")))
```

**Whether the first row names the columns.** A first row that holds no numbers is a header, and one that holds a number is data. That is the whole rule, and it is what a person reads too. The rule gets a file of names with no header wrong, so say which you have:

```swift
(try? loadTable("names.csv", hasHeader: false))   // no header row; read cells by position
```

When a file is read headerless, `columns` is empty and cells come back by position, as in `row[0]`.

<a name="loadJSON"></a>

### loadJSON

```swift
func loadJSON(_ path: String) throws -> JSON
func loadJSON(_ url: URL) throws -> JSON
func loadJSON(resource: String, withExtension ext: String? = "json", in bundle: Bundle) throws -> JSON
```

Read a JSON document. It has the same shape and the same rules as `loadTable`. Call it in `setup()`, pass `.module` for your own bundle, and expect a `FileError` when there is nothing to read or the bytes are not JSON.

```swift
override func setup() {
    document = try? loadJSON(resource: "places", withExtension: "json", in: .module)
}
```

The [Places example](../../Examples/Data/Places/Sketch.swift) draws a survey from a document this way.

<a name="JSON"></a>

### JSON

```swift
enum JSON {
    case null, bool(Bool), number(Double), string(String)
    case array([JSON]), object([String: JSON])
}
```

Nothing is decoded into a type first, so the shape of the document is the shape of the code.

<a name="reaching"></a>

### Reaching through a document

Step in by name or by index, then ask for the kind of value you want at the end:

```swift
json["points"][0]["name"].text
json.survey.title.text          // the same, written as properties
```

```swift
.text       // String?
.number     // Double?, and a quoted number like "42" reads as one
.int        // Int?, rounding a decimal
.bool       // Bool?, and a number reads as a flag: zero false, anything else true
.color      // Color?, from a hex string
.array      // [JSON], empty when this isn't an array
.object     // [String: JSON], empty when this isn't an object
.keys       // [String], sorted, so walking an object is reproducible
.count      // elements or members; zero for everything else
.isNull     // true for a null, and for a key that isn't there
```

**A key that isn't there answers null rather than stopping**, and so does every step after it. That is what makes a whole path safe to write in one line. It is also why `.array` is not optional. A loop over a key that isn't there runs zero times, so you need no check first. A number no `Int` holds (`1e300` in a file) reads as `nil` through `.int` for the same reason.

```swift
for point in json["points"].array {
    let at = Vector2(point["at"]["x"].number ?? 0.5, point["at"]["y"].number ?? 0.5)
    // A point with no `tint` in the file lands on the fallback. No check needed.
    fill(point["tint"].color ?? .gray)
    drawCircle(center: bounds.point(u: at.x, v: at.y), radius: 20)
}
```

When the document is an Optional, as `try?` leaves it, `document?["points"].array ?? []` is the same loop. It runs zero times after a failed load, so the sketch draws nothing rather than stopping.

A missing key and a written null are the same thing here. If your document treats them differently, look for the key in `.object` directly.

<a name="codable"></a>

### When you want a type instead

`JSON` is deliberately small, because it is for reading a document once and drawing from it. When a document has a shape worth naming, and especially when you want it validated, Foundation's `Codable` is still there and is the better tool:

```swift
struct Station: Decodable { let name: String; let weight: Double }

let url = Bundle.module.url(forResource: "places", withExtension: "json")!
let stations = try JSONDecoder().decode([Station].self, from: Data(contentsOf: url))
```

<a name="sketchResource"></a>

### Files beside the sketch

```swift
sketchResource(_ name: String, in folder: String = "Models", from: String = #filePath) -> String?
```

This finds a file kept in a folder beside the sketch, or above it, by walking up from the sketch's own source file. `sketchResource("net.mlmodel")` finds the nearest `Models` folder on the way up and answers the file's path inside it. It answers `nil` when it finds none. The current directory is wherever the sketch was launched from, so a path relative to it breaks once the sketch runs from somewhere else. The source file stays put. It is a free function, so a `static let` can call it. Leave `from` alone, because it defaults to the caller's own file.

```swift
static let modelPath = sketchResource("StyleTransfer.mlmodel")
let dataPath = sketchResource("quakes.csv", in: "Data")
```

For a file bundled *into a target*, keep using `Bundle.module` and the loaders' `resource:in:` forms. `sketchResource` is for the loose folder that sits next to the sketch.

### See also

- [`Images`](../Drawing/Images.md) - `loadImage`, which loads a picture in `setup()` the same way
- [`SVG`](../Drawing/SVG.md) - `loadSVG`, for vector artwork
- [`Color`](../Drawing/Color.md) - palette import, which reads hex, CSV, JSON, and swatch files as colors
- [`Parameters`](./Parameters.md) - `@Param` parameters, for values you tune rather than load
