# Local match telemetry

Captures what happens in a match to a JSONL file on this machine. It is the data
collection step for adaptive bots — nothing here learns anything yet.

Everything stays local. No data leaves the machine.

## Running it

Two launchers in the repo root do this for you:

| Launcher | What it does |
|---|---|
| `start-telemetry.bat` | Starts the sidecar in the current window |
| `play-with-telemetry.bat` | Deploys scripts, starts the sidecar in its own window, launches Dota |

`play-with-telemetry.bat` is meant to be **copied to the Desktop**, so it finds
the repo through the hard-coded `REPO` path at the top of the file rather than
relative to itself. Edit that line if the repo ever moves.

Or by hand — start the sidecar before launching Dota and leave it running:

```bash
python tools/telemetry/server.py
```

It listens on `http://127.0.0.1:8642` and writes one file per match to
`tools/telemetry/data/`. Python 3 standard library only — no dependencies.

## Enabling FretBots (required)

Telemetry only runs when FretBots is loaded, and **FretBots is not a menu
option** — it is a console command you run by hand every match:

1. Launch Dota with the console enabled (`-console` in the launch options).
2. Create a Custom Lobby, server location **Local Host**, and tick
   **Enable Cheats**.
3. Start the game and wait for the map to finish loading.
4. Open the console with `` ` `` and type:

   ```
   sv_cheats 1
   script_reload_code bots/FretBots
   ```

The console should answer with:

```
Open Hyper AI (OHA). Starting Fretbots mode: <version>
[Telemetry] session <id> -> http://127.0.0.1:8642
```

If you do not see that second line, nothing is being recorded. Same procedure as
`bots/Buff/README.md`, which documents it for the Buff script.

Then play. The bots post a snapshot every 30 game-seconds and you will see a
line per tick in the server console.

Afterwards:

```bash
python tools/telemetry/report.py
```

`report.py` reads the newest capture in `data/`, so clear out simulated runs
before a real match if you do not want to confuse the two.

## Files

| File | Role |
|---|---|
| `server.py` | Receives POSTs, appends JSONL to `data/` |
| `report.py` | Summarises one capture; derives first-cut per-player stats |
| `simulate.py` | Drives the server with a synthetic match (no Dota needed) |
| `../../bots/FretBots/Telemetry.lua` | Game side: builds and sends snapshots |

## Wire format

One JSON object per line:

```json
{"type": "tick", "recv_at": "<iso8601>", "payload": { ... }}
```

`type` is `start`, `tick`, `end`, or `malformed`. Every payload carries a
`session_id`, and records are grouped into one file per session — so a missed
`/start` does not lose the ticks that follow.

Each `tick` payload holds `dota_time`, `game_state`, `team_kills`, a `towers`
map per side, and a `players` array with, per player: identity (`player_id`,
`steam_id`, `hero`, `team`, `is_bot`, `role`, `lane`), state (`is_alive`,
`level`, `health`, `mana`, `net_worth`, `gold`, `last_hits`, `denies`), K/D/A,
`items`, and `pos` as `{x, y}`.

The `end` payload additionally carries `match`, which is FretBots' existing
post-game data (winner, duration, mode, per-player finals).

## Testing without Dota

Neither the author nor the assistant can run Dota, so `simulate.py` is the
end-to-end test:

```bash
python tools/telemetry/server.py          # terminal 1
python tools/telemetry/simulate.py        # terminal 2
python tools/telemetry/report.py
```

It POSTs payloads shaped exactly like the ones `Telemetry.lua` builds. That
exercises the server, the on-disk format, and the report — but **not** the Lua
side. Only a real match validates that.

## Game-side configuration

Top of [`bots/FretBots/Telemetry.lua`](../../bots/FretBots/Telemetry.lua):

| Setting | Default | Meaning |
|---|---|---|
| `Telemetry.enabled` | `true` | Master switch |
| `Telemetry.host` | `http://127.0.0.1:8642` | Sidecar base URL |
| `Telemetry.tickInterval` | `30` | Game seconds between snapshots |
| `Telemetry.maxFailures` | `5` | Consecutive failures before giving up |

It fails open. If the sidecar is not running the first failure prints one line to
the console, five consecutive failures disable the module for the rest of the
match, and the game is otherwise untouched. Snapshot building is wrapped in
`pcall`, so a nil from any game API cannot take FretBots down with it.

## Notes and limitations

- **Requires FretBots mode.** `Telemetry.lua` lives in the vscripts VM, which is
  only loaded when FretBots is manually enabled. The Workshop-only install does
  not run it.
- **HTTP from the game VM is unverified.** `Chat.lua` calls `CreateHTTPRequest`
  against a remote host, but `docs/BOT_API_REFERENCE.md:941` documents that
  function as localhost-only. This module targets localhost, which should be the
  permitted case either way — but it has not been confirmed in a live match.
  If no ticks arrive, that is the first thing to check.
- **Captures contain Steam IDs and player names.** `data/` is gitignored. Do not
  commit or share captures.
- Roshan and rune state are not captured yet. Both are worth adding before the
  data is used for anything behavioural.
