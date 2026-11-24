-- kensington-orbit-remapper: "media mode" for the Kensington Orbit Fusion while ⌥ Option is held.
-- Normal mode = whatever Kensington Konnect does. This file only changes behavior while ⌥ is held.
-- Install: symlink this file to ~/.hammerspoon/init.lua (see README.md)

require("hs.ipc") -- enables the `hs` CLI (hs -c "hs.reload()")

local types, props = hs.eventtap.event.types, hs.eventtap.event.properties

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local INVERT_SCROLL = true   -- true: scrolling down = volume up. Flip to taste.
local SCROLL_GAP = 0.05      -- seconds between volume steps (throttles the ring)
local LOG_EVENTS = false     -- true: log mouse/shortcut events (to map new buttons)
local LOG_FILE = hs.configdir .. "/orbit-remapper-events.log" -- ~/.hammerspoon/

-- Keystrokes Konnect sends for its buttons → media key while ⌥ is held.
-- To map another Konnect button: set LOG_EVENTS=true, press it, and add its keycode + flags here.
-- `needs`: every entry must be present; a nested list means "any of these".
-- `middle`: what the button does while the middle button is held (BACK / FORWARD, see NAV_KEYS).
-- ⌘ and ⌃ are interchangeable because apps like iTerm2 can swap them (Keys → Remap Modifiers).
local CMD_OR_CTRL = { "cmd", "ctrl" }
local KONNECT_BUTTONS = {
  { name = "Shottr",          keycode = 19,  needs = { CMD_OR_CTRL, "shift" }, media = "PLAY",     middle = "BACK" },    -- ⌘⇧2
  { name = "Mission Control", keycode = 126, needs = { CMD_OR_CTRL },          media = "PREVIOUS", middle = "FORWARD" }, -- ⌃↑
}
local CLICK_MEDIA = "NEXT"   -- ⌥ + left click (any left-click button)

-- Middle button held = mouse-only modifier: roll left/right = previous/next desktop,
-- roll up/down = next/previous track, right click = play/pause, scroll ring = volume,
-- top / left side button = back / forward (the `middle` field of KONNECT_BUTTONS).
-- A press without any of these stays a middle click. Sends macOS's "Move left/right a space" shortcut (System Settings →
-- Keyboard → Keyboard Shortcuts → Mission Control); DESKTOP_MODS must match what is set there.
local DESKTOP_MODS = { "cmd" } -- ⌘← / ⌘→ here; the macOS default is { "ctrl" }
local MIDDLE_BUTTON = 2      -- mouseEventButtonNumber Konnect sends for "Middle Click"
local SWIPE_PX = 80          -- roll distance needed for one desktop switch / track skip
local SWIPE_GAP = 0.35       -- seconds between actions (lets the desktop slide animation finish)
local ROLL_UP_MEDIA, ROLL_DOWN_MEDIA = "NEXT", "PREVIOUS"
local MIDDLE_RIGHT_CLICK_MEDIA = "PLAY"
local CLICK_SLOP_PX = 6      -- total movement under this still counts as a plain click
local NAV_KEYS = { BACK = "[", FORWARD = "]" } -- ⌘[ / ⌘] = back / forward in Chrome, Safari, Finder

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function mediaKey(key)
  for _, down in ipairs({ true, false }) do
    local e = hs.eventtap.event.newSystemKeyEvent(key, down)
    e:setFlags({}) -- drop Option, otherwise Option+Volume opens Sound settings
    e:post()
  end
end

-- Konnect strips ⌥ from the keystrokes it sends, so track the physical ⌥ key ourselves.
local ALT_KEYS = { [58] = true, [61] = true } -- left / right Option
local altHeld = false

-- Set while the middle button is held (see "Middle button held" below).
local swipe = nil -- { pos, dx, dy, travel, used, last }

local function hasAll(flags, needed)
  for _, f in ipairs(needed) do
    if type(f) == "table" then
      local any = false
      for _, alt in ipairs(f) do any = any or flags[alt] == true end
      if not any then return false end
    elseif not flags[f] then
      return false
    end
  end
  return true
end

---------------------------------------------------------------------------
-- ⌥ + scroll ring = volume
---------------------------------------------------------------------------
local lastScroll = 0
local function onScroll(e)
  if not (e:getFlags().alt or swipe) then return false end
  if swipe then swipe.used = true end
  local dy = e:getProperty(props.scrollWheelEventDeltaAxis1)
  if INVERT_SCROLL then dy = -dy end
  local now = hs.timer.secondsSinceEpoch()
  if dy ~= 0 and now - lastScroll > SCROLL_GAP then
    mediaKey(dy > 0 and "SOUND_UP" or "SOUND_DOWN")
    lastScroll = now
  end
  return true
end

---------------------------------------------------------------------------
-- ⌥ + left click = next track (swallow the whole click, including drag/up)
---------------------------------------------------------------------------
local clickAsMedia = false
local function onLeftMouse(e)
  local t = e:getType()
  if t == types.leftMouseDown and e:getFlags().alt then
    clickAsMedia = true
    mediaKey(CLICK_MEDIA)
    return true
  end
  if clickAsMedia then
    if t == types.leftMouseUp then clickAsMedia = false end
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- ⌥ + Konnect shortcut buttons
-- A Konnect keystroke = physical ⌥ held, but the event itself has no ⌥ (Konnect replaced the flags).
-- A real ⌥⌘⇧2 typed on the keyboard keeps its ⌥ flag and passes through untouched.
---------------------------------------------------------------------------
local swallowKeyUp = {}
local function onKey(e)
  local t, code, flags = e:getType(), e:getKeyCode(), e:getFlags()
  if t == types.flagsChanged then
    if ALT_KEYS[code] then altHeld = flags.alt == true end
    return false
  end
  if t == types.keyUp then
    if swallowKeyUp[code] then swallowKeyUp[code] = nil; return true end
    return false
  end
  if flags.alt or not (altHeld or swipe) then return false end
  for _, b in ipairs(KONNECT_BUTTONS) do
    if code == b.keycode and hasAll(flags, b.needs) then
      if swipe then -- middle button held: back / forward
        if not b.middle then return false end
        swipe.used = true
        hs.eventtap.keyStroke({ "cmd" }, NAV_KEYS[b.middle], 0)
      else
        mediaKey(b.media)
      end
      swallowKeyUp[code] = true
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Middle button held = mouse-only modifier (desktops, tracks, play/pause; volume is in onScroll)
-- The whole press is swallowed. On release with nothing done, a middle click is replayed,
-- tagged with REPLAY_TAG so this handler lets it through.
---------------------------------------------------------------------------
local REPLAY_TAG = 0x0B17

local function switchDesktop(dir)
  local key = dir > 0 and "right" or "left"
  for _, down in ipairs({ true, false }) do
    local mods = { "fn", table.unpack(DESKTOP_MODS) } -- arrow keys carry fn
    hs.eventtap.event.newKeyEvent(mods, key, down):post()
  end
end

local function onMiddleMouse(e)
  if e:getProperty(props.mouseEventButtonNumber) ~= MIDDLE_BUTTON then return false end
  if e:getProperty(props.eventSourceUserData) == REPLAY_TAG then return false end
  local t = e:getType()
  if t == types.otherMouseDown then
    swipe = { pos = hs.mouse.absolutePosition(), dx = 0, dy = 0, travel = 0, used = false, last = 0 }
    return true
  end
  if not swipe then return false end
  if t == types.otherMouseDragged then
    local dx = e:getProperty(props.mouseEventDeltaX)
    local dy = e:getProperty(props.mouseEventDeltaY)
    swipe.dx, swipe.dy = swipe.dx + dx, swipe.dy + dy
    swipe.travel = swipe.travel + math.abs(dx) + math.abs(dy)
    local horizontal = math.abs(swipe.dx) >= math.abs(swipe.dy)
    if math.max(math.abs(swipe.dx), math.abs(swipe.dy)) >= SWIPE_PX then
      local now = hs.timer.secondsSinceEpoch()
      if now - swipe.last > SWIPE_GAP then
        if horizontal then
          switchDesktop(swipe.dx)
        else
          mediaKey(swipe.dy < 0 and ROLL_UP_MEDIA or ROLL_DOWN_MEDIA) -- dy < 0 = rolled up
        end
        swipe.used, swipe.last = true, now
      end
      swipe.dx, swipe.dy = 0, 0
    end
    return true -- pointer still moves; it is put back on release (warping per event stalls input)
  end
  if t == types.otherMouseUp then
    local s = swipe
    swipe = nil
    if s.travel >= CLICK_SLOP_PX then hs.mouse.absolutePosition(s.pos) end
    if not s.used and s.travel < CLICK_SLOP_PX then
      for _, typ in ipairs({ types.otherMouseDown, types.otherMouseUp }) do
        local c = hs.eventtap.event.newMouseEvent(typ, s.pos)
        c:setProperty(props.mouseEventButtonNumber, MIDDLE_BUTTON)
        c:setProperty(props.eventSourceUserData, REPLAY_TAG)
        c:post()
      end
    end
    return true
  end
  return false
end

-- Right click while the middle button is held = play/pause (swallow the whole right click)
local rightAsMedia = false
local function onRightMouse(e)
  local t = e:getType()
  if t == types.rightMouseDown and swipe then
    swipe.used, rightAsMedia = true, true
    mediaKey(MIDDLE_RIGHT_CLICK_MEDIA)
    return true
  end
  if rightAsMedia then
    if t == types.rightMouseUp then rightAsMedia = false end
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- Taps
---------------------------------------------------------------------------
mouseTap = hs.eventtap.new(
  { types.scrollWheel, types.leftMouseDown, types.leftMouseDragged, types.leftMouseUp,
    types.otherMouseDown, types.otherMouseDragged, types.otherMouseUp,
    types.rightMouseDown, types.rightMouseDragged, types.rightMouseUp },
  function(e)
    local t = e:getType()
    if t == types.scrollWheel then return onScroll(e) end
    if t == types.otherMouseDown or t == types.otherMouseDragged or t == types.otherMouseUp then
      return onMiddleMouse(e)
    end
    if t == types.rightMouseDown or t == types.rightMouseDragged or t == types.rightMouseUp then
      return onRightMouse(e)
    end
    return onLeftMouse(e)
  end
):start()

keyTap = hs.eventtap.new({ types.keyDown, types.keyUp, types.flagsChanged }, onKey):start()

-- If a button release is ever missed, a mode would stay on (scroll = volume, clicks swallowed).
local function resetModes()
  swipe, clickAsMedia, rightAsMedia, altHeld = nil, false, false, false
end

-- macOS disables slow event taps; re-enable if that happens and forget any held state.
-- Also drop a mode whose button is no longer physically down.
-- Not for middle mode: macOS never reports Konnect's middle click as held, so this would end it
-- within 2 s. A missed middle release is fixed by the next middle press.
tapWatchdog = hs.timer.doEvery(2, function()
  if not mouseTap:isEnabled() or not keyTap:isEnabled() then
    mouseTap:start(); keyTap:start(); resetModes()
    return
  end
  local b = hs.mouse.getButtons()
  if clickAsMedia and not (b.left or b[1]) then clickAsMedia = false end
  if rightAsMedia and not (b.right or b[2]) then rightAsMedia = false end
end)

---------------------------------------------------------------------------
-- Event logger (for mapping new buttons). Never logs normal typing.
---------------------------------------------------------------------------
if LOG_EVENTS then
  local names = {}
  for k, v in pairs(types) do names[v] = k end
  logTap = hs.eventtap.new({
    types.leftMouseDown, types.rightMouseDown, types.otherMouseDown, types.keyDown, types.flagsChanged,
  }, function(e)
    local t = e:getType()
    if t == types.keyDown then
      local fl, code = e:getFlags(), e:getKeyCode()
      if not (fl.cmd or fl.ctrl or code >= 96) then return false end
    end
    local flags = {}
    for k, v in pairs(e:getFlags()) do if v then table.insert(flags, k) end end
    table.sort(flags)
    local extra
    if t == types.keyDown or t == types.flagsChanged then
      extra = " keycode=" .. e:getKeyCode() .. " (" .. tostring(hs.keycodes.map[e:getKeyCode()]) .. ")"
    else
      extra = " button=" .. e:getProperty(props.mouseEventButtonNumber)
    end
    local f = io.open(LOG_FILE, "a")
    if f then
      f:write(string.format("%s %-14s flags=[%s]%s\n", os.date("%H:%M:%S"), names[t] or t,
        table.concat(flags, ","), extra))
      f:close()
    end
    return false
  end):start()
end

hs.alert.show("Orbit remapper loaded")
