-- Kills player 1's hero after a few seconds to show the end screen (test only).
local old = Survivor_Start
function Survivor_Start()
    old()
    TimerStart(CreateTimer(), 4.0, false, function()
        local g = CreateGroup()
        GroupEnumUnitsOfPlayer(g, Player(0), nil)
        ForGroup(g, function()
            local u = GetEnumUnit()
            if IsUnitType(u, UNIT_TYPE_HERO) then
                KillUnit(u)
            end
        end)
        DestroyGroup(g)
    end)
end
