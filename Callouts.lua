local _, GK = ...

local ALLY_ICON, HORDE_ICON, MID_ICON, FLAG_ICON = 132486, 132485, 136212, 133217
local BLUE, RED, GOLD, CYAN = "|cff4fa3ff", "|cffff4f4f", "|cffffd100", "|cff61f7ff"

-- Same spots and messages as the "!WSG Callout Bar (Both Factions)" WeakAura.
local SPOTS = {
    { "FR", "Flag Room" }, { "TUN", "Tunnel" }, { "TOT", "TOT (Top of Tunnel)" },
    { "ROOF", "Roof/Banana" }, { "RAMP", "Ramp" }, { "GY", "GY" },
    { "LEAF", "Leaf Hut" }, { "ZERK", "Zerk Hut" }, { "CON", "Connector" },
    { "2ND", "2nd Lvl" },
}

local rows = { {}, {}, {} }
for _, s in ipairs(SPOTS) do
    rows[1][#rows[1] + 1] = { label = BLUE .. s[1], icon = ALLY_ICON, msg = "EFC Is Alliance " .. s[2], bind = "Callout: Alliance " .. s[2] }
    rows[2][#rows[2] + 1] = { label = RED .. s[1], icon = HORDE_ICON, msg = "EFC Is Horde " .. s[2], bind = "Callout: Horde " .. s[2] }
end
rows[3] = {
    { label = CYAN .. "MID", icon = MID_ICON, msg = "EFC Is Midfield", bind = "Callout: Midfield" },
    { label = CYAN .. "TREE", icon = MID_ICON, msg = "EFC Is Mid (Tree Stump)", bind = "Callout: Tree Stump" },
    { label = CYAN .. "TOP", icon = MID_ICON, msg = "EFC Is TOPSIDE (Alternating Ramp/GY/TOT)", bind = "Callout: Topside" },
    { label = GOLD .. "PICK", icon = FLAG_ICON, msg = "---PICK UP FLAG---", bind = "Callout: Pick up flag" },
    { label = GOLD .. "CAP", icon = FLAG_ICON, msg = "---CAP---", bind = "Callout: Cap" },
    { label = RED .. "LOW", icon = FLAG_ICON, msg = ">>> EFC LOW - NUKE <<<", bind = "Callout: Enemy carrier low" },
}

-- Every button has a fixed name (WSGForeverCallout1..26, row by row) so it can
-- be bound to a key in the game's Key Bindings menu: see Bindings.xml.
BINDING_HEADER_WSGFOREVER = "WSGForever"
do
    local n = 0
    for _, row in ipairs(rows) do
        for _, spec in ipairs(row) do
            n = n + 1
            spec.name = "WSGForeverCallout" .. n
            _G["BINDING_NAME_CLICK " .. spec.name .. ":LeftButton"] = spec.bind
        end
    end
end

local SIZE, GAP = 34, 2

local Callouts = {}
GK.RegisterModule("Callouts", Callouts)

local buttons = {}

-- Forever blocks addons from sending chat directly, so each button is a
-- secure macro button: clicking it runs "/i <message>" like a player macro.
local function ChatSlash()
    local channel = GK.ChatChannel()
    if channel == "INSTANCE_CHAT" then return "/i " end
    if channel == "RAID" then return "/ra " end
    if channel == "PARTY" then return "/p " end
    return "/s "
end

local function UpdateMacros()
    if InCombatLockdown() then return end
    local slash = ChatSlash()
    for _, b in ipairs(buttons) do
        b:SetAttribute("macrotext", slash .. b.msg)
    end
end

local function MakeButton(parent, spec)
    local b = CreateFrame("Button", spec.name, parent, "SecureActionButtonTemplate")
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b.msg = spec.msg
    buttons[#buttons + 1] = b

    b.icon = b:CreateTexture(nil, "BACKGROUND")
    b.icon:SetAllPoints()
    b.icon:SetTexture(spec.icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:SetAlpha(0.85)

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFont("Fonts\\FRIZQT__.TTF", 10, "THICKOUTLINE")
    -- The outline makes the game measure the label wider and taller than it
    -- draws, so true centre is 2 right and half a step down (measured in game).
    b.text:SetPoint("CENTER", 2, -0.5)
    b.text:SetText(spec.label)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(spec.msg, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

function Callouts:Init()
    local width = #rows[1] * (SIZE + GAP) - GAP
    local height = #rows * (SIZE + GAP) - GAP
    local f = CreateFrame("Frame", "WSGForeverCallouts", UIParent)
    f:SetSize(width, height)
    f:SetFrameStrata("LOW")
    for r, row in ipairs(rows) do
        -- Centre short rows under the full ones.
        local offset = (width - (#row * (SIZE + GAP) - GAP)) / 2
        for c, spec in ipairs(row) do
            local b = MakeButton(f, spec)
            b:SetPoint("TOPLEFT", offset + (c - 1) * (SIZE + GAP), -(r - 1) * (SIZE + GAP))
        end
    end
    GK.MakeMovable(f, "Callouts", { "CENTER", "CENTER", 460, -230 })
    self.frame = f

    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:SetScript("OnEvent", GK.Safe("Callouts event", UpdateMacros))
    UpdateMacros()
end

function Callouts:OutOfCombat()
    UpdateMacros()
end

function Callouts:Refresh()
    if not self.frame then return end
    UpdateMacros()
    self.frame:SetShown(GK.db.callouts and (GK.InWSG() or GK.ShouldShowAll()))
end
