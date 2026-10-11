-- Complement to existing faceplate script: hide eye lenses AND their light effects.
-- Does not touch the player's real face or the movable mask.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local toggle = RS:WaitForChild("IronManMaskToggle")
local states = {}
local saved = setmetatable({}, {__mode="k"})

local function isEyeLayer(part)
    local n = part.Name:lower():gsub("[^a-z0-9]", "")
    return n:find("eye",1,true) ~= nil or n:find("lens",1,true) ~= nil
        or n:find("optic",1,true) ~= nil or n:find("eyeglow",1,true) ~= nil
end

local function apply(character, isOpen)
    local armor = character:FindFirstChild("AssembledIronManArmor")
    if not armor then return end
    local head = character:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then return end
    for _, part in armor:GetDescendants() do
        if not part:IsA("BasePart") or not isEyeLayer(part) then continue end
        -- Restrict changes to the head so an unrelated glowing suit part is untouched.
        if (part.Position-head.Position).Magnitude > 5 then continue end
        for _, inst in {part, table.unpack(part:GetDescendants())} do
            if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
                if saved[inst] == nil then saved[inst] = inst.Transparency end
                inst.Transparency = isOpen and 1 or saved[inst]
            elseif inst:IsA("Light") or inst:IsA("Beam") or inst:IsA("ParticleEmitter") then
                if saved[inst] == nil then saved[inst] = inst.Enabled end
                inst.Enabled = not isOpen and saved[inst] or false
            end
        end
    end
end

toggle.OnServerEvent:Connect(function(player)
    local character = player.Character
    if not character or not character:FindFirstChild("AssembledIronManArmor") then return end
    if not states[player] or states[player].character ~= character then
        states[player] = {character=character, open=false, busy=false}
    end
    local state = states[player]
    if state.busy then return end
    state.busy = true
    local opening = not state.open
    task.delay(opening and 0.3 or 0, function()
        if player.Character == character then apply(character, opening) end
    end)
    task.delay(0.6, function()
        if states[player] == state then state.open=opening; state.busy=false end
    end)
end)
Players.PlayerRemoving:Connect(function(player) states[player]=nil end)
