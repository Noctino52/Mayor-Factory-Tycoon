--[[
	ShopClient.client.luau

	Client behavior for the base shop:
	- Click the Shop button to toggle
	- Shows every purchasable Definition item
	- Sends buy requests to the server and displays server-authored results
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local sharedFolder = ReplicatedStorage:WaitForChild("Shared")

local Definitions = require(sharedFolder:WaitForChild("Definitions"))
local ShopUI = require(StarterGui:WaitForChild("ShopUI"))

local buyItemRemote = ReplicatedStorage:WaitForChild("BuyItem")
local sellItemRemote = ReplicatedStorage:WaitForChild("SellItem")
local getMoneyRemote = ReplicatedStorage:WaitForChild("GetMoney")
local getInventoryRemote = ReplicatedStorage:WaitForChild("GetInventory")
local inventoryUpdatedRemote = ReplicatedStorage:WaitForChild("InventoryUpdated")
local shopTransactionResultRemote = ReplicatedStorage:WaitForChild("ShopTransactionResult")

local CATEGORY_ORDER = {
	machine = 1,
	transportation = 2,
	sell_zone = 3,
	decoration = 4,
}

local ui = ShopUI.Create(playerGui)
local isShopOpen = false
local currentMoney = 0
local purchasableItems = {}
local itemRows = {}
local pendingBuys = {}
local pendingSells = {}

local function getCategoryOrder(category)
	return CATEGORY_ORDER[category] or 99
end

local function setSellPending(itemName, pending)
	pendingSells[itemName] = pending

	local row = itemRows[itemName]
	if not row then
		return
	end

	row.sellButton.Active = not pending
	row.sellButton.AutoButtonColor = not pending
	row.sellButton.Text = pending and "..." or row.sellText
	row.sellButton.BackgroundColor3 = pending and Color3.fromRGB(90, 90, 90) or Color3.fromRGB(130, 74, 48)
end

local function setStatus(message, isError)
	ui.statusText.Text = message or ""
	ui.statusText.TextColor3 = isError and Color3.fromRGB(255, 130, 130) or Color3.fromRGB(160, 235, 170)

	if message and message ~= "" then
		local expected = message
		task.delay(2.5, function()
			if ui.statusText.Text == expected then
				ui.statusText.Text = ""
			end
		end)
	end
end

local function setBuyPending(itemName, pending)
	pendingBuys[itemName] = pending

	local row = itemRows[itemName]
	if not row then
		return
	end

	row.buyButton.Active = not pending
	row.buyButton.AutoButtonColor = not pending
	row.buyButton.Text = pending and "..." or "BUY"
	row.buyButton.BackgroundColor3 = pending and Color3.fromRGB(90, 90, 90) or Color3.fromRGB(48, 130, 74)
end

local function updateMoneyText()
	ui.moneyText.Text = "Money: " .. tostring(currentMoney)
end

local function refreshMoney()
	local success, money = pcall(function()
		return getMoneyRemote:InvokeServer()
	end)

	if success and type(money) == "number" then
		currentMoney = money
		updateMoneyText()
	end
end

local function refreshInventoryCounts()
	local success, inventory = pcall(function()
		return getInventoryRemote:InvokeServer()
	end)

	if not success or type(inventory) ~= "table" then
		return
	end

	local counts = {}
	for _, invItem in ipairs(inventory) do
		counts[invItem.itemName] = (counts[invItem.itemName] or 0) + (tonumber(invItem.count) or 0)
	end

	for itemName, row in pairs(itemRows) do
		row.ownedLabel.Text = "Owned: " .. tostring(counts[itemName] or 0)
	end
end

local function loadPurchasableItems()
	purchasableItems = {}

	for itemName, itemData in pairs(Definitions.GetAllItems()) do
		if itemData.cost and not itemData.isProduction and itemData.type ~= "sell_zone" then
			table.insert(purchasableItems, {
				name = itemName,
				icon = itemData.icon or "?",
				category = itemData.category or "misc",
				cost = itemData.cost,
			})
		end
	end

	table.sort(purchasableItems, function(a, b)
		local categoryA = getCategoryOrder(a.category)
		local categoryB = getCategoryOrder(b.category)
		if categoryA ~= categoryB then
			return categoryA < categoryB
		end

		if a.cost ~= b.cost then
			return a.cost < b.cost
		end

		return a.name < b.name
	end)
end

local function clearItemRows()
	for _, child in ipairs(ui.scrollFrame:GetChildren()) do
		if child:IsA("Frame") and child.Name:sub(1, 5) == "Item_" then
			child:Destroy()
		end
	end

	itemRows = {}
end

local function createTextLabel(parent, name, size, position, text, textSize, color, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextSize = textSize
	label.Font = font or Enum.Font.Gotham
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function createItemRow(item, layoutOrder)
	local card = Instance.new("Frame")
	card.Name = "Item_" .. item.name
	card.LayoutOrder = layoutOrder
	card.BackgroundColor3 = Color3.fromRGB(41, 49, 56)
	card.BorderSizePixel = 0
	card.Parent = ui.scrollFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(76, 92, 104)
	stroke.Thickness = 1
	stroke.Transparency = 0.15
	stroke.Parent = card

	createTextLabel(card, "Icon", UDim2.new(1, 0, 0, 42), UDim2.fromOffset(0, 8), item.icon, 28, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold)
	createTextLabel(card, "Name", UDim2.new(1, -14, 0, 28), UDim2.fromOffset(7, 48), item.name, 13, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold)
	createTextLabel(card, "Category", UDim2.new(1, -14, 0, 20), UDim2.fromOffset(7, 74), item.category, 11, Color3.fromRGB(175, 190, 202), Enum.Font.Gotham)
	createTextLabel(card, "Price", UDim2.new(1, -14, 0, 22), UDim2.fromOffset(7, 96), "$ " .. tostring(item.cost), 14, Color3.fromRGB(190, 246, 155), Enum.Font.GothamBold)

	local ownedLabel = createTextLabel(card, "Owned", UDim2.new(1, -14, 0, 18), UDim2.fromOffset(7, 116), "Owned: 0", 11, Color3.fromRGB(205, 213, 220), Enum.Font.Gotham)

	local buyButton = Instance.new("TextButton")
	buyButton.Name = "BuyButton"
	buyButton.Size = UDim2.new(0.48, -8, 0, 26)
	buyButton.Position = UDim2.new(0, 8, 1, -34)
	buyButton.BackgroundColor3 = Color3.fromRGB(48, 130, 74)
	buyButton.BorderSizePixel = 0
	buyButton.Text = "BUY"
	buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyButton.TextSize = 13
	buyButton.Font = Enum.Font.GothamBold
	buyButton.Parent = card

	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 5)
	buyCorner.Parent = buyButton

	local sellButton = Instance.new("TextButton")
	local sellText = "SELL $" .. tostring(math.floor(item.cost * 0.5))
	sellButton.Name = "SellButton"
	sellButton.Size = UDim2.new(0.48, -8, 0, 26)
	sellButton.Position = UDim2.new(0.52, 0, 1, -34)
	sellButton.BackgroundColor3 = Color3.fromRGB(130, 74, 48)
	sellButton.BorderSizePixel = 0
	sellButton.Text = sellText
	sellButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	sellButton.TextSize = 13
	sellButton.Font = Enum.Font.GothamBold
	sellButton.Parent = card

	local sellCorner = Instance.new("UICorner")
	sellCorner.CornerRadius = UDim.new(0, 5)
	sellCorner.Parent = sellButton

	itemRows[item.name] = {
		buyButton = buyButton,
		sellButton = sellButton,
		sellText = sellText,
		ownedLabel = ownedLabel,
	}

	buyButton.MouseButton1Click:Connect(function()
		if pendingBuys[item.name] then
			return
		end

		if currentMoney < item.cost then
			refreshMoney()
		end

		if currentMoney < item.cost then
			setStatus("Not enough money for " .. item.name .. ".", true)
			return
		end

		setBuyPending(item.name, true)
		buyItemRemote:FireServer(item.name)
	end)

	sellButton.MouseButton1Click:Connect(function()
		if pendingSells[item.name] then
			return
		end

		local ownedText = ownedLabel.Text
		local ownedCount = tonumber(ownedText:match("%d+")) or 0
		if ownedCount <= 0 then
			setStatus("You do not own " .. item.name .. ".", true)
			return
		end

		setSellPending(item.name, true)
		sellItemRemote:FireServer(item.name)
	end)
end

local function updateCanvasSize()
	local contentSize = ui.gridLayout.AbsoluteContentSize
	ui.scrollFrame.CanvasSize = UDim2.fromOffset(0, contentSize.Y + 24)
end

local function renderShopItems()
	clearItemRows()

	for index, item in ipairs(purchasableItems) do
		createItemRow(item, index)
	end

	updateCanvasSize()
end

local function openShop()
	if isShopOpen then
		return
	end

	isShopOpen = true
	ui.background.Visible = true
	setStatus("", false)
	refreshMoney()
	refreshInventoryCounts()
end

local function closeShop()
	if not isShopOpen then
		return
	end

	isShopOpen = false
	ui.background.Visible = false
	setStatus("", false)
end

local function toggleShop()
	if isShopOpen then
		closeShop()
	else
		openShop()
	end
end

shopTransactionResultRemote.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then
		return
	end

	if result.itemName then
		setBuyPending(result.itemName, false)
		setSellPending(result.itemName, false)
	end

	if type(result.money) == "number" then
		currentMoney = result.money
		updateMoneyText()
	else
		refreshMoney()
	end

	if result.success then
		setStatus(result.message or "Purchase complete.", false)
		refreshInventoryCounts()
	else
		setStatus(result.message or "Purchase failed.", true)
	end
end)

inventoryUpdatedRemote.OnClientEvent:Connect(function()
	refreshInventoryCounts()
	refreshMoney()
end)

ui.gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)
ui.openButton.MouseButton1Click:Connect(toggleShop)
ui.closeButton.MouseButton1Click:Connect(closeShop)

loadPurchasableItems()
renderShopItems()
refreshMoney()
refreshInventoryCounts()

print("[ShopClient] Base shop ready. Click the Shop button to open.")
