local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local event = ReplicatedStorage:WaitForChild("IronManSummon")
local lastRequest = 0

UserInputService.InputBegan:Connect(function(input, processed)
  if processed then return end
  if input.KeyCode ~= Enum.KeyCode.E then return end
  if os.clock() - lastRequest < 2 then return end
  lastRequest = os.clock()
  event:FireServer()
end)
