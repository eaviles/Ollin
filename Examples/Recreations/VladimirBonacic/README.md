#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → VladimirBonacic</sup>

---

## Vladimir Bonačić

| [![DynamicObject](https://media.ollin.art/examples/Recreations/VladimirBonacic/DynamicObject/still-640.jpg?v=5e47dbad)](DynamicObject/) | [![NamaFrieze](https://media.ollin.art/examples/Recreations/VladimirBonacic/NamaFrieze/still-640.jpg?v=45dafcd1)](NamaFrieze/) |  |  |
|---|---|---|---|
| [DynamicObject](DynamicObject/) | [NamaFrieze](NamaFrieze/) |  |  |

**Vladimir Bonačić** (Novi Sad, 1938 to Bonn, 1999) grew up in Zagreb and studied electronics at the University of Zagreb. From 1964 he worked at the Ruđer Bošković Institute, heading its Laboratory of Cybernetics from 1969 to 1973, and he took his doctorate in pattern recognition along the way. He came to art from engineering. His pieces ran on hardware he designed, and he described them in the mathematics that drove them.

His way in was the New Tendencies, the international movement that met in Zagreb from 1961 and treated art as a kind of research. In 1968 and 1969 its fourth meeting, *tendencies 4*, was given over to computers and visual research, one of the first exhibitions of computer art anywhere. Bonačić showed seventeen works there, among them *t4*, a panel of lamps made with the painter Ivan Picelj, and took one of the prizes. The jury praised his way of solving a problem "by including a picture and not a number as a parameter".

Between 1968 and 1971 he made what he called **dynamic objects**: panels of lamps driven by special-purpose computers he designed, five of them for public spaces. Nearly all of them ran on the arithmetic of Galois fields, the finite fields of abstract algebra. He was openly skeptical of computer art that leaned on commercially available display equipment, or on play with randomness and deliberately introduced errors. A random generator, he wrote, "creates an accidental and unique presentation, which has neither value nor importance for human beings." His own objects follow a program in which every pattern is a lawful consequence of the one before. The critique produced one piece that does use chance, *Random 63* (1969), with sixty-three independent sources of true randomness. The rest are pseudo-random, which means their laws can be watched.

- **GF.E 32-S 69/70** is a square of 1,024 white lamps behind aluminum tubes, 64 centimeters across, with the field generator inside it. On its back were a start and a stop, a clock the visitor could set anywhere from a tenth of a second to five, and a row of 32 indicator lamps over 32 push buttons, so the pattern on the front could be read out in binary or set by hand.
- **GF.E (16,4) 69/71** is a relief of the same 1,024 fields at four depths, in sixteen colors, 178 centimeters square and half a ton. Three field generators drive the lights, and sixty-four tone oscillators play through four loudspeakers from the same arithmetic. It was shown at the Paris Biennale in 1971.
- **DIN. PR 18** (1969) was a frieze 36 meters long on the front of the NaMa department store on Kvaternik Square in Zagreb: eighteen panels, each 48 by 88 centimeters and a grid of five by three lamps. It stepped through the 262,143 images of an 18-bit field in a variable rhythm, never faster than one every 200 milliseconds. The square was poorly lit then, so the frieze lit it too. A later one went up on the NaMa store in Ilica, in the center of the city, and another on the front of the Museum of Contemporary Art in Belgrade.

In 1971 he founded the cybernetic art team bcd with the programmer Miro Cimerman and the architect Dunja Donassy. The team moved to Jerusalem in 1972, where Bonačić founded and directed the Program in Art and Science at the Bezalel Academy until 1977. From 1980 he lived in Germany, where the team made computer graphics for television, the election-night coverage among them.

He wrote up the dynamic objects for *Leonardo* in 1974. The article prints the polynomials, which is rare in writing about art, and it names what he found most interesting, something he had seen and mathematicians had not: "One of the most interesting aspects of this work is the demonstration of the different visual appearance of the patterns resulting from the polynomials that had not been noted before by mathematicians who have studied Galois fields."

He belongs in this set because his program survives on the page. The article gives the field, the polynomial, and the rule that assigns each lamp, which is enough to build GF.E 32-S again. The lamps themselves, and the square at night, are what a sketch adds.

Learn more:

- Vladimir Bonačić, [*Kinetic Art: Application of Abstract Algebra to Objects with Computer-Controlled Flashing Lights and Sound Combinations*](https://www.jstor.org/stable/1572890), *Leonardo* 7:3 (1974), the artist's own account, with the polynomials and the figures
- Darko Fritz, [*Vladimir Bonačić: Early Works, Zagreb 1968-1971*](https://darkofritz.net/text/bonacic.html), the fullest short account of the dynamic objects, the public installations, and the critique of randomness
- [*Vladimir Bonačić*](https://digitalna-umjetnost-u-hrvatskoj.eu/en/autori/vladimir-bonacic) in *Digital Art in Croatia 1968-1984*, with the measurements of the NaMa frieze and its degree-18 polynomial
- [*Vladimir Bonačić & bcd: CyberneticArt*](https://zkm.de/en/event/2019/11/vladimir-bonacic-bcd-cyberneticart) at ZKM Karlsruhe (2019), and his [biography](https://zkm.de/en/persons/vladimir-bonacic) there
- Darko Fritz, [*Vladimir Bonačić: Computer-Generated Works Made within Zagreb's New Tendencies Network (1961-1973)*](https://direct.mit.edu/leon/article-abstract/41/2/175/45183), *Leonardo* 41:2 (2008), the scholarly account of the whole body of work

### Recreations here

- [**DynamicObject**](DynamicObject/): after *GF.E 32-S 69/70*. The 32 by 32 square of lamps, built from the arithmetic in the article. Each lamp belongs to one of 32 residue classes, its row and column combined bit by bit, so every class holds one lamp in each row and each column and every pattern is symmetric about the diagonal. The pattern is an element of the field of 2^32 elements modulo x^32 + x^22 + x^2 + x + 1, and bit i of it lights class i. Each tick of the clock multiplies it by x, and because that polynomial is primitive the walk shows every one of its 4,294,967,295 patterns before it repeats one. The back of the object is drawn along the bottom: 32 indicators that show the element in binary, and 32 buttons. Click a button to flip its bit and the walk carries on from there. `clock` is the seconds per pattern and `isRunning` the start and stop; space starts and stops it too. The seed decides where on its walk the object is switched on.

  ```sh
  swift run Example-Recreations-VladimirBonacic-DynamicObject
  ```

  Frames of one run as marks, which is what its laws are read from: every residue class all lit or all dark, the indicators reading the same number, and the later frame equal to the earlier one multiplied by x once for every tick between them:

  ```sh
  swift run Example-Recreations-VladimirBonacic-DynamicObject --export-svg a.svg --frame 660 --seed 55
  swift run Example-Recreations-VladimirBonacic-DynamicObject --export-svg b.svg --frame 6060 --seed 55
  ```

- [**NamaFrieze**](NamaFrieze/): after *DIN. PR 18* (1969). The eighteen panels across the store front at night, drawn to scale at fifty pixels to the meter, so the frieze is as wide as the picture and each panel a small thing in it. Nothing records how the eighteen bits reached the lamps, so the reading here is the plainest one: a panel for each bit, its fifteen lamps together. The seed decides where on the walk it is switched on, and the count in the corner says which image is showing. Image 1 is a single panel at the left, and the walk comes back to it after 262,143 images. The rhythm is a second, shorter field: a degree-4 register gates the clock, so the frieze moves on eight ticks in fifteen and waits on the other seven, always in the same irregular order. The lamps light the wall around them and the square in front. `clock` is the seconds per tick and `usesRhythm` turns the gate off. Set `sendsToWall` and the panels go out as DMX over sACN, universe 1, channels 1 to 18, at the level they are drawn at, so eighteen dimmers make a frieze of your own; `wallAddress` names one node, or leave it empty to multicast.

  ```sh
  swift run Example-Recreations-VladimirBonacic-NamaFrieze
  swift run Example-Recreations-VladimirBonacic-NamaFrieze --param sendsToWall=true --param wallAddress=127.0.0.1
  ```

  Frames of one run as marks, which is what its laws are read from: a panel's fifteen lamps always agree, each frame is the first one multiplied by x once for every step the rhythm let through, and the steps and holds repeat every fifteen ticks. With the wall on, any sACN monitor on this Mac reads the same images in the same order:

  ```sh
  swift run Example-Recreations-VladimirBonacic-NamaFrieze --export-svg a.svg --frame 24 --seed 18
  swift run Example-Recreations-VladimirBonacic-NamaFrieze --export-svg b.svg --frame 1617 --seed 18
  ```

These are homages after Vladimir Bonačić, made for learning. They are not reproductions of specific works, they are not affiliated with or endorsed by the artist's estate, and none of his work was used to make them.
