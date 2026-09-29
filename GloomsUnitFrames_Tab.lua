-- ============================================================
-- GloomsUnitFrames_Tab.lua
-- The UNIT FRAMES tab of the Suite window. ★ MID-REDESIGN (Hub BACKLOG 16):
-- stage 1 (2026-09-21) put the KIT's shell around it — the PROFILE row lives
-- in the Suite window's footer (RegisterTab's `profile`), the tool's wordmark
-- in its banner, Player / Target are the two big Michroma buttons at the top,
-- the section headers are the kit's, and the GLOBAL section (visibility,
-- position, layer) is built from the kit's dials and pickers as the proof.
-- The other sections still wear the pre-kit widgets until stage 2 rebuilds
-- them from the owner's seven Unit Frames mocks. The left rail is gone.
-- No Save: every control applies the moment it moves and the on-screen ring
-- IS the preview. Profiles are per character like GB's (the owner,
-- 2026-09-20); the engine holds the plumbing. Every widget comes from
-- LibGloomSkin-1.0; the engine (GloomsUnitFrames.lua) exposes what this
-- file drives.
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
-- This file needs the kit — UI.button / dial / pick / sectionHeader and
-- RegisterTab's `profile` footer (MINOR 11) — and UI.chip, the picker's
-- colour sources and the short dial (MINOR 12).
local SKIN_MAJOR, SKIN_NEEDS = "LibGloomSkin-1.0", 12

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

local PAD        = 18
local TOP_H      = 86   -- the Player / Target row: 20 above, 36 tall, 30 below (the mocks)
local LIST_ROW_H = 30

local container, editorScroll, editorChild, editorBody, emptyNote
local selected
local E = {}
local RefreshList, SelectUnit, RefreshEditor

local UNIT_LABEL = { player = "Player", target = "Target" }
local COND_LABEL = {
  always = "Always", combat = "In combat", target = "Target selected", combat_or_target = "Combat or target", never = "Never",
}

local function Cfg() return selected and GU:Config(selected) or nil end

-- The font list every font picker on this tab offers: the first entry is the
-- fallback (`value = ""` → nil in the config), then LibSharedMedia's catalog.
local function fontOptions(fallbackLabel)
  local opts = { { label = fallbackLabel, value = "" } }
  local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
  if lsm then for _, name in ipairs(lsm:List("font")) do opts[#opts + 1] = { label = name, value = name } end end
  return opts
end
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
-- PROFILE: the suite's one profile control — since stage 1 of the redesign
-- the Suite window draws it in its FOOTER from this api (RegisterTab's
-- `profile`); the same api used to feed UI.profileBlock in the rail. The
-- library is account-wide and each character remembers which one it uses;
-- the engine holds the plumbing.
local function collision() return false, "A profile with that name already exists." end
local PROFILE_API = {
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
}

-- The top row (the mocks): Player / Target as the two big Michroma buttons,
-- the chosen one violet. Copy-from and Reset sit at the row's right end —
-- ★ the mocks do not show them; this placement is the assistant's, to be
-- confirmed against the stage-2 screens.
local function BuildTop(c)
  local top = CreateFrame("Frame", nil, c)
  top:SetPoint("TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", 0, 0); top:SetHeight(TOP_H)
  E.unitBtns = {}
  for i, which in ipairs(GU.UNITS) do
    local b = UI.button(top, UNIT_LABEL[which], { font = FONT.mark, size = 14, h = 36, w = 150, caps = false, kind = "quiet",
      onClick = function() SelectUnit(which) end })
    b:SetPoint("TOPLEFT", 20 + (i - 1) * 170, -20)
    E.unitBtns[which] = b
  end
  attachTip(E.unitBtns.player, "Player", "While this tab is open, the selected unit's ring can be dragged on screen. The green outline is its frame.")
  attachTip(E.unitBtns.target, "Target", "The target ring shows empty until you have a target. While this tab is open it can be dragged on screen.")

  E.resetBtn = UI.button(top, "Reset to defaults", { kind = "warn", onClick = function()
    local which = selected
    if not which then return end
    UI.confirm(("Reset the %s frame to its factory position, size and rings?"):format(UNIT_LABEL[which]:lower()),
      function() GU:Reset(which); RefreshEditor(); RefreshList() end)
  end })
  E.resetBtn:SetPoint("RIGHT", top, "TOPRIGHT", -20, -38)
  attachTip(E.resetBtn, "Reset to defaults", "Puts the selected unit back where a fresh install would have it. Asks first.")

  -- Copy the other unit's settings (everything but position) onto this one.
  E.copyBtn = UI.button(top, "Copy from Target", { kind = "action", onClick = function()
    local which = selected
    if not which then return end
    local from = (which == "player") and "target" or "player"
    UI.confirm(("Copy the %s frame's settings onto the %s frame? Position stays as it is."):format(
      UNIT_LABEL[from]:lower(), UNIT_LABEL[which]:lower()), function()
      GU:CopyFrom(which, from)
      RefreshEditor(); RefreshList()
    end)
  end })
  E.copyBtn:SetPoint("RIGHT", E.resetBtn, "LEFT", -6, 0)
  attachTip(E.copyBtn, "Copy from the other unit",
    "Layer, visibility, text and every ring the two share — sizes, angles, colors, rounding. Position is left alone.")
end

RefreshList = function()
  for _, which in ipairs(GU.UNITS) do
    local b = E.unitBtns and E.unitBtns[which]
    if b then b:SetActive(which == selected) end
  end
  if E.resetBtn then E.resetBtn:SetEnabled(selected ~= nil) end
  if E.copyBtn then
    E.copyBtn:SetEnabled(selected ~= nil)
    E.copyBtn:SetLabel(selected == "target" and "Copy from Player" or "Copy from Target")
  end
end

-- --------------------------------------------------------------------------
-- The accordion: the kit's section headers (a violet triangle + Play Bold 14
-- violet title at x=20), one section open at a time, the stack reflows. The
-- mocks' spacing: a closed header takes 26 (16 + 10); an open one's body
-- starts 20 under it and the next header sits 28 under the body.
-- A section's `refresh` re-syncs its widgets AND may change its height (the
-- grids restack), so makeSection wraps it to relayout afterwards: every
-- handler in a section body calls sc.refresh() and nothing else.
-- --------------------------------------------------------------------------
local SECTION_HDR_H = 26
local BODY_GAP_TOP, BODY_GAP_BOTTOM = 10, 28   -- 10 on top of the header's own 10 → 20
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
    sc.header.button:SetOpen(sc.open)
    if sc.hidden then
      sc.header:Hide(); sc.body:Hide()
    else
      sc.header:Show()
      total = total + SECTION_HDR_H
      if sc.open then
        sc.body:ClearAllPoints()
        sc.body:SetPoint("TOPLEFT", sc.header, "BOTTOMLEFT", 0, -BODY_GAP_TOP)
        sc.body:SetPoint("TOPRIGHT", sc.header, "BOTTOMRIGHT", 0, -BODY_GAP_TOP)
        sc.body:SetHeight(sc.height + BODY_GAP_BOTTOM)
        sc.body:Show()
        prevBottom = sc.body
        total = total + sc.height + BODY_GAP_TOP + BODY_GAP_BOTTOM
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
  -- Closing the open section (nothing open now) goes back to the top so every
  -- header shows (the owner, 2026-09-21). Opening one brings it near the top,
  -- one collapsed header above it.
  if wasOpen and editorScroll then editorScroll:SetVerticalScroll(0) end
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
  local header = CreateFrame("Frame", nil, bodyContainer)   -- the row; the kit header is its click target
  header:SetHeight(SECTION_HDR_H)
  header.button = UI.sectionHeader(header, title, { onToggle = function() toggleSection(sc) end })
  header.button:SetPoint("TOPLEFT", 20, 0)
  local body = CreateFrame("Frame", nil, bodyContainer)
  body:SetHeight(height); body:Hide()
  sc.header, sc.body = header, body
  function sc:SetTitle(t) self.header.button.text:SetText(tostring(t):upper()) end
  build(body, sc)
  local inner = sc.refresh
  if inner then sc.refresh = function() inner(); relayout() end end
  sections[#sections + 1] = sc
  return sc
end

-- --------------------------------------------------------------------------
-- RINGS — one section per ring, all drawn by kitRingSection below. kind:
-- "health" (class color, shield tint / absorb, drain shift) · "power"
-- (power-type color, drain shift) · "resource" (segments: gap, resource
-- color, breakpoint) · "cast" (channels, interrupt coloring).
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

-- --------------------------------------------------------------------------
-- ★ THE KIT'S RING PANEL (redesign stage 2, 2026-09-21) — one panel for
-- every ring, TWO faces, each placed at its own mock's coordinates: the BAR
-- face from the Health mock (`670:7368`), the ARC face from the Power mock
-- (`671:11794`). ⚠ The positions are the mocks', literally — "there aren't
-- necessarily always columns; I put things where they are for a reason" (the
-- owner, 2026-09-21). Every widget is built once at the body's origin and
-- `place`d by the live face in refresh; a widget the face lacks is hidden, a
-- widget another SETTING disables is dimmed to 50%, never hidden.
--   · a colour is a CHIP; the fill colour's chip holds the unit's colour SOURCE
--     (class / power type / resource) through the picker — the "use class
--     color" toggles are gone (the backlog's decision);
--   · "(Remove)" only on the optional colours (outline · track · absorb /
--     shield) — removed = the engine's default;
--   · the Layer Override plate (the mock's faint box, bottom right): OFF|ON ·
--     Layer · Level (a plain field, as drawn).
-- --------------------------------------------------------------------------

-- A labelled kit control: the label on the row, the control 18 under it (the
-- mocks' 35px cell). `make(parent)` returns the control.
local function cellAt(parent, labelText, make)
  local cell = CreateFrame("Frame", nil, parent)
  cell:SetSize(10, 35)
  cell.label = UI.label(cell, labelText); cell.label:SetPoint("TOPLEFT", 0, 0)
  cell.control = make(cell)
  cell.control:SetPoint("TOPLEFT", 0, -18)
  function cell:refresh() if self.control.refresh then self.control:refresh() end end
  -- Disabled BY ANOTHER SETTING = 50%, never hidden (the owner, 2026-09-21:
  -- "that's how ALL of the design mocks are"). Hiding is only for the other
  -- face's controls.
  function cell:setEnabled(on)
    on = on and true or false
    if self.control.setEnabled then self.control:setEnabled(on); self.label:SetAlpha(on and 1 or 0.5)
    elseif self.control.paint then self.control:SetEnabled(on); self.label:SetAlpha(on and 1 or 0.5)   -- a kit button dims itself
    else self:SetAlpha(on and 1 or 0.5); if self.control.SetEnabled then self.control:SetEnabled(on) end end
  end
  return cell
end
local function segCell(parent, labelText, options, get, set)
  return cellAt(parent, labelText, function(c) return UI.segments(c, options, get, set) end)
end
local function toggleCell(parent, labelText, get, set)
  return cellAt(parent, labelText, function(c) return UI.toggleBar(c, get, set) end)
end
local function chipCell(parent, labelText, opts)
  return cellAt(parent, labelText, function(c) return UI.chip(c, opts) end)
end
local function pickCell(parent, labelText, w, getLabel, getOptions, getCurrent, onPick)
  return cellAt(parent, labelText, function(c) return UI.pick(c, w, getLabel, getOptions, getCurrent, onPick) end)
end
local function dialCell(parent, opts) return UI.dial(parent, opts) end   -- a dial IS a 35px labelled cell

-- place(widget, x, y) shows the widget there; place(widget) hides it.
local function place(wd, x, y)
  if not wd then return end
  if x then wd:ClearAllPoints(); wd:SetPoint("TOPLEFT", x, -y); wd:Show() else wd:Hide() end
end

local OUTLINE_OPTS = { { value = "off", label = "Off" }, { value = "thin", label = "Thin" }, { value = "medium", label = "Medium" }, { value = "thick", label = "Thick" } }
local ARC_DIR = { { label = "Clockwise", value = "cw" }, { label = "Counter-clockwise", value = "ccw" } }

local function kitRingSection(b, sc, key, title, kind)
  local isHealth, isPower, isResource, isCast = kind == "health", kind == "power", kind == "resource", kind == "cast"
  local w = {}
  local function R() sc.refresh() end
  local function apply() GU:ApplyLayout(selected); RefreshList() end
  local function setR(field) return function(v) local rc = RingCfg(key); if rc then rc[field] = v; apply() end end end
  local function setRR(field) return function(v) local rc = RingCfg(key); if rc then rc[field] = v; apply(); R() end end end   -- + relayout
  local function setB(field) return function(v) local rc = RingCfg(key); if rc and rc.bar then rc.bar[field] = v; apply() end end end
  local provenance = "Unit Frames › " .. title

  w.enabled = toggleCell(b, title .. " Display", rnum(key, "enabled", true), setR("enabled"))
  w.drawn = segCell(b, "Display Type", { { value = "arc", label = "Arc" }, { value = "bar", label = "Bar" } },
    function() local rc = RingCfg(key); return rc and rc.mode == "bar" and "bar" or "arc" end,
    setRR("mode"))
  w.shape = pickCell(b, "Shape", 175,
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
    function(v) setB("shape")(v); R() end)
  w.outline = segCell(b, (isResource and "Display" or "Bar") .. " Outline", OUTLINE_OPTS,
    function() local rc = RingCfg(key); if not (rc and rc.outline) then return "off" end return rc.outlineWidth or "medium" end,
    function(v)
      local rc = RingCfg(key); if not rc then return end
      rc.outline = v ~= "off"
      if v ~= "off" then rc.outlineWidth = v end
      apply(); R()
    end)
  attachTip(w.outline.control, "Outline", "An outline around the display's shape — a bar's silhouette, or the arc's whole track including its ends. Thin is a hairline; on a shaped bar the outline scales with the shape, on an arc or a rectangle it is a fixed 1 / 3 / 6 px.")

  -- geometry
  w.size = dialCell(b, { label = "Size", min = 8, max = 500, unit = "px", get = bnum(key, "size", 120), set = setB("size") })
  w.asize = dialCell(b, { label = "Size", min = 40, max = 700, unit = "px", get = rnum(key, "size", 220), set = setR("size") })
  w.bwidth = dialCell(b, { label = "Width", min = 8, max = 800, unit = "px", get = bnum(key, "width", 200), set = setB("width") })
  w.bheight = dialCell(b, { label = "Height", min = 4, max = 800, unit = "px", get = bnum(key, "height", 24), set = setB("height") })
  w.thick = dialCell(b, { label = "Thickness", min = 2, max = 350, unit = "px", get = rnum(key, "thickness", 22), set = setR("thickness") })
  -- one pair of offset dials, reading whichever mode's offset is live (they are separate)
  local function offGet(field) return function() local rc = RingCfg(key); if not rc then return 0 end
    local t = (rc.mode == "bar" and rc.bar) and rc.bar or rc; return orDefault(t[field], 0) end end
  local function offSet(field) return function(v) local rc = RingCfg(key); if not rc then return end
    local t = (rc.mode == "bar" and rc.bar) and rc.bar or rc; t[field] = v; apply() end end
  w.dx = dialCell(b, { label = "Horizontal Offset", min = -300, max = 300, unit = "px", centre = true, get = offGet("dx"), set = offSet("dx") })
  w.dy = dialCell(b, { label = "Vertical Offset", min = -300, max = 300, unit = "px", centre = true, get = offGet("dy"), set = offSet("dy") })
  w.rot = dialCell(b, { label = "Rotation", min = 0, max = 359, unit = "°", get = bnum(key, "rotation", 0), set = setB("rotation") })
  w.start = dialCell(b, { label = "Start Angle", min = 0, max = 359, unit = "°", get = rnum(key, "start", 180), set = setR("start") })
  w.span = dialCell(b, { label = "Arc Span", min = 10, max = 360, unit = "°", get = rnum(key, "span", 180), set = setR("span") })
  attachTip(w.start.strip, "Start Angle", "0 is right, 90 top, 180 left, 270 bottom — where the FULL end sits.")
  attachTip(w.rot.strip, "Rotation", "Counter-clockwise. The shape turns; the fill still runs along the screen axis you choose in Fill Direction.")
  if isResource then
    w.roundStart = toggleCell(b, "Rounded Segment Ends", rnum(key, "roundStart", false),
      function(v) local rc = RingCfg(key); if rc then rc.roundStart, rc.roundEnd = v, v; apply() end end)
    w.gap = dialCell(b, { label = "Gap Between Segments", min = 0, max = 30, unit = "°", get = rnum(key, "gap", 4), set = setR("gap") })
    attachTip(w.gap.strip, "Gap between segments", "One segment per point; the count follows your class and spec.")
    -- bar mode: the points in a row
    w.rowGap = dialCell(b, { label = "Gap Between Points", min = 0, max = 60, unit = "px", get = rnum(key, "rowGap", 4), set = setR("rowGap") })
    w.rowDir = pickCell(b, "Points Run", 150,
      function() return ROW_LABEL[rnum(key, "rowDir", "right")()] or "To the right" end,
      function() local o = {}; for _, k in ipairs(ROW_ORDER) do o[#o + 1] = { label = ROW_LABEL[k], value = k } end; return o end,
      rnum(key, "rowDir", "right"), setR("rowDir"))
    -- the breakpoint: at this many points every segment turns the colour
    w.brkOn = toggleCell(b, "Color Change at Point Count", rnum(key, "breakEnabled", false), function(v) setR("breakEnabled")(v); R() end)
    attachTip(w.brkOn.control, "Color change at a point count", "Every segment turns the color below once you have at least this many points.")
    w.brkAt = dialCell(b, { label = "Color Change Point Value", min = 1, max = 7, get = rnum(key, "breakAt", 5), set = setR("breakAt") })
    w.brkColor = chipCell(b, "Change Color to:", { get = rnum(key, "breakColor"), set = setR("breakColor"), label = provenance .. " breakpoint color", title = "Breakpoint Color" })
  else
    w.roundStart = toggleCell(b, "Rounded Fill: Start", rnum(key, "roundStart", false), setR("roundStart"))
    w.roundEnd = toggleCell(b, "Rounded Fill: End", rnum(key, "roundEnd", false), setR("roundEnd"))
    attachTip(w.roundEnd.control, "Round the moving end", "A round cap that rides the leading edge as the value moves.")
  end

  -- outline opacity + colour; then the absorb (bar) or the shield tint (arc)
  w.outlineAlpha = dialCell(b, { label = "Outline Opacity %", min = 0, max = 100, unit = "%", get = (pct(key, "outlineAlpha", 1)), set = select(2, pct(key, "outlineAlpha", 1)) })
  w.outlineColor = chipCell(b, "Outline Color", { get = rnum(key, "outlineColor"), set = setR("outlineColor"), optional = true, label = provenance .. " outline", title = "Outline Color" })
  if isHealth then
    w.absorb = toggleCell(b, "Absorb Shield Indicator", bnum(key, "absorb", true), function(v) setB("absorb")(v); R() end)
    attachTip(w.absorb.control, "Absorb shield", "A striped overlay the size of the unit's absorb, laid from the FULL end back over the fill — so a shield shows at full health too.")
    w.absorbAlpha = dialCell(b, { label = "Absorb Shield Opacity %", min = 0, max = 100, unit = "%", get = (bpct(key, "absorbAlpha", 0.6)), set = select(2, bpct(key, "absorbAlpha", 0.6)) })
    w.absorbColor = chipCell(b, "Absorb Shield Color", { get = bnum(key, "absorbColor"), set = setB("absorbColor"), optional = true, label = provenance .. " absorb", title = "Absorb Shield Color" })
    -- the arc's shield WASH (presence only — FINDINGS §19)
    w.shield = toggleCell(b, "Shield Tint", rnum(key, "shieldTint", false), function(v) setR("shieldTint")(v); R() end)
    attachTip(w.shield.control, "Shield tint", "While the unit has an absorb shield, a wash of a color lies over the filled part of the ring, fading out to nothing. The game decides when — a shield's size is not something an addon may read on 12.1, so this shows presence, not amount.")
    w.shieldAlpha = dialCell(b, { label = "Shield Tint Opacity %", min = 0, max = 100, unit = "%", get = (pct(key, "shieldAlpha", 0.8)), set = select(2, pct(key, "shieldAlpha", 0.8)) })
    w.shieldColor = chipCell(b, "Shield Tint Color", { get = rnum(key, "shieldColor"), set = setR("shieldColor"), optional = true, label = provenance .. " shield tint", title = "Shield Tint Color" })
    w.shieldAuto = toggleCell(b, "Fade Along Arc", rnum(key, "shieldAuto", true), function(v) setR("shieldAuto")(v); R() end)
    attachTip(w.shieldAuto.control, "Fade along the arc", "Strongest at the arc's start, gone by its end, whatever the span and angle. Off: set the width and direction yourself. A full 360° ring always uses the manual settings.")
    w.shieldWidth = dialCell(b, { label = "Fade Width %", min = 10, max = 100, unit = "%", short = true, get = rnum(key, "shieldWidth", 70), set = setR("shieldWidth") })
    w.shieldAngle = dialCell(b, { label = "Fade Direction", min = 0, max = 359, unit = "°", short = true, get = rnum(key, "shieldAngle", 180), set = setR("shieldAngle") })
    attachTip(w.shieldAngle.strip, "Fade direction", "The wash is strongest on this side and fades to nothing across the ring: 180 = full on the left, 0 = full on the right, 90 = top.")
  end

  -- colour type · gradient angle · fill direction (a picker in both faces: the
  -- arc's two directions, the bar's four)
  w.colorType = segCell(b, "Color Type", { { value = "solid", label = "Solid" }, { value = "gradient", label = "Gradient" } },
    function() local rc = RingCfg(key); return rc and rc.colorMode or "solid" end,
    setRR("colorMode"))
  w.gradAngle = dialCell(b, { label = "Gradient Angle", min = 0, max = 359, unit = "°", short = true, get = rnum(key, "gradientAngle", 0), set = setR("gradientAngle") })
  attachTip(w.gradAngle.strip, "Gradient angle", "0 runs left to right, 90 bottom to top — any angle, on an arc or a bar.")
  local function isBar() local rc = RingCfg(key); return rc and rc.mode == "bar" end
  w.fillDir = pickCell(b, "Fill Direction", 150,
    function()
      if isBar() then return FILL_LABEL[bnum(key, "fillDir", "up")()] or "Bottom to top" end
      local rc = RingCfg(key); return (rc and rc.clockwise) and "Clockwise" or "Counter-clockwise"
    end,
    function()
      if not isBar() then return ARC_DIR end
      local o = {}; for _, k in ipairs(FILL_ORDER) do o[#o + 1] = { label = FILL_LABEL[k], value = k } end; return o
    end,
    function()
      if isBar() then return bnum(key, "fillDir", "up")() end
      local rc = RingCfg(key); return (rc and rc.clockwise) and "cw" or "ccw"
    end,
    function(v)
      if isBar() then setB("fillDir")(v) else setR("clockwise")(v == "cw") end
      R()
    end)

  -- the fill colour (with its SOURCE) · the gradient's end colour · the track
  local sources
  if isHealth then
    sources = { { value = "class", label = "Use Class Color", word = "Class", color = function()
      local ok, r, g, b = GU.UnitColor(selected)
      if ok and not (issecretvalue and issecretvalue(r)) then return r, g, b end
    end } }
  elseif isPower then
    sources = { { value = "power", label = "Use Power Color", word = "Power", color = function()
      local c = GU.PowerTypeColor(selected)
      if c then return c[1], c[2], c[3] end
    end } }
  elseif isResource then
    sources = { { value = "resource", label = "Use Resource Color", word = "Resource", color = function() return GU:ResourceColor() end } }
  end
  local srcField = isHealth and "classColor" or isPower and "powerColor" or isResource and "resourceColor" or nil
  w.color = chipCell(b, "Color", {
    get = function()
      local rc = RingCfg(key); if not rc then return nil end
      if srcField and rc[srcField] and rc.colorMode ~= "gradient" then return sources[1].value end
      return rc.color
    end,
    set = function(v)
      local rc = RingCfg(key); if not rc then return end
      if type(v) == "string" then rc[srcField] = true
      elseif type(v) == "table" then if srcField then rc[srcField] = false end; rc.color = v end
      apply()
    end,
    fixed = function() local rc = RingCfg(key); return rc and rc.color end,
    label = provenance .. " color", title = title .. " Color", sources = sources })
  w.color2 = chipCell(b, "End Color", { get = rnum(key, "color2"), set = setR("color2"), label = provenance .. " gradient end", title = "Gradient End Color" })
  w.trackColor = chipCell(b, "Track Color", { get = rnum(key, "trackColor"), set = setR("trackColor"), optional = true, label = provenance .. " track", title = "Track Color" })
  w.trackAlpha = dialCell(b, { label = "Track Opacity %", min = 0, max = 100, unit = "%", short = true, get = (pct(key, "trackAlpha", 0.12)), set = select(2, pct(key, "trackAlpha", 0.12)) })

  -- the drain shift and its two colours
  if isHealth or isPower then
    w.shift = toggleCell(b, "Drain Color Shift", rnum(key, "shift", false), function(v) setR("shift")(v); R() end)
    attachTip(w.shift.control, "Drain color shift", "On top of the color above: the 50% color is fully in by half, and the 0% color fades in from there toward empty. Blended by the game engine, so it works on secret values.")
    w.mid = chipCell(b, "50% Color", { get = rnum(key, "midColor"), set = setR("midColor"), label = provenance .. " mid color", title = "50% Color" })
    w.low = chipCell(b, "0% Color", { get = rnum(key, "lowColor"), set = setR("lowColor"), label = provenance .. " low color", title = "0% Color" })
  end

  -- The LAYER OVERRIDE plate: off = the unit's layer and the automatic order.
  local plate = CreateFrame("Frame", nil, b)
  plate:SetSize(350, 63)
  UI.tint(UI.roundFill(plate), COLOR.faint)
  w.plate = plate
  w.ownLayer = toggleCell(plate, "Layer Override", function() local rc = RingCfg(key); return rc and rc.level ~= nil end,
    function(v)
      local rc = RingCfg(key); if not rc then return end
      if v then
        local f = GU:Frame(selected); local h = f and f.rings[key] and f.rings[key].holder
        rc.strata = h and h:GetFrameStrata() or "MEDIUM"
        rc.level = h and (h:GetFrameLevel() + 1) or 11    -- the lowest piece's level
      else rc.strata, rc.level = nil, nil end
      apply(); R()
    end)
  w.ownLayer:SetPoint("TOPLEFT", 20, -14)
  attachTip(w.ownLayer.control, "Layer override", "Off: this display follows the unit's Layer and draws in the standard order. On: its own layer and level — the same two numbers Gloom's Overlays uses — to slot it between overlay graphics. A bar takes 7 levels from this one, an arc 16.")
  w.strata = pickCell(plate, "Layer", 112,
    function() local rc = RingCfg(key); return rc and STRATA_LABEL[rc.strata or "MEDIUM"] or "Medium" end,
    function() local opts = {}; for _, st in ipairs(STRATA) do opts[#opts + 1] = { label = st[2], value = st[1] } end; return opts end,
    function() local rc = RingCfg(key); return rc and (rc.strata or "MEDIUM") end,
    setR("strata"))
  w.strata:SetPoint("TOPLEFT", 156, -14)
  w.level = cellAt(plate, "Level", function(c)
    local e = UI.field(c, 42, { justify = "CENTER" })
    local function commit(self)
      local v = tonumber((self:GetText() or ""):match("%-?%d+"))
      local rc = RingCfg(key)
      if v and rc then rc.level = math.max(0, math.min(1000, v)); apply() end
      self:refresh()
    end
    function e:refresh() local rc = RingCfg(key); self:SetText(tostring(rc and rc.level or 11)) end
    e:SetScript("OnEditFocusLost", commit)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) self:refresh(); self:ClearFocus() end)
    e.stepper = function(self, delta) local rc = RingCfg(key); if rc then rc.level = math.max(0, math.min(1000, (rc.level or 11) + delta)); apply(); self:refresh(); self:HighlightText() end end
    return e
  end)
  w.level:SetPoint("TOPLEFT", 288, -14)

  if isCast then
    w.drains = toggleCell(b, "Channels Drain", rnum(key, "channelDrains", true), setR("channelDrains"))
    attachTip(w.drains.control, "Channels drain", "A channeled spell empties the display as it runs down; a cast fills it. Off: both fill.")
    w.kick = toggleCell(b, "Color by Interrupt State", rnum(key, "kickAware", true), function(v) setR("kickAware")(v); R() end)
    attachTip(w.kick.control, "Color by interrupt state", "Target only. The display takes one of the colors below by whether the cast can be interrupted and whether your interrupt is ready. Solid colors — a gradient is set aside while this is on.")
    -- The five interrupt colours, each a chip with its description (the mock's
    -- rows, 21 apart). The first IS the display's Color; the last two are
    -- optional — removing one turns that feature off.
    w.kReady = chipCell(b, "", { text = "Interruptible and your interrupt is ready (bar default color)", get = rnum(key, "color"),
      set = function(v) setR("color")(v); w.color:refresh() end, label = provenance .. " color", title = "Cast Color" })
    w.kCD = chipCell(b, "", { text = "Interruptible, but your interrupt is on cooldown", get = rnum(key, "kickCDColor"), set = setR("kickCDColor"),
      label = provenance .. " interrupt on cooldown", title = "Interrupt on Cooldown" })
    w.kLock = chipCell(b, "", { text = "Can't be interrupted", get = rnum(key, "lockedColor"), set = setR("lockedColor"),
      label = provenance .. " uninterruptible", title = "Can't Be Interrupted" })
    w.kMid = chipCell(b, "", { text = "Interrupt available before the cast ends", optional = true,
      get = function() local rc = RingCfg(key); return rc and rc.midCastEnabled ~= false and rc.midCastColor or nil end,
      set = function(v) local rc = RingCfg(key); if not rc then return end
        if v then rc.midCastEnabled, rc.midCastColor = true, v else rc.midCastEnabled = false end; apply() end,
      label = provenance .. " mid-cast tint", title = "Mid-cast Tint" })
    w.kTick = chipCell(b, "", { text = "Show tick on cast bar where interrupt will be available", optional = true,
      get = function() local rc = RingCfg(key); return rc and rc.kickTick ~= false and rc.kickTickColor or nil end,
      set = function(v) local rc = RingCfg(key); if not rc then return end
        if v then rc.kickTick, rc.kickTickColor = true, v else rc.kickTick = false end; apply() end,
      label = provenance .. " kick tick", title = "Interrupt Tick" })
    for _, c in ipairs({ w.kReady, w.kCD, w.kLock, w.kMid, w.kTick }) do c.label:Hide(); c.control:ClearAllPoints(); c.control:SetPoint("TOPLEFT", 0, 0); c:SetHeight(17) end
  end

  -- THE TWO FACES — the mocks' coordinates, body-relative. BAR = the Health
  -- mock; ARC = the Power mock (its dial rows run three deep, so everything
  -- under them sits 35 lower).
  local RX, CX = (isResource or isCast) and 614 or 653, (isResource or isCast) and 838 or 877   -- the right block's two x's, per mock
  local function layoutBar(rc)
    local rect = rc.bar and rc.bar.shape == "rect"
    place(w.enabled, 50, 0); place(w.drawn, 196, 0); place(w.shape, 348, 0); place(w.outline, RX, 0)
    place(w.size, not rect and 50, 55); place(w.bwidth, rect and 50, 55); place(w.bheight, rect and 502, 55)
    place(w.dx, 276, 55); place(w.rot, 50, 112); place(w.dy, 276, 112)
    place(w.asize); place(w.thick); place(w.start); place(w.span); place(w.roundStart); place(w.roundEnd); place(w.gap)
    place(w.outlineAlpha, RX, 57); place(w.outlineColor, CX, 55)
    place(w.absorb, RX, 128); place(w.absorbAlpha, RX, 185); place(w.absorbColor, CX, 183)
    place(w.rowGap, RX, 112); place(w.rowDir, CX, 112)
    place(w.brkOn, RX, 197); place(w.brkAt, 802, 197); place(w.brkColor, RX, 252)
    place(w.kick, RX, 128); place(w.drains, CX, 128)
    place(w.kReady, RX, 187); place(w.kCD, RX, 208); place(w.kLock, RX, 229); place(w.kMid, RX, 250); place(w.kTick, RX, 270)
    place(w.shield); place(w.shieldAlpha); place(w.shieldColor); place(w.shieldAuto); place(w.shieldWidth); place(w.shieldAngle)
    place(w.colorType, 50, 197); place(w.gradAngle, 243, 197); place(w.fillDir, 406, 197)
    place(w.color, 50, 252); place(w.color2, 155, 252); place(w.trackColor, 269, 252); place(w.trackAlpha, 373, 252)
    place(w.shift, 50, 307); place(w.mid, 196, 307); place(w.low, 300, 307)
    place(w.note, 50, 307)
    place(w.plate, 660, isCast and 300 or 292)
    return isCast and 363 or 355
  end
  local function layoutArc(rc)
    place(w.enabled, 50, 0); place(w.drawn, 196, 0); place(w.shape, 348, 0); place(w.outline, RX, 0)
    place(w.asize, 50, 55); place(w.dx, 276, 55); place(w.thick, 50, 112); place(w.dy, 276, 112)
    place(w.start, 50, 167); place(w.span, 276, 167)
    place(w.size); place(w.bwidth); place(w.bheight); place(w.rot); place(w.rowGap); place(w.rowDir)
    place(w.outlineAlpha, RX, 57); place(w.outlineColor, CX, 55)
    if isResource then place(w.gap, RX, 112); place(w.roundStart, CX, 112)
    else place(w.roundStart, 655, 112); place(w.roundEnd, 818, 112) end
    place(w.brkOn, RX, 232); place(w.brkAt, 802, 232); place(w.brkColor, RX, 287)
    place(w.kick, RX, 167); place(w.drains, CX, 167)
    place(w.kReady, RX, 222); place(w.kCD, RX, 243); place(w.kLock, RX, 264); place(w.kMid, RX, 285); place(w.kTick, RX, 305)
    place(w.absorb); place(w.absorbAlpha); place(w.absorbColor)
    place(w.shield, 653, 167); place(w.shieldAlpha, 653, 222); place(w.shieldColor, 877, 220)
    place(w.shieldAuto, 653, 277); place(w.shieldWidth, 793, 277); place(w.shieldAngle, 446, 342)
    place(w.colorType, 50, 232); place(w.gradAngle, 243, 232); place(w.fillDir, 406, 232)
    place(w.color, 50, 287); place(w.color2, 155, 287); place(w.trackColor, 269, 287); place(w.trackAlpha, 373, 287)
    place(w.shift, 50, 342); place(w.mid, 196, 342); place(w.low, 300, 342)
    place(w.note, 50, 342)
    place(w.plate, 660, isCast and 379 or isResource and 354 or 348)
    return isCast and 442 or isResource and 417 or 415
  end

  sc.refresh = function()
    local rc = RingCfg(key)
    if not rc then return end
    local bar = rc.mode == "bar"
    local grad = rc.colorMode == "gradient"
    sc.height = bar and layoutBar(rc) or layoutArc(rc)
    for _, name in ipairs({ "enabled", "drawn", "shape", "outline", "size", "asize", "bwidth", "bheight", "thick", "dx", "dy", "rot", "start", "span",
                            "roundStart", "roundEnd", "outlineAlpha", "outlineColor", "absorb", "absorbAlpha", "absorbColor",
                            "shield", "shieldAlpha", "shieldColor", "shieldAuto", "shieldWidth", "shieldAngle",
                            "colorType", "gradAngle", "fillDir", "color", "color2", "trackColor", "trackAlpha", "shift", "mid", "low",
                            "gap", "rowGap", "rowDir", "brkOn", "brkAt", "brkColor", "drains", "kick", "kReady", "kCD", "kLock", "kMid", "kTick",
                            "ownLayer", "strata", "level" }) do
      local wd = w[name]; if wd and wd:IsShown() then wd:refresh() end
    end
    -- what another setting disables
    w.shape:setEnabled(bar)   -- the Power mock keeps Shape on the arc face; it means nothing there
    local outlined = rc.outline and true or false
    w.outlineAlpha:setEnabled(outlined); w.outlineColor:setEnabled(outlined)
    if w.absorb then
      local on = bar and rc.bar and rc.bar.absorb ~= false
      w.absorbAlpha:setEnabled(on); w.absorbColor:setEnabled(on)
      local tint = (not bar) and rc.shieldTint and true or false
      w.shieldAlpha:setEnabled(tint); w.shieldColor:setEnabled(tint); w.shieldAuto:setEnabled(tint)
      local manual = tint and (rc.shieldAuto == false or (rc.span or 180) >= 360)
      w.shieldWidth:setEnabled(manual); w.shieldAngle:setEnabled(manual)
    end
    w.gradAngle:setEnabled(grad); w.color2:setEnabled(grad)
    if w.shift then w.mid:setEnabled(rc.shift and true or false); w.low:setEnabled(rc.shift and true or false) end
    if w.brkOn then w.brkAt:setEnabled(rc.breakEnabled and true or false); w.brkColor:setEnabled(rc.breakEnabled and true or false) end
    if w.kick then
      local on = rc.kickAware and true or false
      for _, c in ipairs({ w.kReady, w.kCD, w.kLock, w.kMid, w.kTick }) do c:setEnabled(on) end
    end
    local own = rc.level ~= nil
    w.strata:setEnabled(own); w.level:setEnabled(own)
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

-- ★ THE KIT'S TEXTS PANEL (redesign stage 2, 2026-09-21), from the Texts mock
-- (`661:5930`) at its coordinates: each piece is a ROW — "Text N", its
-- TEMPLATE in a white field right there, an EDIT button (EDITING, violet, on
-- the selected one) — 27px apart; ADD TEXT · DUPLICATE · DELETE right-aligned
-- under the rows; the SHORTCODE list on the panel under them (violet code,
-- ink description; click a code to append it to the selected template); and
-- the selected piece's editor at the right, every label suffixed "(Text N)".
-- The font colour chip holds the class-colour SOURCE (no toggle). The Layer
-- Override plate is the rings'.
local TEXT_ROW_H = 27
local textsSection

local function textLayerGet(field, default)
  return function() local tc = TextCfg(); return tc and orDefault(tc[field], default) end
end

textsSection = function(b, sc)
  local w, rows = {}, {}
  local function R() sc.refresh() end
  local function apply() GU:ApplyLayout(selected) end
  local function selectPiece(i) textSel[selected] = i; RefreshEditor() end

  -- the rows
  local function row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, b); r:SetSize(444, 17)
    r.num = UI.label(r, ""); r.num:SetPoint("LEFT", 0, 0)
    r.field = UI.field(r, 299); r.field:SetPoint("LEFT", 57, 0); r.field:SetMaxLetters(200)
    local function commit(self)
      local list = TextList(); local tc = list and list[i]; if not tc then return end
      local v = self:GetText() or ""
      if v ~= tc.template then tc.template = v; apply() end
    end
    r.field:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    r.field:HookScript("OnEditFocusLost", commit)
    r.field:SetScript("OnEscapePressed", function(self) local list = TextList(); local tc = list and list[i]; self:SetText(tc and tc.template or ""); self:ClearFocus() end)
    r.field:HookScript("OnEditFocusGained", function() if (textSel[selected] or 1) ~= i then selectPiece(i) end end)
    attachTip(r.field, "Template", "Words and [shortcodes], in any order — the list below has every code.")
    r.edit = UI.button(r, "Edit", { kind = "action", w = 82, onClick = function() selectPiece(i) end })
    r.edit:SetPoint("LEFT", 362, 0)
    rows[i] = r
    return r
  end
  w.add = UI.button(b, "Add Text", { kind = "action", onClick = function()
    local list = TextList(); if not list then return end
    list[#list + 1] = NewTextPiece("[name]")
    apply(); selectPiece(#list)
  end })
  attachTip(w.add, "Add a text", "A new piece showing the unit's name, placed at the centre. Move it with the offsets.")
  w.dup = UI.button(b, "Duplicate", { kind = "action", onClick = function()
    local list = TextList(); local tc, i = TextCfg()
    if not (list and tc) then return end
    local t = CopyTable(tc); t.y = (t.y or 0) - (t.size or 22) - 4
    table.insert(list, i + 1, t)
    apply(); selectPiece(i + 1)
  end })
  attachTip(w.dup, "Duplicate", "A copy of the selected piece, one line lower.")
  w.del = UI.button(b, "Delete", { kind = "warn", onClick = function()
    local list = TextList(); local tc, i = TextCfg()
    if not (list and tc) then return end
    UI.confirm(("Delete Text %d?\n\n%s"):format(i, tc.template ~= "" and tc.template or "(empty)"), function()
      table.remove(list, i)
      apply(); selectPiece(math.max(1, math.min(i, #list)))
    end, "Delete", "Delete text")
  end })
  w.del:SetPoint("TOPLEFT", 415, 0); w.dup:SetPoint("RIGHT", w.del, "LEFT", -6, 0); w.add:SetPoint("RIGHT", w.dup, "LEFT", -6, 0)

  -- the shortcodes, straight from the engine so they cannot drift. EVERY
  -- [code] on a line is its own link (the owner, 2026-09-21: one link per
  -- line inserted only the first); they are laid right-to-left so the
  -- column stays right-aligned at x=158, the description from x=165.
  local codes = CreateFrame("Frame", nil, b); codes:SetSize(460, 230)
  local ct = UI.label(codes, "Shortcodes"); ct:SetPoint("TOPLEFT", 0, 0)
  local function insertCode(code)
    local tc = TextCfg(); if not tc then return end
    local tpl = tc.template or ""
    tc.template = (tpl == "" and "" or tpl .. " ") .. code
    apply(); R()
  end
  local y = -22
  for _, h in ipairs(GU.TEXT_HELP) do
    local parts = {}
    for code in h[1]:gmatch("%S+") do parts[#parts + 1] = code end
    local prev
    for i = #parts, 1, -1 do
      local code = parts[i]
      local lk = CreateFrame("Button", nil, codes); lk:SetHeight(13)
      lk.text = newText(lk, FONT.ui, 11, COLOR.violet, "RIGHT"); lk.text:SetPoint("RIGHT", 0, 0); lk.text:SetText(code)
      lk:SetWidth(lk.text:GetStringWidth())
      if prev then lk:SetPoint("RIGHT", prev, "LEFT", -4, 0) else lk:SetPoint("TOPRIGHT", codes, "TOPLEFT", 158, y) end
      lk:SetScript("OnEnter", function(self) self.text:SetTextColor(COLOR.lilac.r, COLOR.lilac.g, COLOR.lilac.b) end)
      lk:SetScript("OnLeave", function(self) self.text:SetTextColor(COLOR.violet.r, COLOR.violet.g, COLOR.violet.b) end)
      lk:SetScript("OnClick", function() insertCode(code) end)
      prev = lk
    end
    local what = newText(codes, FONT.ui, 11, COLOR.ink, "LEFT"); what:SetPoint("TOPLEFT", 165, y); what:SetPoint("TOPRIGHT", 0, y)
    what:SetWordWrap(false); what:SetText(h[2])
    y = y - 13
  end
  w.codes = codes

  -- the editor
  local function lab(text) local _, i = TextCfg(); return ("%s (Text %d)"):format(text, i or 1) end
  w.enabled = toggleCell(b, "Status", tget("enabled", true), tset("enabled")); w.enabled:SetPoint("TOPLEFT", 527, 0)
  w.size = dialCell(b, { label = "Font Size", min = 6, max = 72, unit = "px", get = tget("size", 22), set = tset("size") }); w.size:SetPoint("TOPLEFT", 672, 0)
  w.color = chipCell(b, "Font Color", {
    get = function() local tc = TextCfg(); if not tc then return nil end; if tc.classColor then return "class" end; return tc.color end,
    set = function(v) local tc = TextCfg(); if not tc then return end
      if v == "class" then tc.classColor = true elseif type(v) == "table" then tc.classColor = false; tc.color = v end; apply() end,
    fixed = function() local tc = TextCfg(); return tc and tc.color end,
    sources = { { value = "class", label = "Use Class Color", word = "Class", color = function()
      local ok, r, g, bb = GU.UnitColor(selected)
      if ok and not (issecretvalue and issecretvalue(r)) then return r, g, bb end
    end } },
    label = "Unit Frames › text color", title = "Font Color" })
  w.color:SetPoint("TOPLEFT", 899, 0)
  w.font = pickCell(b, "Font", 340,
    function() local tc = TextCfg(); local f = tc and tc.font; return (f and f ~= "") and f or "Unit default" end,
    function() return fontOptions("Unit default") end,
    function() local tc = TextCfg(); return tc and tc.font or "" end,
    function(v) local tc = TextCfg(); if tc then tc.font = (v ~= "") and v or nil; apply() end end)
  w.font:SetPoint("TOPLEFT", 527, -55)
  w.outline = segCell(b, "Outline", { { value = "none", label = "None" }, { value = "thin", label = "Thin" }, { value = "thick", label = "Thick" } },
    tget("outline", "none"), tset("outline"))
  w.outline:SetPoint("TOPLEFT", 527, -110)
  local JUST = { { label = "Left", value = "LEFT" }, { label = "Center", value = "CENTER" }, { label = "Right", value = "RIGHT" } }
  local JUST_LABEL = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
  w.justify = pickCell(b, "Alignment", 105,
    function() return JUST_LABEL[tget("justify", "CENTER")()] or "Center" end,
    function() return JUST end, tget("justify", "CENTER"), tset("justify"))
  w.justify:SetPoint("TOPLEFT", 764, -110)
  attachTip(w.justify.control, "Alignment", "Left: the text grows to the right from its offset. Center: centred on it. Right: grows to the left.")
  w.shadow = toggleCell(b, "Drop Shadow", tget("shadow", true), tset("shadow")); w.shadow:SetPoint("TOPLEFT", 894, -110)
  w.maxWidth = dialCell(b, { label = "Max Width", min = 0, max = 600, unit = "px", get = tget("maxWidth", 0), set = tset("maxWidth") }); w.maxWidth:SetPoint("TOPLEFT", 527, -175)
  attachTip(w.maxWidth.strip, "Max width", "Longer text is cut with … past this width. 0 = no limit.")
  w.x = dialCell(b, { label = "Horizontal Offset", min = -800, max = 800, unit = "px", centre = true, get = tget("x", 0), set = tset("x") }); w.x:SetPoint("TOPLEFT", 794, -175)
  w.y = dialCell(b, { label = "Vertical Offset", min = -800, max = 800, unit = "px", centre = true, get = tget("y", 0), set = tset("y") }); w.y:SetPoint("TOPLEFT", 794, -230)

  -- the Layer Override plate
  local plate = CreateFrame("Frame", nil, b); plate:SetSize(350, 63)
  UI.tint(UI.roundFill(plate), COLOR.faint)
  w.plate = plate
  w.ownLayer = toggleCell(plate, "Layer Override", function() local tc = TextCfg(); return tc and GU:TextOwnLayer(tc) end,
    function(v)
      local tc = TextCfg(); if not tc then return end
      tc.ownLayer = v and true or false
      if v then
        local f = GU:Frame(selected)
        tc.strata = tc.strata or (f and f:GetFrameStrata()) or "MEDIUM"
        tc.level = tc.level or 70
      end
      apply(); R()
    end)
  w.ownLayer:SetPoint("TOPLEFT", 20, -14)
  attachTip(w.ownLayer.control, "Layer override", "Off: the text sits on the unit's layer, above its rings. On: its own layer and level — Gloom's Overlays' two numbers.")
  w.strata = pickCell(plate, "Layer", 112,
    function() local tc = TextCfg(); return tc and STRATA_LABEL[tc.strata or "MEDIUM"] or "Medium" end,
    function() local opts = {}; for _, st in ipairs(STRATA) do opts[#opts + 1] = { label = st[2], value = st[1] } end; return opts end,
    function() local tc = TextCfg(); return tc and (tc.strata or "MEDIUM") end,
    tset("strata"))
  w.strata:SetPoint("TOPLEFT", 156, -14)
  w.level = cellAt(plate, "Level", function(c)
    local e = UI.field(c, 42, { justify = "CENTER" })
    local function commit(self)
      local v = tonumber((self:GetText() or ""):match("%-?%d+"))
      local tc = TextCfg()
      if v and tc then tc.level = math.max(0, math.min(1000, v)); apply() end
      self:refresh()
    end
    function e:refresh() local tc = TextCfg(); self:SetText(tostring(tc and tc.level or 70)) end
    e:SetScript("OnEditFocusLost", commit)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) self:refresh(); self:ClearFocus() end)
    e.stepper = function(self, delta) local tc = TextCfg(); if tc then tc.level = math.max(0, math.min(1000, (tc.level or 70) + delta)); apply(); self:refresh(); self:HighlightText() end end
    return e
  end)
  w.level:SetPoint("TOPLEFT", 288, -14)

  local editor = { w.enabled, w.size, w.color, w.font, w.outline, w.justify, w.shadow, w.maxWidth, w.x, w.y, w.plate }
  local labelled = { { w.enabled, "Status" }, { w.size, "Font Size" }, { w.color, "Font Color" }, { w.font, "Font" }, { w.outline, "Outline" },
                     { w.justify, "Alignment" }, { w.shadow, "Drop Shadow" }, { w.maxWidth, "Max Width" }, { w.x, "Horizontal Offset" }, { w.y, "Vertical Offset" } }

  sc.refresh = function()
    local list = TextList()
    if not list then return end
    local n = #list
    if (textSel[selected] or 1) > n then textSel[selected] = n end
    local cur = textSel[selected] or 1
    for i = 1, n do
      local r = row(i)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 50, -(i - 1) * TEXT_ROW_H)
      r.num:SetText(("Text %d"):format(i))
      if not r.field:HasFocus() then r.field:SetText(list[i].template or "") end
      r.edit:SetLabel(i == cur and "Editing" or "Edit"); r.edit:SetActive(i == cur)
      r.num:SetAlpha(list[i].enabled == false and 0.5 or 1)
      r:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    local btnY = n * TEXT_ROW_H + 5
    w.del:ClearAllPoints(); w.del:SetPoint("TOPLEFT", 415, -btnY)
    w.dup:SetEnabled(n > 0); w.del:SetEnabled(n > 0)
    codes:ClearAllPoints(); codes:SetPoint("TOPLEFT", 50, -(btnY + 37))
    local tc = list[cur]
    for _, e in ipairs(editor) do e:SetShown(tc ~= nil) end
    plate:ClearAllPoints(); plate:SetPoint("TOPLEFT", 660, -344)
    sc.height = math.max(407, btnY + 37 + 230) + 3
    if not tc then return end
    for _, e in ipairs(labelled) do e[1].label:SetText(lab(e[2])) end
    for _, e in ipairs({ w.enabled, w.size, w.color, w.font, w.outline, w.justify, w.shadow, w.maxWidth, w.x, w.y, w.ownLayer, w.strata, w.level }) do e:refresh() end
    local own = GU:TextOwnLayer(tc)
    w.strata:setEnabled(own); w.level:setEnabled(own)
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
  return #parts > 0 and table.concat(parts, " · ") or "any"
end

-- ★ THE KIT'S AURAS PANEL (redesign stage 2, 2026-09-21), from the Auras mock
-- (`661:6273`) at its coordinates: a ROW per group — "Group N", its NAME in a
-- white field, EDIT / EDITING — 27px apart; ADD GROUP · DUPLICATE · DELETE
-- under them; the selected group's editor at the right, labels suffixed
-- "(Group N)": Status · Aura Type (BUFFS | DEBUFFS) · Icon Shape · the dials
-- · Grow Directions (two bars) · Cooldown Swipe · Countdown / Stack Count +
-- their sizes · Display Order · the FILTERS button (the mock's "ANY • MODIFY
-- FILTERS" — it opens the filter panel, which is still pre-kit) · the Layer
-- Override plate. The mock has no "dark edge" control; that setting keeps
-- its saved value.
local AURA_ROW_H = 27

local function aurasSection(b, sc)
  local w, rows = {}, {}
  local function selectGroup(i) auraSel[selected] = i; RefreshEditor() end
  local function R() sc.refresh() end
  local function apply() GU:ApplyLayout(selected) end

  local function row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, b); r:SetSize(358, 17)
    r.num = UI.label(r, ""); r.num:SetPoint("LEFT", 0, 0)
    r.field = UI.field(r, 207); r.field:SetPoint("LEFT", 62, 0); r.field:SetMaxLetters(40)
    local function commit(self)
      local list = AuraList(); local ac = list and list[i]; if not ac then return end
      local v = (self:GetText() or ""):match("^%s*(.-)%s*$")
      ac.name = (v ~= "") and v or nil
      self:SetText(ac.name or GU.AURA_KIND_LABEL[ac.kind] or "")
    end
    r.field:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    r.field:HookScript("OnEditFocusLost", commit)
    r.field:SetScript("OnEscapePressed", function(self) local list = AuraList(); local ac = list and list[i]; self:SetText(ac and (ac.name or GU.AURA_KIND_LABEL[ac.kind]) or ""); self:ClearFocus() end)
    r.field:HookScript("OnEditFocusGained", function() if (auraSel[selected] or 1) ~= i then selectGroup(i) end end)
    attachTip(r.field, "Name", "What this group is called here. It changes nothing on screen.")
    r.edit = UI.button(r, "Edit", { kind = "action", w = 82, onClick = function() selectGroup(i) end })
    r.edit:SetPoint("LEFT", 276, 0)
    rows[i] = r
    return r
  end
  w.add = UI.button(b, "Add Group", { kind = "action", onClick = function()
    local list = AuraList(); if not list then return end
    list[#list + 1] = NewAuraGroup(selected == "target" and "debuffs" or "buffs")
    apply(); selectGroup(#list)
  end })
  attachTip(w.add, "Add an aura group", "A new row of icons at the centre of the frame. Move it with the offsets.")
  w.dup = UI.button(b, "Duplicate", { kind = "action", onClick = function()
    local list = AuraList(); local ac, i = AuraCfg()
    if not (list and ac) then return end
    local t = CopyTable(ac); t.y = (t.y or 0) - (t.size or 28) - 6
    table.insert(list, i + 1, t)
    apply(); selectGroup(i + 1)
  end })
  attachTip(w.dup, "Duplicate", "A copy of the selected group, one row lower.")
  w.del = UI.button(b, "Delete", { kind = "warn", onClick = function()
    local list = AuraList(); local ac, i = AuraCfg()
    if not (list and ac) then return end
    UI.confirm(("Delete Group %d (%s)?"):format(i, ac.name or GU.AURA_KIND_LABEL[ac.kind] or "?"), function()
      table.remove(list, i)
      apply(); selectGroup(math.max(1, math.min(i, #list)))
    end, "Delete", "Delete aura group")
  end })
  w.dup:SetPoint("RIGHT", w.del, "LEFT", -6, 0); w.add:SetPoint("RIGHT", w.dup, "LEFT", -6, 0)

  -- the editor
  local function lab(text) local _, i = AuraCfg(); return ("%s (Group %d)"):format(text, i or 1) end
  w.enabled = toggleCell(b, "Status", aget("enabled", true), aset("enabled")); w.enabled:SetPoint("TOPLEFT", 459, 0)
  w.kind = segCell(b, "Aura Type", { { value = "buffs", label = "Buffs" }, { value = "debuffs", label = "Debuffs" } },
    aget("kind", "buffs"), function(v) aset("kind")(v); R() end)
  w.kind:SetPoint("TOPLEFT", 615, 0)
  attachTip(w.kind.control, "Aura type", "Buffs or debuffs, narrowed by the Filters. Which auras count is decided by the game, so it matches Blizzard's own frames.")
  w.shape = pickCell(b, "Icon Shape", 195,
    function() local ac = AuraCfg(); local hub = GloomsHub; local k = ac and ac.shape
      return (k and hub.SHAPES and hub.SHAPES[k] and hub.SHAPES[k].label) or "Square (none)" end,
    function()
      local opts = { { label = "Square (none)", value = "" } }
      local hub = GloomsHub
      for _, k in ipairs(hub.SHAPE_ORDER or {}) do opts[#opts + 1] = { label = hub.SHAPES[k].label, value = k } end
      return opts
    end,
    function() local ac = AuraCfg(); return ac and ac.shape or "" end,
    function(v) local ac = AuraCfg(); if ac then ac.shape = (v ~= "") and v or nil; apply(); R() end end)
  w.shape:SetPoint("TOPLEFT", 815, 0)
  attachTip(w.shape.control, "Icon shape", "The suite's silhouettes — the same catalog Gloom's Bars and Gloom's Auras draw with. The cooldown swipe follows the shape.")
  w.size = dialCell(b, { label = "Icon Size", min = 10, max = 96, unit = "px", get = aget("size", 28), set = aset("size") }); w.size:SetPoint("TOPLEFT", 576, -55)
  w.x = dialCell(b, { label = "Horizontal Offset", min = -800, max = 800, unit = "px", centre = true, get = aget("x", 0), set = aset("x") }); w.x:SetPoint("TOPLEFT", 813, -55)
  -- Grow Directions: two bars in one cell
  w.grow = cellAt(b, "Grow Directions", function(c)
    local f = CreateFrame("Frame", nil, c); f:SetSize(271, 17)
    f.h = UI.segments(f, { { value = "RIGHT", label = "Right" }, { value = "LEFT", label = "Left" } }, aget("growH", "RIGHT"), aset("growH"))
    f.h:SetPoint("LEFT", 0, 0)
    f.v = UI.segments(f, { { value = "UP", label = "Up" }, { value = "DOWN", label = "Down" } }, aget("growV", "UP"), aset("growV"))
    f.v:SetPoint("LEFT", f.h, "RIGHT", 10, 0)
    function f:refresh() self.h:refresh(); self.v:refresh() end
    return f
  end)
  w.grow:SetPoint("TOPLEFT", 50, -110)
  attachTip(w.grow.control.h, "Grow", "New icons appear in this direction."); attachTip(w.grow.control.v, "Grow", "Extra rows stack this way.")
  w.swipe = toggleCell(b, "Cooldown Swipe", aget("swipe", true), aset("swipe")); w.swipe:SetPoint("TOPLEFT", 351, -110)
  attachTip(w.swipe.control, "Cooldown swipe", "A dark sweep across the icon as the aura runs down. Drawn by the game engine.")
  w.max = dialCell(b, { label = "Max Icons", min = 1, max = 40, get = aget("max", 8), set = aset("max") }); w.max:SetPoint("TOPLEFT", 576, -110)
  w.y = dialCell(b, { label = "Vertical Offset", min = -800, max = 800, unit = "px", centre = true, get = aget("y", 0), set = aset("y") }); w.y:SetPoint("TOPLEFT", 813, -110)
  w.durOn = toggleCell(b, "Countdown", aget("showDuration", true), function(v) aset("showDuration")(v); R() end); w.durOn:SetPoint("TOPLEFT", 50, -165)
  w.durSize = dialCell(b, { label = "Countdown Size", min = 6, max = 32, unit = "px", get = aget("durationSize", 11), set = aset("durationSize") }); w.durSize:SetPoint("TOPLEFT", 201, -165)
  w.perLine = dialCell(b, { label = "Icons Per Row", min = 1, max = 40, get = aget("perLine", 8), set = aset("perLine") }); w.perLine:SetPoint("TOPLEFT", 576, -165)
  attachTip(w.perLine.strip, "Icons per row", "The row wraps after this many; 1 makes a column.")
  w.spacing = dialCell(b, { label = "Icon Spacing", min = 0, max = 20, unit = "px", get = aget("spacing", 3), set = aset("spacing") }); w.spacing:SetPoint("TOPLEFT", 813, -165)
  w.stackOn = toggleCell(b, "Stack Count", aget("showStacks", true), function(v) aset("showStacks")(v); R() end); w.stackOn:SetPoint("TOPLEFT", 50, -220)
  w.stackSize = dialCell(b, { label = "Stack Count Size", min = 6, max = 32, unit = "px", get = aget("stackSize", 11), set = aset("stackSize") }); w.stackSize:SetPoint("TOPLEFT", 201, -220)
  w.order = segCell(b, "Display Order", { { value = "default", label = "Default" }, { value = "expiring", label = "Expiring first" }, { value = "expiringLast", label = "Expiring last" } },
    aget("sort", "default"), aset("sort"))
  w.order:SetPoint("TOPLEFT", 459, -220)
  attachTip(w.order.control, "Display order", "Default is the game's own order. Expiring first puts the aura with the least time left first; Expiring last the most.")

  -- FILTERS behind the button, on the kit's night plate: "Only Timed Auras"
  -- then the engine-decided classes in two columns, each a NEVER | ANY | ONLY
  -- bar; white Play Bold labels. One block per polarity, built on first use.
  local FILTER_ROW_H = 30
  local fw = { blocks = {} }
  local function classMode(key)
    local ac = AuraCfg(); return ac and ac.filter and ac.filter.classes and ac.filter.classes[key] or "any"
  end
  local function setClass(key, mode)
    local ac = AuraCfg(); if not ac then return end
    ac.filter = ac.filter or {}; ac.filter.classes = ac.filter.classes or {}
    ac.filter.classes[key] = (mode ~= "any") and mode or nil
    apply(); R()
  end
  local function nightLabel(parent, text)
    local fs = newText(parent, FONT.uiB, 12, COLOR.paper, "LEFT"); fs:SetText(text); return fs
  end
  local TRI = { { value = "never", label = "Never" }, { value = "any", label = "Any" }, { value = "only", label = "Only" } }
  local function triRow(col, y, cls)
    local lab = nightLabel(col, cls.label); lab:SetPoint("TOPLEFT", 0, y - 2); lab:SetWordWrap(false)
    local seg = UI.segments(col, TRI, function() return classMode(cls.key) end, function(v) setClass(cls.key, v) end, { segW = 52 })
    seg:SetPoint("TOPRIGHT", 0, y)
    lab:SetPoint("RIGHT", seg, "LEFT", -8, 0)
    return seg
  end
  local function filterBlock(c, pol)
    if fw.blocks[pol] then return fw.blocks[pol] end
    local blk = CreateFrame("Frame", nil, c); blk:SetPoint("TOPLEFT"); blk:SetPoint("TOPRIGHT"); blk:SetHeight(10)
    local rows = {}
    local timedLab = nightLabel(blk, "Only Timed Auras"); timedLab:SetPoint("TOPLEFT", 30, 0)
    local timed = UI.toggleBar(blk,
      function() local ac = AuraCfg(); return ac and ac.filter and ac.filter.timed end,
      function(v) local ac = AuraCfg(); if ac then ac.filter = ac.filter or {}; ac.filter.timed = v; apply(); R() end end)
    timed:SetPoint("TOPLEFT", 30, -18)
    attachTip(timed, "Only timed auras", "Hide auras with no duration (permanent ones).")
    rows[#rows + 1] = timed
    local top = -18 - 17 - 24
    local col1 = CreateFrame("Frame", nil, blk); col1:SetPoint("TOPLEFT", 30, top); col1:SetPoint("TOPRIGHT", blk, "TOP", -15, top); col1:SetHeight(10)
    local col2 = CreateFrame("Frame", nil, blk); col2:SetPoint("TOPLEFT", blk, "TOP", 15, top); col2:SetPoint("TOPRIGHT", -30, top); col2:SetHeight(10)
    local list = {}
    for _, cls in ipairs(GU.AURA_CLASSES) do if cls.pol == "both" or cls.pol == pol then list[#list + 1] = cls end end
    local perCol = math.ceil(#list / 2)
    for i, cls in ipairs(list) do
      local col = (i <= perCol) and col1 or col2
      rows[#rows + 1] = triRow(col, -((i - 1) % perCol) * FILTER_ROW_H, cls)
    end
    top = top - perCol * FILTER_ROW_H
    blk.rows = rows
    blk.height = -top
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
    local pf = w.filterPop and w.filterPop.frame
    if pf and pf.title then pf.title:SetText(pol == "buff" and "FILTERS — BUFFS" or "FILTERS — DEBUFFS") end
    if not pol then return 10 end
    local blk = filterBlock(c, pol); blk:Show()
    for _, r in ipairs(blk.rows) do if r.refresh then r:refresh() end end
    return blk.height
  end
  w.filters = cellAt(b, "Filters", function(c)
    local bt = UI.button(c, "", { kind = "state", w = 195 })
    w.filterPop = UI.popover({ owner = bt, title = "Filters", w = 620,
      build = function(c2) return showFilters(c2) end,
      onOpen = function(c2) return showFilters(c2) end })
    bt:SetScript("OnClick", function() w.filterPop:toggle() end)
    function bt:refresh()
      local sum = FilterSummary(AuraCfg())
      self:SetLabel(sum == "any" and "Any • Modify filters" or (sum .. " • Modify"))
    end
    return bt
  end)
  w.filters:SetPoint("TOPLEFT", 815, -220)
  attachTip(w.filters.control, "Filters", "Which auras this group shows: the classes the game can tell apart, only timed ones, and spells to always or never show.")

  -- the Layer Override plate
  local plate = CreateFrame("Frame", nil, b); plate:SetSize(350, 63)
  UI.tint(UI.roundFill(plate), COLOR.faint)
  w.plate = plate
  w.ownLayer = toggleCell(plate, "Layer Override", function() local ac = AuraCfg(); return ac and GU:AuraOwnLayer(ac) end,
    function(v)
      local ac = AuraCfg(); if not ac then return end
      ac.ownLayer = v and true or false
      if v then
        local f = GU:Frame(selected)
        ac.strata = ac.strata or (f and f:GetFrameStrata()) or "MEDIUM"
        ac.level = ac.level or 60
      end
      apply(); R()
    end)
  w.ownLayer:SetPoint("TOPLEFT", 20, -14)
  attachTip(w.ownLayer.control, "Layer override", "Off: the icons sit on the unit's layer, above its rings. On: their own layer and level — Gloom's Overlays' two numbers.")
  w.strata = pickCell(plate, "Layer", 112,
    function() local ac = AuraCfg(); return ac and STRATA_LABEL[ac.strata or "MEDIUM"] or "Medium" end,
    function() local opts = {}; for _, st in ipairs(STRATA) do opts[#opts + 1] = { label = st[2], value = st[1] } end; return opts end,
    function() local ac = AuraCfg(); return ac and (ac.strata or "MEDIUM") end,
    aset("strata"))
  w.strata:SetPoint("TOPLEFT", 156, -14)
  w.level = cellAt(plate, "Level", function(c)
    local e = UI.field(c, 42, { justify = "CENTER" })
    local function commit(self)
      local v = tonumber((self:GetText() or ""):match("%-?%d+"))
      local ac = AuraCfg()
      if v and ac then ac.level = math.max(0, math.min(1000, v)); apply() end
      self:refresh()
    end
    function e:refresh() local ac = AuraCfg(); self:SetText(tostring(ac and ac.level or 60)) end
    e:SetScript("OnEditFocusLost", commit)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) self:refresh(); self:ClearFocus() end)
    e.stepper = function(self, delta) local ac = AuraCfg(); if ac then ac.level = math.max(0, math.min(1000, (ac.level or 60) + delta)); apply(); self:refresh(); self:HighlightText() end end
    return e
  end)
  w.level:SetPoint("TOPLEFT", 288, -14)
  plate:SetPoint("TOPLEFT", 660, -318)

  local editor = { w.enabled, w.kind, w.shape, w.size, w.x, w.grow, w.swipe, w.max, w.y, w.durOn, w.durSize, w.perLine, w.spacing, w.stackOn, w.stackSize, w.order, w.filters, w.plate }
  local labelled = { { w.enabled, "Status" }, { w.kind, "Aura Type" }, { w.shape, "Icon Shape" }, { w.size, "Icon Size" }, { w.x, "Horizontal Offset" },
                     { w.grow, "Grow Directions" }, { w.swipe, "Cooldown Swipe" }, { w.max, "Max Icons" }, { w.y, "Vertical Offset" }, { w.durOn, "Countdown" },
                     { w.durSize, "Countdown Size" }, { w.perLine, "Icons Per Row" }, { w.spacing, "Icon Spacing" }, { w.stackOn, "Stack Count" },
                     { w.stackSize, "Stack Count Size" }, { w.order, "Display Order" }, { w.filters, "Filters" } }

  sc.refresh = function()
    local list = AuraList()
    if not list then return end
    local n = #list
    if (auraSel[selected] or 1) > n then auraSel[selected] = n end
    local cur = auraSel[selected] or 1
    for i = 1, n do
      local r = row(i)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 50, -(i - 1) * AURA_ROW_H)
      r.num:SetText(("Group %d"):format(i))
      if not r.field:HasFocus() then r.field:SetText(list[i].name or GU.AURA_KIND_LABEL[list[i].kind] or "") end
      r.edit:SetLabel(i == cur and "Editing" or "Edit"); r.edit:SetActive(i == cur)
      r.num:SetAlpha(list[i].enabled == false and 0.5 or 1)
      r:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    local btnY = n * AURA_ROW_H + 5
    w.del:ClearAllPoints(); w.del:SetPoint("TOPLEFT", 329, -btnY)
    w.dup:SetEnabled(n > 0); w.del:SetEnabled(n > 0)
    local ac = list[cur]
    for _, e in ipairs(editor) do e:SetShown(ac ~= nil) end
    sc.height = math.max(381, btnY + 30) + 3
    if not ac then return end
    for _, e in ipairs(labelled) do e[1].label:SetText(lab(e[2])) end
    for _, e in ipairs(labelled) do e[1]:refresh() end
    w.ownLayer:refresh(); w.strata:refresh(); w.level:refresh()
    w.durSize:setEnabled(ac.showDuration ~= false)
    w.stackSize:setEnabled(ac.showStacks ~= false)
    local own = GU:AuraOwnLayer(ac)
    w.strata:setEnabled(own); w.level:setEnabled(own)
    if w.filterPop:isOpen() then w.filterPop:open() end
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

  -- GLOBAL (the mocks' "Global Player Settings"): visibility, the unit's
  -- default text font, position, layer — at the mocks' own coordinates
  -- (three columns at x=50 / 380 / 634, rows 55 apart), built from the kit
  -- as stage 1's proof. The default font (stage 2, 2026-09-21) is what a
  -- text piece with no font of its own draws in — `cfg.font`.
  local function kitPick(b, x, y, labelText, w, getLabel, getOptions, getCurrent, onPick, tip)
    local lab = UI.label(b, labelText); lab:SetPoint("TOPLEFT", x, y)
    local pk = UI.pick(b, w, getLabel, getOptions, getCurrent, onPick)
    pk:SetPoint("TOPLEFT", x, y - 18)
    if tip then attachTip(pk, labelText, tip) end
    return pk
  end
  E.globalSec = makeSection("Global player settings", 90, function(b, sc)
    E.cond = kitPick(b, 50, 0, "Visibility", 270,
      function() local cfg = Cfg(); return cfg and COND_LABEL[cfg.showCondition or "always"] or "Always" end,
      function()
        return {
          { label = "Always", value = "always" }, { label = "In combat", value = "combat" },
          { label = "Show when target is selected", value = "target" }, { label = "Combat or target", value = "combat_or_target" },
          { label = "Never", value = "never" },
        }
      end,
      function() local cfg = Cfg(); return cfg and (cfg.showCondition or "always") end,
      function(v) GU:SetCondition(selected, v); RefreshList(); RefreshEditor() end,
      "Always (the target ring still needs a target) · only in combat · only with a target · either · Never.")
    E.font = kitPick(b, 50, -55, "Unit Frame Default Font", 270,
      function() local cfg = Cfg(); local f = cfg and cfg.font; return (f and f ~= "") and f or "Suite default (Khand)" end,
      function() return fontOptions("Suite default (Khand)") end,
      function() local cfg = Cfg(); return cfg and cfg.font or "" end,
      function(v) local cfg = Cfg(); if cfg then cfg.font = (v ~= "") and v or nil; GU:ApplyLayout(selected) end end,
      "The font every text piece on this unit uses unless it picks its own in the Texts section.")
    E.xDial = UI.dial(b, { label = "Horizontal Position (X)", min = -700, max = 700, step = 1, unit = "px", centre = true,
      get = num("x", 0), set = setUnit("x") })
    E.xDial:SetPoint("TOPLEFT", 380, 0)
    E.yDial = UI.dial(b, { label = "Vertical Position (Y)", min = -400, max = 400, step = 1, unit = "px", centre = true,
      get = num("y", 0), set = setUnit("y") })
    E.yDial:SetPoint("TOPLEFT", 380, -55)
    E.strata = kitPick(b, 634, 0, "Layer (Z)", 120,
      function() local cfg = Cfg(); return cfg and STRATA_LABEL[cfg.strata or "MEDIUM"] or "Medium" end,
      function()
        local opts = {}
        for _, s in ipairs(STRATA) do opts[#opts + 1] = { label = s[2], value = s[1] } end
        return opts
      end,
      function() local cfg = Cfg(); return cfg and (cfg.strata or "MEDIUM") end,
      function(v) GU:SetStrata(selected, v) end,
      "Background is behind almost everything; Dialog above almost everything. Medium — the default — sits with most addon frames.")
    E.level = UI.dial(b, { label = "Level Within Layer", min = 0, max = 200, step = 1, get = num("level", 10), set = setUnit("level") })
    E.level:SetPoint("TOPLEFT", 634, -55)
    attachTip(E.level.strip, "Level within the layer", "Higher draws in front — use it to tuck a ring behind or in front of an overlay on the same layer. Drag anywhere on the ticks; the wheel steps it; click the number to type.")
    sc.refresh = function()
      E.cond:refresh(); E.font:refresh(); E.strata:refresh(); E.xDial:refresh(); E.yDial:refresh(); E.level:refresh()
      sc.height = 90
    end
  end)

  E.textsSec = makeSection("Texts", 300, function(b, sc) textsSection(b, sc) end)
  E.aurasSec = makeSection("Auras", 300, function(b, sc) aurasSection(b, sc) end)

  E.healthSec   = makeSection("Health Bar/Ring", 355, function(b, sc) kitRingSection(b, sc, "health", "Health", "health") end)
  E.powerSec    = makeSection("Power Bar/Ring", 415, function(b, sc) kitRingSection(b, sc, "power", "Power", "power") end)
  E.resourceSec = makeSection("Class Resource Bar/Ring", 417, function(b, sc) kitRingSection(b, sc, "resource", "Resource", "resource") end)
  E.castSec     = makeSection("Cast Bar/Ring", 442, function(b, sc) kitRingSection(b, sc, "cast", "Cast Bar", "cast") end)

  E.globalSec.open = true
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
  if E.resourceSec.hidden and E.resourceSec.open then E.resourceSec.open = false; E.globalSec.open = true end
  E.globalSec:SetTitle(("Global %s settings"):format(UNIT_LABEL[selected] or ""))
  -- Visibility "Never": the unit is hidden outright, so every OTHER section's
  -- header dims to say its settings change nothing on screen (the owner, 2026-09-21).
  local never = cfg.showCondition == "never"
  for _, sc in ipairs(sections) do sc.header:SetAlpha((never and sc ~= E.globalSec) and 0.5 or 1) end
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
  BuildTop(c)

  editorScroll = CreateFrame("ScrollFrame", nil, c)
  editorScroll:SetPoint("TOPLEFT", 0, -TOP_H)
  editorScroll:SetPoint("BOTTOMRIGHT", -24, 1)
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
    b:SetPoint("TOPRIGHT", -8, -TOP_H); b:SetPoint("BOTTOMRIGHT", -8, 2)
  end, { kit = true })

  editorBody = CreateFrame("Frame", nil, editorChild)
  editorBody:SetAllPoints()
  BuildEditor(editorBody)
  editorBody:Hide()

  emptyNote = newText(c, FONT.ui, 12, COLOR.ink, "CENTER")
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
    if what == "position" and E.xDial then E.xDial:refresh(); E.yDial:refresh() end
  end)

  SelectUnit("player")
end

-- The Suite window orders the strip itself (the mocks' order); `order` is the
-- fallback. `wordmark` is what the banner shows after "gloom"; `profile` puts
-- the profile row in the window's footer (LibGloomSkin MINOR 11).
GloomsHub:RegisterTab{
  id       = "unitframes",
  title    = "UNIT FRAMES",
  order    = 50,
  wordmark = "UNIT",
  profile  = PROFILE_API,
  build    = BuildTab,
}
