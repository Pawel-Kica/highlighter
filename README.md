# Highlighter

A tiny Mac menu bar app for drawing on your screen while you present.

I built it because I wanted Canva-style highlighting in Google Slides, and Slides only gives you a laser pointer. It does one thing and I'd like to keep it that way. It's omakase style, so if you'd like something changed, fork it or open an issue.

More about it at [pawelkica.com/highlighter](https://pawelkica.com/highlighter).

## How to use it

Press ⌘⌃⌥⇧1 to turn draw mode on. Your cursor turns into a pen and you can drag to draw on any screen. Your slides keep focus the whole time, so the clicker and arrow keys still work.

Press an arrow key, space, Page Up or Page Down and the drawings clear, but draw mode stays on. That way you can draw, go to the next slide, and draw again.

To stop, right-click, press 4, or press ⌘⌃⌥⇧1 again. That turns draw mode off and clears everything.

The pencil icon in the menu bar has the settings: color (ten colors plus rainbow), width (3, 6, 12 or 26 px) and opacity (50, 85 or 100%). The app remembers them. Default is blue, 6 px, 100%.

A note on the hotkey. ⌘⌃⌥⇧ is the "Hyper" key. I map Caps Lock to it with [Karabiner-Elements](https://karabiner-elements.pqrs.org), so for me it's just Caps Lock+1, and the menu hint says that. Without Karabiner you press all four modifiers plus 1. To pick a different shortcut, change the `RegisterEventHotKey` call in `registerHotKey()` in `main.swift` and rebuild. The stop key (4) and the clear keys are at the top of the same file.

## Install

You need macOS 13 or newer and the Xcode Command Line Tools (`xcode-select --install`). No Xcode project, the whole app is one Swift file.

```sh
git clone https://github.com/Pawel-Kica/highlighter.git
cd highlighter
./build.sh
open /Applications/Highlighter.app
```

`build.sh` compiles `main.swift` and puts the app in `/Applications`. To build it somewhere else, run `APP=~/Desktop/Highlighter.app ./build.sh`.

On first launch it asks for Accessibility. Allow it in System Settings > Privacy & Security > Accessibility. It only needs that to see the slide keys and the 4 key. Drawing and the hotkey work without it.

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
