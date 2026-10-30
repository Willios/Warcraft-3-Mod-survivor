-- Test aid: the arena from the run camera with no UI, under the zone's fog and
-- time of day, for the lobby's zone thumbnail. Run alone as wc3_lua_script
-- with +screenshot; it replaces the map's main.
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
    local area = bj_mapInitialPlayableArea
    local x = GetRectCenterX(area) + tonumber(EngineCvar('shot_dx') ~= '' and EngineCvar('shot_dx') or '0')
    local y = GetRectCenterY(area) + tonumber(EngineCvar('shot_dy') ~= '' and EngineCvar('shot_dy') or '0')
    FogEnable(false)
    FogMaskEnable(false)
    SuspendTimeOfDay(true)
    if EngineCvar('shot_fog') == '1' then
        SetTerrainFogEx(0, 900, 4200, 0.5, 0.10, 0.16, 0.22)
    end
    SetFloatGameState(GAME_STATE_TIME_OF_DAY, tonumber(EngineCvar('shot_time') ~= '' and EngineCvar('shot_time') or '0'))
    EnableUserControl(false)
    local anchor = CreateUnit(Player(0), FourCC('hfoo'), x, y, 270)
    ShowUnit(anchor, false)
    TimerStart(CreateTimer(), 0.1, false, function()
        ResetToGameCamera(0)
        SetCameraTargetController(anchor, 0, 0, false)
        SetCameraField(CAMERA_FIELD_TARGET_DISTANCE, 1850, 0)
        SetCameraField(CAMERA_FIELD_ANGLE_OF_ATTACK, 304, 0)
        SetCameraField(CAMERA_FIELD_ROTATION, 90, 0)
        SetCameraField(CAMERA_FIELD_FARZ, 5000, 0)
    end)
end
