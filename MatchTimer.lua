local _, GK = ...

-- A small clock for how long the current battleground has been running,
-- just left of the score at the top of the screen.

local Timer = {}
GK.RegisterModule("MatchTimer", Timer)

local KEY = "Match timer"
local frame, enteredAt

-- Seconds the match has run: the game's own count if it gives one, else
-- the time since you zoned in.
local function Elapsed()
    local ms = GetBattlefieldInstanceRunTime and GK.Plain(GetBattlefieldInstanceRunTime())
    if type(ms) == "number" and ms > 0 then return ms / 1000 end
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
    frame:SetScript("OnEvent", GK.Safe("Match timer event", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            enteredAt = GK.InBattleground() and (enteredAt or GetTime()) or nil
        end
        Place()
    end))
    local tick = 0
    frame:SetScript("OnUpdate", GK.Safe("Match timer", function(_, dt)
        tick = tick + dt
        if tick < 0.25 then return end
        tick = 0
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
