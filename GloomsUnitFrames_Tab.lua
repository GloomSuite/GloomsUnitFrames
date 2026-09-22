-- ============================================================
-- GloomsUnitFrames_Tab.lua
-- The UNIT FRAMES tab of the Suite window, laid out the family way (GB is
-- the reference): a LEFT RAIL (the mark, the PROFILE block, Player / Target
-- as a selectable list, Copy, Reset) and a scrolling RIGHT PANE with the
-- selected unit's settings. No footer: every control applies the moment it
-- moves and the on-screen ring IS the preview. Profiles are per character
-- like GB's (the owner, 2026-09-20 — the tool shipped account-wide and he
-- ruled that wrong); the engine holds the plumbing, this file only drives
-- the shared UI.profileBlock. Every widget comes from LibGloomSkin-1.0; the
-- engine (GloomsUnitFrames.lua) exposes what this file drives.
--
-- LAYOUT (the 2026-09-19 compaction, Hub BACKLOG item 13). The owner: EUI
-- "compacts the settings panels into dropdowns and side-by-side display,
-- whereas you tend to just stack things endlessly." So every section body is
-- a UI.grid — two cells per line (label + control), a full row where a
-- control needs the width — and settings sort into three tiers:
--   · always on the grid: the things you set every time (size, angles,
--     colors, offsets);
--   · a CONDITIONAL LINE that appears under its switch (the gradient's end
--     color + angle, the drain shift's two colors, the resource breakpoint)
--     — one line, so it costs nothing to show inline; the grid restacks;
--   · a COG → POPOVER for a whole cluster behind one switch (the shield
--     tint, the cast ring's interrupt coloring, an aura group's filters) — EUI's shape, UI.cog / UI.popover in the Hub.
-- ============================================================

-- ★ SHARED-TOOLKIT VERSION GATE — GloomsHub/docs/CONTRACTS.md §6. Bump
-- SKIN_NEEDS in the same commit that first calls a newer widget.
-- This file needs UI.grid / UI.popover / UI.cog (MINOR 9).
local SKIN_MAJOR, SKIN_NEEDS = "LibGloomSkin-1.0", 10

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
local sliderRow, makeScrollbar, attachTip = UI.sliderRow, UI.makeScrollbar, UI.attachTip
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

-- ★ `v or default` is WRONG for a boolean setting: an OFF switch (false) would
-- read as its default (true) and every click would turn it off again. nil only.
local function orDefault(v, default) if v == nil then return default end return v end

-- --------------------------------------------------------------------------
-- CELLS — the grid's vocabulary. Each takes the grid and fills one cell
-- (or, in a one-column grid, one row); each returns a handle with :refresh().
-- Heights: a switch / swatch / choice / dropdown line is 28, a slider 44.
-- --------------------------------------------------------------------------
local H_LINE, H_SLIDER = 28, 44

local function label(parent, text, x, y, size, cc)
  local fs = newText(parent, FONT.body, size or 12, cc or TEXT, "LEFT")
  fs:SetPoint("TOPLEFT", x, y); fs:SetText(text)
  return fs
end

-- A cell's left-hand label, vertically centred.
local function cellLabel(f, text, size, cc)
  local fs = newText(f, FONT.body, size or 12, cc or TEXT, "LEFT")
  fs:SetPoint("LEFT", PAD, 0); fs:SetText(text); fs:SetWordWrap(false)
  return fs
end

-- Slider + typed box. `apply(v)` receives an integer clamped to [minV, maxV].
local function cNum(g, labelText, minV, maxV, get, apply, tip)
  local h = {}
  h.cell = g:cell(H_SLIDER, function(f)
    local ebox = flatEditBox(f, 56, 18)
    ebox:SetPoint("TOPRIGHT", -PAD, 0)
    ebox:SetMaxLetters(6); ebox:SetJustifyH("CENTER")
    local row = sliderRow(f, -2, labelText, minV, maxV, 1, get,
      function(v) v = math.floor(v + 0.5); apply(v); ebox:SetText(tostring(v)) end,
      function() return "" end)
    function h:refresh()
      row:refresh()
      ebox:SetText(tostring(math.floor((get() or minV) + 0.5)))
    end
    function h:setEnabled(on) row:setEnabled(on); ebox:SetEnabled(on); ebox:SetAlpha(on and 1 or 0.35) end
    local function commit(self)
      local v = tonumber(self:GetText())
      if v then apply(math.max(minV, math.min(maxV, math.floor(v + 0.5)))) end
      h:refresh()
    end
    ebox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commit(self) end)
    ebox:HookScript("OnEditFocusLost", commit)
    ebox:SetScript("OnEscapePressed", function(self) h:refresh(); self:ClearFocus() end)
    -- Up / Down (Shift ×10) apply LIVE and the box keeps focus (Hub MINOR 10).
    ebox.stepper = function(self, delta)
      local v = tonumber(self:GetText()) or get() or minV
      apply(math.max(minV, math.min(maxV, math.floor(v + 0.5) + delta)))
      h:refresh()
    end
    if tip then attachTip(ebox, labelText, tip) end
    h.box = ebox
  end)
  function h:show(on) g:show(self.cell, on) end
  return h
end

-- Label on the left, sliding switch on the right; an optional cog beside it.
-- `cogOpts` are UI.popover's (title / w / build / onOpen).
local function cToggle(g, labelText, get, set, tip, cogOpts)
  local h = {}
  h.cell = g:cell(H_LINE, function(f)
    local lab = cellLabel(f, labelText)
    local t = makeToggle(f, function() return get() and true or false end, set)
    t:SetPoint("RIGHT", -PAD, 0)
    if tip then attachTip(t, labelText, tip) end
    if cogOpts then
      h.cog = UI.cog(f, cogOpts)
      h.cog:SetPoint("RIGHT", t, "LEFT", -8, 0)
      lab:SetPoint("RIGHT", h.cog, "LEFT", -6, 0)
    else
      lab:SetPoint("RIGHT", t, "LEFT", -6, 0)
    end
    h.toggle = t
  end)
  function h:refresh() self.toggle:refresh() end
  function h:show(on) g:show(self.cell, on) end
  return h
end

-- Label on the left, colour swatch on the right.
local function cColor(g, labelText, get, set, name, tip)
  local h = {}
  h.cell = g:cell(H_LINE, function(f)
    local lab = cellLabel(f, labelText)
    local sw = colorSwatch(f, get, set, false, name)
    sw.swatch:SetPoint("RIGHT", -PAD, 0)
    lab:SetPoint("RIGHT", sw.swatch, "LEFT", -6, 0)
    if tip then attachTip(sw.swatch, labelText, tip) end
    h.sw = sw
  end)
  function h:refresh() self.sw:refresh() end
  function h:show(on) g:show(self.cell, on) end
  return h
end

-- Label on the left, mutually-exclusive flatButtons on the right (the chosen
-- one orange). choices = { { value, text, tip? }, … }.
local function cChoice(g, labelText, choices, bw, onPick)
  local h = { btns = {} }
  h.cell = g:cell(H_LINE, function(f)
    local lab = cellLabel(f, labelText)
    local prev
    for i = #choices, 1, -1 do
      local c = choices[i]
      local b = flatButton(f, bw, 20, COLOR.heroic, c[2] or c[1], 11)
      b:SetBase(0.2)
      if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("RIGHT", -PAD, 0) end
      b:SetScript("OnClick", function() onPick(c[1]); h:sync(c[1]) end)
      if c[3] then attachTip(b, c[2] or c[1], c[3]) end
      h.btns[#h.btns + 1] = { b = b, v = c[1] }
      prev = b
    end
    lab:SetPoint("RIGHT", prev, "LEFT", -6, 0)
  end)
  function h:sync(value) for _, e in ipairs(self.btns) do e.b:SetActive(e.v == value) end end
  function h:show(on) g:show(self.cell, on) end
  return h
end

-- Label on the left, a UI.dropdown on the right; optional cog between them.
local function cDropdown(g, labelText, w, getLabel, getOptions, getCurrent, onPick, tip, cogOpts)
  local h = {}
  h.cell = g:cell(H_LINE, function(f)
    local lab = cellLabel(f, labelText)
    local dd = UI.dropdown(f, w, getLabel, getOptions, getCurrent, onPick)
    dd:SetPoint("RIGHT", -PAD, 0)
    if tip then attachTip(dd, labelText, tip) end
    if cogOpts then
      h.cog = UI.cog(f, cogOpts)
      h.cog:SetPoint("RIGHT", -PAD, 0)
      dd:ClearAllPoints(); dd:SetPoint("RIGHT", h.cog, "LEFT", -8, 0)
    end
    lab:SetPoint("RIGHT", dd, "LEFT", -6, 0)
    h.dd = dd
  end)
  function h:refresh() self.dd:refresh() end
  function h:show(on) g:show(self.cell, on) end
  return h
end

-- A muted note line.
local function cNote(g, text, h)
  local cell = g:row(h or 20, function(f)
    local fs = newText(f, FONT.body, 10.5, MUTE, "LEFT")
    fs:SetPoint("TOPLEFT", PAD, -2); fs:SetPoint("TOPRIGHT", -PAD, -2); fs:SetJustifyH("LEFT"); fs:SetText(text)
    f.text = fs
  end)
  return cell
end

-- Grey a cog out (its cluster is idle) without hiding it.
local function cogEnabled(cog, on)
  if not cog then return end
  cog:SetEnabled(on and true or false); cog:SetAlpha(on and 1 or 0.35)
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

  -- PROFILE: the suite's one profile control (LibGloomSkin MINOR 3), the
  -- same block GB / GA / Overlays carry. The library is account-wide and each
  -- character remembers which one it uses; the engine holds the plumbing.
  local function collision() return false, "A profile with that name already exists." end
  local profBlock = UI.profileBlock(rail, W, {
    noun   = "profile",
    names  = function() return GU:ProfileNames() end,
    active = function() return GU:ActiveProfileName() or "?" end,
    switch = function(v) GU:SetActiveProfile(v) end,
    users  = function(name) return GU:ProfileUsers(name) end,
    create = function(name)
      if not GU:CreateProfile(name) then return collision() end
      GU:SetActiveProfile(name); return true
    end,
    copy = function(name)
      if not GU:CopyProfile(GU:ActiveProfileName(), name) then return collision() end
      GU:SetActiveProfile(name); return true
    end,
    rename = function(name)
      if not GU:RenameProfile(GU:ActiveProfileName(), name) then return collision() end
      return true
    end,
    delete = function()
      local gone = GU:ActiveProfileName()
      local ok, landedOn = GU:DeleteProfile(gone)
      if not ok then return false, "Can't delete the last profile." end
      -- The note line clears on success, so where this character went goes to chat.
      print(("|cff936bffGloom's Unit Frames:|r deleted profile |cffffffff%s|r — this character is now on |cffffffff%s|r.")
        :format(gone, tostring(landedOn)))
      return true
    end,
    onChange = function() RefreshEditor(); RefreshList() end,
    tips = {
      dropdown = "The active profile for this character. Each character remembers its own; the profile library is shared account-wide.",
      new      = "Creates a profile with the factory rings, texts and aura groups, and switches to it. To start from THIS look instead, use Copy.",
      copy     = "Duplicates this profile — both units, everything — and switches to the copy.",
      rename   = "Renames this profile. Characters using it follow the new name.",
      delete   = "Deletes this profile (you'll be asked to confirm). Characters using it fall back to another profile. The last profile can't be deleted.",
    },
  })
  profBlock.frame:SetPoint("TOPLEFT", X, -60)
  E.profBlock = profBlock
  local unitsTop = 60 + profBlock.height + 14   -- the UNITS list sits under the block

  local oh = newText(rail, FONT.head, 12, MUTE, "LEFT")
  oh:SetPoint("TOPLEFT", X, -unitsTop); oh:SetText("UNITS")

  for i, which in ipairs(GU.UNITS) do
    local row = CreateFrame("Button", nil, rail)
    row:SetSize(W, LIST_ROW_H)
    row:SetPoint("TOPLEFT", X, -(unitsTop + 18) - (i - 1) * LIST_ROW_H)
    row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints()
    row.sel:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.28); row.sel:Hide()
    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.07)
    -- Just the name. A right-aligned "which rings are on" summary used to
    -- share the line and collided with it; the owner asked what it was even
    -- for (2026-09-20) — the editor says the same thing one click away.
    row.text = newText(row, FONT.body, 12, TEXT, "LEFT"); row.text:SetPoint("LEFT", 8, 0)
    row.text:SetText(UNIT_LABEL[which])
    row:SetScript("OnClick", function() SelectUnit(which) end)
    rows[which] = row
  end

  local hint = newText(rail, FONT.body, 10.5, MUTE, "LEFT")
  hint:SetPoint("TOPLEFT", X, -(unitsTop + 18) - 2 * LIST_ROW_H - 10)
  hint:SetPoint("TOPRIGHT", -X, -(unitsTop + 18) - 2 * LIST_ROW_H - 10)
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
    local row = rows[which]
    if row then row.sel:SetShown(which == selected) end
  end
  if E.profBlock then E.profBlock:refresh() end
  if E.resetBtn then E.resetBtn:SetEnabled(selected ~= nil) end
  if E.copyBtn then
    E.copyBtn:SetEnabled(selected ~= nil)
    E.copyBtn.text:SetText(selected == "target" and "Copy from Player" or "Copy from Target")
  end
end

-- --------------------------------------------------------------------------
-- The accordion (GB's is the reference): 36px headers — orange caret, Khand
-- purple title, hairline under — one section open at a time, stack reflows.
-- A section's `refresh` re-syncs its widgets AND may change its height (the
-- grids restack), so makeSection wraps it to relayout afterwards: every
-- handler in a section body calls sc.refresh() and nothing else.
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
        sc.body:SetHeight(sc.height)
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

local syncAuraPreview   -- defined with the Auras section (it needs auraSel)
-- Both previews: the cast ring's fake cast while its section is open, and the
-- selected aura group's sample icons while the Auras section is open.
local function syncCastPreview()
  for _, u in ipairs(GU.UNITS) do
    GU:SetCastPreview(u, u == selected and E.castSec and E.castSec.open and container and container:IsVisible())
  end
  if syncAuraPreview then syncAuraPreview() end
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
  local inner = sc.refresh
  if inner then sc.refresh = function() inner(); relayout() end end
  sections[#sections + 1] = sc
  return sc
end

-- --------------------------------------------------------------------------
-- RINGS — one section per ring. kind: "health" (class color, shield tint,
-- drain shift) · "power" (power-type color, drain shift) · "resource"
-- (segments: gap, resource color, breakpoint) · "cast" (channels, interrupt
-- coloring).
-- --------------------------------------------------------------------------
local function rnum(key, field, default)
  return function() local rc = RingCfg(key); return rc and orDefault(rc[field], default) end
end
local function setRing(key, field)
  return function(v) local rc = RingCfg(key); if rc then rc[field] = v; GU:ApplyLayout(selected); RefreshList() end end
end
local function pct(key, field, default)   -- a 0..1 field as 0..100
  return function() local rc = RingCfg(key); return rc and math.floor((orDefault(rc[field], default)) * 100 + 0.5) or default * 100 end,
         function(v) local rc = RingCfg(key); if rc then rc[field] = v / 100; GU:ApplyLayout(selected) end end
end

local STRATA = {
  { "BACKGROUND", "Background", "Behind almost everything." },
  { "LOW",        "Low",        "Behind most frames." },
  { "MEDIUM",     "Medium",     "The default. With most addon frames." },
  { "HIGH",       "High",       "In front of most frames." },
  { "DIALOG",     "Dialog",     "Above almost everything." },
}
local STRATA_LABEL = {}
for _, s in ipairs(STRATA) do STRATA_LABEL[s[1]] = s[2] end

-- the ring's `bar` block (bar mode)
local function bnum(key, field, default)
  return function() local rc = RingCfg(key); return rc and rc.bar and orDefault(rc.bar[field], default) end
end
local function setBar(key, field)
  return function(v) local rc = RingCfg(key); if rc and rc.bar then rc.bar[field] = v; GU:ApplyLayout(selected); RefreshList() end end
end
local function bpct(key, field, default)
  return function() local rc = RingCfg(key); return rc and rc.bar and math.floor((orDefault(rc.bar[field], default)) * 100 + 0.5) or default * 100 end,
         function(v) local rc = RingCfg(key); if rc and rc.bar then rc.bar[field] = v / 100; GU:ApplyLayout(selected) end end
end
local FILL_LABEL = { up = "Bottom to top", down = "Top to bottom", right = "Left to right", left = "Right to left" }
local FILL_ORDER = { "up", "down", "right", "left" }
local ROW_LABEL  = { right = "To the right", left = "To the left", up = "Upward", down = "Downward" }
local ROW_ORDER  = { "right", "left", "up", "down" }

local function ringSection(b, sc, key, title, kind)
  local isHealth, isPower, isResource, isCast = kind == "health", kind == "power", kind == "resource", kind == "cast"
  local w = {}
  local g = UI.grid(b, -8)
  local function R() sc.refresh() end
  local function isBar() local rc = RingCfg(key); return rc and rc.mode == "bar" end

  w.enabled = cToggle(g, "Show this " .. (isResource and "display" or "ring"), rnum(key, "enabled", true), setRing(key, "enabled"),
    "Draws the " .. key .. " display for this unit.")
  -- Arc or Bar: the arc is the ring engine; a bar is a straight fill cut to
  -- a silhouette from the Hub's shape catalog (it can show a real absorb).
  w.drawn = cChoice(g, "Drawn as", {
      { "arc", "Arc", "A ring segment: any span, either direction, round caps." },
      { "bar", "Bar", "A straight fill cut to a shape — a circle, a pill, a rectangle… — filling as a level. The health bar can show a real absorb overlay this way." } },
    66, function(v) setRing(key, "mode")(v); R() end)

  -- BAR cells
  -- the Hub's BAR-shape family — its own list, never the button shapes
  w.shape = cDropdown(g, "Shape", 190,
    function()
      local k = bnum(key, "shape", "orb")()
      if k == "rect" then return "Rectangle" end
      local hub = _G.GloomsHub; local info = hub and hub.BAR_SHAPES and hub.BAR_SHAPES[k]
      return info and info.label or tostring(k)
    end,
    function()
      local opts = { { label = "Rectangle", value = "rect" } }
      local hub = _G.GloomsHub
      if hub and hub.BAR_SHAPE_ORDER then
        for _, k in ipairs(hub.BAR_SHAPE_ORDER) do opts[#opts + 1] = { label = hub.BAR_SHAPES[k].label, value = k } end
      end
      return opts
    end,
    bnum(key, "shape", "orb"),
    function(v) setBar(key, "shape")(v); R() end,
    "The silhouette the fill is cut to. A shape fixes its own proportions — one Size sets it; a Rectangle is free.")
  w.bsize = cNum(g, "Size", 8, 500, bnum(key, "size", 120), setBar(key, "size"),
    "px — the shape's short side; the long side follows the shape")
  w.bwidth = cNum(g, "Width", 8, 800, bnum(key, "width", 200), setBar(key, "width"))
  w.bheight = cNum(g, "Height", 4, 800, bnum(key, "height", 24), setBar(key, "height"))
  w.brot = cNum(g, "Rotation", 0, 359, bnum(key, "rotation", 0), setBar(key, "rotation"),
    "degrees, counter-clockwise. The shape turns; the fill still runs straight along the screen's axis you choose below.")
  w.fillDir = cDropdown(g, "Fills", 160,
    function() return FILL_LABEL[bnum(key, "fillDir", "up")()] or "Bottom to top" end,
    function() local o = {}; for _, k in ipairs(FILL_ORDER) do o[#o + 1] = { label = FILL_LABEL[k], value = k } end; return o end,
    bnum(key, "fillDir", "up"),
    function(v) setBar(key, "fillDir")(v); R() end)
  if isResource then
    w.rowDir = cDropdown(g, "Points run", 160,
      function() return ROW_LABEL[rnum(key, "rowDir", "right")()] or "To the right" end,
      function() local o = {}; for _, k in ipairs(ROW_ORDER) do o[#o + 1] = { label = ROW_LABEL[k], value = k } end; return o end,
      rnum(key, "rowDir", "right"),
      setRing(key, "rowDir"),
      "One shape per point, laid out from the first in this direction.")
    w.rowGap = cNum(g, "Gap between points", 0, 60, rnum(key, "rowGap", 4), setRing(key, "rowGap"), "px")
  end
  if isHealth then
    local aw = {}
    w.absorb = cToggle(g, "Show absorb shields", bnum(key, "absorb", true),
      function(v) setBar(key, "absorb")(v); R() end,
      "A striped overlay the size of the unit's absorb, laid from the FULL end back over the fill — so a shield shows at full health too. Color and opacity behind the cog.",
      { title = "Absorb overlay", w = 300,
        build = function(c)
          local pg = UI.grid(c, -6, { cols = 1 })
          aw.color = cColor(pg, "Stripe color", bnum(key, "absorbColor"), setBar(key, "absorbColor"), "Unit Frames › " .. title .. " absorb")
          aw.alpha = cNum(pg, "Stripe opacity", 0, 100, bpct(key, "absorbAlpha", 0.6))
          aw.grid = pg
          return pg:layout() + 4
        end,
        onOpen = function() aw.color:refresh(); aw.alpha:refresh(); return aw.grid:layout() + 4 end })
  end

  -- ARC cells
  w.dir = cDropdown(g, "Fills", 160,
    function() local rc = RingCfg(key); return (rc and rc.clockwise) and "Clockwise" or "Counter-clockwise" end,
    function() return { { label = "Clockwise", value = "cw" }, { label = "Counter-clockwise", value = "ccw" } } end,
    function() local rc = RingCfg(key); return (rc and rc.clockwise) and "cw" or "ccw" end,
    function(v) setRing(key, "clockwise")(v == "cw") end,
    "The direction the arc grows from its start angle as it fills.")

  w.size = cNum(g, "Size", 40, 700, rnum(key, "size", 220), setRing(key, "size"),
    "px — this ring's outer diameter. Smaller rings nest inside larger ones.")
  w.thick = cNum(g, "Thickness", 2, 350, rnum(key, "thickness", 22), setRing(key, "thickness"),
    "px — cut from the inside; half the size or more is a solid disc")
  -- one pair of cells, reading whichever mode's offset is live (they are separate)
  local function offGet(field) return function() local rc = RingCfg(key); if not rc then return 0 end
    local t = (rc.mode == "bar" and rc.bar) and rc.bar or rc; return orDefault(t[field], 0) end end
  local function offSet(field) return function(v) local rc = RingCfg(key); if not rc then return end
    local t = (rc.mode == "bar" and rc.bar) and rc.bar or rc; t[field] = v; GU:ApplyLayout(selected); RefreshList() end end
  w.dx = cNum(g, "Offset X", -300, 300, offGet("dx"), offSet("dx"), "px from the unit's centre. The arc and the bar each keep their own.")
  w.dy = cNum(g, "Offset Y", -300, 300, offGet("dy"), offSet("dy"), "px from the unit's centre. The arc and the bar each keep their own.")
  w.start = cNum(g, "Start angle", 0, 359, rnum(key, "start", 180), setRing(key, "start"),
    "degrees — 0 is right, 90 top, 180 left, 270 bottom. Where the FULL end sits.")
  w.span = cNum(g, "Arc span", 10, 360, rnum(key, "span", 180), setRing(key, "span"),
    "degrees — 180 is a semicircle, 360 a full ring")

  if isResource then
    -- one switch for both ends of every segment
    w.roundStart = cToggle(g, "Round the segment ends", rnum(key, "roundStart", false),
      function(v) local rc = RingCfg(key); if rc then rc.roundStart, rc.roundEnd = v, v; GU:ApplyLayout(selected) end end,
      "Round caps on both ends of every segment.")
    w.gap = cNum(g, "Gap between segments", 0, 30, rnum(key, "gap", 4), setRing(key, "gap"),
      "degrees — one segment per point; the count follows your class and spec")
  else
    w.roundStart = cToggle(g, "Round the start", rnum(key, "roundStart", false), setRing(key, "roundStart"),
      "A round cap on the arc's fixed end.")
    w.roundEnd = cToggle(g, "Round the moving end", rnum(key, "roundEnd", false), setRing(key, "roundEnd"),
      "A round cap that rides the leading edge as the value moves.")
  end

  -- OUTLINE — a setting of the display, drawn in either mode
  do
    local rw = {}
    w.rim = cToggle(g, "Outline", rnum(key, "outline", false),
      function(v) setRing(key, "outline")(v); R() end,
      "An outline around the display's shape — a bar's silhouette, or the arc's whole track including its ends. Width, color and opacity are behind the cog.",
      { title = "Outline", w = 300,
        build = function(c)
          local pg = UI.grid(c, -6, { cols = 1 })
          local WIDTH_LABEL = { thin = "Thin", medium = "Medium", thick = "Thick" }
          rw.width = cDropdown(pg, "Outline width", 120,
            function() return WIDTH_LABEL[rnum(key, "outlineWidth", "medium")()] or "Medium" end,
            function() return { { label = "Thin", value = "thin" }, { label = "Medium", value = "medium" }, { label = "Thick", value = "thick" } } end,
            rnum(key, "outlineWidth", "medium"),
            setRing(key, "outlineWidth"),
            "Thin is a hairline — about 1 px. On a shaped bar the outline scales with the shape; on an arc or a rectangle it is a fixed 1 / 3 / 6 px.")
          rw.color = cColor(pg, "Outline color", rnum(key, "outlineColor"), setRing(key, "outlineColor"), "Unit Frames › " .. title .. " outline")
          rw.alpha = cNum(pg, "Outline opacity", 0, 100, pct(key, "outlineAlpha", 1))
          rw.grid = pg
          return pg:layout() + 4
        end,
        onOpen = function() rw.width:refresh(); rw.color:refresh(); rw.alpha:refresh(); return rw.grid:layout() + 4 end })
  end
  -- LAYER per display: off = the unit's layer and the automatic order
  -- (health under power under resource under cast); on = this display's own
  -- strata and level, so it can sit between two Overlays graphics.
  w.ownLayer = cToggle(g, "Own layer", function() local rc = RingCfg(key); return rc and rc.level ~= nil end,
    function(v)
      local rc = RingCfg(key); if not rc then return end
      if v then
        local f = GU:Frame(selected); local h = f and f.rings[key] and f.rings[key].holder
        rc.strata = h and h:GetFrameStrata() or "MEDIUM"
        rc.level = h and (h:GetFrameLevel() + 1) or 11    -- the lowest piece's level
      else rc.strata, rc.level = nil, nil end
      GU:ApplyLayout(selected); R()
    end,
    "Off: this display follows the unit's Layer and draws in the standard order. On: give it its own layer and level — the same two numbers Gloom's Overlays uses — to slot it between overlay graphics.")
  w.strata = cDropdown(g, "Layer", 150,
    function() local rc = RingCfg(key); return rc and STRATA_LABEL[rc.strata or "MEDIUM"] or "Medium" end,
    function() local opts = {}; for _, st in ipairs(STRATA) do opts[#opts + 1] = { label = st[2], value = st[1] } end; return opts end,
    function() local rc = RingCfg(key); return rc and (rc.strata or "MEDIUM") end,
    setRing(key, "strata"))
  w.level = cNum(g, "Level within the layer", 0, 1000, rnum(key, "level", 11), setRing(key, "level"),
    "The level of this display's lowest piece; it stacks upward from here — a bar takes 7 levels, an arc 16. An Overlays graphic is one level. To put one UNDER this display give it a lower number; to put one OVER it, a number above this plus 6 (bar) or 15 (arc).")

  w.trackColor = cColor(g, "Empty track color", rnum(key, "trackColor"), setRing(key, "trackColor"),
    "Unit Frames › " .. title .. " track")
  w.trackAlpha = cNum(g, "Empty track opacity", 0, 100, pct(key, "trackAlpha", 0.12))

  -- Color: the swatch and Solid / Gradient in one cell; the gradient's end
  -- color + angle appear on the next line while Gradient is chosen.
  w.colorCell = g:cell(H_LINE, function(f)
    local lab = cellLabel(f, "Color")
    local sw = colorSwatch(f, rnum(key, "color"), setRing(key, "color"), false, "Unit Frames › " .. title .. " color")
    sw.swatch:SetPoint("LEFT", lab, "RIGHT", 8, 0)
    w.color = sw
    local btns = {}
    local prev
    for _, c in ipairs({ { "gradient", "Gradient", "Blends from this color to the end color across the ring, along an angle you set." },
                         { "solid", "Solid", "One color." } }) do
      local bt = flatButton(f, 66, 20, COLOR.heroic, c[2], 11); bt:SetBase(0.2)
      if prev then bt:SetPoint("RIGHT", prev, "LEFT", -4, 0) else bt:SetPoint("RIGHT", -PAD, 0) end
      bt:SetScript("OnClick", function() setRing(key, "colorMode")(c[1]); R() end)
      attachTip(bt, c[2], c[3])
      btns[#btns + 1] = { b = bt, v = c[1] }
      prev = bt
    end
    w.mode = { sync = function(v) for _, e in ipairs(btns) do e.b:SetActive(e.v == v) end end }
  end)
  if isHealth then
    w.unitColor = cToggle(g, "Use the unit's class color", rnum(key, "classColor", true), setRing(key, "classColor"),
      "A player's class color; for an NPC, hostile red, neutral yellow, friendly green — instead of the Color. Solid mode only: a gradient wins over it. The drain shift still applies on top.")
  elseif isPower then
    w.unitColor = cToggle(g, "Use the power type's color", rnum(key, "powerColor", true), setRing(key, "powerColor"),
      "Mana blue, rage red, energy yellow and so on, instead of the Color.")
  elseif isResource then
    w.unitColor = cToggle(g, "Use the resource's color", rnum(key, "resourceColor", true), setRing(key, "resourceColor"),
      "Soul shards purple, combo points yellow and so on, instead of the Color.")
  elseif isCast then
    w.drains = cToggle(g, "Channels drain", rnum(key, "channelDrains", true), setRing(key, "channelDrains"),
      "A channeled spell empties the arc as it runs down; a cast fills it. Off: both fill.")
  end
  w.color2 = cColor(g, "End color", rnum(key, "color2"), setRing(key, "color2"), "Unit Frames › " .. title .. " gradient end")
  w.angle = cNum(g, "Gradient angle", 0, 359, rnum(key, "gradientAngle", 0), setRing(key, "gradientAngle"),
    "degrees — 0 runs left to right, 90 bottom to top. A bar snaps it to the nearest of the four.")

  if isHealth or isPower then
    w.shift = cToggle(g, "Shift color as it drains", rnum(key, "shift", false),
      function(v) setRing(key, "shift")(v); R() end,
      "On top of the color above: the mid color is fully in by 50%, and the low color fades in from there toward empty. Blended by the game engine, so it works on secret values.")
  end
  if isHealth then
    -- The shield tint's five settings live behind the cog.
    local sw = {}
    w.shieldOn = cToggle(g, "Tint while shielded", rnum(key, "shieldTint", false),
      function(v) setRing(key, "shieldTint")(v); R() end,
      "While the unit has an absorb shield, a wash of a color lies over the filled part of the ring, fading out to nothing in the direction you set. The game decides when — the shield's size is not something an addon may read on 12.1, so this shows presence, not amount. The cog holds its color, opacity and fade.",
      { title = "Shield tint", w = 330,
        build = function(c)
          local pg = UI.grid(c, -6, { cols = 1 })
          sw.color = cColor(pg, "Shield tint color", rnum(key, "shieldColor"), setRing(key, "shieldColor"),
            "Unit Frames › " .. title .. " shield tint")
          sw.alpha = cNum(pg, "Shield tint opacity", 0, 100, pct(key, "shieldAlpha", 0.8))
          sw.auto = cToggle(pg, "Fade along the arc", rnum(key, "shieldAuto", true),
            function(v) setRing(key, "shieldAuto")(v); R() end,
            "Strongest at the arc's start, gone by its end, whatever the span and angle. Off: set the width and direction yourself. A full 360° ring always uses the manual settings.")
          sw.width = cNum(pg, "Fade width", 10, 100, rnum(key, "shieldWidth", 70), setRing(key, "shieldWidth"),
            "percent of the ring's diameter the fade runs across, centred — 100 is edge to edge")
          sw.angle = cNum(pg, "Fade direction", 0, 359, rnum(key, "shieldAngle", 180), setRing(key, "shieldAngle"),
            "degrees — the wash is strongest on this side and fades to nothing across the ring: 180 = full on the left, 0 = full on the right, 90 = top")
          sw.grid = pg
          return pg:layout() + 4
        end,
        onOpen = function() return sw.refresh() end })
    function sw.refresh()
      local rc = RingCfg(key); if not rc then return end
      sw.color:refresh(); sw.alpha:refresh(); sw.auto:refresh(); sw.width:refresh(); sw.angle:refresh()
      local manual = rc.shieldAuto == false or (rc.span or 180) >= 360
      sw.width:show(manual); sw.angle:show(manual)
      return sw.grid:layout() + 4
    end
  end
  if isHealth or isPower then
    w.mid = cColor(g, "Mid color (at 50%)", rnum(key, "midColor"), setRing(key, "midColor"), "Unit Frames › " .. title .. " mid color")
    w.low = cColor(g, "Low color (at empty)", rnum(key, "lowColor"), setRing(key, "lowColor"), "Unit Frames › " .. title .. " low color")
  end
  if isResource then
    w.brkOn = cToggle(g, "Change color at a point count", rnum(key, "breakEnabled", false),
      function(v) setRing(key, "breakEnabled")(v); R() end,
      "Every segment turns the color below once you have at least this many points.")
    g:endLine()
    w.brkAt = cNum(g, "At this many points", 1, 7, rnum(key, "breakAt", 5), setRing(key, "breakAt"))
    w.brkColor = cColor(g, "Color from there", rnum(key, "breakColor"), setRing(key, "breakColor"), "Unit Frames › " .. title .. " breakpoint color")
  end
  if isCast then
    -- The interrupt coloring: six settings behind the cog.
    local kw = {}
    w.lockOn = cToggle(g, "Color by interrupt state", rnum(key, "kickAware", true),
      function(v) setRing(key, "kickAware")(v); R() end,
      "Target only. The ring takes one of three colors: the ring's own Color while the cast is interruptible and your interrupt is ready, or the two behind the cog otherwise. Solid colors (a gradient is set aside while this is on).",
      { title = "Interrupt coloring", w = 420,
        build = function(c)
          local pg = UI.grid(c, -6, { cols = 1 })
          -- The same swatch as the grid's Color: the "ready" state IS the ring's color.
          kw.ready = cColor(pg, "Interruptible and your interrupt is ready (the ring's Color)", rnum(key, "color"),
            function(v) setRing(key, "color")(v); w.color:refresh() end,   -- the grid's swatch shows the same value
            "Unit Frames › " .. title .. " color")
          kw.cd = cColor(pg, "Interruptible, but your interrupt is on cooldown", rnum(key, "kickCDColor"), setRing(key, "kickCDColor"),
            "Unit Frames › " .. title .. " interrupt on cooldown")
          kw.lock = cColor(pg, "Can't be interrupted", rnum(key, "lockedColor"), setRing(key, "lockedColor"),
            "Unit Frames › " .. title .. " uninterruptible")
          kw.midOn = cToggle(pg, "Interrupt back before the cast ends: tint", rnum(key, "midCastEnabled", true),
            function(v) setRing(key, "midCastEnabled")(v); R() end,
            "Your interrupt is on cooldown but returns before this cast finishes — the fill takes this color.")
          kw.mid = cColor(pg, "That tint's color", rnum(key, "midCastColor"), setRing(key, "midCastColor"),
            "Unit Frames › " .. title .. " mid-cast tint")
          kw.tickOn = cToggle(pg, "Tick where your interrupt returns", rnum(key, "kickTick", true),
            function(v) setRing(key, "kickTick")(v); R() end,
            "A small mark on the arc at the point where your interrupt comes off cooldown, if that is before the cast ends.")
          kw.tick = cColor(pg, "Tick color", rnum(key, "kickTickColor"), setRing(key, "kickTickColor"),
            "Unit Frames › " .. title .. " kick tick")
          kw.grid = pg
          return pg:layout() + 4
        end,
        onOpen = function() return kw.refresh() end })
    function kw.refresh()
      local rc = RingCfg(key); if not rc then return end
      kw.ready:refresh(); kw.cd:refresh(); kw.lock:refresh(); kw.midOn:refresh(); kw.mid:refresh(); kw.tickOn:refresh(); kw.tick:refresh()
      kw.mid:show(rc.midCastEnabled and true or false)
      kw.tick:show(rc.kickTick and true or false)
      return kw.grid:layout() + 4
    end
    cNote(g, "The cast ring shows only while the unit is casting or channeling.")
  end

  sc.refresh = function()
    local rc = RingCfg(key)
    if not rc then return end
    local bar = rc.mode == "bar"
    w.enabled:refresh(); w.drawn:sync(bar and "bar" or "arc")
    -- arc cells
    for _, cell in ipairs({ w.dir, w.size, w.thick, w.start, w.span, w.roundStart, w.roundEnd, w.gap }) do
      if cell then cell:show(not bar) end
    end
    w.dir:refresh()
    w.size:refresh(); w.thick:refresh(); w.dx:refresh(); w.dy:refresh()
    w.start:refresh(); w.span:refresh()
    w.roundStart:refresh(); if w.roundEnd then w.roundEnd:refresh() end
    if w.gap then w.gap:refresh() end
    -- bar cells
    local rect = bar and rc.bar and rc.bar.shape == "rect"
    w.shape:show(bar); w.shape:refresh()
    w.bsize:show(bar and not rect); w.bsize:refresh()
    w.bwidth:show(rect); w.bwidth:refresh()
    w.bheight:show(rect); w.bheight:refresh()
    w.brot:show(bar); w.brot:refresh()
    w.fillDir:show(bar); w.fillDir:refresh()
    if w.rowDir then w.rowDir:show(bar); w.rowDir:refresh(); w.rowGap:show(bar); w.rowGap:refresh() end
    w.rim:refresh()
    cogEnabled(w.rim.cog, rc.outline and true or false)
    if w.absorb then
      w.absorb:show(bar); w.absorb:refresh()
      cogEnabled(w.absorb.cog, rc.bar and rc.bar.absorb ~= false)
    end
    -- layer
    w.ownLayer:refresh()
    local own = rc.level ~= nil
    w.strata:show(own); w.strata:refresh(); w.level:show(own); w.level:refresh()
    w.trackColor:refresh(); w.trackAlpha:refresh()
    local mode = rc.colorMode or "solid"
    w.mode.sync(mode); w.color:refresh()
    if w.unitColor then w.unitColor:refresh() end
    if isHealth then w.unitColor:show(mode ~= "gradient") end
    w.color2:refresh(); w.angle:refresh()
    w.color2:show(mode == "gradient"); w.angle:show(mode == "gradient")
    if w.shift then
      w.shift:refresh(); w.mid:refresh(); w.low:refresh()
      w.mid:show(rc.shift and true or false); w.low:show(rc.shift and true or false)
    end
    if w.shieldOn then
      w.shieldOn:show(not bar)   -- the arc's presence wash; a bar has the absorb overlay instead
      w.shieldOn:refresh()
      cogEnabled(w.shieldOn.cog, rc.shieldTint and true or false)
      if w.shieldOn.cog.popover:isOpen() then w.shieldOn.cog.popover:open() end
    end
    if w.brkOn then
      w.brkOn:refresh(); w.brkAt:refresh(); w.brkColor:refresh()
      w.brkAt:show(rc.breakEnabled and true or false); w.brkColor:show(rc.breakEnabled and true or false)
    end
    if w.drains then
      w.drains:refresh(); w.lockOn:refresh()
      cogEnabled(w.lockOn.cog, rc.kickAware and true or false)
      if w.lockOn.cog.popover:isOpen() then w.lockOn.cog.popover:open() end
    end
    sc.height = g:layout() + 8
  end
end


-- --------------------------------------------------------------------------
-- TEXTS: any number of text pieces per unit — a list, then the selected
-- piece's editor. The section's height follows the list and the grid.
-- --------------------------------------------------------------------------
local TEXT_ROW_H = 26
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

-- The list + Add / Duplicate / Delete strip both list sections share. `describe(item)`
-- gives a row's text; `onSelect(i)` / `onAdd()` / `onDup(item, i)` the actions.
local function listBlock(b, opts)
  local L = { rows = {} }
  L.add = flatButton(b, opts.addW or 90, 22, COLOR.heroic, opts.addLabel, 11); L.add:SetBase(0.2)
  L.dup = flatButton(b, 90, 22, COLOR.heroic, "Duplicate", 11); L.dup:SetBase(0.2)
  L.del = flatButton(b, 90, 22, COLOR.heroic, "Delete", 11);    L.del:SetBase(0.2)
  L.add:SetScript("OnClick", opts.onAdd)
  L.dup:SetScript("OnClick", opts.onDup)
  L.del:SetScript("OnClick", opts.onDel)
  attachTip(L.add, opts.addTip[1], opts.addTip[2])
  attachTip(L.dup, "Duplicate", opts.dupTip)
  -- Lays the rows out; returns the y the editor should start at.
  function L:refresh(list, cur)
    local n = #list
    for i = 1, n do
      local row = self.rows[i]
      if not row then
        row = CreateFrame("Button", nil, b)
        row:SetHeight(TEXT_ROW_H)
        row.sel = row:CreateTexture(nil, "BACKGROUND"); row.sel:SetAllPoints()
        row.sel:SetColorTexture(COLOR.purple.r, COLOR.purple.g, COLOR.purple.b, 0.28)
        local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.07)
        row.num = newText(row, FONT.body, 11, MUTE, "LEFT"); row.num:SetPoint("LEFT", 8, 0)
        row.text = newText(row, FONT.body, 12, TEXT, "LEFT")
        row.text:SetPoint("LEFT", 30, 0); row.text:SetPoint("RIGHT", -8, 0); row.text:SetWordWrap(false)
        self.rows[i] = row
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", PAD - 8, -8 - (i - 1) * TEXT_ROW_H); row:SetPoint("TOPRIGHT", -PAD + 8, -8 - (i - 1) * TEXT_ROW_H)
      row.num:SetText(tostring(i))
      local item = list[i]
      row.text:SetText(opts.describe(item))
      local off = item.enabled == false
      row.text:SetTextColor(off and MUTE.r or TEXT.r, off and MUTE.g or TEXT.g, off and MUTE.b or TEXT.b)
      row.sel:SetShown(i == cur)
      row:SetScript("OnClick", function() opts.onSelect(i) end)
      row:Show()
    end
    for i = n + 1, #self.rows do self.rows[i]:Hide() end
    local btnY = -8 - n * TEXT_ROW_H - 6
    self.add:ClearAllPoints(); self.add:SetPoint("TOPLEFT", PAD, btnY)
    self.dup:ClearAllPoints(); self.dup:SetPoint("LEFT", self.add, "RIGHT", 6, 0)
    self.del:ClearAllPoints(); self.del:SetPoint("LEFT", self.dup, "RIGHT", 6, 0)
    self.dup:SetEnabled(n > 0); self.del:SetEnabled(n > 0)
    return btnY - 34
  end
  return L
end

local function textsSection(b, sc)
  local w = {}
  local function selectPiece(i) textSel[selected] = i; RefreshEditor() end

  local L = listBlock(b, {
    addLabel = "+ Add text", addTip = { "Add a text", "A new piece showing the unit's name, placed at the centre. Move it with Offset X / Y below." },
    dupTip = "A copy of the selected piece, one line lower.",
    describe = function(tc) local tpl = tc.template or ""; return tpl ~= "" and tpl or "(empty)" end,
    onSelect = selectPiece,
    onAdd = function()
      local list = TextList(); if not list then return end
      list[#list + 1] = NewTextPiece("[name]")
      GU:ApplyLayout(selected); selectPiece(#list)
    end,
    onDup = function()
      local list = TextList(); local tc, i = TextCfg()
      if not (list and tc) then return end
      local t = CopyTable(tc); t.y = (t.y or 0) - (t.size or 22) - 4
      table.insert(list, i + 1, t)
      GU:ApplyLayout(selected); selectPiece(i + 1)
    end,
    onDel = function()
      local list = TextList(); local tc, i = TextCfg()
      if not (list and tc) then return end
      table.remove(list, i)
      GU:ApplyLayout(selected); selectPiece(math.max(1, math.min(i, #list)))
    end,
  })

  -- The editor for the selected piece, anchored under the list.
  local ed = CreateFrame("Frame", nil, b)
  ed:SetPoint("TOPLEFT", 0, 0); ed:SetPoint("TOPRIGHT", 0, 0); ed:SetHeight(10)
  local g = UI.grid(ed, 0)
  local function R() sc.refresh() end

  w.enabled = cToggle(g, "Show this text", tget("enabled", true), tset("enabled"))
  w.font = cDropdown(g, "Font", 190,
    function() local tc = TextCfg(); local f = tc and tc.font; return (f and f ~= "") and f or "Suite default (Khand)" end,
    function()
      local opts = { { label = "Suite default (Khand)", value = "" } }
      local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
      if lsm then for _, name in ipairs(lsm:List("font")) do opts[#opts + 1] = { label = name, value = name } end end
      return opts
    end,
    function() local tc = TextCfg(); return tc and tc.font or "" end,
    function(v) local tc = TextCfg(); if tc then tc.font = (v ~= "") and v or nil; GU:ApplyLayout(selected) end end)

  -- Template: the box, with the shortcode list behind a button — click a
  -- shortcode there and it is added to the template.
  g:row(48, function(f)
    label(f, "Template — words and [shortcodes], in any order", PAD, -2)
    local box = flatEditBox(f, 100, 22)
    box:ClearAllPoints(); box:SetPoint("TOPLEFT", PAD, -20); box:SetPoint("TOPRIGHT", -PAD - 112, -20); box:SetHeight(22)
    box:SetMaxLetters(200)
    local function commit(self)
      local tc = TextCfg(); if not tc then return end
      local v = self:GetText() or ""
      if v ~= tc.template then tc.template = v; GU:ApplyLayout(selected); R() end
    end
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commit(self) end)
    box:HookScript("OnEditFocusLost", commit)
    box:SetScript("OnEscapePressed", function(self) local tc = TextCfg(); self:SetText(tc and tc.template or ""); self:ClearFocus() end)
    w.box = box
    local help = flatButton(f, 104, 22, COLOR.heroic, "Shortcodes", 11); help:SetBase(0.2)
    help:SetPoint("TOPRIGHT", -PAD, -20)
    attachTip(help, "Shortcodes", "Everything a text can show, straight from the engine. Click one to add it to the template.")
    -- The shortcode list, straight from the engine so it cannot drift.
    local pop = UI.popover({ owner = help, title = "Shortcodes — click one to add it", w = 560,
      build = function(c)
        local y = -6
        for _, h in ipairs(GU.TEXT_HELP) do
          local row = CreateFrame("Button", nil, c); row:SetHeight(16)
          row:SetPoint("TOPLEFT", 6, y); row:SetPoint("TOPRIGHT", -6, y)
          local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.07)
          local code = newText(row, FONT.body, 11, TEXT, "LEFT"); code:SetPoint("LEFT", 8, 0); code:SetText(h[1])
          local what = newText(row, FONT.body, 11, MUTE, "LEFT"); what:SetPoint("LEFT", 230, 0)
          what:SetPoint("RIGHT", -8, 0); what:SetJustifyH("LEFT"); what:SetWordWrap(false); what:SetText(h[2])
          local first = h[1]:match("%[[^%]]+%]") or h[1]
          row:SetScript("OnClick", function()
            local tc = TextCfg(); if not tc then return end
            local tpl = tc.template or ""
            tc.template = (tpl == "" and "" or tpl .. " ") .. first
            GU:ApplyLayout(selected); R()
          end)
          y = y - 16
        end
        return -y + 4
      end })
    help:SetScript("OnClick", function() pop:toggle() end)
  end)

  w.size = cNum(g, "Size", 6, 72, tget("size", 22), tset("size"))
  w.outline = cChoice(g, "Outline", { { "none", "None" }, { "thin", "Thin" }, { "thick", "Thick" } }, 56,
    function(v) tset("outline")(v) end)
  w.color = cColor(g, "Color", tget("color"), tset("color"), "Unit Frames › text color")
  w.classColor = cToggle(g, "Use the unit's class color", tget("classColor", false), tset("classColor"),
    "A player's class color; for an NPC, hostile red, neutral yellow, friendly green — instead of the Color.")
  w.shadow = cToggle(g, "Drop shadow", tget("shadow", true), tset("shadow"))
  w.justify = cChoice(g, "Align", {
    { "LEFT", "Left", "The text grows to the right from its offset." },
    { "CENTER", "Center", "The text is centred on its offset." },
    { "RIGHT", "Right", "The text grows to the left from its offset." },
  }, 56, function(v) tset("justify")(v) end)
  w.x = cNum(g, "Offset X", -800, 800, tget("x", 0), tset("x"))
  w.y = cNum(g, "Offset Y", -800, 800, tget("y", 0), tset("y"))
  w.maxWidth = cNum(g, "Max width", 0, 600, tget("maxWidth", 0), tset("maxWidth"),
    "px — longer text is cut with …  (0 = no limit)")
  w.level = cNum(g, "Layer", 0, 100, tget("level", 70), tset("level"),
    "higher draws on top — the rings sit at 1–64 (health 1–16, power 17–32, resource 33–48, cast 49–64)")

  sc.refresh = function()
    local list = TextList()
    if not list then return end
    local n = #list
    if (textSel[selected] or 1) > n then textSel[selected] = n end
    local cur = textSel[selected] or 1
    local edY = L:refresh(list, cur)
    local tc = list[cur]
    ed:ClearAllPoints(); ed:SetPoint("TOPLEFT", 0, edY); ed:SetPoint("TOPRIGHT", 0, edY)
    ed:SetShown(tc ~= nil)
    local edH = tc and (g:layout() + 4) or 0
    ed:SetHeight(math.max(edH, 10))
    sc.height = -edY + edH + 8
    if not tc then return end
    w.enabled:refresh()
    if not w.box:HasFocus() then w.box:SetText(tc.template or "") end
    w.font:refresh(); w.size:refresh()
    w.outline:sync(tc.outline or "none"); w.shadow:refresh()
    w.color:refresh(); w.classColor:refresh()
    w.x:refresh(); w.y:refresh(); w.justify:sync(tc.justify or "CENTER")
    w.maxWidth:refresh(); w.level:refresh()
  end
end


-- --------------------------------------------------------------------------
-- AURAS: any number of aura groups per unit — a list, then the selected
-- group's editor. Same bones as the Texts section. A group's FILTERS sit
-- behind a cog. (The "This spell" kind and its effect cog were removed
-- 2026-09-20 — GloomsUnitFrames_Auras.lua, AURA_KINDS, says why.)
-- --------------------------------------------------------------------------
local auraSel = {}

syncAuraPreview = function()
  for _, u in ipairs(GU.UNITS) do
    local on = u == selected and E.aurasSec and E.aurasSec.open and container and container:IsVisible()
    GU:SetAuraPreview(u, on and (auraSel[selected] or 1) or nil)
  end
end

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

-- One line of the filter summary: what the cog is currently doing.
local function FilterSummary(ac)
  local f = ac and ac.filter
  if not f then return "any" end
  local only, never = 0, 0
  for _, m in pairs(f.classes or {}) do if m == "only" then only = only + 1 elseif m == "never" then never = never + 1 end end
  local parts = {}
  if f.timed then parts[#parts + 1] = "timed" end
  if only > 0 then parts[#parts + 1] = only .. " only" end
  if never > 0 then parts[#parts + 1] = never .. " never" end
  if f.only and #f.only > 0 then parts[#parts + 1] = "+" .. #f.only .. " spell" .. (#f.only == 1 and "" or "s") end
  if f.never and #f.never > 0 then parts[#parts + 1] = "−" .. #f.never .. " spell" .. (#f.never == 1 and "" or "s") end
  return #parts > 0 and table.concat(parts, " · ") or "any"
end

local function aurasSection(b, sc)
  local w = {}
  local function selectGroup(i) auraSel[selected] = i; RefreshEditor() end
  local function R() sc.refresh() end

  local L = listBlock(b, {
    addLabel = "+ Add group", addW = 110,
    addTip = { "Add an aura group", "A new row of icons at the centre of the frame. Move it with Offset X / Y below." },
    dupTip = "A copy of the selected group, one row lower.",
    describe = function(ac)
      return (GU.AURA_KIND_LABEL[ac.kind] or ac.kind or "?") .. "  ·  up to " .. tostring(ac.max or 8) .. " at " .. tostring(ac.size or 28) .. "px"
    end,
    onSelect = selectGroup,
    onAdd = function()
      local list = AuraList(); if not list then return end
      list[#list + 1] = NewAuraGroup(selected == "target" and "mydebuffs" or "buffs")
      GU:ApplyLayout(selected); selectGroup(#list)
    end,
    onDup = function()
      local list = AuraList(); local ac, i = AuraCfg()
      if not (list and ac) then return end
      local t = CopyTable(ac); t.y = (t.y or 0) - (t.size or 28) - 6
      table.insert(list, i + 1, t)
      GU:ApplyLayout(selected); selectGroup(i + 1)
    end,
    onDel = function()
      local list = AuraList(); local ac, i = AuraCfg()
      if not (list and ac) then return end
      table.remove(list, i)
      GU:ApplyLayout(selected); selectGroup(math.max(1, math.min(i, #list)))
    end,
  })

  local ed = CreateFrame("Frame", nil, b)
  ed:SetPoint("TOPLEFT", 0, 0); ed:SetPoint("TOPRIGHT", 0, 0); ed:SetHeight(10)
  local g = UI.grid(ed, 0)

  w.enabled = cToggle(g, "Show this group", aget("enabled", true), aset("enabled"))
  w.kind = cDropdown(g, "Show", 170,
    function() local ac = AuraCfg(); return ac and GU.AURA_KIND_LABEL[ac.kind] or "?" end,
    function()
      local opts = {}
      for _, k in ipairs(GU.AURA_KINDS) do opts[#opts + 1] = { label = k[2], value = k[1] } end
      return opts
    end,
    function() local ac = AuraCfg(); return ac and ac.kind end,
    function(v) aset("kind")(v); R() end,
    "Buffs or debuffs, narrowed by the filters behind their cog — or one spell by ID, with a shape and an effect. Which auras count is decided by the game, so it matches Blizzard's own frames.")

  local function shapeDropdown(pg)
    return cDropdown(pg, "Shape", 170,
      function() local ac = AuraCfg(); local hub = GloomsHub; local k = ac and ac.shape
        return (k and hub.SHAPES and hub.SHAPES[k] and hub.SHAPES[k].label) or "Square (none)" end,
      function()
        local opts = { { label = "Square (none)", value = "" } }
        local hub = GloomsHub
        for _, k in ipairs(hub.SHAPE_ORDER or {}) do opts[#opts + 1] = { label = hub.SHAPES[k].label, value = k } end
        return opts
      end,
      function() local ac = AuraCfg(); return ac and ac.shape or "" end,
      function(v) local ac = AuraCfg(); if ac then ac.shape = (v ~= "") and v or nil; GU:ApplyLayout(selected); R() end end,
      "The suite's silhouettes — the same catalog Gloom's Bars and Gloom's Auras draw with. The cooldown swipe follows the shape.")
  end

  w.shape = shapeDropdown(g)

  -- ---- kinds "buffs" / "debuffs": the list layout + filters ------------
  w.max = cNum(g, "Max icons", 1, 40, aget("max", 8), aset("max"))
  w.perLine = cNum(g, "Icons per row", 1, 40, aget("perLine", 8), aset("perLine"),
    "the row wraps after this many; set it to 1 for a column")
  w.spacing = cNum(g, "Spacing", 0, 20, aget("spacing", 3), aset("spacing"))
  w.order = cDropdown(g, "Order", 150,
    function() local ac = AuraCfg(); local s = ac and ac.sort or "default"
      return s == "expiring" and "Expiring first" or s == "expiringLast" and "Expiring last" or "Default" end,
    function() return { { label = "Default", value = "default" }, { label = "Expiring first", value = "expiring" }, { label = "Expiring last", value = "expiringLast" } } end,
    function() local ac = AuraCfg(); return ac and ac.sort or "default" end,
    function(v) aset("sort")(v) end,
    "Default is the game's own order. Expiring first puts the aura with the least time left first; Expiring last the most.")
  w.growCell = g:cell(H_LINE, function(f)
    local lab = cellLabel(f, "Grow")
    local function pair(field, choices, anchorTo)
      local btns, prev = {}, nil
      for i = #choices, 1, -1 do
        local c = choices[i]
        local bt = flatButton(f, 50, 20, COLOR.heroic, c[2], 11); bt:SetBase(0.2)
        if prev then bt:SetPoint("RIGHT", prev, "LEFT", -4, 0)
        elseif anchorTo then bt:SetPoint("RIGHT", anchorTo, "LEFT", -10, 0)
        else bt:SetPoint("RIGHT", -PAD, 0) end
        bt:SetScript("OnClick", function() aset(field)(c[1]); R() end)
        attachTip(bt, c[2], c[3])
        btns[#btns + 1] = { b = bt, v = c[1] }
        prev = bt
      end
      return { sync = function(v) for _, e in ipairs(btns) do e.b:SetActive(e.v == v) end end, first = prev }
    end
    w.growV = pair("growV", { { "UP", "Up", "Extra rows stack upward." }, { "DOWN", "Down", "Extra rows stack downward." } })
    w.growH = pair("growH", { { "RIGHT", "Right", "New icons appear to the right." }, { "LEFT", "Left", "New icons appear to the left." } }, w.growV.first)
    lab:SetPoint("RIGHT", w.growH.first, "LEFT", -6, 0)
  end)

  -- FILTERS behind the cog: the engine-decided classes in two columns, each
  -- an Any / Only / Never tri-state, "only timed", then "only these spells"
  -- and "never these spells". One block per polarity, built on first use.
  local FILTER_ROW_H = 24
  local fw = { blocks = {} }
  local function classMode(key)
    local ac = AuraCfg(); return ac and ac.filter and ac.filter.classes and ac.filter.classes[key] or nil
  end
  local function setClass(key, mode)
    local ac = AuraCfg(); if not ac then return end
    ac.filter = ac.filter or {}; ac.filter.classes = ac.filter.classes or {}
    ac.filter.classes[key] = mode
    GU:ApplyLayout(selected); R()
  end
  local function triRow(col, y, cls)
    local lab = newText(col, FONT.body, 11.5, TEXT, "LEFT"); lab:SetPoint("TOPLEFT", 4, y); lab:SetText(cls.label)
    local btns = {}
    local prev
    for _, opt in ipairs({ { "never", "Never" }, { "only", "Only" }, { nil, "Any" } }) do
      local bt = flatButton(col, 40, 17, COLOR.heroic, opt[2], 10); bt:SetBase(0.2)
      if prev then bt:SetPoint("RIGHT", prev, "LEFT", -2, 0) else bt:SetPoint("TOPRIGHT", col, "TOPRIGHT", -4, y + 1) end
      bt:SetScript("OnClick", function() setClass(cls.key, opt[1]); for _, e in ipairs(btns) do e.b:SetActive(e.v == opt[1]) end end)
      btns[#btns + 1] = { b = bt, v = opt[1] }
      prev = bt
    end
    lab:SetPoint("RIGHT", prev, "LEFT", -6, 0); lab:SetWordWrap(false)
    return { refresh = function() local m = classMode(cls.key); for _, e in ipairs(btns) do e.b:SetActive(e.v == m) end end }
  end
  local function spellListBox(parent, y, title, field)
    label(parent, title, 4, y, 11.5)
    local box = flatEditBox(parent, 100, 20)
    box:ClearAllPoints(); box:SetPoint("TOPLEFT", 4, y - 16); box:SetPoint("TOPRIGHT", -4, y - 16); box:SetHeight(20)
    box:SetMaxLetters(400)
    local shown   -- what refresh last put in the box; an unchanged box is not re-parsed
    local function commit(self)
      local ac = AuraCfg(); if not ac then return end
      if self:GetText() == shown then return end
      ac.filter = ac.filter or {}
      local ids, missed = {}, {}
      for part in (self:GetText() or ""):gmatch("[^,]+") do
        local id = GU:ResolveSpell(part)
        if id then ids[#ids + 1] = id elseif part:match("%S") then missed[#missed + 1] = part:match("^%s*(.-)%s*$") end
      end
      ac.filter[field] = ids
      ac.filter[field .. "Missed"] = (#missed > 0) and table.concat(missed, ", ") or nil
      GU:ApplyLayout(selected); R()
    end
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commit(self) end)
    box:HookScript("OnEditFocusLost", commit)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); R() end)
    local note = newText(parent, FONT.body, 10, MUTE, "LEFT"); note:SetPoint("TOPLEFT", 4, y - 38); note:SetPoint("TOPRIGHT", -4, y - 38)
    note:SetJustifyH("LEFT"); note:SetWordWrap(false)
    return { refresh = function()
      local ac = AuraCfg(); if not ac then return end
      -- ⚠ On the PLAYER, the engine ignores spell-ID filters on DEBUFFS — include
      -- and exclude both, measured 2026-09-20 (Void Breach stayed through each;
      -- Hub FINDINGS §20). Buffs, and the target, filter fine. Say so instead of
      -- taking a list that does nothing.
      local dead = selected == "player" and ac.kind == "debuffs"
      box:SetEnabled(not dead); box:SetAlpha(dead and 0.35 or 1)
      if dead then
        box:SetText("")
        note:SetText("|cffff7729the game ignores spell-ID filters on your own debuffs|r — use the classes above")
        return
      end
      local ids = ac.filter and ac.filter[field] or {}
      if not box:HasFocus() then
        -- "Name (ID)": the ID must survive a round trip. Shown by name alone, the
        -- next focus-loss re-committed the NAME, which the game only resolves for
        -- spells you know — a zone debuff's ID came back "not found" and the
        -- filter was silently emptied (the owner, 2026-09-20, Void Breach).
        local names = {}
        for _, id in ipairs(ids) do
          local info = C_Spell.GetSpellInfo(id)
          names[#names + 1] = info and info.name and (info.name .. " (" .. id .. ")") or tostring(id)
        end
        shown = table.concat(names, ", ")
        box:SetText(shown)
      end
      local missed = ac.filter and ac.filter[field .. "Missed"]
      note:SetText(missed and ("not found: " .. missed) or (#ids == 0 and "names or IDs, comma-separated" or (#ids .. " spell" .. (#ids == 1 and "" or "s"))))
    end }
  end
  local function filterBlock(c, pol)
    if fw.blocks[pol] then return fw.blocks[pol] end
    local blk = CreateFrame("Frame", nil, c); blk:SetPoint("TOPLEFT"); blk:SetPoint("TOPRIGHT"); blk:SetHeight(10)
    local rows = {}
    local top = -8
    local tg = UI.grid(blk, top, { cols = 1 })
    rows[#rows + 1] = cToggle(tg, "Only timed auras (hide permanent ones)",
      function() local ac = AuraCfg(); return ac and ac.filter and ac.filter.timed end,
      function(v) local ac = AuraCfg(); if ac then ac.filter = ac.filter or {}; ac.filter.timed = v; GU:ApplyLayout(selected); R() end end)
    top = top - tg:layout() - 4
    local col1 = CreateFrame("Frame", nil, blk); col1:SetPoint("TOPLEFT", PAD - 4, top); col1:SetPoint("TOPRIGHT", blk, "TOP", -6, top); col1:SetHeight(10)
    local col2 = CreateFrame("Frame", nil, blk); col2:SetPoint("TOPLEFT", blk, "TOP", 6, top); col2:SetPoint("TOPRIGHT", -PAD + 4, top); col2:SetHeight(10)
    local list = {}
    for _, cls in ipairs(GU.AURA_CLASSES) do if cls.pol == "both" or cls.pol == pol then list[#list + 1] = cls end end
    local perCol = math.ceil(#list / 2)
    for i, cls in ipairs(list) do
      local col = (i <= perCol) and col1 or col2
      local y = -((i - 1) % perCol) * FILTER_ROW_H
      rows[#rows + 1] = triRow(col, y, cls)
    end
    top = top - perCol * FILTER_ROW_H - 6
    local sl1 = CreateFrame("Frame", nil, blk); sl1:SetPoint("TOPLEFT", PAD - 4, top); sl1:SetPoint("TOPRIGHT", blk, "TOP", -6, top); sl1:SetHeight(10)
    local sl2 = CreateFrame("Frame", nil, blk); sl2:SetPoint("TOPLEFT", blk, "TOP", 6, top); sl2:SetPoint("TOPRIGHT", -PAD + 4, top); sl2:SetHeight(10)
    rows[#rows + 1] = spellListBox(sl1, 0, "Only these spells", "only")
    rows[#rows + 1] = spellListBox(sl2, 0, "Never these spells", "never")
    blk.rows = rows
    blk.height = -top + 56
    blk:SetHeight(blk.height)
    fw.blocks[pol] = blk
    return blk
  end
  local function showFilters(c)
    local ac = AuraCfg()
    local pol = ac and ((ac.kind == "buffs") and "buff" or "debuff") or nil
    for k, blk in pairs(fw.blocks) do blk:SetShown(k == pol) end
    -- Name the panel: the two differ (dispel types are debuff-only; defensives,
    -- cancelable, stealable are buff-only) and it read as the filters "going missing".
    local pf = w.filterCog and w.filterCog.popover and w.filterCog.popover.frame
    if pf and pf.title then pf.title:SetText(pol == "buff" and "FILTERS — BUFFS" or "FILTERS — DEBUFFS") end
    if not pol then return 10 end
    local blk = filterBlock(c, pol); blk:Show()
    for _, r in ipairs(blk.rows) do if r.refresh then r:refresh() end end
    return blk.height
  end
  w.filterCell = g:cell(H_LINE, function(f)
    local lab = cellLabel(f, "Filters")
    w.filterCog = UI.cog(f, { title = "Filters", w = 620,
      build = function(c) return showFilters(c) end,
      onOpen = function(c) return showFilters(c) end,
      tip = { "Filters", "Which auras this group shows: the classes the game can tell apart, only timed ones, and spells to always or never show." } })
    w.filterCog:SetPoint("RIGHT", -PAD, 0)
    w.filterSum = newText(f, FONT.body, 11, MUTE, "RIGHT"); w.filterSum:SetPoint("RIGHT", w.filterCog, "LEFT", -8, 0)
    w.filterSum:SetPoint("LEFT", lab, "RIGHT", 8, 0); w.filterSum:SetWordWrap(false)
  end)

  -- ---- every kind ---------------------------------------------------
  w.size = cNum(g, "Icon size", 10, 96, aget("size", 28), aset("size"))
  w.level = cNum(g, "Layer", 0, 100, aget("level", 60), aset("level"),
    "higher draws on top — the rings sit at 1–64")
  w.x = cNum(g, "Offset X", -800, 800, aget("x", 0), aset("x"))
  w.y = cNum(g, "Offset Y", -800, 800, aget("y", 0), aset("y"),
    "the first icon's corner sits here; the group grows away from it")
  w.durOn = cToggle(g, "Countdown text", aget("showDuration", true), function(v) aset("showDuration")(v); R() end)
  w.durSize = cNum(g, "Countdown size", 6, 32, aget("durationSize", 11), aset("durationSize"))
  w.stackOn = cToggle(g, "Stack count", aget("showStacks", true), function(v) aset("showStacks")(v); R() end)
  w.stackSize = cNum(g, "Stack size", 6, 32, aget("stackSize", 11), aset("stackSize"))
  w.swipe = cToggle(g, "Cooldown swipe", aget("swipe", true), aset("swipe"),
    "A dark sweep across the icon as the aura runs down. Drawn by the game engine.")
  w.border = cToggle(g, "Dark edge", aget("border", true), aset("border"),
    "A one-pixel dark edge around a square icon. A shape brings its own edge.")

  sc.refresh = function()
    local list = AuraList()
    if not list then return end
    local n = #list
    if (auraSel[selected] or 1) > n then auraSel[selected] = n end
    local cur = auraSel[selected] or 1
    local edY = L:refresh(list, cur)
    local ac = list[cur]
    ed:ClearAllPoints(); ed:SetPoint("TOPLEFT", 0, edY); ed:SetPoint("TOPRIGHT", 0, edY)
    ed:SetShown(ac ~= nil)
    if ac then w.border:show(not ac.shape) end
    local edH = ac and (g:layout() + 4) or 0
    ed:SetHeight(math.max(edH, 10))
    sc.height = -edY + edH + 8
    if not ac then return end
    w.enabled:refresh(); w.kind:refresh(); w.shape:refresh()
    w.max:refresh(); w.spacing:refresh(); w.perLine:refresh(); w.order:refresh()
    w.growH.sync(ac.growH or "RIGHT"); w.growV.sync(ac.growV or "UP")
    w.filterSum:SetText(FilterSummary(ac))
    if w.filterCog.popover:isOpen() then w.filterCog.popover:open() end
    w.size:refresh(); w.level:refresh(); w.x:refresh(); w.y:refresh()
    w.durOn:refresh(); w.durSize:refresh(); w.durSize:setEnabled(ac.showDuration ~= false)
    w.stackOn:refresh(); w.stackSize:refresh(); w.stackSize:setEnabled(ac.showStacks ~= false)
    w.swipe:refresh(); w.border:refresh()
    syncAuraPreview()   -- the sample icons follow the selected group
  end
end

-- --------------------------------------------------------------------------
-- The editor: the accordion's sections in order.
-- --------------------------------------------------------------------------

local function num(field, default)
  return function() local cfg = Cfg(); return cfg and orDefault(cfg[field], default) end
end
local function setUnit(field)
  return function(v) local cfg = Cfg(); if cfg then cfg[field] = v; GU:ApplyLayout(selected) end end
end

local function BuildEditor(p)
  bodyContainer = CreateFrame("Frame", nil, p)
  bodyContainer:SetPoint("TOPLEFT", 0, 0); bodyContainer:SetPoint("TOPRIGHT", 0, 0)

  E.posSec = makeSection("Position", 60, function(b, sc)
    local g = UI.grid(b, -8)
    E.xRow = cNum(g, "X", -700, 700, num("x", 0), setUnit("x"))
    E.yRow = cNum(g, "Y", -400, 400, num("y", 0), setUnit("y"))
    sc.refresh = function() E.xRow:refresh(); E.yRow:refresh(); sc.height = g:layout() + 8 end
  end)

  E.layerSec = makeSection("Layer", 60, function(b, sc)
    local g = UI.grid(b, -8)
    E.strata = cDropdown(g, "Layer", 150,
      function() local cfg = Cfg(); return cfg and STRATA_LABEL[cfg.strata or "MEDIUM"] or "Medium" end,
      function()
        local opts = {}
        for _, s in ipairs(STRATA) do opts[#opts + 1] = { label = s[2], value = s[1] } end
        return opts
      end,
      function() local cfg = Cfg(); return cfg and (cfg.strata or "MEDIUM") end,
      function(v) GU:SetStrata(selected, v) end,
      "Background is behind almost everything; Dialog above almost everything. Medium — the default — sits with most addon frames.")
    E.level = cNum(g, "Level within the layer", 0, 200, num("level", 10), setUnit("level"),
      "higher draws in front — use it to tuck a ring behind or in front of an overlay on the same layer")
    sc.refresh = function() E.strata:refresh(); E.level:refresh(); sc.height = g:layout() + 8 end
  end)

  E.visSec = makeSection("Visibility", 44, function(b, sc)
    local g = UI.grid(b, -8)
    E.cond = cDropdown(g, "Show", 170,
      function() local cfg = Cfg(); return cfg and COND_LABEL[cfg.showCondition or "always"] or "Always" end,
      function()
        return {
          { label = "Always", value = "always" }, { label = "In combat", value = "combat" },
          { label = "Target selected", value = "target" }, { label = "Combat or target", value = "combat_or_target" },
        }
      end,
      function() local cfg = Cfg(); return cfg and (cfg.showCondition or "always") end,
      function(v) GU:SetCondition(selected, v); RefreshList() end,
      "Always (the target ring still needs a target) · only in combat · only with a target · either.")
    sc.refresh = function() E.cond:refresh(); sc.height = g:layout() + 8 end
  end)

  E.textsSec = makeSection("Texts", 300, function(b, sc) textsSection(b, sc) end)
  E.aurasSec = makeSection("Auras", 300, function(b, sc) aurasSection(b, sc) end)

  local function ringBody(title, key, kind)
    return makeSection(title, 400, function(b, sc) ringSection(b, sc, key, title, kind) end)
  end
  E.healthSec   = ringBody("Health ring",         "health",   "health")
  E.powerSec    = ringBody("Power ring",          "power",    "power")
  E.resourceSec = ringBody("Class resource ring", "resource", "resource")
  E.castSec     = ringBody("Cast ring",           "cast",     "cast")

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
    if what == "profile" then
      if c:IsVisible() then RefreshEditor(); RefreshList() end
      return
    end
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
