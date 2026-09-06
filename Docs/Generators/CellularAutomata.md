#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Cellular automata`</sup>

---

## Cellular automata

A cellular automaton is a grid of cells that changes by a local rule. Ollin has two families of them. The one-dimensional family, `elementaryCA` and `totalisticCA`, computes a row of cells one generation at a time. The classic picture stacks the generations as rows. One number picks the rule, and the rule decides whether the picture is ordered, fractal, or chaotic. The second family is the **turmite** family, `Turmite`. A turmite is a small machine that walks a 2D grid and paints the cells it visits, and Langton's ant is the best-known one. Both families run on the CPU and produce geometry. They are deterministic, and they are cheap enough to rebuild live while you change a parameter.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/19-GridSimulations/WolframAndTurmite-dark.jpg">
  <img src="../../Guide/Images/19-GridSimulations/WolframAndTurmite.jpg" alt="Two panels of black cells on cream. Left, rule 30 grown from a single cell into a triangle whose left half is regular stripes and whose right half is irregular, dotted with white triangles. Right, Langton's ant, a chaotic blot crossed by straight diagonal highways running off the edges" width="680">
</picture>

The GPU version of the idea is **Lenia**, a continuous form of the Game of Life. It runs as a `Sim` on a persistent field, so it is documented with the other simulations in [Layered effects → simField](../Drawing/Effects.md#simfield), next to `.gameOfLife()`.

### Contents

- [Elementary rules](#elementary)
- [Totalistic rules](#totalistic)
- [Random start rows](#random-start)
- [Turmites](#turmites)
- [Custom turmite rules](#turmite-rules)

<a name="elementary"></a>

#### Elementary rules

`elementaryCA` runs one of the 256 two-color rules. Each generation, every cell reads its three-cell neighborhood (left, self, and right) and looks up its next value in the rule's 8-bit table. The rule number encodes that table, so the number alone defines the system. The function returns `generations` rows, each `width` cells wide, and the first row is the start row. You can draw them as rects or over a [`Grid`](../Drawing/Geometry.md#grid).

```swift
func elementaryCA(rule: Int, width: Int, generations: Int,
                  from start: [Bool]? = nil, wrap: Bool = true) -> [[Bool]]
```

```swift
let rows = elementaryCA(rule: 30, width: 181, generations: 181)
let cell = width / 181.0
noStroke(); fill(.white)
for (r, row) in rows.enumerated() {
    for (c, on) in row.enumerated() where on {
        drawRect(Double(c) * cell, Double(r) * cell, cell, cell)
    }
}
```

`start` is the first row. When it is `nil`, the start row is the classic single live cell at the center. `wrap` joins the two ends of the row into a ring. When `wrap` is off, cells past the edges read as dead. Three rules are worth knowing.

- **30** is chaotic, and it was once used as a random-number source.
- **90** draws the Sierpinski triangle.
- **110** builds structured patterns, and it is known to be Turing-complete.

<a name="totalistic"></a>

#### Totalistic rules

`totalisticCA` generalizes the elementary rules to more than two colors. A cell's next value depends only on the sum of its three-cell neighborhood. That sum selects a digit of `code` written in base `colors`, and the digit is the next value. With three or more colors it draws textures that the elementary rules cannot produce.

```swift
func totalisticCA(code: Int, colors: Int = 3, width: Int, generations: Int,
                  from start: [Int]? = nil, wrap: Bool = true) -> [[Int]]
```

Each row holds color indices in `0 ..< colors`, so the natural way to draw it is a palette lookup per cell. Code **777** over 3 colors is a classic rule that grows irregularly. Sweeping the code with a parameter is a good way to find other codes worth drawing.

<a name="random-start"></a>

#### Random start rows

Both functions also exist as sketch methods that take a `startDensity` in place of `from`. The start row is then drawn from the sketch's seeded [`random`](./Random.md), which means a [`variation`](../Core/Variations.md) brings back the same field.

```swift
let rows = elementaryCA(rule: 22, width: 181, generations: 181, startDensity: 0.3)
```

<a name="turmites"></a>

#### Turmites

A `Turmite` is a Turing machine on a wrapped color grid. On each step, every ant reads the color under it and looks up the rule for its `(state, color)` pair. It then writes that rule's color, turns, moves one cell forward, and takes the rule's next state. Make one and keep it in a property, the way you keep a [`DifferentialGrowth`](./DifferentialGrowth.md). Call `step(_:)` each frame, then read the painted cells back.

```swift
let ant = Turmite(.langton, columns: 270, rows: 270)

override func draw() {
    ant.step(500)
    background(.black)
    let cell = width / 270.0
    noStroke(); fill(.white)
    for painted in ant.paintedCells {
        drawRect(Double(painted.column) * cell, Double(painted.row) * cell, cell, cell)
    }
}
```

The `Preset` catalog collects known rule tables, each with its own behavior:

| Preset | Behavior |
|---|---|
| `.langton` | the classic ant: chaotic at first, then an endless diagonal highway after ~10,000 steps |
| `.spiral` | spiral growth, a tightening square coil |
| `.highway` | builds a highway after a period of chaotic growth |
| `.chaos` | chaotic growth with a distinctive woven texture |
| `.frame` | textured growth inside an expanding frame |
| `.fibonacci` | grows outward in a Fibonacci-like spiral, very slowly |

`paintedCells` returns every non-zero cell. It is rebuilt on every call, so in a tight loop use `colorIndex(column:row:)` instead. `antPositions` gives the position of each ant, and `stepCount` is the number of steps the machine has run. The machine is deterministic and uses no randomness, so a fixed step count always paints the same picture. To run several ants, pass their start cells: `Turmite(.langton, columns: 270, rows: 270, ants: [(60, 60), (210, 210)])`. Within one step the ants move in array order.

<a name="turmite-rules"></a>

#### Custom turmite rules

A rule table is an array indexed as `[state][color]`, and each entry is a `Turmite.Rule(write:turn:state:)`. A rule holds the color to write, a `Turn` (`.straight`, `.right`, `.uTurn`, or `.left`), and the next state. Langton's ant has one state and two colors:

```swift
let langton = Turmite(rules: [[Turmite.Rule(write: 1, turn: .right, state: 0),
                               Turmite.Rule(write: 0, turn: .left, state: 0)]],
                      columns: 270, rows: 270)
```

Every state must have a rule for the same number of colors, and that count is the machine's `colors`. Ollin clamps a written color into the color range, and a next state into the state range. Two states and two colors are enough for spirals, highways, and framed textures, so small tables are worth trying by hand.

---

Examples: [`Patterns/ElementaryCA`](../../Examples/Patterns/ElementaryCA/Sketch.swift), [`Patterns/Turmites`](../../Examples/Patterns/Turmites/Sketch.swift), and [`Simulation/Automata`](../../Examples/Simulation/Automata/Sketch.swift) for the GPU version.
