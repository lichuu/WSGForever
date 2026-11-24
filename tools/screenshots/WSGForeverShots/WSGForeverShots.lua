-- Development helper for WSGForever's screenshots (tools/screenshots/shoot.py
-- drives it with /run lines). Not shipped: it lives outside the addon folder.
--
--   WSGFShot.Stage(name)   shows that shot's captions (see CAPTIONS below)
--   WSGFShot.Clear()       removes every caption
--   WSGFShot.Dump()        saves where the addon's frames are on screen, in
--                          pixels, to WSGForeverShotsDB (written on /reload)
--
-- The scoreboard shot stages itself (see the end of this file): it needs a
-- real match, and nobody should be typing into one.
--
-- Captions live here rather than in shoot.py because a chat line holds at
-- most 255 characters, so the driver only sends short calls.

-- The frames shoot.py crops around.
local FRAMES = { "WSGForeverEnemies", "WSGForeverCallouts", "WSGForeverABCallouts",
    "WSGForeverQueue", "WSGForeverOptions", "WSGForeverFlagSpawn", "WSGForeverEFCLow",
    "WSGForeverRezTimer", "UIWidgetTopCenterContainerFrame", "BattlefieldMapFrame" }

-- Per shot: { frame, point, relPoint, x, y, title, text }.
local CAPTIONS = {
    ["enemy-frames"] = { { "WSGForeverEnemies", "TOPRIGHT", "TOPLEFT", -14, -30, "Enemy frames",
        "Class, health, range and who is dead. Left click targets, right click focuses, middle click pings." } },
    ["timers"] = { { "WSGForeverFlagSpawn", "RIGHT", "LEFT", -60, 10, "Flag and rez timers",
        "A countdown when a flag is dropped and when the flags spawn again, and when the next graveyard wave lands. A red banner when the enemy carrier is low." } },
    ["callout-bar"] = { { "WSGForeverCallouts", "BOTTOMRIGHT", "TOPRIGHT", 0, 10, "Callout bar",
        "One click tells your team where the enemy flag carrier is." } },
    ["ab-callouts"] = { { "WSGForeverABCallouts", "BOTTOMRIGHT", "TOPRIGHT", 0, 10, "Arathi Basin callouts",
        "Incoming, big incoming, safe and help for every node, each with its own icon." } },
    ["queue-timers"] = { { "WSGForeverQueue", "RIGHT", "LEFT", -16, 0, "Queue pop",
        "How long is left to enter when a battleground queue pops." } },
    ["scoreboard-time"] = { { "WSGForeverPVPMatchScoreboardTime", "TOPRIGHT", "TOPLEFT", -12, 0, "Time Elapsed on the scoreboard",
        "Back where it used to be, counted from the gates opening. Hover for the seconds." } },
}

WSGFShot = {}
local captions = {}

local function Caption(n, frameName, point, relPoint, x, y, title, text)
    local anchor = _G[frameName]
    if not anchor then print("WSGFShot: no frame " .. tostring(frameName)) return end
    local t = captions[n]
    if not t then
        t = CreateFrame("GameTooltip", "WSGFShotCaption" .. n, UIParent, "GameTooltipTemplate")
        t:SetFrameStrata("TOOLTIP")
        captions[n] = t
    end
    t:SetOwner(UIParent, "ANCHOR_NONE")
    t:ClearAllPoints()
    t:SetPoint(point, anchor, relPoint, x or 0, y or 0)
    t:SetText(title, 1, 0.82, 0)
    if text then t:AddLine(text, 1, 1, 1, true) end
    t:SetMinimumWidth(0)
    t:Show()
end

function WSGFShot.Stage(name)
    WSGFShot.Clear()
    for n, c in ipairs(CAPTIONS[name] or {}) do Caption(n, unpack(c)) end
end

function WSGFShot.Clear()
    for _, t in pairs(captions) do t:Hide() end
end

-- Screen rectangle in pixels, top-left origin: { left, top, right, bottom }.
local function Rect(f)
    local l, b, w, h = f:GetRect()
    if not l then return nil end
    local _, physH = GetPhysicalScreenSize()
    local k = f:GetEffectiveScale() * physH / (GetScreenHeight() * UIParent:GetEffectiveScale())
    return { math.floor(l * k), math.floor(physH - (b + h) * k), math.ceil((l + w) * k), math.ceil(physH - b * k) }
end

function WSGFShot.Dump()
    WSGForeverShotsDB = { rects = {}, at = time() }
    for _, name in ipairs(FRAMES) do
        local f = _G[name]
        if f and f.IsVisible and f:IsVisible() then WSGForeverShotsDB.rects[name] = Rect(f) end
    end
    print("WSGFShot: saved frame positions, /reload to write them")
end

-- Tidy the screen for a shot: hide your own unit frame, and show the version
-- a release would show instead of "development copy".
function WSGFShot.Tidy(version)
    if PlayerFrame then PlayerFrame:SetAlpha(0) end
    local function walk(f)
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetText and r:GetText() == "development copy" then r:SetText("version " .. version) end
        end
        for _, c in ipairs({ f:GetChildren() }) do walk(c) end
    end
    if WSGForeverOptions then walk(WSGForeverOptions) end
end

-- A believable rez countdown for the preview, which otherwise reads "?".
function WSGFShot.Rez(text)
    local f = WSGForeverRezTimer
    if f then f:SetScript("OnUpdate", nil) f.text:SetText(text) end
end

-- The scoreboard's Time Elapsed tab ------------------------------------------
-- It can only be shot in a real match, with players on the board, so this
-- one needs no typing: whenever the tab is showing in a battleground, two
-- minutes or more in and while you are alive, it captions the tab, fades the
-- enemy list beside it, and has the game take its own screenshot (lossless,
-- in the game's Screenshots folder). It stops after MAX_SHOTS; to arm it
-- again: /run WSGForeverShotsDB.autoShots = 0
local MAX_SHOTS, GAP = 4, 45
local auto = CreateFrame("Frame")
local tick, stagedAt, shotAt, lastShot, undo = 0, nil, nil, -GAP, nil

local function Minutes(tab)
    for _, r in ipairs({ tab:GetRegions() }) do
        local text = r.GetText and r:GetText()
        local n = type(text) == "string" and text:match("(%d+) Min")
        if n then return tonumber(n) end
    end
end

local function Alive()
    local ok, dead = pcall(function() return UnitIsDeadOrGhost("player") and true or false end)
    return ok and not dead
end

local function Unstage()
    WSGFShot.Clear()
    if undo then pcall(undo) end
    stagedAt, shotAt, undo = nil, nil, nil
end

local function Step()
    WSGForeverShotsDB = WSGForeverShotsDB or {}
    local db = WSGForeverShotsDB
    local tab = _G.WSGForeverPVPMatchScoreboardTime
    local _, kind = IsInInstance()
    local showing = kind == "pvp" and tab and tab:IsVisible()
    local now = GetTime()
    if not stagedAt then
        if showing and (db.autoShots or 0) < MAX_SHOTS and now - lastShot > GAP
            and (Minutes(tab) or 0) >= 2 and Alive() then
            -- Out of the way for a second: the enemy list beside the tab, and
            -- your target and focus frames, which often sit just below it.
            local format, quality = GetCVar("screenshotFormat"), GetCVar("screenshotQuality")
            local faded = {}
            for _, name in ipairs({ "WSGForeverEnemies", "TargetFrame", "FocusFrame" }) do
                local f = _G[name]
                if f and f.GetAlpha then faded[f] = f:GetAlpha() f:SetAlpha(0) end
            end
            undo = function()
                for f, alpha in pairs(faded) do f:SetAlpha(alpha) end
                if format then SetCVar("screenshotFormat", format) end
                if quality then SetCVar("screenshotQuality", quality) end
            end
            WSGFShot.Stage("scoreboard-time")
            stagedAt = now
        end
    elseif not showing then
        Unstage() -- closed before the shot: nothing taken, nothing counted
    elseif not shotAt then
        if now - stagedAt > 0.6 then
            SetCVar("screenshotFormat", "tga")
            SetCVar("screenshotQuality", "10")
            Screenshot()
            shotAt, lastShot = now, now
            db.autoShots = (db.autoShots or 0) + 1
        end
    elseif now - shotAt > 1.2 then
        Unstage()
    end
end

auto:SetScript("OnUpdate", function(_, dt)
    tick = tick + dt
    if tick < 0.1 then return end
    tick = 0
    local ok, err = pcall(Step)
    if not ok then
        Unstage()
        auto:SetScript("OnUpdate", nil)
        print("WSGFShot: scoreboard shot turned itself off: " .. tostring(err))
    end
end)
