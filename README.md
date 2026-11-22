# kensington-orbit-remapper

Adds a **media mode** to the Kensington Orbit Fusion Wireless trackball on macOS and Windows. Hold **⌥ Option** (Alt on Windows)
and the scroll ring and buttons control music and volume. Release it and everything works as before.

It runs on top of **Kensington Konnect** (the app formerly called KensingtonWorks) using
[Hammerspoon](https://www.hammerspoon.org/). Your normal button setup in Konnect stays untouched.

| Control | Normal (Konnect) | ⌥ held (media mode) |
|---|---|---|
| Scroll ring | scroll | volume (down = louder; see `INVERT_SCROLL`) |
| Top side button | screenshot shortcut (⌘⇧2) | play / pause |
| Left side button | Mission Control (⌃↑) | previous track |
| Any left-click button | left click | next track |

Mouse only: **hold the middle-click button** and

| Then | Action |
|---|---|
| Roll left / right | previous / next desktop (sends the "Move left/right a space" shortcut) |
| Roll up / down | next / previous track |
| Right click | play / pause |
| Scroll ring | volume |
| Nothing (press and release) | normal middle click |

The side buttons only work in media mode if Konnect sends the matching shortcut for them (see
"Set up Konnect" below). If yours sends different shortcuts, edit `KONNECT_BUTTONS` in `macos/init.lua`
(see "Adding a button" below).

## How it works

```
 trackball ──► Konnect ──────────► Hammerspoon event taps ──► apps
               (normal mode)       ⌥ held → swallow the event,
                                   send a media key instead
```

1. **Konnect** turns physical buttons into events. Some become clicks; side buttons can
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
- **Konnect strips ⌥** from the keystrokes it fakes, so the code tracks the physical ⌥ key
  itself. A keystroke that arrives while ⌥ is held but has no ⌥ flag came from Konnect.
  A real ⌥⌘⇧2 typed on the keyboard keeps its ⌥ flag and passes through.
- **Apps can remap modifiers.** iTerm2's "Remap Modifiers" swaps ⌘/⌃ even for fake keystrokes,
  so ⌘ and ⌃ are treated as interchangeable when matching side buttons.
- **⌥ is removed from the media keys sent.** Otherwise ⌥+🔊 opens Sound settings.
- Hammerspoon sees what Konnect *sends*, not physical buttons. Buttons set to the same
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

### Set up Konnect

Scroll and click work with Konnect's defaults. The side buttons need a keyboard shortcut assigned
in Konnect, because media mode reacts to that shortcut, not to the button itself:

| Button | Assign in Konnect | Media mode action |
|---|---|---|
| Top side button | keystroke ⌘⇧2 | play / pause |
| Left side button | keystroke ⌃↑ (or the Mission Control action, which sends ⌃↑) | previous track |
| Big button that defaults to left click (or any spare one) | Middle Click | hold = mouse-only mode (desktops, tracks, play/pause, volume) |

Desktop switching sends macOS's "Move left/right a space" shortcuts, so keep them on (System
Settings → Keyboard → Keyboard Shortcuts → Mission Control). Set `DESKTOP_MODS` to the modifier used there (macOS default ⌃; ⌘ if you changed it). Tune `SWIPE_PX` (roll distance per
switch) and `SWIPE_GAP` in `macos/init.lua`.

If a side button does nothing in media mode, check that Konnect has its shortcut set. Without it,
Hammerspoon never sees a keystroke to turn into a media key.

## Changing things

Edit `macos/init.lua`, then reload with 🔨 menu bar icon → **Reload Config**, or
`hs -c "hs.reload()"`. A "Orbit remapper loaded" message confirms it. If something breaks,
🔨 → **Console** shows the Lua error.

- **Scroll direction:** `INVERT_SCROLL = true/false`.
- **Volume speed:** `SCROLL_GAP` sets the seconds between steps. Lower is faster.
- **Swap actions:** change the `media = "…"` values or `CLICK_MEDIA`. Available keys include
  `SOUND_UP/DOWN`, `MUTE`, `PLAY`, `NEXT`, `PREVIOUS`, `FAST`, `REWIND`, `BRIGHTNESS_UP/DOWN`.
- **Adding a button** (a Konnect shortcut): set `LOG_EVENTS = true`, reload, and press
  the button. Open `~/.hammerspoon/orbit-remapper-events.log`, note its keycode and flags, and add
  a line to `KONNECT_BUTTONS`. Set `LOG_EVENTS` back to `false`. The logger never records plain typing.
- **Anything else** (another modifier, app launching, window moves, …): add a handler that checks
  the condition, does the action, and returns `true` to swallow the original event.

## Known limitations

- **⌥+click and ⌥+scroll stop working everywhere.** That includes ⌥-drag to copy in Finder, ⌥-click
  to move the cursor in iTerm2, and ⌥+scroll zoom in design apps.
- **Secure input blocks it.** In password fields, or with iTerm2's *Secure Keyboard Entry* on, macOS
  hides key events from Hammerspoon. The side-button remaps don't fire there, and an ⌥ release can
  be missed until you press ⌥ again.
- **The mapping follows Konnect.** If you change what a side button sends in Konnect,
  or use per-app profiles that send different shortcuts, update `KONNECT_BUTTONS`.
- **Media keys go to the "Now Playing" app**, which macOS picks. That may be a browser tab rather than Spotify.
- **Middle-drag is taken over** (e.g. panning in 3D/design apps), and a plain middle click fires on
  release instead of on press.
- **Fast spins drop volume steps** because of the `SCROLL_GAP` throttle. Lower it if that bothers you.
- **This file is your whole Hammerspoon config.** To use other Hammerspoon scripts, keep your own
  `init.lua` and `dofile()` this one from it.
- **Updates can revoke Accessibility.** After a Hammerspoon or macOS update, re-check System Settings
  → Privacy & Security → Accessibility if it stops working.

## Windows

`windows/orbit-remapper.ahk` does the same with [AutoHotkey v2](https://www.autohotkey.com/), on
top of Konnect for Windows. Hold **Alt** instead of ⌥. The middle-button mode works the same way.

| Control | Alt held | Middle button held |
|---|---|---|
| Scroll ring | volume | volume |
| Top side button | play / pause | |
| Left side button | previous track | |
| Any left-click button | next track | |
| Right click | | play / pause |
| Roll left / right | | previous / next virtual desktop (Ctrl+Win+←/→) |
| Roll up / down | | next / previous track |

### Install (Windows)

1. Install AutoHotkey v2 (`winget install AutoHotkey.AutoHotkey`) and clone this repo.
2. In Konnect, set the **left side button to Button 4 (Back)** and the **top side button to
   Button 5 (Forward)**, and a spare button to **Middle Click**. On Windows the script matches
   these mouse buttons (`ALT_BUTTONS`), so no keyboard shortcuts are needed.
3. Double-click `orbit-remapper.ahk`. A tray notification confirms it loaded.
4. To start it at login, press Win+R, type `shell:startup`, and put a shortcut to the script there.

To edit it, change the settings at the top of the file, then tray icon → **Reload Script**. To
find what a button sends, use tray icon → **Key history (identify buttons)**, press the button,
and refresh with F5.

Differences from macOS:
- The pointer stays pinned in place while the middle button is held. On macOS it moves and
  jumps back when you release.
- Windows keeps no per-event modifier flags, so the side buttons don't need the "⌥ is missing"
  trick. They are plain Alt+XButton hotkeys.
- Programs running as administrator ignore the script unless it also runs as administrator.

## Linux (not done)

`input-remapper` would work (on X11 and Wayland).

## License

GPL-3.0
