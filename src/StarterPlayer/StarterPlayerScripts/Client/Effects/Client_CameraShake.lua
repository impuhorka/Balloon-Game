local CameraShakeManager = {}
CameraShakeManager.__index = CameraShakeManager

local RunService = game:GetService("RunService")

local Camera = workspace.CurrentCamera
local Player = game.Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local activeShakes = {}
local isRunning = false

function CameraShakeManager:_startUpdateLoop()
	if isRunning then return end
	isRunning = true
	RunService:BindToRenderStep("CameraShakeManager", Enum.RenderPriority.Last.Value, function(dt)
		local totalOffset = Vector3.zero
		for i = #activeShakes, 1, -1 do
			local shake = activeShakes[i]
			shake.elapsedTime += dt
			local offset = shake.updateFunc(shake, dt)
			if offset then
				totalOffset += offset
			else
				table.remove(activeShakes, i)
			end
		end
		if totalOffset.Magnitude > 0 then
			Camera.CFrame = Camera.CFrame * CFrame.new(totalOffset)
		end
		if #activeShakes == 0 then
			RunService:UnbindFromRenderStep("CameraShakeManager")
			isRunning = false
		end
	end)
end

function CameraShakeManager:Start(intensity, frequency, duration, fadeOut)
	if not RunService:IsClient() then
		return
	end
	
	intensity = intensity or 1
	frequency = frequency or 10  -- Hz (how fast it shakes)
	duration = duration or 0.5
	fadeOut = fadeOut or 0.3  -- Fade out duration
	
	local shake = {
		intensity = intensity,
		frequency = frequency,
		duration = duration,
		fadeOut = fadeOut,
		elapsedTime = 0,
		seed = math.random(100000),  -- Random seed for Perlin-like noise
		updateFunc = function(self, dt)
			self.elapsedTime += dt
			
			-- Calculate fade multiplier (smooth curve)
			local fade = 1
			if self.elapsedTime > self.duration then
				-- Fade out phase
				local fadeProgress = (self.elapsedTime - self.duration) / self.fadeOut
				if fadeProgress >= 1 then return nil end
				fade = 1 - fadeProgress
				fade = fade * fade  -- Smooth curve (ease out)
			else
				-- Fade in phase (smooth start)
				local fadeInProgress = math.min(self.elapsedTime / 0.1, 1)
				fade = fadeInProgress * fadeInProgress  -- Smooth curve (ease in)
			end
			
			-- Generate smooth noise using time-based sampling
			local time = self.elapsedTime * self.frequency
			local noiseX = self:_smoothNoise(self.seed + time)
			local noiseY = self:_smoothNoise(self.seed + 1000 + time)
			
			-- Apply intensity and fade
			local offset = Vector3.new(
				noiseX * self.intensity * fade,
				noiseY * self.intensity * fade,
				0
			)
			
			return offset
		end,
		
		-- Simple smooth noise function (replaces random)
		_smoothNoise = function(self, t)
			return math.sin(t) * 0.5 + math.sin(t * 2.3) * 0.3 + math.sin(t * 4.7) * 0.2
		end
	}
	table.insert(activeShakes, shake)
	self:_startUpdateLoop()
end

function CameraShakeManager:ShakeInRadius(position, p)
	if not RunService:IsClient() then
		return
	end
	
	if not position then return end
	local character = Player.Character
	if not (character and character.PrimaryPart) then return end

	local radius       = p.Radius or p[1]
	local outerRadius  = p.OuterRadius or p[2]
	local intensity    = p.Intensity or p[3]
	local roughness    = p.Roughness or p[4]
	local damping      = p.Damping or p[5]
	local distance     = p.Distance or p[6]
	local duration     = p.Duration or p[7]

	if not radius then return end
	outerRadius = (outerRadius and outerRadius > radius) and outerRadius or radius * 2

	local dist = (character.PrimaryPart.Position - position).Magnitude
	if dist >= outerRadius then return end

	local scale = dist <= radius and 1 or 1 - (dist - radius) / (outerRadius - radius)

	self:Start((intensity or 1) * scale, roughness, duration, damping)
end

function CameraShakeManager:ShakePreset(preset, position)
	if not RunService:IsClient() then
		return
	end
	
	local pos = position
	if not pos then
		local character = Player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		pos = root.Position
	end

	if preset == "Punch" then
		self:Start(0.8, 15, 0.3, 0.2)  -- intensity, frequency, duration, fadeOut
	elseif preset == "Ascend" then
		self:Start(1.2, 8, 2.0, 0.5)   -- Gentle upward shake
	elseif preset == "DamageTaken" then
		self:Start(0.4, 20, 0.2, 0.1)  -- Quick sharp shake
	elseif preset == "Explosion" then
		self:Start(1.5, 12, 0.8, 0.4)  -- Strong explosion
	elseif preset == "Earthquake" then
		self:Start(0.6, 6, 3.0, 0.8)   -- Long slow shake
	elseif preset == "Nuke" then
		self:Start(2.0, 8, 1.5, 0.6)   -- Massive explosion
	elseif preset == "ConfettiShake" then
		self:Start(0.3, 12, 0.8, 0.3)  -- Gentle celebratory shake
	elseif preset == "Gentle" then
		self:Start(0.2, 8, 1.0, 0.4)   -- Very gentle shake
	elseif preset == "Heavy" then
		self:Start(1.0, 6, 1.5, 0.5)   -- Heavy impactful shake
	end
end

return CameraShakeManager
