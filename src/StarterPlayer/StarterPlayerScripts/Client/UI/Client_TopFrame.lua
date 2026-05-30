--// Client_TopFrame - Listens to replica and updates UI elements
--// CurrencyFrame: Cash, Speed (rolling animation + bounce like SingingX/Reference)
--// LeftFrame.Buttons.Rebirth.AmountFrame: Rebirth count

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local Client_Data = require(script.Parent.Parent.Core.Client_Data)
local Shared_Shorten = require(ReplicatedStorage.Modules.Utilities.Shared_Shorten)

local Module = {}

-- Animation tracking per currency (rolling number + bounce)
local currencyAnimations = {
	Cash = { currentValue = 0, targetValue = 0, connection = nil },
	Speed = { currentValue = 0, targetValue = 0, connection = nil },
	Rebirths = { currentValue = 0, targetValue = 0, connection = nil }
}

-- Get the label that shows the amount (Amount or Title, whichever exists)
local function getAmountLabel(frame)
	if not frame then return nil end
	local amount = frame:FindFirstChild("Amount")
	if amount and amount:IsA("TextLabel") then
		return amount
	end
	local title = frame:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		return title
	end
	return nil
end

-- Gain/loss gradient colors (Client_ScreenPopup pattern)
local GAIN_COLOR = Color3.fromHex("22c55e")   -- Green
local LOSS_COLOR = Color3.fromHex("ef4444")  -- Red

--- Ensure AddUIGradient and RemoveUIGradient exist on label; return them
local function ensureGradients(label)
	if not label then return nil, nil end
	local addGrad = label:FindFirstChild("AddUIGradient")
	local removeGrad = label:FindFirstChild("RemoveUIGradient")
	if not addGrad and label:IsA("GuiObject") then
		addGrad = Instance.new("UIGradient")
		addGrad.Name = "AddUIGradient"
		addGrad.Color = ColorSequence.new(GAIN_COLOR, GAIN_COLOR:Lerp(Color3.new(1, 1, 1), 0.3))
		addGrad.Enabled = false
		addGrad.Parent = label
	end
	if not removeGrad and label:IsA("GuiObject") then
		removeGrad = Instance.new("UIGradient")
		removeGrad.Name = "RemoveUIGradient"
		removeGrad.Color = ColorSequence.new(LOSS_COLOR, LOSS_COLOR:Lerp(Color3.new(1, 1, 1), 0.3))
		removeGrad.Enabled = false
		removeGrad.Parent = label
	end
	return addGrad, removeGrad
end

--- Apply gain/loss gradient on label (AddUIGradient = green, RemoveUIGradient = red)
local function applyGradient(label, isGain)
	local addGrad, removeGrad = ensureGradients(label)
	if not addGrad and not removeGrad then return end
	if isGain then
		if addGrad then addGrad.Enabled = true end
		if removeGrad then removeGrad.Enabled = false end
	else
		if addGrad then addGrad.Enabled = false end
		if removeGrad then removeGrad.Enabled = true end
	end
end

--- Reset gradients (disable both so label returns to default color)
local function resetGradient(label)
	local addGrad = label and label:FindFirstChild("AddUIGradient")
	local removeGrad = label and label:FindFirstChild("RemoveUIGradient")
	if addGrad then addGrad.Enabled = false end
	if removeGrad then removeGrad.Enabled = false end
end

--- Trigger bounce effect on a currency label using UIScale (Reference/SingingX pattern)
--- Gradient flashes during UP phase only, resets when DOWN phase starts
--- @param onBounceUp function? - Called when bounce reaches peak (down phase starts - disable gradient here)
local function triggerBounce(label, onBounceUp)
	if not label then return end
	-- UIScale drives the bounce animation (1 -> 1.1 -> 1)
	local scaleObj = label:FindFirstChild("UIScale")
	if not scaleObj then
		scaleObj = Instance.new("UIScale")
		scaleObj.Name = "UIScale"
		scaleObj.Scale = 1
		scaleObj.Parent = label
	end
	scaleObj.Scale = 1
	local upInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local downInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local upTween = TweenService:Create(scaleObj, upInfo, { Scale = 1.1 })
	local downTween = TweenService:Create(scaleObj, downInfo, { Scale = 1 })
	upTween.Completed:Connect(function()
		-- Bounce reached peak - disable gradient now (down phase starts)
		if onBounceUp then onBounceUp() end
		downTween:Play()
	end)
	downTween.Completed:Connect(function()
		scaleObj.Scale = 1
	end)
	upTween:Play()
end

--- Animate currency value with rolling number effect (Reference/SingingX pattern)
--- Uses UIScale for bounce, AddUIGradient/RemoveUIGradient for gain/loss feedback
--- @param currencyName string - "Cash", "Speed", or "Rebirths"
--- @param newValue number - Target value
--- @param label TextLabel - UI label to update
--- @param formatter fun(n: number): string - Format function (e.g. Shared_Shorten.Number or tostring)
local function animateCurrency(currencyName, newValue, label, formatter)
	local anim = currencyAnimations[currencyName]
	if not anim or not label then return end
	formatter = formatter or tostring

	-- Stop any existing animation
	if anim.connection then
		anim.connection:Disconnect()
		anim.connection = nil
	end

	anim.targetValue = newValue
	local diff = math.abs(anim.targetValue - anim.currentValue)
	local isGain = newValue > anim.currentValue

	-- Apply gain/loss gradient (AddUIGradient = green, RemoveUIGradient = red)
	applyGradient(label, isGain)

	if diff < 1 then
		anim.currentValue = anim.targetValue
		label.Text = formatter(math.floor(anim.currentValue))
		triggerBounce(label, function() resetGradient(label) end)
		return
	end

	-- +1 increment: skip rolling, just bounce
	if diff == 1 then
		anim.currentValue = anim.targetValue
		label.Text = formatter(math.floor(anim.currentValue))
		triggerBounce(label, function() resetGradient(label) end)
		return
	end

	triggerBounce(label, function() resetGradient(label) end)
	local startValue = anim.currentValue
	local startTime = tick()
	local duration = 0.8

	anim.connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local progress = math.min(elapsed / duration, 1)
		local easedProgress = 1 - math.pow(1 - progress, 3)
		anim.currentValue = startValue + (anim.targetValue - startValue) * easedProgress
		label.Text = formatter(math.floor(anim.currentValue))
		if progress >= 1 then
			anim.currentValue = anim.targetValue
			label.Text = formatter(math.floor(anim.currentValue))
			anim.connection:Disconnect()
			anim.connection = nil
		end
	end)
end

function Module:Init()
	-- Wait for data to be ready
	Client_Data:WaitUntilReady()
	local replica = Client_Data:GetReplica()
	if not replica then
		warn("⚠️ Client_TopFrame: No replica available")
		return
	end

	-- Wait for Main.CurrencyFrame (StarterGui.Main is cloned to PlayerGui)
	local playerGui = Player:WaitForChild("PlayerGui", 10)
	if not playerGui then return end

	local main = playerGui:WaitForChild("Main", 10)
	if not main then
		warn("⚠️ Client_TopFrame: Main not found in PlayerGui")
		return
	end

	local currencyFrame = main:WaitForChild("CurrencyFrame", 10)
	if not currencyFrame then
		warn("⚠️ Client_TopFrame: Main.CurrencyFrame not found")
		return
	end

	local cashFrame = currencyFrame:FindFirstChild("Cash")
	local speedFrame = currencyFrame:FindFirstChild("Speed")

	local cashLabel = getAmountLabel(cashFrame)
	local speedLabel = getAmountLabel(speedFrame)
	
	-- ArcadeTickets: under Speed, show during Arcade event only
	local arcadeTicketsFrame = speedFrame and speedFrame:FindFirstChild("ArcadeTickets")
	local arcadeTicketsAmountLabel = arcadeTicketsFrame and arcadeTicketsFrame:FindFirstChild("Amount")
	if arcadeTicketsFrame then
		arcadeTicketsFrame.Visible = false -- Hidden until Arcade event starts
	end
	
	-- Friend boost label
	local friendBoostLabel = cashFrame and cashFrame:FindFirstChild("FriendBoost") or nil
	
	-- Get LeftFrame for Rebirth display
	local leftFrame = main:WaitForChild("LeftFrame", 10)
	local rebirthButton = leftFrame and leftFrame:FindFirstChild("Buttons") and leftFrame.Buttons:FindFirstChild("Rebirth")
	local rebirthAmountFrame = rebirthButton and rebirthButton:FindFirstChild("AmountFrame")
	local rebirthLabel = rebirthAmountFrame and rebirthAmountFrame:FindFirstChild("Amount")

	local function updateFriendBoost()
		if not friendBoostLabel then return end
		local boostPercent = Player:GetAttribute("FriendCashBoost") or 0
		-- Use rich text with yellow color for the number and %
		friendBoostLabel.Text = string.format('Friend Cash Boost: <font color="#ffd630">%d%%</font>', boostPercent)
	end

	local data = replica.Data
	local cashFormatter = function(n)
		if n == math.huge or n >= 1e308 then
			return "∞" -- Infinity symbol
		end
		return Shared_Shorten:Number(math.floor(n))
	end

	-- Initial values (instant, no animation on first load)
	local initialCash = data.Cash or 0
	local initialRebirths = data.Rebirths or 0
	local initialSpeed = data.Speed or 0
	currencyAnimations.Cash.currentValue = initialCash
	currencyAnimations.Cash.targetValue = initialCash
	currencyAnimations.Rebirths.currentValue = initialRebirths
	currencyAnimations.Rebirths.targetValue = initialRebirths
	currencyAnimations.Speed.currentValue = initialSpeed
	currencyAnimations.Speed.targetValue = initialSpeed

	if cashLabel then
		if initialCash == math.huge or initialCash >= 1e308 then
			cashLabel.Text = "∞"
		else
			cashLabel.Text = Shared_Shorten:Number(initialCash)
		end
	end
	if rebirthLabel then
		rebirthLabel.Text = tostring(initialRebirths)
	end
	if speedLabel then
		speedLabel.Text = tostring(initialSpeed)
	end

	updateFriendBoost()

	-- Listen for changes (use rolling animation + bounce)
	replica:ListenToChange({"Cash"}, function(newValue)
		if cashLabel then
			animateCurrency("Cash", newValue or 0, cashLabel, cashFormatter)
		end
	end)
	replica:ListenToChange({"Rebirths"}, function(newValue)
		if rebirthLabel then
			animateCurrency("Rebirths", newValue or 0, rebirthLabel, tostring)
		end
	end)
	replica:ListenToChange({"Speed"}, function(newValue)
		if speedLabel then
			animateCurrency("Speed", newValue or 0, speedLabel, tostring)
		end
	end)
	
	-- Arcade event: show/hide Main.CurrencyFrame.Speed.ArcadeTickets and keep Amount in sync
	local function updateArcadeTicketsAmount(ticketCount)
		if arcadeTicketsAmountLabel then
			arcadeTicketsAmountLabel.Text = tostring(ticketCount or 0)
		end
	end
	
	local function setArcadeTicketsVisible(visible)
		if arcadeTicketsFrame then
			arcadeTicketsFrame.Visible = visible
		end
		if visible then
			local tickets = replica.Data.EventCurrencies and replica.Data.EventCurrencies.ArcadeTickets or 0
			updateArcadeTicketsAmount(tickets)
		end
	end
	
	replica:ListenToChange({"EventCurrencies", "ArcadeTickets"}, function(newTickets)
		if arcadeTicketsFrame and arcadeTicketsFrame.Visible and arcadeTicketsAmountLabel then
			updateArcadeTicketsAmount(newTickets)
		end
	end)
	
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	local eventUIEvent = eventsFolder and eventsFolder:FindFirstChild("EventUIEvent")
	if eventUIEvent then
		eventUIEvent.OnClientEvent:Connect(function(action, eventData)
			if action == "Start" and eventData and eventData.eventName == "Arcade" then
				setArcadeTicketsVisible(true)
			elseif action == "End" and eventData == "Arcade" then
				setArcadeTicketsVisible(false)
			elseif action == "Sync" and type(eventData) == "table" then
				-- Late joiner: if Arcade is in the active events list, show ArcadeTickets
				local isArcadeActive = false
				for _, ev in ipairs(eventData) do
					if ev.eventName == "Arcade" then
						isArcadeActive = true
						break
					end
				end
				setArcadeTicketsVisible(isArcadeActive)
			end
		end)
	end
	
	-- Late joiner: if Arcade is already active when we init
	if arcadeTicketsFrame and ReplicatedStorage:GetAttribute("ActiveEvent") == "Arcade" then
		setArcadeTicketsVisible(true)
	end
	
	-- Listen for friend boost attribute changes (set by server)
	Player:GetAttributeChangedSignal("FriendCashBoost"):Connect(updateFriendBoost)

end

return Module
