#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 16</sup>

---

# 16. Curves and figures

<!-- Hook image: the finished sketch, a guilloche or harmonograph plate. Waiting on the finished sketch and its render. -->

Some figures come from a rule rather than a hand. Two sine waves at a ratio weave a Lissajous figure, and a wheel rolling inside a ring draws a spirograph. This chapter turns those rules into calls. A spline bends through your points the way a practiced hand would, and the classic curves come from their formulas. A family of lines traces the curve it leans on, and a road engineer's corner eases into its turn. Any outline comes back from spinning circles, one shape turns into another, and a plate reads only in a mirror. Each call hands back a `Contour` or a `Shape` from [Chapter 15](15-ShapesAsMaterial.md), so a figure fills, strokes, and plots like any other outline.

## A curve that reads as drawn: Hobby's spline

`drawCurve` decides its curve one point at a time. At each point it takes a direction from the two neighbors, and that is all it knows. Space the points evenly and the result looks fine. Put two points close together and a third far away, and the curve swells at the near pair and runs flat across the gap.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/16-CurvesAndFigures/HobbyFit-dark.jpg">
  <img src="Images/16-CurvesAndFigures/HobbyFit.jpg" alt="Three panels of the same six dots, two of them close together: joined by straight segments, threaded by the default curve, which bulges at the close pair and flattens after it, and threaded by Hobby's fit, which bends evenly through every dot" width="680">
</picture>

The right panel asks for a different fit. `spline: .hobby` solves every direction at once, so the bend arriving at a point matches the bend leaving it. This is John Hobby's spline, the curve inside the METAFONT and MetaPost typesetting programs. It is close to what a practiced hand draws through a few dots. Four dots on a circle come out as that circle.

```swift
drawCurve(dots, spline: .hobby)                       // the natural fit
drawCurve(dots, spline: .hobby(tension: 2))           // pulled toward the straight lines
drawCurve(dots, closed: true, spline: .hobby)         // a loop you can fill
```

Two settings shape it. `tension` pulls the curve toward the straight lines between the points, with 1 as the natural fit and 2 hugging them. `curl` says how the ends of an open curve bend: 1 gives an end the same bend as its neighbor, and 0 lets it run straight out. When you want the Béziers themselves, `HobbySpline(through:)` is the typed form. Its `segments` are the cubic curves the fit chose, control points included, and its `path` is the same curve as a `Path`.

## Curves you can write down

[Chapter 15](15-ShapesAsMaterial.md#contours-shapes-and-holes)'s leaf was drawn by hand, one control point at a time. Some outlines don't need that, because somebody already found the formula, and the formula is shorter than the drawing. Nine of them come with Ollin, all deterministic and none of them touching randomness.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/16-CurvesAndFigures/ClassicCurves-dark.jpg">
  <img src="Images/16-CurvesAndFigures/ClassicCurves.jpg" alt="Nine panels: a sunflower seed spiral, a woven Lissajous figure, a five-petal rose, a squircle holding a pinched four-point star, a looping spirograph curve, a decaying harmonograph tangle, a seven-lobed supershape star, a braided guilloche rosette of wavy rings, and a rough polygon shown beside its smoothed version" width="680">
</picture>

```swift
phyllotaxis(count: 520, spacing: 7)                   // [Vector2]
lissajous(a: 3, b: 2, width: 200)                     // Contour
rose(n: 5, radius: 100)
hypotrochoid(ring: 84, wheel: 33, pen: 26)
superellipse(width: 200, n: 4)                        // the squircle
supershape(radius: 100, m: 7)
guilloche(rings: 36, innerRadius: 90, outerRadius: 320,
          bumps: 8, amplitude: 24)                    // [Contour], one per ring
```

**Phyllotaxis** is how a sunflower packs its seeds. Seed number `i` sits `i` golden angles around the center and `spacing * sqrt(i)` out from it. That one rule fills the disk evenly at any count. The golden angle, about 137.5 degrees, is doing all the work here. It's the fraction of a turn that never lines back up with itself, so no seed ever lands behind an earlier one. Nudge the angle by a hundredth of a degree and the whole thing collapses into spokes. Try it once just to watch it happen.

**Lissajous figures** are what two sine waves make when one drives the horizontal and the other the vertical. A point swings side to side `a` times while it bobs up and down `b` times. The ratio between them is the whole character of the figure. **Roses** come from one polar equation, `r = radius * cos(k * theta)`. An odd `n` gives you `n` petals, and an even `n` gives you `2n`.

**Hypotrochoids and epitrochoids** are the toy gear set from childhood. A wheel rolls around a ring, inside for the first and outside for the second. A pen sits in a hole `pen` units from the wheel's center. Whole numbers for the gears are what guarantee the pen eventually returns to where it started. Ollin samples exactly the number of laps that closes the curve once, so nothing is drawn twice.

**Superellipses** put the whole family between diamond and rectangle on one exponent. `n: 2` is the ellipse, `n: 4` the squircle of app icons, `n: 1` the diamond, and lower values pinch into a four-point star. Animate `n` and a mark breathes between round and square; the `Shapes/Superellipse` example sweeps a whole wall of them. The **supershape** generalizes further. One formula with a lobe count `m` and three shaping numbers covers stars, flowers, gears, and organic blobs. It's the same formula behind the 3D `Mesh.supershape`. Keep `m` a whole number, since the curve only closes in one turn for integer `m`. The `Shapes/Supershape` example morphs one through its family.

**Guilloche** is the engraved ornament on watch faces and banknotes, and it too was a machine. A lathe's cams rocked the cutter while the piece turned: one wavy ring per pass, the piece nudged a hair between passes. `guilloche` returns those rings as a list of contours. The nudging is the `twist:` parameter, and it's what braids neighboring rings into the woven moiré. Stack a coarse `Rosette` and a fine one and the ripple rides the wave. The `Patterns/Guilloche` example lets the braid crawl.

**Harmonographs** were real Victorian machines: pendulums swinging under a pen, drawing while they slowly died away. Ollin's takes a list of pendulums per axis, each with its own amplitude, frequency, phase, and damping. Near-but-not-quite matching frequencies are where the good tangles come from.

The last panel isn't a curve at all. `smoothed(iterations:)` is Chaikin's corner cutting. It repeatedly replaces every corner with two points partway along its edges. Do it three or four times and a rough polygon becomes a soft curve. Open contours keep their exact endpoints, so a line still starts and ends where you put it.

One habit applies to all of them. These come back in their own coordinates, and the way to fit one to your canvas is `fitted(points, in: rect)`, which scales the *points*. Reaching for `scale()` instead would scale your stroke width along with the geometry, which is rarely what you want on a drawing made of lines.

## A walk that comes home

Not every figure worth drawing has a formula. Here is one with a rule instead, and the rule is short enough to say out loud. Step one length, turn a quarter turn, step two lengths, turn again, and keep going up to some number. Then start the whole run over.

```swift
let figure = spirolateral(order: 7, step: 26)
drawPolyline(fitted(figure.points, in: bounds.inset(by: 60)), closed: figure.closes)
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/16-CurvesAndFigures/Spirolaterals-dark.jpg">
  <img src="Images/16-CurvesAndFigures/Spirolaterals.jpg" alt="Three panels on paper. On the left an orange spiral of seven growing steps. In the middle the same orange run inside a black square knot made of four of them. On the right a walk of eight steps repeated three times, marching off toward the bottom right instead of closing" width="680">
</picture>

That is a spirolateral, named by Frank Odds in 1973. The interesting part is that it sometimes comes home and sometimes doesn't, and you can tell which before you draw a single line.

Follow one run and you turn seven times, which leaves you facing a quarter turn from where you started. So the second run is the first one turned a quarter turn, and the third is turned a half. After four runs you have gone all the way around and closed the ring. That is the middle panel, with the first run left in orange inside it.

Now try an order of eight. Eight quarter turns is two full turns, so the run ends facing exactly the way it set off. Every repeat leaves in the same direction as the last, and the walk marches off the page forever. **At a quarter turn, the orders that never close are the multiples of four, and nothing else.** `closes` tells you, `closingRepeats` says how many runs it takes, and `center` is the point the figure turns about, which is nil when there isn't one.

One warning before you animate it: the turn has to be an exact fraction of a full turn. Sweep it smoothly from a quarter to a third and nothing in between closes at all. Animate the order instead. Or hand `reversed:` a set of steps whose turns go the other way, which changes both the figure and the count.

## The curve a family of lines draws

Some curves are not drawn at all. They are what a moving line leans on.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/16-CurvesAndFigures/RaysLeanOnACurve-dark.jpg">
  <img src="Images/16-CurvesAndFigures/RaysLeanOnACurve.jpg" alt="Two panels. On the left forty tangent lines of a circle, with the circle they lean on picked out in orange. On the right a circular cup lit from outside, its bounced rays crowding along an orange caustic curve with a cusp" width="680">
</picture>

```swift
for run in envelope(of: rays) { drawPolyline(run.points) }
```

Take the tangent lines of a circle, as on the left. No line is the circle, and every line touches it once. Ask where each line crosses the next and those crossings *are* the circle. That is an **envelope**, and the crossing-your-neighbor construction is the whole method.

The right-hand panel is the same idea wearing its most famous hat. Light crosses a cup, bounces off the far wall, and the bounced rays crowd along a bright curve. That curve is their envelope, and it is called a **caustic**. You have seen it in the bottom of a mug on a sunny morning.

```swift
let rays = reflectedRays(off: wall, from: .point(lamp))
drawCaustic(off: wall, from: .point(lamp))
```

Two answers tell you whether your picture came out right. A circle lit from far away draws a **nephroid**, with two cusps, reaching from half the radius out to the mirror. A circle lit from a point on its own rim draws a **cardioid**, with one. A source at the dead center gives no curve at all, since every ray comes straight back.

One trap makes a picture look broken rather than wrong. **Hand in only the stretch of wall the light reaches.** A whole circle has two families of bounces, the near side and the far side, and they lean on different curves. Filtering a ring down to the lit part also has to keep it *unbroken*: if the lit stretch wraps around the end of your array, the two ends land next to each other and the lines between them are not rays at all.

`refractedRays` does the same job for light bending into glass instead of bouncing off it, and a ray that meets the surface too steeply is left out rather than faked, which is total internal reflection doing what it does.

The same idea with circles instead of lines is how a wave gets where it is going. Every point of a wavefront sends out a little wave of its own, and a moment later the front is the curve those wavelets lean on. That is Huygens' construction, from 1690, and `huygensFront(from:advancing:)` is it.

```swift
for step in stride(from: 30.0, through: 400, by: 30) {
    for run in huygensFront(from: shore, advancing: -step) { drawPolyline(run.points) }
}
```

It is not the same as moving every point sideways, and the difference is the whole point. Where the front curves back on itself the sideways move folds over, and the folded piece is *inside* its neighbors' wavelets rather than on the front. Those pieces are dropped, so the front tears and comes to a sharp point. That point is a focus, and it appears exactly when the front has travelled the radius the curve bends at. The `Patterns/Wavefront` example sends a wave off a headland and lets it happen.

## A corner a car could take

Chaikin rounds a corner, and for most drawings that is the end of it. But a rounded corner can be asked a second question, and it is the one a road engineer asks. Not "is the outline smooth" but "is the *turning* smooth".

They are not the same question. An arc is a perfectly smooth outline, and it is also a corner where the bend arrives out of nowhere. Along the straight you are not turning at all. One step later you are turning at `1 / radius`, and there was no room in between for anything else to happen.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/16-CurvesAndFigures/ClothoidCorner-dark.jpg">
  <img src="Images/16-CurvesAndFigures/ClothoidCorner.jpg" alt="The same right-angle corner rounded two ways. On the left one arc, and under it a graph of the bend that is a flat-topped rectangle with vertical sides. On the right the corner eased at both ends, and under it the same graph as a trapezoid that ramps up, holds, and ramps back down" width="680">
</picture>

Ollin has the curve that answers it. A **clothoid** is written as a turn rate rather than as a position. Face a direction, and turn a little more sharply with every step you take. Its bend is then a straight line in the distance traveled, which is exactly the ramp the left-hand graph is missing.

```swift
let route = clothoidCorners(waypoints, radius: 90, easement: 70)
drawPolyline(route.contour().points)
```

Every corner becomes three pieces: a clothoid bending in, an arc, and a clothoid bending back out. `easement` is how much travel the bend is given to arrive over. Set it to zero and you have the plain arc back, which is what the left panel is.

This is how roads, railways, and roller coasters are laid out. It is part of why a motorway curve feels different from a curve drawn with a compass. It matters again to anything that physically follows your drawing. A pen plotter, a laser, or a cutting head has to slow down for a direction that changes all at once. An eased corner gives it nothing to slow down for.

Two more things fall out of the same curve. `clothoidSpline(through:)` fits one clothoid to each gap in a list of points, so the path goes through every point and never kinks at one. And a whole chain of them reads as a single path measured by length, which is what makes it drivable:

```swift
let along = (time * 260).truncatingRemainder(dividingBy: route.length)
if let here = route.point(at: along),           // where you are
   let facing = route.heading(at: along),       // which way you face
   let bend = route.curvature(at: along) {      // where the wheel is
    // draw the vehicle at `here`, turned to `facing`
}
```

The three reads are optional, because a distance past the end of the chain has no point on it. `along` never goes past the end here, since it wraps on `route.length`, so one `if let` over the three is the whole ceremony.

Steady time in, steady ground covered. Read `curvature(at:)` while you drive and you are holding the steering wheel. That is the whole idea again, from the driver's seat rather than the graph's.

Drawn whole, the curve is the Cornu spiral: two arms winding into two eyes they never reach, because the bend keeps on growing. `eulerSpiral(size: 700, turns: 2.5)` returns it as points.

## Circles all the way down

Here is a fact that sounds false. Any closed outline at all, however irregular, is exactly a sum of circles. Each spins at a whole-number rate, riding on the tip of the one before it. That's

Fourier's idea, and Ollin will do the decomposition for you.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/16-CurvesAndFigures/EpicycleTerms-dark.jpg">
  <img src="Images/16-CurvesAndFigures/EpicycleTerms.jpg" alt="Three panels rebuilding the letter g from spinning circles: with three circles it is a wobbly loop, with twelve it is recognizably the letter, and with sixty-four it is exact, with the faint construction circles visible in each" width="680">
</picture>

```swift
let chain = Epicycles(outline, samples: 512)
drawPolygon(chain.path(samples: 600, terms: 64).points)   // the reconstruction
drawEpicycles(chain, at: phase, terms: 64)                // the construction itself
```

`terms` is the dial, and it takes the largest circles first. That ordering is what makes the figure above work. Three circles already give you the outline's gross shape, because the big circles were always doing most of the work. The rest are adding detail. At the full term count the reconstruction is exact, not approximate.

Two ways to use it. `path(samples:terms:)` hands you the whole traced outline as geometry. A deliberately under-termed version of a shape is then a way to *simplify* it that keeps it smooth. The call `point(at:terms:)` gives one position, which is what you animate. `drawEpicycles` draws the whole nest of circles and spokes at a moment, so the machine is visible. The `Motion/Epicycles` example traces a whale that way, with the pen leaving a fading trail.

## One shape becoming another

Two shapes and a number between them gives you every shape in between.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/16-CurvesAndFigures/MorphSteps-dark.jpg">
  <img src="Images/16-CurvesAndFigures/MorphSteps.jpg" alt="Five panels of a solid orange star turning into a ring with a hole, the star's points retracting and the hole opening from nothing in the middle" width="680">
</picture>

```swift
var morph: ShapeMorph?

override func setup() {
    morph = ShapeMorph(from: star, to: ring)
}

override func draw() {
    if let morph { drawShape(morph.shape(at: pingPong(over: 4))) }
}
```

Build it once and keep it. Working out which part of the first shape corresponds to which part of the second is the expensive step. Doing it in `setup()` makes every frame afterward cheap. At `0` and `1` you get your original shapes back exactly, not a re-derived approximation of them.

The holes are the part to watch. When the two shapes don't have the same number of contours, the unmatched ones grow out of their own center, or shrink into it. That is why the ring's hole opens from nothing in the middle, instead of flying in from off-screen. Timing lives outside the morph, so pass it an eased phase, a `pingPong` for there-and-back, or a `Timeline`'s progress. For a one-off blend with no state to keep, `star.morphed(toward: ring, 0.5)` gives you the single shape.

## A drawing only a mirror can read

Every transform so far has kept the drawing readable. This one throws that away on purpose.

Wrap a picture around a mirrored cylinder standing on your page. Then work out where each point of it must be *drawn* for the reflection to put it back where you wrapped it. What lands on the page says nothing. Stand the cylinder on the circle and put your eye in the one place the map was told about. The smear gathers itself into the picture, upright on the glass.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/16-CurvesAndFigures/MirrorReads-dark.jpg">
  <img src="Images/16-CurvesAndFigures/MirrorReads.jpg" alt="Two panels. On the left, a ring of stretched, reversed letters curling around an empty circle, unreadable. On the right, a panel showing the word MIRROR standing upright and slightly curved, which is what the eye receives from that same ring" width="680">
</picture>

Painters were doing this in the 1600s, ruling the construction out by hand. Nothing is undone in software here either. The plate is a real drawing, and the reflection does the reading.

```swift
let mirror = Anamorphosis(
    center: Vector2(540, 480), radius: 130,      // where the cylinder stands
    eye: Vector3(540, 910, 250),                 // and where you will be
    picture: Rectangle(center: Vector2(540, 480), width: 280, height: 70),
    lift: 40
)
let plate = mirror.plate(of: emblem)             // an ordinary Shape in, an ordinary Shape out
drawShape(plate)
drawCircle(mirror.footprint)                     // the circle to stand it on
```

`eye` is a `Vector3` because the height matters as much as the distance. The rule behind every mark is one ray run backwards: from the eye to the glass, bounce, and follow the bounce down to the page.

Two things follow from that, and you can read both off the picture. The marks land on the near side, between the glass and you, so you read the plate by looking *over* it at the mirror. And they spread as they go out. A point higher up the picture is reached by a shallower bounce, and a shallower bounce travels farther before it meets the page.

There is a limit, and it is better met before you compose than after. Two tangent lines run from your eye to the cylinder, and everything past them is turned away. So the picture has an arc it must live inside. `mirror.widestPicture` is that arc in your own units and `mirror.fits` is the yes or no. Standing closer takes some of it away. That is the trade the whole piece is made of: the nearer the viewer, the less of the mirror they can use.

`plate(of:)` takes a point, a `Contour`, or a `Shape`. The map bends straight lines, so a contour is walked at an even spacing first and the bend is carried by the extra points. What comes back is ordinary geometry, so a plate prints. A real mirrored tube standing on a real printed circle is the whole apparatus.

<!-- Putting it together: the finished sketch goes here: a guilloche or harmonograph plate, built from this chapter's steps, with its full listing. -->

## Where this comes from

The named curves each carry a person with them. Lissajous figures are Jules Antoine Lissajous's, from 1857, though Nathaniel Bowditch drew them first. Roses are Guido Grandi's rhodonea, named in the 1720s for their resemblance to flowers.

The trochoids are the mathematics behind the Spirograph toy. The harmonograph was a real Victorian instrument, a pen hung from swinging pendulums. And the sunflower packing is Helmut Vogel's 1979 model.

Spirolaterals were named and studied by Frank Odds in 1973, and Harold Abelson and Andrea diSessa set them as a turtle-geometry exercise in 1981. The curve a family of lines leans on is classical differential geometry, and the caustics of a circle were worked out in the seventeenth century, with Ehrenfried Walther von Tschirnhaus and Christiaan Huygens among the names attached.

Corner cutting is George Chaikin's, from 1974.

The clothoid was described by Leonhard Euler in 1744, and rediscovered by Augustin-Jean Fresnel, whose integrals give its shape. Arthur Talbot brought it into railway practice in 1890. The fit that joins two points and two headings follows Enrico Bertolazzi and Marco Frego's 2015 reduction.

Mirror anamorphosis is older than the mathematics that describes it: Renaissance workshops ruled the construction out by hand, and Jean-Francois Niceron wrote it down in 1638.

Drawing with epicycles goes back through Fourier to the Greek astronomers, who used circles riding on circles to explain the wandering of the planets.

Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Fourier epicycles](../Docs/Drawing/Epicycles.md): the `Term` list, the joint and path readers, and resampling requirements. The [`Examples/Motion/Epicycles`](../Examples/Motion/Epicycles/Sketch.swift) example traces a whale with them.
- [Shape morphing](../Docs/Drawing/Morphing.md): the correspondence rules, `spacing`, and `Tweenable` geometry inside a `Timeline`. The [`Examples/Motion/Morphing`](../Examples/Motion/Morphing/Sketch.swift) example loops a star through a blob and a donut.
- [Classic curves](../Docs/Drawing/Curves.md): every parameter of all nine, including what closes each curve exactly once.
- [Envelopes and caustics](../Docs/Drawing/Envelopes.md): `envelope` and the `Ray2` it works on, reflected and bent rays, and the two caustics of a circle worth recognizing.
- [Anamorphosis](../Docs/Drawing/Anamorphosis.md): the setup, the map for points, contours and shapes, what an eye can see of a cylinder, reading a plate back, and standing a real mirror on a printed one. The [`Examples/Patterns/Anamorphosis`](../Examples/Patterns/Anamorphosis/Sketch.swift) example spells a word around one and shows what the eye receives.
- [Clothoid](../Docs/Drawing/Clothoid.md): the four numbers, the easement, the single curve that fits two points and two headings, corner rounding, and driving a chain by distance.

---

[Contents](README.md#contents) · Previous: [Chapter 15, Shapes as material](15-ShapesAsMaterial.md) · Next: [Chapter 17, Marks and media](17-MarksAndMedia.md)
