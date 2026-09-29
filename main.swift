import AppKit
import Carbon
import ServiceManagement

// Highlighter: Hyper+1 (Caps Lock via Karabiner = ⌘⌃⌥⇧) toggles draw mode, then plain drag draws on any screen.
// Strokes stay until a slide key (arrows, space, Page Up/Down) clears them. Right-click, 4 (with or without
// Hyper) or Hyper+1 again turns draw mode off and clears.
// Settings live in the menu bar item and persist in UserDefaults.
// Menu bar only (no Dock icon), registers itself as a login item on first launch.
// Hyper+1 is a Carbon hotkey. Only the slide-key watcher needs Accessibility.

let clearKeys: Set<UInt16> = [123, 124, 125, 126, 49, 116, 121] // ← → ↓ ↑ space PageUp PageDown
let stopKey: UInt16 = 21 // 4, any modifiers
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

    private static func value(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }
}

// One freehand stroke. Captures the settings at the moment it starts.
final class Stroke {
    var points: [CGPoint]
    let color = palette.first { $0.name == Settings.color }?.color
    let width = Settings.width, opacity = Settings.opacity

    init(at p: CGPoint) { points = [p] }
}

final class OverlayView: NSView {
    var strokes: [Stroke] = []
    var current: Stroke?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) {
        let s = Stroke(at: convert(e.locationInWindow, from: nil))
        strokes.append(s)
        current = s
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        current?.points.append(convert(e.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) { current = nil }

    // Right-click turns draw mode off, which clears every screen. Only reachable while draw mode is on.
    override func rightMouseDown(with e: NSEvent) { (NSApp.delegate as? App)?.toggleDrawMode() }

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
            if let color = s.color {
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
    var pen = NSCursor.arrow
    var hotKey: EventHotKeyRef?
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
        registerHotKey()
        watchSlideKeys()
    }

    @objc func buildOverlays() {
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map { Overlay(screen: $0) }
        drawMode = false
    }

    // Hyper+1 toggles draw mode.
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            (NSApp.delegate as? App)?.toggleDrawMode()
            return noErr
        }, 1, &spec, nil, nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_1), UInt32(cmdKey | controlKey | optionKey | shiftKey),
                            EventHotKeyID(signature: 0x484C_4954, id: 1), GetApplicationEventTarget(), 0, &hotKey)
    }

    // On: overlays take the mouse. Off: clicks go through again and everything is cleared.
    func toggleDrawMode() {
        drawMode.toggle()
        for o in overlays {
            o.ignoresMouseEvents = !drawMode
            // macOS passes clicks through fully transparent pixels, so tint invisibly while drawing.
            o.backgroundColor = drawMode ? NSColor(white: 0, alpha: 0.001) : .clear
        }
        if !drawMode {
            clearAll()
            NSCursor.arrow.set()
        }
    }

    func clearAll() { overlays.forEach { $0.view.clear() } }

    // Slide keys clear all strokes, 4 turns draw mode off. Watching global keys needs Accessibility: asks once,
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
        if drawMode { pen.set() }
    }

    func refreshMenu() {
        pen = penCursor(Settings.color)
        let menu = NSMenu()
        for text in ["Caps Lock+1: draw mode, slide keys clear", "Right-click or 4: stop drawing and clear"] {
            let hint = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        menu.addItem(.separator())
        menu.addItem(group("Color", palette.map { p in (p.name, Settings.color == p.name, { Settings.color = p.name }) }, swatches: true))
        menu.addItem(group("Width", [3.0, 6, 12, 26].map { w in ("\(Int(w)) px", Settings.width == w, { Settings.width = w }) }))
        menu.addItem(group("Opacity", [0.5, 0.85, 1].map { o in ("\(Int(o * 100))%", Settings.opacity == o, { Settings.opacity = o }) }))
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

    // SF pencil in the named palette color with a dark outline. Hotspot is the tip (bottom left).
    func penCursor(_ name: String) -> NSCursor {
        let symbol = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)!
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
        // The tip sits about 2 pt in and 2 pt up from the glyph's bottom-left corner (hotspot is top-left based).
        return NSCursor(image: image, hotSpot: NSPoint(x: pad + 2, y: size.height - pad - 2))
    }
}

let rainbow = NSGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .magenta])!

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
