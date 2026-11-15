--[[
    Universal Hub game module: Depth Incremental (GameId 10769835283)
    Found with ClaudeBridge (2026-11-15):
      - Stairs:   PitRemotes.BuyStep:FireServer(stepNumber)        (no range check)
      - Upgrades: PitRemotes.BuyUpgrade:FireServer(name, buyMax)   (no range check)
                  level = attribute "Up_<name>", cost = PitConfig.UpgradeCost(name, level)
      - Worms:    PitRemotes.WormCollected:FireServer(id)          (server range-checks:
                  works next to the worm, not from 30 studs) -> we hop to each worm.
      - The game's own "Auto" stairs (SetPref AutoSteps) is group-locked server-side.
]]
local DEFAULT_UPGRADES = {
    "MoreCash", "FasterCash", "FasterDigs", "FossilLuck", "MoreFossils", "WalkSpeed",
    "WormCash", "WormMax", "WormSpawn", "WormValue",
}

return {
    Name = "Depth Incremental",
    Version = "1.0",

    Init = function(hub)
        local RS = hub.Services.ReplicatedStorage
        local LP = hub.Services.Players.LocalPlayer
        local PitConfig = require(RS:WaitForChild("PitConfig"))
        local Remotes = RS:WaitForChild("PitRemotes")

        local function attr(name) return LP:GetAttribute(name) or 0 end

        ------------------------------------------------------------------
        -- Stairs
        ------------------------------------------------------------------
        local stairs = hub.Tab:AddSection("Stairs")

        local function nextStep()
            local n = attr("Steps") + 1
            if not PitConfig.Steps[n] or PitConfig.StepBlocked(LP, n) then return end
            local currency = PitConfig.StepCurrency(n) or "Cash"
            local price = PitConfig.Price(n)
            if not price then return end
            return n, currency, math.floor(price * PitConfig.StepDiscount(LP, n))
        end

        local pendingStep = 0
        hub.autoToggle(stairs, hub.id("AutoStairs"), {
            Title = "Auto buy stairs",
            Description = "Buys the next stair as soon as you can afford it",
            Interval = 0.4,
        }, function()
            local n, currency, price = nextStep()
            -- don't re-send the same step while the server is still processing it
            if n and n > pendingStep and attr(currency) >= price then
                pendingStep = n
                Remotes.BuyStep:FireServer(n)
                task.delay(2, function() if pendingStep == n then pendingStep = 0 end end)
            end
        end)

        local stairInfo = stairs:AddParagraph({ Title = "Next stair", Content = "..." })
        hub.loop(1, function()
            local n, currency, price = nextStep()
            if n then
                stairInfo:SetDesc(("Stair %d costs %s %s (you have %s)"):format(
                    n, PitConfig.Short and PitConfig.Short(price) or tostring(price), currency,
                    PitConfig.Short and PitConfig.Short(attr(currency)) or tostring(attr(currency))))
            else
                stairInfo:SetDesc("No stair to buy here (all bought, or the next one is locked)")
            end
        end)

        ------------------------------------------------------------------
        -- Upgrades
        ------------------------------------------------------------------
        local upgrades = hub.Tab:AddSection("Upgrades")

        local names = {}
        for name in pairs(PitConfig.Upgrades) do table.insert(names, name) end
        table.sort(names)

        local default = {}
        for _, name in ipairs(DEFAULT_UPGRADES) do
            if PitConfig.Upgrades[name] then table.insert(default, name) end
        end

        local pick = upgrades:AddDropdown(hub.id("UpgradeList"), {
            Title = "Upgrades to buy",
            Description = "Locked boards are skipped automatically",
            Values = names,
            Multi = true,
            Default = default,
        })

        local backoff = {} -- upgrades the server refused (board not unlocked yet)
        hub.autoToggle(upgrades, hub.id("AutoUpgrades"), {
            Title = "Auto buy upgrades",
            Description = "Buys the selected upgrades whenever you can afford them",
            Interval = 0.5,
        }, function()
            local now = os.clock()
            for name, on in pairs(pick.Value) do
                local data = PitConfig.Upgrades[name]
                if on and data and (backoff[name] or 0) < now then
                    local level = attr("Up_" .. name)
                    local currency = data.currency or "Cash"
                    if level < data.max and attr(currency) >= PitConfig.UpgradeCost(name, level) then
                        Remotes.BuyUpgrade:FireServer(name, false)
                        task.delay(1.5, function()
                            if attr("Up_" .. name) == level then backoff[name] = os.clock() + 30 end
                        end)
                        backoff[name] = now + 0.6
                    end
                end
            end
        end)

        ------------------------------------------------------------------
        -- Worms
        ------------------------------------------------------------------
        local worms = hub.Tab:AddSection("Worms")

        -- The game's WormClient keeps live worms in a table {id = {pos=, born=, heading=, ...}}.
        local wormTable
        local function findWorms()
            if wormTable then return wormTable end
            if not getgc then return end
            for _, t in ipairs(getgc(true)) do
                if type(t) == "table" then
                    local _, v = next(t)
                    if type(v) == "table" and rawget(v, "born") and rawget(v, "heading") then
                        wormTable = t
                        return t
                    end
                end
            end
        end

        local minWorms = worms:AddSlider(hub.id("WormMin"), {
            Title = "Collect when at least",
            Default = 5, Min = 1, Max = 50, Increment = 1, Suffix = " worms",
        })

        local collecting = false
        hub.autoToggle(worms, hub.id("AutoWorms"), {
            Title = "Auto collect worms",
            Description = "Hops to every worm, collects it and puts you back",
            Interval = 3,
        }, function()
            if collecting then return end
            local list = findWorms()
            local hrp = hub.getRoot()
            if not (list and hrp) then return end

            local targets = {}
            for id, w in pairs(list) do
                local p = w.at or w.pos
                if typeof(p) == "Vector3" then table.insert(targets, { id = id, pos = p }) end
            end
            if #targets < minWorms.Value then return end

            collecting = true
            local home = hrp.CFrame
            for _, t in ipairs(targets) do
                if not hrp.Parent then break end
                hrp.CFrame = CFrame.new(t.pos + Vector3.new(0, 3, 0))
                hrp.AssemblyLinearVelocity = Vector3.zero
                task.wait(0.12)
                Remotes.WormCollected:FireServer(t.id)
            end
            task.wait(0.2)
            if hrp.Parent then hrp.CFrame = home end
            collecting = false
        end)

        local wormInfo = worms:AddParagraph({ Title = "Worms on your plot", Content = "..." })
        hub.loop(1, function()
            local list = findWorms()
            local n = 0
            if list then for _ in pairs(list) do n += 1 end end
            wormInfo:SetDesc(list and (n .. " waiting") or "Worm list not found yet")
        end)

        hub.addHelper("steps", function() return attr("Steps") end)
        hub.addHelper("cash", function() return attr("Cash") end)
    end,
}
