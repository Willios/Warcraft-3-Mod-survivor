-- Test aid: rates a map as a survivor arena. Logs ARENA lines (playable rect,
-- walkable share of rings around the center, the hero's spawn) with the same
-- walk check as the script (terrain pathing plus a hidden item probe), frames
-- the center like the run camera for +screenshot, then quits after 6 s.
-- Run alone as wc3_lua_script; it replaces the map's main.
function main()
    InitBlizzard()
    BlzHideOriginFrames(true)
    BlzFrameSetAllPoints(BlzGetOriginFrame(ORIGIN_FRAME_WORLD_FRAME, 0), BlzGetOriginFrame(ORIGIN_FRAME_GAME_UI, 0))
    local creeps = CreateGroup()
    GroupEnumUnitsOfPlayer(creeps, Player(PLAYER_NEUTRAL_AGGRESSIVE), nil)
    ForGroup(creeps, function()
        RemoveUnit(GetEnumUnit())
    end)
    DestroyGroup(creeps)
    FogEnable(false)
    FogMaskEnable(false)
    SuspendTimeOfDay(true)
    SetFloatGameState(GAME_STATE_TIME_OF_DAY, 12)

    local area = bj_mapInitialPlayableArea
    local cx, cy = GetRectCenterX(area), GetRectCenterY(area)
    local probe = CreateItem(FourCC('afac'), cx, cy)
    SetItemVisible(probe, false)
    local function walkable(x, y)
        if IsTerrainPathable(x, y, PATHING_TYPE_WALKABILITY) then
            return false
        end
        SetItemPosition(probe, x, y)
        local dx, dy = GetItemX(probe) - x, GetItemY(probe) - y
        SetItemVisible(probe, false)
        return dx * dx + dy * dy < 100
    end
    local f = math.floor
    print('ARENA rect ' .. f(GetRectMinX(area)) .. ' ' .. f(GetRectMinY(area)) .. ' ' .. f(GetRectMaxX(area))
        .. ' ' .. f(GetRectMaxY(area)) .. ' center ' .. f(cx) .. ' ' .. f(cy))
    print('ARENA center walkable ' .. tostring(walkable(cx, cy)))
    for _, r in ipairs({200, 400, 650, 900, 1250, 1600}) do
        local ok, n = 0, 48
        for i = 1, n do
            local a = i * 6.28318530718 / n
            if walkable(cx + r * math.cos(a), cy + r * math.sin(a)) then
                ok = ok + 1
            end
        end
        print('ARENA ring ' .. r .. ' walkable ' .. ok .. '/' .. n)
    end

    EnableUserControl(false)
    local anchor = CreateUnit(Player(0), FourCC('hfoo'), cx, cy, 270)
    TimerStart(CreateTimer(), 0.1, false, function()
        ResetToGameCamera(0)
        SetCameraTargetController(anchor, 0, 0, false)
        SetCameraField(CAMERA_FIELD_TARGET_DISTANCE, 2600, 0)
        SetCameraField(CAMERA_FIELD_ANGLE_OF_ATTACK, 304, 0)
        SetCameraField(CAMERA_FIELD_ROTATION, 90, 0)
        SetCameraField(CAMERA_FIELD_FARZ, 6000, 0)
    end)
    TimerStart(CreateTimer(), 6, false, function()
        EngineQuit()
    end)
end
