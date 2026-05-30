--// Client_WeatherHandler: Camera-relative grid-based weather system (rain, snow, etc.)
--// Listens to server lighting changes and manages weather effects

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Camera = workspace.CurrentCamera

local Shared_Sounds = require(ReplicatedStorage.Modules.Settings.Shared_Sounds)
local Client_Sounds = require(script.Parent.Client_Sounds)

local POLL_HEIGHT = 40

-- MODULE STATE
local currentWeather = nil -- Active weather handler instance
local currentWeatherType = nil -- "Rain", "Snow", etc.

local Client_WeatherHandler = {}

-- WEATHER HANDLER CLASS
local WeatherHandler = {}
WeatherHandler.__index = WeatherHandler

function WeatherHandler.new(floorPart, skyPart, weatherType)
	local self = setmetatable({}, WeatherHandler)
	
	self.FloorPart = floorPart
	self.SkyPart = skyPart
	self.CellSize = 10
	self.CellAssets = {}
	self.CellData = {}
	self.ParticleCache = {}
	self.ParticleState = {}
	self.CurrentRateMult = 1
	self.LastHeightUpdated = -1
	self.Destroyed = false
	self.TargetVolume = 0.35 -- Rain/weather sound volume (lower = quieter)
	
	-- Create sound from Shared_Sounds
	local soundId = Shared_Sounds.SFX[weatherType]
	if soundId then
		self.Sound = Instance.new("Sound")
		self.Sound.SoundId = soundId
		self.Sound.Volume = 0
		self.Sound.Looped = true
		Client_Sounds:SetGroup(self.Sound, "SFX")
		self.Sound.Parent = script
		self.Sound:Play()
		
		self:FadeInSound()
	end
	
	local effectsFolder = workspace:FindFirstChild("Effects")
	if not effectsFolder then
		effectsFolder = Instance.new("Folder")
		effectsFolder.Name = "Effects"
		effectsFolder.Parent = workspace
	end
	
	self.Model = Instance.new("Model", effectsFolder)
	self.Model.Name = "WeatherModel"
	
	return self
end

function WeatherHandler:SetScaleData(cell_radius, cell_size)
	self.Model:ClearAllChildren()
	self.CellSize = cell_size
	self.CellAssets = {}
	self.CellData = {}
	self.ParticleCache = {}
	self.ParticleState = {}
	
	for x = -cell_radius, cell_radius do
		for y = -cell_radius, cell_radius do
			if math.abs(x) + math.abs(y) > cell_radius then continue end
			
			local dist = Vector3.new(x, y).Magnitude * cell_size
			local dist_scale = 2^(-dist / 25)
			
			local assets = {}
			local cellKey = Vector3.new(x, y)
			
			-- Clone sky part (falling particles)
			if self.SkyPart then
				local part = self.SkyPart:Clone()
				part.Parent = self.Model
				local rate_scale = cell_size^2 / part.Size.X / part.Size.Z * dist_scale * self.CurrentRateMult
				
				-- Cache particle emitters
				local particles = {}
				for _, particle in ipairs(part:GetDescendants()) do
					if particle:IsA("ParticleEmitter") then
						particle.Rate *= rate_scale
						table.insert(particles, particle)
					end
				end
				self.ParticleCache[part] = particles
				self.ParticleState[part] = false
				
				part.Size = Vector3.new(1, 0, 1) * cell_size
				assets.RainPart = part
			end
			
			-- Clone floor part (splash particles)
			if self.FloorPart then
				local part = self.FloorPart:Clone()
				part.Parent = self.Model
				local rate_scale = cell_size^2 / part.Size.X / part.Size.Z * dist_scale * self.CurrentRateMult
				
				-- Cache particle emitters
				local particles = {}
				for _, particle in ipairs(part:GetDescendants()) do
					if particle:IsA("ParticleEmitter") then
						particle.Rate *= rate_scale
						table.insert(particles, particle)
					end
				end
				self.ParticleCache[part] = particles
				self.ParticleState[part] = false
				
				part.Size = Vector3.new(1, 0, 1) * cell_size
				assets.FloorPart = part
			end
			
			self.CellData[cellKey] = {FloorHeight = 0, Active = false}
			self.CellAssets[cellKey] = assets
		end
	end
end

-- Optimized particle enabling with state tracking
local function set_all_enabled(handler, part, enabled)
	if handler.ParticleState[part] == enabled then
		return
	end
	
	local particles = handler.ParticleCache[part]
	if particles then
		for _, particle in ipairs(particles) do
			particle.Enabled = enabled
		end
		handler.ParticleState[part] = enabled
	end
end

function WeatherHandler:UpdateHeight(pos)
	local data = self.CellData[pos]
	if not data then return end
	
	local camera_pos = Camera.CFrame.Position
	local world_pos = camera_pos + Vector3.new(pos.X * self.CellSize, 0, pos.Y * self.CellSize)

	-- Check if indoors (upward raycast)
	local hit_up = workspace:Raycast(world_pos, Vector3.yAxis * POLL_HEIGHT)
	if hit_up ~= nil then
		data.Active = false
		return
	end
	
	data.Active = true

	-- Check for ground (downward raycast)
	local dist_down = 40 + 40 / math.max(pos.Magnitude, 1)
	local hit = workspace:Raycast(world_pos, Vector3.yAxis * -dist_down)
	if hit ~= nil then
		data.FloorHeight = hit.Position.Y
	else
		data.FloorHeight = nil
	end
end

local function get_spiral_pos(n)
	if n == 0 then return Vector3.zero end
	n -= 1
	local spiral_number = math.floor(0.5 + math.sqrt(4 + 8 * n) * 0.25)
	local offset = 2 * spiral_number * (spiral_number - 1)
	local prog = n - offset
	local x = -spiral_number + math.min(prog, spiral_number * 2) + math.min(spiral_number * 2 - prog, 0)
	local y = math.min(prog, spiral_number) + math.clamp(spiral_number - prog, -spiral_number * 2, 0) + math.max(prog - spiral_number * 3, 0)
	return Vector3.new(x, y)
end

function WeatherHandler:UpdateNextHeight()
	local update_index = self.LastHeightUpdated + 1
	local pos = get_spiral_pos(update_index)
	if self.CellData[pos] == nil then
		self.LastHeightUpdated = -1
		return self:UpdateNextHeight()
	end
	self:UpdateHeight(pos)
	self.LastHeightUpdated = update_index
end

function WeatherHandler:UpdateCFrames()
	local parts = {}
	local cframes = {}
	local camera_pos = Camera.CFrame.Position
	
	for offset, assets in pairs(self.CellAssets) do
		local data = self.CellData[offset]
		if not data.Active then
			if assets.FloorPart then set_all_enabled(self, assets.FloorPart, false) end
			if assets.RainPart then set_all_enabled(self, assets.RainPart, false) end
			continue
		end
		
		local world_pos = camera_pos + Vector3.new(offset.X * self.CellSize, 0, offset.Y * self.CellSize)
		local height = Camera.CFrame.LookVector.Y * 10 + 10
		
		-- Sky particles (falling rain/snow)
		if assets.RainPart then
			set_all_enabled(self, assets.RainPart, true)
			table.insert(parts, assets.RainPart)
			table.insert(cframes, CFrame.new(world_pos + Vector3.yAxis * height))
		end
		
		-- Floor particles (splashes)
		if data.FloorHeight ~= nil and assets.FloorPart then
			set_all_enabled(self, assets.FloorPart, true)
			table.insert(parts, assets.FloorPart)
			table.insert(cframes, CFrame.new(world_pos * Vector3.new(1, 0, 1) + Vector3.yAxis * data.FloorHeight))
		elseif assets.FloorPart then
			set_all_enabled(self, assets.FloorPart, false)
		end
	end
	
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function WeatherHandler:Init()
	task.spawn(function()
		while not self.Destroyed do
			task.wait(1/10)
			self:UpdateNextHeight()
			self:UpdateCFrames()
		end
	end)
end

function WeatherHandler:FadeInSound()
	if not self.Sound then return end
	
	local TweenService = game:GetService("TweenService")
	local tweenInfo = TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(self.Sound, tweenInfo, {Volume = self.TargetVolume})
	tween:Play()
end

function WeatherHandler:FadeOutSound(callback)
	if not self.Sound then 
		if callback then callback() end
		return 
	end
	
	local TweenService = game:GetService("TweenService")
	local tweenInfo = TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tween = TweenService:Create(self.Sound, tweenInfo, {Volume = 0})
	tween:Play()
	
	if callback then
		tween.Completed:Wait()
		callback()
	end
end

function WeatherHandler:Destroy()
	self.Destroyed = true
	
	self:FadeOutSound(function()
		if self.Sound then 
			self.Sound:Destroy() 
		end
	end)
	
	self.Model:Destroy()
end

-- MODULE FUNCTIONS
function Client_WeatherHandler:Init()
	local Lighting = game:GetService("Lighting")
	
	-- Read initial weather state
	local initialWeather = Lighting:GetAttribute("Weather")
	if initialWeather then
		self:StartWeather(initialWeather)
	end
	
	-- Listen for weather changes
	Lighting:GetAttributeChangedSignal("Weather"):Connect(function()
		local newWeather = Lighting:GetAttribute("Weather")
		self:HandleWeatherChange(newWeather)
	end)
end

function Client_WeatherHandler:HandleWeatherChange(newWeatherType)
	if newWeatherType == currentWeatherType then return end
	
	if currentWeather then
		currentWeather:Destroy()
		currentWeather = nil
		currentWeatherType = nil
	end
	
	if newWeatherType then
		self:StartWeather(newWeatherType)
	end
end

function Client_WeatherHandler:StartWeather(weatherType)
	local Storage = ReplicatedStorage:WaitForChild("Storage")
	local WeatherFolder = Storage:FindFirstChild("Weather")
	
	if not WeatherFolder then
		warn("⚠️ Weather folder not found in Storage")
		return
	end
	
	local weatherAssets = WeatherFolder:FindFirstChild(weatherType)
	if not weatherAssets then
		warn("⚠️ Weather assets not found for:", weatherType)
		return
	end
	
	local floorPart = weatherAssets:FindFirstChild("Floor")
	local skyPart = weatherAssets:FindFirstChild("Sky")
	
	if not skyPart then
		warn("⚠️ Sky part not found for:", weatherType)
		return
	end
	
	local handler = WeatherHandler.new(floorPart, skyPart, weatherType)
	handler:SetScaleData(2, 35)
	handler:Init()
	
	currentWeather = handler
	currentWeatherType = weatherType
end

function Client_WeatherHandler:StopWeather()
	if currentWeather then
		currentWeather:Destroy()
		currentWeather = nil
		currentWeatherType = nil
	end
end

return Client_WeatherHandler
