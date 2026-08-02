repeat task.wait() until game:IsLoaded()

local getgenv = getgenv or function() return _G end
local genv = getgenv()
local currentSession = tostring(game.PlaceId) .. "_" .. tostring(game.JobId)

if genv.AnimeAstralExecuted and genv.AnimeAstralSession == currentSession then
    return
end

genv.AnimeAstralExecuted = true
genv.AnimeAstralSession = currentSession

-- ══════════════════════════════════════════════════════════════
-- TARGET BALLS LIST (ФИЛЬТР СФЕР)
-- ══════════════════════════════════════════════════════════════

local TARGET_BALL_NAMES = {
    ["Truth"] = true,
    ["Retience"] = true,
    ["Repose"] = true,
    ["Purity"] = true,
    ["Pacifism"] = true,
}

local function isTargetBall(obj)
    if not obj then return false end
    if TARGET_BALL_NAMES[obj.Name] then return true end
    if obj.Parent and TARGET_BALL_NAMES[obj.Parent.Name] then return true end
    return false
end

-- ══════════════════════════════════════════════════════════════
-- SERVICES
-- ══════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

-- ══════════════════════════════════════════════════════════════
-- FEEDBACK CONFIG & HANDLER
-- ══════════════════════════════════════════════════════════════

local ENDPOINT = "https://plua.vercel.app/api/l/B9CcLtGyEFcnTVz7b2gt/feedback"
local httpRequest = (syn and syn.request) or (http and http.request) or http_request
    or (fluxus and fluxus.request) or request

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
        if not sent and res then
            pcall(function() err = HttpService:JSONDecode(res.Body).error end)
        end
        Fluent:Notify({
            Title = "Feedback",
            Content = sent and "Sent — thank you!" or (err or "Could not reach the server."),
            Duration = 4,
        })
    end)
end

-- ══════════════════════════════════════════════════════════════
-- BALL / CROW HANDLER
-- ══════════════════════════════════════════════════════════════

local BALL_HISTORY_FILE = "BallHopHistory.json"
local BALL_COOLDOWN_TIME = 1800
local ballServerHistory = {}

pcall(function()
    if isfile and isfile(BALL_HISTORY_FILE) then
        local fileData = readfile(BALL_HISTORY_FILE)
        if fileData and fileData ~= "" then
            local decoded = HttpService:JSONDecode(fileData)
            if type(decoded) == "table" then ballServerHistory = decoded end
        end
    end
end)

local function saveBallHistory()
    if writefile then
        pcall(function()
            writefile(BALL_HISTORY_FILE, HttpService:JSONEncode(ballServerHistory))
        end)
    end
end

local function cleanBallHistory()
    local currentTime = os.time()
    for jobId, visitTime in pairs(ballServerHistory) do
        if type(visitTime) == "number" and (currentTime - visitTime > BALL_COOLDOWN_TIME) then
            ballServerHistory[jobId] = nil
        end
    end
    saveBallHistory()
end

local function ballServerHop(statusCallback)
    if statusCallback then statusCallback("Searching for new server...") end
    local placeId = game.PlaceId
    local currentJobId = game.JobId
    cleanBallHistory()

    local cursor = ""
    local foundServer = false
    local req = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

    if not req then
        if statusCallback then statusCallback("Executor lacks HTTP request support") end
        return
    end

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
                        local isOnCooldown = false
                        if ballServerHistory[server.id] and (os.time() - ballServerHistory[server.id]) < BALL_COOLDOWN_TIME then
                            isOnCooldown = true
                        end
                        if not isOnCooldown then
                            table.insert(validServers, server)
                        end
                    end
                end

                if #validServers > 0 then
                    local randomServer = validServers[math.random(1, #validServers)]
                    if statusCallback then statusCallback("Teleporting to server: " .. tostring(randomServer.id)) end
                    ballServerHistory[currentJobId] = os.time()
                    saveBallHistory()

                    pcall(function()
                        game:GetService("TeleportService"):TeleportToPlaceInstance(placeId, randomServer.id, LocalPlayer)
                    end)
                    foundServer = true
                    break
                end

                if not foundServer and data.nextPageCursor then
                    cursor = data.nextPageCursor
                elseif not foundServer and not data.nextPageCursor then
                    if statusCallback then statusCallback("Resetting server history & retrying...") end
                    ballServerHistory = {}
                    saveBallHistory()
                    break
                end
            end
        else
            break
        end
        task.wait(0.5)
    end
end

local function collectSingleBall(ballObject)
    if not ballObject or not ballObject.Parent then return false end
    if not isTargetBall(ballObject) then return false end

    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end

    local prompt = ballObject:FindFirstChild("BallClaimPrompt", true)
        or ballObject:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt then
        task.wait(0.5)
        prompt = ballObject:FindFirstChild("BallClaimPrompt", true)
            or ballObject:FindFirstChildWhichIsA("ProximityPrompt", true)
    end
    if not prompt then return false end

    local targetCFrame
    local promptParent = prompt.Parent
    if promptParent and promptParent:IsA("BasePart") then
        targetCFrame = promptParent.CFrame
    elseif ballObject:IsA("Model") then
        local part = ballObject:FindFirstChildWhichIsA("BasePart", true)
        targetCFrame = part and part.CFrame or ballObject:GetPivot()
    elseif ballObject:IsA("BasePart") then
        targetCFrame = ballObject.CFrame
    end

    if not targetCFrame then return false end

    local offset = targetCFrame.LookVector * 3 + Vector3.new(0, 2, 0)
    rootPart.CFrame = targetCFrame + offset
    rootPart.AssemblyLinearVelocity = Vector3.zero

    pcall(function()
        prompt.RequiresLineOfSight = false
        prompt.MaxActivationDistance = 9999
        prompt.HoldDuration = 0
    end)

    local collected = false
    for attempt = 1, 3 do
        if not ballObject.Parent then
            collected = true
            break
        end

        task.wait(0.1)

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

        local startCheck = tick()
        while ballObject.Parent and (tick() - startCheck < 0.5) do
            task.wait(0.05)
        end

        if not ballObject.Parent then
            collected = true
            break
        end
    end

    return collected
end

-- ══════════════════════════════════════════════════════════════
-- CROW (CORVO) HANDLER
-- ══════════════════════════════════════════════════════════════

local CROW_HISTORY_FILE = "CrowHopHistory.json"
local CROW_COOLDOWN_TIME = 1800
local crowServerHistory = {}

pcall(function()
    if isfile and isfile(CROW_HISTORY_FILE) then
        local fileData = readfile(CROW_HISTORY_FILE)
        if fileData and fileData ~= "" then
            local decoded = HttpService:JSONDecode(fileData)
            if type(decoded) == "table" then crowServerHistory = decoded end
        end
    end
end)

local function saveCrowHistory()
    if writefile then
        pcall(function()
            writefile(CROW_HISTORY_FILE, HttpService:JSONEncode(crowServerHistory))
        end)
    end
end

local function cleanCrowHistory()
    local currentTime = os.time()
    for jobId, visitTime in pairs(crowServerHistory) do
        if type(visitTime) == "number" and (currentTime - visitTime > CROW_COOLDOWN_TIME) then
            crowServerHistory[jobId] = nil
        end
    end
    saveCrowHistory()
end

local function crowServerHop(statusCallback)
    if statusCallback then statusCallback("Searching for new server...") end
    local placeId = game.PlaceId
    local currentJobId = game.JobId
    cleanCrowHistory()

    local cursor = ""
    local foundServer = false
    local req = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

    if not req then
        if statusCallback then statusCallback("Executor lacks HTTP request support") end
        return
    end

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
                        local isOnCooldown = false
                        if crowServerHistory[server.id] and (os.time() - crowServerHistory[server.id]) < CROW_COOLDOWN_TIME then
                            isOnCooldown = true
                        end
                        if not isOnCooldown then
                            table.insert(validServers, server)
                        end
                    end
                end

                if #validServers > 0 then
                    local randomServer = validServers[math.random(1, #validServers)]
                    if statusCallback then statusCallback("Teleporting to server: " .. tostring(randomServer.id)) end
                    crowServerHistory[currentJobId] = os.time()
                    saveCrowHistory()

                    pcall(function()
                        game:GetService("TeleportService"):TeleportToPlaceInstance(placeId, randomServer.id, LocalPlayer)
                    end)
                    foundServer = true
                    break
                end

                if not foundServer and data.nextPageCursor then
                    cursor = data.nextPageCursor
                elseif not foundServer and not data.nextPageCursor then
                    if statusCallback then statusCallback("Resetting server history & retrying...") end
                    crowServerHistory = {}
                    saveCrowHistory()
                    break
                end
            end
        else
            break
        end
        task.wait(0.5)
    end
end

local function collectSingleCrow(crowObject)
    if not crowObject or not crowObject.Parent then return false end
    if not isTargetBall(crowObject) then return false end

    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end

    local prompt = crowObject:FindFirstChild("CorvoClaimPrompt", true)
        or crowObject:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt then
        task.wait(0.5)
        prompt = crowObject:FindFirstChild("CorvoClaimPrompt", true)
            or crowObject:FindFirstChildWhichIsA("ProximityPrompt", true)
    end
    if not prompt then return false end

    local targetCFrame
    if crowObject:IsA("Model") then
        local part = crowObject:FindFirstChildWhichIsA("BasePart", true)
        targetCFrame = part and part.CFrame or crowObject:GetPivot()
    elseif crowObject:IsA("BasePart") then
        targetCFrame = crowObject.CFrame
    end

    if not targetCFrame then return false end

    rootPart.CFrame = targetCFrame + Vector3.new(0, 2, 0)
    rootPart.AssemblyLinearVelocity = Vector3.zero

    pcall(function()
        prompt.RequiresLineOfSight = false
        prompt.MaxActivationDistance = 9999
        prompt.HoldDuration = 0
    end)

    local collected = false
    for attempt = 1, 3 do
        if not crowObject.Parent then
            collected = true
            break
        end

        task.wait(0.1)

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

        local startCheck = tick()
        while crowObject.Parent and (tick() - startCheck < 0.5) do
            task.wait(0.05)
        end

        if not crowObject.Parent then
            collected = true
            break
        end
    end

    return collected
end

-- ══════════════════════════════════════════════════════════════
-- UI LIBRARY
-- ══════════════════════════════════════════════════════════════

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/perfectusmim1/Pluent/main/dist/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/perfectusmim1/Pluent/main/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/perfectusmim1/Pluent/main/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Anime Astral",
    SubTitle = "Perfectus",
    TabWidth = 160,
    Size = UDim2.fromOffset(500, 300),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
})

local Tabs = {
    Changelog = Window:AddTab({ Title = "Changelog", Icon = "file-text" }),
    Feedback = Window:AddTab({ Title = "Feedback", Icon = "message-square" }),
    Farm = Window:AddTab({ Title = "Farm", Icon = "crosshair" }),
    Main = Window:AddTab({ Title = "Fire City Dungeon", Icon = "swords" }),
    Gate = Window:AddTab({ Title = "Gate", Icon = "key" }),
    Trial = Window:AddTab({ Title = "Trial", Icon = "timer" }),
    Cursed = Window:AddTab({ Title = "Cursed Rush", Icon = "skull" }),
    Raids = Window:AddTab({ Title = "Raids", Icon = "landmark" }),
    Defense = Window:AddTab({ Title = "Defense", Icon = "shield" }),
    BallCrow = Window:AddTab({ Title = "Ball / Crow", Icon = "disc" }),
    Priority = Window:AddTab({ Title = "Priority", Icon = "star" }),
    Timing = Window:AddTab({ Title = "Timing", Icon = "clock" }),
    Position = Window:AddTab({ Title = "Position", Icon = "map-pin" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

local Options = Fluent.Options

-- ══════════════════════════════════════════════════════════════
-- SHARED STATE
-- ══════════════════════════════════════════════════════════════

local State = {
    currentMode = nil,
    enemiesFolder = nil,
    currentRoom = 0,
    currentWave = 0,
    currentTrialRoom = 0,
    wasIn = { Dungeon = false, Gate = false, TrialEasy = false, TrialMedium = false, TombRaid = false, SoulRaid = false, BeachDefense = false, CloverRaid = false, InfinityCastle = false, TitanDefense = false, TimelessRaid = false, CursedRush = false, KingCursesRush = false, NinjaRaid = false },
    hasLeft = { Dungeon = false, Gate = false, TrialEasy = false, TrialMedium = false, TombRaid = false, SoulRaid = false, BeachDefense = false, CloverRaid = false, InfinityCastle = false, TitanDefense = false, TimelessRaid = false, CursedRush = false, KingCursesRush = false, NinjaRaid = false },
    entryTime = { Dungeon = nil, Gate = nil, TrialEasy = nil, TrialMedium = nil, TombRaid = nil, SoulRaid = nil, BeachDefense = nil, CloverRaid = nil, InfinityCastle = nil, TitanDefense = nil, TimelessRaid = nil, CursedRush = nil, KingCursesRush = nil, NinjaRaid = nil },
    isReturning = false,
    priorities = { Dungeon = 1, Gate = 2, TrialEasy = 3, TrialMedium = 4, TombRaid = 5, SoulRaid = 6, BeachDefense = 7, CloverRaid = 8, InfinityCastle = 9, TitanDefense = 10, TimelessRaid = 11, CursedRush = 12, KingCursesRush = 13, NinjaRaid = 14 },
    canJoin = { Dungeon = false, Gate = false, TrialEasy = false, TrialMedium = false, TombRaid = false, SoulRaid = false, BeachDefense = false, CloverRaid = false, InfinityCastle = false, TitanDefense = false, TimelessRaid = false, CursedRush = false, KingCursesRush = false, NinjaRaid = false },
    isJoining = false,
}

local savedReturnWorld = nil
local savedReturnCFrame = nil
local FarmHeightValue = 6

-- ══════════════════════════════════════════════════════════════
-- UI ELEMENTS
-- ══════════════════════════════════════════════════════════════

-- Changelog Tab
Tabs.Changelog:AddParagraph({
    Title = "Version 1.1",
    Content = "--- Fixed ---\n" ..
              "• Fixed remotes not working on Xeno and similar low-UNC executors.\n" ..
              "• Fixed Gate not joining automatically.\n" ..
              "• Added filtering for special Balls (Truth, Retience, Repose, Purity, Pacifism) & Auto Server Hop."
})

-- Feedback Tab
local BugSection = Tabs.Feedback:AddSection("Bug report")
local BugInput = BugSection:AddInput("BugInput", {
    Title = "Submit",
    Placeholder = "Describe the bug...",
})
BugSection:AddButton({
    Title = "Send bug report",
    Callback = function() SendFeedback("bug", BugInput.Value) end,
})

local SuggestSection = Tabs.Feedback:AddSection("Suggestion")
local SuggestInput = SuggestSection:AddInput("SuggestInput", {
    Title = "Got an idea?",
    Placeholder = "Describe your suggestion...",
})
SuggestSection:AddButton({
    Title = "Send suggestion",
    Callback = function() SendFeedback("suggestion", SuggestInput.Value) end,
})

-- Ball / Crow Tab
local SectionBall = Tabs.BallCrow:AddSection("Auto Collect Special Ball")
Tabs.BallCrow:AddToggle("AutoCollectBall", { Title = "Auto Collect Ball", Default = false })
Tabs.BallCrow:AddToggle("AutoBallServerHop", { Title = "Auto Server Hop (Ball)", Default = false })

local BallStatusParagraph = Tabs.BallCrow:AddParagraph({
    Title = "Ball Collector Status",
    Content = "Status: Idle\nTargeting: Truth, Retience, Repose, Purity, Pacifism"
})

local SectionCrow = Tabs.BallCrow:AddSection("Auto Collect Special Crow")
Tabs.BallCrow:AddToggle("AutoCollectCrow", { Title = "Auto Collect Crow", Default = false })
Tabs.BallCrow:AddToggle("AutoCrowServerHop", { Title = "Auto Server Hop (Crow)", Default = false })

local CrowStatusParagraph = Tabs.BallCrow:AddParagraph({
    Title = "Crow Collector Status",
    Content = "Status: Idle\nTargeting: Truth, Retience, Repose, Purity, Pacifism"
})

-- Dungeon Tab
Tabs.Main:AddToggle("AutoDungeon", { Title = "Auto Dungeon", Default = false })
Tabs.Main:AddToggle("AutoLeave", { Title = "Auto Leave", Default = false })
Tabs.Main:AddSlider("LeaveRoom", { Title = "Leave Room", Min = 1, Max = 50, Default = 50, Rounding = 0.1 })

-- Trial Tab
local SectionTrialEasy = Tabs.Trial:AddSection("Time Trial Easy")
Tabs.Trial:AddToggle("AutoTrialEasy", { Title = "Auto Trial", Default = false })
Tabs.Trial:AddToggle("AutoLeaveTrialEasy", { Title = "Auto Leave", Default = false })
Tabs.Trial:AddSlider("LeaveTrialEasyRoom", { Title = "Leave Room", Min = 1, Max = 50, Default = 50, Rounding = 0.1 })

local SectionTrialMedium = Tabs.Trial:AddSection("Time Trial Medium")
Tabs.Trial:AddToggle("AutoTrialMedium", { Title = "Auto Trial", Default = false })
Tabs.Trial:AddToggle("AutoLeaveTrialMedium", { Title = "Auto Leave", Default = false })
Tabs.Trial:AddSlider("LeaveTrialMediumRoom", { Title = "Leave Room", Min = 1, Max = 50, Default = 50, Rounding = 0.1 })

-- Gate Tab
local GATE_RANK_VALUES = { "E", "D", "C", "B", "A" }
Tabs.Gate:AddToggle("AutoGate", { Title = "Auto Gate", Default = false })
Tabs.Gate:AddDropdown("GateRanks", { Title = "Select Ranks", Values = GATE_RANK_VALUES, Multi = true, Default = {} })
Tabs.Gate:AddToggle("AutoLeaveGate", { Title = "Auto Leave Gate", Default = false })
Tabs.Gate:AddSlider("LeaveGateWave", { Title = "Leave Wave", Min = 1, Max = 50, Default = 50, Rounding = 0.1 })

-- Tomb Raid Tab
local SectionTombRaid = Tabs.Raids:AddSection("Tomb Raid")
Tabs.Raids:AddToggle("AutoTombRaid", { Title = "Auto Tomb Raid", Default = false })
Tabs.Raids:AddToggle("AutoLeaveTombRaid", { Title = "Auto Leave", Default = false })
Tabs.Raids:AddSlider("LeaveTombRaidWave", { Title = "Leave Wave", Min = 1, Max = 100, Default = 50, Rounding = 0.1 })

-- Soul Raid Tab
local SectionSoulRaid = Tabs.Raids:AddSection("Soul Raid")
Tabs.Raids:AddToggle("AutoSoulRaid", { Title = "Auto Soul Raid", Default = false })
Tabs.Raids:AddToggle("AutoLeaveSoulRaid", { Title = "Auto Leave", Default = false })
Tabs.Raids:AddSlider("LeaveSoulRaidWave", { Title = "Leave Wave", Min = 1, Max = 60, Default = 50, Rounding = 0.1 })

-- Clover Raid
local SectionCloverRaid = Tabs.Raids:AddSection("Clover Raid")
Tabs.Raids:AddToggle("AutoCloverRaid", { Title = "Auto Clover Raid", Default = false })
Tabs.Raids:AddToggle("AutoLeaveCloverRaid", { Title = "Auto Leave", Default = false })
Tabs.Raids:AddSlider("LeaveCloverRaidWave", { Title = "Leave Wave", Min = 1, Max = 50, Default = 50, Rounding = 0.1 })

-- Infinity Castle
local SectionInfinityCastle = Tabs.Raids:AddSection("Infinity Castle")
Tabs.Raids:AddToggle("AutoInfinityCastle", { Title = "Auto Infinity Castle", Default = false })
Tabs.Raids:AddToggle("AutoLeaveInfinityCastle", { Title = "Auto Leave", Default = false })
Tabs.Raids:AddSlider("LeaveInfinityCastleWave", { Title = "Leave Wave", Min = 1, Max = 30, Default = 30, Rounding = 0.1 })

-- Timeless Raid
local SectionTimelessRaid = Tabs.Raids:AddSection("Timeless Raid")
Tabs.Raids:AddToggle("AutoTimelessRaid", { Title = "Auto Timeless Raid", Default = false })
Tabs.Raids:AddToggle("AutoLeaveTimelessRaid", { Title = "Auto Leave", Default = false })
Tabs.Raids:AddSlider("LeaveTimelessRaidWave", { Title = "Leave Wave", Min = 1, Max = 50, Default = 50, Rounding = 0.1 })

-- Ninja Raid
local SectionNinjaRaid = Tabs.Raids:AddSection("Ninja Raid")
Tabs.Raids:AddToggle("AutoNinjaRaid", { Title = "Auto Ninja Raid", Default = false })
Tabs.Raids:AddToggle("AutoLeaveNinjaRaid", { Title = "Auto Leave", Default = false })
Tabs.Raids:AddSlider("LeaveNinjaRaidWave", { Title = "Leave Wave", Min = 1, Max = 100, Default = 100, Rounding = 0.1 })

-- Beach Defense
local SectionBeachDefense = Tabs.Defense:AddSection("Beach Defense")
Tabs.Defense:AddToggle("AutoBeachDefense", { Title = "Auto Beach Defense", Default = false })
Tabs.Defense:AddToggle("AutoLeaveBeachDefense", { Title = "Auto Leave", Default = false })
Tabs.Defense:AddSlider("LeaveBeachDefenseWave", { Title = "Leave Wave", Min = 1, Max = 100, Default = 100, Rounding = 0.1 })

-- Titan Defense
local SectionTitanDefense = Tabs.Defense:AddSection("Titan Defense")
Tabs.Defense:AddToggle("AutoTitanDefense", { Title = "Auto Titan Defense", Default = false })
Tabs.Defense:AddToggle("AutoLeaveTitanDefense", { Title = "Auto Leave", Default = false })
Tabs.Defense:AddSlider("LeaveTitanDefenseWave", { Title = "Leave Wave", Min = 1, Max = 100, Default = 100, Rounding = 0.1 })

-- Farm Tab
Tabs.Farm:AddToggle("AutoFarm", { Title = "Auto Farm", Default = false })
local EnemyDropdown = Tabs.Farm:AddDropdown("EnemyDropdown", { Title = "Select Enemies", Values = { "--" }, Multi = true, Default = {} })
Tabs.Farm:AddButton({ Title = "Refresh Enemies", Description = "", Callback = function() pcall(refreshEnemies) end })
Tabs.Farm:AddToggle("PerfectPosition", { Title = "Perfect Position", Default = false })
Tabs.Farm:AddToggle("FastTeleportFarm", { Title = "Fast Teleport Farm", Default = false })
Tabs.Farm:AddToggle("FixedHeightFarm", { Title = "Fixed Height (Hover Farm)", Default = false })
Tabs.Farm:AddSlider("FarmHeight", { Title = "Farm Height", Description = "", Min = 1, Max = 50, Default = 6, Rounding = 0.5, Callback = function(v) FarmHeightValue = v end })

-- Cursed Tab
Tabs.Cursed:AddToggle("AutoFarmCursed", { Title = "Auto Farm", Default = false })
Tabs.Cursed:AddToggle("AutoCollectSukuna", { Title = "Auto Collect Fingers", Default = false })

local SectionCursedRush = Tabs.Cursed:AddSection("Cursed Rush")
Tabs.Cursed:AddToggle("AutoCursedRush", { Title = "Auto Cursed Rush", Default = false })
Tabs.Cursed:AddToggle("AutoLeaveCursedRush", { Title = "Auto Leave", Default = false })
Tabs.Cursed:AddSlider("LeaveCursedRushWave", { Title = "Leave Wave", Min = 1, Max = 300, Default = 300, Rounding = 0 })

local SectionKingCursesRush = Tabs.Cursed:AddSection("King of Curses Rush")
Tabs.Cursed:AddToggle("AutoKingCursesRush", { Title = "Auto King of Curses Rush", Default = false })
Tabs.Cursed:AddToggle("AutoLeaveKingCursesRush", { Title = "Auto Leave", Default = false })
Tabs.Cursed:AddSlider("LeaveKingCursesRushWave", { Title = "Leave Wave", Min = 1, Max = 300, Default = 300, Rounding = 0 })

-- Position Tab
local PositionParagraph = Tabs.Position:AddParagraph({ Title = "Saved Position", Content = "World: nil\nPosition: nil" })

Tabs.Position:AddButton({
    Title = "Save Current Position",
    Callback = function()
        local visibility = LocalPlayer:GetAttribute("VisibilityContext")
        local root = getRootPart()
        local currentWorld = "Unknown"
        local currentPosStr = "nil"

        if visibility then
            local w = string.match(visibility, "^World:(%d+)$")
            if not w then w = string.match(visibility, "World(%d+)") end
            if not w then w = visibility end
            savedReturnWorld = w
            currentWorld = w
        end

        if root then
            savedReturnCFrame = root.CFrame
            local pos = root.Position
            currentPosStr = string.format("%.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z)
        end

        saveReturnData()
        PositionParagraph:SetDesc(string.format("World: %s\nPosition: %s", tostring(currentWorld), currentPosStr))
        Fluent:Notify({ Title = "Position Saved", Content = "Saved returning position successfully.", Duration = 3 })
    end
})

Tabs.Position:AddToggle("AutoReturnDungeon", { Title = "Auto Return (Dungeon)", Default = false })
Tabs.Position:AddToggle("AutoReturnGate", { Title = "Auto Return (Gate)", Default = false })
Tabs.Position:AddToggle("AutoReturnTrialEasy", { Title = "Auto Return (Trial Easy)", Default = false })
Tabs.Position:AddToggle("AutoReturnTrialMedium", { Title = "Auto Return (Trial Medium)", Default = false })

-- ══════════════════════════════════════════════════════════════
-- UTILITY FUNCTIONS
-- ══════════════════════════════════════════════════════════════

local function selectedMultiValues(value)
    local selected = {}
    local seen = {}
    if type(value) ~= "table" then return selected end
    for k, v in pairs(value) do
        local val = nil
        if type(v) == "string" then
            val = v
        elseif type(k) == "string" and v == true then
            val = k
        end
        if val and not seen[val] then
            seen[val] = true
            table.insert(selected, val)
        end
    end
    table.sort(selected)
    return selected
end

function getRootPart()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getObjectCFrame(obj)
    if not obj then return nil end
    if obj:IsA("Model") then
        local ok, pivot = pcall(function() return obj:GetPivot() end)
        if ok then return pivot end
    end
    if obj:IsA("BasePart") then return obj.CFrame end
    local part = obj:FindFirstChild("HumanoidRootPart", true) or obj:FindFirstChildWhichIsA("BasePart", true)
    if part then return part.CFrame end
    return nil
end

local function isEnemyAlive(enemy)
    if not enemy or not enemy.Parent then return false end
    local dead = enemy:GetAttribute("EnemyDead")
    if dead == true then return false end
    local hr = enemy:GetAttribute("HealthReal")
    if type(hr) == "number" then return hr > 0 end
    local hum = enemy:FindFirstChildOfClass("Humanoid") or enemy:FindFirstChild("Humanoid", true)
    if hum then return hum.Health > 0 end
    return true
end

local function getEnemyHealth(enemy)
    if not enemy then return 0 end
    local hr = enemy:GetAttribute("HealthReal")
    if type(hr) == "number" then return hr end
    local hum = enemy:FindFirstChildOfClass("Humanoid") or enemy:FindFirstChild("Humanoid", true)
    if hum then return hum.Health end
    return 0
end

local function getCurrentWorldId()
    local vc = LocalPlayer:GetAttribute("VisibilityContext")
    if vc then return tostring(vc):match("World:(%d+)") end
    return nil
end

local function activeEnemiesFolder()
    local worlds = workspace:FindFirstChild("Worlds")
    if not worlds then return nil end

    local cw = getCurrentWorldId()
    if cw then
        local w = worlds:FindFirstChild(cw)
        if w then return w:FindFirstChild("Enemies") end
        return nil
    end

    local root = getRootPart()
    if root then
        local closestWorld = nil
        local minDistance = math.huge
        for _, w in ipairs(worlds:GetChildren()) do
            local teleporter = w:FindFirstChild("Teleporter") or w:FindFirstChild("Void")
            if teleporter then
                local dist = (root.Position - teleporter.Position).Magnitude
                if dist < minDistance then
                    minDistance = dist
                    closestWorld = w
                end
            end
        end
        if closestWorld and minDistance < 5000 then
            return closestWorld:FindFirstChild("Enemies")
        end
    end
    return nil
end

local function setDropdownValues(dropdown, values)
    if not dropdown then return end
    local ok = false
    if dropdown.SetValues then ok = pcall(function() dropdown:SetValues(values) end) end
    if not ok then pcall(function() dropdown.Values = values end) end
end

function refreshEnemies()
    local enemyLabels = {}
    local folder = activeEnemiesFolder()
    if not folder then return end

    local found = {}
    for _, enemy in ipairs(folder:GetChildren()) do
        local cf = getObjectCFrame(enemy)
        if cf then
            local etype = enemy:GetAttribute("EnemyType") or "Unknown"
            local label = enemy.Name .. " - " .. tostring(etype)
            if not found[label] then
                found[label] = true
                table.insert(enemyLabels, label)
            end
        end
    end

    table.sort(enemyLabels)
    if #enemyLabels == 0 then enemyLabels = { "--" } end
    setDropdownValues(EnemyDropdown, enemyLabels)
end

-- ══════════════════════════════════════════════════════════════
-- BRIDGE & REMOTES
-- ══════════════════════════════════════════════════════════════

local function getBridgeFolder() return ReplicatedStorage:FindFirstChild("BridgeNet2") end
local function getBridgeEvent() return getBridgeFolder() and getBridgeFolder():FindFirstChild("dataRemoteEvent") end

function buildBridgeIdentifierMap()
    local map = {}
    local folder = getBridgeFolder()

    if folder then
        for name, value in pairs(folder:GetAttributes()) do
            if type(value) == "string" then map[name] = value end
        end
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("StringValue") and map[child.Name] == nil then
                map[child.Name] = child.Value
            end
        end
    end

    if typeof(getgc) == "function" then
        local ok, gc = pcall(getgc, true)
        if ok and type(gc) == "table" then
            for _, obj in ipairs(gc) do
                if type(obj) == "table" then
                    pcall(function()
                        local total = 0
                        for k, v in pairs(obj) do
                            if type(k) ~= "string" or type(v) ~= "string" then error("skip") end
                            total = total + 1
                            if total > 300 then error("skip") end
                        end
                        if total < 2 then error("skip") end

                        local nameToId = true
                        for k, v in pairs(obj) do
                            if not (#v <= 3 and #k > 3) then nameToId = false end
                        end

                        if nameToId then
                            for k, v in pairs(obj) do
                                if map[k] == nil then map[k] = v end
                            end
                        end
                    end)
                end
            end
        end
    end

    return map
end

local cachedBridgeMap = nil
local function resolveBridgeId(bridgeName)
    if cachedBridgeMap and cachedBridgeMap[bridgeName] then
        return cachedBridgeMap[bridgeName]
    end
    if not cachedBridgeMap then
        cachedBridgeMap = buildBridgeIdentifierMap()
    end
    return cachedBridgeMap[bridgeName]
end

-- ══════════════════════════════════════════════════════════════
-- BALL & CROW COLLECTOR LOOP WITH FILTER & HOP
-- ══════════════════════════════════════════════════════════════

task.spawn(function()
    while task.wait(1) do
        -- Ball Loop
        if Options.AutoCollectBall and Options.AutoCollectBall.Value then
            local foundBall = false
            for _, obj in ipairs(workspace:GetDescendants()) do
                if isTargetBall(obj) then
                    local isBall = obj:FindFirstChild("BallClaimPrompt", true) or obj.Name:lower():find("ball")
                    if isBall then
                        foundBall = true
                        BallStatusParagraph:SetDesc("Status: Collecting " .. obj.Name)
                        collectSingleBall(obj)
                    end
                end
            end

            if not foundBall then
                BallStatusParagraph:SetDesc("Status: No target Balls found on this server.")
                if Options.AutoBallServerHop and Options.AutoBallServerHop.Value then
                    ballServerHop(function(msg)
                        BallStatusParagraph:SetDesc("Status: " .. msg)
                    end)
                end
            end
        end

        -- Crow Loop
        if Options.AutoCollectCrow and Options.AutoCollectCrow.Value then
            local foundCrow = false
            for _, obj in ipairs(workspace:GetDescendants()) do
                if isTargetBall(obj) then
                    local isCrow = obj:FindFirstChild("CorvoClaimPrompt", true) or obj.Name:lower():find("corvo") or obj.Name:lower():find("crow")
                    if isCrow then
                        foundCrow = true
                        CrowStatusParagraph:SetDesc("Status: Collecting " .. obj.Name)
                        collectSingleCrow(obj)
                    end
                end
            end

            if not foundCrow then
                CrowStatusParagraph:SetDesc("Status: No target Crows found on this server.")
                if Options.AutoCrowServerHop and Options.AutoCrowServerHop.Value then
                    crowServerHop(function(msg)
                        CrowStatusParagraph:SetDesc("Status: " .. msg)
                    end)
                end
            end
        end
    end
end)

-- ══════════════════════════════════════════════════════════════
-- SAVE/LOAD CONFIG AT END
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
Fluent:Notify({
    Title = "Anime Astral",
    Content = "Script loaded successfully with Special Ball/Crow filters!",
    Duration = 5,
})
SaveManager:LoadAutoloadConfig()
