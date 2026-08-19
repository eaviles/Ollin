#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Mesh growth</sup>

---

## Mesh growth

A surface that makes more of itself than it has room for. **`MeshGrowth`** takes a mesh, pushes its vertices apart, and keeps the triangles a fixed size by splitting the ones that stretch. The surface gains area. The area has nowhere to go. It folds.

```swift
// Held across frames, seeded once:
let coral = MeshGrowth(mesh: .icosphere(subdivisions: 3),
                       driver: .chemical(.coral), seed: 7)

// In draw():
coral.step()
material(.dielectric(roughness: 0.4))
drawMesh(coral.mesh)
```

That is the whole idea, and everything that looks designed about the result comes out of it. The forms are the ones growing things arrive at: brain coral, a ruffled leaf margin, a lettuce edge, something branching.

### Contents

- [Why it folds](#folding)
- [What drives the growth](#drivers)
- [Reaction-diffusion on the surface](#chemistry)
- [The knobs that matter](#knobs)
- [Open surfaces](#boundaries)
- [Cost and reproducibility](#cost)

<a name="folding"></a>

#### Why it folds

Worth being clear about, because it explains every result: **nothing pushes the surface outward.** The only forces run along the mesh's own edges, and those lie in the surface. So the form cannot answer new area by inflating the way a balloon does. Whatever area it makes has to be absorbed by bending, and bending is folding.

This means *every* driver folds, including the perfectly even one. What a driver changes is **where** the folds appear and **how large** they are. Growing evenly folds evenly all over, at one size, which is the brain-coral look. Growing in patches folds into lobes with smooth ground between them, which is the branching look.

Two other pieces make the folds behave:

- **Self-avoidance.** Parts of the surface that come near each other without being near *along* the surface push apart, so a fold stacks against its neighbor instead of passing through it.
- **Bending resistance.** A sheet with no stiffness buckles at the smallest scale available. The folds then come out the size of a triangle, and the form reads as crumpled paper. Resisting bending makes small wrinkles expensive, so the same growth gathers into broader waves. That is the `stiffness` knob, and it is the difference between crumpled and ruffled.

<a name="drivers"></a>

#### What drives the growth

| Driver | Grows | Reads as |
|---|---|---|
| `.uniform` | everywhere equally | even folds all over, one scale: brain coral |
| `.curvature` | where the surface already bulges | lobes that sharpen, because a bulge that grows becomes a bigger bulge |
| `.field { position, normal in … }` | wherever your rule says, 0 to 1 | whatever you describe: a rim, a band, a noise field |
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

`.uniform` is the baseline worth starting from: it shows what growth alone produces before any pattern steers it.

<a name="chemistry"></a>

#### Reaction-diffusion on the surface

`.chemical` is the one that composes two processes. A Gray-Scott reaction runs *in the surface* while the surface grows, and the surface grows where the reaction has collected. The pattern decides where to add area, and the new area gives the pattern more room to spread into.

**`SurfaceChemistry`** carries the reaction's settings. The well-traveled corners of the parameter space arrive as presets: `.coral`, the default, plus `.spots`, `.maze`, `.mitosis`, and `.worms`. Its `feed` and `kill` are the same two numbers the texture-space [`Sim.reactionDiffusion`](../Drawing/Effects.md) takes. A pairing that gives a look there gives the same look here.

The same reaction runs on a fixed mesh through **`MeshReactionDiffusion`**, which is the surface-texture use rather than the growth one. The pattern develops in the mesh itself, so it has no seam, no stretching, and needs no texture coordinates.

```swift
let pattern = MeshReactionDiffusion(mesh: .icosphere(subdivisions: 5),
                                    chemistry: .coral, seed: 7)
pattern.step(12)
drawMesh(pattern.displaced(by: 0.06))     // the pattern as relief
```

`values` is the concentration at each vertex, matching `mesh.positions` by index, so you can drive anything with it. `displaced(by:)` is the quick way to see it.

Two things about pace are worth knowing.

The reaction has to organize into a pattern before it can steer anything, so a chemical growth's opening steps are steered mostly by noise. Setting **`settleSteps`** runs that opening chemistry all at once when the first step is taken. The surface is refined to its target triangle size, holding still, and the pattern organizes on it. The first folds then land where the pattern says, and `chemistry` reads as a formed pattern from step one.

The pattern also only ever covers part of the surface. At the same `growthAmount` a chemical growth therefore makes area a few times slower than `.uniform`. Budget more steps, or raise `growthAmount`. That is a permanent character of the driver rather than something settling changes.

Both weld coincident vertices first. Ollin's mesh generators emit flat-shaded geometry whose triangles share no vertices. An icosphere is therefore, by index, thousands of loose triangles. Without welding, nothing can spread across it at all.

<a name="knobs"></a>

#### The knobs that matter

| Knob | Does | Notes |
|---|---|---|
| `edgeLength` | the triangle size the remesher holds | sets the finest fold the surface can hold, and is where the cost lives |
| `growthAmount` | how fast area is made | 0 leaves the surface only relaxing |
| `stiffness` | resistance to bending | the fold size: raise for smooth open ruffles, drop toward 0 for crumpled |
| `repulsionRadius` | how near separate parts may come | past about `3 × edgeLength` it starts pushing on neighbors that are legitimately that close, and the form inflates instead of folding |
| `maxVertices` | the ceiling | growth stops when reached and the surface only relaxes, so it decides how far a form develops |
| `settleSteps` | opening chemistry run all at once on the first step | `.chemical` only; the pattern arrives formed instead of organizing mid-growth |

`edgeLength` defaults to the mean edge length of the mesh you start from. A coarse seed therefore grows coarse folds, and a fine one grows fine ones. Passing a starting mesh is usually all the setup needed.

<a name="boundaries"></a>

#### Open surfaces

A closed surface (a sphere, a torus) grows into a solid form. An open one keeps its rim, whether it is a plane, a disc, or a ribbon. The remesher declines to collapse or flip anything touching the boundary, and a rim vertex slides *along* the rim rather than into the surface. So a sheet stays a sheet with its edge intact, and ruffles along it, which is the leaf-margin case.

<a name="cost"></a>

#### Cost and reproducibility

Growth is deliberately slow: a form takes hundreds of steps to develop. Stepping once or twice a frame is the usual rate, and watching it happen is part of the point.

The work per step rises with the vertex count, and it is real CPU mesh processing with a full remeshing pass every step. `maxVertices` is therefore the dial that keeps a sketch interactive. A few thousand vertices steps comfortably in real time. Nine thousand costs roughly 30 ms a step on an M2, so it wants one step a frame rather than several.

A seeded growth reproduces exactly. The same seed grows the same form, and every pass runs in a fixed order rather than a dictionary's. The small amount of randomness only breaks the starting symmetry. A perfectly symmetric surface has no reason to buckle one way rather than another, which is why the seed exists at all.

### See also

- [`Subdivision surfaces`](./SubdivisionSurfaces.md) - refine the grown mesh into something smoother still
- [`Isosurfaces`](./Isosurface.md) - the other way to arrive at an organic `Mesh`
- [`Differential growth`](./DifferentialGrowth.md) - the same idea one dimension down, on a line
- [`3D`](../3D/3D.md) - materials, lighting, and shadows for the result
