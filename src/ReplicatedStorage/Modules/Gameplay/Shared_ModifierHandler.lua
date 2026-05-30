--[[
	Shared_ModifierHandler
	
	Brainrot modifier visuals: we always use the Normal model and apply modifier
	appearance (TextureID, Color, Material) from modifier templates (Golden, Diamond, etc.).
	This avoids cloning full meshes per modifier and lets Index UI swap visuals without
	reloading viewport models.
	
	Asset expectation:
	- Assets.Brainrots[configName].Normal = full model (clone this).
	- Assets.Brainrots[configName].Golden, .Diamond, .Lava, .Galaxy, etc. = same hierarchy
	  as Normal, used only as visual reference (TextureID, Color, Material copied onto Normal clone).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModifierHandler = {}

-- Cache Assets folder
local function getBrainrotParent(configName)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local brainrots = assets and assets:FindFirstChild("Brainrots")
	return brainrots and brainrots:FindFirstChild(configName)
end

--[[
	Copy visual properties from source part to target part (same hierarchy / match by name).
	Copy: TextureID, Color, Material. Only copies if source has a part (BasePart).
]]
local function copyPartVisuals(sourcePart, targetPart)
	if not sourcePart or not sourcePart:IsA("BasePart") then return end
	if not targetPart or not targetPart:IsA("BasePart") then return end
	targetPart.TextureID = sourcePart.TextureID
	targetPart.Color = sourcePart.Color
	targetPart.Material = sourcePart.Material
end

--[[
	Apply modifier visuals to an existing model in-place.
	For each BasePart in the modifier template, find the part by name in the model
	and copy TextureID, Color, Material. Used by Index UI to switch modifier without
	reloading the viewport model. When modifier is "Normal", we copy from the Normal
	template so switching back from Golden/Diamond etc. restores Normal textures.
	@param model Model - Existing model (e.g. clone of Normal)
	@param configName string
	@param modifier string - "Normal", "Golden", "Diamond", etc. = apply that template's visuals
]]
function ModifierHandler:ApplyModifierToModel(model, configName, modifier)
	if not model then return end
	
	local brainrotParent = getBrainrotParent(configName)
	if not brainrotParent then return end
	
	-- Use Normal template when modifier is "Normal" or missing, so switching back resets textures
	local templateName = (modifier and modifier ~= "") and modifier or "Normal"
	local modifierTemplate = brainrotParent:FindFirstChild(templateName)
	if not modifierTemplate or not modifierTemplate:IsA("Model") then return end
	
	for _, sourcePart in ipairs(modifierTemplate:GetDescendants()) do
		if sourcePart:IsA("BasePart") then
			local targetPart = model:FindFirstChild(sourcePart.Name, true)
			if targetPart then
				copyPartVisuals(sourcePart, targetPart)
			end
		end
	end
end

--[[
	Attach modifier VFX to brainrot.
	- Rainbow: Welds VFX part AND adds animated SurfaceAppearance
	- Other modifiers: Welds VFX part from Assets.Modifiers
	@param brainrotModel Model - The brainrot model to attach VFX to
	@param modifier string - Modifier name ("Rainbow", "Diamond", "Lava", etc.)
]]
function ModifierHandler:AttachModifierVFX(brainrotModel, modifier)
	if not brainrotModel or not brainrotModel.PrimaryPart then return end
	if not modifier or modifier == "Normal" then return end
	
	-- Weld VFX part from Assets.Modifiers (for ALL modifiers including Rainbow)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local modifiers = assets and assets:FindFirstChild("Modifiers")
	local modifierVFX = modifiers and modifiers:FindFirstChild(modifier)
	
	if modifierVFX and modifierVFX:IsA("Model") and modifierVFX.PrimaryPart then
		local vfxPart = modifierVFX.PrimaryPart:Clone()
		vfxPart.Name = "ModifierVFX"
		vfxPart.CanCollide = false
		vfxPart.CanQuery = false
		
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = brainrotModel.PrimaryPart
		weld.Part1 = vfxPart
		weld.Parent = vfxPart
		
		vfxPart.CFrame = brainrotModel.PrimaryPart.CFrame
		vfxPart.Parent = brainrotModel
	end
	
	-- ADDITIONAL: Rainbow modifier gets animated SurfaceAppearance
	if modifier == "Rainbow" then
		local primaryPart = brainrotModel.PrimaryPart
		if not primaryPart:IsA("MeshPart") then return end
		
		-- Get the brainrot's config name from the model
		local configName = brainrotModel.Name
		
		-- Find the Rainbow variant's SurfaceAppearance
		local brainrotParent = getBrainrotParent(configName)
		if not brainrotParent then
			warn("⚠️ Brainrot parent not found for Rainbow modifier:", configName)
			return
		end
		
		local rainbowModel = brainrotParent:FindFirstChild("Rainbow")
		if not rainbowModel or not rainbowModel:IsA("Model") or not rainbowModel.PrimaryPart then
			warn("⚠️ Rainbow variant not found for:", configName)
			return
		end
		
		local rainbowSA = rainbowModel.PrimaryPart:FindFirstChildOfClass("SurfaceAppearance")
		if not rainbowSA then
			warn("⚠️ Rainbow variant has no SurfaceAppearance:", configName)
			return
		end
		
		-- Remove any existing SurfaceAppearance first
		local existingSA = primaryPart:FindFirstChildOfClass("SurfaceAppearance")
		if existingSA then
			existingSA:Destroy()
		end
		
		-- Clone the Rainbow variant's SurfaceAppearance
		local surfaceAppearance = rainbowSA:Clone()
		surfaceAppearance.Parent = primaryPart
		
		-- Tag for client animation
		local CollectionService = game:GetService("CollectionService")
		CollectionService:AddTag(surfaceAppearance, "Rainbow")
	end
end

--[[
	Get a brainrot model: clone Normal and apply modifier visuals.
	Use when you need a new instance (world spawn, plot slot, carried, viewport first load).
	@param configName string
	@param modifier string
	@return Model? - Clone of Normal with modifier visuals applied, or nil
]]
function ModifierHandler:GetBrainrotModel(configName, modifier)
	local brainrotParent = getBrainrotParent(configName)
	if not brainrotParent then return nil end
	
	local normalTemplate = brainrotParent:FindFirstChild("Normal")
	if not normalTemplate or not normalTemplate:IsA("Model") then
		return nil
	end
	
	local model = normalTemplate:Clone()
	model.Name = configName
	
	-- Apply modifier visuals (no-op if modifier == "Normal")
	self:ApplyModifierToModel(model, configName, modifier or "Normal")
	
	-- Attach 3D VFX effects for modifiers
	self:AttachModifierVFX(model, modifier or "Normal")
	
	return model
end

return ModifierHandler
