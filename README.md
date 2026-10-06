# Highlighter

A tiny Mac menu bar app for drawing on your screen while you present.

I built it because I wanted Canva-style highlighting in Google Slides, and Slides only gives you a laser pointer. It does one thing and I'd like to keep it that way. It's omakase style, so if you'd like something changed, fork it or open an issue.

## How to use it

Press ⌘⌃⌥⇧1 to turn draw mode on. Your cursor turns into a pen and you can drag to draw on any screen. Your slides keep focus the whole time, so the clicker and arrow keys still work.

Press an arrow key, space, Page Up or Page Down and the drawings clear, but draw mode stays on. That way you can draw, go to the next slide, and draw again. C clears too, without changing the slide.

To stop, press X or Esc, or press ⌘⌃⌥⇧1 again. That turns draw mode off and clears everything.

Press A for the arrow tool. The cursor turns into an arrow and a drag draws one, from tail to tip. Press A again to get the pen back. The arrows you drew stay.

Press S to copy a screenshot of the screen your cursor is on, drawings included, to the clipboard. Draw mode turns off right after. Right-click does the same by default, the Right-click menu can switch it to another action.

While draw mode is on the app swallows C, X, S and A, so they won't type into whatever has focus. To change a shortcut, click it in the menu and press the new one (Esc cancels).

The pencil icon in the menu bar has the settings: color (ten colors plus rainbow), width (3, 6, 12 or 26 px) and opacity (50, 85 or 100%). The app remembers them. Default is blue, 6 px, 100%.

Two more settings are for arrows. "Default tool" picks whether draw mode starts with the pen or the arrow. "Arrow color" can give every arrow a new color: the first one takes your color, the next ones walk through the other seven (White, Black and Rainbow are skipped). That way you can say "the yellow arrow is this, the red one is that". Clearing starts the colors over.

A note on the hotkey. ⌘⌃⌥⇧ is the "Hyper" key. I map Caps Lock to it with [Karabiner-Elements](https://karabiner-elements.pqrs.org), so for me it's just Caps Lock+1, and the menu says that. Without Karabiner you press all four modifiers plus 1, or pick another shortcut in the menu. It needs a modifier, since it works everywhere. Esc and the slide keys are fixed, at the top of `main.swift`.

## Install

You need macOS 13 or newer and the Xcode Command Line Tools (`xcode-select --install`). No Xcode project, the whole app is one Swift file.

```sh
git clone https://github.com/Pawel-Kica/highlighter.git
cd highlighter
./build.sh
open /Applications/Highlighter.app
```

`build.sh` compiles `main.swift` and puts the app in `/Applications`. To build it somewhere else, run `APP=~/Desktop/Highlighter.app ./build.sh`.

On first launch it asks for Accessibility. Allow it in System Settings > Privacy & Security > Accessibility. It only needs that to see the slide keys and Esc. Drawing and the hotkey work without it.

The first time you press S, macOS asks for Screen Recording. Allow it and open the app again.

It also adds itself as a login item, so it starts with your Mac. You can turn that off in System Settings > General > Login Items.

The app is signed ad hoc, not notarized. If macOS blocks it the first time, go to System Settings > Privacy & Security and click Open Anyway.

Ad hoc signatures change on every build, so after a rebuild macOS will ask for Accessibility again. If you have a signing certificate, pass it in and the permission sticks:

```sh
SIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" ./build.sh
```

`security find-identity -v -p codesigning` lists the ones you have.

After a rebuild, restart the running copy with `pkill -x Highlighter; open /Applications/Highlighter.app`.

The icon comes from `make-icon.swift`. Run `swift make-icon.swift` to regenerate `AppIcon.icns`.

## License

MIT
