#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Formula`</sup>

---

## A number written as a rule

A `Formula` is a small piece of arithmetic read from a string. You can evaluate it as often as you like:

```swift
let wobble = try Formula("120 + sin(time * 2) * 40")
let radius = wobble.value(["time": time])
```

This matters because a string can arrive at runtime, and Swift source cannot. So you can drive a parameter with a rule you typed. A file can carry the rule instead of a list of numbers. An editing surface can give you a field to type in. The arithmetic is the same as what you would write in `draw()`, and you spell it the same way. The difference is that Ollin reads it later, at runtime.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/ParameterAsARule-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/ParameterAsARule.jpg" alt="Two panels showing the same wave. The left one is built from five keyed moments, each marked with a dot, with eased curves between them. The right one is one continuous line with the formula that made it printed underneath" width="680">
</picture>

### Contents

- [Driving a parameter](#driving-a-parameter)
- [A parameter of more than one number](#a-parameter-of-more-than-one-number)
- [What a formula can read](#what-a-formula-can-read)
- [The vocabulary](#the-vocabulary)
- [Two rules that surprise people](#two-rules-that-surprise-people)
- [Using one on its own](#using-one-on-its-own)
- [When the text is wrong](#when-the-text-is-wrong)
- [How it sits beside the rest](#how-it-sits-beside-the-rest)

---

### Driving a parameter

`drive(_:_:)` puts a [`@Param`](Parameters.md) parameter under a formula. Call it in `setup()`:

```swift
final class Ring: Sketch {
    @Param(80...460) var radius = 200.0
    @Param(3...48) var count = 12
    @Param(2...40) var edge = 6.0
    @Param var filled = true

    override func setup() {
        drive($radius, "190 + sin(time * tau / 6) * 80")
        drive($count, "8 + round(sin(time * tau / 12) * 5)")
        drive($edge, "radius / 22")            // worked out from another parameter
        drive($filled, "time % 6 < 3")         // a switch, on when it is not zero
    }
}
```

A formula returns a plain number. So three kinds of parameter can take one: a `Double`, an `Int`, and a `Bool`. An `Int` parameter rounds the number, and a `Bool` parameter is on for any value but zero.

A parameter under a formula is a [track](../Core/Automation.md), the same as a keyed one. `loops`, `speed`, `start`, and `length` shape it the same way. Ollin saves it in the same file as a keyed track, and every export renders it frame for frame.

The [Formula example](../../Examples/Motion/Formula/Sketch.swift) drives six parameters this way. It prints the text that drives each one under the ring.

### A parameter of more than one number

A point holds two numbers, a color holds four, and a pair of ends holds two. Each part can take its own rule. You name the part where you write the rule:

```swift
final class Card: Sketch {
    @Param(x: 0...1080, y: 0...1080, width: 40...900, height: 40...900)
    var frame = Rectangle(x: 190, y: 120, width: 700, height: 420)
    @Param(x: 0...1080, y: 0...1080) var eye = Vector2(540, 330)
    @Param var ink = Color(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)

    override func setup() {
        drive($frame, width: "620 + sin(time * tau / 7) * 220")
        drive($eye, x: "frame.x + frame.width / 2", y: "height / 2")
        drive($ink, red: "0.35 + sin(time) * 0.3")
    }
}
```

**A part with no rule is left alone.** The frame above changes size, but its `x` and `y` stay where you put them. You can still drag them while the size keeps changing. This is why you write a rule for one part rather than for the whole parameter.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/ParameterParts-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/ParameterParts.jpg" alt="A rectangle drawn at three moments from one fixed top-left corner, its size different each time, beside a list of the parameter's four parts: x and y marked no rule, width and height carrying a formula each" width="680">
</picture>

**One part of a parameter is also a name**, spelled `parameter.part`. So `"frame.x + frame.width / 2"` reads the rectangle of this frame. The name works whether keys set that part or another rule computes it.

| Parameter | Parts |
| --- | --- |
| `Vector2` | `x`, `y` |
| `Vector3` | `x`, `y`, `z` |
| `Color` | `red`, `green`, `blue`, `alpha` |
| `Rectangle` | `x`, `y`, `width`, `height` |
| `Insets` | `top`, `right`, `bottom`, `left` |
| `ClosedRange<Double>` | `lower`, `upper` |

Know three things before you write one:

- **One call carries the whole parameter**, so a second call replaces the first. Give every part in one call.
- **A pair of ends stays ordered.** When `lower` climbs past `upper`, it pushes `upper` up with it. The two-thumb slider does the same when you drag it.
- **Nothing holds a color's parts in `0...1`.** The parts are the sRGB numbers. Nothing keeps them inside that range, because a color parameter has no range of its own. Write `saturate(...)` in the rule where you want one. Every other parameter keeps its own range, exactly as it does when you drag the field.

A part cannot name its own parameter. An `x` computed from the `y` of the same point never settles on one frame. So Ollin reports that parameter and leaves it alone, the same way it treats a ring of parameters.

The [FormulaParts example](../../Examples/Motion/FormulaParts/Sketch.swift) drives four such parameters and prints the rule that drives each part.

### What a formula can read

| Name | What it holds |
| --- | --- |
| `time` | The position of the automation, in seconds. With no `speed` or `start` set, this is the sketch clock. |
| `frame` | The number of the frame about to be drawn, the same number `frameCount` reads inside `draw()`. |
| `width`, `height` | The canvas size, in pixels. |
| `mouseX`, `mouseY` | The pointer position. |
| any parameter's name | Any `@Param` on the sketch that is a number or a switch. A switch reads as `1` or `0`. |
| `parameter.part` | One part of a parameter that holds more than one number: `center.x`, `tint.alpha`, `span.lower`. |

A name in the table takes priority over a parameter spelled the same way, so `time` always means the clock.

**A parameter computed from another one lands on the same frame.** The named parameter is always set first, whatever order the tracks are in. So `drive($edge, "radius / 22")` reads the radius of *this* frame. This keeps a formula a plain function of the clock, so the same moment gives the same picture at any frame rate. That is what lets an export at 30 frames a second match the window.

Two parameters that name each other cannot settle that way. A parameter that names itself (`"n + 1"`) cannot settle either. Ollin reports such a ring and leaves it alone, because playing it would give a value that depends on the frame rate. For a value that builds on itself, keep a plain property and step it in `draw()`.

### The vocabulary

**Numbers.** `1`, `1.5`, `.5`, `2e3`, `2.5e-3`.

**Constants.** `pi`, `tau`, `e`.

**Operators**, loosest first: `||`, `&&`, then `==` `!=`, then `<` `<=` `>` `>=`, then `+` `-`, then `*` `/` `%`. A leading `-` or `!` binds tighter than all of those, and `^` binds tightest of all. A comparison returns `1` or `0`. `&&` and `||` stop as soon as the answer is known.

**Functions.**

| | |
| --- | --- |
| Angles | `sin` `cos` `tan` `asin` `acos` `atan` `atan2(y, x)` `sinh` `cosh` `tanh` `radians` `degrees` |
| Numbers | `abs` `sign` `floor` `ceil` `round` `trunc` `fract` `sqrt` `exp` `log` `log2` `log10` `pow(a, b)` `hypot(a, b)` `mod(a, b)` |
| Shaping | `clamp(x, low, high)` `saturate(x)` `lerp(a, b, t)` `mix(a, b, t)` `step(edge, x)` `smoothstep(edge0, edge1, x)` `map(x, a, b, c, d)` |
| Picking | `min(a, b, ...)` `max(a, b, ...)` `if(condition, then, else)` |
| Texture | `noise(x[, y, z])` in `0...1`, `signedNoise(x[, y, z])` in `-1...1` |

The shaping names use the same spelling and the same argument order as [the framework's own](Math.md) and as the shader library's. So the same line reads the same in all three places.

`noise` reads the sketch's own noise field, so `noiseSeed()` reproduces a wandering parameter the same way it reproduces a drawn one. There is no `random`, by design, because a formula returns the same number for the same moment. That is what makes a directed run render the same twice.

`if` picks its branch before evaluating it, so the branch not taken never runs.

### Two rules that surprise people

**`^` binds tighter than a minus sign.** `-2^2` is `-4`, and `2^3^2` is `2^9`. A calculator does the same. Ollin has one *other* small language, the one that writes the productions of a [parametric L-system](../Generators/LSystem.md). That language binds the minus tighter, because the published formalism says so. Neither is a mistake, and the two do not have to agree.

**`%` wraps rather than reflects.** `-1 % 3` is `2`, not `-1`. The remainder floors, which keeps a wrapping phase continuous through zero. It also agrees with `fract` and with the shader spelling. Swift's own `%` returns `-1`. This one does not, by design.

### Using one on its own

A `Formula` does not need a parameter. Read one from a string and evaluate it wherever you like:

```swift
let f = try Formula("a * 2 + b")
f.variables                      // ["a", "b"], in the order it met them
f.value(["a": 3, "b": 1])        // 7
f.value([3, 1])                  // 7, by position, which skips the lookup
```

By default a formula collects its own variable names, so it treats no name as unknown. When you know the names ahead of time, pass them in, and `Formula` rejects a misspelled name instead:

```swift
try Formula("sin(tine)", variables: ["time"])
// FormulaError: 'tine' is not a value or a function; the values here are time (at character 5)
```

`usesNoise` reports whether the formula reads a noise field. `value(_:noise:)` takes one, and `sketch.noiseField()` returns the sketch's own field.

### When the text is wrong

`Formula` throws a `FormulaError` that carries a message and the `offset` of the character where reading stopped. An editing surface can use the offset to point at the spot.

`drive(_:_:)` does not throw. It reports the problem on standard error and leaves the parameter alone. So a typo breaks that one parameter rather than the whole sketch, which is what you want while you edit live. It also reports a formula that names a value nothing supplies. Without that report, the name would read as zero on every frame, and the sketch would draw something almost right. To handle the error yourself, build the formula with `try` and pass it in instead:

```swift
drive($radius, try Formula("190 + sin(time) * 80"))
```

### How it sits beside the rest

- **[Keyframed parameters](../Core/Automation.md).** It is the same track, filled a different way. Keys say where a parameter *is* at a few moments, and a formula says what it *is* at every moment. One automation holds both kinds. A file stores the formula as the text you wrote, so you can edit it there.
- **[Parameters](Parameters.md).** A parameter under a formula returns to the formula on the next frame, so dragging its slider changes it only until then. Remove the formula (`automation = nil`) to tune by hand.
- **[Math](Math.md).** The Swift side of the same vocabulary, for a value computed in `draw()` rather than typed as text.
- **[Replay](../Core/Replay.md).** A run recorded with `--record-take` saves the values the formulas produced, so a take replays the performance with or without the formulas.

---

### See also

- [`Automation`](../Core/Automation.md) - the track a formula fills, and the file that stores both kinds
- [`Parameters`](Parameters.md) - the `@Param` parameters a formula drives
- [`Math`](Math.md) - `map`, `lerp`, and the shaping scalars, spelled the same way
- [`Noise`](../Generators/Noise.md) - the field `noise()` reads, and the seed that reproduces it
