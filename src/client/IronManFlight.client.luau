-- G flight toggle; WASD travel; Space/Ctrl vertical; LeftShift boost.
-- Camera/FOV are local so other players' cameras never change.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local remote = RS:WaitForChild("IronManFlightControl")
local pressed = {}
local nextSend = 0
local currentFov = nil
local cameraBank = 0
local windAttachment = nil
local windEmitter = nil
local windRoot = nil

local function clearWind()
    if windAttachment then windAttachment:Destroy() end
    windAttachment, windEmitter, windRoot = nil, nil, nil
end

local function createWind(root)
    clearWind()
    local att = Instance.new("Attachment")
    att.Name = "IronManLocalWind"
    att.Position = Vector3.new(0, 0, 2.5)
    att.Parent = root
    local wind = Instance.new("ParticleEmitter")
    wind.Name = "FlightWindStreaks"
    wind.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    wind.Color = ColorSequence.new(Color3.fromRGB(190, 233, 255))
    wind.LightEmission = 0.65
    wind.Lifetime = NumberRange.new(0.16, 0.3)
    wind.Speed = NumberRange.new(16, 29)
    wind.Rate = 0
    wind.SpreadAngle = Vector2.new(160, 160)
    wind.Drag = 0
    wind.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.07), NumberSequenceKeypoint.new(0.5, 0.14), NumberSequenceKeypoint.new(1, 0)})
    wind.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.28), NumberSequenceKeypoint.new(1, 1)})
    wind.Parent = att
    windAttachment, windEmitter, windRoot = att, wind, root
end

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.G then remote:FireServer("toggle") end
    pressed[input.KeyCode] = true
end)
UIS.InputEnded:Connect(function(input) pressed[input.KeyCode] = nil end)

local function down(key) return pressed[Enum.KeyCode[key]] == true end
RunService.RenderStepped:Connect(function(dt)
    local camera = workspace.CurrentCamera
    local character = player.Character
    if not camera then return end
    local flying = character and character:GetAttribute("IronManFlying") == true
    local goalFov = 70
    if flying then
        local look = camera.CFrame.LookVector
        local right = camera.CFrame.RightVector
        local flatLook = Vector3.new(look.X,0,look.Z)
        local flatRight = Vector3.new(right.X,0,right.Z)
        if flatLook.Magnitude > 0.001 then flatLook = flatLook.Unit end
        if flatRight.Magnitude > 0.001 then flatRight = flatRight.Unit end
        local movement = flatLook * ((down("W") and 1 or 0) - (down("S") and 1 or 0))
            + flatRight * ((down("D") and 1 or 0) - (down("A") and 1 or 0))
            + Vector3.yAxis * ((down("Space") and 1 or 0) - (down("LeftControl") and 1 or 0))
        if movement.Magnitude > 1 then movement = movement.Unit end
        local boost = down("LeftShift") or down("RightShift")
        if os.clock() >= nextSend then
            nextSend = os.clock() + 0.065
            remote:FireServer("move", movement, look, boost)
        end
        local root = character:FindFirstChild("HumanoidRootPart")
        local speed = root and root.AssemblyLinearVelocity.Magnitude or 0
        goalFov = 70 + math.clamp(speed / 160, 0, 1) * (boost and 33 or 18)
        if root and windRoot ~= root then createWind(root) end
        if windEmitter then
            local intensity = math.clamp((speed - 28) / 132, 0, 1)
            windEmitter.Rate = math.floor(intensity * (boost and 90 or 38))
            windEmitter.Speed = NumberRange.new(14 + intensity * 22, 20 + intensity * 45)
        end
        local steer = (down("D") and 1 or 0) - (down("A") and 1 or 0)
        cameraBank += ((-steer * math.rad(boost and 3.5 or 2)) - cameraBank) * math.clamp(dt * 4, 0, 1)
    else
        if windAttachment then clearWind() end
        cameraBank += (0 - cameraBank) * math.clamp(dt * 5, 0, 1)
    end
    currentFov = currentFov or camera.FieldOfView
    currentFov += (goalFov - currentFov) * math.clamp(dt * 7, 0, 1)
    camera.FieldOfView = currentFov
end)
-- Apply visual banking after the default Roblox camera has updated.
RunService:BindToRenderStep("IronManCameraBank", Enum.RenderPriority.Camera.Value + 1, function()
    if math.abs(cameraBank) > 0.0002 then
        local cam = workspace.CurrentCamera
        if cam then cam.CFrame = cam.CFrame * CFrame.Angles(0, 0, cameraBank) end
    end
end)
player.CharacterAdded:Connect(function()
    table.clear(pressed)
    nextSend = 0
    currentFov = nil
    cameraBank = 0
    clearWind()
end)
