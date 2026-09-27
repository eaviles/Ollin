#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 31</sup>

---

# 31. Traced light

<img src="Images/31-TracedLight/LamplitRoom.jpg" alt="A room lit by one pendant lamp that flares in the lens: a waxed brown floor, a terracotta wall and a teal one, a glass ball on a white plinth focusing the lamp into a bright spot inside its own shadow, and a red ball beside it" width="560">

A 3D frame usually stops light at the first thing it hits. This chapter follows it further. Mirrors show what the camera can't see, light bounces from one wall onto the next, and glass focuses bright patterns onto a floor. A still can be traced path by path until it looks photographed. Then come the frames themselves: edges that settle, highlights that hold still, the streak a shutter leaves, and what a real lens adds. Last are the ways to render fewer pixels and fewer frames when a scene gets heavy. Each is a line or two added to a scene you already have. The chapter ends in a lamplit room, lit by one swinging lamp. Its light bounces off the walls, shows in the waxed floor, is focused by a glass ball, and flares in the lens.

## Mirrors that see off screen: ray-traced reflections

A scene's depth layer, from [Chapter 25](25-3DGently.md#what-the-depth-buffer-is-for), feeds one more effect, and it is where reflections start.

**`.screenSpaceReflections`** makes a floor glossy by reflecting the scene in it, and it runs on any Mac. It has one limit worth understanding rather than being surprised by. It reflects what is on the screen, and a picture does not contain the back of anything. Where the true reflection would be of a surface the camera cannot see, such as the underside of a ball resting on a floor, it can only approximate. That shows as a soft zone right at the contact. A touch of `roughness` hides it, and [Chapter 30](30-SculptingWithFields.md) has the exact alternative.

`rayTracedReflections()` is the answer to that, and it works differently enough to be worth understanding.

Instead of searching the finished picture for what a reflection should show, it fires an actual ray off each reflective surface. It asks what the ray hits, using the real geometry. Off-screen objects appear. Hidden faces appear. The underside of a ball resting on a mirrored floor appears, because the ray goes there and looks. It integrates into the environment lighting rather than sitting on top as a post-process. A traced hit simply replaces what the environment would have contributed, and a ray that hits nothing shows the sky.

<img src="Images/31-TracedLight/TracedMirror.jpg" alt="An orange sphere and a pale box on a nearly polished dark floor under studio lighting, with a blue sphere overhead cropped by the top of the frame. Both floor reflections are sharp, and the box's shows its underside" width="560">

Look at the box's reflection rather than the sphere's. You can see its underside, the face resting toward the floor, which the camera never sees from where it stands. That face exists in the geometry, so a ray sent to it comes back with an answer. A screen-space reflection has no pixels of that face to borrow, because the picture simply doesn't contain it, and has to approximate.

```swift
environment(.studio)
rayTracedReflections()          // needs a ray-tracing GPU; a no-op elsewhere
material(.metal(roughness: 0.08))
```

Three conditions come with it. It needs an `environment(_:)` to fall back to, it only affects physically based materials, and it needs a GPU that can trace rays. Every Apple silicon Mac can. The M3 generation and later do it in dedicated hardware and earlier chips do it in software, so the same scene costs more frames on an M1 or M2. Anywhere it isn't available the call does nothing at all rather than failing. A sketch that asks for it still runs and simply looks plainer, which is why you can leave the call in.

Only the *reflecting* surface has to be physically based. What it shows can wear any finish you like. A ray shades whatever it hits the way that surface shades head on. A cel-shaded prop keeps its hard bands in the mirror, and a Gooch one its warm-to-cool ramp.

There's one behavior worth expecting rather than being puzzled by. Reflections are traced with a limited number of rays and cleaned up over time while the camera holds still. So a fresh view can look faintly noisy for a moment before it settles. Exports don't have that problem, because there Ollin averages several rays within each frame instead of across frames. That's also why a video export can't flicker.

Tracing a mirror is the most expensive thing in a reflective frame, so there is a dial for it, the same kind shadows have. If a mirrored scene stutters while you sketch, `reflectionQuality(.performance)` traces the reflection at half size and stretches it back. On an M2 that takes the example scene from 45 frames a second to 71. You pay for it where you would expect. A curved mirror gets blockier, and fine detail inside a mirror image softens. What you do not pay is the mirror itself: each surface keeps its own reflection right up to its edge. Exports take the fine end on their own.

There is a second dial, and it is about distance rather than detail. A traced reflection walks two surfaces by default: the one the ray finds, and whatever *that* surface reflects, which is the sky. A single mirror never needs more than that. Stand two mirrors face to face, though, and you have asked for something endless. **A tunnel of images is only as deep as the chain you paid for.** At two surfaces the tunnel stops at the third door and puts the environment in it:

<img src="Images/31-TracedLight/MirrorCorridor.gif" alt="A corridor of two facing mirrors with an orange block in it, from a camera that never moves, stepping through reflection chains of two, three, four, and five surfaces. At two the far panel of the mirror is filled with sky. Each step after that opens one more receding frame, with another small image of the block in it" width="560">

`reflectionBounces(4)` opens two more doors, and each step you add costs one more traced ray for every reflected pixel. The images dim quickly, because each mirror passes on only the fraction it reflects. Three or four is usually the end of what you can see. The count is clamped to the range 2 to 8, and it is persistent, so set it once.

### The floor that shows the room

There is a third dial, and it is the one that changes the most pictures. Every reflection so far has been a mirror's. A mirror sends every ray one way, so a single traced ray describes it exactly. Brushed steel does not. A satin floor, a waxed table, a bead-blasted panel: each sends every ray a slightly different way. What you see in one is the average of all of them.

One ray cannot be an average. So on its own, Ollin answers roughness by fading that ray into the blurred environment. The rougher the surface, the more of the environment you get. Stand a satin floor in a red room and it reflects a gray sky. **A rough surface should show you a blurred room, not a blurred sky.** `glossyReflections()` is the call that gets you one:

```swift
rayTracedReflections()
glossyReflections()                    // needs a ray-tracing GPU; a no-op elsewhere
material(.metal(roughness: 0.3))
```

<img src="Images/31-TracedLight/SatinFloor.gif" alt="A satin metal floor between a red wall and a blue wall, with four balls from mirror to nearly matte, from a camera that never moves, switching between one mirror ray and the spread lobe every two seconds. With one ray the floor holds a sharp image of the balls and fades to gray; with the lobe the reflections are soft, the walls' colors spread across the floor, and the two rougher balls take the room's colors" width="560">

Watch the floor rather than the balls. With one ray it holds a hard little copy of each ball, which no satin floor has ever done. The walls arrive as a wedge with a crisp edge. With the lobe the reflections soften into the floor and the two colors spread out across it. The mirror ball on the left does not change at all, because a mirror was never the problem.

Two things are happening for you here. Each ray now leaves along a slightly different direction, picked from how rough the surface is. Each pixel also borrows the rays its neighbors just sent. That borrowing is the part that matters. A handful of scattered rays on their own would look like glitter, and the sharing is what turns them into a picture. A polished surface ignores its neighbors' rays automatically, which is why the mirror ball stays sharp with nothing said about it.

It reaches up to about three-quarters rough and hands back to the environment past that. By then the blur is wide enough that the sky really is the honest answer. It costs one more pass over the picture, so keep it for the sketches whose surfaces are actually satin. Like the others, it is persistent and does nothing at all on a GPU that cannot trace, so the call can stay in.

Meshes and fields differ in a few places over which finish applies to which. The [combining reference](../Docs/3D/Combining.md) is the table for that.

## Light that bounces: global illumination

Every light since [Chapter 25](25-3DGently.md) worked the same way. It left the lamp, hit a surface, and stopped. Real light doesn't stop. The sun patch on your floor lights your ceiling from below. A red wall tints the white shelf beside it, and the dark side of everything in the room is filled in by light arriving second-hand. **Direct light only ever explains half a picture.** The other half has bounced at least once. One call turns that half on:

```swift
spotLight(.white, at: Vector3(0, 3.8, 0), direction: Vector3(0, -1, 0), intensity: 3)
castShadows()
globalIllumination()        // needs a ray-tracing GPU; a no-op elsewhere
```

<img src="Images/31-TracedLight/BouncedLight.jpg" alt="A room with an orange left wall, a teal right wall, and white floor, ceiling, and back, holding a white box and a white sphere. The only light is a spot pool on the floor, but the whole room is softly lit: the ceiling glows from below, the walls carry their colors into the room, and the sphere's shadow side is filled with pale floor-light" width="680">

Everything in this room except the pool itself is bounce. The spot never touches the ceiling, and the ceiling glows anyway, lit from below by the floor. The walls were never lit directly either, yet the orange one reads orange, because floor-light reached it and came back stained. The sphere's shadow side isn't black. It's filled by the bright floor beside it. Cover the figure with your hand except the pool, and you're looking at what the direct-only version showed.

Under the hood, Ollin scatters a grid of invisible **light probes** through the scene. Every frame it re-asks them what light is arriving from every direction, by firing rays at the actual geometry. Lit surfaces then read their neighborhood's probes for the light the lamps couldn't deliver directly. Because the probes are re-traced live, a swinging lamp or a moving shape keeps bouncing correctly, and nothing is baked ahead of time. Three practical notes fall out of that:

- **It composes with what you already know.** With `castShadows()` on, bounce respects the same shadows the direct light does, so light doesn't sneak through a wall on the second hop (a sealed box stays dark inside). With an `environment(_:)`, the probes carry the sky in *with occlusion*, so a room lit through a doorway darkens with distance from the door instead of glowing evenly, which the plain environment ambient can't do.
- **It's the diffuse half.** Matte surfaces gather bounce; a mirror's sharp image of the scene is `rayTracedReflections()`, the specular half from the previous section, and the two are made to run together.
- **`intensity` is an artistic dial, not a lie detector.** `1` is physical. The figure runs `1.6` because the picture wanted it, and that's the whole job of the parameter.

Like the reflections, the probe field settles over a few frames live, so a sudden lighting change fades in the way your eyes adjust. It converges fully inside each frame on export, so a still or a video reproduces exactly. And like the reflections, it needs a ray-tracing GPU and does nothing at all elsewhere, so the call can stay in the sketch.

The [`GlobalIllumination` example](../Examples/3D/Lighting/GlobalIllumination/Sketch.swift) is this room with the lamp swinging. The space bar toggles the bounce, which is the clearest before-and-after you can give yourself. The bounce follows the picture wherever it goes. A wall seen *inside a mirror* carries the same second-hand light as the wall itself, and a scene drawn into a layer for depth of field gathers it like the canvas does. If a heavy scene stutters while you sketch, `globalIlluminationQuality(.performance)` trades a grainier bounce for frame rate, the same kind of dial shadows have. Exports always take the fine end on their own. Scale isn't your problem either. On a terrain-sized scene the scene-wide probe grid would spread too thin, so finer probe volumes gather around the camera on their own and travel with it. The bounce near what you're looking at stays room-quality with nothing to configure.

## The light the glass takes, given back: caustics

Set a real glass on a sunlit table and look next to it. Inside its shadow there's a bright loop, brighter than the open table around it. The glass didn't destroy the light it blocked. It bent all of it into one small place. That focused light is a *caustic*, and one call turns it on:

```swift
directionalLight(.white, direction: Vector3(-0.3, -1, -0.2))
castShadows()
caustics()

fill(.white)
material(.glass(thickness: 1.8))
drawSphere(radius: 0.9)               // its bright spot lands inside its own shadow
```

<img src="Images/31-TracedLight/CausticLight.jpg" alt="Two glass spheres and a chrome ring on a sunlit matte table. The clear sphere throws a tight bright spot inside its own shadow, the bottle-green sphere throws a green-tinted one, and the ring, lying almost flat, folds light into a radial fan across its middle" width="680">

**A shadow is where light couldn't go; a caustic is where it went instead.** The renderer traces thousands of little parcels of light from the sun, through every glass and every polished metal, and draws each one where it lands. A clear ball throws a tight hot spot. A bottle-green ball throws a green one, because the parcels crossed the green interior. A chrome ring folds light into the curved fan a wedding band leaves beside itself. Nothing needs declaring: whatever transmits or mirrors, casts.

Two parameters. `caustics(intensity: 1.6)` turns the patterns up past physical, for drama. `caustics(dispersion: 1)` gives every parcel its own wavelength, so a prism's edge fans into a real rainbow and even a plain sphere's spot picks up red and blue fringes. If the patterns look coarse, `causticsQuality(.detail)` traces more parcels; exports always use the fine setting on their own. Like the other traced light, it needs a Mac that traces and quietly does nothing elsewhere, so the call can stay in the sketch. The [`Caustics` example](../Examples/3D/Lighting/Caustics/Sketch.swift) is the sunlit-table scene: two glass spheres and a chrome ring, with the space bar to compare.

## Edges that settle: temporal anti-aliasing

The last two sections shared a trick worth naming. Render a slightly different estimate every frame, and average. The reflections jitter their rays, and the probes rotate their fans. `temporalAntialiasing()` applies the same idea to **every edge in the 3D picture**:

```swift
camera(.orbiting(target: .zero, radius: 8, azimuth: time * 0.05, elevation: 0.3))
temporalAntialiasing()      // any Metal GPU; edges refine as frames accumulate
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/31-TracedLight/SettledEdges-dark.jpg">
  <img src="Images/31-TracedLight/SettledEdges.jpg" alt="Two magnified crops of the same exported pixels: four thin bright rods at shallow tilts on black. On the left, with temporal anti-aliasing off, each rod is a run of uneven gray dashes with visible steps. On the right, with it on, each rod is one even line" width="680">
</picture>

Every 3D frame already takes eight samples per pixel, but always at the *same* eight positions. So a thin bright edge at a shallow angle still lands as a fixed staircase, and the steps crawl when the camera drifts. With the call on, the camera's projection is nudged by a sub-pixel offset that changes every frame, and the frames fold into a running average. Each pixel has soon been sampled at dozens of positions instead of eight. The staircase melts into a gradient, the crawling stops, and the leftover shimmer of the traced effects above calms down with it. It follows the camera, so orbiting keeps the accumulated detail. It leaves 2D drawing untouched, since that path is already exact. And like everything in this chapter, an export doesn't wait for frames. It renders the scene several times at fixed offsets inside each frame and averages, so a still is finished immediately and a video can't flicker. Unlike the mirrors and the bounce, it doesn't need a ray-tracing GPU, and any Mac that runs Ollin can do it.

The figure is what that looks like in the pixels themselves. The same four rods were exported twice and magnified, one square per pixel. They are thinner than a pixel and tilted a few degrees, which is the case fixed positions handle worst. On the left, a rod catches two of the eight samples in one pixel and none in the next. It comes out as uneven dashes, and the thick one climbs in visible steps. On the right, the export averaged sixteen jittered passes, so each pixel carries the rod's true share of it. The dashes join into an even line, and the steps soften into a ramp. Live, that is the difference between a hairline that crawls as the camera drifts and one that holds still.

One thing the average can't know on its own is where a *moving object* was last frame. The camera's motion is followed automatically. A mesh spinning or flying through the scene on its own refreshes its history instead, so there are no ghost trails, at the price of its edges reading rawer mid-flight. Wrap its drawing in `withMotion { }` and Ollin remembers the block's placement from frame to frame. That hands the average each mover's exact screen motion, so its edges keep their refinement while they move. Name the block, as in `withMotion("rotor") { }`, if the code path that draws it changes between frames.

The [`TemporalAA` example](../Examples/3D/Effects/TemporalAA/Sketch.swift) is a trellis of thin tilted rods under a slow camera sway, with the toggle on a parameter. An orbiting bar has a `withMotion` parameter of its own. Flip them mid-motion and watch the edges stop crawling. The scenes where it makes the most difference are exactly that kind, so hairline geometry, high contrast, and movement.

## Highlights that hold still: specular anti-aliasing

The section above steadied the *edges* of things. Their highlights can crawl too, and jitter is not what fixes that.

A polished surface turns a light into one small bright spot. Where the surface curves tightly, or a normal map turns quickly, a single pixel covers a whole range of surface directions. The spot can end up narrower than that pixel. Ollin shades each pixel once. So the one sample either lands on the spot or misses it, and which of those happens changes from frame to frame. That is the sparkle running over a bed of small shiny balls, a metal roof in the distance, or a bumpy map. The eight samples per pixel do not help: they sample the *shape*, and the shading still happens once.

```swift
material(.metal(roughness: 0.1))
specularAntialiasing()      // the sparkle stops running
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/31-TracedLight/HeldHighlights-dark.jpg">
  <img src="Images/31-TracedLight/HeldHighlights.jpg" alt="Three magnified crops of the same exported pixels, a bed of tiny polished balls under one light. With the call off, the bed is dark with a scatter of hard white specks. The middle crop, rendered at sixteen samples a pixel, is denser and brighter with softer specks. With the call on, the bed is an even mid-gray with no specks at all" width="680">
</picture>

The figure is the bed from the example, each ball a few pixels across, exported three times and magnified. On the left the call is off. Most balls show nothing and a few show one hard white pixel, because the one shading sample either hits the highlight or misses it. The middle crop is the reference, the same frame at sixteen samples a pixel. It shows what the surface really scatters: a highlight on every ball, most of them faint. On the right the call is on. Every ball carries a broader, dimmer highlight, and the bed reads calm. It also reads a touch brighter than the reference, because a widened highlight spreads further than the surface does. That is the trade: steadiness, bought with a little accuracy. As the balls turn, the left crop would change from frame to frame, and the right one would not.

The call widens the roughness of each pixel by how far its own surface direction turns across it. A wider highlight is broader and dimmer. It fills the pixel instead of hiding inside it, so it stays where it is while the surface moves. The cost is two small measurements per pixel. There is no extra pass and no history to build up, and any Mac that runs Ollin can do it.

It finds the detail on its own. A flat wall holds one direction across every pixel of it, so it comes back exactly as it was. A ball a few pixels wide is widened a lot. Nothing is widened past a fixed limit, which keeps the pixels along a silhouette from turning matte. `strength` scales the whole effect. 1 is the standard amount, 2 gives up more of the finish for more calm, and below 1 keeps more of the original sharpness.

Two things it will not do. A highlight so bright that it has already gone flat white cannot be calmed, and widening it only spreads that white. Turn the strength down if a picture reads softer rather than steadier. The measurement also comes from the pixels next door, so detail far below one pixel is guessed rather than measured.

The [`SpecularAntialias` example](../Examples/3D/Effects/SpecularAntialias/Sketch.swift) is a bed of small polished balls under one hard light, with the toggle and the strength on parameters. The plate standing behind them is flat, so it never changes. Watch the balls at the back of the bed, where they are smallest.

## The streak a shutter leaves: motion blur

A rendered frame is an instant: everything in it is perfectly sharp, no matter how fast it was going. A film frame is not. A real camera's shutter stays open for a slice of each frame, and anything that moved during that slice smears along its path. Your eye has spent a lifetime learning that fast things streak. That's why rendered motion can feel like a strobe, since the picture keeps saying *is* when it should sometimes say *was going*. A sharp frame says where things are, and a streak says where they're going.

```swift
motionBlur()                 // the film-standard 180-degree shutter
withMotion {
    rotate(time * 2.5, axis: .unitY)
    translate(2.5, 1, 0)
    drawSphere(radius: 0.4)  // streaks along its orbit
}
```

<img src="Images/31-TracedLight/MotionStreak.jpg" alt="Three colored spheres orbiting a ring of gray columns. The fast yellow sphere draws a long horizontal streak, the middle orange one a short smear, the slow blue one is nearly crisp, and the columns stay perfectly sharp" width="640">

The figure is one still frame, and it already tells you who is moving and how fast. The fast sphere draws a long streak along its orbit, the middle one a short smear, the slow one barely softens, and the columns stay razor sharp. That's the whole contract. Each pixel streaks along *its own* motion. The camera's movement is read from the depth buffer with no declaration at all, so pan past a still scene and the whole scene smears by exactly how far it slid. An object moving on its own declares itself with the same `withMotion { }` block temporal AA already uses, one wrapper serving both systems.

`shutter` is the photographic dial. The default `0.5` is the film standard, the shutter open for half of each frame, the look every movie trained you on. Drop it toward `0.1` and motion turns crisp and staccato, the action-movie look. Raise it to `1` for a full frame of smear, and past it for a streak no real camera could make. Because the blur reads the motion *between frames*, an export carries it deterministically. Frame k streaks by exactly how things moved since frame k-1, a video export looks like the live window, and the very first frame, with nothing before it, is honestly sharp.

The [`MotionBlur` example](../Examples/3D/Effects/MotionBlur/Sketch.swift) is the figure's scene live, with the toggle and the shutter on parameters. Slide the shutter while the spheres orbit and watch the same motion go from strobe to smear. Captions, 2D overlays, and the environment backdrop never streak, so the interface stays still while the world moves.

## Light in the camera: lens flare

Everything else in this chapter is the light and the thing it lands on. A flare is the camera admitting that it is there.

A lens is supposed to bend light onto the sensor. Some of it does not. At every surface a little reflects instead of passing through, and light that reflects twice ends up going the right way again. It lands on the sensor, but in the wrong place. That misplaced light is a **ghost**. A row of ghosts, on the line from a bright source through the middle of the frame, is what a lens flare is.

```swift
var camera = Camera3D(eye: ..., target: ...)
camera.apertureBlades = 6            // the iris has six blades
self.camera(camera)

pointLight(.white, at: lamp, intensity: 20)
lensFlare()                          // the ghosts that lamp leaves in the lens
```

<img src="Images/31-TracedLight/GhostChain.jpg" alt="A dark room with a small bright lamp up and to the left. Coral and lavender hexagons nest on the lamp. A blue-gray hexagon sits down and to the right of it, toward the middle of the frame, lying across a near black slab. Larger, fainter hexagons trail off both ways along the same line" width="640">

Every ghost in the figure is a hexagon, because the iris has six blades and a ghost is a picture of the opening its light came through. They sit on one line, the line from the lamp through the middle of the frame, some on the lamp's side of the middle and some across it. Their colors differ because each surface of the lens is coated for a different wavelength. A coating passes on whatever it fails to cancel. And look where the blue-gray one is. It lies *over* the near black slab, not behind it. Nothing in the room is glowing. The light never reached that slab. It only reached the glass in front of the sensor.

None of them is quite a regular hexagon, either. Each ghost is worked out by following real rays through the lens's real glass, and spheres bend a ray near their rim by more than proportion says. So a ghost's sides stretch a little, more the further the lamp sits from the middle. Where one ends in a curve, that is the round barrel stopping rays the iris let past, and a bright rim along one side is a caustic, where neighboring rays landed on top of one another.

That is one half of a flare. The other sits on the source itself.

<img src="Images/31-TracedLight/StarPoints.jpg" alt="A dark room with a small bright lamp above a row of blocks. Six golden arms reach out from the lamp, each a close frayed pair with fine needles between them, around a blown-out core. A pale hexagon sits on the lamp, and up and to the left a small soft disc with a red rim" width="640">

Those arms are light **bending at the edges of the iris**. Far from an opening, what its edges do to a wave is exactly the opening's own Fourier transform, so what lands on the sensor is a picture of the opening turned inside out. Six blades put six arms on the star for the same reason they put six sides on a ghost.

Three things follow from that, and all three are worth knowing:

- An **odd** number of blades gives **twice** as many arms. No two of its edges are parallel, so each throws its own.
- A **round** iris throws no arms at all, only a halo. Set `apertureBlades` to 0 and watch the arms go with the hexagons.
- **Stopping down grows the star** while it shrinks the ghosts. Light spreads more around a smaller opening, so a landscape shot at f/16 gets long rays and a portrait wide open gets almost none.

The arms fan into color at their tips because a longer wavelength bends further, so red reaches past blue. `star:` scales it, and `star: 0` leaves the ghosts alone without it, which is a real choice: they are two different effects and a piece may want one and not the other.

Look at the arms again, because they are not six ruled lines. Each one is a close pair, a little frayed, with fine needles between them. That is `wear:`, the wear on the opening. The blades of a used lens do not sit quite evenly, and specks and hairline scratches lie across it, and every one of those bends a little light of its own. `wear: 0` gives the perfect star of a perfect iris, which no photograph has ever shown.

So the call asks for a lens, not for a look:

```swift
lensFlare(amount: 0.6, lens: .heliar.stopped(to: 11))
```

`Lens.heliar` is a real prescription, a 1950s portrait lens. Its nine surfaces decide how many ghosts there are, where each sits, how big it is, and what color it comes out. Most of its ghosts are wide and faint, so it veils the frame more than it chains across it. `Lens.doubleGauss` is the other one bundled, with more surfaces and so more ghosts in more sizes, and it is the one the figure above was made with. `stopped(to:)` closes the iris, and the ghosts it shapes shrink and brighten, the same light in a smaller shape. `multicoated()` coats each surface for a different wavelength, the way a modern lens is made. That is what puts the ghosts in different colors instead of all in one. Name no lens and you get `Lens.standard`, the double Gauss multicoated at f/8. `anamorphic()` puts a wide-screen front group on any of them, which stretches the ghosts and the star two to one sideways. Type in a different prescription and you get a different camera's flare.

One more number belongs to the scene rather than the lens, and that is how big the source is. A ghost is a picture taken *with* the source. Every point of the lamp throws its own copy of each ghost, shifted a little, so a wide lamp gives soft ghosts and a distant street light gives hard ones. `sourceSize:` says which. The ghost that lands almost in focus shows it best. From a point it is a hot dot, and from a lamp it is a small soft picture of the lamp.

Three more parts of a flare come from outside the lens's own glass, and all three are off until you ask. `streak:` is what cylindrical glass does to a light, whether it is the front of an anamorphic lens or the fine grooves of a streak filter: it fans each light out into one long thin line. `dirt:` is grime on the front element, so far out of focus that every speck is a soft picture of the iris, glowing where it sits near the light. `halo:` is the rainbow ring that flare artwork draws around a light. That last one is a look and not optics, and the [reference](../Docs/3D/LensFlare.md#extras) says why.

`amount` is the honesty dial, and it is worth being honest about. A flare is a defect. Sometimes you want it, often you want a trace of it, and plenty of pieces want none. `0` removes it.

The last part is what keeps a flare from reading as a sticker stuck to the lens. Its strength follows how much of the source the camera can actually **see**. Walk something in front of the lamp and the flare fades as the lamp is covered. It does not switch off the moment the lamp's center goes behind. That is one of those details you never notice when it is right and cannot stop noticing when it is wrong.

The [`LensFlare` example](../Examples/3D/Effects/LensFlare/Sketch.swift) drifts a lamp back and forth behind a slab with the lens, the amount, the f-number, the blade count, the source's size, and the wear on parameters, with a streak, dirt, and a halo to turn on besides. Watch the ghosts fade as the lamp goes behind, and watch them shrink together as you stop down.

## The shape of a blur: bokeh

[Chapter 25](25-3DGently.md#what-the-depth-buffer-is-for)'s `.defocus` blurs a scene by its depth, and the lens it imitates has an iris of its own.

A blur has a shape, and it is not always a circle. Out of focus, a point of light is not a smudge. It is a picture of the opening its light came through. Hand `.defocus` a `blades` count and every highlight becomes a polygon of that many sides. That is what the iris of a real lens is made of. `catsEye` adds the barrel around that iris. The barrel clips the opening away from the middle of the frame. So a highlight that is whole in the middle lies down into a lemon toward the corners.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/31-TracedLight/TheOpening-dark.jpg">
  <img src="Images/31-TracedLight/TheOpening.jpg" alt="Three panels of the same handful of out-of-focus lights: round blobs through a round opening, clean pentagons through a five-bladed iris, and the same pentagons clipped into lemons toward the corners once the barrel is added" width="680">
</picture>

Leaving `blades` unsaid is not the same as asking for nothing. A scene defocused by its own depth takes the count from the camera that drew it. So one line, `camera.apertureBlades = 6`, shapes this blur, the flare ghosts of [the lens flare](#light-in-the-camera-lens-flare), and the path-traced export together. Name `blades` at the call only for a blur no camera knows about, such as a tilt-shift over a ramp you drew by hand. One practical note. The blur gathers a fixed number of samples. A light smaller than the space between them shows the pattern of the gather instead of a clean edge, so keep a light a few pixels across, or raise `quality`.

## Rendering fewer pixels: temporal upscaling

Almost everything in this chapter charges by the pixel. The mirrors trace one ray per pixel, the fields march per pixel, and the bounce is gathered per pixel. When a scene gets heavy, the honest lever is to render fewer of them. `temporalUpscaling()` pulls it without giving up the full-size picture:

```swift
rayTracedReflections()
temporalUpscaling()      // render at two-thirds size, reconstruct the full canvas
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/31-TracedLight/FewerPixels-dark.jpg">
  <img src="Images/31-TracedLight/FewerPixels.jpg" alt="Two diagram panels. Left, a canvas grid of eight by eight thin cells under a four by four grid of thick cells, with four colored dots in every thick cell, one for each of four frames. Right, the canvas as a square with three smaller squares nested in its corner, labeled performance at half a side, default at two thirds, and detail at three quarters" width="680">
</picture>

The live window draws the whole frame at a fraction of the canvas. The platform's temporal scaler then rebuilds the full-size image from the same jittered history that "Edges that settle: temporal anti-aliasing" accumulates. You render fewer pixels, and the history remembers the rest. The tier picks how few. `.performance` renders at half size per side, a quarter of the pixels, `.default` at two-thirds, and `.detail` at three-quarters. It replaces `temporalAntialiasing()` while it runs, since it *is* that accumulation aimed at resolution. It reads the same `withMotion { }` declarations, so a mover reconstructs cleanly mid-flight. It needs Apple silicon, and anywhere else the call renders normally, with a note.

The left panel of the figure is why that works. At half size, one rendered pixel covers four canvas pixels. The projection is nudged a different way each frame, so the sample lands in a different one of the four each time. After four frames, every canvas pixel has been sampled once. The history holds those frames, and the scaler reads the full-size picture out of them. The right panel is how much each tier renders. Half a side is a quarter of the pixels, two thirds is four ninths, and three quarters is nine sixteenths.

What you keep is never the preview. Exports and snapshots render at full resolution with the deterministic average. So upscaling is purely a live-window trade, and the same sketch previews fast and exports full. The [`Upscaling` example](../Examples/3D/Effects/Upscaling/Sketch.swift) is a mirror floor tracing a ring of columns, with the toggle and the tier on parameters. Watch the FPS readout while you flip them, since that scene runs about twice as fast at `.performance` on an M2. An export never upscales, so the FPS readout, not a still, is where the trade shows.

## Drawing fewer frames: the ones in between

Upscaling spends less on each frame. The other lever is to draw fewer frames and let the machine fill the gaps:

```swift
rayTracedReflections()
frameInterpolation()     // draw every other refresh, show a made frame between
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/31-TracedLight/EveryOtherRefresh-dark.jpg">
  <img src="Images/31-TracedLight/EveryOtherRefresh.jpg" alt="A timing diagram over twelve refreshes of a 60 Hz display. The top row, what draw() made, has a frame on every other refresh, lettered A to F. The bottom row, what the display showed, has each drawn frame one refresh later and, between them, made frames lettered AB, BC, and so on, each joined by lines to the two drawn frames it came from. The first frame is shown at once and repeated" width="680">
</picture>

`draw()` then runs on every other refresh. On the refresh between, the platform builds the picture that belongs in the middle out of the two frames either side of it, guided by the depth buffer and the same `withMotion { }` declarations everything else in this chapter reads. A scene that can hold thirty drawn frames a second moves at the display's sixty.

The figure is a fifth of a second of that, refresh by refresh. The top row is what `draw()` made: six frames, one on every other refresh. The bottom row is what the display showed, and it is twelve. Each made frame sits on the refresh its second source was drawn, built from that frame and the one before it. Each drawn frame is shown on the refresh after its own, which is the wait described below. The first frame has nothing to pair with, so it is shown at once and then repeated.

Your clock is untouched, which is the part that matters for a sketch. `time` still runs on real seconds, so the motion keeps its speed and only its sampling halves. The FPS readout counts frames you drew, so watch it fall to thirty while the picture on screen does not change pace. That gap between the two numbers *is* the feature.

Two things come with it. A drawn frame waits one refresh before it is shown, because the made frame belongs in front of it, so everything arrives about sixteen milliseconds later than it would; a piece steered by the mouse can feel that. And a made frame is a guess: where something moves further than the interpolator can follow, it repeats the drawn frame instead of smearing it. The first frame after it starts is repeated for the same reason, which is why turning it on shows nothing odd.

Exports never interpolate. What you keep is the frames you drew, so no file ever carries a guessed picture. The [`FrameInterpolation` example](../Examples/3D/Effects/FrameInterpolation/Sketch.swift) is a ring of orbiting blocks with a fast arm sweeping through them, with the toggle and a speed parameter. Turn the speed up until the arm stops keeping up, which is the honest edge of what this can do.

## The slow render worth waiting for

A 3D scene has one more way out of the window. Add `--path-traced` to a still, sequence, or video export and the frame renders by *tracing light* instead of rasterizing. Shadows from an area light sharpen at contact and melt with distance. Color bleeds between neighboring surfaces. Every polished thing mirrors the scene, including the other mirrors. A `.glass` material becomes real glass. The view bends through a solid body, and a colored one tints the light crossing it. Even the shadow glows with what got through instead of going black. A mesh with an emissive material becomes a lamp with a shape, lighting its neighbors as smoothly as a softbox. A textured surface keeps its picture in reflections and bounces. The copies of [Chapter 27](27-Landscapes.md) are in there as well, so a field of ten thousand pebbles shadows and mirrors like ten thousand hand-placed ones. The other maps ride along too: a normal map's relief, a roughness map's wear, a glow map's shape all reach the traced light. And the camera gains a real lens. Set `aperture` and `focusDistance` on your `Camera3D`, and the export has true depth of field while the live window stays pinhole-sharp for framing.

```sh
swift run OllinLive MySketches/StillLife.swift --export poster.png --path-traced 512
```

The number is light paths per pixel; more is smoother, and takes longer in step. The live window is the viewfinder, and the flag is the film back. Tune fast, then let the machine take its time. It needs an Apple-silicon Mac, and [the reference](../Docs/Output/PathTraced.md) lists exactly what the traced frame adds and what stays with the raster pipeline.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/31-TracedLight/TracedLight-dark.jpg">
  <img src="Images/31-TracedLight/TracedLight.jpg" alt="Three renders of the same set of three spheres on a pale floor under one softbox: rasterized, with a hard-edged shadow, a tinted glass shell, and a dark chrome ball; path-traced at 96 samples, with soft shadows, red bled onto the floor, the glass lit through, and grain; and the same trace denoised, the grain gone and the edges kept" width="680">
</picture>

The figure is one small set rendered three ways through the same call the flag wraps. The window rasterizes it. The softbox throws a hard-edged shadow, and the floor is lit by the lamp alone. The glass sphere is a tinted shell, and the chrome one is a dark ball with a highlight. Traced at 96 paths a pixel, the shadows soften as they fall away from each sphere. The red sphere warms the floor beside it. The light goes through the amber glass and lands as a tinted pool where the raster had a black shadow. The chrome shows the set. What is left at 96 is grain. The third panel is the same trace through the grain filter this section ends on. The grain is gone, and the edges of the spheres and of their shadows are where they were.

Your light rig comes over as you left it. Here the tracer follows the light itself, so it needs no `castShadows()` and every lamp in the frame throws one. A light you told not to throw still throws nothing, which matters because the fill in a preset rig is exactly such a light. The shadows in the file are the shadows you framed.

There is one more thing you can ask for before the file is written. What is left of the error in a traced render is grain. Buying it away costs the square: four times the paths for half the speckle. `--denoise` filters it out instead. The useful trick is that the tracer wrote down what it *hit*, not only what it saw. It kept the first surface's own color, the way it faces, and how far off it is. It also kept how much the pixel's own samples disagreed. The filter divides the light by that color, smooths the light alone, and multiplies the color back. A texture keeps its edges and a silhouette keeps its line, because neither was ever in the part being smoothed. And since the strength comes from the disagreement, a thin render is smoothed hard and a nearly finished one only a little. On the example scene, 64 filtered samples land about where 240 raw ones would have. It holds at the deep end too: even a 2048-sample render comes out closer to the truth, not merely smoother. It is off unless you ask, because a raw render is the honest one to hand you, and a real sparkle reads softer once the filter has been over it.

## Putting it together: the lamplit room

The lamplit room is one lamp swinging over a waxed floor. Almost everything in the frame is that lamp's light after it has landed somewhere. It bounces off the floor onto the ceiling and shows in the floor's sheen. A glass ball focuses it into a spot, a red ball rolls through it, and the lamp flares in the lens. Make `MySketches/LamplitRoom.swift`:

```swift
import Ollin

final class LamplitRoom: Sketch {
    let bulb = Image(width: 1, height: 1, color: Color(hex: 0xFFF1D6))
    let pivot = Vector3(-0.9, 4.0, -0.6)

    override func draw() {
        background(.black)
        var lens = Camera3D(eye: Vector3(0.2, 1.8, 3.8), target: Vector3(0.4, 1.4, -1),
                            projection: .perspective(fieldOfView: .pi / 2.8))
        lens.apertureBlades = 6
        camera(lens)
        toneMap(.aces, exposure: 1.2)

        // The lamp swings on its cord, and its light points down the cord.
        let swing = 0.3 * sin(time * 1.2)
        let down = Vector3(sin(swing), -cos(swing), 0)
        let lamp = pivot + down * 1.1
        spotLight(Color(hex: 0xFFE2B8), at: lamp, direction: down,
                  coneAngle: 2.0, penumbra: 0.6, intensity: 4)

        // What the light does once it lands.
        environment(.studio.intensified(to: 0.12))
        castShadows()
        globalIllumination()
        rayTracedReflections()
        glossyReflections()
        caustics(dispersion: 0.3)

        // What the camera does with it.
        temporalAntialiasing()
        motionBlur()
        lensFlare(amount: 0.5)

        // The room: a waxed floor, a white ceiling and back wall, one
        // terracotta wall and one teal one.
        withState {
            material(.dielectric(roughness: 0.2))
            fill(Color(hex: 0x7A5E48))
            translate(0, -0.1, 0)
            drawBox(width: 8.4, height: 0.2, depth: 8.4)
        }
        fill(Color(white: 0.86))
        withState { translate(0, 4.1, 0); drawBox(width: 8.4, height: 0.2, depth: 8.4) }
        withState { translate(0, 2, -4.3); drawBox(width: 8.4, height: 4.4, depth: 0.2) }
        withState { fill(Color(hex: 0xC8603A)); translate(-4.3, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8.4) }
        withState { fill(Color(hex: 0x2A8C8C)); translate(4.3, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8.4) }

        // A glass ball on a white plinth, wide enough that the lamp's light
        // comes to its focus on the plinth's top rather than spreading again
        // on the floor beyond it.
        withState { translate(1.1, 0.25, 0.2); drawBox(width: 1.6, height: 0.5, depth: 0.9) }
        withState {
            material(.glass(thickness: 1.2))
            fill(.white)
            translate(1.0, 1.1, 0.2)
            drawSphere(radius: 0.6)
        }

        // A red ball rolling around the plinth.
        withMotion("ball") {
            withState {
                material(.dielectric(roughness: 0.35))
                fill(Color(hex: 0xC8302C))
                translate(1.0, 0.3, 0.2)
                rotate(time * 1.8, axis: .unitY)
                translate(1.5, 0, 0)
                drawSphere(radius: 0.3)
            }
        }

        // The cord and the bulb. The bulb sits a little up the cord from the
        // light, so it never stands between the light and the room.
        withMotion("lamp") {
            withState {
                fill(Color(white: 0.1))
                translate(pivot)
                rotateZ(swing)
                translate(0, -0.475, 0)
                drawCylinder(radius: 0.012, height: 0.95)
            }
            withState {
                translate(lamp - down * 0.08)
                fill(.white)
                matcap(bulb)
                drawSphere(radius: 0.07)
            }
            matcap(nil)
        }
    }
}
```

The sketch sets up its light in three groups. The first is the lamp. A spot light hangs from `pivot` and points down the cord. So as `swing` rocks the lamp, its pool of light moves across the floor with it.

The second group is what the light does once it lands. The bounce comes from `globalIllumination()`, so the floor lights the ceiling and the two colored walls tint what faces them. The floor shows the room rather than the sky through `rayTracedReflections()` and `glossyReflections()`, blurred by its roughness of 0.2. The spot comes from `caustics(dispersion: 0.3)`, which sends the lamp's light through the glass ball and lands it on the floor. The dispersion splits a little of the spot's color apart at its edge.

Shadows hold those three together. With `castShadows()` on, the bounce respects the shadows, and the spot lands inside the glass ball's own shadow. With one light in the room, the light that casts the shadows is also the one the photons leave from. The `environment(_:)` is dim on purpose. The reflections need a sky to fall back to, but the room should be lit by its lamp.

The third group is the camera. The edges settle under `temporalAntialiasing()`, what moves streaks under `motionBlur()`, and `lensFlare(amount: 0.5)` puts the lamp's flare in the lens. The ghosts come out as hexagons and the star with six arms, because the camera was given `apertureBlades = 6`. The red ball is drawn inside `withMotion("ball")`, and the cord and bulb inside `withMotion("lamp")`. That is how the average and the blur learn how each one moved. So the ball's edges stay settled while it rolls, and it streaks along its path.

The bulb is drawn a little way up the cord, not where the light is. A shape drawn right where a light sits stands between that light and everything it shines on. With `castShadows()` on, it shades the whole room. Up the cord, the bulb is behind the light, which points down. The flare checks what covers the light from a point a little in front of it, so the bulb doesn't dim the flare either.

The traced parts need a ray-tracing GPU, which every Apple silicon Mac has. Elsewhere those calls do nothing, and the room still draws with its direct light, its shadows, and its flare. If it stutters on your Mac, `temporalUpscaling()` renders fewer pixels and `frameInterpolation()` draws fewer frames. Neither one changes what an export writes.

Then make it yours:

- Color the glass. Give it `material(.glass(thickness: 1.2, attenuationColor: Color(hex: 0xD08A2E), attenuationDistance: 1.2))`, and the ball and the spot it throws both turn amber. Or turn the caustics' `dispersion` up to 1, and the red and blue at the spot's edge spread wider.
- Stop down the lens. `lensFlare(amount: 0.5, lens: .standard.stopped(to: 16))` shrinks and brightens the ghosts and grows the star. Set `apertureBlades` to 5 as well, and the star has ten arms, since an odd count doubles them.
- Sway the camera. Build `lens` with `Camera3D.orbiting`, around the glass at a radius of 3.6, and let its `azimuth` follow `sin(time * 0.4) * 0.3`. The motion blur and the edge average read the camera's motion on their own, with no `withMotion` needed.

This one moves, so keep it as a movie. This writes twelve seconds of it:

```sh
swift run OllinLive MySketches/LamplitRoom.swift --export-video lamplit-room.mp4 --seconds 12
```

An export doesn't wait for anything to settle. Each frame averages its own jittered passes and gathers its bounce in full. So the first frame is as finished as the last, and the file can't flicker.

A still can go one step further, through "The slow render worth waiting for". Give the camera a real lens with `lens.aperture = 0.05` and `lens.focusDistance = 3.7`, then trace the still:

```sh
swift run OllinLive MySketches/LamplitRoom.swift --export lamplit-room.png --path-traced 512 --denoise
```

The traced frame has true depth of field, focused on the glass, and its out-of-focus highlights are hexagons for the same six blades. One thing does not carry over. The focused spot under the glass comes from the live `caustics()`, so in the traced frame the glass throws a plain tinted shadow instead.

## Where this comes from

The traced light rebuilds published methods, each written from the paper. Global illumination is the dynamic diffuse irradiance field of Zander Majercik, Jean-Philippe Guertin, Derek Nowrouzezahrai, and Morgan McGuire, from 2019. The caustics are Xueqing Yang and Yaobin Ouyang's adaptive anisotropic photon scattering, from 2021. Temporal anti-aliasing is written from Brian Karis's 2014 treatment of temporal supersampling. Specular anti-aliasing is the normal-distribution filtering of Anton Kaplanyan, Stephen Hill, Anjul Patney, and Aaron Lefohn, from 2016. Motion blur is the reconstruction filter of Morgan McGuire, Padraic Hennessy, Michael Bukowski, and Brian Osman, from 2012. The lens flare is written from the matrix formulation of Sungkil Lee and Elmar Eisemann. The color its coatings leave comes from the thin-film reflectance of Matthias Hullin and colleagues. Temporal upscaling drives Apple's MetalFX scaler rather than reimplementing one. The path-traced export stands on James Kajiya's rendering equation, from 1986.

The mirrors follow the hybrid rendering Apple describes for Metal ray tracing. It draws the surfaces as usual and traces one ray from each reflective pixel. The glossy lobe draws each ray with Eric Heitz's sampling of the visible normals, from 2018. It shares the neighbors' rays the way Tomasz Stachowiak's stochastic reflections do, from 2015. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Depth effects](../Docs/Drawing/Effects.md#combined): `.screenSpaceReflections` and `.defocus`, with the iris `blades` and `catsEye` that shape a blur.
- [The traced and temporal tiers](../Docs/3D/3D.md): ray-traced reflections, the global-illumination probe field, temporal anti-aliasing with `withMotion`, specular anti-aliasing, motion blur, and temporal upscaling, each with what it needs and what it costs.
- [Lights](../Docs/3D/3D.md#lights) and [which sources flare](../Docs/3D/LensFlare.md#sources): the spot light the room hangs, and a glowing body drawn where a light sits.
- [Caustics](../Docs/3D/Caustics.md): what casts and what receives, the emitting light's priority, dispersion, the quality dial, and how the photon chain works.
- [Lens flare](../Docs/3D/LensFlare.md): the lens as a stack of interfaces, writing your own prescription, the iris and its blades, which sources flare, and how a flare follows what the camera can see.
- [Path-traced export](../Docs/Output/PathTraced.md): what the traced frame adds and what stays raster, the sample count and its timings, the real lens, and the grain filter.
- Worked examples: [`Examples/3D/Effects/ScreenSpaceReflections`](../Examples/3D/Effects/ScreenSpaceReflections/Sketch.swift), [`RayTracedReflections`](../Examples/3D/Effects/RayTracedReflections/Sketch.swift), [`Examples/3D/Lighting/GlobalIllumination`](../Examples/3D/Lighting/GlobalIllumination/Sketch.swift), [`Caustics`](../Examples/3D/Lighting/Caustics/Sketch.swift), [`Examples/3D/Effects/TemporalAA`](../Examples/3D/Effects/TemporalAA/Sketch.swift), [`SpecularAntialias`](../Examples/3D/Effects/SpecularAntialias/Sketch.swift), [`MotionBlur`](../Examples/3D/Effects/MotionBlur/Sketch.swift), [`LensFlare`](../Examples/3D/Effects/LensFlare/Sketch.swift), [`SceneDefocus`](../Examples/3D/Effects/SceneDefocus/Sketch.swift), [`Upscaling`](../Examples/3D/Effects/Upscaling/Sketch.swift), [`FrameInterpolation`](../Examples/3D/Effects/FrameInterpolation/Sketch.swift), and [`PathTraced`](../Examples/3D/Effects/PathTraced/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 30, Sculpting with fields](30-SculptingWithFields.md) · Next: [Chapter 32, Seeing](32-Seeing.md)
