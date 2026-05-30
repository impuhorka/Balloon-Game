local Players = game:GetService("Players")

local Server_CharacterStats = {}

local DEFAULT_WALK_SPEED = game.StarterPlayer.CharacterWalkSpeed
local DEFAULT_JUMP_POWER = game.StarterPlayer.CharacterJumpPower

function Server_CharacterStats:UpdateCharacterSpeed(player: Player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid.WalkSpeed = DEFAULT_WALK_SPEED
	humanoid.JumpPower = DEFAULT_JUMP_POWER
end

function Server_CharacterStats:UpdateOverheadDisplay(_player: Player)
	return
end

function Server_CharacterStats:ApplyStats(player: Player)
	self:UpdateCharacterSpeed(player)
	self:UpdateOverheadDisplay(player)
end

function Server_CharacterStats:Init()
	for _, player in ipairs(Players:GetPlayers()) do
		self:ApplyStats(player)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			self:ApplyStats(player)
		end)
	end)
end

return Server_CharacterStats
