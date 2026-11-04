# CLAUDE.md: kensington-orbit-remapper

Hammerspoon config that adds a ⌥-held media mode to a Kensington Orbit Fusion trackball.
See README.md for the design and the button table.

- Edit `macos/init.lua`; `~/.hammerspoon/init.lua` is a symlink to it. Never replace the symlink with a copy.
- Reload: `/opt/homebrew/bin/hs -c "hs.reload()"`. Check taps: `hs -c "print(mouseTap:isEnabled(), keyTap:isEnabled())"`.
- Normal mode belongs to Kensington Konnect (formerly KensingtonWorks). Only add behavior that activates while a modifier is held.
- Konnect sends side buttons as keystrokes and **replaces their flags**, so ⌥ is missing.
  Detect them with the tracked `altHeld` plus "event has no ⌥ flag", not with `e:getFlags().alt`.
- Posted media keys must clear flags (`e:setFlags({})`). Otherwise ⌥+volume opens Sound settings.
- The logger (`LOG_EVENTS`) must never record plain typing. Keep the ⌘/⌃/special-key filter.
- Keep the README button table in sync with `KONNECT_BUTTONS`.
- Never commit personal paths or data: this repo is public. The log lives in ~/.hammerspoon/, outside the repo.
