-- Test aid: enters a zone the way the lobby does (survivor_run, then ChangeLevel
-- to that zone's arena from SURVIVOR_ENGINE) and logs ZONERUN lines on the
-- arena: enemy count and hero position every 5 s, then quits after 40 s.
-- Add it after the main scripts in wc3_lua_script and set
-- +set zone_change "<hero> <zone> <difficulty> <key>".
local old = Survivor_Start
function Survivor_Start()
    old()
    local wanted = EngineCvar('zone_change')
    if wanted ~= '' then
        EngineCvar('zone_change', '')
        local zone = tonumber(wanted:match('^\037d+ (\037d+)'))
        TimerStart(CreateTimer(), 2.0, false, function()
            EngineCvar('survivor_run', wanted)
            -- The zone's loading screen, as Engine.loadingScreen sets it.
            EngineCvar('wc3_loading_quiet', '0')
            EngineCvar('wc3_loading_background', tostring(SURVIVOR_ENGINE.arenas[zone].loading))
            print('ZONERUN change to ' .. SURVIVOR_ENGINE.arenas[zone].map)
            ChangeLevel(SURVIVOR_ENGINE.arenas[zone].map, false)
        end)
        return
    end
    local elapsed = 0
    TimerStart(CreateTimer(), 5.0, true, function()
        elapsed = elapsed + 5
        local enemies, hero = 0, nil
        local g = CreateGroup()
        GroupEnumUnitsOfPlayer(g, Player(11), nil)
        ForGroup(g, function()
            if GetWidgetLife(GetEnumUnit()) > 0.405 then
                enemies = enemies + 1
            end
        end)
        GroupEnumUnitsOfPlayer(g, Player(0), nil)
        ForGroup(g, function()
            if IsUnitType(GetEnumUnit(), UNIT_TYPE_HERO) then
                hero = GetEnumUnit()
            end
        end)
        DestroyGroup(g)
        local where = hero and (math.floor(GetUnitX(hero)) .. ' ' .. math.floor(GetUnitY(hero)) .. ' life '
            .. math.floor(GetWidgetLife(hero))) or 'none'
        print('ZONERUN t ' .. elapsed .. ' enemies ' .. enemies .. ' hero ' .. where)
        if elapsed >= 40 then
            EngineQuit()
        end
    end)
end
