local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ConveyorSystem = require(game.ServerScriptService.ConveyorSystem)
local Definitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Definitions"))
local PlayerProgress = require(game.ServerScriptService.PlayerProgress)

local SellSystem = {}

local sellZones = {}

local saleFeedbackRemote = ReplicatedStorage:FindFirstChild("ProductionItemSold")
if not saleFeedbackRemote then
    saleFeedbackRemote = Instance.new("RemoteEvent")
    saleFeedbackRemote.Name = "ProductionItemSold"
    saleFeedbackRemote.Parent = ReplicatedStorage
end

local function cellKey(cellX, cellZ)
    return tostring(cellX) .. "_" .. tostring(cellZ)
end

local function acceptsItem(npcData, itemName)
    for _, acceptedItem in ipairs(npcData.buysItems or {}) do
        if acceptedItem == itemName then
            return true
        end
    end

    return false
end

function SellSystem.CreateSellZone(player, cellX, cellZ, npcName, instance)
    if not player or not player.Parent then
        return false, "Invalid player"
    end

    local npcData = Definitions.GetNPC(npcName)
    if not npcData then
        return false, "Invalid NPC"
    end

    cellX = math.floor(tonumber(cellX) or 0)
    cellZ = math.floor(tonumber(cellZ) or 0)

    if not sellZones[player] then
        sellZones[player] = {}
    end

    sellZones[player][cellKey(cellX, cellZ)] = {
        npcName = npcName,
        instance = instance,
    }

    if instance and instance.Parent then
        instance:SetAttribute("NPCName", npcName)
    end

    return true
end

function SellSystem.RegisterPlacedItem(player, item)
    if not item or not item.Parent then
        return false
    end

    local itemName = item:GetAttribute("ItemName")
    local itemDef = Definitions.GetItem(itemName)
    if not itemDef or itemDef.type ~= "sell_zone" then
        return false
    end

    local cellX = item:GetAttribute("CellX")
    local cellZ = item:GetAttribute("CellZ")
    local npcName = item:GetAttribute("NPCName") or itemDef.npcName
    if cellX == nil or cellZ == nil or not npcName then
        return false
    end

    return SellSystem.CreateSellZone(player, cellX, cellZ, npcName, item)
end

function SellSystem.UnregisterPlacedItem(player, item)
    if not item then
        return
    end

    local cellX = item:GetAttribute("CellX")
    local cellZ = item:GetAttribute("CellZ")
    if cellX == nil or cellZ == nil then
        return
    end

    local zones = sellZones[player]
    if zones then
        zones[cellKey(cellX, cellZ)] = nil
        if next(zones) == nil then
            sellZones[player] = nil
        end
    end
end

function SellSystem.ClearPlayer(player)
    sellZones[player] = nil
end

function SellSystem.SellItem(player, itemName, cellX, cellZ)
    local zones = sellZones[player]
    local zone = zones and zones[cellKey(cellX, cellZ)]
    if not zone then
        return false, "No sell zone at cell"
    end

    local itemData = Definitions.GetItem(itemName)
    local npcData = Definitions.GetNPC(zone.npcName)
    if not itemData or not npcData then
        return false, "Invalid sale data"
    end

    if not acceptsItem(npcData, itemName) then
        return false, "NPC does not buy this item"
    end

    local basePrice = itemData.value or 0
    local sellingPrice = math.floor(basePrice * (npcData.basePriceMultiplier or 1))
    local reputationReward = npcData.baseReputationReward or 0

    PlayerProgress.AddMoney(player, sellingPrice)
    PlayerProgress.RecordSale(player, itemName, zone.npcName, 1)

    local progress = PlayerProgress.GetPlayerProgress(player)
    progress.townPrestige.contributions = (progress.townPrestige.contributions or 0) + sellingPrice
    PlayerProgress.SavePlayerProgress(player, progress)

    local reputationResult = PlayerProgress.AddReputation(player, zone.npcName, reputationReward)

    saleFeedbackRemote:FireClient(player, {
        itemName = itemName,
        npcName = zone.npcName,
        money = sellingPrice,
        reputation = reputationReward,
        contributions = sellingPrice,
        newReputation = reputationResult and reputationResult.newReputation,
        leveledUp = reputationResult and reputationResult.leveledUp,
        newStage = reputationResult and reputationResult.newStage,
    })

    return true
end

function SellSystem.Initialize()
    ConveyorSystem.SetSellHandler(SellSystem.SellItem)

    Players.PlayerRemoving:Connect(function(player)
        SellSystem.ClearPlayer(player)
    end)
end

return SellSystem
