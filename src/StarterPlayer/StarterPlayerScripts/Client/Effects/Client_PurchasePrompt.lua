--// Client_PurchasePrompt - Handles purchase prompt visual feedback
--// Shows rainbow effect during purchase prompts (Roblox handles screen darkening)
--// Plays confetti + camera shake on successful purchases

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local Client_EffectsLibrary = require(script.Parent.Client_EffectsLibrary)
local CameraShake = require(script.Parent.Client_CameraShake)
local Shared_Marketplace = require(ReplicatedStorage.Modules.Settings.Shared_Marketplace)

local Module = {}

-- State tracking
local promptActive = false

--[[
	Show rainbow effect when purchase prompt is active
	(No darken - Roblox darkens screen by default during purchase prompts)
]]
local function ShowPromptOverlay()
	if promptActive then return end
	promptActive = true
	
	-- Start rainbow (loop forever until stopped)
	Client_EffectsLibrary:PlayRainbowHighlight(nil)
end

--[[
	Hide rainbow effect when prompt closes
	@param wasPurchased boolean - If true, plays success effects (confetti + shake)
]]
local function HidePromptOverlay(wasPurchased: boolean)
	if not promptActive then return end
	promptActive = false
	
	-- Stop rainbow
	Client_EffectsLibrary:StopRainbowHighlight()
	
	-- If purchase was successful, celebrate!
	if wasPurchased then
		-- Confetti burst + Robux purchase celebration sound
		Client_EffectsLibrary:PlayConfetti(70, 2.5, 1, "rbxassetid://107412694712908")
		
		-- Gentle camera shake
		CameraShake:ShakePreset("ConfettiShake")
	end
end

--[[
	Initialize the module - listen to marketplace events
]]
function Module:Init()
	-- Listen for when purchase prompts finish
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
		if userId ~= player.UserId then return end
		HidePromptOverlay(wasPurchased)
	end)
	
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(targetPlayer, passId, wasPurchased)
		if targetPlayer ~= player then return end
		HidePromptOverlay(wasPurchased)
	end)
	
	-- Listen for purchase requests from server (ProximityPrompts)
	local Events = ReplicatedStorage:WaitForChild("Events", 10)
	if Events then
		local PurchaseHandler = Events:FindFirstChild("PurchaseHandler")
		if PurchaseHandler then
			PurchaseHandler.OnClientEvent:Connect(function(productId, purchaseContext)
				if type(productId) ~= "number" or productId <= 0 then
					warn("⚠️ Client_PurchasePrompt: Marketplace product is not configured")
					return
				end
				
				-- Show purchase effects
				Module:OnPromptOpening()
				
				-- Prompt the purchase
				local isGamepass = false
				for _, pass in pairs(Shared_Marketplace.Passes) do
					if pass == productId then
						isGamepass = true
						break
					end
				end
				
				pcall(function()
					if isGamepass then
						MarketplaceService:PromptGamePassPurchase(player, productId)
					else
						MarketplaceService:PromptProductPurchase(player, productId)
					end
				end)
			end)
		end
		-- Group system: Server fires "Prompt" with groupId; client shows join prompt and sends back "JoinResult"
		local GroupHandler = Events:FindFirstChild("GroupHandler")
		
		if GroupHandler then
			GroupHandler.OnClientEvent:Connect(function(action, ...)
				if action == "Prompt" then
					local groupId = ...
					local success, result = pcall(function()
						local GroupService = game:GetService("GroupService")
						return GroupService:PromptJoinAsync(groupId)
					end)
					
					if success then
						-- Send result back to server for immediate reward processing
						GroupHandler:FireServer("JoinResult", groupId, result)
					else
						warn("Group join prompt failed:", result)
					end
				end
			end)
		end
		-- Option A: All prompts go through PurchaseHandler:FireClient → this listener (rainbow + prompt). No PlayEffect path.
	end
	
	-- Note: We can't directly detect when a prompt OPENS (no event for that)
	-- So we'll expose a method that marketplace code can call when prompting
end

--[[
	Call this when you're about to prompt a purchase (before PromptProductPurchase)
]]
function Module:OnPromptOpening()
	ShowPromptOverlay()
end

return Module
