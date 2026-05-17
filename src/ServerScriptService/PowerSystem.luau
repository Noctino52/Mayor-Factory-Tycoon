local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Definitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Definitions"))
local PlayerProgress = require(game.ServerScriptService.PlayerProgress)

local PowerSystem = {}

local playerItems = {}
local nextRegistrationOrder = 0

local REFRESH_INTERVAL = 1

local function getItemName(item)
    if not item then
        return nil
    end

    return item:GetAttribute("ItemName")
end

local function getMachinePowerRequired(itemName)
    local machineData = itemName and Definitions.GetMachine(itemName)
    local powerRequired = machineData and tonumber(machineData.powerRequired) or 0

    return math.max(0, powerRequired)
end

local function getGeneratorPowerProvided(itemName)
    local itemDef = itemName and Definitions.GetItem(itemName)
    if not itemDef or itemDef.type ~= "generator" then
        return 0
    end

    return math.max(0, tonumber(itemDef.powerProvided) or 0)
end

local function getRegistry(player)
    local registry = playerItems[player]
    if not registry then
        registry = {}
        playerItems[player] = registry
    end

    return registry
end

local function cleanupRegistry(player)
    local registry = playerItems[player]
    if not registry then
        return {}
    end

    for index = #registry, 1, -1 do
        local entry = registry[index]
        if not entry.item or not entry.item.Parent then
            table.remove(registry, index)
        end
    end

    if #registry <= 0 then
        playerItems[player] = nil
        return {}
    end

    return registry
end

local function setPlayerPowerAttributes(player, status)
    if not player or not player.Parent then
        return
    end

    player:SetAttribute("PowerUsed", status.used)
    player:SetAttribute("PowerCapacity", status.capacity)
    player:SetAttribute("PowerAvailable", status.available)
end

local function findRegisteredItem(registry, item)
    for index, entry in ipairs(registry) do
        if entry.item == item then
            return index, entry
        end
    end

    return nil, nil
end

local function compareConsumerOrder(a, b)
    if a.order == b.order then
        return tostring(a.item) < tostring(b.item)
    end

    return a.order < b.order
end

local function getTotalPowerDemand(player)
    local total = 0

    for _, entry in ipairs(cleanupRegistry(player)) do
        total += getMachinePowerRequired(getItemName(entry.item))
    end

    return total
end

local function calculatePowerStatus(player)
    local registry = cleanupRegistry(player)
    local capacity = PowerSystem.GetBaseCapacity(player)
    local consumers = {}

    for _, entry in ipairs(registry) do
        local item = entry.item
        local itemName = getItemName(item)
        local powerProvided = getGeneratorPowerProvided(itemName)
        capacity += powerProvided

        entry.itemName = itemName
        entry.powerProvided = powerProvided
        entry.powerRequired = getMachinePowerRequired(itemName)

        item:SetAttribute("PowerProvided", powerProvided)
        item:SetAttribute("PowerRequired", entry.powerRequired)

        if entry.powerRequired > 0 then
            table.insert(consumers, entry)
        elseif powerProvided > 0 then
            item:SetAttribute("IsPowered", true)
        else
            item:SetAttribute("IsPowered", nil)
        end
    end

    table.sort(consumers, compareConsumerOrder)

    local used = 0
    for _, entry in ipairs(consumers) do
        local item = entry.item
        local hasCapacity = used + entry.powerRequired <= capacity

        if hasCapacity then
            used += entry.powerRequired
        end

        item:SetAttribute("IsPowered", hasCapacity)
    end

    local status = {
        used = used,
        capacity = capacity,
        available = math.max(0, capacity - used),
    }

    setPlayerPowerAttributes(player, status)

    return status
end

function PowerSystem.GetBaseCapacity(player)
    if not player then
        return 0
    end

    local progress = PlayerProgress.GetPlayerProgress(player)
    local townPrestige = progress.townPrestige or {}
    local stageInfo = PlayerProgress.GetTownPrestigeStageInfo(townPrestige.stage)
    local rewards = stageInfo and stageInfo.rewards or {}

    return math.max(0, tonumber(rewards.powerCapacity) or 0)
end

function PowerSystem.GetGeneratorCapacity(player)
    local total = 0

    for _, entry in ipairs(cleanupRegistry(player)) do
        total += getGeneratorPowerProvided(getItemName(entry.item))
    end

    return total
end

function PowerSystem.GetPowerUsed(player)
    return calculatePowerStatus(player).used
end

function PowerSystem.GetPowerStatus(player)
    local status = calculatePowerStatus(player)

    return {
        used = status.used,
        capacity = status.capacity,
        available = status.available,
    }
end

function PowerSystem.CanPlaceMachine(player, itemName)
    local powerRequired = getMachinePowerRequired(itemName)
    if powerRequired <= 0 then
        return true, nil
    end

    local capacity = PowerSystem.GetBaseCapacity(player) + PowerSystem.GetGeneratorCapacity(player)
    if getTotalPowerDemand(player) + powerRequired > capacity then
        return false, "Not enough Power"
    end

    return true, nil
end

function PowerSystem.RegisterPlacedItem(player, item)
    if not player or not item or not item.Parent then
        return false
    end

    local registry = getRegistry(player)
    local _, existingEntry = findRegisteredItem(registry, item)
    if existingEntry then
        calculatePowerStatus(player)
        return true
    end

    nextRegistrationOrder += 1
    table.insert(registry, {
        item = item,
        order = nextRegistrationOrder,
    })

    calculatePowerStatus(player)
    return true
end

function PowerSystem.UnregisterPlacedItem(player, item)
    local registry = playerItems[player]
    if not registry then
        return
    end

    local index = findRegisteredItem(registry, item)
    if index then
        table.remove(registry, index)
    end

    if item and item.Parent then
        item:SetAttribute("IsPowered", false)
        item:SetAttribute("PowerRequired", nil)
        item:SetAttribute("PowerProvided", nil)
    end

    calculatePowerStatus(player)
end

function PowerSystem.RefreshPlayer(player)
    return calculatePowerStatus(player)
end

function PowerSystem.ClearPlayer(player)
    playerItems[player] = nil

    if player and player.Parent then
        player:SetAttribute("PowerUsed", nil)
        player:SetAttribute("PowerCapacity", nil)
        player:SetAttribute("PowerAvailable", nil)
    end
end

Players.PlayerRemoving:Connect(function(player)
    PowerSystem.ClearPlayer(player)
end)

task.spawn(function()
    while true do
        task.wait(REFRESH_INTERVAL)

        for player in pairs(playerItems) do
            if player.Parent then
                calculatePowerStatus(player)
            else
                PowerSystem.ClearPlayer(player)
            end
        end
    end
end)

return PowerSystem
