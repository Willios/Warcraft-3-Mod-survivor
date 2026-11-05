-- Test add-on: prints what the mounted language gives the script, then quits.
-- Run with +set fs_language deDE +set extra_data <folder with War3zzLang_deDE.mpq>.
local function show(code)
    print('LANG ' .. code .. ' = ' .. tostring(GetObjectName(FourCC(code))))
end

local previous = main
function main()
    if previous then
        previous()
    end
    print('LANG fs_language = ' .. EngineCvar('fs_language'))
    for _, code in ipairs({'Hamg', 'Obla', 'AHbz', 'AOcl', 'AUfn', 'ankh', 'ugho', 'Ulic'}) do
        show(code)
    end
    local t = CreateTimer()
    TimerStart(t, 2.0, false, function()
        EngineQuit()
    end)
end
