-- Remote armor assembly. Store the source rig as ServerStorage/IronManArmor.
-- The source rig is NEVER cloned as a character; only decorative parts are used.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local EVENT = ReplicatedStorage:FindFirstChild("IronManSummon") or Instance.new("RemoteEvent")
EVENT.Name = "IronManSummon"
EVENT.Parent = ReplicatedStorage

local TweenService = game:GetService("TweenService")
local MASK_EVENT = ReplicatedStorage:FindFirstChild("IronManMaskToggle") or Instance.new("RemoteEvent")
MASK_EVENT.Name = "IronManMaskToggle"
MASK_EVENT.Parent = ReplicatedStorage
local maskBusy: {[Player]: boolean} = {}
local maskOpen: {[Player]: boolean} = {}

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
  -- Imported armor has both a Model and a MeshPart with the same limb name.
  -- FindFirstChild(name) can return the Model, wrongly excluding that limb.
  for _, child in rig:GetChildren() do
    if child.Name == name and child:IsA("BasePart") then
      return child
    end
  end
  -- Also support imported rigs with their body parts nested in a container.
  for _, child in rig:GetDescendants() do
    if child.Name == name and child:IsA("BasePart") then
      return child
    end
  end
  return nil
end

local function targetForSection(name: string): string
  if name == "Iron Man Helmet" then return "Head" end
  return name
end

-- Collect meshes regardless of whether Toolbox imported them as Models or MeshParts.
-- Many armor assets use a mixed hierarchy, including a generic Model container.
local function armorMeshes(section: Instance): {BasePart}
  local parts: {BasePart} = {}
  if section:IsA("MeshPart") or section:IsA("UnionOperation") then
    table.insert(parts, section)
  end
  for _, inst in section:GetDescendants() do
    if inst:IsA("MeshPart") or inst:IsA("UnionOperation") or (inst:IsA("Part") and inst:FindFirstChildOfClass("SpecialMesh")) then
      table.insert(parts, inst)
    end
  end
  return parts
end

local function nearestBody(sourceRig: Model, mesh: BasePart): string?
  local closest: string? = nil
  local distance = math.huge
  for name in order do
    local bodyName = targetForSection(name)
    local part = findRigPart(sourceRig, bodyName)
    if part then
      local d = (part.Position - mesh.Position).Magnitude
      if d < distance then
        closest, distance = bodyName, d
      end
    end
  end
  return closest
end

local function makeArmorPieces(sourceRig: Model, character: Model): {any}
  local installed = Instance.new("Folder")
  installed.Name = "AssembledIronManArmor"
  installed.Parent = character
  local flightFolder = Instance.new("Folder")
  flightFolder.Name = "IncomingIronManArmor"
  flightFolder.Parent = workspace
  local sectionsByName: {[string]: any} = {}
  local seen: {[Instance]: boolean} = {}

  local function addVisual(sectionName: string, src: BasePart)
    if seen[src] or src.Transparency >= 1 then return end
    local bodyName = targetForSection(sectionName)
    local fromBody = findRigPart(sourceRig, bodyName)
    local toBody = character:FindFirstChild(bodyName)
    if not (fromBody and toBody and toBody:IsA("BasePart")) then return end
    seen[src] = true
    local data = sectionsByName[sectionName]
    if not data then
      local group = Instance.new("Folder")
      group.Name = sectionName
      group.Parent = flightFolder
      data = {
        name = sectionName, body = toBody, group = group, parts = {},
        start = (order[sectionName] or 0.42) * TIME,
        duration = sectionDuration, installed = installed,
      }
      sectionsByName[sectionName] = data
    end
    local dst = src:Clone()
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
    dst.Parent = data.group
    local offset = fromBody.CFrame:ToObjectSpace(src.CFrame)
    table.insert(data.parts, {part = dst, offset = offset, transparency = src.Transparency})
  end

  -- This imported suit uses its R15 rig MeshParts as visible armor, not
  -- just animation anchors. Previous versions excluded these and left only
  -- the separately modeled mask visible.
  for _, bodyPart in sourceRig:GetChildren() do
    if bodyPart:IsA("MeshPart") and order[bodyPart.Name] ~= nil and bodyPart.Name ~= "HumanoidRootPart" then
      addVisual(bodyPart.Name, bodyPart)
    end
  end

  -- Named body armor groups go to their intended limbs.
  for _, child in sourceRig:GetChildren() do
    if order[child.Name] and child:IsA("Model") then
      for _, src in armorMeshes(child) do
        addVisual(child.Name, src)
      end
    end
  end

  -- Catch loose armor meshes stored in generic containers or directly in the rig.
  -- Never duplicate the original rig's R15 body parts or hair/accessories.
  for _, descendant in sourceRig:GetDescendants() do
    if seen[descendant] or not descendant:IsA("BasePart") then continue end
    if not (descendant:IsA("MeshPart") or descendant:IsA("UnionOperation") or descendant:FindFirstChildOfClass("SpecialMesh")) then continue end
    if descendant.Parent == sourceRig and (findRigPart(sourceRig, descendant.Name) == descendant or descendant.Name == "HumanoidRootPart") then continue end
    if descendant:FindFirstAncestorOfClass("Accessory") then continue end
    local section: string? = nil
    local ancestor = descendant.Parent
    while ancestor and ancestor ~= sourceRig do
      if order[ancestor.Name] then section = ancestor.Name; break end
      ancestor = ancestor.Parent
    end
    section = section or nearestBody(sourceRig, descendant)
    if section then
      if order[section] == nil then
        section = section == "Head" and "Iron Man Helmet" or section
      end
      addVisual(section, descendant)
    end
  end

  local sections = {}
  for _, data in sectionsByName do
    table.insert(sections, data)
  end
  table.sort(sections, function(a, b) return a.start < b.start end)
  local total = 0
  for _, section in sections do total += #section.parts end
  print(string.format("Iron Man: prepared %d armor sections, %d visible parts", #sections, total))
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

-- Face accessories are handled separately; armor attached to arms/legs stays hidden.
local function setFaceAccessories(character: Model, visible: boolean)
  local head = character:FindFirstChild("Head")
  if not head or not head:IsA("BasePart") then return end
  for _, accessory in character:GetChildren() do
    if not accessory:IsA("Accessory") then continue end
    local handle = accessory:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then continue end
    local mountedOnHead = false
    for _, joint in handle:GetDescendants() do
      if joint:IsA("JointInstance") and (joint.Part0 == head or joint.Part1 == head) then
        mountedOnHead = true
        break
      end
    end
    if not mountedOnHead then
      for _, attachment in handle:GetChildren() do
        if attachment:IsA("Attachment") and head:FindFirstChild(attachment.Name) then
          mountedOnHead = true
          break
        end
      end
    end
    if not mountedOnHead then continue end
    for _, visual in accessory:GetDescendants() do
      if visual:IsA("BasePart") or visual:IsA("Decal") or visual:IsA("Texture") then
        local original = visual:GetAttribute("IronManOriginalTransparency")
        if visible then
          if typeof(original) == "number" then visual.Transparency = original end
        else
          if original == nil then
            visual:SetAttribute("IronManOriginalTransparency", visual.Transparency)
          end
          visual.Transparency = 1
        end
      end
    end
  end
end

-- Only the movable mask is motor-mounted. Everything else retains the proven weld system.
local function isMovableFaceplate(name: string): boolean
  local normalized = name:lower():gsub("[^a-z]", "")
  return normalized:find("uppermask", 1, true) ~= nil
      or normalized:find("facemask", 1, true) ~= nil
      or normalized:find("faceplate", 1, true) ~= nil
end

-- Hide every fixed front-face layer when opening, including the imported rig's
-- visible Head MeshPart (the old filter missed that piece). The actual player
-- Head remains untouched: this only traverses AssembledIronManArmor.
-- Preserve rear helmet shell parts when they are separately named.
local function setFixedFaceCover(installed: Instance, open: boolean)
  local count = 0
  for _, part in installed:GetDescendants() do
    if not part:IsA("BasePart") or part:GetAttribute("IronManMovableMask") == true then continue end
    local name = part.Name:lower():gsub("[^a-z]", "")
    local rearShell = name:find("back", 1, true)
      or name:find("rear", 1, true)
      or name:find("backshell", 1, true)
    local frontFace = name == "head"
      or name:find("lowermask", 1, true)
      or name:find("uppermask", 1, true)
      or name:find("facecover", 1, true)
      or name:find("facemask", 1, true)
      or name:find("faceplate", 1, true)
      or name:find("eyemask", 1, true)
      or name:find("eyeglow", 1, true)
      or name:find("eyelight", 1, true)
      or name:find("visor", 1, true)
      or name:find("mouth", 1, true)
      or name:find("jaw", 1, true)
      or name:find("chin", 1, true)
    if frontFace and not rearShell then
      count += 1
      local saved = part:GetAttribute("IronManFixedCoverOriginalTransparency")
      if typeof(saved) ~= "number" then
        saved = part.Transparency
        part:SetAttribute("IronManFixedCoverOriginalTransparency", saved)
      end
      part.Transparency = open and 1 or saved
      for _, visual in part:GetDescendants() do
        if visual:IsA("Decal") or visual:IsA("Texture") then
          local prior = visual:GetAttribute("IronManFixedCoverOriginalTransparency")
          if typeof(prior) ~= "number" then
            prior = visual.Transparency
            visual:SetAttribute("IronManFixedCoverOriginalTransparency", prior)
          end
          visual.Transparency = open and 1 or prior
        end
      end
    end
  end
  print(string.format("Iron Man: %s %d fixed face covering meshes", open and "hid" or "restored", count))
end

MASK_EVENT.OnServerEvent:Connect(function(player: Player)
  if active[player] or maskBusy[player] then return end
  local character = player.Character
  if not character then return end
  local installed = character:FindFirstChild("AssembledIronManArmor")
  if not installed then return end
  local faceplateJoints = {}
  for _, part in installed:GetDescendants() do
    if part:IsA("BasePart") and part:GetAttribute("IronManMovableMask") == true then
      local motor = part:FindFirstChild("IronManMaskMotor")
      if motor and motor:IsA("Motor6D") then table.insert(faceplateJoints, motor) end
    end
  end
  if #faceplateJoints == 0 then
    warn("Iron Man: no separate UpperMask/Faceplate mesh was found for opening")
    return
  end
  maskBusy[player] = true
  local opening = not maskOpen[player]
  local info = TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut)
  for _, motor in faceplateJoints do
    local original: CFrame = motor:GetAttribute("ClosedC0") or motor.C0
    -- Pivot at the upper edge of the face. Rotation and lift happen smoothly together.
    local openOffset = CFrame.new(0, 0.35, 0.18) * CFrame.Angles(math.rad(-105), 0, 0)
    TweenService:Create(motor, info, {C0 = original * (opening and openOffset or CFrame.identity)}):Play()
  end
  if opening then
    -- Wait until the moving plate has cleared the face to avoid a visible pop.
    task.delay(0.25, function()
      if player.Character == character and installed.Parent == character then
        setFixedFaceCover(installed, true)
        setFaceAccessories(character, true)
      end
    end)
  else
    setFaceAccessories(character, false)
    setFixedFaceCover(installed, false)
  end
  task.delay(0.58, function()
    if player.Character == character then maskOpen[player] = opening end
    maskBusy[player] = nil
  end)
end)

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
  -- Leave the player's actual body and its textures unchanged.
  -- Only hide accessories attached to the section that has just arrived.
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
    if body.Name == "Head" and isMovableFaceplate(p.Name) then
      local motor = Instance.new("Motor6D")
      motor.Name = "IronManMaskMotor"
      motor.Part0 = body
      motor.Part1 = p
      motor.C0 = item.offset
      motor.C1 = CFrame.identity
      motor:SetAttribute("ClosedC0", item.offset)
      motor.Parent = p
      p:SetAttribute("IronManMovableMask", true)
    else
      local weld = Instance.new("WeldConstraint")
      weld.Part0 = body
      weld.Part1 = p
      weld.Parent = p
    end
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
  maskOpen[player] = nil
  maskBusy[player] = nil
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
  maskOpen[player] = nil
  maskBusy[player] = nil
end)
