#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Motion</sup>

---

## Motion

Animation driven by `time`. The draw loop runs continuously by default, so nothing has to start it.

| [![ArcModes](https://media.ollin.art/examples/Motion/ArcModes/still-640.jpg)](ArcModes/) | [![Attractor](https://media.ollin.art/examples/Motion/Attractor/still-640.jpg)](Attractor/) | [![Automation](https://media.ollin.art/examples/Motion/Automation/still-640.jpg)](Automation/) | [![DerivedCurves](https://media.ollin.art/examples/Motion/DerivedCurves/still-640.jpg)](DerivedCurves/) |
|---|---|---|---|
| [ArcModes](ArcModes/) | [Attractor](Attractor/) | [Automation](Automation/) | [DerivedCurves](DerivedCurves/) |
| [![DoublePendulum](https://media.ollin.art/examples/Motion/DoublePendulum/still-640.jpg)](DoublePendulum/) | [![Easing](https://media.ollin.art/examples/Motion/Easing/still-640.jpg)](Easing/) | [![EasingGallery](https://media.ollin.art/examples/Motion/EasingGallery/still-640.jpg)](EasingGallery/) | [![EllipseField](https://media.ollin.art/examples/Motion/EllipseField/still-640.jpg)](EllipseField/) |
| [DoublePendulum](DoublePendulum/) | [Easing](Easing/) | [EasingGallery](EasingGallery/) | [EllipseField](EllipseField/) |
| [![FlowField](https://media.ollin.art/examples/Motion/FlowField/still-640.jpg)](FlowField/) | [![Formula](https://media.ollin.art/examples/Motion/Formula/still-640.jpg)](Formula/) | [![FormulaParts](https://media.ollin.art/examples/Motion/FormulaParts/still-640.jpg)](FormulaParts/) | [![Harmonograph](https://media.ollin.art/examples/Motion/Harmonograph/still-640.jpg)](Harmonograph/) |
| [FlowField](FlowField/) | [Formula](Formula/) | [FormulaParts](FormulaParts/) | [Harmonograph](Harmonograph/) |
| [![InverseKinematics](https://media.ollin.art/examples/Motion/InverseKinematics/still-640.jpg)](InverseKinematics/) | [![Lissajous](https://media.ollin.art/examples/Motion/Lissajous/still-640.jpg)](Lissajous/) | [![Mandala](https://media.ollin.art/examples/Motion/Mandala/still-640.jpg)](Mandala/) | [![Morphing](https://media.ollin.art/examples/Motion/Morphing/still-640.jpg)](Morphing/) |
| [InverseKinematics](InverseKinematics/) | [Lissajous](Lissajous/) | [Mandala](Mandala/) | [Morphing](Morphing/) |
| [![Myriad](https://media.ollin.art/examples/Motion/Myriad/still-640.jpg)](Myriad/) | [![NBody](https://media.ollin.art/examples/Motion/NBody/still-640.jpg)](NBody/) | [![Orbits](https://media.ollin.art/examples/Motion/Orbits/still-640.jpg)](Orbits/) | [![PerfectLoop](https://media.ollin.art/examples/Motion/PerfectLoop/still-640.jpg)](PerfectLoop/) |
| [Myriad](Myriad/) | [NBody](NBody/) | [Orbits](Orbits/) | [PerfectLoop](PerfectLoop/) |
| [![Petals](https://media.ollin.art/examples/Motion/Petals/still-640.jpg)](Petals/) | [![SineSweep](https://media.ollin.art/examples/Motion/SineSweep/still-640.jpg)](SineSweep/) | [![Smoothing](https://media.ollin.art/examples/Motion/Smoothing/still-640.jpg)](Smoothing/) | [![Spokes](https://media.ollin.art/examples/Motion/Spokes/still-640.jpg)](Spokes/) |
| [Petals](Petals/) | [SineSweep](SineSweep/) | [Smoothing](Smoothing/) | [Spokes](Spokes/) |
| [![Springs](https://media.ollin.art/examples/Motion/Springs/still-640.jpg)](Springs/) | [![Sway](https://media.ollin.art/examples/Motion/Sway/still-640.jpg)](Sway/) |  |  |
| [Springs](Springs/) | [Sway](Sway/) |  |  |

| Example | What it shows |
|---|---|
| [ArcModes](ArcModes/Sketch.swift) | the three `drawArc` closing modes (open, chord, pie) side by side under an animated sweep |
| [Attractor](Attractor/Sketch.swift) | a rotating de Jong–style chaotic attractor sampled into ~98k fine dots a frame, which blur together into a soft radial bloom: the main example of `drawPoint` at volume (SDF) |
| [Automation](Automation/Sketch.swift) | keyframed parameters: four parameters, each on its own track (size, place, and color move smoothly, and the fill switch steps), and the sketch reads its own tracks back to plot them under the stage (`automate`, `Automation`) |
| [Beats](Beats/Sketch.swift) | the clock's beats charted: `every(1)`, an off-beat `every(1, phase: 0.5)`, a fast `every(0.25)`, and a frame-counted `everyFrames(60)` each stamp their own lane over a twelve-second lap, and `after(4)` fires once |
| [DoublePendulum](DoublePendulum/Sketch.swift) | the butterfly effect: 24 `DoublePendulum`s start a ten-thousandth of a radian apart, swing together as one line, then separate into 24 unrelated motions |
| [Easing](Easing/Sketch.swift) | four dots race to the same target flip on different `@Eased` curves (linear, ease-in, ease-out, ease-in-out), so they pull apart in flight |
| [EasingGallery](EasingGallery/Sketch.swift) | all thirty named `Easing` curves plotted in a grid, each with a dot that follows its shape, and the back, elastic, and bounce rows overshoot their cells |
| [DerivedCurves](DerivedCurves/Sketch.swift) | one curve picked on the inspector and the two derived from it, `reversed()` and `mirrored()`, each riding a dot on the same out-and-back trip beside a plot of its shape |
| [EllipseField](EllipseField/Sketch.swift) | rows of white outlines in two drifting columns: whole `drawEllipse` rings on the left and chord-closed `drawArc` crescents on the right, with position, squash, and arc sweep all driven by `signedNoise` |
| [Epicycles](Epicycles/Sketch.swift) | Fourier epicycles: a chain of spinning circles redraws an SVG whale, the term count is a parameter, and one lap takes one `loopDuration` |
| [FlowField](FlowField/Sketch.swift) | a `curlNoise` flow field: short lines follow the divergence-free curl and drift with `time` |
| [Formula](Formula/Sketch.swift) | six parameters driven by rules typed as text rather than written in Swift, and the sketch prints the rule behind each one under the ring (`drive`, `Formula`) |
| [FormulaParts](FormulaParts/Sketch.swift) | a parameter made of several numbers, with one rule per part: a rectangle whose size follows a rule and whose place does not, a dot that reads the rectangle back part by part, a color under a rule, and a pair of ends under a rule (`drive(_:x:y:)`) |
| [Harmonograph](Harmonograph/Sketch.swift) | a harmonograph in motion: damped pendulums (their settings drawn from the seeded `random`, one figure per `variation`) weave a nested trace, and the trace replays pen-first, exactly as the machine would draw it (`Harmonograph`) |
| [InverseKinematics](InverseKinematics/Sketch.swift) | five `IKChain` tentacles reach toward a swimming lure, a stiffness parameter (`maxBend`) runs from rope to whip, and a toggle swaps the even solver for the tip-curling one |
| [Lissajous](Lissajous/Sketch.swift) | the Lissajous table: a grid of `lissajous(a:b:)` figures with the column frequency against the row frequency, a shared phase that rolls every figure through its family, and tracers that move at true parametric speed |
| [Mandala](Mandala/Sketch.swift) | nested, counter-rotating `hollow` shapes (each a framed band in one call) that slide into a moiré (`hollow`, SDF) |
| [Morphing](Morphing/Sketch.swift) | shape morphing: a star tweens into a blob and the blob into a donut, and every in-between step is a real vector `Shape` (`ShapeMorph`, `morphed(toward:)`) |
| [Myriad](Myriad/Sketch.swift) | 8,100 noise-driven circles on the SDF path, thousands of shapes at full speed, and a parameter swaps them for rounded rects (the corner radius sweeps from square to pill, and each rect turns by its own angle) |
| [NBody](NBody/Sketch.swift) | two toy galaxies (`NBody.disk`) on a bound grazing orbit: tides pull streamer arms off both disks, then the survivors fall back and merge |
| [Orbits](Orbits/Sketch.swift) | ten circles orbiting the center at rising speeds |
| [PerfectLoop](PerfectLoop/Sketch.swift) | a sketch that repeats exactly: `loopDuration` declares the period, looping noise closes the motion, and `--export-loop` renders one seamless lap |
| [Petals](Petals/Sketch.swift) | `drawOrientedVesica` lenses and interleaved `drawOrientedBox` bars span counter-rotating rings, their tips and endpoints drift, and their waists and thicknesses widen and narrow (SDF) |
| [SineSweep](SineSweep/Sketch.swift) | a circle swept across the canvas by `sin(time)` |
| [Smoothing](Smoothing/Sketch.swift) | `@Smoothed` cleans a jittery figure-eight signal with the 1€ filter: the raw input shows as faint dots, and the smoothed output as a smooth tracking trail |
| [Spokes](Spokes/Sketch.swift) | a sunburst of thick, round-capped `drawLine` spokes that pulse with `time` (capsule SDF) |
| [Springs](Springs/Sketch.swift) | the spring family: five dots race the same hop on different `bounce` settings, and a `@Sprung` chaser follows the mouse with momentum (click to kick it) |
| [Steering](Steering/Sketch.swift) | steering creatures (`Vehicle`): a group follows a wavy loop while keeping their distance from each other, wanderers roam and leave trails, and a pursuer intercepts the lead follower |
| [Sway](Sway/Sketch.swift) | the five `SwayShape`s (`.sine`, `.triangle`, `.saw`, `.square`, and a `.wander` that still closes its lap) plotted over one lap with a dot following each, and a circle sized live by the same call (`sway(over:in:shape:phase:)`) |
| [Timeline](Timeline/Sketch.swift) | a `Timeline<Vector2>` walks a dot around a square, with one easing per side and a hold at each corner, while a second timeline grows and shrinks its size, and `progress` is tracked below with a tick per keyframe |
| [Trail](Trail/Sketch.swift) | a Lissajous point traced by a 600-segment polyline |

Run one with `swift run Example-Motion-<Name>`, for example `swift run Example-Motion-SineSweep`.
