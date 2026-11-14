--[[
    Universal Hub game module
    Save as  <GameId>.lua        -> whole game (lobby + all places)
         or  place_<PlaceId>.lua -> one place only
    Locally: UniversalHub/games/   |   Repo: games/
    Re-execute the hub after changing it.
]]
return {
    Name = "My Game",
    Version = "1.0",

    Init = function(hub)
        -- hub.Tab is this game's tab. Prefix option ids with hub.id() so they
        -- don't clash with other modules (they still save in your configs).
        local farm = hub.Tab:AddSection("Farming")

        -- A toggle that runs the function every Interval seconds while it's on
        hub.autoToggle(farm, hub.id("AutoCollect"), {
            Title = "Auto collect",
            Description = "Example: fires the collect remote",
            Interval = 0.5,
        }, function()
            -- your code, e.g.:
            -- hub.Services.ReplicatedStorage.Remotes.Collect:FireServer()
        end)

        farm:AddButton({
            Title = "Teleport to spawn",
            Callback = function()
                local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
                if spawn then hub.teleport(spawn) else hub.notify("Game", "No spawn found") end
            end,
        })

        -- Makes coins() usable in automation conditions / code steps
        hub.addHelper("coins", function() return hub.stat("Coins") end)

        hub.onUnload(function()
            -- clean up anything you created (connections made with hub.connect are cleaned automatically)
        end)
    end,
}
