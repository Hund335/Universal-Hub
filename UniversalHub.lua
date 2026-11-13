--[[
    Universal Hub
    Built on the custom Fluent UI (https://github.com/Hund335/Fluent-Custom)

    Tabs:
      Movement  - walkspeed, jump height, infinite jump, fly, noclip, gravity, click teleport
      Teleport  - instant / tween teleport mode + tween speed, teleport to player, waypoints per game
      Scripts   - script loader (URL or loadstring code), saved scripts, auto-run per game
      Visuals   - fullbright, no fog, FOV, infinite zoom out, ESP, FPS unlock
      Misc      - anti-AFK, rejoin, server hop
      Settings  - notifications, reset to defaults, unload, theme + config files (save/load/autoload)

    Files (executor workspace folder):
      UniversalHub/waypoints.json   - all waypoints (filtered by PlaceId in game)
      UniversalHub/scripts.json     - saved scripts
      UniversalHub/configs/*.json   - settings configs (SaveManager)
]]

-- Re-executing cleanly unloads the previous instance first
if getgenv and getgenv().UniversalHub_Unload then
    pcall(getgenv().UniversalHub_Unload)
end

----------------------------------------------------------------------
-- Services
----------------------------------------------------------------------
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local UIS             = game:GetService("UserInputService")
local TweenService    = game:GetService("TweenService")
local HttpService     = game:GetService("HttpService")
local Lighting        = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local VirtualUser     = game:GetService("VirtualUser")

local LP    = Players.LocalPlayer
local Mouse = LP:GetMouse()

----------------------------------------------------------------------
-- Libraries
----------------------------------------------------------------------
local Library          = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hund335/Fluent-Custom/main/Fluent.lua"))()
local SaveManager      = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()
local Options = Library.Options

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local FOLDER = "UniversalHub"
local hasFS = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
local clipboard = setclipboard or toclipboard or (syn and syn.write_clipboard)

if hasFS and typeof(makefolder) == "function" and typeof(isfolder) == "function" then
    pcall(function()
        if not isfolder(FOLDER) then makefolder(FOLDER) end
    end)
end

local function loadJSON(name, default)
    if not hasFS then return default end
    local path = FOLDER .. "/" .. name
    local okExists, exists = pcall(isfile, path)
    if not okExists or not exists then return default end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if ok and type(data) == "table" then return data end
    return default
end

local function saveJSON(name, data)
    if not hasFS then return false end
    return (pcall(function()
        writefile(FOLDER .. "/" .. name, HttpService:JSONEncode(data))
    end))
end

-- `silent` suppresses toggle notifications while building the UI / loading configs
local silent = true
local function notify(title, content, duration, force)
    if not force then
        if silent then return end
        if Options.ShowNotifications and not Options.ShowNotifications.Value then return end
    end
    Library:Notify({ Title = title, Content = content, Duration = duration or 3 })
end

local function copy(text)
    if clipboard then
        clipboard(text)
        notify("Copied", #text > 80 and text:sub(1, 77) .. "..." or text, 4, true)
    else
        notify("Clipboard", "Your executor doesn't support setclipboard.", 4, true)
    end
end

local Connections = {}
local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(Connections, c)
    return c
end

local function getHum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getHRP()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function uniqueName(name, taken)
    if not taken[name] then return name end
    local i = 2
    while taken[name .. " (" .. i .. ")"] do i += 1 end
    return name .. " (" .. i .. ")"
end

local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end

----------------------------------------------------------------------
-- Teleport core (instant or tween)
----------------------------------------------------------------------
local activeTween
local tweening = false

local function cancelTween()
    if activeTween then activeTween:Cancel() end
    activeTween = nil
    tweening = false
end

local function teleportTo(cf)
    local hrp = getHRP()
    if not hrp then
        notify("Teleport", "No character found.", 3, true)
        return
    end
    cancelTween()
    if Options.TPMode.Value == "Tween" then
        local dist = (hrp.Position - cf.Position).Magnitude
        local duration = dist / math.max(Options.TweenSpeed.Value, 1)
        local tween = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = cf })
        activeTween, tweening = tween, true
        tween.Completed:Once(function()
            if activeTween == tween then
                activeTween, tweening = nil, false
            end
        end)
        tween:Play()
    else
        hrp.CFrame = cf
    end
end

----------------------------------------------------------------------
-- Window & tabs
----------------------------------------------------------------------
local Window = Library:CreateWindow({
    Title = "Universal Hub",
    SubTitle = "v1.0",
    TabWidth = 160,
    Size = UDim2.fromOffset(600, 480),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightShift,
})

local Tabs = {
    Movement = Window:AddTab({ Title = "Movement", Icon = "move" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "map-pin" }),
    Scripts  = Window:AddTab({ Title = "Scripts",  Icon = "terminal" }),
    Visuals  = Window:AddTab({ Title = "Visuals",  Icon = "eye" }),
    Misc     = Window:AddTab({ Title = "Misc",     Icon = "wrench" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

----------------------------------------------------------------------
-- Movement tab
----------------------------------------------------------------------
do
    local S = Tabs.Movement:AddSection("Speed & Jump")
    S:AddToggle("WalkSpeedEnabled", { Title = "WalkSpeed", Description = "Re-applied on respawn and if the game resets it", Default = false })
    S:AddSlider("WalkSpeed", { Title = "Speed", Default = 16, Min = 0, Max = 500, Increment = 1 })
    S:AddKeybind("WalkSpeedKey", { Title = "WalkSpeed keybind", Mode = "Toggle", Default = "V" })

    S:AddToggle("JumpEnabled", { Title = "Jump Height", Default = false })
    S:AddSlider("JumpHeight", { Title = "Height", Default = 7.2, Min = 0, Max = 200, Increment = 0.1, Suffix = " studs" })

    S:AddToggle("InfiniteJump", { Title = "Infinite Jump", Description = "Jump again while in the air", Default = false })
    S:AddKeybind("InfiniteJumpKey", { Title = "Infinite Jump keybind", Mode = "Toggle", Default = "J" })

    local F = Tabs.Movement:AddSection("Fly")
    F:AddParagraph({ Title = "Controls", Content = "WASD to move (follows camera), Space = up, LeftControl = down." })
    F:AddToggle("Fly", { Title = "Fly", Default = false })
    F:AddSlider("FlySpeed", { Title = "Fly Speed", Default = 50, Min = 1, Max = 500, Increment = 1 })
    F:AddKeybind("FlyKey", { Title = "Fly keybind", Mode = "Toggle", Default = "G" })

    local N = Tabs.Movement:AddSection("Noclip")
    N:AddToggle("Noclip", { Title = "Noclip", Description = "Walk through walls", Default = false })
    N:AddKeybind("NoclipKey", { Title = "Noclip keybind", Mode = "Toggle", Default = "N" })

    local G = Tabs.Movement:AddSection("Gravity")
    G:AddToggle("GravityEnabled", { Title = "Custom Gravity", Default = false })
    G:AddSlider("Gravity", { Title = "Gravity", Description = "Roblox default is 196.2", Default = 196.2, Min = 0, Max = 500, Increment = 0.1 })
    G:AddButton({
        Title = "Reset gravity slider",
        Description = "Sets the slider back to 196.2",
        Callback = function() Options.Gravity:SetValue(196.2) end,
    })

    local C = Tabs.Movement:AddSection("Click Teleport")
    C:AddToggle("ClickTP", { Title = "Click Teleport", Description = "Hold LeftControl and click to teleport (uses the Teleport mode)", Default = false })
end

----------------------------------------------------------------------
-- Teleport tab
----------------------------------------------------------------------
local Waypoints = loadJSON("waypoints.json", {})
local WaypointListSection

do
    local S = Tabs.Teleport:AddSection("Teleport Settings")
    S:AddDropdown("TPMode", { Title = "Teleport Mode", Description = "Used by waypoints, players and click TP", Values = { "Instant", "Tween" }, Default = "Instant" })
    S:AddSlider("TweenSpeed", { Title = "Tween Speed", Default = 100, Min = 10, Max = 1000, Increment = 5, Suffix = " st/s" })
    S:AddToggle("TweenNoclip", { Title = "Noclip while tweening", Description = "Avoids getting stuck on walls", Default = true })
    S:AddButton({ Title = "Cancel tween", Callback = function() cancelTween() notify("Teleport", "Tween cancelled.") end })

    local P = Tabs.Teleport:AddSection("Players")
    P:AddDropdown("TPPlayer", { Title = "Player", Values = {}, Default = nil })
    P:AddButton({
        Title = "Teleport to player",
        Callback = function()
            local name = Options.TPPlayer.Value
            local target = name and Players:FindFirstChild(name)
            local hrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then
                notify("Teleport", "Select a player that has a character.", 3, true)
                return
            end
            teleportTo(hrp.CFrame * CFrame.new(0, 0, 3))
            notify("Teleport", "Teleporting to " .. name)
        end,
    })

    local W = Tabs.Teleport:AddSection("Create Waypoint")
    W:AddParagraph({ Title = "This game", Content = "PlaceId: " .. game.PlaceId .. "\nWaypoints only show up in the game they were saved in." })
    W:AddInput("WaypointName", { Title = "Name", Default = "", Placeholder = "e.g. Shop, Boss, Spawn" })
    W:AddInput("WaypointCoords", { Title = "Coordinates (optional)", Default = "", Placeholder = "x, y, z | PlaceId  (empty = current spot)" })
end

----------------------------------------------------------------------
-- Waypoint logic
----------------------------------------------------------------------
local function saveWaypoints() saveJSON("waypoints.json", Waypoints) end

local function gameWaypoints()
    local list = {}
    for _, w in ipairs(Waypoints) do
        if tonumber(w.placeId) == game.PlaceId then table.insert(list, w) end
    end
    return list
end

local function findWaypoint(name)
    for i, w in ipairs(Waypoints) do
        if tonumber(w.placeId) == game.PlaceId and w.name == name then return w, i end
    end
end

local function takenWaypointNames()
    local taken = {}
    for _, w in ipairs(gameWaypoints()) do taken[w.name] = true end
    return taken
end

local function waypointCFrame(w)
    local pos = Vector3.new(w.x, w.y, w.z)
    local look = Vector3.new(w.lx or 0, 0, w.lz or 0)
    if look.Magnitude < 0.01 then return CFrame.new(pos) end
    return CFrame.lookAt(pos, pos + look)
end

local function coordString(x, y, z, placeId)
    return string.format("%.2f, %.2f, %.2f | %d", x, y, z, placeId)
end

local function parseCoords(text)
    local nums = {}
    for n in text:gmatch("-?%d+%.?%d*") do table.insert(nums, tonumber(n)) end
    if #nums < 3 then return nil end
    return Vector3.new(nums[1], nums[2], nums[3]), nums[4]
end

local waypointButtons = {}
local function renderWaypoints()
    for _, b in ipairs(waypointButtons) do pcall(function() b:Destroy() end) end
    table.clear(waypointButtons)

    local list = gameWaypoints()
    local names = {}
    if #list == 0 then
        table.insert(waypointButtons, WaypointListSection:AddButton({
            Title = "No waypoints for this game yet",
            Description = "Save one in the section above",
            Callback = function() end,
        }))
    end
    for _, w in ipairs(list) do
        table.insert(names, w.name)
        table.insert(waypointButtons, WaypointListSection:AddButton({
            Title = w.name,
            Description = string.format("%.1f, %.1f, %.1f", w.x, w.y, w.z),
            Callback = function()
                teleportTo(waypointCFrame(w))
                notify("Waypoint", "Teleporting to " .. w.name)
            end,
        }))
    end
    Options.WaypointSelect:SetValues(names)
    Options.WaypointSelect:SetValue(nil)
end

local function addWaypoint()
    local name = trim(Options.WaypointName.Value)
    local coordText = trim(Options.WaypointCoords.Value)
    local pos, placeId, look

    if coordText ~= "" then
        pos, placeId = parseCoords(coordText)
        if not pos then
            notify("Waypoint", "Couldn't read coordinates. Use: x, y, z | PlaceId", 4, true)
            return
        end
    else
        local hrp = getHRP()
        if not hrp then
            notify("Waypoint", "No character found.", 3, true)
            return
        end
        pos, look = hrp.Position, hrp.CFrame.LookVector
    end
    placeId = placeId or game.PlaceId
    if name == "" then name = "Waypoint" end
    if placeId == game.PlaceId then name = uniqueName(name, takenWaypointNames()) end

    table.insert(Waypoints, {
        name = name, placeId = placeId,
        x = pos.X, y = pos.Y, z = pos.Z,
        lx = look and look.X or 0, lz = look and look.Z or 0,
    })
    saveWaypoints()
    renderWaypoints()
    Options.WaypointName:SetValue("")
    Options.WaypointCoords:SetValue("")
    if placeId == game.PlaceId then
        notify("Waypoint", "Saved \"" .. name .. "\"", 3, true)
    else
        notify("Waypoint", "Saved \"" .. name .. "\" for PlaceId " .. placeId .. " (shows up in that game)", 4, true)
    end
end

do
    local W = Tabs.Teleport:AddSection("Create Waypoint")
    W:AddParagraph({ Title = "This game", Content = "PlaceId: " .. game.PlaceId .. "\nWaypoints only show up in the game they were saved in." })
    W:AddInput("WaypointName", { Title = "Name", Default = "", Placeholder = "e.g. Shop, Boss, Spawn" })
    W:AddInput("WaypointCoords", { Title = "Coordinates (optional)", Default = "", Placeholder = "x, y, z | PlaceId  (empty = current spot)" })
    W:AddButton({ Title = "Save waypoint", Description = "Uses your position, or the coordinates field", Callback = addWaypoint })
    W:AddButton({
        Title = "Copy current coordinates",
        Description = "Format: x, y, z | PlaceId (paste it into the coordinates field later)",
        Callback = function()
            local hrp = getHRP()
            if not hrp then return notify("Waypoint", "No character found.", 3, true) end
            local p = hrp.Position
            copy(coordString(p.X, p.Y, p.Z, game.PlaceId))
        end,
    })

    W = Tabs.Teleport:AddSection("Manage Waypoints")
    W:AddDropdown("WaypointSelect", { Title = "Waypoint", Values = {}, Default = nil })
    W:AddInput("WaypointRename", { Title = "New name", Default = "", Placeholder = "Rename selected waypoint to..." })
    W:AddButton({
        Title = "Rename selected",
        Callback = function()
            local w = findWaypoint(Options.WaypointSelect.Value)
            local newName = trim(Options.WaypointRename.Value)
            if not w then return notify("Waypoint", "Select a waypoint first.", 3, true) end
            if newName == "" then return notify("Waypoint", "Type a new name first.", 3, true) end
            local taken = takenWaypointNames()
            taken[w.name] = nil
            w.name = uniqueName(newName, taken)
            saveWaypoints()
            renderWaypoints()
            Options.WaypointRename:SetValue("")
            notify("Waypoint", "Renamed to \"" .. w.name .. "\"", 3, true)
        end,
    })
    W:AddButton({
        Title = "Copy selected",
        Callback = function()
            local w = findWaypoint(Options.WaypointSelect.Value)
            if not w then return notify("Waypoint", "Select a waypoint first.", 3, true) end
            copy(coordString(w.x, w.y, w.z, w.placeId))
        end,
    })
    W:AddButton({
        Title = "Delete selected",
        Callback = function()
            local w, i = findWaypoint(Options.WaypointSelect.Value)
            if not w then return notify("Waypoint", "Select a waypoint first.", 3, true) end
            Window:Dialog({
                Title = "Delete waypoint",
                Content = "Delete \"" .. w.name .. "\"?",
                Buttons = {
                    { Title = "Delete", Callback = function()
                        table.remove(Waypoints, i)
                        saveWaypoints()
                        renderWaypoints()
                        notify("Waypoint", "Deleted \"" .. w.name .. "\"", 3, true)
                    end },
                    { Title = "Cancel" },
                },
            })
        end,
    })

    WaypointListSection = Tabs.Teleport:AddSection("Waypoints in this game (click to teleport)")
end

----------------------------------------------------------------------
-- Scripts tab
----------------------------------------------------------------------
local SavedScripts = loadJSON("scripts.json", {})
local ScriptListSection
local placeKey = tostring(game.PlaceId)

local function saveScripts() saveJSON("scripts.json", SavedScripts) end

local function findScript(name)
    for i, s in ipairs(SavedScripts) do
        if s.name == name then return s, i end
    end
end

local function runScript(entry)
    task.spawn(function()
        local src = trim(entry.source)
        if src:match("^https?://") then
            local ok, body = pcall(function() return game:HttpGet(src) end)
            if not ok then
                return notify("Script error", entry.name .. ": couldn't download (" .. tostring(body) .. ")", 6, true)
            end
            src = body
        end
        local fn, compileErr = loadstring(src)
        if not fn then
            return notify("Script error", entry.name .. ": " .. tostring(compileErr), 6, true)
        end
        notify("Scripts", "Running \"" .. entry.name .. "\"", 3, true)
        local ok, runErr = pcall(fn)
        if not ok then
            notify("Script error", entry.name .. ": " .. tostring(runErr), 6, true)
        end
    end)
end

local scriptButtons = {}
local function renderScripts()
    for _, b in ipairs(scriptButtons) do pcall(function() b:Destroy() end) end
    table.clear(scriptButtons)

    local names = {}
    if #SavedScripts == 0 then
        table.insert(scriptButtons, ScriptListSection:AddButton({
            Title = "No scripts saved yet",
            Description = "Add one in the section above",
            Callback = function() end,
        }))
    end
    for _, s in ipairs(SavedScripts) do
        table.insert(names, s.name)
        local preview = trim(s.source):gsub("%s+", " ")
        if #preview > 60 then preview = preview:sub(1, 57) .. "..." end
        local auto = (s.autorun and s.autorun[placeKey]) and "[Auto-runs here]  " or ""
        table.insert(scriptButtons, ScriptListSection:AddButton({
            Title = s.name,
            Description = auto .. preview,
            Callback = function() runScript(s) end,
        }))
    end
    Options.ScriptSelect:SetValues(names)
    Options.ScriptSelect:SetValue(nil)
end

local function addScript(runAfter)
    local name = trim(Options.ScriptName.Value)
    local source = trim(Options.ScriptSource.Value)
    if source == "" then return notify("Scripts", "Paste a URL or loadstring code first.", 3, true) end
    if name == "" then name = "Script" end
    local taken = {}
    for _, s in ipairs(SavedScripts) do taken[s.name] = true end
    name = uniqueName(name, taken)

    local entry = { name = name, source = source, autorun = {} }
    table.insert(SavedScripts, entry)
    saveScripts()
    renderScripts()
    Options.ScriptName:SetValue("")
    Options.ScriptSource:SetValue("")
    notify("Scripts", "Added \"" .. name .. "\"", 3, true)
    if runAfter then runScript(entry) end
end

do
    local A = Tabs.Scripts:AddSection("Add Script")
    A:AddParagraph({
        Title = "How it works",
        Content = "Paste either a raw URL (https://...) or full code like loadstring(game:HttpGet(\"...\"))(). Each saved script becomes a button below.",
    })
    A:AddInput("ScriptName", { Title = "Name", Default = "", Placeholder = "e.g. Infinite Yield" })
    A:AddInput("ScriptSource", { Title = "URL or code", Default = "", Placeholder = "https://... or loadstring(...)()" })
    A:AddButton({ Title = "Add script", Callback = function() addScript(false) end })
    A:AddButton({ Title = "Add & run", Callback = function() addScript(true) end })

    local M = Tabs.Scripts:AddSection("Manage Scripts")
    M:AddDropdown("ScriptSelect", { Title = "Script", Values = {}, Default = nil })
    M:AddButton({
        Title = "Toggle auto-run in this game",
        Description = "Runs automatically when the hub loads in this game",
        Callback = function()
            local s = findScript(Options.ScriptSelect.Value)
            if not s then return notify("Scripts", "Select a script first.", 3, true) end
            s.autorun = type(s.autorun) == "table" and s.autorun or {}
            s.autorun[placeKey] = (not s.autorun[placeKey]) or nil
            saveScripts()
            renderScripts()
            notify("Scripts", "\"" .. s.name .. "\" auto-run here: " .. (s.autorun[placeKey] and "ON" or "OFF"), 3, true)
        end,
    })
    M:AddButton({
        Title = "Copy selected source",
        Callback = function()
            local s = findScript(Options.ScriptSelect.Value)
            if not s then return notify("Scripts", "Select a script first.", 3, true) end
            copy(s.source)
        end,
    })
    M:AddButton({
        Title = "Delete selected",
        Callback = function()
            local s, i = findScript(Options.ScriptSelect.Value)
            if not s then return notify("Scripts", "Select a script first.", 3, true) end
            Window:Dialog({
                Title = "Delete script",
                Content = "Delete \"" .. s.name .. "\"?",
                Buttons = {
                    { Title = "Delete", Callback = function()
                        table.remove(SavedScripts, i)
                        saveScripts()
                        renderScripts()
                        notify("Scripts", "Deleted \"" .. s.name .. "\"", 3, true)
                    end },
                    { Title = "Cancel" },
                },
            })
        end,
    })

    ScriptListSection = Tabs.Scripts:AddSection("Your Scripts (click to run)")
end

----------------------------------------------------------------------
-- Visuals tab
----------------------------------------------------------------------
local canFPS = typeof(setfpscap) == "function"
do
    local L = Tabs.Visuals:AddSection("Lighting")
    L:AddToggle("Fullbright", { Title = "Fullbright", Description = "Removes darkness and shadows", Default = false })
    L:AddKeybind("FullbrightKey", { Title = "Fullbright keybind", Mode = "Toggle", Default = "L" })
    L:AddToggle("NoFog", { Title = "No Fog", Default = false })

    local C = Tabs.Visuals:AddSection("Camera")
    C:AddToggle("FOVEnabled", { Title = "Custom FOV", Default = false })
    C:AddSlider("FOV", { Title = "Field of View", Default = 70, Min = 30, Max = 120, Increment = 1 })
    C:AddToggle("InfiniteZoom", { Title = "Infinite Zoom Out", Description = "Removes the max zoom distance and first-person lock", Default = false })

    local E = Tabs.Visuals:AddSection("ESP")
    E:AddToggle("ESP", { Title = "Player ESP", Description = "Highlights players through walls", Default = false })
    E:AddKeybind("ESPKey", { Title = "ESP keybind", Mode = "Toggle", Default = "K" })
    E:AddToggle("ESPNames", { Title = "Show names", Default = true })
    E:AddToggle("ESPDistance", { Title = "Show distance", Default = true })
    E:AddToggle("ESPTeamCheck", { Title = "Hide teammates", Default = false })
    E:AddToggle("ESPTeamColor", { Title = "Use team colors", Default = false })
    E:AddColorpicker("ESPColor", { Title = "ESP color", Default = Color3.fromRGB(255, 70, 70) })
    E:AddSlider("ESPMaxDistance", { Title = "Max distance", Default = 2000, Min = 50, Max = 10000, Increment = 50, Suffix = " studs" })

    local P = Tabs.Visuals:AddSection("Performance")
    if canFPS then
        P:AddToggle("FPSUnlock", { Title = "FPS Unlock", Default = false })
        P:AddSlider("FPSCap", { Title = "FPS cap", Default = 240, Min = 30, Max = 1000, Increment = 10 })
    else
        P:AddParagraph({ Title = "FPS Unlock", Content = "Not supported by your executor (no setfpscap)." })
    end
end

----------------------------------------------------------------------
-- Misc tab
----------------------------------------------------------------------
do
    local M = Tabs.Misc:AddSection("Session")
    M:AddToggle("AntiAFK", { Title = "Anti-AFK", Description = "Prevents the 20 minute idle kick", Default = true })

    local S = Tabs.Misc:AddSection("Server")
    S:AddButton({
        Title = "Rejoin",
        Description = "Rejoins this server",
        Callback = function()
            notify("Server", "Rejoining...", 3, true)
            if #Players:GetPlayers() <= 1 then
                TeleportService:Teleport(game.PlaceId, LP)
            else
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
            end
        end,
    })
    S:AddButton({
        Title = "Server hop",
        Description = "Joins a different public server of this game",
        Callback = function()
            notify("Server", "Searching for a server...", 3, true)
            task.spawn(function()
                local ok, body = pcall(function()
                    return game:HttpGet(("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId))
                end)
                local okDecode, data = pcall(function() return HttpService:JSONDecode(body) end)
                if not ok or not okDecode or type(data) ~= "table" or type(data.data) ~= "table" then
                    return notify("Server", "Couldn't fetch the server list.", 4, true)
                end
                local candidates = {}
                for _, s in ipairs(data.data) do
                    if s.id ~= game.JobId and tonumber(s.playing) and tonumber(s.maxPlayers) and s.playing < s.maxPlayers then
                        table.insert(candidates, s.id)
                    end
                end
                if #candidates == 0 then
                    return notify("Server", "No other servers with space found.", 4, true)
                end
                TeleportService:TeleportToPlaceInstance(game.PlaceId, candidates[math.random(1, #candidates)], LP)
            end)
        end,
    })
    S:AddButton({ Title = "Copy PlaceId", Callback = function() copy(tostring(game.PlaceId)) end })
    S:AddButton({ Title = "Copy JobId", Callback = function() copy(game.JobId) end })
end

----------------------------------------------------------------------
-- Feature state: originals are stored when a feature turns on and
-- restored when it turns off (or when the hub unloads)
----------------------------------------------------------------------
local Orig = {}

-- Keeps obj[prop] = value while `enabled`; restores the original value afterwards.
-- If obj changes (e.g. new Humanoid after respawn) the original value is kept.
local function hold(key, enabled, obj, prop, value)
    local saved = Orig[key]
    if enabled and obj then
        if not saved then
            saved = { obj = obj, value = obj[prop] }
            Orig[key] = saved
        end
        saved.obj = obj
        if obj[prop] ~= value then obj[prop] = value end
    elseif saved then
        Orig[key] = nil
        pcall(function()
            local target = obj or saved.obj
            target[prop] = saved.value
        end)
    end
end

local atmosphereOrig = {}

local function applyState(off)
    local function on(idx)
        return not off and Options[idx] ~= nil and Options[idx].Value == true
    end

    local hum = getHum()
    local cam = workspace.CurrentCamera

    -- WalkSpeed
    if hum or off then
        hold("WalkSpeed", on("WalkSpeedEnabled"), hum, "WalkSpeed", Options.WalkSpeed.Value)
    end

    -- Jump (supports both JumpPower and JumpHeight games)
    if hum or off then
        local jumpOn = on("JumpEnabled")
        local height = Options.JumpHeight.Value
        local usePower = hum and hum.UseJumpPower
        hold("JumpPower", jumpOn and usePower, hum, "JumpPower", math.sqrt(2 * workspace.Gravity * height))
        hold("JumpHeight", jumpOn and not usePower, hum, "JumpHeight", height)
    end

    -- Gravity
    hold("Gravity", on("GravityEnabled"), workspace, "Gravity", Options.Gravity.Value)

    -- Fullbright
    local fb = on("Fullbright")
    hold("Brightness", fb, Lighting, "Brightness", 2)
    hold("ClockTime", fb, Lighting, "ClockTime", 14)
    hold("GlobalShadows", fb, Lighting, "GlobalShadows", false)
    hold("Ambient", fb, Lighting, "Ambient", Color3.fromRGB(178, 178, 178))
    hold("OutdoorAmbient", fb, Lighting, "OutdoorAmbient", Color3.fromRGB(178, 178, 178))

    -- No fog
    local nf = on("NoFog")
    hold("FogEnd", nf, Lighting, "FogEnd", 1e9)
    if nf then
        for _, a in ipairs(Lighting:GetChildren()) do
            if a:IsA("Atmosphere") then
                if atmosphereOrig[a] == nil then atmosphereOrig[a] = a.Density end
                if a.Density ~= 0 then a.Density = 0 end
            end
        end
    elseif next(atmosphereOrig) then
        for a, d in pairs(atmosphereOrig) do pcall(function() a.Density = d end) end
        table.clear(atmosphereOrig)
    end

    -- Camera
    if cam then
        hold("FOV", on("FOVEnabled"), cam, "FieldOfView", Options.FOV.Value)
    end
    local zoom = on("InfiniteZoom")
    hold("MaxZoom", zoom, LP, "CameraMaxZoomDistance", 100000)
    hold("CameraMode", zoom, LP, "CameraMode", Enum.CameraMode.Classic)
end

----------------------------------------------------------------------
-- Fly
----------------------------------------------------------------------
local Fly = {}

local function stopFly()
    if Fly.bv then Fly.bv:Destroy() end
    if Fly.bg then Fly.bg:Destroy() end
    Fly.bv, Fly.bg = nil, nil
    local hum = getHum()
    if hum then hum.PlatformStand = false end
end

local function updateFly()
    local hrp, hum = getHRP(), getHum()
    if not hrp or not hum then return end
    if not Fly.bv or Fly.bv.Parent ~= hrp then
        stopFly()
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        bv.Velocity = Vector3.zero
        bv.Parent = hrp
        local bg = Instance.new("BodyGyro")
        bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        bg.P = 9e4
        bg.CFrame = hrp.CFrame
        bg.Parent = hrp
        Fly.bv, Fly.bg = bv, bg
    end
    hum.PlatformStand = true

    local cam = workspace.CurrentCamera
    local dir = Vector3.zero
    if not UIS:GetFocusedTextBox() then
        local cf = cam.CFrame
        if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
    end
    if dir.Magnitude == 0 and hum.MoveDirection.Magnitude > 0 then
        dir = hum.MoveDirection -- mobile joystick
    end
    Fly.bv.Velocity = dir.Magnitude > 0 and dir.Unit * Options.FlySpeed.Value or Vector3.zero
    Fly.bg.CFrame = cam.CFrame
end

----------------------------------------------------------------------
-- Noclip
----------------------------------------------------------------------
local noclipOrig = {}

local function restoreNoclip()
    for part in pairs(noclipOrig) do
        if part.Parent then part.CanCollide = true end
    end
    table.clear(noclipOrig)
end

local function updateNoclip(off)
    local active = not off and (Options.Noclip.Value or (tweening and Options.TweenNoclip.Value))
    local char = LP.Character
    if active and char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                noclipOrig[part] = true
                part.CanCollide = false
            end
        end
    elseif next(noclipOrig) then
        restoreNoclip()
    end
end

----------------------------------------------------------------------
-- ESP
----------------------------------------------------------------------
local guiParent = (gethui and gethui()) or game:GetService("CoreGui")
local ESP = {}

local function removeESP(p)
    local e = ESP[p]
    if not e then return end
    pcall(function() e.hl:Destroy() end)
    pcall(function() e.bb:Destroy() end)
    ESP[p] = nil
end

local function clearESP()
    for p in pairs(ESP) do removeESP(p) end
end

local function getESP(p)
    local e = ESP[p]
    if e and e.hl.Parent and e.bb.Parent then return e end
    removeESP(p)

    local hl = Instance.new("Highlight")
    hl.Name = "UH_ESP"
    hl.FillTransparency = 0.6
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = guiParent

    local bb = Instance.new("BillboardGui")
    bb.Name = "UH_ESPTag"
    bb.Size = UDim2.fromOffset(200, 40)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Parent = guiParent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.TextStrokeTransparency = 0.4
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Parent = bb

    e = { hl = hl, bb = bb, label = label }
    ESP[p] = e
    return e
end

local function updateESP()
    local enabled = Options.ESP.Value
    if not enabled then
        if next(ESP) then clearESP() end
        return
    end
    local myHRP = getHRP()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local char = p.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local dist = (hrp and myHRP) and (hrp.Position - myHRP.Position).Magnitude or 0
            local teammate = Options.ESPTeamCheck.Value and p.Team ~= nil and p.Team == LP.Team
            local show = hrp and hum and hum.Health > 0 and dist <= Options.ESPMaxDistance.Value and not teammate

            if show then
                local e = getESP(p)
                local color = (Options.ESPTeamColor.Value and p.Team) and p.TeamColor.Color or Options.ESPColor.Value
                if e.hl.Adornee ~= char then e.hl.Adornee = char end
                local head = char:FindFirstChild("Head") or hrp
                if e.bb.Adornee ~= head then e.bb.Adornee = head end
                e.hl.FillColor, e.hl.OutlineColor = color, color
                e.hl.Enabled = true

                local parts = {}
                if Options.ESPNames.Value then table.insert(parts, p.DisplayName) end
                if Options.ESPDistance.Value then table.insert(parts, ("[%d]"):format(math.floor(dist))) end
                e.label.Text = table.concat(parts, " ")
                e.label.TextColor3 = color
                e.bb.Enabled = #parts > 0
            elseif ESP[p] then
                ESP[p].hl.Enabled = false
                ESP[p].bb.Enabled = false
            end
        end
    end
end

----------------------------------------------------------------------
-- Settings tab
----------------------------------------------------------------------
local Defaults = {}
local unload -- defined below

do
    local H = Tabs.Settings:AddSection("Hub")
    H:AddToggle("ShowNotifications", { Title = "Show notifications", Description = "Toggle on/off messages (errors always show)", Default = true })
    H:AddButton({
        Title = "Reset all settings",
        Description = "Sets every toggle, slider and keybind back to default (waypoints and scripts are kept)",
        Callback = function()
            Window:Dialog({
                Title = "Reset settings",
                Content = "Reset all settings to their defaults?",
                Buttons = {
                    { Title = "Reset", Callback = function()
                        silent = true
                        for idx, d in pairs(Defaults) do
                            local opt = Options[idx]
                            if opt then
                                pcall(function()
                                    if opt.Type == "Keybind" then
                                        opt:SetValue(d[1], d[2])
                                    elseif opt.Type == "Colorpicker" then
                                        opt:SetValueRGB(d[1], d[2])
                                    else
                                        opt:SetValue(d[1])
                                    end
                                end)
                            end
                        end
                        silent = false
                        notify("Settings", "All settings reset. Overwrite your config to keep it.", 4, true)
                    end },
                    { Title = "Cancel" },
                },
            })
        end,
    })
    H:AddButton({
        Title = "Unload hub",
        Description = "Turns everything off, restores defaults and closes the UI",
        Callback = function() unload() end,
    })
end

-- Inputs/dropdowns that are not settings (excluded from configs and reset)
local NotSettings = {
    "TPPlayer", "WaypointName", "WaypointCoords", "WaypointSelect", "WaypointRename",
    "ScriptName", "ScriptSource", "ScriptSelect",
}
local notSettingsSet = {}
for _, idx in ipairs(NotSettings) do notSettingsSet[idx] = true end

-- Snapshot defaults before the Save/Interface managers add their own options
for idx, opt in pairs(Options) do
    if not notSettingsSet[idx] then
        if opt.Type == "Keybind" then
            Defaults[idx] = { opt.Value, opt.Mode }
        elseif opt.Type == "Colorpicker" then
            Defaults[idx] = { opt.Value, opt.Transparency }
        elseif opt.Type == "Dropdown" and opt.Multi then
            local copyT = {}
            for k, v in pairs(opt.Value or {}) do copyT[k] = v end
            Defaults[idx] = { copyT }
        else
            Defaults[idx] = { opt.Value }
        end
    end
end

SaveManager:SetLibrary(Library)
InterfaceManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes(NotSettings)
InterfaceManager:SetFolder(FOLDER)
SaveManager:SetFolder(FOLDER .. "/configs")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

-- Loading a config shouldn't spam a notification per toggle
do
    local originalLoad = SaveManager.Load
    SaveManager.Load = function(self, ...)
        local wasSilent = silent
        silent = true
        local results = table.pack(originalLoad(self, ...))
        silent = wasSilent
        return table.unpack(results, 1, results.n)
    end
end

----------------------------------------------------------------------
-- Wiring: notifications, keybinds, events
----------------------------------------------------------------------
local ToggleLabels = {
    WalkSpeedEnabled = "WalkSpeed", JumpEnabled = "Jump Height", InfiniteJump = "Infinite Jump",
    Fly = "Fly", Noclip = "Noclip", GravityEnabled = "Gravity", ClickTP = "Click Teleport",
    TweenNoclip = "Tween Noclip", Fullbright = "Fullbright", NoFog = "No Fog", FOVEnabled = "Custom FOV",
    InfiniteZoom = "Infinite Zoom", ESP = "ESP", AntiAFK = "Anti-AFK", FPSUnlock = "FPS Unlock",
}

local function applyFPS()
    if not canFPS then return end
    if Options.FPSUnlock.Value then
        setfpscap(Options.FPSCap.Value)
    elseif Orig.FPSApplied then
        setfpscap(60)
    end
    Orig.FPSApplied = Options.FPSUnlock.Value or nil
end

for idx, label in pairs(ToggleLabels) do
    local opt = Options[idx]
    if opt then
        opt:OnChanged(function(value)
            if idx == "FPSUnlock" then applyFPS() end
            notify(label, value and "Enabled" or "Disabled", 2)
        end)
    end
end
if canFPS then
    Options.FPSCap:OnChanged(function() applyFPS() end)
end

local KeybindTargets = {
    WalkSpeedKey = "WalkSpeedEnabled",
    InfiniteJumpKey = "InfiniteJump",
    FlyKey = "Fly",
    NoclipKey = "Noclip",
    FullbrightKey = "Fullbright",
    ESPKey = "ESP",
}
for keyIdx, toggleIdx in pairs(KeybindTargets) do
    Options[keyIdx]:OnClick(function()
        if UIS:GetFocusedTextBox() then return end
        local t = Options[toggleIdx]
        t:SetValue(not t.Value)
    end)
end

-- Player list for teleport dropdown
local function refreshPlayers()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then table.insert(names, p.Name) end
    end
    table.sort(names)
    Options.TPPlayer:SetValues(names)
end
connect(Players.PlayerAdded, refreshPlayers)
connect(Players.PlayerRemoving, function(p)
    removeESP(p)
    task.defer(refreshPlayers)
end)

-- Infinite jump
connect(UIS.JumpRequest, function()
    if Options.InfiniteJump.Value then
        local hum = getHum()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

-- Click teleport (LeftControl + click)
connect(UIS.InputBegan, function(input, gameProcessed)
    if gameProcessed or not Options.ClickTP.Value then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 and UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
        local hrp = getHRP()
        if hrp and Mouse.Hit then
            local rotation = hrp.CFrame - hrp.CFrame.Position
            teleportTo(CFrame.new(Mouse.Hit.Position + Vector3.new(0, 3, 0)) * rotation)
        end
    end
end)

-- Anti-AFK
connect(LP.Idled, function()
    if Options.AntiAFK.Value then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

-- Main loops
local espTimer = 0
connect(RunService.Stepped, function()
    updateNoclip(false)
end)

connect(RunService.RenderStepped, function()
    if Options.Fly.Value then
        updateFly()
    elseif Fly.bv then
        stopFly()
    end
end)

connect(RunService.Heartbeat, function(dt)
    if Library.Unloaded then
        unload()
        return
    end
    applyState(false)

    if tweening then
        local hrp = getHRP()
        if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
    end

    espTimer += dt
    if espTimer >= 0.1 then
        espTimer = 0
        updateESP()
    end
end)

----------------------------------------------------------------------
-- Unload
----------------------------------------------------------------------
local unloaded = false
unload = function()
    if unloaded then return end
    unloaded = true

    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    table.clear(Connections)

    cancelTween()
    pcall(stopFly)
    pcall(restoreNoclip)
    pcall(applyState, true)
    pcall(clearESP)
    if canFPS and Orig.FPSApplied then pcall(setfpscap, 60) end

    if not Library.Unloaded then pcall(function() Library:Destroy() end) end
    if getgenv then getgenv().UniversalHub_Unload = nil end
end

if getgenv then getgenv().UniversalHub_Unload = unload end

----------------------------------------------------------------------
-- Finish
----------------------------------------------------------------------
refreshPlayers()
renderWaypoints()
renderScripts()

Window:SelectTab(1)
SaveManager:LoadAutoloadConfig()
silent = false

if not hasFS then
    notify("Universal Hub", "Your executor has no file functions: waypoints, scripts and configs won't be saved.", 8, true)
end
notify("Universal Hub", "Loaded. RightShift hides the UI.", 5, true)

-- Auto-run scripts marked for this game
for _, s in ipairs(SavedScripts) do
    if type(s.autorun) == "table" and s.autorun[placeKey] then
        runScript(s)
    end
end
