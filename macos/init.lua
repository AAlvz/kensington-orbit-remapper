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
-- ⌘ and ⌃ are interchangeable because apps like iTerm2 can swap them (Keys → Remap Modifiers).
local CMD_OR_CTRL = { "cmd", "ctrl" }
local KONNECT_BUTTONS = {
  { name = "Shottr",          keycode = 19,  needs = { CMD_OR_CTRL, "shift" }, media = "PLAY" },     -- ⌘⇧2
  { name = "Mission Control", keycode = 126, needs = { CMD_OR_CTRL },          media = "PREVIOUS" }, -- ⌃↑
}
local CLICK_MEDIA = "NEXT"   -- ⌥ + left click (any left-click button)

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
  if not e:getFlags().alt then return false end
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
  if not altHeld or flags.alt then return false end
  for _, b in ipairs(KONNECT_BUTTONS) do
    if code == b.keycode and hasAll(flags, b.needs) then
      swallowKeyUp[code] = true
      mediaKey(b.media)
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Taps
---------------------------------------------------------------------------
mouseTap = hs.eventtap.new(
  { types.scrollWheel, types.leftMouseDown, types.leftMouseDragged, types.leftMouseUp },
  function(e)
    if e:getType() == types.scrollWheel then return onScroll(e) end
    return onLeftMouse(e)
  end
):start()

keyTap = hs.eventtap.new({ types.keyDown, types.keyUp, types.flagsChanged }, onKey):start()

-- macOS disables slow event taps; re-enable if that happens (and forget ⌥ state, it may be stale)
tapWatchdog = hs.timer.doEvery(5, function()
  if not mouseTap:isEnabled() then mouseTap:start() end
  if not keyTap:isEnabled() then keyTap:start(); altHeld = false end
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
