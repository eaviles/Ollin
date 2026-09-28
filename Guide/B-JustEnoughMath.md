#### <sup>[Ollin](../README.md) → [Guide](README.md) → Appendix B</sup>

---

# B. Just enough math, visually

Every math idea in the guide, re-explained on one page each. Each entry is a picture, the intuition in plain words, and a pointer to the chapter that puts it to work. This is the safety net behind the guide's first promise. If a page anywhere loses you, the missing piece is here.

The entries are grouped by theme rather than by chapter, so related ideas sit together. Read it straight through if you like, and it's a decent tour of the field's math on its own. But it's built for dipping. Come with one confusion, leave with one picture.

**Contents:** [Where things are](#where-things-are) · [Angles and circles](#angles-and-circles) · [Fractions, mapping, and wrapping](#fractions-mapping-and-wrapping) · [Shaping a value](#shaping-a-value) · [Randomness](#randomness) · [Noise](#noise) · [Moving the paper](#moving-the-paper) · [Vectors, motion, and forces](#vectors-motion-and-forces) · [Fields and following them](#fields-and-following-them) · [Local rules, global structure](#local-rules-global-structure) · [Iteration: a rule applied again](#iteration-a-rule-applied-again) · [Shapes as regions](#shapes-as-regions) · [Color and light as numbers](#color-and-light-as-numbers) · [Per-pixel thinking and distance](#per-pixel-thinking-and-distance) · [Into three dimensions](#into-three-dimensions) · [Sound as numbers](#sound-as-numbers)

## Where things are

### The canvas: x right, y down

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/CoordinateSystem-dark.jpg">
  <img src="Images/01-HelloOllin/CoordinateSystem.jpg" alt="The canvas coordinate system: origin at the top left, x growing right, y growing down, with one point marked" width="680">
</picture>

Every position on the canvas is two numbers, counted in pixels from the top-left corner. Here x grows to the right, and y grows *downward*. That last part is the one to internalize, because it's upside down from school graphs. To move something toward the bottom of the screen you *add* to y. The convention comes from how screens have been addressed since text terminals, and [Chapter 1](01-HelloOllin.md) starts here.

### Normalized coordinates: 0…1 anywhere

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/18-YourFirstShader/UVSpace-dark.jpg">
  <img src="Images/18-YourFirstShader/UVSpace.jpg" alt="The uv gradient annotated: (0,0) at the top left, (1,1) at the bottom right, the center marked (0.5, 0.5)" width="680">
</picture>

Instead of pixels, an address can be a *fraction* of the whole, 0 at one edge and 1 at the other. So (0.5, 0.5) is the center of anything, at any resolution. Shaders live entirely in these `uv` coordinates, which is where [Chapter 18](18-YourFirstShader.md) works. Subtracting 0.5 re-centers them, so distances measure from the middle. The same trick names positions inside a camera image regardless of its size ([Chapter 32](32-Seeing.md)).

### Putting a normalized point onto the canvas

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Seeing/TrackerFlow-dark.jpg">
  <img src="Images/32-Seeing/TrackerFlow.jpg" alt="A diagram of camera frames flowing through a tracker, and a normalized lower-left-origin point mapping into the drawn frame's rectangle" width="680">
</picture>

A fraction-of-the-image point becomes a canvas point by scaling it into the rectangle you drew the image in. There's one wrinkle. Vision results count y *up* from the bottom-left, while the canvas counts y *down* from the top-left. So the y fraction flips on the way (`1 - y`). [Chapter 32](32-Seeing.md) wraps the flip-and-scale into one call, but this is all that call does.

### The 3D world frame

<img src="Images/B-JustEnoughMath/WorldFrame.jpg" alt="Two labeled frames: the canvas with y growing down from a top-left origin, and the 3D world with y growing up and z coming toward the viewer" width="680">

The 3D world uses its own frame. The origin sits wherever you like, x still grows right, y grows *up*, and z comes toward you. Positions are in world units rather than pixels. A sphere of radius 1 is one unit, and the camera's distance decides how big it looks. The canvas's y-down is the odd one out, a 2D screen habit, while 3D follows the mathematician's y-up. [Chapter 25](25-3DGently.md) makes the switch. Depth data in meters lands in the same kind of frame in [Chapter 33](33-DepthAndThePhone.md).

## Angles and circles

### Radians and tau

<img src="Images/B-JustEnoughMath/TauClock.jpg" alt="A dial with 0, tau over 4, tau over 2, and 3 tau over 4 marked around it, an accent wedge of tau over 8, and three mini dials showing tau over 12, 6, and 3" width="680">

Angles here are radians, and the friendly way in is `.tau`, the angle of one full turn (about 6.283, twice pi). Fractions of tau read as fractions of a turn: `.tau / 4` is a quarter turn, `.tau / 12` a clock hour. Because the canvas's y points down, angles sweep *clockwise* on screen, starting from 3 o'clock. Thinking in turns spares you both degrees and memorized decimals, and [Chapter 1](01-HelloOllin.md) adopts it immediately.

### An angle and a radius make a point

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/AroundACircle-dark.jpg">
  <img src="Images/01-HelloOllin/AroundACircle.jpg" alt="A circle with an angle marked at its center, and cos and sin placing a point on its rim" width="680">
</picture>

To stand on a circle's rim, you need how far around (an angle) and how far out (a radius). `cos(angle) * radius` gives the across part, `sin(angle) * radius` the down part, and adding them to the center lands the point. This one pattern places petals, clock hands, orbiting moons, and everything else arranged in a ring. It first appears in [Chapter 1](01-HelloOllin.md) and never really leaves.

Once the pattern is yours, it is also one call. `polar(angle, radius, around: center)` lands the same point, and `angles(12)` hands you twelve evenly spaced angles to stand things on. A whole ring becomes a `for` loop with no index arithmetic. This appendix keeps spelling the trig out so you can see it work.

### The angle of an arrow: `atan2`

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../Docs/Images/VectorHeading-dark.jpg">
  <img src="../Docs/Images/VectorHeading.jpg" alt="Three panels in screen space with y down: the vector (3, 4) as the long side of its 3-4-5 right triangle, the angle measured from the positive x-axis and growing clockwise, and a quarter turn taking (3, 0) to (0, 3)" width="680">
</picture>

The entry above goes from an angle to a point. `atan2(y, x)` goes back, from a point to its angle. Given the two parts of an arrow, it answers the angle the arrow points at, measured from the positive x-axis, between `-.pi` and `.pi`. It takes y first. It needs both parts, because an arrow and its opposite have the same ratio of y to x. (1, 1) and (-1, -1) are one example. A vector's `angle` is this call. [Chapter 10](10-Vectors.md) turns a shape to face where it moves with it, and [Chapter 17](17-MarksAndMedia.md) reads the lean of a pen.

### Sine: a smooth swing

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/03-MotionAndTime/CircleToSine-dark.jpg">
  <img src="Images/03-MotionAndTime/CircleToSine.jpg" alt="A point on a circle, with a dashed line carrying its height onto a sine wave traced over time, the period and swing labeled" width="680">
</picture>

`sin` is the height of a point walking around a circle, which is why it swings smoothly between -1 and 1 forever. Its **period** is how long one lap takes, so writing `sin(time * .tau / period)` completes one cycle every `period` seconds. Its **amplitude** is the swing's size, just the circle's radius, set by whatever you multiply the result by. [Chapter 3](03-MotionAndTime.md) builds most of its motion from these two dials, with `cos` as the same walk read as "across" instead of "up".

### Phase: a head start

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/03-MotionAndTime/Phase-dark.jpg">
  <img src="Images/03-MotionAndTime/Phase.jpg" alt="Two identical sine waves, one shifted right by a bracketed phase; below, a row of dots each with a growing head start forming a wave in space" width="680">
</picture>

Adding a constant inside `sin(...)` starts the swing partway through its cycle, a head start, called phase. Give each element a *different* head start, usually derived from its position (`sin(time + x * 0.02)`), and identical motions turn into a traveling wave across space. It's the cheapest large effect in [Chapter 3](03-MotionAndTime.md).

### n copies close the circle

<img src="Images/06-GridsAndRepetition/Rosette.jpg" alt="A twelve-fold rosette: one branching arm repeated by rotation into a botanical snowflake" width="560">

Rotational symmetry is repetition around a point: draw one arm, rotate by `.tau / n`, draw again, n times. Because n equal steps of `tau / n` add up to exactly one full turn, the last copy lands flush against the first with no seam. [Chapter 6](06-GridsAndRepetition.md) builds rosettes and mandalas this way from a single drawing.

### An angle that never closes: the golden angle

<!-- Figure waiting on a render: Figures/B-JustEnoughMath/GoldenAngle.swift (themed). When its image lands, embed it here as a picture tag at width 680, with its dark sibling as the source. -->

Turning by a simple fraction of a turn brings you back to the start after a few steps, which is what closes the rosette above. Sometimes you want the opposite: many things placed around a center, none of them behind another. The golden angle, about 137.5 degrees or 0.382 of a turn, does that. It is the angle that fractions of whole numbers match most poorly, so no step ever lands close behind an earlier one. A sunflower's seeds grow this way. [Chapter 16](16-CurvesAndFigures.md) turns each seed by the golden angle and pushes it out by the square root of its number. [Chapter 27](27-Landscapes.md) spreads its lamps the same way.

### Numbers that turn: complex multiplication

<!-- Figure waiting on a render: Figures/B-JustEnoughMath/MultiplyingTurns.swift (themed). When its image lands, embed it here as a picture tag at width 680, with its dark sibling as the source. -->

A point `(x, y)` can also be read as one number, written `x + y·i`, where `i` is a number whose square is -1. Read that way, the plane is the **complex plane**, and its use here is multiplication. Multiplying two of these numbers multiplies their lengths and adds their angles. So multiplying by `i`, which has length 1 and points a quarter turn around, turns anything a quarter turn. Two quarter turns make half a turn, which is why `i` times `i` is -1. Squaring a point doubles its angle and squares its length. [Chapter 22](22-IteratedForms.md#multiplying-turns-the-complex-plane) builds escape-time fractals and domain coloring on this.

### Circles on circles: Fourier

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/16-CurvesAndFigures/EpicycleTerms-dark.jpg">
  <img src="Images/16-CurvesAndFigures/EpicycleTerms.jpg" alt="Three panels rebuilding the letter g from spinning circles: with three circles it is a wobbly loop, with twelve it is recognizably the letter, and with sixty-four it is exact, with the faint construction circles visible in each" width="680">
</picture>

A closed outline can be rebuilt from circles. Each circle turns a whole number of laps while riding on the tip of the one before it, and the last tip traces the shape. A few large, slow circles give the rough form, and more small, fast ones add the detail. This is Joseph Fourier's idea from the 1820s: a repeating shape is a sum of plain waves. [Chapter 16](16-CurvesAndFigures.md) draws with the circles, and [Chapter 21](21-PicturesYouSolve.md) reads a whole picture as waves. [Chapter 31](31-TracedLight.md) finds it in the star around a bright light in a lens. A sound splits the same way, as [the spectrum](#the-spectrum) shows.

## Fractions, mapping, and wrapping

### t, the fraction along: lerp and map

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/03-MotionAndTime/MapAndLerp-dark.jpg">
  <img src="Images/03-MotionAndTime/MapAndLerp.jpg" alt="Top: a value carried between two number lines by its fraction along. Bottom: dots walking a segment from a to b as t runs 0 to 1" width="680">
</picture>

A value between 0 and 1 can mean "how far along". It reads 0 at the start, 1 at the end, and 0.25 a quarter of the way. `lerp(a, b, t)` walks from `a` to `b` by that fraction. `map(v, inLo, inHi, outLo, outHi)` carries a value from one range to another by *keeping* its fraction along. So 75% into the input range comes out 75% into the output range. The same idea squeezes sine's -1…1 into 0…1 (`sin(x) * 0.5 + 0.5`). [Chapter 2](02-Color.md) mixes colors by `t`, and [Chapter 3](03-MotionAndTime.md) makes both calls everyday tools.

### Three fractions at once: barycentric coordinates

<!-- Figure waiting on a render: Figures/B-JustEnoughMath/Barycentric.swift (themed). When its image lands, embed it here as a picture tag at width 680, with its dark sibling as the source. -->

`lerp` names a point between two ends with one fraction. A point inside a triangle takes three, one for each corner, and the three add up to 1. The point is that much of each corner mixed together. The weights 0.5, 0.3, and 0.2 name a point closest to the first corner. Each weight is also a share of area. Lines from the point to the corners cut the triangle into three, and a corner's weight is the share of the piece opposite it. The same weights mix anything the corners carry, such as a color or a height. [Chapter 27](27-Landscapes.md) reads them off a point scattered over a mesh, to blend what the mesh stores at its corners.

### Wrapping: remainder, fract, and pingPong

<img src="Images/B-JustEnoughMath/Wrap.jpg" alt="Three strips over one time axis: raw time rising forever, loopProgress wrapping 0 to 1 every lap, and pingPong folding each lap out and back" width="680">

A clock that only grows becomes a cycle by wrapping. The `%` remainder wraps whole numbers (`i % 4` cycles 0, 1, 2, 3), and `fract` keeps just the fraction of a decimal, wrapping it into 0…1. `loopProgress(over: 3)` is that wrap applied to the sketch clock, "how far through the current 3-second lap". `pingPong` folds each lap, so the trip goes out and back instead of snapping home. [Chapter 1](01-HelloOllin.md) meets `%`, and [Chapter 3](03-MotionAndTime.md) supplies the two helpers.

### What two counts share: the greatest common divisor

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/07-Tiles/KolamLoops-dark.jpg">
  <img src="Images/07-Tiles/KolamLoops.jpg" alt="Three dark panels of chalk-colored looping line work around small dots. One continuous line over a field of seven by five dots; two interleaved loops in cream and orange over six by four; and the same seven by five field cut into three loops by two short walls" width="680">
</picture>

The greatest common divisor of two whole numbers is the largest number that divides both. For 6 and 4 it is 2, and for 7 and 5 it is 1. It decides how two repeating things line up. [Chapter 7](07-Tiles.md)'s kolam draws one unbroken line around a field of seven by five dots. Around six by four it draws two separate loops, as the first two panels show. The number of loops is the divisor the two sides share. Euclid's method finds it by taking remainders again and again, and [Chapter 37](37-MusicByRule.md)'s Euclidean rhythms spread their hits by the same steps.

### The perfect loop

<img src="Images/03-MotionAndTime/RingPulse.gif" alt="Waves of light chasing around concentric rings of colored dots, looping seamlessly" width="480">

An animation loops invisibly when every time-driven term completes *whole* cycles in the loop length. A 4-second loop can hold sine waves with periods of 4, 2, or 1 second, but a period of 3 pops at the seam. The same thinking loops randomness: `noise(x, loop: t)` tours a closed circle through the noise field, so one lap ends exactly where it began ([Chapter 5](05-Noise.md)). [Chapter 3](03-MotionAndTime.md) states the rule, and exported GIFs live and die by it.

### Sampling one grid with another

<img src="Images/09-Pictures/TypeMosaic.jpg" alt="A portrait built entirely from one word repeated in a grid, colored and sized by the image beneath" width="560">

To read an image at any grid's resolution, use fractions as the go-between. A cell 30% across and 60% down the grid reads the pixel 30% across and 60% down the image. Nothing needs to match in size, because the fractions do the translation. This is how [Chapter 9](09-Pictures.md) rebuilds a photo as a mosaic of letters, and it's the same idea as normalized coordinates wearing work clothes.

## Shaping a value

### Reading a shaping curve

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/03-MotionAndTime/ShapingCurves-dark.jpg">
  <img src="Images/03-MotionAndTime/ShapingCurves.jpg" alt="Three panels showing linear, step, and smoothstep as curves over a faint identity diagonal, each with a strip of dots spaced by the curve" width="680">
</picture>

A shaping function takes a 0…1 value and hands back a reshaped 0…1 value. Its graph shows input along the bottom and output up the side, and the straight diagonal means "unchanged". Where the curve is steep, the value moves fast. Where it's flat, the value lingers, which is why the dot strips under each curve bunch and spread. `step` is an if in curve form, 0 then 1 at an edge. `smoothstep` is the gentle S between two edges, with `t * t * (3 - 2 * t)` inside. Squaring a 0…1 value is a shaping curve too, since it pushes the middle down and keeps the ends. That's [Chapter 9](09-Pictures.md)'s one-line contrast boost. The whole toolkit lives in [Chapter 3](03-MotionAndTime.md).

### Exponential decay

<img src="Images/19-LayersAndEffects/Comets.jpg" alt="Comet swarms of glowing dots, each dragging a soft luminous tail that fades with age" width="560">

Multiply a value by a little less than 1 every frame, keeping 93% say, and it melts away smoothly. It falls fast at first, ever slower, and never quite reaches zero. That's exponential decay, and it's the shape of every fading trail. The newest mark is full strength, and each older one has been multiplied down one more time. [Chapter 19](19-LayersAndEffects.md) uses it as the feedback fade behind these comet tails. [Chapter 34](34-Listening.md) fades a pulse the same way, scaled by `deltaTime` so it falls at the same speed at any frame rate.

## Randomness

### Pseudo-random: a scramble you can replay

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/04-Randomness/SeedSheet-dark.jpg">
  <img src="Images/04-Randomness/SeedSheet.jpg" alt="Nine tiles of dot constellations labeled seed 1 through seed 9, every tile a distinctly different arrangement" width="560">
</picture>

`random()` isn't dice. It's a deterministic scramble that plays out the same sequence from a chosen starting point, the **seed**. Same seed, same "random" piece, every run, which is what makes generative work reproducible: a seed is a piece's serial number. Change the seed and you get a sibling, not a variation. [Chapter 4](04-Randomness.md) builds the whole workflow on this.

### Probability as a threshold

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/04-Randomness/Choices-dark.jpg">
  <img src="Images/04-Randomness/Choices.jpg" alt="Strips of dots showing probability gates at 0.25 and 0.75, a uniform four-color pick, and a pick dominated by one weighted color" width="680">
</picture>

`random() < 0.25` is true a quarter of the time, because a uniform 0…1 roll passes a threshold exactly as often as the threshold is high. Stack several thresholds and you've built a weighted choice, common outcomes owning wide slices of the 0…1 line and rare ones thin slivers. [Chapter 4](04-Randomness.md) turns this into scattered accents and weighted palettes.

### Uniform vs Gaussian

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/04-Randomness/UniformVsGaussian-dark.jpg">
  <img src="Images/04-Randomness/UniformVsGaussian.jpg" alt="Two scatter panels with histograms beneath: uniform spreads dots evenly with a flat histogram, Gaussian piles them around the center in a bell" width="680">
</picture>

`random(a, b)` spreads values evenly, every part of the range equally likely, which makes a flat histogram. `randomGaussian()` piles them around a center in a bell. The **mean** is where the pile sits, and the **deviation** is how wide it spreads. About two thirds of values land within one deviation of the mean. Uniform reads as "scattered", Gaussian as "clustered, with strays", and [Chapter 4](04-Randomness.md) shows when each texture is the right one.

### Rare but huge: a heavy tail

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/04-Randomness/WalkFamily-dark.jpg">
  <img src="Images/04-Randomness/WalkFamily.jpg" alt="Three panels from the same seed: a dense tangle pooling in one area, a set of tight clusters joined by long straight leaps, and an orange path on a grid that fills the square without ever crossing itself" width="680">
</picture>

The **tail** of a distribution is its far end, the values that almost never come up. A Gaussian's tail thins fast, so a value three deviations from the mean is rare. A **heavy tail** thins slowly. Most draws stay small, and now and then one is enormous. [Chapter 4](04-Randomness.md)'s Lévy flight takes its step lengths from a heavy tail. That is why the middle walk here moves in tight clusters and then leaps far.

### Even over a disk: the square root

<!-- Figure waiting on a render: Figures/B-JustEnoughMath/SquareRootSpread.swift (themed). When its image lands, embed it here as a picture tag at width 680, with its dark sibling as the source. -->

To scatter points in a disk, pick an angle and a distance from the center. The obvious distance, `random(1)` times the radius, crowds the points toward the middle. Half of them land within half the radius, but that inner circle holds only a quarter of the disk's area. The square root fixes it. With `sqrt(random(1))` as the fraction, a quarter of the points land within half the radius, which matches the area. [Chapter 27](27-Landscapes.md) places its trees this way. [Chapter 16](16-CurvesAndFigures.md)'s sunflower spreads its seeds by the square root of their number for the same reason.

### Chance is lumpy

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/04-Randomness/ScatterCompare-dark.jpg">
  <img src="Images/04-Randomness/ScatterCompare.jpg" alt="Two panels with the same number of dots: plain random placement with clumps and bare gaps, and a blue-noise scatter, even but organic" width="680">
</picture>

Independent random placements clump and leave holes, and they do not space themselves out, because each roll ignores every other. The clumps aren't a bug in the generator, they're what independence looks like. When you want "random but even", you need an algorithm that pushes points apart, like the blue-noise scatter on the right. [Chapter 4](04-Randomness.md) names the lump problem, and [Chapter 15](15-ShapesAsMaterial.md) fixes it.

### The random walk

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/04-Randomness/WalkVsJumps-dark.jpg">
  <img src="Images/04-Randomness/WalkVsJumps.jpg" alt="Two strips: fresh rolls per step produce a jagged hash, accumulated nudges produce a wandering path" width="680">
</picture>

Re-roll a position every frame and you get noise with no memory, a jagged hash. *Accumulate* small random nudges instead (`x += random(-2, 2)`) and a path appears, because each position remembers all the nudges before it. That one change, re-rolling versus accumulating, separates static from wandering, and it's the first living thing [Chapter 4](04-Randomness.md) makes.

## Noise

### Coherence: a fixed, smooth landscape

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/05-Noise/RandomVsNoise-dark.jpg">
  <img src="Images/05-Noise/RandomVsNoise.jpg" alt="Two framed strips: a jagged hash of random heights, and a smooth rolling curve from noise" width="680">
</picture>

`noise(x)` is not a roll. It's a *lookup* into a fixed, smooth landscape of values. Nearby inputs land on nearby outputs, so a sequence of close questions traces a rolling curve instead of a hash. That property, coherence, is the entire difference between noise and random, and everything [Chapter 5](05-Noise.md) builds rests on it.

### The input multiplier is a zoom control

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/05-Noise/NoiseZoom-dark.jpg">
  <img src="Images/05-Noise/NoiseZoom.jpg" alt="Three panels sampling the same noise field with multipliers 0.004, 0.015, and 0.06: one gentle valley, rolling hills, busy wiggles" width="680">
</picture>

`noise(x * scale)` doesn't change the landscape, it changes how far apart your questions land on it. A small multiplier asks about points close together and sees one broad feature, while a large one strides across many hills and sees busy detail. When noise output looks wrong, the first dial to reach for is almost always this one. [Chapter 5](05-Noise.md) calls it the zoom parameter.

### A field of answers, drifting in time

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/05-Noise/NoiseTerrain-dark.jpg">
  <img src="Images/05-Noise/NoiseTerrain.jpg" alt="The same noise field shaded as soft clouds and drawn as dot sizes, a halftone of the same values" width="680">
</picture>

Give noise two inputs and it answers everywhere on a plane. That's a **field**, one value per position, which you can render as brightness, dot size, or anything else. A third input works as time, sliding the whole landscape smoothly so the field churns without jumping. And because far-apart regions of the landscape don't resemble each other, offsetting your questions (`noise(t + 1000)` vs `noise(t)`) yields independent signals from one field. All of [Chapter 5](05-Noise.md) is variations on this.

### Layering scales

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/05-Noise/NoiseLayers-dark.jpg">
  <img src="Images/05-Noise/NoiseLayers.jpg" alt="Three strips: a slow big-scale curve labeled shape, a busy small-scale curve labeled detail, and their weighted sum" width="680">
</picture>

Natural forms have big shapes *and* fine texture. So take noise at both scales and add them, weighted mostly toward the broad curve and a little toward the busy one. Keep the weights summing to 1 and the result stays in range. Stack a few layers like that (each smaller and fainter) and you get the fractal texture `fbm` packages up. [Chapter 5](05-Noise.md) builds it by hand first, so the packaged call has no mystery in it.

### Distance to the nearest point makes cells

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/05-Noise/CellsFromPoints-dark.jpg">
  <img src="Images/05-Noise/CellsFromPoints.jpg" alt="Two panels of cellular noise: distances shaded so each hidden point sits in a dark core, and the border reading drawing dark walls between the cells" width="680">
</picture>

Scatter points across a plane, then ask everywhere how far the nearest one is. The answers are small beside each point and peak on the walls between two, so shading them divides the plane into cells, one per point. Asking instead how much *farther* the second-nearest point is gives a value that hits zero exactly on those walls, so the borders draw themselves. [Chapter 5](05-Noise.md) meets this as `worley`, the cellular member of the noise family.

## Moving the paper

### Transforms move the paper, not the shape

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/06-GridsAndRepetition/TransformSteps-dark.jpg">
  <img src="Images/06-GridsAndRepetition/TransformSteps.jpg" alt="Four panels drawing the same flag with the same call: untransformed, then translated, then rotated, then scaled" width="680">
</picture>

`translate`, `rotate`, and `scale` don't touch your shapes. They move the paper under the pen. Every draw call afterward lands in the moved frame, and later transforms ride on earlier ones (translate then rotate is not rotate then translate). The habit that makes this easy is to draw your motif *around the origin*, with coordinates straddling (0, 0). Then translate to where it goes and rotate. It pivots about its own center instead of swinging around a distant corner. [Chapter 6](06-GridsAndRepetition.md) turns this into the draw-one-thing-many-ways engine, with `withState { }` to undo the moves after each copy.

### Small moves compound

<img src="Images/25-3DGently/Stairs.jpg" alt="A spiral staircase of colored slabs winding up a dark central post" width="560">

Repeat "move a little, turn a little, draw" without resetting, and the little moves stack, because each copy starts where the last one ended. A straight repetition then curls into an arc, a spiral, or a helix if you lift by a step each time. Scoping is the control. Resets between copies give you a grid, and no resets give you a staircase. [Chapter 6](06-GridsAndRepetition.md) shows both in 2D, and [Chapter 25](25-3DGently.md) builds these stairs with the same loop.

### The plane turned inside out: inversion in a circle

<!-- Figure waiting on a render: Figures/B-JustEnoughMath/CircleInversion.swift (themed). When its image lands, embed it here as a picture tag at width 680, with its dark sibling as the source. -->

Inversion in a circle moves every point along the line from the circle's center through it. A point at distance d from the center lands at r² / d, where r is the circle's radius. Points on the circle stay where they are, points inside go outside, and points near the center go far away. Inverting twice brings every point back, so the circle works like a mirror. A circle comes out as another circle, or as a straight line when it passes through the center. That is why [Chapter 22](22-IteratedForms.md#circles-used-as-mirrors-inversion-limit-sets)'s limit sets are made of round shapes.

### Four corners anywhere: corner pinning

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/41-Installations/FittingTheWall-dark.jpg">
  <img src="Images/41-Installations/FittingTheWall.jpg" alt="Left, a rectangle of grid lines landing on a wall as a tilted trapezoid, labeled as it lands. Right, the same grid sitting square inside the wall with a handle on each corner, labeled corner-pinned. Below, two colored blocks meeting in a shared band where each fades out, with a flat line across the top labeled added up, one coat" width="680">
</picture>

Translate, rotate, and scale keep a square a square. A projector aimed at a wall from an angle turns the picture's rectangle into a lopsided four-sided shape. Fixing that takes one more kind of move. A **projective map** sends the four corners of a square to any four points and carries everything between them along. Straight lines stay straight, but equal steps no longer stay equal, the way a road's stripes crowd together toward the horizon. [Chapter 41](41-Installations.md) fits a projector to a wall by dragging the four corners, and Paul Heckbert set out the math in 1989.

## Vectors, motion, and forces

### A vector is a point and an arrow

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/10-Vectors/VectorArithmetic-dark.jpg">
  <img src="Images/10-Vectors/VectorArithmetic.jpg" alt="Four panels: adding arrows head to tail, the arrow from a point to a target, an arrow scaled and flipped, and a long arrow with its unit-length version" width="680">
</picture>

A `Vector2` is two numbers with two readings. It's a *place*, meaning a position, or a *way to move*, meaning a direction with a length. The arithmetic is drawing. Adding chains arrows head to tail, and `target - position` is the arrow *from* here *to* there. Multiplying by a number stretches or shrinks the arrow, and a negative number flips it. An arrow's `length` comes from Pythagoras. `normalized` keeps its heading at length exactly 1, ready to be scaled to any speed you want. [Chapter 10](10-Vectors.md) is a gentle bootcamp in exactly this.

### The motion trio

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/10-Vectors/MotionTrio-dark.jpg">
  <img src="Images/10-Vectors/MotionTrio.jpg" alt="A dotted flight arc with three arrows at one moment: position from the origin, velocity along the path, acceleration pointing down" width="680">
</picture>

Motion is three vectors in a strict chain. **Acceleration** changes velocity, **velocity** changes position, and never the other way around. Each frame runs `velocity += acceleration` and then `position += velocity`. Steer a thing by pushing on its acceleration and letting the chain carry the push downstream. The lag between push and path is where the lifelike feel comes from. At the canvas's edges you choose a policy. *Wrap* sends a thing out one side and back in the other. *Bounce* flips the velocity component that hit, usually keeping less than all of it. The trio arrives in [Chapter 10](10-Vectors.md) and drives everything in Part II.

### Steering is a correction

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/10-Vectors/SteeringMove-dark.jpg">
  <img src="Images/10-Vectors/SteeringMove.jpg" alt="A dot with a velocity arrow and a desired arrow toward a target; beside it, the steer arrow connecting the velocity's tip to the desired's tip" width="680">
</picture>

A creature that can't teleport steers by comparing wish and state. Compute the velocity it *wants*, toward the target at full speed, then subtract the velocity it *has*. The difference is the correcting force, capped so the turn takes time. `desired - velocity`, nothing more. That one subtraction, re-aimed, becomes seek, flee, arrive, and wander in [Chapter 10](10-Vectors.md) and [Chapter 12](12-FlocksAndSwarms.md).

### Forces add; mass divides

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/11-ForcesAndPhysics/ForceAccumulation-dark.jpg">
  <img src="Images/11-ForcesAndPhysics/ForceAccumulation.jpg" alt="Three labeled arrows for gravity, wind, and drag pushing on one dot; beside it, the same arrows chained tip to tail with the total marked" width="680">
</picture>

A force is a push with a direction, and simultaneous pushes on one body simply add, tip to tail, into one total. What the body *does* with the total depends on its mass: `acceleration = force / mass`, so the same wind barely moves a boulder and flings a leaf. Real gravity is the special case that scales *with* mass, so after the division everything falls alike. Drag doesn't scale that way, which is why the feather drifts. [Chapter 11](11-ForcesAndPhysics.md) builds its confetti on exactly this asymmetry.

### Weaker with distance: the inverse square

<!-- Figure waiting on a render: Figures/B-JustEnoughMath/InverseSquare.swift (themed). When its image lands, embed it here as a picture tag at width 680, with its dark sibling as the source. -->

Light from a point spreads out as it travels. At twice the distance, the same light covers four times the area, so each part of it gets a quarter as much. At three times the distance, each part gets a ninth. That is the **inverse square**: the strength falls as one over the distance squared. Gravity follows the same rule, and it is how [Chapter 11](11-ForcesAndPhysics.md)'s `NBody` pulls its bodies together. [Chapter 27](27-Landscapes.md) says why its lamps use a gentler curve that ends.

### Floating: the weight of the water pushed aside

<img src="Images/28-WorldsWithWeight/Floating.jpg" alt="Four crates floating in a row on still blue water, each riding lower than the one before it, from a pale crate four fifths above the surface to a dark one with a fifth above it" width="560">

A body in water sinks until the water it pushes aside weighs as much as the body. That is Archimedes' principle. So a body half as dense as water floats with half of itself under the surface. One at 0.8 of the water's density floats low, with a fifth above. [Chapter 28](28-WorldsWithWeight.md) works each crate's waterline out from its density alone.

### The spring's rule

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/11-ForcesAndPhysics/SpringRestLength-dark.jpg">
  <img src="Images/11-ForcesAndPhysics/SpringRestLength.jpg" alt="A coil spring between two discs: at rest length, stretched with arrows pulling inward, and squeezed with arrows pushing outward" width="680">
</picture>

A spring has one opinion, its **rest length**. Longer than that and it pulls its ends together, shorter and it pushes them apart, and at rest length it says nothing at all. The correction grows with the error (twice as stretched, twice the pull), and **stiffness** scales how sharply it acts. Everything soft in [Chapter 11](11-ForcesAndPhysics.md), from blobs to bridges, is dots connected by this one rule.

### Damping: a swing that dies away

<!-- Figure waiting on a render: Figures/B-JustEnoughMath/Damping.swift (themed). When its image lands, embed it here as a picture tag at width 680, with its dark sibling as the source. -->

A spring on its own would swing forever. **Damping** is a force against the velocity, and it takes a little energy out of every swing. With a little damping the spring rings for a long time. With a lot, it creeps back without swinging at all. Between the two is the amount that settles soonest without passing the rest length. [Chapter 3](03-MotionAndTime.md)'s `@Sprung` sets this with `bounce`, and in [Chapter 11](11-ForcesAndPhysics.md) the world's built-in drag calms the springs.

### Verlet: motion without a velocity

<img src="Images/B-JustEnoughMath/Verlet.jpg" alt="Dots labeled previous and now, the step between them carried forward as a dashed arrow, then bent down by gravity to the next position" width="680">

Verlet integration stores no velocity at all. It remembers where the particle *was* last frame. The gap between then and now *is* the velocity, so each step replays that gap and bends it by the frame's forces. What that gives you is sturdiness under constraints. When a spring yanks a particle somewhere new, its implied velocity updates automatically, with no bookkeeping to contradict. It's the quiet engine under [Chapter 11](11-ForcesAndPhysics.md)'s soft bodies.

### One second is one second

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/03-MotionAndTime/DeltaTime-dark.jpg">
  <img src="Images/03-MotionAndTime/DeltaTime.jpg" alt="Three dotted strips comparing one second of motion: a fixed step at 60 fps, the same step at 120 fps reaching twice as far, and a deltaTime-scaled step landing in line" width="680">
</picture>

`draw()` runs once per screen refresh, and screens disagree. So a fixed "move 2 pixels per frame" travels twice as far per second at 120 Hz as at 60. There are two honest fixes. Derive positions from `time` directly, or scale each step by `deltaTime`, the seconds since the last frame, so per-frame steps become per-second speeds. Simulations sometimes choose the third road on purpose, a *fixed* step per tick. That trades frame-rate independence for exact repeatability, run for run. [Chapter 3](03-MotionAndTime.md) sets the rule, and [Chapter 12](12-FlocksAndSwarms.md) explains the trade.

## Fields and following them

### A field: a question answered everywhere

<img src="Images/14-FieldsAndFlow/Compass.jpg" alt="A grid of small needles whose directions change smoothly across the canvas, showing currents and swirls" width="560">

A field is a rule that answers a question at *every* point of the plane. "How bright here?" gives a number field, and noise is one. "Which way here?" gives a direction field. The field itself is invisible and continuous, and the needles in the picture are only samples of it on a grid. Once you hold that distinction, sampling versus the thing sampled, the rest lines up. The flow work in [Chapter 14](14-FieldsAndFlow.md) and the terrain in [Chapter 5](05-Noise.md) are the same idea with different questions.

### Following a field: ask, step, ask again

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/14-FieldsAndFlow/TraceSteps-dark.jpg">
  <img src="Images/14-FieldsAndFlow/TraceSteps.jpg" alt="Faint field needles with one walk traced through them: a start dot, then dots connected by arrows stepping along the flow" width="680">
</picture>

To trace a line through a direction field, ask the field which way at your position, take a small step that way, and repeat. That loop is Euler integration, and its one parameter is the step size. Big steps cut corners where the field bends, while small steps follow faithfully and cost more asks. Every streamline in [Chapter 14](14-FieldsAndFlow.md) is this loop running until it's told to stop.

### Optical flow: a measured field

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Seeing/FlowArrows-dark.jpg">
  <img src="Images/32-Seeing/FlowArrows.jpg" alt="A frame of a dancer, with arrows along both arms pointing opposite ways, a few on one leg and at one foot, and none on his chest" width="680">
</picture>

Every field so far was invented, while optical flow is *measured*. Comparing one camera frame with the next assigns each point an arrow, "which way did the picture move here". The result is a direction field you can trace, advect particles through, or paint with, exactly like a noise-built one. The camera becomes a field generator in [Chapter 32](32-Seeing.md).

## Local rules, global structure

### Neighborhoods: who counts as nearby

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/12-FlocksAndSwarms/RuleAlignment-dark.jpg">
  <img src="Images/12-FlocksAndSwarms/RuleAlignment.jpg" alt="One dark boid among gray neighbors inside a faint circle labeled what it can see, with an arrow showing the average heading it turns toward" width="680">
</picture>

Distributed systems need a definition of "nearby". That's a perception radius around each creature, inside which others count and outside which they don't exist. Every flocking rule in [Chapter 12](12-FlocksAndSwarms.md) is an average over that circle. The radius is a character dial, since small circles make jittery individualists and large ones make committees.

### Everyone against everyone: counting pairs

<!-- Figure waiting on a render: Figures/B-JustEnoughMath/EveryPair.swift (themed). When its image lands, embed it here as a picture tag at width 680, with its dark sibling as the source. -->

Asking every creature about every other one costs more than it seems. A group of n things has n × (n − 1) / 2 pairs, about half of n squared. So twice the things make about four times the pairs. Growth like this, with the square of the count, is called **quadratic**. With 300 boids each looking at the other 299, a frame makes about 90,000 looks. That is where [Chapter 12](12-FlocksAndSwarms.md) starts before it cuts the plane into cells and asks only the nearby ones.

### Emergence: local rules, large patterns

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/23-GridSimulations/LifeRules-dark.jpg">
  <img src="Images/23-GridSimulations/LifeRules.jpg" alt="Three three-by-three neighborhoods and their outcomes: lonely cells die, comfortable cells live on, empty cells with three neighbors are born" width="680">
</picture>

No cell in the Game of Life knows what the board looks like. Each one asks only its eight neighbors and follows three lines of rules, and gliders, blinkers, and all the rest emerge unbidden. The same principle runs gentler machinery. Truchet tiles in [Chapter 7](07-Tiles.md) agree only at their shared edges, yet loops and mazes appear. Boids in [Chapter 12](12-FlocksAndSwarms.md) know only their circle, yet the flock turns as one. Reaction-diffusion in [Chapter 23](23-GridSimulations.md) asks even less and builds coral. When a pattern looks globally planned, look for the local law first.

### Constraint propagation

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/07-Tiles/TilesAgree-dark.jpg">
  <img src="Images/07-Tiles/TilesAgree.jpg" alt="Enlarged pipe tiles with dots marking their edge sockets, beside a solved grid where every pipe meets a pipe" width="680">
</picture>

Wave Function Collapse solves a grid the way you solve sudoku. Every cell starts as "could be anything", and each placement rules options out of its neighbors, which rule options out of theirs. The solver always settles the most-constrained cell next (the one with fewest options left), because that's where a contradiction would surface soonest. One local law, "edges must match", propagated relentlessly, forces global coherence. [Chapter 7](07-Tiles.md#every-neighbor-must-agree-wave-function-collapse) solves a pipe network with it.

### A parameter space is a map

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/23-GridSimulations/FeedKillMap-dark.jpg">
  <img src="Images/23-GridSimulations/FeedKillMap.jpg" alt="A grid of reaction-diffusion dishes at different feed and kill settings: most quiet, a diagonal band growing spots, rings, mazes, and dividing dots" width="680">
</picture>

Two parameters span a plane, where every pair of settings is a point. A system's behaviors live in *regions*, spots here, mazes there, dead calm nearly everywhere. Rendering the map, one small run per grid cell, turns parameter-fiddling into geography. Interesting settings cluster along the borders between regions. [Chapter 23](23-GridSimulations.md) maps Gray-Scott's feed and kill this way.

## Iteration: a rule applied again

### Recursion: a rule applied to its own output

<img src="Images/13-GrowingThings/TreeByHand.jpg" alt="A bare fractal tree: one trunk splitting into two branches, each splitting again, nine levels deep" width="560">

A branch is a stick with two smaller branches on top, and each of *those* is a stick with two smaller branches on top. A function that calls itself expresses that directly. It needs two guardrails. Something must shrink on each call, the length here, and a floor must say when to stop, a depth counter. Since every level doubles the branches, n levels make 2ⁿ tips, which is why nine levels is already a canopy. [Chapter 13](13-GrowingThings.md) grows this tree in a dozen lines.

### Rewriting growth

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/13-GrowingThings/LSystemExpansion-dark.jpg">
  <img src="Images/13-GrowingThings/LSystemExpansion.jpg" alt="The same plant grammar drawn after one to four rounds of rewriting, growing from a bare stalk to a full fern, letter counts rising to 1551" width="680">
</picture>

An L-system grows a *sentence*, not a picture. Start from an axiom, replace every symbol by its rule, and repeat. The string lengthens exponentially. A turtle then walks the final string, reading symbols as "forward", "turn", "branch". The drawing gets richer only because the sentence got longer, and all the botany lives in the rewriting. [Chapter 13](13-GrowingThings.md) writes ferns and lichens this way.

### Iterated maps: orbits that pile up

<img src="Images/22-IteratedForms/Plates.jpg" alt="Four glowing density plates: folded translucent attractor forms like X-rays of smoke" width="560">

Take a formula, feed it a point, feed it its own answer, and keep going, and the visited points form an **orbit**. For most formulas the orbit shoots away or settles into a dot. For special ones it wanders forever inside a bounded shape, the **attractor**. Plotting a million faint visits reveals where it likes to be. The ghostly plates in [Chapter 22](22-IteratedForms.md) are nothing but visit counts made luminous.

### Escape time

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/22-IteratedForms/FractalPair-dark.jpg">
  <img src="Images/22-IteratedForms/FractalPair.jpg" alt="Three panels banded in blue, gold, and cream: the whole Mandelbrot set with a small red circle marking one point on its edge, the Julia set that same point produces, and a deep zoom into the Mandelbrot boundary" width="680">
</picture>

Iterate a formula at every pixel and ask one question. How many rounds until the value flies off past a bound? Points that never escape are painted the set's interior. Everywhere else the *count itself* becomes the color, so the smooth bands you see are equal-patience contours. The most famous images in mathematics are literally a loop counter, colorized. Which of the formula's two numbers you hold still decides which fractal you get. The marked point in the first panel is the one whose Julia set sits beside it. [Chapter 22](22-IteratedForms.md) shades both this way.

### Density as tone

<img src="Images/24-ParticleSimulations/MillionGrains.jpg" alt="The same particle system at ten thousand, a hundred thousand, and a million grains: sparse embers, a grainy dune, a smooth field of light" width="560">

Draw one faint dot and you see a dot. Draw a million and you see a *material*, because overlapping near-transparent marks add up to smooth tone exactly where they crowd. The count is the brush: each tenfold increase trades grain for cream. This is how attractor plates, sandpaintings, and [Chapter 24](24-ParticleSimulations.md)'s GPU grains all get their finish. It's also why they need so many particles.

## Shapes as regions

### Set operations on regions

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/15-ShapesAsMaterial/BooleanOps-dark.jpg">
  <img src="Images/15-ShapesAsMaterial/BooleanOps.jpg" alt="A circle and a star combined by union, intersection, subtracting, and symmetricDifference" width="680">
</picture>

Treat shapes as *regions of space* and logic applies to them. Union is "in either", the or. Intersection is "in both", the and. Subtraction is "in one but not the other", the and-not. Symmetric difference is "in exactly one", the xor. Four sentences about membership, drawn. [Chapter 15](15-ShapesAsMaterial.md) uses them to build forms no single primitive could draw.

### Offsets: growing and shrinking

<img src="Images/B-JustEnoughMath/Offsets.jpg" alt="A peanut-shaped region with grown outlines around it and shrunken outlines inside, the deepest inset split into two islands" width="680">

Offsetting moves a region's whole boundary by the same distance everywhere, so outward grows it and inward shrinks it. The interesting part is that insets aren't scaled-down copies. Narrow passages thin faster than broad ones, and a deep enough inset pinches the waist apart into islands. That behavior is honest geometry, since it marks where the shape is thin. [Chapter 15](15-ShapesAsMaterial.md) leans on it for insets, outlines, and plotter work.

### Convexity: the rubber band

<img src="Images/B-JustEnoughMath/Hull.jpg" alt="A scatter of points with the convex hull drawn around them, the points on the band marked as its corners" width="680">

A region is convex if the straight line between any two of its points stays inside it, with no dents. The convex hull of a scatter is the smallest convex region containing all of it. It's exactly the shape a rubber band takes when released around the points, and walking its boundary you turn in only one direction. [Chapter 15](15-ShapesAsMaterial.md) uses hulls to wrap scatters into clean silhouettes.

### Duality: two readings of one point set

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/15-ShapesAsMaterial/Duals-dark.jpg">
  <img src="Images/15-ShapesAsMaterial/Duals.jpg" alt="The same points shown twice: Voronoi cells partitioning the plane into territories, and the Delaunay triangulation joining natural neighbors" width="680">
</picture>

One set of points supports two structures. Each point's Voronoi cell is the territory closer to it than to anyone else. The Delaunay triangulation connects each point to its natural neighbors. They're duals, two answers to "who's near whom", since cells share an edge exactly when their points share a triangle edge. Mosaics want the territories, while networks and meshes want the neighbors. [Chapter 15](15-ShapesAsMaterial.md) builds with both.

## Color and light as numbers

### Numeric vs perceptual mixing

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/02-Color/MixingSpaces-dark.jpg">
  <img src="Images/02-Color/MixingSpaces.jpg" alt="Three rows mixing the same blue and yellow: the RGB row passes through muddy olive, the HSB row detours through green, the OKLab row stays even" width="680">
</picture>

Averaging two colors channel by channel gives the numeric midpoint, and your eye often disagrees with it. RGB's halfway between blue and yellow is a muddy olive. Perceptual spaces like OKLab are laid out so that numeric distance matches *seen* distance, and midpoints in them look like what you'd mix. The lesson generalizes. Whenever math on colors looks wrong, ask which space the math ran in. [Chapter 2](02-Color.md) shows the three rows side by side.

### Perceived brightness

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/PixelSampling-dark.jpg">
  <img src="Images/09-Pictures/PixelSampling.jpg" alt="A photograph of a profile redrawn as a grid of dots, each dot taking its pixel's color and sized by its brightness" width="680">
</picture>

The eye doesn't weigh channels equally. Green counts most, red less, blue least, and the standard weights are 0.2126, 0.7152, 0.0722. Averaging r, g, and b calls a saturated blue as bright as a green, and it visibly isn't. The weighted sum, luminance, matches what you see. Any effect driven by "how bright is this pixel", like the dot sizes here, needs the weighted version. [Chapter 9](09-Pictures.md) meets this the first time it reads pixels.

### The stored number is not the light: linear light

<!-- Figure waiting on a render: Figures/B-JustEnoughMath/LinearLight.swift (themed). When its image lands, embed it here as a picture tag at width 680, with its dark sibling as the source. -->

A picture file doesn't store the amount of light in each pixel. It stores a number bent toward the dark end, so more of its steps go to dark tones, where the eye notices small changes most. That encoding is **sRGB**. The amount of light itself is called **linear light**, and it is what adds up and averages correctly. Half the light is stored as about 0.74, and a stored 0.5 is only about a fifth of the light. So Ollin mixes and blends in linear light, and turns the result back into stored numbers at the end. [Chapter 9](09-Pictures.md) averages pixels this way, and [Chapter 19](19-LayersAndEffects.md)'s blend modes add light the same way.

### What a device can show: gamut

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/ProofBeforePrint-dark.jpg">
  <img src="Images/38-FinishingASketch/ProofBeforePrint.jpg" alt="Three panels of one photograph of a woman before a wall of marigolds: as the screen shows it, the same picture proofed for a four-ink press with the orange gone duller, and the gamut check with most of the wall replaced by gray" width="680">
</picture>

The **gamut** of a screen, a printer, or a file format is the range of colors it can make. A screen makes color from light, and a press from ink on paper, so each reaches colors the other cannot. The standard gamut for screens is sRGB. Display P3, a wider gamut that many Apple screens show, reaches more saturated reds and greens. A color outside sRGB stores components slightly past 0 or 1. [Chapter 38](38-FinishingASketch.md)'s gamut check paints gray over what a press cannot print.

### Blend modes are arithmetic

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/19-LayersAndEffects/BlendModes-dark.jpg">
  <img src="Images/19-LayersAndEffects/BlendModes.jpg" alt="The same two discs composited with normal, add, subtract, multiply, screen, lightest, and darkest blend modes" width="680">
</picture>

Every blend mode is a small per-channel formula for combining the color being drawn with the color already there. Normal covers. Add sums, so light on light gets brighter. Multiply darkens like stacked filter gels, and screen brightens like layered projections. Lightest and darkest keep the winner. Once you read them as arithmetic, choosing one stops being trial and error. [Chapter 19](19-LayersAndEffects.md) puts the whole row to work.

### Light past 1, and bringing it back

<img src="Images/19-LayersAndEffects/ToneClamp.jpg" alt="Three overlapping tinted lamps under the clamp tone map: the overlapping middle blows out to a flat white slab" width="680">

<img src="Images/19-LayersAndEffects/ToneAces.jpg" alt="The same lamps through the ACES film curve: the middle stays bright but keeps its tints, rolling off softly" width="680">

Add enough light and channel values sail past 1, brighter than the screen can show. Something must bring them back. **Clamping** chops everything at 1, so overlapping glows flatten into white slabs with hard seams. A **roll-off curve** like film's compresses the highlights gradually, keeping their tints on the way up. Same scene, different return trip. [Chapter 19](19-LayersAndEffects.md) covers when each is right.

### Feeding a picture back to itself

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/19-LayersAndEffects/FeedbackSteps-dark.jpg">
  <img src="Images/19-LayersAndEffects/FeedbackSteps.jpg" alt="The same orbiting dot drawn into feedback with different transforms: fade leaves a tail, zoom smears a streak, rotate wraps a swirl, both coil a spiral" width="680">
</picture>

Draw this frame on top of a transformed copy of the *last* frame, and the transform applies again every frame, which is iteration. A gentle zoom becomes an ever-deepening tunnel, a small rotation a tightening swirl, because each frame inherits all the transforms before it. Tiny per-frame moves compound into large structure, the same way the staircase compounded, but in pixels. [Chapter 19](19-LayersAndEffects.md) builds video feedback from it.

## Per-pixel thinking and distance

### A function from position to color

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/18-YourFirstShader/PixelGrid-dark.jpg">
  <img src="Images/18-YourFirstShader/PixelGrid.jpg" alt="The same glow function evaluated coarsely, one answer per grid cell, and at full pixel resolution where the answers fuse into a smooth image" width="680">
</picture>

A shader is one function answering one question, "what color at this position?", asked independently at every pixel. There's no canvas to accumulate onto and no loop you can see. The image is only hundreds of thousands of simultaneous answers, fusing smoothly because the function varies smoothly. Evaluate it coarsely and you can watch the answers before they fuse. [Chapter 18](18-YourFirstShader.md) starts pixel thinking here.

### Signed distance: how far, and which side

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/30-SculptingWithFields/FieldMap-dark.jpg">
  <img src="Images/30-SculptingWithFields/FieldMap.jpg" alt="A distance field visualized: a melted shape in warm color surrounded by concentric bands of equal distance, with a bold line at zero" width="680">
</picture>

A signed distance field describes a shape by answering, at every point, "how far to the surface?". The *sign* says which side you're on. Negative is inside, positive is outside, and zero is exactly on the boundary. The shape stops being a list of vertices and becomes a question you can ask anywhere. That's what makes the sculpting in [Chapter 30](30-SculptingWithFields.md) possible.

### Level sets: an edge at a chosen distance

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/18-YourFirstShader/EdgeStep-dark.jpg">
  <img src="Images/18-YourFirstShader/EdgeStep.jpg" alt="The same disc three times: a hard stepped edge, a clean rim from a narrow smoothstep, and a wide soft glow from a broad one" width="680">
</picture>

Given a distance field, a shape is "all points within r". The edge lives where the distance crosses that level, like one contour line on a topographic map. Testing the crossing with `step` gives a hard edge. Testing it with a `smoothstep` window turns the same boundary into a crisp anti-aliased rim, or a wide glow if you widen the window. Every disc in [Chapter 18](18-YourFirstShader.md) is drawn this way, distance in, coverage out.

### min melts, max trims

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/30-SculptingWithFields/MeltStrip-dark.jpg">
  <img src="Images/30-SculptingWithFields/MeltStrip.jpg" alt="Two circles at four smoothing radii: touching hard, necking together, flowing into a peanut, and fused into one capsule" width="680">
</picture>

Combine two distance fields and set operations fall out of two tiny functions. `min` keeps whichever surface is nearer, the union. `max` keeps the farther, the intersection, and negating one gives subtraction. Then there is the **smooth minimum**, a min with a blending radius. Where the two fields are nearly tied it dips below both, so the shapes neck together and melt like wax instead of merely touching. The k dial in the picture is that radius. At an exact tie the dip is a quarter of `k`, and it shrinks to nothing where the two answers are `k` apart. [Chapter 30](30-SculptingWithFields.md) sculpts with it.

<!-- Figure waiting on a render: Figures/B-JustEnoughMath/SmoothMin.swift (themed). When its image lands, embed it here, below the entry's first picture as a picture tag at width 680, with its dark sibling as the source. -->

### Sphere tracing: hop by what the field promises

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/30-SculptingWithFields/MarchRay-dark.jpg">
  <img src="Images/30-SculptingWithFields/MarchRay.jpg" alt="A ray from an eye crossing in shrinking hops, each bounded by a circle showing the distance the field reported, ending on a surface" width="680">
</picture>

To render a distance field, march a ray from the eye. Ask the field "how far to the nearest surface?", and since nothing can be closer than that answer, hop exactly that far, safely. Repeat, and the hops shrink as the surface nears, until a hop below a threshold counts as a hit. No triangles anywhere, just a field asked a few dozen times per pixel. It's how all of [Chapter 30](30-SculptingWithFields.md)'s 3D sculptures reach the screen.

### Folding space

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/30-SculptingWithFields/DomainFold-dark.jpg">
  <img src="Images/30-SculptingWithFields/DomainFold.jpg" alt="An asymmetric cluster mirrored into a facing pair, the same cluster tiled into a grid, and a petal fanned into a nine-fold rosette" width="680">
</picture>

Instead of copying a shape n times, fold the *question*. Mirror the query point, wrap it into a repeating cell, or rotate it into one wedge before asking the field. One shape, one evaluation, and the fold makes it appear everywhere the transformed points coincide. A grid of a thousand copies costs the same as one. It's repetition run backward, applied to space itself. [Chapter 30](30-SculptingWithFields.md) mirrors, tiles, and fans with it.

## Into three dimensions

### An eye on a sphere

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/25-3DGently/Orbit-dark.jpg">
  <img src="Images/25-3DGently/Orbit.jpg" alt="A small camera on a ring around an object, with a sight line labeled radius, a ground arc labeled azimuth, and a climbing arc labeled elevation" width="680">
</picture>

Three numbers aim a camera at a thing: **azimuth** is how far around, **elevation** how far up, and **radius** how far away. Together they place an eye anywhere on a sphere around the target, which is why orbiting feels like turning an object in your hand. It's the polar-coordinates idea from the circle entries, plus one more angle for up. [Chapter 25](25-3DGently.md) drives its cameras with these three.

### Perspective, and who's in front

<img src="Images/25-3DGently/DepthRow.jpg" alt="Six spheres in a row marching away from the camera, each smaller and partly hidden behind the one before" width="560">

Perspective is one rule, that apparent size falls with distance, so equal spheres shrink as they recede. The **field of view** is the lens angle, wide exaggerating the shrink, narrow flattening it like a telephoto. And notice the hiding, because in 3D drawing order stops deciding who's in front. Every pixel remembers the depth of the nearest surface drawn so far and rejects anything farther, which is the **depth test**. [Chapter 25](25-3DGently.md) leans on both without ceremony.

### Which way a face points: the normal

<!-- Figure waiting on a render: Figures/B-JustEnoughMath/EdgesAndNormal.swift (themed). When its image lands, embed it here as a picture tag at width 680, with its dark sibling as the source. -->

A flat triangle faces one way, and the arrow standing straight out of it is its **normal**. Light needs it, because a face turned toward a lamp is lit and a face turned away is dark. Two edges from the same corner give it. The cross product of two directions is a third direction at right angles to both, so `(b - a).cross(c - a)` stands straight out of the face. Which side it comes out of depends on the order of the corners. Name them counter-clockwise as you look at the face, and the normal points toward you. [Chapter 25](25-3DGently.md#what-a-solid-is-made-of-triangles-and-normals) builds its solids from triangles and their normals.

### The pinhole: a pixel plus a depth is a ray

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/33-DepthAndThePhone/Unproject-dark.jpg">
  <img src="Images/33-DepthAndThePhone/Unproject.jpg" alt="A lens, an image plane with a marked pixel, and a dashed ray extending out to a 3D point, with the recovered-coordinates formula below" width="680">
</picture>

A camera flattens the world by sliding every point down a ray through the lens. A depth sensor records how far in front of the camera each pixel's surface was. It measures along the camera's forward axis, not along the ray. Unprojection runs the flattening backward. Slide the pixel off the image center, scale by depth over focal length, and the 3D point returns. A flat photo plus a flat depth map quietly holds a full 3D scene. [Chapter 33](33-DepthAndThePhone.md) stands its point clouds up with exactly this.

### A pose places points in the world

<img src="Images/33-DepthAndThePhone/SweepFuse.jpg" alt="Three tinted captures of a room fused into one cloud, each camera position marked with a small sphere and sight line" width="680">

Points recovered from a camera come out in *its* frame, "two meters ahead of me", wherever "me" was. A **pose** is the transform recording where the camera stood and how it was turned. Applying it carries camera-frame points into one shared world frame. Do that for every frame of a moving sweep and the fragments fuse into a single room, each capture parked where its camera actually stood. [Chapter 33](33-DepthAndThePhone.md) fuses its scans this way.

### Occlusion voids: the shape of not knowing

<img src="Images/33-DepthAndThePhone/CloudLift.jpg" alt="A flat frame stood up into a point cloud viewed from a new angle, with black voids stretching behind the ball and crate" width="560">

A depth image knows only what its rays touched, so behind every object lies a shadow of space nothing measured. View the cloud from where the camera stood and it looks whole. Step to the side and the voids open, holes in the shape of whatever stood in front. They record where the sensor could not see, and only more viewpoints fill them. [Chapter 33](33-DepthAndThePhone.md) fills them by fusing frames from a moving camera.

## Sound as numbers

### The spectrum

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/34-Listening/Anatomy-dark.jpg">
  <img src="Images/34-Listening/Anatomy.jpg" alt="Three stacked panels from one analyzed instant: the raw waveform, the spectrum with spikes at the kick, bass, and melody, and normalized band bars" width="680">
</picture>

Any sound, however messy, splits into a sum of pure vibrations. The spectrum reports the energy at each frequency, the moment's recipe, bass at the left and brilliance at the right. One more fact makes it drawable. Hearing is logarithmic, and each *doubling* of frequency, an octave, sounds like one equal step. So useful band bars are log-spaced, giving the low and high octaves equal width instead of letting the treble hog the axis. [Chapter 34](34-Listening.md) turns spectra into instruments.

### Equal steps that multiply: log scales

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/37-MusicByRule/Sonification-dark.jpg">
  <img src="Images/37-MusicByRule/Sonification.jpg" alt="A series of sixteen values shown as bars, then the same series as note positions spread evenly in semitones, again spread evenly in hertz where the high values bunch together near the top, and again snapped so every mark lands on a line of the scale" width="680">
</picture>

Some amounts are felt by ratio rather than by difference. The step from 220 Hz to 440 sounds the same as the step from 440 to 880, though the second is twice as many hertz. A **logarithmic scale** spaces values by their ratios, so each doubling takes the same distance. Spread notes evenly in hertz and the high ones bunch together when you hear them. Spread them evenly in semitones, a log scale, and they sit evenly, as the second and third rows here show. [Chapter 37](37-MusicByRule.md) spreads data this way, and [Chapter 22](22-IteratedForms.md)'s flames take the logarithm of their counts to fit a huge range into one picture.

### Pitch as ratios: octaves, semitones, and cents

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/37-MusicByRule/Tunings-dark.jpg">
  <img src="Images/37-MusicByRule/Tunings.jpg" alt="Seven tunings as rows of ticks on one axis in cents from the root to three times its frequency, with guides at the octave and at three times: equal temperament, just intonation, pythagorean, quarter tones, nineteen, thirty-one, and Bohlen-Pierce, the tick nearest a just major third marked in each octave tuning, with the row's step count and that third's value under its name" width="680">
</picture>

Doubling a frequency raises a note an octave, and every octave sounds like the same step, whatever note it starts on. Equal temperament splits the octave into twelve semitones of one ratio each. That ratio is the twelfth root of 2, about 1.0595, so twelve of them make exactly 2. **Cents** divide each semitone into a hundred, so an octave is 1200 cents. They measure how far apart two tunings put a note. A just major third, the ratio 5/4, is 386 cents, and equal temperament puts it at 400. [Chapter 37](37-MusicByRule.md) builds scales on the semitone and compares tunings in cents.

### Loudness in steps: decibels

<!-- Figure waiting on a render: Figures/B-JustEnoughMath/Decibels.swift (themed). When its image lands, embed it here as a picture tag at width 680, with its dark sibling as the source. -->

Loudness is also heard by ratio, and decibels count it that way. A level in decibels is 20 times the base-10 logarithm of the level as a fraction of full scale. So 0 dB is as loud as a sample can be. Every 6 decibels down about halves the level, and every 20 down divides it by ten. [Chapter 36](36-MakingSound.md)'s compressor, gate, and limiter set their thresholds in decibels below full scale.

### Events, not levels

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/34-Listening/BeatTimeline-dark.jpg">
  <img src="Images/34-Listening/BeatTimeline.jpg" alt="A six-second timeline: the loudness curve with regular peaks, a beat pulse snapping up at each detection, and tick marks counting beats" width="680">
</picture>

Loudness is a level, while a beat is an *event*. You can't find events by watching a level's height, because a sustained chord is loud forever without ever being "a hit". Detection compares each instant with the moment just before. A sudden rise above the recent trend is an arrival, and a short refractory pause keeps one drum hit from counting twice. The signal is change over time, not amount. [Chapter 34](34-Listening.md) builds its beat-reactive sketches on that comparison.

---

[Contents](README.md#contents) · Previous: [Appendix A, Just enough Swift](A-JustEnoughSwift.md) · Next: [Appendix C, Coming from p5.js and Processing](C-ComingFromP5.md)
