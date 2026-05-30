--// Shared_Brainrots - Brainrot item configurations
--// Uses actual brainrot names and structure

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Module = {}

-- Brainrot hold animation (two-handed pose)
Module.HoldAnimation = "Assets.PlayerAnimations.TwoHandHolding"

-- Maximum level for brainrots
Module.MaxLevel = 150
Module.PlotScaleMin = 0.75
Module.PlotScaleMax = 2.75
Module.PlotScaleMaxLevel = 100

-- ==========================================
-- BALANCE CONFIGURATION
-- Tweak these values to rebalance the entire economy
-- ==========================================

Module.BalanceConfig = {
	-- Rarity base income ranges (CashPerSecond at level 1, Normal modifier)
	-- PowerTier 1 = Min, PowerTier 10 = Max
	RarityBaseIncome = {
		Common =    { Min = 5,       Max = 15 },       -- Baseline
		Rare =      { Min = 100,      Max = 280 },      -- 6x jump
		Epic =      { Min = 300,     Max = 1400 },      -- 6x jump
		Legendary = { Min = 1500,    Max = 5000 },     -- 6x jump
		Mythical =  { Min = 6000,    Max = 20000 },    -- 6x jump
		Secret =    { Min = 22000,   Max = 170000 },   -- 6x jump
		Celestial = { Min = 200000,  Max = 5000000 },   -- 6x jump
		Divine =    { Min = 7500000, Max = 15000000 },  -- 6x jump (massive!)
	},
	
	-- Cookie-clicker style: multiplicative income per level.
	-- Income(level) = baseCPS * (IncomeLevelMultiplier ^ (level-1)) * modifierIncomeMult
	IncomeLevelMultiplier = 1.25, -- +25% income per level
	
	-- Modifier income multipliers (how much more cash modified brainrots earn)
	ModifierIncomeMultiplier = {
		Normal = 1.0,
		Golden = 1.5,
		Diamond = 2,
		Galaxy = 2.5,
		Lava = 3,
		Rainbow = 4.0,
		Arcade = 3.0, -- Same multiplier as Rainbow's CashMultiplier in Shared_Rarity
	},
	
	-- Modifier upgrade cost multipliers (how much more expensive to upgrade)
	-- Rainbow earns 4x cash but costs 5x more to upgrade
	-- Arcade earns 3x cash but costs same as Lava
	ModifierUpgradeCostMultiplier = {
		Normal = 1.0,    -- Baseline
		Golden = 1.1,    -- 50% more expensive
		Diamond = 1.2,   -- 2x more expensive
		Galaxy = 1.3,   -- 2.75x more expensive
		Lava = 1.4,     -- 3.75x more expensive
		Rainbow = 1.5,   -- 5x more expensive
		Arcade = 1.25,    -- Same as Lava (3.75x more expensive)
	},
	
	-- Upgrade cost (derived from income delta, not an independent exponential curve):
	-- Cost(level->level+1) = (Income(level+1)-Income(level)) * PaybackSeconds(level) * ModifierUpgradeCostMult * RarityPaybackMult
	-- This guarantees upgrades always have a predictable ROI (Cookie Clicker feel).
	UpgradePayback = {
		BaseSeconds = 180,            -- target payback at levels 1-10 (3 minutes)
		StepLevels = 10,             -- increase payback every N levels
		-- Two phases: weak growth early, strong growth later
		StepMultiplierPhase1 = 1.5, -- gentle (levels 1–50)
		StepMultiplierPhase2 = 2,  -- steep (level 51+)
		Phase1StepCount = 8,         -- first 8 steps use Phase1 (levels 1–80); step 9+ = Phase2
		-- No MaxSeconds: cost keeps scaling so late-game upgrades stay meaningful
	},
	-- Rarity payback multiplier: high-rarity upgrades cost more "seconds of that slot's income"
	-- so late-game (many Celestials) doesn't make every upgrade trivial.
	RarityPaybackMultiplier = {
		Common = 1.0,
		Rare = 1.25,
		Epic = 1.5,
		Legendary = 1.75,
		Mythical = 2.0,
		Secret = 2.5,
		Celestial = 3,   -- 50% more expensive to upgrade Celestials
		Divine = 4.0,      -- 2x more expensive for Divine
	},
	
	-- Sell worth: expressed as X seconds of production value (plus modifier & optional rebirth mult)
	SellWorthSeconds = 10, -- 10 seconds of that brainrot's current income
}

-- ========================================
-- ECONOMY ROUNDING (professional, scales infinitely)
-- ========================================

--[[
	Professional number rounding for idle/clicker games
	Always produces clean numbers with 1-3 significant figures
	
	Logic:
	- First digit 1-2: Round to nearest 10% of magnitude
	- First digit 3-5: Round to nearest 50% of magnitude  
	- First digit 6-9: Round to nearest full magnitude
	
	Examples:
	- $74.08Sx → $70Sx (digit 7, round to 10Qn)
	- $123.4Sx → $120Sx (digit 1, round to 10Qn)
	- $432Sx → $430Sx (digit 4, round to 50Qn)
]]
local function roundEconomy(value: number): number
	if value <= 0 then return 0 end
	if value < 10 then return math.floor(value + 0.5) end
	
	-- Find the magnitude (power of 10)
	local magnitude = math.floor(math.log10(value))
	local divisor = 10 ^ magnitude
	local firstDigit = math.floor(value / divisor)
	
	-- Determine rounding step based on first digit
	local step
	if firstDigit <= 2 then
		-- For 1xx or 2xx: round to nearest 10% (0.1x the magnitude)
		step = divisor * 0.1
	elseif firstDigit <= 5 then
		-- For 3xx-5xx: round to nearest 50%
		step = divisor * 0.5
	else
		-- For 6xx-9xx: round to nearest full magnitude
		step = divisor
	end
	
	return math.floor(value / step + 0.5) * step
end

Module.List = {
	["67"] = {
		DisplayName = "67",
		Rarity = "Legendary",
		PowerTier = 6,  -- Mid-tier Mythical
		CalloutSound = "rbxassetid://127703147388315",
		NoWorldSpawn = true,  -- Cannot spawn in zones or from lucky blocks (special reward only)
	},
	["69"] = {
		DisplayName = "69",
		Rarity = "Celestial",
		PowerTier = 5,  -- Mid-tier Celestial
		CalloutSound = "rbxassetid://71566058104880",
	},
	["AgarriniLaPallini"] = {
		DisplayName = "Agarrini La Pallini",
		Rarity = "Divine",
		PowerTier = 7,  -- Above-average Divine
		CalloutSound = "rbxassetid://91199009026766",
	},
	["AvocadiniGuffo"] = {
		DisplayName = "Avocadini Guffo",
		Rarity = "Epic",
		PowerTier = 7,  -- Above-average Epic (210 CPS in Tsunami)
		CalloutSound = "rbxassetid://133768184488507",
	},
	["BalerinaCapucina"] = {
		DisplayName = "Balerina Capucina",
		Rarity = "Legendary",
		PowerTier = 4,  -- Below-average Legendary (420 CPS in Tsunami)
		CalloutSound = "rbxassetid://93808589411023",
	},
	["BalerinoLololo"] = {
		DisplayName = "Balerino Lololo",
		Rarity = "Secret",
		PowerTier = 2,  -- Low Secret (8,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://139676553338852",
	},
	["BambiniCrostini"] = {
		DisplayName = "Bambini Crostini",
		Rarity = "Epic",
		PowerTier = 4,  -- Mid-tier Epic (150 CPS in Tsunami)
		CalloutSound = "rbxassetid://108493714442626",
	},
	["BananitoDelfinito"] = {
		DisplayName = "Bananito Delfinito",
		Rarity = "Epic",
		PowerTier = 5,  -- Mid-tier Epic (170 CPS in Tsunami)
		CalloutSound = "rbxassetid://105553663708562",
	},
	["BanditoBobrito"] = {
		DisplayName = "Bandito Bobrito",
		Rarity = "Rare",
		PowerTier = 4,  -- Mid-tier Rare (35 CPS in Tsunami)
		CalloutSound = "rbxassetid://117017197184632",
	},
	["Ben"] = {
		DisplayName = "Ben",
		Rarity = "Divine",
		PowerTier = 6,  -- Mid-tier Divine
		CalloutSound = "rbxassetid://97776339623266",
	},
	["BlueberrinniOctopusini"] = {
		DisplayName = "Blueberrini Octopusini",
		Rarity = "Legendary",
		PowerTier = 5,  -- Mid-tier Legendary (550 CPS in Tsunami)
		CalloutSound = "rbxassetid://100010283971167",
	},
	["BombardiroCrocodilo"] = {
		DisplayName = "Bombardiro Crocodilo",
		Rarity = "Mythical",
		PowerTier = 5,  -- Mid-tier Mythical (3,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://81484828473134",
	},
	["BombombiniGusini"] = {
		DisplayName = "Bombombini Gusini",
		Rarity = "Mythical",
		PowerTier = 4,  -- Below-average Mythical (2,800 CPS in Tsunami)
		CalloutSound = "rbxassetid://71484656055940",
	},
	["BonecaAmbalabu"] = {
		DisplayName = "Boneca Ambalabu",
		Rarity = "Rare",
		PowerTier = 5,  -- Mid-tier Rare (40 CPS in Tsunami)
		CalloutSound = "rbxassetid://113559717256882",
	},
	["BrrBicusDicus"] = {
		DisplayName = "Brr Bicus Dicus",
		Rarity = "Celestial",
		PowerTier = 7,  -- Above-average Celestial
		CalloutSound = "rbxassetid://116090061082222",
	},
	["BrrBrrPatapim"] = {
		DisplayName = "Brr Brr Patapim",
		Rarity = "Epic",
		PowerTier = 1,  -- Lowest Epic (120 CPS in Tsunami)
		CalloutSound = "rbxassetid://138440973714716",
	},
	["BurbaloniLoliloli"] = {
		DisplayName = "Burbaloni Lolioli",
		Rarity = "Legendary",
		PowerTier = 1,  -- Lowest Legendary (290 CPS in Tsunami)
		CalloutSound = "rbxassetid://92776011054820",
	},
	["CactoHipopotamo"] = {
		DisplayName = "Cacto Hipopotamo",
		Rarity = "Rare",
		PowerTier = 6,  -- Above-average Rare (50 CPS in Tsunami)
		CalloutSound = "rbxassetid://133566605406823",
	},
	["CappuccinoAssassino"] = {
		DisplayName = "Cappuccino Assassino",
		Rarity = "Epic",
		PowerTier = 8,  -- High Epic (250 CPS in Tsunami)
		CalloutSound = "rbxassetid://85015489655392",
	},
	["CavalloVirtuoso"] = {
		DisplayName = "Cavallo Virtuoso",
		Rarity = "Mythical",
		PowerTier = 3,  -- Below-average Mythical (2,750 CPS in Tsunami)
		CalloutSound = "rbxassetid://105885551020711",
	},
	["ChefCrabracadabra"] = {
		DisplayName = "Chef Crabracadabra",
		Rarity = "Legendary",
		PowerTier = 6,  -- Above-average Legendary (700 CPS in Tsunami)
		CalloutSound = "rbxassetid://86943862400949",
	},
	["ChicleteiraBicicleteira"] = {
		DisplayName = "Chicleteira Bicicleteira",
		Rarity = "Celestial",
		PowerTier = 6,  -- Above-average Celestial (78,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://90848729978943",
	},
	["ChicleteirinaBicicleteirina"] = {
		DisplayName = "Chicleteirina Bicicleteirina",
		Rarity = "Legendary",
		PowerTier = 10,  -- Top Legendary (1,550 CPS in Tsunami - Smurf Cat level)
		CalloutSound = "rbxassetid://70978480978067",
	},
	["ChillinChili"] = {
		DisplayName = "Chillin Chilli",
		Rarity = "Celestial",
		PowerTier = 2,  -- Low Celestial (27,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://124197124071119",
	},
	["ChimpanziniBananini"] = {
		DisplayName = "Chimpanzini Bananini",
		Rarity = "Legendary",
		PowerTier = 7,  -- Above-average Legendary (800 CPS in Tsunami)
		CalloutSound = "rbxassetid://77555483199311",
	},
	["DragonCannelloni"] = {
		DisplayName = "Dragon Cannelloni",
		Rarity = "Celestial",
		PowerTier = 8,  -- High Celestial (100,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://132232912457311",
	},
	["ElefantoCocofanto"] = {
		DisplayName = "Elefanto Cocofanto",
		Rarity = "Secret",
		PowerTier = 4,  -- Mid-tier Secret (17,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://89572436761350",
	},
	["EsokSekolah"] = {
		DisplayName = "Esok Sekolah",
		Rarity = "Celestial",
		PowerTier = 3,  -- Below-average Celestial (50,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://82044353159804",
	},
	["EspressoSignora"] = {
		DisplayName = "Espresso Signora",
		Rarity = "Mythical",
		PowerTier = 7,  -- Above-average Mythical (3,500 CPS in Tsunami)
		CalloutSound = "rbxassetid://80887212305676",
	},
	["FluriFlura"] = {
		DisplayName = "Fluri Flura",
		Rarity = "Rare",
		PowerTier = 10,  -- Top Rare (90 CPS in Tsunami)
		CalloutSound = "rbxassetid://130873375673656",
	},
	["FrigoCamelo"] = {
		DisplayName = "Frigo Camelo",
		Rarity = "Mythical",
		PowerTier = 1,  -- Lowest Mythical (1,500 CPS in Tsunami)
		CalloutSound = "rbxassetid://129420410582740",
	},
	["GanganzelliTrulala"] = {
		DisplayName = "Ganganzelli Tralala",
		Rarity = "Mythical",
		PowerTier = 10,  -- Top Mythical (5,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://102213410191456",
	},
	["GangsterFootera"] = {
		DisplayName = "Gangster Footera",
		Rarity = "Rare",
		PowerTier = 3,  -- Below-average Rare (30 CPS in Tsunami)
		CalloutSound = "rbxassetid://94428052904630",
	},
	["Garamararam"] = {
		DisplayName = "Garamararam",
		Rarity = "Legendary",
		PowerTier = 8,  -- High Legendary (1,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://80625941125082",
	},
	["GirafaCelestre"] = {
		DisplayName = "Girafa Celestre",
		Rarity = "Secret",
		PowerTier = 1,  -- Lowest Secret (7,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://84485988074572",
	},
	["GlorboFruttodrillo"] = {
		DisplayName = "Glorbo Fruttodrillo",
		Rarity = "Rare",
		PowerTier = 7,  -- Above-average Rare (60 CPS in Tsunami)
		CalloutSound = "rbxassetid://128985768606274",
	},
	["GorilloWatermelondrillo"] = {
		DisplayName = "Gorillo Watermelondrillo",
		Rarity = "Epic",
		PowerTier = 3,  -- Below-average Epic (150 CPS in Tsunami)
		CalloutSound = "rbxassetid://107038227618331",
	},
	["HappyBananaCat"] = {
		DisplayName = "Happy Banana Cat",
		Rarity = "Celestial",
		PowerTier = 4,  -- Mid-tier Celestial (60,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://117030249410899",
	},
	["HappyBananaMeme"] = {
		DisplayName = "Happy Banana Meme",
		Rarity = "Divine",
		PowerTier = 4,  -- Below-average Divine (35,000 CPS in Tsunami - Secret tier)
		CalloutSound = "rbxassetid://75578796392122",
	},
	["Illuminati"] = {
		DisplayName = "Illuminati",
		Rarity = "Divine",
		PowerTier = 10,  -- Top Divine (1,000,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://106038237307843",
	},
	["JobJobJobSahur"] = {
		DisplayName = "Job Job Job Sahur",
		Rarity = "Celestial",
		PowerTier = 9,  -- High Celestial (120,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://122193799389132",
	},
	["KarkerkarKurkur"] = {
		DisplayName = "Karkerkarkurkur",
		Rarity = "Celestial",
		PowerTier = 10,  -- Top Celestial (140,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://108014193550804",
	},
	["LaGrandeCombinasion"] = {
		DisplayName = "La Grande Combinason",
		Rarity = "Celestial",
		PowerTier = 5,  -- Mid-tier Celestial (72,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://88746620356974",
	},
	["LaVaccaSaturnoSaturnita"] = {
		DisplayName = "La Vacca Saturno Saturnita",
		Rarity = "Celestial",
		PowerTier = 1,  -- Lowest Celestial (22,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://139078336048299",
	},
	["Lerulerulerule"] = {
		DisplayName = "Lerulerulerule",
		Rarity = "Celestial",
		PowerTier = 8,  -- High Celestial (110,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://135926306010155",
	},
	["LioneloCactuseli"] = {
		DisplayName = "Lionelo Cactuseli",
		Rarity = "Secret",
		PowerTier = 6,  -- Above-average Secret (25,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://82129358558460",
	},
	["LiriliLarila"] = {
		DisplayName = "Lirili Larila",
		Rarity = "Common",
		PowerTier = 1,  -- Lowest Common (4 CPS in Tsunami)
		CalloutSound = "rbxassetid://100796709036081",
	},
	["LosTralaleritos"] = {
		DisplayName = "Los Tralaleritos",
		Rarity = "Secret",
		PowerTier = 7,  -- Above-average Secret (28,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://71706930606972",
	},
	["Madung"] = {
		DisplayName = "Madung",
		Rarity = "Legendary",
		PowerTier = 9,  -- High Legendary (1,200 CPS in Tsunami)
		CalloutSound = "rbxassetid://127302563764829",
	},
	["Mateo"] = {
		DisplayName = "Mateo",
		Rarity = "Celestial",
		PowerTier = 6,  -- Above-average Celestial (85,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://96483122858512",
	},
	["NyanCat"] = {
		DisplayName = "Nyan Cat",
		Rarity = "Divine",
		PowerTier = 3,  -- Below-average Divine (350,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://106198525007249",
	},
	["OdinDinDinDun"] = {
		DisplayName = "Odin Din Din Dun",
		Rarity = "Secret",
		PowerTier = 8,  -- High Secret (30,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://108848535717093",
	},
	["OrangutiniAnanassini"] = {
		DisplayName = "Orangutini Ananassini",
		Rarity = "Mythical",
		PowerTier = 8,  -- High Mythical (4,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://84633911561339",
	},
	["OrcaleroOrcala"] = {
		DisplayName = "Orcalero Orcala",
		Rarity = "Secret",
		PowerTier = 9,  -- High Secret (32,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://81590257641520",
	},
	["Pakrahmatmamat"] = {
		DisplayName = "Pakrahmatmamat",
		Rarity = "Mythical",
		PowerTier = 9,  -- High Mythical (4,500 CPS in Tsunami)
		CalloutSound = "rbxassetid://103970629759529",
	},
	["Pakrahmatmatina"] = {
		DisplayName = "Pakrahmatmatina",
		Rarity = "Secret",
		PowerTier = 5,  -- Mid-tier Secret (20,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://95308278608936",
	},
	["PandacciniBananini"] = {
		DisplayName = "Pandaccini Bananini",
		Rarity = "Mythical",
		PowerTier = 6,  -- Mid-tier Mythical (3,200 CPS in Tsunami)
		CalloutSound = "rbxassetid://100674633025343",
	},
	["Pepe"] = {
		DisplayName = "Pepe",
		Rarity = "Divine",
		PowerTier = 8,  -- High Divine (650,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://124856711941976",
	},
	["PipiKiwi"] = {
		DisplayName = "Pipi Kiwi",
		Rarity = "Common",
		PowerTier = 6,  -- Above-average Common (13 CPS in Tsunami)
		CalloutSound = "rbxassetid://75755064200975",
	},
	["PipiPotato"] = {
		DisplayName = "Pipi Potato",
		Rarity = "Rare",
		PowerTier = 4,  -- Mid-tier Rare (35 CPS in Tsunami)
		CalloutSound = "rbxassetid://107427636086490",
	},
	["PotHotspot"] = {
		DisplayName = "Pot Hotspot",
		Rarity = "Celestial",
		PowerTier = 7,  -- Above-average Celestial (95,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://128121053034953",
	},
	["RhinoToasterino"] = {
		DisplayName = "Rhino Toasterino",
		Rarity = "Epic",
		PowerTier = 9,  -- High Epic (320 CPS in Tsunami)
		CalloutSound = "rbxassetid://118398638142360",
	},
	["SkibidiToilet"] = {
		DisplayName = "Skibidi Toilet",
		Rarity = "Divine",
		PowerTier = 9,  -- High Divine (850,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://122262396216405",
	},
	["SmurfCat"] = {
		DisplayName = "Smurf Cat",
		Rarity = "Legendary",
		PowerTier = 10,  -- Top Legendary (1,550 CPS in Tsunami)
		CalloutSound = "rbxassetid://80704096050723",
	},
	["StrawberryElephant"] = {
		DisplayName = "Strawberry Elephant",
		Rarity = "Celestial",
		PowerTier = 9,  -- High Celestial (125,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://95418943320376",
	},
	["StrawberrelliFlamingelli"] = {
		DisplayName = "Strawberrelli Flamingelli",
		Rarity = "Legendary",
		PowerTier = 9,  -- High Legendary (1,300 CPS in Tsunami)
		CalloutSound = "rbxassetid://128311028894383",
	},
	["SvininaBombardino"] = {
		DisplayName = "Svinina Bombardino",
		Rarity = "Common",
		PowerTier = 4,  -- Mid Common (11 CPS in Tsunami)
		CalloutSound = "rbxassetid://88538012700158",
	},
	["SwagSoda"] = {
		DisplayName = "Swag Soda",
		Rarity = "Epic",
		PowerTier = 10,  -- Top Epic (400 CPS in Tsunami)
		CalloutSound = "rbxassetid://73789966269726",
	},
	["TalpaDiFero"] = {
		DisplayName = "Talpa Di Ferro",
		Rarity = "Common",
		PowerTier = 3,  -- Below-average Common (9 CPS in Tsunami)
		CalloutSound = "rbxassetid://91967343629818",
	},
	["TatatataSahur"] = {
		DisplayName = "Tatatata Sahur",
		Rarity = "Rare",
		PowerTier = 7,  -- Above-average Rare (55 CPS in Tsunami)
		CalloutSound = "rbxassetid://77383070906611",
	},
	["TigroligreFrutonni"] = {
		DisplayName = "Tigroligre Frutonni",
		Rarity = "Mythical",
		PowerTier = 7,  -- Above-average Mythical (3,750 CPS in Tsunami)
		CalloutSound = "rbxassetid://132110456318439",
	},
	["TimCheese"] = {
		DisplayName = "Tim Cheese",
		Rarity = "Common",
		PowerTier = 10,  -- Top Common (15 CPS in Tsunami)
		CalloutSound = "rbxassetid://120497173089336",
	},
	["TirilikalikaTirilikalako"] = {
		DisplayName = "Tirilikalika Tirilikalako",
		Rarity = "Mythical",
		PowerTier = 8,  -- High Mythical (4,200 CPS in Tsunami)
		CalloutSound = "rbxassetid://97695907342992",
	},
	["TorrtuginniDragonfrutini"] = {
		DisplayName = "Tortugini Dragonfrutini",
		Rarity = "Celestial",
		PowerTier = 6,  -- Above-average Celestial (82,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://116041074584199",
	},
	["Tralaledon"] = {
		DisplayName = "Tralaledon",
		Rarity = "Secret",
		PowerTier = 3,  -- Below-average Secret (15,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://78162461152051",
	},
	["TralaleroTralala"] = {
		DisplayName = "Tralalero Tralala",
		Rarity = "Secret",
		PowerTier = 4,  -- Mid-tier Secret (18,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://100789099731611",
	},
	["TralalitaTralala"] = {
		DisplayName = "Tralalita Tralala",
		Rarity = "Celestial",
		PowerTier = 7,  -- Above-average Celestial (92,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://119662825433470",
	},
	["TricTracBarabum"] = {
		DisplayName = "Tric Trac Barabum",
		Rarity = "Rare",
		PowerTier = 8,  -- High Rare (70 CPS in Tsunami)
		CalloutSound = "rbxassetid://108850294021647",
	},
	["TriplitoTralaleritos"] = {
		DisplayName = "Triplito Tralaleritos",
		Rarity = "Celestial",
		PowerTier = 8,  -- High Celestial (105,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://108316844182088",
	},
	["TrippiTroppi"] = {
		DisplayName = "Trippi Troppi",
		Rarity = "Rare",
		PowerTier = 1,  -- Lowest Rare (20 CPS in Tsunami)
		CalloutSound = "rbxassetid://137792299735043",
	},
	["TrippiTroppiTroppaTrippa"] = {
		DisplayName = "Trippi Troppi Trippa Trapp",
		Rarity = "Legendary",
		PowerTier = 8,  -- High Legendary (950 CPS in Tsunami)
		CalloutSound = "rbxassetid://87819330144551",
	},
	["Trollface"] = {
		DisplayName = "Trollface",
		Rarity = "Divine",
		PowerTier = 5,  -- Mid Divine (500,000 CPS in Tsunami)
		CalloutSound = "rbxassetid://86192504093621",
	},
	["TrulimeroTrulicina"] = {
		DisplayName = "Trulimero Trulicina",
		Rarity = "Epic",
		PowerTier = 2,  -- Low Epic (135 CPS in Tsunami)
		CalloutSound = "rbxassetid://97607554553553",
	},
	["TungTungSahur"] = {
		DisplayName = "Tung Tung Sahur",
		Rarity = "Legendary",
		PowerTier = 10,  -- Top Legendary (1,450 CPS in Tsunami)
		CalloutSound = "rbxassetid://88731650286487",
	},
	["ZibraZubraZibralini"] = {
		DisplayName = "Zibra Zubra Zibralini",
		Rarity = "Mythical",
		PowerTier = 5,  -- Mid Mythical (3,100 CPS in Tsunami)
		CalloutSound = "rbxassetid://84824043761261",
	},
}

-- Modifier data (Golden/Diamond/etc variants – DisplayName, CashMultiplier, Color)
Module.ModifierData = {
	["Normal"] = {
		DisplayName = "Normal",
		CashMultiplier = 1,
		Color = Color3.fromRGB(255, 255, 255),
	},
	["Golden"] = {
		DisplayName = "Golden",
		CashMultiplier = 1.25,
		Color = Color3.fromRGB(255, 200, 0),
	},
	["Diamond"] = {
		DisplayName = "Diamond",
		CashMultiplier = 1.5,
		Color = Color3.fromRGB(100, 220, 255),
	},
	["Galaxy"] = {
		DisplayName = "Galaxy",
		CashMultiplier = 1.85,
		Color = Color3.fromRGB(200, 100, 255),
	},
	["Lava"] = {
		DisplayName = "Lava",
		CashMultiplier = 2.35,
		Color = Color3.fromRGB(255, 100, 28),
	},
	["Rainbow"] = {
		DisplayName = "Rainbow",
		CashMultiplier = 3,
		Color = Color3.fromRGB(255, 0, 127),
	},
}

-- ========================================
-- BALANCE CALCULATION FUNCTIONS
-- ========================================

--[[
	Calculate base CashPerSecond for a brainrot at level 1, Normal modifier
	Uses PowerTier to interpolate between Min and Max for the rarity
	@param configName string - Brainrot config key
	@return number - Base cash per second
]]
function Module:GetBaseCashPerSecond(configName: string): number
	local config = self.List[configName]
	if not config then 
		warn("⚠️ Unknown brainrot: " .. tostring(configName))
		return 0 
	end
	
	local rarityRange = self.BalanceConfig.RarityBaseIncome[config.Rarity]
	if not rarityRange then 
		warn("⚠️ Unknown rarity: " .. tostring(config.Rarity))
		return 0 
	end
	
	-- Default to middle tier if PowerTier not set
	local powerTier = config.PowerTier or 5
	local min, max = rarityRange.Min, rarityRange.Max
	
	-- Linear interpolation: PowerTier 1 = Min, PowerTier 10 = Max
	local cashPerSecond = min + ((max - min) * (powerTier - 1) / 9)
	
	return math.floor(cashPerSecond)
end

-- Internal: raw cash/s (no rounding). Used for consistent delta calculations.
local function getRawCashPerSecond(moduleSelf, configName: string, level: number, modifier: string): number
	local baseCPS = moduleSelf:GetBaseCashPerSecond(configName)
	local modMultiplier = moduleSelf.BalanceConfig.ModifierIncomeMultiplier[modifier] or 1
	local incomeLevelMult = moduleSelf.BalanceConfig.IncomeLevelMultiplier or 1.0
	
	local safeLevel = math.max(1, level or 1)
	local levelFactor = incomeLevelMult ^ (safeLevel - 1)
	
	return baseCPS * levelFactor * modMultiplier
end

--[[
	Calculate actual CashPerSecond with level and modifier applied
	@param configName string
	@param level number
	@param modifier string - "Normal", "Golden", "Diamond", etc.
	@return number - Total cash per second
]]
function Module:GetCashPerSecond(configName: string, level: number, modifier: string): number
	local rawIncome = getRawCashPerSecond(self, configName, level, modifier)
	return roundEconomy(rawIncome)
end

-- Internal: upgrade payback target in seconds for a given level (two-phase step curve).
function Module:GetUpgradePaybackSeconds(level: number): number
	local cfg = self.BalanceConfig.UpgradePayback
	if not cfg then return 180 end
	
	local safeLevel = math.max(1, level or 1)
	local stepLevels = cfg.StepLevels or 10
	local steps = math.floor((safeLevel - 1) / stepLevels)
	
	local base = cfg.BaseSeconds or 180
	local phase1Count = cfg.Phase1StepCount or 5
	local mult1 = cfg.StepMultiplierPhase1 or 1.25
	local mult2 = cfg.StepMultiplierPhase2 or 1.9
	
	local seconds
	if steps <= phase1Count then
		seconds = base * (mult1 ^ steps)
	else
		seconds = base * (mult1 ^ phase1Count) * (mult2 ^ (steps - phase1Count))
	end
	
	local maxSeconds = cfg.MaxSeconds
	if typeof(maxSeconds) == "number" then
		seconds = math.min(seconds, maxSeconds)
	end
	
	return seconds
end

--[[
	Calculate upgrade cost for a brainrot
	Cookie-clicker style (linked to income delta):
	Cost(level->level+1) = (Income(level+1)-Income(level)) * PaybackSeconds(level) * ModifierUpgradeCostMult
	@param configName string
	@param currentLevel number
	@param modifier string - "Normal", "Golden", "Diamond", etc.
	@return number - Cost to upgrade from currentLevel to currentLevel+1
]]
function Module:GetUpgradeCost(configName: string, currentLevel: number, modifier: string): number
	if not self.List[configName] then return 0 end
	
	local config = self.List[configName]
	local safeLevel = math.max(1, currentLevel or 1)
	if safeLevel >= (self.MaxLevel or 150) then
		return 0
	end
	local incomeNow = getRawCashPerSecond(self, configName, safeLevel, modifier)
	local incomeNext = getRawCashPerSecond(self, configName, safeLevel + 1, modifier)
	local delta = math.max(0, incomeNext - incomeNow)
	
	local paybackSeconds = self:GetUpgradePaybackSeconds(safeLevel)
	local rarityMult = (self.BalanceConfig.RarityPaybackMultiplier and self.BalanceConfig.RarityPaybackMultiplier[config.Rarity]) or 1.0
	paybackSeconds = paybackSeconds * rarityMult
	
	local modifierCostMult = self.BalanceConfig.ModifierUpgradeCostMultiplier[modifier] or 1.0
	
	local rawCost = delta * paybackSeconds * modifierCostMult
	return roundEconomy(rawCost)
end

-- ========================================
-- ECONOMY FUNCTIONS
-- ========================================

--[[
	Calculate sell worth of a brainrot
	@param configName string - Brainrot config key (e.g. "LiriliLarila")
	@param level number - Brainrot level (1-100)
	@param modifier string - Modifier ("Normal", "Golden", etc.)
	@param rebirths number? - Optional: apply rebirth cash multiplier
	@return number - Total sell worth
]]
function Module:CalculateSellWorth(configName: string, level: number, modifier: string, rebirths: number?): number
	local config = self.List[configName]
	if not config then 
		warn("⚠️ Unknown brainrot config: " .. tostring(configName))
		return 0 
	end
	
	-- Sell worth = X seconds of this brainrot's current production (clean + predictable)
	local safeLevel = math.max(1, level or 1)
	local income = getRawCashPerSecond(self, configName, safeLevel, modifier)
	local secondsWorth = self.BalanceConfig.SellWorthSeconds or 120
	
	-- Rebirth multiplier (optional - player gets bonus for their progression)
	local rebirthMult = 1
	if rebirths and rebirths > 0 then
		local Shared_RebirthRewards = require(ReplicatedStorage.Modules.Settings.Shared_RebirthRewards)
		rebirthMult = Shared_RebirthRewards:GetCashMultiplier(rebirths)
	end
	
	local rawWorth = income * secondsWorth * rebirthMult
	return roundEconomy(rawWorth)
end

--[[
	Calculate total worth of all brainrots in inventory
	@param inventory table - Player inventory { [uid] = itemData }
	@param rebirths number? - Optional: apply rebirth multiplier
	@return number - Total worth
	@return number - Count of brainrots found
]]
function Module:CalculateInventoryWorth(inventory: {[string]: any}, rebirths: number?): (number, number)
	local total = 0
	local count = 0
	
	for _, itemData in pairs(inventory) do
		if itemData.Type == "Brainrot" then
			local worth = self:CalculateSellWorth(
				itemData.ConfigName,
				itemData.Level or 1,
				itemData.Modifier or "Normal",
				rebirths
			)
			total += worth
			count += 1
		end
	end
	
	return total, count
end

-- Sound lengths for each brainrot (in seconds)
-- Generated using GetSoundLengths.lua script
Module.SoundLengths = {
	["BrrBicusDicus"] = 1.40,
	["Pakrahmatmatina"] = 1.47,
	["GlorboFruttodrillo"] = 1.71,
	["67"] = 1.20,
	["FrigoCamelo"] = 1.19,
	["BalerinoLololo"] = 1.19,
	["EspressoSignora"] = 1.47,
	["DragonCannelloni"] = 1.41,
	["ChicleteirinaBicicleteirina"] = 1.97,
	["BalerinaCapucina"] = 1.40,
	["TricTracBarabum"] = 1.26,
	["SvininaBombardino"] = 1.52,
	["CappuccinoAssassino"] = 1.27,
	["OrcaleroOrcala"] = 1.61,
	["GangsterFootera"] = 1.37,
	["ChimpanziniBananini"] = 1.65,
	["Mateo"] = 1.28,
	["ElefantoCocofanto"] = 1.47,
	["BananitoDelfinito"] = 1.41,
	["BlueberrinniOctopusini"] = 1.76,
	["LiriliLarila"] = 1.10,
	["AgarriniLaPallini"] = 1.33,
	["PipiPotato"] = 1.04,
	["LosTralaleritos"] = 1.38,
	["StrawberryElephant"] = 1.43,
	["HappyBananaMeme"] = 1.28,
	["OdinDinDinDun"] = 1.79,
	["Lerulerulerule"] = 1.33,
	["Pepe"] = 0.54,
	["SwagSoda"] = 1.10,
	["AvocadiniGuffo"] = 1.21,
	["TriplitoTralaleritos"] = 1.57,
	["TirilikalikaTirilikalako"] = 2.10,
	["BombardiroCrocodilo"] = 1.62,
	["ChillinChili"] = 0.95,
	["BombombiniGusini"] = 1.43,
	["ChefCrabracadabra"] = 1.30,
	["Madung"] = 0.67,
	["GanganzelliTrulala"] = 1.53,
	["GorilloWatermelondrillo"] = 2.17,
	["LaGrandeCombinasion"] = 1.54,
	["69"] = 1.13,
	["CactoHipopotamo"] = 1.14,
	["PandacciniBananini"] = 1.61,
	["TungTungSahur"] = 1.95,
	["SkibidiToilet"] = 1.21,
	["RhinoToasterino"] = 1.42,
	["TrippiTroppi"] = 1,
	["PipiKiwi"] = 0.90,
	["Trollface"] = 0.96,
	["GirafaCelestre"] = 1.39,
	["EsokSekolah"] = 1.21,
	["ZibraZubraZibralini"] = 1.81,
	["TralalitaTralala"] = 1.33,
	["BonecaAmbalabu"] = 1.23,
	["BurbaloniLoliloli"] = 1.37,
	["TralaleroTralala"] = 1.25,
	["BanditoBobrito"] = 1.47,
	["CavalloVirtuoso"] = 1.37,
	["JobJobJobSahur"] = 2.01,
	["BambiniCrostini"] = 1.33,
	["BrrBrrPatapim"] = 1.24,
	["Ben"] = 0.62,
	["TalpaDiFero"] = 1.14,
	["LioneloCactuseli"] = 1.48,
	["HappyBananaCat"] = 1.27,
	["Pakrahmatmamat"] = 1.28,
	["Illuminati"] = 0.95,
	["KarkerkarKurkur"] = 1.21,
	["TimCheese"] = 0.91,
	["LaVaccaSaturnoSaturnita"] = 1.77,
	["ChicleteiraBicicleteira"] = 1.61,
	["OrangutiniAnanassini"] = 1.90,
	["StrawberrelliFlamingelli"] = 1.89,
	["SmurfCat"] = 1.14,
	["TatatataSahur"] = 1.42,
	["TigroligreFrutonni"] = 1.56,
	["NyanCat"] = 0.92,
	["TrippiTroppiTroppaTrippa"] = 1.45,
	["TrulimeroTrulicina"] = 1.49,
	["TorrtuginniDragonfrutini"] = 1.83,
	["Tralaledon"] = 0.92,
	["PotHotspot"] = 1.08,
	["FluriFlura"] = 1.06,
	["Garamararam"] = 1.04,
}

function Module:GetPlotScale(level: number): number
	local scaleMaxLevel = math.max(1, self.PlotScaleMaxLevel or 100)
	local minScale = self.PlotScaleMin or 0.75
	local maxScale = self.PlotScaleMax or 2.75
	local safeLevel = math.clamp(level or 1, 1, scaleMaxLevel)
	if scaleMaxLevel <= 1 then
		return maxScale
	end
	local t = (safeLevel - 1) / (scaleMaxLevel - 1)
	return minScale + (maxScale - minScale) * t
end

return Module
