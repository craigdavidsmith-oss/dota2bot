@echo off
setlocal EnableDelayedExpansion

REM ===========================================================================
REM  deploy-bots.bat
REM
REM  Copies this repo's bots\ folder into the Dota 2 vscripts\bots directory.
REM  Put this file in the ROOT of your repo (next to the bots folder) and run it
REM  by double-clicking, or from a terminal.
REM
REM    deploy-bots.bat           copy files, leave anything extra alone
REM    deploy-bots.bat clean     mirror exactly, DELETING files in the target
REM                              that are not in the repo (asks first)
REM
REM  Use "clean" after you rename or delete a script file, otherwise the stale
REM  copy stays behind in the Dota folder and still gets loaded.
REM ===========================================================================

REM --- Optional manual override. If auto-detection fails, put your Dota path
REM --- here, e.g.  set "DOTA_DIR=D:\SteamLibrary\steamapps\common\dota 2 beta"
set "DOTA_DIR="

set "SRC=%~dp0bots"
set "RELPATH=game\dota\scripts\vscripts\bots"

echo.
echo  === Dota 2 bot script deploy ===
echo.

REM --- Sanity check the source ------------------------------------------------
if not exist "%SRC%\bot_generic.lua" (
    echo  [ERROR] Could not find "%SRC%\bot_generic.lua"
    echo.
    echo  This script must sit in the repo root, alongside the bots folder.
    echo  It is currently looking in: %~dp0
    goto :fail
)

REM --- Find Dota ---------------------------------------------------------------
if defined DOTA_DIR goto :havedota

REM 1. Steam's own install path from the registry
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Valve\Steam" /v SteamPath 2^>nul') do set "STEAMPATH=%%B"
if not defined STEAMPATH (
    for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" /v InstallPath 2^>nul') do set "STEAMPATH=%%B"
)
if defined STEAMPATH set "STEAMPATH=!STEAMPATH:/=\!"

if defined STEAMPATH (
    if exist "!STEAMPATH!\steamapps\common\dota 2 beta\%RELPATH%\.." (
        set "DOTA_DIR=!STEAMPATH!\steamapps\common\dota 2 beta"
        goto :havedota
    )
)

REM 2. Dota is often on a different drive. Walk the Steam library list.
if defined STEAMPATH (
    set "LIBVDF=!STEAMPATH!\steamapps\libraryfolders.vdf"
    if exist "!LIBVDF!" (
        for /f usebackq^ tokens^=4^ delims^=^" %%P in (`findstr /i /c:"\"path\"" "!LIBVDF!"`) do (
            set "LIB=%%P"
            set "LIB=!LIB:\\=\!"
            if exist "!LIB!\steamapps\common\dota 2 beta\%RELPATH%\.." (
                set "DOTA_DIR=!LIB!\steamapps\common\dota 2 beta"
                goto :havedota
            )
        )
    )
)

REM 3. Common fallbacks
for %%D in (
    "C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta"
    "C:\Steam\steamapps\common\dota 2 beta"
    "D:\Steam\steamapps\common\dota 2 beta"
    "D:\SteamLibrary\steamapps\common\dota 2 beta"
) do (
    if exist "%%~D\%RELPATH%\.." (
        set "DOTA_DIR=%%~D"
        goto :havedota
    )
)

echo  [ERROR] Could not locate your Dota 2 install.
echo.
echo  Find the folder called "dota 2 beta" yourself, then open this file in
echo  Notepad and set it near the top, like this:
echo.
echo      set "DOTA_DIR=D:\SteamLibrary\steamapps\common\dota 2 beta"
echo.
goto :fail

:havedota
set "DEST=%DOTA_DIR%\%RELPATH%"

REM Verify the parent exists. Refuse to create a whole tree at a guessed path --
REM that is how you end up "deploying" into a folder Dota never reads.
if not exist "%DOTA_DIR%\game\dota\scripts\vscripts" (
    echo  [ERROR] Found "%DOTA_DIR%"
    echo          but "%DOTA_DIR%\game\dota\scripts\vscripts" does not exist.
    echo.
    echo  That is not a real Dota install, or the layout has changed.
    goto :fail
)

echo   Source: %SRC%
echo   Target: %DEST%
echo.

REM --- Copy --------------------------------------------------------------------
set "MODE=/E"
if /i "%~1"=="clean" (
    echo  CLEAN MODE: files in the target that are not in the repo will be DELETED.
    echo.
    set /p "CONFIRM=  Continue? [y/N] "
    if /i not "!CONFIRM!"=="y" (
        echo.
        echo  Cancelled. Nothing was changed.
        goto :done
    )
    set "MODE=/MIR"
    echo.
)

robocopy "%SRC%" "%DEST%" %MODE% /NFL /NDL /NJH /NJS /NP /R:2 /W:1
set "RC=%ERRORLEVEL%"

REM Robocopy uses exit codes as a bitmask. Anything under 8 is success.
if %RC% GEQ 8 (
    echo.
    echo  [ERROR] Copy failed ^(robocopy code %RC%^).
    echo.
    echo  Most likely cause: Dota 2 has the files open, or Steam is updating.
    echo  Close Dota and try again. If it persists, run this as Administrator.
    goto :fail
)

REM --- Stamp the build ---------------------------------------------------------
REM Written to the DESTINATION only, so deploying never dirties your git tree.
set "GITHASH="
set "DIRTY="
for /f "delims=" %%H in ('git -C "%~dp0." rev-parse --short HEAD 2^>nul') do set "GITHASH=%%H"
if defined GITHASH (
    git -C "%~dp0." diff --quiet >nul 2>&1 || set "DIRTY=+edits"
) else (
    set "GITHASH=nogit"
)

set "WHEN="
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format 'MM-dd HH:mm'" 2^>nul') do set "WHEN=%%T"

set "STAMPFILE=%DEST%\FunLib\build_stamp.lua"
> "%STAMPFILE%" echo local ____exports = {}
>>"%STAMPFILE%" echo ____exports.id = "%GITHASH%%DIRTY% @ %WHEN%"
>>"%STAMPFILE%" echo return ____exports

if %RC%==0 (
    echo   Files already up to date.
) else (
    echo   Done. Scripts deployed.
)
echo   Build stamp: %GITHASH%%DIRTY% @ %WHEN%

echo.
echo   The bots announce this stamp in team chat during hero selection.
echo   If it does not match the line above, you are running an old copy.
echo.
echo   Reminder: lobby server location must be set to "Local Host",
echo   and unsubscribe from the Workshop version or it may take precedence.

:done
echo.
if "%~1"=="" pause
exit /b 0

:fail
echo.
if "%~1"=="" pause
exit /b 1
