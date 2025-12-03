-- client.lua

-- Config
local CHECKPOINT_Z_OFFSET = -5.0  -- Z offset for checkpoints
local RESPAWN_KEY = 246           -- Y key
local RESPAWN_DURATION = 2.5      -- seconds
local CHECKPOINT_STYLE = 1        -- Standard GTA Online checkpoint

-- State
local raceStarted = false
local raceName = "Default Race"
local defaultVehicle = "adder"

local checkpoints = {}
local currentCheckpoint = 1
local activeCP, nextPreviewCP = nil, nil
local activeBlip, previewBlip = nil, nil
local lastCheckpointPos = nil
local respawnHoldTime = 0.0
local raceVehicles = {}

-- Helpers
local function safeDeleteCheckpoint(cp) if cp then DeleteCheckpoint(cp) end end
local function safeRemoveBlip(b) if b and DoesBlipExist(b) then RemoveBlip(b) end end

local function spawnAndWarpVehicle(modelName, coords, heading)
    local ped = PlayerPedId()
    local model = GetHashKey(modelName)
    RequestModel(model)
    local t0 = GetGameTimer()
    while not HasModelLoaded(model) and (GetGameTimer()-t0)<5000 do Wait(0) end
    if not HasModelLoaded(model) then return nil end

    local veh = CreateVehicle(model, coords.x, coords.y, coords.z + 1, heading or 0.0, true, false)
    if DoesEntityExist(veh) then
        TaskWarpPedIntoVehicle(ped, veh, -1)
        SetVehicleDoorsLocked(veh, 2)
        FreezeEntityPosition(veh, true)
        return veh
    end
    return nil
end

local function spawnNextCheckpoint()
    safeDeleteCheckpoint(activeCP); safeDeleteCheckpoint(nextPreviewCP)
    safeRemoveBlip(activeBlip); safeRemoveBlip(previewBlip)

    if currentCheckpoint > #checkpoints then return end

    local pos = checkpoints[currentCheckpoint]
    if not pos then return end

    local style = CHECKPOINT_STYLE
    if currentCheckpoint == #checkpoints then
        style = 4  -- Last checkpoint uses Standard Checkpoint 4
    end

    -- Active checkpoint
    activeCP = CreateCheckpoint(style,
        pos.x, pos.y, pos.z + CHECKPOINT_Z_OFFSET,
        pos.x, pos.y, pos.z + CHECKPOINT_Z_OFFSET,
        9.0, 255, 255, 255, 255, 0
    )

    activeBlip = AddBlipForCoord(pos.x, pos.y, pos.z)
    SetBlipSprite(activeBlip, 1)
    SetBlipColour(activeBlip, 5)
    SetBlipScale(activeBlip, 0.9)
    SetBlipRoute(activeBlip, true)
    SetBlipRouteColour(activeBlip, 5)

    -- Preview checkpoint
    local nextIdx = currentCheckpoint + 1
    if nextIdx <= #checkpoints then
        local np = checkpoints[nextIdx]
        nextPreviewCP = CreateCheckpoint(CHECKPOINT_STYLE,
            np.x, np.y, np.z + CHECKPOINT_Z_OFFSET,
            np.x, np.y, np.z + CHECKPOINT_Z_OFFSET,
            6.0, 255, 255, 255, 128, 0
        )

        previewBlip = AddBlipForCoord(np.x, np.y, np.z)
        SetBlipSprite(previewBlip, 1)
        SetBlipColour(previewBlip, 5)
        SetBlipScale(previewBlip, 0.7)
        SetBlipAlpha(previewBlip, 128)
    end
end

-- Events
RegisterNetEvent('race:tpClient')
AddEventHandler('race:tpClient', function(coords, heading, vehicleModel, name)
    raceName = name or raceName
    defaultVehicle = vehicleModel or defaultVehicle

    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z + 1, false, false, false, true)
    SetEntityHeading(ped, heading or coords.w or 0.0)

    local veh = spawnAndWarpVehicle(defaultVehicle, coords, heading or coords.w)
    if veh then table.insert(raceVehicles, veh) end

    lastCheckpointPos = {x=coords.x, y=coords.y, z=coords.z, w=coords.w or 0.0}
end)

RegisterNetEvent('race:startCountdown')
AddEventHandler('race:startCountdown', function()
    if raceStarted then return end
    raceStarted = true

    for i=5,1,-1 do
        BeginTextCommandPrint("STRING")
        AddTextComponentSubstringPlayerName(tostring(i))
        EndTextCommandPrint(1000, true)
        PlaySoundFrontend(-1, "5_SEC_WARNING", "HUD_MINI_GAME_SOUNDSET", true)
        Wait(1000)
    end

    BeginTextCommandPrint("STRING")
    AddTextComponentSubstringPlayerName("GO!")
    EndTextCommandPrint(1000, true)
    PlaySoundFrontend(-1, "GO", "HUD_MINI_GAME_SOUNDSET", true)

    for _, veh in ipairs(raceVehicles) do
        if DoesEntityExist(veh) then
            FreezeEntityPosition(veh, false)
            SetVehicleDoorsLocked(veh, 2)
        end
    end
end)

RegisterNetEvent('race:startCheckpoints')
AddEventHandler('race:startCheckpoints', function(list)
    checkpoints = list
    currentCheckpoint = 1
    spawnNextCheckpoint()
end)

-- Prevent exiting vehicle completely
Citizen.CreateThread(function()
    while true do
        Wait(0)
        if raceStarted then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 then
                -- Lock doors
                SetVehicleDoorsLocked(veh, 2)
                -- Prevent exiting
                DisableControlAction(0, 75, true) -- INPUT_VEH_EXIT
            end
        end
    end
end)

-- Checkpoint detection
Citizen.CreateThread(function()
    while true do
        Wait(0)
        if currentCheckpoint <= #checkpoints then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local cp = checkpoints[currentCheckpoint]
            if cp and #(pos - vector3(cp.x, cp.y, cp.z)) < 12.0 then
                PlaySoundFrontend(-1, "CHECKPOINT_NORMAL", "HUD_MINI_GAME_SOUNDSET", true)
                safeDeleteCheckpoint(activeCP)
                safeRemoveBlip(activeBlip)

                lastCheckpointPos = {x=cp.x, y=cp.y, z=cp.z, w=cp.w or 0.0}

                if currentCheckpoint == #checkpoints then
                    local veh = GetVehiclePedIsIn(ped, false)
                    if veh ~= 0 and DoesEntityExist(veh) then DeleteVehicle(veh) end
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
        if IsControlPressed(0, RESPAWN_KEY) and lastCheckpointPos then
            respawnHoldTime = math.min(respawnHoldTime + 0.01, RESPAWN_DURATION)
            if respawnHoldTime >= RESPAWN_DURATION then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh ~= 0 and DoesEntityExist(veh) then DeleteVehicle(veh) end

                SetEntityCoords(ped, lastCheckpointPos.x, lastCheckpointPos.y, lastCheckpointPos.z + 1, false, false, false, true)
                SetEntityHeading(ped, lastCheckpointPos.w or 0.0)

                local model = GetHashKey(defaultVehicle)
                RequestModel(model)
                local t0 = GetGameTimer()
                while not HasModelLoaded(model) and (GetGameTimer()-t0)<5000 do Wait(0) end
                if HasModelLoaded(model) then
                    local newVeh = CreateVehicle(model, lastCheckpointPos.x, lastCheckpointPos.y, lastCheckpointPos.z, lastCheckpointPos.w or 0.0, true, false)
                    if DoesEntityExist(newVeh) then
                        TaskWarpPedIntoVehicle(ped, newVeh, -1)
                        SetVehicleDoorsLocked(newVeh, 2)
                        table.insert(raceVehicles, newVeh)
                    end
                end
                respawnHoldTime = 0.0
            end
        else
            respawnHoldTime = 0.0
        end
    end
end)

-- Respawn progress bar
Citizen.CreateThread(function()
    while true do
        Wait(0)
        if respawnHoldTime > 0.0 then
            local progress = respawnHoldTime / RESPAWN_DURATION
            local w,h = 0.32,0.02
            local x,y = 0.5 - w/2, 0.75
            DrawRect(x + w/2, y + h/2, w, h, 40,40,40,200)
            DrawRect(x + (w*progress)/2, y + h/2, w*progress, h, 255,220,0,255)
        end
    end
end)

-- Bottom-right checkpoint tracker
Citizen.CreateThread(function()
    while true do
        Wait(0)
        if raceStarted then
            local showIndex = math.min(currentCheckpoint, #checkpoints)
            local display = string.format("Checkpoint %d / %d", showIndex, #checkpoints)
            SetTextFont(0)
            SetTextProportional(1)
            SetTextScale(0.4,0.4)
            SetTextColour(255,255,0,255)
            SetTextOutline()
            SetTextRightJustify(true)
            BeginTextCommandDisplayText("STRING")
            AddTextComponentSubstringPlayerName(display)
            EndTextCommandDisplayText(0.95, 0.95)
        end
    end
end)

-- End race
RegisterNetEvent('race:endRace')
AddEventHandler('race:endRace', function()
    raceStarted = false
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
    lastCheckpointPos = nil
    respawnHoldTime = 0.0
end)
