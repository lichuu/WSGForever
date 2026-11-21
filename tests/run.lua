-- Scenario tests. From the addon folder: lua5.1 tests/run.lua
-- Each scenario scripts what the game reported in a real match and checks
-- what the addon decides to show.

local dir = arg and arg[1] or "."
package.path = dir .. "/tests/?.lua;" .. package.path
local sim = require("wow")

local failures, count = {}, 0
local current

local function check(ok, what)
    if not ok then failures[#failures + 1] = current .. ": " .. what end
end

local function dropped() return sim.showing("Dropped %- returns in") end

-- The addon reports its own errors in chat instead of raising them.
local function noErrors()
    for _, line in ipairs(sim.printed) do
        if line:lower():find("error") or line:find("failed to start") or line:find("couldn't") then
            check(false, "addon reported: " .. line)
        end
    end
end

local friend = { name = "Cheat", surname = "Jump", side = "friend", inRaid = true }
local friend2 = { name = "Isaac", surname = "Braums", side = "friend", inRaid = true }
local enemy = { name = "Hella", surname = "Slick", side = "enemy" }
local hiddenSide = { name = "Bella", surname = "Lefay", side = "hidden" }

local function say(msg) sim.fire("CHAT_MSG_BG_SYSTEM_NEUTRAL", msg) end

local function scenario(name, fn)
    current = name
    count = count + 1
    -- A clean match: nobody carrying, flags at base.
    sim.setCarrier(1, nil)
    sim.setCarrier(2, nil)
    say("The flags are now placed at their bases.")
    sim.run(1)
    sim.printed = {}
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": crashed: " .. tostring(err) end
    noErrors()
end

local GK = sim.load(dir)
current = "loading the addon"
sim.run(8) -- long enough for every module's first updates
noErrors()

scenario("a dropped flag counts down from 12 and then clears", function()
    say("The Alliance Flag was picked up by Cheat Jump!")
    sim.setCarrier(1, friend)
    sim.run(2)
    check(not dropped(), "showed Dropped while the flag was carried")
    sim.setCarrier(1, nil)
    say("The Alliance Flag was dropped by Cheat Jump!")
    sim.run(0.5)
    local text = dropped()
    check(text ~= nil, "no countdown after a real drop")
    check(text and text:find("returns in 12") ~= nil, "countdown did not start at 12, got: " .. tostring(text))
    sim.run(6)
    check(dropped() and dropped():find("returns in 6") ~= nil, "countdown not at 6 after six seconds, got: " .. tostring(dropped()))
    sim.run(7)
    check(not dropped(), "countdown still showing after it ran out")
end)

scenario("a drop seen only through the carrier slots still counts down", function()
    sim.setCarrier(1, friend)
    sim.run(2)
    sim.setCarrier(1, nil)
    sim.run(2)
    check(dropped() ~= nil, "no countdown after the carrier slot emptied")
end)

scenario("a pickup cancels the countdown", function()
    sim.setCarrier(1, friend)
    sim.run(2)
    sim.setCarrier(1, nil)
    say("The Alliance Flag was dropped by Cheat Jump!")
    sim.run(2)
    check(dropped() ~= nil, "no countdown after the drop")
    sim.setCarrier(1, friend2)
    say("The Alliance Flag was picked up by Isaac Braums!")
    sim.run(1)
    check(not dropped(), "countdown kept running after a teammate picked the flag up")
end)

scenario("a hand-off to a carrier whose side is hidden is not a drop", function()
    -- 18 Nov: both flags carried, the new carrier's team unreadable.
    sim.setCarrier(1, enemy)
    sim.setCarrier(2, friend)
    sim.run(2)
    sim.setCarrier(2, nil)
    sim.run(0.4)
    sim.setCarrier(2, hiddenSide)
    for _ = 1, 30 do
        sim.run(0.2)
        check(not dropped(), "showed Dropped with both flags carried")
        if dropped() then break end
    end
end)

scenario("no countdown while both of the game's carrier frames are showing", function()
    -- The slots can read as empty to addons while the game still shows two carriers.
    sim.setCarrier(1, enemy)
    sim.setCarrier(2, friend)
    sim.run(2)
    say("The Alliance Flag was dropped by Cheat Jump!")
    sim.units.arena1, sim.units.arena2 = nil, nil -- hidden from the addon, frames still shown
    sim.run(3)
    check(not dropped(), "showed Dropped while two carrier frames were on screen")
end)

scenario("a capture starts the spawn timer, not a drop countdown", function()
    sim.setCarrier(1, friend)
    sim.run(2)
    sim.setCarrier(1, nil)
    say("Cheat Jump captured the Alliance flag!")
    sim.run(2)
    check(not dropped(), "showed Dropped after a capture")
    check(sim.showing("Flags spawn in") ~= nil, "no flag spawn countdown after a capture")
    sim.run(13)
    check(not sim.showing("Flags spawn in"), "spawn countdown still showing after 12 seconds")
end)

scenario("a returned flag clears the countdown", function()
    sim.setCarrier(1, friend)
    sim.run(2)
    sim.setCarrier(1, nil)
    say("The Alliance Flag was dropped by Cheat Jump!")
    sim.run(2)
    say("The Alliance Flag was returned to its base by Hella Slick!")
    sim.run(0.5)
    check(not dropped(), "countdown kept running after the flag was returned")
end)

scenario("every command and the settings window run without errors", function()
    local slash = SlashCmdList.WSGFOREVER
    slash("")
    check(sim.showing("Carrier health and drop timer") ~= nil, "plain /fc did not open the settings window")
    check(sim.showing("^version 0%.6%.0$") ~= nil, "version not shown in the window")
    slash("options")
    check(sim.showing("Carrier health and drop timer") == nil, "/fc options did not close the open window")
    sim.printed = {}
    slash("help")
    local help = table.concat(sim.printed, " | ")
    check(help:find("/fc history") and help:find("/fc scale") and not help:find("/fc enemies"), "help text wrong: " .. help)
    local before = GK.db.enemies
    slash("enemies")
    check(GK.db.enemies ~= before, "an unlisted feature command stopped working")
    slash("enemies")
    for _, cmd in ipairs({ "help", "test", "test", "unlock", "lock", "scale", "scale map 130", "scale callouts 110",
        "options", "options", "minimap", "minimap", "debug", "reset", "callouts", "callouts", "carriers", "carriers",
        "fcnames", "fcnames", "blizzfc", "blizzfc", "lowalert", "lowalert", "fcicon", "fcicon", "rez", "rez",
        "enemies", "enemies", "assist", "assist", "bgmap", "bgmap" }) do
        slash(cmd)
        sim.run(0.3)
    end
    for _, line in ipairs(sim.printed) do
        if line:find("attempt to") or line:find("%.lua:%d+") then check(false, "command raised: " .. line) end
    end
    sim.printed = {} -- help text mentions no errors; the check above is the real one
end)

-- Match history ----------------------------------------------------------------

local function myRow(extra)
    local row = { name = "Test-Player", classToken = "PRIEST", faction = 0, killingBlows = 4, honorableKills = 21,
        deaths = 3, honorGained = 187, damageDone = 9000, healingDone = 42000,
        stats = { { pvpStatValue = 1 }, { pvpStatValue = 2 } } }
    for k, v in pairs(extra or {}) do row[k] = v end
    return row
end

local function newMatch()
    sim.instanceType, sim.winner = "none", nil
    sim.fire("PLAYER_ENTERING_WORLD")
    sim.instanceType = "pvp"
    sim.fire("PLAYER_ENTERING_WORLD")
end

scenario("a finished match is recorded once, with your scoreboard line", function()
    wipe(GK.db.matches)
    newMatch()
    sim.scores = { { name = "Someone-Else", classToken = "WARRIOR", faction = 1 }, myRow() }
    sim.winner = 0 -- Horde, the player's side
    sim.fire("PVP_MATCH_COMPLETE", 0, 754)
    sim.run(2)
    sim.fire("UPDATE_BATTLEFIELD_SCORE")
    sim.fire("UPDATE_BATTLEFIELD_SCORE")
    local m = GK.db.matches[1]
    check(#GK.db.matches == 1, "expected 1 record, got " .. #GK.db.matches)
    check(m and m.result == "win", "result should be a win, got " .. tostring(m and m.result))
    check(m and m.kills == 4 and m.deaths == 3 and m.honor == 187, "scoreboard numbers not stored")
    check(m and m.caps == 1 and m.returns == 2, "captures and returns not stored")
    check(m and m.seconds == 754, "match length not stored, got " .. tostring(m and m.seconds))
    check(m and m.map == "Warsong Gulch", "battleground name not stored")
    sim.printed = {}
end)

scenario("the next match is a new record, and a loss reads as a loss", function()
    wipe(GK.db.matches)
    newMatch()
    sim.scores = { myRow() }
    sim.winner = 0
    sim.fire("UPDATE_BATTLEFIELD_SCORE") -- clients without the match-complete event
    newMatch()
    sim.scores = { myRow({ killingBlows = 0 }) }
    sim.winner = 1
    sim.fire("UPDATE_BATTLEFIELD_SCORE")
    check(#GK.db.matches == 2, "expected 2 records, got " .. #GK.db.matches)
    check(GK.db.matches[1].result == "loss" and GK.db.matches[2].result == "win", "newest should be the loss")
    sim.printed = {}
end)

scenario("numbers the game hides are left blank, not a crash", function()
    wipe(GK.db.matches)
    newMatch()
    sim.scores = { myRow({ killingBlows = sim.SECRET, honorGained = sim.SECRET, stats = sim.SECRET }) }
    sim.winner = 1
    sim.fire("PVP_MATCH_COMPLETE", 1, sim.SECRET)
    sim.run(2)
    local m = GK.db.matches[1]
    check(m ~= nil, "no record saved")
    check(m and m.kills == nil and m.honor == nil and m.deaths == 3, "hidden values should be blank, readable ones kept")
    sim.printed = {}
end)

scenario("nothing is recorded while a match is still running, or with recording off", function()
    wipe(GK.db.matches)
    newMatch()
    sim.scores = { myRow() }
    sim.fire("UPDATE_BATTLEFIELD_SCORE")
    check(#GK.db.matches == 0, "recorded a match with no winner yet")
    GK.db.history = false
    sim.winner = 0
    sim.fire("UPDATE_BATTLEFIELD_SCORE")
    check(#GK.db.matches == 0, "recorded with recording turned off")
    GK.db.history = true
end)

scenario("the history tab opens, shows the totals, and switches with the settings tab", function()
    wipe(GK.db.matches)
    newMatch()
    sim.scores = { myRow() }
    sim.winner = 0
    sim.fire("UPDATE_BATTLEFIELD_SCORE")
    sim.printed = {}
    SlashCmdList.WSGFOREVER("history")
    check(sim.showing("1 matches") ~= nil and sim.showing("1 won") ~= nil, "summary line missing")
    check(sim.showing("Warsong Gulch") ~= nil, "match row missing")
    check(sim.showing("Carrier health and drop timer") == nil, "settings tab still showing behind the history tab")
    -- the settings tab hides the history, and /fc history again closes the window
    SlashCmdList.WSGFOREVER("options")
    check(sim.showing("1 won") == nil and sim.showing("Carrier health and drop timer") ~= nil, "switching to the settings tab failed")
    SlashCmdList.WSGFOREVER("history")
    SlashCmdList.WSGFOREVER("history")
    check(sim.showing("1 won") == nil and sim.showing("Carrier health and drop timer") == nil, "window did not close")
    sim.instanceType, sim.winner, sim.scores = "pvp", nil, {}
end)

scenario("the match timer counts from the gates opening", function()
    GK.db.gateWait = nil
    newMatch()
    sim.runTimeMs = 30000 -- half a minute in, still behind the gates
    sim.run(1)
    check(sim.showing("^0:00$") ~= nil, "timer should read 0:00 behind the gates")
    sim.runTimeMs = 120000
    say("Let the battle for Warsong Gulch begin!")
    sim.runTimeMs = 600000 -- whatever the game's own count says from here on
    sim.run(65.5)
    check(sim.showing("^1:05$") ~= nil, "timer should count from the gates opening")
    -- a reload mid-match keeps the start
    sim.fire("PLAYER_ENTERING_WORLD")
    sim.run(1)
    check(sim.showing("^1:06$") ~= nil, "timer lost its start on a reload")
    -- joining a match already under way: the game's count less the measured wait
    newMatch()
    sim.runTimeMs = 420000
    sim.run(1)
    check(sim.showing("^5:00$") ~= nil, "a late join should take the gate wait off the game's count")
    -- the game's own countdown also sets the start, ahead of time; the chat line then changes nothing
    newMatch()
    sim.runTimeMs = 90000
    sim.fire("START_TIMER", 1, 30, 120)
    sim.run(10)
    check(sim.showing("^0:00$") ~= nil, "timer should wait out the game's countdown")
    sim.run(20)
    say("Let the battle for Warsong Gulch begin!")
    sim.run(40.5)
    check(sim.showing("^0:40$") ~= nil, "timer should start when the game's countdown ends, got " .. tostring(sim.showing("^%d+:%d%d$")))
    newMatch()
    sim.runTimeMs = 420000
    -- where the game reports the match's own duration, that wins: zero while waiting, exact on a late join
    C_PvP.GetActiveMatchState = function() return sim.matchState end
    C_PvP.GetActiveMatchDuration = function() return sim.matchSeconds end
    sim.matchState, sim.matchSeconds = 2, 0
    sim.run(1)
    check(sim.showing("^0:00$") ~= nil, "timer should read 0:00 while the game says the match is waiting to start")
    sim.matchState, sim.matchSeconds = 3, 95
    sim.run(1)
    check(sim.showing("^1:35$") ~= nil, "timer should show the game's own match duration")
    sim.matchSeconds = sim.SECRET -- hidden from addons: fall back to our own signals
    sim.run(1)
    check(sim.showing("^5:00$") ~= nil, "a hidden duration should fall back, got " .. tostring(sim.showing("^%d+:%d%d$")))
    C_PvP.GetActiveMatchState, C_PvP.GetActiveMatchDuration = nil, nil
    -- a long match shows hours
    sim.runTimeMs = 3845000
    sim.run(1)
    check(sim.showing("^1:02:05$") ~= nil, "timer should show hours past sixty minutes")
    -- no count from the game at all: time since zoning in
    sim.runTimeMs = nil
    newMatch()
    sim.run(65.5)
    check(sim.showing("^1:05$") ~= nil, "without the game's count it should time from zoning in")
    SlashCmdList.WSGFOREVER("timer")
    check(not WSGForeverMatchTimer:IsShown(), "timer did not turn off")
    SlashCmdList.WSGFOREVER("timer")
    check(WSGForeverMatchTimer:IsShown(), "timer did not turn back on")
    GK.db.gateWait = nil
    sim.printed = {}
end)

scenario("the scoreboard's team tabs don't empty the enemy list or cut a team from the history", function()
    wipe(GK.db.matches)
    newMatch()
    sim.scores = { myRow(), { name = "Amy Ally", classToken = "PRIEST", faction = 1, killingBlows = 2 },
        { name = "Zed Ally", classToken = "WARRIOR", faction = 1, killingBlows = 1 } }
    sim.fire("UPDATE_BATTLEFIELD_SCORE")
    check(WSGForeverEnemy1:IsShown() and WSGForeverEnemy2:IsShown(), "enemy rows missing to begin with")
    -- the player clicks the Horde tab and closes the scoreboard: we put it back on All
    SetBattlefieldScoreFaction(0)
    sim.fire("UPDATE_BATTLEFIELD_SCORE")
    check(sim.scoreFilter == -1 and WSGForeverEnemy1:IsShown() and WSGForeverEnemy2:IsShown(), "enemy rows lost after the Horde tab")
    -- with the scoreboard still open their tab is left alone, and the list is kept as it was
    PVPMatchScoreboard = CreateFrame("Frame")
    SetBattlefieldScoreFaction(0)
    sim.fire("UPDATE_BATTLEFIELD_SCORE")
    check(sim.scoreFilter == 0, "changed the player's tab while they were looking at it")
    check(WSGForeverEnemy1:IsShown() and WSGForeverEnemy2:IsShown(), "enemy rows lost while the scoreboard was open")
    -- the match ends like that: saved now, and completed when both teams are back
    sim.winner = 0
    sim.fire("UPDATE_BATTLEFIELD_SCORE")
    local m = GK.db.matches[1]
    check(m and m.partial and m.kills == 4, "match should be saved as incomplete with your own line")
    PVPMatchScoreboard:Hide()
    sim.fire("UPDATE_BATTLEFIELD_SCORE")
    check(not m.partial and m.teams and #m.teams.theirs == 2 and #m.teams.mine == 1, "match not completed once both teams were back")
    PVPMatchScoreboard = nil
    sim.printed = {}
    sim.instanceType, sim.winner, sim.scores = "pvp", nil, {}
end)

scenario("hovering a match shows its final scoreboard", function()
    wipe(GK.db.matches)
    newMatch()
    sim.scores = { myRow(),
        { name = "Amy Ally", classToken = "PRIEST", faction = 1, killingBlows = 0, deaths = 5, honorableKills = 3, honorGained = 40 },
        { name = "Abe Horde", classToken = "WARRIOR", faction = 0 },
        { name = "Zed Ally", classToken = "WARRIOR", faction = 1, killingBlows = 9, deaths = 2, honorableKills = 30, honorGained = 250 } }
    sim.winner = 0
    sim.fire("UPDATE_BATTLEFIELD_SCORE")
    local m = GK.db.matches[1]
    check(m.teams and #m.teams.mine == 2 and #m.teams.theirs == 2 and m.side == 0, "teams not recorded")
    check(m.teams.theirs[1][1] == "Zed Ally" and m.teams.theirs[1][2] == "WARRIOR" and m.damage == 9000 and m.healing == 42000,
        "class or damage not read from the scoreboard")
    -- the same on a client whose scoreboard has no rank column
    wipe(GK.db.matches)
    newMatch()
    sim.scoreLayout = "modern"
    sim.winner = 0
    sim.fire("UPDATE_BATTLEFIELD_SCORE")
    sim.scoreLayout = nil
    m = GK.db.matches[1]
    check(m and m.teams.theirs[1][2] == "WARRIOR" and m.teams.mine[1][2] == "PRIEST" and m.damage == 9000 and m.healing == 42000,
        "class or damage wrong on the other scoreboard layout")
    sim.printed = {}
    SlashCmdList.WSGFOREVER("history")
    local views = GK.modules.History.views
    local hover = views[#views].hovers[1]
    check(hover:IsShown() and not views[#views].hovers[2]:IsShown(), "hover areas should only cover rows with a match")
    hover:GetScript("OnEnter")(hover)
    local tip = table.concat(sim.tip, " / ")
    check(tip:find("Horde %(2%) | Kills / Deaths / HK / Honor") and tip:find("Alliance %(2%)"), "tooltip headings wrong: " .. tip)
    -- most kills first, with the numbers; a player with no readable numbers shows dashes
    check(tip:find("Test%-Player | 4 / 3 / 21 / 187 / Abe Horde | %- / %- / %- / %-"), "your team wrong: " .. tip)
    check(tip:find("Zed Ally | 9 / 2 / 30 / 250 / Amy Ally | 0 / 5 / 3 / 40"), "enemy team wrong: " .. tip)
    m.teams = nil
    hover:GetScript("OnEnter")(hover)
    check(table.concat(sim.tip, " / "):find("not recorded") ~= nil, "a match without a scoreboard should say so")
    SlashCmdList.WSGFOREVER("history")
    sim.instanceType, sim.winner, sim.scores = "pvp", nil, {}
end)

scenario("battlegrounds import from Nova Instance Tracker once, dungeons are skipped", function()
    wipe(GK.db.matches)
    -- The shape Nova Instance Tracker saves, taken from a real file.
    NITdatabase = { global = { PvP = { instances = {
        { type = "party", instanceName = "Wailing Caverns", playerName = "Tear Gas", enteredTime = 5000, leftTime = 7000 },
        { type = "bg", instanceName = "Warsong Gulch", playerName = "Tear Gas", enteredTime = 3000, leftTime = 3554,
            winningFaction = 0, faction = 0, kb = 3, hk = 25, deaths = 0, honor = 267, damage = 4730, healing = 0 },
        { type = "bg", instanceName = "Warsong Gulch", playerName = "Tear Gas", enteredTime = 1000, leftTime = 2380,
            winningFaction = 1, faction = 0, kb = 1, hk = 9, deaths = 4, honor = 222, damage = 100, healing = 9000 },
    } } }, profileKeys = {} }
    local added = GK.modules.History:ImportNova()
    check(added == 2, "expected 2 imported, got " .. tostring(added))
    local newest, oldest = GK.db.matches[1], GK.db.matches[2]
    check(newest and newest.result == "win" and newest.kills == 3 and newest.honor == 267 and newest.seconds == 554, "newest match wrong")
    check(oldest and oldest.result == "loss" and oldest.deaths == 4, "older match wrong")
    check(GK.modules.History:ImportNova() == 0, "importing twice added duplicates")
    -- your own team comes over from Nova, including onto matches imported before teams existed
    NITdatabase.global.PvP.instances[2].group = { Tear = { classEnglish = "PRIEST" }, Khan = { classEnglish = "WARRIOR" } }
    newest.teams = nil
    GK.modules.History:ImportNova()
    check(newest.teams and #newest.teams.mine == 2 and newest.teams.mine[1][1] == "Khan" and newest.side == 0, "team not filled in from Nova")
    NITdatabase = nil
    check(GK.modules.History:ImportNova() == nil, "import without Nova should report nothing to read")
end)

scenario("enemy frame styles resize the rows, wait for combat to end, and reject unknown names", function()
    local slash = SlashCmdList.WSGFOREVER
    slash("style compact")
    check(GK.db.enemyStyle == "compact" and WSGForeverEnemy1:GetHeight() == 17, "compact style not applied")
    sim.inCombat = true
    slash("style flat")
    check(WSGForeverEnemy1:GetHeight() == 17, "rows were resized during combat")
    sim.inCombat = false
    sim.fire("PLAYER_REGEN_ENABLED")
    check(WSGForeverEnemy1:GetHeight() == 24 and WSGForeverEnemies:GetWidth() == 24 + 1 + 164, "style not applied after combat")
    slash("names")
    check(GK.db.enemyNames == false and not WSGForeverEnemy1.name:IsShown(), "names did not hide")
    slash("names")
    check(GK.db.enemyNames == true and WSGForeverEnemy1.name:IsShown(), "names did not come back")
    slash("style nonsense")
    check(GK.db.enemyStyle == "flat", "an unknown style name changed the setting")
    slash("test") -- with sample enemies on screen
    for _, s in ipairs(GK.enemyStyles) do
        slash("style " .. s[1])
        sim.run(0.5)
    end
    slash("style flat")
    slash("test")
end)

scenario("the style dropdown lists every style, and picking a style or texture applies it", function()
    local slash = SlashCmdList.WSGFOREVER
    slash("")
    local page = GK.modules.Options.pages[#GK.modules.Options.pages] -- the window's copy
    check(sim.showing("^Flat$") ~= nil, "the dropdown does not show the current style")
    check(sim.showing("^Dark compact$") == nil, "the list is open before it was clicked")
    page.styleDrop:Open()
    for _, s in ipairs(GK.enemyStyles) do
        check(sim.showing("^" .. s[2] .. "$") ~= nil, "style missing from the list: " .. s[2])
    end
    page.styleDrop:Pick("large")
    check(GK.db.enemyStyle == "large" and WSGForeverEnemy1:GetHeight() == 30, "picking Large did not apply it")
    check(sim.showing("^Large$") ~= nil and sim.showing("^Dark compact$") == nil, "the list stayed open, or the box shows the wrong style")
    page.styleDrop:Pick("minimal")
    check(WSGForeverEnemies:GetWidth() == 180, "the no-icon style should be only as wide as its bar")
    page.textureDrop:Open()
    check(sim.showing("^Style default$") ~= nil and sim.showing("^Blizzard$") ~= nil, "texture list wrong")
    page.textureDrop:Pick("Blizzard")
    check(GK.db.enemyTexture == "Blizzard", "texture not saved")
    page.textureDrop:Pick("")
    check(GK.db.enemyTexture == nil, "Style default should clear the texture choice")
    -- media shared by other addons shows in the lists; ElvUI's own media drives the ElvUI style
    LibStub = function() return {
        List = function(_, kind) return kind == "font" and { "Expressway", "PT Sans Narrow" } or { "ElvUI Norm" } end,
        Fetch = function(_, kind, name) return "Interface\\AddOns\\Shared\\" .. kind .. "\\" .. name end,
    } end
    page.fontDrop:Open()
    check(sim.showing("^Expressway$") ~= nil, "shared fonts missing from the font list")
    page.fontDrop:Pick("Expressway")
    check(GK.db.enemyFont == "Expressway", "font not saved")
    page.textureDrop:Open()
    check(sim.showing("^ElvUI Norm$") ~= nil, "shared textures missing from the texture list")
    page.textureDrop:Pick("")
    page.fontDrop:Pick("")
    check(GK.db.enemyFont == nil, "Style default should clear the font choice")
    -- With a suite running, its unit frame settings are read; shapes as in ElvUI 15 and EllesmereUI (Nov 2026).
    slash("test")
    ElvUI = { { media = { normTex = "Interface\\AddOns\\ElvUI\\Norm", normFont = "Interface\\AddOns\\ElvUI\\Font.ttf" },
        db = { unitframe = { statusbar = "ElvUI Norm", font = "Expressway", fontSize = 10, fontOutline = "MONOCHROMEOUTLINE",
            colors = { healthclass = false, health = { r = 0.31, g = 0.31, b = 0.31 } } } } } }
    slash("style elvui")
    check(GK.db.enemyStyle == "elvui" and WSGForeverEnemy1:GetHeight() == 22, "ElvUI style not applied")
    EllesmereUI = { GetFontPath = function() return "Interface\\AddOns\\EllesmereUI\\Expressway.TTF" end,
        GetFontOutlineFlag = function() return "OUTLINE, SLUG" end,
        GetClassColor = function(token) return { r = 0.5, g = 0.5, b = 0.5 } end }
    slash("style ellesmere")
    check(GK.db.enemyStyle == "ellesmere", "EllesmereUI style not applied")
    -- A suite laid out differently from what we expect must not break anything.
    ElvUI = { { db = "unexpected", media = 5 } }
    EllesmereUI = { GetFontPath = function() error("changed") end, GetClassColor = function() error("changed") end }
    slash("style elvui")
    slash("style ellesmere")
    ElvUI, EllesmereUI, LibStub = nil, nil, nil
    slash("style elvui") -- and both are fine with neither suite installed
    slash("style ellesmere")
    slash("test")
    slash("style flat")
    slash("options")
end)

scenario("Arathi Basin shows its own callout bar, and Warsong Gulch its own", function()
    check(WSGForeverCallouts:IsShown() and not WSGForeverABCallouts:IsShown(), "Warsong Gulch should show only its own bar")
    sim.zone, sim.instanceID = "Arathi Basin", 529
    sim.fire("PLAYER_ENTERING_WORLD")
    check(WSGForeverABCallouts:IsShown() and not WSGForeverCallouts:IsShown(), "Arathi Basin should show only its own bar")
    check(WSGForeverABCallout1:GetAttribute("macrotext") == "/i INC Stables", "first AB callout wrong: " .. tostring(WSGForeverABCallout1:GetAttribute("macrotext")))
    check(WSGForeverABCallout20.msg == "HELP at Farm" and WSGForeverABCallout13.msg == "Lumber Mill SAFE", "AB callouts out of order")
    sim.zone, sim.instanceID = nil, nil
    sim.fire("PLAYER_ENTERING_WORLD")
    check(WSGForeverCallouts:IsShown() and not WSGForeverABCallouts:IsShown(), "back in Warsong Gulch the bars did not switch")
end)

-- Key bindings and the group version check ------------------------------------------

scenario("every key binding presses a button that exists and has a name in the menu", function()
    local f = assert(io.open(dir .. "/Bindings.xml")); local xml = f:read("*a"); f:close()
    local clicks, n = 0, 0
    for name in xml:gmatch('<Binding name="([^"]+)"') do
        n = n + 1
        check(_G["BINDING_NAME_" .. name] ~= nil, "no menu label for binding " .. name)
        local button = name:match("^CLICK (%S+):LeftButton$")
        if button then
            clicks = clicks + 1
            check(_G[button] ~= nil, "binding presses a button that does not exist: " .. button)
        end
    end
    check(n == 51 and clicks == 49, "expected 51 bindings with 49 button presses, got " .. n .. " and " .. clicks)
    check(BINDING_HEADER_WSGFOREVER == "WSGForever", "bindings header missing")
    check(WSGForeverCallout1.msg == "EFC Is Alliance Flag Room" and WSGForeverCallout26.msg:find("LOW") ~= nil, "callout buttons out of order")
    -- the carrier keys point at the carrier slot once someone is carrying
    sim.setCarrier(1, enemy)
    sim.run(1)
    check(WSGForeverBindPingEFC:GetAttribute("macrotext") == "/ping [@arena1] attack", "ping key not aimed at the enemy carrier")
    check(WSGForeverBindTargetEFC:GetAttribute("unit") == "arena1", "target key not aimed at the enemy carrier")
    -- pinging by name must not fall through to your current target when they are out of range
    say("The Alliance Flag was picked up by Cheat Jump!")
    check(WSGForeverBindPingFC:GetAttribute("macrotext") ==
        "/cleartarget\n/targetexact Cheat Jump\n/ping [@target,exists] assist\n/targetlasttarget", "ping-by-name macro wrong: " .. tostring(WSGForeverBindPingFC:GetAttribute("macrotext")))
end)

scenario("the group version check hears others, ignores itself, and mentions a newer version once", function()
    local peers = GK.modules.Peers
    check(peers.Newer("0.7.0", "0.6.0") and peers.Newer("v0.6.1", "0.6.0") and peers.Newer("0.6.0", "0.6.0-beta1"), "newer versions not recognised")
    check(not peers.Newer("0.6.0", "0.6.0") and not peers.Newer("0.5.9", "0.6.0") and not peers.Newer("0.6.0-beta1", "0.6.0")
        and not peers.Newer("dev", "0.6.0") and not peers.Newer("0.7.0", "dev"), "older, equal or unreadable versions counted as newer")
    sim.sent = {}
    sim.fire("GROUP_ROSTER_UPDATE")
    sim.run(40)
    sim.fire("GROUP_ROSTER_UPDATE")
    local mine = 0
    for _, m in ipairs(sim.sent) do if m.prefix == "WSGForeverV" and m.msg == "0.6.0" then mine = mine + 1 end end
    check(mine >= 1, "never announced its own version")
    sim.printed = {}
    sim.fire("CHAT_MSG_ADDON", "WSGForeverV", "0.6.0", "INSTANCE_CHAT", "Cheat Jump")
    sim.fire("CHAT_MSG_ADDON", "WSGForeverV", "0.7.0", "INSTANCE_CHAT", "Isaac Braums")
    sim.fire("CHAT_MSG_ADDON", "WSGForeverV", "0.8.0", "INSTANCE_CHAT", "Hella Slick")
    sim.fire("CHAT_MSG_ADDON", "WSGForeverV", "9.9.9", "INSTANCE_CHAT", "Test-Player") -- our own message coming back
    sim.fire("CHAT_MSG_ADDON", "SomeOtherAddon", "0.9.0", "INSTANCE_CHAT", "Nobody")
    local notices = 0
    for _, line in ipairs(sim.printed) do if line:find("newer WSGForever") then notices = notices + 1 end end
    check(notices == 1, "expected one newer-version notice, got " .. notices)
    check(peers:Summary():find("^3 other players") ~= nil, "summary wrong: " .. peers:Summary())
    sim.printed = {}
    SlashCmdList.WSGFOREVER("who")
    local listed = table.concat(sim.printed, " | ")
    check(listed:find("Hella Slick  0.8.0") and listed:find("You have version 0.6.0"), "who list wrong: " .. listed)
    sim.printed = {}
end)

-- Release pages show RELEASE_NOTES.md, which must be the newest version's notes.
current = "release notes"
count = count + 1
do
    local want = assert(loadfile(dir .. "/tests/release_notes.lua"))("check", dir)
    local f = io.open(dir .. "/RELEASE_NOTES.md")
    local have = f and f:read("*a")
    if f then f:close() end
    check(have == want, "RELEASE_NOTES.md is out of date: run lua5.1 tests/release_notes.lua")
end

if #failures > 0 then
    sim.realPrint(#failures .. " failure(s) in " .. count .. " scenarios:")
    for _, f in ipairs(failures) do sim.realPrint("  FAIL " .. f) end
    os.exit(1)
end
sim.realPrint("ok: " .. count .. " scenarios passed")
