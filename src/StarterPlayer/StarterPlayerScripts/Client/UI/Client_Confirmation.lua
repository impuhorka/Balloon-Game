--[[
	Client_Confirmation - Confirmation dialog for critical actions
	Handles confirmation for selling high-value brainrots
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)
local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)

local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui

local Module = {}

-- State
local isConfirmationOpen = false
local currentConfirmation = nil

-- UI References (will be set in Init)
local ConfirmationFrame = nil
local DarkenFrame = nil

-- Helper: Get rarity color
local function getRarityColor(rarity)
	local colors = {
		Normal = "rgb(200, 200, 200)",
		Shiny = "rgb(255, 215, 0)",
		Special = "rgb(255, 100, 255)",
		Legendary = "rgb(255, 50, 50)",
	}
	return colors[rarity] or "rgb(255, 255, 255)"
end

-- Show confirmation for selling brainrots
function Module:ShowSellConfirmation(brainrotData, sellPrice, isSellAll, onConfirmCallback)
	if not brainrotData then return end
	
	local title = ""
	local description = ""
	
	local cashColor = "rgb(255, 188, 20)" -- Gold color for cash
	
	if isSellAll then
		-- Count total brainrots
		local totalCount = 0
		local rarityCount = {}
		
		if brainrotData.highValueBrainrots then
			for _, brainrot in pairs(brainrotData.highValueBrainrots) do
				totalCount = totalCount + 1
				local rarity = brainrot.Modifier or "Normal"
				rarityCount[rarity] = (rarityCount[rarity] or 0) + 1
			end
		end
		
		-- Title with count and price
		title = string.format("Sell %d Brainrot%s for $%s?", 
			totalCount, 
			totalCount == 1 and "" or "s",
			Shared_Shorten:Number(sellPrice))
		
		-- Format colored rarity list for description
		local coloredRarities = {}
		for rarity, count in pairs(rarityCount) do
			local color = getRarityColor(rarity)
			local text = string.format("<font color=\"%s\">%s</font>", color, rarity)
			if count > 1 then
				text = text .. string.format(" (x%d)", count)
			end
			table.insert(coloredRarities, text)
		end
		
		if #coloredRarities > 0 then
			local rarityList = table.concat(coloredRarities, ", ")
			description = string.format("This includes: %s", rarityList)
		else
			description = "Are you sure you want to proceed?"
		end
	else
		-- Single brainrot confirmation
		local rarity = brainrotData.Modifier or "Normal"
		local rarityColor = getRarityColor(rarity)
		local displayName = brainrotData.ConfigName or "Brainrot"
		
		title = string.format("Sell %s for $%s?", displayName, Shared_Shorten:Number(sellPrice))
		description = string.format("<font color=\"%s\">%s</font> rarity", rarityColor, rarity)
	end
	
	self:ShowConfirmation(title, description, onConfirmCallback)
end

-- Show generic confirmation dialog
function Module:ShowConfirmation(title, description, onConfirmCallback, onCancelCallback)
	if isConfirmationOpen then return end
	if not ConfirmationFrame or not DarkenFrame then return end
	
	isConfirmationOpen = true
	currentConfirmation = {
		onConfirm = onConfirmCallback,
		onCancel = onCancelCallback
	}
	
	-- Set content
	local TitleLabel = ConfirmationFrame:FindFirstChild("Title")
	local DescriptionLabel = ConfirmationFrame:FindFirstChild("Description")
	
	if TitleLabel then
		TitleLabel.Text = title or "CONFIRM ACTION"
	end
	
	if DescriptionLabel then
		DescriptionLabel.Text = description or "Are you sure?"
		DescriptionLabel.RichText = true -- Enable RichText for colored text
	end
	
	-- Show frames
	DarkenFrame.Visible = true
	ConfirmationFrame.Visible = true
	
	-- Start animation from top (off-screen)
	ConfirmationFrame.Position = UDim2.new(0.5, 0, -0.5, 0)
	
	-- Animate darken frame
	TweenService:Create(DarkenFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.3
	}):Play()
	
	-- Animate confirmation to center
	TweenService:Create(ConfirmationFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.5, 0)
	}):Play()
	
	-- Play open sound
	if Module.Client_Sounds then
		Module.Client_Sounds:Play("Frame Open")
	end
end

-- Close confirmation dialog
function Module:CloseConfirmation()
	if not isConfirmationOpen then return end
	if not ConfirmationFrame or not DarkenFrame then return end
	
	isConfirmationOpen = false
	currentConfirmation = nil
	
	-- Animate darken frame back
	TweenService:Create(DarkenFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
		BackgroundTransparency = 1
	}):Play()
	
	-- Animate confirmation down and out
	TweenService:Create(ConfirmationFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, 1.5, 0)
	}):Play()
	
	-- Hide frames after animation
	task.delay(0.2, function()
		ConfirmationFrame.Visible = false
		DarkenFrame.Visible = false
		ConfirmationFrame.Position = UDim2.new(0.5, 0, -0.5, 0)
	end)
	
	-- Play close sound
	if Module.Client_Sounds then
		Module.Client_Sounds:Play("Frame Exit")
	end
end

-- Check if confirmation is open
function Module:IsConfirmationOpen()
	return isConfirmationOpen
end

-- Initialize confirmation system
function Module:Init()
	-- Get Client_Sounds from Library (set by init.client.lua)
	Module.Client_Sounds = self.Client_Sounds
	
	-- Wait for confirmation UI (in Main GUI)
	local Main = PlayerGui:WaitForChild("Main", 10)
	if not Main then
		warn("⚠️ Main GUI not found for confirmation system")
		return
	end
	
	-- Find confirmation frame directly in Main
	ConfirmationFrame = Main:FindFirstChild("ConfirmationFrame")
	if not ConfirmationFrame then
		warn("⚠️ ConfirmationFrame not found in Main")
		return
	end
	
	-- DarkenFrame should also be in Main (or as sibling)
	DarkenFrame = Main:FindFirstChild("DarkenFrame")
	if not DarkenFrame then
		warn("⚠️ DarkenFrame not found in Main")
		return
	end
	
	-- Ensure frames start hidden
	ConfirmationFrame.Visible = false
	ConfirmationFrame.Position = UDim2.new(0.5, 0, -0.5, 0)
	DarkenFrame.BackgroundTransparency = 1
	DarkenFrame.Visible = false
	
	-- Set up buttons
	local Buttons = ConfirmationFrame:FindFirstChild("Buttons")
	if Buttons then
		local ConfirmButton = Buttons:FindFirstChild("Confirm")
		local CancelButton = Buttons:FindFirstChild("Cancel")
		
		if ConfirmButton then
			local confirmBtn = ConfirmButton:FindFirstChild("Button")
			if confirmBtn then
				confirmBtn.MouseButton1Click:Connect(function()
					if currentConfirmation and currentConfirmation.onConfirm then
						currentConfirmation.onConfirm()
					end
					self:CloseConfirmation()
				end)
			end
		end
		
		if CancelButton then
			local cancelBtn = CancelButton:FindFirstChild("Button")
			if cancelBtn then
				cancelBtn.MouseButton1Click:Connect(function()
					if currentConfirmation and currentConfirmation.onCancel then
						currentConfirmation.onCancel()
					end
					self:CloseConfirmation()
				end)
			end
		end
	end
	
	-- Handle ESC key to close
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.KeyCode == Enum.KeyCode.Escape and isConfirmationOpen then
			self:CloseConfirmation()
		end
	end)
	
end

return Module
