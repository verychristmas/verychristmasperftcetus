repeat task.wait() until game:IsLoaded()

local getgenv = getgenv or function() return _G end
local genv = getgenv()

local currentSession = tick()
genv.AnimeAstralSession = currentSession

if genv.AnimeAstralExecuted and genv.AnimeAstralSession == currentSession then
    return
end
genv.AnimeAstralExecuted = true

-- ══════════════════════════════════════════════════════════════
-- SERVICES & UTILS
-- ══════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getRootPart()
    local char = getCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- ══════════════════════════════════════════════════════════════
-- FEEDBACK SYSTEM
-- ══════════════════════════════════════════════════════════════

local ENDPOINT = "https://plua.vercel.app/api/l/B9CcLtGyEFcnTVz7b2gt/feedback"
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

local function TryGet(fn)
    local ok, v = pcall(fn)
    return (ok and v) or "unknown"
end

local function SendFeedback(kind, message)
    if not httpRequest then
        return Fluent:Notify({ Title = "Feedback", Content = "Executor has no HTTP support.", Duration = 4 })
    end
    message = tostring(message or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #message < 2 then
        return Fluent:Notify({ Title = "Feedback", Content = "Type a message first.", Duration = 4 })
    end
    local lp = LocalPlayer or Players.LocalPlayer
    task.spawn(function()
        local ok, res = pcall(httpRequest, {
            Url = ENDPOINT,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                type = kind,
                message = message:sub(1, 1000),
                hwid = TryGet(function() return game:GetService("RbxAnalyticsService"):GetClientId() end),
                robloxId = lp and tostring(lp.UserId) or nil,
                robloxName = lp and lp.Name or nil,
                robloxDisplay = lp and lp.DisplayName or nil,
                executor = TryGet(function()
                    local fn = identifyexecutor or getexecutorname
                    return fn and fn()
                end),
            }),
        })
        local sent = ok and res ~= nil and res.StatusCode == 200
        local err
        if not sent and res then pcall(function() err = HttpService:JSONDecode(res.Body).error end) end
        Fluent:Notify({
            Title = "Feedback",
            Content = sent and "Sent — thank you!" or (err or "Could not reach the server."),
            Duration = 4,
        })
    end)
end

-- ══════════════════════════════════════════════════════════════
-- FIXED SERVER HOP LOGIC (GUI Safe)
-- ══════════════════════════════════════════════════════════════

local HOP_HISTORY_FILE = "AnimeAstralHopHistory.json"
local COOLDOWN_TIME = 1800
local serverHistory = {}
local isHopping = false

pcall(function()
    if isfile and isfile(HOP_HISTORY_FILE) then
        local fileData = readfile(HOP_HISTORY_FILE)
        if fileData and fileData ~= "" then
            local decoded = HttpService:JSONDecode(fileData)
            if type(decoded) == "table" then serverHistory = decoded end
        end
    end
end)

local function saveHistory()
    if writefile then
        pcall(function() writefile(HOP_HISTORY_FILE, HttpService:JSONEncode(serverHistory)) end)
    end
end

local function genericServerHop(statusCallback)
    if isHopping then return end
    isHopping = true

    task.spawn(function()
        if statusCallback then statusCallback("Reconnecting (Safe Hop)...") end
        local placeId = game.PlaceId
        local req = httpRequest

        if not req then 
            isHopping = false 
            return 
        end

        task.wait(0.5)

        -- Используем стандартный чистый Teleport, чтобы не ломать клиентский GUI и BridgeNet2
        local success, err = pcall(function()
            TeleportService:Teleport(placeId, LocalPlayer)
        end)

        if not success then
            -- Запасной поиск через публичные инстансы
            local cursor = ""
            local found = false
            for i = 1, 3 do
                local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100%s", tostring(placeId), cursor ~= "" and "&cursor=" .. cursor or "")
                local s, res = pcall(function() return req({ Url = url, Method = "GET" }) end)
                if s and res and res.Body then
                    local data = HttpService:JSONDecode(res.Body)
                    if data and data.data then
                        for _, srv in ipairs(data.data) do
                            if srv.playing < srv.maxPlayers and srv.id ~= game.JobId then
                                TeleportService:TeleportToPlaceInstance(placeId, srv.id, LocalPlayer)
                                found = true
                                break
                            end
                        end
                    end
                end
                if found then break end
                task.wait(1)
            end
        end

        task.wait(5)
        isHopping = false
    end)
end

-- ══════════════════════════════════════════════════════════════
-- COMMANDMENT DETECTION & COLLECTION LOGIC (v1.3.6)
-- ══════════════════════════════════════════════════════════════

local EXACT_10_COMMANDMENTS = {
    "faith", "love", "pacifism", "patience", "piety",
    "purity", "repose", "retience", "reticence", "selflessness", "truth"
}

local collectedObjects = {}

local function isCommandmentModel(obj)
    if not obj or not obj.Parent then return false end
    if collectedObjects[obj] then return false end
    if not obj:IsDescendantOf(workspace) then return false end

    local nameLower = obj.Name:lower()
    local matchFound = false

    for _, cmdName in ipairs(EXACT_10_COMMANDMENTS) do
        if nameLower:find(cmdName) then
            matchFound = true
            break
        end
    end

    if not matchFound then return false end

    local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt or not prompt.Enabled then return false end

    local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
    if not part then return false end

    return true
end

local function interactWithObject(targetObj)
    local char = getCharacter()
    local rootPart = getRootPart()
    if not char or not rootPart or not targetObj or not targetObj.Parent then return false end

    local targetPart = targetObj:IsA("BasePart") and targetObj or targetObj:FindFirstChildWhichIsA("BasePart", true)
    local targetPos = targetPart and targetPart.Position or targetObj:GetPivot().Position

    if not targetPos then return false end

    local standCFrame = CFrame.lookAt(targetPos + Vector3.new(0, 0.5, 1.5), targetPos)

    pcall(function()
        char:PivotTo(standCFrame)
        rootPart.AssemblyLinearVelocity = Vector3.zero
    end)
    
    task.wait(0.15)

    local prompt = targetObj:FindFirstChildWhichIsA("ProximityPrompt", true) 
        or (targetObj.Parent and targetObj.Parent:FindFirstChildWhichIsA("ProximityPrompt", true))

    if prompt then
        pcall(function()
            prompt.RequiresLineOfSight = false
            prompt.MaxActivationDistance = 9999
            prompt.HoldDuration = 0
            prompt.Enabled = true
        end)

        if typeof(fireproximityprompt) == "function" then
            pcall(fireproximityprompt, prompt)
        end

        pcall(function()
            if prompt.InputHoldBegan then
                prompt:InputHoldBegan()
                task.wait(0.05)
                prompt:InputHoldEnded()
            end
        end)

        pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        end)
    end

    if targetPart and typeof(firetouchinterest) == "function" then
        pcall(function()
            firetouchinterest(rootPart, targetPart, 0)
            task.wait(0.05)
            firetouchinterest(rootPart, targetPart, 1)
        end)
    end

    return true
end

local function collectCommandment(targetObj)
    if not targetObj or not targetObj.Parent then return false end

    for attempt = 1, 3 do
        if not targetObj or not targetObj.Parent then return true end
        interactWithObject(targetObj)
        task.wait(0.3)
    end

    collectedObjects[targetObj] = true
    return false
end

-- ══════════════════════════════════════════════════════════════
-- UI SETUP
-- ══════════════════════════════════════════════════════════════

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/perfectusmim1/Pluent/main/dist/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/perfectusmim1/Pluent/main/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/perfectusmim1/Pluent/main/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Anime Astral",
    SubTitle = "v1.3.6 - Teleport GUI Fix",
    TabWidth = 160,
    Size = UDim2.fromOffset(500, 320),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
})

local Tabs = {
    Changelog = Window:AddTab({ Title = "Changelog", Icon = "file-text" }),
    Feedback = Window:AddTab({ Title = "Feedback", Icon = "message-square" }),
    BallCrow = Window:AddTab({ Title = "Ball / Crow", Icon = "disc" }),
    Commandments = Window:AddTab({ Title = "Commandments", Icon = "shield" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

local Options = Fluent.Options

-- Feedback UI
local BugSection = Tabs.Feedback:AddSection("Bug report")
local BugInput = BugSection:AddInput("BugInput", { Title = "Submit", Placeholder = "Describe the bug..." })
BugSection:AddButton({ Title = "Send bug report", Callback = function() SendFeedback("bug", BugInput.Value) end })

-- Commandments Tab
Tabs.Commandments:AddSection("Auto Collect Commandments")
Tabs.Commandments:AddToggle("AutoCollectCommandments", { Title = "Auto Collect Commandments", Default = false })
Tabs.Commandments:AddToggle("AutoCommandmentServerHop", { Title = "Auto Server Hop (Commandments)", Default = false })
local CommandmentStatusParagraph = Tabs.Commandments:AddParagraph({ Title = "Status", Content = "Waiting for activation..." })

-- ══════════════════════════════════════════════════════════════
-- MAIN LOOPS
-- ══════════════════════════════════════════════════════════════

task.spawn(function()
    while task.wait(0.2) do
        if Options.AutoCollectCommandments and Options.AutoCollectCommandments.Value then
            local target = nil
            
            for _, obj in ipairs(workspace:GetDescendants()) do
                if isCommandmentModel(obj) then
                    target = obj
                    break
                end
            end

            if target and target.Parent then
                CommandmentStatusParagraph:SetDesc("Status: Picking up " .. target.Name .. "...")
                collectCommandment(target)
                task.wait(0.2)
            else
                CommandmentStatusParagraph:SetDesc("Status: No items found. Hopping...")
                if Options.AutoCommandmentServerHop and Options.AutoCommandmentServerHop.Value then
                    genericServerHop(function(msg) CommandmentStatusParagraph:SetDesc("Status: " .. msg) end)
                end
            end
        end
    end
end)

-- ══════════════════════════════════════════════════════════════
-- CONFIG INIT
-- ══════════════════════════════════════════════════════════════

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("AnimeAstralConfig")
SaveManager:SetFolder("AnimeAstralConfig/main")

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(4)
Fluent:Notify({ Title = "Anime Astral", Content = "Loaded v1.3.6!", Duration = 4 })
SaveManager:LoadAutoloadConfig()
