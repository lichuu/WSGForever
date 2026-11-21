local _, GK = ...

-- When a battleground queue pops: a ding, played on the master channel so it
-- is heard with sound effects muted, a big countdown of how long is left to
-- enter, and warning dings with five seconds to go.

local Queue = {}
GK.RegisterModule("Queue", Queue)

local KEY = "Queue pop"
local WARN_AT = 5 -- seconds left when the warning dings play
local frame
local popped = {}  -- battleground slot -> true while its entry is offered
local warned = {}  -- slot -> true once the warning has played

local function Ding()
    if not GK.db.queueSound then return end
    local id = SOUNDKIT and SOUNDKIT.READY_CHECK or 8960
    pcall(PlaySound, id, "Master")
end

-- The slot with an entry offer open, its battleground and seconds left.
local function Offer()
    local count = (GetMaxBattlefieldID and GetMaxBattlefieldID()) or 3
    for i = 1, count do
        local status, name = GetBattlefieldStatus(i)
        if GK.Plain(status) == "confirm" then
            local left = GetBattlefieldPortExpiration and GK.Plain(GetBattlefieldPortExpiration(i))
            -- Some clients count in milliseconds.
            if type(left) == "number" and left > 1000 then left = left / 1000 end
            return i, GK.Plain(name) or "Battleground", type(left) == "number" and left or nil
        end
    end
end

local function Check()
    local count = (GetMaxBattlefieldID and GetMaxBattlefieldID()) or 3
    for i = 1, count do
        local open = GK.Plain(GetBattlefieldStatus(i)) == "confirm"
        if open and not popped[i] and GK.db.queueAlert then Ding() end
        if not open then warned[i] = nil end
        popped[i] = open or nil
    end
    Queue:Refresh()
end

function Queue:Init()
    frame = CreateFrame("Frame", "WSGForeverQueuePop", UIParent)
    frame:SetSize(320, 44)
    frame:SetFrameStrata("HIGH")
    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
    frame.text:SetPoint("CENTER")
    GK.MakeMovable(frame, KEY, { "TOP", "TOP", 0, -190 })

    frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", GK.Safe("Queue event", Check))
    local tick = 0
    frame:SetScript("OnUpdate", GK.Safe("Queue", function(_, dt)
        tick = tick + dt
        if tick < 0.1 then return end
        tick = 0
        local slot, name, left = Offer()
        if not slot then
            -- A sample while placing it.
            frame.text:SetText(GK.ShouldShowAll() and "|cffffd100Warsong Gulch|r is ready: |cff4fff4f85|r" or "")
            return
        end
        if left and left <= WARN_AT and not warned[slot] then
            warned[slot] = true
            Ding()
            C_Timer.After(0.5, Ding)
            C_Timer.After(1, Ding)
        end
        local colour = left and left <= WARN_AT and "|cffff4f4f" or "|cff4fff4f"
        frame.text:SetText(string.format("|cffffd100%s|r is ready: %s%s|r", name, colour, left and tostring(math.ceil(left)) or "now"))
    end))
    Check()
end

function Queue:Refresh()
    if not frame then return end
    local offered = Offer() ~= nil
    frame:SetShown(GK.db.queueAlert and (offered or GK.ShouldShowAll()) and true or false)
end
