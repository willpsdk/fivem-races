-- server.lua

-- Races database
local races = {
    ["downtown_dash"] = {
        name = "Downtown Dash",
        vehicle = "adder",
        startGrid = {
            vector4(3934.07, -4695.64, 4.19, 306.52),
            vector4(3935.69, -4701.87, 4.19, 292.63),
            vector4(3931.56, -4689.58, 4.18, 292.80),
            vector4(3939.37, -4693.50, 4.18, 286.44)
        },
        checkpoints = {
            vector4(4011.82, -4670.64, 4.18, 291.44),
            vector4(4103.84, -4637.02, 4.18, 290.39),
            vector4(4299.76, -4565.44, 4.18, 288.64),
            vector4(4548.85, -4485.32, 3.26, 285.49),
            vector4(4557.47, -4483.16, 3.26, 107.06) -- Last checkpoint
        }
    },
    ["desert_sprint"] = {
        name = "Desert Sprint",
        vehicle = "zentorno",
        startGrid = {
            vector4(1200.0, 3000.0, 40.0, 0.0),
            vector4(1205.0, 3000.0, 40.0, 0.0),
            vector4(1210.0, 3000.0, 40.0, 0.0)
        },
        checkpoints = {
            vector4(1300.0, 3100.0, 40.0, 0.0),
            vector4(1400.0, 3200.0, 40.0, 0.0),
            vector4(1500.0, 3300.0, 40.0, 0.0)
        }
    }
}

local activeRace = nil
local raceParticipants = {}

-- List all races
RegisterCommand("races", function(source)
    local msg = "Available Races: "
    for id, race in pairs(races) do
        msg = msg .. id .. " (" .. race.name .. ") | "
    end
    TriggerClientEvent('chat:addMessage', source, { args = { msg } })
end)

-- Start a race
RegisterCommand("race", function(source, args)
    local raceId = args[1]
    if not raceId or not races[raceId] then
        TriggerClientEvent('chat:addMessage', source, { args = { "Race not found!" } })
        return
    end

    activeRace = raceId
    raceParticipants = {}

    local players = GetPlayers()
    local startGrid = races[raceId].startGrid

    -- Assign players to start positions
    for i, playerId in ipairs(players) do
        local pos = startGrid[((i-1) % #startGrid)+1]
        table.insert(raceParticipants, playerId)
        TriggerClientEvent('race:tpClient', playerId, pos, pos.w, races[raceId].vehicle, races[raceId].name)
    end

    -- Send checkpoints to all
    for _, playerId in ipairs(players) do
        TriggerClientEvent('race:startCheckpoints', playerId, races[raceId].checkpoints)
    end

    -- Start countdown
    for _, playerId in ipairs(players) do
        TriggerClientEvent('race:startCountdown', playerId)
    end

end)

-- End race
RegisterCommand("endrace", function(source)
    if not activeRace then
        TriggerClientEvent('chat:addMessage', source, { args = { "No active race!" } })
        return
    end

    for _, playerId in ipairs(raceParticipants) do
        TriggerClientEvent('race:endRace', playerId)
    end
    activeRace = nil
    raceParticipants = {}
end)
