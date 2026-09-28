import AppKit
import ServiceManagement

// Highlighter: hold Hyper (Caps Lock via Karabiner = ⌘⌃⌥⇧) and drag to draw on any screen.
// Strokes fade on their own. Settings live in the menu bar item and persist in UserDefaults.
// Menu bar only (no Dock icon), registers itself as a login item on first launch.
// No permissions needed: modifiers are polled, and a transparent overlay only takes the mouse while Hyper is held.

let hyper: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
let fadeDuration = 0.4
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
    static var hold: Double { get { value("hold", 1) } set { UserDefaults.standard.set(newValue, forKey: "hold") } }

    private static func value(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }
}

// One freehand stroke. Captures the settings at the moment it starts.
final class Stroke {
    var points: [CGPoint]
    let color = palette.first { $0.name == Settings.color }?.color
    let width = Settings.width, opacity = Settings.opacity, hold = Settings.hold
    var done: Date?

    init(at p: CGPoint) { points = [p] }

    // Current alpha, or nil once fully faded.
    func alpha(at now: Date) -> Double? {
        guard let done else { return opacity }
        let age = now.timeIntervalSince(done)
        if age < hold { return opacity }
        let t = (age - hold) / fadeDuration
        return t >= 1 ? nil : opacity * (1 - t)
    }
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

    override func mouseUp(with e: NSEvent) { finishStroke() }

    func finishStroke() {
        current?.done = Date()
        current = nil
    }

    // Called every frame: drops faded strokes and redraws while anything is visible.
    func tick(_ now: Date) {
        guard !strokes.isEmpty else { return }
        strokes.removeAll { $0.alpha(at: now) == nil }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let now = Date()
        for s in strokes {
            guard let alpha = s.alpha(at: now) else { continue }
            ctx.saveGState()
            ctx.setAlpha(alpha)
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

final class App: NSObject, NSApplicationDelegate {
    var overlays: [Overlay] = []
    var drawing = false
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func applicationDidFinishLaunching(_ n: Notification) {
        buildOverlays()
        refreshMenu()
        if SMAppService.mainApp.status == .notRegistered { try? SMAppService.mainApp.register() }
        NotificationCenter.default.addObserver(self, selector: #selector(buildOverlays),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let timer = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common) // .common keeps it running while the menu is open
    }

    @objc func buildOverlays() {
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map { Overlay(screen: $0) }
        drawing = false
    }

    @objc func tick() {
        let held = NSEvent.modifierFlags.isSuperset(of: hyper)
        if held != drawing {
            drawing = held
            for o in overlays {
                o.ignoresMouseEvents = !held
                // macOS passes clicks through fully transparent pixels, so tint invisibly while drawing.
                o.backgroundColor = held ? NSColor(white: 0, alpha: 0.001) : .clear
                if !held { o.view.finishStroke() } // key released mid-drag
            }
        }
        let now = Date()
        overlays.forEach { $0.view.tick(now) }
    }

    func refreshMenu() {
        item.button?.image = dotImage(Settings.color)
        let menu = NSMenu()
        let hint = NSMenuItem(title: "Hold Caps Lock and drag to draw", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(group("Color", palette.map { p in (p.name, Settings.color == p.name, { Settings.color = p.name }) }, swatches: true))
        menu.addItem(group("Width", [3.0, 6, 12, 26].map { w in ("\(Int(w)) px", Settings.width == w, { Settings.width = w }) }))
        menu.addItem(group("Opacity", [0.5, 0.85, 1].map { o in ("\(Int(o * 100))%", Settings.opacity == o, { Settings.opacity = o }) }))
        menu.addItem(group("Fade after", [0.5, 1, 1.5, 3].map { h in ("\(h.formatted()) s", Settings.hold == h, { Settings.hold = h }) }))
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

    // A dot in the named palette color: the menu bar icon and the Color swatches.
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
                NSGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .magenta])?.draw(in: dot, angle: 0)
            }
            return true
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
