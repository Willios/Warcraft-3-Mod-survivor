-- Test aid: audits a zone arena. Logs the player slots (controller, slot
-- state, team), who the local player is, who owns the hero, and every 0.5 s the
-- hero's position, speed (distance per second), animation and the enemy count.
-- Keeps the hero alive (heals every 0.1 s). Steers the hero with scripted
-- move orders unless +set moveanim_clicks 0 (real clicks from a cfg).
-- Run with +set survivor_run "5 6 1 2" (Blademaster, Northrend) and add this
-- file to wc3_lua_script. Lines start with AUDIT; quits after audit_seconds (40).
local t = CreateTimer()
local elapsed = 0
local hero = nil
local startX, startY = 0, 0
local lastX, lastY = 0, 0
local nextClick = 1.0
local nextLog = 0
local leg = 0
local scripted = EngineCvar('moveanim_clicks') ~= '0'
local limit = tonumber(EngineCvar('audit_seconds') or '') or 40

-- Counts the script's own position writes on the hero, to tell scripted
-- movement from native movement.
local scriptMoves = 0
local nativeSetUnitX = SetUnitX
SetUnitX = function(u, x)
    if hero ~= nil and u == hero then
        scriptMoves = scriptMoves + 1
    end
    return nativeSetUnitX(u, x)
end

local function findHero()
    local found = nil
    for p = 0, 11 do
        local g = CreateGroup()
        GroupEnumUnitsOfPlayer(g, Player(p), nil)
        ForGroup(g, function()
            local u = GetEnumUnit()
            if found == nil and IsUnitType(u, UNIT_TYPE_HERO) then
                found = u
            end
        end)
        DestroyGroup(g)
    end
    return found
end

local function countUnits(p)
    local g = CreateGroup()
    GroupEnumUnitsOfPlayer(g, Player(p), nil)
    local n = 0
    ForGroup(g, function()
        if GetWidgetLife(GetEnumUnit()) > 0.405 then
            n = n + 1
        end
    end)
    DestroyGroup(g)
    return n
end

print(string.format('AUDIT local=\037d playable=\0375.0f,\0375.0f..\0375.0f,\0375.0f',
    GetPlayerId(GetLocalPlayer()), GetRectMinX(bj_mapInitialPlayableArea), GetRectMinY(bj_mapInitialPlayableArea),
    GetRectMaxX(bj_mapInitialPlayableArea), GetRectMaxY(bj_mapInitialPlayableArea)))
for p = 0, 15 do
    local pl = Player(p)
    print(string.format('AUDIT slot \037d controller=\037d state=\037d team=\037d units=\037d',
        p, GetHandleId(GetPlayerController(pl)), GetHandleId(GetPlayerSlotState(pl)), GetPlayerTeam(pl), countUnits(p)))
end

TimerStart(t, 0.1, true, function()
    elapsed = elapsed + 0.1
    if hero == nil then
        hero = findHero()
        if hero then
            startX, startY = GetUnitX(hero), GetUnitY(hero)
            lastX, lastY = startX, startY
            print(string.format('AUDIT hero owner=\037d at \0375.0f,\0375.0f movespeed=\0375.1f',
                GetPlayerId(GetOwningPlayer(hero)), startX, startY, GetUnitMoveSpeed(hero)))
        end
        return
    end
    SetWidgetLife(hero, GetUnitState(hero, UNIT_STATE_MAX_LIFE))
    local x, y = GetUnitX(hero), GetUnitY(hero)
    if scripted and elapsed < limit - 5 and elapsed >= nextClick then
        nextClick = elapsed + 0.4
        leg = leg + 1
        local corner = math.floor(leg / 6)
        local dx = (math.fmod(corner, 2) == 0) and 500 or -500
        local dy = (math.fmod(math.floor(corner / 2), 2) == 0) and 500 or -500
        IssuePointOrder(hero, 'move', startX + dx, startY + dy)
    end
    if elapsed >= 2 and elapsed < 2.1 then
        print('AUDIT cl_fkeys=' .. tostring(EngineCvar('cl_fkeys')))
        local heroes = 0
        for p = 0, 15 do
            local g = CreateGroup()
            GroupEnumUnitsOfPlayer(g, Player(p), nil)
            ForGroup(g, function()
                local u = GetEnumUnit()
                if IsUnitType(u, UNIT_TYPE_HERO) then
                    heroes = heroes + 1
                    print(string.format('AUDIT hero \037s owner=\037d at \0375.0f,\0375.0f Amov=\037d Aatk=\037d',
                        GetUnitName(u), p, GetUnitX(u), GetUnitY(u),
                        GetUnitAbilityLevel(u, FourCC('Amov')), GetUnitAbilityLevel(u, FourCC('Aatk'))))
                end
            end)
            DestroyGroup(g)
            print(string.format('AUDIT player \037d units=\037d', p, countUnits(p)))
        end
    end
    if elapsed >= nextLog then
        nextLog = elapsed + 0.5
        local name, frame, upper = EngineUnitAnimation(hero)
        local speed = math.sqrt((x - lastX) ^ 2 + (y - lastY) ^ 2) / 0.5
        lastX, lastY = x, y
        print(string.format('AUDIT t=\0374.1f pos=\0375.0f,\0375.0f speed=\0374.0f ms=\0373.0f anim=[\037s] upper=[\037s] enemies=\037d owner=\037d order=\037s scriptMoves=\037d',
            elapsed, x, y, speed, GetUnitMoveSpeed(hero), name, upper, countUnits(11), GetPlayerId(GetOwningPlayer(hero)),
            tostring(OrderId2String(GetUnitCurrentOrder(hero))), scriptMoves))
    end
    if elapsed >= limit then
        EngineQuit()
    end
end)
