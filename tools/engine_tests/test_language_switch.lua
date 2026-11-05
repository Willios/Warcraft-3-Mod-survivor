-- Test add-on: asks for German the way the Language window does, then the engine
-- must quit by itself with fs_language archived. Run it with APPDATA set to an empty
-- folder (it writes config.cfg), then test_language.lua must find German without
-- being told.
function main()
    print('LANG before = ' .. EngineCvar('fs_language'))
    local t = CreateTimer()
    TimerStart(t, 2.0, false, function()
        print('LANG asking for deDE')
        EngineLanguage('deDE')
    end)
end
