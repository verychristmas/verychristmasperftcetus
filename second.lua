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
-- SERVER HOP LOGIC
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
        if statusCallback then statusCallback("Searching for new server...") end
        local placeId = game.PlaceId
        local currentJobId = game.JobId
        local cursor = ""
        local foundServer = false
        local req = httpRequest

        if not req then 
            isHopping = false 
            return 
        end

        local attempts = 0
        while not foundServer and attempts < 6 do
            attempts = attempts + 1
            local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100%s", tostring(placeId), cursor ~= "" and "&cursor=" .. cursor or "")
            local success, response = pcall(function() return req({ Url = url, Method = "GET" }) end)

            if success and response and response.Body then
                local data
                pcall(function() data = HttpService:JSONDecode(response.Body) end)

                if data and data.data then
                    local validServers = {}
                    for _, server in ipairs(data.data) do
                        if server.playing < server.maxPlayers and server.id ~= currentJobId then
                            if not (serverHistory[server.id] and (os.time() - serverHistory[server.id]) < COOLDOWN_TIME) then
                                table.insert(validServers, server)
                            end
                        end
                    end

                    if #validServers > 0 then
                        local randomServer = validServers[math.random(1, #validServers)]
                        if statusCallback then statusCallback("Teleporting...") end
                        serverHistory[currentJobId] = os.time()
                        saveHistory()
                        pcall(function()
                            TeleportService:TeleportToPlaceInstance(placeId, randomServer.id, LocalPlayer)
                        end)
                        foundServer = true
                        break
                    end

                    if not foundServer and data.nextPageCursor then
                        cursor = data.nextPageCursor
                    else
                        serverHistory = {}
                        saveHistory()
                        break
                    end
                end
            else
                break
            end
            task.wait(0.3)
        end

        if not foundServer then
            serverHistory = {}
            saveHistory()
            pcall(function() TeleportService:Teleport(placeId, LocalPlayer) end)
        end

        task.wait(2)
        isHopping = false
    end)
end

-- ══════════════════════════════════════════════════════════════
-- COMMANDMENT DETECTION & COLLECTION (v1.1.0)
-- ══════════════════════════════════════════════════════════════

local EXACT_10_COMMANDMENTS = {
    "faith", "love", "pacifism", "patience", "piety",
    "purity", "repose", "retience", "reticence", "selflessness", "truth"
}

local IGNORE_KEYWORDS = {
    "portal", "raid", "gate", "door", "zone", "teleport", 
    "shop", "npc", "spawn", "gui", "ui", "hud", "asta", 
    "quest", "dialog", "humanoid", "player", "clover", "machine",
    "button", "board", "stat"
}

local collectedObjects = {}

local function isCommandmentModel(obj)
    if not obj or not obj.Parent then return false end
    if collectedObjects[obj] then return false end

    -- Фильтр UI
    if obj:IsA("UIComponent") or obj:IsA("GuiObject") or obj:IsA("LayerCollector") then return false end
    if obj:IsDescendantOf(workspace.CurrentCamera) or obj:IsDescendantOf(game:GetService("CoreGui")) then return false end

    -- Фильтр Персонажей и NPC
    if obj:FindFirstChildOfClass("Humanoid") then return false end
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and obj:IsDescendantOf(player.Character) then
            return false
        end
    end

    local fullNameLower = obj:GetFullName():lower()

    -- Игнорируем объекты карты по чёрному списку
    for _, badWord in ipairs(IGNORE_KEYWORDS) do
        if fullNameLower:find(badWord) then
            return false
        end
    end

    -- Проверка на наличие имени заповеди
    local matchFound = false
    local nameLower = obj.Name:lower()

    for _, cmdName in ipairs(EXACT_10_COMMANDMENTS) do
        if nameLower:find(cmdName) then
            matchFound = true
            break
        end
    end

    if not matchFound then return false end

    return obj:IsA("Model") or obj:IsA("BasePart") or obj:IsA("Tool")
end

local function collectCommandment(targetObj)
    if not targetObj or not targetObj.Parent or collectedObjects[targetObj] then return false end
    local char = getCharacter()
    local rootPart = getRootPart()
    if not char or not rootPart then return false end

    -- Помечаем объект как обработанный, чтобы избегать бесконечных циклов
    collectedObjects[targetObj] = true
    warn("[ANIME ASTRAL v1.1.0] Collecting target: " .. targetObj:GetFullName())

    local targetCFrame
    if targetObj:IsA("Model") then
        local part = targetObj.PrimaryPart or targetObj:FindFirstChildWhichIsA("BasePart", true)
        targetCFrame = part and part.CFrame or targetObj:GetPivot()
    elseif targetObj:IsA("BasePart") then
        targetCFrame = targetObj.CFrame
    end

    if not targetCFrame then return false end

    -- 1. ТП прямо к предмету
    pcall(function()
        char:PivotTo(targetCFrame)
        rootPart.AssemblyLinearVelocity = Vector3.zero
    end)
    
    -- Задержка 0.15с, чтобы сервер синхронизировал позицию игрока!
    task.wait(0.15)

    -- 2. Взаимодействие через ProximityPrompt (всеми способами)
    local prompt = targetObj:FindFirstChildWhichIsA("ProximityPrompt", true) 
        or (targetObj.Parent and targetObj.Parent:FindFirstChildWhichIsA("ProximityPrompt", true))

    if prompt then
        pcall(function()
            prompt.RequiresLineOfSight = false
            prompt.MaxActivationDistance = 9999
            prompt.HoldDuration = 0
        end)

        -- Метод 1: Native Fire
        if typeof(fireproximityprompt) == "function" then
            pcall(fireproximityprompt, prompt)
        end

        -- Метод 2: Direct Hold Signals
        pcall(function()
            if prompt.InputHoldBegan then
                prompt:InputHoldBegan()
                task.wait(0.05)
                prompt:InputHoldEnded()
            end
        end)

        -- Метод 3: Key Simulation
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        end)
    end

    -- 3. Взаимодействие через TouchInterest
    local targetPart = targetObj:IsA("BasePart") and targetObj or targetObj:FindFirstChildWhichIsA("BasePart", true)
    if targetPart and typeof(firetouchinterest) == "function" then
        pcall(function()
            firetouchinterest(rootPart, targetPart, 0)
            task.wait(0.05)
            firetouchinterest(rootPart, targetPart, 1)
        end)
    end

    -- Пауза для получения ответа от сервера
    task.wait(0.4)

    -- Удаляем объект локально, если он оказался фантомом
    if targetObj and targetObj.Parent then
        pcall(function() targetObj:Destroy() end)
    end

    return true
end

-- ══════════════════════════════════════════════════════════════
-- UI SETUP
-- ══════════════════════════════════════════════════════════════

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/perfectusmim1/Pluent/main/dist/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/perfectusmim1/Pluent/main/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/perfectusmim1/Pluent/main/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Anime Astral",
    SubTitle = "v1.1.0 - Desync & Prompt Fix",
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

-- Ball / Crow Tab
Tabs.BallCrow:AddSection("Auto Collect Special Items")
Tabs.BallCrow:AddToggle("AutoCollectBall", { Title = "Auto Collect Ball", Default = false })
Tabs.BallCrow:AddToggle("AutoBallServerHop", { Title = "Auto Server Hop (Ball)", Default = false })
local BallStatusParagraph = Tabs.BallCrow:AddParagraph({ Title = "Status", Content = "Waiting for activation..." })

Tabs.BallCrow:AddToggle("AutoCollectCrow", { Title = "Auto Collect Crow", Default = false })
Tabs.BallCrow:AddToggle("AutoCrowServerHop", { Title = "Auto Server Hop (Crow)", Default = false })

-- Commandments Tab
Tabs.Commandments:AddSection("Auto Collect Commandments")
Tabs.Commandments:AddToggle("AutoCollectCommandments", { Title = "Auto Collect Commandments", Default = false })
Tabs.Commandments:AddToggle("AutoCommandmentServerHop", { Title = "Auto Server Hop (Commandments)", Default = false })
local CommandmentStatusParagraph = Tabs.Commandments:AddParagraph({ Title = "Status", Content = "Waiting for activation..." })

-- ══════════════════════════════════════════════════════════════
-- MAIN LOOPS
-- ══════════════════════════════════════════════════════════════

-- Флаг первичной прогрузки сервера
local serverLoadedTime = tick()

-- Ball / Crow Loop
task.spawn(function()
    while task.wait(0.2) do
        if Options.AutoCollectBall and Options.AutoCollectBall.Value then
            local found = false
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj.Name:lower():find("ball") and not isCommandmentModel(obj) and obj:FindFirstChildWhichIsA("ProximityPrompt", true) then
                    found = true
                    BallStatusParagraph:SetDesc("Status: Collecting Ball (" .. obj.Name .. ")")
                    collectCommandment(obj)
                    if Options.AutoBallServerHop and Options.AutoBallServerHop.Value then
                        genericServerHop(function(msg) BallStatusParagraph:SetDesc("Status: " .. msg) end)
                    end
                    break
                end
            end
            if not found and (tick() - serverLoadedTime > 1.5) then
                BallStatusParagraph:SetDesc("Status: No Ball found on this server.")
                if Options.AutoBallServerHop and Options.AutoBallServerHop.Value then
                    genericServerHop(function(msg) BallStatusParagraph:SetDesc("Status: " .. msg) end)
                end
            end
        end

        if Options.AutoCollectCrow and Options.AutoCollectCrow.Value then
            local found = false
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj.Name:lower():find("crow") and not isCommandmentModel(obj) and obj:FindFirstChildWhichIsA("ProximityPrompt", true) then
                    found = true
                    BallStatusParagraph:SetDesc("Status: Collecting Crow (" .. obj.Name .. ")")
                    collectCommandment(obj)
                    if Options.AutoCrowServerHop and Options.AutoCrowServerHop.Value then
                        genericServerHop(function(msg) BallStatusParagraph:SetDesc("Status: " .. msg) end)
                    end
                    break
                end
            end
            if not found and (tick() - serverLoadedTime > 1.5) then
                BallStatusParagraph:SetDesc("Status: No Crow found on this server.")
                if Options.AutoCrowServerHop and Options.AutoCrowServerHop.Value then
                    genericServerHop(function(msg) BallStatusParagraph:SetDesc("Status: " .. msg) end)
                end
            end
        end
    end
end)

-- Commandments Loop
task.spawn(function()
    while task.wait(0.25) do
        if Options.AutoCollectCommandments and Options.AutoCollectCommandments.Value then
            local target = nil
            
            for _, obj in ipairs(workspace:GetDescendants()) do
                if isCommandmentModel(obj) then
                    target = obj
                    break
                end
            end

            if target and target.Parent then
                CommandmentStatusParagraph:SetDesc("Status: FOUND " .. target.Name .. "! Collecting...")
                collectCommandment(target)
                task.wait(0.3)
            else
                -- Ждем минимум 1.5 сек с момента входа на сервер, чтобы исключить несформированный workspace
                if (tick() - serverLoadedTime > 1.5) then
                    CommandmentStatusParagraph:SetDesc("Status: No Commandments found. Hopping...")
                    if Options.AutoCommandmentServerHop and Options.AutoCommandmentServerHop.Value then
                        genericServerHop(function(msg) CommandmentStatusParagraph:SetDesc("Status: " .. msg) end)
                    end
                else
                    CommandmentStatusParagraph:SetDesc("Status: Waiting for workspace stream...")
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
Fluent:Notify({ Title = "Anime Astral", Content = "Loaded v1.1.0 - Desync Fix!", Duration = 4 })
SaveManager:LoadAutoloadConfig()
