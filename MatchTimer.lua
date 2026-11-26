local _, GK = ...

-- How long the current battleground has been running, counted from the
-- gates opening, as a "Time Elapsed" line on the game's scoreboard.

local Timer = {}
GK.RegisterModule("MatchTimer", Timer)

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

-- Once there is a winner the clock stops, so the scoreboard you are left
-- looking at shows how long the match took, not how long you have stood there.
local final
local function Current()
    if not GK.InBattleground() then final = nil return nil end
    local winner = GetBattlefieldWinner and GK.Plain(GetBattlefieldWinner())
    if winner == nil then final = nil return Elapsed() end
    final = final or Elapsed()
    return final
end

-- The game's scoreboard used to end with "Time Elapsed"; this client's does
-- not. We put it back as one more tab hanging from the bottom edge, at the
-- right-hand end, on the scoreboard and on the results window at the end of
-- a match. It reads in whole minutes, as the game's did, and to the second
-- while the mouse is over it, without changing size. It is our own frame
-- hung on theirs: nothing of
-- the game's is changed, and clicking it does nothing.
local BOARDS = { "PVPMatchScoreboard", "PVPMatchResults" }
local LABEL = type(TIME_ELAPSED) == "string" and TIME_ELAPSED or "Time Elapsed:"
local PAD = 16 -- space either side of the words

local function IsWidget(v)
    return type(v) == "table" and v.GetObjectType ~= nil
end

-- One of the board's own team tabs, to take the looks and the height from.
local function BoardTab(board)
    local function dig(...)
        local at = board
        for _, key in ipairs({ ... }) do
            at = type(at) == "table" and at[key] or nil
        end
        return IsWidget(at) and at or nil
    end
    return dig("Tab3") or dig("Content", "TabContainer", "TabGroup", "Tab3")
        or dig("tab3") or dig("content", "tabContainer", "tabGroup", "tab3")
end

-- Draws an unselected tab on our frame by copying the three pieces of a real
-- one: what each shows, its size, and how it is pinned. False if the tab is
-- not built the way we expect, leaving nothing behind.
local function CopyTabArt(body, tab)
    local copies, made = {}, {}
    local function fail()
        for _, tex in ipairs(made) do tex:Hide() end
        return false
    end
    for _, key in ipairs({ "Left", "Right", "Middle" }) do
        local from = tab[key]
        if not (IsWidget(from) and from.GetAtlas and from.GetNumPoints) then return fail() end
        local tex = body:CreateTexture(nil, "BACKGROUND")
        made[#made + 1] = tex
        local atlas = from:GetAtlas()
        if type(atlas) == "string" and atlas ~= "" then
            tex:SetAtlas(atlas)
        else
            local file = from:GetTexture()
            if not file then return fail() end
            tex:SetTexture(file)
            tex:SetTexCoord(from:GetTexCoord())
        end
        local w, h = from:GetSize()
        if type(w) ~= "number" or type(h) ~= "number" then return fail() end
        tex:SetSize(w, h)
        copies[from] = tex
    end
    for from, tex in pairs(copies) do
        local n = from:GetNumPoints()
        if type(n) ~= "number" or n < 1 then return fail() end
        tex:ClearAllPoints()
        for i = 1, n do
            local point, rel, relPoint, x, y = from:GetPoint(i)
            local to = (rel == nil or rel == tab) and body or copies[rel]
            if not (to and type(point) == "string") then return fail() end
            tex:SetPoint(point, to, relPoint or point, x or 0, y or 0)
        end
    end
    return true
end

-- Where a real tab sits: how far its top edge is from the board's bottom
-- edge, how tall it is, and its size next to the board's (tabs can be drawn
-- at their own scale). Nil until the game has laid the tabs out.
local function TabPlacement(board, tab)
    if not tab then return nil end
    local function num(v)
        v = GK.Plain(v)
        return type(v) == "number" and v or nil
    end
    local top, bottom, height = num(tab:GetTop()), num(board:GetBottom()), num(tab:GetHeight())
    local ts, bs = num(tab:GetEffectiveScale()), num(board:GetEffectiveScale())
    if not (top and bottom and height and ts and bs) or bs <= 0 or ts <= 0 then return nil end
    local scale = ts / bs
    local drop = top * scale - bottom
    if drop < -40 or drop > 40 or height < 10 or height > 80 or scale < 0.5 or scale > 2 then return nil end
    return drop, height, scale
end

local boardLines = {}
local function AttachToBoards()
    for _, name in ipairs(BOARDS) do
        local board = _G[name]
        if IsWidget(board) and not boardLines[board] then
            -- The holder only keeps time; the body is what shows.
            local holder = CreateFrame("Frame", nil, board)
            boardLines[board] = holder
            holder:SetSize(1, 1)
            holder:SetPoint("TOPRIGHT", board, "BOTTOMRIGHT", -8, 0)
            local body = CreateFrame("Frame", "WSGForever" .. name .. "Time", holder)
            body:SetSize(180, 32)
            body:SetPoint("TOPRIGHT", board, "BOTTOMRIGHT", -8, 2)
            body:Hide()
            local text = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            -- From the left, so the words stay put when the number changes.
            text:SetPoint("LEFT", body, "LEFT", PAD, 2)

            -- Its own tab says where to sit; any board's tab will do for the looks.
            local tab = BoardTab(board)
            local dressed = false
            for _, other in ipairs({ board, _G.PVPMatchScoreboard or false, _G.PVPMatchResults or false }) do
                local model = not dressed and IsWidget(other) and BoardTab(other)
                if model then
                    local ok, done = pcall(CopyTabArt, body, model)
                    dressed = ok and done or false
                end
            end
            if not dressed then
                -- No tab to copy: a plain dark plate does the same job.
                local plate = body:CreateTexture(nil, "BACKGROUND")
                plate:SetAllPoints(body)
                plate:SetColorTexture(0, 0, 0, 0.7)
            end

            -- Whole minutes, or minutes and seconds under the mouse. The tab
            -- is sized once, for two digits of minutes, and only ever grows.
            local shown, hover, widest
            local function Write()
                if not shown then return end
                if not widest then
                    text:SetText(LABEL .. " 00 Min")
                    widest = text:GetStringWidth() or 120
                end
                text:SetText(LABEL .. " " .. (hover and Text(shown) or (math.floor(shown / 60) .. " Min")))
                widest = math.max(widest, text:GetStringWidth() or 0)
                body:SetWidth(widest + PAD * 2)
            end
            local function Leave() hover = false Write() end
            body:EnableMouse(true)
            body:SetScript("OnEnter", function() hover = true Write() end)
            body:SetScript("OnLeave", Leave)
            body:SetScript("OnHide", Leave)

            local tick, placedAt = 1, nil
            holder:SetScript("OnUpdate", GK.Safe("Scoreboard time", function(_, dt)
                tick = tick + dt
                if tick < 0.25 then return end
                tick = 0
                -- In a match its time; with the frames unlocked or in test
                -- mode, a sample to look at.
                shown = GK.db.matchTimer and (Current() or (GK.ShouldShowAll() and 754)) or nil
                if not shown then body:Hide() return end
                Write()
                -- Level with the real tabs, once they have been laid out.
                local ok, drop, tall, scale = pcall(TabPlacement, board, tab)
                if ok and drop and placedAt ~= drop then
                    placedAt = drop
                    body:SetScale(scale)
                    body:ClearAllPoints()
                    body:SetPoint("TOPRIGHT", board, "BOTTOMRIGHT", -8 / scale, drop / scale)
                    body:SetHeight(tall)
                end
                body:Show()
            end))
        end
    end
end

function Timer:Init()
    -- Nothing to see here: this frame only listens and keeps time.
    frame = CreateFrame("Frame")

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
    pcall(frame.RegisterEvent, frame, "START_TIMER") -- the game's own "battle begins in" countdown
    pcall(frame.RegisterEvent, frame, "PVP_MATCH_ACTIVE") -- the match itself has started
    frame:RegisterEvent("ADDON_LOADED") -- the scoreboard is loaded when first needed
    frame:SetScript("OnEvent", GK.Safe("Match timer event", function(_, event, msg, seconds)
        AttachToBoards()
        if event == "ADDON_LOADED" then return end
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
                if GK.Heard(msg, "begin") then GatesOpened() end
            end
        end
    end))
    local tick = 0
    frame:SetScript("OnUpdate", GK.Safe("Match timer", function(_, dt)
        tick = tick + dt
        if tick < 0.25 then return end
        tick = 0
        WatchPreparation()
        Current() -- notices the match ending even with the scoreboard closed
    end))
end

function Timer:Refresh()
    if not frame then return end
    AttachToBoards()
    local inBG = GK.InBattleground()
    if not inBG then enteredAt = nil elseif not enteredAt then enteredAt = GetTime() end
end
