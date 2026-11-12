import AppKit
import Foundation
import Ollin
import SwiftUI

/// `swift run OllinLive --inspectortest`: the inspector's controls driven by
/// posted events, and the parameters they moved read back. The parameters
/// list is hosted in a window built in this process, over a host that keeps
/// a turned set the way a live session does. A toggle is clicked and a
/// number typed, every event posted to the application's own queue, which is
/// where a real click lands after the window server, so the check runs on a
/// locked screen. Then:
///
/// - **Undo and redo**, sent down the window's responder chain as the Edit
///   menu sends them: each edit goes back and comes forward, the row shows
///   it, the host hears of it, and the first edit undone takes the row's
///   turned mark with it. A reset is one step that brings the marks back.
/// - **The grouped menu**: the menu AppKit was handed for an `Easing`
///   parameter is read as built (twelve rows on its first level, three in a
///   family's submenu, the pick checked), and an item in a submenu is chosen
///   the way a click on it is.
/// - **The Colors panel**: left on top of the inspector, it is moved clear of
///   the list's column when a color row opens it; a color set in the panel
///   lands in the parameter whose well is lit and no other; and the second
///   well's click hands the panel that parameter's color.
///
/// What it cannot reach is anything SwiftUI draws with no view of its own to
/// aim at: the slider's track, the curve and bars rows, the timeline's lanes.
/// Those are desk checks.
@MainActor
enum InspectorTest {
    final class Subject: Sketch {
        @Param(0 ... 200) var radius = 50.0
        @Param var visible = true
        @Param var curve: Easing = .easeInOutCubic
        @Param var ink = Color(red: 0.2, green: 0.4, blue: 0.8)
        @Param var paper = Color(red: 0.9, green: 0.85, blue: 0.7)
    }

    /// What a live session keeps for the list: the names turned by hand, and
    /// every edit it was told of.
    @Observable
    final class Host {
        var tuned: Set<String> = []
        @ObservationIgnored var changes: [(String, ParamStored)] = []

        func heard(_ name: String) -> Int { changes.filter { $0.0 == name }.count }
    }

    struct Root: View {
        let sketch: Subject
        let handles: [ParamHandle]
        let host: Host

        var body: some View {
            ParametersListView(
                parameters: handles, sketchName: "InspectorTest",
                onChange: { name, stored in
                    host.tuned.insert(name)
                    host.changes.append((name, stored))
                },
                reset: ParamResetAction(tuned: host.tuned) { names in
                    sketch.resetParameters(named: names)
                    host.tuned.subtract(names ?? handles.map(\.name))
                })
                .frame(width: 320)
        }
    }

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        wakeAccessibility(app)
        let sketch = Subject()
        let handles = sketch.parameters()
        check(handles.map(\.name) == ["radius", "visible", "curve", "ink", "paper"],
              "the subject's parameters read \(handles.map(\.name))")
        let host = Host()
        let hosting = NSHostingView(rootView: Root(sketch: sketch, handles: handles, host: host))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 420),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        app.finishLaunching()
        app.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        pump(app, for: 0.6)

        let undone = toggleAndUndo(app, window, hosting, sketch, handles, host)
        typeAndUndo(app, window, hosting, sketch, handles, host)
        let dragged = dragAndUndo(app, window, sketch, host)
        resetAndUndo(app, window, sketch, host, radius: dragged)
        let picked = groupedMenu(app, window, hosting, sketch, host)
        let moved = colorsPanel(app, window, hosting, sketch, host)

        print("inspectortest: ok (the field took radius to 120 and undo put it back; a drag took it to "
              + "\(dragged) in one step; a click flipped visible and \(undone) undo steps ran; "
              + "the menu's \(picked); the Colors panel \(moved))")
        exit(0)
    }

    // MARK: The toggle, and undo down the responder chain

    private static func toggleAndUndo(_ app: NSApplication, _ window: NSWindow, _ hosting: NSView,
                                      _ sketch: Subject, _ handles: [ParamHandle], _ host: Host) -> Int {
        guard let toggle = view(named: "PlatformSwitch", under: hosting) else {
            fail("no switch among the inspector's views: \(classes(under: hosting))")
        }
        let box = screenFrame(of: toggle)
        click(app, window, at: NSPoint(x: box.midX, y: box.midY))
        pump(app, for: 0.5)
        check(sketch.visible == false, "the click did not flip the toggle (window key: \(window.isKeyWindow))")
        guard case .boolean(let flipped) = handles[1].param.stored else {
            fail("the toggle's parameter reads \(handles[1].param.stored)")
        }
        check(flipped == sketch.visible, "the handle and the sketch disagree: \(flipped) vs \(sketch.visible)")
        check(host.heard("visible") == 1, "the host heard of visible \(host.heard("visible")) times, not once")
        check(host.tuned == ["visible"], "the host's turned set reads \(host.tuned)")

        // Undo, as the Edit menu sends it. The value goes back, and since the
        // row was not turned before the click, so does its mark.
        check(window.undoManager?.canUndo == true, "the click registered nothing to undo")
        check(window.undoManager?.undoMenuItemTitle == "Undo Change Visible",
              "the step is named \(window.undoManager?.undoMenuItemTitle ?? "nothing")")
        send("undo:", to: window)
        pump(app, for: 0.4)
        check(sketch.visible == true, "undo left visible at \(sketch.visible)")
        check(host.tuned.isEmpty, "undoing the row's first edit left it marked as turned: \(host.tuned)")
        check((toggle as? NSControl)?.integerValue ?? 1 == 1, "the switch did not follow the undo")

        send("redo:", to: window)
        pump(app, for: 0.4)
        check(sketch.visible == false, "redo left visible at \(sketch.visible)")
        check(host.tuned == ["visible"], "redo did not mark the row as turned again: \(host.tuned)")
        check(host.heard("visible") == 2, "redo told the host \(host.heard("visible") - 1) times, not once")
        return 2
    }

    // MARK: The number field

    private static func typeAndUndo(_ app: NSApplication, _ window: NSWindow, _ hosting: NSView,
                                    _ sketch: Subject, _ handles: [ParamHandle], _ host: Host) {
        guard let field = view(named: "AppKitTextField", under: hosting) else {
            fail("no text field among the inspector's views: \(classes(under: hosting))")
        }
        let fieldFrame = screenFrame(of: field)
        check(fieldFrame.width > 10 && fieldFrame.height > 5, "the field's frame reads \(fieldFrame)")
        click(app, window, at: NSPoint(x: fieldFrame.midX, y: fieldFrame.midY))
        pump(app, for: 0.3)
        // A window behind the lock screen is never the key window, and only a
        // key window's click gives a field the keyboard, so the field is
        // handed it here; the keys themselves still arrive as events.
        if !(window.firstResponder is NSTextView) { window.makeFirstResponder(field) }
        pump(app, for: 0.1)
        key(app, window, "a", code: 0, flags: .command)      // select whatever is there
        // Typed slowly, each key later than the quiet time that closes a
        // step: the field writes the parameter as the digits land (1, 12,
        // 120), and the number is still one undo step.
        for (character, code) in [("1", 18), ("2", 19), ("0", 29)] {
            key(app, window, character, code: UInt16(code))
            pump(app, for: 0.45)
        }
        check(sketch.radius == 120, "the canvas follows the typing: radius reads \(sketch.radius) before Return")
        key(app, window, "\r", code: 36)
        pump(app, for: 0.6)
        guard case .number(let typed) = handles[0].param.stored else {
            fail("the number parameter reads \(handles[0].param.stored)")
        }
        check(typed == 120, "typing 120 into the field left radius at \(typed); first responder "
              + "\(String(describing: window.firstResponder.map { type(of: $0) })), key window \(window.isKeyWindow)")
        check(sketch.radius == 120, "the sketch reads what the inspector set: \(sketch.radius)")
        check(host.heard("radius") >= 1, "the host never heard of radius")

        // The field gives up the keyboard first, as a click on the canvas
        // does, so undo is the window's and not the text being typed.
        window.makeFirstResponder(nil)
        pump(app, for: 0.1)
        send("undo:", to: window)
        pump(app, for: 0.4)
        check(sketch.radius == 50, "undo left radius at \(sketch.radius), not the 50 it was typed over")
        check(!host.tuned.contains("radius"), "undo left radius marked as turned")
        check((field as? NSTextField)?.stringValue == "50",
              "the field reads \((field as? NSTextField)?.stringValue ?? "nothing") after the undo")
        // The step under it is still the toggle's.
        check(window.undoManager?.undoMenuItemTitle == "Undo Change Visible",
              "under the field's step the manager holds \(window.undoManager?.undoMenuItemTitle ?? "nothing")")
        send("redo:", to: window)
        pump(app, for: 0.4)
        check(sketch.radius == 120, "redo left radius at \(sketch.radius)")
        check(host.tuned.contains("radius"), "redo did not mark radius as turned")
    }

    // MARK: The slider: one drag is one step

    /// Drag the slider's thumb, which SwiftUI draws with no view of its own:
    /// the accessibility tree says where the thumb is. The drag reports many
    /// values and is one undo step.
    private static func dragAndUndo(_ app: NSApplication, _ window: NSWindow,
                                    _ sketch: Subject, _ host: Host) -> Double {
        let tree = elements(under: window.contentView!)
        guard let track = tree.first(where: { $0.role == "AXSlider" }),
              let thumb = tree.first(where: { $0.role == "AXValueIndicator" }) else {
            fail("no slider in the accessibility tree: \(tree.map(\.role))")
        }
        check(track.value == "120", "the slider reads \(track.value) with radius at 120")
        let heard = host.heard("radius")
        let start = NSPoint(x: thumb.frame.midX, y: thumb.frame.midY)
        post(app, window, .leftMouseDown, at: start)
        pump(app, for: 0.05)
        for step in 1 ... 12 {
            post(app, window, .leftMouseDragged, at: NSPoint(x: start.x - CGFloat(step) * 5, y: start.y))
            pump(app, for: 0.03)
        }
        post(app, window, .leftMouseUp, at: NSPoint(x: start.x - 60, y: start.y))
        pump(app, for: 0.7)       // past the quiet time that closes the step
        let dragged = sketch.radius
        check(dragged < 100 && dragged > 40, "a drag of 60 points to the left took radius from 120 to \(dragged)")
        check(host.heard("radius") - heard >= 3,
              "the drag reported \(host.heard("radius") - heard) values; a drag reports every one it passes")
        check(window.undoManager?.undoMenuItemTitle == "Undo Change Radius",
              "the drag's step is named \(window.undoManager?.undoMenuItemTitle ?? "nothing")")

        send("undo:", to: window)
        pump(app, for: 0.4)
        check(sketch.radius == 120, "one undo after the drag left radius at \(sketch.radius), not the 120 it began at")
        check(window.undoManager?.undoMenuItemTitle == "Undo Change Radius",
              "under the drag the manager holds \(window.undoManager?.undoMenuItemTitle ?? "nothing")")
        send("redo:", to: window)
        pump(app, for: 0.4)
        check(sketch.radius == dragged, "redo left radius at \(sketch.radius), not the \(dragged) the drag ended on")
        return dragged
    }

    // MARK: A reset is one step

    private static func resetAndUndo(_ app: NSApplication, _ window: NSWindow, _ sketch: Subject, _ host: Host,
                                     radius: Double) {
        // The footer's "Reset all" is drawn by SwiftUI with no view of its
        // own; the accessibility tree says where it is, and the click is a
        // posted one.
        press("Reset all", app, window)
        pump(app, for: 0.4)
        check(sketch.radius == 50 && sketch.visible == true,
              "Reset all left radius \(sketch.radius), visible \(sketch.visible)")
        check(host.tuned.isEmpty, "Reset all left \(host.tuned) marked")
        check(window.undoManager?.undoMenuItemTitle == "Undo Reset Parameters",
              "the reset's step is named \(window.undoManager?.undoMenuItemTitle ?? "nothing")")
        send("undo:", to: window)
        pump(app, for: 0.4)
        check(sketch.radius == radius && sketch.visible == false,
              "undoing the reset left radius \(sketch.radius), visible \(sketch.visible)")
        check(host.tuned == ["radius", "visible"], "undoing the reset brought back the marks \(host.tuned)")
    }

    // MARK: The grouped menu

    private static func groupedMenu(_ app: NSApplication, _ window: NSWindow, _ hosting: NSView,
                                    _ sketch: Subject, _ host: Host) -> String {
        let menus = popUps(under: hosting).compactMap(\.menu)
        guard let menu = menus.first(where: { menu in menu.items.contains { $0.title == "Cubic" } }) else {
            fail("no pop-up holds the curve families; the pop-ups read "
                 + "\(popUps(under: hosting).map { $0.menu?.items.map(\.title) ?? [] }), the views \(classes(under: hosting))")
        }
        // The menu's hidden first item is what the pop-up shows closed: the
        // pick's whole name, whichever submenu the pick is in.
        let popUp = popUps(under: hosting).first { $0.menu === menu }
        check(popUp?.titleOfSelectedItem == "Ease In Out Cubic" && menu.items.first?.isHidden == true,
              "the closed menu reads \(popUp?.titleOfSelectedItem ?? "nothing")")
        let level = menu.items.dropFirst().map(\.title)
        check(level == ["Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Expo", "Circ", "Back", "Elastic",
                        "Bounce", "Smoothstep"], "the menu's first level reads \(level)")
        guard let cubic = menu.items.first(where: { $0.title == "Cubic" })?.submenu else {
            fail("Cubic is not a submenu")
        }
        check(cubic.items.map(\.title) == ["Ease In", "Ease Out", "Ease In Out"],
              "the Cubic submenu reads \(cubic.items.map(\.title))")
        check(cubic.items.map(\.state) == [.off, .off, .on], "the pick is not the one checked: \(cubic.items.map(\.state.rawValue))")
        let marked = menu.items.dropFirst().filter { $0.state == .on }.map(\.title)
        check(marked == ["Cubic"], "the rows checked on the first level read \(marked), not the pick's family alone")
        guard let bounce = menu.items.first(where: { $0.title == "Bounce" })?.submenu else {
            fail("Bounce is not a submenu")
        }
        check(bounce.items.allSatisfy { $0.state == .off }, "a family the pick is not in shows a check")

        // Choose Bounce, Ease Out, as a click on the item does.
        bounce.performActionForItem(at: 1)
        pump(app, for: 0.5)
        check(sketch.curve == .easeOutBounce, "choosing Bounce, Ease Out left the curve at \(sketch.curve)")
        check(popUp?.titleOfSelectedItem == "Ease Out Bounce" && bounce.items.map(\.state) == [.off, .on, .off]
              && cubic.items.allSatisfy { $0.state == .off },
              "the menu did not follow the pick: it reads \(popUp?.titleOfSelectedItem ?? "nothing")")
        check(host.changes.last?.0 == "curve" && host.changes.last?.1 == .option("easeOutBounce"),
              "the host heard \(String(describing: host.changes.last))")
        window.makeFirstResponder(nil)
        send("undo:", to: window)
        pump(app, for: 0.4)
        check(sketch.curve == .easeInOutCubic, "undo left the curve at \(sketch.curve)")
        return "first level is \(level.count) rows and Bounce, Ease Out was chosen and undone"
    }

    // MARK: The Colors panel

    private static func colorsPanel(_ app: NSApplication, _ window: NSWindow, _ hosting: NSView,
                                    _ sketch: Subject, _ host: Host) -> String {
        let wells = views(named: "PlatformColorWell", under: hosting)
        check(wells.count == 2, "the list holds \(wells.count) color wells, not two: \(classes(under: hosting))")
        let panel = NSColorPanel.shared
        panel.orderOut(nil)
        // Left where it covers the inspector, which is where it comes back.
        panel.setFrameOrigin(NSPoint(x: window.frame.minX + 20, y: window.frame.minY + 20))
        pump(app, for: 0.2)
        check(panel.frame.intersects(window.frame), "the panel was not put over the inspector to begin with")

        let inkWell = screenFrame(of: wells[0])
        click(app, window, at: NSPoint(x: inkWell.midX, y: inkWell.midY))
        pump(app, for: 0.6)
        check(panel.isVisible, "the click on the ink well did not bring the Colors panel up")
        check(!panel.frame.intersects(window.frame),
              "the Colors panel came up over the inspector: panel \(panel.frame), window \(window.frame)")
        if let screen = (window.screen ?? NSScreen.main)?.visibleFrame {
            check(screen.contains(panel.frame), "the panel was moved off the screen: \(panel.frame) in \(screen)")
        }
        check(near(panel.color, sketch.ink), "the panel shows \(panel.color), the ink is \(sketch.ink)")

        // A color chosen in the panel lands in the lit well's parameter.
        let paperBefore = sketch.paper
        panel.color = NSColor(srgbRed: 0.9, green: 0.1, blue: 0.3, alpha: 1)
        pump(app, for: 0.6)
        check(near(sketch.ink, red: 0.9, green: 0.1, blue: 0.3), "the panel's color left the ink at \(sketch.ink)")
        check(sketch.paper == paperBefore, "the panel's color reached the paper as well: \(sketch.paper)")
        check(host.heard("ink") >= 1, "the host never heard of the ink")

        // The other well: the panel takes that parameter's color, and writes it.
        let place = panel.frame.origin
        let paperWell = screenFrame(of: wells[1])
        click(app, window, at: NSPoint(x: paperWell.midX, y: paperWell.midY))
        pump(app, for: 0.6)
        check(panel.frame.origin == place, "the panel moved again while it was already up")
        check(near(panel.color, paperBefore), "the panel shows \(panel.color) for the paper \(paperBefore)")
        let inkNow = sketch.ink
        panel.color = NSColor(srgbRed: 0.1, green: 0.7, blue: 0.2, alpha: 1)
        pump(app, for: 0.6)
        check(near(sketch.paper, red: 0.1, green: 0.7, blue: 0.2), "the panel's color left the paper at \(sketch.paper)")
        check(sketch.ink == inkNow, "the paper's color reached the ink: \(sketch.ink)")

        window.makeFirstResponder(nil)
        send("undo:", to: window)
        pump(app, for: 0.4)
        check(near(sketch.paper, red: paperBefore.red, green: paperBefore.green, blue: paperBefore.blue),
              "undo left the paper at \(sketch.paper)")
        panel.orderOut(nil)
        return "moved clear of the list and wrote the ink, then the paper"
    }

    private static func near(_ color: NSColor, _ expected: Ollin.Color) -> Bool {
        guard let c = color.usingColorSpace(.sRGB) else { return false }
        return abs(c.redComponent - expected.red) < 0.02 && abs(c.greenComponent - expected.green) < 0.02
            && abs(c.blueComponent - expected.blue) < 0.02
    }

    private static func near(_ color: Ollin.Color, red: Double, green: Double, blue: Double) -> Bool {
        abs(color.red - red) < 0.02 && abs(color.green - green) < 0.02 && abs(color.blue - blue) < 0.02
    }

    // MARK: Events

    /// Send an action down the window's responder chain from its first
    /// responder, which is the route a menu item with no target takes.
    private static func send(_ action: String, to window: NSWindow) {
        let responder: NSResponder = window.firstResponder ?? window
        check(responder.tryToPerform(Selector(action), with: nil),
              "nothing in the window's responder chain answers \(action)")
    }

    private static func click(_ app: NSApplication, _ window: NSWindow, at point: NSPoint) {
        post(app, window, .leftMouseDown, at: point)
        post(app, window, .leftMouseUp, at: point)
        pump(app, for: 0.2)
    }

    private static func post(_ app: NSApplication, _ window: NSWindow, _ type: NSEvent.EventType,
                             at screenPoint: NSPoint) {
        let local = window.convertPoint(fromScreen: screenPoint)
        guard let event = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 1, clickCount: 1, pressure: 1) else {
            fail("could not make a \(type) event")
        }
        app.postEvent(event, atStart: false)
    }

    private static func key(_ app: NSApplication, _ window: NSWindow, _ characters: String,
                            code: UInt16, flags: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil,
                                               characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: code) else {
                fail("could not make a key event for \(characters)")
            }
            // Key events go to the window itself: the application routes them
            // to its key window, and a window with no screen to be key on has
            // none, while the window routes them to its first responder.
            window.sendEvent(event)
        }
        pump(app, for: 0.05)
    }

    /// Run the application's own event loop for a while, dispatching what
    /// was posted and letting SwiftUI lay out and settle. The windows are
    /// told to update after each event, as the application's own loop tells
    /// them, which is what anything watching for that hears.
    private static func pump(_ app: NSApplication, for seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let event = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02),
                                         inMode: .default, dequeue: true) {
                app.sendEvent(event)
                app.updateWindows()
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    // MARK: Views

    /// The first view under `root` whose class name contains `name`.
    private static func view(named name: String, under root: NSView) -> NSView? {
        views(named: name, under: root).first
    }

    /// Every view under `root` whose class name contains `name`, top to
    /// bottom as the list lays them out.
    private static func views(named name: String, under root: NSView) -> [NSView] {
        var pending: [NSView] = [root]
        var found: [NSView] = []
        while let next = pending.popLast() {
            if String(describing: type(of: next)).contains(name) { found.append(next) }
            pending.append(contentsOf: next.subviews.reversed())
        }
        return found.sorted { screenFrame(of: $0).maxY > screenFrame(of: $1).maxY }
    }

    private static func popUps(under root: NSView) -> [NSPopUpButton] {
        var pending: [NSView] = [root]
        var found: [NSPopUpButton] = []
        while let next = pending.popLast() {
            if let popUp = next as? NSPopUpButton { found.append(popUp) }
            pending.append(contentsOf: next.subviews.reversed())
        }
        return found
    }

    private static func buttons(under root: NSView) -> [NSButton] {
        var pending: [NSView] = [root]
        var found: [NSButton] = []
        while let next = pending.popLast() {
            if let button = next as? NSButton { found.append(button) }
            pending.append(contentsOf: next.subviews.reversed())
        }
        return found
    }

    // MARK: The accessibility tree

    /// One element of the window's accessibility tree: what a control drawn
    /// by SwiftUI, with no view of its own, says it is and where it stands.
    struct Element {
        let role: String
        let label: String
        let title: String
        let value: String
        /// In screen coordinates.
        let frame: NSRect
    }

    /// Ask SwiftUI for its accessibility tree. It builds one only for a
    /// client that asked, and setting these two attributes on the application
    /// is how a client asks; without them the tree holds one node.
    private static func wakeAccessibility(_ app: NSApplication) {
        for name in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            app.accessibilitySetValue(NSNumber(value: true), forAttribute: NSAccessibility.Attribute(rawValue: name))
        }
    }

    /// Every element under `root`, parents before children.
    private static func elements(under root: NSObject) -> [Element] {
        func read(_ object: NSObject, _ key: String) -> Any? {
            object.responds(to: Selector(key)) ? object.value(forKey: key) : nil
        }
        func text(_ any: Any?) -> String {
            switch any {
            case let attributed as NSAttributedString: return attributed.string
            case let string as String: return string
            case let number as NSNumber: return number.stringValue
            default: return ""
            }
        }
        var found: [Element] = []
        var pending: [NSObject] = [root]
        while let next = pending.popLast() {
            found.append(Element(role: text(read(next, "accessibilityRole")),
                                 label: text(read(next, "accessibilityLabel")),
                                 title: text(read(next, "accessibilityTitle")),
                                 value: text(read(next, "accessibilityValue")),
                                 frame: (read(next, "accessibilityFrame") as? NSValue)?.rectValue ?? .zero))
            let children = (read(next, "accessibilityChildren") as? [Any]) ?? []
            pending.append(contentsOf: children.reversed().compactMap { $0 as? NSObject })
        }
        return found
    }

    private static func element(_ role: String, labeled label: String? = nil, in window: NSWindow) -> Element? {
        elements(under: window.contentView!).first { $0.role == role && (label == nil || $0.label == label) }
    }

    /// Click the button SwiftUI drew under `label`, where the tree says it is.
    private static func press(_ label: String, _ app: NSApplication, _ window: NSWindow) {
        guard let button = element("AXButton", labeled: label, in: window) else {
            let all = elements(under: window.contentView!).filter { $0.role == "AXButton" }.map(\.label)
            fail("no button reads \(label); the buttons read \(all)")
        }
        click(app, window, at: NSPoint(x: button.frame.midX, y: button.frame.midY))
    }

    /// The class of every view under `root`, for a failure's sentence.
    private static func classes(under root: NSView) -> [String] {
        var pending: [NSView] = [root]
        var seen: [String] = []
        while let next = pending.popLast() {
            seen.append(String(describing: type(of: next)))
            pending.append(contentsOf: next.subviews.reversed())
        }
        return seen
    }

    private static func screenFrame(of view: NSView) -> NSRect {
        guard let window = view.window else { fail("the view has no window") }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }

    // MARK: Reporting

    private static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition { fail(message()) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("inspectortest: \(message)\n".utf8))
        exit(1)
    }
}
