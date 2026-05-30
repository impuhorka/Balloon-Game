local ShooterMotors = {}

ShooterMotors.LEFT_IS_FRONT_OFFSET = math.pi / 2

function ShooterMotors.GetAttrNumber(model: Model, name: string, default: number): number
	return tonumber(model:GetAttribute(name)) or default
end

function ShooterMotors.FindByPart1(model: Model, part: BasePart, exclude: Motor6D?): Motor6D?
	for _, desc in model:GetDescendants() do
		if desc:IsA("Motor6D") and desc ~= exclude and desc.Part1 == part then
			return desc
		end
	end
	return nil
end

function ShooterMotors.FindByPart(model: Model, part: BasePart, exclude: Motor6D?): Motor6D?
	for _, desc in model:GetDescendants() do
		if desc:IsA("Motor6D") and desc ~= exclude and (desc.Part1 == part or desc.Part0 == part) then
			return desc
		end
	end
	return nil
end

function ShooterMotors.FindFirstOnPart(part: BasePart): Motor6D?
	for _, child in part:GetChildren() do
		if child:IsA("Motor6D") then
			return child
		end
	end
	return nil
end

function ShooterMotors.CacheC1(motor: Motor6D): (Vector3, CFrame)
	return motor.C1.Position, motor.C1
end

function ShooterMotors.GetJointCFrame(motor: Motor6D): CFrame?
	local part0 = motor.Part0
	if not part0 then
		return nil
	end
	return part0.CFrame * motor.C0
end

function ShooterMotors.GetTargetC1Y(motor: Motor6D, targetPos: Vector3, yawOffset: number): number?
	local jointCF = ShooterMotors.GetJointCFrame(motor)
	if not jointCF then
		return nil
	end

	local localTarget = jointCF:PointToObjectSpace(targetPos)
	local flat = Vector3.new(localTarget.X, 0, localTarget.Z)
	if flat.Magnitude < 0.001 then
		return nil
	end

	return math.atan2(flat.X, -flat.Z) + yawOffset
end

function ShooterMotors.GetTargetC1Z(
	motor: Motor6D?,
	targetPos: Vector3,
	minPitch: number,
	maxPitch: number,
	pitchOffset: number,
	clampOnly: boolean
): number?
	local jointCF = motor and ShooterMotors.GetJointCFrame(motor)
	if not jointCF then
		return nil
	end

	local localTarget = jointCF:PointToObjectSpace(targetPos)
	local horizontal = math.sqrt(localTarget.X * localTarget.X + localTarget.Z * localTarget.Z)
	if horizontal < 0.001 then
		return nil
	end

	local pitch = math.atan2(localTarget.Y, horizontal)
	local targetZ = pitch + pitchOffset
	if clampOnly then
		return math.clamp(targetZ, minPitch, maxPitch)
	end
	if targetZ < minPitch or targetZ > maxPitch then
		return nil
	end
	return targetZ
end

function ShooterMotors.GetTargetC1X(
	motor: Motor6D?,
	targetPos: Vector3,
	minPitch: number,
	maxPitch: number,
	pitchOffset: number,
	clampOnly: boolean
): number?
	local jointCF = motor and ShooterMotors.GetJointCFrame(motor)
	if not jointCF then
		return nil
	end

	local localTarget = jointCF:PointToObjectSpace(targetPos)
	local horizontal = math.sqrt(localTarget.X * localTarget.X + localTarget.Z * localTarget.Z)
	if horizontal < 0.001 then
		return nil
	end

	local targetX = -math.atan2(localTarget.Y, horizontal) + pitchOffset
	if clampOnly then
		return math.clamp(targetX, minPitch, maxPitch)
	end
	if targetX < minPitch or targetX > maxPitch then
		return nil
	end
	return targetX
end

function ShooterMotors.GetAdaptiveStep(model: Model?, baseStep: number, deltaRad: number): number
	local minDeg = 10
	local maxDeg = 90
	local maxMult = 3
	if model then
		minDeg = ShooterMotors.GetAttrNumber(model, "TurnBoostMinDeg", minDeg)
		maxDeg = ShooterMotors.GetAttrNumber(model, "TurnBoostMaxDeg", maxDeg)
		maxMult = ShooterMotors.GetAttrNumber(model, "TurnBoostMaxMult", maxMult)
	end

	local absDelta = math.abs(deltaRad)
	local minRad = math.rad(minDeg)
	local maxRad = math.rad(maxDeg)
	if absDelta <= minRad or maxRad <= minRad then
		return baseStep
	end

	local t = math.clamp((absDelta - minRad) / (maxRad - minRad), 0, 1)
	return baseStep * (1 + t * (maxMult - 1))
end

function ShooterMotors.ClampDelta(delta: number, baseStep: number, model: Model?, adaptive: boolean): number
	local step = if adaptive then ShooterMotors.GetAdaptiveStep(model, baseStep, delta) else baseStep
	if delta > step then
		return step
	end
	if delta < -step then
		return -step
	end
	return delta
end

function ShooterMotors.ApplyC1Y(motor: Motor6D, restPos: Vector3, targetY: number, baseStep: number, model: Model?, adaptive: boolean?): ()
	local _, currentY, _ = motor.C1:ToEulerAnglesYXZ()
	local delta = (targetY - currentY) % (math.pi * 2)
	if delta > math.pi then
		delta -= math.pi * 2
	elseif delta < -math.pi then
		delta += math.pi * 2
	end
	delta = ShooterMotors.ClampDelta(delta, baseStep, model, adaptive ~= false)
	motor.C1 = CFrame.new(restPos) * CFrame.Angles(0, currentY + delta, 0)
end

function ShooterMotors.ApplyC1Z(motor: Motor6D, restPos: Vector3, restX: number, restY: number, targetZ: number, baseStep: number, model: Model?, adaptive: boolean?): ()
	local _, _, currentZ = motor.C1:ToEulerAnglesYXZ()
	local delta = ShooterMotors.ClampDelta(targetZ - currentZ, baseStep, model, adaptive ~= false)
	motor.C1 = CFrame.new(restPos) * CFrame.Angles(restX, restY, currentZ + delta)
end

function ShooterMotors.ApplyC1X(motor: Motor6D, restPos: Vector3, restY: number, restZ: number, targetX: number, baseStep: number, model: Model?, adaptive: boolean?): ()
	local currentX, _, _ = motor.C1:ToEulerAnglesYXZ()
	local delta = ShooterMotors.ClampDelta(targetX - currentX, baseStep, model, adaptive ~= false)
	motor.C1 = CFrame.new(restPos) * CFrame.Angles(currentX + delta, restY, restZ)
end

return ShooterMotors
