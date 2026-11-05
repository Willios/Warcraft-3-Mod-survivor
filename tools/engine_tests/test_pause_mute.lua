-- Test aid (add-on): logs MUTE lines four times a second: the world pause switch
-- (s_world_paused), the effects volume and the music volume. Add +set survivor_mute 1
-- so the run stays silent: s_world_paused still follows the pause.
-- Run alongside test_medivh.lua (keeps the hero alive) without survivor_autopick,
-- and press Escape and 1 from a cfg (tools/engine_flow.py: k27, k49).
local elapsed = 0
TimerStart(CreateTimer(), 0.25, true, function()
    elapsed = elapsed + 0.25
    print('MUTE t ' .. elapsed .. ' s_world_paused ' .. tostring(EngineCvar('s_world_paused'))
        .. ' s_volume ' .. tostring(EngineCvar('s_volume'))
        .. ' s_musicvolume ' .. tostring(EngineCvar('s_musicvolume')))
end)
