import AppKit
import Carbon
import ServiceManagement

// Highlighter: Hyper+1 (Caps Lock via Karabiner = ⌘⌃⌥⇧) toggles draw mode, then plain drag draws on any screen.
// Strokes stay until C or a slide key (arrows, space, Page Up/Down) clears them. X, Esc or Hyper+1 again
// turns draw mode off and clears. S copies a screenshot of the screen under the cursor, then does the same.
// A switches between the pen and the arrow tool (drag from tail to tip). Right-click runs one of these.
// Settings, shortcuts and the right-click action live in the menu bar item and persist in UserDefaults.
// Menu bar only (no Dock icon), registers itself as a login item on first launch.
// The shortcuts are Carbon hotkeys, so the app underneath never sees them. All but Draw mode are only
// registered while drawing.
// The slide-key watcher needs Accessibility, the screenshot needs Screen Recording.

// A key plus Carbon modifiers, with the text the menu shows for it.
struct Shortcut: Codable { var code: Int; var mods: Int; var label: String }

// What shortcuts can do, in menu order, with Carbon hotkey ids and default keys. Right-click can run all but Draw mode.
let actions: [(id: UInt32, name: String, key: Shortcut)] = [
    (1, "Draw mode", Shortcut(code: kVK_ANSI_1, mods: cmdKey | controlKey | optionKey | shiftKey, label: "Caps Lock+1")),
    (2, "Clear", Shortcut(code: kVK_ANSI_C, mods: 0, label: "C")),
    (5, "Switch pen/arrow", Shortcut(code: kVK_ANSI_A, mods: 0, label: "A")),
    (4, "Screenshot", Shortcut(code: kVK_ANSI_S, mods: 0, label: "S")),
    (3, "Stop drawing", Shortcut(code: kVK_ANSI_X, mods: 0, label: "X")),
]
let clearKeys: Set<UInt16> = [123, 124, 125, 126, 49, 116, 121] // ← → ↓ ↑ space PageUp PageDown
let stopKey: UInt16 = 53 // Esc
let rainbowLength: CGFloat = 500 // stroke length (pt) for one full hue cycle

// nil color = rainbow
let palette: [(name: String, color: NSColor?)] = [
    ("Red", NSColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 1)),
    ("Orange", NSColor(srgbRed: 1, green: 0.584, blue: 0, alpha: 1)),
    ("Yellow", NSColor(srgbRed: 1, green: 0.882, blue: 0.302, alpha: 1)),
    ("Green", NSColor(srgbRed: 0.486, green: 0.988, blue: 0, alpha: 1)),
    ("Teal", NSColor(srgbRed: 0.188, green: 0.835, blue: 0.784, alpha: 1)),
    ("Blue", NSColor(srgbRed: 0.239, green: 0.698, blue: 1, alpha: 1)),
    ("Purple", NSColor(srgbRed: 0.686, green: 0.322, blue: 0.871, alpha: 1)),
    ("Pink", NSColor(srgbRed: 1, green: 0.369, blue: 0.769, alpha: 1)),
    ("White", NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)),
    ("Black", NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)),
    ("Rainbow", nil),
]

enum Settings {
    static var color: String {
        get { UserDefaults.standard.string(forKey: "color") ?? "Blue" }
        set { UserDefaults.standard.set(newValue, forKey: "color") }
    }
    static var width: Double { get { value("width", 6) } set { UserDefaults.standard.set(newValue, forKey: "width") } }
    static var opacity: Double { get { value("opacity", 1) } set { UserDefaults.standard.set(newValue, forKey: "opacity") } }
    // Draw mode starts with the arrow tool, not the pen.
    static var arrowTool: Bool {
        get { UserDefaults.standard.bool(forKey: "arrowTool") }
        set { UserDefaults.standard.set(newValue, forKey: "arrowTool") }
    }
    // Every arrow takes the next palette color, not the pen color.
    static var arrowColors: Bool {
        get { UserDefaults.standard.bool(forKey: "arrowColors") }
        set { UserDefaults.standard.set(newValue, forKey: "arrowColors") }
    }
    // What right-click does in draw mode, an action name.
    static var rightClick: String {
        get { UserDefaults.standard.string(forKey: "rightClick") ?? "Screenshot" }
        set { UserDefaults.standard.set(newValue, forKey: "rightClick") }
    }

    // The action's shortcut picked in the menu, its default otherwise.
    static func shortcut(_ action: String) -> Shortcut {
        if let data = UserDefaults.standard.data(forKey: "shortcut " + action),
           let s = try? JSONDecoder().decode(Shortcut.self, from: data) { return s }
        return actions.first { $0.name == action }!.key
    }
    static func setShortcut(_ action: String, _ s: Shortcut) {
        UserDefaults.standard.set(try? JSONEncoder().encode(s), forKey: "shortcut " + action)
    }

    private static func value(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }
}

// One freehand stroke, or one arrow whose points are tail and tip. Captures the settings at the moment it starts.
final class Stroke {
    var points: [CGPoint]
    let arrow: Bool
    let color: NSColor? // nil = rainbow
    let width = Settings.width, opacity = Settings.opacity

    init(at p: CGPoint, arrow: Bool, color: String) {
        points = [p]
        self.arrow = arrow
        self.color = palette.first { $0.name == color }?.color
    }
}

final class OverlayView: NSView {
    var strokes: [Stroke] = []
    var current: Stroke?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) {
        guard let app = NSApp.delegate as? App else { return }
        let s = Stroke(at: convert(e.locationInWindow, from: nil), arrow: app.arrowTool, color: app.nextColor)
        strokes.append(s)
        current = s
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        guard let s = current else { return }
        let p = convert(e.locationInWindow, from: nil)
        if s.arrow { s.points = [s.points[0], p] } else { s.points.append(p) }
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        // A click without a drag leaves no arrow and doesn't use up a color.
        if let s = current, s.arrow {
            if s.points.count == 2 { (NSApp.delegate as? App)?.arrowDrawn() } else { strokes.removeAll { $0 === s } }
        }
        current = nil
    }

    // Only reachable while draw mode is on.
    override func rightMouseDown(with e: NSEvent) { (NSApp.delegate as? App)?.run(Settings.rightClick) }

    func clear() {
        strokes = []
        current = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        for s in strokes {
            ctx.saveGState()
            ctx.setAlpha(s.opacity)
            // Transparency layer so overlapping parts of one stroke don't stack up.
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.setLineWidth(s.width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            var prev = s.points[0]
            if s.arrow {
                drawArrow(s)
            } else if let color = s.color {
                ctx.setStrokeColor(color.cgColor)
                ctx.move(to: prev)
                for p in s.points { ctx.addLine(to: CGPoint(x: p.x + 0.01, y: p.y)) }
                ctx.strokePath()
            } else {
                // Rainbow: hue follows distance traveled along the stroke.
                var dist: CGFloat = 0
                for p in s.points {
                    dist += hypot(p.x - prev.x, p.y - prev.y)
                    let hue = (dist / rainbowLength).truncatingRemainder(dividingBy: 1)
                    ctx.setStrokeColor(NSColor(hue: hue, saturation: 0.9, brightness: 1, alpha: 1).cgColor)
                    ctx.move(to: prev)
                    ctx.addLine(to: CGPoint(x: p.x + 0.01, y: p.y))
                    ctx.strokePath()
                    prev = p
                }
            }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }

    // Tapered arrow as one filled shape: thin at the tail, growing into the head. Size follows the stroke width.
    func drawArrow(_ s: Stroke) {
        guard s.points.count == 2 else { return }
        let a = s.points[0], b = s.points[1], w = s.width, len = hypot(b.x - a.x, b.y - a.y)
        guard len > 1 else { return }
        let u = CGPoint(x: (b.x - a.x) / len, y: (b.y - a.y) / len), n = CGPoint(x: -u.y, y: u.x)
        let head = min(10 + w * 3, len * 0.6), base = CGPoint(x: b.x - u.x * head, y: b.y - u.y * head)
        func at(_ p: CGPoint, _ d: CGFloat) -> CGPoint { CGPoint(x: p.x + n.x * d, y: p.y + n.y * d) }
        let path = NSBezierPath()
        path.move(to: at(a, w * 0.15))
        for p in [at(base, w * 0.5), at(base, head * 0.5), b, at(base, -head * 0.5), at(base, -w * 0.5), at(a, -w * 0.15)] {
            path.line(to: p)
        }
        path.close()
        if let color = s.color {
            color.set()
            path.fill()
            path.lineWidth = w * 0.3 // rounds the corners
            path.lineJoinStyle = .round
            path.stroke()
        } else {
            rainbow.draw(in: path, angle: atan2(b.y - a.y, b.x - a.x) * 180 / .pi)
        }
    }
}

// Transparent, click-through window covering one screen, above fullscreen apps. Never takes focus.
final class Overlay: NSPanel {
    let view = OverlayView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = view
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
}

// Menu item that runs a closure.
final class ActionItem: NSMenuItem {
    let run: () -> Void

    init(_ title: String, checked: Bool, image: NSImage? = nil, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
        self.image = image
    }

    required init(coder: NSCoder) { fatalError() }

    @objc func fire() { run() }
}

// Private CoreGraphics call that lets a background app set the cursor (we never take focus from the slides).
@_silgen_name("_CGSDefaultConnection") func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSSetConnectionProperty")
func CGSSetConnectionProperty(_ cid: Int32, _ target: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32

final class App: NSObject, NSApplicationDelegate {
    var overlays: [Overlay] = []
    var drawMode = false // toggled by Hyper+1, overlay takes the mouse
    var arrowTool = false // A switches pen and arrow, draw mode starts with Settings.arrowTool
    var arrowCount = 0 // arrows drawn since the last clear, picks the next arrow color
    var cursor = NSCursor.arrow // pen or arrow glyph in the color of the next stroke
    var hotKey: EventHotKeyRef? // Draw mode
    var drawHotKeys: [EventHotKeyRef?] = [] // the other shortcuts, registered only in draw mode
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func applicationDidFinishLaunching(_ n: Notification) {
        buildOverlays()
        // Filled circle with a pen tip, sized to match other menu bar icons. Template, so it follows light/dark.
        item.button?.image = NSImage(systemSymbolName: "pencil.tip.crop.circle.fill", accessibilityDescription: "Highlighter")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        refreshMenu()
        if SMAppService.mainApp.status == .notRegistered { try? SMAppService.mainApp.register() }
        NotificationCenter.default.addObserver(self, selector: #selector(buildOverlays),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let timer = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common) // .common keeps it running while the menu is open
        let cid = _CGSDefaultConnection()
        _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        handleHotKeys()
        registerDrawModeKey()
        watchSlideKeys()
    }

    @objc func buildOverlays() {
        if drawMode { toggleDrawMode() }
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map { Overlay(screen: $0) }
    }

    // Runs the action whose hotkey id fired, see actions.
    func handleHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var key = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &key)
            if let a = actions.first(where: { $0.id == key.id }) { (NSApp.delegate as? App)?.run(a.name) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    // The Draw mode shortcut is registered all the time, the rest only while drawing (toggleDrawMode).
    func registerDrawModeKey() {
        let k = Settings.shortcut("Draw mode")
        RegisterEventHotKey(UInt32(k.code), UInt32(k.mods), EventHotKeyID(signature: 0x484C_4954, id: 1),
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    // On: overlays take the mouse, the other shortcuts become hotkeys, the tool is the default one.
    // Off: clicks and keys go through again, everything is cleared.
    func toggleDrawMode() {
        drawMode.toggle()
        for o in overlays {
            o.ignoresMouseEvents = !drawMode
            // macOS passes clicks through fully transparent pixels, so tint invisibly while drawing.
            o.backgroundColor = drawMode ? NSColor(white: 0, alpha: 0.001) : .clear
        }
        if drawMode {
            arrowTool = Settings.arrowTool
            updateCursor()
            for a in actions.dropFirst() {
                let k = Settings.shortcut(a.name)
                var ref: EventHotKeyRef?
                RegisterEventHotKey(UInt32(k.code), UInt32(k.mods), EventHotKeyID(signature: 0x484C_4954, id: a.id),
                                    GetApplicationEventTarget(), 0, &ref)
                drawHotKeys.append(ref)
            }
        } else {
            drawHotKeys.forEach { UnregisterEventHotKey($0) }
            drawHotKeys = []
            clearAll()
            NSCursor.arrow.set()
        }
    }

    // Also starts the arrow colors over.
    func clearAll() {
        overlays.forEach { $0.view.clear() }
        if arrowCount != 0 {
            arrowCount = 0
            updateCursor()
        }
    }

    // Runs an action by name, from a shortcut or right-click.
    func run(_ action: String) {
        switch action {
        case "Clear": clearAll()
        case "Switch pen/arrow": toggleTool()
        case "Screenshot": screenshot()
        default: toggleDrawMode() // Draw mode, Stop drawing
        }
    }

    // Waits in a small alert for the next key press and saves it as the action's shortcut. Esc cancels.
    // Draw mode needs a modifier: it is registered all the time and would swallow a plain key everywhere.
    func record(_ action: String) {
        if drawMode { toggleDrawMode() }
        UnregisterEventHotKey(hotKey) // so the current Draw mode shortcut gets recorded, not run
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Press the new shortcut for \(action)"
        alert.informativeText = "Esc cancels."
        alert.addButton(withTitle: "Cancel")
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = carbonMods(e.modifierFlags)
            if e.keyCode == stopKey {
                NSApp.stopModal()
            } else if action == "Draw mode", mods == 0 {
                NSSound.beep()
            } else {
                Settings.setShortcut(action, Shortcut(code: Int(e.keyCode), mods: mods, label: keyLabel(e, mods)))
                NSApp.stopModal()
            }
            return nil
        }
        alert.runModal()
        alert.window.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        previous?.activate()
        registerDrawModeKey()
        refreshMenu()
    }

    // A: pen to arrow and back. Drawings stay.
    func toggleTool() {
        arrowTool.toggle()
        updateCursor()
    }

    // Color name for the next stroke. With Settings.arrowColors, arrows walk the palette colors without
    // White, Black and Rainbow, starting at the chosen one (at Red if it is one of those three).
    var nextColor: String {
        guard arrowTool, Settings.arrowColors else { return Settings.color }
        let colors = palette.filter { $0.color != nil && !["White", "Black"].contains($0.name) }.map(\.name)
        return colors[((colors.firstIndex(of: Settings.color) ?? 0) + arrowCount) % colors.count]
    }

    // Called by the overlay when an arrow is finished.
    func arrowDrawn() {
        arrowCount += 1
        updateCursor()
    }

    func updateCursor() { cursor = toolCursor(arrowTool ? "arrow.up.right" : "pencil", nextColor) }

    // Copies the screen under the cursor, drawings included, to the clipboard, then turns draw mode off.
    // Needs Screen Recording, macOS asks on first use.
    func screenshot() {
        let mouse = NSEvent.mouseLocation
        guard let f = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.screens.first)?.frame else { return }
        // screencapture measures from the top left of the primary screen, AppKit from its bottom left.
        let top = NSScreen.screens[0].frame.maxY - f.maxY
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-c", "-R\(Int(f.minX)),\(Int(top)),\(Int(f.width)),\(Int(f.height))"]
        // Stop only once the capture is done, so the drawings are still in it.
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { if self?.drawMode == true { self?.toggleDrawMode() } }
        }
        try? task.run()
    }

    // Slide keys clear all strokes, Esc turns draw mode off. Watching global keys needs Accessibility: asks once,
    // then waits for the grant (signed with a stable certificate, so it survives rebuilds).
    func watchSlideKeys() {
        let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard AXIsProcessTrusted() else { return }
            t.invalidate()
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { e in
                if clearKeys.contains(e.keyCode) { self?.clearAll() }
                if e.keyCode == stopKey, self?.drawMode == true { self?.toggleDrawMode() }
            }
        }
        if trusted { timer.fire() }
    }

    // Every frame in draw mode, the app underneath may reset the cursor.
    @objc func tick() {
        if drawMode { cursor.set() }
    }

    func refreshMenu() {
        updateCursor()
        let menu = NSMenu()
        let hint = NSMenuItem(title: "Shortcuts, click one to change it", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        for a in actions {
            menu.addItem(ActionItem("\(a.name): \(Settings.shortcut(a.name).label)", checked: false) { [weak self] in self?.record(a.name) })
        }
        menu.addItem(group("Right-click", actions.dropFirst().map { a in
            (a.name, Settings.rightClick == a.name, { Settings.rightClick = a.name })
        }))
        menu.addItem(.separator())
        menu.addItem(group("Color", palette.map { p in (p.name, Settings.color == p.name, { Settings.color = p.name }) }, swatches: true))
        menu.addItem(group("Width", [3.0, 6, 12, 26].map { w in ("\(Int(w)) px", Settings.width == w, { Settings.width = w }) }))
        menu.addItem(group("Opacity", [0.5, 0.85, 1].map { o in ("\(Int(o * 100))%", Settings.opacity == o, { Settings.opacity = o }) }))
        menu.addItem(group("Default tool", [("Pen", !Settings.arrowTool, { Settings.arrowTool = false }),
                                            ("Arrow", Settings.arrowTool, { Settings.arrowTool = true })]))
        menu.addItem(group("Arrow color", [("Same as pen", !Settings.arrowColors, { Settings.arrowColors = false }),
                                           ("New color each arrow", Settings.arrowColors, { Settings.arrowColors = true })]))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    // Submenu of checkable options; picking one saves it and rebuilds the menu.
    func group(_ title: String, _ options: [(String, Bool, () -> Void)], swatches: Bool = false) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (name, checked, set) in options {
            let image = swatches ? dotImage(name) : nil
            sub.addItem(ActionItem(name, checked: checked, image: image) { [weak self] in set(); self?.refreshMenu() })
        }
        parent.submenu = sub
        return parent
    }

    // A dot in the named palette color: the Color swatches.
    func dotImage(_ name: String) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let dot = NSBezierPath(ovalIn: r.insetBy(dx: 3, dy: 3))
            if let color = palette.first(where: { $0.name == name })?.color {
                color.setFill()
                dot.fill()
                NSColor.gray.setStroke() // keeps White and Black visible on any menu bar
                dot.lineWidth = 0.5
                dot.stroke()
            } else {
                rainbow.draw(in: dot, angle: 0)
            }
            return true
        }
    }

    // SF symbol (pencil or arrow.up.right) in the named palette color with a dark outline. Hotspot is the
    // bottom left: the pencil's tip, the arrow's tail.
    func toolCursor(_ symbolName: String, _ name: String) -> NSCursor {
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 20, weight: .medium))!
        let pad: CGFloat = 2
        let glyph = NSRect(x: pad, y: pad, width: symbol.size.width, height: symbol.size.height)
        let size = NSSize(width: glyph.width + 2 * pad, height: glyph.height + 2 * pad)
        // The symbol drawn as a mask, filled with a color or the rainbow gradient.
        func tinted(_ fill: @escaping (NSRect) -> Void) -> NSImage {
            NSImage(size: size, flipped: false) { r in
                symbol.draw(in: glyph)
                NSGraphicsContext.current?.compositingOperation = .sourceAtop
                fill(r)
                return true
            }
        }
        let outline = tinted { NSColor.black.setFill(); $0.fill(using: .sourceAtop) }
        let body = tinted { r in
            if let color = palette.first(where: { $0.name == name })?.color { color.setFill(); r.fill(using: .sourceAtop) }
            else { rainbow.draw(in: r, angle: 45) }
        }
        let image = NSImage(size: size, flipped: false) { r in
            for dx in [-1.2, 0, 1.2] { for dy in [-1.2, 0, 1.2] { outline.draw(in: r.offsetBy(dx: dx, dy: dy)) } }
            body.draw(in: r)
            return true
        }
        // It sits about 2 pt in and 2 pt up from the glyph's bottom-left corner (hotspot is top-left based).
        return NSCursor(image: image, hotSpot: NSPoint(x: pad + 2, y: size.height - pad - 2))
    }
}

let rainbow = NSGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .magenta])!

// NSEvent modifier flags as Carbon hotkey modifiers.
func carbonMods(_ f: NSEvent.ModifierFlags) -> Int {
    (f.contains(.command) ? cmdKey : 0) | (f.contains(.control) ? controlKey : 0) |
        (f.contains(.option) ? optionKey : 0) | (f.contains(.shift) ? shiftKey : 0)
}

// Menu text for a key press: "Caps Lock+" for all four modifiers (Hyper), else the ⌃⌥⇧⌘ symbols, then the key.
func keyLabel(_ e: NSEvent, _ mods: Int) -> String {
    let names: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
    let key = names[e.keyCode] ?? e.characters(byApplyingModifiers: [])?.uppercased() ?? "?"
    if mods == cmdKey | controlKey | optionKey | shiftKey { return "Caps Lock+" + key }
    return [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")].filter { mods & $0.0 != 0 }.map(\.1).joined() + key
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
