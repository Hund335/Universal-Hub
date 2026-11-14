--[[
    Universal Hub game module: "Logo for Brainrots!" (GameId 10122742965)

    Auto-collects the cash your brainrot stands produce.
    How the game does it: touching a stand's collector pad fires
        ReplicatedStorage.Remotes.CollectStandCash:FireServer("<stand number>")
    Pending cash per stand is in Player.Data.StandsCash["<stand number>"].
    The server doesn't check distance, so no teleporting is needed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local function getRemote()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("CollectStandCash")
end

local function getStandsCash()
    local data = LP:FindFirstChild("Data")
    return data and data:FindFirstChild("StandsCash")
end

-- Collects every stand from `first` to `last` that has cash waiting.
-- Returns how many stands were collected.
local function collectStands(first, last)
    local remote, standsCash = getRemote(), getStandsCash()
    if not remote or not standsCash then return 0 end
    local count = 0
    for i = first or 1, last or 24 do
        local cash = standsCash:FindFirstChild(tostring(i))
        if cash and cash.Value > 0 then
            remote:FireServer(tostring(i))
            count += 1
        end
    end
    return count
end

-- Total cash waiting in stands first..last
local function pendingCash(first, last)
    local standsCash = getStandsCash()
    if not standsCash then return 0 end
    local total = 0
    for i = first or 1, last or 24 do
        local cash = standsCash:FindFirstChild(tostring(i))
        if cash then total += cash.Value end
    end
    return total
end

return {
    Name = "Logo for Brainrots!",
    Version = "1.0",

    Init = function(hub)
        local section = hub.Tab:AddSection("Stand Cash")

        local first = section:AddSlider(hub.id("BR_First"), { Title = "From stand", Default = 1, Min = 1, Max = 24, Increment = 1 })
        local last = section:AddSlider(hub.id("BR_Last"), { Title = "To stand", Default = 24, Min = 1, Max = 24, Increment = 1 })
        local interval = section:AddSlider(hub.id("BR_Interval"), {
            Title = "Collect every",
            Default = 2, Min = 0.5, Max = 60, Increment = 0.5, Suffix = "s",
        })

        local function range()
            local a, b = first.Value, last.Value
            if a > b then a, b = b, a end
            return a, b
        end

        local autoToggle = section:AddToggle(hub.id("BR_AutoCollect"), {
            Title = "Auto collect stand cash",
            Description = "Collects every stand in the range that has cash waiting",
            Default = false,
        })

        local lastRun = 0
        hub.loop(0.25, function()
            if autoToggle.Value and os.clock() - lastRun >= interval.Value then
                lastRun = os.clock()
                collectStands(range())
            end
        end)

        section:AddButton({
            Title = "Collect now",
            Callback = function()
                local count = collectStands(range())
                hub.notify("Brainrots", count > 0 and ("Collected " .. count .. " stand" .. (count == 1 and "" or "s"))
                    or "No cash waiting in that range")
            end,
        })

        -- Usable in automations: Run code  collectStands()   /   If  standCash() > 1e15
        hub.addHelper("collectStands", function(a, b) return collectStands(a or 1, b or 24) end)
        hub.addHelper("standCash", function(a, b) return pendingCash(a or 1, b or 24) end)
    end,
}
