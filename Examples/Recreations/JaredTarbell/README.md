#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [Recreations](../README.md) → Jared Tarbell</sup>

---

## Jared Tarbell

| [![HappyPlace](https://media.ollin.art/examples/Recreations/JaredTarbell/HappyPlace/still-640.jpg?v=3042d816)](HappyPlace/) | [![SandTraveler](https://media.ollin.art/examples/Recreations/JaredTarbell/SandTraveler/still-640.jpg?v=4f9d1c3b)](SandTraveler/) | [![Substrate](https://media.ollin.art/examples/Recreations/JaredTarbell/Substrate/still-640.jpg?v=eb89a361)](Substrate/) |  |
|---|---|---|---|
| [HappyPlace](HappyPlace/) | [SandTraveler](SandTraveler/) | [Substrate](Substrate/) |  |

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

**"Happy Place" (2004)** begins with nodes standing on a circle. The program makes some of them friends by chance, more often two that stand close together. After that each node has, in his words, "only two goals in mind". It wants to move close to its friends, "but no closer than some minimum distance", and to keep away from everyone else "as reasonably as possible". No arrangement gives every node both, so the ring folds up and keeps shifting. "Nervously, it re-arranges its configuration as a result of the individual desires of the nodes it is composed of," he wrote. The nodes are not what he drew. He drew the friendships, each with what he calls a Sand Stroke, the same kind of translucent sand that shades *Substrate*, and let it pile up while the system moved.

**"Sand Traveler" (2004)** was a commission for Sónar 2004 in Barcelona, as the note at the top of its source says. He describes it as "a rendering of 1,000 traveling particles, each in pursuit of another". The travelers are not drawn either. The sheet keeps what lies between a chaser and the one it follows. As he puts it: "Over time, patterns of travel are exposed as sweeping paths of color." He showed three versions. The first spreads the color evenly along the line, which gives smooth bands. The second lays it with the Sand Stroke. The third turns the Sand Stroke a quarter turn, so it paints across the chase, and those pictures, he wrote, "almost seem nervously alive".

### Rebuilding his work

Each of these pieces is a small rule for one thing: a crack, a node, a traveler. Nobody draws the city, the folded ring, or the whorl. They come from running the rule thousands of times on a sheet that keeps everything drawn on it, which is what a sketch's frame loop and a canvas that is never cleared give you. Rebuilding *Substrate* also left something in the framework: the crack growth is now `CrackGrowth`, which any sketch can call. The other two keep their rules in the sketch, a few lines each, and lay their sand with a sand painter of their own, after his.

- [**HappyPlace**](HappyPlace/): a ring of nodes, each stepping toward its friends and away from everyone else, after Tarbell's *Happy Place* (2004).

  Every friendship lays sand at each step, so the sheet shows where the friendships have been: a fan where one swung across, a dark seam where one held still. One lap paints for 25 seconds, holds, and goes back to paper. `placeSeed` is the whole piece, and a click rolls the next one. `friends`, `bonds`, and `neighborhood` set who knows whom, and `distance` how close a node lets a stranger come. With some seeds a group wanders off the sheet, as his did: "Groups of friends sometimes move as a group in some general direction." Turn `exposure` off to see what does the painting, the nodes as squares and the friendships as thin lines. An original Ollin interpretation written from his description and his pictures. His Processing source, which he gives away, was read once to understand how the piece works and is not ported. The numbers and the palette are the sketch's own.

  ```sh
  swift run Example-Recreations-JaredTarbell-HappyPlace
  ```

  The sand is a lot of work for a debug build, which paints the same picture more slowly. A release build runs it at speed:

  ```sh
  swift run -c release Example-Recreations-JaredTarbell-HappyPlace
  ```

  The nodes and their friendships twenty seconds in, as lines for a pen:

  ```sh
  swift run Example-Recreations-JaredTarbell-HappyPlace --param exposure=false --at 20 --export-svg place.svg
  ```

  One whole lap, which loops exactly:

  ```sh
  swift run Example-Recreations-JaredTarbell-HappyPlace --export-loop place.mp4
  ```

- [**SandTraveler**](SandTraveler/): travelers thrown out from the middle of the sheet, each chasing another, after Tarbell's *Sand Traveler* (2004).

  The travelers are never drawn. Sand is laid between a chaser and the one it follows while the two are within `sight` of each other, so the routes of the chase build up into arcs and a knot. One lap chases for 20 seconds, holds, and goes back to paper. `laying` picks one of his three ways of laying the color: `even` for smooth bands, `stroke` for the sand painter, and `across` for the sand painter turned a quarter turn. `chaseSeed` is the whole piece, and a click rolls the next one. `travelers` is how many there are, and `lead` how far ahead in the order a traveler may pick the one it follows. An original Ollin interpretation written from his description and his pictures. His Processing source was read once to understand how the piece works and is not ported. The numbers and the palette are the sketch's own.

  ```sh
  swift run Example-Recreations-JaredTarbell-SandTraveler
  ```

  The even laying, for smooth bands:

  ```sh
  swift run Example-Recreations-JaredTarbell-SandTraveler --param laying=even
  ```

  One whole lap, which loops exactly:

  ```sh
  swift run Example-Recreations-JaredTarbell-SandTraveler --export-loop traveler.mp4
  ```

- [**Substrate**](Substrate/): a city grown from colliding cracks, after Tarbell's *Substrate* (2003).

  Each crack drags a sand-grain wash across the open space beside it. Click to grow a fresh city from the next seed. The framework provides the technique as [`CrackGrowth`](../../../Docs/Generators/CrackGrowth.md).

  ```sh
  swift run Example-Recreations-JaredTarbell-Substrate
  ```

### Further reading

- [*Substrate* on complexification.net](http://www.complexification.net/gallery/machines/substrate/)
- [*Happy Place*](http://www.complexification.net/gallery/machines/happyPlace/) and [*Sand Traveler*](http://www.complexification.net/gallery/machines/sandTraveler/) on complexification.net, each with his description, his pictures, and the program running in the page
- [*Sand Stroke*](http://www.complexification.net/gallery/machines/sandstroke/), the sand painter on its own
- [levitated.net](http://www.levitated.net), his earlier gallery
- [His own page for *Substrate*](https://www.jaredstarbell.com/algorithms/substrate/), with the rule, the sand painter, and the palette in his words
- [His biography](https://complexification.net/programmer.html) and [his note on the medium](https://complexification.net/medium.html) on complexification.net, the second on why he gives the code away
- [An interview with Jason Bailey at Artnome](https://www.artnome.com/news/2020/8/24/interview-with-generative-artist-jared-tarbell) (2020), on levitated.net, Etsy, the Toy Factory, and the coffee shop where *Substrate* began
- [An interview at Right Click Save](https://www.rightclicksave.com/article/the-interview-jared-s-tarbell-generative-art-etsy) (2024), on Flash, Processing, and releasing the code
- [*{Software} Structures*](https://whitney.org/exhibitions/software-structures) at the Whitney Museum, the 2004 commission
- ["Etsy: an online art cache"](https://www.dailylobo.com/article/2011/04/etsy_an_online_art_cache), a 2011 profile in the Daily Lobo, the University of New Mexico's student paper, on his search tools

### About these homages

These are homages after Jared Tarbell, made for learning. They aren't reproductions of specific works, and they aren't affiliated with or endorsed by the artist.
