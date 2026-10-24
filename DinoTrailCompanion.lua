-- Ride a Dino | WindUI gameplay companion
-- Uses game client modules and normal request paths; WindUI provides the interface.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

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
local DinosConfig = GameRoot and GameRoot.Config and safeRequire(GameRoot.Config:FindFirstChild("Dinos"))
local SpecimenConfig = GameRoot and GameRoot.Config and safeRequire(GameRoot.Config:FindFirstChild("Specimen"))

local RarityAliases = {
    common = "Common", uncommon = "Uncommon", rare = "Rare", epic = "Epic", legendary = "Legendary",
    mythic = "Mythic", cosmic = "Cosmic", secret = "Secret", eternal = "Eternal", divine = "Divine",
}
local RarityOrder = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Cosmic", "Secret", "Eternal", "Divine"}
local MutationOrder = {"None", "Silver", "Golden", "Rainbow", "Magma", "Spectral"}
if SpecimenConfig and type(SpecimenConfig.MUTATION_ORDER) == "table" then
    MutationOrder = SpecimenConfig.MUTATION_ORDER
end
local MutationAliases = {}
for _, mutation in ipairs(MutationOrder) do MutationAliases[string.lower(mutation)] = mutation end
local RarityBySpecies = {}
local FoundRarities = {}
local function collectRarities(value, nameHint, seen)
    if type(value) ~= "table" or seen[value] then return end
    seen[value] = true
    local rawRarity = value.rarity or value.rarityName or value.tier
    local rarity = type(rawRarity) == "string" and RarityAliases[string.lower(rawRarity)] or nil
    if rarity then
        FoundRarities[rarity] = true
        if type(nameHint) == "string" then RarityBySpecies[nameHint] = rarity end
        for _, key in ipairs({"name", "id", "species", "dino", "dinoId", "spec", "specimen"}) do
            local name = value[key]
            if type(name) == "string" then RarityBySpecies[name] = rarity end
        end
    end
    for key, child in pairs(value) do
        if type(child) == "table" then
            collectRarities(child, type(key) == "string" and key or nil, seen)
        end
    end
end
collectRarities(DinosConfig, nil, {})

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
    RarityESP = false,
    ESPRarities = {"Secret"},
    ESPMutations = {"Any"},
    ESPSpecies = {"All species"},
    ESPRadius = 350,
    ESPLabels = false,
    FallSaveRadius = 120,
    AutoFallSave = true,
    Zone = nil,
}

local WindUI
local Window

local function notify(title, content)
    local message = tostring(content)
    if WindUI then
        pcall(function() WindUI:Notify({Title = tostring(title), Content = message, Duration = 3, Icon = "info"}) end)
    else
        warn("[Trail Companion] " .. tostring(title) .. ": " .. message)
    end
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

WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
Window = WindUI:CreateWindow({
    Title = "Dino Trail Companion",
    Icon = "paw-print",
    Author = "Ride a Dino • Stamina, routes, safety, and dino tracking",
    Folder = "DinoTrailCompanion",
    Size = UDim2.fromOffset(780, 590),
    MinSize = Vector2.new(620, 440),
    MaxSize = Vector2.new(1000, 760),
    Theme = "Dark",
    ToggleKey = Enum.KeyCode.RightControl,
    Resizable = true,
    HideSearchBar = false,
    Acrylic = true,
    NewElements = true,
    OpenButton = {Enabled = true, Title = "Open Dino Companion", Icon = "paw-print", OnlyMobile = false, Draggable = true},
})

local ConfigManager = Window.ConfigManager
local ConfigManagerReady = false
if ConfigManager and type(ConfigManager.Init) == "function" then
    local ok, result = pcall(function() return ConfigManager:Init(Window) end)
    ConfigManagerReady = ok and result ~= false
end

local Stamina = Window:Tab({Title = "Stamina", Icon = "battery-charging"})
Stamina:Button({Title = "Mount Training Machine", Desc = "Requests a normal machine mount at your current position.", Callback = function()
    callNet("machineMount")
end})
Stamina:Button({Title = "Dismount Training Machine", Desc = "Uses the game's normal machine dismount request.", Callback = function()
    callNet("machineDismount", "manual")
end})
Stamina:Toggle({Title = "Maintain Grip Automatically", Flag = "MaintainGripAutomatically", Desc = "Requests the training machine when Grip falls below the threshold.", Value = false, Callback = function(value)
    State.AutoTrain = value
end})
Stamina:Slider({Title = "Train Below Grip", Flag = "TrainBelowGrip", Value = {Min = 5, Max = 80, Default = 20}, Step = 5, Callback = function(value)
    State.TrainThreshold = value
end})
Stamina:Toggle({Title = "Infinite Stamina / Grip", Flag = "InfiniteStaminaGrip", Desc = "Keeps the client Tame module's grip drain at zero and extends its ride budget. This is client-side and the game may override or reject it.", Value = true, Callback = setInfiniteStamina})

local Zones = Window:Tab({Title = "Zones", Icon = "map"})
local Options = stageNames()
if #Options == 0 then Options = {"Track data unavailable"} end
State.Zone = Options[1]
Zones:Dropdown({Title = "Destination", Flag = "Destination", Values = Options, Value = State.Zone, Multi = false, SearchBarEnabled = true, Callback = function(value)
    State.Zone = type(value) == "table" and value[1] or value
end})
Zones:Button({Title = "Go to Selected Zone", Desc = "Uses Ride.teleportTo with the zone's start coordinate from Track.Stages.", Callback = function()
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

local Performance = Window:Tab({Title = "Performance", Icon = "gauge"})
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
Performance:Toggle({Title = "Lightweight Graphics", Flag = "LightweightGraphics", Desc = "Locally reduces shadows, textures, and effects. Turning it off restores recorded values.", Value = false, Callback = setLowGraphics})
Performance:Toggle({Title = "Hide Stampede and Other Riders", Flag = "HideStampedeandOtherRiders", Desc = "Locally hides the game's herd and peer models; does not change server state.", Value = false, Callback = function(enabled)
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
Performance:Button({Title = "Restore Graphics", Desc = "Restores local graphics values recorded by this panel.", Callback = function()
    setLowGraphics(false)
    notify("Performance", "Recorded graphics values restored.")
end})

local Safety = Window:Tab({Title = "Safety", Icon = "shield-check"})
Safety:Toggle({Title = "Auto Fall Save", Flag = "AutoFallSave", Desc = "On by default. Saves a fast fall by moving above the nearest loaded dinosaur inside the configurable radius.", Value = true, Callback = function(value)
    State.AutoFallSave = value
end})
Safety:Slider({Title = "Fall Save Range (studs)", Flag = "FallSaveRangestuds", Desc = "Maximum radius to search for a nearby dinosaur during a fall.", Value = {Min = 30, Max = 250, Default = State.FallSaveRadius}, Step = 10, Callback = function(value)
    State.FallSaveRadius = value
end})
Safety:Toggle({Title = "Lane-edge Warning", Flag = "LaneedgeWarning", Desc = "Warns when your character approaches the current stage's course edge.", Value = false, Callback = function(value)
    State.LaneGuard = value
end})

Safety:Toggle({Title = "Camera Lock During a Leap", Flag = "CameraLockDuringaLeap", Desc = "Keeps the game's camera lock enabled when the native ride module says it is available.", Value = false, Callback = function(value)
    State.CameraLock = value
    if Ride and type(Ride.cameraLockAvailable) == "function" and type(Ride.setCameraLock) == "function" then
        pcall(function() if value and Ride.cameraLockAvailable() then Ride.setCameraLock(true) end end)
    end
end})

local Upgrades = Window:Tab({Title = "Upgrades", Icon = "trending-up"})
Upgrades:Toggle({Title = "Auto-buy Next Dummy Tier", Flag = "AutobuyNextDummyTier", Desc = "Uses NetBridge.buy for the next tier; affordability and unlock checks remain server-side.", Value = false, Callback = function(value)
    State.AutoDummy = value
end})
Upgrades:Toggle({Title = "Auto-upgrade Main Pen", Flag = "AutoupgradeMainPen", Desc = "Requests the normal level-one pen upgrade every 10 seconds while enabled.", Value = false, Callback = function(value)
    State.AutoPen = value
end})
Upgrades:Button({Title = "Buy Next Dummy Tier Once", Desc = "Requests the next tier using the game's NetBridge helper.", Callback = function()
    local current = stats()
    local tier = current and (current.dummyTier or current.dummyLevel) or 1
    callNet("buy", (tonumber(tier) or 1) + 1)
end})
Upgrades:Button({Title = "Upgrade Main Pen Once", Desc = "Requests the game's main pen upgrade.", Callback = function()
    callNet("penUpgrade", 1, 1, false)
end})

local QoL = Window:Tab({Title = "Dino Finder", Icon = "sparkles"})
local RarityOptions = {}
for _, rarity in ipairs(RarityOrder) do table.insert(RarityOptions, rarity) end
table.insert(RarityOptions, "All rarities")
for rarity in pairs(FoundRarities) do
    local present = false
    for _, option in ipairs(RarityOptions) do if option == rarity then present = true break end end
    if not present then table.insert(RarityOptions, #RarityOptions, rarity) end
end
QoL:Dropdown({Title = "Rarities", Flag = "Rarities", Desc = "Search and select one or more live rarity tiers.", Values = RarityOptions, Value = State.ESPRarities, Multi = true, SearchBarEnabled = true, AllowNone = true, Callback = function(value)
    State.ESPRarities = normalizeFilterSelection(value, "All rarities")
end})
local function normalizeFilterSelection(value, sentinel)
    local selected = type(value) == "table" and value or {value}
    local hasSentinel = false
    local result = {}
    for _, choice in pairs(selected) do
        if choice == sentinel then hasSentinel = true else table.insert(result, choice) end
    end
    if hasSentinel then return {sentinel} end
    return result
end

local MutationOptions = {"Any"}
for _, mutation in ipairs(MutationOrder) do table.insert(MutationOptions, mutation) end
QoL:Dropdown({Title = "Mutations", Flag = "Mutations", Desc = "Select Any or one or more mutation types.", Values = MutationOptions, Value = State.ESPMutations, Multi = true, SearchBarEnabled = true, AllowNone = true, Callback = function(value)
    State.ESPMutations = normalizeFilterSelection(value, "Any")
end})
local SpeciesOptions = {"All species"}
local speciesSeen = {}
for species in pairs(RarityBySpecies) do
    if not speciesSeen[species] then
        speciesSeen[species] = true
        table.insert(SpeciesOptions, species)
    end
end
table.sort(SpeciesOptions, function(a, b)
    if a == b then return false end
    if a == "All species" then return true end
    if b == "All species" then return false end
    return a:lower() < b:lower()
end)
QoL:Dropdown({Title = "Dinosaur Species", Flag = "DinosaurSpecies", Desc = "Search the live roster and select one or more species.", Values = SpeciesOptions, Value = State.ESPSpecies, Multi = true, SearchBarEnabled = true, AllowNone = true, Callback = function(value)
    State.ESPSpecies = normalizeFilterSelection(value, "All species")
end})
QoL:Slider({Title = "ESP Range (studs)", Flag = "ESPRangestuds", Value = {Min = 50, Max = 1500, Default = State.ESPRadius}, Step = 50, Callback = function(value)
    State.ESPRadius = value
end})
QoL:Toggle({Title = "Show Dino Labels", Flag = "ShowDinoLabels", Desc = "Shows species, rarity, and mutation above each matching model.", Value = State.ESPLabels, Callback = function(value)
    State.ESPLabels = value
end})
QoL:Toggle({Title = "Highlight Matching Dinosaurs", Flag = "HighlightMatchingDinosaurs", Desc = "Highlights streamed models that match all selected filters.", Value = false, Callback = function(value)
    State.RarityESP = value
end})
QoL:Toggle({Title = "Auto-claim Gifts", Flag = "AutoclaimGifts", Desc = "Checks timed gifts at a low rate using the NetBridge helper.", Value = false, Callback = function(value)
    State.AutoGifts = value
end})
QoL:Toggle({Title = "Auto-claim Offline Income", Flag = "AutoclaimOfflineIncome", Desc = "Checks offline income at a low rate using the NetBridge helper.", Value = false, Callback = function(value)
    State.AutoOffline = value
end})
QoL:Button({Title = "Claim Gifts Now", Callback = function() callNet("giftClaim", true) end})
QoL:Button({Title = "Claim Offline Income Now", Callback = function() callNet("offlineClaim") end})

local Configs = Window:Tab({Title = "Configs", Icon = "save"})
local ConfigName = "default"
Configs:Input({Title = "Config name", Value = ConfigName, Callback = function(value)
    local cleaned = tostring(value or ""):gsub("[^%w_-]", ""):sub(1, 32)
    ConfigName = cleaned ~= "" and cleaned or "default"
end})
Configs:Button({Title = "Save Config", Desc = "Saves all flagged toggles, sliders, and dropdowns to a local JSON config.", Callback = function()
    if not ConfigManagerReady then
        notify("Configs unavailable", "This executor does not expose the file APIs WindUI needs.")
        return
    end
    local ok, configOrError = pcall(function()
        return ConfigManager:CreateConfig(ConfigName)
    end)
    if not ok or not configOrError then
        notify("Config save failed", tostring(configOrError))
        return
    end
    local saved, result = pcall(function() return configOrError:Save() end)
    notify(saved and result and "Config saved" or "Config save failed", saved and ("Saved " .. ConfigName) or tostring(result))
end})
Configs:Button({Title = "Load Config", Desc = "Loads the named config and applies saved control values.", Callback = function()
    if not ConfigManagerReady then
        notify("Configs unavailable", "This executor does not expose the file APIs WindUI needs.")
        return
    end
    local ok, configOrError = pcall(function()
        return ConfigManager:CreateConfig(ConfigName)
    end)
    if not ok or not configOrError then
        notify("Config load failed", tostring(configOrError))
        return
    end
    local loaded, result = pcall(function() return configOrError:Load() end)
    notify(loaded and result and "Config loaded" or "Config load failed", loaded and ("Loaded " .. ConfigName) or tostring(result))
end})
Configs:Button({Title = "Delete Config", Desc = "Deletes the named config if the executor supports file deletion.", Callback = function()
    if not ConfigManagerReady or type(ConfigManager.DeleteConfig) ~= "function" then
        notify("Delete unavailable", "Config deletion is not available in this executor.")
        return
    end
    local ok, deleted, message = pcall(ConfigManager.DeleteConfig, ConfigManager, ConfigName)
    notify(ok and deleted and "Config deleted" or "Delete failed", ok and tostring(message or ConfigName) or tostring(deleted))
end})

-- Known Secret species are a fallback for models without a rarity attribute.
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
local RarityHighlights = {}
local RarityLabels = {}
local function speciesId(model)
    for _, key in ipairs({"RunSpecies", "Species", "DinoId", "dinoId", "species", "dino", "spec", "specimen", "id"}) do
        local value = model:GetAttribute(key)
        if type(value) == "string" and value ~= "" then return value end
    end
    if RarityBySpecies[model.Name] or SecretSpecies[model.Name] then return model.Name end
    return nil
end

local function dinoRecord(id)
    if not id or not DinosConfig or type(DinosConfig.byId) ~= "function" then return nil end
    local ok, record = pcall(DinosConfig.byId, id)
    return ok and type(record) == "table" and record or nil
end

local function modelRarity(model)
    if not model:IsA("Model") then return nil end
    for _, key in ipairs({"Rarity", "rarity", "RarityName", "rarityName", "Tier", "tier", "RunTier"}) do
        local value = model:GetAttribute(key)
        if type(value) == "string" and RarityAliases[string.lower(value)] then
            return RarityAliases[string.lower(value)]
        end
    end
    local id = speciesId(model)
    local record = dinoRecord(id)
    local rarity = record and (record.rarity or record.tier)
    if type(rarity) == "string" and RarityAliases[string.lower(rarity)] then
        return RarityAliases[string.lower(rarity)]
    end
    if id and RarityBySpecies[id] then return RarityBySpecies[id] end
    if SecretSpecies[model.Name] then return "Secret" end
    return nil
end

local function modelMutation(model)
    for _, key in ipairs({"RunMutation", "Mutation", "mutation"}) do
        local value = model:GetAttribute(key)
        if type(value) == "string" then
            local normalized = MutationAliases[string.lower(value)]
            if normalized then return normalized end
            if string.lower(value) == "normal" then return "None" end
        end
    end
    return "None"
end

local function hasSelection(values, wanted)
    if type(values) ~= "table" then return values == wanted end
    for key, value in pairs(values) do
        if value == wanted or (key == wanted and value == true) then return true end
    end
    return false
end

local function matchesSelectedRarity(model)
    local rarity = modelRarity(model)
    local matchesRarity = rarity ~= nil and (hasSelection(State.ESPRarities, "All rarities") or hasSelection(State.ESPRarities, rarity))
    local matchesMutation = hasSelection(State.ESPMutations, "Any") or hasSelection(State.ESPMutations, modelMutation(model))
    local species = speciesId(model)
    local matchesSpecies = hasSelection(State.ESPSpecies, "All species") or hasSelection(State.ESPSpecies, species)
    if not (matchesRarity and matchesMutation and matchesSpecies) then return false end
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local ok, position = pcall(function() return model:GetPivot().Position end)
    return ok and (position - root.Position).Magnitude <= State.ESPRadius
end

local function isDinoModel(model)
    return model:IsA("Model") and speciesId(model) ~= nil
end

local RarityColors = {
    Common = Color3.fromRGB(190, 190, 190),
    Uncommon = Color3.fromRGB(110, 220, 120),
    Rare = Color3.fromRGB(85, 160, 255),
    Epic = Color3.fromRGB(185, 100, 255),
    Legendary = Color3.fromRGB(255, 190, 70),
    Mythic = Color3.fromRGB(255, 90, 120),
    Cosmic = Color3.fromRGB(150, 110, 255),
    Secret = Color3.fromRGB(126, 126, 255),
    Eternal = Color3.fromRGB(32, 229, 200),
    Divine = Color3.fromRGB(255, 236, 140),
}

local function refreshRarityHighlights()
    for model, mark in pairs(RarityHighlights) do
        if not model.Parent or not State.RarityESP or not matchesSelectedRarity(model) then
            mark:Destroy()
            RarityHighlights[model] = nil
        end
    end
    for model, label in pairs(RarityLabels) do
        if not model.Parent or not State.RarityESP or not State.ESPLabels or not matchesSelectedRarity(model) then
            label:Destroy()
            RarityLabels[model] = nil
        end
    end
    if not State.RarityESP then return end
    for index, object in ipairs(workspace:GetDescendants()) do
        if index % 500 == 0 then task.wait() end
        if object:IsA("Model") and matchesSelectedRarity(object) and not RarityHighlights[object] then
            local mark = Instance.new("Highlight")
            mark.Title = "TrailCompanionRarityHighlight"
            mark.Adornee = object
            local color = RarityColors[modelRarity(object)] or Color3.fromRGB(255, 255, 255)
            mark.FillColor = color
            mark.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.45)
            mark.FillTransparency = 0.55
            mark.OutlineTransparency = 0
            mark.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            mark.Parent = object
            RarityHighlights[object] = mark
        end
        if object:IsA("Model") and matchesSelectedRarity(object) and State.ESPLabels and not RarityLabels[object] then
            local adornee = object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart", true)
            if adornee then
                local label = Instance.new("BillboardGui")
                label.Name = "TrailCompanionDinoLabel"
                label.Adornee = adornee
                label.Size = UDim2.fromOffset(220, 44)
                label.StudsOffset = Vector3.new(0, 4, 0)
                label.AlwaysOnTop = true
                label.Parent = object
                local text = Instance.new("TextLabel")
                text.BackgroundTransparency = 1
                text.Size = UDim2.fromScale(1, 1)
                text.Font = Enum.Font.GothamSemibold
                text.TextSize = 13
                text.TextColor3 = RarityColors[modelRarity(object)] or Color3.new(1, 1, 1)
                text.TextStrokeTransparency = 0.25
                text.TextWrapped = true
                text.Text = string.format("%s  •  %s\n%s", object.Name, tostring(modelRarity(object) or "Unknown"), modelMutation(object))
                text.Parent = label
                RarityLabels[object] = label
            end
        end
    end
end

local lastFallSaveAttempt = 0
local function tryFallSave()
    if not State.AutoFallSave then return end
    local now = os.clock()
    if now - lastFallSaveAttempt < 1.25 then return end

    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.FloorMaterial ~= Enum.Material.Air then return end
    local humanoidState = humanoid:GetState()
    if humanoidState ~= Enum.HumanoidStateType.Freefall and humanoidState ~= Enum.HumanoidStateType.FallingDown then return end
    if root.AssemblyLinearVelocity.Y > -25 then return end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {character}
    local rayOk, ground = pcall(function()
        return workspace:Raycast(root.Position, Vector3.new(0, -24, 0), rayParams)
    end)
    if not rayOk or not ground or ground.Distance > 22 then return end

    lastFallSaveAttempt = now
    local closestModel, closestDistance, closestBox, closestSize = nil, State.FallSaveRadius, nil, nil
    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("Model") and object ~= character and isDinoModel(object) then
            local ok, box, size = pcall(function() return object:GetBoundingBox() end)
            if ok then
                local distance = (box.Position - root.Position).Magnitude
                if distance < closestDistance then
                    closestModel, closestDistance, closestBox, closestSize = object, distance, box, size
                end
            end
        end
    end

    if closestModel and closestModel.Parent then
        local safePosition = closestBox.Position + Vector3.new(0, closestSize.Y * 0.5 + 3, 0)
        root.CFrame = CFrame.new(safePosition) * root.CFrame.Rotation
        root.AssemblyLinearVelocity = Vector3.zero
        notify("Fall save", "Moved above the nearest nearby dinosaur.")
    end
end
RunService.Heartbeat:Connect(tryFallSave)

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
        if State.RarityESP and now - lastSecretScan >= 3 then
            lastSecretScan = now
            refreshRarityHighlights()
        end
        if not State.RarityESP and next(RarityHighlights) then
            refreshRarityHighlights()
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










