#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 1</sup>

---

# 1. Hello, Ollin

<img src="Images/01-HelloOllin/HelloMotion.jpg" alt="A ring of circles in warm and cool colors, drifting and breathing on a dark ground" width="560">

By the end of this chapter you'll have built the sketch above. It's twenty-eight circles drifting around a ring, each one breathing a little out of step with its neighbors, with a small panel of parameters you can turn while it runs. Every dot is placed and moved by code you'll understand line by line. Getting there takes a working toolchain, one new file, and three shapes, and along the way you'll meet the idea that runs through the whole guide: in Ollin, things move by default.

## What you need

You need a Mac running macOS 26 or newer, and Apple's Swift tools. Installing Xcode from the App Store is the easiest way to get them, and once its first-run setup finishes you never have to open it again. Everything in this guide happens in the terminal and your text editor. You don't need to know Swift either, because the guide teaches what each step needs as it comes up. [Appendix A](A-JustEnoughSwift.md) is the primer to read first, if you'd rather meet the language whole.

Two commands say whether the machine is ready:

```sh
swift --version        # Ollin needs 6.3 or newer
xcrun --find metal     # the Metal compiler Ollin draws with
```

If either one fails, finish Xcode's setup and let it install its additional components, then try again. With both working, clone the repository and run your first example:

```sh
git clone https://github.com/eaviles/Ollin.git
cd Ollin
swift run --package-path Examples Example-Basic-HelloCircle
```

The first build takes a few minutes, and after that builds are quick. A window opens with a circle slowly breathing on a white canvas. That is a **sketch**: a small program that draws a picture. Ollin runs its drawing commands again for every frame, and changing the numbers between frames is what turns the picture into motion.

A running sketch keeps the terminal busy, so quit it with ⌘Q when you've looked at it.

### The gallery

Run this one too:

```sh
swift run OllinExamples
```

That opens the **gallery**, a window holding every example in the repository. Give it two minutes now, because this guide points at examples constantly and the gallery is where you look at them.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/Gallery-dark.jpg">
  <img src="Images/01-HelloOllin/Gallery.jpg" alt="A diagram of the gallery window in three panes: a left sidebar listing example groups as a collapsible tree with one entry selected and a filter field at its foot, a dark center pane showing the running sketch, and a right sidebar of four labeled sliders" width="680">
</picture>

The window has three panes. On the left, every example as a collapsible tree that mirrors the folders on disk, with a filter field at the bottom for finding one by name. In the middle, the selected sketch, actually running rather than pictured. On the right, that sketch's parameters, which you can drag while it runs, and hide with ⌘/ when you want the picture to yourself.

**Arrow keys move through the example list**, not into the sketch. The canvas takes the keyboard only once you *click* it, so that you can still arrow to the next example while a sketch is reading key presses. Examples that use the keyboard show a small hint saying so, and clicking the canvas hands the keys over.

Every entry is an ordinary sketch file sitting at `Examples/<Group>/<Name>/Sketch.swift`, the same shape as the file you're about to write. When one does something you want, open it, read it, copy the part you need.

Quit the gallery with ⌘Q before the next command, or leave it running and open a second terminal tab in the repository folder.

## Your first sketch

Make a folder for your own work and a file in it. A folder inside the cloned repository is convenient, because the commands below all run from the repository folder:

```sh
mkdir MySketches
```

Create `MySketches/FirstCircle.swift` in your editor, with exactly this in it:

```swift
import Ollin

final class FirstCircle: Sketch {
    override func draw() {
        background(.white)
        fill(Color(hex: 0x2B2B2B))
        drawCircle(width / 2, height / 2, 200)
    }
}
```

Then, from the repository folder:

```sh
swift run OllinLive MySketches/FirstCircle.swift
```

<img src="Images/01-HelloOllin/FirstCircle.jpg" alt="A dark circle centered on a white canvas" width="560">

A window opens with your circle in it. Three calls made it happen. `background(.white)` fills the canvas, `fill` sets the color the next shape is drawn in, and `drawCircle` draws it. Its three numbers are x, y, and radius, in that order, and the radius is the distance from the circle's center to its edge.

> **Swift note.** `import Ollin` brings the framework in. `final class FirstCircle: Sketch` declares your sketch, a new thing named `FirstCircle` built on Ollin's `Sketch`, which is what gives you the canvas, the drawing calls, and the loop. `final` says nothing else will build on `FirstCircle` in turn, which is the usual choice for a sketch. `override func draw()` fills in the one function Ollin calls to render a frame. You never call `draw()` yourself, because Ollin is the one calling it.

Now for the part that changes how you work. Keep the window open, go back to your editor, change `200` to `320`, and save. The circle grows in place, because `OllinLive` watches the file and swaps in every save while the window keeps running. Try breaking it on purpose: delete a parenthesis and save. An error prints in the terminal while your last working sketch keeps drawing, so nothing is lost. Fix the parenthesis, save again, and you're back where you were.

You'll work this way through the whole guide, so arrange the window and the editor side by side now. Leave `OllinLive` running in its own terminal tab, and open a second tab in the repository folder for the commands that come later.

## Once, then every frame

`draw()` is one of two functions Ollin calls for you. The other is `setup()`, and it runs a single time, before the first frame is drawn. Both go inside your class:

```swift
final class FirstCircle: Sketch {
    override func setup() {
        // runs once, before anything is drawn
    }

    override func draw() {
        // runs again for every frame, for as long as the window is open
    }
}
```

Keep your own drawing commands in `draw()`; the skeleton above is only showing where the two functions sit. Anything that should happen once belongs in `setup()`. That means work heavy enough that repeating it every frame would slow the sketch down, and decisions you want the sketch to make once and then keep. You don't need it yet, since everything in this chapter is drawn fresh each frame from numbers that are cheap to compute. It arrives properly in [Chapter 2](02-Color.md), where reading the colors out of a photograph turns out to be too slow to repeat. It comes back in [Chapter 3](03-MotionAndTime.md), where an animation has to be told once that it should loop.

## Where things go

Every position in a sketch is measured from the canvas's top-left corner, with x growing to the right and y growing *downward*. If you remember y going up from math class, this is the other way round, but it's how screens have worked for decades, and it's the same convention p5.js and Processing use.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/CoordinateSystem-dark.jpg">
  <img src="Images/01-HelloOllin/CoordinateSystem.jpg" alt="The canvas coordinate system: origin at the top left, x right, y down, with the point (380, 240) marked" width="680">
</picture>

The diagram names one point by how far it sits from that corner, which is all a pair of coordinates ever says. Inside `draw()`, `width` and `height` always hold the canvas size, which is why `drawCircle(width / 2, height / 2, 200)` lands in the middle. Try replacing the coordinates with plain numbers and see where the circle goes. On the default canvas, `drawCircle(380, 240, 60)` sits left of center and above it, because 380 is less than half of 1080 and so is 240.

## The canvas is not the window

The thing you draw on and the thing you look at are two different things.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/CanvasVsWindow-dark.jpg">
  <img src="Images/01-HelloOllin/CanvasVsWindow.jpg" alt="A large dark square labeled as the canvas at 1080 by 1080 pixels, with its corners marked as (0,0) and (1080,1080), and a smaller window containing exactly the same picture scaled down, joined by lines labeled scaled to fit" width="680">
</picture>

The **canvas** is a fixed grid of pixels, 1080 by 1080 unless you say otherwise, and it's what all your coordinates are measured against. The **window** is a view of that canvas, scaled to fit comfortably on your screen. So `width` reports 1080 whatever the window is doing, a circle at `(540, 540)` is exactly in the middle, and an exported image comes out at full canvas resolution.

Two properties control the pair, and they're independent:

```swift
override var canvasSize: CanvasSize { .square(1080) }   // the pixels you draw on
override var windowMode: WindowMode { .auto }           // how it's previewed
```

Those go inside your class, above `draw()`, like the two functions did. `canvasSize` takes a square, an explicit width and height, or one of the named presets. Try `.fhd1080` for a wide canvas. The other presets cover video, phone screens, and real paper, so `.uhd4K`, `.vertical1080`, `.a4`, and `.usLetter` are all there. Paper sizes come with a companion, since `.a4.dpi(300)` keeps the page the same physical size while raising the pixel grid to print resolution.

`windowMode` is `.auto` by default, which picks a preview size that fits your screen and then holds it. `.fixed(0.5)` pins the preview to a fraction you choose, and holds that. Neither window can be dragged, and neither changes your drawing. `.resizable` is the one that can: the window is free, and the canvas follows it, so `width` and `height` change as you drag. Exports still come out at the size `canvasSize` declares.

## Placing things without pixels

Once you know the canvas can be any size, there's a habit that saves rewriting layouts later.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/NormalizedPlacement-dark.jpg">
  <img src="Images/01-HelloOllin/NormalizedPlacement.jpg" alt="Two rows of three canvases each, square, wide, and tall. In the top row, marks placed at fixed pixel positions fall off the edges of the wide and tall canvases; in the bottom row, the same marks placed as fractions sit correctly in all three" width="680">
</picture>

Writing `drawCircle(85, 71, 34)` says "85 pixels from the left". That's fine until the canvas changes shape, and then, as the top row shows, your careful arrangement slides off the edge. Writing the same position as a *fraction* of the canvas says "half way across, a little above the middle", and that survives any canvas you give it.

```swift
drawCircle(center: uv(0.5, 0.42), radius: 200 * scale)
```

`uv(u, v)` hands back the canvas point at those fractions, so `uv(0, 0)` is the top-left corner, `uv(1, 1)` the bottom-right, and `uv(0.5, 0.5)` the middle. Sizes want the same treatment. `scale` is the shorter canvas edge divided by 1000, so `200 * scale` is a fifth of that edge. That is 216 pixels on the default canvas, and proportionally more when you export the same sketch at print resolution.

You don't have to do this everywhere, and plenty of sketches in this guide use plain pixels because they only ever run at one size. Fractions matter the day you want a piece as a poster as well as a screen. They keep the centers where you put them. They can't know what a square arrangement should become on a wide one, so look at the layout again when the shape changes.

## Shapes and ink

You've met `drawCircle`. Its two companions take their numbers the same way, a position first and then dimensions. One difference is worth knowing early: a circle's position is its *center*, while a rectangle's is its *top-left corner*.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/FirstShapes-dark.jpg">
  <img src="Images/01-HelloOllin/FirstShapes.jpg" alt="Six panels: a filled circle, a filled rectangle, and a stroked line on top, with markers showing that a circle's x, y is its center while a rectangle's is its top-left corner; an outlined circle, a filled-and-stroked rectangle, and a thick line below" width="680">
</picture>

Try each of them in place of your circle. `drawRect(300, 240, 240, 160)` puts a rectangle's top-left corner at `(300, 240)` and makes it 240 wide and 160 tall. `drawLine(100, 200, 700, 400)` runs from one point to another, a pair of numbers per end. A line needs a `stroke` color rather than a `fill`, because it has no interior to fill.

The styling calls set what everything after them wears. Once you set `fill` or `stroke`, every shape you draw from then on uses it, until you change it.

```swift
fill(Color(hex: 0xE4572E))   // an orange interior
stroke(.black)               // a black outline
strokeWeight(5)              // five points thick
```

To draw an outline and no interior, call `noFill()` in place of the `fill` line. For an interior and no outline, call `noStroke()` in place of the `stroke` line.

Colors come as names or as hex values like `Color(hex: 0xE4572E)`, the same six digits you'd use on the web. Ollin ships a selected set of the CSS color names, `.white`, `.black`, `.orange`, `.crimson` and about forty more, and the [Color](../Docs/Drawing/Color.md) page lists them all. `background(...)` repaints the whole canvas, so it goes first in `draw()`, since anything drawn before it would be covered up. There are many more shapes where these three came from, including ellipses, triangles, stars, and even hearts, and the [Drawing](../Docs/Drawing/Drawing.md) page is the full catalog.

When you want a rectangle centered on a point instead of hung from its corner, ask for it by name: `drawRect(center: Vector2(x, y), width: w, height: h)`. Most shapes offer both forms, one taking bare numbers in a fixed order and one naming the anchor. Naming the anchor is how you say which part of the shape the position refers to.

> **Swift note.** `Vector2(x, y)` bundles an x and a y into a single value, so you can pass a position around as one thing instead of two loose numbers. That's all you need from it here. [Chapter 10](10-Vectors.md) gives it a whole chapter, because once a position is one value you can add positions together, and that is how motion and forces get written.

> **Swift note.** Some calls take bare values in a fixed order, like `drawCircle(540, 540, 200)` for x, y, and radius. Others name their values, like `Color(hex: 0xE4572E)`, where the `hex:` is part of the call. And `.white` is shorthand for `Color.white`, because Swift lets you drop the type name when it can already tell what you mean.

## Moving something by hand

Placing a shape by typing numbers is fine until you want it *a bit to the left*. Then you're guessing: change 300 to 280, save, look, change it again.

While the sketch is running under `swift run OllinLive`, you can skip that. Give the circle plain numbers first, because a drag rewrites numbers and a calculation has none to rewrite:

```swift
drawCircle(300, 300, 40)
```

Save, then hold Command and move the pointer over the window. The shape under it is outlined, and the line of your file that drew it is named above the outline. Drag the shape where you want it, let go, and those numbers in your file are the ones that change.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/DragToSource-dark.jpg">
  <img src="Images/01-HelloOllin/DragToSource.jpg" alt="Two panels: a circle outlined with the label Sketch.swift:12 while Command is held, and the same circle after being dragged, with the two numbers in the code line below changed" width="680">
</picture>

Your editor may reload the file on its own or ask you first, and the running window has already reloaded itself. Nothing else on the line moves. The radius, your spacing, and the comment you left at the end are all where you put them. The performance host in [Chapter 31](31-SharingAndPerforming.md#performing-the-code-itself) has the same drag. There the numbers change in the code on the stage, and the host evaluates it for you.

The shape itself is only the first of three things to take hold of. Small squares sit on its corners, and a knob stands clear above it.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/DragHandles-dark.jpg">
  <img src="Images/01-HelloOllin/DragHandles.jpg" alt="Three panels: a circle being dragged to a new place, the same circle grown by pulling its bottom-right corner, and a horizontal line with a knob above it sweeping round" width="680">
</picture>

A corner changes the numbers that *size* the shape and leaves the ones that place it alone, so a circle grows from its middle. A rectangle written `drawRect(x, y, width, height)` grows from its top-left corner, which is where those first two numbers put it. That is also why such a rectangle offers three corners and not four: the fourth sits on the corner that places it, and has nothing to size.

The knob turns the shape, and it only appears when the line can say which way the shape faces. A line has two ends, so both swing about the middle. An arc carries its own two angles, so those move instead. A circle looks the same however you turn it, so it shows no knob at all. Turning a circle takes a `rotate` further up the file, which this doesn't touch.

One more move belongs here, and it's the one a number cannot express. A shape drawn later lands on top. With a shape outlined, press `⌘]` to bring it forward or `⌘[` to send it back, and its line moves past its neighbor's in the file. The `fill` it was drawn with travels along and is said again where it lands, and the ink the shapes after it had is put back. So the only thing that changes is which shape is in front. Shift takes it all the way to the front or the back.

Two things are worth knowing before you rely on any of it. A number written whole stays whole, so a shape dragged to 285.7 lands on 286, and a nudge under half a point changes nothing. And only a plain number can be dragged. If you wrote `drawCircle(width / 2, 300, 40)`, that first slot holds no number to change. The host says so rather than moving anything: *places this shape with `width / 2`, so there is no number to move.*

There is one exception. A coordinate written as the name of a `@Param` has no number on the line either, but it does have somewhere to put the value. A parameter is a value you can change while the sketch runs, declared inside the class above `draw()`; you'll meet the whole family at the end of this chapter.

```swift
@Param(60 ... 660) var sunX = 120.0
@Param(60 ... 660) var sunY = 120.0

drawCircle(sunX, sunY, 40)     // dragging this moves both parameters
```

The drag sets those parameters instead of writing the file, so nothing recompiles, and the values stay put across the next reload the way any parameter you change by hand does. Both coordinates have to be parameters for that. With a parameter in one slot and a plain number in the other, the number is still written into the file and the sketch reloads.

That limit is the honest shape of the feature. The file is the sketch, and dragging edits the file, so anything the file works out for itself has to be changed where it's written. [Dragging a shape](../Docs/Tools/DragToEdit.md) covers the rest, including named points, lines with two ends, and what stops a shape from moving past a line that is not ink.

## It moves on its own

This is the idea the framework is named for. Change your `drawCircle` line to:

```swift
drawCircle(width / 2 + time * 120, height / 2, 200)
```

Save, and the circle drifts to the right until it leaves the canvas. You didn't set up an animation and there was no play button to press. `draw()` was already running over and over, as fast as your display refreshes, often 60 or 120 times a second, and `time` holds the seconds since the sketch started. So when `time` grows, an x computed from it grows along with it, and the circle lands somewhere slightly different on every frame. Drawing that sequence quickly is what we read as motion. Nearly everything animated in this guide works this way, from breathing dots to flocking birds: you put time into an expression.

(`time` has siblings called `frameCount`, `deltaTime`, and `frameRate`. The [Sketch](../Docs/Core/Sketch.md#temporal-state) page lists them, and you'll meet them properly in [Chapter 3](03-MotionAndTime.md).)

Our drifting circle has a problem, which is that it left. To make motion that stays on the canvas, we'll borrow one recipe from [Chapter 3](03-MotionAndTime.md) ahead of time: `sin`. All you need to know for now is that as its input grows, `sin` glides smoothly between -1 and 1 and then back again, forever, the way a pendulum swings. Multiply it by a distance and you have a swing of your own.

<img src="Images/01-HelloOllin/FirstMotion.gif" alt="A yellow circle swinging smoothly from side to side" width="480">

Replace everything inside `draw()` with this. It changes the colors as well as the motion, so your window matches the picture:

```swift
background(Color(hex: 0x11151C))
noStroke()
fill(Color(hex: 0xFFB703))
let x = width / 2 + sin(time * .tau / 3) * 300
drawCircle(x, height / 2, 70)
```

The `* 300` is how far it swings. `.tau` is the angle of one full turn, about 6.28, so `time * .tau / 3` completes one turn's worth every three seconds and the swing starts over. [Chapter 3](03-MotionAndTime.md) explains why that works, and for today you can use it as a recipe.

> **Swift note.** `let x = ...` gives a value a name. Use `let` for values computed fresh each frame (most of what you'll write in `draw()`); `var` is for values that need to change after they're set.

The recipe has a second half, and it's what the end of this chapter is built on. `sin` has a twin called `cos`, and together they turn an angle into a point on a circle:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/AroundACircle-dark.jpg">
  <img src="Images/01-HelloOllin/AroundACircle.jpg" alt="A circle with an angle marked at its center, and cos and sin placing a point on its rim" width="680">
</picture>

Angles here are radians rather than degrees, and one full turn is `.tau`. Angle zero points to the right, and since y grows downward, a growing angle sweeps clockwise. The angle in the diagram is negative, which is why its point sits above the center rather than below.

Give the pair an angle and a radius, and `cos(angle) * radius` is how far across the point sits and `sin(angle) * radius` how far down. Grow the angle and the point walks the rim. For now that's all this guide asks of `cos` and `sin`, that they're how you place things *around* something. [Chapter 3](03-MotionAndTime.md) shows why it works, and [Appendix B](B-JustEnoughMath.md#an-angle-and-a-radius-make-a-point) keeps this picture for whenever you want it back.

## The mouse joins in

Your sketch already knows where the cursor is. Change the drawing line in `FirstCircle.swift` to:

```swift
drawCircle(mouseX, mouseY, 80)
```

The circle now follows your mouse, because `mouseX` and `mouseY` update continuously. And since `draw()` runs every frame anyway, reacting to a held button is just an `if`:

```swift
if mouseIsPressed {
    fill(Color(hex: 0xE4572E))
} else {
    fill(Color(hex: 0x2B2B2B))
}
drawCircle(mouseX, mouseY, 80)
```

Hold the button and the circle turns orange. Nothing had to be registered for that. Because `draw()` is running anyway, you can ask "is the button down right now?" on every frame and draw accordingly, and `mouseIsPressed` is that question. Reacting *once* to a press or a release is a different question, and so is the keyboard, which has both a held form and a one-shot form. [Input](../Docs/Helpers/Input.md) covers them all.

## A shorter way to run things

Typing `swift run OllinLive path/to/thing.swift` from inside the repository folder every time gets tiring, and it means every session starts with a `cd`. There's a one-time fix.

```sh
Scripts/ollin install        # run once, from the repository folder
```

That links an `ollin` command into a folder on your `PATH`, which is the list of places your shell looks for commands. If it reports that the folder it picked isn't on yours, run the line it prints, then `source ~/.zshrc`. After that, a sketch is a file you can run from anywhere:

```sh
ollin new NextIdea.swift     # writes a starter sketch, named after the file
ollin NextIdea.swift         # opens it in the live window
```

This is the place to say what a sketch actually *is* in Ollin. It's one `.swift` file. Not a project, not a folder with configuration in it, not something you have to register anywhere. That's deliberate. A sketch is small enough to keep in a notes folder, mail to someone, or paste into a message, and it will run on any machine that has Ollin. Every export option works on a loose file too, so this writes four seconds of a sketch on your desktop as a GIF:

```sh
ollin NextIdea.swift --export-gif out.gif --seconds 4
```

`ollin new` also writes `#!/usr/bin/env ollin` on the first line and marks the file executable, so `./NextIdea.swift` opens it as well. [Single-file sketches](../Docs/Tools/SingleFile.md) covers the rest, including how to do that to a file you wrote by hand.

The guide keeps writing the full `swift run OllinLive` form so everything works whether or not you installed the shortcut. The next two sections use `ollin` commands, though, so skip ahead to [Putting it together](#putting-it-together-a-breathing-ring) if you'd rather not install it.

## When one file isn't enough

A loose sketch can already load a photograph, a font, or a shader sitting in its own folder. What one file can't hold is a second file's worth of code, or the makings of a program you want to build once and hand to somebody. At that point you want a package, and you shouldn't have to build one by hand.

```sh
ollin new MyPiece                                     # a folder that builds and runs
ollin new SoundPiece --template shader --with audio   # wired for a shader and the microphone
```

That writes a small project: the sketch, a manifest that already knows where the framework is, a place to put your material, and a README with the commands in it. The commands run from inside the folder:

```sh
cd MyPiece
swift run MyPiece                       # runs it
ollin Sources/MyPiece/Sketch.swift      # the same file, in the live window
```

Opening it that second way keeps the edit-and-save loop you just learned.

Templates are the part to know about early. A template is not an empty file; it is a small sketch that already does something, so you start by changing something that works instead of facing a blank `draw()`. There are ten, from a plain breathing circle to pen-ready line work to a lit 3D solid.

```sh
ollin generate
```

This is the same thing in a window, and it *runs* each template while you look at it. Pick a starting point by watching it move, tick what the sketch should be wired for, and press Create.

Nothing about this changes what a sketch is. It is still your `.swift` file, still readable on its own, and the folder is somewhere to keep it and its material. [The project generator](../Docs/Tools/ProjectGenerator.md) has the whole list of templates and options.

## Looking something up without leaving the terminal

You're going to want to look things up constantly, and everything the documentation says is already on your machine, in the folder you cloned. So you can read it where you're working:

```sh
ollin docs color             # the page about color
ollin examples flocking      # the example, what it shows, how to run it
```

A long page opens in a pager. Space scrolls it, and `q` gives you the prompt back.

Name a page however you happen to think of it. `Color`, `Drawing/Color`, and a word from its description all land on the same page, and an exact name always wins over a page that merely mentions the word. A long page can be opened at one part of itself:

```sh
ollin docs Color#ramp
```

The command for when you know what you want and not what it's called is the search:

```sh
ollin docs --search "long exposure"
```

That reads every page and shows you each line that says it, with the page and the heading it sits under. A topic that matches no page falls through to the same search, so a wrong guess still turns something up.

The examples answer the other side of the same question. `ollin examples` with no filter lists all of them, grouped by folder. With a word, it finds the ones whose name, folder, or description matches. And `--source` prints the sketch itself, which is often the answer you actually wanted:

```sh
ollin examples ocean --source
```

None of this needs a network. [The reference offline](../Docs/Tools/Reference.md) covers the rest, including how it behaves in a pipe and how `ollin site` writes all of it out as a website.

## Putting it together: a breathing ring

Now we can build the sketch from the top of the chapter. A loop places 28 circles around a ring using the `cos` and `sin` recipe. `time` inside the angle makes the whole ring drift, and `sin` swings both the ring's radius and each circle's size so that the sketch breathes.

Two things in the listing are new. The circles run inside a `for` loop, which repeats the drawing commands once per circle. And each color carries an `alpha`, which is how opaque it is: 1 is solid, 0 is invisible, and 0.85 lets overlapping circles show a little of each other.

> **Swift note.** `for i in 0..<count` counts from 0 up to, but not including, `count`, so `i` names each circle in turn. `i` is an `Int` (a whole number) while positions want `Double` (numbers with fractions), so `Double(i)` converts. `[Color]` is a list of colors, `colors[0]` is its first, `colors.count` is its length, and `%` is the remainder after division, which is what makes the palette repeat. These keep coming back; there's more Swift in the [Swift quick reference](../Docs/Swift.md) whenever you want it.

Make a new file, `MySketches/HelloMotion.swift`:

```swift
import Ollin

final class HelloMotion: Sketch {
    @Param("Speed", 0...2) var speed = 0.3
    @Param("Size", 8...80) var size = 38.0
    @Param("Circles", 4...120) var count = 28
    @Param("Ground") var ground = Color(hex: 0x11151C)

    let colors: [Color] = [
        Color(hex: 0xFFB703, alpha: 0.85), Color(hex: 0xFB8500, alpha: 0.85),
        Color(hex: 0x219EBC, alpha: 0.85), Color(hex: 0x8ECAE6, alpha: 0.85),
    ]

    override func draw() {
        background(ground)
        noStroke()
        for i in 0..<count {
            let angle = Double(i) / Double(count) * .tau + time * speed
            let breathe = sin(time * 1.4 + Double(i) * 0.5)
            let ring = 310 + breathe * 80
            let x = width / 2 + cos(angle) * ring
            let y = height / 2 + sin(angle) * ring
            fill(colors[i % colors.count])
            drawCircle(x, y, size + breathe * 16)
        }
    }
}
```

<img src="Images/01-HelloOllin/HelloMotion.jpg" alt="Twenty-eight circles in warm and cool colors form a ring, at different sizes and with their edges overlapping" width="560">

Run it with `swift run OllinLive MySketches/HelloMotion.swift` and walk through what each line contributes:

- `Double(i) / Double(count) * .tau` divides the full turn into one slot per circle. Adding `time * speed` grows every angle together, so the whole ring rotates.
- `breathe` is the pendulum again, and the part to notice is the `+ Double(i) * 0.5`, which gives each circle a head start over its neighbor. That small offset is what makes the ring ripple instead of pulsing all at once. Try deleting it and watch the difference.
- `breathe` gets used twice, swinging both the ring's radius (`310 + breathe * 80`) and each circle's size (`size + breathe * 16`). So each circle grows as it swings outward and shrinks as it comes back.
- `colors[i % colors.count]` cycles through the palette, so circle 0 gets the first color and circle 4 wraps back around to it.

That leaves the four `@Param` lines. Look at the sidebar of the `OllinLive` window and you'll find they became a small control panel. `@Param("Speed", 0...2) var speed = 0.3` declares a parameter with a label, a range, and a starting value, and the sketch reads it like any other property. Each parameter arrived as the control its type calls for. Speed and Size hold `Double`s, so they are sliders. Circles holds a whole number, so it is a stepper. Ground holds a `Color`, so it is a swatch you click to open a picker. There are more of these, including a toggle for a `Bool` and a draggable pad for a point, and you'll meet them as the guide goes on. Beside a numeric control the value itself is live, so you can drag it sideways to scrub or click it to type one in.

Play the panel while the sketch runs. Your tuned values survive a save, which means you can edit the code, save, and find your parameter positions carried over into the reloaded sketch instead of snapping back to the defaults. Build that habit early, because a number you find yourself trying three values of is a number that wants to be a parameter.

### Saving the values you tuned

There is one thing the panel cannot do on its own, which is remember. A tuned value lives in the running program, so quitting drops it.

The button under the rows writes them down for you. Press **Save parameters to HelloMotion.swift**, and every value you turned goes into the `@Param` line that declared it.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/01-HelloOllin/ParametersToSource-dark.jpg">
  <img src="Images/01-HelloOllin/ParametersToSource.jpg" alt="Two panels: a Radius slider at 120 above a waiting Save parameters button, and the same slider turned down to 86.5 with the button pressed, with the @Param line under each panel showing the number it now carries" width="680">
</picture>

Only the parameters you actually moved are written, and only the value on the line changes. Your label, your range, your spacing, and the comment you left at the end are all where you put them. The host then reloads the sketch from the file, the same way it does after any save of your own.

A number keeps the shape you gave it. A whole default stays whole while the value is whole, and one written with a point keeps its point. That second rule matters more than it looks, because `86` and `86.0` are different types to Swift, and only `86.0` is the `Double` you declared.

The same limit as the drag applies, for the same reason. A default the sketch works out has no value to replace, which you can see for yourself by making the `Size` line a calculation and pressing the button again:

```swift
@Param("Size", 8...80) var size = 114.0 / 3
```

The line under the button says so and names what stands there. Put `38.0` back when you've seen it.

### Make it yours

Three directions worth trying:

- Run `Circles` from 4 up to 120 and watch the gaps close. Keep `Size` above 16 while you do, because below that the breathing takes some radii to zero, and a circle with no radius isn't drawn at all.
- Swap the palette. Pick four hex colors you like and paste them in.
- Replace `drawCircle` with `drawRect(center: Vector2(x, y), width: size, height: size)`. Use the `center:` form here, because the positional `drawRect(x, y, size, size)` would hang each square down and to the right of its place on the ring.

## Where this comes from

The `setup()` and `draw()` sketch model comes from [Processing](https://processing.org), started by Casey Reas and Ben Fry in 2001, and it continues through [p5.js](https://p5js.org), [openFrameworks](https://openframeworks.cc), and [OPENRNDR](https://openrndr.org), each of which shaped Ollin's design. Processing and p5.js repeat `draw()` while a sketch runs, and Ollin keeps that, at the display's refresh rate, with `noLoop()` as the escape hatch for a still. The name is the Nahuatl word for movement, the seventeenth day sign of the Aztec calendar. The edit-and-watch live-reload loop belongs to a long lineage of live-coding tools, and you'll meet its stage-performance form in [Chapter 31](31-SharingAndPerforming.md).

## Go deeper

- [The frame](../Docs/Concepts/Frame.md): one screen on what a drawing call actually does, why the picture is built from nothing each time, and what happens once `draw()` returns.
- [Where a point is](../Docs/Concepts/Coordinates.md): one screen on the coordinates above, the difference between a point and a pixel, and the other frames that arrive with a camera, a 3D scene, or a machine.
- [Sketch](../Docs/Core/Sketch.md): the full lifecycle, `noLoop()` for stills, and running a sketch as its own standalone program with `@main`.
- [Canvas](../Docs/Core/Canvas.md): canvas sizes and presets, the preview window, and writing sketches that hold up at any resolution (`scale` for sizes, and `uv(u, v)` for placing things as 0…1 fractions of the canvas).
- [Drawing](../Docs/Drawing/Drawing.md): every shape and the complete ink state.
- [Single-file sketches](../Docs/Tools/SingleFile.md): installing `ollin`, running one loose `.swift` file, the hashbang form, and exporting from the command line.
- [The project generator](../Docs/Tools/ProjectGenerator.md): every template and option behind `ollin new` and `ollin generate`, what a generated folder holds, and how to add a template of your own.
- [Dragging a shape](../Docs/Tools/DragToEdit.md): everything a Command-drag can move, what it writes, and why a calculation is refused by name.
- [The reference offline](../Docs/Tools/Reference.md): `ollin docs` and `ollin examples` in full, including one section of a page, the search across everything, and what happens in a pipe.
- [Input](../Docs/Helpers/Input.md): the keyboard, click hooks, and the rest of the mouse.
- [Parameters](../Docs/Helpers/Parameters.md): the full parameter family, from toggles and menus to draggable pads, plus grouping them into cards, icons, smoothing, saving a tuned set back into the code, and driving parameters from MIDI or OSC hardware.
- [Appendix A, Just enough Swift](A-JustEnoughSwift.md): the language taught in order, every construct these sketches lean on. [The Swift quick reference](../Docs/Swift.md) is the short version, for whenever a single construct felt mysterious.
- Appendix B draws this chapter's math, one picture per idea: [Where things are](B-JustEnoughMath.md#where-things-are), [Angles and circles](B-JustEnoughMath.md#angles-and-circles), [Fractions, mapping, and wrapping](B-JustEnoughMath.md#fractions-mapping-and-wrapping).
- Worked examples: [`Examples/Basic/HelloCircle`](../Examples/Basic/HelloCircle/Sketch.swift), the parameters demo [`Examples/Live/Parameters`](../Examples/Live/Parameters/Sketch.swift), a page of shapes to drag around, [`Examples/Live/DragToEdit`](../Examples/Live/DragToEdit/Sketch.swift), and a sketch you can grab, drag, and release with the mouse, [`Examples/Input/Drag`](../Examples/Input/Drag/Sketch.swift).

---

[Contents](README.md#contents) · Next: [Chapter 2, Color that works](02-Color.md)
