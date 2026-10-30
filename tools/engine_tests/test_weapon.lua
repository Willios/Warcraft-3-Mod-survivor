-- Test aid: prints the weapon fields the survivor script reads, for a few heroes.
-- Run alone as wc3_lua_script on any melee map (it replaces the map's main).
function main()
    InitBlizzard()
    print('PROBE start')
    TimerStart(CreateTimer(), 1.0, false, function()
        print('PROBE timer')
        for _, id in ipairs({'Hamg', 'Hblm', 'Ofar', 'Emoo', 'Obla', 'Nngs'}) do
            local u = CreateUnit(Player(0), FourCC(id), 0, 0, 0)
            print('PROBE unit', id, tostring(u))
            print('PROBE range', BlzGetUnitWeaponRealField(u, UNIT_WEAPON_RF_ATTACK_RANGE, 0))
            print('PROBE speed', BlzGetUnitWeaponRealField(u, UNIT_WEAPON_RF_ATTACK_PROJECTILE_SPEED, 0))
            print('PROBE art', BlzGetUnitWeaponStringField(u, UNIT_WEAPON_SF_ATTACK_PROJECTILE_ART, 0))
            print('PROBE cd', BlzGetUnitAttackCooldown(u, 0))
        end
        print('PROBE icon', BlzGetAbilityIcon(FourCC('Rhar')), BlzGetAbilityIcon(FourCC('Rhme')))
    end)
end
