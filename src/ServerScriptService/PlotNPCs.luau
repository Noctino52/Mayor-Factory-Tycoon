--[[
	PlotNPCs.luau

	The three traders who stand at their sell zones: Mira the carpenter,
	Bront the mason and Elrik the smith. Each works away at their bench, and
	throws their arms up when something is sold to them.

	They are built from native Roblox parts at classic R6 proportions, the
	same as the Tree Farm's lumberjack, so everyone on a plot is the same
	size and the same style. What differs between them is their colours,
	the tool in their hand and the rhythm they work at.

	Everything here is cosmetic. Selling is driven entirely by SellSystem;
	if this module does nothing, the zones still buy and pay.
]]

local RunService = game:GetService("RunService")

local CharacterRig = require(game.ServerScriptService.CharacterRig)

local PlotNPCs = {}

local R6 = CharacterRig.R6
local newPart = CharacterRig.NewPart

local WOOD = Color3.fromRGB(120, 78, 44)
local STEEL = Color3.fromRGB(160, 165, 170)

-- How long the celebration runs after a sale, in seconds
local CHEER_TIME = 1.4

--[[
	One entry per trader. `stand` is where they stand on the zone, in studs
	from its centre, and `work` is the point their tool moves over - both are
	in the zone's own frame, so they follow it when it is rotated.
]]
local NPC_SPECS = {
	Mira = {
		scale = 0.5,
		palette = {
			skin = Color3.fromRGB(234, 184, 146),
			shirt = Color3.fromRGB(66, 132, 84),
			trousers = Color3.fromRGB(92, 66, 44),
		},
		stand = Vector3.new(-1.1, 0, 1.5),
		work = Vector3.new(-1.1, 0, 0.2),
		-- A carpenter's handsaw: a broad blade with a short grip
		tool = {
			{ name = "ToolBlade", size = Vector3.new(0.10, 0.34, 1.05), color = STEEL, material = Enum.Material.Metal },
			{ name = "ToolGrip", size = Vector3.new(0.16, 0.30, 0.30), color = WOOD, offset = Vector3.new(0, 0, 0.62) },
		},
		rate = 5.5,
		swing = 0.55,
	},
	Bront = {
		scale = 0.5,
		palette = {
			skin = Color3.fromRGB(215, 168, 128),
			shirt = Color3.fromRGB(158, 92, 60),
			trousers = Color3.fromRGB(74, 74, 78),
			hat = Color3.fromRGB(226, 176, 44),
			hatBrim = true,
		},
		stand = Vector3.new(1.2, 0, 1.5),
		work = Vector3.new(1.2, 0, 0.3),
		-- A mason's trowel: a flat steel blade on a stubby handle
		tool = {
			{ name = "ToolGrip", size = Vector3.new(0.14, 0.14, 0.34), color = WOOD },
			{ name = "ToolBlade", size = Vector3.new(0.42, 0.07, 0.62), color = STEEL, material = Enum.Material.Metal, offset = Vector3.new(0, -0.06, -0.46) },
		},
		rate = 3.6,
		swing = 0.42,
	},
	Elrik = {
		scale = 0.5,
		palette = {
			skin = Color3.fromRGB(222, 176, 132),
			shirt = Color3.fromRGB(58, 62, 70),
			trousers = Color3.fromRGB(48, 40, 36),
		},
		stand = Vector3.new(0, 0, 1.6),
		work = Vector3.new(0, 0, 0.25),
		-- A smith's hammer: a heavy head across the end of the haft
		tool = {
			{ name = "ToolGrip", size = Vector3.new(0.13, 0.13, 0.66), color = WOOD },
			{ name = "ToolHead", size = Vector3.new(0.26, 0.26, 0.46), color = STEEL, material = Enum.Material.Metal, offset = Vector3.new(0, 0, -0.42) },
		},
		rate = 4.2,
		swing = 0.9,
	},
}

local active = {}
local heartbeat = nil

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

local function buildTool(rig, spec)
	local scale = spec.scale
	for _, piece in ipairs(spec.tool) do
		local part = newPart(piece.name, piece.size * scale * 2, piece.color, rig)
		part.Material = piece.material or Enum.Material.Wood
		part:SetAttribute("ToolOffset", (piece.offset or Vector3.zero) * scale * 2)
	end
end

local function buildNPC(npcName)
	local spec = NPC_SPECS[npcName]
	if not spec then
		return nil
	end

	local rig = CharacterRig.Build(npcName, spec.scale, spec.palette)
	newPart("RightArm", R6.limb * spec.scale, spec.palette.shirt, rig)
	buildTool(rig, spec)
	return rig
end

-- The floor of the zone, in the zone's own orientation: everything an NPC
-- does is placed relative to this. Measured before the rig is parented in,
-- so the figure cannot drag the bounding box around under itself.
local function zoneBase(instance)
	local boundsCFrame, boundsSize = instance:GetBoundingBox()
	local pivot = instance:GetPivot()
	local floor = CFrame.new(
		boundsCFrame.Position.X,
		boundsCFrame.Position.Y - boundsSize.Y / 2,
		boundsCFrame.Position.Z
	)
	return floor * (pivot - pivot.Position)
end

--[[
	How high the trader's feet go: the top of whatever they are standing on.

	Read off the zone's own pad rather than assumed, so it stays right when
	the flat marker plate is replaced by a modelled stall with a roof on it -
	the bounding box would say the roof, which is not where anyone stands.
]]
local function standHeight(instance, base)
	local top = nil

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local name = descendant.Name
			if string.find(name, "Pad", 1, true) or string.find(name, "SellZone", 1, true) then
				local localTop = base:PointToObjectSpace(descendant.Position).Y + descendant.Size.Y / 2
				top = math.max(top or localTop, localTop)
			end
		end
	end

	return top or 0.2
end

-- ---------------------------------------------------------------------------
-- Posing
-- ---------------------------------------------------------------------------

--[[
	Hangs the working arm and its tool from the right shoulder at `angle`.
	The tool pieces are placed along the forearm's own axis, so a hammer
	swung overhead points where the hand points.
]]
local function poseWorkArm(rig, frame, scale, angle)
	local arm = rig:FindFirstChild("RightArm")
	if not arm then
		return
	end

	arm.CFrame = CharacterRig.ArmCFrame(frame, scale, 1, angle)

	local hand = CharacterRig.HandPoint(scale, 1, angle)
	local grip = frame * CFrame.new(hand) * CFrame.Angles(angle, 0, 0)

	for _, part in ipairs(rig:GetChildren()) do
		local toolOffset = part:IsA("BasePart") and part:GetAttribute("ToolOffset")
		if toolOffset then
			part.CFrame = grip * CFrame.new(toolOffset)
		end
	end
end

local function poseNPC(entry, now)
	local spec = entry.spec
	local scale = spec.scale
	local cheerLeft = entry.cheerUntil and (entry.cheerUntil - now) or 0

	local stand = spec.stand
	local look = spec.work - stand
	local frame = CharacterRig.Frame(entry.base, Vector3.new(stand.X, entry.groundY, stand.Z), look)

	if cheerLeft > 0 then
		-- Two hops with the arms up, settling as the cheer runs out
		local t = 1 - cheerLeft / CHEER_TIME
		local fade = math.min(cheerLeft / 0.35, 1)
		local hop = math.abs(math.sin(t * math.pi * 2)) * 0.55 * scale * fade
		local raise = -2.5 * fade

		CharacterRig.PoseBody(entry.rig, frame, { bounce = hop, armRaise = raise, scale = scale })
		poseWorkArm(entry.rig, frame, scale, raise)
		return
	end

	-- Idle: working away at the bench in front of them
	local swing = -0.35 + math.sin(now * spec.rate) * spec.swing
	CharacterRig.PoseBody(entry.rig, frame, { stride = 0, scale = scale })
	poseWorkArm(entry.rig, frame, scale, swing)
end

local function step()
	local now = os.clock()

	for instance, entry in pairs(active) do
		local anchor = entry.anchor
		local moved = anchor
			and anchor.Parent
			and (anchor.Position - entry.anchorCFrame.Position).Magnitude > 0.05

		if not instance.Parent or not entry.rig.Parent or (anchor and not anchor.Parent) then
			active[instance] = nil
		elseif moved then
			-- Placed somewhere else: the reference frame is stale, so start over
			local npcName = entry.npcName
			PlotNPCs.Detach(instance)
			PlotNPCs.Attach(instance, npcName)
		else
			poseNPC(entry, now)
		end
	end

	if next(active) == nil and heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function PlotNPCs.Attach(instance, npcName)
	if not instance or not instance.Parent or not instance:IsA("Model") then
		return
	end

	local existing = active[instance]
	if existing then
		if existing.npcName == npcName and existing.rig.Parent then
			return
		end
		existing.rig:Destroy()
		active[instance] = nil
	end

	local spec = NPC_SPECS[npcName]
	if not spec then
		return
	end

	-- Measured before the rig goes in, for the same reason the machines do it
	local base = zoneBase(instance)
	local rig = buildNPC(npcName)
	if not rig then
		return
	end

	local groundY = standHeight(instance, base)

	-- Anchored to a real part of the zone, not to the pivot: without a
	-- PrimaryPart the pivot comes from the bounding box, which the trader
	-- would then be part of. If the zone moves under him, he is rebuilt.
	local anchor = instance:FindFirstChildWhichIsA("BasePart", true)

	rig.Parent = instance
	active[instance] = {
		npcName = npcName,
		spec = spec,
		rig = rig,
		base = base,
		groundY = groundY,
		anchor = anchor,
		anchorCFrame = anchor and anchor.CFrame,
	}

	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(step)
	end
end

function PlotNPCs.Detach(instance)
	local entry = instance and active[instance]
	if not entry then
		return
	end

	if entry.rig then
		entry.rig:Destroy()
	end
	active[instance] = nil
end

-- Called when the zone buys something: the trader is pleased about it
function PlotNPCs.Celebrate(instance)
	local entry = instance and active[instance]
	if not entry then
		return
	end

	entry.cheerUntil = os.clock() + CHEER_TIME
end

return PlotNPCs
