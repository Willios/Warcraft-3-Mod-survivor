
-- Test aid (add-on): how long the final boss lives against a fixed build. Heals the hero ten
-- times a second (an invulnerable hero is no target: the boss never comes), so give the build
-- plenty of health (vigor:40). The hero stands still. Logs BALANCE lines, quits when the boss dies.
-- Run: +set survivor_run "1 6 1 2" +set survivor_boss final +set survivor_autopick 1
--      +set survivor_build "pool:10:8:7:5 might:3 ferocity:2" [+set survivor_build_bonus 0.355]
--      +map "Maps/(12)IceCrown.w3m"
--      +set wc3_lua_script ".../ashenvale_survivor.lua,.../engine_boot.lua,.../test_balance.lua"
-- Use an empty APPDATA: a run that ends saves the profile.
local old = Survivor_Start
function Survivor_Start()
    old()
    local limit = tonumber(EngineCvar('balance_len')) or 240
    local elapsed, seen, boss, bossHp = 0, nil, nil, 0
    TimerStart(CreateTimer(), 0.1, true, function()
        local g = CreateGroup()
        GroupEnumUnitsOfPlayer(g, Player(0), nil)
        ForGroup(g, function()
            local u = GetEnumUnit()
            if GetWidgetLife(u) > 0.405 then
                SetWidgetLife(u, BlzGetUnitMaxHP(u))
            end
        end)
        DestroyGroup(g)
    end)
    TimerStart(CreateTimer(), 0.25, true, function()
        elapsed = elapsed + 0.25
        if boss == nil then
            local e = CreateGroup()
            GroupEnumUnitsOfPlayer(e, Player(11), nil)
            ForGroup(e, function()
                local u = GetEnumUnit()
                if GetWidgetLife(u) > 0.405 and BlzGetUnitMaxHP(u) > 5000 then
                    boss, seen, bossHp = u, elapsed, BlzGetUnitMaxHP(u)
                end
            end)
            DestroyGroup(e)
            if boss then
                print('BALANCE boss hp=' .. bossHp .. ' at=' .. elapsed)
            end
        elseif GetWidgetLife(boss) <= 0.405 then
            print('BALANCE ttk=' .. (elapsed - seen) .. ' hp=' .. bossHp .. ' dps=' .. math.floor(bossHp / math.max(0.25, elapsed - seen)))
            EngineQuit()
        end
        if elapsed >= limit then
            print('BALANCE timeout left=' .. (boss and math.floor(GetWidgetLife(boss)) or -1) .. ' of ' .. bossHp)
            EngineQuit()
        end
    end)
end
