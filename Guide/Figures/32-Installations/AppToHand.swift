// figure: frame=0 themed
//
// Guide diagram (Chapter 32): what wrapping a sketch as an app gives you and
// what it does not. On the left, the app itself and where its icon comes from,
// which is one rendered frame of the sketch. On the right, the two ways it can
// travel, because the signature is what decides that: unsigned reaches this
// machine, notarized reaches any Mac. The point of the figure: the app is a
// wrapper, so nothing about the sketch changed on the way in.
import Ollin
import OllinDiagram

final class AppToHand: Sketch {
    override var canvasSize: CanvasSize { .size(880, 500) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The piece's own colors: depicted content, the same in both themes.
    let night = Color(hex: 0x141B2B)
    let path = Color(hex: 0x6E8CC4)
    let star = Color(hex: 0xF2C14E)

    override func draw() {
        let theme = self.theme
        background(theme.paper)
        noStroke()
        textFont(.system)

        drawText("A wrapper, not a port. The sketch is unchanged inside it.",
                 40, 26, size: 17, color: theme.ink, align: .left, .top)
        drawText("ollin new Orbit --kind mac-app   then   ./build.sh", 40, 52,
                 size: 12, color: theme.accent, align: .left, .top)

        bundle()
        travel()

        drawText("A sketch that declares an Installation keeps it inside the app, so the double click",
                 40, 440, size: 13, color: theme.ink, align: .left, .top)
        drawText("opens the piece full screen and unattended. The wall machine needs no toolchain.",
                 40, 462, size: 13, color: theme.ink, align: .left, .top)
    }

    // MARK: The app, and where its face comes from

    func bundle() {
        let theme = self.theme

        // One frame of the sketch, rendered by the build script.
        let frame = Rectangle(x: 40, y: 104, width: 130, height: 130)
        orbit(in: frame)
        stroke(theme.border)
        strokeWeight(1)
        noFill()
        drawRect(frame)
        noStroke()
        drawText("one frame, rendered", frame.x, frame.y + frame.height + 10,
                 size: 11, color: theme.muted, align: .left, .top)

        // Which becomes the icon the Finder shows.
        let icon = Rectangle(x: 268, y: 104, width: 130, height: 130)
        orbit(in: icon, rounded: 28)
        drawText("Orbit.app", icon.center.x, icon.y + icon.height + 10,
                 size: 13, color: theme.ink, align: .center, .top)

        stroke(theme.accent)
        strokeWeight(2)
        drawLine(Vector2(frame.x + frame.width + 12, frame.center.y),
                 Vector2(icon.x - 14, frame.center.y))
        noStroke()
        fill(theme.accent)
        drawTriangle(Vector2(icon.x - 4, frame.center.y),
                     Vector2(icon.x - 14, frame.center.y - 5),
                     Vector2(icon.x - 14, frame.center.y + 5))
        let gap = (frame.x + frame.width + icon.x) / 2
        drawText("the piece wears", gap, frame.center.y - 44,
                 size: 11, color: theme.muted, align: .center, .top)
        drawText("its own face", gap, frame.center.y - 30,
                 size: 11, color: theme.muted, align: .center, .top)

        drawText("Drop an AppIcon.icns beside build.sh to choose it yourself.",
                 40, 290, size: 12, color: theme.muted, align: .left, .top)
        drawText("Inside: the same class, its @main, the mouse, the keyboard,",
                 40, 320, size: 13, color: theme.ink, align: .left, .top)
        drawText("and every export flag. Keep working in a window and wrap",
                 40, 342, size: 13, color: theme.ink, align: .left, .top)
        drawText("when it looks right.", 40, 364, size: 13, color: theme.ink, align: .left, .top)
    }

    /// The sketch the app wraps: a body going around another.
    func orbit(in box: Rectangle, rounded: Double = 0) {
        fill(night)
        drawRect(box, cornerRadius: rounded)
        let center = box.center
        let radius = box.width * 0.3
        stroke(path.withAlpha(0.8))
        strokeWeight(box.width / 90)
        noFill()
        drawEllipse(center: center, radiusX: radius, radiusY: radius * 0.45)
        noStroke()
        fill(star)
        drawCircle(center: center, radius: box.width * 0.075)
        fill(path)
        drawCircle(center.x + radius, center.y, box.width * 0.035)
        fill(path.withAlpha(0.6))
        drawCircle(center.x - radius * 0.72, center.y + radius * 0.3, box.width * 0.024)
    }

    // MARK: How far it travels

    func travel() {
        route(at: Rectangle(x: 470, y: 104, width: 370, height: 130),
              command: "./build.sh",
              headline: "signed for this machine",
              note: "and it says so every time, so nobody\nships one by accident",
              reach: "this Mac")

        route(at: Rectangle(x: 470, y: 254, width: 370, height: 148),
              command: "./build.sh --sign \"Developer ID …\" --notarize",
              headline: "through Apple's notary",
              note: "leaves an Orbit.zip beside the app,\nready to send",
              reach: "any Mac")
    }

    func route(at box: Rectangle, command: String, headline: String, note: String, reach: String) {
        let theme = self.theme
        fill(theme.card)
        drawRect(box, cornerRadius: 8)
        stroke(theme.border)
        strokeWeight(1)
        noFill()
        drawRect(box, cornerRadius: 8)
        noStroke()

        textFont(.systemMono)
        drawText(command, box.x + 16, box.y + 14, size: 11, color: theme.accent, align: .left, .top)
        textFont(.system)
        drawText(headline, box.x + 16, box.y + 38, size: 14, color: theme.ink, align: .left, .top)
        for (index, line) in note.split(separator: "\n").enumerated() {
            drawText(String(line), box.x + 16, box.y + 62 + Double(index) * 17,
                     size: 12, color: theme.muted, align: .left, .top)
        }

        // What it reaches, as a small machine with its lid.
        let mac = Rectangle(x: box.x + box.width - 96, y: box.y + box.height - 62,
                            width: 76, height: 44)
        fill(theme.ink(0.12))
        drawRect(mac, cornerRadius: 4)
        fill(theme.ink(0.3))
        drawRect(Rectangle(x: mac.x - 8, y: mac.y + mac.height, width: mac.width + 16, height: 5),
                 cornerRadius: 2)
        drawText(reach, mac.center.x, mac.y + mac.height + 12,
                 size: 12, color: theme.ink, align: .center, .top)
    }
}
