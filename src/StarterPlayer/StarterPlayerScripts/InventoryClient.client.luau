-- Inventory UI and Placement System
-- Handles inventory display, grid-based placement, and deletion
-- Grid unit is dynamically based on RubiksCube size

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Definitions = require(sharedFolder:WaitForChild("Definitions"))
local templatesFolder = sharedFolder:WaitForChild("ItemTemplates")

-- Wait for remotes
local placeItemRemote = ReplicatedStorage:WaitForChild("PlaceItem")
local getInventoryRemote = ReplicatedStorage:WaitForChild("GetInventory")
local deleteItemRemote = ReplicatedStorage:WaitForChild("DeleteItem")
local rotateItemRemote = ReplicatedStorage:WaitForChild("RotateItem")
local getPlotRemote = ReplicatedStorage:WaitForChild("GetPlayerPlot")
local inventoryUpdatedRemote = ReplicatedStorage:WaitForChild("InventoryUpdated")

-- Configuration
local GHOST_TRANSPARENCY = 0.6
local GRID_UNIT_SIZE = 8 -- Fixed grid size in studs

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
local placementIndicator = nil
local indicatorText = nil
local currentGridUnit = 0 -- Cache for current grid unit size
local currentScaleFactor = 1 -- Cache for current scale factor
local lastPlotSize = nil -- Track plot size changes
local playerPlotInfo = nil -- Cached plot info for this player

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

    if itemName and (itemName:find("CurvedConveyor") or itemName:find("ConveyorCurve") or itemName:find("ConveyorCorner")) then
        return 2, 1
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
}

local function getItemFootprintPadding(itemName)
    local adjustment = ITEM_VISUAL_ADJUSTMENTS[itemName]
    return (adjustment and adjustment.footprintPadding) or 1
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

local function getOwnedPlacedItemFromRay()
    local camera = workspace.CurrentCamera
    local mousePos = UserInputService:GetMouseLocation()
    local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {}
    if ghostItem then
        table.insert(rayParams.FilterDescendantsInstances, ghostItem)
    end
    if player.Character then
        table.insert(rayParams.FilterDescendantsInstances, player.Character)
    end

    local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
    if not result or not result.Instance then
        return nil
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

    return nil
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
    selectionBox.FillTransparency = 0.8
    selectionBox.OutlineTransparency = 0
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

-- Create Inventory UI
local existingInventoryGui = playerGui:FindFirstChild("InventoryUI")
if existingInventoryGui then
    existingInventoryGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "InventoryUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

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
            nextPosition = Vector3.new(footprintCenter.X, pivot.Position.Y, footprintCenter.Z)
        end

        rotateItemRemote:FireServer(contextMenuTarget)
        contextMenuTarget:SetAttribute("Rotation", nextRotation)
        contextMenuTarget:SetAttribute("CellsX", cellsX)
        contextMenuTarget:SetAttribute("CellsZ", cellsZ)
        contextMenuTarget:PivotTo(CFrame.new(nextPosition) * getRotationCFrame(nextRotation))
    end

    hideItemContextMenu()
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
    itemContextMenu.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    itemContextMenu.BackgroundTransparency = 0.05
    itemContextMenu.BorderSizePixel = 0
    itemContextMenu.Active = true
    itemContextMenu.ZIndex = 10
    itemContextMenu.Visible = false
    itemContextMenu.Parent = itemContextBillboard

    local menuCorner = Instance.new("UICorner")
    menuCorner.CornerRadius = UDim.new(0, 8)
    menuCorner.Parent = itemContextMenu

    local rotateButton = Instance.new("TextButton")
    rotateButton.Name = "RotateButton"
    rotateButton.Size = UDim2.new(1, -8, 1, -8)
    rotateButton.Position = UDim2.new(0, 4, 0, 4)
    rotateButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
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
        BackgroundTransparency = 0.05,
    })
    contextMenuTween:Play()

    if rotateButton then
        TweenService:Create(rotateButton, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0,
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
    local _, itemSize = item:GetBoundingBox()
    if itemSize.X <= 0 or itemSize.Z <= 0 then
        return 1
    end

    local footprintPadding = getItemFootprintPadding(itemName)
    
    local scaleX = (gridUnit * cellsX * footprintPadding) / itemSize.X
    local scaleZ = (gridUnit * cellsZ * footprintPadding) / itemSize.Z
    local scaleFactor = math.min(scaleX, scaleZ)
    
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
            end
            
            -- Exit previous placement mode
            if placementMode then
                destroyGhostItem()
                placementMode = false
                placementRotation = 0
                placementIndicator.Visible = false
                selectedItem = nil
                removeGridVisualization()
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
    end
    
    -- Toggle deletion mode
    deletionMode = not deletionMode
    
    if deletionMode then
        deleteButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        placementIndicator.Visible = true
        placementIndicator.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        indicatorText.Text = "DELETE MODE: Click item to remove | Click button to exit"
    else
        deleteButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        placementIndicator.Visible = false
        removeSelectionBox()
        hoveredDeleteItem = nil
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
                return
            end
            
            if isAreaOccupied(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit) then
                ghostItem.Parent = nil
                placementIndicator.Visible = true
                placementIndicator.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
                indicatorText.Text = "Space occupied! | Click button to cancel"
                canPlace = false
                updateHighlightBox(cellX, cellZ, cellsX, cellsZ, false)
                return
            end
            
            ghostItem.Parent = workspace.CurrentCamera
            placementIndicator.Visible = true
            placementIndicator.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
            indicatorText.Text = "Click to place | R to rotate | Click button to cancel"
            
            updateHighlightBox(cellX, cellZ, cellsX, cellsZ, true)
            
            local worldPos = getFootprintCenter(cellX, cellZ, cellsX, cellsZ, plotInfo, gridUnit)
            local itemHeight = getItemHeight(ghostItem)
            local finalY = worldPos.Y + itemHeight / 2
            
            canPlace = true
            ghostItem:PivotTo(CFrame.new(
                worldPos.X,
                finalY,
                worldPos.Z
            ) * getRotationCFrame(placementRotation))
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
                local itemHeight = getItemHeight(ghostItem)
                local finalY = worldPos.Y + itemHeight / 2
                
                local position = Vector3.new(
                    worldPos.X,
                    finalY,
                    worldPos.Z
                )
                
                placeItemRemote:FireServer(selectedItem, position, currentScaleFactor, gridUnit, cellsX, cellsZ, placementRotation, cellX, cellZ)
                
                placementMode = false
                placementRotation = 0
                placementIndicator.Visible = false
                destroyGhostItem()
                selectedItem = nil
                removeGridVisualization()
                
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
RunService.RenderStepped:Connect(function()
    updateGridIfNeeded()
    updateGhostPosition()
    updateDeletionHover()
    updatePlacedItemHoverMenu()
end)

-- Listen for inventory updates (e.g., when shop closes after purchase)
inventoryUpdatedRemote.OnClientEvent:Connect(function()
    task.wait(0.2) -- Small delay to ensure server data is updated
    refreshInventoryUI()
end)

-- Initial inventory refresh
task.wait(1)
refreshInventoryUI()

print("Inventory UI and Placement System loaded!")
