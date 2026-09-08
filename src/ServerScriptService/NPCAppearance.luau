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
