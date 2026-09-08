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
local LEATHER = Color3.fromRGB(74, 48, 30)

-- How long the celebration runs after a sale, in seconds
local CHEER_TIME = 1.4

-- Heights everything worn is measured from, at R6 scale 1
local TORSO_Y = CharacterRig.TorsoY(1)
local HEAD_Y = CharacterRig.HeadY(1)

--[[
	One entry per trader.

	`stand` is where they stand on the zone and `work` is the point they face,
	both in studs from its centre and in the zone's own frame, so they follow
	it when it is rotated. The stall models put the bench at their own +Y,
	which the FBX export turns into -Z here: the trader stands behind the
	bench, looking out at the customer side, which is where deliveries come
	from.

	`dress` is what they wear, `tool` what they hold, and `motion` is the
	shape of the job: where the hand goes over the course of one stroke,
	relative to the shoulder. A saw runs back and forth, a trowel dabs, a
	hammer is lifted slowly and dropped fast - they are recognisable from
	across the plot by the rhythm alone.
]]
local NPC_SPECS = {
	Mira = {
		scale = 0.5,
		palette = {
			skin = Color3.fromRGB(234, 184, 146),
			shirt = Color3.fromRGB(58, 118, 76),
			trousers = Color3.fromRGB(96, 70, 46),
		},
		dress = {
			-- Canvas apron with a nail pocket across it
			{ name = "Apron", size = Vector3.new(2.10, 1.70, 0.20), color = Color3.fromRGB(206, 180, 130), offset = Vector3.new(0, TORSO_Y - 0.10, -0.56) },
			{ name = "ApronPocket", size = Vector3.new(1.30, 0.54, 0.14), color = Color3.fromRGB(176, 148, 100), offset = Vector3.new(0, TORSO_Y - 0.56, -0.66) },
			-- Neckerchief and a flat cap
			{ name = "Scarf", size = Vector3.new(1.48, 0.30, 1.14), color = Color3.fromRGB(168, 62, 52), offset = Vector3.new(0, TORSO_Y + 0.94, 0) },
			{ name = "Cap", size = Vector3.new(2.10, 0.44, 1.90), color = Color3.fromRGB(96, 70, 46), offset = Vector3.new(0, HEAD_Y + 0.56, 0) },
			{ name = "CapPeak", size = Vector3.new(2.00, 0.18, 0.80), color = Color3.fromRGB(78, 56, 36), offset = Vector3.new(0, HEAD_Y + 0.40, -0.86) },
		},
		stand = Vector3.new(-1.1, 0, -1.5),
		work = Vector3.new(-1.1, 0, -0.2),
		-- A carpenter's handsaw: a broad blade with a short grip
		tool = {
			{ name = "ToolBlade", size = Vector3.new(0.10, 0.34, 1.05), color = STEEL, material = Enum.Material.Metal },
			{ name = "ToolGrip", size = Vector3.new(0.16, 0.30, 0.30), color = WOOD, offset = Vector3.new(0, 0, 0.62) },
		},
		rate = 4.4,
		-- Sawing: the hand runs to and fro at a steady height
		motion = function(phase)
			return -0.62, -0.46 - 0.30 * math.sin(phase)
		end,
	},
	Bront = {
		scale = 0.5,
		palette = {
			skin = Color3.fromRGB(215, 168, 128),
			shirt = Color3.fromRGB(158, 92, 60),
			trousers = Color3.fromRGB(74, 74, 78),
		},
		dress = {
			-- Hard hat, and an apron the stone dust has gone grey on
			{ name = "Helmet", size = Vector3.new(2.10, 0.72, 1.94), color = Color3.fromRGB(226, 176, 44), offset = Vector3.new(0, HEAD_Y + 0.62, 0) },
			{ name = "HelmetBrim", size = Vector3.new(2.50, 0.16, 2.40), color = Color3.fromRGB(206, 158, 34), offset = Vector3.new(0, HEAD_Y + 0.34, 0) },
			{ name = "Apron", size = Vector3.new(2.06, 1.30, 0.20), color = Color3.fromRGB(158, 158, 152), offset = Vector3.new(0, TORSO_Y - 0.24, -0.56) },
			-- Tool belt with a pouch on each hip
			{ name = "Belt", size = Vector3.new(2.16, 0.34, 1.14), color = LEATHER, offset = Vector3.new(0, TORSO_Y - 0.82, 0) },
			{ name = "PouchL", size = Vector3.new(0.52, 0.60, 0.44), color = LEATHER, offset = Vector3.new(-0.72, TORSO_Y - 1.02, -0.60) },
			{ name = "PouchR", size = Vector3.new(0.52, 0.60, 0.44), color = LEATHER, offset = Vector3.new(0.72, TORSO_Y - 1.02, -0.60) },
		},
		stand = Vector3.new(1.2, 0, -1.5),
		work = Vector3.new(1.2, 0, -0.2),
		-- A mason's trowel: a flat steel blade on a stubby handle
		tool = {
			{ name = "ToolGrip", size = Vector3.new(0.14, 0.14, 0.34), color = WOOD },
			{ name = "ToolBlade", size = Vector3.new(0.42, 0.07, 0.62), color = STEEL, material = Enum.Material.Metal, offset = Vector3.new(0, -0.06, -0.46) },
		},
		rate = 3.0,
		-- Laying: a short dab out and back, dipping as it goes
		motion = function(phase)
			return -0.56 + 0.12 * math.sin(phase * 2), -0.40 - 0.20 * math.sin(phase)
		end,
	},
	Elrik = {
		scale = 0.5,
		palette = {
			skin = Color3.fromRGB(222, 176, 132),
			shirt = Color3.fromRGB(64, 68, 76),
			trousers = Color3.fromRGB(46, 40, 36),
		},
		dress = {
			-- Leather apron on a shoulder strap, beard, goggles up on the brow
			{ name = "Apron", size = Vector3.new(2.06, 1.80, 0.22), color = LEATHER, offset = Vector3.new(0, TORSO_Y - 0.18, -0.56) },
			{ name = "StrapL", size = Vector3.new(0.34, 1.00, 0.16), color = LEATHER, offset = Vector3.new(-0.52, TORSO_Y + 0.62, -0.58) },
			{ name = "StrapR", size = Vector3.new(0.34, 1.00, 0.16), color = LEATHER, offset = Vector3.new(0.52, TORSO_Y + 0.62, -0.58) },
			{ name = "Beard", size = Vector3.new(1.30, 0.70, 0.60), color = Color3.fromRGB(112, 86, 60), offset = Vector3.new(0, HEAD_Y - 0.30, -0.56) },
			{ name = "Goggles", size = Vector3.new(2.02, 0.30, 1.80), color = Color3.fromRGB(48, 40, 34), offset = Vector3.new(0, HEAD_Y + 0.46, 0) },
			{ name = "LensL", size = Vector3.new(0.44, 0.34, 0.20), color = Color3.fromRGB(196, 206, 176), offset = Vector3.new(-0.44, HEAD_Y + 0.46, -0.92) },
			{ name = "LensR", size = Vector3.new(0.44, 0.34, 0.20), color = Color3.fromRGB(196, 206, 176), offset = Vector3.new(0.44, HEAD_Y + 0.46, -0.92) },
		},
		stand = Vector3.new(0.1, 0, -1.5),
		work = Vector3.new(0.1, 0, -0.2),
		-- A smith's hammer: a heavy head across the end of the haft
		tool = {
			{ name = "ToolGrip", size = Vector3.new(0.13, 0.13, 0.66), color = WOOD },
			{ name = "ToolHead", size = Vector3.new(0.26, 0.26, 0.46), color = STEEL, material = Enum.Material.Metal, offset = Vector3.new(0, 0, -0.42) },
		},
		rate = 2.6,
		-- Striking: raised over three quarters of the stroke, dropped in the
		-- last quarter, which is what makes it read as a hammer blow
		motion = function(phase)
			local t = (phase / (math.pi * 2)) % 1
			local lift = t < 0.75 and (t / 0.75) or (1 - (t - 0.75) / 0.25)
			return -0.62 + 0.86 * lift, -0.46 + 0.30 * lift
		end,
	},
}

local active = {}
local heartbeat = nil

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------

-- Tool sizes are given in finished studs rather than R6 units, because a saw
-- is a saw whatever the person holding it is scaled to
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
	CharacterRig.Dress(rig, spec.scale, spec.dress)
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
	The shoulder angle that puts the hand at a point, given as an offset from
	the shoulder. The arm hangs down and swings about X, so only the up and
	forward components of the offset matter: hand = shoulder + (0, -L*cos,
	-L*sin), which inverts to this.

	Aiming rather than setting an angle directly is what lets each trade have
	its own shape of movement instead of everyone swinging a hinge.
]]
local function armAngleTo(upOffset, forwardOffset)
	return math.atan2(-forwardOffset, -upOffset)
end

-- Hangs the working arm and its tool from the right shoulder at `angle`
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

	-- At work: the hand traces this trade's own stroke over the bench
	local up, forward = spec.motion(now * spec.rate)
	CharacterRig.PoseBody(entry.rig, frame, { scale = scale })
	poseWorkArm(entry.rig, frame, scale, armAngleTo(up, forward))
end

local function step()
	local now = os.clock()

	for instance, entry in pairs(active) do
		local anchor = entry.anchor
		local was = entry.anchorCFrame
		-- Turned counts as moved: rotating a zone on the spot leaves the
		-- reference frame pointing the old way, and the trader would keep
		-- working at thin air beside the bench.
		local moved = anchor
			and anchor.Parent
			and ((anchor.Position - was.Position).Magnitude > 0.05
				or anchor.CFrame.LookVector:Dot(was.LookVector) < 0.999)

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
