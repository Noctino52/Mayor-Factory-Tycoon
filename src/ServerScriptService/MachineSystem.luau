local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ConveyorSystem = require(game.ServerScriptService.ConveyorSystem)
local PlotWorkers = require(game.ServerScriptService.PlotWorkers)
local Definitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Definitions"))

-- Same item models the conveyors use, so the piece a machine is working on
-- looks exactly like the item that went in and the one that comes out.
local productionItemModule = nil
do
    local starterScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
    local moduleScript = starterScripts and starterScripts:FindFirstChild("ProductionItems")
    if moduleScript and moduleScript:IsA("ModuleScript") then
        pcall(function()
            productionItemModule = require(moduleScript)
        end)
    end
end

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

local function hasEnoughInputForRecipe(machine, machineData)
    return #machine.inputQueue >= getRecipeInputCount(machineData)
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
    local billboard = adornee and adornee:FindFirstChild("ProcessingStatus")
    if billboard then
        billboard:Destroy()
    end

    local machineData = Definitions.GetMachine(machine.name)
    local inputItem = machineData and machineData.inputItem or "Input"
    local outputItem = machineData and machineData.outputItem or "Output"
    local recipeInputCount = machineData and getRecipeInputCount(machineData) or 1
    local receivedCount = math.min(#machine.inputQueue, recipeInputCount)
    local processingTime = machineData and machineData.processingTime or 1
    local progress = 0
    local remaining = nil

    if machineData and hasEnoughInputForRecipe(machine, machineData) and machine.processingStartedAt then
        local elapsed = math.max(0, tick() - machine.processingStartedAt)
        progress = math.clamp(elapsed / processingTime, 0, 1)
        remaining = math.max(0, processingTime - elapsed)
    end

    instance:SetAttribute("MachineType", "processor")
    instance:SetAttribute("MachineInputItem", inputItem)
    instance:SetAttribute("MachineOutputItem", outputItem)
    instance:SetAttribute("MachineRecipeReceived", receivedCount)
    instance:SetAttribute("MachineRecipeRequired", recipeInputCount)
    instance:SetAttribute("MachineQueueText", "Queue " .. tostring(#machine.inputQueue) .. "/" .. tostring(machine.inputQueueSize))
    instance:SetAttribute("MachineStatusText", remaining and string.format("%.1fs", remaining) or "Ready")
    instance:SetAttribute("ProcessingCount", #machine.inputQueue)
    instance:SetAttribute("ProcessingCapacity", machine.inputQueueSize)
    instance:SetAttribute("ProcessingProgress", progress)
end

local function updateProducerVisual(machine, machineData)
    local instance = machine.instance
    if not instance or not instance.Parent or machine.type ~= "producer" then
        return
    end

    local outputItem = machineData and machineData.outputItem or "Output"
    local progress = machine.productionProgress or 0

    instance:SetAttribute("MachineType", "producer")
    instance:SetAttribute("MachineInputItem", "")
    instance:SetAttribute("MachineOutputItem", outputItem)
    instance:SetAttribute("MachineRecipeReceived", 0)
    instance:SetAttribute("MachineRecipeRequired", 0)
    instance:SetAttribute("MachineQueueText", "")
    instance:SetAttribute("MachineStatusText", string.format("%d%%", math.floor(progress * 100 + 0.5)))
    instance:SetAttribute("ProcessingCount", 0)
    instance:SetAttribute("ProcessingCapacity", 0)
    instance:SetAttribute("ProcessingProgress", progress)
end

local function updateProducer(player, machine, machineData, now)
    local outputFrequency = machineData.outputFrequency or 5
    machine.productionProgress = math.clamp((now - machine.lastProducedTime) / outputFrequency, 0, 1)
    updateProducerVisual(machine, machineData)
    PlotWorkers.Update(machine, machineData, machine.productionProgress)

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
        updateProducerVisual(machine, machineData)
        machine.retryAt = nil
    elseif message == "Conveyor cell is full" then
        machine.retryAt = now + 0.5
    else
        machine.lastProducedTime = now
        machine.productionProgress = 0
        updateProducerVisual(machine, machineData)
        machine.retryAt = nil
    end
end

-- ---------------------------------------------------------------------------
-- Workpiece animation
--
-- While a processor is working it shows the piece sitting on the machine: the
-- input item rests in place, the saw head (any part named *Head_*, which is
-- how the Blender models are exported) sweeps across it, and partway through
-- the cut the piece becomes the finished item. Purely cosmetic - the real
-- item is still spawned onto the conveyor by updateProcessor.
-- ---------------------------------------------------------------------------

local WORKPIECE_NAME = "Workpiece"

-- The piece is fed in over the first slice of the cycle and pushed out over
-- the last, leaving the middle for the cut itself.
local WORKPIECE_ENTER_UNTIL = 0.2
local WORKPIECE_LEAVE_FROM = 0.8

-- How far along the bed the piece is at this point in the cycle: at the
-- intake before the cut, on the cutting line during it, at the outfeed after.
local function workpieceTravel(config, progress)
    local travel = config.travel or 0
    if travel <= 0 then
        return 0
    end

    if progress <= WORKPIECE_ENTER_UNTIL then
        return -travel * (1 - progress / WORKPIECE_ENTER_UNTIL)
    elseif progress >= WORKPIECE_LEAVE_FROM then
        return travel * ((progress - WORKPIECE_LEAVE_FROM) / (1 - WORKPIECE_LEAVE_FROM))
    end

    return 0
end

local function restoreHeadParts(machine)
    if not machine.headOrigins then
        return
    end

    for part, cframe in pairs(machine.headOrigins) do
        if part.Parent then
            part.CFrame = cframe
        end
    end

    machine.headOrigins = nil
end

local function clearWorkpiece(machine)
    if machine.workpiece then
        machine.workpiece:Destroy()
        machine.workpiece = nil
    end

    machine.workpieceItem = nil
    machine.workpieceCFrame = nil
    machine.workpiecePivot = nil
    machine.workpieceScale = nil
    machine.workpieceExit = nil
    restoreHeadParts(machine)
end

local function captureWorkpieceAnchor(machine, config)
    local instance = machine.instance
    if not instance or not instance.Parent then
        return false
    end

    -- Measured before the workpiece is parented in, so it cannot drag the
    -- bounding box of the machine around with it.
    local boundsCFrame, boundsSize = instance:GetBoundingBox()
    local scale = instance:IsA("Model") and instance:GetScale() or 1
    local bedY = boundsCFrame.Position.Y - boundsSize.Y / 2 + (config.bedHeight or 1) * scale
    local pivot = instance:GetPivot()

    -- The working surface, not where the piece goes: placeWorkpiece stands
    -- each piece on top of it, so a fat log and a thin plank both sit on the
    -- bed instead of one floating and the other sinking into it.
    machine.workpieceCFrame = CFrame.new(boundsCFrame.Position.X, bedY, boundsCFrame.Position.Z)
        * (pivot - pivot.Position)
    machine.workpiecePivot = pivot
    machine.workpieceScale = scale

    -- Which way along the bed the finished piece leaves. Taken from the cell
    -- the machine actually outputs to rather than from a convention about
    -- model orientation, so it follows whatever the machine is set up to do.
    machine.workpieceExit = 0
    local outputCellX, outputCellZ = getOutputCell(machine)
    local cellX = instance:GetAttribute("CellX") or machine.cellX
    local cellZ = instance:GetAttribute("CellZ") or machine.cellZ
    if outputCellX and outputCellZ and cellX and cellZ then
        local worldExit = Vector3.new(
            math.sign(outputCellX - cellX),
            0,
            math.sign(outputCellZ - cellZ)
        )
        local alongBed = pivot:VectorToObjectSpace(worldExit).X
        machine.workpieceExit = math.abs(alongBed) > 0.5 and math.sign(alongBed) or 0
    end

    local origins = {}
    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("BasePart") and string.find(descendant.Name, "Head_", 1, true) then
            origins[descendant] = descendant.CFrame
        end
    end
    machine.headOrigins = next(origins) and origins or nil

    return true
end

local function setWorkpieceItem(machine, itemName)
    if machine.workpieceItem == itemName then
        return
    end

    if machine.workpiece then
        machine.workpiece:Destroy()
        machine.workpiece = nil
    end

    machine.workpieceItem = itemName

    if not productionItemModule or not itemName then
        return
    end

    local created, model = pcall(productionItemModule.CreateInstance, itemName)
    if not created or not model then
        return
    end

    model.Name = WORKPIECE_NAME
    if model:IsA("BasePart") then
        model.Anchored = true
        model.CanCollide = false
        model.CanQuery = false
        model.CanTouch = false
    end
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanQuery = false
            descendant.CanTouch = false
        end
    end

    model.Parent = machine.instance
    machine.workpiece = model
end

local function placeWorkpiece(machine, alongBed)
    local model = machine.workpiece
    local bed = machine.workpieceCFrame
    if not model or not model.Parent or not bed then
        return
    end

    -- The bed axis is the machine's own X: every machine in the game is built
    -- with the flow running along it, in at one end and out at the other.
    bed = bed * CFrame.new((alongBed or 0) * (machine.workpieceExit or 0), 0, 0)

    local function setPivot(cframe)
        if model:IsA("BasePart") then
            model.CFrame = cframe
        else
            model:PivotTo(cframe)
        end
    end

    -- Put the pivot on the bed, then lift by however far the piece hangs
    -- below it. Measuring beats assuming the pivot is at the centre: it is
    -- not, for every model, and that is what leaves pieces half sunk.
    setPivot(bed)

    local centre, size
    if model:IsA("BasePart") then
        centre, size = model.CFrame, model.Size
    else
        centre, size = model:GetBoundingBox()
    end

    setPivot(bed + Vector3.new(0, bed.Position.Y - (centre.Position.Y - size.Y / 2), 0))
end

local function sweepHead(machine, config, progress)
    if not machine.headOrigins then
        return
    end

    local travel = config.headTravel or 0
    if travel <= 0 then
        return
    end

    local instance = machine.instance
    if not instance or not instance.Parent then
        return
    end

    -- Travels the length of the piece across the cut, centred on the machine.
    -- Only while the piece is actually there: it waits at one end of its
    -- stroke while the piece is still coming in, and stays at the other while
    -- it leaves.
    local cut = math.clamp(
        (progress - WORKPIECE_ENTER_UNTIL) / (WORKPIECE_LEAVE_FROM - WORKPIECE_ENTER_UNTIL),
        0,
        1
    )
    local scale = machine.workpieceScale or 1
    local offset = instance:GetPivot().RightVector * (travel * scale * (cut - 0.5))
    for part, origin in pairs(machine.headOrigins) do
        if part.Parent then
            part.CFrame = origin + offset
        end
    end
end

local function updateWorkpiece(machine, machineData, now)
    local config = machineData and machineData.workpiece
    if not config then
        return
    end

    if not machine.processingStartedAt then
        clearWorkpiece(machine)
        return
    end

    local instance = machine.instance
    if machine.workpiecePivot and instance and instance.Parent then
        local pivot = instance:GetPivot()
        local moved = (pivot.Position - machine.workpiecePivot.Position).Magnitude > 0.05
        local turned = pivot.LookVector:Dot(machine.workpiecePivot.LookVector) < 0.999
        if moved or turned then
            -- Origins were captured against the old placement: drop them
            -- before they get restored to the wrong spot.
            machine.headOrigins = nil
            clearWorkpiece(machine)
        end
    end

    if not machine.workpieceCFrame and not captureWorkpieceAnchor(machine, config) then
        return
    end

    local processingTime = machineData.processingTime or 1
    local progress = math.clamp((now - machine.processingStartedAt) / processingTime, 0, 1)
    local swapAt = config.swapAt or 0.65

    setWorkpieceItem(machine, progress < swapAt and machineData.inputItem or machineData.outputItem)
    placeWorkpiece(machine, workpieceTravel(config, progress) * (machine.workpieceScale or 1))
    sweepHead(machine, config, progress)
end

local function updateProcessor(player, machine, machineData, now)
    updateProcessingVisual(machine)

    if not hasEnoughInputForRecipe(machine, machineData) then
        machine.processingStartedAt = nil
        clearWorkpiece(machine)
        return
    end

    if not machine.processingStartedAt then
        machine.processingStartedAt = now
        updateProcessingVisual(machine)
        updateWorkpiece(machine, machineData, now)
        return
    end

    updateWorkpiece(machine, machineData, now)

    local processingTime = machineData.processingTime or 1
    if now - machine.processingStartedAt < processingTime then
        return
    end

    local outputCellX, outputCellZ = getOutputCell(machine)
    if outputCellX == nil or outputCellZ == nil then
        machine.retryAt = now + 0.5
        return
    end

    local spawned, message = ConveyorSystem.SpawnProductionItem(player, machineData.outputItem, outputCellX, outputCellZ)
    if spawned then
        for _ = 1, getRecipeInputCount(machineData) do
            table.remove(machine.inputQueue, 1)
        end

        machine.processingStartedAt = hasEnoughInputForRecipe(machine, machineData) and now or nil
        machine.retryAt = nil
        clearWorkpiece(machine)
        updateProcessingVisual(machine)
    elseif message == "Conveyor cell is full" then
        machine.retryAt = now + 0.5
        return
    else
        machine.retryAt = now + 0.5
        return
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
            machine.processingStartedAt = nil
            clearWorkpiece(machine)
            updateProcessingVisual(machine)
        elseif machine.type == "producer" then
            updateProducerVisual(machine, machineData)
            PlotWorkers.Clear(machine)
        end

        if machine.instance and machine.instance.Parent then
            machine.instance:SetAttribute("MachineStatusText", "No power")
            machine.instance:SetAttribute("ProcessingProgress", 0)
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
        processingStartedAt = nil,
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
    if machine.type == "processor" then
        updateProcessingVisual(machine)
    elseif machine.type == "producer" then
        updateProducerVisual(machine, machineData)
    end

    return true
end

function MachineSystem.UnregisterMachine(player, cellX, cellZ)
    local machines = activeMachines[player]
    if not machines then
        return
    end

    local machine = machines[machineKey(cellX, cellZ)]
    if machine then
        clearWorkpiece(machine)
        PlotWorkers.Clear(machine)
    end

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

    if not machine.processingStartedAt and hasEnoughInputForRecipe(machine, machineData) then
        machine.processingStartedAt = tick()
    end

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
