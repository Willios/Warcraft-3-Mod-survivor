-- Test aid (add-on): stress the Plaguelands roster's casters. On the arena it
-- keeps the hero alive and, every 10 s, spawns Necromancers, Banshees, Meat
-- Wagons, Obsidian Statues and the bosses' unit types next to it for the enemy
-- player, plus a few units killed on the spot (corpses to raise). Logs PLAGUE
-- lines (time, enemy count, last batch) so a crash shows how far it got, and
-- quits after plague_len seconds (default 240).
-- Run: +set survivor_run "5 4 1 2" +map "Maps/(8)Plaguelands.w3m"
--      +set wc3_lua_script ".../ashenvale_survivor.lua,.../engine_boot.lua,.../test_plague.lua"
--      +exec pickcards.cfg
local old = Survivor_Start
function Survivor_Start()
    old()
    local length = tonumber(EngineCvar('plague_len')) or 240
    local only = EngineCvar('plague_units') or ''
    local types = {'unec', 'uban', 'umtw', 'uobs', 'uabo', 'ucry', 'ugar', 'nfgu', 'ufro'}
    if only ~= '' then
        types = {}
        for id in only:gmatch('[A-Za-z0-9]+') do
            types[#types + 1] = id
        end
    end
    local enemy = Player(11)
    local elapsed, wave = 0, 0
    local spawnX, spawnY = nil, nil
    -- Full health ten times a second: a once-a-second heal let a big pack kill
    -- the hero in between, and a death ends the run and saves the real profile.
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
    TimerStart(CreateTimer(), 1.0, true, function()
        elapsed = elapsed + 1
        local hero = nil
        local g = CreateGroup()
        GroupEnumUnitsOfPlayer(g, Player(0), nil)
        ForGroup(g, function()
            if IsUnitType(GetEnumUnit(), UNIT_TYPE_HERO) then
                hero = GetEnumUnit()
            end
        end)
        if hero then
            SetWidgetLife(hero, BlzGetUnitMaxHP(hero))
        end
        -- +set plague_move 1: walk the hero (a right-click every 3 s) around a
        -- 1600-wide loop, so the camera crosses the map like in a real run.
        if hero and spawnX == nil then
            spawnX, spawnY = GetUnitX(hero), GetUnitY(hero)
        end
        if hero and EngineCvar('plague_move') == '1' and math.fmod(elapsed, 3) == 0 then
            local a = elapsed / 3 * 0.9
            IssuePointOrder(hero, 'smart', spawnX + 1600 * math.cos(a) * (0.5 + 0.5 * math.sin(a * 0.37)),
                spawnY + 1600 * math.sin(a) * (0.5 + 0.5 * math.cos(a * 0.23)))
        end
        if hero and math.fmod(elapsed, 10) == 3 then
            wave = wave + 1
            local x, y = GetUnitX(hero), GetUnitY(hero)
            local made = {}
            for i, id in ipairs(types) do
                local a = i * 0.7 + wave
                local u = CreateUnit(enemy, FourCC(id), x + math.cos(a) * 500, y + math.sin(a) * 500, 0)
                if u then
                    IssueTargetOrder(u, 'attack', hero)
                    made[#made + 1] = id
                end
            end
            -- Corpses for Raise Dead and the Meat Wagon.
            for i = 1, 4 do
                local c = CreateUnit(enemy, FourCC('ugho'), x + 300 * math.cos(i), y + 300 * math.sin(i), 0)
                if c then
                    KillUnit(c)
                end
            end
            print('PLAGUE wave ' .. wave .. ' made ' .. table.concat(made, ' '))
        end
        if math.fmod(elapsed, 5) == 0 then
            local enemies, byType = 0, {}
            GroupEnumUnitsOfPlayer(g, enemy, nil)
            ForGroup(g, function()
                local u = GetEnumUnit()
                if GetWidgetLife(u) > 0.405 then
                    enemies = enemies + 1
                    local id = string.pack('<I4', GetUnitTypeId(u))
                    byType[id] = (byType[id] or 0) + 1
                end
            end)
            local parts = {}
            for id, n in pairs(byType) do
                parts[#parts + 1] = id .. '=' .. n
            end
            table.sort(parts)
            print('PLAGUE t ' .. elapsed .. ' enemies ' .. enemies .. ' ' .. table.concat(parts, ' '))
        end
        DestroyGroup(g)
        if elapsed >= length then
            print('PLAGUE done')
            EngineQuit()
        end
    end)
end
