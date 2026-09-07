--[[
	CharacterRig.luau

	Classic R6 figures built from native Roblox parts rather than imported
	meshes, so the people standing around a plot match the game's own art
	style and can be posed directly from code.

	This module knows about bodies: proportions, colours, the face, and how
	to stand one somewhere facing something. It knows nothing about what any
	particular character does for a living - the axe, the trowel and the
	hammer belong to whoever is animating them.
]]

local CharacterRig = {}

-- Classic R6 part sizes, in studs, before the per-character scale is applied
CharacterRig.R6 = {
	torso = Vector3.new(2, 2, 1),
	head = Vector3.new(2, 1, 1),
	limb = Vector3.new(1, 2, 1),
}

local R6 = CharacterRig.R6

CharacterRig.DefaultPalette = {
	skin = Color3.fromRGB(245, 205, 48),
	shirt = Color3.fromRGB(151, 44, 36),
	trousers = Color3.fromRGB(70, 60, 48),
}

function CharacterRig.NewPart(name, size, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--[[
	Builds a body: two legs, a torso, a left arm and a head with the stock
	Roblox face. The right arm is deliberately left out - it is the working
	arm, and whoever holds a tool poses it themselves.

	Each part carries an `Offset` attribute, its position relative to the
	figure's feet, which is all PoseBody needs to place it.
]]
function CharacterRig.Build(name, scale, palette)
	palette = palette or CharacterRig.DefaultPalette
	local skin = palette.skin or CharacterRig.DefaultPalette.skin
	local shirt = palette.shirt or CharacterRig.DefaultPalette.shirt
	local trousers = palette.trousers or CharacterRig.DefaultPalette.trousers

	local rig = Instance.new("Model")
	rig.Name = name

	local torso = R6.torso * scale
	local head = R6.head * scale
	local limb = R6.limb * scale

	local legY = limb.Y / 2
	local torsoY = limb.Y + torso.Y / 2
	local headY = limb.Y + torso.Y + head.Y / 2

	CharacterRig.NewPart("LeftLeg", limb, trousers, rig):SetAttribute("Offset", Vector3.new(-limb.X / 2, legY, 0))
	CharacterRig.NewPart("RightLeg", limb, trousers, rig):SetAttribute("Offset", Vector3.new(limb.X / 2, legY, 0))
	CharacterRig.NewPart("Torso", torso, shirt, rig):SetAttribute("Offset", Vector3.new(0, torsoY, 0))
	CharacterRig.NewPart("LeftArm", limb, shirt, rig)
		:SetAttribute("Offset", Vector3.new(-(torso.X + limb.X) / 2, torsoY, 0))

	local headPart = CharacterRig.NewPart("Head", head, skin, rig)
	headPart:SetAttribute("Offset", Vector3.new(0, headY, 0))
	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent = headPart

	-- The stock Roblox face, on the side the rig frame looks at
	local face = Instance.new("Decal")
	face.Name = "Face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = headPart

	if palette.hat then
		local hat = CharacterRig.NewPart("Hat", Vector3.new(2.2, 0.45, 2.2) * scale, palette.hat, rig)
		hat:SetAttribute("Offset", Vector3.new(0, headY + head.Y * 0.62, 0))
		if palette.hatBrim then
			CharacterRig.NewPart("HatBrim", Vector3.new(2.9, 0.16, 2.9) * scale, palette.hat, rig)
				:SetAttribute("Offset", Vector3.new(0, headY + head.Y * 0.42, 0))
		end
	end

	rig.PrimaryPart = rig:FindFirstChild("Torso")
	return rig
end

--[[
	The frame a figure stands in: at their feet, looking where they are going.

	Built with CFrame.lookAt so the frame follows Roblox's own convention,
	where LookVector is -Z. That is the same convention a Part's Front face
	uses, so the face decal lands on the side they actually look at without
	any guesswork about which way round the rig is.
]]
function CharacterRig.Frame(baseCFrame, standAt, lookDirection)
	local flat = Vector3.new(lookDirection.X, 0, lookDirection.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.zAxis
	end
	return baseCFrame * CFrame.lookAt(standAt, standAt + flat.Unit)
end

-- Where a shoulder sits in the rig's own frame, which is where any arm the
-- caller poses has to start from.
function CharacterRig.Shoulder(scale, side)
	local limbLength = R6.limb.Y * scale
	return Vector3.new(
		(R6.torso.X + R6.limb.X) / 2 * scale * (side or 1),
		(R6.limb.Y + R6.torso.Y / 2) * scale + limbLength / 2,
		0
	)
end

--[[
	Hangs an arm from its shoulder at the given angle: 0 is straight down,
	positive swings it forward and past vertical throws it in the air.

	Rotating about the shoulder rather than about the arm's own centre is the
	difference between a raised arm and an arm floating beside the ear.
]]
function CharacterRig.ArmCFrame(frame, scale, side, angle)
	local limbLength = R6.limb.Y * scale
	local shoulder = CharacterRig.Shoulder(scale, side)
	return frame
		* CFrame.new(shoulder)
		* CFrame.Angles(angle, 0, 0)
		* CFrame.new(0, -limbLength / 2, 0)
end

-- The point the hand ends up at, for hanging a tool off it
function CharacterRig.HandPoint(scale, side, angle)
	local limbLength = R6.limb.Y * scale
	local shoulder = CharacterRig.Shoulder(scale, side)
	return shoulder + (CFrame.Angles(angle, 0, 0) * CFrame.new(0, -limbLength, 0)).Position
end

--[[
	Places every part that declares an offset. `pose` may carry:
		stride   swings the legs and the free arm for a walk
		bounce   lifts the whole figure off the ground, which is all a jump
		         is at this size
		armRaise angle for the free arm, hung from the shoulder - used to
		         throw it in the air rather than let it swing
]]
function CharacterRig.PoseBody(rig, frame, pose)
	pose = pose or {}
	local stride = pose.stride or 0
	local lift = CFrame.new(0, pose.bounce or 0, 0)
	local scale = pose.scale

	for _, part in ipairs(rig:GetChildren()) do
		if part:IsA("BasePart") then
			local offset = part:GetAttribute("Offset")
			if offset then
				if part.Name == "LeftArm" and pose.armRaise and scale then
					part.CFrame = CharacterRig.ArmCFrame(frame * lift, scale, -1, pose.armRaise)
				else
					local lean = 0
					if part.Name == "LeftLeg" then
						lean = stride
					elseif part.Name == "RightLeg" then
						lean = -stride
					elseif part.Name == "LeftArm" then
						lean = -stride
					end
					part.CFrame = frame * lift * CFrame.new(offset) * CFrame.Angles(lean, 0, 0)
				end
			end
		end
	end
end

return CharacterRig
