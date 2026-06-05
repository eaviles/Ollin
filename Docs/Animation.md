#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Animation`</sup>

---

## Animation

Motion is the default in Ollin, so most movement falls out of a `time`-driven term in `draw()`. When you want a value to *ease* between states instead of snapping or moving at a constant rate, there are two pieces: the `Easing` curves, which shape a `0...1` progress, and `@Eased`, a value that eases toward whatever you assign it. And when the value comes from a noisy live signal rather than a target you set, `@Smoothed` cleans it up as it arrives.

### Contents

- [Easing curves](#easing)
- [The curve catalog](#catalog)
- [`@Eased`](#eased)
- [`@Smoothed`](#smoothed)

<a name="easing"></a>

### Easing curves

An `Easing` maps normalized progress (`0...1`) onto a shaped `0...1`. Call it like a function, and pair it with [`lerp`](./Math.md#lerp) to interpolate between two values along the curve:

```swift
let t = (time / 2).truncatingRemainder(dividingBy: 1)        // 0...1, looping
let x = lerp(120, width - 120, Easing.easeInOutCubic(t))     // eased across the canvas
drawCircle(x, height / 2, 40 * scale)
```

The input `t` is clamped to `0...1` first, so values past the ends hold flat. The output is *not* clamped: the back, elastic, and bounce curves overshoot the range on purpose and settle exactly on the endpoints.

```
  Each curve reshapes a 0→1 progress (x) into a 0→1 output (y):

   linear          easeIn          easeOut         easeInOut
    │     ╱          │     ╱         │   ╭───        │     ╭─
    │   ╱            │    ╱          │  ╱            │    ╱
    │ ╱              │  ╱            │ ╱             │  ╱
    ●────            ●─╯──           ●────           ●╯───
   constant rate    slow → fast     fast → slow     slow-fast-slow

  back, elastic, and bounce overshoot past 0 and 1 before settling:
    back     dips below 0, then overshoots past 1
    elastic  springs around the target before resting
    bounce   settles onto the end in shrinking hops
```

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

<a name="smoothed"></a>

### `@Smoothed`

`@Eased` glides toward a target you *know*. When instead you have a noisy live signal whose true value you *don't* know — a jittery `mouseX`/`mouseY`, or the input that arrives once OSC, MIDI, computer vision, and the phone sensors land — reach for `@Smoothed`. It cleans the stream with the [1€ filter](https://gery.casiez.net/1euro/), an adaptive low-pass that stays responsive when the signal moves fast and steady when it's slow, something a fixed low-pass can't manage at both ends.

Assign the raw value each frame and read back a clean one. Like `@Eased`, the sketch advances it for you, so there's no update step to call:

```swift
final class Cursor: Sketch {
    @Smoothed var p = Vector2.zero

    override func draw() {
        background(.white)
        p = Vector2(mouseX, mouseY)                 // feed the jittery input
        drawCircle(center: p, radius: 40 * scale)   // read the smoothed value
    }
}
```

It works on a `Double` or a `Vector2`. Two knobs tune the feel:

- **`minCutoff`** (default `1`) — lower it to cut jitter while the signal is slow, at the cost of a little more lag.
- **`beta`** (default `0.007`) — raise it to cut lag while the signal moves fast.

```swift
@Smoothed(minCutoff: 0.5, beta: 0.02) var angle = 0.0
```

Both are reachable live through the projected value (`$angle.beta = …`), so a `@Param` knob can dial them in by feel. The projected value also gives you `$p.rawValue` (the last unsmoothed input) and `$p.set(v)` (jump there with no glide). Because the filter is timed in seconds, it behaves the same at any frame rate.

To smooth a value that isn't a sketch property, the `OneEuroFilter<Value>` underneath is public — own the state and step it yourself:

```swift
var filter = OneEuroFilter<Double>(minCutoff: 1, beta: 0.02)
let clean = filter.filter(noisy, dt: deltaTime)
```

The [Smoothing example](../Examples/Motion/Smoothing/Sketch.swift) shakes jitter onto a moving target so you can watch the filter glide through the noise.
