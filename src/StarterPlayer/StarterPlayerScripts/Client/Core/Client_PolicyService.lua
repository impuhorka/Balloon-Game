--// Client_PolicyService - PolicyService wrapper for gambling/paid random item restrictions (SingingX-style).
--// Used to block lucky block purchases in regions where paid random items are restricted.

local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared_Marketplace = require(ReplicatedStorage.Modules.Settings.Shared_Marketplace)

local Module = {}

local Player = Players.LocalPlayer
local policyCache = nil
local isLoading = false
local isLoaded = false

-- Set of product IDs considered gambling (lucky blocks only)
local gamblingProductIds = nil

local function buildGamblingProductIdSet()
	if gamblingProductIds then return end
	gamblingProductIds = {}
	local products = Shared_Marketplace.Products
	if not products then return end
	for name, id in pairs(products) do
		if type(name) == "string" and name:find("LuckyBlock") and type(id) == "number" then
			gamblingProductIds[id] = true
		end
	end
end

-- Initialize PolicyService asynchronously (only once)
function Module:Init()
	if isLoading or isLoaded then
		return
	end
	isLoading = true
	buildGamblingProductIdSet()
	task.spawn(function()
		local success, result = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(Player)
		end)
		if success then
			policyCache = result
			isLoaded = true
		else
			warn("❌ Client_PolicyService: Failed to load PolicyService:", result)
			policyCache = { AllowedGambling = true }
			isLoaded = true
		end
		isLoading = false
	end)
end

-- Check if gambling/paid random items are allowed (returns true during loading to prevent blocking)
function Module:IsGamblingAllowed()
	if not isLoaded then
		return true
	end
	if policyCache then
		if policyCache.ArePaidRandomItemsRestricted ~= nil then
			return not policyCache.ArePaidRandomItemsRestricted
		end
		if policyCache.AllowedGambling ~= nil then
			return policyCache.AllowedGambling == true
		end
		if policyCache.AllowGambling ~= nil then
			return policyCache.AllowGambling == true
		end
		return true
	end
	return true
end

function Module:GetRestrictionMessage()
	return "This feature is not available in your region due to local gambling regulations"
end

-- Check if a product ID is a lucky block (gambling product)
function Module:IsGamblingProduct(productId)
	buildGamblingProductIdSet()
	if not gamblingProductIds then return false end
	return gamblingProductIds[productId] == true
end

return Module
