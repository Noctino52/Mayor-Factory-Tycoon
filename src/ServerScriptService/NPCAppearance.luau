--[[
	NPCAppearance.luau

	Dresses a trader as a real Roblox avatar rather than a stack of coloured
	parts: shirt and trousers from clothing assets, and hats, beards and hair
	from catalogue accessories.

	None of it is hard-coded. Everything comes out of

		ReplicatedStorage/Shared/NPCAppearance/

	which holds one `Rig` - a standard R6 rig, the thing Studio's rig builder
	makes - and one folder per NPC with whatever that NPC wears dropped into
	it. A Shirt, a Pants and any number of Accessory objects, straight from
	the toolbox. Nothing needs an asset id written down anywhere, and nothing
	has to be loaded at runtime.

	If the folder is not there, or an NPC has nothing in it, the caller falls
	back to the built-from-parts figure. That is deliberate: the game has to
	keep working while the wardrobe is still being filled.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Definitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Definitions"))

local NPCAppearance = {}

local R6_LIMBS = {
	["Head"] = "Head",
	["Torso"] = "Torso",
	["Left Arm"] = "LeftArm",
	["Right Arm"] = "RightArm",
	["Left Leg"] = "LeftLeg",
	["Right Leg"] = "RightLeg",
}

--[[
	A standard R6 character, built here rather than cloned from a rig someone
	has to make in Studio first. Nothing about a block rig is secret: six
	parts at known sizes with the names clothing looks for, a Humanoid, and
	the attachment points accessories hang from.

	The attachment names and positions are Roblox's own. Humanoid:AddAccessory
	matches an accessory's attachment against these by name, so a hat sits on
	HatAttachment and a beard on FaceFrontAttachment without being told.
]]
local R6_PARTS = {
	{ name = "Head", size = Vector3.new(2, 1, 1), y = 4.5 },
	{ name = "Torso", size = Vector3.new(2, 2, 1), y = 3 },
	{ name = "Left Arm", size = Vector3.new(1, 2, 1), y = 3, x = -1.5 },
	{ name = "Right Arm", size = Vector3.new(1, 2, 1), y = 3, x = 1.5 },
	{ name = "Left Leg", size = Vector3.new(1, 2, 1), y = 1, x = -0.5 },
	{ name = "Right Leg", size = Vector3.new(1, 2, 1), y = 1, x = 0.5 },
}

local HEAD_ATTACHMENTS = {
	HatAttachment = Vector3.new(0, 0.5, 0),
	HairAttachment = Vector3.new(0, 0.5, 0),
	FaceFrontAttachment = Vector3.new(0, 0, -0.5),
	FaceCenterAttachment = Vector3.new(0, 0, 0),
}

local TORSO_ATTACHMENTS = {
	NeckAttachment = Vector3.new(0, 1, 0),
	BodyFrontAttachment = Vector3.new(0, 0, -0.5),
	BodyBackAttachment = Vector3.new(0, 0, 0.5),
	LeftCollarAttachment = Vector3.new(-1, 1, 0),
	RightCollarAttachment = Vector3.new(1, 1, 0),
	WaistCenterAttachment = Vector3.new(0, -1, 0),
	WaistFrontAttachment = Vector3.new(0, -1, -0.5),
	WaistBackAttachment = Vector3.new(0, -1, 0.5),
}

local function addAttachments(part, points)
	for name, position in pairs(points) do
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.Position = position
		attachment.Parent = part
	end
end

function NPCAppearance.BuildRig(name)
	local model = Instance.new("Model")
	model.Name = name or "Rig"

	for _, spec in ipairs(R6_PARTS) do
		local part = Instance.new("Part")
		part.Name = spec.name
		part.Size = spec.size
		part.Position = Vector3.new(spec.x or 0, spec.y, 0)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model

		if spec.name == "Head" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Head
			mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
			mesh.Parent = part

			local face = Instance.new("Decal")
			face.Name = "face"
			face.Texture = "rbxasset://textures/face.png"
			face.Face = Enum.NormalId.Front
			face.Parent = part

			addAttachments(part, HEAD_ATTACHMENTS)
		elseif spec.name == "Torso" then
			addAttachments(part, TORSO_ATTACHMENTS)
		end
	end

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Position = Vector3.new(0, 3, 0)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = model

	model.PrimaryPart = root
	return model
end

--[[
	A trader modelled whole, in Blender, and imported as one model.

	The figure arrives split into the six R6 groups - Head, Torso, ArmL,
	ArmR, LegL, LegR - each of which is a handful of MeshParts, one per
	material. Everything a group carries moves with it: the hat and beard are
	Head, the apron and belt are Torso, a boot is its leg.

	Nothing about where the pieces sit has to be worked out here. They come
	in at the positions they were modelled at, which is the whole point of
	importing the figure whole rather than hanging accessories on a rig and
	guessing at the offsets.
]]
--[[
	The colours Studio's importer throws away. Every part comes in named
	<Npc><Group>_<Material>, so the material is the last word of the name and
	nothing has to be listed part by part.
]]
local TRADER_MATERIALS = {
	SkinLight = { color = Color3.fromRGB(238, 196, 160), material = Enum.Material.SmoothPlastic },
	SkinTan = { color = Color3.fromRGB(222, 172, 128), material = Enum.Material.SmoothPlastic },
	Plaid = { color = Color3.fromRGB(150, 58, 48), material = Enum.Material.Fabric },
	PlaidDark = { color = Color3.fromRGB(96, 32, 26), material = Enum.Material.Fabric },
	HiVis = { color = Color3.fromRGB(232, 182, 44), material = Enum.Material.SmoothPlastic },
	HiVisDeep = { color = Color3.fromRGB(198, 148, 22), material = Enum.Material.SmoothPlastic },
	Reflect = { color = Color3.fromRGB(238, 240, 236), material = Enum.Material.SmoothPlastic },
	WorkNavy = { color = Color3.fromRGB(46, 54, 72), material = Enum.Material.Fabric },
	Denim = { color = Color3.fromRGB(52, 72, 116), material = Enum.Material.Fabric },
	Linen = { color = Color3.fromRGB(238, 236, 228), material = Enum.Material.Fabric },
	Leather = { color = Color3.fromRGB(96, 62, 38), material = Enum.Material.SmoothPlastic },
	LeatherDark = { color = Color3.fromRGB(52, 38, 26), material = Enum.Material.SmoothPlastic },
	ApronGrey = { color = Color3.fromRGB(74, 56, 40), material = Enum.Material.SmoothPlastic },
	Boot = { color = Color3.fromRGB(58, 40, 28), material = Enum.Material.SmoothPlastic },
	Brass = { color = Color3.fromRGB(198, 158, 74), material = Enum.Material.Metal },
	HairDark = { color = Color3.fromRGB(72, 46, 30), material = Enum.Material.SmoothPlastic },
	HairBlack = { color = Color3.fromRGB(28, 26, 28), material = Enum.Material.SmoothPlastic },
	HairFair = { color = Color3.fromRGB(214, 178, 96), material = Enum.Material.SmoothPlastic },
	RuleRed = { color = Color3.fromRGB(176, 44, 40), material = Enum.Material.SmoothPlastic },
}

local GROUP_LIMBS = {
	Head = "Head",
	Torso = "Torso",
	ArmL = "LeftArm",
	ArmR = "RightArm",
	LegL = "LeftLeg",
	LegR = "RightLeg",
}

-- The joint each group swings from, in studs from the feet at R6 scale 1
local GROUP_PIVOTS = {
	ArmL = Vector3.new(-1.5, 4, 0),
	ArmR = Vector3.new(1.5, 4, 0),
	LegL = Vector3.new(-0.5, 2, 0),
	LegR = Vector3.new(0.5, 2, 0),
}

local function groupOf(partName, npcName)
	-- Longest first, so ArmL is not read as Arm
	for _, group in ipairs({ "ArmL", "ArmR", "LegL", "LegR", "Head", "Torso" }) do
		if string.find(partName, npcName .. group, 1, true) == 1 then
			return group
		end
	end
	return nil
end

function NPCAppearance.BuildFromModel(npcName, scale)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local folder = shared and shared:FindFirstChild("TraderModels")
	local source = folder and folder:FindFirstChild(npcName)
	if not source or not source:IsA("Model") then
		return nil
	end

	local model = source:Clone()
	model.Name = npcName

	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end

	local bounds, size = model:GetBoundingBox()
	local feetY = bounds.Position.Y - size.Y / 2
	local tagged = 0

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false

			local suffix = string.match(part.Name, "_(%w+)$")
			local style = suffix and TRADER_MATERIALS[suffix]
			if style then
				part.Color = style.color
				part.Material = style.material
			end

			local group = groupOf(part.Name, npcName)
			if group then
				--[[
					Turned to face the way the figure is posed.

					The models are built with their front at Blender's -Y,
					which the exporter lands on +Z here, while a posing frame
					looks down -Z like everything else in the engine. Half a
					turn about the vertical squares the two up: the offsets
					are mirrored through the centre line, and the parts carry
					the same turn so their geometry follows.
				]]
				part:SetAttribute("Limb", GROUP_LIMBS[group])
				part:SetAttribute("Offset", Vector3.new(
					-(part.Position.X - bounds.Position.X),
					part.Position.Y - feetY,
					-(part.Position.Z - bounds.Position.Z)
				))
				part:SetAttribute("Tilt", Vector3.new(0, math.pi, 0))

				-- The joints mirror with everything else
				local pivot = GROUP_PIVOTS[group]
				if pivot then
					part:SetAttribute("Pivot", Vector3.new(-pivot.X, pivot.Y, -pivot.Z) * (scale or 1))
				end
				tagged += 1
			end
		end
	end

	if tagged == 0 then
		warn("[NPCAppearance] " .. npcName .. " model has no parts named " .. npcName .. "<Group>_")
		model:Destroy()
		return nil
	end

	model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	return model
end

local function appearanceFolder()
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	return shared and shared:FindFirstChild("NPCAppearance")
end

-- The rig everyone is cut from: a plain R6 character, with the part names,
-- attachment points and joints that clothing and accessories expect.
function NPCAppearance.HasRig()
	local folder = appearanceFolder()
	local rig = folder and folder:FindFirstChild("Rig")
	return rig ~= nil and rig:IsA("Model")
end

--[[
	Stands the rig still. These figures are posed a frame at a time from
	code, so the humanoid must not try to walk, fall or ragdoll them: the
	parts are anchored and the state machine is turned off.
]]
local function quieten(model)
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		pcall(function()
			humanoid.EvaluateStateMachine = false
		end)
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			-- The accessories hang off the body on welds, so they have to
			-- stay free to follow it; everything else is placed by hand.
			local isAccessoryPart = descendant:FindFirstAncestorWhichIsA("Accessory") ~= nil
			descendant.Anchored = not isAccessoryPart
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

--[[
	Records what each part is and where it rests, which is all the poser
	needs. `Limb` says which of the six it is, and `Offset` is its position
	relative to the figure's feet - measured off the rig rather than assumed,
	so a rig built at any size still poses correctly.
]]
local function tagParts(model)
	local bounds, size = model:GetBoundingBox()
	local feetY = bounds.Position.Y - size.Y / 2

	local torsoOffset = nil

	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") then
			local limb = R6_LIMBS[part.Name]
			if limb then
				local offset = Vector3.new(
					part.Position.X - bounds.Position.X,
					part.Position.Y - feetY,
					part.Position.Z - bounds.Position.Z
				)
				part:SetAttribute("Limb", limb)
				part:SetAttribute("Offset", offset)
				if limb == "Torso" then
					torsoOffset = offset
				end
			end
		end
	end

	-- The root rides with the torso. It is invisible, but an anchored part
	-- left behind at the origin is still a part left behind at the origin.
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and torsoOffset then
		root:SetAttribute("Limb", "Root")
		root:SetAttribute("Offset", torsoOffset)
	end
end

-- Clothing the game owns, by asset id. Everything else an NPC wears comes
-- out of the wardrobe folder, but a shirt and a pair of trousers are just
-- two numbers and belong with the rest of the NPC's definition.
local function dressFromDefinition(model, npcName)
	local npc = Definitions.GetNPC(npcName)
	local appearance = npc and npc.appearance
	if not appearance then
		return false
	end

	local dressed = false

	if (tonumber(appearance.shirt) or 0) > 0 then
		local shirt = Instance.new("Shirt")
		shirt.ShirtTemplate = "rbxassetid://" .. tostring(appearance.shirt)
		shirt.Parent = model
		dressed = true
	end

	if (tonumber(appearance.pants) or 0) > 0 then
		local pants = Instance.new("Pants")
		pants.PantsTemplate = "rbxassetid://" .. tostring(appearance.pants)
		pants.Parent = model
		dressed = true
	end

	return dressed
end

--[[
	The modelled accessories: a hat, hair, a beard. Each is one model saved
	from Blender, and it goes on the head whole.

	Saved as an .rbxm rather than uploaded as meshes on purpose. An .rbxm
	keeps every part exactly where it was modelled; an uploaded mesh does
	not - Roblox recentres it on its own bounding box, and the position it
	was drawn at is gone before the game ever sees it.
]]
local ACCESSORY_COLOURS = {
	HiVis = { color = Color3.fromRGB(232, 182, 44), material = Enum.Material.SmoothPlastic },
	HiVisDeep = { color = Color3.fromRGB(198, 148, 22), material = Enum.Material.SmoothPlastic },
	HairDark = { color = Color3.fromRGB(72, 46, 30), material = Enum.Material.SmoothPlastic },
	HairBlack = { color = Color3.fromRGB(28, 26, 28), material = Enum.Material.SmoothPlastic },
	HairFair = { color = Color3.fromRGB(214, 178, 96), material = Enum.Material.SmoothPlastic },
	ClothDark = { color = Color3.fromRGB(78, 82, 84), material = Enum.Material.Fabric },
	Leather = { color = Color3.fromRGB(96, 62, 38), material = Enum.Material.SmoothPlastic },
}

--[[
	Hangs one accessory on the head. The pieces are modelled around the head's
	centre, so they need placing there and nowhere else - the whole reason for
	keeping them in a model rather than as loose meshes.
]]
function NPCAppearance.AddAccessory(model, accessoryName, scale)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local folder = shared and shared:FindFirstChild("Accessories")
	local source = folder and folder:FindFirstChild(accessoryName)
	if not source then
		return false
	end

	local head = nil
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and (part:GetAttribute("Limb") or part.Name) == "Head" then
			head = part
			break
		end
	end

	if not head then
		return false
	end

	local headOffset = head:GetAttribute("Offset")
	local worn = source:Clone()
	worn.Name = accessoryName

	for _, part in ipairs(worn:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false

			local suffix = string.match(part.Name, "^[%w_]-_(%a+)_")
			local style = suffix and ACCESSORY_COLOURS[suffix]
			if style then
				part.Color = style.color
				part.Material = style.material
			end

			-- Modelled around the head's centre, so its own position is the
			-- offset from the head, and the head's offset puts it on the body
			part:SetAttribute("Offset", headOffset + part.Position * scale)

			-- The piece keeps the angle it was modelled at - a cap peak, a
			-- plait - with the figure's half turn composed onto it, or the
			-- poser would stand every one of them upright.
			local turned = CFrame.Angles(0, math.pi, 0) * (part.CFrame - part.CFrame.Position)
			local rx, ry, rz = turned:ToEulerAnglesXYZ()
			part:SetAttribute("Tilt", Vector3.new(rx, ry, rz))
			part.Size = part.Size * scale
			part.Parent = model
		end
	end

	worn:Destroy()
	return true
end

local function wear(model, wardrobe)
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")

	for _, item in ipairs(wardrobe:GetChildren()) do
		local worn = item:Clone()

		if worn:IsA("Accessory") then
			if humanoid then
				humanoid:AddAccessory(worn)
			else
				worn:Destroy()
			end
		elseif worn:IsA("Shirt") or worn:IsA("Pants") or worn:IsA("ShirtGraphic") or worn:IsA("BodyColors") then
			worn.Parent = model
		elseif worn:IsA("Decal") and worn.Name == "face" then
			local head = model:FindFirstChild("Head")
			if head then
				local existing = head:FindFirstChild("face")
				if existing then
					existing:Destroy()
				end
				worn.Parent = head
			end
		else
			worn:Destroy()
		end
	end
end

--[[
	Builds one dressed trader, or nil if there is nothing to dress them in.
	The caller keeps its own fallback: this module never returns a half
	assembled figure.
]]
function NPCAppearance.Build(npcName, scale)
	local folder = appearanceFolder()

	local wardrobe = folder and folder:FindFirstChild(npcName)
	local npc = Definitions.GetNPC(npcName)
	local appearance = npc and npc.appearance
	local hasClothing = appearance
		and ((tonumber(appearance.shirt) or 0) > 0 or (tonumber(appearance.pants) or 0) > 0)
	local hasWardrobe = wardrobe and #wardrobe:GetChildren() > 0

	if not hasClothing and not hasWardrobe then
		return nil
	end

	-- A rig dropped in the folder wins, for anyone who wants to hand-build
	-- one; otherwise the standard R6 body is built here.
	local rig = folder and folder:FindFirstChild("Rig")
	local model = (rig and rig:IsA("Model")) and rig:Clone() or NPCAppearance.BuildRig(npcName)
	model.Name = npcName

	dressFromDefinition(model, npcName)
	if wardrobe then
		wear(model, wardrobe)
	end

	-- Scaled before anything is measured: a rig comes out of Studio at full
	-- R6 size, and these people stand in a diorama. ScaleTo carries the
	-- accessories and their attachment points down with it.
	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end

	quieten(model)
	tagParts(model)

	if not model:FindFirstChild("Torso") then
		warn("[NPCAppearance] " .. npcName .. " rig has no Torso; expected a standard R6 rig")
		model:Destroy()
		return nil
	end

	model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
	return model
end

-- How tall the built figure stands, so whoever places it can sit the world
-- around it at the right height
function NPCAppearance.Height(model)
	local _, size = model:GetBoundingBox()
	return size.Y
end

return NPCAppearance
