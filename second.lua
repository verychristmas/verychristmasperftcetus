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
-- COMMANDMENT DETECTION & COLLECTION LOGIC (v1.3.3)
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

    -- Проверяем, находится ли объект в специальной папке или воркспейсе
    local isTargetFolder = obj:IsDescendantOf(workspace:FindFirstChild("World12Commandments") or workspace)
    if not isTargetFolder then return false end

    local nameLower = obj.Name:lower()
    local matchFound = false

    for _, cmdName in ipairs(EXACT_10_COMMANDMENTS) do
        if nameLower:find(cmdName) then
            matchFound = true
            break
        end
    end

    if not matchFound then return false end

    -- Ищем ProximityPrompt внутри
    local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    return prompt ~= nil
end

local function collectCommandment(targetObj)
    if not targetObj or not targetObj.Parent or collectedObjects[targetObj] then return false end
    local char = getCharacter()
    local rootPart = getRootPart()
    if not char or not rootPart then return false end

    local targetPos
    if targetObj:IsA("Model") then
        local part = targetObj.PrimaryPart or targetObj:FindFirstChildWhichIsA("BasePart", true)
        targetPos = part and part.Position or targetObj:GetPivot().Position
    elseif targetObj:IsA("BasePart") then
        targetPos = targetObj.Position
    end

    if not targetPos then return false end

    -- ТП прямо к предмету (чуть выше и с поворотом)
    local standCFrame = CFrame.lookAt(targetPos + Vector3.new(0, 1, 2), targetPos)

    pcall(function()
        char:PivotTo(standCFrame)
        rootPart.AssemblyLinearVelocity = Vector3.zero
    end)
    
    -- Даём 0.3 сек серверу зарегистрировать персонажа рядом
    task.wait(0.3)

    local prompt = targetObj:FindFirstChildWhichIsA("ProximityPrompt", true) 
        or (targetObj.Parent and targetObj.Parent:FindFirstChildWhichIsA("ProximityPrompt", true))

    if prompt then
        pcall(function()
            prompt.RequiresLineOfSight = false
            prompt.MaxActivationDistance = 9999
            prompt.HoldDuration = 0
            prompt.Enabled = true
        end)

        task.wait(0.05)

        -- Вызов ProximityPrompt
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

    -- Дополнительно: касание хитбокса
    local targetPart = targetObj:IsA("BasePart") and targetObj or targetObj:FindFirstChildWhichIsA("BasePart", true)
    if targetPart and typeof(firetouchinterest) == "function" then
        pcall(function()
            firetouchinterest(rootPart, targetPart, 0)
            task.wait(0.05)
            firetouchinterest(rootPart, targetPart, 1)
        end)
    end

    -- Ждем ответа от сервера
    task.wait(0.8)

    -- Если объект всё ещё существует после попытки, заносим в собранные на этом сервере, чтоб не спамить
    if targetObj and targetObj.Parent then
        collectedObjects[targetObj] = true
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
    SubTitle = "v1.3.3 - World12 Fix & Prompt Fix",
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

local serverLoadedTime = tick()

-- Commandments Loop
task.spawn(function()
    while task.wait(0.3) do
        if Options.AutoCollectCommandments and Options.AutoCollectCommandments.Value then
            -- Ждём минимум 4 секунды после реконнекта для загрузки сетевой части
            if (tick() - serverLoadedTime) < 4 then
                CommandmentStatusParagraph:SetDesc("Status: Waiting for server sync (BridgeNet2)...")
                continue
            end

            local target = nil
            
            -- Проверяем сначала специальную папку World12Commandments
            local folder = workspace:FindFirstChild("World12Commandments")
            local searchArea = folder and folder:GetDescendants() or workspace:GetDescendants()

            for _, obj in ipairs(searchArea) do
                if isCommandmentModel(obj) then
                    target = obj
                    break
                end
            end

            if target and target.Parent then
                CommandmentStatusParagraph:SetDesc("Status: Collecting " .. target.Name)
                collectCommandment(target)
                task.wait(0.3)
            else
                CommandmentStatusParagraph:SetDesc("Status: No Commandments found. Hopping...")
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
Fluent:Notify({ Title = "Anime Astral", Content = "Loaded v1.3.3!", Duration = 4 })
SaveManager:LoadAutoloadConfig()
