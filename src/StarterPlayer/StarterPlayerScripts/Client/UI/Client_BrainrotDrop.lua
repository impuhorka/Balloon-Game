--// Client_BrainrotDrop - Handles DropBrainrotFrame UI
--// Shows button to drop all held brainrots

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Events
local Events = ReplicatedStorage:WaitForChild("Events")
local BrainrotHandlerEvent = Events:WaitForChild("BrainrotHandler")
local PurchaseHandlerEvent = Events:FindFirstChild("PurchaseHandler")

local Shared_Marketplace = require(ReplicatedStorage.Modules.Settings.Shared_Marketplace)
local TELEPORT_HOME_PRODUCT_ID = Shared_Marketplace.Products["Teleport Home"]

local Module = {}

-- UI References
local MainUI = nil
local DropBrainrotFrame = nil
local DropButton = nil

--[[
	Update UI visibility based on HeldBrainrotCount attribute
]]
local function updateUIVisibility()
	if not DropBrainrotFrame then return end
	
	local count = Player:GetAttribute("HeldBrainrotCount") or 0
	DropBrainrotFrame.Visible = (count > 0)
end

--[[
	Initialize drop UI
]]
function Module:Init()
	-- Wait for UI
	MainUI = PlayerGui:WaitForChild("Main", 10)
	if not MainUI then
		warn("⚠️ Main UI not found")
		return
	end
	
	DropBrainrotFrame = MainUI:WaitForChild("DropBrainrotFrame", 10)
	if not DropBrainrotFrame then
		warn("⚠️ DropBrainrotFrame not found in Main UI")
		return
	end
	
	local buttonFrame = DropBrainrotFrame:FindFirstChild("ButtonFrame")
	if buttonFrame then
		DropButton = buttonFrame:FindFirstChildOfClass("ImageButton") or buttonFrame:FindFirstChildOfClass("TextButton")
	end
	
	if not DropButton then
		warn("⚠️ Drop button not found in DropBrainrotFrame")
		return
	end
	
	-- Hook up drop button
	DropButton.Activated:Connect(function()
		BrainrotHandlerEvent:FireServer("DropAll")
	end)

	-- Teleport Home button (prompts product 3539211035; on purchase server teleports to plot)
	local teleportFrame = DropBrainrotFrame:FindFirstChild("TeleportFrame")
	local teleportButton = teleportFrame and (teleportFrame:FindFirstChild("Button") or teleportFrame:FindFirstChildOfClass("TextButton") or teleportFrame:FindFirstChildOfClass("ImageButton"))
	if teleportButton and PurchaseHandlerEvent and type(TELEPORT_HOME_PRODUCT_ID) == "number" and TELEPORT_HOME_PRODUCT_ID > 0 then
		teleportButton.Activated:Connect(function()
			PurchaseHandlerEvent:FireServer(TELEPORT_HOME_PRODUCT_ID, nil)
		end)
	end

	-- Listen for count changes
	Player:GetAttributeChangedSignal("HeldBrainrotCount"):Connect(updateUIVisibility)
	
	-- Initial update
	updateUIVisibility()
end

return Module
