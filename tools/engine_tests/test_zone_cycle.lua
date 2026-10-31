-- Test aid (add-on): goes back and forth between the menu map and a zone the
-- way a long session does (Enter zone, Return to Camp), to measure memory
-- across map loads. Start on the menu map with
--   +set zone_cycle <count> +set zone_cycle_run "<hero> <zone> <difficulty> <key>"
-- Each map logs a CYCLE line; the hero is kept at full health on the zone
-- (a death would end the run and save the profile). Quits when the count is spent.
local old = Survivor_Start
function Survivor_Start()
    old()
    local left = tonumber(EngineCvar('zone_cycle')) or 0
    local onZone = EngineCvar('zone_cycle_at') == 'zone'
    print('CYCLE left ' .. left .. ' on ' .. (onZone and 'zone' or 'menu'))
    if onZone then
        TimerStart(CreateTimer(), 0.1, true, function()
            local g = CreateGroup()
            GroupEnumUnitsOfPlayer(g, Player(0), nil)
            ForGroup(g, function()
                local u = GetEnumUnit()
                if IsUnitType(u, UNIT_TYPE_HERO) and GetWidgetLife(u) > 0.405 then
                    SetWidgetLife(u, BlzGetUnitMaxHP(u))
                end
            end)
            DestroyGroup(g)
        end)
    end
    TimerStart(CreateTimer(), onZone and 20.0 or 3.0, false, function()
        if onZone then
            EngineCvar('zone_cycle', tostring(left - 1))
            EngineCvar('zone_cycle_at', 'menu')
            EngineCvar('survivor_run', '')
            ChangeLevel(SURVIVOR_ENGINE.menu, false)
        elseif left <= 0 then
            EngineQuit()
        else
            local wanted = EngineCvar('zone_cycle_run')
            local zone = tonumber(wanted:match('^\037d+ (\037d+)'))
            EngineCvar('zone_cycle_at', 'zone')
            EngineCvar('survivor_run', wanted)
            ChangeLevel(SURVIVOR_ENGINE.arenas[zone].map, false)
        end
    end)
end
