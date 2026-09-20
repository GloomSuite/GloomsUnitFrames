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
        showCondition = "always",  -- "always"|"combat"|"target"|"combat_or_target"
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

local DEFAULTS = {
    _version = 1,
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
}

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local db          = nil
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
        self.durKey = nil
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

    function arc:Layer(name, fn)
        for _, ch in ipairs(self:Pieces()) do local t = ch.layers[name]; if t then fn(t) end end
    end

    -- Uniform colour on a layer.
    function arc:SetColor(name, r, g, b)
        self:Layer(name, function(t) t:SetVertexColor(r, g, b, 1) end)
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
    function arc:SetFromUnit(unit, power)
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

    -- Drive from a duration object whose TOTAL is plain: every point list is
    -- re-expressed over REMAINING seconds (x → T·(1−x), or T·x when the arc
    -- drains) and evaluated engine-side. Cached per (T, drains).
    function arc:SetFromDuration(d, T, drains)
        local key = T .. (drains and "d" or "f")
        if self.durKey ~= key then
            self.durKey = key
            local function conv(pts)
                local out = {}
                for _, pt in ipairs(pts) do
                    local rem = drains and (T * pt[1]) or (T * (1 - pt[1]))
                    out[#out + 1] = { rem, pt[2] }
                end
                table.sort(out, function(a, b) return a[1] < b[1] end)
                return CurveFrom(out)
            end
            self.durCurves = {}
            for k = 1, self.n do
                local ch = self.chunks[k]
                local c = { rot = conv(ch.rotPts), alpha = {} }
                for name in pairs(ch.layers) do c.alpha[name] = conv(ch.alphaPts[name]) end
                self.durCurves[k] = c
            end
            local rd = self.round
            self.durCurves.startAlpha, self.durCurves.endAlpha = {}, {}
            for name in pairs(rd.startCap.layers) do self.durCurves.startAlpha[name] = conv(rd.startCap.alphaPts[name]) end
            for name in pairs(rd.endCap.layers) do self.durCurves.endAlpha[name] = conv(rd.endCap.alphaPts[name]) end
            if rd.endCap.rotPts then self.durCurves.endRot = conv(rd.endCap.rotPts) end
        end
        local dc = self.durCurves
        for k = 1, self.n do
            local ch = self.chunks[k]
            ch.rot:SetRotation(d:EvaluateRemainingDuration(dc[k].rot, ch.y(0)))
            for name, tex in pairs(ch.layers) do
                if tex:IsShown() then tex:SetAlpha(d:EvaluateRemainingDuration(dc[k].alpha[name], ALPHA_OFF)) end
            end
        end
        local rd = self.round
        if self.roundStart then
            for name, tex in pairs(rd.startCap.layers) do
                if tex:IsShown() then tex:SetAlpha(d:EvaluateRemainingDuration(dc.startAlpha[name], ALPHA_OFF)) end
            end
        end
        if self.roundEnd then
            if dc.endRot then rd.endCap.mask:SetRotation(d:EvaluateRemainingDuration(dc.endRot, 0), rd.endCap.pivot) end
            for name, tex in pairs(rd.endCap.layers) do
                if tex:IsShown() then tex:SetAlpha(d:EvaluateRemainingDuration(dc.endAlpha[name], ALPHA_OFF)) end
            end
        end
    end

    -- Drive from a plain 0..1 (the track, and the no-unit state).
    function arc:SetFromPlain(pct, alphaScale)
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
                local r = { holder = h, segs = {} }
                for i = 1, GU.MAX_SEGMENTS do
                    r.segs[i] = { track = NewArc(h, false), fill = NewArc(h, true) }
                end
                f.rings[key] = r
            else
                local r = { holder = h, track = NewArc(h, false), fill = NewArc(h, true) }
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
        local x, y = cx - sw / 2, cy - sh / 2
        f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", x, y)
        local g = ghosts[which]
        g:ClearAllPoints(); g:SetPoint("CENTER", UIParent, "CENTER", x, y)
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
    local t = g:CreateTexture(nil, "OVERLAY")
    t:SetTexture("Interface\\Buttons\\WHITE8x8"); t:SetVertexColor(0, 1, 0.3, 0.9)
    t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); t:SetWidth(1)
    local t2 = g:CreateTexture(nil, "OVERLAY"); t2:SetTexture("Interface\\Buttons\\WHITE8x8"); t2:SetVertexColor(0, 1, 0.3, 0.9)
    t2:SetPoint("TOPRIGHT"); t2:SetPoint("BOTTOMRIGHT"); t2:SetWidth(1)
    local t3 = g:CreateTexture(nil, "OVERLAY"); t3:SetTexture("Interface\\Buttons\\WHITE8x8"); t3:SetVertexColor(0, 1, 0.3, 0.9)
    t3:SetPoint("TOPLEFT"); t3:SetPoint("TOPRIGHT"); t3:SetHeight(1)
    local t4 = g:CreateTexture(nil, "OVERLAY"); t4:SetTexture("Interface\\Buttons\\WHITE8x8"); t4:SetVertexColor(0, 1, 0.3, 0.9)
    t4:SetPoint("BOTTOMLEFT"); t4:SetPoint("BOTTOMRIGHT"); t4:SetHeight(1)
    g:Hide()
    ghosts[which] = g
    return f
end

-- The unit frame's extent: the union of its rings' boxes.
local function UnitExtent(cfg)
    local ext = 60
    for _, key in ipairs(GU.RINGS) do
        local rc = cfg.rings[key]
        if rc and rc.enabled then
            ext = math.max(ext, rc.size + 2 * math.max(math.abs(rc.dx or 0), math.abs(rc.dy or 0)))
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

    local a = anchors[which]
    a:ClearAllPoints(); a:SetSize(ext, ext)
    a:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)
    local g = ghosts[which]
    g:ClearAllPoints(); g:SetSize(ext, ext)
    g:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)

    for i, key in ipairs(GU.RINGS) do
        local rc, r = cfg.rings[key], f.rings[key]
        if rc and r then   -- a unit may lack a ring (the target has no resource ring)
        -- Each ring owns a band of 16 frame levels, in GU.RINGS order, so
        -- overlapping rings never interleave their pieces: track +0..+2, fill
        -- +3..+6, the health ring's shield copy +11..+14, the kick tick +15.
        r.holder:SetFrameLevel(f:GetFrameLevel() + 1 + (i - 1) * 16)
        local artDef = GU.RING_TEXTURES[rc.texture] or GU.RING_TEXTURES.disc
        local art, ramp = artDef.path, artDef.ramp or GU.RING_TEXTURES.disc.ramp
        r.holder:SetSize(rc.size, rc.size)
        r.holder:ClearAllPoints()
        r.holder:SetPoint("CENTER", f, "CENTER", rc.dx or 0, rc.dy or 0)
        local inner = rc.size - 2 * math.max(2, rc.thickness or 22)
        if key == "resource" then
            self:LayoutResource(which, rc, r, art, ramp, inner)
        else
        if key == "cast" then r.holder:SetShown(r.casting and true or false) end
        r.track:SetShown(rc.enabled)
        r.fill:SetShown(rc.enabled)
        r.fill:SetShift(rc.shift and true or false)
        local g = { start = rc.start, span = rc.span, clockwise = rc.clockwise, size = rc.size, inner = inner,
                    thickness = rc.thickness, art = art, ramp = ramp, roundStart = rc.roundStart, roundEnd = rc.roundEnd }
        r.track:Configure(g)
        r.fill:Configure(g)
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
    if rc.resourceColor and token and PowerBarColor[token] then
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
    for i = 1, GU.MAX_SEGMENTS do
        local sg = r.segs[i]
        local live = on and i <= n
        sg.track:SetShown(live); sg.fill:SetShown(live)
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
        if rc.shieldTint and r.shield then
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
        for i = 1, r.n do
            local ok = pcall(r.segs[i].fill.SetFromUnit, r.segs[i].fill, unit, r.pType)
            if not ok then r.segs[i].fill:SetFromPlain(0) end
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
-- ordinary clock arithmetic per frame. A target's may be secret on a
-- restricted map (untested): then the duration object drives the curves
-- through EvaluateRemainingDuration — if even its TOTAL is secret the ring
-- stays hidden rather than guess.
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
local function KickExtras(r, rc, st)
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
        fill:Layer("mid", function(t) if t:IsShown() then t:SetAlpha(d:EvaluateRemainingDuration(a, ALPHA_OFF)) end end)
        fill:Layer("low", function(t) if t:IsShown() then t:SetAlpha(ALPHA_OFF) end end)
    elseif fill.shift then
        fill:SetShift(false)
    end
    if rc.kickTick and fill.geo then
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
        tick:SetRotation(d:EvaluateRemainingDuration(CurveFrom(pts), geo.S), pivot)
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
    local p
    if st.plain then
        local now = GetTime() * 1000
        if st.fake and now >= st.endMS then st.startMS, st.endMS = now, now + 5000 end
        p = (now - st.startMS) / math.max(1, st.endMS - st.startMS)
        p = clamp(p, 0, 1)
        if st.channel and rc.channelDrains then p = 1 - p end
        r.fill:SetFromPlain(p)
    elseif st.duration then
        r.fill:SetFromDuration(st.duration, st.total, st.channel and rc.channelDrains)
    end
    if which == "target" and rc.kickAware and not st.fake then
        r.fill:SetColor("base", KickColor(rc, st.locked))
        KickExtras(r, rc, st)
    end
end

function GU:RefreshCast(which)
    local f, cfg = frames[which], db and db[which]
    if not f or not cfg then return end
    local rc, r = cfg.rings.cast, f.rings.cast
    if not (rc and r) then return end
    local st = rc.enabled and UnitExists(which) and CastState(which) or nil
    if not st and rc.enabled and castPreview[which] then
        local now = GetTime() * 1000
        st = { name = "preview", startMS = now, endMS = now + 5000, channel = false, locked = false, fake = true }
    end
    r.cast = nil
    if st then
        local secretTimes = issecretvalue and (issecretvalue(st.startMS) or issecretvalue(st.endMS))
        if not secretTimes then
            st.plain = true
        else
            local d = (st.channel and UnitChannelDuration or UnitCastingDuration)(which)
            local okT, total = pcall(function() return d and d:GetTotalDuration() end)
            if d and okT and total and not (issecretvalue and issecretvalue(total)) and total > 0 then
                st.duration, st.total = d, total
            else
                st = nil   -- nothing honest to draw
            end
        end
    end
    r.cast = st
    r.casting = st ~= nil
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
function GU:Defaults(which) return DEFAULTS[which] end
function GU:IsReady() return initialised end

function GU:Nudge(which, dx, dy)
    local cfg = db[which]; if not cfg then return end
    cfg.x, cfg.y = cfg.x + dx, cfg.y + dy
    self:ApplyLayout(which)
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

-- While the tab edits a unit its anchor is draggable and its outline shows.
function GU:SetEditing(which)
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
ev:RegisterUnitEvent("UNIT_FACTION", "player", "target")   -- reaction / tap changes
-- events that move only the text pieces
for _, e in ipairs({ "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED", "UNIT_ABSORB_AMOUNT_CHANGED",
                     "UNIT_HEAL_PREDICTION", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_THREAT_SITUATION_UPDATE" }) do
    ev:RegisterUnitEvent(e, "player", "target")
end
for _, e in ipairs({ "PLAYER_FLAGS_CHANGED", "PLAYER_UPDATE_RESTING", "RAID_TARGET_UPDATE", "PARTY_LEADER_CHANGED",
                     "GROUP_ROSTER_UPDATE", "UNIT_THREAT_LIST_UPDATE" }) do
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
        db = GloomsUnitFramesDB
        if db._version ~= DEFAULTS._version then
            for k in pairs(db) do db[k] = nil end
        end
        ApplyDefaults(db, DEFAULTS)
        -- Same-day migration: "shift" was briefly a colour MODE; it is a toggle now.
        for _, which in ipairs(GU.UNITS) do
            for _, key in ipairs(GU.RINGS) do
                local rc = db[which].rings[key]
                if rc then
                    if rc.colorMode == "shift" then rc.colorMode, rc.shift = "solid", true end
                    if rc.texture == "ring" then rc.texture = "disc" end
                end
            end
        end
        for _, which in ipairs(GU.UNITS) do EnsureTexts(db[which]); EnsureAuras(db[which], which); CreateUnitFrame(which) end
        initialised = true
        RefreshKick()
        for _, which in ipairs(GU.UNITS) do GU:ApplyLayout(which) end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TARGET_CHANGED"
        or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        UpdateVisibility()
        if event == "PLAYER_TARGET_CHANGED" then GU:RefreshAuras(frames.target) end
    elseif event == "SPELLS_CHANGED" or (event == "UNIT_PET" and unit == "player") then
        RefreshKick()
    elseif event == "UNIT_MAXPOWER" and unit == "player" or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "UPDATE_SHAPESHIFT_FORM" then
        RefreshKick()
        GU:ApplyLayout("player")   -- the segment count may have changed
    elseif event:find("^UNIT_SPELLCAST") and (unit == "player" or unit == "target") then
        GU:RefreshCast(unit)
    elseif event == "PLAYER_FLAGS_CHANGED" or event == "PLAYER_UPDATE_RESTING" or event == "RAID_TARGET_UPDATE"
        or event == "PARTY_LEADER_CHANGED" or event == "GROUP_ROSTER_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
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
    if msg == "probe" then ProbeAbsorb() return end
    if msg == "auras" then
        Chat(("auras: blizzard container addon loaded=%s  createFailed=%s  layoutError=%s  decorateError=%s"):format(
            tostring(C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")), tostring(GU.aurasFailed or 0), tostring(GU.aurasError), tostring(GU.decorateError)))
        Chat(("effects: host OnShow fired %d time(s), Start called %d time(s), last error=%s"):format(
            GU.hostShows or 0, GU.fxStarts or 0, tostring(GU.fxError)))
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
