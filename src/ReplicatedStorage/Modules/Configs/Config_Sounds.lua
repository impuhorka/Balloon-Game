--// Shared_Sounds - All sound IDs and properties for the game
--// Used by both client and server for consistent sound configuration

return {
	-- Background Music (plays in safe zone - relaxed/chill)
	Music = {
		"rbxassetid://1843536398", -- Safe zone / relaxing music
	},
	
	-- Intense Music (plays in play zone - danger/intense)
	IntenseMusic = {
		"rbxassetid://1848051688", -- Intense track 1
		-- Add more intense music IDs here
	},
	
	-- Event Music (loops during special events)
	EventMusics = {
		RainEvent = "rbxassetid://138783027059661"; --"rbxassetid://95252304566935",
		ArcadeEvent = "rbxassetid://122415785858033", --"rbxassetid://122415785858033",
		MeteorEvent = "rbxassetid://105100211445392",
		PiggyEvent = "rbxassetid://1842247264",
	},
	
	-- SFX (Sound Effects)
	SFX = {
		-- Red Light / Green Light (non-positional, plays like music)
		Red = "rbxassetid://104263753081697",
		Green = "rbxassetid://133294004821345",
		
		-- UI Interaction sounds (from SingingX)
		["Button Press"] = "rbxassetid://99522017054363",
		["Button Release"] = "rbxassetid://99097729413607",
		["Mouse Enter"] = "rbxassetid://105792939878458",
		["Mouse Leave"] = "rbxassetid://105087835192081",
		["Frame Open"] = "rbxassetid://85211163592424",
		["Frame Exit"] = "rbxassetid://119140050789516",
		
		-- Popup / notification feedback
		Success = "rbxassetid://126808324",
		NotError = "rbxassetid://1169806635",
		Error = "rbxassetid://2130284653",
		Announcement = "rbxassetid://17582299860",
		Notification = "rbxassetid://135332060951290",
		Reward = "rbxassetid://107432620533625",
		Achievement = "rbxassetid://97112918938326",
		AchievementClaimed = "rbxassetid://121684497225674",
		["Arcade Ticket Pickup"] = "rbxassetid://133887853988893", -- Popup sound when picking up +1 Arcade Ticket
		Typewriter = "rbxassetid://95765810738510", -- Tutorial typewriter effect
		
		-- Gameplay sounds (from SingingX)
		Purchase = "rbxassetid://131886985",
		["Coins Flying"] = "rbxassetid://607662191",
		["Coin Collect"] = "rbxassetid://359623376",
		["Coin Pop"] = "rbxassetid://120588150624601",
		["Item Equip"] = "rbxassetid://138097048",
		Equip = "rbxassetid://120702574345603",
		Unequip = "rbxassetid://110683413889552",
		
		-- Hatching / Roll sounds
		Hatching = "rbxassetid://5485378340",
		RollSound = "rbxassetid://11225969341",
		WheelTick = "rbxassetid://70482547486758",
		WheelWin = "rbxassetid://70771680624636",
		ArcadeWheelTick = "rbxassetid://135770589782617", -- Retro tick for arcade icon change
		ArcadeWheelWin = "rbxassetid://73860614982546",   -- Arcade final reward
		ArcadeLeverPull = "rbxassetid://114145290691421",  -- Lever pull sound on activation "rbxassetid://137834227040330"
		SpinSound = "rbxassetid://9125806414",
		BeamSound = "rbxassetid://75213214992269",
		Destroy = "rbxassetid://89152209444632",
		HatchFinal = "rbxassetid://12053149329",
		["Egg Hatch"] = "rbxassetid://126176680297971",
		["Egg Stolen"] = "rbxassetid://129539546618462",
		MysteryEgg = "rbxassetid://89172835847101",
		["Lucky Block Explosion"] = "rbxassetid://114518565533265",
		["Lucky Block Wiggle"] = "rbxassetid://123604431530885",
		
		-- Event sounds
		Confetti = "rbxassetid://7933571710",
		Siren = "rbxassetid://119722238859453",
		["Rocket Pickup"] = "rbxassetid://94772689859736",
		["Laser Kill"] = "rbxassetid://129285831966291", -- Arcade event laser death
		
		-- Combat sounds
		["Swatter Swing"] = "rbxassetid://80572912319394",
		["Swatter Swing2"] = "rbxassetid://80542976063121",
		Thunder = "rbxassetid://101420506992565",
		Thunder2 = "rbxassetid://18456252953",
		ThunderBolt = "rbxassetid://127625722966323",
		ShinyStar = "rbxassetid://133987056062707",
		SpookyUpgrade = "rbxassetid://77989786974029",
		
		-- Inspector grade sounds
		Grade1 = "rbxassetid://102374335087970",
		Grade2 = "rbxassetid://112327884832949",
		Grade3 = "rbxassetid://89547025188852",
		Grade4 = "rbxassetid://102478761566180",
		
		["Loading Flash"] = "rbxassetid://93843602064010",
		
		-- Weather sounds
		Rain = "rbxassetid://7127218501",
		
		-- Bee system sounds
		["Flower Locate"] = "rbxassetid://130006091841462",
		["Bee Restock"] = "rbxassetid://102156065709489",
		["Bee Restock Rare"] = "rbxassetid://83415794693081",
		
		-- Delivery system sounds
		["New Delivery"] = "rbxassetid://131132395684284",
		
		-- Brainrot collection sound
		["Brainrot Collection"] = "rbxassetid://79202498901673", --"rbxassetid://113633449245781",
		
		-- Celestial spawn sound
		["Celestial Spawn"] = "rbxassetid://124987759667155",
		
		-- Divine spawn sounds (plays both simultaneously)
		["Divine Spawn"] = {
			"rbxassetid://90338020869315",
			"rbxassetid://140719451384164",
		},
	},
}
