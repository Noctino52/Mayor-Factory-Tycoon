local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")

local Definitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Definitions"))

local productionItemModule = nil
local starterScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
local productionItemScript = starterScripts and starterScripts:FindFirstChild("ProductionItems")
if productionItemScript and productionItemScript:IsA("ModuleScript") then
    pcall(function()
        productionItemModule = require(productionItemScript)
    end)
end

local ConveyorSystem = {}

local PRODUCTION_ITEM_SPEED = 16
local MAX_ITEMS_PER_CELL = 5
local GRID_UNIT_SIZE = 8
local ITEM_HEIGHT_OFFSET = 0.65

local activeItems = {}
local dependencies = nil
local initialized = false
local machineInputHandler = nil
local sellHandler = nil

local productionItemsFolder = workspace:FindFirstChild("ProductionItems")
if not productionItemsFolder then
    productionItemsFolder = Instance.new("Folder")
    productionItemsFolder.Name = "ProductionItems"
    productionItemsFolder.Parent = workspace
end

local function worldDirectionToGrid(direction)
    if math.abs(direction.X) >= math.abs(direction.Z) then
        return direction.X >= 0 and 1 or -1, 0
    end

    return 0, direction.Z >= 0 and 1 or -1
end

local function cellKey(cellX, cellZ)
    return tostring(cellX) .. "_" .. tostring(cellZ)
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

local function getConveyorDirection(item)
    local conveyorPart = getFirstBasePart(item)
    if conveyorPart then
        return worldDirectionToGrid(conveyorPart.CFrame.LookVector)
    end

    if item:IsA("Model") then
        return worldDirectionToGrid(item:GetPivot().LookVector)
    end

    return 1, 0
end

local function gridToWorldPosition(player, cellX, cellZ)
    if not dependencies or not dependencies.getPlayerPlot then
        return nil
    end

    local plotInfo = dependencies.getPlayerPlot(player)
    if not plotInfo then
        return nil
    end

    return Vector3.new(
        plotInfo.position.X + cellX * GRID_UNIT_SIZE + GRID_UNIT_SIZE / 2,
        plotInfo.position.Y + plotInfo.size.Y / 2 + ITEM_HEIGHT_OFFSET,
        plotInfo.position.Z + cellZ * GRID_UNIT_SIZE + GRID_UNIT_SIZE / 2
    )
end

local function getPlacedItems(player)
    if not dependencies or not dependencies.getPlacedItems then
        return {}
    end

    return dependencies.getPlacedItems(player) or {}
end

local function doesFootprintContain(item, cellX, cellZ)
    local itemCellX = item:GetAttribute("CellX")
    local itemCellZ = item:GetAttribute("CellZ")
    if itemCellX == nil or itemCellZ == nil then
        return false
    end

    local cellsX = item:GetAttribute("CellsX") or 1
    local cellsZ = item:GetAttribute("CellsZ") or 1

    return cellX >= itemCellX and cellX < itemCellX + cellsX and cellZ >= itemCellZ and cellZ < itemCellZ + cellsZ
end

local function isConveyorItem(itemName)
    local itemDef = Definitions.GetItem(itemName)
    return (itemDef and itemDef.type == "conveyor") or tostring(itemName):find("Conveyor") ~= nil
end

local function getCellInfo(player, cellX, cellZ)
    for _, item in ipairs(getPlacedItems(player)) do
        if item and item.Parent and doesFootprintContain(item, cellX, cellZ) then
            local itemName = item:GetAttribute("ItemName")
            local itemDef = Definitions.GetItem(itemName)
            local machineDef = Definitions.GetMachine(itemName)

            if isConveyorItem(itemName) then
                local directionX, directionZ = getConveyorDirection(item)

                return {
                    type = "conveyor",
                    instance = item,
                    directionX = directionX,
                    directionZ = directionZ,
                }
            elseif machineDef then
                return {
                    type = "machine",
                    instance = item,
                    machineDef = machineDef,
                }
            elseif itemDef and (itemDef.type == "sell_zone" or itemDef.type == "sellZone") then
                return {
                    type = "sell_zone",
                    instance = item,
                    itemDef = itemDef,
                }
            end

            return {
                type = "occupied",
                instance = item,
                itemDef = itemDef,
            }
        end
    end

    return nil
end

local function countItemsInCell(player, cellX, cellZ)
    local count = 0

    for _, activeItem in ipairs(activeItems) do
        if activeItem.player == player and activeItem.model and activeItem.model.Parent then
            if activeItem.cellX == cellX and activeItem.cellZ == cellZ then
                count += 1
            elseif activeItem.targetCellX == cellX and activeItem.targetCellZ == cellZ then
                count += 1
            end
        end
    end

    return count
end

local function canReserveCell(player, cellX, cellZ)
    return countItemsInCell(player, cellX, cellZ) < MAX_ITEMS_PER_CELL
end

local function getItemCFrame(item)
    if item:IsA("Model") then
        return item:GetPivot()
    end

    return item.CFrame
end

local function setItemCFrame(item, cframe)
    if item:IsA("Model") then
        item:PivotTo(cframe)
    else
        item.CFrame = cframe
    end
end

local function createProductionItemInstance(itemName, cellX, cellZ, player)
    local item
    if productionItemModule and productionItemModule.CreateInstance then
        item = productionItemModule.CreateInstance(itemName)
    elseif productionItemModule and productionItemModule.CreatePart then
        item = productionItemModule.CreatePart(itemName)
    else
        item = Instance.new("Part")
        item.Name = "ProductionItem_" .. tostring(itemName)
        item.Size = Vector3.new(0.5, 0.5, 0.5)
        item.Color = Color3.fromRGB(235, 220, 120)
        item.Material = Enum.Material.SmoothPlastic
        item.Anchored = true
        item.CanCollide = false
        item.CanQuery = false
        item.CanTouch = false
    end

    local worldPosition = gridToWorldPosition(player, cellX, cellZ)
    if not worldPosition then
        item:Destroy()
        return nil
    end

    setItemCFrame(item, CFrame.new(worldPosition))
    item:SetAttribute("Owner", player.UserId)
    item:SetAttribute("ItemName", itemName)
    item:SetAttribute("CellX", cellX)
    item:SetAttribute("CellZ", cellZ)
    item.Parent = productionItemsFolder

    return item
end

local function removeActiveItem(activeItem)
    for index = #activeItems, 1, -1 do
        if activeItems[index] == activeItem then
            table.remove(activeItems, index)
            return
        end
    end
end

local function destroyProductionItem(activeItem, animate, holdPosition)
    removeActiveItem(activeItem)

    local model = activeItem.model
    if not model or not model.Parent then
        return
    end

    if not animate then
        model:Destroy()
        return
    end

    if model:IsA("BasePart") then
        local tweenGoals = {
            Size = Vector3.new(0.05, 0.05, 0.05),
            Transparency = 1,
        }
        if not holdPosition then
            tweenGoals.CFrame = model.CFrame * CFrame.new(0, 1.5, 0)
        end

        local tween = TweenService:Create(model, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), tweenGoals)

        tween.Completed:Connect(function()
            if model and model.Parent then
                model:Destroy()
            end
        end)

        tween:Play()
        return
    end

    local pivotValue = nil
    local pivotConnection = nil
    if not holdPosition then
        pivotValue = Instance.new("CFrameValue")
        pivotValue.Value = model:GetPivot()

        pivotConnection = pivotValue:GetPropertyChangedSignal("Value"):Connect(function()
            if model and model.Parent then
                model:PivotTo(pivotValue.Value)
            end
        end)
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            TweenService:Create(descendant, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Transparency = 1,
            }):Play()
        end
    end

    local tweenTarget = holdPosition and Instance.new("NumberValue") or pivotValue
    if holdPosition then
        tweenTarget.Value = 0
    end

    local tweenGoals = holdPosition and { Value = 1 } or {
        Value = model:GetPivot() * CFrame.new(0, 1.5, 0),
    }
    local tween = TweenService:Create(tweenTarget, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), tweenGoals)
    tween.Completed:Connect(function()
        if pivotConnection then
            pivotConnection:Disconnect()
        end
        tweenTarget:Destroy()
        if model and model.Parent then
            model:Destroy()
        end
    end)

    tween:Play()
end

local function getSellZoneSalePosition(activeItem, cellInfo)
    local basePosition = gridToWorldPosition(activeItem.player, activeItem.cellX, activeItem.cellZ)
    if not basePosition then
        return nil
    end

    local zone = cellInfo and cellInfo.instance
    if not zone or not zone.Parent then
        return basePosition
    end

    local zoneCellX = zone:GetAttribute("CellX")
    local zoneCellZ = zone:GetAttribute("CellZ")
    if zoneCellX == nil or zoneCellZ == nil then
        local zonePosition = zone:IsA("Model") and zone:GetPivot().Position or zone.Position
        return Vector3.new(zonePosition.X, basePosition.Y, zonePosition.Z)
    end

    local cellsX = zone:GetAttribute("CellsX") or 1
    local cellsZ = zone:GetAttribute("CellsZ") or 1
    local centerCellX = zoneCellX + (cellsX - 1) / 2
    local centerCellZ = zoneCellZ + (cellsZ - 1) / 2
    local centerPosition = gridToWorldPosition(activeItem.player, centerCellX, centerCellZ)

    return centerPosition or basePosition
end

local function fadeProductionItemInPlace(activeItem, position)
    removeActiveItem(activeItem)

    local model = activeItem.model
    if not model or not model.Parent then
        return
    end

    if position then
        setItemCFrame(model, CFrame.new(position))
    end

    local lockedCFrame = getItemCFrame(model)
    local holdConnection = RunService.Heartbeat:Connect(function()
        if model and model.Parent then
            setItemCFrame(model, lockedCFrame)
        end
    end)

    local tweens = {}
    local parts = {}
    if model:IsA("BasePart") then
        table.insert(parts, model)
    else
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("BasePart") then
                table.insert(parts, descendant)
            end
        end
    end

    for _, part in ipairs(parts) do
        part.Anchored = true
        part.AssemblyLinearVelocity = Vector3.zero
        part.AssemblyAngularVelocity = Vector3.zero
        table.insert(tweens, TweenService:Create(part, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Transparency = 1,
        }))
    end

    local remaining = #tweens
    local function finish()
        if holdConnection then
            holdConnection:Disconnect()
            holdConnection = nil
        end

        if model and model.Parent then
            model:Destroy()
        end
    end

    if remaining == 0 then
        finish()
        return
    end

    for _, tween in ipairs(tweens) do
        tween.Completed:Connect(function()
            remaining -= 1
            if remaining <= 0 then
                finish()
            end
        end)
        tween:Play()
    end
end

local function sellItem(activeItem, cellInfo, sellCellX, sellCellZ, fadePosition)
    local salePosition = fadePosition or activeItem.salePosition or getSellZoneSalePosition(activeItem, cellInfo)
    local saleCellX = sellCellX or activeItem.cellX
    local saleCellZ = sellCellZ or activeItem.cellZ

    if not sellHandler then
        fadeProductionItemInPlace(activeItem, salePosition)
        return false
    end

    local sold = sellHandler(activeItem.player, activeItem.itemName, saleCellX, saleCellZ)
    fadeProductionItemInPlace(activeItem, salePosition)
    return sold == true
end

local function feedMachine(cellInfo, activeItem)
    if not machineInputHandler then
        destroyProductionItem(activeItem, true)
        return false
    end

    local accepted, message = machineInputHandler(activeItem.player, cellInfo.instance, activeItem.itemName)
    if accepted then
        activeItem.waitingForMachine = false
        destroyProductionItem(activeItem, false)
        return true
    end

    if message == "Machine input queue is full" then
        activeItem.waitingForMachine = true
        activeItem.nextMachineFeedRetry = tick() + 0.25
        return false
    end

    activeItem.waitingForMachine = false
    destroyProductionItem(activeItem, true)
    return false
end

local function handleArrival(activeItem)
    activeItem.targetCellX = nil
    activeItem.targetCellZ = nil
    activeItem.segmentProgress = 0
    activeItem.isMoving = false
    activeItem.waitingForMachine = false

    if activeItem.model and activeItem.model.Parent then
        activeItem.model:SetAttribute("CellX", activeItem.cellX)
        activeItem.model:SetAttribute("CellZ", activeItem.cellZ)
    end

    local cellInfo = getCellInfo(activeItem.player, activeItem.cellX, activeItem.cellZ)
    if activeItem.destroyOnArrival then
        activeItem.destroyOnArrival = false
        destroyProductionItem(activeItem, true)
    elseif not cellInfo then
        destroyProductionItem(activeItem, true)
    elseif cellInfo.type == "machine" then
        feedMachine(cellInfo, activeItem)
    elseif cellInfo.type == "sell_zone" then
        sellItem(activeItem, cellInfo)
    elseif cellInfo.type ~= "conveyor" then
        destroyProductionItem(activeItem, true)
    else
        activeItem.visitedCells[cellKey(activeItem.cellX, activeItem.cellZ)] = true
    end
end

local function tryStartNextSegment(activeItem)
    if activeItem.waitingForMachine then
        if activeItem.nextMachineFeedRetry and tick() < activeItem.nextMachineFeedRetry then
            return
        end

        local cellInfo = getCellInfo(activeItem.player, activeItem.cellX, activeItem.cellZ)
        if cellInfo and cellInfo.type == "machine" then
            feedMachine(cellInfo, activeItem)
        else
            activeItem.waitingForMachine = false
            destroyProductionItem(activeItem, true)
        end

        return
    end

    local currentCell = getCellInfo(activeItem.player, activeItem.cellX, activeItem.cellZ)
    local dx = (currentCell and currentCell.directionX) or 1
    local dz = (currentCell and currentCell.directionZ) or 0
    local nextCellX = activeItem.cellX + dx
    local nextCellZ = activeItem.cellZ + dz
    local nextCell = getCellInfo(activeItem.player, nextCellX, nextCellZ)
    local nextCellKey = cellKey(nextCellX, nextCellZ)
    local isLoopingToVisitedConveyor = nextCell and nextCell.type == "conveyor" and activeItem.visitedCells[nextCellKey] == true

    local startPosition = gridToWorldPosition(activeItem.player, activeItem.cellX, activeItem.cellZ)
    if not startPosition then
        destroyProductionItem(activeItem, true)
        return
    end

    activeItem.salePosition = nil
    if nextCell and nextCell.type == "sell_zone" then
        sellItem(activeItem, nextCell, nextCellX, nextCellZ, startPosition)
        return
    end

    if nextCell and not canReserveCell(activeItem.player, nextCellX, nextCellZ) then
        return
    end

    local targetPosition = gridToWorldPosition(activeItem.player, nextCellX, nextCellZ)
    if not targetPosition then
        destroyProductionItem(activeItem, true)
        return
    end

    activeItem.startCFrame = CFrame.new(startPosition)
    activeItem.targetCFrame = CFrame.new(targetPosition)
    activeItem.targetCellX = nextCellX
    activeItem.targetCellZ = nextCellZ
    activeItem.segmentProgress = 0
    activeItem.totalDistance = GRID_UNIT_SIZE
    activeItem.destroyOnArrival = isLoopingToVisitedConveyor
    activeItem.isMoving = true
end

local function moveItemAlongConveyor(activeItem, deltaTime)
    if not activeItem.model or not activeItem.model.Parent then
        removeActiveItem(activeItem)
        return
    end

    if not activeItem.isMoving then
        tryStartNextSegment(activeItem)
        return
    end

    activeItem.segmentProgress = math.min(1, activeItem.segmentProgress + (PRODUCTION_ITEM_SPEED * deltaTime) / activeItem.totalDistance)
    setItemCFrame(activeItem.model, activeItem.startCFrame:Lerp(activeItem.targetCFrame, activeItem.segmentProgress))

    if activeItem.segmentProgress >= 1 then
        activeItem.cellX = activeItem.targetCellX
        activeItem.cellZ = activeItem.targetCellZ
        handleArrival(activeItem)
    end
end

function ConveyorSystem.SpawnProductionItem(player, itemName, cellX, cellZ, conveyor)
    if not player or not player.Parent then
        return nil, "Invalid player"
    end

    if not Definitions.IsProduction(itemName) then
        return nil, "Invalid production item"
    end

    if conveyor and typeof(conveyor) == "Instance" then
        cellX = conveyor:GetAttribute("CellX") or cellX
        cellZ = conveyor:GetAttribute("CellZ") or cellZ
    end

    cellX = math.floor(tonumber(cellX) or 0)
    cellZ = math.floor(tonumber(cellZ) or 0)

    local cellInfo = getCellInfo(player, cellX, cellZ)
    if not cellInfo or cellInfo.type ~= "conveyor" then
        return nil, "No conveyor at target cell"
    end

    if not canReserveCell(player, cellX, cellZ) then
        return nil, "Conveyor cell is full"
    end

    local item = createProductionItemInstance(itemName, cellX, cellZ, player)
    if not item then
        return nil, "Could not create production item"
    end

    local activeItem = {
        model = item,
        itemName = itemName,
        cellX = cellX,
        cellZ = cellZ,
        player = player,
        startTime = tick(),
        totalDistance = GRID_UNIT_SIZE,
        segmentProgress = 0,
        visitedCells = {
            [cellKey(cellX, cellZ)] = true,
        },
        destroyOnArrival = false,
        waitingForMachine = false,
        isMoving = false,
    }

    table.insert(activeItems, activeItem)
    return activeItem
end

function ConveyorSystem.Initialize(newDependencies)
    if initialized then
        return
    end

    dependencies = newDependencies or {}
    initialized = true

    RunService.Heartbeat:Connect(function(deltaTime)
        for index = #activeItems, 1, -1 do
            moveItemAlongConveyor(activeItems[index], deltaTime)
        end
    end)

    Players.PlayerRemoving:Connect(function(player)
        for index = #activeItems, 1, -1 do
            if activeItems[index].player == player then
                local model = activeItems[index].model
                table.remove(activeItems, index)
                if model and model.Parent then
                    model:Destroy()
                end
            end
        end
    end)
end

function ConveyorSystem.GetActiveItemCount()
    return #activeItems
end

function ConveyorSystem.SetMachineInputHandler(handler)
    machineInputHandler = handler
end

function ConveyorSystem.SetSellHandler(handler)
    sellHandler = handler
end

return ConveyorSystem
