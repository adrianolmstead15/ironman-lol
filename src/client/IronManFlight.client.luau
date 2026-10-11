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
    end
    currentFov = currentFov or camera.FieldOfView
    currentFov += (goalFov - currentFov) * math.clamp(dt * 7, 0, 1)
    camera.FieldOfView = currentFov
end)
player.CharacterAdded:Connect(function()
    table.clear(pressed)
    nextSend = 0
end)
