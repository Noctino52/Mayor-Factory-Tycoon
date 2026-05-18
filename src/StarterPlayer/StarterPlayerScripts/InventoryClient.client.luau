-- Inventory UI and Placement System
-- Handles inventory display, grid-based placement, and deletion
-- Grid unit is dynamically based on RubiksCube size

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Definitions = require(sharedFolder:WaitForChild("Definitions"))
local templatesFolder = sharedFolder:WaitForChild("ItemTemplates")
local flowPreviewTemplatesFolder = sharedFolder:WaitForChild("FlowPreviewTemplates")
local arrowForBeltTemplate = flowPreviewTemplatesFolder:WaitForChild("ArrowForBelt")

-- Wait for remotes
local placeItemRemote = ReplicatedStorage:WaitForChild("PlaceItem")
local getInventoryRemote = ReplicatedStorage:WaitForChild("GetInventory")
local deleteItemRemote = ReplicatedStorage:WaitForChild("DeleteItem")
local rotateItemRemote = ReplicatedStorage:WaitForChild("RotateItem")
local getPlotRemote = ReplicatedStorage:WaitForChild("GetPlayerPlot")
local inventoryUpdatedRemote = ReplicatedStorage:WaitForChild("InventoryUpdated")
local updateFactorySignTextRemote = ReplicatedStorage:WaitForChild("UpdateFactorySignText")

-- Configuration
local GHOST_TRANSPARENCY = 0.6
local GRID_UNIT_SIZE = 8 -- Fixed grid size in studs
local MAX_FACTORY_SIGN_TEXT_LENGTH = 32

-- Item Icons mapping
local ITEM_ICONS = {
    RubiksCube = "🎲",
    TreeFarm = "🌳",
    MineEntrance = "⛏️",
    Sawmill = "🏭",
}

-- Get grid unit size (now fixed)
local function getGridUnitSize()
    return GRID_UNIT_SIZE
end

-- Get icon for item
local function getItemIcon(itemName)
    local itemDef = Definitions.GetItem(itemName)
    if itemDef and itemDef.icon then
        return itemDef.icon
    end

    return ITEM_ICONS[itemName] or "?"
end

-- State
local inventory = {}
local selectedItem = nil
local placementRotation = 0 -- 0, 1, 2, 3 = 0, 90, 180, 270 degrees
local placementMode = false
local deletionMode = false
local ghostItem = nil
local canPlace = false
local hoveredDeleteItem = nil
local hoveredPlacedItem = nil
local placedItemHoverStartedAt = nil
local placedItemHoverEndedAt = nil
local gridVisuals = {} -- Grid lines
local highlightBox = nil -- Single box to highlight target cells
local selectionBox = nil -- For deletion highlight
local itemContextBillboard = nil
local itemContextAttachment = nil
local itemContextMenu = nil
local contextMenuTarget = nil
local contextMenuTween = nil
local lastContextRotateAt = 0
local activeFactorySign = nil
local signEditorFrame = nil
local signEditorTextBox = nil
local signEditorStatus = nil
local placementIndicator = nil
local indicatorText = nil
local currentGridUnit = 0 -- Cache for current grid unit size
local currentScaleFactor = 1 -- Cache for current scale factor
local lastPlotSize = nil -- Track plot size changes
local playerPlotInfo = nil -- Cached plot info for this player
local flowPreviewFolder = nil
local lastFlowPreviewKey = nil

local FLOW_PREVIEW_MAX_STEPS = 20
local FLOW_PREVIEW_Y_OFFSET = 0.55
local FLOW_PREVIEW_ITEMS = {
    Conveyor = true,
    CurvedConveyor = true,
    Splitter = true,
    Merger = true,
}
local FLOW_PREVIEW_COLORS = {
    valid = Color3.fromRGB(70, 255, 120),
    invalid = Color3.fromRGB(255, 70, 70),
    terminal = Color3.fromRGB(255, 220, 70),
    junction = Color3.fromRGB(80, 220, 255),
}

-- Function to get player's assigned plot info
local function getPlotInfo()
    -- Return cached plot info if available
    if playerPlotInfo then
        return playerPlotInfo
    end
    
    -- Try to get plot info from server
    local success, result = pcall(function()
        return getPlotRemote:InvokeServer()
    end)
    
    if success and result then
        playerPlotInfo = result
        return playerPlotInfo
    end
    
    return nil
end

-- Function to refresh plot info from server
local function refreshPlotInfo()
    playerPlotInfo = nil
    return getPlotInfo()
end

-- Function to convert world position to grid cell index
local function worldToGrid(position, plotInfo, gridUnit)
    if not plotInfo then return nil, nil end
    
    -- Calculate relative position from plot center
    local relativeX = position.X - plotInfo.position.X
    local relativeZ = position.Z - plotInfo.position.Z
    
    -- Convert to cell index (cells are between grid lines, offset by gridUnit/2)
    -- Cell 0 goes from 0 to gridUnit, cell -1 goes from -gridUnit to 0, etc.
    local cellX = math.floor(relativeX / gridUnit)
    local cellZ = math.floor(relativeZ / gridUnit)
    
    return cellX, cellZ
end

-- Function to convert grid cell index to world position (CENTER of cell)
local function gridToWorld(cellX, cellZ, plotInfo, gridUnit)
    if not plotInfo then return nil end
    
    -- Return the CENTER of the cell (offset by gridUnit/2 from the grid lines)
    return Vector3.new(
        plotInfo.position.X + cellX * gridUnit + gridUnit/2,
        plotInfo.position.Y + plotInfo.size.Y / 2,
        plotInfo.position.Z + cellZ * gridUnit + gridUnit/2
    )
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
    if rotation % 2 == 1 then
        return cellsZ, cellsX
    end

    return cellsX, cellsZ
end

local function getFootprintCenter(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit)
    if not plotInfo then return nil end

    return Vector3.new(
        plotInfo.position.X + (cellX + cellsX / 2) * gridUnit,
        plotInfo.position.Y + plotInfo.size.Y / 2,
        plotInfo.position.Z + (cellZ + cellsZ / 2) * gridUnit
    )
end

local function getRotationCFrame(rotation)
    return CFrame.Angles(0, (rotation % 4) * math.pi / 2, 0)
end

local ITEM_VISUAL_ADJUSTMENTS = {
    Conveyor = {
        footprintPadding = 0.98,
        maxHeight = 1.2,
    },
    CurvedConveyor = {
        footprintPadding = 0.82,
        maxHeight = 1.2,
        maxScale = 3,
    },
    DecorTree = {
        footprintPadding = 2,
        maxScale = 2,
    },
    FactorySign = {
        footprintPadding = 2,
        maxScale = 2,
    },
    StreetLamp = {
        footprintPadding = 2,
        maxScale = 2,
    },
}

local function getItemFootprintPadding(itemName)
    local adjustment = ITEM_VISUAL_ADJUSTMENTS[itemName]
    return (adjustment and adjustment.footprintPadding) or 1
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

local function prepareCurvedConveyorVisuals(item)
    styleCurvedConveyorBase(item)
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

-- Function to check if cells are within plot bounds
local function areCellsValid(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit)
    if not plotInfo then return false end
    
    local halfPlotCellsX = math.floor((plotInfo.size.X / 2) / gridUnit)
    local halfPlotCellsZ = math.floor((plotInfo.size.Z / 2) / gridUnit)
    
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

-- Function to check if target cells are occupied
local function isAreaOccupied(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit, ignoredItem)
    -- Get all placed items
    local playerItemsFolder = workspace:FindFirstChild("PlayerItems_" .. player.UserId)
    if not playerItemsFolder then return false end
    
    for _, placedItem in ipairs(playerItemsFolder:GetChildren()) do
        if placedItem:IsA("Model") and placedItem ~= ignoredItem then
            local itemPos = placedItem:GetPivot().Position
            local itemCellX = placedItem:GetAttribute("CellX")
            local itemCellZ = placedItem:GetAttribute("CellZ")
            local itemCellsX = placedItem:GetAttribute("CellsX") or 1
            local itemCellsZ = placedItem:GetAttribute("CellsZ") or 1

            if itemCellX == nil or itemCellZ == nil then
                itemCellX, itemCellZ = worldToGrid(itemPos, plotInfo, gridUnit)
            end
            
            if doFootprintsOverlap(cellX, cellZ, cellsX, cellsZ, itemCellX, itemCellZ, itemCellsX, itemCellsZ) then
                return true
            end
        end
    end
    
    return false
end

local function findOwnedPlacedItemAtCell(cellX, cellZ)
    local playerItemsFolder = workspace:FindFirstChild("PlayerItems_" .. player.UserId)
    if not playerItemsFolder then
        return nil
    end

    for _, placedItem in ipairs(playerItemsFolder:GetChildren()) do
        if placedItem:IsA("Model") and placedItem:GetAttribute("Owner") == player.UserId and not placedItem:GetAttribute("IsPlot") then
            local itemCellX = placedItem:GetAttribute("CellX")
            local itemCellZ = placedItem:GetAttribute("CellZ")
            local itemCellsX = placedItem:GetAttribute("CellsX") or 1
            local itemCellsZ = placedItem:GetAttribute("CellsZ") or 1

            if itemCellX ~= nil and itemCellZ ~= nil then
                if cellX >= itemCellX and cellX < itemCellX + itemCellsX and cellZ >= itemCellZ and cellZ < itemCellZ + itemCellsZ then
                    return placedItem
                end
            end
        end
    end

    return nil
end

local function getOwnedPlacedItemFromPlotCell(ray)
    local plotInfo = getPlotInfo()
    if not plotInfo or math.abs(ray.Direction.Y) < 0.0001 then
        return nil
    end

    local plotTopY = plotInfo.position.Y + plotInfo.size.Y / 2
    local distance = (plotTopY - ray.Origin.Y) / ray.Direction.Y
    if distance < 0 then
        return nil
    end

    local hitPosition = ray.Origin + ray.Direction * distance
    local halfPlotSize = plotInfo.size / 2
    if hitPosition.X < plotInfo.position.X - halfPlotSize.X or hitPosition.X > plotInfo.position.X + halfPlotSize.X
        or hitPosition.Z < plotInfo.position.Z - halfPlotSize.Z or hitPosition.Z > plotInfo.position.Z + halfPlotSize.Z then
        return nil
    end

    local gridUnit = currentGridUnit
    if gridUnit == 0 then
        gridUnit = getGridUnitSize()
    end

    local cellX, cellZ = worldToGrid(hitPosition, plotInfo, gridUnit)
    return findOwnedPlacedItemAtCell(cellX, cellZ)
end

local function getOwnedPlacedItemFromRay()
    local playerItemsFolder = workspace:FindFirstChild("PlayerItems_" .. player.UserId)
    if not playerItemsFolder then
        return nil
    end

    local camera = workspace.CurrentCamera
    local mousePos = UserInputService:GetMouseLocation()
    local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Include
    rayParams.FilterDescendantsInstances = {playerItemsFolder}

    local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
    if not result or not result.Instance then
        return getOwnedPlacedItemFromPlotCell(ray)
    end

    local target = result.Instance
    if target:GetAttribute("IsPlot") then
        return nil
    end

    while target and target.Parent and target.Parent ~= workspace do
        if target:GetAttribute("IsPlot") then
            return nil
        end

        if target:GetAttribute("Owner") then
            break
        end

        target = target.Parent
    end

    if target and target:GetAttribute("Owner") == player.UserId and not target:GetAttribute("IsPlot") then
        return target
    end

    return getOwnedPlacedItemFromPlotCell(ray)
end

-- Function to get item height
local function getItemHeight(item)
    local cframe, size = item:GetBoundingBox()
    return size.Y
end

-- Function to remove grid visualization (defined first)
local function removeGridVisualization()
    for _, visual in pairs(gridVisuals) do
        if visual and visual.Parent then
            visual:Destroy()
        end
    end
    gridVisuals = {}
    
    if highlightBox then
        highlightBox:Destroy()
        highlightBox = nil
    end
end

-- Function to create grid visualization with lines (optimized)
local function createGridVisualization()
    removeGridVisualization()
    
    local plotInfo = getPlotInfo()
    if not plotInfo then return end
    
    -- Find the plot object using the plot ID
    local plotsFolder = workspace:FindFirstChild("Plots")
    local plot = nil
    if plotsFolder and plotInfo.id then
        plot = plotsFolder:FindFirstChild("Plot" .. plotInfo.id)
    end
    
    if not plot then return end
    
    local gridUnit = getGridUnitSize()
    currentGridUnit = gridUnit
    
    -- Store current plot size for change detection
    lastPlotSize = plotInfo.size
    
    local plotTop = plotInfo.position.Y + plotInfo.size.Y / 2 + 0.05
    
    -- Calculate number of cells using the SAME logic as placement
    -- Cells go from i*gridUnit to (i+1)*gridUnit, so we need lines at each boundary
    local halfPlotCellsX = math.floor((plotInfo.size.X / 2) / gridUnit)
    local halfPlotCellsZ = math.floor((plotInfo.size.Z / 2) / gridUnit)
    
    -- Create vertical lines (along Z axis) - cell boundaries
    -- Lines at: -halfPlotCellsX*gridUnit, ..., 0, ..., +halfPlotCellsX*gridUnit
    for i = -halfPlotCellsX, halfPlotCellsX do
        local line = Instance.new("Part")
        line.Name = "GridLine_V" .. i
        line.Size = Vector3.new(0.05, 0.05, plotInfo.size.Z)
        line.CFrame = CFrame.new(
            plotInfo.position.X + i * gridUnit,
            plotTop,
            plotInfo.position.Z
        )
        line.Anchored = true
        line.CanCollide = false
        line.CanQuery = false
        line.CanTouch = false
        line.Material = Enum.Material.Neon
        line.Color = Color3.fromRGB(100, 100, 100)
        line.Transparency = 0.5
        line.Parent = plot
        table.insert(gridVisuals, line)
    end
    
    -- Create horizontal lines (along X axis) - cell boundaries
    for i = -halfPlotCellsZ, halfPlotCellsZ do
        local line = Instance.new("Part")
        line.Name = "GridLine_H" .. i
        line.Size = Vector3.new(plotInfo.size.X, 0.05, 0.05)
        line.CFrame = CFrame.new(
            plotInfo.position.X,
            plotTop,
            plotInfo.position.Z + i * gridUnit
        )
        line.Anchored = true
        line.CanCollide = false
        line.CanQuery = false
        line.CanTouch = false
        line.Material = Enum.Material.Neon
        line.Color = Color3.fromRGB(100, 100, 100)
        line.Transparency = 0.5
        line.Parent = plot
        table.insert(gridVisuals, line)
    end
    
    -- Create highlight box (single box for target cells)
    highlightBox = Instance.new("Part")
    highlightBox.Name = "HighlightBox"
    highlightBox.Size = Vector3.new(gridUnit, 0.2, gridUnit)
    highlightBox.Anchored = true
    highlightBox.CanCollide = false
    highlightBox.CanQuery = false
    highlightBox.CanTouch = false
    highlightBox.Material = Enum.Material.Neon
    highlightBox.Color = Color3.fromRGB(50, 200, 50)
    highlightBox.Transparency = 0.3
    highlightBox.Parent = plot
end

-- Function to create selection box for deletion highlight
local function createSelectionBox(item)
    if selectionBox then
        selectionBox:Destroy()
        selectionBox = nil
    end
    
    if not item then return end
    
    selectionBox = Instance.new("Highlight")
    selectionBox.Name = "DeletionHighlight"
    selectionBox.OutlineTransparency = 0

    local itemName = item:GetAttribute("ItemName")
    local itemDef = Definitions.GetItem(itemName)
    if itemDef and itemDef.type == "sell_zone" then
        selectionBox:Destroy()

        local plotInfo = getPlotInfo()
        local gridUnit = currentGridUnit
        if gridUnit == 0 then
            gridUnit = getGridUnitSize()
        end

        local cellX = item:GetAttribute("CellX")
        local cellZ = item:GetAttribute("CellZ")
        local cellsX = item:GetAttribute("CellsX") or 1
        local cellsZ = item:GetAttribute("CellsZ") or 1
        if not plotInfo or cellX == nil or cellZ == nil then
            return
        end

        local center = getFootprintCenter(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit)
        local overlay = Instance.new("Part")
        overlay.Name = "DeletionHighlight"
        overlay.Size = Vector3.new(cellsX * gridUnit, 0.18, cellsZ * gridUnit)
        overlay.CFrame = CFrame.new(center.X, plotInfo.position.Y + plotInfo.size.Y / 2 + 0.22, center.Z)
        overlay.Anchored = true
        overlay.CanCollide = false
        overlay.CanQuery = false
        overlay.CanTouch = false
        overlay.Material = Enum.Material.Neon
        overlay.Color = Color3.fromRGB(255, 220, 70)
        overlay.Transparency = 0.25
        overlay.Parent = workspace
        selectionBox = overlay
        return
    end

    selectionBox.FillTransparency = 0.8
    selectionBox.OutlineColor = Color3.fromRGB(255, 50, 50)
    selectionBox.FillColor = Color3.fromRGB(255, 50, 50)
    selectionBox.Adornee = item
    selectionBox.Parent = item
end

-- Function to remove selection box
local function removeSelectionBox()
    if selectionBox then
        selectionBox:Destroy()
        selectionBox = nil
    end
end

local function clearFlowPreview()
    if flowPreviewFolder then
        flowPreviewFolder:Destroy()
        flowPreviewFolder = nil
    end

    lastFlowPreviewKey = nil
end

local function getFlowPreviewFolder()
    if flowPreviewFolder and flowPreviewFolder.Parent then
        return flowPreviewFolder
    end

    local previewParent = workspace.CurrentCamera or workspace
    local existingPreview = previewParent:FindFirstChild("FlowPreview_" .. player.UserId)
    if existingPreview then
        existingPreview:Destroy()
    end

    flowPreviewFolder = Instance.new("Folder")
    flowPreviewFolder.Name = "FlowPreview_" .. player.UserId
    flowPreviewFolder.Parent = previewParent

    return flowPreviewFolder
end

local function cellKey(cellX, cellZ)
    return tostring(cellX) .. "_" .. tostring(cellZ)
end

local function worldDirectionToGrid(direction)
    if math.abs(direction.X) >= math.abs(direction.Z) then
        return direction.X >= 0 and 1 or -1, 0
    end

    return 0, direction.Z >= 0 and 1 or -1
end

local function rotateDirection(dx, dz, rotationSteps)
    rotationSteps = math.floor(tonumber(rotationSteps) or 0) % 4

    for _ = 1, rotationSteps do
        dx, dz = -dz, dx
    end

    return dx, dz
end

local function getFirstBasePartForFlow(instance)
    if not instance then
        return nil
    end

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

local function isFlowPreviewItem(itemName)
    return FLOW_PREVIEW_ITEMS[itemName] == true or Definitions.GetMachine(itemName) ~= nil
end

local function getFlowItemType(itemName)
    local itemDef = Definitions.GetItem(itemName)
    if itemDef then
        if itemDef.type == "conveyor" or itemDef.type == "curved_conveyor" or itemDef.type == "splitter" or itemDef.type == "merger" then
            return itemDef.type
        end

        if itemDef.type == "sell_zone" or itemDef.type == "sellZone" then
            return "sell_zone"
        end
    end

    if Definitions.GetMachine(itemName) then
        return "machine"
    end

    if tostring(itemName):find("Conveyor", 1, true) then
        return "conveyor"
    end

    return "occupied"
end

local function isFlowTransportType(flowType)
    return flowType == "conveyor" or flowType == "curved_conveyor" or flowType == "splitter" or flowType == "merger"
end

local function isFlowJunctionType(flowType)
    return flowType == "splitter" or flowType == "merger"
end

local function getPreviewConveyorDirection(instance, rotation)
    local conveyorPart = getFirstBasePartForFlow(instance)
    if conveyorPart then
        return worldDirectionToGrid(conveyorPart.CFrame.LookVector)
    end

    if instance and instance:IsA("Model") then
        return worldDirectionToGrid(instance:GetPivot().LookVector)
    end

    return rotateDirection(1, 0, rotation)
end

local function createFlowCellInfo(instance, itemName, cellX, cellZ, cellsX, cellsZ, rotation, isVirtual)
    itemName = itemName or (instance and (instance:GetAttribute("ItemName") or instance.Name))
    if not itemName then
        return nil
    end

    cellX = cellX ~= nil and cellX or (instance and instance:GetAttribute("CellX"))
    cellZ = cellZ ~= nil and cellZ or (instance and instance:GetAttribute("CellZ"))
    if cellX == nil or cellZ == nil then
        return nil
    end

    cellsX = cellsX or (instance and instance:GetAttribute("CellsX")) or 1
    cellsZ = cellsZ or (instance and instance:GetAttribute("CellsZ")) or 1
    rotation = math.floor(tonumber(rotation ~= nil and rotation or (instance and instance:GetAttribute("Rotation"))) or 0) % 4

    local flowType = getFlowItemType(itemName)
    local machineData = Definitions.GetMachine(itemName)
    local info = {
        type = flowType,
        instance = instance,
        itemName = itemName,
        machineData = machineData,
        cellX = math.floor(tonumber(cellX) or 0),
        cellZ = math.floor(tonumber(cellZ) or 0),
        cellsX = math.max(1, math.floor(tonumber(cellsX) or 1)),
        cellsZ = math.max(1, math.floor(tonumber(cellsZ) or 1)),
        rotation = rotation,
        isVirtual = isVirtual == true,
    }

    if isFlowTransportType(flowType) then
        local directionX, directionZ = getPreviewConveyorDirection(instance, rotation)
        info.directionX = directionX
        info.directionZ = directionZ
    end

    return info
end

local function addFlowInfoToLookup(lookup, info)
    if not info then
        return
    end

    for dx = 0, info.cellsX - 1 do
        for dz = 0, info.cellsZ - 1 do
            lookup[cellKey(info.cellX + dx, info.cellZ + dz)] = info
        end
    end
end

local function buildFlowCellLookup(virtualInfo)
    local lookup = {}
    local playerItemsFolder = workspace:FindFirstChild("PlayerItems_" .. player.UserId)

    if playerItemsFolder then
        for _, placedItem in ipairs(playerItemsFolder:GetChildren()) do
            if placedItem:IsA("Model") and placedItem:GetAttribute("Owner") == player.UserId and not placedItem:GetAttribute("IsPlot") then
                addFlowInfoToLookup(lookup, createFlowCellInfo(placedItem))
            end
        end
    end

    if virtualInfo then
        addFlowInfoToLookup(lookup, virtualInfo)
    end

    return lookup
end

local CURVED_CONVEYOR_ROUTES = {
    { inputX = -1, inputZ = 0, outputX = 0, outputZ = 1 },
    { inputX = 0, inputZ = 1, outputX = 1, outputZ = 0 },
    { inputX = 0, inputZ = -1, outputX = 1, outputZ = 0 },
    { inputX = -1, inputZ = 0, outputX = 0, outputZ = -1 },
}

local function routeCurvedConveyorPreview(info, previousCellX, previousCellZ)
    if not info or previousCellX == nil or previousCellZ == nil then
        return nil, nil
    end

    local route = CURVED_CONVEYOR_ROUTES[(info.rotation % 4) + 1]
    if not route then
        return nil, nil
    end

    if previousCellX == info.cellX + route.inputX and previousCellZ == info.cellZ + route.inputZ then
        return info.cellX + route.outputX, info.cellZ + route.outputZ
    elseif previousCellX == info.cellX + route.outputX and previousCellZ == info.cellZ + route.outputZ then
        return info.cellX + route.inputX, info.cellZ + route.inputZ
    end

    return nil, nil
end

local function getSplitterInputLane(info, previousCellX, previousCellZ)
    if not info or previousCellX == nil or previousCellZ == nil then
        return nil
    end

    if info.rotation == 1 then
        return previousCellX == info.cellX - 1 and previousCellZ == info.cellZ and 1 or nil
    elseif info.rotation == 2 then
        return previousCellZ == info.cellZ - 1 and previousCellX == info.cellX + info.cellsX - 1 and 1 or nil
    elseif info.rotation == 3 then
        return previousCellX == info.cellX + info.cellsX and previousCellZ == info.cellZ + info.cellsZ - 1 and 1 or nil
    end

    return previousCellZ == info.cellZ + info.cellsZ and previousCellX == info.cellX and 1 or nil
end

local function getSplitterOutputCell(info, previousCellX, previousCellZ, outputLane)
    if not getSplitterInputLane(info, previousCellX, previousCellZ) then
        return nil, nil
    end

    local useSecondOutput = outputLane == 2
    if info.rotation == 1 then
        return info.cellX + info.cellsX, info.cellZ + (useSecondOutput and 1 or 0)
    elseif info.rotation == 2 then
        return info.cellX + (useSecondOutput and 0 or 1), info.cellZ + info.cellsZ
    elseif info.rotation == 3 then
        return info.cellX - 1, info.cellZ + (useSecondOutput and 0 or 1)
    end

    return info.cellX + (useSecondOutput and 1 or 0), info.cellZ - 1
end

local function getSplitterInputCellForPreview(info)
    if info.rotation == 1 then
        return info.cellX - 1, info.cellZ
    elseif info.rotation == 2 then
        return info.cellX + info.cellsX - 1, info.cellZ - 1
    elseif info.rotation == 3 then
        return info.cellX + info.cellsX, info.cellZ + info.cellsZ - 1
    end

    return info.cellX, info.cellZ + info.cellsZ
end

local function getMergerInputLane(info, inputCellX, inputCellZ)
    if not info or inputCellX == nil or inputCellZ == nil then
        return nil
    end

    if info.rotation == 1 then
        if inputCellX == info.cellX - 1 and inputCellZ >= info.cellZ and inputCellZ < info.cellZ + info.cellsZ then
            return math.clamp(inputCellZ - info.cellZ + 1, 1, 2)
        end
    elseif info.rotation == 2 then
        if inputCellZ == info.cellZ - 1 and inputCellX >= info.cellX and inputCellX < info.cellX + info.cellsX then
            return math.clamp(info.cellX + info.cellsX - inputCellX, 1, 2)
        end
    elseif info.rotation == 3 then
        if inputCellX == info.cellX + info.cellsX and inputCellZ >= info.cellZ and inputCellZ < info.cellZ + info.cellsZ then
            return math.clamp(info.cellZ + info.cellsZ - inputCellZ, 1, 2)
        end
    elseif inputCellZ == info.cellZ + info.cellsZ and inputCellX >= info.cellX and inputCellX < info.cellX + info.cellsX then
        return math.clamp(inputCellX - info.cellX + 1, 1, 2)
    end

    return nil
end

local function getMergerOutputCell(info, previousCellX, previousCellZ)
    local inputLane = getMergerInputLane(info, previousCellX, previousCellZ)
    if not inputLane then
        return nil, nil, nil
    end

    if info.rotation == 1 then
        return info.cellX + info.cellsX, info.cellZ, inputLane
    elseif info.rotation == 2 then
        return info.cellX + info.cellsX - 1, info.cellZ + info.cellsZ, inputLane
    elseif info.rotation == 3 then
        return info.cellX - 1, info.cellZ + info.cellsZ - 1, inputLane
    end

    return info.cellX, info.cellZ - 1, inputLane
end

local function getAdjacentFootprintCell(info, outsideCellX, outsideCellZ)
    for dx = 0, info.cellsX - 1 do
        for dz = 0, info.cellsZ - 1 do
            local footprintCellX = info.cellX + dx
            local footprintCellZ = info.cellZ + dz
            if math.abs(footprintCellX - outsideCellX) + math.abs(footprintCellZ - outsideCellZ) == 1 then
                return footprintCellX, footprintCellZ
            end
        end
    end

    return info.cellX, info.cellZ
end

local function getMergerInputCellsForPreview(info)
    local inputCells = {}

    for candidateX = info.cellX - 1, info.cellX + info.cellsX do
        for candidateZ = info.cellZ - 1, info.cellZ + info.cellsZ do
            local lane = getMergerInputLane(info, candidateX, candidateZ)
            if lane then
                inputCells[lane] = {
                    cellX = candidateX,
                    cellZ = candidateZ,
                }
            end
        end
    end

    return inputCells
end

local function isFlowSourceType(flowType)
    return isFlowTransportType(flowType) or flowType == "machine"
end

local function getMachineOutputDirection(info)
    local machineData = info and (info.machineData or Definitions.GetMachine(info.itemName))
    local rotationOffset = machineData and tonumber(machineData.outputRotationOffset) or 0
    return rotateDirection(1, 0, (info.rotation or 0) + rotationOffset)
end

local function getMachineOutputCell(info)
    local directionX, directionZ = getMachineOutputDirection(info)

    if directionX > 0 then
        return info.cellX + info.cellsX, info.cellZ
    elseif directionX < 0 then
        return info.cellX - 1, info.cellZ
    elseif directionZ > 0 then
        return info.cellX, info.cellZ + info.cellsZ
    end

    return info.cellX, info.cellZ - 1
end

local function getMachineInputCell(info)
    local directionX, directionZ = getMachineOutputDirection(info)

    if directionX > 0 then
        return info.cellX - 1, info.cellZ
    elseif directionX < 0 then
        return info.cellX + info.cellsX, info.cellZ
    elseif directionZ > 0 then
        return info.cellX, info.cellZ - 1
    end

    return info.cellX, info.cellZ + info.cellsZ
end

local function canTransportReceiveFrom(info, previousCellX, previousCellZ)
    if not info or not isFlowTransportType(info.type) then
        return false
    end

    if info.type == "curved_conveyor" then
        local nextCellX, nextCellZ = routeCurvedConveyorPreview(info, previousCellX, previousCellZ)
        return nextCellX ~= nil and nextCellZ ~= nil
    elseif info.type == "splitter" then
        local nextCellX, nextCellZ = getSplitterOutputCell(info, previousCellX, previousCellZ, 1)
        return nextCellX ~= nil and nextCellZ ~= nil
    elseif info.type == "merger" then
        local nextCellX, nextCellZ = getMergerOutputCell(info, previousCellX, previousCellZ)
        return nextCellX ~= nil and nextCellZ ~= nil
    end

    return true
end

local function getFlowStartStates(info)
    if not info then
        return {}
    end

    if info.type == "curved_conveyor" then
        local route = CURVED_CONVEYOR_ROUTES[(info.rotation % 4) + 1]
        if route then
            return {{
                cellX = info.cellX,
                cellZ = info.cellZ,
                previousCellX = info.cellX + route.inputX,
                previousCellZ = info.cellZ + route.inputZ,
            }}
        end
    elseif info.type == "splitter" then
        local previousCellX, previousCellZ = getSplitterInputCellForPreview(info)
        return {{
            cellX = info.cellX,
            cellZ = info.cellZ,
            previousCellX = previousCellX,
            previousCellZ = previousCellZ,
        }}
    elseif info.type == "merger" then
        local inputCells = getMergerInputCellsForPreview(info)
        local inputCell = inputCells[1] or inputCells[2]
        if inputCell then
            return {{
                cellX = info.cellX,
                cellZ = info.cellZ,
                previousCellX = inputCell.cellX,
                previousCellZ = inputCell.cellZ,
            }}
        end

        return {}
    elseif info.type == "machine" then
        return {{
            cellX = info.cellX,
            cellZ = info.cellZ,
            previousCellX = nil,
            previousCellZ = nil,
        }}
    end

    local directionX = info.directionX or 1
    local directionZ = info.directionZ or 0
    return {{
        cellX = info.cellX,
        cellZ = info.cellZ,
        previousCellX = info.cellX - directionX,
        previousCellZ = info.cellZ - directionZ,
    }}
end

local function getNextFlowTargets(info, state)
    if info.type == "curved_conveyor" then
        local nextCellX, nextCellZ = routeCurvedConveyorPreview(info, state.previousCellX, state.previousCellZ)
        if nextCellX == nil or nextCellZ == nil then
            return {}
        end

        return {{
            cellX = nextCellX,
            cellZ = nextCellZ,
            fromCellX = state.cellX,
            fromCellZ = state.cellZ,
        }}
    elseif info.type == "splitter" then
        local targets = {}
        for outputLane = 1, 2 do
            local nextCellX, nextCellZ = getSplitterOutputCell(info, state.previousCellX, state.previousCellZ, outputLane)
            if nextCellX ~= nil and nextCellZ ~= nil then
                local fromCellX, fromCellZ = getAdjacentFootprintCell(info, nextCellX, nextCellZ)
                table.insert(targets, {
                    cellX = nextCellX,
                    cellZ = nextCellZ,
                    fromCellX = fromCellX,
                    fromCellZ = fromCellZ,
                    isJunctionRoute = true,
                })
            end
        end

        return targets
    elseif info.type == "merger" then
        local nextCellX, nextCellZ = getMergerOutputCell(info, state.previousCellX, state.previousCellZ)
        if nextCellX == nil or nextCellZ == nil then
            return {}
        end

        local fromCellX, fromCellZ = getAdjacentFootprintCell(info, nextCellX, nextCellZ)
        return {{
            cellX = nextCellX,
            cellZ = nextCellZ,
            fromCellX = fromCellX,
            fromCellZ = fromCellZ,
            isJunctionRoute = true,
        }}
    elseif info.type == "machine" then
        local machineData = info.machineData or Definitions.GetMachine(info.itemName)
        if not machineData or (machineData.type ~= "producer" and machineData.type ~= "processor") then
            return {}
        end

        local nextCellX, nextCellZ = getMachineOutputCell(info)
        local fromCellX, fromCellZ = getAdjacentFootprintCell(info, nextCellX, nextCellZ)
        return {{
            cellX = nextCellX,
            cellZ = nextCellZ,
            fromCellX = fromCellX,
            fromCellZ = fromCellZ,
            isMachineOutput = true,
        }}
    end

    local directionX = info.directionX or 1
    local directionZ = info.directionZ or 0
    return {{
        cellX = state.cellX + directionX,
        cellZ = state.cellZ + directionZ,
        fromCellX = state.cellX,
        fromCellZ = state.cellZ,
    }}
end

local function getPreviewCellWorldPosition(cellX, cellZ, plotInfo, gridUnit)
    return Vector3.new(
        plotInfo.position.X + cellX * gridUnit + gridUnit / 2,
        plotInfo.position.Y + plotInfo.size.Y / 2 + FLOW_PREVIEW_Y_OFFSET,
        plotInfo.position.Z + cellZ * gridUnit + gridUnit / 2
    )
end

local function styleFlowPreviewInstance(instance, color)
    local descendants = instance:GetDescendants()
    table.insert(descendants, instance)

    for _, descendant in ipairs(descendants) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanQuery = false
            descendant.CanTouch = false
            descendant.CastShadow = false
            descendant.Material = Enum.Material.Neon
            descendant.Color = color
            descendant.Transparency = 0.08
        elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
            descendant:Destroy()
        end
    end
end

local function getArrowForwardCFrame(center, direction)
    local up = Vector3.yAxis
    local zAxis = direction:Cross(up)
    if zAxis.Magnitude < 0.001 then
        zAxis = Vector3.zAxis
    else
        zAxis = zAxis.Unit
    end

    return CFrame.fromMatrix(center, direction, up, zAxis)
end

local function drawModelFlowArrow(fromPosition, toPosition, color, gridUnit)
    local delta = Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z)
    local distance = delta.Magnitude
    if distance < 0.001 then
        return
    end

    local direction = delta.Unit
    local center = fromPosition + direction * (distance * 0.5)
    local arrow = arrowForBeltTemplate:Clone()
    arrow.Name = "FlowPreviewArrow"
    styleFlowPreviewInstance(arrow, color)
    arrow.Parent = getFlowPreviewFolder()

    if arrow:IsA("Model") then
        local _, templateSize = arrow:GetBoundingBox()
        local templateLength = math.max(templateSize.X, 0.001)
        local desiredLength = math.clamp(distance * 0.48, gridUnit * 0.3, gridUnit * 0.56)
        arrow:ScaleTo(desiredLength / templateLength)
        arrow:PivotTo(getArrowForwardCFrame(center, -direction))
    elseif arrow:IsA("BasePart") then
        local templateLength = math.max(arrow.Size.X, 0.001)
        local desiredLength = math.clamp(distance * 0.48, gridUnit * 0.3, gridUnit * 0.56)
        local scale = desiredLength / templateLength
        arrow.Size = arrow.Size * scale
        arrow.CFrame = getArrowForwardCFrame(center, -direction)
    end

end

local function drawFlowArrow(fromCellX, fromCellZ, toCellX, toCellZ, color, plotInfo, gridUnit)
    local fromPosition = getPreviewCellWorldPosition(fromCellX, fromCellZ, plotInfo, gridUnit)
    local toPosition = getPreviewCellWorldPosition(toCellX, toCellZ, plotInfo, gridUnit)
    drawModelFlowArrow(fromPosition, toPosition, color, gridUnit)
end

local function drawFlowStopMarker(cellX, cellZ, color, plotInfo, gridUnit)
    local center = getPreviewCellWorldPosition(cellX, cellZ, plotInfo, gridUnit)
    drawModelFlowArrow(center - Vector3.xAxis * gridUnit * 0.28, center + Vector3.xAxis * gridUnit * 0.28, color, gridUnit)
end

local function classifyFlowTarget(target, nextInfo, visitedCells, plotInfo, gridUnit)
    if not areCellsValid(target.cellX, target.cellZ, 1, 1, plotInfo, gridUnit) then
        return FLOW_PREVIEW_COLORS.invalid, false
    end

    if not nextInfo then
        return FLOW_PREVIEW_COLORS.invalid, false
    end

    if visitedCells[cellKey(target.cellX, target.cellZ)] then
        return FLOW_PREVIEW_COLORS.invalid, false
    end

    if nextInfo.type == "machine" then
        local machineData = nextInfo.machineData or Definitions.GetMachine(nextInfo.itemName)
        if machineData and machineData.type == "processor" then
            return FLOW_PREVIEW_COLORS.terminal, true
        end

        return FLOW_PREVIEW_COLORS.invalid, false
    end

    if nextInfo.type == "sell_zone" then
        return FLOW_PREVIEW_COLORS.terminal, false
    end

    if not isFlowTransportType(nextInfo.type) then
        return FLOW_PREVIEW_COLORS.invalid, false
    end

    if not canTransportReceiveFrom(nextInfo, target.fromCellX, target.fromCellZ) then
        return FLOW_PREVIEW_COLORS.invalid, false
    end

    if target.isJunctionRoute or isFlowJunctionType(nextInfo.type) then
        return FLOW_PREVIEW_COLORS.junction, true
    end

    return FLOW_PREVIEW_COLORS.valid, true
end

local function copyVisitedCells(visitedCells)
    local copy = {}
    for key, value in pairs(visitedCells) do
        copy[key] = value
    end

    return copy
end

local function markFlowFootprintVisited(visitedCells, info)
    for dx = 0, info.cellsX - 1 do
        for dz = 0, info.cellsZ - 1 do
            visitedCells[cellKey(info.cellX + dx, info.cellZ + dz)] = true
        end
    end
end

local function renderFlowPreview(startInfo, plotInfo, gridUnit)
    if not startInfo or not isFlowSourceType(startInfo.type) then
        return
    end

    local lookup = buildFlowCellLookup(startInfo.isVirtual and startInfo or nil)
    local queue = {}
    for _, startState in ipairs(getFlowStartStates(startInfo)) do
        startState.visitedCells = {}
        markFlowFootprintVisited(startState.visitedCells, startInfo)
        startState.depth = 0
        table.insert(queue, startState)
    end

    local drawnSteps = 0
    if startInfo.type == "machine" then
        local machineData = startInfo.machineData or Definitions.GetMachine(startInfo.itemName)
        if machineData and machineData.type == "processor" then
            local inputCellX, inputCellZ = getMachineInputCell(startInfo)
            local toCellX, toCellZ = getAdjacentFootprintCell(startInfo, inputCellX, inputCellZ)
            local color = areCellsValid(inputCellX, inputCellZ, 1, 1, plotInfo, gridUnit) and FLOW_PREVIEW_COLORS.terminal or FLOW_PREVIEW_COLORS.invalid
            drawFlowArrow(inputCellX, inputCellZ, toCellX, toCellZ, color, plotInfo, gridUnit)
            drawnSteps += 1
        end
    end

    if startInfo.type == "merger" then
        for _, inputCell in pairs(getMergerInputCellsForPreview(startInfo)) do
            if drawnSteps >= FLOW_PREVIEW_MAX_STEPS then
                break
            end

            local toCellX, toCellZ = getAdjacentFootprintCell(startInfo, inputCell.cellX, inputCell.cellZ)
            local color = areCellsValid(inputCell.cellX, inputCell.cellZ, 1, 1, plotInfo, gridUnit) and FLOW_PREVIEW_COLORS.junction or FLOW_PREVIEW_COLORS.invalid
            drawFlowArrow(inputCell.cellX, inputCell.cellZ, toCellX, toCellZ, color, plotInfo, gridUnit)
            drawnSteps += 1
        end
    end

    while #queue > 0 and drawnSteps < FLOW_PREVIEW_MAX_STEPS do
        local state = table.remove(queue, 1)
        local currentInfo = lookup[cellKey(state.cellX, state.cellZ)]

        if not currentInfo or not isFlowSourceType(currentInfo.type) then
            break
        end

        local targets = getNextFlowTargets(currentInfo, state)
        if #targets == 0 then
            if state.previousCellX ~= nil and state.previousCellZ ~= nil then
                drawFlowArrow(state.previousCellX, state.previousCellZ, state.cellX, state.cellZ, FLOW_PREVIEW_COLORS.invalid, plotInfo, gridUnit)
                drawnSteps += 1
            else
                drawFlowStopMarker(state.cellX, state.cellZ, FLOW_PREVIEW_COLORS.invalid, plotInfo, gridUnit)
            end
        end

        for _, target in ipairs(targets) do
            if drawnSteps >= FLOW_PREVIEW_MAX_STEPS then
                break
            end

            local nextInfo = lookup[cellKey(target.cellX, target.cellZ)]
            local color, shouldContinue = classifyFlowTarget(target, nextInfo, state.visitedCells, plotInfo, gridUnit)
            drawFlowArrow(target.fromCellX, target.fromCellZ, target.cellX, target.cellZ, color, plotInfo, gridUnit)
            drawnSteps += 1

            if shouldContinue and state.depth < FLOW_PREVIEW_MAX_STEPS then
                local nextVisitedCells = copyVisitedCells(state.visitedCells)
                markFlowFootprintVisited(nextVisitedCells, nextInfo)
                table.insert(queue, {
                    cellX = target.cellX,
                    cellZ = target.cellZ,
                    previousCellX = target.fromCellX,
                    previousCellZ = target.fromCellZ,
                    visitedCells = nextVisitedCells,
                    depth = state.depth + 1,
                })
            end
        end
    end
end

local function updateFlowPreview(flowPreviewKey, startInfo)
    if not startInfo or not isFlowPreviewItem(startInfo.itemName) then
        clearFlowPreview()
        return
    end

    local plotInfo = getPlotInfo()
    if not plotInfo then
        clearFlowPreview()
        return
    end

    local gridUnit = currentGridUnit
    if gridUnit == 0 then
        gridUnit = getGridUnitSize()
    end

    if flowPreviewKey == lastFlowPreviewKey then
        return
    end

    clearFlowPreview()
    lastFlowPreviewKey = flowPreviewKey
    renderFlowPreview(startInfo, plotInfo, gridUnit)
end

local function updateFlowPreviewForPlacement(itemName, instance, cellX, cellZ, cellsX, cellsZ, rotation)
    if not isFlowPreviewItem(itemName) then
        clearFlowPreview()
        return
    end

    local startInfo = createFlowCellInfo(instance, itemName, cellX, cellZ, cellsX, cellsZ, rotation, true)
    local key = table.concat({
        "placement",
        itemName,
        tostring(cellX),
        tostring(cellZ),
        tostring(cellsX),
        tostring(cellsZ),
        tostring(rotation),
    }, ":")

    updateFlowPreview(key, startInfo)
end

local function updateFlowPreviewForSelectedItem(item)
    if not item or not item.Parent then
        clearFlowPreview()
        return
    end

    local itemName = item:GetAttribute("ItemName")
    if not isFlowPreviewItem(itemName) then
        clearFlowPreview()
        return
    end

    local startInfo = createFlowCellInfo(item)
    if not startInfo then
        clearFlowPreview()
        return
    end

    local key = table.concat({
        "selected",
        tostring(item),
        itemName,
        tostring(startInfo.cellX),
        tostring(startInfo.cellZ),
        tostring(startInfo.cellsX),
        tostring(startInfo.cellsZ),
        tostring(startInfo.rotation),
    }, ":")

    updateFlowPreview(key, startInfo)
end

-- Create Inventory UI
local existingInventoryGui = playerGui:FindFirstChild("InventoryUI")
if existingInventoryGui then
    existingInventoryGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "InventoryUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local function sanitizeFactorySignText(text)
    text = tostring(text or "")
    text = text:gsub("[%c\r\n\t]", " ")
    text = text:gsub("%s+", " ")
    text = text:match("^%s*(.-)%s*$") or ""

    if #text > MAX_FACTORY_SIGN_TEXT_LENGTH then
        text = text:sub(1, MAX_FACTORY_SIGN_TEXT_LENGTH)
    end

    return text
end

local function getFactorySignFromInstance(instance)
    local current = instance
    while current and current ~= workspace do
        if current:GetAttribute("ItemName") == "FactorySign" then
            return current
        end

        current = current.Parent
    end

    return nil
end

local function findFactorySignTextLabel(sign)
    local bestLabel = nil
    local bestScore = -1

    for _, descendant in ipairs(sign:GetDescendants()) do
        if descendant:IsA("TextLabel") or descendant:IsA("TextBox") then
            local score = 0
            local parent = descendant.Parent
            local lowerName = string.lower(descendant.Name)
            local lowerText = string.lower(tostring(descendant.Text or ""))

            if parent and parent:IsA("SurfaceGui") then
                score += 10
            end

            if lowerName == "textlabel" or lowerName == "label" or lowerName == "text" then
                score += 5
            end

            if lowerText == "text." or lowerText == "text" or lowerText == "factory" then
                score += 4
            end

            if score > bestScore then
                bestScore = score
                bestLabel = descendant
            end
        end
    end

    return bestLabel
end

local function getCurrentFactorySignText(sign)
    local attributeText = sign:GetAttribute("SignText")
    if type(attributeText) == "string" and attributeText ~= "" then
        return attributeText
    end

    local label = findFactorySignTextLabel(sign)
    if label and type(label.Text) == "string" and label.Text ~= "" then
        return label.Text
    end

    return "Text."
end

local function closeFactorySignEditor()
    activeFactorySign = nil

    if signEditorFrame then
        signEditorFrame.Visible = false
    end
end

local function submitFactorySignText()
    if not activeFactorySign or not activeFactorySign.Parent then
        closeFactorySignEditor()
        return
    end

    local text = sanitizeFactorySignText(signEditorTextBox.Text)
    signEditorTextBox.Text = text
    signEditorStatus.Text = "Salvataggio..."
    updateFactorySignTextRemote:FireServer(activeFactorySign, text)
end

local function createFactorySignEditor()
    if signEditorFrame then
        return
    end

    signEditorFrame = Instance.new("Frame")
    signEditorFrame.Name = "FactorySignEditor"
    signEditorFrame.AnchorPoint = Vector2.new(0.5, 1)
    signEditorFrame.Size = UDim2.new(0, 360, 0, 138)
    signEditorFrame.Position = UDim2.new(0.5, 0, 1, -118)
    signEditorFrame.BackgroundColor3 = Color3.fromRGB(28, 32, 36)
    signEditorFrame.BackgroundTransparency = 0.02
    signEditorFrame.BorderSizePixel = 0
    signEditorFrame.Visible = false
    signEditorFrame.ZIndex = 30
    signEditorFrame.Parent = screenGui

    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0, 8)
    frameCorner.Parent = signEditorFrame

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -28, 0, 26)
    title.Position = UDim2.fromOffset(14, 10)
    title.BackgroundTransparency = 1
    title.Text = "Factory Sign"
    title.TextColor3 = Color3.fromRGB(245, 248, 250)
    title.TextSize = 16
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 31
    title.Parent = signEditorFrame

    signEditorTextBox = Instance.new("TextBox")
    signEditorTextBox.Name = "SignTextInput"
    signEditorTextBox.Size = UDim2.new(1, -28, 0, 42)
    signEditorTextBox.Position = UDim2.fromOffset(14, 42)
    signEditorTextBox.BackgroundColor3 = Color3.fromRGB(44, 50, 56)
    signEditorTextBox.BorderSizePixel = 0
    signEditorTextBox.ClearTextOnFocus = false
    signEditorTextBox.PlaceholderText = "Testo del cartello"
    signEditorTextBox.Text = ""
    signEditorTextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    signEditorTextBox.PlaceholderColor3 = Color3.fromRGB(150, 158, 166)
    signEditorTextBox.TextSize = 16
    signEditorTextBox.Font = Enum.Font.Gotham
    signEditorTextBox.TextXAlignment = Enum.TextXAlignment.Left
    signEditorTextBox.ZIndex = 31
    signEditorTextBox.Parent = signEditorFrame

    local inputCorner = Instance.new("UICorner")
    inputCorner.CornerRadius = UDim.new(0, 6)
    inputCorner.Parent = signEditorTextBox

    signEditorStatus = Instance.new("TextLabel")
    signEditorStatus.Name = "Status"
    signEditorStatus.Size = UDim2.new(1, -180, 0, 30)
    signEditorStatus.Position = UDim2.fromOffset(14, 94)
    signEditorStatus.BackgroundTransparency = 1
    signEditorStatus.Text = ""
    signEditorStatus.TextColor3 = Color3.fromRGB(196, 207, 218)
    signEditorStatus.TextSize = 12
    signEditorStatus.Font = Enum.Font.Gotham
    signEditorStatus.TextXAlignment = Enum.TextXAlignment.Left
    signEditorStatus.ZIndex = 31
    signEditorStatus.Parent = signEditorFrame

    local cancelButton = Instance.new("TextButton")
    cancelButton.Name = "CancelButton"
    cancelButton.Size = UDim2.new(0, 70, 0, 30)
    cancelButton.Position = UDim2.new(1, -156, 1, -44)
    cancelButton.BackgroundColor3 = Color3.fromRGB(62, 68, 74)
    cancelButton.BorderSizePixel = 0
    cancelButton.Text = "Annulla"
    cancelButton.TextColor3 = Color3.fromRGB(235, 240, 246)
    cancelButton.TextSize = 13
    cancelButton.Font = Enum.Font.GothamBold
    cancelButton.ZIndex = 31
    cancelButton.Parent = signEditorFrame

    local cancelCorner = Instance.new("UICorner")
    cancelCorner.CornerRadius = UDim.new(0, 6)
    cancelCorner.Parent = cancelButton

    local saveButton = Instance.new("TextButton")
    saveButton.Name = "SaveButton"
    saveButton.Size = UDim2.new(0, 70, 0, 30)
    saveButton.Position = UDim2.new(1, -82, 1, -44)
    saveButton.BackgroundColor3 = Color3.fromRGB(62, 142, 88)
    saveButton.BorderSizePixel = 0
    saveButton.Text = "Salva"
    saveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    saveButton.TextSize = 13
    saveButton.Font = Enum.Font.GothamBold
    saveButton.ZIndex = 31
    saveButton.Parent = signEditorFrame

    local saveCorner = Instance.new("UICorner")
    saveCorner.CornerRadius = UDim.new(0, 6)
    saveCorner.Parent = saveButton

    signEditorTextBox:GetPropertyChangedSignal("Text"):Connect(function()
        if #signEditorTextBox.Text > MAX_FACTORY_SIGN_TEXT_LENGTH then
            signEditorTextBox.Text = signEditorTextBox.Text:sub(1, MAX_FACTORY_SIGN_TEXT_LENGTH)
        elseif signEditorFrame.Visible then
            signEditorStatus.Text = tostring(#signEditorTextBox.Text) .. "/" .. tostring(MAX_FACTORY_SIGN_TEXT_LENGTH)
        end
    end)

    signEditorTextBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            submitFactorySignText()
        end
    end)

    cancelButton.Activated:Connect(closeFactorySignEditor)
    saveButton.Activated:Connect(submitFactorySignText)
end

local function showFactorySignEditor(sign)
    if placementMode or deletionMode then
        return
    end

    createFactorySignEditor()

    if itemContextMenu then
        itemContextMenu.Visible = false
    end

    activeFactorySign = sign
    signEditorTextBox.Text = sanitizeFactorySignText(getCurrentFactorySignText(sign))
    signEditorStatus.Text = tostring(#signEditorTextBox.Text) .. "/" .. tostring(MAX_FACTORY_SIGN_TEXT_LENGTH)
    signEditorFrame.Visible = true
    signEditorTextBox:CaptureFocus()
end

local function hideItemContextMenu()
    if contextMenuTween then
        contextMenuTween:Cancel()
        contextMenuTween = nil
    end

    if itemContextBillboard then
        itemContextBillboard.Enabled = false
        itemContextBillboard.Adornee = nil
    end

    if itemContextAttachment then
        itemContextAttachment:Destroy()
        itemContextAttachment = nil
    end

    if itemContextMenu then
        itemContextMenu.Visible = false
    end
    contextMenuTarget = nil

    if not placementMode then
        clearFlowPreview()
    end
end

local function getContextMenuWorldPosition()
    if itemContextAttachment then
        return itemContextAttachment.WorldPosition
    end

    if itemContextBillboard and itemContextBillboard.Adornee then
        local adornee = itemContextBillboard.Adornee
        if adornee:IsA("Attachment") then
            return adornee.WorldPosition
        elseif adornee:IsA("BasePart") then
            return adornee.Position + itemContextBillboard.StudsOffsetWorldSpace
        end
    end

    return nil
end

local function isMouseInsideContextMenu()
    if not itemContextMenu or not itemContextMenu.Visible then
        return false
    end

    local mousePos = UserInputService:GetMouseLocation()
    if itemContextBillboard and itemContextBillboard.Enabled and itemContextBillboard.Adornee then
        local camera = workspace.CurrentCamera
        local worldPosition = getContextMenuWorldPosition()
        if worldPosition then
            local screenPosition, onScreen = camera:WorldToViewportPoint(worldPosition)
            if not onScreen then
                return false
            end

            local menuSize = itemContextBillboard.AbsoluteSize
            if menuSize.X <= 0 or menuSize.Y <= 0 then
                menuSize = Vector2.new(130, 44)
            end

            local menuLeft = screenPosition.X - menuSize.X / 2
            local menuTop = screenPosition.Y - menuSize.Y / 2

            return mousePos.X >= menuLeft and mousePos.X <= menuLeft + menuSize.X and
                   mousePos.Y >= menuTop and mousePos.Y <= menuTop + menuSize.Y
        end
    end

    local menuPos = itemContextMenu.AbsolutePosition
    local menuSize = itemContextMenu.AbsoluteSize

    return mousePos.X >= menuPos.X and mousePos.X <= menuPos.X + menuSize.X and
           mousePos.Y >= menuPos.Y and mousePos.Y <= menuPos.Y + menuSize.Y
end

local function rotateContextMenuTarget()
    if tick() - lastContextRotateAt < 0.15 then
        return
    end

    lastContextRotateAt = tick()

    if contextMenuTarget and contextMenuTarget.Parent then
        local nextRotation = ((contextMenuTarget:GetAttribute("Rotation") or 0) + 1) % 4
        local cellsX = contextMenuTarget:GetAttribute("CellsX") or 1
        local cellsZ = contextMenuTarget:GetAttribute("CellsZ") or 1
        if cellsX ~= cellsZ then
            cellsX, cellsZ = cellsZ, cellsX
        end

        local pivot = contextMenuTarget:GetPivot()
        local nextPosition = pivot.Position
        local nextFootprintCenter = nil
        local nextGroundY = nil
        local cellX = contextMenuTarget:GetAttribute("CellX")
        local cellZ = contextMenuTarget:GetAttribute("CellZ")
        local plotInfo = getPlotInfo()
        if cellX ~= nil and cellZ ~= nil and plotInfo then
            local gridUnit = getGridUnitSize()
            if not areCellsValid(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit) or isAreaOccupied(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit, contextMenuTarget) then
                placementIndicator.Visible = true
                placementIndicator.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
                indicatorText.Text = "Cannot rotate here"
                hideItemContextMenu()
                return
            end

            local footprintCenter = getFootprintCenter(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit)
            nextFootprintCenter = footprintCenter
            nextGroundY = footprintCenter.Y
            nextPosition = Vector3.new(footprintCenter.X, pivot.Position.Y, footprintCenter.Z)
        end

        rotateItemRemote:FireServer(contextMenuTarget)
        contextMenuTarget:SetAttribute("Rotation", nextRotation)
        contextMenuTarget:SetAttribute("CellsX", cellsX)
        contextMenuTarget:SetAttribute("CellsZ", cellsZ)
        if contextMenuTarget:GetAttribute("ItemName") == "CurvedConveyor" and nextFootprintCenter and nextGroundY then
            pivotModelToFootprint(contextMenuTarget, nextFootprintCenter, nextGroundY, nextRotation)
        else
            contextMenuTarget:PivotTo(CFrame.new(nextPosition) * getRotationCFrame(nextRotation))
        end
    end

    hideItemContextMenu()
end

local function isMachineContextTarget(target)
    local itemName = target and target:GetAttribute("ItemName")
    return itemName ~= nil and Definitions.GetMachine(itemName) ~= nil
end

local function updateItemContextMenuContents(target)
    if not itemContextBillboard or not itemContextMenu then
        return
    end

    local rotateButton = itemContextMenu:FindFirstChild("RotateButton")
    local machinePanel = itemContextMenu:FindFirstChild("MachineInfoPanel")
    local isMachine = isMachineContextTarget(target)

    if isMachine then
        itemContextBillboard.Size = UDim2.new(0, 230, 0, 128)
        if rotateButton then
            rotateButton.Size = UDim2.new(1, -8, 0, 34)
            rotateButton.Position = UDim2.new(0, 4, 1, -38)
        end

        if machinePanel then
            machinePanel.Visible = true

            local itemName = target:GetAttribute("ItemName")
            local machineData = Definitions.GetMachine(itemName)
            local recipeText = target:GetAttribute("MachineRecipeText")
            local queueText = target:GetAttribute("MachineQueueText")
            local statusText = target:GetAttribute("MachineStatusText")
            local progress = math.clamp(tonumber(target:GetAttribute("ProcessingProgress")) or 0, 0, 1)

            if not recipeText or recipeText == "" then
                if machineData and machineData.type == "processor" then
                    recipeText = tostring(machineData.inputItem or "Input") .. " -> " .. tostring(machineData.outputItem or "Output")
                elseif machineData and machineData.type == "producer" then
                    recipeText = "Produces " .. tostring(machineData.outputItem or "Output")
                else
                    recipeText = itemName
                end
            end

            if not queueText or queueText == "" then
                if machineData and machineData.type == "processor" then
                    local count = tonumber(target:GetAttribute("ProcessingCount")) or 0
                    local capacity = tonumber(target:GetAttribute("ProcessingCapacity")) or machineData.inputQueueSize or 0
                    queueText = "Queue " .. tostring(count) .. "/" .. tostring(capacity)
                else
                    queueText = ""
                end
            end

            if not statusText or statusText == "" then
                statusText = target:GetAttribute("IsPowered") == false and "No power" or "Ready"
            end

            local titleLabel = machinePanel:FindFirstChild("MachineTitle")
            if titleLabel and titleLabel:IsA("TextLabel") then
                titleLabel.Text = itemName
            end

            local recipeLabel = machinePanel:FindFirstChild("MachineRecipe")
            if recipeLabel and recipeLabel:IsA("TextLabel") then
                recipeLabel.Text = recipeText
            end

            local queueLabel = machinePanel:FindFirstChild("MachineQueue")
            if queueLabel and queueLabel:IsA("TextLabel") then
                queueLabel.Text = queueText
            end

            local statusLabel = machinePanel:FindFirstChild("MachineStatus")
            if statusLabel and statusLabel:IsA("TextLabel") then
                statusLabel.Text = statusText
                statusLabel.TextColor3 = target:GetAttribute("IsPowered") == false and Color3.fromRGB(255, 126, 96) or Color3.fromRGB(170, 220, 255)
            end

            local progressBack = machinePanel:FindFirstChild("ProgressBack")
            local progressFill = progressBack and progressBack:FindFirstChild("ProgressFill")
            if progressFill and progressFill:IsA("Frame") then
                progressFill.Size = UDim2.fromScale(progress, 1)
            end
        end
    else
        itemContextBillboard.Size = UDim2.new(0, 130, 0, 44)
        if machinePanel then
            machinePanel.Visible = false
        end

        if rotateButton then
            rotateButton.Size = UDim2.new(1, -8, 1, -8)
            rotateButton.Position = UDim2.new(0, 4, 0, 4)
        end
    end
end

local function createItemContextMenu()
    if itemContextMenu then
        return
    end

    itemContextBillboard = Instance.new("BillboardGui")
    itemContextBillboard.Name = "ItemContextBillboard"
    itemContextBillboard.Size = UDim2.new(0, 130, 0, 44)
    itemContextBillboard.AlwaysOnTop = true
    itemContextBillboard.LightInfluence = 0
    itemContextBillboard.MaxDistance = 120
    itemContextBillboard.Enabled = false
    itemContextBillboard.Parent = screenGui

    itemContextMenu = Instance.new("Frame")
    itemContextMenu.Name = "ItemContextMenu"
    itemContextMenu.AnchorPoint = Vector2.new(0.5, 0.5)
    itemContextMenu.Size = UDim2.new(1, 0, 1, 0)
    itemContextMenu.Position = UDim2.new(0.5, 0, 0.5, 0)
    itemContextMenu.BackgroundColor3 = Color3.fromRGB(22, 52, 64)
    itemContextMenu.BackgroundTransparency = 0.28
    itemContextMenu.BorderSizePixel = 0
    itemContextMenu.Active = true
    itemContextMenu.ZIndex = 10
    itemContextMenu.Visible = false
    itemContextMenu.Parent = itemContextBillboard

    local menuCorner = Instance.new("UICorner")
    menuCorner.CornerRadius = UDim.new(0, 8)
    menuCorner.Parent = itemContextMenu

    local machinePanel = Instance.new("Frame")
    machinePanel.Name = "MachineInfoPanel"
    machinePanel.Size = UDim2.new(1, -12, 0, 82)
    machinePanel.Position = UDim2.fromOffset(6, 6)
    machinePanel.BackgroundTransparency = 1
    machinePanel.Visible = false
    machinePanel.ZIndex = 11
    machinePanel.Parent = itemContextMenu

    local machineTitle = Instance.new("TextLabel")
    machineTitle.Name = "MachineTitle"
    machineTitle.Size = UDim2.new(1, 0, 0, 18)
    machineTitle.BackgroundTransparency = 1
    machineTitle.TextColor3 = Color3.fromRGB(245, 248, 250)
    machineTitle.TextSize = 13
    machineTitle.Font = Enum.Font.GothamBold
    machineTitle.TextXAlignment = Enum.TextXAlignment.Left
    machineTitle.TextTruncate = Enum.TextTruncate.AtEnd
    machineTitle.ZIndex = 12
    machineTitle.Parent = machinePanel

    local machineRecipe = Instance.new("TextLabel")
    machineRecipe.Name = "MachineRecipe"
    machineRecipe.Size = UDim2.new(1, 0, 0, 18)
    machineRecipe.Position = UDim2.fromOffset(0, 20)
    machineRecipe.BackgroundTransparency = 1
    machineRecipe.TextColor3 = Color3.fromRGB(236, 230, 208)
    machineRecipe.TextSize = 12
    machineRecipe.Font = Enum.Font.Gotham
    machineRecipe.TextXAlignment = Enum.TextXAlignment.Left
    machineRecipe.TextTruncate = Enum.TextTruncate.AtEnd
    machineRecipe.ZIndex = 12
    machineRecipe.Parent = machinePanel

    local machineQueue = Instance.new("TextLabel")
    machineQueue.Name = "MachineQueue"
    machineQueue.Size = UDim2.new(0.55, -4, 0, 18)
    machineQueue.Position = UDim2.fromOffset(0, 40)
    machineQueue.BackgroundTransparency = 1
    machineQueue.TextColor3 = Color3.fromRGB(210, 218, 225)
    machineQueue.TextSize = 12
    machineQueue.Font = Enum.Font.Gotham
    machineQueue.TextXAlignment = Enum.TextXAlignment.Left
    machineQueue.TextTruncate = Enum.TextTruncate.AtEnd
    machineQueue.ZIndex = 12
    machineQueue.Parent = machinePanel

    local machineStatus = Instance.new("TextLabel")
    machineStatus.Name = "MachineStatus"
    machineStatus.Size = UDim2.new(0.45, -4, 0, 18)
    machineStatus.Position = UDim2.new(0.55, 4, 0, 40)
    machineStatus.BackgroundTransparency = 1
    machineStatus.TextColor3 = Color3.fromRGB(170, 220, 255)
    machineStatus.TextSize = 12
    machineStatus.Font = Enum.Font.GothamBold
    machineStatus.TextXAlignment = Enum.TextXAlignment.Right
    machineStatus.TextTruncate = Enum.TextTruncate.AtEnd
    machineStatus.ZIndex = 12
    machineStatus.Parent = machinePanel

    local progressBack = Instance.new("Frame")
    progressBack.Name = "ProgressBack"
    progressBack.Size = UDim2.new(1, 0, 0, 8)
    progressBack.Position = UDim2.fromOffset(0, 64)
    progressBack.BackgroundColor3 = Color3.fromRGB(18, 35, 42)
    progressBack.BackgroundTransparency = 0.32
    progressBack.BorderSizePixel = 0
    progressBack.ZIndex = 12
    progressBack.Parent = machinePanel

    local progressFill = Instance.new("Frame")
    progressFill.Name = "ProgressFill"
    progressFill.Size = UDim2.fromScale(0, 1)
    progressFill.BackgroundColor3 = Color3.fromRGB(84, 205, 190)
    progressFill.BorderSizePixel = 0
    progressFill.ZIndex = 13
    progressFill.Parent = progressBack

    local rotateButton = Instance.new("TextButton")
    rotateButton.Name = "RotateButton"
    rotateButton.Size = UDim2.new(1, -8, 1, -8)
    rotateButton.Position = UDim2.new(0, 4, 0, 4)
    rotateButton.BackgroundColor3 = Color3.fromRGB(50, 116, 132)
    rotateButton.BackgroundTransparency = 0.18
    rotateButton.BorderSizePixel = 0
    rotateButton.Active = true
    rotateButton.ZIndex = 11
    rotateButton.Text = "Rotate"
    rotateButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    rotateButton.TextSize = 14
    rotateButton.Font = Enum.Font.GothamBold
    rotateButton.Parent = itemContextMenu

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 6)
    buttonCorner.Parent = rotateButton

    rotateButton.Activated:Connect(rotateContextMenuTarget)
end

local function getItemContextAdornee(target)
    if target:IsA("BasePart") then
        return target
    end

    if target:IsA("Model") then
        if target.PrimaryPart then
            return target.PrimaryPart
        end

        for _, descendant in ipairs(target:GetDescendants()) do
            if descendant:IsA("BasePart") then
                return descendant
            end
        end
    end

    return nil
end

local function attachContextMenuToTarget(target)
    local adornee = getItemContextAdornee(target)
    if not adornee then
        return false
    end

    if itemContextAttachment then
        itemContextAttachment:Destroy()
        itemContextAttachment = nil
    end

    local targetCenter
    local targetSize
    if target:IsA("Model") then
        local targetCFrame
        targetCFrame, targetSize = target:GetBoundingBox()
        targetCenter = targetCFrame.Position
    elseif target:IsA("BasePart") then
        targetCenter = target.Position
        targetSize = target.Size
    else
        return false
    end

    local menuWorldPosition = targetCenter + Vector3.new(0, targetSize.Y / 2 + 1.25, 0)
    itemContextAttachment = Instance.new("Attachment")
    itemContextAttachment.Name = "ItemContextMenuAttachment"
    itemContextAttachment.Position = adornee.CFrame:PointToObjectSpace(menuWorldPosition)
    itemContextAttachment.Parent = adornee

    itemContextBillboard.Adornee = itemContextAttachment
    itemContextBillboard.StudsOffsetWorldSpace = Vector3.zero
    itemContextBillboard.Enabled = true

    return true
end

local function showItemContextMenu(target)
    createItemContextMenu()
    if contextMenuTarget == target and itemContextMenu.Visible then
        return
    end

    if not attachContextMenuToTarget(target) then
        return
    end

    contextMenuTarget = target
    updateItemContextMenuContents(target)
    updateFlowPreviewForSelectedItem(target)

    local finalPosition = UDim2.new(0.5, 0, 0.5, 0)
    itemContextMenu.Position = UDim2.new(0.5, 0, 0.75, 0)
    itemContextMenu.BackgroundTransparency = 1
    itemContextMenu.Visible = true

    local rotateButton = itemContextMenu:FindFirstChild("RotateButton")
    if rotateButton then
        rotateButton.BackgroundTransparency = 1
        rotateButton.TextTransparency = 1
    end

    if contextMenuTween then
        contextMenuTween:Cancel()
    end

    contextMenuTween = TweenService:Create(itemContextMenu, TweenInfo.new(
        0.16,
        Enum.EasingStyle.Back,
        Enum.EasingDirection.Out
    ), {
        Position = finalPosition,
        BackgroundTransparency = 0.28,
    })
    contextMenuTween:Play()

    if rotateButton then
        TweenService:Create(rotateButton, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0.18,
            TextTransparency = 0,
        }):Play()
    end
end

-- Main inventory frame
local inventoryFrame = Instance.new("Frame")
inventoryFrame.Name = "InventoryFrame"
inventoryFrame.Size = UDim2.new(0, 450, 0, 100)
inventoryFrame.Position = UDim2.new(0.5, -225, 1, -120)
inventoryFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
inventoryFrame.BackgroundTransparency = 0.2
inventoryFrame.BorderSizePixel = 0
inventoryFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = inventoryFrame

-- Title
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(0, 100, 0, 25)
title.Position = UDim2.new(0, 10, 0, 5)
title.BackgroundTransparency = 1
title.Text = "INVENTORY"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 16
title.Font = Enum.Font.GothamBold
title.TextStrokeTransparency = 0.5
title.Parent = inventoryFrame

-- Items container
local itemsContainer = Instance.new("Frame")
itemsContainer.Name = "ItemsContainer"
itemsContainer.Size = UDim2.new(1, -80, 0, 60)
itemsContainer.Position = UDim2.new(0, 10, 0, 30)
itemsContainer.BackgroundTransparency = 1
itemsContainer.Parent = inventoryFrame

local itemsLayout = Instance.new("UIGridLayout")
itemsLayout.CellSize = UDim2.new(0, 55, 0, 55)
itemsLayout.CellPadding = UDim2.new(0, 5, 0, 5)
itemsLayout.Parent = itemsContainer

-- Delete button
local deleteButton = Instance.new("TextButton")
deleteButton.Name = "DeleteButton"
deleteButton.Size = UDim2.new(0, 50, 0, 50)
deleteButton.Position = UDim2.new(1, -60, 0.5, -25)
deleteButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
deleteButton.BackgroundTransparency = 0.5
deleteButton.BorderSizePixel = 0
deleteButton.Text = ""
deleteButton.Parent = inventoryFrame

local deleteCorner = Instance.new("UICorner")
deleteCorner.CornerRadius = UDim.new(0, 8)
deleteCorner.Parent = deleteButton

local trashIcon = Instance.new("TextLabel")
trashIcon.Size = UDim2.new(1, 0, 1, 0)
trashIcon.BackgroundTransparency = 1
trashIcon.Text = "🗑️"
trashIcon.TextSize = 28
trashIcon.Parent = deleteButton

-- Placement indicator
placementIndicator = Instance.new("Frame")
placementIndicator.Name = "PlacementIndicator"
placementIndicator.Size = UDim2.new(0, 300, 0, 50)
placementIndicator.Position = UDim2.new(0.5, -150, 0.1, 0)
placementIndicator.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
placementIndicator.BackgroundTransparency = 0.3
placementIndicator.BorderSizePixel = 0
placementIndicator.Visible = false
placementIndicator.Parent = screenGui

local indicatorCorner = Instance.new("UICorner")
indicatorCorner.CornerRadius = UDim.new(0, 8)
indicatorCorner.Parent = placementIndicator

indicatorText = Instance.new("TextLabel")
indicatorText.Size = UDim2.new(1, 0, 1, 0)
indicatorText.BackgroundTransparency = 1
indicatorText.Text = "Click to place | Click button to cancel"
indicatorText.TextColor3 = Color3.fromRGB(255, 255, 255)
indicatorText.TextSize = 14
indicatorText.Font = Enum.Font.GothamBold
indicatorText.Parent = placementIndicator

-- Function to calculate scale to fit the item's base footprint
local function calculateItemScaleForFootprint(item, itemName, gridUnit, cellsX, cellsZ)
    local itemSize = nil
    if itemName == "CurvedConveyor" then
        local _, visibleSize = getVisibleBounds(item)
        if visibleSize then
            itemSize = visibleSize
        end
    end

    if not itemSize then
        local _, boundingSize = item:GetBoundingBox()
        itemSize = boundingSize
    end

    if itemSize.X <= 0 or itemSize.Z <= 0 then
        return 1
    end

    local footprintPadding = getItemFootprintPadding(itemName)
    local adjustment = ITEM_VISUAL_ADJUSTMENTS[itemName]
    
    local scaleX = (gridUnit * cellsX * footprintPadding) / itemSize.X
    local scaleZ = (gridUnit * cellsZ * footprintPadding) / itemSize.Z
    local scaleFactor = math.min(scaleX, scaleZ)

    if adjustment and adjustment.maxScale then
        scaleFactor = math.min(scaleFactor, adjustment.maxScale)
    end
    
    return scaleFactor
end

-- Function to create a ghost item
local function createGhostItem(itemName)
    if ghostItem then
        ghostItem:Destroy()
        ghostItem = nil
    end
    
    local itemTemplate = templatesFolder:FindFirstChild(itemName)
    if not itemTemplate then return nil end

    local newGhost = itemTemplate:Clone()

    newGhost.Name = "GhostItem"
    if itemName == "CurvedConveyor" then
        prepareCurvedConveyorVisuals(newGhost)
    end
    
    -- Calculate and apply scaling to fit the item's base grid footprint.
    local gridUnit = getGridUnitSize()
    local cellsX, cellsZ = getItemBaseFootprint(itemName)
    currentScaleFactor = calculateItemScaleForFootprint(newGhost, itemName, gridUnit, cellsX, cellsZ)
    
    -- Scale the model to fit in one cell
    local currentScale = newGhost:GetScale()
    newGhost:ScaleTo(currentScale * currentScaleFactor)
    applyItemVisualAdjustments(newGhost, itemName)
    
    for _, desc in ipairs(newGhost:GetDescendants()) do
        if desc:IsA("BasePart") or desc:IsA("MeshPart") then
            desc.Transparency = GHOST_TRANSPARENCY
            desc.CanCollide = false
            desc.CanQuery = false
            desc.CanTouch = false
            desc.Anchored = true
        end
    end
    
    newGhost.Parent = workspace.CurrentCamera
    return newGhost
end

-- Function to destroy ghost item
local function destroyGhostItem()
    if ghostItem then
        ghostItem:Destroy()
        ghostItem = nil
    end
end

-- Function to check if position is within plot bounds
local function isWithinPlotBounds(position, plotInfo)
    if not plotInfo then return false end
    
    local halfPlotSize = plotInfo.size / 2
    
    return position.X >= plotInfo.position.X - halfPlotSize.X and
           position.X <= plotInfo.position.X + halfPlotSize.X and
           position.Z >= plotInfo.position.Z - halfPlotSize.Z and
           position.Z <= plotInfo.position.Z + halfPlotSize.Z
end

local function normalizeInventoryList(rawInventory)
    local totals = {}
    local order = {}

    for _, item in ipairs(rawInventory or {}) do
        local itemName = item.itemName
        local count = tonumber(item.count) or 0

        if itemName and count > 0 then
            if not totals[itemName] then
                totals[itemName] = 0
                table.insert(order, itemName)
            end

            totals[itemName] = totals[itemName] + count
        end
    end

    local normalized = {}
    for _, itemName in ipairs(order) do
        table.insert(normalized, {
            itemName = itemName,
            count = totals[itemName],
        })
    end

    return normalized
end

local inventoryRefreshToken = 0

-- Function to refresh inventory UI
local function refreshInventoryUI()
    inventoryRefreshToken = inventoryRefreshToken + 1
    local thisRefreshToken = inventoryRefreshToken

    local success, result = pcall(function()
        return getInventoryRemote:InvokeServer()
    end)

    if thisRefreshToken ~= inventoryRefreshToken then
        return
    end

    for _, child in ipairs(itemsContainer:GetChildren()) do
        if child:IsA("ImageButton") then
            child:Destroy()
        end
    end
    
    if success and result then
        inventory = normalizeInventoryList(result)
    else
        inventory = {}
    end
    
    for i, item in ipairs(inventory) do
        local itemButton = Instance.new("ImageButton")
        itemButton.Name = item.itemName
        itemButton.Size = UDim2.new(0, 55, 0, 55)
        itemButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        itemButton.BackgroundTransparency = 0.5
        itemButton.BorderSizePixel = 0
        itemButton.Parent = itemsContainer
        
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 8)
        btnCorner.Parent = itemButton
        
        local iconLabel = Instance.new("TextLabel")
        iconLabel.Size = UDim2.new(0.6, 0, 0.6, 0)
        iconLabel.Position = UDim2.new(0.2, 0, 0.1, 0)
        iconLabel.BackgroundTransparency = 1
        iconLabel.Text = getItemIcon(item.itemName)
        iconLabel.TextSize = 24
        iconLabel.Parent = itemButton
        
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, 0, 0, 18)
        nameLabel.Position = UDim2.new(0, 0, 1, -20)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = item.itemName
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextSize = 9
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Parent = itemButton
        
        local countLabel = Instance.new("TextLabel")
        countLabel.Size = UDim2.new(0, 22, 0, 22)
        countLabel.Position = UDim2.new(1, -24, 0, 2)
        countLabel.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
        countLabel.BackgroundTransparency = 0.2
        countLabel.Text = tostring(item.count)
        countLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        countLabel.TextSize = 11
        countLabel.Font = Enum.Font.GothamBold
        countLabel.Parent = itemButton
        
        local countCorner = Instance.new("UICorner")
        countCorner.CornerRadius = UDim.new(0, 4)
        countCorner.Parent = countLabel
        
        itemButton.MouseButton1Click:Connect(function()
            -- Exit deletion mode if active
            if deletionMode then
                deletionMode = false
                deleteButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
                placementIndicator.Visible = false
                removeSelectionBox()
                hoveredDeleteItem = nil
                clearFlowPreview()
            end
            
            -- Exit previous placement mode
            if placementMode then
                destroyGhostItem()
                placementMode = false
                placementRotation = 0
                placementIndicator.Visible = false
                selectedItem = nil
                removeGridVisualization()
                clearFlowPreview()
            end
            
            selectedItem = item.itemName
            placementRotation = 0
            placementMode = true
            placementIndicator.Visible = true
            placementIndicator.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
            indicatorText.Text = "Click to place | R to rotate | Click button to cancel"
            
            ghostItem = createGhostItem(selectedItem)
            createGridVisualization()
        end)
    end
end

-- Delete button click handler
deleteButton.MouseButton1Click:Connect(function()
    if placementMode then
        -- Exit placement mode
        placementMode = false
        placementRotation = 0
        placementIndicator.Visible = false
        destroyGhostItem()
        selectedItem = nil
        removeGridVisualization()
        clearFlowPreview()
    end
    
    -- Toggle deletion mode
    deletionMode = not deletionMode
    
    if deletionMode then
        clearFlowPreview()
        deleteButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        placementIndicator.Visible = true
        placementIndicator.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        indicatorText.Text = "DELETE MODE: Click item to remove | Click button to exit"
    else
        deleteButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        placementIndicator.Visible = false
        removeSelectionBox()
        hoveredDeleteItem = nil
        clearFlowPreview()
    end
end)

-- Function to update highlight box position and size
local function updateHighlightBox(cellX, cellZ, cellsX, cellsZ, isValid)
    if not highlightBox then return end
    
    local gridUnit = currentGridUnit
    if gridUnit == 0 then gridUnit = getGridUnitSize() end
    
    local plotInfo = getPlotInfo()
    if not plotInfo then return end
    
    local plotTop = plotInfo.position.Y + plotInfo.size.Y / 2 + 0.1
    
    local cellCenter = getFootprintCenter(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit)
    
    -- Update highlight box (for 1x1 cells, size is just gridUnit)
    highlightBox.Size = Vector3.new(cellsX * gridUnit, 0.2, cellsZ * gridUnit)
    highlightBox.CFrame = CFrame.new(cellCenter.X, plotTop, cellCenter.Z)
    
    if isValid then
        highlightBox.Color = Color3.fromRGB(50, 200, 50)
        highlightBox.Transparency = 0.3
    else
        highlightBox.Color = Color3.fromRGB(200, 50, 50)
        highlightBox.Transparency = 0.3
    end
end

-- Function to update ghost position
local function updateGhostPosition()
    if placementMode and ghostItem then
        local plotInfo = getPlotInfo()
        if not plotInfo then
            ghostItem.Parent = nil
            placementIndicator.Visible = false
            clearFlowPreview()
            return
        end
        
        local gridUnit = getGridUnitSize()
        
        local camera = workspace.CurrentCamera
        local mousePos = UserInputService:GetMouseLocation()
        local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
        
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = {ghostItem}
        if player.Character then
            table.insert(rayParams.FilterDescendantsInstances, player.Character)
        end
        
        local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
        
        if result and result.Instance then
            local hitPos = result.Position
            
            if not isWithinPlotBounds(hitPos, plotInfo) then
                ghostItem.Parent = nil
                placementIndicator.Visible = true
                placementIndicator.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
                indicatorText.Text = "Outside plot! | Click button to cancel"
                canPlace = false
                clearFlowPreview()
                return
            end
            
            local cellX, cellZ = worldToGrid(hitPos, plotInfo, gridUnit)
            local cellsX, cellsZ = getRotatedFootprint(selectedItem, placementRotation)
            
            if not areCellsValid(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit) then
                ghostItem.Parent = nil
                placementIndicator.Visible = true
                placementIndicator.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
                indicatorText.Text = "Outside plot! | Click button to cancel"
                canPlace = false
                updateHighlightBox(cellX, cellZ, cellsX, cellsZ, false)
                clearFlowPreview()
                return
            end
            
            if isAreaOccupied(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit) then
                ghostItem.Parent = nil
                placementIndicator.Visible = true
                placementIndicator.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
                indicatorText.Text = "Space occupied! | Click button to cancel"
                canPlace = false
                updateHighlightBox(cellX, cellZ, cellsX, cellsZ, false)
                clearFlowPreview()
                return
            end
            
            ghostItem.Parent = workspace.CurrentCamera
            placementIndicator.Visible = true
            placementIndicator.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
            indicatorText.Text = "Click to place | R to rotate | Click button to cancel"
            
            updateHighlightBox(cellX, cellZ, cellsX, cellsZ, true)
            
            local worldPos = getFootprintCenter(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit)
            
            canPlace = true
            if selectedItem == "CurvedConveyor" then
                pivotModelToFootprint(ghostItem, worldPos, worldPos.Y, placementRotation)
            else
                local itemHeight = getItemHeight(ghostItem)
                local finalY = worldPos.Y + itemHeight / 2

                ghostItem:PivotTo(CFrame.new(
                    worldPos.X,
                    finalY,
                    worldPos.Z
                ) * getRotationCFrame(placementRotation))
            end

            updateFlowPreviewForPlacement(selectedItem, ghostItem, cellX, cellZ, cellsX, cellsZ, placementRotation)
        end
    end
end

-- Function to update deletion hover
local function updateDeletionHover()
    if deletionMode then
        local foundItem = getOwnedPlacedItemFromRay()
        
        -- Update hover state
        if foundItem ~= hoveredDeleteItem then
            -- Remove highlight from previous
            if hoveredDeleteItem then
                removeSelectionBox()
            end
            
            -- Add highlight to new
            if foundItem then
                createSelectionBox(foundItem)
            end
            
            hoveredDeleteItem = foundItem
        end
    end
end

local function updatePlacedItemHoverMenu()
    if placementMode or deletionMode then
        hoveredPlacedItem = nil
        placedItemHoverStartedAt = nil
        placedItemHoverEndedAt = nil
        hideItemContextMenu()
        return
    end

    if isMouseInsideContextMenu() then
        placedItemHoverEndedAt = nil
        return
    end

    local foundItem = getOwnedPlacedItemFromRay()
    if not foundItem then
        hoveredPlacedItem = nil
        placedItemHoverStartedAt = nil

        if itemContextMenu and itemContextMenu.Visible then
            placedItemHoverEndedAt = placedItemHoverEndedAt or tick()
            if tick() - placedItemHoverEndedAt >= 0.7 then
                placedItemHoverEndedAt = nil
                hideItemContextMenu()
            end
        else
            placedItemHoverEndedAt = nil
        end

        return
    end

    placedItemHoverEndedAt = nil

    if foundItem ~= hoveredPlacedItem then
        hoveredPlacedItem = foundItem
        placedItemHoverStartedAt = tick()

        if contextMenuTarget ~= foundItem then
            hideItemContextMenu()
        end
    end

    if not itemContextMenu or not itemContextMenu.Visible then
        if placedItemHoverStartedAt and tick() - placedItemHoverStartedAt >= 0.5 then
            showItemContextMenu(foundItem)
        end
    end
end

-- Handle mouse click
local function onInputBegan(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Escape and signEditorFrame and signEditorFrame.Visible then
        closeFactorySignEditor()
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 and itemContextMenu and itemContextMenu.Visible and isMouseInsideContextMenu() then
        rotateContextMenuTarget()
        return
    end

    if gameProcessed then return end

    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.R then
        if placementMode and ghostItem then
            placementRotation = (placementRotation + 1) % 4
            updateGhostPosition()
        end
        return
    end
    
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if itemContextMenu and itemContextMenu.Visible then
            if isMouseInsideContextMenu() then
                rotateContextMenuTarget()
                return
            end

            hideItemContextMenu()
        end

        -- Deletion mode
        if deletionMode then
            if hoveredDeleteItem then
                deleteItemRemote:FireServer(hoveredDeleteItem)
                removeSelectionBox()
                hoveredDeleteItem = nil
                -- Stay in deletion mode!
                task.wait(0.1)
                refreshInventoryUI()
            end
        -- Placement mode
        elseif placementMode and canPlace and ghostItem then
            local plotInfo = getPlotInfo()
            local gridUnit = getGridUnitSize()
            local camera = workspace.CurrentCamera
            local mousePos = UserInputService:GetMouseLocation()
            local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
            
            local rayParams = RaycastParams.new()
            rayParams.FilterType = Enum.RaycastFilterType.Exclude
            rayParams.FilterDescendantsInstances = {ghostItem}
            if player.Character then
                table.insert(rayParams.FilterDescendantsInstances, player.Character)
            end
            
            local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
            
            if result then
                local cellX, cellZ = worldToGrid(result.Position, plotInfo, gridUnit)
                local cellsX, cellsZ = getRotatedFootprint(selectedItem, placementRotation)
                local worldPos = getFootprintCenter(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit)
                local position = Vector3.new(worldPos.X, worldPos.Y, worldPos.Z)
                
                placeItemRemote:FireServer(selectedItem, position, currentScaleFactor, gridUnit, cellsX, cellsZ, placementRotation, cellX, cellZ)
                
                placementMode = false
                placementRotation = 0
                placementIndicator.Visible = false
                destroyGhostItem()
                selectedItem = nil
                removeGridVisualization()
                clearFlowPreview()
                
                task.wait(0.1)
                refreshInventoryUI()
            end
        end
    end
end

-- Function to check if plot size changed and update grid
local function updateGridIfNeeded()
    if placementMode then
        local plotInfo = getPlotInfo()
        if plotInfo and lastPlotSize then
            -- Check if plot size changed
            if plotInfo.size ~= lastPlotSize then
                createGridVisualization()
            end
        end
    end
end

-- Connect events
UserInputService.InputBegan:Connect(onInputBegan)
ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
    if (triggeringPlayer and triggeringPlayer ~= player) or prompt.Name ~= "EditFactorySignPrompt" then
        return
    end

    local sign = getFactorySignFromInstance(prompt)
    if sign and sign:GetAttribute("Owner") == player.UserId then
        showFactorySignEditor(sign)
    end
end)

RunService.RenderStepped:Connect(function()
    updateGridIfNeeded()
    updateGhostPosition()
    updateDeletionHover()
    updatePlacedItemHoverMenu()
    if itemContextMenu and itemContextMenu.Visible and contextMenuTarget then
        updateItemContextMenuContents(contextMenuTarget)
    end
end)

-- Listen for inventory updates (e.g., when shop closes after purchase)
inventoryUpdatedRemote.OnClientEvent:Connect(function()
    task.wait(0.2) -- Small delay to ensure server data is updated
    refreshInventoryUI()
end)

updateFactorySignTextRemote.OnClientEvent:Connect(function(success, message, filteredText)
    if not signEditorFrame or not signEditorFrame.Visible then
        return
    end

    signEditorStatus.Text = tostring(message or "")
    if success then
        if activeFactorySign and activeFactorySign.Parent and type(filteredText) == "string" then
            activeFactorySign:SetAttribute("SignText", filteredText)
            local label = findFactorySignTextLabel(activeFactorySign)
            if label then
                label.Text = filteredText
            end
        end

        task.delay(0.35, function()
            if signEditorFrame and signEditorFrame.Visible then
                closeFactorySignEditor()
            end
        end)
    end
end)

-- Initial inventory refresh
task.wait(1)
refreshInventoryUI()

print("Inventory UI and Placement System loaded!")
