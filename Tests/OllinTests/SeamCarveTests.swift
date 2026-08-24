import Ollin
import Testing

/// Pure-CPU laws for seam carving: a seam is connected and touches every row
/// once, it follows the cheapest way through, the forward cost really is the
/// cost of the join it makes, the masks hold and release, growth puts pixels
/// back, and the map agrees with the carve. No GPU is touched.
@Suite
struct SeamCarveTests {
    // MARK: - Shape

    /// A carve gives back exactly the size it was asked for, both ways on both
    /// axes.
    @Test func aCarveGivesTheSizeItWasAskedFor() {
        let picture = texturedPicture(width: 24, height: 16)

        #expect(picture.seamCarved(toWidth: 18).width == 18)
        #expect(picture.seamCarved(toWidth: 18).height == 16)
        #expect(picture.seamCarved(toHeight: 9).height == 9)
        #expect(picture.seamCarved(toHeight: 9).width == 24)
        #expect(picture.seamCarved(toWidth: 30).width == 30)
        #expect(picture.seamCarved(toHeight: 22).height == 22)

        let both = picture.seamCarved(toWidth: 20, toHeight: 12)
        #expect(both.width == 20)
        #expect(both.height == 12)
    }

    /// A size no carve can reach clamps: one pixel at the low end, twice the
    /// size at the high end, because a seam is only ever duplicated once.
    @Test func anImpossibleSizeClamps() {
        let picture = texturedPicture(width: 12, height: 8)
        #expect(picture.seamCarved(toWidth: -5).width == 1)
        #expect(picture.seamCarved(toWidth: 500).width == 23)
    }

    // MARK: - What a seam is

    /// A seam touches every row exactly once and never jumps: from one row to
    /// the next it stays put or steps one pixel sideways. That is the whole
    /// definition, and a backtrack that loses its place breaks it.
    @Test func aSeamTouchesEveryRowOnceAndNeverJumps() {
        let picture = texturedPicture(width: 20, height: 14)
        let seams = picture.seams(4)
        #expect(seams.count == 4)

        for seam in seams {
            #expect(!seam.isClosed)
            #expect(seam.points.count == 14)
            for (row, point) in seam.points.enumerated() {
                #expect(point.y == Double(row) + 0.5)
            }
            for i in 1 ..< seam.points.count {
                let step = abs(seam.points[i].x - seam.points[i - 1].x)
                #expect(step <= 1.0001)
            }
        }
    }

    /// A horizontal seam is the same thing turned: one pixel per column, and
    /// never a jump.
    @Test func aHorizontalSeamRunsAcrossTheColumns() {
        let picture = texturedPicture(width: 18, height: 12)
        let seams = picture.seams(2, along: .horizontal)
        #expect(seams.count == 2)

        for seam in seams {
            #expect(seam.points.count == 18)
            for (column, point) in seam.points.enumerated() {
                #expect(point.x == Double(column) + 0.5)
            }
            for i in 1 ..< seam.points.count {
                #expect(abs(seam.points[i].y - seam.points[i - 1].y) <= 1.0001)
            }
        }
    }

    // MARK: - The cost

    /// A free way down is the way the first seam takes. Every column here
    /// carries its own gray, so removing one joins two grays that differ, except
    /// at column 7, whose neighbors match: closing that gap costs nothing at all.
    /// The seam has to find it and hold it for the whole height.
    @Test func theFreeWayDownIsTheWayTaken() {
        for energy in [SeamEnergy.forward, .gradient] {
            let picture = corridorPicture()
            let seam = picture.seams(1, energy: energy)[0]
            #expect(seam.points.allSatisfy { $0.x == 7.5 })
        }
    }

    /// The forward cost is the cost of the *join*, and each way in has its own
    /// price. Two rows, hand-worked: coming down from the right closes a gap
    /// between two pixels that already match, so it costs nothing over the
    /// crossing itself; coming from the left joins two that differ. The right
    /// way in wins by 0.2 even though the left one starts from a cheaper row.
    /// Trade the two prices for each other and the seam leans the other way.
    @Test func aSeamLeansTowardTheJoinThatCostsNothing() {
        let top: [Double] = [0.6, 0.0, 0.6, 1.0, 0.4]
        let bottom: [Double] = [1.0, 0.2, 0.2, 0.6, 1.0]
        let picture = Image(width: 5, height: 2, color: .black)
        for (x, value) in top.enumerated() { picture[x, 0] = Color(white: value) }
        for (x, value) in bottom.enumerated() { picture[x, 1] = Color(white: value) }

        let seam = picture.seams(1, energy: .forward)[0]
        #expect(seam.points.count == 2)
        #expect(seam.points[0] == Vector2(3.5, 0.5))
        #expect(seam.points[1] == Vector2(2.5, 1.5))
    }

    /// What carries texture keeps its shape; what is flat gives way. A striped
    /// patch on plain ground survives a carve that takes a third of the width,
    /// because every seam through the patch would put two unlike stripes side
    /// by side.
    @Test func whatCarriesTextureKeepsItsShape() {
        let picture = Image(width: 60, height: 30, color: Color(white: 0.5))
        for y in 10 ..< 20 {
            for x in 25 ..< 35 {
                picture[x, y] = Color(white: x % 2 == 0 ? 0.0 : 1.0)
            }
        }

        let carved = picture.seamCarved(toWidth: 40)
        #expect(carved.width == 40)
        for y in 10 ..< 20 {
            var striped = 0
            for x in 0 ..< carved.width {
                let value = carved[x, y].luminance
                if value < 0.05 || value > 0.95 { striped += 1 }
            }
            #expect(striped == 10)
        }
    }

    /// The picture closes over each seam before the next one is looked for, so
    /// carving three seams at once is carving one seam three times. Leave the
    /// picture open between seams and the second seam is only the first one
    /// found again.
    @Test func seamsAreTakenOneAfterTheOther() {
        let picture = texturedPicture(width: 20, height: 12)
        var oneAtATime = picture
        for width in stride(from: 19, through: 17, by: -1) {
            oneAtATime = oneAtATime.seamCarved(toWidth: width)
        }
        let allAtOnce = picture.seamCarved(toWidth: 17)

        #expect(oneAtATime.width == allAtOnce.width)
        for y in 0 ..< allAtOnce.height {
            for x in 0 ..< allAtOnce.width {
                #expect(oneAtATime[x, y] == allAtOnce[x, y])
            }
        }
    }

    // MARK: - The masks

    /// A protected band is never crossed. The free way down is right where the
    /// mask is, so without the mask the seam takes it; with the mask it has to
    /// pay its way somewhere else.
    @Test func aProtectedBandIsNeverCrossed() {
        let picture = corridorPicture()
        #expect(picture.seams(1)[0].points.allSatisfy { $0.x == 7.5 })

        let mask = Image(width: picture.width, height: picture.height, color: .black)
        for y in 0 ..< picture.height { mask[7, y] = .white }

        let guarded = picture.seams(3, protecting: mask)
        for seam in guarded {
            #expect(seam.points.allSatisfy { $0.x != 7.5 })
        }
    }

    /// A discarded band goes first. Column 3 is the most expensive way down in
    /// this picture, so no carve would ever take it; marked for discard, it is
    /// the first thing the carve reaches for.
    @Test func aDiscardedBandGoesFirst() {
        let picture = corridorPicture()
        #expect(picture.seams(1)[0].points.allSatisfy { $0.x != 3.5 })

        let mask = Image(width: picture.width, height: picture.height, color: .black)
        for y in 0 ..< picture.height { mask[3, y] = .white }

        let seam = picture.seams(1, discarding: mask)[0]
        #expect(seam.points.allSatisfy { $0.x == 3.5 })
    }

    /// A mask of the wrong size is left out rather than half applied, so the
    /// carve still runs and still gives the size it was asked for.
    @Test func aMaskOfTheWrongSizeIsLeftOut() {
        let picture = corridorPicture()
        let mask = Image(width: 4, height: 4, color: .white)
        let seam = picture.seams(1, protecting: mask)[0]
        #expect(seam.points.allSatisfy { $0.x == 7.5 })
    }

    // MARK: - Growth

    /// Growing puts pixels back rather than stretching: the picture gets wider
    /// by exactly what was asked, and every column the picture started with is
    /// still in every row.
    @Test func growingKeepsEveryColumnItStartedWith() {
        let picture = Image(width: 8, height: 4, color: .black)
        let grays = [0.0, 0.15, 0.35, 0.5, 0.6, 0.75, 0.85, 1.0]
        for y in 0 ..< 4 {
            for (x, value) in grays.enumerated() { picture[x, y] = Color(white: value) }
        }

        // Read the source's own values back, so the check is against what the
        // picture holds rather than against the numbers it was written with.
        let started = (0 ..< 8).map { picture[$0, 0].luminance }

        let grown = picture.seamCarved(toWidth: 12)
        #expect(grown.width == 12)
        for y in 0 ..< 4 {
            let row = (0 ..< 12).map { grown[$0, y].luminance }
            for value in started {
                #expect(row.contains { abs($0 - value) < 1e-6 })
            }
        }
    }

    // MARK: - The map

    /// The map and the carve are the same answer read two ways: a size taken out
    /// of the map matches the carve to that size, pixel for pixel.
    @Test func theMapAgreesWithTheCarve() {
        let picture = texturedPicture(width: 20, height: 12)
        guard let map = picture.seamMap() else {
            Issue.record("the map was not built")
            return
        }
        #expect(map.sizes == 1 ... 39)

        for width in [19, 16, 12] {
            guard let fromMap = map.image(width) else {
                Issue.record("the map gave no picture at \(width)")
                return
            }
            let carved = picture.seamCarved(toWidth: width)
            #expect(fromMap.width == carved.width)
            #expect(fromMap.height == carved.height)
            for y in 0 ..< carved.height {
                for x in 0 ..< carved.width {
                    #expect(fromMap[x, y] == carved[x, y])
                }
            }
        }
    }

    /// The map grows the same way the carve does.
    @Test func theMapGrowsLikeTheCarve() {
        let picture = texturedPicture(width: 16, height: 10)
        guard let map = picture.seamMap(), let grown = map.image(21) else {
            Issue.record("the map was not built")
            return
        }
        let carved = picture.seamCarved(toWidth: 21)
        #expect(grown.width == 21)
        for y in 0 ..< carved.height {
            for x in 0 ..< carved.width { #expect(grown[x, y] == carved[x, y]) }
        }
    }

    /// A seam read off the map is the same seam the picture gives up.
    @Test func aSeamFromTheMapIsTheSeamTheCarveTakes() {
        let picture = texturedPicture(width: 18, height: 10)
        guard let map = picture.seamMap() else {
            Issue.record("the map was not built")
            return
        }
        let direct = picture.seams(3)
        for index in 0 ..< 3 {
            #expect(map.seam(index).points == direct[index].points)
        }
    }

    // MARK: - Turning it

    /// Carving the height is carving the width of the picture turned on its
    /// side. Turn it, carve, turn it back, and the two agree pixel for pixel.
    @Test func theHorizontalCarveIsTheVerticalOneTurned() {
        let picture = texturedPicture(width: 14, height: 18)
        let shortened = picture.seamCarved(toHeight: 12)
        let turnedAndCarved = turned(turned(picture).seamCarved(toWidth: 12))

        #expect(shortened.width == turnedAndCarved.width)
        #expect(shortened.height == turnedAndCarved.height)
        for y in 0 ..< shortened.height {
            for x in 0 ..< shortened.width {
                #expect(shortened[x, y] == turnedAndCarved[x, y])
            }
        }
    }

    // MARK: - Housekeeping

    /// The same picture carved twice comes out the same, pixel for pixel: ties
    /// break on position, so nothing here is left to chance.
    @Test func carvingIsDeterministic() {
        let picture = texturedPicture(width: 22, height: 14)
        let first = picture.seamCarved(toWidth: 15)
        let second = picture.seamCarved(toWidth: 15)
        for y in 0 ..< first.height {
            for x in 0 ..< first.width { #expect(first[x, y] == second[x, y]) }
        }
    }

    /// Asking for the size it already is hands the picture straight back.
    @Test func askingForNothingChangesNothing() {
        let picture = texturedPicture(width: 10, height: 6)
        let same = picture.seamCarved(toWidth: 10, toHeight: 6)
        #expect(same === picture)
    }

    /// The energy picture is the carve's own reading: bright where the picture
    /// changes, dark where it does not. The free corridor reads darkest.
    @Test func theEnergyPictureIsDarkWhereTheCarveIsFree() {
        guard let energy = corridorPicture().seamEnergy(.gradient) else {
            Issue.record("no energy picture")
            return
        }
        #expect(energy.width == 16)
        #expect(energy.height == 10)
        #expect(energy[7, 5].luminance < 0.01)
        #expect(energy[3, 5].luminance > 0.5)
    }
}

// MARK: - Pictures the laws are read on

/// A picture whose every column carries its own gray, with one free way down at
/// column 7 (its neighbors match, so closing that gap costs nothing) and the
/// most expensive way down at column 3 (its neighbors are as far apart as they
/// go). Every row is the same, so a seam can hold one column for the whole
/// height.
private func corridorPicture() -> Image {
    var columns = [0.10, 0.45, 0.00, 0.55, 1.00, 0.25, 0.70, 0.35, 0.70, 0.15,
                   0.50, 0.20, 0.80, 0.30, 0.60, 0.05]
    columns[3] = 0.55
    let picture = Image(width: columns.count, height: 10, color: .black)
    for y in 0 ..< 10 {
        for (x, value) in columns.enumerated() { picture[x, y] = Color(white: value) }
    }
    return picture
}

/// A picture with texture in both directions, so no seam is free and the carve
/// has to make a real choice.
private func texturedPicture(width: Int, height: Int) -> Image {
    let picture = Image(width: width, height: height, color: .black)
    for y in 0 ..< height {
        for x in 0 ..< width {
            // A fixed, rounded pattern: no rng, and no two columns alike.
            let value = (Double((x * 7 + y * 13) % 11) / 10 + Double((x * 3) % 5) / 8) / 2
            picture[x, y] = Color(white: min(max(value, 0), 1))
        }
    }
    return picture
}

/// The picture turned on its side, so a height carve can be checked against a
/// width carve.
private func turned(_ picture: Image) -> Image {
    let output = Image(width: picture.height, height: picture.width, color: .black)
    for y in 0 ..< picture.height {
        for x in 0 ..< picture.width { output[y, x] = picture[x, y] }
    }
    return output
}
