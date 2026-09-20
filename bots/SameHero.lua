--==============================================================================
--  CDS-PATCH: same-hero selection toggle.
--
--  Runs in the VSCRIPTS VM, not the bot VM. What blocks two players from taking
--  the same hero is the engine, not the bot scripts, and the only handle on it
--  is a GameRules binding:
--
--      server.dll: "When true, players can repeatedly pick the same hero."
--                  SetSameHeroSelectionEnabled
--
--  GameRules does not exist in the bot VM, so bots/hero_selection.lua cannot do
--  this itself. Same deal as FretBots and Buff: it has to be a console command,
--  by hand, once per match.
--
--  USAGE -- open the console the moment the map has finished loading, while you
--  are still in hero selection, and run:
--
--      sv_cheats 1
--      script_reload_code bots/SameHero
--
--  Do it BEFORE anyone readies up. hero_selection.lua holds the bots back while
--  a human is unpicked (X.IsHumanNotReady), but that gate expires at GameTime()
--  20 regardless, and the first bot picks about 4s after that. So you have
--  roughly 24 seconds from map load. If you miss the window, restart the lobby.
--
--  Pair with Customize.Mirror_Hero in bots/Customize/general.lua to make every
--  bot take one hero. This file on its own only lifts the restriction; it does
--  not change what anybody picks.
--==============================================================================

if GameRules == nil then
	print('[SameHero] No GameRules in this VM -- this file is vscripts-only.')
	print('[SameHero] Run it from the Dota console: script_reload_code bots/SameHero')
	return
end

local nState = GameRules:State_Get()

if nState > DOTA_GAMERULES_STATE_HERO_SELECTION then
	print('[SameHero] [WARN] Hero selection is already over (state: '..tostring(nState)..').')
	print('[SameHero] [WARN] Setting the flag anyway, but picks already locked in will stand.')
	print('[SameHero] [WARN] Restart the lobby and run this during hero selection instead.')
end

GameRules:SetSameHeroSelectionEnabled(true)

print('[SameHero] Same-hero selection ENABLED -- every player may now take the same hero.')
print('[SameHero] Once per match. Set Customize.Mirror_Hero to force the bots onto one hero.')
