#### <sup>[Ollin](../README.md) → [Guide](README.md) → Appendix B</sup>

---

# B. Just enough math, visually

This appendix isn't assembled yet; it gets written once several chapters exist, so it can match what the guide actually uses. When it's done, every math idea in the Guide will have one page here with a picture, as the safety net for any page that loses you.

<!-- Running list of ideas to cover, added by each chapter's writing session:
- The canvas coordinate system, y-down (Ch 1) - reuse Images/01-HelloOllin/CoordinateSystem.jpg
- sin as a smooth swing between -1 and 1, and its period (Ch 1)
- tau, the angle of one full turn (Ch 1)
- cos/sin turn an angle + radius into a point on a circle (Ch 1) - reuse Images/01-HelloOllin/AroundACircle.jpg
- The % remainder as "wrap around" / cycling (Ch 1)
- t in 0...1 as "how far along" (Ch 2, mixing and ramps; becomes lerp in Ch 3)
- The squeeze: sin(x) * 0.5 + 0.5 maps -1...1 into 0...1 (Ch 2; becomes map in Ch 3)
- Perceptual vs numeric color distance, why RGB midpoints go muddy (Ch 2) - reuse Images/02-Color/MixingSpaces.jpg
- Sine as the height of a point walking a circle; cosine as its across (Ch 3) - reuse Images/03-MotionAndTime/CircleToSine.jpg
- Period (one full turn = one cycle; time * tau / period) and amplitude (the swing = the radius) (Ch 3)
- Phase as a head start inside sin; phase from position makes a wave in space (Ch 3) - reuse Images/03-MotionAndTime/Phase.jpg
- map carries a value between ranges by keeping its fraction along; lerp walks a to b by t (Ch 3) - reuse Images/03-MotionAndTime/MapAndLerp.jpg
- Wrapping time into looping 0...1 progress (loopProgress; fract underneath), and the out-and-back fold (pingPong) (Ch 3)
- Reading a shaping curve: input along the bottom, reshaped output up; spacing = speed (Ch 3) - reuse Images/03-MotionAndTime/ShapingCurves.jpg
- step as an if; smoothstep as the gentle S between two edges (t * t * (3 - 2 * t)), edges as a soft window (Ch 3)
- Frame-rate independence: derive from time, or scale steps by deltaTime (Ch 3) - reuse Images/03-MotionAndTime/DeltaTime.jpg
- The perfect loop: every time term completes whole cycles in the loop length (Ch 3)
- Pseudo-randomness: a deterministic scramble; the seed picks where the sequence starts (Ch 4)
- Probability as a threshold on a uniform 0...1 roll (random() < p passes p of the time); stacked thresholds = weighted choice (Ch 4) - reuse Images/04-Randomness/Choices.jpg
- Uniform vs Gaussian distributions: flat spread vs bell pile; mean = center, deviation = spread, ~2/3 within one deviation (Ch 4) - reuse Images/04-Randomness/UniformVsGaussian.jpg
- Chance is lumpy: independent rolls clump and drought, they don't space evenly (Ch 4)
- The random walk: accumulate nudges instead of re-rolling, and a path appears (Ch 4) - reuse Images/04-Randomness/WalkVsJumps.jpg
- Coherence: noise is a lookup into a fixed smooth landscape, so nearby inputs give nearby outputs (Ch 5) - reuse Images/05-Noise/RandomVsNoise.jpg
- The input multiplier as a zoom knob: how far apart the questions land (Ch 5) - reuse Images/05-Noise/NoiseZoom.jpg
- A field: an answer at every point of a plane; a third input as drifting time (Ch 5) - reuse Images/05-Noise/NoiseTerrain.jpg
- Decorrelation by offset: far-apart rows of one field are independent signals (Ch 5)
- Layering scales: weighted sum of a big shape and a small detail, weights summing to 1 (Ch 5) - reuse Images/05-Noise/NoiseLayers.jpg
- Looping a drift: tour a closed circle through the field instead of a straight line, and the lap ends where it began (the loop: parameter) (Ch 5)
- Transforms move the paper, not the shape: translate slides the origin, rotate turns around it, scale stretches; later calls ride earlier ones (Ch 6) - reuse Images/06-GridsAndRepetition/TransformSteps.jpg
- Drawing around the origin: coordinates straddling (0, 0) so a translated, rotated mark pivots about its own center (Ch 6)
- Rotational symmetry as repetition: n copies at tau/n apart close the circle exactly (Ch 6) - reuse Images/06-GridsAndRepetition/Rosette.jpg
- Local rules, global order: parts that only agree at their edges still compose global figures (Ch 6) - reuse Images/06-GridsAndRepetition/TruchetJoins.jpg
- Perceived brightness: the eye weighs the channels unequally (r 0.2126, g 0.7152, b 0.0722); averaging reads wrong (Ch 7) - reuse Images/07-WordsAndPictures/PixelSampling.jpg
- Fraction mapping: a cell's u,v fraction across one grid picks the matching index in another (sampling an image at any resolution) (Ch 7)
- Contrast shaping: squaring a 0...1 value pushes the middle down, keeps the ends (Ch 7)
- A vector's two readings: a point (a place) and an arrow (a way to move) (Ch 8)
- Arrow arithmetic: add head-to-tail; target - pos is the arrow from here to there; a scalar stretches or flips (Ch 8) - reuse Images/08-Vectors/VectorArithmetic.jpg
- Length (Pythagoras) and normalize (heading kept, length 1); limited caps length (Ch 8)
- The trio: acceleration changes velocity, velocity changes position, never the other way (Ch 8) - reuse Images/08-Vectors/MotionTrio.jpg
- Steering as correction: desired velocity minus actual velocity, capped (Ch 8)
- Edges: wrap (leave one side, enter the other) vs bounce (flip one velocity component, keep less than all of it) (Ch 8)
- A force is a push with a direction; forces on one body add tip to tail; acceleration = force / mass (Ch 9) - reuse Images/09-ForcesAndPhysics/ForceAccumulation.jpg
- Gravity's pull scales with mass, so after the division everything falls alike; drag doesn't, so light things feel it more (why a feather drifts) (Ch 9)
- A spring's rule: too long pulls in, too short pushes out, at rest length nothing; stiffness is how sharply it corrects (Ch 9) - reuse Images/09-ForcesAndPhysics/SpringRestLength.jpg
- Verlet integration: remember the previous position instead of a velocity; the gap between then and now is the velocity (Ch 9)
-->
