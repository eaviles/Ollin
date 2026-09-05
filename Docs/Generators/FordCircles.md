#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Ford circles`</sup>

---

## Ford circles

**`fordCircles`** gives every fraction a circle, and the circles fit together on their own. The fraction `p/q` in lowest terms gets a circle of radius `1/(2q²)`. That circle sits on the number line at `p/q`, so it touches the line and nothing below it. The rule says nothing about fitting, and yet no two of the circles ever overlap. Two of them touch exactly when `ps - qr` is `1` or `-1`, which is what it means for two fractions to be neighbors. Lester Ford described them in 1938.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/06-GridsAndRepetition/CircleForEveryFraction-dark.jpg">
  <img src="../../Guide/Images/06-GridsAndRepetition/CircleForEveryFraction.jpg" alt="Two panels of circles resting on a number line. On the left the fractions with denominators up to four, labeled, each circle touching its neighbors. On the right the same line once every denominator up to twelve has arrived, the new smaller circles dropping into the gaps between the old ones" width="680">
</picture>

A small denominator means a big circle, and a big circle means a fraction that stays a good approximation to everything near it. That is why the picture was drawn in the first place. It shows how well a number can be approximated by fractions, because the circles that reach highest belong to the fractions worth approximating with.

The fractions themselves come from [`fareySequence`](#farey), which is useful on its own.

### Contents

- [fordCircles](#circles)
- [The Farey sequence](#farey)
- [Fraction](#fraction)
- [Practical notes](#notes)

<a name="circles"></a>

#### fordCircles

```swift
fordCircles(order: Int, in bounds: Rectangle? = nil,
            interval: ClosedRange<Double> = 0 ... 1) -> [FordCircle]

drawFordCircles(order: Int, in bounds: Rectangle? = nil,
                interval: ClosedRange<Double> = 0 ... 1)

struct FordCircle {
    let fraction: Fraction
    let circle: Circle
    func touches(_ other: FordCircle) -> Bool
}
```

`fordCircles` returns one circle for every fraction from 0 to 1 whose denominator is `order` or less, in fraction order from left to right. `drawFordCircles` is the plain reading of that list, and it draws each circle in the current `fill` and `stroke`.

```swift
noFill()
stroke(.white)
for ford in fordCircles(order: 12) {
    drawCircle(ford.circle)
}
```

The unit interval spans the width of `bounds`, and the circles are scaled by that same width. Sharing one scale is what keeps them touching. The largest of them, at `0/1` and `1/1`, is then half the width across. It reaches the top of a square region and hangs half outside the left and right edges, which is the classic picture. Pass `interval` to narrow the run of fractions when you do not want those ends.

`touches` compares the fractions rather than the distance, so its answer is exact. Two circles touch when their fractions are neighbors, and they are strictly apart otherwise.

<a name="farey"></a>

#### The Farey sequence

```swift
fareySequence(order: Int) -> [Fraction]
```

`fareySequence` returns every fraction from 0 to 1 with a denominator of `order` or less, in lowest terms, in order.

```swift
fareySequence(order: 5).map(\.description)
// ["0/1", "1/5", "1/4", "1/3", "2/5", "1/2", "3/5", "2/3", "3/4", "4/5", "1/1"]
```

Two facts make the sequence more than a sorted list of fractions:

- **Any two terms next to each other are neighbors**, so `ps - qr` is exactly `-1`. The Ford circles turn that fact into tangency.
- **The first fraction ever to appear between two neighbors is their mediant**, `(p+r)/(q+s)`. It arrives at exactly the order that its own denominator names.

Each term is worked out from the pair before it, one at a time. The cost is therefore the length of the answer rather than the cost of a sort. That length grows with the square of the order, about `3n²/π²` terms. An order of 100 is already about 3,000 fractions, and an order of 1,000 about 300,000.

<a name="fraction"></a>

#### Fraction

```swift
struct Fraction: Hashable, Comparable {
    init(_ numerator: Int, _ denominator: Int = 1)   // reduces
    let numerator: Int
    let denominator: Int          // always one or more
    var value: Double
    func mediant(with other: Fraction) -> Fraction
    func isNeighbor(of other: Fraction) -> Bool      // |ps - qr| == 1
    func determinant(with other: Fraction) -> Int    // ps - qr
}
```

`Fraction` is a fraction in lowest terms, and the numerator carries the sign. It exists because these pictures rest on exact statements about whole numbers. Two fractions are neighbors or they are not, and no amount of rounding should be able to change the answer. Comparison cross-multiplies rather than divides, for the same reason.

A denominator of zero is taken as one. A fraction over nothing is not a number, and there is nothing better to make of it.

<a name="notes"></a>

#### Practical notes

- **The count grows with the square of the order.** `order: 26` is about 210 circles, and `order: 60` about 1,100. The small ones vanish quickly, because the radius falls with the *square* of the denominator. Past about 40, most of what arrives is invisible.
- **Growing the order is the animation.** Each new denominator drops its circles into gaps that were already there. The circles never move, so the picture reads as arrival rather than motion.
- **Color by denominator, not by position.** The denominator is what the picture is about, and the size already shows it. A ramp over the denominator therefore reads immediately.
- The circles are plain `Circle` values, so they hatch, cut, and export to SVG for a pen plotter like any other geometry.

Example: `Patterns/FordCircles`. Guide: [Chapter 6](../../Guide/06-GridsAndRepetition.md).

---

#### Where this comes from

Lester R. Ford's "Fractions" (*American Mathematical Monthly* 45/9, 1938). The sequence behind the circles is named for John Farey, who noticed the mediant rule in 1816. Charles Haros had published it in 1802, and Augustin-Louis Cauchy supplied the proof. See [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

#### Go deeper

- [Ulam spiral](./UlamSpiral.md): the other picture that turns a fact about whole numbers into a drawing
- [Tiling and layout](../Drawing/Tiling.md): `apollonianGasket`, the other packing of circles that touch
- [Math helpers](../Helpers/Math.md): `primes(upTo:)`, `isPrime`, and the rest of the number helpers
