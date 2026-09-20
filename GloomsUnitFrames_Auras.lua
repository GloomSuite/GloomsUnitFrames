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
    level     = 60,           -- frame level above the unit frame (rings 1–64)
    -- kind "spell" only: ONE aura by spell ID (buff or debuff, whichever it
    -- is), wearing a Hub silhouette and running a Hub effect while present.
    spellID   = 0,
    shape     = nil,          -- a GloomsHub.SHAPES key
    effect    = nil,          -- a GloomsHub.Effects module id
    effectParams = nil,       -- { [moduleId] = { key = value } }, laid over the module defaults
}

-- Three kinds. Buffs / Debuffs are engine GROUPS narrowed by `filter`; This
-- spell is a pair of SLOTS filtered to one spell ID.
GU.AURA_KINDS = {
    { "buffs",   "Buffs",      "HELPFUL" },
    { "debuffs", "Debuffs",    "HARMFUL" },
    { "spell",   "This spell", nil },
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
    if flt.only and #flt.only > 0 then
        local set = {}; for _, id in ipairs(flt.only) do set[id] = true end
        cand.includeSpellIDs = set
    end
    if flt.never and #flt.never > 0 then
        local set = {}; for _, id in ipairs(flt.never) do set[id] = true end
        cand.excludeSpellIDs = set
    end
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
-- Shape + effect on a button's OWN regions, wired ONCE, here, with no
-- trigger: nothing under an aura button ever tells us it appeared (measured
-- 2026-09-19 — no OnShow, no OnUpdate on a child frame; IsShown/IsVisible
-- answer with a SECRET boolean). So the effect is simply started now and lives
-- under the button, which the engine hides and shows. The Hub's Effects
-- modules verify their mask bind and retry until the texture has drawn
-- (Effects.lua, "Hosts under a Blizzard AuraButton"); the icon's shape mask
-- below does the same.
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
        local function attempt()
            if not live.on then return end
            if not BindMask(icon, mask) then C_Timer.After(0.5, attempt) end
        end
        C_Timer.After(0, attempt)
        local swipe = cd and hub:ShapeAsset(key, "swipe")
        if swipe and cd.SetSwipeTexture then cd:SetSwipeTexture(swipe) end
    end
    -- A Hub effect is the THIS SPELL highlight only. A list group can carry a
    -- stale `effect` (its kind was changed after one was picked) and every one
    -- of its buttons would run it — measured 2026-09-20 as a Breathe storm on
    -- a Buffs group whose effect the tab no longer even shows.
    local E = hub and hub.Effects
    local id = ac.kind == "spell" and ac.effect or nil
    if key and id and E and E.Get and E:Get(id) then
        local merged = GU:EffectParams(ac)
        local mod = E:Get(id)
        if merged then
            GU.fxStarts = (GU.fxStarts or 0) + 1
            local ok, err = pcall(mod.Start, mod, host, host, key, merged)
            if not ok then GU.fxError = err end
            live.hosts[#live.hosts + 1] = { mod = mod, host = host, key = key }
        end
    end
end

-- The effect's parameters for a group: module defaults with the saved ones over.
function GU:EffectParams(ac)
    local E = _G.GloomsHub and _G.GloomsHub.Effects
    if not (E and ac.effect) then return nil end
    return E:MergeParams(ac.effect, ac.effectParams and ac.effectParams[ac.effect])
end
local function ParamsSig(ac)
    local p = GU:EffectParams(ac)
    if not p then return "-" end
    local keys = {}
    for k in pairs(p) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        local v = p[k]
        parts[#parts + 1] = k .. "=" .. (type(v) == "table" and (tostring(v[1]) .. "," .. tostring(v[2]) .. "," .. tostring(v[3])) or tostring(v))
    end
    return table.concat(parts, "|")
end

-- Re-tune a running effect in place (Start is idempotent) when only its
-- parameters changed — no container rebuild, no icon blink. Guarded by a
-- signature: a re-Start re-primes and reveals a frame later, so a storm of
-- them makes the effect flicker (CONTRACTS §8).
local function RestyleEffects(g, ac)
    local sig = ParamsSig(ac)
    if g.live.paramsSig == sig then return end
    g.live.paramsSig = sig
    local merged = GU:EffectParams(ac)
    if not merged then return end
    for _, e in ipairs(g.live.hosts) do pcall(e.mod.Start, e.mod, e.host, e.host, e.key, merged) end
end

-- `slot` (kind "spell"): the engine does not lay slot buttons out, so the
-- button is glued to a frame WE position (moving it later needs no button call).
local function MakeInitializer(ac, slotAnchor, live)
    local w, h = IconRect(ac)
    local size = math.max(w, h)
    return function(button)
        -- 1 · size: the flow layout only anchors; an unsized button draws nothing
        button:SetSize(w, h)
        if slotAnchor then
            button:ClearAllPoints(); button:SetAllPoints(slotAnchor)
            button:SetFrameLevel(slotAnchor:GetFrameLevel() + 1)
        end
        -- an explicitly sized frame of our own for the shape mask and the
        -- effect to size against; it hides and shows with the button
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
    local fstr, cand
    if ac.kind ~= "spell" then fstr, cand = GU:AuraFilter(ac) end
    return table.concat({ ac.kind == "spell" and ("spell" .. tostring(ac.spellID)) or (fstr .. "#" .. CandSig(cand)),
        tostring(ac.sort), ac.size or 28, ac.showDuration ~= false and 1 or 0,
        ac.durationSize or 11, ac.showStacks ~= false and 1 or 0, ac.stackSize or 11,
        ac.swipe ~= false and 1 or 0, ac.border ~= false and 1 or 0,
        tostring(ac.shape), tostring(ac.effect) }, ":")   -- effect PARAMS restyle live, see RestyleEffects
end

local function Retire(g)
    if not g then return end
    if g.live then
        g.live.on = false
        for _, e in ipairs(g.live.hosts) do pcall(e.mod.Stop, e.mod, e.host) end
    end
    if g.container then
        pcall(g.container.SetUnit, g.container, nil)
        g.container:Hide()
    end
    g.holder:Hide()
end

local function LayoutLive(g, ac, f)
    local c, holder = g.container, g.holder
    holder:SetFrameLevel(f:GetFrameLevel() + (ac.level or 60))
    holder:SetShown(ac.enabled ~= false)
    local anchor = AnchorFor(ac.growH, ac.growV)
    if g.slotAnchor then
        -- kind "spell": the icon's centre sits at the offset
        g.slotAnchor:SetSize(IconRect(ac))
        g.slotAnchor:ClearAllPoints(); g.slotAnchor:SetPoint("CENTER", f, "CENTER", ac.x or 0, ac.y or 0)
        c:ClearAllPoints(); c:SetPoint("CENTER", g.slotAnchor, "CENTER")
        return
    end
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
    -- what this container's buttons are running, so Retire can stop it
    local live = { on = true, hosts = {} }
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    if not (ok and c) then
        GU.aurasFailed = (GU.aurasFailed or 0) + 1
        holder:Hide()
        return nil
    end
    c:SetSize(1, 1)
    local g = { holder = holder, container = c, sig = Signature(ac), live = live }
    if ac.kind == "spell" then
        g.slotAnchor = CreateFrame("Frame", nil, holder)
        g.slotAnchor:SetFrameLevel(holder:GetFrameLevel())
        LayoutLive(g, ac, f)
        -- one slot per polarity: a spell is a buff or a debuff, and asking
        -- the user which is a question the engine can answer for us
        local ids = { [tonumber(ac.spellID) or 0] = true }
        for _, pol in ipairs({ "HELPFUL", "HARMFUL" }) do
            c:AddAuraSlot(pol, pol, { candidateFilters = { includeSpellIDs = ids },
                                       initializeFrame = MakeInitializer(ac, g.slotAnchor, live) })
        end
    else
        LayoutLive(g, ac, f)
        local iw, ih = IconRect(ac)
        local fstr, cand = GU:AuraFilter(ac)
        local sortMethod, sortDirection = SortOpts(ac)
        c:AddAuraGroup("main", fstr, {
            maxFrameCount = ac.max or 8,
            candidateFilters = cand,
            sortMethod = sortMethod, sortDirection = sortDirection,
            initializeFrame = MakeInitializer(ac, nil, live),
            layout = { elementWidth = iw, elementHeight = ih,
                       elementSpacing = ac.spacing or 3, lineSpacing = ac.spacing or 3 },
        })
    end
    -- unit LAST: event registration is evaluated on SetUnit and needs the group in place
    c:SetUnit(unit)
    c:UpdateAllAuras()
    c:Show()
    return g
end

-- Called by the engine from ApplyLayout.
function GU:LayoutAuras(f, cfg, unit)
    f.auras = f.auras or {}
    local list = cfg.auras or {}
    for i, ac in ipairs(list) do
        local g = f.auras[i]
        if g and g.sig ~= Signature(ac) then Retire(g); g = nil end
        if not g then
            g = Build(f, unit, ac)
            f.auras[i] = g or false
            if g then g.live.paramsSig = ParamsSig(ac) end
        else
            LayoutLive(g, ac, f)
            RestyleEffects(g, ac)
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
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(tonumber(text) or text)
    if info and info.spellID then return info.spellID, info.name, info.iconID end
    return nil
end
