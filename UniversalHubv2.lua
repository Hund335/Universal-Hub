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
local autoNoclip = false -- set by the automation "Fly to" step

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
    Acrylic = false, -- the acrylic blur (glass part + DepthOfField) costs FPS and makes the camera/mouse feel sluggish
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightShift,
})

local Tabs = {
    Game     = Window:AddTab({ Title = "Game", Icon = "gamepad-2" }),
    Aimbot   = Window:AddTab({ Title = "Aimbot", Icon = "crosshair" }),
    Movement = Window:AddTab({ Title = "Movement", Icon = "move" }),
    Teleport = Window:AddTab({ Title = "Teleport", Icon = "map-pin" }),
    Automation = Window:AddTab({ Title = "Automation", Icon = "bot" }),
    Scripts  = Window:AddTab({ Title = "Scripts",  Icon = "terminal" }),
    Visuals  = Window:AddTab({ Title = "Visuals",  Icon = "eye" }),
    Misc     = Window:AddTab({ Title = "Misc",     Icon = "wrench" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

----------------------------------------------------------------------
-- Aimbot tab (integrated from Hund335/Aimbot)
----------------------------------------------------------------------
local aimbotCleanup

do
    local Settings = Tabs.Aimbot:AddSection("Aimbot Settings")
    Settings:AddParagraph({
        Title = "Controls",
        Content = "Hold the selected trigger key to aim, or enable Toggle Mode. The FOV ring follows the mouse.",
    })
    Settings:AddToggle("AimbotEnabled", { Title = "Enabled", Default = false })
    Settings:AddToggle("AimbotToggleMode", { Title = "Toggle Mode", Description = "On = press once to toggle; off = hold the trigger key", Default = false })
    Settings:AddDropdown("AimbotLockPart", {
        Title = "Lock Part",
        Values = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" },
        Default = "Head",
    })
    Settings:AddSlider("AimbotSensitivity", { Title = "Sensitivity", Description = "Camera easing time (seconds); 0 = instant", Default = 0, Min = 0, Max = 1, Increment = 0.01, Suffix = " s" })
    Settings:AddToggle("AimbotTeamCheck", { Title = "Team Check", Default = false })
    Settings:AddToggle("AimbotWallCheck", { Title = "Wall Check", Default = false })
    Settings:AddToggle("AimbotAliveCheck", { Title = "Alive Check", Default = true })

    local ThirdPerson = Tabs.Aimbot:AddSection("Third Person")
    ThirdPerson:AddToggle("AimbotThirdPerson", { Title = "Enable Third Person", Description = "Uses mouse movement instead of directly changing the camera", Default = false })
    ThirdPerson:AddSlider("AimbotThirdPersonSensitivity", { Title = "Sensitivity", Default = 3, Min = 0.1, Max = 5, Increment = 0.1 })

    local FOV = Tabs.Aimbot:AddSection("Field Of View")
    FOV:AddToggle("AimbotFOVEnabled", { Title = "Enabled", Default = true })
    FOV:AddToggle("AimbotFOVVisible", { Title = "Visible", Default = true })
    FOV:AddSlider("AimbotFOVAmount", { Title = "Radius", Default = 90, Min = 10, Max = 500, Increment = 1, Suffix = " px" })
    FOV:AddToggle("AimbotFOVFilled", { Title = "Filled", Default = false })
    FOV:AddSlider("AimbotFOVTransparency", { Title = "Transparency", Default = 0.5, Min = 0, Max = 1, Increment = 0.05 })
    FOV:AddSlider("AimbotFOVSides", { Title = "Sides", Default = 60, Min = 3, Max = 100, Increment = 1 })
    FOV:AddSlider("AimbotFOVThickness", { Title = "Thickness", Default = 1, Min = 1, Max = 10, Increment = 1 })
    FOV:AddColorpicker("AimbotFOVColor", { Title = "Color", Default = Color3.fromRGB(255, 255, 255) })
    FOV:AddColorpicker("AimbotFOVLockedColor", { Title = "Locked Color", Default = Color3.fromRGB(255, 70, 70) })

    local UserInputService = game:GetService("UserInputService")
    local aimbotMouseMove = mousemoverel or (Input and Input.MouseMove)
    local aimbotCircle
    local aimbotDrawingAvailable = typeof(Drawing) == "table" and typeof(Drawing.new) == "function"
    local AIMBOT_RENDER_STEP = "UniversalHub_AimbotRenderStep"

    if aimbotDrawingAvailable then
        local ok, circle = pcall(function() return Drawing.new("Circle") end)
        if ok then aimbotCircle = circle end
    end
    if not aimbotCircle then
        Settings:AddParagraph({ Title = "FOV Circle", Content = "Your executor does not expose Drawing.new('Circle'); aiming can still run, but the FOV ring will not be drawn." })
    end
    if not aimbotMouseMove then
        ThirdPerson:AddParagraph({ Title = "Third-person input", Content = "mousemoverel is unavailable in this executor. Third-person mode will fall back to camera aiming." })
    end

    local Typing = false
    local Running = false
    local Locked
    local PreviousAimKeyDown = false
    local OriginalSensitivity = UserInputService.MouseDeltaSensitivity

    -- Fluent's keybind callback is intended for activation events, but polling
    -- GetState() is more reliable for Hold mode and supports both keyboard and
    -- mouse bindings (including MB2).
    local AimKeybind = Settings:AddKeybind("AimbotTriggerBind", {
        Title = "Aim Key",
        Description = "Hold to aim; Toggle Mode changes this to press-once activation.",
        Mode = "Hold",
        Default = "MB2",
    })

    local function cancelLock()
        Locked = nil
        if aimbotCircle then
            aimbotCircle.Color = Options.AimbotFOVColor.Value
        end
        UserInputService.MouseDeltaSensitivity = OriginalSensitivity
    end

    local function getAimKeyDown()
        if Typing or UserInputService:GetFocusedTextBox() then
            return false
        end
        local ok, state = pcall(function()
            return AimKeybind:GetState()
        end)
        return ok and state == true
    end

    Options.AimbotEnabled:OnChanged(function(enabled)
        if not enabled then
            Running = false
            PreviousAimKeyDown = false
            cancelLock()
        end
    end)

    Options.AimbotToggleMode:OnChanged(function()
        Running = false
        PreviousAimKeyDown = false
        cancelLock()
    end)

    local function getValidLockPart(player, camera)
        if not player or player == LP then return nil end
        local character = player.Character
        if not character then return nil end

        local lockPart = character:FindFirstChild(Options.AimbotLockPart.Value)
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not lockPart or not humanoid then return nil end
        if Options.AimbotTeamCheck.Value and LP.Team ~= nil and player.Team == LP.Team then return nil end
        if Options.AimbotAliveCheck.Value and humanoid.Health <= 0 then return nil end

        if Options.AimbotWallCheck.Value then
            local ignore = character:GetDescendants()
            if LP.Character then
                for _, descendant in ipairs(LP.Character:GetDescendants()) do
                    table.insert(ignore, descendant)
                end
            end
            local ok, blocked = pcall(function()
                return #camera:GetPartsObscuringTarget({ lockPart.Position }, ignore) > 0
            end)
            if not ok or blocked then return nil end
        end

        return lockPart
    end

    -- GetMouseLocation() does not account for ScreenInsets, so use
    -- WorldToViewportPoint() here to keep the target and cursor coordinates aligned.
    local function getScreenPosition(camera, worldPosition)
        local point, onScreen = camera:WorldToViewportPoint(worldPosition)
        return Vector2.new(point.X, point.Y), onScreen and point.Z > 0
    end

    local function getClosestPlayer(camera)
        local mouseLocation = UserInputService:GetMouseLocation()
        local maxDistance = Options.AimbotFOVEnabled.Value and Options.AimbotFOVAmount.Value or math.huge

        -- Apply the FOV only when acquiring a target. Once locked, keep tracking
        -- that valid target; the camera rotation itself can move its projection
        -- away from the cursor even though the lock is working correctly.
        if Locked then
            local lockPart = getValidLockPart(Locked, camera)
            if lockPart then
                local _, onScreen = getScreenPosition(camera, lockPart.Position)
                if onScreen then
                    return Locked, lockPart
                end
            end
            cancelLock()
        end

        local closestPlayer, closestPart
        local closestDistance = maxDistance
        for _, player in ipairs(Players:GetPlayers()) do
            local lockPart = getValidLockPart(player, camera)
            if lockPart then
                local screenPosition, onScreen = getScreenPosition(camera, lockPart.Position)
                if onScreen then
                    local distance = (mouseLocation - screenPosition).Magnitude
                    if distance <= closestDistance then
                        closestDistance = distance
                        closestPlayer = player
                        closestPart = lockPart
                    end
                end
            end
        end

        Locked = closestPlayer
        return closestPlayer, closestPart
    end

    local function updateAimbot(dt)
        local keyDown = getAimKeyDown()
        if Options.AimbotEnabled.Value then
            if Options.AimbotToggleMode.Value then
                if keyDown and not PreviousAimKeyDown then
                    Running = not Running
                    if not Running then cancelLock() end
                end
            else
                Running = keyDown
                if PreviousAimKeyDown and not keyDown then
                    cancelLock()
                end
            end
        else
            Running = false
            if Locked then cancelLock() end
        end
        PreviousAimKeyDown = keyDown

        local camera = workspace.CurrentCamera
        if aimbotCircle then
            if camera and Options.AimbotFOVEnabled.Value and Options.AimbotEnabled.Value then
                local mouseLocation = UserInputService:GetMouseLocation()
                aimbotCircle.Radius = Options.AimbotFOVAmount.Value
                aimbotCircle.Thickness = Options.AimbotFOVThickness.Value
                aimbotCircle.Filled = Options.AimbotFOVFilled.Value
                aimbotCircle.NumSides = Options.AimbotFOVSides.Value
                aimbotCircle.Color = Options.AimbotFOVColor.Value
                aimbotCircle.Transparency = Options.AimbotFOVTransparency.Value
                aimbotCircle.Visible = Options.AimbotFOVVisible.Value
                aimbotCircle.Position = Vector2.new(mouseLocation.X, mouseLocation.Y)
            else
                aimbotCircle.Visible = false
            end
        end

        if not (Running and Options.AimbotEnabled.Value and camera) then
            if Locked then cancelLock() end
            return
        end

        local targetPlayer, lockPart = getClosestPlayer(camera)
        if not targetPlayer or not lockPart then
            UserInputService.MouseDeltaSensitivity = OriginalSensitivity
            return
        end

        if Options.AimbotThirdPerson.Value and aimbotMouseMove then
            local targetScreenPosition = getScreenPosition(camera, lockPart.Position)
            local mouseLocation = UserInputService:GetMouseLocation()
            pcall(aimbotMouseMove,
                (targetScreenPosition.X - mouseLocation.X) * Options.AimbotThirdPersonSensitivity.Value,
                (targetScreenPosition.Y - mouseLocation.Y) * Options.AimbotThirdPersonSensitivity.Value
            )
            UserInputService.MouseDeltaSensitivity = OriginalSensitivity
        else
            local targetCFrame = CFrame.lookAt(camera.CFrame.Position, lockPart.Position)
            local smoothTime = Options.AimbotSensitivity.Value
            if smoothTime > 0 then
                local alpha = 1 - math.exp(-math.max(dt, 1 / 240) / smoothTime)
                camera.CFrame = camera.CFrame:Lerp(targetCFrame, math.clamp(alpha, 0, 1))
            else
                camera.CFrame = targetCFrame
            end
            UserInputService.MouseDeltaSensitivity = 0
        end

        if aimbotCircle then
            aimbotCircle.Color = Options.AimbotFOVLockedColor.Value
        end
    end

    -- Run after Roblox's camera controller so its per-frame camera update does
    -- not immediately overwrite the aim rotation.
    RunService:BindToRenderStep(AIMBOT_RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, updateAimbot)

    connect(UserInputService.TextBoxFocused, function()
        Typing = true
    end)
    connect(UserInputService.TextBoxFocusReleased, function()
        Typing = false
    end)

    aimbotCleanup = function()
        Running = false
        PreviousAimKeyDown = false
        pcall(function() RunService:UnbindFromRenderStep(AIMBOT_RENDER_STEP) end)
        cancelLock()
        if aimbotCircle then
            pcall(function() aimbotCircle:Remove() end)
            aimbotCircle = nil
        end
    end
end

----------------------------------------------------------------------
-- Movement tab
----------------------------------------------------------------------
do
    local S = Tabs.Movement:AddSection("Speed")
    S:AddToggle("WalkSpeedEnabled", { Title = "Walk speed", Description = "Stays applied after respawning", Default = false })
    S:AddKeybind("WalkSpeedKey", { Title = "Keybind", Mode = "Toggle", Default = "V" })
    S:AddSlider("WalkSpeed", { Title = "Speed", Default = 16, Min = 0, Max = 500, Increment = 1 })

    local J = Tabs.Movement:AddSection("Jump")
    J:AddToggle("JumpEnabled", { Title = "Jump height", Default = false })
    J:AddSlider("JumpHeight", { Title = "Height", Default = 7.2, Min = 0, Max = 200, Increment = 0.1, Suffix = " studs" })
    J:AddToggle("InfiniteJump", { Title = "Infinite jump", Description = "Jump again while in the air", Default = false })
    J:AddKeybind("InfiniteJumpKey", { Title = "Keybind", Mode = "Toggle", Default = "J" })

    local F = Tabs.Movement:AddSection("Fly")
    F:AddToggle("Fly", { Title = "Fly", Description = "WASD follows the camera, Space = up, LeftControl = down", Default = false })
    F:AddKeybind("FlyKey", { Title = "Keybind", Mode = "Toggle", Default = "G" })
    F:AddSlider("FlySpeed", { Title = "Speed", Default = 50, Min = 1, Max = 500, Increment = 1 })
    F:AddDropdown("FlyMode", {
        Title = "Mode",
        Description = "Hovering but can't move? Switch to Velocity",
        Values = { "CFrame", "Velocity" },
        Default = "CFrame",
    })
    F:AddToggle("LegacyFly", {
        Title = "Legacy fly",
        Description = "The original BodyVelocity fly. Overrides Mode while on",
        Default = false,
    })

    local N = Tabs.Movement:AddSection("Noclip & Click Teleport")
    N:AddToggle("Noclip", { Title = "Noclip", Description = "Walk through walls", Default = false })
    N:AddKeybind("NoclipKey", { Title = "Keybind", Mode = "Toggle", Default = "N" })
    N:AddToggle("ClickTP", { Title = "Click teleport", Description = "Hold LeftControl and click. Uses the Teleport tab's mode", Default = false })

    local G = Tabs.Movement:AddSection("Gravity")
    G:AddToggle("GravityEnabled", { Title = "Custom gravity", Default = false })
    G:AddSlider("Gravity", { Title = "Gravity", Description = "Roblox default: 196.2", Default = 196.2, Min = 0, Max = 500, Increment = 0.1 })
    G:AddButton({
        Title = "Reset to default",
        Callback = function() Options.Gravity:SetValue(196.2) end,
    })

    local SP = Tabs.Movement:AddSection("Spinbot")
    SP:AddToggle("SpinBot", { Title = "Spinbot", Description = "Spins your character in place", Default = false })
    SP:AddKeybind("SpinBotKey", { Title = "Keybind", Mode = "Toggle", Default = "X" })
    SP:AddSlider("SpinSpeed", { Title = "Speed", Default = 720, Min = 30, Max = 5000, Increment = 10, Suffix = " deg/s" })
    SP:AddDropdown("SpinDirection", { Title = "Direction", Values = { "Right", "Left" }, Default = "Right" })
end

----------------------------------------------------------------------
-- Teleport tab
----------------------------------------------------------------------
local Waypoints = loadJSON("waypoints.json", {})
local WaypointListSection

do
    local S = Tabs.Teleport:AddSection("Teleport Mode")
    S:AddDropdown("TPMode", { Title = "Mode", Description = "Used by waypoints, players, click teleport and automations", Values = { "Instant", "Tween" }, Default = "Instant" })
    S:AddSlider("TweenSpeed", { Title = "Tween speed", Default = 100, Min = 10, Max = 1000, Increment = 5, Suffix = " st/s" })
    S:AddToggle("TweenNoclip", { Title = "Noclip while tweening", Description = "Avoids getting stuck on walls", Default = true })
    S:AddButton({ Title = "Cancel tween", Callback = function() cancelTween() notify("Teleport", "Tween cancelled.") end })

    local P = Tabs.Teleport:AddSection("Player")
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

    -- The clickable list comes first; create / manage sections are added below it
    WaypointListSection = Tabs.Teleport:AddSection("Waypoints (click to teleport)")
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
    local W = Tabs.Teleport:AddSection("New Waypoint")
    W:AddInput("WaypointName", { Title = "Name", Default = "", Placeholder = "e.g. Shop, Boss, Spawn" })
    W:AddInput("WaypointCoords", { Title = "Coordinates (optional)", Default = "", Placeholder = "x, y, z | PlaceId  (empty = current spot)" })
    W:AddButton({ Title = "Save waypoint", Description = "Only shows up in this game (PlaceId " .. game.PlaceId .. ")", Callback = addWaypoint })
    W:AddButton({
        Title = "Copy my coordinates",
        Description = "Paste them into Coordinates later to recreate this spot",
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
    -- The clickable list comes first; add / manage sections are below it
    ScriptListSection = Tabs.Scripts:AddSection("Your Scripts (click to run)")

    local A = Tabs.Scripts:AddSection("New Script")
    A:AddInput("ScriptName", { Title = "Name", Default = "", Placeholder = "e.g. Infinite Yield" })
    A:AddInput("ScriptSource", { Title = "URL or code", Description = "A raw URL, or code like loadstring(game:HttpGet(\"...\"))()", Default = "", Placeholder = "https://... or loadstring(...)()" })
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
end

----------------------------------------------------------------------
-- Visuals tab
----------------------------------------------------------------------
local canFPS = typeof(setfpscap) == "function"
do
    local E = Tabs.Visuals:AddSection("ESP")
    E:AddToggle("ESP", { Title = "Player ESP", Description = "Highlights players through walls", Default = false })
    E:AddKeybind("ESPKey", { Title = "Keybind", Mode = "Toggle", Default = "K" })
    E:AddToggle("ESPNames", { Title = "Show names", Default = true })
    E:AddToggle("ESPDistance", { Title = "Show distance", Default = true })
    E:AddToggle("ESPTeamCheck", { Title = "Hide teammates", Default = false })
    E:AddSlider("ESPMaxDistance", { Title = "Max distance", Default = 2000, Min = 50, Max = 10000, Increment = 50, Suffix = " studs" })

    local EC = Tabs.Visuals:AddSection("ESP Colors")
    EC:AddColorpicker("ESPColor", { Title = "Color", Default = Color3.fromRGB(255, 70, 70) })
    EC:AddToggle("ESPVisibleCheck", { Title = "Different color when in sight", Description = "When nothing blocks your view of them", Default = true })
    EC:AddColorpicker("ESPVisibleColor", { Title = "In-sight color", Default = Color3.fromRGB(60, 220, 90) })
    EC:AddToggle("ESPTeamColor", { Title = "Use team colors", Default = false })

    local T = Tabs.Visuals:AddSection("Tracers")
    local hasDrawing = typeof(Drawing) == "table" and typeof(Drawing.new) == "function"
    T:AddToggle("ESPTracers", {
        Title = "Tracers",
        Description = hasDrawing and "A line to each player in their ESP color (needs Player ESP on)"
            or "Not supported by your executor (no Drawing library)",
        Default = false,
    })
    T:AddDropdown("ESPTracerOrigin", { Title = "Start from", Values = { "Bottom", "Center", "Mouse", "Top" }, Default = "Bottom" })
    T:AddSlider("ESPTracerThickness", { Title = "Thickness", Default = 1.5, Min = 1, Max = 5, Increment = 0.5 })

    local L = Tabs.Visuals:AddSection("World")
    L:AddToggle("Fullbright", { Title = "Fullbright", Description = "Removes darkness and shadows", Default = false })
    L:AddKeybind("FullbrightKey", { Title = "Keybind", Mode = "Toggle", Default = "L" })
    L:AddToggle("NoFog", { Title = "No fog", Default = false })

    local C = Tabs.Visuals:AddSection("Camera")
    C:AddToggle("FOVEnabled", { Title = "Custom FOV", Default = false })
    C:AddSlider("FOV", { Title = "Field of view", Default = 70, Min = 30, Max = 120, Increment = 1 })
    C:AddToggle("InfiniteZoom", { Title = "Infinite zoom out", Description = "Also removes forced first person", Default = false })
    if canFPS then
        C:AddToggle("FPSUnlock", { Title = "FPS unlock", Default = false })
        C:AddSlider("FPSCap", { Title = "FPS cap", Default = 240, Min = 30, Max = 1000, Increment = 10 })
    else
        C:AddParagraph({ Title = "FPS unlock", Content = "Not supported by your executor (no setfpscap)." })
    end
end

----------------------------------------------------------------------
-- Misc tab
----------------------------------------------------------------------
-- Webhook (Discord). Defined before the Misc UI so other features can use it.
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
local WEBHOOK_EVENTS = {
    "Automation started", "Automation finished", "Automation error", "Safety stop", "Server hop", "Hub loaded",
}

local gameNameCache
local function gameName()
    if not gameNameCache then
        local ok, info = pcall(function()
            return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
        end)
        gameNameCache = ok and info and info.Name or tostring(game.PlaceId)
    end
    return gameNameCache
end

-- {player} {displayname} {game} {placeid} {jobid} {players} {time} {health} {stat:Coins}
-- plus any extra keys passed in (e.g. {automation} {loop} {reason})
local function fillPlaceholders(text, extra)
    text = tostring(text or "")
    text = text:gsub("{stat:([^}]+)}", function(name)
        local stats = LP:FindFirstChild("leaderstats")
        local v = stats and stats:FindFirstChild(trim(name))
        return v and tostring(v.Value) or "?"
    end)
    local hum = getHum()
    local values = {
        player = LP.Name, displayname = LP.DisplayName, game = gameName(),
        placeid = tostring(game.PlaceId), jobid = game.JobId,
        players = tostring(#Players:GetPlayers()), time = os.date("%H:%M:%S"),
        health = hum and tostring(math.floor(hum.Health)) or "0",
    }
    for k, v in pairs(extra or {}) do values[k] = tostring(v) end
    return (text:gsub("{(%w+)}", function(key) return values[key:lower()] end))
end

-- Sends an embed. `callback(ok, info)` is optional (used by the Test button).
local function sendWebhook(title, message, color, callback)
    local url = trim(Options.WebhookURL and Options.WebhookURL.Value or "")
    local function finish(ok, info) if callback then callback(ok, info) end end
    if not url:match("^https://") then return finish(false, "No webhook URL set (Misc tab).") end
    if not httpRequest then return finish(false, "Your executor has no request function.") end

    task.spawn(function()
        local fields = { { name = "Game", value = gameName(), inline = true } }
        if Options.WebhookShowPlayer.Value then
            table.insert(fields, { name = "Player", value = LP.Name, inline = true })
        end
        table.insert(fields, { name = "Server", value = #Players:GetPlayers() .. " players", inline = true })

        local ping = trim(Options.WebhookPing.Value or "")
        local body = {
            username = "Universal Hub",
            content = ping:match("^%d+$") and ("<@" .. ping .. ">") or nil,
            embeds = { {
                title = title,
                description = message,
                color = color or 0x5865F2,
                fields = fields,
                timestamp = DateTime.now():ToIsoDate(),
            } },
        }
        local ok, res = pcall(httpRequest, {
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(body),
        })
        local code = ok and type(res) == "table" and tonumber(res.StatusCode) or nil
        if code and code >= 200 and code < 300 then
            finish(true, "Sent")
        else
            finish(false, ok and ("Discord answered " .. tostring(code)) or tostring(res))
        end
    end)
end

local function webhookEvent(event, title, message, color)
    local events = Options.WebhookEvents and Options.WebhookEvents.Value
    if type(events) == "table" and events[event] then
        sendWebhook(title, message, color)
    end
end

-- Re-run the hub after any teleport (server hop, rejoin, game teleports) so
-- auto-start automations keep going in the new server
local queueTeleport = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
local LOAD_LINE = 'loadstring(game:HttpGet("https://raw.githubusercontent.com/Hund335/Universal-Hub/main/loader.lua"))()'
local teleportQueued = false
local function queueHubReload()
    if teleportQueued or not queueTeleport or not (Options.KeepAfterTeleport and Options.KeepAfterTeleport.Value) then return end
    teleportQueued = pcall(queueTeleport, LOAD_LINE)
end

local function rejoin()
    notify("Server", "Rejoining...", 3, true)
    queueHubReload()
    if #Players:GetPlayers() <= 1 then
        TeleportService:Teleport(game.PlaceId, LP)
    else
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
    end
end

local function serverHop(reason)
    notify("Server", "Searching for a server...", 3, true)
    local ok, body = pcall(function()
        return game:HttpGet(("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId))
    end)
    local okDecode, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or not okDecode or type(data) ~= "table" or type(data.data) ~= "table" then
        notify("Server", "Couldn't fetch the server list.", 4, true)
        return false
    end
    local candidates = {}
    for _, s in ipairs(data.data) do
        if s.id ~= game.JobId and tonumber(s.playing) and tonumber(s.maxPlayers) and s.playing < s.maxPlayers then
            table.insert(candidates, s)
        end
    end
    if #candidates == 0 then
        notify("Server", "No other servers with space found.", 4, true)
        return false
    end
    if Options.HopSmallest.Value then
        table.sort(candidates, function(x, y) return x.playing < y.playing end)
        while #candidates > 5 do table.remove(candidates) end
    end
    local pick = candidates[math.random(1, #candidates)]
    webhookEvent("Server hop", "Server hop", (reason and (reason .. "\n") or "") .. "Joining a server with " .. tostring(pick.playing) .. " players", 0x3BA55D)
    queueHubReload()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, pick.id, LP)
    return true
end

do
    local S = Tabs.Misc:AddSection("Server")
    S:AddButton({ Title = "Rejoin", Callback = rejoin })
    S:AddButton({
        Title = "Server hop",
        Description = "Joins a different public server of this game",
        Callback = function() task.spawn(serverHop) end,
    })
    S:AddToggle("HopSmallest", { Title = "Hop to smallest servers", Description = "Off = any server with space", Default = false })
    S:AddToggle("KeepAfterTeleport", {
        Title = "Re-run hub after teleport",
        Description = queueTeleport and "Lets automations continue after a hop"
            or "Not supported by your executor (no queue_on_teleport)",
        Default = true,
    })
    S:AddToggle("AntiAFK", { Title = "Anti-AFK", Description = "Prevents the 20 minute idle kick", Default = true })
    S:AddButton({ Title = "Copy PlaceId", Callback = function() copy(tostring(game.PlaceId)) end })
    S:AddButton({ Title = "Copy JobId", Callback = function() copy(game.JobId) end })

    local W = Tabs.Misc:AddSection("Discord Webhook")
    W:AddInput("WebhookURL", { Title = "Webhook URL", Default = "", Placeholder = "https://discord.com/api/webhooks/..." })
    W:AddButton({
        Title = "Test webhook",
        Callback = function()
            sendWebhook("Test", "Universal Hub webhook works.", 0x3BA55D, function(ok, info)
                notify("Webhook", ok and "Test sent, check Discord." or ("Failed: " .. info), 4, true)
            end)
        end,
    })
    W:AddDropdown("WebhookEvents", {
        Title = "Send on",
        Description = "Events that post automatically",
        Values = WEBHOOK_EVENTS,
        Multi = true,
        Default = { "Automation finished", "Automation error", "Safety stop" },
    })
    W:AddInput("WebhookPing", { Title = "Ping user ID (optional)", Default = "", Placeholder = "Your Discord user ID, e.g. 123456789012345678", Numeric = true })
    W:AddToggle("WebhookShowPlayer", { Title = "Include player name", Default = true })
    W:AddInput("WebhookMessage", {
        Title = "Custom message",
        Description = "Placeholders: {player} {displayname} {game} {placeid} {jobid} {players} {time} {health} {stat:Coins}",
        Default = "{player} is in {game}",
        Placeholder = "Text for the Send button",
    })
    W:AddButton({
        Title = "Send custom message",
        Callback = function()
            sendWebhook("Message", fillPlaceholders(Options.WebhookMessage.Value), nil, function(ok, info)
                notify("Webhook", ok and "Sent!" or ("Failed: " .. info), 4, true)
            end)
        end,
    })
end

connect(LP.OnTeleport, function(state)
    if state == Enum.TeleportState.Started then queueHubReload() end
end)

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
        local current = obj[prop]
        -- Numbers are stored as float32 by the engine, so compare with a tolerance
        -- (otherwise e.g. Gravity 196.2 gets rewritten every single frame)
        if type(value) == "number" and type(current) == "number" then
            if math.abs(current - value) > 0.01 then obj[prop] = value end
        elseif current ~= value then
            obj[prop] = value
        end
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

    -- Spinbot: stop the Humanoid turning you toward where you walk (restored when off)
    if hum or off then
        hold("AutoRotate", on("SpinBot"), hum, "AutoRotate", false)
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
-- CFrame-based fly: no BodyVelocity/BodyGyro (many games delete those) and no
-- PlatformStand (which makes you flop to the ground if anything goes wrong).
-- We keep our own target position so gravity can't make you sink.
-- Legacy fly (the original version) uses BodyVelocity + BodyGyro + PlatformStand.
local Fly = { active = false, pos = nil, bv = nil, bg = nil }

local function stopLegacyFly()
    if not (Fly.bv or Fly.bg) then return end
    if Fly.bv then Fly.bv:Destroy() end
    if Fly.bg then Fly.bg:Destroy() end
    Fly.bv, Fly.bg = nil, nil
    local hum = getHum()
    if hum then hum.PlatformStand = false end
end

local function stopFly()
    Fly.active, Fly.pos = false, nil
    stopLegacyFly()
    local hrp = getHRP()
    if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
end

local function getFlyDirection(cam, hum)
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
    return dir
end

local function updateLegacyFly(hrp, hum)
    if not Fly.bv or Fly.bv.Parent ~= hrp or not Fly.bg or Fly.bg.Parent ~= hrp then
        stopLegacyFly()
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
    local dir = getFlyDirection(cam, hum)
    Fly.bv.Velocity = dir.Magnitude > 0 and dir.Unit * Options.FlySpeed.Value or Vector3.zero
    Fly.bg.CFrame = cam.CFrame
end

local function updateFly(dt)
    local hrp, hum = getHRP(), getHum()
    if not hrp or not hum then
        Fly.pos = nil
        return
    end
    Fly.active = true

    if Options.LegacyFly.Value then
        Fly.pos = nil
        updateLegacyFly(hrp, hum)
        return
    end
    stopLegacyFly()

    -- Let teleports/tweens move us; resync afterwards
    if tweening then
        Fly.pos = nil
        return
    end
    if not Fly.pos or (hrp.Position - Fly.pos).Magnitude > 8 then
        Fly.pos = hrp.Position
    end

    local cam = workspace.CurrentCamera
    local dir = getFlyDirection(cam, hum)
    local speed = Options.FlySpeed.Value
    local moveVel = dir.Magnitude > 0 and dir.Unit * speed or Vector3.zero
    Fly.pos += moveVel * math.min(dt, 0.1)

    if Options.FlyMode.Value == "Velocity" then
        -- Moves with real velocity (like normal physics), never writes your position.
        -- A small correction toward the target keeps you from sinking.
        -- Walls stop you in this mode.
        local correction = (Fly.pos - hrp.Position) * 10
        if correction.Magnitude > speed then correction = correction.Unit * speed end
        hrp.AssemblyLinearVelocity = moveVel + correction
        hrp.AssemblyAngularVelocity = Vector3.zero
    else
        -- CFrame: sets your position directly every frame (passes through walls)
        local look = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
        if look.Magnitude < 0.01 then look = hrp.CFrame.LookVector * Vector3.new(1, 0, 1) end
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.CFrame = CFrame.lookAt(Fly.pos, Fly.pos + look.Unit)
    end
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
    local active = not off and (Options.Noclip.Value or autoNoclip or (tweening and Options.TweenNoclip.Value))
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
    if e.tracer then pcall(function() e.tracer:Remove() end) end
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

-- True when a ray from the camera reaches the character without hitting a wall.
-- See-through parts (glass, invisible barriers) don't count as walls.
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude

local function isInSight(char)
    local cam = workspace.CurrentCamera
    if not cam then return false end
    local origin = cam.CFrame.Position
    local ignore = { char }
    if LP.Character then table.insert(ignore, LP.Character) end
    for _, partName in ipairs({ "Head", "HumanoidRootPart" }) do
        local part = char:FindFirstChild(partName)
        if part then
            local direction = part.Position - origin
            for _ = 1, 4 do
                sightParams.FilterDescendantsInstances = ignore
                local hit = workspace:Raycast(origin, direction, sightParams)
                if not hit then return true end
                if hit.Instance.Transparency < 0.8 then break end
                table.insert(ignore, hit.Instance) -- see-through: look past it
            end
        end
    end
    return false
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
                if Options.ESPVisibleCheck.Value and isInSight(char) then
                    color = Options.ESPVisibleColor.Value
                end
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
                e.color, e.root, e.shown = color, hrp, true -- used by the tracer pass every frame
            elseif ESP[p] then
                ESP[p].hl.Enabled = false
                ESP[p].bb.Enabled = false
                ESP[p].shown = false
            end
        end
    end
end

-- Tracers run every frame (ESP itself refreshes 10x/s), otherwise the lines lag behind
local canDraw = typeof(Drawing) == "table" and typeof(Drawing.new) == "function"
local function updateTracers()
    if not canDraw then return end
    local enabled = Options.ESP.Value and Options.ESPTracers.Value
    local cam = workspace.CurrentCamera
    local origin
    if enabled and cam then
        local size = cam.ViewportSize
        local mode = Options.ESPTracerOrigin.Value
        if mode == "Center" then
            origin = size / 2
        elseif mode == "Mouse" then
            origin = UIS:GetMouseLocation()
        elseif mode == "Top" then
            origin = Vector2.new(size.X / 2, 0)
        else
            origin = Vector2.new(size.X / 2, size.Y)
        end
    end

    for _, e in pairs(ESP) do
        local line = e.tracer
        local visible = false
        if origin and e.shown and e.root and e.root.Parent then
            local pos = cam:WorldToViewportPoint(e.root.Position)
            if pos.Z > 0 then -- in front of the camera
                if not line then
                    line = Drawing.new("Line")
                    e.tracer = line
                end
                line.From = origin
                line.To = Vector2.new(pos.X, pos.Y)
                line.Color = e.color or Options.ESPColor.Value
                line.Thickness = Options.ESPTracerThickness.Value
                line.Transparency = 1
                visible = true
            end
        end
        if line then line.Visible = visible end
    end
end

----------------------------------------------------------------------
-- Automation: engine
----------------------------------------------------------------------
local VIM do
    local ok, svc = pcall(function() return game:GetService("VirtualInputManager") end)
    VIM = ok and svc or nil
end

local Automations = loadJSON("automations.json", {})
local function saveAutomations() saveJSON("automations.json", Automations) end

local STEP_TYPES = {
    "Teleport", "Walk to", "Fly to", "Interact", "Run code / Fire event",
    "Wait", "Wait until", "Press key", "Click", "Equip tool", "Use tool", "Notify",
    "Send webhook", "Server hop", "Label", "Go to label", "If condition, go to label", "Repeat from label", "Stop automation",
}
local POSITION_STEPS = { ["Teleport"] = true, ["Walk to"] = true, ["Fly to"] = true }
local CODE_STEPS = { ["Run code / Fire event"] = true, ["Wait until"] = true, ["If condition, go to label"] = true }
-- Control-flow steps run instantly: no "delay between steps" after them
local CONTROL_STEPS = {
    ["Label"] = true, ["Go to label"] = true, ["If condition, go to label"] = true,
    ["Repeat from label"] = true, ["Stop automation"] = true,
}

-- "label, times" -> "label", times
local function parseRepeat(value)
    local label, times = (value or ""):match("^%s*(.-)%s*,%s*(%d+)%s*$")
    if not label or label == "" then return nil end
    return label, tonumber(times)
end

-- Helpers available inside Run code / Wait until / If conditions
local scriptEnv = (getfenv and getfenv()) or _G
local CodeHelpers = {
    player = LP,
    char = function() return LP.Character end,
    hrp = getHRP,
    hum = getHum,
    stat = function(name) -- leaderstats value, e.g. stat("Coins")
        local stats = LP:FindFirstChild("leaderstats")
        local v = stats and stats:FindFirstChild(name)
        return v and v.Value
    end,
    health = function()
        local h = getHum()
        return h and h.Health or 0
    end,
    dist = function(x, y, z) -- distance to a position / part / model
        local hrp = getHRP()
        if not hrp then return math.huge end
        local target = x
        if typeof(x) == "number" then target = Vector3.new(x, y, z)
        elseif typeof(x) == "Instance" then target = x:IsA("Model") and x:GetPivot().Position or x.Position end
        return (hrp.Position - target).Magnitude
    end,
    hasTool = function(name)
        name = (name or ""):lower()
        for _, container in ipairs({ LP:FindFirstChildOfClass("Backpack"), LP.Character }) do
            for _, item in ipairs(container and container:GetChildren() or {}) do
                if item:IsA("Tool") and item.Name:lower():find(name, 1, true) then return true end
            end
        end
        return false
    end,
    find = function(name) return workspace:FindFirstChild(name, true) end,
}

local function compileUserCode(src, asExpression)
    local fn, err
    if asExpression then fn = loadstring("return " .. src) end
    if not fn then fn, err = loadstring(src) end
    if fn and setfenv then
        pcall(setfenv, fn, setmetatable({}, {
            __index = function(_, key)
                local helper = CodeHelpers[key]
                if helper ~= nil then return helper end
                return scriptEnv[key]
            end,
        }))
    end
    return fn, err
end
local POSITION_HINT = "Empty = your current spot, a waypoint name, or x, y, z"
local STEP_HINTS = {
    ["Teleport"] = POSITION_HINT .. " (uses Teleport tab mode/speed)",
    ["Walk to"] = POSITION_HINT .. " (walks normally, 30s timeout)",
    ["Fly to"] = POSITION_HINT .. " (flies in a straight line at Fly Speed, noclip on)",
    ["Interact"] = "Optional filter (prompt text or object name). Uses nearest prompt / click detector in range",
    ["Run code / Fire event"] = "Opens the code editor: paste your remote / event code",
    ["Wait"] = "Seconds, e.g. 1.5",
    ["Wait until"] = "Timeout in seconds (default 30). The condition goes in the editor",
    ["Press key"] = "Key name, e.g. E, F, One, Space",
    ["Click"] = "Empty = screen center, or x, y in pixels",
    ["Equip tool"] = "Tool name (part of it is enough). Empty = first tool",
    ["Use tool"] = "Nothing needed: activates the tool you're holding",
    ["Notify"] = "Message to show",
    ["Send webhook"] = "Message, e.g. {player} has {stat:Coins} coins (loop {loop}). URL is set in the Misc tab",
    ["Server hop"] = "Optional reason for the webhook. Turn on Auto-start so the automation continues in the new server",
    ["Label"] = "Label name, e.g. farm. Marks a spot other steps can jump to",
    ["Go to label"] = "Label to jump to, e.g. farm",
    ["If condition, go to label"] = "Label to jump to when the condition is true. The condition goes in the editor",
    ["Repeat from label"] = "label, times  e.g. farm, 5  (jumps back 5 times, then continues)",
    ["Stop automation"] = "Nothing needed: ends the run (also stops looping)",
}

local Auto = { running = false, runId = 0, statusPara = nil }

local function autoAlive(id) return Auto.running and Auto.runId == id end

local function autoSleep(id, seconds)
    local deadline = os.clock() + (seconds or 0)
    while os.clock() < deadline do
        if not autoAlive(id) then return false end
        task.wait(0.05)
    end
    return autoAlive(id)
end

local function setStatus(text)
    if Auto.statusPara then pcall(function() Auto.statusPara:SetDesc(text) end) end
end

local function waitForCharacter(id)
    while autoAlive(id) do
        local hum, hrp = getHum(), getHRP()
        if hum and hrp and hum.Health > 0 then return true end
        task.wait(0.25)
    end
    return false
end

local function stepCFrame(s)
    local pos = Vector3.new(s.x, s.y, s.z)
    local look = Vector3.new(s.lx or 0, 0, s.lz or 0)
    if look.Magnitude < 0.01 then return CFrame.new(pos) end
    return CFrame.lookAt(pos, pos + look)
end

local function shortText(text, len)
    text = (text or ""):gsub("%s+", " ")
    if #text > len then text = text:sub(1, len - 3) .. "..." end
    return text
end

local function stepSummary(s)
    local t, v = s.type, s.value or ""
    if POSITION_STEPS[t] then
        return t .. " -> " .. (s.label or string.format("%.0f, %.0f, %.0f", s.x, s.y, s.z))
    elseif t == "Interact" then
        return "Interact " .. (v ~= "" and ("[" .. v .. "]") or "(nearest)") .. " within " .. (s.range or 20)
    elseif t == "Run code / Fire event" then
        return "Code: " .. shortText(s.code, 45)
    elseif t == "Wait until" then
        return "Wait until " .. shortText(s.code, 35) .. " (max " .. (v ~= "" and v or "30") .. "s)"
    elseif t == "Wait" then
        return "Wait " .. v .. "s"
    elseif t == "Press key" then
        return "Press " .. v
    elseif t == "Click" then
        return "Click " .. (v ~= "" and v or "screen center")
    elseif t == "Equip tool" then
        return "Equip " .. (v ~= "" and v or "first tool")
    elseif t == "Notify" then
        return "Notify: " .. shortText(v, 40)
    elseif t == "Send webhook" then
        return "Webhook: " .. shortText(v, 40)
    elseif t == "Server hop" then
        return "Server hop" .. (v ~= "" and (" (" .. shortText(v, 30) .. ")") or "")
    elseif t == "Label" then
        return "Label: " .. v
    elseif t == "Go to label" then
        return "Go to " .. v
    elseif t == "If condition, go to label" then
        return "If " .. shortText(s.code, 35) .. " -> go to " .. v
    elseif t == "Repeat from label" then
        local label, times = parseRepeat(v)
        return "Repeat from " .. tostring(label) .. " (" .. tostring(times) .. "x)"
    elseif t == "Stop automation" then
        return "Stop automation"
    end
    return t
end

local function findInteractable(range, filter)
    local hrp = getHRP()
    if not hrp then return nil end
    filter = (filter or ""):lower()
    local best, bestDist
    for _, d in ipairs(workspace:GetDescendants()) do
        local isPrompt = d:IsA("ProximityPrompt")
        if (isPrompt and d.Enabled) or d:IsA("ClickDetector") then
            local holder = d.Parent
            if holder and holder:IsA("Attachment") then holder = holder.Parent end
            local pos
            if holder and holder:IsA("BasePart") then
                pos = holder.Position
            elseif holder and holder:IsA("Model") then
                pos = holder:GetPivot().Position
            end
            if pos then
                local dist = (pos - hrp.Position).Magnitude
                if dist <= range and (not bestDist or dist < bestDist) then
                    local matches = true
                    if filter ~= "" then
                        local text = holder.Name .. " " .. d.Name .. " " .. (holder.Parent and holder.Parent.Name or "")
                        if isPrompt then text ..= " " .. d.ActionText .. " " .. d.ObjectText end
                        matches = text:lower():find(filter, 1, true) ~= nil
                    end
                    if matches then best, bestDist = d, dist end
                end
            end
        end
    end
    return best
end

local function triggerInteractable(obj, id)
    if obj:IsA("ProximityPrompt") then
        if typeof(fireproximityprompt) == "function" and pcall(fireproximityprompt, obj) then
            return true
        end
        obj:InputHoldBegin()
        autoSleep(id, obj.HoldDuration + 0.1)
        obj:InputHoldEnd()
        return true
    end
    if typeof(fireclickdetector) == "function" then
        return (pcall(fireclickdetector, obj))
    end
    return false
end

local function walkTo(id, target)
    local deadline, lastIssue = os.clock() + 30, 0
    while autoAlive(id) and os.clock() < deadline do
        local hum, hrp = getHum(), getHRP()
        if not hum or not hrp then return false end
        if ((target - hrp.Position) * Vector3.new(1, 0, 1)).Magnitude < 2.5 then return true end
        if os.clock() - lastIssue > 4 then -- MoveTo gives up after ~8s, so re-issue it
            hum:MoveTo(target)
            lastIssue = os.clock()
        end
        task.wait(0.1)
    end
    return false
end

local function flyTo(id, target)
    autoNoclip = true
    while autoAlive(id) do
        local dt = RunService.Heartbeat:Wait()
        local hrp = getHRP()
        if not hrp then break end
        local delta = target - hrp.Position
        if delta.Magnitude < 0.5 then break end
        local move = math.min(delta.Magnitude, Options.FlySpeed.Value * math.min(dt, 0.1))
        local flat = delta * Vector3.new(1, 0, 1)
        local rotation = flat.Magnitude > 0.1 and CFrame.lookAt(Vector3.zero, flat.Unit) or (hrp.CFrame - hrp.CFrame.Position)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.CFrame = CFrame.new(hrp.Position + delta.Unit * move) * rotation
    end
    autoNoclip = false
end

local function sendKey(id, name)
    if not VIM then return false, "VirtualInputManager not available" end
    name = name:sub(1, 1):upper() .. name:sub(2)
    local ok, key = pcall(function() return Enum.KeyCode[name] end)
    if not ok or not key then return false, "Unknown key: " .. name end
    VIM:SendKeyEvent(true, key, false, game)
    autoSleep(id, 0.08)
    VIM:SendKeyEvent(false, key, false, game)
    return true
end

local function sendClick(id, value)
    if not VIM then return false, "VirtualInputManager not available" end
    local cam = workspace.CurrentCamera
    local x, y = cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2
    local nums = {}
    for n in (value or ""):gmatch("-?%d+%.?%d*") do table.insert(nums, tonumber(n)) end
    if #nums >= 2 then x, y = nums[1], nums[2] end
    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
    autoSleep(id, 0.05)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
    return true
end

-- Control-flow steps. Returns "jump", targetIndex | "stop" | nil (continue).
-- ctx = { labels = {lowername = index}, counters = {}, index = n, testing = bool }
local function runControlStep(step, ctx, fail)
    local t, v = step.type, trim(step.value or "")
    local function target(label)
        local index = ctx.labels[(label or ""):lower()]
        if not index then fail("label \"" .. tostring(label) .. "\" doesn't exist") end
        return index
    end

    if t == "Label" then
        return nil
    elseif t == "Go to label" then
        local index = target(v)
        if ctx.testing then
            if index then notify("Automation", "Would jump to step " .. index .. " (" .. v .. ")", 3, true) end
            return nil
        end
        if index then return "jump", index end
    elseif t == "If condition, go to label" then
        local fn, err = compileUserCode(step.code or "false", true)
        if not fn then return fail("condition doesn't compile: " .. tostring(err)) end
        local ok, result = pcall(fn)
        if not ok then return fail("condition error: " .. tostring(result)) end
        if ctx.testing then
            notify("Automation", "Condition is " .. (result and "TRUE (would jump to " .. v .. ")" or "FALSE (would continue)"), 4, true)
            return nil
        end
        if result then
            local index = target(v)
            if index then return "jump", index end
        end
    elseif t == "Repeat from label" then
        local label, times = parseRepeat(v)
        if not label then return fail("Repeat needs \"label, times\"") end
        local index = target(label)
        if ctx.testing or not index then return nil end
        local count = ctx.counters[ctx.index] or 0
        if count < times then
            ctx.counters[ctx.index] = count + 1
            return "jump", index
        end
        ctx.counters[ctx.index] = 0 -- reset so an outer loop can repeat it again
    elseif t == "Stop automation" then
        if ctx.testing then
            notify("Automation", "Would stop the automation here", 3, true)
            return nil
        end
        return "stop"
    end
    return nil
end

local function runStep(step, id, automationName, ctx)
    local function fail(msg) notify("Automation", automationName .. ": " .. msg, 4, true) end
    if CONTROL_STEPS[step.type] then return runControlStep(step, ctx, fail) end

    if not waitForCharacter(id) then return end
    local t, v = step.type, step.value or ""

    if t == "Teleport" then
        teleportTo(stepCFrame(step))
        while tweening and autoAlive(id) do task.wait(0.05) end
    elseif t == "Walk to" then
        if not walkTo(id, Vector3.new(step.x, step.y, step.z)) and autoAlive(id) then fail("Walk to timed out") end
    elseif t == "Fly to" then
        flyTo(id, Vector3.new(step.x, step.y, step.z))
    elseif t == "Interact" then
        local obj = findInteractable(step.range or 20, v)
        if not obj then
            fail("nothing to interact with nearby")
        elseif not triggerInteractable(obj, id) then
            fail("your executor can't fire click detectors")
        end
    elseif t == "Run code / Fire event" then
        local fn, err = compileUserCode(step.code or "", false)
        if not fn then return fail("code error: " .. tostring(err)) end
        local ok, runErr = pcall(fn)
        if not ok then fail("code error: " .. tostring(runErr)) end
    elseif t == "Wait" then
        autoSleep(id, tonumber(v) or 1)
    elseif t == "Wait until" then
        local fn, err = compileUserCode(step.code or "false", true)
        if not fn then return fail("condition doesn't compile: " .. tostring(err)) end
        local deadline = os.clock() + (tonumber(v) or 30)
        while autoAlive(id) do
            local ok, result = pcall(fn)
            if ok and result then break end
            if os.clock() > deadline then fail("Wait until timed out") break end
            task.wait(0.1)
        end
    elseif t == "Press key" then
        local ok, err = sendKey(id, v)
        if not ok then fail(err) end
    elseif t == "Click" then
        local ok, err = sendClick(id, v)
        if not ok then fail(err) end
    elseif t == "Equip tool" then
        local hum, backpack = getHum(), LP:FindFirstChildOfClass("Backpack")
        local tool
        for _, item in ipairs(backpack and backpack:GetChildren() or {}) do
            if item:IsA("Tool") and (v == "" or item.Name:lower():find(v:lower(), 1, true)) then
                tool = item
                break
            end
        end
        local held = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
        if tool and hum then
            hum:EquipTool(tool)
        elseif not (held and (v == "" or held.Name:lower():find(v:lower(), 1, true))) then
            fail("no tool matching \"" .. v .. "\"")
        end
    elseif t == "Use tool" then
        local tool = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
        if tool then tool:Activate() else fail("not holding a tool") end
    elseif t == "Notify" then
        notify("Automation", fillPlaceholders(v, ctx and ctx.extra), 3, true)
    elseif t == "Send webhook" then
        sendWebhook(automationName, fillPlaceholders(v ~= "" and v or "Step reached", ctx and ctx.extra), nil, function(ok, info)
            if not ok then fail("webhook failed: " .. info) end
        end)
    elseif t == "Server hop" then
        if ctx and ctx.testing then
            return notify("Automation", "Would server hop here (skipped while testing)", 3, true)
        end
        if serverHop(automationName .. (v ~= "" and (": " .. v) or "")) then
            autoSleep(id, 20) -- teleport takes us away; if it fails we carry on afterwards
        end
    end
end

local function stopAutomation(quiet)
    if not Auto.running then return end
    Auto.running = false
    Auto.runId += 1
    autoNoclip = false
    cancelTween()
    setStatus("Stopped")
    if not quiet then notify("Automation", "Stopped", 2, true) end
end

-- Safety stops ------------------------------------------------------
local SAFETY_ACTIONS = { "Stop", "Server hop", "Rejoin" }
local friendCache = {}

local function isFriend(p)
    if friendCache[p.UserId] == nil then
        local ok, result = pcall(function() return LP:IsFriendsWith(p.UserId) end)
        friendCache[p.UserId] = ok and result or false
    end
    return friendCache[p.UserId]
end

-- Returns a reason string when a safety rule of automation `a` is broken
local function checkSafety(a, startedAt)
    local hrp, hum = getHRP(), getHum()
    local range = tonumber(a.safetyRange) or 0
    if range > 0 and hrp then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and not (a.safetyIgnoreFriends ~= false and isFriend(p)) then
                local other = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if other and (other.Position - hrp.Position).Magnitude <= range then
                    return ("%s came within %d studs"):format(p.Name, range)
                end
            end
        end
    end
    local minHealth = tonumber(a.safetyHealth) or 0
    if minHealth > 0 and hum and hum.Health > 0 and hum.MaxHealth > 0 then
        local percent = hum.Health / hum.MaxHealth * 100
        if percent <= minHealth then return ("health dropped to %d%%"):format(math.floor(percent)) end
    end
    local minutes = tonumber(a.safetyMinutes) or 0
    if minutes > 0 and os.clock() - startedAt >= minutes * 60 then
        return ("time limit of %d minutes reached"):format(minutes)
    end
end

local function triggerSafety(a, reason)
    local action = a.safetyAction or "Stop"
    stopAutomation(true)
    setStatus("Safety stop: " .. reason .. "\nAction: " .. action)
    notify("Safety stop", a.name .. ": " .. reason .. " -> " .. action, 6, true)
    webhookEvent("Safety stop", "Safety stop: " .. a.name, reason .. "\nAction: " .. action, 0xED4245)
    if action == "Server hop" then
        task.delay(1, serverHop, "Safety: " .. reason)
    elseif action == "Rejoin" then
        task.delay(1, rejoin)
    end
end

local function runAutomation(a, onlyStep)
    if not a then return notify("Automation", "Select an automation first.", 3, true) end
    local steps = onlyStep and { onlyStep } or a.steps
    if #steps == 0 then return notify("Automation", "\"" .. a.name .. "\" has no steps yet.", 3, true) end

    stopAutomation(true)
    Auto.running = true
    Auto.runId += 1
    local id = Auto.runId
    if not onlyStep then
        notify("Automation", "Started \"" .. a.name .. "\"", 2, true)
        webhookEvent("Automation started", "Automation started", a.name, 0x5865F2)

        -- Safety watcher
        task.spawn(function()
            local startedAt = os.clock()
            while autoAlive(id) do
                local reason = checkSafety(a, startedAt)
                if reason and autoAlive(id) then return triggerSafety(a, reason) end
                task.wait(0.5)
            end
        end)
    end

    -- Label lookup always uses the full step list (so "Run this step only" can check labels)
    local labels = {}
    for index, s in ipairs(a.steps) do
        if s.type == "Label" and trim(s.value or "") ~= "" then
            labels[trim(s.value):lower()] = labels[trim(s.value):lower()] or index
        end
    end

    task.spawn(function()
        local loops = 0
        local stopped = false
        local ok, err = pcall(function()
            while autoAlive(id) do
                loops += 1
                local ctx = {
                    labels = labels, counters = {}, testing = onlyStep ~= nil,
                    extra = { automation = a.name, loop = loops },
                }
                local i, instantSteps = 1, 0
                while i <= #steps do
                    if not autoAlive(id) then return end
                    local step = steps[i]
                    ctx.index = i
                    setStatus(("%s  |  loop %d  |  step %d/%d\n%s"):format(a.name, loops, i, #steps, stepSummary(step)))
                    local action, target = runStep(step, id, a.name, ctx)

                    if action == "stop" then
                        stopped = true
                        return
                    elseif action == "jump" then
                        i = target
                    else
                        i += 1
                    end

                    if CONTROL_STEPS[step.type] then
                        -- jumps with no real actions in between could freeze the game
                        instantSteps += 1
                        if instantSteps >= 50 then
                            instantSteps = 0
                            task.wait()
                        end
                    else
                        instantSteps = 0
                        if (a.stepDelay or 0) > 0 and not autoSleep(id, a.stepDelay) then return end
                    end
                end
                if onlyStep or not a.loop then break end
                if (a.loopCount or 0) > 0 and loops >= a.loopCount then break end
                task.wait()
            end
        end)
        if Auto.runId ~= id then return end -- stopped or replaced by another run
        Auto.running = false
        autoNoclip = false
        local loopText = ("%d loop%s"):format(loops, loops == 1 and "" or "s")
        if not ok then
            setStatus("Error: " .. tostring(err))
            notify("Automation", "Error: " .. tostring(err), 6, true)
            if not onlyStep then webhookEvent("Automation error", "Automation error: " .. a.name, tostring(err), 0xED4245) end
        elseif onlyStep then
            setStatus("Ran one step of \"" .. a.name .. "\"")
        elseif stopped then
            setStatus(("Stopped by a Stop step in \"%s\""):format(a.name))
            notify("Automation", "\"" .. a.name .. "\" reached a Stop step", 3, true)
            webhookEvent("Automation finished", "Automation finished", a.name .. " reached a Stop step after " .. loopText, 0x3BA55D)
        else
            setStatus(("Finished \"%s\" (%s)"):format(a.name, loopText))
            notify("Automation", "Finished \"" .. a.name .. "\"", 3, true)
            webhookEvent("Automation finished", "Automation finished", a.name .. " finished after " .. loopText, 0x3BA55D)
        end
    end)
end

----------------------------------------------------------------------
-- Automation: multi-line code editor (Fluent inputs are single-line,
-- which breaks pasted remote code with comments / newlines)
----------------------------------------------------------------------
local editorGui

local function closeEditor()
    if editorGui then editorGui:Destroy() end
    editorGui = nil
end

local function openEditor(title, initial, onSave)
    closeEditor()
    local gui = Instance.new("ScreenGui")
    gui.Name = "UH_Editor"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 1000
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = guiParent
    editorGui = gui

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.Size = UDim2.fromOffset(580, 380)
    frame.BackgroundColor3 = Color3.fromRGB(28, 28, 33)
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(70, 70, 80)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.BackgroundTransparency = 1
    titleLabel.Position = UDim2.fromOffset(14, 8)
    titleLabel.Size = UDim2.new(1, -28, 0, 24)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 15
    titleLabel.TextColor3 = Color3.new(1, 1, 1)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextScaled = true -- long titles (with helper hints) shrink to fit
    local sizeLimit = Instance.new("UITextSizeConstraint", titleLabel)
    sizeLimit.MaxTextSize = 15
    titleLabel.Text = title
    titleLabel.Parent = frame

    local scroll = Instance.new("ScrollingFrame")
    scroll.Position = UDim2.fromOffset(12, 40)
    scroll.Size = UDim2.new(1, -24, 1, -96)
    scroll.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.CanvasSize = UDim2.new()
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
    scroll.Parent = frame
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 6)

    local box = Instance.new("TextBox")
    box.BackgroundTransparency = 1
    box.Size = UDim2.fromScale(1, 1)
    box.AutomaticSize = Enum.AutomaticSize.XY
    box.MultiLine = true
    box.ClearTextOnFocus = false
    box.TextWrapped = false
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextYAlignment = Enum.TextYAlignment.Top
    box.Font = Enum.Font.Code
    box.TextSize = 14
    box.TextColor3 = Color3.fromRGB(230, 230, 235)
    box.PlaceholderText = "Paste here..."
    box.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
    box.Text = initial or ""
    box.Parent = scroll
    local pad = Instance.new("UIPadding", box)
    pad.PaddingLeft, pad.PaddingTop, pad.PaddingRight, pad.PaddingBottom =
        UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)

    local function makeButton(text, color, xOffset, callback)
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(1, 1)
        b.Position = UDim2.new(1, xOffset, 1, -12)
        b.Size = UDim2.fromOffset(100, 32)
        b.BackgroundColor3 = color
        b.Font = Enum.Font.GothamBold
        b.TextSize = 14
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Text = text
        b.AutoButtonColor = true
        b.Parent = frame
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        b.MouseButton1Click:Connect(callback)
    end
    makeButton("Save", Color3.fromRGB(70, 120, 230), -12, function()
        local text = box.Text
        closeEditor()
        onSave(text)
    end)
    makeButton("Cancel", Color3.fromRGB(60, 60, 68), -122, closeEditor)
end

----------------------------------------------------------------------
-- Automation: tab UI
----------------------------------------------------------------------
local currentAuto, selectedStep
local syncingAuto = false
local AutoListSection, StepListSection
local renderAutomations, renderSteps

local function gameAutomations()
    local list = {}
    for _, a in ipairs(Automations) do
        if tonumber(a.placeId) == game.PlaceId then table.insert(list, a) end
    end
    return list
end

local function findAutomation(name)
    for i, a in ipairs(Automations) do
        if tonumber(a.placeId) == game.PlaceId and a.name == name then return a, i end
    end
end

local function takenAutoNames()
    local taken = {}
    for _, a in ipairs(gameAutomations()) do taken[a.name] = true end
    return taken
end

local function resolvePosition(value)
    value = trim(value)
    if value == "" then
        local hrp = getHRP()
        if not hrp then return nil end
        return hrp.Position, hrp.CFrame.LookVector, nil
    end
    for _, w in ipairs(gameWaypoints()) do
        if w.name:lower() == value:lower() then
            return Vector3.new(w.x, w.y, w.z), Vector3.new(w.lx or 0, 0, w.lz or 0), "waypoint \"" .. w.name .. "\""
        end
    end
    local pos = parseCoords(value)
    return pos, nil, nil
end

-- Builds a step of `stepType` from `value` (opens the editor for code steps).
-- `existing` is passed when editing, so the editor starts with the old code.
local function buildStep(stepType, value, existing, done)
    local step = { type = stepType }
    value = trim(value)

    if POSITION_STEPS[stepType] then
        local pos, look, label = resolvePosition(value)
        if not pos then
            return notify("Automation", "Couldn't find that position. Use a waypoint name or x, y, z.", 4, true)
        end
        step.x, step.y, step.z = pos.X, pos.Y, pos.Z
        if look then step.lx, step.lz = look.X, look.Z end
        step.label = label
        return done(step)
    elseif stepType == "Interact" then
        step.value = value
        step.range = Options.InteractRange.Value
        return done(step)
    elseif CODE_STEPS[stepType] then
        if stepType == "Wait until" then
            if value ~= "" and not tonumber(value) then
                return notify("Automation", "Timeout must be a number of seconds.", 3, true)
            end
            step.value = value ~= "" and value or (existing and existing.value) or "30"
        elseif stepType == "If condition, go to label" then
            step.value = value ~= "" and value or (existing and existing.value) or ""
            if step.value == "" then
                return notify("Automation", "Type the label to jump to in the Value field.", 3, true)
            end
        end
        local helpersHint = "  |  helpers: stat(\"Coins\"), health(), dist(x,y,z), hasTool(\"Sword\"), find(\"Boss\")"
        local title = "Run code / Fire event: paste your code"
        if stepType == "Wait until" then
            title = "Wait until: condition, e.g. stat(\"Coins\") >= 100" .. helpersHint
        elseif stepType == "If condition, go to label" then
            title = "If: condition, e.g. health() < 30" .. helpersHint
        end
        return openEditor(title, existing and existing.code or "", function(code)
            if trim(code) == "" then return notify("Automation", "Code was empty, step not saved.", 3, true) end
            step.code = code
            done(step)
        end)
    elseif stepType == "Wait" then
        if not tonumber(value) then return notify("Automation", "Enter the number of seconds to wait.", 3, true) end
    elseif stepType == "Press key" then
        local name = value:sub(1, 1):upper() .. value:sub(2)
        local ok, key = pcall(function() return Enum.KeyCode[name] end)
        if value == "" or not ok or not key then
            return notify("Automation", "Unknown key. Examples: E, F, Space, One, LeftShift", 4, true)
        end
        value = name
    elseif stepType == "Label" or stepType == "Go to label" then
        if value == "" then return notify("Automation", "Type a label name in the Value field.", 3, true) end
    elseif stepType == "Repeat from label" then
        if not parseRepeat(value) then
            return notify("Automation", "Use \"label, times\", e.g. farm, 5", 3, true)
        end
    end
    step.value = value
    done(step)
end

local function stepLabel(i, s) return i .. ". " .. stepSummary(s) end

do
    local A = Tabs.Automation:AddSection("Automations (this game)")
    A:AddDropdown("AutoSelect", { Title = "Automation", Values = {}, Default = nil })
    A:AddInput("AutoName", { Title = "Name", Default = "", Placeholder = "e.g. Coin farm" })
    A:AddButton({
        Title = "New automation",
        Description = "Saved for this game (PlaceId " .. game.PlaceId .. ")",
        Callback = function()
            local name = trim(Options.AutoName.Value)
            if name == "" then name = "Automation" end
            name = uniqueName(name, takenAutoNames())
            local a = { name = name, placeId = game.PlaceId, steps = {}, loop = false, loopCount = 0, stepDelay = 0.2, autoStart = false }
            table.insert(Automations, a)
            saveAutomations()
            currentAuto = a
            Options.AutoName:SetValue("")
            renderAutomations()
            notify("Automation", "Created \"" .. name .. "\". Add steps below.", 3, true)
        end,
    })
    A:AddButton({
        Title = "Rename selected",
        Description = "Uses the Name field",
        Callback = function()
            local name = trim(Options.AutoName.Value)
            if not currentAuto then return notify("Automation", "Select an automation first.", 3, true) end
            if name == "" then return notify("Automation", "Type a new name first.", 3, true) end
            local taken = takenAutoNames()
            taken[currentAuto.name] = nil
            currentAuto.name = uniqueName(name, taken)
            saveAutomations()
            Options.AutoName:SetValue("")
            renderAutomations()
        end,
    })
    A:AddButton({
        Title = "Duplicate selected",
        Callback = function()
            if not currentAuto then return notify("Automation", "Select an automation first.", 3, true) end
            local copyA = HttpService:JSONDecode(HttpService:JSONEncode(currentAuto))
            copyA.name = uniqueName(currentAuto.name, takenAutoNames())
            copyA.autoStart = false
            table.insert(Automations, copyA)
            saveAutomations()
            currentAuto = copyA
            renderAutomations()
        end,
    })
    A:AddButton({
        Title = "Delete selected",
        Callback = function()
            local a = currentAuto
            if not a then return notify("Automation", "Select an automation first.", 3, true) end
            Window:Dialog({
                Title = "Delete automation",
                Content = "Delete \"" .. a.name .. "\" and all its steps?",
                Buttons = {
                    { Title = "Delete", Callback = function()
                        local _, i = findAutomation(a.name)
                        if i then table.remove(Automations, i) end
                        if Auto.running then stopAutomation(true) end
                        currentAuto, selectedStep = nil, nil
                        saveAutomations()
                        renderAutomations()
                        notify("Automation", "Deleted \"" .. a.name .. "\"", 3, true)
                    end },
                    { Title = "Cancel" },
                },
            })
        end,
    })

    local R = Tabs.Automation:AddSection("Run")
    Auto.statusPara = R:AddParagraph({ Title = "Status", Content = "Idle" })
    R:AddButton({ Title = "Run", Description = "Runs the selected automation", Callback = function() runAutomation(currentAuto) end })
    R:AddButton({ Title = "Stop", Callback = function() stopAutomation() end })
    R:AddKeybind("AutoRunKey", { Title = "Run / stop keybind", Mode = "Toggle", Default = "P" })

    -- Steps list right under Run; adding / editing / options follow below
    StepListSection = Tabs.Automation:AddSection("Steps (click to select)")

    local S = Tabs.Automation:AddSection("Add Step")
    S:AddDropdown("StepType", { Title = "Action", Values = STEP_TYPES, Default = "Teleport" })
    S:AddInput("StepValue", { Title = "Value", Default = "", Placeholder = "see hint below the title" })
    S:AddSlider("InteractRange", { Title = "Interact range", Description = "Used by new Interact steps", Default = 20, Min = 5, Max = 200, Increment = 1, Suffix = " studs" })
    S:AddToggle("InsertAfterSelected", { Title = "Insert after selected step", Description = "Off = add to the end", Default = false })
    S:AddButton({
        Title = "Add step",
        Callback = function()
            local a = currentAuto
            if not a then return notify("Automation", "Create or select an automation first.", 3, true) end
            buildStep(Options.StepType.Value, Options.StepValue.Value, nil, function(step)
                local index = #a.steps + 1
                if Options.InsertAfterSelected.Value and selectedStep and a.steps[selectedStep] then
                    index = selectedStep + 1
                end
                table.insert(a.steps, index, step)
                selectedStep = index
                saveAutomations()
                Options.StepValue:SetValue("")
                renderSteps()
                notify("Automation", "Added: " .. stepSummary(step), 2)
            end)
        end,
    })

    local E = Tabs.Automation:AddSection("Edit Selected Step")
    E:AddDropdown("StepSelect", { Title = "Step", Values = {}, Default = nil })
    local function withStep(fn)
        return function()
            local a = currentAuto
            local s = a and selectedStep and a.steps[selectedStep]
            if not s then return notify("Automation", "Select a step first (click it in the list).", 3, true) end
            fn(a, s, selectedStep)
        end
    end
    E:AddButton({ Title = "Run this step only", Callback = withStep(function(a, s) runAutomation(a, s) end) })
    E:AddButton({
        Title = "Edit step",
        Description = "Position steps: re-captures from the Value field (empty = current spot). Code steps: opens the editor",
        Callback = withStep(function(a, s, i)
            buildStep(s.type, Options.StepValue.Value, s, function(step)
                a.steps[i] = step
                saveAutomations()
                Options.StepValue:SetValue("")
                renderSteps()
                notify("Automation", "Updated: " .. stepSummary(step), 2)
            end)
        end),
    })
    E:AddButton({
        Title = "Move up",
        Callback = withStep(function(a, s, i)
            if i <= 1 then return end
            a.steps[i], a.steps[i - 1] = a.steps[i - 1], a.steps[i]
            selectedStep = i - 1
            saveAutomations()
            renderSteps()
        end),
    })
    E:AddButton({
        Title = "Move down",
        Callback = withStep(function(a, s, i)
            if i >= #a.steps then return end
            a.steps[i], a.steps[i + 1] = a.steps[i + 1], a.steps[i]
            selectedStep = i + 1
            saveAutomations()
            renderSteps()
        end),
    })
    E:AddButton({
        Title = "Duplicate step",
        Callback = withStep(function(a, s, i)
            table.insert(a.steps, i + 1, HttpService:JSONDecode(HttpService:JSONEncode(s)))
            selectedStep = i + 1
            saveAutomations()
            renderSteps()
        end),
    })
    E:AddButton({
        Title = "Delete step",
        Callback = withStep(function(a, s, i)
            table.remove(a.steps, i)
            selectedStep = math.min(i, #a.steps)
            if selectedStep == 0 then selectedStep = nil end
            saveAutomations()
            renderSteps()
        end),
    })

    local O = Tabs.Automation:AddSection("Loop & Auto-start")
    O:AddToggle("AutoLoop", { Title = "Loop", Description = "Repeat the steps when they finish", Default = false })
    O:AddSlider("AutoLoopCount", { Title = "Loop count", Description = "0 = forever", Default = 0, Min = 0, Max = 1000, Increment = 1 })
    O:AddSlider("AutoStepDelay", { Title = "Delay between steps", Default = 0.2, Min = 0, Max = 10, Increment = 0.1, Suffix = "s" })
    O:AddToggle("AutoStartOnJoin", { Title = "Auto-start when I join", Description = "Also after a server hop", Default = false })

    local F = Tabs.Automation:AddSection("Safety (0 = off)")
    F:AddSlider("SafetyRange", { Title = "Stop if a player comes within", Default = 0, Min = 0, Max = 500, Increment = 5, Suffix = " studs" })
    F:AddToggle("SafetyIgnoreFriends", { Title = "Ignore friends", Default = true })
    F:AddSlider("SafetyHealth", { Title = "Stop if health drops to", Default = 0, Min = 0, Max = 100, Increment = 1, Suffix = "%" })
    F:AddSlider("SafetyMinutes", { Title = "Stop after", Default = 0, Min = 0, Max = 600, Increment = 1, Suffix = " min" })
    F:AddDropdown("SafetyAction", {
        Title = "Then",
        Description = "Server hop + auto-start keeps farming in a fresh server",
        Values = SAFETY_ACTIONS,
        Default = "Stop",
    })

    local X = Tabs.Automation:AddSection("Share")
    X:AddButton({
        Title = "Export selected to clipboard",
        Description = "Copies the automation as text so you can back it up or share it",
        Callback = function()
            if not currentAuto then return notify("Automation", "Select an automation first.", 3, true) end
            copy(HttpService:JSONEncode(currentAuto))
        end,
    })
    X:AddButton({
        Title = "Import automation",
        Description = "Paste exported text; it's added to this game",
        Callback = function()
            openEditor("Import automation: paste exported text", "", function(text)
                local ok, data = pcall(function() return HttpService:JSONDecode(text) end)
                if not ok or type(data) ~= "table" or type(data.steps) ~= "table" then
                    return notify("Automation", "That isn't a valid exported automation.", 4, true)
                end
                data.placeId = game.PlaceId
                data.name = uniqueName(tostring(data.name or "Imported"), takenAutoNames())
                data.autoStart = false
                table.insert(Automations, data)
                saveAutomations()
                currentAuto = data
                renderAutomations()
                notify("Automation", "Imported \"" .. data.name .. "\"", 3, true)
            end)
        end,
    })
end

local stepButtons = {}
renderSteps = function()
    for _, b in ipairs(stepButtons) do pcall(function() b:Destroy() end) end
    table.clear(stepButtons)

    local a = currentAuto
    local labels = {}
    if not a then
        table.insert(stepButtons, StepListSection:AddButton({ Title = "No automation selected", Description = "Create or select one above", Callback = function() end }))
    elseif #a.steps == 0 then
        table.insert(stepButtons, StepListSection:AddButton({ Title = "No steps yet", Description = "Add one in the Add Step section", Callback = function() end }))
    else
        for i, s in ipairs(a.steps) do
            local label = stepLabel(i, s)
            labels[i] = label
            table.insert(stepButtons, StepListSection:AddButton({
                Title = (i == selectedStep and "> " or "") .. i .. ". " .. s.type,
                Description = stepSummary(s),
                Callback = function()
                    selectedStep = i
                    renderSteps()
                end,
            }))
        end
    end

    if selectedStep and not (a and a.steps[selectedStep]) then selectedStep = nil end
    syncingAuto = true
    Options.StepSelect:SetValues(labels)
    Options.StepSelect:SetValue(selectedStep and labels[selectedStep] or nil)
    syncingAuto = false
end

renderAutomations = function()
    local names = {}
    for _, a in ipairs(gameAutomations()) do table.insert(names, a.name) end
    if currentAuto and not findAutomation(currentAuto.name) then currentAuto = nil end

    syncingAuto = true
    Options.AutoSelect:SetValues(names)
    Options.AutoSelect:SetValue(currentAuto and currentAuto.name or nil)
    Options.AutoLoop:SetValue(currentAuto and currentAuto.loop or false)
    Options.AutoLoopCount:SetValue(currentAuto and currentAuto.loopCount or 0)
    Options.AutoStepDelay:SetValue(currentAuto and currentAuto.stepDelay or 0.2)
    Options.AutoStartOnJoin:SetValue(currentAuto and currentAuto.autoStart or false)
    Options.SafetyRange:SetValue(currentAuto and currentAuto.safetyRange or 0)
    Options.SafetyIgnoreFriends:SetValue(not currentAuto or currentAuto.safetyIgnoreFriends ~= false)
    Options.SafetyHealth:SetValue(currentAuto and currentAuto.safetyHealth or 0)
    Options.SafetyMinutes:SetValue(currentAuto and currentAuto.safetyMinutes or 0)
    Options.SafetyAction:SetValue(currentAuto and currentAuto.safetyAction or "Stop")
    syncingAuto = false
    renderSteps()
end

-- Wiring for the automation controls
Options.AutoSelect:OnChanged(function(name)
    if syncingAuto then return end
    currentAuto = name and findAutomation(name) or nil
    selectedStep = nil
    renderAutomations()
end)
Options.StepSelect:OnChanged(function(label)
    if syncingAuto then return end
    local i = label and tonumber(label:match("^(%d+)%."))
    if i ~= selectedStep then
        selectedStep = i
        renderSteps()
    end
end)
Options.StepType:OnChanged(function(stepType)
    pcall(function() Options.StepValue:SetDesc(STEP_HINTS[stepType] or "") end)
end)

local function bindAutoSetting(idx, field)
    Options[idx]:OnChanged(function(value)
        if syncingAuto or not currentAuto then return end
        currentAuto[field] = value
        if field == "autoStart" and value then
            -- only one automation per game auto-starts
            for _, other in ipairs(gameAutomations()) do
                if other ~= currentAuto then other.autoStart = false end
            end
        end
        saveAutomations()
    end)
end
bindAutoSetting("AutoLoop", "loop")
bindAutoSetting("AutoLoopCount", "loopCount")
bindAutoSetting("AutoStepDelay", "stepDelay")
bindAutoSetting("AutoStartOnJoin", "autoStart")
bindAutoSetting("SafetyRange", "safetyRange")
bindAutoSetting("SafetyIgnoreFriends", "safetyIgnoreFriends")
bindAutoSetting("SafetyHealth", "safetyHealth")
bindAutoSetting("SafetyMinutes", "safetyMinutes")
bindAutoSetting("SafetyAction", "safetyAction")

Options.AutoRunKey:OnClick(function()
    if UIS:GetFocusedTextBox() then return end
    if Auto.running then stopAutomation() else runAutomation(currentAuto) end
end)

----------------------------------------------------------------------
-- Game tab: loads a feature module for the game you're in.
-- Lookup order (first found wins):
--   1. local  UniversalHub/games/place_<PlaceId>.lua
--   2. local  UniversalHub/games/<GameId>.lua
--   3. GitHub games/place_<PlaceId>.lua
--   4. GitHub games/<GameId>.lua
-- GameId covers every place of a game (lobby, matches, ...).
----------------------------------------------------------------------
local GameModule = { cleanups = {} }
-- Use the exact commit the loader resolved (branch URLs can be stale for minutes)
local GAME_REPO = "https://raw.githubusercontent.com/Hund335/Universal-Hub/"
    .. tostring(getgenv and getgenv().UniversalHub_Ref or "main") .. "/games/"

local GAME_TEMPLATE = [==[
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
]==]

local function readLocalGameModule(file)
    if not hasFS then return nil end
    local path = FOLDER .. "/games/" .. file
    local ok, exists = pcall(isfile, path)
    if not ok or not exists then return nil end
    local okRead, src = pcall(readfile, path)
    return okRead and src or nil
end

local function fetchGameModule(file)
    local ok, body = pcall(function() return game:HttpGet(GAME_REPO .. file) end)
    if ok and type(body) == "string" and trim(body) ~= "" and not body:match("^%s*404") then
        return body
    end
end

local function findGameModule()
    local files = { "place_" .. game.PlaceId .. ".lua", game.GameId .. ".lua" }
    for _, file in ipairs(files) do
        local src = readLocalGameModule(file)
        if src then return src, "local file " .. file end
    end
    for _, file in ipairs(files) do
        local src = fetchGameModule(file)
        if src then return src, "GitHub " .. file end
    end
end

local function firePrompt(prompt)
    if typeof(fireproximityprompt) == "function" and pcall(fireproximityprompt, prompt) then return true end
    prompt:InputHoldBegin()
    task.wait(prompt.HoldDuration + 0.05)
    prompt:InputHoldEnd()
    return true
end

-- The `hub` table every module's Init receives
local function makeGameAPI(tab)
    local api = {
        Tab = tab, Window = Window, Library = Library, Options = Options,
        Player = LP, PlaceId = game.PlaceId, GameId = game.GameId, GameName = gameName(),
        Services = setmetatable({}, { __index = function(_, name) return game:GetService(name) end }),
    }

    function api.id(name) return "Game_" .. tostring(name) end
    function api.notify(title, text, duration) notify(title, text, duration, true) end
    function api.webhook(title, message, color) sendWebhook(title, fillPlaceholders(message), color) end
    function api.getCharacter() return LP.Character end
    api.getRoot, api.getHumanoid = getHRP, getHum
    api.stat = CodeHelpers.stat
    api.firePrompt = firePrompt
    api.serverHop, api.rejoin = serverHop, rejoin

    -- Teleport to a Vector3, CFrame, Part or Model (uses the Teleport tab mode)
    function api.teleport(target)
        local cf
        if typeof(target) == "CFrame" then
            cf = target
        elseif typeof(target) == "Vector3" then
            cf = CFrame.new(target)
        elseif typeof(target) == "Instance" then
            cf = (target:IsA("Model") and target:GetPivot() or target.CFrame) + Vector3.new(0, 3, 0)
        end
        if cf then teleportTo(cf) end
    end

    -- Connections made here are disconnected when the hub unloads
    api.connect = connect
    function api.onUnload(fn) table.insert(GameModule.cleanups, fn) end

    -- Runs fn every `interval` seconds until the hub unloads (or the returned stop() is called)
    function api.loop(interval, fn)
        local running = true
        task.spawn(function()
            while running and not Library.Unloaded do
                local ok, err = pcall(fn)
                if not ok then warn("[Universal Hub game module] " .. tostring(err)) end
                task.wait(interval or 0.5)
            end
        end)
        local function stop() running = false end
        table.insert(GameModule.cleanups, stop)
        return stop
    end

    -- Toggle + loop in one: fn runs every Interval seconds while the toggle is on
    function api.autoToggle(section, idx, config, fn)
        local toggle = section:AddToggle(idx, {
            Title = config.Title or idx,
            Description = config.Description,
            Default = config.Default or false,
        })
        api.loop(config.Interval or 0.5, function()
            if toggle.Value then fn() end
        end)
        return toggle
    end

    -- Expose a function to automation conditions / code steps, e.g. If coins() > 100
    function api.addHelper(name, fn) CodeHelpers[name] = fn end

    return api
end

do
    local tab = Tabs.Game
    local info = tab:AddSection("This game")
    local status = info:AddParagraph({
        Title = gameName(),
        Content = ("GameId %d  |  PlaceId %d\nLooking for a game module..."):format(game.GameId, game.PlaceId),
    })
    local function setInfo(text)
        pcall(function() status:SetDesc(("GameId %d  |  PlaceId %d\n%s"):format(game.GameId, game.PlaceId, text)) end)
    end

    local src, from = findGameModule()
    if not src then
        setInfo("No module for this game yet. Use the buttons below to make one.")
    else
        local fn, compileErr = loadstring(src)
        local ok, result = false, compileErr
        if fn then ok, result = pcall(fn) end
        local init = ok and (type(result) == "function" and result or (type(result) == "table" and (result.Init or result.init)))
        if not fn then
            setInfo("Module from " .. from .. " has a syntax error:\n" .. tostring(compileErr))
        elseif not ok then
            setInfo("Module from " .. from .. " errored:\n" .. tostring(result))
        elseif not init then
            setInfo("Module from " .. from .. " must return a function or a table with Init.")
        else
            local okInit, initErr = pcall(init, makeGameAPI(tab))
            local name = type(result) == "table" and result.Name or "Game module"
            local version = type(result) == "table" and result.Version and (" v" .. result.Version) or ""
            if okInit then
                GameModule.name = name
                setInfo(("Loaded %s%s from %s"):format(name, version, from))
            else
                setInfo(("%s%s failed in Init:\n%s"):format(name, version, tostring(initErr)))
                notify("Game module", name .. " failed to load, see the Game tab.", 6, true)
            end
        end
    end

    local tools = tab:AddSection("Module tools")
    tools:AddButton({
        Title = "Create local module for this game",
        Description = "Writes a template to UniversalHub/games/" .. game.GameId .. ".lua (edit it, then re-execute the hub)",
        Callback = function()
            if not hasFS then return notify("Game module", "Your executor has no file functions.", 4, true) end
            local path = FOLDER .. "/games/" .. game.GameId .. ".lua"
            pcall(function()
                if not isfolder(FOLDER .. "/games") then makefolder(FOLDER .. "/games") end
            end)
            if readLocalGameModule(game.GameId .. ".lua") then
                return notify("Game module", "A local module already exists: " .. path, 5, true)
            end
            local safeName = gameName():gsub('"', "'")
            local template = GAME_TEMPLATE:gsub('Name = "My Game"', function() return 'Name = "' .. safeName .. '"' end, 1)
            local ok = pcall(writefile, path, template)
            notify("Game module", ok and ("Created " .. path) or "Couldn't write the file.", 5, true)
        end,
    })
    tools:AddButton({ Title = "Copy module template", Callback = function() copy(GAME_TEMPLATE) end })
    tools:AddButton({ Title = "Copy GameId", Callback = function() copy(tostring(game.GameId)) end })
end

----------------------------------------------------------------------
-- Settings tab
----------------------------------------------------------------------
local Defaults = {}
local unload -- defined below
local autoSaveStatus -- paragraph in Settings > Hub
local activeConfig   -- config that auto-save writes to (last loaded/saved, or autoload)
local autoSaving = false

do
    local H = Tabs.Settings:AddSection("Hub")
    H:AddToggle("ShowNotifications", { Title = "Show notifications", Description = "Errors always show", Default = true })
    H:AddToggle("AutoSave", {
        Title = "Auto-save settings",
        Description = "Saves changes to your active config about a second after you make them",
        Default = true,
    })
    autoSaveStatus = H:AddParagraph({ Title = "Auto-save", Content = "Starting..." })
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
    -- automation fields belong to each saved automation, not to configs
    "AutoSelect", "AutoName", "AutoLoop", "AutoLoopCount", "AutoStepDelay", "AutoStartOnJoin",
    "StepType", "StepValue", "StepSelect", "InsertAfterSelected",
    "SafetyRange", "SafetyIgnoreFriends", "SafetyHealth", "SafetyMinutes", "SafetyAction",
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
        if results[1] then activeConfig = (...) end -- auto-save now writes to the loaded config
        return table.unpack(results, 1, results.n)
    end

    -- A manual save / create / overwrite makes that config the auto-save target
    local originalSave = SaveManager.Save
    SaveManager.Save = function(self, name, ...)
        local results = table.pack(originalSave(self, name, ...))
        if results[1] and not autoSaving then activeConfig = name end
        return table.unpack(results, 1, results.n)
    end
end

----------------------------------------------------------------------
-- Wiring: notifications, keybinds, events
----------------------------------------------------------------------
local ToggleLabels = {
    WalkSpeedEnabled = "WalkSpeed", JumpEnabled = "Jump Height", InfiniteJump = "Infinite Jump",
    Fly = "Fly", LegacyFly = "Legacy Fly", Noclip = "Noclip", GravityEnabled = "Gravity", ClickTP = "Click Teleport",
    TweenNoclip = "Tween Noclip", Fullbright = "Fullbright", NoFog = "No Fog", FOVEnabled = "Custom FOV",
    InfiniteZoom = "Infinite Zoom", ESP = "ESP", AntiAFK = "Anti-AFK", FPSUnlock = "FPS Unlock",
    SpinBot = "Spinbot",
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
    SpinBotKey = "SpinBot",
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

-- Spinbot keeps its own angle and sets the yaw directly, so it also works
-- while flying (fly re-aims the character every frame)
local spinAngle
connect(RunService.RenderStepped, function(dt)
    if Options.Fly.Value then
        updateFly(dt)
    elseif Fly.active then
        stopFly()
    end

    if Options.SpinBot.Value then
        local hrp = getHRP()
        if hrp then
            if not spinAngle then
                local look = hrp.CFrame.LookVector
                spinAngle = math.atan2(-look.X, -look.Z)
            end
            local direction = Options.SpinDirection.Value == "Left" and 1 or -1
            spinAngle = (spinAngle + direction * math.rad(Options.SpinSpeed.Value) * math.min(dt, 0.1)) % (2 * math.pi)
            hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, spinAngle, 0)
        end
    else
        spinAngle = nil
    end

    updateTracers()
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

    pcall(stopAutomation, true)
    pcall(closeEditor)
    for _, cleanup in ipairs(GameModule.cleanups) do pcall(cleanup) end
    cancelTween()
    pcall(stopFly)
    pcall(restoreNoclip)
    pcall(applyState, true)
    pcall(clearESP)
    if aimbotCleanup then pcall(aimbotCleanup) end
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
do -- preselect this game's first automation
    local list = gameAutomations()
    currentAuto = list[1]
    renderAutomations()
end

Window:SelectTab(1)
SaveManager:LoadAutoloadConfig()
silent = false

----------------------------------------------------------------------
-- Auto-save: every second, compare all saved settings with the last save.
-- Once a change has stayed the same for a second, write it to the active
-- config. With no config yet, creates "autosave" and makes it the autoload.
----------------------------------------------------------------------
do
    local autoloadPath = SaveManager.Folder .. "/settings/autoload.txt"

    local function readAutoload()
        if not hasFS then return nil end
        local ok, exists = pcall(isfile, autoloadPath)
        if not ok or not exists then return nil end
        local okRead, name = pcall(readfile, autoloadPath)
        name = okRead and trim(name) or ""
        return name ~= "" and name or nil
    end

    local function setStatus(text)
        pcall(function() autoSaveStatus:SetDesc(text) end)
    end

    -- One line per saved option, so any change produces a different string
    local function snapshotSettings()
        local lines = {}
        for idx, opt in pairs(Options) do
            if not SaveManager.Ignore[idx] then
                local v = opt.Value
                if opt.Type == "Keybind" then
                    v = tostring(v) .. "/" .. tostring(opt.Mode)
                elseif opt.Type == "Colorpicker" then
                    v = (typeof(v) == "Color3" and v:ToHex() or tostring(v)) .. "/" .. tostring(opt.Transparency)
                elseif type(v) == "table" then
                    local keys = {}
                    for k, on in pairs(v) do if on then table.insert(keys, tostring(k)) end end
                    table.sort(keys)
                    v = table.concat(keys, ",")
                end
                table.insert(lines, idx .. "=" .. tostring(v))
            end
        end
        table.sort(lines)
        return table.concat(lines, "\n")
    end

    activeConfig = activeConfig or readAutoload()
    if not hasFS then
        setStatus("Your executor has no file functions, so settings can't be saved.")
    elseif activeConfig then
        setStatus(("Changes save to config \"%s\" automatically."):format(activeConfig))
    else
        setStatus("Your first change creates config \"autosave\" (and loads it automatically next time).")
    end

    local lastSaved = snapshotSettings()
    local lastSeen = lastSaved
    task.spawn(function()
        while not unloaded and not Library.Unloaded do
            task.wait(1)
            if hasFS and Options.AutoSave and Options.AutoSave.Value then
                local snap = snapshotSettings()
                -- save only once the change has settled (e.g. not mid-slider-drag)
                if snap ~= lastSaved and snap == lastSeen then
                    local firstConfig = not activeConfig
                    activeConfig = activeConfig or "autosave"
                    autoSaving = true
                    local ok, err = SaveManager:Save(activeConfig)
                    autoSaving = false
                    if ok then
                        lastSaved = snap
                        if firstConfig then
                            pcall(writefile, autoloadPath, activeConfig)
                            pcall(function() Options.SaveManager_ConfigList:SetValues(SaveManager:RefreshConfigList()) end)
                        end
                        setStatus(("Changes save to config \"%s\" automatically.\nLast saved %s"):format(activeConfig, os.date("%H:%M:%S")))
                    else
                        setStatus("Auto-save failed: " .. tostring(err))
                    end
                end
                lastSeen = snap
            end
        end
    end)
end

if not hasFS then
    notify("Universal Hub", "Your executor has no file functions: waypoints, scripts and configs won't be saved.", 8, true)
end
notify("Universal Hub", "Loaded. RightShift hides the UI.", 5, true)
webhookEvent("Hub loaded", "Hub loaded", fillPlaceholders("{player} joined {game} ({players} players)"), 0x5865F2)

-- Auto-run scripts marked for this game
for _, s in ipairs(SavedScripts) do
    if type(s.autorun) == "table" and s.autorun[placeKey] then
        runScript(s)
    end
end

-- Auto-start the automation marked for this game (after scripts had a moment to load)
for _, a in ipairs(gameAutomations()) do
    if a.autoStart then
        currentAuto = a
        renderAutomations()
        notify("Automation", "Auto-starting \"" .. a.name .. "\" in 3s (press " .. tostring(Options.AutoRunKey.Value) .. " to stop)", 4, true)
        task.delay(3, function()
            if not unloaded then runAutomation(a) end
        end)
        break
    end
end
