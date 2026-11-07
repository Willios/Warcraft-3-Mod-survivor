-- Plays the map script through the mock: lobby, tabs, runs on every
-- difficulty, level-ups, bosses, victory, defeat, saving and every hero.
math.randomseed(7)

local function upvalue(fn, name)
    for i = 1, 200 do
        local n, v = debug.getupvalue(fn, i)
        if n == nil then return nil end
        if n == name then return v end
    end
end

Survivor_Start()
MOCK.advance(0.1)
local UI = upvalue(Survivor_Start, 'UI')
local G = upvalue(Survivor_Start, 'G')
local function R() return upvalue(G.tick, 'R') end
local S = upvalue(G.startRun, 'S')
local HEROES = upvalue(G.startRun, 'HEROES')
local SPELLS = upvalue(G.learnSpell, 'SPELLS')
local Profile = upvalue(G.endRun, 'Profile')
assert(UI and G and S and HEROES and SPELLS and Profile, 'internals not found')

local realDamage = UnitDamageTarget
function UnitDamageTarget(src, target, amount, ...)
    local result = realDamage(src, target, amount, ...)
    if target.hero and target.owner == Player(0) and not target.alive and not target.reported then
        target.reported = true
        MOCK.heroDeath = string.format('hero killed by %s (%s) for %.0f, max hp %d', tostring(src.name), tostring(src.id), amount, target.maxHp)
    end
    return result
end
local report = {}
local function note(s) report[#report + 1] = s end
local function check(cond, msg) if not cond then error('CHECK FAILED: ' .. msg .. ' REPORT: ' .. table.concat(report, ' | '), 2) end end
local function errors() return #MOCK.printed end

check(MOCK.findText('WARCRAFT SURVIVORS'), 'lobby title visible')
for _, tab in ipairs({'Armory', 'Codex', 'Talents', 'Achievements', 'Rewards', 'Character'}) do
    MOCK.click(tab)
    MOCK.pokeAll()
end
note('lobby tabs ok, errors=' .. errors())

-- Simulate a run: hold a direction, take hits, pick cards as they come.
local function play(seconds, opts)
    opts = opts or {}
    local keys = {OSKEY_1, OSKEY_2, OSKEY_3}
    local hands, elapsed = 0, 0
    while elapsed < seconds do
        MOCK.advance(0.25)
        elapsed = elapsed + 0.25
        local run = R()
        if run == nil or run.ended then break end
        if run.hand then
            hands = hands + 1
            if math.random() < 0.15 and run.rerolls > 0 then MOCK.tap(OSKEY_R) end
            if math.random() < 0.1 and run.banishes > 0 then
                upvalue(G.tryOpenHand, 'Cards').banish(1)
            end
            MOCK.tap(keys[math.random(1, #run.hand.cards)])
        end
        -- Mock enemies have no AI: walk them toward the hero.
        for u in pairs(run.enemies) do
            local dx, dy = run.hx - u.x, run.hy - u.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d > 90 then
                u.x, u.y = u.x + dx / d * 75, u.y + dy / d * 75
            end
        end
        -- Enemies hit the hero now and then.
        if math.random() < 0.3 then
            for u, info in pairs(run.enemies) do
                UnitDamageTarget(u, run.hero, opts.hit or 4, true, false, ATTACK_TYPE_CHAOS, DAMAGE_TYPE_NORMAL, WEAPON_TYPE_WHOKNOWS)
                break
            end
        end
        if opts.immortal then
            run.hero.maxHp = 1e6
            run.hero.life = 1e6
        elseif not opts.mortal and math.floor(elapsed) % 20 == 0 then
            SetWidgetLife(run.hero, BlzGetUnitMaxHP(run.hero))
        end
        -- Help the mock hero finish bosses so the run can end.
        if opts.slayBosses and run.time > (opts.slayAfter or 0) then
            for u, info in pairs(run.enemies) do
                if info.boss then
                    UnitDamageTarget(run.hero, u, 1e7, false, false, ATTACK_TYPE_CHAOS, DAMAGE_TYPE_NORMAL, WEAPON_TYPE_WHOKNOWS)
                end
            end
        end
        -- Kite in a square: a right-click 600 away every three seconds.
        if elapsed % 3 == 0 then
            local square = {{0, 600}, {600, 0}, {0, -600}, {-600, 0}}
            local side = square[math.floor(elapsed / 3) % 4 + 1]
            MOCK.order(run.hero, run.hx + side[1], run.hy + side[2])
        end
    end
    return hands
end

-- 0. Options: Escape opens them over the lobby, and Space does not start a run behind them.
MOCK.tap(OSKEY_ESCAPE)
check(MOCK.findText('Esc closes this menu'), 'escape opens options in the lobby')
check(not MOCK.findText('Restart Run'), 'no restart in the lobby')
MOCK.tap(OSKEY_SPACE)
check(R() == nil, 'space is ignored while options are open')
MOCK.tap(OSKEY_ESCAPE)
check(not MOCK.findText('Esc closes this menu'), 'escape closes options')

-- 1. Normal run to victory.
MOCK.tap(OSKEY_SPACE)
check(R() ~= nil, 'space starts a run')
local run = R()
-- Options during a run pause it; a volume step is saved; Resume unpauses.
local spellsVolume, musicVolume = MOCK.groupVolume[SOUND_VOLUMEGROUP_SPELLS], MOCK.musicVolume
check(spellsVolume > 0 and musicVolume > 0, 'a running game has sound and music')
MOCK.tap(OSKEY_ESCAPE)
check(run.paused and MOCK.findText('Restart Run'), 'options pause the run')
check(MOCK.groupVolume[SOUND_VOLUMEGROUP_SPELLS] == 0 and MOCK.groupVolume[SOUND_VOLUMEGROUP_UNITSOUNDS] == 0
    and MOCK.musicVolume == musicVolume, 'a pause keeps only the music')
-- The game menu stacks its pages: Audio opens in its place, Escape comes back.
MOCK.click('Audio')
check(not MOCK.findText('Restart Run') and MOCK.findText('Esc returns to the menu'), 'audio page replaces the menu')
MOCK.click('-')
check(Profile.data.opts.master == 50, 'master volume stepped to 50, got ' .. tostring(Profile.data.opts.master))
Profile.data.opts.master = nil
MOCK.tap(OSKEY_ESCAPE)
check(run.paused and MOCK.findText('Restart Run'), 'escape returns from a page to the menu')
local soundsBefore = MOCK.sounds or 0
MOCK.click('Resume')
check(not run.paused, 'resume unpauses the run')
check(MOCK.sounds == soundsBefore + 1 and MOCK.lastSound.label == 'GlueScreenClick' and not MOCK.lastSound.is3D,
    'a button click plays the interface click')
check(MOCK.groupVolume[SOUND_VOLUMEGROUP_SPELLS] == spellsVolume and MOCK.musicVolume == musicVolume, 'resuming brings the sound back')
Profile.data.opts.music = nil
-- Mouse movement (the default): WASD does nothing, a right-click walks to the clicked point.
local x0, y0 = GetUnitX(run.hero), GetUnitY(run.hero)
MOCK.key(OSKEY_W, true)
MOCK.advance(0.5)
MOCK.key(OSKEY_W, false)
check(GetUnitY(run.hero) == y0 and GetUnitX(run.hero) == x0, 'W does not move the hero')
MOCK.order(run.hero, x0 + 200, y0)
MOCK.advance(0.4)
check(GetUnitX(run.hero) > x0 + 50, 'right-click walks the hero there')
check(GetUnitX(run.hero) <= x0 + 200.5, 'the hero stops at the click')
MOCK.advance(1.0)
check(math.abs(GetUnitX(run.hero) - (x0 + 200)) < 1, 'the hero arrives at the click')
-- Keyboard movement: W walks north, right-clicks do nothing; then W rebound to I.
MOCK.tap(OSKEY_ESCAPE)
MOCK.click('Keybinds')
MOCK.click('Keyboard')
check(Profile.data.opts.wasd == 1, 'keyboard movement on')
MOCK.tap(OSKEY_ESCAPE)
MOCK.click('Resume')
x0, y0 = GetUnitX(run.hero), GetUnitY(run.hero)
MOCK.order(run.hero, x0 + 300, y0)
MOCK.advance(0.5)
check(GetUnitX(run.hero) == x0 and GetUnitY(run.hero) == y0, 'right-click does not move with keyboard movement')
MOCK.key(OSKEY_W, true)
MOCK.advance(0.5)
MOCK.key(OSKEY_W, false)
check(GetUnitY(run.hero) > y0 + 50 and GetUnitX(run.hero) == x0, 'W walks the hero north')
MOCK.tap(OSKEY_ESCAPE)
MOCK.click('Keybinds')
MOCK.click('W')
check(MOCK.findText('Press a key'), 'a key waits for the new one')
MOCK.tap(OSKEY_I)
check(Profile.data.binds.up == 73, 'move up rebound to I, got ' .. tostring(Profile.data.binds.up))
MOCK.tap(OSKEY_ESCAPE)
MOCK.click('Resume')
y0 = GetUnitY(run.hero)
MOCK.key(OSKEY_W, true)
MOCK.advance(0.3)
MOCK.key(OSKEY_W, false)
check(GetUnitY(run.hero) == y0, 'W no longer walks')
MOCK.key(OSKEY_I, true)
MOCK.advance(0.3)
MOCK.key(OSKEY_I, false)
check(GetUnitY(run.hero) > y0 + 30, 'I walks north')
-- Binding a key another action has swaps them; Reset restores the defaults.
MOCK.tap(OSKEY_ESCAPE)
MOCK.click('Keybinds')
MOCK.click('I')
MOCK.tap(OSKEY_R)
check(Profile.data.binds.up == 82 and Profile.data.binds.reroll == 73, 'R swapped with reroll')
MOCK.click('Reset to Defaults')
check(next(Profile.data.binds) == nil, 'defaults restored')
MOCK.click('Mouse')
check(Profile.data.opts.wasd == 0, 'mouse movement back on')
MOCK.tap(OSKEY_ESCAPE)
MOCK.click('Resume')
check(not run.paused, 'run resumes after the keybinds')
check(MOCK.music and MOCK.music:find('NightElf', 1, true), 'zone music plays')
note('options ok')
-- The stats panel shows under the hero frame; C hides and shows it.
MOCK.advance(0.2)
check(MOCK.findText('Critical chance') and MOCK.findText('175'), 'stats panel lists critical strike')
MOCK.tap(OSKEY_C)
check(not MOCK.findText('Critical chance') and Profile.data.opts.stats == 0, 'C hides the stats')
MOCK.tap(OSKEY_C)
check(MOCK.findText('Critical chance'), 'C shows the stats again')
-- Hovering a spell slot shows what the spell does.
local hud = upvalue(G.startRun, 'Hud')
UI.safe(function() hud.spellTip(1) end)
check(MOCK.findText(run.spells[1].def.name .. '   rank 1'), 'spell slot tooltip')
UI.safe(function() hud.hideTip() end)
check(not MOCK.findText(run.spells[1].def.name .. '   rank 1'), 'tooltip hides')
-- Every living boss keeps its own health bar, oldest on top; the banner and
-- the toast move below the rows, and bosses beyond the rows only count.
do
    local names = {run.zone.bosses[1].name, run.zone.bosses[2].name}
    local function refresh()
        MOCK.advance(0.1)
        if run.hand then MOCK.tap(OSKEY_1) end
        UI.safe(function() hud.update() end)
    end
    local function row(i)
        return hud.bossRows[i].name.visible and hud.bossRows[i].name.text or nil
    end
    G.spawnBoss(run.zone.bosses[1], false)
    local first = run.bossUnits[1]
    G.spawnBoss(run.zone.bosses[2], false)
    refresh()
    check(row(1) and row(1):find(names[1], 1, true) and row(2) and row(2):find(names[2], 1, true) and not row(3),
        'two bosses, two health bars')
    check(hud.alertRows == 1, 'the toast moves below two bars')
    UnitDamageTarget(run.hero, first, 1e7, false, false, ATTACK_TYPE_CHAOS, DAMAGE_TYPE_NORMAL, WEAPON_TYPE_WHOKNOWS)
    refresh()
    check(row(1) and row(1):find(names[2], 1, true) and not row(2), 'the second boss moves up when the first dies')
    check(hud.alertRows == 0, 'the toast moves back')
    for _ = 1, 5 do
        G.spawnBoss(run.zone.bosses[1], false)
    end
    refresh()
    check(row(5) and hud.bossMore.text:find('+1', 1, true), 'six bosses: five bars and +1')
    for _, u in ipairs({table.unpack(run.bossUnits)}) do
        UnitDamageTarget(run.hero, u, 1e7, false, false, ATTACK_TYPE_CHAOS, DAMAGE_TYPE_NORMAL, WEAPON_TYPE_WHOKNOWS)
    end
    refresh()
    check(#run.bossUnits == 0 and not row(1) and hud.bossMore.text == '', 'no boss, no bar')
    note('boss bars stack and follow deaths')
end
note('run started: ' .. run.def.name .. ' in ' .. run.zone.name .. ' (' .. run.diff.name .. ')')
local hands = play(700, {slayBosses = true, slayAfter = 0})
run = R()
note(string.format('normal run: time %.0f level %d kills %d bosses %d hands %d spells %d ended=%s victory=%s loot=%d gold=%.0f chests=%d',
    run.time, run.level, run.kills, run.bosses, hands, #run.spells, tostring(run.ended), tostring(run.victory), #run.loot, run.gold, run.worldChestsOpened))
if not (run.ended and run.victory) then return table.concat(report, ' | ') .. ' | FINAL BOSS SPAWNED=' .. tostring(run.finalSpawned) .. ' hero life=' .. GetWidgetLife(run.hero) .. ' enemies=' .. run.enemyCount .. ' paused=' .. tostring(run.paused) .. ' hand=' .. tostring(run.hand ~= nil) end
check(run.ended and run.victory, 'normal run ends in victory')
check(MOCK.findText('VICTORY'), 'victory screen')
MOCK.pokeAll()
-- Endless mode: the won run goes on, stronger every minute, bosses on a timer;
-- its end adds only what came after the victory.
local runsBefore, killsBanked, goldBefore = Profile.data.runs, run.kills, Profile.data.gold
local bossesBefore = run.bosses
MOCK.click('Endless Mode')
check(R() == run and not run.ended and run.endless, 'endless mode resumes the run')
play(200, {slayBosses = true, immortal = true})
check(not run.ended, 'endless run still going')
check(run.bosses > bossesBefore, 'endless bosses come back, slain ' .. (run.bosses - bossesBefore))
local hpScale = G.endlessScale()
check(hpScale > 1.4, 'endless health grows, x' .. hpScale)
local endlessGold = run.gold - run.banked.gold
run.hero.invulnerable = false
run.invulnUntil = 0
UnitDamageTarget(next(run.enemies), run.hero, 1e8, true, false, ATTACK_TYPE_CHAOS, DAMAGE_TYPE_NORMAL, WEAPON_TYPE_WHOKNOWS)
MOCK.advance(0.1)
check(run.ended and run.victory, 'endless ends, still a victory')
check(MOCK.findText('ENDLESS'), 'endless end screen')
check(not MOCK.findText('Endless Mode'), 'no endless button after endless')
check(Profile.data.runs == runsBefore, 'endless is the same run')
check(Profile.data.endless['1'] and Profile.data.endless['1'] >= 790, 'endless time saved, got ' .. tostring(Profile.data.endless['1']))
check(math.abs(Profile.data.gold - goldBefore - math.floor(endlessGold * run.diff.reward + 0.5)) <= 1, 'endless gold banked once')
note(string.format('endless: %.0f s, health x%.2f, +%d kills, +%d bosses', run.time - run.endlessAt, hpScale,
    run.kills - killsBanked, run.bosses - bossesBefore))
MOCK.click('Return to Camp')
check(R() == nil and S.screen == 'lobby', 'back in lobby')
note('profile after win: zoneDiff1=' .. tostring(Profile.data.zoneDiff['1']) .. ' unlocked=' .. Profile.data.unlocked
    .. ' gold=' .. Profile.data.gold .. ' gear=' .. (function() local n = 0 for _ in pairs(Profile.data.gear) do n = n + 1 end return n end)())

-- 2. Save round trip.
local saved = Profile.encode(Profile.data)
Profile.load()
check(Profile.encode(Profile.data) == saved, 'save/load round trip')
note('save round trip ok (' .. #saved .. ' chars)')

-- 3. Heroic is open now; pick it in the difficulty window, then unlock Mythic+ and push a +12 key.
MOCK.click('rewards x1.00')
check(MOCK.findText('Win Ashenvale on Heroic to open it.'), 'difficulty window lists the locked ones')
MOCK.click('Mythic')
check(S.difficulty == 1, 'a locked difficulty cannot be picked')
MOCK.click('Heroic')
check(S.difficulty == 2, 'picked Heroic, got ' .. S.difficulty)
MOCK.click('Done')
check(not MOCK.findText('Win Ashenvale on Heroic to open it.'), 'Done closes the difficulty window')
check(MOCK.findText('Win on Heroic to open Mythic'), 'mythic lock hint')
Profile.data.zoneDiff['1'] = 3
Profile.data.keyMax['1'] = 12
Profile.data.gold = 5000
UI.safe(function() upvalue(G.startRun, 'Lobby').refresh() end)
MOCK.click('rewards x1.50')
MOCK.click('Mythic+')
check(S.difficulty == 4 and S.keyLevel == 12, 'Mythic+ at +12, got ' .. S.difficulty .. ' +' .. S.keyLevel)
MOCK.click('-')
check(S.keyLevel == 11, 'key down')
MOCK.click('+')
MOCK.click('+')
check(S.keyLevel == 12, 'key capped at max')
MOCK.tap(OSKEY_SPACE)
check(R() == nil, 'space does not start a run behind the difficulty window')
MOCK.tap(OSKEY_ESCAPE)
check(not MOCK.findText('Esc closes this menu') and not MOCK.findText('No end: kill the final boss'), 'escape closes the difficulty window only')
MOCK.tap(OSKEY_SPACE)
run = R()
note('mythic+ run: ' .. run.diff.name .. ' hp x' .. string.format('%.2f', run.diff.hp) .. ' lives=' .. run.stats.lives)
check(run.diff.level == 12, 'keystone +12 run')
play(640, {slayBosses = true, slayAfter = 605, immortal = true})
run = R()
note(tostring(MOCK.heroDeath)); note(string.format('mythic+ state: time %.1f ended=%s victory=%s finalSpawned=%s finalAt=%s life=%.0f hand=%s paused=%s',
    run.time, tostring(run.ended), tostring(run.victory), tostring(run.finalSpawned), tostring(run.finalAt),
    GetWidgetLife(run.hero), tostring(run.hand ~= nil), tostring(run.paused)))
check(run.ended and run.victory, 'mythic+ victory')
note(string.format('mythic+ result: upgrade +%d keyBest=%s keyMax=%s',
    run.keyUpgrade or -1, tostring(Profile.data.keyBest['1']), tostring(Profile.data.keyMax['1'])))
check(MOCK.findText('timed'), 'keystone timed line')
MOCK.click('Play Again')
check(R() ~= nil and not R().ended, 'play again starts a run')
play(20)
run = R()
UnitDamageTarget(next(run.enemies), run.hero, 1e7, true, false, ATTACK_TYPE_CHAOS, DAMAGE_TYPE_NORMAL, WEAPON_TYPE_WHOKNOWS)
MOCK.advance(0.1)
check(R().ended and not R().victory, 'defeat')
check(MOCK.findText('DEFEAT'), 'defeat screen')
MOCK.click('Return to Camp')

-- 4. Armory upgrades and talents.
MOCK.click('Armory')
MOCK.pokeAll()
local before = Profile.data.gold
MOCK.click('Upgrade')
note('armory upgrade spent ' .. (before - Profile.data.gold) .. ' gold')
check(before > Profile.data.gold, 'upgrade costs gold')
-- Looted items go straight into the six-slot inventory; Unequip and Equip move them.
local function carried()
    local n = 0
    for _ in pairs(Profile.data.inv) do n = n + 1 end
    return n
end
local looted = 0
for _ in pairs(Profile.data.gear) do looted = looted + 1 end
check(carried() == math.min(6, looted), 'loot fills the inventory, carried ' .. carried() .. ' of ' .. looted)
local carriedBefore = carried()
MOCK.click('Unequip')
check(carried() == carriedBefore - 1, 'unequip frees a slot')
MOCK.click('Equip')
check(carried() == carriedBefore, 'equip fills it again')
note('inventory ok: ' .. carried() .. ' carried')
MOCK.click('Talents')
MOCK.click('gold')
MOCK.click('Rewards')
MOCK.click('Character')

-- Wisp Companion perk: gems and coins beyond the pickup range reach the hero.
Profile.data.perks.companion = 3
S.heroIndex, S.difficulty = 1, 1
G.startRun()
run = R()
check(run.companion ~= nil, 'the companion perk spawns a wisp')
MOCK.pokeAll()
G.dropPickup('gold', run.hx + 900, run.hy, 50)
local farCoin = run.pickups[#run.pickups]
G.dropPickup('xp', run.hx - 600, run.hy + 500, 3)
local farGem = run.pickups[#run.pickups]
local function lying(p)
    for _, q in ipairs(R().pickups) do
        if q == p then return true end
    end
    return false
end
for _ = 1, 60 do
    MOCK.advance(0.25)
    if R().hand then MOCK.tap(OSKEY_1) end
    if not lying(farCoin) and not lying(farGem) then break end
end
check(not lying(farCoin) and not lying(farGem), 'the wisp fetched the far coin and gem')
note('companion fetched far pickups')
-- A run that ends while paused (Main Menu in the game menu) gets its sound back.
G.setPaused(true)
check(MOCK.groupVolume[SOUND_VOLUMEGROUP_SPELLS] == 0, 'paused before the end')
G.endRun(false)
check(MOCK.groupVolume[SOUND_VOLUMEGROUP_SPELLS] > 0, 'the end screen has its sound')
MOCK.click('Return to Camp')
Profile.data.perks.companion = nil

-- World objects: three lie near the start; walking onto a free one pays out,
-- a paid chest waits for the gold, then opens a card hand.
S.heroIndex, S.difficulty = 1, 1
G.startRun()
run = R()
check(#run.interactables == 3, 'a run starts with three world objects, got ' .. #run.interactables)
local function objectOf(kind)
    for _, o in ipairs(run.interactables) do
        if o.kind == kind then return o end
    end
end
local function standOn(o)
    SetUnitX(run.hero, o.x)
    SetUnitY(run.hero, o.y)
end
local vein = objectOf('vein')
local goldBefore = run.gold
standOn(vein)
MOCK.advance(0.1)
check(objectOf('vein') == nil and run.gold > goldBefore, 'walking onto the gold vein mines it')
check(vein.fx.dead and vein.glow.dead, 'a used object takes its art away')
local chest = objectOf('chest')
check(chest.price == 40 and chest.priceTag ~= nil, 'the chest shows its price')
run.gold = 0
standOn(chest)
MOCK.advance(0.5)
check(objectOf('chest') == chest, 'a chest without the gold stays shut')
run.gold = 1000
MOCK.advance(0.5)
check(objectOf('chest') == nil and run.worldChestsOpened == 1, 'the chest opens once the gold is there')
check(run.hand ~= nil or run.pendingChests > 0, 'the chest deals a card hand')
check(chest.priceTag == nil, 'its price tag goes with it')
if run.hand then MOCK.tap(OSKEY_1) end
-- The shrine's countdown only falls, waits while an enemy stands in its ring,
-- and pays out after 10 clear seconds.
do
    local function settle(seconds)
        for _ = 1, math.ceil(seconds / 0.03125) do
            MOCK.advance(0.03125)
            if run.hand then MOCK.tap(OSKEY_1) end
        end
    end
    local shrine = G.spawnWorldObject('protection', run.hx + 1500, run.hy, true)
    local away = {run.hx, run.hy}
    standOn(shrine)
    MOCK.advance(0.1)
    check(shrine.challenge and shrine.priceTag and shrine.priceTag.text == '10', 'the shrine wakes showing 10')
    -- The hero leaves. Whatever else is near the shrine, only a clear ring counts.
    SetUnitX(run.hero, away[1])
    SetUnitY(run.hero, away[2])
    local blocker = G.createEnemy(G.pickEnemyType(), shrine.x + 50, shrine.y, {})
    settle(0.5)
    local held = shrine.progress
    settle(2)
    check(shrine.progress == held and shrine.priceTag.g < 100, 'an enemy in the ring holds the countdown, in red')
    UnitDamageTarget(run.hero, blocker, 1e7, false, false, ATTACK_TYPE_CHAOS, DAMAGE_TYPE_NORMAL, WEAPON_TYPE_WHOKNOWS)
    local goldBeforeShrine = run.gold
    local last = tonumber(shrine.priceTag.text)
    for _ = 1, 12 / 0.25 do
        if not shrine.active then break end
        settle(0.25)
        for u in pairs(run.enemies) do
            local dx, dy = GetUnitX(u) - shrine.x, GetUnitY(u) - shrine.y
            if u ~= run.hero and dx * dx + dy * dy < 90000 then
                UnitDamageTarget(run.hero, u, 1e7, false, false, ATTACK_TYPE_CHAOS, DAMAGE_TYPE_NORMAL, WEAPON_TYPE_WHOKNOWS)
            end
        end
        if shrine.active then
            local now = tonumber(shrine.priceTag.text)
            check(now <= last, 'the countdown never goes back up, ' .. last .. ' to ' .. now)
            last = now
        end
    end
    check(not shrine.active and run.gold >= goldBeforeShrine + 100, 'a protected shrine pays out')
    check(shrine.priceTag == nil, 'its countdown goes with it')
end
-- World objects keep coming, chests among them, within the hero's reach.
do
    local kinds, near = {}, 0
    for _ = 1, 15 do
        kinds[#kinds + 1] = G.nextWorldObjectKind()
    end
    local count = {}
    for _, kind in ipairs(kinds) do count[kind] = (count[kind] or 0) + 1 end
    check(count.chest == 4 and count.wealth == 1, 'the deck deals every card once')
    for _ = 1, 10 do
        local x, y = G.spawnWorldObjectPoint()
        if x then
            local d = math.sqrt((x - run.hx) ^ 2 + (y - run.hy) ^ 2)
            if d <= 1400.01 and d >= 700 then near = near + 1 end
        end
    end
    check(near >= 8, 'objects turn up around the hero, near=' .. near)
    note('objects: deck deals 4 chests in 15, ' .. near .. '/10 points near the hero')
end
-- A hero's spells cannot be banished; blessings can.
do
    local Cards = upvalue(G.tryOpenHand, 'Cards')
    if run.hand then MOCK.tap(OSKEY_1) end
    Cards.open('chest')
    local spellCard, blessingCard
    for _ = 1, 200 do
        for _, c in ipairs(Cards.draw(3, nil, 1)) do
            if c.type == 'spell' then spellCard = spellCard or c end
            if c.type == 'blessing' then blessingCard = blessingCard or c end
        end
        if spellCard and blessingCard then break end
    end
    check(spellCard and blessingCard, 'the deck deals spells and blessings')
    run.hand.cards = {spellCard, blessingCard}
    run.banishes = 2
    Cards.render()
    check(not Cards.cards[1].banish.enabled, 'the button is off on a spell card')
    check(Cards.cards[2].banish.enabled, 'the button is on for a blessing card')
    Cards.banish(1)
    check(run.banishes == 2 and not run.banished[spellCard.key] and run.hand.cards[1] == spellCard, 'a spell cannot be banished')
    Cards.banish(2)
    check(run.banishes == 1 and run.banished[blessingCard.key], 'a blessing can')
    for _ = 1, 3 do
        if run.hand then MOCK.tap(OSKEY_1) end
    end
    note('banish: blessings only')
end
-- Card power: rarity adds instead of multiplying, Multishot stops at its cap, life steal has a budget.
do
    local Cards = upvalue(G.tryOpenHand, 'Cards')
    local near = function(a, b) return math.abs(a - b) < 0.001 end
    local v = G.spellValues({dmg = 100, per = 0.1}, 10, 2.0, G.baseStats())
    check(near(v.dmg, 100 * (1 + 0.35 * 9 + 1)), 'spell rank and rarity add, dmg=' .. v.dmg)
    check(near(v.amount, 0.1 * 11), 'a spell amount adds rarity too, amount=' .. v.amount)
    check(near(G.blessingTotal({per = 0.1}, 10, 2.0), 1.1), 'a blessing adds rarity per card')

    local saved = run.blessings.multishot
    local order = #run.blessingOrder
    run.blessings.multishot = nil
    G.recomputeStats()
    local base = run.stats.multishot
    G.applyCard({type = 'blessing', key = 'multishot', rarity = 5})
    check(run.stats.multishot == math.min(base + 1, 6), 'a legendary Multishot is still +1, now ' .. run.stats.multishot)
    for _ = 1, 8 do
        G.applyCard({type = 'blessing', key = 'multishot', rarity = 5})
    end
    check(run.stats.multishot == 6, 'extra projectiles stop at 6, now ' .. run.stats.multishot)
    local offered = false
    for _, o in ipairs(Cards.options({})) do
        offered = offered or o.key == 'multishot' or o.key == 'barrage'
    end
    check(not offered, 'no projectile card is dealt at the cap')
    run.blessings.multishot = saved
    while #run.blessingOrder > order do
        table.remove(run.blessingOrder)
    end
    G.recomputeStats()

    local maxHp = BlzGetUnitMaxHP(run.hero)
    SetWidgetLife(run.hero, 1)
    local stats = run.stats
    local lifesteal = stats.lifesteal
    stats.lifesteal = 0.1
    run.stealReset = nil
    G.lifesteal(1000000)
    check(near(GetWidgetLife(run.hero), 1 + maxHp * 0.05), 'life steal 10 percent heals 5 percent of max health at most, life=' .. GetWidgetLife(run.hero))
    G.lifesteal(1000000)
    check(near(GetWidgetLife(run.hero), 1 + maxHp * 0.05), 'the budget lasts a second')
    stats.lifesteal = 0.5
    run.stealReset = nil
    SetWidgetLife(run.hero, 1)
    G.lifesteal(1000000)
    check(near(GetWidgetLife(run.hero), 1 + maxHp * 0.10), 'life steal heals 10 percent of max health a second at most')
    stats.lifesteal = lifesteal
    run.stealReset = nil
    SetWidgetLife(run.hero, maxHp)
    note('card power: additive, projectiles capped, life steal budget')
end
-- Boss patterns: one per zone in play order, harder as the zones go, every
-- spell castable; a pause keeps the warning fair; the hero is hit only inside.
do
    check(#G.bossPatterns == 12, 'a pattern for each of the 12 zones')
    local used, seen = {}, {}
    local lastScale = 99
    for rank, pattern in ipairs(G.bossPatterns) do
        check(pattern.scale <= lastScale, 'telegraphs never get slower, zone ' .. rank)
        lastScale = pattern.scale
        for _, kit in ipairs({pattern.boss, pattern.final}) do
            local name = table.concat(kit, ' ')
            check(not seen[name], 'a kit appears once: ' .. name)
            seen[name] = true
            for _, key in ipairs(kit) do
                check(G.bossSpells[key] and G.bossBuild[key], 'kit spell exists: ' .. key)
                used[key] = true
            end
        end
    end
    for key in pairs(G.bossSpells) do
        check(used[key], 'every boss spell is used: ' .. key)
    end
    local hits = 0
    local realHit = G.bossHit
    G.bossHit = function(...) hits = hits + 1; return realHit(...) end
    local bossDef = run.zone.bosses[1]
    G.spawnBoss(bossDef, false)
    local boss = run.bossUnits[#run.bossUnits]
    local info = run.enemies[boss]
    info.slamAt = 1e9
    -- By the run's own clock (a level-up hand pauses it), the boss and the hero kept alive.
    local function settle(seconds)
        local target = run.time + seconds
        for _ = 1, 400 do
            if run.time >= target then break end
            SetWidgetLife(boss, BlzGetUnitMaxHP(boss))
            SetWidgetLife(run.hero, BlzGetUnitMaxHP(run.hero))
            MOCK.advance(0.03125)
            if run.hand then MOCK.tap(OSKEY_1) end
        end
    end
    for key in pairs(G.bossSpells) do
        info.kitOverride = {key}
        info.kitStep = 0
        local before = errors()
        local length = G.bossCast(boss, info)
        check(length > 0, 'a cast has a length: ' .. key)
        settle(length + 0.5)
        check(errors() == before, 'boss spell runs clean: ' .. key)
        check(not info.casting, 'the boss moves again after: ' .. key)
        check(next(run.bossTelegraphs) == nil, 'no telegraph left after: ' .. key)
    end
    -- A hit lands on a hero who stands still in a slam, not on one who left.
    local function slamOn(stay)
        hits = 0
        info.kitOverride = {'slam'}
        info.kitStep = 0
        info.hitAt = 0
        local length = G.bossCast(boss, info)
        if not stay then
            SetUnitX(run.hero, run.hx + 900)
        end
        settle(length + 0.25)
        return hits
    end
    check(slamOn(true) == 1, 'a slam catches a hero standing in it')
    check(slamOn(false) == 0, 'a hero who walks out is safe')
    -- 'safe' burns all but one spot.
    info.kitOverride = {'safe'}
    local parts = G.bossBuild.safe({bx = run.hx + 300, by = run.hy, hx = run.hx, hy = run.hy, facing = 0, dist = 300})
    local spec = parts[1].spec
    check(spec.shape == 'ring' and not G.inTelegraph(spec, spec.x, spec.y) and G.inTelegraph(spec, run.hx, run.hy),
        'safe: the spot is safe, the hero\'s place is not')
    -- A pause during a cast: the warning goes, comes back with the time left, the hit still lands.
    hits = 0
    info.kitOverride = {'slam'}
    info.kitStep = 0
    info.hitAt = 0
    local length = G.bossCast(boss, info)
    settle(0.5)
    local entry = next(run.bossTelegraphs)
    check(entry and entry.id ~= nil, 'the slam is on the ground')
    local endsAt = entry.endsAt
    G.setPaused(true)
    check(entry.id == nil, 'a pause takes the warning away')
    G.setPaused(false)
    check(entry.id ~= nil and entry.endsAt == endsAt, 'the end of the pause draws it again')
    settle(length)
    check(hits == 1, 'the hit lands after the pause, hits=' .. hits)
    G.bossHit = realHit
    UnitDamageTarget(run.hero, boss, 1e7, false, false, ATTACK_TYPE_CHAOS, DAMAGE_TYPE_NORMAL, WEAPON_TYPE_WHOKNOWS)
    MOCK.advance(0.1)
    if run.hand then MOCK.tap(OSKEY_1) end
    note('boss patterns: 12 zones, every spell runs, hits and pauses are fair')
end
-- Bodies block: a step into an enemy is held back, and a step away is free.
G.refreshEnemyCache()
local blocker = run.elist[1]
SetUnitX(blocker, run.hx + 40)
SetUnitY(blocker, run.hy)
G.refreshEnemyCache()
local nx = G.collide(run.hx, run.hy, run.hx + 20, run.hy)
check(nx <= run.hx + 0.01, 'an enemy in the way blocks the hero, moved ' .. (nx - run.hx))
nx = G.collide(run.hx, run.hy, run.hx - 20, run.hy)
check(math.abs(nx - (run.hx - 20)) < 0.01, 'the hero can always step away')
-- A save from 1.3.0 test builds that turned collision off no longer matters.
Profile.data.opts.collide = 0
nx = G.collide(run.hx, run.hy, run.hx + 20, run.hy)
check(nx <= run.hx + 0.01, 'collision cannot be turned off, moved ' .. (nx - run.hx))
Profile.data.opts.collide = nil
G.endRun(false)
MOCK.click('Return to Camp')
check(#MOCK.liveTags() == 0, 'no price tag is left after the run')
note('world objects: vein mined, chest opened for 40 gold, collision blocks')

-- 5. Every hero with every spell of its pool at a high rank (no rank limit).
for index, hero in ipairs(HEROES) do
    S.heroIndex = index
    S.difficulty = 1
    -- The starting spell is the one picked in the lobby.
    local pick = (index - 1) % #hero.pool + 1
    Profile.data.starts[hero.id] = pick
    G.startRun()
    run = R()
    check(run.spells[1].def.key == hero.pool[pick], hero.name .. ' starts with ' .. hero.pool[pick])
    for _, key in ipairs(hero.pool) do
        local inst = run.spellByKey[key] or G.learnSpell(key, 1.3)
        inst.rank = SPELLS[key].maxRank or 15
    end
    G.recomputeStats()
    if run.spellByKey.mirror_image then
        G.mirrorImages(2, 200)
        local image = next(run.images)
        check(image ~= nil, 'mirror images appear')
        local life = GetWidgetLife(image)
        UnitDamageTarget(next(run.enemies), image, 10, true, false, ATTACK_TYPE_CHAOS, DAMAGE_TYPE_NORMAL, WEAPON_TYPE_WHOKNOWS)
        check(math.abs(life - GetWidgetLife(image) - 30) < 0.01, 'mirror images take triple damage, lost '
            .. (life - GetWidgetLife(image)))
        note('mirror image takes 10 x 3')
    end
    if run.spellByKey.raven_form then
        -- Medivh turns into the raven (the Alternate sequences), flies over
        -- enemies, and comes back to his own attack when it ends.
        local CAST = upvalue(G.updateSpells, 'CAST')
        local inst = run.spellByKey.raven_form
        MOCK.advance(0.1)
        if run.hand then MOCK.tap(OSKEY_1) end
        for _ = 1, 5 do
            G.createEnemy(G.pickEnemyType(), run.hx + 60, run.hy, {})
        end
        G.refreshEnemyCache()
        check(run.buffs.raven_form or CAST.buff(inst, inst.v), 'raven form casts when surrounded')
        check(run.hero.props == 'alternate' and run.attackAnim == 'attack', 'medivh becomes the raven')
        local nx = G.collide(run.hx, run.hy, run.hx + 20, run.hy)
        check(math.abs(nx - (run.hx + 20)) < 0.01, 'the raven flies over enemies')
        for _ = 1, math.ceil(inst.v.dur / 0.25) + 4 do
            MOCK.advance(0.25)
            if run.hand then MOCK.tap(OSKEY_1) end
        end
        check(run.buffs.raven_form == nil or run.buffs.raven_form.untilT > run.time, 'raven form ends')
        if run.buffs.raven_form == nil then
            check(run.hero.props == nil and run.attackAnim == 'spell', 'medivh takes his own form back, attack '
                .. tostring(run.attackAnim))
        end
        note('medivh raven form morphs and flies')
    end
    if run.spellByKey.metamorphosis then
        -- The Demon Hunter plays the model's Morph clip, becomes the demon
        -- (Alternate sequences, demon missile) and plays the way back.
        local CAST = upvalue(G.updateSpells, 'CAST')
        local inst = run.spellByKey.metamorphosis
        local function wait(seconds)
            for _ = 1, math.ceil(seconds / 0.25) do
                MOCK.advance(0.25)
                if run.hand then MOCK.tap(OSKEY_1) end
            end
        end
        wait(run.buffs.metamorphosis and inst.v.dur + 2 or 2)
        for _ = 1, 5 do
            G.createEnemy(G.pickEnemyType(), run.hx + 60, run.hy, {})
        end
        G.refreshEnemyCache()
        if run.buffs.metamorphosis == nil and not run.morphEnd then
            check(CAST.buff(inst, inst.v), 'metamorphosis casts when surrounded')
            check(run.buffs.metamorphosis.fx == nil, 'metamorphosis has no borrowed caster art')
            check(run.morphEnd and run.hero.props ~= 'alternate', 'the morph clip plays before the form changes')
        end
        wait(inst.def.morphTime + 0.5)
        check(run.hero.props == 'alternate' and run.missile:find('DemonHunterMissile') ~= nil,
            'the demon form takes over, with the demon missile')
        wait(inst.v.dur + inst.def.morphTime + 1)
        check(run.hero.props ~= 'alternate' and run.missile == run.heroMissile, 'the demon hunter takes his own form back')
        note('demon hunter metamorphosis morphs and back')
    end
    if run.spellByKey.storm_earth_fire then
        -- The Brewmaster splits into three spirits, hidden and invulnerable,
        -- and merges back when the split ends.
        local CAST = upvalue(G.updateSpells, 'CAST')
        local inst = run.spellByKey.storm_earth_fire
        MOCK.advance(0.1)
        if run.hand then MOCK.tap(OSKEY_1) end
        check(run.split or CAST.summon(inst, inst.v), 'storm, earth and fire casts')
        inst.cd = inst.v.cd
        -- The mock lists npn1 as an unknown rawcode: Storm and Earth come out.
        check(run.split and #run.split.units == 2, 'the spirits that exist come out, got '
            .. tostring(run.split and #run.split.units))
        check(run.hero.alpha == 0, 'the split hero is hidden')
        local spirits = run.split.units
        for _ = 1, math.ceil(inst.v.dur / 0.25) + 4 do
            MOCK.advance(0.25)
            if run.hand then MOCK.tap(OSKEY_1) end
        end
        check(run.split == nil, 'the split ends, time ' .. run.time .. ' until ' .. tostring(run.split and run.split.untilT)
            .. ' paused=' .. tostring(run.paused) .. ' hand=' .. tostring(run.hand ~= nil) .. ' ended=' .. tostring(run.ended)
            .. ' same=' .. tostring(run.split == spirits))
        check(run.hero.alpha == 255, 'the hero comes back')
        for _, u in ipairs(spirits) do
            check(u.removed and run.summons[u] == nil, 'the spirits merge back')
        end
        note(string.format('brewmaster split %.1f s and merged', inst.v.dur))
    end
    play(45, {slayBosses = true})
    run = R()
    -- Extra lives and invulnerability buffs mean it can take a few blows.
    local blows = 0
    while run and not run.ended and blows < 20 do
        blows = blows + 1
        run.hero.invulnerable = false
        local attacker = next(run.enemies) or run.hero
        UnitDamageTarget(attacker, run.hero, 1e7, true, false, ATTACK_TYPE_CHAOS, DAMAGE_TYPE_NORMAL, WEAPON_TYPE_WHOKNOWS)
        MOCK.advance(3)
        if run.hand then MOCK.tap(OSKEY_1) end
    end
    check(run.ended, hero.name .. ' run ends after ' .. blows .. ' blows')
    MOCK.click('Return to Camp')
end
note('all ' .. #HEROES .. ' heroes played with full pools')

-- Mana Burn: the ability's own beam and target art, no missile.
do
    for index, hero in ipairs(HEROES) do
        if hero.id == 'Edem' then S.heroIndex = index end
    end
    S.difficulty = 1
    G.startRun()
    run = R()
    local def = SPELLS.mana_burn
    check(def.beam == 'MBUR' and def.instant and def.missile == nil, 'Mana Burn is a beam, not a missile')
    check(def.impact:find('ManaBurnTarget', 1, true), 'Mana Burn keeps its target art')
    local u = G.createEnemy(run.zone.enemies[1], run.hx + 400, run.hy, {})
    u.life, u.maxHp = 1000000, 1000000   -- it must outlive the hit for the beam to follow it
    G.refreshEnemyCache()
    local bolts, launched = {}, 0
    local add, launch = AddLightningEx, G.launch
    AddLightningEx = function(...) local b = add(...); bolts[#bolts + 1] = b; return b end
    G.launch = function(...) launched = launched + 1; return launch(...) end
    local inst = G.learnSpell('mana_burn')
    check(upvalue(G.updateSpells, 'CAST').bolt(inst, G.spellValues(def, 1, 1, run.stats)), 'Mana Burn casts')
    AddLightningEx, G.launch = add, launch
    check(#bolts >= 1 and bolts[1].code == 'MBUR' and launched == 0, 'one beam per target, nothing launched')
    run.hx, run.hy = run.hx + 100, run.hy + 50
    SetUnitPosition(u, GetUnitX(u) + 70, GetUnitY(u))
    G.updateBeams()
    check(run.enemies[u] and bolts[1].x1 == run.hx and bolts[1].x2 == GetUnitX(u), 'the beam stays on the hero and the target')
    local lastX = bolts[1].x2
    UnitDamageTarget(run.hero, u, 1e9, false, false, nil, nil, nil)
    SetUnitPosition(u, lastX + 500, GetUnitY(u))
    G.updateBeams()
    check(run.enemies[u] == nil and bolts[1].x2 == lastX, 'a dead target keeps the beam at its last point')
    run.time = run.time + 0.6
    G.runScheduled()
    G.updateBeams()
    check(bolts[1].dead and #run.beams == 0, 'the beam ends by itself')
    G.endRun(false)
    MOCK.click('Return to Camp')
    note('mana burn: beam from the hero to the target')
end

-- Leftover effects/units check.
local alive = 0
for u in pairs(MOCK.units) do alive = alive + 1 end
-- The last hero is the Forsaken Paladin, which the mock treats as an unknown
-- rawcode, so no lobby preview unit is expected here.
note('units left in lobby: ' .. alive)

local missing = {}
for name in pairs(MOCK.missing) do missing[#missing + 1] = name end
table.sort(missing)
note('natives not in mock: ' .. table.concat(missing, ', '))
note('script errors printed: ' .. errors())
for i = 1, math.min(10, #MOCK.printed) do note('  ' .. MOCK.printed[i]) end
return table.concat(report, '\n')
