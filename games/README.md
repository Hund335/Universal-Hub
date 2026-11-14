# Game modules

The hub's **Game** tab loads one module for the game you're in. It looks in this order and uses the first one it finds:

1. Local `UniversalHub/games/place_<PlaceId>.lua`
2. Local `UniversalHub/games/<GameId>.lua`
3. This folder: `place_<PlaceId>.lua`
4. This folder: `<GameId>.lua`

Use `<GameId>.lua` for a whole game (lobby, matches and every other place). Use `place_<PlaceId>.lua` only when one place needs different features. The Game tab shows both IDs and has a **Create local module for this game** button that writes a starter file.

Start from [`_template.lua`](_template.lua). A module returns a table with `Init(hub)`, or just a function:

```lua
return {
    Name = "My Game",
    Version = "1.0",
    Init = function(hub)
        local section = hub.Tab:AddSection("Farming")
        hub.autoToggle(section, hub.id("AutoCollect"), { Title = "Auto collect", Interval = 0.5 }, function()
            -- runs every 0.5s while the toggle is on
        end)
    end,
}
```

## The `hub` API

| Field | What it is |
|---|---|
| `hub.Tab` | This game's Fluent tab. Add sections, toggles, sliders and buttons to it |
| `hub.id(name)` | Prefixes an option id (`Game_<name>`). Module options still save in configs |
| `hub.autoToggle(section, id, {Title, Description, Default, Interval}, fn)` | Toggle that runs `fn` every `Interval` seconds while on |
| `hub.loop(interval, fn)` | Runs `fn` repeatedly until unload; returns `stop()` |
| `hub.connect(signal, fn)` | Like `:Connect`, but disconnected when the hub unloads |
| `hub.onUnload(fn)` | Cleanup when the hub unloads |
| `hub.teleport(target)` | Vector3, CFrame, Part or Model. Uses the Teleport tab mode (Instant or Tween) |
| `hub.firePrompt(prompt)` | Triggers a ProximityPrompt |
| `hub.getCharacter()` `hub.getRoot()` `hub.getHumanoid()` | Your character, HumanoidRootPart and Humanoid |
| `hub.stat("Coins")` | A leaderstats value |
| `hub.notify(title, text)` | Notification |
| `hub.webhook(title, message)` | Sends to the hub's Discord webhook (placeholders like `{player}` work) |
| `hub.serverHop()` `hub.rejoin()` | Same as the Misc tab buttons |
| `hub.addHelper(name, fn)` | Makes `fn` usable in automation conditions and code steps, e.g. `If coins() > 100` |
| `hub.Services.X` | `game:GetService("X")` |
| `hub.Player` `hub.PlaceId` `hub.GameId` `hub.GameName` | Info about the current game |
| `hub.Window` `hub.Library` `hub.Options` | The Fluent window, library and options table |

If a module errors, the Game tab shows the error and the rest of the hub keeps working.
