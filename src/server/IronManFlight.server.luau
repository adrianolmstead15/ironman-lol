-- Iron Man powered flight. Requires AssembledIronManArmor on an R15 character.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local event = RS:FindFirstChild("IronManFlightControl") or Instance.new("RemoteEvent")
event.Name = "IronManFlightControl"
event.Parent = RS

local NORMAL_SPEED, BOOST_SPEED = 80, 160
local states = {}

local function flames(character)
    local folder = Instance.new("Folder")
    folder.Name = "IronManThrusters"
    folder.Parent = character
    local emitters = {}
    for _, name in {"LeftFoot", "RightFoot", "LeftHand", "RightHand"} do
        local body = character:FindFirstChild(name)
        if body and body:IsA("BasePart") then
            local att = Instance.new("Attachment")
            att.Name = "IronManNozzle"
            att.Position = Vector3.new(0, -body.Size.Y * 0.45, 0)
            att.Parent = body
            local fire = Instance.new("ParticleEmitter")
            fire.Name = "IronManFlame"
            fire.Texture = "rbxasset://textures/particles/fire_main.dds"
            fire.Color = ColorSequence.new(Color3.fromRGB(110,215,255), Color3.fromRGB(255,175,56))
            fire.LightEmission = 1
            fire.Lifetime = NumberRange.new(0.12, 0.25)
            fire.Speed = NumberRange.new(9, 17)
            fire.Rate = 48
            fire.SpreadAngle = Vector2.new(11,11)
            fire.EmissionDirection = Enum.NormalId.Bottom
            fire.Size = NumberSequence.new({NumberSequenceKeypoint.new(0,0.8),NumberSequenceKeypoint.new(0.45,0.6),NumberSequenceKeypoint.new(1,0)})
            fire.Enabled = true
            fire.Parent = att
            table.insert(emitters, fire)
            local light = Instance.new("PointLight")
            light.Color = Color3.fromRGB(105,204,255)
            light.Brightness = 1.2
            light.Range = 7
            light.Parent = att
            table.insert(emitters, light)
            att:SetAttribute("IronManThruster", true)
        end
    end
    return emitters
end

local function stop(player)
    local state = states[player]
    if not state then return end
    states[player] = nil
    for _, connection in state.connections do connection:Disconnect() end
    if state.lv then state.lv:Destroy() end
    if state.ao then state.ao:Destroy() end
    if state.attachment then state.attachment:Destroy() end
    local character = state.character
    if character and character.Parent then
        for _, inst in character:GetDescendants() do
            if inst:IsA("Attachment") and inst:GetAttribute("IronManThruster") then inst:Destroy() end
        end
        local h = character:FindFirstChildOfClass("Humanoid")
        if h and h.Health > 0 then h.PlatformStand = false; h.AutoRotate = true end
        character:SetAttribute("IronManFlying", false)
        character:SetAttribute("IronManBoosting", false)
    end
end

local function start(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local armor = character and character:FindFirstChild("AssembledIronManArmor")
    if not character or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") or not armor or #armor:GetChildren() < 10 then return end
    if states[player] then return end
    local att = Instance.new("Attachment")
    att.Name = "IronManFlightAttachment"
    att.Parent = root
    local lv = Instance.new("LinearVelocity")
    lv.Name = "IronManFlightVelocity"
    lv.Attachment0 = att
    lv.RelativeTo = Enum.ActuatorRelativeTo.World
    lv.VectorVelocity = Vector3.zero
    lv.MaxForce = 1e8
    lv.Parent = root
    local ao = Instance.new("AlignOrientation")
    ao.Name = "IronManFlightFacing"
    ao.Attachment0 = att
    ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
    ao.MaxTorque = 1e8
    ao.Responsiveness = 18
    ao.Parent = root
    humanoid.PlatformStand = true
    humanoid.AutoRotate = false
    character:SetAttribute("IronManFlying", true)
    local thrusterEffects = flames(character)
    local state = {character=character,lv=lv,ao=ao,attachment=att,connections={},lastCommand=os.clock(),targetVelocity=Vector3.zero,boost=false,thrusterEffects=thrusterEffects}
    states[player] = state
    table.insert(state.connections, humanoid.Died:Connect(function() stop(player) end))
    table.insert(state.connections, character.AncestryChanged:Connect(function(_, parent) if not parent then stop(player) end end))
end

event.OnServerEvent:Connect(function(player, action, direction, facing, boost)
    if action == "toggle" then
        if states[player] then stop(player) else start(player) end
        return
    end
    if action ~= "move" then return end
    local state = states[player]
    if not state or player.Character ~= state.character then return end
    if typeof(direction) ~= "Vector3" or typeof(facing) ~= "Vector3" or typeof(boost) ~= "boolean" then return end
    if direction.X ~= direction.X or direction.Y ~= direction.Y or direction.Z ~= direction.Z then return end
    if facing.X ~= facing.X or facing.Y ~= facing.Y or facing.Z ~= facing.Z then return end
    if direction.Magnitude > 1.01 or facing.Magnitude > 1.01 then return end
    state.lastCommand = os.clock()
    state.targetVelocity = direction * (boost and BOOST_SPEED or NORMAL_SPEED)
    state.boost = boost
    state.character:SetAttribute("IronManBoosting", boost and direction.Magnitude > 0.1)
    local flat = Vector3.new(facing.X, 0, facing.Z)
    if flat.Magnitude > 0.05 then
        state.ao.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit) * CFrame.Angles(math.rad(-math.clamp(direction.Y*15, -15, 15)), 0, 0)
    end
end)

-- Smooth acceleration and deceleration; stale input settles into hover.
game:GetService("RunService").Heartbeat:Connect(function(dt)
    for player, state in states do
        if not state.lv.Parent or player.Character ~= state.character then continue end
        if os.clock() - state.lastCommand > 0.6 then
            state.targetVelocity = Vector3.zero
            state.boost = false
            state.character:SetAttribute("IronManBoosting", false)
        end
        local response = state.boost and 4.8 or 3.4
        state.lv.VectorVelocity = state.lv.VectorVelocity:Lerp(state.targetVelocity, 1 - math.exp(-response * dt))
        local speedRatio = math.clamp(state.lv.VectorVelocity.Magnitude / BOOST_SPEED, 0, 1)
        for _, inst in state.thrusterEffects do
            if inst:IsA("ParticleEmitter") and inst.Parent then
                inst.Rate = (state.boost and 115 or 55) + math.floor(22 * speedRatio)
                inst.Speed = NumberRange.new(12 + 20 * speedRatio, 22 + 30 * speedRatio)
            end
        end
    end
end)
Players.PlayerRemoving:Connect(stop)
Players.PlayerAdded:Connect(function(player) player.CharacterRemoving:Connect(function() stop(player) end) end)
