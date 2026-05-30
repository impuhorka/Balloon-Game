local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer

local Events = ReplicatedStorage:WaitForChild("Events")
local IdleEvent = Events:WaitForChild("IdleHandler")

local AFK_TIME = 900
local CHECK_INTERVAL = 30

local isIdle = false
local idleStartTime = nil
local inputConnection = nil

local Module = {}

function Module:Init()
	local checkThread = nil
	
	Player.Idled:Connect(function()
		if not isIdle then
			isIdle = true
			idleStartTime = os.time()
			
			if inputConnection then
				inputConnection:Disconnect()
			end
			
			inputConnection = UserInputService.InputBegan:Connect(function()
				isIdle = false
				idleStartTime = nil
				if inputConnection then
					inputConnection:Disconnect()
					inputConnection = nil
				end
				if checkThread then
					task.cancel(checkThread)
					checkThread = nil
				end
			end)
			
			checkThread = task.spawn(function()
				while isIdle and Player.Parent do
					if idleStartTime then
						local currentTime = os.time()
						if (currentTime - idleStartTime) >= AFK_TIME then
							IdleEvent:FireServer()
							isIdle = false
							idleStartTime = nil
							if inputConnection then
								inputConnection:Disconnect()
								inputConnection = nil
							end
							break
						end
					end
					task.wait(CHECK_INTERVAL)
				end
				checkThread = nil
			end)
		end
	end)
end

return Module
