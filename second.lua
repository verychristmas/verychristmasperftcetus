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
local LocalPlayer = Players.LocalPlayer

local function getRootPart()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
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
-- SERVER HOP & ITEM LOGIC
-- ══════════════════════════════════════════════════════════════

local HOP_HISTORY_FILE = "AnimeAstralHopHistory.json"
local COOLDOWN_TIME = 1800
local serverHistory = {}

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
    if statusCallback then statusCallback("Searching for new server...") end
    local placeId = game.PlaceId
    local currentJobId = game.JobId
    local cursor = ""
    local foundServer = false
    local req = httpRequest

    if not req then return end

    while not foundServer do
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
                        game:GetService("TeleportService"):TeleportToPlaceInstance(placeId, randomServer.id, LocalPlayer)
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
        task.wait(0.5)
    end
end

local function interactWithPrompt(prompt)
    if not prompt then return end
    pcall(function()
        prompt.RequiresLineOfSight = false
        prompt.MaxActivationDistance = 9999
        prompt.HoldDuration = 0
    end)

    if typeof(fireproximityprompt) == "function" then
        pcall(fireproximityprompt, prompt)
    else
        pcall(function()
            if prompt.InputHoldBegan then
                prompt:InputHoldBegan()
                task.wait(0.02)
                if prompt.InputHoldEnded then prompt:InputHoldEnded() end
            else
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.wait(0.02)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            end
        end)
    end
end

local function collectTarget(targetObj)
    if not targetObj or not targetObj.Parent then return false end
    local rootPart = getRootPart()
    if not rootPart then return false end

    local prompt = targetObj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt then return false end

    local targetCFrame
    if targetObj:IsA("Model") then
        local part = targetObj:FindFirstChildWhichIsA("BasePart", true)
        targetCFrame = part and part.CFrame or targetObj:GetPivot()
    elseif targetObj:IsA("BasePart") then
        targetCFrame = targetObj.CFrame
    end

    if not targetCFrame then return false end

    rootPart.CFrame = targetCFrame + Vector3.new(0, 2, 0)
    rootPart.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.1)

    interactWithPrompt(prompt)
    return true
end

-- ══════════════════════════════════════════════════════════════
-- SEARCH HELPERS
-- ══════════════════════════════════════════════════════════════

local COMMANDMENT_NAMES = {
    "faith", "pacifism", "piety", "purity", "repose", 
    "retience", "reticence", "selflessness", "truth", "commandment"
}

local function isCommandmentModel(obj)
    if not obj then return false end
    local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt then return false end

    local nameLower = obj.Name:lower()
    for _, name in ipairs(COMMANDMENT_NAMES) do
        if nameLower:find(name) then return true end
    end

    if obj.Parent then
        local parentLower = obj.Parent.Name:lower()
        for _, name in ipairs(COMMANDMENT_NAMES) do
            if parentLower:find(name) then return true end
        end
    end

    -- Проверка BillboardGui / TextLabel внутри модели
    local textLabel = obj:FindFirstChildWhichIsA("TextLabel", true)
    if textLabel and textLabel.Text then
        local txt = textLabel.Text:lower()
        for _, name in ipairs(COMMANDMENT_NAMES) do
            if txt:find(name) then return true end
        end
    end

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
    SubTitle = "Perfectus",
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

-- Changelog
Tabs.Changelog:AddParagraph({ Title = "Update Log", Content = "- Added Commandments Auto Collect & Server Hop\n- Optimized prompt collection" })

-- Feedback UI
local BugSection = Tabs.Feedback:AddSection("Bug report")
local BugInput = BugSection:AddInput("BugInput", { Title = "Submit", Placeholder = "Describe the bug..." })
BugSection:AddButton({ Title = "Send bug report", Callback = function() SendFeedback("bug", BugInput.Value) end })

-- Ball / Crow Tab (ОРИГИНАЛЬНАЯ)
Tabs.BallCrow:AddSection("Auto Collect Special Items")
Tabs.BallCrow:AddToggle("AutoCollectBall", { Title = "Auto Collect Ball", Default = false })
Tabs.BallCrow:AddToggle("AutoBallServerHop", { Title = "Auto Server Hop (Ball)", Default = false })
local BallStatusParagraph = Tabs.BallCrow:AddParagraph({ Title = "Status", Content = "Waiting for activation..." })

Tabs.BallCrow:AddToggle("AutoCollectCrow", { Title = "Auto Collect Crow", Default = false })
Tabs.BallCrow:AddToggle("AutoCrowServerHop", { Title = "Auto Server Hop (Crow)", Default = false })

-- Commandments Tab (НОВАЯ ВКЛАДКА)
Tabs.Commandments:AddSection("Auto Collect Commandments")
Tabs.Commandments:AddToggle("AutoCollectCommandments", { Title = "Auto Collect Commandments", Default = false })
Tabs.Commandments:AddToggle("AutoCommandmentServerHop", { Title = "Auto Server Hop (Commandments)", Default = false })
local CommandmentStatusParagraph = Tabs.Commandments:AddParagraph({ Title = "Status", Content = "Waiting for activation..." })

-- ══════════════════════════════════════════════════════════════
-- MAIN LOOPS
-- ══════════════════════════════════════════════════════════════

-- Логика Ball / Crow (Оригинальная)
task.spawn(function()
    while task.wait(0.5) do
        if Options.AutoCollectBall and Options.AutoCollectBall.Value then
            local found = false
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj.Name:lower():find("ball") and obj:FindFirstChildWhichIsA("ProximityPrompt", true) then
                    found = true
                    BallStatusParagraph:SetDesc("Status: Collecting Ball (" .. obj.Name .. ")")
                    collectTarget(obj)
                    task.wait(0.5)
                    break
                end
            end
            if not found then
                BallStatusParagraph:SetDesc("Status: No Ball found on this server.")
                if Options.AutoBallServerHop and Options.AutoBallServerHop.Value then
                    genericServerHop(function(msg) BallStatusParagraph:SetDesc("Status: " .. msg) end)
                end
            end
        end

        if Options.AutoCollectCrow and Options.AutoCollectCrow.Value then
            local found = false
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj.Name:lower():find("crow") and obj:FindFirstChildWhichIsA("ProximityPrompt", true) then
                    found = true
                    BallStatusParagraph:SetDesc("Status: Collecting Crow (" .. obj.Name .. ")")
                    collectTarget(obj)
                    task.wait(0.5)
                    break
                end
            end
            if not found then
                BallStatusParagraph:SetDesc("Status: No Crow found on this server.")
                if Options.AutoCrowServerHop and Options.AutoCrowServerHop.Value then
                    genericServerHop(function(msg) BallStatusParagraph:SetDesc("Status: " .. msg) end)
                end
            end
        end
    end
end)

-- Логика Commandments (Новая)
task.spawn(function()
    while task.wait(0.5) do
        if Options.AutoCollectCommandments and Options.AutoCollectCommandments.Value then
            local found = false
            for _, obj in ipairs(workspace:GetDescendants()) do
                if isCommandmentModel(obj) then
                    found = true
                    CommandmentStatusParagraph:SetDesc("Status: Collecting Commandment (" .. obj.Name .. ")")
                    collectTarget(obj)
                    task.wait(0.5)
                    break
                end
            end

            if not found then
                CommandmentStatusParagraph:SetDesc("Status: No Commandments found on this server.")
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

Window:SelectTab(1)
Fluent:Notify({ Title = "Anime Astral", Content = "Script updated with Commandments tab!", Duration = 4 })
SaveManager:LoadAutoloadConfig()
