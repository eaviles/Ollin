#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Coupled oscillators`</sup>

---

## Coupled oscillators

`Kuramoto` is Kuramoto's model of synchronization. A crowd of oscillators each runs at its own natural pace, and each is pulled toward the phase of the others. Weakly coupled, they drift apart and the crowd is incoherent. Past a critical coupling a locked group forms and grows, and the crowd falls into step. It is the model behind fireflies flashing together, crickets chirping in unison, pacemaker cells, a footbridge swaying under a crowd, and the pendulum clocks Huygens found beating together on one wall. You hold one on the sketch, advance it each frame, and read its phases to draw. It runs on the CPU, and a run is a pure function of its seed and parameters, so an export replays it exactly.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/12-FlocksAndSwarms/Fireflies-dark.jpg">
  <img src="../../Guide/Images/12-FlocksAndSwarms/Fireflies.jpg" alt="Left, three wheels of small dots on a circle at three moments, the dots scattered around the first, gathering on the second, and bunched together on the third, each wheel with an orange arrow from its center growing longer. Right, three curves of coherence over twelve seconds: one staying near the floor, one wandering low, and one climbing to nearly one" width="880">
</picture>

### Contents

- [Quick start](#quick-start)
- [The rule](#the-rule)
- [Reading the crowd](#reading-the-crowd)
- [Parameters](#parameters)
- [On a ring](#on-a-ring)
- [Notes](#notes)

<a name="quick-start"></a>

### Quick start

Three hundred fireflies, each glowing by its phase:

```swift
let sync = Kuramoto(count: 300, coupling: 2, seed: 7)
var spots: [Vector2] = []

override func setup() {
    spots = (0 ..< 300).map { _ in Vector2(random(width), random(height)) }
}

override func draw() {
    sync.advance()
    background(.black)
    noStroke()
    for (i, phase) in sync.phases.enumerated() {
        fill(Color(white: (1 + cos(phase)) / 2))
        drawCircle(center: spots[i], radius: 6)
    }
}
```

Watch it for a few seconds. At a coupling of 2 against the default spread, the crowd locks and the dots brighten together. Set the coupling to 0.5 and they never do.

<a name="the-rule"></a>

### The rule

For an oscillator with natural frequency `w`, its phase advances at `w + coupling * r * sin(meanPhase - phase - lag)`. Here `r` and `meanPhase` are the crowd's own order parameter, described below, so every oscillator is pulled toward the crowd's phase, and harder the more coherent the crowd already is. That is Kuramoto's mean-field form, and it is what makes the model cheap: one pass over the crowd, however large, rather than one over every pair. The integration is fixed substeps of at most 1/240 of a second, so a bigger interval costs more substeps rather than accuracy, and every phase is kept in `0 ..< 2 * .pi`.

<a name="reading-the-crowd"></a>

### Reading the crowd

- **`phases`** is every oscillator's phase in radians. Read it to draw: a firefly glows by `(1 + cos(phase)) / 2`, a dot sits on a circle at its phase, a pendulum swings by `sin(phase)`. Set an entry to kick one oscillator.
- **`coherence`** is the order parameter r, the length of the mean of every phase's unit vector: 0 when the phases are spread evenly around the circle, 1 when they all agree. It is the measure to watch as a crowd locks.
- **`meanPhase`** is the direction of that mean vector, the phase of the crowd as a whole, which a locked crowd shares.
- **`criticalCoupling`** is the coupling at which a locked group first forms, for the normal spread of natural frequencies the crowd was made with: `spread * sqrt(8 / pi)`, from Kuramoto's `2 / (pi * g(0))` with `g` the frequency distribution. Below it the crowd stays scattered however long it runs. A few times above it, the crowd locks nearly whole. Identical oscillators, a spread of 0, lock at any coupling.
- **`frequencies`** is every oscillator's natural pace in radians per second. Set it to hand the crowd a spectrum of your own, two clusters or a chord; `criticalCoupling` keeps describing the spread the crowd was made with.

<a name="parameters"></a>

### Parameters

`Kuramoto(count:coupling:frequency:spread:lag:range:seed:)` makes a crowd of `count` oscillators at random phases.

- **`coupling`** (default `1`) is how hard the crowd pulls on each phase, K, in radians per second. Compare it with `criticalCoupling` after making the crowd. Settable while it runs, which is how a slider takes a crowd across the transition.
- **`frequency`** (default `1`) is the center of the natural frequencies in radians per second: 1 is one turn every 2 pi seconds, about six seconds.
- **`spread`** (default `0.5`) is the standard deviation of the natural frequencies, in the same units. A wide spread needs a stronger pull; the critical coupling is 1.6 times the spread.
- **`lag`** (default `0`) is a phase lag in the pull, in radians. With a lag a locked crowd runs slower than its natural pace, by `coupling * sin(lag)` when fully locked, and on a ring a lag is what makes patterns travel.
- **`range`** (default `0`) is how many neighbors each way on a ring an oscillator listens to; 0 is the mean field, where everyone listens to everyone.
- **`seed`** picks the phases and the frequencies, so the same seed replays the same crowd.

<a name="on-a-ring"></a>

### On a ring

With `range` above 0 each oscillator listens only to that many neighbors each way, the array's order wrapping into a ring, and the pull is averaged over them so `coupling` means the same per neighbor. A ring locks locally: neighbor pairs agree within a few degrees. The ring as a whole can keep a twist, the phase winding once or several times around it, so `coherence` stays low even though every neighbor agrees with its neighbor. Add a `lag` and the locked pattern travels around the ring. Draw the ring as a circle of dots, or as a row, and the twist and the traveling wave are what you see.

<a name="notes"></a>

### Notes

- The mean field is one pass over the crowd per substep, so thousands of oscillators cost nothing a frame notices; a ring costs `range` times that.
- `advance()` is one 60 fps frame. Pass a fixed interval for a run that replays, as the default does; a frame's own measured time makes the run depend on the machine.
- The [Kuramoto example](../../Examples/Simulation/Kuramoto/Sketch.swift) is a meadow of fireflies with the phases on a wheel and the order parameter as an arrow from its center, the coupling and the spread on sliders.
