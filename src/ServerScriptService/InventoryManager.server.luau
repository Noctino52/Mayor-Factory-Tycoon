-- Inventory Manager Script (Tycoon Factory System)
-- Manages player inventories, plot assignment, and item placement
-- Uses DataStore for persistence

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

-- Import modules
local PlayerProgress = require(game.ServerScriptService.PlayerProgress)
local Definitions = require(game.ReplicatedStorage.Shared.Definitions)
local ConveyorSystem = require(game.ServerScriptService.ConveyorSystem)
local MachineSystem = require(game.ServerScriptService.MachineSystem)
local PowerSystem = require(game.ServerScriptService.PowerSystem)
local SellSystem = require(game.ServerScriptService.SellSystem)

-- Configuration
local GRID_UNIT_SIZE = 8 -- Fixed grid size in studs
local MAX_PLOTS = 6 -- Maximum number of plots
local PLOT_LABEL_HEIGHT = 15 -- Height of the plot label above the plot

-- DataStore for persistence
local playerDataStore = DataStoreService:GetDataStore("TycoonFactoryData")

-- Fallback storage if DataStore fails
local fallbackDataStore = {}
local playerData = {}
local PLOT_SAVE_VERSION = 2
local MAX_DATASTORE_RETRIES = 3
local DATASTORE_RETRY_DELAY = 1

-- Get grid unit size (now fixed)
local function getGridUnitSize()
    return GRID_UNIT_SIZE
end

local function shouldLogItemAction(itemName)
    return not tostring(itemName):find("Conveyor", 1, true)
end

local function normalizeRotation(rotation)
    return math.floor(tonumber(rotation) or 0) % 4
end

local function getRotationCFrame(rotation)
    return CFrame.Angles(0, normalizeRotation(rotation) * math.pi / 2, 0)
end

local function getFootprintCenter(cellX, cellZ, cellsX, cellsZ, plotInfo, y)
    return Vector3.new(
        plotInfo.position.X + (cellX + cellsX / 2) * GRID_UNIT_SIZE,
        y,
        plotInfo.position.Z + (cellZ + cellsZ / 2) * GRID_UNIT_SIZE
    )
end

local function roundToNearestCell(value)
    return math.floor(value + 0.5)
end

local function getPlayerDataKey(player)
    return "Player_" .. player.UserId
end

local function getItemBaseFootprint(itemName)
    local itemDef = Definitions.GetItem(itemName)
    if itemDef and itemDef.gridSize then
        return itemDef.gridSize.x or itemDef.gridSize.X or itemDef.gridSize[1] or 1,
               itemDef.gridSize.z or itemDef.gridSize.Z or itemDef.gridSize[2] or 1
    end

    if itemDef and itemDef.cells then
        return itemDef.cells.x or itemDef.cells.X or itemDef.cells[1] or 1,
               itemDef.cells.z or itemDef.cells.Z or itemDef.cells[2] or 1
    end

    return 1, 1
end

local function getRotatedFootprint(itemName, rotation)
    local cellsX, cellsZ = getItemBaseFootprint(itemName)
    if normalizeRotation(rotation) % 2 == 1 then
        return cellsZ, cellsX
    end

    return cellsX, cellsZ
end

local ITEM_VISUAL_ADJUSTMENTS = {
    Conveyor = {
        maxHeight = 1.2,
    },
    CurvedConveyor = {
        footprintPadding = 0.82,
        maxHeight = 1.2,
        maxScale = 3,
    },
}

local function sanitizeScaleFactor(itemName, scaleFactor)
    scaleFactor = tonumber(scaleFactor) or 1

    local adjustment = ITEM_VISUAL_ADJUSTMENTS[itemName]
    if adjustment and adjustment.maxScale then
        return math.min(scaleFactor, adjustment.maxScale)
    end

    return scaleFactor
end

local function getCurvedConveyorVisualPart(conveyor)
    local fallbackPart = nil
    local fallbackArea = 0

    for _, descendant in ipairs(conveyor:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local lowerName = string.lower(descendant.Name)
            if lowerName == "curvedconveyorpivot" then
                continue
            end

            if lowerName == "curved conveyor" or lowerName == "curvedconveyor" or lowerName == "curvebelt" then
                return descendant
            end

            local area = descendant.Size.X * descendant.Size.Z
            if descendant.Transparency < 1 and area > fallbackArea then
                fallbackPart = descendant
                fallbackArea = area
            end
        end
    end

    return fallbackPart
end

local function ensureCurvedConveyorPivot(conveyor)
    local pivotPart = conveyor:FindFirstChild("CurvedConveyorPivot")
    if pivotPart and pivotPart:IsA("BasePart") then
        conveyor.PrimaryPart = pivotPart
        return pivotPart
    end

    pivotPart = Instance.new("Part")
    pivotPart.Name = "CurvedConveyorPivot"
    pivotPart.Size = Vector3.new(0.2, 0.2, 0.2)
    pivotPart.Transparency = 1
    pivotPart.Anchored = true
    pivotPart.CanCollide = false
    pivotPart.CanQuery = false
    pivotPart.CanTouch = false
    pivotPart.CFrame = conveyor:GetPivot()
    pivotPart.Parent = conveyor
    conveyor.PrimaryPart = pivotPart

    return pivotPart
end

local function getVisibleBounds(instance)
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    local hasVisiblePart = false

    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant.Transparency < 1 then
            hasVisiblePart = true
            local halfSize = descendant.Size / 2
            for _, x in ipairs({ -halfSize.X, halfSize.X }) do
                for _, y in ipairs({ -halfSize.Y, halfSize.Y }) do
                    for _, z in ipairs({ -halfSize.Z, halfSize.Z }) do
                        local corner = (descendant.CFrame * CFrame.new(x, y, z)).Position
                        minX = math.min(minX, corner.X)
                        minY = math.min(minY, corner.Y)
                        minZ = math.min(minZ, corner.Z)
                        maxX = math.max(maxX, corner.X)
                        maxY = math.max(maxY, corner.Y)
                        maxZ = math.max(maxZ, corner.Z)
                    end
                end
            end
        end
    end

    if not hasVisiblePart then
        return nil, nil
    end

    local minPoint = Vector3.new(minX, minY, minZ)
    local maxPoint = Vector3.new(maxX, maxY, maxZ)
    return (minPoint + maxPoint) / 2, maxPoint - minPoint
end

local function normalizeCurvedConveyorGeometry(conveyor)
    local visualPart = getCurvedConveyorVisualPart(conveyor)
    if not visualPart then
        return nil
    end

    local pivotPart = ensureCurvedConveyorPivot(conveyor)

    for _, descendant in ipairs(conveyor:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant ~= visualPart and string.lower(descendant.Name) == "cube" then
            descendant.Transparency = 1
            descendant.CanCollide = false
            descendant.CanQuery = false
            descendant.CanTouch = false
        end
    end

    if not conveyor:GetAttribute("CurvedGeometryNormalized") then
        local visibleCenter, visibleSize = getVisibleBounds(conveyor)
        if visibleCenter and visibleSize then
            local pivot = pivotPart.CFrame
            local currentLocalCenter = pivot:PointToObjectSpace(visibleCenter)
            local targetLocalCenter = Vector3.new(0, visibleSize.Y / 2, 0)
            local worldDelta = pivot:VectorToWorldSpace(targetLocalCenter - currentLocalCenter)

            for _, descendant in ipairs(conveyor:GetDescendants()) do
                if descendant:IsA("BasePart") and descendant.Transparency < 1 then
                    descendant.CFrame = descendant.CFrame + worldDelta
                end
            end
        end

        conveyor:SetAttribute("CurvedGeometryNormalized", true)
    end

    return pivotPart
end

local function pivotModelToFootprint(model, centerPosition, groundY, rotation)
    model:PivotTo(CFrame.new(centerPosition.X, groundY, centerPosition.Z) * getRotationCFrame(rotation))

    local visibleCenter, visibleSize = getVisibleBounds(model)
    if visibleCenter and visibleSize then
        local targetCenter = Vector3.new(centerPosition.X, groundY + visibleSize.Y / 2, centerPosition.Z)
        model:PivotTo(model:GetPivot() + (targetCenter - visibleCenter))
        return
    end

    local boundingCFrame, size = model:GetBoundingBox()
    local targetCenter = Vector3.new(centerPosition.X, groundY + size.Y / 2, centerPosition.Z)
    model:PivotTo(model:GetPivot() + (targetCenter - boundingCFrame.Position))
end

local function getAdjustedItemHeight(itemName, height)
    local adjustment = ITEM_VISUAL_ADJUSTMENTS[itemName]
    if not adjustment or not adjustment.maxHeight then
        return height
    end

    return math.min(height, adjustment.maxHeight)
end

local function applyItemVisualAdjustments(item, itemName)
    local adjustment = ITEM_VISUAL_ADJUSTMENTS[itemName]
    if not adjustment or not adjustment.maxHeight then
        return
    end

    local _, size = item:GetBoundingBox()
    if size.Y <= adjustment.maxHeight or size.Y <= 0 then
        return
    end

    local heightScale = adjustment.maxHeight / size.Y
    for _, descendant in ipairs(item:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Size = Vector3.new(
                descendant.Size.X,
                math.max(0.05, descendant.Size.Y * heightScale),
                descendant.Size.Z
            )
        end
    end
end

local function areCellsValid(cellX, cellZ, cellsX, cellsZ, plotInfo)
    if not plotInfo or cellX == nil or cellZ == nil then
        return false
    end

    local halfPlotCellsX = math.floor((plotInfo.size.X / 2) / GRID_UNIT_SIZE)
    local halfPlotCellsZ = math.floor((plotInfo.size.Z / 2) / GRID_UNIT_SIZE)

    for dx = 0, cellsX - 1 do
        for dz = 0, cellsZ - 1 do
            local checkX = cellX + dx
            local checkZ = cellZ + dz

            if checkX < -halfPlotCellsX or checkX >= halfPlotCellsX or checkZ < -halfPlotCellsZ or checkZ >= halfPlotCellsZ then
                return false
            end
        end
    end

    return true
end

local function doFootprintsOverlap(ax, az, aw, ad, bx, bz, bw, bd)
    return ax < bx + bw and ax + aw > bx and az < bz + bd and az + ad > bz
end

local function isAreaOccupied(player, cellX, cellZ, cellsX, cellsZ, ignoredItem)
    local data = playerData[player]
    if not data then
        return false
    end

    for _, placedItem in ipairs(data.placedItems) do
        if placedItem and placedItem.Parent and placedItem ~= ignoredItem then
            local itemCellX = placedItem:GetAttribute("CellX")
            local itemCellZ = placedItem:GetAttribute("CellZ")
            local itemCellsX = placedItem:GetAttribute("CellsX") or 1
            local itemCellsZ = placedItem:GetAttribute("CellsZ") or 1

            if itemCellX ~= nil and itemCellZ ~= nil and doFootprintsOverlap(cellX, cellZ, cellsX, cellsZ, itemCellX, itemCellZ, itemCellsX, itemCellsZ) then
                return true
            end
        end
    end

    return false
end

-- Get templates folder
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local templatesFolder = sharedFolder:WaitForChild("ItemTemplates")

-- Clean up template artifacts that should never run from placed/cloned items.
local function removeRuntimeArtifacts(model)
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("Sound") or descendant:IsA("Script") or descendant:IsA("LocalScript") then
            descendant:Destroy()
        end
    end
end

for _, template in ipairs(templatesFolder:GetChildren()) do
    removeRuntimeArtifacts(template)
end
templatesFolder.DescendantAdded:Connect(function(descendant)
    if descendant:IsA("Sound") or descendant:IsA("Script") or descendant:IsA("LocalScript") then
        descendant:Destroy()
    end
end)
print("[InventoryManager] Removed runtime artifacts from all templates")

-- Create RemoteEvents
local placeItemRemote = Instance.new("RemoteEvent")
placeItemRemote.Name = "PlaceItem"
placeItemRemote.Parent = ReplicatedStorage

local getInventoryRemote = Instance.new("RemoteFunction")
getInventoryRemote.Name = "GetInventory"
getInventoryRemote.Parent = ReplicatedStorage

local spawnProductionItemRemote = Instance.new("RemoteFunction")
spawnProductionItemRemote.Name = "SpawnProductionItem"
spawnProductionItemRemote.Parent = ReplicatedStorage

local deleteItemRemote = Instance.new("RemoteEvent")
deleteItemRemote.Name = "DeleteItem"
deleteItemRemote.Parent = ReplicatedStorage

local rotateItemRemote = Instance.new("RemoteEvent")
rotateItemRemote.Name = "RotateItem"
rotateItemRemote.Parent = ReplicatedStorage

-- Create new RemoteEvent for plot assignment
local getPlotRemote = Instance.new("RemoteFunction")
getPlotRemote.Name = "GetPlayerPlot"
getPlotRemote.Parent = ReplicatedStorage

-- Create RemoteFunctions for player progress
local getMoneyRemote = Instance.new("RemoteFunction")
getMoneyRemote.Name = "GetMoney"
getMoneyRemote.Parent = ReplicatedStorage

local getReputationRemote = Instance.new("RemoteFunction")
getReputationRemote.Name = "GetReputation"
getReputationRemote.Parent = ReplicatedStorage

local getPlacedItemsRemote = Instance.new("RemoteFunction")
getPlacedItemsRemote.Name = "GetPlacedItems"
getPlacedItemsRemote.Parent = ReplicatedStorage

local getTownPrestigeRemote = Instance.new("RemoteFunction")
getTownPrestigeRemote.Name = "GetTownPrestige"
getTownPrestigeRemote.Parent = ReplicatedStorage

local getSalesStatsRemote = Instance.new("RemoteFunction")
getSalesStatsRemote.Name = "GetSalesStats"
getSalesStatsRemote.Parent = ReplicatedStorage

local getPowerStatusRemote = Instance.new("RemoteFunction")
getPowerStatusRemote.Name = "GetPowerStatus"
getPowerStatusRemote.Parent = ReplicatedStorage

-- Create RemoteEvent for buying items from shop
local buyItemRemote = Instance.new("RemoteEvent")
buyItemRemote.Name = "BuyItem"
buyItemRemote.Parent = ReplicatedStorage

-- Create RemoteEvent for selling items back to shop
local sellItemRemote = Instance.new("RemoteEvent")
sellItemRemote.Name = "SellItem"
sellItemRemote.Parent = ReplicatedStorage

-- Create RemoteEvents for inventory/shop feedback
local inventoryUpdatedRemote = Instance.new("RemoteEvent")
inventoryUpdatedRemote.Name = "InventoryUpdated"
inventoryUpdatedRemote.Parent = ReplicatedStorage

local shopTransactionResultRemote = Instance.new("RemoteEvent")
shopTransactionResultRemote.Name = "ShopTransactionResult"
shopTransactionResultRemote.Parent = ReplicatedStorage

local placementResultRemote = Instance.new("RemoteEvent")
placementResultRemote.Name = "PlacementResult"
placementResultRemote.Parent = ReplicatedStorage

-- Configuration Constants
local MAX_ITEMS_PER_PLOT = 100

-- Player data storage

-- Plot assignment tracking (plotId -> player)
local plotAssignments = {} -- {plotId = player.UserId}
local playerPlots = {} -- {player.UserId = plotId}

-- Default inventory for new players.
-- Sell zones are permanent utility items: one per NPC, never bought from the shop.
local DEFAULT_INVENTORY = {
    {itemName = "MiraSellZone", count = 1},
    {itemName = "BrontSellZone", count = 1},
    {itemName = "ElrikSellZone", count = 1},
}

local SELL_ZONE_ITEMS = {
    MiraSellZone = "Mira",
    BrontSellZone = "Bront",
    ElrikSellZone = "Elrik",
}

local function createDefaultInventory()
    local inventory = {}
    for _, itemInfo in ipairs(DEFAULT_INVENTORY) do
        table.insert(inventory, {
            itemName = itemInfo.itemName,
            count = itemInfo.count,
        })
    end
    return inventory
end

local function getTemplateAlias(itemName)
    if itemName == "MineEntrance" then
        return templatesFolder:FindFirstChild("MineEntrace")
    end

    return nil
end

local function createConveyorTemplate()
    local existing = templatesFolder:FindFirstChild("Conveyor")
    if existing then
        return existing
    end

    local conveyor = Instance.new("Model")
    conveyor.Name = "Conveyor"

    local base = Instance.new("Part")
    base.Name = "Belt"
    base.Size = Vector3.new(7.6, 0.45, 7.6)
    base.CFrame = CFrame.new(0, 0.225, 0)
    base.Anchored = true
    base.CanCollide = true
    base.Material = Enum.Material.Metal
    base.Color = Color3.fromRGB(55, 60, 64)
    base.Parent = conveyor

    local arrow = Instance.new("Part")
    arrow.Name = "DirectionArrow"
    arrow.Size = Vector3.new(3.5, 0.08, 1.2)
    arrow.CFrame = CFrame.new(0.65, 0.5, 0)
    arrow.Anchored = true
    arrow.CanCollide = false
    arrow.CanQuery = false
    arrow.CanTouch = false
    arrow.Material = Enum.Material.Neon
    arrow.Color = Color3.fromRGB(80, 190, 255)
    arrow.Parent = conveyor

    local arrowHead = Instance.new("WedgePart")
    arrowHead.Name = "DirectionArrowHead"
    arrowHead.Size = Vector3.new(1.2, 0.08, 1.8)
    arrowHead.CFrame = CFrame.new(2.75, 0.5, 0) * CFrame.Angles(0, 0, math.rad(-90))
    arrowHead.Anchored = true
    arrowHead.CanCollide = false
    arrowHead.CanQuery = false
    arrowHead.CanTouch = false
    arrowHead.Material = Enum.Material.Neon
    arrowHead.Color = Color3.fromRGB(80, 190, 255)
    arrowHead.Parent = conveyor

    conveyor.PrimaryPart = base
    conveyor.Parent = templatesFolder

    return conveyor
end

local function styleCurvedConveyorBase(conveyor)
    local pivotPart = normalizeCurvedConveyorGeometry(conveyor)
    local basePart = getCurvedConveyorVisualPart(conveyor) or conveyor.PrimaryPart

    if pivotPart then
        conveyor.PrimaryPart = pivotPart
    end

    local shouldStyleAsBase = false
    if basePart then
        local color = basePart.Color
        local looksDefaultWhite = color.R > 0.8 and color.G > 0.8 and color.B > 0.8
        shouldStyleAsBase = basePart.Name == "Cube" or looksDefaultWhite
    end

    if basePart and shouldStyleAsBase then
        basePart.Name = "CurveBelt"
        basePart.Material = Enum.Material.Metal
        basePart.Color = Color3.fromRGB(54, 62, 66)
    end

    return basePart
end

local function createCurvedConveyorTemplate()
    local existing = templatesFolder:FindFirstChild("CurvedConveyor")
    if existing then
        styleCurvedConveyorBase(existing)
        return existing
    end

    local conveyor = Instance.new("Model")
    conveyor.Name = "CurvedConveyor"

    local base = Instance.new("Part")
    base.Name = "CurveBelt"
    base.Size = Vector3.new(7.6, 0.45, 7.6)
    base.CFrame = CFrame.new(0, 0.225, 0)
    base.Anchored = true
    base.CanCollide = true
    base.Material = Enum.Material.Metal
    base.Color = Color3.fromRGB(54, 62, 66)
    base.Parent = conveyor

    conveyor.PrimaryPart = base
    conveyor.Parent = templatesFolder

    return conveyor
end

local function createTransportJunctionTemplate(itemName)
    local existing = templatesFolder:FindFirstChild(itemName)
    if existing then
        return existing
    end

    local isSplitter = itemName == "Splitter"
    local isMerger = itemName == "Merger"
    local junction = Instance.new("Model")
    junction.Name = itemName

    local base = Instance.new("Part")
    base.Name = itemName .. "Base"
    base.Size = (isSplitter or isMerger) and Vector3.new(15.6, 0.45, 7.6) or Vector3.new(7.6, 0.45, 7.6)
    base.CFrame = CFrame.new(0, 0.225, 0)
    base.Anchored = true
    base.CanCollide = true
    base.Material = Enum.Material.Metal
    base.Color = isSplitter and Color3.fromRGB(64, 72, 88) or Color3.fromRGB(72, 64, 88)
    base.Parent = junction

    local forward = Instance.new("Part")
    forward.Name = isSplitter and "NorthOutputA" or "NorthOutput"
    forward.Size = isSplitter and Vector3.new(0.85, 0.08, 3.8) or Vector3.new(0.85, 0.08, 3.8)
    forward.CFrame = isSplitter and CFrame.new(-2, 0.52, -1.1) or CFrame.new(0, 0.52, -1.1)
    forward.Anchored = true
    forward.CanCollide = false
    forward.CanQuery = false
    forward.CanTouch = false
    forward.Material = Enum.Material.Neon
    forward.Color = isSplitter and Color3.fromRGB(95, 220, 255) or Color3.fromRGB(205, 165, 255)
    forward.Parent = junction

    local forwardHead = Instance.new("WedgePart")
    forwardHead.Name = isSplitter and "NorthOutputAHead" or "NorthOutputHead"
    forwardHead.Size = Vector3.new(1.0, 0.08, 1.45)
    forwardHead.CFrame = isSplitter and CFrame.new(-2, 0.52, -2.95) * CFrame.Angles(0, math.rad(-90), math.rad(-90)) or CFrame.new(0, 0.52, -2.95) * CFrame.Angles(0, math.rad(-90), math.rad(-90))
    forwardHead.Anchored = true
    forwardHead.CanCollide = false
    forwardHead.CanQuery = false
    forwardHead.CanTouch = false
    forwardHead.Material = Enum.Material.Neon
    forwardHead.Color = forward.Color
    forwardHead.Parent = junction

    if isSplitter then
        local branch = Instance.new("Part")
        branch.Name = "NorthOutputB"
        branch.Size = Vector3.new(0.85, 0.08, 3.8)
        branch.CFrame = CFrame.new(2, 0.54, -1.1)
        branch.Anchored = true
        branch.CanCollide = false
        branch.CanQuery = false
        branch.CanTouch = false
        branch.Material = Enum.Material.Neon
        branch.Color = Color3.fromRGB(120, 255, 170)
        branch.Parent = junction

        local branchHead = Instance.new("WedgePart")
        branchHead.Name = "NorthOutputBHead"
        branchHead.Size = Vector3.new(1.0, 0.08, 1.45)
        branchHead.CFrame = CFrame.new(2, 0.54, -2.95) * CFrame.Angles(0, math.rad(-90), math.rad(-90))
        branchHead.Anchored = true
        branchHead.CanCollide = false
        branchHead.CanQuery = false
        branchHead.CanTouch = false
        branchHead.Material = Enum.Material.Neon
        branchHead.Color = branch.Color
        branchHead.Parent = junction

        local input = Instance.new("Part")
        input.Name = "SouthInput"
        input.Size = Vector3.new(0.85, 0.08, 3.2)
        input.CFrame = CFrame.new(-2, 0.56, 1.0)
        input.Anchored = true
        input.CanCollide = false
        input.CanQuery = false
        input.CanTouch = false
        input.Material = Enum.Material.Neon
        input.Color = Color3.fromRGB(255, 220, 120)
        input.Parent = junction
    else
        for inputIndex, inputX in ipairs({ -2, 2 }) do
            local input = Instance.new("Part")
            input.Name = "SouthInput" .. inputIndex
            input.Size = Vector3.new(0.85, 0.08, 3.2)
            input.CFrame = CFrame.new(inputX, 0.54, 1.0)
            input.Anchored = true
            input.CanCollide = false
            input.CanQuery = false
            input.CanTouch = false
            input.Material = Enum.Material.Neon
            input.Color = inputIndex == 1 and Color3.fromRGB(255, 190, 105) or Color3.fromRGB(255, 225, 135)
            input.Parent = junction
        end
    end

    junction.PrimaryPart = base
    junction.Parent = templatesFolder

    return junction
end

local function createSawmillTemplate()
    local existing = templatesFolder:FindFirstChild("Sawmill")
    if existing then
        return existing
    end

    local sawmill = Instance.new("Model")
    sawmill.Name = "Sawmill"

    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(7.4, 0.45, 7.4)
    base.CFrame = CFrame.new(0, 0.225, 0)
    base.Anchored = true
    base.CanCollide = true
    base.Material = Enum.Material.WoodPlanks
    base.Color = Color3.fromRGB(118, 82, 48)
    base.Parent = sawmill

    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(5.8, 1.5, 3.4)
    body.CFrame = CFrame.new(0, 1.2, 0)
    body.Anchored = true
    body.CanCollide = true
    body.Material = Enum.Material.Metal
    body.Color = Color3.fromRGB(92, 96, 96)
    body.Parent = sawmill

    local blade = Instance.new("Part")
    blade.Name = "Blade"
    blade.Shape = Enum.PartType.Cylinder
    blade.Size = Vector3.new(0.25, 2.5, 2.5)
    blade.CFrame = CFrame.new(0.4, 2.05, 0) * CFrame.Angles(0, 0, math.rad(90))
    blade.Anchored = true
    blade.CanCollide = false
    blade.Material = Enum.Material.Metal
    blade.Color = Color3.fromRGB(205, 210, 212)
    blade.Parent = sawmill

    sawmill.PrimaryPart = base
    sawmill.Parent = templatesFolder

    return sawmill
end

local function createGeneratorTemplate(itemName)
    local existing = templatesFolder:FindFirstChild(itemName)
    if existing then
        return existing
    end

    local itemDef = Definitions.GetItem(itemName)
    if not itemDef or itemDef.type ~= "generator" then
        return nil
    end

    local generator = Instance.new("Model")
    generator.Name = itemName

    local base = Instance.new("Part")
    base.Name = "Base"
    base.Size = Vector3.new(7.4, 0.45, 7.4)
    base.CFrame = CFrame.new(0, 0.225, 0)
    base.Anchored = true
    base.CanCollide = true
    base.Material = Enum.Material.Metal
    base.Color = Color3.fromRGB(44, 50, 54)
    base.Parent = generator

    local casing = Instance.new("Part")
    casing.Name = "Casing"
    casing.Size = Vector3.new(4.6, 2.1, 3.2)
    casing.CFrame = CFrame.new(0, 1.5, 0)
    casing.Anchored = true
    casing.CanCollide = true
    casing.Material = Enum.Material.Metal
    casing.Color = Color3.fromRGB(82, 96, 92)
    casing.Parent = generator

    local coil = Instance.new("Part")
    coil.Name = "PowerCore"
    coil.Shape = Enum.PartType.Cylinder
    coil.Size = Vector3.new(0.8, 2.5, 2.5)
    coil.CFrame = CFrame.new(0, 1.55, 0) * CFrame.Angles(0, 0, math.rad(90))
    coil.Anchored = true
    coil.CanCollide = false
    coil.Material = Enum.Material.Neon
    coil.Color = Color3.fromRGB(255, 206, 86)
    coil.Parent = generator

    local terminal = Instance.new("Part")
    terminal.Name = "Terminal"
    terminal.Size = Vector3.new(1.2, 0.35, 2.6)
    terminal.CFrame = CFrame.new(2.1, 2.75, 0)
    terminal.Anchored = true
    terminal.CanCollide = false
    terminal.Material = Enum.Material.Neon
    terminal.Color = Color3.fromRGB(116, 218, 255)
    terminal.Parent = generator

    generator.PrimaryPart = base
    generator.Parent = templatesFolder

    return generator
end

local SELL_ZONE_COLORS = {
    Mira = Color3.fromRGB(58, 150, 84),
    Bront = Color3.fromRGB(139, 96, 54),
    Elrik = Color3.fromRGB(118, 126, 134),
}

local function createSellZoneTemplate(itemName)
    local existing = templatesFolder:FindFirstChild(itemName)
    if existing then
        return existing
    end

    local itemDef = Definitions.GetItem(itemName)
    if not itemDef or itemDef.type ~= "sell_zone" or not itemDef.npcName then
        return nil
    end

    local npcName = itemDef.npcName
    local zone = Instance.new("Model")
    zone.Name = itemName
    zone:SetAttribute("NPCName", npcName)

    local base = Instance.new("Part")
    base.Name = "SellZone"
    base.Size = Vector3.new(7.6, 0.14, 7.6)
    base.CFrame = CFrame.new(0, 0.07, 0)
    base.Anchored = true
    base.CanCollide = true
    base.Material = Enum.Material.Neon
    base.Color = SELL_ZONE_COLORS[npcName] or Color3.fromRGB(82, 170, 95)
    base.Transparency = 0.2
    base.Parent = zone

    local marker = Instance.new("Part")
    marker.Name = "Marker"
    marker.Size = Vector3.new(3.5, 0.08, 3.5)
    marker.CFrame = CFrame.new(0, 0.2, 0)
    marker.Anchored = true
    marker.CanCollide = false
    marker.CanQuery = false
    marker.CanTouch = false
    marker.Material = Enum.Material.SmoothPlastic
    marker.Color = Color3.fromRGB(245, 245, 245)
    marker.Transparency = 0.55
    marker.Parent = zone

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "SellZoneLabel"
    billboard.Size = UDim2.fromOffset(110, 28)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = base

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 0.25
    label.BackgroundColor3 = Color3.fromRGB(18, 20, 22)
    label.BorderSizePixel = 0
    label.Text = npcName .. " Sell"
    label.TextColor3 = Color3.fromRGB(245, 248, 250)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard

    zone.PrimaryPart = base
    zone.Parent = templatesFolder

    return zone
end

local function ensureItemTemplate(itemName)
    local template = templatesFolder:FindFirstChild(itemName)
    if template then
        return template
    end

    local alias = getTemplateAlias(itemName)
    if alias then
        alias.Name = itemName
        return alias
    end

    if itemName == "Conveyor" then
        return createConveyorTemplate()
    end

    if itemName == "CurvedConveyor" then
        return createCurvedConveyorTemplate()
    end

    if itemName == "Splitter" or itemName == "Merger" then
        return createTransportJunctionTemplate(itemName)
    end

    if itemName == "Sawmill" then
        return createSawmillTemplate()
    end

    local itemDef = Definitions.GetItem(itemName)
    if itemDef and itemDef.type == "generator" then
        return createGeneratorTemplate(itemName)
    end

    if itemDef and itemDef.type == "sell_zone" then
        return createSellZoneTemplate(itemName)
    end

    return nil
end

local function ensurePurchasableTemplates()
    for itemName, itemDef in pairs(Definitions.GetAllItems()) do
        if itemDef.cost and not itemDef.isProduction then
            ensureItemTemplate(itemName)
        end
    end

    for _, itemInfo in ipairs(DEFAULT_INVENTORY) do
        ensureItemTemplate(itemInfo.itemName)
    end
end

local function notifyInventoryUpdated(player)
    inventoryUpdatedRemote:FireClient(player)
end

local function sendShopResult(player, success, action, itemName, message, balance)
    shopTransactionResultRemote:FireClient(player, {
        success = success,
        action = action,
        itemName = itemName,
        message = message,
        money = balance,
    })
end

local function sendPlacementResult(player, success, itemName, message)
    placementResultRemote:FireClient(player, {
        success = success,
        itemName = itemName,
        message = message,
    })
end

local function isValidInventoryItem(itemName)
    local itemDef = Definitions.GetItem(itemName)
    return itemDef ~= nil and itemDef.isProduction ~= true
end

local function isSellZoneItem(itemName)
    local itemDef = Definitions.GetItem(itemName)
    return itemDef ~= nil and itemDef.type == "sell_zone" and itemDef.npcName ~= nil
end

local function getSellZoneNpcName(itemName)
    local itemDef = Definitions.GetItem(itemName)
    return itemDef and itemDef.type == "sell_zone" and itemDef.npcName or nil
end

local function normalizeInventory(inventory)
    local totals = {}
    local order = {}

    for _, existingItem in ipairs(inventory or {}) do
        local itemName = existingItem.itemName
        local count = tonumber(existingItem.count) or 0

        if itemName and isValidInventoryItem(itemName) and count > 0 then
            if not totals[itemName] then
                totals[itemName] = 0
                table.insert(order, itemName)
            end

            totals[itemName] = totals[itemName] + count
        elseif itemName then
            print("[INVENTORY] Removed invalid inventory entry: " .. tostring(itemName))
        end
    end

    local normalized = {}
    for _, itemName in ipairs(order) do
        local count = totals[itemName]
        if isSellZoneItem(itemName) then
            count = math.min(count, 1)
        end

        table.insert(normalized, {
            itemName = itemName,
            count = count,
        })
    end

    return normalized
end

local function getInventoryCount(inventory, itemName)
    for _, invItem in ipairs(inventory or {}) do
        if invItem.itemName == itemName then
            return tonumber(invItem.count) or 0
        end
    end

    return 0
end

local function setInventoryCount(inventory, itemName, count)
    count = math.max(0, math.floor(tonumber(count) or 0))

    for index = #inventory, 1, -1 do
        local invItem = inventory[index]
        if invItem.itemName == itemName then
            if count <= 0 then
                table.remove(inventory, index)
            else
                invItem.count = count
            end
            return
        end
    end

    if count > 0 then
        table.insert(inventory, {itemName = itemName, count = count})
    end
end

local function addItemToInventory(player, itemName, count)
    local data = playerData[player]
    if not data or not isValidInventoryItem(itemName) then
        return false, 0
    end

    data.inventory = normalizeInventory(data.inventory)
    count = count or 1

    for _, invItem in ipairs(data.inventory) do
        if invItem.itemName == itemName then
            invItem.count = invItem.count + count
            return true, invItem.count
        end
    end

    table.insert(data.inventory, {itemName = itemName, count = count})
    return true, count
end

local function removeItemFromInventory(player, itemName, count)
    local data = playerData[player]
    if not data then
        return false, 0
    end

    data.inventory = normalizeInventory(data.inventory)
    count = count or 1

    for i, invItem in ipairs(data.inventory) do
        if invItem.itemName == itemName and invItem.count >= count then
            invItem.count = invItem.count - count
            local remaining = invItem.count

            if invItem.count <= 0 then
                table.remove(data.inventory, i)
                remaining = 0
            end

            return true, remaining
        end
    end

    return false, 0
end

ensurePurchasableTemplates()

local function reconcileSellZoneOwnership(player)
    local data = playerData[player]
    if not data then
        return
    end

    data.inventory = normalizeInventory(data.inventory)

    local placedByNpc = {}
    for index = #data.placedItems, 1, -1 do
        local placedItem = data.placedItems[index]
        if placedItem and placedItem.Parent then
            local itemName = placedItem:GetAttribute("ItemName")
            local npcName = getSellZoneNpcName(itemName)
            if npcName then
                if placedByNpc[npcName] then
                    SellSystem.UnregisterPlacedItem(player, placedItem)
                    PowerSystem.UnregisterPlacedItem(player, placedItem)
                    placedItem:Destroy()
                    table.remove(data.placedItems, index)
                else
                    placedByNpc[npcName] = true
                end
            end
        elseif placedItem then
            table.remove(data.placedItems, index)
        end
    end

    for itemName, npcName in pairs(SELL_ZONE_ITEMS) do
        if placedByNpc[npcName] then
            setInventoryCount(data.inventory, itemName, 0)
        else
            setInventoryCount(data.inventory, itemName, 1)
        end
    end
end

local function hasPlacedSellZoneForNpc(player, npcName)
    local data = playerData[player]
    if not data then
        return false
    end

    for _, placedItem in ipairs(data.placedItems) do
        if placedItem and placedItem.Parent then
            local itemName = placedItem:GetAttribute("ItemName")
            if getSellZoneNpcName(itemName) == npcName then
                return true
            end
        end
    end

    return false
end

local function countPlacedMachines(player)
    local data = playerData[player]
    if not data then
        return 0
    end

    local count = 0
    for _, placedItem in ipairs(data.placedItems) do
        if placedItem and placedItem.Parent then
            if Definitions.GetMachine(placedItem:GetAttribute("ItemName")) then
                count += 1
            end
        end
    end

    return count
end

local function isSaveablePlacedItem(itemName)
    local itemDef = Definitions.GetItem(itemName)
    if not itemDef or itemDef.isProduction == true then
        return false
    end

    return itemDef.type ~= nil or itemDef.isMachine == true or itemDef.cost ~= nil
end

-- Function to get plot by ID
local function getPlotById(plotId)
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    return plotsFolder:FindFirstChild("Plot" .. plotId)
end

-- Function to get plot info by ID
local function getPlotInfo(plotId)
    local plot = getPlotById(plotId)
    if not plot then return nil end
    return {
        id = plotId,
        position = plot.Position,
        size = plot.Size
    }
end

-- Function to check if position is within a specific plot's bounds
local function isWithinPlot(position, itemSize, plotId)
    local plotInfo = getPlotInfo(plotId)
    if not plotInfo then return false end
    
    local halfPlotSize = plotInfo.size / 2
    local halfItemSize = itemSize / 2
    
    local minX = plotInfo.position.X - halfPlotSize.X + halfItemSize.X
    local maxX = plotInfo.position.X + halfPlotSize.X - halfItemSize.X
    local minZ = plotInfo.position.Z - halfPlotSize.Z + halfItemSize.Z
    local maxZ = plotInfo.position.Z + halfPlotSize.Z - halfItemSize.Z
    
    return position.X >= minX and position.X <= maxX and
           position.Z >= minZ and position.Z <= maxZ
end

-- Function to find a free plot
local function findFreePlot()
    for plotId = 1, MAX_PLOTS do
        if not plotAssignments[plotId] then
            return plotId
        end
    end
    return nil
end

-- Function to create plot label (BillboardGui with player name and face)
local function createPlotLabel(plot, player)
    -- Remove existing label if any
    local existingLabel = plot:FindFirstChild("PlotLabel")
    if existingLabel then
        existingLabel.Parent = nil
    end
    
    -- Create a Part to hold the BillboardGui
    local labelPart = Instance.new("Part")
    labelPart.Name = "PlotLabel"
    labelPart.Size = Vector3.new(0.1, 0.1, 0.1)
    labelPart.Transparency = 1
    labelPart.CanCollide = false
    labelPart.Anchored = true
    labelPart.Position = plot.Position + Vector3.new(0, plot.Size.Y/2 + PLOT_LABEL_HEIGHT, 0)
    labelPart.Parent = plot
    
    -- Create BillboardGui
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "PlotBillboard"
    billboard.Size = UDim2.new(0, 400, 0, 60)
    billboard.StudsOffset = Vector3.new(0, 0, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = labelPart
    
    -- Create main frame
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel = 0
    frame.Parent = billboard
    
    -- Add rounded corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame
    
    -- Add stroke
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.new(1, 1, 1)
    stroke.Thickness = 2
    stroke.Transparency = 0.5
    stroke.Parent = frame
    
    -- Create player face image
    local faceImage = Instance.new("ImageLabel")
    faceImage.Size = UDim2.new(0, 50, 0, 50)
    faceImage.Position = UDim2.new(0, 5, 0.5, -25)
    faceImage.BackgroundColor3 = Color3.new(1, 1, 1)
    faceImage.BackgroundTransparency = 0.5
    faceImage.Image = Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
    faceImage.Parent = frame
    
    -- Add rounded corners to face
    local faceCorner = Instance.new("UICorner")
    faceCorner.CornerRadius = UDim.new(0, 25)
    faceCorner.Parent = faceImage
    
    -- Create text label
    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, -70, 1, 0)
    textLabel.Position = UDim2.new(0, 60, 0, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = player.Name .. "'s Plot"
    textLabel.TextColor3 = Color3.new(1, 1, 1)
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.GothamBold
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.Parent = frame
    
    return labelPart
end

-- Function to teleport player to their plot
local function teleportToPlot(player, plotId)
    local plot = getPlotById(plotId)
    if not plot then return end
    
    -- Wait for character to load
    local character = player.Character or player.CharacterAdded:Wait()
    if not character then return end
    
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
    if not humanoidRootPart then return end
    
    -- Teleport to center of plot, slightly above it
    local teleportPosition = plot.Position + Vector3.new(0, plot.Size.Y/2 + 5, 0)
    humanoidRootPart.CFrame = CFrame.new(teleportPosition)
    
    print("Teleported " .. player.Name .. " to Plot " .. plotId)
end

-- Function to protect plot from deletion
local function protectPlot(plot)
    plot.Locked = true -- Prevent selection in Studio
    plot:SetAttribute("IsPlot", true) -- Mark as protected plot
end

-- Function to assign a plot to a player
local function assignPlotToPlayer(player)
    -- Check if player already has a plot
    if playerPlots[player.UserId] then
        return playerPlots[player.UserId]
    end
    
    -- Find a free plot
    local freePlotId = findFreePlot()
    if not freePlotId then
        return nil -- No free plots
    end
    
    -- Assign the plot
    plotAssignments[freePlotId] = player.UserId
    playerPlots[player.UserId] = freePlotId
    
    -- Update plot visual indicator
    local plot = getPlotById(freePlotId)
    if plot then
        plot:SetAttribute("Owner", player.UserId)
        plot:SetAttribute("OwnerName", player.Name)
        
        -- Protect the plot
        protectPlot(plot)
        
        -- Create plot label
        createPlotLabel(plot, player)
    end
    
    return freePlotId
end

-- Function to release a player's plot
local function releasePlayerPlot(player)
    local plotId = playerPlots[player.UserId]
    if plotId then
        plotAssignments[plotId] = nil
        playerPlots[player.UserId] = nil
        
        -- Update plot visual indicator
        local plot = getPlotById(plotId)
        if plot then
            plot:SetAttribute("Owner", nil)
            plot:SetAttribute("OwnerName", nil)
            
            -- Remove plot label
            local label = plot:FindFirstChild("PlotLabel")
            if label then
                label.Parent = nil
            end
        end
    end
end

local function cloneInventoryForSave(inventory)
    local normalized = normalizeInventory(inventory or DEFAULT_INVENTORY)
    local cloned = {}

    for _, item in ipairs(normalized) do
        table.insert(cloned, {
            itemName = item.itemName,
            count = math.max(0, math.floor(tonumber(item.count) or 0)),
        })
    end

    return cloned
end

local function getLegacyPosition(itemInfo)
    local position = itemInfo and itemInfo.position
    if typeof(position) == "Vector3" then
        return position
    end

    if type(position) == "table" then
        local x = tonumber(position[1] or position.x or position.X)
        local y = tonumber(position[2] or position.y or position.Y)
        local z = tonumber(position[3] or position.z or position.Z)
        if x and y and z then
            return Vector3.new(x, y, z)
        end
    end

    return nil
end

local function serializePlacedItem(item)
    if not item or not item.Parent then
        return nil
    end

    local itemName = item:GetAttribute("ItemName")
    if not isSaveablePlacedItem(itemName) then
        return nil
    end

    local cellX = item:GetAttribute("CellX")
    local cellZ = item:GetAttribute("CellZ")
    if cellX == nil or cellZ == nil then
        return nil
    end

    local itemDef = Definitions.GetItem(itemName)

    return {
        itemName = itemName,
        cellX = math.floor(tonumber(cellX) or 0),
        cellZ = math.floor(tonumber(cellZ) or 0),
        rotation = normalizeRotation(item:GetAttribute("Rotation")),
        scaleFactor = sanitizeScaleFactor(itemName, item:GetAttribute("ScaleFactor")),
        cellsX = math.max(1, math.floor(tonumber(item:GetAttribute("CellsX")) or 1)),
        cellsZ = math.max(1, math.floor(tonumber(item:GetAttribute("CellsZ")) or 1)),
        npcName = item:GetAttribute("NPCName") or (itemDef and itemDef.npcName) or nil,
    }
end

local function migrateSavedPlacedItem(itemInfo, plotId)
    if type(itemInfo) ~= "table" then
        return nil
    end

    local itemName = itemInfo.itemName or itemInfo.name
    if not isSaveablePlacedItem(itemName) then
        return nil
    end

    local rotation = normalizeRotation(itemInfo.rotation)
    local cellsX = tonumber(itemInfo.cellsX)
    local cellsZ = tonumber(itemInfo.cellsZ)
    if not cellsX or not cellsZ then
        cellsX, cellsZ = getRotatedFootprint(itemName, rotation)
    end

    cellsX = math.max(1, math.floor(cellsX))
    cellsZ = math.max(1, math.floor(cellsZ))

    local cellX = itemInfo.cellX
    local cellZ = itemInfo.cellZ
    if cellX == nil or cellZ == nil then
        local legacyPosition = getLegacyPosition(itemInfo)
        local plotInfo = plotId and getPlotInfo(plotId)
        if legacyPosition and plotInfo then
            cellX = roundToNearestCell((legacyPosition.X - plotInfo.position.X) / GRID_UNIT_SIZE - cellsX / 2)
            cellZ = roundToNearestCell((legacyPosition.Z - plotInfo.position.Z) / GRID_UNIT_SIZE - cellsZ / 2)
        end
    end

    if cellX == nil or cellZ == nil then
        return nil
    end

    local itemDef = Definitions.GetItem(itemName)

    return {
        itemName = itemName,
        cellX = math.floor(tonumber(cellX) or 0),
        cellZ = math.floor(tonumber(cellZ) or 0),
        rotation = rotation,
        scaleFactor = sanitizeScaleFactor(itemName, itemInfo.scaleFactor),
        cellsX = cellsX,
        cellsZ = cellsZ,
        npcName = itemInfo.npcName or itemInfo.NPCName or (itemDef and itemDef.npcName) or nil,
    }
end

local function migratePlotSaveData(rawData)
    if type(rawData) ~= "table" then
        return nil
    end

    local plotId = tonumber(rawData.plotId)
    local migrated = {
        version = PLOT_SAVE_VERSION,
        plotId = plotId,
        inventory = cloneInventoryForSave(rawData.inventory),
        placedItems = {},
        lastSaved = tonumber(rawData.lastSaved) or tick(),
    }

    for _, itemInfo in ipairs(rawData.placedItems or {}) do
        local migratedItem = migrateSavedPlacedItem(itemInfo, plotId)
        if migratedItem then
            table.insert(migrated.placedItems, migratedItem)
        end
    end

    return migrated
end

local function createPlotSaveData(player, plotId)
    local data = playerData[player]
    if not data then
        return nil
    end

    data.inventory = normalizeInventory(data.inventory)

    local saveData = {
        version = PLOT_SAVE_VERSION,
        plotId = plotId,
        inventory = cloneInventoryForSave(data.inventory),
        placedItems = {},
        lastSaved = tick(),
    }

    for _, item in ipairs(data.placedItems) do
        local savedItem = serializePlacedItem(item)
        if savedItem then
            table.insert(saveData.placedItems, savedItem)
        end
    end

    return saveData
end

-- Function to save player data to DataStore
local function savePlayerData(player)
    local plotId = playerPlots[player.UserId]
    if not plotId then return end

    local saveData = createPlotSaveData(player, plotId)
    if not saveData then return end

    local key = getPlayerDataKey(player)
    local lastErr = nil

    for attempt = 1, MAX_DATASTORE_RETRIES do
        local success, err = pcall(function()
            playerDataStore:SetAsync(key, saveData)
        end)

        if success then
            fallbackDataStore[key] = saveData
            print("[SAVED] " .. player.Name .. " - " .. #saveData.placedItems .. " items on Plot " .. plotId .. " (v" .. saveData.version .. ")")
            return true
        end

        lastErr = err
        warn("[ERROR] Save attempt " .. attempt .. " failed for " .. player.Name .. ": " .. tostring(err))
        if attempt < MAX_DATASTORE_RETRIES then
            task.wait(DATASTORE_RETRY_DELAY)
        end
    end

    fallbackDataStore[key] = saveData
    warn("[ERROR] Failed to save data for " .. player.Name .. " after " .. MAX_DATASTORE_RETRIES .. " attempts; using fallback cache: " .. tostring(lastErr))
    return false
end

-- Function to load player data from DataStore
local function loadPlayerData(player)
    local key = getPlayerDataKey(player)
    local lastErr = nil

    for attempt = 1, MAX_DATASTORE_RETRIES do
        local success, data = pcall(function()
            return playerDataStore:GetAsync(key)
        end)

        if success then
            if data then
                local migrated = migratePlotSaveData(data)
                if migrated then
                    fallbackDataStore[key] = migrated
                    print("[LOADED] " .. player.Name .. " - " .. #migrated.placedItems .. " items from DataStore (v" .. tostring(data.version or 1) .. " -> v" .. migrated.version .. ")")
                    return migrated
                end
            end
            break
        end

        lastErr = data
        warn("[ERROR] Load attempt " .. attempt .. " failed for " .. player.Name .. ": " .. tostring(data))
        if attempt < MAX_DATASTORE_RETRIES then
            task.wait(DATASTORE_RETRY_DELAY)
        end
    end

    local fallbackData = fallbackDataStore[key]
    if fallbackData then
        local migrated = migratePlotSaveData(fallbackData)
        if migrated then
            print("[LOADED] " .. player.Name .. " - " .. #migrated.placedItems .. " items from fallback")
            return migrated
        end
    end

    if lastErr then
        warn("[ERROR] No plot data loaded for " .. player.Name .. ": " .. tostring(lastErr))
    end

    return nil
end

-- Function to migrate old inventory to new one (adds missing items and removes invalid ones)
local function migrateInventory(oldInventory)
    return cloneInventoryForSave(oldInventory or DEFAULT_INVENTORY)
end

-- Function to spawn saved items
local function spawnSavedItems(player, itemsData, plotId)
    local data = playerData[player]
    if not data then return end
    
    for _, itemInfo in ipairs(itemsData) do
        local template = ensureItemTemplate(itemInfo.itemName)
        if template then
            local newItem = template:Clone()
            
            -- Remove template-only runtime artifacts from the model.
            removeRuntimeArtifacts(newItem)
            
            -- Apply scale
            local scaleFactor = sanitizeScaleFactor(itemInfo.itemName, itemInfo.scaleFactor)
            local currentScale = newItem:GetScale()
            newItem:ScaleTo(currentScale * scaleFactor)
            applyItemVisualAdjustments(newItem, itemInfo.itemName)
            
            -- Enable collisions and anchor
            for _, desc in ipairs(newItem:GetDescendants()) do
                if desc:IsA("BasePart") then
                    desc.CanCollide = true
                    desc.Anchored = true
                end
            end
            
            -- Position the item from its saved grid footprint. Legacy saves are migrated before this point.
            local rotation = normalizeRotation(itemInfo.rotation)
            local cellX = tonumber(itemInfo.cellX)
            local cellZ = tonumber(itemInfo.cellZ)
            local cellsX = tonumber(itemInfo.cellsX)
            local cellsZ = tonumber(itemInfo.cellsZ)
            if not cellsX or not cellsZ then
                cellsX, cellsZ = getRotatedFootprint(itemInfo.itemName, rotation)
            end

            cellsX = math.max(1, math.floor(cellsX))
            cellsZ = math.max(1, math.floor(cellsZ))

            local plotInfo = getPlotInfo(plotId)
            if not plotInfo or cellX == nil or cellZ == nil then
                warn("[LOAD] Skipped " .. tostring(itemInfo.itemName) .. " for " .. player.Name .. ": missing plot or grid cell")
                newItem:Destroy()
                continue
            end

            cellX = math.floor(cellX)
            cellZ = math.floor(cellZ)
            if not areCellsValid(cellX, cellZ, cellsX, cellsZ, plotInfo) or isAreaOccupied(player, cellX, cellZ, cellsX, cellsZ) then
                warn("[LOAD] Skipped " .. tostring(itemInfo.itemName) .. " for " .. player.Name .. ": invalid or occupied grid cell")
                newItem:Destroy()
                continue
            end

            local plotTopY = plotInfo.position.Y + plotInfo.size.Y / 2
            local footprintCenter = getFootprintCenter(cellX, cellZ, cellsX, cellsZ, plotInfo, plotTopY)
            local _, size = newItem:GetBoundingBox()
            local position = Vector3.new(footprintCenter.X, plotTopY + getAdjustedItemHeight(itemInfo.itemName, size.Y * scaleFactor) / 2, footprintCenter.Z)

            if itemInfo.itemName == "CurvedConveyor" then
                pivotModelToFootprint(newItem, footprintCenter, plotTopY, rotation)
            else
                newItem:PivotTo(CFrame.new(position) * getRotationCFrame(rotation))
            end
            
            -- Set attributes
            local itemDef = Definitions.GetItem(itemInfo.itemName)
            newItem:SetAttribute("Owner", player.UserId)
            newItem:SetAttribute("ItemName", itemInfo.itemName)
            newItem:SetAttribute("CellsX", cellsX)
            newItem:SetAttribute("CellsZ", cellsZ)
            newItem:SetAttribute("CellX", cellX)
            newItem:SetAttribute("CellZ", cellZ)
            newItem:SetAttribute("Rotation", rotation)
            newItem:SetAttribute("ScaleFactor", scaleFactor)
            local npcName = itemInfo.npcName or (itemDef and itemDef.npcName)
            if npcName then
                newItem:SetAttribute("NPCName", npcName)
            end
            
            -- Parent to player's items folder
            local playerItemsFolder = workspace:FindFirstChild("PlayerItems_" .. player.UserId)
            if playerItemsFolder then
                newItem.Parent = playerItemsFolder
                table.insert(data.placedItems, newItem)
                PowerSystem.RegisterPlacedItem(player, newItem)
                MachineSystem.RegisterPlacedItem(player, newItem)
                SellSystem.RegisterPlacedItem(player, newItem)
            end
        end
    end
end

-- Function to get item template
local function getItemTemplate(itemName)
    return ensureItemTemplate(itemName)
end

-- Function to get item bounding box size
local function getItemSize(item)
    local cframe, size = item:GetBoundingBox()
    return size
end

-- Handle player joining
local function onPlayerAdded(player)
    -- Initialize player progress (money, reputation, etc.)
    local progress = PlayerProgress.GetPlayerProgress(player)
    print("[PlayerProgress] Loaded progress for " .. player.Name .. " - Money: " .. progress.money)
    -- Try to load saved data
    local savedData = loadPlayerData(player)
    
    -- Assign a plot
    local plotId
    if savedData and savedData.plotId then
        -- Player had a plot, try to reassign it
        if not plotAssignments[savedData.plotId] then
            plotId = savedData.plotId
            plotAssignments[plotId] = player.UserId
            playerPlots[player.UserId] = plotId
        else
            -- Plot was taken, assign a new one
            plotId = assignPlotToPlayer(player)
        end
    else
        -- New player, assign a free plot
        plotId = assignPlotToPlayer(player)
    end
    
    if not plotId then
        warn("No free plots available for " .. player.Name)
        return
    end
    
    -- Initialize player data
    if savedData then
        playerData[player] = {
            inventory = migrateInventory(savedData.inventory),
            placedItems = {}
        }
    else
        playerData[player] = {
            inventory = createDefaultInventory(),
            placedItems = {}
        }
    end
    
    -- Create a folder for player's placed items
    local playerItemsFolder = workspace:FindFirstChild("PlayerItems_" .. player.UserId)
    if not playerItemsFolder then
        playerItemsFolder = Instance.new("Folder")
        playerItemsFolder.Name = "PlayerItems_" .. player.UserId
        playerItemsFolder.Parent = workspace
    end
    
    -- Spawn saved items if any
    if savedData and savedData.placedItems then
        spawnSavedItems(player, savedData.placedItems, plotId)
    end
    reconcileSellZoneOwnership(player)
    
    -- Teleport player to their plot when character spawns
    if player.Character then
        teleportToPlot(player, plotId)
    else
        player.CharacterAdded:Connect(function()
            teleportToPlot(player, plotId)
        end)
    end
    
    print("Inventory initialized for " .. player.Name .. " on Plot " .. plotId)
    notifyInventoryUpdated(player)
end

-- Handle player leaving
local function onPlayerRemoving(player)
    -- Save player data before leaving
    savePlayerData(player)

    MachineSystem.ClearPlayer(player)
    PowerSystem.ClearPlayer(player)
    SellSystem.ClearPlayer(player)
    
    -- Clear player progress from cache
    PlayerProgress.ClearPlayerData(player)
    
    -- Clean up placed items from workspace (but keep in DataStore)
    local playerItemsFolder = workspace:FindFirstChild("PlayerItems_" .. player.UserId)
    if playerItemsFolder then
        playerItemsFolder.Parent = nil -- Remove from workspace but don't destroy
    end
    
    -- Release the plot (but keep assignment for reconnection)
    -- Option: Keep plot assigned for a short time to allow reconnection
    -- For now, we release it but save the plotId in DataStore
    releasePlayerPlot(player)
    
    playerData[player] = nil
end

-- Handle place item request (now with footprint cells and rotation)
placeItemRemote.OnServerEvent:Connect(function(player, itemName, position, scaleFactor, gridUnit, cellsX, cellsZ, rotation, cellX, cellZ)
    local data = playerData[player]
    if not data then return end
    data.inventory = normalizeInventory(data.inventory)
    reconcileSellZoneOwnership(player)
    
    -- Get player's assigned plot
    local plotId = playerPlots[player.UserId]
    if not plotId then
        return false, "No plot assigned"
    end
    
    -- Check if player has already reached the max items limit
    if #data.placedItems >= MAX_ITEMS_PER_PLOT then
        print(player.Name .. " tried to place " .. itemName .. " but has reached max items limit (" .. MAX_ITEMS_PER_PLOT .. ")")
        return false, "Max items placed: " .. MAX_ITEMS_PER_PLOT
    end
    
    -- Check if player has this item
    local inventoryItem = nil
    local inventoryIndex = nil
    for i, item in ipairs(data.inventory) do
        if item.itemName == itemName and item.count > 0 then
            inventoryItem = item
            inventoryIndex = i
            break
        end
    end
    
    if not inventoryItem then
        return false, "Item not in inventory"
    end

    local sellZoneNpcName = getSellZoneNpcName(itemName)
    if sellZoneNpcName and hasPlacedSellZoneForNpc(player, sellZoneNpcName) then
        reconcileSellZoneOwnership(player)
        return false, "Only one sell zone per NPC is allowed"
    end

    if Definitions.GetMachine(itemName) then
        local canPlace, message = PowerSystem.CanPlaceMachine(player, itemName)
        if not canPlace then
            message = message or "Not enough Power"
            sendPlacementResult(player, false, itemName, message)
            return false, message
        end
    end
    
    -- Get template and check size
    local template = ensureItemTemplate(itemName)
    if not template then
        return false, "Item template not found"
    end
    
    -- Apply scaling if provided
    if not scaleFactor then scaleFactor = 1 end
    scaleFactor = sanitizeScaleFactor(itemName, scaleFactor)
    if not gridUnit then gridUnit = getGridUnitSize() end
    rotation = normalizeRotation(rotation)
    cellsX, cellsZ = getRotatedFootprint(itemName, rotation)
    cellX = math.floor(tonumber(cellX) or 0)
    cellZ = math.floor(tonumber(cellZ) or 0)

    local plotInfo = getPlotInfo(plotId)
    if not areCellsValid(cellX, cellZ, cellsX, cellsZ, plotInfo) then
        return false, "Position outside your plot bounds"
    end

    if isAreaOccupied(player, cellX, cellZ, cellsX, cellsZ) then
        return false, "Space occupied"
    end
    
    -- Check if position is within player's plot (considering rotated grid footprint)
    local _, size = template:GetBoundingBox()
    local itemSize = Vector3.new(cellsX * GRID_UNIT_SIZE, getAdjustedItemHeight(itemName, size.Y * scaleFactor), cellsZ * GRID_UNIT_SIZE)
    local plotTopY = plotInfo.position.Y + plotInfo.size.Y / 2
    local footprintCenter = getFootprintCenter(cellX, cellZ, cellsX, cellsZ, plotInfo, plotTopY)
    position = Vector3.new(footprintCenter.X, plotTopY + itemSize.Y / 2, footprintCenter.Z)
    if not isWithinPlot(position, itemSize, plotId) then
        return false, "Position outside your plot bounds"
    end
    
    -- Place the item
    local newItem = template:Clone()
    
    -- Remove template-only runtime artifacts from the model.
    removeRuntimeArtifacts(newItem)
    
    -- Apply client-computed scale for the item's grid footprint.
    local currentScale = newItem:GetScale()
    newItem:ScaleTo(currentScale * scaleFactor)
    applyItemVisualAdjustments(newItem, itemName)
    
    -- Enable collisions on all parts
    for _, desc in ipairs(newItem:GetDescendants()) do
        if desc:IsA("BasePart") then
            desc.CanCollide = true
            desc.Anchored = true -- Anchor the item so it doesn't fall
        end
    end
    
    if itemName == "CurvedConveyor" then
        pivotModelToFootprint(newItem, footprintCenter, plotTopY, rotation)
    else
        newItem:PivotTo(CFrame.new(position) * getRotationCFrame(rotation))
    end
    newItem.Parent = workspace:FindFirstChild("PlayerItems_" .. player.UserId)
    
    newItem:SetAttribute("Owner", player.UserId)
    newItem:SetAttribute("ItemName", itemName)
    newItem:SetAttribute("CellsX", cellsX) -- Store how many cells in X direction
    newItem:SetAttribute("CellsZ", cellsZ) -- Store how many cells in Z direction
    newItem:SetAttribute("CellX", cellX)
    newItem:SetAttribute("CellZ", cellZ)
    newItem:SetAttribute("Rotation", rotation)
    newItem:SetAttribute("ScaleFactor", scaleFactor) -- Store the scale factor
    local placedItemDef = Definitions.GetItem(itemName)
    if placedItemDef and placedItemDef.npcName then
        newItem:SetAttribute("NPCName", placedItemDef.npcName)
    end
    
    -- Decrease inventory count
    inventoryItem.count = inventoryItem.count - 1
    if inventoryItem.count <= 0 then
        table.remove(data.inventory, inventoryIndex)
    end
    
    table.insert(data.placedItems, newItem)
    PowerSystem.RegisterPlacedItem(player, newItem)
    MachineSystem.RegisterPlacedItem(player, newItem)
    SellSystem.RegisterPlacedItem(player, newItem)
    reconcileSellZoneOwnership(player)
    
    -- Save after placing
    savePlayerData(player)
    notifyInventoryUpdated(player)
    
    if shouldLogItemAction(itemName) then
        print(player.Name .. " placed " .. itemName .. " at " .. tostring(position) .. " on Plot " .. plotId)
    end
    return true
end)

-- Handle delete item request
deleteItemRemote.OnServerEvent:Connect(function(player, item)
    local data = playerData[player]
    if not data then return end
    data.inventory = normalizeInventory(data.inventory)
    
    -- Check if item exists and belongs to player
    if not item or not item.Parent then return end
    
    -- Prevent deletion of plots
    if item:GetAttribute("IsPlot") then
        warn(player.Name .. " tried to delete a plot - not allowed!")
        return
    end
    
    if item:GetAttribute("Owner") ~= player.UserId then
        warn(player.Name .. " tried to delete an item they don't own")
        return
    end
    
    local itemName = item:GetAttribute("ItemName") or "Unknown"
    MachineSystem.UnregisterPlacedItem(player, item)
    PowerSystem.UnregisterPlacedItem(player, item)
    SellSystem.UnregisterPlacedItem(player, item)
    
    -- Remove from placed items list
    for i, placedItem in ipairs(data.placedItems) do
        if placedItem == item then
            table.remove(data.placedItems, i)
            break
        end
    end
    
    -- Remove the item
    item.Parent = nil
    
    -- Add back to inventory
    local foundItem = nil
    for _, invItem in ipairs(data.inventory) do
        if invItem.itemName == itemName then
            foundItem = invItem
            break
        end
    end
    
    if foundItem then
        foundItem.count = foundItem.count + 1
    else
        table.insert(data.inventory, {itemName = itemName, count = 1})
    end
    reconcileSellZoneOwnership(player)
    
    -- No refund - items are free to delete
    if shouldLogItemAction(itemName) then
        print(player.Name .. " deleted " .. itemName .. " and removed it from world")
    end
    
    -- Save after deleting
    savePlayerData(player)
    notifyInventoryUpdated(player)
end)

-- Handle rotate item request
rotateItemRemote.OnServerEvent:Connect(function(player, itemOrPosition)
    local data = playerData[player]
    if not data then return end

    local item = nil

    if typeof(itemOrPosition) == "Instance" then
        item = itemOrPosition
    elseif typeof(itemOrPosition) == "Vector3" then
        for _, placedItem in ipairs(data.placedItems) do
            if placedItem and placedItem.Parent and (placedItem:GetPivot().Position - itemOrPosition).Magnitude < 0.1 then
                item = placedItem
                break
            end
        end
    end

    if not item or not item.Parent then return end
    if item:GetAttribute("IsPlot") then return end

    if item:GetAttribute("Owner") ~= player.UserId then
        warn(player.Name .. " tried to rotate an item they don't own")
        return
    end

    local itemName = item:GetAttribute("ItemName")
    local nextRotation = normalizeRotation((item:GetAttribute("Rotation") or 0) + 1)
    local pivot = item:GetPivot()
    local cellsX, cellsZ = getRotatedFootprint(itemName, nextRotation)

    local nextPosition = pivot.Position
    local nextFootprintCenter = nil
    local nextGroundY = nil
    local cellX = item:GetAttribute("CellX")
    local cellZ = item:GetAttribute("CellZ")
    local plotId = playerPlots[player.UserId]
    local plotInfo = plotId and getPlotInfo(plotId)
    if cellX ~= nil and cellZ ~= nil and plotInfo then
        if not areCellsValid(cellX, cellZ, cellsX, cellsZ, plotInfo) or isAreaOccupied(player, cellX, cellZ, cellsX, cellsZ, item) then
            return
        end

        nextGroundY = plotInfo.position.Y + plotInfo.size.Y / 2
        nextFootprintCenter = getFootprintCenter(cellX, cellZ, cellsX, cellsZ, plotInfo, nextGroundY)
        nextPosition = Vector3.new(nextFootprintCenter.X, pivot.Position.Y, nextFootprintCenter.Z)
    end

    if itemName == "CurvedConveyor" and nextFootprintCenter and nextGroundY then
        pivotModelToFootprint(item, nextFootprintCenter, nextGroundY, nextRotation)
    else
        item:PivotTo(CFrame.new(nextPosition) * getRotationCFrame(nextRotation))
    end
    item:SetAttribute("Rotation", nextRotation)
    item:SetAttribute("CellsX", cellsX)
    item:SetAttribute("CellsZ", cellsZ)

    savePlayerData(player)
end)

-- Handle get inventory request
getInventoryRemote.OnServerInvoke = function(player)
    local data = playerData[player]
    if not data then
        local startTime = tick()
        while not data and tick() - startTime < 5 do
            task.wait(0.1)
            data = playerData[player]
        end
    end

    if not data then return {} end
    data.inventory = normalizeInventory(data.inventory)
    return data.inventory
end

-- Handle get player plot request
getPlotRemote.OnServerInvoke = function(player)
    local plotId = playerPlots[player.UserId]
    if not plotId then return nil end
    
    local plotInfo = getPlotInfo(plotId)
    return plotInfo
end

-- Handle get money request
getMoneyRemote.OnServerInvoke = function(player)
    local progress = PlayerProgress.GetPlayerProgress(player)
    return progress.money
end

-- Handle get reputation request
getReputationRemote.OnServerInvoke = function(player)
    local progress = PlayerProgress.GetPlayerProgress(player)
    return progress.npcReputation
end

-- Handle get placed items request
getPlacedItemsRemote.OnServerInvoke = function(player)
    local data = playerData[player]
    if not data then return {} end
    
    local placedItemsList = {}
    for _, item in ipairs(data.placedItems) do
        if item and item.Parent then
            table.insert(placedItemsList, {
                name = item:GetAttribute("ItemName"),
                position = item:GetPivot().Position,
                scaleFactor = item:GetAttribute("ScaleFactor") or 1,
                rotation = normalizeRotation(item:GetAttribute("Rotation"))
            })
        end
    end
    
    return placedItemsList
end

-- Handle production item spawn requests for machines/debug tools.
spawnProductionItemRemote.OnServerInvoke = function(player, itemName, cellX, cellZ, conveyor)
    local activeItem, message = ConveyorSystem.SpawnProductionItem(player, itemName, cellX, cellZ, conveyor)
    if not activeItem then
        return false, message
    end

    return true, "Spawned"
end

getPowerStatusRemote.OnServerInvoke = function(player)
    return PowerSystem.GetPowerStatus(player)
end

-- Handle get town prestige request
getTownPrestigeRemote.OnServerInvoke = function(player)
    local progress = PlayerProgress.GetPlayerProgress(player)
    local stageInfo = PlayerProgress.GetCurrentTownPrestigeStageInfo(player)
    local powerStatus = PowerSystem.GetPowerStatus(player)
    return {
        stage = progress.townPrestige.stage,
        stageName = stageInfo and stageInfo.name or nil,
        contributions = progress.townPrestige.contributions or 0,
        currentItemsPlaced = countPlacedMachines(player),
        maxItemsAllowed = MAX_ITEMS_PER_PLOT,
        power = powerStatus,
        powerUsed = powerStatus.used,
        powerCapacity = powerStatus.capacity,
        powerAvailable = powerStatus.available,
        basePowerCapacity = PowerSystem.GetBaseCapacity(player),
        generatorPowerCapacity = PowerSystem.GetGeneratorCapacity(player),
        unlockedShopItems = PlayerProgress.GetUnlockedShopItems(player),
    }
end

getSalesStatsRemote.OnServerInvoke = function(player)
    return PlayerProgress.GetPublicProgressSnapshot(player)
end

-- Handle buy item request (Shop system)
buyItemRemote.OnServerEvent:Connect(function(player, itemName)
    if not playerData[player] then return end
    
    -- Get item definition
    local itemDef = Definitions.GetItem(itemName)
    if not itemDef then
        print(player.Name .. " tried to buy invalid item: " .. itemName)
        sendShopResult(player, false, "buy", itemName, "Invalid item.", nil)
        return
    end
    
    -- Check if item is purchasable (has a cost)
    if not itemDef.cost or itemDef.isProduction or itemDef.type == "sell_zone" then
        print(player.Name .. " tried to buy non-purchasable item: " .. itemName)
        sendShopResult(player, false, "buy", itemName, "This item cannot be bought.", nil)
        return
    end

    if not PlayerProgress.IsShopItemUnlocked(player, itemName) then
        print(player.Name .. " tried to buy locked item: " .. itemName)
        sendShopResult(player, false, "buy", itemName, "This item is not unlocked yet.", nil)
        return
    end
    
    -- Get player's current money
    local progress = PlayerProgress.GetPlayerProgress(player)
    if progress.money < itemDef.cost then
        print(player.Name .. " tried to buy " .. itemName .. " but doesn't have enough money (has " .. progress.money .. ", needs " .. itemDef.cost .. ")")
        sendShopResult(player, false, "buy", itemName, "Not enough money.", progress.money)
        return
    end
    
    -- Deduct money from player
    local newBalance = PlayerProgress.AddMoney(player, -itemDef.cost)
    if not newBalance then
        sendShopResult(player, false, "buy", itemName, "Not enough money.", progress.money)
        return
    end
    print(player.Name .. " bought " .. itemName .. " for " .. itemDef.cost .. "💵 - New balance: " .. newBalance)
    
    -- Add item to inventory
    local added = addItemToInventory(player, itemName, 1)
    if not added then
        PlayerProgress.AddMoney(player, itemDef.cost)
        sendShopResult(player, false, "buy", itemName, "Could not add item to inventory.", progress.money)
        return
    end
    
    -- Save after purchase
    savePlayerData(player)
    notifyInventoryUpdated(player)
    sendShopResult(player, true, "buy", itemName, "Purchased " .. itemName .. ".", newBalance)
end)

-- Handle sell item request (Shop system)
sellItemRemote.OnServerEvent:Connect(function(player, itemName)
    if not playerData[player] then return end
    
    -- Get item definition
    local itemDef = Definitions.GetItem(itemName)
    if not itemDef then
        print(player.Name .. " tried to sell invalid item: " .. itemName)
        sendShopResult(player, false, "sell", itemName, "Invalid item.", nil)
        return
    end
    
    -- Check if item has a cost (can be sold)
    if not itemDef.cost then
        print(player.Name .. " tried to sell non-sellable item: " .. itemName)
        sendShopResult(player, false, "sell", itemName, "This item cannot be sold.", nil)
        return
    end
    
    -- Check if player has this item in inventory
    local removed = removeItemFromInventory(player, itemName, 1)
    if not removed then
        print(player.Name .. " tried to sell " .. itemName .. " but doesn't have it")
        local progress = PlayerProgress.GetPlayerProgress(player)
        sendShopResult(player, false, "sell", itemName, "You do not own this item.", progress.money)
        return
    end
    
    -- Give half price to player when selling from inventory.
    local saleValue = math.floor(itemDef.cost * 0.5)
    local newBalance = PlayerProgress.AddMoney(player, saleValue)
    print(player.Name .. " sold " .. itemName .. " for " .. saleValue .. "💵 - New balance: " .. newBalance)
    
    -- Save after selling
    savePlayerData(player)
    notifyInventoryUpdated(player)
    sendShopResult(player, true, "sell", itemName, "Sold " .. itemName .. " for " .. saleValue .. ".", newBalance)
end)

-- Protect all plots at startup
local function protectAllPlots()
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return end
    
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if plot:IsA("BasePart") then
            protectPlot(plot)
        end
    end
end

ConveyorSystem.Initialize({
    getPlayerPlot = function(player)
        local plotId = playerPlots[player.UserId]
        if not plotId then
            return nil
        end

        return getPlotInfo(plotId)
    end,

    getPlacedItems = function(player)
        local data = playerData[player]
        if not data then
            return {}
        end

        return data.placedItems
    end,

    addMoney = function(player, amount)
        return PlayerProgress.AddMoney(player, amount)
    end,
})
MachineSystem.Initialize()
SellSystem.Initialize()

-- Setup players
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Handle players already in game
for _, player in Players:GetPlayers() do
    onPlayerAdded(player)
end

-- Protect plots at startup
protectAllPlots()

print("Inventory Manager started successfully!")
