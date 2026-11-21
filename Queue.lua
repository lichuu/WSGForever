local _, GK = ...

-- Battleground queue timers. While you wait: one row per queue with how long
-- you have waited, the game's estimate, and a bar that empties and turns from
-- green to red as the wait passes the estimate. When a queue pops: a
-- countdown of how long is left to enter. A ding on the pop is optional
-- (off by default), played on the master channel so muted effects don't hide it.

local Queue = {}
GK.RegisterModule("Queue", Queue)

local KEY = "Queue timers"
local SLOTS = 3
local WARN_AT = 5 -- seconds left to enter when the warning plays
local ROW_W, ROW_H, BAR_H = 240, 18, 4
local FLAT = "Interface\\Buttons\\WHITE8X8"
local frame
local rows = {}
local popped, warned, offerLength = {}, {}, {}

local function Ding()
    if not GK.db.queueSound then return end
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master")
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Some clients count these in milliseconds, others in seconds.
local function Seconds(fn, i, alwaysMs)
    local v = fn and GK.Plain(fn(i))
    if type(v) ~= "number" or v <= 0 then return nil end
    if alwaysMs or v > 1000 then v = v / 1000 end
    return v
end

-- Green while well inside the estimate, through yellow and orange, red past it.
local function Colour(frac)
    if frac < 0.5 then return 0.3, 0.85, 0.3 end
    if frac < 0.8 then return 0.95, 0.85, 0.2 end
    if frac < 1 then return 1, 0.55, 0.1 end
    return 0.95, 0.25, 0.2
end

-- What each slot holds: { kind = "queued" | "ready", name, waited, estimate, left }.
local function Read(i)
    local status, name = GetBattlefieldStatus(i)
    status, name = GK.Plain(status), GK.Plain(name) or "Battleground"
    if status == "queued" then
        return { kind = "queued", name = name,
            waited = Seconds(GetBattlefieldTimeWaited, i, true) or 0,
            estimate = Seconds(GetBattlefieldEstimatedWaitTime, i, true) }
    elseif status == "confirm" then
        return { kind = "ready", name = name, left = Seconds(GetBattlefieldPortExpiration, i) }
    end
end

local function MakeRow(i)
    local r = CreateFrame("Frame", nil, frame)
    r:SetSize(ROW_W, ROW_H + BAR_H + 2)
    r:SetPoint("TOP", 0, -(i - 1) * (ROW_H + BAR_H + 6))
    r.text = r:CreateFontString(nil, "OVERLAY")
    r.text:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    r.text:SetPoint("TOPLEFT")
    r.text:SetPoint("TOPRIGHT")
    r.text:SetJustifyH("LEFT")
    r.time = r:CreateFontString(nil, "OVERLAY")
    r.time:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    r.time:SetPoint("TOPRIGHT")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetColorTexture(0, 0, 0, 0.6)
    r.bg:SetPoint("BOTTOMLEFT")
    r.bg:SetPoint("BOTTOMRIGHT")
    r.bg:SetHeight(BAR_H)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetStatusBarTexture(FLAT)
    r.bar:SetAllPoints(r.bg)
    r.bar:SetMinMaxValues(0, 1)
    r:Hide()
    return r
end

local function Draw(r, q)
    if q.kind == "queued" then
        r.text:SetText("|cffffd100" .. q.name .. "|r")
        if q.estimate then
            local frac = q.waited / q.estimate
            r.time:SetText(Clock(q.waited) .. " |cff9a9a9a/ " .. Clock(q.estimate) .. "|r")
            r.bar:SetValue(math.max(0, 1 - frac))
            r.bar:SetStatusBarColor(Colour(frac))
        else
            r.time:SetText(Clock(q.waited))
            r.bar:SetValue(1)
            r.bar:SetStatusBarColor(0.45, 0.45, 0.5)
        end
    else
        local left, full = q.left, q.full or 90
        r.text:SetText("|cffffd100" .. q.name .. "|r is ready")
        local colour = left and left <= WARN_AT and "|cffff4f4f" or "|cff4fff4f"
        r.time:SetText(colour .. (left and Clock(left) or "now") .. "|r")
        r.bar:SetValue(left and math.min(1, left / full) or 1)
        r.bar:SetStatusBarColor(Colour(left and 1 - left / full or 0))
    end
    r:Show()
end

-- Sample rows while placing it.
local SAMPLE = {
    { kind = "queued", name = "Warsong Gulch", waited = 104, estimate = 150 },
    { kind = "ready", name = "Arathi Basin", left = 61, full = 90 },
}

local function Update()
    local any = false
    for i = 1, SLOTS do
        local q = Read(i)
        if q and q.kind == "ready" then
            if not popped[i] then
                popped[i] = true
                offerLength[i] = q.left
                Ding()
            end
            q.full = offerLength[i]
            if q.left and q.left <= WARN_AT and not warned[i] then
                warned[i] = true
                Ding()
                C_Timer.After(0.5, Ding)
                C_Timer.After(1, Ding)
            end
        else
            popped[i], warned[i], offerLength[i] = nil, nil, nil
        end
        if q and GK.db.queueAlert then
            Draw(rows[i], q)
            any = true
        else
            rows[i]:Hide()
        end
    end
    if not any and GK.ShouldShowAll() and GK.db.queueAlert then
        for i, q in ipairs(SAMPLE) do Draw(rows[i], q) end
        any = true
    end
    frame:SetShown(any)
end

function Queue:Init()
    frame = CreateFrame("Frame", "WSGForeverQueue", UIParent)
    frame:SetSize(ROW_W, SLOTS * (ROW_H + BAR_H + 6))
    frame:SetFrameStrata("HIGH")
    for i = 1, SLOTS do rows[i] = MakeRow(i) end
    GK.MakeMovable(frame, KEY, { "TOP", "TOP", 0, -190 })
    frame:Hide()

    -- A separate frame keeps the clock running while the display is hidden.
    local driver = CreateFrame("Frame")
    driver:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    driver:SetScript("OnEvent", GK.Safe("Queue event", Update))
    local tick = 0
    driver:SetScript("OnUpdate", GK.Safe("Queue", function(_, dt)
        tick = tick + dt
        if tick < 0.2 then return end
        tick = 0
        Update()
    end))
end

function Queue:Refresh()
    if frame then Update() end
end
