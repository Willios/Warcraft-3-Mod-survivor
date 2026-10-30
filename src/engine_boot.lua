-- Warcraft Survivors: entry point for the standalone engine (engine/).
--
-- The engine runs this after src/ashenvale_survivor.lua on top of an official
-- melee map (see CLAUDE.md, "Standalone engine"). The map keeps its own JASS
-- config, so players and start locations stay as Blizzard authored them; this
-- main replaces the map's melee main, so no town halls or melee rules start.
--
-- Same rule as the main script: never type a percent sign in this file.

-- The game starts on the menu map behind a quiet (black) load; entering a
-- zone loads its arena map behind a loading screen. loading is the row of
-- [LoadingScreens] in UI\WorldEditData.txt drawn behind the zone's text.
SURVIVOR_ENGINE = {
    menu = 'Maps\\FrozenThrone\\(6)Moonglade.w3x',
    arenas = {
        [1] = {map = 'Maps\\FrozenThrone\\(6)Moonglade.w3x', loading = 34}, -- Ashenvale: Night Elf campaign art
    },
}

function main()
    InitBlizzard()

    -- Melee maps place creep camps; the survivor waves own the arena instead.
    local creeps = CreateGroup()
    GroupEnumUnitsOfPlayer(creeps, Player(PLAYER_NEUTRAL_AGGRESSIVE), nil)
    ForGroup(creeps, function()
        RemoveUnit(GetEnumUnit())
    end)
    DestroyGroup(creeps)

    Survivor_Start()
end
