/// The look of an on-canvas status notice (see `Sketch.drawStatus`).
public enum StatusStyle: Sendable {
    /// Quiet gray — something hasn't started yet ("Waiting for camera…").
    case info
    /// Salmon — something can't run here (a vision model with no compute
    /// device, a missing install) and the sketch should say why.
    case warning
}

/// Which edge a caption sits on (see `Sketch.drawCaption`).
public enum CaptionEdge: Sendable {
    case top
    case bottom
}

extension Sketch {
    /// Draw a standard status notice — `message` centered in `container` (the
    /// whole canvas by default), wrapped if long, in the standard typeface. The
    /// one-liner for the states a sketch should report instead of staying
    /// silently blank: a feed that hasn't produced a frame (`.info`, the
    /// default) or a capability that can't run on this Mac (`.warning`).
    ///
    /// ```swift
    /// if let reason = tracker.unavailableReason {
    ///     return drawStatus(reason, style: .warning)
    /// }
    /// ```
    ///
    /// Draws with its own font, size, and alignment, scoped — the sketch's
    /// drawing state is untouched.
    public func drawStatus(_ message: String, style: StatusStyle = .info,
                           in container: Rectangle? = nil) {
        let box = container ?? bounds
        withState {
            noStroke()
            textFont(OutlineFont.systemMedium)
            textAlign(.center, .middle)
            switch style {
            case .info:
                fill(Color(white: 0.5))
                textSize(22 * scale)
            case .warning:
                fill(Color(red: 1.0, green: 0.5, blue: 0.4))
                textSize(18 * scale)
            }
            drawText(message, in: Rectangle(center: box.center,
                                            width: box.width * 0.8,
                                            height: box.height * 0.6))
        }
    }

    /// Draw a standard caption — `text` centered along the bottom edge of the
    /// canvas (or the top, with `edge: .top`), small and white, in the standard
    /// typeface. The label on a sketch: what it is, what it's showing, what
    /// to do with it.
    ///
    /// ```swift
    /// drawCaption("FaceTracking — \(faces.count) faces")
    /// ```
    ///
    /// Draws with its own font, size, and alignment, scoped — the sketch's
    /// drawing state is untouched. The caption is drawn over the finished frame
    /// (`withOverlay`), so it stays sharp and white over a depth of field, a motion
    /// blur, a bloom, or a lens flare, and never joins an accumulating canvas;
    /// inside a layer or a batch recording, where there is no overlay, it draws
    /// in place.
    public func drawCaption(_ text: String, edge: CaptionEdge = .bottom) {
        let body = {
            self.withState {
                self.noStroke()
                self.fill(.white)
                self.textFont(OutlineFont.systemMedium)
                self.textSize(15 * self.scale)
                let inset = 28 * self.scale
                switch edge {
                case .bottom:
                    self.textAlign(.center, .bottom)
                    self.drawText(text, self.width / 2, self.height - inset)
                case .top:
                    self.textAlign(.center, .top)
                    self.drawText(text, self.width / 2, inset)
                }
            }
        }
        if drawer.canDrawOverlay { withOverlay(body) } else { body() }
    }
}
