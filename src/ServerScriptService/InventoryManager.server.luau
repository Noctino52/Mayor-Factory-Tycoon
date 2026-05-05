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

-- Configuration
local GRID_UNIT_SIZE = 8 -- Fixed grid size in studs
local MAX_PLOTS = 6 -- Maximum number of plots
local PLOT_LABEL_HEIGHT = 15 -- Height of the plot label above the plot

-- DataStore for persistence
local playerDataStore = DataStoreService:GetDataStore("TycoonFactoryData")

-- Fallback storage if DataStore fails
local fallbackDataStore = {}

-- Get grid unit size (now fixed)
local function getGridUnitSize()
    return GRID_UNIT_SIZE
end

-- Get templates folder
local templatesFolder = ReplicatedStorage:WaitForChild("ItemTemplates")

-- Clean up all sounds from templates at startup
task.spawn(function()
    wait(0.5) -- Give time for templates to load
    for _, template in ipairs(templatesFolder:GetChildren()) do
        for _, sound in ipairs(template:GetDescendants()) do
            if sound:IsA("Sound") then
                sound:Destroy()
            end
        end
    end
    print("[InventoryManager] Removed sounds from all templates")
end)

-- Create RemoteEvents
local placeItemRemote = Instance.new("RemoteEvent")
placeItemRemote.Name = "PlaceItem"
placeItemRemote.Parent = ReplicatedStorage

local getInventoryRemote = Instance.new("RemoteFunction")
getInventoryRemote.Name = "GetInventory"
getInventoryRemote.Parent = ReplicatedStorage

local deleteItemRemote = Instance.new("RemoteEvent")
deleteItemRemote.Name = "DeleteItem"
deleteItemRemote.Parent = ReplicatedStorage

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

-- Configuration Constants
local MAX_ITEMS_PER_PLOT = 20

-- Player data storage
local playerData = {}

-- Plot assignment tracking (plotId -> player)
local plotAssignments = {} -- {plotId = player.UserId}
local playerPlots = {} -- {player.UserId = plotId}

-- Default inventory for new players
local DEFAULT_INVENTORY = {
    {itemName = "RubiksCube", count = 1},
    {itemName = "TreeFarm", count = 5},
    {itemName = "MineEntrance", count = 1},
    {itemName = "Sawmill", count = 5}
}

-- Function to remove all sounds from a model
local function removeAllSounds(model)
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("Sound") then
            descendant.Parent = nil
        end
    end
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

-- Function to save player data to DataStore
local function savePlayerData(player)
    local data = playerData[player]
    if not data then return end
    
    local plotId = playerPlots[player.UserId]
    if not plotId then return end
    
    -- Prepare save data
    local saveData = {
        inventory = data.inventory,
        placedItems = {},
        plotId = plotId
    }
    
    -- Save placed items info
    for _, item in ipairs(data.placedItems) do
        if item and item.Parent then
            table.insert(saveData.placedItems, {
                itemName = item:GetAttribute("ItemName"),
                position = {item:GetPivot().Position.X, item:GetPivot().Position.Y, item:GetPivot().Position.Z},
                scaleFactor = item:GetAttribute("ScaleFactor") or 1,
                cellsX = item:GetAttribute("CellsX") or 1,
                cellsZ = item:GetAttribute("CellsZ") or 1
            })
        end
    end
    
    -- Save to DataStore
    local success, err = pcall(function()
        playerDataStore:SetAsync("Player_" .. player.UserId, saveData)
    end)
    
    if success then
        print("[SAVED] " .. player.Name .. " - " .. #saveData.placedItems .. " items on Plot " .. plotId)
    else
        warn("[ERROR] Failed to save data for " .. player.Name .. ": " .. tostring(err))
        -- Fallback to memory storage
        fallbackDataStore["Player_" .. player.UserId] = saveData
    end
end

-- Function to load player data from DataStore
local function loadPlayerData(player)
    -- Try DataStore first
    local success, data = pcall(function()
        return playerDataStore:GetAsync("Player_" .. player.UserId)
    end)
    
    if success and data then
        print("[LOADED] " .. player.Name .. " - " .. #data.placedItems .. " items from DataStore")
        return data
    end
    
    -- Fallback to memory storage
    local fallbackData = fallbackDataStore["Player_" .. player.UserId]
    if fallbackData then
        print("[LOADED] " .. player.Name .. " - " .. #fallbackData.placedItems .. " items from fallback")
        return fallbackData
    end
    
    return nil
end

-- Function to migrate old inventory to new one (adds missing items and removes invalid ones)
local function migrateInventory(oldInventory)
    if not oldInventory then return table.clone(DEFAULT_INVENTORY) end
    
    local migratedInv = {}
    local validItemNames = {}
    
    -- Build set of valid item names from DEFAULT_INVENTORY
    for _, defaultItem in ipairs(DEFAULT_INVENTORY) do
        validItemNames[defaultItem.itemName] = true
    end
    
    -- Keep only valid items from old inventory
    for _, existingItem in ipairs(oldInventory) do
        if validItemNames[existingItem.itemName] then
            table.insert(migratedInv, existingItem)
        else
            print("[MIGRATED] Rimosso item invalido: " .. existingItem.itemName)
        end
    end
    
    -- Add missing items from DEFAULT_INVENTORY
    for _, defaultItem in ipairs(DEFAULT_INVENTORY) do
        local found = false
        for _, existingItem in ipairs(migratedInv) do
            if existingItem.itemName == defaultItem.itemName then
                found = true
                break
            end
        end
        
        -- If item not found, add it with DEFAULT count
        if not found then
            table.insert(migratedInv, {itemName = defaultItem.itemName, count = defaultItem.count})
            print("[MIGRATED] Aggiunto nuovo item: " .. defaultItem.itemName .. " (count: " .. defaultItem.count .. ")")
        end
    end
    
    return migratedInv
end

-- Function to spawn saved items
local function spawnSavedItems(player, itemsData, plotId)
    local data = playerData[player]
    if not data then return end
    
    for _, itemInfo in ipairs(itemsData) do
        local template = templatesFolder:FindFirstChild(itemInfo.itemName)
        if template then
            local newItem = template:Clone()
            
            -- Remove all sounds from the model
            removeAllSounds(newItem)
            
            -- Apply scale
            local currentScale = newItem:GetScale()
            newItem:ScaleTo(currentScale * (itemInfo.scaleFactor or 1))
            
            -- Enable collisions and anchor
            for _, desc in ipairs(newItem:GetDescendants()) do
                if desc:IsA("BasePart") then
                    desc.CanCollide = true
                    desc.Anchored = true
                end
            end
            
            -- Position the item
            local position = Vector3.new(itemInfo.position[1], itemInfo.position[2], itemInfo.position[3])
            newItem:PivotTo(CFrame.new(position))
            
            -- Set attributes
            newItem:SetAttribute("Owner", player.UserId)
            newItem:SetAttribute("ItemName", itemInfo.itemName)
            newItem:SetAttribute("CellsX", itemInfo.cellsX or 1)
            newItem:SetAttribute("CellsZ", itemInfo.cellsZ or 1)
            newItem:SetAttribute("ScaleFactor", itemInfo.scaleFactor or 1)
            
            -- Parent to player's items folder
            local playerItemsFolder = workspace:FindFirstChild("PlayerItems_" .. player.UserId)
            if playerItemsFolder then
                newItem.Parent = playerItemsFolder
                table.insert(data.placedItems, newItem)
            end
        end
    end
end

-- Function to get item template
local function getItemTemplate(itemName)
    return templatesFolder:FindFirstChild(itemName)
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
            inventory = table.clone(DEFAULT_INVENTORY),
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
    
    -- Teleport player to their plot when character spawns
    if player.Character then
        teleportToPlot(player, plotId)
    else
        player.CharacterAdded:Connect(function()
            teleportToPlot(player, plotId)
        end)
    end
    
    print("Inventory initialized for " .. player.Name .. " on Plot " .. plotId)
end

-- Handle player leaving
local function onPlayerRemoving(player)
    -- Save player data before leaving
    savePlayerData(player)
    
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

-- Handle place item request (now with separate cellsX and cellsZ)
placeItemRemote.OnServerEvent:Connect(function(player, itemName, position, scaleFactor, gridUnit, cellsX, cellsZ)
    local data = playerData[player]
    if not data then return end
    
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
    
    -- Check if this is a placeable item with cost
    local itemDef = Definitions.GetItem(itemName)
    if itemDef and itemDef.cost then
        -- Check if player has enough money
        local progress = PlayerProgress.GetPlayerProgress(player)
        if progress.money < itemDef.cost then
            print(player.Name .. " tried to place " .. itemName .. " but has insufficient funds")
            return false, "Insufficient funds"
        end
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
    
    -- Get template and check size
    local template = templatesFolder:FindFirstChild(itemName)
    if not template then
        return false, "Item template not found"
    end
    
    -- Apply scaling if provided
    if not scaleFactor then scaleFactor = 1 end
    if not gridUnit then gridUnit = getGridUnitSize() end
    if not cellsX then cellsX = 1 end
    if not cellsZ then cellsZ = 1 end
    
    -- Check if position is within player's plot (considering scaled size)
    local itemSize
    local cframe, size = template:GetBoundingBox()
    itemSize = size * scaleFactor
    if not isWithinPlot(position, itemSize, plotId) then
        return false, "Position outside your plot bounds"
    end
    
    -- Place the item
    local newItem = template:Clone()
    
    -- Remove all sounds from the model
    removeAllSounds(newItem)
    
    -- Apply scale to fit in one cell
    local currentScale = newItem:GetScale()
    newItem:ScaleTo(currentScale * scaleFactor)
    
    -- Enable collisions on all parts
    for _, desc in ipairs(newItem:GetDescendants()) do
        if desc:IsA("BasePart") then
            desc.CanCollide = true
            desc.Anchored = true -- Anchor the item so it doesn't fall
        end
    end
    
    newItem:PivotTo(CFrame.new(position))
    newItem.Parent = workspace:FindFirstChild("PlayerItems_" .. player.UserId)
    
    newItem:SetAttribute("Owner", player.UserId)
    newItem:SetAttribute("ItemName", itemName)
    newItem:SetAttribute("CellsX", cellsX) -- Store how many cells in X direction
    newItem:SetAttribute("CellsZ", cellsZ) -- Store how many cells in Z direction
    newItem:SetAttribute("ScaleFactor", scaleFactor) -- Store the scale factor
    
    -- Decrease inventory count
    inventoryItem.count = inventoryItem.count - 1
    if inventoryItem.count <= 0 then
        table.remove(data.inventory, inventoryIndex)
    end
    
    table.insert(data.placedItems, newItem)
    
    -- Deduct money if this item has a cost
    if itemDef and itemDef.cost then
        local newBalance = PlayerProgress.AddMoney(player, -itemDef.cost)
        print(player.Name .. " placed " .. itemName .. " for " .. itemDef.cost .. "💵 - New balance: " .. newBalance)
    end
    
    -- Save after placing
    savePlayerData(player)
    
    print(player.Name .. " placed " .. itemName .. " at " .. tostring(position) .. " on Plot " .. plotId)
    return true
end)

-- Handle delete item request
deleteItemRemote.OnServerEvent:Connect(function(player, item)
    local data = playerData[player]
    if not data then return end
    
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
    
    -- Refund 50% of the cost if item has a cost
    local itemDef = Definitions.GetItem(itemName)
    if itemDef and itemDef.cost then
        local refundAmount = math.floor(itemDef.cost * 0.5)
        local newBalance = PlayerProgress.AddMoney(player, refundAmount)
        print(player.Name .. " deleted " .. itemName .. " and received " .. refundAmount .. "💵 refund - New balance: " .. newBalance)
    else
        print(player.Name .. " deleted " .. itemName)
    end
    
    -- Save after deleting
    savePlayerData(player)
end)

-- Handle get inventory request
getInventoryRemote.OnServerInvoke = function(player)
    local data = playerData[player]
    if not data then return {} end
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
                scaleFactor = item:GetAttribute("ScaleFactor") or 1
            })
        end
    end
    
    return placedItemsList
end

-- Handle get town prestige request
getTownPrestigeRemote.OnServerInvoke = function(player)
    local progress = PlayerProgress.GetPlayerProgress(player)
    return {
        stage = progress.townPrestige.stage,
        contributions = progress.townPrestige.contributions or 0,
        currentItemsPlaced = #(playerData[player] and playerData[player].placedItems or {}),
        maxItemsAllowed = MAX_ITEMS_PER_PLOT
    }
end

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