--[[
	Definitions.luau
	
	Centralized module containing all immutable game definitions:
	- Items (production and placeable)
	- Machines (producers and processors)
	- NPCs and their specializations
	- Town prestige stages
	- Currencies
	
	This module is loaded by both server and client scripts.
	All data is read-only after initialization to prevent accidental modifications.
]]

local Definitions = {}

-- ============================================================================
-- ITEMS: Production items and placeable machines
-- ============================================================================
local ITEMS = {
	-- Production Items (consumables that can be transported/sold)
	Log = {
		name = "Log",
		icon = "🪵",
		category = "wood",
		value = 10,
		rarity = "common",
		isProduction = true,
		size = Vector3.new(2.2, 0.9, 0.9),
	},
	Plank = {
		name = "Plank",
		icon = "🟫",
		category = "wood",
		value = 15,
		rarity = "common",
		isProduction = true,
		size = Vector3.new(1.35, 0.45, 1.35),
	},
	Beam = {
		name = "Beam",
		icon = "📏",
		category = "wood",
		value = 25,
		rarity = "common",
		isProduction = true,
		size = Vector3.new(4.5, 1.35, 1.95),
	},
	Crate = {
		name = "Crate",
		icon = "CR",
		category = "wood",
		value = 45,
		rarity = "common",
		isProduction = true,
		size = Vector3.new(1.15, 1.0, 1.15),
	},
	Stone = {
		name = "Stone",
		icon = "🪨",
		category = "stone",
		value = 12,
		rarity = "common",
		isProduction = true,
		size = Vector3.new(0.85, 0.65, 0.85),
	},
	StoneBlock = {
		name = "StoneBlock",
		icon = "🧱",
		category = "stone",
		value = 18,
		rarity = "common",
		isProduction = true,
		size = Vector3.new(0.9, 0.75, 0.9),
	},
	Brick = {
		name = "Brick",
		icon = "BR",
		category = "stone",
		value = 42,
		rarity = "common",
		isProduction = true,
		size = Vector3.new(1.15, 0.55, 0.6),
	},
	IronOre = {
		name = "IronOre",
		icon = "🪨",
		category = "iron",
		value = 20,
		rarity = "common",
		isProduction = true,
		size = Vector3.new(1.05, 0.75, 1.05),
	},
	IronIngot = {
		name = "IronIngot",
		icon = "⚙️",
		category = "iron",
		value = 30,
		rarity = "common",
		isProduction = true,
		size = Vector3.new(1.1, 0.45, 0.55),
	},

	-- Placeable Items (machines, transportation, and decorations)
	RubiksCube = {
		name = "RubiksCube",
		icon = "R",
		category = "decoration",
		cost = 10,
		type = "decoration",
		isMachine = false,
		isProduction = false,
	},
	DecorTree = {
		name = "DecorTree",
		icon = "🌳",
		category = "decoration",
		cost = 20,
		type = "decoration",
		isMachine = false,
		isProduction = false,
	},
	FactorySign = {
		name = "FactorySign",
		icon = "🪧",
		category = "decoration",
		cost = 35,
		type = "decoration",
		isMachine = false,
		isProduction = false,
	},
	StreetLamp = {
		name = "StreetLamp",
		icon = "💡",
		category = "decoration",
		cost = 50,
		type = "decoration",
		isMachine = false,
		isProduction = false,
	},
	Conveyor = {
		name = "Conveyor",
		icon = "=>",
		category = "transportation",
		cost = 25,
		type = "conveyor",
		isMachine = false,
		isProduction = false,
	},
	CurvedConveyor = {
		name = "CurvedConveyor",
		icon = "↪",
		category = "transportation",
		cost = 35,
		type = "curved_conveyor",
		isMachine = false,
		isProduction = false,
	},
	Splitter = {
		name = "Splitter",
		icon = "Y",
		category = "transportation",
		cost = 60,
		type = "splitter",
		gridSize = { x = 2, z = 1 },
		isMachine = false,
		isProduction = false,
	},
	Merger = {
		name = "Merger",
		icon = ">",
		category = "transportation",
		cost = 60,
		type = "merger",
		gridSize = { x = 2, z = 1 },
		isMachine = false,
		isProduction = false,
	},
	SmallGenerator = {
		name = "SmallGenerator",
		icon = "⚡",
		category = "power",
		cost = 250,
		type = "generator",
		powerProvided = 20,
		isMachine = false,
		isProduction = false,
	},
	MiraSellZone = {
		name = "MiraSellZone",
		icon = "M",
		category = "sell_zone",
		type = "sell_zone",
		npcName = "Mira",
		isMachine = false,
		isProduction = false,
	},
	BrontSellZone = {
		name = "BrontSellZone",
		icon = "B",
		category = "sell_zone",
		type = "sell_zone",
		npcName = "Bront",
		isMachine = false,
		isProduction = false,
	},
	ElrikSellZone = {
		name = "ElrikSellZone",
		icon = "E",
		category = "sell_zone",
		type = "sell_zone",
		npcName = "Elrik",
		isMachine = false,
		isProduction = false,
	},
	TreeFarm = {
		name = "TreeFarm",
		icon = "🌳",
		category = "machine",
		cost = 100,
		type = "producer",
		isMachine = true,
		isProduction = false,
	},
	MineEntrance = {
		name = "MineEntrance",
		icon = "⛏️",
		category = "machine",
		cost = 150,
		type = "producer",
		isMachine = true,
		isProduction = false,
	},
	Quarry = {
		name = "Quarry",
		icon = "QR",
		category = "machine",
		cost = 100,
		type = "producer",
		isMachine = true,
		isProduction = false,
	},
	Sawmill = {
		name = "Sawmill",
		icon = "🏭",
		category = "machine",
		cost = 75,
		type = "processor",
		isMachine = true,
		isProduction = false,
	},
	BeamCutter = {
		name = "BeamCutter",
		icon = "BC",
		category = "machine",
		cost = 125,
		type = "processor",
		isMachine = true,
		isProduction = false,
	},
	CrateAssembler = {
		name = "CrateAssembler",
		icon = "CA",
		category = "machine",
		cost = 350,
		type = "processor",
		isMachine = true,
		isProduction = false,
	},
	StoneCutter = {
		name = "StoneCutter",
		icon = "SC",
		category = "machine",
		cost = 125,
		type = "processor",
		isMachine = true,
		isProduction = false,
	},
	Furnace = {
		name = "Furnace",
		icon = "F",
		category = "machine",
		cost = 175,
		type = "processor",
		isMachine = true,
		isProduction = false,
	},
	BrickKiln = {
		name = "BrickKiln",
		icon = "BK",
		category = "machine",
		cost = 420,
		type = "processor",
		isMachine = true,
		isProduction = false,
	},
}

-- ============================================================================
-- MACHINES: Production and processing machine definitions
-- ============================================================================
local MACHINES = {
	-- Producer machines (generate items without input)
	TreeFarm = {
		name = "TreeFarm",
		type = "producer",
		outputItem = "Log",
		outputRate = 1,
		outputFrequency = 5, -- seconds between outputs
		-- Logs leave on the side the model's log pile is on
		outputRotationOffset = 2,
		powerRequired = 10,
		-- Drives the lumberjack animation. Tree positions are read from the
		-- placed model at runtime; only the count is declared here.
		worker = {
			scale = 0.5,
			groundY = 0.30,
			standInset = 0.55, -- how far off the bed he stands, toward the road
			dropAt = Vector3.new(2.40, 0, 0),
			regrowCycles = 2,
			treeCount = 6,
			walkOut = 0.22,
			chopUntil = 0.55,
			carryUntil = 0.85,
		},
	},
	MineEntrance = {
		name = "MineEntrance",
		type = "producer",
		outputItem = "IronOre",
		outputRate = 1,
		outputFrequency = 6,
		outputRotationOffset = 3,
		powerRequired = 15,
	},
	Quarry = {
		name = "Quarry",
		type = "producer",
		outputItem = "Stone",
		outputRate = 1,
		outputFrequency = 6,
		outputRotationOffset = 3,
		powerRequired = 12,
	},

	-- Processor machines (transform items)
	Sawmill = {
		name = "Sawmill",
		type = "processor",
		inputItem = "Log",
		outputItem = "Plank",
		conversionRate = 1,
		processingTime = 3,
		inputQueueSize = 2,
		powerRequired = 8,
		-- Drives the on-machine cutting animation: where the piece rests
		-- (studs above the machine's base), how far the saw head sweeps,
		-- and how far through the cut the log becomes a plank.
		workpiece = { height = 1.25, headTravel = 2.2, swapAt = 0.62 },
	},
	BeamCutter = {
		name = "BeamCutter",
		type = "processor",
		inputItem = "Plank",
		outputItem = "Beam",
		processingTime = 4,
		inputQueueSize = 2,
		powerRequired = 12,
	},
	CrateAssembler = {
		name = "CrateAssembler",
		type = "processor",
		inputItem = "Beam",
		inputCount = 2,
		outputItem = "Crate",
		processingTime = 6,
		inputQueueSize = 4,
		powerRequired = 18,
		outputRotationOffset = 0,
	},
	StoneCutter = {
		name = "StoneCutter",
		type = "processor",
		inputItem = "Stone",
		outputItem = "StoneBlock",
		processingTime = 3,
		inputQueueSize = 2,
		powerRequired = 10,
	},
	Furnace = {
		name = "Furnace",
		type = "processor",
		inputItem = "IronOre",
		outputItem = "IronIngot",
		outputRotationOffset = 3,
		processingTime = 5,
		inputQueueSize = 2,
		powerRequired = 15,
	},
	BrickKiln = {
		name = "BrickKiln",
		type = "processor",
		inputItem = "StoneBlock",
		inputCount = 2,
		outputItem = "Brick",
		processingTime = 7,
		inputQueueSize = 4,
		powerRequired = 20,
		outputRotationOffset = 0,
	},
}

-- ============================================================================
-- NPCS: NPCs and their properties
-- ============================================================================
local NPCS = {
	Mira = {
		name = "Mira",
		title = "Falegname",
		icon = "👨",
		specialization = "wood",
		buysItems = { "Plank", "Beam", "Crate" },
		baseReputationReward = 5,
		basePriceMultiplier = 1.0,
		itemRewards = {
			Plank = { money = 15, reputation = 5 },
			Beam = { money = 25, reputation = 8 },
			Crate = { money = 45, reputation = 12 },
		},
		unlocksAt = { reputation = 0 }, -- Unlocked from start
	},
	Bront = {
		name = "Bront",
		title = "Muratore",
		icon = "👷",
		specialization = "stone",
		buysItems = { "StoneBlock", "Brick", "Glass" },
		baseReputationReward = 5,
		basePriceMultiplier = 1.0,
		unlocksAt = { reputation = 0 },
	},
	Elrik = {
		name = "Elrik",
		title = "Fabbro",
		icon = "⚒️",
		specialization = "iron",
		buysItems = { "IronIngot", "IronPlate", "Gear" },
		baseReputationReward = 5,
		basePriceMultiplier = 1.0,
		unlocksAt = { reputation = 0 },
	},
	Mayor = {
		name = "Sindaco",
		title = "Gestione Città",
		icon = "👔",
		specialization = "prestige",
		collectsContributions = true,
	},
}

-- ============================================================================
-- TOWN_PRESTIGE_STAGES: Town progression stages
-- ============================================================================
local TOWN_PRESTIGE_STAGES = {
	{
		stage = 1,
		name = "Outpost",
		requirements = { totalContribution = 0 },
		rewards = { powerCapacity = 100, newShopItems = {} },
	},
	{
		stage = 2,
		name = "Village",
		requirements = { totalContribution = 500, Mira = 50 },
		rewards = { powerCapacity = 100, newShopItems = { "SmallGenerator" } },
	},
}

-- ============================================================================
-- CURRENCIES: Currency definitions
-- ============================================================================
local CURRENCIES = {
	Money = { symbol = "💵", type = "earneable", source = "selling" },
	Diamond = { symbol = "💎", type = "earneable", source = "achievements" },
	Robux = { symbol = "Ⓡ", type = "premium", source = "gamepasses" },
}

-- ============================================================================
-- Helper function to create lookup maps
-- ============================================================================
local function CreateNameMap(items, mapName)
	local map = {}
	for key, value in pairs(items) do
		if map[key] then
			error(string.format("[Definitions] Duplicate name conflict in %s: '%s'", mapName, key))
		end
		map[key] = value
	end
	return map
end

-- Create lookup maps for fast access
local itemMap = CreateNameMap(ITEMS, "ITEMS")
local machineMap = CreateNameMap(MACHINES, "MACHINES")
local npcMap = CreateNameMap(NPCS, "NPCS")

-- ============================================================================
-- Helper Functions
-- ============================================================================

--[[
	GetItem(itemName: string) -> table or nil
	Returns the definition of an item by name, or nil if not found.
]]
function Definitions.GetItem(itemName)
	return itemMap[itemName]
end

--[[
	GetMachine(machineName: string) -> table or nil
	Returns the definition of a machine by name, or nil if not found.
]]
function Definitions.GetMachine(machineName)
	return machineMap[machineName]
end

--[[
	GetNPC(npcName: string) -> table or nil
	Returns the definition of an NPC by name, or nil if not found.
]]
function Definitions.GetNPC(npcName)
	return npcMap[npcName]
end

--[[
	IsProduction(itemName: string) -> boolean
	Returns true if the item is a production item (consumable), false if placeable.
]]
function Definitions.IsProduction(itemName)
	local item = itemMap[itemName]
	if not item then
		return false
	end
	return item.isProduction == true
end

--[[
	IsMachine(itemName: string) -> boolean
	Returns true if the item is a machine, false otherwise.
]]
function Definitions.IsMachine(itemName)
	local item = itemMap[itemName]
	if not item then
		return false
	end
	return item.isMachine == true
end

-- ============================================================================
-- Make definitions immutable (read-only)
-- ============================================================================

local function MakeReadOnly(tbl, tableName)
	return setmetatable({}, {
		__index = tbl,
		__pairs = function()
			return pairs(tbl)
		end,
		__newindex = function(t, k, v)
			error(string.format("[Definitions] Cannot modify read-only table '%s'", tableName))
		end,
		__metatable = "locked",
	})
end

-- Expose definitions as read-only tables
Definitions.ITEMS = MakeReadOnly(ITEMS, "ITEMS")
Definitions.MACHINES = MakeReadOnly(MACHINES, "MACHINES")
Definitions.NPCS = MakeReadOnly(NPCS, "NPCS")
Definitions.TOWN_PRESTIGE_STAGES = MakeReadOnly(TOWN_PRESTIGE_STAGES, "TOWN_PRESTIGE_STAGES")
Definitions.CURRENCIES = MakeReadOnly(CURRENCIES, "CURRENCIES")

-- Validate no conflicts between tables
local function ValidateNoConflicts()
	local allNames = {}

	-- Check ITEMS
	for itemName, _ in pairs(ITEMS) do
		if allNames[itemName] then
			error(string.format("[Definitions] Name conflict: '%s' appears in multiple definition tables", itemName))
		end
		allNames[itemName] = "ITEMS"
	end

	-- Check MACHINES (machines can have same names as items, that's expected)
	for machineName, _ in pairs(MACHINES) do
		if not ITEMS[machineName] then
			error(string.format("[Definitions] Machine '%s' has no corresponding item definition", machineName))
		end
	end

	-- Check NPCS
	for npcName, _ in pairs(NPCS) do
		if allNames[npcName] and allNames[npcName] ~= "NPCS" then
			error(string.format("[Definitions] Name conflict: '%s' appears in multiple definition tables", npcName))
		end
		allNames[npcName] = "NPCS"
	end
end

-- Run validation on load
ValidateNoConflicts()

-- ============================================================================
-- Helper function to get all items
-- ============================================================================
local function GetAllItems()
	return ITEMS
end

Definitions.GetAllItems = GetAllItems

-- ============================================================================
-- Export module
-- ============================================================================

return Definitions
