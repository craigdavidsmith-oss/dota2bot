#!/usr/bin/env python3
"""
Offline reader for telemetry captured by server.py.

Summarises one match log and derives the first cut of the per-player
descriptive statistics that a playstyle profiler would be built on. Nothing
here learns anything; it exists so a capture can be verified without the game
running, and so the shape of the data is visible before anything consumes it.

Usage:
    python tools/telemetry/report.py                  # newest log in data/
    python tools/telemetry/report.py path/to/log.jsonl
    python tools/telemetry/report.py --list
"""

import argparse
import json
import math
import sys
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent / "data"

# Approximate ancient positions in Dota world coordinates. Used only to turn
# raw positions into a crude "how far forward does this player play" number.
ANCIENTS = {"Radiant": (-7200.0, -6666.0), "Dire": (7000.0, 6000.0)}


def load(path):
    records = []
    with path.open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as exc:
                print(f"  ! skipping malformed line {line_no}: {exc}", file=sys.stderr)
    return records


def newest_log():
    logs = sorted(DATA_DIR.glob("*.jsonl"), key=lambda p: p.stat().st_mtime)
    return logs[-1] if logs else None


def fmt_time(seconds):
    if seconds is None:
        return "?"
    seconds = int(seconds)
    sign = "-" if seconds < 0 else ""
    seconds = abs(seconds)
    return f"{sign}{seconds // 60}:{seconds % 60:02d}"


def summarise(records):
    starts = [r for r in records if r.get("type") == "start"]
    ticks = [r for r in records if r.get("type") == "tick"]
    ends = [r for r in records if r.get("type") == "end"]

    print(f"records      {len(records)}  ({len(starts)} start, {len(ticks)} tick, {len(ends)} end)")
    if not (starts or ticks or ends):
        print("nothing to summarise")
        return

    first = (starts or ticks or ends)[0]["payload"]
    print(f"session      {first.get('session_id')}")
    print(f"version      {first.get('version')}   build {first.get('build', '?')}")

    if ticks:
        span_start = ticks[0]["payload"].get("dota_time")
        span_end = ticks[-1]["payload"].get("dota_time")
        print(f"clock span   {fmt_time(span_start)} -> {fmt_time(span_end)}")

    if ends:
        match = ends[-1]["payload"].get("match") or {}
        if match:
            print(f"winner       {match.get('winning_team', '?')}"
                  f"   duration {fmt_time(match.get('time_passed'))}"
                  f"   mode {match.get('mode', '?')}")

    # ---- per-player aggregation ------------------------------------------
    players = {}
    for rec in ticks:
        for entry in rec["payload"].get("players") or []:
            pid = entry.get("player_id")
            if pid is None:
                continue
            acc = players.setdefault(pid, {
                "hero": entry.get("hero"),
                "name": entry.get("name"),
                "team": entry.get("team"),
                "is_bot": entry.get("is_bot"),
                "samples": 0,
                "dead_samples": 0,
                "advance": [],
                "last": entry,
            })
            acc["last"] = entry
            acc["samples"] += 1
            if entry.get("is_alive") is False:
                acc["dead_samples"] += 1

            pos = entry.get("pos") or {}
            ancient = ANCIENTS.get(entry.get("team"))
            if ancient and pos.get("x") is not None and pos.get("y") is not None:
                dist = math.hypot(pos["x"] - ancient[0], pos["y"] - ancient[1])
                acc["advance"].append(dist)

    if not players:
        print("\nno per-player tick data captured")
        return

    print(f"\n{'hero':<26}{'side':<9}{'who':<7}{'K/D/A':<11}{'net':<8}{'lvl':<5}{'dead%':<7}{'advance'}")
    print("-" * 86)
    for pid in sorted(players):
        acc = players[pid]
        last = acc["last"]
        kda = f"{last.get('kills', 0)}/{last.get('deaths', 0)}/{last.get('assists', 0)}"
        dead_pct = (acc["dead_samples"] / acc["samples"] * 100) if acc["samples"] else 0
        advance = sum(acc["advance"]) / len(acc["advance"]) if acc["advance"] else 0
        who = "bot" if acc["is_bot"] else "HUMAN"
        hero = (acc["hero"] or "?").replace("npc_dota_hero_", "")
        print(f"{hero:<26}{acc['team']:<9}{who:<7}{kda:<11}"
              f"{last.get('net_worth', 0) or 0:<8}{last.get('level', 0) or 0:<5}"
              f"{dead_pct:<7.0f}{advance:.0f}")

    print("\nadvance = mean distance from own ancient across all ticks; higher means")
    print("the player spent more of the match pushed up the map.")

    humans = [p for p in players.values() if not p["is_bot"]]
    if humans:
        print(f"\n{len(humans)} human player(s) in this match - the profiling target.")


def main():
    parser = argparse.ArgumentParser(description="Inspect an OHA telemetry capture")
    parser.add_argument("log", nargs="?", type=Path, help="JSONL file (default: newest in data/)")
    parser.add_argument("--list", action="store_true", help="list captures and exit")
    args = parser.parse_args()

    if args.list:
        logs = sorted(DATA_DIR.glob("*.jsonl"))
        if not logs:
            print(f"no captures in {DATA_DIR}")
        for path in logs:
            print(f"{path.name}  {path.stat().st_size / 1024:.1f} KB")
        return

    path = args.log or newest_log()
    if path is None:
        print(f"no captures found in {DATA_DIR}", file=sys.stderr)
        sys.exit(1)
    if not path.exists():
        print(f"no such file: {path}", file=sys.stderr)
        sys.exit(1)

    print(f"file         {path.name}\n")
    summarise(load(path))


if __name__ == "__main__":
    main()
