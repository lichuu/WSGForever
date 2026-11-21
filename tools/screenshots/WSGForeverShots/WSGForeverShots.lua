-- Development helper for WSGForever's screenshots (tools/screenshots/shoot.py
-- drives it with /run lines). Not shipped: it lives outside the addon folder.
--
--   WSGFShot.Caption(n, frame, point, relPoint, x, y, title, text)
--       a real game tooltip next to a named frame, as a caption
--   WSGFShot.Clear()             removes every caption
--   WSGFShot.Dump(names)         saves where those frames are on screen, in
--                                pixels, to WSGForeverShotsDB (written on /reload)

WSGFShot = {}
local captions = {}

function WSGFShot.Caption(n, frameName, point, relPoint, x, y, title, text)
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

function WSGFShot.Dump(names)
    WSGForeverShotsDB = { rects = {}, at = time() }
    for _, name in ipairs(names) do
        local f = _G[name]
        if f and f.IsVisible and f:IsVisible() then WSGForeverShotsDB.rects[name] = Rect(f) end
    end
    print("WSGFShot: saved " .. #names .. " frames, /reload to write them")
end
