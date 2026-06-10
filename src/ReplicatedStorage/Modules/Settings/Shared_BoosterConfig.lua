return {
	RootPath = { "Game", "Boosters" },
	CirclePartName = "BoostCircle",

	CooldownSeconds = 1.4,
	GlobalCooldownSeconds = 0.35,

	OverlapExpand = Vector3.new(3, 6, 3),

	Normal = {
		VerticalLaunch = 54,
		MinVerticalSpeed = 42,
		HorizontalBoost = 16,
		FloatLiftMultBonus = 0.22,
		RiseCapBonus = 42,
		FovNarrow = 9,
	},
	VIP = {
		VerticalLaunch = 72,
		MinVerticalSpeed = 56,
		HorizontalBoost = 24,
		FloatLiftMultBonus = 0.32,
		RiseCapBonus = 58,
		FovNarrow = 13,
	},

	BlendFadeOutSeconds = 2.2,
	FovNarrowInRate = 16,
	FovNarrowOutRate = 4.5,
	FovNarrowMax = 24,
	MinMoveSpeedForDir = 2.5,
}
