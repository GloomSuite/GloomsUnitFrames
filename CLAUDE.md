# Gloom's Unit Frames — project guide

> **▶ PART OF THE GLOOM SUITE.** Gloom's Unit Frames is the suite's sixth tool, alongside Gloom's
> Bars, Auras, Overlays and Portraits, under the shared base addon **GloomsHub** (`~/GloomsHub`).
> All cross-cutting suite facts — the plan, current state, and shared runtime contracts (design
> tokens, the tabbed-shell API, the media resolver) — live THERE and are the single source of
> truth; this repo does not keep its own copy. **Before any *suite* work read
> `~/GloomsHub/docs/BACKLOG.md` first**, then SUITE-STATE.md, FINDINGS.md and CONTRACTS.md as
> needed. Normal Unit-Frames-only work proceeds here as usual.
> **Gloom's Build Barn is NOT in the suite.**

> ## ★★ ONE PROJECT, SIX REPOS — the owner works from `~/GloomsHub`
> **He opens GloomsHub and nothing else, ever.** This repo gets edited from a Hub session
> routinely — **that is correct, not a violation. Never tell him to close a project and open
> another one.** Before any change, decide which repo OWNS it and say so in one line, up front.
>
> **Belongs HERE (`~/GloomsUnitFrames`):** the rings (health / power / class resource / cast), their
> placement, colours, rounding, the cast + interrupt logic, and the contents of the Unit Frames tab.
> **Belongs in `~/GloomsHub`:** the Suite window + tab API · the shared `LibGloomSkin` toolkit ·
> media registration/resolver · the one minimap launcher · the suite docs and backlog.
> Full rule + ownership table: `~/GloomsHub/CLAUDE.md`.

Bespoke WoW addon: **circular unit frames** for the player and the target — health, power,
class-resource and cast displays as ARCS of any span, each placeable, sizeable, layerable and
colourable. Target: **Midnight 12.1** (Interface `120100`), retail only. Built 2026-09-19 in one
session, owner-QA'd throughout. Its purpose is to **replace EllesmereUI's player and target frames
outright**; EUI keeps target-of-target, focus, pet and boss frames via its per-unit *hidden* source.
The remaining milestones are Hub BACKLOG item 12.

## ★ THE ONE THING TO READ BEFORE TOUCHING THE RENDERER

**Hub FINDINGS §18.** On 12.1 health is a SECRET number for every unit everywhere (the player's own,
on a training dummy). The ring is drawn by handing secrets to widget setters the engine evaluates —
curves (`C_CurveUtil`) + rotating half-plane masks — and §18 records the sink table (six setters
that accept a secret and DO NOTHING among them), the three-mask limit, the zero-alpha rule and the
anti-aliasing rules for seams. **The header comment of `GloomsUnitFrames.lua` is the canonical
description of the technique; keep it true.** Do not:
- position anything by a secret (`SetPoint` drops it silently);
- hide anything with a secret alpha of 0 (ignored; "empty" must be geometry — a hairline);
- use `Texture:SetGradient` (a gradient texture ignores secret alpha) or `SetRotation` on a fill
  texture (masks clip it half a pixel tighter — a fringe);
- rely on ARTWORK sublevels for draw order across masked textures (frame levels only);
- add a fourth mask to a texture (hard error at login).

## Shape

- **`GloomsUnitFrames.lua` — the ENGINE.** Defaults, `GloomsUnitFramesDB` (account-wide,
  `_version = 1`), the arc renderer (`NewArc`/`Configure`/`SetFromUnit`/`SetFromPlain`/
  `SetFromDuration`), the per-unit frames with a ring HOLDER per ring (each ring owns a band of 8
  frame levels; rings in `GU.RINGS` order: health, power, resource, cast), the class-resource
  segments (`LayoutResource`; count = `UnitPowerMax`, hides at 0; Death Knight runes are NOT a
  power type and are unbuilt), the cast ring (`RefreshCast`/`CastTick`: the player's times are
  PLAIN — clock arithmetic; a target with secret times uses the duration object and hides if even
  the total is secret), the interrupt colouring (`KickColor`, EUI's spell table; `KickExtras` for
  the mid-cast tint + the tick, only when the "not interruptible" flag is PLAIN), and a small API
  the tab drives: `Config · ApplyLayout · Nudge · SetStrata · SetCondition · Reset · CopyFrom ·
  SetEditing · SetCastPreview · OnChange`. `/gu debug` / `/gu debug target` print every ring's
  state (secrets print as SECRET; a secret can be READ on screen by rendering it as text).
- **`GloomsUnitFrames_Tab.lua` — the UNIT FRAMES tab** (`GloomsHub:RegisterTab`, id `unitframes`,
  order 50), built on `LibGloomSkin` (`SKIN_NEEDS = 4`; bump in the same commit as any newer call).
  Rail: the mark, Player / Target, **Copy from the other unit** (everything but position), Reset.
  Editor: a GB-style accordion — Position · Layer · Visibility · Center text · one section per
  ring (the resource section only for Player). Everything applies live; there is no Save. **The tab
  is the lock**: `SetEditing(which)` on the container's OnShow makes the selected unit draggable
  with a green outline; OnHide locks. While the Cast ring section is open, that unit's ring runs a
  fake 5s cast on repeat (`SetCastPreview`).
- **`Media/art/`** is GENERATED (Python/PIL; the scripts were throwaway — regenerate from the
  descriptions in FINDINGS §18 / the engine header): `disc.png` (the default ring art, radius
  250/256) + `disc-ramp.png` (its gradient companion — a texture takes at most 3 masks, so the
  shape is baked in; custom art wants its own `<name>-ramp`), `halfplane-ccw/cw.png` (exact 180°,
  soft on the leading half of the edge, hard on the trailing), `halfplane-lead-ccw/cw.png` (180° +
  1.5° on the start side, binary), `hole.png` (transparent disc r=120/128, used with `CLAMP`),
  `cap.png` (hard 3° wedge). **The Gu mark (`Media/ui/logo.png`) is still the Hub's logo — owed.**
- **Trap fixed in the tab, worth knowing:** a setting getter must test `== nil`, never `v or
  default` — an OFF switch (`false`) would read as its default and stick.

## Conventions
- Namespace `GloomsUnitFrames` → `_G.GloomsUnitFrames`; frames `GloomsUnitFrames_*`; slash
  **`/gu`** (`/unitframes` also). Chat prefix `|cff936bffGloom's Unit Frames:|r`.
- Plain frames, plain SavedVariables, no Ace3, no embedded libraries — everything shared comes
  from the Hub, a hard dependency.
- Angles are degrees in math convention (0 right, 90 top, 180 left), counter-clockwise positive;
  a ring's `start` is where the FULL end sits and it sweeps `span` in `clockwise`/not as it fills.
- US spelling in user-visible text.

## Testing / release
Symlinked into the client at `…/Interface/AddOns/GloomsUnitFrames`. QA by the owner (non-dev): ONE
copy-paste step at a time, verify before claiming, BugSack error text first — **and the picture
over any `pcall`**. `/reload` is enough, including for new files and regenerated art. **The GitHub
repo `GloomSuite/GloomsUnitFrames` does not exist yet** (2026-09-19); the packager config and
workflow are in place for when the owner says it goes up — public, org-owned, private membership
(Hub `CLAUDE.md` PRIVACY). Tags cut a GitHub Release as a version marker only; the owner runs the
symlink.
