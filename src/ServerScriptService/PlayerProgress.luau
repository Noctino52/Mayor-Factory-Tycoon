--[[
	PlayerProgress.luau
	
	Server-side module for managing player progression data:
	- Money and currency
	- NPC reputation
	- Town prestige level
	- Sales statistics
	
	All data is persisted to DataStore with in-memory fallback.
	Auto-saves on important changes to prevent data loss.
]]

local PlayerProgress = {}

local DataStoreService = game:GetService("DataStoreService")
local Definitions = require(game.ReplicatedStorage.Shared.Definitions)

-- ============================================================================
-- Configuration
-- ============================================================================

local DATASTORE_NAME = "MayorsFactoryTycoon_PlayerData"
local DATASTORE_VERSION = 2
local AUTO_SAVE_INTERVAL = 30 -- seconds
local SAVE_DEBOUNCE_INTERVAL = 8 -- seconds
local MAX_RETRIES = 3

-- ============================================================================
-- Cache and DataStore access
-- ============================================================================

local playerDataCache = {} -- playerId -> progressData
local dirtyPlayerData = {} -- playerId -> true when cached data needs persistence
local saveScheduled = {} -- playerId -> true when a deferred save is already queued
local saveInProgress = {} -- playerId -> true while a DataStore save is running
local playerDataStore = nil
local dataStoreReady = false

-- Initialize DataStore safely
local function InitializeDataStore()
	local success, err = pcall(function()
		playerDataStore = DataStoreService:GetDataStore(DATASTORE_NAME)
		dataStoreReady = true
	end)

	if not success then
		warn("[PlayerProgress] Failed to initialize DataStore:", err)
		warn("[PlayerProgress] Using in-memory storage fallback")
		dataStoreReady = false
	end
end

-- ============================================================================
-- Default data structure
-- ============================================================================

local function GetDefaultProgress()
	return {
		version = DATASTORE_VERSION,
		money = 10000, -- 10000 for testing
		npcReputation = {
			Mira = 0,
			Bront = 0,
			Elrik = 0,
		},
		townPrestige = {
			stage = 1,
			contributions = 0,
		},
		statistics = {
			lifetimeSold = {}, -- itemName -> count
			npcSold = {}, -- npcName -> { itemName -> count }
			mayorContribution = {}, -- itemName -> count
		},
		lastSaved = tick(),
	}
end

local function MigrateProgressData(storedData)
	local migrated = GetDefaultProgress()
	if type(storedData) ~= "table" then
		return migrated
	end

	migrated.version = DATASTORE_VERSION
	migrated.money = tonumber(storedData.money) or migrated.money

	if type(storedData.npcReputation) == "table" then
		for npcName, reputation in pairs(storedData.npcReputation) do
			migrated.npcReputation[npcName] = tonumber(reputation) or 0
		end
	end

	if type(storedData.townPrestige) == "table" then
		migrated.townPrestige.stage = tonumber(storedData.townPrestige.stage) or migrated.townPrestige.stage
		migrated.townPrestige.contributions = tonumber(storedData.townPrestige.contributions) or migrated.townPrestige.contributions
		migrated.townPrestige.lastReward = storedData.townPrestige.lastReward
	end

	if type(storedData.statistics) == "table" then
		for statName, statValue in pairs(storedData.statistics) do
			if type(statValue) == "table" then
				migrated.statistics[statName] = statValue
			end
		end
	end

	migrated.lastSaved = tonumber(storedData.lastSaved) or migrated.lastSaved

	return migrated
end

local function DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, childValue in pairs(value) do
		copy[key] = DeepCopy(childValue)
	end

	return copy
end

local function GetNextTownPrestigeStageInfo(currentStage)
	currentStage = tonumber(currentStage) or 1

	for _, stageInfo in pairs(Definitions.TOWN_PRESTIGE_STAGES) do
		if (tonumber(stageInfo.stage) or 0) == currentStage + 1 then
			return stageInfo
		end
	end

	return nil
end

-- ============================================================================
-- DataStore Operations
-- ============================================================================

--[[
	LoadPlayerDataFromStore(userId: number) -> table or nil
	Attempts to load player data from DataStore with retries.
	Returns nil if DataStore is unavailable.
]]
local function LoadPlayerDataFromStore(userId)
	if not dataStoreReady or not playerDataStore then
		return nil
	end

	local key = "PlayerData_" .. userId
	local data = nil
	local err = nil

	for attempt = 1, MAX_RETRIES do
		local success
		success, data, err = pcall(function()
			return playerDataStore:GetAsync(key)
		end)

		if success then
			return data -- May be nil if player is new
		end

		if attempt < MAX_RETRIES then
			wait(1) -- Wait before retry
		end
	end

	warn("[PlayerProgress] Failed to load data for player", userId, "after", MAX_RETRIES, "retries:", err)
	return nil
end

--[[
	SavePlayerDataToStore(userId: number, progressData: table) -> (boolean, string or nil)
	Attempts to save player data to DataStore with retries.
	Returns (success, errorMessage).
]]
local function SavePlayerDataToStore(userId, progressData)
	if not dataStoreReady or not playerDataStore then
		return true, nil -- Silent fail, data is in cache
	end

	local key = "PlayerData_" .. userId
	progressData.lastSaved = tick()

	for attempt = 1, MAX_RETRIES do
		local success, err = pcall(function()
			playerDataStore:SetAsync(key, progressData)
		end)

		if success then
			return true, nil
		end

		if attempt < MAX_RETRIES then
			wait(1)
		end
	end

	warn("[PlayerProgress] Failed to save data for player", userId)
	return false, "DataStore save failed"
end

local SchedulePlayerSave

local function SaveCachedPlayerData(userId)
	while saveInProgress[userId] do
		task.wait(0.1)
	end

	local progressData = playerDataCache[userId]
	if not progressData then
		return true, nil
	end

	dirtyPlayerData[userId] = nil
	saveInProgress[userId] = true

	local success, err = SavePlayerDataToStore(userId, progressData)

	saveInProgress[userId] = nil
	if not success and playerDataCache[userId] then
		SchedulePlayerSave(userId, SAVE_DEBOUNCE_INTERVAL)
	end

	return success, err
end

function SchedulePlayerSave(userId, delaySeconds)
	dirtyPlayerData[userId] = true
	if saveScheduled[userId] then
		return true, nil
	end

	saveScheduled[userId] = true
	task.delay(delaySeconds or SAVE_DEBOUNCE_INTERVAL, function()
		saveScheduled[userId] = nil

		if playerDataCache[userId] then
			SaveCachedPlayerData(userId)
		end
	end)

	return true, nil
end

-- ============================================================================
-- Public API
-- ============================================================================

--[[
	GetPlayerProgress(player: Player) -> table
	
	Loads or retrieves player progress data.
	- Checks cache first
	- Loads from DataStore if not cached
	- Creates default data for new players
	- Uses fallback if DataStore is down
]]
function PlayerProgress.GetPlayerProgress(player)
	if not player then
		error("[PlayerProgress] Player is required")
	end

	local userId = player.UserId

	-- Return cached data if available
	if playerDataCache[userId] then
		return playerDataCache[userId]
	end

	-- Try loading from DataStore
	local storedData = LoadPlayerDataFromStore(userId)

	if storedData then
		local migratedData = MigrateProgressData(storedData)
		playerDataCache[userId] = migratedData
		if storedData.version ~= DATASTORE_VERSION then
			PlayerProgress.SavePlayerProgress(player, migratedData)
		end
		return migratedData
	end

	-- Create default data for new player
	local newData = GetDefaultProgress()
	playerDataCache[userId] = newData

	-- Try to save immediately (non-blocking)
	task.spawn(function()
		SavePlayerDataToStore(userId, newData)
	end)

	return newData
end

--[[
	SavePlayerProgress(player: Player, progressData: table) -> (boolean, string or nil)
	
	Saves player progress to DataStore immediately.
	- Updates cache
	- Saves to DataStore with retries
	- Returns (success, errorMessage)
]]
function PlayerProgress.SavePlayerProgress(player, progressData)
	if not player then
		error("[PlayerProgress] Player is required")
	end

	local userId = player.UserId

	-- Update cache
	playerDataCache[userId] = progressData

	return SchedulePlayerSave(userId)
end

function PlayerProgress.FlushPlayerProgress(player)
	if not player then
		error("[PlayerProgress] Player is required")
	end

	local userId = player.UserId
	saveScheduled[userId] = nil
	return SaveCachedPlayerData(userId)
end

--[[
	AddMoney(player: Player, amount: number) -> number
	
	Adds or subtracts money from player.
	- If amount < 0, checks that player has enough
	- Saves immediately
	- Returns new balance, or nil if insufficient funds
]]
function PlayerProgress.AddMoney(player, amount)
	if not player then
		error("[PlayerProgress] Player is required")
	end

	if type(amount) ~= "number" then
		error("[PlayerProgress] Amount must be a number")
	end

	local progress = PlayerProgress.GetPlayerProgress(player)

	-- Check if subtracting and player has enough
	if amount < 0 and progress.money + amount < 0 then
		return nil
	end

	progress.money = progress.money + amount
	PlayerProgress.SavePlayerProgress(player, progress)

	return progress.money
end

--[[
	AddReputation(player: Player, npcName: string, amount: number) -> table
	
	Adds reputation with an NPC.
	- Automatically checks for town prestige upgrades
	- Returns { newReputation, leveledUp, newStage }
]]
function PlayerProgress.AddReputation(player, npcName, amount)
	if not player then
		error("[PlayerProgress] Player is required")
	end

	if not Definitions.GetNPC(npcName) then
		error("[PlayerProgress] Invalid NPC name: " .. npcName)
	end

	if type(amount) ~= "number" then
		error("[PlayerProgress] Amount must be a number")
	end

	local progress = PlayerProgress.GetPlayerProgress(player)

	-- Add reputation
	if not progress.npcReputation[npcName] then
		progress.npcReputation[npcName] = 0
	end

	progress.npcReputation[npcName] = progress.npcReputation[npcName] + amount

	-- Check for prestige upgrade
	local leveledUp, newStage = PlayerProgress.CheckTownPrestigeUpgrade(player)

	PlayerProgress.SavePlayerProgress(player, progress)

	return {
		newReputation = progress.npcReputation[npcName],
		leveledUp = leveledUp,
		newStage = newStage,
	}
end

--[[
	RecordSale(player: Player, itemName: string, npcName: string, quantity: number) -> table
	
	Records a sale in statistics.
	- Updates lifetimeSold, npcSold, mayorContribution
	- Returns updated statistics
]]
function PlayerProgress.RecordSale(player, itemName, npcName, quantity)
	if not player then
		error("[PlayerProgress] Player is required")
	end

	if not itemName or not npcName then
		error("[PlayerProgress] itemName and npcName are required")
	end

	if type(quantity) ~= "number" or quantity <= 0 then
		error("[PlayerProgress] Quantity must be a positive number")
	end

	local progress = PlayerProgress.GetPlayerProgress(player)
	local stats = progress.statistics

	-- Update lifetimeSold
	if not stats.lifetimeSold[itemName] then
		stats.lifetimeSold[itemName] = 0
	end
	stats.lifetimeSold[itemName] = stats.lifetimeSold[itemName] + quantity

	-- Update npcSold
	if npcName ~= "Mayor" then
		if not stats.npcSold[npcName] then
			stats.npcSold[npcName] = {}
		end
		if not stats.npcSold[npcName][itemName] then
			stats.npcSold[npcName][itemName] = 0
		end
		stats.npcSold[npcName][itemName] = stats.npcSold[npcName][itemName] + quantity
	end

	-- Update mayorContribution (sales to Mayor count as contribution)
	if npcName == "Mayor" then
		if not stats.mayorContribution[itemName] then
			stats.mayorContribution[itemName] = 0
		end
		stats.mayorContribution[itemName] = stats.mayorContribution[itemName] + quantity
		progress.townPrestige.contributions = (progress.townPrestige.contributions or 0) + quantity
	end

	PlayerProgress.SavePlayerProgress(player, progress)

	return stats
end

function PlayerProgress.GetTownPrestigeStageInfo(stage)
	stage = tonumber(stage) or 1

	local bestStageInfo = nil
	for _, stageInfo in pairs(Definitions.TOWN_PRESTIGE_STAGES) do
		local stageNumber = tonumber(stageInfo.stage) or 0

		if stageNumber == stage then
			return stageInfo
		end

		local bestStageNumber = bestStageInfo and tonumber(bestStageInfo.stage) or 0
		if stageNumber <= stage and (not bestStageInfo or stageNumber > bestStageNumber) then
			bestStageInfo = stageInfo
		end
	end

	return bestStageInfo
end

function PlayerProgress.GetCurrentTownPrestigeStageInfo(player)
	local progress = PlayerProgress.GetPlayerProgress(player)
	local townPrestige = progress.townPrestige or {}

	return PlayerProgress.GetTownPrestigeStageInfo(townPrestige.stage)
end

function PlayerProgress.GetTownPrestigeRewards(player)
	local stageInfo = PlayerProgress.GetCurrentTownPrestigeStageInfo(player)

	return stageInfo and stageInfo.rewards or {}
end

function PlayerProgress.GetUnlockedShopItems(player)
	local progress = PlayerProgress.GetPlayerProgress(player)
	local currentStage = tonumber(progress.townPrestige and progress.townPrestige.stage) or 1
	local unlockedItems = {}

	for itemName, itemDef in pairs(Definitions.GetAllItems()) do
		if itemDef.cost and itemDef.isProduction ~= true and itemDef.type ~= "sell_zone" then
			unlockedItems[itemName] = true
		end
	end

	for _, stageInfo in pairs(Definitions.TOWN_PRESTIGE_STAGES) do
		local rewards = stageInfo.rewards or {}
		for _, itemName in ipairs(rewards.newShopItems or {}) do
			if (tonumber(stageInfo.stage) or 0) <= currentStage then
				unlockedItems[itemName] = true
			else
				unlockedItems[itemName] = nil
			end
		end
	end

	return unlockedItems
end

function PlayerProgress.IsShopItemUnlocked(player, itemName)
	local unlockedItems = PlayerProgress.GetUnlockedShopItems(player)

	return unlockedItems[itemName] == true
end

--[[
	GetPublicProgressSnapshot(player: Player) -> table

	Returns only progression data that is safe for clients to display.
	No economy decisions should be made from this snapshot.
]]
function PlayerProgress.GetPublicProgressSnapshot(player)
	if not player then
		error("[PlayerProgress] Player is required")
	end

	local progress = PlayerProgress.GetPlayerProgress(player)
	local statistics = progress.statistics or {}
	local townPrestige = progress.townPrestige or {}
	local currentStageInfo = PlayerProgress.GetTownPrestigeStageInfo(townPrestige.stage)
	local nextStageInfo = GetNextTownPrestigeStageInfo(townPrestige.stage)

	return {
		lifetimeSold = DeepCopy(statistics.lifetimeSold or {}),
		npcSold = DeepCopy(statistics.npcSold or {}),
		mayorContribution = DeepCopy(statistics.mayorContribution or {}),
		npcReputation = DeepCopy(progress.npcReputation or {}),
		townPrestige = {
			stage = tonumber(townPrestige.stage) or 1,
			stageName = currentStageInfo and currentStageInfo.name or nil,
			contributions = tonumber(townPrestige.contributions) or 0,
			nextStage = nextStageInfo and {
				stage = nextStageInfo.stage,
				name = nextStageInfo.name,
				requirements = DeepCopy(nextStageInfo.requirements or {}),
				rewards = DeepCopy(nextStageInfo.rewards or {}),
			} or nil,
		},
	}
end

--[[
	CheckTownPrestigeUpgrade(player: Player) -> (boolean, number or nil)
	
	Checks if player meets requirements for next prestige stage.
	- If yes, upgrades and returns (true, newStage)
	- If no, returns (false, nil)
]]
function PlayerProgress.CheckTownPrestigeUpgrade(player)
	if not player then
		error("[PlayerProgress] Player is required")
	end

	local progress = PlayerProgress.GetPlayerProgress(player)
	local currentStage = progress.townPrestige.stage
	local allStages = Definitions.TOWN_PRESTIGE_STAGES

	-- Find next stage
	local nextStageInfo = nil
	for _, stageInfo in pairs(allStages) do
		if stageInfo.stage == currentStage + 1 then
			nextStageInfo = stageInfo
			break
		end
	end

	-- No next stage exists
	if not nextStageInfo then
		return false, nil
	end

	-- Check requirements
	local requirements = nextStageInfo.requirements

	-- Check totalContribution requirement
	if requirements.totalContribution then
		if (progress.townPrestige.contributions or 0) < requirements.totalContribution then
			return false, nil
		end
	end

	-- Check individual NPC reputation requirements
	for npcName, repRequired in pairs(requirements) do
		if npcName ~= "totalContribution" then
			local currentRep = progress.npcReputation[npcName] or 0
			if currentRep < repRequired then
				return false, nil
			end
		end
	end

	-- All requirements met, upgrade!
	progress.townPrestige.stage = nextStageInfo.stage

	-- Apply rewards
	if nextStageInfo.rewards then
		-- Rewards would be applied by calling code (e.g., power capacity increase)
		progress.townPrestige.lastReward = nextStageInfo.rewards
	end

	PlayerProgress.SavePlayerProgress(player, progress)

	return true, nextStageInfo.stage
end

--[[
	ClearPlayerData(player: Player) -> void
	
	Removes player data from cache when they leave.
	Called automatically by InventoryManager on player disconnect.
]]
function PlayerProgress.ClearPlayerData(player)
	if player then
		PlayerProgress.FlushPlayerProgress(player)
		playerDataCache[player.UserId] = nil
		dirtyPlayerData[player.UserId] = nil
		saveScheduled[player.UserId] = nil
		saveInProgress[player.UserId] = nil
	end
end

--[[
	GetAllPlayers() -> table
	Returns all cached player data (for admin/debug purposes).
]]
function PlayerProgress.GetAllPlayers()
	return playerDataCache
end

--[[
	AdminAddMoneyByUserId(userId: number, amount: number) -> (boolean, string)
	Admin function to add money to a player by userId (works even if offline).
	Returns (success, message)
]]
function PlayerProgress.AdminAddMoneyByUserId(userId, amount)
	if type(userId) ~= "number" or type(amount) ~= "number" then
		return false, "UserId and amount must be numbers"
	end

	-- Try to modify in-memory cache first if player is online
	if playerDataCache[userId] then
		playerDataCache[userId].money = playerDataCache[userId].money + amount
		SavePlayerDataToStore(userId, playerDataCache[userId])
		return true, "Added " .. amount .. " money to player " .. userId .. " (online). New balance: " .. playerDataCache[userId].money
	end

	-- Try to load and modify from DataStore if offline
	if not dataStoreReady or not playerDataStore then
		return false, "DataStore not available"
	end

	local key = "PlayerData_" .. userId
	local success, data = pcall(function()
		return playerDataStore:GetAsync(key)
	end)

	if not success or not data then
		return false, "Could not load player data for userId " .. userId
	end

	-- Add money
	data.money = (data.money or 0) + amount

	-- Save back
	local saveSuccess, saveErr = SavePlayerDataToStore(userId, data)
	if saveSuccess then
		return true, "Added " .. amount .. " money to player " .. userId .. " (offline). New balance: " .. data.money
	else
		return false, "Failed to save: " .. (saveErr or "Unknown error")
	end
end

-- ============================================================================
-- Initialization
-- ============================================================================

InitializeDataStore()

-- Auto-save all player data periodically
task.spawn(function()
	while true do
		wait(AUTO_SAVE_INTERVAL)

		for userId, progressData in pairs(playerDataCache) do
			task.spawn(function()
				if dirtyPlayerData[userId] then
					SaveCachedPlayerData(userId)
				else
					SavePlayerDataToStore(userId, progressData)
				end
			end)
		end
	end
end)

-- ============================================================================
-- Export module
-- ============================================================================

return PlayerProgress
