-- Test aid: the survivor hero's walk check drops a hidden item and reads it
-- back; retail pushes the item off trees. Prints, for a few trees on the map,
-- how far SetItemPosition moved the probe (0 = the tree does not block).
-- Run alone as wc3_lua_script on a map with trees (it replaces the map's main).
function main()
    InitBlizzard()
    TimerStart(CreateTimer(), 1.0, false, function()
        local probe = CreateItem(FourCC('afac'), 0, 0)
        local found, blocked = 0, 0
        EnumDestructablesInRect(GetPlayableMapRect(), nil, function()
            local d = GetEnumDestructable()
            if found >= 8 or GetDestructableLife(d) <= 0 then
                return
            end
            found = found + 1
            local x, y = GetDestructableX(d), GetDestructableY(d)
            SetItemPosition(probe, x, y)
            local dx, dy = GetItemX(probe) - x, GetItemY(probe) - y
            local moved = math.sqrt(dx * dx + dy * dy)
            if moved > 10 then
                blocked = blocked + 1
            end
            print(string.format('TREES tree at %.0f %.0f: probe moved %.0f', x, y, moved))
        end)
        -- An open point must keep the probe exactly where it was put.
        SetItemPosition(probe, 0, 0)
        print(string.format('TREES open ground: probe at %.1f %.1f', GetItemX(probe), GetItemY(probe)))
        print('TREES blocked ' .. blocked .. ' of ' .. found)
    end)
end
