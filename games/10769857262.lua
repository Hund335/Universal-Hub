--[[
    Universal Hub game module: REALISTIC HOME DEFENSE (GameId 10769857262)
    No recoil for the solo mode. The game uses ACS; every shot reads the
    scales below from ReplicatedStorage.ACS_Engine.GameRules.Config, so
    setting them to 0 removes camera climb, punch, shake, jolt and gun kick.

    Solo only: it switches itself off whenever anyone else is in the server.
]]
local KEYS = { "CameraRecoilScale", "GunRecoilScale", "CameraShake", "CameraJolt" }

return {
    Name = "Realistic Home Defense",
    Version = "1.0",

    Init = function(hub)
        local Players = hub.Services.Players
        local section = hub.Tab:AddSection("Solo mode")

        local ok, Config = pcall(function()
            return require(hub.Services.ReplicatedStorage:WaitForChild("ACS_Engine", 10).GameRules.Config)
        end)
        if not ok or type(Config) ~= "table" then
            section:AddParagraph({ Title = "No recoil", Content = "ACS config not found, not available here." })
            return
        end

        local original = {}
        for _, k in ipairs(KEYS) do original[k] = Config[k] end

        local status = section:AddParagraph({ Title = "Status", Content = "Off" })
        local toggle = section:AddToggle(hub.id("NoRecoil"), {
            Title = "No recoil",
            Description = "Only works while you're the only player in the server",
            Default = false,
        })

        local applied = false
        local function set(on)
            if on == applied then return end
            applied = on
            for _, k in ipairs(KEYS) do Config[k] = on and 0 or original[k] end
        end

        local function update()
            local solo = false
            set(toggle.Value and solo)
            if not toggle.Value then
                status:SetDesc("Off")
            elseif solo then
                status:SetDesc("Active (solo)")
            else
                status:SetDesc("Paused: other players are in this server")
            end
        end

        toggle:OnChanged(update)
        hub.connect(Players.PlayerAdded, update)
        hub.connect(Players.PlayerRemoving, function() task.defer(update) end)
        hub.onUnload(function() set(false) end)
    end,
}
