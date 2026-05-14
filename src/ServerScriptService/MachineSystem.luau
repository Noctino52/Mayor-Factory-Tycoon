local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ConveyorSystem = require(game.ServerScriptService.ConveyorSystem)
local Definitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Definitions"))

local MachineSystem = {}

local activeMachines = {}
local initialized = false

local function machineKey(cellX, cellZ)
    return tostring(cellX) .. "_" .. tostring(cellZ)
end

local function normalizeRotation(rotation)
    return math.floor(tonumber(rotation) or 0) % 4
end

local function getDirectionForRotation(rotation)
    rotation = normalizeRotation(rotation)

    if rotation == 1 then
        return 0, 1
    elseif rotation == 2 then
        return -1, 0
    elseif rotation == 3 then
        return 0, -1
    end

    return 1, 0
end

local function getOutputCell(machine)
    local instance = machine.instance
    local cellX = instance and instance.Parent and instance:GetAttribute("CellX") or machine.cellX
    local cellZ = instance and instance.Parent and instance:GetAttribute("CellZ") or machine.cellZ
    if cellX == nil or cellZ == nil then
        return nil, nil
    end

    local rotation = instance and instance.Parent and instance:GetAttribute("Rotation") or machine.rotation
    local dx, dz = getDirectionForRotation(rotation)
    local cellsX = instance and instance.Parent and instance:GetAttribute("CellsX") or machine.cellsX or 1
    local cellsZ = instance and instance.Parent and instance:GetAttribute("CellsZ") or machine.cellsZ or 1

    if dx > 0 then
        return cellX + cellsX, cellZ
    elseif dx < 0 then
        return cellX - 1, cellZ
    elseif dz > 0 then
        return cellX, cellZ + cellsZ
    end

    return cellX, cellZ - 1
end

local function updateMachineProduction(player, machine, now)
    if not machine.isPowered then
        return
    end

    if machine.instance and not machine.instance.Parent then
        MachineSystem.UnregisterMachine(player, machine.cellX, machine.cellZ)
        return
    end

    if machine.retryAt and now < machine.retryAt then
        return
    end

    local machineData = Definitions.GetMachine(machine.name)
    if not machineData or machineData.type ~= "producer" then
        return
    end

    local outputFrequency = machineData.outputFrequency or 5
    machine.productionProgress = math.clamp((now - machine.lastProducedTime) / outputFrequency, 0, 1)

    if now - machine.lastProducedTime < outputFrequency then
        return
    end

    local outputCellX, outputCellZ = getOutputCell(machine)
    if outputCellX == nil or outputCellZ == nil then
        machine.lastProducedTime = now
        machine.productionProgress = 0
        return
    end

    local spawned, message = ConveyorSystem.SpawnProductionItem(player, machineData.outputItem, outputCellX, outputCellZ)
    if spawned then
        machine.lastProducedTime = now
        machine.productionProgress = 0
        machine.retryAt = nil
    elseif message == "Conveyor cell is full" then
        machine.retryAt = now + 0.5
    else
        machine.lastProducedTime = now
        machine.productionProgress = 0
        machine.retryAt = nil
    end
end

function MachineSystem.RegisterMachine(player, cellX, cellZ, machineName, instance)
    if not player or not player.Parent then
        return false
    end

    local machineData = Definitions.GetMachine(machineName)
    if not machineData or machineData.type ~= "producer" then
        return false
    end

    cellX = math.floor(tonumber(cellX) or 0)
    cellZ = math.floor(tonumber(cellZ) or 0)

    if not activeMachines[player] then
        activeMachines[player] = {}
    end

    activeMachines[player][machineKey(cellX, cellZ)] = {
        name = machineName,
        cellX = cellX,
        cellZ = cellZ,
        cellsX = instance and instance:GetAttribute("CellsX") or 1,
        cellsZ = instance and instance:GetAttribute("CellsZ") or 1,
        rotation = instance and instance:GetAttribute("Rotation") or 0,
        instance = instance,
        lastProducedTime = tick(),
        productionProgress = 0,
        isPowered = true,
    }

    return true
end

function MachineSystem.UnregisterMachine(player, cellX, cellZ)
    local machines = activeMachines[player]
    if not machines then
        return
    end

    machines[machineKey(cellX, cellZ)] = nil

    if next(machines) == nil then
        activeMachines[player] = nil
    end
end

function MachineSystem.RegisterPlacedItem(player, item)
    if not item or not item.Parent then
        return false
    end

    local itemName = item:GetAttribute("ItemName")
    local cellX = item:GetAttribute("CellX")
    local cellZ = item:GetAttribute("CellZ")
    if cellX == nil or cellZ == nil then
        return false
    end

    return MachineSystem.RegisterMachine(player, cellX, cellZ, itemName, item)
end

function MachineSystem.UnregisterPlacedItem(player, item)
    if not item then
        return
    end

    local cellX = item:GetAttribute("CellX")
    local cellZ = item:GetAttribute("CellZ")
    if cellX == nil or cellZ == nil then
        return
    end

    MachineSystem.UnregisterMachine(player, cellX, cellZ)
end

function MachineSystem.RegisterPlayerMachines(player, placedItems)
    for _, item in ipairs(placedItems or {}) do
        MachineSystem.RegisterPlacedItem(player, item)
    end
end

function MachineSystem.ClearPlayer(player)
    activeMachines[player] = nil
end

function MachineSystem.GetActiveMachineCount(player)
    local count = 0

    if player then
        for _ in pairs(activeMachines[player] or {}) do
            count += 1
        end
        return count
    end

    for _, machines in pairs(activeMachines) do
        for _ in pairs(machines) do
            count += 1
        end
    end

    return count
end

function MachineSystem.Initialize()
    if initialized then
        return
    end

    initialized = true

    RunService.Heartbeat:Connect(function()
        local now = tick()

        for player, machines in pairs(activeMachines) do
            if not player.Parent then
                activeMachines[player] = nil
            else
                for _, machine in pairs(machines) do
                    updateMachineProduction(player, machine, now)
                end
            end
        end
    end)

    Players.PlayerRemoving:Connect(function(player)
        MachineSystem.ClearPlayer(player)
    end)
end

return MachineSystem
