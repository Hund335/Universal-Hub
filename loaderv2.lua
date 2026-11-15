--[[
    Universal Hub V2 loader
    Loads UniversalHubv2.lua from the newest commit (branch URLs can be stale)
    and retries when GitHub answers with an error page instead of the file.
]]
local REPO = "Hund335/Universal-Hub"

local function get(url)
    local ok, body = pcall(game.HttpGet, game, url)
    if ok and type(body) == "string" then return body end
end

local ref
for attempt = 1, 3 do
    local body = get("https://api.github.com/repos/" .. REPO .. "/commits/main")
    ref = body and body:match('"sha"%s*:%s*"(%x+)"')
    if ref then break end
    task.wait(attempt)
end
ref = ref or "main"
getgenv().UniversalHub_Ref = ref

local lastErr
for attempt = 1, 5 do
    local body = get("https://raw.githubusercontent.com/" .. REPO .. "/" .. ref .. "/UniversalHubv2.lua")
    if body then
        local fn, err = loadstring(body)
        if fn then return fn() end
        lastErr = err
    end
    task.wait(attempt)
end
error("Universal Hub: couldn't load V2 (" .. tostring(lastErr or "download failed") .. ")", 0)
