-- server.lua
local RESOURCE = GetCurrentResourceName()
local RACES_FILE = "races.json"
local PROPS_FILE = "props.json"
local BUILDER_REMOVE_RADIUS = 6.0
local RESPAWN_NEARBY_RESOURCE = "fivem-respawn-nearby"

local currentRaceId = nil
local activeRacePlayers = {}
local finishedRacePlayers = {}
local builderSessions = {}
local playerCheckpoints = {}  -- Track checkpoint progress: {playerId = {checkpoint = num, distToNext = distance}}
local raceCheckpoints = {}  -- Store checkpoints for distance calculations
local raceExcludedPlayers = {}  -- Players excluded from next race

local function notify(source, prefix, message)
    TriggerClientEvent("chat:addMessage", source, { args = { prefix, message } })
end

local function setNearbyRespawnResourceEnabled(enabled)
    local state = GetResourceState(RESPAWN_NEARBY_RESOURCE)

    if enabled then
        if state ~= "started" and state ~= "starting" then
            ExecuteCommand(("start %s"):format(RESPAWN_NEARBY_RESOURCE))
            print(("[races] Started %s"):format(RESPAWN_NEARBY_RESOURCE))
        end
        return
    end

    if state == "started" or state == "starting" then
        ExecuteCommand(("stop %s"):format(RESPAWN_NEARBY_RESOURCE))
        print(("[races] Stopped %s"):format(RESPAWN_NEARBY_RESOURCE))
    end
end

local function loadRaces()
    local content = LoadResourceFile(RESOURCE, RACES_FILE)
    if not content or content == "" then
        print("^1ERROR: Could not load races.json file!^7")
        return {}
    end

    local ok, decoded = pcall(json.decode, content)
    if not ok or type(decoded) ~= "table" then
        print("^1ERROR: Failed to parse races.json!^7")
        return {}
    end

    print("^2Successfully loaded races from JSON^7")
    return decoded
end

local function saveRaces(racesTable)
    local ok, encoded = pcall(json.encode, racesTable)
    if not ok or not encoded then
        print("^1ERROR: Failed to encode races JSON^7")
        return false
    end

    local saved = SaveResourceFile(RESOURCE, RACES_FILE, encoded, -1)
    if not saved then
        print("^1ERROR: Failed to write races.json^7")
        return false
    end

    return true
end

local function loadProps()
    local content = LoadResourceFile(RESOURCE, PROPS_FILE)
    if not content or content == "" then
        print("^3WARNING: props.json missing or empty, using empty prop table.^7")
        return {}
    end

    local ok, decoded = pcall(json.decode, content)
    if not ok or type(decoded) ~= "table" then
        print("^1ERROR: Failed to parse props.json!^7")
        return {}
    end

    return decoded
end

local function saveProps(propsTable)
    local ok, encoded = pcall(json.encode, propsTable)
    if not ok or not encoded then
        print("^1ERROR: Failed to encode props JSON^7")
        return false
    end

    local saved = SaveResourceFile(RESOURCE, PROPS_FILE, encoded, -1)
    if not saved then
        print("^1ERROR: Failed to write props.json^7")
        return false
    end

    return true
end

local Races = loadRaces()
local RaceProps = loadProps()

local function serializeVector4List(list)
    local out = {}
    for i = 1, #list do
        local v = list[i]
        local point = { x = v.x, y = v.y, z = v.z, w = v.w }
        if v.type == "transform" then
            point.type = "transform"
            if v.transformVehicle then
                point.transformVehicle = v.transformVehicle
            end
        elseif v.type == "warp" then
            point.type = "warp"
        end
        out[i] = point
    end
    return out
end

local function cleanPoint(point)
    if type(point) ~= "table" then return nil end
    local x = tonumber(point.x)
    local y = tonumber(point.y)
    local z = tonumber(point.z)
    local w = tonumber(point.w) or 0.0
    if not x or not y or not z then return nil end
    local out = { x = x, y = y, z = z, w = w }
    if point.type == "transform" then
        out.type = "transform"
    end
    return out
end

local function cloneVector4List(list)
    local out = {}
    for i = 1, #list do
        local point = cleanPoint(list[i])
        if point then
            out[#out + 1] = point
        end
    end
    return out
end

local function cleanProp(prop)
    if type(prop) ~= "table" then return nil end

    local modelHash = tonumber(prop.modelHash)
    local pos = prop.pos
    local rot = prop.rot

    if not modelHash or type(pos) ~= "table" or type(rot) ~= "table" then
        return nil
    end

    local px = tonumber(pos.x)
    local py = tonumber(pos.y)
    local pz = tonumber(pos.z)
    local rx = tonumber(rot.x) or 0.0
    local ry = tonumber(rot.y) or 0.0
    local rz = tonumber(rot.z) or 0.0
    local scale = tonumber(prop.scale) or 1.0

    if not px or not py or not pz then
        return nil
    end

    if scale < 0.2 then scale = 0.2 end
    if scale > 3.0 then scale = 3.0 end

    return {
        modelHash = modelHash,
        pos = { x = px, y = py, z = pz },
        rot = { x = rx, y = ry, z = rz },
        scale = scale
    }
end

local function clonePropList(list)
    local out = {}
    if type(list) ~= "table" then
        return out
    end

    for i = 1, #list do
        local p = cleanProp(list[i])
        if p then
            out[#out + 1] = p
        end
    end

    return out
end

local function sendBuilderMeta(source)
    local session = builderSessions[source]
    if not session then
        TriggerClientEvent("racebuilder:updateMeta", source, "", "", "", 0, 0, false)
        TriggerClientEvent("racebuilder:updatePoints", source, {}, {})
        return
    end

    TriggerClientEvent(
        "racebuilder:updateMeta",
        source,
        session.id,
        session.name,
        session.vehicle,
        #session.startGrid,
        #session.checkpoints,
        true
    )
    TriggerClientEvent("racebuilder:updatePoints", source, cloneVector4List(session.startGrid), cloneVector4List(session.checkpoints))
end

local function findClosestPointIndex(list, point, maxDistance)
    if type(list) ~= "table" or #list == 0 then
        return nil
    end

    local maxDistSq = (tonumber(maxDistance) or BUILDER_REMOVE_RADIUS)
    maxDistSq = maxDistSq * maxDistSq

    local bestIndex = nil
    local bestDistSq = nil

    for i = 1, #list do
        local p = list[i]
        local dx = (p.x or 0.0) - point.x
        local dy = (p.y or 0.0) - point.y
        local dz = (p.z or 0.0) - point.z
        local distSq = (dx * dx) + (dy * dy) + (dz * dz)

        if distSq <= maxDistSq and (not bestDistSq or distSq < bestDistSq) then
            bestDistSq = distSq
            bestIndex = i
        end
    end

    return bestIndex
end

local function removeClosestPoint(list, point, maxDistance)
    local idx = findClosestPointIndex(list, point, maxDistance)
    if not idx then
        return nil
    end

    table.remove(list, idx)
    return idx
end

local function startBuilderSession(source, id, vehicle, displayName, options)
    if not id or id == "" then
        notify(source, "^1BUILDER", "Builder start failed: missing race id.")
        return false
    end

    local cleanId = tostring(id):lower():gsub("[^%w_]", "_")
    local cleanVehicle = tostring(vehicle or "adder"):lower()
    local cleanName = (displayName and displayName ~= "") and tostring(displayName) or cleanId
    local config = options or {}

    builderSessions[source] = {
        id = cleanId,
        name = cleanName,
        vehicle = cleanVehicle,
        startGrid = config.startGrid or {},
        checkpoints = config.checkpoints or {},
        props = clonePropList(config.props or {}),
        mode = config.mode or "new",
        originalId = config.originalId or cleanId
    }

    TriggerClientEvent("racebuilder:setActive", source, true)
    sendBuilderMeta(source)
    TriggerClientEvent("racebuilder:updateProps", source, clonePropList(builderSessions[source].props or {}))
    notify(source, "^2BUILDER", "Started builder for id '" .. cleanId .. "'.")
    return true
end

local function saveBuilderSession(source)
    local session = builderSessions[source]
    if not session then
        notify(source, "^1BUILDER", "No active builder.")
        return false
    end

    local originalId = session.originalId or session.id

    if session.mode == "edit" and session.id ~= originalId and Races[session.id] and session.id ~= originalId then
        notify(source, "^1BUILDER", "Race id '" .. session.id .. "' already exists.")
        return false
    end

    if session.mode == "edit" and originalId ~= session.id then
        Races[originalId] = nil
        RaceProps[originalId] = nil
    end

    Races[session.id] = {
        name = session.name,
        vehicle = session.vehicle,
        startGrid = session.startGrid,
        checkpoints = session.checkpoints
    }
    RaceProps[session.id] = clonePropList(session.props or {})

    if saveRaces(Races) and saveProps(RaceProps) then
        notify(source, "^2BUILDER", "Saved race '" .. session.id .. "' to races.json")
        print(("Saved race '%s' (%d start spots, %d checkpoints)"):format(session.id, #session.startGrid, #session.checkpoints))
        builderSessions[source] = nil
        TriggerClientEvent("racebuilder:setActive", source, false)
        sendBuilderMeta(source)
        return true
    end

    notify(source, "^1BUILDER", "Failed to write races.json/props.json")
    return false
end

local function startEditSession(source, id)
    local race = Races[id]
    if not race then
        notify(source, "^1SYSTEM", "Race '" .. id .. "' not found!")
        return false
    end

    return startBuilderSession(source, id, race.vehicle or "adder", race.name or id, {
        mode = "edit",
        originalId = id,
        startGrid = cloneVector4List(race.startGrid or {}),
        checkpoints = cloneVector4List(race.checkpoints or {}),
        props = clonePropList(RaceProps[id] or {})
    })
end

local function clearRaceState()
    currentRaceId = nil
    activeRacePlayers = {}
    finishedRacePlayers = {}
end

local function countRacersRemaining()
    local remaining = 0
    for playerId, isActive in pairs(activeRacePlayers) do
        if isActive and not finishedRacePlayers[playerId] then
            remaining = remaining + 1
        end
    end
    return remaining
end

local function endRaceInternal(reason)
    if currentRaceId == nil then
        return
    end

    local oldRaceId = currentRaceId
    clearRaceState()
    raceExcludedPlayers = {}  -- Clear exclusions after race ends
    TriggerClientEvent("race:endRace", -1)
    setNearbyRespawnResourceEnabled(true)
    if reason and reason ~= "" then
        print(("Race '%s' ended: %s"):format(oldRaceId, reason))
    else
        print(("Race '%s' ended."):format(oldRaceId))
    end
end

local function buildRaceMenuEntries()
    local entries = {}
    for id, race in pairs(Races) do
        entries[#entries + 1] = {
            id = id,
            name = race.name or id,
            hasGrid = race.startGrid and #race.startGrid > 0
        }
    end

    table.sort(entries, function(a, b)
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)

    return entries
end

local function openRaceMenuForPlayer(source)
    local entries = buildRaceMenuEntries()
    if #entries == 0 then
        notify(source, "^1SYSTEM", "No races are available.")
        return false
    end

    TriggerClientEvent("race:menuClear", source)
    for i = 1, #entries do
        local entry = entries[i]
        TriggerClientEvent("race:menuAddEntry", source, entry.id, entry.name, entry.hasGrid == true)
    end
    TriggerClientEvent("race:menuOpen", source)
    return true
end

local function startRaceById(invokerSource, id)
    if not id or id == "" then
        if invokerSource == 0 then
            print("Usage: /race <id>")
        else
            notify(invokerSource, "^1SYSTEM", "Usage: /race <id>")
        end
        return false
    end

    local race = Races[id]
    if not race then
        if invokerSource == 0 then
            print(("Race '%s' not found."):format(id))
        else
            notify(invokerSource, "^1SYSTEM", "Race '" .. id .. "' not found!")
        end
        return false
    end

    if not race.startGrid or #race.startGrid == 0 then
        if invokerSource == 0 then
            print(("Race '%s' has no start grid positions."):format(id))
        else
            notify(invokerSource, "^1SYSTEM", "Race has no start grid positions.")
        end
        return false
    end

    local players = GetPlayers()
    if #players == 0 then
        if invokerSource == 0 then
            print("No players available to start the race.")
        else
            notify(invokerSource, "^1SYSTEM", "No players available to start the race.")
        end
        return false
    end

    currentRaceId = id
    activeRacePlayers = {}
    finishedRacePlayers = {}
    playerCheckpoints = {}  -- Reset player checkpoints
    raceCheckpoints = race.checkpoints or {}  -- Store checkpoints for distance calculations

    print(("Starting race '%s' (%s)"):format(id, race.name or id))
    setNearbyRespawnResourceEnabled(false)

    local gridCount = #race.startGrid
    for i, playerId in ipairs(players) do
        -- Skip excluded players from starting
        if raceExcludedPlayers[tostring(playerId)] then
            notify(playerId, "^1SYSTEM", "You have been excluded from this race.")
            TriggerClientEvent("race:setExcluded", playerId, true)
        else
            local spot = race.startGrid[((i - 1) % gridCount) + 1]
            activeRacePlayers[tostring(playerId)] = true
            TriggerClientEvent(
                "race:tpClient",
                playerId,
                { x = spot.x, y = spot.y, z = spot.z },
                spot.w,
                race.vehicle,
                race.name
            )
            TriggerClientEvent("race:setExcluded", playerId, false)
        end
    end

    Wait(1000)
    -- Send race events to all players
    TriggerClientEvent("race:startCountdown", -1, GetGameTimer())
    TriggerClientEvent("race:startCheckpoints", -1, serializeVector4List(race.checkpoints or {}))
    TriggerClientEvent("race:startProps", -1, clonePropList(RaceProps[id] or {}))
    return true
end

RegisterCommand("testxmlparse", function(source, args)
    if source ~= 0 then
        notify(source, "^1SYSTEM", "Console only command")
        return
    end
    
    local testXml = [[<?xml version="1.0" encoding="utf-8"?>
<Map xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Objects>
    <MapObject>
      <Type>Prop</Type>
      <Position>
        <X>-2512.73218</X>
        <Y>3655.26929</Y>
        <Z>-199.466858</Z>
      </Position>
      <Rotation>
        <X>148.2807</X>
        <Y>-52.9898949</Y>
        <Z>-14.6232672</Z>
      </Rotation>
      <Hash>725274945</Hash>
    </MapObject>
  </Objects>
</Map>]]
    
    print("^3TEST^7: Parsing sample XML")
    local props = parsePropsFromXml(testXml)
    print("^3TEST^7: Found " .. #props .. " props")
    if #props > 0 then
        print("^2PASS^7: First prop at x=" .. props[1].pos.x .. " y=" .. props[1].pos.y .. " z=" .. props[1].pos.z .. " hash=" .. props[1].modelHash)
    else
        print("^1FAIL^7: No props parsed")
    end
end)

RegisterCommand("debugxmlparser", function(source, args)
    if source ~= 0 then
        print("Console only")
        return
    end
    
    local testContent = [[<MapObject>
      <Type>Prop</Type>
      <Position>
        <X>-2512.73218</X>
        <Y>3655.26929</Y>
        <Z>-199.466858</Z>
      </Position>
      <Hash>725274945</Hash>
    </MapObject>]]
    
    print("^3DEBUG^7: Testing individual parsers")
    local hash = xmlReadModelHash(testContent)
    print("^3DEBUG^7: Hash result: " .. tostring(hash))
    
    local pos = xmlReadVector3(testContent, {"Position"})
    if pos then
        print("^3DEBUG^7: Position: x=" .. pos.x .. " y=" .. pos.y .. " z=" .. pos.z)
    else
        print("^1DEBUG^7: Position not found")
    end
end)

RegisterCommand("race", function(source, args)
    local id = (args[1] or ""):lower()
    if id == "" then
        if source == 0 then
            print("Usage: /race <id> (console) | /race (in-game menu)")
            return
        end

        openRaceMenuForPlayer(source)
        return
    end

    startRaceById(source, id)
end)

RegisterCommand("endrace", function()
    endRaceInternal("manual stop")
end)

RegisterCommand("races", function(source)
    if source == 0 then
        print("Use /race <id> from console.")
        return
    end

    openRaceMenuForPlayer(source)
end)

RegisterCommand("racedelete", function(source, args)
    local id = (args[1] or ""):lower()
    if id == "" then
        if source == 0 then
            print("Usage: /racedelete <id>")
        else
            notify(source, "^1SYSTEM", "Usage: /racedelete <id>")
        end
        return
    end

    if not Races[id] then
        if source == 0 then
            print(("Race '%s' not found."):format(id))
        else
            notify(source, "^1SYSTEM", "Race '" .. id .. "' not found!")
        end
        return
    end

    Races[id] = nil
    RaceProps[id] = nil

    if currentRaceId == id then
        endRaceInternal("race deleted")
    end

    if saveRaces(Races) and saveProps(RaceProps) then
        if source == 0 then
            print(("Deleted race '%s' from races.json and props.json"):format(id))
        else
            notify(source, "^2SYSTEM", "Deleted race '" .. id .. "' from races.json and props.json")
        end
    else
        notify(source, "^1SYSTEM", "Failed to save races.json/props.json after delete")
    end
end)

RegisterNetEvent('race:playTransformSmoke')
AddEventHandler('race:playTransformSmoke', function(pedCoords)
    -- Broadcast transform smoke to all players so they can see it
    TriggerClientEvent('race:showTransformSmoke', -1, pedCoords)
end)

RegisterCommand("raceexclude", function(source, args)
    if source == 0 then
        print("raceexclude must be used in-game.")
        return
    end
    
    local playerIdentifier = (args[1] or ""):lower()
    if playerIdentifier == "" then
        notify(source, "^1SYSTEM", "Usage: /raceexclude <player name or id>")
        return
    end
    
    -- Try to find player by ID first
    local targetPlayer = nil
    local targetId = tonumber(playerIdentifier)
    if targetId then
        local players = GetPlayers()
        for _, playerId in ipairs(players) do
            if tonumber(playerId) == targetId then
                targetPlayer = tonumber(playerId)
                break
            end
        end
    end
    
    -- If not found by ID, try by name
    if not targetPlayer then
        local players = GetPlayers()
        for _, playerId in ipairs(players) do
            local playerName = GetPlayerName(tonumber(playerId)):lower()
            if playerName:match(playerIdentifier) then
                targetPlayer = tonumber(playerId)
                break
            end
        end
    end
    
    if not targetPlayer then
        notify(source, "^1SYSTEM", "Player '" .. playerIdentifier .. "' not found!")
        return
    end
    
    raceExcludedPlayers[tostring(targetPlayer)] = true
    local excludedPlayerName = GetPlayerName(targetPlayer)
    notify(source, "^3SYSTEM", "Excluded " .. excludedPlayerName .. " from the next race.")
    print(("^3[races] Excluded player %s (%d) from next race^7"):format(excludedPlayerName, targetPlayer))
end)

RegisterCommand("rbimportxml", function(source, args)
    if source == 0 then
        print("Use in-game: /rbimportxml <resource:file.xml|file.xml>")
        return
    end

    local reference = table.concat(args or {}, " ")
    if reference == "" then
        notify(source, "^1BUILDER", "Usage: /rbimportxml <resource:file.xml|file.xml>")
        return
    end

    importXmlPropsForBuilder(source, reference)
end)

RegisterNetEvent("race:selectAndStart")
AddEventHandler("race:selectAndStart", function(id)
    local src = source
    local raceId = tostring(id or ""):lower()
    if raceId == "" then
        notify(src, "^1SYSTEM", "Invalid race selection.")
        return
    end

    startRaceById(src, raceId)
end)

RegisterNetEvent("race:playerFinished")
AddEventHandler("race:playerFinished", function()
    local srcId = tostring(source)
    if currentRaceId == nil then
        return
    end

    if not activeRacePlayers[srcId] then
        return
    end

    if finishedRacePlayers[srcId] then
        return
    end

    finishedRacePlayers[srcId] = true

    local remaining = countRacersRemaining()
    if remaining <= 0 then
        endRaceInternal("all racers finished")
    end
end)

RegisterCommand("racebuilder", function(source, args)
    if source == 0 then
        print("racebuilder must be used in-game.")
        return
    end

    local sub = (args[1] or ""):lower()
    local session = builderSessions[source]

    if sub == "" then
        if session then
            notify(source, "^5BUILDER", "Builder already active.")
            notify(source, "^5BUILDER", "ID: " .. session.id .. " | Name: " .. session.name .. " | Vehicle: " .. session.vehicle)
            notify(source, "^5BUILDER", "Start spots: " .. #session.startGrid .. " | Checkpoints: " .. #session.checkpoints)
            return
        end

        local autoId = ("custom_%d"):format(GetGameTimer())
        local autoName = ("Custom Race %d"):format(GetGameTimer())
        startBuilderSession(source, autoId, "adder", autoName)
        notify(source, "^2BUILDER", "Builder started. Use the MenuAPI builder menu.")
        return
    end

    if sub == "help" then
        notify(source, "^5BUILDER", "Usage:")
        notify(source, "^5BUILDER", "/racebuilder  (quick start builder)")
        notify(source, "^5BUILDER", "/racebuilder start <id> <vehicle> [name]")
        notify(source, "^5BUILDER", "/editrace <id>  (edit an existing race)")
        notify(source, "^5BUILDER", "/racebuilder addstart | addcp | removestart | removecp")
        notify(source, "^5BUILDER", "/racebuilder status | save | cancel")
        return
    end

    if sub == "start" then
        local id = (args[2] or ""):lower()
        local vehicle = args[3] or "adder"
        local displayName = table.concat(args, " ", 4)

        if id == "" then
            notify(source, "^1BUILDER", "Usage: /racebuilder start <id> <vehicle> [name]")
            return
        end

        startBuilderSession(source, id, vehicle, displayName)
        notify(source, "^2BUILDER", "Use /racebuilder addstart and /racebuilder addcp to place points.")
        return
    end

    if not session then
        notify(source, "^1BUILDER", "No active builder. Start with /racebuilder start <id> <vehicle> [name]")
        return
    end

    if sub == "addstart" then
        TriggerClientEvent("racebuilder:captureStart", source)
        return
    end

    if sub == "addcp" then
        TriggerClientEvent("racebuilder:captureCheckpoint", source)
        return
    end

    if sub == "removestart" then
        TriggerClientEvent("racebuilder:captureRemoveStart", source)
        return
    end

    if sub == "removecp" then
        TriggerClientEvent("racebuilder:captureRemoveCheckpoint", source)
        return
    end

    if sub == "status" then
        notify(source, "^5BUILDER", "ID: " .. session.id .. " | Vehicle: " .. session.vehicle)
        notify(source, "^5BUILDER", "Start spots: " .. #session.startGrid .. " | Checkpoints: " .. #session.checkpoints)
        return
    end

    if sub == "cancel" then
        builderSessions[source] = nil
        TriggerClientEvent("racebuilder:setActive", source, false)
        sendBuilderMeta(source)
        notify(source, "^3BUILDER", "Builder canceled.")
        return
    end

    if sub == "save" then
        saveBuilderSession(source)
        return
    end

    notify(source, "^1BUILDER", "Unknown subcommand. Use /racebuilder help")
end)

RegisterCommand("editrace", function(source, args)
    if source == 0 then
        print("editrace must be used in-game.")
        return
    end

    local id = (args[1] or ""):lower()
    if id == "" then
        notify(source, "^1SYSTEM", "Usage: /editrace <id>")
        return
    end

    if builderSessions[source] then
        notify(source, "^3BUILDER", "Builder already active. Use /racebuilder cancel or 7 to stop it first.")
        return
    end

    if startEditSession(source, id) then
        notify(source, "^2BUILDER", "Editing race '" .. id .. "'. Use 6 to save your changes.")
    end
end)

RegisterNetEvent("racebuilder:addStart")
AddEventHandler("racebuilder:addStart", function(point)
    local src = source
    local session = builderSessions[src]
    if not session then
        notify(src, "^1BUILDER", "No active builder.")
        return
    end

    local clean = cleanPoint(point)
    if not clean then
        notify(src, "^1BUILDER", "Invalid start point data.")
        return
    end

    table.insert(session.startGrid, clean)
    notify(src, "^2BUILDER", ("Added start point #%d"):format(#session.startGrid))
    sendBuilderMeta(src)
end)

RegisterNetEvent("racebuilder:addCheckpoint")
AddEventHandler("racebuilder:addCheckpoint", function(point, cpType)
    local src = source
    local session = builderSessions[src]
    if not session then
        notify(src, "^1BUILDER", "No active builder.")
        return
    end

    local clean = cleanPoint(point)
    if not clean then
        notify(src, "^1BUILDER", "Invalid checkpoint data.")
        return
    end

    cpType = (cpType == "transform") and "transform" or "normal"
    clean.type = cpType
    table.insert(session.checkpoints, clean)
    local typeLabel = (cpType == "transform") and "^5Transform" or "^2Normal"
    notify(src, "^2BUILDER", ("Added checkpoint #%d [%s^2]"):format(#session.checkpoints, typeLabel))
    sendBuilderMeta(src)
end)

RegisterNetEvent("racebuilder:removeStartAt")
AddEventHandler("racebuilder:removeStartAt", function(point)
    local src = source
    local session = builderSessions[src]
    if not session then
        notify(src, "^1BUILDER", "No active builder.")
        return
    end

    if #session.startGrid == 0 then
        notify(src, "^1BUILDER", "No start points to remove.")
        return
    end

    local clean = cleanPoint(point)
    if not clean then
        notify(src, "^1BUILDER", "Invalid remove position.")
        return
    end

    local removedIndex = removeClosestPoint(session.startGrid, clean, BUILDER_REMOVE_RADIUS)
    if not removedIndex then
        notify(src, "^1BUILDER", ("No start point near you (%.1fm)."):format(BUILDER_REMOVE_RADIUS))
        return
    end

    notify(src, "^3BUILDER", "Removed start point #" .. removedIndex .. ". Total: " .. #session.startGrid)
    sendBuilderMeta(src)
end)

RegisterNetEvent("racebuilder:removeCheckpointAt")
AddEventHandler("racebuilder:removeCheckpointAt", function(point)
    local src = source
    local session = builderSessions[src]
    if not session then
        notify(src, "^1BUILDER", "No active builder.")
        return
    end

    if #session.checkpoints == 0 then
        notify(src, "^1BUILDER", "No checkpoints to remove.")
        return
    end

    local clean = cleanPoint(point)
    if not clean then
        notify(src, "^1BUILDER", "Invalid remove position.")
        return
    end

    local removedIndex = removeClosestPoint(session.checkpoints, clean, BUILDER_REMOVE_RADIUS)
    if not removedIndex then
        notify(src, "^1BUILDER", ("No checkpoint near you (%.1fm)."):format(BUILDER_REMOVE_RADIUS))
        return
    end

    notify(src, "^3BUILDER", "Removed checkpoint #" .. removedIndex .. ". Total: " .. #session.checkpoints)
    sendBuilderMeta(src)
end)

RegisterNetEvent("racebuilder:clearAllCheckpoints")
AddEventHandler("racebuilder:clearAllCheckpoints", function()
    local src = source
    local session = builderSessions[src]
    if not session then
        notify(src, "^1BUILDER", "No active builder.")
        return
    end

    local removedCount = #session.checkpoints
    if removedCount == 0 then
        notify(src, "^1BUILDER", "No checkpoints to remove.")
        return
    end

    session.checkpoints = {}
    notify(src, "^3BUILDER", "Removed all " .. removedCount .. " checkpoints.")
    sendBuilderMeta(src)
end)

RegisterNetEvent("racebuilder:keySave")
AddEventHandler("racebuilder:keySave", function()
    saveBuilderSession(source)
end)

RegisterNetEvent("racebuilder:keyCancel")
AddEventHandler("racebuilder:keyCancel", function()
    local src = source
    if not builderSessions[src] then
        notify(src, "^1BUILDER", "No active builder.")
        return
    end

    builderSessions[src] = nil
    TriggerClientEvent("racebuilder:setActive", src, false)
    sendBuilderMeta(src)
    notify(src, "^3BUILDER", "Builder canceled.")
end)

RegisterNetEvent("racebuilder:keyStatus")
AddEventHandler("racebuilder:keyStatus", function()
    local src = source
    local session = builderSessions[src]
    if not session then
        notify(src, "^1BUILDER", "No active builder. Use /racebuilder to start.")
        return
    end

    notify(src, "^5BUILDER", "ID: " .. session.id .. " | Name: " .. session.name .. " | Vehicle: " .. session.vehicle)
    notify(src, "^5BUILDER", "Start spots: " .. #session.startGrid .. " | Checkpoints: " .. #session.checkpoints)
end)

RegisterNetEvent("racebuilder:updateInfo")
AddEventHandler("racebuilder:updateInfo", function(id, displayName, vehicle)
    local src = source
    local session = builderSessions[src]
    if not session then
        notify(src, "^1BUILDER", "No active builder.")
        return
    end

    local newId = tostring(id or "")
    if newId ~= "" then
        newId = newId:lower():gsub("[^%w_]", "_")
        session.id = newId
    end

    local newName = tostring(displayName or "")
    if newName ~= "" then
        session.name = newName
    end

    local newVehicle = tostring(vehicle or "")
    if newVehicle ~= "" then
        session.vehicle = newVehicle:lower()
    end

    sendBuilderMeta(src)
    notify(src, "^2BUILDER", "Builder info updated.")
end)

RegisterNetEvent("racebuilder:updateProps")
AddEventHandler("racebuilder:updateProps", function(props)
    local src = source
    local session = builderSessions[src]
    if not session then
        notify(src, "^1BUILDER", "No active builder.")
        return
    end

    session.props = clonePropList(props or {})
    sendBuilderMeta(src)
end)

-- Parse UGC race data from Rockstar JSON and start builder session
-- Parse Rockstar UGC race JSON and extract race data
local function ParseUGCRace(ugcData, source)
    if not ugcData or type(ugcData) ~= "table" then
        TriggerClientEvent("race:client:importResult", source, {success = false, error = "Invalid race data"})
        return nil
    end
    
    local race = {}
    
    -- Extract mission data (with nil safety)
    local mission = ugcData.mission
    if not mission or type(mission) ~= "table" then
        TriggerClientEvent("race:client:importResult", source, {success = false, error = "Mission data not found"})
        return nil
    end
    
    local gen = mission.gen or {}
    
    -- Use placeholder for imported race name and ID
    race.name = "placeholder"
    
    -- Extract type from ugcData.mission.gen.subtype (can be string or numeric)
    local rawType = gen.subtype or "race"
    race.type = tostring(rawType)
    
    -- Validate race type - accept both string names and Rockstar numeric codes
    -- Rockstar uses numeric codes: 7 = point-to-point stunt, etc.
    local validTypes = {
        ["race"] = true, ["stunt"] = true, ["transform"] = true,
        -- Also accept numeric Rockstar type codes
        ["0"] = true, ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, 
        ["5"] = true, ["6"] = true, ["7"] = true, ["8"] = true, ["9"] = true
    }
    
    if not validTypes[race.type:lower()] then
        TriggerClientEvent("race:client:importResult", source, {
            success = false,
            error = "Unsupported race type: " .. tostring(race.type)
        })
        return nil
    end
    
    -- Extract vehicle model from mission.gen.ivm (initial vehicle model for the race)
    race.vehicle = tonumber(mission.gen.ivm) or 0
    
    -- Extract start grid from mission.veh (vehicle spawn positions with headings)
    race.startGrid = {}
    local veh = mission.veh or {}
    local vehicleCount = tonumber(veh.no) or 0
    local vehLoc = veh.loc or {}
    local vehHead = veh.head or {}
    
    if vehicleCount > 0 then
        for i = 1, vehicleCount do
            local spawn = vehLoc[i]
            if spawn and type(spawn) == "table" then
                local sx = tonumber(spawn.x)
                local sy = tonumber(spawn.y)
                local sz = tonumber(spawn.z)
                local heading = tonumber(vehHead[i]) or 0.0
                if sx and sy and sz then
                    table.insert(race.startGrid, {x = sx, y = sy, z = sz, w = heading})
                end
            end
        end
    end
    
    print("^2[Race Import] Extracted vehicle: " .. tostring(race.vehicle) .. " with " .. #race.startGrid .. " start spawns^7")
    
    -- Extract checkpoints from mission.race.chl (Rockstar checkpoint locations)
    race.checkpoints = {}
    local chpCount = tonumber(mission.race.chp) or 0
    local chl = mission.race.chl or {}
    
    if chpCount > 0 and type(chl) == "table" and #chl > 0 then
        local checkpointList = {}
        
        -- Collect all checkpoints from mission.race.chl array
        for i = 1, chpCount do
            local cp = chl[i]
            if cp and type(cp) == "table" then
                local x = tonumber(cp.x)
                local y = tonumber(cp.y)
                local z = tonumber(cp.z)
                if x and y and z then
                    local cpData = {
                        x = x, y = y, z = z,
                        type = "normal",
                        vehicle = nil
                    }
                    
                    -- Check if this checkpoint is a transform using cptfrm/trfmvm arrays
                    if mission.race.cptfrm and mission.race.cptfrm[i] then
                        local transformIndex = tonumber(mission.race.cptfrm[i])
                        if transformIndex >= 0 and mission.race.trfmvm then
                            -- Get vehicle hash from trfmvm (transform index is 0-indexed, array is 1-indexed)
                            local vehicleHash = mission.race.trfmvm[transformIndex + 1]
                            if vehicleHash and vehicleHash ~= 0 then
                                cpData.type = "transform"
                                cpData.vehicle = tonumber(vehicleHash)
                            end
                        end
                    end
                    
                    table.insert(checkpointList, cpData)
                end
            end
        end
        
        -- Calculate bearings to next checkpoint
        for i = 1, #checkpointList do
            local cpData = checkpointList[i]
            local bearing = 0.0
            
            -- Calculate bearing to next checkpoint
            if i < #checkpointList then
                local nextCp = checkpointList[i + 1]
                local dx = nextCp.x - cpData.x
                local dy = nextCp.y - cpData.y
                bearing = math.deg(math.atan(dx, dy))
                if bearing < 0 then
                    bearing = bearing + 360
                end
            else
                -- Last checkpoint reuses previous bearing
                if i > 1 then
                    local prevCp = checkpointList[i - 1]
                    local dx = cpData.x - prevCp.x
                    local dy = cpData.y - prevCp.y
                    bearing = math.deg(math.atan(dx, dy))
                    if bearing < 0 then
                        bearing = bearing + 360
                    end
                end
            end
            
            -- Build checkpoint entry with optional transformVehicle field
            local cpEntry = {x = cpData.x, y = cpData.y, z = cpData.z, w = bearing}
            
            -- Add transform data if this is a transform checkpoint
            if cpData.type == "transform" then
                cpEntry.type = "transform"
                if cpData.vehicle then
                    cpEntry.transformVehicle = cpData.vehicle
                else
                    cpEntry.transformVehicle = race.vehicle
                end
            end
            
            table.insert(race.checkpoints, cpEntry)
        end
        
        print("^2[Race Import] Extracted " .. #race.checkpoints .. " checkpoints^7")
        
        -- Count and print transform checkpoints
        local transformCount = 0
        for i, cp in ipairs(race.checkpoints) do
            if cp.type == "transform" then
                transformCount = transformCount + 1
                local vehicleHash = cp.transformVehicle or race.vehicle or 0
                print("^3[Transform] Checkpoint " .. i .. " ▶ Vehicle Hash: " .. tostring(vehicleHash) .. "^7")
            end
        end
        if transformCount > 0 then
            print("^3[Race Import] Found " .. transformCount .. " transform checkpoint(s)! 🚗^7")
        end
    end
    
    
    -- Extract props from ugcData.mission.prop using vRot for full rotation data
    race.props = {}
    local missingProps = {}
    local prop = mission.prop
    if prop and type(prop) == "table" and prop.loc and type(prop.loc) == "table" then
        local numProps = tonumber(prop.no) or #prop.loc
        local models = prop.model or {}
        local vRots = prop.vRot or {}
        
        for i = 1, numProps do
            local propLoc = prop.loc[i]
            if propLoc and type(propLoc) == "table" then
                local modelHash = tonumber(models[i])
                local x = tonumber(propLoc.x)
                local y = tonumber(propLoc.y)
                local z = tonumber(propLoc.z)
                
                -- Extract rotation from vRot (contains x, y, z in radians)
                local rotX = 0.0
                local rotY = 0.0
                local rotZ = 0.0
                if vRots[i] and type(vRots[i]) == "table" then
                    rotX = tonumber(vRots[i].x) or 0.0
                    rotY = tonumber(vRots[i].y) or 0.0
                    rotZ = tonumber(vRots[i].z) or 0.0
                end
                
                if modelHash and x and y and z then
                    table.insert(race.props, {
                        modelHash = modelHash,
                        scale = 1.0,
                        pos = {x = x, y = y, z = z},
                        rot = {x = rotX, y = rotY, z = rotZ}
                    })
                elseif modelHash then
                    table.insert(missingProps, "Model " .. tostring(modelHash) .. " missing position data")
                elseif x and y and z then
                    table.insert(missingProps, "Position (" .. x .. ", " .. y .. ", " .. z .. ") missing model hash")
                end
            end
        end
    end
    
    -- Log missing props to console
    if #missingProps > 0 then
        print("^3[Race Import] Missing props for race import:^7")
        for i, missingProp in ipairs(missingProps) do
            print("  - " .. missingProp)
        end
    end
    

    
    return race
end

-- Register server event to handle Rockstar UGC imports
-- Try multiple URL patterns for Rockstar CDN (different languages and indices)
local function tryFetchRaceJSON(baseUrl, source, attemptCount)
    attemptCount = attemptCount or 0
    local languages = {"en", "fr", "de", "es", "it", "ja", "pt", "ru", "ko", "zh", "pl"}
    local patterns = {{0, 0}, {0, 1}, {1, 0}, {2, 0}}
    
    if attemptCount >= #languages * #patterns then
        TriggerClientEvent("race:client:importResult", source, {success = false, error = "Failed to fetch from Rockstar (No valid JSON found)"})
        return
    end
    
    local patternIndex = math.floor(attemptCount / #languages) + 1
    local langIndex = (attemptCount % #languages) + 1
    
    local pattern = patterns[patternIndex]
    local lang = languages[langIndex]
    
    if not pattern then
        TriggerClientEvent("race:client:importResult", source, {success = false, error = "Failed to fetch from Rockstar (No valid JSON found)"})
        return
    end
    
    local fetchUrl = baseUrl .. "/" .. pattern[1] .. "_" .. pattern[2] .. "_" .. lang .. ".json"
    
    PerformHttpRequest(fetchUrl, function(errorCode, resultData, resultHeaders)
        if errorCode ~= 200 then
            -- Try next pattern
            tryFetchRaceJSON(baseUrl, source, attemptCount + 1)
            return
        end
        
        if not resultData or resultData == "" then
            TriggerClientEvent("race:client:importResult", source, {success = false, error = "Empty response from Rockstar"})
            return
        end
        
        local ok, decoded = pcall(json.decode, resultData)
        if not ok or type(decoded) ~= "table" then
            TriggerClientEvent("race:client:importResult", source, {success = false, error = "Failed to parse race data"})
            return
        end
        
        local race = ParseUGCRace(decoded, source)
        if not race then
            return
        end
        
        -- Show what was found
        TriggerClientEvent("chat:addMessage", source, { args = { '^3BUILDER', 'Found: ' .. tostring(#race.startGrid) .. ' starts, ' .. tostring(#race.checkpoints) .. ' checkpoints, ' .. tostring(#race.props) .. ' props' } })
        
        -- Validate start grid - if empty for stunt race, use first checkpoint as start
        if #race.startGrid == 0 and #race.checkpoints > 0 then
            -- For stunt races, start at the first checkpoint location
            local firstCp = race.checkpoints[1]
            if firstCp then
                table.insert(race.startGrid, {x = firstCp.x, y = firstCp.y, z = firstCp.z, w = firstCp.w or 0})
            end
        end
        
        -- If no start grid and no checkpoints, create a dummy start at world center
        if #race.startGrid == 0 and #race.checkpoints == 0 then
            table.insert(race.startGrid, {x = 0, y = 0, z = 0, w = 0})
        end
        
        -- Start builder session with imported race
        startBuilderSession(source, race.name, race.vehicle, race.name, {
            mode = "new",
            startGrid = race.startGrid,
            checkpoints = race.checkpoints,
            props = race.props
        })
        
        -- Send success result to client
        TriggerClientEvent("race:client:importResult", source, {
            success = true,
            name = race.name,
            checkpointCount = #race.checkpoints
        })
    end, "GET", "", {})
end

RegisterNetEvent("race:server:importUGC")
AddEventHandler("race:server:importUGC", function(baseUrl, playerSource)
    local source = source or playerSource
    
    if not baseUrl or baseUrl == "" then
        TriggerClientEvent("race:client:importResult", source, {success = false, error = "No URL provided"})
        return
    end
    
    -- SSRF prevention: validate URL is from Rockstar CDN
    if not string.find(baseUrl, "prod.cloud.rockstargames.com", 1, true) then
        TriggerClientEvent("race:client:importResult", source, {success = false, error = "Invalid URL"})
        return
    end
    
    -- Start attempting to fetch with different patterns
    tryFetchRaceJSON(baseUrl, source, 0)
end)

-- Track player checkpoint progress
RegisterNetEvent("race:updatePlayerCheckpoint")
AddEventHandler("race:updatePlayerCheckpoint", function(checkpointNumber, distToNext)
    local playerId = source
    if currentRaceId then
        playerCheckpoints[tostring(playerId)] = {
            checkpoint = checkpointNumber or 0,
            distToNext = distToNext or 999999  -- Large distance if not provided
        }
    end
end)

-- Broadcast leaderboard data to all clients every 200ms
CreateThread(function()
    while true do
        Wait(200)
        
        if currentRaceId and raceCheckpoints and #raceCheckpoints > 0 then
            -- Build ranking list
            local playerList = {}
            
            for playerId in pairs(activeRacePlayers) do
                local playerData = playerCheckpoints[tostring(playerId)]
                local checkpoint = 0
                local distToNext = 999999
                
                if playerData and type(playerData) == "table" then
                    checkpoint = playerData.checkpoint or 0
                    distToNext = playerData.distToNext or 999999
                end
                
                local playerName = GetPlayerName(tonumber(playerId)) or ("Player " .. playerId)
                
                table.insert(playerList, {
                    id = playerId,
                    name = playerName,
                    checkpoint = checkpoint,
                    distToNext = distToNext
                })
            end
            
            -- Sort by checkpoint (highest first), then by distance to next (closest first)
            table.sort(playerList, function(a, b)
                if a.checkpoint ~= b.checkpoint then
                    return a.checkpoint > b.checkpoint
                end
                -- Same checkpoint: closer to next is ranked higher
                return a.distToNext < b.distToNext
            end)
            
            -- Build top 4 for broadcast
            local top4 = {}
            for i = 1, math.min(4, #playerList) do
                table.insert(top4, {
                    name = playerList[i].name,
                    checkpoint = playerList[i].checkpoint
                })
            end
            
            -- Broadcast to all clients
            TriggerClientEvent("race:leaderboardUpdate", -1, top4)
        end
    end
end)

AddEventHandler("playerDropped", function()
    local srcId = tostring(source)
    if activeRacePlayers[srcId] then
        activeRacePlayers[srcId] = nil
        finishedRacePlayers[srcId] = nil
        if currentRaceId ~= nil and countRacersRemaining() <= 0 then
            endRaceInternal("all racers finished or left")
        end
    end

    builderSessions[source] = nil
end)

