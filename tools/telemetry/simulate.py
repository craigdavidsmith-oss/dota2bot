#!/usr/bin/env python3
"""
Drives the telemetry sidecar with a synthetic match.

Neither of us can run Dota, so this is the only end-to-end test available: it
POSTs payloads shaped exactly like the ones bots/FretBots/Telemetry.lua builds,
which exercises the server, the on-disk format, and report.py without a game.

It does NOT validate the Lua side. Only a real match can do that.

Usage:
    python tools/telemetry/simulate.py
    python tools/telemetry/simulate.py --ticks 40 --url http://127.0.0.1:8642
"""

import argparse
import json
import random
import urllib.error
import urllib.request

HEROES = [
    ("npc_dota_hero_juggernaut", "Radiant", True, 1),
    ("npc_dota_hero_lina", "Radiant", True, 2),
    ("npc_dota_hero_axe", "Radiant", True, 3),
    ("npc_dota_hero_lion", "Radiant", True, 4),
    ("npc_dota_hero_crystal_maiden", "Radiant", True, 5),
    ("npc_dota_hero_phantom_assassin", "Dire", False, 1),
    ("npc_dota_hero_zuus", "Dire", True, 2),
    ("npc_dota_hero_tidehunter", "Dire", True, 3),
    ("npc_dota_hero_ogre_magi", "Dire", True, 4),
    ("npc_dota_hero_oracle", "Dire", True, 5),
]

ANCIENTS = {"Radiant": (-7200.0, -6666.0), "Dire": (7000.0, 6000.0)}
TOWER_NAMES = ["TopTier1", "TopTier2", "TopTier3", "MidTier1", "MidTier2",
               "MidTier3", "BotTier1", "BotTier2", "BotTier3"]


def post(url, route, payload):
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{url}/{route}", data=body,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(request, timeout=5) as response:
        return response.status, response.read().decode("utf-8")


def snapshot(session_id, tick, dota_time, state):
    players = []
    for pid, (hero, team, is_bot, role) in enumerate(HEROES):
        stat = state[pid]
        ancient = ANCIENTS[team]
        # Push players progressively further from their own ancient over the
        # match so the "advance" figure in report.py has something to show.
        reach = min(1.0, max(0.0, dota_time / 2400.0)) * random.uniform(0.6, 1.3)
        pos_x = ancient[0] + (0 - ancient[0]) * reach + random.uniform(-800, 800)
        pos_y = ancient[1] + (0 - ancient[1]) * reach + random.uniform(-800, 800)

        if random.random() < 0.08:
            stat["deaths"] += 1
        if random.random() < 0.10:
            stat["kills"] += 1
        if random.random() < 0.15:
            stat["assists"] += 1

        level = min(30, 1 + int(dota_time / 90))
        players.append({
            "player_id": pid,
            "steam_id": f"7656119{pid:010d}",
            "hero": hero,
            "name": hero.replace("npc_dota_hero_", ""),
            "team": team,
            "is_bot": is_bot,
            "role": role,
            "lane": random.choice([1, 2, 3]),
            "is_alive": random.random() > 0.12,
            "level": level,
            "health": random.randint(200, 2400),
            "max_health": 600 + level * 120,
            "mana": random.randint(50, 900),
            "max_mana": 300 + level * 60,
            "kills": stat["kills"],
            "deaths": stat["deaths"],
            "assists": stat["assists"],
            "net_worth": int(600 + dota_time * random.uniform(4.0, 9.0)),
            "gold": random.randint(0, 3000),
            "last_hits": int(dota_time / 12 * random.uniform(0.4, 1.6)),
            "denies": int(dota_time / 90 * random.uniform(0.0, 1.5)),
            "items": [{"slot": s, "name": f"item_placeholder_{s}"} for s in range(random.randint(0, 6))],
            "pos": {"x": round(pos_x, 1), "y": round(pos_y, 1)},
        })

    def towers(fraction_down):
        out = {}
        for i, name in enumerate(TOWER_NAMES):
            alive = (i / len(TOWER_NAMES)) >= fraction_down
            out[name] = {"alive": alive, "health": 1800 if alive else 0}
        return out

    progress = min(0.8, dota_time / 3000.0)
    return {
        "session_id": session_id,
        "tick": tick,
        "dota_time": dota_time,
        "absolute_time": dota_time + 90,
        "game_state": 5,
        "host_id": "76561190000000000",
        "version": "simulated",
        "team_kills": {
            "Radiant": sum(state[p]["kills"] for p in range(0, 5)),
            "Dire": sum(state[p]["kills"] for p in range(5, 10)),
        },
        "towers": {"Radiant": towers(progress), "Dire": towers(progress * 0.7)},
        "players": players,
    }


def main():
    parser = argparse.ArgumentParser(description="Drive the telemetry sidecar with a fake match")
    parser.add_argument("--url", default="http://127.0.0.1:8642")
    parser.add_argument("--ticks", type=int, default=30)
    parser.add_argument("--interval", type=int, default=30, help="simulated game seconds per tick")
    parser.add_argument("--seed", type=int, default=None)
    args = parser.parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    session_id = f"sim-{random.randint(10**6, 10**7 - 1)}"
    state = {pid: {"kills": 0, "deaths": 0, "assists": 0} for pid in range(len(HEROES))}

    try:
        status, _ = post(args.url, "start", snapshot(session_id, 0, -90, state))
        print(f"start  -> {status}")

        for tick in range(1, args.ticks + 1):
            payload = snapshot(session_id, tick, tick * args.interval, state)
            status, _ = post(args.url, "tick", payload)
            print(f"tick {tick:>3} -> {status}  t={payload['dota_time']}s")

        final = snapshot(session_id, args.ticks + 1, (args.ticks + 1) * args.interval, state)
        final["match"] = {
            "winning_team": random.choice(["Radiant", "Dire"]),
            "time_passed": (args.ticks + 1) * args.interval,
            "mode": "Normal",
            "host_id": "76561190000000000",
        }
        status, _ = post(args.url, "end", final)
        print(f"end    -> {status}")
        print(f"\nsession {session_id} written. Now run:\n    python tools/telemetry/report.py")

    except urllib.error.URLError as exc:
        print(f"\ncannot reach sidecar at {args.url}: {exc}")
        print("start it first:  python tools/telemetry/server.py")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
