local Shared_RebirthRewards = {}

Shared_RebirthRewards.Rewards = {}

function Shared_RebirthRewards:GetRewardForLevel(level: number)
	return self.Rewards[level] or {
		Cash = 0,
		Slots = 0,
		Carry = 0,
		Floor = 0,
	}
end

function Shared_RebirthRewards:GetTotalReward(rebirths: number, rewardName: string)
	local total = 0
	for level = 1, math.max(rebirths or 0, 0) do
		local reward = self:GetRewardForLevel(level)
		total += reward[rewardName] or 0
	end
	return total
end

function Shared_RebirthRewards:GetTotalSlots(rebirths: number, baseSlots: number)
	return (baseSlots or 0) + self:GetTotalReward(rebirths or 0, "Slots")
end

function Shared_RebirthRewards:GetCashMultiplier(rebirths: number)
	local bonusPercent = self:GetTotalReward(rebirths or 0, "Cash")
	return 1 + (bonusPercent / 100)
end

return Shared_RebirthRewards
