//  Recreation after Anwar Jalal Shemza - the Roots series (1977 to 1985),
//  his last: a plant above the ground and its roots below it as calligraphy,
//  painted on pieces of hand-dyed cloth laid on a board. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist or his
//  estate.
//  https://www.anwarshemza.com/
//
//  An original Ollin interpretation, written from the pictures as the estate
//  and the scholars who have written on them describe them: a foliate form
//  on the upper half, root forms on the lower, the roots curling into
//  illegible script. The words here are the sketch's own, set in real
//  Arabic-script faces, and they are legible: root, earth, sky, water,
//  homeland, seed, branch, flower, home, and the letter meem. There is no
//  code to port.

import Ollin

/// Roots (Anwar Jalal Shemza, Stafford, 1977 to 1985). In the last eight
/// years of his life Shemza, who had left Lahore for London in 1956 and
/// settled in Stafford, his wife's home town, painted a series he called
/// *Roots*. Each picture is a plant: a flower or a crown of leaves on the
/// upper part, drawn from the circle and the square he built everything
/// from, and below it the roots, which are not roots at all but letters,
/// Arabic and Urdu script curling where the roots should be, too tangled to
/// read. They are painted on pieces of cloth he dyed himself by dipping them
/// again and again in thinned paint, the edges left frayed, laid in two or
/// three on a board. He meant to show them in Pakistan; the tour opened in
/// 1985, the year he died.
///
/// This sketch keeps that structure. A board holds `panels` pieces of
/// cloth, each with a fringe of threads along its edges. The top piece is
/// the sky, and on it `flowers` flowers stand on stems: each blossom is a
/// cup, a half-disc, with three lobes of discs grown onto it, made by
/// joining the shapes, then the same blossom again smaller and darker inside
/// it, and a bud at its heart. Where the sky is tall the stems send roots
/// down through it, wandering lines that end at the cloth's lower edge. Each
/// piece below the sky carries a word in Urdu, the roots: `word` is which
/// (or dealt by the seed), and `script` is the hand it is written in, the
/// rounded naskh of Geeza Pro, the hanging nastaliq of Urdu's own
/// tradition, or the angular Kufi. The word is set from the face's own
/// outlines at a size taller than the cloth, so it runs off the edges and is
/// cut where the cloth ends, exactly as the painted letters are. `palette`
/// is the dye. A press deals the next picture.
///
/// Over one cycle of `seconds` the board is laid and the cloths pinned on,
/// the stems grow and the blossoms open, the roots wander down, and the
/// words are written right to left, the way Urdu reads; then the picture
/// holds and fades back, which is also the export loop.
///
/// The cloths export as rectangles, their fringes as lines, each blossom as
/// the outline the joined shapes make, and every word as the letters' own
/// outlines cut to the cloth, carrying the move that placed them, so
/// `--export-svg` with a frame in the hold gives back the rule: every letter
/// is the face's glyph at that size, every cut lies on the cloth's edge, and
/// every blossom is its own reflection about its stem.
@main
final class Roots: Sketch {
    enum Script: String, CaseIterable, ParamOption {
        case naskh, nastaliq, kufi

        var fontName: String {
            switch self {
            case .naskh: "Geeza Pro"
            case .nastaliq: "Noto Nastaliq Urdu"
            case .kufi: "KufiStandardGK"
            }
        }
    }

    /// The words the roots may spell, in Urdu, with their meanings.
    enum Word: String, CaseIterable, ParamOption {
        case dealt, root, earth, sky, water, homeland, seed, branch, flower, home, meem

        var urdu: String {
            switch self {
            case .dealt: ""
            case .root: "جڑ"
            case .earth: "زمین"
            case .sky: "آسمان"
            case .water: "پانی"
            case .homeland: "وطن"
            case .seed: "بیج"
            case .branch: "شاخ"
            case .flower: "پھول"
            case .home: "گھر"
            case .meem: "میم"
            }
        }
    }

    enum Palette: String, CaseIterable, ParamOption {
        /// After *Roots Three*: a cream board, blue, brown, and green cloths.
        case cream
        /// After *Roots Two*: a red board, a blue sky and a green ground.
        case red
        /// After *Roots One*: tan linen, a pink sky and a pale ground.
        case linen
    }

    @Param(icon: "paintpalette") var palette = Palette.cream
    @Param(icon: "textformat") var script = Script.naskh
    @Param(icon: "character") var word = Word.dealt
    @Param(2 ... 3, icon: "rectangle.split.1x2") var panels = 3
    @Param(1 ... 4, icon: "camera.macro") var flowers = 3
    @Param(8 ... 90, icon: "clock") var seconds = 24.0

    override var canvasSize: CanvasSize { .size(810, 1080) }
    override var loopDuration: Double? { seconds }

    private struct Dye {
        var board: Color
        var cloths: [Color]
        var ink: Color
        var petal: Color
        var petalDark: Color
        var core: Color
        var stem: Color
    }

    private struct Thread {
        var from: Vector2
        var to: Vector2
    }

    private struct Flower {
        var stemX: Double
        var base: Double
        var top: Double
        var size: Double
        var outer: Shape
        var inner: Shape
        var bud: Vector2
        var budRadius: Double
        var roots: [[Vector2]]
    }

    private struct Placed {
        var panel: Int
        var word: Word
        var font: OutlineFont
        var size: Double
        var move: Vector2
        var glyphs: [Shape]
    }

    private struct Picture {
        var cloths: [Rectangle]
        var threads: [[Thread]]
        var flowers: [Flower]
        var words: [Placed]
    }

    private struct Dealt: Equatable {
        var palette: Palette, script: Script, word: Word, panels: Int, flowers: Int, seed: Int
    }

    private var picture: Picture?
    private var dealtFor: Dealt?
    private var pressed = false
    private var fonts: [Script: OutlineFont] = [:]

    private var dye: Dye {
        switch palette {
        case .cream:
            Dye(board: Color(hex: 0xE7DFC6), cloths: [Color(hex: 0xA9C7E6), Color(hex: 0x8B6A2C), Color(hex: 0x3F5A3A)],
                ink: Color(hex: 0xB7C98A), petal: Color(hex: 0xE89CB8), petalDark: Color(hex: 0xB0355A),
                core: Color(hex: 0x6E1E36), stem: Color(hex: 0x4E7A3C))
        case .red:
            Dye(board: Color(hex: 0xC9473D), cloths: [Color(hex: 0x2E5BA8), Color(hex: 0x7A9A43), Color(hex: 0x5E7E35)],
                ink: Color(hex: 0xE87AA4), petal: Color(hex: 0xE8A0C0), petalDark: Color(hex: 0xA64D86),
                core: Color(hex: 0x5A1F4E), stem: Color(hex: 0xE87AA4))
        case .linen:
            Dye(board: Color(hex: 0xC9B59C), cloths: [Color(hex: 0xE9B9C8), Color(hex: 0xEDE6D6), Color(hex: 0xD9D3C3)],
                ink: Color(hex: 0x8C4FA3), petal: Color(hex: 0xB06FBF), petalDark: Color(hex: 0x4A2C4F),
                core: Color(hex: 0x2A1A2E), stem: Color(hex: 0x8C4FA3))
        }
    }

    override func setup() {
        for script in Script.allCases {
            fonts[script] = OutlineFont(name: script.fontName)
        }
    }

    override func mousePressed() {
        pressed = true
    }

    override func draw() {
        if pressed {
            pressed = false
            seed(variation + 1)
        }
        let wanted = Dealt(palette: palette, script: script, word: word, panels: panels, flowers: flowers, seed: variation)
        if dealtFor != wanted || picture == nil {
            dealtFor = wanted
            picture = deal()
        }
        guard let picture else { return }
        let dye = dye

        background(dye.board)
        let phase = loopProgress(over: seconds)
        let pinned = 0.08, bloomed = 0.38, written = 0.82, held = 0.92

        // The cloths, pinned on from the top down, each with its fringe.
        noStroke()
        for (i, cloth) in picture.cloths.enumerated() {
            let share = Double(picture.cloths.count)
            let alpha = smoothstep(Double(i) / share * pinned, (Double(i) + 1) / share * pinned, phase)
            guard alpha > 0 else { continue }
            let color = dye.cloths[i % dye.cloths.count].withAlpha(alpha)
            fill(color)
            drawRect(cloth)
            stroke(color)
            strokeWeight(1.2)
            strokeCap(.butt)
            for thread in picture.threads[i] {
                drawLine(thread.from, thread.to)
            }
            noStroke()
        }

        // The flowers: the stem climbs, the blossom opens, the roots wander.
        let blooming = phase < pinned ? 0 : min(1, (phase - pinned) / (bloomed - pinned))
        for flower in picture.flowers {
            drawFlower(flower, progress: blooming, dye: dye)
        }

        // The words, written right to left, one cloth after another.
        let writing = phase < bloomed ? 0 : min(1, (phase - bloomed) / (written - bloomed))
        for (i, placed) in picture.words.enumerated() {
            let share = Double(picture.words.count)
            let f = min(1, max(0, writing * share - Double(i)))
            guard f > 0 else { continue }
            let cloth = picture.cloths[placed.panel]
            if f >= 1 {
                drawWord(placed, cloth: cloth, dye: dye)
            } else {
                let revealed = Rectangle(x: cloth.x + (1 - f) * cloth.width, y: cloth.y - 1,
                                         width: f * cloth.width + 1, height: cloth.height + 2)
                withClip(revealed) {
                    drawWord(placed, cloth: cloth, dye: dye)
                }
            }
        }

        if phase > held {
            fill(dye.board.withAlpha(smoothstep(held, 1, phase)))
            noStroke()
            drawRect(0, 0, width, height)
        }
    }

    /// The word's glyphs, cut to the cloth, drawn under the move that placed
    /// them so the export carries it.
    private func drawWord(_ placed: Placed, cloth: Rectangle, dye: Dye) {
        let local = Rectangle(x: cloth.x - placed.move.x, y: cloth.y - placed.move.y,
                              width: cloth.width, height: cloth.height)
        let window = Shape([local.corner, Vector2(local.x + local.width, local.y),
                            local.bottomRight, local.bottomLeft])
        withState {
            translate(placed.move.x, placed.move.y)
            noStroke()
            fill(dye.ink)
            for glyph in placed.glyphs {
                drawShape(glyph.intersection(window))
            }
        }
    }

    private func drawFlower(_ flower: Flower, progress: Double, dye: Dye) {
        guard progress > 0 else { return }
        let climb = min(1, progress / 0.4)
        let open = smoothstep(0.4, 1, progress)
        let wander = smoothstep(0.3, 0.8, progress)

        // The roots first, under the stem.
        stroke(dye.stem)
        strokeWeight(0.06 * flower.size)
        strokeJoin(.round)
        strokeCap(.round)
        noFill()
        for root in flower.roots {
            let count = max(2, Int((Double(root.count) * wander).rounded(.up)))
            if wander >= 1 {
                drawPolyline(root)
            } else if count >= 2 {
                var shown = Array(root.prefix(count))
                if count < root.count {
                    let t = Double(root.count) * wander - Double(count - 1)
                    shown[count - 1] = root[count - 2] + (root[count - 1] - root[count - 2]) * max(0, min(1, t))
                }
                drawPolyline(shown)
            }
        }

        // The stem, climbing from the cloth to the blossom.
        let top = flower.base - climb * (flower.base - flower.top)
        drawLine(flower.stemX, flower.base, flower.stemX, top)
        noStroke()
        guard open > 0 else { return }

        // The blossom opens from the stem's top.
        withState {
            translate(flower.stemX, flower.top)
            scale(open, open)
            stroke(dye.core)
            strokeWeight(0.025 * flower.size / max(open, 0.01))
            strokeJoin(.round)
            fill(dye.petal)
            drawShape(flower.outer)
            noStroke()
            fill(dye.petalDark)
            drawShape(flower.inner)
            fill(dye.core)
            drawCircle(flower.bud.x, flower.bud.y, flower.budRadius)
        }
    }

    /// Lays the board for the seed: the cloths and their threads, the
    /// flowers, and the words with their faces, sizes, and moves.
    private func deal() -> Picture {
        randomSeed(variation)

        // The cloths, top to bottom, with a gap between and a margin round.
        let margin = 0.09 * width
        let gap = 0.03 * height
        let shares: [Double] = panels == 2 ? [0.42, 0.30] : [0.19, 0.25, 0.32]
        let stack = shares.reduce(0, +) * height + Double(shares.count - 1) * gap
        var y = (height - stack) / 2
        var cloths: [Rectangle] = []
        for share in shares {
            cloths.append(Rectangle(x: margin, y: y, width: width - 2 * margin, height: share * height))
            y += share * height + gap
        }

        // The fringe: threads every few points along the top and bottom
        // edges, shorter ones down the sides.
        var threads: [[Thread]] = []
        for cloth in cloths {
            var own: [Thread] = []
            var x = cloth.x
            while x <= cloth.x + cloth.width {
                let up = random(4, 11), down = random(4, 11)
                own.append(Thread(from: Vector2(x, cloth.y), to: Vector2(x + random(-1, 1), cloth.y - up)))
                own.append(Thread(from: Vector2(x, cloth.y + cloth.height),
                                  to: Vector2(x + random(-1, 1), cloth.y + cloth.height + down)))
                x += random(2.5, 4.5)
            }
            var yy = cloth.y
            while yy <= cloth.y + cloth.height {
                own.append(Thread(from: Vector2(cloth.x, yy), to: Vector2(cloth.x - random(2, 6), yy)))
                own.append(Thread(from: Vector2(cloth.x + cloth.width, yy),
                                  to: Vector2(cloth.x + cloth.width + random(2, 6), yy)))
                yy += random(3, 6)
            }
            threads.append(own)
        }

        // The flowers on the sky.
        let sky = cloths[0]
        var flowerList: [Flower] = []
        let size = min(0.22 * sky.height, sky.width / (Double(flowers) * 2.6))
        for i in 0 ..< flowers {
            let x = sky.x + sky.width * (Double(i) + 0.5) / Double(flowers)
            let tall = panels == 2
            let top = sky.y + 2.35 * size + random(0, 0.05) * sky.height
            let base = tall ? sky.y + sky.height * random(0.55, 0.68) : sky.y + sky.height
            let (outer, inner, bud, budRadius) = blossom(size: size)
            var roots: [[Vector2]] = []
            if tall {
                let count = 2 + Int(random(0, 3))
                for k in 0 ..< count {
                    var points = [Vector2(x, base)]
                    var px = x
                    let lean = (Double(k) - Double(count - 1) / 2) * 0.5 + random(-0.2, 0.2)
                    var drift = lean * 0.12 * size
                    let steps = 18
                    for s in 1 ... steps {
                        let py = base + (sky.y + sky.height - base) * Double(s) / Double(steps)
                        drift += random(-0.05, 0.05) * size
                        drift = max(-0.3 * size, min(0.3 * size, drift))
                        px += drift
                        px = max(sky.x + 0.05 * size, min(sky.x + sky.width - 0.05 * size, px))
                        points.append(Vector2(px, py))
                    }
                    roots.append(points)
                }
            }
            flowerList.append(Flower(stemX: x, base: base, top: top, size: size, outer: outer, inner: inner,
                                     bud: bud, budRadius: budRadius, roots: roots))
        }

        // The words on the cloths below the sky.
        var words: [Placed] = []
        let font = fonts[script] ?? fonts[.naskh] ?? .system
        var choices = Word.allCases.filter { $0 != .dealt }
        for i in 1 ..< cloths.count {
            let cloth = cloths[i]
            var chosen = word == .dealt ? randomChoice(choices) : word
            choices.removeAll { $0 == chosen }
            var face = font
            // A face that lacks a letter of the word would borrow it from
            // another, and a Kufi word with one rounded letter is no Kufi
            // word: a dealt word is dealt again, and a chosen one is set
            // whole in naskh.
            var tries = 0
            while face.fontsUsed(for: chosen.urdu).count > 1, word == .dealt, !choices.isEmpty, tries < 20 {
                tries += 1
                chosen = randomChoice(choices)
                choices.removeAll { $0 == chosen }
            }
            if face.fontsUsed(for: chosen.urdu).count > 1, let naskh = fonts[.naskh] {
                face = naskh
            }
            var measured: [Shape] = []
            withState {
                textFont(face)
                textSize(100)
                textAlign(.left, .baseline)
                textDirection(.automatic)
                measured = textToShapes(chosen.urdu, 0, 0)
            }
            let box = bounds(of: measured)
            let size = 100 * 1.12 * cloth.height / max(box.height, 1)
            var glyphs: [Shape] = []
            withState {
                textFont(face)
                textSize(size)
                textAlign(.left, .baseline)
                textDirection(.automatic)
                glyphs = textToShapes(chosen.urdu, 0, 0)
            }
            let placedBox = bounds(of: glyphs)
            let slide = random(-0.22, 0.22) * cloth.width
            let lift = random(-0.06, 0.06) * cloth.height
            let move = Vector2(cloth.center.x - placedBox.center.x + slide, cloth.center.y - placedBox.center.y + lift)
            words.append(Placed(panel: i, word: chosen, font: face, size: size, move: move, glyphs: glyphs))
        }
        return Picture(cloths: cloths, threads: threads, flowers: flowerList, words: words)
    }

    /// A blossom about the origin, the stem's top: a cup that is the lower
    /// part of a disc, cut level with half its radius above the center, three
    /// lobes of discs joined onto it, the same again smaller and darker
    /// inside, and a bud at the heart.
    private func blossom(size: Double) -> (Shape, Shape, Vector2, Double) {
        func disc(_ center: Vector2, _ r: Double) -> Shape {
            Shape(contours: [Circle(center: center, radius: r).contour(segments: 96)], winding: .nonZero)
        }
        func build(_ s: Double, at offset: Vector2) -> Shape {
            let lower = Shape([Vector2(-2 * s, -0.5 * s), Vector2(2 * s, -0.5 * s), Vector2(2 * s, 2 * s), Vector2(-2 * s, 2 * s)])
            let cup = disc(Vector2(0, 0), s).intersection(lower)
            let left = disc(Vector2(-0.5 * s, -0.35 * s), 0.55 * s)
            let right = disc(Vector2(0.5 * s, -0.35 * s), 0.55 * s)
            let crown = disc(Vector2(0, -0.8 * s), 0.45 * s)
            return cup.union(left).union(right).union(crown).mapPoints { $0 + offset }
        }
        let outer = build(size, at: Vector2(0, -size))
        let inner = build(0.6 * size, at: Vector2(0, -size + 0.12 * size))
        return (outer, inner, Vector2(0, -size - 0.55 * size), 0.17 * size)
    }

    private func bounds(of shapes: [Shape]) -> Rectangle {
        var low = Vector2(Double.infinity, Double.infinity)
        var high = Vector2(-Double.infinity, -Double.infinity)
        for shape in shapes {
            for contour in shape.contours {
                for p in contour.points {
                    low = Vector2(min(low.x, p.x), min(low.y, p.y))
                    high = Vector2(max(high.x, p.x), max(high.y, p.y))
                }
            }
        }
        guard low.x <= high.x else { return Rectangle(x: 0, y: 0, width: 0, height: 0) }
        return Rectangle(x: low.x, y: low.y, width: high.x - low.x, height: high.y - low.y)
    }
}
