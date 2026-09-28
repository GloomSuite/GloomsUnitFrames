-- ============================================================
-- GloomsUnitFrames_Pages.lua — Gloom's Unit Frames
-- ★ THE TWO-WINDOW DESIGN (2026-09-27), from the owner's Figma page
-- "GloomSuite UI 3": "gloomUnits, Global Player Settings" · "Texts" ·
-- "Auras" · "Health Bar Ring" · "Power Bar Ring" · "Class Resources" ·
-- "Cast Bar", the "Shortcodes Popup", and the small selector beside them.
-- The Hub (Windows.lua) owns the windows: the SELECTOR (240 wide, 105 tall
-- here — just Player | Target), the SETTINGS window (400) with its TAB
-- ("gloomUNITS: Player"), the pop-outs, the headers, the scrolling and
-- Global Settings. This file draws:
--   the selector's two unit buttons;
--   the tab;
--   the seven SECTIONS — Global <Unit> Settings · Texts · Auras (Buffs &
--     Debuffs) · Health / Power / Class Resource / Cast Bar/Ring;
--   two popups of its own on the kit's window: the SHORTCODES list (the Texts
--     section's "View Shortcodes" link; a code clicked goes into the template
--     being edited, at the cursor) and an aura group's FILTERS.
-- ★ Every number is the mock's own coordinate inside its section: a labelled
-- control is 31 tall (the label's 11, 4, the 16-tall control), rows 41 apart,
-- blocks 30 apart, columns 170 at 0 / 190, three of 107/106/107 at 0 / 127 /
-- 253. A ring section is a LIST OF ROWS per face (arc / bar), laid by one flow
-- so switching Display Type just reflows; the faces the mocks show are
-- literal (Health and Cast = bar, Power and Class Resource = arc), the other
-- face of each follows the same rows with that mode's controls.
-- Disabled by another setting = 30%, never hidden; a control the face lacks is
-- simply not in its rows.
-- It is DRAWING only: every setting writes the same config fields the engine
-- (GloomsUnitFrames.lua) always read. The previous tab (GloomsUnitFrames_Tab.lua)
-- is no longer loaded; delete it once the owner approves these windows.
-- ============================================================

local SKIN_NEEDS = 17
local Skin, skinMinor
if LibStub then Skin, skinMinor = LibStub("LibGloomSkin-1.0", true) end
local GU = _G.GloomsUnitFrames
if not (Skin and GU) then return end
if (skinMinor or 0) < SKIN_NEEDS then
  print("|cffff7729Gloom's Unit Frames:|r the Unit Frames windows need Gloom's Hub with LibGloomSkin " .. SKIN_NEEDS .. " or newer — update Gloom's Hub.")
  return
end

local UI, COLOR, FONT = Skin.UI, Skin.COLOR, Skin.FONT
local LIME, LILAC, VIOLET = COLOR.lime, COLOR.lilac, COLOR.violet
local DIM = UI.G_DIM or 0.3
local LIME_HEX = ("%02x%02x%02x"):format(LIME.r * 255, LIME.g * 255, LIME.b * 255)
local attachTip = UI.attachTip

local UNIT_LABEL = { player = "Player", target = "Target" }
local selected = "player"
local P = { secs = {} }          -- every built section: { frame, refresh }

local function Cfg() return selected and GU:Config(selected) or nil end
local function RingCfg(key) local c = Cfg(); return c and c.rings and c.rings[key] or nil end
-- ★ `v or default` is WRONG for a boolean (an OFF switch would read as its
-- default): nil only.
local function orDefault(v, default) if v == nil then return default end return v end
local function apply() GU:ApplyLayout(selected) end
local function Relayout() if GloomsHub.RefreshWindows then GloomsHub:RefreshWindows("unitframes") end end
local function CopyTable(v)
  if type(v) ~= "table" then return v end
  local t = {}; for k, x in pairs(v) do t[k] = CopyTable(x) end; return t
end

-- Refresh every built section (a unit switch, a profile change).
function P.refreshAll()
  for _, s in ipairs(P.secs) do if s.refresh then s.refresh() end end
  Relayout()
end

local STRATA = {
  { "BACKGROUND", "Background" }, { "LOW", "Low" }, { "MEDIUM", "Medium" }, { "HIGH", "High" }, { "DIALOG", "Dialog" },
}
local STRATA_LABEL = {}
for _, s in ipairs(STRATA) do STRATA_LABEL[s[1]] = s[2] end
local function strataOptions() local o = {}; for _, s in ipairs(STRATA) do o[#o + 1] = { value = s[1], label = s[2] } end; return o end

local OFFON = { { false, "Off" }, { true, "On" } }

-- The font list: the fallback first ("" → nil), then every Shared Media font,
-- each drawn in its own face (the owner, 2026-09-27: "fonts show as previews").
local function fontOptions(fallback)
  local o = { { value = "", label = fallback } }
  local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
  if lsm then
    for _, name in ipairs(lsm:List("font")) do o[#o + 1] = { value = name, label = name, font = lsm:Fetch("font", name, true) } end
  end
  return o
end

-- ---------------------------------------------------------------------------
-- CELLS — a labelled control, built once, placed by its section. Each has
-- :refresh() and :setEnabled(on) (the label dims with it), and :setLabel(t).
-- ---------------------------------------------------------------------------
local function cell(parent, text, w, make)
  local c = CreateFrame("Frame", nil, parent); c:SetSize(w, 31)
  c.label = UI.gLabel(c, text or ""); c.label:SetPoint("TOPLEFT", 0, 0)
  c.control = make(c, w)
  c.control:SetPoint("TOPLEFT", 0, -15)
  function c:refresh() if self.control.refresh then self.control:refresh() end end
  function c:setEnabled(on)
    on = on and true or false
    if self.control.setEnabled then self.control:setEnabled(on) end
    self.label:SetAlpha(on and 1 or DIM)
  end
  function c:setLabel(t) self.label:SetText(t) end
  return c
end
local function Switch(parent, text, w, choices, get, set)
  return cell(parent, text, w, function(c, cw) return UI.gSwitch(c, choices, get, set, { w = cw }) end)
end
local function Drop(parent, text, w, getLabel, getOptions, getCurrent, onPick, opts)
  return cell(parent, text, w, function(c, cw) return UI.gDrop(c, cw, getLabel, getOptions, getCurrent, onPick, opts) end)
end
local function Color(parent, text, w, opts)
  opts.w = w
  opts.title = opts.title or text
  return cell(parent, text, w, function(c) return UI.gColor(c, opts) end)
end
-- A dial carries its own label; the same interface as a cell.
local function Dial(parent, w, opts)
  opts.w = w
  local d = UI.gDial(parent, opts)
  function d:setLabel(t) if self.label then self.label:SetText(t) end end
  return d
end
local function Button(parent, text, w, onClick, danger)
  return UI.gButton(parent, text, { w = w, h = 16, pad = 10, danger = danger, onClick = onClick })
end

-- place(widget, x, y) shows it there; place(widget) hides it.
local function place(wd, x, y)
  if not wd then return end
  if x then wd:ClearAllPoints(); wd:SetPoint("TOPLEFT", x, -y); wd:Show() else wd:Hide() end
end

-- THE FLOW: rows of cells, 41 apart; GAP ends a block (the next row 30 under
-- the last one instead of 10). A row is { cells = { {widget, x}, … }, h = 31 }.
-- Returns the height.
local GAP = "gap"
local function flow(all, rows)
  for _, wd in pairs(all) do if wd then wd:Hide() end end
  local y, last = 0, 0
  for _, r in ipairs(rows) do
    if r == GAP then y = y + 20
    else
      for _, c in ipairs(r.cells) do place(c[1], c[2], y) end
      last = y + (r.h or 31)
      y = last + 10
    end
  end
  return last
end
local function row(...) return { cells = { ... } } end

-- A section's frame, registered for refreshAll.
local function Section(parent, h)
  local f = CreateFrame("Frame", nil, parent); f:SetSize(360, h)
  local s = { frame = f }
  P.secs[#P.secs + 1] = s
  f:HookScript("OnShow", function() if s.refresh then s.refresh() end; if P.syncPreviews then P.syncPreviews() end end)
  f:HookScript("OnHide", function() if P.syncPreviews then P.syncPreviews() end end)
  return f, s
end
-- (the Hub re-lays the window out when a section's height changes)
local function setHeight(f, h)
  if math.abs((f:GetHeight() or 0) - h) > 0.5 then f:SetHeight(h) end
end

-- The LAYER OVERRIDE row every list item and ring ends with (the mocks' Frame
-- 528): Off|On (95) · Strata (95) · Level (130). `t()` is the table holding
-- ownLayer / strata / level; `isOn(t)`, `turnOn(t)`, `turnOff(t)` decide what
-- "own layer" means for it.
local function LayerRow(parent, t, isOn, turnOn, turnOff, levelDefault, refreshAll)
  local w = {}
  w.own = Switch(parent, "Layer Override", 95, OFFON,
    function() local x = t(); return x and isOn(x) and true or false end,
    function(v) local x = t(); if not x then return end; if v then turnOn(x) else turnOff(x) end; apply(); refreshAll() end)
  attachTip(w.own.control, "Layer override", "Off: follows the unit's layer and the automatic order. On: its own Strata and Level — Gloom's Overlays' two numbers — to slot it between overlay graphics.")
  w.strata = Drop(parent, "Strata", 95,
    function() local x = t(); return STRATA_LABEL[(x and x.strata) or "MEDIUM"] or "Medium" end,
    strataOptions,
    function() local x = t(); return (x and x.strata) or "MEDIUM" end,
    function(v) local x = t(); if x then x.strata = v; apply() end end)
  w.level = Dial(parent, 130, { label = "Level", min = 0, max = 1000, step = 1, dragPx = 1500,
    get = function() local x = t(); return (x and x.level) or levelDefault end,
    set = function(v) local x = t(); if x then x.level = v; apply() end end })
  function w:refresh()
    self.own:refresh(); self.strata:refresh(); self.level:refresh()
    local x = t(); local on = x and isOn(x) and true or false
    self.strata:setEnabled(on); self.level:setEnabled(on)
  end
  function w:row() return row({ self.own, 0 }, { self.strata, 115 }, { self.level, 230 }) end
  return w
end

-- ===========================================================================
-- THE SELECTOR — "gloomUNITS ▸" (the Hub's) and Player | Target, 98 × 23, 4
-- apart, 52 down; the chosen one violet 30% with a white word.
-- ===========================================================================
local unitBtns = {}
local function SelectUnit(which)
  selected = which
  for u, b in pairs(unitBtns) do b:SetSelected(u == which) end
  if P.windowsOpen then GU:SetEditing(which) end
  P.refreshAll()
  if P.syncPreviews then P.syncPreviews() end
end
P.SelectUnit = SelectUnit

local function buildSelector(c)
  for i, which in ipairs(GU.UNITS) do
    local b = UI.gButton(c, UNIT_LABEL[which], { w = 98, h = 23, size = 10, onClick = function() SelectUnit(which) end })
    b:SetPoint("TOPLEFT", 20 + (i - 1) * 102, -52)
    b:SetSelected(which == selected)
    unitBtns[which] = b
  end
  attachTip(unitBtns.player, "Player", "Edit the player frame. While these windows are open it can be dragged on screen; the green outline is its frame.")
  attachTip(unitBtns.target, "Target", "Edit the target frame. It shows empty until you have a target; while these windows are open it can be dragged on screen.")
end

-- ===========================================================================
-- THE TAB — "gloomUNITS:" lime, the unit white, Sansation 10.
-- ===========================================================================
local function buildTab(tab)
  local t = {}
  local lead = UI.newText(tab, FONT.sa, 10, LIME, "LEFT"); lead:SetPoint("TOPLEFT", 20, -9)
  lead:SetText("gloomUNITS: ")
  local name = UI.newText(tab, FONT.sa, 10, COLOR.paper, "LEFT"); name:SetPoint("LEFT", lead, "RIGHT", 0, 0)
  function t:refresh() name:SetText(UNIT_LABEL[selected] or "") end
  t:refresh()
  return t
end

-- ===========================================================================
-- SECTION · GLOBAL <UNIT> SETTINGS (the mock's Frame 573, 179 tall)
-- ===========================================================================
local COND = {
  { "always", "Always" }, { "combat", "In Combat" }, { "target", "Show When Target Is Selected" },
  { "combat_or_target", "Combat or Target" }, { "never", "Never" },
}
local COND_LABEL = {}
for _, c in ipairs(COND) do COND_LABEL[c[1]] = c[2] end

local function buildGlobal(parent)
  local f, s = Section(parent, 179)
  local function num(field, default) return function() local c = Cfg(); return c and orDefault(c[field], default) end end
  local function setNum(field) return function(v) local c = Cfg(); if c then c[field] = v; apply() end end end
  local cond = Drop(f, "Visibility", 170,
    function() local c = Cfg(); return COND_LABEL[(c and c.showCondition) or "always"] or "Always" end,
    function() local o = {}; for _, x in ipairs(COND) do o[#o + 1] = { value = x[1], label = x[2] } end; return o end,
    function() local c = Cfg(); return (c and c.showCondition) or "always" end,
    function(v) GU:SetCondition(selected, v); P.refreshAll() end)
  attachTip(cond.control, "Visibility", "Always (the target frame still needs a target) · only in combat · only with a target · either · Never — hidden outright.")
  place(cond, 0, 0)
  local font = Drop(f, "Unit Frame Default Font", 170,
    function() local c = Cfg(); local v = c and c.font; return (v and v ~= "") and v or "Suite default (Khand)" end,
    function() return fontOptions("Suite default (Khand)") end,
    function() local c = Cfg(); return (c and c.font) or "" end,
    function(v) local c = Cfg(); if c then c.font = (v ~= "") and v or nil; apply() end end)
  attachTip(font.control, "Default font", "What every text on this unit draws in unless it picks its own in Texts.")
  place(font, 0, 41)
  local x = Dial(f, 170, { label = "Horizontal Position", min = -700, max = 700, step = 1, unit = "px", dragPx = 1400, get = num("x", 0), set = setNum("x") })
  place(x, 190, 0)
  local y = Dial(f, 170, { label = "Vertical Position", min = -400, max = 400, step = 1, unit = "px", dragPx = 1000, get = num("y", 0), set = setNum("y") })
  place(y, 190, 41)
  local strata = Drop(f, "Strata", 170,
    function() local c = Cfg(); return STRATA_LABEL[(c and c.strata) or "MEDIUM"] or "Medium" end,
    strataOptions,
    function() local c = Cfg(); return (c and c.strata) or "MEDIUM" end,
    function(v) GU:SetStrata(selected, v) end)
  attachTip(strata.control, "Strata", "Background is behind almost everything; Dialog above almost everything. Medium — the default — sits with most addon frames.")
  place(strata, 0, 102)
  local level = Dial(f, 170, { label = "Level", min = 0, max = 200, step = 1, dragPx = 600, get = num("level", 10), set = setNum("level") })
  attachTip(level.strip, "Level", "Higher draws in front — tuck the frame behind or in front of an overlay on the same strata.")
  place(level, 190, 102)
  -- Copy Settings from <the other unit> · Reset to Defaults (both ask first)
  local copy = Button(f, "", 175, function()
    local from = (selected == "player") and "target" or "player"
    UI.confirm(("Copy the %s frame's settings onto the %s frame? Position stays as it is."):format(UNIT_LABEL[from]:lower(), UNIT_LABEL[selected]:lower()),
      function() GU:CopyFrom(selected, from); P.refreshAll() end)
  end)
  copy:SetPoint("TOPLEFT", 0, -163)
  attachTip(copy, "Copy settings", "Layer, visibility, texts and every ring the two share — sizes, angles, colors, rounding. Position is left alone. Asks first.")
  local reset = Button(f, "Reset to Defaults", 175, function()
    UI.confirm(("Reset the %s frame to its factory position, size and rings?"):format(UNIT_LABEL[selected]:lower()),
      function() GU:Reset(selected); P.refreshAll() end)
  end)
  reset:SetPoint("TOPLEFT", 185, -163)
  attachTip(reset, "Reset to defaults", "Puts this unit back where a fresh install would have it. Asks first.")
  P.globalDials = { x, y }
  s.refresh = function()
    for _, w in ipairs({ cond, font, x, y, strata, level }) do w:refresh() end
    copy:SetLabel(("Copy Settings from %s"):format(selected == "player" and "TARGET" or "PLAYER"))
  end
  return f
end

-- ===========================================================================
-- LIST ROWS (Texts and Auras): "<Noun> N" right-aligned, its field, EDIT /
-- EDITING (60) — 22 apart. The one being edited is lime: its label, its field
-- (lime 30%), its button filled lime with a black word.
-- ===========================================================================
local function listRow(parent, labelW, onSelect, onCommit, tip)
  local r = CreateFrame("Frame", nil, parent); r:SetSize(360, 16)
  r.num = UI.newText(r, FONT.sa, 10, LILAC, "RIGHT"); r.num:SetPoint("LEFT", 0, 0); r.num:SetWidth(labelW)
  r.field = UI.gField(r, 360 - labelW - 6 - 6 - 60, {
    commit = function(text) onCommit(r.index, text) end,
    revert = function(self) if r.revertText then self:SetText(r.revertText) end end,
  })
  r.field:SetPoint("LEFT", labelW + 6, 0)
  r.field:HookScript("OnEditFocusGained", function() if not r.current then onSelect(r.index) end end)
  if tip then attachTip(r.field, tip[1], tip[2]) end
  r.btn = UI.gButton(r, "Edit", { w = 60, h = 16, size = 10, onClick = function() onSelect(r.index) end })
  r.btn:SetPoint("LEFT", 300, 0)
  -- the lime EDITING state on top of the kit button
  local lime = r.btn:CreateTexture(nil, "ARTWORK", nil, -1); lime:SetAllPoints(); lime:SetColorTexture(LIME.r, LIME.g, LIME.b, 1); lime:Hide()
  function r:set(i, label, text, current, dimmed)
    self.index, self.current, self.revertText = i, current, text
    self.num:SetText(label)
    local c = current and LIME or LILAC
    self.num:SetTextColor(c.r, c.g, c.b); self.num:SetAlpha(dimmed and DIM or 1)
    if not self.field:HasFocus() then self.field:SetText(text or "") end
    local bc = current and LIME or VIOLET
    self.field.bg:SetColorTexture(bc.r, bc.g, bc.b, 0.3)
    self.btn:SetLabel(current and "Editing" or "Edit")
    lime:SetShown(current)
    if self.btn.edge then self.btn.edge:SetShown(not current) end
    if current then self.btn.text:SetTextColor(0, 0, 0) end
  end
  r.btn:HookScript("OnLeave", function() if r.current then r.btn.text:SetTextColor(0, 0, 0) end end)
  r.btn:HookScript("OnEnter", function() if r.current then r.btn.text:SetTextColor(0, 0, 0) end end)
  return r
end
-- "<label> (Text N)" with the suffix in lime.
local function suffixed(label, noun, i) return ("%s |cff%s(%s %d)|r"):format(label, LIME_HEX, noun, i or 1) end

-- ===========================================================================
-- THE SHORTCODES POPUP (the mock's "Shortcodes Popup", 343 wide): "Shortcodes"
-- (Sansation 14), then a line per group, 13 apart — the codes lilac and
-- right-aligned, EVERY code its own link, 10 on the description in white.
-- A code clicked goes into the template being edited, at its cursor.
-- ===========================================================================
local CODES = {
  { "[name] [name:8]", "name | first 8 letters" },
  { "[level]", "level | '??' for a skull" },
  { "[class] [race] [type]", "e.g. Warlock | Orc | Demon" },
  { "[elite]", "Elite/Rare/Boss" },
  { "[hp] [hp:1] [hp:full] [hpmax]", "health, various lengths" },
  { "[hp:pct]", "health percentage" },
  { "[absorb] [heals]", "shield | incoming heals" },
  { "[power] [powermax] [power:pct]", "mana, rage, energy, etc" },
  { "[powertype]", "Mana, Energy, etc" },
  { "[shards] [shards:max]", "class resource unit count" },
  { "[cast] [casttime] [casttime:total]", "spell name | seconds left" },
  { "[kick]", "a mark for uninterruptible cast" },
  { "[status]", "dead/ghost/offline/afk/dnd" },
  { "[combat] [resting] [pvp] [leader]", "a mark when true" },
  { "[mark]", "a raid target icon" },
  { "[threat]", "your threat as percentage" },
}
local function popupWindow(w, h, onHide)
  local root = GloomsHub.SuiteRoot and GloomsHub:SuiteRoot() or UIParent
  local win = UI.gWindow({ parent = root, w = w, h = h, minH = h, maxH = h,
    onFocus = function(self) if GloomsHub.SuiteManage then GloomsHub:SuiteManage(self) end end })
  if win.grip then win.grip:Hide() end
  if onHide then win:HookScript("OnHide", onHide) end
  function win:openBeside()
    local set = GloomsHub:SuiteWindow("unitframes", "set")
    if not self._placed and set and set:GetRight() then
      self._placed = true
      self:ClearAllPoints(); self:SetPoint("TOPLEFT", set, "TOPRIGHT", 20, 0); UI.gSnap(self)
    end
    self:Show()
    if GloomsHub.SuiteManage then GloomsHub:SuiteManage(self) end
  end
  win:Hide()
  return win
end

local codesWin
local insertCode    -- set by the Texts section
local function openShortcodes()
  if not codesWin then
    codesWin = popupWindow(343, 20 + 16 + 10 + #CODES * 13 + 20)
    local c = codesWin.content
    local title = UI.newText(c, FONT.sa, 14, COLOR.paper, "LEFT"); title:SetPoint("TOPLEFT", 20, -20); title:SetText("Shortcodes")
    -- the code column is as wide as its widest line
    local probe = UI.newText(c, FONT.sa, 10, LILAC, "LEFT")
    local colW = 0
    for _, g in ipairs(CODES) do probe:SetText(g[1]); colW = math.max(colW, math.ceil(probe:GetStringWidth())) end
    probe:Hide()
    for li, g in ipairs(CODES) do
      local y = -(46 + (li - 1) * 13)
      local parts = {}
      for code in g[1]:gmatch("%S+") do parts[#parts + 1] = code end
      local prev
      for i = #parts, 1, -1 do
        local code = parts[i]
        local lk = CreateFrame("Button", nil, c); lk:SetHeight(13)
        lk.text = UI.newText(lk, FONT.sa, 10, LILAC, "RIGHT"); lk.text:SetPoint("RIGHT", 0, 0); lk.text:SetText(code)
        lk:SetWidth(math.ceil(lk.text:GetStringWidth()))
        if prev then lk:SetPoint("RIGHT", prev, "LEFT", -3, 0) else lk:SetPoint("TOPRIGHT", c, "TOPLEFT", 20 + colW, y) end
        lk:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
        lk:SetScript("OnLeave", function(self) self.text:SetTextColor(LILAC.r, LILAC.g, LILAC.b) end)
        lk:SetScript("OnClick", function() if insertCode then insertCode(code) end end)
        attachTip(lk, code, "Click to put it into the text being edited, where the cursor was.")
        prev = lk
      end
      local what = UI.newText(c, FONT.sa, 10, COLOR.paper, "LEFT"); what:SetPoint("TOPLEFT", 20 + colW + 10, y)
      what:SetText(g[2]); what:SetWordWrap(false)
    end
  end
  if codesWin:IsShown() then codesWin:Hide() else codesWin:openBeside() end
end

-- ===========================================================================
-- SECTION · TEXTS (the mock's Frame 580)
-- ===========================================================================
local textSel = {}
local function TextList() local c = Cfg(); return c and c.texts or nil end
local function TextCfg() local l = TextList(); if not l then return nil end; local i = textSel[selected] or 1; return l[i], i end
local function tget(field, default) return function() local t = TextCfg(); return t and orDefault(t[field], default) end end
local function tset(field) return function(v) local t = TextCfg(); if t then t[field] = v; apply() end end end

local function buildTexts(parent)
  local f, s = Section(parent, 435)
  local rows, w = {}, {}
  local function R() s.refresh() end
  local function selectPiece(i) textSel[selected] = i; R() end
  local function commit(i, text)
    local l = TextList(); local t = l and l[i]; if not t then return end
    if text ~= t.template then t.template = text; apply() end
  end
  local function getRow(i)
    if not rows[i] then rows[i] = listRow(f, 30, selectPiece, commit, { "Template", "Words and [shortcodes], in any order — View Shortcodes lists every code." }) end
    return rows[i]
  end
  -- Where a code goes: the field of the piece being edited, at the cursor it
  -- last had (the end if it was never clicked).
  insertCode = function(code)
    local l = TextList(); local t, i = TextCfg(); if not t then return end
    local r = rows[i]
    local tpl = t.template or ""
    local at = (r and r.cursor) and math.min(r.cursor, #tpl) or #tpl
    local before, after = tpl:sub(1, at), tpl:sub(at + 1)
    local pad = (before ~= "" and not before:match("%s$")) and " " or ""
    t.template = before .. pad .. code .. after
    if r then r.cursor = #before + #pad + #code end
    apply(); R()
  end
  w.add = Button(f, "Add Text", 113, function()
    local l = TextList(); if not l then return end
    local t = CopyTable(GU.TEXT_DEFAULTS); t.template = "[name]"
    l[#l + 1] = t; apply(); selectPiece(#l)
  end)
  attachTip(w.add, "Add a text", "A new piece showing the unit's name, at the center. Move it with the offsets.")
  w.dup = Button(f, "Duplicate", 114, function()
    local l = TextList(); local t, i = TextCfg(); if not (l and t) then return end
    local c = CopyTable(t); c.y = (c.y or 0) - (c.size or 22) - 4
    table.insert(l, i + 1, c); apply(); selectPiece(i + 1)
  end)
  attachTip(w.dup, "Duplicate", "A copy of the text being edited, one line lower.")
  w.del = Button(f, "Delete", 113, function()
    local l = TextList(); local t, i = TextCfg(); if not (l and t) then return end
    UI.confirm(("Delete Text %d?\n\n%s"):format(i, (t.template ~= "" and t.template) or "(empty)"), function()
      table.remove(l, i); apply(); selectPiece(math.max(1, math.min(i, #l)))
    end, "Delete", "Delete text")
  end, true)
  -- "View Shortcodes": plain lime text, a link
  w.codes = CreateFrame("Button", nil, f); w.codes:SetHeight(14)
  w.codes.text = UI.newText(w.codes, FONT.sa, 9, LIME, "LEFT"); w.codes.text:SetPoint("LEFT", 0, 0); w.codes.text:SetText("View Shortcodes")
  w.codes:SetWidth(math.ceil(w.codes.text:GetStringWidth()))
  w.codes:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
  w.codes:SetScript("OnLeave", function(self) self.text:SetTextColor(LIME.r, LIME.g, LIME.b) end)
  w.codes:SetScript("OnClick", openShortcodes)

  -- the editor
  w.enabled = Switch(f, "Status", 170, OFFON, tget("enabled", true), function(v) tset("enabled")(v); R() end)
  w.size = Dial(f, 170, { label = "Font Size", min = 6, max = 72, step = 1, unit = "px", dragPx = 400, get = tget("size", 22), set = tset("size") })
  w.font = Drop(f, "Font", 170,
    function() local t = TextCfg(); local v = t and t.font; return (v and v ~= "") and v or "Unit default" end,
    function() return fontOptions("Unit default") end,
    function() local t = TextCfg(); return (t and t.font) or "" end,
    function(v) local t = TextCfg(); if t then t.font = (v ~= "") and v or nil; apply() end end)
  local function unitClassRGB()
    local ok, r, g, b = GU.UnitColor(selected)
    if ok and not (issecretvalue and issecretvalue(r)) then return r, g, b end
  end
  w.color = Color(f, "Font Color", 170, { required = true,
    get = function() local t = TextCfg(); if not t then return nil end
      if t.classColor then local r, g, b = unitClassRGB(); if r then return { r, g, b } end end
      return t.color end,
    set = function(v) local t = TextCfg(); if t then t.classColor = false; t.color = v; apply() end end,
    sources = { { value = "class", label = "Use Class Color", word = "Class", color = unitClassRGB } },
    getSource = function() local t = TextCfg(); return (t and t.classColor) and "class" or nil end,
    setSource = function() local t = TextCfg(); if t then t.classColor = true; apply() end end })
  w.justify = Switch(f, "Alignment", 170, { { "LEFT", "Left" }, { "CENTER", "Center" }, { "RIGHT", "Right" } }, tget("justify", "CENTER"), tset("justify"))
  attachTip(w.justify.control, "Alignment", "Left: the text grows to the right from its offset. Center: centered on it. Right: grows to the left.")
  w.outline = Switch(f, "Outline", 170, { { "none", "None" }, { "thin", "Thin" }, { "thick", "Thick" } }, tget("outline", "none"), tset("outline"))
  w.maxWidth = Dial(f, 170, { label = "Max Width", min = 0, max = 600, step = 1, unit = "px", dragPx = 900, get = tget("maxWidth", 0), set = tset("maxWidth") })
  attachTip(w.maxWidth.strip, "Max width", "Longer text is cut with … past this width. 0 = no limit.")
  w.shadow = Switch(f, "Drop Shadow", 170, OFFON, tget("shadow", true), tset("shadow"))
  w.x = Dial(f, 170, { label = "Horizontal Offset", min = -800, max = 800, step = 1, unit = "px", dragPx = 1600, get = tget("x", 0), set = tset("x") })
  w.y = Dial(f, 170, { label = "Vertical Offset", min = -800, max = 800, step = 1, unit = "px", dragPx = 1600, get = tget("y", 0), set = tset("y") })
  w.layer = LayerRow(f, function() return (TextCfg()) end,
    function(t) return GU:TextOwnLayer(t) end,
    function(t) local fr = GU:Frame(selected); t.ownLayer = true; t.strata = t.strata or (fr and fr:GetFrameStrata()) or "MEDIUM"; t.level = t.level or 70 end,
    function(t) t.ownLayer = false end, 70, R)
  local labelled = { { w.enabled, "Status" }, { w.size, "Font Size" }, { w.font, "Font" }, { w.color, "Font Color" }, { w.justify, "Alignment" },
                     { w.outline, "Outline" }, { w.maxWidth, "Max Width" }, { w.shadow, "Drop Shadow" }, { w.x, "Horizontal Offset" }, { w.y, "Vertical Offset" } }
  local editor = { w.enabled, w.size, w.font, w.color, w.justify, w.outline, w.maxWidth, w.shadow, w.x, w.y, w.layer.own, w.layer.strata, w.layer.level }

  s.refresh = function()
    local l = TextList(); if not l then return end
    local n = #l
    if (textSel[selected] or 1) > n then textSel[selected] = math.max(1, n) end
    local cur = textSel[selected] or 1
    for i = 1, n do
      local r = getRow(i)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
      r:set(i, ("Text %d"):format(i), l[i].template or "", i == cur, l[i].enabled == false)
      r:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    local by = math.max(0, n * 22 - 6) + 10       -- the rows' block (16 each, 6 apart), then 10
    w.add:ClearAllPoints(); w.add:SetPoint("TOPLEFT", 0, -by)
    w.dup:ClearAllPoints(); w.dup:SetPoint("TOPLEFT", 123, -by)
    w.del:ClearAllPoints(); w.del:SetPoint("TOPLEFT", 247, -by)
    w.dup:setEnabled(n > 0); w.del:setEnabled(n > 0)
    w.codes:ClearAllPoints(); w.codes:SetPoint("TOPLEFT", 0, -(by + 26))
    local ey = by + 26 + 14 + 30                  -- the editor, 30 under the link
    local t = l[cur]
    for _, e in ipairs(editor) do e:SetShown(t ~= nil) end
    if not t then setHeight(f, ey - 30); return end
    for _, e in ipairs(labelled) do e[1]:setLabel(suffixed(e[2], "Text", cur)) end
    place(w.enabled, 0, ey); place(w.size, 190, ey)
    place(w.font, 0, ey + 41); place(w.color, 190, ey + 41)
    place(w.justify, 0, ey + 82); place(w.outline, 190, ey + 82)
    place(w.maxWidth, 0, ey + 123); place(w.shadow, 190, ey + 123)
    place(w.x, 0, ey + 184); place(w.y, 0, ey + 225)
    place(w.layer.own, 0, ey + 286); place(w.layer.strata, 115, ey + 286); place(w.layer.level, 230, ey + 286)
    for _, e in ipairs(editor) do if e.refresh then e:refresh() end end
    w.layer:refresh()
    setHeight(f, ey + 286 + 31)
  end
  -- remember each field's cursor, for the shortcodes
  local get0 = getRow
  getRow = function(i)
    local r = get0(i)
    if not r._cursorHooked then
      r._cursorHooked = true
      r.field:HookScript("OnCursorChanged", function(self) r.cursor = self:GetCursorPosition() end)
    end
    return r
  end
  return f
end

-- ===========================================================================
-- SECTION · AURAS (BUFFS & DEBUFFS) (the mock's Frame 580, groups at 22)
-- ===========================================================================
local auraSel = {}
local function AuraList() local c = Cfg(); return c and c.auras or nil end
local function AuraCfg() local l = AuraList(); if not l then return nil end; local i = auraSel[selected] or 1; return l[i], i end
local function aget(field, default) return function() local a = AuraCfg(); return a and orDefault(a[field], default) end end
local function aset(field) return function(v) local a = AuraCfg(); if a then a[field] = v; apply() end end end

local function FilterSummary(ac)
  local fl = ac and ac.filter
  if not fl then return "Any" end
  local only, never = 0, 0
  for _, m in pairs(fl.classes or {}) do if m == "only" then only = only + 1 elseif m == "never" then never = never + 1 end end
  local parts = {}
  if fl.timed then parts[#parts + 1] = "Timed" end
  if only > 0 then parts[#parts + 1] = only .. " only" end
  if never > 0 then parts[#parts + 1] = never .. " never" end
  return #parts > 0 and table.concat(parts, " · ") or "Any"
end

-- THE FILTERS POPUP — an aura group's filters on the kit's window, the rows of
-- the settings sections: Only Timed Auras, then every class the game can tell
-- apart for this polarity as Never | Any | Only, two columns.
local filterWin
local filterBlocks = {}
local function refreshFilters()
  if not (filterWin and filterWin:IsShown()) then return end
  local ac = AuraCfg()
  local pol = ac and ((ac.kind == "buffs") and "buff" or "debuff") or nil
  filterWin.title:SetText(pol == "buff" and "Filters — Buffs" or "Filters — Debuffs")
  for k, blk in pairs(filterBlocks) do blk:SetShown(k == pol) end
  local blk = pol and filterBlocks[pol]
  if not blk then
    local c = filterWin.content
    blk = CreateFrame("Frame", nil, c); blk:SetPoint("TOPLEFT", 20, -54); blk:SetSize(360, 10)
    blk.cells = {}
    local timed = Switch(blk, "Only Timed Auras", 170, OFFON,
      function() local a = AuraCfg(); return a and a.filter and a.filter.timed and true or false end,
      function(v) local a = AuraCfg(); if a then a.filter = a.filter or {}; a.filter.timed = v or nil; apply(); P.auraRefresh() end end)
    attachTip(timed.control, "Only timed auras", "Hide auras with no duration (permanent ones).")
    place(timed, 0, 0)
    blk.cells[#blk.cells + 1] = timed
    local list = {}
    for _, cls in ipairs(GU.AURA_CLASSES) do if cls.pol == "both" or cls.pol == pol then list[#list + 1] = cls end end
    local TRI = { { "never", "Never" }, { "any", "Any" }, { "only", "Only" } }
    for i, cls in ipairs(list) do
      local sw = Switch(blk, cls.label, 170, TRI,
        function() local a = AuraCfg(); return a and a.filter and a.filter.classes and a.filter.classes[cls.key] or "any" end,
        function(v) local a = AuraCfg(); if not a then return end
          a.filter = a.filter or {}; a.filter.classes = a.filter.classes or {}
          a.filter.classes[cls.key] = (v ~= "any") and v or nil
          apply(); P.auraRefresh() end)
      place(sw, ((i - 1) % 2 == 0) and 0 or 190, 41 * (1 + math.floor((i - 1) / 2)) + 20)
      blk.cells[#blk.cells + 1] = sw
    end
    blk.h = 41 * (1 + math.ceil(#list / 2)) + 20 - 10
    filterBlocks[pol] = blk
  end
  blk:Show()
  for _, c in ipairs(blk.cells) do c:refresh() end
  filterWin:SetHeight(54 + blk.h + 20)
end
local function openFilters()
  if not filterWin then
    filterWin = popupWindow(400, 300)
    filterWin.title = UI.newText(filterWin.content, FONT.sa, 14, COLOR.paper, "LEFT"); filterWin.title:SetPoint("TOPLEFT", 20, -20)
    filterWin:HookScript("OnShow", refreshFilters)
  end
  if filterWin:IsShown() then filterWin:Hide() else filterWin:openBeside(); refreshFilters() end
end

local function buildAuras(parent)
  local f, s = Section(parent, 553)
  local rows, w = {}, {}
  local function R() s.refresh() end
  P.auraRefresh = function() R(); refreshFilters() end
  local function selectGroup(i) auraSel[selected] = i; R(); refreshFilters(); if P.syncPreviews then P.syncPreviews() end end
  local function commit(i, text)
    local l = AuraList(); local a = l and l[i]; if not a then return end
    local v = (text or ""):match("^%s*(.-)%s*$")
    a.name = (v ~= "") and v or nil
    R()
  end
  local function getRow(i)
    if not rows[i] then rows[i] = listRow(f, 50, selectGroup, commit, { "Name", "What this group is called here. It changes nothing on screen." }) end
    return rows[i]
  end
  w.add = Button(f, "Add Group", 113, function()
    local l = AuraList(); if not l then return end
    local a = CopyTable(GU.AURA_DEFAULTS); a.kind = (selected == "target") and "debuffs" or "buffs"
    l[#l + 1] = a; apply(); selectGroup(#l)
  end)
  attachTip(w.add, "Add an aura group", "A new row of icons at the center of the frame. Move it with the offsets.")
  w.dup = Button(f, "Duplicate", 114, function()
    local l = AuraList(); local a, i = AuraCfg(); if not (l and a) then return end
    local c = CopyTable(a); c.y = (c.y or 0) - (c.size or 28) - 6
    table.insert(l, i + 1, c); apply(); selectGroup(i + 1)
  end)
  attachTip(w.dup, "Duplicate", "A copy of the group being edited, one row lower.")
  w.del = Button(f, "Delete", 113, function()
    local l = AuraList(); local a, i = AuraCfg(); if not (l and a) then return end
    UI.confirm(("Delete Group %d (%s)?"):format(i, a.name or GU.AURA_KIND_LABEL[a.kind] or "?"), function()
      table.remove(l, i); apply(); selectGroup(math.max(1, math.min(i, #l)))
    end, "Delete", "Delete aura group")
  end, true)

  w.enabled = Switch(f, "Status", 170, OFFON, aget("enabled", true), function(v) aset("enabled")(v); R() end)
  w.kind = Switch(f, "Aura Type", 170, { { "buffs", "Buffs" }, { "debuffs", "Debuffs" } }, aget("kind", "buffs"),
    function(v) aset("kind")(v); R(); refreshFilters() end)
  attachTip(w.kind.control, "Aura type", "Buffs or debuffs, narrowed by the Filters. Which auras count is decided by the game, so it matches Blizzard's own frames.")
  w.filters = Drop(f, "Filters", 170, function() return FilterSummary((AuraCfg())) end, nil, nil, nil, { onClick = openFilters })
  attachTip(w.filters.control, "Filters", "Which auras this group shows: only timed ones, and the classes the game can tell apart — Never, Any or Only for each.")
  w.shape = Drop(f, "Icon Shape", 170,
    function() local a = AuraCfg(); local k = a and a.shape; local hub = GloomsHub
      return (k and hub.SHAPES and hub.SHAPES[k] and hub.SHAPES[k].label) or "Square (none)" end,
    function()
      local o = { { value = "", label = "Square (none)" } }
      for _, k in ipairs(GloomsHub.SHAPE_ORDER or {}) do o[#o + 1] = { value = k, label = GloomsHub.SHAPES[k].label } end
      return o
    end,
    function() local a = AuraCfg(); return (a and a.shape) or "" end,
    function(v) local a = AuraCfg(); if a then a.shape = (v ~= "") and v or nil; apply() end end)
  attachTip(w.shape.control, "Icon shape", "The suite's silhouettes — the same catalog Gloom's Bars and Gloom's Auras draw with. The cooldown swipe follows the shape.")
  w.order = Switch(f, "Display Order", 360, { { "default", "Default" }, { "expiring", "Expiring First" }, { "expiringLast", "Expiring Last" } }, aget("sort", "default"), aset("sort"))
  attachTip(w.order.control, "Display order", "Default is the game's own order. Expiring First puts the aura with the least time left first; Expiring Last the most.")
  -- Grow Direction: two switches of 82, 6 apart, in one cell
  w.grow = cell(f, "Grow Direction", 170, function(c)
    local g = CreateFrame("Frame", nil, c); g:SetSize(170, 16)
    g.h = UI.gSwitch(g, { { "RIGHT", "Right" }, { "LEFT", "Left" } }, aget("growH", "RIGHT"), aset("growH"), { w = 82 }); g.h:SetPoint("TOPLEFT", 0, 0)
    g.v = UI.gSwitch(g, { { "UP", "Up" }, { "DOWN", "Down" } }, aget("growV", "UP"), aset("growV"), { w = 82 }); g.v:SetPoint("TOPLEFT", 88, 0)
    function g:refresh() self.h:refresh(); self.v:refresh() end
    function g:setEnabled(on) self.h:setEnabled(on); self.v:setEnabled(on) end
    return g
  end)
  attachTip(w.grow.control.h, "Grow", "New icons appear in this direction."); attachTip(w.grow.control.v, "Grow", "Extra rows stack this way.")
  w.swipe = Switch(f, "Cooldown Swipe", 170, OFFON, aget("swipe", true), aset("swipe"))
  attachTip(w.swipe.control, "Cooldown swipe", "A dark sweep across the icon as the aura runs down. Drawn by the game engine.")
  w.size = Dial(f, 170, { label = "Icon Size", min = 10, max = 96, step = 1, unit = "px", dragPx = 400, get = aget("size", 28), set = aset("size") })
  w.x = Dial(f, 170, { label = "Horizontal Offset", min = -800, max = 800, step = 1, unit = "px", dragPx = 1600, get = aget("x", 0), set = aset("x") })
  w.max = Dial(f, 170, { label = "Max Icons", min = 1, max = 40, step = 1, dragPx = 300, get = aget("max", 8), set = aset("max") })
  w.y = Dial(f, 170, { label = "Vertical Offset", min = -800, max = 800, step = 1, unit = "px", dragPx = 1600, get = aget("y", 0), set = aset("y") })
  w.perLine = Dial(f, 170, { label = "Icons Per Row", min = 1, max = 40, step = 1, dragPx = 300, get = aget("perLine", 8), set = aset("perLine") })
  attachTip(w.perLine.strip, "Icons per row", "The row wraps after this many; 1 makes a column.")
  w.spacing = Dial(f, 170, { label = "Icon Spacing", min = 0, max = 20, step = 1, unit = "px", dragPx = 200, get = aget("spacing", 3), set = aset("spacing") })
  w.durOn = Switch(f, "Countdown", 170, OFFON, aget("showDuration", true), function(v) aset("showDuration")(v); R() end)
  w.durSize = Dial(f, 170, { label = "Countdown Size", min = 6, max = 32, step = 1, unit = "px", dragPx = 200, get = aget("durationSize", 11), set = aset("durationSize") })
  w.stackOn = Switch(f, "Stack Count", 170, OFFON, aget("showStacks", true), function(v) aset("showStacks")(v); R() end)
  w.stackSize = Dial(f, 170, { label = "Stack Count Size", min = 6, max = 32, step = 1, unit = "px", dragPx = 200, get = aget("stackSize", 11), set = aset("stackSize") })
  w.layer = LayerRow(f, function() return (AuraCfg()) end,
    function(a) return GU:AuraOwnLayer(a) end,
    function(a) local fr = GU:Frame(selected); a.ownLayer = true; a.strata = a.strata or (fr and fr:GetFrameStrata()) or "MEDIUM"; a.level = a.level or 60 end,
    function(a) a.ownLayer = false end, 60, R)
  local labelled = { { w.enabled, "Status" }, { w.kind, "Aura Type" }, { w.filters, "Filters" }, { w.shape, "Icon Shape" }, { w.order, "Display Order" },
                     { w.grow, "Grow Direction" }, { w.swipe, "Cooldown Swipe" }, { w.size, "Icon Size" }, { w.x, "Horizontal Offset" },
                     { w.max, "Max Icons" }, { w.y, "Vertical Offset" }, { w.perLine, "Icons Per Row" }, { w.spacing, "Icon Spacing" },
                     { w.durOn, "Countdown" }, { w.durSize, "Countdown Size" }, { w.stackOn, "Stack Count" }, { w.stackSize, "Stack Count Size" } }
  local editor = {}
  for _, e in ipairs(labelled) do editor[#editor + 1] = e[1] end
  for _, e in ipairs({ w.layer.own, w.layer.strata, w.layer.level }) do editor[#editor + 1] = e end

  s.refresh = function()
    local l = AuraList(); if not l then return end
    local n = #l
    if (auraSel[selected] or 1) > n then auraSel[selected] = math.max(1, n) end
    local cur = auraSel[selected] or 1
    for i = 1, n do
      local r = getRow(i)
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
      r:set(i, ("Group %d"):format(i), l[i].name or GU.AURA_KIND_LABEL[l[i].kind] or "", i == cur, l[i].enabled == false)
      r:Show()
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    local by = math.max(0, n * 22 - 6) + 10
    w.add:ClearAllPoints(); w.add:SetPoint("TOPLEFT", 0, -by)
    w.dup:ClearAllPoints(); w.dup:SetPoint("TOPLEFT", 123, -by)
    w.del:ClearAllPoints(); w.del:SetPoint("TOPLEFT", 247, -by)
    w.dup:setEnabled(n > 0); w.del:setEnabled(n > 0)
    local ey = by + 16 + 30
    local a = l[cur]
    for _, e in ipairs(editor) do e:SetShown(a ~= nil) end
    if not a then setHeight(f, by + 16); return end
    for _, e in ipairs(labelled) do e[1]:setLabel(suffixed(e[2], "Group", cur)) end
    place(w.enabled, 0, ey); place(w.kind, 190, ey)
    place(w.filters, 0, ey + 41); place(w.shape, 190, ey + 41)
    place(w.order, 0, ey + 82)
    place(w.grow, 0, ey + 123); place(w.swipe, 190, ey + 123)
    place(w.size, 0, ey + 184); place(w.x, 190, ey + 184)
    place(w.max, 0, ey + 225); place(w.y, 190, ey + 225)
    place(w.perLine, 0, ey + 266); place(w.spacing, 190, ey + 266)
    place(w.durOn, 0, ey + 327); place(w.durSize, 190, ey + 327)
    place(w.stackOn, 0, ey + 368); place(w.stackSize, 190, ey + 368)
    place(w.layer.own, 0, ey + 429); place(w.layer.strata, 115, ey + 429); place(w.layer.level, 230, ey + 429)
    for _, e in ipairs(labelled) do e[1]:refresh() end
    w.layer:refresh()
    w.durSize:setEnabled(a.showDuration ~= false)
    w.stackSize:setEnabled(a.showStacks ~= false)
    setHeight(f, ey + 429 + 31)
  end
  return f
end

-- ===========================================================================
-- THE RING SECTIONS — Health · Power · Class Resource · Cast, one builder.
-- Faces from the mocks: BAR = Health / Cast ("gloomUnits, Health Bar Ring",
-- "Cast Bar"), ARC = Power / Class Resource. A rectangle bar has a width and a
-- height where a shaped one has a Size, so its first dial row is Width |
-- Horizontal Offset, then Height | Vertical Offset, then Rotation.
-- ===========================================================================
local OUTLINE = { { "off", "Off" }, { "thin", "Thin" }, { "medium", "Medium" }, { "thick", "Thick" } }
local FILL_LABEL = { up = "Bottom to Top", down = "Top to Bottom", right = "Left to Right", left = "Right to Left" }
local FILL_ORDER = { "up", "down", "right", "left" }
local ROW_LABEL = { right = "To the Right", left = "To the Left", up = "Upward", down = "Downward" }
local ROW_ORDER = { "right", "left", "up", "down" }

local function buildRing(parent, key, title, kind)
  local isHealth, isPower, isResource, isCast = kind == "health", kind == "power", kind == "resource", kind == "cast"
  local f, s = Section(parent, 600)
  local w = {}
  local function R() s.refresh() end
  local function rget(field, default) return function() local rc = RingCfg(key); return rc and orDefault(rc[field], default) end end
  local function rset(field) return function(v) local rc = RingCfg(key); if rc then rc[field] = v; apply() end end end
  local function rsetR(field) return function(v) rset(field)(v); R() end end
  local function bget(field, default) return function() local rc = RingCfg(key); return rc and rc.bar and orDefault(rc.bar[field], default) end end
  local function bset(field) return function(v) local rc = RingCfg(key); if rc and rc.bar then rc.bar[field] = v; apply() end end end
  local function pct(get0, set0, default) -- a 0..1 field as 0..100
    return function() return math.floor((get0() or default) * 100 + 0.5) end, function(v) set0(v / 100) end
  end
  local function isBar() local rc = RingCfg(key); return rc and rc.mode == "bar" end
  local function isRect() local rc = RingCfg(key); return rc and rc.bar and rc.bar.shape == "rect" end

  w.enabled = Switch(f, title .. " Display", 107, OFFON, rget("enabled", true), rsetR("enabled"))
  w.mode = Switch(f, "Display Type", 106, { { "arc", "Arc" }, { "bar", "Bar" } },
    function() return isBar() and "bar" or "arc" end, rsetR("mode"))
  w.shape = Drop(f, "Shape", 107,
    function()
      local k = bget("shape", "orb")()
      if k == "rect" then return "Rectangle" end
      local info = GloomsHub.BAR_SHAPES and GloomsHub.BAR_SHAPES[k]
      return info and info.label or tostring(k)
    end,
    function()
      local o = { { value = "rect", label = "Rectangle" } }
      for _, k in ipairs(GloomsHub.BAR_SHAPE_ORDER or {}) do o[#o + 1] = { value = k, label = GloomsHub.BAR_SHAPES[k].label } end
      return o
    end,
    bget("shape", "orb"),
    function(v) bset("shape")(v); R() end)
  -- geometry
  w.bsize = Dial(f, 170, { label = "Size", min = 8, max = 500, step = 1, unit = "px", dragPx = 900, get = bget("size", 120), set = bset("size") })
  w.asize = Dial(f, 170, { label = "Size", min = 40, max = 700, step = 1, unit = "px", dragPx = 1200, get = rget("size", 220), set = rset("size") })
  w.bwidth = Dial(f, 170, { label = "Width", min = 8, max = 800, step = 1, unit = "px", dragPx = 1400, get = bget("width", 200), set = bset("width") })
  w.bheight = Dial(f, 170, { label = "Height", min = 4, max = 800, step = 1, unit = "px", dragPx = 1400, get = bget("height", 24), set = bset("height") })
  -- one pair of offsets reading whichever mode is live (they are separate — the owner's ruling)
  local function offGet(field) return function() local rc = RingCfg(key); if not rc then return 0 end
    local t = (rc.mode == "bar" and rc.bar) and rc.bar or rc; return orDefault(t[field], 0) end end
  local function offSet(field) return function(v) local rc = RingCfg(key); if not rc then return end
    local t = (rc.mode == "bar" and rc.bar) and rc.bar or rc; t[field] = v; apply() end end
  w.dx = Dial(f, 170, { label = "Horizontal Offset", min = -300, max = 300, step = 1, unit = "px", dragPx = 900, get = offGet("dx"), set = offSet("dx") })
  w.dy = Dial(f, 170, { label = "Vertical Offset", min = -300, max = 300, step = 1, unit = "px", dragPx = 900, get = offGet("dy"), set = offSet("dy") })
  w.rot = Dial(f, 170, { label = "Rotation", min = 0, max = 359, step = 1, unit = "°", dragPx = 720, get = bget("rotation", 0), set = bset("rotation") })
  attachTip(w.rot.strip, "Rotation", "Counter-clockwise. The shape turns; the fill still runs along the screen axis you choose in Fill Direction.")
  w.thick = Dial(f, 170, { label = "Thickness", min = 2, max = 350, step = 1, unit = "px", dragPx = 900, get = rget("thickness", 22), set = rset("thickness") })
  w.span = Dial(f, 170, { label = "Arc Span", min = 10, max = 360, step = 1, unit = "°", dragPx = 720, get = rget("span", 180), set = rset("span") })
  w.start = Dial(f, 170, { label = "Start Angle", min = 0, max = 359, step = 1, unit = "°", dragPx = 720, get = rget("start", 180), set = rset("start") })
  attachTip(w.start.strip, "Start Angle", "0 is right, 90 top, 180 left, 270 bottom — where the FULL end sits.")
  if isResource then
    w.roundStart = Switch(f, "Rounded Segment Ends", 170, OFFON, rget("roundStart", false),
      function(v) local rc = RingCfg(key); if rc then rc.roundStart, rc.roundEnd = v, v; apply() end end)
    w.gap = Dial(f, 170, { label = "Gap Between Segments", min = 0, max = 30, step = 1, unit = "°", dragPx = 300, get = rget("gap", 4), set = rset("gap") })
    attachTip(w.gap.strip, "Gap between segments", "One segment per point; the count follows your class and spec.")
    w.rowGap = Dial(f, 170, { label = "Gap Between Segments", min = 0, max = 60, step = 1, unit = "px", dragPx = 400, get = rget("rowGap", 4), set = rset("rowGap") })
  else
    w.roundStart = Switch(f, "Rounded Fill: Start", 170, OFFON, rget("roundStart", false), rset("roundStart"))
    w.roundEnd = Switch(f, "Rounded Fill: End", 170, OFFON, rget("roundEnd", false), rset("roundEnd"))
    attachTip(w.roundEnd.control, "Round the moving end", "A round cap that rides the leading edge as the value moves.")
  end
  -- outline
  w.outline = Switch(f, "Bar Outline", 170, OUTLINE,
    function() local rc = RingCfg(key); if not (rc and rc.outline) then return "off" end return rc.outlineWidth or "medium" end,
    function(v) local rc = RingCfg(key); if not rc then return end
      rc.outline = v ~= "off"; if v ~= "off" then rc.outlineWidth = v end; apply(); R() end)
  attachTip(w.outline.control, "Outline", "An outline around the display's shape — a bar's silhouette, or the arc's whole track including its ends.")
  w.outlineColor = Color(f, "Outline Color", 170, { get = rget("outlineColor"), set = rset("outlineColor") })
  local og, os = pct(rget("outlineAlpha", 1), rset("outlineAlpha"), 1)
  w.outlineAlpha = Dial(f, 170, { label = "Outline Opacity", min = 0, max = 100, step = 1, unit = "%", dragPx = 400, get = og, set = os })
  -- the absorb shield: the bar's overlay, the arc's wash (FINDINGS §19 — presence only)
  if isHealth then
    w.absorb = Switch(f, "Absorb Shield Indicator", 170, OFFON,
      function() local rc = RingCfg(key); if not rc then return false end
        if isBar() then return rc.bar and rc.bar.absorb ~= false end; return rc.shieldTint and true or false end,
      function(v) local rc = RingCfg(key); if not rc then return end
        if isBar() then if rc.bar then rc.bar.absorb = v end else rc.shieldTint = v end; apply(); R() end)
    attachTip(w.absorb.control, "Absorb shield", "Bar: a striped overlay the size of the unit's absorb, laid from the full end back over the fill. Arc: a wash over the filled part while a shield is up — the game decides when; its size is not something an addon may read on 12.1.")
    w.absorbColor = Color(f, "Absorb Shield Color", 170, {
      get = function() local rc = RingCfg(key); if not rc then return nil end; if isBar() then return rc.bar and rc.bar.absorbColor end; return rc.shieldColor end,
      set = function(v) local rc = RingCfg(key); if not rc then return end; if isBar() then if rc.bar then rc.bar.absorbColor = v end else rc.shieldColor = v end; apply() end })
    w.absorbAlpha = Dial(f, 170, { label = "Absorb Shield Opacity", min = 0, max = 100, step = 1, unit = "%", dragPx = 400,
      get = function() local rc = RingCfg(key); if not rc then return 60 end
        local v = isBar() and (rc.bar and rc.bar.absorbAlpha or 0.6) or (rc.shieldAlpha or 0.8); return math.floor(v * 100 + 0.5) end,
      set = function(v) local rc = RingCfg(key); if not rc then return end
        if isBar() then if rc.bar then rc.bar.absorbAlpha = v / 100 end else rc.shieldAlpha = v / 100 end; apply() end })
  end
  -- fill
  w.colorType = Switch(f, "Fill Color Type", 170, { { "solid", "Solid" }, { "gradient", "Gradient" } },
    function() local rc = RingCfg(key); return (rc and rc.colorMode) or "solid" end, rsetR("colorMode"))
  w.fillDir = Drop(f, "Fill Direction", 170,
    function()
      if isBar() then
        if isResource then return ROW_LABEL[rget("rowDir", "right")()] or "To the Right" end
        return FILL_LABEL[bget("fillDir", "up")()] or "Bottom to Top"
      end
      local rc = RingCfg(key); return (rc and rc.clockwise) and "Clockwise" or "Counter-Clockwise"
    end,
    function()
      local o = {}
      if isBar() then
        if isResource then for _, k in ipairs(ROW_ORDER) do o[#o + 1] = { value = k, label = ROW_LABEL[k] } end
        else for _, k in ipairs(FILL_ORDER) do o[#o + 1] = { value = k, label = FILL_LABEL[k] } end end
        return o
      end
      return { { value = "cw", label = "Clockwise" }, { value = "ccw", label = "Counter-Clockwise" } }
    end,
    function()
      if isBar() then return isResource and rget("rowDir", "right")() or bget("fillDir", "up")() end
      local rc = RingCfg(key); return (rc and rc.clockwise) and "cw" or "ccw"
    end,
    function(v)
      if isBar() then if isResource then rset("rowDir")(v) else bset("fillDir")(v) end
      else rset("clockwise")(v == "cw") end
      R()
    end)
  -- the fill color and its SOURCE: the unit's class, its power type, the class resource
  local srcField, source
  if isHealth then
    srcField = "classColor"
    source = { value = "class", label = "Use Class Color", word = "Class", color = function()
      local ok, r, g, b = GU.UnitColor(selected)
      if ok and not (issecretvalue and issecretvalue(r)) then return r, g, b end
    end }
  elseif isPower then
    srcField = "powerColor"
    source = { value = "power", label = "Use Power Color", word = "Power", color = function()
      local c = GU.PowerTypeColor(selected); if c then return c[1], c[2], c[3] end
    end }
  elseif isResource then
    srcField = "resourceColor"
    source = { value = "resource", label = "Use Resource Color", word = "Resource", color = function() return GU:ResourceColor() end }
  end
  local fillOpts = { required = true,
    get = function()
      local rc = RingCfg(key); if not rc then return nil end
      if srcField and rc[srcField] and rc.colorMode ~= "gradient" then
        local r, g, b = source.color(); if r then return { r, g, b } end
      end
      return rc.color
    end,
    set = function(v) local rc = RingCfg(key); if not rc then return end; if srcField then rc[srcField] = false end; rc.color = v; apply() end }
  if source then
    fillOpts.sources = { source }
    fillOpts.getSource = function() local rc = RingCfg(key); return (rc and rc[srcField]) and source.value or nil end
    fillOpts.setSource = function() local rc = RingCfg(key); if rc then rc[srcField] = true; apply() end end
  end
  w.color = Color(f, "Fill Color", 85, fillOpts)
  w.gradAngle = Dial(f, 150, { label = "Gradient Angle", min = 0, max = 359, step = 1, unit = "°", dragPx = 720, get = rget("gradientAngle", 0), set = rset("gradientAngle") })
  attachTip(w.gradAngle.strip, "Gradient angle", "0 runs left to right, 90 bottom to top. A bar snaps it to the nearest of the four.")
  w.color2 = Color(f, "2nd Fill Color", 85, { required = true, get = rget("color2"), set = rset("color2") })
  -- track
  w.trackColor = Color(f, "Track Color", 170, { get = rget("trackColor"), set = rset("trackColor") })
  local tg, ts = pct(rget("trackAlpha", 0.12), rset("trackAlpha"), 0.12)
  w.trackAlpha = Dial(f, 170, { label = "Track Opacity", min = 0, max = 100, step = 1, unit = "%", dragPx = 400, get = tg, set = ts })
  -- drain shift (health, power)
  if isHealth or isPower then
    w.shift = Switch(f, "Drain Color Shift", 107, OFFON, rget("shift", false), rsetR("shift"))
    attachTip(w.shift.control, "Drain color shift", "On top of the fill color: the 50% color is fully in by half, and the 0% color fades in from there toward empty. Blended by the game engine, so it works on secret values.")
    w.mid = Color(f, "50% Color", 106, { required = true, get = rget("midColor"), set = rset("midColor") })
    w.low = Color(f, "0% Color", 107, { required = true, get = rget("lowColor"), set = rset("lowColor") })
  end
  -- the resource's color change at a point count
  if isResource then
    w.brkOn = Switch(f, "Color Change", 92, OFFON, rget("breakEnabled", false), rsetR("breakEnabled"))
    attachTip(w.brkOn.control, "Color change", "Every segment turns the color beside it once you have at least this many points.")
    w.brkAt = Dial(f, 136, { label = "Color Change at Point Count", min = 1, max = 7, step = 1, dragPx = 200, get = rget("breakAt", 5), set = rset("breakAt") })
    w.brkColor = Color(f, "Change Color To", 92, { required = true, get = rget("breakColor"), set = rset("breakColor") })
  end
  -- the cast: interrupt state and channels
  if isCast then
    w.kick = Switch(f, "Color by Interrupt State", 170, OFFON, rget("kickAware", true), rsetR("kickAware"))
    attachTip(w.kick.control, "Color by interrupt state", "Target only. The bar takes one of the colors below by whether the cast can be interrupted and whether your interrupt is ready. Solid colors — a gradient is set aside while this is on.")
    w.drains = Switch(f, "Channels Drain", 170, OFFON, rget("channelDrains", true), rset("channelDrains"))
    attachTip(w.drains.control, "Channels drain", "A channeled spell empties the bar as it runs down; a cast fills it. Off: both fill.")
    -- the five interrupt colors: a 15 disc, 10 on the words; the last two are
    -- OPTIONAL — "(Remove)" turns that feature off, clicking the disc brings it back.
    local block = CreateFrame("Frame", nil, f); block:SetSize(360, 99)
    w.kickRows = block
    local kr = {}
    local function kickRow(i, text, get, set, optional)
      local r = CreateFrame("Frame", nil, block); r:SetSize(360, 15); r:SetPoint("TOPLEFT", 0, -(i - 1) * 21)
      r.dot = UI.gColor(r, { dot = true, required = true, get = get, set = set, title = text })
      r.dot:SetPoint("LEFT", 0, 0)
      r.text = UI.newText(r, FONT.sa, 10, COLOR.paper, "LEFT"); r.text:SetPoint("LEFT", 25, 0); r.text:SetText(text)
      if optional then
        r.remove = CreateFrame("Button", nil, r); r.remove:SetHeight(14)
        r.remove.t = UI.newText(r.remove, FONT.sa, 10, LIME, "LEFT"); r.remove.t:SetPoint("LEFT", 0, 0); r.remove.t:SetText("(Remove)")
        r.remove:SetWidth(math.ceil(r.remove.t:GetStringWidth())); r.remove:SetPoint("LEFT", r.text, "RIGHT", 4, 0)
        r.remove:SetScript("OnClick", function() set(nil); r:refresh() end)
        r.remove:SetScript("OnEnter", function(self) self.t:SetTextColor(1, 1, 1) end)
        r.remove:SetScript("OnLeave", function(self) self.t:SetTextColor(LIME.r, LIME.g, LIME.b) end)
      end
      function r:refresh() self.dot:refresh(); if self.remove then self.remove:SetShown(get() ~= nil) end end
      function r:setEnabled(on) self.dot:setEnabled(on); self.text:SetAlpha(on and 1 or DIM); if self.remove then self.remove:SetAlpha(on and 1 or DIM); self.remove:SetEnabled(on) end end
      kr[#kr + 1] = r
    end
    kickRow(1, "Interruptible and your interrupt is ready (bar default color)", rget("color"), function(v) rset("color")(v); R() end)
    kickRow(2, "Interruptible, but your interrupt is on cooldown", rget("kickCDColor"), rset("kickCDColor"))
    kickRow(3, "Can't be interrupted", rget("lockedColor"), rset("lockedColor"))
    kickRow(4, "Interrupt available before the cast ends",
      function() local rc = RingCfg(key); return rc and rc.midCastEnabled ~= false and rc.midCastColor or nil end,
      function(v) local rc = RingCfg(key); if not rc then return end
        if v then rc.midCastEnabled, rc.midCastColor = true, v else rc.midCastEnabled = false end; apply() end, true)
    kickRow(5, "Tick mark on castbar where interrupt will be available",
      function() local rc = RingCfg(key); return rc and rc.kickTick ~= false and rc.kickTickColor or nil end,
      function(v) local rc = RingCfg(key); if not rc then return end
        if v then rc.kickTick, rc.kickTickColor = true, v else rc.kickTick = false end; apply() end, true)
    function block:refresh() for _, r in ipairs(kr) do r:refresh() end end
    function block:setEnabled(on) for _, r in ipairs(kr) do r:setEnabled(on) end end
  end
  -- the layer
  w.layer = LayerRow(f, function() return RingCfg(key) end,
    function(rc) return rc.level ~= nil end,
    function(rc) local fr = GU:Frame(selected); local h = fr and fr.rings and fr.rings[key] and fr.rings[key].holder
      rc.strata = h and h:GetFrameStrata() or "MEDIUM"; rc.level = h and (h:GetFrameLevel() + 1) or 11 end,
    function(rc) rc.strata, rc.level = nil, nil end, 11, R)

  local all = {}
  for _, v in pairs(w) do if type(v) == "table" and v.Hide and v ~= w.layer then all[#all + 1] = v end end
  for _, v in ipairs({ w.layer.own, w.layer.strata, w.layer.level }) do all[#all + 1] = v end

  -- THE ROWS, per face
  local function rows()
    local bar, rect = isBar(), isRect()
    local t = { row({ w.enabled, 0 }, { w.mode, 127 }, { w.shape, 253 }) }
    if bar then
      if rect then
        t[#t + 1] = row({ w.bwidth, 0 }, { w.dx, 190 })
        t[#t + 1] = row({ w.bheight, 0 }, { w.dy, 190 })
        t[#t + 1] = row({ w.rot, 0 })
      else
        t[#t + 1] = row({ w.bsize, 0 }, { w.dx, 190 })
        t[#t + 1] = row({ w.rot, 0 }, { w.dy, 190 })
      end
    else
      t[#t + 1] = row({ w.asize, 0 }, { w.dx, 190 })
      t[#t + 1] = row({ w.thick, 0 }, { w.dy, 190 })
      t[#t + 1] = row({ w.span, 0 }, { w.start, 190 })
    end
    t[#t + 1] = GAP
    -- rounding: the arc face (Power / Resource mocks), and the Cast mock's bar face
    if isResource then
      t[#t + 1] = row({ w.roundStart, 0 }, { bar and w.rowGap or w.gap, 190 }); t[#t + 1] = GAP
    elseif not bar or isCast then
      t[#t + 1] = row({ w.roundStart, 0 }, { w.roundEnd, 190 }); t[#t + 1] = GAP
    end
    t[#t + 1] = row({ w.outline, 0 }, { w.outlineColor, 190 })
    t[#t + 1] = row({ w.outlineAlpha, 0 })
    t[#t + 1] = GAP
    if isHealth then
      t[#t + 1] = row({ w.absorb, 0 }, { w.absorbColor, 190 })
      t[#t + 1] = row({ w.absorbAlpha, 0 })
      t[#t + 1] = GAP
    end
    t[#t + 1] = row({ w.colorType, 0 }, { w.fillDir, 190 })
    t[#t + 1] = row({ w.color, 0 }, { w.gradAngle, 105 }, { w.color2, 275 })
    -- the track: in the fill's block on Health (the drain shift its own block
    -- under it); a block of its own on Power, Resource and Cast, with the
    -- drain shift / color change / interrupt rows under it (the mocks)
    if not isHealth then t[#t + 1] = GAP end
    t[#t + 1] = row({ w.trackColor, 0 }, { w.trackAlpha, 190 })
    if isHealth then t[#t + 1] = GAP end
    if isCast then
      t[#t + 1] = row({ w.kick, 0 }, { w.drains, 190 })
      t[#t + 1] = { cells = { { w.kickRows, 0 } }, h = 99 }
    end
    if isHealth or isPower then t[#t + 1] = row({ w.shift, 0 }, { w.mid, 127 }, { w.low, 253 })
    elseif isResource then t[#t + 1] = row({ w.brkOn, 0 }, { w.brkAt, 112 }, { w.brkColor, 268 }) end
    t[#t + 1] = GAP
    t[#t + 1] = w.layer:row()
    return t
  end

  s.refresh = function()
    local rc = RingCfg(key); if not rc then return end
    local h = flow(all, rows())
    for _, v in ipairs(all) do if v:IsShown() and v.refresh then v:refresh() end end
    w.layer:refresh()
    -- what another setting disables (30%, never hidden)
    local bar = rc.mode == "bar"
    w.shape:setEnabled(bar)
    if w.roundEnd then w.roundStart:setEnabled(not bar); w.roundEnd:setEnabled(not bar) end
    if isResource then w.roundStart:setEnabled(not bar) end
    local outlined = rc.outline and true or false
    w.outlineColor:setEnabled(outlined); w.outlineAlpha:setEnabled(outlined)
    if w.absorb then
      local on = bar and (rc.bar and rc.bar.absorb ~= false) or (not bar and rc.shieldTint)
      w.absorbColor:setEnabled(on and true or false); w.absorbAlpha:setEnabled(on and true or false)
    end
    local grad = rc.colorMode == "gradient"
    w.gradAngle:setEnabled(grad); w.color2:setEnabled(grad)
    if w.shift then local on = rc.shift and true or false; w.mid:setEnabled(on); w.low:setEnabled(on) end
    if w.brkOn then local on = rc.breakEnabled and true or false; w.brkAt:setEnabled(on); w.brkColor:setEnabled(on) end
    if w.kick then w.kickRows:setEnabled(rc.kickAware and true or false) end
    setHeight(f, h)
  end
  return f
end

-- ===========================================================================
-- PREVIEWS — while the windows are open the selected unit can be dragged (the
-- green outline); its cast ring runs a fake cast while the Cast section is on
-- screen, and the selected aura group shows sample icons while Auras is.
-- ===========================================================================
local castFrame, auraFrame
function P.syncPreviews()
  local open = P.windowsOpen
  for _, u in ipairs(GU.UNITS) do
    GU:SetCastPreview(u, open and u == selected and castFrame and castFrame:IsVisible() or false)
    GU:SetAuraPreview(u, (open and u == selected and auraFrame and auraFrame:IsVisible()) and (auraSel[selected] or 1) or nil)
  end
end

-- ===========================================================================
-- Mount the Unit Frames windows (CONTRACTS §2, the two-window block).
-- ===========================================================================
local function collision() return false, "A profile with that name already exists." end
local PROFILE_API = {
  noun   = "profile",
  names  = function() return GU:ProfileNames() end,
  active = function() return GU:ActiveProfileName() or "?" end,
  switch = function(v) GU:SetActiveProfile(v) end,
  users  = function(name) return GU:ProfileUsers(name) end,
  create = function(name) if not GU:CreateProfile(name) then return collision() end; GU:SetActiveProfile(name); return true end,
  copy   = function(name) if not GU:CopyProfile(GU:ActiveProfileName(), name) then return collision() end; GU:SetActiveProfile(name); return true end,
  rename = function(name) if not GU:RenameProfile(GU:ActiveProfileName(), name) then return collision() end; return true end,
  delete = function()
    local gone = GU:ActiveProfileName()
    local ok, landedOn = GU:DeleteProfile(gone)
    if not ok then return false, "Can't delete the last profile." end
    print(("|cff936bffGloom's Unit Frames:|r deleted profile |cffffffff%s|r — this character is now on |cffffffff%s|r."):format(gone, tostring(landedOn)))
    return true
  end,
  onChange = function() P.refreshAll() end,
  tips = {
    dropdown = "The active profile for this character. Each character remembers its own; the profile library is shared account-wide.",
    new      = "Creates a profile with the factory rings, texts and aura groups, and switches to it. To start from THIS look instead, use Copy.",
    copy     = "Duplicates this profile — both units, everything — and switches to the copy.",
    rename   = "Renames this profile. Characters using it follow the new name.",
    delete   = "Deletes this profile (you'll be asked to confirm). Characters using it fall back to another profile. The last profile can't be deleted.",
  },
}

local function never() local c = Cfg(); return c and c.showCondition == "never" end

GloomsHub:RegisterTab{
  id       = "unitframes",
  title    = "Unit Frames",
  order    = 30,
  wordmark = "UNITS",
  product  = "GloomUnitFrames",
  windows  = true,
  profile  = PROFILE_API,
  selector = { build = buildSelector, h = 105 },
  tab      = { w = 360, build = buildTab },
  sections = {
    { id = "global",   title = function() return ("Global %s Settings"):format(UNIT_LABEL[selected] or "") end, build = buildGlobal },
    { id = "texts",    title = "Texts",                     build = buildTexts, dim = never },
    { id = "auras",    title = "Auras (Buffs & Debuffs)",   dim = never,
      build = function(p) auraFrame = buildAuras(p); return auraFrame end },
    { id = "health",   title = "Health Bar/Ring",           build = function(p) return buildRing(p, "health", "Health", "health") end, dim = never },
    { id = "power",    title = "Power Bar/Ring",            build = function(p) return buildRing(p, "power", "Power", "power") end, dim = never },
    { id = "resource", title = "Class Resource Bar/Ring",   build = function(p) return buildRing(p, "resource", "Resource", "resource") end, dim = never,
      hidden = function() local c = Cfg(); return not (c and c.rings and c.rings.resource) end },
    { id = "cast",     title = "Cast Bar/Ring",             dim = never,
      build = function(p) castFrame = buildRing(p, "cast", "Cast Bar", "cast"); return castFrame end },
  },
  onOpen   = function()
    P.windowsOpen = true
    GU:SetEditing(selected)
    for _, s in ipairs(P.secs) do if s.refresh then s.refresh() end end
    P.syncPreviews()
  end,
  onClose  = function()
    P.windowsOpen = false
    GU:SetEditing(nil)
    if codesWin then codesWin:Hide() end
    if filterWin then filterWin:Hide() end
    P.syncPreviews()
  end,
  refresh  = function() for _, s in ipairs(P.secs) do if s.refresh then s.refresh() end end end,
}

GU:OnChange(function(what, which)
  if what == "profile" then if P.windowsOpen then P.refreshAll() end; return end
  if which ~= selected then return end
  if what == "position" and P.globalDials then for _, d in ipairs(P.globalDials) do d:refresh() end end
end)
