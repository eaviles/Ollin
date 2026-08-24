#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `Ford circles`</sup>

---

## Ford circles

**`fordCircles`** gives every fraction a circle, and the circles fit together on their own. The fraction `p/q` in lowest terms gets a circle of radius `1/(2q²)` sitting on the number line at `p/q`, touching the line and nothing below it. Nothing in that rule asks the circles to fit, and yet no two of them ever overlap. Two of them touch exactly when `ps - qr` is `1` or `-1`, which is what it means for two fractions to be neighbors. Lester Ford described them in 1938.

```
        ___________                         ___________
       /           \                       /           \
      |     0/1     |                     |     1/1     |
       \___________/       _______         \___________/
                          /  1/2  \
              __         |         |         __
             /1/3\        \_______/        /2/3\
    ________(_____)__________________(____)_______________
      0            1/3       1/2       2/3            1
```

A small denominator means a big circle, and a big circle means a fraction that stays a good approximation to everything near it. That is why the picture was drawn in the first place. It shows how well a number can be approximated by fractions: the circles that reach highest belong to the fractions worth approximating with.

The fractions themselves come from [`fareySequence`](#farey), which is worth having on its own.

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

Every fraction from 0 to 1 whose denominator is `order` or less, one circle each, in fraction order from left to right. `drawFordCircles` is the plain reading: each circle drawn in the current `fill` and `stroke`.

```swift
noFill()
stroke(.white)
for ford in fordCircles(order: 12) {
    drawCircle(ford.circle)
}
```

The unit interval spans the width of `bounds`, and the circles are scaled by that same width. Sharing one scale is what keeps them touching. The largest of them, at `0/1` and `1/1`, is then half the width across. It reaches the top of a square region and hangs half outside the left and right edges, which is the classic picture. Pass `interval` to narrow the run of fractions when those ends are not wanted.

`touches` answers on the fractions, never on the distance, so it is exact. Two circles touch when their fractions are neighbors, and are strictly apart otherwise.

<a name="farey"></a>

#### The Farey sequence

```swift
fareySequence(order: Int) -> [Fraction]
```

Every fraction from 0 to 1 with a denominator of `order` or less, in lowest terms, in order.

```swift
fareySequence(order: 5).map(\.description)
// ["0/1", "1/5", "1/4", "1/3", "2/5", "1/2", "3/5", "2/3", "3/4", "4/5", "1/1"]
```

Two facts make it more than a sorted pile of fractions:

- **Any two terms next to each other are neighbors**, so `ps - qr` is exactly `-1`. This is the fact the Ford circles turn into tangency.
- **The first fraction ever to appear between two neighbors is their mediant**, `(p+r)/(q+s)`, and it arrives exactly at the order its own denominator names.

The terms are walked out one at a time from the pair before them, so the cost is the length of the answer rather than a sort. That length grows with the square of the order, about `3n²/π²` terms. An order of 100 is already about 3,000 fractions, and an order of 1,000 about 300,000.

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

A fraction in lowest terms, with the sign carried by the numerator. It exists because these pictures rest on exact statements about whole numbers. Two fractions are neighbors or they are not, and no amount of rounding should be able to change the answer. Comparison cross-multiplies rather than divides, for the same reason.

A denominator of zero is taken as one, since a fraction over nothing is not a number and there is nothing better to make of it.

<a name="notes"></a>

#### Practical notes

- **The count grows with the square of the order.** `order: 26` is about 210 circles, `order: 60` about 1,100. The small ones vanish quickly: the radius falls with the *square* of the denominator, so past about 40 most of what arrives is invisible.
- **Growing the order is the animation.** Each new denominator drops its circles into gaps that were waiting for them. The circles never move, which is what makes it read as arrival rather than motion.
- **Color by denominator, not by position.** The denominator is what the picture is about, and it is also what the size already shows, so a ramp over it reads immediately.
- The circles are plain `Circle` values, so they hatch, cut, and export to SVG for a pen plotter like any other geometry.

Example: `Patterns/FordCircles`. Guide: [Chapter 6](../../Guide/06-GridsAndRepetition.md).

---

#### Where this comes from

Lester R. Ford's "Fractions" (*American Mathematical Monthly* 45/9, 1938). The sequence under it is named for John Farey, who noticed the mediant rule in 1816. Charles Haros had published it in 1802, and Augustin-Louis Cauchy supplied the proof. See [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

#### Go deeper

- [Ulam spiral](./UlamSpiral.md): the other picture that turns a fact about whole numbers into a drawing
- [Tiling and layout](../Drawing/Tiling.md): `apollonianGasket`, the other packing of circles that touch
- [Math helpers](../Helpers/Math.md): `primes(upTo:)`, `isPrime`, and the rest of the number helpers
