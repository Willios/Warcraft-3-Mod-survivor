-- Ashenvale: The Long Night
-- Warcraft III Reforged Lua prototype.
-- Put this function in the map-level Custom Script Code area. Then add the
-- one-line call Survivor_Start() to a Map Initialization trigger.

function Survivor_Start()
do
    local PLAYER = Player(0)
    local HOSTILE = Player(PLAYER_NEUTRAL_AGGRESSIVE)
    local ENEMY_TYPE = FourCC('hfoo') -- Footman placeholder
    local HERO_GROUPS = {
        Alliance = {
            {id = 'Hamg', name = 'Archmage', icon = 'BTNArchMage', blizzard = 'AHbz', elemental = 'AHwe', damage = 45},
            {id = 'Hmkg', name = 'Mountain King', icon = 'BTNMtnKing', damage = 55},
            {id = 'Hpal', name = 'Paladin', icon = 'BTNHeroPaladin', damage = 48},
            {id = 'Hblm', name = 'Blood Mage', icon = 'BTNBloodMage', damage = 45}
        },
        Horde = {
            {id = 'Obla', name = 'Blademaster', icon = 'BTNBlademaster', damage = 58},
            {id = 'Ofar', name = 'Far Seer', icon = 'BTNFarseer', damage = 44},
            {id = 'Otch', name = 'Tauren Chieftain', icon = 'BTNTaurenChieftain', damage = 58},
            {id = 'Oshd', name = 'Shadow Hunter', icon = 'BTNShadowHunter', damage = 43}
        },
        Undead = {
            {id = 'Udea', name = 'Death Knight', icon = 'BTNHeroDeathKnight', damage = 52},
            {id = 'Udre', name = 'Dreadlord', icon = 'BTNDreadLord', damage = 48},
            {id = 'Ulic', name = 'Lich', icon = 'BTNLich', damage = 44},
            {id = 'Ucrl', name = 'Crypt Lord', icon = 'BTNCryptLord', damage = 55}
        },
        ['Night Elf'] = {
            {id = 'Edem', name = 'Demon Hunter', icon = 'BTNDemonHunter', damage = 55},
            {id = 'Ekee', name = 'Keeper of the Grove', icon = 'BTNKeeperOfTheGrove', damage = 43},
            {id = 'Emoo', name = 'Priestess of the Moon', icon = 'BTNHeroMoonPriestess', damage = 46},
            {id = 'Ewar', name = 'Warden', icon = 'BTNHeroWarden', damage = 54}
        },
        Tavern = {
            {id = 'Nngs', name = 'Naga Sea Witch', icon = 'BTNSeaWitch', damage = 45},
            {id = 'Nbrn', name = 'Dark Ranger', icon = 'BTNBansheeRanger', damage = 46},
            {id = 'Nbst', name = 'Beastmaster', icon = 'BTNBeastMaster', damage = 52},
            {id = 'Npbm', name = 'Pandaren Brewmaster', icon = 'BTNHeroPandarenBrewmaster', damage = 52},
            {id = 'Nfir', name = 'Firelord', icon = 'BTNFireLord', damage = 46},
            {id = 'Ntin', name = 'Goblin Tinker', icon = 'BTNTinker', damage = 45},
            {id = 'Nalc', name = 'Goblin Alchemist', icon = 'BTNHeroAlchemist', damage = 45},
            {id = 'Nplh', name = 'Pit Lord', icon = 'BTNPitLord', damage = 55},
            {id = 'Npal', name = 'Forsaken Paladin', icon = 'BTNHeroPaladin', damage = 52}
        }
    }
    local selectedFaction = 'Alliance'
    local selectedHero = HERO_GROUPS.Alliance[1]
    local selectedZone = 'Ashenvale'

    local STEP = 0.25
    local RUN_LENGTH = 600.0
    local MAX_ENEMIES = 140
    local HERO_ATTACK_INTERVAL = 0.8
    local BLIZZARD_COOLDOWN = 8.0
    local BLIZZARD_RADIUS = 300.0
    local WATER_ELEMENTAL_COOLDOWN = 20.0
    local BOSS_TIMES = {120, 240, 360, 480, 540}

    local centerX = GetRectCenterX(bj_mapInitialPlayableArea)
    local centerY = GetRectCenterY(bj_mapInitialPlayableArea)
    local minX = GetRectMinX(bj_mapInitialPlayableArea) + 192
    local maxX = GetRectMaxX(bj_mapInitialPlayableArea) - 192
    local minY = GetRectMinY(bj_mapInitialPlayableArea) + 192
    local maxY = GetRectMaxY(bj_mapInitialPlayableArea) - 192

    local hero = nil
    local enemies = {}
    local elapsed = 0.0
    local spawnClock = 0.0
    local attackClock = 0.0
    local blizzardClock = 0.0
    local blizzardWasLearned = false
    local elementalClock = 0.0
    local elementalWasLearned = false
    local waterElemental = nil
    local nextBoss = 1
    local experience = 0
    local totalKills = 0
    local level = 1
    local experienceToNext = 5
    local heroDamage = selectedHero.damage
    local heroRange = 700.0
    local heroSpeed = 300.0
    local upgradePending = false
    local upgradesQueued = 0
    local ended = false
    local keysDown = {w = false, a = false, s = false, d = false}
    local lobbyFrames = {}
    local hudFrames = {}
    local heroListButtons = {}
    local lobbyHeroName = nil
    local lobbyHeroDetails = nil
    local lobbyHeroIcon = nil
    local lobbyZoneDetails = nil
    local hudClock = nil
    local hudStats = nil
    local hudXpText = nil
    local hudXpFill = nil
    local hudHealthFill = nil
    local upgradePanel = nil
    local upgradeTitleFrame = nil
    local upgradeButtons = {}
    local runMessage = nil
    local gameUI = BlzGetOriginFrame(ORIGIN_FRAME_GAME_UI, 0)
    local startRun
    local applyUpgrade
    local createRunUI
    local updateRunHUD

    local function makePanel(name, x, y, width, height, alpha)
        local frame = BlzCreateFrameByType('BACKDROP', name, gameUI, '', 0)
        BlzFrameSetAbsPoint(frame, FRAMEPOINT_BOTTOMLEFT, x, y)
        BlzFrameSetSize(frame, width, height)
        BlzFrameSetTexture(frame, 'UI\\Widgets\\EscMenu\\Human\\blank-background.blp', 0, true)
        BlzFrameSetVertexColor(frame, BlzConvertColor(alpha or 225, 15, 10, 6))
        return frame
    end

    local function makeText(name, value, x, y, width, height, scale)
        local frame = BlzCreateFrameByType('TEXT', name, gameUI, '', 0)
        BlzFrameSetAbsPoint(frame, FRAMEPOINT_BOTTOMLEFT, x, y)
        BlzFrameSetSize(frame, width, height)
        BlzFrameSetText(frame, value)
        BlzFrameSetScale(frame, scale or 1.0)
        return frame
    end

    local function makeButton(name, value, x, y, width, height, parent, action)
        local frame = BlzCreateFrameByType('GLUETEXTBUTTON', name, parent or gameUI, 'ScriptDialogButton', 0)
        BlzFrameSetAbsPoint(frame, FRAMEPOINT_BOTTOMLEFT, x, y)
        BlzFrameSetSize(frame, width, height)
        BlzFrameSetText(frame, value)
        local trigger = CreateTrigger()
        BlzTriggerRegisterFrameEvent(trigger, frame, FRAMEEVENT_CONTROL_CLICK)
        TriggerAddAction(trigger, action)
        return frame
    end

    local function setFramesVisible(frames, visible)
        for _, frame in ipairs(frames) do
            BlzFrameSetVisible(frame, visible)
        end
    end

    local function updateHeroSelection()
        local heroes = HERO_GROUPS[selectedFaction]
        for index, button in ipairs(heroListButtons) do
            if heroes[index] then
                BlzFrameSetVisible(button, true)
                BlzFrameSetText(button, heroes[index].name)
            else
                BlzFrameSetVisible(button, false)
            end
        end
        BlzFrameSetText(lobbyHeroName, '|cffffcc66' .. selectedHero.name .. '|r')
        BlzFrameSetText(lobbyHeroDetails,
            selectedFaction .. ' hero\nStarts with an automatic attack.\nLearn supported abilities in-game to unlock autocasts.')
        BlzFrameSetTexture(lobbyHeroIcon,
            'ReplaceableTextures\\CommandButtons\\' .. selectedHero.icon .. '.blp', 0, true)
    end

    local function showLobby()
        BlzHideOriginFrames(true)
        local consoleBackdrop = BlzGetFrameByName('ConsoleUIBackdrop', 0)
        if consoleBackdrop ~= nil then
            BlzFrameSetVisible(consoleBackdrop, false)
        end

        local background = makePanel('AS_LobbyBG', 0.0, 0.0, 0.80, 0.60, 245)
        lobbyFrames[#lobbyFrames + 1] = background
        local title = makeText('AS_Title', '|cffffcc66WARCRAFT SURVIVORS|r', 0.22, 0.515, 0.38, 0.055, 1.8)
        lobbyFrames[#lobbyFrames + 1] = title

        local tabs = {'Character', 'Collection', 'Codex', 'Talents', 'Achievements', 'Rewards'}
        for index, label in ipairs(tabs) do
            local x = 0.055 + (index - 1) * 0.115
            local tab = makeText('AS_Tab' .. index, '|cffffcc66' .. label .. '|r', x, 0.472, 0.11, 0.028, 1.05)
            lobbyFrames[#lobbyFrames + 1] = tab
        end

        local left = makePanel('AS_HeroPanel', 0.025, 0.105, 0.245, 0.35, 235)
        local center = makePanel('AS_DetailPanel', 0.285, 0.105, 0.305, 0.35, 235)
        local right = makePanel('AS_ZonePanel', 0.605, 0.105, 0.17, 0.35, 235)
        lobbyFrames[#lobbyFrames + 1] = left
        lobbyFrames[#lobbyFrames + 1] = center
        lobbyFrames[#lobbyFrames + 1] = right
        lobbyFrames[#lobbyFrames + 1] = makeText('AS_HeroHeading', '|cffffcc66HEROES|r', 0.10, 0.42, 0.12, 0.025, 1.25)
        lobbyFrames[#lobbyFrames + 1] = makeText('AS_DetailHeading', '|cffffcc66CHOSEN HERO|r', 0.37, 0.42, 0.14, 0.025, 1.25)
        lobbyFrames[#lobbyFrames + 1] = makeText('AS_ZoneHeading', '|cffffcc66ZONE|r', 0.66, 0.42, 0.08, 0.025, 1.25)

        local factions = {
            {name = 'Alliance', label = 'Alliance', x = 0.038, y = 0.378},
            {name = 'Horde', label = 'Horde', x = 0.117, y = 0.378},
            {name = 'Undead', label = 'Undead', x = 0.196, y = 0.378},
            {name = 'Night Elf', label = 'Night Elf', x = 0.075, y = 0.345},
            {name = 'Tavern', label = 'Tavern', x = 0.157, y = 0.345}
        }
        for index, entry in ipairs(factions) do
            local factionName = entry.name
            local button = makeButton('AS_Faction' .. index, entry.label, entry.x, entry.y, 0.072, 0.026, gameUI, function()
                selectedFaction = factionName
                selectedHero = HERO_GROUPS[factionName][1]
                updateHeroSelection()
            end)
            lobbyFrames[#lobbyFrames + 1] = button
        end

        for index = 1, 9 do
            local heroIndex = index
            local column = math.floor((index - 1) / 5)
            local row = (index - 1) % 5
            local x = 0.039 + column * 0.112
            local y = 0.307 - row * 0.038
            local button = makeButton('AS_Hero' .. index, '', x, y, 0.105, 0.032, gameUI, function()
                local heroChoice = HERO_GROUPS[selectedFaction][heroIndex]
                if heroChoice then
                    selectedHero = heroChoice
                    updateHeroSelection()
                end
            end)
            heroListButtons[index] = button
            lobbyFrames[#lobbyFrames + 1] = button
        end

        lobbyHeroIcon = BlzCreateFrameByType('BACKDROP', 'AS_HeroIcon', gameUI, '', 0)
        BlzFrameSetAbsPoint(lobbyHeroIcon, FRAMEPOINT_BOTTOMLEFT, 0.315, 0.265)
        BlzFrameSetSize(lobbyHeroIcon, 0.09, 0.09)
        lobbyFrames[#lobbyFrames + 1] = lobbyHeroIcon
        lobbyHeroName = makeText('AS_SelectedHero', '', 0.42, 0.325, 0.15, 0.035, 1.4)
        lobbyHeroDetails = makeText('AS_HeroDetails', '', 0.42, 0.24, 0.15, 0.07, 1.0)
        lobbyFrames[#lobbyFrames + 1] = lobbyHeroName
        lobbyFrames[#lobbyFrames + 1] = lobbyHeroDetails

        lobbyZoneDetails = makeText('AS_ZoneDetails', '|cffffcc66ASHENVALE|r\nThe Long Night\nSurvive the monster waves.',
            0.622, 0.31, 0.14, 0.07, 1.0)
        lobbyFrames[#lobbyFrames + 1] = lobbyZoneDetails
        local lockedZones = makeText('AS_LockedZones', '|cff999999Lordaeron - locked\nDurotar - locked\nNorthrend - locked|r',
            0.622, 0.20, 0.14, 0.08, 0.95)
        lobbyFrames[#lobbyFrames + 1] = lockedZones

        local enter = makeButton('AS_Enter', '|cffffcc66ENTER ASHENVALE|r', 0.315, 0.045, 0.25, 0.052, gameUI, function()
            setFramesVisible(lobbyFrames, false)
            setFramesVisible(hudFrames, true)
            BlzHideOriginFrames(false)
            startRun()
        end)
        lobbyFrames[#lobbyFrames + 1] = enter
        local footer = makeText('AS_Footer', '|cffccbb99WASD move  |  abilities autocast after learning  |  survive 10 minutes|r',
            0.20, 0.015, 0.40, 0.022, 0.9)
        lobbyFrames[#lobbyFrames + 1] = footer

        updateHeroSelection()
        createRunUI()
        setFramesVisible(hudFrames, false)
    end

    local function say(message)
        DisplayTimedTextToPlayer(PLAYER, 0.0, 0.0, 4.0, message)
    end

    local function pauseBattle(pause)
        if hero ~= nil then
            PauseUnit(hero, pause)
        end
        for unit in pairs(enemies) do
            if GetWidgetLife(unit) > 0.405 then
                PauseUnit(unit, pause)
            end
        end
    end

    local function endRun(victory)
        if ended then
            return
        end
        ended = true
        pauseBattle(true)
        if victory then
            say('|cff00ff00Ashenvale holds! You survived the night.|r')
        else
            say('|cffff4040You have fallen in Ashenvale.|r')
        end
        say('Final level: ' .. I2S(level) .. '   Kills: ' .. I2S(totalKills))
        if runMessage ~= nil then
            BlzFrameSetText(runMessage, victory and '|cff00ff00VICTORY - ASHENVALE HOLDS|r'
                or '|cffff4040DEFEAT - YOU HAVE FALLEN|r')
        end
    end

    local function offerUpgrade()
        if ended or upgradesQueued <= 0 then
            return
        end
        upgradePending = true
        pauseBattle(true)
        if upgradePanel ~= nil then
            BlzFrameSetVisible(upgradePanel, true)
            BlzFrameSetVisible(upgradeTitleFrame, true)
            for _, button in ipairs(upgradeButtons) do
                BlzFrameSetVisible(button, true)
            end
        end
        if runMessage ~= nil then
            BlzFrameSetText(runMessage, '|cffffff00LEVEL ' .. I2S(level) .. ' - CHOOSE AN UPGRADE|r')
        end
    end

    local function awardExperience(amount)
        experience = experience + amount
        while experience >= experienceToNext do
            experience = experience - experienceToNext
            level = level + 1
            experienceToNext = 5 + (level - 1) * 3
            upgradesQueued = upgradesQueued + 1
        end
        if not upgradePending and upgradesQueued > 0 then
            offerUpgrade()
        end
    end

    applyUpgrade = function(choice)
        if ended or not upgradePending then
            return
        end
        if choice == 1 or choice == '1' then
            heroDamage = heroDamage + 12.0
        elseif choice == 2 or choice == '2' then
            heroRange = heroRange + 100.0
        elseif choice == 3 or choice == '3' then
            heroSpeed = heroSpeed + 30.0
            SetUnitMoveSpeed(hero, heroSpeed)
        elseif choice == 4 or choice == '4' then
            local currentHealth = GetWidgetLife(hero)
            BlzSetUnitMaxHP(hero, BlzGetUnitMaxHP(hero) + 100)
            SetWidgetLife(hero, currentHealth + 100.0)
        else
            return
        end
        BlzFrameSetVisible(upgradePanel, false)
        BlzFrameSetVisible(upgradeTitleFrame, false)
        for _, button in ipairs(upgradeButtons) do
            BlzFrameSetVisible(button, false)
        end
        upgradesQueued = upgradesQueued - 1
        upgradePending = false
        if upgradesQueued > 0 then
            offerUpgrade()
        else
            pauseBattle(false)
            if not ended then
                -- Reissue the current movement direction if a key was held
                -- while the level-up prompt had paused the hero.
                local dx = (keysDown.d and 1 or 0) - (keysDown.a and 1 or 0)
                local dy = (keysDown.w and 1 or 0) - (keysDown.s and 1 or 0)
                if dx ~= 0 or dy ~= 0 then
                    local length = math.sqrt(dx * dx + dy * dy)
                    local tx = math.max(minX, math.min(maxX, GetUnitX(hero) + dx / length * 3000.0))
                    local ty = math.max(minY, math.min(maxY, GetUnitY(hero) + dy / length * 3000.0))
                    IssuePointOrder(hero, 'move', tx, ty)
                end
            end
            if runMessage ~= nil then
                BlzFrameSetText(runMessage, '')
            end
        end
        updateRunHUD()
    end

    local function chooseUpgrade()
        if GetTriggerPlayer() ~= PLAYER then
            return
        end
        local choice = tonumber(GetEventPlayerChatString())
        if choice ~= nil then
            applyUpgrade(choice)
        end
    end

    local function makeUpgradeTrigger()
        local trigger = CreateTrigger()
        TriggerRegisterPlayerChatEvent(trigger, PLAYER, '1', true)
        TriggerRegisterPlayerChatEvent(trigger, PLAYER, '2', true)
        TriggerRegisterPlayerChatEvent(trigger, PLAYER, '3', true)
        TriggerRegisterPlayerChatEvent(trigger, PLAYER, '4', true)
        TriggerAddAction(trigger, chooseUpgrade)
    end

    updateRunHUD = function()
        if hudClock == nil or hero == nil then
            return
        end
        local minutes = math.floor(elapsed / 60.0)
        local seconds = math.floor(elapsed % 60.0)
        local bossTime = BOSS_TIMES[nextBoss] or RUN_LENGTH
        local bossRemaining = math.max(0, math.floor(bossTime - elapsed))
        BlzFrameSetText(hudClock,
            string.format('%02d:%02d   |   Next boss %02d:%02d', minutes, seconds,
                math.floor(bossRemaining / 60), bossRemaining % 60))
        BlzFrameSetText(hudStats,
            selectedHero.name .. '  |  Level ' .. I2S(level) .. '  |  Kills ' .. I2S(totalKills))
        BlzFrameSetText(hudXpText,
            'Health ' .. I2S(R2I(GetWidgetLife(hero))) .. '/' .. I2S(BlzGetUnitMaxHP(hero)) ..
            '     XP ' .. I2S(experience) .. '/' .. I2S(experienceToNext))
        BlzFrameSetSize(hudHealthFill,
            0.19 * math.max(0.0, math.min(1.0, GetWidgetLife(hero) / BlzGetUnitMaxHP(hero))), 0.012)
        BlzFrameSetSize(hudXpFill,
            0.30 * math.max(0.0, math.min(1.0, experience / experienceToNext)), 0.012)
    end

    createRunUI = function()
        local top = makePanel('AS_HUDTop', 0.255, 0.535, 0.29, 0.047, 220)
        local bottom = makePanel('AS_HUDBottom', 0.025, 0.025, 0.22, 0.055, 220)
        local xpPanel = makePanel('AS_HUDXPPanel', 0.285, 0.025, 0.32, 0.055, 220)
        hudFrames[#hudFrames + 1] = top
        hudFrames[#hudFrames + 1] = bottom
        hudFrames[#hudFrames + 1] = xpPanel
        hudClock = makeText('AS_HUDClock', '00:00', 0.275, 0.55, 0.25, 0.025, 1.2)
        hudStats = makeText('AS_HUDStats', '', 0.045, 0.07, 0.19, 0.022, 0.9)
        hudXpText = makeText('AS_HUDXPText', '', 0.30, 0.07, 0.29, 0.022, 0.9)
        hudFrames[#hudFrames + 1] = hudClock
        hudFrames[#hudFrames + 1] = hudStats
        hudFrames[#hudFrames + 1] = hudXpText

        local healthBack = makePanel('AS_HUDHealthBack', 0.04, 0.045, 0.19, 0.012, 230)
        hudHealthFill = makePanel('AS_HUDHealthFill', 0.04, 0.045, 0.19, 0.012, 255)
        BlzFrameSetVertexColor(hudHealthFill, BlzConvertColor(255, 150, 30, 25))
        local xpBack = makePanel('AS_HUDXPBack', 0.30, 0.045, 0.29, 0.012, 230)
        hudXpFill = makePanel('AS_HUDXPFill', 0.30, 0.045, 0.01, 0.012, 255)
        BlzFrameSetVertexColor(hudXpFill, BlzConvertColor(255, 225, 175, 40))
        hudFrames[#hudFrames + 1] = healthBack
        hudFrames[#hudFrames + 1] = hudHealthFill
        hudFrames[#hudFrames + 1] = xpBack
        hudFrames[#hudFrames + 1] = hudXpFill

        runMessage = makeText('AS_RunMessage', '', 0.30, 0.48, 0.40, 0.03, 1.0)
        hudFrames[#hudFrames + 1] = runMessage

        upgradePanel = makePanel('AS_UpgradePanel', 0.12, 0.12, 0.56, 0.38, 248)
        local upgradeTitle = makeText('AS_UpgradeTitle', '|cffffcc66LEVEL UP - CHOOSE ONE|r',
            0.245, 0.455, 0.31, 0.035, 1.5)
        upgradeTitleFrame = upgradeTitle
        hudFrames[#hudFrames + 1] = upgradePanel
        hudFrames[#hudFrames + 1] = upgradeTitle
        local upgradeNames = {
            '|cffffcc66ARCANE POWER - +12 DAMAGE|r',
            '|cffffcc66LONGER REACH - +100|r',
            '|cffffcc66SWIFTNESS - +30 SPEED|r',
            '|cffffcc66VITALITY - +100 HEALTH|r'
        }
        for index = 1, 4 do
            local upgradeIndex = index
            local button = makeButton('AS_Upgrade' .. index, upgradeNames[index],
                0.135 + (index - 1) * 0.135, 0.24, 0.125, 0.14, gameUI, function()
                    if applyUpgrade then
                        applyUpgrade(upgradeIndex)
                    end
                end)
            upgradeButtons[index] = button
            hudFrames[#hudFrames + 1] = button
        end
        BlzFrameSetVisible(upgradePanel, false)
        BlzFrameSetVisible(upgradeTitleFrame, false)
        for _, button in ipairs(upgradeButtons) do
            BlzFrameSetVisible(button, false)
        end
        updateRunHUD()
    end

    local function issueMovement()
        if hero == nil or upgradePending or ended then
            return
        end
        local dx = (keysDown.d and 1 or 0) - (keysDown.a and 1 or 0)
        local dy = (keysDown.w and 1 or 0) - (keysDown.s and 1 or 0)
        if dx == 0 and dy == 0 then
            IssueImmediateOrder(hero, 'stop')
            return
        end
        local length = math.sqrt(dx * dx + dy * dy)
        local tx = math.max(minX, math.min(maxX, GetUnitX(hero) + dx / length * 3000.0))
        local ty = math.max(minY, math.min(maxY, GetUnitY(hero) + dy / length * 3000.0))
        IssuePointOrder(hero, 'move', tx, ty)
    end

    local function makeMovementTrigger()
        local trigger = CreateTrigger()
        local keys = {
            {key = OSKEY_W, name = 'w'},
            {key = OSKEY_A, name = 'a'},
            {key = OSKEY_S, name = 's'},
            {key = OSKEY_D, name = 'd'}
        }
        for _, entry in ipairs(keys) do
            BlzTriggerRegisterPlayerKeyEvent(trigger, PLAYER, entry.key, 0, true)
            BlzTriggerRegisterPlayerKeyEvent(trigger, PLAYER, entry.key, 0, false)
        end
        TriggerAddAction(trigger, function()
            local pressedKey = BlzGetTriggerPlayerKey()
            local isDown = BlzGetTriggerPlayerIsKeyDown()
            for _, entry in ipairs(keys) do
                if pressedKey == entry.key then
                    keysDown[entry.name] = isDown
                    break
                end
            end
            issueMovement()
        end)
    end

    local function spawnEnemy(isBoss, nearHero)
        local angle = GetRandomReal(0.0, 6.28318530718)
        local radius = nearHero and GetRandomReal(450.0, 650.0) or GetRandomReal(850.0, 1050.0)
        local x = math.max(minX, math.min(maxX, centerX + math.cos(angle) * radius))
        local y = math.max(minY, math.min(maxY, centerY + math.sin(angle) * radius))
        local unit = CreateUnit(HOSTILE, ENEMY_TYPE, x, y, GetRandomReal(0.0, 360.0))
        local minutes = math.floor(elapsed / 60.0)
        local health = 360.0 + minutes * 90.0

        if isBoss then
            health = health * 12.0
            SetUnitScale(unit, 1.65, 1.65, 1.65)
            SetUnitVertexColor(unit, 255, 80, 60, 255)
        else
            SetUnitVertexColor(unit, 180, 95, 95, 255)
        end

        BlzSetUnitMaxHP(unit, R2I(health))
        SetWidgetLife(unit, health)
        BlzSetUnitBaseDamage(unit, 12 + minutes * 3, 0)
        IssueTargetOrder(unit, 'attack', hero)
        enemies[unit] = {boss = isBoss}

        if isBoss then
            say('|cffff4040A powerful foe has entered the clearing!|r')
        end
    end

    local function getNearestEnemy()
        local closest = nil
        local closestDistance = heroRange
        local hx = GetUnitX(hero)
        local hy = GetUnitY(hero)
        for unit in pairs(enemies) do
            if GetWidgetLife(unit) > 0.405 then
                local dx = GetUnitX(unit) - hx
                local dy = GetUnitY(unit) - hy
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance < closestDistance then
                    closest = unit
                    closestDistance = distance
                end
            end
        end
        return closest
    end

    local function castBlizzard()
        local centerUnit = nil
        local bestCount = 0
        local maxCastDistance = 1100.0
        local hx = GetUnitX(hero)
        local hy = GetUnitY(hero)

        -- Place Blizzard over the densest nearby pack.
        for candidate in pairs(enemies) do
            if GetWidgetLife(candidate) > 0.405 then
                local dx = GetUnitX(candidate) - hx
                local dy = GetUnitY(candidate) - hy
                if dx * dx + dy * dy <= maxCastDistance * maxCastDistance then
                    local count = 0
                    for other in pairs(enemies) do
                        if GetWidgetLife(other) > 0.405 then
                            local ox = GetUnitX(other) - GetUnitX(candidate)
                            local oy = GetUnitY(other) - GetUnitY(candidate)
                            if ox * ox + oy * oy <= BLIZZARD_RADIUS * BLIZZARD_RADIUS then
                                count = count + 1
                            end
                        end
                    end
                    if count > bestCount then
                        bestCount = count
                        centerUnit = candidate
                    end
                end
            end
        end

        if centerUnit == nil then
            return false
        end

        local x = GetUnitX(centerUnit)
        local y = GetUnitY(centerUnit)
        local effect = AddSpecialEffect('Abilities\\Spells\\Human\\Blizzard\\BlizzardTarget.mdl', x, y)
        BlzSetSpecialEffectScale(effect, 1.5)
        TimerStart(CreateTimer(), 2.5, false, function()
            DestroyEffect(effect)
            DestroyTimer(GetExpiredTimer())
        end)

        for unit in pairs(enemies) do
            if GetWidgetLife(unit) > 0.405 then
                local dx = GetUnitX(unit) - x
                local dy = GetUnitY(unit) - y
                if dx * dx + dy * dy <= BLIZZARD_RADIUS * BLIZZARD_RADIUS then
                    UnitDamageTarget(hero, unit, 125.0 + math.floor(elapsed / 60.0) * 18.0,
                        true, false, ATTACK_TYPE_MAGIC, DAMAGE_TYPE_COLD, WEAPON_TYPE_WHOKNOWS)
                end
            end
        end
        say('|cff80c0ffBlizzard!|r')
        return true
    end

    local function summonWaterElemental()
        local rank = GetUnitAbilityLevel(hero, FourCC(selectedHero.elemental))
        local unitType = FourCC('hwat')
        if rank >= 3 then
            unitType = FourCC('hwt3')
        elseif rank == 2 then
            unitType = FourCC('hwt2')
        end

        local angle = GetRandomReal(0.0, 6.28318530718)
        local x = GetUnitX(hero) + math.cos(angle) * 140.0
        local y = GetUnitY(hero) + math.sin(angle) * 140.0
        waterElemental = CreateUnit(PLAYER, unitType, x, y, 270.0)
        UnitApplyTimedLife(waterElemental, FourCC('BTLF'), 45.0)

        local target = getNearestEnemy()
        if target ~= nil then
            IssueTargetOrder(waterElemental, 'attack', target)
        else
            IssuePointOrder(waterElemental, 'attack', GetUnitX(hero), GetUnitY(hero))
        end
        say('|cff80c0ffWater Elemental summoned!|r')
    end

    local function fireArcaneBolt(target)
        local startX = GetUnitX(hero)
        local startY = GetUnitY(hero)
        local startZ = BlzGetUnitZ(hero) + 65.0
        local distanceX = GetUnitX(target) - startX
        local distanceY = GetUnitY(target) - startY
        local distance = math.sqrt(distanceX * distanceX + distanceY * distanceY)
        local flightTime = math.max(0.16, distance / 2200.0)
        local effect = AddSpecialEffect(
            'Abilities\\Weapons\\ArcaneTowerMissile\\ArcaneTowerMissile.mdl', startX, startY)
        BlzSetSpecialEffectPosition(effect, startX, startY, startZ)
        BlzSetSpecialEffectScale(effect, 1.35)

        local timer = CreateTimer()
        local flightElapsed = 0.0
        TimerStart(timer, 0.03, true, function()
            if GetWidgetLife(target) <= 0.405 or ended then
                DestroyEffect(effect)
                DestroyTimer(GetExpiredTimer())
                return
            end

            flightElapsed = flightElapsed + 0.03
            local progress = math.min(1.0, flightElapsed / flightTime)
            local targetX = GetUnitX(target)
            local targetY = GetUnitY(target)
            local targetZ = BlzGetUnitZ(target) + 45.0
            BlzSetSpecialEffectPosition(effect,
                startX + (targetX - startX) * progress,
                startY + (targetY - startY) * progress,
                startZ + (targetZ - startZ) * progress)

            if progress >= 1.0 then
                DestroyEffect(effect)
                UnitDamageTarget(hero, target, heroDamage, true, false,
                    ATTACK_TYPE_MAGIC, DAMAGE_TYPE_MAGIC, WEAPON_TYPE_WHOKNOWS)
                local impact = AddSpecialEffectTarget(
                    'Abilities\\Spells\\NightElf\\ManaBurn\\ManaBurnTarget.mdl', target, 'origin')
                local cleanup = CreateTimer()
                TimerStart(cleanup, 0.55, false, function()
                    DestroyEffect(impact)
                    DestroyTimer(GetExpiredTimer())
                end)
                DestroyTimer(GetExpiredTimer())
            end
        end)
    end

    local function tick()
        if ended then
            return
        end

        if GetWidgetLife(hero) <= 0.405 then
            endRun(false)
            return
        end

        if upgradePending then
            return
        end

        elapsed = elapsed + STEP
        spawnClock = spawnClock + STEP
        attackClock = attackClock + STEP
        updateRunHUD()

        if nextBoss <= #BOSS_TIMES and elapsed >= BOSS_TIMES[nextBoss] then
            spawnEnemy(true)
            nextBoss = nextBoss + 1
        end

        local activeCount = 0
        for unit, info in pairs(enemies) do
            if GetWidgetLife(unit) <= 0.405 then
                local reward = info.boss and 15 or 1
                enemies[unit] = nil
                RemoveUnit(unit)
                totalKills = totalKills + 1
                awardExperience(reward)
            else
                activeCount = activeCount + 1
            end
        end

        if upgradePending then
            return
        end

        local minute = math.floor(elapsed / 60.0)
        local spawnInterval = math.max(0.55, 2.2 - minute * 0.18)
        if spawnClock >= spawnInterval and activeCount < MAX_ENEMIES then
            spawnClock = 0.0
            local count = math.min(3, 1 + math.floor(elapsed / 180.0))
            for _ = 1, count do
                if activeCount < MAX_ENEMIES then
                    spawnEnemy(false)
                    activeCount = activeCount + 1
                end
            end
        end

        if attackClock >= HERO_ATTACK_INTERVAL then
            attackClock = 0.0
            local target = getNearestEnemy()
            if target ~= nil then
                fireArcaneBolt(target)
            end
        end

        local blizzardLearned = selectedHero.blizzard ~= nil
            and GetUnitAbilityLevel(hero, FourCC(selectedHero.blizzard)) > 0
        if blizzardLearned then
            if not blizzardWasLearned then
                blizzardWasLearned = true
                blizzardClock = 0.0
                say('|cff80c0ffBlizzard learned: it will autocast on cooldown.|r')
            else
                blizzardClock = blizzardClock + STEP
            end
            if blizzardClock >= BLIZZARD_COOLDOWN and castBlizzard() then
                blizzardClock = 0.0
            end
        end

        local elementalLearned = selectedHero.elemental ~= nil
            and GetUnitAbilityLevel(hero, FourCC(selectedHero.elemental)) > 0
        if elementalLearned then
            if not elementalWasLearned then
                elementalWasLearned = true
                elementalClock = 0.0
                say('|cff80c0ffWater Elemental learned: it will autocast on cooldown.|r')
            else
                elementalClock = elementalClock + STEP
            end
            if elementalClock >= WATER_ELEMENTAL_COOLDOWN
                and (waterElemental == nil or GetWidgetLife(waterElemental) <= 0.405) then
                summonWaterElemental()
                elementalClock = 0.0
            end
        end

        if elapsed >= RUN_LENGTH then
            endRun(true)
        end
    end

    startRun = function()
        heroDamage = selectedHero.damage
        hero = CreateUnit(PLAYER, FourCC(selectedHero.id), centerX, centerY, 270.0)
        SetUnitMoveSpeed(hero, heroSpeed)
        SetCameraPosition(centerX, centerY)
        SelectUnitForPlayerSingle(hero, PLAYER)

        makeUpgradeTrigger()
        makeMovementTrigger()
        -- Give the opening attack and first Blizzard targets immediately.
        for _ = 1, 5 do
            spawnEnemy(false, true)
        end
        TimerStart(CreateTimer(), STEP, true, tick)
        say('|cff80c0ffASHENVALE: THE LONG NIGHT|r')
        say('Move with WASD. Arcane Pulse fires automatically every 0.8 seconds.')
        say('Learn a hero ability with the skill button to unlock its automatic cast.')
        say('Survive 10 minutes. Choose upgrades using the cards shown on screen.')
    end

    showLobby()
end
end
