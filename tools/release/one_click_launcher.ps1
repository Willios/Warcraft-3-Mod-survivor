$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$engine = Join-Path $root 'openwarcraft3.exe'
$wc3Data = Join-Path $root 'Warcraft III Legacy'
$arguments = '-data "{0}" -tft +set vid_fullscreen 2 +set vid_native 1 +set wc3_loading_quiet 1 +set scr_showfps 0 +set wc3_lua_script "Scripts/Survivor/ashenvale_survivor.lua,Scripts/Survivor/engine_boot.lua" +map "Maps/FrozenThrone/(6)Moonglade.w3x"' -f $wc3Data

$game = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $root -PassThru -Wait
exit $game.ExitCode
