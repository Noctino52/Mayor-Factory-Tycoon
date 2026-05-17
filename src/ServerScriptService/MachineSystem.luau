local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ConveyorSystem = require(game.ServerScriptService.ConveyorSystem)
local Definitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Definitions"))

local MachineSystem = {}

local activeMachines = {}
local initialized = false

local function isPlacedItemOwnedByPlayer(player, item)
    return player and item and item:GetAttribute("Owner") == player.UserId and item:GetAttribute("PlotId") ~= nil
end

local function doesProductionItemMatchMachine(player, machineInstance, productionItem)
    if not isPlacedItemOwnedByPlayer(player, machineInstance) then
        return false
    end

    if not productionItem or not productionItem.Parent then
        return false
    end

    return productionItem:GetAttribute("Owner") == player.UserId
        and productionItem:GetAttribute("PlotId") == machineInstance:GetAttribute("PlotId")
end

local function validateMachineDefinitions()
    local outputsByItem = {}

    for machineName, machineData in pairs(Definitions.MACHINES) do
        if not Definitions.GetItem(machineName) then
            error("[MachineSystem] Machine " .. tostring(machineName) .. " has no placeable item definition")
        end

        if machineData.type == "processor" and not Definitions.IsProduction(machineData.inputItem) then
            error("[MachineSystem] Processor " .. tostring(machineName) .. " has invalid input item: " .. tostring(machineData.inputItem))
        end

        if machineData.outputItem then
            if not Definitions.IsProduction(machineData.outputItem) then
                error("[MachineSystem] Machine " .. tostring(machineName) .. " has invalid output item: " .. tostring(machineData.outputItem))
            end

            local existingMachine = outputsByItem[machineData.outputItem]
            if existingMachine then
                error("[MachineSystem] Output item " .. tostring(machineData.outputItem) .. " is produced by both " .. tostring(existingMachine) .. " and " .. tostring(machineName))
            end

            outputsByItem[machineData.outputItem] = machineName
        end
    end
end

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

local function getFirstBasePart(instance)
    if instance:IsA("BasePart") then
        return instance
    end

    if instance:IsA("Model") and instance.PrimaryPart then
        return instance.PrimaryPart
    end

    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return descendant
        end
    end

    return nil
end

local function getOutputCell(machine)
    local instance = machine.instance
    local cellX = instance and instance.Parent and instance:GetAttribute("CellX") or machine.cellX
    local cellZ = instance and instance.Parent and instance:GetAttribute("CellZ") or machine.cellZ
    if cellX == nil or cellZ == nil then
        return nil, nil
    end

    local rotation = instance and instance.Parent and instance:GetAttribute("Rotation") or machine.rotation
    local machineData = Definitions.GetMachine(machine.name)
    rotation = normalizeRotation(rotation + (machineData and machineData.outputRotationOffset or 0))
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

local function getRecipeInputCount(machineData)
    return machineData.inputCount or machineData.inputQuantity or machineData.inputRequired or 1
end

local function getNextProcessingItem(machine)
    local nextItem = nil

    for _, inputItem in ipairs(machine.inputQueue) do
        if not nextItem or inputItem.receivedAt < nextItem.receivedAt then
            nextItem = inputItem
        end
    end

    return nextItem
end

local function isInstancePowered(instance, machineData)
    local powerRequired = machineData and tonumber(machineData.powerRequired) or 0
    if powerRequired <= 0 then
        return true
    end

    if not instance or not instance.Parent then
        return false
    end

    return instance:GetAttribute("IsPowered") == true
end

local function getMachineForInstance(player, instance)
    if not instance then
        return nil
    end

    local cellX = instance:GetAttribute("CellX")
    local cellZ = instance:GetAttribute("CellZ")
    if cellX == nil or cellZ == nil then
        return nil
    end

    local key = machineKey(cellX, cellZ)
    local machines = activeMachines[player]
    if not machines or not machines[key] then
        MachineSystem.RegisterPlacedItem(player, instance)
        machines = activeMachines[player]
    end

    return machines and machines[key] or nil
end

local function updateProcessingVisual(machine)
    local instance = machine.instance
    if not instance or not instance.Parent or machine.type ~= "processor" then
        return
    end

    local adornee = getFirstBasePart(instance)
    if not adornee then
        return
    end

    local billboard = adornee:FindFirstChild("ProcessingStatus")
    if not billboard then
        billboard = Instance.new("BillboardGui")
        billboard.Name = "ProcessingStatus"
        billboard.Size = UDim2.fromOffset(150, 72)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = adornee

        local panel = Instance.new("Frame")
        panel.Name = "Panel"
        panel.Size = UDim2.fromScale(1, 1)
        panel.BackgroundTransparency = 0.25
        panel.BackgroundColor3 = Color3.fromRGB(18, 20, 22)
        panel.BorderSizePixel = 0
        panel.Parent = billboard

        local recipeLabel = Instance.new("TextLabel")
        recipeLabel.Name = "RecipeLabel"
        recipeLabel.Size = UDim2.new(1, -10, 0, 20)
        recipeLabel.Position = UDim2.fromOffset(5, 4)
        recipeLabel.BackgroundTransparency = 1
        recipeLabel.TextColor3 = Color3.fromRGB(245, 238, 220)
        recipeLabel.TextScaled = true
        recipeLabel.Font = Enum.Font.GothamBold
        recipeLabel.Parent = panel

        local queueLabel = Instance.new("TextLabel")
        queueLabel.Name = "QueueLabel"
        queueLabel.Size = UDim2.new(0.5, -6, 0, 18)
        queueLabel.Position = UDim2.fromOffset(5, 26)
        queueLabel.BackgroundTransparency = 1
        queueLabel.TextColor3 = Color3.fromRGB(210, 218, 225)
        queueLabel.TextScaled = true
        queueLabel.Font = Enum.Font.Gotham
        queueLabel.Parent = panel

        local timeLabel = Instance.new("TextLabel")
        timeLabel.Name = "TimeLabel"
        timeLabel.Size = UDim2.new(0.5, -6, 0, 18)
        timeLabel.Position = UDim2.new(0.5, 1, 0, 26)
        timeLabel.BackgroundTransparency = 1
        timeLabel.TextColor3 = Color3.fromRGB(170, 220, 255)
        timeLabel.TextScaled = true
        timeLabel.Font = Enum.Font.GothamBold
        timeLabel.Parent = panel

        local progressBack = Instance.new("Frame")
        progressBack.Name = "ProgressBack"
        progressBack.Size = UDim2.new(1, -10, 0, 8)
        progressBack.Position = UDim2.fromOffset(5, 55)
        progressBack.BackgroundColor3 = Color3.fromRGB(54, 58, 62)
        progressBack.BorderSizePixel = 0
        progressBack.Parent = panel

        local progressFill = Instance.new("Frame")
        progressFill.Name = "ProgressFill"
        progressFill.Size = UDim2.fromScale(0, 1)
        progressFill.BackgroundColor3 = Color3.fromRGB(92, 185, 255)
        progressFill.BorderSizePixel = 0
        progressFill.Parent = progressBack
    end

    local machineData = Definitions.GetMachine(machine.name)
    local inputItem = machineData and machineData.inputItem or "Input"
    local outputItem = machineData and machineData.outputItem or "Output"
    local recipeInputCount = machineData and getRecipeInputCount(machineData) or 1
    local receivedCount = math.min(#machine.inputQueue, recipeInputCount)
    local processingItem = getNextProcessingItem(machine)
    local processingTime = machineData and machineData.processingTime or 1
    local progress = 0
    local remaining = nil

    if processingItem then
        local elapsed = math.max(0, tick() - processingItem.receivedAt)
        progress = math.clamp(elapsed / processingTime, 0, 1)
        remaining = math.max(0, processingTime - elapsed)
    end

    local panel = billboard:FindFirstChild("Panel")
    if panel then
        local recipeLabel = panel:FindFirstChild("RecipeLabel")
        if recipeLabel and recipeLabel:IsA("TextLabel") then
            recipeLabel.Text = inputItem .. " " .. tostring(receivedCount) .. "/" .. tostring(recipeInputCount) .. " -> " .. outputItem
        end

        local queueLabel = panel:FindFirstChild("QueueLabel")
        if queueLabel and queueLabel:IsA("TextLabel") then
            queueLabel.Text = "Queue " .. tostring(#machine.inputQueue) .. "/" .. tostring(machine.inputQueueSize)
        end

        local timeLabel = panel:FindFirstChild("TimeLabel")
        if timeLabel and timeLabel:IsA("TextLabel") then
            timeLabel.Text = remaining and string.format("%.1fs", remaining) or "Ready"
        end

        local progressBack = panel:FindFirstChild("ProgressBack")
        local progressFill = progressBack and progressBack:FindFirstChild("ProgressFill")
        if progressFill and progressFill:IsA("Frame") then
            progressFill.Size = UDim2.fromScale(progress, 1)
        end
    end

    instance:SetAttribute("ProcessingCount", #machine.inputQueue)
    instance:SetAttribute("ProcessingCapacity", machine.inputQueueSize)
    instance:SetAttribute("ProcessingProgress", progress)
end

local function updateProducer(player, machine, machineData, now)
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

local function updateProcessor(player, machine, machineData, now)
    updateProcessingVisual(machine)

    if #machine.inputQueue <= 0 then
        return
    end

    for index = #machine.inputQueue, 1, -1 do
        local inputItem = machine.inputQueue[index]
        local processingTime = machineData.processingTime or 1

        if now - inputItem.receivedAt >= processingTime then
            local outputCellX, outputCellZ = getOutputCell(machine)
            if outputCellX == nil or outputCellZ == nil then
                machine.retryAt = now + 0.5
                return
            end

            local spawned, message = ConveyorSystem.SpawnProductionItem(player, machineData.outputItem, outputCellX, outputCellZ)
            if spawned then
                table.remove(machine.inputQueue, index)
                machine.retryAt = nil
                updateProcessingVisual(machine)
            elseif message == "Conveyor cell is full" then
                machine.retryAt = now + 0.5
                return
            else
                machine.retryAt = now + 0.5
                return
            end
        end
    end
end

local function updateMachineProduction(player, machine, now)
    if machine.instance and not machine.instance.Parent then
        MachineSystem.UnregisterMachine(player, machine.cellX, machine.cellZ)
        return
    end

    local machineData = Definitions.GetMachine(machine.name)
    if not machineData then
        return
    end

    machine.isPowered = isInstancePowered(machine.instance, machineData)
    if not machine.isPowered then
        machine.lastProducedTime = now
        machine.productionProgress = 0

        if machine.type == "processor" then
            for _, inputItem in ipairs(machine.inputQueue) do
                inputItem.receivedAt = now
            end
            updateProcessingVisual(machine)
        end

        return
    end

    if machine.retryAt and now < machine.retryAt then
        if machine.type == "processor" then
            updateProcessingVisual(machine)
        end
        return
    end

    if machine.type == "processor" then
        updateProcessor(player, machine, machineData, now)
    elseif machine.type == "producer" then
        updateProducer(player, machine, machineData, now)
    end
end

function MachineSystem.RegisterMachine(player, cellX, cellZ, machineName, instance)
    if not player or not player.Parent then
        return false
    end

    if instance and not isPlacedItemOwnedByPlayer(player, instance) then
        return false
    end

    local machineData = Definitions.GetMachine(machineName)
    if not machineData then
        return false
    end

    cellX = math.floor(tonumber(cellX) or 0)
    cellZ = math.floor(tonumber(cellZ) or 0)

    if not activeMachines[player] then
        activeMachines[player] = {}
    end

    local machine = {
        name = machineName,
        type = machineData.type,
        cellX = cellX,
        cellZ = cellZ,
        cellsX = instance and instance:GetAttribute("CellsX") or 1,
        cellsZ = instance and instance:GetAttribute("CellsZ") or 1,
        rotation = instance and instance:GetAttribute("Rotation") or 0,
        instance = instance,
        inputQueue = {},
        inputQueueSize = machineData.inputQueueSize or 0,
        lastProducedTime = tick(),
        productionProgress = 0,
        isPowered = isInstancePowered(instance, machineData),
    }

    if instance then
        instance:SetAttribute("PowerRequired", tonumber(machineData.powerRequired) or 0)
        if instance:GetAttribute("IsPowered") == nil then
            instance:SetAttribute("IsPowered", machine.isPowered)
        end
    end

    activeMachines[player][machineKey(cellX, cellZ)] = machine
    updateProcessingVisual(machine)

    return true
end

function MachineSystem.UnregisterMachine(player, cellX, cellZ)
    local machines = activeMachines[player]
    if not machines then
        return
    end

    local machine = machines[machineKey(cellX, cellZ)]
    if machine and machine.instance and machine.instance.Parent then
        local adornee = getFirstBasePart(machine.instance)
        local billboard = adornee and adornee:FindFirstChild("ProcessingStatus")
        if billboard then
            billboard:Destroy()
        end
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

    if not isPlacedItemOwnedByPlayer(player, item) then
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

function MachineSystem.FeedMachine(player, machineInstance, itemName, productionItem)
    local machine = getMachineForInstance(player, machineInstance)
    if not machine then
        return false, "Machine is not registered"
    end

    if not doesProductionItemMatchMachine(player, machineInstance, productionItem) then
        return false, "Invalid item ownership"
    end

    if productionItem:GetAttribute("ItemName") ~= itemName then
        return false, "Production item mismatch"
    end

    local machineData = Definitions.GetMachine(machine.name)
    if not machineData or machineData.type ~= "processor" then
        return false, "Machine does not accept input"
    end

    machine.isPowered = isInstancePowered(machine.instance, machineData)
    if not machine.isPowered then
        return false, "Machine is not powered"
    end

    if machineData.inputItem ~= itemName then
        return false, "Invalid input item"
    end

    if #machine.inputQueue >= machine.inputQueueSize then
        return false, "Machine input queue is full"
    end

    table.insert(machine.inputQueue, {
        itemName = itemName,
        receivedAt = tick(),
    })
    updateProcessingVisual(machine)

    return true
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

    validateMachineDefinitions()

    initialized = true
    ConveyorSystem.SetMachineInputHandler(MachineSystem.FeedMachine)

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
