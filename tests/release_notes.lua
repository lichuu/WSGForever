-- Writes RELEASE_NOTES.md: the notes of the newest released version only,
-- taken from CHANGELOG.md. Release pages and CurseForge show this file, so
-- each release lists its own changes and not the whole history.
-- From the addon folder: lua5.1 tests/release_notes.lua
-- Returns the text when loaded with a first argument of "check" (the tests).

local function newest(path)
    local lines, on = {}, false
    for line in io.lines(path) do
        local version = line:match("^## (.+)$")
        if version then
            if on then break end
            on = version ~= "Unreleased"
        elseif on then
            lines[#lines + 1] = line
        end
    end
    while lines[#lines] == "" do lines[#lines] = nil end
    return table.concat(lines, "\n") .. "\n"
end

local mode, dir = ...
dir = dir or "."
local text = newest(dir .. "/CHANGELOG.md")
if mode == "check" then return text end
local f = assert(io.open(dir .. "/RELEASE_NOTES.md", "w"))
f:write(text)
f:close()
print("RELEASE_NOTES.md written")
