import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public extension Sketch {
    /// Put the frame on the clipboard as a PNG, ready to paste into another app.
    ///
    /// The frame is the next one the window shows, read through the same
    /// frame grab a recorder uses, at the canvas's own size whatever the
    /// window's, so the copy costs one more pass on that frame and no second
    /// render. The usual caller is an input hook:
    ///
    /// ```swift
    /// override func keyPressed() {
    ///     if key == "c" { copyFrame() }
    /// }
    /// ```
    ///
    /// A sketch that has stopped looping draws one frame for the copy, as
    /// ``redraw()`` would, so what it copies is what its `draw()` makes now:
    /// a still sketch that rolls new numbers in every `draw()` copies a new
    /// roll. Building the picture in `setup()`, or seeding the numbers inside
    /// `draw()`, keeps the copy the picture on screen.
    ///
    /// The copy takes the place of whatever the clipboard held. In an export
    /// there is no window and no clipboard to write to, and the call does
    /// nothing.
    func copyFrame() {
        #if os(macOS)
        copyFrame(to: .general)
        #else
        copyFrame { png in
            UIPasteboard.general.setData(png, forPasteboardType: UTType.png.identifier)
        }
        #endif
    }
}

extension Sketch {
    #if os(macOS)
    /// `copyFrame()` onto a pasteboard the caller names, so a test reads the
    /// bytes off a pasteboard of its own rather than the person's clipboard.
    func copyFrame(to pasteboard: NSPasteboard) {
        copyFrame { png in
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
        }
    }
    #endif

    /// Copy the next frame shown as PNG bytes into `write`.
    func copyFrame(into write: @escaping @MainActor (Data) -> Void) {
        guard host != nil else { return }
        let copier: FrameCopier
        if let armed = frameCopier {
            copier = armed
        } else {
            copier = FrameCopier()
            frameCopier = copier
            extend(copier)
        }
        copier.write = write
        redraw()
    }
}

/// The one-shot frame grab behind `copyFrame()`: armed by the call, spent by
/// the first frame it is handed, and asking for nothing in between.
final class FrameCopier: SketchExtension {
    var write: (@MainActor (Data) -> Void)?

    var wantsRenderedFrame: Bool { write != nil }

    func frameRendered(_ sketch: Sketch, image: CGImage) {
        guard let write else { return }
        self.write = nil
        guard let png = Self.png(of: image) else {
            FileHandle.standardError.write(Data(
                "Ollin: the frame could not be encoded as a PNG, so nothing was copied\n".utf8))
            return
        }
        write(png)
    }

    /// `image` as PNG bytes, carrying its color space; nil if the system
    /// declines to encode it.
    static func png(of image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        let properties = [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGSoftware: "Ollin"]]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
