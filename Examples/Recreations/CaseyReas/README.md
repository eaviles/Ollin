#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Casey Reas</sup>

---

## Casey Reas

| [![Planes](https://media.ollin.art/examples/Recreations/CaseyReas/Planes/still-640.jpg?v=b205d97f)](Planes/) | [![Touching](https://media.ollin.art/examples/Recreations/CaseyReas/Touching/still-640.jpg?v=d3527730)](Touching/) |  |  |
|---|---|---|---|
| [Planes](Planes/) | [Touching](Touching/) |  |  |

**Casey Reas** (born 1972, Troy, Ohio; lives in Los Angeles) writes software that other things carry out, and he wrote the language a great many artists write theirs in. He studied design at the University of Cincinnati, then took a master's at the MIT Media Lab in the Aesthetics and Computation Group under John Maeda, and in 2001, with Ben Fry, made Processing. It is the reason a sketch anywhere has a `setup()` and a `draw()`, this framework included. He has taught at UCLA since 2003, wrote the Processing handbook with Fry, and co-founded the Processing Foundation with Fry and Lauren McCarthy, who made p5.js.

The work in this folder is after the other half of what he does. In 2001 the curator Christiane Paul asked him for a piece for the Whitney's artport, and he answered by asking whether the history of conceptual art has anything to say about software as art. **{Software} Structures** (2004) was his answer: three written structures, implemented by him and by three other programmers, Jared Tarbell, Robert Hodgin and William Ngan, in three languages, twenty-six pieces of software out of three short texts. He took the model straight from Sol LeWitt, whose wall drawings are instructions that other people draw, and asked what happens when the drafter is a machine.

The **Process** works (2004-2010) are what he built on that. Each one is a short text with two parts. A library of **forms** (a circle, a line) and numbered **behaviors** ("move in a straight line", "constrain to surface", "change direction while touching another element") combine into **elements**: an element is one form plus a list of behaviors. A **process** then says how many of which element fill a surface, and what to draw from the relations between them, in two or three sentences. There are fifteen of them, numbered 4 through 18, and the *Process Compendium* collects them.

The order matters. The text comes first, and Reas is explicit that the software is secondary to it, a translation into which somebody's decisions go. What the elements do is all he specifies. The picture is a side effect of their behavior over time, and in most of the processes the elements themselves are never drawn at all, so the surface holds only the relations they had.

He belongs in this set twice over. Once for Processing, without which most of the artists in the folders beside this one would have had a harder time, and once because the *Process* texts ask the question this whole set is built around: where does the work live, in the instruction or in the thing that comes out.

Learn more:

- [Casey Reas on Wikipedia](https://en.wikipedia.org/wiki/Casey_Reas)
- [reas.com/process](https://reas.com/process), the *Process* works
- [*{Software} Structures*](https://artport.whitney.org/commissions/softwarestructures/text.html) at the Whitney artport, with the three structures and every implementation
- [*Process Compendium 2004-2010*](https://reas.com/compendium_b_p/), the book that collects them
- [Processing](https://processing.org) and the [Processing Foundation](https://processingfoundation.org)

### Recreations here

- [**Touching**](Touching/): a surface filled with circles that move in a straight line, stay on the surface, turn while they touch, and move away from what they overlap. The circles are never drawn. What is drawn is a line between the centers of two of them while they touch, valued from black to white by how far apart the centers are, and the surface keeps every one of those lines, so the picture is the record of the meetings rather than of the elements. `elements`, `smallest` and `largest` are what the surface is filled with, `speed` and `turn` how they behave, `ink` and `lineWeight` the pen. A press starts a new surface. An original Ollin interpretation: the instruction is our own, written in the form Reas writes his in.

  ```sh
  swift run Example-Recreations-CaseyReas-Touching
  ```

  The lines of one frame, each a chord no longer than two of the largest elements:

  ```sh
  swift run Example-Recreations-CaseyReas-Touching --export-svg surface.svg --frame 700
  ```

- [**Planes**](Planes/): the same kind of instruction in the present tense. The elements are lines that wrap around the edges, turn toward the direction of what they touch, and wander a little on their own, and the mark is the quadrilateral through the four endpoints of a touching pair, which grows more opaque while they stay together and fades once they part. The two behaviors pull against each other, so flocks gather, hold a shape long enough for their planes to go solid, and come apart again. `elements` and `length` are the surface, `reach` how near counts as touching, `align` and `drift` the pair to hold against each other, `rise` and `fall` the seconds a plane takes to arrive and to go. An original Ollin interpretation, the same way.

  ```sh
  swift run Example-Recreations-CaseyReas-Planes
  ```

  The whole picture, since nothing here is accumulated:

  ```sh
  swift run Example-Recreations-CaseyReas-Planes --export-svg planes.svg --frame 700
  ```

This is a homage after Casey Reas, made for learning. It isn't a reproduction of a specific work, and it isn't affiliated with or endorsed by the artist.
