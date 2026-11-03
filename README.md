# kensington-orbit-remapper

Adds a **media mode** to the Kensington Orbit Fusion Wireless trackball on macOS. Hold **⌥ Option**
and the scroll ring and buttons control music and volume. Release it and everything works as before.

It runs on top of [KensingtonWorks](https://www.kensington.com/software/kensingtonworks/) using
[Hammerspoon](https://www.hammerspoon.org/). Your normal button setup in KensingtonWorks stays untouched.

| Control | Normal (KensingtonWorks) | ⌥ held (media mode) |
|---|---|---|
| Scroll ring | scroll | volume (down = louder; see `INVERT_SCROLL`) |
| Top side button | screenshot shortcut (⌘⇧2) | play / pause |
| Left side button | Mission Control (⌃↑) | previous track |
| Any left-click button | left click | next track |

The side-button rows match my KensingtonWorks setup. If yours sends different shortcuts, edit
`KW_BUTTONS` in `macos/init.lua` (see "Adding a button" below).

## How it works

```
 trackball ──► KensingtonWorks ──► Hammerspoon event taps ──► apps
               (normal mode)       ⌥ held → swallow the event,
                                   send a media key instead
```

1. **KensingtonWorks** turns physical buttons into events. Some become clicks; side buttons can
   become **fake keystrokes**, e.g. Mission Control = ⌃↑.
2. **Hammerspoon** installs *event taps*: hooks that see every input event before apps do, and
   can let it through, change it, or swallow it. Hammerspoon needs Accessibility permission for this.
3. While ⌥ is held, the taps swallow:
   - scroll events, sending volume up/down instead (throttled so one notch ≠ ten steps),
   - left clicks (the whole click, including drag and release), sending next track,
   - the fake keystrokes from the side buttons, sending play/pause or previous track.
4. Media keys are sent as *system key events*, the same thing the keyboard's ⏯ / 🔊 keys send, so
   they control whatever is playing (Spotify, Music, a browser tab, …).

Gotchas this code handles:
- **KensingtonWorks strips ⌥** from the keystrokes it fakes, so the code tracks the physical ⌥ key
  itself. A keystroke that arrives while ⌥ is held but has no ⌥ flag came from KensingtonWorks.
  A real ⌥⌘⇧2 typed on the keyboard keeps its ⌥ flag and passes through.
- **Apps can remap modifiers.** iTerm2's "Remap Modifiers" swaps ⌘/⌃ even for fake keystrokes,
  so ⌘ and ⌃ are treated as interchangeable when matching side buttons.
- **⌥ is removed from the media keys sent.** Otherwise ⌥+🔊 opens Sound settings.
- Hammerspoon sees what KensingtonWorks *sends*, not physical buttons. Buttons set to the same
  action (e.g. two "Left Click" buttons) behave the same in media mode.
- Trade-off: ⌥+click and ⌥+scroll are taken over everywhere (e.g. ⌥-drag to copy in Finder).

## Install (macOS)

```bash
brew install --cask hammerspoon
git clone https://github.com/AAlvz/kensington-orbit-remapper.git
ln -s "$PWD/kensington-orbit-remapper/macos/init.lua" ~/.hammerspoon/init.lua
```

Open Hammerspoon. Grant Accessibility (System Settings → Privacy & Security → Accessibility) and
turn on "Launch at login".

If you already have a `~/.hammerspoon/init.lua`, add `dofile("/path/to/macos/init.lua")` to it instead.

## Changing things

Edit `macos/init.lua`, then reload with 🔨 menu bar icon → **Reload Config**, or
`hs -c "hs.reload()"`. A "Orbit remapper loaded" message confirms it. If something breaks,
🔨 → **Console** shows the Lua error.

- **Scroll direction:** `INVERT_SCROLL = true/false`.
- **Volume speed:** `SCROLL_GAP` sets the seconds between steps. Lower is faster.
- **Swap actions:** change the `media = "…"` values or `CLICK_MEDIA`. Available keys include
  `SOUND_UP/DOWN`, `MUTE`, `PLAY`, `NEXT`, `PREVIOUS`, `FAST`, `REWIND`, `BRIGHTNESS_UP/DOWN`.
- **Adding a button** (a KensingtonWorks shortcut): set `LOG_EVENTS = true`, reload, and press
  the button. Open `~/.hammerspoon/orbit-remapper-events.log`, note its keycode and flags, and add
  a line to `KW_BUTTONS`. Set `LOG_EVENTS` back to `false`. The logger never records plain typing.
- **Anything else** (another modifier, app launching, window moves, …): add a handler that checks
  the condition, does the action, and returns `true` to swallow the original event.

## Other OSes (not done)

- Windows: AutoHotkey, e.g. `!WheelUp::Send {Volume_Up}`.
- Linux: `input-remapper` (works on X11 and Wayland).

## License

GPL-3.0
