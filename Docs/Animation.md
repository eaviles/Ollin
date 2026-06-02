#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Animation`</sup>

---

## Animation

Motion is the default in Ollin, so most movement falls out of a `time`-driven term in `draw()`. When you want a value to *ease* between states instead of snapping or moving at a constant rate, there are two pieces: the `Easing` curves, which shape a `0...1` progress, and `@Eased`, a value that eases toward whatever you assign it.

### Contents

- [Easing curves](#easing)
- [The curve catalog](#catalog)
- [`@Eased`](#eased)

<a name="easing"></a>

### Easing curves

An `Easing` maps normalized progress (`0...1`) onto a shaped `0...1`. Call it like a function, and pair it with [`lerp`](./Math.md#lerp) to interpolate between two values along the curve:

```swift
let t = (time / 2).truncatingRemainder(dividingBy: 1)        // 0...1, looping
let x = lerp(120, width - 120, Easing.easeInOutCubic(t))     // eased across the canvas
drawCircle(x, height / 2, 40 * scale)
```

The input `t` is clamped to `0...1` first, so values past the ends hold flat. The output is *not* clamped: the back, elastic, and bounce curves overshoot the range on purpose and settle exactly on the endpoints.

Build a custom curve from any closure:

```swift
let gentle = Easing { t in t * t * (3 - 2 * t) }   // a hand-rolled smoothstep
```

<a name="catalog"></a>

### The curve catalog

`linear` plus the thirty named curves from [Robert Penner's easing equations](https://easings.net), grouped by family with in / out / in-out variants:

| Family | Ease in | Ease out | Ease in-out |
|---|---|---|---|
| Sine | `easeInSine` | `easeOutSine` | `easeInOutSine` |
| Quadratic | `easeInQuad` | `easeOutQuad` | `easeInOutQuad` |
| Cubic | `easeInCubic` | `easeOutCubic` | `easeInOutCubic` |
| Quartic | `easeInQuart` | `easeOutQuart` | `easeInOutQuart` |
| Quintic | `easeInQuint` | `easeOutQuint` | `easeInOutQuint` |
| Exponential | `easeInExpo` | `easeOutExpo` | `easeInOutExpo` |
| Circular | `easeInCirc` | `easeOutCirc` | `easeInOutCirc` |
| Back | `easeInBack` | `easeOutBack` | `easeInOutBack` |
| Elastic | `easeInElastic` | `easeOutElastic` | `easeInOutElastic` |
| Bounce | `easeInBounce` | `easeOutBounce` | `easeInOutBounce` |

The back, elastic, and bounce families overshoot: back dips past the start and overshoots the target, elastic springs around it, and bounce settles in steps. The other seven stay within `0...1`.

Three friendly aliases cover the common case: `.easeIn`, `.easeOut`, and `.easeInOut` map to the cubic forms. `.smoothStep` is a Hermite smoothstep, a gentler S than `easeInOut`.

The [EasingGallery example](../Examples/Motion/EasingGallery/Sketch.swift) plots all thirty so you can see the shapes side by side.

<a name="eased"></a>

### `@Eased`

A property wrapper for a `Double` that eases toward whatever you assign it, a little each frame. Read it to get the current animated value; assign it to set a new target. The sketch advances it automatically, so there's no update step to call.

```swift
final class Follow: Sketch {
    @Eased var x = 0.0                                  // 0.5s ease-in-out (the defaults)
    @Eased(duration: 1, curve: .easeOutBack) var y = 0.0

    override func draw() {
        background(.white)
        x = mouseX                                      // retarget; the dot glides over
        y = mouseY
        drawCircle(x, y, 40 * scale)
    }
}
```

Assigning the value it's already heading for is a no-op, so it's safe to set the target every frame. Only a *change* restarts the tween, and it restarts from wherever the value currently is. The tween is timed in seconds (`duration`), so it runs the same at any frame rate.

The projected value (`$x`) exposes a little more:

```swift
$x.target          // the value being eased toward
$x.isAnimating     // true while it's still moving
$x.set(200)        // jump straight there, no animation
```

The [Easing example](../Examples/Motion/Easing/Sketch.swift) races four dots toward the same target on different curves, so you can watch the curves pull apart in flight.
