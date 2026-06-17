--[[
	Server_IndexRewards - Check and grant Index (collection) rewards when
	player reaches RequiredCount for a modifier. Handles EquipFloor (set EquippedIndexFloor).
	1s cooldown per player on switching floors.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Server_Data = require(script.Parent.Parent.Core.Server_Data)
local Shared_IndexRewards = require(ReplicatedStorage.Modules.Gameplay.Shared_IndexRewards)

local Module = {}

local COOLDOWN_SECONDS = 1
local LastSwitchTime = {} -- [userId] = tick()
local IndexHandlerConnected = false

local function tryApplyFloorSwitch(player, applyFn)
	local now = tick()
	local last = LastSwitchTime[player.UserId] or 0
	local elapsed = now - last
	if elapsed < COOLDOWN_SECONDS then
		local remaining = math.ceil(COOLDOWN_SECONDS - elapsed)
		local popupEvent = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("Popup")
		if popupEvent then
			popupEvent:FireClient(player, "Please wait " .. remaining .. " seconds!", "error")
		end
		return false
	end
	applyFn()
	LastSwitchTime[player.UserId] = now
	return true
end

local function connectIndexHandler()
	if IndexHandlerConnected then
		return
	end

	local events = ReplicatedStorage:WaitForChild("Events", 30)
	if not events then
		warn("[Server_IndexRewards] Events folder not found")
		return
	end

	local indexHandler = events:WaitForChild("IndexHandler", 30)
	if not indexHandler or not indexHandler:IsA("RemoteEvent") then
		warn("[Server_IndexRewards] IndexHandler RemoteEvent not found")
		return
	end

	indexHandler.OnServerEvent:Connect(function(player, action, ...)
		if action == "EquipFloor" then
			local modifier = ...
			if type(modifier) ~= "string" or modifier == "" then
				return
			end
			local config = Shared_IndexRewards:GetRewardConfig(modifier)
			if not config then
				return
			end
			local profile = Server_Data:GetProfile(player)
			if not profile or not profile.Data then
				return
			end
			local unlocked
			if Shared_IndexRewards:IsGamepassUnlock(config) then
				unlocked = (profile.Data.Passes and profile.Data.Passes[config.PassName]) == true
			elseif Shared_IndexRewards:IsIndexUnlock(config) then
				local rewardsUnlocked = profile.Data.IndexRewardsUnlocked or {}
				unlocked = rewardsUnlocked[modifier] == true
			elseif Shared_IndexRewards:IsSpecialRewardUnlock(config) then
				local rewardsUnlocked = profile.Data.IndexRewardsUnlocked or {}
				unlocked = rewardsUnlocked[modifier] == true
			else
				unlocked = false
			end
			if not unlocked then
				return
			end

			tryApplyFloorSwitch(player, function()
				Server_Data:SetValue(player, "EquippedIndexFloor", modifier)
				local PlotService = require(script.Parent.Parent.Plot.PlotService)
				local applied = PlotService:ApplyPlotSkin(player, modifier)
				PlotService:UpdatePlotPlayerInfo(player)
				local BrainrotVisuals = require(script.Parent.Parent.Plot.BrainrotVisuals)
				BrainrotVisuals:UpdateAllBillboardsForPlayer(player)
				local popupEvent = events:FindFirstChild("Popup")
				if popupEvent then
					if applied then
						popupEvent:FireClient(player, "Equipped " .. (config.RewardName or modifier) .. "!", "success")
					else
						local skinKey = Shared_IndexRewards:GetSkinKey(modifier)
						popupEvent:FireClient(
							player,
							"Could not apply plot skin (need Floor0_" .. skinKey .. " in Assets.PlotSkins and Floor0 on plot)",
							"error"
						)
					end
				end
			end)
		elseif action == "UnequipFloor" then
			tryApplyFloorSwitch(player, function()
				Server_Data:SetValue(player, "EquippedIndexFloor", "Default")
				local PlotService = require(script.Parent.Parent.Plot.PlotService)
				PlotService:ApplyPlotSkin(player, "Default")
				PlotService:UpdatePlotPlayerInfo(player)
				local BrainrotVisuals = require(script.Parent.Parent.Plot.BrainrotVisuals)
				BrainrotVisuals:UpdateAllBillboardsForPlayer(player)
			end)
		end
	end)

	IndexHandlerConnected = true
end

function Module:Init()
	connectIndexHandler()
end

Players.PlayerRemoving:Connect(function(player)
	LastSwitchTime[player.UserId] = nil
end)

--[[
	Call after updating player's Index (e.g. in Server_BrainrotSpawner collect,
	Server_ItemHandler FinishOpening). Checks each modifier; if discovered count
	>= RequiredCount and not yet unlocked, sets IndexRewardsUnlocked[modifier] = true
	and optionally notifies client.
]]
function Module:CheckAndGrant(player)
	local profile = Server_Data:GetProfile(player)
	if not profile or not profile.Data then return end

	local index = profile.Data.Index or {}
	local unlocked = profile.Data.IndexRewardsUnlocked or {}
	local updated = false
	local newUnlocks = {}

	for modifier, config in pairs(Shared_IndexRewards.Rewards) do
		if not Shared_IndexRewards:IsIndexUnlock(config) then continue end
		local list = index[modifier]
		local count = (type(list) == "table") and #list or 0
		local required = config.RequiredCount or 0
		if count >= required and not unlocked[modifier] then
			unlocked[modifier] = true
			updated = true
			table.insert(newUnlocks, { Modifier = modifier, RewardName = config.RewardName })
		end
	end

	if not updated then return end

	Server_Data:SetValue(player, "IndexRewardsUnlocked", unlocked)

	local popupEvent = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("Popup")
	for _, entry in ipairs(newUnlocks) do
		if popupEvent then
			popupEvent:FireClient(player, "Unlocked: " .. entry.RewardName .. "!", "success")
		end
	end
end

-- Backward-compatible: connect immediately if Init hasn't run yet.
connectIndexHandler()

return Module
