#### <sup>[Ollin](../README.md) → [Guide](README.md) → Appendix B</sup>

---

# B. Just enough math, visually

This appendix explains every math idea in the guide again, in one short entry each. Each entry gives a picture, a plain-words explanation, and a link to the chapter that uses it. It supports the guide's first rule, that a concept comes before anything uses it. If you get lost on a page anywhere, look here for what you are missing.

The entries are grouped by theme rather than by chapter, so related ideas sit together. You can read it from start to end, or go straight to the one idea you need.

**Contents:** [Where things are](#where-things-are) · [Angles and circles](#angles-and-circles) · [Fractions, mapping, and wrapping](#fractions-mapping-and-wrapping) · [Shaping a value](#shaping-a-value) · [Randomness](#randomness) · [Noise](#noise) · [Moving the paper](#moving-the-paper) · [Vectors, motion, and forces](#vectors-motion-and-forces) · [Fields and following them](#fields-and-following-them) · [Local rules, global structure](#local-rules-global-structure) · [Iteration: a rule applied again](#iteration-a-rule-applied-again) · [Shapes as regions](#shapes-as-regions) · [Color and light as numbers](#color-and-light-as-numbers) · [Per-pixel thinking and distance](#per-pixel-thinking-and-distance) · [Into three dimensions](#into-three-dimensions) · [Sound as numbers](#sound-as-numbers)

## Where things are

### The canvas: x right, y down

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/CoordinateSystem-dark.jpg">
  <img src="Images/01-HelloOllin/CoordinateSystem.jpg" alt="The canvas coordinate system: origin at the top left, x growing right, y growing down, with one point marked" width="680">
</picture>

Every position on the canvas is two numbers, counted in pixels from the top-left corner. Here x grows to the right, and y grows *downward*. Graphs in school math do the opposite, with y growing upward. To move something toward the bottom of the screen you *add* to y. The convention comes from how screens have been addressed since text terminals, and [Chapter 1](01-HelloOllin.md) starts here.

### Normalized coordinates: 0…1 anywhere

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/18-YourFirstShader/UVSpace-dark.jpg">
  <img src="Images/18-YourFirstShader/UVSpace.jpg" alt="The uv gradient annotated: (0,0) at the top left, (1,1) at the bottom right, the center marked (0.5, 0.5)" width="680">
</picture>

Instead of pixels, an address can be a *fraction* of the whole, 0 at one edge and 1 at the other. So (0.5, 0.5) is the center of anything, at any resolution. A shader's `shade` function gets each position in these `uv` coordinates, and [Chapter 18](18-YourFirstShader.md) works in them. Subtracting 0.5 re-centers them, so distances measure from the middle. The same trick names positions inside a camera image regardless of its size ([Chapter 34](34-Seeing.md)).

### Putting a normalized point onto the canvas

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/34-Seeing/TrackerFlow-dark.jpg">
  <img src="Images/34-Seeing/TrackerFlow.jpg" alt="A diagram of camera frames flowing through a tracker, and a normalized lower-left-origin point mapping into the drawn frame's rectangle" width="680">
</picture>

A point given as fractions of an image becomes a canvas point when you scale it into the rectangle you drew the image in. Vision results count y *up* from the bottom-left, while the canvas counts y *down* from the top-left. So the y fraction flips on the way (`1 - y`). In [Chapter 34](34-Seeing.md), the `in:` helpers such as `bounds(in:)` do the flip and the scale for you, with this same math.

### The 3D world frame

<img src="Images/B-JustEnoughMath/WorldFrame.jpg" alt="Two labeled frames: the canvas with y growing down from a top-left origin, and the 3D world with y growing up and z coming toward the viewer" width="680">

The 3D world uses its own frame. The origin sits wherever you like, x still grows right, y grows *up*, and z comes toward you. Positions are in world units rather than pixels. A sphere of radius 1 is one unit, and the camera's distance decides how big it looks. The canvas's y-down is a habit of 2D screens, and 3D keeps the y-up of school math. [Chapter 26](26-3DGently.md) makes the switch. Depth data in meters lands in the same kind of frame in [Chapter 35](35-Depth.md).

## Angles and circles

### Radians and tau

<img src="Images/B-JustEnoughMath/TauClock.jpg" alt="A dial with 0, tau over 4, tau over 2, and 3 tau over 4 marked around it, an accent wedge of tau over 8, and three mini dials showing tau over 12, 6, and 3" width="680">

Angles here are radians, and the easiest way to write them is with `.tau`, the angle of one full turn (about 6.283, twice pi). Fractions of tau read as fractions of a turn: `.tau / 4` is a quarter turn, `.tau / 12` a clock hour. Because the canvas's y points down, angles sweep *clockwise* on screen, starting from 3 o'clock. Thinking in turns spares you both degrees and memorized decimals, and [Chapter 1](01-HelloOllin.md) measures angles this way.

### An angle and a radius make a point

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/AroundACircle-dark.jpg">
  <img src="Images/01-HelloOllin/AroundACircle.jpg" alt="A circle with an angle marked at its center, and cos and sin placing a point on its rim" width="680">
</picture>

To stand on a circle's rim, you need how far around (an angle) and how far out (a radius). `cos(angle) * radius` gives the across part, `sin(angle) * radius` the down part, and adding them to the center gives the point. The angle in the picture is negative, so its point sits above the center. This one pattern places petals, clock hands, orbiting moons, and everything else arranged in a ring. It first appears in [Chapter 1](01-HelloOllin.md), and later chapters keep using it.

Once you know the pattern, you can also write it as one call. `polar(angle, radius, around: center)` returns the same point, and `angles(12)` returns twelve evenly spaced angles to place things at. A ring of things becomes a `for` loop with no index arithmetic. This appendix keeps spelling the trig out so you can see it work.

### The angle of an arrow: `atan2`

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../Docs/Images/VectorHeading-dark.jpg">
  <img src="../Docs/Images/VectorHeading.jpg" alt="Three panels in screen space with y down: the vector (3, 4) as the long side of its 3-4-5 right triangle, the angle measured from the positive x-axis and growing clockwise, and a quarter turn taking (3, 0) to (0, 3)" width="680">
</picture>

[An angle and a radius make a point](#an-angle-and-a-radius-make-a-point) goes from an angle to a point. `atan2(y, x)` goes back, from a point to its angle. Given the two parts of an arrow, it answers the angle the arrow points at, measured from the positive x-axis, between `-.pi` and `.pi`. It takes y first. It needs both parts, because an arrow and its opposite have the same ratio of y to x. (1, 1) and (-1, -1) are one example. A vector's `angle` is this call. [Chapter 10](10-Vectors.md) turns a shape to face where it moves with it, and [Chapter 17](17-MarksAndMedia.md) reads the lean of a pen.

### Two angles and a radius make a point in space

In the [3D world frame](#the-3d-world-frame) a point on a sphere needs two angles and a distance. The first angle is the azimuth, and it turns around the y axis like a compass bearing. `0` points along +z toward you, and a quarter turn points along +x. The second is the elevation, which lifts the point above the floor of x and z: `0` is level, `.pi / 2` is straight up. These are latitude and longitude with a radius added, the way maps have named places since Ptolemy's *Geography*, nearly two thousand years ago.

```swift
let planet = Vector3(0, 1, 0)
let moon = spherical(time, 0.3, 3, around: planet)    // circles the planet, a little above its level
```

`spherical(azimuth, elevation, radius, around:)` takes the angles first and the radius last, as `polar` does. Inside, it is the circle pattern twice. The elevation splits the radius into a height of `sin(elevation) * radius` and a reach along the floor of `cos(elevation) * radius`. The azimuth then places that reach on a circle. It is the same convention as the camera's orbit, so `spherical(a, e, r)` is where a camera stands when it orbits the origin at those angles. A `Vector3`'s `azimuth` and `elevation` go the other way and read the two angles off a direction. Each is an `atan2` like the one above.

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

Adding a constant inside `sin(...)` starts the swing partway through its cycle, a head start, called phase. Give each element a *different* head start, usually from its position, as in `sin(time + x * 0.02)`. Then identical motions turn into a wave that travels across space. [Chapter 3](03-MotionAndTime.md) gives a row of dots their head starts this way.

### n copies close the circle

<img src="Images/06-GridsAndRepetition/Rosette.jpg" alt="A twelve-fold rosette: one branching arm repeated by rotation into a botanical snowflake" width="560">

Rotational symmetry is repetition around a point: draw one arm, rotate by `.tau / n`, draw again, n times. Since n equal steps of `.tau / n` add up to exactly one full turn, the last copy meets the first with no seam. [Chapter 6](06-GridsAndRepetition.md) builds rosettes and mandalas this way from a single drawing.

### An angle that never closes: the golden angle

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/B-JustEnoughMath/GoldenAngle-dark.jpg">
  <img src="Images/B-JustEnoughMath/GoldenAngle.jpg" alt="The same 500 seeds in three disks, each seed turned by one angle and pushed out by the square root of its number: at 137.5 degrees, the golden angle, in orange, they fill the disk evenly; at 137.0 degrees they line up into curving spokes with gaps between them; at 144 degrees, two fifths of a turn, they make five straight spokes" width="680">
</picture>

Turning by a simple fraction of a turn brings you back to the start after a few steps, which is what closes [the rosette](#n-copies-close-the-circle). Sometimes you want the opposite, many things placed around a center with none lined up behind another. The golden angle, about 137.5 degrees or 0.382 of a turn, does that. As a fraction of a turn, it is the number that simple fractions like 2/5 or 3/8 come least close to. So no two steps ever line up, and each new one lands in one of the widest gaps left. A sunflower's seeds grow this way. The middle disk turns the same seeds by 137.0 degrees, which lines them up into curving arms with gaps between them. The right one turns them by 144 degrees, two fifths of a turn, and they fall on five straight spokes. [Chapter 16](16-CurvesAndFigures.md) turns each seed by the golden angle and pushes it out by the square root of its number. [Chapter 29](29-Landscapes.md) spreads its lamps the same way.

### Numbers that turn: complex multiplication

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/B-JustEnoughMath/MultiplyingTurns-dark.jpg">
  <img src="Images/B-JustEnoughMath/MultiplyingTurns.jpg" alt="Two panels on the complex plane. Left, arrows from the origin for z, length 1.2 at 20 degrees, and w, length 1.5 at 50 degrees, and in orange their product z times w, length 1.8 at 70 degrees. Right, arrows to 1, to i, and to -1, with an orange half circle through them and the note that each multiplication by i is a quarter turn" width="680">
</picture>

A point `(x, y)` can also be read as one number, written `x + y·i`, where `i` is a number whose square is -1. Read that way, the plane is the **complex plane**, and its use here is multiplication. Multiplying two of these numbers multiplies their lengths and adds their angles. In the left panel, z points at 20 degrees and w at 50 degrees, so z times w points at 70 degrees. The lengths multiply too, and 1.2 times 1.5 makes the 1.8 of the orange arrow. So multiplying by `i`, which has length 1 and points a quarter turn around, turns anything a quarter turn. Two quarter turns make half a turn, which is why `i` times `i` is -1. Squaring a point doubles its angle and squares its length. [Chapter 22](22-IteratedForms.md#multiplying-turns-the-complex-plane) builds escape-time fractals and domain coloring on this.

### Circles on circles: Fourier

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/16-CurvesAndFigures/EpicycleTerms-dark.jpg">
  <img src="Images/16-CurvesAndFigures/EpicycleTerms.jpg" alt="Three panels rebuilding the letter g from spinning circles: with three circles it is a wobbly loop, with twelve it is recognizably the letter, and with sixty-four it is exact, with the faint construction circles visible in each" width="680">
</picture>

A closed outline can be rebuilt from circles. Each circle turns a whole number of laps while centered on the tip of the one before it, and the last tip traces the shape. A few large, slow circles give the rough form, and more small, fast ones add the detail. This is Joseph Fourier's idea from the 1820s: a repeating shape is a sum of plain waves. [Chapter 16](16-CurvesAndFigures.md) draws with the circles, and [Chapter 21](21-PicturesYouSolve.md) reads a whole picture as waves. [Chapter 33](33-TracedLight.md) finds it in the star around a bright light in a lens. A sound splits the same way, as [the spectrum](#the-spectrum) shows.

## Fractions, mapping, and wrapping

### t, the fraction along: lerp and map

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/03-MotionAndTime/MapAndLerp-dark.jpg">
  <img src="Images/03-MotionAndTime/MapAndLerp.jpg" alt="Top: a value carried between two number lines by its fraction along. Bottom: dots walking a segment from a to b as t runs 0 to 1" width="680">
</picture>

A value between 0 and 1 can mean "how far along". It reads 0 at the start, 1 at the end, and 0.25 a quarter of the way. `lerp(a, b, t)` walks from `a` to `b` by that fraction. `map(v, inLo, inHi, outLo, outHi)` carries a value from one range to another by *keeping* its fraction along. So 75% into the input range comes out 75% into the output range. The same idea squeezes sine's -1…1 into 0…1 (`sin(x) * 0.5 + 0.5`). [Chapter 2](02-Color.md) mixes colors by `t`, and [Chapter 3](03-MotionAndTime.md) makes both calls everyday tools.

### Three fractions at once: barycentric coordinates

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/B-JustEnoughMath/Barycentric-dark.jpg">
  <img src="Images/B-JustEnoughMath/Barycentric.jpg" alt="Two triangles with corners a, b, and c. Left, one orange point joined to the corners, which cuts the triangle into three pieces labeled 0.5 of a, 0.3 of b, and 0.2 of c, each weight in the piece opposite its corner. Right, the triangle filled with dots whose colors mix red at a, blue at b, and yellow at c in each dot's own weights. Mixed as light, the colors stay bright through the middle, a pale tan there and a dusty mauve along the edge from a to b" width="680">
</picture>

`lerp` names a point between two ends with one fraction. A point inside a triangle takes three, one for each corner, and the three add up to 1. The point is that much of each corner mixed together. A weight of 0.5 on the first corner puts the point halfway from the opposite edge to that corner. Each weight is also a share of area. Lines from the point to the corners cut the triangle into three. A corner's weight is the share of the piece opposite it. The orange point on the left has a weight of 0.5 on corner a, so the piece opposite that corner is half the triangle. The same weights mix anything the corners carry, such as a color or a height. The right half of the picture gives each corner a color and mixes the three at every dot. [Chapter 29](29-Landscapes.md) reads the weights off a point scattered over a mesh, to blend what the mesh stores at its corners.

### Wrapping: remainder, fract, and pingPong

<img src="Images/B-JustEnoughMath/Wrap.jpg" alt="Three strips over one time axis: raw time rising forever, loopProgress wrapping 0 to 1 every lap, and pingPong folding each lap out and back" width="680">

A clock that only grows becomes a cycle by wrapping. The `%` remainder wraps whole numbers, so `i % 4` cycles 0, 1, 2, 3. `fract` keeps only the part after the decimal point, so 2.75 becomes 0.75, and a growing value wraps into 0…1. `loopProgress(over: 3)` is that wrap applied to the sketch clock, "how far through the current 3-second lap". `pingPong` folds each lap, so the value goes out and back instead of jumping to 0. [Chapter 1](01-HelloOllin.md) meets `%`, and [Chapter 3](03-MotionAndTime.md) supplies the two helpers.

### What two counts share: the greatest common divisor

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/07-Tiles/KolamLoops-dark.jpg">
  <img src="Images/07-Tiles/KolamLoops.jpg" alt="Three dark panels of chalk-colored looping line work around small dots. One continuous line over a field of seven by five dots; two interleaved loops in cream and orange over six by four; and the same seven by five field cut into three loops by two short walls" width="680">
</picture>

The greatest common divisor of two whole numbers is the largest number that divides both. For 6 and 4 it is 2, and for 7 and 5 it is 1. It decides how two repeating things line up. [Chapter 7](07-Tiles.md)'s kolam draws one unbroken line around a field of seven by five dots. Around six by four it draws two separate loops, as the first two panels show. The number of loops is the greatest divisor the two sides share. Euclid's method finds it by taking remainders again and again, and [Chapter 40](40-MusicByRule.md)'s Euclidean rhythms spread their hits by the same steps.

### The perfect loop

<img src="Images/03-MotionAndTime/RingPulse.gif" alt="Waves of light chasing around concentric rings of colored dots, looping seamlessly" width="480">

An animation loops with no visible jump when every time-driven term completes *whole* cycles in the loop length. A 4-second loop can hold sine waves with periods of 4, 2, or 1 second. A period of 3 jumps where the loop starts over. Noise loops the same way. `noise(x, loop: t)` walks a closed circle through the noise field, so one lap ends where it began ([Chapter 5](05-Noise.md)). [Chapter 3](03-MotionAndTime.md) states the rule. An exported GIF depends on it, because a GIF plays its first frame again after its last.

### Sampling one grid with another

<img src="Images/09-Pictures/TypeMosaic.jpg" alt="A portrait built entirely from one word repeated in a grid, colored and sized by the image beneath" width="560">

To read an image at any grid's resolution, connect the grid and the image through fractions. A cell 30% across and 60% down the grid reads the pixel 30% across and 60% down the image. Nothing needs to match in size, because the fractions do the translation. This is how [Chapter 9](09-Pictures.md) rebuilds a photo as a mosaic of letters. It is the idea of normalized coordinates, from the start of this appendix, used on a grid.

## Shaping a value

### Reading a shaping curve

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/03-MotionAndTime/ShapingCurves-dark.jpg">
  <img src="Images/03-MotionAndTime/ShapingCurves.jpg" alt="Three panels showing linear, step, and smoothstep as curves over a faint identity diagonal, each with a strip of dots spaced by the curve" width="680">
</picture>

A shaping function takes a 0…1 value and hands back a reshaped 0…1 value. Its graph shows input along the bottom and output up the side, and the straight diagonal means "unchanged". Where the curve is steep, the value moves fast. Where it's flat, the value lingers, which is why the dot strips under each curve bunch and spread. `step` is an if in curve form, 0 then 1 at an edge. `smoothstep` is the gentle S between two edges, with `t * t * (3 - 2 * t)` inside. Squaring a 0…1 value is a shaping curve too, since it pushes the middle down and keeps the ends. That's [Chapter 9](09-Pictures.md)'s one-line contrast boost. [Chapter 3](03-MotionAndTime.md) has the rest of these curves.

### Exponential decay

<img src="Images/19-LayersAndEffects/Comets.jpg" alt="Comet swarms of glowing dots, each dragging a soft luminous tail that fades with age" width="560">

Multiply a value by a little less than 1 every frame, keeping 93% say, and it fades smoothly. It falls fast at first, then more and more slowly, and never quite reaches zero. That's exponential decay, and it is the shape of a fading trail. The newest mark is full strength, and each older one has been multiplied down one more time. [Chapter 19](19-LayersAndEffects.md) uses it as the feedback fade behind these comet tails. [Chapter 37](37-Listening.md) fades a pulse the same way, scaled by `deltaTime` so it falls at the same speed at any frame rate.

## Randomness

### Pseudo-random: a scramble you can replay

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/04-Randomness/SeedSheet-dark.jpg">
  <img src="Images/04-Randomness/SeedSheet.jpg" alt="Nine tiles of dot constellations labeled seed 1 through seed 9, every tile a distinctly different arrangement" width="560">
</picture>

`random()` is a deterministic scramble that plays out the same sequence from a chosen starting point, the **seed**. The same seed gives the same "random" result on every run, which is what makes generative work reproducible. A seed works like a serial number. Change it and you get another variation, a different result from the same code. [Chapter 4](04-Randomness.md) builds its seed workflow on this.

### Probability as a threshold

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/04-Randomness/Choices-dark.jpg">
  <img src="Images/04-Randomness/Choices.jpg" alt="Strips of dots showing probability gates at 0.25 and 0.75, a uniform four-color pick, and a pick dominated by one weighted color" width="680">
</picture>

`random() < 0.25` is true a quarter of the time. Every part of 0…1 is equally likely, and 0 to 0.25 is a quarter of it. By the same reasoning, `random() < 0.5` is true half the time. Stack several thresholds and you have a weighted choice. A common outcome gets a wide slice of the 0…1 line, and a rare one gets a thin slice. [Chapter 4](04-Randomness.md) turns this into scattered accents and weighted palettes.

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

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/B-JustEnoughMath/SquareRootSpread-dark.jpg">
  <img src="Images/B-JustEnoughMath/SquareRootSpread.jpg" alt="Two disks of 900 dots, each with an orange circle at half the radius. Left, at random(1) times the radius, the dots crowd the middle and 444 of 900 fall inside the circle. Right, at sqrt(random(1)) times the radius, they spread evenly and 218 of 900 fall inside it" width="680">
</picture>

To scatter points in a disk, pick an angle and a distance from the center. A plain distance, `random(1)` times the radius, crowds the points toward the middle. Half of them land within half the radius, but that inner circle holds only a quarter of the disk's area. The square root fixes it. With `sqrt(random(1))` as the fraction, a quarter of the points land within half the radius, which matches the area. The picture counts them. With the plain distance, 444 of 900 dots land inside the orange circle, and with the square root, 218 do, about a quarter. [Chapter 29](29-Landscapes.md) places its trees this way. [Chapter 16](16-CurvesAndFigures.md)'s sunflower spreads its seeds by the square root of their number for the same reason.

### Chance is lumpy

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/04-Randomness/ScatterCompare-dark.jpg">
  <img src="Images/04-Randomness/ScatterCompare.jpg" alt="Two panels with the same number of dots: plain random placement with clumps and bare gaps, and a blue-noise scatter, even but organic" width="680">
</picture>

Independent random placements clump and leave holes, because each roll ignores every other. Clumps are what independent rolls look like, even from a good generator. When you want "random but even", you need an algorithm that pushes points apart, like the blue-noise scatter on the right. [Chapter 4](04-Randomness.md) names the lump problem and fixes it with blue noise, and [Chapter 15](15-ShapesAsMaterial.md) scatters the same way inside a shape.

### The random walk

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/04-Randomness/WalkVsJumps-dark.jpg">
  <img src="Images/04-Randomness/WalkVsJumps.jpg" alt="Two strips: fresh rolls per step produce a jagged hash, accumulated nudges produce a wandering path" width="680">
</picture>

Re-roll a position every frame and you get a jagged hash with no memory. *Accumulate* small random nudges instead (`x += random(-2, 2)`) and a path appears, because each position remembers all the nudges before it. That one change, re-rolling or accumulating, is the difference between a jagged hash and a wandering path. [Chapter 4](04-Randomness.md) builds its random walks this way.

## Noise

### Coherence: a fixed, smooth landscape

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/05-Noise/RandomVsNoise-dark.jpg">
  <img src="Images/05-Noise/RandomVsNoise.jpg" alt="Two framed strips: a jagged hash of random heights, and a smooth rolling curve from noise" width="680">
</picture>

`noise(x)` is a *lookup* into a fixed, smooth landscape of values. Nearby inputs land on nearby outputs, so a sequence of close questions traces a rolling curve instead of a hash. This property is called coherence. It is what separates noise from random, and [Chapter 5](05-Noise.md) builds on it throughout.

### The input multiplier is a zoom control

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/05-Noise/NoiseZoom-dark.jpg">
  <img src="Images/05-Noise/NoiseZoom.jpg" alt="Three panels sampling the same noise field with multipliers 0.004, 0.015, and 0.06: one gentle valley, rolling hills, busy wiggles" width="680">
</picture>

The multiplier in `noise(x * scale)` sets how far apart your questions land on the landscape. The landscape itself stays the same. A small multiplier asks about points close together and sees one broad feature, while a large one steps across many hills and sees busy detail. When noise looks wrong, try changing this multiplier first. [Chapter 5](05-Noise.md) calls it the zoom multiplier.

### A field of answers, drifting in time

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/05-Noise/NoiseTerrain-dark.jpg">
  <img src="Images/05-Noise/NoiseTerrain.jpg" alt="The same noise field shaded as soft clouds and drawn as dot sizes, a halftone of the same values" width="680">
</picture>

Give noise two inputs and it answers everywhere on a plane. That's a **field**, one value per position, which you can render as brightness, dot size, or anything else. A third input works as time, sliding the whole landscape smoothly so the field changes without jumping. And because far-apart regions of the landscape don't resemble each other, offsetting your questions (`noise(t + 1000)` vs `noise(t)`) yields independent signals from one field. Most of [Chapter 5](05-Noise.md) works with fields like this.

### Layering scales

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/05-Noise/NoiseLayers-dark.jpg">
  <img src="Images/05-Noise/NoiseLayers.jpg" alt="Three strips: a slow big-scale curve labeled shape, a busy small-scale curve labeled detail, and their weighted sum" width="680">
</picture>

Natural forms have big shapes *and* fine texture. So take noise at both scales and add them, weighted mostly toward the broad curve and a little toward the busy one. Keep the weights summing to 1 and the result stays in range. Stack a few layers like that (each smaller and fainter) and you get the fractal texture that `fbm` gives in one call. [Chapter 5](05-Noise.md) builds it by hand first, so you know what that call does.

### Distance to the nearest point makes cells

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/05-Noise/CellsFromPoints-dark.jpg">
  <img src="Images/05-Noise/CellsFromPoints.jpg" alt="Two panels of cellular noise: distances shaded so each hidden point sits in a dark core, and the border reading drawing dark walls between the cells" width="680">
</picture>

Scatter points across a plane, then ask everywhere how far the nearest one is. The answers are small beside each point and peak on the walls between two, so shading them divides the plane into cells, one per point. Asking instead how much *farther* the second-nearest point is gives a value that is zero on those walls. Shading it draws the walls as dark lines. [Chapter 5](05-Noise.md) meets this as `worley`, the cellular member of the noise family.

## Moving the paper

### Transforms move the paper, not the shape

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/06-GridsAndRepetition/TransformSteps-dark.jpg">
  <img src="Images/06-GridsAndRepetition/TransformSteps.jpg" alt="Four panels drawing the same flag with the same call: untransformed, then translated, then rotated, then scaled" width="680">
</picture>

`translate`, `rotate`, and `scale` don't touch your shapes. They move the paper under the pen. Every draw call afterward lands in the moved frame, and later transforms build on earlier ones (translate then rotate is not rotate then translate). The habit that makes this easy is to draw your motif *around the origin*, with (0, 0) at its center. Then translate to where it goes and rotate. It pivots about its own center instead of swinging around a distant corner. [Chapter 6](06-GridsAndRepetition.md) uses this to draw one thing many ways, with `withState { }` to undo the moves after each copy.

### Small moves compound

<img src="Images/26-3DGently/Stairs.jpg" alt="A spiral staircase of colored slabs winding up a dark central post" width="560">

Repeat "move a little, turn a little, draw" without resetting, and the little moves stack, because each copy starts where the last one ended. A straight repetition then curls into an arc, a spiral, or a helix if you lift by a step each time. `withState { }` controls where the moves reset. Resets between copies give you a grid, and no resets give you a staircase. [Chapter 6](06-GridsAndRepetition.md) shows both in 2D, and [Chapter 26](26-3DGently.md) builds these stairs with the same loop.

### The plane turned inside out: inversion in a circle

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/B-JustEnoughMath/CircleInversion-dark.jpg">
  <img src="Images/B-JustEnoughMath/CircleInversion.jpg" alt="An orange mirror circle with its center marked. A point P inside it, at distance d, lies on a dashed ray that runs out to its image at r squared over d. A small gray square inside the circle near its rim comes out as a larger orange shape outside it with curved sides. Notes beside them: the rim stays where it is, inside goes outside and outside comes in, near the center goes far, and straight edges come out curved" width="680">
</picture>

Inversion in a circle moves every point along the line from the circle's center through it. A point at distance d from the center lands at r² / d, where r is the circle's radius. Points on the circle stay where they are, points inside go outside, and points near the center go far away. Inverting twice brings every point back, so the circle works like a mirror. A circle comes out as another circle, or as a straight line when it passes through the center. In reverse, a straight line that misses the center comes out as a circle through the center. So the gray square in the picture comes out with curved sides, and its corner nearest the center lands farthest away. Since circles come out as circles, [Chapter 22](22-IteratedForms.md#circles-used-as-mirrors-inversion-limit-sets)'s limit sets are made of round shapes.

### Four corners anywhere: corner pinning

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/45-Installations/FittingTheWall-dark.jpg">
  <img src="Images/45-Installations/FittingTheWall.jpg" alt="Left, a rectangle of grid lines landing on a wall as a lopsided four-sided shape, labeled as it lands. Right, the same grid sitting square inside the wall with a handle on each corner, labeled corner-pinned. Below, two colored blocks meeting in a shared band where each fades out, with a flat line across the top labeled added up, one coat" width="680">
</picture>

Translate, rotate, and scale keep parallel lines parallel. A projector aimed at a wall from an angle turns the picture's rectangle into a lopsided four-sided shape. Fixing that takes one more kind of move. A **projective map** sends the four corners of a square to any four points and carries everything between them along. Straight lines stay straight, but equal steps no longer stay equal, the way a road's stripes crowd together toward the horizon. [Chapter 45](45-Installations.md) fits a projector to a wall by dragging the four corners, and Paul Heckbert set out the math in 1989.

## Vectors, motion, and forces

### A vector is a point and an arrow

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/10-Vectors/VectorArithmetic-dark.jpg">
  <img src="Images/10-Vectors/VectorArithmetic.jpg" alt="Four panels: adding arrows head to tail, the arrow from a point to a target, an arrow scaled and flipped, and a long arrow with its unit-length version" width="680">
</picture>

A `Vector2` is two numbers with two readings. It's a *place*, meaning a position, or a *way to move*, meaning a direction with a length. Each operation has a picture. Adding chains arrows head to tail, and `target - position` is the arrow *from* here *to* there. Multiplying by a number stretches or shrinks the arrow, and a negative number flips it. An arrow's `length` comes from Pythagoras. `normalized` keeps its heading at length exactly 1, ready to be scaled to any speed you want. [Chapter 10](10-Vectors.md) teaches all of this, one step at a time.

### The motion trio

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/10-Vectors/MotionTrio-dark.jpg">
  <img src="Images/10-Vectors/MotionTrio.jpg" alt="A dotted flight arc with three arrows at one moment: position from the origin, velocity along the path, acceleration pointing down" width="680">
</picture>

Motion is three vectors in a strict chain. **Acceleration** changes velocity, **velocity** changes position, and never the other way around. Each frame runs `velocity += acceleration` and then `position += velocity`. Steer a thing by pushing on its acceleration and letting the chain pass the push on to velocity and position. The lag between push and path is where the lifelike feel comes from. At the canvas's edges you choose a policy. *Wrap* sends a thing out one side and back in the other. *Bounce* flips the velocity component that hit, usually keeping less than all of it. The trio arrives in [Chapter 10](10-Vectors.md), and the forces and flocks of [Chapter 11](11-ForcesAndPhysics.md) and [Chapter 12](12-FlocksAndSwarms.md) are built on it.

### Steering is a correction

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/10-Vectors/SteeringMove-dark.jpg">
  <img src="Images/10-Vectors/SteeringMove.jpg" alt="A dot with a velocity arrow and a desired arrow toward a target; beside it, the steer arrow connecting the velocity's tip to the desired's tip" width="680">
</picture>

A creature that cannot jump straight to its target steers by correcting its course. Compute the velocity it *wants*, toward the target at full speed, then subtract the velocity it *has*. The difference is the correcting force, capped so the turn takes time. In code, that is `desired - velocity`. That one subtraction, re-aimed, becomes seek, flee, arrive, and wander in [Chapter 10](10-Vectors.md) and [Chapter 12](12-FlocksAndSwarms.md).

### Forces add; mass divides

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/11-ForcesAndPhysics/ForceAccumulation-dark.jpg">
  <img src="Images/11-ForcesAndPhysics/ForceAccumulation.jpg" alt="Three labeled arrows for gravity, wind, and drag pushing on one dot; beside it, the same arrows chained tip to tail with the total marked" width="680">
</picture>

A force is a push with a direction, and simultaneous pushes on one body add, tip to tail, into one total. What the body *does* with the total depends on its mass, through `acceleration = force / mass`. So the same wind barely moves a boulder and flings a leaf. Real gravity is the special case that scales *with* mass, so after the division everything falls alike. Drag doesn't scale that way, which is why a feather drifts. [Chapter 11](11-ForcesAndPhysics.md) builds its confetti on this difference.

### Weaker with distance: the inverse square

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/B-JustEnoughMath/InverseSquare-dark.jpg">
  <img src="Images/B-JustEnoughMath/InverseSquare.jpg" alt="Light from a point source spreading through a widening pyramid and crossing three squares at distances 1, 2, and 3, which hold 1, 4, and 9 cells. Beside it, a curve of the light in one cell against distance, falling through 1, 1/4, and 1/9" width="680">
</picture>

Light from a point spreads out as it travels. At twice the distance, the same light covers four times the area, so each part of it gets a quarter as much. At three times the distance, each part gets a ninth. That is the **inverse square**: the strength falls as one over the distance squared. Its curve in the picture falls steeply near the source and flattens farther out. Gravity follows the same rule, and it is how [Chapter 11](11-ForcesAndPhysics.md)'s `NBody` pulls its bodies together. [Chapter 29](29-Landscapes.md) says why its lamps use a gentler curve that ends.

### Floating: the weight of the water pushed aside

<img src="Images/30-WorldsWithWeight/Floating.jpg" alt="Four crates floating in a row on still blue water, each sitting lower than the one before it, from a pale crate four fifths above the surface to a dark one with a fifth above it" width="560">

A body in water sinks until the water it pushes aside weighs as much as the body. That is Archimedes' principle. So a body half as dense as water floats with half of itself under the surface. One at 0.8 of the water's density floats low, with a fifth above. [Chapter 30](30-WorldsWithWeight.md) works each crate's waterline out from its density alone.

### The spring's rule

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/11-ForcesAndPhysics/SpringRestLength-dark.jpg">
  <img src="Images/11-ForcesAndPhysics/SpringRestLength.jpg" alt="A coil spring between two discs: at rest length, stretched with arrows pulling inward, and squeezed with arrows pushing outward" width="680">
</picture>

A spring is built around one number, its **rest length**. When it is longer than that, it pulls its ends together. When it is shorter, it pushes them apart, and at its rest length it does nothing. The correction grows with the error (twice as stretched, twice the pull), and **stiffness** scales how sharply it acts. Everything soft in [Chapter 11](11-ForcesAndPhysics.md), from ropes to blobs, is dots connected by this one rule.

### Damping: a swing that dies away

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/B-JustEnoughMath/Damping-dark.jpg">
  <img src="Images/B-JustEnoughMath/Damping.jpg" alt="Three panels of a spring let go from one unit of stretch, over three seconds. With a little damping it swings past the rest length again and again, each swing smaller. With just enough, in orange, it drops to the rest length and stays. With a lot, it creeps toward the rest length and has not reached it at the end" width="680">
</picture>

A spring on its own would swing forever. **Damping** is a force against the velocity, and it takes a little energy out of every swing. With a little damping the spring rings for a long time. With a lot, it creeps back without swinging at all. Between the two is the amount that settles soonest without passing the rest length. In the picture, that amount, in orange, settles within about a second, while the other two have not settled after three seconds. [Chapter 3](03-MotionAndTime.md)'s `@Sprung` sets this with `bounce`, and in [Chapter 11](11-ForcesAndPhysics.md) the world's built-in drag calms the springs.

### Verlet: motion without a velocity

<img src="Images/B-JustEnoughMath/Verlet.jpg" alt="Dots labeled previous and now, the step between them carried forward as a dashed arrow, then bent down by gravity to the next position" width="680">

Verlet integration stores no velocity at all. It remembers where the particle *was* last frame. The gap between then and now *is* the velocity, so each step replays that gap and bends it by the frame's forces. This makes Verlet steady under constraints. When a spring pulls a particle somewhere new, its velocity changes with it. There is no stored velocity that could fall out of step with the position. The particles in [Chapter 11](11-ForcesAndPhysics.md)'s physics world move this way, which is part of why its springs and piles stay calm.

### One second is one second

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/03-MotionAndTime/DeltaTime-dark.jpg">
  <img src="Images/03-MotionAndTime/DeltaTime.jpg" alt="Three dotted strips comparing one second of motion: a fixed step at 60 fps, the same step at 120 fps reaching twice as far, and a deltaTime-scaled step landing in line" width="680">
</picture>

`draw()` runs once per screen refresh, and screens refresh at different rates. So a fixed "move 2 pixels per frame" travels twice as far per second at 120 Hz as at 60. There are two fixes. Derive positions from `time` directly, or scale each step by `deltaTime`, the seconds since the last frame, so per-frame steps become per-second speeds. Simulations sometimes choose a third option on purpose, a *fixed* step per tick. That gives up frame-rate independence so that every run repeats the same way. [Chapter 3](03-MotionAndTime.md) sets the rule, and [Chapter 12](12-FlocksAndSwarms.md) explains the trade.

## Fields and following them

### A field: a question answered everywhere

<img src="Images/14-FieldsAndFlow/Compass.jpg" alt="A grid of small needles whose directions change smoothly across the canvas, showing currents and swirls" width="560">

A field is a rule that answers a question at *every* point of the plane. "How bright here?" gives a number field, and noise is one. "Which way here?" gives a direction field. The field itself is invisible and continuous, and the needles in the picture are only samples of it on a grid. The flow work in [Chapter 14](14-FieldsAndFlow.md) and the terrain in [Chapter 5](05-Noise.md) are the same idea with different questions.

### Following a field: ask, step, ask again

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/14-FieldsAndFlow/TraceSteps-dark.jpg">
  <img src="Images/14-FieldsAndFlow/TraceSteps.jpg" alt="Faint field needles with one walk traced through them: a start dot, then dots connected by arrows stepping along the flow" width="680">
</picture>

To trace a line through a direction field, ask the field which way at your position, take a small step that way, and repeat. That loop is Euler integration, and its one parameter is the step size. Big steps cut corners where the field bends, while small steps follow it closely but need more questions. Every streamline in [Chapter 14](14-FieldsAndFlow.md) is this loop running until it's told to stop.

### Optical flow: a measured field

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/34-Seeing/FlowArrows-dark.jpg">
  <img src="Images/34-Seeing/FlowArrows.jpg" alt="A frame of a dancer, with arrows along both arms pointing opposite ways, a few on one leg and at one foot, and none on his chest" width="680">
</picture>

Every field so far was invented, while optical flow is *measured*. Comparing one camera frame with the next assigns each point an arrow, "which way did the picture move here". The result is a direction field you can trace, carry particles through, or paint with, the same way as a field built from noise. The camera becomes a field generator in [Chapter 34](34-Seeing.md).

## Local rules, global structure

### Neighborhoods: who counts as nearby

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/12-FlocksAndSwarms/RuleAlignment-dark.jpg">
  <img src="Images/12-FlocksAndSwarms/RuleAlignment.jpg" alt="One dark boid among gray neighbors inside a faint circle labeled what it can see, with an arrow showing the average heading it turns toward" width="680">
</picture>

Systems of many creatures need a definition of "nearby". That's a perception radius around each creature. Others inside it count, and others outside it are ignored. Every flocking rule in [Chapter 12](12-FlocksAndSwarms.md) is an average over that circle. The radius changes how the group behaves. Small circles make creatures that jitter on their own, and large circles make them move together.

### Everyone against everyone: counting pairs

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/B-JustEnoughMath/EveryPair-dark.jpg">
  <img src="Images/B-JustEnoughMath/EveryPair.jpg" alt="Three rings of orange dots with a line joining every pair: 5 dots make 10 pairs, 10 dots make 45, and 20 dots make 190, so many lines that the middle turns gray" width="680">
</picture>

Asking every creature about every other one grows fast. A group of n things has n × (n − 1) / 2 pairs, about half of n squared. So twice the things make about four times the pairs. In the picture, 10 dots make 45 pairs, and 20 make 190. Growth like this, with the square of the count, is called **quadratic**. With 300 boids each looking at the other 299, a frame makes about 90,000 looks, two for each of the 44,850 pairs. That is where [Chapter 12](12-FlocksAndSwarms.md) starts before it cuts the plane into cells and asks only the nearby ones.

### Emergence: local rules, large patterns

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/23-GridSimulations/LifeRules-dark.jpg">
  <img src="Images/23-GridSimulations/LifeRules.jpg" alt="Three three-by-three neighborhoods and their outcomes: lonely cells die, comfortable cells live on, empty cells with three neighbors are born" width="680">
</picture>

No cell in the Game of Life knows what the board looks like. Each one asks only its eight neighbors and follows three lines of rules, and gliders, blinkers, and other patterns appear with no one planning them. Other systems work the same way. Truchet tiles in [Chapter 7](07-Tiles.md) agree only at their shared edges, yet loops and mazes appear. Boids in [Chapter 12](12-FlocksAndSwarms.md) know only their circle, yet the flock turns as one. Reaction-diffusion in [Chapter 23](23-GridSimulations.md) asks even less and builds coral. When a pattern looks globally planned, look for the local law first.

### Constraint propagation

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/07-Tiles/TilesAgree-dark.jpg">
  <img src="Images/07-Tiles/TilesAgree.jpg" alt="Enlarged pipe tiles with dots marking their edge sockets, beside a solved grid where every pipe meets a pipe" width="680">
</picture>

Wave Function Collapse solves a grid the way you solve sudoku. Every cell starts as "could be anything", and each placement rules options out of its neighbors, which rule options out of theirs. The solver always settles the most-constrained cell next (the one with fewest options left), because that's where a contradiction would surface soonest. One local law, "edges must match", spread from cell to cell, makes the grid fit together everywhere. [Chapter 7](07-Tiles.md#every-neighbor-must-agree-wave-function-collapse) solves a pipe network with it.

### A parameter space is a map

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/23-GridSimulations/FeedKillMap-dark.jpg">
  <img src="Images/23-GridSimulations/FeedKillMap.jpg" alt="A grid of reaction-diffusion dishes at different feed and kill settings: about half stay quiet, and the rest, in a diagonal band, grow large spots, rings, mazes, and grids of small dots" width="680">
</picture>

Two parameters span a plane, where every pair of settings is a point. A system's behaviors live in *regions*, spots here, mazes there, and dead calm over wide stretches. Render the map, one small run per grid cell, and you can see which settings give which behavior. Interesting settings cluster along the borders between regions. [Chapter 23](23-GridSimulations.md) maps Gray-Scott's feed and kill this way.

## Iteration: a rule applied again

### Recursion: a rule applied to its own output

<img src="Images/13-GrowingThings/TreeByHand.jpg" alt="A bare fractal tree: one trunk splitting into two branches, each splitting again, nine levels deep" width="560">

A branch is a stick with two smaller branches on top, and each of *those* is a stick with two smaller branches on top. A function that calls itself expresses that directly. It needs two rules. Something must shrink on each call, the length here, so each branch is smaller than the one below it. And a floor must say when to stop, a depth counter, or the calls would never end. Since every level doubles the branches, n levels end in 2ⁿ⁻¹ tips, so nine levels make a canopy of 256 tips. [Chapter 13](13-GrowingThings.md) grows this tree from one short function.

### Rewriting growth

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/13-GrowingThings/LSystemExpansion-dark.jpg">
  <img src="Images/13-GrowingThings/LSystemExpansion.jpg" alt="The same plant grammar drawn after one to four rounds of rewriting, growing from a bare stalk to a full fern, letter counts rising to 1551" width="680">
</picture>

An L-system grows a *sentence* first and draws it afterward. Start from an axiom, replace every symbol by its rule, and repeat. The string lengthens exponentially. A turtle then walks the final string, reading symbols as "forward", "turn", "branch". The drawing gets richer only because the sentence got longer, so the plant's shape comes from the rewriting rules. [Chapter 13](13-GrowingThings.md) grows its fern and the garden's row of plants this way.

### Iterated maps: orbits that pile up

<img src="Images/22-IteratedForms/Plates.jpg" alt="Four glowing density plates: folded translucent attractor forms like X-rays of smoke" width="560">

Take a formula, feed it a point, feed it its own answer, and keep going, and the visited points form an **orbit**. For most formulas the orbit shoots away or settles into a dot. For special ones it wanders forever inside a bounded shape, the **attractor**. Plotting a million faint points shows where it goes most often. The plates in [Chapter 22](22-IteratedForms.md) are visit counts drawn as brightness.

### Escape time

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/22-IteratedForms/FractalPair-dark.jpg">
  <img src="Images/22-IteratedForms/FractalPair.jpg" alt="Three panels banded in blue, gold, and cream: the whole Mandelbrot set with a small red circle marking one point on its edge, the Julia set that same point produces, and a deep zoom into the Mandelbrot boundary" width="680">
</picture>

Iterate a formula at every pixel and ask one question. How many rounds until the value flies off past a bound? Points that never escape are painted as the inside of the set. Everywhere else the *count itself* becomes the color. Points that took about the same number of rounds get about the same color, and that is what makes the bands. Which of the formula's two numbers you hold still decides which fractal you get. The marked point in the first panel is the one whose Julia set sits beside it. [Chapter 22](22-IteratedForms.md) shades both this way.

## Shapes as regions

### Set operations on regions

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/15-ShapesAsMaterial/BooleanOps-dark.jpg">
  <img src="Images/15-ShapesAsMaterial/BooleanOps.jpg" alt="A circle and a star combined by union, intersection, subtracting, and symmetricDifference" width="680">
</picture>

Treat shapes as *regions of space* and logic applies to them. Union is "in either", the or. Intersection is "in both", the and. Subtraction is "in one but not the other", the and-not. Symmetric difference is "in exactly one", the xor. [Chapter 15](15-ShapesAsMaterial.md) uses them to build forms no single primitive could draw.

### Offsets: growing and shrinking

<img src="Images/B-JustEnoughMath/Offsets.jpg" alt="A peanut-shaped region with grown outlines around it and shrunken outlines inside, the deepest inset split into two islands" width="680">

Offsetting moves a region's whole boundary by the same distance everywhere, so outward grows it and inward shrinks it. But an inset, an inward offset, is not a scaled-down copy. Narrow passages thin faster than broad ones, and a deep enough inset pinches the waist apart into islands. The split is useful, since it marks where the shape is thin. [Chapter 15](15-ShapesAsMaterial.md) uses offsets for insets, outlines, and plotter work.

### Convexity: the rubber band

<img src="Images/B-JustEnoughMath/Hull.jpg" alt="A scatter of points with the convex hull drawn around them, the points on the band marked as its corners" width="680">

A region is convex if the straight line between any two of its points stays inside it, with no dents. The convex hull of a scatter is the smallest convex region containing all of it. It is the shape a rubber band takes when you let it close around the points. Walking its boundary, you turn in only one direction. [Chapter 15](15-ShapesAsMaterial.md) uses hulls to wrap scatters into clean silhouettes.

### Duality: two readings of one point set

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/15-ShapesAsMaterial/Duals-dark.jpg">
  <img src="Images/15-ShapesAsMaterial/Duals.jpg" alt="The same points shown twice: Voronoi cells partitioning the plane into territories, and the Delaunay triangulation joining natural neighbors" width="680">
</picture>

One set of points supports two structures. Each point's Voronoi cell is the territory closer to it than to any other point. The Delaunay triangulation connects each point to its natural neighbors. They're duals, two answers to "who's near whom", since cells share an edge exactly when their points share a triangle edge. Mosaics use the territories, and networks and meshes use the neighbors. [Chapter 15](15-ShapesAsMaterial.md) builds with both.

## Color and light as numbers

### Numeric vs perceptual mixing

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/02-Color/MixingSpaces-dark.jpg">
  <img src="Images/02-Color/MixingSpaces.jpg" alt="Three rows mixing the same blue and yellow: the RGB row passes through muddy olive, the HSB row detours through green, the OKLab row stays even" width="680">
</picture>

Averaging two colors channel by channel gives the numeric midpoint, and your eye often disagrees with it. RGB's halfway between blue and yellow is a muddy olive. Perceptual spaces like OKLab are laid out so that numeric distance matches *seen* distance, and midpoints in them look like what you'd mix. More generally, whenever math on colors looks wrong, ask which space the math ran in. [Chapter 2](02-Color.md) shows the three rows side by side.

### Perceived brightness

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/PixelSampling-dark.jpg">
  <img src="Images/09-Pictures/PixelSampling.jpg" alt="A photograph of a profile redrawn as a grid of dots, each dot taking its pixel's color and sized by its brightness" width="680">
</picture>

The eye doesn't weigh channels equally. Green counts most, red less, blue least, and the standard weights are 0.2126, 0.7152, 0.0722. Averaging r, g, and b rates a saturated blue as bright as a green, though the blue looks much darker. The weighted sum, luminance, matches what you see. Any effect driven by "how bright is this pixel", like the dot sizes here, needs the weighted version. [Chapter 9](09-Pictures.md) meets this the first time it reads pixels.

### Light and the number stored for it: linear light

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/B-JustEnoughMath/LinearLight-dark.jpg">
  <img src="Images/B-JustEnoughMath/LinearLight.jpg" alt="Left, a curve of the stored number against the light, bowed above the diagonal, marking half the light stored as 0.74 and a stored 0.5 at a fifth of the light. Right, two strips of nine gray steps: equal steps of the stored number darken evenly, and equal steps of light crowd toward white" width="680">
</picture>

A picture file stores a number for each pixel. That number gives more of its steps to dark tones, where the eye notices small changes most. That encoding is **sRGB**. The amount of light itself is called **linear light**, and it is what adds up and averages correctly. The two strips in the picture show the difference. Nine equal steps of the stored number look evenly spaced, while nine equal steps of light leave black at once and crowd toward white. On the curve, half the light is stored as about 0.74, and a stored 0.5 is about a fifth of the light. So Ollin mixes and blends in linear light, and turns the result back into stored numbers at the end. [Chapter 9](09-Pictures.md) averages pixels this way, and [Chapter 19](19-LayersAndEffects.md)'s blend modes add light the same way.

### What a device can show: gamut

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/42-MakingItPhysical/ProofBeforePrint-dark.jpg">
  <img src="Images/42-MakingItPhysical/ProofBeforePrint.jpg" alt="Three panels of one photograph of a woman before a wall of marigolds: as the screen shows it, the same picture proofed for a four-ink press with the orange gone duller, and the gamut check with most of the wall replaced by gray" width="680">
</picture>

The **gamut** of a screen or a printer is the range of colors it can make. The gamut of a color space is the range it can describe. A screen makes color from light, and a press from ink on paper, so each reaches colors the other cannot. The standard gamut for screens is sRGB. Display P3, a wider gamut that many Apple screens show, reaches more saturated reds and greens. Written in sRGB numbers, the way Ollin's `Color` holds it, a color outside sRGB has components below 0 or above 1. The gamut check of [Chapter 42](42-MakingItPhysical.md#seeing-the-print-before-you-print-it-soft-proofs) paints gray over what a press cannot print.

### Blend modes are arithmetic

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/19-LayersAndEffects/BlendModes-dark.jpg">
  <img src="Images/19-LayersAndEffects/BlendModes.jpg" alt="The same two discs composited with normal, add, subtract, multiply, screen, lightest, and darkest blend modes" width="680">
</picture>

Every blend mode is a small per-channel formula for combining the color being drawn with the color already there. Normal covers. Add sums, so light on light gets brighter. Multiply darkens like stacked filter gels, and screen brightens like layered projections. Lightest and darkest keep the lighter or the darker of the two. Once you read them as arithmetic, choosing one stops being trial and error. [Chapter 19](19-LayersAndEffects.md) draws with each of them.

### Density as tone

<img src="Images/25-ParticleSimulations/MillionGrains.jpg" alt="The same particle system at ten thousand, a hundred thousand, and a million grains: sparse embers, a grainy dune, a smooth field of light" width="560">

Draw one faint dot and you see a dot. Draw a million and you see a *material*, because overlapping near-transparent marks add up to smooth tone where they crowd. The count sets the texture, and each tenfold increase trades grain for smoothness. This is how attractor plates, sandpaintings, and [Chapter 25](25-ParticleSimulations.md)'s GPU grains all get their finish. It's also why they need so many particles.

### Light past 1, and bringing it back

<img src="Images/19-LayersAndEffects/ToneClamp.jpg" alt="Three overlapping tinted lamps under the clamp tone map: the overlapping middle blows out to a flat white slab" width="680">

<img src="Images/19-LayersAndEffects/ToneAces.jpg" alt="The same lamps through the ACES film curve: the middle stays bright but keeps its tints, rolling off softly" width="680">

Add enough light and channel values go past 1, brighter than the screen can show. Something must bring them back. **Clamping** chops everything at 1, so overlapping glows flatten into white slabs with hard seams. A **roll-off curve** like film's compresses the highlights gradually, keeping their tints on the way up. [Chapter 19](19-LayersAndEffects.md) covers when each is right.

### Feeding a picture back to itself

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/19-LayersAndEffects/FeedbackSteps-dark.jpg">
  <img src="Images/19-LayersAndEffects/FeedbackSteps.jpg" alt="The same orbiting dot drawn into feedback with different transforms: fade leaves a tail, zoom smears a streak, rotate wraps a swirl, both coil a spiral" width="680">
</picture>

Draw this frame on top of a transformed copy of the *last* frame, and the transform applies again every frame, which is iteration. A gentle zoom becomes an ever-deepening tunnel, a small rotation a tightening swirl, because each frame inherits all the transforms before it. Tiny changes each frame add up to large structure, as the staircase did in [Small moves compound](#small-moves-compound), but in pixels. [Chapter 19](19-LayersAndEffects.md) builds video feedback from it.

## Per-pixel thinking and distance

### A function from position to color

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/18-YourFirstShader/PixelGrid-dark.jpg">
  <img src="Images/18-YourFirstShader/PixelGrid.jpg" alt="The same glow function evaluated coarsely, one answer per grid cell, and at full pixel resolution where the answers fuse into a smooth image" width="680">
</picture>

A shader is one function answering one question, "what color at this position?", asked independently at every pixel. There's no canvas to accumulate onto and no loop you can see. The image is only hundreds of thousands of simultaneous answers, fusing smoothly because the function varies smoothly. Evaluate it coarsely and you can watch the answers before they fuse. [Chapter 18](18-YourFirstShader.md) starts pixel thinking here.

### Signed distance: how far, and which side

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-SculptingWithFields/FieldMap-dark.jpg">
  <img src="Images/32-SculptingWithFields/FieldMap.jpg" alt="A distance field visualized: a melted shape in warm color surrounded by concentric bands of equal distance, with a bold line at zero" width="680">
</picture>

A signed distance field describes a shape by answering, at every point, "how far to the surface?". The *sign* says which side you're on. Negative is inside, positive is outside, and zero is exactly on the boundary. The shape stops being a list of vertices and becomes a question you can ask anywhere. [Chapter 32](32-SculptingWithFields.md) sculpts with shapes described this way.

### Level sets: an edge at a chosen distance

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/18-YourFirstShader/EdgeStep-dark.jpg">
  <img src="Images/18-YourFirstShader/EdgeStep.jpg" alt="The same disc three times: a hard stepped edge, a clean rim from a narrow smoothstep, and a wide soft glow from a broad one" width="680">
</picture>

Given a distance field, a shape is "all points within r". The edge lives where the distance crosses that level, like one contour line on a topographic map. Testing the crossing with `step` gives a hard edge. Testing it with a `smoothstep` window turns the same boundary into a crisp anti-aliased rim, or a wide glow if you widen the window. Every disc in [Chapter 18](18-YourFirstShader.md) is drawn this way, by turning each pixel's distance into how strongly it is painted.

### min melts, max trims

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-SculptingWithFields/MeltStrip-dark.jpg">
  <img src="Images/32-SculptingWithFields/MeltStrip.jpg" alt="Two circles at four smoothing radii: touching hard, necking together, flowing into a peanut, and fused into one capsule" width="680">
</picture>

Combine two distance fields and set operations come from two small functions. `min` keeps whichever surface is nearer, the union. `max` keeps the farther, the intersection, and negating one gives subtraction. Then there is the **smooth minimum**, a min with a blending radius. Where the two fields are nearly tied it dips below both, so the shapes join through a smooth neck instead of only touching. The `k` under each pair of circles is that radius, and the neck widens as `k` grows. [Chapter 32](32-SculptingWithFields.md) sculpts with the smooth minimum.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/B-JustEnoughMath/SmoothMin-dark.jpg">
  <img src="Images/B-JustEnoughMath/SmoothMin.jpg" alt="A plot of distance to the edge along the line through two circles' centers, with inside shaded below zero. The plain min is a W with a sharp peak above zero where the two distances tie. The smooth min with k = 1.4, in orange, follows it on the outer arms and rounds the peak into a hump a quarter of k lower, below zero, so the gap between the circles counts as inside" width="680">
</picture>

This plot follows the line through the centers of two circles. The plain min comes to a sharp peak where the two distances tie, and the smooth min, in orange, rounds that peak off. At an exact tie the dip is a quarter of `k`. It shrinks as the two distances move apart and is gone once they differ by `k`. Here the dip takes the curve below zero, so the gap between the circles counts as inside and fills in.

### Sphere tracing: hop by what the field promises

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-SculptingWithFields/MarchRay-dark.jpg">
  <img src="Images/32-SculptingWithFields/MarchRay.jpg" alt="A ray from an eye crossing in hops that shrink as it passes close to a lower shape and lengthen again, each bounded by a circle showing the distance the field reported, ending on a surface" width="680">
</picture>

To render a distance field, march a ray from the eye. Ask the field "how far to the nearest surface?", and since nothing can be closer than that answer, it is safe to hop that far. Repeat until a hop below a threshold counts as a hit. The hops shrink wherever the ray passes close to a surface and grow again in open space. There are no triangles, only a field asked a few dozen times per pixel. It's how all of [Chapter 32](32-SculptingWithFields.md)'s 3D sculptures reach the screen.

### Folding space

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-SculptingWithFields/DomainFold-dark.jpg">
  <img src="Images/32-SculptingWithFields/DomainFold.jpg" alt="An asymmetric cluster mirrored into a facing pair, the same cluster tiled into a grid, and a petal fanned into a nine-fold rosette" width="680">
</picture>

Instead of copying a shape n times, fold the *question*. Mirror the query point, wrap it into a repeating cell, or rotate it into one wedge before asking the field. The field still holds one shape, and each point asks it only once. The fold makes that shape appear at every point whose folded copy lands on it. A grid of a thousand copies costs the same as one. [Chapter 32](32-SculptingWithFields.md) mirrors, tiles, and fans with it.

## Into three dimensions

### An eye on a sphere

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/26-3DGently/Orbit-dark.jpg">
  <img src="Images/26-3DGently/Orbit.jpg" alt="A small camera on a ring around an object, with a sight line labeled radius, a ground arc labeled azimuth, and a climbing arc labeled elevation" width="680">
</picture>

Three numbers aim a camera at a thing: **azimuth** is how far around, **elevation** how far up, and **radius** how far away. Together they place an eye anywhere on a sphere around the target, which is why orbiting feels like turning an object in your hand. It's the polar-coordinates idea from the circle entries, plus one more angle for up. [Chapter 26](26-3DGently.md) drives its cameras with these three.

### Perspective, and who's in front

<img src="Images/26-3DGently/DepthRow.jpg" alt="Six spheres in a row marching away from the camera, each smaller and partly hidden behind the one before" width="560">

Perspective is one rule, that apparent size falls with distance, so equal spheres shrink as they recede. The **field of view** is the lens angle, wide exaggerating the shrink, narrow flattening it like a telephoto. And notice the hiding, because in 3D drawing order stops deciding who's in front. Every pixel remembers the depth of the nearest surface drawn so far and rejects anything farther, which is the **depth test**. [Chapter 26](26-3DGently.md) uses both.

### Which way a face points: the normal

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/B-JustEnoughMath/EdgesAndNormal-dark.jpg">
  <img src="Images/B-JustEnoughMath/EdgesAndNormal.jpg" alt="A triangle with corners a, b, and c lying in a flat plane seen at a slant. Arrows for b minus a and c minus a leave corner a along two edges, and an orange arrow labeled (b - a).cross(c - a) stands straight up out of the middle of the face" width="680">
</picture>

A flat triangle faces one way, and the arrow standing straight out of it is its **normal**. Light needs it, because a face turned toward a lamp is lit and a face turned away is dark. Two edges from the same corner give it. The cross product of two directions is a third direction at right angles to both. So `(b - a).cross(c - a)` stands straight out of the face. Which side it comes out of depends on the order of the corners. Name them counter-clockwise as you look at the face, and the normal points toward you. In the picture, a, b, and c run counter-clockwise as you look down on the face, so the normal points up. [Chapter 26](26-3DGently.md#what-a-solid-is-made-of-triangles-and-normals) builds its solids from triangles and their normals.

### The pinhole: a pixel plus a depth is a ray

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/35-Depth/Unproject-dark.jpg">
  <img src="Images/35-Depth/Unproject.jpg" alt="A lens with its forward axis, an image plane with a marked pixel, and a dashed ray out to a 3D point. A dotted drop from the point meets the axis square, and the depth is marked along the axis from the lens to that foot. The recovered-coordinates formula sits below" width="680">
</picture>

A camera flattens the world by sliding every point down a ray through the lens. A depth sensor records how far in front of the camera each pixel's surface was. It measures along the camera's forward axis, not along the ray. Unprojection runs the flattening backward. Slide the pixel off the image center, scale by depth over focal length, and the 3D point returns. So a flat photo plus a flat depth map holds the 3D shape of everything the camera saw. [Chapter 35](35-Depth.md) builds its point clouds with this recipe.

### A pose places points in the world

<img src="Images/35-Depth/SweepFuse.jpg" alt="Three tinted captures of a room fused into one cloud, each camera position marked with a small sphere and sight line" width="680">

Points recovered from a camera come out in *its* frame, "two meters ahead of me", wherever "me" was. A **pose** is the transform recording where the camera stood and how it was turned. Applying it carries camera-frame points into one shared world frame. Do that for every frame of a moving sweep and the fragments fuse into a single room, each capture placed where its camera stood. [Chapter 35](35-Depth.md) fuses its scans this way.

### Occlusion voids: what the camera could not see

<img src="Images/35-Depth/CloudLift.jpg" alt="A flat frame stood up into a point cloud viewed from a new angle, with black voids stretching behind the ball and crate" width="560">

A depth image knows only what its rays touched, so nothing measured the space behind each object. View the cloud from where the camera stood and it looks whole. Step to the side and the voids open, holes in the shape of whatever stood in front. Only more viewpoints fill them. [Chapter 35](35-Depth.md) fills them by fusing frames from a moving camera.

## Sound as numbers

### The spectrum

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/37-Listening/Anatomy-dark.jpg">
  <img src="Images/37-Listening/Anatomy.jpg" alt="Three stacked panels from one analyzed instant: the raw waveform, the spectrum with spikes at the kick, bass, and melody, and normalized band bars" width="680">
</picture>

Any sound, however messy, splits into a sum of pure vibrations. The spectrum reports the energy at each frequency in one moment, with bass at the left and treble at the right. To draw it well, you need one more fact. Hearing is logarithmic, and each *doubling* of frequency, an octave, sounds like one equal step. So band bars are usually log-spaced, which gives every octave the same width. If the bars were spaced evenly in hertz, the treble octaves would fill most of the axis. [Chapter 37](37-Listening.md) maps these bands onto pictures.

### Equal steps that multiply: log scales

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/40-MusicByRule/Sonification-dark.jpg">
  <img src="Images/40-MusicByRule/Sonification.jpg" alt="A series of sixteen values shown as bars, then the same series as note positions spread evenly in semitones, again spread evenly in hertz where the high values bunch together near the top, and again snapped so every mark lands on a line of the scale" width="680">
</picture>

Some amounts are felt by ratio rather than by difference. The step from 220 Hz to 440 sounds the same as the step from 440 to 880, though the second is twice as many hertz. A **logarithmic scale** spaces values by their ratios, so each doubling takes the same distance. Spread notes evenly in hertz and the high ones bunch together when you hear them. Spread them evenly in semitones, a log scale, and they sit evenly, as the second and third rows here show. [Chapter 40](40-MusicByRule.md) spreads data this way, and [Chapter 22](22-IteratedForms.md)'s flames take the logarithm of their counts to fit a huge range into one picture.

### Pitch as ratios: octaves, semitones, and cents

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/40-MusicByRule/Tunings-dark.jpg">
  <img src="Images/40-MusicByRule/Tunings.jpg" alt="Seven tunings as rows of ticks on one axis in cents from the root to three times its frequency, with guides at the octave and at three times: equal temperament, just intonation, pythagorean, quarter tones, nineteen, thirty-one, and Bohlen-Pierce, the tick nearest a just major third marked in each octave tuning, with the row's step count and that third's value under its name" width="680">
</picture>

Doubling a frequency raises a note an octave, and every octave sounds like the same step, whatever note it starts on. Equal temperament splits the octave into twelve semitones of one ratio each. That ratio is the twelfth root of 2, about 1.0595, so twelve of them make exactly 2. **Cents** divide each semitone into a hundred, so an octave is 1200 cents. They measure how far apart two tunings put a note. A just major third, the ratio 5/4, is 386 cents, and equal temperament puts it at 400. [Chapter 40](40-MusicByRule.md) builds scales on the semitone and compares tunings in cents.

### A level in steps: decibels

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/B-JustEnoughMath/Decibels-dark.jpg">
  <img src="Images/B-JustEnoughMath/Decibels.jpg" alt="Nine bars from 0 dB down to -48 dB in steps of 6, each about half as long as the one above it: 1.0, 0.501, 0.251, and on down to 0.004. The -12 dB bar is orange, with the note that a mix usually sits below it" width="680">
</picture>

Decibels count a sound's level by ratio, the way a log scale counts pitch. A level in decibels is 20 times the base-10 logarithm of the level as a fraction of full scale. So 0 dB is as loud as a sample can be. Every 6 decibels down about halves the level, and every 20 down divides it by ten. The orange bar in the picture marks -12 dB, and a level you would mix at sits somewhere under it. [Chapter 39](39-MakingSound.md)'s compressor and gate set their thresholds, and its limiter its ceiling, in decibels below full scale.

### Events, not levels

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/37-Listening/BeatTimeline-dark.jpg">
  <img src="Images/37-Listening/BeatTimeline.jpg" alt="Three rows over the same stretch of time: the loudness curve with regular peaks, a beat pulse that jumps up at each detection and fades, and a tick for each beat counted" width="680">
</picture>

Loudness is a level, while a beat is an *event*. You can't find events by watching a level's height, because a held chord stays loud without ever being "a hit". Detection compares each instant with the moment just before. A sudden rise above the recent trend is an arrival, and a short pause after each beat keeps one drum hit from counting twice. So the detector watches change over time rather than loudness. [Chapter 37](37-Listening.md) builds its beat-reactive sketches on that comparison.

---

[Contents](README.md#contents) · Previous: [Appendix A, Just enough Swift](A-JustEnoughSwift.md) · Next: [Appendix C, Coming from p5.js and Processing](C-ComingFromP5.md)
