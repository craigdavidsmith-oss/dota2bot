--[[ CDS-PATCH: this build reads its own settings, and only its own.

     Upstream loads "game/Customize/general" first and falls back to the copy
     inside the bot folder. That override exists so Workshop users' settings
     survive Workshop updates -- Steam replaces the bot folder, but leaves
     vscripts/game alone.

     This build is not a Workshop item. It runs as the Local Dev Script from a real
     vscripts/bots folder that Steam never touches, so there is nothing for the
     override to survive. Worse, game/Customize is shared: the Workshop Open Hyper
     AI reads the very same file. Preferring it here meant the two builds
     silently used one another's settings, and it is also what caused the
     split-brain where custom_loader callers read one file while the mode_*.lua
     files (which require Customize/general directly) read another.

     So: bot folder copy first, always. game/Customize is left entirely to the
     Workshop build. The override is kept only as a last resort, in case the bot
     folder copy is missing or fails to load. ]]
local Customize = nil
function LoadCustomize()
	if Customize then return Customize end

	local ok, tSet = pcall(function()
		if GetScriptDirectory() == 'bots' then return require('bots.Customize.general') end
		return require( GetScriptDirectory()..'/Customize/general' )
	end)
	if ok and tSet then
		Customize = tSet
		return Customize
	end

	print( '[WARN] Could not load the bot folder Customize/general, falling back to game/Customize: '..tostring(tSet) )
	local okOverride, tOverride = pcall(require, "game/Customize/general")
	if okOverride and tOverride then
		Customize = tOverride
	else
		-- Nothing loaded. An empty table leaves every Customize.Enable check false,
		-- so the bots run on defaults rather than erroring on a nil index -- which
		-- would silently drop every bot to Valve's default AI.
		print( '[WARN] No Customize settings could be loaded; running on defaults.' )
		Customize = {}
	end
	return Customize
end
return LoadCustomize()
