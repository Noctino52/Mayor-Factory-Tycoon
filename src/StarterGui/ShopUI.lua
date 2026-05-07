--[[
	ShopUI.lua

	Reusable client-side UI factory for the base shop.
	ShopClient.client.luau owns behavior; this module only builds instances.
]]

local ShopUI = {}

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

function ShopUI.Create(parent)
	local existing = parent:FindFirstChild("ShopScreenGui")
	if existing then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ShopScreenGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 100
	screenGui.Parent = parent

	local openButton = Instance.new("TextButton")
	openButton.Name = "OpenShopButton"
	openButton.Size = UDim2.fromOffset(112, 36)
	openButton.Position = UDim2.new(1, -128, 0, 18)
	openButton.BackgroundColor3 = Color3.fromRGB(38, 92, 122)
	openButton.BorderSizePixel = 0
	openButton.Text = "Shop"
	openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	openButton.TextSize = 16
	openButton.Font = Enum.Font.GothamBold
	openButton.Parent = screenGui
	addCorner(openButton, 6)

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	background.BackgroundTransparency = 0.42
	background.BorderSizePixel = 0
	background.Visible = false
	background.Parent = screenGui

	local window = Instance.new("Frame")
	window.Name = "ShopWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Size = UDim2.fromScale(0.62, 0.72)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.BackgroundColor3 = Color3.fromRGB(24, 29, 34)
	window.BorderSizePixel = 0
	window.Parent = background
	addCorner(window, 8)
	addStroke(window, Color3.fromRGB(89, 142, 174), 2, 0.2)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(380, 320)
	sizeConstraint.MaxSize = Vector2.new(760, 620)
	sizeConstraint.Parent = window

	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 52)
	titleBar.BackgroundColor3 = Color3.fromRGB(16, 19, 23)
	titleBar.BorderSizePixel = 0
	titleBar.Parent = window

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -110, 1, 0)
	title.Position = UDim2.fromOffset(16, 0)
	title.BackgroundTransparency = 1
	title.Text = "Base Shop"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 22
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = titleBar

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.fromOffset(36, 36)
	closeButton.Position = UDim2.new(1, -46, 0, 8)
	closeButton.BackgroundColor3 = Color3.fromRGB(150, 58, 58)
	closeButton.BorderSizePixel = 0
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.TextSize = 16
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Parent = titleBar
	addCorner(closeButton, 6)

	local moneyText = Instance.new("TextLabel")
	moneyText.Name = "MoneyText"
	moneyText.Size = UDim2.new(0, 190, 0, 28)
	moneyText.Position = UDim2.new(1, -250, 0, 12)
	moneyText.BackgroundTransparency = 1
	moneyText.Text = "Money: 0"
	moneyText.TextColor3 = Color3.fromRGB(190, 246, 155)
	moneyText.TextSize = 15
	moneyText.Font = Enum.Font.GothamBold
	moneyText.TextXAlignment = Enum.TextXAlignment.Right
	moneyText.Parent = titleBar

	local statusText = Instance.new("TextLabel")
	statusText.Name = "StatusText"
	statusText.Size = UDim2.new(1, -32, 0, 28)
	statusText.Position = UDim2.fromOffset(16, 56)
	statusText.BackgroundTransparency = 1
	statusText.Text = ""
	statusText.TextColor3 = Color3.fromRGB(255, 255, 255)
	statusText.TextSize = 14
	statusText.Font = Enum.Font.Gotham
	statusText.TextXAlignment = Enum.TextXAlignment.Left
	statusText.Parent = window

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "Items"
	scrollFrame.Size = UDim2.new(1, -32, 1, -100)
	scrollFrame.Position = UDim2.fromOffset(16, 88)
	scrollFrame.BackgroundColor3 = Color3.fromRGB(30, 36, 42)
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 8
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(89, 142, 174)
	scrollFrame.CanvasSize = UDim2.fromOffset(0, 0)
	scrollFrame.Parent = window
	addCorner(scrollFrame, 6)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = scrollFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.Name = "GridLayout"
	gridLayout.CellSize = UDim2.fromOffset(142, 154)
	gridLayout.CellPadding = UDim2.fromOffset(10, 10)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = scrollFrame

	return {
		screenGui = screenGui,
		openButton = openButton,
		background = background,
		window = window,
		scrollFrame = scrollFrame,
		gridLayout = gridLayout,
		moneyText = moneyText,
		statusText = statusText,
		closeButton = closeButton,
	}
end

return ShopUI
