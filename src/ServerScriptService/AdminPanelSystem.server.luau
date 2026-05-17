--[[
	AdminPanelSystem.server.luau

	Private admin tooling for test account Noctino52.
	Every action is authorized server-side; the client only renders data returned
	by this script.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerProgress = require(game.ServerScriptService.PlayerProgress)
local TutorialSystem = require(game.ServerScriptService.TutorialSystem)

local ADMIN_USERNAMES = {
	Noctino52 = true,
}

local PROGRESS_STORE_NAME = "MayorsFactoryTycoon_PlayerData"
local PLOT_STORE_NAME = "TycoonFactoryData"
local ADMIN_INDEX_STORE_NAME = "MayorsFactoryTycoon_AdminPlayerIndex"
local ADMIN_INDEX_KEY = "Players"
local PROGRESS_KEY_PREFIX = "PlayerData_"
local PLOT_KEY_PREFIX = "Player_"
local LIST_KEYS_PAGE_SIZE = 100

local progressDataStore = DataStoreService:GetDataStore(PROGRESS_STORE_NAME)
local plotDataStore = DataStoreService:GetDataStore(PLOT_STORE_NAME)
local adminIndexStore = DataStoreService:GetDataStore(ADMIN_INDEX_STORE_NAME)

local adminIndexCache = nil

local function getOrCreateFolder(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local adminFolder = getOrCreateFolder(ReplicatedStorage, "AdminPanel")
local adminRequestRemote = adminFolder:FindFirstChild("AdminPanelRequest")
if adminRequestRemote then
	adminRequestRemote:Destroy()
end

adminRequestRemote = Instance.new("RemoteFunction")
adminRequestRemote.Name = "AdminPanelRequest"
adminRequestRemote.Parent = adminFolder

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

local function isAuthorized(player)
	return player ~= nil and ADMIN_USERNAMES[player.Name] == true
end

local function getOnlinePlayerByUserId(userId)
	userId = tonumber(userId)
	if not userId then
		return nil
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == userId then
			return player
		end
	end

	return nil
end

local function sanitizeIndexEntry(entry)
	entry = type(entry) == "table" and entry or {}

	return {
		userId = tonumber(entry.userId) or 0,
		name = tostring(entry.name or ""),
		displayName = tostring(entry.displayName or ""),
		firstSeen = tonumber(entry.firstSeen) or os.time(),
		lastSeen = tonumber(entry.lastSeen) or os.time(),
		lastResetAt = tonumber(entry.lastResetAt),
		lastAdminEditAt = tonumber(entry.lastAdminEditAt),
		lastPlaceId = entry.lastPlaceId,
		lastJobId = entry.lastJobId,
	}
end

local function loadAdminIndex()
	if adminIndexCache then
		return adminIndexCache
	end

	local success, data = pcall(function()
		return adminIndexStore:GetAsync(ADMIN_INDEX_KEY)
	end)

	if not success or type(data) ~= "table" then
		adminIndexCache = {}
		return adminIndexCache
	end

	adminIndexCache = {}
	local rawPlayers = type(data.players) == "table" and data.players or data
	for userIdKey, entry in pairs(rawPlayers) do
		local userId = tonumber(userIdKey) or tonumber(entry.userId)
		if userId then
			local sanitized = sanitizeIndexEntry(entry)
			sanitized.userId = userId
			adminIndexCache[tostring(userId)] = sanitized
		end
	end

	return adminIndexCache
end

local function saveAdminIndex()
	local index = loadAdminIndex()

	local success, err = pcall(function()
		adminIndexStore:SetAsync(ADMIN_INDEX_KEY, {
			version = 1,
			updatedAt = os.time(),
			players = index,
		})
	end)

	if not success then
		warn("[AdminPanel] Failed to save player index:", err)
	end

	return success
end

local function updatePlayerIndex(player)
	local index = loadAdminIndex()
	local userIdKey = tostring(player.UserId)
	local now = os.time()
	local existing = index[userIdKey]

	index[userIdKey] = {
		userId = player.UserId,
		name = player.Name,
		displayName = player.DisplayName,
		firstSeen = existing and existing.firstSeen or now,
		lastSeen = now,
		lastResetAt = existing and existing.lastResetAt,
		lastAdminEditAt = existing and existing.lastAdminEditAt,
		lastPlaceId = game.PlaceId,
		lastJobId = game.JobId,
	}

	task.spawn(saveAdminIndex)
end

local function markAdminEdited(userId, reset)
	local index = loadAdminIndex()
	local userIdKey = tostring(userId)
	local entry = sanitizeIndexEntry(index[userIdKey])

	entry.userId = userId
	entry.lastAdminEditAt = os.time()
	if reset then
		entry.lastResetAt = entry.lastAdminEditAt
	end

	index[userIdKey] = entry
	task.spawn(saveAdminIndex)
end

local function tryGetUserName(userId)
	local success, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)

	if success then
		return name
	end

	return nil
end

local function readDataStore(dataStore, key)
	local success, result = pcall(function()
		return dataStore:GetAsync(key)
	end)

	if success then
		return true, result
	end

	return false, result
end

local function writeDataStore(dataStore, key, value)
	local success, err = pcall(function()
		dataStore:SetAsync(key, value)
	end)

	return success, err
end

local function removeDataStoreKey(dataStore, key)
	local success, err = pcall(function()
		dataStore:RemoveAsync(key)
	end)

	return success, err
end

local function collectUserIdsFromKeys(dataStore, prefix, target)
	local success, pages = pcall(function()
		return dataStore:ListKeysAsync(prefix, LIST_KEYS_PAGE_SIZE)
	end)

	if not success or not pages then
		return false
	end

	while true do
		for _, keyInfo in ipairs(pages:GetCurrentPage()) do
			local keyName = keyInfo.KeyName or keyInfo.keyName or keyInfo.Name or tostring(keyInfo)
			local userId = tonumber(string.match(keyName, "^" .. prefix .. "(%d+)$"))
			if userId then
				target[userId] = true
			end
		end

		if pages.IsFinished then
			break
		end

		local advanced = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advanced then
			break
		end
	end

	return true
end

local function invokeInventoryBridge(action, userId, payload)
	local bridge = game.ServerScriptService:FindFirstChild("AdminInventoryBridge")
	if not bridge or not bridge:IsA("BindableFunction") then
		return false, "Inventory admin bridge is not ready"
	end

	local success, ok, result = pcall(function()
		return bridge:Invoke(action, userId, payload)
	end)

	if not success then
		return false, ok
	end

	return ok, result
end

local function createFallbackPlotData(rawPlotData)
	if type(rawPlotData) == "table" then
		rawPlotData.version = tonumber(rawPlotData.version) or 2
		rawPlotData.lastSaved = tick()
		return rawPlotData
	end

	return {
		version = 2,
		plotId = nil,
		inventory = {
			{ itemName = "MiraSellZone", count = 1 },
			{ itemName = "BrontSellZone", count = 1 },
			{ itemName = "ElrikSellZone", count = 1 },
		},
		placedItems = {},
		lastSaved = tick(),
	}
end

local function loadPlotDataByUserId(userId)
	local onlinePlayer = getOnlinePlayerByUserId(userId)
	if onlinePlayer then
		local ok, plotData = invokeInventoryBridge("GetPlotData", userId)
		if ok then
			return true, plotData, true
		end
	end

	local success, plotData = readDataStore(plotDataStore, PLOT_KEY_PREFIX .. tostring(userId))
	if not success then
		return false, plotData, false
	end

	return true, plotData, false
end

local function savePlotDataByUserId(userId, plotData)
	local onlinePlayer = getOnlinePlayerByUserId(userId)
	if onlinePlayer then
		local ok, result = invokeInventoryBridge("ApplyPlotData", userId, plotData)
		if ok then
			return true, result
		end

		return false, result
	end

	local saveData = createFallbackPlotData(plotData)
	local success, err = writeDataStore(plotDataStore, PLOT_KEY_PREFIX .. tostring(userId), saveData)
	if not success then
		return false, err
	end

	return true, saveData
end

local function resetPlotDataByUserId(userId)
	local onlinePlayer = getOnlinePlayerByUserId(userId)
	if onlinePlayer then
		return invokeInventoryBridge("ResetPlotData", userId)
	end

	local success, err = removeDataStoreKey(plotDataStore, PLOT_KEY_PREFIX .. tostring(userId))
	if not success then
		return false, err
	end

	return true, nil
end

local function getKnownUserIds()
	local knownUserIds = {}
	local index = loadAdminIndex()

	for userIdKey in pairs(index) do
		local userId = tonumber(userIdKey)
		if userId then
			knownUserIds[userId] = true
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		knownUserIds[player.UserId] = true
	end

	collectUserIdsFromKeys(progressDataStore, PROGRESS_KEY_PREFIX, knownUserIds)
	collectUserIdsFromKeys(plotDataStore, PLOT_KEY_PREFIX, knownUserIds)

	return knownUserIds
end

local function getPlayerSummary(userId)
	local userIdKey = tostring(userId)
	local indexEntry = loadAdminIndex()[userIdKey]
	local onlinePlayer = getOnlinePlayerByUserId(userId)
	local name = onlinePlayer and onlinePlayer.Name or (indexEntry and indexEntry.name)

	if not name or name == "" then
		name = tryGetUserName(userId) or ("User " .. tostring(userId))
	end

	local progressExists, rawProgress = readDataStore(progressDataStore, PROGRESS_KEY_PREFIX .. tostring(userId))
	local plotExists, rawPlot = readDataStore(plotDataStore, PLOT_KEY_PREFIX .. tostring(userId))

	return {
		userId = userId,
		name = name,
		displayName = onlinePlayer and onlinePlayer.DisplayName or (indexEntry and indexEntry.displayName) or name,
		online = onlinePlayer ~= nil,
		firstSeen = indexEntry and indexEntry.firstSeen or nil,
		lastSeen = indexEntry and indexEntry.lastSeen or nil,
		lastResetAt = indexEntry and indexEntry.lastResetAt or nil,
		lastAdminEditAt = indexEntry and indexEntry.lastAdminEditAt or nil,
		progressMeta = {
			key = PROGRESS_KEY_PREFIX .. tostring(userId),
			exists = progressExists and rawProgress ~= nil,
			version = type(rawProgress) == "table" and rawProgress.version or nil,
			lastSaved = type(rawProgress) == "table" and rawProgress.lastSaved or nil,
		},
		plotMeta = {
			key = PLOT_KEY_PREFIX .. tostring(userId),
			exists = plotExists and rawPlot ~= nil,
			version = type(rawPlot) == "table" and rawPlot.version or nil,
			lastSaved = type(rawPlot) == "table" and rawPlot.lastSaved or nil,
			inventoryCount = type(rawPlot) == "table" and type(rawPlot.inventory) == "table" and #rawPlot.inventory or 0,
			placedItemsCount = type(rawPlot) == "table" and type(rawPlot.placedItems) == "table" and #rawPlot.placedItems or 0,
		},
	}
end

local function listPlayers()
	local summaries = {}
	for userId in pairs(getKnownUserIds()) do
		table.insert(summaries, getPlayerSummary(userId))
	end

	table.sort(summaries, function(a, b)
		if a.online ~= b.online then
			return a.online
		end

		local aSeen = tonumber(a.lastSeen) or 0
		local bSeen = tonumber(b.lastSeen) or 0
		if aSeen ~= bSeen then
			return aSeen > bSeen
		end

		return tostring(a.name) < tostring(b.name)
	end)

	return {
		players = summaries,
		generatedAt = os.time(),
	}
end

local function getPlayerData(userId)
	userId = tonumber(userId)
	if not userId then
		return false, "Invalid UserId"
	end

	local progressOk, progressData = PlayerProgress.AdminLoadProgressByUserId(userId)
	if not progressOk then
		return false, progressData
	end

	local plotOk, plotData, livePlot = loadPlotDataByUserId(userId)
	if not plotOk then
		return false, plotData
	end

	return true, {
		summary = getPlayerSummary(userId),
		progressData = progressData,
		plotData = plotData,
		meta = {
			progressStore = PROGRESS_STORE_NAME,
			plotStore = PLOT_STORE_NAME,
			livePlot = livePlot == true,
			loadedAt = os.time(),
		},
	}
end

local function refreshOnlinePlayerTutorial(userId)
	local player = getOnlinePlayerByUserId(userId)
	if not player then
		return
	end

	local tutorialUpdatedRemote = ReplicatedStorage:FindFirstChild("TutorialUpdated")
	if tutorialUpdatedRemote and tutorialUpdatedRemote:IsA("RemoteEvent") then
		tutorialUpdatedRemote:FireClient(player, TutorialSystem.GetTutorialState(player))
	end
end

local function savePlayerData(userId, payload)
	userId = tonumber(userId)
	if not userId then
		return false, "Invalid UserId"
	end

	if type(payload) ~= "table" then
		return false, "Payload must be a table"
	end

	local progressData = payload.progressData
	local plotData = payload.plotData

	if progressData ~= nil then
		local ok, result = PlayerProgress.AdminSaveProgressByUserId(userId, progressData)
		if not ok then
			return false, result
		end
	end

	if plotData ~= nil then
		local ok, result = savePlotDataByUserId(userId, plotData)
		if not ok then
			return false, result
		end
	end

	markAdminEdited(userId, false)
	refreshOnlinePlayerTutorial(userId)
	return getPlayerData(userId)
end

local function resetPlayerData(userId)
	userId = tonumber(userId)
	if not userId then
		return false, "Invalid UserId"
	end

	local progressOk, progressResult = PlayerProgress.AdminResetProgressByUserId(userId)
	if not progressOk then
		return false, progressResult
	end

	local plotOk, plotResult = resetPlotDataByUserId(userId)
	if not plotOk then
		return false, plotResult
	end

	markAdminEdited(userId, true)
	refreshOnlinePlayerTutorial(userId)
	return getPlayerData(userId)
end

adminRequestRemote.OnServerInvoke = function(player, action, payload)
	if not isAuthorized(player) then
		warn("[AdminPanel] Unauthorized admin request from " .. tostring(player and player.Name) .. ": " .. tostring(action))
		return {
			success = false,
			message = "Unauthorized",
		}
	end

	if action == "IsAuthorized" then
		return {
			success = true,
			authorized = true,
		}
	elseif action == "ListPlayers" then
		return {
			success = true,
			data = listPlayers(),
		}
	elseif action == "GetPlayerData" then
		local ok, result = getPlayerData(payload and payload.userId)
		return {
			success = ok,
			data = ok and result or nil,
			message = ok and nil or tostring(result),
		}
	elseif action == "SavePlayerData" then
		local ok, result = savePlayerData(payload and payload.userId, payload)
		return {
			success = ok,
			data = ok and result or nil,
			message = ok and "Saved" or tostring(result),
		}
	elseif action == "ResetPlayerData" then
		local ok, result = resetPlayerData(payload and payload.userId)
		return {
			success = ok,
			data = ok and result or nil,
			message = ok and "Reset complete" or tostring(result),
		}
	end

	return {
		success = false,
		message = "Unknown admin action",
	}
end

Players.PlayerAdded:Connect(updatePlayerIndex)
for _, player in ipairs(Players:GetPlayers()) do
	updatePlayerIndex(player)
end

print("[AdminPanel] Server admin panel ready")
