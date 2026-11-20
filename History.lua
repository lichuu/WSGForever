local _, GK = ...

-- Match history: one record per finished battleground (result, score, your
-- line from the scoreboard), kept across sessions, with a window to browse it.
-- It shows as a tab in the settings window (/fc history). Every value read from the game is checked
-- first, because Forever hides some of them from addons.

local History = {}
GK.RegisterModule("History", History)

local MAX_RECORDS = 300
local ROWS = 14
local ROW_H = 20
local FLAT = "Interface\\Buttons\\WHITE8X8"

-- Column layout: { title, width, how to align }.
local COLUMNS = {
    { "Date", 96, "LEFT" }, { "Battleground", 124, "LEFT" }, { "Result", 52, "LEFT" }, { "Score", 46, "CENTER" },
    { "Time", 50, "RIGHT" }, { "Kills", 44, "RIGHT" }, { "Deaths", 50, "RIGHT" }, { "Honor", 54, "RIGHT" },
    { "Caps", 40, "RIGHT" }, { "Returns", 56, "RIGHT" },
}

local views = {} -- each place the list is drawn
local inMatch, saved, startedAt = false, false, nil
local offset = 0

local function Num(v)
    v = GK.Plain(v)
    if type(v) == "number" then return v end
end

-- Recording -----------------------------------------------------------------

-- Your own line on the scoreboard, as plain numbers where the game allows.
local function MyScore()
    local me, short = GK.FullName("player"), GK.Plain((UnitName("player")))
    local n = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
    for i = 1, n do
        -- GetBattlefieldScore first: it is the call known to return readable
        -- numbers on Forever. The newer one is the fallback.
        if GetBattlefieldScore then
            local name, kills, hk, deaths, honor, _, _, _, _, _, damage, healing = GetBattlefieldScore(i)
            name = GK.Plain(name)
            if name and (name == me or name == short) then
                local row = { kills = Num(kills), hk = Num(hk), deaths = Num(deaths), honor = Num(honor),
                    damage = Num(damage), healing = Num(healing) }
                -- Battleground-specific columns: in Warsong Gulch, captures then returns.
                if GetBattlefieldStatData then
                    row.caps, row.returns = Num(GetBattlefieldStatData(i, 1)), Num(GetBattlefieldStatData(i, 2))
                end
                return row
            end
        elseif C_PvP and C_PvP.GetScoreInfo then
            local info = C_PvP.GetScoreInfo(i)
            local name = info and GK.Plain(info.name)
            if name and (name == me or name == short) then
                local row = { kills = Num(info.killingBlows), hk = Num(info.honorableKills), deaths = Num(info.deaths),
                    honor = Num(info.honorGained), damage = Num(info.damageDone), healing = Num(info.healingDone) }
                if type(info.stats) == "table" then
                    row.caps = info.stats[1] and Num(info.stats[1].pvpStatValue)
                    row.returns = info.stats[2] and Num(info.stats[2].pvpStatValue)
                end
                return row
            end
        end
    end
    return {}
end

-- Flag captures per team from the counts at the top of the screen ("2/3"):
-- the Alliance row is the upper one. Returns alliance, horde, or nil.
local function FlagScore()
    local container = _G.UIWidgetTopCenterContainerFrame
    if not container then return nil end
    local found = {}
    local function scan(frame, depth)
        if depth > 3 then return end
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:GetObjectType() == "FontString" then
                local text = GK.Plain(region:GetText())
                local top = region:GetTop()
                if type(text) == "string" and top then
                    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    local n = text:match("^%s*(%d+)%s*/%s*%d+%s*$")
                    if n then found[#found + 1] = { top = top, n = tonumber(n) } end
                end
            end
        end
        for _, child in ipairs({ frame:GetChildren() }) do scan(child, depth + 1) end
    end
    scan(container, 0)
    if #found ~= 2 then return nil end
    table.sort(found, function(a, b) return a.top > b.top end)
    return found[1].n, found[2].n
end

-- "win", "loss" or "draw", from which side the game says won (0 Horde, 1 Alliance).
local function Result(winner)
    winner = Num(winner)
    if winner == nil and GetBattlefieldWinner then winner = Num(GetBattlefieldWinner()) end
    if winner == nil then return nil end
    if winner ~= 0 and winner ~= 1 then return "draw" end
    return winner == GK.PlayerFactionIndex() and "win" or "loss"
end

local function Save(winner, duration)
    if saved or not GK.db.history then return end
    local result = Result(winner)
    if not result then return end
    saved = true
    local record = MyScore()
    record.at = time()
    record.map = GK.Plain((GetInstanceInfo())) or GK.Plain(GetZoneText()) or "Battleground"
    record.result = result
    record.who = GK.FullName("player")
    duration = Num(duration)
    if not duration and GetBattlefieldInstanceRunTime then
        local ms = Num(GetBattlefieldInstanceRunTime())
        duration = ms and ms > 0 and ms / 1000 or nil
    end
    if not duration and startedAt then duration = GetTime() - startedAt end
    record.seconds = duration and math.floor(duration + 0.5) or nil
    if GK.InWSG() then
        local alliance, horde = FlagScore()
        if alliance then
            local mine = GK.PlayerFactionIndex() == 0 and horde or alliance
            local theirs = GK.PlayerFactionIndex() == 0 and alliance or horde
            record.score = mine .. "-" .. theirs
        end
    end
    local list = GK.db.matches
    table.insert(list, 1, record)
    while #list > MAX_RECORDS do table.remove(list) end
    GK.Print(string.format("Match recorded: %s, %s. /fc history shows them all.", record.map,
        result == "win" and "|cff4fff4fwin|r" or result == "loss" and "|cffff4f4floss|r" or "draw"))
    History:Update()
end

-- Import ----------------------------------------------------------------------

-- Copies battlegrounds from Nova Instance Tracker's own history, for matches
-- played before this addon was recording. Returns how many were added.
function History:ImportNova()
    local nova = _G.NITdatabase
    local theirs = type(nova) == "table" and nova.global
    local added = 0
    if type(theirs) ~= "table" then return nil end
    local list = GK.db.matches
    local have = {}
    for _, m in ipairs(list) do have[#have + 1] = m end
    for _, realm in pairs(theirs) do
        local instances = type(realm) == "table" and realm.instances
        if type(instances) == "table" then
            for _, e in ipairs(instances) do
                if type(e) == "table" and e.type == "bg" and e.winningFaction and e.faction and (e.leftTime or e.enteredTime) then
                    local at = e.leftTime or e.enteredTime
                    local dup = false
                    for _, m in ipairs(have) do
                        if m.map == e.instanceName and math.abs((m.at or 0) - at) < 900 then dup = true break end
                    end
                    if not dup then
                        list[#list + 1] = {
                            at = at, map = e.instanceName, who = e.playerName, imported = true,
                            result = (e.winningFaction ~= 0 and e.winningFaction ~= 1) and "draw"
                                or (e.winningFaction == e.faction and "win" or "loss"),
                            -- Their times run from zoning in to leaving, so this includes the gate wait.
                            seconds = e.enteredTime and e.leftTime and (e.leftTime - e.enteredTime) or nil,
                            kills = e.kb, hk = e.hk, deaths = e.deaths, honor = e.honor, damage = e.damage, healing = e.healing,
                        }
                        added = added + 1
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
    while #list > MAX_RECORDS do table.remove(list) end
    return added
end

-- The window ------------------------------------------------------------------

local RESULT_TEXT = { win = "|cff4fff4fWin|r", loss = "|cffff4f4fLoss|r", draw = "|cffffd100Draw|r" }

local function Clock(seconds)
    if not seconds then return "" end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function Cells(m)
    return {
        date("%d %b %H:%M", m.at), m.map or "", RESULT_TEXT[m.result] or "", m.score or "", Clock(m.seconds),
        m.kills or "", m.deaths or "", m.honor or "", m.caps or "", m.returns or "",
    }
end

local function Summary()
    local list = GK.db.matches
    if #list == 0 then return "No matches recorded yet. Finish a battleground and it will show up here." end
    local wins, losses, honor, kills, deaths = 0, 0, 0, 0, 0
    for _, m in ipairs(list) do
        if m.result == "win" then wins = wins + 1 elseif m.result == "loss" then losses = losses + 1 end
        honor, kills, deaths = honor + (m.honor or 0), kills + (m.kills or 0), deaths + (m.deaths or 0)
    end
    local played = wins + losses
    return string.format("%d matches   |cff4fff4f%d won|r   |cffff4f4f%d lost|r   %d%% win rate   %d honor   %d kills, %d deaths",
        #list, wins, losses, played > 0 and math.floor(wins / played * 100 + 0.5) or 0, honor, kills, deaths)
end

-- Draws the history inside parent, starting at (x, y). Returns its height.
function History:BuildView(parent, x, y)
    local width = 0
    for _, c in ipairs(COLUMNS) do width = width + c[2] end
    local v = { parent = parent, rows = {} }

    v.summary = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    v.summary:SetPoint("TOPLEFT", x, y)

    -- Column titles, then the rows.
    local top = y - 24
    for r = 0, ROWS do
        local row = {}
        local cx = x
        for c, col in ipairs(COLUMNS) do
            local fs = parent:CreateFontString(nil, "OVERLAY", r == 0 and "GameFontNormalSmall" or "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", cx, top - r * ROW_H - (r > 0 and 2 or 0))
            fs:SetWidth(col[2] - 6)
            fs:SetJustifyH(col[3])
            fs:SetWordWrap(false)
            if r == 0 then fs:SetText(col[1]) end
            row[c] = fs
            cx = cx + col[2]
        end
        if r > 0 then v.rows[r] = row end
    end
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", x, top - ROW_H + 3)
    line:SetWidth(width)

    local bottom = top - (ROWS + 1) * ROW_H - 12
    v.page = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    v.page:SetPoint("TOPLEFT", x, bottom - 5)
    local clear = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clear:SetSize(110, 22)
    clear:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, bottom)
    clear:SetText("Clear history")
    clear:SetScript("OnClick", function()
        -- Ask twice: this can't be undone.
        if clear.armed then
            wipe(GK.db.matches)
            offset = 0
        end
        clear.armed = not clear.armed
        clear:SetText(clear.armed and "Really clear?" or "Clear history")
        History:Update()
    end)
    parent:HookScript("OnHide", function() clear.armed = false clear:SetText("Clear history") end)

    -- Only offered when Nova Instance Tracker is installed.
    if type(_G.NITdatabase) == "table" then
        local import = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        import:SetSize(230, 22)
        import:SetPoint("RIGHT", clear, "LEFT", -8, 0)
        import:SetText("Import from Nova Instance Tracker")
        import:SetScript("OnClick", function()
            local added = History:ImportNova()
            GK.Print(added and added > 0 and (added .. " matches imported from Nova Instance Tracker.")
                or "Nothing new to import from Nova Instance Tracker.")
            offset = 0
            History:Update()
        end)
    end

    parent:EnableMouseWheel(true)
    parent:SetScript("OnMouseWheel", function(_, delta)
        local last = math.max(0, #GK.db.matches - ROWS)
        offset = math.max(0, math.min(last, offset - delta * 3))
        History:Update()
    end)
    parent:HookScript("OnShow", function() offset = 0 History:Update() end)
    views[#views + 1] = v
    return y - bottom + 30
end

function History:Update()
    local list = GK.db.matches
    for _, v in ipairs(views) do
        if v.parent:IsVisible() then
            v.summary:SetText(Summary())
            for r, row in ipairs(v.rows) do
                local m = list[offset + r]
                local cells = m and Cells(m)
                for c, fs in ipairs(row) do fs:SetText(cells and tostring(cells[c]) or "") end
            end
            if #list > ROWS then
                v.page:SetText(string.format("%d-%d of %d. Scroll for more.", offset + 1, math.min(#list, offset + ROWS), #list))
            else
                v.page:SetText("")
            end
        end
    end
end

-- Opens the settings window on its history tab.
function History:Toggle()
    local o = GK.modules.Options
    if o then o:Toggle("history") end
end

-- Events ----------------------------------------------------------------------

function History:Init()
    GK.db.matches = GK.db.matches or {}
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
    f:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
    pcall(f.RegisterEvent, f, "PVP_MATCH_COMPLETE") -- not every client has this one
    f:SetScript("OnEvent", GK.Safe("Match history", function(_, event, a1, a2)
        if event == "PLAYER_ENTERING_WORLD" then
            local now = GK.InBattleground()
            if now and not inMatch then saved, startedAt = false, nil end
            inMatch = now
        elseif not GK.InBattleground() then
            return
        elseif event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
            local msg = GK.Plain(a1)
            if type(msg) == "string" and msg:lower():find("beg[ua]n") then startedAt = startedAt or GetTime() end
        elseif event == "PVP_MATCH_COMPLETE" then
            -- The scoreboard can lag the result by a moment.
            if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
            C_Timer.After(1.5, function() Save(a1, a2) end)
        elseif event == "UPDATE_BATTLEFIELD_SCORE" then
            if GetBattlefieldWinner and Num(GetBattlefieldWinner()) ~= nil then Save() end
        end
    end))
end

function History:Refresh()
    self:Update()
end
