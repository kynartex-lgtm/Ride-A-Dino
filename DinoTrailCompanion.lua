-- Ride a Dino | Luna gameplay companion
-- Uses game client modules and their normal request paths. Luna was discontinued in April 2025.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local ClientRoot = PlayerScripts:WaitForChild("RideADinoClient", 10)
local Modules = ClientRoot and ClientRoot:WaitForChild("Modules", 10)
local GameRoot = ReplicatedStorage:WaitForChild("RideADino", 10)

local function safeRequire(module)
    if not module then return nil end
    local ok, value = pcall(require, module)
    return ok and value or nil
end

local Net = Modules and safeRequire(Modules:FindFirstChild("NetBridge"))
local Ride = Modules and safeRequire(Modules:FindFirstChild("Ride"))
local Track = GameRoot and safeRequire(GameRoot.Config:FindFirstChild("Track"))

local State = {
    AutoTrain = false,
    TrainThreshold = 20,
    InfiniteStamina = true,
    AutoDummy = false,
    AutoPen = false,
    AutoGifts = false,
    AutoOffline = false,
    LowGraphics = false,
    LaneGuard = false,
    CameraLock = false,
    SecretESP = false,
    Zone = nil,
}

local Window

local function notify(title, content)
    pcall(function()
        warn("[Trail Companion] " .. tostring(title) .. ": " .. tostring(content))
    end)
end

local function callNet(name, ...)
    if not Net or type(Net[name]) ~= "function" then
        notify("Module unavailable", "NetBridge." .. name .. " is not available in this client.")
        return false
    end
    local ok, err = pcall(Net[name], ...)
    if not ok then notify("Request failed", err) end
    return ok
end

local function stats()
    if not Net or type(Net.stats) ~= "function" then return nil end
    local ok, value = pcall(Net.stats)
    return ok and type(value) == "table" and value or nil
end

local function stageNames()
    local names = {}
    if Track and type(Track.Stages) == "table" then
        for _, stage in ipairs(Track.Stages) do
            if type(stage) == "table" and type(stage.name) == "string" and stage.name ~= "" then
                if names[#names] ~= stage.name then table.insert(names, stage.name) end
            end
        end
    end
    return names
end

local tameController
local tameOriginalUpdate
local tameWrappedUpdate
local installGeneration = 0

local function isTameController(value)
    return type(value) == "table"
        and type(value.state) == "table"
        and type(value.beginMount) == "function"
        and type(value.hasGrip) == "function"
        and type(value.update) == "function"
end

local function resolveTameController()
    local rideScript = Modules and Modules:FindFirstChild("Ride")
    local tameScript = rideScript and rideScript:FindFirstChild("Tame")
    local controller = tameScript and safeRequire(tameScript)
    if isTameController(controller) then return controller end
    return nil
end

local function setInfiniteStamina(enabled)
    State.InfiniteStamina = enabled
    installGeneration += 1
    local generation = installGeneration

    if not enabled then
        if tameController and tameWrappedUpdate and tameController.update == tameWrappedUpdate then
            tameController.update = tameOriginalUpdate
        end
        if tameController then
            tameController.__TrailCompanionInfiniteGrip = nil
            tameController.infiniteStamina = nil
        end
        tameController, tameOriginalUpdate, tameWrappedUpdate = nil, nil, nil
        return
    end

    task.spawn(function()
        for _ = 1, 20 do
            if generation ~= installGeneration or not State.InfiniteStamina then return end
            local candidate = resolveTameController()
            if candidate then
                local previous = candidate.__TrailCompanionInfiniteGrip
                if type(previous) == "table" and candidate.update == previous.wrapper then
                    candidate.update = previous.original
                end
                local originalUpdate = candidate.update
                local wrappedUpdate
                wrappedUpdate = function(...)
                    local current = candidate.state
                    if type(current) == "table" then
                        current.drain = 0
                        current.gripMax = math.max(tonumber(current.gripMax) or 0, tonumber(current.required) or 0, 1)
                        current.gripLeft = current.gripMax
                        current.rideBudget = (tonumber(current.t) or 0) + 1000000
                        current.calmUntil = current.rideBudget
                    end
                    return originalUpdate(...)
                end
                candidate.update = wrappedUpdate
                candidate.infiniteStamina = true
                candidate.__TrailCompanionInfiniteGrip = {original = originalUpdate, wrapper = wrappedUpdate}
                tameController, tameOriginalUpdate, tameWrappedUpdate = candidate, originalUpdate, wrappedUpdate
                notify("Stamina", "Infinite Grip override enabled.")
                return
            end
            task.wait(1)
        end
        if generation == installGeneration then
            State.InfiniteStamina = false
            notify("Stamina unavailable", "Could not resolve the game's Tame module.")
        end
    end)
end

local Luna = loadstring(game:HttpGet("https://raw.githubusercontent.com/Nebula-Softworks/Luna-Interface-Suite/refs/heads/master/source.lua", true))()
Window = Luna:CreateWindow({
    Name = "Dino Trail Companion",
    LogoID = "6031097225",
    Subtitle = "Stamina • Zones • Performance • Safety",
    LoadingEnabled = true,
    LoadingTitle = "Trail Companion",
    LoadingSubtitle = "Reading game modules...",
    ConfigSettings = {RootFolder = nil, ConfigFolder = "DinoTrailCompanion"},
    KeySystem = false,
})

local Stamina = Window:CreateTab({Name = "Stamina", Icon = "6035121907", ImageSource = "Custom", ShowTitle = true})
Stamina:CreateSection("Grip management")
Stamina:CreateParagraph({Title = "Stamina is Grip", Content = "The live stats expose Grip as an absolute amount, with no maximum/cap field. Auto-train therefore uses an absolute Grip threshold; a 100% setting cannot be calculated from the game data currently exposed. Training requests use the normal machine path and remain server-validated."})
Stamina:CreateButton({Name = "Mount Training Machine", Description = "Requests a normal machine mount at your current position.", Callback = function()
    callNet("machineMount")
end})
Stamina:CreateButton({Name = "Dismount Training Machine", Description = "Uses the game's normal machine dismount request.", Callback = function()
    callNet("machineDismount", "manual")
end})
Stamina:CreateToggle({Name = "Maintain Grip Automatically", Description = "Requests the training machine when Grip falls below the threshold.", CurrentValue = false, Callback = function(value)
    State.AutoTrain = value
end})
Stamina:CreateSlider({Name = "Train Below Grip", Range = {5, 80}, Increment = 5, CurrentValue = 20, Callback = function(value)
    State.TrainThreshold = value
end})
Stamina:CreateToggle({Name = "Infinite Stamina / Grip", Description = "Keeps the client Tame module's grip drain at zero and extends its ride budget. This is client-side and the game may override or reject it.", CurrentValue = true, Callback = setInfiniteStamina})

local Zones = Window:CreateTab({Name = "Zones", Icon = "6023426941", ImageSource = "Custom", ShowTitle = true})
Zones:CreateSection("Course navigation")
local Options = stageNames()
if #Options == 0 then Options = {"Track data unavailable"} end
State.Zone = Options[1]
Zones:CreateDropdown({Name = "Destination", Options = Options, CurrentOption = {State.Zone}, MultipleOptions = false, Callback = function(value)
    State.Zone = type(value) == "table" and value[1] or value
end})
Zones:CreateButton({Name = "Go to Selected Zone", Description = "Uses Ride.teleportTo with the zone's start coordinate from Track.Stages.", Callback = function()
    if not (Track and Ride and type(Ride.teleportTo) == "function") then
        notify("Navigation unavailable", "Track stages or Ride.teleportTo could not be resolved.")
        return
    end
    for _, stage in ipairs(Track.Stages) do
        if stage.name == State.Zone then
            local ok, message = pcall(Ride.teleportTo, stage.z0, stage.name)
            notify("Zone navigation", ok and (message or ("Requested " .. stage.name)) or message)
            return
        end
    end
    notify("Zone unavailable", "The selected stage is not present in Track.Stages.")
end})
Zones:CreateParagraph({Title = "Stage data", Content = "Destinations are loaded from the game's Track configuration, including the repeated Plains segment. If zone travel is locked or unavailable, the game handles that response."})

local Performance = Window:CreateTab({Name = "Performance", Icon = "6026681578", ImageSource = "Custom", ShowTitle = true})
Performance:CreateSection("Local graphics")
local original = {shadows = Lighting.GlobalShadows, parts = {}, decals = {}, effects = {}}
local function setLowGraphics(enabled)
    State.LowGraphics = enabled
    Lighting.GlobalShadows = if enabled then false else original.shadows
    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("BasePart") then
            if enabled then
                if original.parts[object] == nil then original.parts[object] = object.CastShadow end
                object.CastShadow = false
            elseif original.parts[object] ~= nil then
                object.CastShadow = original.parts[object]
                original.parts[object] = nil
            end
        elseif object:IsA("Decal") or object:IsA("Texture") then
            if enabled then
                if original.decals[object] == nil then original.decals[object] = object.Transparency end
                object.Transparency = 1
            elseif original.decals[object] ~= nil then
                object.Transparency = original.decals[object]
                original.decals[object] = nil
            end
        elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Smoke") or object:IsA("Fire") then
            if enabled then
                if original.effects[object] == nil then original.effects[object] = object.Enabled end
                object.Enabled = false
            elseif original.effects[object] ~= nil then
                object.Enabled = original.effects[object]
                original.effects[object] = nil
            end
        end
    end
end
Performance:CreateToggle({Name = "Lightweight Graphics", Description = "Locally reduces shadows, textures, and effects. Turning it off restores recorded values.", CurrentValue = false, Callback = setLowGraphics})
Performance:CreateToggle({Name = "Hide Stampede and Other Riders", Description = "Locally hides the game's herd and peer models; does not change server state.", CurrentValue = false, Callback = function(enabled)
    State.HidePeers = enabled
    for _, folderName in ipairs({"StampedeHerd", "RideADinoPeers"}) do
        local folder = workspace:FindFirstChild(folderName)
        if folder then
            for _, item in ipairs(folder:GetDescendants()) do
                if item:IsA("BasePart") then item.LocalTransparencyModifier = enabled and 1 or 0 end
            end
        end
    end
end})
Performance:CreateButton({Name = "Restore Graphics", Description = "Restores local graphics values recorded by this panel.", Callback = function()
    setLowGraphics(false)
    notify("Performance", "Recorded graphics values restored.")
end})

local Safety = Window:CreateTab({Name = "Safety", Icon = "6035078889", ImageSource = "Custom", ShowTitle = true})
Safety:CreateSection("Fall awareness and recovery")
Safety:CreateParagraph({Title = "How the safety options work", Content = "The inspected client modules expose ride state and lane geometry, but no supported invulnerability or no-fall switch. Lane Guard warns when your character is close to a course edge. The game owns revive handling; this panel does not send revive requests."})
Safety:CreateToggle({Name = "Lane-edge Warning", Description = "Warns when your character approaches the current stage's course edge.", CurrentValue = false, Callback = function(value)
    State.LaneGuard = value
end})

Safety:CreateToggle({Name = "Camera Lock During a Leap", Description = "Keeps the game's camera lock enabled when the native ride module says it is available.", CurrentValue = false, Callback = function(value)
    State.CameraLock = value
    if Ride and type(Ride.cameraLockAvailable) == "function" and type(Ride.setCameraLock) == "function" then
        pcall(function() if value and Ride.cameraLockAvailable() then Ride.setCameraLock(true) end end)
    end
end})

local Upgrades = Window:CreateTab({Name = "Upgrades", Icon = "6031225815", ImageSource = "Custom", ShowTitle = true})
Upgrades:CreateSection("Server-validated purchases")
Upgrades:CreateToggle({Name = "Auto-buy Next Dummy Tier", Description = "Uses NetBridge.buy for the next tier; affordability and unlock checks remain server-side.", CurrentValue = false, Callback = function(value)
    State.AutoDummy = value
end})
Upgrades:CreateToggle({Name = "Auto-upgrade Main Pen", Description = "Requests the normal level-one pen upgrade every 10 seconds while enabled.", CurrentValue = false, Callback = function(value)
    State.AutoPen = value
end})
Upgrades:CreateButton({Name = "Buy Next Dummy Tier Once", Description = "Requests the next tier using the game's NetBridge helper.", Callback = function()
    local current = stats()
    local tier = current and (current.dummyTier or current.dummyLevel) or 1
    callNet("buy", (tonumber(tier) or 1) + 1)
end})
Upgrades:CreateButton({Name = "Upgrade Main Pen Once", Description = "Requests the game's main pen upgrade.", Callback = function()
    callNet("penUpgrade", 1, 1, false)
end})

local QoL = Window:CreateTab({Name = "QoL", Icon = "6031265971", ImageSource = "Custom", ShowTitle = true})
QoL:CreateSection("Secret creature highlights")
QoL:CreateToggle({Name = "Highlight Secret Dinos", Description = "Locally highlights loaded Secret-rarity dinosaur models. The game only exposes models after they stream in.", CurrentValue = false, Callback = function(value)
    State.SecretESP = value
end})
QoL:CreateSection("Rewards")
QoL:CreateToggle({Name = "Auto-claim Gifts", Description = "Checks timed gifts at a low rate using the NetBridge helper.", CurrentValue = false, Callback = function(value)
    State.AutoGifts = value
end})
QoL:CreateToggle({Name = "Auto-claim Offline Income", Description = "Checks offline income at a low rate using the NetBridge helper.", CurrentValue = false, Callback = function(value)
    State.AutoOffline = value
end})
QoL:CreateButton({Name = "Claim Gifts Now", Callback = function() callNet("giftClaim", true) end})
QoL:CreateButton({Name = "Claim Offline Income Now", Callback = function() callNet("offlineClaim") end})
QoL:CreateParagraph({Title = "Status", Content = "Grip: reading… • Stage: " .. tostring(State.Zone)})

-- Secret-rarity roster read from ReplicatedStorage.RideADino.Config.Dinos.
local SecretSpecies = {
    ["Alien Skeleton Boss"] = true,
    ["Barosaurus Skeleton Fossil"] = true,
    ["El Maja"] = true,
    ["King Gorilla"] = true,
    ["King Yeti"] = true,
    ["Magmasaur"] = true,
    ["Qianzhousaurus_Rig"] = true,
    ["Skeletal Rex"] = true,
}
local SecretHighlights = {}
local function isSecretModel(model)
    if not model:IsA("Model") then return false end
    if SecretSpecies[model.Name] then return true end
    local tier = model:GetAttribute("rarity") or model:GetAttribute("tier")
    if type(tier) == "string" and string.lower(tier) == "secret" then return true end
    for _, key in ipairs({"species", "dino", "dinoId", "spec", "specimen", "id"}) do
        local value = model:GetAttribute(key)
        if type(value) == "string" and SecretSpecies[value] then return true end
    end
    return false
end

local function refreshSecretHighlights()
    for model, mark in pairs(SecretHighlights) do
        if not model.Parent or not State.SecretESP or not isSecretModel(model) then
            mark:Destroy()
            SecretHighlights[model] = nil
        end
    end
    if not State.SecretESP then return end
    for index, object in ipairs(workspace:GetDescendants()) do
        if index % 500 == 0 then task.wait() end
        if object:IsA("Model") and isSecretModel(object) and not SecretHighlights[object] then
            local mark = Instance.new("Highlight")
            mark.Name = "TrailCompanionSecretHighlight"
            mark.Adornee = object
            mark.FillColor = Color3.fromRGB(126, 126, 255)
            mark.OutlineColor = Color3.fromRGB(220, 220, 255)
            mark.FillTransparency = 0.55
            mark.OutlineTransparency = 0
            mark.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            mark.Parent = object
            SecretHighlights[object] = mark
        end
    end
end

-- Single, throttled worker. It uses only the game client modules inspected above.
task.spawn(function()
    local lastPen = 0
    local lastGift = 0
    local lastOffline = 0
    local lastTrain = 0
    local lastDummy = 0
    local lastWarn = 0
    local lastUi = 0
    local lastGripNotice = nil
    local lastSecretScan = 0
    while task.wait(0.5) do
        local now = os.clock()
        local current = stats()
        if State.SecretESP and now - lastSecretScan >= 3 then
            lastSecretScan = now
            refreshSecretHighlights()
        end
        if not State.SecretESP and next(SecretHighlights) then
            refreshSecretHighlights()
        end
        if State.AutoTrain and now - lastTrain >= 8 and current and tonumber(current.grip) and current.grip <= State.TrainThreshold then
            lastTrain = now
            callNet("machineMount")
        end
        if State.AutoDummy and current and now - lastDummy >= 5 then
            lastDummy = now
            local tier = tonumber(current.dummyTier or current.dummyLevel) or 1
            if tier < 10 then callNet("buy", tier + 1) end
        end
        if State.AutoPen and now - lastPen >= 10 then
            lastPen = now
            callNet("penUpgrade", 1, 1, false)
        end
        if State.AutoGifts and now - lastGift >= 30 then
            lastGift = now
            callNet("giftClaim", true)
        end
        if State.AutoOffline and now - lastOffline >= 45 then
            lastOffline = now
            callNet("offlineClaim")
        end
        if State.CameraLock and Ride and type(Ride.cameraLockAvailable) == "function" and type(Ride.setCameraLock) == "function" then
            pcall(function() if Ride.cameraLockAvailable() and not Ride.cameraLocked() then Ride.setCameraLock(true) end end)
        end
        if State.LaneGuard and now - lastWarn >= 2 and Track and Ride and type(Ride.courseZ) == "function" then
            local zOk, z = pcall(Ride.courseZ)
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if zOk and type(z) == "number" and root then
                local x = root.Position.X
                local centre = Track.centreX(z)
                local half = Track.laneHalfWidth(z)
                if math.abs(x - centre) >= half - 8 then
                    lastWarn = now
                    notify("Course edge", "You are near the lane edge. Steer toward the center.")
                end
            end
        end
        if now - lastUi >= 5 then
            lastUi = now
            local grip = current and current.grip
            -- Paragraph is intentionally static; current Grip is announced to avoid rebuilding UI controls.
            if grip ~= nil and lastGripNotice ~= grip then
                lastGripNotice = grip
                notify("Grip", tostring(grip) .. (current.gripMax and (" / " .. tostring(current.gripMax)) or ""))
            end
        end
    end
end)

warn("[Trail Companion] Loaded from the game's Track, Ride, and NetBridge modules.")










