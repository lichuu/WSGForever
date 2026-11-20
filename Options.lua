local _, GK = ...

-- A minimap button and the addon's window, which has two tabs: settings and
-- match history. The settings page also shows under Options > AddOns.
-- Everything on it is also a /fc command; both change the same saved settings.

local Options = {}
GK.RegisterModule("Options", Options)

local ICON = "Interface\\Icons\\INV_Misc_Rune_07"
local FLAT = "Interface\\Buttons\\WHITE8X8"
local COL_W, ROW_H, PAD = 296, 38, 18
local PAGE_W = PAD + COL_W + 20 + COL_W + PAD

-- Settings in the order shown: { setting, name, one line, tooltip }.
local SECTIONS = {
    { "Flag carriers", {
        { "carriers", "Carrier health and drop timer", "Health and a drop countdown by the names.",
            "Health next to the carrier names, and a countdown when a flag is dropped." },
        { "moveBlizzCarriers", "Carrier frames beside the flags", "The game's carrier frames, by the score.",
            "Moves the game's carrier frames up next to the score. Reload to undo." },
        { "fcNames", "Clickable carrier names", "Our own carrier names. Click to target.",
            "WSGForever's own carrier names. Click one to target the carrier." },
        { "efcLowAlert", "Enemy carrier low warning", "A red banner under 50% health.",
            "A red banner when the enemy flag carrier is under 50% health." },
        { "raidFlag", "Flag icon on raid frames", "Marks your carrier in the raid frames.",
            "Marks your team's carrier in the raid frames." },
    } },
    { "Battleground", {
        { "callouts", "Callout bar", "One-click callouts to battleground chat.",
            "One-click location callouts to battleground chat." },
        { "enemies", "Enemy frames", "Enemy team with class, health and range.",
            "The enemy team with class, health and range. Left click targets, right click focuses, middle click pings." },
        { "rezTimer", "Resurrection timer", "Countdown to the next graveyard wave.",
            "Countdown to the next graveyard wave, in every battleground." },
        { "autoAssist", "Auto assist", "Raid assist for everyone when you lead.",
            "Gives everyone raid assist when you lead a battleground." },
        { "battleMap", "Battlefield map dots", "Teammates as bigger class-coloured dots.",
            "Shows teammates on the battlefield map as bigger dots in their class colours. /fc scale map and /fc scale mapdots change the sizes." },
        { "history", "Record match history", "Keeps a record of every finished battleground.",
            "Keeps the result, score and your scoreboard line for every battleground you finish. /fc history shows them." },
        { "minimapButton", "Minimap button", "The button that opens this page.",
            "The minimap button that opens this page. /fc minimap brings it back." },
    } },
}

local window, minimap
local pages = {} -- every copy of the page: the window's and the game options'

-- The page ---------------------------------------------------------------------

local function MakeCheck(page, parent, key, name, desc, full)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(COL_W, ROW_H - 4)
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetSize(18, 18)
    edge:SetPoint("TOPLEFT", 0, -2)
    edge:SetColorTexture(0.42, 0.42, 0.46, 1)
    local box = b:CreateTexture(nil, "BORDER")
    box:SetPoint("TOPLEFT", edge, 1, -1)
    box:SetPoint("BOTTOMRIGHT", edge, -1, 1)
    box:SetColorTexture(0.04, 0.04, 0.05, 1)
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b.mark:SetSize(24, 24)
    b.mark:SetPoint("CENTER", edge)
    local title = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", edge, "TOPRIGHT", 9, -1)
    title:SetText(name)
    local sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    sub:SetWidth(COL_W - 28)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    sub:SetText(desc)
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("TOPLEFT", -4, 2)
    hover:SetPoint("BOTTOMRIGHT", 0, -2)
    hover:SetColorTexture(1, 1, 1, 0.05)
    b:SetScript("OnClick", function()
        GK.db[key] = not GK.db[key]
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        GK.Refresh()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(name)
        GameTooltip:AddLine(full or desc, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b.key = key
    page.checks[#page.checks + 1] = b
    return b
end

local function MakeHeader(parent, text, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", x, y - 17)
    line:SetWidth(width)
end

local function MakeButton(parent, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetScript("OnClick", function()
        onClick()
        Options:Sync()
    end)
    return b
end

-- Builds the page inside parent, starting at (x, y). Returns its height.
local function BuildPage(parent, x, y)
    local page = { checks = {} }
    local top, lowest = y, y
    for col, section in ipairs(SECTIONS) do
        local cx, cy = x + (col - 1) * (COL_W + 20), top
        MakeHeader(parent, section[1], cx, cy, COL_W)
        cy = cy - 28
        for _, item in ipairs(section[2]) do
            MakeCheck(page, parent, item[1], item[2], item[3], item[4]):SetPoint("TOPLEFT", cx, cy)
            cy = cy - ROW_H
        end
        lowest = math.min(lowest, cy)
    end

    y = lowest - 10
    local width = COL_W * 2 + 20
    MakeHeader(parent, "Layout", x, y, width)
    y = y - 30
    local third = (width - 16) / 3
    page.move = MakeButton(parent, third, function() GK.SetLocked(not GK.db.locked) end)
    page.move:SetPoint("TOPLEFT", x, y)
    page.test = MakeButton(parent, third, function() GK.SetTestMode(not GK.testMode) end)
    page.test:SetPoint("LEFT", page.move, "RIGHT", 8, 0)
    local reset = MakeButton(parent, third, GK.ResetLayout)
    reset:SetText("Reset positions and sizes")
    reset:SetPoint("LEFT", page.test, "RIGHT", 8, 0)
    y = y - 30
    local history = MakeButton(parent, third, function() Options:Open("history") end)
    history:SetText("Match history")
    history:SetPoint("TOPLEFT", x, y)
    y = y - 32
    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", x, y)
    hint:SetWidth(width)
    hint:SetJustifyH("LEFT")
    hint:SetText("While moving, drag the blue boxes and scroll on one to resize it. Preview shows everything outside a battleground. Type /fc for the same settings as commands.")
    y = y - 30

    pages[#pages + 1] = page
    return top - y
end

function Options:Sync()
    if minimap then minimap:SetShown(GK.db.minimapButton) end
    for _, page in ipairs(pages) do
        for _, c in ipairs(page.checks) do c.mark:SetShown(GK.db[c.key] and true or false) end
        page.move:SetText(GK.db.locked and "Move and resize frames" or "Lock frames")
        page.test:SetText(GK.testMode and "End preview" or "Preview")
    end
end

-- Its own window -----------------------------------------------------------

local function BuildWindow()
    local f = CreateFrame("Frame", "WSGForeverOptions", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.06, 0.07, 0.96)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    f:SetPoint("CENTER", 0, 40)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "WSGForeverOptions") -- Escape closes it

    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(1, 1, 1, 0.05)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(34)
    local icon = f:CreateTexture(nil, "OVERLAY")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", PAD, -8)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("WSGForever")

    -- A plain close button: the game's template one misbehaved here.
    local close = CreateFrame("Button", nil, f)
    close:SetSize(34, 34)
    close:SetPoint("TOPRIGHT", -1, -1)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("x")
    local hot = close:CreateTexture(nil, "HIGHLIGHT")
    hot:SetAllPoints()
    hot:SetColorTexture(0.8, 0.15, 0.1, 0.6)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Two tabs, each with its own body below the title bar.
    local body = { settings = CreateFrame("Frame", nil, f), history = CreateFrame("Frame", nil, f) }
    for _, b in pairs(body) do
        b:SetPoint("TOPLEFT", 0, -35)
        b:SetPoint("BOTTOMRIGHT")
    end
    local settingsHeight = BuildPage(body.settings, PAD, -16) + 16
    local historyHeight = GK.modules.History:BuildView(body.history, PAD, -16) + 16
    f:SetSize(PAGE_W, 35 + math.max(settingsHeight, historyHeight) + 8)

    local tabs = {}
    local function MakeTab(name, label, after)
        local t = CreateFrame("Button", nil, f)
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t.text:SetPoint("CENTER")
        t.text:SetText(label)
        t:SetSize(t.text:GetStringWidth() + 24, 34)
        t:SetPoint("LEFT", after, "RIGHT", after == title and 28 or 0, 0)
        t.line = t:CreateTexture(nil, "OVERLAY")
        t.line:SetColorTexture(1, 0.82, 0, 1)
        t.line:SetHeight(2)
        t.line:SetPoint("BOTTOMLEFT", 8, 4)
        t.line:SetPoint("BOTTOMRIGHT", -8, 4)
        t:SetScript("OnClick", function() f.Select(name) end)
        tabs[name] = t
        return t
    end
    MakeTab("history", "Match history", MakeTab("settings", "Settings", title))

    function f.Select(name)
        f.tab = name
        for n, b in pairs(body) do b:SetShown(n == name) end
        for n, t in pairs(tabs) do
            t.line:SetShown(n == name)
            if n == name then t.text:SetTextColor(1, 1, 1) else t.text:SetTextColor(0.6, 0.6, 0.65) end
        end
        Options:Sync()
        if name == "history" then GK.modules.History:Update() end
    end
    f.Select("settings")
    return f
end

-- Under Options > AddOns ---------------------------------------------------

local category
local function RegisterWithGame()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    panel:Hide()
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PAD, -16)
    title:SetText("WSGForever")
    BuildPage(panel, PAD, -52)
    panel:SetScript("OnShow", function() Options:Sync() end)
    category = Settings.RegisterCanvasLayoutCategory(panel, "WSGForever")
    Settings.RegisterAddOnCategory(category)
end

-- Shows the window on a tab ("settings" or "history").
function Options:Open(tab)
    if not window then window = BuildWindow() end
    window:Show()
    window.Select(tab or "settings")
end

-- Opens on that tab, or closes the window if it is already showing it.
function Options:Toggle(tab)
    tab = tab or "settings"
    if window and window:IsShown() and window.tab == tab then
        window:Hide()
    else
        self:Open(tab)
    end
end

-- Minimap button ------------------------------------------------------------

local function PlaceOnMinimap()
    local angle = math.rad(GK.db.minimapAngle or 205)
    local radius = Minimap:GetWidth() / 2 + 6
    minimap:ClearAllPoints()
    minimap:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    GK.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    PlaceOnMinimap()
end

local function BuildMinimapButton()
    local b = CreateFrame("Button", "WSGForeverMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            GK.SetLocked(not GK.db.locked)
            Options:Sync()
        else
            Options:Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("WSGForever")
        GameTooltip:AddLine("Left click: settings", 1, 1, 1)
        GameTooltip:AddLine("Right click: move or lock frames", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
        local peers = GK.modules.Peers
        if peers then GameTooltip:AddLine(peers:Summary(), 0.6, 0.6, 0.65) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

BINDING_NAME_WSGFOREVER_SETTINGS = "Open settings"
BINDING_NAME_WSGFOREVER_HISTORY = "Open match history"

-- A launcher for info bars and minimap-button collectors, when one is installed.
local function RegisterLauncher()
    local stub = _G.LibStub
    local ldb = stub and stub("LibDataBroker-1.1", true)
    if not ldb then return end
    ldb:NewDataObject("WSGForever", {
        type = "launcher", icon = ICON, text = "WSGForever",
        OnClick = function(_, button)
            if button == "RightButton" then Options:Toggle("history") else Options:Toggle("settings") end
        end,
        OnTooltipShow = function(tip)
            tip:AddLine("WSGForever")
            tip:AddLine("Left click: settings", 1, 1, 1)
            tip:AddLine("Right click: match history", 1, 1, 1)
        end,
    })
end

function Options:Init()
    minimap = BuildMinimapButton()
    PlaceOnMinimap()
    pcall(RegisterLauncher)
    local ok, err = pcall(RegisterWithGame)
    if not ok then GK.Print("|cffff4f4fCouldn't add settings to the game options:|r " .. tostring(err)) end
end

function Options:Refresh()
    self:Sync()
end
