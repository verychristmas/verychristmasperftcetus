local function collectCommandment(targetObj)
    -- Если объекта нет — сразу выходим, ничего не телепортируем!
    if not targetObj or not targetObj.Parent then return false end
    
    local char = getCharacter()
    local rootPart = getRootPart()
    if not char or not rootPart then return false end

    -- Находим точные координаты
    local targetCFrame
    if targetObj:IsA("Model") then
        local part = targetObj:FindFirstChildWhichIsA("BasePart", true)
        targetCFrame = part and part.CFrame or targetObj:GetPivot()
    elseif targetObj:IsA("BasePart") then
        targetCFrame = targetObj.CFrame
    end

    if not targetCFrame then return false end

    -- Телепортируем персонажа на предмет
    pcall(function()
        char:PivotTo(targetCFrame)
        rootPart.AssemblyLinearVelocity = Vector3.zero
    end)

    -- Быстрый сбор
    local prompt = targetObj:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        pcall(function()
            prompt.RequiresLineOfSight = false
            prompt.MaxActivationDistance = 9999
            prompt.HoldDuration = 0
        end)

        if typeof(fireproximityprompt) == "function" then
            pcall(fireproximityprompt, prompt)
        else
            pcall(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.wait(0.02)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            end)
        end
    end

    local targetPart = targetObj:IsA("BasePart") and targetObj or targetObj:FindFirstChildWhichIsA("BasePart", true)
    if targetPart and typeof(firetouchinterest) == "function" then
        pcall(function()
            firetouchinterest(rootPart, targetPart, 0)
            task.wait(0.02)
            firetouchinterest(rootPart, targetPart, 1)
        end)
    end

    return true
end
