local _, GK = ...

-- The words the game uses in its battleground messages, per game language.
-- The addon follows the flags by reading these, so on a language with no
-- entry here it falls back to English and the carrier tracking, the match
-- timer and the rez timer miss their cues.
--
-- To add a language: copy the enUS block under its code ("deDE", "frFR", ...)
-- and replace each phrase with what that client shows. Only the keys that
-- differ need to be given; the rest fall back to English. On a language with
-- no entry, the report behind "Report a problem" in the settings window (and
-- /fc debug) lists the messages the addon saw and could not read, which is
-- what a translation is written from.
--
-- A list is "any of these, anywhere in the message", compared without regard
-- to (unaccented) upper and lower case.
local locales = {
    enUS = {
        -- Which flag a message is about.
        allianceFlag = { "alliance flag" },
        hordeFlag = { "horde flag" },
        -- What happened to it.
        dropped = { "dropped by" },
        captured = { "captured the" },
        returned = { "returned" },
        flagsReset = { "placed at their bases" },
        -- A Lua pattern that captures the name of whoever picked the flag up.
        pickedUpBy = "[Pp]icked up by (.-)!?$",
        -- The gates opening: "Let the battle for Warsong Gulch begin!",
        -- "The battle has begun!".
        battle = { "battle" },
        begin = { "begun", "begin!" },
        -- Match history starts its clock on these.
        started = { "begun", "began" },
        -- Whole messages, and how many seconds after them the first
        -- graveyard wave lands.
        startOffsets = {
            ["Let the battle for Warsong Gulch begin!"] = 5,
            ["The battle for Alterac Valley has begun!"] = 0,
        },
        -- In the tooltips of the game's capture counters (upper and lower
        -- case as the game writes them).
        widgetAllianceFlag = "Alliance flag",
        widgetHordeFlag = "Horde flag",
    },
}

local english = locales.enUS

-- Adds or extends a language.
function GK.AddLocale(code, phrases)
    local t = locales[code] or {}
    for k, v in pairs(phrases) do t[k] = v end
    locales[code] = t
end

-- Reads the game's messages as the given language from now on.
function GK.UseLocale(code)
    if code == "enGB" then code = "enUS" end
    GK.locale = code
    -- False when the addon has no phrases for this language at all.
    GK.localeKnown = locales[code] ~= nil
    GK.L = setmetatable({}, { __index = function(_, key)
        local own = locales[code]
        local v = own and own[key]
        if v == nil then v = english[key] end
        return v
    end })
end

GK.UseLocale(GetLocale and GetLocale() or "enUS")

-- True if the message holds any of the phrases listed under key.
function GK.Heard(msg, key)
    local lower = msg:lower()
    for _, phrase in ipairs(GK.L[key]) do
        if lower:find(phrase:lower(), 1, true) then return true end
    end
    return false
end

-- Messages nothing here could read, on a language with no entry: kept so
-- the report can list them for whoever writes the translation.
local MAX_UNREAD = 20

function GK.NoteUnread(msg)
    if GK.localeKnown or not GK.db then return end
    local list = GK.db.unreadMessages or {}
    GK.db.unreadMessages = list
    for _, seen in ipairs(list) do
        if seen == msg then return end
    end
    if #list < MAX_UNREAD then list[#list + 1] = msg end
end

function GK.PrintUnread()
    local list = GK.db and GK.db.unreadMessages
    if GK.localeKnown or not list or #list == 0 then return end
    GK.Print(string.format("game language %s has no translation yet. Messages the addon could not read:",
        tostring(GK.locale)))
    for _, msg in ipairs(list) do GK.Print("  " .. msg) end
end
