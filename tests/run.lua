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
noErrors()
sim.run(8)

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
    for _, cmd in ipairs({ "", "test", "test", "unlock", "lock", "scale", "scale map 130", "scale callouts 110",
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

if #failures > 0 then
    sim.realPrint(#failures .. " failure(s) in " .. count .. " scenarios:")
    for _, f in ipairs(failures) do sim.realPrint("  FAIL " .. f) end
    os.exit(1)
end
sim.realPrint("ok: " .. count .. " scenarios passed")
