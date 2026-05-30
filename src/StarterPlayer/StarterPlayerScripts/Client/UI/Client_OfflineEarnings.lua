-- Client_OfflineEarnings.lua
-- Manages the offline earnings popup UI

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Get Main UI
local Main = playerGui:WaitForChild("Main")
local OfflineEarningsFrame = Main.Frames:WaitForChild("OfflineEarnings")
local MainFrame = OfflineEarningsFrame:WaitForChild("MainFrame")
local AmountLabel = MainFrame.Amount
local ButtonsContainer = MainFrame.Buttons
local ClaimButton = ButtonsContainer.Claim:WaitForChild("Button")
local x10Button = ButtonsContainer.x10:WaitForChild("Button")
local x10AmountLabel = x10Button:FindFirstChild("Amount") -- x10.Button.Amount.Text

-- Get modules
local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)

-- Get RemoteEvent
local Events = ReplicatedStorage:WaitForChild("Events")
local OfflineHandler = Events:WaitForChild("OfflineHandler")

-- Module table
local Module = {}

-- State
local currentPendingAmount = 0
local isProcessing = false -- Debounce for button clicks

-- Reference to Client_Frames (will be set in Init)
local Client_Frames = nil
local Client_PurchasePrompt = nil

--[[
	Shows the offline earnings popup with the specified amount
	@param amount number - The pending offline earnings amount
	@param timeOffline number - How long the player was offline (in seconds)
]]
local function ShowPopup(amount: number, timeOffline: number)
	if amount <= 0 then
		warn("Client_OfflineEarnings: Cannot show popup with amount <= 0")
		return
	end
	
	currentPendingAmount = amount
	
	-- Update amount text
	AmountLabel.Text = "$" .. Shared_Shorten:Number(amount)
	if x10AmountLabel and x10AmountLabel:IsA("TextLabel") then
		x10AmountLabel.Text = "$" .. Shared_Shorten:Number(amount * 10)
	end
	
	-- Open frame using Client_Frames system
	if Client_Frames then
		Client_Frames:OpenFrame("OfflineEarnings")
	else
		OfflineEarningsFrame.Visible = true
	end
end

--[[
	Closes the popup UI
	@param shouldAutoClaim boolean - If true, auto-claims free amount before closing
]]
local function ClosePopup(shouldAutoClaim: boolean?)
	if shouldAutoClaim and currentPendingAmount > 0 and not isProcessing then
		-- Auto-claim the free amount when closing
		isProcessing = true
		OfflineHandler:FireServer("Free")
	end
	
	-- Close frame using Client_Frames system
	if Client_Frames then
		Client_Frames:CloseFrame("OfflineEarnings")
	else
		OfflineEarningsFrame.Visible = false
	end
	
	currentPendingAmount = 0
	isProcessing = false
end

--[[
	Handles the "Claim" button (free claim)
]]
local function OnClaimClicked()
	if isProcessing or currentPendingAmount <= 0 then
		return
	end
	
	isProcessing = true
	OfflineHandler:FireServer("Free")
	ClosePopup(false)
end

--[[
	Handles the "x10" button (Robux boost purchase)
	Only closes UI after successful purchase (server will clear pending and we detect via replica change)
]]
local function OnX10Clicked()
	if isProcessing or currentPendingAmount <= 0 then
		return
	end
	
	isProcessing = true
	
	-- Server will FireClient(PurchaseHandler); client listener shows rainbow + prompt
	OfflineHandler:FireServer("10x")
	-- Don't close UI here - let user cancel the purchase and still claim free
	-- UI will auto-close when purchase succeeds (server clears PendingOfflineEarnings)
	
	-- Reset processing after a delay so they can still claim free if they cancel
	task.delay(1, function()
		isProcessing = false
	end)
end

--[[
	Initialize the module.
	Bootstrap calls Module.Init(Module), so first arg is self (the module).
	Other modules (e.g. Client_Frames) are on self via metatable.
]]
function Module:Init()
	-- Get Client_Frames from self (Library is set as metatable on all client modules)
	Client_Frames = self.Client_Frames
	Client_PurchasePrompt = self.Client_PurchasePrompt
	
	-- Listen for server event
	OfflineHandler.OnClientEvent:Connect(function(data: { amount: number, timeOffline: number })
		if data and data.amount and data.amount > 0 then
			ShowPopup(data.amount, data.timeOffline or 0)
		end
	end)
	
	-- Connect buttons
	ClaimButton.MouseButton1Click:Connect(OnClaimClicked)
	x10Button.MouseButton1Click:Connect(OnX10Clicked)
	
	-- Close button (if exists) - auto-claims on close
	local closeButton = MainFrame:FindFirstChild("Close")
	if closeButton and closeButton:IsA("GuiButton") then
		closeButton.MouseButton1Click:Connect(function()
			ClosePopup(true)
		end)
	end
	
	-- Auto-claim when frame is closed by Escape or other means (detect visibility change)
	-- Only if there's still pending earnings (purchase might have already claimed)
	OfflineEarningsFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not OfflineEarningsFrame.Visible and currentPendingAmount > 0 and not isProcessing then
			-- Frame was closed externally (Escape, CloseFrame tag), auto-claim
			-- But only if the server hasn't already cleared it (e.g. purchase succeeded)
			local Client_Data = require(script.Parent.Parent.Core.Client_Data)
			local replica = Client_Data:GetReplica()
			if replica and (replica.Data.PendingOfflineEarnings or 0) > 0 then
				isProcessing = true
				OfflineHandler:FireServer("Free")
				currentPendingAmount = 0
			else
				-- Already claimed (purchase succeeded), just clear local state
				currentPendingAmount = 0
				isProcessing = false
			end
		end
	end)
	
	-- Listen for PendingOfflineEarnings being cleared (purchase succeeded or claimed)
	local Client_Data = require(script.Parent.Parent.Core.Client_Data)
	task.spawn(function()
		local replica = Client_Data:GetReplica()
		if not replica then
			-- Wait for replica if not available yet
			task.wait(1)
			replica = Client_Data:GetReplica()
		end
		
		if replica then
			replica:ListenToChange({"PendingOfflineEarnings"}, function(newValue)
				-- If pending cleared (0 or nil) and frame is open, close it
				if (newValue == nil or newValue == 0) and OfflineEarningsFrame.Visible then
					currentPendingAmount = 0
					isProcessing = false
					ClosePopup(false) -- Don't auto-claim again (already cleared)
				end
			end)
		end
	end)
	
	-- Ensure frame is hidden on startup
	OfflineEarningsFrame.Visible = false
end

return Module
