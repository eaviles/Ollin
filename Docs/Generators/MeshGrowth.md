#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Mesh growth</sup>

---

## Mesh growth

**`MeshGrowth`** grows a surface that makes more of itself than it has room for. It takes a mesh, pushes its vertices apart, and keeps the triangles a fixed size by splitting the ones that stretch. The surface gains area, and that area has nowhere to go, so the surface folds.

```swift
// Held across frames, seeded once:
let coral = MeshGrowth(mesh: .icosphere(subdivisions: 3),
                       driver: .chemical(.coral), seed: 7)

// In draw():
coral.step()
material(.dielectric(roughness: 0.4))
drawMesh(coral.mesh)
```

That is the whole idea, and everything that looks designed about the result comes out of it. The forms it makes are the ones growing things arrive at, such as brain coral, a ruffled leaf margin, a lettuce edge, or something branching.

### Contents

- [Why it folds](#folding)
- [What drives the growth](#drivers)
- [Reaction-diffusion on the surface](#chemistry)
- [The parameters that matter](#parameters)
- [Open surfaces](#boundaries)
- [Cost and reproducibility](#cost)

<a name="folding"></a>

#### Why it folds

One point explains every result: **nothing pushes the surface outward.** The only forces run along the mesh's own edges, which lie in the surface. So the form cannot take up new area by inflating the way a balloon does. It has to absorb that area by bending instead, and bending is folding.

Because of that, *every* driver folds, including the perfectly even one. A driver changes only **where** the folds appear and **how large** they are. Growing evenly folds evenly all over at one size, which is the brain-coral look. Growing in patches folds into lobes with smooth ground between them, which is the branching look.

Two other parts of the model set how the folds behave:

- **Self-avoidance.** Parts of the surface that come near each other, without being near *along* the surface, push apart. A fold then stacks against its neighbor instead of passing through it.
- **Bending resistance.** A sheet with no stiffness buckles at the smallest scale available. The folds then come out the size of a triangle, and the form reads as crumpled paper. Resisting bending makes small wrinkles expensive, so the same growth gathers into broader waves. That resistance is the `stiffness` parameter, and it sets the difference between crumpled and ruffled.

<a name="drivers"></a>

#### What drives the growth

| Driver | Grows | Reads as |
|---|---|---|
| `.uniform` | everywhere equally | even folds all over at one size: brain coral |
| `.curvature` | where the surface already bulges | lobes that sharpen, because a bulge that grows becomes a bigger bulge |
| `.field { position, normal in … }` | wherever your rule says, on a scale of 0 to 1 | whatever you describe, such as a rim, a band, or a noise field |
| `.chemical(SurfaceChemistry)` | where a reaction-diffusion pattern collects | branching coral |

```swift
MeshGrowth(mesh: .icosphere(subdivisions: 3), driver: .uniform)
MeshGrowth(mesh: .icosphere(subdivisions: 3), driver: .curvature)
MeshGrowth(mesh: .icosphere(subdivisions: 3), driver: .chemical(.coral))

// Grow only near the equator, the way a leaf grows at its margin.
MeshGrowth(mesh: .icosphere(subdivisions: 3),
           driver: .field { position, _ in
               1 - smoothstep(0.05, 0.45, abs(position.y))
           })
```

<img src="../../Guide/Images/22-Meshes/GrowingSurface.jpg" alt="Three forms in a row against black: a smooth yellow sphere labeled the starting mesh, an orange ball completely covered in even brain-like folds labeled everywhere, and a flattened orange form with a smooth top and a ruffled rim labeled at the equator" width="680">

`.uniform` is the baseline to start from, because it shows what growth alone produces before any pattern steers it.

<a name="chemistry"></a>

#### Reaction-diffusion on the surface

`.chemical` is the driver that combines two processes. A Gray-Scott reaction runs *in the surface* while the surface grows, and the surface grows where the reaction has collected. So the pattern decides where to add area, and the new area gives the pattern more room to spread into.

**`SurfaceChemistry`** carries the reaction's settings. The most used corners of the parameter space arrive as presets: `.coral`, the default, plus `.spots`, `.maze`, `.mitosis`, and `.worms`. Its `feed` and `kill` are the same two numbers that the texture-space [`Sim.reactionDiffusion`](../Drawing/Effects.md) takes. A pairing that gives a look there gives the same look here.

**`MeshReactionDiffusion`** runs the same reaction on a fixed mesh, which is the surface-texture use rather than the growth one. The pattern develops in the mesh itself, so it has no seam, no stretching, and it needs no texture coordinates.

```swift
let pattern = MeshReactionDiffusion(mesh: .icosphere(subdivisions: 5),
                                    chemistry: .coral, seed: 7)
pattern.step(12)
drawMesh(pattern.displaced(by: 0.06))     // the pattern as relief
```

`values` holds the concentration at each vertex, in the same order as `mesh.positions`, so you can drive anything with it. `displaced(by:)` is the quick way to see it.

Two things about the pace of a chemical growth are worth knowing.

The reaction has to organize into a pattern before it can steer anything, so noise steers most of the opening steps of a chemical growth. Setting **`settleSteps`** runs that opening chemistry all at once on the first step. The surface is refined to its target triangle size and held still while the pattern organizes on it. The first folds then land where the pattern says, so `chemistry` reads as a formed pattern from step one.

The pattern also covers only part of the surface at any time. So at the same `growthRate`, a chemical growth makes area a few times slower than `.uniform`. Allow more steps, or raise `growthRate`. This is a permanent character of the driver rather than something that settling changes.

Both `MeshGrowth` and `MeshReactionDiffusion` weld coincident vertices first. Ollin's mesh generators emit flat-shaded geometry whose triangles share no vertices, so an icosphere is thousands of loose triangles by index. Without welding, nothing can spread across it at all.

<a name="parameters"></a>

#### The parameters that matter

| Parameter | Does | Notes |
|---|---|---|
| `edgeLength` | the triangle size the remesher holds | sets the finest fold the surface can hold, and it is where the cost lives |
| `growthRate` | how fast area is made | at 0 the surface only relaxes |
| `stiffness` | resistance to bending | sets the fold size: raise it for smooth open ruffles, lower it toward 0 for crumpled |
| `repulsionRadius` | how near separate parts may come | past about `3 × edgeLength` it starts pushing on neighbors that are properly that close, so the form inflates instead of folding |
| `maxVertices` | the ceiling on the vertex count | growth stops there and the surface only relaxes, so this sets how far a form develops |
| `settleSteps` | opening chemistry run all at once on the first step | `.chemical` only. The pattern arrives formed instead of organizing during the growth |

`edgeLength` defaults to the mean edge length of the mesh you start from. So a coarse starting mesh grows coarse folds, and a fine one grows fine folds. Passing a starting mesh is usually all the setup you need.

<a name="boundaries"></a>

#### Open surfaces

A closed surface, such as a sphere or a torus, grows into a solid form. An open surface keeps its rim, whether it is a plane, a disc, or a ribbon. The remesher refuses to collapse or flip anything that touches the boundary, and a rim vertex slides *along* the rim rather than into the surface. So a sheet stays a sheet with its edge intact, and it ruffles along that edge, which is the leaf-margin case.

<a name="cost"></a>

#### Cost and reproducibility

Growth is deliberately slow, so a form takes hundreds of steps to develop. Stepping once or twice a frame is the usual rate, and watching it develop is part of the point.

The work per step rises with the vertex count. It is CPU mesh processing, with a full remeshing pass every step, so `maxVertices` is the control that keeps a sketch interactive. A few thousand vertices step comfortably in real time. Nine thousand vertices cost roughly 30 ms a step on an M2, so run one step a frame rather than several.

A seeded growth reproduces exactly. The same seed grows the same form, because every pass runs in a fixed order rather than in a dictionary's order. The small amount of randomness only breaks the starting symmetry. A perfectly symmetric surface has no reason to buckle one way rather than another, which is why the seed exists at all.

### See also

- [`Subdivision surfaces`](./SubdivisionSurfaces.md) - refine the grown mesh into a smoother surface
- [`Isosurfaces`](./Isosurface.md) - the other way to arrive at an organic `Mesh`
- [`Differential growth`](./DifferentialGrowth.md) - the same idea one dimension down, on a line
- [`3D`](../3D/3D.md) - materials, lighting, and shadows for the result
