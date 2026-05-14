--[[
	CurrencyUI.client.luau
	
	Client-side script for displaying currency, reputation, and town prestige HUD.
	- Shows real-time money updates with animations
	- Displays NPC reputation values
	- Shows current town prestige stage
	- Updates every 0.5 seconds
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Get remote functions
local getMoneyRemote = ReplicatedStorage:WaitForChild("GetMoney")
local getReputationRemote = ReplicatedStorage:WaitForChild("GetReputation")
local getTownPrestigeRemote = ReplicatedStorage:WaitForChild("GetTownPrestige")
local saleFeedbackRemote = ReplicatedStorage:WaitForChild("ProductionItemSold", 5)

-- Configuration
local UPDATE_INTERVAL = 0.5 -- seconds
local ANIMATION_DURATION = 0.3 -- seconds for money change animation
local HUD_WIDTH = 300
local HUD_HEIGHT = 218

-- State tracking
local currentMoney = 0

-- NPC emoji mapping
local NPC_EMOJIS = {
	Mira = "😊",
	Bront = "👷",
	Elrik = "⚒️",
}

-- Function to create the main HUD ScreenGui
local function createHUD()
	-- Check if HUD already exists
	local existingGui = playerGui:FindFirstChild("CurrencyHUD")
	if existingGui then
		existingGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CurrencyHUD"
	screenGui.ResetOnSpawn = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- Create main background frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromOffset(HUD_WIDTH, HUD_HEIGHT)
	mainFrame.Position = UDim2.fromOffset(15, 15)
	mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui

	-- Add background transparency
	local bgTransparency = Instance.new("UICorner")
	bgTransparency.CornerRadius = UDim.new(0, 10)
	bgTransparency.Parent = mainFrame

	-- Add stroke for border
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 150, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = mainFrame

	-- Add padding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = mainFrame

	-- Create vertical list layout
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = mainFrame

	-- ===== MONEY DISPLAY =====
	local moneyFrame = Instance.new("Frame")
	moneyFrame.Name = "MoneyFrame"
	moneyFrame.Size = UDim2.new(1, 0, 0, 30)
	moneyFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	moneyFrame.BorderSizePixel = 0
	moneyFrame.Parent = mainFrame

	local moneyCorner = Instance.new("UICorner")
	moneyCorner.CornerRadius = UDim.new(0, 5)
	moneyCorner.Parent = moneyFrame

	local moneyLabel = Instance.new("TextLabel")
	moneyLabel.Name = "MoneyLabel"
	moneyLabel.Size = UDim2.fromScale(1, 1)
	moneyLabel.BackgroundTransparency = 1
	moneyLabel.Text = "💵 Money: 0"
	moneyLabel.TextColor3 = Color3.fromRGB(200, 255, 100)
	moneyLabel.Font = Enum.Font.GothamBold
	moneyLabel.TextSize = 14
	moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
	moneyLabel.Parent = moneyFrame

	-- ===== REPUTATION DISPLAY =====
	local reputationFrame = Instance.new("Frame")
	reputationFrame.Name = "ReputationFrame"
	reputationFrame.Size = UDim2.new(1, 0, 0, 80)
	reputationFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	reputationFrame.BorderSizePixel = 0
	reputationFrame.Parent = mainFrame

	local repCorner = Instance.new("UICorner")
	repCorner.CornerRadius = UDim.new(0, 5)
	repCorner.Parent = reputationFrame

	local repListLayout = Instance.new("UIListLayout")
	repListLayout.FillDirection = Enum.FillDirection.Vertical
	repListLayout.Padding = UDim.new(0, 3)
	repListLayout.Parent = reputationFrame

	local repPadding = Instance.new("UIPadding")
	repPadding.PaddingLeft = UDim.new(0, 5)
	repPadding.PaddingRight = UDim.new(0, 5)
	repPadding.PaddingTop = UDim.new(0, 3)
	repPadding.PaddingBottom = UDim.new(0, 3)
	repPadding.Parent = reputationFrame

	-- Create reputation labels for each NPC
	for npcName, emoji in pairs(NPC_EMOJIS) do
		local repLabel = Instance.new("TextLabel")
		repLabel.Name = npcName .. "Rep"
		repLabel.Size = UDim2.new(1, 0, 0, 20)
		repLabel.BackgroundTransparency = 1
		repLabel.Text = emoji .. " " .. npcName .. " Rep: 0"
		repLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
		repLabel.Font = Enum.Font.Gotham
		repLabel.TextSize = 12
		repLabel.TextXAlignment = Enum.TextXAlignment.Left
		repLabel.Parent = reputationFrame
	end

	-- ===== TOWN PRESTIGE DISPLAY =====
	local prestigeFrame = Instance.new("Frame")
	prestigeFrame.Name = "PrestigeFrame"
	prestigeFrame.Size = UDim2.new(1, 0, 0, 30)
	prestigeFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	prestigeFrame.BorderSizePixel = 0
	prestigeFrame.Parent = mainFrame

	local prestigeCorner = Instance.new("UICorner")
	prestigeCorner.CornerRadius = UDim.new(0, 5)
	prestigeCorner.Parent = prestigeFrame

	local prestigeLabel = Instance.new("TextLabel")
	prestigeLabel.Name = "PrestigeLabel"
	prestigeLabel.Size = UDim2.fromScale(1, 1)
	prestigeLabel.BackgroundTransparency = 1
	prestigeLabel.Text = "🏛️ Stage 1: Outpost (0/500)"
	prestigeLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
	prestigeLabel.Font = Enum.Font.GothamBold
	prestigeLabel.TextSize = 12
	prestigeLabel.TextXAlignment = Enum.TextXAlignment.Left
	prestigeLabel.Parent = prestigeFrame

	-- ===== PLOT USAGE DISPLAY =====
	local plotUsageFrame = Instance.new("Frame")
	plotUsageFrame.Name = "PlotUsageFrame"
	plotUsageFrame.Size = UDim2.new(1, 0, 0, 30)
	plotUsageFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	plotUsageFrame.BorderSizePixel = 0
	plotUsageFrame.Parent = mainFrame

	local plotUsageCorner = Instance.new("UICorner")
	plotUsageCorner.CornerRadius = UDim.new(0, 5)
	plotUsageCorner.Parent = plotUsageFrame

	local plotUsageLabel = Instance.new("TextLabel")
	plotUsageLabel.Name = "PlotUsageLabel"
	plotUsageLabel.Size = UDim2.fromScale(1, 1)
	plotUsageLabel.BackgroundTransparency = 1
	plotUsageLabel.Text = "Machines: 0/100"
	plotUsageLabel.TextColor3 = Color3.fromRGB(190, 230, 255)
	plotUsageLabel.Font = Enum.Font.GothamBold
	plotUsageLabel.TextSize = 12
	plotUsageLabel.TextXAlignment = Enum.TextXAlignment.Left
	plotUsageLabel.Parent = plotUsageFrame

	return screenGui, {
		money = moneyLabel,
		reputation = reputationFrame,
		prestige = prestigeLabel,
		plotUsage = plotUsageLabel,
	}
end

-- Function to animate money change
local function animateMoneyChange(moneyLabel, oldMoney, newMoney)
	local difference = newMoney - oldMoney

	if difference == 0 then
		return
	end

	local isPositive = difference > 0
	local color = isPositive and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)

	-- Update text color temporarily
	moneyLabel.TextColor3 = color

	-- Reset color after animation
	task.wait(ANIMATION_DURATION)
	moneyLabel.TextColor3 = Color3.fromRGB(200, 255, 100)
end

local function showSalePopup(gui, result)
    if not gui or not gui.Parent or not result then
        return
    end

    local popup = Instance.new("TextLabel")
    popup.Name = "SalePopup"
    popup.Size = UDim2.fromOffset(260, 36)
    popup.Position = UDim2.new(0.5, -130, 0, 95)
    popup.BackgroundColor3 = Color3.fromRGB(34, 132, 72)
    popup.BackgroundTransparency = 0.08
    popup.BorderSizePixel = 0
    popup.TextColor3 = Color3.fromRGB(240, 255, 244)
    popup.TextScaled = true
    popup.Font = Enum.Font.GothamBold
    popup.Text = "+" .. tostring(result.money or 0) .. "$ +" .. tostring(result.reputation or 0) .. " Rep (" .. tostring(result.npcName or "?") .. ")"
    popup.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = popup

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(170, 255, 190)
    stroke.Thickness = 1
    stroke.Transparency = 0.25
    stroke.Parent = popup

    local tween = TweenService:Create(popup, TweenInfo.new(1.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, -130, 0, 53),
        BackgroundTransparency = 1,
        TextTransparency = 1,
    })

    tween.Completed:Connect(function()
        if popup and popup.Parent then
            popup:Destroy()
        end
    end)

    tween:Play()
end

-- Function to update HUD with current data
local function updateHUD(labels)
	-- Update money
	local money = getMoneyRemote:InvokeServer()
	if money ~= currentMoney then
		task.spawn(function()
			animateMoneyChange(labels.money, currentMoney, money)
		end)
		currentMoney = money
	end
	labels.money.Text = "💵 Money: " .. tostring(currentMoney)

	-- Update reputation
	local reputation = getReputationRemote:InvokeServer()
	if reputation then
		for npcName, npcRepValue in pairs(reputation) do
			local emoji = NPC_EMOJIS[npcName] or "❓"
			local repLabel = labels.reputation:FindFirstChild(npcName .. "Rep")
			if repLabel then
				repLabel.Text = emoji .. " " .. npcName .. " Rep: " .. tostring(npcRepValue or 0)
			end
		end
	end

	-- Update town prestige
	local prestige = getTownPrestigeRemote:InvokeServer()
	if prestige then
		-- Stage name mapping (can be expanded)
		local stageNames = {
			[1] = "Outpost",
			[2] = "Village",
			[3] = "Town",
			[4] = "City",
		}
		local stageName = stageNames[prestige.stage] or ("Stage " .. prestige.stage)
		local placedCount = prestige.currentItemsPlaced or 0
		local maxPlaced = prestige.maxItemsAllowed or 100
		if labels.plotUsage then
			labels.plotUsage.Text = "Machines: " .. tostring(placedCount) .. "/" .. tostring(maxPlaced)
		end
		labels.prestige.Text = "🏛️ " .. stageName .. " (" .. prestige.contributions .. "/500)"
	end
end

-- Main update loop
local function mainLoop()
	local gui, labels = createHUD()

	if saleFeedbackRemote then
		saleFeedbackRemote.OnClientEvent:Connect(function(result)
			showSalePopup(gui, result)
		end)
	end

	while true do
		task.wait(UPDATE_INTERVAL)

		-- Wrap in pcall to handle errors gracefully
		local success, err = pcall(function()
			updateHUD(labels)
		end)

		if not success then
			warn("[CurrencyUI] Error updating HUD:", err)
		end

		-- Check if HUD still exists (player might have left)
		if not gui or not gui.Parent then
			break
		end
	end
end

-- Initialize
mainLoop()

print("[CurrencyUI] Currency HUD initialized successfully!")
