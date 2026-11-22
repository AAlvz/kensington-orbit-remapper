; kensington-orbit-remapper (Windows): "media mode" for the Kensington Orbit Fusion.
; Normal mode = whatever Kensington Konnect does. This script only changes behavior while
; Alt or the middle button is held. Same design as macos/init.lua; see README.md.
; Run: double-click (needs AutoHotkey v2), or put a shortcut to it in shell:startup.

#Requires AutoHotkey v2.0
#SingleInstance Force
InstallMouseHook
InstallKeybdHook
A_MaxHotkeysPerInterval := 1000 ; the scroll ring fires wheel hotkeys fast; don't warn
KeyHistory 100

;---------------------------------------------------------------------------
; Settings
;---------------------------------------------------------------------------
INVERT_SCROLL := true        ; true: scrolling down = volume up. Flip to taste.
SCROLL_GAP := 50             ; ms between volume steps (throttles the ring)

; Alt + button -> media key. Konnect's defaults send the side buttons as XButton1/XButton2.
; To find what a button sends: tray icon -> "Key history (identify buttons)", press it, refresh (F5).
CLICK_MEDIA := "Media_Next"  ; Alt + left click (any left-click button)
ALT_BUTTONS := Map(
  "XButton1", "Media_Prev",        ; left side button
  "XButton2", "Media_Play_Pause",  ; top side button
)

; Middle button held = mouse-only modifier: roll left/right = previous/next desktop,
; roll up/down = next/previous track, right click = play/pause, scroll ring = volume.
; A press without any of these stays a middle click (sent on release).
DESKTOP_LEFT := "^#{Left}"   ; Windows' "switch virtual desktop" shortcuts
DESKTOP_RIGHT := "^#{Right}"
SWIPE_PX := 80               ; roll distance needed for one desktop switch / track skip
SWIPE_GAP := 350             ; ms between actions (lets the desktop slide animation finish)
ROLL_UP_MEDIA := "Media_Next"
ROLL_DOWN_MEDIA := "Media_Prev"
MIDDLE_RIGHT_CLICK_MEDIA := "Media_Play_Pause"
CLICK_SLOP_PX := 6           ; total movement under this still counts as a plain click
POLL_MS := 10                ; how often the pointer is read while the middle button is held

;---------------------------------------------------------------------------
; State
;---------------------------------------------------------------------------
; Each mode is cleared by its button's release hotkey. The watchdog is a backup for a missed
; release. Konnect may inject its clicks, and the hook doesn't count injected input as
; physical, so the watchdog only checks buttons whose press showed up as physical.
swipe := false        ; object while the middle button is held
clickAsMedia := false ; an Alt+click became a media key; swallow its release
rightAsMedia := false ; a right click (middle held) became a media key; swallow its release
physical := Map()     ; button -> its current press is visible to GetKeyState(.., "P")
lastScroll := 0

MediaKey(key) {
  ; Plain Send releases the held Alt for the keystroke, like the macOS version clearing flags.
  Send "{" key "}"
}

CursorPos() {
  pt := Buffer(8)
  DllCall("GetCursorPos", "Ptr", pt)
  return [NumGet(pt, 0, "Int"), NumGet(pt, 4, "Int")]
}

;---------------------------------------------------------------------------
; Scroll ring = volume (Alt held, or middle button held)
;---------------------------------------------------------------------------
OnWheel(louder) {
  global lastScroll
  if swipe
    swipe.used := true
  if (A_TickCount - lastScroll > SCROLL_GAP) {
    MediaKey(louder ? "Volume_Up" : "Volume_Down")
    lastScroll := A_TickCount
  }
}

!WheelUp::   OnWheel(!INVERT_SCROLL)
!WheelDown:: OnWheel(INVERT_SCROLL)

;---------------------------------------------------------------------------
; Alt + left click = next track (swallow the whole click, including drag and release)
;---------------------------------------------------------------------------
!LButton:: {
  global clickAsMedia := true
  physical["LButton"] := GetKeyState("LButton", "P")
  MediaKey(CLICK_MEDIA)
}

#HotIf clickAsMedia
*LButton Up:: {         ; swallow the release (and any drag in between)
  global clickAsMedia := false
}
#HotIf

;---------------------------------------------------------------------------
; Alt + side buttons
;---------------------------------------------------------------------------
for btn, media in ALT_BUTTONS
  Hotkey "!" btn, ((m, *) => MediaKey(m)).Bind(media)

;---------------------------------------------------------------------------
; Middle button held = mouse-only modifier
; The press is swallowed. While held, the pointer is pinned where it was and every poll
; reads how far it was pushed, so rolling keeps counting even at a screen edge.
; On release with nothing done, a normal middle click is sent instead.
;---------------------------------------------------------------------------
*MButton:: {
  global swipe
  if swipe
    return
  p := CursorPos()
  swipe := { x: p[1], y: p[2], dx: 0, dy: 0, travel: 0, used: false, last: 0 }
  physical["MButton"] := GetKeyState("MButton", "P")
  SetTimer PollSwipe, POLL_MS
}

*MButton Up:: {
  global swipe
  if !swipe
    return
  PollSwipe()           ; count the last bit of movement
  s := swipe
  swipe := false
  SetTimer PollSwipe, 0
  if (!s.used && s.travel < CLICK_SLOP_PX)
    Click "Middle"      ; the script's own clicks don't trigger its hotkeys
}

PollSwipe() {
  if !swipe
    return
  p := CursorPos()
  dx := p[1] - swipe.x, dy := p[2] - swipe.y
  if (dx = 0 && dy = 0)
    return
  DllCall("SetCursorPos", "Int", swipe.x, "Int", swipe.y)
  swipe.dx += dx, swipe.dy += dy
  swipe.travel += Abs(dx) + Abs(dy)
  if (Max(Abs(swipe.dx), Abs(swipe.dy)) < SWIPE_PX)
    return
  if (A_TickCount - swipe.last > SWIPE_GAP) {
    if (Abs(swipe.dx) >= Abs(swipe.dy))
      Send swipe.dx > 0 ? DESKTOP_RIGHT : DESKTOP_LEFT
    else
      MediaKey(swipe.dy < 0 ? ROLL_UP_MEDIA : ROLL_DOWN_MEDIA) ; dy < 0 = rolled up
    swipe.used := true, swipe.last := A_TickCount
  }
  swipe.dx := 0, swipe.dy := 0
}

#HotIf swipe
*WheelUp::   OnWheel(!INVERT_SCROLL)
*WheelDown:: OnWheel(INVERT_SCROLL)
*RButton:: {
  global rightAsMedia := true
  physical["RButton"] := GetKeyState("RButton", "P")
  swipe.used := true
  MediaKey(MIDDLE_RIGHT_CLICK_MEDIA)
}
#HotIf rightAsMedia
*RButton Up:: {
  global rightAsMedia := false
}
#HotIf

;---------------------------------------------------------------------------
; Watchdog: if a release is ever missed, a mode would stay on (scroll = volume,
; clicks swallowed). Drop any mode whose button is no longer physically down.
;---------------------------------------------------------------------------
Released(btn) => physical.Get(btn, false) && !GetKeyState(btn, "P")

Watchdog() {
  global swipe, clickAsMedia, rightAsMedia
  if (swipe && Released("MButton")) {
    swipe := false
    SetTimer PollSwipe, 0
  }
  if (clickAsMedia && Released("LButton"))
    clickAsMedia := false
  if (rightAsMedia && Released("RButton"))
    rightAsMedia := false
}
SetTimer Watchdog, 2000

;---------------------------------------------------------------------------
; Tray
;---------------------------------------------------------------------------
A_IconTip := "Orbit remapper"
A_TrayMenu.Insert("1&", "Key history (identify buttons)", (*) => KeyHistory())
A_TrayMenu.Insert("2&")
TrayTip "Alt or middle button + trackball = media / desktops", "Orbit remapper loaded"
