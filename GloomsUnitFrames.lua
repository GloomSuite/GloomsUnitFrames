-- GloomsUnitFrames.lua — Gloom's Unit Frames, the suite's sixth tool: the ENGINE.
-- Circular health / power displays for the player and the target: arcs of any
-- span, placeable, layerable, colorable. /gu opens the Unit Frames tab of the
-- Suite window (GloomsUnitFrames_Tab.lua).
--
-- ★ HOW A RING IS DRAWN, AND WHY — measured 2026-09-19 (Hub FINDINGS §18)
-- On 12.1 UnitHealth is a SECRET number for EVERY unit, everywhere — the
-- player's own, on a training dummy, in and out of combat. Lua may never do
-- arithmetic on it, so "angle = health / max * span" is impossible. What IS
-- possible: hand the secret to a widget setter the engine evaluates itself.
-- `Texture:SetRotation`, `MaskTexture:SetRotation` and `Texture:SetAlpha`
-- accept a secret, and `UnitHealthPercent(unit, true, curve)` returns the
-- health percent pushed through a curve (C_CurveUtil) — evaluated engine-
-- side, result still secret. So:
--   • The art never moves. Two HALF-PLANE MASKS sit on it: one FIXED at the
--     arc's start, one ROTATED by the swept angle; their intersection is the
--     visible wedge. A wedge is at most 180°, so a span over 180° is drawn as
--     ceil(span/180) "chunks", each with its own masks and its own curves.
--   • Two half-planes can never intersect to NOTHING (rotate past empty and
--     the overlap wraps round to the far side — a floating sliver, seen on
--     the first build). So EMPTY is done with ALPHA: each chunk's opacity is
--     its own curve, 0 until the value reaches that chunk.
--   • The fixed mask is a hair WIDER than 180° (182°) so each chunk begins a
--     degree inside the previous one — no seam where two anti-aliased edges
--     would otherwise meet at 50%. The rotating mask is exact, so it bounds
--     the far end and nothing is double-drawn.
--   • Thickness is a third mask: a HOLE cut from a solid disc.
--   • "Shift" colours are two more layers (mid, low) whose opacity curves
--     fade them in as the value drains — on top of a solid or gradient base.
--   • A GRADIENT is a layer too: the art's ramp companion (same shape, alpha
--     0→1 left to right), rotated to the chosen angle, tinted with the end
--     colour, over the solid base colour. Masks are capped at THREE per
--     texture (measured), which is why the shape is baked in, not masked.
--     NOT Texture:SetGradient — a texture carrying one ACCEPTS a secret alpha
--     and silently ignores it (probe J), so it could never be gated.
--   • A ROUND END on the moving edge is a small disc MASK pivoting about the
--     ring's centre by the same curve (SetRotation takes a pivot; a secret
--     angle is accepted — probe K), applied to ring-sized copies of the fill's
--     layers, so it is cut from the same art and colours as the arc.
-- No number ever reaches Lua. What does NOT accept a secret (same
-- measurement): SetWidth, Cooldown setters, Animation:SetDegrees. SetPoint
-- ACCEPTS one and silently drops it; so does SetAlpha on a gradient texture.
--
-- This file owns the frames and the saved settings and exposes a small API on
-- `GloomsUnitFrames` for the tab. It draws no config UI of its own.
--
-- COORDINATE SYSTEM NOTE (as Portraits): WoW's UI space is 768 units tall at
-- any resolution; ~1365 wide at 16:9; screen centre is 0,0.

local GU = {}
_G.GloomsUnitFrames = GU

local PI = math.pi
local issecretvalue = _G.issecretvalue

local ART = "Interface\\AddOns\\GloomsUnitFrames\\Media\\art\\"
-- key → { label, path, ramp }. `ramp` is the art's GRADIENT COMPANION: the
-- same shape with a left→right alpha ramp baked in (a texture may carry at
-- most 3 masks — measured — so the ramp cannot be shaped by the art at
-- runtime). Custom art without a companion falls back to the disc's.
GU.RING_TEXTURES = {
    disc = { label = "Solid", path = ART .. "disc.png", ramp = ART .. "disc-ramp.png" },
}
-- The ramp at NARROWER fade widths (disc-ramp-10 … disc-ramp-90: the 0→1
-- runs over that percent of the diameter, centred; the disc shape is baked
-- in as always). The shield wash picks one so its fade fits the arc.
local function RampAt(pct, fullRamp)
    pct = math.max(10, math.min(100, math.floor(pct / 10 + 0.5) * 10))   -- (clamp is defined below)
    if pct >= 100 then return fullRamp end
    return ART .. "disc-ramp-" .. pct .. ".png"
end
-- The ROTATING mask, exact 180°, one per sweep direction: SOFT on its leading
-- (moving) edge, HARD on its trailing edge — the trailing edge can end up
-- inside the overlap zone over the other chunk (spans ≥ ~358°), where a soft
-- edge drawn in two layers leaves a residual line.
local MASK_ROT   = { ccw = ART .. "halfplane-ccw.png", cw = ART .. "halfplane-cw.png" }
local MASK_CAP   = ART .. "cap.png"                 -- hard 3° wedge: covers a full ring's closing point
-- The FIXED mask of a chunk that follows another: exact half-turn plus D of
-- overshoot on its START side only (over the previous chunk — the overlap
-- that kills the seam), binary edges. Nothing past its far end, so an empty
-- chunk is a hairline, not a wedge. One per sweep direction.
local MASK_LEAD  = { ccw = ART .. "halfplane-lead-ccw.png", cw = ART .. "halfplane-lead-cw.png" }
local MASK_HOLE  = ART .. "hole.png"             -- transparent disc, radius 120/128
local HOLE_SCALE = 256 / 240                     -- mask size per unit of inner diameter
local ART_R      = 250 / 256                     -- the disc art's radius as a fraction of its half-size

------------------------------------------------------------------------
-- Defaults
------------------------------------------------------------------------
-- Angles are DEGREES in math convention: 0 = right, 90 = top, 180 = left,
-- counter-clockwise positive. `start` is where the arc begins (the full end);
-- it sweeps `span` degrees in `direction` as the value FILLS. The factory look
-- is the speedometer the owner briefed: health from the left over the top,
-- power from the left under the bottom, so both begin at the same point.
local function RingDefaults(over)
    local r = {
        enabled   = true,
        size      = 220,          -- this ring's outer diameter, px
        dx        = 0, dy = 0,    -- offset from the unit's centre
        start     = 180,
        span      = 180,
        clockwise = true,
        thickness = 22,           -- px, cut from the inside
        texture   = "disc",
        -- Colour: "solid" or "gradient" (color → color2 along `gradientAngle`)
        -- as the base; `shift` additionally fades midColor in by 50% and
        -- lowColor in toward empty, as alpha layers on top.
        colorMode = "solid",
        shift     = false,
        color     = { 0.0, 1.0, 0.6 },
        color2    = { 0.58, 0.42, 1.0 },
        gradientAngle = 0,
        midColor  = { 1.0, 0.85, 0.2 },
        lowColor  = { 1.0, 0.25, 0.25 },
        trackColor = { 1, 1, 1 },     -- the empty track
        trackAlpha = 0.12,
        roundStart = false,           -- a round cap on the arc's start
        roundEnd   = false,           -- a round cap riding the leading edge
        -- MODE (2026-09-21): "arc" is everything above; "bar" is a straight
        -- StatusBar masked to a silhouette from the Hub's shape catalog — the
        -- engine sizes the fill from the secret itself (no curves, no chunks)
        -- and a real absorb overlay is possible. The colour settings above
        -- serve both modes; `bar` holds only what a bar adds.
        mode = "arc",
        -- LAYERING per display (2026-09-21): nil = the unit's strata / the
        -- automatic band (16 levels per ring in GU.RINGS order). Set, they
        -- are absolute, so a display can sit between two Overlays graphics —
        -- the same two numbers Gloom's Overlays gives each of its own.
        strata = nil, level = nil,
        -- OUTLINE, in either mode (the owner, 2026-09-21: it is a property of
        -- the display, not of the bar). A bar wears the shape's rim art at
        -- one of three widths (thin / medium / thick, three files per shape;
        -- a rectangle draws four edges); an arc draws a slightly larger arc
        -- in the outline colour under its track — outer edge, inner edge and
        -- both ends — following the geometry, never the value.
        outline = false, outlineWidth = "medium",
        outlineColor = { 0.58, 0.42, 1.0 }, outlineAlpha = 1,
        bar = {
            shape    = "orb",         -- a key of the Hub's BAR-shape family, or "rect" for a free rectangle
            size     = 120,           -- the silhouette's SHORT side, px; the long side follows its aspect
            -- shapeW / shapeH (2026-09-27, the owner): the shape's own WIDTH and
            -- HEIGHT, px, set apart — it stretches. nil = `size` at the art's
            -- proportions. For a nested SET they are the SET's box, so members
            -- wearing the same numbers still nest. shapeLink: keep proportions.
            width    = 200, height = 24,   -- "rect" only
            rotation = 0,             -- degrees, counter-clockwise; the fill stays screen-axis
            flipH    = false, flipV = false,
            fillDir  = "up",          -- "up" | "down" | "left" | "right"
            -- the absorb, EUI-style: from the FULL end back over the fill,
            -- present at full health too
            absorb   = true, absorbColor = { 1, 1, 1 }, absorbAlpha = 0.6,
            -- the bar's OWN offset from the unit's centre — the owner, 2026-09-21:
            -- an arc and a bar never want the same spot, so `dx` / `dy` above
            -- stay the arc's
            dx = 0, dy = 0,
        },
    }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
end

-- The class-resource ring: N segments, one per point (soul shards, combo
-- points, holy power, chi, arcane charges, essence). Player only.
local function ResourceDefaults()
    return RingDefaults({
        size = 160, thickness = 14, start = 180, span = 180, clockwise = true,
        gap = 4,                      -- degrees between segments
        -- bar mode: the points in a ROW, `rowDir` from the first, `rowGap` px apart
        rowDir = "right", rowGap = 4,
        color = { 0.58, 0.42, 1.0 },
        resourceColor = true,         -- the game's colour for that resource
        -- At `breakAt` points or more, every segment turns `breakColor`.
        breakEnabled = false, breakAt = 5, breakColor = { 0.2, 1.0, 0.4 },
    })
end

local function UnitDefaults(x, y)
    return {
        x = x, y = y,
        strata = "MEDIUM",
        level = 10,
        showCondition = "always",  -- "always"|"combat"|"target"|"combat_or_target"|"never"
        font = nil,                -- the unit's DEFAULT text font (an LSM name); a text
                                   -- piece with no font of its own uses it; nil = Khand
        rings = {
            -- classColor: a player's class colour / an NPC's reaction colour
            -- stands in for `color` in SOLID mode (the shift layers still
            -- apply on top). A gradient wins over it.
            -- shieldTint: while the unit has an absorb, the fill takes
            -- shieldColor at shieldAlpha (a gated copy of the arc — see Refresh).
            health = RingDefaults({ classColor = true,
                                    shieldTint = false, shieldColor = { 0.45, 0.85, 1.0 }, shieldAlpha = 0.8,
                                    -- shieldAuto: the wash runs along the arc's chord, its fade as
                                    -- wide as the chord; off = shieldAngle / shieldWidth by hand
                                    shieldAuto = true, shieldAngle = 180, shieldWidth = 70 }),
            power  = RingDefaults({ clockwise = false, color = { 0.58, 0.42, 1.0 }, powerColor = true }),
            -- The cast ring shows only while the unit casts or channels. A
            -- channel DRAINS (its arc shrinks) when `channelDrains` is on.
            cast   = RingDefaults({ size = 250, thickness = 8, start = 90, span = 360, clockwise = true,
                                    color = { 1.0, 0.55, 0.1 }, color2 = { 1.0, 0.2, 0.4 },
                                    trackAlpha = 0.08, channelDrains = true,
                                    -- target only: colour by interrupt state — the ring's own colour
                                    -- while you can interrupt, these two otherwise
                                    kickAware = true,
                                    kickCDColor = { 0.85, 0.45, 0.1 },
                                    lockedColor = { 0.55, 0.55, 0.55 },
                                    -- kick on cooldown but back BEFORE the cast ends: a tint, and a
                                    -- tick on the arc where it returns
                                    midCastEnabled = true, midCastColor = { 0.32, 0.82, 0.36 },
                                    kickTick = true, kickTickColor = { 1, 1, 1 } }),
        },
        -- texts: the list of text pieces (GloomsUnitFrames_Text.lua). Not a
        -- default here on purpose: an empty list must STAY empty across
        -- logins, so EnsureTexts seeds it only when the key is absent.
    }
end

-- A PROFILE is the whole tool's config: both units. GloomsUnitFramesDB holds a
-- library of them, shared account-wide, and a per-character binding to one
-- (GB's shape; the owner, 2026-09-20: "a profile-based system, like it is for
-- literally every other module in this suite"):
--   GloomsUnitFramesDB = { _version = 2,
--                          profiles     = { [name] = { player = {…}, target = {…} } },
--                          charProfiles = { ["Name-Realm"] = name } }
-- The engine's `db` below is the ACTIVE profile's table, so every db[which]
-- read is unchanged; switching swaps `db` and re-applies both units.
local DB_VERSION = 2
local DEFAULTS = {
    player = UnitDefaults(-300, -150),
    target = UnitDefaults( 300, -150),
}
DEFAULTS.player.rings.resource = ResourceDefaults()

GU.UNITS = { "player", "target" }
GU.RINGS = { "health", "power", "resource", "cast" }   -- draw order; a unit may lack some
GU.MAX_SEGMENTS = 7

-- Which secondary power a class shows. The max (UnitPowerMax) decides whether
-- it applies right now — 0 means "not for this spec/form" and the ring hides.
local CLASS_RESOURCE = {
    WARLOCK     = { type = Enum.PowerType.SoulShards,    token = "SOUL_SHARDS" },
    ROGUE       = { type = Enum.PowerType.ComboPoints,   token = "COMBO_POINTS" },
    DRUID       = { type = Enum.PowerType.ComboPoints,   token = "COMBO_POINTS" },
    PALADIN     = { type = Enum.PowerType.HolyPower,     token = "HOLY_POWER" },
    MONK        = { type = Enum.PowerType.Chi,           token = "CHI" },
    MAGE        = { type = Enum.PowerType.ArcaneCharges, token = "ARCANE_CHARGES" },
    EVOKER      = { type = Enum.PowerType.Essence,       token = "ESSENCE" },
    -- Runes ARE a power type: UnitPower counts the READY runes (max 6), so the
    -- segments fill by count like every other resource — a recharging rune is
    -- simply "not ready yet". Added 2026-09-20 for the owner's partner's DK.
    DEATHKNIGHT = { type = Enum.PowerType.Runes,         token = "RUNES" },
}

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local root        = nil   -- GloomsUnitFramesDB
local db          = nil   -- the ACTIVE profile: { player = cfg, target = cfg }
local initialised = false
local frames      = {}   -- per unit: the ring frame
local anchors     = {}   -- per unit: the draggable anchor (tab open only)
local ghosts      = {}   -- per unit: outline shown while the tab edits it
local editing     = nil
local listeners   = {}
local Skin        -- LibGloomSkin, resolved lazily (fonts for the centre text)

local UpdateVisibility

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function ApplyDefaults(tbl, defaults)
    for k, v in pairs(defaults) do
        if tbl[k] == nil then
            tbl[k] = (type(v) == "table") and {} or v
            if type(v) == "table" then ApplyDefaults(tbl[k], v) end
        elseif type(v) == "table" and type(tbl[k]) == "table" then
            ApplyDefaults(tbl[k], v)
        end
    end
end

-- Seed a unit's text list on first sight (and migrate the old single
-- "center text"), then fill each piece's newer fields from TEXT_DEFAULTS.
local function EnsureTexts(cfg)
    if cfg.texts == nil then
        local old = cfg.text
        cfg.texts = { { template = "[hp:pct]", size = old and old.size or 22,
                        enabled = not (old and old.enabled == false) } }
    end
    cfg.text = nil
    for _, tc in ipairs(cfg.texts) do
        ApplyDefaults(tc, GU.TEXT_DEFAULTS)
        -- same-day migration: ring bands grew from 8 to 16 levels, so the old
        -- text default (40, above everything) now sits under the cast ring
        if tc.level == 40 and not tc.lv16 then tc.level = 70 end
        tc.lv16 = true
    end
end

-- Seed a unit's aura groups on first sight; fill newer fields from AURA_DEFAULTS.
local function EnsureAuras(cfg, which)
    if cfg.auras == nil then
        cfg.auras = { { kind = (which == "target") and "mydebuffs" or "buffs", x = -110, y = 118 } }
    end
    -- The "This spell" kind was removed 2026-09-20 (GloomsUnitFrames_Auras.lua,
    -- AURA_KINDS); a saved group of that kind is dropped rather than migrated —
    -- nothing else can do what it claimed to.
    for i = #cfg.auras, 1, -1 do
        if cfg.auras[i].kind == "spell" then table.remove(cfg.auras, i) end
    end
    for _, ac in ipairs(cfg.auras) do ApplyDefaults(ac, GU.AURA_DEFAULTS); GU:MigrateAuraGroup(ac) end
end

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

local function Chat(msg) print("|cff936bffGloom's Unit Frames:|r " .. msg) end

------------------------------------------------------------------------
-- The arc.
-- Half-plane H(a) shows angles [a, a+π]; the wide one H'(a) = [a−D, a+π+D].
-- For a fill of θ radians from start S, chunk k shows φ = clamp(θ−kπ, 0, π):
--   counter-clockwise: wedge [S+kπ, S+kπ+φ]  fixed H'(S+kπ)     rot H(S+kπ−π+φ)
--   clockwise:         wedge [S−kπ−φ, S−kπ]  fixed H'(S−kπ−π)   rot H(S−kπ−φ)
-- rot = base ± φ is what the rotation curve produces from the secret percent,
-- with `base` folded into its y values (Lua cannot add to the result).
-- Where two chunks meet, the seam is about ALPHA. Two anti-aliased edges on
-- one line each draw at 50% — and 50% over 50% is 75%, not 100%. On the
-- OPAQUE fill that is a visible bleed, so a fill chunk that follows another
-- OVERLAPS it: its fixed mask starts D before the boundary (hard-edged, so
-- the two-layer residual a soft edge leaves over solid colour never shows)
-- and opaque over opaque hides both edges. On the TRANSLUCENT track an
-- overlap would double the alpha, so track chunks are NUDGED to start
-- exactly on the boundary, where 75% of 12% is invisible. The first chunk
-- of a partial arc is nudged too (an exact start); a full ring's is not.
-- NO mask overshoots its FAR end: an empty chunk must be empty by geometry
-- (a hairline where the two masks meet), because a secret alpha of ZERO is
-- not honoured by the engine — measured 2026-09-19 — and the gate below can
-- only dim, never hide.
local D = math.rad(1.5)          -- the wide mask's overshoot per side (matches the art)
local LAYERS = { "base", "grad", "mid", "low" }

-- Alpha PROFILES over the whole value (0..1): what each layer wants to be
-- when its chunk is visible at all. Base is always on; mid is fully in by
-- 50%; low fades in below 50%. Blended in that order that gives EXACTLY the
-- mid colour at 50% and mid/low at 25%.
-- ★ OFF is ALPHA_OFF, never 0: the engine ignores a SECRET alpha of exactly
-- zero (measured 2026-09-19 — the layer keeps its last opacity), and 0.4% is
-- invisible. An arc may override a layer's profile (arc.profiles[name]).
local ALPHA_OFF = 0.004
local PROFILE = {
    base = { { 0, 1 }, { 1, 1 } },
    grad = { { 0, 1 }, { 1, 1 } },
    mid  = { { 0, 1 }, { 0.5, 1 }, { 1, ALPHA_OFF } },
    low  = { { 0, 1 }, { 0.5, ALPHA_OFF }, { 1, ALPHA_OFF } },
}

-- Piecewise-linear evaluation in Lua, for PLAIN values (the track, the
-- empty state). Mirrors what the engine does with the same points.
local function Eval(pts, x)
    if x <= pts[1][1] then return pts[1][2] end
    for i = 2, #pts do
        local a, b = pts[i - 1], pts[i]
        if x <= b[1] then
            local t = (b[1] == a[1]) and 1 or (x - a[1]) / (b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t
        end
    end
    return pts[#pts][2]
end

local function CurveFrom(pts)
    local c = C_CurveUtil.CreateCurve()
    c:SetType(Enum.LuaCurveType.Linear)
    for _, pt in ipairs(pts) do c:AddPoint(pt[1], pt[2]) end
    return c
end

-- A profile gated to 0 below `xg` (with a 0.002 ramp), as a point list.
local function Gated(profile, xg)
    local pts = { { 0, ALPHA_OFF } }
    if xg > 0 then pts[#pts + 1] = { xg, ALPHA_OFF } end
    local xr = math.min(xg + 0.002, 1)
    pts[#pts + 1] = { xr, Eval(profile, xr) }
    for _, pt in ipairs(profile) do
        if pt[1] > xr then pts[#pts + 1] = pt end
    end
    return pts
end

-- Each chunk is its own child FRAME, one level above the previous chunk:
-- where two chunks overlap, every layer of chunk 2 must draw over every
-- layer of chunk 1, and ARTWORK sublevels turned out not to guarantee that
-- across textures carrying different masks (the boundary spoke showed chunk
-- 1's ramp landing on chunk 2's base). Frame level is absolute. The chunk
-- owns its three masks; the hole is sized in Configure.
local function NewChunk(holder, levelUp, withLayers)
    local ch = { layers = {} }
    local fr = CreateFrame("Frame", nil, holder)
    fr:SetAllPoints(holder)
    fr:SetFrameLevel(holder:GetFrameLevel() + levelUp)
    ch.frame, ch.levelUp = fr, levelUp
    ch.fixed = fr:CreateMaskTexture()
    -- (the image is chosen per direction in ConfigureChunk)
    ch.fixed:SetPoint("CENTER", fr, "CENTER")
    ch.rot = fr:CreateMaskTexture()
    ch.rot:SetPoint("CENTER", fr, "CENTER")
    ch.hole = fr:CreateMaskTexture()
    ch.hole:SetTexture(MASK_HOLE, "CLAMP", "CLAMP")   -- CLAMP: opaque forever outward
    for i, name in ipairs(withLayers and LAYERS or { "base" }) do
        local tex = fr:CreateTexture(nil, "ARTWORK", nil, i - 1)
        tex:SetAllPoints(fr)
        tex:AddMaskTexture(ch.fixed)
        tex:AddMaskTexture(ch.rot)
        tex:AddMaskTexture(ch.hole)
        ch.layers[name] = tex
    end
    return ch
end

-- Point the chunk at its slice of the arc. Everything here is a PLAIN number.
-- `lo, hi`: the slice of the 0..1 value this arc answers to (a resource
-- segment owns one point's worth); the whole arc is {0, 1}.
-- `off` (radians) is how far the drawn arc's start sits past the nominal
-- start (a round start cap pulls it in); `spanFull` is the nominal span the
-- VALUE maps onto, while `span` is what is actually drawn.
local function ConfigureChunk(ch, S, sgn, k, span, diameter, inner, nudge, lo, hi, profiles, off, spanFull)
    ch.frame:SetFrameLevel(ch.frame:GetParent():GetFrameLevel() + ch.levelUp)
    ch.fixed:SetSize(diameter * 1.5, diameter * 1.5)
    ch.rot:SetSize(diameter * 1.5, diameter * 1.5)
    -- Thickness ≥ half the size is a solid disc: park the hole off to the
    -- side, where its CLAMP edge (opaque) is all the art can see. A
    -- zero-size mask would hide everything instead.
    ch.hole:ClearAllPoints()
    if inner >= 2 then
        ch.hole:SetSize(inner * HOLE_SCALE, inner * HOLE_SCALE)
        ch.hole:SetPoint("CENTER", ch.frame, "CENTER")
    else
        ch.hole:SetSize(8, 8)
        ch.hole:SetPoint("CENTER", ch.frame, "CENTER", diameter, 0)
    end
    local fixedAngle
    if sgn > 0 then fixedAngle, ch.base = S + k * PI, S + k * PI - PI
    else            fixedAngle, ch.base = S - k * PI - PI, S - k * PI end
    ch.fixed:SetRotation(fixedAngle)
    -- Nudged: an exact half-turn whose START edge is a visible end of the arc
    -- and must be soft — the half-hard images serve, aimed so their soft half
    -- is the start (CCW starts on the angle-0 side, CW on the angle-π side).
    -- Not nudged: the lead mask — exact plus D back over the previous chunk,
    -- hard, because a soft edge drawn in two layers (base + ramp) leaves a
    -- residual of the base colour along it, a line over solid colour.
    if nudge then ch.fixed:SetTexture(sgn > 0 and MASK_ROT.cw or MASK_ROT.ccw, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    else ch.fixed:SetTexture(sgn > 0 and MASK_LEAD.ccw or MASK_LEAD.cw, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST") end
    local over = D   -- only the start-side overlap remains; it lies over the previous chunk
    -- NEAREST keeps the trailing edge truly hard; the leading edge's
    -- anti-aliasing is baked into the (1024px) image, so it stays soft.
    ch.rot:SetTexture(sgn > 0 and MASK_ROT.ccw or MASK_ROT.cw, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    ch.sgn = sgn
    lo, hi = lo or 0, hi or 1
    off, spanFull = off or 0, spanFull or span
    local w = hi - lo
    local function xAt(angle) return lo + (angle / spanFull) * w end   -- value at which the arc reaches `angle` past the nominal start
    local x0, x1 = xAt(off + k * PI), xAt(off + (k + 1) * PI)
    -- Clamped to this chunk's half-turn AND to the arc's own span: a windowed
    -- arc (a resource segment) sees values past its window and must stop.
    local cap = math.min(PI, span - k * PI)
    local function y(x) return ch.base + sgn * clamp(((x - lo) / w) * spanFull - off - k * PI, 0, cap) end
    ch.y = y
    -- Breakpoints of the piecewise-linear angle, in value units.
    local xs = { 0, lo, x0, math.min(x1, 1), math.min(xAt(off + span), 1), hi, 1 }
    table.sort(xs)
    local rot, last = {}, nil
    for _, x in ipairs(xs) do
        if x ~= last then rot[#rot + 1] = { x, y(x) }; last = x end
    end
    ch.rotPts, ch.rotCurve = rot, CurveFrom(rot)
    -- Gate: dims the chunk until φ clears its start (the engine will not
    -- honour a secret alpha of exactly zero, so this softens rather than hides).
    local xg = x0 + ((over * 0.5) / span) * w
    ch.alphaPts, ch.alphaCurve = {}, {}
    for name in pairs(ch.layers) do
        ch.alphaPts[name] = Gated(profiles and profiles[name] or PROFILE[name], xg)
        ch.alphaCurve[name] = CurveFrom(ch.alphaPts[name])
    end
end

-- One arc = up to two chunks (span ≤ 360°), created once, reconfigured freely.
-- `hole` is the ring's shared inner mask. `withLayers` adds the mid/low
-- shift layers (the fill has them; the track does not).
-- The CAP: a hard 3° wedge over a full ring's closing point, on top of both
-- chunks, fading in above ~99.6% — where chunk 2's soft leading edge comes
-- to rest over chunk 1's start and would otherwise leave a residual line.
local function NewCap(holder, levelUp)
    local cap = { layers = {}, levelUp = levelUp }
    local fr = CreateFrame("Frame", nil, holder)
    fr:SetAllPoints(holder)
    cap.frame = fr
    cap.mask = fr:CreateMaskTexture()
    cap.mask:SetTexture(MASK_CAP, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    cap.mask:SetPoint("CENTER", fr, "CENTER")
    cap.hole = fr:CreateMaskTexture()
    cap.hole:SetTexture(MASK_HOLE, "CLAMP", "CLAMP")
    for i, name in ipairs(LAYERS) do
        local tex = fr:CreateTexture(nil, "ARTWORK", nil, i - 1)
        tex:SetAllPoints(fr)
        tex:AddMaskTexture(cap.mask)
        tex:AddMaskTexture(cap.hole)
        cap.layers[name] = tex
    end
    return cap
end

local function ConfigureCap(cap, S, span, diameter, inner)
    cap.frame:SetFrameLevel(cap.frame:GetParent():GetFrameLevel() + cap.levelUp)
    cap.mask:SetSize(diameter * 1.5, diameter * 1.5)
    cap.mask:SetRotation(S)
    cap.hole:ClearAllPoints()
    if inner >= 2 then
        cap.hole:SetSize(inner * HOLE_SCALE, inner * HOLE_SCALE)
        cap.hole:SetPoint("CENTER", cap.frame, "CENTER")
    else
        cap.hole:SetSize(8, 8)
        cap.hole:SetPoint("CENTER", cap.frame, "CENTER", diameter, 0)
    end
    local xg = 1 - D / span
    cap.alphaPts, cap.alphaCurve = {}, {}
    for name in pairs(cap.layers) do
        cap.alphaPts[name] = Gated(PROFILE[name], xg)
        cap.alphaCurve[name] = CurveFrom(cap.alphaPts[name])
    end
end

-- ROUND ENDS. The START cap is static: a disc the ring's thickness at the
-- start point (its own small textures; base colour pre-blended for a
-- gradient). The END cap rides the leading edge: ring-sized layers seen
-- through a disc MASK that pivots about the ring's centre by the sweep
-- angle. The track's caps are single discs cut to the half BEYOND the arc's
-- end by a half-plane mask, so a translucent cap never doubles the track.
local function NewRoundCaps(holder, levelUp, withLayers)
    local fr = CreateFrame("Frame", nil, holder)
    fr:SetAllPoints(holder)
    local caps = { frame = fr, levelUp = levelUp }
    -- Both caps are cut from ring-sized copies of the layers by a disc mask
    -- AND the ring's hole, so a cap is exactly "the band, where the disc is"
    -- — the same edges as the arc, never a separate shape that could bulge.
    -- The track's caps add a half-plane mask keeping only the half beyond
    -- the arc's end, so a translucent cap never doubles the track.
    caps.hole = fr:CreateMaskTexture()
    caps.hole:SetTexture(MASK_HOLE, "CLAMP", "CLAMP")
    local function piece(rotates)
        local pc = { layers = {} }
        pc.mask = fr:CreateMaskTexture()
        pc.mask:SetTexture(ART .. "disc.png", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        if not withLayers then
            pc.half = fr:CreateMaskTexture()
            pc.half:SetTexture(MASK_ROT.ccw, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
        end
        for i, name in ipairs(withLayers and LAYERS or { "base" }) do
            local t = fr:CreateTexture(nil, "ARTWORK", nil, i - 1)
            t:SetAllPoints(fr)
            t:AddMaskTexture(pc.mask)
            t:AddMaskTexture(caps.hole)
            if pc.half then t:AddMaskTexture(pc.half) end
            pc.layers[name] = t
        end
        return pc
    end
    caps.startCap, caps.endCap = piece(false), piece(true)
    return caps
end

-- Frame levels above the holder: track chunks +1/+2 (caps +0), fill chunks
-- +3/+4, the fill's closing cap +5, its round ends +6.
local function NewArc(holder, withLayers)
    local up = withLayers and 3 or 1
    local arc = { chunks = { NewChunk(holder, up, withLayers), NewChunk(holder, up + 1, withLayers) },
                  n = 0, shown = false, shift = false, gradient = false, translucent = not withLayers,
                  capOn = false, roundStart = false, roundEnd = false }
    if withLayers then arc.cap = NewCap(holder, up + 2) end
    arc.round = NewRoundCaps(holder, withLayers and 6 or 0, withLayers)
    -- Every piece that carries layers: the chunks, the closing cap, the round ends.
    function arc:Pieces()
        local t = { self.chunks[1], self.chunks[2] }
        if self.cap then t[#t + 1] = self.cap end
        t[#t + 1] = self.round.startCap
        t[#t + 1] = self.round.endCap
        return t
    end

    -- g: { start, span, clockwise, size, inner, thickness, art, ramp, lo, hi, roundStart, roundEnd }
    function arc:Configure(g)
        local startDeg, spanDeg, clockwise, diameter, inner, path, rampPath, lo, hi =
            g.start, g.span, g.clockwise, g.size, g.inner, g.art, g.ramp, g.lo, g.hi
        spanDeg = clamp(spanDeg, 1, 360)
        local S0, spanFull, sgn = math.rad(startDeg), math.rad(spanDeg), clockwise and -1 or 1
        self.roundStart, self.roundEnd = g.roundStart and true or false, g.roundEnd and true or false
        -- The band the art really draws: outer edge from the disc art's radius,
        -- inner edge from the hole. A round cap is a disc that fills it exactly,
        -- and the arc is pulled in by half a cap so the cap's far edge lands
        -- where the flat end would have been.
        local outerR = ART_R * diameter / 2
        local innerR = math.max(0, inner) / 2
        local capD = math.max(2, outerR - innerR)
        local rMid = (outerR + innerR) / 2
        local delta = (capD / 2) / math.max(rMid, 1)
        local offS = self.roundStart and delta or 0
        local offE = self.roundEnd and delta or 0
        local S = S0 + sgn * offS
        local span = math.max(0.01, spanFull - offS - offE)
        self.n = span > PI and 2 or 1
        self.geo = { S = S, S0 = S0, span = span, spanFull = spanFull, off = offS, sgn = sgn, size = diameter,
                     inner = inner, capD = capD, rMid = rMid, lo = lo or 0, hi = hi or 1 }
        for k = 0, 1 do
            local ch = self.chunks[k + 1]
            for name, tex in pairs(ch.layers) do tex:SetTexture(name == "grad" and rampPath or path) end
            if k < self.n then
                -- track: exact everywhere · fill: exact start only (see above)
                local nudge = self.translucent or (k == 0 and spanDeg < 360)
                ConfigureChunk(ch, S, sgn, k, span, diameter, inner, nudge, lo, hi, self.profiles, offS, spanFull)
            end
        end
        self.capOn = (self.cap ~= nil) and spanDeg >= 360 and not (self.roundStart or self.roundEnd)
        if self.cap then
            for name, tex in pairs(self.cap.layers) do tex:SetTexture(name == "grad" and rampPath or path) end
            if self.capOn then ConfigureCap(self.cap, S, span, diameter, inner) end
        end
        self:ConfigureRound(rampPath, path)
        self:Apply()
    end

    -- The round ends' geometry and curves.
    function arc:ConfigureRound(rampPath, path)
        local geo, rd = self.geo, self.round
        rd.frame:SetFrameLevel(rd.frame:GetParent():GetFrameLevel() + rd.levelUp)
        local r, S, sgn, span, spanFull, off = geo.rMid, geo.S, geo.sgn, geo.span, geo.spanFull, geo.off
        local t = geo.capD / ART_R          -- mask size that cuts a disc of exactly capD
        local sx, sy = r * math.cos(S), r * math.sin(S)
        local E = S + sgn * span
        local ex, ey = r * math.cos(E), r * math.sin(E)
        local w = geo.hi - geo.lo
        -- the hole, as on the chunks
        rd.hole:ClearAllPoints()
        if geo.inner >= 2 then
            rd.hole:SetSize(geo.inner * HOLE_SCALE, geo.inner * HOLE_SCALE)
            rd.hole:SetPoint("CENTER", rd.frame, "CENTER")
        else
            rd.hole:SetSize(8, 8)
            rd.hole:SetPoint("CENTER", rd.frame, "CENTER", geo.size, 0)
        end
        for _, pc in ipairs({ rd.startCap, rd.endCap }) do
            for name, tex in pairs(pc.layers) do tex:SetTexture(name == "grad" and rampPath or path) end
            pc.mask:SetSize(t, t)
        end
        -- start cap: static at the drawn start
        local sc = rd.startCap
        sc.mask:ClearAllPoints(); sc.mask:SetPoint("CENTER", rd.frame, "CENTER", sx, sy)
        sc.mask:SetRotation(0)
        if sc.half then
            sc.half:SetSize(t * 1.5, t * 1.5); sc.half:ClearAllPoints()
            sc.half:SetPoint("CENTER", rd.frame, "CENTER", sx, sy)
            sc.half:SetRotation(sgn > 0 and (S - PI) or S)   -- the half BEYOND the start
        end
        -- end cap
        local ec = rd.endCap
        ec.mask:ClearAllPoints()
        if ec.half then
            -- the track's: static at the drawn end, the half beyond it
            ec.mask:SetPoint("CENTER", rd.frame, "CENTER", ex, ey); ec.mask:SetRotation(0)
            ec.half:SetSize(t * 1.5, t * 1.5); ec.half:ClearAllPoints()
            ec.half:SetPoint("CENTER", rd.frame, "CENTER", ex, ey)
            ec.half:SetRotation(sgn > 0 and E or (E - PI))
            ec.rotPts, ec.rotCurve, ec.pivot = nil, nil, nil
        else
            -- the fill's: parked at the start, pivoting about the ring's centre
            ec.mask:SetPoint("CENTER", rd.frame, "CENTER", sx, sy)
            ec.pivot = CreateVector2D(0.5 - sx / t, 0.5 - sy / t)
            local function ya(x) return sgn * clamp(((x - geo.lo) / w) * spanFull - off, 0, span) end
            local xs = { 0, geo.lo, geo.lo + (off / spanFull) * w, geo.lo + ((off + span) / spanFull) * w, geo.hi, 1 }
            table.sort(xs)
            local pts, last = {}, nil
            for _, x in ipairs(xs) do
                if x ~= last then pts[#pts + 1] = { x, ya(x) }; last = x end
            end
            ec.rotPts, ec.rotCurve = pts, CurveFrom(pts)
        end
        -- alpha: both caps follow the arc's first chunk (hidden while empty)
        local xg = geo.lo + ((D * 0.5) / spanFull) * w
        for _, piece in ipairs({ sc, ec }) do
            piece.alphaPts, piece.alphaCurve = {}, {}
            for name in pairs(piece.layers) do
                piece.alphaPts[name] = Gated(self.profiles and self.profiles[name] or PROFILE[name], xg)
                piece.alphaCurve[name] = CurveFrom(piece.alphaPts[name])
            end
        end
    end

    -- Which textures are on at all: chunks the span uses; the closing cap and
    -- the round ends when on; the ramp only in gradient mode; mid/low only
    -- when shifting.
    function arc:Apply()
        -- rampOnly: the ramp layer alone, no base under it — a colour fading
        -- to TRANSPARENT along the gradient angle (the shield wash).
        local function want(name)
            return (name == "base" and not self.rampOnly) or (name == "grad" and self.gradient)
                or ((name == "mid" or name == "low") and self.shift)
        end
        for k, ch in ipairs(self.chunks) do
            local on = self.shown and k <= self.n
            for name, tex in pairs(ch.layers) do tex:SetShown(on and want(name)) end
        end
        if self.cap then
            for name, tex in pairs(self.cap.layers) do tex:SetShown(self.shown and self.capOn and want(name)) end
        end
        for name, tex in pairs(self.round.startCap.layers) do tex:SetShown(self.shown and self.roundStart and want(name)) end
        for name, tex in pairs(self.round.endCap.layers) do tex:SetShown(self.shown and self.roundEnd and want(name)) end
    end
    function arc:SetShown(on) self.shown = on; self:Apply() end
    function arc:SetShift(on) self.shift = on; self:Apply() end

    -- fn(texture, piece): the piece carries its own alpha gate (piece.alphaPts).
    function arc:Layer(name, fn)
        for _, ch in ipairs(self:Pieces()) do local t = ch.layers[name]; if t then fn(t, ch) end end
    end

    -- Uniform colour on a layer. ★ Colour ONLY — no alpha argument: passing
    -- SetVertexColor a 4th value of 1 landed as the layer's OPACITY on 12.1
    -- (measured 2026-09-20: the cast ring's per-tick recolour lifted the
    -- empty second chunk's base to alpha 1 and drew its 1.5° lead overlap as
    -- a slice at the boundary, while the gate still held every other layer).
    function arc:SetColor(name, r, g, b)
        self:Layer(name, function(t) t:SetVertexColor(r, g, b) end)
    end

    -- The base: one colour, or colour → colour2 along `angleDeg` (0 = left
    -- to right) via the ramp layer, which is rotated to aim it.
    function arc:SetSolid(c)
        self.gradient = false
        self:SetColor("base", c[1], c[2], c[3])
        self:Apply()
    end

    function arc:SetGradient(c1, c2, angleDeg)
        self.gradient = true
        self:SetColor("base", c1[1], c1[2], c1[3])
        local a = math.rad(angleDeg or 0)
        local cs, sn = math.cos(a), math.sin(a)
        local function uv(u, v)   -- rotate (u,v) about the centre; +angle turns the ramp counter-clockwise
            local du, dv = u - 0.5, v - 0.5
            return 0.5 + du * cs - dv * sn, 0.5 + du * sn + dv * cs
        end
        local ulx, uly = uv(0, 0)
        local llx, lly = uv(0, 1)
        local urx, ury = uv(1, 0)
        local lrx, lry = uv(1, 1)
        self:Layer("grad", function(t)
            t:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
            t:SetVertexColor(c2[1], c2[2], c2[3], 1)
        end)
        self:Apply()
    end

    -- Drive from a unit: the engine evaluates every curve on the secret.
    -- `power` (a power type) selects UnitPowerPercent; nil means health.
    local function P(unit, power, curve)
        if power ~= nil then return UnitPowerPercent(unit, power, true, curve) end
        return UnitHealthPercent(unit, true, curve)
    end
    -- ★ Every driver returns early on an arc that was never Configured: the
    -- health ring's shield copy exists from creation but is only configured
    -- while "Tint while shielded" is on, and Refresh empties every arc when
    -- the unit does not exist (41× "alphaPts nil", 2026-09-20).
    function arc:SetFromUnit(unit, power)
        if not self.geo then return end
        for k = 1, self.n do
            local ch = self.chunks[k]
            ch.rot:SetRotation(P(unit, power, ch.rotCurve))
            for name, tex in pairs(ch.layers) do
                if tex:IsShown() then tex:SetAlpha(P(unit, power, ch.alphaCurve[name])) end
            end
        end
        if self.capOn then
            for name, tex in pairs(self.cap.layers) do
                if tex:IsShown() then tex:SetAlpha(P(unit, power, self.cap.alphaCurve[name])) end
            end
        end
        local rd = self.round
        if self.roundStart then
            for name, tex in pairs(rd.startCap.layers) do
                if tex:IsShown() then tex:SetAlpha(P(unit, power, rd.startCap.alphaCurve[name])) end
            end
        end
        if self.roundEnd then
            if rd.endCap.rotCurve then rd.endCap.mask:SetRotation(P(unit, power, rd.endCap.rotCurve), rd.endCap.pivot) end
            for name, tex in pairs(rd.endCap.layers) do
                if tex:IsShown() then tex:SetAlpha(P(unit, power, rd.endCap.alphaCurve[name])) end
            end
        end
    end

    -- Drive from a DURATION OBJECT (a target's cast on a restricted map: start,
    -- end AND total all secret — measured in a delve 2026-09-20). The object
    -- evaluates a curve over its own 0..1 FRACTION engine-side —
    -- EvaluateElapsedPercent for a cast that fills, EvaluateRemainingPercent
    -- for a channel that drains — so the very curves SetFromUnit hands to
    -- UnitHealthPercent serve unchanged, and no total is ever needed. (OPie's
    -- cooldown spiral uses the same door; EUI's bar gets it for free through
    -- StatusBar:SetTimerDuration, which a masked arc cannot use.)
    -- ★ A rotation evaluation takes NO second argument: the evaluators'
    -- optional "modifier" is validated to 0..1 (an alpha default passes; an
    -- angle in radians is refused — "bad argument #3", 2026-09-20).
    function arc:SetFromDuration(d, drains)
        if not self.geo then return end
        local m = drains and d.EvaluateRemainingPercent or d.EvaluateElapsedPercent
        local function D(curve, default) return m(d, curve, default) end
        for k = 1, self.n do
            local ch = self.chunks[k]
            ch.rot:SetRotation(m(d, ch.rotCurve))
            for name, tex in pairs(ch.layers) do
                if tex:IsShown() then tex:SetAlpha(D(ch.alphaCurve[name], ALPHA_OFF)) end
            end
        end
        if self.capOn then
            for name, tex in pairs(self.cap.layers) do
                if tex:IsShown() then tex:SetAlpha(D(self.cap.alphaCurve[name], ALPHA_OFF)) end
            end
        end
        local rd = self.round
        if self.roundStart then
            for name, tex in pairs(rd.startCap.layers) do
                if tex:IsShown() then tex:SetAlpha(D(rd.startCap.alphaCurve[name], ALPHA_OFF)) end
            end
        end
        if self.roundEnd then
            if rd.endCap.rotCurve then rd.endCap.mask:SetRotation(m(d, rd.endCap.rotCurve), rd.endCap.pivot) end
            for name, tex in pairs(rd.endCap.layers) do
                if tex:IsShown() then tex:SetAlpha(D(rd.endCap.alphaCurve[name], ALPHA_OFF)) end
            end
        end
    end

    -- Drive from a plain 0..1 (the track, and the no-unit state).
    function arc:SetFromPlain(pct, alphaScale)
        if not self.geo then return end
        pct = clamp(pct, 0, 1)
        for k = 1, self.n do
            local ch = self.chunks[k]
            ch.rot:SetRotation(Eval(ch.rotPts, pct))
            for name, tex in pairs(ch.layers) do
                tex:SetAlpha(Eval(ch.alphaPts[name], pct) * (alphaScale or 1))
            end
        end
        if self.capOn then
            for name, tex in pairs(self.cap.layers) do
                tex:SetAlpha(Eval(self.cap.alphaPts[name], pct) * (alphaScale or 1))
            end
        end
        local rd = self.round
        for name, tex in pairs(rd.startCap.layers) do
            tex:SetAlpha(Eval(rd.startCap.alphaPts[name], pct) * (alphaScale or 1))
        end
        if rd.endCap.rotPts then rd.endCap.mask:SetRotation(Eval(rd.endCap.rotPts, pct), rd.endCap.pivot) end
        for name, tex in pairs(rd.endCap.layers) do
            tex:SetAlpha(Eval(rd.endCap.alphaPts[name], pct) * (alphaScale or 1))
        end
    end
    return arc
end

------------------------------------------------------------------------
-- Color. A ring is either a flat color, the unit's power-type color, or a
-- health-driven blend (a color curve the engine evaluates on the secret).
------------------------------------------------------------------------
------------------------------------------------------------------------
-- The BAR (2026-09-21): a straight StatusBar cut to a silhouette.
-- The other door out of a secret: `StatusBar:SetMinMaxValues` and `SetValue`
-- both take one, and the ENGINE sizes the fill — no curve, no chunk, no seam
-- (measured with `/gu barprobe`: 80.0% health → a fill 80.0% tall under a
-- circle mask, and an absorb bar sized by the secret absorb). The fill's
-- layers are one StatusBar each, all fed the same value: base (colour, or a
-- SetGradient ACROSS the fill axis — that axis does not shrink with the
-- value), grad (the ramp companion, ALONG the fill axis — a StatusBar crops
-- its texture rather than stretching it, so the ramp stays put in space),
-- mid / low (the shift colours; their alpha is the same curve the arc uses).
-- Every texture wears its own MaskTexture of the same silhouette; the mask
-- is sized to the shape's CANVAS so the silhouette's footprint lands exactly
-- on the bar (the catalog's art carries 128 px of bloom padding per side).
-- The absorb is a reverse-filled StatusBar over the whole box: from the full
-- end back over the fill, present at full health, the way EUI draws it.
-- A bar has NO outline (the owner, 2026-09-27: "I still can't think of a use
-- for it" — and a stretched shape would have thickened its baked rim unevenly);
-- the outline settings are the arc's alone.
------------------------------------------------------------------------
local RAMP_PLAIN = ART .. "ramp.png"    -- alpha 0→1 left to right, no shape
-- ★ A gradient at ANY angle (BACKLOG 18, 2026-09-27): the grad StatusBar's
-- fill is INVISIBLE and only sizes a clipping frame, exactly as the absorb
-- does; inside it the ramp is a plain texture over the whole box, SQUARE
-- (so rotated texture coordinates stay a true rotation, not a skew), aimed
-- with the 8-corner SetTexCoord the arc uses and CLAMPed so everything past
-- the ramp's ends is the pure colour. It never moves as the value changes.
-- The absorb overlay's stripes: a 32 px TILE, repeated at its own size
-- (SetHorizTile / SetVertTile with REPEAT wrap), never stretched. A
-- StatusBar cannot tile — it stretches its texture over the box, and one
-- pattern went flat on a wide rectangle and huge on a tall one — so the
-- absorb StatusBar's fill is INVISIBLE and only sizes a clipping frame
-- pinned to its rectangle; the tiled stripes live inside that frame,
-- anchored across the whole bar. Blizzard's raid-frame shield is built the
-- same way. The engine still sizes the visible area from the secret.
-- ★ A tiled texture repeats at its FILE's size in UI units and ignores
-- SetTexCoord (measured 2026-09-21: a repeat count changed nothing). The
-- file's size IS the stripe scale: an 8 px tile carrying TWO periods (4 units).
local HATCH = ART .. "hatch.png"

local function Pct(unit, power, curve)
    if power ~= nil then return UnitPowerPercent(unit, power, true, curve) end
    return UnitHealthPercent(unit, true, curve)
end

-- The silhouette's geometry for a bar of `size` (the footprint's short
-- side), from the Hub's BAR-shape row: the footprint (the bar's box), the
-- canvas (the mask's size) and the footprint centre's offset from the
-- canvas centre (0,0 for a centred shape; a nested SET's member sits where
-- it was drawn). All px, y up. Rectangle: the box itself, no canvas.
local function ShapeGeometry(bc)
    if bc.shape == "rect" then return bc.width, bc.height, bc.width, bc.height, 0, 0 end
    local hub = _G.GloomsHub
    local info = hub and hub.BarShapeInfo and hub:BarShapeInfo(bc.shape)
    if not info then return bc.size, bc.size, bc.size, bc.size, 0, 0 end
    local fp, cv = info.footprint, info.canvas
    local fpw, fph = fp[3] - fp[1], fp[4] - fp[2]
    -- a set member scales by the SET's footprint, so all members share one scale
    local ref = info.setFootprint or fp
    local rw, rh = ref[3] - ref[1], ref[4] - ref[2]
    local k = bc.size / math.min(rw, rh)
    -- a stretched shape: its own scale per axis (the mask stretches with it;
    -- the fill, the gradient and the absorb all work from the box)
    local kx = bc.shapeW and (bc.shapeW / rw) or k
    local ky = bc.shapeH and (bc.shapeH / rh) or k
    local ox = ((fp[1] + fp[3]) / 2 - cv[1] / 2) * kx
    local oy = -((fp[2] + fp[4]) / 2 - cv[2] / 2) * ky
    return fpw * kx, fph * ky, cv[1] * kx, cv[2] * ky, ox, oy
end

-- A shaped bar's Width and Height as the tab shows them: the shape's (or its
-- SET's) box at the current scale — shapeW / shapeH when set, else `size` at
-- the art's own proportions.
function GU.BarShapeSize(bc)
    if not bc or bc.shape == "rect" then return nil end
    local hub = _G.GloomsHub
    local info = hub and hub.BarShapeInfo and hub:BarShapeInfo(bc.shape)
    if not info then return bc.size or 120, bc.size or 120 end
    local ref = info.setFootprint or info.footprint
    local rw, rh = ref[3] - ref[1], ref[4] - ref[2]
    local k = (bc.size or 120) / math.min(rw, rh)
    return bc.shapeW or (rw * k), bc.shapeH or (rh * k)
end

-- The box a bar occupies on screen (its footprint's bounding box after the
-- rotation), and where that box's centre sits relative to the shape's
-- canvas centre — the rotation turns the whole canvas about ITS centre, so
-- an off-centre member swings round with its set.
local function BarBox(bc)
    local fw, fh, _, _, ox, oy = ShapeGeometry(bc)
    local a = math.rad(bc.rotation or 0)
    local c, sn = math.cos(a), math.sin(a)
    local bw, bh = fw * math.abs(c) + fh * math.abs(sn), fw * math.abs(sn) + fh * math.abs(c)
    return bw, bh, ox * c - oy * sn, ox * sn + oy * c
end
GU.BarBox = BarBox

-- ★ GROW FROM (2026-09-30, the owner: widening a bar grew it both ways). A
-- bar's `growFrom` = nil (its centre) | "left" | "right" | "top" | "bottom":
-- that EDGE stays put as the size changes, and the bar's saved dx / dy are
-- where that edge's middle sits. This is how far the bar's CENTRE lies from
-- that point (plus the silhouette's own box offset, BarBox's ox / oy) — what
-- the holder is placed by. The unit box and the drag keep working in centres.
local function BarAnchorAdj(bc)
    local bw, bh, ox, oy = BarBox(bc)
    local g = bc.growFrom
    local gx = (g == "left" and bw / 2) or (g == "right" and -bw / 2) or 0
    local gy = (g == "bottom" and bh / 2) or (g == "top" and -bh / 2) or 0
    return ox + gx, oy + gy
end
GU.BarAnchorAdj = BarAnchorAdj

local FILL = {   -- fillDir → orientation, reverse
    up    = { "VERTICAL",   false }, down  = { "VERTICAL",   true },
    right = { "HORIZONTAL", false }, left  = { "HORIZONTAL", true },
}

-- `detached`: the bar's frame is placed and sized by the caller (a resource
-- segment); otherwise it fills the holder.
local function NewBar(holder, detached)
    local bar = { shown = false, shift = false, gradient = false, layers = {}, masks = {}, alphaCurve = {} }
    local fr = CreateFrame("Frame", nil, holder)
    if not detached then fr:SetAllPoints(holder) end
    bar.frame = fr
    -- Every texture wears a mask of the silhouette — EXCEPT in Rectangle
    -- mode, where the masks come OFF: a StatusBar is already a rectangle,
    -- and a mask's clamp-to-black wrap fades its outer half-texel, which on
    -- a stretched 8×8 was 12 px of soft edge per side (the owner, 2026-09-21).
    -- ★ ROUNDED ENDS on a Rectangle (2026-09-29): each texture also carries two
    -- CAP masks — a half-disc as tall as the bar at either end, CLAMP-wrapped, so
    -- the disc's solid edge extends over the whole rest of the bar (TESTED that
    -- day with a throwaway `/gu capprobe`: a mask honours CLAMP; the fill runs into the round
    -- end with no seam). Two masks AND together, so both ends can be round. The
    -- radius is always half the short side, whatever the length.
    -- ★ The faint dark rim at a rounded end's edge (the owner, 2026-09-29) is
    -- stacked, separately cut layers: on the edge's part-covered pixels the
    -- base's dark colour bleeds through the layers over it (Figma cuts the
    -- finished stack once). Growing the upper layers' masks by a screen pixel
    -- was TRIED that day and REVERTED — it put points where the curve begins and
    -- flattened the end's middle; the owner: "I just live with it".
    local function masked(tex)
        local m = fr:CreateMaskTexture()
        m:SetPoint("CENTER", fr, "CENTER")
        tex:AddMaskTexture(m)
        bar.masks[#bar.masks + 1] = { tex = tex, mask = m, on = true,
            capS = fr:CreateMaskTexture(), capE = fr:CreateMaskTexture() }
    end
    bar.track = fr:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints(); bar.track:SetColorTexture(1, 1, 1, 1); masked(bar.track)
    for i, name in ipairs(LAYERS) do
        local sb = CreateFrame("StatusBar", nil, fr)
        sb:SetAllPoints(); sb.levelUp = i
        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        masked(sb:GetStatusBarTexture())
        bar.layers[name] = sb
        if PROFILE[name] and name ~= "base" and name ~= "grad" then bar.alphaCurve[name] = CurveFrom(PROFILE[name]) end
    end
    -- the ramp: the grad bar only sizes its clip (a plain zero alpha)
    local gsb = bar.layers.grad
    gsb:GetStatusBarTexture():SetAlpha(0)
    bar.gradClip = CreateFrame("Frame", nil, gsb)
    bar.gradClip:SetClipsChildren(true)
    bar.gradClip:SetPoint("TOPLEFT", gsb:GetStatusBarTexture(), "TOPLEFT")
    bar.gradClip:SetPoint("BOTTOMRIGHT", gsb:GetStatusBarTexture(), "BOTTOMRIGHT")
    bar.gradTex = bar.gradClip:CreateTexture(nil, "ARTWORK")
    bar.gradTex:SetTexture(RAMP_PLAIN, "CLAMP", "CLAMP")
    bar.gradTex:SetPoint("CENTER", fr, "CENTER")
    masked(bar.gradTex)
    -- GLOSS (2026-09-29, the owner's Figma mock): ONE white inner shadow — 65%,
    -- offset 0/4, blur 4 — rendered into art by tools/gen-gloss.py: a rim of
    -- fixed thickness along the top edge (gloss-band) and, at a rounded end, the
    -- rim curving round it (gloss-cap-*-<height>). Untinted, over the fill. Like
    -- the ramp, the gloss StatusBar is INVISIBLE and only sizes a clip, so the
    -- rim drains with the fill; its three textures live in the clip.
    local gl = CreateFrame("StatusBar", nil, fr)
    gl:SetAllPoints(); gl.levelUp = #LAYERS + 1
    gl:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    gl:GetStatusBarTexture():SetAlpha(0)
    bar.layers.gloss = gl
    bar.glossClip = CreateFrame("Frame", nil, gl)
    bar.glossClip:SetClipsChildren(true)
    bar.glossClip:SetPoint("TOPLEFT", gl:GetStatusBarTexture(), "TOPLEFT")
    bar.glossClip:SetPoint("BOTTOMRIGHT", gl:GetStatusBarTexture(), "BOTTOMRIGHT")
    bar.glossTex = {}
    for _, k in ipairs({ "band", "capS", "capE" }) do
        local t = bar.glossClip:CreateTexture(nil, "ARTWORK")
        masked(t)
        bar.glossTex[k] = t
    end
    -- its alpha (a resource segment's step) goes to all three pieces
    bar.glossAlpha = { SetAlpha = function(_, a) for _, t in pairs(bar.glossTex) do t:SetAlpha(a) end; if bar.endTex then bar.endTex.gloss:SetAlpha(a); bar.endTex.band:SetAlpha(a) end end }
    bar.absorb = CreateFrame("StatusBar", nil, fr)
    bar.absorb:SetAllPoints(); bar.absorb.levelUp = #LAYERS + 2
    bar.absorb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar.absorb:GetStatusBarTexture():SetAlpha(0)      -- a plain zero; it only sizes the clip
    bar.absorbClip = CreateFrame("Frame", nil, bar.absorb)
    bar.absorbClip:SetClipsChildren(true)
    bar.absorbClip:SetPoint("TOPLEFT", bar.absorb:GetStatusBarTexture(), "TOPLEFT")
    bar.absorbClip:SetPoint("BOTTOMRIGHT", bar.absorb:GetStatusBarTexture(), "BOTTOMRIGHT")
    bar.hatch = bar.absorbClip:CreateTexture(nil, "ARTWORK")
    bar.hatch:SetTexture(HATCH, "REPEAT", "REPEAT")
    bar.hatch:SetHorizTile(true); bar.hatch:SetVertTile(true)
    bar.hatch:SetAllPoints(fr)
    masked(bar.hatch)

    -- ★ THE FILL'S EDGE PIECES AND SEGMENTS (2026-09-29, the owner — `/gu
    -- fillprobe` TESTED that day: pieces ANCHORED to the StatusBar's fill texture
    -- ride its engine-sized edge on a secret value, down to the far end at 0%;
    -- a step-shaped alpha curve through the percent switches a piece cleanly).
    --   the FILL END (`bc.fillEnd` round | angled | point; Rectangle, no
    --     segments): one piece per colour layer, pinned PAST the fill's edge, so
    --     the layers are shortened by its length (`capLen`, half the bar's
    --     thickness) and it reaches the box's end at 100%. Its base / mid / low
    --     pieces take every colour and alpha their layers take (Tex returns the
    --     PAIR); its gradient piece's alpha is the ramp at the edge, a curve of
    --     the percent (AimGradient). All in `endGate`, whose alpha is a step:
    --     GONE at exactly 0% — the owner: "at 0%, the unit is dead".
    --   the MARKER (`bc.marker`): a sprite centred on — or just inside — the
    --     edge (the fill end's tip when there is one), in `markGate`, gone at 0%.
    --   SEGMENTS (`bc.segments` 2..30, not `segWhole`): dividers laid OVER the
    --     bar — straight, slanted or chevron, `segGap` wide, `segColor` — in a
    --     clip of the box, cut to the silhouette. Static; the fill runs under
    --     them. (Whole segments are a ROW of window bars instead — NewRow.)
    local EPIECES = { "base", "grad", "mid", "low" }
    bar.endGate = CreateFrame("Frame", nil, fr); bar.endGate:SetAllPoints(fr)
    bar.endTex = {}
    for i, name in ipairs(EPIECES) do
        local t = bar.endGate:CreateTexture(nil, "ARTWORK", nil, i - 1)
        bar.endTex[name] = t
    end
    bar.endTex.gloss = bar.endGate:CreateTexture(nil, "OVERLAY")
    -- ★ The end's GRADIENT and straight GLOSS are the bar's own ramp and gloss
    -- band, laid over the whole box exactly as the fill's are (so they stay put
    -- in space) and cut to the end's shape by `endMask`, which rides the edge.
    -- A single colour picked "where the end is" was wrong for a gradient ACROSS
    -- the bar (the owner's screenshot, 2026-09-29: a flat red wedge beside a
    -- red→maroon fill).
    bar.endMask = bar.endGate:CreateMaskTexture()
    bar.endTex.grad:SetTexture(RAMP_PLAIN, "CLAMP", "CLAMP")
    bar.endTex.grad:AddMaskTexture(bar.endMask)
    bar.endTex.band = bar.endGate:CreateTexture(nil, "OVERLAY")
    bar.endTex.band:AddMaskTexture(bar.endMask)
    -- ★ and the round end's gloss rim: the art is BLURRED past the curve (42%
    -- of its alpha lies outside the half-disc, measured 2026-09-29) and relies
    -- on a mask to cut it — unmasked it drew a white crust round the end (the
    -- owner's screenshot, the same day). A Rounded End's rim is cut by its cap mask.
    bar.endTex.gloss:AddMaskTexture(bar.endMask)
    bar.endGate:Hide()
    -- a colour layer and its end piece take every colour / alpha together
    local function Pair(a, b)
        return {
            SetVertexColor = function(_, ...) a:SetVertexColor(...); b:SetVertexColor(...) end,
            SetAlpha = function(_, v) a:SetAlpha(v); b:SetAlpha(v) end,
            IsShown = function() return a:IsShown() end,
        }
    end
    bar.pairs = {}
    for _, name in ipairs({ "base", "mid", "low" }) do
        bar.pairs[name] = Pair(bar.layers[name]:GetStatusBarTexture(), bar.endTex[name])
    end
    -- the TRACK's end, in the fill end's shape: the track stays ONE texture, cut
    -- at the far end by a CLAMP mask of the end art (as the absorb, below). A
    -- separate end piece left a seam where the two met (the owner, 2026-09-29).
    bar.trackEndMask = fr:CreateMaskTexture()
    -- ★ the ABSORB stripes, cut to that shape too (2026-09-29, the owner: they
    -- ran square past an angled end): a mask of the end art at the far end,
    -- CLAMP-wrapped — the art's inner column is solid, so CLAMP carries it over
    -- the rest of the bar (the Rounded Ends masks' trick, TESTED). It takes the
    -- slot the far side's Rounded End gives up (Configure).
    bar.absorbEndMask = fr:CreateMaskTexture()
    bar.markGate = CreateFrame("Frame", nil, fr); bar.markGate:SetAllPoints(fr)
    bar.marker = bar.markGate:CreateTexture(nil, "OVERLAY")
    bar.markGate:Hide()
    bar.segFrame = CreateFrame("Frame", nil, fr); bar.segFrame:SetAllPoints(fr)
    bar.segFrame:SetClipsChildren(true)
    bar.segFrame:Hide()
    bar.dividers = {}
    -- the divider pool grows on demand, BEFORE Configure lays the masks on it
    function bar:EnsureDividers(n)
        for i = #self.dividers + 1, n do
            local t = self.segFrame:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(1, 1, 1, 1)
            masked(t)
            self.dividers[i] = t
        end
    end
    -- alpha-driven extras (the gates, the end's gradient piece): key → { obj, pts, curve }
    bar.extra = {}

    -- bc: the ring's `bar` block. Returns the box (w, h) the holder must take.
    function bar:Configure(bc)
        self.geo = true
        local nseg = (not self.window) and math.floor(bc.segments or 0) or 0
        -- (Whole segments are a Rectangle's only: a shape keeps the dividers)
        if nseg >= 2 and not (bc.segWhole and bc.shape == "rect") then
            self:EnsureDividers((math.min(nseg, 30) - 1) * ((bc.segStyle == "chevron") and 2 or 1))
        end
        local fw, fh, cw, ch = ShapeGeometry(bc)
        local bw, bh, ox, oy = BarBox(bc)
        local hub = _G.GloomsHub
        -- ★ The catalog's base art has a BINARY edge (measured 2026-09-21: alpha
        -- 0→255 in one texel), which minified ten times at a 24 px shard is a
        -- jagged rim. Under ~192 px on screen the SMALL variant (`-base-s`, a
        -- quarter size, resampled so the edge carries anti-aliasing) draws
        -- clean; the full art keeps its crispness for big shapes.
        -- ★ Measured in SCREEN PIXELS, not UI units (fixed 2026-09-27): the test
        -- was `< 192` units, and on the owner's 4K a unit is ~2 px — so an orb
        -- of Size 96 (a 191-unit canvas) stretched the 128 px small mask ~3x
        -- and went soft, while Size 97 took the full art and was sharp.
        local _, physH = GetPhysicalScreenSize()
        local pxPerUnit = ((physH and physH > 0) and (physH / 768) or 1) * (fr:GetEffectiveScale() or 1)
        local part = (math.max(cw, ch) * pxPerUnit < 192) and "base-s" or "base"
        local base = bc.shape ~= "rect" and hub and hub:BarShapeAsset(bc.shape, part) or "Interface\\Buttons\\WHITE8x8"
        local rot = math.rad(bc.rotation or 0)
        -- ★ No SetTexCoord on a mask: flipped coordinates (either form) make
        -- the mask hide everything (measured 2026-09-21, twice). A flip is a
        -- matter of ART — a mirrored file — not of the mask. Rotation is fine.
        -- the mask is centred on the CANVAS centre, which sits (-ox, -oy)
        -- from the box centre — zero for a centred shape
        local rect = bc.shape == "rect"
        self.maskSpec = (not rect) and { cw, ch, base, rot, -ox, -oy } or nil   -- for a late-comer (the kick tick)
        -- the rounded ends (Rectangle only): along the LONG side — left / right on a
        -- flat bar, bottom / top on a standing one; "start" is the left / bottom
        local ends = rect and bc.roundEnds or nil
        local flat = (bc.width or 200) >= (bc.height or 24)
        local short = math.min(bc.width or 200, bc.height or 24)
        local function cap(m, want, file, point)
            m:ClearAllPoints()
            if flat then m:SetSize(short / 2, short) else m:SetSize(short, short / 2) end
            m:SetPoint(point, fr, point, 0, 0)
            m:SetTexture(ART .. file, "CLAMP", "CLAMP")
            return want
        end
        local wantS = ends == "start" or ends == "both"
        local wantE = ends == "end" or ends == "both"
        -- ★ A FILL END shapes the bar's far end too (2026-09-29, the owner: an
        -- angled fill over a round-ended track): the track's end takes the fill
        -- end's shape (ConfigureEdge), so the Rounded End on THAT side stands down.
        local fe = bc.fillEnd
        if rect and nseg < 2 and not self.window and (fe == "round" or fe == "angled" or fe == "point") then
            local d = bc.fillDir or "up"
            if flat and d == "right" then wantE = false
            elseif flat and d == "left" then wantS = false
            elseif not flat and d == "up" then wantE = false
            elseif not flat and d == "down" then wantS = false end
        end
        for _, e in ipairs(self.masks) do
            cap(e.capS, wantS, flat and "cap-l.png" or "cap-b.png", flat and "LEFT" or "BOTTOM")
            cap(e.capE, wantE, flat and "cap-r.png" or "cap-t.png", flat and "RIGHT" or "TOP")
            if wantS ~= (e.onS or false) then if wantS then e.tex:AddMaskTexture(e.capS) else e.tex:RemoveMaskTexture(e.capS) end; e.onS = wantS end
            if wantE ~= (e.onE or false) then if wantE then e.tex:AddMaskTexture(e.capE) else e.tex:RemoveMaskTexture(e.capE) end; e.onE = wantE end
            if rect then
                if e.on then e.tex:RemoveMaskTexture(e.mask); e.on = false end
            else
                if not e.on then e.tex:AddMaskTexture(e.mask); e.on = true end
                local m = e.mask
                m:SetSize(cw, ch)
                m:ClearAllPoints(); m:SetPoint("CENTER", fr, "CENTER", -ox, -oy)
                m:SetTexture(base, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                m:SetRotation(rot)
            end
        end
        local dir = FILL[bc.fillDir] or FILL.up
        local lv = fr:GetFrameLevel()
        for _, sb in pairs(self.layers) do
            sb:SetOrientation(dir[1]); sb:SetReverseFill(dir[2]); sb:SetFrameLevel(lv + sb.levelUp)
        end
        self.boxW, self.boxH = bw, bh
        self:AimGradient()
        self.absorb:SetOrientation(dir[1]); self.absorb:SetReverseFill(not dir[2]); self.absorb:SetFrameLevel(lv + self.absorb.levelUp)
        self.glossOn = bc.gloss == true
        self:PlaceGloss(bc, rect, flat, short, wantS, wantE, fw, fh)
        self.absorbOn = self.hasAbsorb and bc.absorb ~= false or false   -- the health bar only
        local ac = bc.absorbColor or { 1, 1, 1 }
        self.hatch:SetVertexColor(ac[1], ac[2], ac[3])
        self.hatch:SetAlpha(bc.absorbAlpha or 0.6)
        self.fillDir = bc.fillDir or "up"
        self:ConfigureEdge(bc, rect, bw, bh, lv)
        self:Apply()
        return bw, bh
    end

    -- The gloss's pieces for this bar: lit from above, so a FLAT bar takes the
    -- band along its top (between any rounded ends) and a curving piece at each
    -- rounded end; a STANDING bar only glosses at its top — its rounded top's
    -- piece, or the band across a square top. A shaped bar takes the band,
    -- cut by its silhouette.
    local GLOSS = ART .. "gloss\\"
    local function near(n) return math.max(8, math.min(96, math.floor(n / 4 + 0.5) * 4)) end
    function bar:PlaceGloss(bc, rect, flat, short, wantS, wantE, fw, fh)
        local G = self.glossTex
        for _, t in pairs(G) do t:ClearAllPoints(); t:Hide() end
        local fr = self.frame
        local function band(l, r, h)
            local b = G.band
            b:SetTexture(GLOSS .. "gloss-band.png", "CLAMP", "CLAMP")
            local bh = math.min(32, h)
            b:SetPoint("TOPLEFT", fr, "TOPLEFT", l, 0); b:SetPoint("TOPRIGHT", fr, "TOPRIGHT", -r, 0)
            b:SetHeight(bh); b:SetTexCoord(0, 1, 0, bh / 32); b:Show()
        end
        if not rect then band(0, 0, fh); return end
        local r = short / 2
        if flat then
            band(wantS and r or 0, wantE and r or 0, fh)
            if wantS then G.capS:SetTexture(GLOSS .. "gloss-cap-l-" .. near(short) .. ".png"); G.capS:SetSize(r, short); G.capS:SetPoint("LEFT", fr, "LEFT"); G.capS:Show() end
            if wantE then G.capE:SetTexture(GLOSS .. "gloss-cap-r-" .. near(short) .. ".png"); G.capE:SetSize(r, short); G.capE:SetPoint("RIGHT", fr, "RIGHT"); G.capE:Show() end
        elseif wantE then
            G.capE:SetTexture(GLOSS .. "gloss-cap-t-" .. near(short) .. ".png"); G.capE:SetSize(short, r); G.capE:SetPoint("TOP", fr, "TOP"); G.capE:Show()
        else
            band(0, 0, fh)
        end
    end

    -- The fill end, the marker and the dividers for this bar (see NewBar).
    local FILLART = ART .. "fill\\"
    -- fillDir → the fill texture's moving edge, the end piece's side that meets
    -- it, and the art's suffix
    local EDGE = {
        right = { "RIGHT", "LEFT", "r" }, left = { "LEFT", "RIGHT", "l" },
        up    = { "TOP", "BOTTOM", "t" }, down = { "BOTTOM", "TOP", "b" },
    }
    -- the markers: across = the size, along = size x ratio (never under `min`);
    -- `turn` = the art is drawn for a flat bar and turns on a standing one
    local MARKERS = {
        post    = { ratio = 0.15, min = 2 },
        knob    = { file = "marker-knob.png", ratio = 1 },
        diamond = { file = "marker-diamond.png", ratio = 1 },
        glow    = { file = "marker-glow.png", ratio = 1, add = true },
        spark   = { file = "marker-spark.png", ratio = 0.25, min = 4, add = true, turn = true },
        custom  = { ratio = 1 },
    }
    GU.MARKERS = MARKERS
    local GATE_PTS = { { 0, ALPHA_OFF }, { 0.0005, 1 }, { 1, 1 } }   -- off at exactly 0%, on above
    local function setExtra(self, key, obj, pts)
        if not obj then self.extra[key] = nil; return end
        self.extra[key] = { obj = obj, pts = pts, curve = CurveFrom(pts) }
    end
    -- a media name / atlas / file ID / path onto a texture (Overlays' rule)
    local function SetArt(t, name)
        local hub = _G.GloomsHub
        local path = hub and hub.ResolveAssetPath and hub:ResolveAssetPath(name)
        if path then t:SetTexture(path)
        elseif tonumber(name) then t:SetTexture(tonumber(name))
        elseif name and name ~= "" and C_Texture and C_Texture.GetAtlasInfo(name) then t:SetAtlas(name)
        elseif name and name ~= "" then t:SetTexture(name)
        else t:SetColorTexture(1, 1, 1, 1) end
    end
    function bar:ConfigureEdge(bc, rect, bw, bh, lv)
        local fr = self.frame
        local dir = bc.fillDir or "up"
        local vertical = dir == "up" or dir == "down"
        local sgn = (dir == "down" or dir == "left") and -1 or 1
        local L, A = vertical and bh or bw, vertical and bw or bh
        local E = EDGE[dir] or EDGE.up
        local nseg = (not self.window) and math.min(30, math.floor(bc.segments or 0)) or 0
        if nseg < 2 then nseg = 0 end
        local ends = (not self.window) and rect and nseg == 0 and bc.fillEnd or nil
        if ends ~= "round" and ends ~= "angled" and ends ~= "point" then ends = nil end
        self.capOn = ends ~= nil
        local capLen = ends and math.max(1, math.floor(A / 2 + 0.5)) or 0
        -- the colour layers make room for the end (the absorb keeps the whole box)
        for _, sb in pairs(self.layers) do
            sb:ClearAllPoints()
            if capLen == 0 then sb:SetAllPoints(fr)
            elseif dir == "right" then sb:SetPoint("TOPLEFT", fr, "TOPLEFT"); sb:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", -capLen, 0)
            elseif dir == "left" then sb:SetPoint("TOPLEFT", fr, "TOPLEFT", capLen, 0); sb:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT")
            elseif dir == "up" then sb:SetPoint("TOPLEFT", fr, "TOPLEFT", 0, -capLen); sb:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT")
            else sb:SetPoint("TOPLEFT", fr, "TOPLEFT"); sb:SetPoint("BOTTOMRIGHT", fr, "BOTTOMRIGHT", 0, capLen) end
        end
        -- ★ The end pieces OVERLAP the fill by one screen pixel: the fill's edge
        -- lands between pixels, and two shapes butted at it are each smoothed on
        -- their own — a faint seam (the owner, 2026-09-29). The solid base hides
        -- the overlap. `ox, oy` point back into the fill.
        local _, physH = GetPhysicalScreenSize()
        local px = 1 / math.max(0.01, ((physH and physH > 0) and (physH / 768) or 1) * (fr:GetEffectiveScale() or 1))
        local ox = (dir == "right" and -px) or (dir == "left" and px) or 0
        local oy = (dir == "up" and -px) or (dir == "down" and px) or 0
        local function endSize(t) if vertical then t:SetSize(A, capLen + px) else t:SetSize(capLen + px, A) end end
        local edgeTex = self.layers.base:GetStatusBarTexture()
        -- THE FILL END
        self.endGate:SetFrameLevel(lv + #LAYERS + 1)
        if ends then
            local file = (ends == "round") and (ART .. "cap-" .. E[3] .. ".png") or (FILLART .. "end-" .. ends .. "-" .. E[3] .. ".png")
            local am = self.absorbEndMask
            am:ClearAllPoints()
            if vertical then am:SetSize(A, capLen) else am:SetSize(capLen, A) end
            am:SetPoint(E[1], fr, E[1])
            am:SetTexture(file, "CLAMP", "CLAMP")
            if not self.absorbEndOn then self.hatch:AddMaskTexture(am); self.absorbEndOn = true end
            local tm = self.trackEndMask
            tm:ClearAllPoints()
            if vertical then tm:SetSize(A, capLen) else tm:SetSize(capLen, A) end
            tm:SetPoint(E[1], fr, E[1])
            tm:SetTexture(file, "CLAMP", "CLAMP")
            if not self.trackEndOn then self.track:AddMaskTexture(tm); self.trackEndOn = true end
            for _, name in ipairs({ "base", "mid", "low" }) do
                local t = self.endTex[name]
                t:ClearAllPoints()
                endSize(t)
                t:SetPoint(E[2], edgeTex, E[1], ox, oy)
                t:SetTexture(file, "CLAMP", "CLAMP")
            end
            local m = self.endMask
            m:ClearAllPoints()
            endSize(m)
            m:SetPoint(E[2], edgeTex, E[1], ox, oy)
            m:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            -- the gloss's curve round a ROUND end (lit from above: a flat bar's
            -- right or left end, a standing bar's top)
            local g = self.endTex.gloss
            g:ClearAllPoints()
            local gfile
            if ends == "round" then
                local n = math.max(8, math.min(96, math.floor(A / 4 + 0.5) * 4))
                if not vertical then gfile = ART .. "gloss\\gloss-cap-" .. E[3] .. "-" .. n .. ".png"
                elseif dir == "up" then gfile = ART .. "gloss\\gloss-cap-t-" .. n .. ".png" end
            end
            self.endGlossOK = gfile ~= nil
            if gfile then
                g:SetTexture(gfile)
                endSize(g)
                g:SetPoint(E[2], edgeTex, E[1], ox, oy)
            end
            -- an angled or pointed end on a flat bar: the straight rim runs on over it
            local band = self.endTex.band
            band:ClearAllPoints()
            self.endBandOK = (ends ~= "round") and not vertical
            if self.endBandOK then
                local h = math.min(32, A)
                band:SetTexture(ART .. "gloss\\gloss-band.png", "CLAMP", "CLAMP")
                band:SetPoint("TOPLEFT", fr, "TOPLEFT"); band:SetPoint("TOPRIGHT", fr, "TOPRIGHT")
                band:SetHeight(h); band:SetTexCoord(0, 1, 0, h / 32)
            end
            setExtra(self, "endGate", self.endGate, GATE_PTS)
        else
            setExtra(self, "endGate", nil)
            if self.absorbEndOn then self.hatch:RemoveMaskTexture(self.absorbEndMask); self.absorbEndOn = false end
            if self.trackEndOn then self.track:RemoveMaskTexture(self.trackEndMask); self.trackEndOn = false end
        end
        -- THE MARKER
        local mk = (not self.window) and bc.marker or nil
        local def = mk and MARKERS[mk]
        self.markOn = def ~= nil
        self.markGate:SetFrameLevel(lv + #LAYERS + 5)
        if def then
            local m = self.marker
            m:SetRotation(0); m:SetTexCoord(0, 1, 0, 1)
            if mk == "custom" then SetArt(m, bc.markerTex)
            elseif def.file then m:SetTexture(FILLART .. def.file)
            else m:SetColorTexture(1, 1, 1, 1) end
            m:SetBlendMode(def.add and "ADD" or "BLEND")
            local size = bc.markerSize or (A + 8)
            local along = math.max(def.min or 1, size * def.ratio)
            if vertical and def.turn then m:SetSize(along, size); m:SetRotation(math.pi / 2)
            elseif vertical then m:SetSize(size, along)
            else m:SetSize(along, size) end
            local c = bc.markerColor or { 1, 1, 1 }
            m:SetVertexColor(c[1], c[2], c[3])
            m:SetAlpha(bc.markerAlpha or 1)
            -- the tip: the fill end's far side when there is one, else the fill's edge
            local anchor = ends and self.endTex.base or edgeTex
            m:ClearAllPoints()
            if bc.markerAlign == "inside" then m:SetPoint(E[1], anchor, E[1]) else m:SetPoint("CENTER", anchor, E[1]) end
            setExtra(self, "markGate", self.markGate, GATE_PTS)
        else
            setExtra(self, "markGate", nil)
        end
        -- THE DIVIDERS (smooth segments), in (along, across) about the box's
        -- centre; a standing bar swaps the axes (which mirrors the rotation)
        local smooth = nseg >= 2 and not (bc.segWhole and bc.shape == "rect")
        self.segOn = smooth
        self.segFrame:SetFrameLevel(lv + #LAYERS + 3)
        for _, t in ipairs(self.dividers) do t:Hide() end
        if smooth then
            local gap = math.max(1, bc.segGap or 2)
            local style = bc.segStyle or "straight"
            local a = math.rad(math.max(5, math.min(60, bc.segSlant or 30)))
            local c = bc.segColor or { 0, 0, 0 }
            local alpha = bc.segAlpha or 1
            local k = 0
            local function quad(along, across, thick, len, rot)
                k = k + 1
                local t = self.dividers[k]; if not t then return end
                t:ClearAllPoints()
                if vertical then t:SetSize(len, thick); t:SetPoint("CENTER", fr, "CENTER", across, along); t:SetRotation(-rot)
                else t:SetSize(thick, len); t:SetPoint("CENTER", fr, "CENTER", along, across); t:SetRotation(rot) end
                t:SetVertexColor(c[1], c[2], c[3]); t:SetAlpha(alpha); t:Show()
            end
            for i = 1, nseg - 1 do
                local b = -L / 2 + i * L / nseg
                if style == "slant" then
                    quad(b, 0, gap, A / math.cos(a) + gap * 2, -sgn * a)
                elseif style == "chevron" then
                    local d = (A / 2) * math.tan(a)
                    local len = (A / 2) / math.cos(a) + gap
                    quad(b - sgn * d / 2, A / 4, gap, len, sgn * a)
                    quad(b - sgn * d / 2, -A / 4, gap, len, -sgn * a)
                else
                    quad(b, 0, gap, A + 2, 0)
                end
            end
        end
    end

    function bar:Apply()
        local function want(name)
            return name == "base" or (name == "grad" and self.gradient) or ((name == "mid" or name == "low") and self.shift)
                or (name == "gloss" and self.glossOn)
        end
        for name, sb in pairs(self.layers) do sb:SetShown(self.shown and want(name)) end
        self.track:SetShown(self.shown)
        self.absorb:SetShown(self.shown and self.absorbOn)
        self.endGate:SetShown(self.shown and self.capOn and true or false)
        if self.capOn then
            for _, name in ipairs({ "base", "grad", "mid", "low" }) do self.endTex[name]:SetShown(want(name)) end
            self.endTex.gloss:SetShown(want("gloss") and self.endGlossOK and true or false)
            self.endTex.band:SetShown(want("gloss") and self.endBandOK and true or false)
        end
        self.markGate:SetShown(self.shown and self.markOn and true or false)
        self.segFrame:SetShown(self.shown and self.segOn and true or false)
    end
    function bar:SetShown(on) self.shown = on; self:Apply() end
    function bar:SetShift(on) self.shift = on; self:Apply() end
    -- the texture a layer's colour and alpha land on (grad: the ramp, not its sizer)
    function bar:Tex(name)
        if self.pairs[name] then return self.pairs[name] end
        if name == "grad" then return self.gradTex end
        if name == "gloss" then return self.glossAlpha end
        local sb = self.layers[name]
        return sb and sb:GetStatusBarTexture()
    end
    function bar:SetTrack(c, alpha) self.track:SetVertexColor(c[1], c[2], c[3]); self.track:SetAlpha(alpha) end

    -- Colour ONLY, three values (the 4th lands as opacity on 12.1 — the arc's lesson).
    function bar:SetColor(name, r, g, b)
        local t = self:Tex(name)
        if t then t:SetVertexColor(r, g, b) end
    end
    function bar:SetSolid(c)
        self.gradient = false
        self:SetColor("base", c[1], c[2], c[3])
        self:Apply()
    end
    -- colour → colour2 along `angleDeg` in SCREEN space (0 = left→right,
    -- 90 = bottom→top — the arc's convention), any angle: the base carries
    -- colour, the ramp fades colour2 in over it. The ramp spans the box's
    -- extent along the angle, so both ends reach their pure colours.
    function bar:SetGradient(c1, c2, angleDeg)
        self.gradient = true
        self.gradAngle = angleDeg or 0
        self:SetColor("base", c1[1], c1[2], c1[3])
        self.gradTex:SetVertexColor(c2[1], c2[2], c2[3])
        self.endTex.grad:SetVertexColor(c2[1], c2[2], c2[3])
        self:AimGradient()
        self:Apply()
    end
    function bar:AimGradient()
        local w, h = self.boxW, self.boxH
        if not w then return end
        local a = math.rad(self.gradAngle or 0)
        local cs, sn = math.cos(a), math.sin(a)
        local L = math.max(1, math.abs(w * cs) + math.abs(h * sn))   -- the box along the angle
        local D = math.sqrt(w * w + h * h)                           -- a square that covers the box
        self.gradTex:SetSize(D, D)
        -- a corner at (x, y) from the centre, y up → u runs 0→1 across L along the angle
        local function uv(x, y)
            return 0.5 + (x * cs + y * sn) / L, 0.5 - (-x * sn + y * cs) / L
        end
        local r = D / 2
        local ulx, uly = uv(-r, r)
        local llx, lly = uv(-r, -r)
        local urx, ury = uv(r, r)
        local lrx, lry = uv(r, -r)
        self.gradTex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
        -- the fill END's gradient piece: the same ramp, same place (cut by endMask)
        local eg = self.endTex.grad
        eg:ClearAllPoints(); eg:SetPoint("CENTER", self.frame, "CENTER")
        eg:SetSize(D, D)
        eg:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
    end

    local function feed(self, max, val)
        self.timerFor = nil
        for _, sb in pairs(self.layers) do
            if sb:IsShown() then sb:SetMinMaxValues(0, max); sb:SetValue(val) end
        end
    end
    -- A WINDOW (a resource segment): the bar is always drawn FULL and its
    -- layers' alpha is a step at `hi` of the overall percent — a point is
    -- whole or absent. `profiles` may override mid / low (the breakpoint).
    function bar:SetWindow(hi, profiles)
        self.window = hi
        self.alphaPts = {
            base = { { 0, ALPHA_OFF }, { math.max(0, hi - 0.002), ALPHA_OFF }, { hi, 1 }, { 1, 1 } },
            mid  = (profiles and profiles.mid) or PROFILE.mid,
            low  = (profiles and profiles.low) or PROFILE.low,
        }
        self.alphaPts.grad = self.alphaPts.base
        self.alphaPts.gloss = self.alphaPts.base   -- the gloss steps with its segment
        self.alphaCurve = {}
        for name, pts in pairs(self.alphaPts) do self.alphaCurve[name] = CurveFrom(pts) end
    end
    local function pts(self, name) return (self.alphaPts and self.alphaPts[name]) or PROFILE[name] end
    function bar:SetFromUnit(unit, power)
        if not self.geo then return end
        if self.window then feed(self, 1, 1)
        else
            local max = (power ~= nil) and UnitPowerMax(unit, power) or UnitHealthMax(unit)
            local val = (power ~= nil) and UnitPower(unit, power) or UnitHealth(unit)
            feed(self, max, val)
        end
        for name, curve in pairs(self.alphaCurve) do
            if self.layers[name]:IsShown() then self:Tex(name):SetAlpha(Pct(unit, power, curve)) end
        end
        for _, e in pairs(self.extra) do e.obj:SetAlpha(Pct(unit, power, e.curve)) end
    end
    function bar:SetFromPlain(pct, alphaScale)
        if not self.geo then return end
        pct = clamp(pct, 0, 1)
        feed(self, 1, self.window and 1 or pct)
        for name in pairs(self.alphaCurve) do
            self:Tex(name):SetAlpha(Eval(pts(self, name), pct) * (alphaScale or 1))
        end
        for _, e in pairs(self.extra) do e.obj:SetAlpha(Eval(e.pts, pct)) end
    end
    -- A cast whose times are secret: the engine animates the bar itself from
    -- the duration object (StatusBar:SetTimerDuration — EUI's cast bar), set
    -- ONCE per cast; the shift layers' alpha comes from the same object's
    -- percent evaluators each tick, as the arc does.
    function bar:SetFromDuration(d, drains)
        if not self.geo then return end
        local dirE = Enum.StatusBarTimerDirection
        -- a WINDOW (a whole segment) is drawn full; only its alpha step moves
        if self.window then feed(self, 1, 1)
        elseif self.timerFor ~= d and dirE then
            self.timerFor = d
            local interp = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.None
            for _, sb in pairs(self.layers) do
                if sb:IsShown() then
                    sb:SetMinMaxValues(0, 1)
                    sb:SetTimerDuration(d, interp, drains and dirE.RemainingTime or dirE.ElapsedTime)
                end
            end
        end
        local m = drains and d.EvaluateRemainingPercent or d.EvaluateElapsedPercent
        for name, curve in pairs(self.alphaCurve) do
            if self.layers[name]:IsShown() then self:Tex(name):SetAlpha(m(d, curve, ALPHA_OFF)) end
        end
        for _, e in pairs(self.extra) do e.obj:SetAlpha(m(d, e.curve, ALPHA_OFF)) end
    end
    -- fn(texture, piece) over one layer — the bar is its own single piece.
    function bar:Layer(name, fn)
        local t = self:Tex(name)
        if t then fn(t, self) end
    end
    -- The kick tick on a bar: a hairline across the fill axis at `frac` of
    -- the box (plain arithmetic — the plain-time path only, as the arc).
    function bar:PlaceTick(tick, frac, thickness)
        local w, h = self.frame:GetSize()
        local vertical = (self.fillDir == "up" or self.fillDir == "down")
        local rev = (self.fillDir == "down" or self.fillDir == "left")
        if rev then frac = 1 - frac end
        tick:ClearAllPoints()
        if vertical then
            tick:SetSize(w, thickness)
            tick:SetPoint("CENTER", self.frame, "BOTTOM", 0, frac * h)
        else
            tick:SetSize(thickness, h)
            tick:SetPoint("CENTER", self.frame, "LEFT", frac * w, 0)
        end
        tick:SetRotation(0)
        -- cut to the silhouette like everything else on the bar (none on a rectangle)
        local ms = self.maskSpec
        if ms then
            if not tick.barMask then tick.barMask = tick:GetParent():CreateMaskTexture() end
            if not tick.barMaskOn then tick:AddMaskTexture(tick.barMask); tick.barMaskOn = true end
            tick.barMask:ClearAllPoints(); tick.barMask:SetPoint("CENTER", self.frame, "CENTER", ms[5], ms[6])
            tick.barMask:SetSize(ms[1], ms[2]); tick.barMask:SetTexture(ms[3], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); tick.barMask:SetRotation(ms[4])
        elseif tick.barMaskOn then
            tick:RemoveMaskTexture(tick.barMask); tick.barMaskOn = false
        end
    end
    -- The absorb overlay: sized by the secret amount against the unit's max.
    function bar:SetAbsorb(unit)
        if not (self.geo and self.absorbOn) then return end
        if not unit then self.absorb:SetMinMaxValues(0, 1); self.absorb:SetValue(0) return end
        if GU.absorbMax then self.absorb:SetMinMaxValues(0, 1); self.absorb:SetValue(1) return end
        self.absorb:SetMinMaxValues(0, UnitHealthMax(unit))
        self.absorb:SetValue(UnitGetTotalAbsorbs(unit) or 0)
    end
    return bar
end

------------------------------------------------------------------------
-- WHOLE SEGMENTS (2026-09-29, the owner: segments that light one at a time,
-- never half-lit). A Rectangle bar with `segments` >= 2 and `segWhole` is drawn
-- as a ROW of window bars — the class resource's bar row, fed the ring's own
-- percent: segment i is whole once the value reaches i/n (the step TESTED with
-- a throwaway `/gu fillprobe`). Real gaps (the world shows through), each segment its own
-- track, its own rounded ends and gloss. The drain shift is gated per segment
-- so an unlit one never shows the 50% / 0% colour. The row answers the same
-- calls as a bar, so Refresh and the cast tick drive it as `r.fill` unchanged.
-- No absorb overlay, no fill end, no marker (there is no moving edge); the
-- rotation is not applied.
------------------------------------------------------------------------
local function WholeSegments(bc)
    return bc and bc.shape == "rect" and bc.segWhole and math.floor(bc.segments or 0) >= 2 or false
end
GU.WholeSegments = WholeSegments

local function NewRow(holder)
    local row = { bars = {}, n = 0, shown = false, shift = false }
    row.frame = CreateFrame("Frame", nil, holder)
    row.frame:SetAllPoints(holder)
    local function each(fn) for i = 1, row.n do fn(row.bars[i]) end end
    function row:Configure(bc)
        local n = math.min(30, math.floor(bc.segments or 2))
        local dir = bc.fillDir or "up"
        local vertical = dir == "up" or dir == "down"
        local bw, bh = bc.width or 200, bc.height or 24
        local L, A = vertical and bh or bw, vertical and bw or bh
        local gap = math.max(0, bc.segGap or 2)
        local seg = math.max(1, (L - (n - 1) * gap) / n)
        for i = n + 1, #self.bars do self.bars[i]:SetShown(false) end
        self.n = n
        for i = 1, n do
            local b = self.bars[i]
            if not b then b = NewBar(self.frame, true); self.bars[i] = b end
            local sbc = {}
            for k, v in pairs(bc) do sbc[k] = v end
            sbc.segments, sbc.segWhole, sbc.fillEnd, sbc.marker, sbc.rotation, sbc.absorb = nil, nil, nil, nil, 0, false
            if vertical then sbc.width, sbc.height = A, seg else sbc.width, sbc.height = seg, A end
            local step = (i - 1) * (seg + gap)
            b.frame:ClearAllPoints(); b.frame:SetSize(sbc.width, sbc.height)
            if dir == "right" then b.frame:SetPoint("LEFT", self.frame, "LEFT", step, 0)
            elseif dir == "left" then b.frame:SetPoint("RIGHT", self.frame, "RIGHT", -step, 0)
            elseif dir == "up" then b.frame:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, step)
            else b.frame:SetPoint("TOP", self.frame, "TOP", 0, -step) end
            b:Configure(sbc)
            local hi = i / n
            b:SetWindow(hi, { mid = Gated(PROFILE.mid, math.max(0, hi - 0.002)), low = Gated(PROFILE.low, math.max(0, hi - 0.002)) })
            b:SetShown(self.shown)
            b:SetShift(self.shift)
        end
        self.boxW, self.boxH, self.fillDir = bw, bh, dir
        return bw, bh
    end
    function row:SetShown(on) self.shown = on; self.frame:SetShown(on); each(function(b) b:SetShown(on) end) end
    function row:SetShift(on) self.shift = on; each(function(b) b:SetShift(on) end) end
    function row:SetTrack(c, a) each(function(b) b:SetTrack(c, a) end) end
    function row:SetColor(name, r, g, b2) each(function(b) b:SetColor(name, r, g, b2) end) end
    function row:SetSolid(c) each(function(b) b:SetSolid(c) end) end
    function row:SetGradient(c1, c2, ang) each(function(b) b:SetGradient(c1, c2, ang) end) end
    function row:SetFromUnit(unit, power) each(function(b) b:SetFromUnit(unit, power) end) end
    function row:SetFromPlain(pct, a) each(function(b) b:SetFromPlain(pct, a) end) end
    function row:SetFromDuration(d, drains) each(function(b) b:SetFromDuration(d, drains) end) end
    function row:SetAbsorb() end
    -- a segment is its own piece: the kick's mid-cast tint gates on its window
    function row:Layer(name, fn) each(function(b) local t = b:Tex(name); if t then fn(t, { alphaPts = b.alphaPts }) end end) end
    -- the kick tick across the whole row (plain arithmetic, as a bar's)
    function row:PlaceTick(tick, frac, thickness)
        local w, h = self.frame:GetSize()
        local vertical = (self.fillDir == "up" or self.fillDir == "down")
        if self.fillDir == "down" or self.fillDir == "left" then frac = 1 - frac end
        tick:ClearAllPoints(); tick:SetRotation(0)
        if tick.barMaskOn then tick:RemoveMaskTexture(tick.barMask); tick.barMaskOn = false end
        if vertical then tick:SetSize(w, thickness); tick:SetPoint("CENTER", self.frame, "BOTTOM", 0, frac * h)
        else tick:SetSize(thickness, h); tick:SetPoint("CENTER", self.frame, "LEFT", frac * w, 0) end
    end
    return row
end

local function PowerTypeColor(unit)
    local pType, pToken = UnitPowerType(unit)
    if issecretvalue and (issecretvalue(pType) or issecretvalue(pToken)) then return nil, pType end
    local c = pToken and PowerBarColor[pToken] or PowerBarColor[pType]
    if c then return { c.r, c.g, c.b }, pType end
    return nil, pType
end

-- The health fill's colour when `classColor` is on: the unit's class for a
-- player, the reaction colour for an NPC, grey when tapped. Any piece of this
-- can be SECRET: the class token on an identity-restricted unit (EUI's
-- reading of 12.1 — focus, ToT; Hub FINDINGS §17 says the target's identity
-- goes secret in combat on a restricted map). A secret class token STILL
-- colours the ring — `C_ClassColor.GetClassColor` accepts it and
-- `SetVertexColor` accepts the secret channels it returns (§18's sink table).
-- A secret DECISION (is it a player? which reaction?) cannot be branched on,
-- so it reports "no" and the ring keeps its own colour. Returns ok, r, g, b —
-- `ok` is a PLAIN boolean, the channels may be secret: never truth-test them,
-- only pass them to a setter.
local function secret(v) return issecretvalue and issecretvalue(v) end
local function UnitColor(unit)
    local isPlayer = UnitIsPlayer(unit)
    if secret(isPlayer) then return false end
    if isPlayer then
        local _, class = UnitClass(unit)
        local c
        if secret(class) then
            if C_ClassColor and C_ClassColor.GetClassColor then c = C_ClassColor.GetClassColor(class) end
        elseif class then
            c = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)) or RAID_CLASS_COLORS[class]
        end
        if c then return true, c.r, c.g, c.b end
        return false
    end
    local tapped = UnitIsTapDenied and UnitIsTapDenied(unit)
    if not secret(tapped) and tapped then return true, 0.6, 0.6, 0.6 end
    local reaction = UnitReaction(unit, "player")
    if not secret(reaction) and reaction then
        local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        if c then return true, c.r, c.g, c.b end
    end
    return false
end

GU.UnitColor = UnitColor
GU.PowerTypeColor = PowerTypeColor   -- the tab's colour chip previews the source with it


-- The player's class resource right now: power type, token, max points —
-- or nil when the class has none / the spec or form gives 0.
local function ClassResource()
    local _, class = UnitClass("player")
    local def = class and CLASS_RESOURCE[class]
    if not def then return nil end
    local max = UnitPowerMax("player", def.type)
    if issecretvalue and issecretvalue(max) then return nil end
    if not max or max < 1 then return nil end
    return def.type, def.token, math.min(max, GU.MAX_SEGMENTS)
end
function GU:ClassResource() return ClassResource() end
-- The player's class-resource colour as the tab previews it: the same rule
-- Refresh applies (a DK's runes are the class red, not PowerBarColor.RUNES).
function GU:ResourceColor()
    local _, token = ClassResource()
    if token == "RUNES" then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS.DEATHKNIGHT
        if c then return c.r, c.g, c.b end
    elseif token and PowerBarColor[token] then
        local c = PowerBarColor[token]; return c.r, c.g, c.b
    end
end

------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------
local function EnsureSkin()
    if Skin == nil then Skin = LibStub and LibStub("LibGloomSkin-1.0", true) or false end
    return Skin or nil
end

local function CreateUnitFrame(which)
    local f = CreateFrame("Frame", "GloomsUnitFrames_" .. which, UIParent)
    f.unit = which
    f.rings = {}
    for _, key in ipairs(GU.RINGS) do
        if DEFAULTS[which].rings[key] then
            -- Each ring lives on its own holder so it can have its own size and
            -- offset; the unit frame is the drag box around all of them.
            local h = CreateFrame("Frame", nil, f)
            h:SetPoint("CENTER")
            if key == "resource" then
                local r = { holder = h, segs = {}, segBars = {} }
                r.outlineHolder = CreateFrame("Frame", nil, h); r.outlineHolder:SetAllPoints(h)
                for i = 1, GU.MAX_SEGMENTS do
                    r.segs[i] = { track = NewArc(h, false), fill = NewArc(h, true), outline = NewArc(r.outlineHolder, false) }
                    r.segBars[i] = NewBar(h, true)     -- bar mode: one shape per point
                end
                f.rings[key] = r
            else
                local r = { holder = h, track = NewArc(h, false), fill = NewArc(h, true) }
                r.fillArc = r.fill
                -- the arc's OUTLINE: a plain, full arc on a sub-holder one level
                -- under the track (+1/+2) and its caps (+0)
                r.outlineHolder = CreateFrame("Frame", nil, h); r.outlineHolder:SetAllPoints(h)
                r.outline = NewArc(r.outlineHolder, false)
                -- bar mode: the same holder, the other renderer
                r.bar = NewBar(h)
                r.bar.hasAbsorb = (key == "health")
                if key == "health" then
                    -- The SHIELD TINT: a second copy of the fill arc in the shield
                    -- colour, above the fill, behind two frames — `gate`, whose
                    -- alpha is the absorb amount itself (see Refresh), and `inner`,
                    -- whose plain alpha is the user's tint opacity.
                    local gate = CreateFrame("Frame", nil, h); gate:SetAllPoints(h)
                    local inner = CreateFrame("Frame", nil, gate); inner:SetAllPoints(gate)
                    r.shield = { gate = gate, inner = inner, arc = NewArc(inner, true) }
                    gate:Hide()
                end
                f.rings[key] = r
            end
        end
    end
    -- the QA probe's readout (Debug); the user's texts are pieces, see _Text.lua
    f.debugText = f:CreateFontString(nil, "OVERLAY")
    f.debugText:SetPoint("CENTER", 0, 0)
    f.debugText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    frames[which] = f

    -- Anchor: an invisible frame the tab makes draggable; the ring follows it.
    local a = CreateFrame("Frame", "GloomsUnitFrames_" .. which .. "Anchor", UIParent)
    a:SetMovable(true); a:EnableMouse(false); a:SetClampedToScreen(true)
    a:RegisterForDrag("LeftButton")
    -- While dragging, the ring and outline follow the anchor every frame;
    -- the position is saved once, on release.
    local function follow(self)
        local cx, cy = self:GetCenter()
        local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
        if not (cx and cy) then return end
        -- the anchor is the PIECES' box, which may sit off the unit's centre
        local x, y = cx - sw / 2 - (f.bbX or 0), cy - sh / 2 - (f.bbY or 0)
        f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", x, y)
        local g = ghosts[which]
        g:ClearAllPoints(); g:SetPoint("CENTER", UIParent, "CENTER", x + (f.bbX or 0), y + (f.bbY or 0))
        return x, y
    end
    a:SetScript("OnDragStart", function(self)
        if editing ~= which then return end
        self:StartMoving()
        self:SetScript("OnUpdate", follow)
    end)
    a:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)
        local x, y = follow(self)
        if x then db[which].x, db[which].y = x, y end
        GU:ApplyLayout(which)
        GU:Notify("position", which)
    end)
    anchors[which] = a

    local g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("HIGH")   -- over the ring, under the Suite window (DIALOG)
    -- the unit's box: corner brackets 10 px outside (2026-09-30, the Hub's UI.gBrackets)
    GloomsHub.UI.gBrackets(g, 0, 1, 0.3, 0.9)
    g:Hide()
    ghosts[which] = g
    return f
end

-- The outline of an arc: the same arc grown by `w` px on every side —
-- outer edge, inner edge, and both ends (the span widened by the angle w
-- subtends at the band's middle) — drawn plain and full in the outline
-- colour under the track. `g` is the track's geometry table.
local OUTLINE_PX = { thin = 1, medium = 3, thick = 6 }
local function OutlineWidth(rc) return OUTLINE_PX[rc.outlineWidth or "medium"] or 3 end
local function ConfigureOutline(arc, holder, g, rc)
    local on = rc.enabled and rc.outline and true or false
    arc:SetShown(on)
    if not on then return end
    -- the outline's chunks sit at sub-holder +1/+2, so the sub-holder goes
    -- three under the ring's holder to land beneath the caps (+0) and the
    -- track (+1/+2); a ring at level < 3 ties, which only a unit at level 0 can produce
    holder:SetFrameLevel(math.max(0, holder:GetParent():GetFrameLevel() - 3))
    local w = OutlineWidth(rc)
    local outerR, innerR = ART_R * g.size / 2, math.max(0, g.inner) / 2
    local rMid = math.max(1, (outerR + innerR) / 2)
    local dDeg = math.deg(w / rMid)
    local sgn = g.clockwise and -1 or 1
    local g2 = {}
    for k, v in pairs(g) do g2[k] = v end
    g2.size = g.size + 2 * w / ART_R
    g2.inner = math.max(0, g.inner - 2 * w)
    g2.thickness = (g.thickness or 22) + 2 * w
    if (g.span or 180) < 360 then
        g2.start = g.start - sgn * dDeg
        g2.span = math.min(360, g.span + 2 * dDeg)
    end
    arc:Configure(g2)
    local c = rc.outlineColor or { 1, 1, 1 }
    arc:SetColor("base", c[1], c[2], c[3])
    arc:SetFromPlain(1, rc.outlineAlpha or 1)
end

-- The unit frame's extent: the union of its rings' boxes.
local function UnitExtent(cfg)
    local ext = 60
    for _, key in ipairs(GU.RINGS) do
        local rc = cfg.rings[key]
        if rc and rc.enabled then
            local size = rc.size
            if rc.mode == "bar" and rc.bar then
                local bw, bh = BarBox(rc.bar); size = math.max(bw, bh)
                if key == "resource" then size = math.max(size, size * GU.MAX_SEGMENTS) end   -- the row, generously
            end
            local off = (rc.mode == "bar" and rc.bar) and rc.bar or rc
            ext = math.max(ext, size + 2 * math.max(math.abs(off.dx or 0), math.abs(off.dy or 0)))
        end
    end
    return ext
end

-- Geometry + static styling from the config. Plain numbers only.
function GU:ApplyLayout(which)
    local f, cfg = frames[which], db and db[which]
    if not f or not cfg then return end
    local ext = UnitExtent(cfg)
    f:ClearAllPoints()
    f:SetSize(ext, ext)
    f:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)
    f:SetFrameStrata(cfg.strata or "MEDIUM")
    f:SetFrameLevel(cfg.level or 10)

    local bb   -- the rings' union box, relative to the unit's centre (the anchor + green outline)

    for i, key in ipairs(GU.RINGS) do
        local rc, r = cfg.rings[key], f.rings[key]
        if rc and r then   -- a unit may lack a ring (the target has no resource ring)
        -- Each ring owns a band of 16 frame levels, in GU.RINGS order, so
        -- overlapping rings never interleave their pieces: track +0..+2, fill
        -- +3..+6, the health ring's shield copy +11..+14, the kick tick +15.
        r.holder:SetFrameStrata(rc.strata or cfg.strata or "MEDIUM")
        -- An own level is the level of the display's LOWEST piece (the pieces
        -- sit at holder+1 up: 7 levels for a bar, 16 for an arc), so a
        -- display "at 131" and an Overlays graphic "at 131" are level — the
        -- owner, 2026-09-21, after an overlay landed inside the stack.
        r.holder:SetFrameLevel(rc.level and math.max(0, rc.level - 1) or (f:GetFrameLevel() + 1 + (i - 1) * 16))
        local artDef = GU.RING_TEXTURES[rc.texture] or GU.RING_TEXTURES.disc
        local art, ramp = artDef.path, artDef.ramp or GU.RING_TEXTURES.disc.ramp
        r.holder:SetSize(rc.size, rc.size)
        r.holder:ClearAllPoints()
        local off = (rc.mode == "bar" and rc.bar) and rc.bar or rc   -- each mode keeps its own offset
        local sx, sy = 0, 0
        if rc.mode == "bar" and rc.bar and key ~= "resource" then sx, sy = BarAnchorAdj(rc.bar) end
        r.px, r.py = (off.dx or 0) + sx, (off.dy or 0) + sy   -- kept: the unit box below reads these, not the frame
        r.holder:SetPoint("CENTER", f, "CENTER", r.px, r.py)
        local inner = rc.size - 2 * math.max(2, rc.thickness or 22)
        local isBar = rc.mode == "bar" and r.bar and rc.bar
        if key == "resource" then
            self:LayoutResource(which, rc, r, art, ramp, inner)
        elseif isBar then
            if key == "cast" then r.holder:SetShown(r.casting and true or false) end
            -- BAR MODE: the arcs go dark, the holder takes the bar's box, and
            -- `r.fill` IS the bar — Refresh drives whichever renderer is live
            -- through the same four calls (SetFromUnit / SetFromPlain / SetSolid / SetColor).
            -- WHOLE SEGMENTS: the row stands in for the bar (NewRow)
            local B = r.bar
            if WholeSegments(rc.bar) then
                r.row = r.row or NewRow(r.holder)
                B = r.row
                r.bar:SetShown(false)
            elseif r.row then
                r.row:SetShown(false)
            end
            r.fill = B
            r.track:SetShown(false); r.fillArc:SetShown(false)
            if r.shield then r.shield.gate:Hide() end
            r.outline:SetShown(false)
            B:SetShift(rc.shift and true or false)   -- before Configure: a row's segments take it as they are made
            local bw, bh = B:Configure(rc.bar)
            r.holder:SetSize(bw, bh)
            B:SetShown(rc.enabled)
            B:SetShift(rc.shift and true or false)
            B:SetTrack(rc.trackColor or { 1, 1, 1 }, rc.trackAlpha or 0.12)
            if rc.colorMode == "gradient" then B:SetGradient(rc.color, rc.color2, rc.gradientAngle)
            else B:SetSolid(rc.color) end
            B:SetColor("mid", rc.midColor[1], rc.midColor[2], rc.midColor[3])
            B:SetColor("low", rc.lowColor[1], rc.lowColor[2], rc.lowColor[3])
        else
        r.fill = r.fillArc
        if r.bar then r.bar:SetShown(false) end
        if r.row then r.row:SetShown(false) end
        if key == "cast" then r.holder:SetShown(r.casting and true or false) end
        r.track:SetShown(rc.enabled)
        r.fill:SetShown(rc.enabled)
        r.fill:SetShift(rc.shift and true or false)
        local g = { start = rc.start, span = rc.span, clockwise = rc.clockwise, size = rc.size, inner = inner,
                    thickness = rc.thickness, art = art, ramp = ramp, roundStart = rc.roundStart, roundEnd = rc.roundEnd }
        r.track:Configure(g)
        r.fill:Configure(g)
        ConfigureOutline(r.outline, r.outlineHolder, g, rc)
        local tc = rc.trackColor or { 1, 1, 1 }
        r.track:SetColor("base", tc[1], tc[2], tc[3])
        r.track:SetFromPlain(1, rc.trackAlpha or 0.12)
        -- Static colouring; the power ring may override the base per tick.
        if rc.colorMode == "gradient" then r.fill:SetGradient(rc.color, rc.color2, rc.gradientAngle)
        else r.fill:SetSolid(rc.color) end
        r.fill:SetColor("mid", rc.midColor[1], rc.midColor[2], rc.midColor[3])
        r.fill:SetColor("low", rc.lowColor[1], rc.lowColor[2], rc.lowColor[3])
        if r.shield then
            local sh = r.shield
            local on = rc.enabled and rc.shieldTint and true or false
            sh.gate:SetFrameLevel(r.holder:GetFrameLevel() + 7)
            sh.inner:SetFrameLevel(r.holder:GetFrameLevel() + 8)
            sh.gate:SetShown(on)
            if on then
                -- A wash: the shield colour fading to transparent. Automatic:
                -- along the arc's CHORD, from its start to its end, the fade as
                -- wide as the chord (an arc's chord midpoint always projects onto
                -- the centre along the chord, so a centred ramp lines up with any
                -- arc). A full ring has no chord and takes the manual settings.
                local sc = rc.shieldColor or { 0.45, 0.85, 1.0 }
                local ang, wPct
                if rc.shieldAuto ~= false and (rc.span or 180) < 360 then
                    local S = math.rad(rc.start or 0)
                    local E = S + (rc.clockwise and -1 or 1) * math.rad(rc.span or 180)
                    ang = math.deg(math.atan2(math.sin(S) - math.sin(E), math.cos(S) - math.cos(E)))
                    wPct = math.sin(math.rad(rc.span or 180) / 2) * 100
                else
                    ang, wPct = rc.shieldAngle or 180, rc.shieldWidth or 70
                end
                local g2 = {}
                for k, val in pairs(g) do g2[k] = val end
                g2.ramp = RampAt(wPct, ramp)
                sh.arc.rampOnly = true
                sh.arc:SetShown(true)
                sh.arc:SetShift(false)
                sh.arc:Configure(g2)
                sh.arc:SetGradient(sc, sc, ang)
                sh.inner:SetAlpha(rc.shieldAlpha or 0.8)
                sh.gate:SetAlpha(0)
            end
        end
        end
        end
    end

    -- The unit's drag box and green outline HUG its rings (2026-09-27): it was a
    -- square grown by every offset, which — with offsets out to 1500 — could
    -- cover the screen while editing. Each ring's box at its offset, unioned.
    for _, key in ipairs(GU.RINGS) do
        local rc, r = cfg.rings[key], f.rings[key]
        if rc and r and rc.enabled then
            -- plain numbers only: the frame's own geometry can turn secret (a text's did)
            local px, py = r.px, r.py
            local w, h = r.holder:GetSize()
            if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then w = nil end
            if px and w and w > 0 then
                local l, rr, b, t = px - w / 2, px + w / 2, py - h / 2, py + h / 2
                if bb then bb[1] = math.min(bb[1], l); bb[2] = math.max(bb[2], rr); bb[3] = math.min(bb[3], b); bb[4] = math.max(bb[4], t)
                else bb = { l, rr, b, t } end
            end
        end
    end
    bb = bb or { -30, 30, -30, 30 }
    f.bbX, f.bbY = (bb[1] + bb[2]) / 2, (bb[3] + bb[4]) / 2
    local a = anchors[which]
    a:ClearAllPoints(); a:SetSize(math.max(20, bb[2] - bb[1]), math.max(20, bb[4] - bb[3]))
    a:SetPoint("CENTER", UIParent, "CENTER", cfg.x + f.bbX, cfg.y + f.bbY)
    local g = ghosts[which]
    g:ClearAllPoints(); g:SetSize(math.max(20, bb[2] - bb[1]), math.max(20, bb[4] - bb[3]))
    g:SetPoint("CENTER", UIParent, "CENTER", cfg.x + f.bbX, cfg.y + f.bbY)

    EnsureTexts(cfg)
    self:LayoutTexts(f, cfg)
    EnsureAuras(cfg, which)
    -- Fenced: an aura-engine failure must never cost the rings or the other unit.
    local okA, errA = pcall(self.LayoutAuras, self, f, cfg, which)
    if not okA then
        GU.aurasError = errA
        if not GU.aurasErrorSaid then GU.aurasErrorSaid = true; Chat("aura groups failed to build: " .. tostring(errA)) end
    end

    self:Refresh(which)
    UpdateVisibility()
    if which == "player" then GU:ApplyBlizzardCastBar() end
end

------------------------------------------------------------------------
-- ★ BLIZZARD'S CAST BAR (2026-09-30, the owner: with EllesmereUI's player cast
-- bar off, Blizzard's came back — "ONLY the GU one", and NOT contingent on EUI
-- "in case I ever uninstall it"). While the player's cast display is on and
-- `rings.cast.hideBlizzard` isn't false (default: hide), PlayerCastingBarFrame
-- lives in a hidden frame — re-parented, not hidden, so nothing Blizzard does
-- to it shows it again; the hook puts it back if anything re-parents it (Edit
-- Mode, another addon restoring it). EllesmereUI does the same thing the same
-- way, so the two agree whether or not it is installed. Never during combat or
-- with Edit Mode open (re-parenting there runs Blizzard's layout code tainted —
-- EUI's own note); both re-apply on the way out. Switched off: back to the
-- parent it had.
------------------------------------------------------------------------
local blizzHidden, blizzOrigParent, blizzHooked
local function EditModeOpen() return EditModeManagerFrame and EditModeManagerFrame:IsShown() end
local function WantBlizzardHidden()
    local cfg = db and db.player
    local rc = cfg and cfg.rings and cfg.rings.cast
    return rc ~= nil and rc.enabled ~= false and rc.hideBlizzard ~= false
end
function GU:ApplyBlizzardCastBar()
    local bar = PlayerCastingBarFrame
    if not bar or InCombatLockdown() or EditModeOpen() then return end
    if not blizzHidden then blizzHidden = CreateFrame("Frame"); blizzHidden:Hide() end
    if WantBlizzardHidden() then
        if bar:GetParent() ~= blizzHidden then
            blizzOrigParent = bar:GetParent()
            bar:SetParent(blizzHidden)
        end
        if not blizzHooked then
            blizzHooked = true
            hooksecurefunc(bar, "SetParent", function(self, newParent)
                if newParent ~= blizzHidden and WantBlizzardHidden() then
                    C_Timer.After(0, function() GU:ApplyBlizzardCastBar() end)
                end
            end)
        end
    elseif bar:GetParent() == blizzHidden then
        bar:SetParent(blizzOrigParent or UIParent)
    end
end
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("EditMode.Exit", function() GU:ApplyBlizzardCastBar() end, GU)
end

-- The resource ring: N segments around the arc, each owning one point's
-- worth of the value (segment i answers to [ (i-1)/N, i/N ]), separated by
-- `gap` degrees. Unused segments hide.
function GU:LayoutResource(which, rc, r, art, ramp, inner)
    local pType, token, n = ClassResource()
    r.pType, r.n = pType, n or 0
    local on = rc.enabled and n ~= nil
    local gap = clamp(rc.gap or 0, 0, 30)
    local span = clamp(rc.span, 10, 360)
    local seg = n and math.max(1, (span - (n - 1) * gap) / n) or 0
    local sgn = rc.clockwise and -1 or 1
    local color = rc.color
    if rc.resourceColor and token == "RUNES" then
        -- Blizzard's RUNES entry is the grey of a generic rune; a DK's resource
        -- colour is the class red (the owner, 2026-09-20).
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS.DEATHKNIGHT
        if c then color = { c.r, c.g, c.b } end
    elseif rc.resourceColor and token and PowerBarColor[token] then
        local c = PowerBarColor[token]; color = { c.r, c.g, c.b }
    end
    -- The breakpoint: at `breakAt` points or more every segment turns
    -- breakColor — the `low` layer, given a step profile at that count (the
    -- `mid` layer is parked off). Same overall percent, same step, so all
    -- segments switch together.
    local brk = rc.breakEnabled and n and clamp(rc.breakAt or 5, 1, n) or nil
    local profiles
    if brk then
        local thr = brk / n
        profiles = {
            mid = { { 0, ALPHA_OFF }, { 1, ALPHA_OFF } },
            low = { { 0, ALPHA_OFF }, { math.max(0, thr - 0.002), ALPHA_OFF }, { thr, 1 }, { 1, 1 } },
        }
    end
    local tc = rc.trackColor or { 1, 1, 1 }
    local isBar = rc.mode == "bar" and rc.bar
    if isBar then
        -- BAR MODE: n copies of the silhouette in a row; segment i is whole
        -- once the value reaches i/n. The holder takes the row's extent.
        local bw, bh = BarBox(rc.bar)
        local gapPx = rc.rowGap or 4
        local along = (rc.rowDir == "left" or rc.rowDir == "right")
        local count = math.max(1, n or 1)
        local rowW = along and (count * bw + (count - 1) * gapPx) or bw
        local rowH = along and bh or (count * bh + (count - 1) * gapPx)
        r.holder:SetSize(rowW, rowH)
        r.rowBox = math.max(rowW, rowH)
        for i = 1, GU.MAX_SEGMENTS do
            local sg, b = r.segs[i], r.segBars[i]
            sg.track:SetShown(false); sg.fill:SetShown(false); sg.outline:SetShown(false)
            local live = on and i <= n
            if live then
                local step = (i - 1) * ((along and bw or bh) + gapPx)
                b.frame:ClearAllPoints(); b.frame:SetSize(bw, bh)
                if rc.rowDir == "right" then b.frame:SetPoint("LEFT", r.holder, "LEFT", step, 0)
                elseif rc.rowDir == "left" then b.frame:SetPoint("RIGHT", r.holder, "RIGHT", -step, 0)
                elseif rc.rowDir == "up" then b.frame:SetPoint("BOTTOM", r.holder, "BOTTOM", 0, step)
                else b.frame:SetPoint("TOP", r.holder, "TOP", 0, -step) end
                b:Configure(rc.bar)
                b:SetWindow(i / n, profiles)
                b:SetShown(true)
                b:SetShift(brk ~= nil)
                b:SetTrack(tc, rc.trackAlpha or 0.12)
                if rc.colorMode == "gradient" then b:SetGradient(color, rc.color2, rc.gradientAngle)
                else b:SetSolid(color) end
                if brk then
                    local bc = rc.breakColor
                    b:SetColor("low", bc[1], bc[2], bc[3]); b:SetColor("mid", bc[1], bc[2], bc[3])
                end
            else
                b:SetShown(false)
            end
        end
        return
    end
    r.rowBox = nil
    for i = 1, GU.MAX_SEGMENTS do
        local sg = r.segs[i]
        r.segBars[i]:SetShown(false)
        local live = on and i <= n
        sg.track:SetShown(live); sg.fill:SetShown(live); sg.outline:SetShown(false)
        sg.fill.profiles = profiles
        sg.fill:SetShift(brk ~= nil)
        if live then
            local start = rc.start + sgn * (i - 1) * (seg + gap)
            local lo, hi = (i - 1) / n, i / n
            local g = { start = start, span = seg, clockwise = rc.clockwise, size = rc.size, inner = inner,
                        thickness = rc.thickness, art = art, ramp = ramp, lo = lo, hi = hi,
                        roundStart = rc.roundStart, roundEnd = rc.roundEnd }
            sg.track:Configure(g)
            sg.fill:Configure(g)
            ConfigureOutline(sg.outline, r.outlineHolder, g, rc)
            sg.track:SetColor("base", tc[1], tc[2], tc[3])
            sg.track:SetFromPlain(1, rc.trackAlpha or 0.12)
            if rc.colorMode == "gradient" then sg.fill:SetGradient(color, rc.color2, rc.gradientAngle)
            else sg.fill:SetSolid(color) end
            if brk then
                local bc = rc.breakColor
                sg.fill:SetColor("low", bc[1], bc[2], bc[3])
                sg.fill:SetColor("mid", bc[1], bc[2], bc[3])
            end
        end
    end
end

-- Push the live values. The secrets go straight into setters.
function GU:Refresh(which)
    local f, cfg = frames[which], db and db[which]
    if not f or not cfg or not f:IsShown() then return end
    local unit = which
    if not UnitExists(unit) then
        for _, key in ipairs(GU.RINGS) do
            local r = f.rings[key]
            if r and r.fill then r.fill:SetFromPlain(0) end
            if r and r.bar then r.bar:SetAbsorb(nil) end
            if r and r.shield then r.shield.arc:SetFromPlain(0); r.shield.gate:SetAlpha(0) end
        end
        self:RefreshTexts(f, unit)
        return
    end

    -- Health ring. In solid mode with classColor on, the colour follows the
    -- unit (a target changes; a neutral turns hostile). A gradient WINS over
    -- the class colour — the owner's call, the two are exclusive — and the
    -- layout has already set it.
    local rc, r = cfg.rings.health, f.rings.health
    if rc.enabled then
        if rc.classColor and rc.colorMode ~= "gradient" then
            local ok, cr, cg, cb = UnitColor(unit)
            r.fill:SetSolid(ok and { cr, cg, cb } or rc.color)
        end
        r.fill:SetFromUnit(unit)
        if rc.mode == "bar" and r.bar then
            r.bar:SetAbsorb(unit)
        elseif rc.shieldTint and r.shield then
            -- The presence gate (measured 2026-09-19, /gu gate): a secret
            -- alpha of ZERO is ignored, so the frame is set to a PLAIN zero
            -- first and then to the absorb amount — shown iff shielded, and
            -- no number ever reaches Lua.
            r.shield.arc:SetFromUnit(unit)
            r.shield.gate:SetAlpha(0)
            r.shield.gate:SetAlpha(UnitGetTotalAbsorbs(unit) or 0)
        end
    end

    -- Power ring. A unit with no power type (a training dummy) reads 0.
    rc, r = cfg.rings.power, f.rings.power
    if rc.enabled then
        local pcol, pType = PowerTypeColor(unit)
        -- A unit with a power type but a max of 0 (a training dummy's rage)
        -- has no percent; the curve extrapolates garbage and the only place
        -- it can show is the overshoot at the arc's far end. Empty instead.
        local max = UnitPowerMax(unit, pType or 0)
        local noPower = not (issecretvalue and issecretvalue(max)) and (not max or max <= 0)
        local ok = (not noPower) and pcall(r.fill.SetFromUnit, r.fill, unit, pType or 0)
        if not ok then r.fill:SetFromPlain(0) end
        if rc.powerColor then r.fill:SetSolid(pcol or rc.color) end
    end

    -- Resource ring: every live segment reads the same percent through its own window.
    rc, r = cfg.rings.resource, f.rings.resource
    if rc and r and rc.enabled and r.pType then
        -- Runes: UnitPowerPercent does not take them (the ring stayed empty on the
        -- DK, 2026-09-20), so count the READY runes through GetRuneCooldown and feed
        -- the plain fraction — each segment's window fills in turn. A secret answer
        -- falls back to the percent route rather than guessing.
        local plain
        if Enum.PowerType.Runes and r.pType == Enum.PowerType.Runes and GetRuneCooldown then
            local ready, total = 0, 0
            for i = 1, 6 do
                local ok, _, _, runeReady = pcall(GetRuneCooldown, i)
                if not ok or (issecretvalue and issecretvalue(runeReady)) then ready = nil; break end
                if runeReady ~= nil then total = total + 1; if runeReady then ready = ready + 1 end end
            end
            if ready and total > 0 then plain = ready / total end
        end
        for i = 1, r.n do
            local seg = (rc.mode == "bar" and rc.bar) and r.segBars[i] or r.segs[i].fill
            if plain then seg:SetFromPlain(plain)
            else
                local ok = pcall(seg.SetFromUnit, seg, unit, r.pType)
                if not ok then seg:SetFromPlain(0) end
            end
        end
    end

    self:RefreshTexts(f, unit)
    self:RefreshCast(which)
end

-- The player's interrupt, for colouring a target's cast. Table and
-- resolution order from EllesmereUI_Kick (a summoned demon's interrupt wins).
local KICK_SPELLS = {
    DEATHKNIGHT = { 47528 }, WARRIOR = { 6552 }, WARLOCK = { 19647, 89766, 119910, 1276467, 132409 },
    SHAMAN = { 57994 }, ROGUE = { 1766 }, PRIEST = { 15487 }, PALADIN = { 31935, 96231 },
    MONK = { 116705 }, MAGE = { 2139 }, HUNTER = { 187707, 147362 }, EVOKER = { 351338 },
    DRUID = { 38675, 78675, 106839 }, DEMONHUNTER = { 183752 },
}
local activeKick
local function RefreshKick()
    activeKick = nil
    local list = KICK_SPELLS[UnitClassBase("player") or ""]
    if not (list and C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook) then return end
    local pet, own
    for _, id in ipairs(list) do
        if Enum.SpellBookSpellBank and C_SpellBook.IsSpellKnownOrInSpellBook(id, Enum.SpellBookSpellBank.Pet) then pet = id
        elseif C_SpellBook.IsSpellKnownOrInSpellBook(id) then own = id end
    end
    activeKick = pet or own
end

-- A target cast's colour by interrupt state, secret-safe: the "kick ready"
-- boolean may be secret, so the engine picks the channel values
-- (EvaluateColorValueFromBoolean); a secret "not interruptible" flag nests
-- the same way, falling back to the ready blend if the nest is refused.
local function KickColor(rc, locked)
    local base, cd, lk = rc.color, rc.kickCDColor, rc.lockedColor
    local r, g, b = base[1], base[2], base[3]
    if activeKick and C_Spell.GetSpellCooldownDuration and C_CurveUtil.EvaluateColorValueFromBoolean then
        local d = C_Spell.GetSpellCooldownDuration(activeKick)
        if d and d.IsZero then
            local ready = d:IsZero()
            -- (boolean, value if TRUE, value if FALSE)
            r = C_CurveUtil.EvaluateColorValueFromBoolean(ready, base[1], cd[1])
            g = C_CurveUtil.EvaluateColorValueFromBoolean(ready, base[2], cd[2])
            b = C_CurveUtil.EvaluateColorValueFromBoolean(ready, base[3], cd[3])
        end
    end
    if locked ~= nil then
        if issecretvalue and issecretvalue(locked) then
            local ok, r2, g2, b2 = pcall(function()
                return C_CurveUtil.EvaluateColorValueFromBoolean(locked, lk[1], r),
                       C_CurveUtil.EvaluateColorValueFromBoolean(locked, lk[2], g),
                       C_CurveUtil.EvaluateColorValueFromBoolean(locked, lk[3], b)
            end)
            if ok then r, g, b = r2, g2, b2 end
        elseif locked then
            r, g, b = lk[1], lk[2], lk[3]
        end
    end
    return r, g, b
end

------------------------------------------------------------------------
-- Casting. The player's cast times are PLAIN (measured 2026-09-19: name,
-- start, end, the duration object's total and remaining), so the ring is
-- ordinary clock arithmetic per frame. A target's ARE secret on a restricted
-- map — start, end and total alike (delve, 2026-09-20) — so there the duration
-- object drives the ring's percent curves itself, through
-- EvaluateElapsedPercent / EvaluateRemainingPercent (arc:SetFromDuration).
-- The ring hides only if no duration object exists at all.
------------------------------------------------------------------------
local function CastState(unit)
    local name, _, _, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(unit)
    local channel = false
    if not name then
        name, _, _, startMS, endMS, _, notInterruptible = UnitChannelInfo(unit)
        channel = name and true or false
    end
    if not name then return nil end
    return { name = name, startMS = startMS, endMS = endMS, channel = channel, locked = notInterruptible }
end

-- Preview: while the tab's Cast section is open for a unit, its ring runs a
-- fake 5s cast on repeat so it can be sized and styled without casting.
local castPreview = {}
function GU:SetCastPreview(which, on)
    castPreview[which] = on and true or nil
    self:RefreshCast(which)
end

-- The kick tick: a short radial bar parked at 3 o'clock on the band, rotated
-- about the ring's centre to where the interrupt returns (the arc's start
-- angle is folded into the curve, so its orientation stays radial).
local function EnsureTick(r)
    if r.tick then return r.tick end
    local fr = CreateFrame("Frame", nil, r.holder)
    fr:SetAllPoints(r.holder)
    fr:SetFrameLevel(r.holder:GetFrameLevel() + 15)
    local t = fr:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\WHITE8x8")
    r.tick, r.tickFrame = t, fr
    return t
end

local function HideKickExtras(r)
    if r.tick then r.tick:Hide() end
    if r.fill.shift then r.fill:SetShift(false) end
end

-- Mid-cast: the kick's cooldown object evaluated against "back before this
-- cast ends". Only for a cast with PLAIN times and a PLAIN interruptible
-- flag (a secret flag may not decide what shows).
local function KickExtras(r, rc, st, pct)
    local locked = st.locked
    if not activeKick or not st.plain or (issecretvalue and issecretvalue(locked)) or locked
       or not (rc.midCastEnabled or rc.kickTick) or not C_Spell.GetSpellCooldownDuration then
        HideKickExtras(r); return
    end
    local d = C_Spell.GetSpellCooldownDuration(activeKick)
    if not (d and d.EvaluateRemainingDuration) then HideKickExtras(r); return end
    local nowS = GetTime()
    local startS, endS = st.startMS / 1000, st.endMS / 1000
    local castRem = endS - nowS
    if castRem <= 0.05 then HideKickExtras(r); return end
    -- alpha over the kick's remaining seconds: on between "not already ready"
    -- and "back before the cast ends"
    local a = CurveFrom({ { 0, ALPHA_OFF }, { 0.05, ALPHA_OFF }, { 0.06, 1 }, { castRem, 1 }, { castRem + 0.01, ALPHA_OFF }, { castRem + 1000, ALPHA_OFF } })
    local fill = r.fill
    if rc.midCastEnabled then
        if not fill.shift then fill:SetShift(true) end
        local mc = rc.midCastColor
        fill:SetColor("mid", mc[1], mc[2], mc[3])
        -- ★ Gated per piece: a piece the fill has not reached (the empty
        -- second half of a 360° ring, a cap) shows nothing but its 1.5° lead
        -- overlap at the boundary, and painting the tint there put an orange
        -- slice at 12 o'clock (measured 2026-09-20). The cast percent is PLAIN
        -- on this path, so the piece's own base gate decides in Lua.
        fill:Layer("mid", function(t, piece)
            if not t:IsShown() then return end
            local gate = piece.PlaceTick and 1   -- a bar is one piece, always reached
                or (piece.alphaPts and piece.alphaPts.base and Eval(piece.alphaPts.base, pct)) or ALPHA_OFF
            if gate <= ALPHA_OFF then t:SetAlpha(ALPHA_OFF)
            else t:SetAlpha(d:EvaluateRemainingDuration(a, ALPHA_OFF)) end
        end)
        fill:Layer("low", function(t) if t:IsShown() then t:SetAlpha(ALPHA_OFF) end end)
    elseif fill.shift then
        fill:SetShift(false)
    end
    if rc.kickTick and fill.PlaceTick then
        -- a BAR: the tick sits at the fraction of the cast where the kick returns
        local tick = EnsureTick(r)
        local kc = rc.kickTickColor
        tick:SetVertexColor(kc[1], kc[2], kc[3], 1)
        tick:Show()
        local total = math.max(0.001, endS - startS)
        -- the return time is secret-safe only through the object; the PLACE
        -- is plain arithmetic on the cast's clock, so it is evaluated as a
        -- rotation-free alpha gate plus a position from the plain remaining
        -- kick time, which C_Spell.GetSpellCooldown gives on the plain path
        local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(activeKick)
        local kickRem = cd and cd.startTime and cd.duration and (cd.startTime + cd.duration - nowS) or 0
        if issecretvalue and issecretvalue(kickRem) then tick:Hide() return end
        local x = (nowS - startS + math.max(0, kickRem)) / total
        if st.channel and rc.channelDrains then x = 1 - x end
        fill:PlaceTick(tick, clamp(x, 0, 1), 2)
        tick:SetAlpha(d:EvaluateRemainingDuration(a, ALPHA_OFF))
    elseif rc.kickTick and fill.geo then
        local geo = fill.geo
        local tick = EnsureTick(r)
        local w = geo.capD
        tick:SetSize(w, 3)
        tick:ClearAllPoints(); tick:SetPoint("CENTER", r.tickFrame, "CENTER", geo.rMid, 0)
        local kc = rc.kickTickColor
        tick:SetVertexColor(kc[1], kc[2], kc[3], 1)
        tick:Show()
        local pivot = CreateVector2D(0.5 - geo.rMid / w, 0.5)
        -- angle where the kick returns, in the arc's drawn terms, + the start angle
        local total = math.max(0.001, endS - startS)
        local elapsed = nowS - startS
        local function ang(rem)
            local x = (elapsed + rem) / total
            if st.channel and rc.channelDrains then x = 1 - x end
            return geo.S + geo.sgn * clamp(x * geo.spanFull - geo.off, 0, geo.span)
        end
        local remA = clamp(total * (geo.off / geo.spanFull) - elapsed, 0, 1e6)
        local remB = clamp(total * ((geo.off + geo.span) / geo.spanFull) - elapsed, 0, 1e6)
        local xs = { 0, remA, remB, remB + 1000 }
        table.sort(xs)
        local pts, last = {}, nil
        for _, x in ipairs(xs) do if x ~= last then pts[#pts + 1] = { x, ang(x) }; last = x end end
        -- ★ No second argument on a ROTATION evaluation: the "modifier" is
        -- validated to 0..1 (an alpha passes, an angle in radians is "bad
        -- argument #3" — measured 2026-09-20, the tick's first outing on a
        -- class with an interrupt). The alpha curves may keep theirs.
        tick:SetRotation(d:EvaluateRemainingDuration(CurveFrom(pts)), pivot)
        tick:SetAlpha(d:EvaluateRemainingDuration(a, ALPHA_OFF))
    elseif r.tick then
        r.tick:Hide()
    end
end

-- The unit's current cast state as the ring sees it (the text pieces read it).
function GU:CastInfo(which)
    local f = frames[which]
    local r = f and f.rings.cast
    local st = r and r.cast
    if st and st.fake then return nil end
    return st
end

local function CastTick(holder)
    local which, r, rc = holder.unit, holder.ring, holder.cfg
    local st = r.cast
    if not st then return end
    GU:RefreshTexts(frames[which], which, "cast")
    -- Colour first, geometry second: the alpha gate must be the last writer.
    local kickAware = which == "target" and rc.kickAware and not st.fake
    if kickAware then r.fill:SetColor("base", KickColor(rc, st.locked)) end
    local p
    if st.plain then
        local now = GetTime() * 1000
        if st.fake and now >= st.endMS then st.startMS, st.endMS = now, now + 5000 end
        p = (now - st.startMS) / math.max(1, st.endMS - st.startMS)
        p = clamp(p, 0, 1)
        if st.channel and rc.channelDrains then p = 1 - p end
        r.fill:SetFromPlain(p)
    elseif st.duration then
        r.fill:SetFromDuration(st.duration, st.channel and rc.channelDrains)
    end
    if kickAware then KickExtras(r, rc, st, p or 0) end
end

function GU:RefreshCast(which)
    local f, cfg = frames[which], db and db[which]
    if not f or not cfg then return end
    local rc, r = cfg.rings.cast, f.rings.cast
    if not (rc and r) then return end
    local st = rc.enabled and UnitExists(which) and CastState(which) or nil
    local route = (not rc.enabled) and "ring switched off" or (not st) and "no cast" or nil   -- for the trace
    if not st and rc.enabled and castPreview[which] then
        local now = GetTime() * 1000
        st = { name = "preview", startMS = now, endMS = now + 5000, channel = false, locked = false, fake = true }
    end
    r.cast = nil
    if st then
        local secretTimes = issecretvalue and (issecretvalue(st.startMS) or issecretvalue(st.endMS))
        if not secretTimes then
            st.plain = true
            route = "PLAIN times"
        else
            local d = (st.channel and UnitChannelDuration or UnitCastingDuration)(which)
            if d and d.EvaluateElapsedPercent and d.EvaluateRemainingPercent then
                st.duration = d
                route = "DURATION object (times secret; drawn from its fraction)"
            else
                st = nil   -- nothing honest to draw
                route = d and "HIDDEN — duration object has no percent evaluator" or "HIDDEN — no duration object"
            end
        end
    end
    r.cast = st
    r.casting = st ~= nil
    -- QA trace (`/gu casttrace`): a target's casts in a delve are too quick to
    -- catch with `/gu debug target`, so say in chat which route each cast took
    -- the moment it changes — plain times, the duration object, or hidden.
    if GU.castTrace and which == "target" and r.lastRoute ~= route then
        r.lastRoute = route
        local name = st and st.name
        if name and issecretvalue and issecretvalue(name) then name = "(secret name)" end
        Chat(("cast trace: %s%s"):format(route, name and (" — " .. tostring(name)) or ""))
    end
    -- colour: a target's cast by interrupt state (re-evaluated per tick, the
    -- kick's cooldown moves); otherwise the ring's own colouring
    if st then
        if which == "target" and rc.kickAware and not st.fake then
            r.fill:SetSolid(rc.color)
            r.fill:SetColor("base", KickColor(rc, st.locked))
        elseif rc.colorMode == "gradient" then r.fill:SetGradient(rc.color, rc.color2, rc.gradientAngle)
        else r.fill:SetSolid(rc.color) end
    end
    r.holder:SetShown(r.casting and f:IsShown())
    r.holder.unit, r.holder.ring, r.holder.cfg = which, r, rc
    r.holder:SetScript("OnUpdate", r.casting and CastTick or nil)
    if not (r.casting and which == "target" and rc.kickAware and not st.fake) then HideKickExtras(r) end
    if r.casting then CastTick(r.holder) else r.fill:SetFromPlain(0); GU:RefreshTexts(f, which, "cast") end
end

------------------------------------------------------------------------
-- Visibility
------------------------------------------------------------------------
UpdateVisibility = function()
    if not initialised then return end
    local inCombat = UnitAffectingCombat("player")
    local hasTarget = UnitExists("target")
    for _, which in ipairs(GU.UNITS) do
        local cfg, f = db[which], frames[which]
        local cond = cfg.showCondition or "always"
        local show
        if cond == "combat" then show = inCombat
        elseif cond == "target" then show = hasTarget
        elseif cond == "combat_or_target" then show = inCombat or hasTarget
        elseif cond == "never" then show = false   -- hidden, full stop — even while the tab is editing it (the owner, 2026-09-21)
        else show = true end
        if which == "target" and not hasTarget and editing ~= "target" then show = false end
        f:SetShown(show)
        if show then GU:Refresh(which) end
        if f.rings.cast then f.rings.cast.holder:SetShown(show and f.rings.cast.casting or false) end
    end
end

------------------------------------------------------------------------
-- API for the tab
------------------------------------------------------------------------
function GU:Config(which) return db and db[which] or nil end
function GU:Frame(which) return frames[which] end
function GU:Defaults(which) return DEFAULTS[which] end
function GU:IsReady() return initialised end

function GU:Nudge(which, dx, dy)
    local cfg = db[which]; if not cfg then return end
    cfg.x, cfg.y = cfg.x + dx, cfg.y + dy
    self:ApplyLayout(which)
    self:Notify("position", which)
end


function GU:SetStrata(which, strata)
    db[which].strata = strata; self:ApplyLayout(which)
end

function GU:SetCondition(which, cond)
    db[which].showCondition = cond; self:ApplyLayout(which)
end

-- Copy every setting but the position from the other unit. Rings the
-- destination lacks (the target has no resource ring) are left alone.
local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = DeepCopy(x) end
    return t
end
function GU:CopyFrom(which, from)
    local dst, src = db[which], db[from]
    if not (dst and src) or which == from then return end
    for k, v in pairs(src) do
        if k ~= "x" and k ~= "y" and k ~= "rings" then dst[k] = DeepCopy(v) end
    end
    for key, rc in pairs(src.rings) do
        if dst.rings[key] then dst.rings[key] = DeepCopy(rc) end
    end
    self:ApplyLayout(which)
end

function GU:Reset(which)
    db[which] = nil
    ApplyDefaults(db, DEFAULTS)
    self:ApplyLayout(which)
end

------------------------------------------------------------------------
-- Profiles (the data model is described above DEFAULTS).
------------------------------------------------------------------------
function GU:CharKey()
    local name, realm = UnitName("player"), GetRealmName()
    return (name or "?") .. "-" .. (realm or "?")
end

local function SortedNames(t)
    local o = {}
    for name in pairs(t or {}) do o[#o + 1] = name end
    table.sort(o)
    return o
end
function GU:ProfileNames() return SortedNames(root and root.profiles) end
-- The characters bound to a profile (their keys), for the delete gate.
function GU:ProfileUsers(name)
    local o = {}
    for char, p in pairs((root and root.charProfiles) or {}) do if p == name then o[#o + 1] = char end end
    return o
end

-- Fill a profile out to the current shape: defaults, then the field
-- migrations, then the two seeded lists. Every profile passes through here
-- before it is drawn, whether migrated, created, copied or switched to.
local BAR_SHAPE_MIGRATE = { circle = "orb", pill21 = "pill", pill32 = "pill" }
local function PrepareProfile(prof)
    ApplyDefaults(prof, DEFAULTS)
    for _, which in ipairs(GU.UNITS) do
        for _, key in ipairs(GU.RINGS) do
            local rc = prof[which].rings[key]
            if rc then
                -- Same-day migration (2026-09-19): "shift" was briefly a colour MODE; it is a toggle now.
                if rc.colorMode == "shift" then rc.colorMode, rc.shift = "solid", true end
                if rc.texture == "ring" then rc.texture = "disc" end
                -- Same-day migration (2026-09-21): bar shapes came from the button
                -- catalog for a few hours; they are their own family now.
                -- Same-day migration (2026-09-21): the outline was the bar's for an hour
                if rc.bar and rc.bar.rim ~= nil then
                    rc.outline, rc.outlineWidth = rc.bar.rim, rc.bar.rimWidth or "medium"
                    rc.outlineColor, rc.outlineAlpha = rc.bar.rimColor or rc.outlineColor, rc.bar.rimAlpha or 1
                    rc.bar.rim, rc.bar.rimWidth, rc.bar.rimColor, rc.bar.rimAlpha = nil, nil, nil, nil
                end
                if rc.bar and rc.bar.shape and rc.bar.shape ~= "rect" then
                    local hub = _G.GloomsHub
                    if not (hub and hub.BAR_SHAPES and hub.BAR_SHAPES[rc.bar.shape]) then
                        rc.bar.shape = BAR_SHAPE_MIGRATE[rc.bar.shape] or "orb"
                    end
                end
            end
        end
        EnsureTexts(prof[which]); EnsureAuras(prof[which], which)
    end
    return prof
end

-- The profile this character is bound to. An unbound character lands on
-- "Default" — the migrated account-wide config, so nothing the owner built
-- is lost on any character — else on the first name; login writes the binding.
function GU:ActiveProfileName()
    if not (root and root.profiles) then return nil end
    local name = root.charProfiles and root.charProfiles[GU:CharKey()]
    if name and root.profiles[name] then return name end
    if root.profiles.Default then return "Default" end
    return SortedNames(root.profiles)[1]
end

-- Point the engine at a profile and redraw both units. The frames already
-- exist; ApplyLayout re-reads db[which] for rings, texts, aura groups and
-- the cast holder's config, so nothing else caches the old table.
local function LoadProfile(name)
    db = PrepareProfile(root.profiles[name])
    if initialised then
        for _, which in ipairs(GU.UNITS) do GU:ApplyLayout(which) end
        GU:Notify("profile")
    end
end

-- The active profile's table itself, and a full re-apply — the Hub's UNDO
-- (Undo.lua, 2026-09-30) snapshots the one and puts it back through the other.
function GU:ActiveProfileTable() return db end

-- ★ The two unit frames are ANCHORS other tools may attach to (the Hub's
-- Anchors.lua, 2026-09-30 — gloomUI's groups). A frame's centre is the unit's
-- saved position (cfg.x / cfg.y), so ring edits never move what is attached,
-- and it follows a drag live.
if GloomsHub and GloomsHub.RegisterAnchor then
    GloomsHub:RegisterAnchor("uf:player", { label = "Player Frame", frame = function() return GU:Frame("player") end })
    GloomsHub:RegisterAnchor("uf:target", { label = "Target Frame", frame = function() return GU:Frame("target") end })
end
function GU:ReapplyAll()
    if not initialised then return end
    for _, which in ipairs(GU.UNITS) do GU:ApplyLayout(which) end
    GU:Notify("profile")
end

function GU:SetActiveProfile(name)
    if not (root and root.profiles[name]) then return false end
    root.charProfiles = root.charProfiles or {}
    root.charProfiles[self:CharKey()] = name
    LoadProfile(name)
    return true
end

-- New = the factory look (Copy is how you start from THIS look).
function GU:CreateProfile(name)
    if not root or root.profiles[name] then return false end
    root.profiles[name] = PrepareProfile({})
    return true
end

function GU:CopyProfile(src, new)
    if not (root and root.profiles[src]) or root.profiles[new] then return false end
    root.profiles[new] = DeepCopy(root.profiles[src])
    return true
end

function GU:RenameProfile(old, new)
    if not (root and root.profiles[old]) then return false end
    if old == new then return true end   -- the dialog prefills the name; OK-without-typing is not a collision
    if root.profiles[new] then return false end
    root.profiles[new] = root.profiles[old]
    root.profiles[old] = nil
    for char, p in pairs(root.charProfiles or {}) do
        if p == old then root.charProfiles[char] = new end
    end
    return true
end

-- Never deletes the last profile. Every character bound to the deleted one
-- moves to the fallback, returned so the caller can SAY where this character
-- landed rather than moving it silently.
function GU:DeleteProfile(name)
    if not (root and root.profiles[name]) then return false end
    if #SortedNames(root.profiles) <= 1 then return false end
    local wasActive = (self:ActiveProfileName() == name)
    root.profiles[name] = nil
    local fallback = root.profiles.Default and "Default" or SortedNames(root.profiles)[1]
    for char, p in pairs(root.charProfiles or {}) do
        if p == name then root.charProfiles[char] = fallback end
    end
    if wasActive then LoadProfile(fallback) end
    return true, fallback
end

-- While the tab edits a unit its anchor is draggable and its outline shows.
-- ★ PER-PIECE DRAGGING (2026-09-27, the owner: "per piece dragging, applied
-- to the offsets"). While a ring, text or aura-group section is open, a lime
-- handle sits on that piece — pinned to the piece's own frame, so it follows
-- it — and dragging it moves the piece live; letting go writes the offset
-- (a ring's dx/dy in the live mode's table, a text's or group's x/y) and
-- re-lays the unit out. The unit itself still drags by its green box.
-- kind = "ring" (key = the ring) | "text" (key = its index) | "aura" (its
-- index) | nil (no piece handle).
-- ★ A piece is moved from its SAVED offset, never from what the frame reports:
-- a text showing a secret value makes its FontString's own geometry secret
-- (GetPoint returned secret numbers — BugSack, 2026-09-27), and no arithmetic
-- is allowed on those. Each kind re-anchors itself the way its layout does.
local handles = {}
local function DragHandle(which)
    local h = handles[which]
    if h then return h end
    h = CreateFrame("Frame", nil, UIParent)
    h:SetFrameStrata("HIGH"); h:SetFrameLevel(100)
    h:EnableMouse(true); h:Hide()
    -- corner brackets 10 px outside, not a box over the piece (the owner,
    -- 2026-09-30 — the Hub's UI.gBrackets); the drag area is still the piece
    GloomsHub.UI.gBrackets(h, 0.44, 0.93, 0.25, 0.9)
    local function cursor() local x, y = GetCursorPosition(); local s = UIParent:GetEffectiveScale(); return x / s, y / s end
    local function finish(self)
        local st = self.st
        self:SetScript("OnUpdate", nil)
        if not (st and st.moving) then return end
        st.moving = false
        local x, y = cursor()
        local dx, dy = math.floor(x - st.cx + 0.5), math.floor(y - st.cy + 0.5)
        st.tbl[st.fx] = (st.ox or 0) + dx
        st.tbl[st.fy] = (st.oy or 0) + dy
        GU:ApplyLayout(which)
        GU:Notify("piece", which)
        GU:SetDragPiece(which, st.kind, st.key)   -- re-pin to the re-laid-out piece
    end
    h:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or not self.st then return end
        local st = self.st
        st.cx, st.cy = cursor()
        st.ox, st.oy = st.tbl[st.fx] or 0, st.tbl[st.fy] or 0
        st.moving = true
        self:SetScript("OnUpdate", function(me)
            if not IsMouseButtonDown("LeftButton") then finish(me); return end
            local x, y = cursor()
            st.place(st.ox + x - st.cx, st.oy + y - st.cy)
        end)
    end)
    h:SetScript("OnMouseUp", function(self) finish(self) end)
    handles[which] = h
    return h
end

function GU:SetDragPiece(which, kind, key)
    for _, hh in pairs(handles) do if not (hh.st and hh.st.moving) then hh:Hide(); hh.st = nil end end
    if not (which and kind and editing == which) then return end
    local f, cfg = frames[which], db and db[which]
    if not (f and cfg) then return end
    local h = DragHandle(which)
    if h.st and h.st.moving then return end
    local st = { kind = kind, key = key }
    h:ClearAllPoints()
    if kind == "ring" then
        local rc, r = cfg.rings[key], f.rings[key]
        if not (rc and r and rc.enabled and r.holder:IsShown()) then return end
        st.tbl = (rc.mode == "bar" and rc.bar) and rc.bar or rc
        st.fx, st.fy = "dx", "dy"
        -- the bar's box sits off its canvas centre by BarBox's offset (ApplyLayout)
        local sx, sy = 0, 0
        if rc.mode == "bar" and rc.bar and key ~= "resource" then sx, sy = BarAnchorAdj(rc.bar) end
        st.place = function(x, y) r.holder:ClearAllPoints(); r.holder:SetPoint("CENTER", f, "CENTER", x + sx, y + sy) end
        h:SetAllPoints(r.holder)
    elseif kind == "text" then
        local tc, p = cfg.texts and cfg.texts[key], f.texts and f.texts[key]
        if not (tc and p and p.frame:IsShown()) then return end
        st.tbl, st.fx, st.fy = tc, "x", "y"
        local just = tc.justify or "CENTER"   -- as GU:LayoutTexts anchors it
        st.place = function(x, y) p.fs:ClearAllPoints(); p.fs:SetPoint(just, f, "CENTER", x, y) end
        h:SetPoint("TOPLEFT", p.fs, "TOPLEFT", -4, 4); h:SetPoint("BOTTOMRIGHT", p.fs, "BOTTOMRIGHT", 4, -4)
    elseif kind == "aura" then
        local ac = cfg.auras and cfg.auras[key]
        -- ★ not `self.AuraPreviewBox and self:AuraPreviewBox(…)`: an `and` keeps only
        -- the call's FIRST value
        if not self.AuraPreviewBox then return end
        local pv, anchor, w, hh = self:AuraPreviewBox(which, ac)
        if not pv then return end
        local g = f.auras and f.auras[key]
        st.tbl, st.fx, st.fy = ac, "x", "y"
        st.place = function(x, y)   -- the preview and the live container, as the aura layout anchors them
            pv:ClearAllPoints(); pv:SetPoint(anchor, f, "CENTER", x, y)
            if g and g.container then g.container:ClearAllPoints(); g.container:SetPoint(anchor, f, "CENTER", x, y) end
        end
        h:SetSize(math.max(8, w), math.max(8, hh)); h:SetPoint(anchor, pv, "CENTER")
    else
        return
    end
    h.st = st
    h:Show()
end

-- ARROW-KEY NUDGES for a PIECE (the Hub's key frame, 2026-09-30): whatever
-- carries the lime drag handle right now (the open section's ring, text or
-- aura group) moves by (dx, dy) — written to the same saved offset a drag
-- writes. false = no piece handle is up.
function GU:NudgePiece(which, dx, dy)
    local h = handles[which]
    local st = h and h:IsShown() and h.st
    if not (st and st.tbl and st.fx) then return false end
    st.tbl[st.fx] = (st.tbl[st.fx] or 0) + dx
    st.tbl[st.fy] = (st.tbl[st.fy] or 0) + dy
    self:ApplyLayout(which)
    self:Notify("piece", which)
    self:SetDragPiece(which, st.kind, st.key)
    return true
end

function GU:SetEditing(which)
    if which ~= editing then self:SetDragPiece(nil) end
    editing = which
    for _, u in ipairs(GU.UNITS) do
        local on = (u == which)
        anchors[u]:EnableMouse(on)
        ghosts[u]:SetShown(on)
    end
    UpdateVisibility()
end

function GU:OnChange(fn) listeners[#listeners + 1] = fn end
function GU:Notify(what, which) for _, fn in ipairs(listeners) do fn(what, which) end end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterUnitEvent("UNIT_HEALTH", "player", "target")
ev:RegisterUnitEvent("UNIT_MAXHEALTH", "player", "target")
ev:RegisterUnitEvent("UNIT_POWER_UPDATE", "player", "target")
ev:RegisterUnitEvent("UNIT_MAXPOWER", "player", "target")
ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player", "target")
ev:RegisterEvent("RUNE_POWER_UPDATE")   -- a DK's rune readiness (no unit arg; player only)
ev:RegisterUnitEvent("UNIT_FACTION", "player", "target")   -- reaction / tap changes
-- events that move only the text pieces
for _, e in ipairs({ "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED", "UNIT_ABSORB_AMOUNT_CHANGED",
                     "UNIT_HEAL_PREDICTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_THREAT_SITUATION_UPDATE" }) do
    ev:RegisterUnitEvent(e, "player", "target")
end
for _, e in ipairs({ "PLAYER_FLAGS_CHANGED", "PLAYER_UPDATE_RESTING", "RAID_TARGET_UPDATE", "PARTY_LEADER_CHANGED",
                     "GROUP_ROSTER_UPDATE", "UNIT_THREAT_LIST_UPDATE", "PLAYER_GUILD_UPDATE" }) do
    ev:RegisterEvent(e)
end
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("UNIT_PET")
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_DELAYED",
                     "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
                     "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTIBLE",
                     "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do
    ev:RegisterUnitEvent(e, "player", "target")
end
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        GloomsUnitFramesDB = GloomsUnitFramesDB or {}
        root = GloomsUnitFramesDB
        -- Colors set to "Use Class Color" take THIS character's class, in every
        -- profile, before anything applies them (the Hub's kit). The fill and
        -- text colors' own Class / Power / Resource sources follow the UNIT live.
        if GloomsHub and GloomsHub.UI and GloomsHub.UI.StampClassColors then GloomsHub.UI.StampClassColors(root) end
        if root._version == 1 or (root._version == nil and root.player) then
            -- v1 was ONE account-wide config { player, target }. It becomes the
            -- first profile, "Default", and every character keeps landing on it
            -- until the owner makes another — nothing he built is lost.
            local prof = { player = root.player, target = root.target }
            for k in pairs(root) do root[k] = nil end
            root.profiles = { Default = prof }
        elseif root._version ~= nil and root._version ~= DB_VERSION then
            for k in pairs(root) do root[k] = nil end
        end
        root._version = DB_VERSION
        root.profiles = root.profiles or {}
        root.charProfiles = root.charProfiles or {}
        if next(root.profiles) == nil then root.profiles.Default = {} end
        -- Bind this character (CharKey needs the realm, hence LOGIN) and load.
        local name = GU:ActiveProfileName()
        root.charProfiles[GU:CharKey()] = name
        LoadProfile(name)
        for _, which in ipairs(GU.UNITS) do CreateUnitFrame(which) end
        initialised = true
        RefreshKick()
        for _, which in ipairs(GU.UNITS) do GU:ApplyLayout(which) end
        -- the frames other tools attach to now exist (the Hub's Anchors.lua)
        if GloomsHub.AnchorsChanged then GloomsHub:AnchorsChanged() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TARGET_CHANGED"
        or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        UpdateVisibility()
        if event == "PLAYER_TARGET_CHANGED" then GU:RefreshAuras(frames.target) end
        if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then GU:ApplyBlizzardCastBar() end
    elseif event == "SPELLS_CHANGED" or (event == "UNIT_PET" and unit == "player") then
        RefreshKick()
    elseif event == "RUNE_POWER_UPDATE" then
        if initialised and frames.player:IsShown() then GU:Refresh("player") end
    elseif event == "UNIT_MAXPOWER" and unit == "player" or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "UPDATE_SHAPESHIFT_FORM" then
        RefreshKick()
        GU:ApplyLayout("player")   -- the segment count may have changed
    elseif event:find("^UNIT_SPELLCAST") and (unit == "player" or unit == "target") then
        GU:RefreshCast(unit)
    elseif event == "PLAYER_FLAGS_CHANGED" or event == "PLAYER_UPDATE_RESTING" or event == "RAID_TARGET_UPDATE"
        or event == "PARTY_LEADER_CHANGED" or event == "GROUP_ROSTER_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE"
        or event == "PLAYER_GUILD_UPDATE" then   -- [guild] (the player's arrives after login)
        if initialised then
            for _, which in ipairs(GU.UNITS) do
                if frames[which]:IsShown() then GU:RefreshTexts(frames[which], which) end
            end
        end
    elseif unit == "player" or unit == "target" then
        GU:Refresh(unit)
    end
end)

------------------------------------------------------------------------
-- Slash
------------------------------------------------------------------------
SLASH_GLOOMSUNITFRAMES1 = "/gu"
SLASH_GLOOMSUNITFRAMES2 = "/unitframes"
-- QA probe: what every chunk/layer of a unit's rings is doing right now.
-- Kept in the addon — a /run over 255 characters silently does nothing.
local function Debug(which)
    local f, cfg = frames[which], db[which]
    if not f then return end
    local function v(x)
        if x == nil then return "nil" end
        if issecretvalue and issecretvalue(x) then return "SECRET" end
        if type(x) == "number" then return ("%.3f"):format(x) end
        return tostring(x)
    end
    for _, key in ipairs(GU.RINGS) do
        local rc, r = cfg.rings[key], f.rings[key]
        if rc and r and r.fill then
        Chat(("%s %s ring: enabled=%s mode=%s shift=%s span=%s start=%s cw=%s chunks=%d shown=%s"):format(
            which, key, tostring(rc.enabled), tostring(rc.colorMode), tostring(rc.shift),
            tostring(rc.span), tostring(rc.start), tostring(rc.clockwise), r.fill.n, tostring(r.fill.shown)))
        if key == "cast" then
            -- Which route the cast ring is on: plain clock arithmetic, the engine's
            -- duration object evaluating the ring's fraction, or nothing honest to draw.
            local st = r.cast
            print(("   cast=%s  name=%s  locked=%s  channel=%s"):format(
                (not st) and "none" or st.plain and "PLAIN times" or "DURATION object (times secret; drawn from its fraction)",
                st and v(st.name) or "-", st and v(st.locked) or "-", st and v(st.channel) or "-"))
        end
        if key == "power" then
            local pcol, pType = PowerTypeColor(which)
            local max = UnitPowerMax(which, pType or 0)
            print(("   power type=%s max=%s pct=%s"):format(v(pType), v(max),
                v(UnitPowerPercent(which, pType or 0, true, CurveConstants.ScaleTo100))))
            -- A secret renders as TEXT: show the raw percent, the gate curve's
            -- answer and UnitPower itself in the ring's centre for a few seconds.
            local gate = r.fill.chunks[1].alphaCurve.base
            f.debugText:SetFormattedText("pct %.2f  gate %.2f  pow %d  max %d",
                UnitPowerPercent(which, pType or 0, true, CurveConstants.ScaleTo100),
                UnitPowerPercent(which, pType or 0, true, gate),
                UnitPower(which, pType or 0), max)
            C_Timer.After(8, function() f.debugText:SetText("") end)
        end
        for k, ch in ipairs(r.fill.chunks) do
            print(("   chunk %d  fixed rot=%s  rot rot=%s"):format(k, v(ch.fixed:GetRotation()), v(ch.rot:GetRotation())))
            for name, tex in pairs(ch.layers) do
                local cr, cg, cb = tex:GetVertexColor()
                print(("     %-4s shown=%s alpha=%s color=%s,%s,%s"):format(
                    name, tostring(tex:IsShown()), v(tex:GetAlpha()), v(cr), v(cg), v(cb)))
            end
        end
        end
    end
end

-- QA probe for the absorb arc (2026-09-19): does a curve object evaluate a
-- secret itself, and does UnitHealthPercent's second argument include
-- absorbs? Prints to chat and renders the two percents in the player ring.
local function ProbeAbsorb()
    local function v(x)
        if x == nil then return "nil" end
        if issecretvalue and issecretvalue(x) then return "SECRET" end
        return tostring(x)
    end
    local c = C_CurveUtil.CreateCurve()
    c:AddPoint(0, 0); c:AddPoint(1, 1)
    local mt = getmetatable(c)
    Chat("curve object: type=" .. type(c) .. " metatable=" .. tostring(mt ~= nil)
        .. " __index=" .. (mt and type(mt.__index) or "-"))
    if mt and type(mt.__index) == "table" then
        local names = {}
        for k in pairs(mt.__index) do names[#names + 1] = tostring(k) end
        table.sort(names)
        print("   methods: " .. table.concat(names, ", "))
    end
    for _, name in ipairs({ "Evaluate", "EvaluateAt", "GetValue", "GetValueAt", "Sample" }) do
        if type(c[name]) == "function" then
            local ok, r = pcall(c[name], c, 0.5)
            print(("   c:%s(0.5) -> ok=%s value=%s"):format(name, tostring(ok), v(r)))
            local ok2, r2 = pcall(c[name], c, UnitGetTotalAbsorbs("player"))
            print(("   c:%s(secret absorb) -> ok=%s value=%s"):format(name, tostring(ok2), v(r2)))
        end
    end
    local abs = UnitGetTotalAbsorbs("player")
    Chat("absorbs(player)=" .. v(abs) .. "  maxhp(player)=" .. v(UnitHealthMax("player")))
    -- Rendered on screen, top centre, big: a secret can be READ that way.
    if not GU.probeText then
        local pf = CreateFrame("Frame", nil, UIParent)
        pf:SetFrameStrata("TOOLTIP"); pf:SetSize(10, 10); pf:SetPoint("TOP", 0, -120)
        GU.probeText = pf:CreateFontString(nil, "OVERLAY")
        GU.probeText:SetFont("Fonts\\FRIZQT__.TTF", 28, "THICKOUTLINE")
        GU.probeText:SetPoint("TOP"); GU.probeText:SetTextColor(1, 0.9, 0.2)
    end
    GU.probeText:SetFormattedText("with %d  /  without %d     absorb %s",
        UnitHealthPercent("player", true, CurveConstants.ScaleTo100),
        UnitHealthPercent("player", false, CurveConstants.ScaleTo100),
        AbbreviateNumbers(abs or 0))
    C_Timer.After(20, function() GU.probeText:SetText("") end)
    Chat("rendered at the TOP of the screen for 20s: the percent WITH the flag / WITHOUT it / your absorb")
end

-- QA probe 2 (2026-09-19): the presence gate for an absorb tint. A secret
-- alpha of ZERO is ignored (§18), so: set PLAIN 0 first, then the secret
-- amount — visible iff the amount is non-zero. Three squares, top of screen:
--   A  a FRAME's alpha gated by the absorb        (expect: shown iff shielded)
--   B  a TEXTURE's alpha gated by the absorb      (expect: shown iff shielded)
--   C  a frame gated by a secret that IS zero     (expect: never shown)
local function ProbeGate()
    if not GU.gateProbe then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:SetFrameStrata("TOOLTIP"); holder:SetSize(300, 80); holder:SetPoint("TOP", 0, -170)
        local function square(i, label)
            local fr = CreateFrame("Frame", nil, holder)
            fr:SetSize(60, 60); fr:SetPoint("LEFT", (i - 1) * 100, 0)
            local t = fr:CreateTexture(nil, "ARTWORK"); t:SetAllPoints(); t:SetColorTexture(1, 0.85, 0.2, 1)
            local l = holder:CreateFontString(nil, "OVERLAY"); l:SetFont("Fonts\\FRIZQT__.TTF", 16, "THICKOUTLINE")
            l:SetPoint("TOP", fr, "BOTTOM", 0, -2); l:SetText(label)
            return fr, t
        end
        GU.gateProbe = { holder = holder }
        GU.gateProbe.A = square(1, "A frame")
        GU.gateProbe.B, GU.gateProbe.Bt = square(2, "B texture")
        GU.gateProbe.C = square(3, "C zero")
    end
    local g = GU.gateProbe
    local abs = UnitGetTotalAbsorbs("player") or 0
    local zero = UnitGetTotalHealAbsorbs("player") or 0    -- normally 0; secret or not
    g.holder:Show()
    g.A:SetAlpha(0);  g.A:SetAlpha(abs)
    g.Bt:SetAlpha(0); g.Bt:SetAlpha(abs)
    g.C:SetAlpha(0);  g.C:SetAlpha(zero)
    local function v(x) if issecretvalue and issecretvalue(x) then return "SECRET" end return tostring(x) end
    Chat(("gate probe: absorb=%s healabsorb=%s — squares A and B should be visible only while you have a shield; C never."):format(v(abs), v(zero)))
    Chat("run /gu gate again after the shield fades (or /gu gate off to remove the squares)")
end

SlashCmdList["GLOOMSUNITFRAMES"] = function(msg)
    if not initialised then Chat("Still loading, please wait.") return end
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "debug" then Debug("player") return end
    if msg == "debug target" then Debug("target") return end
    if msg == "casttrace" then
        GU.castTrace = not GU.castTrace
        Chat("cast trace " .. (GU.castTrace and "ON — the target's cast route prints here as it changes" or "off"))
        return
    end
    if msg == "probe" then ProbeAbsorb() return end
    if msg == "auras" then
        Chat(("auras: blizzard container addon loaded=%s  createFailed=%s  layoutError=%s  decorateError=%s"):format(
            tostring(C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")), tostring(GU.aurasFailed or 0), tostring(GU.aurasError), tostring(GU.decorateError)))
        for _, which in ipairs(GU.UNITS) do
            local f = frames[which]
            local cfgN, liveN = #(db[which].auras or {}), 0
            for _ in pairs(f.auras or {}) do liveN = liveN + 1 end
            Chat(("%s: %d group(s) configured, %d recorded on the frame, frame shown=%s"):format(which, cfgN, liveN, tostring(f:IsShown())))
            for i = 1, cfgN do
                local g = f.auras and f.auras[i]
                local ok, err = pcall(function()
                if g then
                    local c = g.container
                    -- ⚠ IsShown on the engine's buttons is a SECRET boolean; count only
                    local n, shown = c:GetNumChildren(), -1
                    local w, h = c:GetSize()
                    local px, py = c:GetCenter()
                    Chat(("%s group %d: kind=%s holder shown=%s container shown=%s visible=%s size=%.0fx%.0f centre=%s,%s children=%d shown=%d unit=%s"):format(
                        which, i, tostring(db[which].auras[i].kind), tostring(g.holder:IsShown()), tostring(c:IsShown()),
                        tostring(c:IsVisible()), w, h, px and ("%.0f"):format(px) or "?", py and ("%.0f"):format(py) or "?",
                        n, shown, tostring(c.GetUnit and c:GetUnit())))
                else
                    Chat(which .. " group " .. i .. ": NOT BUILT")
                end
                end)
                if not ok then Chat(which .. " group " .. i .. ": diagnostic error " .. tostring(err)) end
            end
        end
        return
    end
    if msg == "gate" then ProbeGate() return end
    if msg == "gate off" then if GU.gateProbe then GU.gateProbe.holder:Hide() end return end
    -- QA until the tab has it: /gu bar <health|power> <shape|rect|off> [size]
    --   · /gu bar <ring> dir <up|down|left|right> · rot <deg> · flip <h|v> · rim · absorb · grad <deg>|solid
    local ring, rest = msg:match("^bar%s+(%a+)%s*(.*)$")
    if ring == "health" or ring == "power" or ring == "resource" or ring == "cast" then
        local rc = db.player.rings[ring]
        if not rc then Chat("no " .. ring .. " ring on the player") return end
        local a, b = rest:match("^(%S+)%s*(%S*)$")
        if a == "off" then rc.mode = "arc"
        elseif a == "reset" then
            -- the bar block and the colouring back to factory; the mode stays
            rc.bar = nil; ApplyDefaults(rc, DEFAULTS.player.rings[ring])
            rc.colorMode, rc.shift = "solid", false
        elseif a == "debug" then
            local bar = frames.player.rings[ring].bar or frames.player.rings[ring].segBars[1]
            local c = rc.color
            Chat(("%s config: color=%.2f,%.2f,%.2f colorMode=%s classColor=%s powerColor=%s"):format(ring, c[1], c[2], c[3], tostring(rc.colorMode), tostring(rc.classColor), tostring(rc.powerColor)))
            for name, sb in pairs(bar.layers) do
                local tex = sb:GetStatusBarTexture()
                local mn, mx = sb:GetMinMaxValues()
                local vr, vg, vb, va = tex:GetVertexColor()
                local sv = function(x) if issecretvalue and issecretvalue(x) then return "SECRET" end return tostring(x) end
                Chat(("%s: shown=%s level=%d tex=%s alpha=%.2f vertex=%.2f,%.2f,%.2f,%.2f value=%s/%s size=%sx%s"):format(
                    name, tostring(sb:IsShown()), sb:GetFrameLevel(), tostring(tex:GetTexture()), tex:GetAlpha(),
                    vr or -1, vg or -1, vb or -1, va or -1, sv(sb:GetValue()), sv(mx), sv(tex:GetWidth()), sv(tex:GetHeight())))
            end
            Chat(("gradient=%s shift=%s fillDir=%s colorMode=%s"):format(tostring(bar.gradient), tostring(bar.shift), tostring(bar.fillDir), rc.colorMode))
            return
        elseif a == "dir" then rc.bar.fillDir = b
        elseif a == "rot" then rc.bar.rotation = tonumber(b) or 0
        elseif a == "flip" then Chat("flips are art, not the mask (a mask refuses flipped texcoords) — later") return
        elseif a == "absorbmax" then GU.absorbMax = not GU.absorbMax   -- QA: draw the absorb overlay at FULL
        elseif a == "strata" then rc.strata = (b ~= "" and b ~= "auto") and b:upper() or nil
        elseif a == "row" then rc.rowDir = b
        elseif a == "rowgap" then rc.rowGap = tonumber(b) or 4
        elseif a == "level" then rc.level = tonumber(b)
        elseif a == "rim" then rc.outline = not rc.outline
        elseif a == "absorb" then rc.bar.absorb = not rc.bar.absorb
        elseif a == "shift" then rc.shift = not rc.shift
        elseif a == "solid" then rc.colorMode = "solid"
        elseif a == "grad" then rc.colorMode = "gradient"; rc.gradientAngle = tonumber(b) or 90
        elseif a then
            rc.mode = "bar"; rc.bar.shape = a
            if tonumber(b) then rc.bar.size = tonumber(b) end
        end
        GU:ApplyLayout("player")
        local h = frames.player.rings[ring].holder
        Chat(("player %s: mode=%s shape=%s size=%d dir=%s rot=%d rim=%s absorb=%s color=%s shift=%s · strata=%s level=%s (drawn at %s %d)"):format(
            ring, rc.mode, rc.bar.shape, rc.bar.size, rc.bar.fillDir, rc.bar.rotation,
            tostring(rc.outline), tostring(rc.bar.absorb), rc.colorMode, tostring(rc.shift),
            tostring(rc.strata or "auto"), tostring(rc.level or "auto"), h:GetFrameStrata(), h:GetFrameLevel() + 1))
        return
    end
    -- QA: /gu text <template> · /gu text target <template> — sets the FIRST
    -- text piece's template (the tab is the real editor).
    local which, tpl = msg:match("^text%s+(target)%s+(.+)$")
    if not which then tpl = msg:match("^text%s+(.+)$"); which = "player" end
    if tpl then
        local cfg = db[which]; EnsureTexts(cfg)
        cfg.texts[1] = cfg.texts[1] or {}
        cfg.texts[1].template = tpl
        GU:ApplyLayout(which)
        Chat(which .. " text 1 = " .. tpl)
        return
    end
    GloomsHub:ToggleWindow("unitframes")
end
