local ProductionItems = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ProductionItems.Size = Vector3.new(0.5, 0.5, 0.5)

local ITEM_COLORS = {
    Log = Color3.fromRGB(124, 78, 43),
    Plank = Color3.fromRGB(190, 142, 84),
    Stone = Color3.fromRGB(122, 128, 132),
    StoneBlock = Color3.fromRGB(150, 154, 158),
    IronOre = Color3.fromRGB(82, 86, 92),
    IronIngot = Color3.fromRGB(170, 175, 182),
}

local ITEM_MAX_BOUNDS = {
    IronOre = Vector3.new(1.05, 0.75, 1.05),
    Plank = Vector3.new(1.35, 0.45, 1.35),
}

function ProductionItems.GetColor(itemName)
    return ITEM_COLORS[itemName] or Color3.fromRGB(235, 220, 120)
end

local function findTemplate(itemName)
    local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
    if not sharedFolder then
        return nil
    end

    local productionTemplates = sharedFolder:FindFirstChild("ProductionItemTemplates")
    if productionTemplates then
        local template = productionTemplates:FindFirstChild(itemName)
        if template then
            return template
        end
    end

    return nil
end

local function configureInstance(instance, itemName)
    instance.Name = "ProductionItem_" .. tostring(itemName)
    instance:SetAttribute("ItemName", itemName)
    instance:SetAttribute("IsProductionItem", true)

    if instance:IsA("BasePart") then
        instance.Anchored = true
        instance.CanCollide = false
        instance.CanQuery = false
        instance.CanTouch = false
        return
    end

    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanQuery = false
            descendant.CanTouch = false
        elseif descendant:IsA("Sound") or descendant:IsA("Script") or descendant:IsA("LocalScript") then
            descendant:Destroy()
        end
    end
end

local function hasVisiblePart(instance)
    if instance:IsA("BasePart") then
        return true
    end

    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return true
        end
    end

    return false
end

local function getInstanceSize(instance)
    if instance:IsA("BasePart") then
        return instance.Size
    end

    local _, size = instance:GetBoundingBox()
    return size
end

local function fitInstanceToMaxBounds(instance, itemName)
    local maxBounds = ITEM_MAX_BOUNDS[itemName]
    if not maxBounds then
        return
    end

    local size = getInstanceSize(instance)
    if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
        return
    end

    local scale = math.min(maxBounds.X / size.X, maxBounds.Y / size.Y, maxBounds.Z / size.Z, 1)
    if scale >= 1 then
        return
    end

    if instance:IsA("BasePart") then
        instance.Size *= scale
    else
        instance:ScaleTo(instance:GetScale() * scale)
    end
end

function ProductionItems.CreateInstance(itemName)
    local template = findTemplate(itemName)
    if template then
        local instance = template:Clone()
        configureInstance(instance, itemName)

        if hasVisiblePart(instance) then
            fitInstanceToMaxBounds(instance, itemName)
            return instance
        end

        warn("[ProductionItems] Template for " .. tostring(itemName) .. " has no BasePart after cleanup. Using fallback part.")
        instance:Destroy()
    end

    return ProductionItems.CreatePart(itemName)
end

function ProductionItems.CreatePart(itemName)
    local part = Instance.new("Part")
    part.Name = "ProductionItem_" .. tostring(itemName)
    part.Size = ProductionItems.Size
    part.Color = ProductionItems.GetColor(itemName)
    part.Material = Enum.Material.SmoothPlastic
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part:SetAttribute("ItemName", itemName)
    part:SetAttribute("IsProductionItem", true)

    return part
end

return ProductionItems
