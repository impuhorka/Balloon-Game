local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PublicPlaceId = game.PlaceId

local PlayerData = {}

local Module = {}

local IS_AFK_RESERVED = (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0)

local function bounceBackToPublic(player)
	task.wait(2)
	
	local opts = Instance.new("TeleportOptions")
	opts:SetTeleportData({
		AFKReturn = true
	})
	
	for i = 1, 5 do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(PublicPlaceId, {player}, opts)
		end)
		
		if ok then
			return
		end
		
		warn(("AntiAFK: bounce attempt %d failed: %s"):format(i, tostring(err)))
		task.wait(1 + 0.5 * i)
	end
	
	warn("AntiAFK: giving up bouncing", player.Name)
end

local function handlePlayerJoin(player)
	if RunService:IsStudio() then return end
	
	local joinData = player:GetJoinData()
	local td = joinData and joinData.TeleportData
	
	if IS_AFK_RESERVED and not (td and td.AFKReturn) then
		task.spawn(bounceBackToPublic, player)
		return
	end
	
	PlayerData[player] = true
end

local function handlePlayerLeave(player)
	PlayerData[player] = nil
end

function Module:Init()
	if RunService:IsStudio() then return end
	
	local Events = ReplicatedStorage:WaitForChild("Events")
	local IdleEvent = Events:WaitForChild("IdleHandler")
	
	for _, p in ipairs(Players:GetPlayers()) do
		handlePlayerJoin(p)
	end
	
	Players.PlayerAdded:Connect(handlePlayerJoin)
	Players.PlayerRemoving:Connect(handlePlayerLeave)
	
	IdleEvent.OnServerEvent:Connect(function(player)
		if not PlayerData[player] then return end
		
		if IS_AFK_RESERVED then return end
		
		local ok, code = pcall(function()
			return TeleportService:ReserveServer(PublicPlaceId)
		end)
		
		if not ok or type(code) ~= "string" then return end
		
		local opts = Instance.new("TeleportOptions")
		opts:SetTeleportData({
			AFKTeleport = true
		})
		
		local success, err = pcall(function()
			TeleportService:TeleportToPrivateServer(PublicPlaceId, code, {player}, nil, opts)
		end)
		
		if not success then
			warn("Failed to teleport player to reserved:", err)
		end
	end)
end

return Module
