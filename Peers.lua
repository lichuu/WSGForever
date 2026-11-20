local _, GK = ...

-- Who else in your group runs WSGForever, and whether a newer version is
-- out. Each copy tells the group its version with a hidden addon message.
-- If the game blocks those messages, this simply stays empty.

local Peers = {}
GK.RegisterModule("Peers", Peers)

local PREFIX = "WSGForeverV"
local SEND_EVERY = 30 -- seconds between announcements

local seen = {}       -- name -> { version, at }
local lastSent = 0
local told = false    -- "a newer version is out" is said once per session

local MyVersion = GK.Version

-- "v0.6.0-beta1" -> 0, 6, 0, false (true when it is a full release).
local function Parse(v)
    if type(v) ~= "string" then return nil end
    local a, b, c, rest = v:match("^v?(%d+)%.(%d+)%.(%d+)(.*)$")
    if not a then return nil end
    return tonumber(a), tonumber(b), tonumber(c), rest == ""
end

-- True when theirs is newer than mine. Unreadable versions never are.
local function Newer(theirs, mine)
    local a1, b1, c1, r1 = Parse(theirs)
    local a2, b2, c2, r2 = Parse(mine)
    if not a1 or not a2 then return false end
    if a1 ~= a2 then return a1 > a2 end
    if b1 ~= b2 then return b1 > b2 end
    if c1 ~= c2 then return c1 > c2 end
    return r1 and not r2 -- same numbers: a release beats a beta
end
Peers.Newer = Newer

local function Announce(force)
    local now = GetTime()
    if not force and now - lastSent < SEND_EVERY then return end
    if not GK.ChatChannel() then return end
    lastSent = now
    GK.SendAddon(PREFIX, MyVersion())
end

local function Heard(version, sender)
    version, sender = GK.Plain(version), GK.Plain(sender)
    if type(version) ~= "string" or type(sender) ~= "string" then return end
    if sender == GK.FullName("player") or sender == GK.Plain((UnitName("player"))) then return end
    local first = not seen[sender]
    seen[sender] = { version = version, at = GetTime() }
    -- Answer a newcomer so they learn about us without waiting.
    if first then Announce() end
    if not told and Newer(version, MyVersion()) then
        told = true
        GK.Print(string.format("A newer WSGForever is out: %s (you have %s).", version, MyVersion()))
    end
end

-- Everyone heard from, newest version first.
local function List()
    local list = {}
    for name, p in pairs(seen) do list[#list + 1] = { name = name, version = p.version } end
    table.sort(list, function(a, b)
        if a.version ~= b.version then return Newer(a.version, b.version) end
        return a.name < b.name
    end)
    return list
end

function Peers:Summary()
    local n = #List()
    if n == 0 then return "No one else in your group has been seen with WSGForever." end
    return n == 1 and "1 other player in your group has WSGForever." or (n .. " other players in your group have WSGForever.")
end

function Peers:Print()
    GK.Print("You have version " .. MyVersion() .. ". " .. self:Summary())
    for _, p in ipairs(List()) do print("  " .. p.name .. "  " .. p.version) end
    Announce(true)
end

function Peers:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", GK.Safe("Peers", function(_, event, prefix, msg, _, sender)
        if event == "CHAT_MSG_ADDON" then
            if GK.Plain(prefix) == PREFIX then Heard(msg, sender) end
        else
            -- Leaving a group forgets who was in it.
            if not GK.ChatChannel() then wipe(seen) end
            Announce()
        end
    end))
end
