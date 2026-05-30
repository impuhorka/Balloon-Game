--// TableUtil - Professional table manipulation utilities
--// Use built-in table.clone for performance

local TableUtil = {}

--[[
	Deep clone a table (handles nested tables)
	@param tbl table - Table to clone
	@return table - Cloned table
]]
function TableUtil.DeepClone(tbl: {[any]: any}): {[any]: any}
	if type(tbl) ~= "table" then return tbl end
	
	local clone = {}
	for k, v in pairs(tbl) do
		clone[k] = type(v) == "table" and TableUtil.DeepClone(v) or v
	end
	return clone
end

--[[
	Copy table excluding specific key(s)
	@param tbl table - Source table
	@param excludeKey any - Key to exclude (or table of keys)
	@return table - New table without excluded key(s)
]]
function TableUtil.CopyExcept(tbl: {[any]: any}, excludeKey: any): {[any]: any}
	local result = {}
	local excludeSet = {}
	
	if type(excludeKey) == "table" then
		for _, key in ipairs(excludeKey) do
			excludeSet[key] = true
		end
	else
		excludeSet[excludeKey] = true
	end
	
	for k, v in pairs(tbl) do
		if not excludeSet[k] then
			result[k] = v
		end
	end
	
	return result
end

--[[
	Merge two tables (second overwrites first)
	@param target table - Target table
	@param source table - Source table
	@return table - Merged table
]]
function TableUtil.Merge(target: {[any]: any}, source: {[any]: any}): {[any]: any}
	local result = table.clone(target)
	for k, v in pairs(source) do
		result[k] = v
	end
	return result
end

--[[
	Count elements in a table (works for dictionaries)
	@param tbl table - Table to count
	@return number - Count
]]
function TableUtil.Count(tbl: {[any]: any}): number
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

--[[
	Check if table is empty
	@param tbl table - Table to check
	@return boolean - True if empty
]]
function TableUtil.IsEmpty(tbl: {[any]: any}): boolean
	return next(tbl) == nil
end

return TableUtil
