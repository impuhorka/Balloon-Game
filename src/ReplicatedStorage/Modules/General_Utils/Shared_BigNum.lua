--// Shared_BigNum - Mantissa-Exponent system for numbers beyond 2^53
--// Supports numbers up to 10^308 (and beyond with proper handling)

local Module = {}

--[[
	Big Number Format:
	{
		m = number,  -- Mantissa (1-10 range, e.g., 1.5)
		e = number   -- Exponent (power of 10, e.g., 21 for Sx)
	}
	
	Example: 1.5 Sx = {m = 1.5, e = 21} = 1.5 × 10^21
]]

local MAX_SAFE_INTEGER = 9007199254740992 -- 2^53

--[[
	Create a BigNum from a regular number
	@param value number - Regular Lua number
	@return table - BigNum {m, e}
]]
function Module:FromNumber(value: number)
	if value == 0 or value ~= value then -- 0 or NaN
		return {m = 0, e = 0}
	end
	
	if value == math.huge then
		return {m = 1, e = 308}
	end
	
	if value < 0 then
		warn("⚠️ BigNum: Negative numbers not supported, using absolute value")
		value = math.abs(value)
	end
	
	-- Calculate exponent using log10
	local exponent = math.floor(math.log10(value))
	local mantissa = value / (10 ^ exponent)
	
	-- Normalize mantissa to 1-10 range
	if mantissa >= 10 then
		mantissa = mantissa / 10
		exponent = exponent + 1
	elseif mantissa < 1 and mantissa > 0 then
		mantissa = mantissa * 10
		exponent = exponent - 1
	end
	
	return {m = mantissa, e = exponent}
end

--[[
	Convert BigNum to regular number (if possible)
	@param bigNum table - BigNum {m, e}
	@return number - Regular number or math.huge if too large
]]
function Module:ToNumber(bigNum)
	if not bigNum or type(bigNum) ~= "table" then
		return 0
	end
	
	-- Handle legacy regular numbers
	if type(bigNum) == "number" then
		return bigNum
	end
	
	local m = bigNum.m or 0
	local e = bigNum.e or 0
	
	if m == 0 then return 0 end
	
	-- If exponent is too high, return infinity
	if e > 308 then
		return math.huge
	end
	
	-- Calculate actual value
	local result = m * (10 ^ e)
	
	-- Clamp to prevent overflow
	if result == math.huge then
		return math.huge
	end
	
	return result
end

--[[
	Add two BigNums
	@param a table - BigNum
	@param b table - BigNum
	@return table - Result BigNum
]]
function Module:Add(a, b)
	-- Convert to BigNum if needed
	if type(a) == "number" then a = self:FromNumber(a) end
	if type(b) == "number" then b = self:FromNumber(b) end
	
	local m1, e1 = a.m or 0, a.e or 0
	local m2, e2 = b.m or 0, b.e or 0
	
	if m1 == 0 then return {m = m2, e = e2} end
	if m2 == 0 then return {m = m1, e = e1} end
	
	-- Align exponents
	local diff = e1 - e2
	if diff > 15 then
		-- a is much larger, b is negligible
		return {m = m1, e = e1}
	elseif diff < -15 then
		-- b is much larger, a is negligible
		return {m = m2, e = e2}
	end
	
	-- Convert to same exponent (use larger one)
	local targetExp = math.max(e1, e2)
	local adjustedM1 = m1 * (10 ^ (e1 - targetExp))
	local adjustedM2 = m2 * (10 ^ (e2 - targetExp))
	
	local sumMantissa = adjustedM1 + adjustedM2
	
	-- Normalize
	return self:FromNumber(sumMantissa * (10 ^ targetExp))
end

--[[
	Multiply two BigNums
	@param a table - BigNum
	@param b table - BigNum or number
	@return table - Result BigNum
]]
function Module:Multiply(a, b)
	-- Convert to BigNum if needed
	if type(a) == "number" then a = self:FromNumber(a) end
	if type(b) == "number" then b = self:FromNumber(b) end
	
	local m1, e1 = a.m or 0, a.e or 0
	local m2, e2 = b.m or 0, b.e or 0
	
	if m1 == 0 or m2 == 0 then
		return {m = 0, e = 0}
	end
	
	local newMantissa = m1 * m2
	local newExponent = e1 + e2
	
	-- Normalize mantissa to 1-10 range
	if newMantissa >= 10 then
		local adjustment = math.floor(math.log10(newMantissa))
		newMantissa = newMantissa / (10 ^ adjustment)
		newExponent = newExponent + adjustment
	elseif newMantissa < 1 and newMantissa > 0 then
		local adjustment = math.floor(math.log10(newMantissa))
		newMantissa = newMantissa / (10 ^ adjustment)
		newExponent = newExponent + adjustment
	end
	
	return {m = newMantissa, e = newExponent}
end

--[[
	Compare two BigNums
	@param a table - BigNum
	@param b table - BigNum
	@return number - 1 if a > b, -1 if a < b, 0 if equal
]]
function Module:Compare(a, b)
	if type(a) == "number" then a = self:FromNumber(a) end
	if type(b) == "number" then b = self:FromNumber(b) end
	
	local m1, e1 = a.m or 0, a.e or 0
	local m2, e2 = b.m or 0, b.e or 0
	
	-- Compare exponents first
	if e1 > e2 then return 1 end
	if e1 < e2 then return -1 end
	
	-- Same exponent, compare mantissas
	if m1 > m2 then return 1 end
	if m1 < m2 then return -1 end
	
	return 0
end

--[[
	Check if BigNum is greater than another
	@param a table - BigNum
	@param b table - BigNum
	@return boolean
]]
function Module:GreaterThan(a, b)
	return self:Compare(a, b) == 1
end

--[[
	Check if BigNum is less than another
	@param a table - BigNum
	@param b table - BigNum
	@return boolean
]]
function Module:LessThan(a, b)
	return self:Compare(a, b) == -1
end

--[[
	Compress BigNum for OrderedDataStore using log scale
	@param bigNum table - BigNum {m, e}
	@return number - Compressed sortable value for OrderedDataStore
]]
function Module:CompressForLeaderboard(bigNum)
	if type(bigNum) == "number" then
		bigNum = self:FromNumber(bigNum)
	end
	
	local value = self:ToNumber(bigNum)
	
	if value <= 0 then return 0 end
	if value == math.huge then return 9e15 end -- Max sortable value
	
	-- Logarithmic compression (industry standard for simulators)
	return math.log10(value + 1) * 29921268260572600
end

--[[
	Format BigNum for display using suffix system
	@param bigNum table - BigNum {m, e}
	@return string - Formatted string (e.g., "1.5 Sx")
]]
function Module:ToString(bigNum)
	if type(bigNum) == "number" then
		bigNum = self:FromNumber(bigNum)
	end
	
	local m = bigNum.m or 0
	local e = bigNum.e or 0
	
	if m == 0 then return "0" end
	
	local Suffixes = {"", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No", "De", "UDe", "DDe", "TDe", "QtDe", "QnDe", "SxDe", "SpDe", "OcDe", "NoDe",
		"Vg", "UVg", "DVg", "TVg", "QtVg", "QnVg", "SxVg", "SpVg", "OcVg", "NoVg", "Tg", "UTg", "DTg", "TTg", "QdTg", "QnTg", "SxTg", "SpTg", "OcTg", "NoTg",
		"qg", "Uqg", "Dqg", "Tqg", "Qdqg", "Qnqg", "Sxqg", "Spqg", "Ocqg", "Noqg", "Qg", "UQg", "DQg", "TQg", "QdQg", "QnQg", "SxQg", "SpQg", "OcQg", "NoQg",
		"sg", "Usg", "Dsg", "Tsg", "Qdsg", "Qnsg", "Sxsg", "Spsg", "Ocsg", "Nosg", "Sg", "USg", "DSg", "TSg", "QdSg", "QnSg", "SxSg", "SpSg", "OcSg", "NoSg", "Og",
		"UOg", "DOg", "TOg", "QdOg", "QnOg", "SxOg", "SpOg", "OcOg", "NoOg", "Ng", "UNg", "DNg", "TNg", "QdNg", "QnNg", "SxNg", "SpNg", "OcNg", "NoNg", "Ce"}
	
	-- Calculate suffix index (every 3 exponents = 1 suffix)
	local suffixIndex = math.floor(e / 3) + 1
	
	if suffixIndex > #Suffixes then
		-- Beyond our suffix range, use scientific notation
		return string.format("%.2fe+%d", m, e)
	end
	
	-- Calculate display mantissa for this suffix
	local remainder = e % 3
	local displayMantissa = m * (10 ^ remainder)
	
	-- Format mantissa
	local formatted
	if displayMantissa == math.floor(displayMantissa) then
		formatted = tostring(math.floor(displayMantissa))
	else
		if suffixIndex == 1 then
			-- No suffix: 1 decimal for <10
			if displayMantissa < 10 then
				formatted = string.format("%.1f", displayMantissa)
			else
				formatted = tostring(math.floor(displayMantissa + 0.5))
			end
		else
			-- With suffix: 2 decimals
			formatted = string.format("%.2f", displayMantissa)
		end
		formatted = formatted:gsub("%.?0+$", "")
	end
	
	return formatted .. Suffixes[suffixIndex]
end

--[[
	Check if value is a BigNum
	@param value any
	@return boolean
]]
function Module:IsBigNum(value)
	return type(value) == "table" and value.m ~= nil and value.e ~= nil
end

--[[
	Normalize any input to BigNum
	@param value number|table - Regular number or BigNum
	@return table - BigNum
]]
function Module:Normalize(value)
	if type(value) == "number" then
		return self:FromNumber(value)
	elseif self:IsBigNum(value) then
		return value
	else
		return {m = 0, e = 0}
	end
end

return Module
