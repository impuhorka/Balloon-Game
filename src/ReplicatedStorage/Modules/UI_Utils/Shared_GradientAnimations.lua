--// Shared_GradientAnimations - Reusable UIGradient animation calculations
--// Provides gradient keypoint calculations for Rainbow, Golden, and other animated effects

local Module = {}

-- Rainbow gradient settings
local RAINBOW_SPEED = 0.5  -- Speed of color cycling (slightly faster)
local RAINBOW_SATURATION = 1.0  -- Full saturation for vibrant colors
local RAINBOW_VALUE = 1.0  -- Full brightness

-- Golden gradient settings
local GOLDEN_SPEED = 0.15  -- Slightly slower for golden effect

--[[
	Calculate rainbow gradient with breathing transparency
	@param time - Current animation time (accumulated deltaTime)
	@param phaseOffset - Random offset for variety (0-1)
	@return keypoints (ColorSequenceKeypoint array), offset (number), transparency (NumberSequence)
]]
function Module:CalculateRainbowGradient(time: number, phaseOffset: number)
	local loop = ((time + phaseOffset) * RAINBOW_SPEED) % 1  -- 0 to 1 cycle
	local range = 6  -- Fewer keypoints = more zoomed in colors
	
	local keypoints = {}
	for i = 1, range + 1 do
		-- Calculate hue with seamless continuous flow (reduced multiplier for zoom)
		local hue = loop - ((i - 1) / range) * 0.8
		local color = Color3.fromHSV(hue % 1, RAINBOW_SATURATION, RAINBOW_VALUE)
		local position = (i - 1) / range
		table.insert(keypoints, ColorSequenceKeypoint.new(position, color))
	end
	
	-- Breathing transparency effect (slow sine wave)
	local breathCycle = math.sin(time * 0.8) * 0.25 + 0.75  -- 0.5 to 1.0
	local transparency = 1 - breathCycle  -- 0 to 0.5 transparency
	local transparencySeq = NumberSequence.new(transparency)
	
	return keypoints, 0, transparencySeq  -- No offset needed, return transparency
end

--[[
	Calculate golden gradient keypoints (Yellow to Yellow-Orange cycling)
	@param time - Current animation time (accumulated deltaTime)
	@param phaseOffset - Random offset for variety (0-1)
	@return keypoints (ColorSequenceKeypoint array), offset (number)
]]
function Module:CalculateGoldenGradient(time: number, phaseOffset: number)
	local loop = ((time + phaseOffset) * GOLDEN_SPEED) % 1  -- 0 to 1 cycle
	local range = 3  -- Simple gradient, fewer keypoints
	
	-- Golden color palette: Yellow (#FFD700) to Yellow-Orange (#FFAA00)
	local goldenColors = {
		Color3.fromRGB(255, 215, 0),   -- Gold
		Color3.fromRGB(255, 170, 0),   -- Yellow-Orange
		Color3.fromRGB(255, 215, 0),   -- Gold (loop back)
	}
	
	local keypoints = {}
	for i = 1, range + 1 do
		local colorIndex = ((loop + (i - 1) / range) % 1) * (#goldenColors - 1) + 1
		local lowerIndex = math.floor(colorIndex)
		local upperIndex = math.ceil(colorIndex)
		local t = colorIndex - lowerIndex
		
		if upperIndex > #goldenColors then upperIndex = 1 end
		
		local color = goldenColors[lowerIndex]:Lerp(goldenColors[upperIndex], t)
		local position = (i - 1) / range
		table.insert(keypoints, ColorSequenceKeypoint.new(position, color))
	end
	
	return keypoints, 0  -- No offset needed
end

-- Default shine band width (0–1): fraction of the gradient that is the bright band. 0.1 = thin, 0.3 = wide.
local SHINE_BAND_WIDTH_DEFAULT = 0.22

--[[
	Get white shine effect sequences (like SingingX ForeverPack shine)
	Returns transparency and color sequences for a white light sweep effect.
	@param bandWidth number? - Optional. 0–1, fraction of gradient that is the bright band (default 0.22). Larger = wider shine.
	@return transparencySequence (NumberSequence), colorSequence (ColorSequence)
]]
function Module:GetShineSequences(bandWidth: number?)
	local width = bandWidth
	if width == nil or width <= 0 or width > 1 then
		width = SHINE_BAND_WIDTH_DEFAULT
	end
	local left = 0.5 - width / 2
	local right = 0.5 + width / 2

	-- Full white color for the entire gradient
	local whiteColor = Color3.fromRGB(255, 255, 255)
	local colorSequence = ColorSequence.new(whiteColor, whiteColor)

	-- Transparency: edges fully transparent, band in center is less transparent (the shine line)
	local transparencySequence = NumberSequence.new{
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(left, 0.5),
		NumberSequenceKeypoint.new(right, 0.5),
		NumberSequenceKeypoint.new(1, 1)
	}

	return transparencySequence, colorSequence
end

--[[
	Get shine tween info (for offset animation sweep)
	@return TweenInfo for shine offset animation
]]
function Module:GetShineTweenInfo()
	return TweenInfo.new(
		1.5,  -- Duration
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
end

--[[
	Get recommended update interval for gradient animations (30fps to save frames)
	@return interval in seconds (1/30)
]]
function Module:GetUpdateInterval(): number
	return 1/30
end

return Module
