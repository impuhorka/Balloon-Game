--[[
	Server_RagdollSystem.lua
	
	Centralized ragdoll system using BoolValue approach (R15 only)
	Shared by Server_Slapper and Server_GameHandler
]]

local RunService = game:GetService("RunService")

local RagdollSystem = {}

--[[
	Setup ragdoll system for a character (R15 BoolValue approach)
]]
function RagdollSystem:Setup(character)
	local ragdollValue = character:FindFirstChild("Ragdoll")
	if not ragdollValue then
		ragdollValue = Instance.new("BoolValue")
		ragdollValue.Name = "Ragdoll"
		ragdollValue.Parent = character
	end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
end

--[[
	Start ragdoll physics on a character
]]
function RagdollSystem:Start(character)
	if not character then return end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	if not hrp or not humanoid then return end
	
	-- Check if it's R15
	if not character:FindFirstChild("LowerTorso") then 
		return 
	end
	
	-- Create TorsoWeld to keep HRP connected to body
	if not hrp:FindFirstChild("TorsoWeld") then
		local torsoWeld = Instance.new("Weld")
		torsoWeld.Part0 = hrp
		torsoWeld.Part1 = character.LowerTorso
		torsoWeld.Name = "TorsoWeld"
		torsoWeld:AddTag("RagdollStuff")
		torsoWeld.Parent = hrp
	end
	
	-- Disable RootJoint
	local rootJoint = hrp:FindFirstChild("RootJoint")
	if rootJoint then
		rootJoint.Enabled = false
	end
	
	task.wait()
	
	-- Disable humanoid control
	humanoid.JumpPower = 0
	humanoid.WalkSpeed = 0
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	
	-- Process all Motor6D joints (except RootJoint)
	for _, motor6D in pairs(character:GetDescendants()) do
		if not motor6D:IsA("Motor6D") or motor6D == rootJoint or motor6D.Enabled == false then 
			continue 
		end
		
		-- Only ragdoll specific arm and leg joints
		local jointName = motor6D.Name
		local shouldRagdoll = false
		
		if jointName == "RightShoulder" or jointName == "LeftShoulder" then
			shouldRagdoll = true
		elseif jointName == "RightHip" or jointName == "LeftHip" then
			shouldRagdoll = true
		elseif jointName == "RightKnee" or jointName == "LeftKnee" then
			shouldRagdoll = true
		elseif jointName == "RightElbow" or jointName == "LeftElbow" then
			shouldRagdoll = true
		end
		
		if not shouldRagdoll then continue end
		
		-- Create invisible collider part
		local colliderPart = Instance.new("Part")
		colliderPart.Size = motor6D.Part1.Size / 1.7
		colliderPart.CFrame = motor6D.Part1.CFrame
		colliderPart.Massless = true
		colliderPart.CanQuery = false
		colliderPart.CanTouch = false
		colliderPart.Transparency = 1
		colliderPart.Name = "ColliderPart"
		colliderPart:AddTag("RagdollStuff")
		colliderPart.Parent = character
		
		-- Weld collider to the part
		local colliderWeld = Instance.new("Weld")
		colliderWeld.Part0 = colliderPart
		colliderWeld.Part1 = motor6D.Part1
		colliderWeld.Name = "ColliderPartWeld"
		colliderWeld:AddTag("RagdollStuff")
		colliderWeld.Parent = colliderPart
		
		-- Create attachments for BallSocketConstraint
		local attach0 = Instance.new("Attachment")
		attach0.CFrame = motor6D.C0
		attach0.Name = "RagdollAttach0"
		attach0:AddTag("RagdollStuff")
		attach0.Parent = motor6D.Part0
		
		local attach1 = Instance.new("Attachment")
		attach1.CFrame = motor6D.C1
		attach1.Name = "RagdollAttach1"
		attach1:AddTag("RagdollStuff")
		attach1.Parent = motor6D.Part1
		
		-- Create BallSocketConstraint
		local constraint = Instance.new("BallSocketConstraint")
		constraint.Attachment0 = attach0
		constraint.Attachment1 = attach1
		constraint.LimitsEnabled = true
		constraint.TwistLimitsEnabled = true
		
		-- Set limits based on joint type
		if jointName == "RightKnee" or jointName == "LeftKnee" then
			constraint.UpperAngle = 30
			constraint.TwistUpperAngle = 2
			constraint.TwistLowerAngle = -2
		elseif jointName == "RightElbow" or jointName == "LeftElbow" then
			constraint.UpperAngle = 35
			constraint.TwistUpperAngle = 3
			constraint.TwistLowerAngle = -3
		elseif jointName == "RightShoulder" or jointName == "LeftShoulder" then
			constraint.UpperAngle = 60
			constraint.TwistUpperAngle = 30
			constraint.TwistLowerAngle = -30
		elseif jointName == "RightHip" or jointName == "LeftHip" then
			constraint.UpperAngle = 25
			constraint.TwistUpperAngle = 15
			constraint.TwistLowerAngle = -15
		end
		
		constraint.Name = "RagdollConstraint"
		constraint:AddTag("RagdollStuff")
		constraint.Parent = character
		
		-- Disable the original joint
		motor6D.Enabled = false
	end
end

--[[
	Stop ragdoll physics on a character
]]
function RagdollSystem:Stop(character)
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid and humanoid.Health <= 0 then return end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	-- Wait for physics to settle
	RunService.Heartbeat:Wait()
	task.wait()
	
	-- Anchor HRP temporarily
	hrp.Anchored = true
	
	-- Find ground position
	local getUpCFrame = CFrame.new(hrp.Position)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	rayParams.FilterDescendantsInstances = {character}
	
	local rayEnd = hrp.Position + Vector3.new(0, -3, 0) - hrp.Position
	local rayResult = workspace:Raycast(hrp.Position, rayEnd, rayParams)
	if rayResult then
		getUpCFrame = CFrame.new(rayResult.Position + Vector3.new(0, 3, 0))
	end
	
	hrp.CFrame = getUpCFrame
	
	-- Restore humanoid control
	humanoid.PlatformStand = false
	RunService.Heartbeat:Wait()
	humanoid.AutoRotate = true
	hrp.Anchored = false
	
	-- Clean up all ragdoll objects
	for _, bodyPart in pairs(character:GetDescendants()) do
		if bodyPart:HasTag("RagdollStuff") then
			bodyPart:Destroy()
		end
		if bodyPart:IsA("Motor6D") then
			bodyPart.Enabled = true
		end
	end
	
	-- Remove TorsoWeld
	if hrp:FindFirstChild("TorsoWeld") then
		hrp.TorsoWeld:Destroy()
	end
	
	local baseWalkSpeed = game.StarterPlayer.CharacterWalkSpeed
	local baseJumpPower = game.StarterPlayer.CharacterJumpPower
	
	humanoid.WalkSpeed = baseWalkSpeed
	humanoid.JumpPower = baseJumpPower
end

--[[
	Connect ragdoll events for a character
]]
function RagdollSystem:ConnectEvents(character)
	local ragdollValue = character:FindFirstChild("Ragdoll")
	if ragdollValue then
		ragdollValue.Changed:Connect(function(value)
			if value then
				RagdollSystem:Start(character)
			else
				RagdollSystem:Stop(character)
			end
		end)
		return
	end
	
	-- Listen for when ragdoll value is added
	character.ChildAdded:Connect(function(child)
		if not child:IsA("BoolValue") or child.Name ~= "Ragdoll" then return end
		child.Changed:Connect(function(value)
			if value then
				RagdollSystem:Start(character)
			else
				RagdollSystem:Stop(character)
			end
		end)
	end)
end

return RagdollSystem
