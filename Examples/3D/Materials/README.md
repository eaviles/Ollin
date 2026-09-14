#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [3D](../README.md) → Materials</sup>

---

## Materials

| [![BrushedMetal](https://media.ollin.art/examples/3D/Materials/BrushedMetal/still-640.jpg?v=819826df)](BrushedMetal/) | [![CoatAndCloth](https://media.ollin.art/examples/3D/Materials/CoatAndCloth/still-640.jpg?v=9dc6bd1e)](CoatAndCloth/) | [![Decals](https://media.ollin.art/examples/3D/Materials/Decals/still-640.jpg?v=f04fed92)](Decals/) | [![Detail](https://media.ollin.art/examples/3D/Materials/Detail/still-640.jpg?v=013fca2f)](Detail/) |
|---|---|---|---|
| [BrushedMetal](BrushedMetal/) | [CoatAndCloth](CoatAndCloth/) | [Decals](Decals/) | [Detail](Detail/) |
| [![Explorer](https://media.ollin.art/examples/3D/Materials/Explorer/still-640.jpg?v=1eb85080)](Explorer/) | [![Glass](https://media.ollin.art/examples/3D/Materials/Glass/still-640.jpg?v=155ce580)](Glass/) | [![Inked](https://media.ollin.art/examples/3D/Materials/Inked/still-640.jpg?v=f376a7db)](Inked/) | [![LiveSurface](https://media.ollin.art/examples/3D/Materials/LiveSurface/still-640.jpg?v=d831912b)](LiveSurface/) |
| [Explorer](Explorer/) | [Glass](Glass/) | [Inked](Inked/) | [LiveSurface](LiveSurface/) |
| [![Matcap](https://media.ollin.art/examples/3D/Materials/Matcap/still-640.jpg?v=907c3afc)](Matcap/) | [![Materials](https://media.ollin.art/examples/3D/Materials/Materials/still-640.jpg?v=136060de)](Materials/) | [![NormalMaps](https://media.ollin.art/examples/3D/Materials/NormalMaps/still-640.jpg?v=d852fdd3)](NormalMaps/) | [![Parallax](https://media.ollin.art/examples/3D/Materials/Parallax/still-640.jpg?v=cc9d1a39)](Parallax/) |
| [Matcap](Matcap/) | [Materials](Materials/) | [NormalMaps](NormalMaps/) | [Parallax](Parallax/) |
| [![PhysicalMaterials](https://media.ollin.art/examples/3D/Materials/PhysicalMaterials/still-640.jpg?v=efde6f57)](PhysicalMaterials/) | [![SeeThrough](https://media.ollin.art/examples/3D/Materials/SeeThrough/still-640.jpg?v=4a4cc60b)](SeeThrough/) | [![Subsurface](https://media.ollin.art/examples/3D/Materials/Subsurface/still-640.jpg?v=4875baea)](Subsurface/) | [![SurfaceMaps](https://media.ollin.art/examples/3D/Materials/SurfaceMaps/still-640.jpg?v=77317ef9)](SurfaceMaps/) |
| [PhysicalMaterials](PhysicalMaterials/) | [SeeThrough](SeeThrough/) | [Subsurface](Subsurface/) | [SurfaceMaps](SurfaceMaps/) |
| [![ThinFilm](https://media.ollin.art/examples/3D/Materials/ThinFilm/still-640.jpg?v=e54f079c)](ThinFilm/) | [![Triplanar](https://media.ollin.art/examples/3D/Materials/Triplanar/still-640.jpg?v=800a89ba)](Triplanar/) |  |  |
| [ThinFilm](ThinFilm/) | [Triplanar](Triplanar/) |  |  |

This group covers what surfaces are made of: stylized finishes, physically based metal, glass, subsurface, thin film, and the map set that varies any of them per pixel.

| Sketch | What it shows |
| --- | --- |
| [Materials](Materials/) | The material library. One orbiting sphere grid wears each built-in `Material` (`.iridescent`/`.soapBubble`/`.velvet`/`.jade`/`.toon`/`.gooch`/…), and the view-angle finishes shift as it turns. |
| [Inked](Inked/) | The cartoon look: toon solids with an ink line around every shape (`outline(width:color:)`), under a three-point rig that rides the camera (`relativeTo(.camera)`), a world sun, or a `headlight()`, switched by a parameter. |
| [PhysicalMaterials](PhysicalMaterials/) | The physically-based finish as a metallic × roughness sweep. `Material.physicallyBased` shades one sphere grid from tight mirror highlights to matte, and from dielectric to metal. |
| [Matcap](Matcap/) | Matcaps. A whole surface-and-lighting look is baked into one sphere texture and sampled by the view normal (`matcap(_:)`). That gives chrome, clay, wax, or a cel look with no scene lights at all. |
| [Explorer](Explorer/) | The material explorer. Every finish is shown on one shape, with its parameters to adjust. |
| [SurfaceMaps](SurfaceMaps/) | The rest of the surface-map set: metallic-roughness, occlusion, and emissive maps, each varying a finish per pixel. |
| [NormalMaps](NormalMaps/) | Normal maps: per-pixel surface relief without per-pixel geometry. |
| [Detail](Detail/) | Detail maps: texture that stays sharp under a close look. |
| [Parallax](Parallax/) | A photographed stone wall read two ways: parallax occlusion and real displacement. |
| [Triplanar](Triplanar/) | Talavera tilework on meshes with no uvs at all, projected from three directions. |
| [Decals](Decals/) | Pictures stamped onto the scene, projected rather than mapped. |
| [Glass](Glass/) | Physically-based transmission and refraction. |
| [SeeThrough](SeeThrough/) | The scene showing through glass, with no ray tracing. |
| [LiveSurface](LiveSurface/) | The camera frame wraps a globe and lights it, so a live feed serves as a surface. |
| [CoatAndCloth](CoatAndCloth/) | Clearcoat and sheen, the two layered finishes on the physically-based material. |
| [Subsurface](Subsurface/) | Light that travels under the surface before it comes back out. |
| [BrushedMetal](BrushedMetal/) | Anisotropic specular: brushed, turned, and satin finishes whose highlight is a streak instead of a dot. |
| [ThinFilm](ThinFilm/) | Thin-film interference two ways: a series of nm thicknesses on a physically-based surface, and animated soap bubbles on thin glass. |

Run one with `swift run Example-3D-Materials-<Name>`, for example `swift run Example-3D-Materials-Materials`.
