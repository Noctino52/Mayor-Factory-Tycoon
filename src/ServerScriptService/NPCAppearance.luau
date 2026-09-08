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

local NPCAppearance = {}

local R6_LIMBS = {
	["Head"] = "Head",
	["Torso"] = "Torso",
	["Left Arm"] = "LeftArm",
	["Right Arm"] = "RightArm",
	["Left Leg"] = "LeftLeg",
	["Right Leg"] = "RightLeg",
}

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
	if not folder then
		return nil
	end

	local rig = folder:FindFirstChild("Rig")
	local wardrobe = folder:FindFirstChild(npcName)
	if not rig or not rig:IsA("Model") or not wardrobe then
		return nil
	end

	local model = rig:Clone()
	model.Name = npcName

	wear(model, wardrobe)

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
