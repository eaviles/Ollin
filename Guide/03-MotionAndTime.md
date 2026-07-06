#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 3</sup>

---

# 3. Motion and time

<img src="Images/03-MotionAndTime/RingPulse.gif" alt="Waves of light chasing around five concentric rings of colored dots, looping seamlessly" width="480">

Chapter 1 handed you `sin` as a recipe and promised the why later. This is later. By the end of this chapter you'll know where that wave actually comes from, how to make motion run at the same speed on every display, and how to bend plain, constant-rate movement into motion with character: motion that eases, snaps, springs, and bounces. It all funnels into the piece above, a loop that ends exactly where it begins, which you'll export as the book's first shareable file.

## The clock

Every sketch carries a clock, and you've already used it: `time` is the seconds since the sketch started. It has three siblings, all free to read inside `draw()`:

- `frameCount`: how many frames have been drawn so far (1 on the first).
- `deltaTime`: the seconds since the previous frame, around 0.0167 at 60 fps.
- `frameRate`: the current frames-per-second estimate.

Why care about `deltaTime`? Because your sketch's frame rate is not a constant of the universe. `draw()` runs at whatever your display refreshes at, 60 times a second on many screens, 120 on recent MacBooks, and a step like `x += 3` happens once per *frame*. The same sketch covers twice the distance on the faster display:

<img src="Images/03-MotionAndTime/DeltaTime.jpg" alt="Three dotted strips comparing one second of motion: a fixed per-frame step at 60 fps, the same step at 120 fps reaching twice as far, and a deltaTime-scaled step landing back in line" width="680">

There are two honest ways to move, and this book uses both:

- **Derive positions from `time`.** `width / 2 + time * 120` is at the same place after one second on any display, because it says where to *be*, not how far to *step*. Most of what you've written so far works this way, and it's the default habit to build.
- **Scale steps by `deltaTime`.** When a value has to accumulate (a particle that remembers where it was, which is most of Part II), write the speed per second and multiply: `x += 120 * deltaTime`. Now a fast display takes more, smaller steps and lands in the same place.

What you want to avoid is the third way, a bare per-frame step, which silently bakes your display's refresh rate into the artwork.

## The circle behind sin

Time to cash Chapter 1's promise. Here is where the wave comes from:

<img src="Images/03-MotionAndTime/CircleToSine.jpg" alt="A point on a circle at some angle, with a dashed line carrying its height onto a sine wave traced over time, the period and swing labeled" width="680">

Picture a point walking around a circle at a steady speed. Ask, at every moment, "how high is it?" and write the answers down left to right. The trace you get is the sine wave. That's all `sin` is: **the height of a point going around a circle**. Its partner `cos` is the same point's *across*. That's why the pair places things around a circle, like Chapter 1's ring of dots: they were never two separate tools, just the two coordinates of one walking point.

Everything you need to control follows from the picture:

- **One full turn is one full cycle.** The angle of a full turn is `.tau`, so `sin(time * .tau)` swings exactly once per second, and `sin(time * .tau / 5)` once every five seconds. The mysterious `/ 3` in Chapter 1's swinging circle was the period all along: one back-and-forth every three seconds.
- **The swing is the radius.** `sin` runs between -1 and 1, so multiply to make it move: `sin(...) * 300` swings 300 pixels each way.

Put both to work and the walking point itself appears:

```swift
let angle = time * .tau / 5          // one full turn every five seconds
let x = width / 2 + cos(angle) * 320
let y = height / 2 + sin(angle) * 320
drawCircle(x, y, 60)
```

An orbit, from nothing but the clock and the pair. Slow it down, speed it up, shrink the radius: each knob now means something.

## Phase: the head start

One more gift falls out of the circle picture. What happens if a second point starts its walk a little further along? Same circle, same speed, same wave, just shifted in time. That shift is called **phase**, and you make it by adding a constant inside `sin`:

<img src="Images/03-MotionAndTime/Phase.jpg" alt="Two identical sine waves, one shifted right by a bracketed phase; below, a row of dots each with a growing head start forming a wave in space" width="680">

The magic starts when *neighbors get different head starts*. Give each dot in a row a phase proportional to its position, look at any single instant, and a wave appears across space, no dot ever doing anything but its own private swing:

```swift
for i in 0..<24 {
    let x = 80 + Double(i) * 40
    let y = height / 2 + sin(time * .tau / 3 + Double(i) * 0.4) * 160
    drawCircle(x, y, 15)
}
```

Run that and you've built the bottom half of the diagram, live. And you've seen this move before: Chapter 1's breathing ring offset each circle's swing with `+ Double(i) * 0.5`. That was phase, smuggled in before it had a name. It is the single cheapest way to make many things feel alive together, and the payoff piece leans on it hard.

## map and lerp: moving between ranges

`sin` hands you -1...1, but you rarely want -1...1. You want 40...220 pixels of radius, or 0...1 for a color ramp. Chapter 2 patched this with the squeeze, `sin(...) * 0.5 + 0.5`. The grown-up tool is `map`, which carries a value from one range to another by keeping its *fraction along*:

<img src="Images/03-MotionAndTime/MapAndLerp.jpg" alt="Top: a value carried between two number lines by its fraction along, map. Bottom: dots walking a segment from a to b as t runs 0 to 1, lerp" width="680">

```swift
let radius = map(sin(time * .tau / 4), -1, 1, 40, 220)
drawCircle(width / 2, height / 2, radius)
```

Read it as a sentence: "take this value, which lives in -1...1, and speak it in 40...220." A breathing circle, and every number in sight says what it means. (By default `map` extrapolates past the ends; add `clamp: true` to pin the result inside the target range.)

Its little sibling `lerp(a, b, t)` skips the first range: `t` is already a 0...1 "how far along", the same `t` you fed to `Color.mix` and ramps in Chapter 2, and `lerp` returns the point that far from `a` to `b`. `lerp(140, 940, 0.5)` is halfway, 540.

Which raises a question: where does a moving `t` come from? From the clock, by wrapping it. Divide `time` by how long one lap should take, and keep only the fraction of the current lap you're through. That move is so common it has a name; every sketch can just ask:

```swift
let t = loopProgress(over: 3)          // 0...1, every 3 seconds
let x = lerp(140, width - 140, t)
drawCircle(x, height / 2, 50)
```

The dot crosses the canvas in three seconds, snaps back, and crosses again. There's no magic inside: `loopProgress(over: 3)` is `fract(time / 3)`, where `fract` keeps a number's fractional part, so 7.5 seconds in is `fract(2.5)`, halfway through the third lap. (`fract` is yours too, whenever you want a wrap by hand.)

If the snap offends you (it should, a little), ask for the fold instead: `pingPong(over:)` runs 0 up to 1 and back to 0 over the same period, so the trip retraces itself instead of teleporting home:

```swift
let back = pingPong(over: 3)           // 0 to 1 to 0, every 3 seconds
let x = lerp(140, width - 140, back)
```

## Shaping time

Now the heart of the chapter. Everything so far moves at a constant rate, and constant-rate motion has no character: real things lean into a start and brake into an arrival. The fix is a small family of functions with one job: **take a plain 0...1 progress in, hand a reshaped 0...1 progress out**. Feed the reshaped progress to `lerp` and the same trip happens with a different personality.

Because they're functions, you can draw them, and drawn is the only way they make sense. Every plot below reads the same way: the input progress runs along the bottom, the reshaped output is the height, and the thin diagonal is "unchanged" for reference. Under each plot is the same experiment: thirteen evenly spaced *moments*, placed where the curve sends them. Where dots bunch up, motion is slow; where they spread, it's fast.

<img src="Images/03-MotionAndTime/ShapingCurves.jpg" alt="Three panels showing linear, step, and smoothstep as curves over a faint identity diagonal, each with a strip of thirteen dots spaced by the curve" width="680">

- **linear** is the diagonal itself: out equals in, steady all the way. It's what you've been using.
- **step** is an `if` wearing a function costume: 0 until the halfway point, then 1. No in-between at all, which is exactly what you want for a blink, a flip, a light switching on.
- **smoothstep** is the S between them, and it's the one to internalize. Follow the curve: it leaves the floor gently, hurries through the middle, and settles onto the ceiling gently. In the dot strip, that's tight spacing, wide spacing, tight spacing: ease out, travel, ease in. No corners, no jolt, just a motion that feels finished.

In Ollin both ship as bare functions, `step(edge, x)` and `smoothstep(edge0, edge1, x)`. The extra numbers are *edges*: where the ramp begins and where it ends. With the edges at 0 and 1, smoothstep is exactly the S in the figure:

```swift
let t = loopProgress(over: 3)
let x = lerp(140, width - 140, smoothstep(0, 1, t))
drawCircle(x, height / 2, 50)
```

Same dot, same three seconds, but now it *departs* and *arrives*. (Under the hood the S is one line of algebra, `t * t * (3 - 2 * t)`; you'll never need to know that, but it's pleasant that the whole curve fits in a pocket.)

And because the edges are yours to place, smoothstep is more than a reshape: it's a **window cutter**. `smoothstep(0.3, 1.0, wave)` reads "0 until the wave climbs past 0.3, 1 once it reaches the top, and a soft shoulder in between", which turns any signal into a smooth spotlight. Hold that thought; the payoff piece runs on it. This little S-curve is one of the great workhorses of computer graphics; when you reach shaders in Chapter 15, it'll be there waiting, spelled exactly the same, doing per-pixel what it does per-frame here.

## A catalog of curves

Once you can read curve-and-strip, you can read any easing function at a glance, and Ollin ships a whole catalog of them: Robert Penner's classic easing equations, thirty curves in ten families, each in ease-in (slow start), ease-out (slow arrival), and ease-in-out forms.

<img src="Images/03-MotionAndTime/EasingFamilies.jpg" alt="Six easing curves with spacing strips: easeInQuad, easeOutQuad, easeInOutCubic, then easeOutBack, easeOutElastic, and easeOutBounce which overshoot and settle" width="680">

The top row is polite: quadratics and cubics that stay inside 0...1 and differ in how hard they lean. The bottom row has personality on purpose. `easeOutBack` overshoots the target and comes back, like reaching past a shelf. `easeOutElastic` arrives like a plucked rubber band. `easeOutBounce` drops the value onto its target in shrinking hops. Watch four of them run the same trip:

<img src="Images/03-MotionAndTime/CurvesRace.gif" alt="Four dots running the same out-and-back trip on linear, easeInQuad, easeOutQuad, and smoothstep curves, their spacing differing in flight" width="600">

Same start, same finish, same four seconds. The only difference is *when* each dot spends its time. That's the whole craft of easing in one sentence: an animation's character lives in the spacing, not the path. Hand the dot listing `Easing.easeOutBounce(t)` in place of `smoothstep(0, 1, t)` and nothing about the trip changes except everything about how it feels. (The S itself lives in the catalog too, as `Easing.smoothstep`, for anywhere that wants a curve by name.)

The full table of thirty names is in the [Animation](../Docs/Helpers/Animation.md#catalog) reference, and the [EasingGallery example](../Examples/Motion/EasingGallery/Sketch.swift) plots them all side by side.

## Values that chase, signals that shake

The shaping functions assume you're steering `t` yourself. Two property wrappers handle the everyday cases where you'd rather not.

**`@Eased`** is for a value with a *target*: assign where it should go, read where it currently is, and it glides over on its own, along a curve and duration you pick once:

```swift
final class Springy: Sketch {
    @Eased(duration: 0.9, curve: .easeOutElastic) var x = 540.0
    @Eased(duration: 0.9, curve: .easeOutElastic) var y = 540.0

    override func draw() {
        background(.white)
        fill(.coral)
        drawCircle(x, y, 60)
    }

    override func mousePressed() {
        x = mouseX
        y = mouseY
    }
}
```

Click around: the dot springs to each click, and there's no progress variable for you to manage. Like everything in this chapter, the tween is timed in seconds, so it feels identical at 60 and 120 fps.

**`@Smoothed`** is for the opposite situation: the value arrives *from outside*, continuously, and shakes. A jittery mouse, and later in this book MIDI knobs, camera trackers, and phone sensors. There's no target to ease toward, only a noisy stream to clean as it comes:

<img src="Images/03-MotionAndTime/SmoothedSignal.jpg" alt="A jittery gray signal path with the smoothed version drawn through it in orange" width="680">

```swift
@Smoothed var x = 0.0
// each frame: feed the raw value in, read the calm one back
x = mouseX
```

Behind it is an adaptive filter that stays steady while the signal is slow and snaps awake when it moves fast, which a simple average can't do. File it away until Part V hands you your first shaky tracker; the [Animation](../Docs/Helpers/Animation.md#smoothed) page has the tuning knobs.

## Choreography: Timeline

`@Eased` glides toward one target at a time. When a value should follow a *script*, rise over 1.2 seconds, hold, then tumble back down, build a `Timeline`: a sequence of timed keyframes, each segment with its own easing, read like a value:

<img src="Images/03-MotionAndTime/TimelineCurve.jpg" alt="A timeline's value plotted over 2.8 seconds: an eased rise to 1, a flat hold, then an easeOutBounce drop to 0.25, keyframes marked as dots" width="680">

```swift
final class Rise: Sketch {
    let move = Timeline(0.0)
        .to(1, in: 1.2, ease: .easeInOut)
        .hold(for: 0.6)
        .to(0.25, in: 1.0, ease: .easeOutBounce)

    override func setup() {
        move.loops = true
    }

    override func draw() {
        background(.white)
        fill(Color(hex: 0x5E60CE))
        let y = map(move.value, 0, 1, height - 200, 200)
        drawCircle(width / 2, y, 70)
    }
}
```

The plot above *is* this timeline, sampled and drawn by an Ollin sketch like every figure in this book. Timelines advance themselves once per frame as long as they're stored properties on the sketch, like `move` here; one you create on the fly inside `draw()` needs stepping by hand (`move.advance(by: deltaTime)`). They loop, report `progress` and `isFinished`, can be restarted and scrubbed, and sequence 2D and 3D positions as happily as numbers. The details live in [Animation](../Docs/Helpers/Animation.md#timeline).

## The payoff: a loop that never ends

Now the piece from the top of the chapter, and the one new idea it needs: the **perfect loop**. A GIF plays its frames in a ring, so if the last frame flows into the first, the motion reads as endless. The recipe is exactly the circle-to-sine picture: `sin` repeats every full turn, so *pick a loop length, and make every time-driven term complete a whole number of turns in it*. In code: choose a `loopTime`, make one beat from it, `loopProgress(over: loopTime) * .tau`, exactly one full turn per lap, and let that beat (times a whole number) be the only time in the sketch. Phase offsets are free, they just shift the start of each swing. Space has the same rule bent into a circle: a wave wrapped around a ring must fit a whole number of times, or it won't meet itself.

That's the entire theory of the piece. Make `MySketches/RingPulse.swift`:

```swift
import Ollin

final class RingPulse: Sketch {
    @Param("Waves", 1...6) var waves = 3
    @Param("Pulse width", 0.1...0.9) var pulseWidth = 0.35

    let loopTime = 4.0
    let ramp = Ramp([
        Color(hex: 0x5E60CE), Color(hex: 0x64DFDF),
        Color(hex: 0xFFB703), Color(hex: 0xE56B6F),
    ])

    override func draw() {
        background(Color(hex: 0x0E1116))
        noStroke()
        let beat = loopProgress(over: loopTime) * .tau   // one full turn per loop
        for ring in 0..<5 {
            let radius = 110.0 + Double(ring) * 82
            let count = 14 + ring * 6
            let base = ramp.color(at: Double(ring) / 4)
            var direction = 1.0
            if ring % 2 == 1 { direction = -1 }
            for i in 0..<count {
                let angle = Double(i) / Double(count) * .tau
                let wave = sin(angle * Double(waves) - beat * 2 * direction)
                let lit = smoothstep(1 - pulseWidth * 2, 1, wave)
                fill(Color.mix(base, Color(hex: 0xFFF6E8), t: lit * 0.4))
                let x = width / 2 + cos(angle) * (radius + lit * 18)
                let y = height / 2 + sin(angle) * (radius + lit * 18)
                drawCircle(x, y, 6 + lit * 20)
            }
        }
    }
}
```

Run it with `swift run OllinLive MySketches/RingPulse.swift` and take the interesting lines apart:

- `beat` is the loop's heartbeat: `loopProgress` laps 0...1 once every `loopTime` seconds, so times `.tau` it turns exactly one full circle per lap. The only other time term in the sketch is `beat * 2`, a whole multiple, so frame 0 and frame `loopTime` are identical. That's the loop rule, enforced by construction.
- `wave` is the phase trick from earlier, bent into a circle: each dot's head start is its angle times the wave count, so the crests *travel* around the ring. The count has to stay whole or the wave won't meet itself where the ring closes, so `waves` starts at `3` (not `3.0`): a whole-number property makes a whole-number knob, stepping 1, 2, 3 instead of sliding through fractions. `Double(waves)` converts it for the math, the same move as Chapter 1's `Double(i)`.
- `lit` is the window cutter from the shaping section earning its keep: a **soft spotlight**. The wave lives in -1...1, and smoothstep's edges carve out its crest, everything below the threshold 0, the peak 1, soft shoulders between, so dots swell and fade instead of switching. Widen `Pulse width` and the lower edge drops; the window opens and the whole ring breathes.
- Everything `lit` touches is a `lerp` in spirit: the color leans toward warm white by `lit * 0.4` (Chapter 2's `Color.mix`), the dot lifts outward by `lit * 18`, and swells from 6 up to 26. One shaped value, three payoffs.
- `direction` flips alternate rings, which is most of why the piece feels alive rather than mechanical.

When it feels right in the live window, export it. Anything Ollin can run it can also render headlessly to a file, and the live host takes the same export flags the example targets do:

```sh
swift run OllinLive MySketches/RingPulse.swift --export-gif ring.gif --seconds 4 --gif-width 540
```

Four seconds at the default 25 fps, scaled to 540 pixels: a small file that loops forever, because `--seconds 4` matches `loopTime` exactly. Your first export, and it's the piece at the top of this chapter, rendered by this same command. (`--export-video ring.mp4` writes a real video instead, and `--export frame.png` grabs a still; the whole menu is in [Export](../Docs/Output/Export.md).)

Then make it yours:

- Set `Waves` to 1 for a slow radar sweep, or 6 for a glitter of small pulses.
- Add a breath: make each `radius` line `radius + sin(beat + Double(ring)) * 10`. One whole multiple of the beat, so the loop survives. Check it by re-exporting.
- Replace the `smoothstep` in `lit` with `step(1 - pulseWidth * 2, wave)` and the glow becomes a hard blink: same window, no shoulders. Put the smoothstep back and appreciate the shoulders.
- Make all rings run the same `direction`, or give the ramp four colors of your own.

## Where this comes from

The named easing curves are Robert Penner's easing equations, published with his 2002 book *Programming Macromedia Flash MX* and since absorbed into practically every animation system; Ollin's are written from the formulas catalogued at [easings.net](https://easings.net). The craft behind them is older than software: the animator's principles of slow-in and slow-out grew out of the Disney studio of the 1930s, and "the spacing is the animation" is their lesson. Smoothstep is a small classic of computer graphics shading languages, where it does per-pixel what this chapter does per-frame; [The Book of Shaders](https://thebookofshaders.com) by Patricio Gonzalez Vivo and Jen Lowe teaches that per-pixel world beautifully, and its insistence on *drawing* shaping functions rather than defining them shaped this chapter. `@Smoothed` implements the [1€ filter](https://gery.casiez.net/1euro/) by Géry Casiez, Nicolas Roussel, and Daniel Vogel (CHI 2012). Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Math helpers](../Docs/Helpers/Math.md): `map`, `lerp`, `dist`, the shaping scalars, and the constants.
- [Animation](../Docs/Helpers/Animation.md): the full easing catalog, `@Eased`, `@Smoothed`, and `Timeline`.
- [Sketch](../Docs/Core/Sketch.md#temporal-state): the clock properties in one table.
- [Export](../Docs/Output/Export.md): stills, sequences, video, GIF sizing, and render quality.
- Worked examples, all in [`Examples/Motion/`](../Examples/Motion/): `Breathing` (map on a pulse), `Easing` (four dots racing to a click), `EasingGallery` (all thirty curves), `Timeline` (a scripted tour of a square, one easing per side), `Smoothing` (the filter chasing a shaky target), `SineSweep`, and `Orbits`.

---

[Contents](README.md#contents) · Previous: [Chapter 2, Color that works](02-Color.md) · Next: [Chapter 4, Randomness](04-Randomness.md)
