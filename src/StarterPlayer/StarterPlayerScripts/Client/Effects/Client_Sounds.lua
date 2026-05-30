--// Client_Sounds: Event-driven music system with smooth transitions
--// Handles background music, event music, and SFX with crossfading

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui

-- Music state management
local MusicLoaded = false
local MusicTracks = {}
local IntenseMusicTracks = {}
local EventMusicTracks = {}
local MusicEnabled = true

-- Current playing tracks (always playing, volume controlled)
local CurrentNormalTrack = nil
local CurrentIntenseTrack = nil
local CurrentEventSound = nil

-- Event state
local IsEventMusicActive = false
local PausedIsPlaying = nil -- Remember zone state during events

-- Active tweens tracking (so we can cancel them)
local ActiveTweens = {}

-- SoundGroups for volume control
local MusicSoundGroup = nil
local SFXSoundGroup = nil

local Module = {}

-- Crossfade duration (1 second for quick response)
local CROSSFADE_DURATION = 1

-- Music volume settings
local MUSIC_VOLUME = 0.6 -- Louder (0.1 = quiet, 1 = max)

-- Store volume settings to apply when SoundGroups are loaded
local PendingMusicVolume = true
local PendingSFXVolume = true

-- Event-specific volume settings
local EVENT_VOLUMES = {
	DiscoEvent = 0.7, -- Louder for disco events
	BombardiroCrocodilo = 1,
	MrInspectorBee = 0.5,
	RainEvent = 0.8, -- Rainstorm event music
	ArcadeEvent = 0.7, -- Arcade event music (a bit louder)
	MeteorEvent = 0.7, -- Meteor Shower event music
	PiggyEvent = 0.7, -- Piggy event music
	default = 0.4 -- Default event volume
}

-- Initialize the music system
function Module:Init()
	-- Prevent multiple initializations (set flag immediately)
	if MusicLoaded or #MusicTracks > 0 then
		return
	end
	
	-- Set flag immediately to prevent race conditions
	MusicLoaded = true
	
	-- Wait for SoundGroups from ReplicatedStorage
	local SoundGroupsFolder = ReplicatedStorage:WaitForChild("SoundGroups", 10)
	if SoundGroupsFolder then
		MusicSoundGroup = SoundGroupsFolder:WaitForChild("Music", 30)
		SFXSoundGroup = SoundGroupsFolder:WaitForChild("SFX", 30)
	end
	
	-- Apply any pending volume settings now that SoundGroups are loaded
	if MusicSoundGroup and PendingMusicVolume ~= nil then
		MusicSoundGroup.Volume = PendingMusicVolume and 1 or 0
		PendingMusicVolume = nil
	end
	
	if SFXSoundGroup and PendingSFXVolume ~= nil then
		SFXSoundGroup.Volume = PendingSFXVolume and 1 or 0
		PendingSFXVolume = nil
	end
	
	-- Wait for Shared_Sounds to be available
	local Shared_Sounds = require(ReplicatedStorage.Modules.Settings.Shared_Sounds)
	
	-- Create sound objects for normal music tracks (safe zone)
	if Shared_Sounds.Music and #Shared_Sounds.Music > 0 then
		-- For now, just use the first track (single soundtrack)
		local sound = Instance.new("Sound")
		sound.SoundId = Shared_Sounds.Music[1]
		sound.Name = "NormalMusic"
		sound.Volume = MUSIC_VOLUME -- Start audible (spawn in safe zone)
		sound.Looped = true
		if MusicSoundGroup then
			sound.SoundGroup = MusicSoundGroup
		end
		sound.Parent = script
		
		CurrentNormalTrack = sound
	end
	
	-- Create sound objects for intense music tracks (play zone)
	if Shared_Sounds.IntenseMusic and #Shared_Sounds.IntenseMusic > 0 then
		-- For now, just use the first track (single soundtrack)
		local sound = Instance.new("Sound")
		sound.SoundId = Shared_Sounds.IntenseMusic[1]
		sound.Name = "IntenseMusic"
		sound.Volume = 0 -- Start muted (spawn in safe zone)
		sound.Looped = true
		if MusicSoundGroup then
			sound.SoundGroup = MusicSoundGroup
		end
		sound.Parent = script
		
		CurrentIntenseTrack = sound
	end
	
	-- Create sound objects for event music tracks
	if Shared_Sounds.EventMusics then
		for eventName, musicId in pairs(Shared_Sounds.EventMusics) do
			local sound = Instance.new("Sound")
			sound.SoundId = musicId
			sound.Name = eventName
			sound.Volume = EVENT_VOLUMES[eventName] or EVENT_VOLUMES.default
			sound.Looped = true -- Event music loops
			if MusicSoundGroup then
				sound.SoundGroup = MusicSoundGroup
			end
			sound.Parent = script
			
			EventMusicTracks[eventName] = sound
		end
	end
	
	-- Set up SFX sounds
	for Name, Sound in pairs(Shared_Sounds.SFX) do
		-- Handle arrays of sounds (for playing multiple simultaneously)
		if type(Sound) == "table" then
			-- Create a folder to hold multiple sounds
			local SoundFolder = Instance.new("Folder")
			SoundFolder.Name = Name
			SoundFolder.Parent = script
			
			for i, soundId in ipairs(Sound) do
				local Sounding = Instance.new("Sound")
				Sounding.SoundId = soundId
				Sounding.Name = Name .. "_" .. i
				if SFXSoundGroup then
					Sounding.SoundGroup = SFXSoundGroup
				end
				Sounding.Parent = SoundFolder
				self:AddCompressor(Sounding)
			end
		else
			-- Single sound (original behavior)
			local Sounding = Instance.new("Sound")
			Sounding.SoundId = Sound
			Sounding.Name = Name
			if SFXSoundGroup then
				Sounding.SoundGroup = SFXSoundGroup
			end
			Sounding.Parent = script
			self:AddCompressor(Sounding)
		end
	end
	
	-- Connect to MusicEvent for event music control
	local MusicEvent = ReplicatedStorage:WaitForChild("Events", 10):WaitForChild("MusicEvent", 10)
	if MusicEvent then
		MusicEvent.OnClientEvent:Connect(function(action, eventName)
			if action == "StartEventMusic" then
				Module:StartEventMusic(eventName)
			elseif action == "StopEventMusic" then
				Module:StopEventMusic()
			elseif action == "StopNormalMusic" then
				Module:PauseZoneMusic()
			end
		end)
	end
	
	-- Connect to Sound/PlaySound for server-triggered SFX (e.g. laser kill, collect)
	local EventsFolder = ReplicatedStorage:FindFirstChild("Events")
	local soundEvent = EventsFolder and (EventsFolder:FindFirstChild("Sound") or EventsFolder:FindFirstChild("PlaySound"))
	if soundEvent then
		soundEvent.OnClientEvent:Connect(function(soundName)
			if not soundName or type(soundName) ~= "string" then return end
			local soundId = Shared_Sounds.SFX and Shared_Sounds.SFX[soundName]
			if type(soundId) == "table" then
				soundId = soundId[1]
			end
			if type(soundId) == "string" then
				local sound = Instance.new("Sound")
				sound.SoundId = soundId
				sound.Volume = 1
				if SFXSoundGroup then
					sound.SoundGroup = SFXSoundGroup
				end
				sound.Parent = script
				sound:Play()
				sound.Ended:Connect(function()
					sound:Destroy()
				end)
			end
		end)
	end
	
	-- Start both music tracks playing simultaneously (unless event is active)
	task.spawn(function()
		-- Small delay to ensure server has sent event music if active
		task.wait(0.5)
		
		-- Check if an event is active via ReplicatedStorage attribute
		local activeEvent = ReplicatedStorage:GetAttribute("ActiveEvent")
		local activeEventMusic = ReplicatedStorage:GetAttribute("ActiveEventMusic")
		
		if activeEvent and activeEventMusic then
			-- Event is active, start event music only
			Module:StartEventMusic(activeEventMusic)
		elseif MusicEnabled and not IsEventMusicActive then
			-- No event and no event music already playing, start normal zone music
			if CurrentNormalTrack then
				CurrentNormalTrack:Play()
			end
			if CurrentIntenseTrack then
				CurrentIntenseTrack:Play()
			end
		end
	end)
end

--[[
	Fade to normal music (safe zone)
	Mutes intense music, unmutes normal music
]]
function Module:FadeToNormalMusic()
	if not MusicLoaded or not MusicEnabled then
		return
	end
	
	-- Block during events (double check both flag and attribute)
	if IsEventMusicActive then
		return
	end
	local activeEvent = ReplicatedStorage:GetAttribute("ActiveEvent")
	if activeEvent then
		return
	end
	
	self:CancelTweensForSound(CurrentNormalTrack)
	self:CancelTweensForSound(CurrentIntenseTrack)
	
	if CurrentNormalTrack then
		CurrentNormalTrack.TimePosition = 0
		self:FadeVolume(CurrentNormalTrack, MUSIC_VOLUME)
	end
	if CurrentIntenseTrack then
		self:FadeVolume(CurrentIntenseTrack, 0)
	end
end

--[[
	Fade to intense music (play zone)
	Mutes intense music, unmutes normal music
]]
function Module:FadeToIntenseMusic()
	if not MusicLoaded or not MusicEnabled then
		return
	end
	
	-- Block during events (double check both flag and attribute)
	if IsEventMusicActive then
		return
	end
	local activeEvent = ReplicatedStorage:GetAttribute("ActiveEvent")
	if activeEvent then
		return
	end
	
	self:CancelTweensForSound(CurrentNormalTrack)
	self:CancelTweensForSound(CurrentIntenseTrack)
	
	if CurrentNormalTrack then
		self:FadeVolume(CurrentNormalTrack, 0)
	end
	if CurrentIntenseTrack then
		CurrentIntenseTrack.TimePosition = 0
		self:FadeVolume(CurrentIntenseTrack, MUSIC_VOLUME)
	end
end

--[[
	Fade a sound's volume to target value
]]
function Module:FadeVolume(sound, targetVolume)
	if not sound then return end
	
	local fadeInfo = TweenInfo.new(
		CROSSFADE_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.InOut
	)
	
	local fadeTween = TweenService:Create(sound, fadeInfo, {Volume = targetVolume})
	
	-- Track this tween
	table.insert(ActiveTweens, {sound = sound, tween = fadeTween})
	
	fadeTween:Play()
	
	-- Remove from active tweens when completed
	fadeTween.Completed:Connect(function()
		for i = #ActiveTweens, 1, -1 do
			if ActiveTweens[i].tween == fadeTween then
				table.remove(ActiveTweens, i)
				break
			end
		end
	end)
end

--[[
	Cancel all tweens for a specific sound
]]
function Module:CancelTweensForSound(sound)
	if not sound then return end
	
	for i = #ActiveTweens, 1, -1 do
		local tweenData = ActiveTweens[i]
		if tweenData.sound == sound then
			tweenData.tween:Cancel()
			table.remove(ActiveTweens, i)
		end
	end
end

-- Legacy compatibility (deprecated, but kept for now)
function Module:StartNormalMusic()
	self:FadeToNormalMusic()
end

function Module:StartIntenseMusic()
	self:FadeToIntenseMusic()
end

function Module:StopIntenseMusic()
	self:FadeToNormalMusic()
end

function Module:StopCurrentMusic()
	-- Stop both tracks if needed
	if CurrentNormalTrack then
		CurrentNormalTrack:Stop()
	end
	if CurrentIntenseTrack then
		CurrentIntenseTrack:Stop()
	end
end

-- Enable/disable music (from settings)
function Module:EnableMusic(Value)
	MusicEnabled = Value
	
	-- Control music volume through SoundGroup
	if MusicSoundGroup then
		MusicSoundGroup.Volume = Value and 1 or 0
		PendingMusicVolume = nil
	else
		PendingMusicVolume = Value
	end
	
	if Value then
		-- Music enabled - check if event is active first
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local activeEvent = ReplicatedStorage:GetAttribute("ActiveEvent")
		local activeEventMusic = ReplicatedStorage:GetAttribute("ActiveEventMusic")
		
		if activeEvent and activeEventMusic then
			-- Event is active, start event music only
			task.wait(0.5)
			Module:StartEventMusic(activeEventMusic)
		elseif not CurrentNormalTrack or not CurrentNormalTrack.IsPlaying then
			-- No event, restart zone music
			task.wait(0.5)
			if CurrentNormalTrack then CurrentNormalTrack:Play() end
			if CurrentIntenseTrack then CurrentIntenseTrack:Play() end
		end
	end
end

-- Enable/disable sounds
function Module:EnableSounds(Value)
	-- Control SFX volume through SoundGroup
	if SFXSoundGroup then
		SFXSoundGroup.Volume = Value and 1 or 0
		PendingSFXVolume = nil
	else
		PendingSFXVolume = Value
	end
end

-- Play SFX sound
function Module:Play(Name, pitch)
	local soundTarget = script:FindFirstChild(Name)
	if not MusicLoaded or not soundTarget then
		return
	end
	
	-- Check if it's a folder (multiple sounds to play simultaneously)
	if soundTarget:IsA("Folder") then
		-- Play all sounds in the folder simultaneously
		for _, sound in ipairs(soundTarget:GetChildren()) do
			if sound:IsA("Sound") then
				-- Apply pitch variation if provided
				if pitch and type(pitch) == "number" then
					sound.PlaybackSpeed = pitch
				else
					sound.PlaybackSpeed = 1  -- Reset to normal pitch
				end
				sound:Play()
			end
		end
	elseif soundTarget:IsA("Sound") then
		-- Single sound (original behavior)
		-- Apply pitch variation if provided
		if pitch and type(pitch) == "number" then
			soundTarget.PlaybackSpeed = pitch
		else
			soundTarget.PlaybackSpeed = 1  -- Reset to normal pitch
		end
		soundTarget:Play()
	end
end

-- Add compressor to sound
function Module:AddCompressor(Sound)
	local Compressor = Instance.new("CompressorSoundEffect")
	Compressor.Name = "AutoCompressor"
	Compressor.Threshold = -12
	Compressor.Ratio = 6
	Compressor.Attack = 0.05
	Compressor.Release = 0.2
	Compressor.GainMakeup = 3
	Compressor.Enabled = true
	Compressor.Parent = Sound
end

-- Get SoundGroups for other scripts
function Module:GetMusicSoundGroup()
	return MusicSoundGroup
end

function Module:GetSFXSoundGroup()
	return SFXSoundGroup
end

-- Wait for SoundGroups (uses WaitForChild; use when groups may not be loaded yet)
function Module:WaitForMusicSoundGroup()
	if MusicSoundGroup then
		return MusicSoundGroup
	end
	local SoundGroupsFolder = ReplicatedStorage:WaitForChild("SoundGroups", 10)
	if SoundGroupsFolder then
		MusicSoundGroup = SoundGroupsFolder:WaitForChild("Music", 30)
		if MusicSoundGroup and PendingMusicVolume ~= nil then
			MusicSoundGroup.Volume = PendingMusicVolume and 1 or 0
			PendingMusicVolume = nil
		end
		return MusicSoundGroup
	end
	return nil
end

function Module:WaitForSFXSoundGroup()
	if SFXSoundGroup then
		return SFXSoundGroup
	end
	local SoundGroupsFolder = ReplicatedStorage:WaitForChild("SoundGroups", 10)
	if SoundGroupsFolder then
		SFXSoundGroup = SoundGroupsFolder:WaitForChild("SFX", 30)
		if SFXSoundGroup and PendingSFXVolume ~= nil then
			SFXSoundGroup.Volume = PendingSFXVolume and 1 or 0
			PendingSFXVolume = nil
		end
		return SFXSoundGroup
	end
	return nil
end

-- Set SoundGroup for a sound (helper for other scripts like WeatherHandler)
function Module:SetGroup(sound, groupType)
	if sound and sound:IsA("Sound") then
		if groupType == "Music" and MusicSoundGroup then
			sound.SoundGroup = MusicSoundGroup
		elseif groupType == "SFX" and SFXSoundGroup then
			sound.SoundGroup = SFXSoundGroup
		end
	end
end

--[[
	Pause zone music system (fade out both tracks)
	Called when event starts
]]
function Module:PauseZoneMusic()
	if not MusicLoaded then
		return
	end
	
	-- Remember current zone state
	PausedIsPlaying = Player:GetAttribute("IsPlaying")
	
	-- Fade out both tracks
	self:CancelTweensForSound(CurrentNormalTrack)
	self:CancelTweensForSound(CurrentIntenseTrack)
	
	if CurrentNormalTrack then
		self:FadeVolume(CurrentNormalTrack, 0)
	end
	if CurrentIntenseTrack then
		self:FadeVolume(CurrentIntenseTrack, 0)
	end
end

--[[
	Start event music
	Pauses zone music and plays event-specific music
]]
function Module:StartEventMusic(eventName)
	if not MusicLoaded then
		return
	end
	
	local eventSound = EventMusicTracks[eventName]
	if not eventSound then
		warn("Event music not found:", eventName)
		return
	end
	
	-- Set event music active flag FIRST
	IsEventMusicActive = true
	CurrentEventSound = eventSound
	
	-- Cancel any ongoing zone music tweens immediately
	self:CancelTweensForSound(CurrentNormalTrack)
	self:CancelTweensForSound(CurrentIntenseTrack)
	
	-- Immediately mute zone music
	if CurrentNormalTrack then
		CurrentNormalTrack.Volume = 0
	end
	if CurrentIntenseTrack then
		CurrentIntenseTrack.Volume = 0
	end
	
	-- Set event-specific volume
	local eventVolume = EVENT_VOLUMES[eventName] or EVENT_VOLUMES.default
	eventSound.Volume = 0
	eventSound.TimePosition = 0

	-- Start event music with fade in
	eventSound:Play()
	self:FadeVolume(eventSound, eventVolume)
end

--[[
	Stop event music and resume zone music
]]
function Module:StopEventMusic()
	if not IsEventMusicActive or not CurrentEventSound then
		return
	end
	
	-- Fade out event music
	self:FadeVolume(CurrentEventSound, 0)
	
	-- Wait for fade to complete, then stop
	task.delay(CROSSFADE_DURATION, function()
		if CurrentEventSound then
			CurrentEventSound:Stop()
			CurrentEventSound = nil
		end
		IsEventMusicActive = false
		
		-- Resume zone music based on saved state
		self:ResumeZoneMusic()
	end)
end

--[[
	Resume zone music after event ends
	Restores music based on CURRENT zone state (not saved state)
]]
function Module:ResumeZoneMusic()
	if not MusicLoaded or IsEventMusicActive or not MusicEnabled then
		return
	end
	
	-- Check CURRENT zone state (player may have moved during event)
	local currentIsPlaying = Player:GetAttribute("IsPlaying")
	
	-- Start the music tracks if they're not already playing (for players who joined during event)
	if CurrentNormalTrack and not CurrentNormalTrack.IsPlaying then
		CurrentNormalTrack:Play()
	end
	if CurrentIntenseTrack and not CurrentIntenseTrack.IsPlaying then
		CurrentIntenseTrack:Play()
	end
	
	if currentIsPlaying then
		-- Currently in play zone - play intense music
		self:FadeToIntenseMusic()
	else
		-- Currently in safe zone - play normal music
		self:FadeToNormalMusic()
	end
	
	PausedIsPlaying = nil
end

return Module
