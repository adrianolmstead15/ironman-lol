-- Remote armor assembly. Store the source rig as ServerStorage/IronManArmor.
-- The source rig is NEVER cloned as a character; only decorative parts are used.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local EVENT = ReplicatedStorage:FindFirstChild("IronManSummon") or Instance.new("RemoteEvent")
EVENT.Name = "IronManSummon"
EVENT.Parent = ReplicatedStorage

local TIME = 2.25
local FLIGHT_DISTANCE = 170
local COOLDOWN = 3
local lastUse: {[Player]: number} = {}
local active: {[Player]: boolean} = {}

local order = {
  LeftFoot = 0.05, RightFoot = 0.05,
  LeftLowerLeg = 0.13, RightLowerLeg = 0.13,
  LeftUpperLeg = 0.23, RightUpperLeg = 0.23,
  LowerTorso = 0.33, UpperTorso = 0.42,
  LeftHand = 0.52, RightHand = 0.52,
  LeftLowerArm = 0.59, RightLowerArm = 0.59,
  LeftUpperArm = 0.66, RightUpperArm = 0.66,
  Head = 0.79, ["Iron Man Helmet"] = 0.79,
}
local sectionDuration = 0.27

local function smooth(t: number): number
  t = math.clamp(t, 0, 1)
  -- Fast approach, then a deliberate final lock-on.
  return 1 - (1-t)^3
end

local function findRigPart(rig: Model, name: string): BasePart?
  local obj = rig:FindFirstChild(name)
  if obj and obj:IsA("BasePart") then return obj end
  return nil
end

local function targetForSection(name: string): string
  if name == "Iron Man Helmet" then return "Head" end
  return name
end

local function collectVisuals(section: Instance): {BasePart}
  local visuals: {BasePart} = {}
  for _, inst in section:GetDescendants() do
    if inst:IsA("BasePart") then table.insert(visuals, inst) end
  end
  return visuals
end

local function makeArmorPieces(sourceRig: Model, character: Model): {any}
  local sections = {}
  local installed = Instance.new("Folder")
  installed.Name = "AssembledIronManArmor"
  installed.Parent = character
  local flightFolder = Instance.new("Folder")
  flightFolder.Name = "IncomingIronManArmor"
  flightFolder.Parent = workspace

  for _, section in sourceRig:GetChildren() do
    if not section:IsA("Model") or order[section.Name] == nil then continue end
    local bodyName = targetForSection(section.Name)
    local fromBody = findRigPart(sourceRig, bodyName)
    local toBody = character:FindFirstChild(bodyName)
    if not (fromBody and toBody and toBody:IsA("BasePart")) then continue end
    local sourceVisuals = collectVisuals(section)
    if #sourceVisuals == 0 then continue end

    local group = Instance.new("Folder")
    group.Name = section.Name
    group.Parent = flightFolder
    local parts = {}
    for _, src in sourceVisuals do
      local dst = src:Clone()
      -- Remove constraints/other descendants from imported models.
      for _, child in dst:GetDescendants() do
        if child:IsA("LuaSourceContainer") or child:IsA("JointInstance") or child:IsA("Constraint") then
          child:Destroy()
        end
      end
      dst.Anchored = true
      dst.CanCollide = false
      dst.CanTouch = false
      dst.CanQuery = false
      dst.Massless = true
      dst.Parent = group
      local offset = fromBody.CFrame:ToObjectSpace(src.CFrame)
      table.insert(parts, {part = dst, offset = offset, transparency = src.Transparency})
    end
    table.insert(sections, {
      name = section.Name, body = toBody, group = group, parts = parts,
      start = order[section.Name] * TIME, duration = sectionDuration,
      installed = installed,
    })
  end
  return sections, flightFolder, installed
end

-- Hide only accessories mounted to the body section that just received armor.
-- Leave the player's unrelated accessories alone until their own section arrives.
local function hideAccessoriesForBody(character: Model, body: BasePart)
  for _, accessory in character:GetChildren() do
    if not accessory:IsA("Accessory") then continue end
    local handle = accessory:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then continue end
    local belongs = false
    -- Roblox accessories use AccessoryWeld or other joints connected to a limb.
    for _, descendant in handle:GetDescendants() do
      if descendant:IsA("JointInstance") and (descendant.Part0 == body or descendant.Part1 == body) then
        belongs = true
        break
      end
    end
    if not belongs then
      -- Attachment matching catches accessories whose joint is not exposed yet.
      for _, attachment in handle:GetChildren() do
        if attachment:IsA("Attachment") and body:FindFirstChild(attachment.Name) then
          belongs = true
          break
        end
      end
    end
    if belongs then
      for _, visual in accessory:GetDescendants() do
        if visual:IsA("BasePart") or visual:IsA("Decal") or visual:IsA("Texture") then
          if visual:GetAttribute("IronManOriginalTransparency") == nil then
            visual:SetAttribute("IronManOriginalTransparency", visual.Transparency)
          end
          visual.Transparency = 1
        end
      end
    end
  end
end

local function restoreAccessoryVisibility(character: Model)
  for _, accessory in character:GetChildren() do
    if not accessory:IsA("Accessory") then continue end
    for _, visual in accessory:GetDescendants() do
      if visual:IsA("BasePart") or visual:IsA("Decal") or visual:IsA("Texture") then
        local previous = visual:GetAttribute("IronManOriginalTransparency")
        if typeof(previous) == "number" then
          visual.Transparency = previous
          visual:SetAttribute("IronManOriginalTransparency", nil)
        end
      end
    end
  end
end

local function animateSection(data: any, startTime: number, direction: Vector3, character: Model)
  local body: BasePart = data.body
  local id = data.name
  local seed = string.byte(id, 1) or 1
  local sideways = (seed % 2 == 0 and 1 or -1) * (25 + seed % 18)
  local pathOffset = direction * FLIGHT_DISTANCE + Vector3.new(sideways, 55 + seed % 22, 0)
  local endTime = startTime + data.start + data.duration
  -- Only one effect per section to avoid overwhelming the scene.
  local trail: Trail? = nil
  local first = data.parts[1]
  if first then
    local a0 = Instance.new("Attachment")
    a0.Position = Vector3.new(0, 0.22, 0)
    a0.Name = "IronManFlightTrail"
    a0.Parent = first.part
    local a1 = Instance.new("Attachment")
    a1.Position = Vector3.new(0, -0.22, 0)
    a1.Name = "IronManFlightTrail"
    a1.Parent = first.part
    trail = Instance.new("Trail")
    trail.Attachment0 = a0
    trail.Attachment1 = a1
    trail.Lifetime = 0.11
    trail.MinLength = 0.06
    trail.LightEmission = 0.6
    trail.Color = ColorSequence.new(Color3.fromRGB(115, 225, 255))
    trail.Transparency = NumberSequence.new(0.25, 1)
    trail.Parent = first.part
  end
  local beganAt = startTime + data.start

  while os.clock() < endTime do
    if not character.Parent or not body.Parent then return end
    local rawT = math.clamp((os.clock() - beganAt) / data.duration, 0, 1)
    local t = smooth(rawT)
    local offset = pathOffset * (1-t)
    -- Incoming parts stabilize just before reaching their mounting position.
    local rotation = CFrame.Angles(0, (1-t)*math.rad(100), (1-t)*math.rad(65))
    local base = body.CFrame * CFrame.new(offset) * rotation
    for _, item in data.parts do
      item.part.CFrame = base * item.offset
    end
    RunService.Heartbeat:Wait()
  end

  if not character.Parent or not body.Parent then return end
  -- The armor covers this section now; hide its accessories at this exact moment.
  hideAccessoriesForBody(character, body)
  if trail then trail.Enabled = false end
  for _, item in data.parts do
    local p: BasePart = item.part
    p.CFrame = body.CFrame * item.offset
    p.Transparency = item.transparency
    -- Remove flight effects before welding so trails never remain on worn armor.
    for _, child in p:GetChildren() do
      if child:IsA("Trail") then child:Destroy() end
      if child:IsA("Attachment") and child.Name == "IronManFlightTrail" then child:Destroy() end
    end
    p.Parent = data.installed
    p.Anchored = false
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = body
    weld.Part1 = p
    weld.Parent = p
  end
  data.group:Destroy()
end

EVENT.OnServerEvent:Connect(function(player: Player)
  if active[player] then return end
  local now = os.clock()
  if now - (lastUse[player] or -100) < COOLDOWN then return end
  local character = player.Character
  if not character or not character.Parent then return end
  local humanoid = character:FindFirstChildOfClass("Humanoid")
  local root = character:FindFirstChild("HumanoidRootPart")
  if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 or not root or not root:IsA("BasePart") then
    warn("Iron Man needs an R15 character")
    return
  end
  local rig = ServerStorage:FindFirstChild("IronManArmor")
  if not rig or not rig:IsA("Model") then
    warn("Put IronManArmor model directly into ServerStorage")
    return
  end
  local old = character:FindFirstChild("AssembledIronManArmor")
  if old then old:Destroy() end
  restoreAccessoryVisibility(character)
  active[player] = true
  lastUse[player] = now
  local sections, incoming, installed = makeArmorPieces(rig, character)
  if #sections == 0 then
    warn("No armor visuals found: check model section names and R15 body names")
    incoming:Destroy()
    installed:Destroy()
    active[player] = nil
    return
  end
  local startTime = os.clock()
  local direction = -root.CFrame.LookVector
  local remaining = #sections
  for _, section in sections do
    task.spawn(function()
      task.wait(math.max(0, startTime + section.start - os.clock()))
      animateSection(section, startTime, direction, character)
      remaining -= 1
    end)
  end
  while remaining > 0 and os.clock() - startTime < TIME + 1.5 do task.wait(0.05) end
  incoming:Destroy()
  active[player] = nil
end)

Players.PlayerRemoving:Connect(function(player)
  active[player] = nil
  lastUse[player] = nil
end)
