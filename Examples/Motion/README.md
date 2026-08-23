#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Motion</sup>

---

## Motion

Animation driven by `time`, with the draw loop running continuously by default.

| Example | What it shows |
|---|---|
| [ArcField](ArcField/Sketch.swift) | EllipseField's cousin: chord-closed `drawArc` crescents whose start and sweep also ride `signedNoise` |
| [ArcModes](ArcModes/Sketch.swift) | the three `drawArc` closing modes — open, chord, pie — side by side under an animated sweep |
| [Attractor](Attractor/Sketch.swift) | a rotating de Jong–style chaotic attractor sampled into ~98k fine dots a frame, smearing into a soft radial bloom — the headline for `drawPoint` at volume (SDF) |
| [Automation](Automation/Sketch.swift) | keyframed parameters: four knobs on their own tracks (size, place, color travel; the fill switch steps), with the sketch reading its own tracks back to plot them under the stage (`automate`, `Automation`) |
| [Breathing](Breathing/Sketch.swift) | the same circle, animated via `time` |
| [DoublePendulum](DoublePendulum/Sketch.swift) | the butterfly effect drawn: 24 `DoublePendulum`s released a ten-thousandth of a radian apart swing as one line, then tear into 24 unrelated dances |
| [Easing](Easing/Sketch.swift) | four dots race one target flip on different `@Eased` curves — linear, ease-in, ease-out, ease-in-out — pulling apart in flight |
| [EasingGallery](EasingGallery/Sketch.swift) | all thirty named `Easing` curves plotted in a grid, each with a dot riding its shape — the back, elastic, and bounce rows overshoot their cells |
| [EllipseField](EllipseField/Sketch.swift) | rows of `drawEllipse` outlines in two columns, drifting and squashing via `signedNoise` |
| [Epicycles](Epicycles/Sketch.swift) | Fourier epicycles: a chain of spinning circles re-draws an SVG whale, term count on a knob, one lap per `loopDuration` |
| [FlowField](FlowField/Sketch.swift) | a `curlNoise` flow field: short lines follow the divergence-free curl, drifting with `time` |
| [Formula](Formula/Sketch.swift) | six knobs driven by rules typed as text rather than written as Swift, with the sketch printing the rule driving each one under the ring (`drive`, `Formula`) |
| [Harmonograph](Harmonograph/Sketch.swift) | a harmonograph performing: damped pendulums (rolled from the seeded `random`, one figure per `variation`) weave a nested trace that replays pen-first, exactly as the machine would draw it (`Harmonograph`) |
| [InverseKinematics](InverseKinematics/Sketch.swift) | five `IKChain` tentacles strain toward a swimming lure; a stiffness knob (`maxBend`) runs rope to whip, and a toggle swaps the even solver for the tip-curling one |
| [Lissajous](Lissajous/Sketch.swift) | the Lissajous table: a grid of `lissajous(a:b:)` figures, column against row frequency, a shared phase rolling every figure through its family while tracers ride at true parametric speed |
| [Linkage](Linkage/Sketch.swift) | `drawOrientedBox` bars connecting two counter-rotating rings of points — each bar's length and angle change as both endpoints drift (SDF) |
| [Mandala](Mandala/Sketch.swift) | nested, counter-rotating `hollow` shapes — each a framed band in one call — sliding into a moiré (`hollow`, SDF) |
| [Morphing](Morphing/Sketch.swift) | shape morphing: a star tweened into a blob, the blob into a donut, every in-between a real vector `Shape` (`ShapeMorph`, `morphed(toward:)`) |
| [Myriad](Myriad/Sketch.swift) | 8,100 noise-driven circles on the SDF path — thousands of shapes at full speed |
| [NBody](NBody/Sketch.swift) | two toy galaxies (`NBody.disk`) on a bound grazing orbit: tides peel streamer arms off both disks, then the survivors fall back to merge |
| [Orbits](Orbits/Sketch.swift) | ten circles orbiting the center at rising speeds |
| [PerfectLoop](PerfectLoop/Sketch.swift) | a sketch that repeats exactly: `loopDuration` declares the period, looping noise closes the motion, and `--export-loop` renders one seamless lap |
| [Petals](Petals/Sketch.swift) | `drawOrientedVesica` lenses spanning two counter-rotating rings — petals whose tips drift and waists breathe (SDF) |
| [Polygons](Polygons/Sketch.swift) | regular `drawNgon` (3–8 sides) and a five-point `drawStar` relaxing from spiky to round as its inner radius grows, both turning (SDF) |
| [RectField](RectField/Sketch.swift) | Myriad's cousin: thousands of rounded rects, corner radius sweeping square→pill, each rotated on the SDF box path |
| [SineSweep](SineSweep/Sketch.swift) | a circle swept across the canvas by `sin(time)` |
| [Smoothing](Smoothing/Sketch.swift) | `@Smoothed` cleans a jittery figure-eight signal with the 1€ filter — faint raw dots, a smooth tracking trail |
| [Spokes](Spokes/Sketch.swift) | a sunburst of fat, round-capped `drawLine` spokes pulsing with `time` (capsule SDF) |
| [Springs](Springs/Sketch.swift) | the spring family portrait: five dots race the same hop on different `bounce` settings, and a `@Sprung` chaser follows the mouse with momentum (click to kick) |
| [Star](Star/Sketch.swift) | a concave star with a hole, filled via `drawShape` and the vector `Shape` type (a triangulated fill `drawPolygon` can't do) |
| [Steering](Steering/Sketch.swift) | steering creatures (`Vehicle`): a troop follows a wavy loop with personal space, wanderers roam leaving trails, and a pursuer intercepts the lead follower |
| [Timeline](Timeline/Sketch.swift) | a `Timeline<Vector2>` walks a dot around a square, one easing per side with a hold at each corner, while a second timeline breathes its size; `progress` tracked below, a tick per keyframe |
| [Trail](Trail/Sketch.swift) | a Lissajous point traced by a 600-segment polyline |
| [Triangles](Triangles/Sketch.swift) | the two `drawTriangle` forms side by side — equilateral pivoting on its center, isosceles wedge pivoting on its apex (SDF) |

Run one with `swift run Example-Motion-<Name>`, e.g. `swift run Example-Motion-Breathing`.
