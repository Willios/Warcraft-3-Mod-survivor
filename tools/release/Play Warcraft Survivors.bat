@echo off
rem Warcraft Survivors (open-realm engine). Uses the bundled Warcraft III Legacy
rem folder if present; otherwise it asks for a local 1.29 (Legacy, MPQ) install.
rem The chosen folder is remembered in wc3path.txt next to this file.
setlocal
cd /d "%~dp0"

set "WC3=%~dp0Warcraft III Legacy"
call :check "%WC3%" && goto run

set "WC3="
if exist wc3path.txt set /p WC3=<wc3path.txt
if defined WC3 (call :check "%WC3%" && goto run)

for %%D in (
  "C:\Program Files (x86)\Warcraft III (Legacy)"
  "C:\Program Files (x86)\Warcraft III"
  "C:\Program Files\Warcraft III (Legacy)"
  "C:\Program Files\Warcraft III"
  "C:\Games\Warcraft III"
) do (
  call :check %%D && (set "WC3=%%~D" & goto save)
)

:ask
echo Warcraft III 1.29 (Legacy) was not found.
echo Pick the folder that contains War3.mpq and War3x.mpq.
set "WC3="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -STA -Command "Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = 'Warcraft III 1.29 folder (contains War3x.mpq)'; if ($d.ShowDialog() -eq 'OK') { $d.SelectedPath }"`) do set "WC3=%%P"
if not defined WC3 goto :eof
call :check "%WC3%" && goto save
echo.
echo "%WC3%" is not a Warcraft III 1.29 install (War3x.mpq or Maps\FrozenThrone missing).
echo Reforged (1.32+) does not work: it has no MPQ files.
echo.
goto ask

:save
> wc3path.txt echo %WC3%

:run
start "" openwarcraft3.exe -data "%WC3%" -tft ^
  +set vid_fullscreen 2 +set vid_native 1 ^
  +set wc3_loading_quiet 1 +set scr_showfps 0 ^
  +set wc3_lua_script "Scripts/Survivor/ashenvale_survivor.lua,Scripts/Survivor/engine_boot.lua" ^
  +map "Maps/FrozenThrone/(6)Moonglade.w3x"
goto :eof

:check
if not exist "%~1\War3.mpq" exit /b 1
if not exist "%~1\War3x.mpq" exit /b 1
if not exist "%~1\Maps\FrozenThrone\(6)Moonglade.w3x" exit /b 1
exit /b 0
