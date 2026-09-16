@echo off
setlocal EnableDelayedExpansion

REM ===========================================================================
REM  start-telemetry.bat
REM
REM  Starts the local telemetry sidecar in this window. Leave it running while
REM  you play, then read the capture with:
REM
REM      python tools\telemetry\report.py
REM
REM  Ctrl+C stops it. Captures land in tools\telemetry\data\ and never leave
REM  this machine.
REM ===========================================================================

set "PORT=8642"
set "SERVER=%~dp0tools\telemetry\server.py"

echo.
echo  === OHA telemetry sidecar ===
echo.

if not exist "%SERVER%" (
    echo  [ERROR] Could not find "%SERVER%"
    echo.
    echo  This script must sit in the repo root, alongside the tools folder.
    echo  It is currently looking in: %~dp0
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
    echo  [ERROR] Python was not found on PATH.
    echo.
    echo  Install Python 3, or edit this file and set PY to the full path of
    echo  python.exe, e.g.
    echo      set "PY=C:\Python313\python.exe"
    goto :fail
)

REM --- Refuse to start a second copy on the same port ---------------------------
netstat -ano | findstr /r /c:"LISTENING" | findstr /c:":%PORT% " >nul 2>&1
if not errorlevel 1 (
    echo  [ERROR] Something is already listening on port %PORT%.
    echo.
    echo  The sidecar is probably already running in another window. Use that
    echo  one, or close it before starting a new one.
    goto :fail
)

echo   Python: %PY%
echo   Server: %SERVER%
echo.
echo   Leave this window open while you play. Ctrl+C to stop.
echo.

"%PY%" "%SERVER%" --port %PORT%

echo.
echo   Sidecar stopped.
goto :done

:fail
echo.
if "%~1"=="" pause
exit /b 1

:done
echo.
if "%~1"=="" pause
exit /b 0
