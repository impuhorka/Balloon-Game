local Module = {}

-- Load BigNum for handling large numbers
local BigNum = require(script.Parent.Shared_BigNum)

function Module:Number(Val)
	-- Handle BigNum format {m, e}
	if type(Val) == "table" and Val.m and Val.e then
		return BigNum:ToString(Val)
	end
	
	-- Handle regular numbers
	if type(Val) ~= "number" then
		return "0"
	end
	
	-- Handle infinity
	if Val == math.huge or Val >= 1e308 or Val ~= Val then -- NaN check: Val ~= Val
		return "∞"
	end
	
	-- If number exceeds safe integer range, convert to BigNum
	if Val > 9007199254740992 then
		local bigNum = BigNum:FromNumber(Val)
		return BigNum:ToString(bigNum)
	end
	
	local Suffixes = {"", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No", "De", "UDe", "DDe", "TDe", "QtDe", "QnDe", "SxDe", "SpDe", "OcDe", "NoDe",
		"Vg", "UVg", "DVg", "TVg", "QtVg", "QnVg", "SxVg", "SpVg", "OcVg", "NoVg", "Tg", "UTg", "DTg", "TTg", "QdTg", "QnTg", "SxTg", "SpTg", "OcTg", "NoTg",
		"qg", "Uqg", "Dqg", "Tqg", "Qdqg", "Qnqg", "Sxqg", "Spqg", "Ocqg", "Noqg", "Qg", "UQg", "DQg", "TQg", "QdQg", "QnQg", "SxQg", "SpQg", "OcQg", "NoQg",
		"sg", "Usg", "Dsg", "Tsg", "Qdsg", "Qnsg", "Sxsg", "Spsg", "Ocsg", "Nosg", "Sg", "USg", "DSg", "TSg", "QdSg", "QnSg", "SxSg", "SpSg", "OcSg", "NoSg", "Og",
		"UOg", "DOg", "TOg", "QdOg", "QnOg", "SxOg", "SpOg", "OcOg", "NoOg", "Ng", "UNg", "DNg", "TNg", "QdNg", "QnNg", "SxNg", "SpNg", "OcNg", "NoNg", "Ce"}
	for i = 1, #Suffixes do
		if tonumber(Val) < 10^(i*3) then
			local divisor = 10 ^ ((i-1) * 3)
			local result = Val / divisor
			
			-- Whole numbers: show as integer
			if result == math.floor(result) then
				return tostring(math.floor(result)) .. Suffixes[i]
			else
				-- Decimals: different rules for raw vs suffixed numbers
				local formatted
				if i == 1 then
					-- Raw numbers (no suffix): 1 decimal for <10, whole number for >=10
					if result < 10 then
						formatted = string.format("%.1f", result)
						formatted = formatted:gsub("%.?0+$", "") -- Remove trailing zeros
					else
						-- >= 10: whole number only
						formatted = tostring(math.floor(result + 0.5))
					end
				else
					-- Suffixed numbers (K, M, B, etc.): always 2 decimals
					formatted = string.format("%.2f", result)
					formatted = formatted:gsub("%.?0+$", "") -- Remove trailing zeros
				end
				return formatted .. Suffixes[i]
			end
		end
	end
end -- e.g. Module:Number(2592000) → "2.59M", Module:Number(1000) → "1K", Module:Number(1) → "1"

function Module:NumberPoint(Amount)
	local s = tostring(Amount)
	local len = #s
	local result = ""
	local count = 0

	for i = len, 1, -1 do
		local c = s:sub(i, i)
		count = count + 1
		result = c .. result
		if count % 3 == 0 and i ~= 1 then
			result = "," .. result
		end
	end

	return result
end

function Module:NormalTime(seconds)
	local months = math.floor(seconds / 2592000) -- 30 days in a month
	local days = math.floor((seconds % 2592000) / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local remainingSeconds = seconds % 60

	local timeString = ""
	if months > 0 then
		timeString = timeString .. months .. (months == 1 and "m" or "m") .. ", "
	end
	if days > 0 then
		timeString = timeString .. days .. (days == 1 and "d" or "d") .. ", "
	end
	if hours > 0 then
		timeString = timeString .. hours .. (hours == 1 and "h" or "h") .. ", "
	end
	if minutes > 0 then
		timeString = timeString .. minutes .. (minutes == 1 and "min" or "min") .. ", "
	end
	timeString = timeString .. remainingSeconds .. (remainingSeconds == 1 and "s" or "s")

	return timeString
end -- e.g. Module:NormalTime(2592000) → "1m, 0d, 0h, 0min, 0s"

function Module:OneTime(seconds)
	seconds = math.floor(math.max(seconds or 0, 0) + 0.5)
	
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local remainingSeconds = seconds % 60

	local timeString = ""
	if days > 0 then
		timeString = timeString .. days .. "d"
		-- Show hours if there are any remaining
		if hours > 0 then
			timeString = timeString .. " " .. hours .. "h"
		end
		return timeString
	end
	if hours > 0 then
		timeString = timeString .. hours .. "h"
		-- Show minutes if there are any remaining
		if minutes > 0 then
			timeString = timeString .. " " .. minutes .. "m"
		end
		return timeString
	end
	if minutes > 0 then
		-- Show minutes and seconds for better readability
		if remainingSeconds > 0 then
			timeString = timeString .. minutes .. "m " .. remainingSeconds .. "s"
		else
			timeString = timeString .. minutes .. "m"
		end
		return timeString
	end

	timeString = remainingSeconds .. "s"
	return timeString
end -- e.g. Module:OneTime(2592000) → "30d", Module:OneTime(93600) → "1d 2h"

function Module:Daily(seconds)
	local months = math.floor(seconds / 2592000) -- 30 days in a month
	local days = math.floor((seconds % 2592000) / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local remainingSeconds = seconds % 60

	local timeString = ""
	if months > 0 then
		timeString = timeString .. months .. " Months"
		return timeString
	end
	if days > 0 then
		timeString = timeString .. days .. " Days"
		return timeString
	end
	if hours > 0 then
		timeString = timeString .. hours .. " Hours"
		return timeString
	end
	if minutes > 0 then
		timeString = timeString .. minutes .. " Minutes"
		return timeString
	end

	timeString = remainingSeconds .. " Seconds"
	return timeString
end -- e.g. Module:Daily(2592000) → "1 Months"

function Module:Time(Val)
	local hours = math.floor(Val / 3600)
	local minutes = math.floor((Val % 3600) / 60)
	local remainingSeconds = Val % 60

	local formattedTime = ""

	if hours > 0 then
		formattedTime = string.format("%02d:%02d:%02d", hours, minutes, remainingSeconds)
	elseif minutes > 0 then
		formattedTime = string.format("%02d:%02d", minutes, remainingSeconds)
	else
		formattedTime = string.format("%02d:%02d", minutes, remainingSeconds)
	end

	return formattedTime
end -- e.g. Module:Time(2592000) → "720:00:00"

return Module
