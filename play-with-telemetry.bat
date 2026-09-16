@echo off
setlocal EnableDelayedExpansion

REM ===========================================================================
REM  play-with-telemetry.bat
REM
REM  One-click launcher: deploys the bot scripts, starts the telemetry sidecar
REM  in its own window, then launches Dota 2.
REM
REM  Designed to be copied to the Desktop, so it does NOT locate the repo
REM  relative to itself. Set REPO below if you ever move the repo.
REM ===========================================================================

REM --- Where the repo lives. Edit this if you move it. -------------------------
set "REPO=C:\DotaBots\work"

REM --- Set to 0 to skip the deploy step and just start telemetry + Dota --------
set "DO_DEPLOY=1"

set "PORT=8642"
set "STEAM_APPID=570"

echo.
echo  === Dota 2 + OHA telemetry ===
echo.

if not exist "%REPO%\tools\telemetry\server.py" (
    echo  [ERROR] Could not find the repo at:
    echo      %REPO%
    echo.
    echo  Open this file in Notepad and correct the REPO line near the top.
    goto :fail
)

REM --- Find Python -------------------------------------------------------------
set "PY="
for /f "delims=" %%P in ('where python 2^>nul') do (
    if not defined PY set "PY=%%P"
)
if not defined PY (
    for /f "delims=" %%P in ('where py 2^>nul') do (
        if not defined PY set "PY=%%P"
    )
)
if not defined PY (
    echo  [ERROR] Python was not found on PATH. Install Python 3, or edit this
    echo  file and set PY to the full path of python.exe.
    goto :fail
)

REM --- Deploy first, while Dota is definitely not holding the files open --------
if "%DO_DEPLOY%"=="1" (
    if exist "%REPO%\deploy-bots.bat" (
        echo  [1/3] Deploying bot scripts...
        echo.
        REM The argument is what suppresses deploy-bots.bat's own pause; any
        REM value other than "clean" means a normal non-destructive copy.
        call "%REPO%\deploy-bots.bat" auto
        if errorlevel 1 (
            echo.
            echo  [ERROR] Deploy failed. Not launching. See the message above.
            goto :fail
        )
        echo.
    ) else (
        echo  [1/3] Skipping deploy - deploy-bots.bat not found.
        echo.
    )
) else (
    echo  [1/3] Deploy disabled in this script ^(DO_DEPLOY=0^).
    echo.
)

REM --- Telemetry ---------------------------------------------------------------
netstat -ano | findstr /r /c:"LISTENING" | findstr /c:":%PORT% " >nul 2>&1
if not errorlevel 1 (
    echo  [2/3] Telemetry already running on port %PORT% - leaving it alone.
) else (
    echo  [2/3] Starting telemetry sidecar...
    start "OHA Telemetry" cmd /k ""%PY%" "%REPO%\tools\telemetry\server.py" --port %PORT%"
)
echo.

REM --- Dota --------------------------------------------------------------------
echo  [3/3] Launching Dota 2...
start "" "steam://rungameid/%STEAM_APPID%"
echo.

echo  ---------------------------------------------------------------------
echo   Once in game:
echo.
echo     1. Create a Custom Lobby
echo          - server location "Local Host"
echo          - TICK "Enable Cheats"     ^(required^)
echo     2. Start the game and WAIT for the map to finish loading
echo     3. Open the console ^(`^) and type these two lines:
echo.
echo            sv_cheats 1
echo            script_reload_code bots/FretBots
echo.
echo        FretBots is NOT a menu option. Without this command the
echo        telemetry module never loads and nothing is recorded.
echo     4. The console should answer with:
echo            Open Hyper AI ^(OHA^). Starting Fretbots mode: ...
echo            [Telemetry] session ... -^> http://127.0.0.1:%PORT%
echo     5. Watch the telemetry window for a tick line every 30 seconds
echo.
echo   Afterwards, from %REPO%:
echo       python tools\telemetry\report.py
echo.
echo   No [Telemetry] line at all  = FretBots never loaded ^(step 3^)
echo   "sidecar unreachable"       = it loaded but could not connect
echo  ---------------------------------------------------------------------
echo.

pause
exit /b 0

:fail
echo.
pause
exit /b 1
