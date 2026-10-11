-- Layered R15 Iron Man poses. Does not change flight physics or the suit-up code.
-- Operates on Motor6D.C0 so the pose is visible to other players as well.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local event = RS:FindFirstChild("IronManAnimationAction") or Instance.new("RemoteEvent")
event.Name = "IronManAnimationAction"
event.Parent = RS

local records = {}
local angles = math.rad
local function pose(x, y, z)
    return CFrame.Angles(angles(x), angles(y), angles(z))
end
local function getMotor(character, name)
    for _, item in character:GetDescendants() do
        if item:IsA("Motor6D") and item.Name == name then return item end
    end
    return nil
end
local function prepare(character)
    local joints = {}
    for label, jointName in pairs({leftArm="LeftShoulder",rightArm="RightShoulder",leftLeg="LeftHip",rightLeg="RightHip",waist="Waist",neck="Neck"}) do
        local motor = getMotor(character, jointName)
        if motor then joints[label] = {motor=motor, original=motor.C0} end
    end
    return {character=character,joints=joints,aim=false,previousFlying=false,landUntil=0,landPending=false,lastUpdate=0,blend=0}
end
local function restore(record)
    for _, joint in pairs(record.joints) do
        if joint.motor.Parent then joint.motor.C0 = joint.original end
    end
end
local function unregister(player)
    local r=records[player]
    if r then restore(r);records[player]=nil end
end

event.OnServerEvent:Connect(function(player, action, enabled)
    if action ~= "aim" or typeof(enabled) ~= "boolean" then return end
    local character=player.Character
    if not character or not character:FindFirstChild("AssembledIronManArmor") then return end
    local r=records[player]
    if not r or r.character ~= character then
        r=prepare(character)
        records[player]=r
    end
    r.aim=enabled
end)

local elapsed=0
RunService.Heartbeat:Connect(function(dt)
    elapsed += dt
    if elapsed < 1/30 then return end
    local step=elapsed
    elapsed=0
    local now=os.clock()
    for _, player in Players:GetPlayers() do
        local character=player.Character
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local hasArmor=character and character:FindFirstChild("AssembledIronManArmor")
        local r=records[player]
        if not character or not humanoid or humanoid.Health<=0 or not root or not hasArmor then
            if r then unregister(player) end
            continue
        end
        if not r or r.character~=character then
            if r then unregister(player) end
            r=prepare(character)
            records[player]=r
        end
        local flying=character:GetAttribute("IronManFlying")==true
        local boosting=flying and character:GetAttribute("IronManBoosting")==true
        local velocity=root.AssemblyLinearVelocity
        local speed=velocity.Magnitude
        if r.previousFlying and not flying then
            r.landPending=true
            r.landDeadline=now+3
        end
        if flying then r.landPending=false end
        if r.landPending and (humanoid.FloorMaterial~=Enum.Material.Air or now>(r.landDeadline or 0)) then
            r.landPending=false
            if humanoid.FloorMaterial~=Enum.Material.Air then r.landUntil=now+0.48 end
        end
        r.previousFlying=flying
        local landing=not flying and now<r.landUntil
        local active=flying or landing or r.aim
        local alpha=math.clamp(step*(active and 12 or 9),0,1)
        local aim=r.aim and not boosting
        local t=now
        local offsets={}
        if flying then
            local forward=math.clamp(-root.CFrame.LookVector:Dot(velocity)/100, -1, 1)
            local travel=math.clamp(speed/110,0,1)
            local bank=math.clamp(root.CFrame.RightVector:Dot(velocity)/80,-1,1)
            local rise=math.clamp(velocity.Y/85,-1,1)
            local flutter=math.sin(t*11)*math.min(travel,1)*4
            local base=boosting and 1 or travel
            -- In hover, arms stabilize downward. At speed they sweep behind the suit.
            offsets.leftArm=pose(14+base*64+flutter,0,-14-bank*13)
            offsets.rightArm=pose(14+base*64-flutter,0,14-bank*13)
            offsets.leftLeg=pose(-3-base*12+flutter*0.65,0,-4+bank*6)
            offsets.rightLeg=pose(-3-base*12-flutter*0.65,0,4+bank*6)
            offsets.waist=pose(-base*13-rise*5,0,-bank*8)
            offsets.neck=pose(base*9,0,bank*5)
            if aim then offsets.rightArm=pose(-74,0,7) end
        elseif landing then
            local fraction=math.clamp((r.landUntil-now)/0.48,0,1)
            local impact=math.sin(fraction*math.pi)*1
            offsets.leftArm=pose(32*impact,0,-17*impact)
            offsets.rightArm=pose(-38*impact,0,9*impact)
            offsets.leftLeg=pose(-28*impact,0,-5*impact)
            offsets.rightLeg=pose(39*impact,0,4*impact)
            offsets.waist=pose(-24*impact,0,0)
            offsets.neck=pose(15*impact,0,0)
        elseif aim then
            offsets.rightArm=pose(-83,0,10)
            offsets.leftArm=pose(-12,0,-6)
            offsets.waist=pose(0,-8,0)
        end
        for label, joint in pairs(r.joints) do
            if joint.motor.Parent then
                local desired=joint.original*(offsets[label] or CFrame.identity)
                joint.motor.C0=joint.motor.C0:Lerp(desired,alpha)
            end
        end
    end
end)

Players.PlayerRemoving:Connect(unregister)
Players.PlayerAdded:Connect(function(player)
    player.CharacterRemoving:Connect(function() unregister(player) end)
end)
