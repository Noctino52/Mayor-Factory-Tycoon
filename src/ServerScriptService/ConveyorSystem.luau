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

local function isTransportItem(itemName)
    local itemDef = Definitions.GetItem(itemName)
    if not itemDef then
        return isConveyorItem(itemName)
    end

    return itemDef.type == "conveyor" or itemDef.type == "curved_conveyor" or itemDef.type == "splitter" or itemDef.type == "merger"
end

local function rotateDirection(dx, dz, rotationSteps)
    rotationSteps = math.floor(tonumber(rotationSteps) or 0) % 4

    for _ = 1, rotationSteps do
        dx, dz = -dz, dx
    end

    return dx, dz
end

local function getRoutingDirection(cellInfo, activeItem)
    if not cellInfo then
        return 1, 0
    end

    if cellInfo.type == "merger" then
        return rotateDirection(1, 0, cellInfo.rotation)
    end

    return cellInfo.directionX or 1, cellInfo.directionZ or 0
end

local CURVED_CONVEYOR_ROUTES = {
    -- Rotation 0: input from left -> output bottom.
    { inputX = -1, inputZ = 0, outputX = 0, outputZ = 1 },
    -- Rotation 1: input from bottom -> output right.
    { inputX = 0, inputZ = 1, outputX = 1, outputZ = 0 },
    -- Rotation 2: input from top -> output right.
    { inputX = 0, inputZ = -1, outputX = 1, outputZ = 0 },
    -- Rotation 3: input from left -> output top.
    { inputX = -1, inputZ = 0, outputX = 0, outputZ = -1 },
}

local CURVED_CONVEYOR_ROUTE_ROTATION_OFFSET = 0

local function formatCellForLog(cellX, cellZ)
    if cellX == nil or cellZ == nil then
        return "(nil,nil)"
    end

    return "(" .. tostring(cellX) .. "," .. tostring(cellZ) .. ")"
end

local function formatVectorForLog(position)
    if not position then
        return "(nil,nil,nil)"
    end

    return string.format("(%.3f, %.3f, %.3f)", position.X, position.Y, position.Z)
end

local function getRouteSideLabel(dx, dz)
    if dx == -1 and dz == 0 then
        return "sinistra(-X)"
    elseif dx == 1 and dz == 0 then
        return "destra(+X)"
    elseif dx == 0 and dz == -1 then
        return "alto(-Z)"
    elseif dx == 0 and dz == 1 then
        return "basso(+Z)"
    end

    return tostring(dx) .. "," .. tostring(dz)
end

local function logCurvedConveyorRoute(cellInfo, previousCellX, previousCellZ, nextCellX, nextCellZ, activeItem, route, rotation, visualRotation)
    local curvedConveyor = cellInfo and cellInfo.instance
    local player = activeItem and activeItem.player
    local itemName = activeItem and activeItem.itemName or "unknown"
    local cellX = curvedConveyor and curvedConveyor:GetAttribute("CellX") or nil
    local cellZ = curvedConveyor and curvedConveyor:GetAttribute("CellZ") or nil
    local pivot = curvedConveyor and curvedConveyor:GetPivot() or nil
    local yawDegrees = 0

    if pivot then
        local _, yaw = pivot:ToOrientation()
        yawDegrees = math.deg(yaw)
    end

    local expectedInputCell = route and formatCellForLog(cellX + route.inputX, cellZ + route.inputZ) or "(nil,nil)"
    local expectedOutputCell = route and formatCellForLog(cellX + route.outputX, cellZ + route.outputZ) or "(nil,nil)"
    local inputSide = route and getRouteSideLabel(route.inputX, route.inputZ) or "nil"
    local outputSide = route and getRouteSideLabel(route.outputX, route.outputZ) or "nil"
    local result = (nextCellX ~= nil and nextCellZ ~= nil) and "ACCEPTED" or "REJECTED"

    print(string.format(
        "[CurvedConveyorRoute] result=%s player=%s item=%s curved=%s cell=%s world=%s logicalRotation=%s visualRouteRotation=%s routeOffset=%s modelYaw=%.1f prevCell=%s expectedInput=%s inputSide=%s outputCell=%s outputSide=%s nextCell=%s",
        result,
        player and player.Name or "nil",
        tostring(itemName),
        curvedConveyor and curvedConveyor:GetFullName() or "nil",
        formatCellForLog(cellX, cellZ),
        formatVectorForLog(pivot and pivot.Position or nil),
        tostring(rotation),
        tostring(visualRotation),
        tostring(CURVED_CONVEYOR_ROUTE_ROTATION_OFFSET),
        yawDegrees,
        formatCellForLog(previousCellX, previousCellZ),
        expectedInputCell,
        inputSide,
        expectedOutputCell,
        outputSide,
        formatCellForLog(nextCellX, nextCellZ)
    ))
end

local function RouteCurvedConveyor(cellInfo, previousCellX, previousCellZ, activeItem, shouldLog)
    local curvedConveyor = cellInfo and cellInfo.instance
    if not curvedConveyor or not curvedConveyor.Parent or previousCellX == nil or previousCellZ == nil then
        if shouldLog then
            logCurvedConveyorRoute(cellInfo, previousCellX, previousCellZ, nil, nil, activeItem, nil, nil, nil)
        end
        return nil, nil
    end

    local cellX = curvedConveyor:GetAttribute("CellX")
    local cellZ = curvedConveyor:GetAttribute("CellZ")
    if cellX == nil or cellZ == nil then
        if shouldLog then
            logCurvedConveyorRoute(cellInfo, previousCellX, previousCellZ, nil, nil, activeItem, nil, nil, nil)
        end
        return nil, nil
    end

    local rotation = math.floor(tonumber(curvedConveyor:GetAttribute("Rotation")) or 0) % 4

    local visualRotation = (rotation + CURVED_CONVEYOR_ROUTE_ROTATION_OFFSET) % 4
    local route = CURVED_CONVEYOR_ROUTES[visualRotation + 1]
    local nextCellX = nil
    local nextCellZ = nil

    if route then
        curvedConveyor:SetAttribute("DebugLogicalRotation", rotation)
        curvedConveyor:SetAttribute("DebugVisualRouteRotation", visualRotation)
        curvedConveyor:SetAttribute("DebugInputCellX", cellX + route.inputX)
        curvedConveyor:SetAttribute("DebugInputCellZ", cellZ + route.inputZ)
        curvedConveyor:SetAttribute("DebugOutputCellX", cellX + route.outputX)
        curvedConveyor:SetAttribute("DebugOutputCellZ", cellZ + route.outputZ)
    end

    if route and previousCellX == cellX + route.inputX and previousCellZ == cellZ + route.inputZ then
        nextCellX = cellX + route.outputX
        nextCellZ = cellZ + route.outputZ
    end

    if curvedConveyor then
        curvedConveyor:SetAttribute("DebugRouteAccepted", nextCellX ~= nil and nextCellZ ~= nil)
    end

    if shouldLog then
        logCurvedConveyorRoute(cellInfo, previousCellX, previousCellZ, nextCellX, nextCellZ, activeItem, route, rotation, visualRotation)
    end

    return nextCellX, nextCellZ
end

local function getSplitterInputLane(splitter, previousCellX, previousCellZ)
    if previousCellX == nil or previousCellZ == nil then
        return nil
    end

    local cellX = splitter:GetAttribute("CellX")
    local cellZ = splitter:GetAttribute("CellZ")
    if cellX == nil or cellZ == nil then
        return nil
    end

    local cellsX = splitter:GetAttribute("CellsX") or 2
    local cellsZ = splitter:GetAttribute("CellsZ") or 1
    local rotation = math.floor(tonumber(splitter:GetAttribute("Rotation")) or 0) % 4

    if rotation == 1 then
        return previousCellX == cellX - 1 and previousCellZ == cellZ and 1 or nil
    elseif rotation == 2 then
        return previousCellZ == cellZ - 1 and previousCellX == cellX + cellsX - 1 and 1 or nil
    elseif rotation == 3 then
        return previousCellX == cellX + cellsX and previousCellZ == cellZ + cellsZ - 1 and 1 or nil
    end

    return previousCellZ == cellZ + cellsZ and previousCellX == cellX and 1 or nil
end

local function isCellOnSplitterInput(splitter, previousCellX, previousCellZ)
    return getSplitterInputLane(splitter, previousCellX, previousCellZ) ~= nil
end

local function getSplitterOutputCell(cellInfo, activeItem, outputLane)
    local splitter = cellInfo and cellInfo.instance
    if not splitter or not splitter.Parent then
        return nil, nil
    end

    if not isCellOnSplitterInput(splitter, activeItem and activeItem.previousCellX, activeItem and activeItem.previousCellZ) then
        return nil, nil
    end

    local cellX = splitter:GetAttribute("CellX")
    local cellZ = splitter:GetAttribute("CellZ")
    if cellX == nil or cellZ == nil then
        return nil, nil
    end

    outputLane = outputLane or (splitter:GetAttribute("SplitterUseSecondOutput") == true and 2 or 1)

    local cellsX = splitter:GetAttribute("CellsX") or 2
    local cellsZ = splitter:GetAttribute("CellsZ") or 1
    local rotation = math.floor(tonumber(splitter:GetAttribute("Rotation")) or 0) % 4
    local useSecondOutput = outputLane == 2

    if rotation == 1 then
        return cellX + cellsX, cellZ + (useSecondOutput and 1 or 0)
    elseif rotation == 2 then
        return cellX + (useSecondOutput and 0 or 1), cellZ + cellsZ
    elseif rotation == 3 then
        return cellX - 1, cellZ + (useSecondOutput and 0 or 1)
    end

    return cellX + (useSecondOutput and 1 or 0), cellZ - 1
end

local function getSplitterInputCellForSpawn(cellInfo, spawnCellX, spawnCellZ)
    local splitter = cellInfo and cellInfo.instance
    if not splitter or not splitter.Parent then
        return nil, nil
    end

    local cellX = splitter:GetAttribute("CellX")
    local cellZ = splitter:GetAttribute("CellZ")
    if cellX == nil or cellZ == nil then
        return nil, nil
    end

    local cellsX = splitter:GetAttribute("CellsX") or 2
    local cellsZ = splitter:GetAttribute("CellsZ") or 1
    local rotation = math.floor(tonumber(splitter:GetAttribute("Rotation")) or 0) % 4

    if rotation == 1 then
        return cellX - 1, cellZ
    elseif rotation == 2 then
        return cellX + cellsX - 1, cellZ - 1
    elseif rotation == 3 then
        return cellX + cellsX, cellZ + cellsZ - 1
    end

    return cellX, cellZ + cellsZ
end

local function getMergerInputLane(merger, inputCellX, inputCellZ)
    if inputCellX == nil or inputCellZ == nil then
        return nil
    end

    local cellX = merger:GetAttribute("CellX")
    local cellZ = merger:GetAttribute("CellZ")
    if cellX == nil or cellZ == nil then
        return nil
    end

    local cellsX = merger:GetAttribute("CellsX") or 2
    local cellsZ = merger:GetAttribute("CellsZ") or 1
    local rotation = math.floor(tonumber(merger:GetAttribute("Rotation")) or 0) % 4

    if rotation == 1 then
        if inputCellX == cellX - 1 and inputCellZ >= cellZ and inputCellZ < cellZ + cellsZ then
            return math.clamp(inputCellZ - cellZ + 1, 1, 2)
        end
    elseif rotation == 2 then
        if inputCellZ == cellZ - 1 and inputCellX >= cellX and inputCellX < cellX + cellsX then
            return math.clamp(cellX + cellsX - inputCellX, 1, 2)
        end
    elseif rotation == 3 then
        if inputCellX == cellX + cellsX and inputCellZ >= cellZ and inputCellZ < cellZ + cellsZ then
            return math.clamp(cellZ + cellsZ - inputCellZ, 1, 2)
        end
    elseif inputCellZ == cellZ + cellsZ and inputCellX >= cellX and inputCellX < cellX + cellsX then
        return math.clamp(inputCellX - cellX + 1, 1, 2)
    end

    return nil
end

local function getMergerOutputCell(cellInfo, activeItem)
    local merger = cellInfo and cellInfo.instance
    if not merger or not merger.Parent then
        return nil, nil, nil
    end

    local inputLane = getMergerInputLane(merger, activeItem and activeItem.previousCellX, activeItem and activeItem.previousCellZ)
    if not inputLane then
        return nil, nil, nil
    end

    local cellX = merger:GetAttribute("CellX")
    local cellZ = merger:GetAttribute("CellZ")
    if cellX == nil or cellZ == nil then
        return nil, nil, nil
    end

    local cellsX = merger:GetAttribute("CellsX") or 2
    local cellsZ = merger:GetAttribute("CellsZ") or 1
    local rotation = math.floor(tonumber(merger:GetAttribute("Rotation")) or 0) % 4

    if rotation == 1 then
        return cellX + cellsX, cellZ, inputLane
    elseif rotation == 2 then
        return cellX + cellsX - 1, cellZ + cellsZ, inputLane
    elseif rotation == 3 then
        return cellX - 1, cellZ + cellsZ - 1, inputLane
    end

    return cellX, cellZ - 1, inputLane
end

local function getMergerInputCellForSpawn(cellInfo, spawnCellX, spawnCellZ)
    local merger = cellInfo and cellInfo.instance
    if not merger or not merger.Parent then
        return nil, nil
    end

    local cellX = merger:GetAttribute("CellX")
    local cellZ = merger:GetAttribute("CellZ")
    if cellX == nil or cellZ == nil then
        return nil, nil
    end

    local cellsX = merger:GetAttribute("CellsX") or 2
    local cellsZ = merger:GetAttribute("CellsZ") or 1
    local rotation = math.floor(tonumber(merger:GetAttribute("Rotation")) or 0) % 4

    if rotation == 1 then
        return cellX - 1, spawnCellZ
    elseif rotation == 2 then
        return spawnCellX, cellZ - 1
    elseif rotation == 3 then
        return cellX + cellsX, spawnCellZ
    end

    return spawnCellX, cellZ + cellsZ
end

local function getCellInfo(player, cellX, cellZ)
    for _, item in ipairs(getPlacedItems(player)) do
        if item and item.Parent and doesFootprintContain(item, cellX, cellZ) then
            local itemName = item:GetAttribute("ItemName")
            local itemDef = Definitions.GetItem(itemName)
            local machineDef = Definitions.GetMachine(itemName)

            if isTransportItem(itemName) then
                local directionX, directionZ = getConveyorDirection(item)
                local cellType = itemDef and itemDef.type or "conveyor"

                return {
                    type = cellType,
                    instance = item,
                    itemDef = itemDef,
                    rotation = item:GetAttribute("Rotation") or 0,
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

local function isTransportCell(cellInfo)
    return cellInfo and (cellInfo.type == "conveyor" or cellInfo.type == "curved_conveyor" or cellInfo.type == "splitter" or cellInfo.type == "merger")
end

local function canReceiveSplitOutput(cellInfo)
    return cellInfo and (isTransportCell(cellInfo) or cellInfo.type == "machine" or cellInfo.type == "sell_zone")
end

local function selectSplitterOutputCell(player, splitterCellInfo, activeItem)
    local splitter = splitterCellInfo and splitterCellInfo.instance
    if not splitter then
        return nil, nil
    end

    local straightCellX, straightCellZ = getSplitterOutputCell(splitterCellInfo, activeItem, 1)
    if straightCellX == nil or straightCellZ == nil then
        return nil, nil
    end

    local preferredLane = splitter:GetAttribute("SplitterUseSecondOutput") == true and 2 or 1
    if preferredLane == 1 then
        splitter:SetAttribute("SplitterUseSecondOutput", true)
        return straightCellX, straightCellZ
    end

    local branchCellX, branchCellZ = getSplitterOutputCell(splitterCellInfo, activeItem, 2)
    local branchCell = getCellInfo(player, branchCellX, branchCellZ)
    if canReceiveSplitOutput(branchCell) and canReserveCell(player, branchCellX, branchCellZ) then
        splitter:SetAttribute("SplitterUseSecondOutput", false)
        return branchCellX, branchCellZ
    end

    return straightCellX, straightCellZ
end

local function shouldAllowMergerInput(activeItem, mergerCellInfo, inputLane)
    local merger = mergerCellInfo and mergerCellInfo.instance
    if not merger or not inputLane then
        return false
    end

    local hasCompetingInput = false
    for _, otherItem in ipairs(activeItems) do
        if otherItem ~= activeItem and otherItem.player == activeItem.player and otherItem.model and otherItem.model.Parent and not otherItem.isMoving and not otherItem.waitingForMachine then
            local otherCurrentCell = getCellInfo(otherItem.player, otherItem.cellX, otherItem.cellZ)
            if isTransportCell(otherCurrentCell) and otherCurrentCell.type ~= "splitter" and otherCurrentCell.type ~= "merger" then
                local otherNextCellX = nil
                local otherNextCellZ = nil
                if otherCurrentCell.type == "curved_conveyor" then
                    otherNextCellX, otherNextCellZ = RouteCurvedConveyor(otherCurrentCell, otherItem.previousCellX, otherItem.previousCellZ)
                else
                    local otherDx, otherDz = getRoutingDirection(otherCurrentCell, otherItem)
                    otherNextCellX = otherItem.cellX + otherDx
                    otherNextCellZ = otherItem.cellZ + otherDz
                end

                local otherNextCell = otherNextCellX ~= nil and otherNextCellZ ~= nil and getCellInfo(otherItem.player, otherNextCellX, otherNextCellZ) or nil
                if otherNextCell and otherNextCell.instance == merger then
                    local otherLane = getMergerInputLane(merger, otherItem.cellX, otherItem.cellZ)
                    if otherLane and otherLane ~= inputLane then
                        hasCompetingInput = true
                        break
                    end
                end
            end
        end
    end

    if not hasCompetingInput then
        return true
    end

    local nextInputLane = merger:GetAttribute("MergerNextInputLane")
    if nextInputLane ~= 1 and nextInputLane ~= 2 then
        nextInputLane = 1
    end

    if inputLane ~= nextInputLane then
        return false
    end

    return true
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
    elseif not isTransportCell(cellInfo) then
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
    if not isTransportCell(currentCell) then
        destroyProductionItem(activeItem, true)
        return
    end

    if currentCell.type == "splitter" and not activeItem.spawnedOnSplitter then
        destroyProductionItem(activeItem, true)
        return
    end

    if currentCell.type == "merger" and not activeItem.spawnedOnMerger then
        destroyProductionItem(activeItem, true)
        return
    end

    local nextCellX = nil
    local nextCellZ = nil
    local mergerToAdvance = nil
    local mergerInputLane = nil
    if currentCell.type == "splitter" then
        activeItem.spawnedOnSplitter = false
        nextCellX, nextCellZ = selectSplitterOutputCell(activeItem.player, currentCell, activeItem)
    elseif currentCell.type == "curved_conveyor" then
        nextCellX, nextCellZ = RouteCurvedConveyor(currentCell, activeItem.previousCellX, activeItem.previousCellZ, activeItem, true)
    elseif currentCell.type == "merger" then
        local inputLane = nil
        nextCellX, nextCellZ, inputLane = getMergerOutputCell(currentCell, activeItem)
        if not shouldAllowMergerInput(activeItem, currentCell, inputLane) then
            return
        end
        mergerToAdvance = currentCell.instance
        mergerInputLane = inputLane
        activeItem.spawnedOnMerger = false
    else
        local dx, dz = getRoutingDirection(currentCell, activeItem)
        nextCellX = activeItem.cellX + dx
        nextCellZ = activeItem.cellZ + dz
    end

    if nextCellX == nil or nextCellZ == nil then
        destroyProductionItem(activeItem, true)
        return
    end
    local nextCell = getCellInfo(activeItem.player, nextCellX, nextCellZ)
    local nextCellKey = cellKey(nextCellX, nextCellZ)
    local isLoopingToVisitedTransport = isTransportCell(nextCell) and activeItem.visitedCells[nextCellKey] == true

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

    if nextCell and nextCell.type == "splitter" then
        local routedCellX, routedCellZ = selectSplitterOutputCell(activeItem.player, nextCell, {
            previousCellX = activeItem.cellX,
            previousCellZ = activeItem.cellZ,
        })

        if routedCellX == nil or routedCellZ == nil then
            destroyProductionItem(activeItem, true)
            return
        end

        nextCellX = routedCellX
        nextCellZ = routedCellZ
        nextCell = getCellInfo(activeItem.player, nextCellX, nextCellZ)
        nextCellKey = cellKey(nextCellX, nextCellZ)
        isLoopingToVisitedTransport = isTransportCell(nextCell) and activeItem.visitedCells[nextCellKey] == true
    end

    if nextCell and nextCell.type == "merger" then
        local routedCellX, routedCellZ, inputLane = getMergerOutputCell(nextCell, {
            previousCellX = activeItem.cellX,
            previousCellZ = activeItem.cellZ,
        })

        if routedCellX == nil or routedCellZ == nil then
            destroyProductionItem(activeItem, true)
            return
        end

        if not shouldAllowMergerInput(activeItem, nextCell, inputLane) then
            return
        end

        mergerToAdvance = nextCell.instance
        mergerInputLane = inputLane
        nextCellX = routedCellX
        nextCellZ = routedCellZ
        nextCell = getCellInfo(activeItem.player, nextCellX, nextCellZ)
        nextCellKey = cellKey(nextCellX, nextCellZ)
        isLoopingToVisitedTransport = isTransportCell(nextCell) and activeItem.visitedCells[nextCellKey] == true
    end

    if nextCell and not canReserveCell(activeItem.player, nextCellX, nextCellZ) then
        return
    end

    local targetPosition = gridToWorldPosition(activeItem.player, nextCellX, nextCellZ)
    if not targetPosition then
        destroyProductionItem(activeItem, true)
        return
    end

    if mergerToAdvance and mergerInputLane then
        mergerToAdvance:SetAttribute("MergerNextInputLane", mergerInputLane == 1 and 2 or 1)
    end

    activeItem.startCFrame = CFrame.new(startPosition)
    activeItem.targetCFrame = CFrame.new(targetPosition)
    activeItem.targetCellX = nextCellX
    activeItem.targetCellZ = nextCellZ
    activeItem.segmentProgress = 0
    activeItem.totalDistance = math.max((targetPosition - startPosition).Magnitude, 0.001)
    activeItem.destroyOnArrival = isLoopingToVisitedTransport
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
        activeItem.previousCellX = activeItem.cellX
        activeItem.previousCellZ = activeItem.cellZ
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
    if not isTransportCell(cellInfo) then
        return nil, "No transport at target cell"
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

    if cellInfo.type == "splitter" then
        activeItem.previousCellX, activeItem.previousCellZ = getSplitterInputCellForSpawn(cellInfo, cellX, cellZ)
        activeItem.spawnedOnSplitter = activeItem.previousCellX ~= nil and activeItem.previousCellZ ~= nil
    elseif cellInfo.type == "merger" then
        activeItem.previousCellX, activeItem.previousCellZ = getMergerInputCellForSpawn(cellInfo, cellX, cellZ)
        activeItem.spawnedOnMerger = activeItem.previousCellX ~= nil and activeItem.previousCellZ ~= nil
    end

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
