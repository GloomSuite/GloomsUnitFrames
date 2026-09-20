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
The remaining work is Hub BACKLOG items 12 (watching) and 13 (the tab tidy pass); 14 (profiles) and 15 closed 2026-09-20.

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

- **`GloomsUnitFrames.lua` — the ENGINE.** Defaults, `GloomsUnitFramesDB` **v2 — PROFILES**
  (2026-09-20, the owner's ruling): `{ _version = 2, profiles = { [name] = { player, target } },
  charProfiles = { ["Name-Realm"] = name } }`. The engine's `db` local IS the active profile, so
  every `db[which]` read is unchanged; `LoadProfile` swaps it and re-applies both units.
  `PrepareProfile` fills defaults + the field migrations + the seeded lists for any profile before
  it is drawn. An unbound character lands on "Default" (the migrated v1 config) else the first
  name; login writes the binding. New = factory, Copy = deep copy, Rename-to-same = no-op,
  Delete refuses the last one and returns the fallback (Default if it exists) so the tab can say
  where the character landed; `ProfileUsers(name)` feeds the Hub's delete gate. ⚠ The mid-combat
  ruling (the owner, 2026-09-20, **for GU only**): a config change need not apply live in a
  fight, it must land at regen. `EnsureTexts` / `EnsureAuras` seed the two lists only when the
  key is ABSENT, so an emptied list stays empty, and `EnsureAuras` DROPS a saved group of the
  removed `spell` kind. The arc renderer (`NewArc`/`Configure`/`SetFromUnit`/`SetFromPlain`/
  `SetFromDuration`; `rampOnly` = the ramp layer alone, a colour fading to transparent), the
  per-unit frames with a ring HOLDER per ring (each ring owns a band of **16** frame levels: track
  +0..+2, fill +3..+6, the health ring's shield copy +11..+14, the kick tick +15; rings in
  `GU.RINGS` order: health, power, resource, cast — so rings sit at 1–64 of the unit frame), the
  health fill's colour (`UnitColor`: class for a player, reaction for an NPC, tapped grey; a PLAIN
  `ok` ahead of possibly-secret channels; a gradient wins over it), the shield WASH (`r.shield`: a
  ramp-only copy of the arc under a `gate` frame whose alpha is plain 0 then the secret absorb
  amount, and an `inner` frame carrying the user's opacity; the fade fits the arc's chord via
  `RampAt`), the class-resource
  segments (`LayoutResource`; count = `UnitPowerMax`, hides at 0; **Death Knight runes** ARE a
  power type for the count — 6 — but `UnitPowerPercent` does not take them, so `Refresh` counts
  the READY runes through `GetRuneCooldown` and feeds the plain fraction, on `RUNE_POWER_UPDATE`;
  their colour is the class red, not `PowerBarColor.RUNES`' grey — owner-QA'd 2026-09-20), the cast ring (`RefreshCast`/`CastTick`: the player's times are
  PLAIN — clock arithmetic; **a target's are secret in every part on a restricted map**, and the
  duration object then drives the ring's own percent curves through `EvaluateElapsedPercent` /
  `EvaluateRemainingPercent` — `arc:SetFromDuration`, Hub FINDINGS §18.10; ★ a ROTATION evaluation
  takes no second argument, the "modifier" is validated to 0..1 — §18.11), the interrupt colouring
  (`KickColor`, EUI's spell table, secret-safe; `KickExtras` for the mid-cast tint + the tick, only
  on a PLAIN-time cast, gated per piece so it never paints empty geometry — §18.12; `arc:SetColor`
  passes NO alpha, and `CastTick` recolours BEFORE the geometry pass), and a small API
  the tab drives: `Config · ApplyLayout · Nudge · SetStrata · SetCondition · Reset · CopyFrom ·
  SetEditing · SetCastPreview · OnChange · UnitColor · ClassResource · CastInfo`. `/gu debug` /
  `/gu debug target` print every ring's state (secrets print as SECRET; a secret can be READ on
  screen by rendering it as text; the cast ring's line names its route); **`/gu casttrace`** (one
  chat line per change of the target's cast route — the only way to measure a two-second delve
  cast); `/gu probe` (the absorb doors, §19), `/gu gate` (the presence gate, three squares),
  `/gu auras` (per-group container state) and `/gu text [target] <template>` are QA tools kept in
  the addon because a `/run` over 255 characters does nothing. Every arc driver returns early on
  an arc that was never `Configure`d (the health ring's shield copy exists before it is on).
- **`GloomsUnitFrames_Text.lua` — the TEXT PIECES.** `cfg.texts` is a list; each piece is a
  template of words and `[shortcodes]` compiled ONCE into a format string + one reader per code,
  rendered by a single `SetFormattedText` whose arguments may be secret (`AbbreviateNumbers` for
  845K). Readers never branch on a secret. `GU.TEXT_HELP` is the list the tab prints — keep it next
  to `TAGS`. Pieces are child frames (own level) with a FontString; `LayoutTexts` from ApplyLayout,
  `RefreshTexts(f, unit[, group])` from Refresh / the cast tick.
- **`GloomsUnitFrames_Auras.lua` — the AURA GROUPS.** `cfg.auras` is a list; TWO kinds, `buffs` /
  `debuffs` (an `AuraContainer` GROUP, `AddAuraGroup` with the engine flow layout, narrowed by
  `ac.filter` → `GU:AuraFilter` builds the token string + `candidateFilters`; `GU.AURA_CLASSES` is
  the catalog). ⚠ **The `spell` kind ("This spell": one aura by ID wearing a Hub effect) was
  REMOVED by the owner 2026-09-20** — on the PLAYER the engine ignores `includeSpellIDs` AND
  `excludeSpellIDs` on HARMFUL auras (Hub FINDINGS §20.6, measured six ways), and a highlight
  that cannot single out a debuff was "effectively useless". The Hub-effect-under-a-button
  machinery went with it. **Do not rebuild it on the same call.** The tab greys the two spell-list
  boxes on a PLAYER Debuffs group and says why; they work on Buffs and on the target. Everything
  on a button is wired in `initializeFrame` and nowhere else; the Hub shape mask is started THERE
  with no trigger (§20), its bind verified and retried — **out of combat only**: a button wired
  mid-fight is forbidden from the start and `AddMaskTexture` throws (§20.7). A changed filter /
  size / shape swaps in a fresh container (`Signature`); max count and position adjust the live
  one (`LayoutLive`). Legacy kinds (`mydebuffs`…) migrate to filters in `MigrateAuraGroup`.
  **The PREVIEW** (`LayoutAuraPreview`, `GU:SetAuraPreview`): sample icons from the spellbook drawn
  by our own textures where the selected group's buttons will be, by the same rules the engine's
  flow layout is given, while the tab's Auras section is open — the engine only draws buttons for
  auras you have, so an empty group was invisible while being placed. Its pixel alignment against
  a live group is unverified (BACKLOG 12.3).
- **`GloomsUnitFrames_Tab.lua` — the UNIT FRAMES tab** (`GloomsHub:RegisterTab`, id `unitframes`,
  order 50), built on `LibGloomSkin` (`SKIN_NEEDS = 10`; bump in the same commit as any newer call).
  Rail: the mark, **the PROFILE block** (the suite's `UI.profileBlock`, with `users` for the delete
  gate), UNITS — Player / Target as plain rows (the ring summary that used to share the line was
  removed: it collided, and the owner asked what it was even for) — **Copy from the other unit**
  (everything but position), Reset. Editor: a GB-style accordion — Position · Layer · Visibility ·
  **Texts** (list + editor, the shortcode list a popover that INSERTS on click) · **Auras** (list +
  editor; filters behind a cog, its popover titled "FILTERS — BUFFS / DEBUFFS" because the two
  panels differ; the spell-list boxes render "Name (ID)" and resolve by the ID so a zone debuff's
  entry survives a round trip) · one section per ring (the resource section only for Player).
  Number cells (`cNum`) set the Hub's `stepper` so Up / Down apply live. **Every section body is a `UI.grid`** (two cells
  per line — the 2026-09-20 compaction, Hub BACKLOG 13): the deep clusters (shield tint, interrupt
  colouring) sit behind `UI.cog` popovers, one-line conditionals (gradient end, drain shift,
  breakpoint) appear inline under their switch, and a section's `refresh` ends with
  `sc.height = g:layout() + 8` so the accordion follows. The file's header comment explains the
  three tiers; the owner called the result "a little messy" and may mock the tidy pass — ask for
  the mock first. Everything applies live; there is no Save. **The tab
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
repo `GloomSuite/GloomsUnitFrames` exists since 2026-09-20** — public, org-owned, private
membership, default branch `master`, verified anonymously (author `Gloom`, no linked account; Hub
`CLAUDE.md` PRIVACY). Untagged so far. Tags cut a GitHub Release as a version marker only; the
owner runs the symlink.
