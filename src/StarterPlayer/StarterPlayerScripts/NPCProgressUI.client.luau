--[[
	NPCProgressUI.client.luau

	Client-side read-only UI for NPC sales statistics and town prestige progress.
	All mutable progress comes from the server GetSalesStats snapshot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Definitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Definitions"))
local getSalesStatsRemote = ReplicatedStorage:WaitForChild("GetSalesStats")
local saleFeedbackRemote = ReplicatedStorage:WaitForChild("ProductionItemSold", 5)

local BUTTON_ORDER = { "Mira", "Bront", "Elrik", "Mayor" }
local BUTTON_LABELS = {
	Mira = "Mira",
	Bront = "Bront",
	Elrik = "Elrik",
	Mayor = "Sindaco",
}

local GUI_NAME = "NPCProgressUI"
local BUTTON_WIDTH = 78
local BUTTON_HEIGHT = 32
local PANEL_WIDTH = 360
local PANEL_HEIGHT = 330

local selectedMenu = nil
local latestStats = nil
local ui = {}

local function clearChildren(container)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function formatNumber(value)
	value = tonumber(value) or 0
	return tostring(math.floor(value))
end

local function getItemBasePrice(itemName, npcData)
	local itemData = Definitions.GetItem(itemName)
	if not itemData or type(itemData.value) ~= "number" then
		return nil
	end

	return math.floor(itemData.value * (npcData.basePriceMultiplier or 1))
end

local function getCurrentStageInfo(stage)
	stage = tonumber(stage) or 1

	for _, stageInfo in pairs(Definitions.TOWN_PRESTIGE_STAGES) do
		if (tonumber(stageInfo.stage) or 0) == stage then
			return stageInfo
		end
	end

	return nil
end

local function getNextStageInfo(stats)
	local townPrestige = stats and stats.townPrestige or {}
	if townPrestige.nextStage then
		return townPrestige.nextStage
	end

	local currentStage = tonumber(townPrestige.stage) or 1
	for _, stageInfo in pairs(Definitions.TOWN_PRESTIGE_STAGES) do
		if (tonumber(stageInfo.stage) or 0) == currentStage + 1 then
			return stageInfo
		end
	end

	return nil
end

local function getRequirementLabel(requirementName)
	if requirementName == "totalContribution" then
		return "Contributi"
	end

	return tostring(requirementName):gsub("Reputation$", " Rep")
end

local function getRequirementProgress(stats, requirementName)
	if requirementName == "totalContribution" then
		return tonumber(stats.townPrestige and stats.townPrestige.contributions) or 0
	end

	local reputation = stats.npcReputation or {}
	if reputation[requirementName] ~= nil then
		return tonumber(reputation[requirementName]) or 0
	end

	local normalizedName = tostring(requirementName):gsub("Reputation$", "")
	if normalizedName ~= requirementName and reputation[normalizedName] ~= nil then
		return tonumber(reputation[normalizedName]) or 0
	end

	return 0
end

local function createLabel(name, text, textSize, color, height, bold)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, 0, 0, height or 24)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or Color3.fromRGB(236, 241, 248)
	label.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	label.TextSize = textSize or 14
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center

	return label
end

local function createInfoRow(name, leftText, rightText, accentColor)
	local row = Instance.new("Frame")
	row.Name = name
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundColor3 = Color3.fromRGB(40, 45, 55)
	row.BackgroundTransparency = 0.05
	row.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = row

	local stroke = Instance.new("UIStroke")
	stroke.Color = accentColor or Color3.fromRGB(70, 88, 112)
	stroke.Thickness = 1
	stroke.Transparency = 0.45
	stroke.Parent = row

	local left = Instance.new("TextLabel")
	left.Name = "Left"
	left.Size = UDim2.new(0.58, -10, 1, 0)
	left.Position = UDim2.fromOffset(10, 0)
	left.BackgroundTransparency = 1
	left.Text = leftText
	left.TextColor3 = Color3.fromRGB(238, 242, 248)
	left.Font = Enum.Font.GothamMedium
	left.TextSize = 13
	left.TextTruncate = Enum.TextTruncate.AtEnd
	left.TextXAlignment = Enum.TextXAlignment.Left
	left.Parent = row

	local right = Instance.new("TextLabel")
	right.Name = "Right"
	right.Size = UDim2.new(0.42, -10, 1, 0)
	right.Position = UDim2.new(0.58, 0, 0, 0)
	right.BackgroundTransparency = 1
	right.Text = rightText
	right.TextColor3 = Color3.fromRGB(173, 213, 255)
	right.Font = Enum.Font.GothamBold
	right.TextSize = 13
	right.TextTruncate = Enum.TextTruncate.AtEnd
	right.TextXAlignment = Enum.TextXAlignment.Right
	right.Parent = row

	return row
end

local function setPanelVisible(visible)
	if ui.panel then
		ui.panel.Visible = visible
	end
end

local function fetchStats()
	local success, result = pcall(function()
		return getSalesStatsRemote:InvokeServer()
	end)

	if success and type(result) == "table" then
		latestStats = result
		return result
	end

	warn("[NPCProgressUI] Failed to fetch sales stats:", result)
	return latestStats
end

local function renderNPCMenu(npcName, stats)
	local npcData = Definitions.GetNPC(npcName)
	if not npcData then
		return
	end

	local soldByNpc = (stats.npcSold and stats.npcSold[npcName]) or {}
	local reputation = (stats.npcReputation and stats.npcReputation[npcName]) or 0
	local title = tostring(npcData.name or npcName) .. " - " .. tostring(npcData.title or "NPC")

	ui.title.Text = title
	clearChildren(ui.content)

	createLabel("Reputation", "Reputation attuale: " .. formatNumber(reputation), 14, Color3.fromRGB(174, 216, 255), 26, true).Parent = ui.content
	createLabel("ItemsTitle", "Item accettati", 13, Color3.fromRGB(238, 242, 248), 22, true).Parent = ui.content

	local header = createInfoRow("Header", "Item", "Prezzo / Venduti", Color3.fromRGB(95, 118, 145))
	header.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
	header.Parent = ui.content

	for _, itemName in ipairs(npcData.buysItems or {}) do
		local price = getItemBasePrice(itemName, npcData)
		local priceText = price and ("$" .. formatNumber(price)) or "N/D"
		local soldText = priceText .. " / " .. formatNumber(soldByNpc[itemName])
		createInfoRow(itemName .. "Row", itemName, soldText, Color3.fromRGB(71, 103, 135)).Parent = ui.content
	end
end

local function formatRewardText(rewards)
	if type(rewards) ~= "table" then
		return "Nessuna"
	end

	local parts = {}
	if rewards.powerCapacity then
		table.insert(parts, "Power " .. tostring(rewards.powerCapacity))
	end

	if type(rewards.newShopItems) == "table" and #rewards.newShopItems > 0 then
		table.insert(parts, "Shop: " .. table.concat(rewards.newShopItems, ", "))
	end

	if #parts == 0 then
		return "Nessuna"
	end

	return table.concat(parts, " | ")
end

local function renderMayorMenu(stats)
	local townPrestige = stats.townPrestige or {}
	local currentStageInfo = getCurrentStageInfo(townPrestige.stage)
	local nextStageInfo = getNextStageInfo(stats)
	local stageName = townPrestige.stageName or (currentStageInfo and currentStageInfo.name) or "Stage"
	local contributions = tonumber(townPrestige.contributions) or 0

	ui.title.Text = "Sindaco - Town Prestige"
	clearChildren(ui.content)

	createLabel("Stage", "Stage attuale: " .. formatNumber(townPrestige.stage) .. " - " .. tostring(stageName), 14, Color3.fromRGB(255, 216, 148), 28, true).Parent = ui.content
	createInfoRow("ContributionTotal", "Contributi totali", formatNumber(contributions), Color3.fromRGB(132, 110, 61)).Parent = ui.content

	if not nextStageInfo then
		createLabel("NoNextStage", "Prestige massimo raggiunto", 14, Color3.fromRGB(167, 240, 183), 28, true).Parent = ui.content
		return
	end

	createLabel("NextRequirements", "Requisiti prossimo stage: " .. tostring(nextStageInfo.name or ("Stage " .. tostring(nextStageInfo.stage))), 13, Color3.fromRGB(238, 242, 248), 26, true).Parent = ui.content

	for requirementName, requiredValue in pairs(nextStageInfo.requirements or {}) do
		local currentValue = getRequirementProgress(stats, requirementName)
		local rowText = formatNumber(currentValue) .. " / " .. formatNumber(requiredValue)
		createInfoRow("Req" .. tostring(requirementName), getRequirementLabel(requirementName), rowText, Color3.fromRGB(116, 92, 52)).Parent = ui.content
	end

	local missingContribution = math.max(0, (tonumber((nextStageInfo.requirements or {}).totalContribution) or 0) - contributions)
	createInfoRow("MissingContribution", "Manca ai contributi", formatNumber(missingContribution), Color3.fromRGB(150, 112, 58)).Parent = ui.content

	createLabel("RewardsTitle", "Ricompense prossimo stage", 13, Color3.fromRGB(238, 242, 248), 24, true).Parent = ui.content
	createLabel("Rewards", formatRewardText(nextStageInfo.rewards), 13, Color3.fromRGB(172, 227, 191), 44, false).Parent = ui.content
end

local function renderSelectedMenu()
	if not selectedMenu then
		setPanelVisible(false)
		return
	end

	local stats = fetchStats()
	if not stats then
		return
	end

	setPanelVisible(true)

	if selectedMenu == "Mayor" then
		renderMayorMenu(stats)
	else
		renderNPCMenu(selectedMenu, stats)
	end
end

local function selectMenu(menuName)
	if selectedMenu == menuName and ui.panel and ui.panel.Visible then
		selectedMenu = nil
	else
		selectedMenu = menuName
	end

	for _, button in pairs(ui.buttons or {}) do
		local isSelected = button.Name == (tostring(selectedMenu) .. "Button")
		button.BackgroundColor3 = isSelected and Color3.fromRGB(69, 112, 158) or Color3.fromRGB(36, 42, 53)
		button.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(218, 227, 238)
	end

	renderSelectedMenu()
end

local function createButton(menuName)
	local button = Instance.new("TextButton")
	button.Name = menuName .. "Button"
	button.Size = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT)
	button.BackgroundColor3 = Color3.fromRGB(36, 42, 53)
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = BUTTON_LABELS[menuName] or menuName
	button.TextColor3 = Color3.fromRGB(218, 227, 238)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 12

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(96, 123, 154)
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Parent = button

	button.Activated:Connect(function()
		selectMenu(menuName)
	end)

	return button
end

local function createUI()
	local existingGui = playerGui:FindFirstChild(GUI_NAME)
	if existingGui then
		existingGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = GUI_NAME
	screenGui.ResetOnSpawn = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local buttonFrame = Instance.new("Frame")
	buttonFrame.Name = "ButtonFrame"
	buttonFrame.Size = UDim2.fromOffset((BUTTON_WIDTH + 8) * #BUTTON_ORDER - 8, BUTTON_HEIGHT)
	buttonFrame.Position = UDim2.fromOffset(15, 285)
	buttonFrame.BackgroundTransparency = 1
	buttonFrame.Parent = screenGui

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Padding = UDim.new(0, 8)
	buttonLayout.Parent = buttonFrame

	ui.buttons = {}
	for index, menuName in ipairs(BUTTON_ORDER) do
		local button = createButton(menuName)
		button.LayoutOrder = index
		button.Parent = buttonFrame
		ui.buttons[menuName] = button
	end

	local panel = Instance.new("Frame")
	panel.Name = "StatsPanel"
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT)
	panel.Position = UDim2.fromOffset(15, 325)
	panel.BackgroundColor3 = Color3.fromRGB(22, 26, 34)
	panel.BackgroundTransparency = 0.02
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui
	ui.panel = panel

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(100, 128, 161)
	panelStroke.Thickness = 2
	panelStroke.Transparency = 0.25
	panelStroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = panel

	local title = createLabel("Title", "Statistiche", 16, Color3.fromRGB(255, 255, 255), 30, true)
	title.Parent = panel
	ui.title = title

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.fromOffset(28, 28)
	closeButton.Position = UDim2.new(1, -28, 0, 0)
	closeButton.BackgroundColor3 = Color3.fromRGB(54, 61, 74)
	closeButton.BorderSizePixel = 0
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(235, 240, 248)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 13
	closeButton.Parent = panel

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = closeButton

	closeButton.Activated:Connect(function()
		selectedMenu = nil
		selectMenu(nil)
	end)

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Size = UDim2.new(1, 0, 1, -42)
	content.Position = UDim2.fromOffset(0, 42)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.fromOffset(0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 5
	content.ScrollBarImageColor3 = Color3.fromRGB(110, 135, 165)
	content.Parent = panel
	ui.content = content

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.FillDirection = Enum.FillDirection.Vertical
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 7)
	contentLayout.Parent = content

	return screenGui
end

createUI()
fetchStats()

if saleFeedbackRemote then
	saleFeedbackRemote.OnClientEvent:Connect(function()
		fetchStats()
		renderSelectedMenu()
	end)
end

task.spawn(function()
	while true do
		task.wait(2)
		if not ui.panel or not ui.panel.Parent then
			break
		end

		if selectedMenu then
			renderSelectedMenu()
		else
			fetchStats()
		end
	end
end)

print("[NPCProgressUI] NPC progress UI initialized successfully!")
