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

	-- The chopping arm and its axe are posed together, so they live in their
	-- own folder and are placed relative to the shoulder rather than the feet
	local armPivot = Vector3.new((torso.X + limb.X) / 2, torsoY + limb.Y / 2, 0)
	local arm = newPart("RightArm", limb, SHIRT, rig)
	arm:SetAttribute("Pivot", armPivot)
	arm:SetAttribute("Offset", Vector3.new(0, -limb.Y / 2, 0))

	local handle = newPart("AxeHandle", Vector3.new(0.12, 1.05, 0.12) * scale * 2, AXE_HANDLE, rig)
	handle:SetAttribute("Pivot", armPivot)
	handle:SetAttribute("Offset", Vector3.new(0, -limb.Y * 0.95, 0.10 * scale))

	local blade = newPart("AxeHead", Vector3.new(0.55, 0.42, 0.16) * scale * 2, AXE_HEAD, rig)
	blade.Material = Enum.Material.Metal
	blade:SetAttribute("Pivot", armPivot)
	blade:SetAttribute("Offset", Vector3.new(0.12 * scale, -limb.Y * 1.42, 0.10 * scale))

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

local function poseRig(rig, baseCFrame, standAt, facing, swing, stride)
	for _, part in ipairs(rig:GetChildren()) do
		if part:IsA("BasePart") then
			local offset = part:GetAttribute("Offset")
			if offset then
				local pivotOffset = part:GetAttribute("Pivot")
				local local_
				if pivotOffset then
					-- Arm and axe rotate about the shoulder
					local_ = CFrame.new(standAt + pivotOffset)
						* CFrame.Angles(swing, 0, 0)
						* CFrame.new(offset)
				else
					local lean = 0
					if part.Name == "LeftLeg" then
						lean = stride
					elseif part.Name == "RightLeg" then
						lean = -stride
					elseif part.Name == "LeftArm" then
						lean = -stride
					end
					local_ = CFrame.new(standAt + offset) * CFrame.Angles(lean, 0, 0)
				end

				part.CFrame = baseCFrame * (CFrame.new(standAt) * CFrame.Angles(0, facing, 0) * CFrame.new(-standAt)) * local_
			end
		end
	end
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
	local position, facing, swing, stride = standAtDrop, 0, 0, 0

	local phase = {
		walkOut = config.walkOut or 0.22,
		chop = config.chopUntil or 0.55,
		carry = config.carryUntil or 0.85,
	}

	if progress < phase.walkOut then
		local t = progress / phase.walkOut
		position = standAtDrop:Lerp(standAtTree, t)
		stride = math.sin(progress * 40) * 0.45
		facing = math.atan2(standAtTree.X - standAtDrop.X, standAtTree.Z - standAtDrop.Z)
	elseif progress < phase.chop then
		position = standAtTree
		-- Repeated overhead swings while the tree is still standing
		swing = -math.abs(math.sin((progress - phase.walkOut) * 26)) * 2.2
		facing = math.atan2(tree.X - standAtTree.X, tree.Z - standAtTree.Z)
	elseif progress < phase.carry then
		local t = (progress - phase.chop) / (phase.carry - phase.chop)
		position = standAtTree:Lerp(standAtDrop, t)
		stride = math.sin(progress * 40) * 0.45
		facing = math.atan2(standAtDrop.X - standAtTree.X, standAtDrop.Z - standAtTree.Z)
	else
		position = standAtDrop
		facing = math.atan2(standAtTree.X - standAtDrop.X, standAtTree.Z - standAtDrop.Z)
	end

	-- Fell the tree at the end of the chopping phase
	if progress >= phase.chop and not machine.workerFelled[treeIndex] then
		setTreeVisible(instance, treeIndex, false)
		machine.workerFelled[treeIndex] = machine.workerCycle or 0
	end

	poseRig(machine.worker, base, position, facing, swing, stride)

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
		local scale = config.scale or 0.5
		local hold = position + Vector3.new(0, R6.limb.Y * scale + R6.torso.Y * scale * 0.55, 0)
		log.CFrame = base
			* (CFrame.new(hold) * CFrame.Angles(0, facing, 0) * CFrame.new(0, 0, -0.55 * scale * 2))
	end
end

return PlotWorkers
