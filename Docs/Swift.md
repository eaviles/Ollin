#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Swift`</sup>

---

## Swift quick reference

New to Swift? This page is the language at sketch speed: the handful of constructs you'll actually type in `draw()`, each with an example that lands on something you'd write in Ollin. It's a primer, not a manual.

Coming from p5.js or Processing? [Appendix C of the Guide](../Guide/C-ComingFromP5.md) maps the API you already know onto Ollin; this page covers the language underneath. For a slower, narrative pass through the same Swift, the Guide's Appendix A is the place.

### Contents

- [The shape of a sketch](#shape)
- [`let` and `var`](#let-var)
- [Types are explicit, but inferred](#types)
- [`Double` vs `Int` (and why `1/2 == 0`)](#double-int)
- [Functions and argument labels](#functions)
- [Classes and `override`](#classes)
- [Loops and arrays](#loops)
- [Trailing closures](#closures)
- [Optionals at a glance](#optionals)
- [String interpolation](#strings)
- [Where to go next](#next)

<a name="shape"></a>

### The shape of a sketch

Every sketch is a class built on `Sketch`, with the lifecycle methods filled in:

```swift
import Ollin

final class Pulse: Sketch {
    override func draw() {
        background(.white)
        drawCircle(width / 2, height / 2, 120 + sin(time) * 40)
    }
}
```

Run it as a loose file with `swift run OllinLive Pulse.swift` (add `@main` above the class if you make it a standalone program; see [Sketch](./Core/Sketch.md)). Every piece of syntax in it is covered below: `import` brings the framework in, `final class ... : Sketch` declares the sketch, and `override func` replaces a method the base class already defines.

<a name="let-var"></a>

### `let` and `var`

`let` declares a constant (it can't be reassigned) and `var` a variable (it can). Prefer `let`; reach for `var` only when you reassign.

```swift
let radius = 120.0          // constant
var angle = 0.0             // will change
angle += 0.05
```

Most values in `draw()` are computed fresh each frame, so `let` is the everyday choice; `var` earns its place on state that persists and changes across frames.

<a name="types"></a>

### Types are explicit, but inferred

Swift is statically typed: every value has a fixed type. You rarely write the type, because the compiler infers it from the value:

```swift
let r = 120.0               // inferred Double
let name = "Pulse"          // inferred String
let center = Vector2(width / 2, height / 2)   // inferred Vector2
```

You only write the type when there's nothing to infer it from (an empty array, a property you declare before assigning):

```swift
var trail: [Vector2] = []   // an empty array needs its element type stated
```

The payoff for the strictness: typos and wrong-type mistakes are caught before the sketch ever runs.

<a name="double-int"></a>

### `Double` vs `Int` (and why `1/2 == 0`)

This is the one that surprises people most. Swift separates whole numbers (`Int`) from decimals (`Double`), and **integer division throws away the remainder**:

```swift
1 / 2        // 0,   Int division
1.0 / 2.0    // 0.5, Double division
```

Ollin's drawing API speaks `Double` (coordinates, radii, time), so write your literals as decimals to stay in `Double`:

```swift
let half = width / 2          // fine: width is already Double
let third = 100.0 / 3.0       // 33.33…, not 33
```

Swift also won't quietly mix the two. `Int(...)` and `Double(...)` convert explicitly when you need to cross over:

```swift
let n = 50                    // Int (a count)
let spacing = width / Double(n)   // convert before dividing into a Double
```

<a name="functions"></a>

### Functions and argument labels

A function is `func`. Arguments carry labels by default, and an underscore in the declaration removes one, which is how the API offers both bare and labeled forms:

```swift
func dot(_ p: Vector2) {      // called as dot(p): the _ removes the label
    drawCircle(p.x, p.y, 4)
}
```

You'll meet both styles constantly as a caller: `drawCircle(x, y, r)` takes bare positional arguments, while `drawCircle(center: p, radius: r)` names them. The labels are part of the function's name, so a call spells exactly the labels the declaration asks for.

<a name="classes"></a>

### Classes and `override`

Your sketch *is* a class, a subclass of `Sketch`:

```swift
final class Flow: Sketch {
    // properties: per-sketch state that persists across frames
    var particles: [Vector2] = []

    override func setup() {
        for _ in 0..<200 {
            particles.append(Vector2(random(width), random(height)))
        }
    }

    override func draw() {
        background(.white)
        for p in particles { drawCircle(p.x, p.y, 3) }
    }
}
```

- **Properties** (declared with `let`/`var` at the top of the class) are how a sketch remembers state between frames, scoped to the instance rather than floating as globals.
- **`override`** marks a method that replaces one the base class defines (`setup`, `draw`, `mousePressed`, and friends). It's required and checked: misspell `draw` and the compiler tells you there's nothing to override, instead of silently never running. Your own helper methods take no `override`.
- **`final`** means "no further subclassing." Use it on your sketches; it's a small performance and clarity win. (`Sketch` itself is *not* final, which is what lets you subclass it.)
- **`self`** refers to the current instance. Swift rarely needs it spelled out: write `particles`, not `self.particles`, unless a local name shadows it.

<a name="loops"></a>

### Loops and arrays

A counted loop uses a range. `0..<n` is "0 up to but not including n" (the common case); `0...n` includes `n`:

```swift
for i in 0..<10 {
    drawCircle(Double(i) * 40 + 20, height / 2, 12)
}
```

Use `_` for the loop variable when you don't need it:

```swift
for _ in 0..<200 { /* place a particle */ }
```

Arrays are `[Element]`. The everyday operations:

```swift
var pts: [Vector2] = []
pts.append(Vector2(10, 10))    // add to the end
pts.count                      // length
pts[0]                         // index
for p in pts { drawCircle(p.x, p.y, 4) }   // iterate the values directly

let xs = pts.map { $0.x }      // transform every element
```

<a name="closures"></a>

### Trailing closures

A closure is an inline function you pass as a value. When a closure is the last argument, Swift lets you drop the parentheses and write it as a trailing `{ }` block. Ollin uses this for scoped state:

```swift
withState {
    translate(width / 2, height / 2)   // changes here…
    rotate(time)
    drawRect(-50, -50, 100, 100)
}                                       // …are undone when the block ends
```

`$0`, `$1`, … are the shorthand argument names inside a closure (you saw `$0` in the `.map` above), so you often don't name them at all.

<a name="optionals"></a>

### Optionals at a glance

Swift makes "might be missing" part of the type. An optional `T?` either holds a `T` or is `nil`. You won't define many in a sketch, but you'll meet them wherever something can fail, like loading a file or looking up a first element. Unwrap with `if let`:

```swift
if let first = particles.first {     // .first is Vector2?, nil if empty
    drawCircle(first.x, first.y, 8)
}
```

The point: `nil` can't sneak into a non-optional value, so a whole class of "crashed on a missing value" bugs doesn't happen.

<a name="strings"></a>

### String interpolation

`\(...)` embeds any value inside a `"..."` string:

```swift
let r = 120.0
print("radius is \(r)")          // radius is 120.0
override var title: String { "Pulse \(frameCount)" }
```

<a name="next"></a>

### Where to go next

That's the delta that bites: enough to read and write Ollin sketches. For the rest of the language (structs and enums, protocols, generics, error handling), Apple's free book is the canonical reference:

- [*The Swift Programming Language*](https://docs.swift.org/swift-book/), the official guide.

Coming from p5.js or Processing, the Guide's [Appendix C](../Guide/C-ComingFromP5.md) is the API translation table to keep beside this page. And the best way to learn the *Ollin* side is to read and tweak the [`Examples/`](../Examples/README.md): each is one small, self-contained sketch you can run with `swift run` and edit live. Start with `Basic`, then follow your curiosity.
