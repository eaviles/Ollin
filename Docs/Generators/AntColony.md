#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → `AntColony`</sup>

---

## Ant colony

**Ant-colony optimization** looks for a short route that visits every city once. It works the way a colony of ants finds food, by leaving pheromone on the ground. In each iteration every ant walks a full tour, and it picks its next city by trail strength and by closeness. The whole map then evaporates a little, and every ant lays fresh pheromone along its tour, more of it for shorter tours. Good edges get stronger and bad ones fade, so the web condenses onto a short route.

The web itself is the part worth drawing. `trails` holds the colony's current trail strength for every edge, so drawing it each iteration shows a haze of possibilities condensing into one answer.

<img src="../../Guide/Images/20-ParticleSimulations/AntColonySearch.jpg" alt="Three dark panels of the same scatter of white city dots. Left, after one iteration, a pale web of trails over nearly every pair. Middle, after eight, fewer and stronger edges. Right, after sixty, a settled web with the best tour traced through the cities in orange" width="680">

`AntColony` is a stateful object that you hold on to. `step()` runs one full iteration, and `step(_:)` runs a batch of them. It is seeded, so the same seed searches the same way.

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

`cities` are the points to tour, and a few dozen of them make a readable web. `ants` defaults to one ant per city. `alpha` sets how strongly the trail counts when an ant chooses, and `beta` sets how strongly closeness counts. Raise `beta` and the ants become close to greedy, and drop it to `0` and they follow pheromone alone. `evaporation` is the rate at which the colony forgets. High values keep the ants exploring, and low values commit early, sometimes to a route the colony cannot get out of. `elitism` gives the best tour so far that many extra deposits per iteration, which sharpens the web onto the current answer.

<a name="searching"></a>

#### Searching

`step()` runs one full colony iteration. Every ant walks a tour from its own random start, then the map evaporates, then every tour deposits pheromone, and finally `bestTour` and `bestLength` update. `iterations` counts how many iterations have run. One or two per frame reads as a search you can watch, and a few dozen usually settle a small scatter. The best tour never gets worse, so you can stop whenever the web looks done.

<a name="drawing"></a>

#### Drawing the web and the answer

```swift
colony.trails                        // [(a, b, strength)], strongest edge = 1
colony.bestTourPoints                // [Vector2], for drawPolyline(closed: true)
colony.pheromone(between: i, and: j) // one edge's trail, symmetric
```

`trails` returns every city pair whose trail still matters. The strengths are normalized so that the strongest edge reads 1. Map strength onto alpha and width, and the web draws itself. Early iterations show a faint haze over every pair, and late ones show only the condensed route. `bestTourPoints` is the answer so far, ready to stroke on top. The `Patterns/AntColony` example shows the condensation as it happens.

---

Related: [`singleLine`](./SingleLine.md) solves the same tour deterministically for the plotter path, so use the colony instead when you want to watch the search itself. The physarum simulation in [`Artificial life`](../Simulation/ArtificialLife.md) uses the same trail-following idea in a free-roaming field.
