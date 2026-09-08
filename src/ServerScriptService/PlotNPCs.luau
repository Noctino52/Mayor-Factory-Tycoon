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
local NPCAppearance = require(game.ServerScriptService.NPCAppearance)

local PlotNPCs = {}

local R6 = CharacterRig.R6
local newPart = CharacterRig.NewPart

local WOOD = Color3.fromRGB(120, 78, 44)
local STEEL = Color3.fromRGB(160, 165, 170)
local LEATHER = Color3.fromRGB(96, 62, 38)
local APRON = Color3.fromRGB(64, 66, 66)
local BOOT = Color3.fromRGB(74, 52, 36)
local HAIR_DARK = Color3.fromRGB(72, 46, 30)
local HI_VIS = Color3.fromRGB(232, 182, 44)
local HI_VIS_DEEP = Color3.fromRGB(206, 156, 30)

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
--[[
	A hard hat, shared by the two who wear one: a squashed ball for the shell
	with the brim under it, which is the shape that stops it reading as a
	slab on a box. The brim sits above the eyes so the face still shows.
]]
local function hardHat(shell, trim)
	return {
		{ name = "HelmetBrim", size = Vector3.new(2.70, 0.16, 2.70), color = trim, offset = Vector3.new(0, HEAD_Y + 0.45, 0) },
		{ name = "HelmetShell", size = Vector3.new(2.30, 1.30, 2.20), color = shell, shape = Enum.PartType.Ball, offset = Vector3.new(0, HEAD_Y + 0.72, 0) },
		{ name = "HelmetRidge", size = Vector3.new(0.42, 0.34, 2.05), color = trim, offset = Vector3.new(0, HEAD_Y + 1.16, 0) },
		{ name = "HelmetPeak", size = Vector3.new(1.40, 0.14, 0.94), color = trim, offset = Vector3.new(0, HEAD_Y + 0.40, -1.32), tilt = Vector3.new(-0.16, 0, 0) },
	}
end

--[[
	A beard around the jaw rather than across it: two sides and a chin, so it
	frames the face instead of covering it. A block over the front of the
	head hides the eyes, which is what makes a figure look like a brick.
]]
local function beard(colour, moustache)
	local pieces = {
		{ name = "BeardChin", size = Vector3.new(1.44, 0.64, 0.62), color = colour, offset = Vector3.new(0, HEAD_Y - 0.74, -0.34) },
		{ name = "BeardJawL", size = Vector3.new(0.36, 1.06, 1.02), color = colour, offset = Vector3.new(-1.02, HEAD_Y - 0.42, -0.18) },
		{ name = "BeardJawR", size = Vector3.new(0.36, 1.06, 1.02), color = colour, offset = Vector3.new(1.02, HEAD_Y - 0.42, -0.18) },
	}

	if moustache then
		table.insert(pieces, { name = "Moustache", size = Vector3.new(0.96, 0.24, 0.26), color = colour, offset = Vector3.new(0, HEAD_Y - 0.36, -0.66) })
	end

	return pieces
end

local function boots(colour)
	return {
		{ name = "BootL", size = Vector3.new(1.06, 0.46, 1.34), color = colour, offset = Vector3.new(-0.5, 0.23, -0.12) },
		{ name = "BootR", size = Vector3.new(1.06, 0.46, 1.34), color = colour, offset = Vector3.new(0.5, 0.23, -0.12) },
	}
end

local function dressed(...)
	local pieces = {}
	for _, group in ipairs({ ... }) do
		for _, piece in ipairs(group) do
			table.insert(pieces, piece)
		end
	end
	return pieces
end

local NPC_SPECS = {
	--[[
		Mira, carpenter. Hard hat over shoulder-length hair, plaid work shirt,
		hi-vis braces with square buckles, and a loaded tool belt over yellow
		work trousers.
	]]
	Mira = {
		scale = 0.5,
		palette = {
			skin = Color3.fromRGB(240, 200, 168),
			shirt = Color3.fromRGB(138, 62, 52),
			arms = Color3.fromRGB(138, 62, 52),
			trousers = Color3.fromRGB(222, 176, 60),
		},
		accessories = dressed(
			{
				{ name = "HairCrown", size = Vector3.new(2.40, 1.30, 2.32), color = HAIR_DARK, shape = Enum.PartType.Ball, offset = Vector3.new(0, HEAD_Y + 0.36, 0.06) },
				{ name = "HairBack", size = Vector3.new(2.12, 1.70, 0.58), color = HAIR_DARK, offset = Vector3.new(0, HEAD_Y - 0.30, 0.80) },
				{ name = "HairSideL", size = Vector3.new(0.42, 1.74, 1.34), color = HAIR_DARK, offset = Vector3.new(-1.08, HEAD_Y - 0.52, 0.10) },
				{ name = "HairSideR", size = Vector3.new(0.42, 1.74, 1.34), color = HAIR_DARK, offset = Vector3.new(1.08, HEAD_Y - 0.52, 0.10) },
				{ name = "Ponytail", size = Vector3.new(0.68, 1.60, 0.68), color = HAIR_DARK, offset = Vector3.new(0, HEAD_Y - 1.30, 1.02), tilt = Vector3.new(0.22, 0, 0) },
				-- A fringe under the brim, or she reads as bald from the front
				{ name = "Fringe", size = Vector3.new(1.90, 0.34, 0.30), color = HAIR_DARK, offset = Vector3.new(0, HEAD_Y + 0.30, -0.60) },
			},
			hardHat(HI_VIS, HI_VIS_DEEP)
		),
		dress = dressed(
			{
				-- Braces over the shoulders, buckled at the chest
				{ name = "BraceL", size = Vector3.new(0.42, 1.96, 0.16), color = HI_VIS, offset = Vector3.new(-0.56, TORSO_Y + 0.04, -0.57), tilt = Vector3.new(0, 0, 0.06) },
				{ name = "BraceR", size = Vector3.new(0.42, 1.96, 0.16), color = HI_VIS, offset = Vector3.new(0.56, TORSO_Y + 0.04, -0.57), tilt = Vector3.new(0, 0, -0.06) },
				{ name = "BraceOverL", size = Vector3.new(0.42, 0.16, 1.10), color = HI_VIS, offset = Vector3.new(-0.56, TORSO_Y + 1.02, 0) },
				{ name = "BraceOverR", size = Vector3.new(0.42, 0.16, 1.10), color = HI_VIS, offset = Vector3.new(0.56, TORSO_Y + 1.02, 0) },
				{ name = "BuckleL", size = Vector3.new(0.38, 0.36, 0.12), color = LEATHER, offset = Vector3.new(-0.56, TORSO_Y + 0.52, -0.66) },
				{ name = "BuckleR", size = Vector3.new(0.38, 0.36, 0.12), color = LEATHER, offset = Vector3.new(0.56, TORSO_Y + 0.52, -0.66) },
				-- Tool belt, pouches and a rule sticking out of one of them
				{ name = "Belt", size = Vector3.new(2.10, 0.44, 1.10), color = LEATHER, offset = Vector3.new(0, TORSO_Y - 0.82, 0) },
				{ name = "PouchL", size = Vector3.new(0.62, 0.66, 0.44), color = LEATHER, offset = Vector3.new(-0.74, TORSO_Y - 1.08, -0.56) },
				{ name = "PouchR", size = Vector3.new(0.62, 0.66, 0.44), color = LEATHER, offset = Vector3.new(0.74, TORSO_Y - 1.08, -0.56) },
				{ name = "BeltRule", size = Vector3.new(0.20, 0.86, 0.20), color = Color3.fromRGB(176, 44, 40), offset = Vector3.new(-1.04, TORSO_Y - 1.30, -0.26), tilt = Vector3.new(0, 0, 0.12) },
				{ name = "HandL", size = Vector3.new(0.94, 0.54, 0.94), color = Color3.fromRGB(240, 200, 168), hand = -1 },
			},
			boots(BOOT)
		),
		stand = Vector3.new(-1.1, 0, -1.5),
		work = Vector3.new(-1.1, 0, -0.2),
		-- A carpenter handsaw: a broad blade with a short grip
		tool = {
			{ name = "HandR", size = Vector3.new(0.46, 0.26, 0.46), color = Color3.fromRGB(240, 200, 168) },
			{ name = "ToolBlade", size = Vector3.new(0.10, 0.34, 1.05), color = STEEL, material = Enum.Material.Metal },
			{ name = "ToolGrip", size = Vector3.new(0.16, 0.30, 0.30), color = WOOD, offset = Vector3.new(0, 0, 0.62) },
		},
		rate = 4.4,
		-- Sawing: the hand runs to and fro at a steady height
		motion = function(phase)
			return -0.62, -0.46 - 0.30 * math.sin(phase)
		end,
	},

	--[[
		Bront, mason. Hard hat, hi-vis vest with reflective stripes over a
		dark work shirt, full black beard, jeans and a broad buckled belt.
	]]
	Bront = {
		scale = 0.5,
		palette = {
			skin = Color3.fromRGB(226, 178, 140),
			shirt = Color3.fromRGB(46, 54, 72),
			arms = Color3.fromRGB(46, 54, 72),
			trousers = Color3.fromRGB(52, 72, 116),
		},
		accessories = dressed(
			hardHat(HI_VIS, HI_VIS_DEEP),
			beard(Color3.fromRGB(32, 30, 32), true)
		),
		dress = dressed(
			{
				-- The vest wraps the torso rather than hanging off the front
				{ name = "VestFront", size = Vector3.new(1.92, 1.72, 0.18), color = HI_VIS, offset = Vector3.new(0, TORSO_Y - 0.04, -0.56) },
				{ name = "VestBack", size = Vector3.new(1.92, 1.72, 0.16), color = HI_VIS, offset = Vector3.new(0, TORSO_Y - 0.04, 0.55) },
				{ name = "VestSideL", size = Vector3.new(0.20, 1.72, 1.12), color = HI_VIS, offset = Vector3.new(-0.98, TORSO_Y - 0.04, 0) },
				{ name = "VestSideR", size = Vector3.new(0.20, 1.72, 1.12), color = HI_VIS, offset = Vector3.new(0.98, TORSO_Y - 0.04, 0) },
				{ name = "VestStripeL", size = Vector3.new(0.30, 1.72, 0.08), color = Color3.fromRGB(240, 240, 236), offset = Vector3.new(-0.54, TORSO_Y - 0.04, -0.66) },
				{ name = "VestStripeR", size = Vector3.new(0.30, 1.72, 0.08), color = Color3.fromRGB(240, 240, 236), offset = Vector3.new(0.54, TORSO_Y - 0.04, -0.66) },
				{ name = "VestBand", size = Vector3.new(2.04, 0.26, 0.08), color = Color3.fromRGB(240, 240, 236), offset = Vector3.new(0, TORSO_Y - 0.48, -0.66) },
				{ name = "Belt", size = Vector3.new(2.12, 0.38, 1.12), color = LEATHER, offset = Vector3.new(0, TORSO_Y - 0.90, 0) },
				{ name = "Buckle", size = Vector3.new(0.56, 0.38, 0.12), color = Color3.fromRGB(198, 158, 74), offset = Vector3.new(0, TORSO_Y - 0.90, -0.60) },
				{ name = "HandL", size = Vector3.new(0.94, 0.54, 0.94), color = Color3.fromRGB(226, 178, 140), hand = -1 },
			},
			boots(Color3.fromRGB(52, 42, 36))
		),
		stand = Vector3.new(1.2, 0, -1.5),
		work = Vector3.new(1.2, 0, -0.2),
		-- A mason trowel: a flat steel blade on a stubby handle
		tool = {
			{ name = "HandR", size = Vector3.new(0.46, 0.26, 0.46), color = Color3.fromRGB(226, 178, 140) },
			{ name = "ToolGrip", size = Vector3.new(0.14, 0.14, 0.34), color = WOOD },
			{ name = "ToolBlade", size = Vector3.new(0.42, 0.07, 0.62), color = STEEL, material = Enum.Material.Metal, offset = Vector3.new(0, -0.06, -0.46) },
		},
		rate = 3.0,
		-- Laying: a short dab out and back, dipping as it goes
		motion = function(phase)
			return -0.56 + 0.12 * math.sin(phase * 2), -0.40 - 0.20 * math.sin(phase)
		end,
	},

	--[[
		Elrik, smith. Long leather apron on shoulder straps over rolled white
		sleeves, fair beard, soft dark cap.
	]]
	Elrik = {
		scale = 0.5,
		palette = {
			skin = Color3.fromRGB(238, 200, 166),
			shirt = Color3.fromRGB(238, 236, 228),
			arms = Color3.fromRGB(238, 236, 228),
			trousers = Color3.fromRGB(58, 58, 60),
		},
		accessories = dressed(
			{
				{ name = "Cap", size = Vector3.new(2.24, 1.10, 2.16), color = Color3.fromRGB(78, 82, 84), shape = Enum.PartType.Ball, offset = Vector3.new(0, HEAD_Y + 0.62, 0.06) },
				{ name = "CapBand", size = Vector3.new(2.20, 0.26, 2.12), color = Color3.fromRGB(60, 64, 66), offset = Vector3.new(0, HEAD_Y + 0.44, 0.04) },
			},
			beard(Color3.fromRGB(214, 178, 96), true)
		),
		dress = dressed(
			{
				-- The apron is the whole outfit: bib, body, and a skirt that
				-- carries on down over the legs
				{ name = "ApronBib", size = Vector3.new(1.26, 0.96, 0.18), color = APRON, offset = Vector3.new(0, TORSO_Y + 0.74, -0.55) },
				{ name = "ApronBody", size = Vector3.new(1.98, 1.62, 0.20), color = APRON, offset = Vector3.new(0, TORSO_Y - 0.30, -0.56) },
				{ name = "ApronSkirt", size = Vector3.new(1.76, 1.34, 0.20), color = APRON, offset = Vector3.new(0, TORSO_Y - 1.70, -0.52) },
				{ name = "ApronBelt", size = Vector3.new(2.06, 0.24, 0.28), color = Color3.fromRGB(52, 38, 26), offset = Vector3.new(0, TORSO_Y - 0.32, -0.60) },
				{ name = "StrapL", size = Vector3.new(0.32, 1.16, 0.18), color = APRON, offset = Vector3.new(-0.46, TORSO_Y + 0.80, -0.54), tilt = Vector3.new(0, 0, 0.10) },
				{ name = "StrapR", size = Vector3.new(0.32, 1.16, 0.18), color = APRON, offset = Vector3.new(0.46, TORSO_Y + 0.80, -0.54), tilt = Vector3.new(0, 0, -0.10) },
				{ name = "StrapOverL", size = Vector3.new(0.32, 0.16, 1.06), color = APRON, offset = Vector3.new(-0.46, TORSO_Y + 1.02, 0) },
				{ name = "StrapOverR", size = Vector3.new(0.32, 0.16, 1.06), color = APRON, offset = Vector3.new(0.46, TORSO_Y + 1.02, 0) },
				{ name = "HandL", size = Vector3.new(0.94, 0.54, 0.94), color = Color3.fromRGB(238, 200, 166), hand = -1 },
			},
			boots(Color3.fromRGB(46, 38, 34))
		),
		stand = Vector3.new(0.1, 0, -1.5),
		work = Vector3.new(0.1, 0, -0.2),
		-- A smith hammer: a heavy head across the end of the haft
		tool = {
			{ name = "HandR", size = Vector3.new(0.46, 0.26, 0.46), color = Color3.fromRGB(238, 200, 166) },
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

--[[
	A trader, dressed if there is anything to dress them in.

	The wardrobe comes first: a real Roblox avatar in catalogue clothing is
	what these people are meant to look like. The figure built out of parts
	is the fallback, and stays in the game so a plot is never populated by
	nobody while the wardrobe is being filled.
]]
local function buildNPC(npcName)
	local spec = NPC_SPECS[npcName]
	if not spec then
		return nil
	end

	local rig = NPCAppearance.Build(npcName, spec.scale)
	if not rig then
		-- The stand-in has to wear its clothes, because it has no textures
		rig = CharacterRig.Build(npcName, spec.scale, spec.palette)
		CharacterRig.Dress(rig, spec.scale, spec.dress)
		newPart("RightArm", R6.limb * spec.scale, spec.palette.arms or spec.palette.shirt, rig)
	end

	-- Hats, hair and beards are geometry either way: a texture can put a
	-- shirt on someone but it cannot give them a brim or a chin.
	CharacterRig.Dress(rig, spec.scale, spec.accessories)

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
-- The working arm, whichever rig this is: a built figure calls it RightArm,
-- a real avatar calls it "Right Arm" and says so in its Limb attribute
local function workingArm(rig)
	for _, part in ipairs(rig:GetChildren()) do
		if part:IsA("BasePart") and (part:GetAttribute("Limb") or part.Name) == "RightArm" then
			return part
		end
	end
	return nil
end

local function poseWorkArm(rig, frame, scale, angle)
	local arm = workingArm(rig)
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
