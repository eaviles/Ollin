import Testing
import Foundation
import simd
import Ollin
@testable import OllinPhone

/// Exercises the marker stream over staged wire samples (GPU-free, CI-safe): the
/// size a reference file's own name states, the name left after that size is taken
/// off, and the placement frame a sketch hands to `transform(_:)`. The numbers are
/// chosen so each expectation has one hand-checkable answer.
@Suite(.timeLimit(.minutes(1))) struct PhoneMarkerTests {

    // MARK: What the file name says

    @Test func aNameCanStateThePrintedWidth() {
        // The four ways somebody writes a size, and the units they write it in.
        #expect(abs(PhoneWire.markerWidth(fromName: "poster@30cm.png").meters - 0.3) < 1e-9)
        #expect(abs(PhoneWire.markerWidth(fromName: "card-50mm.jpg").meters - 0.05) < 1e-9)
        #expect(abs(PhoneWire.markerWidth(fromName: "plate 12in.heic").meters - 0.3048) < 1e-9)
        #expect(abs(PhoneWire.markerWidth(fromName: "tile_0.4m.png").meters - 0.4) < 1e-9)
        #expect(PhoneWire.markerWidth(fromName: "poster@30cm.png").stated)
    }

    @Test func aNameThatSaysNothingGetsTheFallback() {
        // A word that merely ends in a unit says nothing: "diagram" is not 0 meters
        // and "platinum" is not a measurement, so both take the fallback and report
        // that they were not told.
        for name in ["diagram.png", "platinum.jpg", "poster.png", "cover.heic"] {
            let width = PhoneWire.markerWidth(fromName: name)
            #expect(!width.stated, "\(name) should state no size")
            #expect(abs(width.meters - 0.15) < 1e-9)
        }
    }

    @Test func anAbsurdSizeIsRefusedRatherThanTrusted() {
        // A wrong width puts a picture at the wrong distance, so a measurement
        // outside a printable range is treated as no measurement at all.
        #expect(!PhoneWire.markerWidth(fromName: "wall@900cm.png").stated)   // 9 meters
        #expect(!PhoneWire.markerWidth(fromName: "speck@2mm.png").stated)    // 2 millimeters
        // The edges of that range still count.
        #expect(PhoneWire.markerWidth(fromName: "stamp@1cm.png").stated)
        #expect(PhoneWire.markerWidth(fromName: "banner@5m.png").stated)
    }

    @Test func theNameIsWhatIsLeftAfterTheSize() {
        // What a sketch matches on: the file's own name, with the extension and the
        // size taken off, and with the separator that introduced the size gone too.
        #expect(PhoneWire.markerName(fromFileName: "poster@30cm.png") == "poster")
        #expect(PhoneWire.markerName(fromFileName: "card-50mm.jpg") == "card")
        #expect(PhoneWire.markerName(fromFileName: "my sign 12in.heic") == "my sign")
        #expect(PhoneWire.markerName(fromFileName: "tile_0.4m.png") == "tile")
        // No size in the name means the whole name is the name.
        #expect(PhoneWire.markerName(fromFileName: "diagram.png") == "diagram")
        #expect(PhoneWire.markerName(fromFileName: "teapot.arobject") == "teapot")
    }

    // MARK: The placement of a picture

    /// A 30 by 42 cm print hanging on a wall two meters away, facing the room. Its
    /// anchor lies in its own x-z plane the way ARKit reports one: the anchor's y
    /// axis points out of the printed face (world +z), and the picture's own up
    /// direction is the anchor's -z (world +y).
    private func wallPrint(scale: Float = 1) -> PhoneMarker {
        let x = SIMD3<Float>(1, 0, 0) * scale
        let y = SIMD3<Float>(0, 0, 1) * scale
        let z = SIMD3<Float>(0, -1, 0) * scale
        return PhoneMarker(PhoneMarkerSample(
            isTracked: true, timestamp: 4, id: UUID(), name: "poster", kind: .image,
            transform: simd_float4x4(SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0),
                                     SIMD4<Float>(0, 1.5, -2, 1)),
            size: SIMD3<Float>(0.3, 0.42, 0), scaleFactor: scale))
    }

    @Test func aPictureStandsUpInItsPlacementFrame() {
        let marker = wallPrint()
        // The frame a sketch draws through: x across the print, y up it, z out of
        // the face toward whoever looks at it. This print faces the room, so the
        // three axes land on the world's own.
        #expect(marker.across.distance(to: Vector3(1, 0, 0)) < 1e-6)
        #expect(marker.up.distance(to: Vector3(0, 1, 0)) < 1e-6)
        #expect(marker.facing.distance(to: Vector3(0, 0, 1)) < 1e-6)
        #expect(marker.position.distance(to: Vector3(0, 1.5, -2)) < 1e-6)
        #expect(abs(marker.width - 0.3) < 1e-6)
        #expect(abs(marker.height - 0.42) < 1e-6)
        #expect(marker.depth == 0)
        #expect(marker.isImage)
    }

    @Test func theCornersRunAroundThePrint() {
        // Perimeter order, top-left first: half the width across and half the
        // height up from the middle.
        let corners = wallPrint().corners
        #expect(corners.count == 4)
        #expect(corners[0].distance(to: Vector3(-0.15, 1.71, -2)) < 1e-6)
        #expect(corners[1].distance(to: Vector3(0.15, 1.71, -2)) < 1e-6)
        #expect(corners[2].distance(to: Vector3(0.15, 1.29, -2)) < 1e-6)
        #expect(corners[3].distance(to: Vector3(-0.15, 1.29, -2)) < 1e-6)
    }

    @Test func anEstimatedScaleBecomesSizeNotAScaledFrame() {
        // ARKit folds its own estimate of the printed size into the anchor. A frame
        // carrying that scale would scale everything drawn through it, so the
        // placement is handed back clean and the scale is reported as size: this
        // print measures a tenth more than its name said.
        let marker = wallPrint(scale: 1.1)
        #expect(abs(marker.width - 0.33) < 1e-5)
        #expect(abs(marker.height - 0.462) < 1e-5)
        // Every axis of the frame is still one unit long.
        for axis in [marker.across, marker.up, marker.facing] {
            #expect(abs(axis.length - 1) < 1e-6)
        }
    }

    @Test func aBrokenPlacementFallsBackToTheWorldAxes() {
        // A matrix of zeros would divide by zero. It reads as the world's own axes
        // instead, so a bad frame draws in the wrong place rather than as NaN.
        let marker = PhoneMarker(PhoneMarkerSample(
            isTracked: false, timestamp: 0, id: UUID(), name: "broken", kind: .image,
            transform: simd_float4x4(SIMD4<Float>(repeating: 0), SIMD4<Float>(repeating: 0),
                                     SIMD4<Float>(repeating: 0), SIMD4<Float>(repeating: 0)),
            size: .zero))
        #expect(marker.across.distance(to: Vector3(1, 0, 0)) < 1e-6)
        #expect(marker.facing.length == 1)
    }

    // MARK: The placement of an object

    @Test func anObjectStandsAtTheMiddleOfItsBox() {
        // A scanned teapot whose anchor sits on the table under it: the middle of
        // its box is six centimeters up its own y axis, and the axes are the ones
        // the scan gave it. Turned a quarter around y, that offset comes out along
        // world y all the same, and the box keeps its measured size.
        let quarter = simd_float4x4(SIMD4<Float>(0, 0, -1, 0), SIMD4<Float>(0, 1, 0, 0),
                                    SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0.5, 0, -1, 1))
        let marker = PhoneMarker(PhoneMarkerSample(
            isTracked: true, timestamp: 2, id: UUID(), name: "teapot", kind: .object,
            transform: quarter, size: SIMD3<Float>(0.18, 0.12, 0.14),
            center: SIMD3<Float>(0, 0.06, 0)))
        #expect(marker.isObject)
        #expect(marker.position.distance(to: Vector3(0.5, 0.06, -1)) < 1e-6)
        #expect(abs(marker.width - 0.18) < 1e-6)
        #expect(abs(marker.depth - 0.14) < 1e-6)
        // The quarter turn puts the object's own x along the world's -z.
        #expect(marker.across.distance(to: Vector3(0, 0, -1)) < 1e-6)
        #expect(marker.up.distance(to: Vector3(0, 1, 0)) < 1e-6)
    }

    @Test func anObjectsSizeIgnoresTheScaleField() {
        // Only a picture is measured against a stated width, so an object's box is
        // reported exactly as its scan measured it whatever the scale field says.
        let marker = PhoneMarker(PhoneMarkerSample(
            isTracked: true, timestamp: 0, id: UUID(), name: "cup", kind: .object,
            transform: matrix_identity_float4x4, size: SIMD3<Float>(0.1, 0.1, 0.1),
            scaleFactor: 2))
        #expect(abs(marker.width - 0.1) < 1e-6)
    }
}
