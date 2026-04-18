-- client.lua

-- Config
local CHECKPOINT_Z_OFFSET = -5.0  -- Z offset for checkpoints
local RESPAWN_KEY = 75            -- F key (vehicle exit control)
local RESPAWN_DURATION = 2.0      -- seconds
local RESPAWN_COOLDOWN_MS = 10000 -- 10 seconds
local CHECKPOINT_STYLE = 1        -- Standard GTA Online checkpoint
local CHECKPOINT_LOOKAHEAD = 12.0 -- Distance used to orient checkpoint arrow
local HUD_VALUE_Y_OFFSET = -0.023 -- Move right-side TIME/CHECKPOINT values up/down quickly

-- State
local raceStarted = false
local raceName = "Default Race"
local defaultVehicle = "adder"
local raceTimerStart = 0

local checkpoints = {}
local currentCheckpoint = 1
local activeCP, nextPreviewCP = nil, nil
local activeBlip, previewBlip = nil, nil
local lastCheckpointPos = nil
local lastCheckpointType = "normal"
local lastCheckpointTransformVehicle = nil
local currentRaceVehicle = nil  -- Track current vehicle model for respawns
local respawnHoldTime = 0.0
local nextRespawnAllowedAt = 0
local raceVehicles = {}
local raceFinishReported = false
local isRaceExcluded = false
local builderActive = false
local builderRaceId = ""
local builderRaceName = ""
local builderVehicle = ""
local builderStartCount = 0
local builderCheckpointCount = 0
local builderStartGrid = {}
local builderCheckpoints = {}
local propPlacerActive = false
local mouseGizmoMode = false
local checkpointTypeBeingPlaced = "normal"  -- "normal" or "transform"
local placedProps = {}
local raceSpawnedProps = {}
local propScaleByEntity = {}
local selectedPropIndex = 0
local propVerticalAxis = 'y'
local propUndoStack = {}
local propRedoStack = {}
local propEditGestureActive = false
local propRotateMode = false
local nextScaleAdjustAt = 0
local nextRotateAdjustAt = 0
local numpad8Held = false
local numpad2Held = false
local numpad4Held = false
local numpad6Held = false
local numpadMulHeld = false
local numpadSubHeld = false
local countdownLocked = false
local deathRespawnTriggered = false
local playerCheckpoints = {}  -- Track checkpoint progress for all players: {playerId = checkpointNumber}
local serverLeaderboard = {}  -- Store leaderboard from server

local function setCheckpointType(newType)
    local resolved = (newType == "transform") and "transform" or "normal"
    checkpointTypeBeingPlaced = resolved
    TriggerEvent('racebuilder:checkpointTypeChanged', checkpointTypeBeingPlaced)
end

-- Helpers
local function safeDeleteCheckpoint(cp) if cp then DeleteCheckpoint(cp) end end
local function safeRemoveBlip(b) if b and DoesBlipExist(b) then RemoveBlip(b) end end

local function clearEntityList(list)
    for i = #list, 1, -1 do
        local entity = list[i]
        if entity and DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
        propScaleByEntity[entity] = nil
        list[i] = nil
    end
end

local function applyScaleNative(entity, scale)
    local s = tonumber(scale) or 1.0

    if SetObjectScale then
        local ok = pcall(SetObjectScale, entity, s)
        if ok then return true end
        ok = pcall(SetObjectScale, entity, s, s, s)
        if ok then return true end
    end

    if SetEntityScale then
        local ok = pcall(SetEntityScale, entity, s, s, s)
        if ok then return true end
        ok = pcall(SetEntityScale, entity, s, s, s, false)
        if ok then return true end
    end

    return false
end

local function setPropScale(entity, scale)
    if not entity or not DoesEntityExist(entity) then
        return
    end

    local clamped = math.max(0.2, math.min(3.0, tonumber(scale) or 1.0))
    if applyScaleNative(entity, clamped) then
        propScaleByEntity[entity] = clamped
    else
        propScaleByEntity[entity] = clamped
    end
end

local function getPropScale(entity)
    local current = propScaleByEntity[entity]
    if current == nil then
        return 1.0
    end
    return tonumber(current) or 1.0
end

local function snapToRightAngle(angle)
    return math.floor((angle / 90.0) + 0.5) * 90.0
end

local function drawHudText(x, y, scale, r, g, b, a, text, justify)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(0.0, scale)
    SetTextColour(r, g, b, a)
    SetTextDropShadow(1, 0, 0, 0, 200)
    if justify == 2 then
        SetTextRightJustify(true)
        SetTextWrap(0.0, x)
        SetTextJustification(2)
    else
        SetTextRightJustify(false)
        SetTextWrap(0.0, 1.0)
        SetTextJustification(1)
    end
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function formatRaceTime(ms)
    local totalCs = math.floor((ms or 0) / 10)
    local minutes = math.floor(totalCs / 6000)
    local seconds = math.floor((totalCs % 6000) / 100)
    local centis = totalCs % 100
    return string.format("%02d:%02d.%02d", minutes, seconds, centis)
end

local transformVehiclePool = nil

local function resolveVehicleModelHash(modelRef)
    if type(modelRef) == 'number' then
        return modelRef
    end

    if type(modelRef) == 'string' then
        local asNumber = tonumber(modelRef)
        if asNumber then
            return asNumber
        end
        return GetHashKey(modelRef)
    end

    return nil
end

local function buildTransformVehiclePool()
    local pool = {}
    local seen = {}

    if GetAllVehicleModels then
        local ok, models = pcall(GetAllVehicleModels)
        if ok and type(models) == 'table' then
            for i = 1, #models do
                local hash = resolveVehicleModelHash(models[i])
                if hash and not seen[hash] and IsModelInCdimage(hash) and IsModelAVehicle(hash) then
                    seen[hash] = true
                    pool[#pool + 1] = hash
                end
            end
        end
    end

    transformVehiclePool = pool
end

local function warpPedIntoVehicleReliable(ped, veh)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false
    end
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        return false
    end

    TaskWarpPedIntoVehicle(ped, veh, -1)
    Wait(0)
    if GetVehiclePedIsIn(ped, false) == veh then
        return true
    end

    SetPedIntoVehicle(ped, veh, -1)
    Wait(0)
    if GetVehiclePedIsIn(ped, false) == veh then
        return true
    end

    for _ = 1, 8 do
        TaskWarpPedIntoVehicle(ped, veh, -1)
        Wait(0)
        if GetVehiclePedIsIn(ped, false) == veh then
            return true
        end
    end

    return false
end

local function spawnAndWarpVehicle(modelName, coords, heading, velocity, forwardSpeed)
    local ped = PlayerPedId()
    local model = resolveVehicleModelHash(modelName)
    if not model then
        return nil
    end
    if not IsModelInCdimage(model) or not IsModelAVehicle(model) then
        return nil
    end
    RequestModel(model)
    local t0 = GetGameTimer()
    while not HasModelLoaded(model) and (GetGameTimer()-t0)<5000 do Wait(0) end
    if not HasModelLoaded(model) then return nil end

    local veh = CreateVehicle(model, coords.x, coords.y, coords.z + 1, heading or 0.0, true, false)
    if DoesEntityExist(veh) then
        local didWarp = warpPedIntoVehicleReliable(ped, veh)
        if not didWarp then
            DeleteVehicle(veh)
            return nil
        end

        SetVehicleEngineOn(veh, true, true, false)
        SetVehicleHandbrake(veh, false)
        FreezeEntityPosition(veh, false)
        if velocity then
            SetEntityVelocity(veh, velocity.x or 0.0, velocity.y or 0.0, math.max(-2.0, math.min(velocity.z or 0.0, 0.5)))
        end
        if forwardSpeed and forwardSpeed > 0.0 then
            SetVehicleForwardSpeed(veh, forwardSpeed)
        end
        return veh
    end
    return nil
end

-- Get model name/label from hash, with fallback to hash value
local function getModelName(modelHash)
    if not modelHash or modelHash == 0 then return "Unknown" end
    -- Try to get the model name
    local modelName = GetLabelText(GetDisplayNameFromModel(modelHash))
    if modelName and modelName ~= "NULL" and string.len(modelName) > 0 then
        return modelName
    end
    return tostring(modelHash)
end

local function pickRandomTransformVehicle(currentModelHash)
    local currentHash = tonumber(currentModelHash) or 0
    if not transformVehiclePool or #transformVehiclePool < 1 then
        buildTransformVehiclePool()
    end

    if not transformVehiclePool or #transformVehiclePool < 1 then
        return nil
    end

    -- Fast random attempts first.
    for _ = 1, 20 do
        local hash = transformVehiclePool[math.random(1, #transformVehiclePool)]
        if hash and hash ~= currentHash then
            return hash
        end
    end

    -- Deterministic fallback in rare cases where random kept hitting the same model.
    for i = 1, #transformVehiclePool do
        local hash = transformVehiclePool[i]
        if hash and hash ~= currentHash then
            return hash
        end
    end

    return nil
end

local function ensureTransformPtfxAsset()
    RequestNamedPtfxAsset("core")
    local t0 = GetGameTimer()
    while not HasNamedPtfxAssetLoaded("core") and (GetGameTimer() - t0) < 1500 do
        Wait(0)
    end
    return HasNamedPtfxAssetLoaded("core")
end

local function spawnYellowTransformCloud(x, y, z, scale)
    local fxScale = tonumber(scale) or 1.0
    if not ensureTransformPtfxAsset() then
        return
    end

    UseParticleFxAssetNextCall("core")
    if SetParticleFxNonLoopedColour then
        pcall(SetParticleFxNonLoopedColour, 1.0, 0.9, 0.0)
    end

    StartParticleFxNonLoopedAtCoord(
        "ent_sht_news_fog",
        x, y, z,
        0.0, 0.0, 0.0,
        fxScale,
        false, false, false
    )
end

local function applyTransformCloudOverrideBriefly()
    -- Brief world cloud override to reinforce the transform flash mask.
    pcall(SetCloudSettingsOverride, "Cloudy 01")
    pcall(SetCloudsAlpha, 1.0)

    CreateThread(function()
        Wait(700)
        pcall(SetCloudSettingsOverride, "")
    end)
end

local function spawnTransformCloudOnEntity(ped)
    -- Large looped cloud effect on player ped to hide vehicle transformation
    CreateThread(function()
        RequestNamedPtfxAsset("scr_as_trans")
        local startTime = GetGameTimer()
        while not HasNamedPtfxAssetLoaded("scr_as_trans") and (GetGameTimer() - startTime) < 1500 do
            Wait(0)
        end
        
        if HasNamedPtfxAssetLoaded("scr_as_trans") then
            UseParticleFxAssetNextCall("scr_as_trans")
            local effect = StartParticleFxLoopedOnEntity("scr_as_trans_smoke", ped, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, false, false, false)
            -- Color the cloud yellow
            SetParticleFxLoopedColour(effect, 1.0, 1.0, 0.0, true)
            Wait(500)  -- Cloud lasts for half a second
            StopParticleFxLooped(effect, true)
            RemoveNamedPtfxAsset("scr_as_trans")
        end
    end)
end

local function respawnPlayerAtLastCheckpoint(fromDeath)
    if not raceStarted or not lastCheckpointPos then
        return false
    end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and DoesEntityExist(veh) then
        DeleteVehicle(veh)
    end

    DoScreenFadeOut(175)
    while not IsScreenFadedOut() do
        Wait(0)
    end

    if fromDeath and IsEntityDead(ped) then
        NetworkResurrectLocalPlayer(lastCheckpointPos.x, lastCheckpointPos.y, lastCheckpointPos.z + 1.0, lastCheckpointPos.w or 0.0, true, true, false)
        ClearPedBloodDamage(ped)
    end

    SetEntityCoords(ped, lastCheckpointPos.x, lastCheckpointPos.y, lastCheckpointPos.z + 1, false, false, false, true)
    SetEntityHeading(ped, lastCheckpointPos.w or 0.0)

    local respawnVehicle = defaultVehicle
    
    -- Use current vehicle if player is on one (from transform or race start)
    if currentRaceVehicle then
        respawnVehicle = currentRaceVehicle
    elseif lastCheckpointType == "transform" then
        -- Fallback: use transform vehicle if at transform checkpoint
        respawnVehicle = lastCheckpointTransformVehicle or defaultVehicle
    end

    local newVeh = spawnAndWarpVehicle(respawnVehicle, {
        x = lastCheckpointPos.x,
        y = lastCheckpointPos.y,
        z = lastCheckpointPos.z
    }, lastCheckpointPos.w or 0.0, nil, nil)
    if not newVeh and respawnVehicle ~= defaultVehicle then
        newVeh = spawnAndWarpVehicle(defaultVehicle, {
            x = lastCheckpointPos.x,
            y = lastCheckpointPos.y,
            z = lastCheckpointPos.z
        }, lastCheckpointPos.w or 0.0, nil, nil)
    end

    if newVeh then
        SetVehicleDoorsLocked(newVeh, 2)  -- Lock doors
        table.insert(raceVehicles, newVeh)
    end

    Wait(100)
    DoScreenFadeIn(225)

    nextRespawnAllowedAt = GetGameTimer() + RESPAWN_COOLDOWN_MS
    respawnHoldTime = 0.0
    EnableGhostMode(10)
    
    return true
end

local function spawnNextCheckpoint()
    safeDeleteCheckpoint(activeCP); safeDeleteCheckpoint(nextPreviewCP)
    safeRemoveBlip(activeBlip); safeRemoveBlip(previewBlip)

    if currentCheckpoint > #checkpoints then return end

    local pos = checkpoints[currentCheckpoint]
    if not pos then return end

    local function getPointTo(cp, nextCp)
        -- Prefer race flow direction so arrows point at the upcoming checkpoint.
        if nextCp then
            return nextCp.x, nextCp.y, nextCp.z + CHECKPOINT_Z_OFFSET
        end

        -- Fallback to stored heading in races.json if there is no next checkpoint.
        local heading = tonumber(cp.w) or 0.0
        local headingRad = math.rad(heading)
        local dirX = -math.sin(headingRad)
        local dirY = math.cos(headingRad)
        return cp.x + (dirX * CHECKPOINT_LOOKAHEAD), cp.y + (dirY * CHECKPOINT_LOOKAHEAD), cp.z + CHECKPOINT_Z_OFFSET
    end

    local posPointToX, posPointToY, posPointToZ = getPointTo(pos, checkpoints[currentCheckpoint + 1])

    local style = CHECKPOINT_STYLE
    if currentCheckpoint == #checkpoints then
        style = 4  -- Last checkpoint uses Standard Checkpoint 4
    end

    -- Active checkpoint
    activeCP = CreateCheckpoint(style,
        pos.x, pos.y, pos.z + CHECKPOINT_Z_OFFSET,
        posPointToX, posPointToY, posPointToZ,
        9.0, 255, 255, 255, 255, 0
    )

    -- Primary color affects the main ring; secondary color affects inner arrow/highlight.
    if pos.type == "transform" then
        -- Check if this is a specific vehicle (orange) or randomized (pink)
        if pos.transformVehicle and pos.transformVehicle ~= 0 then
            -- Specific vehicle transform: Orange
            SetCheckpointRgba(activeCP, 255, 140, 0, 220)    -- Orange outer ring
            SetCheckpointRgba2(activeCP, 255, 200, 0, 255)   -- Bright orange center arrow
        else
            -- Randomized vehicle transform: Pink
            SetCheckpointRgba(activeCP, 255, 105, 180, 220)  -- Pink outer ring
            SetCheckpointRgba2(activeCP, 255, 150, 200, 255) -- Bright pink center arrow
        end
    else
        -- Normal checkpoints: Yellow and Blue
        SetCheckpointRgba(activeCP, 255, 230, 0, 220)   -- Yellow outer ring
        SetCheckpointRgba2(activeCP, 50, 150, 255, 255) -- Blue center arrow
    end

    -- Only add blips if not excluded from the race
    if not isRaceExcluded then
        activeBlip = AddBlipForCoord(pos.x, pos.y, pos.z)
        SetBlipSprite(activeBlip, 1)
        SetBlipColour(activeBlip, 5)   -- Blue for all checkpoints
        SetBlipScale(activeBlip, 0.9)
        SetBlipRoute(activeBlip, true)
        SetBlipRouteColour(activeBlip, 5) -- Keep route line normal yellow/standard color

        -- Preview checkpoint blip (next checkpoint)
        local nextIdx = currentCheckpoint + 1
        if nextIdx <= #checkpoints then
            local np = checkpoints[nextIdx]
            previewBlip = AddBlipForCoord(np.x, np.y, np.z)
            SetBlipSprite(previewBlip, 1)
            SetBlipColour(previewBlip, 5)   -- Blue for all checkpoints
            SetBlipScale(previewBlip, 0.7)
            SetBlipAlpha(previewBlip, 128)
        end
    end
end

local function getPlayerPoint()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    return { x = coords.x, y = coords.y, z = coords.z, w = heading }
end

local function camForwardVector()
    local rot = GetGameplayCamRot(2)
    local pitch = math.rad(rot.x)
    local yaw = math.rad(rot.z)
    local cp = math.cos(pitch)
    return vector3(-math.sin(yaw) * cp, math.cos(yaw) * cp, math.sin(pitch))
end

local function camRightVector()
    local rot = GetGameplayCamRot(2)
    local yaw = math.rad(rot.z + 90.0)
    return vector3(-math.sin(yaw), math.cos(yaw), 0.0)
end

local function notifyPropPlacerState()
    TriggerEvent('racebuilder:propplacerState', propPlacerActive)
end

local function getSelectedProp()
    if selectedPropIndex < 1 or selectedPropIndex > #placedProps then
        return nil
    end

    local entity = placedProps[selectedPropIndex]
    if entity and DoesEntityExist(entity) then
        return entity
    end

    return nil
end

local function normalizeSelection()
    local valid = {}
    local newScaleMap = {}
    for i = 1, #placedProps do
        local entity = placedProps[i]
        if entity and DoesEntityExist(entity) then
            valid[#valid + 1] = entity
            newScaleMap[entity] = getPropScale(entity)
        end
    end
    placedProps = valid
    propScaleByEntity = newScaleMap

    if #placedProps == 0 then
        selectedPropIndex = 0
        return
    end

    if selectedPropIndex < 1 then
        selectedPropIndex = 1
    elseif selectedPropIndex > #placedProps then
        selectedPropIndex = #placedProps
    end
end

local function spawnPropByName(modelName, initialPos, initialRot, initialScale)
    local modelHash = GetHashKey(modelName)
    if not IsModelInCdimage(modelHash) then
        TriggerEvent('chat:addMessage', { args = { '^1PROP', ('Model not found: %s'):format(modelName) } })
        return false
    end

    RequestModel(modelHash)
    local t0 = GetGameTimer()
    while not HasModelLoaded(modelHash) and (GetGameTimer() - t0) < 5000 do
        Wait(0)
    end

    if not HasModelLoaded(modelHash) then
        TriggerEvent('chat:addMessage', { args = { '^1PROP', ('Failed to load model: %s'):format(modelName) } })
        return false
    end

    local spawnPos = initialPos or (GetEntityCoords(PlayerPedId()) + (camForwardVector() * 4.0))
    local entity = CreateObjectNoOffset(modelHash, spawnPos.x, spawnPos.y, spawnPos.z, true, true, false)
    if not DoesEntityExist(entity) then
        TriggerEvent('chat:addMessage', { args = { '^1PROP', 'Failed to create prop entity.' } })
        return false
    end

    SetEntityAsMissionEntity(entity, true, true)
    FreezeEntityPosition(entity, true)
    SetEntityCollision(entity, true, true)
    if initialRot then
        SetEntityRotation(entity, initialRot.x or 0.0, initialRot.y or 0.0, initialRot.z or 0.0, 2, true)
    else
        SetEntityHeading(entity, GetGameplayCamRot(2).z)
    end

    placedProps[#placedProps + 1] = entity
    selectedPropIndex = #placedProps
    setPropScale(entity, initialScale or 1.0)
    return true
end

local function spawnPropByHash(modelHash, initialPos, initialRot, initialScale)
    if not IsModelInCdimage(modelHash) then
        TriggerEvent('chat:addMessage', { args = { '^1PROP', ('Model hash not found: %s'):format(tostring(modelHash)) } })
        return false
    end

    RequestModel(modelHash)
    local t0 = GetGameTimer()
    while not HasModelLoaded(modelHash) and (GetGameTimer() - t0) < 5000 do
        Wait(0)
    end

    if not HasModelLoaded(modelHash) then
        TriggerEvent('chat:addMessage', { args = { '^1PROP', ('Failed to load model hash: %s'):format(tostring(modelHash)) } })
        return false
    end

    local spawnPos = initialPos or (GetEntityCoords(PlayerPedId()) + (camForwardVector() * 4.0))
    local entity = CreateObjectNoOffset(modelHash, spawnPos.x, spawnPos.y, spawnPos.z, true, true, false)
    if not DoesEntityExist(entity) then
        TriggerEvent('chat:addMessage', { args = { '^1PROP', 'Failed to create prop entity.' } })
        return false
    end

    SetEntityAsMissionEntity(entity, true, true)
    FreezeEntityPosition(entity, true)
    SetEntityCollision(entity, true, true)
    if initialRot then
        -- vRot from Rockstar appears to be in radians
        -- Apply all rotations via SetEntityRotation
        local rotX = tonumber(initialRot.x) or 0.0
        local rotY = tonumber(initialRot.y) or 0.0
        local rotZ = tonumber(initialRot.z) or 0.0
        
        if rotX ~= 0.0 or rotY ~= 0.0 or rotZ ~= 0.0 then
            SetEntityRotation(entity, rotX, rotY, rotZ, 2, true)
        end
    else
        SetEntityHeading(entity, GetGameplayCamRot(2).z)
    end

    placedProps[#placedProps + 1] = entity
    selectedPropIndex = #placedProps
    setPropScale(entity, initialScale or 1.0)
    return true
end

local function spawnRacePropByHash(modelHash, initialPos, initialRot, initialScale)
    if not IsModelInCdimage(modelHash) then
        return false
    end

    RequestModel(modelHash)
    local t0 = GetGameTimer()
    while not HasModelLoaded(modelHash) and (GetGameTimer() - t0) < 5000 do
        Wait(0)
    end

    if not HasModelLoaded(modelHash) then
        return false
    end

    local spawnPos = initialPos or (GetEntityCoords(PlayerPedId()) + (camForwardVector() * 4.0))
    local entity = CreateObjectNoOffset(modelHash, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false)
    if not DoesEntityExist(entity) then
        return false
    end

    SetEntityAsMissionEntity(entity, true, true)
    FreezeEntityPosition(entity, true)
    SetEntityCollision(entity, true, true)
    if initialRot then
        -- Apply all rotations via SetEntityRotation (vRot from Rockstar is in radians)
        local rotX = tonumber(initialRot.x) or 0.0
        local rotY = tonumber(initialRot.y) or 0.0
        local rotZ = tonumber(initialRot.z) or 0.0
        SetEntityRotation(entity, rotX, rotY, rotZ, 2, true)
    end

    setPropScale(entity, initialScale or 1.0)

    raceSpawnedProps[#raceSpawnedProps + 1] = entity
    return true
end

local function collectPlacedPropsForSave()
    local out = {}
    normalizeSelection()

    for i = 1, #placedProps do
        local entity = placedProps[i]
        if entity and DoesEntityExist(entity) then
            local coords = GetEntityCoords(entity)
            local rot = GetEntityRotation(entity, 2)
            out[#out + 1] = {
                modelHash = GetEntityModel(entity),
                pos = { x = coords.x, y = coords.y, z = coords.z },
                rot = { x = rot.x, y = rot.y, z = rot.z },
                scale = getPropScale(entity)
            }
        end
    end

    return out
end

local function resetPropHistory()
    propUndoStack = {}
    propRedoStack = {}
    propEditGestureActive = false
    propRotateMode = false
    nextScaleAdjustAt = 0
    nextRotateAdjustAt = 0
end

local function pushUndoSnapshot()
    propUndoStack[#propUndoStack + 1] = collectPlacedPropsForSave()
    if #propUndoStack > 50 then
        table.remove(propUndoStack, 1)
    end
    propRedoStack = {}
end

local function applyPropSnapshot(snapshot)
    clearEntityList(placedProps)
    selectedPropIndex = 0

    if type(snapshot) ~= 'table' then
        return
    end

    for i = 1, #snapshot do
        local item = snapshot[i]
        if type(item) == 'table' and type(item.pos) == 'table' and type(item.rot) == 'table' then
            local modelHash = tonumber(item.modelHash)
            local px = tonumber(item.pos.x)
            local py = tonumber(item.pos.y)
            local pz = tonumber(item.pos.z)
            if modelHash and px and py and pz then
                spawnPropByHash(modelHash, { x = px, y = py, z = pz }, {
                    x = tonumber(item.rot.x) or 0.0,
                    y = tonumber(item.rot.y) or 0.0,
                    z = tonumber(item.rot.z) or 0.0
                }, tonumber(item.scale) or 1.0)
            end
        end
    end

    normalizeSelection()
end

RegisterCommand('+racebuilder_numpad8', function()
    numpad8Held = true
end, false)

RegisterCommand('-racebuilder_numpad8', function()
    numpad8Held = false
end, false)

RegisterCommand('+racebuilder_numpad2', function()
    numpad2Held = true
end, false)

RegisterCommand('-racebuilder_numpad2', function()
    numpad2Held = false
end, false)

RegisterCommand('+racebuilder_numpad4', function()
    numpad4Held = true
end, false)

RegisterCommand('-racebuilder_numpad4', function()
    numpad4Held = false
end, false)

RegisterCommand('+racebuilder_numpad6', function()
    numpad6Held = true
end, false)

RegisterCommand('-racebuilder_numpad6', function()
    numpad6Held = false
end, false)

RegisterCommand('+racebuilder_numpadmul', function()
    numpadMulHeld = true
end, false)

RegisterCommand('-racebuilder_numpadmul', function()
    numpadMulHeld = false
end, false)

RegisterCommand('+racebuilder_numpadsub', function()
    numpadSubHeld = true
end, false)

RegisterCommand('-racebuilder_numpadsub', function()
    numpadSubHeld = false
end, false)

RegisterCommand('racebuilder_numpad5_toggle_axis', function()
    if builderActive and propPlacerActive then
        propVerticalAxis = (propVerticalAxis == 'y') and 'z' or 'y'
    end
end, false)

RegisterCommand('racebuilder_toggle_rotate_mode', function()
    if builderActive and propPlacerActive then
        propRotateMode = not propRotateMode
        propEditGestureActive = false
    end
end, false)

RegisterCommand('racebuilder_toggle_mouse_gizmo', function()
    if builderActive and propPlacerActive then
        mouseGizmoMode = not mouseGizmoMode
        local status = mouseGizmoMode and '^2ON' or '^1OFF'
        TriggerEvent('chat:addMessage', { args = { '^3BUILDER', 'Mouse Gizmo Mode: ' .. status } })
    end
end, false)

RegisterCommand('rbspawnprop', function(_, args)
    if not builderActive then
        TriggerEvent('chat:addMessage', { args = { '^1BUILDER', 'Start race builder first.' } })
        return
    end

    local modelName = table.concat(args or {}, ' ')
    if modelName == '' then
        TriggerEvent('chat:addMessage', { args = { '^3BUILDER', 'Usage: /rbspawnprop <modelName>' } })
        return
    end

    TriggerEvent('racebuilder:propplacer:spawn', modelName)
end, false)

RegisterNetEvent('racebuilder:setCheckpointType')
AddEventHandler('racebuilder:setCheckpointType', function(cpType)
    setCheckpointType(cpType)
end)

RegisterKeyMapping('+racebuilder_numpad8', 'Race Builder Prop Axis +', 'keyboard', 'NUMPAD8')
RegisterKeyMapping('+racebuilder_numpad2', 'Race Builder Prop Axis -', 'keyboard', 'NUMPAD2')
RegisterKeyMapping('+racebuilder_numpad4', 'Race Builder Prop -X', 'keyboard', 'NUMPAD4')
RegisterKeyMapping('+racebuilder_numpad6', 'Race Builder Prop +X', 'keyboard', 'NUMPAD6')
RegisterKeyMapping('+racebuilder_numpadmul', 'Race Builder Scale Down', 'keyboard', 'NUMPADMULTIPLY')
RegisterKeyMapping('+racebuilder_numpadsub', 'Race Builder Scale Up', 'keyboard', 'NUMPADSUBTRACT')
RegisterKeyMapping('racebuilder_numpad5_toggle_axis', 'Race Builder Toggle Y/Z Axis', 'keyboard', 'NUMPAD5')
RegisterKeyMapping('racebuilder_toggle_rotate_mode', 'Race Builder Toggle Rotate Mode', 'keyboard', 'R')
RegisterKeyMapping('racebuilder_toggle_mouse_gizmo', 'Race Builder Toggle Mouse Gizmo', 'keyboard', 'F6')

local function setPropPlacerActive(isActive)
    if propPlacerActive == isActive then
        return
    end

    propPlacerActive = isActive
    local ped = PlayerPedId()
    if propPlacerActive then
        SetFollowPedCamViewMode(4)
        SetEntityCollision(ped, false, false)
        FreezeEntityPosition(ped, false)
        SetLocalPlayerVisibleLocally(false)
        SetEntityAlpha(ped, 0, false)
    else
        SetEntityCollision(ped, true, true)
        SetLocalPlayerVisibleLocally(true)
        ResetEntityAlpha(ped)
        propRotateMode = false
        propEditGestureActive = false
        nextRotateAdjustAt = 0
        mouseGizmoMode = false
    end

    notifyPropPlacerState()
end

local function getGizmoAxisVector(axis)
    if axis == 'x' then
        return vector3(1.0, 0.0, 0.0)
    end
    if axis == 'y' then
        return vector3(0.0, 1.0, 0.0)
    end
    return vector3(0.0, 0.0, 1.0)
end

local function getGizmoAxisScreenDirection(origin, axisVec, axisLength)
    local ox, oy, oz = origin.x, origin.y, origin.z
    local onScreenA, sxA, syA = GetScreenCoordFromWorldCoord(ox, oy, oz)
    local p2 = origin + (axisVec * axisLength)
    local onScreenB, sxB, syB = GetScreenCoordFromWorldCoord(p2.x, p2.y, p2.z)
    if not onScreenA or not onScreenB then
        return nil, nil
    end

    local dx = sxB - sxA
    local dy = syB - syA
    local mag = math.sqrt((dx * dx) + (dy * dy))
    if mag < 0.0001 then
        return nil, nil
    end

    return dx / mag, dy / mag
end

local function selectAxisFromCrosshair(origin, axisLength)
    local axes = {
        { key = 'x', vec = vector3(1.0, 0.0, 0.0) },
        { key = 'y', vec = vector3(0.0, 1.0, 0.0) },
        { key = 'z', vec = vector3(0.0, 0.0, 1.0) }
    }

    local bestAxis = nil
    local bestDist = 999.0
    local cx, cy = 0.5, 0.5

    for i = 1, #axes do
        local endPos = origin + (axes[i].vec * axisLength)
        local onScreen, sx, sy = GetScreenCoordFromWorldCoord(endPos.x, endPos.y, endPos.z)
        if onScreen then
            local dx = sx - cx
            local dy = sy - cy
            local dist = math.sqrt((dx * dx) + (dy * dy))
            if dist < bestDist then
                bestDist = dist
                bestAxis = axes[i].key
            end
        end
    end

    if bestAxis and bestDist <= 0.08 then
        propGizmoAxis = bestAxis
        return true
    end

    return false
end

-- Events
RegisterNetEvent('race:tpClient')
AddEventHandler('race:tpClient', function(coords, heading, vehicleModel, name)
    raceName = name or raceName
    defaultVehicle = vehicleModel or defaultVehicle
    countdownLocked = true

    local ped = PlayerPedId()
    
    -- Delete player's current vehicle if they're in one
    local currentVehicle = GetVehiclePedIsIn(ped, false)
    if currentVehicle ~= 0 then
        DeleteEntity(currentVehicle)
    end
    
    SetEntityCoords(ped, coords.x, coords.y, coords.z + 1, false, false, false, true)
    SetEntityHeading(ped, heading or coords.w or 0.0)

    local veh = spawnAndWarpVehicle(defaultVehicle, coords, heading or coords.w)
    if veh then
        SetVehicleHandbrake(veh, true)
        FreezeEntityPosition(veh, true)
        SetVehicleForwardSpeed(veh, 0.0)
        SetVehicleDoorsLocked(veh, 2)  -- Lock doors
        table.insert(raceVehicles, veh)
    end

    lastCheckpointPos = {x=coords.x, y=coords.y, z=coords.z, w=coords.w or 0.0}
end)


-- Enforce a hard pre-race lock from spawn until GO.
Citizen.CreateThread(function()
    while true do
        Wait(0)
        if countdownLocked then
            DisableControlAction(0, 71, true)
            DisableControlAction(0, 72, true)
            DisableControlAction(0, 59, true)
            DisableControlAction(0, 60, true)
            DisableControlAction(0, 75, true)
            DisableControlAction(0, 21, true)

            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and DoesEntityExist(veh) then
                SetVehicleHandbrake(veh, true)
                FreezeEntityPosition(veh, true)
                SetVehicleForwardSpeed(veh, 0.0)
                SetVehicleDoorsLocked(veh, 2)  -- Lock doors
            end
        end
    end
end)

-- Prevent exiting vehicle during race
Citizen.CreateThread(function()
    while true do
        Wait(0)
        if raceStarted then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and DoesEntityExist(veh) then
                SetVehicleDoorsLocked(veh, 2)  -- Keep doors locked
                DisableControlAction(0, 75, true)  -- Disable vehicle exit control
            end
        end
    end
end)

local function drawCircle(x, y, radius, red, green, blue, alpha)
    local segments = 32
    for i = 0, segments - 1 do
        local angle1 = (i / segments) * 360.0
        local angle2 = ((i + 1) / segments) * 360.0
        
        local x1 = x + radius * math.cos(math.rad(angle1))
        local y1 = y + radius * math.sin(math.rad(angle1))
        local x2 = x + radius * math.cos(math.rad(angle2))
        local y2 = y + radius * math.sin(math.rad(angle2))
        
        DrawLine(x1, y1, 0.0, x2, y2, 0.0, red, green, blue, alpha)
    end
end

RegisterNetEvent('race:startCountdown')
AddEventHandler('race:startCountdown', function(serverStartTime)
    if raceStarted then return end
    if isRaceExcluded then return end  -- Skip countdown for excluded players
    raceStarted = true
    StartGhostLoop()
    EnableGhostMode(15)
    playerCheckpoints = {}  -- Reset player checkpoint tracking
    serverLeaderboard = {}  -- Reset server leaderboard
    countdownLocked = true
    
    -- Initialize current vehicle to race default vehicle
    currentRaceVehicle = resolveVehicleModelHash(defaultVehicle)
    lastCheckpointTransformVehicle = nil

    -- Print transform checkpoint info to console and chat
    local transformCount = 0
    for i, cp in ipairs(checkpoints) do
        if cp.type == "transform" then
            transformCount = transformCount + 1
            local vehicleHash = cp.transformVehicle or defaultVehicle
            local vehicleName = getModelName(vehicleHash)
            TriggerEvent('chat:addMessage', {
                color = {255, 140, 0},
                multiline = true,
                args = {"Transform Checkpoint", i .. " ▶ " .. vehicleName}
            })
            print("^3[Transform Checkpoint " .. i .. "] Vehicle: " .. vehicleName .. " (Hash: " .. tostring(vehicleHash) .. ")^7")
        end
    end
    
    if transformCount > 0 then
        TriggerEvent('chat:addMessage', {
            color = {255, 165, 0},
            multiline = true,
            args = {"Race Info", "⚡ " .. transformCount .. " transform checkpoint(s) detected!"}
        })
        print("^3[Race] This race has " .. transformCount .. " transform checkpoint(s)!^7")
    end

    local ped = PlayerPedId()
    local startVeh = GetVehiclePedIsIn(ped, false)
    if startVeh ~= 0 and DoesEntityExist(startVeh) then
        FreezeEntityPosition(startVeh, true)
        SetVehicleHandbrake(startVeh, true)
    end

    -- Countdown with HTML images
    local countdownNumbers = {"5", "4", "3", "2", "1"}
    
    for _, num in ipairs(countdownNumbers) do
        PlaySoundFrontend(-1, "5_SEC_WARNING", "HUD_MINI_GAME_SOUNDSET", true)
        
        -- Show countdown image via NUI
        local msg = json.encode({
            type = 'countdown',
            show = true,
            number = num
        })
        TriggerEvent('chat:addMessage', { args = { '^2COUNTDOWN', 'Showing: ' .. num } })
        SendNuiMessage(msg)
        
        local countdownStart = GetGameTimer()
        while (GetGameTimer() - countdownStart) < 1000 do
            -- Hard lock movement during countdown.
            DisableControlAction(0, 71, true)
            DisableControlAction(0, 72, true)
            DisableControlAction(0, 59, true)
            DisableControlAction(0, 60, true)
            DisableControlAction(0, 75, true)
            DisableControlAction(0, 21, true)
            
            Wait(0)
        end
    end

    -- Show GO!
    raceTimerStart = GetGameTimer()
    PlaySoundFrontend(-1, "GO", "HUD_MINI_GAME_SOUNDSET", true)
    
    SendNuiMessage(json.encode({
        type = 'countdown',
        show = true,
        number = 'Go'
    }))
    
    local goStart = GetGameTimer()
    while (GetGameTimer() - goStart) < 1000 do
        DisableControlAction(0, 71, true)
        DisableControlAction(0, 72, true)
        DisableControlAction(0, 59, true)
        DisableControlAction(0, 60, true)
        DisableControlAction(0, 75, true)
        DisableControlAction(0, 21, true)
        
        Wait(0)
    end

    -- Hide countdown
    SendNuiMessage(json.encode({
        type = 'countdown',
        show = false
    }))

    countdownLocked = false

    local releaseVeh = GetVehiclePedIsIn(PlayerPedId(), false)
    if releaseVeh ~= 0 and DoesEntityExist(releaseVeh) then
        SetVehicleHandbrake(releaseVeh, false)
        FreezeEntityPosition(releaseVeh, false)
    end

    for _, veh in ipairs(raceVehicles) do
        if DoesEntityExist(veh) then
            SetVehicleHandbrake(veh, false)
            FreezeEntityPosition(veh, false)
        end
    end
end)

RegisterNetEvent('race:setExcluded')
AddEventHandler('race:setExcluded', function(excluded)
    isRaceExcluded = excluded == true
end)

RegisterNetEvent('race:showTransformSmoke')
AddEventHandler('race:showTransformSmoke', function(coords)
    -- Show transform smoke effect to all players
    CreateThread(function()
        RequestNamedPtfxAsset("scr_as_trans")
        local startTime = GetGameTimer()
        while not HasNamedPtfxAssetLoaded("scr_as_trans") and (GetGameTimer() - startTime) < 1500 do
            Wait(0)
        end
        
        if HasNamedPtfxAssetLoaded("scr_as_trans") then
            UseParticleFxAssetNextCall("scr_as_trans")
            -- Use looped effect for better visibility
            local effect = StartParticleFxLoopedAtCoord("scr_as_trans_smoke", coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 2.0, false, false, false)
            Wait(700)  -- Keep effect visible for 700ms
            StopParticleFxLooped(effect, true)
            RemoveNamedPtfxAsset("scr_as_trans")
        end
    end)
end)

RegisterNetEvent('race:startCheckpoints')
AddEventHandler('race:startCheckpoints', function(list)
    checkpoints = list
    currentCheckpoint = 1
    raceFinishReported = false
    spawnNextCheckpoint()
end)

RegisterNetEvent('race:startProps')
AddEventHandler('race:startProps', function(props)
    clearEntityList(raceSpawnedProps)

    if type(props) ~= 'table' then
        return
    end

    for i = 1, #props do
        local prop = props[i]
        if type(prop) == 'table' and type(prop.pos) == 'table' then
            local modelHash = tonumber(prop.modelHash)
            local px = tonumber(prop.pos.x)
            local py = tonumber(prop.pos.y)
            local pz = tonumber(prop.pos.z)
            if modelHash and px and py and pz then
                local rot = type(prop.rot) == 'table' and {
                    x = tonumber(prop.rot.x) or 0.0,
                    y = tonumber(prop.rot.y) or 0.0,
                    z = tonumber(prop.rot.z) or 0.0
                } or { x = 0.0, y = 0.0, z = 0.0 }
                spawnRacePropByHash(modelHash, { x = px, y = py, z = pz }, rot, tonumber(prop.scale) or 1.0)
            end
        end
    end
end)

RegisterNetEvent('racebuilder:setActive')
AddEventHandler('racebuilder:setActive', function(isActive)
    builderActive = isActive == true
    SetTextChatEnabled(not builderActive)
    if not builderActive then
        setPropPlacerActive(false)
        clearEntityList(placedProps)
        selectedPropIndex = 0
        resetPropHistory()
    end
    if not builderActive then
        builderRaceId = ""
        builderRaceName = ""
        builderVehicle = ""
        builderStartCount = 0
        builderCheckpointCount = 0
        builderStartGrid = {}
        builderCheckpoints = {}
    end
end)

RegisterNetEvent('racebuilder:updateMeta')
AddEventHandler('racebuilder:updateMeta', function(id, raceName, vehicle, startCount, checkpointCount, isActive)
    builderActive = isActive == true
    SetTextChatEnabled(not builderActive)
    builderRaceId = id or ""
    builderRaceName = raceName or ""
    builderVehicle = vehicle or ""
    builderStartCount = tonumber(startCount) or 0
    builderCheckpointCount = tonumber(checkpointCount) or 0
end)

RegisterNetEvent('racebuilder:updatePoints')
AddEventHandler('racebuilder:updatePoints', function(startGrid, checkpointList)
    builderStartGrid = startGrid or {}
    builderCheckpoints = checkpointList or {}
end)

RegisterNetEvent('racebuilder:updateProps')
AddEventHandler('racebuilder:updateProps', function(props)
    clearEntityList(placedProps)
    selectedPropIndex = 0
    resetPropHistory()

    if type(props) ~= 'table' then
        return
    end

    for i = 1, #props do
        local prop = props[i]
        if type(prop) == 'table' and type(prop.pos) == 'table' then
            local modelHash = tonumber(prop.modelHash)
            local px = tonumber(prop.pos.x)
            local py = tonumber(prop.pos.y)
            local pz = tonumber(prop.pos.z)
            if modelHash and px and py and pz then
                local rot = type(prop.rot) == 'table' and {
                    x = tonumber(prop.rot.x) or 0.0,
                    y = tonumber(prop.rot.y) or 0.0,
                    z = tonumber(prop.rot.z) or 0.0
                } or { x = 0.0, y = 0.0, z = 0.0 }
                spawnPropByHash(modelHash, { x = px, y = py, z = pz }, rot, tonumber(prop.scale) or 1.0)
            end
        end
    end
end)

RegisterNetEvent('racebuilder:propplacer:syncToServer')
AddEventHandler('racebuilder:propplacer:syncToServer', function()
    TriggerServerEvent('racebuilder:updateProps', collectPlacedPropsForSave())
end)

RegisterNetEvent('racebuilder:captureStart')
AddEventHandler('racebuilder:captureStart', function()
    TriggerServerEvent('racebuilder:addStart', getPlayerPoint())
end)

RegisterNetEvent('racebuilder:captureCheckpoint')
AddEventHandler('racebuilder:captureCheckpoint', function()
    TriggerServerEvent('racebuilder:addCheckpoint', getPlayerPoint(), checkpointTypeBeingPlaced)
end)

RegisterNetEvent('racebuilder:captureRemoveStart')
AddEventHandler('racebuilder:captureRemoveStart', function()
    TriggerServerEvent('racebuilder:removeStartAt', getPlayerPoint())
end)

RegisterNetEvent('racebuilder:captureRemoveCheckpoint')
AddEventHandler('racebuilder:captureRemoveCheckpoint', function()
    TriggerServerEvent('racebuilder:removeCheckpointAt', getPlayerPoint())
end)

RegisterNetEvent('racebuilder:removeAllCheckpoints')
AddEventHandler('racebuilder:removeAllCheckpoints', function()
    TriggerServerEvent('racebuilder:clearAllCheckpoints')
end)

RegisterNetEvent('racebuilder:propplacer:toggle')
AddEventHandler('racebuilder:propplacer:toggle', function()
    if not builderActive then
        return
    end

    setPropPlacerActive(not propPlacerActive)
end)

RegisterNetEvent('racebuilder:propplacer:forceOff')
AddEventHandler('racebuilder:propplacer:forceOff', function()
    setPropPlacerActive(false)
end)

RegisterNetEvent('racebuilder:propplacer:spawn')
AddEventHandler('racebuilder:propplacer:spawn', function(modelName)
    if not builderActive then
        return
    end

    if type(modelName) ~= 'string' or modelName == '' then
        return
    end

    pushUndoSnapshot()
    spawnPropByName(modelName)
end)

RegisterNetEvent('racebuilder:propplacer:deleteSelected')
AddEventHandler('racebuilder:propplacer:deleteSelected', function()
    local selected = getSelectedProp()
    if not selected then
        return
    end

    pushUndoSnapshot()
    DeleteEntity(selected)
    normalizeSelection()
end)

RegisterNetEvent('racebuilder:propplacer:duplicate')
AddEventHandler('racebuilder:propplacer:duplicate', function()
    local selected = getSelectedProp()
    if not selected then
        return
    end

    pushUndoSnapshot()

    local modelHash = GetEntityModel(selected)
    local spawnPos = GetEntityCoords(selected)
    local rot = GetEntityRotation(selected, 2)
    local scale = getPropScale(selected)
    spawnPropByHash(modelHash, spawnPos, rot, scale)
end)

RegisterNetEvent('racebuilder:propplacer:scaleLeft')
AddEventHandler('racebuilder:propplacer:scaleLeft', function()
    local selected = getSelectedProp()
    if not selected then
        return
    end

    pushUndoSnapshot()
    setPropScale(selected, getPropScale(selected) - 0.05)
end)

RegisterNetEvent('racebuilder:propplacer:scaleRight')
AddEventHandler('racebuilder:propplacer:scaleRight', function()
    local selected = getSelectedProp()
    if not selected then
        return
    end

    pushUndoSnapshot()
    setPropScale(selected, getPropScale(selected) + 0.05)
end)

RegisterNetEvent('racebuilder:propplacer:undo')
AddEventHandler('racebuilder:propplacer:undo', function()
    if #propUndoStack < 1 then
        return
    end

    propRedoStack[#propRedoStack + 1] = collectPlacedPropsForSave()
    local snapshot = propUndoStack[#propUndoStack]
    propUndoStack[#propUndoStack] = nil
    applyPropSnapshot(snapshot)
end)

RegisterNetEvent('racebuilder:propplacer:redo')
AddEventHandler('racebuilder:propplacer:redo', function()
    if #propRedoStack < 1 then
        return
    end

    propUndoStack[#propUndoStack + 1] = collectPlacedPropsForSave()
    local snapshot = propRedoStack[#propRedoStack]
    propRedoStack[#propRedoStack] = nil
    applyPropSnapshot(snapshot)
end)

RegisterNetEvent('racebuilder:propplacer:changeModel')
AddEventHandler('racebuilder:propplacer:changeModel', function(modelName)
    local selected = getSelectedProp()
    if not selected then
        TriggerEvent('chat:addMessage', { args = { '^1PROP', 'No prop selected.' } })
        return
    end

    if type(modelName) ~= 'string' or modelName == '' then
        return
    end

    local modelHash = GetHashKey(modelName)
    if not IsModelInCdimage(modelHash) then
        TriggerEvent('chat:addMessage', { args = { '^1PROP', ('Model not found: %s'):format(modelName) } })
        return
    end

    RequestModel(modelHash)
    local t0 = GetGameTimer()
    while not HasModelLoaded(modelHash) and (GetGameTimer() - t0) < 5000 do
        Wait(0)
    end

    if not HasModelLoaded(modelHash) then
        TriggerEvent('chat:addMessage', { args = { '^1PROP', ('Failed to load model: %s'):format(modelName) } })
        return
    end

    pushUndoSnapshot()

    local oldCoords = GetEntityCoords(selected)
    local oldRot = GetEntityRotation(selected, 2)
    local oldScale = getPropScale(selected)

    -- Delete the old prop
    DeleteEntity(selected)
    normalizeSelection()

    -- Spawn new prop with old coordinates and rotation
    local entity = CreateObjectNoOffset(modelHash, oldCoords.x, oldCoords.y, oldCoords.z, true, true, false)
    if not DoesEntityExist(entity) then
        TriggerEvent('chat:addMessage', { args = { '^1PROP', 'Failed to create new prop entity.' } })
        return
    end

    SetEntityAsMissionEntity(entity, true, true)
    FreezeEntityPosition(entity, true)
    SetEntityCollision(entity, true, true)
    SetEntityRotation(entity, oldRot.x, oldRot.y, oldRot.z, 2, true)

    placedProps[#placedProps + 1] = entity
    selectedPropIndex = #placedProps
    setPropScale(entity, oldScale)
    
    TriggerEvent('chat:addMessage', { args = { '^2PROP', ('Changed to model: %s'):format(modelName) } })
end)

RegisterNetEvent('racebuilder:propplacer:cycleProp')
AddEventHandler('racebuilder:propplacer:cycleProp', function()
    normalizeSelection()
    
    if #placedProps < 1 then
        TriggerEvent('chat:addMessage', { args = { '^1PROP', 'No props placed.' } })
        return
    end

    selectedPropIndex = selectedPropIndex + 1
    if selectedPropIndex > #placedProps then
        selectedPropIndex = 1
    end

    local selected = placedProps[selectedPropIndex]
    if selected and DoesEntityExist(selected) then
        TriggerEvent('chat:addMessage', { args = { '^2PROP', ('Selected prop %d / %d'):format(selectedPropIndex, #placedProps) } })
    end
end)



Citizen.CreateThread(function()
    while true do
        Wait(0)

        if builderActive and propPlacerActive then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local speed = IsControlPressed(0, 21) and 0.35 or 0.12
            local forward = camForwardVector()
            local right = camRightVector()
            local move = vector3(0.0, 0.0, 0.0)

            -- Keep prop placer locked to first person while active.
            if GetFollowPedCamViewMode() ~= 4 then
                SetFollowPedCamViewMode(4)
            end
            SetEntityLocallyInvisible(ped)
            DisableControlAction(0, 0, true)
            DisableControlAction(0, 26, true)

            if mouseGizmoMode then
                -- In mouse gizmo mode, allow mouse to interact with gizmos
                SetCursorLocation(0.5, 0.5)
            else
                -- Normal prop placer movement
                if IsControlPressed(0, 32) then move = move + (forward * speed) end -- W
                if IsControlPressed(0, 33) then move = move - (forward * speed) end -- S
                if IsControlPressed(0, 34) then move = move + (right * speed) end -- A
                if IsControlPressed(0, 35) then move = move - (right * speed) end -- D
                if IsControlPressed(0, 22) then move = move + vector3(0.0, 0.0, speed) end -- Space
                if IsControlPressed(0, 36) then move = move - vector3(0.0, 0.0, speed) end -- Ctrl

                local newPos = pos + move
                SetEntityCoordsNoOffset(ped, newPos.x, newPos.y, newPos.z, true, true, true)
                SetEntityHeading(ped, GetGameplayCamRot(2).z)
            end

            normalizeSelection()
            local selected = getSelectedProp()
            if selected then
                local sPos = GetEntityCoords(selected)
                local xLen = 1.5
                local yLen = 1.5
                local zLen = 1.5

                local xR, xG, xB = 255, 50, 50
                local yR, yG, yB = 50, 255, 50
                local zR, zG, zB = 50, 130, 255

                if propVerticalAxis == 'y' then
                    yR, yG, yB = 255, 255, 255
                else
                    zR, zG, zB = 255, 255, 255
                end

                DrawLine(sPos.x, sPos.y, sPos.z, sPos.x + xLen, sPos.y, sPos.z, xR, xG, xB, 235)
                DrawLine(sPos.x, sPos.y, sPos.z, sPos.x, sPos.y + yLen, sPos.z, yR, yG, yB, 235)
                DrawLine(sPos.x, sPos.y, sPos.z, sPos.x, sPos.y, sPos.z + zLen, zR, zG, zB, 235)
                DrawMarker(28, sPos.x, sPos.y, sPos.z + 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.24, 0.24, 0.24, 50, 255, 90, 235, false, false, 2, false, nil, nil, false)

                DrawMarker(28, sPos.x + xLen, sPos.y, sPos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.15, 0.15, 0.15, xR, xG, xB, 220, false, false, 2, false, nil, nil, false)
                DrawMarker(28, sPos.x, sPos.y + yLen, sPos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.15, 0.15, 0.15, yR, yG, yB, 220, false, false, 2, false, nil, nil, false)
                DrawMarker(28, sPos.x, sPos.y, sPos.z + zLen, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.15, 0.15, 0.15, zR, zG, zB, 220, false, false, 2, false, nil, nil, false)

                local step = IsControlPressed(0, 21) and 0.08 or 0.02
                local nPos = sPos
                local didTransform = false
                local heldEditInput = numpad4Held or numpad6Held or numpad8Held or numpad2Held or numpadMulHeld or numpadSubHeld

                if heldEditInput and not propEditGestureActive then
                    pushUndoSnapshot()
                    propEditGestureActive = true
                end

                if propRotateMode then
                    local rot = GetEntityRotation(selected, 2)
                    local nowRot = GetGameTimer()
                    if (numpad4Held or numpad6Held or numpad8Held or numpad2Held) and nowRot >= nextRotateAdjustAt then
                        local rotStep = 90.0

                        if numpad4Held then
                            rot = vector3(snapToRightAngle(rot.x) - rotStep, rot.y, rot.z)
                            didTransform = true
                        end
                        if numpad6Held then
                            rot = vector3(snapToRightAngle(rot.x) + rotStep, rot.y, rot.z)
                            didTransform = true
                        end
                        if numpad8Held then
                            if propVerticalAxis == 'y' then
                                rot = vector3(rot.x, snapToRightAngle(rot.y) + rotStep, rot.z)
                            else
                                rot = vector3(rot.x, rot.y, snapToRightAngle(rot.z) + rotStep)
                            end
                            didTransform = true
                        end
                        if numpad2Held then
                            if propVerticalAxis == 'y' then
                                rot = vector3(rot.x, snapToRightAngle(rot.y) - rotStep, rot.z)
                            else
                                rot = vector3(rot.x, rot.y, snapToRightAngle(rot.z) - rotStep)
                            end
                            didTransform = true
                        end

                        nextRotateAdjustAt = nowRot + 125
                    end

                    if didTransform then
                        SetEntityRotation(selected, rot.x, rot.y, rot.z, 2, true)
                    end
                else
                    if numpad4Held then
                        nPos = nPos + vector3(-step, 0.0, 0.0)
                        didTransform = true
                    end
                    if numpad6Held then
                        nPos = nPos + vector3(step, 0.0, 0.0)
                        didTransform = true
                    end
                    if numpad8Held then
                        if propVerticalAxis == 'y' then
                            nPos = nPos + vector3(0.0, step, 0.0)
                        else
                            nPos = nPos + vector3(0.0, 0.0, step)
                        end
                        didTransform = true
                    end
                    if numpad2Held then
                        if propVerticalAxis == 'y' then
                            nPos = nPos + vector3(0.0, -step, 0.0)
                        else
                            nPos = nPos + vector3(0.0, 0.0, -step)
                        end
                        didTransform = true
                    end

                    if didTransform then
                        SetEntityCoordsNoOffset(selected, nPos.x, nPos.y, nPos.z, true, true, true)
                    end
                end

                local now = GetGameTimer()
                local didScale = false
                if (numpadMulHeld or numpadSubHeld) and now >= nextScaleAdjustAt then
                    local scaleDelta = 0.02
                    if numpadMulHeld then
                        setPropScale(selected, getPropScale(selected) - scaleDelta)
                        didScale = true
                    end
                    if numpadSubHeld then
                        setPropScale(selected, getPropScale(selected) + scaleDelta)
                        didScale = true
                    end
                    nextScaleAdjustAt = now + 65
                end

                if not heldEditInput then
                    propEditGestureActive = false
                end
            end
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(0)
        if builderActive and not raceStarted then
            local playerPos = GetEntityCoords(PlayerPedId())

            for i = 1, #builderStartGrid do
                local p = builderStartGrid[i]
                local dist = #(playerPos - vector3(p.x, p.y, p.z))
                local near = dist < 6.0
                DrawMarker(
                    1,
                    p.x, p.y, p.z - 1.0,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    2.2, 2.2, 1.2,
                    near and 255 or 70,
                    near and 225 or 180,
                    70,
                    near and 220 or 170,
                    false,
                    false,
                    2,
                    false,
                    nil,
                    nil,
                    false
                )
            end

            for i = 1, #builderCheckpoints do
                local p = builderCheckpoints[i]
                local dist = #(playerPos - vector3(p.x, p.y, p.z))
                local near = dist < 6.0
                DrawMarker(
                    1,
                    p.x, p.y, p.z - 1.0,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    1.8, 1.8, 1.0,
                    70,
                    near and 255 or 170,
                    near and 255 or 220,
                    near and 220 or 165,
                    false,
                    false,
                    2,
                    false,
                    nil,
                    nil,
                    false
                )
            end
        end
    end
end)

-- Checkpoint detection
Citizen.CreateThread(function()
    while true do
        Wait(0)
        if currentCheckpoint <= #checkpoints and not isRaceExcluded then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local cp = checkpoints[currentCheckpoint]
            if cp and #(pos - vector3(cp.x, cp.y, cp.z)) < 12.0 then
                PlaySoundFrontend(-1, "CHECKPOINT_NORMAL", "HUD_MINI_GAME_SOUNDSET", true)
                safeDeleteCheckpoint(activeCP)
                safeRemoveBlip(activeBlip)

                -- Handle Transform Checkpoint
                if cp.type == "transform" then
                    local veh = GetVehiclePedIsIn(ped, false)
                    if veh ~= 0 and DoesEntityExist(veh) then
                        local vehCoords = GetEntityCoords(veh)
                        local oldModelHash = GetEntityModel(veh)
                        local oldVelocity = GetEntityVelocity(veh)
                        local oldSpeed = GetEntitySpeed(veh)
                        local carryVelocity = vector3(oldVelocity.x or 0.0, oldVelocity.y or 0.0, 0.0)

                        -- Show large cloud to hide the car transformation
                        spawnTransformCloudOnEntity(ped)
                        applyTransformCloudOverrideBriefly()
                        
                        -- Broadcast smoke effect so all players can see it
                        local vehCoords = GetEntityCoords(veh)
                        TriggerServerEvent('race:playTransformSmoke', vehCoords)

                        -- Capture old car transform data.
                        local oldPos = GetEntityCoords(veh)
                        local oldHeading = GetEntityHeading(veh)

                        -- Use stored transform vehicle if available, otherwise randomize
                        local transformVehicle = cp.transformVehicle or pickRandomTransformVehicle(oldModelHash)
                        local newVeh = transformVehicle and spawnAndWarpVehicle(transformVehicle, oldPos, oldHeading, carryVelocity, oldSpeed) or nil
                        if not newVeh then
                            newVeh = spawnAndWarpVehicle(defaultVehicle, oldPos, oldHeading, carryVelocity, oldSpeed)
                        end

                        -- Only delete old car after replacement exists and player is seated in it.
                        if newVeh and GetVehiclePedIsIn(ped, false) == newVeh then
                            -- Ensure player stays visible after the warp.
                            SetEntityVisible(ped, true, false)
                            ResetEntityAlpha(ped)
                            
                            -- Track the new vehicle for respawns
                            currentRaceVehicle = GetEntityModel(newVeh)

                            SetEntityAsMissionEntity(veh, true, true)
                            DeleteVehicle(veh)
                            if DoesEntityExist(veh) then
                                DeleteEntity(veh)
                            end
                        else
                            if newVeh and DoesEntityExist(newVeh) then
                                DeleteVehicle(newVeh)
                            end
                            -- Keep the original vehicle if replacement failed.
                            SetVehicleEngineOn(veh, true, true, false)
                            SetVehicleHandbrake(veh, false)
                        end

                        if newVeh and GetVehiclePedIsIn(ped, false) == newVeh then
                            local model = GetEntityModel(newVeh)
                            if not IsThisModelAHeli(model) and not IsThisModelAPlane(model) and not IsThisModelABoat(model) then
                                SetVehicleOnGroundProperly(newVeh)
                            end
                            table.insert(raceVehicles, newVeh)
                        end
                    end
                end

                -- Handle Warp Checkpoint
                if cp.type == "warp" and currentCheckpoint < #checkpoints then
                    local nextCp = checkpoints[currentCheckpoint + 1]
                    if nextCp then
                        local veh = GetVehiclePedIsIn(ped, false)
                        local nextHeading = nextCp.w or 0.0
                        
                        -- Calculate heading toward next-next checkpoint if available
                        if currentCheckpoint + 2 <= #checkpoints then
                            local nextNextCp = checkpoints[currentCheckpoint + 2]
                            local dx = nextNextCp.x - nextCp.x
                            local dy = nextNextCp.y - nextCp.y
                            nextHeading = GetHeadingFromVector_2d(dx, dy)
                        end
                        
                        if veh ~= 0 and DoesEntityExist(veh) then
                            -- Warp vehicle to next checkpoint
                            SetEntityCoords(veh, nextCp.x, nextCp.y, nextCp.z, false, false, false, true)
                            SetEntityHeading(veh, nextHeading)
                        end
                        
                        -- Warp ped as well
                        SetEntityCoords(ped, nextCp.x, nextCp.y, nextCp.z + 1, false, false, false, true)
                        SetEntityHeading(ped, nextHeading)
                    end
                end

                local heading = cp.w or 0.0
                local nextCp = checkpoints[currentCheckpoint + 1]
                if nextCp then
                    local dx = nextCp.x - cp.x
                    local dy = nextCp.y - cp.y
                    heading = GetHeadingFromVector_2d(dx, dy)
                end
                lastCheckpointPos = {x=cp.x, y=cp.y, z=cp.z, w=heading}
                lastCheckpointType = (cp.type == "transform") and "transform" or (cp.type == "warp") and "warp" or "normal"
                lastCheckpointTransformVehicle = cp.transformVehicle or nil
                
                -- Track current vehicle for respawns
                local ped = PlayerPedId()
                local veh = GetVehiclePedIsIn(ped, false)
                if veh ~= 0 and DoesEntityExist(veh) then
                    currentRaceVehicle = GetEntityModel(veh)
                end

                if currentCheckpoint == #checkpoints then
                    if not raceFinishReported then
                        raceFinishReported = true
                        TriggerServerEvent('race:playerFinished')
                    end

                    if cp.type ~= "transform" then
                        local veh = GetVehiclePedIsIn(ped, false)
                        if veh ~= 0 and DoesEntityExist(veh) then DeleteVehicle(veh) end
                    end
                end

                currentCheckpoint = currentCheckpoint + 1
                spawnNextCheckpoint()
            end
        end
    end
end)

-- Respawn
Citizen.CreateThread(function()
    while true do
        Wait(0)
        local ped = PlayerPedId()
        local now = GetGameTimer()
        local canRespawn = now >= nextRespawnAllowedAt

        if raceStarted and lastCheckpointPos and canRespawn and IsDisabledControlPressed(0, RESPAWN_KEY) then
            DisableControlAction(0, RESPAWN_KEY, true)
            respawnHoldTime = math.min(respawnHoldTime + GetFrameTime(), RESPAWN_DURATION)
            if respawnHoldTime >= RESPAWN_DURATION then
                respawnPlayerAtLastCheckpoint(false)
            end
        else
            respawnHoldTime = 0.0
        end
    end
end)

-- Auto-respawn when player dies during a race.
Citizen.CreateThread(function()
    while true do
        Wait(0)

        local ped = PlayerPedId()
        if raceStarted and lastCheckpointPos and DoesEntityExist(ped) then
            if IsEntityDead(ped) then
                if not deathRespawnTriggered and GetGameTimer() >= nextRespawnAllowedAt then
                    deathRespawnTriggered = true
                    respawnHoldTime = 0.0
                    respawnPlayerAtLastCheckpoint(true)
                end
            else
                deathRespawnTriggered = false
            end
        else
            deathRespawnTriggered = false
        end
    end
end)

-- Receive leaderboard updates from server
RegisterNetEvent('race:leaderboardUpdate')
AddEventHandler('race:leaderboardUpdate', function(leaderboardData)
    serverLeaderboard = leaderboardData or {}
end)

-- Send player checkpoint progress with distance to next checkpoint
Citizen.CreateThread(function()
    while true do
        Wait(500)  -- Update every 500ms
        if raceStarted and #checkpoints > 0 then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            
            if veh ~= 0 and DoesEntityExist(veh) then
                local vehPos = GetEntityCoords(veh)
                local distToNext = 999999
                
                -- Calculate distance to next checkpoint
                if currentCheckpoint <= #checkpoints then
                    local nextCp = checkpoints[currentCheckpoint]
                    if nextCp then
                        distToNext = GetDistanceBetweenCoords(vehPos.x, vehPos.y, vehPos.z, nextCp.x, nextCp.y, nextCp.z)
                    end
                end
                
                -- Send to server with distance
                TriggerServerEvent('race:updatePlayerCheckpoint', currentCheckpoint, distToNext)
            end
        end
    end
end)

-- Checkpoint display update thread
Citizen.CreateThread(function()
    while true do
        Wait(100)
        if raceStarted and not IsPauseMenuActive() and not isRaceExcluded then
            local total = #checkpoints
            local showIndex = total > 0 and math.min(currentCheckpoint, total) or 0
            local cpDisplay = string.format("%d-%d", showIndex, total)
            
            SendNuiMessage(json.encode({
                type = 'checkpoint',
                show = true,
                current = showIndex,
                total = total,
                display = cpDisplay
            }))
            
            SendNuiMessage(json.encode({
                type = 'leaderboard',
                show = true
            }))
            
            -- Send server-provided leaderboard directly (both players visible)
            SendNuiMessage(json.encode({
                type = 'player-leaderboard',
                show = true,
                players = serverLeaderboard
            }))
        else
            SendNuiMessage(json.encode({
                type = 'checkpoint',
                show = false
            }))
            
            SendNuiMessage(json.encode({
                type = 'leaderboard',
                show = false
            }))
            
            SendNuiMessage(json.encode({
                type = 'player-leaderboard',
                show = false
            }))
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        setPropPlacerActive(false)
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        xmlPasteUiOpen = false
        clearEntityList(placedProps)
        clearEntityList(raceSpawnedProps)
        SetTextChatEnabled(true)
    end
end)

-- End race
RegisterNetEvent('race:endRace')
AddEventHandler('race:endRace', function()
    raceStarted = false
    StopGhostLoop()
    countdownLocked = false
    raceTimerStart = 0
    currentRaceVehicle = nil
    lastCheckpointTransformVehicle = nil
    
    safeDeleteCheckpoint(activeCP)
    safeDeleteCheckpoint(nextPreviewCP)
    safeRemoveBlip(activeBlip)
    safeRemoveBlip(previewBlip)
    for _, v in ipairs(raceVehicles) do
        if DoesEntityExist(v) then
            local pedSeat = GetPedInVehicleSeat(v, -1)
            if pedSeat == PlayerPedId() then TaskLeaveVehicle(pedSeat,v,0) end
            DeleteVehicle(v)
        end
    end
    raceVehicles = {}
    checkpoints = {}
    currentCheckpoint = 1
    playerCheckpoints = {}
    raceFinishReported = false
    lastCheckpointPos = nil
    lastCheckpointType = "normal"
    lastCheckpointTransformVehicle = nil
    respawnHoldTime = 0.0
    nextRespawnAllowedAt = 0
    deathRespawnTriggered = false
    clearEntityList(raceSpawnedProps)
end)

-- Handle Rockstar UGC import result
RegisterNetEvent('race:client:importResult')
AddEventHandler('race:client:importResult', function(result)
    if not result or type(result) ~= "table" then
        return
    end
    
    if not result.success then
        TriggerEvent('chat:addMessage', { args = { "^1ERROR", result.error or "Unknown error" } })
        return
    end
    
    -- Success: show notification
    local message = string.format("^2Imported: %s — %d checkpoints. Builder is ready.", 
        result.name or "Unknown", result.checkpointCount or 0)
    TriggerEvent('chat:addMessage', { args = { "^2IMPORT", message } })
end)

-- Handle Rockstar import menu selection
RegisterNetEvent('racebuilder:importRockstar')
AddEventHandler('racebuilder:importRockstar', function()
    AddTextEntry("ROCKSTAR_IMPORT_INPUT", "Enter Rockstar Job ID (e.g., tYHL3jKh50a0JKr273ajrw)")
    DisplayOnscreenKeyboard(1, "ROCKSTAR_IMPORT_INPUT", "", "", "", "", "", 64)
    
    Wait(500) -- Give keyboard time to appear
    
    local waitingForInput = true
    local maxWaitTime = GetGameTimer() + 120000 -- 120 second timeout (plenty of time to type)
    
    while waitingForInput do
        Wait(0)
        
        -- Check for timeout
        if GetGameTimer() > maxWaitTime then
            TriggerEvent('chat:addMessage', { args = { '^1ERROR', 'Input timeout.' } })
            return
        end
        
        local inputStatus = UpdateOnscreenKeyboard()
        
        if inputStatus == 1 then
            -- User confirmed input
            local jobId = GetOnscreenKeyboardResult()
            waitingForInput = false
            
            TriggerEvent('chat:addMessage', { args = { '^3BUILDER', 'Job ID received: ' .. jobId } })
            
            if not jobId or jobId == "" then
                TriggerEvent('chat:addMessage', { args = { '^3BUILDER', 'Import cancelled.' } })
                return
            end
            
            -- Validate Job ID format
            if not string.match(jobId, "^[a-zA-Z0-9_-]+$") then
                TriggerEvent('chat:addMessage', { args = { '^1ERROR', 'Invalid Job ID format.' } })
                return
            end
            
            -- Construct base fetch URL
            local baseUrl = "https://prod.cloud.rockstargames.com/ugc/gta5mission/" .. jobId
            
            TriggerEvent('chat:addMessage', { args = { '^3BUILDER', 'Fetching Job ID: ' .. jobId } })
            
            -- Fire server event with base URL
            TriggerServerEvent("race:server:importUGC", baseUrl)
            
            -- Show notification
            TriggerEvent('chat:addMessage', { args = { '^3BUILDER', 'Fetching race from Rockstar, please wait...' } })
        elseif inputStatus == 2 or inputStatus == -1 then
            -- User cancelled or input timed out
            waitingForInput = false
            if inputStatus == -1 then
                TriggerEvent('chat:addMessage', { args = { '^1ERROR', 'Keyboard input timeout - please try again.' } })
            else
                TriggerEvent('chat:addMessage', { args = { '^3BUILDER', 'Import cancelled.' } })
            end
        end
    end
end)

local ghostTimer = 0
local ghostLoopActive = false

function EnableGhostMode(seconds)
    ghostTimer = GetGameTimer() + (seconds * 1000)
    
    if not LocalPlayer.state.isGhosted then
        LocalPlayer.state:set("isGhosted", true, true)
    end
end

local ghostTimer = 0
local ghostLoopActive = false

function EnableGhostMode(seconds)
    ghostTimer = GetGameTimer() + (seconds * 1000)
    
    if not LocalPlayer.state.isGhosted then
        LocalPlayer.state:set("isGhosted", true, true)
    end
end

function StartGhostLoop()
    if ghostLoopActive then return end
    ghostLoopActive = true
    
    Citizen.CreateThread(function()
        while ghostLoopActive do
            Citizen.Wait(0)
            
            local now = GetGameTimer()
            local amIGhosted = LocalPlayer.state.isGhosted == true
            
            -- Check if my timer expired
            if amIGhosted and now >= ghostTimer then
                LocalPlayer.state:set("isGhosted", false, true)
                amIGhosted = false
            end
            
            local ped = PlayerPedId()
            local myVeh = GetVehiclePedIsIn(ped, false)
            
            -- Handle my own opacity
            if myVeh and myVeh ~= 0 then
                if amIGhosted then
                    if GetEntityAlpha(myVeh) ~= 100 then SetEntityAlpha(myVeh, 100, false) end
                else
                    if GetEntityAlpha(myVeh) ~= 255 then ResetEntityAlpha(myVeh) end
                end
            end
            
            -- Handle other players' opacity and collisions
            for _, player in ipairs(GetActivePlayers()) do
                if player ~= PlayerId() then
                    local otherPed = GetPlayerPed(player)
                    local otherVeh = GetVehiclePedIsIn(otherPed, false)
                    
                    if otherVeh and otherVeh ~= 0 then
                        local otherServerId = GetPlayerServerId(player)
                        local isOtherGhosted = false
                        
                        if Player(otherServerId).state then
                            isOtherGhosted = Player(otherServerId).state.isGhosted == true
                        end
                        
                        -- Apply low opacity to them
                        if isOtherGhosted then
                            if GetEntityAlpha(otherVeh) ~= 100 then SetEntityAlpha(otherVeh, 100, false) end
                        else
                            if GetEntityAlpha(otherVeh) ~= 255 then ResetEntityAlpha(otherVeh) end
                        end
                        
                        -- Disable collision if either player is ghosted
                        if (amIGhosted or isOtherGhosted) and myVeh and myVeh ~= 0 then
                            -- THIS IS THE FIX: Set to 'true' so it only disables collision per-frame
                            SetEntityNoCollisionEntity(myVeh, otherVeh, true)
                        end
                    end
                end
            end
        end
    end)
end

function StopGhostLoop()
    ghostLoopActive = false
    LocalPlayer.state:set("isGhosted", false, true)
    
    local ped = PlayerPedId()
    local myVeh = GetVehiclePedIsIn(ped, false)
    if myVeh and myVeh ~= 0 then ResetEntityAlpha(myVeh) end
    
    for _, player in ipairs(GetActivePlayers()) do
        local otherPed = GetPlayerPed(player)
        local otherVeh = GetVehiclePedIsIn(otherPed, false)
        if otherVeh and otherVeh ~= 0 then ResetEntityAlpha(otherVeh) end
    end
end