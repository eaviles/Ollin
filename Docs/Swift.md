#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Swift`</sup>

---

## Swift for p5.js newcomers

Coming from p5.js or plain JavaScript? The drawing API is meant to feel familiar — `setup()`/`draw()`, bare calls like `background(.white)` and `drawCircle(x, y, r)`, motion by default. The one barrier is the language. This page teaches *just enough* Swift to be productive in `draw()` — the handful of differences that actually bite — and points you at the full Swift book for the rest.

Every point lands on something you'll type in an Ollin sketch. It's a primer, not a manual.

### Contents

- [The whole sketch, side by side](#side-by-side)
- [`let` and `var`](#let-var)
- [Types are explicit, but inferred](#types)
- [`Double` vs `Int` (and why `1/2 == 0`)](#double-int)
- [Functions and `override`](#functions)
- [Classes and `override`](#classes)
- [Loops and arrays](#loops)
- [Trailing closures](#closures)
- [Optionals at a glance](#optionals)
- [String interpolation](#strings)
- [Where to go next](#next)

<a name="side-by-side"></a>

### The whole sketch, side by side

In p5.js you write two global functions:

```js
function setup() {
  createCanvas(800, 800);
}

function draw() {
  background(255);
  circle(width / 2, height / 2, 120 + sin(frameCount * 0.05) * 40);
}
```

In Ollin the same sketch is a class that overrides those two methods:

```swift
import Ollin

@main
final class Pulse: Sketch {
    override func draw() {
        background(.white)
        drawCircle(width / 2, height / 2, 120 + sin(time) * 40)
    }
}
```

The shape is the same — bare calls, terse positional arguments, a loop that runs `draw()` every frame. The rest of this page is the Swift-specific glue: `final class`, `override func`, `@main`, and `import`.

<a name="let-var"></a>

### `let` and `var`

JavaScript's `const` and `let` become Swift's `let` (a constant — can't be reassigned) and `var` (a variable — can). Prefer `let`; reach for `var` only when you reassign.

```swift
let radius = 120.0          // constant
var angle = 0.0             // will change
angle += 0.05
```

p5's `let x = 5` maps to Swift `var x = 5` if you reassign `x`, or `let x = 5` if you don't.

<a name="types"></a>

### Types are explicit, but inferred

Swift is statically typed — every value has a fixed type — but you rarely write the type, because the compiler infers it from the value:

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

This is the one that surprises JavaScript people most. JS has a single `number`; Swift separates whole numbers (`Int`) from decimals (`Double`), and **integer division throws away the remainder**:

```swift
1 / 2        // 0   — Int division
1.0 / 2.0    // 0.5 — Double division
```

Ollin's drawing API speaks `Double` (coordinates, radii, time), so write your literals as decimals to stay in `Double`:

```swift
let half = width / 2          // fine — width is already Double
let third = 100.0 / 3.0       // 33.33…, not 33
```

Swift also won't quietly mix the two — `Int(...)` / `Double(...)` convert explicitly when you need to cross over:

```swift
let n = 50                    // Int (a count)
let spacing = width / Double(n)   // convert before dividing into a Double
```

<a name="functions"></a>

### Functions and `override`

A function is `func`. The lifecycle methods you fill in (`setup`, `draw`, `mousePressed`) already exist on the `Sketch` base class, so you mark yours with `override` to replace them:

```swift
override func setup() {
    noLoop()        // run a single still frame
}

override func draw() {
    background(.white)
    drawCircle(width / 2, height / 2, 100)
}
```

`override` is required and checked: misspell `draw` and the compiler tells you there's nothing to override, instead of silently never running.

Your own helper functions need no `override`:

```swift
func dot(_ p: Vector2) {
    drawCircle(p.x, p.y, 4)
}
```

(Argument labels and the `_` that suppresses them are a Swift feature you'll meet in the API — `drawCircle(_:_:_:)` takes bare positional arguments, `drawCircle(center:radius:)` labels them. You don't need to define your own to write sketches.)

<a name="classes"></a>

### Classes and `override`

Your sketch *is* a class — a subclass of `Sketch`:

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

- **Properties** (declared with `let`/`var` at the top of the class) are how a sketch remembers state between frames — the equivalent of a global `let particles = []` in a p5 sketch, but scoped to the instance.
- **`final`** means "no further subclassing." Use it on your sketches; it's a small performance and clarity win. (`Sketch` itself is *not* final, which is what lets you subclass it.)
- **`self`** refers to the current instance, like JS `this` — but Swift's `self` is not the moving target JS's `this` is, so you rarely need it; write `particles`, not `self.particles`, unless a local name shadows it.

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
pts.append(Vector2(10, 10))    // push
pts.count                      // length
pts[0]                         // index
for p in pts { drawCircle(p.x, p.y, 4) }   // iterate the values directly

let xs = pts.map { $0.x }      // like JS Array.map
```

<a name="closures"></a>

### Trailing closures

A closure is an inline function — the same idea as a JS arrow function or callback. When a closure is the last argument, Swift lets you drop the parentheses and write it as a trailing `{ }` block. Ollin uses this for scoped state, which is `push()`/`pop()` in p5:

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

Swift makes "might be missing" part of the type. An optional `T?` either holds a `T` or is `nil`. You won't define many in a sketch, but you'll see them — for example, a lookup that can fail. Unwrap with `if let`:

```swift
if let first = particles.first {     // .first is Vector2?, nil if empty
    drawCircle(first.x, first.y, 8)
}
```

The point: `nil` can't sneak into a non-optional value, so the "undefined is not a function" class of bug doesn't happen.

<a name="strings"></a>

### String interpolation

Backtick templates (`` `r is ${r}` ``) become `\(...)` inside a normal `"..."` string:

```swift
let r = 120.0
print("radius is \(r)")          // radius is 120.0
override var title: String { "Pulse \(frameCount)" }
```

<a name="next"></a>

### Where to go next

That's the delta that bites — enough to read and write Ollin sketches. For the rest of the language (structs and enums, protocols, generics, error handling), Apple's free book is the canonical reference:

- [*The Swift Programming Language*](https://docs.swift.org/swift-book/) — the official guide.

And the best way to learn the *Ollin* side is to read and tweak the [`Examples/`](../Examples/README.md): each is one small, self-contained sketch you can run with `swift run` and edit live. Start with `Basic`, then follow your curiosity.
