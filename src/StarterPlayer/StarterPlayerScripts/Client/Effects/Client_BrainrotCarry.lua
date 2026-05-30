local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer

-- Asset references
local Assets = ReplicatedStorage:WaitForChild("Assets")
local PlayerAnimations = Assets:WaitForChild("PlayerAnimations")
local OverheadAnimation = PlayerAnimations:WaitForChild("OverheadAnimation")

-- Events
local Events = ReplicatedStorage:WaitForChild("Events")
local BrainrotHandlerEvent = Events:WaitForChild("BrainrotHandler")

-- Modules
local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
local Shared_Rarity = require(ReplicatedStorage.Modules.Gameplay.Shared_Rarity)
local Shared_LuckyBlocks = require(ReplicatedStorage.Modules.ItemConfigs.Shared_LuckyBlocks)
local Client_Popups = require(script.Parent.Parent.UI.Client_Popups)
local Client_EffectsLibrary = require(script.Parent.Client_EffectsLibrary)

local Module = {}

-- State
local AnimationTrack = nil

--[[
	Play overhead carrying animation
]]
local function playOverheadAnimation()
	if AnimationTrack then return end
	
	local character = Player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	
	AnimationTrack = humanoid:LoadAnimation(OverheadAnimation)
	AnimationTrack.Priority = Enum.AnimationPriority.Action2
	AnimationTrack.Looped = true
	AnimationTrack:Play()
end

--[[
	Stop overhead carrying animation
]]
local function stopOverheadAnimation()
	if AnimationTrack then
		AnimationTrack:Stop()
		AnimationTrack = nil
	end
end

--[[
	Update animation based on held count
]]
local function updateAnimation()
	local count = Player:GetAttribute("HeldBrainrotCount") or 0
	
	if count > 0 then
		playOverheadAnimation()
	else
		stopOverheadAnimation()
	end
end

--[[
	Initialize brainrot carrying system
	
	This module handles:
	1. Overhead carrying animations when player holds brainrots
	2. Collection notifications with rarity-colored names and callout sounds
	3. Triggers collection effect (via Client_EffectsLibrary)
	
	GRADIENT COLORING:
	- Uses UIGradient on the entire popup for rarity-based coloring
	- Passes rarityInfo.gradient and rarityInfo.isRainbow to Client_Popups
	- Mythical rarity gets animated rainbow effect (0° rotation, animated keypoints)
	- Other rarities get static gradients (90° rotation)
	- Much more effective than richtext - handles all gradient effects automatically
	
	SOUND SYSTEM INTEGRATION:
	- CalloutSounds are asset IDs (rbxassetid://...) from brainrot configs
	- Client_Popups detects asset IDs and creates temporary sounds
	- Sounds auto-cleanup when finished, respect SFX volume settings
	
	MULTIPLE BRAINROT HANDLING:
	- Each brainrot gets unique popupType to prevent merging/replacement
	- Format: "brainrot_{ConfigName}_{timestamp}" ensures uniqueness
	- 0.7s delay between multiple brainrots for better audio/visual separation
	- Allows multiple sounds to play with proper spacing when carrying multiple brainrots
	
	COLLECTION EFFECTS:
	- All effects handled by Client_EffectsLibrary:PlayCollectionEffect()
	- Confetti VFX, rainbow highlight, collection sound, camera zoom
	- Effects play ONCE per collection event, regardless of brainrot count
	- See Client_EffectsLibrary for full effect implementation details
]]
function Module:Init()
	-- Listen for count changes to play/stop animation
	Player:GetAttributeChangedSignal("HeldBrainrotCount"):Connect(updateAnimation)
	
	-- Handle character respawn
	Player.CharacterAdded:Connect(function(newCharacter)
		stopOverheadAnimation()
		task.wait(0.1) -- Wait for character to load
		updateAnimation() -- Re-check if we should play animation
	end)
	
	-- Listen for item collection events from server
	BrainrotHandlerEvent.OnClientEvent:Connect(function(action, data)
		if action == "BrainrotsCollected" then
			-- Play collection effect ONCE (handled by EffectsLibrary)
			Client_EffectsLibrary:PlayCollectionEffect()
			
			-- Show popup + play sound for each collected brainrot
			task.spawn(function()
				for i, brainrotData in ipairs(data) do
					local config = Shared_Brainrots.List[brainrotData.ConfigName]
					if config then
						local displayName = config.DisplayName or brainrotData.ConfigName
						
						-- Get rarity gradient for popup coloring
						local rarityInfo = Shared_Rarity:GetRarityInfo(config.Rarity)
						if not rarityInfo then
							warn("⚠️ No rarity info found for:", config.Rarity)
							return
						end
						
						-- Simple message text (no richtext needed)
						local message = string.format("Collected %s!", displayName)
									
						-- Show popup with rarity gradient and callout sound
						-- Unique type so each brainrot gets its own popup (no merging)
						local uniquePopupType = "brainrot_" .. brainrotData.ConfigName .. "_" .. tick()
						Client_Popups:AddPopupImmediate(
							message,
							{
								popupType = uniquePopupType,
								sound = config.CalloutSound, -- Asset ID will be handled by Client_Popups
								gradient = rarityInfo.gradient, -- Use rarity gradient for popup coloring
								isRainbow = rarityInfo.isRainbow, -- Flag for Mythical rainbow animation
								duration = 3
							}
						)
						
						-- Wait for exact sound length from pre-defined table
						if i < #data then
							local soundLength = Shared_Brainrots.SoundLengths[brainrotData.ConfigName] or 1.2
							task.wait(soundLength) -- Exact sound duration, no buffer
						end
					end
				end
			end)
		elseif action == "ItemsCollected" then
			-- Combined handler: play brainrots first, then lucky blocks sequentially
			Client_EffectsLibrary:PlayCollectionEffect()
			
			task.spawn(function()
				local brainrots = data.Brainrots or {}
				local luckyBlocks = data.LuckyBlocks or {}
				
				-- Play brainrot callouts first
				for i, brainrotData in ipairs(brainrots) do
					local config = Shared_Brainrots.List[brainrotData.ConfigName]
					if config then
						local displayName = config.DisplayName or brainrotData.ConfigName
						local rarityInfo = Shared_Rarity:GetRarityInfo(config.Rarity)
						if rarityInfo then
							local message = string.format("Collected %s!", displayName)
							local uniquePopupType = "brainrot_" .. brainrotData.ConfigName .. "_" .. tick()
							Client_Popups:AddPopupImmediate(message, {
								popupType = uniquePopupType,
								sound = config.CalloutSound,
								gradient = rarityInfo.gradient,
								isRainbow = rarityInfo.isRainbow,
								duration = 3
							})
							
							-- Wait for sound to finish
							local soundLength = Shared_Brainrots.SoundLengths[brainrotData.ConfigName] or 1.2
							task.wait(soundLength)
						end
					end
				end
				
				-- Then play lucky block callouts
				for i, luckyBlockData in ipairs(luckyBlocks) do
					local config = Shared_LuckyBlocks.List[luckyBlockData.ConfigName]
					if config then
						local displayName = config.DisplayName or luckyBlockData.ConfigName
						local rarityInfo = Shared_Rarity:GetRarityInfo(config.Rarity)
						if rarityInfo then
							local message = string.format("Collected %s!", displayName)
							local uniquePopupType = "luckyblock_" .. luckyBlockData.ConfigName .. "_" .. tick()
							Client_Popups:AddPopupImmediate(message, {
								popupType = uniquePopupType,
								sound = "rbxassetid://138136042083639",
								gradient = rarityInfo.gradient,
								isRainbow = rarityInfo.isRainbow,
								duration = 3
							})
							
							-- Wait 1 second between lucky blocks
							if i < #luckyBlocks then
								task.wait(1)
							end
						end
					end
				end
			end)
		end
	end)
	
	-- Initial update
	updateAnimation()
end

return Module
