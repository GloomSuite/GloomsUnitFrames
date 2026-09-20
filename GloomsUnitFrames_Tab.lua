-- ============================================================
-- GloomsUnitFrames_Tab.lua
-- The UNIT FRAMES tab of the Suite window, laid out the family way (GB is
-- the reference): a LEFT RAIL (the mark, Player / Target as a selectable
-- list, Reset) and a scrolling RIGHT PANE with the selected unit's settings.
-- No footer: every control applies the moment it moves and the on-screen
-- ring IS the preview. No profile block (two fixed units, one account-wide
-- config — as Portraits). Every widget comes from LibGloomSkin-1.0; the
-- engine (GloomsUnitFrames.lua) exposes what this file drives.
-- ============================================================

-- ★ SHARED-TOOLKIT VERSION GATE — GloomsHub/docs/CONTRACTS.md §6. Bump
-- SKIN_NEEDS in the same commit that first calls a newer widget.
-- This file needs tabHeader (MINOR 4); everything else it calls is older.
local SKIN_MAJOR, SKIN_NEEDS = "LibGloomSkin-1.0", 4

local Skin, skinMinor = LibStub(SKIN_MAJOR, true)
if not Skin or (skinMinor or 0) < SKIN_NEEDS then
  local found = Skin and ("v" .. tostring(skinMinor or 0)) or "none"
  local warn = CreateFrame("Frame")
  warn:RegisterEvent("PLAYER_LOGIN")
  warn:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    print("|cffff7729Gloom's Unit Frames:|r please update |cff936bffGloom's Hub|r. This version "
      .. "needs a newer Hub toolkit (needs v" .. SKIN_NEEDS .. ", found " .. found
      .. "), so the UNIT FRAMES tab is unavailable. Your rings keep rendering normally.")
  end)
  return
end
local UI = Skin.UI
local COLOR, FONT = Skin.COLOR, Skin.FONT
local TEXT, MUTE = COLOR.text, COLOR.mute

local newText, flatButton, flatEditBox = UI.newText, UI.flatButton, UI.flatEditBox
local sliderRow, makeScrollbar, attachTip, hLine = UI.sliderRow, UI.makeScrollbar, UI.attachTip, UI.hLine
local makeToggle, colorSwatch = UI.makeToggle, UI.colorSwatch

local GU = _G.GloomsUnitFrames

-- Font pairs this tab draws beyond the Hub's warm list (CONTRACTS §4).
UI.RegisterWarmPairs({
  { FONT.head, 13 },
  { FONT.label, 11 },
  { FONT.head, 22 },   -- the ring's centre text, at its default size
})

local RAIL_W     = 240
local PAD        = 18
local LIST_ROW_H = 30

local container, rail, editorScroll, editorChild, editorBody, emptyNote
local selected
local rows = {}
local E = {}
local RefreshList, SelectUnit, RefreshEditor

local UNIT_LABEL = { player = "Player", target = "Target" }
local COND_LABEL = {
  always = "Always", combat = "In combat", target = "Target selected", combat_or_target = "Combat or target",
}

local function Cfg() return selected and GU:Config(selected) or nil end
local function RingCfg(key) local c = Cfg(); return c and c.rings[key] or nil end

-- --------------------------------------------------------------------------
-- Local widget shapes (the same ones the Portraits tab keeps)
-- --------------------------------------------------------------------------
local function label(parent, text, x, y, size, cc)
  local fs = newText(parent, FONT.body, size or 12, cc or TEXT, "LEFT")
  fs:SetPoint("TOPLEFT", x, y); fs:SetText(text)
  return fs
end

-- Slider + typed box. `apply(v)` receives an integer clamped to [minV, maxV].
local function numRow(parent, yTop, labelText, minV, maxV, get, apply, sub)
  local h = {}
  local ebox = flatEditBox(parent, 56, 18)
  ebox:SetPoint("TOPRIGHT", -18, yTop + 3)
  ebox:SetMaxLetters(6); ebox:SetJustifyH("CENTER")
  local row = sliderRow(parent, yTop, labelText, minV, maxV, 1, get,
    function(v) v = math.floor(v + 0.5); apply(v); ebox:SetText(tostring(v)) end,
    function() return "" end, sub)
  function h:refresh()
    row:refresh()
    ebox:SetText(tostring(math.floor((get() or minV) + 0.5)))
  end
  function h:show(on) row:SetShown(on); ebox:SetShown(on) end
  local function commit(self)
    local v = tonumber(self:GetText())
    if v then apply(math.max(minV, math.min(maxV, math.floor(v + 0.5)))) end
    h:refresh()
  end
  ebox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commit(self) end)
  ebox:HookScript("OnEditFocusLost", commit)
  ebox:SetScript("OnEscapePressed", function(self) h:refresh(); self:ClearFocus() end)
  return h
end

-- Label on the left, sliding switch on the right.
local function toggleRow(parent, yTop, labelText, get, set, tip)
  local lab = newText(parent, FONT.body, 12, TEXT, "LEFT")
  lab:SetPoint("TOPLEFT", PAD, yTop); lab:SetText(labelText)
  local t = makeToggle(parent, function() return get() and true or false end, set)
  t:SetPoint("TOPRIGHT", -PAD, yTop + 3)
  if tip then attachTip(t, labelText, tip) end
  function t:show(on) lab:SetShown(on); self:SetShown(on) end
  return t
end

-- Label on the left, colour swatch on the right.
local function colorRow(parent, yTop, labelText, get, set, tip, name)
  local lab = newText(parent, FONT.body, 12, TEXT, "LEFT")
  lab:SetPoint("TOPLEFT", PAD, yTop); lab:SetText(labelText)
  local sw = colorSwatch(parent, get, set, false, name)
  sw.swatch:SetPoint("TOPRIGHT", -PAD, yTop + 3)
  if tip then attachTip(sw.swatch, labelText, tip) end
  function sw:show(on) lab:SetShown(on); self.swatch:SetShown(on) end
  return sw
end

-- Mutually-exclusive flatButtons, the selected one orange.
local function choiceRow(parent, choices, bw, bh, x, y, gap, onPick, perRow)
  local btns = {}
  for i, c in ipairs(choices) do
    local value, text = c[1], c[2] or c[1]
    local col = perRow and ((i - 1) % perRow) or (i - 1)
    local rowN = perRow and math.floor((i - 1) / perRow) or 0
    local b = flatButton(parent, bw, bh, COLOR.heroic, text, 11)
    b:SetBase(0.2)
    b:SetPoint("TOPLEFT", x + col * (bw + (gap or 4)), y - rowN * (bh + 4))
    b:SetScript("OnClick", function()
      onPick(value)
      for _, e in ipairs(btns) do e.b:SetActive(e.v == value) end
    end)
    if c[3] then attachTip(b, text, c[3]) end
    btns[#btns + 1] = { b = b, v = value }
  end
  return { sync = function(value) for _, e in ipairs(btns) do e.b:SetActive(e.v == value) end end }
end

-- --------------------------------------------------------------------------
-- LEFT RAIL
-- --------------------------------------------------------------------------
local function BuildRail(c)
  rail = CreateFrame("Frame", nil, c)
  rail:SetPoint("TOPLEFT", 0, 0); rail:SetPoint("BOTTOMLEFT", 0, 0)
  rail:SetWidth(RAIL_W)
  local X, W = 14, RAIL_W - 28

  UI.tabHeader(rail, {
    texture = "Interface\\AddOns\\GloomsUnitFrames\\Media\\ui\\logo.png",
    label   = "GLOOM'S UNIT FRAMES",
    x       = X,
  })

  local oh = newText(rail, FONT.head, 12, MUTE, "LEFT")
  oh:SetPoint("TOPLEFT", X, -62); oh:SetText("UNITS")

  for i, which in ipairs(GU.UNITS) do
    local row = CreateFrame("Button", nil, rail)
    row:SetSize(W, LIST_ROW_H)
    row:SetPoint("TOPLEFT", X, -80 - (i - 1) * LIST_ROW_H)
    row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints()
    row.sel:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.28); row.sel:Hide()
    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.07)
    row.text = newText(row, FONT.body, 12, TEXT, "LEFT"); row.text:SetPoint("LEFT", 8, 0)
    row.text:SetText(UNIT_LABEL[which])
    row.sub = newText(row, FONT.body, 10.5, MUTE, "RIGHT"); row.sub:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnClick", function() SelectUnit(which) end)
    rows[which] = row
  end

  local hint = newText(rail, FONT.body, 10.5, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", X, -80 - 2 * LIST_ROW_H - 10)
  hint:SetPoint("TOPRIGHT", -X, -80 - 2 * LIST_ROW_H - 10)
  hint:SetJustifyH("LEFT")
  hint:SetText("While this tab is open, the selected unit's ring can be dragged on screen. "
    .. "The green outline is its frame; the target ring shows empty until you have a target.")

  -- Copy the other unit's settings (everything but position) onto this one.
  E.copyBtn = flatButton(rail, W, 22, COLOR.heroic, "Copy from Target", 11)
  E.copyBtn:SetBase(0.2); E.copyBtn:SetPoint("BOTTOMLEFT", X, 34)
  E.copyBtn:SetScript("OnClick", function()
    local which = selected
    if not which then return end
    local from = (which == "player") and "target" or "player"
    UI.confirm(("Copy the %s frame's settings onto the %s frame? Position stays as it is."):format(
      UNIT_LABEL[from]:lower(), UNIT_LABEL[which]:lower()), function()
      GU:CopyFrom(which, from)
      RefreshEditor(); RefreshList()
    end)
  end)
  attachTip(E.copyBtn, "Copy from the other unit",
    "Layer, visibility, text and every ring the two share — sizes, angles, colors, rounding. Position is left alone.")

  E.resetBtn = flatButton(rail, W, 22, COLOR.heroic, "Reset to defaults", 11)
  E.resetBtn:SetBase(0.2); E.resetBtn:SetPoint("BOTTOMLEFT", X, 6)
  E.resetBtn:SetScript("OnClick", function()
    local which = selected
    if not which then return end
    UI.confirm(("Reset the %s frame to its factory position, size and rings?"):format(UNIT_LABEL[which]:lower()),
      function() GU:Reset(which); RefreshEditor(); RefreshList() end)
  end)
  attachTip(E.resetBtn, "Reset to defaults", "Puts the selected unit back where a fresh install would have it. Asks first.")
end

RefreshList = function()
  for _, which in ipairs(GU.UNITS) do
    local row, cfg = rows[which], GU:Config(which)
    if row then
      row.sel:SetShown(which == selected)
      if cfg then
        local on = {}
        if cfg.rings.health.enabled then on[#on + 1] = "Health" end
        if cfg.rings.power.enabled then on[#on + 1] = "Power" end
        if cfg.rings.resource and cfg.rings.resource.enabled then on[#on + 1] = "Resource" end
        if cfg.rings.cast and cfg.rings.cast.enabled then on[#on + 1] = "Cast" end
        row.sub:SetText((#on > 0 and table.concat(on, " + ") or "Off") .. " · " .. (COND_LABEL[cfg.showCondition] or "Always"))
      else
        row.sub:SetText("")
      end
    end
  end
  if E.resetBtn then E.resetBtn:SetEnabled(selected ~= nil) end
  if E.copyBtn then
    E.copyBtn:SetEnabled(selected ~= nil)
    E.copyBtn.text:SetText(selected == "target" and "Copy from Player" or "Copy from Target")
  end
end

-- --------------------------------------------------------------------------
-- RIGHT PANE
-- --------------------------------------------------------------------------
local STRATA = {
  { "BACKGROUND", "Background", "Behind almost everything." },
  { "LOW",        "Low",        "Behind most frames." },
  { "MEDIUM",     "Medium",     "The default. With most addon frames." },
  { "HIGH",       "High",       "In front of most frames." },
  { "DIALOG",     "Dialog",     "Above almost everything." },
}

-- ★ `v or default` is WRONG for a boolean setting: an OFF switch (false) would
-- read as its default (true) and every click would turn it off again. nil only.
local function orDefault(v, default) if v == nil then return default end return v end

local function num(field, default)
  return function() local cfg = Cfg(); return cfg and orDefault(cfg[field], default) end
end
local function setUnit(field)
  return function(v) local cfg = Cfg(); if cfg then cfg[field] = v; GU:ApplyLayout(selected) end end
end
local function rnum(key, field, default)
  return function() local rc = RingCfg(key); return rc and orDefault(rc[field], default) end
end
local function setRing(key, field)
  return function(v) local rc = RingCfg(key); if rc then rc[field] = v; GU:ApplyLayout(selected); RefreshList() end end
end

-- One ring's section: on/off, geometry, colour. Fixed height, :refresh().
-- kind: "health" · "power" (power-type colour toggle) · "resource" (segments:
-- gap row + resource-colour toggle, no shift). Fills an accordion body.
local function ringSection(sec, key, title, kind)
  local isHealth, isPower, isResource, isCast = kind == "health", kind == "power", kind == "resource", kind == "cast"
  local w = {}

  w.enabled = toggleRow(sec, -42, "Show this ring", rnum(key, "enabled", true), setRing(key, "enabled"),
    "Draws the " .. key .. " arc for this unit.")

  w.size = numRow(sec, -74, "Size", 40, 700, rnum(key, "size", 220), setRing(key, "size"),
    "px — this ring's outer diameter. Smaller rings nest inside larger ones.")
  w.thick = numRow(sec, -124, "Thickness", 2, 350, rnum(key, "thickness", 22), setRing(key, "thickness"),
    "px — cut from the inside; half the size or more is a solid disc")
  w.dx = numRow(sec, -174, "Offset X", -300, 300, rnum(key, "dx", 0), setRing(key, "dx"))
  w.dy = numRow(sec, -220, "Offset Y", -300, 300, rnum(key, "dy", 0), setRing(key, "dy"))

  w.start = numRow(sec, -266, "Start angle", 0, 359, rnum(key, "start", 180), setRing(key, "start"),
    "degrees — 0 is right, 90 top, 180 left, 270 bottom. Where the FULL end sits.")
  w.span = numRow(sec, -316, "Arc span", 10, 360, rnum(key, "span", 180), setRing(key, "span"),
    "degrees — 180 is a semicircle, 360 a full ring")

  label(sec, "Fills", PAD, -368)
  w.dir = choiceRow(sec, {
    { "cw",  "Clockwise",         "The arc grows clockwise from its start angle." },
    { "ccw", "Counter-clockwise", "The arc grows counter-clockwise from its start angle." },
  }, 130, 20, 80, -366, 6, function(v) setRing(key, "clockwise")(v == "cw") end)

  local cy = -398
  if isResource then
    -- one switch for both ends of every segment
    w.roundStart = toggleRow(sec, cy, "Round the segment ends", rnum(key, "roundStart", false),
      function(v) local rc = RingCfg(key); if rc then rc.roundStart, rc.roundEnd = v, v; GU:ApplyLayout(selected) end end,
      "Round caps on both ends of every segment.")
    cy = cy - 28
  else
    w.roundStart = toggleRow(sec, cy, "Round the start", rnum(key, "roundStart", false), setRing(key, "roundStart"),
      "A round cap on the arc's fixed end.")
    cy = cy - 28
    w.roundEnd = toggleRow(sec, cy, "Round the moving end", rnum(key, "roundEnd", false), setRing(key, "roundEnd"),
      "A round cap that rides the leading edge as the value moves.")
    cy = cy - 28
  end
  w.trackColor = colorRow(sec, cy, "Empty track color", rnum(key, "trackColor"), setRing(key, "trackColor"), nil,
    "Unit Frames › " .. title .. " track")
  cy = cy - 28
  w.trackAlpha = numRow(sec, cy, "Empty track opacity", 0, 100,
    function() local rc = RingCfg(key); return rc and math.floor((rc.trackAlpha or 0.12) * 100 + 0.5) or 12 end,
    function(v) local rc = RingCfg(key); if rc then rc.trackAlpha = v / 100; GU:ApplyLayout(selected) end end,
    "percent — the unfilled part of the ring")
  cy = cy - 54
  if isHealth then
    w.powerColor = toggleRow(sec, cy, "Use the unit's class color",
      rnum(key, "classColor", true), setRing(key, "classColor"),
      "A player's class color; for an NPC, hostile red, neutral yellow, friendly green — instead of the Color below. Solid mode only: a gradient wins over it. The drain shift still applies on top.")
    cy = cy - 28
    w.shieldOn = toggleRow(sec, cy, "Tint while shielded", rnum(key, "shieldTint", false),
      function(v) setRing(key, "shieldTint")(v); sec:refresh() end,
      "While the unit has an absorb shield, a wash of the color below lies over the filled part of the ring, fading out to nothing in the direction you set. The game decides when — the shield's size is not something an addon may read on 12.1, so this shows presence, not amount.")
    cy = cy - 28
    w.shieldColor = colorRow(sec, cy, "Shield tint color", rnum(key, "shieldColor"), setRing(key, "shieldColor"), nil,
      "Unit Frames › " .. title .. " shield tint")
    cy = cy - 28
    w.shieldAlpha = numRow(sec, cy, "Shield tint opacity", 0, 100,
      function() local rc = RingCfg(key); return rc and math.floor((rc.shieldAlpha or 0.8) * 100 + 0.5) or 80 end,
      function(v) local rc = RingCfg(key); if rc then rc.shieldAlpha = v / 100; GU:ApplyLayout(selected) end end,
      "percent — the wash at its strongest end")
    cy = cy - 50
    w.shieldAuto = toggleRow(sec, cy, "Fade along the arc", rnum(key, "shieldAuto", true),
      function(v) setRing(key, "shieldAuto")(v); sec:refresh() end,
      "Strongest at the arc's start, gone by its end, whatever the span and angle. Off: set the width and direction yourself. A full 360° ring always uses the manual settings.")
    cy = cy - 28
    w.shieldWidth = numRow(sec, cy, "Shield fade width", 10, 100, rnum(key, "shieldWidth", 70), setRing(key, "shieldWidth"),
      "percent of the ring's diameter the fade runs across, centred — 100 is edge to edge")
    cy = cy - 50
    w.shieldAngle = numRow(sec, cy, "Shield fade direction", 0, 359, rnum(key, "shieldAngle", 180), setRing(key, "shieldAngle"),
      "degrees — the wash is strongest on this side and fades to nothing across the ring: 180 = full on the left, 0 = full on the right, 90 = top")
    cy = cy - 50
  elseif isPower then
    w.powerColor = toggleRow(sec, cy, "Use the power type's color",
      rnum(key, "powerColor", true), setRing(key, "powerColor"),
      "Mana blue, rage red, energy yellow and so on, instead of the color below.")
    cy = cy - 28
  elseif isCast then
    w.drains = toggleRow(sec, cy, "Channels drain", rnum(key, "channelDrains", true), setRing(key, "channelDrains"),
      "A channeled spell empties the arc as it runs down; a cast fills it. Off: both fill.")
    cy = cy - 28
    w.lockOn = toggleRow(sec, cy, "Color the target's cast by interrupt state", rnum(key, "kickAware", true),
      function(v) setRing(key, "kickAware")(v); sec:refresh() end,
      "Target only. Interruptible with your interrupt ready = the Color row above. Otherwise the two colors below. Solid colors (a gradient is set aside while this is on).")
    cy = cy - 28
    w.cdColor = colorRow(sec, cy, "…interruptible, but your interrupt is on cooldown", rnum(key, "kickCDColor"), setRing(key, "kickCDColor"), nil,
      "Unit Frames › " .. title .. " interrupt on cooldown")
    cy = cy - 28
    w.lockColor = colorRow(sec, cy, "…can't be interrupted", rnum(key, "lockedColor"), setRing(key, "lockedColor"), nil,
      "Unit Frames › " .. title .. " uninterruptible")
    cy = cy - 28
    w.midOn = toggleRow(sec, cy, "…interrupt back before the cast ends: tint", rnum(key, "midCastEnabled", true),
      function(v) setRing(key, "midCastEnabled")(v); sec:refresh() end,
      "Your interrupt is on cooldown but returns before this cast finishes — the fill takes this color.")
    cy = cy - 28
    w.midColor = colorRow(sec, cy, "…that tint's color", rnum(key, "midCastColor"), setRing(key, "midCastColor"), nil,
      "Unit Frames › " .. title .. " mid-cast tint")
    cy = cy - 28
    w.tickOn = toggleRow(sec, cy, "Tick where your interrupt returns", rnum(key, "kickTick", true),
      function(v) setRing(key, "kickTick")(v); sec:refresh() end,
      "A small mark on the arc at the point where your interrupt comes off cooldown, if that is before the cast ends.")
    cy = cy - 28
    w.tickColor = colorRow(sec, cy, "Tick color", rnum(key, "kickTickColor"), setRing(key, "kickTickColor"), nil,
      "Unit Frames › " .. title .. " kick tick")
    cy = cy - 28
  elseif isResource then
    w.gap = numRow(sec, cy, "Gap between segments", 0, 30, rnum(key, "gap", 4), setRing(key, "gap"),
      "degrees — one segment per point; the count follows your class and spec")
    cy = cy - 50
    w.powerColor = toggleRow(sec, cy, "Use the resource's color",
      rnum(key, "resourceColor", true), setRing(key, "resourceColor"),
      "Soul shards purple, combo points yellow and so on, instead of the color below.")
    cy = cy - 28
  end

  label(sec, "Color", PAD, cy)
  w.mode = choiceRow(sec, {
    { "solid",    "Solid",    "One color." },
    { "gradient", "Gradient", "Blends from the first color to the second across the ring, along an angle you set." },
  }, 90, 20, 80, cy + 2, 6, function(v) setRing(key, "colorMode")(v); sec:refresh() end)
  cy = cy - 28
  w.color = colorRow(sec, cy, "Color", rnum(key, "color"), setRing(key, "color"), nil,
    "Unit Frames › " .. title .. " color")
  cy = cy - 28
  w.color2 = colorRow(sec, cy, "End color", rnum(key, "color2"), setRing(key, "color2"), nil,
    "Unit Frames › " .. title .. " gradient end")
  w.angle = numRow(sec, cy - 22, "Gradient angle", 0, 359, rnum(key, "gradientAngle", 0), setRing(key, "gradientAngle"),
    "degrees — 0 runs left to right, 90 bottom to top")
  cy = cy - 78
  if isCast then
    label(sec, "The cast ring shows only while the unit is casting or channeling.", PAD, cy + 8, 10.5, MUTE)
  end
  if isResource then
    w.brkOn = toggleRow(sec, cy, "Change color at a point count",
      rnum(key, "breakEnabled", false), function(v) setRing(key, "breakEnabled")(v); sec:refresh() end,
      "Every segment turns the color below once you have at least this many points.")
    cy = cy - 28
    w.brkAt = numRow(sec, cy, "At this many points", 1, 7, rnum(key, "breakAt", 5), setRing(key, "breakAt"))
    cy = cy - 46
    w.brkColor = colorRow(sec, cy, "Color from there", rnum(key, "breakColor"), setRing(key, "breakColor"), nil,
      "Unit Frames › " .. title .. " breakpoint color")
  end
  if not (isResource or isCast) then
    w.shift = toggleRow(sec, cy, "Shift color as it drains",
      rnum(key, "shift", false), function(v) setRing(key, "shift")(v); sec:refresh() end,
      "On top of the color above: the mid color is fully in by 50%, and the low color fades in from there toward empty. Blended by the game engine, so it works on secret values.")
    cy = cy - 28
    w.mid = colorRow(sec, cy, "Mid color (at 50%)", rnum(key, "midColor"), setRing(key, "midColor"), nil,
      "Unit Frames › " .. title .. " mid color")
    cy = cy - 28
    w.low = colorRow(sec, cy, "Low color (at empty)", rnum(key, "lowColor"), setRing(key, "lowColor"), nil,
      "Unit Frames › " .. title .. " low color")
  end

  function sec:refresh()
    local rc = RingCfg(key)
    if not rc then return end
    w.enabled:refresh()
    w.size:refresh(); w.thick:refresh(); w.dx:refresh(); w.dy:refresh()
    w.start:refresh(); w.span:refresh()
    w.dir.sync(rc.clockwise and "cw" or "ccw")
    if w.powerColor then w.powerColor:refresh() end
    if w.gap then w.gap:refresh() end
    if w.drains then
      w.drains:refresh(); w.lockOn:refresh(); w.cdColor:refresh(); w.lockColor:refresh()
      local on = rc.kickAware and true or false
      w.cdColor:show(on); w.lockColor:show(on)
      w.midOn:refresh(); w.midColor:refresh(); w.tickOn:refresh(); w.tickColor:refresh()
      w.midOn:show(on); w.midColor:show(on and rc.midCastEnabled and true or false)
      w.tickOn:show(on); w.tickColor:show(on and rc.kickTick and true or false)
    end
    w.roundStart:refresh(); if w.roundEnd then w.roundEnd:refresh() end
    w.trackColor:refresh(); w.trackAlpha:refresh()
    if w.brkOn then
      w.brkOn:refresh(); w.brkAt:refresh(); w.brkColor:refresh()
      w.brkAt:show(rc.breakEnabled and true or false); w.brkColor:show(rc.breakEnabled and true or false)
    end
    local mode = rc.colorMode or "solid"
    w.mode.sync(mode)
    if isHealth then
      w.powerColor:show(mode ~= "gradient")
      w.shieldOn:refresh(); w.shieldColor:refresh(); w.shieldAlpha:refresh()
      w.shieldAuto:refresh(); w.shieldWidth:refresh(); w.shieldAngle:refresh()
      local son = rc.shieldTint and true or false
      local manual = son and (rc.shieldAuto == false or (rc.span or 180) >= 360)
      w.shieldColor:show(son); w.shieldAlpha:show(son); w.shieldAuto:show(son)
      w.shieldWidth:show(manual); w.shieldAngle:show(manual)
    end
    w.color:refresh(); w.color2:refresh(); w.angle:refresh()
    w.color2:show(mode == "gradient"); w.angle:show(mode == "gradient")
    if w.shift then
      w.shift:refresh(); w.mid:refresh(); w.low:refresh()
      w.mid:show(rc.shift and true or false); w.low:show(rc.shift and true or false)
    end
  end
  return sec
end

-- --------------------------------------------------------------------------
-- The accordion (GB's is the reference): 36px headers — orange caret, Khand
-- purple title, hairline under — one section open at a time, stack reflows.
-- --------------------------------------------------------------------------
local SECTION_HDR_H = 36
local sections = {}
local bodyContainer

local function relayout()
  local prevBottom, total = nil, 0
  for _, sc in ipairs(sections) do
    sc.header:ClearAllPoints()
    if prevBottom then
      sc.header:SetPoint("TOPLEFT", prevBottom, "BOTTOMLEFT", 0, 0)
      sc.header:SetPoint("TOPRIGHT", prevBottom, "BOTTOMRIGHT", 0, 0)
    else
      sc.header:SetPoint("TOPLEFT", bodyContainer, "TOPLEFT", 0, 0)
      sc.header:SetPoint("TOPRIGHT", bodyContainer, "TOPRIGHT", 0, 0)
    end
    sc.caret:SetRotation(sc.open and UI.CARET_DOWN or 0)
    if sc.hidden then
      sc.header:Hide(); sc.body:Hide()
    else
      sc.header:Show()
      total = total + SECTION_HDR_H
      if sc.open then
        sc.body:ClearAllPoints()
        sc.body:SetPoint("TOPLEFT", sc.header, "BOTTOMLEFT", 0, 0)
        sc.body:SetPoint("TOPRIGHT", sc.header, "BOTTOMRIGHT", 0, 0)
        sc.body:Show()
        prevBottom = sc.body
        total = total + sc.height
      else
        sc.body:Hide()
        prevBottom = sc.header
      end
    end
  end
  bodyContainer:SetHeight(math.max(total + 4, 10))
  editorChild:SetHeight(math.max(total + 4, 10))
end

local function syncCastPreview()
  for _, u in ipairs(GU.UNITS) do
    GU:SetCastPreview(u, u == selected and E.castSec and E.castSec.open and container and container:IsVisible())
  end
end

local function toggleSection(sc)
  local wasOpen = sc.open
  for _, x in ipairs(sections) do x.open = false end
  if not wasOpen then sc.open = true; if sc.refresh then sc.refresh() end end
  relayout()
  syncCastPreview()
  -- Bring a freshly opened section near the top, one collapsed header above it.
  if not wasOpen and editorScroll then
    local idx
    for i, x in ipairs(sections) do if x == sc then idx = i; break end end
    if idx then
      local target = (idx - 2) * SECTION_HDR_H
      C_Timer.After(0, function()
        if not editorScroll then return end
        local range = editorScroll:GetVerticalScrollRange()
        editorScroll:SetVerticalScroll(math.max(0, math.min(range, target)))
      end)
    end
  end
end

local function makeSection(title, height, build)
  local sc = { title = title, height = height, open = false }
  local header = CreateFrame("Button", nil, bodyContainer)
  header:SetHeight(SECTION_HDR_H)
  local hover = header:CreateTexture(nil, "BACKGROUND"); hover:SetAllPoints(); hover:SetColorTexture(1, 1, 1, 0.05); hover:Hide()
  header:SetScript("OnEnter", function() hover:Show() end)
  header:SetScript("OnLeave", function() hover:Hide() end)
  local caret = header:CreateTexture(nil, "ARTWORK"); caret:SetTexture(UI.CARET)
  caret:SetVertexColor(COLOR.orange.r, COLOR.orange.g, COLOR.orange.b)
  caret:SetSize(9, 9); caret:SetPoint("LEFT", PAD, 0)
  local h = newText(header, FONT.head, 16, COLOR.purple, "LEFT")
  h:SetPoint("LEFT", caret, "RIGHT", 11, -1); h:SetText(title:upper())
  local div = header:CreateTexture(nil, "ARTWORK"); div:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a or 0.1)
  div:SetHeight(1); div:SetPoint("BOTTOMLEFT", 0, 0); div:SetPoint("BOTTOMRIGHT", 0, 0)
  local body = CreateFrame("Frame", nil, bodyContainer)
  body:SetHeight(height); body:Hide()
  sc.header, sc.caret, sc.body = header, caret, body
  header:SetScript("OnClick", function() toggleSection(sc) end)
  build(body, sc)
  sections[#sections + 1] = sc
  return sc
end


-- --------------------------------------------------------------------------
-- TEXTS: any number of text pieces per unit — a list, then the selected
-- piece's editor. The section's height follows the list.
-- --------------------------------------------------------------------------
local TEXT_ROW_H = 26
local EDITOR_H   = 780
local textSel = {}          -- per unit: the selected piece's index

local function TextList() local cfg = Cfg(); return cfg and cfg.texts or nil end
local function TextCfg()
  local list = TextList(); if not list then return nil end
  local i = textSel[selected] or 1
  return list[i], i
end
local function tget(field, default)
  return function() local tc = TextCfg(); return tc and orDefault(tc[field], default) end
end
local function tset(field)
  return function(v) local tc = TextCfg(); if tc then tc[field] = v; GU:ApplyLayout(selected) end end
end
local function CopyTable(v)
  if type(v) ~= "table" then return v end
  local t = {}; for k, x in pairs(v) do t[k] = CopyTable(x) end; return t
end
local function NewTextPiece(template)
  local t = CopyTable(GU.TEXT_DEFAULTS)
  t.template = template or "[name]"
  return t
end

local function textsSection(b, sc)
  local w = {}
  local listRows = {}

  local function selectPiece(i)
    textSel[selected] = i
    RefreshEditor()
  end

  local btnY = 0  -- set by refresh
  w.add = flatButton(b, 90, 22, COLOR.heroic, "+ Add text", 11); w.add:SetBase(0.2)
  w.dup = flatButton(b, 90, 22, COLOR.heroic, "Duplicate", 11);  w.dup:SetBase(0.2)
  w.del = flatButton(b, 90, 22, COLOR.heroic, "Delete", 11);     w.del:SetBase(0.2)
  w.add:SetScript("OnClick", function()
    local list = TextList(); if not list then return end
    list[#list + 1] = NewTextPiece("[name]")
    GU:ApplyLayout(selected); selectPiece(#list)
  end)
  w.dup:SetScript("OnClick", function()
    local list = TextList(); local tc, i = TextCfg()
    if not (list and tc) then return end
    local t = CopyTable(tc); t.y = (t.y or 0) - (t.size or 22) - 4
    table.insert(list, i + 1, t)
    GU:ApplyLayout(selected); selectPiece(i + 1)
  end)
  w.del:SetScript("OnClick", function()
    local list = TextList(); local tc, i = TextCfg()
    if not (list and tc) then return end
    table.remove(list, i)
    GU:ApplyLayout(selected); selectPiece(math.max(1, math.min(i, #list)))
  end)
  attachTip(w.add, "Add a text", "A new piece showing the unit's name, placed at the centre. Move it with Offset X / Y below.")
  attachTip(w.dup, "Duplicate", "A copy of the selected piece, one line lower.")

  -- The editor for the selected piece, anchored under the list.
  local ed = CreateFrame("Frame", nil, b)
  ed:SetPoint("TOPLEFT", 0, 0); ed:SetPoint("TOPRIGHT", 0, 0); ed:SetHeight(EDITOR_H)
  w.ed = ed

  w.enabled = toggleRow(ed, -4, "Show this text", tget("enabled", true), tset("enabled"))

  label(ed, "Template — words and [shortcodes], in any order", PAD, -36)
  local box = flatEditBox(ed, 100, 22)
  box:ClearAllPoints(); box:SetPoint("TOPLEFT", PAD, -52); box:SetPoint("TOPRIGHT", -PAD, -52); box:SetHeight(22)
  box:SetMaxLetters(200)
  local function commit(self)
    local tc = TextCfg(); if not tc then return end
    local v = self:GetText() or ""
    if v ~= tc.template then tc.template = v; GU:ApplyLayout(selected); sc.refresh() end
  end
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commit(self) end)
  box:HookScript("OnEditFocusLost", commit)
  box:SetScript("OnEscapePressed", function(self) local tc = TextCfg(); self:SetText(tc and tc.template or ""); self:ClearFocus() end)
  w.box = box

  -- The shortcode list, straight from the engine so it cannot drift.
  label(ed, "Shortcodes", PAD, -86, 12, COLOR.purple)
  local hy = -104
  for _, h in ipairs(GU.TEXT_HELP) do
    local code = newText(ed, FONT.body, 11, TEXT, "LEFT"); code:SetPoint("TOPLEFT", PAD, hy); code:SetText(h[1])
    local what = newText(ed, FONT.body, 11, MUTE, "LEFT"); what:SetPoint("TOPLEFT", PAD + 230, hy)
    what:SetPoint("TOPRIGHT", -PAD, hy); what:SetJustifyH("LEFT"); what:SetWordWrap(false); what:SetText(h[2])
    hy = hy - 14
  end
  hy = hy - 10

  label(ed, "Font", PAD, hy)
  w.font = UI.dropdown(ed, 220,
    function() local tc = TextCfg(); local f = tc and tc.font; return (f and f ~= "") and f or "Suite default (Khand)" end,
    function()
      local opts = { { label = "Suite default (Khand)", value = "" } }
      local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
      if lsm then for _, name in ipairs(lsm:List("font")) do opts[#opts + 1] = { label = name, value = name } end end
      return opts
    end,
    function() local tc = TextCfg(); return tc and tc.font or "" end,
    function(v) local tc = TextCfg(); if tc then tc.font = (v ~= "") and v or nil; GU:ApplyLayout(selected) end end)
  w.font:SetPoint("TOPRIGHT", -PAD, hy + 3)
  hy = hy - 32
  w.size = numRow(ed, hy, "Size", 6, 72, tget("size", 22), tset("size"))
  hy = hy - 48
  label(ed, "Outline", PAD, hy)
  w.outline = choiceRow(ed, {
    { "none", "None" }, { "thin", "Thin" }, { "thick", "Thick" },
  }, 70, 20, 80, hy + 2, 6, function(v) tset("outline")(v); sc.refresh() end)
  hy = hy - 28
  w.shadow = toggleRow(ed, hy, "Drop shadow", tget("shadow", true), tset("shadow"))
  hy = hy - 32
  w.color = colorRow(ed, hy, "Color", tget("color"), tset("color"), nil, "Unit Frames › text color")
  hy = hy - 28
  w.classColor = toggleRow(ed, hy, "Use the unit's class color", tget("classColor", false), tset("classColor"),
    "A player's class color; for an NPC, hostile red, neutral yellow, friendly green — instead of the Color above.")
  hy = hy - 36
  w.x = numRow(ed, hy, "Offset X", -800, 800, tget("x", 0), tset("x"))
  hy = hy - 46
  w.y = numRow(ed, hy, "Offset Y", -800, 800, tget("y", 0), tset("y"))
  hy = hy - 48
  label(ed, "Align", PAD, hy)
  w.justify = choiceRow(ed, {
    { "LEFT", "Left", "The text grows to the right from its offset." },
    { "CENTER", "Center", "The text is centred on its offset." },
    { "RIGHT", "Right", "The text grows to the left from its offset." },
  }, 70, 20, 80, hy + 2, 6, function(v) tset("justify")(v); sc.refresh() end)
  hy = hy - 30
  w.maxWidth = numRow(ed, hy, "Max width", 0, 600, tget("maxWidth", 0), tset("maxWidth"),
    "px — longer text is cut with …  (0 = no limit)")
  hy = hy - 52
  w.level = numRow(ed, hy, "Layer", 0, 100, tget("level", 70), tset("level"),
    "higher draws on top — the rings sit at 1–64 (health 1–16, power 17–32, resource 33–48, cast 49–64)")

  function sc.refresh()
    local list = TextList()
    if not list then return end
    local n = #list
    if (textSel[selected] or 1) > n then textSel[selected] = n end
    local cur = textSel[selected] or 1
    -- the list
    for i = 1, n do
      local row = listRows[i]
      if not row then
        row = CreateFrame("Button", nil, b)
        row:SetHeight(TEXT_ROW_H)
        row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints()
        row.sel:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.28)
        local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.07)
        row.num = newText(row, FONT.body, 11, MUTE, "LEFT"); row.num:SetPoint("LEFT", 8, 0)
        row.text = newText(row, FONT.body, 12, TEXT, "LEFT")
        row.text:SetPoint("LEFT", 30, 0); row.text:SetPoint("RIGHT", -8, 0); row.text:SetWordWrap(false)
        listRows[i] = row
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", PAD - 8, -8 - (i - 1) * TEXT_ROW_H); row:SetPoint("TOPRIGHT", -PAD + 8, -8 - (i - 1) * TEXT_ROW_H)
      row.num:SetText(tostring(i))
      local tc = list[i]
      local tpl = tc.template or ""
      row.text:SetText(tpl ~= "" and tpl or "(empty)")
      row.text:SetTextColor(tc.enabled == false and MUTE.r or TEXT.r, tc.enabled == false and MUTE.g or TEXT.g, tc.enabled == false and MUTE.b or TEXT.b)
      row.sel:SetShown(i == cur)
      row:SetScript("OnClick", function() selectPiece(i) end)
      row:Show()
    end
    for i = n + 1, #listRows do listRows[i]:Hide() end
    btnY = -8 - n * TEXT_ROW_H - 6
    w.add:ClearAllPoints(); w.add:SetPoint("TOPLEFT", PAD, btnY)
    w.dup:ClearAllPoints(); w.dup:SetPoint("LEFT", w.add, "RIGHT", 6, 0)
    w.del:ClearAllPoints(); w.del:SetPoint("LEFT", w.dup, "RIGHT", 6, 0)
    w.dup:SetEnabled(n > 0); w.del:SetEnabled(n > 0)
    -- the editor
    local tc = list[cur]
    ed:ClearAllPoints(); ed:SetPoint("TOPLEFT", 0, btnY - 34); ed:SetPoint("TOPRIGHT", 0, btnY - 34)
    ed:SetShown(tc ~= nil)
    sc.height = -(btnY - 34) + (tc and EDITOR_H or 0) + 8
    b:SetHeight(sc.height)
    if not tc then return end
    w.enabled:refresh()
    if not w.box:HasFocus() then w.box:SetText(tc.template or "") end
    w.font:refresh(); w.size:refresh()
    w.outline.sync(tc.outline or "none"); w.shadow:refresh()
    w.color:refresh(); w.classColor:refresh()
    w.x:refresh(); w.y:refresh(); w.justify.sync(tc.justify or "CENTER")
    w.maxWidth:refresh(); w.level:refresh()
  end
end


-- --------------------------------------------------------------------------
-- AURAS: any number of aura groups per unit — a list, then the selected
-- group's editor. Same bones as the Texts section.
-- --------------------------------------------------------------------------
local AURA_EDITOR_H = 730
local auraSel = {}

local function AuraList() local cfg = Cfg(); return cfg and cfg.auras or nil end
local function AuraCfg()
  local list = AuraList(); if not list then return nil end
  local i = auraSel[selected] or 1
  return list[i], i
end
local function aget(field, default)
  return function() local ac = AuraCfg(); return ac and orDefault(ac[field], default) end
end
local function aset(field)
  return function(v) local ac = AuraCfg(); if ac then ac[field] = v; GU:ApplyLayout(selected) end end
end
local function NewAuraGroup(kind)
  local t = CopyTable(GU.AURA_DEFAULTS)
  t.kind = kind or "buffs"
  return t
end

local function aurasSection(b, sc)
  local w = {}
  local listRows = {}
  local function selectGroup(i) auraSel[selected] = i; RefreshEditor() end

  w.add = flatButton(b, 110, 22, COLOR.heroic, "+ Add group", 11); w.add:SetBase(0.2)
  w.dup = flatButton(b, 90, 22, COLOR.heroic, "Duplicate", 11);    w.dup:SetBase(0.2)
  w.del = flatButton(b, 90, 22, COLOR.heroic, "Delete", 11);       w.del:SetBase(0.2)
  w.add:SetScript("OnClick", function()
    local list = AuraList(); if not list then return end
    list[#list + 1] = NewAuraGroup(selected == "target" and "mydebuffs" or "buffs")
    GU:ApplyLayout(selected); selectGroup(#list)
  end)
  w.dup:SetScript("OnClick", function()
    local list = AuraList(); local ac, i = AuraCfg()
    if not (list and ac) then return end
    local t = CopyTable(ac); t.y = (t.y or 0) - (t.size or 28) - 6
    table.insert(list, i + 1, t)
    GU:ApplyLayout(selected); selectGroup(i + 1)
  end)
  w.del:SetScript("OnClick", function()
    local list = AuraList(); local ac, i = AuraCfg()
    if not (list and ac) then return end
    table.remove(list, i)
    GU:ApplyLayout(selected); selectGroup(math.max(1, math.min(i, #list)))
  end)
  attachTip(w.add, "Add an aura group", "A new row of icons at the centre of the frame. Move it with Offset X / Y below.")

  local ed = CreateFrame("Frame", nil, b)
  ed:SetPoint("TOPLEFT", 0, 0); ed:SetPoint("TOPRIGHT", 0, 0); ed:SetHeight(AURA_EDITOR_H)

  w.enabled = toggleRow(ed, -4, "Show this group", aget("enabled", true), aset("enabled"))
  local hy = -36
  label(ed, "Show", PAD, hy)
  w.kind = UI.dropdown(ed, 220,
    function() local ac = AuraCfg(); return ac and GU.AURA_KIND_LABEL[ac.kind] or "?" end,
    function()
      local opts = {}
      for _, k in ipairs(GU.AURA_KINDS) do opts[#opts + 1] = { label = k[2], value = k[1] } end
      return opts
    end,
    function() local ac = AuraCfg(); return ac and ac.kind end,
    function(v) aset("kind")(v); sc.refresh() end)
  w.kind:SetPoint("TOPRIGHT", -PAD, hy + 3)
  attachTip(w.kind, "What this group shows",
    "\"My\" = only what you cast. Dispellable = debuffs your class can remove. Stealable = buffs you could purge or spellsteal. Which auras count is decided by the game, so it matches Blizzard's own frames.")
  hy = hy - 32
  -- kind "spell": which spell, its silhouette and its effect. These rows share
  -- the vertical space of the list-kind rows (max / spacing / per row / grow).
  local spellY = hy
  w.spellLab = label(ed, "Spell — its ID, or a name the game knows", PAD, spellY)
  w.spellBox = flatEditBox(ed, 100, 22)
  w.spellBox:ClearAllPoints(); w.spellBox:SetPoint("TOPLEFT", PAD, spellY - 16); w.spellBox:SetPoint("TOPRIGHT", -PAD, spellY - 16); w.spellBox:SetHeight(22)
  w.spellBox:SetMaxLetters(80)
  w.spellNote = newText(ed, FONT.body, 10.5, MUTE, "LEFT"); w.spellNote:SetPoint("TOPLEFT", PAD, spellY - 42)
  w.spellNote:SetPoint("TOPRIGHT", -PAD, spellY - 42); w.spellNote:SetJustifyH("LEFT"); w.spellNote:SetWordWrap(false)
  local function commitSpell(self)
    local ac = AuraCfg(); if not ac then return end
    local id, name = GU:ResolveSpell(self:GetText())
    if id then
      if id ~= ac.spellID then ac.spellID, ac.spellName = id, name; GU:ApplyLayout(selected) end
    else
      ac.spellID, ac.spellName = 0, nil; GU:ApplyLayout(selected)
    end
    sc.refresh()
  end
  w.spellBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commitSpell(self) end)
  w.spellBox:HookScript("OnEditFocusLost", commitSpell)
  w.spellBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); sc.refresh() end)
  local function shapeDropdown(y)
    local dd = UI.dropdown(ed, 220,
    function() local ac = AuraCfg(); local hub = GloomsHub; local k = ac and ac.shape
      return (k and hub.SHAPES and hub.SHAPES[k] and hub.SHAPES[k].label) or "Square (none)" end,
    function()
      local opts = { { label = "Square (none)", value = "" } }
      local hub = GloomsHub
      for _, k in ipairs(hub.SHAPE_ORDER or {}) do opts[#opts + 1] = { label = hub.SHAPES[k].label, value = k } end
      return opts
    end,
    function() local ac = AuraCfg(); return ac and ac.shape or "" end,
    function(v) local ac = AuraCfg(); if ac then ac.shape = (v ~= "") and v or nil; if not ac.shape then ac.effect = nil end; GU:ApplyLayout(selected); sc.refresh() end end)
    dd:SetPoint("TOPRIGHT", -PAD, y + 3)
    attachTip(dd, "Shape", "The suite's silhouettes — the same catalog Gloom's Bars and Gloom's Auras draw with. The cooldown swipe follows the shape. An effect needs a shape to trace.")
    return dd
  end
  w.shapeLab = label(ed, "Shape", PAD, spellY - 66)
  w.shape = shapeDropdown(spellY - 66)
  w.effectLab = label(ed, "Effect", PAD, spellY - 96)
  w.effect = UI.dropdown(ed, 220,
    function() local ac = AuraCfg(); local E = GloomsHub.Effects; local m = ac and ac.effect and E and E:Get(ac.effect)
      return m and m.label or "None" end,
    function()
      local opts = { { label = "None", value = "" } }
      local E = GloomsHub.Effects
      if E then E:Each(function(mod) opts[#opts + 1] = { label = mod.label, value = mod.id } end) end
      return opts
    end,
    function() local ac = AuraCfg(); return ac and ac.effect or "" end,
    function(v) local ac = AuraCfg(); if ac then ac.effect = (v ~= "") and v or nil; GU:ApplyLayout(selected); sc.refresh() end end)
  w.effect:SetPoint("TOPRIGHT", -PAD, spellY - 93)
  w.spellRows = { w.spellLab, w.spellBox, w.spellNote, w.shapeLab, w.shape, w.effectLab, w.effect }

  -- The effect's own settings, from its schema (CONTRACTS §8): one block per
  -- module, built on first use, only the current module's block shown. Sits
  -- under the standard rows; the editor grows by PARAM_BLOCK_H for it.
  local PARAM_BLOCK_H = 230
  local paramBlocks = {}
  w.paramLab = label(ed, "Effect settings", PAD, -AURA_EDITOR_H - 4, 12, COLOR.purple)
  local function pget(id, key)
    return function()
      local ac = AuraCfg(); if not ac then return nil end
      local saved = ac.effectParams and ac.effectParams[id]
      if saved and saved[key] ~= nil then return saved[key] end
      local E = GloomsHub.Effects; local m = E and E:MergeParams(id, nil)
      return m and m[key]
    end
  end
  local function pset(id, key)
    return function(v)
      local ac = AuraCfg(); if not ac then return end
      ac.effectParams = ac.effectParams or {}; ac.effectParams[id] = ac.effectParams[id] or {}
      ac.effectParams[id][key] = v
      GU:ApplyLayout(selected)
    end
  end
  local function paramBlock(id)
    if paramBlocks[id] then return paramBlocks[id] end
    local E = GloomsHub.Effects; local mod = E and E:Get(id)
    local blk = CreateFrame("Frame", nil, ed); blk:SetAllPoints(ed)
    local rows = {}
    local y = -AURA_EDITOR_H - 24
    for _, prm in ipairs(mod and mod.params or {}) do
      local kind = prm.kind
      if kind == "color" then
        rows[#rows + 1] = colorRow(blk, y, prm.label == "Colour" and "Color" or prm.label, pget(id, prm.key), pset(id, prm.key), nil,
          "Unit Frames › aura effect " .. prm.key)
        y = y - 28
      elseif kind == "range" then
        local dec = (prm.step or 1) < 1
        rows[#rows + 1] = sliderRow(blk, y, prm.label, prm.min, prm.max, prm.step or 1, pget(id, prm.key), pset(id, prm.key),
          function(v) return dec and ("%.2f"):format(v) or tostring(math.floor(v + 0.5)) end)
        y = y - 46
      elseif kind == "bispeed" then
        local neg, pos = prm.neg or "CCW", prm.pos or "CW"
        local g, st = pget(id, prm.key), pset(id, prm.key)
        rows[#rows + 1] = sliderRow(blk, y, prm.label, -100, 100, 5,
          function() return math.floor((g() or 0) * 100 + 0.5) end,
          function(v) st(v / 100) end,
          function(v) if v == 0 then return "still" end return (v < 0 and neg or pos) .. " " .. math.abs(math.floor(v + 0.5)) .. "%" end,
          "direction and speed — left of centre is " .. neg .. ", right is " .. pos)
        y = y - 60
      elseif kind == "choice" then
        label(blk, prm.label, PAD, y)
        local choices = {}
        for _, c in ipairs(prm.choices or {}) do choices[#choices + 1] = { c[1], c[2] or c[1] } end
        local cr = choiceRow(blk, choices, 70, 20, 100, y + 2, 6, function(v) pset(id, prm.key)(v) end)
        rows[#rows + 1] = { refresh = function() cr.sync(pget(id, prm.key)()) end }
        y = y - 30
      end
    end
    blk.rows = rows
    paramBlocks[id] = blk
    return blk
  end
  w.paramBlock = function(id)
    for k, blk in pairs(paramBlocks) do blk:SetShown(k == id) end
    if not id then return nil end
    local blk = paramBlock(id); blk:Show()
    for _, r in ipairs(blk.rows) do if r.refresh then r:refresh() end end
    return blk
  end
  w.PARAM_BLOCK_H = PARAM_BLOCK_H

  -- FILTERS for the Buffs / Debuffs kinds: the engine-decided classes in two
  -- columns, each an Any / Only / Never tri-state, then "only these spells"
  -- and "never these spells". One block per polarity, shown for the current
  -- kind, under the standard rows (same slot the effect settings use).
  local FILTER_ROW_H = 24
  local filterBlocks = {}
  w.filterLab = label(ed, "Filters", PAD, -AURA_EDITOR_H - 4, 12, COLOR.purple)
  local function classMode(key)
    local ac = AuraCfg(); return ac and ac.filter and ac.filter.classes and ac.filter.classes[key] or nil
  end
  local function setClass(key, mode)
    local ac = AuraCfg(); if not ac then return end
    ac.filter = ac.filter or {}; ac.filter.classes = ac.filter.classes or {}
    ac.filter.classes[key] = mode
    GU:ApplyLayout(selected)
  end
  local function triRow(col, y, cls)
    local lab = newText(col, FONT.body, 11.5, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 4, y); lab:SetText(cls.label)
    local btns = {}
    local prev
    for _, opt in ipairs({ { "never", "Never" }, { "only", "Only" }, { nil, "Any" } }) do
      local b = flatButton(col, 40, 17, COLOR.heroic, opt[2], 10); b:SetBase(0.2)
      if prev then b:SetPoint("RIGHT", prev, "LEFT", -2, 0) else b:SetPoint("TOPRIGHT", col, "TOPRIGHT", -4, y + 1) end
      b:SetScript("OnClick", function() setClass(cls.key, opt[1]); for _, e in ipairs(btns) do e.b:SetActive(e.v == opt[1]) end end)
      btns[#btns + 1] = { b = b, v = opt[1] }
      prev = b
    end
    lab:SetPoint("RIGHT", prev, "LEFT", -6, 0); lab:SetWordWrap(false)
    return { refresh = function() local m = classMode(cls.key); for _, e in ipairs(btns) do e.b:SetActive(e.v == m) end end }
  end
  local function spellListBox(parent, y, title, field)
    label(parent, title, 4, y, 11.5)
    local box = flatEditBox(parent, 100, 20)
    box:ClearAllPoints(); box:SetPoint("TOPLEFT", 4, y - 16); box:SetPoint("TOPRIGHT", -4, y - 16); box:SetHeight(20)
    box:SetMaxLetters(400)
    local function commit(self)
      local ac = AuraCfg(); if not ac then return end
      ac.filter = ac.filter or {}
      local ids, missed = {}, {}
      for part in (self:GetText() or ""):gmatch("[^,]+") do
        local id = GU:ResolveSpell(part)
        if id then ids[#ids + 1] = id elseif part:match("%S") then missed[#missed + 1] = part:match("^%s*(.-)%s*$") end
      end
      ac.filter[field] = ids
      ac.filter[field .. "Missed"] = (#missed > 0) and table.concat(missed, ", ") or nil
      GU:ApplyLayout(selected); sc.refresh()
    end
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commit(self) end)
    box:HookScript("OnEditFocusLost", commit)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); sc.refresh() end)
    local note = newText(parent, FONT.body, 10, MUTE, "LEFT"); note:SetPoint("TOPLEFT", 4, y - 38); note:SetPoint("TOPRIGHT", -4, y - 38)
    note:SetJustifyH("LEFT"); note:SetWordWrap(false)
    return { refresh = function()
      local ac = AuraCfg(); if not ac then return end
      local ids = ac.filter and ac.filter[field] or {}
      if not box:HasFocus() then
        local names = {}
        for _, id in ipairs(ids) do local info = C_Spell.GetSpellInfo(id); names[#names + 1] = info and info.name or tostring(id) end
        box:SetText(table.concat(names, ", "))
      end
      local missed = ac.filter and ac.filter[field .. "Missed"]
      note:SetText(missed and ("not found: " .. missed) or (#ids == 0 and "names or IDs, comma-separated" or (#ids .. " spell" .. (#ids == 1 and "" or "s"))))
    end }
  end
  local function filterBlock(pol)
    if filterBlocks[pol] then return filterBlocks[pol] end
    local blk = CreateFrame("Frame", nil, ed); blk:SetAllPoints(ed)
    local rows = {}
    local top = -AURA_EDITOR_H - 24
    rows[#rows + 1] = toggleRow(blk, top, "Only timed auras (hide permanent ones)",
      function() local ac = AuraCfg(); return ac and ac.filter and ac.filter.timed end,
      function(v) local ac = AuraCfg(); if ac then ac.filter = ac.filter or {}; ac.filter.timed = v; GU:ApplyLayout(selected) end end)
    top = top - 30
    local col1 = CreateFrame("Frame", nil, blk); col1:SetPoint("TOPLEFT", PAD - 4, top); col1:SetPoint("TOPRIGHT", ed, "TOP", -6, top); col1:SetHeight(10)
    local col2 = CreateFrame("Frame", nil, blk); col2:SetPoint("TOPLEFT", ed, "TOP", 6, top); col2:SetPoint("TOPRIGHT", -PAD + 4, top); col2:SetHeight(10)
    local list = {}
    for _, c in ipairs(GU.AURA_CLASSES) do if c.pol == "both" or c.pol == pol then list[#list + 1] = c end end
    local perCol = math.ceil(#list / 2)
    for i, c in ipairs(list) do
      local col = (i <= perCol) and col1 or col2
      local y = -((i - 1) % perCol) * FILTER_ROW_H
      rows[#rows + 1] = triRow(col, y, c)
    end
    top = top - perCol * FILTER_ROW_H - 6
    local c1y = top
    local sl1 = CreateFrame("Frame", nil, blk); sl1:SetPoint("TOPLEFT", PAD - 4, c1y); sl1:SetPoint("TOPRIGHT", ed, "TOP", -6, c1y); sl1:SetHeight(10)
    local sl2 = CreateFrame("Frame", nil, blk); sl2:SetPoint("TOPLEFT", ed, "TOP", 6, c1y); sl2:SetPoint("TOPRIGHT", -PAD + 4, c1y); sl2:SetHeight(10)
    rows[#rows + 1] = spellListBox(sl1, 0, "Only these spells", "only")
    rows[#rows + 1] = spellListBox(sl2, 0, "Never these spells", "never")
    blk.rows = rows
    blk.height = 24 + 30 + perCol * FILTER_ROW_H + 6 + 56
    filterBlocks[pol] = blk
    return blk
  end
  w.filterBlock = function(pol)
    for k, blk in pairs(filterBlocks) do blk:SetShown(k == pol) end
    if not pol then return nil end
    local blk = filterBlock(pol); blk:Show()
    for _, r in ipairs(blk.rows) do if r.refresh then r:refresh() end end
    return blk
  end

  w.max = numRow(ed, hy, "Max icons", 1, 40, aget("max", 8), aset("max"))
  hy = hy - 46
  w.spacing = numRow(ed, hy, "Spacing", 0, 20, aget("spacing", 3), aset("spacing"))
  hy = hy - 46
  w.perLine = numRow(ed, hy, "Icons per row", 1, 40, aget("perLine", 8), aset("perLine"),
    "the row wraps after this many; set it to 1 for a column")
  hy = hy - 52
  w.growLab = label(ed, "Grow", PAD, hy)
  w.growFrame = CreateFrame("Frame", nil, ed); w.growFrame:SetAllPoints(ed)
  w.growH = choiceRow(w.growFrame, {
    { "RIGHT", "Right", "New icons appear to the right." },
    { "LEFT",  "Left",  "New icons appear to the left." },
  }, 70, 20, 80, hy + 2, 6, function(v) aset("growH")(v); sc.refresh() end)
  w.growV = choiceRow(w.growFrame, {
    { "UP",   "Up",   "Extra rows stack upward." },
    { "DOWN", "Down", "Extra rows stack downward." },
  }, 70, 20, 80 + 2 * 76 + 10, hy + 2, 6, function(v) aset("growV")(v); sc.refresh() end)
  hy = hy - 30
  w.orderLab = label(ed, "Order", PAD, hy)
  w.orderFrame = CreateFrame("Frame", nil, ed); w.orderFrame:SetAllPoints(ed)
  w.order = choiceRow(w.orderFrame, {
    { "default",      "Default",        "The game's own order." },
    { "expiring",     "Expiring first", "The aura with the least time left comes first." },
    { "expiringLast", "Expiring last",  "The aura with the most time left comes first." },
  }, 96, 20, 80, hy + 2, 6, function(v) aset("sort")(v); sc.refresh() end)
  hy = hy - 32
  w.size = numRow(ed, hy, "Icon size", 10, 96, aget("size", 28), aset("size"))
  hy = hy - 46
  w.x = numRow(ed, hy, "Offset X", -800, 800, aget("x", 0), aset("x"))
  hy = hy - 46
  w.y = numRow(ed, hy, "Offset Y", -800, 800, aget("y", 0), aset("y"),
    "the first icon's corner sits here; the group grows away from it")
  hy = hy - 56
  w.durOn = toggleRow(ed, hy, "Countdown text", aget("showDuration", true),
    function(v) aset("showDuration")(v); sc.refresh() end)
  hy = hy - 28
  w.durSize = numRow(ed, hy, "Countdown size", 6, 32, aget("durationSize", 11), aset("durationSize"))
  hy = hy - 46
  w.stackOn = toggleRow(ed, hy, "Stack count", aget("showStacks", true),
    function(v) aset("showStacks")(v); sc.refresh() end)
  hy = hy - 28
  w.stackSize = numRow(ed, hy, "Stack size", 6, 32, aget("stackSize", 11), aset("stackSize"))
  hy = hy - 46
  w.swipe = toggleRow(ed, hy, "Cooldown swipe", aget("swipe", true), aset("swipe"),
    "A dark sweep across the icon as the aura runs down. Drawn by the game engine.")
  hy = hy - 28
  w.border = toggleRow(ed, hy, "Dark edge", aget("border", true), aset("border"))
  hy = hy - 30
  w.shapeLab2 = label(ed, "Shape", PAD, hy)
  w.shape2 = shapeDropdown(hy)
  hy = hy - 34
  w.level = numRow(ed, hy, "Layer", 0, 100, aget("level", 60), aset("level"),
    "higher draws on top — the rings sit at 1–64")

  function sc.refresh()
    local list = AuraList()
    if not list then return end
    local n = #list
    if (auraSel[selected] or 1) > n then auraSel[selected] = n end
    local cur = auraSel[selected] or 1
    for i = 1, n do
      local row = listRows[i]
      if not row then
        row = CreateFrame("Button", nil, b)
        row:SetHeight(TEXT_ROW_H)
        row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints()
        row.sel:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.28)
        local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.07)
        row.num = newText(row, FONT.body, 11, MUTE, "LEFT"); row.num:SetPoint("LEFT", 8, 0)
        row.text = newText(row, FONT.body, 12, TEXT, "LEFT")
        row.text:SetPoint("LEFT", 30, 0); row.text:SetPoint("RIGHT", -8, 0); row.text:SetWordWrap(false)
        listRows[i] = row
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", PAD - 8, -8 - (i - 1) * TEXT_ROW_H); row:SetPoint("TOPRIGHT", -PAD + 8, -8 - (i - 1) * TEXT_ROW_H)
      row.num:SetText(tostring(i))
      local ac = list[i]
      if ac.kind == "spell" then
        row.text:SetText("This spell  ·  " .. (ac.spellName or ((ac.spellID or 0) > 0 and tostring(ac.spellID)) or "(none set)") .. "  ·  " .. tostring(ac.size or 28) .. "px")
      else
        row.text:SetText((GU.AURA_KIND_LABEL[ac.kind] or ac.kind or "?") .. "  ·  up to " .. tostring(ac.max or 8) .. " at " .. tostring(ac.size or 28) .. "px")
      end
      local off = ac.enabled == false
      row.text:SetTextColor(off and MUTE.r or TEXT.r, off and MUTE.g or TEXT.g, off and MUTE.b or TEXT.b)
      row.sel:SetShown(i == cur)
      row:SetScript("OnClick", function() selectGroup(i) end)
      row:Show()
    end
    for i = n + 1, #listRows do listRows[i]:Hide() end
    local btnY = -8 - n * TEXT_ROW_H - 6
    w.add:ClearAllPoints(); w.add:SetPoint("TOPLEFT", PAD, btnY)
    w.dup:ClearAllPoints(); w.dup:SetPoint("LEFT", w.add, "RIGHT", 6, 0)
    w.del:ClearAllPoints(); w.del:SetPoint("LEFT", w.dup, "RIGHT", 6, 0)
    w.dup:SetEnabled(n > 0); w.del:SetEnabled(n > 0)
    local ac = list[cur]
    ed:ClearAllPoints(); ed:SetPoint("TOPLEFT", 0, btnY - 34); ed:SetPoint("TOPRIGHT", 0, btnY - 34)
    ed:SetShown(ac ~= nil)
    local isSpell = ac and ac.kind == "spell"
    local withParams = isSpell and ac.effect ~= nil
    local pol = ac and not isSpell and ((ac.kind == "buffs") and "buff" or "debuff") or nil
    local fblk = w.filterBlock(pol)
    w.filterLab:SetShown(fblk ~= nil)
    local edH = AURA_EDITOR_H + (withParams and w.PARAM_BLOCK_H or 0) + (fblk and fblk.height or 0)
    ed:SetHeight(edH)
    sc.height = -(btnY - 34) + (ac and edH or 0) + 8
    b:SetHeight(sc.height)
    if not ac then return end
    w.enabled:refresh(); w.kind:refresh()
    for _, r in ipairs(w.spellRows) do r:SetShown(isSpell) end
    w.paramLab:SetShown(withParams)
    w.paramBlock(withParams and ac.effect or nil)
    w.max:show(not isSpell); w.spacing:show(not isSpell); w.perLine:show(not isSpell)
    w.growFrame:SetShown(not isSpell); w.growLab:SetShown(not isSpell)
    w.orderFrame:SetShown(not isSpell); w.orderLab:SetShown(not isSpell)
    w.order.sync(ac.sort or "default")
    w.border:show(not ac.shape)
    w.shapeLab2:SetShown(not isSpell); w.shape2:SetShown(not isSpell); w.shape2:refresh()
    if isSpell then
      if not w.spellBox:HasFocus() then w.spellBox:SetText(ac.spellName or ((ac.spellID or 0) > 0 and tostring(ac.spellID)) or "") end
      if (ac.spellID or 0) > 0 then w.spellNote:SetText(("ID %d — %s. Shows while this aura is on the %s."):format(ac.spellID, ac.spellName or "?", selected == "target" and "target" or "you"))
      else w.spellNote:SetText("No spell set. Type an ID (from Wowhead) or the name of one of your own spells, then Enter.") end
      w.shape:refresh(); w.effect:refresh()
    end
    w.max:refresh(); w.size:refresh(); w.spacing:refresh(); w.perLine:refresh()
    w.growH.sync(ac.growH or "RIGHT"); w.growV.sync(ac.growV or "UP")
    w.x:refresh(); w.y:refresh()
    w.durOn:refresh(); w.durSize:refresh(); w.durSize:show(ac.showDuration ~= false)
    w.stackOn:refresh(); w.stackSize:refresh(); w.stackSize:show(ac.showStacks ~= false)
    w.swipe:refresh(); w.border:refresh(); w.level:refresh()
  end
end

local function BuildEditor(p)
  bodyContainer = CreateFrame("Frame", nil, p)
  bodyContainer:SetPoint("TOPLEFT", 0, 0); bodyContainer:SetPoint("TOPRIGHT", 0, 0)

  E.posSec = makeSection("Position", 110, function(b, sc)
    E.xRow = numRow(b, -12, "X", -700, 700, num("x", 0), setUnit("x"))
    E.yRow = numRow(b, -56, "Y", -400, 400, num("y", 0), setUnit("y"))
    sc.refresh = function() E.xRow:refresh(); E.yRow:refresh() end
  end)

  E.layerSec = makeSection("Layer", 126, function(b, sc)
    E.strata = choiceRow(b, STRATA, 88, 20, PAD, -12, 4, function(v) GU:SetStrata(selected, v) end)
    E.level = numRow(b, -44, "Level within the layer", 0, 200, num("level", 10), setUnit("level"),
      "higher draws in front — use it to tuck a ring behind or in front of an overlay on the same layer")
    sc.refresh = function()
      local cfg = Cfg(); if not cfg then return end
      E.strata.sync(cfg.strata or "MEDIUM"); E.level:refresh()
    end
  end)

  E.visSec = makeSection("Visibility", 62, function(b, sc)
    E.cond = choiceRow(b, {
      { "always",           "Always",           "Always shown (the target ring still needs a target)." },
      { "combat",           "In combat",        "Only while you are in combat." },
      { "target",           "Target selected",  "Only while you have a target." },
      { "combat_or_target", "Combat or target", "While in combat OR while you have a target." },
    }, 120, 20, PAD, -12, 6, function(v) GU:SetCondition(selected, v); RefreshList() end)
    sc.refresh = function() local cfg = Cfg(); if cfg then E.cond.sync(cfg.showCondition or "always") end end
  end)

  E.textsSec = makeSection("Texts", 300, function(b, sc) textsSection(b, sc) end)
  E.aurasSec = makeSection("Auras", 300, function(b, sc) aurasSection(b, sc) end)

  -- The ring bodies keep their original y offsets (content from -42), so the
  -- body is anchored 30px up: the header row already provides that space.
  local function ringBody(title, key, kind, height)
    return makeSection(title, height, function(b, sc)
      local inner = CreateFrame("Frame", nil, b)
      inner:SetPoint("TOPLEFT", 0, 30); inner:SetPoint("TOPRIGHT", 0, 30); inner:SetHeight(height + 30)
      local sec = ringSection(inner, key, title, kind)
      sc.refresh = function() sec:refresh() end
      sc.ring = sec
    end)
  end
  E.healthSec   = ringBody("Health ring",         "health",   "health",   990)
  E.powerSec    = ringBody("Power ring",          "power",    "power",    756)
  E.resourceSec = ringBody("Class resource ring", "resource", "resource", 780)
  E.castSec     = ringBody("Cast ring",           "cast",     "cast",     900)

  E.posSec.open = true
  relayout()
end

RefreshEditor = function()
  local cfg = Cfg()
  if not cfg then
    if editorBody then editorBody:Hide() end
    if E.editorBar then E.editorBar:Hide() end
    if emptyNote then emptyNote:Show() end
    return
  end
  if emptyNote then emptyNote:Hide() end
  editorBody:Show(); E.editorBar:Show()
  E.resourceSec.hidden = (cfg.rings.resource == nil)
  if E.resourceSec.hidden and E.resourceSec.open then E.resourceSec.open = false; E.posSec.open = true end
  for _, sc in ipairs(sections) do if sc.open and sc.refresh then sc.refresh() end end
  relayout()
end

SelectUnit = function(which)
  selected = which
  if container and container:IsVisible() then GU:SetEditing(which) end
  RefreshEditor(); RefreshList()
  if editorScroll then editorScroll:SetVerticalScroll(0) end
  syncCastPreview()
end

-- --------------------------------------------------------------------------
-- The tab
-- --------------------------------------------------------------------------
local function BuildTab(c)
  container = c
  BuildRail(c)

  local vdiv = c:CreateTexture(nil, "ARTWORK")
  vdiv:SetColorTexture(COLOR.rim.r, COLOR.rim.g, COLOR.rim.b, COLOR.rim.a or 0.1)
  vdiv:SetWidth(1)
  vdiv:SetPoint("TOPLEFT", RAIL_W, 0); vdiv:SetPoint("BOTTOMLEFT", RAIL_W, 0)

  editorScroll = CreateFrame("ScrollFrame", nil, c)
  editorScroll:SetPoint("TOPLEFT", RAIL_W + 1, -1)
  editorScroll:SetPoint("BOTTOMRIGHT", -10, 1)
  editorScroll:EnableMouseWheel(true)
  editorScroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 42)))
  end)
  editorChild = CreateFrame("Frame", nil, editorScroll)
  editorChild:SetSize(math.max(10, editorScroll:GetWidth()), 10)
  editorScroll:SetScrollChild(editorChild)
  editorScroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then editorChild:SetWidth(w) end end)
  E.editorBar = makeScrollbar(c, editorScroll, function(b)
    b:SetPoint("TOPRIGHT", -4, -2); b:SetPoint("BOTTOMRIGHT", -4, 2)
  end)

  editorBody = CreateFrame("Frame", nil, editorChild)
  editorBody:SetAllPoints()
  BuildEditor(editorBody)
  editorBody:Hide()

  emptyNote = newText(c, FONT.body, 12, MUTE, "CENTER")
  emptyNote:SetPoint("CENTER", editorScroll, "CENTER", 0, 0)
  emptyNote:SetText("Select Player or Target on the left to edit that frame.")

  c:HookScript("OnShow", function()
    if selected then GU:SetEditing(selected) end
    RefreshEditor(); RefreshList()
    syncCastPreview()
  end)
  c:HookScript("OnHide", function()
    GU:SetEditing(nil)
    syncCastPreview()
  end)

  GU:OnChange(function(what, which)
    if which ~= selected then return end
    if what == "position" and E.xRow then E.xRow:refresh(); E.yRow:refresh() end
  end)

  SelectUnit("player")
end

-- Order 50: after Portraits (40), before Media (90).
GloomsHub:RegisterTab{
  id    = "unitframes",
  title = "UNIT FRAMES",
  order = 50,
  build = BuildTab,
}
