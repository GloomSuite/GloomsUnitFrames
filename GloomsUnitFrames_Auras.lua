-- GloomsUnitFrames_Auras.lua — AURA GROUPS on the frames: any number per
-- unit, each a filtered list of the unit's buffs or debuffs (all, or only
-- yours, or dispellable), laid out as icons growing from a point you place,
-- with the engine's own duration swipe, countdown and stack count.
--
-- ★ HOW THIS SURVIVES 12.1 (Hub FINDINGS §1; EllesmereUI's AuraKit is the
-- reference for the GROUP form of the API, GA's AuraDuration for the rules)
-- Aura data is fully secret to addons in combat. The one object allowed to
-- hold an aura is a Blizzard AuraButton, so the display is a Blizzard
-- `AuraContainer` with an `AddAuraGroup`: the ENGINE scans the unit's auras
-- against a filter string, sorts them, lays the buttons out in a flow, and
-- renders icon / swipe / countdown / stacks into regions WE create as
-- children of each button — inside `initializeFrame`, the only window in
-- which addon code may touch the button. The addon never sees an aura.
-- Rules that are load-bearing (all measured by GA / EUI on this client):
--   • Everything that touches the BUTTON happens in initializeFrame. After
--     it returns, the button is denied to addon code whenever auras are
--     secret; our own child regions stay writable.
--   • Regions get their font BEFORE they are registered: registering runs
--     the engine's update at once, and an unstyled FontString hard-errors.
--   • A group's filter string is FIXED at declaration and groups are add-
--     only. A setting that changes the filter (or anything set inside
--     initializeFrame — sizes, fonts) swaps in a fresh container; a change of
--     max count or position adjusts the live one.
--   • A target container does not follow target swaps by itself (§1 point
--     2): PLAYER_TARGET_CHANGED → UpdateAllAuras.
--   • Bind and anchor FIRST, decorate LAST: the window is one-shot, and a
--     throw in cosmetics must not cost the bindings.

local GU = _G.GloomsUnitFrames

------------------------------------------------------------------------
-- Defaults for one aura group
------------------------------------------------------------------------
GU.AURA_DEFAULTS = {
    enabled   = true,
    kind      = "buffs",      -- see GU.AURA_KINDS
    max       = 8,
    size      = 28,
    spacing   = 3,
    perLine   = 8,
    sort      = "default",    -- "default" (engine order) | "expiring" (soonest first) | "expiringLast"
    growH     = "RIGHT",      -- "RIGHT" | "LEFT"
    growV     = "UP",         -- "UP" | "DOWN"
    x = 0, y = 0,
    showDuration = true, durationSize = 11,
    showStacks   = true, stackSize = 11,
    swipe     = true,         -- the engine's cooldown swipe over the icon
    border    = true,         -- 1px dark edge
    -- LAYER (the redesign's Layer Override plate, 2026-09-21): off = the unit's
    -- strata, 60 above the unit frame (rings 1–64); on = `strata` + `level`, own.
    ownLayer  = nil,          -- nil on an old group: on iff its level was changed from 60
    strata    = nil,
    level     = 60,
    shape     = nil,          -- a GloomsHub.SHAPES key, worn by every icon in the group
    name      = nil,          -- the row's name in the tab; nil = the kind's label
}
function GU:AuraOwnLayer(ac)
    if ac.ownLayer ~= nil then return ac.ownLayer end
    return ac.level ~= nil and ac.level ~= 60
end
local function AuraLevel(ac, f)
    if GU:AuraOwnLayer(ac) then return ac.level or 60 end
    return f:GetFrameLevel() + 60
end

-- Two kinds: Buffs / Debuffs are engine GROUPS narrowed by `filter`.
-- ⚠ There was a third, "This spell" — ONE aura by spell ID wearing a Hub effect —
-- REMOVED by the owner 2026-09-20: on the player, the engine ignores a spell-ID
-- filter on HARMFUL auras (measured through a slot and a group, in either order:
-- a group filtered to one ID showed Void Breach, then Blood Draw), and a
-- highlight that cannot single out a DEBUFF is "effectively useless" (his words).
-- Hub FINDINGS §20 holds the evidence. The Hub-effect-under-a-button machinery
-- went with it; a saved group of that kind is dropped at load (EnsureAuras).
GU.AURA_KINDS = {
    { "buffs",   "Buffs",      "HELPFUL" },
    { "debuffs", "Debuffs",    "HARMFUL" },
}
local BASE, KIND_LABEL = {}, {}
for _, k in ipairs(GU.AURA_KINDS) do BASE[k[1]] = k[3]; KIND_LABEL[k[1]] = k[2] end
GU.AURA_KIND_LABEL = KIND_LABEL

-- The filter CLASSES a group can require ("only") or refuse ("never"). Every
-- one is decided by the ENGINE, so they hold under secrecy. `token` classes
-- go into the filter string (negated with "!"), `cand` classes are boolean
-- candidate filters, `dispel` classes are the include/exclude dispel-type
-- sets. Vocabulary as EllesmereUI's AuraKit verified it on 12.1; `pol` says
-- which polarity a class means anything for.
GU.AURA_CLASSES = {
    { key = "mine",        label = "Cast by you",                  pol = "both",   token = "PLAYER" },
    { key = "fromplayer",  label = "From a player or pet",         pol = "debuff", cand = "isFromPlayerOrPlayerPet" },
    { key = "boss",        label = "Boss debuffs",                 pol = "debuff", cand = "isBossAura" },
    { key = "important",   label = "Important (raid priority)",    pol = "debuff", cand = "isPriorityAura" },
    { key = "cc",          label = "Crowd control",                pol = "debuff", token = "CROWD_CONTROL" },
    { key = "role",        label = "Role debuffs",                 pol = "debuff", cand = "isRoleAura" },
    { key = "raid",        label = "Raid",                         pol = "both",   token = "RAID" },
    { key = "raidcombat",  label = "Raid, in combat",              pol = "both",   token = "RAID_IN_COMBAT" },
    { key = "dispellable", label = "Dispellable by you",           pol = "debuff", token = "RAID_PLAYER_DISPELLABLE" },
    { key = "canapply",    label = "Debuffs your class can apply", pol = "debuff", cand = "canApplyAura" },
    { key = "magic",       label = "Magic",                        pol = "debuff", dispel = "Magic" },
    { key = "curse",       label = "Curse",                        pol = "debuff", dispel = "Curse" },
    { key = "poison",      label = "Poison",                       pol = "debuff", dispel = "Poison" },
    { key = "disease",     label = "Disease",                      pol = "debuff", dispel = "Disease" },
    { key = "bleed",       label = "Bleed",                        pol = "debuff", dispel = "Bleed" },
    { key = "bigdef",      label = "Big defensives",               pol = "buff",   token = "BIG_DEFENSIVE" },
    { key = "extdef",      label = "External defensives",          pol = "buff",   token = "EXTERNAL_DEFENSIVE" },
    { key = "cancel",      label = "Cancelable",                   pol = "buff",   token = "CANCELABLE" },
    { key = "stealable",   label = "Stealable / purgeable",        pol = "buff",   cand = "isStealable" },
}

-- ac.filter = { classes = { [key] = "only"|"never" }, timed = bool, only = {ids}, never = {ids} }
-- → the engine filter string and the candidateFilters table for the group.
function GU:AuraFilter(ac)
    local flt = ac.filter or {}
    local classes = flt.classes or {}
    local pol = (ac.kind == "buffs") and "buff" or "debuff"
    local tokens, cand, inc, exc = {}, {}, nil, nil
    for _, c in ipairs(GU.AURA_CLASSES) do
        local mode = classes[c.key]
        if mode and (c.pol == "both" or c.pol == pol) then
            if c.token then tokens[#tokens + 1] = (mode == "never" and "!" or "") .. c.token
            elseif c.cand then cand[c.cand] = (mode == "only")
            elseif c.dispel then
                if mode == "only" then inc = inc or {}; inc[c.dispel] = true
                else exc = exc or {}; exc[c.dispel] = true end
            end
        end
    end
    -- one canonical token order: the engine shares one scan per exact string
    table.sort(tokens, function(a, b) return (a:gsub("^!", "")) < (b:gsub("^!", "")) end)
    local str = BASE[ac.kind] or "HELPFUL"
    if #tokens > 0 then str = str .. "|" .. table.concat(tokens, "|") end
    if inc then cand.includeDispelTypes = inc end
    if exc then cand.excludeDispelTypes = exc end
    if flt.timed then cand.maxDuration = math.huge end
    -- ⚠ The spell-ID lists (`flt.only` / `flt.never` → includeSpellIDs /
    -- excludeSpellIDs) were REMOVED by the owner 2026-09-21: the engine ignores
    -- them on the player's debuffs (Hub FINDINGS §20.6) and "three of four
    -- cases isn't good enough, and is just confusing." A saved list is ignored.
    return str, (next(cand) ~= nil) and cand or nil
end

-- Sort options for AddAuraGroup. BigWigs' aura plugin documents the values.
local function SortOpts(ac)
    if ac.sort ~= "expiring" and ac.sort ~= "expiringLast" then return nil, nil end
    local rule = (Enum.UnitAuraSortRule and Enum.UnitAuraSortRule.ExpirationOnly) or 4
    local dirs = Enum.UnitAuraSortDirection or {}
    local dir = (ac.sort == "expiringLast") and (dirs.Reverse or 1) or (dirs.Normal or 0)
    return rule, dir
end

local function CandSig(cand)
    if not cand then return "-" end
    local keys = {}
    for k in pairs(cand) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        local v = cand[k]
        if type(v) == "table" then
            local ks = {}; for kk in pairs(v) do ks[#ks + 1] = tostring(kk) end; table.sort(ks)
            out[#out + 1] = k .. "={" .. table.concat(ks, ",") .. "}"
        else out[#out + 1] = k .. "=" .. tostring(v) end
    end
    return table.concat(out, ";")
end

-- The pre-filter kinds ("My debuffs" and friends) become filter settings.
local LEGACY = {
    mybuffs   = { "buffs",   "mine" },
    mydebuffs = { "debuffs", "mine" },
    dispel    = { "debuffs", "dispellable" },
    stealable = { "buffs",   "cancel" },
}
function GU:MigrateAuraGroup(ac)
    local m = LEGACY[ac.kind]
    if m then
        ac.kind = m[1]
        ac.filter = ac.filter or {}
        ac.filter.classes = ac.filter.classes or {}
        ac.filter.classes[m[2]] = "only"
    end
    ac.filter = ac.filter or {}
    ac.filter.classes = ac.filter.classes or {}
end

-- The first icon sits at this corner of the container, given the growth.
local function AnchorFor(growH, growV)
    local v = (growV == "DOWN") and "TOP" or "BOTTOM"
    local h = (growH == "LEFT") and "RIGHT" or "LEFT"
    return v .. h
end

-- An icon takes its silhouette's footprint: `size` is the LONG side; a 2:1
-- portrait shape at 28 is 14 wide × 28 tall, a landscape one 28 × 14. The
-- square icon art is CROPPED to that aspect, never squashed.
local function IconRect(ac)
    local size = ac.size or 28
    local hub = _G.GloomsHub
    local info = ac.shape and hub and hub.ShapeInfo and hub:ShapeInfo(ac.shape)
    local aspect, orient = (info and info.aspect) or 1, info and info.orient
    if aspect <= 1 or not orient or orient == "square" then return size, size end
    if orient == "portrait" then return size / aspect, size end
    return size, size / aspect
end
GU.AuraIconRect = IconRect

local function CropCoords(w, h)
    local z = 0.08
    local span = 1 - 2 * z
    if h > w then
        local u = span * (w / h); local u0 = 0.5 - u / 2
        return u0, 1 - u0, z, 1 - z
    elseif w > h then
        local v = span * (h / w); local v0 = 0.5 - v / 2
        return z, 1 - z, v0, 1 - v0
    end
    return z, 1 - z, z, 1 - z
end

local Skin
local function FontPath()
    if Skin == nil then Skin = LibStub and LibStub("LibGloomSkin-1.0", true) or false end
    return (Skin and Skin.FONT and Skin.FONT.head) or "Fonts\\FRIZQT__.TTF"
end

local function Available()
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    return true
end

------------------------------------------------------------------------
-- initializeFrame: one button, wired once. `ac` is the group config at
-- creation time — anything read from it here is baked into this container.
------------------------------------------------------------------------
-- The shape on a button's OWN regions, wired ONCE, here, with no trigger:
-- nothing under an aura button ever tells us it appeared (measured 2026-09-19
-- — no OnShow, no OnUpdate on a child frame; IsShown/IsVisible answer with a
-- SECRET boolean). The mask bind is verified and retried until the texture
-- has drawn. (A Hub EFFECT used to be started here too, for the This-spell
-- kind; that kind is gone — see AURA_KINDS.)
local issecretvalue = _G.issecretvalue
local function BindMask(tex, mask)
    tex:AddMaskTexture(mask)
    if tex.GetNumMaskTextures then
        local n = tex:GetNumMaskTextures()
        if not (issecretvalue and issecretvalue(n)) and n == 0 then return false end
    end
    return true
end

local function Decorate(button, icon, cd, host, ac, size, live)
    local hub = _G.GloomsHub
    local key = ac.shape
    local path = key and hub and hub.ShapeAsset and hub:ShapeAsset(key, "base")
    if path then
        local mask = button:CreateMaskTexture()
        mask:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        hub:GrowAnchor(mask, host, 0)
        -- In a fight the icon is a forbidden object and AddMaskTexture THROWS (20×
        -- on the DK's first pull, 2026-09-20 — buttons wired mid-combat by a buff
        -- appearing); so wait for regen, and never let the bind error escape.
        local function attempt()
            if not live.on then return end
            if InCombatLockdown() then C_Timer.After(1, attempt); return end
            local ok, bound = pcall(BindMask, icon, mask)
            if not (ok and bound) then C_Timer.After(0.5, attempt) end
        end
        C_Timer.After(0, attempt)
        local swipe = cd and hub:ShapeAsset(key, "swipe")
        if swipe and cd.SetSwipeTexture then cd:SetSwipeTexture(swipe) end
    end
end

local function MakeInitializer(ac, live)
    local w, h = IconRect(ac)
    local size = math.max(w, h)
    return function(button)
        -- 1 · size: the flow layout only anchors; an unsized button draws nothing
        button:SetSize(w, h)
        -- an explicitly sized frame of our own for the shape mask to size
        -- against; it hides and shows with the button
        local host = CreateFrame("Frame", nil, button)
        host:SetSize(w, h); host:SetPoint("CENTER", button, "CENTER")
        host:EnableMouse(false)

        -- 2 · regions, styled BEFORE registration
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)
        icon:SetTexCoord(CropCoords(w, h))
        local border
        if ac.border ~= false and not ac.shape then
            border = button:CreateTexture(nil, "BACKGROUND")
            border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
            border:SetColorTexture(0, 0, 0, 0.9)
        end
        local cd
        if ac.swipe ~= false then
            cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cd:SetAllPoints(button)
            cd:SetDrawEdge(false); cd:SetDrawBling(false)
            cd:SetHideCountdownNumbers(true)
            cd:SetSwipeColor(0, 0, 0, 0.6)
        end
        local carrier = CreateFrame("Frame", nil, button)
        carrier:SetAllPoints(button)
        carrier:SetFrameLevel((cd and cd:GetFrameLevel() or button:GetFrameLevel()) + 2)
        carrier:EnableMouse(false)
        local font = FontPath()
        local dur, stack
        if ac.showDuration ~= false then
            dur = carrier:CreateFontString(nil, "OVERLAY")
            dur:SetFont(font, ac.durationSize or 11, "OUTLINE")
            dur:SetPoint("CENTER", 0, 0)
            dur:SetTextColor(1, 1, 1)
        end
        if ac.showStacks ~= false then
            stack = carrier:CreateFontString(nil, "OVERLAY")
            stack:SetFont(font, ac.stackSize or 11, "OUTLINE")
            stack:SetPoint("BOTTOMRIGHT", 1, -1)
            stack:SetTextColor(1, 1, 1)
        end

        -- 3 · bind. Clicks off (they would eat clicks on whatever is under the
        -- frame); motion stays on so the engine's tooltip works.
        pcall(button.SetMouseClickEnabled, button, false)
        button:SetIcon(icon)
        if cd then button:SetDurationCooldown(cd) end
        if stack then button:SetApplicationCount(stack, {}) end
        if dur then button:SetDurationText(dur, { zeroDurationText = "", expiredText = "" }) end

        -- 4 · decoration, last: a throw here must not cost the bindings
        local okD, errD = pcall(Decorate, button, icon, cd, host, ac, size, live)
        if not okD then GU.decorateError = errD end
    end
end

------------------------------------------------------------------------
-- Containers. One per aura group; keyed on the unit frame.
------------------------------------------------------------------------
-- What must match for a live container to be kept; anything else → rebuild.
local function Signature(ac)
    local fstr, cand = GU:AuraFilter(ac)
    return table.concat({ fstr .. "#" .. CandSig(cand),
        tostring(ac.sort), ac.size or 28, ac.showDuration ~= false and 1 or 0,
        ac.durationSize or 11, ac.showStacks ~= false and 1 or 0, ac.stackSize or 11,
        ac.swipe ~= false and 1 or 0, ac.border ~= false and 1 or 0,
        tostring(ac.shape) }, ":")
end

local function Retire(g)
    if not g then return end
    if g.live then g.live.on = false end
    if g.container then
        pcall(g.container.SetUnit, g.container, nil)
        g.container:Hide()
    end
    g.holder:Hide()
end

local function LayoutLive(g, ac, f)
    local c, holder = g.container, g.holder
    holder:SetFrameStrata((GU:AuraOwnLayer(ac) and ac.strata) or f:GetFrameStrata())
    holder:SetFrameLevel(AuraLevel(ac, f))
    holder:SetShown(ac.enabled ~= false)
    local anchor = AnchorFor(ac.growH, ac.growV)
    c:ClearAllPoints()
    c:SetPoint(anchor, f, "CENTER", ac.x or 0, ac.y or 0)
    if c.SetFlowLayoutAnchorPoint then c:SetFlowLayoutAnchorPoint(anchor) end
    local FD = AnchorUtil and AnchorUtil.FlowDirection
    if c.SetFlowLayoutGrowthDirection and FD then
        c:SetFlowLayoutGrowthDirection((ac.growH == "LEFT") and FD.Left or FD.Right, (ac.growV == "DOWN") and FD.Down or FD.Up)
    end
    local n = math.max(1, ac.perLine or 8)
    local iw, ih = IconRect(ac)
    local lineSize = n * iw + (n - 1) * (ac.spacing or 3) + 0.5
    if c.SetFlowLayoutMaximumLineSize then c:SetFlowLayoutMaximumLineSize(lineSize) end
    if c.SetAuraGroupMaxFrameCount then pcall(c.SetAuraGroupMaxFrameCount, c, "main", ac.enabled ~= false and (ac.max or 8) or 0) end
    if c.SetAuraGroupLayout then
        pcall(c.SetAuraGroupLayout, c, "main", { elementWidth = iw, elementHeight = ih,
                                                   elementSpacing = ac.spacing or 3, lineSpacing = ac.spacing or 3 })
    end
end

local function Build(f, unit, ac)
    if not Available() then return nil end
    local holder = CreateFrame("Frame", nil, f)
    holder:SetAllPoints(f)
    -- `on` lets a retired container's pending mask binds stop
    local live = { on = true }
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    if not (ok and c) then
        GU.aurasFailed = (GU.aurasFailed or 0) + 1
        holder:Hide()
        return nil
    end
    c:SetSize(1, 1)
    local g = { holder = holder, container = c, sig = Signature(ac), live = live }
    LayoutLive(g, ac, f)
    local iw, ih = IconRect(ac)
    local fstr, cand = GU:AuraFilter(ac)
    local sortMethod, sortDirection = SortOpts(ac)
    c:AddAuraGroup("main", fstr, {
        maxFrameCount = ac.max or 8,
        candidateFilters = cand,
        sortMethod = sortMethod, sortDirection = sortDirection,
        initializeFrame = MakeInitializer(ac, live),
        layout = { elementWidth = iw, elementHeight = ih,
                   elementSpacing = ac.spacing or 3, lineSpacing = ac.spacing or 3 },
    })
    -- unit LAST: event registration is evaluated on SetUnit and needs the group in place
    c:SetUnit(unit)
    c:UpdateAllAuras()
    c:Show()
    return g
end

------------------------------------------------------------------------
-- The PREVIEW (the owner, 2026-09-20): sample icons drawn where a group's
-- buttons will be, so it can be placed and sized before any aura is up —
-- the engine only ever draws buttons for auras you actually have. Our own
-- textures, laid out by the same rules the engine's flow layout is given
-- (icon rect, spacing, wrap, growth direction, anchor corner), with the
-- group's shape. Shown for the SELECTED group while the tab's Auras section
-- is open, like the cast ring's fake cast. Icons come from your own spellbook.
------------------------------------------------------------------------
local auraPreview = {}   -- [unit] = index of the previewed group, or nil

local sampleIcons
local function SampleIcons()
    if sampleIcons then return sampleIcons end
    sampleIcons = {}
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local n = C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines() or 0
    for line = 1, n do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and info.itemIndexOffset and info.numSpellBookItems then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local ok, item = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
                if ok and item and item.iconID and not item.isPassive and item.iconID ~= 134400 then
                    sampleIcons[#sampleIcons + 1] = item.iconID
                end
                if #sampleIcons >= 40 then break end
            end
        end
        if #sampleIcons >= 40 then break end
    end
    if #sampleIcons == 0 then sampleIcons[1] = 134400 end
    return sampleIcons
end

local function LayoutAuraPreview(f, cfg, unit)
    local idx = auraPreview[unit]
    local ac = idx and cfg.auras and cfg.auras[idx]
    local pv = f.auraPreview
    if not ac then if pv then pv:Hide() end return end
    if not pv then
        pv = CreateFrame("Frame", nil, f)
        pv.icons = {}
        f.auraPreview = pv
    end
    pv:SetFrameStrata((GU:AuraOwnLayer(ac) and ac.strata) or f:GetFrameStrata())
    pv:SetFrameLevel(AuraLevel(ac, f) + 1)
    local iw, ih = IconRect(ac)
    local gap = ac.spacing or 3
    local perLine = math.max(1, ac.perLine or 8)
    local count = math.max(1, math.min(ac.max or 8, 40))
    local anchor = AnchorFor(ac.growH, ac.growV)
    local sx = (ac.growH == "LEFT") and -1 or 1
    local sy = (ac.growV == "DOWN") and -1 or 1
    pv:ClearAllPoints()
    pv:SetPoint(anchor, f, "CENTER", ac.x or 0, ac.y or 0)
    pv:SetSize(1, 1)
    local hub = _G.GloomsHub
    local maskPath = ac.shape and hub and hub.ShapeAsset and hub:ShapeAsset(ac.shape, "base")
    local icons = SampleIcons()
    for k = 1, math.max(count, #pv.icons) do
        local slot = pv.icons[k]
        if k <= count then
            if not slot then
                slot = CreateFrame("Frame", nil, pv)
                slot.tex = slot:CreateTexture(nil, "ARTWORK")
                slot.tex:SetAllPoints(slot)
                slot.edge = slot:CreateTexture(nil, "BACKGROUND")
                slot.edge:SetColorTexture(0, 0, 0, 0.9)
                slot.mask = slot:CreateMaskTexture()
                pv.icons[k] = slot
            end
            local col, row = (k - 1) % perLine, math.floor((k - 1) / perLine)
            slot:SetSize(iw, ih)
            slot:ClearAllPoints()
            slot:SetPoint(anchor, pv, anchor, sx * col * (iw + gap), sy * row * (ih + gap))
            slot.tex:SetTexture(icons[((k - 1) % #icons) + 1])
            slot.tex:SetTexCoord(CropCoords(iw, ih))
            slot.tex:SetAlpha(0.9)
            slot.tex:RemoveMaskTexture(slot.mask)
            if maskPath then
                slot.mask:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                hub:GrowAnchor(slot.mask, slot, 0)
                slot.tex:AddMaskTexture(slot.mask)
                slot.edge:Hide()
            elseif ac.border ~= false then
                -- a square icon's 1px dark edge, as the live one draws it
                slot.edge:ClearAllPoints()
                slot.edge:SetPoint("TOPLEFT", -1, 1); slot.edge:SetPoint("BOTTOMRIGHT", 1, -1)
                slot.edge:Show()
            else
                slot.edge:Hide()
            end
            slot:Show()
        elseif slot then
            slot:Hide()
        end
    end
    pv:SetShown(ac.enabled ~= false)
end

-- The tab: preview group `index` of `unit` (nil = off). Re-laid on every ApplyLayout.
function GU:SetAuraPreview(unit, index)
    auraPreview[unit] = index
    local f = self.Frame and self:Frame(unit)
    local cfg = self:Config(unit)
    if f and cfg then LayoutAuraPreview(f, cfg, unit) end
end

-- Called by the engine from ApplyLayout.
function GU:LayoutAuras(f, cfg, unit)
    LayoutAuraPreview(f, cfg, unit)
    f.auras = f.auras or {}
    local list = cfg.auras or {}
    for i, ac in ipairs(list) do
        local g = f.auras[i]
        if g and g.sig ~= Signature(ac) then Retire(g); g = nil end
        if not g then
            g = Build(f, unit, ac)
            f.auras[i] = g or false
        else
            LayoutLive(g, ac, f)
        end
    end
    for i = #list + 1, #f.auras do
        if f.auras[i] then Retire(f.auras[i]) end
        f.auras[i] = nil
    end
end

-- A target container only reacts to its own unit's UNIT_AURA: nudge it on a swap.
function GU:RefreshAuras(f)
    if not (f and f.auras) then return end
    for _, g in ipairs(f.auras) do
        if g and g.container and g.container.UpdateAllAuras then g.container:UpdateAllAuras() end
    end
end

-- Resolve what the user typed (a spell ID or a name) to an ID + display name.
-- Names resolve only for spells the game can find by name (usually your own);
-- an ID always works, and is what a boss debuff needs.
function GU:ResolveSpell(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    if text == "" then return nil end
    -- "Name (ID)" — the tab's own rendering of a stored entry — resolves by the ID.
    local tail = text:match("%((%d+)%)%s*$")
    if tail then text = tail end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(tonumber(text) or text)
    if info and info.spellID then return info.spellID, info.name, info.iconID end
    -- A bare number is accepted as-is: an aura's ID (a zone debuff, a boss
    -- mechanic) often has no spell record the client will hand back, and it is
    -- still exactly the key the engine filters on (the owner, 2026-09-20).
    local n = tonumber(text)
    if n and n > 0 and n == math.floor(n) then return n, nil, nil end
    return nil
end
