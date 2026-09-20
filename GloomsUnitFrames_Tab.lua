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
  local isPower, isResource, isCast = kind == "power", kind == "resource", kind == "cast"
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
  if isPower then
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

  E.textSec = makeSection("Center text", 106, function(b, sc)
    E.textOn = toggleRow(b, -12, "Show health percent in the middle",
      function() local c = Cfg(); return c and c.text.enabled end,
      function(v) local c = Cfg(); if c then c.text.enabled = v; GU:ApplyLayout(selected) end end)
    E.textSize = numRow(b, -40, "Text size", 8, 64,
      function() local c = Cfg(); return c and c.text.size or 22 end,
      function(v) local c = Cfg(); if c then c.text.size = v; GU:ApplyLayout(selected) end end)
    sc.refresh = function() E.textOn:refresh(); E.textSize:refresh() end
  end)

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
  E.healthSec   = ringBody("Health ring",         "health",   "health",   726)
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
