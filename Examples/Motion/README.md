#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Motion</sup>

---

## Motion

Animation driven by `time`, with the draw loop running continuously by default.

| Example | What it shows |
|---|---|
| [ArcModes](ArcModes/Sketch.swift) | the three `drawArc` closing modes — open, chord, pie — side by side under an animated sweep |
| [Attractor](Attractor/Sketch.swift) | a rotating de Jong–style chaotic attractor sampled into ~98k fine dots a frame, smearing into a soft radial bloom — the headline for `drawPoint` at volume (SDF) |
| [Automation](Automation/Sketch.swift) | keyframed parameters: four parameters on their own tracks (size, place, color travel; the fill switch steps), with the sketch reading its own tracks back to plot them under the stage (`automate`, `Automation`) |
| [Beats](Beats/Sketch.swift) | the clock's beats charted: `every(1)`, an off-beat `every(1, phase: 0.5)`, a fast `every(0.25)` and a frame-counted `everyFrames(60)` each stamp a lane over a twelve-second lap, with `after(4)` firing once |
| [DoublePendulum](DoublePendulum/Sketch.swift) | the butterfly effect drawn: 24 `DoublePendulum`s released a ten-thousandth of a radian apart swing as one line, then tear into 24 unrelated dances |
| [Easing](Easing/Sketch.swift) | four dots race one target flip on different `@Eased` curves — linear, ease-in, ease-out, ease-in-out — pulling apart in flight |
| [EasingGallery](EasingGallery/Sketch.swift) | all thirty named `Easing` curves plotted in a grid, each with a dot riding its shape — the back, elastic, and bounce rows overshoot their cells |
| [EllipseField](EllipseField/Sketch.swift) | rows of white outlines in two drifting columns, whole `drawEllipse` rings on the left and chord-closed `drawArc` crescents on the right, position, squash, and arc sweep all riding `signedNoise` |
| [Epicycles](Epicycles/Sketch.swift) | Fourier epicycles: a chain of spinning circles re-draws an SVG whale, term count on a parameter, one lap per `loopDuration` |
| [FlowField](FlowField/Sketch.swift) | a `curlNoise` flow field: short lines follow the divergence-free curl, drifting with `time` |
| [Formula](Formula/Sketch.swift) | six parameters driven by rules typed as text rather than written as Swift, with the sketch printing the rule driving each one under the ring (`drive`, `Formula`) |
| [FormulaParts](FormulaParts/Sketch.swift) | a parameter of more than one number under one rule per part: a rectangle whose size is ruled and whose place is not, a dot reading the rectangle back part by part, a ruled color and a ruled pair of ends (`drive(_:x:y:)`) |
| [Harmonograph](Harmonograph/Sketch.swift) | a harmonograph performing: damped pendulums (rolled from the seeded `random`, one figure per `variation`) weave a nested trace that replays pen-first, exactly as the machine would draw it (`Harmonograph`) |
| [InverseKinematics](InverseKinematics/Sketch.swift) | five `IKChain` tentacles strain toward a swimming lure; a stiffness parameter (`maxBend`) runs rope to whip, and a toggle swaps the even solver for the tip-curling one |
| [Lissajous](Lissajous/Sketch.swift) | the Lissajous table: a grid of `lissajous(a:b:)` figures, column against row frequency, a shared phase rolling every figure through its family while tracers ride at true parametric speed |
| [Mandala](Mandala/Sketch.swift) | nested, counter-rotating `hollow` shapes — each a framed band in one call — sliding into a moiré (`hollow`, SDF) |
| [Morphing](Morphing/Sketch.swift) | shape morphing: a star tweened into a blob, the blob into a donut, every in-between a real vector `Shape` (`ShapeMorph`, `morphed(toward:)`) |
| [Myriad](Myriad/Sketch.swift) | 8,100 noise-driven circles on the SDF path, thousands of shapes at full speed, with a parameter swapping them for rounded rects (corner radius sweeping square→pill, each turned by its own angle) |
| [NBody](NBody/Sketch.swift) | two toy galaxies (`NBody.disk`) on a bound grazing orbit: tides peel streamer arms off both disks, then the survivors fall back to merge |
| [Orbits](Orbits/Sketch.swift) | ten circles orbiting the center at rising speeds |
| [PerfectLoop](PerfectLoop/Sketch.swift) | a sketch that repeats exactly: `loopDuration` declares the period, looping noise closes the motion, and `--export-loop` renders one seamless lap |
| [Petals](Petals/Sketch.swift) | `drawOrientedVesica` lenses and interleaved `drawOrientedBox` bars spanning counter-rotating rings, tips and endpoints drifting, waists and thicknesses breathing (SDF) |
| [SineSweep](SineSweep/Sketch.swift) | a circle swept across the canvas by `sin(time)` |
| [Smoothing](Smoothing/Sketch.swift) | `@Smoothed` cleans a jittery figure-eight signal with the 1€ filter — faint raw dots, a smooth tracking trail |
| [Spokes](Spokes/Sketch.swift) | a sunburst of fat, round-capped `drawLine` spokes pulsing with `time` (capsule SDF) |
| [Springs](Springs/Sketch.swift) | the spring family portrait: five dots race the same hop on different `bounce` settings, and a `@Sprung` chaser follows the mouse with momentum (click to kick) |
| [Steering](Steering/Sketch.swift) | steering creatures (`Vehicle`): a troop follows a wavy loop with personal space, wanderers roam leaving trails, and a pursuer intercepts the lead follower |
| [Sway](Sway/Sketch.swift) | the five `SwayShape`s plotted over one lap with a dot riding each, and a circle sized live by the same call: `.sine`, `.triangle`, `.saw`, `.square`, and a `.wander` that still closes its lap (`sway(over:in:shape:phase:)`) |
| [Timeline](Timeline/Sketch.swift) | a `Timeline<Vector2>` walks a dot around a square, one easing per side with a hold at each corner, while a second timeline breathes its size; `progress` tracked below, a tick per keyframe |
| [Trail](Trail/Sketch.swift) | a Lissajous point traced by a 600-segment polyline |

Run one with `swift run Example-Motion-<Name>`, e.g. `swift run Example-Motion-SineSweep`.
