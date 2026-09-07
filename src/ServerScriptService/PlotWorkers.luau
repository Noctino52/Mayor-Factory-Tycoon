--[[
	PlotWorkers.luau

	Builds and animates the little workers that make a machine look alive.

	Right now that is the TreeFarm lumberjack: he walks the plantation road,
	fells a tree, carries the log to the pile and drops it off, in time with
	the machine's own production cycle. The felled tree fades back in a few
	cycles later, so the rows keep rotating.

	The worker is made from native Roblox parts at classic R6 proportions
	(scaled down to diorama size) rather than an imported mesh, so he matches
	the game's own art style and can be posed directly from code.

	Everything here is cosmetic. Production is still driven entirely by
	MachineSystem; if this module does nothing, the machine still works.
]]

local PlotWorkers = {}

-- Classic R6 part sizes, in studs, before the per-machine scale is applied
local R6 = {
	torso = Vector3.new(2, 2, 1),
	head = Vector3.new(2, 1, 1),
	limb = Vector3.new(1, 2, 1),
}

local SKIN = Color3.fromRGB(245, 205, 48)
local SHIRT = Color3.fromRGB(151, 44, 36)
local TROUSERS = Color3.fromRGB(70, 60, 48)
local AXE_HANDLE = Color3.fromRGB(120, 78, 44)
local AXE_HEAD = Color3.fromRGB(160, 165, 170)

local function newPart(name, size, color, parent)
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

-- Local offsets of each body part relative to the worker's feet
local function buildRig(scale)
	local rig = Instance.new("Model")
	rig.Name = "Lumberjack"

	local torso = R6.torso * scale
	local head = R6.head * scale
	local limb = R6.limb * scale

	local legY = limb.Y / 2
	local torsoY = limb.Y + torso.Y / 2
	local headY = limb.Y + torso.Y + head.Y / 2

	newPart("LeftLeg", limb, TROUSERS, rig):SetAttribute("Offset", Vector3.new(-limb.X / 2, legY, 0))
	newPart("RightLeg", limb, TROUSERS, rig):SetAttribute("Offset", Vector3.new(limb.X / 2, legY, 0))
	newPart("Torso", torso, SHIRT, rig):SetAttribute("Offset", Vector3.new(0, torsoY, 0))
	newPart("LeftArm", limb, SHIRT, rig):SetAttribute("Offset", Vector3.new(-(torso.X + limb.X) / 2, torsoY, 0))

	local headPart = newPart("Head", head, SKIN, rig)
	headPart:SetAttribute("Offset", Vector3.new(0, headY, 0))
	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent = headPart

	-- The stock Roblox face, so he actually looks at what he is chopping
	local face = Instance.new("Decal")
	face.Name = "Face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = headPart

	-- The chopping arm and axe are positioned explicitly each frame (see
	-- poseArm) rather than carried as fixed offsets, so the blade can be made
	-- to land on the trunk instead of swinging through empty air.
	newPart("RightArm", limb, SHIRT, rig)

	newPart("AxeHandle", Vector3.new(0.09, 0.95, 0.09) * scale * 2, AXE_HANDLE, rig)

	-- An axe head reads as an axe only if it tapers: a small eye where it
	-- meets the shaft, and a wedge flaring out to the cutting edge.
	local eye = newPart("AxeEye", Vector3.new(0.16, 0.20, 0.16) * scale * 2, AXE_HEAD, rig)
	eye.Material = Enum.Material.Metal

	local bit = Instance.new("WedgePart")
	bit.Name = "AxeBit"
	bit.Size = Vector3.new(0.10, 0.34, 0.36) * scale * 2
	bit.Color = AXE_HEAD
	bit.Material = Enum.Material.Metal
	bit.Anchored = true
	bit.CanCollide = false
	bit.CanQuery = false
	bit.CanTouch = false
	bit.Parent = rig

	rig.PrimaryPart = rig:FindFirstChild("Torso")
	return rig
end

local function getCarriedLog(rig)
	return rig:FindFirstChild("CarriedLog")
end

-- ---------------------------------------------------------------------------
-- Placement helpers
-- ---------------------------------------------------------------------------

local function machineBase(instance)
	local boundsCFrame, boundsSize = instance:GetBoundingBox()
	local pivot = instance:GetPivot()
	local floor = CFrame.new(boundsCFrame.Position.X, boundsCFrame.Position.Y - boundsSize.Y / 2, boundsCFrame.Position.Z)
	return floor * (pivot - pivot.Position)
end

-- The frame the worker stands in: at his feet, looking where he is going.
--
-- Built with CFrame.lookAt so the frame follows Roblox's own convention,
-- where LookVector is -Z. That is the same convention a Part's Front face
-- uses, so the face decal lands on the side he actually looks at without any
-- guesswork about which way round the rig is.
local function rigFrame(baseCFrame, standAt, lookDirection)
	local flat = Vector3.new(lookDirection.X, 0, lookDirection.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.zAxis
	end
	return baseCFrame * CFrame.lookAt(standAt, standAt + flat.Unit)
end

local function poseBody(rig, frame, stride)
	for _, part in ipairs(rig:GetChildren()) do
		if part:IsA("BasePart") then
			local offset = part:GetAttribute("Offset")
			if offset then
				local lean = 0
				if part.Name == "LeftLeg" then
					lean = stride
				elseif part.Name == "RightLeg" then
					lean = -stride
				elseif part.Name == "LeftArm" then
					lean = -stride
				end
				part.CFrame = frame * CFrame.new(offset) * CFrame.Angles(lean, 0, 0)
			end
		end
	end
end

-- Places the arm and axe by aiming them at a point, so the blade can be put
-- exactly on the trunk rather than at the end of a guessed rotation.
local function poseArm(rig, frame, scale, targetInFrame)
	local arm = rig:FindFirstChild("RightArm")
	local handle = rig:FindFirstChild("AxeHandle")
	local eye = rig:FindFirstChild("AxeEye")
	local bit = rig:FindFirstChild("AxeBit")
	if not (arm and handle and eye and bit) then
		return
	end

	local limbLength = R6.limb.Y * scale
	local shoulder = Vector3.new(
		(R6.torso.X + R6.limb.X) / 2 * scale,
		(R6.limb.Y + R6.torso.Y / 2) * scale + limbLength / 2,
		0
	)

	local reach = targetInFrame - shoulder
	local distance = reach.Magnitude
	if distance < 0.05 then
		return
	end
	local direction = reach / distance

	-- Arm covers the first stretch, the shaft spans the rest to the blade
	local armEnd = shoulder + direction * limbLength
	-- Up must not be parallel to the aim, and the axe hangs straight down at
	-- rest, so the sideways axis is used instead of world up.
	local aim = CFrame.lookAt(Vector3.zero, direction, Vector3.xAxis) * CFrame.Angles(math.rad(-90), 0, 0)

	arm.CFrame = frame * (CFrame.new(shoulder + direction * (limbLength / 2)) * (aim - aim.Position))

	local shaftLength = math.max(distance - limbLength, 0.05)
	handle.Size = Vector3.new(handle.Size.X, shaftLength, handle.Size.Z)
	handle.CFrame = frame * (CFrame.new(armEnd + direction * (shaftLength / 2)) * (aim - aim.Position))

	eye.CFrame = frame * (CFrame.new(targetInFrame - direction * 0.10) * (aim - aim.Position))
	bit.CFrame = frame
		* (CFrame.new(targetInFrame + direction * 0.06) * (aim - aim.Position) * CFrame.Angles(0, math.rad(90), 0))
end

-- ---------------------------------------------------------------------------
-- Tree visibility
-- ---------------------------------------------------------------------------

local function setTreeVisible(instance, treeIndex, visible)
	local prefix = "Tree" .. tostring(treeIndex) .. "_"
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") and string.find(descendant.Name, prefix, 1, true) then
			descendant.Transparency = visible and 0 or 1
		end
	end
end

local function resetTrees(instance, count)
	for index = 1, count do
		setTreeVisible(instance, index, true)
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function PlotWorkers.Clear(machine)
	if machine.worker then
		machine.worker:Destroy()
		machine.worker = nil
	end

	if machine.instance and machine.instance.Parent and machine.workerConfig then
		resetTrees(machine.instance, machine.workerConfig.treeCount or 0)
	end

	machine.workerConfig = nil
	machine.workerBase = nil
	machine.workerAnchor = nil
	machine.workerAnchorCFrame = nil
	machine.workerCycle = nil
	machine.workerTrees = nil
	machine.workerProgress = nil
	machine.workerFelled = nil
end

function PlotWorkers.Update(machine, machineData, progress)
	local config = machineData and machineData.worker
	local instance = machine.instance
	if not config or not instance or not instance.Parent then
		return
	end

	if not machine.worker or not machine.worker.Parent then
		-- Measured before the rig is parented in, otherwise the worker and the
		-- log he carries would drag the machine's own bounding box around and
		-- the reference frame would drift a little further every step.
		machine.workerBase = machineBase(instance)
		-- Anchor to a real part of the machine, not to GetPivot(): without a
		-- PrimaryPart the pivot is derived from the bounding box, which the
		-- worker himself would then be part of.
		machine.workerAnchor = instance:FindFirstChildWhichIsA("BasePart", true)
		machine.workerAnchorCFrame = machine.workerAnchor and machine.workerAnchor.CFrame
		machine.worker = buildRig(config.scale or 0.5)
		machine.worker.Parent = instance
		machine.workerConfig = config
		machine.workerCycle = 0
		machine.workerFelled = {}

		-- Read where the trees actually are rather than trusting hand-written
		-- coordinates: the FBX pipeline can flip axes, and the model is the
		-- only thing that knows the truth.
		machine.workerTrees = {}
		for index = 1, (config.treeCount or 0) do
			local prefix = "Tree" .. tostring(index) .. "_"
			for _, descendant in ipairs(instance:GetDescendants()) do
				if descendant:IsA("BasePart") and string.find(descendant.Name, prefix, 1, true) then
					local localPosition = machine.workerBase:PointToObjectSpace(descendant.Position)
					machine.workerTrees[index] = Vector3.new(localPosition.X, 0, localPosition.Z)
					break
				end
			end
		end
	end

	-- Rebuild the reference if the machine was rotated or moved underneath him
	local anchor = machine.workerAnchor
	local anchorWas = machine.workerAnchorCFrame
	if anchor and anchorWas then
		if not anchor.Parent then
			PlotWorkers.Clear(machine)
			return
		end

		local moved = (anchor.Position - anchorWas.Position).Magnitude > 0.05
		local turned = anchor.CFrame.LookVector:Dot(anchorWas.LookVector) < 0.999
		if moved or turned then
			machine.worker:Destroy()
			machine.worker = nil
			machine.workerBase = nil
			machine.workerAnchor = nil
			machine.workerAnchorCFrame = nil
			return
		end
	end

	-- A cycle has rolled over when the machine's progress resets
	local previous = machine.workerProgress or 0
	if progress < previous - 0.25 then
		machine.workerCycle = (machine.workerCycle or 0) + 1

		-- Regrow anything felled long enough ago
		local regrowAfter = config.regrowCycles or 2
		for index, cycle in pairs(machine.workerFelled) do
			if machine.workerCycle - cycle >= regrowAfter then
				setTreeVisible(instance, index, true)
				machine.workerFelled[index] = nil
			end
		end
	end
	machine.workerProgress = progress

	local trees = machine.workerTrees or {}
	local treeCount = #trees
	if treeCount == 0 then
		return
	end

	local treeIndex = ((machine.workerCycle or 0) % treeCount) + 1
	local tree = trees[treeIndex]
	local drop = config.dropAt or Vector3.new(2.4, 0, 0)
	local groundY = config.groundY or 0.3

	-- Stand on the road beside the tree rather than in its bed
	local standAtTree = Vector3.new(tree.X, groundY, tree.Z * (config.standInset or 0.55))
	local standAtDrop = Vector3.new(drop.X, groundY, drop.Z)

	local base = machine.workerBase
	if not base then
		return
	end
	local position, stride = standAtDrop, 0
	local lookAt = standAtTree - standAtDrop
	local chopBlend = nil

	local phase = {
		walkOut = config.walkOut or 0.22,
		chop = config.chopUntil or 0.55,
		carry = config.carryUntil or 0.85,
	}

	if progress < phase.walkOut then
		local t = progress / phase.walkOut
		position = standAtDrop:Lerp(standAtTree, t)
		stride = math.sin(progress * 40) * 0.45
		lookAt = standAtTree - standAtDrop
	elseif progress < phase.chop then
		position = standAtTree
		lookAt = Vector3.new(tree.X, 0, tree.Z) - standAtTree
		-- 0 is the axe raised behind him, 1 is the blade buried in the trunk
		chopBlend = 0.5 - 0.5 * math.cos((progress - phase.walkOut) * 26)
	elseif progress < phase.carry then
		local t = (progress - phase.chop) / (phase.carry - phase.chop)
		position = standAtTree:Lerp(standAtDrop, t)
		stride = math.sin(progress * 40) * 0.45
		lookAt = standAtDrop - standAtTree
	else
		position = standAtDrop
		lookAt = standAtTree - standAtDrop
	end

	-- Fell the tree at the end of the chopping phase
	if progress >= phase.chop and not machine.workerFelled[treeIndex] then
		setTreeVisible(instance, treeIndex, false)
		machine.workerFelled[treeIndex] = machine.workerCycle or 0
	end

	local frame = rigFrame(base, position, lookAt)
	local scale = config.scale or 0.5
	poseBody(machine.worker, frame, stride)

	-- Where the blade should be. While chopping that is the trunk itself, at
	-- the height a lumberjack actually cuts; otherwise the axe simply hangs.
	local limbLength = R6.limb.Y * scale
	local shoulderHeight = (R6.limb.Y + R6.torso.Y / 2) * scale + limbLength / 2
	local resting = Vector3.new(
		(R6.torso.X + R6.limb.X) / 2 * scale,
		shoulderHeight - limbLength * 1.55,
		-0.10
	)

	local aimAt = resting
	if chopBlend then
		local trunkInFrame = frame:PointToObjectSpace(
			(base * CFrame.new(Vector3.new(tree.X, groundY + (config.chopHeight or 0.55), tree.Z))).Position
		)
		local raised = Vector3.new(resting.X, shoulderHeight + limbLength * 0.55, limbLength * 0.45)
		aimAt = raised:Lerp(trunkInFrame, chopBlend)
	end

	poseArm(machine.worker, frame, scale, aimAt)

	-- Carry the log between felling and dropping it on the pile
	local carrying = progress >= phase.chop and progress < phase.carry
	local log = getCarriedLog(machine.worker)
	if carrying and not log then
		log = Instance.new("Part")
		log.Name = "CarriedLog"
		log.Shape = Enum.PartType.Cylinder
		log.Size = Vector3.new(1.30, 0.42, 0.42)
		log.Color = Color3.fromRGB(124, 78, 43)
		log.Material = Enum.Material.Wood
		log.Anchored = true
		log.CanCollide = false
		log.CanQuery = false
		log.CanTouch = false
		log.Parent = machine.worker
	elseif not carrying and log then
		log:Destroy()
		log = nil
	end

	if log then
		-- Slung across his back: forward is -Z, so behind him is +Z
		log.CFrame = frame
			* CFrame.new(0, (R6.limb.Y + R6.torso.Y * 0.55) * scale, 0.62 * scale * 2)
	end
end

return PlotWorkers
