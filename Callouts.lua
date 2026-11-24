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

-- Arathi Basin: one column per node, each with its own icon (a horse for
-- the Stables, gold for the Gold Mine and so on), and one row per call.
local ICONS = "Interface\\Icons\\"
local AB_NODES = {
    { "ST", "Stables", ICONS .. "Ability_Mount_RidingHorse" },
    { "BS", "Blacksmith", ICONS .. "Trade_BlackSmithing" },
    { "LM", "Lumber Mill", ICONS .. "INV_TradeskillItem_03" },
    { "GM", "Gold Mine", ICONS .. "INV_Ore_Gold_01" },
    { "FARM", "Farm", ICONS .. "INV_Misc_Food_Wheat_01" },
}
-- { label, colour, message, name in the Key Bindings menu }; %s is the node.
local AB_CALLS = {
    { "INC", RED, "INC %s", "Incoming" },
    { "BIG", GOLD, "BIG INC %s - 4 or more", "Big incoming" },
    { "SAFE", "|cff5fff6f", "%s SAFE", "Safe" },
    { "HELP", CYAN, "HELP at %s", "Help" },
}
local abRows = {}
for r, call in ipairs(AB_CALLS) do
    abRows[r] = {}
    for _, node in ipairs(AB_NODES) do
        abRows[r][#abRows[r] + 1] = { label = call[2] .. call[1] .. "\n" .. node[1], icon = node[3], dim = true,
            msg = call[3]:format(node[2]), bind = "AB callout: " .. call[4] .. " " .. node[2] }
    end
end

-- Every button has a fixed name, row by row (WSGForeverCallout1..26 and
-- WSGForeverABCallout1..20), so it can be bound to a key in the game's Key
-- Bindings menu: see Bindings.xml.
BINDING_HEADER_WSGFOREVER = "WSGForever"
local function NameButtons(set, prefix)
    local n = 0
    for _, row in ipairs(set) do
        for _, spec in ipairs(row) do
            n = n + 1
            spec.name = prefix .. n
            _G["BINDING_NAME_CLICK " .. spec.name .. ":LeftButton"] = spec.bind
        end
    end
end
NameButtons(rows, "WSGForeverCallout")
NameButtons(abRows, "WSGForeverABCallout")

-- One more button, off unless you turn it on with /fc ad: a line about the
-- addon for your team. It is a callout like the rest, so a click sends it
-- at any point in a match, and it has a key binding of its own.
local function AdSpec(name)
    return { name = name, label = GOLD .. "AD", icon = 134420, dim = true, msg = GK.AD }
end
_G["BINDING_NAME_CLICK WSGForeverAdButton:LeftButton"] = "Tell your team about WSGForever"

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
    -- Detailed icons are darkened a little so the label reads over them.
    if spec.dim then b.icon:SetVertexColor(0.6, 0.6, 0.6) end

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
        GameTooltip:SetText(spec.msg, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

-- One bar of callout buttons, movable under its own name.
local function MakeBar(name, set, key, default)
    local width = #set[1] * (SIZE + GAP) - GAP
    local height = #set * (SIZE + GAP) - GAP
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetFrameStrata("LOW")
    for r, row in ipairs(set) do
        -- Centre short rows under the full ones.
        local offset = (width - (#row * (SIZE + GAP) - GAP)) / 2
        for c, spec in ipairs(row) do
            local b = MakeButton(f, spec)
            b:SetPoint("TOPLEFT", offset + (c - 1) * (SIZE + GAP), -(r - 1) * (SIZE + GAP))
        end
    end
    -- The ad button goes at the right-hand end of the last row where that
    -- row has room; otherwise it gets a row of its own, and the bar is that
    -- much taller while it shows.
    local last = #set
    local ownRow = #set[last] == #set[1]
    f.ad = MakeButton(f, AdSpec(name .. "Ad"))
    f.ad:SetPoint("TOPLEFT", width - SIZE, -(ownRow and last or last - 1) * (SIZE + GAP))
    f.ad:Hide()
    f.plainHeight, f.adHeight = height, ownRow and height + SIZE + GAP or height
    GK.MakeMovable(f, key, default)
    return f
end

-- Shows or hides the ad button on a bar. Bars cannot change in combat.
local function SyncAd(f)
    if InCombatLockdown() then return end
    local on = GK.db.adButton and true or false
    f.ad:SetShown(on)
    f:SetHeight(on and f.adHeight or f.plainHeight)
end

-- The key binding for the ad presses this hidden button, so it works
-- whether or not the button on the bar is turned on.
local function MakeAdBinding()
    local b = CreateFrame("Button", "WSGForeverAdButton", UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b.msg = GK.AD
    buttons[#buttons + 1] = b -- so it follows the same chat channel as the callouts
    b:Hide()
end

function Callouts:Init()
    local f = MakeBar("WSGForeverCallouts", rows, "Callouts", { "CENTER", "CENTER", 460, -230 })
    self.frame = f
    MakeAdBinding()
    self.abFrame = MakeBar("WSGForeverABCallouts", abRows, "AB callouts", { "CENTER", "CENTER", 460, -80 })

    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:SetScript("OnEvent", GK.Safe("Callouts event", UpdateMacros))
    UpdateMacros()
end

function Callouts:OutOfCombat()
    UpdateMacros()
    SyncAd(self.frame)
    SyncAd(self.abFrame)
end

function Callouts:Refresh()
    if not self.frame then return end
    UpdateMacros()
    SyncAd(self.frame)
    SyncAd(self.abFrame)
    -- Until it has been dragged somewhere of its own, the Arathi Basin bar
    -- takes the Warsong bar's spot (same bottom right corner): the two are
    -- never needed at once, and that spot is already clear on your screen.
    local own = GK.db.positions["AB callouts"] ~= nil
    if not own then
        self.abFrame:ClearAllPoints()
        self.abFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
    end
    -- Each battleground gets its own bar. Outside one, the preview shows the
    -- Warsong bar, plus the Arathi one if it has its own spot; unlocking
    -- shows both so the Arathi one can be dragged away.
    local wsg, ab = GK.InWSG(), GK.InAB()
    local preview = GK.ShouldShowAll()
    self.frame:SetShown(GK.db.callouts and (wsg or (preview and not ab)) and true or false)
    self.abFrame:SetShown(GK.db.callouts and (ab or (not wsg and ((preview and own) or not GK.db.locked))) and true or false)
end
