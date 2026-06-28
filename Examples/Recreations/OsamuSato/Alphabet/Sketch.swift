//  Recreation after Osamu Sato — "The Art of Computer Designing: A Black and
//  White Approach" (1993, Graphic-Sha). A homage to its shape-built typefaces —
//  the modular square alphabets of Chapter 3 ("Squares", e.g. the "OS KAKU BOLD"
//  specimen) — where every letter is assembled from identical squares, set in
//  bold black with a red accent. An original Ollin interpretation: the letterforms
//  are our own, drawn from `drawRect` square modules, not ported from the book's
//  disk. A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist.

import Foundation
import Ollin

/// A type-specimen sheet — A–Z and 0–9 — in a square-module font, after Osamu
/// Sato's shape-built alphabets. Each glyph is a 5×7 grid of square modules drawn
/// with `drawRect`. Sato's pages are still; here the sheet is alive: every square
/// shimmers (its size eased by a wave travelling diagonally across the whole
/// sheet), and a red highlight sweeps through the glyphs like a moving accent.
@main
final class Alphabet: Sketch {
    @Param(0...1) var shimmer = 0.6    // how much the squares pulse
    @Param(0.2...4) var sweepSpeed = 1.8   // how fast the red accent travels

    let sato = Color(red: 0.85, green: 0.09, blue: 0.16)
    let ink = Color.black

    let order = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    /// 5×7 square-module letterforms (rows top to bottom, `#` = a filled square).
    let glyphs: [Character: [String]] = [
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
        "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "G": [".####", "#....", "#....", "#.###", "#...#", "#...#", ".####"],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
        "J": ["#####", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
        "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
    ]

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.96))
        let g = grid(columns: 6, rows: 6, padding: .all(width * 0.06))
        // 5 modules wide, 7 tall, with a little padding inside each cell.
        let module = min(g.cellWidth / 6.0, g.cellHeight / 8.5)
        let glyphW = 5 * module, glyphH = 7 * module

        // One cell per glyph, in order; the inner loops walk each glyph's bitmap.
        for (cell, char) in zip(g.cells, order) {
            guard let pattern = glyphs[char] else { continue }
            let originX = cell.frame.x + (g.cellWidth - glyphW) / 2
            let originY = cell.frame.y + (g.cellHeight - glyphH) / 2

            // A red accent that sweeps diagonally across the grid over time.
            let onAccent = sin(Double(cell.column + cell.row) * 0.6 - time * sweepSpeed) > 0.45
            fill(onAccent ? sato : ink)

            for (my, line) in pattern.enumerated() {
                for (mx, bit) in line.enumerated() where bit == "#" {
                    // The square's size eases on a wave travelling across the sheet,
                    // keyed to its absolute module position, so the shimmer flows
                    // glyph-to-glyph instead of resetting per cell.
                    let phase = Double(cell.column * 6 + mx + cell.row * 8 + my) * 0.35 - time * 3.0
                    let frac = 0.80 + 0.14 * shimmer * sin(phase)
                    let cx = originX + (Double(mx) + 0.5) * module
                    let cy = originY + (Double(my) + 0.5) * module
                    drawRect(center: Vector2(cx, cy), width: module * frac, height: module * frac)
                }
            }
        }
    }
}
