--// Server_Slapper - Slapper inventory (give on spawn) + slap hit detection and ragdoll
--// One module: gives StandardSlapper/VIPSlapper on spawn, connects Slapper event, handles hits

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Import centralized ragdoll system
local RagdollSystem = require(script.Parent.Parent.Systems.Server_RagdollSystem)

-- Slapper config names (from Shared_Tools)
local SLAPPER_VARIANTS = {
	Default = "StandardSlapper",
	VIP = "VIPSlapper",
}

local function getSlapperVariant(player)
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	local data = Server_Data:GetValue(player, "Passes")
	if data and data.VIP then
		return SLAPPER_VARIANTS.VIP
	end
	return SLAPPER_VARIANTS.Default
end

-- Give slapper to player's inventory and auto-equip (runtime only, not saved)
local function giveSlapper(module, player)
	if not player or not player:IsDescendantOf(Players) then return end
	
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	local Server_Inventory = require(script.Parent.Parent.Core.Server_Inventory)
	
	-- Wait for profile/replica (max ~5 seconds, then give up)
	local profile = Server_Data:GetProfile(player)
	local maxAttempts = 50
	local attempt = 0
	while not profile and player.Parent and attempt < maxAttempts do
		task.wait(0.1)
		profile = Server_Data:GetProfile(player)
		attempt = attempt + 1
	end
	if not profile then
		warn("⚠️ Server_Slapper: Profile not ready for", player.Name, "- skipping slapper this spawn")
		return
	end
	
	local inventory = Server_Inventory:GetInventory(player)
	for uid, itemData in pairs(inventory) do
		if itemData.Type == "Tool" and (itemData.ConfigName == SLAPPER_VARIANTS.Default or itemData.ConfigName == SLAPPER_VARIANTS.VIP) then
			Server_Inventory:RemoveItem(player, uid)
		end
	end
	
	local variant = getSlapperVariant(player)
	local success, uid = Server_Inventory:AddItem(player, "Tool", variant, {})
	if not success then
		warn("⚠️ Server_Slapper: Failed to add slapper:", uid)
		return
	end
	-- Slapper is in inventory; player equips manually (e.g. slot 1)
end

--// Variables
local SlapperCooldowns = {} -- Track slapper cooldowns per player to prevent spam
local RagdolledPlayers = {} -- Track which players are currently ragdolled to prevent chain hits
local PlayerImmunity = {} -- Track immunity periods for players after ragdoll ends
local GodmodePlayers = {} -- Track which players have godmode enabled (slaps get reversed)
local Shared_Tools = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Tools)

-- Function to get slapper stats based on player's equipped tool
local function GetSlapperStats(Player)
	-- Get current equipped item from player attribute
	local currentEquipped = Player:GetAttribute("CurrentEquipped")
	if not currentEquipped then
		return Shared_Tools.List.StandardSlapper -- Default
	end
	
	-- Get item data from Server_Inventory
	local Server_Inventory = require(script.Parent.Parent.Core.Server_Inventory)
	local itemData = Server_Inventory:GetItem(Player, currentEquipped)
	
	if itemData and itemData.Type == "Tool" then
		local toolConfig = Shared_Tools.List[itemData.ConfigName]
		if toolConfig then
			return toolConfig
		end
	end
	
	return Shared_Tools.List.StandardSlapper -- Default fallback
end

local IMMUNITY_DURATION = 0.5 -- Players are immune to slaps for 0.5s after ragdoll ends

--// Functions
local Module = {}

Module.Variants = SLAPPER_VARIANTS

function Module:GiveSlapper(player)
	giveSlapper(self, player)
end

function Module:RefreshSlapper(player)
	giveSlapper(self, player)
end

function Module:Init()
	local Server_Data = require(script.Parent.Parent.Core.Server_Data)
	
	-- Give slapper on spawn/respawn
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait()
			giveSlapper(self, player)
		end)
	end)
	
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			task.wait()
			giveSlapper(self, player)
		end)
		if player.Character then
			task.spawn(function()
				local replica = Server_Data:GetReplica(player)
				while not replica and player.Parent do
					task.wait(0.1)
					replica = Server_Data:GetReplica(player)
				end
				if replica then
					giveSlapper(self, player)
				end
			end)
		end
	end
	
	-- Connect to slapper event (hit detection)
	ReplicatedStorage.Events.Slapper.OnServerEvent:Connect(function(Player, TargetPlayer, Velocity)
		if RagdolledPlayers[Player.UserId] then return end

		local Server_Inventory = require(script.Parent.Parent.Core.Server_Inventory)
		local equippedUid = Player:GetAttribute("CurrentEquipped")
		if type(equippedUid) ~= "string" or equippedUid == "" then
			return
		end
		local itemData = Server_Inventory:GetItem(Player, equippedUid)
		if not itemData or itemData.Type ~= "Tool" then
			return
		end
		if itemData.ConfigName ~= SLAPPER_VARIANTS.Default and itemData.ConfigName ~= SLAPPER_VARIANTS.VIP then
			return
		end
		
		local slapperStats = GetSlapperStats(Player)
		local currentTime = tick()
		local lastUseTime = SlapperCooldowns[Player.UserId] or 0
		local serverCooldown = (slapperStats and slapperStats.ServerCooldown) or 0.8
		
		if currentTime - lastUseTime < serverCooldown then return end
		
		SlapperCooldowns[Player.UserId] = currentTime
		
		if TargetPlayer and Velocity then
			self:HandleSlapper(Player, TargetPlayer, Velocity)
		else
			self:StartSlapperCollisionDetection(Player)
		end
	end)
	
	-- Clean up when players leave
	Players.PlayerRemoving:Connect(function(Player)
		self:CleanupPlayer(Player)
	end)
end

function Module:StartSlapperCollisionDetection(Player)
	local Character = Player.Character
	if not Character then return end
	
	local tool = Character:FindFirstChild("CurrentEquippedAccessory")
	if not tool or not tool:FindFirstChild("Handle") then return end
	
	local slapperStats = GetSlapperStats(Player)
	local Power = (slapperStats and slapperStats.Power) or 8
	local Speed = (slapperStats and slapperStats.Speed) or 0.8
	
	local connection
	connection = tool.Handle.Touched:Connect(function(hit)
		local hitCharacter = hit.Parent
		if not hitCharacter or not hitCharacter:IsA("Model") then return end
		
		local hitPlayer = Players:GetPlayerFromCharacter(hitCharacter)
		if not hitPlayer or hitPlayer == Player then return end
		
		local PlayerRootPart = Character:FindFirstChild("HumanoidRootPart")
		local HitRootPart = hitCharacter:FindFirstChild("HumanoidRootPart")
		
		if PlayerRootPart and HitRootPart then
			local direction = (HitRootPart.Position - PlayerRootPart.Position).Unit
			local slapPowerBonus = Player:GetAttribute("SlapPowerBonus") or 0
			local velocity = direction * (Power + slapPowerBonus)
			self:HandleSlapper(Player, hitPlayer, velocity)
			if connection then connection:Disconnect() end
		end
	end)
	
	task.delay(Speed, function()
		if connection then connection:Disconnect() end
	end)
end

function Module:HandleSlapper(Player, TargetPlayer, Velocity, bypassImmunity)
	-- Prevent self-hits - players can only hit other players
	if not TargetPlayer or TargetPlayer == Player then return end
	
	local TargetCharacter = TargetPlayer.Character
	local TargetHumanoid = TargetCharacter and TargetCharacter:FindFirstChild("Humanoid")
	local TargetRootPart = TargetCharacter and TargetCharacter:FindFirstChild("HumanoidRootPart")
	
	if not TargetHumanoid or not TargetRootPart then return end
	
	-- Get slapper stats for this player
	local slapperStats = GetSlapperStats(Player)
	
	-- Check if target has godmode - reverse the slap onto the attacker
	if GodmodePlayers[TargetPlayer.UserId] then
		-- If attacker also has godmode, cancel the slap to prevent infinite loop
		if GodmodePlayers[Player.UserId] then
			return -- Both players have godmode, cancel the slap
		end
		
		-- Trigger godmode flash effect on the protected player (cyan flash)
		if TargetCharacter then
			-- Create highlight for flash effect
			local Highlight = Instance.new("Highlight")
			Highlight.FillColor = Color3.fromRGB(0, 255, 204)
			Highlight.OutlineColor = Color3.fromRGB(0, 255, 204)
			Highlight.FillTransparency = 1  -- Start invisible
			Highlight.OutlineTransparency = 1
			Highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			Highlight.Parent = TargetCharacter
			
			-- Flash animation: quick in (25%), slow out (75%)
			local flashDuration = 0.5
			local quickInDuration = flashDuration * 0.25
			local slowOutDuration = flashDuration * 0.75
			
			-- Quick tween to visible
			local tweenInfo1 = TweenInfo.new(quickInDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween1 = TweenService:Create(Highlight, tweenInfo1, {
				FillTransparency = 0.3,
				OutlineTransparency = 0.1
			})
			
			-- Slow tween to invisible
			local tweenInfo2 = TweenInfo.new(slowOutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local tween2 = TweenService:Create(Highlight, tweenInfo2, {
				FillTransparency = 1,
				OutlineTransparency = 1
			})
			
			-- Chain tweens and cleanup
			tween1:Play()
			tween1.Completed:Connect(function()
				tween2:Play()
				tween2.Completed:Connect(function()
					if Highlight and Highlight.Parent then
						Highlight:Destroy()
					end
				end)
			end)
			
			-- Play godmode sound
			if TargetRootPart then
				local GodmodeSound = Instance.new("Sound")
				GodmodeSound.SoundId = "rbxassetid://92998677294407"
				GodmodeSound.Volume = 1
				GodmodeSound.RollOffMaxDistance = 200
				GodmodeSound.RollOffMinDistance = 30
				GodmodeSound.PlaybackSpeed = math.random(95, 115) / 100 -- Random speed between 0.95 and 1.15
				GodmodeSound.Parent = TargetRootPart
				GodmodeSound:Play()
				
				-- Clean up sound after it finishes
				GodmodeSound.Ended:Connect(function()
					if GodmodeSound and GodmodeSound.Parent then
						GodmodeSound:Destroy()
					end
				end)
			end
		end
		
		-- Reverse the slap - the attacker becomes the target (with reversed direction)
		-- Pass bypassImmunity=true to ensure the reversal always works
		local reversedVelocity = -Velocity
		self:HandleSlapper(TargetPlayer, Player, reversedVelocity, true)
		return
	end
	
	-- Check if target player is currently ragdolled or has immunity (unless bypassing)
	if not bypassImmunity and (RagdolledPlayers[TargetPlayer.UserId] or PlayerImmunity[TargetPlayer.UserId]) then
		return -- Target is immune to slaps
	end
	
	-- Drop held brainrots when slapped
	local Server_BrainrotSpawner = script.Parent.Server_BrainrotSpawner
	if Server_BrainrotSpawner then
		local spawnerModule = require(Server_BrainrotSpawner)
		if spawnerModule and spawnerModule.OnPlayerSlapped then
			spawnerModule:OnPlayerSlapped(TargetPlayer)
		end
	end
	
	-- Setup ragdoll system for this character
	RagdollSystem:Setup(TargetCharacter)
	self:ConnectRagdollEvents(TargetCharacter)
	
	-- Mark player as ragdolled (they can't use slapper while ragdolled)
	RagdolledPlayers[TargetPlayer.UserId] = true
	
	-- Mark this as a slap-caused ragdoll (can be overridden by guard)
	TargetCharacter:SetAttribute("RagdollSource", "Slap")
	
	-- Start ragdoll IMMEDIATELY (before launch) so character is limp while flying
	local RagdollValue = TargetCharacter:FindFirstChild("Ragdoll")
	if RagdollValue then
		RagdollValue.Value = true
	end
	
	-- Temporarily disable humanoid control so physics can take over
	TargetHumanoid.PlatformStand = true
	
	-- Launch: horizontal from direction*power (XZ only so vertical is consistent), vertical from config (Tsunami-style)
	local upwardBoost = (slapperStats and slapperStats.UpwardBoost) or 40
	local power = Velocity.Magnitude
	local dir = power > 0 and Velocity.Unit or Vector3.new(1, 0, 0)
	-- Flatten to XZ so vertical is purely from UpwardBoost (Standard 40, VIP 55)
	local dirXZ = Vector3.new(dir.X, 0, dir.Z)
	if dirXZ.Magnitude > 0 then dirXZ = dirXZ.Unit end
	local BodyVelocity = Instance.new("BodyVelocity")
	BodyVelocity.MaxForce = Vector3.new(1e8, 1e8, 1e8)
	BodyVelocity.Velocity = dirXZ * (power * 5) + Vector3.new(0, upwardBoost, 0)
	BodyVelocity.Parent = TargetRootPart
	
	-- Play slap sound (tool-specific: VIP uses different sound, SingingX-style)
	local slapSoundId = (slapperStats and slapperStats.SlapSoundId) or "rbxassetid://7195270254"
	local SlapSound = Instance.new("Sound")
	SlapSound.SoundId = slapSoundId
	SlapSound.Volume = 3
	SlapSound.Parent = TargetRootPart
	SlapSound:Play()
	
	-- Play random hit sound from ReplicatedStorage.Assets.HitSounds folder with delay
	local HitSoundsFolder = ReplicatedStorage.Assets:FindFirstChild("HitSounds")
	if HitSoundsFolder then
		local hitSounds = {}
		-- Collect all sound files from the HitSounds folder
		for _, sound in pairs(HitSoundsFolder:GetChildren()) do
			if sound:IsA("Sound") then
				table.insert(hitSounds, sound)
			end
		end
		
		-- Play a random hit sound if we have any (with 0.2s delay)
		if #hitSounds > 0 then
			task.delay(0.2, function()
				local randomSound = hitSounds[math.random(1, #hitSounds)]
				local hitSound = Instance.new("Sound")
				hitSound.SoundId = randomSound.SoundId
				hitSound.Volume = 2.5  -- Slightly lower than slap sound
				hitSound.Parent = TargetRootPart
				hitSound:Play()
				
				-- Clean up the hit sound after it finishes
				hitSound.Ended:Connect(function()
					if hitSound and hitSound.Parent then
						hitSound:Destroy()
					end
				end)
			end)
		end
	end
	
	-- Remove launch physics after a very short duration (0.2s) for quick impulse, then gravity takes over
	task.delay(0.2, function()
		-- Remove the launch physics
		if BodyVelocity and BodyVelocity.Parent then
			BodyVelocity:Destroy()
		end
		
		-- Keep ragdoll active (it's already on from the start)
		-- Ragdoll will continue for the remaining time
	end)
	
	-- End ragdoll after total duration (SingingX: FlightSpeed)
	local flightSpeed = (slapperStats and slapperStats.FlightSpeed) or 2.5
	task.delay(flightSpeed, function()
		-- Check if this ragdoll was overridden by a guard shot
		local ragdollSource = TargetCharacter:GetAttribute("RagdollSource")
		if ragdollSource == "Guard" then
			-- Guard ragdoll takes priority - don't disable it
			return
		end
		
		-- Stop ragdolling using BoolValue
		if RagdollValue then
			RagdollValue.Value = false
		end
		
		-- Remove from ragdolled players list
		RagdolledPlayers[TargetPlayer.UserId] = nil
		
		-- Add immunity period to prevent chain slaps
		PlayerImmunity[TargetPlayer.UserId] = true
		
		-- Remove immunity after duration
		task.delay(IMMUNITY_DURATION, function()
			PlayerImmunity[TargetPlayer.UserId] = nil
		end)
		
		-- Clean up sounds
		if SlapSound and SlapSound.Parent then
			SlapSound:Destroy()
		end
		
		-- Clean up any remaining hit sounds
		for _, sound in pairs(TargetRootPart:GetChildren()) do
			if sound:IsA("Sound") and sound ~= SlapSound then
				sound:Destroy()
			end
		end
	end)
end

function Module:ConnectRagdollEvents(Character)
	-- Check if character already has ragdoll value
	if Character:FindFirstChild("Ragdoll") then
		local ExistingRagdollValue = Character.Ragdoll
		ExistingRagdollValue.Changed:Connect(function(Value)
			if Value then
				RagdollSystem:Start(Character)
			else
				RagdollSystem:Stop(Character)
			end
		end)
		return
	end
	
	-- Listen for when ragdoll value is added
	Character.ChildAdded:Connect(function(Child)
		if not Child:IsA("BoolValue") or Child.Name ~= "Ragdoll" then return end
		Child.Changed:Connect(function(Value)
			if Value then
				RagdollSystem:Start(Character)
			else
				RagdollSystem:Stop(Character)
			end
		end)
	end)
end

function Module:CleanupPlayer(Player)
	-- Clean up player's slapper cooldown when they leave
	SlapperCooldowns[Player.UserId] = nil
	-- Clean up ragdolled status when they leave
	RagdolledPlayers[Player.UserId] = nil
	-- Clean up immunity status when they leave
	PlayerImmunity[Player.UserId] = nil
	-- Clean up godmode status when they leave
	GodmodePlayers[Player.UserId] = nil
end

function Module:ToggleGodmode(Player)
	if GodmodePlayers[Player.UserId] then
		GodmodePlayers[Player.UserId] = nil
		return false
	else
		GodmodePlayers[Player.UserId] = true
		return true
	end
end

return Module
