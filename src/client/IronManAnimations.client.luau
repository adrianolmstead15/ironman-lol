-- Hold left mouse to strike a repulsor aiming pose; no damage is applied yet.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RS=game:GetService("ReplicatedStorage")
local event=RS:WaitForChild("IronManAnimationAction")
local player=Players.LocalPlayer
local held=false
UIS.InputBegan:Connect(function(input, processed)
    if processed or input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    local character=player.Character
    if character and character:FindFirstChild("AssembledIronManArmor") then
        held=true
        event:FireServer("aim",true)
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 and held then
        held=false
        event:FireServer("aim",false)
    end
end)
player.CharacterAdded:Connect(function() held=false end)
