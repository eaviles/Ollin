#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `The reference offline`</sup>

---

# The reference offline

Everything in [`Docs/`](../README.md) and every sketch in [`Examples/`](../../Examples/README.md) is already on your machine, in the checkout you build against. `ollin docs` and `ollin examples` read them there, so looking something up costs a command rather than a browser, a network, and a search box.

```sh
ollin docs color
ollin examples flocking
```

It reads the checkout you are running, which means the answer is the version you build against rather than whatever is published somewhere. On a plane, on a train, or on a machine with no network, it is the whole reference. `ollin site` writes the same pages out as a website, for when a browser is the better place to read.

## Reading a page

Name it however you think of it. A page name, a path, part of either, or a word from the line the index says about it:

```sh
ollin docs Color              # the page
ollin docs Drawing/Color      # the same page, by path
ollin docs reflectance        # the page whose description says it
```

Exact beats loose, so `color` gives you the color page rather than the nine pages that mention color. When a word really does fit several pages equally, they are listed with their descriptions so you can pick:

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

The heading is matched the way you would say it, so backticks, capitals, and the dashes of a web anchor all work. Name one that is not there and the page's headings are listed instead.

With no topic at all, you get every page grouped the way the reference groups them, which is the map:

```sh
ollin docs
```

## Searching it

When you know what you want to do and not what it is called, read the whole reference for a word:

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

You do not have to ask for this. A topic that matches no page falls through to the same search, so a wrong guess still lands somewhere useful.

## The examples

The examples set answers the other half of the question: not what a call does, but what somebody built with it.

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

`--source` prints the sketch itself, which is often the fastest answer of all:

```sh
ollin examples ocean --source
```

To start your own project from one, rather than read it, hand it to the generator instead: `ollin new MyOcean --from 3D/Geometry/Ocean` copies the sketch and everything beside it. See [the project generator](./ProjectGenerator.md).

## In a terminal, and in a pipe

Output is dressed for whoever is reading it. A terminal gets color and the width of your window; a pipe gets plain text, so the commands compose:

```sh
ollin docs --list | grep 3D          # one topic per line
ollin examples --list | wc -l        # one path per line
ollin docs color --plain > color.txt
```

A page longer than the screen opens in your pager (`$PAGER`, or `less`), which `--no-pager` turns off. `--width` sets the column width, `--plain` drops the color, and `--color` keeps it through a pipe.

## In a browser

The same pages can be written out as a website:

```sh
ollin site                 # writes the site into .build/site
ollin site ~/Desktop/ollin # or into a folder you name
```

Open the folder's `index.html`. The README is the front page, and it opens on the ring of breathing circles: the `Examples/Web/BreathingRing` sketch, exported as [its own web page](../Output/Web.md) and played by that page's player, with its ink and paper set to the site's own colors. The site opens on a sketch drawn the way the framework draws it. The Guide has its chapter list beside it, and the reference is grouped the way its index groups it. Every example has a page of its own with its source. Every picture the pages show is copied in. A figure with a dark variant follows your system setting, and so does the site.

The site is a lens on the same files, not a second copy. A page's prose arrives exactly as the file spells it, and its links point at the same neighbors they do on GitHub. A link at something the site does not render, such as a source file or a folder of figures, points at that file on GitHub instead. Paths mirror the repository in lower case, so `Docs/Drawing/Color.md` is `docs/drawing/color.html`.

`--domain ollin.art` writes the `CNAME` file for a custom domain and makes every page's canonical address absolute. The repository's own workflow (`.github/workflows/site.yml`) runs the same command and publishes the result to GitHub Pages.

## What it is not

This prints pages for a person to read, and nothing else. The website is the same pages for a browser, and it carries no search index either. There is no machine-readable output, and no index for another program to consume. That is a decision rather than a gap: [where the line falls](../../ROADMAP.md#a-third-party-extension-ecosystem) for anything that points a tool at the reference is still an open question here, and printing a page somebody asked for takes no position on it.

---

### See also

- [Documentation index](../README.md): the same map, in a browser
- [Examples](../../Examples/README.md): the sketches, by category
- [Project generator](./ProjectGenerator.md): starting a project from a template or from an example
- [Single-file sketches](./SingleFile.md): the rest of what the `ollin` command does
