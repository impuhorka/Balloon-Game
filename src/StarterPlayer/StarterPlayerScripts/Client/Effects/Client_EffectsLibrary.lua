--// Client_EffectsLibrary - Reusable effect utilities (sounds, highlights, debris)
--// Provides helper functions for common visual and audio effects

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared_Sounds = require(ReplicatedStorage.Modules.Settings.Shared_Sounds)
local Shared_Effects = require(ReplicatedStorage.Modules.Settings.Shared_Effects)
local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
local Shared_Rarity = require(ReplicatedStorage.Modules.Gameplay.Shared_Rarity)
local Shared_ModifierHandler = require(ReplicatedStorage.Modules.Gameplay.Shared_ModifierHandler)
local CameraShake = require(script.Parent.Client_CameraShake)
local Client_FOV = require(script.Parent.Parent.Effects.Client_FOV)
local Client_Sounds = require(script.Parent.Client_Sounds)
local Client_Popups = require(script.Parent.Parent.UI.Client_Popups)

local Player = Players.LocalPlayer
local Effects = {}

-- ========================================
-- CENTRALIZED EFFECTS DISPATCHER (SingingX Pattern)
-- ========================================

-- Listen for PlayEffect events - all visual effects route through here
task.spawn(function()
	local Events = ReplicatedStorage:WaitForChild("Events")
	local PlayEffect = Events:WaitForChild("PlayEffect", 10)
	if PlayEffect then
		PlayEffect.OnClientEvent:Connect(function(effectData)
			if effectData.effectType == "luckyblock" then
				Effects:PlayLuckyBlockOpening(effectData)
			elseif effectData.effectType == "confetti" then
				-- Future: Effects:PlayConfetti(effectData)
			elseif effectData.effectType == "fov" then
				-- FOV transition effect (camera zoom)
				Effects:PlayFOV(effectData.startFOV, effectData.endFOV, effectData.duration, effectData.easing)
			elseif effectData.effectType == "thunderbolt" then
				Effects:PlayThunderbolt(effectData.startPosition, effectData.endPosition, effectData.brainrotUID)
			elseif effectData.effectType == "cashrain" then
				-- Scale amount and duration by cash: Cash1 = lighter, Cash3 = heavier rain (size fixed)
				local cashAmount = effectData.cashAmount or 1000
				local amount = math.clamp(math.floor(20 + (cashAmount - 1000) / 24000 * 55), 20, 75)
				local duration = 1.5 + (cashAmount - 1000) / 24000 * 1.5 -- 1.5s to 3s
				Effects:PlayCashRain(amount, duration, 1)
			elseif effectData.effectType == "flash" then
				-- White flash effect for event intros
				Effects:PlayFlash(effectData.duration)
			elseif effectData.effectType == "cameraShake" then
				-- Camera shake effect with preset
				if effectData.preset then
					CameraShake:ShakePreset(effectData.preset, effectData.position)
				end
			elseif effectData.effectType == "meteor" then
				-- Meteor falling effect
				Effects:PlayMeteor(effectData.startPosition, effectData.impactPosition, effectData.duration, effectData.speed)
			elseif effectData.effectType == "meteorImpact" then
				-- Meteor impact explosion VFX + camera shake
				Effects:PlayMeteorImpact(effectData.impactPosition)
			elseif effectData.effectType == "piggyBlockDrop" then
				-- Piggy lucky block drop animation
				Effects:PlayPiggyBlockDrop(effectData)
			elseif effectData.effectType == "balloonPop" then
				Effects:PlayBalloonPop(effectData.position)
			end
			-- Add more effect types here as needed
		end)
	end
end)

-- ========================================
-- SOUND UTILITIES
-- ========================================

--[[
	Play a sound from the Shared_Sounds config
	@param parent - The parent instance for the sound
	@param soundName - The name of the sound in Shared_Sounds
	@param overrideProperties - Optional table to override sound properties
	@return Sound instance
]]
function Effects:PlaySound(parent: Instance, soundName: string, overrideProperties: {[string]: any}?)
	local soundConfig = Shared_Sounds[soundName]
	if not soundConfig then
		warn(("⚠️ Sound '%s' not found in Shared_Sounds"):format(soundName))
		return nil
	end
	
	local sound = Instance.new("Sound")
	sound.SoundId = soundConfig.SoundId
	sound.Volume = (overrideProperties and overrideProperties.Volume) or soundConfig.Volume or 1.0
	sound.RollOffMaxDistance = soundConfig.RollOffMaxDistance or 100
	
	-- Random playback speed if range provided
	if soundConfig.PlaybackSpeedRange then
		local min = soundConfig.PlaybackSpeedRange[1]
		local max = soundConfig.PlaybackSpeedRange[2]
		sound.PlaybackSpeed = math.random(min * 100, max * 100) / 100
	elseif overrideProperties and overrideProperties.PlaybackSpeed then
		sound.PlaybackSpeed = overrideProperties.PlaybackSpeed
	end
	
	-- Assign to SFX SoundGroup (respects volume settings)
	Client_Sounds:SetGroup(sound, "SFX")
	
	sound.Parent = parent
	sound:Play()
	
	-- Auto-cleanup when sound ends
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	
	return sound
end

--[[
	Play collection effect (confetti, rainbow highlight, sound, camera zoom)
	Called when brainrots are successfully collected
]]
function Effects:PlayCollectionEffect()
	-- Get player's RootPart
	local character = Player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	-- 1. CONFETTI VFX
	local VFX = ReplicatedStorage.Assets:FindFirstChild("VFX")
	if VFX then
		local confettiTemplate = VFX:FindFirstChild("Confetti_FX")
		if confettiTemplate then
			local confetti = confettiTemplate:Clone()
			confetti.Parent = workspace
			confetti:PivotTo(rootPart.CFrame)
			
			-- Emit particles using existing system
			self:EmitParticlesInContainer(confetti, 50)
			
			-- Cleanup after 3 seconds
			task.delay(3, function()
				confetti:Destroy()
			end)
		else
			warn("⚠️ Confetti_FX not found in Assets.VFX")
		end
	else
		warn("⚠️ VFX folder not found in Assets")
	end
	
	-- 2. COLLECTION SOUND
	Client_Sounds:Play("Brainrot Collection")
	
	-- 3. CAMERA ZOOM EFFECT
	local camera = workspace.CurrentCamera
	local originalFOV = camera.FieldOfView
	
	-- Lock FOV system so it doesn't interfere
	Client_FOV:LockFOV(2.5) -- Total effect duration
	
	-- Zoom out (increase FOV) - FIRST
	local zoomOutInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local zoomOutTween = TweenService:Create(camera, zoomOutInfo, {
		FieldOfView = originalFOV + 8 -- Subtle zoom out (less FOV change)
	})
	
	-- Zoom back in (return to original) - AFTER effects
	local zoomInInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local zoomInTween = TweenService:Create(camera, zoomInInfo, {
		FieldOfView = originalFOV
	})
	
	-- Sequence: Zoom out → play effects → hold → zoom back in
	zoomOutTween:Play()
	self:PlayRainbowHighlight(0.4)
	zoomOutTween.Completed:Connect(function()
		-- Play rainbow highlight AFTER zoom out completes
		--self:PlayRainbowHighlight(0.4)
		
		-- Hold zoomed out for a moment, then zoom back
		--task.wait(0.5)
		zoomInTween:Play()
	end)
end

-- ========================================
-- HIGHLIGHT FLASH EFFECT
-- ========================================

--[[
	Flash a highlight on a model (e.g., for hit effects)
	@param model - The model to apply highlight to
	@param duration - How long the flash lasts (default: 0.25s)
	@param fillColor - Fill color (default: red)
	@param outlineColor - Outline color (default: white)
]]
function Effects:FlashHighlight(model: Model, duration: number?, fillColor: Color3?, outlineColor: Color3?)
	if not model then return end
	
	duration = duration or 0.25
	fillColor = fillColor or Color3.fromRGB(255, 0, 0)
	outlineColor = outlineColor or Color3.fromRGB(255, 255, 255)
	
	-- Get or create highlight
	local highlight = model:FindFirstChildOfClass("Highlight")
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.FillTransparency = 1
		highlight.OutlineTransparency = 1
		highlight.Adornee = model
		highlight.Parent = model
	end
	
	highlight.FillColor = fillColor
	highlight.OutlineColor = outlineColor
	
	-- Animate flash (fade in, then fade out)
	local pulseDuration = duration / 2
	
	-- Fade in
	local fadeIn = TweenService:Create(
		highlight,
		TweenInfo.new(pulseDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{FillTransparency = 0.3, OutlineTransparency = 0}
	)
	fadeIn:Play()
	fadeIn.Completed:Wait()
	
	-- Fade out
	local fadeOut = TweenService:Create(
		highlight,
		TweenInfo.new(pulseDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{FillTransparency = 1, OutlineTransparency = 1}
	)
	fadeOut:Play()
end

-- ========================================
-- WHITE FLASH EFFECT (Event Intro)
-- ========================================

--[[
	Play dramatic white flash effect for event intros.
	Flash configuration: 0.2s instant white, 1.0s fade out (dramatic)
	Used to hide EventPreset loading during event countdown.
	@param duration - Fade out duration in seconds (default: 1.0)
]]
function Effects:PlayFlash(duration)
	local fadeInDuration = 0.1
	local fadeOutDuration = duration or 0.7
	
	-- Get WhiteFrame from BlackFrameUI
	local PlayerGui = Player:WaitForChild("PlayerGui")
	local BlackFrameUI = PlayerGui:FindFirstChild("BlackFrameUI")
	if not BlackFrameUI then 
		warn("⚠️ BlackFrameUI not found - flash effect skipped")
		return 
	end
	
	local WhiteFrame = BlackFrameUI:FindFirstChild("WhiteFrame")
	if not WhiteFrame then 
		warn("⚠️ WhiteFrame not found in BlackFrameUI - flash effect skipped")
		return 
	end
	
	-- Show and start fully transparent
	WhiteFrame.Visible = true
	WhiteFrame.BackgroundTransparency = 1
	
	-- Fade to white (instant dramatic flash)
	local fadeInTween = TweenService:Create(
		WhiteFrame,
		TweenInfo.new(fadeInDuration, Enum.EasingStyle.Linear),
		{BackgroundTransparency = 0}
	)
	
	fadeInTween:Play()
	fadeInTween.Completed:Wait()
	
	-- Hold at full white for 0.1 seconds
	task.wait(0.1)
	
	-- Fade out smoothly
	local fadeOutTween = TweenService:Create(
		WhiteFrame,
		TweenInfo.new(fadeOutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 1}
	)
	
	fadeOutTween:Play()
	fadeOutTween.Completed:Wait()
	WhiteFrame.Visible = false
end

-- ========================================
-- FOV EFFECT (Camera Zoom)
-- ========================================

--[[
	Play FOV transition effect (camera zoom).
	Locks FOV system to prevent running speed from interfering.
	@param startFOV - Starting field of view
	@param endFOV - Ending field of view
	@param duration - Duration of transition in seconds
	@param easing - Easing style (default: Quad)
]]
function Effects:PlayFOV(startFOV, endFOV, duration, easing)
	local camera = workspace.CurrentCamera
	if not camera then 
		warn("⚠️ Camera not found - FOV effect skipped")
		return 
	end
	
	-- Lock FOV system to prevent running speed from interfering
	Client_FOV:LockFOV(duration or 1.0)
	
	-- Set starting FOV
	camera.FieldOfView = startFOV or camera.FieldOfView
	
	-- Create FOV tween
	local fovTween = TweenService:Create(
		camera,
		TweenInfo.new(
			duration or 1.0,
			easing or Enum.EasingStyle.Quad,
			Enum.EasingDirection.InOut
		),
		{FieldOfView = endFOV or 70}
	)
	
	fovTween:Play()
	fovTween.Completed:Wait()
end

--[[
	Fill-only highlight flash on a model (no outline, occluded depth mode).
	Uses Shared_Effects.HighlightFill[presetName] for color and duration.
	@param model Model - The model to highlight (e.g. brainrot)
	@param presetName string? - "Upgrade" (green) or "Collect" (white). Default "Collect"
]]
function Effects:FlashHighlightFill(model: Model, presetName: string?)
	if not model or not model:IsA("Model") then return end

	local config = Shared_Effects.HighlightFill or {}
	local preset = (presetName and config[presetName]) or config.Collect or {
		Color = Color3.new(1, 1, 1),
		Duration = 0.65,
		FillTransparencyStart = 0.3,
	}

	local duration = preset.Duration or 0.65
	local fillStart = preset.FillTransparencyStart or 0.3

	local highlight = Instance.new("Highlight")
	highlight.Name = "HighlightFillFlash"
	highlight.FillColor = preset.Color or Color3.new(1, 1, 1)
	highlight.FillTransparency = fillStart
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model

	local tween = TweenService:Create(
		highlight,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{FillTransparency = 1}
	)
	tween:Play()
	tween.Completed:Connect(function()
		highlight:Destroy()
	end)
end

-- ========================================
-- DEBRIS/EXPLOSION EFFECTS
-- ========================================

--[[
	Create an explosion effect by breaking a part into pieces
	@param originalPart - The part to break
	@param maxPieces - Maximum number of pieces to create
	@param force - Explosion force magnitude
	@param debrisLifetime - How long before debris is cleaned up
	@return Debris folder
]]
function Effects:CreateExplosion(originalPart: BasePart, maxPieces: number, force: number, debrisLifetime: number)
	if not originalPart then return nil end
	
	local debrisFolder = workspace:FindFirstChild("ExplosionDebris")
	if not debrisFolder then
		debrisFolder = Instance.new("Folder")
		debrisFolder.Name = "ExplosionDebris"
		debrisFolder.Parent = workspace
	end
	
	local size = originalPart.Size
	local cframe = originalPart.CFrame
	local color = originalPart.Color
	local material = originalPart.Material
	
	-- Calculate optimal grid dimensions based on wall proportions
	-- For walls, typically one dimension is much smaller (thickness)
	-- We want to split the larger dimensions more
	local dimensions = {size.X, size.Y, size.Z}
	table.sort(dimensions, function(a, b) return a > b end) -- Sort descending
	
	-- Determine which axis is which
	local isXThick = size.X == dimensions[3] -- X is smallest (thickness)
	local isYThick = size.Y == dimensions[3] -- Y is smallest
	local isZThick = size.Z == dimensions[3] -- Z is smallest
	
	-- Calculate grid: split larger dimensions more, keep thickness at 1-2 pieces
	local numX, numY, numZ
	
	if isXThick then
		-- Wall is thin in X (like a vertical wall)
		numX = 1
		numY = math.ceil(math.sqrt(maxPieces * (size.Y / size.Z)))
		numZ = math.ceil(maxPieces / numY)
		-- Ensure we don't exceed maxPieces
		while numY * numZ > maxPieces do
			if numY > numZ then numY = numY - 1 else numZ = numZ - 1 end
		end
	elseif isYThick then
		-- Wall is thin in Y (like a floor/ceiling)
		numY = 1
		numX = math.ceil(math.sqrt(maxPieces * (size.X / size.Z)))
		numZ = math.ceil(maxPieces / numX)
		while numX * numZ > maxPieces do
			if numX > numZ then numX = numX - 1 else numZ = numZ - 1 end
		end
	else
		-- Wall is thin in Z (like a vertical wall facing different direction)
		numZ = 1
		numX = math.ceil(math.sqrt(maxPieces * (size.X / size.Y)))
		numY = math.ceil(maxPieces / numX)
		while numX * numY > maxPieces do
			if numX > numY then numX = numX - 1 else numY = numY - 1 end
		end
	end
	
	-- Ensure minimum of 1 piece per dimension
	numX = math.max(1, numX)
	numY = math.max(1, numY)
	numZ = math.max(1, numZ)
	
	-- Calculate exact piece size (must perfectly divide)
	local pieceSize = Vector3.new(size.X / numX, size.Y / numY, size.Z / numZ)
	
	-- Create pieces in a grid that perfectly fits the original part
	for x = 0, numX - 1 do
		for y = 0, numY - 1 do
			for z = 0, numZ - 1 do
				local piece = Instance.new("Part")
				piece.Size = pieceSize
				piece.Color = color
				piece.Material = material
				piece.Anchored = false
				piece.CanCollide = false
				
				-- Calculate position: start from bottom-left-back corner, then offset by piece position
				-- The center of the first piece should be at: -size/2 + pieceSize/2
				-- Then each subsequent piece is offset by pieceSize
				local localOffset = Vector3.new(
					-size.X / 2 + pieceSize.X / 2 + x * pieceSize.X,
					-size.Y / 2 + pieceSize.Y / 2 + y * pieceSize.Y,
					-size.Z / 2 + pieceSize.Z / 2 + z * pieceSize.Z
				)
				
				-- Transform to world space using the part's CFrame
				piece.CFrame = cframe * CFrame.new(localOffset)
				piece.Parent = debrisFolder
				
				-- Apply explosion force (radial from center)
				local direction = (piece.Position - cframe.Position).Unit
				local randomness = Vector3.new(
					math.random(-100, 100) / 100,
					math.random(0, 150) / 100, -- More upward bias
					math.random(-100, 100) / 100
				)
				local finalDirection = (direction + randomness * 0.4).Unit
				piece.AssemblyLinearVelocity = finalDirection * force
				
				-- Random rotation
				piece.AssemblyAngularVelocity = Vector3.new(
					math.random(-5, 5),
					math.random(-5, 5),
					math.random(-5, 5)
				)
				
				-- Fade out and cleanup
				task.spawn(function()
					task.wait(debrisLifetime * 0.7)
					local fadeTween = TweenService:Create(
						piece,
						TweenInfo.new(debrisLifetime * 0.3, Enum.EasingStyle.Linear),
						{Transparency = 1}
					)
					fadeTween:Play()
					fadeTween.Completed:Wait()
					piece:Destroy()
				end)
			end
		end
	end
	
	return debrisFolder
end

--[[
	Create debris particles that fly in a direction
	@param position - Where to spawn debris
	@param count - Number of debris parts
	@param partSize - Size of each debris part
	@param color - Color of debris
	@param direction - General direction to fly
	@param force - How fast debris flies
	@param lifetime - How long before cleanup
	@return Array of debris parts
]]
function Effects:CreateDebris(position: Vector3, count: number, partSize: Vector3, color: Color3, direction: Vector3, force: number, lifetime: number)
	local debrisFolder = workspace:FindFirstChild("DebrisEffects")
	if not debrisFolder then
		debrisFolder = Instance.new("Folder")
		debrisFolder.Name = "DebrisEffects"
		debrisFolder.Parent = workspace
	end
	
	local debris = {}
	
	for i = 1, count do
		local part = Instance.new("Part")
		part.Size = partSize
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = false
		part.CanCollide = true
		part.Transparency = 0
		
		-- Random offset from spawn position
		local randomOffset = Vector3.new(
			math.random(-50, 50) / 100,
			math.random(-50, 50) / 100,
			math.random(-50, 50) / 100
		) * partSize.Magnitude
		
		part.Position = position + randomOffset
		part.Parent = debrisFolder
		
		-- Apply velocity
		local randomDirection = Vector3.new(
			direction.X + math.random(-30, 30) / 100,
			direction.Y + math.random(-20, 20) / 100,
			direction.Z + math.random(-30, 30) / 100
		).Unit
		
		part.AssemblyLinearVelocity = randomDirection * force
		
		-- Random rotation
		part.AssemblyAngularVelocity = Vector3.new(
			math.random(-10, 10),
			math.random(-10, 10),
			math.random(-10, 10)
		)
		
		-- Fade out and cleanup
		task.spawn(function()
			task.wait(lifetime * 0.7)
			local fadeTween = TweenService:Create(
				part,
				TweenInfo.new(lifetime * 0.3, Enum.EasingStyle.Linear),
				{Transparency = 1}
			)
			fadeTween:Play()
			fadeTween.Completed:Wait()
			part:Destroy()
		end)
		
		table.insert(debris, part)
	end
	
	return debris
end

-- ========================================
-- TROPHY FLYING EFFECT
-- ========================================

-- Bezier curve utility (quadratic)
local function lerpVector3(a: Vector3, b: Vector3, t: number): Vector3
	return a + (b - a) * t
end

local function quadraticBezier(t: number, p0: Vector3, p1: Vector3, p2: Vector3): Vector3
	local l1 = lerpVector3(p0, p1, t)
	local l2 = lerpVector3(p1, p2, t)
	return lerpVector3(l1, l2, t)
end

--[[
	Spawn trophy that flies to player (when breaking through wall with wins)
	@param spawnPosition - Where the trophy spawns (wall position)
	@param player - Player who broke the wall
	@param winsAmount - Amount of wins earned
]]
function Effects:SpawnFlyingTrophy(spawnPosition: Vector3, player: Player, winsAmount: number)
	-- Get trophy template
	local trophyTemplate = ReplicatedStorage:FindFirstChild("Storage")
	if trophyTemplate then
		trophyTemplate = trophyTemplate:FindFirstChild("Assets")
		if trophyTemplate then
			trophyTemplate = trophyTemplate:FindFirstChild("Trophy")
		end
	end
	
	if not trophyTemplate then
		warn("⚠️ Trophy template not found at ReplicatedStorage.Storage.Assets.Trophy")
		return
	end
	
	local trophyCount = math.clamp(winsAmount, 1, 5)
	
	-- Get player's position and scale (use Main part for ragdoll)
	local character = player.Character
	local customCharacter = character and character:FindFirstChild("CustomCharacter")
	local main = customCharacter and customCharacter:FindFirstChild("Main")
	
	if not main or not main:IsA("BasePart") then
		warn("⚠️ Player Main part not found for trophy spawn")
		return
	end
	
	-- Get player scale (default to 1 if not found)
	local playerScale = main:GetAttribute("CurrentScale") or 1
	
	-- Scale spawn height: 10 studs at 1x scale, 30 studs at 5x scale
	local spawnHeight = 25 + (playerScale - 1) * 15 -- Linear interpolation: 10 at 1x, 30 at 5x
	local baseSpawnHeight = main.Position.Y + spawnHeight -- Global Y position
	
	-- Spawn multiple trophies with scaled delays (more trophies = bigger delays for dramatic effect)
	local baseDelay = 0.2 -- Base delay
	local delayMultiplier = 1 + (trophyCount - 1) * 0.1 -- Scales with trophy count (1x at 1 trophy, 1.4x at 5 trophies)
	local spawnDelay = baseDelay * delayMultiplier
	
	for i = 1, trophyCount do
		task.delay((i - 1) * spawnDelay, function() -- Stagger spawn with scaled delay
			local trophy = trophyTemplate:Clone()
			
			-- Check if trophy is a MeshPart or contains a mesh
			local isMeshPart = trophy:IsA("MeshPart")
			local meshPart = isMeshPart and trophy or trophy:FindFirstChildWhichIsA("MeshPart")
			
			if not meshPart then
				warn("⚠️ Trophy template is not a MeshPart and doesn't contain one")
				return
			end
			
			-- Setup trophy with spawn position in a circle above player (global space)
			local angle = (i - 1) / trophyCount * math.pi * 2 -- Evenly distribute in circle
			local radius = 25 * playerScale -- Scale radius with player size (8 at 1x, 40 at 5x)
			local spawnOffset = Vector3.new(
				math.cos(angle) * radius,
				math.random() * 3, -- Random Y variation: 0-3 studs
				math.sin(angle) * radius
			)
			local randomizedSpawnPos = Vector3.new(
				main.Position.X,
				baseSpawnHeight,
				main.Position.Z
			) + spawnOffset
			
		meshPart.Position = randomizedSpawnPos
		meshPart.Anchored = true
		meshPart.CanCollide = false
		
		-- Scale trophy size based on player scale
		local originalSize = meshPart.Size
		local trophyBaseSize = originalSize * playerScale
		meshPart.Size = trophyBaseSize
		
		trophy.Parent = workspace
		
		-- Animation parameters
		local startTime = tick()
		local currentYRotation = math.random() * 360 -- Random starting Y rotation
		local rotationSpeed = math.random(180, 360) -- Degrees per second (Y axis only)
		
		-- Orbital parameters
		local orbitSpeed = 1.5 -- Circles per second (reduced from 2 for less spinning)
		local spiralInSpeed = 1.2 -- How fast to close in on player (increased for faster approach)
		local currentRadius = radius
		local currentAngle = angle
		
		local RunService = game:GetService("RunService")
		
		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			if not trophy or not trophy.Parent or not meshPart or not meshPart.Parent then
				if connection then connection:Disconnect() end
				return
			end
			
			local elapsed = tick() - startTime
			
			-- Get current player position (dynamic tracking using Main part)
			local character = player.Character
			local customCharacter = character and character:FindFirstChild("CustomCharacter")
			local main = customCharacter and customCharacter:FindFirstChild("Main")
			if not main or not main:IsA("BasePart") then
				trophy:Destroy()
				connection:Disconnect()
				return
			end
			
			-- Update orbit angle
			currentAngle = currentAngle + (orbitSpeed * dt * math.pi * 2)
			
			-- Spiral in toward player
			currentRadius = currentRadius - (spiralInSpeed * dt * radius)
			
			-- Calculate position: orbit around player while spiraling in
			local targetHeight = main.Position.Y + 2 -- Chest height
			local currentHeight = main.Position.Y + math.max(currentRadius * 0.5, 2) -- Height decreases as we spiral in
			
			local orbitOffset = Vector3.new(
				math.cos(currentAngle) * currentRadius,
				0,
				math.sin(currentAngle) * currentRadius
			)
			
			local currentPos = main.Position + orbitOffset + Vector3.new(0, currentHeight - main.Position.Y, 0)
			
			-- Scale down as it approaches player (based on radius, starting from scaled base size)
			local shrinkProgress = math.max(0.3, currentRadius / radius)
			meshPart.Size = trophyBaseSize * shrinkProgress
				
				-- Rotate on Y axis only (like coins)
				currentYRotation = currentYRotation + rotationSpeed * dt
				meshPart.Position = currentPos
				meshPart.Orientation = Vector3.new(0, currentYRotation, 0)
				
				-- End animation when very close to player
				if currentRadius <= 0.5 then
					connection:Disconnect()
					
				-- Play collection sound
				local sound = Instance.new("Sound")
				sound.SoundId = "rbxassetid://12345678" -- TODO: Replace with actual sound ID
				sound.Volume = 0.75
				Client_Sounds:SetGroup(sound, "SFX")
				sound.Parent = main
				sound:Play()
				Debris:AddItem(sound, 2)
					
					-- Show wins popup only once (for the first trophy)
					if i == 1 then
						local Players = game:GetService("Players")
						if player == Players.LocalPlayer then
							local Client_Popups = require(script.Parent.Parent.UI.Client_Popups)
							if Client_Popups and Client_Popups.ShowWinsPopup then
								Client_Popups:ShowWinsPopup(winsAmount)
							end
						end
					end
					
					trophy:Destroy()
				end
			end)
		end)
	end
end

-- ========================================
-- COIN FOUNTAIN EFFECT
-- ========================================

--[[
	Spawn coin fountain on death (replaces splatter debris)
	@param deathPosition - Where the player died
	@param playerScale - Player's scale (affects coin count and spread)
	@param coinsEarned - Total coins earned (for popup display, optional)
]]
function Effects:SpawnDeathCoins(deathPosition: Vector3, playerScale: number, coinsEarned: number?)
	-- Get coin template
	local coinTemplate = ReplicatedStorage:FindFirstChild("Storage")
	if coinTemplate then
		coinTemplate = coinTemplate:FindFirstChild("Assets")
		if coinTemplate then
			coinTemplate = coinTemplate:FindFirstChild("Coin")
		end
	end
	
	if not coinTemplate then
		warn("⚠️ Coin template not found at ReplicatedStorage.Storage.Assets.Coin")
		return
	end
	
	-- Coin spawn configuration - FAR spread, scales with player size
	-- Scale 1: 5 coins, Scale 4: 25 coins, Scale 5: 25 coins (capped)
	local coinCount = math.clamp(math.floor(5 * playerScale), 5, 25)
	local minSpread = 5 + playerScale * 2 -- Minimum distance from center
	local maxSpread = 12 + playerScale * 4 -- Maximum distance (scales heavily with player size)
	
	local RunService = game:GetService("RunService")
	
	-- Spawn coins
	for i = 1, coinCount do
		local coin = coinTemplate:Clone()
		
		-- Check if coin is a MeshPart or contains a mesh
		local isMeshPart = coin:IsA("MeshPart")
		local meshPart = isMeshPart and coin or coin:FindFirstChildWhichIsA("MeshPart")
		
		if not meshPart then
			warn("⚠️ Coin template is not a MeshPart and doesn't contain one")
			continue
		end
		
		-- Random direction for spread - FAR from player
		local angle = math.random() * math.pi * 2
		local distance = minSpread + math.random() * (maxSpread - minSpread)
		
		-- Calculate horizontal landing position
		local horizontalLanding = Vector3.new(
			deathPosition.X + math.cos(angle) * distance,
			deathPosition.Y, -- Start at death height
			deathPosition.Z + math.sin(angle) * distance
		)
		
		-- Raycast downward from landing position to find ground
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {workspace.CurrentCamera, coin}
		
		local rayResult = workspace:Raycast(horizontalLanding, Vector3.new(0, -200, 0), raycastParams)
		local groundLevel = rayResult and rayResult.Position.Y or (deathPosition.Y - 10)
		
		-- Landing position: on surface + 1 stud up
		local landingPos = Vector3.new(
			horizontalLanding.X,
			groundLevel + 1,
			horizontalLanding.Z
		)
		
		-- Position coin at death position
		meshPart.Position = deathPosition
		meshPart.Anchored = true
		meshPart.CanCollide = false
		
		-- Set upright orientation (X=-90 degrees)
		meshPart.Orientation = Vector3.new(-90, 0, 0)
		
		coin.Parent = workspace
		
		-- Animate coin: falling -> rotating -> flying to camera
		local startTime = tick()
		local fallDuration = 0.7
		local rotateDuration = 0.3 -- Time on ground before flying
		local staggerDelay = (i - 1) * 0.08 -- Stagger each coin by 80ms (1 by 1 collection)
		local flyDuration = 0.6 -- Time to fly to camera
		local bounceHeight = 4 + math.random() * 3 -- Higher pop (4-7 studs)
		local fallRotationSpeed = math.random(360, 720) -- Degrees per second during fall
		local groundRotationSpeed = math.random(180, 360) -- Degrees per second on ground
		local currentYRotation = 0 -- Y rotation in degrees (0-360+)
		local finalYRotation = 0 -- Lock rotation when flying starts
		local state = "falling" -- States: falling, rotating, waiting, flying, collected
		
		-- Random offset for camera target (spread across viewport)
		local randomOffsetX = math.random(-8, 8) -- Left/Right spread
		local randomOffsetY = math.random(-5, 5) -- Up/Down spread
		
		-- Bezier curve control point (for curved flight path)
		-- Random perpendicular offset from the direct path
		local curveOffsetX = math.random(-10, 10)
		local curveOffsetY = math.random(-8, 8)
		
		-- Calculate coin value (rounded, split evenly) - default to 1 if not provided
		local coinValue = 1
		if coinsEarned and coinsEarned > 0 then
			coinValue = math.floor((coinsEarned / coinCount) + 0.5)
		end
		
		task.spawn(function()
			local connection
			connection = RunService.Heartbeat:Connect(function(dt)
				if not coin or not coin.Parent or not meshPart or not meshPart.Parent then
					if connection then connection:Disconnect() end
					return
				end
				
				local elapsed = tick() - startTime
				
				if state == "falling" then
					local t = math.clamp(elapsed / fallDuration, 0, 1)
					
					if t >= 1 then
						-- Landed - switch to rotating state
						state = "rotating"
						startTime = tick() -- Reset timer for rotate phase
						meshPart.Position = landingPos
						meshPart.Orientation = Vector3.new(-90, currentYRotation, 0)
						return
					end
					
					-- Horizontal lerp from death position to landing position
					local currentHorizontal = deathPosition:Lerp(landingPos, t)
					
					-- Vertical: pop up then fall with gravity
					local upTime = 0.3 -- First 30% is pop-up
					local gravity = 25
					local verticalOffset
					
					if t <= upTime then
						-- Pop-up phase
						verticalOffset = bounceHeight * (t / upTime)
					else
						-- Falling phase with gravity
						local fallTime = t - upTime
						local fallDuration = 1 - upTime
						local fallProgress = fallTime / fallDuration
						verticalOffset = bounceHeight - (gravity * fallProgress^2)
					end
					
					local currentPos = Vector3.new(
						currentHorizontal.X,
						math.max(deathPosition.Y + verticalOffset, landingPos.Y),
						currentHorizontal.Z
					)
					
					-- Update Y rotation (in degrees, 0-360+)
					currentYRotation = currentYRotation + fallRotationSpeed * dt
					
					-- Apply position and orientation
					meshPart.Position = currentPos
					meshPart.Orientation = Vector3.new(-90, currentYRotation, 0)
					
				elseif state == "rotating" then
					-- Rotate on ground (slower, continuous) - Y axis increments
					currentYRotation = currentYRotation + groundRotationSpeed * dt
					meshPart.Orientation = Vector3.new(-90, currentYRotation, 0)
					
					-- After rotate duration, wait for stagger delay
					if elapsed >= rotateDuration then
						state = "waiting"
						startTime = tick() -- Reset timer for wait phase
					end
					
				elseif state == "waiting" then
					-- Keep rotating while waiting for stagger delay
					currentYRotation = currentYRotation + groundRotationSpeed * dt
					meshPart.Orientation = Vector3.new(-90, currentYRotation, 0)
					
					-- After stagger delay, fly to camera
					if elapsed >= staggerDelay then
						state = "flying"
						finalYRotation = currentYRotation -- Lock rotation for flying
						startTime = tick() -- Reset timer for fly phase
					end
					
				elseif state == "flying" then
					local t = math.clamp(elapsed / flyDuration, 0, 1)
					
					-- Get camera position
					local camera = workspace.CurrentCamera
					if not camera then
						coin:Destroy()
						if connection then connection:Disconnect() end
						return
					end
					
					-- Calculate bezier curve positions
					-- P0 = start (landing position)
					-- P1 = control point (curved path)
					-- P2 = end (camera target)
					local cameraCFrame = camera.CFrame
					local targetPos = cameraCFrame.Position 
						+ cameraCFrame.LookVector * 5 
						+ cameraCFrame.RightVector * randomOffsetX 
						+ cameraCFrame.UpVector * randomOffsetY
					
					-- Control point: midpoint between start and target, with perpendicular offset
					local midpoint = landingPos:Lerp(targetPos, 0.5)
					local controlPoint = midpoint 
						+ cameraCFrame.RightVector * curveOffsetX 
						+ cameraCFrame.UpVector * curveOffsetY
					
					-- Quadratic Bezier curve formula: B(t) = (1-t)^2 * P0 + 2(1-t)t * P1 + t^2 * P2
					local oneMinusT = 1 - t
					local currentPos = (oneMinusT * oneMinusT * landingPos) 
						+ (2 * oneMinusT * t * controlPoint) 
						+ (t * t * targetPos)
					
					meshPart.Position = currentPos
					
					-- Keep rotation locked (no spinning during flight)
					meshPart.Orientation = Vector3.new(-90, finalYRotation, 0)
					
					-- Fade out as it approaches camera (0 -> 1 transparency)
					-- Start fading after 50% of flight
					local fadeStart = 0.5
					if t > fadeStart then
						local fadeProgress = (t - fadeStart) / (1 - fadeStart)
						meshPart.Transparency = fadeProgress
					end
					
					-- Collection check: when close enough or animation done
					local distanceToCamera = (meshPart.Position - camera.CFrame.Position).Magnitude
					if t >= 1 or distanceToCamera < 3 then
						state = "collected"
						
						-- Show coin popup for this coin's value
						local Popups = require(script.Parent.Parent.UI.Client_Popups)
						if Popups and Popups.ShowCoinPopup then
							Popups:ShowCoinPopup(coinValue) -- Green popup with +X
						end
						
						-- Destroy immediately (already faded)
						coin:Destroy()
						if connection then connection:Disconnect() end
					end
				end
			end)
		end)
	end
end

-- ========================================
-- SPEEDLINES EFFECT
-- ========================================

local speedlinesData = {
	attachment = nil,
	emitter = nil,
	connection = nil,
	enabled = false
}

--[[
	Enable speedlines effect (particles that scale with velocity during ragdoll)
	Attaches to camera and updates based on player speed
]]
function Effects:EnableSpeedlines()
	if speedlinesData.enabled then return end
	
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	
	-- Get speedlines template from ReplicatedStorage
	local storage = ReplicatedStorage:FindFirstChild("Storage")
	if not storage then
		warn("⚠️ ReplicatedStorage.Storage not found")
		return
	end
	
	local assets = storage:FindFirstChild("Assets")
	if not assets then
		warn("⚠️ ReplicatedStorage.Storage.Assets not found")
		return
	end
	
	local speedlinesPart = assets:FindFirstChild("Speedlines")
	if not speedlinesPart then
		warn("⚠️ Speedlines part not found in ReplicatedStorage.Storage.Assets")
		return
	end
	
	-- Find the Attachment and ParticleEmitter in the part
	local sourceAttachment = speedlinesPart:FindFirstChildOfClass("Attachment")
	if not sourceAttachment then
		warn("⚠️ No Attachment found in Speedlines part")
		return
	end
	
	local sourceEmitter = sourceAttachment:FindFirstChildOfClass("ParticleEmitter")
	if not sourceEmitter then
		warn("⚠️ No ParticleEmitter found in Speedlines Attachment")
		return
	end
	
	-- Clone and setup for camera
	local attachment = sourceAttachment:Clone()
	local emitter = attachment:FindFirstChildOfClass("ParticleEmitter")
	
	-- Position attachment ahead of camera
	attachment.Parent = camera
	
	-- Store references
	speedlinesData.attachment = attachment
	speedlinesData.emitter = emitter
	speedlinesData.enabled = true
	
	-- Configuration
	local minSpeed = 50 -- Below this speed, no particles
	local maxSpeed = 120 -- At this speed, full particle effect
	local maxRate = 125 -- Maximum particles per second (keep it low for performance!)
	local cameraOffset = 8 -- Distance ahead of camera
	
	-- Update loop: adjust particle rate based on player velocity
	speedlinesData.connection = RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		if not character then
			emitter.Rate = 0
			return
		end
		
		-- Get player's Main part (rolling body)
		local customCharacter = character:FindFirstChild("CustomCharacter")
		local main = customCharacter and customCharacter:FindFirstChild("Main")
		
		if not main or not main:IsA("BasePart") then
			emitter.Rate = 0
			return
		end
		
		-- Calculate speed
		local velocity = main.AssemblyLinearVelocity
		local speed = velocity.Magnitude
		
		-- Map speed to particle rate (0 at minSpeed, maxRate at maxSpeed)
		local speedFactor = math.clamp((speed - minSpeed) / (maxSpeed - minSpeed), 0, 1)
		emitter.Rate = speedFactor * maxRate
		
		-- Position attachment ahead of camera
		local cameraCFrame = camera.CFrame
		local aspectRatio = camera.ViewportSize.X / camera.ViewportSize.Y
		local offsetDistance = aspectRatio > 1.5 and cameraOffset or (cameraOffset + 3)
		
		attachment.WorldCFrame = cameraCFrame + (cameraCFrame.LookVector * offsetDistance)
	end)
end

--[[
	Disable speedlines effect and cleanup
]]
function Effects:DisableSpeedlines()
	if not speedlinesData.enabled then return end
	
	-- Disconnect update loop
	if speedlinesData.connection then
		speedlinesData.connection:Disconnect()
		speedlinesData.connection = nil
	end
	
	-- Destroy attachment (and emitter with it)
	if speedlinesData.attachment then
		speedlinesData.attachment:Destroy()
		speedlinesData.attachment = nil
	end
	
	speedlinesData.emitter = nil
	speedlinesData.enabled = false
end

-- ========================================
-- GUARD PROJECTILE & IMPACT EFFECTS
-- ========================================

--[[
	Create and animate projectile from guard to player
	@param startPos Vector3 - Guard position
	@param endPos Vector3 - Player position
]]
function Effects:CreateGuardProjectile(startPos: Vector3, endPos: Vector3)
	-- Create projectile block (longer than wide, like a bullet)
	local projectile = Instance.new("Part")
	projectile.Name = "GuardProjectile"
	-- Block: narrow in X/Y, longer in Z (length along travel direction)
	projectile.Size = Vector3.new(0.2, 0.2, 5)
	projectile.Color = Color3.fromRGB(255, 119, 0) -- Yellowish
	projectile.Material = Enum.Material.Neon
	projectile.Transparency = 0
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanQuery = false
	projectile.CanTouch = false
	projectile.CastShadow = false
	
	-- Orient so long axis points toward target
	projectile.CFrame = CFrame.lookAt(startPos, endPos)
	projectile.Parent = workspace
	
	-- Calculate travel time based on distance and speed
	local distance = (endPos - startPos).Magnitude
	local projectileSpeed = 1200 -- Studs per second (average speed)
	local travelTime = distance / projectileSpeed
	
	local direction = (endPos - startPos).Unit
	local endCFrame = CFrame.lookAt(endPos, endPos + direction)
	
	-- Tween with acceleration (starts slow, speeds up) using Sine.In
	local tweenInfo = TweenInfo.new(
		travelTime,
		Enum.EasingStyle.Sine, -- Smooth acceleration
		Enum.EasingDirection.In -- Accelerate (start slow, end fast)
	)
	
	local tween = TweenService:Create(projectile, tweenInfo, {
		CFrame = endCFrame
	})
	
	tween:Play()
	
	-- Cleanup after tween completes
	tween.Completed:Connect(function()
		projectile:Destroy()
	end)
	
	-- Safety cleanup if tween fails
	Debris:AddItem(projectile, travelTime + 0.5)
end

function Effects:PlayBalloonPop(worldPos: Vector3)
	local host = Instance.new("Part")
	host.Name = "BalloonPopHost"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.CFrame = CFrame.new(worldPos)
	host.Parent = workspace

	local pop = Instance.new("Part")
	pop.Name = "BalloonPopBurst"
	pop.Shape = Enum.PartType.Ball
	pop.Material = Enum.Material.Neon
	pop.Color = Color3.fromRGB(255, 70, 90)
	pop.Anchored = true
	pop.CanCollide = false
	pop.CanQuery = false
	pop.CanTouch = false
	pop.Size = Vector3.new(0.8, 0.8, 0.8)
	pop.CFrame = CFrame.new(worldPos)
	pop.Parent = workspace

	local ring = pop:Clone()
	ring.Color = Color3.fromRGB(255, 255, 255)
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.5, 0.5, 0.5)
	ring.Parent = workspace

	TweenService:Create(
		pop,
		TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(4.5, 4.5, 4.5), Transparency = 1 }
	):Play()
	TweenService:Create(
		ring,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(6, 6, 6), Transparency = 1 }
	):Play()

	Debris:AddItem(pop, 0.45)
	Debris:AddItem(ring, 0.45)
	Debris:AddItem(host, 0.45)
end

--[[
	Play gunshot sound at guard position
	@param guardPos Vector3 - Guard's position
]]
--[[
	Emit all ParticleEmitters in a container, respecting EmitCount, EmitDelay, and EmitBursts attributes.
	Use this for all VFX emit logic so behavior is consistent.
	@param container Instance - Model, Part, or folder (GetDescendants used to find ParticleEmitters)
	@param defaultEmitCount number? - Default per emitter if EmitCount attribute not set (default 10)
]]
function Effects:EmitParticlesInContainer(container: Instance, defaultEmitCount: number?)
	if not container then return end
	local defaultCount = defaultEmitCount or 10
	for _, desc in ipairs(container:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			local emitCount = desc:GetAttribute("EmitCount") or defaultCount
			local emitDelay = desc:GetAttribute("EmitDelay") or 0
			local emitBursts = desc:GetAttribute("EmitBursts") or 1
			task.spawn(function()
				for burst = 1, emitBursts do
					if burst > 1 and emitDelay > 0 then
						task.wait(emitDelay)
					end
					if desc.Parent then
						desc:Emit(emitCount)
					end
				end
			end)
		end
	end
end

--[[
	Emit particles from guard's GunAttachment (uses EmitParticlesInContainer)
	@param guard Model - The guard model with GunAttachment
]]
function Effects:EmitGuardParticles(guard: Model)
	if not guard then return end
	local gunAttachment = guard:FindFirstChild("GunAttachment", true)
	if not gunAttachment then
		warn("⚠️ No GunAttachment found in guard:", guard.Name)
		return
	end
	self:EmitParticlesInContainer(gunAttachment, 10)
end

--[[
	Play gunshot sound at guard position
	@param guardPos Vector3 - Position to play sound from
]]
function Effects:PlayGuardGunshot(guardPos: Vector3)
	if not guardPos then return end
	
	-- Create invisible part for sound
	local soundPart = Instance.new("Part")
	soundPart.Transparency = 1
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.Position = guardPos
	soundPart.Parent = workspace
	
	local gunshotSound = Instance.new("Sound")
	gunshotSound.SoundId = "rbxassetid://138451493714439"
	gunshotSound.Volume = 1
	gunshotSound.RollOffMinDistance = 25
	gunshotSound.RollOffMaxDistance = 500
	gunshotSound.TimePosition = 0.3
	Client_Sounds:SetGroup(gunshotSound, "SFX")
	gunshotSound.Parent = soundPart
	gunshotSound:Play()
	
	Debris:AddItem(soundPart, 3)
end

--[[
	Play impact sound when projectile hits player
	@param targetRootPart BasePart - Player's HumanoidRootPart
]]
function Effects:PlayGuardImpact(targetRootPart: BasePart)
	if not targetRootPart then return end
	
	local character = targetRootPart.Parent
	if not character then return end
	
	-- Check if this is the local player to apply camera shake
	local targetPlayer = Players:GetPlayerFromCharacter(character)
	local isLocalPlayer = targetPlayer == Player
	
	-- Impact sound
	local impactSound = Instance.new("Sound")
	impactSound.SoundId = "rbxassetid://131472999032031"
	impactSound.Volume = 1
	impactSound.RollOffMinDistance = 25
	impactSound.RollOffMaxDistance = 500
	Client_Sounds:SetGroup(impactSound, "SFX")
	impactSound.Parent = targetRootPart
	impactSound:Play()
	
	impactSound.Ended:Connect(function()
		impactSound:Destroy()
	end)
	
	Debris:AddItem(impactSound, 3)
	
	-- Red highlight flash (smooth fade)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 0, 0)
	highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 0
	highlight.Parent = character
	
	-- Tween fade out
	local tweenInfo = TweenInfo.new(
		0.5, -- Duration
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	local fadeOut = TweenService:Create(highlight, tweenInfo, {
		FillTransparency = 1,
		OutlineTransparency = 1
	})
	fadeOut:Play()
	
	-- Cleanup after tween
	fadeOut.Completed:Connect(function()
		highlight:Destroy()
	end)
	
	-- Camera shake for the player who got shot (natural, subtle)
	if isLocalPlayer then
		-- intensity, frequency (Hz), duration, fadeOut - subtle and natural
		CameraShake:Start(0.5, 12, 0.35, 0.2)
	end
end

--[[
	Create red highlight flash on character (visible to everyone)
	@param character Model - The character model to highlight
]]
function Effects:CreateRedFlash(character: Model)
	if not character then return end
	
	-- Red highlight flash (smooth fade)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 0, 0)
	highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 0
	highlight.Parent = character
	
	-- Tween fade out
	local tweenInfo = TweenInfo.new(
		0.5, -- Duration
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	local fadeOut = TweenService:Create(highlight, tweenInfo, {
		FillTransparency = 1,
		OutlineTransparency = 1
	})
	fadeOut:Play()
	
	-- Cleanup after tween
	fadeOut.Completed:Connect(function()
		highlight:Destroy()
	end)
end

--[[
	Play state change sound (Red/Green light)
	Non-positional - plays through SFX sound system (like music)
	@param state string - "Red" or "Green"
]]
function Effects:PlayStateSound(state: string)
	if state ~= "Red" and state ~= "Green" then
		warn("⚠️ Unknown state sound:", state)
		return
	end
	
	local Client_Sounds = require(script.Parent.Client_Sounds)
	Client_Sounds:Play(state)
end

--[[
	Create hit effect VFX at player's position, facing the guard
	@param rootPart BasePart - Player's HumanoidRootPart
	@param guardPos Vector3 - Guard's position (for orientation)
]]
function Effects:CreateHitEffect(rootPart: BasePart, guardPos: Vector3)
	if not rootPart or not rootPart.Parent then return end
	
	-- Get hit effect template from ReplicatedStorage
	local hitEffectTemplate = ReplicatedStorage:FindFirstChild("Assets")
	if hitEffectTemplate then
		hitEffectTemplate = hitEffectTemplate:FindFirstChild("VFX")
	end
	if hitEffectTemplate then
		hitEffectTemplate = hitEffectTemplate:FindFirstChild("HitEffect_FX")
	end
	
	if not hitEffectTemplate then
		warn("⚠️ HitEffect not found in ReplicatedStorage.Assets.VFX.HitEffect_FX")
		return
	end
	
	-- Find attachment inside the hit effect model's PrimaryPart
	local attachment = nil
	if hitEffectTemplate and hitEffectTemplate.PrimaryPart then
		attachment = hitEffectTemplate.PrimaryPart:FindFirstChildOfClass("Attachment")
	end
	
	if not attachment then
		warn("⚠️ No Attachment found in HitEffect PrimaryPart")
		return
	end
	
	-- Clone the attachment with all its particle emitters
	local clonedAttachment = attachment:Clone()
	
	-- Direction from player to guard (incoming bullet direction = impact side)
	local playerPos = rootPart.Position
	local directionToGuard = (guardPos - playerPos).Unit
	
	-- Place attachment ~1 stud toward the impact (where bullet would hit the body)
	local impactOffsetStuds = 1
	local attachmentWorldPos = playerPos + directionToGuard * impactOffsetStuds
	
	-- CFrame in part space: position offset + facing the guard
	clonedAttachment.CFrame = rootPart.CFrame:Inverse() * CFrame.lookAt(attachmentWorldPos, guardPos)
	
	-- Parent to player's rootpart
	clonedAttachment.Parent = rootPart
	
	self:EmitParticlesInContainer(clonedAttachment, 20)
	
	-- Cleanup after particles finish (2 seconds should be enough)
	Debris:AddItem(clonedAttachment, 2)
end

--[[
	Play upgrade VFX at a world position (e.g. brainrot slot). Clones Upgrade_FX, positions, emits, then cleans up.
	@param worldPosition Vector3 - Where to spawn the effect (e.g. slot model position)
]]
function Effects:PlayUpgradeVFX(worldPosition: Vector3)
	if not worldPosition then return end
	local vfxFolder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("VFX")
	local upgradeTemplate = vfxFolder and vfxFolder:FindFirstChild("Upgrade_FX")
	if not upgradeTemplate then
		warn("⚠️ Upgrade_FX not found in ReplicatedStorage.Assets.VFX")
		return
	end
	local clone = upgradeTemplate:Clone()
	
	-- Make all parts non-collidable so VFX doesn't block clicks/raycasts
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
		end
	end
	
	clone.Parent = workspace
	
	-- Center the VFX at worldPosition (compensate for pivot offset from bounding box)
	local cf, size = clone:GetBoundingBox()
	local pivotPos = clone:GetPivot().Position
	local centerPos = cf.Position
	local offsetToCenter = centerPos - pivotPos -- vector from pivot to center
	clone:PivotTo(CFrame.new(worldPosition - offsetToCenter) * clone:GetPivot().Rotation)
	
	self:EmitParticlesInContainer(clone, 10)
	Debris:AddItem(clone, 3)
end

-- ========================================
-- RAINBOW HIGHLIGHT SYSTEM (Purchase Prompts)
-- ========================================

local RainbowHighlightManager = {
	isActive = false,
	rotationConnection = nil,
	fadeTween = nil,
	totalDuration = 0,
	startTime = 0,
	looping = false, -- If true, runs until StopRainbowHighlight is called
}

--[[
	Play rainbow highlight effect on BlackFrameUI.RainbowHighlight
	Fades in, rotates gradient, auto-stops after duration (or loops infinitely)
	@param duration number? - How long to run (nil or 0 = loop forever until stopped)
]]
function Effects:PlayRainbowHighlight(duration: number?)
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local BlackFrameUI = PlayerGui:FindFirstChild("BlackFrameUI")
	if not BlackFrameUI then
		warn("Client_EffectsLibrary: BlackFrameUI not found")
		return
	end
	
	local RainbowHighlight = BlackFrameUI:FindFirstChild("RainbowHighlight")
	if not RainbowHighlight then
		warn("Client_EffectsLibrary: RainbowHighlight not found in BlackFrameUI")
		return
	end
	
	-- Find UIGradient inside RainbowHighlight
	local UIGradient = RainbowHighlight:FindFirstChildOfClass("UIGradient")
	if not UIGradient then
		warn("Client_EffectsLibrary: UIGradient not found in RainbowHighlight")
		return
	end
	
	local currentTime = tick()
	local isLooping = not duration or duration <= 0
	
	-- If already active, extend duration (or restart loop)
	if RainbowHighlightManager.isActive then
		if not isLooping then
			local elapsed = currentTime - RainbowHighlightManager.startTime
			RainbowHighlightManager.totalDuration = elapsed + duration
		end
		RainbowHighlightManager.looping = isLooping
		
		-- Cancel any fade out tween and fade back in
		if RainbowHighlightManager.fadeTween then
			RainbowHighlightManager.fadeTween:Cancel()
		end
		
		local fadeInTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		RainbowHighlightManager.fadeTween = TweenService:Create(RainbowHighlight, fadeInTweenInfo, {
			ImageTransparency = 0
		})
		RainbowHighlightManager.fadeTween:Play()
		
		return
	end
	
	-- Start new rainbow highlight
	RainbowHighlightManager.isActive = true
	RainbowHighlightManager.totalDuration = duration or 0
	RainbowHighlightManager.startTime = currentTime
	RainbowHighlightManager.looping = isLooping
	
	-- Fade in the RainbowHighlight (transparency 1 → 0)
	RainbowHighlight.ImageTransparency = 1
	local fadeTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	RainbowHighlightManager.fadeTween = TweenService:Create(RainbowHighlight, fadeTweenInfo, {
		ImageTransparency = 0
	})
	RainbowHighlightManager.fadeTween:Play()
	
	-- Start continuous rotation of UIGradient
	RainbowHighlightManager.rotationConnection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - RainbowHighlightManager.startTime
		
		-- Check if we should stop (only if not looping)
		if not RainbowHighlightManager.looping and elapsed >= RainbowHighlightManager.totalDuration then
			Effects:StopRainbowHighlight()
			return
		end
		
		-- Rotate the gradient continuously (180 degrees per second = 360 every 2 seconds)
		-- Use elapsed directly (no modulo) for smooth infinite rotation
		UIGradient.Rotation = (elapsed * 180) % 360
	end)
end

--[[
	Stop rainbow highlight effect with fade out
]]
function Effects:StopRainbowHighlight()
	if not RainbowHighlightManager.isActive then
		return
	end
	
	RainbowHighlightManager.isActive = false
	RainbowHighlightManager.looping = false
	
	-- Stop rotation
	if RainbowHighlightManager.rotationConnection then
		RainbowHighlightManager.rotationConnection:Disconnect()
		RainbowHighlightManager.rotationConnection = nil
	end
	
	-- Cancel any existing fade tween
	if RainbowHighlightManager.fadeTween then
		RainbowHighlightManager.fadeTween:Cancel()
	end
	
	-- Fade out the RainbowHighlight (transparency 0 → 1)
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local BlackFrameUI = PlayerGui:FindFirstChild("BlackFrameUI")
	if BlackFrameUI then
		local RainbowHighlight = BlackFrameUI:FindFirstChild("RainbowHighlight")
		if RainbowHighlight then
			local fadeOutTweenInfo = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			RainbowHighlightManager.fadeTween = TweenService:Create(RainbowHighlight, fadeOutTweenInfo, {
				ImageTransparency = 1
			})
			RainbowHighlightManager.fadeTween:Play()
		end
	end
	
	-- Reset duration
	RainbowHighlightManager.totalDuration = 0
end

-- ========================================
-- CONFETTI EFFECT (Purchase Success) - 3D Depth
-- ========================================

--[[
	Emit colorful confetti that falls from top of screen with 3D depth effect
	Smaller pieces = slower (background), Larger pieces = faster (foreground)
	@param amount number - Number of confetti pieces (default 60)
	@param duration number - How long confetti falls (default 2)
	@param size number - Size multiplier (default 1)
	@param soundId string? - Optional sound ID to play (default: Shared_Sounds.SFX.Confetti)
]]
function Effects:PlayConfetti(amount: number?, duration: number?, size: number?, soundId: string?)
	amount = amount or 60
	duration = duration or 2
	size = size or 1
	
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local Main = PlayerGui:FindFirstChild("Main")
	if not Main then
		warn("Client_EffectsLibrary: Main UI not found for confetti")
		return
	end
	
	-- Play celebration sound (custom soundId or default Confetti)
	local id = soundId or (Shared_Sounds.SFX and Shared_Sounds.SFX.Confetti)
	if id then
		local sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Volume = 1
		Client_Sounds:SetGroup(sound, "SFX")
		sound.Parent = PlayerGui
		sound:Play()
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
	end
	
	task.spawn(function()
		local colors = {
			Color3.fromRGB(255, 255, 0),   -- Yellow
			Color3.fromRGB(255, 170, 255), -- Pink
			Color3.fromRGB(255, 85, 255),  -- Magenta
			Color3.fromRGB(255, 85, 0),    -- Orange
			Color3.fromRGB(170, 85, 255),  -- Purple
			Color3.fromRGB(66, 224, 238),  -- Cyan
			Color3.fromRGB(0, 255, 0),     -- Green
		}
		
		for i = 1, amount do
			local confetti = Instance.new("Frame")
			confetti.Name = "Confetti"
			confetti.AnchorPoint = Vector2.new(0.5, 0.5)
			
			-- Randomize size for 3D depth effect (0.45x to 1.2x) – narrow range so fall times stay 1–1.5s
			local sizeMultiplier = math.random(45, 120) / 100
			local confettiSize = 0.03 * size * sizeMultiplier
			confetti.Size = UDim2.new(confettiSize, 0, confettiSize, 0)
			
			-- Set ZIndex based on size (smaller = background = lower ZIndex)
			confetti.ZIndex = math.floor(10 + (sizeMultiplier * 5)) -- 10-16 range
			
			confetti.BorderSizePixel = 0
			confetti.BackgroundColor3 = colors[math.random(1, #colors)]
			confetti.Rotation = math.random(-360, 360)
			-- Tighter spread: on-screen horizontal (0.08–0.92), narrow band at top (Y -0.12 to 0.02)
			local startX = math.random(8, 92) / 100
			local startY = math.random(-12, 2) / 100
			confetti.Position = UDim2.new(startX, 0, startY, 0)
			confetti.Parent = Main
			
			-- Fall: fastest 1s, slowest 1.5s (base 1s at 1x; min speed 0.67 so 1/0.67 ≈ 1.5s)
			local speedMultiplier = math.min(1.0, 0.4 + (sizeMultiplier * 0.6)) -- cap 1x so fastest = 1s
			local baseFallTime = 1.0
			local adjustedDuration = baseFallTime / speedMultiplier
			
			local tween = TweenService:Create(
				confetti,
				TweenInfo.new(adjustedDuration, Enum.EasingStyle.Linear),
				{
					Rotation = math.random(-360, 360),
					Position = UDim2.new(startX, 0, 1.1, 0)
				}
			)
			tween:Play()
			
			-- Destroy after animation
			tween.Completed:Connect(function()
				if confetti and confetti.Parent then
					confetti:Destroy()
				end
			end)
			
			-- Short burst window (0–40ms) so it pops without a visible line
			task.wait(math.random(0, 40) / 1000)
		end
	end)
end

-- ========================================
-- CASH RAIN EFFECT (Cash Purchases)
-- ========================================

--[[
	Emit falling cash icons with 3D depth effect (for cash purchases/rewards)
	@param amount number - Number of cash pieces (default 30)
	@param duration number - How long cash falls (default 2)
	@param size number - Size multiplier (default 1)
]]
function Effects:PlayCashRain(amount: number?, duration: number?, size: number?)
	amount = amount or 30
	duration = duration or 2
	size = size or 1
	
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local Main = PlayerGui:FindFirstChild("Main")
	if not Main then
		warn("Client_EffectsLibrary: Main UI not found for cash rain")
		return
	end
	
	task.spawn(function()
		for i = 1, amount do
			local cash = Instance.new("ImageLabel")
			cash.Name = "Cash"
			cash.AnchorPoint = Vector2.new(0.5, 0.5)
			
		-- Randomize size for 3D depth effect (0.5x to 1.3x)
		local sizeMultiplier = math.random(50, 130) / 100
		local cashSize = 0.08 * size * sizeMultiplier -- Increased from 0.03 to 0.08
		cash.Size = UDim2.new(cashSize, 0, cashSize, 0)
			
			-- Set ZIndex based on size (smaller = background)
			cash.ZIndex = math.floor(10 + (sizeMultiplier * 5)) -- 10-16 range
			
			cash.Position = UDim2.new(math.random(0, 100) / 100, 0, -0.1, 0)
			cash.BackgroundTransparency = 1
			cash.Image = "rbxassetid://80851691919622" -- Cash icon
			cash.ImageColor3 = Color3.fromRGB(255, 255, 255)
			cash.ScaleType = Enum.ScaleType.Fit
			cash.Parent = Main
			
			-- Speed based on size: smaller (background) = slower, larger (foreground) = faster
			local speedMultiplier = 0.3 + (sizeMultiplier * 0.7) -- 0.3x to 1.0x speed
			local baseFallTime = 1.0
			local adjustedDuration = baseFallTime / speedMultiplier
			
			local tween = TweenService:Create(
				cash,
				TweenInfo.new(adjustedDuration, Enum.EasingStyle.Linear),
				{
					Position = UDim2.new(cash.Position.X.Scale, 0, 1.1, 0),
					Rotation = math.random(0, 360)
				}
			)
			tween:Play()
			
			-- Destroy after animation
			tween.Completed:Connect(function()
				if cash and cash.Parent then
					cash:Destroy()
				end
			end)
			
			-- Stagger spawning throughout duration
			task.wait(duration / amount)
		end
	end)
end

-- ========================================
-- LUCKY BLOCK OPENING ANIMATION
-- ========================================

--[[
	Play complete lucky block opening animation - Pet Sim 99 Egg Drop Style
	Called via PlayEffect event from server (SingingX pattern)
	@param effectData table - Effect data containing all parameters
]]
function Effects:PlayLuckyBlockOpening(effectData)
	-- Extract data from effectData table
	local openingPlayerId = effectData.openingPlayerId
	local openingPlayerName = effectData.openingPlayerName
	local luckyBlockConfig = effectData.luckyBlockConfig
	local luckyBlockModifier = effectData.luckyBlockModifier
	local launchOrigin = effectData.launchOrigin
	local landingPosition = effectData.landingPosition
	local throwAngle = effectData.throwAngle
	local possibleBrainrots = effectData.possibleBrainrots
	local pickedConfig = effectData.pickedConfig
	local pickedModifier = effectData.pickedModifier
	local weight = effectData.weight
	local level = effectData.level
	local openId = effectData.openId
	
	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	if not Assets then return end
	
	-- Load configs
	local Shared_LuckyBlocks = require(ReplicatedStorage.Modules.ItemConfigs.Shared_LuckyBlocks)
	local Shared_Brainrots = require(ReplicatedStorage.Modules.ItemConfigs.Shared_Brainrots)
	local Shared_Effects = require(ReplicatedStorage.Modules.Settings.Shared_Effects)
	
	local lbData = Shared_LuckyBlocks.List[luckyBlockConfig]
	if not lbData then return end
	
	-- Get animation constants
	local constants = Shared_Effects.LuckyBlockOpening
	local THROW_DURATION = constants.ThrowDuration or 0.8
	local HOVER_HEIGHT = constants.HoverHeight or 0.25
	local LANDING_PAUSE = constants.LandingPause or 0.15
	local WIGGLE_ANGLE = constants.WiggleAngle or 20
	local WIGGLE_DURATION = constants.WiggleDuration or 0.08
	local WIGGLE_PAUSE = constants.WigglePause or 0.12
	local WIGGLE_COUNT = constants.WiggleCount or 4
	local EXPLOSION_SCALE = constants.ExplosionScale or 3
	local EXPLOSION_DURATION = constants.ExplosionDuration or 0.2
	local REVEAL_POP_DURATION = constants.RevealPopDuration or 0.25
	local REVEAL_ROTATE_DURATION = constants.RevealRotateDuration or 2
	local REVEAL_SHRINK_DURATION = constants.RevealShrinkDuration or 0.4
	local REVEAL_BOUNCE_HEIGHT = constants.RevealBounceHeight or 0.8
	
	-- Get lucky block model
	local luckyBlocksFolder = Assets:FindFirstChild("LuckyBlocks")
	if not luckyBlocksFolder then return end
	
	local modelName = Shared_LuckyBlocks:GetModelAssetName(luckyBlockConfig)
	local lbModelTemplate = luckyBlocksFolder:FindFirstChild(modelName)
	if not lbModelTemplate then return end
	
	-- Clone and setup lucky block
	local lbModel = lbModelTemplate:Clone()
	lbModel.Parent = workspace
	local primary = lbModel.PrimaryPart
	if not primary then
		lbModel:Destroy()
		return
	end
	
	-- Setup parts (cache descendants list)
	local descendants = lbModel:GetDescendants()
	for _, inst in ipairs(descendants) do
		if inst:IsA("BasePart") then
			inst.Massless = true
			inst.CanCollide = false
			inst.Anchored = false
		end
	end
	primary.Anchored = true
	
	-- Find floor position at landing
	local rayOrigin = landingPosition + Vector3.new(0, 10, 0)
	local rayDirection = Vector3.new(0, -50, 0)
	local raycastResult = workspace:Raycast(rayOrigin, rayDirection)
	local groundY = raycastResult and raycastResult.Position.Y or (landingPosition.Y - 5)
	local landingY = groundY + primary.Size.Y * 0.5
	local finalLanding = Vector3.new(landingPosition.X, landingY, landingPosition.Z)
	
	-- ========================================
	-- PHASE 1: Throw Arc (Smooth continuous spin → land perfectly)
	-- ========================================
	primary.CFrame = CFrame.new(launchOrigin)
	
	-- Add trail effect for coolness
	local trail = Instance.new("Trail")
	local attach0 = Instance.new("Attachment", primary)
	attach0.Position = Vector3.new(0, 0, 1)
	local attach1 = Instance.new("Attachment", primary)
	attach1.Position = Vector3.new(0, 0, -1)
	trail.Attachment0 = attach0
	trail.Attachment1 = attach1
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1)
	})
	trail.Lifetime = 0.3
	trail.MinLength = 0
	trail.Parent = primary
	
	-- Add "Coin Pop" sound when block starts traveling
	local coinPopSound = Instance.new("Sound")
	coinPopSound.SoundId = Shared_Sounds.SFX and Shared_Sounds.SFX["Lucky Block Wiggle"] or "rbxassetid://123604431530885"
	coinPopSound.Volume = 2
	coinPopSound.RollOffMaxDistance = 180
	coinPopSound.RollOffMinDistance = 30
	coinPopSound.Parent = primary
	Client_Sounds:SetGroup(coinPopSound, "SFX")
	coinPopSound:Play()
	
	-- Auto-cleanup sound when it ends
	coinPopSound.Ended:Connect(function()
		coinPopSound:Destroy()
	end)
	
	-- Get STARTING rotation (ignore position)
	local startRotation = primary.CFrame - primary.CFrame.Position
	
	-- Calculate ENDING rotation (facing player)
	local openingPlayer = Players:GetPlayerByUserId(openingPlayerId)
	local endRotation = CFrame.new(0, 0, 0) -- Identity rotation as fallback
	if openingPlayer and openingPlayer.Character then
		local playerRoot = openingPlayer.Character:FindFirstChild("HumanoidRootPart")
		if playerRoot then
			local lookTarget = Vector3.new(playerRoot.Position.X, finalLanding.Y, playerRoot.Position.Z)
			local lookCF = CFrame.lookAt(finalLanding, lookTarget)
			endRotation = lookCF - lookCF.Position -- Extract rotation only
		end
	end
	
	local distance = (finalLanding - launchOrigin).Magnitude
	local arcHeight = math.min(distance * 0.4, 8)
	
	-- Total spins during flight (1.0 full rotation = 360 degrees)
	-- MUST be a whole number so it returns to base orientation!
	local totalSpins = 1.0
	
	-- Cache spin axis (calculated once, not every frame)
	local spinAxis = Vector3.new(1, 1, 0).Unit
	
	local animationStartTime = os.clock()
	
	local throwConnection
	throwConnection = RunService.Heartbeat:Connect(function()
		if not lbModel or not lbModel.Parent then
			if throwConnection then throwConnection:Disconnect() end
			return
		end
		
		local elapsed = os.clock() - animationStartTime
		local t = math.min(elapsed / THROW_DURATION, 1)
		
		-- Calculate position along parabolic arc
		local horizontalPos = launchOrigin:Lerp(finalLanding, t)
		local arcY = -4 * arcHeight * math.pow(t - 0.5, 2) + arcHeight
		local arcPosition = Vector3.new(horizontalPos.X, horizontalPos.Y + arcY, horizontalPos.Z)
		
		-- Lerp from start rotation to end rotation
		local baseRotation = startRotation:Lerp(endRotation, t)
		
		-- Apply spin on a DIAGONAL LOCAL axis for smooth, consistent tumble
		-- Use easing: spin fast at start, slow down at end
		local spinT = t * t * (3 - 2 * t) -- Smoothstep easing
		local spinProgress = spinT * 360 * 1 -- 0 to 360 degrees (1 rotation)
		
		-- Use cached spin axis
		local localSpin = CFrame.fromAxisAngle(spinAxis, math.rad(spinProgress))
		
		-- Apply: base rotation FIRST, THEN local spin
		local finalRotation = baseRotation * localSpin
		
		-- Apply position + rotation
		primary.CFrame = CFrame.new(arcPosition) * finalRotation
		
		-- When animation completes
		if t >= 1 then
			throwConnection:Disconnect()
			-- Force exact landing rotation
			primary.CFrame = CFrame.new(finalLanding) * endRotation
			if trail then trail:Destroy() end
		end
	end)
	
	-- Wait for throw to complete before continuing
	task.wait(THROW_DURATION)
	
	-- ========================================
	-- PHASE 2: Land & Hover (smooth settle)
	-- ========================================
	-- Store current orientation (already facing player from flight)
	local currentOrientation = primary.CFrame - primary.CFrame.Position
	
	local hoverY = finalLanding.Y + HOVER_HEIGHT
	local hoverPos = Vector3.new(finalLanding.X, hoverY, finalLanding.Z)
	
	-- Smooth settle with Heartbeat (maintain orientation!)
	local settleStart = os.clock()
	local settleDuration = 0.2
	local settleConnection
	settleConnection = RunService.Heartbeat:Connect(function()
		if not lbModel or not lbModel.Parent then
			if settleConnection then settleConnection:Disconnect() end
			return
		end
		
		local elapsed = os.clock() - settleStart
		local t = math.min(elapsed / settleDuration, 1)
		
		if t >= 1 then
			settleConnection:Disconnect()
			primary.CFrame = CFrame.new(hoverPos) * currentOrientation
			return
		end
		
		-- Bounce easing (like Enum.EasingStyle.Bounce.Out)
		local easedT
		if t < (1/2.75) then
			easedT = 7.5625 * t * t
		elseif t < (2/2.75) then
			local t2 = t - (1.5/2.75)
			easedT = 7.5625 * t2 * t2 + 0.75
		elseif t < (2.5/2.75) then
			local t2 = t - (2.25/2.75)
			easedT = 7.5625 * t2 * t2 + 0.9375
		else
			local t2 = t - (2.625/2.75)
			easedT = 7.5625 * t2 * t2 + 0.984375
		end
		
		-- Interpolate position, keep orientation
		local currentPos = finalLanding:Lerp(Vector3.new(hoverPos.X, hoverPos.Y, hoverPos.Z), easedT)
		primary.CFrame = CFrame.new(currentPos) * currentOrientation
	end)
	
	task.wait(settleDuration)
	if settleConnection then settleConnection:Disconnect() end
	
	-- Store the lookAtCFrame for wiggle reference
	local lookAtCFrame = primary.CFrame
	
	-- Landing pause before wiggle
	task.wait(LANDING_PAUSE)
	
	-- ========================================
	-- PHASE 3: Pokéball-style hop + wiggle!
	-- ========================================
	
	-- Pokéball wiggle: Gets FASTER and MORE INTENSE each time!
	local hopHeights = {0.8, 1, 1.5, 2} -- Each hop gets HIGHER
	local hopUpDurations = {0.15, 0.14, 0.13, 0.12} -- Hops get FASTER (4th less extreme)
	local hopDownDurations = {0.12, 0.11, 0.10, 0.09} -- Falls get FASTER (4th less extreme)
	local wiggleDurations = {0.08, 0.075, 0.07, 0.065} -- Wiggles get faster (4th less extreme)
	
	for wiggleIndex = 1, WIGGLE_COUNT do
		local hopHeight = hopHeights[wiggleIndex]
		local hopUpDuration = hopUpDurations[wiggleIndex]
		local hopDownDuration = hopDownDurations[wiggleIndex]
		local wiggleDuration = wiggleDurations[wiggleIndex]
		
		-- HOP UP (smooth Heartbeat animation)
		local hopUpStart = os.clock()
		local hopUpConnection
		hopUpConnection = RunService.Heartbeat:Connect(function()
			if not lbModel or not lbModel.Parent then
				if hopUpConnection then hopUpConnection:Disconnect() end
				return
			end
			
			local elapsed = os.clock() - hopUpStart
			local t = math.min(elapsed / hopUpDuration, 1)
			
			if t >= 1 then
				hopUpConnection:Disconnect()
				primary.CFrame = lookAtCFrame + Vector3.new(0, hopHeight, 0)
				return
			end
			
			-- Smooth ease out (quadratic)
			local easedT = 1 - math.pow(1 - t, 2)
			primary.CFrame = lookAtCFrame + Vector3.new(0, hopHeight * easedT, 0)
		end)
		task.wait(hopUpDuration)
		if hopUpConnection then hopUpConnection:Disconnect() end
		
		-- WIGGLE IN AIR (smooth Heartbeat animations)
		local wiggleAngles = {-WIGGLE_ANGLE, WIGGLE_ANGLE, -WIGGLE_ANGLE, 0}
		for shake = 1, 4 do
			local startAngle = shake == 1 and 0 or wiggleAngles[shake - 1]
			local targetAngle = wiggleAngles[shake]
			
			local startCF = (lookAtCFrame + Vector3.new(0, hopHeight, 0)) * CFrame.Angles(0, 0, math.rad(startAngle))
			local endCF = (lookAtCFrame + Vector3.new(0, hopHeight, 0)) * CFrame.Angles(0, 0, math.rad(targetAngle))
			
			-- Play pop sound on each wiggle (shakes 1-3, not shake 4 which is return to center)
			if shake <= 3 then
				local wiggleRollSound = Instance.new("Sound")
				wiggleRollSound.SoundId = Shared_Sounds.SFX and Shared_Sounds.SFX["Coin Pop"] or "rbxassetid://120588150624601"
				wiggleRollSound.Volume = 0.5
				wiggleRollSound.RollOffMaxDistance = 180
				wiggleRollSound.RollOffMinDistance = 30
				-- Increase pitch as wiggles get faster/more intense
				wiggleRollSound.PlaybackSpeed = 1.0 + (wiggleIndex - 1) * 0.15 -- 1.0, 1.15, 1.3, 1.45
				wiggleRollSound.Parent = primary
				Client_Sounds:SetGroup(wiggleRollSound, "SFX")
				wiggleRollSound:Play()
				wiggleRollSound.Ended:Connect(function()
					wiggleRollSound:Destroy()
				end)
			end
			
			local wiggleStart = os.clock()
			local wiggleConnection
			wiggleConnection = RunService.Heartbeat:Connect(function()
				if not lbModel or not lbModel.Parent then
					if wiggleConnection then wiggleConnection:Disconnect() end
					return
				end
				
				local elapsed = os.clock() - wiggleStart
				local t = math.min(elapsed / wiggleDuration, 1)
				
				if t >= 1 then
					wiggleConnection:Disconnect()
					primary.CFrame = endCF
					return
				end
				
				-- Smooth sine easing with elastic bounce
				local easedT = math.sin(t * math.pi * 0.5)
				primary.CFrame = startCF:Lerp(endCF, easedT)
			end)
			task.wait(wiggleDuration)
			if wiggleConnection then wiggleConnection:Disconnect() end
		end
		
		-- HOP DOWN (smooth Heartbeat animation) - BUT NOT ON FINAL WIGGLE!
		if wiggleIndex < WIGGLE_COUNT then
			local hopDownStart = os.clock()
			local hopDownConnection
			hopDownConnection = RunService.Heartbeat:Connect(function()
				if not lbModel or not lbModel.Parent then
					if hopDownConnection then hopDownConnection:Disconnect() end
					return
				end
				
				local elapsed = os.clock() - hopDownStart
				local t = math.min(elapsed / hopDownDuration, 1)
				
				if t >= 1 then
					hopDownConnection:Disconnect()
					primary.CFrame = lookAtCFrame
					return
				end
				
				-- Smooth ease in (quadratic)
				local easedT = t * t
				local currentY = hopHeight * (1 - easedT)
				primary.CFrame = lookAtCFrame + Vector3.new(0, currentY, 0)
			end)
			task.wait(hopDownDuration)
			if hopDownConnection then hopDownConnection:Disconnect() end
			
			-- Brief pause before next hop
			local pauseTime = 0.08 - (wiggleIndex * 0.015)
			task.wait(pauseTime)
		else
			-- FINAL WIGGLE - Stay in the air! Explosion happens here
		end
	end
	
	-- Play explosion sound RIGHT BEFORE flash (at end of wiggle phase)
	local soundHost = Instance.new("Part")
	soundHost.Anchored = true
	soundHost.CanCollide = false
	soundHost.Transparency = 1
	soundHost.Size = Vector3.new(0.1, 0.1, 0.1)
	soundHost.CFrame = primary.CFrame
	soundHost.Parent = workspace
	
	local explosionSound = Instance.new("Sound")
	explosionSound.SoundId = "rbxassetid://114518565533265"
	explosionSound.Volume = 0.6
	explosionSound.RollOffMaxDistance = 150
	explosionSound.RollOffMinDistance = 20
	explosionSound.Parent = soundHost
	Client_Sounds:SetGroup(explosionSound, "SFX")
	explosionSound:Play()
	explosionSound.Ended:Connect(function()
		soundHost:Destroy() -- Cleanup both sound and host
	end)
	
	-- ========================================
	-- PHASE 4: Explosion + Brainrot Pop (simultaneous)
	-- ========================================
	
	-- Start spawning brainrot DURING explosion (Normal + modifier visuals)
	local finalModel = Shared_ModifierHandler:GetBrainrotModel(pickedConfig, pickedModifier or "Normal")
	if finalModel then
		finalModel.Parent = workspace
		if not finalModel.PrimaryPart then
			finalModel.PrimaryPart = finalModel:FindFirstChildWhichIsA("BasePart", true)
		end
		local fp = finalModel.PrimaryPart
		if fp then
					for _, inst in ipairs(finalModel:GetDescendants()) do
						if inst:IsA("BasePart") then
							inst.Massless = true
							inst.CanCollide = false
							inst.Anchored = false
						end
					end
					fp.Anchored = true
					
					-- Position CORRECTLY like slots do - using PrimaryPart size
					local modelHeight = fp.Size.Y
					local correctY = hoverPos.Y + (modelHeight / 2)
					
					-- Orient toward opening player
					local openingPlayer = Players:GetPlayerByUserId(openingPlayerId)
					local targetPos = Vector3.new(hoverPos.X, correctY, hoverPos.Z)
					local facingCFrame = CFrame.new(targetPos)
					
					if openingPlayer and openingPlayer.Character then
						local playerRoot = openingPlayer.Character:FindFirstChild("HumanoidRootPart")
						if playerRoot then
							facingCFrame = CFrame.lookAt(targetPos, Vector3.new(playerRoot.Position.X, targetPos.Y, playerRoot.Position.Z))
						end
					end
					
					-- Use PivotTo for proper positioning
					finalModel:PivotTo(facingCFrame)
					
					-- Start at scale 0
					finalModel:ScaleTo(0.01)
					
					-- Play success sound
					if openingPlayerId == Player.UserId then
						Client_Sounds:Play("Item Equip")
					end
				end
	end
	
	-- Clone ONLY the primary part for explosion effect
	local explosionPart = primary:Clone()
	explosionPart.Parent = workspace
	explosionPart.CFrame = primary.CFrame
	explosionPart.Anchored = true
	
	-- Make it neon white, START FULLY VISIBLE (0 transparency)
	explosionPart.Material = Enum.Material.Neon
	explosionPart.Color = Color3.new(1, 1, 1)
	explosionPart.Transparency = 0
	
	-- Remove any surface appearances/textures
	for _, child in ipairs(explosionPart:GetChildren()) do
		if child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceAppearance") then
			child:Destroy()
		end
	end
	
	-- Store original size
	local originalSize = explosionPart.Size
	explosionPart.Size = originalSize * 0.5
	
	-- Instantly hide the original lucky block (explosion flash covers it)
	for _, part in ipairs(lbModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 1
		end
	end
	
	local explosionStart = os.clock()
	local explosionConnection
	explosionConnection = RunService.Heartbeat:Connect(function()
		if not explosionPart or not explosionPart.Parent then
			if explosionConnection then explosionConnection:Disconnect() end
			return
		end
		
		local elapsed = os.clock() - explosionStart
		local t = elapsed / EXPLOSION_DURATION
		
		if t >= 1 then
			explosionConnection:Disconnect()
			explosionPart:Destroy()
			return
		end
		
		-- Scale from 0.5 to 3x (fast expansion)
		local scale = 0.5 + (t * (EXPLOSION_SCALE - 0.5))
		explosionPart.Size = originalSize * scale
		
		-- Fade from 0 to 1 with exponential easing (looks more natural)
		local fadeT = 1 - math.pow(1 - t, 3) -- Exponential fade out
		explosionPart.Transparency = fadeT
		
		-- Keep brainrot at 0.01 scale during explosion (invisible)
		-- It will pop out AFTER the explosion finishes
	end)
	
	-- Destroy original model and cleanup
	lbModel:Destroy()
	
	-- Start brainrot pop animation AT THE SAME TIME as explosion (not after)
	task.spawn(function()
		if not finalModel or not finalModel.Parent then return end
		local fp = finalModel.PrimaryPart
		if not fp then return end
		
		-- FIRST: Load and play idle animation IMMEDIATELY
		local animator = nil
		local humanoid = finalModel:FindFirstChildOfClass("Humanoid", true)
		if humanoid then
			animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		else
			local animController = finalModel:FindFirstChildOfClass("AnimationController", true)
			if not animController then
				animController = Instance.new("AnimationController")
				animController.Parent = finalModel
			end
			animator = animController:FindFirstChildOfClass("Animator") or Instance.new("Animator", animController)
		end
		
		-- Load idle animation from Assets.Animations[ConfigName].Idle
		if animator then
			local animFolder = Assets:FindFirstChild("Animations")
			local configAnimFolder = animFolder and animFolder:FindFirstChild(pickedConfig)
			local idleAnim = configAnimFolder and configAnimFolder:FindFirstChild("Idle")
			
			if idleAnim and idleAnim:IsA("Animation") then
				-- Check if not already playing
				local alreadyPlaying = false
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					if track.Animation and track.Animation.AnimationId == idleAnim.AnimationId then
						alreadyPlaying = true
						break
					end
				end
				
				if not alreadyPlaying then
					local track = animator:LoadAnimation(idleAnim)
					track.Priority = Enum.AnimationPriority.Idle
					track.Looped = true
					track:Play(0.1, 1, 1)
				end
			end
		end
		
		-- PLAY COLLECTION EFFECTS RIGHT AS POP STARTS (only for opening player)
		if openingPlayerId == Player.UserId then
			-- Play collection effect (confetti + camera zoom)
			self:PlayCollectionEffect()
			
			-- Show popup with callout sound
			local config = Shared_Brainrots.List[pickedConfig]
			if config then
				local displayName = config.DisplayName or pickedConfig
				local rarityInfo = Shared_Rarity:GetRarityInfo(config.Rarity)
				if rarityInfo then
					local message = string.format("Unlocked %s!", displayName)
					local uniquePopupType = "brainrot_luckyblock_" .. pickedConfig .. "_" .. tick()
					Client_Popups:AddPopupImmediate(
						message,
						{
							popupType = uniquePopupType,
							sound = config.CalloutSound,
							gradient = rarityInfo.gradient,
							isRainbow = rarityInfo.isRainbow,
							duration = 3
						}
					)
				end
			end
		end
		
		-- Notify server to add brainrot to inventory
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local ItemHandler = Events and Events:FindFirstChild("ItemHandler")
		if ItemHandler then
			ItemHandler:FireServer("FinishOpening", openId)
		end
		
		-- POP animation: Scale from 0.01 to 1.1x then settle to 1x over 0.6s
		local popStart = os.clock()
		local popConnection
		popConnection = RunService.Heartbeat:Connect(function()
			if not finalModel or not finalModel.Parent then
				if popConnection then popConnection:Disconnect() end
				return
			end
			
			local elapsed = os.clock() - popStart
			local t = elapsed / REVEAL_POP_DURATION
			
			if t >= 1 then
				popConnection:Disconnect()
				finalModel:ScaleTo(1) -- Settle at 1x
				return
			end
			
			-- Pop animation: 0.01 -> 1.1 (0 to 70%) -> 1.0 (70% to 100%)
			local popScale
			if t < 0.7 then
				-- Scale up from 0.01 to 1.1 (with slight ease)
				local scaleT = t / 0.7
				local easedT = scaleT * scaleT * (3 - 2 * scaleT) -- Smoothstep
				popScale = 0.01 + (easedT * 1.09) -- 0.01 to 1.1
			else
				-- Settle from 1.1 to 1.0 (with bounce-out feel)
				local settleT = (t - 0.7) / 0.3
				local easedT = 1 - math.pow(1 - settleT, 2) -- Ease out
				popScale = 1.1 - (easedT * 0.1) -- 1.1 to 1.0
			end
			finalModel:ScaleTo(popScale)
		end)
		
		task.wait(REVEAL_POP_DURATION)
		if popConnection then popConnection:Disconnect() end
		finalModel:ScaleTo(1)
	end)
	
	task.wait(EXPLOSION_DURATION)
	
	-- ========================================
	-- PHASE 5: Rotating Reveal (showcase!)
	-- ========================================
	if finalModel and finalModel.Parent then
		local fp = finalModel.PrimaryPart
		if fp then
			
			-- Get pivot position (center of model at base)
			local pivotPos = finalModel:GetPivot().Position
			
			-- Rotate 720° + bounce + shrink ALL AT ONCE (START IMMEDIATELY)
			local totalDuration = REVEAL_ROTATE_DURATION + REVEAL_SHRINK_DURATION
			local rotateStart = os.clock()
			local bounceHeight = REVEAL_BOUNCE_HEIGHT
			local rotateConnection
			rotateConnection = RunService.Heartbeat:Connect(function()
				if not finalModel or not finalModel.Parent then
					if rotateConnection then rotateConnection:Disconnect() end
					return
				end
				
				local elapsed = os.clock() - rotateStart
				local t = elapsed / totalDuration
				
				if t >= 1 then
					rotateConnection:Disconnect()
					finalModel:Destroy()
					return
				end
				
				-- Rotate 720° (2 full rotations) throughout entire animation
				local rotation = t * 720
				
				-- Bounce UP then DOWN - starts at 0, goes up to bounceHeight, back to 0
				local bounceT = t * math.pi * 2 -- 0 to 2π for one complete cycle
				local bounce = math.sin(bounceT) * bounceHeight
				local currentY = pivotPos.Y + bounce
				local currentPos = Vector3.new(pivotPos.X, currentY, pivotPos.Z)
				
				-- Start shrinking after rotation duration
				local scale = 1
				if elapsed > REVEAL_ROTATE_DURATION then
					local shrinkT = (elapsed - REVEAL_ROTATE_DURATION) / REVEAL_SHRINK_DURATION
					scale = 1 - shrinkT
					finalModel:ScaleTo(math.max(scale, 0.01))
				end
				
				-- Keep facing player while rotating and bouncing
				local openingPlayer = Players:GetPlayerByUserId(openingPlayerId)
				local baseCFrame = CFrame.new(currentPos)
				if openingPlayer and openingPlayer.Character then
					local playerRoot = openingPlayer.Character:FindFirstChild("HumanoidRootPart")
					if playerRoot then
						baseCFrame = CFrame.lookAt(currentPos, Vector3.new(playerRoot.Position.X, currentPos.Y, playerRoot.Position.Z))
					end
				end
				
				finalModel:PivotTo(baseCFrame * CFrame.Angles(0, math.rad(rotation), 0))
			end)
			
			task.wait(totalDuration)
		end
	end
	
	-- Notify server animation complete (only if this is the opening player)
	if openingPlayerId == Player.UserId then
		local Events = ReplicatedStorage:WaitForChild("Events")
		local ItemHandler = Events:WaitForChild("ItemHandler")
		ItemHandler:FireServer("FinishOpening", openId)
	end
end

--[[
	Play thunderbolt effect from clouds to brainrot (SingingX exact implementation)
	@param startPosition Vector3 - Lightning start (clouds)
	@param endPosition Vector3 - Lightning end (brainrot)
	@param brainrotUID string - UID of the brainrot to scale
]]
function Effects:PlayThunderbolt(startPosition, endPosition, brainrotUID)
	-- Create segmented lightning bolt (exact SingingX implementation)
	local segments = 15
	local color = Color3.fromRGB(255, 255, 100) -- Yellow lightning
	local lifetime = 2.5
	
	local direction = (endPosition - startPosition)
	local totalDistance = direction.Magnitude
	local segmentLength = totalDistance / segments
	local unitDir = direction.Unit
	local lastPos = startPosition
	
	local lightningParts = {}
	
	for i = 1, segments do
		-- Progress from top to bottom (0 = top, 1 = bottom)
		local progress = i / segments
		
		-- Reduce jaggedness as we go down (0.2 at top, 0.12 at bottom)
		local jaggedness = 0.2 * (1 - progress) + 0.12
		
		-- Taper thickness from top to bottom (2 at top, 0.3 at bottom)
		local thickness = 2 * (1 - progress) + 0.3
		
		-- Only horizontal offset (X and Z), no vertical (Y) zigzagging
		local horizontalOffset = Vector3.new(
			(math.random() - 0.5) * jaggedness * totalDistance,
			0, -- No Y offset
			(math.random() - 0.5) * jaggedness * totalDistance
		)
		
		local nextPos = (i == segments) and endPosition or (startPosition + unitDir * (segmentLength * i) + horizontalOffset)
		local mid = (lastPos + nextPos) / 2
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Size = Vector3.new(thickness, thickness, (nextPos - lastPos).Magnitude)
		part.CFrame = CFrame.lookAt(mid, nextPos)
		part.Parent = workspace:FindFirstChild("Effects") or workspace
		
		table.insert(lightningParts, part)
		lastPos = nextPos
	end
	
	-- Play ThunderBolt sound at impact position (using SingingX sound)
	local thunderSound = Instance.new("Sound")
	thunderSound.SoundId = "rbxassetid://127625722966323" -- SingingX ThunderBolt sound
	thunderSound.Volume = 2
	thunderSound.RollOffMinDistance = 50
	thunderSound.RollOffMaxDistance = 700
	Client_Sounds:SetGroup(thunderSound, "SFX")
	thunderSound.Parent = lightningParts[#lightningParts]
	thunderSound:Play()
	game:GetService("Debris"):AddItem(thunderSound, 5)
	
	-- Scale the struck brainrot (SingingX scale effect)
	if brainrotUID then
		local brainrotsFolder = workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Brainrots")
		if brainrotsFolder then
			-- Find brainrot by checking UID attribute on models
			for _, model in pairs(brainrotsFolder:GetChildren()) do
				if model:IsA("Model") and model:GetAttribute("UID") == brainrotUID then
					Effects:ScaleModelBounce(model, 1.2, 0.5)
					break
				end
			end
		end
	end
	
	-- Fade out all segments together after lightning hits (exact SingingX timing)
	task.spawn(function()
		local fadeStart = tick()
		while tick() - fadeStart < lifetime do
			local progress = (tick() - fadeStart) / lifetime
			for _, part in ipairs(lightningParts) do
				if part and part.Parent then
					part.Transparency = progress
				end
			end
			task.wait()
		end
		
		-- Clean up all parts
		for _, part in ipairs(lightningParts) do
			if part and part.Parent then
				part:Destroy()
			end
		end
	end)
	
	-- Add camera shake using our CameraShake module
	CameraShake:ShakeInRadius(endPosition, {
		Radius = 150,
		OuterRadius = 300,
		Intensity = 0.45,
		Roughness = 8,
		Damping = 0.25,
		Distance = 0.5,
		Duration = 1
	})
end

--[[
	Scale a model up and down with a bounce effect (SingingX style)
	@param model Model - The model to scale
	@param maxScale number - Maximum scale multiplier (default 1.2)
	@param duration number - Total animation duration (default 0.5)
]]
function Effects:ScaleModelBounce(model, maxScale, duration)
	if not model or not model:IsA("Model") then
		warn("ScaleModelBounce: Invalid model")
		return
	end
	
	maxScale = maxScale or 1.2
	duration = duration or 0.5
	
	local originalScale = model:GetScale()
	local startTime = tick()
	
	-- Animate scale using RunService (SingingX implementation)
	local scaleConnection
	scaleConnection = game:GetService("RunService").RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local progress = math.min(elapsed / duration, 1)
		
		local scaleFactor = 1
		if progress < 0.5 then
			-- Scale up from 1.0 to maxScale
			local t = progress * 2
			scaleFactor = 1 + ((maxScale - 1) * math.sin(t * math.pi / 2))
		else
			-- Scale down from maxScale to 1.0
			local t = (progress - 0.5) * 2
			scaleFactor = maxScale - ((maxScale - 1) * math.sin(t * math.pi / 2))
		end
		
		model:ScaleTo(originalScale * scaleFactor)
		
		if progress >= 1 then
			scaleConnection:Disconnect()
			model:ScaleTo(originalScale) -- Ensure exact restoration
		end
	end)
	
	-- Safety timeout cleanup
	task.delay(duration + 0.1, function()
		if scaleConnection and scaleConnection.Connected then
			scaleConnection:Disconnect()
			model:ScaleTo(originalScale)
		end
	end)
end

-- ========================================
-- METEOR EFFECTS (Client-Side)
-- ========================================

--[[
	Spawn and animate a meteor falling from sky to impact position
	@param startPosition Vector3 - Starting position in sky
	@param impactPosition Vector3 - Landing position
	@param duration number - Travel duration in seconds
	@param speed number - Speed of meteor
]]
function Effects:PlayMeteor(startPosition, impactPosition, duration, speed)
	-- Get meteor asset from workspace.Events (cloned by server)
	local eventsFolder = workspace:FindFirstChild("Events")
	if not eventsFolder then return end
	
	local meteorPreset = eventsFolder:FindFirstChild("Meteor")
	if not meteorPreset then return end
	
	local meteorPartTemplate = meteorPreset:FindFirstChild("Meteor")
	if not meteorPartTemplate or not meteorPartTemplate:IsA("BasePart") then return end
	
	-- Clone meteor
	local meteor = meteorPartTemplate:Clone()
	
	-- Position meteor at start with rotation towards target
	local lookCFrame = CFrame.lookAt(startPosition, impactPosition)
	meteor.CFrame = lookCFrame
	meteor.Parent = workspace
	
	-- Add whoosh sound
	local meteorSound = Instance.new("Sound")
	meteorSound.SoundId = "rbxassetid://137851402452818"
	meteorSound.Looped = true
	meteorSound.RollOffMinDistance = 100
	meteorSound.RollOffMaxDistance = 800
	meteorSound.Volume = 1
	meteorSound.Parent = meteor
	meteorSound:Play()
	
	-- Animate meteor falling
	local startTime = tick()
	
	local moveConnection
	moveConnection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.min(elapsed / duration, 1)
		
		if not meteor or not meteor.Parent then
			moveConnection:Disconnect()
			return
		end
		
		-- Interpolate position
		local currentPos = startPosition:Lerp(impactPosition, alpha)
		
		-- Update meteor CFrame with rotation
		local lookCFrame = CFrame.lookAt(currentPos, impactPosition)
		meteor.CFrame = lookCFrame
		
		-- If reached destination, instant fade and cleanup
		if alpha >= 1 then
			moveConnection:Disconnect()
			if meteorSound then
				meteorSound:Stop()
			end
			
			-- Destroy all VFX immediately on impact
			for _, desc in pairs(meteor:GetDescendants()) do
				if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
					desc.Enabled = false
				end
			end
			
			-- Instant fade on impact (very quick tween)
			TweenService:Create(meteor, TweenInfo.new(0.1), {Transparency = 1}):Play()
			
			-- Destroy meteor quickly after fade
			Debris:AddItem(meteor, 0.15)
		end
	end)
end

--[[
	Play meteor impact explosion effect with VFX
	@param impactPosition Vector3 - Position where meteor hit
]]
function Effects:PlayMeteorImpact(impactPosition)
	-- Get VFX assets
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return end
	
	local vfxFolder = assets:FindFirstChild("VFX")
	if not vfxFolder then return end
	
	local explosionTemplate = vfxFolder:FindFirstChild("MeteorExplosion")
	if not explosionTemplate then return end
	
	-- Clone explosion VFX
	local explosion = explosionTemplate:Clone()
	explosion:PivotTo(CFrame.new(impactPosition))
	explosion.Parent = workspace
	
	-- Play impact sound
	local impactSound = Instance.new("Sound")
	impactSound.SoundId = "rbxassetid://126678295707422"
	impactSound.Volume = 1
	impactSound.RollOffMinDistance = 75
	impactSound.RollOffMaxDistance = 600
	impactSound.Parent = explosion.PrimaryPart or explosion:FindFirstChildWhichIsA("BasePart")
	impactSound:Play()
	
	-- Emit particles using centralized function (respects EmitCount, EmitDelay, EmitBursts attributes)
	self:EmitParticlesInContainer(explosion, 10)
	
	-- Camera shake (same as lightning strike)
	CameraShake:ShakeInRadius(impactPosition, {
		Radius = 150,
		OuterRadius = 400,
		Intensity = 0.45,
		Roughness = 8,
		Damping = 0.25,
		Distance = 0.5,
		Duration = 1
	})
	
	-- Cleanup explosion after particles finish
	Debris:AddItem(explosion, 17)
end

-- ========================================
-- PIGGY BLOCK DROP ANIMATION
-- ========================================

--[[
	Play piggy lucky block drop animation (fake visual that fades out)
	Server spawns real block at the same time this finishes
	@param effectData table - { luckyBlockName, launchPos, landingPos, duration, arcHeight }
]]
function Effects:PlayPiggyBlockDrop(effectData)
	local luckyBlockName = effectData.luckyBlockName
	local launchPos = effectData.launchPos
	local landingPos = effectData.landingPos
	local duration = effectData.duration or 2
	local arcHeight = effectData.arcHeight or 15
	
	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	if not Assets then return end
	
	local luckyBlocksFolder = Assets:FindFirstChild("LuckyBlocks")
	if not luckyBlocksFolder then return end
	
	local modelTemplate = luckyBlocksFolder:FindFirstChild(luckyBlockName)
	if not modelTemplate then return end
	
	-- Clone lucky block model
	local lbModel = modelTemplate:Clone()
	lbModel.Parent = workspace
	
	local primary = lbModel.PrimaryPart
	if not primary then
		lbModel:Destroy()
		return
	end
	
	-- Setup parts
	for _, inst in ipairs(lbModel:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Massless = true
			inst.CanCollide = false
			inst.Anchored = false
			inst.Transparency = 0
		end
	end
	primary.Anchored = true
	
	-- Play pop sound
	local popSound = Instance.new("Sound")
	popSound.SoundId = Shared_Sounds.SFX and Shared_Sounds.SFX["Lucky Block Wiggle"] or "rbxassetid://123604431530885"
	popSound.Volume = 1.5
	popSound.RollOffMaxDistance = 180
	popSound.RollOffMinDistance = 30
	popSound.Parent = primary
	Client_Sounds:SetGroup(popSound, "SFX")
	popSound:Play()
	
	-- Animate arc from piggy to ground with fade
	local startTime = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not lbModel or not lbModel.Parent then
			if connection then connection:Disconnect() end
			return
		end
		
		local elapsed = os.clock() - startTime
		local t = math.clamp(elapsed / duration, 0, 1)
		
		-- Arc position
		local pos = launchPos:Lerp(landingPos, t)
		pos = pos + Vector3.new(0, math.sin(t * math.pi) * arcHeight, 0)
		primary.CFrame = CFrame.new(pos)
		
		-- Fade out in last 10% of animation
		if t > 0.95 then
			local fadeT = (t - 0.9) / 0.1
			for _, inst in ipairs(lbModel:GetDescendants()) do
				if inst:IsA("BasePart") then
					inst.Transparency = fadeT
				end
			end
		end
		
		-- End animation
		if t >= 1 then
			connection:Disconnect()
			lbModel:Destroy()
		end
	end)
end

return Effects
