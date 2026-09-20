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
> placement, colours, rounding, the cast + interrupt logic, the TEXT pieces, the AURA groups, and the
> contents of the Unit Frames tab.
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

**Hub FINDINGS §18** (the rings), **§19** (absorbs: no arc, a presence gate) and **§20** (what an
aura button's children can and cannot do). On 12.1 health is a SECRET number for every unit everywhere (the player's own,
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
- add a fourth mask to a texture (hard error at login);
- TRUTH-TEST a secret — functions that may return one return a PLAIN `ok` first (`UnitColor`);
- expect any script on a frame under an aura button to run, or its `IsShown` to be plain (§20).

## Shape

- **`GloomsUnitFrames.lua` — the ENGINE.** Defaults, `GloomsUnitFramesDB` (account-wide,
  `_version = 1`; `EnsureTexts` / `EnsureAuras` seed the two lists only when the key is ABSENT, so
  an emptied list stays empty), the arc renderer (`NewArc`/`Configure`/`SetFromUnit`/`SetFromPlain`/
  `SetFromDuration`; `rampOnly` = the ramp layer alone, a colour fading to transparent), the
  per-unit frames with a ring HOLDER per ring (each ring owns a band of **16** frame levels: track
  +0..+2, fill +3..+6, the health ring's shield copy +11..+14, the kick tick +15; rings in
  `GU.RINGS` order: health, power, resource, cast — so rings sit at 1–64 of the unit frame), the
  health fill's colour (`UnitColor`: class for a player, reaction for an NPC, tapped grey; a PLAIN
  `ok` ahead of possibly-secret channels; a gradient wins over it), the shield WASH (`r.shield`: a
  ramp-only copy of the arc under a `gate` frame whose alpha is plain 0 then the secret absorb
  amount, and an `inner` frame carrying the user's opacity; the fade fits the arc's chord via
  `RampAt`), the class-resource
  segments (`LayoutResource`; count = `UnitPowerMax`, hides at 0; Death Knight runes are NOT a
  power type and are unbuilt), the cast ring (`RefreshCast`/`CastTick`: the player's times are
  PLAIN — clock arithmetic; a target with secret times uses the duration object and hides if even
  the total is secret), the interrupt colouring (`KickColor`, EUI's spell table; `KickExtras` for
  the mid-cast tint + the tick, only when the "not interruptible" flag is PLAIN), and a small API
  the tab drives: `Config · ApplyLayout · Nudge · SetStrata · SetCondition · Reset · CopyFrom ·
  SetEditing · SetCastPreview · OnChange · UnitColor · ClassResource · CastInfo`. `/gu debug` /
  `/gu debug target` print every ring's state (secrets print as SECRET; a secret can be READ on
  screen by rendering it as text); `/gu probe` (the absorb doors, §19), `/gu gate` (the presence
  gate, three squares), `/gu auras` (per-group container state) and `/gu text [target] <template>`
  are QA tools kept in the addon because a `/run` over 255 characters does nothing.
- **`GloomsUnitFrames_Text.lua` — the TEXT PIECES.** `cfg.texts` is a list; each piece is a
  template of words and `[shortcodes]` compiled ONCE into a format string + one reader per code,
  rendered by a single `SetFormattedText` whose arguments may be secret (`AbbreviateNumbers` for
  845K). Readers never branch on a secret. `GU.TEXT_HELP` is the list the tab prints — keep it next
  to `TAGS`. Pieces are child frames (own level) with a FontString; `LayoutTexts` from ApplyLayout,
  `RefreshTexts(f, unit[, group])` from Refresh / the cast tick.
- **`GloomsUnitFrames_Auras.lua` — the AURA GROUPS.** `cfg.auras` is a list; kinds `buffs` /
  `debuffs` (an `AuraContainer` GROUP, `AddAuraGroup` with the engine flow layout, narrowed by
  `ac.filter` → `GU:AuraFilter` builds the token string + `candidateFilters`; `GU.AURA_CLASSES` is
  the catalog) and `spell` (two SLOTS, HELPFUL + HARMFUL, `includeSpellIDs = {[id]=true}`, the
  button glued to a frame we position). Everything on a button is wired in `initializeFrame` and
  nowhere else; the Hub shape mask and the Hub effect are started THERE with no trigger (§20).
  A changed filter / size / shape / effect swaps in a fresh container (`Signature`); max count,
  position and effect PARAMS adjust the live one (`LayoutLive`, `RestyleEffects`). Legacy kinds
  (`mydebuffs`…) migrate to filters in `MigrateAuraGroup`.
- **`GloomsUnitFrames_Tab.lua` — the UNIT FRAMES tab** (`GloomsHub:RegisterTab`, id `unitframes`,
  order 50), built on `LibGloomSkin` (`SKIN_NEEDS = 4`; bump in the same commit as any newer call).
  Rail: the mark, Player / Target, **Copy from the other unit** (everything but position), Reset.
  Editor: a GB-style accordion — Position · Layer · Visibility · **Texts** (list + editor, the
  shortcode help printed from `GU.TEXT_HELP`) · **Auras** (list + editor; a two-column tri-state
  filter block for Buffs/Debuffs, a schema-driven effect-settings block for This spell, built from
  `GloomsHub.Effects` params) · one section per ring (the resource section only for Player).
  ⚠ **The owner finds the tab too STACKED** — Hub BACKLOG item 13 is the compaction pass. Everything applies live; there is no Save. **The tab
  is the lock**: `SetEditing(which)` on the container's OnShow makes the selected unit draggable
  with a green outline; OnHide locks. While the Cast ring section is open, that unit's ring runs a
  fake 5s cast on repeat (`SetCastPreview`).
- **`Media/art/`** is GENERATED (Python/PIL; the scripts were throwaway — regenerate from the
  descriptions in FINDINGS §18 / the engine header): `disc.png` (the default ring art, radius
  250/256) + `disc-ramp.png` (its gradient companion — a texture takes at most 3 masks, so the
  shape is baked in; custom art wants its own `<name>-ramp`), `halfplane-ccw/cw.png` (exact 180°,
  soft on the leading half of the edge, hard on the trailing), `halfplane-lead-ccw/cw.png` (180° +
  1.5° on the start side, binary), `hole.png` (transparent disc r=120/128, used with `CLAMP`),
  `cap.png` (hard 3° wedge), `disc-ramp-10.png … disc-ramp-90.png` (the ramp with its 0→1 over
  that percent of the diameter, centred — the shield wash picks the one matching the arc's chord;
  512² RGBA, alpha = ramp × disc coverage at radius 500 px, 4× supersampled edge). **The Gu mark
  (`Media/ui/logo.png`) is still the Hub's logo — owed.**
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
