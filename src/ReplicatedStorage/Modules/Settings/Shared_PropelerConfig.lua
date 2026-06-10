return {
	IdleSeconds = 5,
	ActiveSeconds = 5,
	SpinUpSeconds = 1.25,
	SpinDownSeconds = 1.25,
	SpeedDegrees = 720,

	ZoneRadius = 40,
	ZoneMaxHeightAbove = 75,
	ManualFloatMult = 1,
	--[[ Scales normal balloon float speed (not a separate boost force). ]]
	ZoneAutoFloatMult = 2.08,
	--[[ Multiplies zone float when also holding jump (stacking boost). ]]
	ZoneManualHoldComboMult = 1.42,
	ZoneLiftCurvePower = 0.65,
	ZoneTargetVyBonusScale = 0.72,
	ZoneEntryLaunchVy = 32,
	ZoneFadeInSeconds = 0.16,
	ZoneFadeOutSeconds = 2.8,
	ZoneExitVyBleedRate = 11,
	ClientFovNarrow = 13,
	ClientFovNarrowInRate = 16,
	ClientFovNarrowOutRate = 4.5,
	ClientShakeIntensity = 0.14,
	ClientEntryShakeIntensity = 0.26,

	Units = {
		{
			RootPath = { "Game", "BigPropeler" },
			ModelName = "PropelerModel",
			EffectsPartName = "Effects",
		},
	},
}
