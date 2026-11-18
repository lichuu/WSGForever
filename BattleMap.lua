local _, GK = ...

-- The battlefield map (the small zone map, Shift-M): teammates drawn as
-- larger dots in their class colours, and a map size you can set with
-- /fc scale map. The game draws the dots itself; this only restyles them.

local Map = {}
GK.RegisterModule("BattleMap", Map)

local DOT = 12                        -- teammate dot size at 100%
local DOT_ATLAS = "WhiteCircle-RaidBlips" -- a plain dot that takes a class colour cleanly
local GROUPS = { "raid", "party" }

local original -- the game's own sizes and scale, to put back when turned off
local applied = false
local hooked = false

local function Parts()
    local map = _G.BattlefieldMapFrame
    local provider = map and map.groupMembersDataProvider
    if provider and provider.pin then return map, provider, provider.pin end
end

local function Apply()
    local map, provider, pin = Parts()
    if not map then return end
    if not original then
        original = { scale = map:GetScale(), sizes = {} }
        for unitType, size in pairs(provider:GetUnitPinSizesTable()) do original.sizes[unitType] = size end
    end
    -- "Show players" off in the map's own menu hides the dots; leave that alone.
    local showPlayers = not BattlefieldMapOptions or BattlefieldMapOptions.showPlayers ~= false
    if GK.db.battleMap then
        map:SetScale(GK.Scale("Battle map"))
        local hasDot = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(DOT_ATLAS)
        for _, unitType in ipairs(GROUPS) do
            if showPlayers then provider:SetUnitPinSize(unitType, DOT * GK.Scale("Map dots")) end
            if hasDot then pin:SetPinTexture(unitType, DOT_ATLAS) end
            pin:SetAppearanceField(unitType, "useClassColor", true)
        end
        pin:UpdateAppearanceData()
        applied = true
    elseif applied then
        map:SetScale(original.scale)
        for _, unitType in ipairs(GROUPS) do
            if showPlayers and original.sizes[unitType] then provider:SetUnitPinSize(unitType, original.sizes[unitType]) end
            pin:SetAppearanceField(unitType, "useClassColor", false)
        end
        pin:UpdateAppearanceData()
        applied = false
    end
end
Apply = GK.Safe("Battle map", Apply)

-- The game resets dot sizes when the map is shown or its options change.
local function Hook()
    local map = Parts()
    if hooked or not map then return end
    hooked = true
    map:HookScript("OnShow", Apply)
    if map.UpdateUnitsVisibility then hooksecurefunc(map, "UpdateUnitsVisibility", Apply) end
end

function Map:Init()
    -- The map loads on demand, so it may not exist yet.
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function()
        Hook()
        Apply()
    end)
end

function Map:Refresh()
    Hook()
    Apply()
end
