#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Animation`</sup>

---

## Animation

Motion is the default in Ollin, so most movement falls out of a `time`-driven term in `draw()`. When you want a value to *ease* between states instead of snapping or moving at a constant rate, there are two pieces: the `Easing` curves, which shape a `0...1` progress, and `@Eased`, a value that eases toward whatever you assign it. And when the value comes from a noisy live signal rather than a target you set, `@Smoothed` cleans it up as it arrives.

### Contents

- [Looping progress](#loop): `loopProgress`, `pingPong`
- [Easing curves](#easing)
- [The curve catalog](#catalog)
- [`@Eased`](#eased)
- [`@Smoothed`](#smoothed)
- [`@Sprung`](#sprung): spring toward a target with momentum
- [`Timeline`](#timeline)

<a name="loop"></a>

### Looping progress

```swift
loopProgress(over duration: Double, phase: Double = 0) -> Double
pingPong(over duration: Double, phase: Double = 0) -> Double
```

Most repeating motion starts from a `0...1` progress that laps on a fixed period. `loopProgress(over:)` reads the sketch clock and hands you exactly that: `0...1` over `duration` seconds, wrapping back to `0` as each lap completes. `pingPong(over:)` is its out-and-back fold, `0` up to `1` and back to `0` over the same `duration`, so the motion it drives retraces its path instead of snapping home:

```swift
let t = loopProgress(over: 3)                       // 0...1, every 3 seconds
let x = lerp(140, width - 140, t)                   // cross, snap back, cross again

let back = pingPong(over: 3)                        // 0 -> 1 -> 0, every 3 seconds
let y = lerp(200, height - 200, back)               // sweep out and back forever
```

Under the hood a lap is just the clock wrapped by its period, `fract(time / duration)`; the helper spells it so a sketch doesn't have to. `phase` shifts the loop forward by a fraction of its length (`0.5` starts halfway through), which is the staggered-neighbors trick in one argument:

```swift
for (i, cell) in grid(columns: 12, rows: 1).cells.enumerated() {
    let t = pingPong(over: 3, phase: Double(i) / 12)   // each column a little ahead
    drawCircle(center: cell.center, radius: 12 + t * 28)
}
```

Progress from these helpers feeds everything below: reshape it with an easing curve, or hand it straight to `lerp`, a [`Ramp`](../Drawing/Color.md), or a rotation.

A sketch built this way repeats exactly, and it can say so: declare the period as [`loopDuration`](../Core/Sketch.md#loopDuration) and `--export-loop` renders exactly one lap as a seamless GIF or video (see [perfect loops](../Output/Export.md#perfect-loops)).

<a name="easing"></a>

### Easing curves

An `Easing` maps normalized progress (`0...1`) onto a shaped `0...1`. Call it like a function, and pair it with [`lerp`](../Helpers/Math.md#lerp) to interpolate between two values along the curve:

```swift
let t = loopProgress(over: 2)                                // 0...1, looping
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

Three friendly aliases cover the common case: `.easeIn`, `.easeOut`, and `.easeInOut` map to the cubic forms. `.smoothstep` is a Hermite smoothstep, a gentler S than `easeInOut` and the same curve as the bare [`smoothstep(0, 1, t)`](../Helpers/Math.md#shaping).

The [EasingGallery example](../../Examples/Motion/EasingGallery/Sketch.swift) plots all thirty so you can see the shapes side by side.

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

The [Easing example](../../Examples/Motion/Easing/Sketch.swift) races four dots toward the same target on different curves, so you can watch the curves pull apart in flight.

<a name="smoothed"></a>

### `@Smoothed`

`@Eased` glides toward a target you *know*. When instead you have a noisy live signal whose true value you *don't* know (a jittery `mouseX`/`mouseY`, or live input from OSC, MIDI, computer vision, or the phone sensors), reach for `@Smoothed`. It cleans the stream with the [1€ filter](https://gery.casiez.net/1euro/), an adaptive low-pass that stays responsive when the signal moves fast and steady when it's slow, something a fixed low-pass can't manage at both ends.

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

- **`minCutoff`** (default `1`): lower it to cut jitter while the signal is slow, at the cost of a little more lag.
- **`beta`** (default `0.007`): raise it to cut lag while the signal moves fast.

```swift
@Smoothed(minCutoff: 0.5, beta: 0.02) var angle = 0.0
```

Both are reachable live through the projected value (`$angle.beta = …`), so a [`@Param`](../Helpers/Parameters.md) knob can dial them in by feel. The projected value also gives you `$p.rawValue` (the last unsmoothed input) and `$p.set(v)` (jump there with no glide). Because the filter is timed in seconds, it behaves the same at any frame rate.

To smooth a value that isn't a sketch property, the `OneEuroFilter<Value>` underneath is public: own the state and step it yourself.

```swift
var filter = OneEuroFilter<Double>(minCutoff: 1, beta: 0.02)
let clean = filter.filter(noisy, dt: deltaTime)
```

The [Smoothing example](../../Examples/Motion/Smoothing/Sketch.swift) shakes jitter onto a moving target so you can watch the filter glide through the noise.

<a name="sprung"></a>

### `@Sprung`

The third sibling: a damped spring. `@Eased` replays a fixed curve over a fixed duration, so retargeting it mid-flight restarts the tween. A spring instead carries real momentum: retarget it and the motion bends smoothly through the turn, which is why springs feel alive under a target that never stops moving (a cursor, a tracked hand, a beat).

```swift
final class Chase: Sketch {
    @Sprung var p = Vector2.zero                      // critically damped
    @Sprung(duration: 0.4, bounce: 0.5) var r = 40.0  // wobbly

    override func draw() {
        background(.white)
        p = Vector2(mouseX, mouseY)                   // retarget freely
        r = mouseIsPressed ? 90 : 40
        drawCircle(center: p, radius: r * scale)
    }
}
```

Two knobs, both perceptual:

- **`duration`** (default `0.5`) is the response time in seconds, roughly how long a settle takes.
- **`bounce`** (default `0`) is the character. `0` is critically damped: the fastest possible arrival with no overshoot. Positive values overshoot and wobble (up to `1`, which rings forever); negative values drag in slowly, like moving through honey.

The projected value exposes the physics: `$p.velocity` (read or set), `$p.kick(impulse)` (throw the value and let it spring back, great on a beat or a click), `$p.target`, and `$p.set(v)` to jump with no motion. Works on a `Double` or a `Vector2`.

Each frame advances by the exact closed-form solution of the damped oscillator, not a numeric approximation, so a spring is unconditionally stable: a frame hitch can never make it explode or ring, and the motion is identical at any frame rate.

For spring state that isn't a sketch property (values in an array, say), the `DampedSpring<Value>` underneath is public:

```swift
var spring = DampedSpring(value: 0.0, duration: 0.6, bounce: 0.3)
let x = spring.step(toward: target, dt: deltaTime)
```

The [Springs example](../../Examples/Motion/Springs/Sketch.swift) races five bounces side by side and hangs a kickable chaser on the mouse.

<a name="timeline"></a>

### `Timeline`

`@Eased` eases toward a single moving target. When you instead want to *sequence* a value through several timed keyframes, each with its own easing (start here, glide to a value over a duration, hold, glide on), reach for `Timeline`. Build it fluently, then read `value` each frame:

```swift
let move = Timeline(0.0)
    .to(100, in: 1.5, ease: .easeOut)   // glide 0 -> 100 over 1.5s
    .hold(for: 0.5)                       // sit at 100 for 0.5s
    .to(0, in: 1.0)                       // glide back to 0
// each frame:
x = move.value
```

The clock advances in seconds, so a timeline runs the same at any frame rate. `loops` wraps it; `progress` is `0...1` over the whole sequence; `isFinished` reports when a non-looping run reaches the end; `restart()` and `seek(to:)` move the clock. It works on any `Tweenable` value (`Double`, `Vector2`, `Vector3`), so a `Timeline<Vector3>` sequences a position through space.

Like `@Eased`, a `Timeline` is advanced for you once per frame, but only when it is a **stored property on the sketch that exists before the first frame** (declared as a property, or assigned in `setup()`), the same rule `@Eased` follows. One created later inside `draw()`, or held in a local or a collection, is not picked up; advance it by hand with `tl.advance(by: deltaTime)` each frame. The cinematic [camera moves](../3D/Camera.md#catalog) drive their own timelines internally, so this rule never bites there.

The [Timeline example](../../Examples/Motion/Timeline/Sketch.swift) walks a dot around a square on one `Timeline<Vector2>`, a different easing per side with a hold at every corner, while a second timeline breathes its size; the bar underneath tracks `progress` with a tick per keyframe.

