local _, GK = ...

-- When a battleground queue pops: a line showing how long is left to enter,
-- red for the last five seconds. Nothing shows while you are only queued.
-- A ding on the pop is optional (off by default), played on the master
-- channel so muted sound effects don't hide it.

local Queue = {}
GK.RegisterModule("Queue", Queue)

local KEY = "Queue pop"
local SLOTS = 3
local WARN_AT = 5 -- seconds left to enter when the warning plays
local frame
local rows = {}
local popped, warned = {}, {}

local function Ding()
    if not GK.db.queueSound then return end
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master")
end

local function Clock(seconds)
    seconds = math.max(0, math.ceil(seconds))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- The battleground and seconds left to enter, if this slot's queue has popped.
local function Offer(i)
    local status, name = GetBattlefieldStatus(i)
    if GK.Plain(status) ~= "confirm" then return nil end
    local left = GetBattlefieldPortExpiration and GK.Plain(GetBattlefieldPortExpiration(i))
    -- Some clients count in milliseconds.
    if type(left) == "number" and left > 1000 then left = left / 1000 end
    return GK.Plain(name) or "Battleground", type(left) == "number" and left > 0 and left or nil
end

local function Draw(row, name, left)
    local colour = left and left <= WARN_AT and "|cffff4f4f" or "|cff4fff4f"
    row:SetText(string.format("|cffffd100%s|r is ready: %s%s|r", name, colour, left and Clock(left) or "now"))
    row:Show()
end

local function Update()
    local any = false
    for i = 1, SLOTS do
        local name, left = Offer(i)
        if name then
            if not popped[i] then popped[i] = true Ding() end
            if left and left <= WARN_AT and not warned[i] then
                warned[i] = true
                Ding()
                C_Timer.After(0.5, Ding)
                C_Timer.After(1, Ding)
            end
        else
            popped[i], warned[i] = nil, nil
        end
        if name and GK.db.queueAlert then
            Draw(rows[i], name, left)
            any = true
        else
            rows[i]:Hide()
        end
    end
    -- A sample while placing it.
    if not any and GK.ShouldShowAll() and GK.db.queueAlert then
        Draw(rows[1], "Warsong Gulch", 85)
        any = true
    end
    frame:SetShown(any)
end

function Queue:Init()
    frame = CreateFrame("Frame", "WSGForeverQueue", UIParent)
    frame:SetSize(320, SLOTS * 24)
    frame:SetFrameStrata("HIGH")
    for i = 1, SLOTS do
        local row = frame:CreateFontString(nil, "OVERLAY")
        row:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
        row:SetPoint("TOP", 0, -(i - 1) * 24)
        row:Hide()
        rows[i] = row
    end
    -- Below the flag timers and the enemy carrier low banner.
    GK.MakeMovable(frame, KEY, { "TOP", "TOP", 0, -330 })
    frame:Hide()

    -- A separate frame keeps the countdown running while the display is hidden.
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
