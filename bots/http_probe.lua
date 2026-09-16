--[[ ==========================================================================
     CDS-PATCH: standalone HTTP probe.

     Answers one question and nothing else: can the vscripts VM reach the local
     telemetry sidecar? Load it from the Dota console in a lobby, no game needed:

         sv_cheats 1
         script_reload_code bots/http_probe

     Expected output when everything works:

         [Probe] CreateHTTPRequest      = function
         [Probe] CreateRemoteHTTPRequest= function
         [Probe] sending via CreateHTTPRequest to http://127.0.0.1:8642/tick
         [Probe] CALLBACK FIRED status=200
         [Probe] SUCCESS

     A missing CALLBACK line is the interesting failure: it means the request was
     built and dispatched but the VM never ran the completion handler, which is
     what a blocked or sandboxed request looks like from in here.

     This file is standalone on purpose. It requires nothing from the rest of the
     codebase, so it cannot be broken by an unrelated load error.
     ========================================================================== ]]

local HOST = 'http://127.0.0.1:8642'

local function Say(msg)
	print('[Probe] ' .. tostring(msg))
end

Say('---- http probe starting ----')
Say('CreateHTTPRequest      = ' .. type(CreateHTTPRequest))
Say('CreateRemoteHTTPRequest= ' .. type(CreateRemoteHTTPRequest))

-- A deliberately tiny, hand-built body: no json library, no game API calls, so
-- nothing but the transport itself is under test.
local body = '{"session_id":"probe","tick":0,"dota_time":0,'
	.. '"players":[],"note":"http_probe"}'

local function Attempt(ctorName, ctor, route)
	if ctor == nil then
		Say('skipping ' .. ctorName .. ': not available in this VM')
		return false
	end

	local url = HOST .. '/' .. route
	Say('sending via ' .. ctorName .. ' to ' .. url)

	local ok, err = pcall(function()
		local request = ctor('POST', url)
		if request == nil then
			Say(ctorName .. ' returned nil')
			return
		end
		request:SetHTTPRequestHeaderValue('Content-Type', 'application/json')
		request:SetHTTPRequestRawPostBody('application/json', body)
		request:Send(function(response)
			if response == nil then
				Say('CALLBACK FIRED but response was nil (' .. ctorName .. ')')
				return
			end
			Say('CALLBACK FIRED status=' .. tostring(response.StatusCode)
				.. ' via ' .. ctorName)
			if response.StatusCode == 200 then
				Say('SUCCESS - the sidecar received it. Check the server window.')
			else
				Say('reached something, but not a 200. Body: '
					.. tostring(response.Body))
			end
		end)
		Say(ctorName .. ' dispatched, waiting for callback...')
	end)

	if not ok then
		Say(ctorName .. ' THREW: ' .. tostring(err))
		return false
	end
	return true
end

Attempt('CreateHTTPRequest', CreateHTTPRequest, 'tick')
Attempt('CreateRemoteHTTPRequest', CreateRemoteHTTPRequest, 'tick')

Say('---- probe dispatched; callbacks arrive asynchronously ----')
Say('If no CALLBACK line appears within a few seconds, the request was')
Say('built but never completed - the VM is blocking it.')
