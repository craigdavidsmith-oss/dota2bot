# Dota 2 bot scripts — project guide

Lua bot scripts for Dota 2, run in a local-host custom lobby. This is Craig's
copy of `forest0xia/dota2bot-OpenHyperAI` (MIT), maintained independently — there
is no upstream remote and no plan to merge from the original.

Local changes are tagged `CDS-PATCH` in comments. Grep for that to find them.

## Read these first

- `docs/ARCHITECTURE.md` — full file map, naming conventions, every subsystem
- `docs/BOT_API_REFERENCE.md` — Valve bot API surface
- `docs/PATCH_UPDATE_GUIDE.md` — runbook for when a new Dota patch drops

Read the architecture doc before making changes. It saves scanning the tree.

## Hard rules

**Lua 5.1 only.** The Dota bot VM has no bitwise operators. `~`, `&`, `|`, `<<`,
`>>` are syntax errors. Use arithmetic instead. Also no `goto`, no `//`.

**Syntax-check every Lua file you edit** before saying you're done:

```
luajit -bl path/to/file.lua
```

Non-zero exit means a syntax error. If `luajit` isn't installed, say so rather
than skipping the check — a syntax error makes the whole team's scripts fail to
load, and the in-game symptom is silent: bots fall back to Valve default AI with
no error surfaced to the player.

**Some FunLib Lua files are generated from TypeScript.** Editing the `.lua` alone
means `npm run build:lua` silently reverts you. Full mapping in
`docs/ARCHITECTURE.md` section 13. The ones most likely to come up:

| Generated Lua | TypeScript source |
|---|---|
| `bots/FunLib/aba_push.lua` | `typescript/bots/FunLib/aba_push.ts` |
| `bots/FunLib/aba_defend.lua` | `typescript/bots/FunLib/aba_defend.ts` |
| `bots/FunLib/aba_role.lua` | `typescript/bots/FunLib/aba_role.ts` |
| `bots/FunLib/utils.lua` | `typescript/bots/FunLib/utils.ts` |
| `bots/FunLib/global_cache.lua` | `typescript/bots/FunLib/global_cache.ts` |

For those: edit the `.ts`, run `npx tsc -p tsconfig-tstl.json --noEmit`, then
`npm run build:lua`, and commit both files. If `npm install` fails on peer deps,
use `--legacy-peer-deps`.

Everything else — `bots/BotLib/hero_*.lua`, `bots/mode_*.lua`,
`bots/FunLib/jmz_func.lua`, `bots/FretBots/*.lua`, `bots/Customize/*.lua` — is
hand-written Lua. Edit directly.

**Never edit `bots/FunLib/build_stamp.lua`.** It's a placeholder that
`deploy-bots.bat` overwrites at the destination.

## Testing

There is no test suite, and neither of us can run Dota. Static verification is
all we have:

1. `luajit -bl` on every changed Lua file
2. `npx tsc -p tsconfig-tstl.json --noEmit` if any `.ts` changed
3. Confirm helper functions exist before calling them —
   `grep -n "^function J\.<name>" bots/FunLib/jmz_func.lua`. The codebase has
   several near-miss names, and calling a nil function is a runtime crash, not a
   load error.

**`bots/hero_selection.lua` does not parse under strict Lua 5.1.** It contains
`break;`, which LuaJIT accepts but the 5.1 grammar does not, so step 1 reports a
failure on that file at HEAD regardless of your changes. Check it by confirming
the only parse error is that `break;`, and validate any edited region separately.
Do not "fix" the semicolons just to make a checker happy.

Say plainly when a change can only be validated in game. Don't imply more
confidence than the checks support.

## Deploying

`deploy-bots.bat` in the repo root copies `bots/` into the Dota install and
stamps the build:

```
deploy-bots.bat          copy, leave extra files alone
deploy-bots.bat clean    mirror, deleting files not in the repo (prompts first)
```

Use `clean` after renaming or deleting a script file — otherwise the stale copy
stays in the Dota folder and still loads.

The bots announce the build stamp in team chat during hero selection, so Craig
can confirm which build is live. If it reads
`source - not deployed via deploy-bots.bat`, files were copied by hand.

## Common tasks

**Fix a hero's items:** `bots/BotLib/hero_<name>.lua`, the
`sRoleItemsBuyList['pos_N']` arrays. Item names are `item_<internal_name>`; valid
names in `bots/FunLib/aba_item.lua`. Use `GetItemComponents()` for recipes —
don't hardcode component arrays.

**Fix a hero's abilities:** same file. `SkillsComplement()` sets cast priority;
each ability has a `ConsiderX()` returning desire plus target. Prefer
`sAbilityList[N]` references over literal names so renames don't break it.

**Add a hero:** copy a similar `bots/BotLib/hero_*.lua`, then register in
`bots/FretBots/HeroNames.lua`, `bots/FunLib/aba_hero_roles_map.lua`, and
`bots/FunLib/spell_list.lua`.

**Tune behaviour:** `bots/Customize/general.lua`. The `CDS-PATCH` block near the
top holds the rune, support-farming, high-ground and Dire-compensation settings.
Prefer adding a setting there over hardcoding a threshold.

**Patch updates:** follow `docs/PATCH_UPDATE_GUIDE.md`. Verify ability names on
Liquipedia — patch note summaries are frequently wrong. Always update both
neutral item files (`bots/Buff/` and `bots/FretBots/`).

## Behaviour modes

Desires compete: each `mode_*_generic.lua` returns a number, highest wins. When
bots "won't do X", the usual cause is another mode outbidding X, not X being
broken. Check the ceiling on the mode that should be winning and the floor on the
one that actually is.

`GetDesire()` decides whether to run; `Think()` does the work. Defining `Think()`
in a mode file overrides Valve's built-in behaviour for that mode **entirely** —
there is no partial override. Weigh what's lost before adding one.

## Context that isn't obvious from the code

- Bots on a team share module state via `require` caching, so `FunLib` tables
  work for cross-bot coordination. Bot scopes and the `hero_selection.lua` scope
  may not share state — don't assume they do.
- `UpdateLaneAssignments()` returns a table the engine indexes by **team slot
  (1..5)**, *not* by PlayerID. This note used to say the opposite, and that was
  wrong — it justified a patch that remapped the table onto player ids, and since
  a Radiant player id is its slot minus one, every lane shifted one place: pos 1
  was handed slot 2's lane, mid. The symptom was a carry permanently sharing the
  human's mid lane, and it cost several games to find. Measured across two
  matches with different heroes, the engine produced an identical assignment —
  `pid0→MID, pid2→TOP, pid3→BOT, pid4→unset` — which is what gave it away. See
  the `CDS-PATCH` in `bots/hero_selection.lua`. Dire's separate problem was a
  genuine role/lane permutation, fixed slot-for-slot in
  `CorrectPotentialLaneAssignment`; that one is unrelated to the keying.
- **Nothing the bot VM `print()`s reaches `console.log`.** Every `[VScript]` line
  in that file comes from the vscripts VM. Bot-VM diagnostics have to go through
  `bot:ActionImmediate_Chat(msg, false)` (team-only), which does land in the log
  as a `CLocalize::FindSafe failed to localize` warning. Two debugging attempts
  were lost to printing into a void before this was understood.
- Dota **tears the console log off at match start**: the menu goes to
  `console.log`, and the match goes to `console.<matchid>.log` in
  `game/dota/`. Needs `-condebug` in the launch options — and it must be in
  Steam's Launch Options field, not appended to a `steam://` shortcut, where
  everything after the URL is silently dropped.
- Deterministic-per-window hashing is the pattern for making bots agree on a
  shared decision without a race. See `bots/mode_rune_generic.lua`.
