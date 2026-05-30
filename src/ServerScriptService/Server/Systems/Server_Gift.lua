--// Server_Gift - Brainrot/LuckyBlock gifting (single GiftHandler RemoteEvent)
--// SendProposition → pending per recipient → ShowProposition to recipient → Answer (accept/cancel) or 15s timeout

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Module = {}

-- [recipientUserId] = { fromUserId, toUserId, itemUid, timerTask }
local PendingGiftByRecipient = {}

local function getProfile(player)
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	return Server_Data:GetProfile(player)
end

local function clearPendingForPlayer(userId)
	local p = PendingGiftByRecipient[userId]
	if p then
		if p.timerTask then task.cancel(p.timerTask) end
		PendingGiftByRecipient[userId] = nil
	end
	for toUid, pend in pairs(PendingGiftByRecipient) do
		if pend.fromUserId == userId then
			if pend.timerTask then task.cancel(pend.timerTask) end
			PendingGiftByRecipient[toUid] = nil
			local rec = Players:GetPlayerByUserId(toUid)
			if rec then
				local Events = ReplicatedStorage:FindFirstChild("Events")
				local gh = Events and Events:FindFirstChild("GiftHandler")
				if gh then gh:FireClient(rec, "CancelProposition", userId) end
			end
			break
		end
	end
end

-- Resolve the one giftable item: equipped Brainrot or LuckyBlock, or SlotPlacablePicked if that item is Brainrot/LuckyBlock
local function resolveGiftItem(sender)
	local Server_Inventory = require(script.Parent.Parent.Core.Server_Inventory)
	local profile = getProfile(sender)
	if not profile or not profile.Data or not profile.Data.Inventory then return nil, nil end
	local inv = profile.Data.Inventory
	local uid = Server_Inventory:GetEquippedItem(sender, "Brainrot")
	if uid and inv[uid] then
		local item = inv[uid]
		if item and (item.Type == "Brainrot" or item.Type == "LuckyBlock") then
			return uid, item
		end
	end
	uid = Server_Inventory:GetEquippedItem(sender, "LuckyBlock")
	if uid and inv[uid] then
		local item = inv[uid]
		if item and item.Type == "LuckyBlock" then
			return uid, item
		end
	end
	uid = sender:GetAttribute("SlotPlacablePicked")
	if type(uid) == "string" and uid ~= "" and inv[uid] then
		local item = inv[uid]
		if item and (item.Type == "Brainrot" or item.Type == "LuckyBlock") then
			return uid, item
		end
	end
	return nil, nil
end

local function firePopup(player, text, kind)
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local popup = Events and Events:FindFirstChild("Popup")
	if popup then popup:FireClient(player, text, kind or "info") end
end

function Module:Init()
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local GiftHandler = Events and Events:FindFirstChild("GiftHandler")
	if not GiftHandler then return end

	GiftHandler.OnServerEvent:Connect(function(player, action, ...)
		if action == "SendProposition" then
			local recipientUserId = ...
			if type(recipientUserId) ~= "number" or recipientUserId == player.UserId then return end
			local recipient = Players:GetPlayerByUserId(recipientUserId)
			if not recipient or not getProfile(recipient) then
				firePopup(player, "That player is no longer in the game.", "error")
				return
			end
			local itemUid, item = resolveGiftItem(player)
			if not itemUid or not item then
				firePopup(player, "You don't have a brainrot or lucky block to gift.", "error")
				return
			end
			if item.Type ~= "Brainrot" and item.Type ~= "LuckyBlock" then return end

			local existing = PendingGiftByRecipient[recipientUserId]
			if existing then
				if existing.timerTask then task.cancel(existing.timerTask) end
				PendingGiftByRecipient[recipientUserId] = nil
				GiftHandler:FireClient(recipient, "CancelProposition", existing.fromUserId)
			end

			local fromUserId = player.UserId
			local toUserId = recipientUserId
			local itemData = {
				Type = item.Type,
				ConfigName = item.ConfigName,
				Modifier = item.Modifier or "Normal",
				Level = item.Level or 1,
			}
			if item.Metadata then
				for k, v in pairs(item.Metadata) do
					if itemData[k] == nil then itemData[k] = v end
				end
			end

			local function cancelPending()
				local p = PendingGiftByRecipient[toUserId]
				if p and p.fromUserId == fromUserId and p.itemUid == itemUid then
					PendingGiftByRecipient[toUserId] = nil
					local rec = Players:GetPlayerByUserId(toUserId)
					if rec then GiftHandler:FireClient(rec, "CancelProposition", fromUserId) end
				end
			end

			PendingGiftByRecipient[toUserId] = {
				fromUserId = fromUserId,
				toUserId = toUserId,
				itemUid = itemUid,
				timerTask = task.delay(15, cancelPending),
			}
			GiftHandler:FireClient(recipient, "ShowProposition", fromUserId, player.DisplayName or player.Name, item.Type, itemData)
		elseif action == "Answer" then
			local accepted = ...
			local pending = PendingGiftByRecipient[player.UserId]
			if not pending then return end
			PendingGiftByRecipient[player.UserId] = nil
			if pending.timerTask then task.cancel(pending.timerTask) end

			local sender = Players:GetPlayerByUserId(pending.fromUserId)
			if not sender or not getProfile(sender) then return end
			local senderProfile = getProfile(sender).Data
			local item = senderProfile.Inventory and senderProfile.Inventory[pending.itemUid]
			if not item then
				if accepted then firePopup(player, "This gift is no longer available.", "error") end
				return
			end

			if accepted then
				local Server_Inventory = require(script.Parent.Parent.Core.Server_Inventory)
				local recipientProfile = getProfile(player).Data
				local inv = recipientProfile.Inventory or {}
				local count = 0
				for _ in pairs(inv) do count += 1 end
				local InventoryConfig = require(ReplicatedStorage.Modules.Settings.InventoryConfig)
				local limit = InventoryConfig and InventoryConfig.MaxInventorySize or 999
				if count >= limit then
					firePopup(player, "Your inventory is full. You can't accept the gift.", "error")
					return
				end
				local ok, removedData = Server_Inventory:RemoveItemWithReturn(sender, pending.itemUid)
				if not ok or not removedData then
					firePopup(player, "This gift is no longer available.", "error")
					return
				end
				local meta = removedData.Metadata and table.clone(removedData.Metadata) or {}
				local addOk, _ = Server_Inventory:AddItem(player, removedData.Type, removedData.ConfigName, meta)
				if not addOk then
					firePopup(player, "Could not add the gift to your inventory.", "error")
					Server_Inventory:AddItem(sender, removedData.Type, removedData.ConfigName, meta)
					return
				end
				firePopup(player, "You received a gift!", "success")
				firePopup(sender, "Your gift was accepted!", "success")
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(leaving)
		clearPendingForPlayer(leaving.UserId)
	end)
end

return Module
