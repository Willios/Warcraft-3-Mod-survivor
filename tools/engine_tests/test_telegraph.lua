-- Test aid (add-on): draws every ground telegraph shape around the hero in a
-- loop, for screenshots of the WoW-style warnings (EngineTelegraph). Keeps the
-- hero alive (a death ends the run and saves the real profile), logs TELEGRAPH
-- lines and quits after telegraph_len seconds (default 25).
-- Each 3.5 s cycle: a circle on the hero (2.0 s cast), a cone north-east (2.6 s),
-- a line south of it (1.6 s) and a ring east (3.0 s), so one screenshot
-- shows the fills at different stages and the line's impact flash.
-- With +set telegraph_shapes 0 +set survivor_boss final it only keeps the hero
-- alive while a boss casts its spells at it.
-- Run: +set survivor_run "5 1 1 2" +map "Maps/FrozenThrone/(6)Moonglade.w3x"
--      +set wc3_lua_script ".../ashenvale_survivor.lua,.../engine_boot.lua,.../test_telegraph.lua"
local old = Survivor_Start
function Survivor_Start()
    old()
    local length = tonumber(EngineCvar('telegraph_len')) or 25
    local function hero()
        local found = nil
        local g = CreateGroup()
        GroupEnumUnitsOfPlayer(g, Player(0), nil)
        ForGroup(g, function()
            if IsUnitType(GetEnumUnit(), UNIT_TYPE_HERO) then
                found = GetEnumUnit()
            end
        end)
        DestroyGroup(g)
        return found
    end
    TimerStart(CreateTimer(), 0.1, true, function()
        local h = hero()
        if h and GetWidgetLife(h) > 0.405 then
            SetWidgetLife(h, BlzGetUnitMaxHP(h))
        end
    end)
    local elapsed = 0
    -- +set telegraph_shapes 0: only keep the hero alive (boss spells with +set survivor_boss).
    local shapes = EngineCvar('telegraph_shapes') ~= '0'
    local function cycle()
        local h = hero()
        if h == nil then
            return
        end
        local x, y = GetUnitX(h), GetUnitY(h)
        local ids = {
            EngineTelegraph({shape = 'circle', x = x, y = y, radius = 240, duration = 2.0}),
            EngineTelegraph({shape = 'cone', x = x + 80, y = y + 120, angle = 35, radius = 520, arc = 70, duration = 2.6}),
            EngineTelegraph({shape = 'line', x = x - 150, y = y - 430, angle = 0, length = 750, width = 160, duration = 1.6}),
            EngineTelegraph({shape = 'ring', x = x + 720, y = y - 150, radius = 230, inner = 100, duration = 3.0}),
        }
        print(string.format('TELEGRAPH t=\037.1f hero=\037.0f,\037.0f ids=\037s', elapsed, x, y, table.concat(ids, ' ')))
    end
    -- +set telegraph_kite 1: every 1.5 s the hero heads for a point 520 away from
    -- the strongest enemy, circling it, so its spells land at range.
    local kite = EngineCvar('telegraph_kite') == '1'
    local homeX, homeY = nil, nil
    local kiteX, kiteY = nil, nil
    TimerStart(CreateTimer(), 1.5, true, function()
        local h = hero()
        if not kite or h == nil then
            return
        end
        local x, y = GetUnitX(h), GetUnitY(h)
        homeX, homeY = homeX or x + 350, homeY or y - 100
        local boss, best = nil, 0
        local g = CreateGroup()
        GroupEnumUnitsOfPlayer(g, Player(11), nil)
        ForGroup(g, function()
            local u = GetEnumUnit()
            if GetWidgetLife(u) > 0.405 and BlzGetUnitMaxHP(u) > best then
                boss, best = u, BlzGetUnitMaxHP(u)
            end
        end)
        DestroyGroup(g)
        local tx, ty = homeX, homeY
        if boss and best > 1000 then
            local bx, by = GetUnitX(boss), GetUnitY(boss)
            local a = math.atan(y - by, x - bx) + 0.7
            tx, ty = bx + 520 * math.cos(a), by + 520 * math.sin(a)
            -- Stay in the open ground east of the spawn (the forest is to the north-west).
            if math.abs(tx - homeX) > 550 or math.abs(ty - homeY) > 400 then
                tx, ty = homeX + (homeX - bx) * 0.5, homeY + (homeY - by) * 0.5
            end
        end
        kiteX, kiteY = tx, ty
    end)
    -- A right-click does nothing when the profile plays with WASD, so the hero
    -- slides there itself (about 300 a second).
    TimerStart(CreateTimer(), 0.05, true, function()
        local h = hero()
        if h == nil or kiteX == nil then
            return
        end
        local x, y = GetUnitX(h), GetUnitY(h)
        local dx, dy = kiteX - x, kiteY - y
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 20 then
            SetUnitPosition(h, x + dx / d * 15, y + dy / d * 15)
        end
    end)
    TimerStart(CreateTimer(), 0.5, true, function()
        elapsed = elapsed + 0.5
        if shapes and elapsed >= 2 and math.fmod(elapsed, 3.5) == 0 then
            cycle()
        end
        if elapsed >= length then
            EngineQuit()
        end
    end)
end
