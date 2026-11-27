#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Jared Tarbell</sup>

---

## Jared Tarbell

| [![Substrate](https://media.ollin.art/examples/Recreations/JaredTarbell/Substrate/still-640.jpg?v=eb89a361)](Substrate/) |  |  |  |
|---|---|---|---|
| [Substrate](Substrate/) |  |  |  |

| Born | Lives in | Wing |
|---|---|---|
| Albuquerque, New Mexico, 1973 | Albuquerque | [Growth](../README.md#growth) |

### His life

**Jared Tarbell** is an American generative artist and programmer from New Mexico, and a co-founder of Etsy. He was born in Albuquerque, met his first computer in 1987, and took a degree in computer science at New Mexico State University.

From about 2000 to 2004 he kept levitated.net, a site of small Flash experiments, each given away with its source. Then came **complexification.net**, which he calls his Gallery of Computation. The works he published there, written in Processing and Flash, became one of the reference points of early generative art. In 2004 the Whitney Museum's Artport commissioned him and two other programmers to write Casey Reas's *{Software} Structures* out as running code.

Rob Kalin found him through that gallery and asked him to work on Etsy, which started in 2005. There he built search tools, the search by color among them, and he left in 2011. Back in Albuquerque he ran a workshop, the Levitated Toy Factory, for about eighteen months, and he still does a great deal of laser cutting and woodworking. He still writes drawing programs too, and he has said that every new one, for the rest of his life, will be released with its code.

### What he made

His pieces grow from simple local rules run at scale, so thousands of small marks build up into cities, sand paintings, and swarms. He gives the programs away in a form that can be changed. "I believe all code is dead unless executing within the computer," he wrote on the gallery's own page.

**"Substrate" (2003)** is his best-known work. Straight cracks move across the plane and stop where they meet an older crack. A new crack then starts at a right angle to the existing pattern. As this repeats, the surface divides into blocks, like the street map of an unplanned city. A translucent wash he calls a *sand painter* shades the open space beside each line, in colors taken from a painting by Jackson Pollock. He has said he saw the algorithm in a coffee shop in Santa Fe, in a window sticker the sun had cracked.

### Rebuilding his work

*Substrate* is a rule for one crack: grow straight, stop at an older crack, and start a new one at a right angle. Nobody draws the city. It comes from running that rule thousands of times, which is what a sketch's frame loop does. Rebuilding it also left something in the framework: the crack growth is now `CrackGrowth`, which any sketch can call.

- [**Substrate**](Substrate/): a city grown from colliding cracks, after Tarbell's *Substrate* (2003).

  Each crack drags a sand-grain wash across the open space beside it. Click to grow a fresh city from the next seed. The framework provides the technique as [`CrackGrowth`](../../../Docs/Generators/CrackGrowth.md).

  ```sh
  swift run Example-Recreations-JaredTarbell-Substrate
  ```

### Further reading

- [*Substrate* on complexification.net](http://www.complexification.net/gallery/machines/substrate/)
- [levitated.net](http://www.levitated.net), his earlier gallery
- [His own page for *Substrate*](https://www.jaredstarbell.com/algorithms/substrate/), with the rule, the sand painter, and the palette in his words
- [His biography](https://complexification.net/programmer.html) and [his note on the medium](https://complexification.net/medium.html) on complexification.net, the second on why he gives the code away
- [An interview with Jason Bailey at Artnome](https://www.artnome.com/news/2020/8/24/interview-with-generative-artist-jared-tarbell) (2020), on levitated.net, Etsy, the Toy Factory, and the coffee shop where *Substrate* began
- [An interview at Right Click Save](https://www.rightclicksave.com/article/the-interview-jared-s-tarbell-generative-art-etsy) (2024), on Flash, Processing, and releasing the code
- [*{Software} Structures*](https://whitney.org/exhibitions/software-structures) at the Whitney Museum, the 2004 commission
- ["Etsy: an online art cache"](https://www.dailylobo.com/article/2011/04/etsy_an_online_art_cache), a 2011 profile in the Daily Lobo, the University of New Mexico's student paper, on his search tools

### About these homages

These are homages after Jared Tarbell, made for learning. They aren't reproductions of specific works, and they aren't affiliated with or endorsed by the artist.
