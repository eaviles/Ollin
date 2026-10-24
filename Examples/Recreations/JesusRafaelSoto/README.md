#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Jesús Rafael Soto</sup>

---

## Jesús Rafael Soto

| [![Penetrable](https://media.ollin.art/examples/Recreations/JesusRafaelSoto/Penetrable/still-640.jpg?v=5e601edd)](Penetrable/) | [![Vibracion](https://media.ollin.art/examples/Recreations/JesusRafaelSoto/Vibracion/still-640.jpg?v=b0f8bd13)](Vibracion/) |  |  |
|---|---|---|---|
| [Penetrable](Penetrable/) | [Vibracion](Vibracion/) |  |  |

**Jesús Rafael Soto** (Ciudad Bolívar, Venezuela, 1923; Paris, 2005) studied at the school of fine and applied arts in Caracas from 1942 to 1947, and in 1950 a government grant took him to Paris, where he lived for the rest of his life. He was in *Le Mouvement* at the Galerie Denise René in 1955, the show that helped launch kinetic art, though his own works hardly move. What moves is the person looking at them.

From the late 1950s he painted grounds of fine black and white stripes and hung things a hand's width in front of them: wires, and from 1963 painted rods, on nylon threads. A dark wire over a black stripe disappears, and over a white one it shows, so as you walk past, the wire breaks into dashes that run along it, flickers, and seems to dissolve. These are the *Vibraciones*. In 1962 he began the *Escrituras*, the writings, in which the wire is bent into curves and loops like a hand writing across the stripes. "The vibration is purely optical," he told the critic Guy Brett, "without physical substance." His London retrospective of 1965 at Signals was called *15 Years of Vibrations*.

In 1967 he showed the *Muro panorámico vibrante* at the Galerie Denise René, a first version of the idea built into a wall, and in 1969 he made the first *Penetrable* proper: a room of hanging threads or tubes, close enough to read as a solid from across the room, that you walk into. He made twenty to twenty-five of them. "When you enter a penetrable," he said, "you have the sensation of being in a light swirl, a total plenitude of vibrations." In 1973 the Museo de Arte Moderno Jesús Soto opened in Ciudad Bolívar, in a building by Carlos Raúl Villanueva. The largest Penetrable, designed for the Museum of Fine Arts, Houston, in 2004, was finished by the Atelier Soto after his death and first shown in 2014: 24,000 PVC tubes, 28 feet long, over 2,600 square feet, painted so that at rest they make a yellow orb floating in the room.

He belongs in this set because his work is about what changes when the viewer moves, which is the part of a picture a screen can let you take hold of. The first sketch here gives the pointer the viewer's place, and the second gives the camera a body.

He is the folder's second artist from Venezuela, after [Gego](../Gego/).

Learn more:

- [*Vibration*](https://sammlung.staedelmuseum.de/en/work/vibration) (1961) at the Städel Museum, Frankfurt, a row of pendulum wires and a tangle of bent wire over a finely striped panel
- [*Vibration jaune*](https://www.centrepompidou.fr/en/ressources/oeuvre/UJEzYfg) (1965) at the Centre Pompidou, Paris, yellow rods hung level on nylon threads over a field of stripes, with the museum's essay and his words to Guy Brett, and the [*Cube pénétrable*](https://www.centrepompidou.fr/en/ressources/oeuvre/cBAK8xR) (1996) beside it
- [*Grande écriture*](https://sammlung.kunstpalast.de/en/objects/41888/grande-ecriture) (1972) at the Kunstpalast, Düsseldorf, semicircles, curves, and straight lines of wire across a three-meter panel
- [*The Houston Penetrable*](https://emuseum.mfah.org/objects/107105) at the Museum of Fine Arts, Houston, and the museum's [exhibition page](https://mfah.org/exhibitions/jesus-rafael-soto) for it

### Recreations here

- [**Vibracion**](Vibracion/): the *Vibraciones* and the *Escrituras*. Move the pointer and you move where you stand. A ground of black and white stripes is drawn at a declared pitch, a whole number of them across the panel, and every wire hangs a measured distance in front of it, so seen from where you stand it lands on the stripes by its parallax, near wires sliding farther than far ones. The shadows a lamp throws on the ground stay where they are while the wires move over them. `work` picks the panel: the 1961 *Vibration*, a row of straight wires hung like pendulums with a tangle of bent wire and one heavy rod in front of them; *Vibration jaune*, yellow rods tied on one thread over level stripes under a yellow field; or *Grande écriture*, a long panel striped between two white bands with wire bent into semicircles, curves, and strokes hanging over it and down past it. The 1961 row is itself a grating, its wires `rowSpacing` stripes apart, so the two beat: a group of wires shows, the next group is gone, and a step sideways moves that beat about twenty-five times as far as it moves the wires, the other way. While the pointer rests you drift on your own and the wires swing a little on their threads. `stripePitch`, `depth`, `distance`, `standX`, `standY`, `sway`, `swing`, `rowWires`, `rowSpacing`, `tangle`, `rods`, `lean`, `strokes`, and `shadow` are the measures. An original Ollin interpretation written from the works and the museums' descriptions; he bent the wires by hand, so there is no code to port.

  ```sh
  swift run Example-Recreations-JesusRafaelSoto-Vibracion
  ```

  The panel as a file: the stripes as rectangles at the declared pitch, and every wire and its shadow as a line, so the pitch, the counts, the parallax, and the beat can be read back from it:

  ```sh
  swift run Example-Recreations-JesusRafaelSoto-Vibracion --param sway=0 --param swing=0 --export-svg vibracion.svg
  ```

- [**Penetrable**](Penetrable/): *The Houston Penetrable*, at the record's measurements. 200 tubes across 19.99 meters and 120 deep across 12.12, one every ten centimeters, each 8.48 meters from the frame to just above the floor, and each painted yellow along the stretch of it that passes through an orb hanging in the middle of the room. From outside, those stretches line up into one floating form; from inside, it comes apart into strands overhead. A visitor walks a long loop in through the front, under the orb, out the back, and round again. Their body pushes aside every tube it meets at the hip, each tube swings back from the frame as a pendulum does and settles, and the paint goes with it. `view` is the visitor's own eyes, where a drag looks around, or the gallery, turned `around` the room. `pace`, `reach`, `air`, and `haze` are the walk, the body, the room's air, and how much the clear tubes show. The orb's size and height are this sketch's reading; the record does not give them.

  ```sh
  swift run Example-Recreations-JesusRafaelSoto-Penetrable
  ```

  Every tube as a line through the gallery's eye, the clear lengths gray and the painted ones yellow, and the visitor as a line with a ring at the hip:

  ```sh
  swift run Example-Recreations-JesusRafaelSoto-Penetrable --param view=gallery --frame 1500 --export-svg penetrable.svg
  ```

These are homages after Jesús Rafael Soto, made for learning. They are not reproductions of specific works, and they are not affiliated with or endorsed by the artist, his estate, the Atelier Soto, or the museums that hold the works.
