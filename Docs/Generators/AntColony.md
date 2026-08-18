#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `AntColony`</sup>

---

## Ant colony

**Ant-colony optimization** solves "visit every city once, briefly" the way a colony finds food: by talking through the floor. Each iteration every ant walks a full tour, choosing its next city by trail strength and closeness. Then the whole map evaporates a little, and every ant lays fresh pheromone along its tour, more for shorter tours. Good edges reinforce, bad ones fade, and the web condenses onto a short route.

The pretty part is the web itself. `trails` is the colony's live belief about every edge, and drawing it each iteration shows a haze of possibilities condensing into an answer.

`AntColony` is a stateful stepper you hold. `step()` runs one full iteration, `step(_:)` a batch. It's seeded, so the same seed searches the same way.

```swift
let colony = AntColony(cities: points, seed: 7)

override func draw() {
    colony.step()
    background(.black)
    for trail in colony.trails {
        stroke(Color.white.withAlpha(trail.strength * 0.8))
        drawLine(trail.a, trail.b)
    }
}
```

### Contents

- [Building a colony](#building)
- [Searching](#searching)
- [Drawing the web and the answer](#drawing)

<a name="building"></a>

#### Building a colony

```swift
AntColony(cities: [Vector2], ants: Int? = nil, alpha: Double = 1,
          beta: Double = 4, evaporation: Double = 0.5,
          elitism: Double = 0, seed: UInt64 = 0)
```

`cities` are the points to tour; a few dozen make a readable web. `ants` defaults to one per city. `alpha` is how strongly the trail counts when an ant chooses, and `beta` how strongly closeness counts: raise `beta` and the ants turn near-greedy, drop it to `0` and they follow pheromone alone. `evaporation` is the forgetting rate. High values keep exploring; low values commit early, sometimes to a rut. `elitism` gives the best-so-far tour that many extra deposits per iteration, which sharpens the web onto the current answer.

<a name="searching"></a>

#### Searching

`step()` is one full colony iteration: every ant walks a tour from its own random start, the map evaporates, every tour deposits, and `bestTour`/`bestLength` update. `iterations` counts how many have run. One or two per frame reads as a living search; a few dozen usually settle a small scatter. The best never worsens, so you can stop whenever the web looks done.

<a name="drawing"></a>

#### Drawing the web and the answer

```swift
colony.trails                        // [(a, b, strength)], strongest edge = 1
colony.bestTourPoints                // [Vector2], for drawPolyline(closed: true)
colony.pheromone(between: i, and: j) // one edge's trail, symmetric
```

`trails` returns every city pair whose trail still matters, with strengths normalized so the strongest edge reads 1; map strength onto alpha and width and the web draws itself. Early iterations show a faint haze over every pair, late ones only the condensed route. `bestTourPoints` is the answer so far, ready to stroke on top. The `Patterns/AntColony` example watches the condensation live.

---

Related: [`singleLine`](./SingleLine.md) solves the same tour deterministically for the plotter path; the colony's charm is watching the search. The physarum simulation in [`Artificial life`](../Simulation/ArtificialLife.md) is the same trail-talking idea as a free-roaming field.
