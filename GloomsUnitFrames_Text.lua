-- GloomsUnitFrames_Text.lua — the TEXT PIECES: any number of free-text
-- labels per unit, each a template of words and [shortcodes], each with its
-- own font, size, colour, position and layer.
--
-- ★ HOW A TEMPLATE RENDERS ON 12.1 (Hub FINDINGS §18, and EUI's tags)
-- Nearly every value here is SECRET for the target in combat on a restricted
-- map, and health is secret for EVERY unit everywhere. Lua may never look at
-- a secret, but `FontString:SetFormattedText(fmt, ...)` takes secrets as its
-- ARGUMENTS and the engine formats them. So a template is compiled ONCE into
-- a plain format string ("%s · %d%%") plus one reader function per shortcode,
-- and every refresh is a single SetFormattedText call with the readers'
-- results — whether they are secret or not. Abbreviation ("845K") goes
-- through Blizzard's `AbbreviateNumbers`, which runs engine-side and accepts
-- a secret (that is how EllesmereUI shows 845K). What a reader may NOT do is
-- decide anything from a secret: every `if` below first checks the value is
-- plain, and falls back to showing it raw or showing nothing.
--
-- Shortcodes: [code] or [code:style]. The list the tab prints is GU.TEXT_HELP.

local GU = _G.GloomsUnitFrames
local issecretvalue = _G.issecretvalue
local function plain(v) return not (issecretvalue and issecretvalue(v)) end

local function utf8sub(s, n)
    if string.utf8sub then return string.utf8sub(s, 1, n) end
    return s:sub(1, n)
end

------------------------------------------------------------------------
-- Defaults for one text piece
------------------------------------------------------------------------
GU.TEXT_DEFAULTS = {
    enabled    = true,
    template   = "[hp:pct]",
    font       = nil,          -- an LSM font NAME; nil = the unit's default font (cfg.font), else Khand
    size       = 22,
    outline    = "none",       -- "none" | "thin" | "thick"
    shadow     = true,
    color      = { 1, 1, 1 },
    classColor = false,        -- the unit's class / reaction colour instead
    x = 0, y = 0,
    justify    = "CENTER",     -- "LEFT" | "CENTER" | "RIGHT" — also the anchor side
    maxWidth   = 0,            -- >0: clip with … past this width
    -- LAYER (the redesign's Layer Override plate, 2026-09-21): off = the unit's
    -- strata, level 70 above the unit frame (rings use 1–64); on = `strata`
    -- (nil = the unit's) and `level`, this piece's own.
    ownLayer   = nil,          -- nil on an old piece: on iff its level was changed from 70
    strata     = nil,
    level      = 70,
}
function GU:TextOwnLayer(tc)
    if tc.ownLayer ~= nil then return tc.ownLayer end
    return tc.level ~= nil and tc.level ~= 70
end

------------------------------------------------------------------------
-- Number formatting. AbbreviateNumbers(v[, cfg]) is Blizzard's, engine-side,
-- secret-safe. Its default config is "845K"; this one adds a decimal.
------------------------------------------------------------------------
local ABBREV_1 = { breakpointData = {
    { breakpoint = 1e9, abbreviation = "B", significandDivisor = 1e8, fractionDivisor = 10, abbreviationIsGlobal = false },
    { breakpoint = 1e6, abbreviation = "M", significandDivisor = 1e5, fractionDivisor = 10, abbreviationIsGlobal = false },
    { breakpoint = 1e3, abbreviation = "K", significandDivisor = 1e2, fractionDivisor = 10, abbreviationIsGlobal = false },
} }

-- style: "" → 845K · "1" → 845.2K · "full" → 845,123 (digits only when secret)
local function FormatAmount(v, style, blankZero)
    v = v or 0
    if blankZero and plain(v) and v == 0 then return "" end
    if style == "full" then
        if plain(v) then return BreakUpLargeNumbers(v) end
        return v
    end
    if style == "1" then return AbbreviateNumbers(v, ABBREV_1) end
    return AbbreviateNumbers(v)
end

local function Icon(path) return "|T" .. path .. ":0|t" end
local ICON_COMBAT  = "|TInterface\\CharacterFrame\\UI-StateIcon:0:0:0:0:64:64:32:64:0:32|t"
local ICON_RESTING = "|TInterface\\CharacterFrame\\UI-StateIcon:0:0:0:0:64:64:0:32:0:32|t"
local ICON_LEADER  = Icon("Interface\\GroupFrame\\UI-Group-LeaderIcon")
local ICON_LOCKED  = Icon("Interface\\RaidFrame\\ReadyCheck-NotReady")

local CLASSIFICATION = {
    elite = { "Elite", "+" }, rareelite = { "Rare Elite", "R+" }, rare = { "Rare", "R" }, worldboss = { "Boss", "B" },
}

------------------------------------------------------------------------
-- The shortcodes. Each entry: group (which events refresh it) and make(style)
-- → spec, reader. `spec` is the piece of format string the code contributes
-- and `reader(unit)` returns exactly as many values as `spec` consumes.
-- Readers never return nil.
------------------------------------------------------------------------
local TAGS = {}

local function amountTag(group, read, blankZero)
    return { group = group, make = function(style)
        return "%s", function(unit) return FormatAmount(read(unit), style, blankZero) end
    end }
end
local function pctTag(group, read)
    return { group = group, make = function(style)
        local spec = (style == "1") and "%.1f" or "%d"
        return spec, function(unit) return read(unit) or 0 end
    end }
end
local function flagTag(group, read, icon)
    return { group = group, make = function()
        return "%s", function(unit)
            local on = read(unit)
            if plain(on) and on then return icon end
            return ""
        end
    end }
end

TAGS.name = { group = "identity", make = function(style)
    local n = tonumber(style)
    return "%s", function(unit)
        local name = UnitName(unit) or ""
        if n and plain(name) then return utf8sub(name, n) end
        return name
    end
end }

-- [guild] — the unit's guild, blank without one; [title] — the name as the
-- game shows it with the unit's title ("Thrall the Warchief"), the plain name
-- without one (2026-09-30, the owner). Same shape as [name]: passed through,
-- never compared.
TAGS.guild = { group = "identity", make = function()
    return "%s", function(unit) return (GetGuildInfo(unit)) or "" end
end }
TAGS.title = { group = "identity", make = function()
    return "%s", function(unit) return UnitPVPName(unit) or UnitName(unit) or "" end
end }

TAGS.level = { group = "identity", make = function()
    return "%s", function(unit)
        local l = UnitEffectiveLevel(unit)
        if l == nil then return "" end
        if plain(l) and l <= 0 then return "??" end
        return l
    end
end }

TAGS.class = { group = "identity", make = function()
    return "%s", function(unit) return (UnitClass(unit)) or "" end
end }
TAGS.race = { group = "identity", make = function()
    return "%s", function(unit) return (UnitRace(unit)) or "" end
end }
TAGS.type = { group = "identity", make = function()
    return "%s", function(unit) return UnitCreatureType(unit) or "" end
end }
TAGS.elite = { group = "identity", make = function(style)
    local i = (style == "short") and 2 or 1
    return "%s", function(unit)
        local c = UnitClassification(unit)
        if not plain(c) then return "" end
        local e = c and CLASSIFICATION[c]
        return e and e[i] or ""
    end
end }

TAGS.hp     = amountTag("health", function(u) return UnitHealth(u) end)
TAGS.hpmax  = amountTag("health", function(u) return UnitHealthMax(u) end)
TAGS.absorb = amountTag("health", function(u) return UnitGetTotalAbsorbs(u) end, true)
TAGS.heals  = amountTag("health", function(u) return UnitGetIncomingHeals(u) end, true)
-- [hp:pct] / [hp:pct1] are routed here by Compile (the ":pct" style on hp).
TAGS.hppct  = pctTag("health", function(u) return UnitHealthPercent(u, true, CurveConstants.ScaleTo100) end)

local function powerType(u)
    local t = UnitPowerType(u)
    if plain(t) and t then return t end
    return nil
end
TAGS.power    = amountTag("power", function(u) return UnitPower(u, powerType(u)) end)
TAGS.powermax = amountTag("power", function(u) return UnitPowerMax(u, powerType(u)) end)
TAGS.powerpct = pctTag("power", function(u)
    local ok, v = pcall(UnitPowerPercent, u, powerType(u) or 0, true, CurveConstants.ScaleTo100)
    return ok and v or 0
end)
TAGS.powertype = { group = "power", make = function()
    return "%s", function(unit)
        local _, token = UnitPowerType(unit)
        if plain(token) and token then return _G[token] or token end
        return ""
    end
end }

-- The player's class resource (soul shards, combo points…): the engine knows
-- which power that is right now.
TAGS.shards = { group = "power", make = function(style)
    if style == "max" then
        return "%d / %d", function()
            local pType, _, max = GU:ClassResource()
            if not pType then return 0, 0 end
            return UnitPower("player", pType) or 0, max
        end
    end
    return "%d", function()
        local pType = GU:ClassResource()
        if not pType then return 0 end
        return UnitPower("player", pType) or 0
    end
end }

TAGS.cast = { group = "cast", make = function()
    return "%s", function(unit)
        local st = GU:CastInfo(unit)
        return st and st.name or ""
    end
end }
-- Seconds left. A string, so it can be BLANK when nothing is cast: the
-- player's times are plain and format in Lua; a target's may be a secret
-- duration, which is handed over raw.
TAGS.casttime = { group = "cast", make = function(style)
    local total = style == "total"
    return "%s", function(unit)
        local st = GU:CastInfo(unit)
        if not st then return "" end
        if st.plain then
            local now = GetTime() * 1000
            local rem = math.max(0, st.endMS - now) / 1000
            if total then return ("%.1f / %.1f"):format(rem, (st.endMS - st.startMS) / 1000) end
            return ("%.1f"):format(rem)
        elseif st.duration then
            local ok, rem = pcall(function() return st.duration:GetRemainingDuration() end)
            if not ok or rem == nil then return "" end
            if plain(rem) then
                if total then return ("%.1f / %.1f"):format(rem, st.total or 0) end
                return ("%.1f"):format(rem)
            end
            return rem
        end
        return ""
    end
end }
TAGS.kick = { group = "cast", make = function()
    return "%s", function(unit)
        local st = GU:CastInfo(unit)
        if st and plain(st.locked) and st.locked then return ICON_LOCKED end
        return ""
    end
end }

TAGS.status = { group = "flags", make = function()
    return "%s", function(unit)
        local con = UnitIsConnected(unit)
        if plain(con) and con == false then return "OFFLINE" end
        local dead = UnitIsDead(unit)
        if plain(dead) and dead then return "DEAD" end
        local ghost = UnitIsGhost(unit)
        if plain(ghost) and ghost then return "GHOST" end
        local afk = UnitIsAFK(unit)
        if plain(afk) and afk then return "AFK" end
        local dnd = UnitIsDND(unit)
        if plain(dnd) and dnd then return "DND" end
        return ""
    end
end }
TAGS.combat  = flagTag("flags", function(u) return UnitAffectingCombat(u) end, ICON_COMBAT)
TAGS.resting = flagTag("flags", function(u) return u == "player" and IsResting() end, ICON_RESTING)
TAGS.leader  = flagTag("flags", function(u) return UnitIsGroupLeader(u) end, ICON_LEADER)
TAGS.pvp = { group = "flags", make = function()
    return "%s", function(unit)
        local on = UnitIsPVP(unit)
        if not (plain(on) and on) then return "" end
        local faction = UnitFactionGroup(unit)
        if not plain(faction) then return "" end
        if faction == "Horde" then return Icon("Interface\\PVPFrame\\PVP-Currency-Horde") end
        if faction == "Alliance" then return Icon("Interface\\PVPFrame\\PVP-Currency-Alliance") end
        return Icon("Interface\\PVPFrame\\PVP-Currency-Horde")
    end
end }
TAGS.mark = { group = "flags", make = function()
    return "%s", function(unit)
        local i = GetRaidTargetIndex(unit)
        if plain(i) and i and i >= 1 and i <= 8 then
            return Icon("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)
        end
        return ""
    end
end }
TAGS.threat = { group = "flags", make = function()
    return "%d", function(unit)
        if unit == "player" then return 0 end
        local _, _, pct = UnitDetailedThreatSituation("player", unit)
        return pct or 0
    end
end }

-- What the tab prints. Kept next to the table so it cannot drift from it.
GU.TEXT_HELP = {
    { "[name]", "name — [name:8] first 8 letters" },
    { "[guild]", "guild name, blank without one" },
    { "[title]", "name with its title — Thrall the Warchief" },
    { "[level]", "level, ?? for a skull" },
    { "[class] [race] [type]", "Warlock · Orc · Demon" },
    { "[elite]", "Elite / Rare / Boss — [elite:short] for + R B" },
    { "[hp] [hpmax]", "health as 845K — [hp:1] 845.2K · [hp:full] all the digits" },
    { "[hp:pct]", "health percent — [hp:pct1] with a decimal" },
    { "[absorb] [heals]", "shield · incoming heals, blank at zero (same styles as hp)" },
    { "[power] [powermax] [power:pct]", "mana, rage, energy… (same styles)" },
    { "[powertype]", "Mana, Energy…" },
    { "[shards]", "class resource count — [shards:max] as 3 / 5" },
    { "[cast] [casttime]", "spell name · seconds left — [casttime:total] as 1.2 / 2.5" },
    { "[kick]", "a mark while the target's cast can't be interrupted" },
    { "[status]", "DEAD / GHOST / OFFLINE / AFK / DND" },
    { "[combat] [resting] [pvp] [leader]", "a mark when true" },
    { "[mark]", "the raid target icon" },
    { "[threat]", "your threat on the target, percent" },
}

------------------------------------------------------------------------
-- Compile a template → { fmt, readers, groups }. Unknown codes stay as
-- typed. A literal % in the text is escaped for the formatter.
------------------------------------------------------------------------
local function escape(s) return (s:gsub("%%", "%%%%")) end

local compiled = setmetatable({}, { __mode = "k" })
function GU:CompileTemplate(template)
    template = template or ""
    local fmt, readers, groups = {}, {}, {}
    local pos = 1
    while true do
        local s, e, code, style = template:find("%[(%a+):?([%w%.]*)%]", pos)
        if not s then fmt[#fmt + 1] = escape(template:sub(pos)); break end
        fmt[#fmt + 1] = escape(template:sub(pos, s - 1))
        code = code:lower(); style = style:lower()
        -- [hp:pct] and [power:pct] are their own tags
        if (code == "hp" or code == "power") and style:sub(1, 3) == "pct" then
            code, style = code .. "pct", style:sub(4)
        end
        local tag = TAGS[code]
        if tag then
            local spec, reader = tag.make(style)
            fmt[#fmt + 1] = spec
            readers[#readers + 1] = reader
            groups[tag.group] = true
        else
            fmt[#fmt + 1] = escape(template:sub(s, e))
        end
        pos = e + 1
    end
    return { fmt = table.concat(fmt), readers = readers, groups = groups }
end

------------------------------------------------------------------------
-- Pieces on a unit frame. Each is a child frame (for its own level) with a
-- FontString; pieces are pooled per unit and re-configured by LayoutTexts.
------------------------------------------------------------------------
local OUTLINE = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
local Skin

local function FontPath(name)
    if name and name ~= "" then
        local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
        local path = lsm and lsm:Fetch("font", name, true)
        if path then return path end
    end
    if Skin == nil then Skin = LibStub and LibStub("LibGloomSkin-1.0", true) or false end
    return (Skin and Skin.FONT and Skin.FONT.head) or "Fonts\\FRIZQT__.TTF"
end

local function NewPiece(f)
    local fr = CreateFrame("Frame", nil, f)
    fr:SetAllPoints(f)
    local fs = fr:CreateFontString(nil, "OVERLAY")
    return { frame = fr, fs = fs }
end

local scratch = {}
local function Render(piece, unit)
    local c, fs = piece.compiled, piece.fs
    if not c then return end
    local n = 0
    for i = 1, #c.readers do
        local a, b = c.readers[i](unit)
        n = n + 1; scratch[n] = a
        if b ~= nil then n = n + 1; scratch[n] = b end
    end
    for i = n + 1, #scratch do scratch[i] = nil end
    fs:SetFormattedText(c.fmt, unpack(scratch, 1, n))
end

-- Called by the engine from ApplyLayout: (re)build the pieces from cfg.texts.
function GU:LayoutTexts(f, cfg)
    f.texts = f.texts or {}
    local list = cfg.texts or {}
    for i, tc in ipairs(list) do
        local p = f.texts[i] or NewPiece(f)
        f.texts[i] = p
        p.cfg = tc
        local own = GU:TextOwnLayer(tc)
        p.frame:SetFrameStrata((own and tc.strata) or f:GetFrameStrata())
        p.frame:SetFrameLevel(own and (tc.level or 70) or (f:GetFrameLevel() + 70))
        local fs = p.fs
        -- A piece's own font, else the unit's default (stage 2 of the redesign, 2026-09-21).
        fs:SetFont(FontPath((tc.font and tc.font ~= "") and tc.font or cfg.font), tc.size or 22, OUTLINE[tc.outline or "none"] or "")
        if tc.shadow then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 0.8)
        else fs:SetShadowOffset(0, 0) end
        local just = tc.justify or "CENTER"
        fs:SetJustifyH(just)
        fs:ClearAllPoints()
        fs:SetPoint(just, f, "CENTER", tc.x or 0, tc.y or 0)
        fs:SetWordWrap(false)
        if (tc.maxWidth or 0) > 0 then fs:SetWidth(tc.maxWidth) else fs:SetWidth(0) end
        local col = tc.color or { 1, 1, 1 }
        fs:SetTextColor(col[1], col[2], col[3])
        p.compiled = self:CompileTemplate(tc.template)
        p.frame:SetShown(tc.enabled ~= false)
    end
    for i = #list + 1, #f.texts do f.texts[i].frame:Hide(); f.texts[i].cfg = nil end
end

-- Called by the engine whenever the unit's values move. `group` limits the
-- pass to pieces that read that group (the cast tick passes "cast").
function GU:RefreshTexts(f, unit, group)
    if not (f and f.texts) then return end
    local exists = UnitExists(unit)
    for _, p in ipairs(f.texts) do
        local tc = p.cfg
        if tc and tc.enabled ~= false and (not group or (p.compiled and p.compiled.groups[group])) then
            if not exists then
                p.fs:SetText("")
            else
                if tc.classColor then
                    local ok, r, g, b = self.UnitColor(unit)
                    if ok then p.fs:SetTextColor(r, g, b)
                    else local c = tc.color or { 1, 1, 1 }; p.fs:SetTextColor(c[1], c[2], c[3]) end
                end
                Render(p, unit)
            end
        end
    end
end
