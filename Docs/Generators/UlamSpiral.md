#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Ulam spiral`</sup>

---

## Ulam spiral

**`ulamSpiral`** writes the whole numbers in a square spiral from the middle outward, one number per cell. A test on those numbers then becomes a picture. The walk turns as soon as the side it is on runs out. That gives right one, up one, left two, down two, right three, and so on without end, filling the square. Mark the primes and the marks do not scatter. They gather along diagonal lines, which is what Stanisław Ulam noticed on a notepad during a dull talk in 1963.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/06-GridsAndRepetition/NumbersInASpiral-dark.jpg">
  <img src="../../Guide/Images/06-GridsAndRepetition/NumbersInASpiral.jpg" alt="Two panels: a seven by seven grid with the numbers 1 to 49 written in a spiral and the walk drawn under them, and a sixty-one cell square with only the primes marked as dots, falling along visible diagonals" width="680">
</picture>

The lines are not a coincidence, and they are not a proof of anything. A diagonal of the spiral is the run of values of a quadratic. A diagonal that stays crowded is therefore a quadratic that keeps returning primes, and mathematics has known such polynomials since Euler. The picture makes them visible.

### Contents

- [ulamSpiral](#spiral)
- [Reading it](#reading)
- [Primes on their own](#primes)
- [Practical notes](#notes)

<a name="spiral"></a>

#### ulamSpiral

```swift
ulamSpiral(in bounds: Rectangle? = nil, size: Int, start: Int = 1,
           padding: Insets = .zero) -> UlamSpiral

drawUlamSpiral(in bounds: Rectangle? = nil, size: Int, start: Int = 1,
               padding: Insets = .zero)
```

Both calls lay a `size × size` square of cells over `bounds`, which is the whole canvas by default. The count begins at `start`, and `start` sits in the middle cell. `drawUlamSpiral` gives the plain reading. It marks the primes as filled dots in the current `fill`, sized to the cell.

```swift
let spiral = ulamSpiral(size: 101)
noStroke(); fill(.white)
for point in spiral.primePoints { drawCircle(center: point, radius: 3) }
```

Counting from somewhere other than 1 moves every number, so the diagonals break up and re-form. It is the same fact seen from a different starting point, and it animates well.

<a name="reading"></a>

#### Reading it

| On `UlamSpiral` | What it gives |
|---|---|
| `grid` | The `Grid` the spiral is written on, so every cell carries its own `frame` and `center`. |
| `numbers` | The number in each cell, row-major, so it zips with `grid.cells`. |
| `order` | The cell each number lands on, in counting order. A step that the walk took outside the grid reads `-1`, which happens only on an even-sided grid. |
| `point(of:)` | Where a number sits, or `nil` if the spiral never reached it. |
| `number(column:row:)` | The number at a cell. |
| `points(where:)` | The middle of every cell whose number passes a test you write. |
| `primePoints` | The middle of every cell that holds a prime, worked out by one sieve over the whole square. |
| `path` | The walk itself as one open `Contour`, from the middle outward. |

Any test makes a picture, and the primes are only the famous one:

```swift
let spiral = ulamSpiral(size: 81)
for point in spiral.points(where: { $0 % 7 == 0 }) { drawCircle(center: point, radius: 2) }
```

<a name="primes"></a>

#### Primes on their own

```swift
primes(upTo limit: Int) -> [Int]
isPrime(_ number: Int) -> Bool
```

`primes(upTo:)` is the sieve of Eratosthenes. It answers the whole run at once, which is what makes a field of thousands of numbers cheap. `isPrime` is the shorter route for a single number. It divides by two, then by three, then by every number of the form `6k ± 1` up to the square root.

```swift
for p in primes(upTo: 500) { drawCircle(Double(p), height / 2, 3) }
```

<a name="notes"></a>

#### Practical notes

- **An odd `size` puts 1 in the middle**, which is the picture everybody knows. An even `size` has no middle cell, so the walk starts just past it. It then steps outside the square before the square fills, and those steps are the `-1` entries in `order`.
- **The whole square is worked out when the value is made.** For a spiral built every frame, keep `size` to the hundreds. Otherwise build it once in `setup()`.
- **Deterministic.** Nothing here is random, so the same `size` and `start` always give the same picture.
- **The `path` is one continuous line**, so `--export-svg` writes the spiral as a single polyline for a plotter.

---

Related: [`Geometry`](../Drawing/Geometry.md) (the `Grid` this is written on), [`Math`](../Helpers/Math.md) (the rest of the number helpers), [`Ten print`](../Drawing/TenPrint.md) and [`Hitomezashi`](../Drawing/Hitomezashi.md) (other one-rule pictures over a grid).
