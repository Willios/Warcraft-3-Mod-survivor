-- Test aid: drives the hero with the orders a right-click gives and logs what
-- the engine plays (EngineUnitAnimation) and where the hero stands.
-- Run with +set survivor_run "5 1 1 2" (Blademaster) and add this file to
-- wc3_lua_script. Lines start with MOVEANIM; the run quits after 30 s.
local t = CreateTimer()
local elapsed = 0
local hero = nil
local startX, startY = 0, 0
local nextClick = 1.0
local leg = 0
local treeClicked = false
-- +set moveanim_clicks 0: only log; the clicks come from a cfg sending the
-- client's real right-click command (tools/engine_clicks.py).
local scripted = EngineCvar('moveanim_clicks') ~= '0'

local function findHero()
    local g = CreateGroup()
    GroupEnumUnitsOfPlayer(g, Player(0), nil)
    local found = nil
    ForGroup(g, function()
        local u = GetEnumUnit()
        if found == nil and IsUnitType(u, UNIT_TYPE_HERO) then
            found = u
        end
    end)
    DestroyGroup(g)
    return found
end

TimerStart(t, 0.1, true, function()
    elapsed = elapsed + 0.1
    if hero == nil then
        hero = findHero()
        if hero then
            startX, startY = GetUnitX(hero), GetUnitY(hero)
        end
        return
    end
    local x, y = GetUnitX(hero), GetUnitY(hero)
    -- At 20 s: right-click the nearest tree (a target order with no unit).
    -- The hero must walk to the tree, not to the middle of the map.
    if scripted and elapsed >= 20 and not treeClicked then
        treeClicked = true
        local best, bestD = nil, 1e12
        EnumDestructablesInRect(Rect(x - 1500, y - 1500, x + 1500, y + 1500), nil, function()
            local d = GetEnumDestructable()
            local dx, dy = GetDestructableX(d) - x, GetDestructableY(d) - y
            if dx * dx + dy * dy < bestD then
                best, bestD = d, dx * dx + dy * dy
            end
        end)
        if best then
            print(string.format('MOVEANIM tree at \0375.0f,\0375.0f', GetDestructableX(best), GetDestructableY(best)))
            IssueTargetOrder(hero, 'smart', best)
        else
            print('MOVEANIM no tree found')
        end
    end
    -- Walk a square 500 away from the start, one click per corner, re-clicking
    -- every 0.4 s like a player steering.
    if scripted and elapsed < 20 and elapsed >= nextClick then
        nextClick = elapsed + 0.4
        leg = leg + 1
        local corner = math.floor(leg / 6)
        local dx = (math.fmod(corner, 2) == 0) and 500 or -500
        local dy = (math.fmod(math.floor(corner / 2), 2) == 0) and 500 or -500
        IssuePointOrder(hero, 'move', startX + dx, startY + dy)
    end
    local name, frame, upper = EngineUnitAnimation(hero)
    print(string.format('MOVEANIM t=\0374.1f anim=[\037s] frame=\037d upper=[\037s] pos=\0375.0f,\0375.0f fromStart=\0374.0f',
        elapsed, name, frame, upper, x, y, math.sqrt((x - startX) ^ 2 + (y - startY) ^ 2)))
    if elapsed >= 30 then
        EngineQuit()
    end
end)
