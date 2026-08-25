#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Billiards</sup>

---

## Billiards: one rule, and the room does the rest

A ball goes straight until it meets the wall, then leaves at the angle it arrived at. That is the whole system. Everything you see comes from the shape of the room, which is why the same two lines of code draw a rosette in a circle and a scribble in a stadium.

```swift
let room = Billiard(.circle(Circle(center: middle, radius: 380)))
drawPolyline(room.path(from: start, heading: 0.7, bounces: 400))
```

The path comes back as the points the ball turns at, so it is ordinary geometry: stroke it, fade it along its length, cut it with the [shape booleans](../Drawing/Geometry.md#shape-booleans), or send it to a pen through [SVG export](../Output/Export.md).

### Contents

- [The rooms](#rooms)
- [Letting a ball go](#running)
- [What each room draws](#pictures)
- [Things standing in the room](#obstacles)
- [Drawing the room itself](#outline)

<a name="rooms"></a>

#### The rooms

```swift
Billiard(.circle(Circle(center: middle, radius: 380)))
Billiard(.ellipse(center: middle, radii: Vector2(400, 250)))
Billiard(.polygon(outline))                              // any closed straight-sided outline
Billiard(.stadium(center: middle, straight: 380, radius: 240))
```

A stadium is a circle cut through the middle and pulled apart by `straight`: two flats joined by two half-circles. It is worth having its own case because of what it does, which is [below](#pictures).

<a name="running"></a>

#### Letting a ball go

```swift
room.path(from: start, heading: 0.7, bounces: 400)          // [Vector2], start first
room.path(from: start, direction: Vector2(1, 0.3), bounces: 400)
room.contains(start)                                        // is this a place a ball can be?
```

The path stops early where there is no answer: a corner the ball arrives exactly at, a start outside the room, or a direction that finds no wall at all. So the count of points is `bounces + 1` when everything went normally, and fewer when it did not.

Where a ball is let go matters as much as the room. In a circle it decides how big the hole in the middle is, and a ball let go at the exact middle leaves no hole at all. `contains` is the check worth making first: the middle of a room with a post in it is inside the post, where a ball would be trapped.

<a name="pictures"></a>

#### What each room draws

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/18-IteratedForms/BallInARoom-dark.jpg">
  <img src="../../Guide/Images/18-IteratedForms/BallInARoom.jpg" alt="Four rooms with a bouncing path drawn in each. A circle holds a star-like rosette with a clean round hole in the middle. An ellipse holds a woven band that never reaches either end. A stadium and a square with a round post in it are both filled edge to edge with scribble" width="680">
</picture>

**A circle keeps a hole.** A bounce turns the path about the radius, which leaves untouched how far the chord passes from the middle. Every chord of the path misses the middle by the same distance, so the whole rosette wraps one smaller circle it can never enter. Every chord is also the same length as every other, and each bounce moves the ball around the rim by the same angle, so a turn that is a whole fraction of a circle closes exactly into a star.

**An ellipse sorts paths into two kinds.** The product of the distances from the two foci to a chord is the same for every chord of a path. A path that passes between the foci therefore keeps passing between them, and one that misses keeps missing, forever. Those are two entirely different pictures out of the same room, and `foci` gives you the two points that decide which one you get.

**A stadium keeps nothing.** Cut the circle in half and pull the halves apart, and the hole goes. The path fills the room, and two balls let go a hair apart end up nowhere near each other within a few dozen bounces. That is the whole reason the shape is famous.

<a name="obstacles"></a>

#### Things standing in the room

```swift
Billiard(.polygon(square), obstacles: [Circle(center: middle, radius: 150)])
```

A post in the middle of a square does to it what pulling a circle apart does: it fills, and it separates. Aimed straight at the middle of a round post the ball comes straight back the way it came, since the wall it meets is square to it.

Obstacles are circles, they can be anywhere, and there can be any number of them.

<a name="outline"></a>

#### Drawing the room itself

```swift
let walls = room.outline()          // a Contour, curved parts cut into segments
let walls = room.outline(segments: 480)
```

`outline()` hands back the room as geometry so it draws with everything else. A polygon room hands back the outline it was given, unchanged.

### See also

- [`Geometry`](../Drawing/Geometry.md) - `Contour`, `Circle`, and the booleans a path can be cut with
- [`Attractors`](../Drawing/Attractors.md) - the other place in the catalog where one small rule draws a picture nobody designed
- [`Export`](../Output/Export.md) - SVG out, since a path is already lines a pen can draw
- Example: [Patterns/Billiards](../../Examples/Patterns/Billiards/Sketch.swift)
