--// BalloonRig — knot hub, HRP strap anchors (torso-equivalent world position), balloon rods/ropes on character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Modules.ItemConfigs.BalloonConfig)
local BalloonRigKit = require(script.Parent.BalloonRigKit)

local BalloonRig = {}
BalloonRig.__index = BalloonRig

--// Constants (shared with BalloonRigKit) --------------------------------------

BalloonRig.ATTACHED_BALLOONS_FOLDER = "AttachedBalloons"
BalloonRig.TORSO_SHARED_ATT_NAME = "BalloonTorsoStringAnchor"
BalloonRig.KNOT_PART_NAME = "BalloonStringKnot"
BalloonRig.KNOT_ATT_NAME = "BalloonKnotAnchor"
BalloonRig.KNOT_ATT_PREFIX = "BalloonKnotAnchor_"
BalloonRig.STRAP_NAME = "BalloonTorsoStrap"
BalloonRig.STRAP_ATT_PREFIX = "BalloonTorsoStrapAtt_"
BalloonRig.BALLOON_DOWN_ATT_NAME = Config.BalloonDownAttachmentName
BalloonRig.BALLOON_COLLISION_GROUP = Config.BalloonCollisionGroup
BalloonRig.SETTLING_ATTR = BalloonRigKit.SETTLING_ATTR

--// Construction ---------------------------------------------------------------

function BalloonRig.new(rigFolder: Folder?, character: Model, networkOwner: Player?)
	local owner = networkOwner
	if not owner and RunService:IsClient() then
		owner = Players.LocalPlayer
	end
	local self = setmetatable({
		_rigFolder = rigFolder,
		_character = character,
		_networkOwner = owner,
		_adopted = false,
		_lastConfigNames = nil :: { string }?,
		_balloonsFolder = nil :: Folder?,
		_hubAtt = nil :: Attachment?,
		_knotAtts = nil :: { Attachment }?,
		_torsoAtt = nil :: Attachment?,
		_knotPart = nil :: BasePart?,
		_spawnSettleUntil = nil :: number?,
		_pendingHubBalloonCount = nil :: number?,
	}, BalloonRig)
	return self
end

function BalloonRig.adoptFromCharacter(character: Model, networkOwner: Player?)
	local self = BalloonRig.new(nil, character, networkOwner)
	self._adopted = true
	self:_refreshAdoptedRefs()
	return self
end

function BalloonRig:_refreshAdoptedRefs()
	local ch = self._character
	if not ch then
		return
	end

	local folder = ch:FindFirstChild(BalloonRig.ATTACHED_BALLOONS_FOLDER)
	self._balloonsFolder = if folder and folder:IsA("Folder") then folder else nil

	local knot = ch:FindFirstChild(BalloonRig.KNOT_PART_NAME)
	self._knotPart = if knot and knot:IsA("BasePart") then knot else nil
	self._hubAtt = nil
	self._knotAtts = nil

	if self._knotPart then
		local atts: { Attachment } = {}
		for _, child in self._knotPart:GetChildren() do
			if child:IsA("Attachment") and BalloonRig.isKnotAttachmentName(child.Name) then
				table.insert(atts, child)
				if child.Name == BalloonRig.KNOT_ATT_NAME then
					self._hubAtt = child
				end
			end
		end
		if #atts > 0 then
			atts = self:_sortKnotAttachments(atts)
		end
		self._knotAtts = atts
		self._hubAtt = self._hubAtt or atts[1]
	end

	local host = self:_getHubHostPart()
	self._torsoAtt = nil
	if host then
		if not self._hubAtt then
			local hubAtt = host:FindFirstChild(BalloonRig.TORSO_SHARED_ATT_NAME)
			if hubAtt and hubAtt:IsA("Attachment") then
				self._hubAtt = hubAtt
			end
		end
		local strapAtt = host:FindFirstChild(BalloonRig.STRAP_ATT_PREFIX .. "1")
		if strapAtt and strapAtt:IsA("Attachment") then
			self._torsoAtt = strapAtt
		end
	end
end

function BalloonRig:Destroy()
	if self._adopted then
		self._rigFolder = nil
		self._character = nil
		self._balloonsFolder = nil
		self._hubAtt = nil
		self._knotAtts = nil
		self._torsoAtt = nil
		self._knotPart = nil
		self._lastConfigNames = nil
		return
	end

	self:Clear()
	if self._rigFolder then
		for _, child in self._rigFolder:GetChildren() do
			child:Destroy()
		end
	end
	self._rigFolder = nil
	self._character = nil
	self._lastConfigNames = nil
end

--// Public API (incremental) ---------------------------------------------------

function BalloonRig:_balloonModelCount(): number
	local folder = self._balloonsFolder
	if not folder then
		return 0
	end
	local n = 0
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			n += 1
		end
	end
	return n
end

function BalloonRig:_intendedBalloonCount(): number
	local pending = self._pendingHubBalloonCount
	if type(pending) == "number" and pending > 0 then
		return pending
	end
	return self:_balloonModelCount()
end

function BalloonRig:_shouldUseKnotHub(balloonCount: number?): boolean
	if not Config.flag("BalloonStringKnotEnabled") then
		return false
	end
	local count = balloonCount
	if count == nil then
		count = self:_intendedBalloonCount()
	end
	local minKnot = Config.number("BalloonKnotMinBalloonCount", 5)
	return count >= minKnot
end

function BalloonRig:_isUsingKnotHub(): boolean
	local knot = self._knotPart
	return knot ~= nil and knot.Parent ~= nil
end

function BalloonRig:_ensureHubForCount(balloonCount: number): Attachment
	self:_destroyLegacyWorkspaceAnchors()
	self._pendingHubBalloonCount = math.max(0, math.floor(balloonCount))

	local torso = self:_getTorsoReferencePart() or self:_getTorsoPart()
	local host = self:_getHubHostPart()
	local character = self._character
	if not torso or not host or not character then
		error("[BalloonRig] torso/hrp/character missing")
	end

	local off = BalloonRig.computeTorsoHubOffset(torso)
	local wantKnot = self:_shouldUseKnotHub(balloonCount)

	if wantKnot then
		if not self:_isUsingKnotHub() or not self._hubAtt then
			self:_destroyHub()
			return self:_ensureKnotHub(host, torso, character, off)
		end
		return self._hubAtt :: Attachment
	end

	self:_destroyHub()
	local host = self:_getHubHostPart()
	local torso = self:_getTorsoReferencePart() or self:_getTorsoPart()
	if not host or not torso then
		error("[BalloonRig] torso/hrp missing for torso hub")
	end
	BalloonRig._clearTorsoStrapsOnPart(host)
	return self:_createTorsoHubAttachment(host, torso, off)
end

function BalloonRig:_syncBalloonTethers(balloonModel: Model, balloonIndex: number)
	if not self._hubAtt then
		return
	end

	local downAtt = self:_findDownAttachment(balloonModel)
	if not downAtt then
		return
	end

	local rowIndex, slotInRow, rowDef = BalloonRig.resolveRow(balloonIndex)
	local rowBalloonCount = rowDef.count or 6
	local hubAtt = self:_getKnotAttForBalloon(rowIndex, slotInRow, rowBalloonCount) or self._hubAtt
	local rodLen = self:_rodLengthForIndex(balloonIndex, hubAtt, downAtt)
	local ropeLen = rodLen + Config.number("BalloonRopeLengthAboveRodStuds", 0.1)

	local rod: RodConstraint? = nil
	local rope: RopeConstraint? = nil
	for _, inst in balloonModel:GetDescendants() do
		if inst:IsA("RodConstraint") and inst.Name == "BalloonRod" then
			rod = inst
		elseif inst:IsA("RopeConstraint") and inst.Name == "BalloonRope" then
			rope = inst
		end
	end

	local function tetherBroken(c: Constraint?): boolean
		if not c or not c.Parent then
			return true
		end
		local a0 = c.Attachment0
		local a1 = c.Attachment1
		return not a0 or not a1 or not a0.Parent or not a1.Parent
	end

	local function ropeValid(r: RopeConstraint?): boolean
		if tetherBroken(r) then
			return false
		end
		return r.Attachment0 == hubAtt and r.Attachment1 == downAtt
	end

	if tetherBroken(rod) or not ropeValid(rope) then
		for _, inst in balloonModel:GetDescendants() do
			if inst:IsA("RodConstraint") and inst.Name == "BalloonRod" then
				inst:Destroy()
			elseif inst:IsA("RopeConstraint") and inst.Name == "BalloonRope" then
				inst:Destroy()
			end
		end
		self:_attachRodAndRope(downAtt, hubAtt, rodLen, ropeLen, rowIndex, slotInRow, rowBalloonCount, balloonIndex)
	else
		rod.Attachment0 = hubAtt
		rod.Length = rodLen
		rope.Attachment0 = hubAtt
		rope.Length = ropeLen
		rope.Visible = self:_ropeVisibleForBalloon(rowIndex, slotInRow, rowBalloonCount, balloonIndex)
	end

	self:_snapBalloonToRodRest(balloonModel, hubAtt, downAtt, rodLen)
	self:_zeroBalloonVelocities(balloonModel)
end

function BalloonRig:_reconnectAllBalloonHubs()
	local folder = self._balloonsFolder
	if not folder or not self._hubAtt then
		return
	end

	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end

		local balloonIndex = tonumber(child:GetAttribute("BalloonIndex"))
		if not balloonIndex then
			continue
		end

		self:_syncBalloonTethers(child, balloonIndex)
	end

	self:SyncRopeVisibility()
end

function BalloonRig:_clearHubIfEmpty()
	if self:_balloonModelCount() > 0 then
		return
	end
	self:_destroyHub()
end

function BalloonRig:CreateBalloon(configName: string, opts: { index: number? }?): Model?
	local torso = self:_getTorsoPart()
	if not torso or configName == "" then
		return nil
	end

	local index = (opts and opts.index) or (self:_balloonModelCount() + 1)
	local countBefore = self:_balloonModelCount()
	local hubChanging = self:_shouldUseKnotHub(countBefore) ~= self:_shouldUseKnotHub(index)

	self._balloonsFolder = self:_ensureBalloonsFolder()
	if hubChanging and countBefore > 0 then
		self:_swapHubForBalloonCount(index)
	else
		self._hubAtt = self:_ensureHubForCount(index)
	end

	local model = self:_installBalloon(configName, index)
	if model then
		if hubChanging then
			self:_finalizeRigAfterBuild()
		else
			self:_finalizeIncrementalAdd(index)
		end
	end
	return model
end

function BalloonRig:RemoveBalloon(key: string | number)
	local folder = self._balloonsFolder
	if not folder then
		return
	end

	local countBefore = self:_balloonModelCount()

	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local match = false
			if type(key) == "number" then
				match = child:GetAttribute("BalloonIndex") == key
			elseif type(key) == "string" then
				match = child:GetAttribute("BalloonConfigName") == key
			end
			if match then
				child:Destroy()
				break
			end
		end
	end

	local countAfter = self:_balloonModelCount()
	if countAfter == 0 then
		self:_clearHubIfEmpty()
	else
		local hubChanging = self:_shouldUseKnotHub(countBefore) ~= self:_shouldUseKnotHub(countAfter)
		if hubChanging then
			self:_swapHubForBalloonCount(countAfter)
			self:_finalizeRigAfterBuild()
		end
	end

	self:SyncRopeVisibility()
end

--// Public API (full sync from ownership list) ---------------------------------

function BalloonRig:Sync(configNames: { string })
	self:Clear()

	local torso = self:_getTorsoPart()
	if not torso then
		self._pendingHubBalloonCount = nil
		return
	end

	if #configNames == 0 then
		self._pendingHubBalloonCount = nil
		return
	end

	self._pendingHubBalloonCount = #configNames

	local host = self:_getHRP()
	local torsoRef = self:_getTorsoReferencePart() or host
	self._hubAtt = self:_ensureHubForCount(#configNames)
	self._balloonsFolder = self:_ensureBalloonsFolder()
	if host and torsoRef then
		self:_updateHubAnchorPositions(host, torsoRef)
		self:_repositionKnotToHost()
	end
	for index, configName in ipairs(configNames) do
		self:_installBalloon(configName, index)
	end
	self:SyncRopeVisibility()
	if self:_balloonModelCount() >= #configNames then
		self._lastConfigNames = table.clone(configNames)
	end
	self:_finalizeRigAfterBuild()
end

local function namesMatchPrefix(a: { string }, b: { string }, len: number): boolean
	for i = 1, len do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

function BalloonRig:applyConfigList(configNames: { string }): boolean
	if self._adopted then
		return false
	end

	local old = self._lastConfigNames or {}
	local oldCount = #old
	local newCount = #configNames

	if newCount == 0 then
		self:Clear()
		self._lastConfigNames = {}
		return true
	end

	if oldCount == 0 or self:_balloonModelCount() == 0 then
		self:Sync(configNames)
		return true
	end

	if newCount > oldCount and namesMatchPrefix(old, configNames, oldCount) then
		if self:_balloonModelCount() ~= oldCount then
			self:Sync(configNames)
			return true
		end
		for i = oldCount + 1, newCount do
			self:CreateBalloon(configNames[i], { index = i })
		end
		self._lastConfigNames = table.clone(configNames)
		return false
	end

	if newCount < oldCount and namesMatchPrefix(configNames, old, newCount) then
		local modelCount = self:_balloonModelCount()
		local hubChanging = self:_shouldUseKnotHub(oldCount) ~= self:_shouldUseKnotHub(newCount)
		if modelCount > newCount then
			for index = modelCount, newCount + 1, -1 do
				self:RemoveBalloon(index)
			end
		elseif hubChanging then
			self:swapHubForBalloonCount(newCount)
		end
		self._lastConfigNames = table.clone(configNames)
		return false
	end

	if newCount < oldCount then
		local modelCount = self:_balloonModelCount()
		local hubChanging = self:_shouldUseKnotHub(oldCount) ~= self:_shouldUseKnotHub(newCount)
		if hubChanging and modelCount == newCount and modelCount > 0 then
			self:swapHubForBalloonCount(newCount)
			self._lastConfigNames = table.clone(configNames)
			return false
		end
	end

	if oldCount == newCount and namesMatchPrefix(old, configNames, oldCount) then
		if self:_balloonModelCount() >= newCount then
			local wantKnot = self:_shouldUseKnotHub(newCount)
			if wantKnot ~= self:_isUsingKnotHub() then
				self:swapHubForBalloonCount(newCount)
			else
				self:SyncRopeVisibility()
			end
			return false
		end
	end

	self:Sync(configNames)
	return true
end

function BalloonRig:swapHubForBalloonCount(balloonCount: number)
	self:_swapHubForBalloonCount(balloonCount)
	self:_finalizeRigAfterBuild()
end

function BalloonRig:Clear()
	if self._adopted then
		self:_refreshAdoptedRefs()
		return
	end

	self:_destroyHub()
	if self._balloonsFolder then
		self._balloonsFolder:Destroy()
	end
	self._balloonsFolder = nil
	self._lastConfigNames = {}
end

--// Hub ------------------------------------------------------------------------

function BalloonRig:_getHRP(): BasePart?
	local ch = self._character
	if not ch then
		return nil
	end
	local hrp = ch:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

function BalloonRig:_getTorsoPart(): BasePart?
	local ch = self._character
	if not ch then
		return nil
	end
	local torso = ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	return self:_getHRP()
end

function BalloonRig:_getTorsoReferencePart(): BasePart?
	local ch = self._character
	if not ch then
		return nil
	end
	local torso = ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end
	return nil
end

function BalloonRig:_getHubHostPart(): BasePart?
	return self:_getHRP()
end

local function configureHubAxesOnHost(hubAtt: Attachment, host: BasePart)
	local towardSky = Vector3.yAxis
	hubAtt.Axis = host.CFrame:VectorToObjectSpace(towardSky)
	hubAtt.SecondaryAxis = host.CFrame:VectorToObjectSpace(Vector3.xAxis)
end

function BalloonRig.computeTorsoAttachmentWorldPosition(torso: BasePart, offsetInTorsoSpace: Vector3): Vector3
	return (torso.CFrame * CFrame.new(offsetInTorsoSpace)).Position
end

-- Torso-local offset → same world spot → HRP-local position (attachments live on HRP only).
function BalloonRig.computeHubLocalOffsetOnHrp(hrp: BasePart, torso: BasePart, offsetInTorsoSpace: Vector3): Vector3
	local worldPos = BalloonRig.computeTorsoAttachmentWorldPosition(torso, offsetInTorsoSpace)
	return hrp.CFrame:PointToObjectSpace(worldPos)
end

function BalloonRig.computeTorsoHubOffset(torso: BasePart): Vector3
	local topInset = Config.number("BalloonTorsoAnchorTopInsetStuds", 0.06)
	local backInset = Config.number("BalloonTorsoAnchorTopBackInsetStuds", 0.08)
	local halfY = torso.Size.Y * 0.5
	local halfZ = torso.Size.Z * 0.5
	-- Top + back face (+Z is back on UpperTorso/Torso for this rig)
	return Vector3.new(0, halfY - topInset, halfZ - backInset)
end

function BalloonRig.isKnotAttachmentName(name: string): boolean
	return name == BalloonRig.KNOT_ATT_NAME
		or string.sub(name, 1, #BalloonRig.KNOT_ATT_PREFIX) == BalloonRig.KNOT_ATT_PREFIX
end

function BalloonRig.getKnotAttachmentDefs(): { { name: string, position: Vector3 } }
	local t = Config.BalloonKnotAttachments
	if type(t) == "table" and #t > 0 then
		local out = {}
		for i, entry in ipairs(t) do
			if type(entry) == "table" then
				local pos = entry.position
				if typeof(pos) ~= "Vector3" then
					pos = Vector3.zero
				end
				table.insert(out, {
					name = (type(entry.name) == "string" and entry.name) or ("Att" .. tostring(i)),
					position = pos,
				})
			end
		end
		if #out > 0 then
			return out
		end
	end
	return {
		{ name = "Center", position = Vector3.zero },
		{ name = "Back", position = Vector3.new(0, 0, 0.11) },
		{ name = "Front", position = Vector3.new(0, 0, -0.11) },
		{ name = "Left", position = Vector3.new(-0.1, 0, 0) },
		{ name = "Right", position = Vector3.new(0.1, 0, 0) },
	}
end

function BalloonRig._clearKnotAttachments(knotPart: BasePart)
	for _, child in knotPart:GetChildren() do
		if child:IsA("Attachment") and BalloonRig.isKnotAttachmentName(child.Name) then
			child:Destroy()
		end
	end
end

function BalloonRig:_sortKnotAttachments(atts: { Attachment }): { Attachment }
	local defs = BalloonRig.getKnotAttachmentDefs()
	local byName: { [string]: Attachment } = {}
	for _, att in atts do
		byName[att.Name] = att
	end

	local sorted: { Attachment } = {}
	for i, def in ipairs(defs) do
		local name = if i == 1 then BalloonRig.KNOT_ATT_NAME else BalloonRig.KNOT_ATT_PREFIX .. def.name
		local att = byName[name]
		if att then
			table.insert(sorted, att)
		end
	end

	for _, att in atts do
		if not table.find(sorted, att) then
			table.insert(sorted, att)
		end
	end

	return sorted
end

function BalloonRig:_pickKnotAtt(pickIndex: number): Attachment?
	local atts = self._knotAtts
	if atts and #atts > 0 then
		local i = ((math.max(1, math.floor(pickIndex)) - 1) % #atts) + 1
		return atts[i]
	end
	return self._hubAtt
end

function BalloonRig:_getKnotAttForBalloon(rowIndex: number, slotInRow: number, _rowBalloonCount: number): Attachment?
	if not self:_shouldUseKnotHub() then
		return self._hubAtt
	end
	return self:_pickKnotAtt(slotInRow + math.max(0, rowIndex - 1))
end

function BalloonRig:_ensureKnotAttachments(knotPart: BasePart, host: BasePart): { Attachment }
	BalloonRig._clearKnotAttachments(knotPart)
	local defs = BalloonRig.getKnotAttachmentDefs()
	local atts: { Attachment } = {}
	for i, def in ipairs(defs) do
		local att = Instance.new("Attachment")
		att.Name = if i == 1 then BalloonRig.KNOT_ATT_NAME else BalloonRig.KNOT_ATT_PREFIX .. def.name
		att.Position = def.position
		att.Parent = knotPart
		configureHubAxesOnHost(att, host)
		atts[i] = att
	end
	self._knotAtts = atts
	self._hubAtt = atts[1]
	return atts
end

function BalloonRig:_clearKnotConstraints(knotPart: BasePart)
	for _, child in knotPart:GetChildren() do
		if child:IsA("WeldConstraint") or child:IsA("AlignPosition") or child:IsA("AlignOrientation") then
			child:Destroy()
		end
	end
end

function BalloonRig:_ensureKnotWeldToHost(host: BasePart, torso: BasePart, knotPart: BasePart)
	self:_clearKnotConstraints(knotPart)
	local off = BalloonRig.computeTorsoHubOffset(torso)
	local knotLocal = BalloonRig.computeKnotLocalOffset(off)
	local knotHostLocal = BalloonRig.computeHubLocalOffsetOnHrp(host, torso, knotLocal)
	knotPart.CFrame = host.CFrame * CFrame.new(knotHostLocal)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = host
	weld.Part1 = knotPart
	weld.Parent = knotPart
end

function BalloonRig:_destroyKnotBundle()
	local ch = self._character
	if ch then
		local knot = ch:FindFirstChild(BalloonRig.KNOT_PART_NAME)
		if knot then
			knot:Destroy()
		end
		local host = self:_getHubHostPart()
		if host then
			local hubAtt = host:FindFirstChild(BalloonRig.TORSO_SHARED_ATT_NAME)
			if hubAtt then
				hubAtt:Destroy()
			end
			BalloonRig._clearTorsoStrapsOnPart(host)
		end
		BalloonRig._clearLegacyTorsoHubParts(ch)
	end
	self._hubAtt = nil
	self._knotAtts = nil
	self._torsoAtt = nil
	self._knotPart = nil
end

function BalloonRig._clearTorsoStrapsOnPart(torso: BasePart)
	for _, child in torso:GetChildren() do
		if child:IsA("RopeConstraint") and string.sub(child.Name, 1, #BalloonRig.STRAP_NAME) == BalloonRig.STRAP_NAME then
			child:Destroy()
		elseif child:IsA("Attachment") and string.sub(child.Name, 1, #BalloonRig.STRAP_ATT_PREFIX) == BalloonRig.STRAP_ATT_PREFIX then
			child:Destroy()
		end
	end
end

function BalloonRig._clearLegacyTorsoHubParts(character: Model?)
	if not character then
		return
	end
	for _, name in { "UpperTorso", "Torso", "HumanoidRootPart" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local hubAtt = part:FindFirstChild(BalloonRig.TORSO_SHARED_ATT_NAME)
			if hubAtt then
				hubAtt:Destroy()
			end
			-- Straps live on HRP; only strip stray legacy straps from torso parts.
			if name ~= "HumanoidRootPart" then
				BalloonRig._clearTorsoStrapsOnPart(part)
			end
		end
	end
end

function BalloonRig._clearOrphanKnot(character: Model?)
	if not character then
		return
	end
	local folder = character:FindFirstChild(BalloonRig.ATTACHED_BALLOONS_FOLDER)
	local knot = character:FindFirstChild(BalloonRig.KNOT_PART_NAME)
	if knot and (not folder or not folder:IsA("Folder") or #folder:GetChildren() == 0) then
		knot:Destroy()
	end
end

function BalloonRig:_updateHubAnchorPositions(host: BasePart, torso: BasePart)
	local off = BalloonRig.computeTorsoHubOffset(torso)
	local spread = Config.number("BalloonTorsoStrapSpreadStuds", 0.1)
	local strapCount = self:_getActiveRowCount(self._pendingHubBalloonCount)

	local sharedHub = host:FindFirstChild(BalloonRig.TORSO_SHARED_ATT_NAME)
	if sharedHub and sharedHub:IsA("Attachment") then
		sharedHub.Position = BalloonRig.computeHubLocalOffsetOnHrp(host, torso, off)
		configureHubAxesOnHost(sharedHub, host)
	end

	local strapIndex = 0
	for _, child in host:GetChildren() do
		if child:IsA("Attachment") and string.sub(child.Name, 1, #BalloonRig.STRAP_ATT_PREFIX) == BalloonRig.STRAP_ATT_PREFIX then
			strapIndex += 1
			local x = (strapIndex - (strapCount + 1) * 0.5) * spread
			child.Position = BalloonRig.computeHubLocalOffsetOnHrp(host, torso, off + Vector3.new(x, 0, 0))
			configureHubAxesOnHost(child, host)
		end
	end

	if self:_shouldUseKnotHub() and not self:_torsoStrapsAreComplete(host, strapCount) then
		self:_syncTorsoStraps()
	end
end

function BalloonRig:_destroyLegacyWorkspaceAnchors()
	local rigFolder = self._rigFolder
	if not rigFolder then
		return
	end
	for _, name in { "BalloonHubProxy", "BalloonTorsoAnchorProxy" } do
		local legacy = rigFolder:FindFirstChild(name)
		if legacy then
			legacy:Destroy()
		end
	end
	local legacyFolder = rigFolder:FindFirstChild(BalloonRig.ATTACHED_BALLOONS_FOLDER)
	if legacyFolder then
		legacyFolder:Destroy()
	end
end

function BalloonRig:_destroyHub()
	self:_destroyKnotBundle()
	self:_destroyLegacyWorkspaceAnchors()
end

function BalloonRig:_refreshKnotAttachmentRefs()
	local character = self._character
	local knotPart = self._knotPart
	if (not knotPart or not knotPart.Parent) and character then
		local found = character:FindFirstChild(BalloonRig.KNOT_PART_NAME)
		knotPart = if found and found:IsA("BasePart") then found else nil
	end
	if not knotPart then
		return
	end

	self._knotPart = knotPart
	local atts: { Attachment } = {}
	for _, child in knotPart:GetChildren() do
		if child:IsA("Attachment") and BalloonRig.isKnotAttachmentName(child.Name) then
			table.insert(atts, child)
			if child.Name == BalloonRig.KNOT_ATT_NAME then
				self._hubAtt = child
			end
		end
	end
	if #atts > 0 then
		atts = self:_sortKnotAttachments(atts)
		self._knotAtts = atts
		self._hubAtt = self._hubAtt or atts[1]
	end
end

function BalloonRig:_freezeAllBalloons(): { BasePart }
	local frozen: { BasePart } = {}
	local folder = self._balloonsFolder
	if not folder then
		return frozen
	end

	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			for _, part in self:_setBalloonAnchored(child, true) do
				table.insert(frozen, part)
			end
			self:_zeroBalloonVelocities(child)
		end
	end

	return frozen
end

function BalloonRig:_unfreezeAllBalloons(frozen: { BasePart })
	if self:_spawnAtRodRestEnabled() then
		return
	end

	for _, part in frozen do
		if part.Parent then
			part.Anchored = false
		end
	end
end

function BalloonRig:_swapHubForBalloonCount(balloonCount: number)
	local frozen = self:_freezeAllBalloons()
	self._pendingHubBalloonCount = math.max(0, math.floor(balloonCount))
	self:_transitionHubForBalloonCount(balloonCount)
	self:_snapAllBalloonsToRodRest()
	self:_settleSpawnPhysics()

	local knot = self._knotPart
	if knot and knot:IsA("BasePart") then
		knot.AssemblyLinearVelocity = Vector3.zero
		knot.AssemblyAngularVelocity = Vector3.zero
	end

	self:_unfreezeAllBalloons(frozen)
	if self:_shouldUseKnotHub(balloonCount) then
		self:_syncTorsoStraps()
	end
	self:SyncRopeVisibility()
end

function BalloonRig:_getActiveRowCount(hintBalloonCount: number?): number
	local maxRow = 0
	local maxIndex = if hintBalloonCount then math.max(0, math.floor(hintBalloonCount)) else 0

	local folder = self._balloonsFolder
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				local rowIndex = tonumber(child:GetAttribute("BalloonRow"))
				if rowIndex and rowIndex > maxRow then
					maxRow = rowIndex
				end
				local balloonIndex = tonumber(child:GetAttribute("BalloonIndex"))
				if balloonIndex and balloonIndex > maxIndex then
					maxIndex = balloonIndex
				end
			end
		end
	end

	if maxRow == 0 and maxIndex > 0 then
		maxRow = BalloonRig.resolveRow(maxIndex)
	end

	return math.max(1, maxRow)
end

function BalloonRig:_torsoStrapRopeIsValid(
	host: BasePart,
	strap: RopeConstraint,
	strapAtt: Attachment,
	pickAtt: Attachment?
): boolean
	if not pickAtt or not pickAtt.Parent then
		return false
	end
	if strap.Attachment0 ~= strapAtt or strap.Attachment1 ~= pickAtt then
		return false
	end
	if strapAtt.Parent ~= host then
		return false
	end
	local knot = self._knotPart
	if knot and pickAtt.Parent ~= knot then
		return false
	end
	return true
end

function BalloonRig:_torsoStrapsAreComplete(host: BasePart, strapCount: number): boolean
	for i = 1, strapCount do
		local strapAtt = host:FindFirstChild(BalloonRig.STRAP_ATT_PREFIX .. tostring(i))
		local strap = host:FindFirstChild(BalloonRig.STRAP_NAME .. "_" .. tostring(i))
		if not strapAtt or not strapAtt:IsA("Attachment") or not strap or not strap:IsA("RopeConstraint") then
			return false
		end
		local pickAtt = self:_pickKnotAtt(i)
		if not self:_torsoStrapRopeIsValid(host, strap, strapAtt, pickAtt) then
			return false
		end
	end
	return true
end

function BalloonRig:_applyTorsoStrapRope(
	host: BasePart,
	strapAtt: Attachment,
	pickAtt: Attachment,
	index: number,
	slack: number
): RopeConstraint
	local ropeName = BalloonRig.STRAP_NAME .. "_" .. tostring(index)
	local span = (pickAtt.WorldPosition - strapAtt.WorldPosition).Magnitude
	local strap = host:FindFirstChild(ropeName)

	if strap and strap:IsA("RopeConstraint") then
		strap.Attachment0 = strapAtt
		strap.Attachment1 = pickAtt
		strap.Length = span + slack
		strap.Visible = Config.flag("BalloonTorsoStrapVisible")
		return strap
	end

	strap = Instance.new("RopeConstraint")
	strap.Name = ropeName
	strap.Attachment0 = strapAtt
	strap.Attachment1 = pickAtt
	strap.Length = span + slack
	strap.Visible = Config.flag("BalloonTorsoStrapVisible")
	strap.Thickness = Config.number("RopeThicknessStuds", 0.12)
	pcall(function()
		strap.Restitution = 0
		strap.WinchEnabled = false
	end)
	strap.Parent = host
	return strap
end

function BalloonRig:_syncTorsoStraps()
	local host = self:_getHubHostPart()
	local torso = self:_getTorsoReferencePart() or host
	if not host or not torso or not self:_shouldUseKnotHub() then
		return
	end

	self:_refreshKnotAttachmentRefs()
	if not self._hubAtt then
		return
	end

	local knotPart = self._knotPart
	if knotPart and knotPart.Parent and (not self._knotAtts or #self._knotAtts == 0) then
		self:_ensureKnotAttachments(knotPart, host)
	end

	local hintCount = self._pendingHubBalloonCount
	self._pendingHubBalloonCount = nil

	local strapCount = self:_getActiveRowCount(hintCount)
	local off = BalloonRig.computeTorsoHubOffset(torso)
	local slack = Config.number("BalloonTorsoStrapSlackStuds", 0.35)
	local spread = Config.number("BalloonTorsoStrapSpreadStuds", 0.1)

	local needsRebuild = not self:_torsoStrapsAreComplete(host, strapCount)
	if needsRebuild then
		BalloonRig._clearTorsoStrapsOnPart(host)
		if self._character then
			BalloonRig._clearLegacyTorsoHubParts(self._character)
		end
	end

	for i = 1, strapCount do
		local attName = BalloonRig.STRAP_ATT_PREFIX .. tostring(i)
		local strapAtt = host:FindFirstChild(attName)
		if not strapAtt or not strapAtt:IsA("Attachment") then
			strapAtt = Instance.new("Attachment")
			strapAtt.Name = attName
			strapAtt.Parent = host
		end

		local x = (i - (strapCount + 1) * 0.5) * spread
		strapAtt.Position = BalloonRig.computeHubLocalOffsetOnHrp(host, torso, off + Vector3.new(x, 0, 0))
		configureHubAxesOnHost(strapAtt, host)

		local pickAtt = self:_pickKnotAtt(i)
		if pickAtt then
			self:_applyTorsoStrapRope(host, strapAtt, pickAtt, i, slack)
		end
	end

	self._torsoAtt = host:FindFirstChild(BalloonRig.STRAP_ATT_PREFIX .. "1")
end

function BalloonRig:repairTorsoStrapsIfNeeded()
	if not self:_shouldUseKnotHub() then
		return false
	end

	local host = self:_getHubHostPart()
	if not host then
		return false
	end

	local strapCount = self:_getActiveRowCount()
	if self:_torsoStrapsAreComplete(host, strapCount) then
		return false
	end

	self:_syncTorsoStraps()
	return true
end

function BalloonRig:_isSpawnSettling(): boolean
	local untilTime = self._spawnSettleUntil
	return untilTime ~= nil and os.clock() < untilTime
end

function BalloonRig:_spawnAtRodRestEnabled(): boolean
	return Config.flag("BalloonSpawnAtRodRestEnabled")
end

function BalloonRig:_releaseAllBalloonAnchors()
	local folder = self._balloonsFolder
	if not folder then
		return
	end

	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			self:_setBalloonAnchored(child, false)
			self:_zeroBalloonVelocities(child)
		end
	end
end

function BalloonRig:_beginSpawnSettle()
	if self:_spawnAtRodRestEnabled() then
		return
	end

	local seconds = Config.number("BalloonRigSpawnSettleSeconds", 1.25)
	self._spawnSettleUntil = os.clock() + seconds
	local character = self._character
	if character then
		character:SetAttribute(BalloonRig.SETTLING_ATTR, true)
		task.delay(seconds, function()
			if self._character ~= character or not character.Parent then
				return
			end
			self._spawnSettleUntil = nil
			character:SetAttribute(BalloonRig.SETTLING_ATTR, false)
			self:_snapAllBalloonsToRodRest()
			self:_settleSpawnPhysics()
		end)
	end
end

function BalloonRig:_setBalloonLiftEnabled(enabled: boolean)
	local folder = self._balloonsFolder
	if not folder then
		return
	end
	local forceName = Config.BalloonLiftForceName or "BalloonLift"
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local vf = child:FindFirstChild(forceName, true)
			if vf and vf:IsA("VectorForce") then
				vf.Enabled = enabled
				if not enabled then
					vf.Force = Vector3.zero
				end
			end
		end
	end
end

function BalloonRig:_tickSpawnSettle()
	if not self:_isSpawnSettling() then
		return
	end
	self:_settleSpawnPhysics()
	self:_setBalloonLiftEnabled(false)
end

function BalloonRig:_canSyncHubOrientation(): boolean
	if self:_isSpawnSettling() then
		return false
	end
	local character = self._character
	if not character or not character.Parent then
		return false
	end

	local host = self:_getHRP()
	local torso = self:_getTorsoReferencePart() or host
	if not host or not torso then
		return false
	end
	if host.Parent ~= character or torso.Parent ~= character then
		return false
	end

	return self:_balloonModelCount() > 0 or self._hubAtt ~= nil
end

function BalloonRig:_settleSpawnPhysics()
	local character = self._character
	if not character then
		return
	end

	local knot = self._knotPart or character:FindFirstChild(BalloonRig.KNOT_PART_NAME)
	if knot and knot:IsA("BasePart") then
		knot.AssemblyLinearVelocity = Vector3.zero
		knot.AssemblyAngularVelocity = Vector3.zero
	end

	local folder = self._balloonsFolder or character:FindFirstChild(BalloonRig.ATTACHED_BALLOONS_FOLDER)
	if folder and folder:IsA("Folder") then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				for _, d in child:GetDescendants() do
					if d:IsA("BasePart") then
						d.AssemblyLinearVelocity = Vector3.zero
						d.AssemblyAngularVelocity = Vector3.zero
					end
				end
			end
		end
	end
end

function BalloonRig:_repositionKnotToHost()
	if not self:_isUsingKnotHub() then
		return
	end

	local host = self:_getHRP()
	local torso = self:_getTorsoReferencePart() or host
	local knot = self._knotPart
	if not host or not torso or not knot or not knot.Parent then
		return
	end

	self:_ensureKnotWeldToHost(host, torso, knot)
	self:_refreshKnotAttachmentRefs()
	if not self._knotAtts or #self._knotAtts == 0 then
		self:_ensureKnotAttachments(knot, host)
	end
end

function BalloonRig:_finalizeRigAfterBuild()
	self:_beginSpawnSettle()
	if self:_getHRP() and (self:_getTorsoReferencePart() or self:_getHRP()) then
		local host = self:_getHRP()
		local torso = self:_getTorsoReferencePart() or host
		if host and torso then
			self:_updateHubAnchorPositions(host, torso)
			self:_repositionKnotToHost()
		end
	end
	self:_snapAllBalloonsToRodRest()
	self:_settleSpawnPhysics()
	self:_setBalloonLiftEnabled(false)
	if self:_spawnAtRodRestEnabled() then
		self:_releaseAllBalloonAnchors()
	end
	if self:_shouldUseKnotHub() then
		self:_syncTorsoStraps()
	end
	self:SyncRopeVisibility()
	self._pendingHubBalloonCount = nil
end

function BalloonRig:_snapBalloonIndexToRodRest(balloonIndex: number)
	local folder = self._balloonsFolder
	if not folder or not self._hubAtt then
		return
	end

	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		if tonumber(child:GetAttribute("BalloonIndex")) ~= balloonIndex then
			continue
		end

		local rowIndex, slotInRow, rowDef = BalloonRig.resolveRow(balloonIndex)
		local rowBalloonCount = rowDef.count or 6
		local downAtt = self:_findDownAttachment(child)
		if not downAtt then
			return
		end

		local hubAtt = self:_getKnotAttForBalloon(rowIndex, slotInRow, rowBalloonCount) or self._hubAtt
		local rodLen = self:_resolveRodLength(balloonIndex, hubAtt, downAtt, nil)
		self:_snapBalloonToRodRest(child, hubAtt, downAtt, rodLen)
		self:_zeroBalloonVelocities(child)
		return
	end
end

function BalloonRig:_finalizeIncrementalAdd(newIndex: number)
	local host = self:_getHRP()
	local torso = self:_getTorsoReferencePart() or host
	if host and torso then
		self:_updateHubAnchorPositions(host, torso)
		self:_repositionKnotToHost()
	end

	self:_snapBalloonIndexToRodRest(newIndex)
	self:SyncRopeVisibility()
	self._pendingHubBalloonCount = nil
end

function BalloonRig:SyncHubOrientation()
	if not self:_canSyncHubOrientation() then
		return
	end

	local host = self:_getHRP()
	local torso = self:_getTorsoReferencePart() or host
	if not host or not torso then
		return
	end

	-- HRP attachment positions only — never teleport the knot (rods/ropes explode if we do).
	self:_updateHubAnchorPositions(host, torso)
end

function BalloonRig:_createTorsoHubAttachment(host: BasePart, torso: BasePart, off: Vector3): Attachment
	local hubAtt = host:FindFirstChild(BalloonRig.TORSO_SHARED_ATT_NAME)
	if not hubAtt or not hubAtt:IsA("Attachment") then
		if hubAtt then
			hubAtt:Destroy()
		end
		hubAtt = Instance.new("Attachment")
		hubAtt.Name = BalloonRig.TORSO_SHARED_ATT_NAME
		hubAtt.Parent = host
	end
	hubAtt.Position = BalloonRig.computeHubLocalOffsetOnHrp(host, torso, off)
	configureHubAxesOnHost(hubAtt, host)
	self._hubAtt = hubAtt
	self._torsoAtt = nil
	return hubAtt
end

function BalloonRig:_transitionHubForBalloonCount(balloonCount: number)
	local host = self:_getHubHostPart()
	local torso = self:_getTorsoReferencePart() or self:_getTorsoPart()
	if not host or not torso then
		return
	end

	local off = BalloonRig.computeTorsoHubOffset(torso)
	local wantKnot = self:_shouldUseKnotHub(balloonCount)

	if wantKnot then
		self._hubAtt = self:_ensureHubForCount(balloonCount)
		self:_reconnectAllBalloonHubs()
		return
	end

	-- Knot → torso: point rods at HRP hub first, then delete knot (never the reverse).
	self:_createTorsoHubAttachment(host, torso, off)
	self:_reconnectAllBalloonHubs()

	local character = self._character
	if character then
		local knot = character:FindFirstChild(BalloonRig.KNOT_PART_NAME)
		if knot then
			knot:Destroy()
		end
	end
	self._knotPart = nil
	self._knotAtts = nil
	self._knotHostLocal = nil
	BalloonRig._clearTorsoStrapsOnPart(host)
end

function BalloonRig.getRow1BaseHeightStuds(): number
	local _rowIndex, _slotInRow, rowDef = BalloonRig.resolveRow(1)
	return rowDef.heightAboveRootStuds or 6.2
end

function BalloonRig.getBalloonSpawnLowerStuds(): number
	return Config.number("BalloonSpawnHeightLowerStuds", 1.2)
		- Config.number("BalloonSpawnCloserToKnotStuds", 0)
end

function BalloonRig.getRow1SpawnHeightStuds(): number
	return BalloonRig.getRow1BaseHeightStuds() - BalloonRig.getBalloonSpawnLowerStuds()
end

function BalloonRig.computeKnotLocalOffset(torsoHubOff: Vector3): Vector3
	local row1BaseY = BalloonRig.getRow1BaseHeightStuds()
	local aboveRow1 = Config.number("BalloonKnotAboveRow1Studs", 1.04)
	local knotExtraY = Config.number("BalloonKnotExtraYOffsetStuds", 0)
	local backZ = Config.number("BalloonKnotBackOffsetStuds", 0.12)
	return Vector3.new(torsoHubOff.X, row1BaseY + aboveRow1 + knotExtraY, torsoHubOff.Z + backZ)
end

function BalloonRig:_ensureKnotHub(host: BasePart, torso: BasePart, character: Model, _off: Vector3): Attachment
	BalloonRig._clearTorsoStrapsOnPart(host)
	BalloonRig._clearLegacyTorsoHubParts(character)

	local torsoAtt = torso:FindFirstChild(BalloonRig.TORSO_SHARED_ATT_NAME)
	if torsoAtt then
		torsoAtt:Destroy()
	end

	local knotPart = character:FindFirstChild(BalloonRig.KNOT_PART_NAME)
	if not knotPart or not knotPart:IsA("BasePart") then
		if knotPart then
			knotPart:Destroy()
		end
		knotPart = Instance.new("Part")
		knotPart.Name = BalloonRig.KNOT_PART_NAME
		knotPart.Size = Vector3.new(0.12, 0.12, 0.12)
		knotPart.Transparency = 1
		knotPart.Anchored = false
		knotPart.CanCollide = false
		knotPart.CanQuery = false
		knotPart.CanTouch = false
		knotPart.Massless = true
		knotPart.CollisionGroup = BalloonRig.BALLOON_COLLISION_GROUP
		knotPart.Parent = character
	end

	for _, child in knotPart:GetChildren() do
		if child:IsA("WeldConstraint")
			or child:IsA("AlignPosition")
			or child:IsA("AlignOrientation")
			or (child:IsA("Motor6D") and child.Name == BalloonRig.KNOT_MOTOR_NAME)
		then
			child:Destroy()
		end
	end

	self:_ensureKnotAttachments(knotPart, host)
	self:_ensureKnotWeldToHost(host, torso, knotPart)

	if RunService:IsServer() then
		self:_setPartNetworkOwner(knotPart)
	end

	self._knotPart = knotPart
	self._torsoAtt = nil
	self:_syncTorsoStraps()
	return self._hubAtt :: Attachment
end

function BalloonRig:_ensureHub(): Attachment
	return self:_ensureHubForCount(math.max(1, self:_balloonModelCount()))
end

--// Row layout (6 / 8 / 10 per ring) -------------------------------------------

local function _defaultRows()
	return {
		{ count = 6, rodLengthStuds = 8, rodLengthJitterStuds = 0.5, heightAboveRootStuds = 6.2, ringRadiusStuds = 2.6 },
		{ count = 8, rodLengthStuds = 10.5, rodLengthJitterStuds = 0.5, heightAboveRootStuds = 7.6, ringRadiusStuds = 3.1 },
		{ count = 10, rodLengthStuds = 13, rodLengthJitterStuds = 0.5, heightAboveRootStuds = 9.0, ringRadiusStuds = 3.6 },
	}
end

function BalloonRig.getRowDefs()
	local rows = Config.BalloonRows
	if type(rows) == "table" and #rows > 0 then
		return rows
	end
	return _defaultRows()
end

function BalloonRig.resolveRow(index: number)
	local globalIndex = math.max(1, math.floor(index))
	local cursor = 0
	local rowDefs = BalloonRig.getRowDefs()

	for rowIndex, row in ipairs(rowDefs) do
		local count = math.max(1, row.count or 6)
		if globalIndex <= cursor + count then
			return rowIndex, globalIndex - cursor, row
		end
		cursor += count
	end

	local lastRow = rowDefs[#rowDefs]
	local extraCount = math.max(1, Config.number("BalloonRowExtraCount", lastRow.count or 10))
	local past = globalIndex - cursor
	local extraRowIndex = math.ceil(past / extraCount)
	local slotInRow = ((past - 1) % extraCount) + 1
	local rodStep = Config.number("BalloonRowExtraRodStepStuds", 2.5)
	local heightStep = Config.number("BalloonRowExtraHeightStepStuds", 1.4)
	local radiusStep = Config.number("BalloonRowExtraRadiusStepStuds", 0.35)

	local extrapolated = {
		count = extraCount,
		rodLengthStuds = (lastRow.rodLengthStuds or 13) + rodStep * extraRowIndex,
		rodLengthJitterStuds = lastRow.rodLengthJitterStuds or 0.5,
		heightAboveRootStuds = (lastRow.heightAboveRootStuds or 9)
			+ heightStep * extraRowIndex,
		ringRadiusStuds = (lastRow.ringRadiusStuds or 3.6) + radiusStep * extraRowIndex,
	}
	return #rowDefs + extraRowIndex, slotInRow, extrapolated
end

function BalloonRig.spawnLocalOffset(index: number): Vector3
	local rowIndex, slotInRow, rowDef = BalloonRig.resolveRow(index)
	local count = math.max(1, rowDef.count or 6)
	local angle = ((slotInRow - 1) / count) * math.pi * 2
	if Config.flag("BalloonRowAngleStagger") then
		angle += (rowIndex - 1) * (math.pi / count)
	end
	local r = rowDef.ringRadiusStuds or Config.number("BalloonSpawnRingRadiusStuds", 2.5)
	local y = rowDef.heightAboveRootStuds or 6.2
	y -= BalloonRig.getBalloonSpawnLowerStuds()
	return Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)
end

function BalloonRig:_spawnCFrame(index: number): CFrame?
	local torso = self:_getTorsoPart()
	if not torso then
		return nil
	end
	local offset = BalloonRig.spawnLocalOffset(index)
	return torso.CFrame * CFrame.new(offset)
end

--// Templates & clone ----------------------------------------------------------

function BalloonRig:_getTemplateFolder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets and RunService:IsServer() then
		assets = ReplicatedStorage:WaitForChild("Assets", 8)
	end
	if not assets then
		return nil
	end
	return assets:FindFirstChild("Baloons") or assets:FindFirstChild("Balloons")
end

function BalloonRig:_cloneTemplate(configName: string, index: number): Model?
	local templates = self:_getTemplateFolder()
	if not templates then
		warn("[BalloonRig] Missing ReplicatedStorage.Assets balloon templates folder (Baloons/Balloons).")
		return nil
	end
	local template = templates:FindFirstChild(configName)
	if not template then
		warn(("[BalloonRig] Missing balloon template %q."):format(configName))
		return nil
	end

	local clone = template:Clone()
	local balloonModel: Model?

	if clone:IsA("BasePart") then
		balloonModel = Instance.new("Model")
		balloonModel.Name = "Balloon_" .. tostring(index) .. "_" .. configName
		clone.Name = "Root"
		clone.Parent = balloonModel
		balloonModel.PrimaryPart = clone
	elseif clone:IsA("Model") then
		balloonModel = clone
		balloonModel.Name = "Balloon_" .. tostring(index) .. "_" .. configName
	else
		clone:Destroy()
		return nil
	end

	if not balloonModel.PrimaryPart then
		balloonModel.PrimaryPart = self:_pickMainPart(balloonModel)
	end
	if not balloonModel.PrimaryPart then
		balloonModel:Destroy()
		return nil
	end

	return balloonModel
end

--// Physics & prep -------------------------------------------------------------

function BalloonRig:_pickMainPart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local bestPart: BasePart? = nil
	local bestVol = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local vol = d.Size.X * d.Size.Y * d.Size.Z
			if vol > bestVol then
				bestVol = vol
				bestPart = d
			end
		end
	end
	return bestPart
end

function BalloonRig:_stripTemplateTethers(balloonModel: Model)
	for _, inst in balloonModel:GetDescendants() do
		if inst:IsA("RodConstraint") or inst:IsA("RopeConstraint") then
			inst:Destroy()
		elseif inst.Name == "BalloonRod" or inst.Name == "BalloonRope" then
			inst:Destroy()
		elseif string.sub(inst.Name, 1, #BalloonRig.STRAP_NAME) == BalloonRig.STRAP_NAME then
			inst:Destroy()
		end
	end
end

function BalloonRig:_applyBalloonPhysics(balloonModel: Model)
	for _, d in balloonModel:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = BalloonRig.BALLOON_COLLISION_GROUP
			d.CanCollide = true
			d.CanTouch = false
			d.CanQuery = false
			d.Anchored = false
		end
	end
	self:_applyBalloonNetworkOwner(balloonModel)
end

function BalloonRig:_setPartNetworkOwner(part: BasePart)
	if not RunService:IsServer() then
		return
	end

	local owner = self._networkOwner
	if not owner or not owner.Parent then
		return
	end

	pcall(function()
		part:SetNetworkOwnershipAuto(false)
		part:SetNetworkOwner(owner)
	end)
end

function BalloonRig:_applyBalloonNetworkOwner(balloonModel: Model)
	if not RunService:IsServer() then
		return
	end

	for _, d in balloonModel:GetDescendants() do
		if d:IsA("BasePart") then
			self:_setPartNetworkOwner(d)
		end
	end
end

function BalloonRig:_findDownAttachment(balloonModel: Model): Attachment?
	local att = balloonModel:FindFirstChild(BalloonRig.BALLOON_DOWN_ATT_NAME, true)
	if att and att:IsA("Attachment") then
		return att
	end
	return nil
end

--// Rod + rope (A0 = knot hub, A1 = DownAttachment; torso strap separate) -----

function BalloonRig:_rodLengthFromConfig(index: number): number
	local _rowIndex, _slotInRow, rowDef = BalloonRig.resolveRow(index)
	local base = rowDef.rodLengthStuds or 8
	local jitter = rowDef.rodLengthJitterStuds or 0.5
	return base + math.random() * jitter
end

function BalloonRig:_resolveRodLength(
	index: number,
	hubAtt: Attachment,
	downAtt: Attachment,
	prefLen: number?
): number
	local rodLen = prefLen or self:_rodLengthFromConfig(index)
	local span = (downAtt.WorldPosition - hubAtt.WorldPosition).Magnitude
	return math.max(rodLen, span * 0.98)
end

function BalloonRig:_spawnDirectionWorld(index: number, hubWorld: Vector3): Vector3
	local spawnCF = self:_spawnCFrame(index)
	if not spawnCF then
		return Vector3.new(0, -1, 0)
	end

	local dir = spawnCF.Position - hubWorld
	if dir.Magnitude < 0.05 then
		return Vector3.new(0, -1, 0)
	end

	return dir.Unit
end

function BalloonRig:_computeRodRestDownWorld(index: number, hubAtt: Attachment, rodLen: number): Vector3
	local hubWorld = hubAtt.WorldPosition
	return hubWorld + self:_spawnDirectionWorld(index, hubWorld) * rodLen
end

function BalloonRig:_pivotBalloonAttachmentToWorld(balloonModel: Model, att: Attachment, worldPos: Vector3)
	local delta = worldPos - att.WorldPosition
	if delta.Magnitude > 0.001 then
		balloonModel:PivotTo(balloonModel:GetPivot() + delta)
	end
end

function BalloonRig:_setBalloonAnchored(balloonModel: Model, anchored: boolean): { BasePart }
	local changed: { BasePart } = {}
	for _, d in balloonModel:GetDescendants() do
		if d:IsA("BasePart") and d.Anchored ~= anchored then
			d.Anchored = anchored
			table.insert(changed, d)
		end
	end
	return changed
end

function BalloonRig:_zeroBalloonVelocities(balloonModel: Model)
	for _, d in balloonModel:GetDescendants() do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

function BalloonRig:_snapAllBalloonsToRodRest()
	local folder = self._balloonsFolder
	if not folder or not self._hubAtt then
		return
	end

	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end

		local balloonIndex = tonumber(child:GetAttribute("BalloonIndex"))
		if not balloonIndex then
			continue
		end

		local rowIndex, slotInRow, rowDef = BalloonRig.resolveRow(balloonIndex)
		local rowBalloonCount = rowDef.count or 6
		local downAtt = self:_findDownAttachment(child)
		if not downAtt then
			continue
		end

		local hubAtt = self:_getKnotAttForBalloon(rowIndex, slotInRow, rowBalloonCount) or self._hubAtt
		local rodLen = self:_resolveRodLength(balloonIndex, hubAtt, downAtt, nil)
		self:_snapBalloonToRodRest(child, hubAtt, downAtt, rodLen)
		self:_zeroBalloonVelocities(child)
	end
end

function BalloonRig:_rodLengthForIndex(index: number, hubAtt: Attachment?, downAtt: Attachment?): number
	if not hubAtt or not downAtt then
		return self:_rodLengthFromConfig(index)
	end
	return self:_resolveRodLength(index, hubAtt, downAtt, nil)
end

function BalloonRig:_snapBalloonToRodRest(balloonModel: Model, hubAtt: Attachment, downAtt: Attachment, rodLen: number)
	local hubWorld = hubAtt.WorldPosition
	local downWorld = downAtt.WorldPosition
	local dir = downWorld - hubWorld
	if dir.Magnitude < 0.05 then
		return
	end
	local targetDown = hubWorld + dir.Unit * rodLen
	local delta = targetDown - downWorld
	if delta.Magnitude < 0.01 then
		return
	end
	balloonModel:PivotTo(balloonModel:GetPivot() + delta)
end

--[[
	Row 1 (e.g. 6 slots): ropes on slots 1..n−1 → 5 ropes when full.
	Row 2+ (e.g. 8 slots): rope slot 1 always; +1 rope on slot (rowCount−1) when reached (slot 7 → 13 balloons = 7 total).
]]
function BalloonRig:_belowKnotBalloonCount(): boolean
	return self:_balloonModelCount() < Config.number("BalloonKnotMinBalloonCount", 5)
end

function BalloonRig:_ropeVisibleForBalloon(
	rowIndex: number,
	slotInRow: number,
	rowBalloonCount: number,
	balloonIndex: number?
): boolean
	if self:_belowKnotBalloonCount() then
		return true
	end

	if not self:_shouldUseKnotHub(self:_balloonModelCount()) then
		return true
	end

	if balloonIndex and balloonIndex < Config.number("BalloonKnotMinBalloonCount", 5) then
		return true
	end

	rowBalloonCount = math.max(1, math.floor(rowBalloonCount))
	slotInRow = math.max(1, math.floor(slotInRow))

	if rowIndex <= 1 then
		local filled = self:_balloonModelCount()
		if filled < Config.number("BalloonKnotMinBalloonCount", 5) then
			return true
		end
		return slotInRow < rowBalloonCount
	end

	if slotInRow == 1 then
		return true
	end

	local lastRopeSlot = rowBalloonCount - 1
	if lastRopeSlot <= 1 then
		return false
	end
	return slotInRow == lastRopeSlot
end

function BalloonRig:SyncRopeVisibility()
	local folder = self._balloonsFolder
	if not folder or not folder.Parent then
		return
	end
	for _, child in folder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		local balloonIndex = tonumber(child:GetAttribute("BalloonIndex"))
		local rowIndex = tonumber(child:GetAttribute("BalloonRow"))
		local slotInRow = tonumber(child:GetAttribute("BalloonRowSlot"))
		local rowBalloonCount = tonumber(child:GetAttribute("BalloonRowCount"))
		if not rowIndex or not slotInRow or not rowBalloonCount then
			if balloonIndex then
				local rowDef
				rowIndex, slotInRow, rowDef = BalloonRig.resolveRow(balloonIndex)
				rowBalloonCount = rowDef.count
			else
				rowIndex = 999
				slotInRow = 1
				rowBalloonCount = 1
			end
		end

		local hasValidRope = false
		for _, inst in child:GetDescendants() do
			if inst:IsA("RopeConstraint") and inst.Name == "BalloonRope" then
				local visible = self:_ropeVisibleForBalloon(rowIndex, slotInRow, rowBalloonCount, balloonIndex)
				if self:_belowKnotBalloonCount() then
					visible = true
				end
				inst.Visible = visible
				if inst.Attachment0 and inst.Attachment1 and inst.Attachment0.Parent and inst.Attachment1.Parent then
					hasValidRope = true
				end
			end
		end
		if not hasValidRope and balloonIndex and self._hubAtt then
			self:_syncBalloonTethers(child, balloonIndex)
		end
	end
	if self:_shouldUseKnotHub(self:_balloonModelCount()) then
		self:_syncTorsoStraps()
	end
end

function BalloonRig:_attachRodAndRope(
	downAtt: Attachment,
	hubAtt: Attachment,
	rodLen: number,
	ropeLen: number,
	rowIndex: number,
	slotInRow: number,
	rowBalloonCount: number,
	balloonIndex: number?
)
	local hostPart = downAtt.Parent :: BasePart

	local rod = Instance.new("RodConstraint")
	rod.Name = "BalloonRod"
	rod.Attachment0 = hubAtt
	rod.Attachment1 = downAtt
	rod.Length = rodLen
	rod.LimitsEnabled = Config.flag("BalloonRodLimitsEnabled")
	rod.LimitAngle0 = Config.number("BalloonRodLimitAngle0", 27)
	rod.LimitAngle1 = Config.number("BalloonRodLimitAngle1", 90)
	rod.Visible = Config.flag("BalloonRodVisible")
	rod.Thickness = Config.number("BalloonRodThicknessStuds", 0.08)
	rod.Parent = hostPart

	local rope = Instance.new("RopeConstraint")
	rope.Name = "BalloonRope"
	rope.Attachment0 = hubAtt
	rope.Attachment1 = downAtt
	rope.Length = ropeLen
	rope.Visible = self:_ropeVisibleForBalloon(rowIndex, slotInRow, rowBalloonCount, balloonIndex)
	if self:_belowKnotBalloonCount() then
		rope.Visible = true
	end
	rope.Thickness = Config.number("RopeThicknessStuds", 0.12)
	pcall(function()
		rope.Restitution = 0
		rope.WinchEnabled = false
	end)
	rope.Parent = hostPart
end

--// Install --------------------------------------------------------------------

function BalloonRig:_ensureBalloonsFolder(): Folder
	self:_destroyLegacyWorkspaceAnchors()

	local parent = self._character
	if not parent or not parent.Parent then
		error("[BalloonRig] character missing")
	end

	local folder = self._balloonsFolder
	if folder and folder.Parent == parent then
		return folder
	end
	if folder then
		folder:Destroy()
	end

	folder = parent:FindFirstChild(BalloonRig.ATTACHED_BALLOONS_FOLDER)
	if folder and folder:IsA("Folder") then
		self._balloonsFolder = folder
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = BalloonRig.ATTACHED_BALLOONS_FOLDER
	folder.Parent = parent
	self._balloonsFolder = folder
	return folder
end

function BalloonRig:_installBalloon(configName: string, index: number): Model?
	local torso = self:_getTorsoPart()
	if not torso then
		return nil
	end

	self._balloonsFolder = self:_ensureBalloonsFolder()
	local folder = self._balloonsFolder
	if not folder then
		return nil
	end

	local host = self:_getHRP()
	local torsoRef = self:_getTorsoReferencePart() or host
	if host and torsoRef then
		self:_updateHubAnchorPositions(host, torsoRef)
		self:_repositionKnotToHost()
	end

	if not self._hubAtt then
		return nil
	end

	local balloonModel = self:_cloneTemplate(configName, index)
	if not balloonModel then
		return nil
	end

	self:_stripTemplateTethers(balloonModel)
	self:_applyBalloonPhysics(balloonModel)

	local downAtt = self:_findDownAttachment(balloonModel)
	if not downAtt then
		warn(
			("[BalloonRig] %q missing Attachment %q.")
				:format(configName, BalloonRig.BALLOON_DOWN_ATT_NAME)
		)
		balloonModel:Destroy()
		return nil
	end

	local downPart = downAtt.Parent
	if not downPart or not downPart:IsA("BasePart") then
		balloonModel:Destroy()
		return nil
	end

	local rowIndex, slotInRow, rowDef = BalloonRig.resolveRow(index)
	local rowBalloonCount = rowDef.count or 6
	local knotAtt = self:_getKnotAttForBalloon(rowIndex, slotInRow, rowBalloonCount) or self._hubAtt

	local rodLen = self:_rodLengthFromConfig(index)
	balloonModel.Parent = folder
	self:_pivotBalloonAttachmentToWorld(balloonModel, downAtt, self:_computeRodRestDownWorld(index, knotAtt, rodLen))

	rodLen = self:_resolveRodLength(index, knotAtt, downAtt, rodLen)
	self:_snapBalloonToRodRest(balloonModel, knotAtt, downAtt, rodLen)

	balloonModel:SetAttribute("BalloonConfigName", configName)
	balloonModel:SetAttribute("BalloonIndex", index)
	local _pitch, spawnYaw, _roll = balloonModel:GetPivot():ToEulerAnglesYXZ()
	balloonModel:SetAttribute("BalloonLockedYaw", spawnYaw)
	balloonModel:SetAttribute("BalloonRow", rowIndex)
	balloonModel:SetAttribute("BalloonRowSlot", slotInRow)
	balloonModel:SetAttribute("BalloonRowCount", rowBalloonCount)

	self:_applyBalloonNetworkOwner(balloonModel)

	local ropeLen = rodLen + Config.number("BalloonRopeLengthAboveRodStuds", 0.1)
	self:_attachRodAndRope(downAtt, knotAtt, rodLen, ropeLen, rowIndex, slotInRow, rowBalloonCount, index)

	self:_setBalloonAnchored(balloonModel, false)
	self:_zeroBalloonVelocities(balloonModel)

	return balloonModel
end

return BalloonRig
