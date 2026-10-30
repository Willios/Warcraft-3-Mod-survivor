-- Test add-on: prints the hero's weapon sound type and churns floating text
-- tags (lifespan 0.3 s) to check that expired tags free their slot.
local old = Survivor_Start
function Survivor_Start()
    old()
    TimerStart(CreateTimer(), 3.0, false, function()
        local g = CreateGroup()
        GroupEnumUnitsOfPlayer(g, Player(0), nil)
        ForGroup(g, function()
            local u = GetEnumUnit()
            if IsUnitType(u, UNIT_TYPE_HERO) then
                print('HITFX weapon sound type ' .. tostring(BlzGetUnitWeaponIntegerField(u, UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND, 0)))
            end
        end)
        DestroyGroup(g)
        local made, failed = 0, 0
        TimerStart(CreateTimer(), 0.05, true, function()
            local tag = CreateTextTag()
            if tag then
                made = made + 1
                SetTextTagText(tag, 'x', 0.02)
                SetTextTagPos(tag, 0, 0, 60)
                SetTextTagPermanent(tag, false)
                SetTextTagLifespan(tag, 0.3)
            else
                failed = failed + 1
            end
            if made + failed == 250 then
                print('HITFX texttags made ' .. made .. ' failed ' .. failed)
                PauseTimer(GetExpiredTimer())
            end
        end)
    end)
end
