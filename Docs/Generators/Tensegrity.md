#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Tensegrity</sup>

---

## Tensegrity

A tensegrity is a structure of rigid struts that never touch, held up by a net of cables. The struts push, the cables pull, and the form stands because every push meets an equal pull. **`Tensegrity`** is the geometry: nodes in space, the struts between them, and the cables between them. Three classic forms come ready-made in their balanced shape, and any of them can be handed to a `World3D` to fall, land, and stand.

```swift
let ball = Tensegrity.icosahedron(strutLength: 2)    // the six-strut form

fill(.white)
drawTensegrity(ball)                                  // struts and cables, where they are
```

<img src="../../Guide/Images/24-WorldsWithWeight/Tensegrity.jpg" alt="Three tensegrities standing on a dark floor, each built from colored struts and thin pale cables: an orange three-strut prism on the left, a yellow six-strut ball in the middle, and a tall teal mast of three stacked prisms on the right. No strut touches another in the first two." width="680">

### Contents

- [The three forms](#forms)
- [Balance](#balance)
- [Giving it weight](#weight)
- [Reading it back](#reading)
- [Building your own](#own)

<a name="forms"></a>

#### The three forms

| Form | Struts | Cables | What it is |
|---|---|---|---|
| `prism(struts:radius:height:twist:)` | `n` | `3n` | Two regular polygons of `radius`, the top raised by `height` and turned by `twist`. Each strut runs from a bottom node to the top node one step around. The simplest tensegrity. |
| `icosahedron(strutLength:)` | 6 | 24 | Three pairs of parallel struts, one pair along each axis, each pair half a strut's length apart. The shape most people picture. Its nodes are the vertices of Jessen's icosahedron. |
| `tower(levels:struts:radius:levelHeight:)` | `n × levels` | `n × (2 levels + 1)` | Prisms stacked on shared polygons, each level twisted the other way from the one below. Two struts meet at every shared node. |

A prism's default twist is the one that balances, `prismTwist(struts:)`, a quarter turn less half the polygon's angle: `π/2 − π/n`. Thirty degrees for three struts, forty-five for four, sixty for six. It does not depend on the height or the radius.

```swift
Tensegrity.prism(struts: 4, radius: 1, height: 1.5)   // balanced, at 45°
Tensegrity.prism(twist: 0.2)                          // three struts at the wrong twist
Tensegrity.tower(levels: 5, struts: 3, radius: 0.5, levelHeight: 1)
```

Every form is a value. `translated(by:)`, `rotated(by:)`, and `scaled(by:)` move it, `center` and `bottom` say where it is, and `endpoints(of:)` and `length(of:)` read any member.

<a name="balance"></a>

#### Balance

**`imbalance`** says how far a structure is from holding. It gives every strut the same push, finds the cable pulls that come closest to canceling it at every node, and reports the largest leftover force as a fraction of the mean pull. Zero means every node is in equilibrium. The three built-in forms read near zero. A prism at any other twist reads well above it, because no set of taut cables can balance its struts.

```swift
Tensegrity.prism().imbalance             // ~0
Tensegrity.prism(twist: 0.2).imbalance   // ~0.47
```

It is a check, not a fix. For a form of your own, read it before building.

<a name="weight"></a>

#### Giving it weight

`World3D.addTensegrity(_:at:…)` builds the structure in a physics world and returns a `Tensegrity3D`. Each strut becomes a capsule body and each cable a `.cable` joint between two strut tips. Where two struts share a node, a `.ball` joint ties them there.

```swift
import OllinPhysics

let world = World3D()
world.ground = 0
let mast = world.addTensegrity(Tensegrity.tower(levels: 3),
                               at: Vector3(0, 0.3, 0))    // a little above the floor

// each frame:
world.advance(by: deltaTime)
fill(.white)
drawTensegrity(mast)
```

The form falls, lands on its feet, and stands. Drag a strut with `dragBodies(in:)` and the whole thing follows and rights itself. `remove(_:)` takes it and all its parts out again.

- **`prestress`** is how much shorter than its drawn length each cable is made, as a fraction. Default `0.02`. A real tensegrity is tensioned this way. With none, a landing can leave a cable slack and the form loose. The struts are rigid, so the cables cannot actually reach the shorter length; they sit a little over it, taut.
- **`stiffness`** is the cables' give. `1` is inextensible. Less lets them stretch like a bungee, which softens every landing.
- **`strutRadius`**, **`density`**, and **`friction`** describe the struts. Friction is what keeps the feet from skating when it lands.

A prism built at the wrong twist and prestressed turns toward the balanced twist as it settles, because that is the only shape in which all its cables can be taut at once. It is a good thing to watch.

**The `.cable` joint** is the one new joint kind, and it is useful on its own. It holds two anchors no farther apart than `length` and does nothing when they come closer: a tether, a tendon, a guy line. A `.distance` joint is a rod; a `.cable` is a rope.

```swift
world.connect(mast, kite, .cable(from: mastTop, to: kiteNose, length: 4))
```

<a name="reading"></a>

#### Reading it back

A `Tensegrity3D` reads its own state from the struts:

- `struts` are the strut bodies, in `source.struts` order. `cables` are the cable joints, in `source.cables` order. `jointsBetweenStruts` are the ball joints at shared nodes.
- `source` is the geometry as built, in world coordinates. A strut of no length, a cable to a node no strut reaches, and that node are left out, so every member in it has a live counterpart.
- `nodes` are the live node positions. `endpoints(of:)` reads a member's two ends now.
- `cableLengths` and `cableRestLengths` compare each cable's length now with the length it was given; `isSlack(_:)` says whether one has gone loose.
- `center`, `bottom`, `top`, `isAwake`, `wake()`, and `applyImpulse(_:)`, which splits a shove evenly over the struts so the form moves as one.

`drawTensegrity(_:cableRadius:)` draws every strut as its capsule body and every cable as a thin capsule between the live nodes, in the current fill and material. For struts and cables in different colors, draw the struts with `drawBody(_:)` and the cables from `nodes` yourself.

A snapshot carries a tensegrity with the rest of the world: the struts and cables come back as bodies and joints, and the `Tensegrity3D` grouping comes back with them, reading the same nodes.

<a name="own"></a>

#### Building your own

A `Tensegrity` is three arrays, so any topology can be written down directly.

```swift
let form = Tensegrity(nodes: points,
                      struts: [Tensegrity.Member(0, 3), Tensegrity.Member(1, 4), Tensegrity.Member(2, 5)],
                      cables: cablePairs)
print(form.imbalance)      // near zero if it can hold
```

Nothing is checked at construction. `addTensegrity` skips a strut whose nodes coincide and a cable whose node no strut reaches, and returns `nil` if no strut is left. A cable may only join two different struts.

### See also

- [3D physics](../Simulation/Physics3D.md), for `World3D`, the joint kinds, and `dragBodies`.
- [Force-directed layout](ForceLayout.md), the other structure here that finds its own shape.
- Chapter 24, [Worlds with weight](../../Guide/24-WorldsWithWeight.md#standing-on-cables), which teaches it.
