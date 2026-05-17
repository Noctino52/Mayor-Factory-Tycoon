--[[
	AdminPanelClient.client.luau

	Client UI for the private Noctino52 admin panel.
	All permissions and writes are validated by AdminPanelSystem.server.luau.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if player.Name ~= "Noctino52" then
	return
end

local adminFolder = ReplicatedStorage:WaitForChild("AdminPanel")
local adminRequestRemote = adminFolder:WaitForChild("AdminPanelRequest")
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "NoctinoAdminPanel"
local PANEL_WIDTH = 920
local PANEL_HEIGHT = 590

local ui = {}
local playerSummaries = {}
local selectedUserId = nil
local selectedData = nil
local resetConfirmUntil = 0

local function invokeAdmin(action, payload)
	local success, result = pcall(function()
		return adminRequestRemote:InvokeServer(action, payload or {})
	end)

	if not success then
		return {
			success = false,
			message = tostring(result),
		}
	end

	if type(result) ~= "table" then
		return {
			success = false,
			message = "Invalid admin response",
		}
	end

	return result
end

local function isArray(value)
	if type(value) ~= "table" then
		return false
	end

	local count = 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or math.floor(key) ~= key then
			return false
		end
		count += 1
	end

	for index = 1, count do
		if value[index] == nil then
			return false
		end
	end

	return true
end

local function encodeScalar(value)
	local valueType = type(value)
	if valueType == "string" or valueType == "number" or valueType == "boolean" or value == nil then
		return HttpService:JSONEncode(value)
	end

	return HttpService:JSONEncode(tostring(value))
end

local function sortedKeys(value)
	local keys = {}
	for key in pairs(value) do
		table.insert(keys, key)
	end

	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	return keys
end

local function prettyJson(value, indentLevel)
	indentLevel = indentLevel or 0
	if type(value) ~= "table" then
		return encodeScalar(value)
	end

	local indent = string.rep("  ", indentLevel)
	local childIndent = string.rep("  ", indentLevel + 1)

	if isArray(value) then
		if #value == 0 then
			return "[]"
		end

		local parts = {}
		for _, childValue in ipairs(value) do
			table.insert(parts, childIndent .. prettyJson(childValue, indentLevel + 1))
		end

		return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
	end

	local keys = sortedKeys(value)
	if #keys == 0 then
		return "{}"
	end

	local parts = {}
	for _, key in ipairs(keys) do
		table.insert(parts, childIndent .. HttpService:JSONEncode(tostring(key)) .. ": " .. prettyJson(value[key], indentLevel + 1))
	end

	return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

local function setStatus(message, isError)
	if not ui.statusLabel then
		return
	end

	ui.statusLabel.Text = message or ""
	ui.statusLabel.TextColor3 = isError and Color3.fromRGB(255, 130, 130) or Color3.fromRGB(150, 238, 168)
end

local function clearChildren(container, keepLayouts)
	for _, child in ipairs(container:GetChildren()) do
		if keepLayouts and (child:IsA("UIListLayout") or child:IsA("UIPadding")) then
			continue
		end

		child:Destroy()
	end
end

local function createButton(parent, name, text, size, position, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color or Color3.fromRGB(48, 90, 130)
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.fromRGB(245, 248, 252)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.AutoButtonColor = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	return button
end

local function createLabel(parent, name, text, size, position, textSize, bold)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(232, 238, 246)
	label.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	label.TextSize = textSize or 13
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

local function createJsonBox(parent, name, position)
	local box = Instance.new("TextBox")
	box.Name = name
	box.Size = UDim2.fromOffset(620, 190)
	box.Position = position
	box.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Code
	box.TextSize = 12
	box.TextColor3 = Color3.fromRGB(232, 238, 246)
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.TextWrapped = false
	box.MultiLine = true
	box.Text = "{}"
	box.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = box

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(70, 88, 108)
	stroke.Thickness = 1
	stroke.Transparency = 0.25
	stroke.Parent = box

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = box

	return box
end

local function setPanelVisible(visible)
	ui.panel.Visible = visible
	if visible then
		resetConfirmUntil = 0
		ui.resetButton.Text = "RESET"
	end
end

local function formatTimestamp(value)
	value = tonumber(value)
	if not value then
		return "-"
	end

	if value > 1000000000 then
		return os.date("%Y-%m-%d %H:%M:%S", value)
	end

	return string.format("tick %.0f", value)
end

local function renderMetadata(data)
	if type(data) ~= "table" then
		ui.metaLabel.Text = "No player selected"
		return
	end

	local summary = data.summary or {}
	local progressMeta = summary.progressMeta or {}
	local plotMeta = summary.plotMeta or {}
	local meta = data.meta or {}

	ui.metaLabel.Text = table.concat({
		"User: " .. tostring(summary.name or "?") .. " (" .. tostring(summary.userId or "?") .. ")",
		"Online: " .. tostring(summary.online == true) .. " | Live plot: " .. tostring(meta.livePlot == true),
		"Progress: " .. tostring(progressMeta.key or "-") .. " | saved: " .. tostring(progressMeta.exists == true) .. " | last: " .. formatTimestamp(progressMeta.lastSaved),
		"Plot: " .. tostring(plotMeta.key or "-") .. " | saved: " .. tostring(plotMeta.exists == true) .. " | inventory: " .. tostring(plotMeta.inventoryCount or 0) .. " | placed: " .. tostring(plotMeta.placedItemsCount or 0),
		"Seen: " .. formatTimestamp(summary.firstSeen) .. " -> " .. formatTimestamp(summary.lastSeen),
		"Admin edit: " .. formatTimestamp(summary.lastAdminEditAt) .. " | reset: " .. formatTimestamp(summary.lastResetAt),
	}, "\n")
end

local function renderSelectedData(data)
	selectedData = data
	renderMetadata(data)

	ui.progressBox.Text = prettyJson(data and data.progressData or {})
	ui.plotBox.Text = prettyJson(data and data.plotData or {})
end

local function loadPlayerData(userId)
	selectedUserId = tonumber(userId)
	if not selectedUserId then
		return
	end

	setStatus("Loading player data...", false)
	local response = invokeAdmin("GetPlayerData", {
		userId = selectedUserId,
	})

	if not response.success then
		setStatus(response.message or "Load failed", true)
		return
	end

	renderSelectedData(response.data)
	setStatus("Loaded " .. tostring((response.data.summary or {}).name or selectedUserId), false)
end

local function renderPlayerList()
	clearChildren(ui.playerList, true)

	for _, summary in ipairs(playerSummaries) do
		local row = createButton(
			ui.playerList,
			"Player_" .. tostring(summary.userId),
			"",
			UDim2.new(1, -8, 0, 46),
			UDim2.fromOffset(0, 0),
			summary.userId == selectedUserId and Color3.fromRGB(58, 112, 154) or Color3.fromRGB(35, 43, 54)
		)
		row.LayoutOrder = summary.online and 0 or 1
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextSize = 12
		row.Text = (summary.online and "[ONLINE] " or "") .. tostring(summary.name or "?") .. "\n" .. tostring(summary.userId)

		row.Activated:Connect(function()
			loadPlayerData(summary.userId)
			renderPlayerList()
		end)
	end
end

local function refreshPlayerList()
	setStatus("Refreshing players...", false)
	local response = invokeAdmin("ListPlayers")
	if not response.success then
		setStatus(response.message or "Refresh failed", true)
		return
	end

	playerSummaries = (response.data and response.data.players) or {}
	renderPlayerList()
	setStatus("Players loaded: " .. tostring(#playerSummaries), false)
end

local function decodeJsonBox(box, label)
	local success, result = pcall(function()
		return HttpService:JSONDecode(box.Text)
	end)

	if not success then
		return false, label .. " JSON invalid: " .. tostring(result)
	end

	return true, result
end

local function saveSelectedPlayer()
	if not selectedUserId then
		setStatus("Select a player first", true)
		return
	end

	local progressOk, progressData = decodeJsonBox(ui.progressBox, "Progress")
	if not progressOk then
		setStatus(progressData, true)
		return
	end

	local plotOk, plotData = decodeJsonBox(ui.plotBox, "Plot")
	if not plotOk then
		setStatus(plotData, true)
		return
	end

	setStatus("Saving...", false)
	local response = invokeAdmin("SavePlayerData", {
		userId = selectedUserId,
		progressData = progressData,
		plotData = plotData,
	})

	if not response.success then
		setStatus(response.message or "Save failed", true)
		return
	end

	renderSelectedData(response.data)
	refreshPlayerList()
	setStatus("Saved", false)
end

local function resetSelectedPlayer()
	if not selectedUserId then
		setStatus("Select a player first", true)
		return
	end

	local now = tick()
	if now > resetConfirmUntil then
		resetConfirmUntil = now + 4
		ui.resetButton.Text = "CONFIRM"
		setStatus("Click CONFIRM within 4 seconds to reset this player", true)
		return
	end

	resetConfirmUntil = 0
	ui.resetButton.Text = "RESET"
	setStatus("Resetting...", false)

	local response = invokeAdmin("ResetPlayerData", {
		userId = selectedUserId,
	})

	if not response.success then
		setStatus(response.message or "Reset failed", true)
		return
	end

	renderSelectedData(response.data)
	refreshPlayerList()
	setStatus("Reset complete", false)
end

local function createUI()
	local existing = playerGui:FindFirstChild(GUI_NAME)
	if existing then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = GUI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local openButton = createButton(
		screenGui,
		"OpenAdminButton",
		"Admin",
		UDim2.fromOffset(74, 32),
		UDim2.new(1, -94, 0, 112),
		Color3.fromRGB(72, 78, 96)
	)
	ui.openButton = openButton

	local panel = Instance.new("Frame")
	panel.Name = "AdminPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT)
	panel.BackgroundColor3 = Color3.fromRGB(22, 27, 35)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui
	ui.panel = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(92, 116, 144)
	panelStroke.Thickness = 2
	panelStroke.Transparency = 0.15
	panelStroke.Parent = panel

	createLabel(panel, "Title", "Admin Data Panel", UDim2.fromOffset(240, 32), UDim2.fromOffset(14, 10), 18, true)

	local refreshButton = createButton(panel, "RefreshButton", "REFRESH", UDim2.fromOffset(88, 30), UDim2.fromOffset(570, 12), Color3.fromRGB(54, 94, 132))
	local saveButton = createButton(panel, "SaveButton", "SAVE", UDim2.fromOffset(76, 30), UDim2.fromOffset(666, 12), Color3.fromRGB(44, 124, 74))
	local resetButton = createButton(panel, "ResetButton", "RESET", UDim2.fromOffset(84, 30), UDim2.fromOffset(750, 12), Color3.fromRGB(154, 58, 52))
	local closeButton = createButton(panel, "CloseButton", "X", UDim2.fromOffset(34, 30), UDim2.fromOffset(872, 12), Color3.fromRGB(68, 74, 88))
	ui.resetButton = resetButton

	local playerList = Instance.new("ScrollingFrame")
	playerList.Name = "PlayerList"
	playerList.Size = UDim2.fromOffset(246, 510)
	playerList.Position = UDim2.fromOffset(14, 62)
	playerList.BackgroundColor3 = Color3.fromRGB(17, 21, 27)
	playerList.BorderSizePixel = 0
	playerList.ScrollBarThickness = 6
	playerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	playerList.CanvasSize = UDim2.fromOffset(0, 0)
	playerList.Parent = panel
	ui.playerList = playerList

	local playerListCorner = Instance.new("UICorner")
	playerListCorner.CornerRadius = UDim.new(0, 6)
	playerListCorner.Parent = playerList

	local playerListPadding = Instance.new("UIPadding")
	playerListPadding.PaddingLeft = UDim.new(0, 8)
	playerListPadding.PaddingRight = UDim.new(0, 4)
	playerListPadding.PaddingTop = UDim.new(0, 8)
	playerListPadding.PaddingBottom = UDim.new(0, 8)
	playerListPadding.Parent = playerList

	local playerListLayout = Instance.new("UIListLayout")
	playerListLayout.FillDirection = Enum.FillDirection.Vertical
	playerListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	playerListLayout.Padding = UDim.new(0, 7)
	playerListLayout.Parent = playerList

	local rightPanel = Instance.new("Frame")
	rightPanel.Name = "RightPanel"
	rightPanel.Size = UDim2.fromOffset(630, 510)
	rightPanel.Position = UDim2.fromOffset(276, 62)
	rightPanel.BackgroundTransparency = 1
	rightPanel.Parent = panel

	local metaLabel = createLabel(rightPanel, "MetaLabel", "No player selected", UDim2.fromOffset(620, 92), UDim2.fromOffset(0, 0), 12, false)
	metaLabel.TextYAlignment = Enum.TextYAlignment.Top
	ui.metaLabel = metaLabel

	createLabel(rightPanel, "ProgressTitle", "progressData JSON", UDim2.fromOffset(200, 22), UDim2.fromOffset(0, 100), 13, true)
	local progressBox = createJsonBox(rightPanel, "ProgressJsonBox", UDim2.fromOffset(0, 124))
	ui.progressBox = progressBox

	createLabel(rightPanel, "PlotTitle", "plotData JSON", UDim2.fromOffset(200, 22), UDim2.fromOffset(0, 322), 13, true)
	local plotBox = createJsonBox(rightPanel, "PlotJsonBox", UDim2.fromOffset(0, 346))
	ui.plotBox = plotBox

	local statusLabel = createLabel(panel, "StatusLabel", "", UDim2.fromOffset(420, 24), UDim2.fromOffset(274, 542), 12, false)
	statusLabel.TextColor3 = Color3.fromRGB(150, 238, 168)
	ui.statusLabel = statusLabel

	openButton.Activated:Connect(function()
		setPanelVisible(not panel.Visible)
		if panel.Visible and #playerSummaries == 0 then
			refreshPlayerList()
		end
	end)

	closeButton.Activated:Connect(function()
		setPanelVisible(false)
	end)

	refreshButton.Activated:Connect(refreshPlayerList)
	saveButton.Activated:Connect(saveSelectedPlayer)
	resetButton.Activated:Connect(resetSelectedPlayer)
end

local authResponse = invokeAdmin("IsAuthorized")
if not authResponse.success or authResponse.authorized ~= true then
	return
end

createUI()
print("[AdminPanelClient] Admin panel ready")
