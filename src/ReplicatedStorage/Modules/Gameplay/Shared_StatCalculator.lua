--[[
	Shared_StatCalculator.lua
	
	Centralized stat calculation formulas
	Shared between client (for preview) and server (for validation)
]]

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

-- ========================================
-- MODULE
-- ========================================

local Module = {}

-- Configuration (balance these values)
Module.Config = {
	-- Speed
	BaseSpeed = 20, -- Starting walk speed when Speed stat is 0
	SpeedPerUpgrade = 1, -- Each Speed stat point = +1 stud/second
	
	-- Cost formula (SINGLE SOURCE OF TRUTH for speed costs)
	SpeedBaseCost = 250, -- Cost of first speed upgrade
	SpeedCostRatio = 1.24, -- +20% per level (nerfed from 1.36) → more gradual curve
	
	-- Purchase increments
	SpeedIncrements = {1, 5, 10}, -- Available purchase amounts
	
	-- Rebirth requirements
	RebirthSpeedRequired = 30, -- Speed needed for first rebirth (increases per rebirth)
	RebirthSpeedIncrement = 10, -- Additional speed per rebirth level (1-10)
	RebirthSpeedIncrementHigh = 20, -- Additional speed per rebirth level (11+)
}

--[[
	Calculate effective walk speed from Speed stat
	@param speedStat number - Player's Speed stat value
	@return number - Effective walk speed in studs/second
]]
function Module.CalculateWalkSpeed(speedStat: number): number
	return Module.Config.BaseSpeed + (speedStat * Module.Config.SpeedPerUpgrade)
end

--[[
	Calculate cost for upgrading Speed
	Uses geometric series formula: Cost = BaseCost * Ratio^CurrentSpeed * (Ratio^SpeedToAdd - 1) / (Ratio - 1)
	
	@param currentSpeed number - Current Speed stat value
	@param speedToAdd number - Amount of Speed to add
	@param currentRebirths number? - Current Rebirth count (optional, for tutorial free upgrade)
	@return number - Total cost for the upgrade
]]
function Module.CalculateSpeedCost(currentSpeed: number, speedToAdd: number, currentRebirths: number?): number
	if speedToAdd <= 0 then return 0 end
	
	-- Tutorial: First speed upgrade is free for rebirth 0 players only
	if currentRebirths == 0 and currentSpeed == 0 and speedToAdd == 1 then
		return 0
	end
	
	local baseCost = Module.Config.SpeedBaseCost
	local ratio = Module.Config.SpeedCostRatio
	
	-- Geometric series formula for cumulative cost
	local startExponent = currentSpeed
	local count = speedToAdd
	
	local totalCost = baseCost * (ratio ^ startExponent) * (ratio ^ count - 1) / (ratio - 1)
	
	return roundEconomy(totalCost)
end

--[[
	Get cost breakdown for each increment option
	@param currentSpeed number - Current Speed stat value
	@param currentRebirths number? - Current Rebirth count (optional, for tutorial free upgrade)
	@return table - Array of {increment, cost} pairs
]]
function Module.GetSpeedUpgradeOptions(currentSpeed: number, currentRebirths: number?): {{increment: number, cost: number}}
	local options = {}
	
	for _, increment in ipairs(Module.Config.SpeedIncrements) do
		local cost = Module.CalculateSpeedCost(currentSpeed, increment, currentRebirths)
		table.insert(options, {
			increment = increment,
			cost = cost,
		})
	end
	
	return options
end

--[[
	Validate if a speed purchase is legal
	@param currentSpeed number - Current Speed stat
	@param speedToAdd number - Requested speed to add
	@param playerCash number - Player's current cash
	@param currentRebirths number? - Current Rebirth count (optional, for tutorial free upgrade)
	@return boolean, string? - (isValid, errorMessage)
]]
function Module.ValidateSpeedPurchase(currentSpeed: number, speedToAdd: number, playerCash: number, currentRebirths: number?): (boolean, string?)
	-- Check if increment is valid
	local validIncrement = false
	for _, allowed in ipairs(Module.Config.SpeedIncrements) do
		if speedToAdd == allowed then
			validIncrement = true
			break
		end
	end
	
	if not validIncrement then
		return false, "Invalid speed increment"
	end
	
	-- Check if player has enough cash
	local cost = Module.CalculateSpeedCost(currentSpeed, speedToAdd, currentRebirths)
	if playerCash < cost then
		return false, "Not enough cash"
	end
	
	return true, nil
end

--[[
	Calculate speed required for next rebirth
	@param currentRebirths number - Current rebirth count
	@return number - Speed required for next rebirth
]]
function Module.CalculateSpeedForRebirth(currentRebirths: number): number
	-- After rebirth 10, use higher increment
	if currentRebirths >= 10 then
		local earlyRebirthCost = Module.Config.RebirthSpeedRequired + (Module.Config.RebirthSpeedIncrement * 10)
		local additionalRebirths = currentRebirths - 10
		return earlyRebirthCost + (Module.Config.RebirthSpeedIncrementHigh * additionalRebirths)
	else
		return Module.Config.RebirthSpeedRequired + (Module.Config.RebirthSpeedIncrement * currentRebirths)
	end
end

--[[
	Check if player can rebirth
	@param currentSpeed number - Current Speed stat
	@param currentRebirths number - Current Rebirth count
	@return boolean, string? - (canRebirth, errorMessage)
]]
function Module.CanRebirth(currentSpeed: number, currentRebirths: number): (boolean, string?)
	local speedRequired = Module.CalculateSpeedForRebirth(currentRebirths)
	
	if currentSpeed < speedRequired then
		return false, string.format("Need %d speed (you have %d)", speedRequired, currentSpeed)
	end
	
	return true, nil
end

return Module
