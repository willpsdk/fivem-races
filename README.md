# Races Framework - v1.2.0

A comprehensive multi-race framework for FiveM that features race management, vehicle transformations, dynamic props, and advanced race building tools.

**Author:** willpsdk

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Player Commands](#player-commands)
- [Admin/Builder Commands](#adminbuilder-commands)
- [Race Structure](#race-structure)
- [Checkpoint Types](#checkpoint-types)
- [Vehicle Transformations](#vehicle-transformations)
- [Race Exclusion](#race-exclusion)
- [Files & Configuration](#files--configuration)
- [Advanced Features](#advanced-features)

---

## Features

### Core Features
- 🏁 **Multi-race Management** - Create, edit, delete, and run multiple races
- 🚗 **Vehicle System** - Dynamic race vehicles with respawning
- 📍 **Checkpoint System** - Normal, transform, and warp checkpoints
- 🎨 **Dynamic Props** - Place and customize race props with scale and rotation
- 👥 **Leaderboard** - Real-time player leaderboard with distance tracking
- 🎮 **Race Builder** - Full in-game race creation tool via MenuAPI
- 🔒 **Player Exclusion** - Exclude specific players from races
- 💨 **Transform Effects** - Visual smoke effects when vehicles transform
- 📊 **Respawn System** - Smart respawning with maintained vehicle type

### Checkpoint Features
- **Normal Checkpoints** (Yellow/Blue) - Standard race checkpoints
- **Transform Checkpoints** (Orange/Pink):
  - Orange: Specific vehicle transforms (from UGC imports or pre-defined)
  - Pink: Randomized vehicle transforms (local races)
  - Maintains current vehicle on respawn
  - Visible smoke effects for all players
- **Warp Checkpoints** - Teleport points in races

### Advanced Features
- Import GTA Online races
- Checkpoint type detection and conversion
- Smart vehicle transform tracking across checkpoints
- Distance-based leaderboard updates
- Real-time prop rendering with physics
- Undo/redo system for prop placement

---

## Installation

1. **Extract to Resources**
   ```
   Place the races folder in your FiveM resources directory
   ```

2. **Update server.cfg**
   ```
   ensure races
   ```

4. **Start the Resource**
   ```
   /ensure races
   ```

---

## Player Commands

### Starting & Managing Races

#### `/race` or `/races`
- **Usage:** `/race` or `/races`
- **Description:** Opens the race selection menu
- **Permission:** Everyone
- **Aliases:** Both commands open the same race menu
- **In-Game Menu:** Browse and select races with details (checkpoints, start grid)

#### `/race <race_id>`
- **Usage:** `/race cityrace` or `/race waterrace`
- **Description:** Start a specific race by ID
- **Permission:** Everyone
- **Example:** `/race cityrace` - starts the "cityrace" race if it exists

### Race Mechanics

#### During Race
- **F Key** - Respawn at last checkpoint (after 2 seconds of holding)
- **Hold F (2+ seconds)** - Triggers respawn
- **10 second cooldown** between respawns

#### Checkpoint Progression
- Drive through checkpoints in order
- 3D checkpoints appear in the game world
- Minimap shows checkpoint locations (if not excluded)
- Smoke effects visible when transforming

---

## Admin/Builder Commands

### Race Management

#### `/endrace`
- **Description:** Immediately end the current active race
- **Permission:** Admin (console only works, but any player can use in-game)
- **Effect:** All players are teleported back; leaderboard is saved

#### `/racedelete <race_id>`
- **Usage:** `/racedelete cityrace`
- **Description:** Permanently delete a race from races.json
- **Permission:** Admin
- **Warning:** Cannot be undone

#### `/raceexclude <player_name_or_id>`
- **Usage:** `/raceexclude john` or `/raceexclude 127`
- **Description:** Exclude a player from the next race
- **Permission:** Admin
- **Features:**
  - Works with partial player names (case-insensitive)
  - Can also use exact player server ID
  - Exclusion automatically clears after race ends
  - Excluded players see 3D checkpoints but:
    - Cannot progress through checkpoints
    - Don't appear on minimap
    - Don't see countdown timer
    - Don't appear on leaderboard
    - Don't see checkpoint progress UI

---

## Race Builder Commands

### Builder Setup

#### `/racebuilder`
- **Description:** Start the race builder with auto-generated ID and name
- **Auto-ID:** `custom_<timestamp>`
- **Auto-Name:** `Custom Race <timestamp>`
- **Opens:** MenuAPI builder menu for prop placement and editing

#### `/racebuilder start <id> <vehicle> [name]`
- **Usage:** `/racebuilder start myracetrack adder "My Race Track"`
- **Parameters:**
  - `<id>` - Unique race identifier (lowercase, no spaces)
  - `<vehicle>` - Starting vehicle (e.g., adder, blista, seashark)
  - `[name]` - Optional display name (use quotes for multi-word names)

#### `/editrace <race_id>`
- **Usage:** `/editrace cityrace`
- **Description:** Edit an existing race
- **Opens:** MenuAPI builder menu for the race

### Builder Controls (MenuAPI)

#### Grid/Checkpoint Placement
- **Add Start Point:** Capture current player position as start grid location
- **Add Checkpoint:** Place a checkpoint at player location
- **Remove Start Point:** Remove nearest start grid point (6m radius)
- **Remove Checkpoint:** Remove nearest checkpoint (6m radius)

#### Checkpoint Type Selection
- **Toggle Checkpoint Type:** Switch between "normal" and "transform"
- **Checkpoint Types:**
  - Normal: Standard racing checkpoint
  - Transform: Vehicle change at this point

#### Prop Placement (MenuAPI)
- **Spawn Prop:** Load and place props by model name or hash
- **Move Props:** Use arrow keys or numpad directions
- **Rotate Props:** Numpad 4 (left), 6 (right)
- **Scale Props:** Numpad * (increase), - (decrease)
- **Delete Prop:** Remove selected prop
- **Undo/Redo:** Full history for prop operations

#### Session Management
- **View Status:** `/racebuilder status` - Show current session info
- **Save Race:** `/racebuilder save` - Save to races.json
- **Cancel:** `/racebuilder cancel` - Discard changes

### Import & Export

#### `/rbimportxml <resource:file.xml|file.xml>`
- **Usage:** `/rbimportxml cfx:gtav:races.xml` or `/rbimportxml races.xml`
- **Description:** Import GTA Online race missions from XML files
- **Features:**
  - Auto-converts checkpoints
  - Imports race metadata (name, vehicle, etc.)
  - Detects transform vehicles for specific checkpoints
  - Cleans up invalid points

#### `/testxmlparse` (Debug)
- **Description:** Test XML parser with sample data
- **Permission:** Console only

#### `/debugxmlparser` (Debug)
- **Description:** Debug XML parsing issues
- **Permission:** Console only

---

## Race Structure

### races.json Format

```json
{
  "race_id": {
    "name": "City Race",
    "vehicle": "adder",
    "startGrid": [
      {"x": 100.0, "y": 200.0, "z": 25.0, "w": 90.0},
      {"x": 110.0, "y": 200.0, "z": 25.0, "w": 90.0}
    ],
    "checkpoints": [
      {
        "type": "normal",
        "x": 150.0, "y": 250.0, "z": 25.0, "w": 180.0
      },
      {
        "type": "transform",
        "transformVehicle": 1033245328,
        "x": 200.0, "y": 300.0, "z": 25.0, "w": 90.0
      },
      {
        "type": "transform",
        "x": 250.0, "y": 350.0, "z": 0.0, "w": 0.0
      }
    ]
  }
}
```

### Race Object Properties
- **name** (string) - Display name of the race
- **vehicle** (string) - Default starting vehicle
- **startGrid** (array) - Array of start positions with x, y, z, w (heading)
- **checkpoints** (array) - Array of checkpoint objects

### Checkpoint Properties

#### Normal Checkpoint
```json
{
  "type": "normal",
  "x": 100.0, "y": 200.0, "z": 25.0, "w": 90.0
}
```
- Visual: Yellow/Blue
- No special behavior

#### Transform Checkpoint (Specific Vehicle)
```json
{
  "type": "transform",
  "transformVehicle": 1033245328,
  "x": 100.0, "y": 200.0, "z": 25.0, "w": 90.0
}
```
- Visual: Orange
- `transformVehicle` - Hash of specific vehicle to transform to
- Player maintains this vehicle on respawn

#### Transform Checkpoint (Randomized)
```json
{
  "type": "transform",
  "x": 100.0, "y": 200.0, "z": 25.0, "w": 90.0
}
```
- Visual: Pink
- Random vehicle selected from pool when hit
- Respawn uses same random vehicle

#### Warp Checkpoint
```json
{
  "type": "warp",
  "x": 100.0, "y": 200.0, "z": 25.0, "w": 90.0
}
```
- Teleports player to checkpoint location

---

## Checkpoint Types

### Visual Indicators

| Type | Color | Behavior |
|------|-------|----------|
| Normal | Yellow/Blue | Standard checkpoint, no effect |
| Transform (Specific) | Orange | Changes to specific vehicle |
| Transform (Random) | Pink | Changes to random vehicle |
| Warp | Same as Normal | Teleports player |

### Color Details
- **Outer Ring** - Primary checkpoint color
- **Center Arrow** - Secondary color for direction indicator
- **Minimap** - Blue blip (not shown to excluded players)

---

## Vehicle Transformations

### Specific Vehicle Transforms (Orange)

**From UGC/XML Imports:**
- Imported races retain specific vehicle hashes
- Boats, helicopters, and unique vehicles preserved
- Example: Transform checkpoint on water gives you a seashark

**How it works:**
1. Player hits checkpoint with orange smoke effect
2. Current vehicle is saved
3. New specific vehicle spawns
4. Player stays in same position with velocity preserved
5. On respawn, player gets back the same specific vehicle

### Randomized Transforms (Pink)

**Local Race Checkpoints:**
- Transform checkpoints without `transformVehicle` field
- Randomly selects from vehicle pool at runtime
- Same vehicle persists across respawns

**Randomization Logic:**
- Selects from vehicle class pool
- Excludes current vehicle model
- Maintains for entire race session

### Transform Mechanics

#### Velocity Preservation
- Horizontal velocity (x, y) is maintained
- Vertical velocity (z) clamped to prevent falling through world
- Forward speed preserved for smooth transitions

#### Respawn Vehicle Selection Priority
1. If at transform checkpoint → Use checkpoint's vehicle
2. If at normal checkpoint → Use vehicle from when checkpoint was hit
3. If crashed/died → Restore last active vehicle
4. Fallback → Race default vehicle

#### Visual Effects
- Yellow smoke cloud around player (local view)
- Networked smoke visible to all players in race
- 700ms effect duration
- Synchronized across all clients

---

## Race Exclusion

### Excluding Players

```
/raceexclude john
/raceexclude 127
/raceexclude J
```

### What Excluded Players Experience

**Visible:**
- ✅ 3D checkpoints in game world
- ✅ Race props rendered
- ✅ Transform smoke effects
- ✅ Other players' vehicles and movements

**Hidden:**
- ❌ Countdown timer (5, 4, 3, 2, 1, Go)
- ❌ Checkpoint progress UI
- ❌ Leaderboard display
- ❌ Minimap markers and routes
- ❌ Can't progress through checkpoints

**Mechanics:**
- Can't pass through checkpoints
- Not counted in race completion
- Doesn't affect other players' races
- Exclusion clears after race ends
- Can join future races normally

### Use Cases
- Testing race without affecting scoring
- Spectating without interference
- Practice mode
- Punishment/timeout without kick

---

## Files & Configuration

### Core Files

```
races/
├── fxmanifest.lua          # FiveM manifest
├── client.lua              # Client-side logic (1900+ lines)
├── server.lua              # Server-side logic (900+ lines)
├── races.json              # Race definitions
├── props.json              # Race props storage
│
├── bin/
│   ├── MenuAPI.dll         # Menu UI framework
│   └── races.net.dll       # .NET helper (if included)
│
└── ui/
    ├── index.html          # Main UI page
    ├── app.js              # Main app logic
    ├── style.css           # Main styles
    ├── fonts.css           # Font definitions
    │
    ├── countdown.html      # Countdown UI
    ├── countdown.js
    ├── countdown.css
    │
    ├── checkpoint.html     # Checkpoint progress
    ├── checkpoint.js
    ├── checkpoint.css
    │
    ├── leaderboard.html    # Race leaderboard
    ├── leaderboard.js
    ├── leaderboard.css
    │
    ├── player-leaderboard.html  # Player distance info
    ├── player-leaderboard.js
    ├── player-leaderboard.css
    │
    ├── images/
    │   └── [countdown numbers, leader icon, etc.]
    │
    └── fonts/
        └── Mont-HeavyDEMO.otf
```

### Configuration Constants (client.lua)

```lua
CHECKPOINT_Z_OFFSET = -5.0         -- Checkpoint height offset
RESPAWN_KEY = 75                   -- F key
RESPAWN_DURATION = 2.0             -- Hold time (seconds)
RESPAWN_COOLDOWN_MS = 10000        -- 10 second cooldown
CHECKPOINT_STYLE = 1               -- GTA Online checkpoint style
CHECKPOINT_LOOKAHEAD = 12.0        -- Arrow direction distance
```

---

## Advanced Features

### Leaderboard System

#### Real-Time Tracking
- Distance to next checkpoint calculated per player
- Updates every 100ms client-side
- Server aggregates and broadcasts
- Shows current/total checkpoint count

#### Leaderboard Display
- Player name and position
- Current checkpoint progress
- Estimated distance remaining
- Live rank updates

#### Network Events
- `race:updatePlayerCheckpoint` - Client reports progress
- Server responds with full leaderboard update
- Updates sent to all active race players (excluding those excluded)

### Respawn System

#### Respawn Logic
1. **Trigger:** Player holds F key for 2 seconds
2. **Animation:** Screen fade out while teleporting
3. **Vehicle:** Restored with appropriate model based on last checkpoint
4. **Position:** Last checkpoint location
5. **State:** Velocity reset, handbrake off
6. **Cooldown:** 10 second wait before next respawn

#### Respawn Variants
- **Death Respawn:** Automatic resurrection at checkpoint
- **Manual Respawn:** Player-initiated via F key
- **Respawn Nearby Resource:** Optional extra spawning logic

### Prop System

#### Prop Placement
- Load by model name or hash
- Real-time 3D preview
- Customize scale (0.5x - 2.0x)
- Rotate on Z axis (0° - 360°)
- Move with grid snapping

#### Prop Storage (props.json)
```json
{
  "race_id": [
    {
      "modelHash": 1033245328,
      "pos": {"x": 100.0, "y": 200.0, "z": 25.0},
      "rot": {"x": 0.0, "y": 0.0, "z": 90.0},
      "scale": 1.0
    }
  ]
}
```

#### Prop Rendering
- Props load when race starts
- Physics enabled for collision
- Clean up on race end
- Scale applied per-entity

### Distance Calculation

#### Checkpoint Distance
- Uses 3D Euclidean distance
- Calculates to next checkpoint
- Updates for all players
- Sorted by distance for leaderboard

#### Leaderboard Sorting
1. Sort by checkpoint progress (higher is better)
2. Sort by distance to next (lower is better)
3. Tie-breaker: Finish time if both finished

---

## Events & Network Communication

### Client → Server Events

```lua
TriggerServerEvent('race:updatePlayerCheckpoint', checkpointNum, distance)
TriggerServerEvent('race:playerFinished')
TriggerServerEvent('race:playTransformSmoke', coordinates)
```

### Server → Client Events

```lua
TriggerClientEvent('race:tpClient', player, coords, heading, vehicle, raceName)
TriggerClientEvent('race:startCountdown', player, gameTimer)
TriggerClientEvent('race:startCheckpoints', player, checkpointsList)
TriggerClientEvent('race:startProps', player, propsList)
TriggerClientEvent('race:endRace', player)
TriggerClientEvent('race:setExcluded', player, isExcluded)
TriggerClientEvent('race:showTransformSmoke', player, coords)
TriggerClientEvent('race:updateLeaderboard', player, leaderboardData)
```

### Custom Events

```lua
-- UI Events
TriggerEvent('chat:addMessage', {args = {prefix, message}})

-- Builder Events
TriggerEvent('racebuilder:checkpointTypeChanged', type)
TriggerEvent('racebuilder:propplacerState', isActive)
```

---

## Troubleshooting

### Race Won't Start
- Check races.json for syntax errors
- Verify race ID is lowercase
- Ensure at least one start grid position exists
- Check that checkpoints array exists and is not empty

### Checkpoints Not Appearing
- Verify checkpoint coordinates are valid
- Check if player is excluded (use `/raceexclude`)
- Ensure checkpoint type is set correctly
- Reload race with `/endrace` then `/race <id>`

### Vehicles Not Transforming
- For specific transforms: Verify `transformVehicle` field exists and has valid hash
- For randomized: Remove `transformVehicle` field from checkpoint JSON
- Check server console for transform errors
- Ensure vehicle model is loaded in game

### Leaderboard Not Updating
- Verify players are in active race
- Check server receives checkpoint updates
- Ensure race hasn't ended
- Restart race if leaderboard stuck

### Props Not Loading
- Check props.json syntax
- Verify model hashes are correct
- Ensure models are available in game
- Check props are associated with correct race ID

---

## Development Notes

### Code Structure

#### Client-Side (client.lua)
- State management for race variables
- Checkpoint detection thread
- Leaderboard update loop
- Builder UI controls
- Prop placement system
- Network event listeners

#### Server-Side (server.lua)
- Race management
- Player tracking
- Leaderboard aggregation
- Builder session management
- Race persistence (JSON I/O)
- XML import parser

### Performance Optimization
- Distance calculations throttled to 100ms
- Props rendered only during active race
- Checkpoint detection uses 12m radius checks
- Leaderboard updates batched server-side

### Extensibility
- Easy to add new checkpoint types
- Custom vehicle pools can be defined
- Props system supports any model hash
- Builder is extensible via MenuAPI

---

## Support & Credits

**Original Author:** willpsdk  
**Version:** 1.2.0  
**Framework:** FiveM (ESX/Standalone compatible)

### Key Systems
- MenuAPI integration for builder UI
- GTA Online race import support
- Full race persistence with JSON storage
- Networked multi-player synchronization

---

## License

This race framework is provided as-is for FiveM servers. Modify and distribute as needed for your community.

---

**Last Updated:** April 2026  
**Maintained For:** GTA V (FiveM)
