return {
	IdleSeconds = 5,
	ActiveSeconds = 5,
	SpinUpSeconds = 1.25,
	SpinDownSeconds = 1.25,
	SpeedDegrees = 720,

	ZoneRadius = 40,
	ZoneMaxHeightAbove = 75,
	ManualFloatMult = 1,
	ZoneAutoFloatMult = 7 / 5 * 1.25,
	ZoneComboHalfMult = (7 / 2) / 5 * 1.25,
	ZoneFadeInSeconds = 0.7,
	ZoneFadeOutSeconds = 1.1,

	Units = {
		{
			RootPath = { "Game", "BigPropeler" },
			ModelName = "PropelerModel",
			EffectsPartName = "Effects",
		},
	},
}
