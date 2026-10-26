#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Carlos Cruz-Diez</sup>

---

## Carlos Cruz-Diez

| [![Chromosaturation](https://media.ollin.art/examples/Recreations/CarlosCruzDiez/Chromosaturation/still-640.jpg?v=2fe003c4)](Chromosaturation/) | [![Physichromie](https://media.ollin.art/examples/Recreations/CarlosCruzDiez/Physichromie/still-640.jpg?v=e78bc448)](Physichromie/) |  |  |
|---|---|---|---|
| [Chromosaturation](Chromosaturation/) | [Physichromie](Physichromie/) |  |  |

**Carlos Cruz-Diez** (Caracas, 1923; Paris, 2019) studied at the school of fine and applied arts in Caracas from 1940 to 1945 and later taught there. In the fall of 1960 he settled in Paris with his family, and he worked there for the rest of his life. "In my works, nothing is left to chance," he said; "everything is intended, planned, and programmed." And: "I don't get inspired: I reflect."

What he reflected on was color as something that happens, in time and in space, rather than something a surface holds. In 1959 he made the first *Physichromie*: narrow strips of colored cardboard laid flat on a ground, with thin blades of cardboard standing upright between them, later of plastic or metal. Seen straight on, you see the strips and the painted edges of the blades. From the side, each blade hides the ground beside it and shows you its own face, so the picture is made where you stand and changes as you walk past. The foundation that keeps his work calls a Physichromie a "light trap." He went on making them for sixty years; Tate holds *Physichromie No. 113* (1963, reconstructed 1976) and *Physichromie No. 123* (1964). The same year he began the *Couleur Additive* pictures, flat planes of color that meet along an edge: "When one plane of color touches another, a darker vertical line appears at the point of contact. This virtual line in fact contributes a third color that is not in the support." The additive yellow of 1959 was made of two fine lines, one green and one red. From 1963 the *Inductions Chromatiques* put the afterimage to work on the panel.

In 1965 he conceived the *Chromosaturation*, part of a larger *Deconditioning Labyrinth* that was never fully built: three chambers, one red, one green, and one blue, each flooded with its one color of light and holding nothing else. It was first shown at the *Cinétique* exhibition in Grenoble in 1968, and built for the street in Paris in 1969, at Place Henri Mondor on the Boulevard Saint-Germain. The retina, the foundation writes, is "accustomed to receive a wide range of colors simultaneously," and a room of one color disturbs it; the eye adapted to one room sees the next more vividly than it is. Museums have built it since: the Museum of Fine Arts, Houston (1965/2004) and the Pérez Art Museum Miami (1965/2007) hold their own.

His family keeps his legacy through the Cruz-Diez Foundation in Houston, the Atelier Cruz-Diez in Paris, and Articruz, the workshop in Panama City that continues what his Caracas workshop made.

He belongs in this set because his pictures are made by the person looking at them, which is the part of a picture a screen can give you to hold: the first sketch here gives the pointer the viewer's place, and the second walks the camera through the rooms and models what the eye does on the way.

He is the folder's third artist from Venezuela, after [Gego](../Gego/) and [Jesús Rafael Soto](../JesusRafaelSoto/).

Learn more:

- The Cruz-Diez Foundation's pages on the [*Physichromie*](https://cruz-diez.com/works/physichromie-1959-2019/), the [*Couleur Additive*](https://cruz-diez.com/works/couleur-additive/), and the [*Chromosaturation*](https://cruz-diez.com/works/chromosaturation/), and its [account of the artist](https://www.cruz-diez.com/about/)
- [*Carlos Cruz-Diez's Physichromies: Between Centre and Periphery*](https://www.tate.org.uk/research/tate-papers/32/carlos-cruz-diez-physichromies), a Tate paper on how the series was built and read, and Tate's record of [*Physichromie No. 113*](https://www.tate.org.uk/art/artworks/cruz-diez-physichromie-no-113-t02094)
- [*Chromosaturation*](https://www.pamm.org/?p=37369) at the Pérez Art Museum Miami, with the museum's account of the three chambers

### Recreations here

- [**Physichromie**](Physichromie/): the *Physichromies* and the *Couleur Additive*. Move the pointer and you move where you stand, left and right across the panel and up for farther away. `work` picks the panel. **physichromie** is a panel of modules at a declared `pitch`, each a blade standing at its left edge and `strips` fine strips of color on the ground up to the next. The ground alternates two colors, each blade carries one color on its left face and another on its right, and the panel is laid out in regions, a base and a few forms by seed, each with its own set of colors, so a square that is there from the left is gone from the right. The geometry is the stated one: a blade `blade` centimeters tall at `x`, seen from `distance` centimeters away standing `v` centimeters to the right of the middle, lands its top on the ground at `x - (v - x) * blade / (distance - blade)`, hides that much ground on the side away from you, shows its face toward you over the same width, and carries its edge, `thickness` millimeters, at the far end of the face; a nearer blade covers a farther one. **additive** is a *Couleur Additive*: vertical planes of flat color, and across every joint a band `joint` centimeters wide of fine lines in the two neighbors' colors, which merge as you step back. While the pointer rests you drift from side to side by `sway`.

  ```sh
  swift run Example-Recreations-CarlosCruzDiez-Physichromie
  ```

  The panel as a file, seen from 35 centimeters to the right: every strip, face, and edge as a rectangle, so the pitch, the counts, the occlusion, and the order can be read back from it:

  ```sh
  swift run Example-Recreations-CarlosCruzDiez-Physichromie --param sway=0 --param standX=35 --export-svg physichromie.svg
  ```

- [**Chromosaturation**](Chromosaturation/): three chambers in a row, `chamberWidth` by `chamberDepth` meters and `chamberHeight` high, white matte inside, each lit by two panels of one color in its ceiling, with a doorway in every partition and in both end walls. A visitor walks in at one end, through the green, the red, and the blue, out the far end, and round the back to come in again, at `pace` meters a second, and the camera is their eyes; drag to look around. Where a room's light reaches through a doorway into the next, the two colors meet on the floor and the walls. The eye's adaptation is modeled and named: the light around the eye is taken as the mix of the rooms' colors by where the eye stands, in linear light, and each channel's gain heads for the inverse of that channel's share, `adaptation` of the way, never past `maxGain`, drifting there over `adaptationTime` seconds. The gains multiply the finished frame, so a red room pales as you stand in it, and the green one you step into next burns. `adaptedTo` is what the eye brings in at the start, and `pace` at 0 stands still.

  ```sh
  swift run Example-Recreations-CarlosCruzDiez-Chromosaturation
  ```

  The plan: the three rooms in their colors, the walls with their doorways, the lights, the walk, and where the visitor is:

  ```sh
  swift run Example-Recreations-CarlosCruzDiez-Chromosaturation --frame 900 --export-svg chromosaturation.svg
  ```

These are homages after Carlos Cruz-Diez, made for learning. They are not reproductions of specific works, and they are not affiliated with or endorsed by the artist, his family, the Cruz-Diez Foundation, the Atelier Cruz-Diez, Articruz, or the museums that hold the works.
