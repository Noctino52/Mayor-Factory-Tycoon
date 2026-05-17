--[[
	TutorialSystem.luau

	Server-authoritative first-loop tutorial.
	Clients can only request/read the current objective; all advancement is driven
	by inventory, placement, and sale state that the server already validated.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProgress = require(game.ServerScriptService.PlayerProgress)

local TutorialSystem = {}

local STEP_DEFINITIONS = {
	{
		objective = "Buy a TreeFarm from the Shop",
	},
	{
		objective = "Place the TreeFarm on your plot",
	},
	{
		objective = "Buy and place a Conveyor",
	},
	{
		objective = "Buy and place a Sawmill",
	},
	{
		objective = "Place Mira's Sell Zone",
	},
	{
		objective = "Sell a Plank to Mira",
	},
}

local STEP_COUNT = #STEP_DEFINITIONS
local initialized = false

local function getOrCreateRemote(className, name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end

	if existing then
		warn("[TutorialSystem] Replacing " .. name .. " because it is a " .. existing.ClassName .. ", not " .. className)
		existing:Destroy()
	end

	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = ReplicatedStorage

	return remote
end

local getTutorialStateRemote = getOrCreateRemote("RemoteFunction", "GetTutorialState")
local tutorialUpdatedRemote = getOrCreateRemote("RemoteEvent", "TutorialUpdated")

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, childValue in pairs(value) do
		copy[key] = deepCopy(childValue)
	end

	return copy
end

local function getStepKey(stepNumber)
	return tostring(math.floor(tonumber(stepNumber) or 0))
end

local function getInventoryCount(inventory, itemName)
	local count = 0

	for _, inventoryItem in ipairs(inventory or {}) do
		if inventoryItem.itemName == itemName then
			count += tonumber(inventoryItem.count) or 0
		end
	end

	return count
end

local function getPlacedCount(placedItems, itemName)
	local count = 0

	for _, placedItem in ipairs(placedItems or {}) do
		local placedItemName = nil

		if typeof(placedItem) == "Instance" then
			if placedItem.Parent then
				placedItemName = placedItem:GetAttribute("ItemName")
			end
		elseif type(placedItem) == "table" then
			placedItemName = placedItem.itemName or placedItem.name
		end

		if placedItemName == itemName then
			count += 1
		end
	end

	return count
end

local function hasInventoryItem(inventory, itemName)
	return getInventoryCount(inventory, itemName) > 0
end

local function hasPlacedItem(placedItems, itemName)
	return getPlacedCount(placedItems, itemName) > 0
end

local function hasSoldPlankToMira(player)
	local progress = PlayerProgress.GetPlayerProgress(player)
	local statistics = progress.statistics or {}
	local npcSold = statistics.npcSold or {}
	local miraSold = npcSold.Mira or {}

	return (tonumber(miraSold.Plank) or 0) >= 1
end

local function isStepSatisfied(player, stepNumber, inventory, placedItems)
	if stepNumber == 1 then
		return hasInventoryItem(inventory, "TreeFarm") or hasPlacedItem(placedItems, "TreeFarm")
	elseif stepNumber == 2 then
		return hasPlacedItem(placedItems, "TreeFarm")
	elseif stepNumber == 3 then
		return hasPlacedItem(placedItems, "Conveyor")
	elseif stepNumber == 4 then
		return hasPlacedItem(placedItems, "Sawmill")
	elseif stepNumber == 5 then
		return hasPlacedItem(placedItems, "MiraSellZone")
	elseif stepNumber == 6 then
		return hasSoldPlankToMira(player)
	end

	return false
end

local function createSnapshot(player)
	local tutorial = PlayerProgress.GetTutorialProgress(player)
	local stepDefinition = STEP_DEFINITIONS[tutorial.currentStep]

	return {
		currentStep = tutorial.currentStep,
		completed = tutorial.completed == true,
		completedSteps = deepCopy(tutorial.completedSteps or {}),
		stepCount = STEP_COUNT,
		objective = stepDefinition and stepDefinition.objective or nil,
	}
end

local function fireTutorialUpdate(player)
	if player and player.Parent then
		tutorialUpdatedRemote:FireClient(player, createSnapshot(player))
	end
end

local function advanceSatisfiedSteps(player, inventory, placedItems)
	local tutorial = PlayerProgress.GetTutorialProgress(player)
	if tutorial.completed then
		return false
	end

	local advanced = false

	while not tutorial.completed do
		local currentStep = tonumber(tutorial.currentStep) or 1
		if currentStep < 1 or currentStep > STEP_COUNT then
			tutorial.completed = true
			tutorial.currentStep = STEP_COUNT + 1
			advanced = true
			break
		end

		if not isStepSatisfied(player, currentStep, inventory, placedItems) then
			break
		end

		tutorial.completedSteps[getStepKey(currentStep)] = true
		advanced = true

		if currentStep >= STEP_COUNT then
			tutorial.completed = true
			tutorial.currentStep = STEP_COUNT + 1
		else
			tutorial.currentStep = currentStep + 1
		end
	end

	if advanced then
		PlayerProgress.SaveTutorialProgress(player, tutorial)
		fireTutorialUpdate(player)
	end

	return advanced
end

function TutorialSystem.GetTutorialState(player)
	if not player then
		error("[TutorialSystem] Player is required")
	end

	return createSnapshot(player)
end

function TutorialSystem.SyncPlayerState(player, inventory, placedItems)
	if not player or not player.Parent then
		return false
	end

	return advanceSatisfiedSteps(player, inventory, placedItems)
end

function TutorialSystem.ObserveSale(player, itemName, npcName, quantity)
	if itemName ~= "Plank" or npcName ~= "Mira" or (tonumber(quantity) or 0) <= 0 then
		return false
	end

	return TutorialSystem.SyncPlayerState(player)
end

function TutorialSystem.Initialize()
	if initialized then
		return
	end

	initialized = true

	getTutorialStateRemote.OnServerInvoke = function(player)
		return TutorialSystem.GetTutorialState(player)
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			fireTutorialUpdate(player)
		end)
	end)
end

return TutorialSystem
