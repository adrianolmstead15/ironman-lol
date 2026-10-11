-- R15 Iron Man flight poses. Replaces the previous animation controller.
-- Uses the character's real R15 Motor6D joints so welded armor moves with them.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local action = ReplicatedStorage:FindFirstChild("IronManAnimationAction") or Instance.new("RemoteEvent")
action.Name = "IronManAnimationAction"
action.Parent = ReplicatedStorage

local jointsByPlayer = {}
local desiredAim = {}
local RAD = math.rad
local function rotate(x, y, z)
    return CFrame.Angles(RAD(x), RAD(y), RAD(z))
end

local JOINT_NAMES = {
    leftArm = "LeftShoulder", rightArm = "RightShoulder",
    leftLeg = "LeftHip", rightLeg = "RightHip",
    waist = "Waist", neck = "Neck",
}

local function getJoint(character, name)
    for _, descendant in character:GetDescendants() do
        if descendant:IsA("Motor6D") and descendant.Name == name then
            return descendant
        end
    end
end

local function restore(player)
    local record = jointsByPlayer[player]
    if not record then return end
    for _, entry in record.joints do
        if entry.motor.Parent then entry.motor.C0 = entry.original end
    end
    if record.animate and record.animate.Parent then
        record.animate.Disabled = record.animateWasDisabled
    end
    jointsByPlayer[player] = nil
end

local function setup(player, character)
    local joints = {}
    for label, jointName in JOINT_NAMES do
        local joint = getJoint(character, jointName)
        if joint then joints[label] = {motor = joint, original = joint.C0} end
    end
    local animate = character:FindFirstChild("Animate")
    local count = 0
    for _ in joints do count += 1 end
    print(string.format("Iron Man animations READY for %s: %d/6 R15 joints", player.Name, count))
    return {
        character = character, joints = joints, animate = animate,
        animateWasDisabled = animate and animate.Disabled or false,
        flying = false, lastFlying = false, landingUntil = 0,
    }
end

action.OnServerEvent:Connect(function(player, command, enabled)
    if command == "aim" and typeof(enabled) == "boolean" then
        desiredAim[player] = enabled
    end
end)

-- C0 changes are made on the server so other players see the animated armor too.
RunService.Heartbeat:Connect(function(dt)
    local now = os.clock()
    for _, player in Players:GetPlayers() do
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local assembled = character and character:FindFirstChild("AssembledIronManArmor")
        local record = jointsByPlayer[player]
        if not character or not humanoid or humanoid.Health <= 0 or not root or not assembled then
            if record then restore(player) end
            continue
        end
        if not record or record.character ~= character then
            if record then restore(player) end
            record = setup(player, character)
            jointsByPlayer[player] = record
        end
        local flying = character:GetAttribute("IronManFlying") == true
        local boosting = character:GetAttribute("IronManBoosting") == true
        local speed = root.AssemblyLinearVelocity.Magnitude
        local moving = math.clamp(speed / 100, 0, 1)
        if record.lastFlying and not flying then record.landingUntil = now + 0.5 end
        record.lastFlying = flying
        local landing = not flying and now < record.landingUntil
        local aiming = desiredAim[player] == true and not boosting
        local controlling = flying or landing or aiming
        -- Default Roblox animation tracks can otherwise fight the custom poses.
        if record.animate and record.animate.Parent then
            record.animate.Disabled = controlling or record.animateWasDisabled
        end
        local pose = {}
        if flying then
            local strength = boosting and 1 or moving
            local flutter = math.sin(now * 8) * (boosting and 4 or 2)
            local relative = root.CFrame:VectorToObjectSpace(root.AssemblyLinearVelocity)
            local bank = math.clamp(relative.X / 90, -1, 1)
            pose.leftArm = rotate(22 + strength * 100 + flutter, 0, -22 - bank * 16)
            pose.rightArm = rotate(22 + strength * 100 - flutter, 0, 22 - bank * 16)
            pose.leftLeg = rotate(-8 - strength * 20, 0, -5 + bank * 9)
            pose.rightLeg = rotate(-8 - strength * 20, 0, 5 + bank * 9)
            pose.waist = rotate(-strength * 22, 0, -bank * 13)
            pose.neck = rotate(strength * 13, 0, bank * 4)
            if aiming then pose.rightArm = rotate(-85, 0, 12) end
        elseif landing then
            local progress = math.clamp((record.landingUntil - now) / 0.5, 0, 1)
            local strength = math.sin(progress * math.pi)
            pose.leftArm = rotate(25 * strength, 0, -25 * strength)
            pose.rightArm = rotate(-50 * strength, 0, 8 * strength)
            pose.leftLeg = rotate(-35 * strength, 0, 0)
            pose.rightLeg = rotate(35 * strength, 0, 0)
            pose.waist = rotate(-22 * strength, 0, 0)
        elseif aiming then
            pose.rightArm = rotate(-95, 0, 10)
            pose.leftArm = rotate(-10, 0, -8)
        end
        local blend = 1 - math.exp(-(controlling and 11 or 15) * math.min(dt, 0.1))
        for label, entry in record.joints do
            if entry.motor.Parent then
                entry.motor.C0 = entry.motor.C0:Lerp(entry.original * (pose[label] or CFrame.identity), blend)
            end
        end
    end
end)

Players.PlayerRemoving:Connect(function(player)
    restore(player)
    desiredAim[player] = nil
end)
print("Iron Man animation controller LOADED")
