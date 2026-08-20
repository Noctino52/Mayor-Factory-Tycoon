local ProductionItems = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ProductionItems.Size = Vector3.new(0.5, 0.5, 0.5)

local ITEM_COLORS = {
    Log = Color3.fromRGB(124, 78, 43),
    Plank = Color3.fromRGB(190, 142, 84),
    Beam = Color3.fromRGB(150, 102, 52),
    Crate = Color3.fromRGB(174, 116, 58),
    Stone = Color3.fromRGB(122, 128, 132),
    StoneBlock = Color3.fromRGB(150, 154, 158),
    IronOre = Color3.fromRGB(82, 86, 92),
    IronIngot = Color3.fromRGB(170, 175, 182),
}

local ITEM_MAX_BOUNDS = {
    IronOre = Vector3.new(1.05, 0.75, 1.05),
    Plank = Vector3.new(1.35, 0.45, 1.35),
    Beam = Vector3.new(1.5, 0.45, 0.65),
    Crate = Vector3.new(1.15, 1.0, 1.15),
    Stone = Vector3.new(0.85, 0.65, 0.85),
    StoneBlock = Vector3.new(0.9, 0.75, 0.9),
    IronIngot = Vector3.new(1.1, 0.45, 0.55),
}

local ITEM_VISUAL_SCALE = {
    Beam = 3,
}

local ITEM_FALLBACK_SIZES = {
    Beam = Vector3.new(4.5, 1.35, 1.95),
    Crate = Vector3.new(1.0, 0.9, 1.0),
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

local function applyVisualScale(instance, itemName)
    local scale = ITEM_VISUAL_SCALE[itemName]
    if not scale or scale == 1 then
        return
    end

    if instance:IsA("BasePart") then
        local cframe = instance.CFrame
        instance.Size *= scale
        instance.CFrame = cframe
    else
        local pivot = instance:GetPivot()
        instance:ScaleTo(instance:GetScale() * scale)
        instance:PivotTo(pivot)
    end
end

local function createCrateInstance()
    local crate = Instance.new("Model")

    local body = Instance.new("Part")
    body.Name = "CrateBody"
    body.Size = Vector3.new(1.0, 0.85, 1.0)
    body.CFrame = CFrame.new(0, 0, 0)
    body.Material = Enum.Material.WoodPlanks
    body.Color = ProductionItems.GetColor("Crate")
    body.Parent = crate

    local bandColor = Color3.fromRGB(92, 58, 32)
    local bandSpecs = {
        { name = "BandX", size = Vector3.new(1.08, 0.12, 0.12), cframe = CFrame.new(0, 0.16, -0.35) },
        { name = "BandX2", size = Vector3.new(1.08, 0.12, 0.12), cframe = CFrame.new(0, 0.16, 0.35) },
        { name = "BandZ", size = Vector3.new(0.12, 0.12, 1.08), cframe = CFrame.new(-0.35, -0.16, 0) },
        { name = "BandZ2", size = Vector3.new(0.12, 0.12, 1.08), cframe = CFrame.new(0.35, -0.16, 0) },
    }

    for _, spec in ipairs(bandSpecs) do
        local band = Instance.new("Part")
        band.Name = spec.name
        band.Size = spec.size
        band.CFrame = spec.cframe
        band.Material = Enum.Material.WoodPlanks
        band.Color = bandColor
        band.Parent = crate
    end

    crate.PrimaryPart = body
    configureInstance(crate, "Crate")
    return crate
end

function ProductionItems.CreateInstance(itemName)
    local template = findTemplate(itemName)
    if template then
        local instance = template:Clone()
        configureInstance(instance, itemName)

        if hasVisiblePart(instance) then
            fitInstanceToMaxBounds(instance, itemName)
            applyVisualScale(instance, itemName)
            return instance
        end

        warn("[ProductionItems] Template for " .. tostring(itemName) .. " has no BasePart after cleanup. Using fallback part.")
        instance:Destroy()
    end

    if itemName == "Crate" then
        return createCrateInstance()
    end

    return ProductionItems.CreatePart(itemName)
end

function ProductionItems.CreatePart(itemName)
    local part = Instance.new("Part")
    part.Name = "ProductionItem_" .. tostring(itemName)
    part.Size = ITEM_FALLBACK_SIZES[itemName] or ProductionItems.Size
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
