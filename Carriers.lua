local _, GK = ...

-- Flag carriers in WSG:
--  * HP % after Blizzard's carrier names at the top of the screen
--    (or WSGForever's own clickable names with /fc fcnames)
--  * a countdown when a dropped flag will return to base
--  * a countdown to the flags spawning again after a capture
--  * an "EFC LOW" banner when the enemy carrier is under 50% HP

local DROP_RETURN = 12 -- seconds before a dropped flag returns to base
local FLAG_RESPAWN = 12 -- seconds until the flags spawn again after a capture
local LOW_HP = 0.5     -- "EFC LOW" banner below this

local FC = {}
GK.RegisterModule("Carriers", FC)

-- Keyed by which flag is carried: "Alliance" = the Alliance flag (held by a Horde player).
local state = {
    Alliance = { holder = nil, droppedAt = nil },
    Horde = { holder = nil, droppedAt = nil },
}
local classByName = {}
-- Captures: when the flags spawn again, when the last one was seen, and the
-- total capture count last read from the top of the screen.
local spawnAt, capturedAt, lastCaps

local function OurFlag()
    return UnitFactionGroup("player")
end

local function TheirFlag()
    return OurFlag() == "Horde" and "Alliance" or "Horde"
end

-- The game's unit slots for flag carriers (arena1/arena2 in BGs).
-- On Forever these slots hold carriers from both teams, so check the side.
-- Whether a carrier slot holds an enemy; nil if the game won't say.
local function IsEnemy(unit)
    local friend = GK.Plain(UnitIsFriend("player", unit))
    if friend ~= nil then return not friend end
    local enemy = GK.Plain(UnitIsEnemy("player", unit))
    if enemy ~= nil then return enemy end
    local faction = GK.Plain(UnitFactionGroup(unit))
    if faction then return faction ~= UnitFactionGroup("player") end
    -- Someone in our own raid is never an enemy.
    if GK.Plain(UnitInRaid(unit)) or GK.Plain(UnitInParty(unit)) then return false end
end

-- Second result is true when a slot is filled but its side can't be read,
-- so "no unit" doesn't have to mean the flag is no longer carried.
local function CarrierUnit(wantEnemy)
    local exists, enemy = {}, {}
    for i = 1, 2 do
        local unit = "arena" .. i
        if GK.Plain(UnitExists(unit)) then
            exists[i], enemy[i] = true, IsEnemy(unit)
        end
    end
    -- Two carriers are always one from each team, so a side the game won't
    -- give is the opposite of the other carrier's.
    if exists[1] and exists[2] then
        if enemy[1] == nil and enemy[2] ~= nil then enemy[1] = not enemy[2]
        elseif enemy[2] == nil and enemy[1] ~= nil then enemy[2] = not enemy[1] end
    end
    local unsure = false
    for i = 1, 2 do
        if exists[i] then
            if enemy[i] == wantEnemy then return "arena" .. i, false end
            if enemy[i] == nil then unsure = true end
        end
    end
    return nil, unsure
end

-- How many carrier slots are filled right now.
local function FilledSlots()
    local n = 0
    for i = 1, 2 do
        if GK.Plain(UnitExists("arena" .. i)) then n = n + 1 end
    end
    return n
end
local lastFilled = 0

-- How many of the game's own carrier frames are showing. These stay
-- readable when the carrier slots themselves aren't.
local function ShownCarrierFrames()
    local n = 0
    for i = 1, 2 do
        local f = _G["ArenaEnemyMatchFrame" .. i]
        local ok, shown = pcall(function() return f and f:IsVisible() end)
        if ok and shown then n = n + 1 end
    end
    return n
end

-- Keeps a short record of each drop countdown and what the game showed at
-- the time, to track down false ones (/fc debug prints how many).
local function NoteDrop(flag, source)
    local log = GK.db.dropLog or {}
    GK.db.dropLog = log
    local parts = { date("%H:%M:%S"), flag, source, "frames=" .. ShownCarrierFrames() }
    for i = 1, 2 do
        local unit = "arena" .. i
        local exists = UnitExists(unit)
        parts[#parts + 1] = string.format("%s[exists=%s enemy=%s name=%s]", unit,
            GK.IsSecret(exists) and "hidden" or tostring(exists),
            tostring(GK.Plain(exists) and IsEnemy(unit)), tostring(GK.Plain(exists) and GK.FullName(unit)))
    end
    log[#log + 1] = table.concat(parts, " ")
    while #log > 40 do table.remove(log, 1) end
end

function GK.EnemyCarrierUnit() return (CarrierUnit(true)) end
local function FriendlyCarrierUnit() return (CarrierUnit(false)) end

-- Name of the enemy holding our flag, if known.
function GK.GetEFC()
    return state[OurFlag()].holder
end

-- Name of our player holding the enemy flag, if known.
function GK.GetOurFC()
    return state[TheirFlag()].holder
end

local function Reset()
    for _, s in pairs(state) do
        s.holder, s.unit, s.droppedAt, s.fromSlot, s.lostAt = nil, nil, nil, nil, nil
    end
    spawnAt, capturedAt, lastCaps = nil, nil, nil
end

-- A flag was just captured: nothing is dropped, and both flags spawn again
-- after a delay. Seen twice (chat message and capture count) counts once.
local function OnCapture(now)
    for _, s in pairs(state) do s.droppedAt, s.lostAt = nil, nil end
    if capturedAt and now - capturedAt < 5 then return end
    capturedAt = now
    spawnAt = now + FLAG_RESPAWN
end

local function RefreshClasses()
    for _, row in ipairs(GK.ScoreRows()) do
        classByName[row.name] = row.classToken
        classByName[GK.ShortName(row.name)] = row.classToken
    end
end

-- Blizzard's capture widgets ---------------------------------------------

-- Finds the widget for each flag. The WeakAura matched these tooltips:
-- "Horde flag captures" sits on the Alliance side, and vice versa.
local function FindWidgets()
    local found = {}
    local container = _G.UIWidgetTopCenterContainerFrame
    if not container then return found end
    for _, child in ipairs({ container:GetChildren() }) do
        local tip = GK.Plain(child.tooltip)
        if child:IsShown() and type(tip) == "string" then
            if tip:find("Horde flag") then found.Alliance = child
            elseif tip:find("Alliance flag") then found.Horde = child end
        end
    end
    return found
end

-- Finds the FontString in Blizzard's widget that shows this carrier's name.
local function FindNameString(frame, name, depth)
    if not frame or depth > 3 then return nil end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetText and region:GetObjectType() == "FontString" then
            local text = GK.Plain(region:GetText())
            if type(text) == "string" and text:find(name, 1, true) then return region end
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        local found = FindNameString(child, name, depth + 1)
        if found then return found end
    end
end

-- Both teams' capture counts ("1/3") at the top of the screen, added up.
-- nil unless exactly two can be read, so a row loading late isn't a capture.
local function TotalCaptures()
    local container = _G.UIWidgetTopCenterContainerFrame
    if not container then return nil end
    local total, found = 0, 0
    local function scan(frame, depth)
        if depth > 3 then return end
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:GetObjectType() == "FontString" then
                local text = GK.Plain(region:GetText())
                if type(text) == "string" then
                    -- Drop colour codes like |cffffffff ... |r before matching.
                    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    local n = text:match("^%s*(%d+)%s*/%s*%d+%s*$")
                    if n then total, found = total + tonumber(n), found + 1 end
                end
            end
        end
        for _, child in ipairs({ frame:GetChildren() }) do scan(child, depth + 1) end
    end
    scan(container, 0)
    if found == 2 then return total end
end

-- A higher total means a capture, whichever team's count went up.
local function WatchCaptures(now)
    local caps = TotalCaptures()
    if not caps then return end
    if lastCaps and caps > lastCaps then OnCapture(now) end
    lastCaps = caps
end

-- Keeps each flag's carrier in sync with the game's carrier slots. In
-- battlegrounds the flag messages can reach addons hidden, so the slots are
-- the reliable source. Returns true if a carrier changed.
-- slotLost: a carrier slot emptied since the last look.
local function SyncFromSlots(flag, now, slotLost)
    local s = state[flag]
    local unit, unsure = CarrierUnit(flag == OurFlag())
    local changed = false
    if unit then
        -- A new pickup means the flags are back, whatever the countdown says.
        if not s.unit and capturedAt and now - capturedAt > 3 then spawnAt = nil end
        -- A filled slot means the flag is carried, even when the carrier's
        -- name can't be read (hidden, or not loaded yet). Keep the last
        -- known name until a readable one replaces it.
        local name = GK.FullName(unit)
        if (name and s.holder ~= name) or not s.unit then
            if name then s.holder = name end
            changed = true
        end
        s.unit, s.fromSlot = unit, true
        s.droppedAt, s.lostAt = nil, nil
    elseif s.fromSlot and not unsure then
        -- No carrier for this flag any more. If no slot emptied, the game
        -- only changed its mind about which side a carrier is on (it can
        -- misreport a carrier who just picked up), so nothing was dropped.
        -- Otherwise the flag was dropped or captured: unless a capture was
        -- just seen, wait a moment for one (OnCapture clears lostAt) before
        -- calling it a drop.
        s.holder, s.unit, s.fromSlot = nil, nil, nil
        if slotLost and not (capturedAt and now - capturedAt < 3) then s.lostAt = now end
        changed = true
    end
    if s.lostAt and now - s.lostAt > 1 then
        if not s.droppedAt then
            s.droppedAt = s.lostAt
            NoteDrop(flag, "slot")
        end
        s.lostAt = nil
    end
    return changed
end

-- Our clickable name buttons (only shown with /fc fcnames) -----------------

local buttons = {}

local function MakeButton(flag)
    local b = CreateFrame("Button", "WSGForeverFC" .. flag, UIParent, "SecureActionButtonTemplate")
    -- Above Blizzard's flag display, which otherwise catches the clicks.
    b:SetFrameStrata("HIGH")
    -- Fire on the same click edge as action buttons, like BattleGroundEnemies.
    local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown") or false
    b:RegisterForClicks(keyDown and "AnyDown" or "AnyUp")
    b:SetAttribute("useOnKeyDown", keyDown)
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "")
    b.text = b:CreateFontString(nil, "ARTWORK")
    b.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    b.text:SetPoint("LEFT")
    b:SetSize(1, 16)
    return b
end

-- Anchors our buttons next to the widgets. Only possible out of combat.
local function Anchor()
    if InCombatLockdown() then return end
    local widgets = FindWidgets()
    local container = _G.UIWidgetTopCenterContainerFrame
    for i, flag in ipairs({ "Alliance", "Horde" }) do
        local b = buttons[flag]
        b:ClearAllPoints()
        if widgets[flag] then
            b:SetPoint("LEFT", widgets[flag], "LEFT", 85, 0)
        elseif container then
            b:SetPoint("TOP", container, "BOTTOM", 0, -2 - (i - 1) * 18)
        else
            b:SetPoint("TOP", UIParent, "TOP", 0, -60 - (i - 1) * 18)
        end
    end
end

-- Hidden buttons for the Key Bindings menu: target or ping a carrier by key.
_G["BINDING_NAME_CLICK WSGForeverBindTargetEFC:LeftButton"] = "Target enemy flag carrier"
_G["BINDING_NAME_CLICK WSGForeverBindPingEFC:LeftButton"] = "Ping enemy flag carrier (Attack)"
_G["BINDING_NAME_CLICK WSGForeverBindPingFC:LeftButton"] = "Ping our flag carrier (Assist)"
local bindButtons = {}
local function MakeBindButtons()
    for _, name in ipairs({ "TargetEFC", "PingEFC", "PingFC" }) do
        local b = CreateFrame("Button", "WSGForeverBind" .. name, UIParent, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:Hide()
        bindButtons[name] = b
    end
end

local function ApplyMacros()
    if InCombatLockdown() then return end
    if bindButtons.PingEFC then
        local unit = GK.EnemyCarrierUnit() or "arena1"
        bindButtons.TargetEFC:SetAttribute("type", "target")
        bindButtons.TargetEFC:SetAttribute("unit", unit)
        bindButtons.PingEFC:SetAttribute("type", "macro")
        bindButtons.PingEFC:SetAttribute("macrotext", "/ping [@" .. unit .. "] attack")
        local ours = GK.GetOurFC()
        bindButtons.PingFC:SetAttribute("type", "macro")
        bindButtons.PingFC:SetAttribute("macrotext", ours and GK.OnNamedTarget(ours, "/ping [@target,exists] assist") or "")
    end
    for flag, s in pairs(state) do
        local b = buttons[flag]
        if flag == OurFlag() then
            -- Enemy carrier: target the game's carrier slot directly, the way
            -- BattleGroundEnemies does. Works in combat and when the flag
            -- changes hands, no name needed. Right click sets focus, middle
            -- click pings Attack.
            local unit = GK.EnemyCarrierUnit() or "arena1"
            b:SetAttribute("unit", unit)
            b:SetAttribute("type1", "target")
            b:SetAttribute("type2", "focus")
            b:SetAttribute("type3", "macro")
            b:SetAttribute("macrotext3", "/ping [@" .. unit .. "] attack")
        else
            -- Our own carrier: target by name.
            b:SetAttribute("unit", nil)
            b:SetAttribute("type1", "macro")
            b:SetAttribute("type2", "macro")
            b:SetAttribute("type3", "macro")
            b:SetAttribute("macrotext", s.holder and ("/targetexact " .. s.holder) or "")
            -- Middle click pings Assist on our carrier.
            b:SetAttribute("macrotext3", s.holder and GK.OnNamedTarget(s.holder, "/ping [@target,exists] assist") or "")
        end
        b:SetWidth(math.max(1, b.text:GetStringWidth()))
    end
end

-- HP / drop-timer labels -----------------------------------------------------

-- Plain labels (not clickable, so they can move in combat). They sit after
-- Blizzard's carrier name, or after ours with /fc fcnames.
local labels = {}

local function MakeLabel()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetSize(1, 16)
    f.text = f:CreateFontString(nil, "ARTWORK")
    f.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    f.text:SetPoint("LEFT")
    return f
end

local function PlaceLabel(flag, holder)
    local label = labels[flag]
    label:ClearAllPoints()
    if GK.db.fcNames then
        label:SetPoint("LEFT", buttons[flag].text, "RIGHT", 4, 0)
        return
    end
    local widget = FindWidgets()[flag]
    local nameFS = widget and holder and FindNameString(widget, holder, 0)
    if nameFS then
        label:SetPoint("LEFT", nameFS, "LEFT", nameFS:GetUnboundedStringWidth() + 6, 0)
    elseif widget then
        -- Past Blizzard's flag icon, which sits just right of the score, and
        -- past the carrier frames when those are parked there and in use.
        local x = 34
        local framesRight = GK.CarrierFramesRight and GK.CarrierFramesRight()
        local widgetRight = widget:GetRight()
        if framesRight and widgetRight then
            local k = widget:GetEffectiveScale() / UIParent:GetEffectiveScale()
            -- Only when the frames really are beside the flag rows.
            local gap = framesRight - widgetRight * k
            if gap > 0 and gap < 400 then x = math.max(x, gap + 10) end
        end
        label:SetPoint("LEFT", widget, "RIGHT", x, 0)
    else
        label:SetPoint("TOP", UIParent, "TOP", 0, flag == "Alliance" and -60 or -78)
    end
end

-- "EFC LOW" banner -----------------------------------------------------------
-- The addon can't read enemy HP, but the game can turn hidden HP into a bar
-- fill. A step curve maps HP below 50% to 1 and above to 0; the bar's fill
-- is the banner, so it only shows when the enemy carrier is low.

local lowBanner, lowCurve

local function MakeLowBanner()
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType) then return end
    local ok = pcall(function()
        lowCurve = C_CurveUtil.CreateCurve()
        lowCurve:SetType(Enum.LuaCurveType.Step)
        lowCurve:AddPoint(0, 1)
        lowCurve:AddPoint(LOW_HP, 0)
    end)
    if not ok then lowCurve = nil return end

    local f = CreateFrame("StatusBar", "WSGForeverEFCLow", UIParent)
    f:SetSize(190, 30)
    f:SetFrameStrata("LOW")
    f:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    f:GetStatusBarTexture():SetAlpha(0) -- the fill only drives the clip below
    f:SetMinMaxValues(0, 1)
    f:SetValue(0)

    -- Everything visible lives in a frame clipped to the fill, so it all
    -- appears at once when HP drops under 50% and vanishes above it.
    local clip = CreateFrame("Frame", nil, f)
    clip:SetPoint("TOPLEFT", f:GetStatusBarTexture(), "TOPLEFT")
    clip:SetPoint("BOTTOMRIGHT", f:GetStatusBarTexture(), "BOTTOMRIGHT")
    clip:SetClipsChildren(true)
    local plate = CreateFrame("Frame", nil, clip)
    plate:SetAllPoints(f)

    local bg = plate:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.07, 0.02, 0.02, 0.88)
    -- Thin red border.
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = plate:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.85, 0.12, 0.1, 0.9)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
        end
    end
    -- Accent stripe on the left.
    local stripe = plate:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("BOTTOMLEFT", 1, 1)
    stripe:SetWidth(4)
    stripe:SetColorTexture(1, 0.2, 0.15, 1)
    -- Soft red glow that pulses.
    local glow = plate:CreateTexture(nil, "ARTWORK", nil, -1)
    glow:SetPoint("TOPLEFT", 5, -1)
    glow:SetPoint("BOTTOMRIGHT", -1, 1)
    glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    if glow.SetGradient and CreateColor then
        glow:SetGradient("HORIZONTAL", CreateColor(0.9, 0.1, 0.08, 0.45), CreateColor(0.9, 0.1, 0.08, 0))
    else
        glow:SetVertexColor(0.9, 0.1, 0.08, 0.2)
    end
    local pulse = plate:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetTarget(glow)
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.2)
    fade:SetDuration(0.5)
    fade:SetSmoothing("IN_OUT")
    pulse:Play()

    local skull = plate:CreateTexture(nil, "OVERLAY")
    skull:SetSize(18, 18)
    skull:SetPoint("LEFT", 12, 0)
    skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    local text = plate:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    text:SetPoint("LEFT", skull, "RIGHT", 8, 0)
    text:SetTextColor(1, 0.4, 0.35)
    text:SetText("ENEMY FC LOW")
    GK.MakeMovable(f, "EFC low alert", { "TOP", "TOP", 0, -174 })
    lowBanner = f
end

local function UpdateLowBanner(unit)
    if not lowBanner then return end
    if GK.ShouldShowAll() and not GK.InWSG() then
        lowBanner:SetValue(1) -- keep it visible while placing or testing
        return
    end
    if not unit or not GK.db.efcLowAlert then
        lowBanner:SetValue(0)
        return
    end
    local ok = pcall(function()
        local v = UnitHealthPercent(unit, true, lowCurve)
        if v then lowBanner:SetValue(v) end
    end)
    if not ok then lowBanner:SetValue(0) end
end

-- Flag spawn countdown ------------------------------------------------------
-- One line for both flags, by default between the rez timer and the EFC
-- LOW banner.

local spawnFrame
local SPAWN_TEXT = "|cff4fff4fFlags spawn in %d|r"

local function MakeSpawnFrame()
    local f = CreateFrame("Frame", "WSGForeverFlagSpawn", UIParent)
    f:SetSize(190, 24)
    f:SetFrameStrata("LOW") -- under bags and other windows
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    f.text:SetPoint("CENTER")
    GK.MakeMovable(f, "Flag spawn", { "TOP", "TOP", 0, -146 })
    spawnFrame = f
end

local function UpdateSpawnFrame(now)
    local left = spawnAt and (spawnAt - now)
    if left and left > 0 then
        spawnFrame.text:SetFormattedText(SPAWN_TEXT, math.ceil(left))
    else
        spawnFrame.text:SetText("")
    end
end

-- Per-tick update ------------------------------------------------------------

local function UpdateFlag(flag, units)
    local s, b = state[flag], buttons[flag]
    local label = labels[flag].text
    local isEFC = (flag == OurFlag())

    if not s.holder and not s.unit then
        b.text:SetText("")
        local now = GetTime()
        local left = s.droppedAt and (s.droppedAt + DROP_RETURN - now)
        if left and left > 0 then
            PlaceLabel(flag, nil)
            label:SetText(string.format("|cffffd100Dropped - returns in %d|r", math.ceil(left)))
        else
            s.droppedAt = nil
            label:SetText("")
        end
        if isEFC then UpdateLowBanner(nil) end
        return
    end

    if GK.db.fcNames and s.holder then
        local r, g, bl = GK.ClassColor(classByName[s.holder])
        b.text:SetText(string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, bl * 255, s.holder))
        if not InCombatLockdown() then b:SetWidth(math.max(1, b.text:GetStringWidth())) end
    else
        b.text:SetText("")
    end
    PlaceLabel(flag, s.holder)

    local unit = s.unit or (s.holder and units[s.holder])
    if not unit then unit = isEFC and GK.EnemyCarrierUnit() or (not isEFC and FriendlyCarrierUnit()) or nil end
    -- Blizzard's carrier frames already show HP when we move them up here.
    if unit and not GK.db.moveBlizzCarriers then
        GK.SetHealthText(label, unit, "pct")
    else
        label:SetText("")
    end
    if isEFC then UpdateLowBanner(unit) end
end

-- Events ---------------------------------------------------------------

local function FlagFromMsg(msg)
    local lower = msg:lower()
    if lower:find("alliance flag") then return "Alliance" end
    if lower:find("horde flag") then return "Horde" end
end

local function OnSystemMessage(msg)
    msg = GK.Plain(msg)
    if type(msg) ~= "string" then return end
    local lower = msg:lower()
    if lower:find("placed at their bases") then Reset() return end
    local flag = FlagFromMsg(msg)
    if not flag then return end
    local s = state[flag]
    local picker = msg:match("[Pp]icked up by (.-)!?$")
    if picker then
        s.holder, s.droppedAt, s.lostAt = picker, nil, nil
        if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
    elseif lower:find("dropped by") then
        s.holder, s.unit, s.fromSlot, s.lostAt, s.droppedAt = nil, nil, nil, nil, GetTime()
        NoteDrop(flag, "chat")
    elseif lower:find("captured the") then
        s.holder, s.unit, s.fromSlot = nil, nil, nil
        OnCapture(GetTime())
    elseif lower:find("returned") then
        s.holder, s.unit, s.fromSlot, s.lostAt, s.droppedAt = nil, nil, nil, nil, nil
    end
    ApplyMacros()
end

function FC:Init()
    buttons.Alliance = MakeButton("Alliance")
    buttons.Horde = MakeButton("Horde")
    MakeBindButtons()
    labels.Alliance = MakeLabel()
    labels.Horde = MakeLabel()
    MakeLowBanner()
    MakeSpawnFrame()

    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
    f:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
    f:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
    f:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
    f:RegisterEvent("UPDATE_UI_WIDGET")
    f:RegisterEvent("ARENA_OPPONENT_UPDATE")
    f:SetScript("OnEvent", GK.Safe("Carriers event", function(_, event, ...)
        if not GK.InWSG() and not GK.testMode then return end
        if event == "UPDATE_BATTLEFIELD_SCORE" then
            RefreshClasses()
        elseif event == "UPDATE_UI_WIDGET" then
            Anchor()
        elseif event == "ARENA_OPPONENT_UPDATE" then
            ApplyMacros() -- carrier slot changed; no-op in combat
        else
            OnSystemMessage(...)
        end
    end))

    local elapsed = 0
    f:SetScript("OnUpdate", GK.Safe("Carriers", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 then return end
        elapsed = 0
        if not labels.Alliance:IsShown() then return end
        local units = GK.VisibleUnits()
        local now = GetTime()
        if spawnAt and now >= spawnAt then spawnAt = nil end
        if GK.InWSG() then
            WatchCaptures(now)
            UpdateSpawnFrame(now)
        end
        local filled = FilledSlots()
        local slotLost = filled < lastFilled
        lastFilled = filled
        local changedA = SyncFromSlots("Alliance", now, slotLost)
        local changedH = SyncFromSlots("Horde", now, slotLost)
        -- Both slots filled (or both of the game's carrier frames showing)
        -- means both flags are being carried, even if
        -- the game won't say who is on which side: nothing is dropped.
        if filled == 2 or ShownCarrierFrames() == 2 then
            for _, s in pairs(state) do s.droppedAt, s.lostAt = nil, nil end
        end
        if changedA or changedH then ApplyMacros() end
        UpdateFlag("Alliance", units)
        UpdateFlag("Horde", units)
    end))
end

-- /fc debug: what the carrier tracking can see.
function FC:Debug()
    for i = 1, 2 do
        local unit = "arena" .. i
        local exists = GK.Plain(UnitExists(unit))
        GK.Print(string.format("%s: exists %s, enemy %s, name %s", unit, tostring(exists),
            tostring(exists and IsEnemy(unit)), tostring(exists and GK.FullName(unit))))
    end
    for flag, s in pairs(state) do
        GK.Print(string.format("%s flag: holder %s, unit %s, dropped %s", flag, tostring(s.holder),
            tostring(s.unit), s.droppedAt and string.format("%.0fs ago", GetTime() - s.droppedAt) or "no"))
    end
    GK.Print(string.format("carrier frames showing: %d, drop countdowns recorded: %d", ShownCarrierFrames(),
        GK.db.dropLog and #GK.db.dropLog or 0))
    GK.Print(string.format("captures read: %s, flags spawn in: %s", tostring(TotalCaptures()),
        spawnAt and string.format("%.0fs", spawnAt - GetTime()) or "no"))
end

function FC:OutOfCombat()
    Anchor()
    ApplyMacros()
end

function FC:Refresh()
    if not buttons.Alliance then return end
    local inWSG = GK.InWSG()
    local show = GK.db.carriers and (inWSG or GK.testMode)
    -- Clear sample names when test mode ends, and everything when leaving WSG.
    if not inWSG or (self.showingTest and not GK.testMode) then Reset() end
    self.showingTest = show and GK.testMode and not inWSG
    if self.showingTest then
        state.Alliance.holder = GK.FullName("player")
        state.Horde.droppedAt = GetTime()
    end
    -- Size of the HP / timer text and our carrier names.
    local scale = GK.Scale("Carrier text")
    for _, flag in ipairs({ "Alliance", "Horde" }) do
        labels[flag].text:SetFont("Fonts\\FRIZQT__.TTF", 14 * scale, "OUTLINE")
        labels[flag]:SetHeight(16 * scale)
        buttons[flag].text:SetFont("Fonts\\FRIZQT__.TTF", 14 * scale, "OUTLINE")
        buttons[flag]:SetHeight(16 * scale)
    end
    spawnFrame:SetShown(GK.db.carriers and (inWSG or GK.ShouldShowAll()))
    -- A sample while unlocked or testing so it can be placed.
    if not inWSG then
        spawnFrame.text:SetText(GK.ShouldShowAll() and SPAWN_TEXT:format(FLAG_RESPAWN) or "")
    end
    buttons.Alliance:SetShown(show and GK.db.fcNames)
    buttons.Horde:SetShown(show and GK.db.fcNames)
    labels.Alliance:SetShown(show)
    labels.Horde:SetShown(show)
    if lowBanner then
        lowBanner:SetShown(GK.db.efcLowAlert and (inWSG or GK.ShouldShowAll()))
        -- Show it filled while unlocked or testing so it can be placed.
        if GK.ShouldShowAll() and not inWSG then lowBanner:SetValue(1) end
    end
    if show then
        RefreshClasses()
        Anchor()
        ApplyMacros()
    end
end
