#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Data`</sup>

---

## Data

Read a CSV, a TSV, or a JSON file and draw from it. You load both of them once, so call them in `setup()`, keep the result in a property, and read it in `draw()`.

Neither loader throws. A file that can't be read, or that holds nothing usable, comes back `nil`. A missing asset or a bad download then shows up as an empty sketch you can report, not as a crash.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/09-Pictures/DataAsMaterial-dark.jpg">
  <img src="../../Guide/Images/09-Pictures/DataAsMaterial.jpg" alt="Left, five lines of a CSV file in a pixel font, the header and one quoted row picked out in dark ink. Right, the four data rows as colored horizontal bars labeled Oslo, Bath Maine, Kyoto, and Lima, each sized by its number" width="680">
</picture>

### Contents

- [loadTable](#loadTable)
- [Table](#Table)
- [Reading rows](#rows)
- [Reading columns](#columns)
- [How a file is read](#parsing)
- [loadJSON](#loadJSON)
- [JSON](#JSON)
- [Reaching through a document](#reaching)
- [When you want a type instead](#codable)
- [Files beside the sketch](#sketchResource)

<a name="loadTable"></a>

### loadTable

```swift
func loadTable(_ path: String, format: TableFormat = .auto, hasHeader: Bool? = nil) -> Table?
func loadTable(_ url: URL, format: TableFormat = .auto, hasHeader: Bool? = nil) -> Table?
func loadTable(resource: String, withExtension ext: String? = "csv", in bundle: Bundle,
               format: TableFormat = .auto, hasHeader: Bool? = nil) -> Table?
```

Read a delimited file. Use the `resource:` form for a file that sits beside the sketch. Pass `.module` for the sketch's own bundle. That parameter has no default, because a default would resolve to Ollin's bundle rather than yours.

```swift
final class Readings: Sketch {
    private var table: Table?

    override func setup() {
        table = loadTable(resource: "readings", withExtension: "csv", in: .module)
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

<a name="parsing"></a>

### How a file is read

Parsing follows the published CSV description. A cell wrapped in double quotes can hold the separator, line breaks, and doubled quotes, where two quotes stand for one:

```csv
month,note
Feb,"the ""thaw"" week"
May,"long, mild evenings"
```

Around that rule, parsing is forgiving, because real files are untidy. All of these read without complaint: a byte-order mark, any mix of line endings, blank lines, a missing final newline, and rows of uneven length. A spreadsheet writes that mark at the front of a file, and left in place it would join the first column's name invisibly. An unquoted cell has its surrounding spaces trimmed, so `a, b` reads as `b`. Quote a cell to keep the spaces. A backslash is not an escape here, only a doubled quote is.

Two things are guessed when you don't state them, and stating one overrides its guess.

**The separator.** `.auto` counts commas, tabs, semicolons, and pipes on the first line, outside quotes, then takes the most frequent one. Name the separator with `format:` when a file is unusual enough for that count to go wrong:

```swift
loadTable("odd.txt", format: .tsv)
loadTable("odd.txt", format: .delimited("|"))
```

**Whether the first row names the columns.** A first row that holds no numbers is a header, and one that holds a number is data. That is the whole rule, and it is what a person reads too. The rule gets a file of names with no header wrong, so say which you have:

```swift
loadTable("names.csv", hasHeader: false)   // no header row; read cells by position
```

When a file is read headerless, `columns` is empty and cells come back by position, as in `row[0]`.

<a name="loadJSON"></a>

### loadJSON

```swift
func loadJSON(_ path: String) -> JSON?
func loadJSON(_ url: URL) -> JSON?
func loadJSON(resource: String, withExtension ext: String? = "json", in bundle: Bundle) -> JSON?
```

Read a JSON document. It has the same shape and the same rules as `loadTable`. Call it in `setup()`, pass `.module` for your own bundle, and expect `nil` when there is nothing to read.

```swift
override func setup() {
    document = loadJSON(resource: "places", withExtension: "json", in: .module)
}
```

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

**A key that isn't there answers null rather than stopping**, and so does every step after it. That is what makes a whole path safe to write in one line. It is also why `.array` is not optional. A loop over a key that isn't there runs zero times, so you need no check first.

```swift
for point in json["points"].array {
    let at = Vector2(point["at"]["x"].number ?? 0.5, point["at"]["y"].number ?? 0.5)
    // A point with no `tint` in the file lands on the fallback. No check needed.
    fill(point["tint"].color ?? .gray)
    drawCircle(center: bounds.point(u: at.x, v: at.y), radius: 20)
}
```

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
