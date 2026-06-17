local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
local Shared_LuckyBlocks = require(ReplicatedStorage.Modules.ItemConfigs.Shared_LuckyBlocks)
local Server_Inventory = require(script.Parent.Parent.Core.Server_Inventory)
local Server_IndexRewards = require(script.Parent.Server_IndexRewards)

local Module = {}

local OPEN_COOLDOWN = 0.25
local OPEN_TTL = 20

local lastOpenRequest = {}
local pendingByOpenId = {}
local pendingByPlayer = {}

local function weightedPick(weightMap: { [string]: number }): (string?, number?)
	local total = 0
	for key, rawWeight in pairs(weightMap) do
		local weight = tonumber(rawWeight) or 0
		if weight > 0 and key ~= "" then
			total += weight
		end
	end

	if total <= 0 then
		return nil, nil
	end

	local roll = math.random() * total
	local acc = 0
	for key, rawWeight in pairs(weightMap) do
		local weight = tonumber(rawWeight) or 0
		if weight > 0 and key ~= "" then
			acc += weight
			if roll <= acc then
				return key, weight
			end
		end
	end

	for key, rawWeight in pairs(weightMap) do
		local weight = tonumber(rawWeight) or 0
		if weight > 0 and key ~= "" then
			return key, weight
		end
	end

	return nil, nil
end

local function collectBrainrotsByRarity(rarity: string): { string }
	local out = {}
	for configName, brainrotData in pairs(Shared_Brainrots.List) do
		if brainrotData.Rarity == rarity then
			table.insert(out, configName)
		end
	end
	return out
end

local function pickFromList(list: { string }): string?
	if #list <= 0 then
		return nil
	end
	return list[math.random(1, #list)]
end

local function rollLevel(blockData: { [string]: any }): number
	if type(blockData.Level) == "number" then
		return math.max(1, math.floor(blockData.Level))
	end

	local minLevel = tonumber(blockData.LevelMin) or 5
	local maxLevel = tonumber(blockData.LevelMax) or 40
	if maxLevel < minLevel then
		minLevel, maxLevel = maxLevel, minLevel
	end
	minLevel = math.max(1, math.floor(minLevel))
	maxLevel = math.max(minLevel, math.floor(maxLevel))
	return math.random(minLevel, maxLevel)
end

local function buildPossibleRewards(blockData: { [string]: any }): { string }
	if type(blockData.Reward) == "table" then
		local out = {}
		for configName, rawWeight in pairs(blockData.Reward) do
			local weight = tonumber(rawWeight) or 0
			if weight > 0 and Shared_Brainrots.List[configName] then
				table.insert(out, configName)
			end
		end
		return out
	end

	local out = {}
	local seen = {}
	if type(blockData.RarityPool) == "table" then
		for rarity, rawWeight in pairs(blockData.RarityPool) do
			local weight = tonumber(rawWeight) or 0
			if weight > 0 then
				for _, configName in ipairs(collectBrainrotsByRarity(rarity)) do
					if not seen[configName] then
						seen[configName] = true
						table.insert(out, configName)
					end
				end
			end
		end
	end
	return out
end

local function rollReward(blockConfigName: string): (boolean, { [string]: any } | string)
	local blockData = Shared_LuckyBlocks.List[blockConfigName]
	if not blockData then
		return false, "Invalid lucky block config"
	end

	local pickedConfigName = nil
	local pickedWeight = 0

	if type(blockData.Reward) == "table" then
		local rewardKey, rewardWeight = weightedPick(blockData.Reward)
		if not rewardKey or not Shared_Brainrots.List[rewardKey] then
			return false, "Lucky block reward config invalid"
		end
		pickedConfigName = rewardKey
		pickedWeight = rewardWeight or 0
	elseif type(blockData.RarityPool) == "table" then
		local rarity, rarityWeight = weightedPick(blockData.RarityPool)
		if not rarity then
			return false, "Lucky block rarity pool invalid"
		end
		local candidates = collectBrainrotsByRarity(rarity)
		local selected = pickFromList(candidates)
		if not selected then
			return false, "No brainrots for rolled rarity"
		end
		pickedConfigName = selected
		pickedWeight = rarityWeight or 0
	else
		return false, "Lucky block has no reward table"
	end

	return true, {
		pickedConfig = pickedConfigName,
		pickedModifier = "Normal",
		level = rollLevel(blockData),
		weight = pickedWeight,
		possibleBrainrots = buildPossibleRewards(blockData),
	}
end

local function getOpenPositions(player: Player): (Vector3, Vector3)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		local fallback = Vector3.new(0, 5, 0)
		return fallback, fallback + Vector3.new(0, 0, -6)
	end

	local launchOrigin = hrp.Position + hrp.CFrame.UpVector * 2 + hrp.CFrame.LookVector * 1.2
	local landingPosition = hrp.Position + hrp.CFrame.LookVector * 6 + Vector3.new(0, 1, 0)
	return launchOrigin, landingPosition
end

local function clearPending(openId: string)
	local pending = pendingByOpenId[openId]
	if not pending then
		return
	end
	pendingByOpenId[openId] = nil
	if pendingByPlayer[pending.userId] == openId then
		pendingByPlayer[pending.userId] = nil
	end
end

local function isOpenThrottled(player: Player): boolean
	local now = os.clock()
	local prev = lastOpenRequest[player.UserId] or 0
	lastOpenRequest[player.UserId] = now
	return (now - prev) < OPEN_COOLDOWN
end

local function handleOpenLuckyBlock(player: Player, uid: string)
	if type(uid) ~= "string" or uid == "" then
		return
	end
	if isOpenThrottled(player) then
		return
	end
	if pendingByPlayer[player.UserId] then
		return
	end

	local currentEquipped = player:GetAttribute("CurrentEquipped")
	if currentEquipped ~= uid then
		return
	end

	local consumeSuccess, consumeResult = Server_Inventory:ConsumeItem(player, uid, function(_p, itemData)
		if not itemData or itemData.Type ~= "LuckyBlock" then
			return false, "Item is not a lucky block"
		end
		if (itemData.ConfigName == nil) or (itemData.ConfigName == "") then
			return false, "Lucky block config missing"
		end

		local rewardSuccess, rewardData = rollReward(itemData.ConfigName)
		if not rewardSuccess then
			return false, rewardData
		end

		return true, {
			blockConfig = itemData.ConfigName,
			reward = rewardData,
		}
	end)

	if not consumeSuccess or type(consumeResult) ~= "table" then
		return
	end

	local rewardData = consumeResult.reward
	if type(rewardData) ~= "table" then
		return
	end

	local pickedConfig = rewardData.pickedConfig
	if type(pickedConfig) ~= "string" or pickedConfig == "" then
		return
	end

	local playEffect = ReplicatedStorage:FindFirstChild("Events")
		and ReplicatedStorage.Events:FindFirstChild("PlayEffect")
	if not playEffect or not playEffect:IsA("RemoteEvent") then
		local _ = Server_Inventory:AddItem(player, "LuckyBlock", consumeResult.blockConfig, {})
		return
	end

	local openId = HttpService:GenerateGUID(false)
	local launchOrigin, landingPosition = getOpenPositions(player)
	pendingByOpenId[openId] = {
		userId = player.UserId,
		pickedConfig = pickedConfig,
		pickedModifier = rewardData.pickedModifier or "Normal",
		level = rewardData.level or 1,
		blockConfig = consumeResult.blockConfig,
		createdAt = os.clock(),
	}
	pendingByPlayer[player.UserId] = openId
	task.delay(OPEN_TTL, function()
		local entry = pendingByOpenId[openId]
		if entry and entry.userId == player.UserId then
			clearPending(openId)
		end
	end)

	playEffect:FireAllClients({
		effectType = "luckyblock",
		openingPlayerId = player.UserId,
		openingPlayerName = player.Name,
		luckyBlockConfig = consumeResult.blockConfig,
		luckyBlockModifier = "Normal",
		launchOrigin = launchOrigin,
		landingPosition = landingPosition,
		throwAngle = 0,
		possibleBrainrots = rewardData.possibleBrainrots or {},
		pickedConfig = pickedConfig,
		pickedModifier = rewardData.pickedModifier or "Normal",
		weight = rewardData.weight or 0,
		level = rewardData.level or 1,
		openId = openId,
	})
end

local function handleFinishOpening(player: Player, openId: string)
	if type(openId) ~= "string" or openId == "" then
		return
	end

	local pending = pendingByOpenId[openId]
	if not pending then
		return
	end
	if pending.userId ~= player.UserId then
		return
	end
	if (os.clock() - (pending.createdAt or 0)) > OPEN_TTL then
		clearPending(openId)
		return
	end

	clearPending(openId)
	Server_Inventory:AddItem(player, "Brainrot", pending.pickedConfig, {
		Modifier = pending.pickedModifier or "Normal",
		Level = pending.level or 1,
	})
	Server_IndexRewards:RegisterDiscovery(player, pending.pickedConfig, pending.pickedModifier or "Normal")
end

function Module:Init()
	local events = ReplicatedStorage:WaitForChild("Events")
	local itemHandler = events:WaitForChild("ItemHandler")

	itemHandler.OnServerEvent:Connect(function(player: Player, action: string, payload: any)
		if type(action) ~= "string" then
			return
		end

		if action == "OpenLuckyBlock" then
			handleOpenLuckyBlock(player, payload)
		elseif action == "FinishOpening" then
			handleFinishOpening(player, payload)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local openId = pendingByPlayer[player.UserId]
		if openId then
			clearPending(openId)
		end
		lastOpenRequest[player.UserId] = nil
	end)
end

return Module
