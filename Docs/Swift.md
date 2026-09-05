#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Swift`</sup>

---

## Swift quick reference

New to Swift? This page covers the handful of constructs you will actually type in `draw()`. Each one comes with an example of something you would write in Ollin. It is a primer, not a manual.

Coming from p5.js or Processing? [Appendix C of the Guide](../Guide/C-ComingFromP5.md) maps the API you already know onto Ollin. This page covers the language underneath that API. For a slower pass through the same Swift, read the Guide's [Appendix A](../Guide/A-JustEnoughSwift.md).

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

Every sketch is a class that builds on `Sketch`, and you fill in the lifecycle methods:

```swift
import Ollin

final class Pulse: Sketch {
    override func draw() {
        background(.white)
        drawCircle(width / 2, height / 2, 120 + sin(time) * 40)
    }
}
```

Run it as a loose file with `swift run OllinLive Pulse.swift`. To make it a standalone program instead, add `@main` above the class, as [Sketch](./Core/Sketch.md) describes. The rest of this page covers every piece of syntax in it. `import` brings the framework in. `final class ... : Sketch` declares the sketch, and `override func` replaces a method the base class already defines.

<a name="let-var"></a>

### `let` and `var`

`let` declares a constant, which you cannot reassign, and `var` declares a variable, which you can. Prefer `let`, and use `var` only when you reassign the value.

```swift
let radius = 120.0          // constant
var angle = 0.0             // will change
angle += 0.05
```

Most values in `draw()` are computed fresh each frame, so `let` is the everyday choice. Use `var` for state that persists and changes across frames.

<a name="types"></a>

### Types are explicit, but inferred

Swift is statically typed, so every value has a fixed type. You rarely write that type out, because the compiler infers it from the value:

```swift
let r = 120.0               // inferred Double
let name = "Pulse"          // inferred String
let center = Vector2(width / 2, height / 2)   // inferred Vector2
```

You write the type only when there is nothing to infer it from, such as an empty array or a property you declare before assigning:

```swift
var trail: [Vector2] = []   // an empty array needs its element type stated
```

In return for that strictness, the compiler catches typos and wrong-type mistakes before the sketch ever runs.

<a name="double-int"></a>

### `Double` vs `Int` (and why `1/2 == 0`)

This is the rule that surprises people most. Swift separates whole numbers (`Int`) from decimals (`Double`), and **integer division throws away the remainder**:

```swift
1 / 2        // 0,   Int division
1.0 / 2.0    // 0.5, Double division
```

Ollin's drawing API takes `Double` for coordinates, radii, and time, so write your literals as decimals to stay in `Double`:

```swift
let half = width / 2          // fine: width is already Double
let third = 100.0 / 3.0       // 33.33…, not 33
```

Swift also refuses to mix the two on its own. Use `Int(...)` and `Double(...)` to convert when you need to cross between them:

```swift
let n = 50                    // Int (a count)
let spacing = width / Double(n)   // convert before dividing into a Double
```

<a name="functions"></a>

### Functions and argument labels

You declare a function with `func`. Arguments carry labels by default, and an underscore in the declaration removes one, which is how the API offers both bare and labeled forms:

```swift
func dot(_ p: Vector2) {      // called as dot(p): the _ removes the label
    drawCircle(p.x, p.y, 4)
}
```

You will use both styles constantly as a caller. `drawCircle(x, y, r)` takes bare positional arguments, and `drawCircle(center: p, radius: r)` names them. The labels are part of the function's name, so a call has to spell out exactly the labels the declaration asks for.

<a name="classes"></a>

### Classes and `override`

Your sketch is a class, and it subclasses `Sketch`:

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

- **Properties** are declared with `let` or `var` at the top of the class. They are how a sketch remembers state between frames, and they belong to the instance instead of floating as globals.
- **`override`** marks a method that replaces one the base class defines, such as `setup`, `draw`, or `mousePressed`. It is required, and the compiler checks it. Misspell `draw` and the compiler tells you there is nothing to override, instead of leaving you with a method that silently never runs. Your own helper methods take no `override`.
- **`final`** means the class cannot be subclassed any further. Use it on your sketches, because it is a little faster and a little clearer. `Sketch` itself is not final, which is what lets you subclass it.
- **`self`** refers to the current instance. Swift rarely needs it spelled out, so write `particles` rather than `self.particles`, unless a local name shadows it.

<a name="loops"></a>

### Loops and arrays

A counted loop uses a range. `0..<n` means 0 up to but not including n, which is the common case, and `0...n` includes `n`:

```swift
for i in 0..<10 {
    drawCircle(Double(i) * 40 + 20, height / 2, 12)
}
```

Use `_` for the loop variable when you do not need it:

```swift
for _ in 0..<200 { /* place a particle */ }
```

An array of a type is written `[Element]`. These are the everyday operations:

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

A closure is an inline function that you pass as a value. When a closure is the last argument, you can drop the parentheses and write it as a trailing `{ }` block. Ollin uses that form for scoped state:

```swift
withState {
    translate(width / 2, height / 2)   // changes here…
    rotate(time)
    drawRect(-50, -50, 100, 100)
}                                       // …are undone when the block ends
```

Inside a closure, `$0`, `$1`, and so on are shorthand names for the arguments. The `.map` above uses `$0` that way, so you often do not name the arguments at all.

<a name="optionals"></a>

### Optionals at a glance

Swift makes "might be missing" part of the type. An optional `T?` either holds a `T` or is `nil`. You will define few of them in a sketch. You will meet them wherever something can fail, such as loading a file or looking up a first element. Unwrap one with `if let`:

```swift
if let first = particles.first {     // .first is Vector2?, nil if empty
    drawCircle(first.x, first.y, 8)
}
```

Because `nil` cannot reach a non-optional value, a whole class of "crashed on a missing value" bugs cannot happen.

<a name="strings"></a>

### String interpolation

`\(...)` puts any value inside a `"..."` string:

```swift
let r = 120.0
print("radius is \(r)")          // radius is 120.0
override var title: String { "Pulse \(frameCount)" }
```

<a name="next"></a>

### Where to go next

Those are the differences that trip people up, and they are enough Swift to read and write Ollin sketches. For the rest of the language, which includes structs and enums, protocols, generics, and error handling, Apple's free book is the canonical reference:

- [*The Swift Programming Language*](https://docs.swift.org/swift-book/), the official guide.

If you are coming from p5.js or Processing, keep the Guide's [Appendix C](../Guide/C-ComingFromP5.md) beside this page as the API translation table. The best way to learn the Ollin side is to read and change the [`Examples/`](../Examples/README.md). Each one is a small, self-contained sketch that you can run with `swift run` and edit live. Start with `Basic`, then follow your curiosity.
