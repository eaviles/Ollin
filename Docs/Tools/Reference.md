#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `The reference offline`</sup>

---

# The reference offline

Everything in [`Docs/`](../README.md) and every sketch in [`Examples/`](../../Examples/README.md) is already on your machine, in the checkout you build against. `ollin docs` and `ollin examples` read them from there, so looking something up takes one command instead of a browser, a network, and a search box.

```sh
ollin docs color
ollin examples flocking
```

It reads the checkout you are running, so the answer describes the version you build against rather than whatever is published somewhere. That also means you have the whole reference with no network, on a plane, on a train, or on a machine that is offline. When a browser is the better place to read, `ollin site` writes the same pages out as a website.

## Reading a page

Name a page however you think of it. You can give a page name, a path, part of either, or a word from the description the index gives it:

```sh
ollin docs Color              # the page
ollin docs Drawing/Color      # the same page, by path
ollin docs reflectance        # the page whose description says it
```

An exact match wins over a loose one, so `color` gives you the color page rather than the nine pages that mention color. When a word does fit several pages equally well, the command lists them with their descriptions so you can pick one:

```
"light" matches 2 pages:

  Concepts/Light  why color mixes in linear light, and what the last pass of a frame does
  Drawing/Light   Combine.light, the light that reaches every pixel of a flat scene ...
```

Add a heading to go straight to one part of a long page:

```sh
ollin docs Color#ramps
ollin docs Drawing/Drawing#strokeAlign
```

The heading is matched the way you would say it, so backticks, capitals, and the dashes of a web anchor all work. If you name a heading that is not there, the command lists the page's headings instead.

With no topic at all, you get every page, grouped the way the reference groups them. That listing is the map:

```sh
ollin docs
```

## Searching it

Sometimes you know what you want to do but not what it is called. In that case, search the whole reference for a word:

```sh
ollin docs --search "long exposure"
```

Each hit comes back with its page, its line number, and the heading it sits under:

```
Concepts/Light
  29: (What follows from it) - Adding light works. blendMode(.add) with faint marks sums
      the way light sums, which is what makes an accumulated canvas read as a long
      exposure instead of a smear.

Concepts/Persistence
  19: (Kept between frames) - The canvas, if you ask for it. noClear() stops the
      per-frame wipe, so drawing piles up and background(_:) becomes the reset.
```

You do not have to ask for the search. A topic that matches no page falls through to it anyway, so a wrong guess still gives you something useful.

## The examples

The examples answer the other half of the question. They show you not what a call does, but what somebody built with it.

```sh
ollin examples                # every sketch, grouped by folder
ollin examples ocean          # the one you meant
ollin examples boids          # matched on the description, not the name
```

One match prints what it shows and how to run it:

```
3D/Geometry/Ocean

A sea built from its own wave spectrum: one inverse Fourier transform on the GPU
makes the surface, drawn as water with no geometry anywhere (oceanField, drawOcean).

  sketch   Examples/3D/Geometry/Ocean/Sketch.swift
  run      swift run --package-path Examples Example-3D-Geometry-Ocean
  read     ollin examples 3D/Geometry/Ocean --source
```

`--source` prints the sketch itself, which is often the fastest answer:

```sh
ollin examples ocean --source
```

To start your own project from an example rather than read it, hand the example to the generator. `ollin new MyOcean --from 3D/Geometry/Ocean` copies the sketch and everything beside it. See [the project generator](./ProjectGenerator.md).

## In a terminal, and in a pipe

The output is formatted for whoever is reading it. A terminal gets color and the width of your window. A pipe gets plain text, so the commands compose:

```sh
ollin docs --list | grep 3D          # one topic per line
ollin examples --list | wc -l        # one path per line
ollin docs color --plain > color.txt
```

A page longer than the screen opens in your pager (`$PAGER`, or `less`), and `--no-pager` turns that off. `--width` sets the column width, `--plain` drops the color, and `--color` keeps the color through a pipe.

## In a browser

You can also write the same pages out as a website:

```sh
ollin site                 # writes the site into .build/site
ollin site ~/Desktop/ollin # or into a folder you name
```

Open the folder's `index.html` to start reading. The front page opens on the ring of breathing circles. That is the `Examples/Web/BreathingRing` sketch, exported as [its own web page](../Output/Web.md) and played by that page's player. Its ink and paper are set to the site's own colors. The site opens on a sketch drawn the way the framework draws it. Under the ring, the front page shows part of the README. It has the opening, then *Hello, circle*, *Run it*, *Install*, and *What's in it*, laid out for a browser window. The whole README is the About page, and the front page ends with a link to every section it left there. The Guide has its chapter list beside it, and the reference is grouped the way its index groups it. Every example gets a page of its own with its source, and every picture the pages show is copied in. A figure with a dark variant follows your system setting, and so does the site.

The site shows the same files rather than a second copy of them. A page's prose arrives exactly as the file spells it, and its links point at the same neighbors they do on GitHub. The site does not render every kind of file. A link to one it skips, such as a source file or a folder of figures, points at that file on GitHub instead. Paths mirror the repository in lower case, so `Docs/Drawing/Color.md` becomes `docs/drawing/color.html`.

Every page has a search. Press `/`, or the command key with K, or the button in the bar, and type. It looks through the Guide, the reference, and the examples one section at a time. A page's title counts most, then its heading, then its first line, then the words of its prose. So `color` puts the color page first, and `kuwa` finds the brushwork filter by a word its prose uses. A typo in a longer word is forgiven, and every word you type has to match. No page takes more than three rows, and the words that matched are marked. The index is written with the site as `assets/search-index.js`, one entry per section. The matching runs in your browser through [MiniSearch](https://lucaong.github.io/minisearch/), a small open-source library. The page loads it from a content network the first time you search, pinned to one release and checked against its published hash. That is the one thing on the site that comes from outside it. A folder you opened off the disk with no connection has every page, and its search says the library did not load.

`--domain ollin.art` writes the `CNAME` file for a custom domain, and it makes every page's canonical address absolute. A link to any page unfurls with the mark as its card, in a message or a feed. The card is `Logo/ollin-social.png`, which `Scripts/logo.sh` writes from the logo's master. The repository's own workflow (`.github/workflows/site.yml`) runs the same command and publishes the result to GitHub Pages.

## What it is not

The command prints pages for a person to read, and nothing else. The website is the same pages for a browser. Its search index is for the page's own script: headings and first lines with the words under them, not a copy of the reference. There is no machine-readable output, and no index written for another program to read. That is a decision rather than a gap. Anything that points a tool at the reference raises the question of [where the line falls](../../ROADMAP.md#a-third-party-extension-ecosystem), and that question is still open here. Printing a page somebody asked for takes no position on it.

---

### See also

- [Documentation index](../README.md): the same map, in a browser
- [Examples](../../Examples/README.md): the sketches, by category
- [Project generator](./ProjectGenerator.md): starting a project from a template or from an example
- [Single-file sketches](./SingleFile.md): the rest of what the `ollin` command does
