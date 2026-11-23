-- A small stand-in for the game, enough to load the addon and drive it with
-- scripted events on a fake clock. Run under Lua 5.1, the game's Lua version.
--
-- It has no renderer: it can check what the addon decides to show, not how
-- it looks. Game behaviour here is only what was observed in the real client.

local sim = { time = 1000, frames = {}, timers = {}, printed = {}, units = {} }

-- Hidden ("secret") values: readable by the game, not by addons.
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
sim.SECRET = SECRET
function issecretvalue(v) return v == SECRET end

-- Widgets ------------------------------------------------------------------

local methods = {}
local WidgetMT = {}

local function Widget(kind, parent)
    local w = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {}, events = {},
        children = {}, regions = {}, attributes = {} }, WidgetMT)
    return w
end

WidgetMT.__index = function(_, key)
    local m = methods[key]
    if m then return m end
    if type(key) ~= "string" then return nil end
    -- Anything else the game offers is accepted and does nothing.
    if key:find("^Create") then
        return function(self) local c = Widget(key, self) self.regions[#self.regions + 1] = c return c end
    end
    if key:find("^[A-Z]") then return function() end end
end

function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:GetScript(name) return self.scripts[name] end
function methods:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = old and function(...) old(...) fn(...) end or fn
end
function methods:RegisterEvent(e) self.events[e] = true end
function methods:UnregisterEvent(e) self.events[e] = nil end
-- Showing and hiding run the frame's OnShow / OnHide scripts, as the game does.
function methods:SetShown(on)
    on = on and true or false
    if on == self.shown then return end
    self.shown = on
    local fn = self.scripts[on and "OnShow" or "OnHide"]
    if fn then fn(self) end
end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:IsShown() return self.shown end
function methods:IsVisible()
    local w = self
    while w do
        if not w.shown then return false end
        w = w.parent
    end
    return true
end
function methods:SetText(t) self.text = t end
function methods:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function methods:GetText() return self.text end
function methods:SetAttribute(k, v) self.attributes[k] = v end
function methods:GetAttribute(k) return self.attributes[k] end
function methods:GetParent() return self.parent end
function methods:GetName() return self.name end
function methods:GetObjectType() return self.kind end
function methods:GetChildren() return unpack(self.children) end
function methods:GetRegions() return unpack(self.regions) end
function methods:SetSize(w, h) self.w, self.h = w, h end
function methods:SetWidth(w) self.w = w end
function methods:SetHeight(h) self.h = h end
function methods:GetWidth() return self.w or 100 end
function methods:GetHeight() return self.h or 20 end
function methods:SetAtlas(a) self.atlas = a end
function methods:GetAtlas() return self.atlas end
function methods:GetStringWidth() return 50 end
function methods:GetUnboundedStringWidth() return 50 end
function methods:GetScale() return self.scale or 1 end
function methods:SetScale(s) self.scale = s end
function methods:GetEffectiveScale() return 1 end
function methods:GetFrameLevel() return 1 end
function methods:GetFrameStrata() return "MEDIUM" end
function methods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function methods:SetPoint(_, rel) if type(rel) == "table" then self.anchoredTo = rel end end
function methods:ClearAllPoints() self.anchoredTo = nil end
function methods:GetCenter() return 500, 500 end
function methods:GetRight() return 600 end
function methods:GetLeft() return 400 end
function methods:GetTop() return 520 end
function methods:GetBottom() return 480 end
function methods:CreateFontString() local c = Widget("FontString", self) self.regions[#self.regions + 1] = c return c end
function methods:CreateTexture() local c = Widget("Texture", self) self.regions[#self.regions + 1] = c return c end
function methods:CreateAnimationGroup() return Widget("AnimationGroup", self) end
function methods:CreateAnimation() return Widget("Animation", self) end
function methods:GetStatusBarTexture() self.barTexture = self.barTexture or Widget("Texture", self) return self.barTexture end

function CreateFrame(kind, name, parent)
    local f = Widget(kind or "Frame", parent)
    f.name = name
    if parent then parent.children[#parent.children + 1] = f end
    if name then _G[name] = f end
    sim.frames[#sim.frames + 1] = f
    return f
end

UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
function GameTooltip_Hide() end
-- What the tooltip currently says, one string per line, in sim.tip.
sim.tip = {}
function GameTooltip:SetText(text) sim.tip = { text } end
function GameTooltip:AddLine(text) sim.tip[#sim.tip + 1] = text end
function GameTooltip:AddDoubleLine(left, right) sim.tip[#sim.tip + 1] = left .. " | " .. right end
UISpecialFrames = {}

-- Plain globals the addon reads ------------------------------------------------

RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
CLASS_ICON_TCOORDS = {}
UNKNOWNOBJECT = "Unknown"
LE_PARTY_CATEGORY_INSTANCE = 2
SlashCmdList = {}
C_Timer = {}
function C_Timer.After(delay, fn) sim.timers[#sim.timers + 1] = { at = sim.time + delay, fn = fn } end
function GetTime() return sim.time end
function date() return "00:00:00" end
function time() return math.floor(sim.time) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
function hooksecurefunc(a, b, c)
    if type(a) == "string" then
        local old = _G[a]
        _G[a] = function(...) local r = { old(...) } b(...) return unpack(r) end
    elseif type(a) == "table" then
        local old = a[b]
        a[b] = function(...) local r = { old(...) } c(...) return unpack(r) end
    end
end
function InCombatLockdown() return sim.inCombat or false end
function GetInstanceInfo() return sim.zone or "Warsong Gulch", sim.instanceType or "pvp", nil, nil, nil, nil, nil, sim.instanceID or 489 end
function GetZoneText() return sim.zone or "Warsong Gulch" end
-- The scoreboard: sim.scores is a list of rows as the game returns them,
-- sim.winner is 0 (Horde), 1 (Alliance) or nil while the match is running.
sim.scores = {}
-- The scoreboard's team tabs limit what these return: -1 both, 0 Horde, 1 Alliance.
sim.scoreFilter = -1
function SetBattlefieldScoreFaction(faction) sim.scoreFilter = faction or -1 end
local function Scores()
    if sim.scoreFilter ~= 0 and sim.scoreFilter ~= 1 then return sim.scores end
    local list = {}
    for _, r in ipairs(sim.scores) do
        if r.faction == sim.scoreFilter then list[#list + 1] = r end
    end
    return list
end
function GetNumBattlefieldScores() return #Scores() end
C_PvP = { GetScoreInfo = function(i) return Scores()[i] end }
-- The older scoreboard call, with its positional results.
function GetBattlefieldScore(i)
    local r = Scores()[i]
    if not r then return nil end
    -- sim.scoreLayout "modern" has no rank column, as on newer clients.
    if sim.scoreLayout == "modern" then
        return r.name, r.killingBlows, r.honorableKills, r.deaths, r.honorGained, r.faction, "Race", "Class", r.classToken, r.damageDone, r.healingDone
    end
    return r.name, r.killingBlows, r.honorableKills, r.deaths, r.honorGained, r.faction, 0, "Race", "Class", r.classToken, r.damageDone, r.healingDone
end
function GetBattlefieldStatData(i, j)
    local r = Scores()[i]
    local st = r and r.stats
    if st == SECRET then return SECRET end
    return type(st) == "table" and st[j] and st[j].pvpStatValue or nil
end
function GetBattlefieldWinner() return sim.winner end
function GetBattlefieldInstanceRunTime() return sim.runTimeMs or 0 end
function RequestBattlefieldScoreData() end
function GetNumGroupMembers() return 0 end
function IsInGroup() return true end
function IsInRaid() return true end
-- Hidden addon-to-addon messages: what the addon sent is kept in sim.sent.
sim.sent = {}
sim.version = "0.6.0"
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, msg, channel) sim.sent[#sim.sent + 1] = { prefix = prefix, msg = msg, channel = channel } end,
}
function GetAddOnMetadata(_, field) if field == "Version" then return sim.version end end
function UnitIsGroupLeader() return false end
function GetCVarBool() return false end
function GetCursorPosition() return 0, 0 end
-- Sounds played, and the battleground queue: sim.queue[i] = { status, name, secondsLeft }.
sim.sounds = {}
function PlaySound(id, channel) sim.sounds[#sim.sounds + 1] = { id = id, channel = channel } end
sim.queue = {}
function GetMaxBattlefieldID() return 3 end
function GetBattlefieldStatus(i) local q = sim.queue[i] if q then return q[1], q[2] end return "none" end
function GetBattlefieldPortExpiration(i) local q = sim.queue[i] return q and q[3] or 0 end
-- While queued: sim.queue[i] = { "queued", name, nil, waitedMs, estimateMs }.
function GetBattlefieldTimeWaited(i) local q = sim.queue[i] return q and q[4] or 0 end
function GetBattlefieldEstimatedWaitTime(i) local q = sim.queue[i] return q and q[5] or 0 end

local realPrint = print
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    sim.printed[#sim.printed + 1] = table.concat(parts, " ")
end
sim.realPrint = realPrint

-- Units --------------------------------------------------------------------------
-- sim.units[token] = { name = "First", surname = "Last", side = "friend" | "enemy" | "hidden",
--                      inRaid = bool }. sim.playerFaction is the player's side.

sim.playerFaction = "Horde"
local function U(unit) return sim.units[unit] end

function UnitExists(unit) if unit == "player" then return true end return U(unit) ~= nil end
function UnitName(unit)
    if unit == "player" then return "Test", "Player" end
    local u = U(unit)
    if not u then return nil end
    if u.nameHidden then return SECRET end
    return u.name, u.surname
end
function UnitFactionGroup(unit)
    if unit == "player" then return sim.playerFaction end
    local u = U(unit)
    if not u or u.side == "hidden" then return u and SECRET or nil end
    local other = sim.playerFaction == "Horde" and "Alliance" or "Horde"
    return u.side == "friend" and sim.playerFaction or other
end
function UnitIsFriend(_, unit)
    local u = U(unit)
    if not u then return nil end
    if u.side == "hidden" then return SECRET end
    return u.side == "friend"
end
function UnitIsEnemy(_, unit)
    local u = U(unit)
    if not u then return nil end
    if u.side == "hidden" then return SECRET end
    return u.side == "enemy"
end
function UnitInRaid(unit) local u = U(unit) return u and u.inRaid and 1 or nil end
function UnitInParty() return nil end
function UnitHealth() return SECRET end
function UnitHealthMax() return SECRET end
function UnitPower() return 0 end
function UnitPowerMax() return 0 end
function UnitIsUnit() return false end
function UnitGUID() return nil end
function UnitClass() return "Priest", "PRIEST" end
function UnitIsDeadOrGhost() return false end
function AbbreviateNumbers(n) return tostring(n) end

-- The game's own carrier frames: shown whenever a carrier slot is filled,
-- even when the slot's details are hidden from addons.
for i = 1, 2 do CreateFrame("Frame", "ArenaEnemyMatchFrame" .. i):Hide() end
function sim.setCarrier(slot, unit)
    sim.units["arena" .. slot] = unit
    _G["ArenaEnemyMatchFrame" .. slot]:SetShown(unit ~= nil)
end

-- Driving the addon --------------------------------------------------------------

function sim.load(dir)
    local ns = {}
    for line in io.lines(dir .. "/WSGForever.toc") do
        local file = line:gsub("\r", ""):match("^([%w_]+%.lua)$")
        if file then
            local chunk = assert(loadfile(dir .. "/" .. file))
            chunk("WSGForever", ns)
        end
    end
    sim.fire("ADDON_LOADED", "WSGForever")
    sim.fire("PLAYER_LOGIN")
    sim.fire("PLAYER_ENTERING_WORLD")
    return ns
end

function sim.fire(event, ...)
    -- Copy first: handlers may create frames.
    local targets = {}
    for _, f in ipairs(sim.frames) do
        if f.events[event] and f.scripts.OnEvent then targets[#targets + 1] = f end
    end
    for _, f in ipairs(targets) do f.scripts.OnEvent(f, event, ...) end
end

-- Advance the clock in small steps, running timers and per-frame updates.
function sim.run(seconds, step)
    step = step or 0.05
    local stop = sim.time + seconds - 1e-9
    while sim.time < stop do
        sim.time = sim.time + step
        local due = {}
        for i = #sim.timers, 1, -1 do
            if sim.timers[i].at <= sim.time then due[#due + 1] = table.remove(sim.timers, i) end
        end
        for i = #due, 1, -1 do due[i].fn() end
        local n = #sim.frames
        for i = 1, n do
            local f = sim.frames[i]
            if f.scripts.OnUpdate and f:IsVisible() then f.scripts.OnUpdate(f, step) end
        end
    end
end

-- Every piece of text currently on screen.
function sim.texts()
    local out = {}
    local function walk(w)
        if not w.shown then return end
        for _, r in ipairs(w.regions) do
            if r.kind == "FontString" and r.shown and r.text and r.text ~= "" then out[#out + 1] = r.text end
        end
        for _, c in ipairs(w.children) do walk(c) end
    end
    for _, f in ipairs(sim.frames) do
        if not f.parent then walk(f) end
    end
    return out
end

function sim.showing(pattern)
    for _, t in ipairs(sim.texts()) do
        if t:find(pattern) then return t end
    end
end

return sim
