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
--  USAGE -- wait until the hero grid is actually on screen, then run:
--
--      sv_cheats 1
--      script_reload_code bots/SameHero
--
--  and check the console shows "[SameHero] Same-hero selection ENABLED". No
--  line means no flag: the file did not run.
--
--  Ways it fails to run without an obvious error:
--    - Too early. Typed during the loading screen, the command lands before the
--      server's script VM exists and is dropped with "[VScript] Scripting
--      disabled or no server running". That line, logged at map spawn ten
--      seconds before hero selection opened, is the likely cause of the failed
--      attempts on 2026-09-25. Wait for the hero grid.
--    - Wrong path. It is bots/SameHero. A bare "SameHero" looks in the vscripts
--      root, where there is no such file.
--
--  Timing against the BOTS does not matter. Bot SelectHero() calls skip the
--  engine's uniqueness check entirely: on 2026-09-25 five and six bots took
--  Pudge in matches where this flag was never set. The rule binds HUMAN picks
--  only. So the one ordering that matters is flag first, then humans pick --
--  humans should hold off until you have seen the line above.
--
--  (An earlier version of this note claimed a ~24s window before the bots pick.
--  Wrong twice over: GameTime() includes the loading screen, so X.IsHumanNotReady's
--  GameTime() > 20 cutoff has usually expired before the grid even appears and
--  the first bot picks ~6s in; and as above, the bots never needed the flag.)
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
