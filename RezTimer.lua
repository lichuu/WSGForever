local _, GK = ...

-- Port of the "BG Rez Timer" WeakAura: when several teammates come back to
-- life at once, a spirit healer wave just happened, so the next one is
-- rezInterval seconds later.

local PREFIX = "WSGForeverRez"

local Rez = {}
GK.RegisterModule("RezTimer", Rez)

local nextRez, lastTotal
-- Fewest teammates alive in the last moment, and when that was noted. A wave
-- is a jump up from it; teammates in one wave can pop up a tick or two apart.
local lowAlive, lowAt
local WAVE_WINDOW = 1.5
-- Enemy deaths on the scoreboard, total and at the last wave. The difference
-- is how many enemies will come back at the next wave.
local enemyDeaths, enemyDeathsAtWave = 0, 0

local function CountEnemyDeaths()
    if not GetNumBattlefieldScores then return end
    local mine = GK.PlayerFactionIndex()
    local total = 0
    for i = 1, GetNumBattlefieldScores() do
        local deaths, faction
        if C_PvP and C_PvP.GetScoreInfo then
            local info = C_PvP.GetScoreInfo(i)
            if info then deaths, faction = info.deaths, info.faction end
        else
            local _
            _, _, _, deaths, _, faction = GetBattlefieldScore(i)
        end
        deaths, faction = GK.Plain(deaths), GK.Plain(faction)
        if deaths and faction ~= nil and faction ~= mine then total = total + deaths end
    end
    enemyDeaths = total
    if enemyDeathsAtWave > enemyDeaths then enemyDeathsAtWave = enemyDeaths end
end

-- A spirit healer wave just happened.
local function Wave(now)
    nextRez = now + GK.db.rezInterval
    enemyDeathsAtWave = enemyDeaths
end

local function GroupAlive()
    local alive, total = 0, 0
    local n = GetNumGroupMembers()
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and n or (n - 1)
    for i = 1, count do
        local unit = prefix .. i
        if GK.Plain(UnitExists(unit)) then
            total = total + 1
            local dead = GK.Plain(UnitIsDeadOrGhost(unit))
            if dead == nil then return nil end -- can't read it, give up this tick
            if not dead then alive = alive + 1 end
        end
    end
    if not IsInRaid() then
        total = total + 1
        if not UnitIsDeadOrGhost("player") then alive = alive + 1 end
    end
    return alive, total
end

local function Threshold()
    if GK.InAV() then return GK.db.avRezThreshold end
    return GK.db.wsgRezThreshold
end

-- Spirit healers work the same in every battleground.
local function Active()
    return GK.InBattleground()
end

-- Seconds from a "battle has begun" message to the first wave, or nil if
-- the message isn't one.
local function StartOffset(msg)
    if type(msg) ~= "string" then return nil end
    local exact = GK.L.startOffsets[msg]
    if exact then return exact end
    if GK.Heard(msg, "battle") and GK.Heard(msg, "begin") then
        return GK.InWSG() and 5 or 0
    end
end

function Rez:SendSync()
    if not nextRez then GK.Print("Rez timer isn't running.") return end
    GK.SendAddon(PREFIX, string.format("%.1f", nextRez - GetTime()))
    GK.Print("Sent rez timer to your group.")
end

function Rez:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end

    local f = CreateFrame("Frame", "WSGForeverRezTimer", UIParent)
    f:SetSize(160, 36)
    f:SetFrameStrata("LOW") -- under bags and other windows
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    f.text:SetPoint("CENTER")
    GK.MakeMovable(f, "RezTimer", { "TOP", "TOP", 0, -110 })
    self.frame = f

    f:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
    f:RegisterEvent("PLAYER_UNGHOST")
    f:SetScript("OnEvent", GK.Safe("RezTimer event", function(_, event, a1, a2, _, a4)
        if event == "ZONE_CHANGED_NEW_AREA" then
            nextRez, lastTotal, lowAlive, lowAt = nil, nil, nil, nil
            enemyDeaths, enemyDeathsAtWave = 0, 0
        elseif event == "UPDATE_BATTLEFIELD_SCORE" then
            if Active() then CountEnemyDeaths() end
        elseif event == "PLAYER_UNGHOST" then
            -- Coming back at full health means the spirit healer just rezzed
            -- us. Health can lag the event, so look a moment later.
            local at = GetTime()
            if Active() then
                C_Timer.After(0.3, function()
                    if GK.HealthFraction("player") ~= 1 then return end
                    Wave(at)
                    GK.SendAddon(PREFIX, string.format("%.1f", nextRez - GetTime()))
                end)
            end
        elseif event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
            local offset = Active() and StartOffset(GK.Plain(a1))
            if offset then nextRez = GetTime() + GK.db.rezInterval + offset end
        elseif event == "CHAT_MSG_ADDON" and GK.Plain(a1) == PREFIX then
            local remaining = tonumber(GK.Plain(a2) or "")
            if remaining and GK.Plain(a4) ~= GK.FullName("player") then
                nextRez = GetTime() + remaining
            end
        end
    end))

    local elapsed, lastScoreRequest = 0, 0
    f:SetScript("OnUpdate", GK.Safe("RezTimer", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 then return end
        elapsed = 0
        local now = GetTime()

        -- While we're dead the game tells us the exact time to the next wave.
        local exact = GetAreaSpiritHealerTime and GK.Plain(GetAreaSpiritHealerTime())
        if exact and exact > 0 then nextRez = now + exact end

        local alive, total = GroupAlive()
        if alive then
            if total ~= lastTotal or not lowAlive or alive < lowAlive or now - lowAt > WAVE_WINDOW then
                lowAlive, lowAt = alive, now
            elseif alive >= lowAlive + Threshold() then
                Wave(now)
                lowAlive, lowAt = alive, now
            end
            lastTotal = total
        end

        if nextRez then
            if nextRez - now <= 0 then
                Wave(now)
            end
            local left = nextRez - now
            -- Refresh enemy deaths just before the wave so the count is current.
            if left <= 2 and now - lastScoreRequest > 1 and RequestBattlefieldScoreData then
                lastScoreRequest = now
                RequestBattlefieldScoreData()
            end
            local color = left < 5 and "|cffff4f4f" or "|cffffffff"
            -- Scoreboard deaths can be hidden mid-match, so also count the
            -- enemies the enemy frames currently show as dead.
            local ressing = math.max(0, enemyDeaths - enemyDeathsAtWave)
            if GK.DeadEnemyCount then ressing = math.max(ressing, GK.DeadEnemyCount()) end
            self.text:SetText(string.format("Rez: %s%.1f|r\nEnemies ressing: %d", color, left, ressing))
        else
            self.text:SetText("Rez: |cff7f7f7f?|r")
        end
    end))
end

function Rez:Refresh()
    if not self.frame then return end
    self.frame:SetShown(GK.db.rezTimer and (Active() or GK.ShouldShowAll()))
end
