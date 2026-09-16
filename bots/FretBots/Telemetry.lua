--[[ ==========================================================================
     CDS-PATCH: local match telemetry.

     Periodically snapshots match state and POSTs it to a telemetry sidecar
     running on this machine (tools/telemetry/server.py), which appends it to a
     JSONL file. Nothing is sent anywhere else.

     This runs in the vscripts VM alongside the rest of FretBots, not in the bot
     VM. That matters: this file is loaded exactly once per match rather than
     once per bot, so there is no need to elect a single writer the way the bot
     VM would require.

     Fails open in every direction. If the sidecar is not running, requests fail,
     a handful of failures disables the module for the rest of the match, and the
     game is otherwise untouched. Snapshot building is wrapped in pcall so a nil
     from any game API can never take FretBots down with it.
     ========================================================================== ]]

local json = require('bots.ts_libs.utils.json')
local Version = require 'bots.FunLib.version'
require 'bots.FretBots.Timers'
require 'bots.FretBots.Utilities'

local Telemetry = {}

-- ===== Configuration ======================================================

-- Master switch. Set false to compile the module in but send nothing.
Telemetry.enabled = true

-- Sidecar base URL. Must be localhost: the bot/vscripts HTTP sandbox is
-- documented as permitting local connections only.
Telemetry.host = 'http://127.0.0.1:8642'

-- Game seconds between snapshots. 30 keeps a 40 minute match under ~80 ticks,
-- which is plenty of resolution for positional and timing analysis.
Telemetry.tickInterval = 30

-- Consecutive transport failures before this module gives up for the match.
Telemetry.maxFailures = 5

-- Per-request console logging. Leave on until a capture has been confirmed in a
-- real match; the whole point is that silence is otherwise indistinguishable
-- from success.
Telemetry.verbose = true

-- ===== Internal state =====================================================

local RADIANT = 2
local DIRE = 3

local timerName = 'ohaTelemetryTick'
local sessionId = nil
local tickIndex = 0
local failureCount = 0
local isDisabled = false
local isStarted = false

-- ===== Helpers ============================================================

-- Deliberately arithmetic-only: the Dota Lua VM is 5.1 and has no bitwise
-- operators, so hashing has to be done with multiply/modulo.
local function MakeSessionId()
	local stamp = GetSystemTime()
	if type(stamp) == 'string' then stamp = string.gsub(stamp, ':', '') end
	local n = tonumber(stamp) or 0
	local h = 5381
	local vals = { n, math.floor((Time() or 0) * 1000), math.random(1, 999983) }
	for i = 1, #vals do
		h = (h * 33 + math.floor(vals[i])) % 2147483647
	end
	return string.format('%d-%d', math.floor(n), h)
end

local function SafeNumber(value)
	if type(value) ~= 'number' then return nil end
	-- json.encode chokes on inf/nan; both are reachable from division by zero
	-- in derived stats, so filter them here rather than at every call site.
	if value ~= value then return nil end
	if value == math.huge or value == -math.huge then return nil end
	return value
end

-- Every game API read goes through this. A nil handle or a renamed method
-- returns nil instead of erroring out of the whole snapshot.
local function Try(fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then return nil end
	return result
end

local function UnitItems(unit)
	local items = {}
	for slot = 0, 8 do
		local item = Try(unit.GetItemInSlot, unit, slot)
		if item ~= nil then
			local name = Try(item.GetAbilityName, item)
			if name ~= nil then
				table.insert(items, { slot = slot, name = name })
			end
		end
	end
	-- Neutral item slot. Its index has moved between patches, so probe and
	-- ignore failures rather than assuming.
	local neutral = Try(unit.GetItemInSlot, unit, 16)
	if neutral ~= nil then
		local name = Try(neutral.GetAbilityName, neutral)
		if name ~= nil then
			table.insert(items, { slot = 'neutral', name = name })
		end
	end
	return items
end

local function PlayerSnapshot(unit)
	if unit == nil or unit.stats == nil then return nil end
	local stats = unit.stats
	local id = stats.id

	local origin = Try(unit.GetAbsOrigin, unit)
	local entry = {
		player_id     = id,
		steam_id      = tostring(stats.steamId),
		hero          = stats.internalName,
		name          = stats.name,
		team          = (stats.team == RADIANT) and 'Radiant' or 'Dire',
		is_bot        = stats.isBot,
		role          = stats.role,
		lane          = stats.lane,
		is_alive      = Try(unit.IsAlive, unit),
		level         = SafeNumber(Try(unit.GetLevel, unit)),
		health        = SafeNumber(Try(unit.GetHealth, unit)),
		max_health    = SafeNumber(Try(unit.GetMaxHealth, unit)),
		mana          = SafeNumber(Try(unit.GetMana, unit)),
		max_mana      = SafeNumber(Try(unit.GetMaxMana, unit)),
		kills         = SafeNumber(Try(PlayerResource.GetKills, PlayerResource, id)),
		deaths        = SafeNumber(Try(PlayerResource.GetDeaths, PlayerResource, id)),
		assists       = SafeNumber(Try(PlayerResource.GetAssists, PlayerResource, id)),
		net_worth     = SafeNumber(Try(PlayerResource.GetNetWorth, PlayerResource, id)),
		gold          = SafeNumber(Try(PlayerResource.GetGold, PlayerResource, id)),
		last_hits     = SafeNumber(Try(PlayerResource.GetLastHits, PlayerResource, id)),
		denies        = SafeNumber(Try(PlayerResource.GetDenies, PlayerResource, id)),
		items         = UnitItems(unit),
	}

	if origin ~= nil then
		entry.pos = { x = SafeNumber(origin.x), y = SafeNumber(origin.y) }
	end

	return entry
end

local function TowerSnapshot(towers)
	local result = {}
	if towers == nil then return result end
	for name, building in pairs(towers) do
		if building ~= nil then
			result[name] = {
				alive  = Try(building.IsAlive, building),
				health = SafeNumber(Try(building.GetHealth, building)),
			}
		end
	end
	return result
end

local function BuildSnapshot()
	local players = {}
	if AllUnits ~= nil then
		for _, unit in pairs(AllUnits) do
			local entry = PlayerSnapshot(unit)
			if entry ~= nil then table.insert(players, entry) end
		end
	end

	return {
		session_id     = sessionId,
		tick           = tickIndex,
		dota_time      = SafeNumber(Utilities:GetTime()),
		absolute_time  = SafeNumber(Utilities:GetAbsoluteTime()),
		game_state     = Try(GameRules.State_Get, GameRules),
		host_id        = tostring(Try(PlayerResource.GetSteamID, PlayerResource, Utilities:GetHostPlayerID())),
		version        = Version.number,
		team_kills     = {
			Radiant = SafeNumber(Try(PlayerResource.GetTeamKills, PlayerResource, RADIANT)),
			Dire    = SafeNumber(Try(PlayerResource.GetTeamKills, PlayerResource, DIRE)),
		},
		towers = {
			Radiant = TowerSnapshot(RadiantTowers),
			Dire    = TowerSnapshot(DireTowers),
		},
		players = players,
	}
end

-- ===== Transport ==========================================================

local function Log(msg)
	print('[Telemetry] ' .. tostring(msg))
end

local function Verbose(msg)
	if Telemetry.verbose then Log(msg) end
end

-- Reports which HTTP constructors this VM actually exposes. The API reference
-- (docs/BOT_API_REFERENCE.md:941) says CreateHTTPRequest is localhost-only and
-- CreateRemoteHTTPRequest is for external hosts, while Chat.lua uses the former
-- against a remote host -- so neither claim can be trusted without checking.
function Telemetry:Probe()
	local hasLocal = (CreateHTTPRequest ~= nil)
	local hasRemote = (CreateRemoteHTTPRequest ~= nil)
	Log('HTTP probe: CreateHTTPRequest=' .. tostring(hasLocal) ..
	    ' CreateRemoteHTTPRequest=' .. tostring(hasRemote))
	if not (hasLocal or hasRemote) then
		Log('NEITHER HTTP constructor exists in this VM. Nothing can be sent.')
	end
	return hasLocal or hasRemote
end

local function MakeRequest(url)
	if CreateHTTPRequest ~= nil then
		local ok, request = pcall(CreateHTTPRequest, 'POST', url)
		if ok and request ~= nil then return request, 'CreateHTTPRequest' end
	end
	if CreateRemoteHTTPRequest ~= nil then
		local ok, request = pcall(CreateRemoteHTTPRequest, 'POST', url)
		if ok and request ~= nil then return request, 'CreateRemoteHTTPRequest' end
	end
	return nil, nil
end

local function CountFailure(reason)
	failureCount = failureCount + 1
	Log(reason .. '  (failure ' .. tostring(failureCount) ..
	    ' of ' .. tostring(Telemetry.maxFailures) .. ')')
	if failureCount >= Telemetry.maxFailures then
		isDisabled = true
		Log('disabled for this match after ' .. tostring(failureCount) ..
		    ' consecutive failures.')
	end
end

local function PostInner(route, payload)
	local url = Telemetry.host .. '/' .. route

	local encoded
	local ok, err = pcall(function() encoded = json.encode(payload) end)
	if not ok or encoded == nil then
		CountFailure('encode failed for /' .. route .. ': ' .. tostring(err))
		return
	end

	local request, ctor = MakeRequest(url)
	if request == nil then
		CountFailure('could not create an HTTP request for ' .. url)
		return
	end

	Verbose('POST ' .. url .. ' via ' .. ctor .. ' (' .. tostring(#encoded) .. ' bytes)')

	request:SetHTTPRequestHeaderValue('Content-Type', 'application/json')
	request:SetHTTPRequestRawPostBody('application/json', encoded)

	request:Send(function(response)
		-- Reaching here at all proves the request was dispatched and the VM ran
		-- our callback; a silent absence of this line means it never did.
		if response == nil then
			CountFailure('callback fired with a nil response for /' .. route)
			return
		end
		if response.StatusCode == 200 then
			if failureCount > 0 then Log('recovered, sidecar responding again') end
			failureCount = 0
			Verbose('OK /' .. route .. ' -> 200')
			return
		end
		CountFailure('/' .. route .. ' -> status ' .. tostring(response.StatusCode) ..
		             ' from ' .. Telemetry.host)
	end)
end

function Telemetry:Post(route, payload)
	if isDisabled or not Telemetry.enabled then return end
	-- Wrapped because a missing or renamed HTTP API would otherwise throw out of
	-- the Timers callback that called us and kill the whole timer silently.
	local ok, err = pcall(PostInner, route, payload)
	if not ok then
		CountFailure('post to /' .. route .. ' threw: ' .. tostring(err))
	end
end

-- ===== Lifecycle ==========================================================

function Telemetry:Tick()
	if isDisabled or not Telemetry.enabled then
		Timers:RemoveTimer(timerName)
		return nil
	end

	-- Stop logging once the match is over; PostGame is handled by Finish().
	local state = Try(GameRules.State_Get, GameRules)
	if state ~= nil and state >= DOTA_GAMERULES_STATE_POST_GAME then
		Timers:RemoveTimer(timerName)
		return nil
	end

	tickIndex = tickIndex + 1

	local ok, snapshot = pcall(BuildSnapshot)
	if ok and snapshot ~= nil then
		Telemetry:Post('tick', snapshot)
	else
		Log('snapshot failed: ' .. tostring(snapshot))
	end

	return Telemetry.tickInterval
end

function Telemetry:Start()
	if isStarted then
		Log('Start() called twice; ignoring the second call.')
		return
	end
	if not Telemetry.enabled then
		Log('disabled by configuration (Telemetry.enabled = false).')
		return
	end
	isStarted = true

	sessionId = MakeSessionId()
	Log('session ' .. tostring(sessionId) .. ' -> ' .. Telemetry.host)
	Telemetry:Probe()

	local ok, snapshot = pcall(BuildSnapshot)
	if not ok or snapshot == nil then
		Log('first snapshot failed: ' .. tostring(snapshot))
		snapshot = { session_id = sessionId }
	else
		Verbose('first snapshot built with ' .. tostring(#(snapshot.players or {})) .. ' players')
		snapshot.build = Try(function() return require('bots.FunLib.build_stamp').id end)
	end
	Telemetry:Post('start', snapshot)

	Timers:CreateTimer(timerName, { endTime = Telemetry.tickInterval, callback = Telemetry['Tick'] })
	Log('tick timer armed, every ' .. tostring(Telemetry.tickInterval) .. 's')
end

-- Called at post-game. Sends one final snapshot plus the match outcome.
function Telemetry:Finish(matchData)
	if not Telemetry.enabled then return end
	Timers:RemoveTimer(timerName)

	local ok, snapshot = pcall(BuildSnapshot)
	if not ok or snapshot == nil then snapshot = { session_id = sessionId } end
	snapshot.match = matchData
	Telemetry:Post('end', snapshot)
end

-- Printed at require time. If this line is absent from the console then the
-- module never loaded at all, which is a different problem from it loading and
-- failing to send.
Log('module loaded, target ' .. Telemetry.host)

return Telemetry
