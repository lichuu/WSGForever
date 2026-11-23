-- Development helper for WSGForever's screenshots (tools/screenshots/shoot.py
-- drives it with /run lines). Not shipped: it lives outside the addon folder.
--
--   WSGFShot.Stage(name)   shows that shot's captions (see CAPTIONS below)
--   WSGFShot.Clear()       removes every caption
--   WSGFShot.Dump()        saves where the addon's frames are on screen, in
--                          pixels, to WSGForeverShotsDB (written on /reload)
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
