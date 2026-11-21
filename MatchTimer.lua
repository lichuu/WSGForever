local _, GK = ...

-- A small clock for how long the current battleground has been running,
-- counted from the gates opening, just left of the score at the top of the
-- screen.

local Timer = {}
GK.RegisterModule("MatchTimer", Timer)

local KEY = "Match timer"
local frame, enteredAt

-- The game's own count for this battleground, in seconds. It starts when
-- the battleground is created, so it includes the wait behind the gates.
local function GameCount()
    local ms = GetBattlefieldInstanceRunTime and GK.Plain(GetBattlefieldInstanceRunTime())
    if type(ms) == "number" and ms > 0 then return ms / 1000 end
end

local function Map()
    return GK.Plain((GetInstanceInfo())) or "?"
end

-- The gates opened: time from now. Saved, so a reload mid-match keeps it.
-- How far the game's count had got is remembered per battleground, to work
-- out the start when you join a match that is already running.
-- inSeconds: how long until they open, when the game announces it ahead.
local function GatesOpened(inSeconds)
    inSeconds = inSeconds or 0
    local at = time() + inSeconds
    -- The game's countdown and the chat line both report the same opening:
    -- whichever came first stands.
    local start = GK.db.matchStart
    if start and start.map == Map() and math.abs(start.at - at) < 15 then return end
    GK.db.matchStart = { at = at, map = Map() }
    local count = GameCount()
    if count then
        GK.db.gateWait = GK.db.gateWait or {}
        GK.db.gateWait[Map()] = count + inSeconds
    end
end

-- The game's own answer, where it has one: how long the match itself has
-- been active, which is zero behind the gates and right on a late join.
local function ServerDuration()
    local api = C_PvP
    if not (api and api.GetActiveMatchDuration) then return nil end
    local function ask(fn)
        if not fn then return nil end
        local ok, v = pcall(fn)
        return ok and GK.Plain(v) or nil
    end
    local state = ask(api.GetActiveMatchState)
    if type(state) == "number" then
        -- 1 and 2: waiting to start. 3 and 4: under way. 5: finished.
        if state == 1 or state == 2 then return 0 end
        if state < 3 or state > 5 then return nil end
    elseif not (ask(api.IsMatchActive) or ask(api.IsMatchComplete)) then
        return nil
    end
    local seconds = ask(api.GetActiveMatchDuration)
    if type(seconds) == "number" and seconds >= 0 and seconds < 86400 then return seconds end
end

-- The Preparation buff is on you while you wait behind the gates and is
-- taken off the moment they open, which makes it one more start signal.
local PREPARATION = 44521
local hadPreparation = false
local function WatchPreparation()
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not get or not GK.InBattleground() then hadPreparation = false return end
    local ok, aura = pcall(get, PREPARATION)
    local has = ok and aura ~= nil
    if hadPreparation and not has then GatesOpened() end
    hadPreparation = has
end

-- Seconds since the gates opened.
local function Elapsed()
    local server = ServerDuration()
    if server then return server end
    local start = GK.db.matchStart
    if start and start.map == Map() then return math.max(0, time() - start.at) end
    local count = GameCount()
    if count then
        -- Joined after the gates opened, or they haven't yet: take the wait
        -- off the game's count (two minutes if we have never measured it).
        local wait = GK.db.gateWait and GK.db.gateWait[Map()]
        if wait then return math.max(0, count - wait) end
        return count < 125 and 0 or count
    end
    if enteredAt then return GetTime() - enteredAt end
end

local function Text(seconds)
    seconds = math.floor(seconds)
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Until it has been dragged somewhere, it sits just left of the score.
local function Place()
    if GK.db.positions[KEY] then return end
    local score = _G.UIWidgetTopCenterContainerFrame
    if score and score:IsShown() then
        frame:ClearAllPoints()
        frame:SetPoint("RIGHT", score, "LEFT", -10, 0)
    end
end

function Timer:Init()
    frame = CreateFrame("Frame", "WSGForeverMatchTimer", UIParent)
    frame:SetSize(64, 20)
    frame:SetFrameStrata("LOW")
    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    frame.text:SetPoint("RIGHT")
    frame.text:SetTextColor(1, 1, 1)
    GK.MakeMovable(frame, KEY, { "TOP", "TOP", -150, -22 })

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UPDATE_UI_WIDGET")
    frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
    pcall(frame.RegisterEvent, frame, "START_TIMER") -- the game's own "battle begins in" countdown
    pcall(frame.RegisterEvent, frame, "PVP_MATCH_ACTIVE") -- the match itself has started
    frame:SetScript("OnEvent", GK.Safe("Match timer event", function(_, event, msg, seconds)
        if event == "PLAYER_ENTERING_WORLD" then
            enteredAt = GK.InBattleground() and (enteredAt or GetTime()) or nil
            -- Out of the battleground: the next match starts its own clock.
            if not GK.InBattleground() then GK.db.matchStart = nil end
        elseif event == "PVP_MATCH_ACTIVE" then
            if GK.InBattleground() then GatesOpened() end
            return
        elseif event == "START_TIMER" then
            seconds = GK.Plain(seconds)
            if type(seconds) == "number" and seconds >= 0 and seconds < 600 and GK.InBattleground() then
                GatesOpened(seconds)
            end
            return
        elseif event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
            -- "Let the battle for Warsong Gulch begin!" / "The battle has begun!"
            msg = GK.Plain(msg)
            if type(msg) == "string" and GK.InBattleground() then
                local lower = msg:lower()
                if lower:find("begun") or lower:find("begin!") then GatesOpened() end
            end
            return
        end
        Place()
    end))
    local tick = 0
    frame:SetScript("OnUpdate", GK.Safe("Match timer", function(_, dt)
        tick = tick + dt
        if tick < 0.25 then return end
        tick = 0
        WatchPreparation()
        local seconds = GK.InBattleground() and Elapsed()
        -- A sample outside a battleground, so it can be placed.
        frame.text:SetText(seconds and Text(seconds) or "12:34")
    end))
end

function Timer:Refresh()
    if not frame then return end
    local inBG = GK.InBattleground()
    if not inBG then enteredAt = nil elseif not enteredAt then enteredAt = GetTime() end
    frame:SetShown(GK.db.matchTimer and (inBG or GK.ShouldShowAll()) and true or false)
    Place()
end
