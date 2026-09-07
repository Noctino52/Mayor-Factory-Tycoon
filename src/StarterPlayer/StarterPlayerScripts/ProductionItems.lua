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
    Brick = Color3.fromRGB(178, 90, 62),
    IronOre = Color3.fromRGB(82, 86, 92),
    IronIngot = Color3.fromRGB(170, 175, 182),
}

local ITEM_MAX_BOUNDS = {
    IronOre = Vector3.new(1.05, 0.75, 1.05),
    Plank = Vector3.new(2.0, 0.3, 0.75),
    Beam = Vector3.new(1.5, 0.45, 0.65),
    Crate = Vector3.new(1.15, 1.0, 1.15),
    Stone = Vector3.new(0.85, 0.65, 0.85),
    StoneBlock = Vector3.new(0.9, 0.75, 0.9),
    Brick = Vector3.new(1.15, 0.55, 0.6),
    IronIngot = Vector3.new(1.1, 0.45, 0.55),
}

local ITEM_VISUAL_SCALE = {
    Beam = 3,
}

local ITEM_FALLBACK_SIZES = {
    Beam = Vector3.new(4.5, 1.35, 1.95),
    Plank = Vector3.new(2.0, 0.26, 0.7),
    Crate = Vector3.new(1.0, 0.9, 1.0),
    Brick = Vector3.new(1.1, 0.5, 0.55),
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

local function createLogInstance()
    local size = Vector3.new(2.2, 0.9, 0.9)
    local log = Instance.new("Model")

    local body = Instance.new("Part")
    body.Name = "LogBody"
    body.Shape = Enum.PartType.Cylinder
    body.Size = size
    body.CFrame = CFrame.new(0, 0, 0)
    body.Material = Enum.Material.Wood
    body.Color = ProductionItems.GetColor("Log")
    body.Parent = log

    -- Pale sawn faces at both ends, so it reads as cut timber
    for index, offsetX in ipairs({ -size.X / 2 + 0.03, size.X / 2 - 0.03 }) do
        local face = Instance.new("Part")
        face.Name = "LogFace" .. index
        face.Shape = Enum.PartType.Cylinder
        face.Size = Vector3.new(0.06, size.Y * 0.94, size.Z * 0.94)
        face.CFrame = CFrame.new(offsetX, 0, 0)
        face.Material = Enum.Material.Wood
        face.Color = Color3.fromRGB(197, 156, 106)
        face.Parent = log
    end

    -- A couple of darker bark bands to break up the barrel
    for index, offsetX in ipairs({ -0.45, 0.45 }) do
        local band = Instance.new("Part")
        band.Name = "LogBand" .. index
        band.Shape = Enum.PartType.Cylinder
        band.Size = Vector3.new(0.16, size.Y * 1.02, size.Z * 1.02)
        band.CFrame = CFrame.new(offsetX, 0, 0)
        band.Material = Enum.Material.Wood
        band.Color = Color3.fromRGB(92, 58, 32)
        band.Parent = log
    end

    log.PrimaryPart = body
    configureInstance(log, "Log")
    return log
end

local function createPlankInstance()
    local size = Vector3.new(2.0, 0.26, 0.7)
    local plank = Instance.new("Model")

    local body = Instance.new("Part")
    body.Name = "PlankBody"
    body.Size = size
    body.CFrame = CFrame.new(0, 0, 0)
    body.Material = Enum.Material.WoodPlanks
    body.Color = ProductionItems.GetColor("Plank")
    body.Parent = plank

    -- Rough sawn ends, a shade darker than the planed faces
    for index, offsetX in ipairs({ -size.X / 2 + 0.02, size.X / 2 - 0.02 }) do
        local endGrain = Instance.new("Part")
        endGrain.Name = "PlankEnd" .. index
        endGrain.Size = Vector3.new(0.04, size.Y * 1.01, size.Z * 1.01)
        endGrain.CFrame = CFrame.new(offsetX, 0, 0)
        endGrain.Material = Enum.Material.Wood
        endGrain.Color = Color3.fromRGB(156, 112, 62)
        endGrain.Parent = plank
    end

    -- Two grain lines down the face, so it reads as a board and not a slab
    for index, offsetZ in ipairs({ -0.18, 0.16 }) do
        local grain = Instance.new("Part")
        grain.Name = "PlankGrain" .. index
        grain.Size = Vector3.new(size.X * 0.9, 0.02, 0.06)
        grain.CFrame = CFrame.new(0, size.Y / 2 - 0.005, offsetZ)
        grain.Material = Enum.Material.Wood
        grain.Color = Color3.fromRGB(163, 118, 68)
        grain.Parent = plank
    end

    plank.PrimaryPart = body
    configureInstance(plank, "Plank")
    return plank
end

-- Items whose look lives here in code rather than in an imported model.
-- Checked before the template folder: a template left behind in the place
-- file would otherwise quietly shadow the code and nothing would change.
local PROCEDURAL_ITEMS = {
    Log = createLogInstance,
    Plank = createPlankInstance,
}

local function createBrickInstance()
    local brick = Instance.new("Model")

    local body = Instance.new("Part")
    body.Name = "BrickBody"
    body.Size = Vector3.new(1.1, 0.5, 0.55)
    body.CFrame = CFrame.new(0, 0, 0)
    body.Material = Enum.Material.Brick
    body.Color = ProductionItems.GetColor("Brick")
    body.Parent = brick

    local grooveColor = Color3.fromRGB(120, 60, 40)
    local grooveSpecs = {
        { name = "GrooveTop", size = Vector3.new(1.12, 0.05, 0.08), cframe = CFrame.new(0, 0.23, 0) },
        { name = "GrooveSideA", size = Vector3.new(0.08, 0.52, 0.57), cframe = CFrame.new(-0.28, 0, 0) },
        { name = "GrooveSideB", size = Vector3.new(0.08, 0.52, 0.57), cframe = CFrame.new(0.28, 0, 0) },
    }

    for _, spec in ipairs(grooveSpecs) do
        local groove = Instance.new("Part")
        groove.Name = spec.name
        groove.Size = spec.size
        groove.CFrame = spec.cframe
        groove.Material = Enum.Material.Brick
        groove.Color = grooveColor
        groove.Parent = brick
    end

    brick.PrimaryPart = body
    configureInstance(brick, "Brick")
    return brick
end

function ProductionItems.CreateInstance(itemName)
    local builder = PROCEDURAL_ITEMS[itemName]
    if builder then
        return builder()
    end

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
    elseif itemName == "Brick" then
        return createBrickInstance()
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
