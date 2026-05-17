--[[
	TutorialClient.client.luau

	Small objective tracker for the server-authoritative tutorial.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local getTutorialStateRemote = ReplicatedStorage:WaitForChild("GetTutorialState")
local tutorialUpdatedRemote = ReplicatedStorage:WaitForChild("TutorialUpdated")

local GUI_NAME = "TutorialObjectiveTracker"
local PANEL_COLOR = Color3.fromRGB(24, 28, 36)
local PANEL_FLASH_COLOR = Color3.fromRGB(36, 58, 48)

local ui = {}
local latestStep = nil
local activeTween = nil

local function createTracker()
	local existingGui = playerGui:FindFirstChild(GUI_NAME)
	if existingGui then
		existingGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = GUI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "ObjectiveFrame"
	mainFrame.AnchorPoint = Vector2.new(1, 0)
	mainFrame.Position = UDim2.new(1, -20, 0, 20)
	mainFrame.Size = UDim2.new(1, -40, 0, 84)
	mainFrame.BackgroundColor3 = PANEL_COLOR
	mainFrame.BackgroundTransparency = 0.03
	mainFrame.BorderSizePixel = 0
	mainFrame.Active = false
	mainFrame.Visible = false
	mainFrame.Parent = screenGui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(240, 84)
	sizeConstraint.MaxSize = Vector2.new(340, 84)
	sizeConstraint.Parent = mainFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = mainFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 138, 168)
	stroke.Thickness = 1
	stroke.Transparency = 0.25
	stroke.Parent = mainFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = mainFrame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, -52, 0, 18)
	titleLabel.Position = UDim2.fromOffset(0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Objective"
	titleLabel.TextColor3 = Color3.fromRGB(174, 215, 255)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 13
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center
	titleLabel.Parent = mainFrame

	local stepLabel = Instance.new("TextLabel")
	stepLabel.Name = "StepLabel"
	stepLabel.Size = UDim2.fromOffset(48, 18)
	stepLabel.Position = UDim2.new(1, -48, 0, 0)
	stepLabel.BackgroundTransparency = 1
	stepLabel.Text = ""
	stepLabel.TextColor3 = Color3.fromRGB(206, 220, 232)
	stepLabel.Font = Enum.Font.GothamMedium
	stepLabel.TextSize = 12
	stepLabel.TextXAlignment = Enum.TextXAlignment.Right
	stepLabel.TextYAlignment = Enum.TextYAlignment.Center
	stepLabel.Parent = mainFrame

	local objectiveLabel = Instance.new("TextLabel")
	objectiveLabel.Name = "ObjectiveLabel"
	objectiveLabel.Size = UDim2.new(1, 0, 0, 40)
	objectiveLabel.Position = UDim2.fromOffset(0, 26)
	objectiveLabel.BackgroundTransparency = 1
	objectiveLabel.Text = ""
	objectiveLabel.TextColor3 = Color3.fromRGB(244, 248, 252)
	objectiveLabel.Font = Enum.Font.GothamBold
	objectiveLabel.TextSize = 16
	objectiveLabel.TextWrapped = true
	objectiveLabel.TextXAlignment = Enum.TextXAlignment.Left
	objectiveLabel.TextYAlignment = Enum.TextYAlignment.Top
	objectiveLabel.Parent = mainFrame

	ui.screenGui = screenGui
	ui.mainFrame = mainFrame
	ui.titleLabel = titleLabel
	ui.stepLabel = stepLabel
	ui.objectiveLabel = objectiveLabel
end

local function flashTracker()
	if not ui.mainFrame then
		return
	end

	if activeTween then
		activeTween:Cancel()
	end

	ui.mainFrame.BackgroundColor3 = PANEL_FLASH_COLOR
	activeTween = TweenService:Create(ui.mainFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = PANEL_COLOR,
	})
	activeTween:Play()
end

local function applyTutorialState(state)
	if type(state) ~= "table" or not ui.mainFrame then
		return
	end

	if state.completed == true then
		ui.mainFrame.Visible = false
		latestStep = state.currentStep
		return
	end

	local objective = state.objective
	if type(objective) ~= "string" or objective == "" then
		ui.mainFrame.Visible = false
		return
	end

	local currentStep = tonumber(state.currentStep) or 1
	local stepCount = tonumber(state.stepCount) or 1

	ui.objectiveLabel.Text = objective
	ui.stepLabel.Text = tostring(currentStep) .. "/" .. tostring(stepCount)
	ui.mainFrame.Visible = true

	if latestStep and latestStep ~= currentStep then
		flashTracker()
	end

	latestStep = currentStep
end

local function fetchTutorialState()
	for _ = 1, 8 do
		local success, state = pcall(function()
			return getTutorialStateRemote:InvokeServer()
		end)

		if success and type(state) == "table" then
			applyTutorialState(state)
			return
		end

		task.wait(0.5)
	end

	warn("[TutorialClient] Could not fetch tutorial state from server")
end

createTracker()

tutorialUpdatedRemote.OnClientEvent:Connect(function(state)
	applyTutorialState(state)
end)

task.spawn(fetchTutorialState)

print("[TutorialClient] Tutorial objective tracker initialized")
