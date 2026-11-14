--[[
    Universal Hub loader
    Branch URLs (main / refs/heads/main) can be served from a stale cache for
    several minutes after an update. This asks GitHub for the newest commit and
    loads that exact commit's files, which are never stale.
]]
local REPO = "Hund335/Universal-Hub"

local ref = "main"
local ok, body = pcall(function()
    return game:HttpGet("https://api.github.com/repos/" .. REPO .. "/commits/main")
end)
if ok and type(body) == "string" then
    ref = body:match('"sha"%s*:%s*"(%x+)"') or ref
end

getgenv().UniversalHub_Ref = ref
return loadstring(game:HttpGet("https://raw.githubusercontent.com/" .. REPO .. "/" .. ref .. "/UniversalHub.lua"))()
